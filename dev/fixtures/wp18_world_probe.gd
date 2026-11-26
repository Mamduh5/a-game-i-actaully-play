extends Node2D
## Recorded fixture inputs act on the same host simulation in each view arm.

const Seed := 18061
const Rider := &"scout"
const Hunter := &"hunter"
const Wild := &"wildborn"
const Hollow := &"hollow"
const Fallen := &"legion"
const Overworld := WorldTopology.OVERWORLD
const Interior := &"silent_garden"
const Unvisited := &"inverted_archive"
const Ages := 18
const DenseAges := 120

var _kernel := CombatKernel.new()
var _world := WorldActivity.new(_kernel, Seed)
var _controls := PlayerControlState.new()
var _rooms: Dictionary[StringName, WorldExploration] = {}
var _centers: Dictionary[StringName, RealmSweep.Point] = {}
var _overworld := WorldTopology.generate(Seed)
var _before_seam: StringName
var _after_seam: StringName
var _seam := Vector2.ZERO
var _along := Vector2.ZERO
var _mode := "headless"
var _capture: String
var _tick: int
var _step_samples: Array[int] = []
var _facts: Array[Dictionary] = []
var _state: Dictionary
var _kills: Array[Array] = []
var _detected := false
var _crossed := false
var _lost := false
var _reanimated := false
var _maximum_changed := false
var _skip_rejected := false
var _opened_without_view := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_mode = args[0]
	if args.size() >= 2:
		_capture = args[1]
	get_window().title = "WP18 offscreen simulation fixture"
	RenderingServer.set_default_clear_color(Color("222f35"))
	if (_mode not in ["full", "switch", "headless", "dense"] or not _setup()
			or (_mode == "dense" and not _dense_territories())):
		_finish(false)


func _setup() -> bool:
	_before_seam = WorldTopology.ANCHORS[0]
	var destination := WorldTopology.ANCHORS[1]
	var route := _overworld.route(_before_seam, destination)
	if route.size() < 2:
		return false
	_after_seam = route[1]
	var initial := _overworld.center(_before_seam)
	var neighbor := _overworld.center(_after_seam)
	_seam = (_vector(initial) + _vector(neighbor)) * 0.5
	_along = (_vector(neighbor) - _vector(initial)).normalized()
	for layout: WorldTopology in [_overworld, WorldTopology.generate_optional(Seed, Interior),
			WorldTopology.generate_optional(Seed, Unvisited)]:
		var room := WorldExploration.create(layout, [Rider])
		if room == null or not _world.register_realm(room):
			return false
		_rooms[layout.realm] = room
		_centers[layout.realm] = _point(_seam) if layout.realm == Overworld else layout.center(WorldTopology.ENTRY)
	var player := CombatantState.new()
	player.id = Rider
	player.owner = Rider
	player.realm = Overworld
	player.life = 1
	player.max_hp = Quantity.from_count(100)
	player.hp = QuantityLayerLedger.Pool.new(player.max_hp, QuantityErrorBounds.new())
	if (not _kernel.add_actor(player)
			or not _rooms[Overworld].geometry().add_circle(Rider, 0, _point(_seam + 24.0 * _along), 4.0, WorldActivity.ACTORS)
			or not _world.track_player(Rider)):
		return false
	var predator := _rules(&"hunter", [&"wildborn"], 50, 4)
	predator.hunter = true
	predator.stride = 12.0
	predator.sight = 92.0
	predator.attack_range = 8.0
	predator.pursuit_ticks = 3
	if (not _world.introduce_enemy(Hunter, Overworld, predator, _point(_seam - 30.0 * _along))
			or not _world.introduce_enemy(&"decoy", Overworld, _rules(Wild, [], 40, 1),
				_point(_seam - 24.0 * _along + 18.0 * _along.orthogonal()))):
		return false
	var center := _vector(_centers[Interior])
	if (not _world.introduce_enemy(&"prowler", Interior, _rules(Wild, [Hollow], 30, 12),
				_point(center - Vector2(16, 0)))
			or not _world.introduce_enemy(Fallen, Interior, _rules(Hollow, [Wild], 10, 2),
				_point(center + Vector2(16, 0)))):
		return false
	var site := WorldActivity.SpawnSite.new()
	site.id = &"unvisited"
	site.realm = Unvisited
	site.rules = _rules(Wild, [], 10, 1)
	site.first_tick = 2
	site.period = 3
	site.limit = 1
	var remote := _vector(_centers[Unvisited])
	site.positions = [_point(remote + Vector2(20, 0)), _point(remote - Vector2(20, 0))]
	return _world.schedule_spawn(site)


