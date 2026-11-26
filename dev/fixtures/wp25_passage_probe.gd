extends Node2D
## Controlled round trip through the ordinary movement and interaction inputs.

const Seed := 2507
const Solo := &"solo"
const Garden := &"silent_garden"
const Outside := WorldTopology.OVERWORLD
const BodyMask := 2

class TravelHost extends RunAuthority:
	var party: RunParty
	var last_closed := false

	func _supports_action(action: StringName) -> bool:
		return action in [PlayerCommand.MOVE_TO, PlayerCommand.AIM, PlayerCommand.INTERACT]

	func _resolve_tick(tick: int, accepted: Array[RunIntent], _streams: RunRandom) -> Array[Dictionary]:
		for intent: RunIntent in accepted:
			if intent.action != PlayerCommand.INTERACT:
				party.apply_input(intent.seat_id, intent.command)
		var moved := party.step_movement(Solo, 240.0, 1.0 / 60.0)
		last_closed = moved != null and party.close_tick(tick)
		return []

var _outer := WorldExploration.create(WorldTopology.generate(Seed), [Solo])
var _inner := WorldExploration.create(WorldTopology.generate_optional(Seed, Garden), [Solo])
var _host := TravelHost.new()
var _router := PlayerInputRouter.new()
var _party: RunParty
var _passages: RunRealmPassages
var _outside_handle := _outer.module_center(WorldTopology.ANCHORS[0])
var _inside_handle := _inner.module_center(WorldTopology.RETURN_EXIT)
var _camera: RealmSweep.Point
var _waypoints: Array[RealmSweep.Point] = []
var _requested := false
var _entered := false
var _realm := Outside
var _sequence: int
var _capture_root: String
var _facts: Array[Array] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_capture_root = args[0]
	get_window().title = "WP25 optional realm round-trip fixture"
	RenderingServer.set_default_clear_color(Color("25353a"))
	if not _begin():
		_finish(false)
		return
	_waypoints = [_outside_handle]
	_router.world_from_viewport = _from_viewport
	add_child(_router)


func _begin() -> bool:
	var kernel := CombatKernel.new()
	var realms: Dictionary[StringName, RealmGeometry] = {Outside: _outer.geometry(), Garden: _inner.geometry()}
	for floor: RealmGeometry in realms.values():
		if not kernel.attach_geometry(floor, WorldExploration.BLOCKER):
			return false
	var start := RealmSweep.Point.new(_outside_handle.x - 72.0, _outside_handle.y)
	var actor := CombatantState.new()
	actor.id = Solo
	actor.owner = Solo
	actor.realm = Outside
	actor.life = 1
	actor.max_hp = Quantity.from_count(20)
	actor.hp = QuantityLayerLedger.Pool.new(actor.max_hp, QuantityErrorBounds.new())
	if not kernel.add_actor(actor) or not realms[Outside].add_circle(Solo, 0, start, 4.0, BodyMask):
		return false
	var setup := RunSetup.new()
	setup.run_id = &"wp25-passage"
	setup.authority_id = Solo
	setup.epoch = 1
	setup.seed = Seed
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = &"starter"
	setup.challenge_id = &"normal"
	setup.initial_realms = {Solo: Outside}
	_party = RunParty.begin(setup, Solo, kernel, realms, {Solo: Solo}, WorldExploration.BLOCKER)
	_host.party = _party
	_passages = RunRealmPassages.new(_host, _party)
	return (_party != null and _host.start(setup, Solo)
		and _passages.register_optional(&"garden", _outer, _outside_handle, _inner, 36.0, 10.0))


func _physics_process(_delta: float) -> void:
	var tick := _host.next_tick()
	if tick > 900:
		_finish(false)
		return
	var before := _party.view(Solo, CombatInstant.at_tick(tick - 1))
	_camera = before.position
	_drive(before.position)
	var request: RunIntent
	for command: PlayerCommand in _router.drain():
		var intent := RunIntent.new(&"wp25-passage", 1, _realm, Solo, tick, _sequence + 1, command.action, command)
		_sequence += 1
		if _host.submit(Solo, intent) != RunAuthority.Admission.QUEUED:
			_finish(false)
			return
		if command.action == PlayerCommand.INTERACT:
			request = intent
	if not _host.close_tick() or not _host.last_closed:
		_finish(false)
		return
	if request != null:
		if not _passages.interact(request):
			_finish(false)
			return
		var reached := _party.view(Solo, CombatInstant.at_tick(tick))
		_realm = reached.realm
		_camera = reached.position
		_facts.append([tick, _realm, reached.position.x, reached.position.y])
		queue_redraw()
		set_physics_process(false)
		await _capture("garden.png" if _realm == Garden else "return.png")
		if _entered:
			_finish(_realm == Outside)
			return
		_entered = true
		_waypoints = _inner.physical_route(WorldTopology.ENTRY, WorldTopology.RETURN_EXIT)
		if _waypoints.is_empty() or _realm != Garden:
			_finish(false)
			return
		_requested = false
		set_physics_process(true)
	else:
		_camera = _party.view(Solo, CombatInstant.at_tick(tick)).position
		queue_redraw()


func _drive(at: RealmSweep.Point) -> void:
	while not _waypoints.is_empty() and _waypoints[0].x == at.x and _waypoints[0].y == at.y:
		_waypoints.pop_front()
		_requested = false
	if _requested:
		return
	_requested = true
	var target := (_inside_handle if _entered else _outside_handle) if _waypoints.is_empty() else _waypoints[0]
	var pixel := _to_viewport(target)
	var motion := InputEventMouseMotion.new()
	motion.position = pixel
	motion.global_position = pixel
	get_viewport().push_input(motion, true)
	for pressed: bool in [true, false]:
		if _waypoints.is_empty():
			var key := InputEventKey.new()
			key.physical_keycode = KEY_E
			key.pressed = pressed
			get_viewport().push_input(key, true)
		else:
			var button := InputEventMouseButton.new()
			button.position = pixel
			button.global_position = pixel
			button.button_index = MOUSE_BUTTON_RIGHT
			button.pressed = pressed
			get_viewport().push_input(button, true)


func _from_viewport(pixel: Vector2) -> RealmSweep.Point:
	var offset := pixel - get_viewport_rect().size * 0.5
	return RealmSweep.Point.new(_camera.x + offset.x, _camera.y + offset.y)


func _to_viewport(world: RealmSweep.Point) -> Vector2:
	return Vector2(world.x - _camera.x, world.y - _camera.y) + get_viewport_rect().size * 0.5


func _draw() -> void:
	if _camera == null:
		return
	var center := get_viewport_rect().size * 0.5
	draw_circle(center, 10.0, Color("a0ead7"))
	var door := _to_viewport(_inside_handle if _realm == Garden else _outside_handle)
	draw_arc(door, 22.0, 0.0, TAU, 40, Color("d5b8ef"), 3.0, true)
	draw_string(ThemeDB.fallback_font, Vector2(26.0, 42.0), "Silent Garden" if _realm == Garden else "Overworld")
	draw_string(ThemeDB.fallback_font, Vector2(26.0, 68.0), "E  Use passage")


func _capture(filename: String) -> void:
	if _capture_root.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	if get_viewport().get_texture().get_image().save_png(_capture_root.path_join(filename)) != OK:
		push_error("WP25 viewport evidence could not be saved")


func _finish(passed: bool) -> void:
	set_physics_process(false)
	print("WP25_PASSAGE ", JSON.stringify({"passed": passed, "transfer": _facts, "sequence": _sequence}))
	get_tree().quit(0 if passed else 1)
