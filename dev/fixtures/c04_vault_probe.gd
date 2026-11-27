extends Node2D
## Controlled display and ordinary input for the C04 hero witnesses.

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
var _close_call := false
var _gravity := false
var _pulled := false
var _sequence: int
var _committed := false
var _warning := false
var _capture_fault := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_capture = args[0] if not args.is_empty() else ""
	_low = args.size() < 2 or args[1] == "low"
	_close_call = args.size() > 1 and args[1] == "close-call"
	_gravity = args.size() > 1 and args[1] == "gravity"
	RenderingServer.set_default_clear_color(Color("#202b29"))
	_stage.position = Vector2(435, 148)
	_stage.scale = Vector2.ONE * 1.55
	add_child(_stage)
	_caption.position = Vector2(435, 82)
	_caption.add_theme_font_size_override("font_size", 29)
	_caption.text = "Vault · low obstacle" if _low else "Vault · sealed obstacle"
	if _close_call:
		_caption.text = "The Acrobat"
	elif _gravity:
		_caption.text = "The Gravity Weaver"
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
	var hero := &"H05" if _gravity else &"H02"
	build.preparation = RunPreparation.select(catalog, hero, &"W01", [&"", &""], slots, {hero: true})
	build.powers = RunRewardQueue.begin(build.preparation, RunRandom.new(setup.seed), SEAT)
	build.start = RealmSweep.Point.new(62, 128)
	build.maximum_hp = Quantity.from_count(100)
	var world := WorldExploration.create(WorldTopology.generate(setup.seed), [SEAT])
	var solids: Array[StringName] = []
	if not _close_call and not _gravity:
		solids.append(SOLID)
	if not solids.is_empty() and not world.place_route_solid(SOLID, RealmSweep.Point.new(94, 128), 4.0, null, _low):
		return false
	_encounter = StarterEncounter.assemble(setup, SEAT, world, {SEAT: build})
	if _encounter == null:
		return false
	_stage.prepare([Vector2i.ZERO], world.geometry(), solids, Vector2(256, 128), Vector2(216, 192))
	var foe := WorldEnemy.Rules.new()
	foe.faction = &"fixture"
	foe.foes = [WorldEnemy.PARTY]
	foe.family = &"fixture/ground-warning"
	foe.hp = Quantity.from_count(100)
	foe.damage = Quantity.from_count(16)
	foe.radius = 8
	foe.sight = 160
	foe.attack_range = 125
	foe.attack_radius = 26 if _close_call else 40
	foe.windup_ticks = 39 if _close_call else 7
	foe.recovery_ticks = 40
	foe.ground_only = true
	var position := RealmSweep.Point.new(135, 128) if _close_call else RealmSweep.Point.new(159, 76)
	if _gravity:
		position = RealmSweep.Point.new(178, 128)
		foe.windup_ticks = 58
	return _encounter.place_enemy(&"foe", foe, position)


func _physics_process(_delta: float) -> void:
	var tick := _encounter.next_tick()
	if tick == 2 and _warning:
		if _close_call:
			_click(Vector2(105, 128), MOUSE_BUTTON_RIGHT)
		elif _gravity:
			_click(Vector2(142, 128), MOUSE_BUTTON_LEFT)
		else:
			_click(Vector2(210, 128), MOUSE_BUTTON_LEFT)
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
	if _gravity and tick > 1:
		_observe_gravity(tick, view)
	elif tick == 1 or tick == (40 if _close_call else 16):
		set_physics_process(false)
		if tick == 1:
			_warning = not view.threats.is_empty()
			await _snap("warning.png")
			set_physics_process(true)
		elif _close_call:
			var outcomes: Array = _encounter.closed_result()["outcomes"]
			var active := outcomes.has({"seat": SEAT, "close_call": true})
			_caption.text = "Close Call · movement and attack rate up" if active else "The Acrobat"
			await _snap("close-call.png")
			var speed := _encounter.movement_state(SEAT, 1, 41).speed
			_finish(active and _warning and not _capture_fault and speed == 120.0
				and view.player.hp.native_at_scale(0) == 100 and absf(view.player.at.x - 105.0) < 0.01)
		else:
			await _snap("landed.png")
			var correct_x := 126.0 if _low else 76.0
			_finish(_warning and _committed and not _capture_fault and absf(view.player.at.x - correct_x) < 0.01
				and view.player.hp.native_at_scale(0) == 100 and _encounter.movement_state(SEAT, 1, 17).permits_prediction)


func _observe_gravity(tick: int, view: StarterEncounter.View) -> void:
	if tick == 2:
		set_physics_process(false)
		var foe := view.others[0]
		_pulled = absf(foe.at.x - 157.2) < 0.01 and foe.hp.native_at_scale(0) == 100
		await _snap("pull.png")
		set_physics_process(true)
	elif tick == 26:
		set_physics_process(false)
		var foe := view.others[0]
		await _snap("reversal.png")
		_finish(_committed and _pulled and not _capture_fault and foe.hp.native_at_scale(0) == 78
			and absf(foe.at.x - 175.4) < 0.01)


func _click(at: Vector2, button: MouseButton) -> void:
	var point := _stage.get_global_transform_with_canvas() * at
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button
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
	var facts := {"passed": passed, "warning": _warning, "sequence": _sequence,
		"x": final.player.at.x if final != null else 0, "hp": final.player.hp.native_at_scale(0) if final != null else 0}
	if _close_call:
		facts["speed"] = _encounter.movement_state(SEAT, 1, final.tick + 1).speed if final != null else 0
		print("C04_CLOSE_CALL ", JSON.stringify(facts))
	elif _gravity:
		facts["pulled"] = _pulled
		facts["foe_x"] = final.others[0].at.x if final != null and not final.others.is_empty() else 0
		facts["foe_hp"] = final.others[0].hp.native_at_scale(0) if final != null and not final.others.is_empty() else 0
		print("C04_GRAVITY ", JSON.stringify(facts))
	else:
		facts["low"] = _low
		facts["committed"] = _committed
		print("C04_VAULT ", JSON.stringify(facts))
	get_tree().quit(0 if passed else 1)
