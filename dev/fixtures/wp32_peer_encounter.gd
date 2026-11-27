extends "res://dev/fixtures/wp06_session_probe.gd"
## A real-time fixture with separate renderers and policies for host and guest.

const Screen := preload("res://dev/fixtures/wp32_peer_screen.gd")
const ROSTER: CatalogBundle = preload("res://src/catalog/starter_roster.tres")
const HOST := &"host"
const GUEST := &"guest"
const RUN := &"wp32-peer-encounter"
const REALM := WorldTopology.OVERWORLD
const SEED := 3207
const Kinds := ReplicationMessage.Kind
const CELLS: Array[Vector2i] = [Vector2i.ZERO, Vector2i.RIGHT]
const PASSAGE := Vector2(256, 135)
const GOAL := Vector2(454, 128)
const SNAPSHOT_INTERVAL := 3

var _encounter: StarterEncounter
var _floor: WorldExploration
var _bridge: HostMovementBridge
var _movement := GuestMovement.new()
var _replica := GuestReplica.new()
var _screen: Screen
var _store := ProfileStore.new()
var _trace: FileAccess
var _profile_id: String
var _preset: String
var _peer: ENetPacketPeer
var _connection: int
var _baseline := 1
var _published: int
var _movement_packet: int
var _reliable_packet: int
var _local_seq: int
var _started := false
var _ending := false
var _passed := false
var _failure: String
var _last_view_tick := -1
var _last_move_ack: int
var _sent_views: int
var _manuals: Dictionary[StringName, int] = {}
var _finishing := false


func _ready() -> void:
	set_physics_process(false)
	super._ready()
	if not is_processing():
		return
	_deadline = Time.get_ticks_msec() + 40000
	var args := OS.get_cmdline_user_args()
	var options: Variant = JSON.parse_string(args[8]) if args.size() == 9 else null
	_preset = OS.get_environment("AGIP_WP32_PRESET")
	_profile_id = "wp32-" + _role
	if (not options is Dictionary or not options.get("python") is String or not options.get("policy") is String
			or not options.get("output") is String or _preset not in ["sword", "bow"]
			or OS.has_feature("server") or DisplayServer.get_name() == "headless"
			or _store.open(_profile_id) != ProfileStore.OpenResult.OPENED):
		_fail("peer setup")
		return
	var output: String = options["output"]
	_trace = FileAccess.open(output.path_join("peer.jsonl"), FileAccess.WRITE)
	_screen = Screen.new()
	add_child(_screen)
	if _trace == null or not _screen.start(_role, _preset, options["python"], options["policy"], output):
		_fail("screen or policy setup")
		return
	if _role == "host" and not _assemble():
		_fail("host encounter setup")
		return
	set_physics_process(true)


func _assemble() -> bool:
	var catalog := ROSTER.compile()
	var setup := RunSetup.new()
	setup.role = RunSetup.Role.HOST
	setup.run_id = RUN
	setup.authority_id = HOST
	setup.seed = SEED
	setup.epoch = EPOCH
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = catalog.revision
	setup.challenge_id = &"encounter-fixture"
	setup.initial_realms = {HOST: REALM, GUEST: REALM}
	_floor = WorldExploration.create(WorldTopology.generate(SEED), [HOST, GUEST])
	var other := "bow" if _preset == "sword" else "sword"
	var builds: Dictionary[StringName, StarterEncounter.Build] = {
		HOST: _build(catalog, HOST, _preset, RealmSweep.Point.new(55, 86)),
		GUEST: _build(catalog, GUEST, other, RealmSweep.Point.new(62, 169)),
	}
	_encounter = StarterEncounter.assemble(setup, HOST, _floor, builds)
	if _encounter == null:
		return false
	_bridge = HostMovementBridge.new(_encounter)
	var rules := WorldEnemy.Rules.new()
	rules.faction = &"sparring"
	rules.foes = [WorldEnemy.PARTY]
	rules.family = &"fixture/sweep"
	rules.hp = Quantity.from_count(240)
	rules.damage = Quantity.from_count(16)
	rules.sight = 154.0
	rules.radius = 12.0
	rules.stride = 0.58
	rules.attack_range = 103.0
	rules.attack_radius = 26.0
	rules.windup_ticks = 39
	rules.recovery_ticks = 78
	if (not _encounter.place_enemy(&"near", rules, RealmSweep.Point.new(155, 160))
			or not _encounter.place_enemy(&"far", rules, RealmSweep.Point.new(369, 123))
			or not _encounter.place_enemy(&"flank", rules, RealmSweep.Point.new(421, 158))):
		return false
	_screen.stage.prepare_floor(CELLS, StarterEncounterView.section_edges(CELLS, _floor.geometry()), PASSAGE, GOAL)
	_screen.present(_encounter.view_for(HOST))
	return true


