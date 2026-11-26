"""Reconcile durable grants across two authenticated native sessions and a host switch."""

import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
from verify_wp06_link import ephemeral_port, launch, peer_env, wait_for_host
from verify_wp06_session import enroll, keygen, receipt, stop


def exchange_receipt(log):
    prefix = "WP23_EXCHANGE "
    lines = log.read_text(encoding="utf-8").splitlines()
    return next(json.loads(line[len(prefix):]) for line in lines if line.startswith(prefix))


def run_session(exe, evidence, scratch, host_identity, guest_identity, reverse):
    host, guest = scratch / "host", scratch / "guest"
    host.mkdir(parents=True)
    guest.mkdir()
    shutil.copyfile(host_identity / "host.crt", host / "host.crt")
    shutil.copyfile(guest_identity / "peer.pub", host / "paired-guest.pub")
    if not reverse:
        shutil.copyfile(host_identity / "peer.pub", guest / "paired-issuer.pub")
    fingerprint = enroll(exe, scratch, evidence)
    host_env = dict(peer_env(host / "session"), AGIP_WP23_PROFILES=str(host_identity / "profiles"),
                    AGIP_WP23_REVERSED=str(int(reverse)), AGIP_WP06_BIND="127.0.0.1")
    guest_env = dict(peer_env(guest / "session"), AGIP_WP23_PROFILES=str(guest_identity / "profiles"),
                     AGIP_WP23_REVERSED=str(int(reverse)), AGIP_WP06_BIND="127.0.0.1")
    if not reverse:
        host_env["AGIP_WP23_ORIGINAL_PEER"] = str(host / "paired-guest.pub")
        guest_env["AGIP_WP23_ORIGINAL_PEER"] = str(guest / "paired-issuer.pub")
    ready, offered, invitation = host / "ready", host / "offered", guest / "invitation"
    host_log, guest_log = evidence / "host.log", evidence / "guest.log"
    port = ephemeral_port()
    children = []
    try:
        server = launch([exe], host_log, host_env, "host", port, host / "host.crt", host_identity / "peer.key",
                        host / "paired-guest.pub", offered, ready, "paired")
        children.append(server)
        wait_for_host(server, ready)
        shutil.copyfile(offered, invitation)
        client = launch([exe], guest_log, guest_env, "guest", port, guest, fingerprint,
                        guest_identity / "peer.key", invitation, "-", "paired")
        children.append(client)
        exits = [client.wait(timeout=10), server.wait(timeout=10)]
        natives = [receipt(host_log), receipt(guest_log)]
        assert exits == [0, 0], (scratch.name, exits, natives)
        assert natives[0]["admitted"] == 1 and natives[0]["departures"] == 1
        assert all(side["passed"] and side["rejected"] == side["lost"] == 0 for side in natives)
        assert all(error["host_drain_site"] for error in natives[0]["diagnostics"])
        assert not natives[1]["diagnostics"]
        return {"host": exchange_receipt(host_log), "guest": exchange_receipt(guest_log)}
    finally:
        for child in children:
            stop(child)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("exe", type=Path)
    parser.add_argument("evidence", type=Path)
    options = parser.parse_args()
    exe, evidence = options.exe.resolve(strict=True), options.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="agip-wp23-exchange-") as root:
        scratch = Path(root)
        alice, bob = scratch / "alice", scratch / "bob"
        for identity in (alice, bob):
            keygen(exe, identity, evidence, identity.name)
        report = {}
        for label, host, guest, reverse in (("original", alice, bob, False), ("reversed", bob, alice, True)):
            session = evidence / label
            session.mkdir()
            report[label] = run_session(exe, session, scratch / label, host, guest, reverse)
    assert report == {
        "original": {
            "host": {"reversed": False, "profile": "alice", "balance": 0, "pending": 2,
                     "generation": 3, "received": [], "passed": True},
            "guest": {"reversed": False, "profile": "bob", "balance": 17, "pending": 0,
                      "generation": 2, "received": [0], "passed": True},
        },
        "reversed": {
            "host": {"reversed": True, "profile": "bob", "balance": 40, "pending": 0,
                     "generation": 3, "received": [5, 5, 1, 0], "passed": True},
            "guest": {"reversed": True, "profile": "alice", "balance": 0, "pending": 0,
                      "generation": 5, "received": [0, 1, 0], "passed": True},
        },
    }, report
    body = json.dumps(report, indent=2, sort_keys=True) + "\n"
    (evidence / "receipt.json").write_text(body, encoding="utf-8")
    print(body)


if __name__ == "__main__":
    main()
