extends "res://dev/fixtures/wp18_split_native_probe.gd"
## Both realms keep stepping while the guest walks a generated return route.

const ABSENT_STEPS := 60
const LATER_SITE := &"after_exit"
const RESEND_MS := 250

var _markers: Array[RealmSweep.Point] = []
var _closed_legs: Array[Array] = []
var _seen_legs: Array[Array] = []
var _walking := false
var _exit_queued := false
var _reentry_queued := false
var _stale_exit_refused := false
var _first_pair_ok := false
var _guest_sequence := 2
var _guest_peer: ENetPacketPeer
var _guest_retry_at: int
var _host_retry_at: int
var _cached_state: PackedByteArray
var _old_exit: PackedByteArray
var _exit_tick: int
var _reentry_tick: int
var _new_spawn_tick: int
var _new_resident: StringName
var _outside_capture_ok := true
var _return_facts: Dictionary


func _ready() -> void:
	var route := WorldTopology.generate_optional(SEED, GARDEN)
	for module: StringName in route.route(WorldTopology.ENTRY, WorldTopology.RETURN_EXIT).slice(1):
		_markers.append(route.center(module))
	super._ready()
	if is_processing():
		_deadline = Time.get_ticks_msec() + 28_000


func _run_host() -> void:
	super._run_host()
	if (is_processing() and not _closing and not _cached_state.is_empty()
			and Time.get_ticks_msec() >= _host_retry_at and not _repeat_state()):
		_finish(false)


func _publish_movement(state: MovementSnapshot) -> bool:
	_cached_state = state.pack()
	return _repeat_state()


func _repeat_state() -> bool:
	_host_retry_at = Time.get_ticks_msec() + RESEND_MS
	return _send(Kinds.STATE, _cached_state)


func _run_guest() -> void:
	super._run_guest()
	if not is_processing() or _guest_peer == null or Time.get_ticks_msec() < _guest_retry_at:
		return
	var pending := _movement.latest_packet()
	if not pending.is_empty() and not _send_guest(_guest_peer, SEQUENCED, pending):
		_finish(false)


func _send_guest(peer: ENetPacketPeer, kind: NativeSessionFrame.Kind, payload: PackedByteArray) -> bool:
	_guest_sequence += 1
	_guest_retry_at = Time.get_ticks_msec() + RESEND_MS
	return _link.send(peer, kind, EPOCH, _guest_sequence, payload) == OK


func _queue_command(command: NativeSessionHost.Command) -> bool:
	if _authority.next_tick() <= 2:
		return super._queue_command(command)
	var wire := ReplicationMessage.read(command.frame)
	if wire == null:
		return false
	if wire.kind == Kinds.MOVEMENT:
		return _queue_walk(command, MovementFrame.read(wire.body))
	if wire.kind != Kinds.INTERACTION or _closed_legs.size() != _markers.size():
		return false
	if _baseline == 2 and not _exit_queued:
		_exit_queued = _bridge.submit_interaction(command) == Queued
		return _exit_queued
	if _baseline != 3 or _reentry_queued or _authority.next_tick() != _exit_tick + ABSENT_STEPS + 1:
		return false
	var interaction := RealmInteractionFrame.read(wire.body)
	if interaction != null and interaction.baseline == 2 and not _stale_exit_refused:
		_stale_exit_refused = _bridge.submit_interaction(command) == RunAuthority.Admission.UNSUPPORTED_ACTION
		return _stale_exit_refused
	_reentry_queued = _stale_exit_refused and _bridge.submit_interaction(command) == Queued
	return _reentry_queued