static func _build(catalog: DefinitionCatalog, seat: StringName, preset: String,
		at: RealmSweep.Point) -> StarterEncounter.Build:
	var sword := preset == "sword"
	var hero := &"H01" if sword else &"H03"
	var weapon := &"W01" if sword else &"W02"
	var runes: Array[StringName] = [&"R02" if sword else &"R01", &"R03"]
	var slots: Array[StringName] = []
	slots.resize(RunPreparation.CANDIDATE_SLOTS)
	slots.fill(&"")
	slots[0] = &"P03" if sword else &"P02"
	if not sword:
		slots[1] = &"P14"
	var licensed: Dictionary[StringName, bool] = {&"P14": not sword}
	var prep := RunPreparation.select(catalog, hero, weapon, runes, slots, licensed)
	if prep == null:
		return null
	var powers := RunRewardQueue.begin(prep, RunRandom.new(SEED), seat)
	var waiting: Array[StringName] = [slots[0]]
	if not sword:
		waiting.append(slots[1])
	for tick: int in range(1, 65):
		if waiting.is_empty():
			break
		var offer := powers.read_offer(powers.earn(tick))
		if offer == null:
			return null
		for power: StringName in waiting:
			if offer.options.has(power):
				powers.select(offer.ordinal, power)
				waiting.erase(power)
				break
	if not waiting.is_empty():
		return null
	var build := StarterEncounter.Build.new()
	build.preparation = prep
	build.powers = powers
	build.start = at
	build.maximum_hp = Quantity.from_count(100)
	return build


func _run_host() -> void:
	var batch := _session.pump()
	_admitted += batch.admitted.size()
	_rejected += batch.rejected
	_departures += batch.departures
	_lost += batch.lost_seats.size()
	if batch.failure or _admitted > 1 or _rejected != 0 or _lost != 0:
		_fail("native host session")
		return
	for connection: int in batch.admitted:
		_connection = connection
		if not _send_baseline():
			_fail("initial host scope")
			return
	for command: NativeSessionHost.Command in batch.commands:
		if not _admit(command):
			_fail("host command")
			return
	if _departures == 1 and not _closing:
		_closing = true
		print("WP06_SESSION_PHASE host-draining")
		_session.request_close()
	if _closing and not _session.is_open():
		_finish(_passed)


func _admit(command: NativeSessionHost.Command) -> bool:
	var wire := ReplicationMessage.read(command.frame)
	if wire == null:
		return false
	match wire.kind:
		Kinds.MOVEMENT:
			var result := _bridge.submit(_encounter, command)
			_started = _started or result == RunAuthority.Admission.QUEUED
			return result in [RunAuthority.Admission.QUEUED, RunAuthority.Admission.DUPLICATE, RunAuthority.Admission.STALE_SEQUENCE]
		Kinds.INTERACTION:
			return _bridge.submit_interaction(command) == RunAuthority.Admission.QUEUED
		Kinds.RESYNC:
			if wire.body.size() != 16 or wire.body.decode_s64(0) != EPOCH:
				return false
			_baseline += 1
			return _send_baseline()
	return false


func _physics_process(_delta: float) -> void:
	if _ending or _screen == null:
		return
	if _screen.failed():
		_fail("visible policy")
		return
	if _role == "host" and _started:
		_host_step()
	elif _role == "guest" and _last_view_tick >= 0:
		_guest_step()


func _host_step() -> void:
	var tick := _encounter.next_tick()
	for command: PlayerCommand in _screen.commands(tick):
		_local_seq += 1
		var intent := RunIntent.new(RUN, EPOCH, REALM, HOST, tick, _local_seq, command.action, command)
		if _encounter.submit(HOST, intent) != RunAuthority.Admission.QUEUED:
			_fail("local admission")
			return
	if not _encounter.close_tick() or not _encounter.fault().is_empty():
		_fail("host tick")
		return
	var result := _encounter.closed_result()
	var lifecycle := false
	for outcome: Dictionary in result["outcomes"]:
		if outcome.get("manual") == true:
			var seat: StringName = outcome["seat"]
			_manuals[seat] = _manuals.get(seat, 0) + 1
		lifecycle = lifecycle or outcome.get("eliminated") == true
	var home := _encounter.view_for(HOST)
	var guest := _encounter.view_for(GUEST)
	_screen.present(home)
	_record({"tick": tick, "accepted": result["accepted"], "outcomes": result["outcomes"],
		"seat_poses": [_xy(home.player.at), _xy(guest.player.at)], "guest_hp": guest.player.hp.native_at_scale(0)})
	_passed = guest.cleared and _at_goal(home.player.at) and _at_goal(guest.player.at)
	_ending = _passed or guest.defeated
	if tick % SNAPSHOT_INTERVAL == 0 or lifecycle or _ending:
		var state := _encounter.movement_state(GUEST, _baseline, tick + 1)
		if (not _publish(Kinds.STATE, state.pack())
				or not _send_view(guest, state, lifecycle or _ending)):
			_fail("closed state publication")
			return
	if _ending:
		_screen.capture("end.png")


