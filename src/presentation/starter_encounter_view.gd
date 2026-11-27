class_name StarterEncounterView
extends Node2D
## The projection contains only the actors and cues this player can see.

const INK := Color("#e6ece6")
const WALL := Color("#75887f")
const PLAYER := Color("#9dd8bc")
const ENEMY := Color("#df9a84")
const THREAT := Color("#ff9f76")
const POWER := Color("#b9aae9")

var outline_only := false
var _cells: Array[Vector2i] = []
var _edges: Array[RealmOutline.Edge] = []
var _solids: Array[Vector3] = []
var _passage: Vector2
var _goal: Vector2
var _view: StarterEncounter.View
var _cues := StarterCombatCues.new()


func _ready() -> void:
	add_child(_cues)


func prepare(cells: Array[Vector2i], geometry: RealmGeometry, solids: Array[StringName],
		passage: Vector2, goal: Vector2) -> void:
	var edges := section_edges(cells, geometry)
	prepare_floor(cells, edges, passage, goal)
	for id: StringName in solids:
		var at := geometry.circle_center(id, 0)
		_solids.append(Vector3(at.x, at.y, geometry.circle_radius(id, 0)))


func prepare_floor(cells: Array[Vector2i], edges: Array[RealmOutline.Edge], passage: Vector2, goal: Vector2) -> void:
	_cells = cells.duplicate()
	_edges = edges.duplicate()
	_solids.clear()
	_passage = passage
	_goal = goal
	queue_redraw()


static func section_edges(cells: Array[Vector2i], geometry: RealmGeometry) -> Array[RealmOutline.Edge]:
	var edges: Array[RealmOutline.Edge] = []
	if cells.is_empty():
		return edges
	var tile := float(WorldTopology.MODULE_SIZE)
	var covered := Rect2(Vector2(cells[0]) * tile, Vector2.ONE * tile)
	for cell: Vector2i in cells:
		covered = covered.merge(Rect2(Vector2(cell) * tile, Vector2.ONE * tile))
	covered = covered.grow(0.1)
	for edge: RealmOutline.Edge in geometry.segments(WorldExploration.BLOCKER):
		var first := _point(edge.first)
		var last := _point(edge.last)
		if covered.has_point(first) and covered.has_point(last):
			edges.append(edge)
	return edges


func display(view: StarterEncounter.View) -> void:
	_view = view
	_cues.present(view.cues, view.tick, outline_only)
	queue_redraw()


func world_from_viewport(point: Vector2) -> RealmSweep.Point:
	var world := get_global_transform_with_canvas().affine_inverse() * point
	return RealmSweep.Point.new(world.x, world.y)


func _draw() -> void:
	var size := float(WorldTopology.MODULE_SIZE)
	for cell: Vector2i in _cells:
		var at := Vector2(cell) * size
		draw_rect(Rect2(at, Vector2.ONE * size), Color("#30403e"))
		for line: int in range(1, 8):
			var distance := line * size / 8.0
			draw_line(at + Vector2(distance, 0), at + Vector2(distance, size), Color("#384946"), 0.65)
			draw_line(at + Vector2(0, distance), at + Vector2(size, distance), Color("#384946"), 0.65)
	for edge: RealmOutline.Edge in _edges:
		draw_line(_point(edge.first), _point(edge.last), WALL, 3.0, true)
	for rock: Vector3 in _solids:
		draw_circle(Vector2(rock.x, rock.y), rock.z, Color("#667069"), true, -1.0, true)
		draw_arc(Vector2(rock.x, rock.y), rock.z, 0, TAU, 28, WALL, 1.5, true)
	draw_polyline(PackedVector2Array([_passage - Vector2(6, 5), _passage, _passage - Vector2(6, -5)]),
		Color(PLAYER, 0.62), 2.0, true)
	draw_arc(_goal, 16.0, 0, TAU, 32, Color(PLAYER, 0.6), 1.4, true)
	draw_circle(_goal, 3.5, PLAYER, true, -1.0, true)
	if _view == null:
		return
	for warning: WorldEnemy.Threat in _view.threats:
		var at := _point(warning.center)
		var progress := clampf(float(_view.tick - warning.start_tick) / (warning.impact_tick - warning.start_tick), 0, 1)
		if not outline_only:
			draw_circle(at, warning.radius, Color(THREAT, 0.20), true, -1.0, true)
		draw_arc(at, warning.radius, 0.0, TAU, 48, Color(THREAT, 0.70), 1.4, true)
		draw_arc(at, warning.radius + 2.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 40, THREAT, 3.0, true)
	for link: Array in _view.tethers:
		draw_line(_point(link[0]), _point(link[1]), POWER, 3.0, true)
	for mine: RealmSweep.Point in _view.mines:
		_diamond(_point(mine), 7.0, POWER)
	for familiar: RealmSweep.Point in _view.familiars:
		_diamond(_point(familiar), 7.0, Color("#d5d6a0"))
	for dart: RealmSweep.Point in _view.darts:
		draw_circle(_point(dart), 3.0, Color("#d5d6a0"), true, -1.0, true)
	for lance: RealmSweep.Point in _view.lances:
		_diamond(_point(lance), 4.0, Color("#8bb6fb"))
	var ally_visible := false
	for unit: StarterEncounter.Fighter in _view.others:
		_draw_fighter(unit, unit.id == _view.selected)
		ally_visible = ally_visible or not unit.enemy
	_draw_fighter(_view.player, false)
	if ally_visible:
		var at := _point(_view.player.at)
		draw_line(at + Vector2(-5, 4), at + Vector2(0, 8), INK, 1.5, true)
		draw_line(at + Vector2(0, 8), at + Vector2(5, 4), INK, 1.5, true)
	if _view.barrier != null and _view.barrier.sign_value > 0:
		draw_arc(_point(_view.player.at), _view.player.radius + 2.0, 0, TAU, 34, Color("#7fcfe2"), 2.4, true)


func _draw_fighter(unit: StarterEncounter.Fighter, selected: bool) -> void:
	var at := _point(unit.at)
	var color := ENEMY if unit.enemy else PLAYER
	if unit.hp.sign_value <= 0:
		color = Color("#778780")
	draw_circle(at + Vector2(0, 2), unit.radius + 1.5, Color("#202d2c"), true, -1.0, true)
	draw_circle(at, unit.radius, color, not outline_only, -1.0 if not outline_only else 2.0, true)
	_diamond(at, unit.radius * 0.55, Color("#3d514c") if not unit.enemy else Color("#744f48"))
	if selected:
		draw_arc(at, unit.radius + 3.0, 0, TAU, 32, INK, 1.4, true)
	var hp := float(unit.hp.native_at_scale(0))
	var maximum := float(unit.maximum.native_at_scale(0))
	var label := Rect2(at - Vector2(unit.radius, unit.radius + 8.0), Vector2(unit.radius * 2.0, 3.0))
	draw_rect(label, Color("#202d2c"))
	draw_rect(Rect2(label.position, Vector2(label.size.x * clampf(hp / maxf(maximum, 1.0), 0, 1), 3.0)), color)


func _diamond(at: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		at + Vector2.UP * radius, at + Vector2.RIGHT * radius,
		at + Vector2.DOWN * radius, at + Vector2.LEFT * radius,
	]), color)


static func _point(point: RealmSweep.Point) -> Vector2:
	return Vector2(point.x, point.y)
