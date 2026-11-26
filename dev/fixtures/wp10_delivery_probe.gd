extends Node2D
## Native witness for paid return flight, moving owner and frozen damage.

const REALM := &"delivery_fixture"
const OWNER := &"owner"
const TARGET := &"target"
const MANA := &"mana"

var _geometry := RealmGeometry.new(REALM)
var _kernel := CombatKernel.new()
var _flight: CombatReturningFlight
var _position := RealmSweep.Point.new(0, 0)
var _path: Array[RealmSweep.Point] = []
var _stage := 1
var _frames: int
var _rendered: bool
var _capture: String
var _label := Label.new()
var _trace: Array[Array] = []


func _ready() -> void:
	_rendered = DisplayServer.get_name() != "headless"
	var args := OS.get_cmdline_user_args()
	if _rendered and args.size() == 1:
		_capture = args[0]
	_label.position = Vector2(32, 24)
	_label.add_theme_font_size_override("font_size", 23)
	_label.text = "WP10 paid return flight"
	add_child(_label)
	var owner := _actor(OWNER)
	owner.resources[MANA] = Quantity.from_count(3)
	if (not _kernel.add_actor(owner) or not _kernel.add_actor(_actor(TARGET))
			or not _geometry.add_circle(OWNER, 0, _position, 1.0, 1)
			or not _geometry.add_circle(TARGET, 0, RealmSweep.Point.new(3, 0), 1.0, 1)):
		_finish(false)
		return
	var action := CombatAction.new()
	action.source = OWNER
	action.source_life = 1
	action.family = &"returning_fixture"
	action.origin = CombatOrigin.new()
	action.origin.owner = OWNER
	action.origin.activation = 1
	action.origin.committed_at = CombatInstant.at_tick(1)
	var component := CombatAction.Component.new()
	component.base = Quantity.from_count(2)
	action.components = [component]
	action.activation_costs[MANA] = Quantity.from_count(3)
	_flight = CombatReturningFlight.create(_kernel, action, REALM, _position, RealmSweep.Point.new(8, 0), 10)
	if _flight == null:
		_finish(false)
		return
	# Change the original payload after paying to exercise the held snapshot.
	component.base = Quantity.from_count(12)
	_path.append(_position)


func _process(_unused: float) -> void:
	_frames += 1
	if _rendered and _frames % 24 != 1:
		return
	if _stage == 5:
		if not _capture.is_empty() and get_viewport().get_texture().get_image().save_png(_capture) != OK:
			_finish(false)
			return
		_finish(true)
		return
	if _stage == 3 and (not _geometry.commit_circle_pose(OWNER, 0, RealmSweep.Point.new(8, 8))
			or not _geometry.commit_circle_pose(TARGET, 0, RealmSweep.Point.new(8, 2))):
		_finish(false)
		return
	if _stage == 4 and not _geometry.commit_circle_pose(OWNER, 0, RealmSweep.Point.new(12, 4)):
		_finish(false)
		return
	var anchor := _geometry.circle_center(OWNER, 0)
	var step := _flight.plan(_geometry, anchor, 4.0, 0.0, 1, 2)
	if step == null:
		_finish(false)
		return
	var tick := _stage * 2
	var posted := 0
	for contact: RealmGeometry.Contact in step.sweep.contacts:
		match _flight.admit(step, tick, contact, 1, true):
			CombatDelivery.Result.ADMITTED: posted += 1
			CombatDelivery.Result.CADENCE: pass
			_:
				_finish(false)
				return
	if not _flight.settle(step):
		_finish(false)
		return
	var wave := _kernel.resolve_next(CombatInstant.at_tick(tick + 1), 1)
	var expected := 1 if _stage in [1, 3] else 0
	var hp: int = _kernel.actor_snapshot(TARGET).hp.amount.native_at_scale(0)
	if (posted != expected or wave.hits.size() != expected
			or hp != (18 if _stage < 3 else 16)):
		_finish(false)
		return
	_position = step.finish
	_path.append(_position)
	_trace.append([_stage, _position.x, _position.y, _flight.phase, hp])
	_stage += 1
	if _stage == 5 and _flight.phase != CombatReturningFlight.Phase.FINISHED:
		_finish(false)
		return
	_label.text = "WP10 paid return flight\n%s | Target HP %d" % [
		["Outward hit", "Outbound range reached", "Return tracks the moved owner", "Caught by the moving owner"][_stage - 2], hp,
	]
	queue_redraw()


func _draw() -> void:
	if not _rendered or _flight == null:
		return
	for index: int in range(1, _path.size()):
		draw_line(_screen(_path[index - 1]), _screen(_path[index]), Color("f0ad62"), 4.0, true)
	draw_circle(_screen(_geometry.circle_center(OWNER, 0)), 17.0, Color("94cec6"), true, -1.0, true)
	draw_circle(_screen(_geometry.circle_center(TARGET, 0)), 17.0, Color("dc7784"), true, -1.0, true)
	draw_arc(_screen(_position), 10.0, 0.0, TAU, 32, Color("fff6dc"), 2.0, true)


static func _screen(point: RealmSweep.Point) -> Vector2:
	return Vector2(76.0 + point.x * 48.0, 140.0 + point.y * 36.0)


static func _actor(id: StringName) -> CombatantState:
	var result := CombatantState.new()
	result.id = id
	result.life = 1
	result.owner = id
	result.realm = REALM
	result.hp = QuantityLayerLedger.Pool.new(Quantity.from_count(20), QuantityErrorBounds.new())
	return result


func _finish(passed: bool) -> void:
	var facts := JSON.stringify(_trace)
	print("WP10 passed=%s rendered=%s hash=%s facts=%s" % [passed, _rendered, facts.sha256_text(), facts])
	get_tree().quit(0 if passed else 1)
