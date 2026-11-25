"""Exercise authenticated admission through separate native release peers on loopback."""

import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile

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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--client-close", action="store_true", help="Include the direct guest-side ENet close diagnostic arm")
    args = parser.parse_args()
    exe, logs = args.release.resolve(strict=True), args.output.resolve()
    logs.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="agip-wp06-session-") as temporary:
        secrets = Path(temporary)
        keygen(exe, secrets / "host", logs, "host")
        keygen(exe, secrets / "guest", logs, "guest")
        shutil.copyfile(secrets / "host" / "host.crt", secrets / "guest" / "paired.crt")
        shutil.copyfile(secrets / "guest" / "guest.pub", secrets / "host" / "guest.pub")
        modes = ("paired", "early", "client-close") if args.client_close else ("paired", "early")
        report = {mode: exchange(exe, secrets, logs, mode) for mode in modes}
    (logs / "summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({mode: result["passed"] for mode, result in report.items()}))
    if not all(result["passed"] for result in report.values()):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
