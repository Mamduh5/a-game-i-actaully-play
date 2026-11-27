extends "res://dev/fixtures/wp25_native_passage_probe.gd"
## Inhabited and unviewed realms step on the accepted native passage clock.

const ARCHIVE := &"inverted_archive"
const RESIDENT := &"spawn/7:arrival/1"
const LEGION := &"archive/legion"
const WILD := &"archive/wildborn"
const SITE := &"arrival"

var _trace: Array[Dictionary] = []
var _world_facts: Dictionary = {}
var _display: StarterEncounterView
var _caption: Label
var _capture: String
var _ending: bool
var _garden_unviewed: bool


func _ready() -> void:
	_capture = OS.get_environment("AGIP_WP18_CAPTURE")
	super._ready()


func _start_run() -> bool:
	if not super._start_run():
		return false
	_rooms[ARCHIVE] = WorldExploration.create(WorldTopology.generate_optional(SEED, ARCHIVE), [HOST, GUEST])
	var activity := WorldActivity.new(_kernel, SEED)
	for room: WorldExploration in _rooms.values():
		if not activity.register_realm(room):
			return false
	if not activity.track_player(HOST) or not activity.track_player(GUEST):
		return false
	var at := _rooms[ARCHIVE].module_center(WorldTopology.ENTRY)
	if (not activity.introduce_enemy(LEGION, ARCHIVE, _foe(&"legion", [&"wildborn"], 10, 2), _offset(at, -16))
			or not activity.introduce_enemy(WILD, ARCHIVE, _foe(&"wildborn", [&"legion"], 30, 12), _offset(at, 16))):
		return false
	var site := WorldActivity.SpawnSite.new()
	site.realm = GARDEN
	site.id = SITE
	site.first_tick = 1
	site.period = 1
	site.limit = 1
	site.rules = _foe(&"garden", [], 20, 1)
	at = _rooms[GARDEN].module_center(WorldTopology.ENTRY)
	site.positions = [_offset(at, 24), _offset(at, -24)]
	_authority.activity = activity
	return activity.schedule_spawn(site)


func _close_and_publish() -> bool:
	if _baseline == 1:
		_garden_unviewed = _unviewed(_rooms[GARDEN])
	return super._close_and_publish()


func _arrival_fighters(scope: RecipientView.Scope, actors: Array[RecipientView.Actor], tick: int) -> StarterEncounter.View:
	if scope.realm != GARDEN:
		return null
	var settled := _authority.activity.snapshot()
	var resident: Array = settled.actors.get(RESIDENT, [])
	if resident.is_empty() or resident[0] != GARDEN:
		return null
	var pose := _party.view(GUEST, CombatInstant.at_tick(tick)).position
	var at := _rooms[GARDEN].geometry().circle_center(RESIDENT, 0)
	var clear := _rooms[GARDEN].geometry().certify_frozen_path(GARDEN, pose, at, 0.0, WorldExploration.BLOCKER)
	if clear == null or not clear.contacts.is_empty() or not clear.unresolved.is_empty():
		return null
	scope.actors[RESIDENT] = true
	actors.append(_actor(RESIDENT, GARDEN, at))
	var view := _living_view(GUEST, GARDEN, tick)
	view.others.append(_fighter(RESIDENT, GARDEN, true))
	_world_facts["arrived_with_resident"] = true
	_world_facts["resident_x"] = at.x
	_trace.append({"state": settled, "spawns": _authority.world_frame.spawns, "arrival": String(GARDEN)})
	return view


