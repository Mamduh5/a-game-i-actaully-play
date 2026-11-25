extends RunAuthority
## Fixture-only rule. Its outcomes consume independent streams without granting game state.


func _supports_action(action: StringName) -> bool:
	return action in [&"sample_world", &"sample_reward"]


func _resolve_tick(_tick: int, accepted: Array[RunIntent], streams: RunRandom) -> Array[Dictionary]:
	var outcomes: Array[Dictionary] = []
	for intent: RunIntent in accepted:
		var stream: StringName = &"world" if intent.action == &"sample_world" else &"reward"
		outcomes.append({"seat": intent.seat_id, "stream": stream, "value": streams.draw(stream)})
	return outcomes
