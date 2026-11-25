class_name RunIntent
extends RefCounted
## An input adapter supplies the envelope. Its claimed seat is checked separately.

var run_id: StringName
var epoch: int
var realm_id: StringName
var seat_id: StringName
var tick: int
var sequence: int
var action: StringName
var command: PlayerCommand


func _init(
		p_run_id: StringName,
		p_epoch: int,
		p_realm_id: StringName,
		p_seat_id: StringName,
		p_tick: int,
		p_sequence: int,
		p_action: StringName,
		p_command: PlayerCommand = null
) -> void:
	run_id = p_run_id
	epoch = p_epoch
	realm_id = p_realm_id
	seat_id = p_seat_id
	tick = p_tick
	sequence = p_sequence
	action = p_action
	command = p_command.copy() if p_command != null else null


func copy() -> RunIntent:
	return RunIntent.new(run_id, epoch, realm_id, seat_id, tick, sequence, action, command)


func receipt() -> Dictionary:
	var facts := {"realm": realm_id, "seat": seat_id, "sequence": sequence, "action": action}
	if command != null:
		facts["point"] = [command.x, command.y]
	return facts


func valid_payload() -> bool:
	if action in PlayerCommand.ACTIONS:
		return command != null and command.action == action and command.valid()
	return command == null


func matches_payload(other: RunIntent) -> bool:
	if action != other.action:
		return false
	return other.command == null if command == null else command.matches(other.command)