func _queue_walk(command: NativeSessionHost.Command, packet: MovementFrame) -> bool:
	if packet == null or packet.baseline != 2 or packet.epoch != EPOCH or packet.command.action != PlayerCommand.MOVE_TO:
		return false
	var leg := packet.sequence - 3
	if leg < 0 or leg >= _markers.size() or leg > _closed_legs.size():
		return false
	var goal := _markers[leg]
	if packet.command.x != goal.x or packet.command.y != goal.y:
		return false
	var admission := _bridge.submit(_authority, command)
	if leg < _closed_legs.size() or _walking:
		return admission in [RunAuthority.Admission.DUPLICATE, RunAuthority.Admission.STALE_SEQUENCE,
			RunAuthority.Admission.WRONG_REALM]
	_walking = admission == Queued
	_cached_state.clear()
	return _walking


func _advance_host() -> bool:
	if _authority.next_tick() <= 2:
		if not super._advance_host():
			return false
		if _authority.next_tick() == 3:
			_first_pair_ok = super._host_verdict()
			return _first_pair_ok
	if _exit_queued:
		return _exit_garden()
	if _reentry_queued:
		return _reenter_garden()
	return true


func _exit_garden() -> bool:
	_exit_queued = false
	if not _cross_passage() or not _unviewed(_rooms[GARDEN]):
		return false
	_cached_state.clear()
	_exit_tick = _authority.next_tick() - 1
	var site := WorldActivity.SpawnSite.new()
	site.realm = GARDEN
	site.id = LATER_SITE
	site.first_tick = _exit_tick + 30
	site.period = 60
	site.limit = 1
	site.positions = [_offset(_rooms[GARDEN].module_center(WorldTopology.ENTRY), 48)]
	site.rules = _foe(&"garden", [], 14, 1)
	_baseline = 3
	return _authority.activity.schedule_spawn(site) and _publish_scope()


func _reenter_garden() -> bool:
	_reentry_queued = false
	if _new_resident.is_empty() or not _unviewed(_rooms[GARDEN]) or not _cross_passage():
		return false
	_cached_state.clear()
	_reentry_tick = _authority.next_tick() - 1
	_baseline = 4
	return _publish_scope()


func _cross_passage() -> bool:
	return (_authority.close_tick() and _authority.valid and _authority.clicks.size() == 1
		and _passages.interact(_authority.clicks[0]))


func _physics_process(_delta: float) -> void:
	if _role != "host" or _ending or _closing or not _first_pair_ok:
		return
	if not _walking and (_exit_tick == 0 or _authority.next_tick() > _exit_tick + ABSENT_STEPS):
		return
	if not _authority.close_tick() or not _authority.valid:
		_finish(false)
		return
	var state := _snapshot()
	if _walking:
		if not _rooms[GARDEN].observe_seat(GUEST, GARDEN, state.position):
			_finish(false)
			return
		var goal := _markers[_closed_legs.size()]
		if state.position.x == goal.x and state.position.y == goal.y:
			_walking = false
			_closed_legs.append([state.tick, state.acknowledged, state.position.x, state.position.y])
			if not _publish_movement(state):
				_finish(false)
	else:
		if not _unviewed(_rooms[GARDEN]):
			_finish(false)
			return
		if state.tick == _exit_tick + 30:
			for spawn: Array in _authority.world_frame.spawns:
				if spawn[0] == LATER_SITE and String(spawn[1]).begins_with("spawn/"):
					_new_spawn_tick = state.tick
					_new_resident = spawn[1]
		if state.tick == _exit_tick + ABSENT_STEPS and not _publish_movement(state):
			_finish(false)


func _arrival_fighters(scope: RecipientView.Scope, actors: Array[RecipientView.Actor], tick: int) -> StarterEncounter.View:
	if _baseline == 3:
		var view := _living_view(GUEST, OUTSIDE, tick)
		view.others.append(_fighter(HOST, OUTSIDE, false))
		return view
	if _baseline == 4:
		var view := _living_view(GUEST, GARDEN, tick)
		for id: StringName in [RESIDENT, _new_resident]:
			var fighter := _fighter(id, GARDEN, true)
			scope.actors[id] = true
			actors.append(_actor(id, GARDEN, fighter.at))
			view.others.append(fighter)
		return view
	return super._arrival_fighters(scope, actors, tick)


