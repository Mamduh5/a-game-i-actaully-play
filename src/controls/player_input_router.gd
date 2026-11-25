class_name PlayerInputRouter
extends Node
## Device presses become commands only after the viewport's GUI has handled them.

const LEFT := &"player_move_left"
const RIGHT := &"player_move_right"
const UP := &"player_move_up"
const DOWN := &"player_move_down"
const DESTINATION := &"player_move_to"
const MANUAL := &"player_manual"
const INTERACT := &"player_interact"
const TARGET := &"player_target"

const AXES := [LEFT, RIGHT, UP, DOWN]
const ACTIONS := [LEFT, RIGHT, UP, DOWN, DESTINATION, MANUAL, INTERACT, TARGET]
const MAX_PENDING := 32

var world_from_viewport: Callable
var _held: Dictionary[int, StringName] = {}
var _key_down: Dictionary[int, bool] = {}
var _mouse_down: Dictionary[int, bool] = {}
var _pending: Array[PlayerCommand] = []
var _aim: PlayerCommand
var _overflow := false
var _pointer := Vector2.ZERO


func _ready() -> void:
	install_defaults()
	get_window().focus_exited.connect(clear_focus)


static func install_defaults() -> void:
	for entry: Array in [[LEFT, KEY_A], [RIGHT, KEY_D], [UP, KEY_W], [DOWN, KEY_S],
			[INTERACT, KEY_E], [TARGET, KEY_Q]]:
		var key := InputEventKey.new()
		key.physical_keycode = entry[1]
		_add_default(entry[0], key)
	for entry: Array in [[DESTINATION, MOUSE_BUTTON_RIGHT], [MANUAL, MOUSE_BUTTON_LEFT]]:
		var pointer := InputEventMouseButton.new()
		pointer.button_index = entry[1]
		_add_default(entry[0], pointer)


static func _add_default(action: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		InputMap.action_add_event(action, event)


## A layout update is atomic. It can swap two occupied bindings together.
static func rebind(layout: Dictionary[StringName, InputEvent]) -> bool:
	for action: StringName in layout:
		if action not in ACTIONS or not _supported_binding(action, layout[action]):
			return false
	for index: int in ACTIONS.size():
		var first: StringName = ACTIONS[index]
		var first_events := _layout_events(first, layout)
		for next: int in range(index + 1, ACTIONS.size()):
			var second_events := _layout_events(ACTIONS[next], layout)
			for left: InputEvent in first_events:
				for right: InputEvent in second_events:
					if left.is_match(right):
						return false
	for action: StringName in layout:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, layout[action].duplicate())
	return true


static func _layout_events(action: StringName, layout: Dictionary[StringName, InputEvent]) -> Array[InputEvent]:
	if layout.has(action):
		return [layout[action]]
	return InputMap.action_get_events(action) if InputMap.has_action(action) else []


static func _supported_binding(action: StringName, event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.keycode != KEY_NONE or event.physical_keycode != KEY_NONE
	return (action not in AXES and event is InputEventMouseButton
		and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE,
			MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2])


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_pointer = event.position
	if event is InputEventMouseButton and _supported_binding(MANUAL, event):
		if not event.pressed:
			var world_owned: bool = _mouse_down.get(event.button_index, false)
			_mouse_down.erase(event.button_index)
			if world_owned:
				get_viewport().set_input_as_handled()
		elif _mouse_down.has(event.button_index):
			get_viewport().set_input_as_handled()
		else:
			_mouse_down[event.button_index] = false
	if event is InputEventKey:
		var id := _key_id(event)
		if not event.pressed:
			_key_down.erase(id)
			if _held.erase(id):
				_queue_axes()
		elif not event.echo:
			if _key_down.has(id):
				get_viewport().set_input_as_handled()
			else:
				_key_down[id] = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_aim = _position_command(PlayerCommand.AIM)
		return
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventMouseButton and _mouse_down.has(event.button_index):
		_mouse_down[event.button_index] = true
	for action: StringName in AXES:
		if event is InputEventKey and event.is_action_pressed(action, false, true):
			_held[_key_id(event)] = action
			_queue_axes()
			get_viewport().set_input_as_handled()
			return
	for pair: Array in [[DESTINATION, PlayerCommand.MOVE_TO], [MANUAL, PlayerCommand.MANUAL],
			[INTERACT, PlayerCommand.INTERACT], [TARGET, PlayerCommand.TARGET]]:
		if event.is_action_pressed(pair[0], false, true):
			if pair[0] != DESTINATION or _held.is_empty():
				_queue(_position_command(pair[1]))
			get_viewport().set_input_as_handled()
			return


func drain() -> Array[PlayerCommand]:
	var finished := _pending
	_pending = []
	if _overflow:
		finished = [_axes_command()]
	elif _aim != null:
		finished.append(_aim)
	_aim = null
	_overflow = false
	return finished


func clear_focus() -> void:
	_held.clear()
	_key_down.clear()
	_mouse_down.clear()
	_pending.clear()
	_aim = null
	_overflow = false
	_queue_axes()


func _position_command(kind: StringName) -> PlayerCommand:
	if not world_from_viewport.is_valid():
		return null
	var point: RealmSweep.Point = world_from_viewport.call(_pointer)
	if point == null:
		return null
	return PlayerCommand.new(kind, point.x, point.y)


func _queue_axes() -> void:
	_queue(_axes_command())


func _axes_command() -> PlayerCommand:
	var directions := _held.values()
	return PlayerCommand.new(PlayerCommand.MOVE_AXES, float(int(RIGHT in directions) - int(LEFT in directions)),
		float(int(DOWN in directions) - int(UP in directions)))


func _queue(command: PlayerCommand) -> void:
	if command == null or _overflow:
		return
	if _pending.size() == MAX_PENDING:
		_pending.clear()
		_overflow = true
	else:
		_pending.append(command)


static func _key_id(event: InputEventKey) -> int:
	return event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
