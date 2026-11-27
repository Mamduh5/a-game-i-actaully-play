extends Node2D
## Controlled baseline traversal using ordinary movement and interaction input.

const Observatory := preload("res://src/run/run_observatory_gateway.gd")
const SEAT := &"solo"
const RUN := &"wp25-observatory"
const OUTSIDE := WorldTopology.OVERWORLD
const ARENA := RunSetup.FINAL_REALM
const SCALE := 0.88

class Driver extends RunAuthority:
	var party: RunParty
	var kernel: CombatKernel
	var clicks: Array[RunIntent] = []
	var settled: bool

	func _supports_action(action: StringName) -> bool:
		return action in [PlayerCommand.MOVE_TO, PlayerCommand.AIM, PlayerCommand.INTERACT]

	func _resolve_tick(tick: int, accepted: Array[RunIntent], _streams: RunRandom) -> Array[Dictionary]:
		clicks.clear()
		for intent: RunIntent in accepted:
			if intent.action == PlayerCommand.INTERACT:
				clicks.append(intent)
			else:
				party.apply_input(SEAT, intent.command)
		settled = (party.step_movement(SEAT, PlayerControlState.REFERENCE_SPEED, 1.0 / 60.0) != null
			and kernel.advance_survival(CombatInstant.at_tick(tick)).result == CombatKernel.Result.CLOSED
			and party.close_tick(tick))
		return []

var _driver := Driver.new()
var _router := PlayerInputRouter.new()
var _world: WorldExploration
var _gate: Observatory
var _center: RealmSweep.Point
var _neighbor: RealmSweep.Point
var _pilot_destination: RealmSweep.Point
var _marks: Array[Observatory.Mark] = []
var _known: Dictionary[StringName, RealmSweep.Point] = {}
var _actor: RunParty.View
var _edges: Array[RealmOutline.Edge] = []
var _seed: int
var _sequence: int
var _turns: int
var _crossed := false
var _has_clue := false
var _seen_open := false
var _done := false
var _capturing := false
var _capture_fault := false
var _capture_root: String


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_capture_root = args[0] if not args.is_empty() else ""
	_seed = args[1].to_int() if args.size() > 1 else _early_seed()
	get_window().title = "Silent Observatory | WP25 controlled PR04 entry"
	RenderingServer.set_default_clear_color(Color("#1e2834"))
	if not _setup():
		_finish(false)
		return
	_router.world_from_viewport = _world_at
	add_child(_router)


func _setup() -> bool:
	var layout := WorldTopology.generate(_seed)
	_world = WorldExploration.create(layout, [SEAT])
	if _world == null:
		return false
	_center = _world.early_observatory_center()
	var path := _world.route(WorldTopology.ANCHORS[0], WorldTopology.OBSERVATORY)
	if _center == null or path.size() < 2:
		return false
	_neighbor = _world.module_center(path[-2])
	var direction := PlayerControlState.direction(_neighbor, _center, RealmSweep.Point.new(1, 0))
	var start := RealmSweep.Point.new(_neighbor.x + 85.0 * direction.x, _neighbor.y + 85.0 * direction.y)
	var floor := _world.geometry()
	var approach := floor.certify_frozen_path(OUTSIDE, start, _center, WorldExploration.STARTER_RADIUS,
		WorldExploration.BLOCKER)
	if approach == null or not approach.contacts.is_empty() or not approach.unresolved.is_empty():
		return false
	for edge: RealmOutline.Edge in floor.segments(WorldExploration.BLOCKER):
		if _near_stage(edge.first) and _near_stage(edge.last):
			_edges.append(edge)
	var bundle: CatalogBundle = load("res://src/catalog/starter_roster.tres")
	var catalog := bundle.compile()
	var setup := RunSetup.new()
	setup.run_id = RUN
	setup.epoch = 1
	setup.authority_id = SEAT
	setup.seed = _seed
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = catalog.revision
	setup.challenge_id = &"normal"
	setup.initial_realms = {SEAT: OUTSIDE}
	var candidates: Array[StringName] = []
	candidates.resize(RunPreparation.CANDIDATE_SLOTS)
	candidates.fill(&"")
	var prepared := RunPreparation.select(catalog, &"H01", &"W01", [&"", &""], candidates, {})
	var progress := PartyProgression.begin(setup, {SEAT: prepared})
	var body := CombatantState.new()
	body.id = SEAT
	body.owner = SEAT
	body.realm = OUTSIDE
	body.life = 1
	body.max_hp = Quantity.from_count(100)
	body.hp = QuantityLayerLedger.Pool.new(body.max_hp, QuantityErrorBounds.new())
	_driver.kernel = CombatKernel.new()
	if (not _driver.kernel.attach_geometry(floor, WorldExploration.BLOCKER) or not _driver.kernel.add_actor(body)
			or not floor.add_circle(SEAT, 0, start, WorldExploration.STARTER_RADIUS, WorldActivity.ACTORS)):
		return false
	_driver.party = RunParty.begin(setup, SEAT, _driver.kernel, {OUTSIDE: floor}, {SEAT: SEAT}, WorldExploration.BLOCKER)
	if _driver.party == null or not _driver.start(setup, SEAT):
		return false
	_actor = _driver.party.view(SEAT, CombatInstant.at_tick(0))
	_gate = Observatory.register(_driver, _driver.party, _world, RealmGeometry.new(ARENA),
		{SEAT: RealmSweep.Point.new(128, 128)}, progress)
	return _gate != null and _gate.view_for(SEAT).is_empty()


