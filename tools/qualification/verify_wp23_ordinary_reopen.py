"""Verify ordinary-earning disclosure after native process termination and clean exit."""

import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
from verify_wp06_link import launch, peer_env
from verify_wp06_session import stop, wait_for_signal

PREFIX = "WP23_REOPEN "


def read_result(process, log):
    try:
        code = process.wait(timeout=10)
    finally:
        stop(process)
    lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
    if code != 0 or any("ERROR:" in line for line in lines):
        raise RuntimeError(f"Unexpected exit or diagnostic in {log.name}")
    return next((json.loads(line[len(PREFIX):]) for line in lines if line.startswith(PREFIX)), None)


def verify(exe, evidence, scratch, capture):
    observations = {}
    for mode in ("before", "after", "orderly"):
        root = scratch / mode
        ready = scratch / f"{mode}.ready"
        log = evidence / f"{mode}-writer.log"
        arguments = [mode, root]
        if mode != "orderly":
            arguments.append(ready)
        writer = launch([exe], log, peer_env(scratch / f"{mode}-writer"), *arguments)
        if mode == "orderly":
            read_result(writer, log)
        else:
            try:
                wait_for_signal(writer, ready, 8)
                writer.kill()
                if writer.wait(timeout=5) == 0:
                    raise RuntimeError(f"{mode} writer did not terminate abruptly")
            finally:
                stop(writer)
        log = evidence / f"{mode}-reader.log"
        reader = launch([exe], log, peer_env(scratch / f"{mode}-reader"), "read", root)
        observations[mode] = read_result(reader, log)

    if capture:
        log = evidence / "rendered-reader.log"
        image = evidence / "disclosure.png"
        reader = subprocess.Popen(
            [exe, "--resolution", "960x540", "--log-file", log, "--", "read", scratch / "before", image],
            env=peer_env(scratch / "rendered-reader"), creationflags=subprocess.CREATE_NO_WINDOW,
        )
        if read_result(reader, log) != observations["before"] or not image.is_file() or image.stat().st_size == 0:
            raise RuntimeError("Rendered readback did not match the headless readback")

    expected = {
        "before": {"balance": 7, "generation": 2, "notice": True},
        "after": {"balance": 18, "generation": 3, "notice": True},
        "orderly": {"balance": 18, "generation": 4, "notice": False},
    }
    return {"passed": observations == expected, "observations": observations}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("exe", type=Path)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--capture", action="store_true")
    options = parser.parse_args()
    evidence = options.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="agip-wp23-reopen-") as directory:
        result = verify(options.exe.resolve(strict=True), evidence, Path(directory), options.capture)
    receipt = json.dumps(result, indent=2, sort_keys=True)
    (evidence / "receipt.json").write_text(receipt + "\n", encoding="utf-8")
    print(receipt)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
