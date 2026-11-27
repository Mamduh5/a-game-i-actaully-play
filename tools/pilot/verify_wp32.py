"""Run the rendered starter encounter and replay the same legal inputs with outline art."""

import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

PREFIX = "WP32_ENCOUNTER "
SCENE = "res://dev/fixtures/wp32_encounter.tscn"
FAMILIES = {
    "sword": {"W01", "H01.siphon_pulse", "R02.lightning", "RP03.storm_relay"},
    "bow": {"W02", "H03.harmonic_burst", "P02", "P14"},
    "staff": {"W03", "H04.temporal_echo", "P04", "P14"},
}


def run(command, environment, output, preset, mode, inputs):
    output.mkdir(parents=True)
    log = output / "runtime.log"
    args = ["--resolution", "960x540", "--log-file", log, "--", preset, mode,
            sys.executable, inputs, output]
    process = subprocess.run([*command, *args], env=environment, timeout=70,
                             creationflags=subprocess.CREATE_NO_WINDOW, check=False)
    lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
    receipt = next((json.loads(line[len(PREFIX):]) for line in lines if line.startswith(PREFIX)), None)
    if (process.returncode or receipt is None or not receipt["passed"]
            or any("ERROR:" in line for line in lines)):
        raise RuntimeError(f"Encounter failed. See {log}")
    records = [json.loads(line) for line in (output / "evidence.jsonl").read_text(encoding="utf-8").splitlines()]
    closed = [row for row in records if "outcomes" in row]
    if len(closed) != receipt["ticks"] or not (output / "end.png").is_file():
        raise RuntimeError(f"Missing closed tick or capture in {output}")
    return receipt, closed


def verify(command, directory, scratch, presets):
    roaming, local = scratch / "roaming", scratch / "local"
    roaming.mkdir()
    local.mkdir()
    environment = dict(os.environ, APPDATA=str(roaming), LOCALAPPDATA=str(local), GODOT_MCP_RUNTIME="off")
    policy = Path(__file__).with_name("wp32_policy.py").resolve(strict=True)
    results = {}
    for preset in presets:
        live = directory / preset / "live"
        replay = directory / preset / "replay-outline"
        result, closed = run(command, environment, live, preset, "pilot", policy)
        alternate, replayed = run(command, environment, replay, preset, "replay-outline", live / "evidence.jsonl")
        if result != alternate or closed != replayed:
            raise RuntimeError(f"{preset} replay diverged")
        if (not FAMILIES[preset] <= result["damage_by_family"].keys() or result["manual"] <= 0
                or result["warning_ticks"] <= 0 or not result["second_room"]
                or (preset in {"sword", "bow"} and result["displacements"] <= 0)):
            raise RuntimeError(f"{preset} did not cover the representative mechanics")
        if not (live / "warning.png").is_file():
            raise RuntimeError(f"{preset} warning was not captured")
        if (live / "end.png").read_bytes() == (replay / "end.png").read_bytes():
            raise RuntimeError(f"{preset} outline presentation did not change")
        result["trace"] = sha256(json.dumps(closed, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        results[preset] = result
    return {"passed": True, "encounters": results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("exe", type=Path)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--project", type=Path, help="Editor project root when running the source scene")
    parser.add_argument("--preset", choices=FAMILIES, action="append")
    options = parser.parse_args()
    command = [options.exe.resolve(strict=True)]
    if options.project:
        command.extend(["--path", options.project.resolve(strict=True), SCENE])
    evidence = options.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="agip-wp32-solo-") as directory:
        result = verify(command, evidence, Path(directory), options.preset or FAMILIES)
    receipt = json.dumps(result, indent=2, sort_keys=True)
    (evidence / "receipt.json").write_text(receipt + "\n", encoding="utf-8")
    print(receipt)
    return 0


if __name__ == "__main__":
    sys.exit(main())
