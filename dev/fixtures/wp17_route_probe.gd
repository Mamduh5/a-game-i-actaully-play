extends Node2D
## Follow a certified post-placement route using the normal movement command.

const ALT := &"alternate_blocker"
const MOVER := &"moved"
const SEAT := &"host"
const ACTOR := &"walker"
const WALK_MASK := 2
const SOLID_RADIUS := 33.0
const START := WorldTopology.ENTRY
const EXIT := WorldTopology.RETURN_EXIT

var _layout: WorldTopology
var _world: WorldExploration
var _route: Array[RealmSweep.Point] = []
var _control := PlayerControlState.new()
var _center: RealmSweep.Point
var _target: RealmSweep.Point
var _motion: WorldExploration.SolidMotion
var _next := 1
var _ticks: int
var _linger: int
var _finished: bool
var _rendered: bool
var _capture := ""
var _title := Label.new()


func _ready() -> void:
	_rendered = DisplayServer.get_name() != "headless"
	var args := OS.get_cmdline_user_args()
	if _rendered and args.size() == 1:
		_capture = args[0]
	_title.position = Vector2(32, 20)
	_title.text = "WP17 route fixture\nWalking the certified route to the return exit"
	add_child(_title)
	_layout = WorldTopology.generate_optional(-4, &"inverted_archive")
	_world = WorldExploration.create(_layout, [SEAT])
	var modules := _layout.route(START, EXIT)
	var entry := _layout.center(START)
	var neighbor := _layout.center(modules[1])
	var dx := neighbor.x - entry.x
	var dy := neighbor.y - entry.y
	var start := RealmSweep.Point.new(entry.x + dx * 0.2 - dy * 0.25, entry.y + dy * 0.2 + dx * 0.25)
	_target = RealmSweep.Point.new(entry.x + dx * 0.5, entry.y + dy * 0.5)
	for module: Dictionary in _layout.manifest()["modules"]:
		if module["id"] != START:
			continue
		for other: StringName in module["neighbors"]:
			if other != modules[1]:
				var other_center := _layout.center(other)
				var seam := RealmSweep.Point.new((entry.x + other_center.x) * 0.5, (entry.y + other_center.y) * 0.5)
				if not _world.place_route_solid(ALT, seam, SOLID_RADIUS):
					_finish(false)
					return
	if not _world.place_route_solid(MOVER, start, SOLID_RADIUS):
		_finish(false)
		return
	_motion = _world.move_route_solid(MOVER, _target)
	if _motion == null or not _motion.route_limited or not _motion.motion.stopped_by.is_empty():
		_finish(false)
		return
	_route = _world.physical_route(START, EXIT)
	if _route.size() < 2 or not _world.geometry().add_circle(ACTOR, 0, entry, WorldExploration.STARTER_RADIUS, WALK_MASK):
		_finish(false)
		return
	_center = entry
	_request_next()


func _physics_process(delta: float) -> void:
	_ticks += 1
	if _ticks > 900 or _center == null:
		_finish(false)
		return
	if _finished:
		_linger += 1
		if _linger >= 3:
			if not _capture.is_empty() and get_viewport().get_texture().get_image().save_png(_capture) != OK:
				_finish(false)
				return
			_finish(true)
		return
	_center = _control.step(_world.geometry(), ACTOR, 0, WorldExploration.BLOCKER, PlayerControlState.REFERENCE_SPEED, delta)
	if _center == null or not _world.observe_seat(SEAT, _layout.realm, _center):
		_finish(false)
		return
	var destination := _route[_next]
	if _center.x == destination.x and _center.y == destination.y:
		_next += 1
		if _next == _route.size():
			_finished = true
			_title.text = "WP17 route fixture\nReturn exit reached. The solid stopped short of closing the route."
		else:
			_request_next()
	queue_redraw()


func _request_next() -> void:
	var destination := _route[_next]
	_control.apply(PlayerCommand.new(PlayerCommand.MOVE_TO, destination.x, destination.y))


func _draw() -> void:
	if not _rendered or _center == null:
		return
	for module: Dictionary in _layout.manifest()["modules"]:
		var tile: Vector2i = module["cell"]
		var size := WorldTopology.MODULE_SIZE
		var top_left := _screen(RealmSweep.Point.new(tile.x * size, tile.y * size))
		draw_rect(Rect2(top_left, Vector2.ONE * size * 0.9 - Vector2.ONE * 2.0), Color("27313c"))
	for index: int in range(1, _route.size()):
		draw_line(_screen(_route[index - 1]), _screen(_route[index]), Color("73c9b2"), 3.0, true)
	for id: StringName in [ALT, MOVER]:
		draw_circle(_screen(_world.geometry().circle_center(id, 0)), SOLID_RADIUS * 0.9, Color("ce8540"), true, -1.0, true)
	draw_arc(_screen(_target), SOLID_RADIUS * 0.9, 0.0, TAU, 48, Color("f6c688"), 1.0, true)
	draw_circle(_screen(_center), WorldExploration.STARTER_RADIUS * 0.9, Color("f3faea"), true, -1.0, true)


static func _screen(point: RealmSweep.Point) -> Vector2:
	return Vector2(32.0 + point.x * 0.9, 78.0 + point.y * 0.9)


func _finish(passed: bool) -> void:
	if _world != null and _motion != null and _center != null:
		var settled := _motion.motion.finish
		var rows := JSON.stringify([_route.size(), settled.x, settled.y, _center.x, _center.y, _world.view(SEAT)["explored"].size()])
		print("WP17 passed=%s rendered=%s ticks=%d hash=%s facts=%s" % [passed, _rendered, _ticks, rows.sha256_text(), rows])
	else:
		print("WP17 passed=false setup")
	get_tree().quit(0 if passed else 1)