func _guest_step() -> void:
	for command: PlayerCommand in _screen.commands(_last_view_tick):
		if MovementFrame.is_voluntary(command):
			if _movement.issue(command).is_empty():
				_fail("guest voluntary prediction")
				return
		elif command.action in PlayerCommand.RELIABLE_ACTIONS:
			var packet := _movement.interaction_packet(command)
			if not _send_guest(packet, RELIABLE):
				_fail("guest bound click")
				return
	var repeat := _movement.latest_packet()
	if not repeat.is_empty() and not _send_guest(repeat, SEQUENCED):
		_fail("guest motion send")
		return
	if not _movement.advance() and _movement.needs_baseline():
		_request_resync()
		return
	var pose := _movement.draw_position(0.50)
	var view := _replica.encounter_view(GUEST, _last_view_tick - 2, pose)
	if view != null:
		_screen.present(view)


func _send_baseline() -> bool:
	var reset := MovementBaseline.new()
	reset.realm = REALM
	reset.state = _encounter.movement_state(GUEST, _baseline, _encounter.next_tick())
	for edge: RealmOutline.Edge in StarterEncounterView.section_edges(CELLS, _floor.geometry()):
		var disclosed := GuestMovement.Blocker.new()
		disclosed.first = edge.first
		disclosed.last = edge.last
		reset.blockers.append(disclosed)
	return (_bridge.bind(1, _connection, EPOCH, RUN, EPOCH, REALM, GUEST, _baseline)
		and _publish(Kinds.BASELINE, reset.pack())
		and _send_view(_encounter.view_for(GUEST), reset.state, true))


func _send_view(view: StarterEncounter.View, state: MovementSnapshot, reliable: bool) -> bool:
	var payload := RecipientView.pack_encounter(view, state, REALM, _encounter.party_statuses(), _floor)
	if not _publish(Kinds.VIEW if reliable else Kinds.VIEW_STATE, payload):
		return false
	_sent_views += 1
	_record({"sent": _facts(view), "hash": ProfileMutation.sha256(payload), "reliable": reliable})
	return true


func _publish(kind: ReplicationMessage.Kind, payload: PackedByteArray) -> bool:
	if payload.is_empty():
		return false
	_published += 1
	return _session.send(_connection, ReplicationMessage.transport_kind(kind), _published,
		ReplicationMessage.pack(kind, payload)) == OK


func _guest_ready(peer: ENetPacketPeer) -> bool:
	_peer = peer
	return true


func _accept(peer: ENetPacketPeer, frame: NativeSessionFrame) -> bool:
	if frame.kind == ADMISSION:
		return super._accept(peer, frame)
	var wire := ReplicationMessage.read(frame)
	if wire == null or frame.generation != EPOCH or _guest_stage != 3:
		return false
	match wire.kind:
		Kinds.BASELINE:
			var reset := MovementBaseline.read(wire.body)
			if reset == null or reset.realm != REALM:
				return false
			var accepted := _movement.receive_frame(frame)
			if accepted == GuestMovement.Acceptance.STALE:
				return true
			if accepted != GuestMovement.Acceptance.APPLIED or not _replica.install_scope(reset.realm, reset.state):
				return false
			var edges: Array[RealmOutline.Edge] = []
			for disclosed: GuestMovement.Blocker in reset.blockers:
				var edge := RealmOutline.Edge.new()
				edge.first = disclosed.first
				edge.last = disclosed.last
				edges.append(edge)
			_screen.stage.prepare_floor(CELLS, edges, PASSAGE, GOAL)
			_frames[RELIABLE] = true
			return true
		Kinds.STATE:
			var movement := _movement.receive_frame(frame)
			if movement == GuestMovement.Acceptance.NEED_BASELINE:
				return _request_resync()
			if movement == GuestMovement.Acceptance.APPLIED:
				_frames[SEQUENCED] = true
				_last_move_ack = _movement.confirmed_scope().state.acknowledged
			return movement in [GuestMovement.Acceptance.APPLIED, GuestMovement.Acceptance.STALE]
		Kinds.VIEW, Kinds.VIEW_STATE:
			return _accept_view(frame, wire)
	return false


