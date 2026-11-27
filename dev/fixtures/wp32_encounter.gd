extends Node2D
## The authored loadouts and enemy placements are restricted to this fixture.

const Actuator := preload("res://dev/fixtures/visible_pilot/pilot_actuator.gd")
const Policy := preload("res://dev/fixtures/visible_pilot/pilot_policy_client.gd")
const ROSTER: CatalogBundle = preload("res://src/catalog/starter_roster.tres")
const SEAT := &"player"
const REALM := WorldTopology.OVERWORLD
const RUN := &"wp32-encounter"
const SEED := 3207
const ROCK := &"route_stone"
const PASSAGE := Vector2(256, 135)
const DESTINATION := Vector2(454, 128)
const PRESETS := ["sword", "bow", "staff"]
const MOVEMENT: Array[StringName] = [PlayerInputRouter.LEFT, PlayerInputRouter.RIGHT,
	PlayerInputRouter.UP, PlayerInputRouter.DOWN]
const MAX_TICKS := 2400

var _encounter: StarterEncounter
var _stage := StarterEncounterView.new()
var _router := PlayerInputRouter.new()
var _pilot := Policy.new()
var _actuator: Actuator
var _view: StarterEncounter.View
var _caption := Label.new()
var _status := Label.new()
var _prompt := Label.new()
var _trace: FileAccess
var _output: String
var _mode: String
var _preset := "sword"
var _seq: int
var _replay: Dictionary[int, Dictionary] = {}
var _family_hits: Dictionary[StringName, int] = {}
var _manual_uses: int
var _warning_ticks: int
var _enemy_damage: int
var _displacements: int
var _second_room := false
var _finishing := false
var _started := false
var _captured_warning := false
var _done_tick: int


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_preset = args[0]
	if args.size() == 5 and args[1] in ["pilot", "replay", "replay-outline"]:
		_mode = "replay" if args[1] == "replay-outline" else args[1]
		_stage.outline_only = args[1] == "replay-outline"
		_output = args[4]
		_started = true
	elif args.size() == 3 and args[1] == "observe":
		_output = args[2]
	elif args.size() > 1:
		_stop(&"arguments")
		return
	if _preset not in PRESETS or not _assemble():
		_stop(&"assembly")
		return
	RenderingServer.set_default_clear_color(Color("#1e2b29"))
	get_window().title = "A Game I Actually Play | Encounter fixture"
	add_child(_stage)
	_build_hud()
	_layout()
	get_viewport().size_changed.connect(_layout)
	_router.world_from_viewport = _stage.world_from_viewport
	add_child(_router)
	_actuator = Actuator.new(get_viewport(), MOVEMENT, false)
	if not _output.is_empty():
		_trace = FileAccess.open(_output.path_join("evidence.jsonl"), FileAccess.WRITE)
		if _trace == null:
			_stop(&"evidence")
			return
		if _mode == "pilot" and not _pilot.start(args[2], args[3]):
			_stop(&"policy")
			return
		if _mode == "replay" and not _read_replay(args[3]):
			_stop(&"replay")
			return
	_present()


func _assemble() -> bool:
	var world := WorldExploration.create(WorldTopology.generate(SEED), [SEAT])
	if world == null:
		return false
	if not world.place_route_solid(ROCK, RealmSweep.Point.new(217, 88), 13.0):
		return false
	var shift := world.move_route_solid(ROCK, RealmSweep.Point.new(256, 99))
	if shift == null or shift.motion.finish.x != 256.0 or shift.motion.finish.y != 99.0:
		return false
	var catalog := ROSTER.compile()
	var build := _loadout(catalog, SEAT, RealmSweep.Point.new(62, 128))
	if build == null:
		return false
	var setup := RunSetup.new()
	setup.run_id = RUN
	setup.authority_id = SEAT
	setup.seed = SEED
	setup.epoch = 1
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = catalog.revision
	setup.challenge_id = &"encounter-fixture"
	setup.initial_realms = {SEAT: REALM}
	_encounter = StarterEncounter.assemble(setup, SEAT, world, {SEAT: build})
	if _encounter == null:
		return false
	var rules := WorldEnemy.Rules.new()
	rules.faction = &"sparring"
	rules.foes = [WorldEnemy.PARTY]
	rules.family = &"fixture/sweep"
	rules.hp = Quantity.from_count(132)
	rules.damage = Quantity.from_count(16)
	rules.sight = 154.0
	rules.radius = 12.0
	rules.stride = 0.58
	rules.attack_range = 103.0
	rules.attack_radius = 26.0
	rules.windup_ticks = 39
	rules.recovery_ticks = 78
	if (not _encounter.place_enemy(&"near", rules, RealmSweep.Point.new(155, 128))
			or not _encounter.place_enemy(&"far", rules, RealmSweep.Point.new(369, 123))
			or not _encounter.place_enemy(&"flank", rules, RealmSweep.Point.new(421, 158))):
		return false
	_stage.prepare([Vector2i.ZERO, Vector2i.RIGHT], world.geometry(), [ROCK], PASSAGE, DESTINATION)
	return true


