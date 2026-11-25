"""Use separate native release processes to challenge the profile lease."""

import argparse
import json
from pathlib import Path
import sys
import tempfile

sys.dont_write_bytecode = True
from verify_wp06_link import launch, peer_env, wait_for_host
from verify_wp06_session import stop


MODE = {"journal": "delete", "locking": "exclusive", "sqlite": "3.51.0", "synchronous": 3}


def observation(process, log):
    code = process.wait(timeout=8)
    lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
    prefix = "WP13_PROFILE "
    for line in lines:
        if line.startswith(prefix):
            return {"exit": code, **json.loads(line[len(prefix):])}
    raise RuntimeError(f"No profile result in {log}")


def verify(exe, evidence, scratch):
    ready, release, profiles = (scratch / name for name in ("ready", "release", "profiles"))
    results = {}
    holder_log = evidence / "owner.log"
    holder = launch([exe], holder_log, peer_env(scratch / "owner"), profiles, "alpha", ready, release)
    try:
        wait_for_host(holder, ready)
        for name, identity in (("same-profile", "alpha"), ("separate-profile", "beta")):
            log = evidence / f"{name}.log"
            peer = launch([exe], log, peer_env(scratch / name), profiles, identity)
            try:
                results[name] = observation(peer, log)
            finally:
                stop(peer)
        release.touch()
        results["owner"] = observation(holder, holder_log)
        reopened_log = evidence / "reopened.log"
        reopened = launch([exe], reopened_log, peer_env(scratch / "reopened"), profiles, "alpha")
        try:
            results["reopened"] = observation(reopened, reopened_log)
        finally:
            stop(reopened)

        crash_ready = scratch / "crash-ready"
        crashed = launch([exe], evidence / "crash-owner.log", peer_env(scratch / "crash-owner"), profiles,
                         "alpha", crash_ready, scratch / "unreleased")
        try:
            wait_for_host(crashed, crash_ready)
            crashed.kill()
            results["closed_by_os"] = crashed.wait(timeout=5)
        finally:
            stop(crashed)
        recovery_log = evidence / "after-crash.log"
        recovered = launch([exe], recovery_log, peer_env(scratch / "after-crash"), profiles, "alpha")
        try:
            results["after-crash"] = observation(recovered, recovery_log)
        finally:
            stop(recovered)
    finally:
        stop(holder)
    opened = (results[name] for name in ("owner", "separate-profile", "reopened", "after-crash"))
    contender = results["same-profile"]
    passed = (all(item["exit"] == 0 and item["open"] == "OPENED" and item["mode"] == MODE and item["closed"]
                  for item in opened) and contender["exit"] == 0 and contender["open"] == "BUSY"
              and not contender["mode"] and contender["closed"] and results["closed_by_os"] != 0)
    return {"passed": passed, "peers": results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("exe", type=Path)
    parser.add_argument("evidence", type=Path)
    options = parser.parse_args()
    evidence = options.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="agip-wp13-profile-") as directory:
        result = verify(options.exe.resolve(strict=True), evidence, Path(directory))
    text = json.dumps(result, indent=2, sort_keys=True)
    (evidence / "receipt.json").write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
