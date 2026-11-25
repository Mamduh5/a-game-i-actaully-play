"""Compare native mixed-rate posting and timing output with both arithmetic references."""

import argparse
from fractions import Fraction
import json
from pathlib import Path
import subprocess

from wp04_posting_oracle import Cursor


RATES = ((1, 3), (2, 9), (1, 7), (7, 13), (3, 17))
MICRO = 1_000_000


def verify(path):
    report = json.loads(path.read_text(encoding="utf-8"))
    frontiers = report.pop("frontiers")
    if len(frontiers) != 1000:
        raise ValueError("Incomplete native workload")
    worst = Fraction(0)
    for batch, (remaining, debits) in enumerate(frontiers):
        exact = Fraction(100 + batch % 7)
        counts = int(exact) * MICRO
        by_origin = [0, 0, 0, 0]
        cursor = None
        streams = 0
        for event in range(100):
            if event % 3 == 0:
                numerator, divisor = RATES[(batch + event // 3) % len(RATES)]
                cursor = Cursor(numerator, divisor)
                streams += 1
            exact -= Fraction(numerator, divisor)
            if exact <= 0:
                raise ValueError("Ideal reference reached an unexpected terminal branch")
            debit = cursor.next_debit().at_scale(6)
            counts -= debit
            by_origin[event % 4] += debit
        if counts != int(remaining) or by_origin != debits:
            raise ValueError(f"Incorrect represented result in batch {batch}")
        error = abs(exact - Fraction(counts, MICRO))
        if error > Fraction(streams, 2 * MICRO):
            raise ValueError(f"Aggregate error bound exceeded in batch {batch}")
        worst = max(worst, error)
    report["verified_events"] = len(frontiers) * 100
    report["worst_ideal_abs_error"] = str(worst)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    data = output / "native.json"
    log = output / "native.log"
    with log.open("wb") as destination:
        subprocess.run(
            [args.engine.resolve(), "--headless", "--path", args.project.resolve(), "--script",
             "res://tools/qualification/wp04_posting_workload.gd", "--", data],
            stdout=destination, stderr=subprocess.STDOUT, check=True, timeout=180,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
    if "ERROR:" in log.read_text(encoding="utf-8", errors="replace"):
        raise ValueError("Native runtime reported an error")
    summary = json.dumps(verify(data), indent=2)
    (output / "summary.json").write_text(summary + "\n", encoding="utf-8")
    print(summary)


if __name__ == "__main__":
    main()
