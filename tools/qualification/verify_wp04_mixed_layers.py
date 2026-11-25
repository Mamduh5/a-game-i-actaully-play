"""Check composited mixed-rate layer receipts against rational and integer models."""

import argparse
from fractions import Fraction
import json
from pathlib import Path
import random
import subprocess
import sys

sys.dont_write_bytecode = True
from verify_wp04_amounts import encode
from wp04_posting_oracle import Amount, Cursor


SCALE = 7
GRID = 10**SCALE


def scenarios(count):
    sources = [101, 103, 107, 109, 113, 127, 131, 137, 139, 149, 151, 157, 163, 167, 173, 179, 181, 191, 193, 197]
    rng = random.Random(620404)
    for index in range(count):
        rates = rng.sample(sources, 15)
        # The first layer has exhausted replay by the last hit. Samples vary
        # how far the final debit reaches through the remaining pools.
        yield {"rates": rates, "hp": 20, "attack": [95, 97, 105, 118, 130][index % 5],
               "excess": bool(index % 2)}


def wire(count):
    return encode(Amount(count, SCALE))


def consume(budget, pool):
    debit = min(budget, pool)
    return debit, budget - debit, pool - debit


def reference(row):
    barrier, ideal_barrier = 100 * GRID, Fraction(100)
    origin_totals = [0, 0, 0]
    receipts = []
    half_quantum = Fraction(1, 2 * GRID)
    for index, denominator in enumerate(row["rates"]):
        cursor = Cursor(10, denominator)
        for occurrence in range(3):
            debit = cursor.next_debit().at_scale(SCALE)
            ideal_barrier -= Fraction(10, denominator)
            barrier -= debit
            assert abs(Fraction(barrier, GRID) - ideal_barrier) <= (index + 1) * half_quantum
            origin = (index + occurrence) % len(origin_totals)
            origin_totals[origin] += debit
            receipts.append([origin, wire(debit)])
    hp_limit = row["hp"] * GRID
    attack = row["attack"] * GRID
    a, remaining, a_left = consume(attack, barrier)
    b, remaining, b_left = consume(remaining, GRID)
    hp, overkill, hp_left = consume(remaining, hp_limit)
    exact_a, exact_remaining, exact_a_left = consume(Fraction(row["attack"]), ideal_barrier)
    exact_b, exact_remaining, exact_b_left = consume(exact_remaining, Fraction(1))
    exact_hp, exact_overkill, exact_hp_left = consume(exact_remaining, Fraction(row["hp"]))
    represented = (a_left, b_left, hp, hp_left, overkill)
    ideal = (exact_a_left, exact_b_left, exact_hp, exact_hp_left, exact_overkill)
    for posted, exact in zip(represented, ideal, strict=True):
        assert (posted > 0) == (exact > 0)
        assert abs(Fraction(posted, GRID) - exact) <= len(row["rates"]) * half_quantum
    assert a + b + hp + overkill == attack
    assert exact_a + exact_b + exact_hp + exact_overkill == row["attack"]
    restored = min(2 * GRID, hp_limit - hp_left) if hp_left else 0
    excess = 2 * GRID - restored if hp_left and row["excess"] else 0
    fields = (a, b, hp, hp_left, overkill, attack, hp, restored, hp_left + restored, excess,
              2 * GRID - restored - excess, *origin_totals)
    return {"receipts": receipts, "amounts": [wire(amount) for amount in fields], "lethal": hp_left == 0,
            "depleted": [a_left == 0, b_left == 0], "first_interval_expired": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--histories", type=int, default=96)
    args = parser.parse_args()
    if args.histories < 1:
        parser.error("--histories must be positive")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    rows = list(scenarios(args.histories))
    source, native, log = (output / name for name in ("vectors.json", "native.json", "native.log"))
    source.write_text(json.dumps(rows), encoding="utf-8")
    with log.open("wb") as destination:
        subprocess.run([args.engine.resolve(), "--headless", "--path", args.project.resolve(), "--script",
                        "res://tools/qualification/wp04_mixed_layers_probe.gd", "--", source, native],
                       stdout=destination, stderr=subprocess.STDOUT, check=True, timeout=180,
                       creationflags=subprocess.CREATE_NO_WINDOW)
    if "ERROR:" in log.read_text(encoding="utf-8", errors="replace"):
        raise ValueError("Native mixed-rate probe reported an error")
    expected = [reference(row) for row in rows]
    (output / "reference.json").write_text(json.dumps(expected), encoding="utf-8")
    actual = json.loads(native.read_text(encoding="utf-8"))
    for index, (observed, wanted) in enumerate(zip(actual["rows"], expected, strict=True)):
        if observed != wanted:
            raise ValueError(f"Mixed-rate ledger mismatch in case {index}")
    measurement = actual["measurement"]
    measurement["attributed_postings"] = sum(len(row["receipts"]) for row in expected)
    summary = json.dumps(measurement, indent=2)
    (output / "summary.json").write_text(summary + "\n", encoding="utf-8")
    print(summary)


if __name__ == "__main__":
    main()
