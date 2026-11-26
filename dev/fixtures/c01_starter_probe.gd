extends Node2D
## Scripted viewport inputs feed the ordinary RunAuthority and C01 deliveries.

const Run := &"c01-probe"
const Player := &"player"
const Realm := &"arena"
const Foe := 1
const Wall := 2
const Ally := 4

class Rules extends RunAuthority:
	var geometry := RealmGeometry.new(Realm)
	var kernel := CombatKernel.new()
	var controls := PlayerControlState.new()
	var targeting := PlayerTargeting.new()
	var combat: StarterCombat
	var targets: Array[PlayerTargeting.Candidate] = []
	var scenario: String
	var trace: Array[Array] = []
	var manual: int
	var axes: int
	var launches: int
	var uncredited_barrier := -1
	var passed := true

	func initialize(which: String) -> bool:
		scenario = which
		var tuning: StarterCombatRules = load("res://src/catalog/starter_combat.tres")
		var roster: CatalogBundle = load("res://src/catalog/starter_roster.tres")
		var catalog := roster.compile()
		var weapon := &"W01" if which == "sword" else (&"W03" if which == "sigil" else &"W02")
		var slots: Array[StringName] = []
		slots.resize(RunPreparation.CANDIDATE_SLOTS)
		slots.fill(&"")
		var prep := RunPreparation.select(catalog, &"H01", weapon, [&"", &""], slots, {})
		var actor := _actor(Player, 100, CombatOrigin.Provenance.SEAT)
		actor.physical.rating = Quantity.from_count(10)
		actor.magical.rating = Quantity.from_count(10)
		if (not tuning.prepare_hero(actor, prep) or not kernel.add_actor(actor)
				or not geometry.add_circle(Player, 0, RealmSweep.Point.new(320, 380), 14.0, Ally)
				or not kernel.attach_geometry(geometry, Wall)):
			return false
		combat = StarterCombat.create(tuning, catalog, prep, kernel, geometry, Player, Foe, Foe, Wall)
		var setup := RunSetup.new()
		setup.run_id = Run
		setup.authority_id = Player
		setup.epoch = 1
		setup.seed = 601
		setup.rules_revision = &"V42.6/R1"
		setup.catalog_revision = catalog.revision
		setup.challenge_id = &"c01-fixture"
		setup.initial_realms = {Player: Realm}
		if combat == null or not start(setup, Player):
			return false
		match which:
			"sword":
				return _enemy(&"front", 375, 380, 20) and _enemy(&"flank", 364, 419, 80) and _enemy(&"rear", 245, 380, 80, false)
			"bow", "bow-miss":
				return _enemy(&"aim", 570, 380, 60) and _enemy(&"interceptor", 498, 450, 60, false)
			"sigil":
				return _enemy(&"aim", 560, 380, 60) and _enemy(&"arrival", 620, 470, 60, false)
			"undying":
				var ally := _actor(&"ally", 100, CombatOrigin.Provenance.SEAT)
				return (kernel.add_actor(ally)
					and geometry.add_circle(&"ally", 0, RealmSweep.Point.new(259, 380), 14.0, Ally)
					and _enemy(&"uncredited", 268, 422, 16) and _enemy(&"small", 377, 388, 16)
					and _enemy(&"durable", 378, 416, 100))
		return false

	func _enemy(id: StringName, x: float, y: float, health: int, known: bool = true) -> bool:
		var target := PlayerTargeting.Candidate.new()
		target.id = id
		target.kind = PlayerTargeting.Kind.HOSTILE
		target.known = known
		target.compatible = true
		target.position = RealmSweep.Point.new(x, y)
		targets.append(target)
		return kernel.add_actor(_actor(id, health, CombatOrigin.Provenance.SPAWN)) and geometry.add_circle(
			id, 0, target.position, 12.0, Foe)

	static func _actor(id: StringName, health: int, side: CombatOrigin.Provenance) -> CombatantState:
		var actor := CombatantState.new()
		actor.id = id
		actor.owner = id
		actor.realm = Realm
		actor.life = 1
		actor.provenance = side
		actor.max_hp = Quantity.from_count(health)
		actor.hp = QuantityLayerLedger.Pool.new(actor.max_hp, QuantityErrorBounds.new())
		return actor

	func _supports_action(action: StringName) -> bool:
		return action in [PlayerCommand.MOVE_AXES, PlayerCommand.MOVE_TO, PlayerCommand.AIM, PlayerCommand.MANUAL]

	func _resolve_tick(tick: int, accepted: Array[RunIntent], _streams: RunRandom) -> Array[Dictionary]:
		var now := CombatInstant.at_tick(tick)
		passed = passed and _settle(now, false)
		for intent: RunIntent in accepted:
			if intent.action == PlayerCommand.MANUAL:
				manual += int(combat.try_manual(tick) == StarterCombat.Attempt.COMMITTED)
			else:
				axes += int(intent.action == PlayerCommand.MOVE_AXES and intent.command.y < 0.0)
				controls.apply(intent.command)
		passed = passed and controls.step(geometry, Player, 0, Wall, 100.0, 1.0 / 60.0) != null
		if tick == 8 and scenario != "undying":
			launches += int(combat.try_weapon(tick, targeting, targets) == StarterCombat.Attempt.COMMITTED)
		if tick == 11 and scenario in ["bow", "bow-miss"]:
			passed = passed and geometry.commit_circle_pose(&"aim", 0, RealmSweep.Point.new(570, 500))
		if tick == 12 and scenario == "bow":
			passed = passed and geometry.commit_circle_pose(&"interceptor", 0, RealmSweep.Point.new(498, 380))
		if tick == 16 and scenario == "sigil":
			passed = passed and geometry.commit_circle_pose(&"aim", 0, RealmSweep.Point.new(560, 520))
			passed = passed and geometry.commit_circle_pose(&"arrival", 0, RealmSweep.Point.new(603, 401))
		if tick == 5 and scenario == "undying":
			passed = passed and _ally_elimination(tick)
		passed = passed and combat.advance(tick) and _settle(now, true)
		if kernel.advance_survival(now).result == CombatKernel.Result.INTERRUPTED:
			passed = false
		if tick == 5 and scenario == "undying":
			uncredited_barrier = layer_units(StarterCombatRules.HARVEST)
		return []

	func _settle(now: CombatInstant, include_equal: bool) -> bool:
		while kernel.pending_count() > 0:
			var next := kernel.next_due()
			if next == null:
				return false
			var order := next.order_against(now)
			if order == RealmCircleTime.Order.AFTER or (order == RealmCircleTime.Order.SAME and not include_equal):
				return true
			if order == RealmCircleTime.Order.UNRESOLVED:
				return false
			var closed := kernel.resolve_next(now)
			if closed.result == CombatKernel.Result.YIELDED:
				continue
			if closed.result != CombatKernel.Result.CLOSED:
				return false
			for hit: CombatKernel.Hit in closed.hits:
				trace.append([closed.due.tick, String(hit.family), String(hit.target), hit.eliminated])
		return true

	func _ally_elimination(tick: int) -> bool:
		var action := CombatAction.new()
		action.source = &"ally"
		action.source_life = 1
		action.family = &"ally-test"
		action.origin = CombatOrigin.new()
		action.origin.owner = &"ally"
		action.origin.activation = tick
		action.origin.committed_at = CombatInstant.at_tick(tick)
		var component := CombatAction.Component.new()
		component.base = Quantity.from_count(20)
		action.components.append(component)
		var delivery := CombatDelivery.activate(kernel, action, Realm)
		var at := geometry.circle_center(&"uncredited", 0)
		var contacts := geometry.certify_circle_snapshot(Realm, at, 0.0, Foe)
		return (delivery != null and contacts.contacts.size() == 1
			and delivery.admit(tick, contacts.contacts[0], 1, true) == CombatDelivery.Result.ADMITTED and delivery.finish())

	func layer_units(id: StringName) -> int:
		for layer: CombatantState.Barrier in kernel.actor_snapshot(Player).barriers:
			if layer.id == id:
				return int(layer.pool.amount.native_at_scale(0))
		return 0

	func verdict() -> bool:
		var player := geometry.circle_center(Player, 0)
		if not passed:
			return false
		match scenario:
			"sword":
				return (trace == [[8, "W01", "flank", false], [8, "W01", "front", true]] and launches == 1
					and axes > 0 and is_equal_approx(player.y, 330.0) and layer_units(StarterCombatRules.HARVEST) == 2)
			"bow": return launches == 1 and trace.size() == 1 and trace[0].slice(1) == ["W02", "interceptor", false]
			"bow-miss": return launches == 1 and trace.is_empty() and combat.cues().is_empty()
			"sigil": return launches == 1 and trace == [[32, "W03", "arrival", false]]
			"undying":
				return (manual == 1 and uncredited_barrier == 0 and trace.size() == 3
					and layer_units(StarterCombatRules.HARVEST) == 2 and layer_units(StarterCombatRules.SIPHON) == 27)
		return false

