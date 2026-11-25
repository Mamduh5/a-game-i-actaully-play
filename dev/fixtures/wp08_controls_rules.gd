extends RunAuthority
## Labeled rules fixture with a single automatic sample delivery.

const REALM := &"outer"
const PLAYER := &"player"
const BLOCKERS := 1
const ACTORS := 2
const ATTACKABLE := 4
const ATTACK_RANGE := 490.0

var geometry := RealmGeometry.new(REALM)
var controls := PlayerControlState.new()
var targeting := PlayerTargeting.new()
var candidates: Array[PlayerTargeting.Candidate] = []
var aim := RealmSweep.Point.new(1, 0)
var manual_count: int
var interaction_count: int
var marked: StringName
var interacted: StringName
var launches: int
var misses: int
var hits: int
var movement_during_delivery: int
var shot: RealmSweep.Point
var shot_direction: RealmSweep.Point
var _remaining: float
var _launch_tick: int


func initialize() -> bool:
	var wall := RealmOutline.Edge.new()
	wall.first = RealmSweep.Point.new(825, 180)
	wall.last = RealmSweep.Point.new(825, 575)
	if not geometry.add_segment(&"wall", 0, wall, BLOCKERS, true):
		return false
	if not geometry.add_circle(PLAYER, 0, RealmSweep.Point.new(240, 360), 14, ACTORS):
		return false
	candidates.assign([
		_candidate(&"moving_target", PlayerTargeting.Kind.HOSTILE, 620, 360),
		_candidate(&"pillar", PlayerTargeting.Kind.PILLAR, 485, 465),
		_candidate(&"mechanism", PlayerTargeting.Kind.MECHANISM, 400, 260),
	])
	candidates[2].interactable = true
	candidates[2].precision = true
	return geometry.add_circle(candidates[0].id, 0, candidates[0].position, 18, ATTACKABLE)


static func _candidate(id: StringName, kind: PlayerTargeting.Kind, x: float, y: float) -> PlayerTargeting.Candidate:
	var target := PlayerTargeting.Candidate.new()
	target.id = id
	target.kind = kind
	target.position = RealmSweep.Point.new(x, y)
	target.pick_radius = 25
	target.known = true
	target.compatible = true
	return target


func _supports_action(action: StringName) -> bool:
	return action in PlayerCommand.ACTIONS


func _resolve_tick(tick: int, accepted: Array[RunIntent], _streams: RunRandom) -> Array[Dictionary]:
	var before := geometry.circle_center(PLAYER, 0)
	for intent: RunIntent in accepted:
		var command := intent.command
		var cursor := RealmSweep.Point.new(command.x, command.y)
		match command.action:
			PlayerCommand.MANUAL:
				manual_count += 1
			PlayerCommand.INTERACT:
				interacted = targeting.interact(before, cursor, 270.0, candidates)
				interaction_count += int(not interacted.is_empty())
			PlayerCommand.TARGET:
				marked = targeting.select(before, cursor, ATTACK_RANGE, candidates)
			_:
				controls.apply(command)
				if _launch_tick == 0 and (command.action == PlayerCommand.MOVE_TO or
						(command.action == PlayerCommand.MOVE_AXES and (command.x != 0 or command.y != 0))):
					_launch_tick = tick + 12
	var after := controls.step(geometry, PLAYER, 0, BLOCKERS, 205.0, 1.0 / 60.0)
	if after == null:
		return [{"fault": "uncertified_movement"}]
	aim = controls.aim_from(after, aim)
	if tick == _launch_tick:
		_launch(after)
	elif _launch_tick > 0 and tick == _launch_tick + 8:
		candidates[0].position = RealmSweep.Point.new(620, 225)
		if not geometry.commit_circle_pose(candidates[0].id, 0, candidates[0].position):
			return [{"fault": "target_pose_rejected"}]
	if shot != null:
		movement_during_delivery += int(after.x != before.x or after.y != before.y)
		_advance_shot()
	return [{"position": [after.x, after.y], "aim": [aim.x, aim.y], "manual": manual_count,
		"interactions": interaction_count, "marked": marked, "interacted": interacted, "launches": launches,
		"hits": hits, "misses": misses, "moving_while_committed": movement_during_delivery}]


func _launch(start: RealmSweep.Point) -> void:
	var picked := targeting.attack_target(start, ATTACK_RANGE, candidates)
	for candidate: PlayerTargeting.Candidate in candidates:
		if candidate.id == picked:
			shot = start
			shot_direction = PlayerControlState.direction(start, candidate.position, aim)
			_remaining = ATTACK_RANGE
			launches += 1
			targeting.commit_attack_target(picked)
			return


func _advance_shot() -> void:
	var speed := minf(8, _remaining)
	var finish := RealmSweep.Point.new(shot.x + shot_direction.x * speed, shot.y + shot_direction.y * speed)
	var contact := geometry.certify_circle_sweep(REALM, shot, finish, 0.0, ATTACKABLE)
	if contact != null and contact.unresolved.is_empty() and not contact.contacts.is_empty():
		hits += 1
		shot = null
		return
	_remaining -= speed
	shot = finish
	if _remaining == 0.0:
		misses += 1
		shot = null
