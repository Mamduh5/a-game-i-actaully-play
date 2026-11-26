class_name StarterCombatCues
extends Node2D
## Functional C01 telegraphs. The authority supplies geometry and impact
## phase. The art and its world-to-view transform do not drive combat.

const SWORD := Color("#f5c989")
const ARROW := Color("#fff0b7")
const SIGIL := Color("#a9c1ff")
const SIPHON := Color("#73d9c3")

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
			StarterCombatRules.SIPHON: _circle(center, cue.reach, SIPHON, true)
			StarterCombatRules.HARMONIC_BURST:
				var end := center + Vector2(cue.heading.x, cue.heading.y) * cue.reach
				draw_line(center, end, SIGIL, 3.0, true)
				draw_arc(end, 7.0, 0, TAU, 20, SIGIL, 2.0, true)


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


func _circle(center: Vector2, radius: float, ink: Color, active: bool) -> void:
	if active and not _reduce_fill:
		draw_circle(center, radius, Color(ink, 0.26), true, -1.0, true)
	for index: int in (1 if active else 16):
		var start := 0.0 if active else float(index) * TAU / 16.0
		var length := TAU if active else TAU / 24.0
		draw_arc(center, radius, start, start + length, 64 if active else 6,
			ink, 3.0 if active else 2.0, true)
	draw_circle(center, 3.0, ink, true, -1.0, true)
