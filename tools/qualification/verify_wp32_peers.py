"""Run both roles through a rendered starter encounter over native loopback."""

import argparse
import json
from math import dist
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
from verify_wp06_link import ephemeral_port, peer_env, wait_for_host
from verify_wp06_session import enroll, keygen, receipt, stop

PREFIX = "WP32_PEER "
FAMILIES = {"sword": "W01", "bow": "W02"}
MANUALS = {"sword": "H01.siphon_pulse", "bow": "H03.harmonic_burst"}
OBSERVABLE = {"player", "radius", "enemies", "warnings", "manual_ready", "goal", "passage"}
POSITION_TOLERANCE = 1e-9
POSITION_FIELDS = {"player", "actors", "warnings"}


def rendered(exe, log, environment, *args):
    return subprocess.Popen(
        [exe, "--resolution", "960x540", "--log-file", log, "--", *map(str, args)],
        env=environment, creationflags=subprocess.CREATE_NO_WINDOW,
    )


def facts(log):
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith(PREFIX):
            return json.loads(line[len(PREFIX):])
    raise RuntimeError(f"Peer encounter receipt missing from {log}")


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def same_point(source, received):
    return dist(source, received) <= POSITION_TOLERANCE


def same_projection(source, received):
    if source is None or source.keys() != received.keys():
        return False
    for field in source.keys() - POSITION_FIELDS:
        if source[field] != received[field]:
            return False
    # The receipt compares decoded double positions with the source before JSON
    # encoding. The payload digest still has to match exactly.
    if not same_point(source["player"], received["player"]):
        return False
    if source["actors"].keys() != received["actors"].keys():
        return False
    for actor, (position, hp) in source["actors"].items():
        guest_position, guest_hp = received["actors"][actor]
        if hp != guest_hp or not same_point(position, guest_position):
            return False
    if len(source["warnings"]) != len(received["warnings"]):
        return False
    for warning, guest_warning in zip(source["warnings"], received["warnings"]):
        if (warning[:2] != guest_warning[:2] or warning[3] != guest_warning[3]
                or not same_point(warning[2], guest_warning[2])):
            return False
    return True


def measure(evidence, host_facts, guest_facts):
    host = rows(evidence / "host" / "peer.jsonl")
    guest = rows(evidence / "guest" / "peer.jsonl")
    sent = {row["hash"]: row["sent"] for row in host if "sent" in row}
    accepted = [row for row in guest if "received" in row]
    matched = sum(same_projection(sent.get(row["hash"]), row["received"]) for row in accepted)
    ticks = {row["tick"]: row for row in host if "outcomes" in row}
    displacements = sum(event.get("pushed", False) for row in ticks.values() for event in row["outcomes"])
    damage = {seat: set() for seat in ("host", "guest")}
    for row in ticks.values():
        for event in row["outcomes"]:
            if event.get("damage") and event.get("owner") in damage:
                damage[event["owner"]].add(event["family"])
    avoided = set()
    for row in accepted:
        observation = row["received"]
        for impact, began, center, radius in observation["warnings"]:
            if impact - observation["tick"] < 10 or impact not in ticks:
                continue
            if dist(observation["player"], center) <= radius + 14 and dist(ticks[impact]["seat_poses"][1], center) > radius + 14:
                avoided.add((began, impact, tuple(center)))
    local = {seat: rows(evidence / seat / "input.jsonl") for seat in ("host", "guest")}
    inputs = {seat: sorted({row["action"] for row in data if "action" in row}) for seat, data in local.items()}
    visible_only = all(set(row["visible"]) == OBSERVABLE for data in local.values() for row in data if "visible" in row)
    captures = all((evidence / seat / image).is_file()
                   for seat in ("host", "guest") for image in ("warning.png", "end.png"))
    presets = {"host": host_facts["preset"], "guest": guest_facts["preset"]}
    mechanic_coverage = all(FAMILIES[presets[seat]] in damage[seat] and MANUALS[presets[seat]] in damage[seat]
                            and {"move_axes", "manual"} <= set(inputs[seat]) for seat in damage)
    replays = [row["received"] for row in accepted]
    ended_together = bool(replays) and replays[-1]["cleared"] and (
        replays[-1]["tick"] == guest_facts["closed_tick"] == host_facts["closed_tick"])
    passed = (matched == len(accepted) and captures and visible_only and ended_together and len(ticks) >= 240
              and len(accepted) >= 75 and guest_facts["last_move_ack"] >= 8
              and mechanic_coverage and bool(avoided) and displacements > 0)
    return {"passed": passed, "projected_matches": matched, "visible_only": visible_only,
            "source_ticks": len(ticks), "captures": captures, "ended_together": ended_together,
            "families": {seat: sorted(families) for seat, families in damage.items()}, "inputs": inputs,
            "guest_avoided": len(avoided), "displacements": displacements}


