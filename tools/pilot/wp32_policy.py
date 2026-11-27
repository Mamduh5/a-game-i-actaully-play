"""Steer the encounter from the same circles, threat footprints and controls it draws."""

from __future__ import annotations

import json
from math import dist
import sys

FIELDS = {"player", "radius", "enemies", "warnings", "manual_ready", "goal", "passage"}


def point(value):
    return isinstance(value, list) and len(value) == 2 and all(type(axis) is int for axis in value)


def decide(view):
    if (not isinstance(view, dict) or set(view) != FIELDS
            or not all(point(view[name]) for name in ("player", "goal", "passage"))
            or type(view["radius"]) is not int or view["radius"] <= 0
            or type(view["manual_ready"]) is not bool
            or not isinstance(view["enemies"], list) or not all(point(at) for at in view["enemies"])
            or not isinstance(view["warnings"], list) or not all(
                isinstance(warning, list) and len(warning) == 2 and point(warning[0])
                and type(warning[1]) is int and warning[1] > 0 for warning in view["warnings"])):
        raise ValueError("Invalid visible encounter frame")
    player = view["player"]
    passage = view["passage"]
    goal = view["goal"]
    radius = view["radius"]
    opponents = view["enemies"]
    target = min(opponents, key=lambda at: dist(at, player)) if opponents else None
    threat = next((at for at, reach in view["warnings"] if dist(at, player) < reach + radius + 8), None)
    if threat is not None:
        # At the center of a tell, pick the side with room to step away.
        away = player[1] - threat[1]
        if abs(away) < 3:
            away = 1 if player[1] < passage[1] else -1
        travel = (0, 1 if away > 0 else -1)
    else:
        destination = target if target is not None else goal
        if (player[0] < passage[0] + radius + 12 and destination[0] >= passage[0]
                and abs(player[1] - passage[1]) > 3):
            destination = [player[0], passage[1]]
        if target is not None and destination == target and dist(target, player) <= radius * 2.9:
            travel = (0, 0)
        else:
            travel = tuple(0 if abs(a - b) <= 2 else (1 if a > b else -1)
                           for a, b in zip(destination, player))
    click = (target if target is not None and view["manual_ready"] and dist(target, player) <= radius * 4.5
             else [])
    return {"horizontal": travel[0], "vertical": travel[1], "manual": False, "click": click}


def main():
    for line in sys.stdin:
        request = json.loads(line)
        if not isinstance(request, dict) or set(request) != {"protocol", "id", "view"} or request["protocol"] != 1:
            raise ValueError("Invalid encounter protocol")
        reply = {"protocol": 1, "id": request["id"], "command": decide(request["view"])}
        print(json.dumps(reply, separators=(",", ":")), flush=True)


if __name__ == "__main__":
    main()
