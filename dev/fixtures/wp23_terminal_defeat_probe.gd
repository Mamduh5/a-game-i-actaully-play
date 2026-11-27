extends Node2D
## Hold one real defeat across a refused SQLite write, then cold-read the profile.

const SEAT := &"wp23-terminal"
const RUN := &"live-defeat"
const REALM := WorldTopology.OVERWORLD
const ACCOUNT := "currency/permanent"
const SHELL := preload("res://src/app/main.tscn")

class RefusalStore extends ProfileStore:
	var remaining_before_refusal := -1

	func _commit_io() -> bool:
		if remaining_before_refusal == 0:
			return false
		if remaining_before_refusal > 0:
			remaining_before_refusal -= 1
		return super._commit_io()

var _store := RefusalStore.new()
var _encounter: StarterEncounter
var _ordinary: OrdinaryCurrency
var _stage: StarterEncounterView
var _router: PlayerInputRouter
var _caption: Label
var _capture: String
var _fault_after: int
var _capture_ok := true


func _ready() -> void:
	set_physics_process(false)
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 3 or args[0] not in ["money", "marker", "read"]:
		get_tree().quit(2)
		return
	if _store.open(String(SEAT), args[1]) != ProfileStore.OpenResult.OPENED:
		get_tree().quit(3)
		return
	var shell := SHELL.instantiate()
	add_child(shell)
	if not shell.bind_profile(_store):
		get_tree().quit(4)
		return
	if args[0] == "read":
		_readback()
		return
	shell.hide()
	_capture = args[2] if args.size() == 3 else ""
	_fault_after = int(args[0] == "marker")
	RenderingServer.set_default_clear_color(Color("#202b29"))
	_stage = StarterEncounterView.new()
	_stage.position = Vector2(435, 148)
	_stage.scale = Vector2.ONE * 1.55
	add_child(_stage)
	_caption = Label.new()
	_caption.position = Vector2(435, 82)
	_caption.add_theme_font_size_override("font_size", 29)
	_caption.text = "Starter encounter"
	add_child(_caption)
	_router = PlayerInputRouter.new()
	_router.world_from_viewport = _stage.world_from_viewport
	add_child(_router)
	if not _begin() or not shell.bind_run(_encounter):
		_finish(false)
		return
	set_physics_process(true)


func _begin() -> bool:
	var catalog: DefinitionCatalog = load("res://src/catalog/starter_roster.tres").compile()
	var setup := RunSetup.new()
	setup.run_id = RUN
	setup.epoch = 1
	setup.seed = 3207
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = catalog.revision
	setup.authority_id = SEAT
	setup.challenge_id = &"normal"
	setup.initial_realms = {SEAT: REALM}
	var slots: Array[StringName] = []
	slots.resize(RunPreparation.CANDIDATE_SLOTS)
	slots.fill(&"")
	var build := StarterEncounter.Build.new()
	build.preparation = RunPreparation.select(catalog, &"H01", &"W01", [&"", &""], slots, {})
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
	foe.family = &"fixture/defeat-strike"
	foe.hp = Quantity.from_count(100)
	foe.damage = Quantity.from_count(100)
	foe.radius = 12.0
	foe.sight = 154.0
	foe.attack_range = 103.0
	foe.attack_radius = 26.0
	foe.windup_ticks = 2
	foe.recovery_ticks = 78
	if not _encounter.place_enemy(&"foe", foe, RealmSweep.Point.new(155, 128)):
		return false
	var key := Crypto.new().generate_rsa(2048)
	var grant := ProfileGrant.Binding.new()
	grant.run = RUN
	grant.rules = setup.rules_revision
	grant.catalog = setup.catalog_revision
	grant.recipient = SEAT
	grant.issuer = key
	grant.recipient_key = key
	_ordinary = OrdinaryCurrency.begin(_store, grant, key, ACCOUNT)
	return _encounter.attach_ordinary_currency(_ordinary)


func _physics_process(_delta: float) -> void:
	if _encounter.next_tick() < 3:
		if not _encounter.close_tick():
			_finish(false)
			return
		_stage.display(_encounter.view_for(SEAT))
		return
	set_physics_process(false)
	var before := _encounter.closed_result()
	var input := _admit_move()
	var accrued := _ordinary.accrue("fixture/earlier-spawn", Quantity.from_count(7)) == OrdinaryCurrency.Eligibility.QUEUED
	_store.remaining_before_refusal = _fault_after
	var delayed := not _encounter.close_tick() and _encounter.has_unpublished_tick() and _encounter.fault().is_empty()
	var retained := (_encounter.closed_result() == before and _encounter.movement_acknowledgement(SEAT) == 0
		and _encounter.view_for(SEAT) == null and _encounter.next_tick() == 3)
	var balance_at_wait: int = _store.balance(ACCOUNT).native_at_scale(0)
	var refused_again := not _encounter.close_tick()
	_caption.text = "Saving run earnings"
	await _snap("waiting.png")
	_store.remaining_before_refusal = -1
	if not _encounter.close_tick():
		_finish(false)
		return
	var view := _encounter.view_for(SEAT)
	_stage.display(view)
	_caption.text = "Defeated  ·  Earnings saved"
	await _snap("defeat.png")
	var published: bool = (view.defeated and view.player.hp.sign_value == 0 and _encounter.next_tick() == 4
		and _encounter.movement_acknowledgement(SEAT) == 1 and _encounter.closed_result().accepted.size() == 1
		and not _encounter.close_tick())
	_finish(input and accrued and delayed and retained and refused_again and balance_at_wait == _fault_after * 7 and published)


func _admit_move() -> bool:
	var point := _stage.get_global_transform_with_canvas() * Vector2(64, 128)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = pressed
		get_viewport().push_input(event, true)
	var commands := _router.drain()
	if commands.size() != 1:
		return false
	var command := commands[0]
	var intent := RunIntent.new(RUN, 1, REALM, SEAT, 3, 1, command.action, command)
	return _encounter.submit(SEAT, intent) == RunAuthority.Admission.QUEUED


func _snap(name: String) -> void:
	if _capture.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_capture_ok = _capture_ok and get_viewport().get_texture().get_image().save_png(_capture.path_join(name)) == OK


func _finish(passed: bool) -> void:
	set_physics_process(false)
	var closed := _encounter.closed_result() if _encounter != null else {}
	var balance: int = _store.balance(ACCOUNT).native_at_scale(0)
	var generation: int = _store.checkpoint().get("generation", -1)
	var saved := _store.close()
	passed = passed and _capture_ok and balance == 7 and generation == 3 and saved
	print("WP23_LIVE_DEFEAT ", JSON.stringify({"passed": passed, "fault_after": _fault_after,
		"balance": balance, "tick": closed.get("tick", -1), "generation": generation}))
	get_tree().quit(0 if passed else 1)


func _readback() -> void:
	var balance: int = _store.balance(ACCOUNT).native_at_scale(0)
	var generation: int = _store.checkpoint().get("generation", -1)
	var clear := ProfileOrdinarySession.reopen_status(_store) == ProfileOrdinarySession.ReopenStatus.CLEAR
	var saved := _store.close()
	var passed := clear and balance == 7 and generation == 3 and saved
	print("WP23_LIVE_READ ", JSON.stringify({"passed": passed, "balance": balance, "generation": generation, "clear": clear}))
	get_tree().quit(0 if passed else 1)
