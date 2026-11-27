extends RefCounted
## Emits only ordinary bound key events and viewport pointer gestures.

const LEFT := &"wp14_left"
const RIGHT := &"wp14_right"
const UP := &"wp14_up"
const DOWN := &"wp14_down"
const MANUAL := &"wp14_manual"
const MOVEMENT: Array[StringName] = [LEFT, RIGHT, UP, DOWN]

var _view: Viewport
var _movement: Array[StringName]
var _notify_pointer: bool
var _held: Dictionary[StringName, bool] = {}


func _init(viewport: Viewport, movement: Array[StringName] = MOVEMENT, notify_pointer: bool = true) -> void:
	_view = viewport
	_movement = movement.duplicate()
	_notify_pointer = notify_pointer


func apply(command: Dictionary) -> bool:
	if command.size() != 4 or _movement.size() != 4:
		return false
	var x: Variant = command.get("horizontal")
	var y: Variant = command.get("vertical")
	var manual: Variant = command.get("manual")
	var click: Variant = command.get("click")
	if not _axis(x) or not _axis(y) or not manual is bool or not click is Array:
		return false
	var rect := _view.get_visible_rect()
	if not click.is_empty() and (click.size() != 2 or not _coordinate(click[0]) or not _coordinate(click[1]) \
			or not rect.has_point(Vector2(click[0], click[1]))):
		return false
	var next: Array[bool] = [x == -1, x == 1, y == -1, y == 1]
	for index: int in _movement.size():
		var action := _movement[index]
		if bool(_held.get(action, false)) != next[index]:
			_push_key(action, next[index])
			_held[action] = next[index]
	if manual:
		_push_key(MANUAL, true)
		_push_key(MANUAL, false)
	if not click.is_empty():
		_push_click(Vector2(click[0], click[1]))
	return true


func release() -> void:
	for action: StringName in _held:
		if _held[action]:
			_push_key(action, false)
	_held.clear()


func _push_key(action: StringName, pressed: bool) -> void:
	var bound := InputMap.action_get_events(action)[0] as InputEventKey
	var event := InputEventKey.new()
	event.physical_keycode = bound.physical_keycode
	event.pressed = pressed
	_view.push_input(event, true)


func _push_click(point: Vector2) -> void:
	if _notify_pointer:
		_view.notify_mouse_entered()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	_view.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		_view.push_input(event, true)


static func _axis(value: Variant) -> bool:
	return _coordinate(value) and value >= -1 and value <= 1


static func _coordinate(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and floorf(value) == value