var _rules := Rules.new()
var _router := PlayerInputRouter.new()
var _view := StarterCombatCues.new()
var _hud := Label.new()
var _sequence: int
var _capture_dir: String
var _capture_success := true
var _case: String
var _reduced: bool


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not _rules.initialize(args[0]):
		get_tree().quit(1)
		return
	_case = args[0]
	_capture_dir = args[1] if args.size() > 1 and DisplayServer.get_name() != "headless" else ""
	_reduced = args.size() > 2 and args[2] == "reduced"
	Input.use_accumulated_input = false
	_router.world_from_viewport = func(point: Vector2) -> RealmSweep.Point: return RealmSweep.Point.new(point.x, point.y)
	add_child(_router)
	add_child(_view)
	_view.z_index = 1
	add_child(_hud)
	_hud.position = Vector2(55, 48)
	_hud.add_theme_font_size_override("font_size", 24)
	_hud.add_theme_color_override("font_color", Color("#e2dcce"))
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _physics_process(_delta: float) -> void:
	var tick := _rules.next_tick()
	_drive_visible_inputs(tick)
	for command: PlayerCommand in _router.drain():
		_sequence += 1
		var intent := RunIntent.new(Run, 1, Realm, Player, tick, _sequence, command.action, command)
		if _rules.submit(Player, intent) != RunAuthority.Admission.QUEUED:
			_rules.passed = false
	_rules.passed = _rules.passed and _rules.close_tick()
	_view.present(_rules.combat.cues(), tick, _reduced)
	_hud.text = "%s\nLife Harvest %d   •   Siphon Pulse %d" % [
		{"sword": "Sword", "bow": "Bow", "bow-miss": "Bow", "sigil": "Magic Staff", "undying": "The Undying"}[_case],
		_rules.layer_units(StarterCombatRules.HARVEST), _rules.layer_units(StarterCombatRules.SIPHON),
	]
	queue_redraw()
	if not _capture_dir.is_empty() and tick in {"sword": [10], "bow": [16], "bow-miss": [21],
			"sigil": [20, 34], "undying": [18]}[_case]:
		RenderingServer.frame_post_draw.connect(_capture.bind(tick), CONNECT_ONE_SHOT)
	if tick >= 59 or not _rules.passed:
		var good := _rules.verdict() and _capture_success
		var pose := _rules.geometry.circle_center(Player, 0)
		var facts := [_case, _rules.trace, snappedf(pose.y, 0.001), _rules.launches, _rules.manual,
			_rules.layer_units(StarterCombatRules.HARVEST), _rules.layer_units(StarterCombatRules.SIPHON)]
		var serial := JSON.stringify(facts)
		print("C01 passed=%s hash=%s facts=%s" % [good, serial.sha256_text(), serial])
		get_tree().quit(0 if good else 1)


