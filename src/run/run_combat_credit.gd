class_name RunCombatCredit
extends RefCounted
## Personal credit is derived from closed combat receipts. The encounter's
## presence ledger and shared XP never supply a personal kill or assist.

class Credit:
	var target: StringName
	var life: int
	var killer: StringName
	var assists: Array[StringName] = []

var _seats: Array[StringName]
var _assists: Dictionary[String, Dictionary] = {}
var _closed_lives: Dictionary[StringName, int] = {}
var _latest: CombatInstant


func _init(party: RunParty) -> void:
	_seats = party.initialized_seats()


## Only authored effects can confirm meaningful non-damaging control.
func observe_hit(hit: CombatKernel.Hit, now: CombatInstant, window: int, effective_control: bool = false) -> bool:
	return (hit != null and hit.accepted and hit.hostile and (effective_control or hit.dealt_hostile_damage())
		and _record(hit.origin, hit.target, hit.target_life, now, window))


## The authored support mechanic reports which enemy life actually benefited
## from that ally contribution. Proximity alone does not reach this path.
func observe_support(origin: CombatOrigin, target: StringName, life: int, now: CombatInstant, window: int) -> bool:
	return _record(origin, target, life, now, window)


func settle(elimination: CombatKernel.Hit, now: CombatInstant) -> Credit:
	if (elimination == null or not elimination.eliminated or not elimination.accepted or not _accepts_time(now)
			or elimination.origin == null or not elimination.origin.valid_for(now)
			or not _open_life(elimination.target, elimination.target_life)):
		return null
	var result := Credit.new()
	result.target = elimination.target
	result.life = elimination.target_life
	if _player(elimination.origin):
		result.killer = elimination.origin.owner
	var key := _key(result.target, result.life)
	var assists: Dictionary = _assists.get(key, {})
	for seat: StringName in _seats:
		var expiry: CombatInstant = assists.get(seat)
		if seat != result.killer and expiry != null and now.order_against(expiry) in [
				RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]:
			result.assists.append(seat)
	_assists.erase(key)
	_closed_lives[result.target] = result.life
	_latest = now
	return result


func _record(origin: CombatOrigin, target: StringName, life: int, now: CombatInstant, window: int) -> bool:
	if (not _accepts_time(now) or not _player(origin) or not origin.valid_for(now)
			or not _open_life(target, life) or window < 0):
		return false
	var through := now.after_ticks(window)
	if through == null:
		return false
	var assists: Dictionary = _assists.get_or_add(_key(target, life), {})
	var previous: CombatInstant = assists.get(origin.owner)
	if previous != null:
		match previous.order_against(through):
			RealmCircleTime.Order.UNRESOLVED: return false
			RealmCircleTime.Order.SAME, RealmCircleTime.Order.AFTER: through = previous
	assists[origin.owner] = through
	_latest = now
	return true


func _accepts_time(now: CombatInstant) -> bool:
	return now != null and (_latest == null or _latest.order_against(now) in [
		RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME])


func _open_life(target: StringName, life: int) -> bool:
	return not target.is_empty() and life > int(_closed_lives.get(target, 0))


func _player(origin: CombatOrigin) -> bool:
	return origin != null and origin.provenance == CombatOrigin.Provenance.SEAT and origin.owner in _seats


static func _key(target: StringName, life: int) -> String:
	return "%d:%s/%d" % [target.length(), target, life]
