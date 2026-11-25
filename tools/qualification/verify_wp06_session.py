"""Exercise authenticated admission through separate native release peers on loopback."""

import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile
import time

sys.dont_write_bytecode = True
from verify_wp06_link import ephemeral_port, launch, peer_env, wait_for_host


def keygen(exe, directory, logs, role):
    directory.mkdir()
    application = peer_env(directory / "keygen")
    process = launch([exe], logs / f"keygen-{role}.log", application, "keygen", role, directory)
    try:
        if process.wait(timeout=10) != 0:
            raise RuntimeError(f"Key generation failed for {role}")
    finally:
        stop(process)


def stop(child):
    if child.poll() is None:
        child.kill()
        child.wait(timeout=5)


def wait_for_signal(process, path, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline and process.poll() is None:
        if path.is_file() and path.read_bytes() == b"\x01":
            return
        time.sleep(0.025)
    raise RuntimeError(f"Fixture did not report {path.name}")


def receipt(path):
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    marker = "WP06_SESSION_RESULT "
    result = next(json.loads(line[len(marker):]) for line in lines if line.startswith(marker))
    diagnostics = []
    phase = "startup"
    for index, line in enumerate(lines):
        if line.startswith("WP06_SESSION_PHASE "):
            phase = line.split()[1]
        if "ERROR:" in line or "Unicode parsing error" in line:
            teardown = phase == "host-draining" and "godot_mbedtls_mutex_free" in "\n".join(lines[index:index + 3])
            diagnostics.append({"line": line, "phase": phase, "host_drain_site": teardown})
    result["diagnostics"] = diagnostics
    return result


def exchange(exe, secrets, logs, mode):
    host, guest = secrets / "host", secrets / "guest"
    host_env, guest_env = (peer_env(path / mode) for path in (host, guest))
    host_log, guest_log = (logs / f"{mode}-{role}.log" for role in ("host", "guest"))
    port = ephemeral_port()
    host_token, guest_token, ready = host / f"{mode}.token", guest / f"{mode}.token", host / f"{mode}.ready"
    children = []
    try:
        server = launch([exe], host_log, host_env, "host", port, host / "host.crt", host / "host.key",
                        host / "guest.pub", host_token, ready, mode)
        children.append(server)
        wait_for_host(server, ready)
        shutil.copyfile(host_token, guest_token)
        if mode == "wrong-invite":
            credential = bytearray(guest_token.read_bytes())
            credential[0] ^= 1
            guest_token.write_bytes(credential)
        client = launch([exe], guest_log, guest_env, "guest", port, guest / "paired.crt", "-",
                        guest / "guest.key", guest_token, "-", mode)
        children.append(client)
        codes = [client.wait(timeout=10), server.wait(timeout=10)]
        observations = [receipt(host_log), receipt(guest_log)]
        passed = not any(codes) and all(item["passed"] for item in observations)
        passed = passed and all(item["host_drain_site"] for item in observations[0]["diagnostics"])
        passed = passed and not observations[1]["diagnostics"]
        return {"passed": passed, "exits": codes, "peers": observations}
    finally:
        for child in children:
            stop(child)


def abrupt_reclaim(exe, secrets, logs, lose_acceptance):
    host, guest = secrets / "host", secrets / "guest"
    host_env, guest_env = (peer_env(path / "abrupt") for path in (host, guest))
    reclaim_env = peer_env(guest / "reclaim")
    host_log, lost_log, resumed_log = (logs / f"abrupt-{role}.log" for role in ("host", "guest", "resumed"))
    port = ephemeral_port()
    invitation, ready, lost = (host / name for name in ("abrupt.token", "abrupt.ready", "seat-lost"))
    copied_token, old_credential, new_credential, exchanged = (
        guest / name for name in ("abrupt.token", "prior.credential", "current.credential", "first-exchange")
    )
    children = []
    try:
        server = launch([exe], host_log, host_env, "host", port, host / "host.crt", host / "host.key",
                        host / "guest.pub", invitation, ready, "abrupt", lost)
        children.append(server)
        wait_for_host(server, ready)
        shutil.copyfile(invitation, copied_token)
        original = launch([exe], lost_log, guest_env, "guest", port, guest / "paired.crt", "-",
                          guest / "guest.key", copied_token, "-", "abrupt", old_credential, exchanged)
        children.append(original)
        wait_for_signal(original, exchanged, 5)
        if len(old_credential.read_bytes()) != 32:
            raise RuntimeError("The initial guest did not receive a reclaim credential")
        loss_start = time.monotonic()
        original.kill()
        original_exit = original.wait(timeout=5)
        wait_for_signal(server, lost, 40)
        detection_ms = round((time.monotonic() - loss_start) * 1000)
        abandoned = None
        abandoned_credential = guest / "unacked.credential"
        abandoned_log = logs / "abrupt-unacked.log"
        if lose_acceptance:
            acceptance = guest / "unacked-acceptance"
            abandoned = launch([exe], abandoned_log, peer_env(guest / "unacked"), "guest", port,
                               guest / "paired.crt", "-", guest / "guest.key", old_credential, "-", "unacked",
                               abandoned_credential, acceptance)
            children.append(abandoned)
            wait_for_signal(abandoned, acceptance, 5)
        returned = launch([exe], resumed_log, reclaim_env, "guest", port, guest / "paired.crt", "-",
                          guest / "guest.key", old_credential, "-", "reclaim", new_credential)
        children.append(returned)
        codes = [returned.wait(timeout=8), server.wait(timeout=8)]
        observations = [receipt(host_log), receipt(resumed_log)]
        rotated = new_credential.is_file() and len(new_credential.read_bytes()) == 32 and (
            new_credential.read_bytes() != old_credential.read_bytes()
        )
        if original_exit == 0:
            raise RuntimeError("Original guest exited normally before the abrupt fault")
        passed = rotated and not any(codes) and all(item["passed"] for item in observations)
        passed = passed and all(item["host_drain_site"] for item in observations[0]["diagnostics"])
        passed = passed and not observations[1]["diagnostics"]
        if abandoned is not None:
            abandoned_exit = abandoned.wait(timeout=5)
            fenced = receipt(abandoned_log)
            abandoned_token = abandoned_credential.read_bytes()
            passed = (passed and abandoned_exit == 0 and fenced["passed"] and not fenced["diagnostics"]
                      and len(abandoned_token) == 32 and abandoned_token != old_credential.read_bytes()
                      and abandoned_token != new_credential.read_bytes())
            observations.append(fenced)
        return {"passed": passed, "exits": codes, "terminated_peer_exit": original_exit,
                "loss_detection_ms": detection_ms, "credential_rotated": rotated,
                "unacknowledged_acceptance": lose_acceptance, "peers": observations}
    finally:
        for child in children:
            stop(child)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--client-close", action="store_true", help="Include the direct guest-side ENet close diagnostic arm")
    parser.add_argument("--abrupt-reclaim", action="store_true", help="Terminate an admitted guest and reclaim its seat")
    parser.add_argument("--lost-acceptance", action="store_true", help="Also leave the first reclaim acceptance unacknowledged")
    args = parser.parse_args()
    if args.lost_acceptance and not args.abrupt_reclaim:
        parser.error("--lost-acceptance requires --abrupt-reclaim")
    exe, logs = args.release.resolve(strict=True), args.output.resolve()
    logs.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="agip-wp06-session-") as temporary:
        secrets = Path(temporary)
        keygen(exe, secrets / "host", logs, "host")
        keygen(exe, secrets / "guest", logs, "guest")
        shutil.copyfile(secrets / "host" / "host.crt", secrets / "guest" / "paired.crt")
        shutil.copyfile(secrets / "guest" / "guest.pub", secrets / "host" / "guest.pub")
        modes = ("paired", "early", "wrong-invite", "client-close") if args.client_close else (
            "paired", "early", "wrong-invite"
        )
        report = {mode: exchange(exe, secrets, logs, mode) for mode in modes}
        if args.abrupt_reclaim:
            report["abrupt-reclaim"] = abrupt_reclaim(exe, secrets, logs, args.lost_acceptance)
    (logs / "summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({mode: result["passed"] for mode, result in report.items()}))
    if not all(result["passed"] for result in report.values()):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
