extends Node2D
## Scripted viewport inputs feed the ordinary RunAuthority and C01 deliveries.

const Run := &"c01-probe"
const Player := &"player"
const Realm := &"arena"
const Foe := 1
const Wall := 2
const Ally := 4
const POWER_CASES := ["familiar", "mines", "lance", "tether"]
const SPEAR_CASES := ["spear-clear", "spear-blocked"]
const SPEAR_WALL_TOP := Vector2(408, 327)
const SPEAR_WALL_BOTTOM := Vector2(408, 433)
const DAGGER_WALL_TOP := Vector2(346, 382)
const DAGGER_WALL_BOTTOM := Vector2(346, 432)

class Rules extends RunAuthority:
	var geometry := RealmGeometry.new(Realm)
	var kernel := CombatKernel.new()
	var controls := PlayerControlState.new()
	var targeting := PlayerTargeting.new()
	var combat: StarterCombat
	var familiar: SketchFamiliar
	var mines: RunicMines
	var lance: SpectralLance
	var tether: ArcaneTether
	var targets: Array[PlayerTargeting.Candidate] = []
	var scenario: String
	var trace: Array[Array] = []
	var dagger_strokes: Array[Array] = []
	var manual: int
	var axes: int
	var launches: int
	var uncredited_barrier := -1
	var passed := true
	var prepared: bool

	func initialize(which: String, prepared_offense: bool) -> bool:
		if prepared_offense and which not in POWER_CASES:
			return false
		scenario = which
		prepared = prepared_offense
		var tuning: StarterCombatRules = load("res://src/catalog/starter_combat.tres")
		var roster: CatalogBundle = load("res://src/catalog/starter_roster.tres")
		var catalog := roster.compile()
		var weapon := &"W01" if which in ["sword", "bleed", "wake", "rupture", "conductor-charged"] else (&"W03" if which == "sigil" else &"W02")
		var slots: Array[StringName] = []
		slots.resize(RunPreparation.CANDIDATE_SLOTS)
		slots.fill(&"")
		var hero := StarterCombatRules.CONDUCTOR if which.begins_with("conductor") else StarterCombatRules.UNDYING
		var unlocked: Dictionary[StringName, bool] = {}
		if which in SPEAR_CASES:
			weapon = &"W04"
			unlocked[weapon] = true
		if which == "daggers":
			weapon = &"W06"
			unlocked[weapon] = true
		if which == "tether":
			unlocked[&"P14"] = true
			slots[0] = &"P14"
		if which == "fracture":
			hero = StarterCombatRules.CHRONOMANCER
			weapon = &"W03"
			unlocked[hero] = true
		var runes: Array[StringName] = [&"", &""]
		if which == "storm-relay":
			runes.assign([&"R02", &"R03"])
		elif which == "bleed":
			runes[0] = &"R01"
		elif which == "wake":
			runes.assign([&"R01", &"R03"])
		elif which == "rupture":
			runes.assign([&"R01", &"R02"])
		var upgrades: Dictionary[StringName, int] = {}
		if prepared:
			upgrades = {&"base_damage": 2500, &"automatic_attack_frequency": 2500}
		var prep := RunPreparation.select(catalog, hero, weapon, runes, slots, unlocked, upgrades)
		var actor := _actor(Player, 100, CombatOrigin.Provenance.SEAT)
		actor.physical.rating = Quantity.from_count(10)
		actor.magical.rating = Quantity.from_count(10)
		if (not tuning.prepare_hero(actor, prep) or not kernel.add_actor(actor)
				or not geometry.add_circle(Player, 0, RealmSweep.Point.new(320, 380), 14.0, Ally)
				or not kernel.attach_geometry(geometry, Wall)):
			return false
		combat = StarterCombat.create(tuning, catalog, prep, kernel, geometry, Player, Foe, Foe, Wall)
		if which in POWER_CASES:
			var rewards := RunRewardQueue.begin(prep, RunRandom.new(17), Player)
			var family: StringName = {"familiar": &"P02", "mines": &"P03", "lance": &"P04", "tether": &"P14"}[which]
			for event: int in range(1, 100):
				if rewards.ranks().get(family, 0) == 5:
					break
				var ordinal := rewards.earn(event)
				var options := rewards.read_offer(ordinal).options
				rewards.select(ordinal, family if options.has(family) else options.keys()[0])
			if rewards.ranks().get(family, 0) != 5:
				return false
			if which == "familiar":
				familiar = SketchFamiliar.create(kernel, geometry, Player, rewards, Foe, Wall)
			elif which == "mines":
				mines = RunicMines.create(Player, rewards, kernel, geometry, Foe, Wall, combat)
			elif which == "lance":
				lance = SpectralLance.create(Player, rewards, kernel, geometry, Foe, Wall)
			else:
				tether = ArcaneTether.create(Player, rewards, kernel, geometry, Foe, Wall)
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
			"spear-clear", "spear-blocked":
				if not (_enemy(&"front", 378, 380, 100) and _enemy(&"rear", 443, 380, 100)
						and _enemy(&"flank", 415, 409, 100, false)):
					return false
				if which == "spear-clear":
					return true
				return _shield(SPEAR_WALL_TOP, SPEAR_WALL_BOTTOM)
			"daggers":
				return (_enemy(&"front", 352, 365, 100, false) and _enemy(&"rear", 363, 375, 100, false)
					and _enemy(&"aim", 367, 380, 100) and _shield(DAGGER_WALL_TOP, DAGGER_WALL_BOTTOM))
			"tether":
				return (tether != null and _enemy(&"first", 400, 380, 200) and _enemy(&"last", 520, 380, 200)
					and _enemy(&"visitor", 460, 390, 200, false))
			"lance":
				return (lance != null and _enemy(&"aim", 374, 380, 200)
					and _enemy(&"edge", 404, 396, 200, false) and _enemy(&"rear", 444, 380, 200))
			"mines":
				return mines != null and _enemy(&"left", 304, 380, 200) and _enemy(&"arrival", 420, 380, 200, false)
			"fracture":
				return _enemy(&"aim", 440, 380, 100) and _enemy(&"arrival", 550, 380, 100, false)
			"familiar":
				return familiar != null and _enemy(&"near", 366, 380, 200) and _enemy(&"rear", 395, 380, 200)
			"rupture":
				return _enemy(&"near", 357, 380, 100) and _enemy(&"flank", 365, 401, 100)
			"wake":
				return _enemy(&"near", 357, 380, 200) and _enemy(&"visitor", 510, 380, 100, false)
			"bleed":
				return _enemy(&"near", 357, 380, 100)
			"storm-relay":
				return _enemy(&"primary", 390, 380, 100) and _enemy(&"first", 370, 415, 100, false) and _enemy(&"relay", 435, 405, 100, false)
			"conductor-charged":
				return _enemy(&"near", 357, 380, 500) and _enemy(&"far", 320, 451, 500)
			"conductor":
				return _enemy(&"near", 380, 367, 100) and _enemy(&"far", 343, 452, 100)
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

	func _shield(first: Vector2, last: Vector2) -> bool:
		var edge := RealmOutline.Edge.new()
		edge.first = RealmSweep.Point.new(first.x, first.y)
		edge.last = RealmSweep.Point.new(last.x, last.y)
		return geometry.add_segment(&"fixture/shield", 0, edge, Wall, false)

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
				manual += int(combat.try_manual(tick, RealmSweep.Point.new(intent.command.x, intent.command.y)) == StarterCombat.Attempt.COMMITTED)
			else:
				axes += int(intent.action == PlayerCommand.MOVE_AXES and intent.command.y < 0.0)
				controls.apply(intent.command)
		passed = passed and controls.step(geometry, Player, 0, Wall, 100.0, 1.0 / 60.0) != null
		if scenario == "daggers" and tick >= 8:
			var attempt := combat.try_weapon(tick, targeting, targets)
			passed = passed and attempt != StarterCombat.Attempt.FAULT
			if attempt == StarterCombat.Attempt.COMMITTED:
				launches += 1
				var cue := combat.cues()[0]
				var at := geometry.circle_center(Player, 0)
				dagger_strokes.append([tick, cue.position.y - at.y, snappedf(cue.reach, 0.001)])
		elif (tick == 8 and scenario not in ["undying", "familiar", "mines", "lance", "tether"]) or (tick == 68 and scenario == "wake"):
			launches += int(combat.try_weapon(tick, targeting, targets) == StarterCombat.Attempt.COMMITTED)
		if tick == 11 and scenario in ["bow", "bow-miss"]:
			passed = passed and geometry.commit_circle_pose(&"aim", 0, RealmSweep.Point.new(570, 500))
		if tick == 12 and scenario == "bow":
			passed = passed and geometry.commit_circle_pose(&"interceptor", 0, RealmSweep.Point.new(498, 380))
		if tick == 16 and scenario == "sigil":
			passed = passed and geometry.commit_circle_pose(&"aim", 0, RealmSweep.Point.new(560, 520))
			passed = passed and geometry.commit_circle_pose(&"arrival", 0, RealmSweep.Point.new(603, 401))
		if tick == 20 and scenario == "fracture":
			passed = passed and geometry.commit_circle_pose(&"aim", 0, RealmSweep.Point.new(440, 470))
			passed = passed and geometry.commit_circle_pose(&"arrival", 0, RealmSweep.Point.new(450, 385))
		if tick == 5 and scenario == "undying":
			passed = passed and _ally_elimination(tick)
		if scenario == "wake" and tick in [83, 98]:
			passed = passed and geometry.commit_circle_pose(&"visitor", 0,
				RealmSweep.Point.new(387, 389 if tick == 83 else 410))
		if familiar != null:
			passed = passed and familiar.advance(tick, targets)
		if lance != null:
			if tick == 2:
				passed = passed and geometry.commit_circle_pose(&"aim", 0, RealmSweep.Point.new(374, 340))
			passed = passed and lance.advance(tick, targets)
		if tether != null:
			if tick == 28:
				var wall := RealmOutline.Edge.new()
				wall.first = RealmSweep.Point.new(458, 350)
				wall.last = RealmSweep.Point.new(458, 410)
				passed = passed and geometry.add_segment(&"door", 0, wall, Wall, false)
			if tick == 43:
				passed = passed and geometry.remove_mutable(&"door", 0)
				passed = passed and geometry.commit_circle_pose(&"last", 0, RealmSweep.Point.new(520, 452))
			passed = passed and tether.advance(tick, targets)
		if mines != null:
			if tick == 35:
				passed = passed and geometry.stage_circle_motion(&"arrival", 0, RealmSweep.Point.new(340, 380))
			elif tick == 36:
				passed = passed and geometry.commit_circle_motion(&"arrival", 0)
			passed = passed and mines.advance(tick)
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
			combat.observe_closed_group(closed)
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
			"spear-clear", "spear-blocked":
				var expected := [[8, "W04", "front", false]]
				if scenario == "spear-clear":
					expected.append([8, "W04", "rear", false])
				return (launches == 1 and trace == expected and player.x == 355.0
					and kernel.actor_snapshot(&"front").hp.amount.native_at_scale(0) == 80
					and kernel.actor_snapshot(&"rear").hp.amount.native_at_scale(0) == (80 if scenario == "spear-clear" else 100)
					and kernel.actor_snapshot(&"flank").hp.amount.native_at_scale(0) == 100)
			"daggers":
				return (launches == 3 and dagger_strokes[0] == [8, -5.0, 50.0]
					and dagger_strokes[1].slice(0, 2) == [32, 5.0] and is_equal_approx(dagger_strokes[1][2], 20.333)
					and dagger_strokes[2] == [56, -5.0, 50.0] and is_equal_approx(player.x, 332.0)
					and trace == [[8, "W06", "front", false], [56, "W06", "front", false]]
					and kernel.actor_snapshot(&"front").hp.amount.native_at_scale(0) == 82
					and kernel.actor_snapshot(&"rear").hp.amount.native_at_scale(0) == 100)
			"tether":
				return (trace == [[16, "P14", "first", false], [16, "P14", "last", false],
					[16, "P14", "visitor", false], [46, "P14", "first", false], [46, "P14", "last", false]]
					and kernel.actor_snapshot(&"first").hp.amount.native_at_scale(0) == (160 if prepared else 168))
			"lance":
				return (trace.size() == 2 and trace[0].slice(1) == ["P04", "edge", false]
					and trace[1].slice(1) == ["P04", "rear", false] and trace[0][0] < trace[1][0]
					and kernel.actor_snapshot(&"aim").hp.amount.native_at_scale(0) == 200
					and kernel.actor_snapshot(&"edge").hp.amount.native_at_scale(0) == (175 if prepared else 180)
					and kernel.actor_snapshot(&"rear").hp.amount.native_at_scale(2) == (16875 if prepared else 17500)
					and (lance.position() != null) == prepared)
			"mines":
				return (trace == [[13, "P03", "left", false], [35, "P03", "arrival", false], [35, "P03", "left", false]]
					and kernel.actor_snapshot(&"left").hp.amount.native_at_scale(0) == (118 if prepared else 130)
					and kernel.actor_snapshot(&"arrival").hp.amount.native_at_scale(0) == (148 if prepared else 154)
					and mines.positions().is_empty())
			"fracture":
				return (launches == 1 and manual == 1 and trace == [[22, "W03", "arrival", false],
					[37, "H04.temporal_echo", "arrival", false]]
					and kernel.actor_snapshot(&"arrival").hp.amount.native_at_scale(0) == 70
					and kernel.actor_snapshot(&"aim").hp.amount.native_at_scale(0) == 100)
			"familiar":
				var dart_contacts: Array[int] = []
				for row: Array in trace:
					if row[1] == "P02":
						dart_contacts.append(row[0])
				return (manual == 1 and dart_contacts == ([4, 4, 6, 6, 54, 54, 57] if prepared else [4, 4, 6, 6])
					and familiar.position().y < 350
					and layer_units(StarterCombatRules.SIPHON) > 0)
			"rupture":
				return (launches == 1 and kernel.pending_count() == 0 and trace.size() == 6
					and trace[4] == [8, "RP01.thunder_rupture", "flank", false]
					and trace[5] == [8, "RP01.thunder_rupture", "near", false]
					and kernel.actor_snapshot(&"near").hp.amount.native_at_scale(0) == 64
					and kernel.actor_snapshot(&"flank").hp.amount.native_at_scale(0) == 64)
			"wake":
				var contacts: Array = []
				for row: Array in trace:
					if row[1] == "RP02.blood_wake":
						contacts.append([row[0], row[2]])
				return (launches == 2 and contacts == [[83, "near"], [83, "visitor"], [98, "near"], [113, "near"]]
					and kernel.actor_snapshot(&"visitor").hp.amount.native_at_scale(0) == 96
					and kernel.actor_snapshot(&"near").hp.amount.native_at_scale(0) == 145)
			"bleed":
				return (launches == 1 and kernel.pending_count() == 0
					and kernel.actor_snapshot(&"near").hp.amount.native_at_scale(0) == 71
					and trace == [[8, "W01", "near", false], [68, "R01.bleed", "near", false],
						[128, "R01.bleed", "near", false], [188, "R01.bleed", "near", false]])
			"storm-relay":
				return (launches == 1 and geometry.circle_center(&"primary", 0).x == 410.0
					and trace.size() == 3 and trace[0].slice(1) == ["W02", "primary", false]
					and trace[1].slice(1) == ["R02.lightning", "first", false]
					and trace[2].slice(1) == ["RP03.storm_relay", "relay", false]
					and trace[0][0] == trace[1][0] and trace[1][0] == trace[2][0])
			"conductor-charged":
				return (manual == 2 and launches == 1 and combat.resonance == 0 and trace == [
					[2, "H03.harmonic_burst", "near", false], [8, "W01", "near", false],
					[242, "H03.harmonic_burst", "far", false], [242, "H03.harmonic_burst", "near", false]])
			"conductor":
				return (manual == 1 and launches == 1 and trace.size() == 2
					and trace[0].slice(1) == ["W02", "near", false]
					and trace[1] == [16, "H03.harmonic_burst", "near", false])
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
	if args.is_empty() or not _rules.initialize(args[0], args.size() > 2 and args[2] == "prepared"):
		set_physics_process(false)
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
	if _case.begins_with("conductor"):
		_hud.text = "The Conductor\nResonance %d" % _rules.combat.resonance
	elif _case == "storm-relay":
		_hud.text = "Lightning + Force\nStorm Relay"
	elif _case == "bleed":
		_hud.text = "Bleed\nTarget HP %d" % _rules.kernel.actor_snapshot(&"near").hp.amount.native_at_scale(0)
	elif _case == "wake":
		_hud.text = "Blood Wake\nTarget HP %d   Visitor HP %d" % [
			_rules.kernel.actor_snapshot(&"near").hp.amount.native_at_scale(0),
			_rules.kernel.actor_snapshot(&"visitor").hp.amount.native_at_scale(0)]
	elif _case == "familiar":
		_hud.text = "Sketch Familiar\nTwin Quill + Piercing Quill"
	elif _case == "mines":
		_hud.text = "Runic Mine\nLeft HP %d   Arrival HP %d" % [
			_rules.kernel.actor_snapshot(&"left").hp.amount.native_at_scale(0),
			_rules.kernel.actor_snapshot(&"arrival").hp.amount.native_at_scale(0)]
	elif _case == "lance":
		var rear := _rules.kernel.actor_snapshot(&"rear").hp.amount
		var rear_label := "%.2f" % (float(rear.native_at_scale(2)) / 100.0) if _rules.prepared else str(rear.native_at_scale(0))
		_hud.text = "Spectral Lance\nEdge HP %d   Rear HP %s" % [
			_rules.kernel.actor_snapshot(&"edge").hp.amount.native_at_scale(0),
			rear_label]
	elif _case in SPEAR_CASES:
		_hud.text = "Spear\nFront HP %d   Rear HP %d" % [
			_rules.kernel.actor_snapshot(&"front").hp.amount.native_at_scale(0),
			_rules.kernel.actor_snapshot(&"rear").hp.amount.native_at_scale(0)]
	elif _case == "daggers":
		var hand := "Ready"
		if not _rules.dagger_strokes.is_empty():
			hand = "Left" if _rules.dagger_strokes[-1][1] < 0.0 else "Right"
		_hud.text = "Twin Daggers / %s\nFront HP %d   Rear HP %d" % [hand,
			_rules.kernel.actor_snapshot(&"front").hp.amount.native_at_scale(0),
			_rules.kernel.actor_snapshot(&"rear").hp.amount.native_at_scale(0)]
	elif _case == "tether":
		_hud.text = "Arcane Tether\nEndpoint HP %d   Visitor HP %d" % [
			_rules.kernel.actor_snapshot(&"first").hp.amount.native_at_scale(0),
			_rules.kernel.actor_snapshot(&"visitor").hp.amount.native_at_scale(0)]
	elif _case == "fracture":
		_hud.text = "The Chronomancer\nTime Fracture"
	elif _case == "rupture":
		_hud.text = "Thunder Rupture\nTarget HP %d   Flank HP %d" % [
			_rules.kernel.actor_snapshot(&"near").hp.amount.native_at_scale(0),
			_rules.kernel.actor_snapshot(&"flank").hp.amount.native_at_scale(0)]
	else:
		_hud.text = "%s\nLife Harvest %d   •   Siphon Pulse %d" % [
			{"sword": "Sword", "bow": "Bow", "bow-miss": "Bow", "sigil": "Magic Staff", "undying": "The Undying"}[_case],
			_rules.layer_units(StarterCombatRules.HARVEST), _rules.layer_units(StarterCombatRules.SIPHON),
		]
	queue_redraw()
	var capture_ticks: Array = {"sword": [10], "bow": [16], "bow-miss": [21],
			"sigil": [20, 34], "undying": [18], "conductor": [18], "conductor-charged": [12, 244], "storm-relay": [17],
			"bleed": [190], "wake": [80, 85, 100], "rupture": [10], "familiar": [2, 24], "fracture": [15, 23],
			"mines": [6, 18, 38], "lance": [3, 10], "tether": [18, 33, 48],
			"spear-clear": [9], "spear-blocked": [9], "daggers": [9, 33, 57]}[_case]
	var extra_capture := _rules.prepared and ((_case == "familiar" and tick == 50) or (_case == "lance" and tick == 59))
	if not _capture_dir.is_empty() and (tick in capture_ticks or extra_capture):
		RenderingServer.frame_post_draw.connect(_capture.bind(tick), CONNECT_ONE_SHOT)
	var finish_tick := 60 if _rules.prepared else int({"conductor-charged": 252, "bleed": 192, "wake": 118}.get(_case, 59))
	if tick >= finish_tick or not _rules.passed:
		var good := _rules.verdict() and _capture_success
		var pose := _rules.geometry.circle_center(Player, 0)
		var facts := [_case, _rules.trace, snappedf(pose.y, 0.001), _rules.launches, _rules.manual,
			_rules.layer_units(StarterCombatRules.HARVEST), _rules.layer_units(StarterCombatRules.SIPHON)]
		if _case in SPEAR_CASES:
			facts.append(snappedf(pose.x, 0.001))
		if _case == "daggers":
			facts.append(snappedf(pose.x, 0.001))
			facts.append(_rules.dagger_strokes)
		var serial := JSON.stringify(facts)
		print("C01 passed=%s hash=%s facts=%s" % [good, serial.sha256_text(), serial])
		if _rules.prepared:
			var hp_hundredths: Dictionary[StringName, int] = {}
			for target: PlayerTargeting.Candidate in _rules.targets:
				hp_hundredths[target.id] = _rules.kernel.actor_snapshot(target.id).hp.amount.native_at_scale(2)
			print("WP21_POWER ", JSON.stringify({"case": _case, "passed": good, "hits": _rules.trace,
				"hp_hundredths": hp_hundredths}))
		get_tree().quit(0 if good else 1)


