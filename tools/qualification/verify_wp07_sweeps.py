"""Compare scalar-double contact times to an independent Decimal oracle."""

import argparse
from decimal import Decimal as D, localcontext
import json
import math
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
    for power in range(0, 26):
        scale = 1 << power
        for gap in (0.0, math.ulp(5.0 * scale), -math.ulp(5.0 * scale)):
            center = (5.0 * scale + gap, 5.0 * scale)
            vector = {"kind": "circle", "start": (0, 0), "finish": (8 * scale, 8 * scale),
                      "a": center, "b": center, "radius": scale, "other_radius": 0, "certified_only": True}
            if gap == 0:
                reference_index = len(rows)
            else:
                vector["compare_to"] = reference_index
            rows.append(vector)
        rows.append({"kind": "segment", "start": (0, 0), "finish": (8 * scale, 8 * scale),
                     "a": (scale, 9 * scale), "b": (9 * scale, scale), "radius": scale,
                     "certified_only": True, "compare_to": reference_index, "equal": True})
    scale = 1 << 30
    tangent = {"kind": "circle", "start": (0, 0), "finish": (12 * scale, 16 * scale),
               "a": (2 * scale, 11 * scale), "b": (2 * scale, 11 * scale), "other_radius": 0,
               "certified_only": True}
    for radius in (5.0 * scale, math.nextafter(5.0 * scale, 0.0), math.nextafter(5.0 * scale, math.inf)):
        rows.append(dict(tangent, radius=radius))
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
    native = json.loads(result.read_text(encoding="utf-8"))
    actual = [row["time"] for row in native]
    with localcontext() as context:
        context.prec = 85
        projected = [ideal(row) for row in cases]
        (output / "reference.json").write_text(json.dumps(projected, default=str), encoding="utf-8")
        worst = D(0)
        certified = {kind: {"hits": 0, "misses": 0, "unresolved": 0} for kind in ("circle", "segment")}
        ordered = 0
        for index, (row, expected) in enumerate(zip(native, projected, strict=True)):
            case = cases[index]
            observed = row["time"]
            if not case.get("certified_only"):
                if (observed == -1) != (expected is None):
                    raise ValueError(f"Contact classification mismatch at vector {index}")
                if expected is not None:
                    worst = max(worst, abs(D.from_float(float(observed)) - expected))
                    if abs(D.from_float(float(observed)) - expected) > D("2e-12"):
                        raise ValueError(f"Contact time mismatch at vector {index}")
            proof = row.get("proof")
            if proof is None:
                continue
            counts = certified[cases[index]["kind"]]
            if proof["outcome"] == 0:
                if expected is not None:
                    raise ValueError(f"False certified miss at vector {index}")
                counts["misses"] += 1
            elif proof["outcome"] == 1:
                if expected is None or not D.from_float(proof["lower"]) <= expected <= D.from_float(proof["upper"]):
                    raise ValueError(f"Contact outside certified bounds at vector {index}")
                counts["hits"] += 1
            elif proof["outcome"] == 2:
                if case.get("certified_only"):
                    raise ValueError(f"Unresolved adversarial vector {index}")
                counts["unresolved"] += 1
            else:
                raise ValueError(f"Invalid certification at vector {index}")
            if "compare_to" in case:
                delta = expected - projected[case["compare_to"]]
                if case.get("equal"):
                    assert abs(delta) < D("1e-75")
                    delta = D(0)
                if row["order"] != 1 + (delta > 0) - (delta < 0):
                    raise ValueError(f"Certified order mismatch at vector {index}")
                ordered += 1
        if not actual[-2] < actual[-1] or not projected[-2] < projected[-1]:
            raise ValueError("Far-realm order did not survive")
    print(json.dumps({"cases": len(cases), "contacts": sum(time is not None for time in projected),
                      "maximum_time_error": str(worst), "far_order": actual[-2:],
                      "certified_order_pairs": ordered, "certified": certified}, indent=2))


if __name__ == "__main__":
    main()
