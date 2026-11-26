extends Control
## Scripted native input witness using representative reciprocal definitions.

const Seat := &"solo"
const Starter := preload("res://src/catalog/starter_roster.tres")
const Reciprocal := preload("res://dev/fixtures/catalog_reciprocal.tres")
const Names: Dictionary[StringName, String] = {
	&"E07A": "Crimson Reservoir", &"E12A": "Mirror Guard", &"F06": "Sanguine Aegis",
}

var _panel := RunProgressionPanel.new()
var _progression: PartyProgression
var _earned := 0
var _selected: Array[StringName] = []
var _last_result: RunRewardQueue.Selection = RunRewardQueue.Selection.UNKNOWN_REWARD
var _capture_root: String


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_capture_root = args[0]
	get_window().title = "WP20 transformation reward fixture"
	RenderingServer.set_default_clear_color(Color("223039"))
	var caption := Label.new()
	caption.text = "WP20 transformation reward fixture"
	caption.position = Vector2(26.0, 28.0)
	add_child(caption)
	_panel.position = Vector2(340.0, 45.0)
	add_child(_panel)
	_panel.choice_requested.connect(_choose)
	_panel.dismissed.connect(_panel.hide)
	var passed := _begin()
	if passed:
		passed = await _exercise()
	print("WP20_TRANSFORM ", JSON.stringify({"passed": passed, "selected": _selected, "earned": _earned}))
	get_tree().quit(0 if passed else 1)


func _begin() -> bool:
	var entries: Array[CatalogEntry] = []
	for entry: CatalogEntry in Starter.entries:
		if entry.id in [&"H01", &"W01"]:
			entries.append(entry)
	entries.append_array(Reciprocal.entries)
	var catalog := DefinitionCatalog.compile(&"wp20-reciprocal", entries)
	var candidates: Array[StringName] = [&"P07", &"P12"]
	candidates.resize(RunPreparation.CANDIDATE_SLOTS)
	var prepared := RunPreparation.select(catalog, &"H01", &"W01", [&"", &""], candidates,
		{&"P07": true, &"P12": true})
	var setup := RunSetup.new()
	setup.run_id = &"transformation-fixture"
	setup.authority_id = Seat
	setup.epoch = 1
	setup.seed = 620
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = catalog.revision
	setup.challenge_id = &"normal"
	setup.initial_realms = {Seat: &"test"}
	_progression = PartyProgression.begin(setup, {Seat: prepared})
	if _progression == null:
		return false
	for base: StringName in [&"P07", &"P12"]:
		for rank: int in range(1, 6):
			var offer := _earn()
			if (offer == null or offer.options.get(base) != rank
					or _progression.select(Seat, offer.ordinal, base) != RunRewardQueue.Selection.APPLIED):
				return false
	return true


func _earn() -> RunRewardQueue.Offer:
	_earned += 1
	var need := PartyProgression.xp_to_next(_progression.level())
	var source := StringName("fixture-clear/%d" % _earned)
	if _progression.grant_xp(source, need, _earned) != PartyProgression.Award.APPLIED:
		return null
	return _progression.offer(Seat, _earned)


func _exercise() -> bool:
	for index: int in 3:
		var offer := _earn()
		if offer == null:
			return false
		var fusion := index == 2
		var id := offer.fusion if fusion else offer.evolution
		if not Names.has(id) or (fusion and _progression.active_power_form(Seat, &"P07") != &"E07A"):
			return false
		var title := "%s · %s" % [Names[id], "Fusion" if fusion else "Evolution"]
		_panel.show_offer(offer, Names)
		await get_tree().process_frame
		if index == 0:
			if not await _click("Choose later") or _panel.visible:
				return false
			var reopened := _progression.offer(Seat, offer.ordinal)
			if reopened == null or reopened.options != offer.options:
				return false
			_panel.show_offer(reopened, Names)
			await get_tree().process_frame
		if not await _capture(String(id) + ".png"):
			return false
		var already_selected := _selected.size()
		if (not await _click(title) or _last_result != RunRewardQueue.Selection.APPLIED
				or _selected.size() != already_selected + 1 or _selected.back() != id
				or _progression.offer(Seat, offer.ordinal) != null):
			return false
	return (_progression.active_power_form(Seat, &"P07") == &"F06"
		and _progression.active_power_form(Seat, &"P12") == &"F06")


func _choose(ordinal: int, id: StringName) -> void:
	_last_result = _progression.select(Seat, ordinal, id)
	if _last_result == RunRewardQueue.Selection.APPLIED:
		_selected.append(id)
		_panel.hide()


func _click(title: String) -> bool:
	for found: Node in _panel.find_children("*", "Button", true, false):
		var button := found as Button
		if button.text != title or not button.is_visible_in_tree():
			continue
		var point := button.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		get_viewport().push_input(motion, true)
		for pressed: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = point
			event.global_position = point
			event.pressed = pressed
			get_viewport().push_input(event, true)
		await get_tree().process_frame
		return true
	return false


func _capture(filename: String) -> bool:
	if _capture_root.is_empty() or DisplayServer.get_name() == "headless":
		return true
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image().save_png(_capture_root.path_join(filename)) == OK