func _accept(peer: ENetPacketPeer, frame: NativeSessionFrame) -> bool:
	var wire := ReplicationMessage.read(frame)
	if wire != null and wire.kind == Kinds.STATE and frame.generation == EPOCH:
		var state := MovementSnapshot.read(wire.body)
		var current := _movement.confirmed_scope()
		# The fixture repeats the last snapshot while it waits for the next leg.
		if state != null and current != null and state.epoch == EPOCH and state.serial <= current.state.serial:
			return true
	return super._accept(peer, frame)


func _finish_guest_move(peer: ENetPacketPeer, scope: GuestMovement.Scope) -> bool:
	var state := scope.state
	if scope.realm == OUTSIDE:
		_return_facts["final_tick"] = state.tick
		_return_facts["final_ack"] = state.acknowledged
		var click := _movement.interaction_packet(PlayerCommand.new(PlayerCommand.INTERACT, state.position.x, state.position.y))
		return (_return_facts.get("returned", false) and state.tick == _return_facts["exit_tick"] + ABSENT_STEPS
			and _outside_capture_ok and _send_guest(peer, RELIABLE, _old_exit) and _send_guest(peer, RELIABLE, click))
	if scope.realm != GARDEN or state.acknowledged != _seen_legs.size() + (2 if state.tick == 2 else 3):
		return false
	_guest_peer = peer
	if state.tick == 2:
		_facts["movement_ack"] = 2
		_frames[SEQUENCED] = true
	else:
		var reached := _markers[_seen_legs.size()]
		if state.position.x != reached.x or state.position.y != reached.y:
			return false
		_seen_legs.append([state.tick, state.acknowledged, reached.x, reached.y])
	if _seen_legs.size() == _markers.size():
		_old_exit = _movement.interaction_packet(PlayerCommand.new(PlayerCommand.INTERACT, state.position.x, state.position.y))
		return _send_guest(peer, RELIABLE, _old_exit)
	var goal := _markers[_seen_legs.size()]
	var movement := _movement.issue(PlayerCommand.new(PlayerCommand.MOVE_TO, goal.x, goal.y))
	return _send_guest(peer, SEQUENCED, movement)


func _receive_view(peer: ENetPacketPeer, frame: NativeSessionFrame, body: PackedByteArray) -> bool:
	var snapshot := RecipientView.read(body)
	if snapshot != null and snapshot.baseline == 4:
		return _receive_reentry(peer, frame, snapshot)
	if snapshot == null or snapshot.baseline != 3:
		return super._receive_view(peer, frame, body)
	if (_replica.receive_frame(frame) != GuestReplica.Acceptance.APPLIED
			or snapshot.realm != String(OUTSIDE) or _replica.actor_ids() != ["guest", "host"]
			or body.get_string_from_utf8().contains(String(RESIDENT))):
		return false
	_return_facts = {"exit_tick": snapshot.tick, "returned": true, "legs": _seen_legs}
	var view := _replica.encounter_view(GUEST, snapshot.tick)
	if view == null:
		return false
	_present(view, OUTSIDE, "Overworld / Returned guest")
	if _display != null:
		_outside_capture_ok = false
		_capture_return_view()
	return true


func _capture_return_view() -> void:
	await RenderingServer.frame_post_draw
	_outside_capture_ok = get_viewport().get_texture().get_image().save_png(_capture.path_join("overworld-return.png")) == OK


