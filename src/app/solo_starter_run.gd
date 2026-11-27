class_name SoloStarterRun
extends Node2D
## Native solo composition. Input and display only see the public tick frontier.

signal end_requested

const SEAT := &"solo"
const REALM := WorldTopology.OVERWORLD
const RULES := &"V42.6/R1"

var authority: StarterEncounter
var _setup: RunSetup
var _floor: WorldExploration
var _profile: ProfileStore
var _earnings: OrdinaryCurrency
var _stage: StarterEncounterView
var _router: PlayerInputRouter
var _status: Label
var _end: Button
var _cells: Array[Vector2i] = []
var _sequence: int
var _retry_at: int
var _saved: Quantity
var _finished: bool


static func assemble(profile: ProfileStore, preparation: RunPreparation) -> SoloStarterRun:
	if profile == null or preparation == null:
		return null
	var nonce := Crypto.new().generate_random_bytes(16)
	if nonce.size() != 16:
		return null
	var setup := RunSetup.new()
	setup.run_id = StringName("solo-" + nonce.hex_encode())
	setup.authority_id = SEAT
	setup.epoch = 1
	setup.seed = nonce.decode_s64(0)
	setup.rules_revision = RULES
	setup.catalog_revision = preparation.catalog_revision
	setup.challenge_id = &"normal"
	setup.initial_realms = {SEAT: REALM}
	var floor := WorldExploration.create(WorldTopology.generate(setup.seed), [SEAT])
	if floor == null:
		return null
	var center := floor.module_center(WorldTopology.ANCHORS[0])
	var build := StarterEncounter.Build.new()
	build.preparation = preparation
	build.powers = RunRewardQueue.begin(preparation, RunRandom.new(setup.seed), SEAT)
	build.start = RealmSweep.Point.new(center.x - 78.0, center.y)
	build.maximum_hp = Quantity.from_count(100)
	var encounter := StarterEncounter.assemble(setup, SEAT, floor, {SEAT: build})
	var earnings := OrdinaryCurrency.begin_local(profile, setup, StarterEncounter.COMMON_CURRENCY)
	if encounter == null or earnings == null or not encounter.bind_enemy_currency({SEAT: earnings}):
		return null
	if (not encounter.place_enemy(&"starter/first", _enemy(20, 8), RealmSweep.Point.new(center.x - 12.0, center.y), 3)
			or not encounter.place_enemy(&"starter/second", _enemy(40, 12), RealmSweep.Point.new(center.x + 56.0, center.y + 38.0), 3)):
		return null
	var run := SoloStarterRun.new()
	run.authority = encounter
	run._setup = setup
	run._floor = floor
	run._profile = profile
	run._earnings = earnings
	return run


static func _enemy(hp: int, damage: int) -> WorldEnemy.Rules:
	var rules := WorldEnemy.Rules.new()
	rules.faction = &"starter"
	rules.foes = [WorldEnemy.PARTY]
	rules.family = &"starter/ground_strike"
	rules.hp = Quantity.from_count(hp)
	rules.damage = Quantity.from_count(damage)
	rules.radius = 12.0
	rules.sight = 184.0
	rules.stride = 0.55
	rules.attack_range = 83.0
	rules.attack_radius = 24.0
	rules.windup_ticks = 32
	rules.recovery_ticks = 78
	return rules


func _ready() -> void:
	_saved = _profile.balance(StarterEncounter.COMMON_CURRENCY)
	_stage = StarterEncounterView.new()
	_stage.scale = Vector2.ONE * 1.9
	add_child(_stage)
	_router = PlayerInputRouter.new()
	_router.world_from_viewport = _stage.world_from_viewport
	add_child(_router)
	_status = Label.new()
	_status.position = Vector2(38, 30)
	_status.add_theme_font_size_override("font_size", 21)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)
	_end = Button.new()
	_end.text = "End run"
	_end.position = Vector2(1030, 30)
	_end.size = Vector2(210, 44)
	_end.pressed.connect(func() -> void: end_requested.emit())
	add_child(_end)
	_present()


func _draw() -> void:
	draw_rect(get_viewport_rect(), Color("#202b29"))


func freeze_for_exit() -> void:
	set_physics_process(false)
	_router.clear_focus()
	_end.disabled = true
	_status.text = "Saving earned currency…"


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now < _retry_at:
		return
	var before := _earnings.pending_amount()
	authority.service_ordinary_currency()
	var after := _earnings.pending_amount()
	var settled := before != null and after != null and before.compare(after) != 0
	if settled:
		_saved = _profile.balance(StarterEncounter.COMMON_CURRENCY)
	if _finished:
		if settled:
			_present()
		return
	if not authority.has_unpublished_tick() and authority.can_open_earning_group():
		var tick := authority.next_tick()
		for command: PlayerCommand in _router.drain():
			_sequence += 1
			var intent := RunIntent.new(_setup.run_id, _setup.epoch, REALM, SEAT, tick, _sequence, command.action, command)
			authority.submit(SEAT, intent)
	if not authority.close_tick():
		_router.clear_focus()
		_retry_at = now + 125
		_status.text = "Saving earned currency. Play will resume after storage recovers."
		return
	_present()


func _present() -> void:
	var view := authority.view_for(SEAT)
	if view == null:
		return
	var point := Vector2(view.player.at.x, view.player.at.y)
	var cell := Vector2i((point / WorldTopology.MODULE_SIZE).floor())
	if _cells.is_empty() or _cells[0] != cell:
		_cells.assign([cell])
		var offscreen := point + Vector2(0, 16384)
		_stage.prepare_floor(_cells, StarterEncounterView.section_edges(_cells, _floor.geometry()), offscreen, offscreen)
	_stage.position = get_viewport_rect().size * 0.5 - point * _stage.scale
	_stage.display(view)
	if view.defeated:
		_saved = _profile.balance(StarterEncounter.COMMON_CURRENCY)
	var pending := _earnings.pending_amount()
	var waiting := "  ·  %s pending" % _amount(pending) if pending != null and pending.sign_value > 0 else ""
	_status.text = "HP %s / %s    Barrier %s\nCommon currency  %s%s" % [
		_amount(view.player.hp), _amount(view.player.maximum), _amount(view.barrier), _amount(_saved), waiting]
	if not authority.fault().is_empty() or view.defeated or view.cleared:
		var verdict := "Run interrupted" if not authority.fault().is_empty() else ("Defeated" if view.defeated else "Encounter cleared")
		_status.text += "\n" + verdict
		_end.text = "Return to preparation"
		_finished = true


static func _amount(amount: Quantity) -> String:
	if amount == null:
		return "Unavailable"
	var digits := amount.magnitude_text()
	if amount.scale == 0:
		return digits
	digits = digits.pad_zeros(amount.scale + 1)
	var whole := digits.length() - amount.scale
	return digits.left(whole) + "." + digits.substr(whole)
