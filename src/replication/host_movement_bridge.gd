class_name HostMovementBridge
extends RefCounted
## Maps the admitted native connection to a run seat and one permitted baseline.

class Binding:
	var active: bool
	var connection: int
	var generation: int
	var run: StringName
	var epoch: int
	var realm: StringName
	var seat: StringName
	var baseline: int

class BoundInteraction:
	var run: StringName
	var epoch: int
	var realm: StringName
	var seat: StringName
	var baseline: int
	var sequence: int
	var command: PlayerCommand

var _seats: Dictionary[int, Binding] = {}
var _interaction_authority: RunAuthority


func _init(interaction_authority: RunAuthority = null) -> void:
	_interaction_authority = interaction_authority


## Install from the host owner after acknowledged admission or a new baseline.
func bind(native_seat: int, connection: int, generation: int, run: StringName, epoch: int,
		realm: StringName, seat: StringName, baseline: int) -> bool:
	if (native_seat <= 0 or connection <= 0 or generation <= 0 or run.is_empty() or epoch <= 0
			or realm.is_empty() or seat.is_empty() or baseline <= 0):
		return false
	var old: Binding = _seats.get(native_seat)
	if old != null and (generation < old.generation
			or (generation == old.generation and (connection < old.connection
				or (connection == old.connection and not old.active)))
			or epoch < old.epoch or (epoch == old.epoch and baseline <= old.baseline)):
		return false
	var scope := Binding.new()
	scope.active = true
	scope.connection = connection
	scope.generation = generation
	scope.run = run
	scope.epoch = epoch
	scope.realm = realm
	scope.seat = seat
	scope.baseline = baseline
	if old != null and old.active:
		_retire_interactions(old)
	_seats[native_seat] = scope
	return true


## Keep the seat watermark after a connection leaves. A newer host session
## may reuse its connection ordinal, so loss also identifies the generation.
func unbind(native_seat: int, connection: int, generation: int) -> void:
	var scope: Binding = _seats.get(native_seat)
	if scope != null and scope.active and scope.connection == connection and scope.generation == generation:
		scope.active = false
		_retire_interactions(scope)


func submit(authority: RunAuthority, received: NativeSessionHost.Command) -> RunAuthority.Admission:
	if authority == null or received == null or received.frame == null:
		return RunAuthority.Admission.INACTIVE
	var scope := _bound_scope(received)
	if scope == null:
		return RunAuthority.Admission.WRONG_SEAT
	var wire := ReplicationMessage.read(received.frame)
	if wire == null or wire.kind != ReplicationMessage.Kind.MOVEMENT:
		return RunAuthority.Admission.UNSUPPORTED_ACTION
	var message := MovementFrame.read(wire.body)
	if message == null:
		return RunAuthority.Admission.UNSUPPORTED_ACTION
	if message.epoch != scope.epoch:
		return RunAuthority.Admission.WRONG_EPOCH
	if message.baseline != scope.baseline:
		return RunAuthority.Admission.WRONG_REALM
	var intent := RunIntent.new(scope.run, scope.epoch, scope.realm, scope.seat, authority.next_tick(),
		message.sequence, message.command.action, message.command)
	return authority.submit(scope.seat, intent)


func submit_interaction(received: NativeSessionHost.Command) -> RunAuthority.Admission:
	if _interaction_authority == null:
		return RunAuthority.Admission.INACTIVE
	var clicked := read_interaction(received)
	if clicked == null:
		return RunAuthority.Admission.UNSUPPORTED_ACTION
	var intent := RunIntent.new(clicked.run, clicked.epoch, clicked.realm, clicked.seat,
		_interaction_authority.next_tick(), clicked.sequence, clicked.command.action, clicked.command)
	intent.reliable = true
	return _interaction_authority.submit(clicked.seat, intent)


## Pass only a scoped reliable click to the authoritative interaction owner.
## Its native sequence belongs to the reliable stream.
func read_interaction(received: NativeSessionHost.Command) -> BoundInteraction:
	var scope := _bound_scope(received)
	if scope == null:
		return null
	var wire := ReplicationMessage.read(received.frame)
	if wire == null or wire.kind != ReplicationMessage.Kind.INTERACTION:
		return null
	var message := RealmInteractionFrame.read(wire.body)
	if message == null or message.epoch != scope.epoch or message.baseline != scope.baseline:
		return null
	var clicked := BoundInteraction.new()
	clicked.run = scope.run
	clicked.epoch = scope.epoch
	clicked.realm = scope.realm
	clicked.seat = scope.seat
	clicked.baseline = scope.baseline
	clicked.sequence = received.frame.sequence
	clicked.command = message.command
	return clicked


func _retire_interactions(scope: Binding) -> void:
	if _interaction_authority != null:
		_interaction_authority.retire_reliable_interactions(scope.run, scope.epoch, scope.seat, scope.realm)


func _bound_scope(received: NativeSessionHost.Command) -> Binding:
	if received == null or received.frame == null:
		return null
	var scope: Binding = _seats.get(received.seat)
	if (scope == null or not scope.active or scope.connection != received.connection
			or scope.generation != received.frame.generation):
		return null
	return scope
