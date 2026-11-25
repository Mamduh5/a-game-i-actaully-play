"""Compare scalar-double contact times to an independent Decimal oracle."""

import argparse
from decimal import Decimal as D, localcontext
import json
from pathlib import Path
import random
import subprocess


def subtract(left, right):
    return tuple(x - y for x, y in zip(left, right, strict=True))


def dot(left, right):
    return sum(x * y for x, y in zip(left, right, strict=True))


def cross(left, right):
    return left[0] * right[1] - left[1] * right[0]


def circle(offset, motion, radius):
    separation = dot(offset, offset) - radius ** 2
    if separation <= 0:
        return D(0)
    a = dot(motion, motion)
    b = dot(offset, motion)
    determinant = b ** 2 - a * separation
    if a == 0 or b >= 0 or determinant < 0:
        return None
    contact = (-b - determinant.sqrt()) / a
    return contact if 0 <= contact <= 1 else None


def segment(offset, motion, radius, axis):
    length_squared = dot(axis, axis)
    if length_squared == 0:
        return circle(offset, motion, radius)
    projection = dot(offset, axis)
    lateral = cross(axis, offset)
    if 0 <= projection <= length_squared and lateral ** 2 <= radius ** 2 * length_squared:
        return D(0)
    contacts = [
        circle(offset, motion, radius),
        circle(subtract(offset, axis), motion, radius),
    ]
    swept_lateral = cross(axis, motion)
    if swept_lateral != 0:
        offset_on_side = radius * length_squared.sqrt()
        for distance in (-offset_on_side, offset_on_side):
            time = (distance - lateral) / swept_lateral
            if 0 <= time <= 1 and 0 <= projection + dot(motion, axis) * time <= length_squared:
                contacts.append(time)
    return min((time for time in contacts if time is not None), default=None)


def ideal(row):
    def point(field):
        return tuple(D.from_float(float(x)) for x in row[field])

    start, finish, a, b = map(point, ("start", "finish", "a", "b"))
    radius = D.from_float(float(row["radius"]))
    if row["kind"] == "circle":
        return circle(subtract(start, a), subtract(subtract(finish, start), subtract(b, a)),
                      radius + D.from_float(float(row["other_radius"])))
    return segment(subtract(start, a), subtract(finish, start), radius, subtract(b, a))


def vectors():
    rows = []
    randomizer = random.Random(70042)
    for index in range(200):
        center = (0, 10 ** 12, -(10 ** 12))[index % 3]
        at = lambda x, y: (center + x, -center + y)
        kind = "circle" if index % 2 == 0 else "segment"
        radius = randomizer.randrange(1, 18) / 8
        start = at(0, randomizer.randrange(-20, 20) / 4)
        finish = at(100, randomizer.randrange(-30, 30) / 4)
        a = at(randomizer.randrange(10, 85), randomizer.randrange(-40, 40) / 4)
        b = at(a[0] - center + randomizer.randrange(-9, 10), a[1] + center + randomizer.randrange(-15, 16))
        rows.append({"kind": kind, "start": start, "finish": finish, "a": a, "b": b,
                     "radius": radius, "other_radius": 0.625})
    far = 10 ** 12
    for offset in (16.0, 16.0009765625):
        rows.append({"kind": "segment", "start": [far, -far], "finish": [far + 64, -far],
                     "a": [far + offset, -far - 4], "b": [far + offset, -far + 4], "radius": 0.125})
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    cases = vectors()
    source, result, log = (output / name for name in ("cases.json", "native.json", "native.log"))
    source.write_text(json.dumps(cases), encoding="utf-8")
    with log.open("wb") as destination:
        subprocess.run(
            [args.engine.resolve(), "--headless", "--path", args.project.resolve(), "--script",
             "res://tools/qualification/wp07_sweep_probe.gd", "--", source, result],
            stdout=destination, stderr=subprocess.STDOUT, check=True, timeout=30,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
    if "ERROR:" in log.read_text(encoding="utf-8", errors="replace"):
        raise ValueError("Native runtime reported an error")
    actual = json.loads(result.read_text(encoding="utf-8"))
    with localcontext() as context:
        context.prec = 85
        projected = [ideal(row) for row in cases]
        (output / "reference.json").write_text(json.dumps(projected, default=str), encoding="utf-8")
        worst = D(0)
        for index, (observed, expected) in enumerate(zip(actual, projected, strict=True)):
            if (observed == -1) != (expected is None):
                raise ValueError(f"Contact classification mismatch at vector {index}")
            if expected is not None:
                worst = max(worst, abs(D.from_float(float(observed)) - expected))
                if abs(D.from_float(float(observed)) - expected) > D("2e-12"):
                    raise ValueError(f"Contact time mismatch at vector {index}")
        if not actual[-2] < actual[-1] or not projected[-2] < projected[-1]:
            raise ValueError("Far-realm order did not survive")
    print(json.dumps({"cases": len(cases), "contacts": sum(time is not None for time in projected),
                      "maximum_time_error": str(worst), "far_order": actual[-2:]}, indent=2))


if __name__ == "__main__":
    main()
