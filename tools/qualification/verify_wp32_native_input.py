"""Verify reliable combat input against the encounter on two Windows Dev processes."""

import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
from verify_wp06_link import ephemeral_port, launch, peer_env, wait_for_host
from verify_wp06_session import enroll, keygen, receipt, stop

PREFIX = "WP32_NATIVE_INPUT "


def facts(path):
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith(PREFIX):
            return json.loads(line[len(PREFIX):])
    raise RuntimeError(f"Encounter input receipt missing from {path.name}")


def verify(exe, evidence, scratch):
    for role in ("host", "guest"):
        keygen(exe, scratch / role, evidence, role)
    host, guest = scratch / "host", scratch / "guest"
    shutil.copyfile(guest / "guest.pub", host / "guest.pub")
    fingerprint = enroll(exe, scratch, evidence)
    port = ephemeral_port()
    ready, offered = host / "ready", host / "offered"
    copied = guest / "offered"
    host_log, guest_log = evidence / "host.log", evidence / "guest.log"
    server = launch([exe], host_log, dict(peer_env(host / "run"), AGIP_WP06_BIND="127.0.0.1"),
                    "host", port, host / "host.crt", host / "host.key", host / "guest.pub", offered, ready, "paired")
    clients = [server]
    try:
        wait_for_host(server, ready)
        shutil.copyfile(offered, copied)
        clients.append(launch([exe], guest_log, peer_env(guest / "run"),
                              "guest", port, guest, fingerprint, guest / "guest.key", copied, "-", "paired"))
        exits = [client.wait(timeout=10) for client in clients]
    finally:
        for client in clients:
            stop(client)
    host_result, guest_result = map(facts, (host_log, guest_log))
    host_session, guest_session = map(receipt, (host_log, guest_log))
    expected = {"barrier": 18, "cast_tick": 1, "guest_owned_hit": True, "movement_ack": 1,
                "new_movement_ack": 2, "stale_refused": True, "cooldown_refused": True}
    passed = (exits == [0, 0] and host_session["passed"] and guest_session["passed"]
              and host_session["admitted"] == 1 and host_session["departures"] == 1
              and host_session["lost"] == host_session["rejected"] == 0
              and all(item["host_drain_site"] for item in host_session["diagnostics"])
              and not guest_session["diagnostics"] and host_result == expected
              and guest_result == {"first_ack": 1, "last_ack": 2})
    return {"passed": passed, "exits": exits, "host": host_result, "guest": guest_result,
            "native_sessions": [host_session, guest_session]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("exe", type=Path)
    parser.add_argument("evidence", type=Path)
    options = parser.parse_args()
    evidence = options.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="agip-wp32-native-input-") as directory:
        result = verify(options.exe.resolve(strict=True), evidence, Path(directory))
    body = json.dumps(result, indent=2, sort_keys=True)
    (evidence / "receipt.json").write_text(body + "\n", encoding="utf-8")
    print(body)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
