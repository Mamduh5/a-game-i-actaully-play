extends Node2D
## Labeled H07 builds operated through the native encounter input route.

const SEAT := &"bloodbound"
const RUN := &"c05-bloodbound"
const REALM := WorldTopology.OVERWORLD

var _stage := StarterEncounterView.new()
var _router := PlayerInputRouter.new()
var _caption := Label.new()
var _encounter: StarterEncounter
var _capture: String
var _lethal: bool
var _sequence: int
var _low_before_offering: bool
var _capture_fault: bool
var _manuals: Array[bool] = []
var _weapon_ticks: Array[int] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[1] not in ["safe", "lethal"]:
		_finish(false)
		return
	_capture = args[0]
	_lethal = args[1] == "lethal"
	RenderingServer.set_default_clear_color(Color("#262626"))
	_stage.position = Vector2(435, 148)
	_stage.scale = Vector2.ONE * 1.55
	add_child(_stage)
	_caption.position = Vector2(435, 78)
	_caption.add_theme_font_size_override("font_size", 25)
	add_child(_caption)
	_router.world_from_viewport = _stage.world_from_viewport
	add_child(_router)
	if not _begin():
		_finish(false)


func _begin() -> bool:
	var catalog: DefinitionCatalog = load("res://src/catalog/starter_roster.tres").compile()
	var setup := RunSetup.new()
	setup.run_id = RUN
	setup.epoch = 1
	setup.authority_id = SEAT
	setup.seed = 3207
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = catalog.revision
	setup.challenge_id = &"normal"
	setup.initial_realms = {SEAT: REALM}
	var slots: Array[StringName] = []
	slots.resize(RunPreparation.CANDIDATE_SLOTS)
	slots.fill(&"")
	var upgrades: Dictionary[StringName, int] = {}
	if not _lethal:
		upgrades[&"maximum_hp"] = 2500
	var build := StarterEncounter.Build.new()
	build.preparation = RunPreparation.select(catalog, &"H07", &"W01", [&"", &""], slots, {&"H07": true}, upgrades)
	build.powers = RunRewardQueue.begin(build.preparation, RunRandom.new(setup.seed), SEAT)
	build.start = RealmSweep.Point.new(62, 128)
	build.maximum_hp = Quantity.from_count(100)
	var floor := WorldExploration.create(WorldTopology.generate(setup.seed), [SEAT])
	_encounter = StarterEncounter.assemble(setup, SEAT, floor, {SEAT: build})
	if _encounter == null:
		return false
	var solids: Array[StringName] = []
	_stage.prepare([Vector2i.ZERO], floor.geometry(), solids, Vector2(256, 128), Vector2(216, 192))
	var foe := WorldEnemy.Rules.new()
	foe.faction = &"fixture"
	foe.foes = [WorldEnemy.PARTY]
	foe.family = &"fixture/bloodbound-strike"
	foe.hp = Quantity.from_count(200)
	foe.damage = Quantity.from_count(75 if _lethal else 1)
	foe.radius = 8.0
	foe.sight = 160.0
	foe.attack_range = 103.0
	foe.attack_radius = 26.0
	foe.windup_ticks = 7 if _lethal else 180
	foe.recovery_ticks = 100
	return _encounter.place_enemy(&"foe", foe, RealmSweep.Point.new(133, 128))


func _physics_process(_delta: float) -> void:
	var tick := _encounter.next_tick()
	if (_lethal and tick == 9) or (not _lethal and tick in [2, 3]):
		_click_manual()
	for command: PlayerCommand in _router.drain():
		_sequence += 1
		var intent := RunIntent.new(RUN, 1, REALM, SEAT, tick, _sequence, command.action, command)
		if _encounter.submit(SEAT, intent) != RunAuthority.Admission.QUEUED:
			_finish(false)
			return
	if not _encounter.close_tick() or not _encounter.fault().is_empty():
		_finish(false)
		return
	for outcome: Dictionary in _encounter.closed_result().outcomes:
		if outcome.has("manual"):
			_manuals.append(outcome["manual"])
		if outcome.has("weapon"):
			_weapon_ticks.append(tick)
	var view := _encounter.view_for(SEAT)
	_stage.display(view)
	var hp_hundredths: int = view.player.hp.native_at_scale(2)
	var empowered := view.cues.any(func(cue: StarterCombat.Cue) -> bool: return cue.id == StarterCombatRules.CRIMSON_OFFERING)
	_caption.text = "The Bloodbound\n%.2f HP" % (float(hp_hundredths) / 100.0)
	if empowered:
		_caption.text += "  ·  Crimson Empowerment"
	if _lethal and tick == 8:
		_low_before_offering = hp_hundredths == 2500 and view.manual_ready
	if not _lethal and tick == 4:
		await _snap("empowered.png")
	if _lethal and tick == 9:
		await _snap("lethal.png")
		_finish(_manuals == [true] and _weapon_ticks == [1] and _low_before_offering
			and hp_hundredths == 0 and view.defeated and not empowered)
	elif not _lethal and tick == 48:
		_finish(_manuals == [true, false] and _weapon_ticks == [1, 48] and hp_hundredths == 9375
			and view.others[0].hp.native_at_scale(0) == 152 and empowered and not view.defeated)


func _click_manual() -> void:
	var point := _stage.get_global_transform_with_canvas() * Vector2(62, 128)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)


func _snap(name: String) -> void:
	if _capture.is_empty() or DisplayServer.get_name() == "headless":
		return
	set_physics_process(false)
	await RenderingServer.frame_post_draw
	_capture_fault = _capture_fault or get_viewport().get_texture().get_image().save_png(_capture.path_join(name)) != OK
	set_physics_process(true)


func _finish(verified: bool) -> void:
	set_physics_process(false)
	var view := _encounter.view_for(SEAT) if _encounter != null else null
	var passed := verified and not _capture_fault
	print("C05_BLOODBOUND ", JSON.stringify({"passed": passed, "lethal": _lethal, "manuals": _manuals,
		"weapon_ticks": _weapon_ticks, "sequence": _sequence, "defeated": view != null and view.defeated,
		"hp_hundredths": view.player.hp.native_at_scale(2) if view != null else null,
		"foe_hp": view.others[0].hp.native_at_scale(0) if view != null and not view.others.is_empty() else null}))
	get_tree().quit(0 if passed else 1)
