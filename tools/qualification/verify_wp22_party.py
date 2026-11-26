"""Check split encounter eligibility and guest reclaim on private native peers."""

import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
from verify_wp06_link import ephemeral_port, launch, peer_env, wait_for_host
from verify_wp06_session import enroll, keygen, receipt, stop, wait_for_signal


def party_receipt(path):
    prefix = "WP22_PARTY "
    for line in reversed(path.read_text(encoding="utf-8", errors="replace").splitlines()):
        if line.startswith(prefix):
            return json.loads(line[len(prefix):])
    raise RuntimeError(f"No WP22 party result in {path.name}")


def exchange(exe, evidence, secrets, fingerprint):
    host, guest = secrets / "host", secrets / "guest"
    port = ephemeral_port()
    offered, ready, lost = (host / name for name in ("offered", "ready", "lost"))
    copied, token, rotated, moved = (guest / name for name in ("offered", "prior", "rotated", "moved"))
    host_log, original_log, replacement_log = (
        evidence / f"{role}.log" for role in ("host", "original", "replacement")
    )
    children = []
    try:
        host_env = {**peer_env(host / "session"), "AGIP_WP06_BIND": "127.0.0.1"}
        server = launch([exe], host_log, host_env, "host", port, host / "host.crt", host / "host.key",
                        host / "guest.pub", offered, ready, "abrupt", lost)
        children.append(server)
        wait_for_host(server, ready)
        shutil.copyfile(offered, copied)
        original_env = {**peer_env(guest / "original"), "AGIP_WP06_BIND": "127.0.0.1"}
        original = launch([exe], original_log, original_env, "guest", port, guest, fingerprint,
                          guest / "guest.key", copied, "-", "abrupt", token, moved)
        children.append(original)
        wait_for_signal(original, moved, 6)
        original.kill()
        original_exit = original.wait(timeout=5)
        wait_for_signal(server, lost, 24)
        replacement_env = {**peer_env(guest / "replacement"), "AGIP_WP06_BIND": "127.0.0.1"}
        replacement = launch([exe], replacement_log, replacement_env, "guest", port, guest, fingerprint,
                             guest / "guest.key", token, "-", "reclaim", rotated)
        children.append(replacement)
        exits = [server.wait(timeout=16), replacement.wait(timeout=8)]
        host_result, guest_result = map(party_receipt, (host_log, replacement_log))
        host_session, guest_session = map(receipt, (host_log, replacement_log))
        credential_rotated = (token.is_file() and rotated.is_file() and len(token.read_bytes()) == 32
                              and len(rotated.read_bytes()) == 32 and token.read_bytes() != rotated.read_bytes())
        passed = (not any(exits) and original_exit != 0 and credential_rotated
                  and host_result["passed"] and guest_result["passed"]
                  and host_result["opened_profile"] == "wp22-host" and guest_result["opened_profile"] == "wp22-guest"
                  and host_result["host_local"] == ["host"] and host_result["guest_local_in_grace"] == ["guest"]
                  and host_result["outside"] and host_result["disconnected"]
                  and host_result["inclusive_x"] == host_result["return_x"] == host_result["stationary_x"] == 220.0
                  and host_result["host_frontier_tick"] == 4 and host_result["locked_hp_scale"] == 150
                  and len(host_result["host_frozen"]) == len(host_result["guest_frozen"]) == 3
                  and host_result["host_frozen"] != host_result["guest_frozen"]
                  and host_result["host_choice"] in host_result["host_frozen"] and host_result["guest_offer_preserved"]
                  and guest_result["realm"] == "observatory" and guest_result["visible_actor_ids"] == ["guest"]
                  and guest_result["party_status"] == {"host": "living", "guest": "living"}
                  and guest_result["level"] == 2 and guest_result["baseline_ack"] == 3
                  and guest_result["closed_ack"] == 4 and guest_result["authoritative_x"] == 219.0
                  and host_session["admitted"] == 2 and host_session["lost"] == 1
                  and host_session["departures"] == 1 and not host_session["rejected"]
                  and all(error["host_drain_site"] for error in host_session["diagnostics"])
                  and not guest_session["diagnostics"])
        return {"passed": passed, "exits": exits, "terminated_original_exit": original_exit,
                "credential_rotated": credential_rotated, "host": host_result, "guest": guest_result,
                "native_sessions": [host_session, guest_session]}
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
    with tempfile.TemporaryDirectory(prefix="agip-wp22-party-") as directory:
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