def verify(exe, evidence, scratch, preset):
    for seat in ("host", "guest"):
        keygen(exe, scratch / seat, evidence, seat)
        (evidence / seat).mkdir()
    host, guest = scratch / "host", scratch / "guest"
    shutil.copyfile(guest / "guest.pub", host / "guest.pub")
    fingerprint = enroll(exe, scratch, evidence)
    port = ephemeral_port()
    ready, offered = host / "ready", host / "offered"
    copied = guest / "offered"
    policy = Path(__file__).resolve().parent.parent / "pilot" / "wp32_policy.py"
    host_log, guest_log = evidence / "host.log", evidence / "guest.log"
    host_env = dict(peer_env(host / "run"), AGIP_WP06_BIND="127.0.0.1", AGIP_WP32_PRESET=preset)
    guest_preset = "bow" if preset == "sword" else "sword"
    guest_env = dict(peer_env(guest / "run"), AGIP_WP06_BIND="127.0.0.1", AGIP_WP32_PRESET=guest_preset)

    def options(seat):
        return json.dumps({"python": sys.executable, "policy": str(policy), "output": str(evidence / seat)})

    server = rendered(exe, host_log, host_env, "host", port, host / "host.crt", host / "host.key",
                      host / "guest.pub", offered, ready, "paired", options("host"))
    children = [server]
    try:
        wait_for_host(server, ready)
        shutil.copyfile(offered, copied)
        children.append(rendered(exe, guest_log, guest_env, "guest", port, guest, fingerprint, guest / "guest.key",
                                 copied, "-", "paired", options("guest")))
        exits = [child.wait(timeout=45) for child in children]
    finally:
        for child in children:
            stop(child)
    host_facts, guest_facts = map(facts, (host_log, guest_log))
    host_session, guest_session = map(receipt, (host_log, guest_log))
    result = measure(evidence, host_facts, guest_facts)
    passed = (exits == [0, 0] and result["passed"] and host_facts["passed"] and guest_facts["passed"]
              and host_facts["profile"] != guest_facts["profile"] and host_session["admitted"] == 1
              and host_session["departures"] == 1 and host_session["lost"] == host_session["rejected"] == 0
              and all(item["host_drain_site"] for item in host_session["diagnostics"])
              and not guest_session["diagnostics"])
    return {"passed": passed, "exits": exits, "host": host_facts, "guest": guest_facts, "measurements": result,
            "native_sessions": [host_session, guest_session]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("exe", type=Path)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--host", choices=FAMILIES, action="append")
    options = parser.parse_args()
    evidence = options.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    receipts = {}
    for preset in options.host or FAMILIES:
        output = evidence / f"host-{preset}"
        output.mkdir()
        with tempfile.TemporaryDirectory(prefix="agip-wp32-peers-") as directory:
            receipts[preset] = verify(options.exe.resolve(strict=True), output, Path(directory), preset)
    passed = all(arm["passed"] for arm in receipts.values())
    body = json.dumps({"passed": passed, "arms": receipts}, indent=2, sort_keys=True)
    (evidence / "receipt.json").write_text(body + "\n", encoding="utf-8")
    print(body)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