func _host_verdict() -> bool:
	if not super._host_verdict() or _trace.size() != 1:
		return false
	var world := _authority.activity.snapshot()
	var kills: Array[Array] = []
	for wave: CombatKernel.WaveResult in _authority.world_frame.combat:
		for hit: CombatKernel.Hit in wave.eliminations:
			kills.append([hit.target, hit.target_life, hit.origin.owner])
	var host := _host_scope()
	var host_filtered := (host != null and host.actors.keys() == [String(HOST)]
		and host.encounter != null and host.encounter.others.is_empty()
		and host.party == {"host": "living", "guest": "living"})
	var no_archive_view := _unviewed(_rooms[ARCHIVE])
	_trace.append({"state": world, "spawns": _authority.world_frame.spawns, "kills": kills,
		"host_fog": _rooms[OUTSIDE].view(HOST), "guest_fog": _rooms[GARDEN].view(GUEST)})
	var body := JSON.stringify(_trace, "", true, true)
	_world_facts["digest"] = body.sha256_text()
	_world_facts["faction_kills"] = kills
	_world_facts["spawned_at_arrival"] = _garden_unviewed and _trace[0].spawns == [[SITE, RESIDENT]]
	_world_facts["draws"] = world.rng[&"world-spawn/arrival"][1]
	_world_facts["host_filtered"] = host_filtered
	_world_facts["archive_unviewed"] = no_archive_view
	if not _capture.is_empty():
		var output := FileAccess.open(_capture.path_join("world.json"), FileAccess.WRITE)
		if output == null:
			return false
		output.store_string(body)
		output.close()
	if host_filtered:
		_present(host.encounter, OUTSIDE, "Overworld / Host")
	return (_world_facts["arrived_with_resident"] and _world_facts["spawned_at_arrival"] and host_filtered
		and no_archive_view and _world_facts["draws"] == 1 and kills == [[LEGION, 1, WILD]]
		and _authority.world_frame.spawns == [[SITE, &"full"]])


func _host_scope() -> RecipientView.Snapshot:
	var tick := _authority.next_tick() - 1
	var scope := RecipientView.Scope.new()
	scope.seat = HOST
	scope.realm = OUTSIDE
	var actors := _seat_actors(CombatInstant.at_tick(tick))
	var view := _living_view(HOST, OUTSIDE, tick)
	view.others.append(_fighter(GUEST, GARDEN, false))
	for id: StringName in [RESIDENT, WILD]:
		var realm := GARDEN if id == RESIDENT else ARCHIVE
		var fighter := _fighter(id, realm, true)
		actors.append(_actor(id, realm, fighter.at))
		view.others.append(fighter)
	# Submit the out-of-realm actors as a negative control for the realm filter.
	for actor: RecipientView.Actor in actors:
		scope.actors[actor.id] = true
	return RecipientView.read(RecipientView.pack(scope, EPOCH, 1, tick, 1, "0", _party.status_ids(),
		actors, [], _rooms[OUTSIDE], ReplicationMessage.MAX_BODY, &"", {}, view))


func _unviewed(room: WorldExploration) -> bool:
	for seat: StringName in [HOST, GUEST]:
		var visible: Array[Vector2i] = room.view(seat)["visible"]
		if not visible.is_empty():
			return false
	return true


func _receive_view(peer: ENetPacketPeer, frame: NativeSessionFrame, body: PackedByteArray) -> bool:
	var view := RecipientView.read(body)
	if view == null:
		return false
	if view.baseline == 1:
		if body.get_string_from_utf8().contains(String(RESIDENT)):
			return false
		_world_facts["resident_hidden_before_entry"] = true
		return super._receive_view(peer, frame, body)
	if (_replica.receive_frame(frame) != GuestReplica.Acceptance.APPLIED or view.baseline != 2 or view.tick != 1
			or view.realm != String(GARDEN) or view.party != {"host": "living", "guest": "living"}
			or _replica.actor_ids() != ["guest", String(RESIDENT)] or view.explored.is_empty()):
		return false
	var local := _replica.encounter_view(GUEST, view.tick)
	if local == null or local.others.size() != 1 or local.others[0].hp.native_at_scale(0) != 20:
		return false
	_facts["arrival_realm"] = view.realm
	_facts["visible"] = _replica.actor_ids()
	_facts["party"] = view.party
	_facts["arrival_cell_seen"] = true
	_world_facts["resident_x"] = local.others[0].at.x
	_world_facts["resident_hp"] = local.others[0].hp.native_at_scale(0)
	_world_facts["archive_hidden"] = not body.get_string_from_utf8().contains("archive/")
	_frames[RELIABLE] = true
	_present(local, GARDEN, "Silent Garden / Guest")
	var movement := _movement.issue(PlayerCommand.new(PlayerCommand.MOVE_AXES, 1.0))
	return (_world_facts["archive_hidden"] and _link.send(peer, SEQUENCED, EPOCH, view.baseline, movement) == OK
		and _link.send(peer, RELIABLE, EPOCH, view.baseline, _sent_click) == OK)


