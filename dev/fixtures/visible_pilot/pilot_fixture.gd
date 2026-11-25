extends Node2D
## Synthetic course for the supervised pilot. All actions pass through the viewport.

const Policy := preload("res://dev/fixtures/visible_pilot/pilot_policy_client.gd")
const Actuator := preload("res://dev/fixtures/visible_pilot/pilot_actuator.gd")
const Evidence := preload("res://dev/fixtures/visible_pilot/pilot_evidence.gd")
const COURSE_SPEED := 240.0
const BEACON := Vector2(952, 360)
const HAZARD := Rect2(425, 288, 208, 144)
const WARNING_TICKS := 48
const DECISION_STRIDE := 4
const MAX_TICKS := 900

var _position := Vector2(144, 360)
var _keys: Dictionary[StringName, bool] = {}
var _tick := 0
var _warning_since := 0
var _wet_ticks := 0
var _manual_uses := 0
var _world_clicks := 0
var _interactions := 0
var _hidden_variant := "alpha"
var _hidden_fixture: Dictionary
var _button := Button.new()
var _manual_key: Key = KEY_F
var _policy := Policy.new()
var _actuator: Actuator
var _evidence := Evidence.new()
var _capture_dir := ""
var _worker := false
var _replaying := false
var _replay: Dictionary[int, Dictionary] = {}
var _last_request: Dictionary = {}


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--wp14-rebind":
			_manual_key = KEY_G
		elif arg.begins_with("--wp14-hidden="):
			_hidden_variant = arg.trim_prefix("--wp14-hidden=")
		elif arg.begins_with("--wp14-evidence="):
			_capture_dir = arg.trim_prefix("--wp14-evidence=")
	_register_binding(Actuator.LEFT, KEY_A)
	_register_binding(Actuator.RIGHT, KEY_D)
	_register_binding(Actuator.UP, KEY_W)
	_register_binding(Actuator.DOWN, KEY_S)
	_register_binding(Actuator.MANUAL, _manual_key)
	_actuator = Actuator.new(get_viewport())
	_button.position = Vector2(900, 475)
	_button.custom_minimum_size = Vector2(154, 52)
	_button.text = "Inspect beacon"
	_button.hide()
	_button.pressed.connect(_interact)
	add_child(_button)
	_hidden_fixture = {"recipe": "unknown-a", "actor_x": 1131} if _hidden_variant == "alpha" \
		else {"recipe": "unknown-b", "actor_x": 1193}
	if not _capture_dir.is_empty():
		set_physics_process(false)
		if not _evidence.open(_capture_dir.path_join("evidence.jsonl")):
			_stop(false, "evidence file unavailable")
			return
		_initialize_run.call_deferred()


func _initialize_run() -> void:
	await RenderingServer.frame_post_draw
	if not _capture("start.png"):
		_stop(false, "initial frame unavailable")
		return
	_evidence.record("fixture", 0, {"hidden": _hidden_fixture, "policy": "wp14-visible-1",
		"manual_key": OS.get_keycode_string(_manual_key), "profile": "disposable fixture",
		"interventions": ["launcher started the labeled course"]})
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--wp14-policy="):
			var view_path := ProjectSettings.globalize_path("res://tools/pilot/wp14_policy.py")
			_worker = _policy.start(arg.trim_prefix("--wp14-policy="), view_path)
		elif arg.begins_with("--wp14-replay="):
			_replaying = _load_replay(arg.trim_prefix("--wp14-replay="))
	if _worker == _replaying:
		_stop(false, "expected one successful worker or replay")
		return
	print("WP14_READY fixture=visible_pilot mode=", "policy" if _worker else "replay")
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_tick += 1
	if _worker and not _policy_tick():
		_stop(false, "policy pipe, envelope or input failed")
		return
	if _replaying and _replay.has(_tick):
		if not _apply(_replay[_tick]):
			_stop(false, "recorded input rejected")
			return
	var direction := Vector2(
		int(_keys.get(Actuator.RIGHT, false)) - int(_keys.get(Actuator.LEFT, false)),
		int(_keys.get(Actuator.DOWN, false)) - int(_keys.get(Actuator.UP, false))
	)
	_position += direction.normalized() * COURSE_SPEED * delta
	_position = _position.clamp(Vector2(90, 197), Vector2(1080, 532))
	if _warning_since == 0 and _position.x >= 292:
		_warning_since = _tick
		_evidence.record("warning", _tick, {"player": _point(_position)})
	if _active_hazard() and HAZARD.has_point(_position):
		_wet_ticks += 1
	queue_redraw()
	if _worker or _replaying:
		if _interactions > 0:
			_stop(_manual_uses == 1 and _wet_ticks == 0 and _world_clicks == 0, "course completed")
		elif _tick >= MAX_TICKS:
			_stop(false, "course timed out")