func _loadout(catalog: DefinitionCatalog, id: StringName, start: RealmSweep.Point) -> StarterEncounter.Build:
	var index := PRESETS.find(_preset)
	var hero: StringName = [&"H01", &"H03", &"H04"][index]
	var weapon: StringName = [&"W01", &"W02", &"W03"][index]
	var equipped: Array[StringName] = []
	equipped.assign([[&"R02", &"R03"], [&"R01", &"R03"], [&"R01", &"R02"]][index])
	var picked: Array[StringName] = []
	picked.assign([[&"P03"], [&"P02", &"P14"], [&"P04", &"P14"]][index])
	var slots: Array[StringName] = []
	slots.resize(RunPreparation.CANDIDATE_SLOTS)
	slots.fill(&"")
	var unlocked: Dictionary[StringName, bool] = {hero: true}
	for number: int in picked.size():
		var power := picked[number]
		slots[number] = power
		unlocked[power] = true
	var prep := RunPreparation.select(catalog, hero, weapon, equipped, slots, unlocked)
	if prep == null:
		return null
	var powers := RunRewardQueue.begin(prep, RunRandom.new(SEED), id)
	var waiting := picked.duplicate()
	for offer_tick: int in range(1, 65):
		if waiting.is_empty():
			break
		var ordinal := powers.earn(offer_tick)
		var offer := powers.read_offer(ordinal)
		if offer == null:
			break
		for power: StringName in waiting:
			if offer.options.has(power):
				powers.select(ordinal, power)
				waiting.erase(power)
				break
	if not waiting.is_empty():
		return null
	var build := StarterEncounter.Build.new()
	build.preparation = prep
	build.powers = powers
	build.start = start
	build.maximum_hp = Quantity.from_count(100)
	return build


func _physics_process(_seconds: float) -> void:
	if _finishing or _encounter == null:
		return
	var tick := _encounter.next_tick()
	var decision: Dictionary = {}
	if _mode == "pilot":
		if _pilot.failed():
			_stop(&"policy")
			return
		decision = _pilot.poll()
	elif _mode == "replay":
		decision = _replay.get(tick, {})
	if not decision.is_empty():
		if bool(decision.get("manual", true)) or not _actuator.apply(decision):
			_stop(&"input")
			return
		_record({"tick": tick, "decision": decision})
	var commands := _router.drain()
	if not _started:
		for command: PlayerCommand in commands:
			if command.action in [PlayerCommand.MOVE_TO, PlayerCommand.MANUAL] or (
					command.action == PlayerCommand.MOVE_AXES and (command.x != 0 or command.y != 0)):
				_started = true
				break
		if not _started:
			return
	for command: PlayerCommand in commands:
		_seq += 1
		var intent := RunIntent.new(RUN, 1, REALM, SEAT, tick, _seq, command.action, command)
		if _encounter.submit(SEAT, intent) != RunAuthority.Admission.QUEUED:
			_stop(&"admission")
			return
	if not _encounter.close_tick() or not _encounter.fault().is_empty():
		_stop(_encounter.fault() if not _encounter.fault().is_empty() else &"clock")
		return
	_present()
	_audit()
	if not _view.threats.is_empty() and not _captured_warning and not _output.is_empty():
		_captured_warning = true
		_capture("warning.png")
	if _view.defeated or _view.cleared and _at_destination():
		_stop(&"defeated" if _view.defeated else &"cleared")
	elif not _output.is_empty() and tick >= MAX_TICKS:
		_stop(&"timeout")
	elif _mode == "pilot" and not _pilot.pending():
		var observation := _visible_sample()
		if not _pilot.send(observation):
			_stop(&"observation")
			return
		_record({"tick": tick, "visible": observation})


func _present() -> void:
	_view = _encounter.view_for(SEAT)
	_stage.display(_view)
	var hp: Variant = _view.player.hp.native_at_scale(0)
	var barrier: Variant = _view.barrier.native_at_scale(0)
	var ability := "Ready" if _view.manual_ready else "Recovering"
	_status.text = "HP %s   Barrier %s   Ability %s" % [hp, barrier, ability]
	_second_room = _second_room or _view.player.at.x > 256.0
	_prompt.text = "Reach the marked circle" if _view.cleared else "Cross the passage and clear both rooms"
	if not _started:
		_prompt.text = "Move or cast to start"


