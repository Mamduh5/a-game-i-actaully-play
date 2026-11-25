extends Node2D
## Compare the original and replacement at native scale using fixed fixture geometry.

const Assets: Array[VisualAsset] = [
	preload("res://dev/fixtures/asset_pipeline/waystone.tres"),
	preload("res://dev/fixtures/asset_pipeline/waystone_alternate.tres"),
]
const Cue := preload("res://dev/fixtures/asset_pipeline/derived/waystone_cue.ogg")
const PhaseNames := ["Launch", "Active", "Recovery"]
const PhaseMillis := [180, 120, 260]
const FootprintRadius := 15.0
const ImpactRadius := 32.0
const LightInk := Color("#292823")
const DarkInk := Color("#f0e8d6")

var _variant := 0
var _overlay := false
var _views: Array[AnimatedSprite2D] = []
var _status := Label.new()
var _audio := AudioStreamPlayer.new()
var _guides := Node2D.new()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_status.position = Vector2(64, 116)
	_status.add_theme_color_override("font_color", LightInk)
	add_child(_status)
	for panel: int in 2:
		for phase: int in 3:
			var view := AnimatedSprite2D.new()
			view.position = _anchor(panel, phase)
			add_child(view)
			_views.append(view)
	_guides.draw.connect(_draw_guides)
	add_child(_guides)
	_add_button("Swap artwork", Vector2(64, 608), _swap)
	_add_button("Geometry overlay", Vector2(228, 608), _toggle_overlay)
	_add_button("Play cue", Vector2(392, 608), _audio.play)
	_audio.stream = Cue
	add_child(_audio)
	_bind()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--wp15-capture="):
			_capture.call_deferred(arg.trim_prefix("--wp15-capture="))


func _add_button(label: String, anchor: Vector2, action: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.position = anchor
	button.size = Vector2(152, 44)
	button.pressed.connect(action)
	add_child(button)


func _anchor(panel: int, phase: int) -> Vector2:
	return Vector2(148.0 + panel * 584.0 + phase * 184.0, 381.0)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("#ede8dc"))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(64, 89), "Development fixture · Replaceable artwork", HORIZONTAL_ALIGNMENT_LEFT, -1, 35, LightInk)
	for panel: int in 2:
		var x := 64.0 + 584.0 * panel
		var ink := LightInk if panel == 0 else DarkInk
		var ground := Color("#f8f2e4") if panel == 0 else Color("#34353a")
		draw_rect(Rect2(x, 174, 568, 388), ground)
		draw_string(font, Vector2(x + 24, 222), "Light paper" if panel == 0 else "Dark ground",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 25, ink)
		for phase: int in 3:
			var anchor := _anchor(panel, phase)
			var label := "%s · %d ms" % [PhaseNames[phase], PhaseMillis[phase]]
			draw_string(font, anchor + Vector2(-88, 90), label, HORIZONTAL_ALIGNMENT_CENTER, 176, 19, ink)
			_draw_tell(anchor, phase)


func _draw_guides() -> void:
	if not _overlay:
		return
	for panel: int in 2:
		var ink := LightInk if panel == 0 else DarkInk
		for phase: int in 3:
			var anchor := _anchor(panel, phase)
			_guides.draw_arc(anchor, FootprintRadius, 0, TAU, 64, ink, 1.0, true)
			_guides.draw_line(anchor - Vector2(7, 0), anchor + Vector2(7, 0), ink, 1.0, true)
			_guides.draw_line(anchor - Vector2(0, 7), anchor + Vector2(0, 7), ink, 1.0, true)
			var socket: Vector2 = anchor + Assets[_variant].sockets[&"rune"]
			_guides.draw_line(socket, socket - Vector2(53, 19), ink, 1.0, true)
			_guides.draw_circle(socket, 2.0, Color("#ffb65e"), true, -1, true)
			_guides.draw_circle(anchor + Vector2(27, 0), 3.0, Color("#e59f64"), true, -1, true)
			_guides.draw_circle(anchor + Vector2(38, 0), 3.0, Color("#6badd6"), true, -1, true)


