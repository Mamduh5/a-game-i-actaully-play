extends Node2D
## Controlled display and ordinary manual input for the two Vault surfaces.

const SEAT := &"acrobat"
const RUN := &"c04-vault"
const REALM := WorldTopology.OVERWORLD
const SOLID := &"fixture/obstacle"

var _stage := StarterEncounterView.new()
var _router := PlayerInputRouter.new()
var _encounter: StarterEncounter
var _caption := Label.new()
var _capture: String
var _low := true
var _sequence: int
var _committed := false
var _warning := false
var _capture_fault := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_capture = args[0] if not args.is_empty() else ""
	_low = args.size() < 2 or args[1] == "low"
	RenderingServer.set_default_clear_color(Color("#202b29"))
	_stage.position = Vector2(435, 148)
	_stage.scale = Vector2.ONE * 1.55
	add_child(_stage)
	_caption.position = Vector2(435, 82)
	_caption.add_theme_font_size_override("font_size", 29)
	_caption.text = "Vault · low obstacle" if _low else "Vault · sealed obstacle"
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
	var build := StarterEncounter.Build.new()
	build.preparation = RunPreparation.select(catalog, &"H02", &"W01", [&"", &""], slots, {})
	build.powers = RunRewardQueue.begin(build.preparation, RunRandom.new(setup.seed), SEAT)
	build.start = RealmSweep.Point.new(62, 128)
	build.maximum_hp = Quantity.from_count(100)
	var world := WorldExploration.create(WorldTopology.generate(setup.seed), [SEAT])
	if not world.place_route_solid(SOLID, RealmSweep.Point.new(94, 128), 4.0, null, _low):
		return false
	_encounter = StarterEncounter.assemble(setup, SEAT, world, {SEAT: build})
	if _encounter == null:
		return false
	_stage.prepare([Vector2i.ZERO], world.geometry(), [SOLID], Vector2(256, 128), Vector2(216, 192))
	var foe := WorldEnemy.Rules.new()
	foe.faction = &"fixture"
	foe.foes = [WorldEnemy.PARTY]
	foe.family = &"fixture/ground-warning"
	foe.hp = Quantity.from_count(100)
	foe.damage = Quantity.from_count(16)
	foe.radius = 8
	foe.sight = 160
	foe.attack_range = 125
	foe.attack_radius = 40
	foe.windup_ticks = 7
	foe.recovery_ticks = 40
	foe.ground_only = true
	return _encounter.place_enemy(&"foe", foe, RealmSweep.Point.new(159, 76))


func _physics_process(_delta: float) -> void:
	var tick := _encounter.next_tick()
	if tick == 2 and _warning:
		_click()
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
		_committed = _committed or outcome.get("manual", false)
	var view := _encounter.view_for(SEAT)
	_stage.display(view)
	if tick == 1 or tick == 16:
		set_physics_process(false)
		if tick == 1:
			_warning = not view.threats.is_empty()
			await _snap("warning.png")
			set_physics_process(true)
		else:
			await _snap("landed.png")
			var correct_x := 126.0 if _low else 76.0
			_finish(_warning and _committed and not _capture_fault and absf(view.player.at.x - correct_x) < 0.01
				and view.player.hp.native_at_scale(0) == 100 and _encounter.movement_state(SEAT, 1, 17).permits_prediction)


func _click() -> void:
	var point := _stage.get_global_transform_with_canvas() * Vector2(210, 128)
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
	await RenderingServer.frame_post_draw
	_capture_fault = _capture_fault or get_viewport().get_texture().get_image().save_png(_capture.path_join(name)) != OK


func _finish(passed: bool) -> void:
	set_physics_process(false)
	var final := _encounter.view_for(SEAT) if _encounter != null else null
	print("C04_VAULT ", JSON.stringify({"passed": passed, "low": _low, "warning": _warning,
		"sequence": _sequence, "committed": _committed, "x": final.player.at.x if final != null else 0,
		"hp": final.player.hp.native_at_scale(0) if final != null else 0}))
	get_tree().quit(0 if passed else 1)