func _drive_visible_inputs(tick: int) -> void:
	if _case == "sword" and tick in [1, 31]:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_W
		event.pressed = tick == 1
		Input.parse_input_event(event)
	if _case == "undying" and tick == 16:
		for pressed: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = Vector2(320, 380)
			event.pressed = pressed
			Input.parse_input_event(event)


func _capture(tick: int) -> void:
	_capture_success = get_viewport().get_texture().get_image().save_png(
		_capture_dir.path_join("%s-%d.png" % [_case, tick])) == OK and _capture_success


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("#212631"))
	draw_rect(Rect2(55, 152, 1170, 505), Color("#2b3441"))
	var player := _rules.geometry.circle_center(Player, 0)
	if player == null:
		return
	for target: PlayerTargeting.Candidate in _rules.targets:
		var pose := _rules.geometry.circle_center(target.id, 0)
		var location := Vector2(pose.x, pose.y)
		var living := _rules.kernel.actor_snapshot(target.id).is_alive()
		draw_circle(location, 12, Color("#df9290") if living else Color("#4b4c57"), true, -1.0, true)
		draw_arc(location, 12, 0, TAU, 24, Color("#774d59") if living else Color("#69727e"), 1.5, true)
		draw_string(ThemeDB.fallback_font, location + Vector2(-22, 34), String(target.id),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#ded7ca"))
	draw_circle(Vector2(player.x, player.y), 14, Color("#9fe0c5"), true, -1.0, true)
	draw_arc(Vector2(player.x, player.y), 15, 0, TAU, 24, Color("#223837"), 2.0, true)