func _physics_process(_delta: float) -> void:
	var tick := _driver.next_tick()
	if tick > 900 or _capture_fault:
		_finish(false)
		return
	_marks = _gate.view_for(SEAT)
	if not _capturing:
		_drive()
	for command: PlayerCommand in _router.drain():
		_sequence += 1
		var input := RunIntent.new(RUN, 1, OUTSIDE, SEAT, tick, _sequence, command.action, command)
		if _driver.submit(SEAT, input) != RunAuthority.Admission.QUEUED:
			_finish(false)
			return
	if not _driver.close_tick() or not _driver.settled:
		_finish(false)
		return
	for click: RunIntent in _driver.clicks:
		if _gate.turn(click):
			_turns += 1
		elif _gate.enter(click) != RunAuthority.GatewayResult.ENTERED:
			_finish(false)
			return
	_actor = _driver.party.view(SEAT, CombatInstant.at_tick(tick))
	_crossed = _crossed or (_actor.realm == OUTSIDE and _world.module_at(_actor.position) == WorldTopology.OBSERVATORY)
	_marks = _gate.view_for(SEAT)
	queue_redraw()
	if _actor.realm == ARENA:
		set_physics_process(false)
		await _capture("arena.png")
		_finish(_crossed and _has_clue and _seen_open and _turns == 4 and not _capture_fault
			and _driver.checkpoint().get("early_gateway_tick") == tick)


func _drive() -> void:
	if not _has_clue:
		if not _near(_actor.position, _center, 0.25):
			_walk(_center)
			return
		for mark: Observatory.Mark in _marks:
			_known[mark.id] = mark.position
			_has_clue = _has_clue or not mark.inscription.is_empty()
		if _has_clue and not _known.has(Observatory.GATE):
			_capture("clue.png")
		return
	for mark: Observatory.Mark in _marks:
		if mark.id == Observatory.GATE:
			if not _seen_open:
				_seen_open = true
				_capture("aligned.png")
				return
			_approach_handle(mark.position)
			return
	var side := Observatory.WEST_CONDUIT if _turns == 0 else Observatory.EAST_CONDUIT
	_approach_handle(_known[side])


func _approach_handle(point: RealmSweep.Point) -> void:
	if _near(_actor.position, point, 24.0):
		_pilot_destination = null
		_gesture(point, true)
	else:
		_walk(point)


func _walk(point: RealmSweep.Point) -> void:
	if _pilot_destination != null and _near(_pilot_destination, point, 0.001):
		return
	_pilot_destination = point
	_gesture(point, false)


func _gesture(point: RealmSweep.Point, interact: bool) -> void:
	var pixel := _pixel(point)
	var cursor := InputEventMouseMotion.new()
	cursor.position = pixel
	cursor.global_position = pixel
	get_viewport().push_input(cursor, true)
	for pressed: bool in [true, false]:
		if interact:
			var key := InputEventKey.new()
			key.physical_keycode = KEY_E
			key.pressed = pressed
			get_viewport().push_input(key, true)
		else:
			var action := InputEventMouseButton.new()
			action.button_index = MOUSE_BUTTON_RIGHT
			action.position = pixel
			action.global_position = pixel
			action.pressed = pressed
			get_viewport().push_input(action, true)


