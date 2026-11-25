"""Exercise movement reclaim in a live host session across native processes."""

import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile
import time

sys.dont_write_bytecode = True
from verify_wp06_link import ephemeral_port, launch, peer_env, wait_for_host
from verify_wp06_session import enroll, keygen, receipt, stop, wait_for_signal


def reclaim_receipt(log):
    prefix = "WP12_RECLAIM "
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith(prefix):
            return json.loads(line[len(prefix):])
    raise RuntimeError(f"No WP12 reclaim result in {log.name}")


def exchange(exe, evidence, secrets, fingerprint):
    host, guest = secrets / "host", secrets / "guest"
    port = ephemeral_port()
    offered, ready, lost = (host / name for name in ("offered", "ready", "lost"))
    copied, prior, replacement, exchanged = (
        guest / name for name in ("offered", "prior.credential", "replacement.credential", "exchanged")
    )
    host_log, original_log, concurrent_log, replacement_log = (
        evidence / f"{role}.log" for role in ("host", "original", "concurrent", "replacement")
    )
    children = []
    try:
        server = launch([exe], host_log, peer_env(host / "session"), "host", port, host / "host.crt",
                        host / "host.key", host / "guest.pub", offered, ready, "abrupt", lost)
        children.append(server)
        wait_for_host(server, ready)
        shutil.copyfile(offered, copied)
        original = launch([exe], original_log, peer_env(guest / "original"), "guest", port, guest, fingerprint,
                          guest / "guest.key", copied, "-", "abrupt", prior, exchanged)
        children.append(original)
        wait_for_signal(original, exchanged, 6)
        concurrent = launch([exe], concurrent_log, peer_env(guest / "concurrent"), "guest", port, guest,
                            fingerprint, guest / "guest.key", prior, "-", "stale-credential")
        children.append(concurrent)
        concurrent_exit = concurrent.wait(timeout=8)
        original_live = original.poll() is None
        if not original_live:
            raise RuntimeError("The protected original controller exited during the concurrent reclaim attempt")
        loss_start = time.monotonic()
        original.kill()
        original_exit = original.wait(timeout=5)
        wait_for_signal(server, lost, 40)
        loss_ms = round((time.monotonic() - loss_start) * 1000)
        resumed = launch([exe], replacement_log, peer_env(guest / "replacement"), "guest", port, guest,
                         fingerprint, guest / "guest.key", prior, "-", "reclaim", replacement)
        children.append(resumed)
        exits = [concurrent_exit, resumed.wait(timeout=9), server.wait(timeout=55)]
        host_result, concurrent_result, resumed_result = map(reclaim_receipt, (host_log, concurrent_log, replacement_log))
        host_session, concurrent_session, resumed_session = map(receipt, (host_log, concurrent_log, replacement_log))
        rotated = (prior.is_file() and replacement.is_file() and len(prior.read_bytes()) == 32
                   and len(replacement.read_bytes()) == 32 and prior.read_bytes() != replacement.read_bytes())
        passed = (not any(exits) and original_exit != 0 and original_live and rotated and lost.exists()
                  and all(result["passed"] for result in (host_result, concurrent_result, resumed_result))
                  and host_result.get("old_movement_fenced") is True and host_result.get("authoritative_x") == 2
                  and resumed_result.get("baseline_ack") == 1
                  and resumed_result.get("closed_ack") == 2 and host_session["admitted"] == 2
                  and host_session["rejected"] == 1 and host_session["lost"] == 1
                  and all(error["host_drain_site"] for error in host_session["diagnostics"])
                  and not concurrent_session["diagnostics"] and not resumed_session["diagnostics"])
        return {"passed": passed, "exits": exits, "terminated_original_exit": original_exit,
                "protected_original_controller": original_live, "loss_detection_ms": loss_ms,
                "credential_rotated": rotated, "host": host_result, "replacement": resumed_result,
                "native_sessions": [host_session, concurrent_session, resumed_session]}
    finally:
        for child in children:
            stop(child)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("exe", type=Path)
    parser.add_argument("evidence", type=Path)
    options = parser.parse_args()
    exe, evidence = options.exe.resolve(strict=True), options.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="agip-wp12-reclaim-") as directory:
        secrets = Path(directory)
        for role in ("host", "guest"):
            keygen(exe, secrets / role, evidence, role)
        shutil.copyfile(secrets / "guest" / "guest.pub", secrets / "host" / "guest.pub")
        fingerprint = enroll(exe, secrets, evidence)
        result = exchange(exe, evidence, secrets, fingerprint)
    body = json.dumps(result, indent=2, sort_keys=True)
    (evidence / "receipt.json").write_text(body + "\n", encoding="utf-8")
    print(body)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
