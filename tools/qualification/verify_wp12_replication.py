"""Test the exported WP12 fixture with separate authenticated native peers."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
from verify_wp06_link import ephemeral_port, launch, peer_env, wait_for_host
from verify_wp06_session import enroll, keygen, receipt, stop


def replication_receipt(log):
    prefix = "WP12_RESULT "
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith(prefix):
            return json.loads(line[len(prefix):])
    raise RuntimeError(f"No WP12 receipt in {log}")


def exchange(exe, evidence, secrets, fingerprint, rendered, large, sealed_vault):
    host, guest = secrets / "host", secrets / "guest"
    port = ephemeral_port()
    offered, ready, copied = host / "offered", host / "ready", guest / "offered"
    host_log, guest_log = evidence / "host.log", evidence / "guest.log"
    host_env = peer_env(host / "session")
    host_env["AGIP_WP12_LARGE_VIEW"] = "1" if large else "0"
    host_env["AGIP_WP12_SEALED_VAULT"] = "1" if sealed_vault else "0"
    server = launch([exe], host_log, host_env, "host", port,
                    host / "host.crt", host / "host.key", host / "guest.pub", offered, ready, "paired")
    client = None
    try:
        wait_for_host(server, ready)
        shutil.copyfile(offered, copied)
        env = peer_env(guest / "session")
        env["AGIP_WP12_LARGE_VIEW"] = host_env["AGIP_WP12_LARGE_VIEW"]
        env["AGIP_WP12_SEALED_VAULT"] = host_env["AGIP_WP12_SEALED_VAULT"]
        env["AGIP_WP12_CAPTURE"] = str(evidence) if rendered else ""
        args = ["guest", str(port), str(guest), fingerprint, str(guest / "guest.key"), str(copied), "-", "paired"]
        if rendered:
            client = subprocess.Popen([str(exe), "--audio-driver", "Dummy", "--resolution", "960x540", "--max-fps", "120",
                                       "--log-file", str(guest_log), "--", *args], env=env)
        else:
            client = launch([exe], guest_log, env, *args)
        exits = [client.wait(timeout=12), server.wait(timeout=12)]
        host_result, guest_result = map(replication_receipt, (host_log, guest_log))
        host_errors = receipt(host_log)["diagnostics"]
        guest_errors = receipt(guest_log)["diagnostics"]
        captured = not rendered or all(guest_result.get(name) and (evidence / name).is_file()
                                       for name in ("wall.png", "active-cue.png", "forced.png"))
        lock_cleared = (guest_result.get("pending_before_lock") == 1 and guest_result.get("pending_during_lock") == 0
                        and guest_result.get("unlock_preserved_pose") is True)
        disclosure_complete = (not large or (host_result.get("baseline_parts", 0) > 1
                               and host_result.get("view_parts", 0) > 1
                               and guest_result.get("disclosed_actor_count") == 221
                               and guest_result.get("view_bytes", 0) > 4094))
        impact = host_result.get("authority_impact_unix_ms", 0)
        received = guest_result.get("warning_received_unix_ms", 0)
        activated = guest_result.get("warning_activation_unix_ms", 0)
        displayed = guest_result.get("warning_rendered_unix_ms", 0)
        timed_threat = (0 < received < activated < impact and host_result.get("authority_impact_tick") == 30
                        and guest_result.get("observed_warning_tick") == 20 and guest_result.get("observed_impact_tick") == 30
                        and host_result.get("contact_at_obstructed_pose") is True
                        and host_result.get("contact_after_forced_motion") is False
                        and (not rendered or activated <= displayed < impact))
        expected_x = 7.0 if sealed_vault else 9.0
        landed = (abs(host_result.get("vault_landing_x", 0) - expected_x) < 0.000001
                  and abs(guest_result.get("forced_snap_draw_x", 0) - expected_x) < 0.000001
                  and host_result.get("vault_sealed_contacts") == int(sealed_vault))
        return {"passed": not any(exits) and host_result["passed"] and guest_result["passed"] and captured and lock_cleared
                and disclosure_complete and timed_threat and landed
                and all(error["host_drain_site"] for error in host_errors) and not guest_errors,
                "exits": exits, "rendered": rendered, "large": large, "host": host_result, "guest": guest_result,
                "sealed_vault": sealed_vault,
                "receipt_to_authority_impact_ms": impact - received, "activation_to_authority_impact_ms": impact - activated,
                "rendered_warning_to_impact_ms": impact - displayed if rendered else None,
                "host_diagnostics": host_errors, "guest_diagnostics": guest_errors}
    finally:
        if client is not None:
            stop(client)
        stop(server)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("exe", type=Path)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--rendered", action="store_true")
    parser.add_argument("--large", action="store_true")
    parser.add_argument("--sealed-vault", action="store_true")
    options = parser.parse_args()
    exe, evidence = options.exe.resolve(strict=True), options.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="agip-wp12-peers-") as directory:
        secrets = Path(directory)
        for role in ("host", "guest"):
            keygen(exe, secrets / role, evidence, role)
        shutil.copyfile(secrets / "guest" / "guest.pub", secrets / "host" / "guest.pub")
        fingerprint = enroll(exe, secrets, evidence)
        result = exchange(exe, evidence, secrets, fingerprint, options.rendered, options.large, options.sealed_vault)
    text = json.dumps(result, indent=2, sort_keys=True)
    (evidence / "receipt.json").write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
