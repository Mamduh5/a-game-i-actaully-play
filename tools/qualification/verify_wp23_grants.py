"""Kill separate native development processes around important grant commits."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


def exercise(exe, evidence, root):
    root = root.resolve()
    marker = root / "boundary"
    env = {**os.environ, "GODOT_MCP_RUNTIME": "off"}

    def start(label, role, *extras):
        log = evidence / f"{label}.log"
        args = [exe, "--headless", "--log-file", log, "--", role, str(root), *extras]
        return subprocess.Popen(args, env=env, creationflags=subprocess.CREATE_NO_WINDOW), log

    def run(label, role):
        child, log = start(label, role)
        try:
            assert child.wait(timeout=12) == 0, label
        finally:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=4)
        output = log.read_text(encoding="utf-8")
        assert "ERROR:" not in output, label
        line = next(text for text in output.splitlines() if text.startswith("WP23_GRANT "))
        result = json.loads(line.removeprefix("WP23_GRANT "))
        assert result.pop("passed"), label
        return result

    def interrupt(role, point):
        marker.unlink(missing_ok=True)
        child, _ = start(f"{role}-{point}-killed", role, point)
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline and child.poll() is None:
                if marker.is_file() and marker.read_bytes() == b"\x01":
                    child.kill()
                    assert child.wait(timeout=4) != 0
                    return
                time.sleep(0.015)
            raise RuntimeError(f"The {role} process did not reach {point} commit")
        finally:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=4)

    run("keys", "keys")
    results = {}
    for role, inspect in [("issue", "inspect-issuer"), ("apply", "inspect-recipient"), ("ack", "inspect-issuer")]:
        for boundary in ("before", "after"):
            interrupt(role, boundary)
            label = f"{role}-{boundary}"
            results[label] = run(label, inspect)
        if role == "issue":
            results["courier"] = run("courier", "courier")
        if role == "apply":
            results["replay"] = run("redelivered", "apply")
    results["duplicate_ack"] = run("duplicate-ack", "ack")
    assert results["issue-before"] == {"pending": 0, "generation": 0, "tick": -1, "balance": 0}
    assert results["issue-after"] == {"pending": 1, "generation": 1, "tick": 4, "balance": 0}
    assert results["courier"] == {"pending": 1}
    assert results["apply-before"] == {"pending": 0, "generation": 0, "tick": -1, "balance": 0}
    assert results["apply-after"] == {"pending": 0, "generation": 1, "tick": -1, "balance": 17}
    assert results["replay"] == {"status": 1, "balance": 17}
    assert results["ack-before"] == {"pending": 1, "generation": 1, "tick": 4, "balance": 0}
    assert results["ack-after"] == {"pending": 0, "generation": 2, "tick": 4, "balance": 0}
    assert results["duplicate_ack"] == {"status": 1, "pending": 0}
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("exe", type=Path)
    parser.add_argument("evidence", type=Path)
    options = parser.parse_args()
    evidence = options.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="agip-wp23-grants-") as work:
        results = exercise(options.exe.resolve(strict=True), evidence, Path(work))
    receipt = json.dumps(results, indent=2, sort_keys=True) + "\n"
    (evidence / "receipt.json").write_text(receipt, encoding="utf-8")
    print(receipt)


if __name__ == "__main__":
    main()