func _policy_tick() -> bool:
	var command := _policy.poll()
	if _policy.failed():
		return false
	if not command.is_empty():
		_evidence.record("decision", _tick, {"view": _last_request, "command": command})
		if not _apply(command):
			return false
	if _tick % DECISION_STRIDE == 1 and not _policy.pending():
		_last_request = _projection()
		return _policy.send(_last_request)
	return true


func _apply(command: Dictionary) -> bool:
	if not _actuator.apply(command):
		return false
	_evidence.record("input", _tick, command)
	return true


func _register_binding(action: StringName, physical_key: Key) -> void:
	InputMap.add_action(action)
	var input := InputEventKey.new()
	input.physical_keycode = physical_key
	InputMap.action_add_event(action, input)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		for action: StringName in Actuator.MOVEMENT:
			if event.is_action(action):
				_keys[action] = event.is_pressed()
				get_viewport().set_input_as_handled()
				return
		if event.is_action_pressed(Actuator.MANUAL) and _manual_ready():
			_manual_uses += 1
			_button.show()
			_evidence.record("manual", _tick, {"physical_key": event.physical_keycode, "player": _point(_position)})
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_world_clicks += 1


func _interact() -> void:
	_interactions += 1
	var focus := get_viewport().gui_get_focus_owner()
	_evidence.record("interaction", _tick, {"focused": focus == _button, "player": _point(_position)})
	_button.disabled = true


func _manual_ready() -> bool:
	return _manual_uses == 0 and _position.distance_squared_to(BEACON) <= 76.0 * 76.0


func _active_hazard() -> bool:
	return _warning_since != 0 and _tick >= _warning_since + WARNING_TICKS


func _projection() -> Dictionary:
	var hazard: Array[int] = []
	if _warning_since != 0:
		hazard.append_array(_point(HAZARD.position))
		hazard.append_array(_point(HAZARD.end))
	var click: Array[int] = []
	if _button.visible and not _button.disabled:
		click = _point(_button.get_global_rect().get_center())
	return {"player": _point(_position), "beacon": _point(BEACON), "hazard": hazard,
		"manual_ready": _manual_ready(), "button": click, "complete": _interactions > 0}


func _draw() -> void:
	var view := _projection()
	var ink := Color("#292b31")
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, 1280, 720), Color("#ede6d4"))
	draw_rect(Rect2(64, 173, 1050, 385), Color("#f7f0de"))
	draw_string(font, Vector2(64, 84), "Development fixture · Visible-input course",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 36, ink)
	var manual := OS.get_keycode_string(_manual_key)
	draw_string(font, Vector2(64, 127), "WASD to move   ·   %s near the beacon   ·   Click Inspect" % manual,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
	if not view["hazard"].is_empty():
		var color := Color("#ad593c") if _active_hazard() else Color("#98733b")
		draw_rect(HAZARD, Color(color, 0.20))
		draw_rect(HAZARD, color, false, 3.0)
		draw_string(font, HAZARD.position + Vector2(12, 30), "Active" if _active_hazard() else "Warning",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)
	draw_circle(BEACON, 23, Color("#a68145"), false, 4.0, true)
	draw_string(font, BEACON + Vector2(-42, -38), "Beacon", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
	draw_circle(Vector2(view["player"][0], view["player"][1]), 13, Color("#385c68"), true, -1, true)
	var status := "Inspect the beacon"
	if view["complete"]:
		status = "Course complete"
	elif view["manual_ready"]:
		status = "Press %s to reveal the interaction" % manual
	elif _manual_uses == 0:
		status = "Reach the beacon"
	draw_string(font, Vector2(64, 610), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 25, ink)


func _load_replay(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty():
			continue
		var parser := JSON.new()
		if parser.parse(line) != OK or not parser.data is Dictionary:
			return false
		var row: Dictionary = parser.data
		if row.get("kind") == "input":
			var at := int(row.get("tick", 0))
			if at < 1 or at > MAX_TICKS or _replay.has(at) or not row.get("data") is Dictionary:
				return false
			_replay[at] = row["data"]
	return not _replay.is_empty()


func _stop(passed: bool, reason: String) -> void:
	set_physics_process(false)
	_policy.close()
	if _actuator != null:
		_actuator.release()
	var result := {"passed": passed, "reason": reason, "player": _point(_position),
		"danger_ticks": _wet_ticks, "manual_uses": _manual_uses, "interactions": _interactions,
		"world_pointer_events": _world_clicks}
	_evidence.record("result", _tick, result)
	_evidence.close()
	print("WP14_RESULT ", JSON.stringify(result))
	_finish.call_deferred(passed)


func _finish(passed: bool) -> void:
	await RenderingServer.frame_post_draw
	var saved := _capture("end.png")
	get_tree().quit(0 if passed and saved else 1)


func _capture(filename: String) -> bool:
	var image := get_viewport().get_texture().get_image()
	return image != null and image.save_png(_capture_dir.path_join(filename)) == OK


static func _point(value: Vector2) -> Array[int]:
	return [roundi(value.x), roundi(value.y)]
