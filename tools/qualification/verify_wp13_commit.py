"""Kill the native profile writer on both sides of the economic commit."""

import argparse
import json
from pathlib import Path
import sys
import tempfile

sys.dont_write_bytecode = True
from verify_wp06_link import launch, peer_env, wait_for_host
from verify_wp06_session import stop


def read_receipt(process, log):
    code = process.wait(timeout=8)
    prefix = "WP13_COMMIT "
    lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
    receipt = next((json.loads(line[len(prefix):]) for line in lines if line.startswith(prefix)), None)
    errors = [line for line in lines if "ERROR:" in line]
    if code or receipt is None or any("database is locked" not in line for line in errors):
        raise RuntimeError(f"Unexpected exit or diagnostic in {log}")
    return receipt


def verify(exe, evidence, scratch):
    profiles = scratch / "profiles"

    def start(label, mode, *args):
        log = evidence / f"{label}.log"
        process = launch([exe], log, peer_env(scratch / label), profiles, mode, *args)
        return process, log

    def run(label, mode):
        process, log = start(label, mode)
        try:
            return read_receipt(process, log)
        finally:
            stop(process)

    observations = {"seed": run("seed", "seed")}
    for mode in ("before", "after"):
        ready = scratch / f"{mode}.ready"
        process, _ = start(f"kill-{mode}", mode, ready)
        try:
            wait_for_host(process, ready)
            observations[f"contender-{mode}"] = run(f"contender-{mode}", "inspect")
            process.kill()
            observations[f"exit-{mode}"] = process.wait(timeout=5)
        finally:
            stop(process)
        observations[f"reopen-{mode}"] = run(f"reopen-{mode}", "inspect")
    observations["replay"] = run("replay", "replay")

    before, after, replay = (observations[key] for key in ("reopen-before", "reopen-after", "replay"))
    passed = (observations["seed"].get("seed") == "COMMITTED"
              and all(observations[f"contender-{mode}"]["open"] == "BUSY" and observations[f"exit-{mode}"] != 0
                      for mode in ("before", "after"))
              and (before["balance"], before["head"], before["frontier"]) == (7, 1, 1)
              and before["pending_grants"] == ["seed-grant"] and before["before_receipt"] == "MISSING"
              and (after["balance"], after["head"], after["frontier"]) == (18, 2, 3)
              and after["pending_grants"] == ["after-grant", "seed-grant"] and after["after_receipt"] == "COMMITTED"
              and replay["replay"] == "DUPLICATE" and replay["conflict"] == "CONFLICT"
              and all(replay[key] == after[key] for key in ("balance", "head", "frontier", "pending_grants")))
    return {"passed": passed, "observations": observations}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("exe", type=Path)
    parser.add_argument("evidence", type=Path)
    options = parser.parse_args()
    evidence = options.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="agip-wp13-commit-") as directory:
        result = verify(options.exe.resolve(strict=True), evidence, Path(directory))
    text = json.dumps(result, indent=2, sort_keys=True)
    (evidence / "receipt.json").write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