func _receive_reentry(peer: ENetPacketPeer, frame: NativeSessionFrame, snapshot: RecipientView.Snapshot) -> bool:
	var state := _movement.confirmed_scope()
	if (_replica.receive_frame(frame) != GuestReplica.Acceptance.APPLIED or state == null or state.realm != GARDEN
			or snapshot.realm != String(GARDEN) or snapshot.tick != _return_facts.get("final_tick", 0) + 1
			or snapshot.tick != state.state.tick or state.state.acknowledged != 5
			or snapshot.party != {"host": "living", "guest": "living"}):
		return false
	var returned := _replica.encounter_view(GUEST, snapshot.tick)
	if returned == null or returned.others.size() != 2 or _replica.actor_ids().size() != 3:
		return false
	var saved: Dictionary[String, int] = {}
	for fighter: StarterEncounter.Fighter in returned.others:
		saved[String(fighter.id)] = int(fighter.hp.native_at_scale(0))
	var site_tick: int = _return_facts["exit_tick"] + 30
	var later := "spawn/10:after_exit/%d" % site_tick
	var exit := _markers[-1]
	var exit_cell := Vector2i(floori(exit.x / WorldExploration.EXPLORATION_CELL), floori(exit.y / WorldExploration.EXPLORATION_CELL))
	if (saved != {String(RESIDENT): 20, later: 14} or _replica.actor_ids() != ["guest", later, String(RESIDENT)]
			or exit_cell not in snapshot.explored):
		return false
	_return_facts["reentry_tick"] = snapshot.tick
	_return_facts["reentry_hp"] = saved
	_return_facts["exit_cell_retained"] = true
	_present(returned, GARDEN, "Silent Garden / Re-entered")
	return _link.send(peer, ADMISSION, EPOCH, 4, NativeAdmissionMessage.leave()) == OK


func _host_verdict() -> bool:
	var world := _authority.activity.snapshot()
	var resident: Array = world.actors.get(RESIDENT, [])
	var added: Array = world.actors.get(_new_resident, [])
	var returned := _snapshot()
	_return_facts = {"exit_tick": _exit_tick, "legs": _closed_legs, "final_tick": _exit_tick + ABSENT_STEPS,
		"final_ack": returned.acknowledged, "spawned_while_empty": _new_spawn_tick,
		"reentry_tick": _reentry_tick, "stale_exit_refused": _stale_exit_refused,
		"reentry_hp": {String(RESIDENT): 20, String(_new_resident): 14},
		"resident_retained": not resident.is_empty() and resident[2] == "20",
		"later_resident": not added.is_empty() and added[2] == "14"}
	var body := JSON.stringify({"state": world, "return": _return_facts}, "", true, true)
	_return_facts["world_digest"] = body.sha256_text()
	if not _capture.is_empty():
		var file := FileAccess.open(_capture.path_join("return.json"), FileAccess.WRITE)
		if file == null:
			return false
		file.store_string(body)
		file.close()
	return (_first_pair_ok and _closed_legs.size() == 3 and _exit_tick >= 760
		and _new_spawn_tick == _exit_tick + 30 and world.tick == _reentry_tick
		and _reentry_tick == _exit_tick + ABSENT_STEPS + 1 and _stale_exit_refused
		and _party.view(GUEST, CombatInstant.at_tick(_reentry_tick)).realm == GARDEN
		and returned.acknowledged == 5 and _return_facts["resident_retained"] and _return_facts["later_resident"])


func _finish(passed: bool) -> void:
	if not _ending:
		if not passed:
			var diagnostics := {"walking": _walking, "first_pair": _first_pair_ok,
				"closed_legs": _closed_legs, "seen_legs": _seen_legs, "exit": _exit_tick,
				"reentry": _reentry_tick, "native_sequence": _guest_sequence}
			if _role == "host" and _party != null:
				var state := _snapshot()
				diagnostics["last"] = [state.tick, state.acknowledged, state.position.x, state.position.y]
				diagnostics["waypoints"] = _markers.map(func(at: RealmSweep.Point) -> Array: return [at.x, at.y])
			print("WP18_EXIT_DIAGNOSTIC ", JSON.stringify(diagnostics))
		print("WP18_EXIT ", JSON.stringify(_return_facts))
	super._finish(passed)
