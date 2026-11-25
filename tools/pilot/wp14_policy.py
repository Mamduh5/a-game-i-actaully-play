"""Visible-only WP14 policy. Its process adapter exchanges one JSON line per frame."""

import json
import sys


VIEW_FIELDS = {"player", "beacon", "hazard", "manual_ready", "button", "complete"}


def decide(view):
    if view.keys() != VIEW_FIELDS:
        raise ValueError("Expected the exact player-visible observation schema")
    command = {"horizontal": 0, "vertical": 0, "manual": False, "click": []}
    if view["complete"]:
        return command
    if view["button"]:
        command["click"] = view["button"]
        return command
    x, y = view["player"]
    goal_x, goal_y = view["beacon"]
    if view["hazard"]:
        _, top, right, _ = view["hazard"]
        if x <= right + 22:
            if y > top - 36:
                command["vertical"] = -1
            else:
                command["horizontal"] = 1
            return command
    if abs(y - goal_y) > 11:
        command["vertical"] = 1 if y < goal_y else -1
    elif view["manual_ready"]:
        command["manual"] = True
    else:
        command["horizontal"] = 1 if x < goal_x else -1
    return command


def main():
    for line in sys.stdin:
        frame = json.loads(line)
        if frame.keys() != {"protocol", "id", "view"} or frame["protocol"] != 1:
            raise ValueError("Invalid frame")
        reply = {"protocol": 1, "id": frame["id"], "command": decide(frame["view"])}
        print(json.dumps(reply, ensure_ascii=True, separators=(",", ":")), flush=True)


if __name__ == "__main__":
    main()
