"""Check the WP14 rendered, hidden-state and real-input replay evidence."""

import argparse
import hashlib
import json
from pathlib import Path

from wp14_policy import decide


def load(directory):
    return [json.loads(line) for line in (directory / "evidence.jsonl").read_text(encoding="utf-8").splitlines()]


def first(rows, kind):
    return next(row for row in rows if row["kind"] == kind)


def events(rows, kind):
    return [row for row in rows if row["kind"] == kind]


def sha(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def check(condition, reason):
    if not condition:
        raise ValueError(reason)


def verify_course(rows):
    result = first(rows, "result")["data"]
    check(result["passed"] and result["danger_ticks"] == 0, "Expected completed avoidance")
    check(result["manual_uses"] == 1 and result["interactions"] == 1, "Expected one manual action and interaction")
    check(result["world_pointer_events"] == 0, "A GUI gesture leaked into the world route")
    check(first(rows, "warning")["tick"] < first(rows, "manual")["tick"], "Expected the warning before interaction")
    check(first(rows, "interaction")["data"]["focused"], "Expected ordinary button focus")
    return result


def verify(alpha, beta, replay):
    left, right, repeat = (load(directory) for directory in (alpha, beta, replay))
    check(sha(alpha / "start.png") == sha(beta / "start.png"), "Initial player-visible images differ")
    check(first(left, "fixture")["data"]["hidden"] != first(right, "fixture")["data"]["hidden"],
          "Hidden fixtures must differ")
    initial = first(left, "decision")["data"]
    check(initial == first(right, "decision")["data"], "Policy differed for an identical visible frame")
    try:
        decide(dict(initial["view"], hidden_recipe="control"))
    except ValueError:
        pass
    else:
        raise ValueError("Policy schema accepted an undisclosed field")
    for rows in (left, right):
        for row in events(rows, "decision"):
            frame = row["data"]
            check(decide(frame["view"]) == frame["command"], "Recorded visible input does not reproduce decision")
    left_result, right_result, replay_result = (verify_course(rows) for rows in (left, right, repeat))
    check(first(repeat, "fixture")["data"]["hidden"] == first(right, "fixture")["data"]["hidden"],
          "Replay must use the opposing hidden fixture")
    check(replay_result == left_result, "The same bound command replay changed the authoritative result")
    check(first(repeat, "fixture")["data"]["manual_key"] != first(left, "fixture")["data"]["manual_key"],
          "Replay did not exercise the remapped binding")
    check(first(repeat, "manual")["data"]["physical_key"] != first(left, "manual")["data"]["physical_key"],
          "Actuator did not dispatch the remapped physical key")
    check([(r["tick"], r["data"]) for r in events(left, "input")]
          == [(r["tick"], r["data"]) for r in events(repeat, "input")], "Replay altered event order or ticks")
    return {
        "start_frame_sha256": sha(alpha / "start.png"),
        "initial_visible_decision": initial,
        "alpha": left_result,
        "beta": right_result,
        "replay": replay_result,
        "alpha_inputs": len(events(left, "input")),
        "beta_inputs": len(events(right, "input")),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("alpha", type=Path)
    parser.add_argument("beta", type=Path)
    parser.add_argument("replay", type=Path)
    inputs = parser.parse_args()
    print(json.dumps(verify(inputs.alpha, inputs.beta, inputs.replay), indent=2))
