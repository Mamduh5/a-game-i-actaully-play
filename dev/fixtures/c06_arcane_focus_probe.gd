extends Node2D
## Scripted movement through a native encounter with a decoded beam view.

const SEAT := &"player"
const RUN := &"c06-arcane-focus"
const REALM := WorldTopology.OVERWORLD
const SEED := 3207
const SAMPLES := [1, 16, 31, 46]

var _encounter: StarterEncounter
var _replica := GuestReplica.new()
var _display := StarterEncounterView.new()
var _label := Label.new()
var _blocked: bool
var _capture_dir: String
var _capture_ok := true
var _launches: Array[int] = []
var _damage: Array[Array] = []
var _samples: Array[Array] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or args[0] not in ["clear", "blocked"]:
		_finish(false)
		return
	_blocked = args[0] == "blocked"
	if args.size() > 1 and DisplayServer.get_name() != "headless":
		_capture_dir = args[1]
	_display.outline_only = "reduced" in args
	if not _assemble():
		_finish(false)


func _assemble() -> bool:
	var layout := WorldTopology.generate(SEED)
	var floor := WorldExploration.create(layout, [SEAT])
	if floor == null:
		return false
	if _blocked:
		var wall := RealmOutline.Edge.new()
		wall.first = RealmSweep.Point.new(164.0, 102.0)
		wall.last = RealmSweep.Point.new(164.0, 186.0)
		if not floor.geometry().add_segment(&"stone_screen", 0, wall, WorldExploration.BLOCKER, false):
			return false
	var roster: CatalogBundle = load("res://src/catalog/starter_roster.tres")
	var catalog := roster.compile()
	var slots: Array[StringName] = []
	slots.resize(RunPreparation.CANDIDATE_SLOTS)
	slots.fill(&"")
	var build := StarterEncounter.Build.new()
	build.preparation = RunPreparation.select(catalog, &"H01", &"W09", [&"", &""], slots, {&"W09": true})
	build.powers = RunRewardQueue.begin(build.preparation, RunRandom.new(SEED), SEAT)
	build.start = RealmSweep.Point.new(62.0, 128.0)
	build.maximum_hp = Quantity.from_count(100)
	var setup := RunSetup.new()
	setup.role = RunSetup.Role.SOLO
	setup.run_id = RUN
	setup.authority_id = SEAT
	setup.epoch = 1
	setup.seed = SEED
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = catalog.revision
	setup.challenge_id = &"normal"
	setup.initial_realms = {SEAT: REALM}
	_encounter = StarterEncounter.assemble(setup, SEAT, floor, {SEAT: build})
	var rules := WorldEnemy.Rules.new()
	rules.faction = &"fixture"
	rules.family = &"fixture/target"
	rules.hp = Quantity.from_count(100)
	rules.damage = Quantity.from_count(1)
	rules.radius = 8.0
	rules.sight = 10.0
	rules.attack_range = 10.0
	rules.attack_radius = 8.0
	rules.windup_ticks = 1
	rules.recovery_ticks = 1
	if (_encounter == null or not _encounter.place_enemy(&"front", rules, RealmSweep.Point.new(118.0, 128.0))
			or not _encounter.place_enemy(&"rear", rules, RealmSweep.Point.new(198.0, 128.0))
			or not _encounter.place_enemy(&"side", rules, RealmSweep.Point.new(143.0, 165.0))):
		return false
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	if layout.contains_cell(Vector2i.RIGHT):
		cells.append(Vector2i.RIGHT)
	_display.scale = Vector2(2.0, 2.0)
	_display.position = Vector2(216, 110)
	add_child(_display)
	_display.prepare(cells, floor.geometry(), [], Vector2(-200, -200), Vector2(-200, -200))
	_label.position = Vector2(216, 38)
	_label.add_theme_font_size_override("font_size", 30)
	_label.text = "Arcane Focus / Stone screen" if _blocked else "Arcane Focus / Open lane"
	add_child(_label)
	return true


func _physics_process(_delta: float) -> void:
	var tick := _encounter.next_tick()
	if tick in [2, 17, 32]:
		var axis := 1 if tick == 2 else (-1 if tick == 17 else 0)
		var command := PlayerCommand.new(PlayerCommand.MOVE_AXES, 0, axis)
		var intent := RunIntent.new(RUN, 1, REALM, SEAT, tick, tick, command.action, command)
		if _encounter.submit(SEAT, intent) != RunAuthority.Admission.QUEUED:
			_finish(false)
			return
	if not _encounter.close_tick() or not _encounter.fault().is_empty():
		_finish(false)
		return
	for outcome: Dictionary in _encounter.closed_result()["outcomes"]:
		if outcome.get("weapon") == &"W09":
			_launches.append(tick)
		if outcome.get("family") == &"W09" and outcome["damage"]:
			_damage.append([tick, outcome["target"]])
	var state := _encounter.movement_state(SEAT, 1, tick)
	if tick == 1 and not _replica.install_scope(REALM, state):
		_finish(false)
		return
	var source := _encounter.view_for(SEAT)
	var body := RecipientView.pack_encounter(source, state, REALM, _encounter.party_statuses(), null)
	var kind := ReplicationMessage.Kind.VIEW_STATE
	var channel := ReplicationMessage.transport_kind(kind)
	var packet := NativeSessionFrame.pack(channel, 1, tick, ReplicationMessage.pack(kind, body))
	if _replica.receive_frame(NativeSessionFrame.read(packet, NativeSessionFrame.channel(channel))) != GuestReplica.Acceptance.APPLIED:
		_finish(false)
		return
	var view := _replica.encounter_view(SEAT, tick)
	if view == null:
		_finish(false)
		return
	_display.display(view)
	if tick in SAMPLES:
		if view.cues.size() != 1:
			_finish(false)
			return
		var beam := view.cues[0]
		var expected_y := 153.0 if tick == 16 else 128.0
		var visible := _replica.actor_ids()
		if (beam.id != &"W09" or beam.impact != tick or beam.ends != 61
				or not is_equal_approx(view.player.at.y, expected_y) or beam.position.y != view.player.at.y
				or beam.heading.x != 1.0 or beam.heading.y != 0.0 or beam.radius != 12.0
				or ("rear" in visible) == _blocked
				or (_blocked and not is_equal_approx(beam.reach, 102.0)) or (not _blocked and beam.reach <= 140.0)):
			_finish(false)
			return
		_samples.append([tick, snappedf(beam.position.y, 0.001), snappedf(beam.reach, 0.001), visible])
		if not _capture_dir.is_empty():
			RenderingServer.frame_post_draw.connect(_capture.bind(tick), CONNECT_ONE_SHOT)
	if tick == 61:
		var expected: Array[Array] = []
		for pulse: int in SAMPLES:
			expected.append([pulse, &"side" if pulse == 16 else &"front"])
			if not _blocked and pulse != 16:
				expected.append([pulse, &"rear"])
		_finish(_launches == [1] and _damage == expected and view.cues.is_empty() and _capture_ok)


func _capture(tick: int) -> void:
	_capture_ok = get_viewport().get_texture().get_image().save_png(
		_capture_dir.path_join("focus-%d.png" % tick)) == OK and _capture_ok


func _finish(passed: bool) -> void:
	set_physics_process(false)
	print("C06_FOCUS ", JSON.stringify({"passed": passed, "blocked": _blocked, "launches": _launches,
		"damage": _damage, "samples": _samples}))
	get_tree().quit(0 if passed else 1)
