extends Node2D
## Labeled normal-input witness for the WP19 preparation and reward controls.

const SEAT := &"solo"
const REALM := &"fixture_realm"
const PLAYER := &"fixture_player"
const NAMES: Dictionary[StringName, String] = {
	&"H01": "The Undying", &"H02": "The Acrobat", &"H03": "The Conductor",
	&"W01": "Sword", &"W02": "Bow", &"W03": "Magic Staff",
	&"R01": "Bleed", &"R02": "Lightning", &"R03": "Force",
	&"P01": "Spinning Blade", &"P02": "Sketch Familiar", &"P03": "Runic Mine", &"P04": "Spectral Lance",
	&"P05": "Battle Tempo", &"P06": "Sharpsight", &"P07": "Vital Exchange", &"P08": "Fracture",
	&"P09": "Death Bloom", &"P10": "Echo Strike", &"P11": "Collision Burst", &"P12": "Reprisal Pulse",
}

class FixtureAuthority extends RunAuthority:
	var controls := PlayerControlState.new()
	var geometry := RealmGeometry.new(REALM)
	var manual_casts: int

	func _supports_action(action: StringName) -> bool:
		return action in [PlayerCommand.MOVE_AXES, PlayerCommand.MOVE_TO, PlayerCommand.MANUAL]

	func _resolve_tick(_tick: int, accepted: Array[RunIntent], _streams: RunRandom) -> Array[Dictionary]:
		for intent: RunIntent in accepted:
			if intent.action == PlayerCommand.MANUAL:
				manual_casts += 1
			else:
				controls.apply(intent.command)
		controls.step(geometry, PLAYER, 0, 2, 180.0, GuestMovement.SECONDS_PER_TICK)
		return []

var _authority := FixtureAuthority.new()
var _router := PlayerInputRouter.new()
var _panel := RunProgressionPanel.new()
var _catalog := _compile_fixture_catalog()
var _profile := ProfileStore.new()
var _profile_root: DirAccess
var _setup := RunSetup.new()
var _party: PartyProgression
var _started := false
var _sequence: int
var _reopen_button := Button.new()
var _pawn := Polygon2D.new()
var _label := Label.new()


func _ready() -> void:
	get_window().title = "WP19 progression input fixture"
	RenderingServer.set_default_clear_color(Color("223039"))
	_pawn.polygon = PackedVector2Array([Vector2(-11, -11), Vector2(13, 0), Vector2(-11, 11)])
	_pawn.color = Color("80dac9")
	_pawn.position = Vector2(220, 250)
	add_child(_pawn)
	_label.position = Vector2(24, 24)
	_label.text = "WP19 progression input fixture"
	add_child(_label)
	_reopen_button.text = "Pending rewards"
	_reopen_button.position = Vector2(24, 52)
	_reopen_button.pressed.connect(_show_next_offer)
	_reopen_button.hide()
	add_child(_reopen_button)
	_router.world_from_viewport = func(at: Vector2) -> RealmSweep.Point: return RealmSweep.Point.new(at.x, at.y)
	add_child(_router)
	_panel.position = Vector2(530, 36)
	add_child(_panel)
	_panel.preparation_requested.connect(_start)
	_panel.choice_requested.connect(_choose)
	_panel.dismissed.connect(_panel.hide)
	_panel.show_preparation(_catalog, {}, NAMES)
	_capture("preparation.png")


func _start(preparation: RunPreparation) -> void:
	if _party != null:
		return
	_profile_root = DirAccess.create_temp("agip-wp19-input")
	_setup.run_id = &"input_fixture"
	_setup.authority_id = SEAT
	_setup.epoch = 1
	_setup.seed = 341
	_setup.rules_revision = &"V42.6/R1"
	_setup.catalog_revision = _catalog.revision
	_setup.challenge_id = &"normal"
	_setup.initial_realms = {SEAT: REALM}
	_party = PartyProgression.begin(_setup, {SEAT: preparation})
	if (_party == null or not _authority.start(_setup, SEAT)
			or not _authority.geometry.add_circle(PLAYER, 0, RealmSweep.Point.new(220, 250), 10.0, 1)
			or _profile.open("input_fixture", _profile_root.get_current_dir()) != ProfileStore.OpenResult.OPENED
			or not _save("prepare", 0, _party)):
		push_error("WP19 preparation fixture failed")
		return
	_authority.close_tick()
	if (_party.grant_xp(&"fixture_clear", Quantity.from_count(215), 1) != PartyProgression.Award.APPLIED
			or not _save("earn", 1, _party)):
		push_error("WP19 XP fixture failed")
		return
	_label.text = "Level 3 · 3 XP carried"
	_started = true
	_reopen_button.show()
	_show_next_offer()
	print("WP19_PREPARED ", JSON.stringify({"hero": preparation.hero, "weapon": preparation.weapon,
		"runes": preparation.runes(), "candidate_slots": preparation.candidates().size(), "offers": 2}))


