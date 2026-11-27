"""Verify a scoped passage with two separate Windows Dev release processes."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
from verify_wp06_link import ephemeral_port, launch, peer_env, wait_for_host
from verify_wp06_session import enroll, keygen, receipt, stop


def passage_facts(path, marker="WP25_NATIVE "):
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith(marker):
            return json.loads(line[len(marker):])
    raise RuntimeError(f"Missing {marker.strip()} receipt in {path.name}")


def run_peers(exe, evidence, secrets, fingerprint, gateway, world, rendered, walk_return):
    host, guest = secrets / "host", secrets / "guest"
    port = ephemeral_port()
    offered, ready = host / "offered", host / "ready"
    copied = guest / "offered"
    host_log, guest_log = evidence / "host.log", evidence / "guest.log"
    children = []
    try:
        host_env, guest_env = (dict(peer_env(role / "run"), AGIP_WP06_BIND="127.0.0.1") for role in (host, guest))
        if world:
            for role, environment in (("host", host_env), ("guest", guest_env)):
                captures = evidence / f"{role}-scope"
                captures.mkdir()
                environment["AGIP_WP18_CAPTURE"] = str(captures)
        server = launch([exe], host_log, host_env, "host", port, host / "host.crt", host / "host.key",
                        host / "guest.pub", offered, ready, "paired", rendered=rendered)
        children.append(server)
        wait_for_host(server, ready)
        shutil.copyfile(offered, copied)
        visitor = launch([exe], guest_log, guest_env, "guest", port, guest, fingerprint,
                         guest / "guest.key", copied, "-", "paired", rendered=rendered)
        children.append(visitor)
        exits = [child.wait(timeout=32 if walk_return else 10) for child in children]
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
        if world:
            expected_guest["visible"].append("spawn/7:arrival/1")
    passed = (exits == [0, 0] and host_session["passed"] and guest_session["passed"]
              and host_session["admitted"] == 1 and host_session["departures"] == 1
              and host_session["lost"] == host_session["rejected"] == 0
              and all(item["host_drain_site"] for item in host_session["diagnostics"])
              and not guest_session["diagnostics"] and host_facts == expected_host and guest_facts == expected_guest)
    result = {"passed": passed, "exits": exits, "host": host_facts, "guest": guest_facts,
              "native_sessions": [host_session, guest_session]}
    if world:
        host_world, guest_world = (passage_facts(path, "WP18_SPLIT ") for path in (host_log, guest_log))
        trace = evidence / "host-scope" / "world.json"
        result["world"] = {"host": host_world, "guest": guest_world}
        result["passed"] = (passed and host_world["arrived_with_resident"] and host_world["spawned_at_arrival"]
                            and host_world["host_filtered"] and host_world["archive_unviewed"]
                            and host_world["draws"] == 1 and guest_world["resident_hp"] == 20
                            and guest_world["resident_hidden_before_entry"] and guest_world["archive_hidden"]
                            and host_world["resident_x"] == guest_world["resident_x"]
                            and host_world["faction_kills"] == [["archive/legion", 1, "archive/wildborn"]]
                            and hashlib.sha256(trace.read_bytes()).hexdigest() == host_world["digest"]
                            and (not rendered or all((evidence / f"{role}-scope" / "view.png").is_file()
                                                     for role in ("host", "guest"))))
    if walk_return:
        host_return, guest_return = (passage_facts(path, "WP18_EXIT ") for path in (host_log, guest_log))
        result["return"] = {"host": host_return, "guest": guest_return}
        end = host_return.get("exit_tick", 0)
        trace = evidence / "host-scope" / "return.json"
        result["passed"] = (result["passed"] and guest_return.get("returned", False)
                            and end >= 760 and guest_return["exit_tick"] == end
                            and len(host_return["legs"]) == 3 and host_return["legs"] == guest_return["legs"]
                            and host_return["final_ack"] == guest_return["final_ack"] == 5
                            and host_return["final_tick"] == guest_return["final_tick"] == end + 60
                            and host_return["spawned_while_empty"] == end + 30
                            and host_return["reentry_tick"] == guest_return["reentry_tick"] == end + 61
                            and host_return["reentry_hp"] == guest_return["reentry_hp"]
                            and host_return["stale_exit_refused"] and guest_return["exit_cell_retained"]
                            and host_return["resident_retained"] and host_return["later_resident"]
                            and hashlib.sha256(trace.read_bytes()).hexdigest() == host_return["world_digest"]
                            and (not rendered or (evidence / "guest-scope" / "overworld-return.png").is_file()))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("exe", type=Path)
    parser.add_argument("evidence", type=Path)
    target = parser.add_mutually_exclusive_group()
    target.add_argument("--gateway", action="store_true")
    target.add_argument("--world", action="store_true")
    target.add_argument("--walk-return", action="store_true")
    parser.add_argument("--rendered", action="store_true")
    options = parser.parse_args()
    if options.rendered and not (options.world or options.walk_return):
        parser.error("--rendered requires --world or --walk-return")
    exe, evidence = options.exe.resolve(strict=True), options.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="agip-wp25-passage-") as directory:
        secrets = Path(directory)
        for role in ("host", "guest"):
            keygen(exe, secrets / role, evidence, role)
        shutil.copyfile(secrets / "guest" / "guest.pub", secrets / "host" / "guest.pub")
        fingerprint = enroll(exe, secrets, evidence)
        result = run_peers(exe, evidence, secrets, fingerprint, options.gateway, options.world or options.walk_return,
                           options.rendered, options.walk_return)
    body = json.dumps(result, indent=2, sort_keys=True)
    (evidence / "receipt.json").write_text(body + "\n", encoding="utf-8")
    print(body)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