func _living_view(id: StringName, realm: StringName, tick: int) -> StarterEncounter.View:
	var view := StarterEncounter.View.new()
	view.tick = tick
	view.player = _fighter(id, realm, false)
	view.barrier = Quantity.from_count(0)
	return view


func _fighter(id: StringName, realm: StringName, enemy: bool) -> StarterEncounter.Fighter:
	var fighter := StarterEncounter.Fighter.new()
	var geometry := _rooms[realm].geometry()
	var state := _kernel.actor_vitals(id)
	fighter.id = id
	fighter.at = geometry.circle_center(id, 0)
	fighter.radius = geometry.circle_radius(id, 0)
	fighter.hp = state.hp
	fighter.maximum = state.maximum
	fighter.enemy = enemy
	return fighter


func _present(view: StarterEncounter.View, realm: StringName, title: String) -> void:
	if _capture.is_empty() or DisplayServer.get_name() == "headless":
		return
	if _display != null:
		_display.queue_free()
		_caption.queue_free()
	_display = StarterEncounterView.new()
	var point := Vector2(view.player.at.x, view.player.at.y)
	var cells: Array[Vector2i] = [Vector2i((point / WorldTopology.MODULE_SIZE).floor())]
	var layout := WorldTopology.generate(SEED) if realm == OUTSIDE else WorldTopology.generate_optional(SEED, realm)
	var floor := layout.realize(WorldExploration.SEALED_BLOCKER)
	_display.scale = Vector2.ONE * 1.55
	_display.position = Vector2(640, 360) - point * _display.scale
	add_child(_display)
	var outside_view := point + Vector2(0, 480)
	_display.prepare_floor(cells, StarterEncounterView.section_edges(cells, floor), outside_view, outside_view)
	_display.display(view)
	_caption = Label.new()
	_caption.position = Vector2(430, 82)
	_caption.add_theme_font_size_override("font_size", 29)
	_caption.text = title
	add_child(_caption)


func _finish(passed: bool) -> void:
	if _ending:
		return
	_ending = true
	set_process(false)
	if _display != null:
		await RenderingServer.frame_post_draw
		passed = (get_viewport().get_texture().get_image().save_png(_capture.path_join("view.png")) == OK
			and passed)
	print("WP18_SPLIT ", JSON.stringify(_world_facts))
	super._finish(passed)


static func _foe(faction: StringName, enemies: Array[StringName], hp: int, damage: int) -> WorldEnemy.Rules:
	var rules := WorldEnemy.Rules.new()
	rules.faction = faction
	rules.foes = enemies
	rules.family = &"fixture/faction"
	rules.hp = Quantity.from_count(hp)
	rules.damage = Quantity.from_count(damage)
	rules.radius = 4.0
	rules.sight = 48.0
	rules.attack_range = 40.0
	rules.attack_radius = 6.0
	rules.windup_ticks = 1
	rules.recovery_ticks = 6
	return rules


static func _offset(point: RealmSweep.Point, dx: float) -> RealmSweep.Point:
	return RealmSweep.Point.new(point.x + dx, point.y)
