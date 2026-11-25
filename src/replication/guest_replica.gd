class_name GuestReplica
extends RefCounted
## Guest-only view state. Rendering samples never enter the authority command path.

enum Acceptance { APPLIED, STALE, NEED_BASELINE, INVALID, WAITING_FOR_PARTS }

var _epoch: int
var _baseline: int
var _realm: String
var _baseline_tick: int
var _wanted_epoch: int
var _wanted_baseline: int
var _latest: RecipientView.Snapshot
var _previous: RecipientView.Snapshot
var _view_parts := ReplicationChunks.new()


## Call only after movement has accepted the reliable baseline for this scope.
func install_scope(realm: StringName, state: MovementSnapshot) -> bool:
	if (realm.is_empty() or state == null or not state.valid()
			or state.epoch < _wanted_epoch or (state.epoch == _wanted_epoch and state.baseline < _wanted_baseline)
			or state.epoch < _epoch
			or (state.epoch == _epoch and (state.baseline <= _baseline or state.tick < _baseline_tick))):
		return false
	_epoch = state.epoch
	_baseline = state.baseline
	_realm = String(realm)
	_baseline_tick = state.tick
	_wanted_epoch = _epoch
	_wanted_baseline = _baseline
	_latest = null
	_previous = null
	return true


func receive_frame(frame: NativeSessionFrame) -> Acceptance:
	var wire := ReplicationMessage.read(frame)
	if wire == null:
		return Acceptance.INVALID
	match wire.kind:
		ReplicationMessage.Kind.VIEW:
			return _receive_view(wire.body)
		ReplicationMessage.Kind.SNAPSHOT_PART:
			var assembly := _view_parts.accept(frame.generation, wire, ReplicationMessage.Kind.VIEW)
			match assembly.result:
				ReplicationChunks.Result.COMPLETE: return _receive_view(assembly.body)
				ReplicationChunks.Result.WAITING: return Acceptance.WAITING_FOR_PARTS
				ReplicationChunks.Result.STALE: return Acceptance.STALE
	return Acceptance.INVALID


func _receive_view(bytes: PackedByteArray) -> Acceptance:
	var sample := RecipientView.read(bytes)
	if sample == null:
		return Acceptance.INVALID
	if sample.epoch < _wanted_epoch or (sample.epoch == _wanted_epoch and sample.baseline < _wanted_baseline):
		return Acceptance.STALE
	if sample.epoch > _epoch or (sample.epoch == _epoch and sample.baseline > _baseline):
		_wanted_epoch = sample.epoch
		_wanted_baseline = sample.baseline
		_latest = null
		_previous = null
		return Acceptance.NEED_BASELINE
	if sample.realm != _realm:
		return Acceptance.INVALID
	if sample.tick < _baseline_tick or (_latest != null and sample.tick <= _latest.tick):
		return Acceptance.STALE
	_previous = _latest
	_latest = sample
	return Acceptance.APPLIED


func actor_ids() -> Array[String]:
	return _latest.actors.keys() if _latest != null else []


func actor_pose(id: String, render_tick: int) -> RealmSweep.Point:
	if _latest == null or not _latest.actors.has(id):
		return null
	var current := _latest.actors[id]
	if _previous == null or not _previous.actors.has(id) or render_tick >= _latest.tick:
		return PlayerControlState.copy_point(current)
	var previous := _previous.actors[id]
	if render_tick <= _previous.tick:
		return PlayerControlState.copy_point(previous)
	var alpha := float(render_tick - _previous.tick) / float(_latest.tick - _previous.tick)
	return RealmSweep.Point.new(previous.x * (1.0 - alpha) + current.x * alpha,
		previous.y * (1.0 - alpha) + current.y * alpha)


func warning_sample(id: String) -> RecipientView.Warning:
	if _latest == null or not _latest.warnings.has(id):
		return null
	var source := _latest.warnings[id]
	var warning := RecipientView.Warning.new()
	warning.id = source.id
	warning.realm = source.realm
	warning.origin = PlayerControlState.copy_point(source.origin)
	warning.end = PlayerControlState.copy_point(source.end)
	warning.radius = source.radius
	warning.activation = source.activation
	warning.impact = source.impact
	return warning


func active_warning_ids(tick: int) -> Array[String]:
	var active: Array[String] = []
	if _latest != null:
		for warning: RecipientView.Warning in _latest.warnings.values():
			if tick >= warning.activation and tick <= warning.impact:
				active.append(String(warning.id))
	return active
