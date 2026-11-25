extends GutTest


class Commands:
	extends RunAuthority

	func _supports_action(action: StringName) -> bool:
		return action in PlayerCommand.ACTIONS


func test_semantic_payload_is_copied_and_conflicts_are_arrival_independent() -> void:
	var authority := Commands.new()
	var setup := RunSetup.new()
	setup.run_id = &"controls"
	setup.authority_id = &"local"
	setup.epoch = 1
	setup.rules_revision = &"r1"
	setup.catalog_revision = &"fixture"
	setup.challenge_id = &"fixture"
	setup.initial_realms = {&"seat": &"outer"}
	assert_true(authority.start(setup, &"local"))

	var move := PlayerCommand.new(PlayerCommand.MOVE_TO, 256, 100)
	var first := _intent(move, 1)
	assert_eq(authority.submit(&"seat", first), RunAuthority.Admission.QUEUED)
	move.x = 12
	first.command.x = 99
	assert_eq(authority.submit(&"seat", _intent(PlayerCommand.new(PlayerCommand.MOVE_TO, 256, 100), 1)),
		RunAuthority.Admission.DUPLICATE)
	assert_eq(authority.submit(&"seat", first), RunAuthority.Admission.CONFLICT)
	assert_eq(authority.submit(&"seat", _intent(move, 2)), RunAuthority.Admission.QUEUED)
	assert_eq(authority.submit(&"seat", _intent(PlayerCommand.new(PlayerCommand.MOVE_AXES, 2, 0), 3)),
		RunAuthority.Admission.UNSUPPORTED_ACTION)
	assert_eq(authority.submit(&"seat", _intent(PlayerCommand.new(PlayerCommand.AIM, INF, 0), 3)),
		RunAuthority.Admission.UNSUPPORTED_ACTION)
	assert_true(authority.close_tick())
	var closed := authority.closed_result()
	assert_eq(closed["conflicts"], [{"seat": &"seat", "sequence": 1}])
	assert_eq(closed["accepted"][0]["point"], [12.0, 100.0])


func test_movement_speed_and_aim_are_independent_of_diagonal_or_crowd_overlap() -> void:
	var geometry := RealmGeometry.new(&"outer")
	assert_true(geometry.add_circle(&"player", 0, _point(0, 0), 1, 2))
	assert_true(geometry.add_circle(&"crowd", 0, _point(0, 0), 40, 2))
	var state := PlayerControlState.new()
	state.apply(PlayerCommand.new(PlayerCommand.AIM, -100, -100))
	state.apply(PlayerCommand.new(PlayerCommand.MOVE_AXES, 1, 1))
	var diagonal := state.step(geometry, &"player", 0, 1, 100, 0.1)
	assert_not_null(diagonal)
	assert_almost_eq(diagonal.x * diagonal.x + diagonal.y * diagonal.y, 100.0, 1e-12)
	assert_lt(state.aim_from(diagonal, _point(1, 0)).x, 0.0)
	assert_true(geometry.commit_circle_pose(&"player", 0, _point(0, 0)))
	state.apply(PlayerCommand.new(PlayerCommand.MOVE_AXES, 1, 0))
	var cardinal := state.step(geometry, &"player", 0, 1, 100, 0.1)
	assert_eq(cardinal.x, 10.0)
	state.apply(PlayerCommand.new(PlayerCommand.MOVE_TO, 11, 0))
	assert_eq(state.step(geometry, &"player", 0, 1, 100, 0.1).x, 11.0)


func test_voluntary_motion_uses_the_certified_blocker_and_sees_immediate_removal() -> void:
	var geometry := RealmGeometry.new(&"outer")
	var wall := RealmOutline.Edge.new()
	wall.first = _point(5, -10)
	wall.last = _point(5, 10)
	assert_true(geometry.add_segment(&"door", 0, wall, 1, false))
	assert_true(geometry.add_circle(&"player", 0, _point(0, 0), 1, 2))
	var control := PlayerControlState.new()
	control.apply(PlayerCommand.new(PlayerCommand.MOVE_TO, 10, 0))
	var clipped := control.step(geometry, &"player", 0, 1, 100, 0.1)
	assert_not_null(clipped)
	assert_almost_eq(clipped.x, 4.0, 1e-12)
	assert_eq(geometry.circle_center(&"player", 0).x, clipped.x)
	assert_true(geometry.remove_mutable(&"door", 0))
	assert_eq(control.step(geometry, &"player", 0, 1, 100, 0.1).x, 10.0)


