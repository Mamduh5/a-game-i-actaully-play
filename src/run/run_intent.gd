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


func _init(
		p_run_id: StringName,
		p_epoch: int,
		p_realm_id: StringName,
		p_seat_id: StringName,
		p_tick: int,
		p_sequence: int,
		p_action: StringName
) -> void:
	run_id = p_run_id
	epoch = p_epoch
	realm_id = p_realm_id
	seat_id = p_seat_id
	tick = p_tick
	sequence = p_sequence
	action = p_action


func copy() -> RunIntent:
	return RunIntent.new(run_id, epoch, realm_id, seat_id, tick, sequence, action)


func receipt() -> Dictionary:
	return {"realm": realm_id, "seat": seat_id, "sequence": sequence, "action": action}