func _dense_territories() -> bool:
	var profiles := [
		_rules(&"dense_a", [&"dense_b"], 5000, 1),
		_rules(&"dense_b", [&"dense_a"], 5000, 1),
	]
	for realm: StringName in _rooms:
		var center := _overworld.center(_before_seam) if realm == Overworld else _centers[realm]
		for column: int in range(4):
			for row: int in range(4):
				var id := StringName("%s/%d/%d" % [realm, column, row])
				var pose := RealmSweep.Point.new(center.x - 58.0 + 24.0 * column, center.y + 28.0 + 18.0 * row)
				if not _world.introduce_enemy(id, realm, profiles[(column + row) % profiles.size()], pose):
					return false
	return true


func _physics_process(_delta: float) -> void:
	_tick += 1
	if _tick == 1:
		var before := _world.snapshot()
		_skip_rejected = _world.advance(3) == null and before == _world.snapshot()
	if _tick == 4:
		_reanimated = (_world.reanimate(Fallen, 1, Quantity.from_count(5, 1), 3)
			and not _world.reanimate(Fallen, 1, Quantity.from_count(5, 1), 3))
	if _tick == 10:
		var previous := _kernel.actor_snapshot(&"prowler")
		_maximum_changed = (_kernel.change_max_hp(previous.id, previous.life, Quantity.from_count(60))
			and _kernel.actor_snapshot(previous.id).hp.amount.compare(previous.hp.amount) == 0)
	if _tick in [4, 5, 6]:
		var target := _seam + _along * (24 + (_tick - 3) * 38)
		_controls.apply(PlayerCommand.new(PlayerCommand.MOVE_TO, target.x, target.y))
		if _controls.step(_rooms[Overworld].geometry(), Rider, 0, WorldExploration.BLOCKER, 2400.0, 1.0 / 60.0) == null:
			_finish(false)
			return
	var floor := _rooms[Overworld].geometry()
	if not _rooms[Overworld].observe_seat(Rider, Overworld, floor.circle_center(Rider, 0)):
		_finish(false)
		return
	var started := Time.get_ticks_usec()
	var step := _world.advance(_tick)
	_step_samples.append(Time.get_ticks_usec() - started)
	if step == null:
		_finish(false)
		return
	_state = _world.snapshot()
	var hunter: Array = _state.actors[Hunter]
	var memory: Array = hunter[7][3]
	_detected = _detected or (not memory.is_empty() and memory[0] == Rider)
	_crossed = _crossed or hunter[6] == _after_seam
	_lost = _lost or (_detected and _tick > 6 and memory.is_empty())
	var hits: Array[Array] = []
	for wave: CombatKernel.WaveResult in step.combat:
		for hit: CombatKernel.Hit in wave.hits:
			if hit.accepted:
				hits.append([hit.source, hit.target, hit.target_life, hit.origin.provenance, hit.eliminated])
				if hit.eliminated:
					_kills.append([hit.target, hit.target_life, hit.origin.provenance, hit.origin.owner])
	for spawn: Array in step.spawns:
		if spawn[0] == &"unvisited" and spawn[1] not in [&"full", &"no_clearance"]:
			_opened_without_view = true
	var fog := _rooms[Overworld].view(Rider)
	_facts.append({"state": _state, "spawns": step.spawns, "hits": hits, "fog": fog})
	if _mode in ["full", "switch"]:
		queue_redraw()
	if _tick == (DenseAges if _mode == "dense" else Ages):
		set_physics_process(false)
		await _capture_frame()
		var expected: Array[Array] = [[Fallen, 1, CombatOrigin.Provenance.SPAWN, &"prowler"],
			[Fallen, 2, CombatOrigin.Provenance.SPAWN, &"prowler"]]
		if _mode == "dense":
			expected.append([&"decoy", 1, CombatOrigin.Provenance.SPAWN, Hunter])
		_finish(_detected and _crossed and _lost and _reanimated and _maximum_changed
			and _skip_rejected and _opened_without_view and _kills == expected
			and _state.defeated_lives[Fallen] == 2 and _state.rng[&"world-spawn/unvisited"][1] == 1)