func test_hostile_priority_and_known_deliberate_targets_have_distinct_eligibility() -> void:
	var targeting := PlayerTargeting.new()
	var candidates: Array[PlayerTargeting.Candidate] = [
		_candidate(&"cache", PlayerTargeting.Kind.SEALED_CACHE, 4.0),
		_candidate(&"enemy", PlayerTargeting.Kind.HOSTILE, 12.0),
		_candidate(&"crystal", PlayerTargeting.Kind.CRYSTAL, 20.0),
		_candidate(&"secret", PlayerTargeting.Kind.SECRET, 5.0),
		_candidate(&"hidden", PlayerTargeting.Kind.HOSTILE, 2.0),
	]
	candidates[4].known = false
	var origin := _point(0, 0)
	assert_eq(targeting.attack_target(origin, 30, candidates), &"enemy")
	assert_eq(targeting.select(origin, _point(20, 0), 30, candidates), &"crystal")
	assert_eq(targeting.attack_target(origin, 30, candidates), &"crystal")
	assert_eq(targeting.attack_target(origin, 10, candidates), &"cache")
	assert_eq(targeting.select(origin, _point(5, 0), 30, candidates), &"")
	assert_eq(targeting.select(origin, _point(2, 0), 30, candidates), &"")


func test_precision_interaction_redirects_one_eligible_opportunity() -> void:
	var targeting := PlayerTargeting.new()
	var mechanism := _candidate(&"mechanism", PlayerTargeting.Kind.MECHANISM, 4)
	mechanism.interactable = true
	mechanism.precision = true
	var enemy := _candidate(&"enemy", PlayerTargeting.Kind.HOSTILE, 3)
	var candidates: Array[PlayerTargeting.Candidate] = [mechanism, enemy]
	var origin := _point(0, 0)
	assert_eq(targeting.select(origin, _point(4, 0), 10, candidates), &"")
	assert_eq(targeting.interact(origin, _point(4, 0), 2, candidates), &"")
	assert_eq(targeting.interact(origin, _point(4, 0), 10, candidates), &"mechanism")
	mechanism.compatible = false
	assert_eq(targeting.attack_target(origin, 10, candidates), &"enemy")
	mechanism.compatible = true
	assert_eq(targeting.attack_target(origin, 10, candidates), &"mechanism")
	assert_eq(targeting.attack_target(origin, 10, candidates), &"mechanism")
	targeting.commit_attack_target(&"mechanism")
	assert_eq(targeting.attack_target(origin, 10, candidates), &"enemy")


