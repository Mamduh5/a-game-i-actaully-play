class_name GuestMovement
extends RefCounted
## Predicts the local circle against a detached set of disclosed blockers.
## Host snapshots always own the reset pose, speed and input frontier.

enum Acceptance { APPLIED, STALE, NEED_BASELINE, INVALID, WAITING_FOR_PARTS }

const MAX_PREDICTION_STEPS := 64
const SECONDS_PER_TICK := 1.0 / 60.0
const BLOCKERS := 1
const AVATAR := 2
const LOCAL_BODY := &"local_prediction"

class Blocker:
	var first: RealmSweep.Point
	var last: RealmSweep.Point

	func copy() -> Blocker:
		var result := Blocker.new()
		result.first = PlayerControlState.copy_point(first)
		result.last = PlayerControlState.copy_point(last)
		return result

class Sample:
	var sequence: int
	var tick: int
	var command: PlayerCommand

class Playback:
	var geometry: RealmGeometry
	var controls := PlayerControlState.new()
	var tick: int
	var applied: int

class Scope:
	var realm: StringName
	var state: MovementSnapshot

var _realm: StringName
var _confirmed: MovementSnapshot
var _known: Array[Blocker] = []
var _pending: Array[Sample] = []
var _playback: Playback
var _issued: int
var _needs_baseline := true
var _wanted_epoch: int
var _wanted_baseline: int
var _display: RealmSweep.Point
var _baseline_parts := ReplicationChunks.new()


func install_baseline(realm: StringName, state: MovementSnapshot, disclosed: Array[Blocker]) -> Acceptance:
	if realm.is_empty() or state == null or not state.valid():
		return Acceptance.INVALID
	if state.epoch < _wanted_epoch or (state.epoch == _wanted_epoch and state.baseline < _wanted_baseline):
		return Acceptance.STALE
	if _confirmed != null and (state.epoch < _confirmed.epoch
			or (state.epoch == _confirmed.epoch and (state.baseline <= _confirmed.baseline
				or state.tick < _confirmed.tick or state.acknowledged < _confirmed.acknowledged
				or state.acknowledged > _issued))):
		return Acceptance.STALE
	var known: Array[Blocker] = []
	for blocker: Blocker in disclosed:
		if blocker == null or blocker.first == null or blocker.last == null:
			return Acceptance.INVALID
		known.append(blocker.copy())
	var same_scope := _confirmed != null and state.epoch == _confirmed.epoch and realm == _realm
	var pending: Array[Sample] = []
	if same_scope:
		pending = _retained_inputs(state)
	var finish := _playback.tick if same_scope else state.tick
	var draft := _rebuild(realm, state, known, pending, finish)
	if draft == null:
		return Acceptance.INVALID
	if _confirmed == null or state.epoch != _confirmed.epoch:
		_issued = state.acknowledged
	_realm = realm
	_known = known
	_pending = pending
	_install(state, draft, true)
	return Acceptance.APPLIED


func receive_frame(frame: NativeSessionFrame) -> Acceptance:
	var wire := ReplicationMessage.read(frame)
	if wire == null:
		return Acceptance.INVALID
	match wire.kind:
		ReplicationMessage.Kind.BASELINE:
			return _receive_baseline(wire.body)
		ReplicationMessage.Kind.STATE:
			return receive(MovementSnapshot.read(wire.body))
		ReplicationMessage.Kind.SNAPSHOT_PART:
			var assembly := _baseline_parts.accept(frame.generation, wire, ReplicationMessage.Kind.BASELINE)
			match assembly.result:
				ReplicationChunks.Result.COMPLETE: return _receive_baseline(assembly.body)
				ReplicationChunks.Result.WAITING: return Acceptance.WAITING_FOR_PARTS
				ReplicationChunks.Result.STALE: return Acceptance.STALE
	return Acceptance.INVALID


func _receive_baseline(bytes: PackedByteArray) -> Acceptance:
	var reset := MovementBaseline.read(bytes)
	return install_baseline(reset.realm, reset.state, reset.blockers) if reset != null else Acceptance.INVALID


func receive(state: MovementSnapshot) -> Acceptance:
	if state == null or not state.valid():
		return Acceptance.INVALID
	if _confirmed != null and state.epoch < _confirmed.epoch:
		return Acceptance.STALE
	if _confirmed == null or state.epoch > _confirmed.epoch or state.baseline > _confirmed.baseline:
		if state.epoch > _wanted_epoch or (state.epoch == _wanted_epoch and state.baseline > _wanted_baseline):
			_wanted_epoch = state.epoch
			_wanted_baseline = state.baseline
		_needs_baseline = true
		return Acceptance.NEED_BASELINE
	if (state.baseline < _confirmed.baseline or state.serial <= _confirmed.serial or state.tick < _confirmed.tick
			or state.acknowledged < _confirmed.acknowledged or state.acknowledged > _issued):
		return Acceptance.STALE
	if state.revision != _confirmed.revision or _needs_baseline:
		_needs_baseline = true
		return Acceptance.NEED_BASELINE
	var pending := _retained_inputs(state)
	var draft := _rebuild(_realm, state, _known, pending, _playback.tick)
	if draft == null:
		_needs_baseline = true
		return Acceptance.NEED_BASELINE
	_pending = pending
	_install(state, draft, state.forced_correction or not state.permits_prediction)
	return Acceptance.APPLIED


