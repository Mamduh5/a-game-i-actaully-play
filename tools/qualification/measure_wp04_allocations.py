"""Count WP04 creation sites and major limb buffers in a temporary source copy."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


COUNTER = """extends RefCounted

static var enabled := false
static var creations := {}
static var peak_limb_bytes := 0
static var limb_bytes_requested := 0
static var widest_amount_bytes := 0
static var widening_calls := 0
static var wide_amounts := 0

static func created(kind: String) -> void:
	if enabled:
		creations[kind] = int(creations.get(kind, 0)) + 1

static func scratch(limbs: int) -> void:
	if enabled:
		var size := limbs * 4
		limb_bytes_requested += size
		peak_limb_bytes = maxi(peak_limb_bytes, size)

static func widened() -> void:
	if enabled:
		widening_calls += 1

static func stored(limbs: int) -> void:
	if enabled:
		wide_amounts += 1
		widest_amount_bytes = maxi(widest_amount_bytes, limbs * 4)

static func summary() -> Dictionary:
	return {"creations": creations, "widening_calls": widening_calls,
		"wide_amounts": wide_amounts, "widest_amount_payload_bytes": widest_amount_bytes,
		"peak_limb_buffer_payload_bytes": peak_limb_bytes, "limb_buffer_bytes_requested": limb_bytes_requested}
"""
PRELOAD = 'const AllocationProbe := preload("res://tools/qualification/wp04_allocation_counter.gd")'
CONSTRUCTOR = re.compile(r"\b(\w+(?:\.\w+)?)\.new\(")
LIMB_BUFFER = re.compile(r"(?:result(?:\.whole)?|shifted)\.resize\((.*)\)")


def instrument(path):
    lines = path.read_text(encoding="utf-8").splitlines()
    transformed = []
    for line in lines:
        indent = line[:len(line) - len(line.lstrip())]
        if stripped := line.strip():
            if not stripped.startswith("#"):
                for name in CONSTRUCTOR.findall(line):
                    if name == "Draft":
                        name = "QuantityThresholdDebit.Draft"
                    transformed.append(f'{indent}AllocationProbe.created("{name}")')
                if path.stem == "quantity_magnitude" and (match := LIMB_BUFFER.fullmatch(stripped)):
                    transformed.append(f"{indent}AllocationProbe.scratch({match[1]})")
                if path.stem == "quantity":
                    if stripped.startswith("static func _make_wide("):
                        transformed.extend((line, "\tAllocationProbe.widened()"))
                        continue
                    if stripped == "result._limbs = limbs":
                        transformed.append(f"{indent}AllocationProbe.stored(limbs.size())")
        transformed.append(line)
        if line == "extends RefCounted":
            transformed.extend(("", PRELOAD))
    path.write_text("\n".join(transformed) + "\n", encoding="utf-8")


def instrument_workload(path):
    text = path.read_text(encoding="utf-8")
    text = text.replace("extends SceneTree\n", f"extends SceneTree\n\n{PRELOAD}\n", 1)
    text, starts = re.subn(r"(?m)^(\t+)(var before_\w+ := Time\.get_ticks_usec\(\))$",
                          r"\1AllocationProbe.enabled = true\n\1\2", text)
    text, ends = re.subn(r"(?m)^(\t+)(elapsed \+= Time\.get_ticks_usec\(\).*)$",
                        r"\1AllocationProbe.enabled = false\n\1\2", text)
    if starts != 3 or ends != 3:
        raise ValueError("Mixed workload measurement boundaries changed")
    text = text.replace("_measured.summary()}",
                        '_measured.summary(), "allocations": AllocationProbe.summary()}')
    path.write_text(text, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--histories", type=int, default=96)
    args = parser.parse_args()
    project = args.project.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, GODOT_MCP_RUNTIME="0", GODOT_MCP_EDITOR_PORT="16551")
    with tempfile.TemporaryDirectory(prefix="agip-wp04-allocation-") as directory:
        copy = Path(directory) / "checkout"
        shutil.copytree(project, copy, ignore=shutil.ignore_patterns(
            ".git", ".godot", ".qa-evidence", "source.zip", "roaming", "local"))
        for path in (copy / "src/quantities").glob("*.gd"):
            instrument(path)
        tools = copy / "tools/qualification"
        (tools / "wp04_allocation_counter.gd").write_text(COUNTER, encoding="utf-8")
        instrument_workload(tools / "wp04_mixed_layers_probe.gd")
        with (output / "import.log").open("wb") as log:
            subprocess.run([args.engine.resolve(), "--headless", "--path", copy, "--import"],
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=90,
                           creationflags=subprocess.CREATE_NO_WINDOW, env=env)
        subprocess.run([sys.executable, "-B", tools / "verify_wp04_mixed_layers.py",
                        "--engine", args.engine.resolve(), "--project", copy,
                        "--output", output / "mixed", "--histories", str(args.histories)],
                       check=True, env=env)
    native = json.loads((output / "mixed/native.json").read_text(encoding="utf-8"))
    allocation = native["allocations"]
    allocation["histories"] = args.histories
    summary = json.dumps(allocation, indent=2, sort_keys=True)
    (output / "allocations.json").write_text(summary + "\n", encoding="utf-8")
    print(summary)


if __name__ == "__main__":
    main()
