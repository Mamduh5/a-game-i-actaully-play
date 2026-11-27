extends Node2D
## Same renderer, bindings and policy pipe on either side of the connection.

const Actuator := preload("res://dev/fixtures/visible_pilot/pilot_actuator.gd")
const Policy := preload("res://dev/fixtures/visible_pilot/pilot_policy_client.gd")
const MOVEMENT: Array[StringName] = [PlayerInputRouter.LEFT, PlayerInputRouter.RIGHT,
	PlayerInputRouter.UP, PlayerInputRouter.DOWN]
const PASSAGE := Vector2(256, 135)
const GOAL := Vector2(454, 128)

var stage := StarterEncounterView.new()
var _router := PlayerInputRouter.new()
var _pilot := Policy.new()
var _actuator: Actuator
var _title := Label.new()
var _status := Label.new()
var _control := Label.new()
var _displayed: StarterEncounter.View
var _directory: String
var _inputs: FileAccess
var _fault := false
var _captured_warning := false


func start(role: String, preset: String, python: String, policy: String, directory: String) -> bool:
	_directory = directory
	_inputs = FileAccess.open(directory.path_join("input.jsonl"), FileAccess.WRITE)
	get_window().title = "A Game I Actually Play | WP32 " + role
	RenderingServer.set_default_clear_color(Color("#1e2b29"))
	add_child(stage)
	var build := "The Undying · Sword" if preset == "sword" else "The Conductor · Bow"
	_make_label(_title, 31, "%s — %s" % [role.capitalize(), build])
	_make_label(_status, 21, "Connecting")
	_make_label(_control, 19, "Clear both rooms and reach the marked circle")
	_layout()
	get_viewport().size_changed.connect(_layout)
	_router.world_from_viewport = stage.world_from_viewport
	add_child(_router)
	_actuator = Actuator.new(get_viewport(), MOVEMENT, false)
	return _inputs != null and _pilot.start(python, policy)


func commands(tick: int) -> Array[PlayerCommand]:
	var decision := _pilot.poll()
	if not decision.is_empty():
		if bool(decision.get("manual", true)) or not _actuator.apply(decision):
			_fault = true
			return []
		_record({"relative_usec": Time.get_ticks_usec(), "tick": tick, "decision": decision})
	var translated := _router.drain()
	for command: PlayerCommand in translated:
		_record({"tick": tick, "action": command.action, "xy": [command.x, command.y]})
	if _displayed != null and not _pilot.pending():
		var observation := _visible_sample()
		if not _pilot.send(observation):
			_fault = true
		_record({"tick": _displayed.tick, "visible": observation})
	return translated


func present(view: StarterEncounter.View) -> void:
	_displayed = view
	stage.display(view)
	_status.text = "HP %s   Barrier %s   Ability %s" % [view.player.hp.native_at_scale(0),
		view.barrier.native_at_scale(0), "Ready" if view.manual_ready else "Recovering"]
	if view.cleared:
		_control.text = "Encounter clear · Reach the marked circle"
	if not _captured_warning and not view.threats.is_empty():
		_captured_warning = true
		capture("warning.png")


func capture(file: String) -> void:
	await RenderingServer.frame_post_draw
	if get_viewport().get_texture().get_image().save_png(_directory.path_join(file)) != OK:
		_fault = true


func failed() -> bool:
	return _fault or _pilot.failed()


func shutdown() -> void:
	_pilot.close()
	if _actuator != null:
		_actuator.release()
	if _inputs != null:
		_inputs.close()


func _record(row: Dictionary) -> void:
	_inputs.store_line(JSON.stringify(row))


func _visible_sample() -> Dictionary:
	var enemies: Array[Array] = []
	var viewport := get_viewport_rect()
	for fighter: StarterEncounter.Fighter in _displayed.others:
		var at := _pixel(Vector2(fighter.at.x, fighter.at.y))
		if fighter.enemy and viewport.has_point(Vector2(at[0], at[1])):
			enemies.append(at)
	var warnings: Array[Array] = []
	for warning: WorldEnemy.Threat in _displayed.threats:
		var at := _pixel(Vector2(warning.center.x, warning.center.y))
		if viewport.has_point(Vector2(at[0], at[1])):
			warnings.append([at, roundi(warning.radius * stage.scale.x)])
	var avatar := _displayed.player
	return {"player": _pixel(Vector2(avatar.at.x, avatar.at.y)), "radius": roundi(avatar.radius * stage.scale.x),
		"enemies": enemies, "warnings": warnings, "manual_ready": _displayed.manual_ready,
		"goal": _pixel(GOAL), "passage": _pixel(PASSAGE)}


func _pixel(at: Vector2) -> Array[int]:
	var pixel := stage.get_global_transform_with_canvas() * at
	return [roundi(pixel.x), roundi(pixel.y)]


func _make_label(label: Label, size: int, message: String) -> void:
	label.text = message
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("#e6ece6"))
	add_child(label)


func _layout() -> void:
	var available := get_viewport_rect().size
	var magnification := minf(available.x / 586.0, available.y / 465.0)
	stage.scale = Vector2.ONE * magnification
	stage.position = Vector2((available.x - 512.0 * magnification) * 0.5, available.y * 0.49 - 128.0 * magnification)
	_title.position = Vector2(stage.position.x, 24)
	_status.position = Vector2(stage.position.x, 68)
	_control.position = Vector2(stage.position.x, stage.position.y + 256.0 * magnification + 22)