func _finish(passed: bool) -> void:
	set_physics_process(false)
	var canonical := JSON.stringify(_facts, "", true)
	var written := true
	if not _capture.is_empty():
		var file := FileAccess.open(_capture.path_join("trace.json"), FileAccess.WRITE)
		written = file != null
		if file != null:
			file.store_string(canonical + "\n")
			file.close()
	var outcome := {"passed": passed and written, "digest": canonical.sha256_text(), "fault": _world.fault(),
		"detected": _detected, "crossed": _crossed, "lost": _lost, "reanimated": _reanimated,
		"maximum_preserved_hp": _maximum_changed, "skip_rejected": _skip_rejected,
		"remote_spawn": _opened_without_view, "kills": _kills}
	print("WP18_WORLD ", JSON.stringify(outcome))
	_step_samples.sort()
	if not _step_samples.is_empty():
		var count := _step_samples.size()
		print("WP18_CPU ", JSON.stringify({"ticks": count, "bodies": _state.get("actors", {}).size(),
			"median_usec": _step_samples[(count - 1) >> 1],
			"p95_usec": _step_samples[ceili(count * 0.95) - 1], "max_usec": _step_samples.back()}))
	get_tree().quit(0 if outcome.passed else 1)


func _capture_frame() -> void:
	if _capture.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	if get_viewport().get_texture().get_image().save_png(_capture.path_join("world.png")) != OK:
		push_error("WP18 viewport evidence could not be saved")


func _draw() -> void:
	if _state.is_empty():
		return
	var drawn: Array[StringName] = [Overworld]
	if _mode == "full":
		drawn = [Overworld, Interior, Unvisited]
	elif _tick in [1, Ages]:
		drawn.append(Interior)
	var colors := {Rider: Color("82eeca"), Hunter: Color("e59ada")}
	for index: int in drawn.size():
		var realm := drawn[index]
		var viewport := Rect2(12 + index * 310, 36, 298, 330)
		draw_rect(viewport, Color("30464d"))
		draw_string(ThemeDB.fallback_font, viewport.position + Vector2(12, 24), String(realm))
		var center := _vector(_centers[realm])
		for id: StringName in _state.actors:
			var actor: Array = _state.actors[id]
			if actor[0] != realm:
				continue
			var local := (Vector2(actor[4], actor[5]) - center) * 0.8
			var spot := viewport.get_center() + local
			draw_circle(spot, 8.0, Color("7b7472") if actor[2] == "0" else colors.get(id, Color("edc182")))
			draw_string(ThemeDB.fallback_font, spot + Vector2(12, -5), String(id))


static func _rules(faction_id: StringName, foes: Array[StringName], hp: int, damage: int) -> WorldEnemy.Rules:
	var rules := WorldEnemy.Rules.new()
	rules.faction = faction_id
	rules.foes = foes
	rules.family = StringName("fixture/%s" % faction_id)
	rules.hp = Quantity.from_count(hp)
	rules.damage = Quantity.from_count(damage)
	rules.radius = 4.0
	rules.sight = 72.0
	rules.attack_range = 46.0
	rules.attack_radius = 6.0
	rules.windup_ticks = 2
	rules.recovery_ticks = 2
	return rules


static func _vector(point: RealmSweep.Point) -> Vector2:
	return Vector2(point.x, point.y)


static func _point(vector: Vector2) -> RealmSweep.Point:
	return RealmSweep.Point.new(vector.x, vector.y)
