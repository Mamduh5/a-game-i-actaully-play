extends Node
## Controlled engine witness for whole barriers and terminal causal completion.

const REALM := &"survival_fixture"
const HERO := &"hero"
const CREATOR := &"creator"
const GUARD := &"guard"

var _kernel := CombatKernel.new()
var _budget: int
var _stage := 1
var _frames: int
var _yields: int
var _rendered: bool
var _captures: String
var _screen := Label.new()
var _trace: Array[Array] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or args[0].to_int() <= 0:
		_finish(false)
		return
	_budget = args[0].to_int()
	_rendered = DisplayServer.get_name() != "headless"
	if _rendered and args.size() == 2:
		_captures = args[1]
	_screen.position = Vector2(32, 32)
	_screen.add_theme_font_size_override("font_size", 24)
	add_child(_screen)
	var hero := _actor(HERO, 3)
	var layer := CombatantState.Barrier.new()
	layer.id = GUARD
	layer.mask = CombatAction.Damage.PHYSICAL
	layer.pool = QuantityLayerLedger.Pool.new(Quantity.from_count(80), QuantityErrorBounds.new())
	layer.expires = CombatInstant.at_tick(6)
	hero.barriers = [layer]
	var release := CombatFollowUp.new()
	release.id = &"fortified_release"
	release.family = release.id
	release.cause = CombatFollowUp.Cause.HOSTILE_LAYER
	release.layer = GUARD
	release.component = _component(4)
	hero.follow_ups = [release]
	if (not _kernel.add_actor(hero) or not _kernel.add_actor(_actor(CREATOR, 4))
			or not _kernel.configure_terminal(CREATOR, [HERO]) or not _grant(1, 60, 8)):
		_finish(false)


func _process(_delta: float) -> void:
	_frames += 1
	# Render each settled state across several frames before taking a capture.
	if _rendered and _frames % 18 != 1:
		return
	if _rendered and not _captures.is_empty() and _stage > 1:
		var pixels := get_viewport().get_texture().get_image()
		if pixels.save_png(_captures.path_join("stage-%d.png" % (_stage - 1))) != OK:
			_finish(false)
			return
	if _stage == 5:
		_finish(true)
		return
	var due := CombatInstant.at_tick([1, 2, 10, 12][_stage - 1])
	var wave := _kernel.advance_survival(due) if _stage == 3 else _kernel.resolve_next(due, _budget)
	if wave.result == CombatKernel.Result.YIELDED:
		_yields += 1
		if not _kernel.actor_snapshot(HERO).is_alive() or not wave.hits.is_empty():
			_finish(false)
		return
	if wave.result != CombatKernel.Result.CLOSED:
		_finish(false)
		return
	var hero := _kernel.actor_snapshot(HERO)
	var layer: CombatantState.Barrier = hero.barriers[0] if not hero.barriers.is_empty() else null
	var ending := wave.ended_barriers[0] if wave.ended_barriers.size() == 1 else null
	var verdict := false
	match _stage:
		1:
			verdict = ending == null and layer != null and layer.generation == 1 and layer.expires.tick == 6
			verdict = verdict and _grant(2, 80, 8)
		2:
			verdict = (ending != null and ending.reason == CombatKernel.BarrierEnd.REPLACED
				and layer != null and layer.generation == 2 and layer.expires.tick == 10 and wave.hits.size() == 1)
		3:
			verdict = (ending != null and ending.reason == CombatKernel.BarrierEnd.EXPIRED
				and layer == null and wave.hits.is_empty() and _grant(11, 2, 5))
			if verdict:
				var supplied := _kernel.resolve_next(CombatInstant.at_tick(11), _budget)
				var later := _action(HERO, 12, 4)
				var lethal := _action(CREATOR, 12, 5)
				verdict = (supplied.result == CombatKernel.Result.CLOSED
					and _admit(later, CREATOR, 14) and _admit(lethal, HERO, 12))
		4:
			verdict = (wave.terminal == CombatKernel.Terminal.VICTORY and wave.eliminations.size() == 2
				and wave.hits.size() == 2 and wave.hits[1].reaction == &"fortified_release"
				and wave.hits[0].components[0].barriers[0].hostile_depletion and _kernel.pending_count() == 0)
	if not verdict:
		_finish(false)
		return
	var capacity: int = layer.pool.amount.native_at_scale(0) if layer != null else 0
	_trace.append([_stage, capacity, layer.generation if layer != null else 0, ending.reason if ending != null else -1,
		wave.hits.size(), wave.eliminations.size(), wave.terminal])
	_screen.text = "WP11 survival fixture\nHero HP %s | Guard %d\n%s" % [
		hero.hp.amount.native_at_scale(0), capacity,
		["Stronger current instance kept", "Whole instance replaced", "Barrier expired", "Immediate release: victory"][_stage - 1],
	]
	_stage += 1


func _grant(tick: int, capacity: int, duration: int) -> bool:
	var action := _action(HERO, tick, 0)
	var grant := CombatAction.BarrierGrant.new()
	grant.id = GUARD
	grant.mask = CombatAction.Damage.PHYSICAL
	grant.capacity = Quantity.from_count(capacity)
	grant.duration_ticks = duration
	grant.rule = CombatAction.BarrierRule.STRONGEST
	action.barrier_for_source = grant
	return _admit(action, CREATOR, tick)


func _admit(action: CombatAction, target: StringName, due: int) -> bool:
	var geometry := RealmGeometry.new(REALM)
	var center := RealmSweep.Point.new(0, 0)
	if not geometry.add_circle(target, 0, center, 1.0, 1):
		return false
	var sweep := geometry.certify_circle_sweep(REALM, center, center, 0.0, 1)
	return _kernel.admit_contact(_kernel.commit(action), 1, REALM, due, sweep.contacts[0], 1, true) == CombatRootQueue.Result.ACCEPTED


static func _action(source: StringName, tick: int, damage: int) -> CombatAction:
	var action := CombatAction.new()
	action.source = source
	action.source_life = 1
	action.family = &"fixture"
	action.origin = CombatOrigin.new()
	action.origin.owner = source
	action.origin.activation = tick
	action.origin.committed_at = CombatInstant.at_tick(tick)
	action.components = [_component(damage)]
	return action


static func _component(damage: int) -> CombatAction.Component:
	var component := CombatAction.Component.new()
	component.base = Quantity.from_count(damage)
	return component


static func _actor(id: StringName, hp: int) -> CombatantState:
	var actor := CombatantState.new()
	actor.id = id
	actor.life = 1
	actor.owner = id
	actor.realm = REALM
	actor.hp = QuantityLayerLedger.Pool.new(Quantity.from_count(hp), QuantityErrorBounds.new())
	actor.max_hp = Quantity.from_count(hp)
	return actor


func _finish(passed: bool) -> void:
	var facts := JSON.stringify(_trace)
	print("WP11 passed=%s rendered=%s budget=%d yields=%d hash=%s facts=%s" % [
		passed, _rendered, _budget, _yields, facts.sha256_text(), facts,
	])
	get_tree().quit(0 if passed else 1)