func _draw_tell(anchor: Vector2, phase: int) -> void:
	if phase == 0:
		for dash: int in 8:
			var start := dash * TAU / 8.0
			draw_arc(anchor, ImpactRadius, start, start + 0.43, 10, Color("#c88850"), 2.0, true)
	elif phase == 1:
		draw_circle(anchor, ImpactRadius, Color(0.78, 0.47, 0.22, 0.20), true, -1, true)
		draw_arc(anchor, ImpactRadius, 0, TAU, 64, Color("#c88850"), 3.0, true)
	else:
		draw_arc(anchor, FootprintRadius + 6.0, 0, TAU, 48, Color("#948778"), 1.0, true)


func _swap() -> void:
	_variant = 1 - _variant
	_bind()


func _toggle_overlay() -> void:
	_overlay = not _overlay
	_guides.queue_redraw()


func _bind() -> void:
	var asset: VisualAsset = Assets[_variant]
	for index: int in _views.size():
		var view: AnimatedSprite2D = _views[index]
		asset.bind_view(view)
		view.animation = &"cue"
		view.frame = index % 3
	_status.text = "%s  ·  %d × %d px  ·  1:1" % [asset.visual_id, asset.frame_size.x, asset.frame_size.y]
	_guides.queue_redraw()


func _trace() -> Array[Dictionary]:
	var outcomes: Array[Dictionary] = []
	var time_ms := 0
	for phase: int in 3:
		var hits: Array[int] = []
		if phase == 1:
			for distance: int in [27, 38]:
				if distance * distance <= ImpactRadius * ImpactRadius:
					hits.append(distance)
		outcomes.append({"start_ms": time_ms, "duration_ms": PhaseMillis[phase], "hits": hits})
		time_ms += PhaseMillis[phase]
	return outcomes


func _capture(path: String) -> void:
	var authority := _trace()
	for variant: int in Assets.size():
		_variant = variant
		for overlay: bool in [false, true]:
			_overlay = overlay
			_bind()
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			var filename := "art-%d-%s.png" % [variant, "overlay" if overlay else "clean"]
			if image.save_png(path.path_join(filename)) != OK or _trace() != authority:
				push_error("WP15 image save or fixture trace failed")
				get_tree().quit(1)
				return
			var asset: VisualAsset = Assets[variant]
			var observed: Array[int] = []
			for index: int in asset.frames.get_frame_count(&"cue"):
				var seconds := asset.frames.get_frame_duration(&"cue", index) / asset.frames.get_animation_speed(&"cue")
				observed.append(roundi(1000.0 * seconds))
			if observed != PhaseMillis:
				push_error("WP15 Godot import changed frame duration")
				get_tree().quit(1)
				return
			print("WP15_DRAW ", asset.visual_id, " overlay=", overlay, " source-ms=", observed, " trace=", authority)
		if not await _measure_playback():
			push_error("WP15 playback did not follow the imported frame timings")
			get_tree().quit(1)
			return
	_audio.play()
	await get_tree().create_timer(0.09).timeout
	var position_seconds := _audio.get_playback_position()
	if not _audio.playing or position_seconds <= 0.0:
		push_error("WP15 cue playback did not advance")
		get_tree().quit(1)
		return
	print("WP15_AUDIO playing=", _audio.playing, " elapsed=", position_seconds, " duration=", Cue.get_length(),
		" driver=", AudioServer.get_driver_name())
	get_tree().quit(0)


func _measure_playback() -> bool:
	var view: AnimatedSprite2D = _views[0]
	var changes: Array[int] = []
	var started := Time.get_ticks_msec()
	var track := func() -> void:
		changes.append(Time.get_ticks_msec() - started)
	view.frame_changed.connect(track)
	view.play(&"cue")
	await view.animation_finished
	view.frame_changed.disconnect(track)
	changes.append(Time.get_ticks_msec() - started)
	print("WP15_PLAYBACK ", Assets[_variant].visual_id, " observed-ms=", changes)
	var expected: Array[int] = [180, 300, 560]
	if changes.size() != expected.size():
		return false
	for index: int in expected.size():
		if absi(changes[index] - expected[index]) > 50:
			return false
	return true