func test_viewport_press_ownership_survives_panel_drag_closure_and_remap() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 300)
	add_child_autofree(viewport)
	var router := PlayerInputRouter.new()
	router.world_from_viewport = func(point: Vector2) -> RealmSweep.Point: return _point(point.x, point.y)
	viewport.add_child(router)
	var button := Button.new()
	button.position = Vector2(160, 40)
	button.size = Vector2(120, 80)
	viewport.add_child(button)
	watch_signals(button)
	await get_tree().process_frame
	var panel := Vector2(180, 65)
	var world := Vector2(35, 165)
	_push_mouse(viewport, panel, MOUSE_BUTTON_LEFT, true)
	button.hide()
	_push_mouse(viewport, world, MOUSE_BUTTON_LEFT, false)
	assert_eq(router.drain().size(), 0)
	button.show()
	_push_mouse(viewport, panel, MOUSE_BUTTON_LEFT, true)
	_push_mouse(viewport, panel, MOUSE_BUTTON_LEFT, false)
	assert_signal_emit_count(button, "pressed", 1)
	assert_eq(router.drain().size(), 0)

	var swap: Dictionary[StringName, InputEvent] = {
		PlayerInputRouter.MANUAL: _mouse(MOUSE_BUTTON_RIGHT),
		PlayerInputRouter.DESTINATION: _mouse(MOUSE_BUTTON_LEFT),
	}
	assert_true(PlayerInputRouter.rebind(swap))
	_push_mouse(viewport, panel, MOUSE_BUTTON_LEFT, true)
	_push_motion(viewport, world)
	_push_mouse(viewport, world, MOUSE_BUTTON_LEFT, false)
	for command: PlayerCommand in router.drain():
		assert_eq(command.action, PlayerCommand.AIM)
	assert_signal_emit_count(button, "pressed", 1)
	_push_mouse(viewport, world, MOUSE_BUTTON_LEFT, true)
	_push_motion(viewport, panel)
	_push_mouse(viewport, panel, MOUSE_BUTTON_LEFT, false)
	var world_commands := router.drain()
	var moves := 0
	for command: PlayerCommand in world_commands:
		if command.action == PlayerCommand.MOVE_TO:
			moves += 1
			assert_eq(command.x, world.x)
		else:
			assert_eq(command.action, PlayerCommand.AIM)
	assert_eq(moves, 1)
	assert_signal_emit_count(button, "pressed", 1)
	for action: StringName in PlayerInputRouter.ACTIONS:
		InputMap.erase_action(action)


func test_rebinding_held_keys_clears_the_original_direction_on_release_and_focus_loss() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(100, 100)
	add_child_autofree(viewport)
	var router := PlayerInputRouter.new()
	viewport.add_child(router)
	await get_tree().process_frame
	_push_key(viewport, KEY_D, true)
	var east := router.drain()
	assert_eq(east.size(), 1)
	if east.size() == 1:
		assert_eq(east[0].x, 1.0)
	var conflict: Dictionary[StringName, InputEvent] = {PlayerInputRouter.RIGHT: _key(KEY_A)}
	assert_false(PlayerInputRouter.rebind(conflict))
	var arrows: Dictionary[StringName, InputEvent] = {PlayerInputRouter.RIGHT: _key(KEY_RIGHT)}
	assert_true(PlayerInputRouter.rebind(arrows))
	_push_key(viewport, KEY_D, false)
	var stopped := router.drain()
	assert_eq(stopped.size(), 1)
	if stopped.size() == 1:
		assert_eq(stopped[0].x, 0.0)
	_push_key(viewport, KEY_RIGHT, true)
	router.clear_focus()
	var cleared := router.drain()
	assert_eq(cleared.size(), 1)
	if cleared.size() == 1:
		assert_eq(cleared[0].x, 0.0)
	for action: StringName in PlayerInputRouter.ACTIONS:
		InputMap.erase_action(action)


static func _intent(command: PlayerCommand, sequence: int) -> RunIntent:
	return RunIntent.new(&"controls", 1, &"outer", &"seat", 1, sequence, command.action, command)


static func _point(x: float, y: float) -> RealmSweep.Point:
	return RealmSweep.Point.new(x, y)


static func _candidate(id: StringName, kind: PlayerTargeting.Kind, x: float) -> PlayerTargeting.Candidate:
	var candidate := PlayerTargeting.Candidate.new()
	candidate.id = id
	candidate.kind = kind
	candidate.position = _point(x, 0)
	candidate.pick_radius = 0.25
	candidate.known = true
	candidate.compatible = true
	return candidate


static func _push_mouse(viewport: Viewport, point: Vector2, index: MouseButton, down: bool) -> void:
	var event := _mouse(index)
	event.position = point
	event.global_position = point
	event.pressed = down
	if down:
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if index == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	viewport.push_input(event, true)


static func _push_motion(viewport: Viewport, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	viewport.push_input(event, true)


static func _mouse(index: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	return event


static func _push_key(viewport: Viewport, code: Key, down: bool) -> void:
	var event := _key(code)
	event.pressed = down
	viewport.push_input(event, true)


static func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event
