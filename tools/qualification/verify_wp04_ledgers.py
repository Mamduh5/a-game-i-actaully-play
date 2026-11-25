"""Compare ordered native ledger drafts and their encodings to integer accounting."""

import argparse
import json
from pathlib import Path
import random
import subprocess
import sys

sys.dont_write_bytecode = True
from verify_wp04_amounts import encode
from wp04_posting_oracle import Amount


INPUT_SCALE = 8
GRID = INPUT_SCALE + 2


def cases():
    randomizer = random.Random(62044)
    huge = 10 ** (400 + INPUT_SCALE)
    for values in (
        (0, 0, 0, 0, 100, 50, 25, 50),
        (5, 1, 1, 2, 100, 50, 0, 100),
        (4, 1, 1, 2, 100, 50, 0, 100),
        (3, 1, 1, 2, 100, 50, 0, 100),
        (1, huge, 0, 0, huge, 0, 10, 10),
        (0, huge, 0, 0, huge - 1, 0, 10, 10),
        (0, 98, 0, 0, 101, 1, 4, 15),
        (0, 98, 0, 0, 101, 5, 4, 5),
    ):
        for hostile in (False, True):
            for excess in (False, True):
                yield values, hostile, excess
    for index in range(400):
        maximum = randomizer.randrange(10 ** (12 if index % 5 else 410))
        reserve_limit = randomizer.randrange(10**12)
        fields = (randomizer.randrange(10**12), randomizer.randrange(10**12), randomizer.randrange(10**11),
                  randomizer.randrange(10**11), maximum, randomizer.randrange(10**12),
                  randomizer.randrange(reserve_limit + 1), reserve_limit)
        yield fields, bool(index % 2), bool(index % 3)


def reference(fields, hostile, excess_allowed):
    incoming, hp, a, b, cap, offered, reserve, limit = [value * 100 for value in fields]
    paid_a = min(incoming, a)
    paid_b = min(incoming - paid_a, b)
    after_barriers = incoming - paid_a - paid_b
    damage = min(after_barriers, hp)
    after_hit = hp - damage
    clamped = min(after_hit, cap)
    restored = min(offered, cap - clamped) if clamped else 0
    after_heal = clamped + restored
    excess = offered - restored if clamped and excess_allowed else 0
    stored = min(limit - reserve, excess)
    balance = reserve + stored
    released = min(balance, cap // 20, cap - after_heal) if after_heal else 0
    amounts = (paid_a, a - paid_a, paid_b, b - paid_b, damage, after_hit, damage if hostile else 0,
               after_barriers - damage, clamped, after_hit - clamped, restored, after_heal, excess,
               offered - restored - excess, stored, balance, excess - stored, released,
               after_heal + released, released, balance - released)
    return {"amounts": [encode(Amount(value, GRID)) for value in amounts],
            "depleted": [hostile and 0 < paid_a == a, hostile and 0 < paid_b == b],
            "lethal": 0 < hp == damage}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    source, native, log = (output / name for name in ("vectors.json", "native.json", "native.log"))
    rows = list(cases())
    source.write_text(json.dumps([{"amounts": [Amount(value, INPUT_SCALE).fields() for value in fields],
                                  "hostile": hostile, "excess": excess} for fields, hostile, excess in rows]),
                      encoding="utf-8")
    with log.open("wb") as destination:
        subprocess.run([args.engine.resolve(), "--headless", "--path", args.project.resolve(), "--script",
                        "res://tools/qualification/wp04_native_ledger_probe.gd", "--", source, native],
                       stdout=destination, stderr=subprocess.STDOUT, check=True, timeout=40,
                       creationflags=subprocess.CREATE_NO_WINDOW)
    if "ERROR:" in log.read_text(encoding="utf-8", errors="replace"):
        raise ValueError("Native ledger reported an error")
    expected = [reference(*row) for row in rows]
    (output / "reference.json").write_text(json.dumps(expected), encoding="utf-8")
    for index, (actual, target) in enumerate(zip(json.loads(native.read_text(encoding="utf-8")), expected, strict=True)):
        if actual != target:
            raise ValueError(f"Ledger mismatch in vector {index}")
    print(f"Matched {len(rows)} ledger vectors with 21 encoded postings and three branch decisions each")


if __name__ == "__main__":
    main()