func _accept_view(frame: NativeSessionFrame, wire: ReplicationMessage) -> bool:
	var accepted := _replica.receive_frame(frame)
	if accepted != GuestReplica.Acceptance.APPLIED:
		return accepted in [GuestReplica.Acceptance.STALE, GuestReplica.Acceptance.NEED_BASELINE]
	var view := _replica.encounter_view(GUEST, RunAuthority.MAX_TICK)
	if view == null:
		return false
	_last_view_tick = view.tick
	_record({"received": _facts(view), "hash": ProfileMutation.sha256(wire.body), "movement_ack": _last_move_ack})
	if _ending:
		return true
	_screen.present(view)
	for ally: StarterEncounter.Fighter in view.others:
		if (ally.id == HOST and wire.kind == Kinds.VIEW and view.cleared
				and _at_goal(ally.at) and _at_goal(view.player.at)):
			_end_guest(true)
			break
	if view.defeated:
		_end_guest(false)
	return true


func _end_guest(passed: bool) -> void:
	_ending = true
	_passed = passed
	await _screen.capture("end.png")
	if _link.send(_peer, ADMISSION, EPOCH, 4, NativeAdmissionMessage.leave()) != OK:
		_fail("ordered guest leave")


func _request_resync() -> bool:
	var request := _movement.resync_request()
	return not request.is_empty() and _send_guest(request, RELIABLE)


func _send_guest(payload: PackedByteArray, lane: NativeSessionFrame.Kind) -> bool:
	if payload.is_empty():
		return false
	var sequence: int
	if lane == RELIABLE:
		_reliable_packet += 1
		sequence = _reliable_packet
	else:
		_movement_packet += 1
		sequence = _movement_packet
	return _link.send(_peer, lane, EPOCH, sequence, payload) == OK


func _fail(reason: String) -> void:
	_failure = reason
	_finish(false)


func _finish(passed: bool) -> void:
	if _finishing:
		return
	_finishing = true
	set_physics_process(false)
	if _screen != null:
		_screen.shutdown()
	if _trace != null:
		_trace.close()
	if not _store.identity().is_empty():
		_store.close()
	if _screen != null:
		passed = passed and _passed
		print("WP32_PEER ", JSON.stringify({"passed": passed, "role": _role, "preset": _preset, "profile": _profile_id,
			"closed_tick": _encounter.next_tick() - 1 if _encounter != null else _last_view_tick,
			"sent_views": _sent_views, "last_move_ack": _last_move_ack, "manuals": _manuals, "fault": _failure}))
	super._finish(passed)


func _record(row: Dictionary) -> void:
	_trace.store_line(JSON.stringify(row))


static func _at_goal(at: RealmSweep.Point) -> bool:
	return Vector2(at.x, at.y).distance_to(GOAL) <= 25.0


static func _xy(at: RealmSweep.Point) -> Array[float]:
	return [at.x, at.y]


static func _facts(view: StarterEncounter.View) -> Dictionary:
	var actors := {}
	for fighter: StarterEncounter.Fighter in view.others:
		actors[String(fighter.id)] = [_xy(fighter.at), QuantityCodec.encode(fighter.hp).hex_encode()]
	var warnings: Array[Array] = []
	for tell: WorldEnemy.Threat in view.threats:
		warnings.append([tell.impact_tick, tell.start_tick, _xy(tell.center), tell.radius])
	warnings.sort_custom(func(first: Array, second: Array) -> bool:
		return JSON.stringify(first) < JSON.stringify(second))
	var cues: Array[StringName] = []
	for cue: StarterCombat.Cue in view.cues:
		cues.append(cue.id)
	return {"tick": view.tick, "player": _xy(view.player.at), "hp": QuantityCodec.encode(view.player.hp).hex_encode(),
		"barrier": QuantityCodec.encode(view.barrier).hex_encode(), "actors": actors, "warnings": warnings,
		"cues": cues, "manual_ready": view.manual_ready, "cleared": view.cleared,
		"effects": [view.mines.size(), view.darts.size(), view.lances.size(), view.tethers.size(), view.familiars.size()]}
