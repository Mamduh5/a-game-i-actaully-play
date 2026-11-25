extends Node
## Compare one committed combat trace under different rendered wave budgets.

const REALM := &"fixture_realm"
const CHARGE := &"fixture_charge"
const PAID_REACTIONS := 96

var _kernel := CombatKernel.new()
var _budget: int
var _stage := 1
var _rendered := false
var _frames: int
var _yields: int
var _rows: Array[Array] = []
var _label := Label.new()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or args[0].to_int() <= 0:
		_finish(false)
		return
	_budget = args[0].to_int()
	_rendered = DisplayServer.get_name() != "headless"
	_label.position = Vector2(32, 32)
	_label.text = "WP09 combat fixture\nLast committed charges: 96"
	add_child(_label)
	var hero := _actor(&"hero", 2)
	hero.resources[CHARGE] = Quantity.from_count(PAID_REACTIONS)
	var paid := _reaction(&"paid", CombatFollowUp.Cause.PAID_HIT, 0)
	paid.resource = CHARGE
	paid.cost = Quantity.from_count(1)
	hero.follow_ups = [paid, _reaction(&"retaliate", CombatFollowUp.Cause.HOSTILE_HP, 3)]
	if (not _kernel.add_actor(hero) or not _kernel.add_actor(_actor(&"target", 10))
			or not _kernel.add_actor(_actor(&"creator", 3)) or not _kernel.configure_terminal(&"creator", [&"hero"])
			or not _admit(&"hero", &"target", 1, 2, 0)):
		_finish(false)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames > 150:
		_finish(false)
		return
	var result := _kernel.resolve_next(CombatInstant.at_tick(3 if _stage == 1 else 5), _budget)
	if result.result == CombatKernel.Result.YIELDED:
		_yields += 1
		var visible := _kernel.actor_snapshot(&"hero")
		var charge: int = visible.resources[CHARGE].native_at_scale(0)
		if not result.hits.is_empty() or charge != (PAID_REACTIONS if _stage == 1 else 0) or not visible.is_alive():
			_finish(false)
		return
	if result.result != CombatKernel.Result.CLOSED:
		_finish(false)
		return
	for hit: CombatKernel.Hit in result.hits:
		_rows.append([_stage, hit.wave, hit.event, hit.parent, hit.source, hit.target, hit.reaction, hit.eliminated])
	if _stage == 1:
		if result.waves != PAID_REACTIONS + 1 or result.terminal != CombatKernel.Terminal.ACTIVE or not _admit(&"creator", &"hero", 3, 4, 2):
			_finish(false)
			return
		_stage = 2
		_label.text = "WP09 combat fixture\nLast committed charges: 0"
		return
	_finish(result.waves == 2 and result.terminal == CombatKernel.Terminal.VICTORY and result.eliminations.size() == 2)


func _admit(source: StringName, target: StringName, commit_tick: int, due_tick: int, damage: int) -> bool:
	var action := CombatAction.new()
	action.source = source
	action.source_life = 1
	action.family = &"fixture"
	action.origin = CombatOrigin.new()
	action.origin.owner = source
	action.origin.activation = 1
	action.origin.committed_at = CombatInstant.at_tick(commit_tick)
	var component := CombatAction.Component.new()
	component.base = Quantity.from_count(damage)
	action.components = [component]
	var geometry := RealmGeometry.new(REALM)
	if not geometry.add_circle(target, 0, RealmSweep.Point.new(0, 0), 1.0, 1):
		return false
	var proof := geometry.certify_circle_sweep(REALM, RealmSweep.Point.new(-2, 0), RealmSweep.Point.new(2, 0), 0, 1)
	if proof == null or proof.contacts.size() != 1:
		return false
	return _kernel.admit_contact(_kernel.commit(action), 1, REALM, due_tick, proof.contacts[0], 1, true) == CombatRootQueue.Result.ACCEPTED


func _finish(passed: bool) -> void:
	set_process(false)
	print("WP09_RESULT ", JSON.stringify({"passed": passed, "rendered": _rendered, "budget": _budget,
		"frames": _frames, "yielded": _yields, "posts": _rows.size(), "trace": JSON.stringify(_rows).sha256_text()}))
	get_tree().quit(0 if passed else 1)


static func _actor(id: StringName, hp: int) -> CombatantState:
	var actor := CombatantState.new()
	actor.id = id
	actor.owner = id
	actor.realm = REALM
	actor.life = 1
	actor.hp = QuantityLayerLedger.Pool.new(Quantity.from_count(hp), QuantityErrorBounds.new())
	return actor


static func _reaction(id: StringName, cause: CombatFollowUp.Cause, hp: int) -> CombatFollowUp:
	var rule := CombatFollowUp.new()
	rule.id = id
	rule.family = id
	rule.cause = cause
	rule.component = CombatAction.Component.new()
	rule.component.base = Quantity.from_count(hp)
	return rule
