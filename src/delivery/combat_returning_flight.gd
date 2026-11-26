class_name CombatReturningFlight
extends RefCounted
## An already paid outward and return flight. Each step uses actual geometry
## and the return samples its current realm-local anchor.

enum Phase { OUTWARD, RETURNING, FINISHED }

class Step:
	var _flight: CombatReturningFlight
	var _geometry: RealmGeometry
	var _ordinal: int
	var phase: Phase
	var next_phase: Phase
	var finish: RealmSweep.Point
	var sweep: CombatDelivery.SweepPlan

var _delivery: CombatDelivery
var _position: RealmSweep.Point
var _outward_end: RealmSweep.Point
var _phase: Phase
var _ordinal: int
var _max_steps: int

var phase: Phase:
	get: return _phase


static func create(kernel: CombatKernel, action: CombatAction, realm: StringName,
		launch: RealmSweep.Point, outward_end: RealmSweep.Point, max_steps: int) -> CombatReturningFlight:
	if not _finite(launch) or not _finite(outward_end) or max_steps <= 0:
		return null
	if launch.x == outward_end.x and launch.y == outward_end.y:
		return null
	var delivery := CombatDelivery.activate(kernel, action, realm, 0, true)
	if delivery == null:
		return null
	var flight := CombatReturningFlight.new()
	flight._delivery = delivery
	flight._position = RealmSweep.Point.new(launch.x, launch.y)
	flight._outward_end = RealmSweep.Point.new(outward_end.x, outward_end.y)
	flight._max_steps = max_steps
	return flight


func plan(geometry: RealmGeometry, return_anchor: RealmSweep.Point, distance: float,
		radius: float, targets: int, blockers: int) -> Step:
	if _phase == Phase.FINISHED or not is_finite(distance) or distance <= 0.0:
		return null
	var goal := _outward_end if _phase == Phase.OUTWARD else return_anchor
	if not _finite(goal):
		return null
	var desired := _advance_toward(_position, goal, distance)
	if desired == null:
		return null
	var step := Step.new()
	step._flight = self
	step._geometry = geometry
	step._ordinal = _ordinal
	step.phase = _phase
	step.next_phase = _phase
	step.sweep = _delivery.plan_sweep(geometry, _position, desired, radius, targets, blockers, true)
	if step.sweep == null:
		return null
	step.finish = step.sweep.finish
	var arrived := desired.x == goal.x and desired.y == goal.y
	if arrived or step.sweep.blocker != null:
		step.next_phase = Phase.RETURNING if _phase == Phase.OUTWARD else Phase.FINISHED
	if _ordinal + 1 == _max_steps:
		step.next_phase = Phase.FINISHED
	return step


func admit(step: Step, start_tick: int, contact: RealmGeometry.Contact, life: int, hostile: bool) -> CombatDelivery.Result:
	if not _awaits(step) or contact not in step.sweep.contacts:
		return CombatDelivery.Result.INVALID
	return _delivery.admit(start_tick, contact, life, hostile, int(step.phase))


func settle(step: Step) -> bool:
	if not _awaits(step):
		return false
	if step.next_phase == Phase.FINISHED and not _delivery.finish():
		return false
	_position = RealmSweep.Point.new(step.finish.x, step.finish.y)
	_phase = step.next_phase
	_ordinal += 1
	return true


func cancel() -> bool:
	if _phase == Phase.FINISHED or not _delivery.finish():
		return false
	_phase = Phase.FINISHED
	return true


func _awaits(step: Step) -> bool:
	return (step != null and step._flight == self and step._ordinal == _ordinal and step.phase == _phase
		and step._geometry != null and step.sweep != null and step._geometry.revision == step.sweep.revision)


static func _advance_toward(start: RealmSweep.Point, goal: RealmSweep.Point, distance: float) -> RealmSweep.Point:
	var dx := goal.x - start.x
	var dy := goal.y - start.y
	var largest := maxf(absf(dx), absf(dy))
	if largest == 0.0:
		return RealmSweep.Point.new(goal.x, goal.y)
	if not is_finite(largest):
		return null
	var unit_x := dx / largest
	var unit_y := dy / largest
	var scale := distance / sqrt(unit_x * unit_x + unit_y * unit_y)
	if scale >= largest:
		return RealmSweep.Point.new(goal.x, goal.y)
	return RealmSweep.Point.new(start.x + scale * unit_x, start.y + scale * unit_y)


static func _finite(point: RealmSweep.Point) -> bool:
	return point != null and is_finite(point.x) and is_finite(point.y)