func _visible_sample() -> Dictionary:
	var opponents: Array[Array] = []
	for actor: StarterEncounter.Fighter in _view.others:
		if actor.enemy:
			opponents.append(_pixel(Vector2(actor.at.x, actor.at.y)))
	var warnings: Array[Array] = []
	for tell: WorldEnemy.Threat in _view.threats:
		warnings.append([_pixel(Vector2(tell.center.x, tell.center.y)), roundi(tell.radius * _stage.scale.x)])
	return {"player": _pixel(Vector2(_view.player.at.x, _view.player.at.y)),
		"radius": roundi(_view.player.radius * _stage.scale.x), "enemies": opponents, "warnings": warnings,
		"manual_ready": _view.manual_ready, "goal": _pixel(DESTINATION), "passage": _pixel(PASSAGE)}


func _pixel(at: Vector2) -> Array[int]:
	var point := _stage.get_global_transform_with_canvas() * at
	return [roundi(point.x), roundi(point.y)]


func _at_destination() -> bool:
	var at := Vector2(_view.player.at.x, _view.player.at.y)
	return at.distance_to(DESTINATION) <= 16.0


func _audit() -> void:
	_warning_ticks += int(not _view.threats.is_empty())
	var result := _encounter.closed_result()
	for event: Dictionary in result["outcomes"]:
		if event.has("manual"):
			_manual_uses += int(event["manual"])
		if event.has("family") and event["damage"]:
			var family: StringName = event["family"]
			_family_hits[family] = int(_family_hits.get(family, 0)) + 1
			_enemy_damage += int(event["target"] == SEAT)
			_displacements += int(event["pushed"])
	_record({"tick": _view.tick, "accepted": result["accepted"], "outcomes": result["outcomes"]})


func _build_hud() -> void:
	var heading: String = ["The Undying · Sword", "The Conductor · Bow", "The Chronomancer · Staff"][PRESETS.find(_preset)]
	_make_label(_caption, 35, heading)
	_make_label(_status, 21, "")
	_make_label(_prompt, 23, "")
	var controls := Label.new()
	controls.name = "ControlHelp"
	_make_label(controls, 18, "WASD or right-click to move     Left-click to cast     Q to target")


func _make_label(label: Label, size: int, text: String) -> void:
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("#e6ece6"))
	add_child(label)


func _layout() -> void:
	var visible := get_viewport_rect().size
	var scale_to_fit := minf(visible.x / 586.0, visible.y / 465.0)
	_stage.scale = Vector2.ONE * scale_to_fit
	_stage.position = Vector2((visible.x - 512.0 * scale_to_fit) * 0.5, visible.y * 0.49 - 128.0 * scale_to_fit)
	_caption.position = Vector2(_stage.position.x, 24)
	_prompt.position = Vector2(_stage.position.x, _stage.position.y + 256 * scale_to_fit + 20)
	_status.position = Vector2(_stage.position.x, 67)
	var controls := get_node("ControlHelp") as Label
	controls.position = Vector2(_stage.position.x, _prompt.position.y + 32)


func _read_replay(path: String) -> bool:
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null:
		return false
	while not source.eof_reached():
		var line := source.get_line()
		if line.is_empty():
			continue
		var record: Variant = JSON.parse_string(line)
		if not record is Dictionary:
			return false
		if record.has("decision"):
			var tick := int(record.get("tick", 0))
			if tick <= 0 or tick > MAX_TICKS or _replay.has(tick) or not record["decision"] is Dictionary:
				return false
			_replay[tick] = record["decision"]
	return not _replay.is_empty()


func _record(row: Dictionary) -> void:
	if _trace != null:
		_trace.store_line(JSON.stringify(row))


func _capture(file: String) -> void:
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(_output.path_join(file))
	if result != OK:
		push_error("Encounter capture failed.")


func _stop(reason: StringName) -> void:
	if _finishing:
		return
	_finishing = true
	_pilot.close()
	if _actuator != null:
		_actuator.release()
	_done_tick = _view.tick if _view != null else 0
	var passed := reason == &"cleared" and _second_room
	var receipt := {"passed": passed, "reason": reason, "ticks": _done_tick, "preset": _preset,
		"manual": _manual_uses, "warning_ticks": _warning_ticks, "enemy_damage": _enemy_damage,
		"second_room": _second_room, "displacements": _displacements, "damage_by_family": _family_hits}
	print("WP32_ENCOUNTER ", JSON.stringify(receipt))
	if _trace != null:
		_trace.close()
	if not _output.is_empty():
		_prompt.text = "Encounter cleared" if passed else "Encounter ended"
		await _capture("end.png")
	if _output.is_empty() and reason in [&"cleared", &"defeated"]:
		_prompt.text = "Encounter cleared" if passed else "Encounter ended"
	else:
		get_tree().quit(0 if passed else 1)


func _exit_tree() -> void:
	_pilot.close()