func _draw() -> void:
	if _actor == null:
		return
	var font := ThemeDB.fallback_font
	var width := WorldTopology.MODULE_SIZE * SCALE
	if _actor.realm == ARENA:
		var at := get_viewport_rect().size * 0.5
		draw_circle(at, 108, Color("#3f465e"))
		draw_circle(at, WorldExploration.STARTER_RADIUS * SCALE, Color("#c0efce"))
		draw_string(font, Vector2(30, 42), "Unfinished Canvas", HORIZONTAL_ALIGNMENT_LEFT, -1, 27)
		return
	for tile: RealmSweep.Point in [_center, _neighbor]:
		draw_rect(Rect2(_pixel(tile) - Vector2(width, width) * 0.5, Vector2(width, width)), Color("#314759"))
	for edge: RealmOutline.Edge in _edges:
		draw_line(_pixel(edge.first), _pixel(edge.last), Color("#78939e"), 3.0, true)
	for mark: Observatory.Mark in _marks:
		var at := _pixel(mark.position)
		if mark.id == Observatory.INSCRIPTION:
			draw_circle(at, 6, Color("#d9c7a3"))
			draw_string(font, at + Vector2(-235, -19), mark.inscription, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		elif mark.id == Observatory.GATE:
			draw_arc(at, 21, 0, TAU, 32, Color("#dcaee5"), 5.0, true)
		else:
			draw_circle(at, 16, Color("#1e2834"))
			draw_line(at, at + Vector2(mark.direction) * 22, Color("#e4bf78"), 6.0, true)
	draw_circle(_pixel(_actor.position), WorldExploration.STARTER_RADIUS * SCALE, Color("#c0efce"))
	draw_string(font, Vector2(30, 42), "Silent Observatory", HORIZONTAL_ALIGNMENT_LEFT, -1, 27)
	draw_string(font, Vector2(30, get_viewport_rect().size.y - 26), "Right click to move   E to interact",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20)


func _focus() -> Vector2:
	return Vector2((_neighbor.x + _center.x) * 0.5, (_neighbor.y + _center.y) * 0.5)


func _pixel(point: RealmSweep.Point) -> Vector2:
	return (Vector2(point.x, point.y) - _focus()) * SCALE + get_viewport_rect().size * 0.5


func _world_at(pixel: Vector2) -> RealmSweep.Point:
	var point := (pixel - get_viewport_rect().size * 0.5) / SCALE + _focus()
	return RealmSweep.Point.new(point.x, point.y)


func _near_stage(point: RealmSweep.Point) -> bool:
	var offset := Vector2(point.x, point.y) - _focus()
	return absf(offset.x) <= WorldTopology.MODULE_SIZE and absf(offset.y) <= WorldTopology.MODULE_SIZE


static func _near(from: RealmSweep.Point, to: RealmSweep.Point, distance: float) -> bool:
	return (from.x - to.x) ** 2 + (from.y - to.y) ** 2 <= distance ** 2


static func _early_seed() -> int:
	for seed: int in range(128):
		if WorldTopology.generate(seed).has_early_observatory():
			return seed
	return -1


func _capture(filename: String) -> void:
	if _capture_root.is_empty() or DisplayServer.get_name() == "headless":
		return
	_capturing = true
	queue_redraw()
	await RenderingServer.frame_post_draw
	_capture_fault = get_viewport().get_texture().get_image().save_png(_capture_root.path_join(filename)) != OK
	_capturing = false


func _finish(passed: bool) -> void:
	if _done:
		return
	_done = true
	set_physics_process(false)
	var accepted := _driver.checkpoint()
	print("WP25_OBSERVATORY ", JSON.stringify({"passed": passed, "seed": _seed, "crossed": _crossed,
		"clue": _has_clue, "aligned": _seen_open, "turns": _turns, "epoch": accepted.get("world_epoch", 1),
		"entry_tick": accepted.get("early_gateway_tick", -1), "input_sequence": _sequence}))
	get_tree().quit(0 if passed else 1)
