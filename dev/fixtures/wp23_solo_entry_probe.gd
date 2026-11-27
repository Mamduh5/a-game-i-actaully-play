extends Node
## Exercise the real application entry and ordinary viewport input.

const SHELL := preload("res://src/app/main.tscn")
const PROFILE_ID := "wp23-solo"
var _capture_dir: String
var _captures_ok := true


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "read-solo" in args:
		_read_back()
		return
	for arg: String in args:
		if arg.begins_with("--capture="):
			_capture_dir = arg.trim_prefix("--capture=")
	_exercise.call_deferred()


func _exercise() -> void:
	var shell := SHELL.instantiate()
	get_tree().root.add_child(shell)
	await get_tree().process_frame
	await get_tree().process_frame
	var input := shell.get_node("%ProfileName") as LineEdit
	var open := shell.get_node("%OpenProfile") as Button
	var start := shell.get_node("%StartSolo") as Button
	if not input.is_visible_in_tree() or not open.is_visible_in_tree():
		_fail("profile entry")
		return
	input.text = PROFILE_ID
	await _capture("profile.png")
	_click(open.get_global_rect().get_center())
	await get_tree().process_frame
	if not start.is_visible_in_tree() or shell._profile == null:
		_fail("opened profile")
		return
	await _capture("preparation.png")
	_click(start.get_global_rect().get_center())
	var run := shell._solo as SoloStarterRun
	if run == null:
		_fail("start control")
		return
	var authority := run.authority
	var first_id: StringName = authority.checkpoint().identity.run
	var view := authority.view_for(SoloStarterRun.SEAT)
	var from := view.player.at
	if view.others.size() < 2:
		_fail("start view")
		return
	var target := view.others[1].at
	_click(run._stage.to_global(Vector2(target.x, target.y)), MOUSE_BUTTON_RIGHT)
	var maximum_tick := authority.next_tick() + 225
	var warned := false
	while view != null and not view.cleared and not view.defeated and authority.next_tick() < maximum_tick:
		await get_tree().physics_frame
		view = authority.view_for(SoloStarterRun.SEAT)
		if view != null and not warned and not view.threats.is_empty():
			warned = true
			await _capture("combat.png")
	var ack := authority.movement_acknowledgement(SoloStarterRun.SEAT)
	if (view == null or not view.cleared or not warned or ack < 1 or view.player.at.x <= from.x
			or run._earnings.pending_amount().native_at_scale(0) != 6
			or shell._profile.balance(StarterEncounter.COMMON_CURRENCY).sign_value != 0):
		print("WP23_SOLO_DIAGNOSTIC ", JSON.stringify({"tick": authority.next_tick(),
			"cleared": view != null and view.cleared, "warned": warned, "ack": ack,
			"moved": view != null and view.player.at.x > from.x,
			"pending": run._earnings.pending_amount().native_at_scale(0)}))
		_fail("live encounter and earnings")
		return
	await _capture("cleared.png")
	_click(run._end.get_global_rect().get_center())
	await get_tree().process_frame
	var saved: int = shell._profile.balance(StarterEncounter.COMMON_CURRENCY).native_at_scale(0)
	if shell._solo != null or not start.is_visible_in_tree() or saved != 6:
		_fail("return and flush")
		return
	await _capture("saved.png")
	var weapon := shell.get_node("%WeaponChoice") as OptionButton
	weapon.select(1)
	_click(start.get_global_rect().get_center())
	var second := shell._solo as SoloStarterRun
	if second == null or second.authority.belongs_to(first_id, 1):
		_fail("next run")
		return
	await get_tree().process_frame
	_click(second._end.get_global_rect().get_center())
	if shell._solo != null or ProfileOrdinarySession.reopen_status(shell._profile) != ProfileOrdinarySession.ReopenStatus.CLEAR:
		_fail("second run close")
		return
	print("WP23_SOLO_ENTRY ", JSON.stringify({"passed": _captures_ok, "moved": true, "cleared": true,
		"earnings": saved, "separate_run": true, "generation": shell._profile.checkpoint().generation}))
	get_tree().quit(0 if _captures_ok else 1)


func _click(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = at
		event.global_position = at
		get_viewport().push_input(event, true)


func _capture(name: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_captures_ok = get_viewport().get_texture().get_image().save_png(_capture_dir.path_join(name)) == OK and _captures_ok


func _read_back() -> void:
	var profile := ProfileStore.new()
	if profile.open(PROFILE_ID) != ProfileStore.OpenResult.OPENED:
		_fail("cold reopen")
		return
	var balance: int = profile.balance(StarterEncounter.COMMON_CURRENCY).native_at_scale(0)
	var generation: int = profile.checkpoint().generation
	var clear := ProfileOrdinarySession.reopen_status(profile) == ProfileOrdinarySession.ReopenStatus.CLEAR
	var saved := profile.close()
	var passed := balance == 6 and generation == 5 and clear and saved
	print("WP23_SOLO_READ ", JSON.stringify({"passed": passed, "balance": balance, "generation": generation, "clear": clear}))
	get_tree().quit(0 if passed else 1)


func _fail(stage: String) -> void:
	print("WP23_SOLO_ENTRY ", JSON.stringify({"passed": false, "stage": stage}))
	get_tree().quit(1)
