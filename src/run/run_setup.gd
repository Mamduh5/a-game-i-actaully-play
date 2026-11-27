class_name RunSetup
extends RefCounted
## Preparation data. The authority captures a detached copy before starting.

enum Role { SOLO, HOST }

const MAX_SEATS := 4 # GDS PR07 prototype envelope.
const FINAL_REALM := &"unfinished_canvas"

var role: Role = Role.SOLO
var run_id: StringName
var authority_id: StringName
var epoch: int
var seed: int
var rules_revision: StringName
var catalog_revision: StringName
var challenge_id: StringName
var initial_realms: Dictionary[StringName, StringName] = {}


func is_valid_for(local_authority_id: StringName) -> bool:
	if run_id.is_empty() or authority_id.is_empty() or authority_id != local_authority_id:
		return false
	if epoch < 1 or rules_revision.is_empty() or catalog_revision.is_empty() or challenge_id.is_empty():
		return false
	match role:
		Role.SOLO:
			if initial_realms.size() != 1:
				return false
		Role.HOST:
			if initial_realms.is_empty() or initial_realms.size() > MAX_SEATS:
				return false
		_:
			return false
	for seat: StringName in initial_realms:
		if seat.is_empty() or initial_realms[seat].is_empty():
			return false
	return true


func identity() -> Dictionary:
	var seats: Array[StringName] = initial_realms.keys()
	seats.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	var realms: Dictionary[StringName, StringName] = {}
	for seat: StringName in seats:
		realms[seat] = initial_realms[seat]
	return {
		"role": role,
		"run": run_id,
		"authority": authority_id,
		"epoch": epoch,
		"seed": seed,
		"rules": rules_revision,
		"catalog": catalog_revision,
		"challenge": challenge_id,
		"initial_realms": realms,
	}
