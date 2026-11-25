class_name PlayerCommand
extends RefCounted
## Semantic input. Coordinates are realm-local doubles except for Move Axes.

const MOVE_AXES := &"move_axes"
const MOVE_TO := &"move_to"
const AIM := &"aim"
const MANUAL := &"manual"
const INTERACT := &"interact"
const TARGET := &"target"
const ACTIONS := [MOVE_AXES, MOVE_TO, AIM, MANUAL, INTERACT, TARGET]

var action: StringName
var x: float
var y: float


func _init(kind: StringName, horizontal: float = 0.0, vertical: float = 0.0) -> void:
	action = kind
	x = horizontal
	y = vertical


func valid() -> bool:
	return (action in ACTIONS and is_finite(x) and is_finite(y)
		and (action != MOVE_AXES or (absf(x) <= 1.0 and absf(y) <= 1.0)))


func copy() -> PlayerCommand:
	return PlayerCommand.new(action, x, y)


func matches(other: PlayerCommand) -> bool:
	return other != null and action == other.action and x == other.x and y == other.y
