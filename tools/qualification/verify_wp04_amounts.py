"""Compare native signed decimals and binary encoding to independent integer vectors."""

import argparse
import json
from pathlib import Path
import random
import struct
import subprocess

from wp04_posting_oracle import Amount, quantize


def encode(value):
    magnitude = str(abs(value.count)).encode("ascii")
    header = struct.pack("<BBHI", 1, value.count < 0, value.scale, len(magnitude))
    return (header + magnitude).hex()


def cases():
    randomizer = random.Random(62004)
    pairs = [
        (Amount(0, 0), Amount(7, 0)),
        (Amount(1, 0), Amount(4_000_000, 0)),
        (Amount(-9223372036854775808, 0), Amount(9223372036854775807, 0)),
        (Amount(10 ** 400, 0), Amount(25, 8)),
        (Amount(25, 8), Amount(10 ** 400, 0)),
    ]
    digits = (1, 9, 18, 19, 42, 200, 401)
    for index in range(96):
        left = randomizer.randrange(10 ** digits[index % len(digits)])
        right = randomizer.randint(1, 10 ** randomizer.choice(digits))
        pairs.append((Amount(-left if index % 2 else left, randomizer.randrange(13)),
                      Amount(right, randomizer.randrange(13))))
    return pairs


def expected(left, right):
    grid = max(left.scale, right.scale)
    a, b = left.at_scale(grid), right.at_scale(grid)
    products = (
        left + right,
        left - right,
        Amount(left.count * right.count, left.scale + right.scale),
        quantize(left.count * 10 ** right.scale, right.count * 10 ** left.scale),
    )
    return {"encoded": [encode(value) for value in products], "compare": (a > b) - (a < b)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    project, output = args.project.resolve(), args.output.resolve()
    pairs = cases()
    inputs = output / "vectors.json"
    native = output / "native.json"
    log = output / "native.log"
    inputs.write_text(json.dumps([{"left": a.fields(), "right": b.fields()} for a, b in pairs], indent=2),
                      encoding="utf-8")
    with log.open("wb") as destination:
        subprocess.run(
            [args.engine.resolve(), "--headless", "--path", project, "--script",
             "res://tools/qualification/wp04_native_vectors.gd", "--", inputs, native],
            stdout=destination, stderr=subprocess.STDOUT, check=True, timeout=30,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
    if "ERROR:" in log.read_text(encoding="utf-8", errors="replace"):
        raise ValueError("Native runtime reported an error")
    actual = json.loads(native.read_text(encoding="utf-8"))
    reference = [expected(a, b) for a, b in pairs]
    (output / "reference.json").write_text(json.dumps(reference), encoding="utf-8")
    if len(actual) != len(reference):
        raise ValueError("Result count mismatch")
    for index, (observed, target) in enumerate(zip(actual, reference, strict=True)):
        if observed != target:
            raise ValueError(f"Vector {index} disagreed with the independent oracle")
    print(f"Native amount cross-check passed: {len(actual)} operand pairs, 5 results per pair")


if __name__ == "__main__":
    main()
