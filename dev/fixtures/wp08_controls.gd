extends Node2D
## Native viewport fixture. The drawing depends on the closed position; the
## router submits the same typed envelopes as a local fixed-step adapter.

const Rules := preload("res://dev/fixtures/wp08_controls_rules.gd")

var state := Rules.new()
var router := PlayerInputRouter.new()
var reward_count: int
var sequence: int
var facts: Dictionary = {}
var _caption: Label
var _panel: PanelContainer
var _reward: Button
var _swapped := false


func _ready() -> void:
	var setup := RunSetup.new()
	setup.run_id = &"wp08_controls"
	setup.authority_id = &"local"
	setup.epoch = 1
	setup.rules_revision = &"controls_v1"
	setup.catalog_revision = &"fixture"
	setup.challenge_id = &"fixture"
	setup.initial_realms = {Rules.PLAYER: Rules.REALM}
	if not state.initialize() or not state.start(setup, &"local"):
		get_tree().quit(1)
		return
	router.world_from_viewport = _world_point
	add_child(router)
	_add_controls()


func _add_controls() -> void:
	var overlay := CanvasLayer.new()
	add_child(overlay)
	_panel = PanelContainer.new()
	_panel.position = Vector2(930, 180)
	_panel.custom_minimum_size = Vector2(270, 220)
	overlay.add_child(_panel)
	var choices := VBoxContainer.new()
	_panel.add_child(choices)
	_reward = Button.new()
	_reward.name = "FixtureReward"
	_reward.text = "Record sample choice"
	_reward.custom_minimum_size = Vector2(0, 72)
	_reward.pressed.connect(func() -> void: reward_count += 1)
	choices.add_child(_reward)
	var swap := Button.new()
	swap.text = "Swap mouse and use arrows"
	swap.custom_minimum_size = Vector2(0, 58)
	swap.pressed.connect(_swap_layout)
	choices.add_child(swap)
	_caption = Label.new()
	_caption.position = Vector2(32, 26)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_theme_color_override("font_color", Color(0.1, 0.12, 0.13))
	overlay.add_child(_caption)


func _physics_process(_delta: float) -> void:
	for command: PlayerCommand in router.drain():
		sequence += 1
		var envelope := RunIntent.new(&"wp08_controls", 1, Rules.REALM, Rules.PLAYER, state.next_tick(),
			sequence, command.action, command)
		if state.submit(Rules.PLAYER, envelope) != RunAuthority.Admission.QUEUED:
			push_error("WP08 fixture rejected a local envelope")
	if not state.close_tick():
		return
	var result := state.closed_result()
	facts = result["outcomes"][0]
	var binding_line := "Arrows / left mouse to move    Right mouse manual" if _swapped else (
		"WASD / right mouse to move    Left mouse manual")
	_caption.text = ("WP08 controls fixture    %s    E interact    Q target\n" +
		"Tick %d    Choices %d    Manual %d    Interactions %d    Target %s    Launch/hit/miss %d/%d/%d") % [
		binding_line, result["tick"], reward_count, state.manual_count, state.interaction_count,
		str(state.marked), state.launches, state.hits, state.misses]
	queue_redraw()


func _swap_layout() -> void:
	var layout: Dictionary[StringName, InputEvent] = {
		PlayerInputRouter.LEFT: _key(KEY_LEFT), PlayerInputRouter.RIGHT: _key(KEY_RIGHT),
		PlayerInputRouter.UP: _key(KEY_UP), PlayerInputRouter.DOWN: _key(KEY_DOWN),
		PlayerInputRouter.DESTINATION: _button(MOUSE_BUTTON_LEFT),
		PlayerInputRouter.MANUAL: _button(MOUSE_BUTTON_RIGHT),
	}
	if not PlayerInputRouter.rebind(layout):
		push_error("WP08 fixture could not swap the control layout")
	else:
		_swapped = true
		_caption.add_theme_color_override("font_color", Color(0.13, 0.31, 0.25))


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.86, 0.83, 0.74))
	draw_line(Vector2(825, 180), Vector2(825, 575), Color(0.27, 0.28, 0.3), 8)
	var position := state.geometry.circle_center(Rules.PLAYER, 0)
	if position == null:
		return
	var center := Vector2(position.x, position.y)
	draw_circle(center, 14, Color(0.14, 0.32, 0.36))
	draw_line(center, center + Vector2(state.aim.x, state.aim.y) * 23.0, Color(0.1, 0.15, 0.17), 3)
	for item: PlayerTargeting.Candidate in state.candidates:
		var body := Vector2(item.position.x, item.position.y)
		draw_circle(body, 18, Color(0.56, 0.26, 0.22) if item.kind == PlayerTargeting.Kind.HOSTILE else Color(0.42, 0.39, 0.25))
		draw_string(ThemeDB.fallback_font, body + Vector2(-27, 38), String(item.id), HORIZONTAL_ALIGNMENT_LEFT,
			-1, 15, Color(0.13, 0.12, 0.11))
	if state.shot != null:
		draw_circle(Vector2(state.shot.x, state.shot.y), 5, Color(0.08, 0.11, 0.2))


func _world_point(screen: Vector2) -> RealmSweep.Point:
	var point := get_global_transform_with_canvas().affine_inverse() * screen
	return RealmSweep.Point.new(point.x, point.y)


static func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event


static func _button(index: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	return event