func _drive_visible_inputs(tick: int) -> void:
	if _case == "fracture" and tick == 12:
		for pressed: bool in [true, false]:
			var field := InputEventMouseButton.new()
			field.button_index = MOUSE_BUTTON_LEFT
			field.position = Vector2(440, 380)
			field.pressed = pressed
			get_viewport().push_input(field, true)
	if _case in ["familiar", "mines"] and tick == 10:
		for pressed: bool in [true, false]:
			var move := InputEventMouseButton.new()
			move.button_index = MOUSE_BUTTON_RIGHT
			move.position = Vector2(320, 330)
			move.pressed = pressed
			get_viewport().push_input(move, true)
	if (_case in SPEAR_CASES and tick == 1) or (_case == "daggers" and tick in [8, 32, 56]):
		var target_x := 324.0 + float(tick - 8) / 6.0 if _case == "daggers" else 355.0
		for pressed: bool in [true, false]:
			var move := InputEventMouseButton.new()
			move.button_index = MOUSE_BUTTON_RIGHT
			move.position = Vector2(target_x, 380)
			move.pressed = pressed
			get_viewport().push_input(move, true)
	if _case == "sword" and tick in [1, 31]:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_W
		event.pressed = tick == 1
		Input.parse_input_event(event)
	if (_case in ["undying", "conductor", "familiar"] and tick == 16) or (_case == "conductor-charged" and tick in [2, 242]):
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
	if _case == "spear-blocked":
		draw_line(SPEAR_WALL_TOP, SPEAR_WALL_BOTTOM, Color("#bdafa3"), 6, true)
	elif _case == "daggers":
		draw_line(DAGGER_WALL_TOP, DAGGER_WALL_BOTTOM, Color("#bdafa3"), 3, true)
	if _rules.tether != null:
		var segment := _rules.tether.visible_segment()
		if segment.size() == 2:
			draw_line(Vector2(segment[0].x, segment[0].y), Vector2(segment[1].x, segment[1].y), Color("#b6d4ff"), 4, true)
		if _rules.next_tick() > 28 and _rules.next_tick() <= 43:
			draw_line(Vector2(458, 350), Vector2(458, 410), Color("#bdafa3"), 6, true)
	for target: PlayerTargeting.Candidate in _rules.targets:
		var pose := _rules.geometry.circle_center(target.id, 0)
		var location := Vector2(pose.x, pose.y)
		var living := _rules.kernel.actor_snapshot(target.id).is_alive()
		draw_circle(location, 12, Color("#df9290") if living else Color("#4b4c57"), true, -1.0, true)
		draw_arc(location, 12, 0, TAU, 24, Color("#774d59") if living else Color("#69727e"), 1.5, true)
		var above := (_case in ["wake", "rupture"] and target.id == &"near") or (_case == "mines" and target.id == &"left")
		var label_offset := Vector2(-22, -23) if above else Vector2(-22, 34)
		draw_string(ThemeDB.fallback_font, location + label_offset, String(target.id),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#ded7ca"))
	draw_circle(Vector2(player.x, player.y), 14, Color("#9fe0c5"), true, -1.0, true)
	if _rules.mines != null:
		for mine: RealmSweep.Point in _rules.mines.positions():
			draw_arc(Vector2(mine.x, mine.y), RunicMines.TRIGGER_RADIUS, 0, TAU, 24, Color("#e5c28b"), 2, true)
			draw_circle(Vector2(mine.x, mine.y), 4, Color("#e5c28b"), true, -1, true)
	if _rules.lance != null and _rules.lance.position() != null:
		var tip := _rules.lance.position()
		var axis := _rules.lance.heading()
		draw_line(Vector2(tip.x - axis.x * 18, tip.y - axis.y * 18), Vector2(tip.x, tip.y), Color("#d5c6fc"), 5, true)
	if _rules.familiar != null and _rules.familiar.position() != null:
		var pet := _rules.familiar.position()
		draw_circle(Vector2(pet.x, pet.y), 6.0, Color("#e1d6bf"), true, -1.0, true)
		for dart: RealmSweep.Point in _rules.familiar.dart_positions():
			draw_circle(Vector2(dart.x, dart.y), 2.0, Color("#efe2b2"), true, -1.0, true)
	draw_arc(Vector2(player.x, player.y), 15, 0, TAU, 24, Color("#223837"), 2.0, true)