func _physics_process(_delta: float) -> void:
	if not _started:
		_router.drain()
		return
	for command: PlayerCommand in _router.drain():
		_sequence += 1
		_authority.submit(SEAT, RunIntent.new(_setup.run_id, _setup.epoch, REALM, SEAT,
			_authority.next_tick(), _sequence, command.action, command))
	_authority.close_tick()
	var pose := _authority.geometry.circle_center(PLAYER, 0)
	_pawn.position = Vector2(pose.x, pose.y)


func _show_next_offer() -> void:
	for ordinal: int in [1, 2]:
		var offer := _party.offer(SEAT, ordinal)
		if offer != null:
			_panel.show_offer(offer, NAMES)
			_capture("reward-%d.png" % ordinal)
			return
	_panel.hide()
	_reopen_button.hide()


func _choose(ordinal: int, id: StringName) -> void:
	var draft := PartyProgression.reopen(_setup, _catalog, _profile.frontier(String(_setup.run_id)))
	if draft == null:
		push_error("WP19 selection cannot read the prepared frontier")
		return
	var result := draft.select(SEAT, ordinal, id)
	if result != RunRewardQueue.Selection.APPLIED:
		_panel.show_feedback("That choice has already changed.")
		return
	var tick := _authority.next_tick() - 1
	if not _save("choose:%d" % ordinal, tick, draft) or not _profile.close():
		push_error("WP19 selection save failed")
		return
	if _profile.open("input_fixture", _profile_root.get_current_dir()) != ProfileStore.OpenResult.OPENED:
		push_error("WP19 selection reopen failed")
		return
	var durable := PartyProgression.reopen(_setup, _catalog, _profile.frontier(String(_setup.run_id)))
	if durable == null or durable.offer(SEAT, ordinal) != null:
		push_error("WP19 saved selection was not recovered")
		return
	_party = durable
	_panel.hide()
	print("WP19_CHOICE ", JSON.stringify({"id": id, "ordinal": ordinal, "world_tick": tick,
		"x": _pawn.position.x, "manual_casts": _authority.manual_casts, "recovered": true}))
	_capture("selected-%d.png" % ordinal)


func _save(operation: String, tick: int, source: PartyProgression) -> bool:
	var mutation := ProfileMutation.new()
	mutation.id = operation
	mutation.rules = String(_setup.rules_revision)
	mutation.catalog = String(_setup.catalog_revision)
	mutation.frontier = source.frontier(tick)
	return mutation.frontier != null and _profile.commit(mutation).status == ProfileStore.CommitResult.COMMITTED


func _capture(filename: String) -> void:
	var evidence := OS.get_environment("AGIP_WP19_CAPTURE")
	if evidence.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	if get_viewport().get_texture().get_image().save_png(evidence.path_join(filename)) != OK:
		push_error("WP19 fixture evidence could not be saved")


static func _compile_fixture_catalog() -> DefinitionCatalog:
	var entries: Array[CatalogEntry] = []
	for id: StringName in NAMES:
		var entry := CatalogEntry.new()
		entry.id = id
		entry.source_family = id
		entry.eligibility = CatalogEntry.Eligibility.STARTER
		entry.targeting = CatalogEntry.Targeting.NONE
		entry.lifetime = CatalogEntry.Lifetime.PREPARATION
		match String(id).left(1):
			"H": entry.kind = CatalogEntry.Kind.HERO
			"W": entry.kind = CatalogEntry.Kind.WEAPON
			"R": entry.kind = CatalogEntry.Kind.RUNE
			"P":
				entry.kind = CatalogEntry.Kind.POWER
				entry.ranks = [&"rank1", &"rank2", &"rank3", &"rank4", &"rank5"]
		entries.append(entry)
	return DefinitionCatalog.compile(&"wp19_input_fixture", entries)