func issue(command: PlayerCommand) -> PackedByteArray:
	if (_needs_baseline or not _confirmed.permits_prediction or not MovementFrame.is_voluntary(command)
			or _pending.size() >= MAX_PREDICTION_STEPS or _issued == 9223372036854775807
			or _playback.tick >= RunAuthority.MAX_TICK):
		return PackedByteArray()
	var sample := Sample.new()
	_issued += 1
	sample.sequence = _issued
	sample.tick = _playback.tick + 1
	sample.command = command.copy()
	_pending.append(sample)
	return latest_packet()


## Repeat the latest unacknowledged complete movement intent after packet loss.
func latest_packet() -> PackedByteArray:
	if _needs_baseline or _pending.is_empty() or not _confirmed.permits_prediction:
		return PackedByteArray()
	var sample := _pending[-1]
	return ReplicationMessage.pack(ReplicationMessage.Kind.MOVEMENT,
		MovementFrame.pack(_confirmed.epoch, _confirmed.baseline, sample.sequence, sample.command))


func resync_request() -> PackedByteArray:
	if not _needs_baseline:
		return PackedByteArray()
	var request := PackedByteArray()
	request.resize(16)
	request.encode_s64(0, _wanted_epoch)
	request.encode_s64(8, _wanted_baseline)
	return ReplicationMessage.pack(ReplicationMessage.Kind.RESYNC, request)


func advance() -> bool:
	if _needs_baseline or not _confirmed.permits_prediction:
		return false
	if _playback.tick - _confirmed.tick >= MAX_PREDICTION_STEPS or not _step(_playback, _confirmed.speed, _pending):
		_needs_baseline = true
		return false
	return true


func position() -> RealmSweep.Point:
	return _playback.geometry.circle_center(LOCAL_BODY, 0) if _playback != null else null


func confirmed_scope() -> Scope:
	if _confirmed == null:
		return null
	var scope := Scope.new()
	scope.realm = _realm
	scope.state = MovementSnapshot.read(_confirmed.pack())
	return scope


func needs_baseline() -> bool:
	return _needs_baseline


func pending_count() -> int:
	return _pending.size()


## Rendering is separate from the certified prediction pose.
func draw_position(blend: float) -> RealmSweep.Point:
	var pose := position()
	if pose == null:
		return null
	var alpha := clampf(blend, 0.0, 1.0) if is_finite(blend) else 1.0
	_display = RealmSweep.Point.new(lerpf(_display.x, pose.x, alpha), lerpf(_display.y, pose.y, alpha))
	return PlayerControlState.copy_point(_display)


func _install(state: MovementSnapshot, draft: Playback, snap: bool) -> void:
	_confirmed = MovementSnapshot.read(state.pack())
	_playback = draft
	_needs_baseline = false
	_wanted_epoch = state.epoch
	_wanted_baseline = state.baseline
	var pose := position()
	if (snap or _display == null or absf(_display.x - pose.x) + absf(_display.y - pose.y) > state.radius):
		_display = pose
	elif _display.x != pose.x or _display.y != pose.y:
		var path := draft.geometry.certify_circle_sweep(_realm, _display, pose, state.radius, BLOCKERS)
		if path == null or not path.contacts.is_empty() or not path.unresolved.is_empty():
			_display = pose


func _retained_inputs(state: MovementSnapshot) -> Array[Sample]:
	var pending: Array[Sample] = []
	# An authority-owned motion transition supersedes voluntary input even
	# when the last input arrived too late to be acknowledged by the host.
	if not state.permits_prediction or state.forced_correction:
		return pending
	for sample: Sample in _pending:
		if sample.sequence > state.acknowledged:
			pending.append(sample)
	return pending


static func _rebuild(realm: StringName, state: MovementSnapshot, known: Array[Blocker],
		pending: Array[Sample], until: int) -> Playback:
	var draft := Playback.new()
	draft.geometry = RealmGeometry.new(realm)
	if not draft.geometry.add_circle(LOCAL_BODY, 0, state.position, state.radius, AVATAR):
		return null
	for index: int in known.size():
		var edge := RealmOutline.Edge.new()
		edge.first = known[index].first
		edge.last = known[index].last
		if not draft.geometry.add_segment(&"disclosed_blockers", index, edge, BLOCKERS, true):
			return null
	draft.controls.apply(state.movement)
	draft.tick = state.tick
	draft.applied = state.acknowledged
	if state.permits_prediction:
		var finish := state.tick + clampi(until - state.tick, 0, MAX_PREDICTION_STEPS)
		while draft.tick < finish:
			if not _step(draft, state.speed, pending):
				return null
	return draft


static func _step(draft: Playback, speed: float, pending: Array[Sample]) -> bool:
	if draft.tick >= RunAuthority.MAX_TICK:
		return false
	var tick := draft.tick + 1
	for sample: Sample in pending:
		if sample.sequence > draft.applied and sample.tick <= tick:
			draft.controls.apply(sample.command)
			draft.applied = sample.sequence
	if draft.controls.step(draft.geometry, LOCAL_BODY, 0, BLOCKERS, speed, SECONDS_PER_TICK) == null:
		return false
	draft.tick = tick
	return true
