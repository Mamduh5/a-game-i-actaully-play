class_name StarterCombatCues
extends Node2D
## Functional C01 telegraphs. The authority supplies geometry and impact
## phase. The art and its world-to-view transform do not drive combat.

const SWORD := Color("#f5c989")
const ARROW := Color("#fff0b7")
const SIGIL := Color("#a9c1ff")
const SIPHON := Color("#73d9c3")
const DAGGERS := Color("#d9e5f6")
const FOCUS := Color("#c0baff")

var _cues: Array[StarterCombat.Cue]
var _tick: int
var _reduce_fill: bool


func present(cues: Array[StarterCombat.Cue], tick: int, reduce_fill: bool = false) -> void:
	_cues = cues
	_tick = tick
	_reduce_fill = reduce_fill
	queue_redraw()


func _draw() -> void:
	for cue: StarterCombat.Cue in _cues:
		var center := Vector2(cue.position.x, cue.position.y)
		match cue.id:
			&"W01": _fan(center, cue)
			&"W02":
				var axis := Vector2(cue.heading.x, cue.heading.y)
				draw_line(center - axis * 17.0, center, ARROW, 2.0, true)
				draw_colored_polygon(PackedVector2Array([center + axis * 4.0,
					center - axis * 5.0 + axis.orthogonal() * 4.0,
					center - axis * 5.0 - axis.orthogonal() * 4.0]), ARROW)
			&"W03": _circle(center, cue.reach, SIGIL, _tick >= cue.impact)
			&"W04": _thrust(center, cue)
			&"W06": _thrust(center, cue, DAGGERS)
			&"W09":
				_thrust(center, cue, FOCUS)
				var end := center + Vector2(cue.heading.x, cue.heading.y) * cue.reach
				var width := 4.0 if _tick - cue.impact <= 2 else 1.5
				draw_line(center, end, FOCUS, width, true)
			StarterCombatRules.TIME_FRACTURE: _circle(center, cue.reach, Color("#8bd9ed"), true)
			StarterCombatRules.TEMPORAL_ECHO: _circle(center, cue.reach, Color("#f2d5ff"), false)
			StarterCombatRules.CLOSE_CALL: draw_arc(center, cue.reach, 0.0, TAU, 48, SIPHON, 2.0, true)
			StarterCombatRules.SINGULARITY: _circle(center, cue.reach, Color("#d8a4ee"), _tick >= cue.impact)
			StarterCombatRules.CRIMSON_OFFERING: draw_arc(center, cue.reach, 0.0, TAU, 48, Color("#ef8d99"), 2.0, true)
			&"RP02.blood_wake":
				var end := center + Vector2(cue.heading.x, cue.heading.y) * cue.reach
				var ink := Color("#e78491")
				var side := Vector2(cue.heading.x, cue.heading.y).orthogonal() * cue.radius
				if not _reduce_fill:
					draw_line(center, end, Color(ink, 0.32), cue.radius * 2.0, true)
				_capsule_outline(center, end, side, ink, 1.5)
			StarterCombatRules.SIPHON: _circle(center, cue.reach, SIPHON, true)
			StarterCombatRules.HARMONIC_BURST, &"R02.lightning", &"RP03.storm_relay":
				var end := center + Vector2(cue.heading.x, cue.heading.y) * cue.reach
				var ink := SWORD if cue.id == &"RP03.storm_relay" else SIGIL
				draw_line(center, end, ink, 3.0, true)
				draw_arc(end, 7.0, 0, TAU, 20, ink, 2.0, true)


func _fan(center: Vector2, cue: StarterCombat.Cue) -> void:
	var facing := atan2(cue.heading.y, cue.heading.x)
	var minimum := facing - cue.half_angle
	var maximum := facing + cue.half_angle
	var polygon := PackedVector2Array([center])
	for index: int in 25:
		polygon.append(center + Vector2.from_angle(lerpf(minimum, maximum, float(index) / 24.0)) * cue.reach)
	if not _reduce_fill:
		draw_colored_polygon(polygon, Color(SWORD, 0.24))
	draw_line(center, polygon[1], SWORD, 2.0, true)
	draw_line(center, polygon[-1], SWORD, 2.0, true)
	draw_arc(center, cue.reach, minimum, maximum, 24, SWORD, 3.0, true)


func _thrust(center: Vector2, cue: StarterCombat.Cue, ink: Color = SWORD) -> void:
	var axis := Vector2(cue.heading.x, cue.heading.y)
	var start := center + axis * cue.radius
	var end := center + axis * (cue.reach - cue.radius)
	var side := axis.orthogonal() * cue.radius
	if not _reduce_fill and cue.reach > cue.radius * 2.0:
		draw_colored_polygon(PackedVector2Array([start - side, end - side, end + side, start + side]), Color(ink, 0.24))
	_capsule_outline(start, end, side, ink, 2.0)


func _capsule_outline(start: Vector2, end: Vector2, side: Vector2, ink: Color, width: float) -> void:
	var angle := side.angle()
	var radius := side.length()
	if start != end:
		draw_line(start - side, end - side, ink, width, true)
		draw_line(start + side, end + side, ink, width, true)
	draw_arc(start, radius, angle - PI, angle, 16, ink, width, true)
	draw_arc(end, radius, angle, angle + PI, 16, ink, width, true)


func _circle(center: Vector2, radius: float, ink: Color, active: bool) -> void:
	if active and not _reduce_fill:
		draw_circle(center, radius, Color(ink, 0.26), true, -1.0, true)
	for index: int in (1 if active else 16):
		var start := 0.0 if active else float(index) * TAU / 16.0
		var length := TAU if active else TAU / 24.0
		draw_arc(center, radius, start, start + length, 64 if active else 6,
			ink, 3.0 if active else 2.0, true)
	draw_circle(center, 3.0, ink, true, -1.0, true)
