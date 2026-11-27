"""Verify a scoped passage with two separate Windows Dev release processes."""

import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
from verify_wp06_link import ephemeral_port, launch, peer_env, wait_for_host
from verify_wp06_session import enroll, keygen, receipt, stop


def passage_facts(path):
    marker = "WP25_NATIVE "
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith(marker):
            return json.loads(line[len(marker):])
    raise RuntimeError(f"Missing passage receipt in {path.name}")


def run_peers(exe, evidence, secrets, fingerprint, gateway):
    host, guest = secrets / "host", secrets / "guest"
    port = ephemeral_port()
    offered, ready = host / "offered", host / "ready"
    copied = guest / "offered"
    host_log, guest_log = evidence / "host.log", evidence / "guest.log"
    children = []
    try:
        host_env, guest_env = (dict(peer_env(role / "run"), AGIP_WP06_BIND="127.0.0.1") for role in (host, guest))
        server = launch([exe], host_log, host_env, "host", port, host / "host.crt", host / "host.key",
                        host / "guest.pub", offered, ready, "paired")
        children.append(server)
        wait_for_host(server, ready)
        shutil.copyfile(offered, copied)
        visitor = launch([exe], guest_log, guest_env, "guest", port, guest, fingerprint,
                         guest / "guest.key", copied, "-", "paired")
        children.append(visitor)
        exits = [child.wait(timeout=10) for child in children]
    finally:
        for child in children:
            stop(child)
    host_facts, guest_facts = map(passage_facts, (host_log, guest_log))
    host_session, guest_session = map(receipt, (host_log, guest_log))
    if gateway:
        expected_host = {"arena_movement_ack": 2, "body_wait_preserved": True, "gated_before_rebaseline": True,
                         "generation": 1, "settled": 17, "stale_refused": True}
        expected_guest = {"arena_epoch": 3, "arena_movement_ack": 2, "arrival_tick": 90000,
                          "party": {"guest": "living", "host": "down"}, "visible": ["guest", "host"]}
    else:
        expected_host = {"crossed_tick": 1, "source_moved_one_unit": True, "stale_refused": True,
                         "guest_realm": "silent_garden", "host_realm": "overworld", "movement_ack": 2}
        expected_guest = {"arrival_realm": "silent_garden", "visible": ["guest"],
                          "party": {"guest": "living", "host": "living"},
                          "arrival_cell_seen": True, "movement_ack": 2}
    passed = (exits == [0, 0] and host_session["passed"] and guest_session["passed"]
              and host_session["admitted"] == 1 and host_session["departures"] == 1
              and host_session["lost"] == host_session["rejected"] == 0
              and all(item["host_drain_site"] for item in host_session["diagnostics"])
              and not guest_session["diagnostics"] and host_facts == expected_host and guest_facts == expected_guest)
    return {"passed": passed, "exits": exits, "host": host_facts, "guest": guest_facts,
            "native_sessions": [host_session, guest_session]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("exe", type=Path)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--gateway", action="store_true")
    options = parser.parse_args()
    exe, evidence = options.exe.resolve(strict=True), options.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="agip-wp25-passage-") as directory:
        secrets = Path(directory)
        for role in ("host", "guest"):
            keygen(exe, secrets / role, evidence, role)
        shutil.copyfile(secrets / "guest" / "guest.pub", secrets / "host" / "guest.pub")
        fingerprint = enroll(exe, secrets, evidence)
        result = run_peers(exe, evidence, secrets, fingerprint, options.gateway)
    body = json.dumps(result, indent=2, sort_keys=True)
    (evidence / "receipt.json").write_text(body + "\n", encoding="utf-8")
    print(body)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
