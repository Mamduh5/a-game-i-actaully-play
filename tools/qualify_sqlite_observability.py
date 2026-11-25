"""Measure checkpoint stalls and sidecar handling in a verified WP05 disposable matrix."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess


FIXTURE_SHA256 = "2f3e429004e57abfbf7a1809b735c7a4ac3feb798fed4176fead81113d983ebb"
ENGINE_SHA256 = "b2ca888d5115a6cedee564764a2ee494a625f2ec2edbabd010fe33c9a88a6bf8"
RELEASE_DLL_SHA256 = "ba79b9bbf916c4ed2eb22ac719051c4a4258e460c4a354590b071beb9a87fedb"


def verify_hash(path, expected):
    with path.open("rb") as file:
        actual = hashlib.file_digest(file, "sha256").hexdigest()
    if actual != expected:
        raise ValueError(f"Unexpected SHA-256 for {path.name}: {actual}")


def patch_fixture(path):
    verify_hash(path, FIXTURE_SHA256)
    source = path.read_text(encoding="utf-8")
    edits = {
        '\t\t\trun_sql("CREATE TABLE sample(n INTEGER PRIMARY KEY)")':
            '\t\t\trun_sql("CREATE TABLE sample(n INTEGER PRIMARY KEY)")\n'
            '\t\t\tif wal:\n'
            '\t\t\t\tread_one("PRAGMA wal_autocheckpoint=0", 0)',
        '\t\t\t\trun_sql("COMMIT")\n\t\t\t\ttrace.append("us "':
            '\t\t\t\tif n == 0:\n'
            '\t\t\t\t\tobserve_sidecars(args[1], "active")\n'
            '\t\t\t\trun_sql("COMMIT")\n\t\t\t\ttrace.append("us "',
        '\t\t\tread_one("SELECT COUNT(*) FROM sample", 128)':
            '\t\t\t\tif wal and (n + 1) % 16 == 0:\n'
            '\t\t\t\t\tvar before: int = Time.get_ticks_usec()\n'
            '\t\t\t\t\trun_sql("PRAGMA wal_checkpoint(TRUNCATE)")\n'
            '\t\t\t\t\ttrace.append("checkpoint us " + str(Time.get_ticks_usec() - before))\n'
            '\t\t\t\t\tcheck(db.query_result[0].values()[0] == 0, "checkpoint not busy")\n'
            '\t\t\tobserve_sidecars(args[1], "committed")\n'
            '\t\t\tread_one("SELECT COUNT(*) FROM sample", 128)',
        '\tcheck(db.close_db(), "close")\n\treport(0)':
            '\tcheck(db.close_db(), "close")\n'
            '\tif mode == "latency":\n'
            '\t\tobserve_sidecars(args[1], "closed")\n'
            '\treport(0)',
    }
    for old, new in edits.items():
        if source.count(old) != 1:
            raise ValueError("Fixture no longer matches the documented input")
        source = source.replace(old, new)
    source += '''

func observe_sidecars(path: String, phase: String) -> void:
	for suffix: String in ["-journal", "-wal", "-shm"]:
		trace.append("sidecar %s %s %s" % [phase, suffix, FileAccess.file_exists(path + suffix)])
'''
    path.write_text(source, encoding="utf-8", newline="\n")


def run(arguments, output, environment):
    engine_log = Path(arguments[arguments.index("--log-file") + 1])
    with engine_log.with_suffix(".stdout.log").open("wb") as destination:
        subprocess.run(
            arguments, cwd=output, env=environment, stdout=destination,
            stderr=subprocess.STDOUT, check=True, timeout=30,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
    # The actual GUI editor EXE writes its diagnostic log via --log-file.
    if re.search(r"(?m)^\s*(?:SCRIPT ERROR|ERROR):", engine_log.read_text(encoding="utf-8", errors="replace")):
        raise RuntimeError(f"Engine reported an error in {engine_log.name}")


def describe_receipt(receipt, journal):
    content = receipt.read_text(encoding="utf-8")
    if not content.startswith("0\n"):
        raise ValueError(f"Fixture did not pass for {journal}")
    checkpoints = [int(value) for value in re.findall(r"(?m)^checkpoint us (\d+)$", content)]
    if len(checkpoints) != (8 if journal == "WAL" else 0):
        raise ValueError(f"Unexpected checkpoint count for {journal}")
    sidecars = {}
    for phase, suffix, exists in re.findall(r"(?m)^sidecar (\w+) (-\w+) (true|false)$", content):
        sidecars.setdefault(phase, {})[suffix] = exists == "true"
    if len(sidecars) != 3 or any(len(state) != 3 for state in sidecars.values()):
        raise ValueError(f"Incomplete sidecar observations for {journal}")
    if any(sidecars["closed"].values()):
        raise ValueError(f"Sidecar remained after graceful close under {journal}")
    expected_during_write = "-wal" if journal == "WAL" else "-journal"
    if not sidecars["active"][expected_during_write]:
        raise ValueError(f"Expected {expected_during_write} during {journal} write")
    return {
        "checkpoint_samples_us": checkpoints,
        "checkpoint_median_us": statistics.median(checkpoints) if checkpoints else None,
        "checkpoint_max_us": max(checkpoints) if checkpoints else None,
        "sidecars": sidecars,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matrix", type=Path, required=True, help="Existing successful portable reviewer matrix")
    parser.add_argument("--output", type=Path, required=True, help="Fresh disposable directory")
    args = parser.parse_args()
    matrix = args.matrix.resolve()
    output = args.output.resolve()
    rows = json.loads((matrix / "results.json").read_text(encoding="utf-8"))
    if not any(row["name"] == "boot-c" and row.get("DELETE") == row.get("WAL") == "passed" for row in rows):
        raise ValueError("Expected a completed boot-c run in both journal modes")
    boot = matrix / "boot-c"
    engine = boot / "portable" / "Godot_v4.7-stable_win64.exe"
    verify_hash(engine, ENGINE_SHA256)
    output.mkdir(parents=True, exist_ok=False)
    project = output / "project"
    shutil.copytree(boot / "checkout", project, ignore=shutil.ignore_patterns(".git", ".godot"))
    patch_fixture(project / "fixture.gd")
    environment = dict(os.environ)
    for name in ("APPDATA", "LOCALAPPDATA", "TEMP", "TMP"):
        isolated = output / name.lower()
        isolated.mkdir(exist_ok=True)
        environment[name] = str(isolated)
    prefix = [engine, "--headless", "--path", project]
    run(prefix + ["--editor", "--quit-after", "180", "--log-file", output / "bootstrap.log"], output, environment)
    run(prefix + ["--import", "--log-file", output / "import.log"], output, environment)
    release = output / "qual.exe"
    run(prefix + ["--export-release", "Windows Desktop", release, "--log-file", output / "export.log"], output, environment)
    verify_hash(output / "libgdsqlite.windows.template_release.x86_64.dll", RELEASE_DLL_SHA256)

    results = {}
    for journal in ("DELETE", "WAL"):
        receipt = output / f"{journal}.txt"
        run(
            [release, "--headless", "--log-file", output / f"{journal}.log", "--", "latency",
             output / f"{journal}.db", receipt, output / f"{journal}-unused-backup.db"],
            output, dict(environment, QUAL_JOURNAL=journal),
        )
        results[journal] = describe_receipt(receipt, journal)
    report = json.dumps(results, indent=2)
    (output / "observability.json").write_text(report + "\n", encoding="utf-8")
    print(report)


if __name__ == "__main__":
    main()
