extends Control
## A rendered fixture with a normal Control input route and a labeled deterministic replay.

const FixtureRules := preload("res://dev/fixtures/run_authority_fixture_rules.gd")
const SPLIT_TICK := 90
const END_TICK := 180

var _run := FixtureRules.new()
var _setup := RunSetup.new()
var _automatic: bool
var _diagnostics: bool
var _resuming: bool
var _checkpoint_path: String
var _sequence: int
var _frames := 0
var _started_usec: int
var _digest := HashingContext.new()

@onready var _status: Label = %Status
@onready var _input_result: Label = %InputResult
@onready var _closed_result: Label = %ClosedResult


func _ready() -> void:
	_setup.run_id = &"wp02-fixture"
	_setup.authority_id = &"fixture-local"
	_setup.epoch = 2
	_setup.seed = 426001
	_setup.rules_revision = &"V42.6/R1"
	_setup.catalog_revision = &"wp02-fixture-v1"
	_setup.challenge_id = &"fixture"
	_setup.initial_realms = {&"seat-1": &"realm-core"}
	var args := OS.get_cmdline_user_args()
	_automatic = args.has("--wp02-auto")
	_diagnostics = args.has("--wp02-trace")
	_resuming = args.has("--wp02-resume")
	if _automatic:
		_setup.role = RunSetup.Role.HOST
		_setup.initial_realms[&"seat-2"] = &"realm-side"
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		for arg: String in args:
			if arg.begins_with("--wp02-fps="):
				Engine.max_fps = arg.get_slice("=", 1).to_int()
			elif arg.begins_with("--wp02-checkpoint="):
				_checkpoint_path = arg.trim_prefix("--wp02-checkpoint=")
	if _resuming:
		var file := FileAccess.open(_checkpoint_path, FileAccess.READ)
		if file == null:
			_fail("missing checkpoint")
			return
		var saved: Variant = file.get_var()
		if not saved is Dictionary or not _run.restore(_setup, _setup.authority_id, saved):
			_fail("checkpoint rejected")
			return
	elif not _run.start(_setup, _setup.authority_id):
		_fail("run setup rejected")
		return
	%Sample.pressed.connect(_manual_submit.bind(false))
	%Stale.pressed.connect(_manual_submit.bind(true))
	_digest.start(HashingContext.HASH_SHA256)
	_started_usec = Time.get_ticks_usec()
	print("WP02_READY ", _setup.identity())


func _process(_delta: float) -> void:
	_frames += 1


func _physics_process(_delta: float) -> void:
	var tick := _run.next_tick()
	var admissions: Array[String] = []
	if _automatic:
		admissions = _replay_inputs(tick)
	if not _run.close_tick():
		_fail("could not close tick")
		return
	var closed := _run.closed_result()
	_status.text = "Run %s    Epoch %d    Closed tick %d" % [_setup.run_id, _setup.epoch, tick]
	if not closed["outcomes"].is_empty():
		_closed_result.text = "Closed at %d: %s" % [tick, closed["outcomes"]]
		if not _automatic:
			print("WP02_MANUAL_CLOSED ", closed)
	if not _automatic:
		return
	var checkpoint := _run.checkpoint()
	var sample: Array = [admissions, closed, checkpoint["random"]]
	_digest.update(var_to_bytes(sample))
	if _diagnostics and (not admissions.is_empty() or tick in [SPLIT_TICK, END_TICK]):
		print("WP02_TRACE ", sample)
	if tick == SPLIT_TICK:
		_report(tick, checkpoint)
		_digest.start(HashingContext.HASH_SHA256)
		_started_usec = Time.get_ticks_usec()
		_frames = 0
		if not _checkpoint_path.is_empty():
			var file := FileAccess.open(_checkpoint_path, FileAccess.WRITE)
			if file == null or not file.store_var(checkpoint):
				_fail("checkpoint write failed")
			else:
				file.close()
				get_tree().quit(0)
	elif tick == END_TICK:
		_report(tick, checkpoint)
		get_tree().quit(0)


func _replay_inputs(tick: int) -> Array[String]:
	var admissions: Array[String] = []
	if tick % 30 == 1:
		# Arrival order differs from canonical seat/sequence order.
		admissions.append(_submit(&"seat-2", tick, tick, &"sample_reward", _setup.epoch))
		admissions.append(_submit(&"seat-1", tick, tick + 1, &"sample_reward", _setup.epoch))
		admissions.append(_submit(&"seat-1", tick, tick, &"sample_world", _setup.epoch))
		admissions.append(_submit(&"seat-1", tick, tick, &"sample_world", _setup.epoch))
	if tick % 30 == 2:
		admissions.append(_submit(&"seat-1", tick, tick + 1, &"sample_world", _setup.epoch - 1))
		admissions.append(_submit(&"seat-2", tick - 1, tick, &"sample_world", _setup.epoch))
		admissions.append(_submit(&"seat-1", tick, tick, &"sample_world", _setup.epoch))
	return admissions


func _manual_submit(stale: bool) -> void:
	_sequence += 1
	var epoch := _setup.epoch - int(stale)
	var admission := _submit(&"seat-1", _run.next_tick(), _sequence, &"sample_world", epoch)
	_input_result.text = "Input %d: %s" % [_sequence, admission]
	print("WP02_MANUAL_INPUT ", _input_result.text)


func _submit(seat: StringName, tick: int, sequence: int, action: StringName, epoch: int) -> String:
	var intent := RunIntent.new(_setup.run_id, epoch, _setup.initial_realms[seat], seat, tick, sequence, action)
	return RunAuthority.Admission.keys()[_run.submit(seat, intent)]


func _report(tick: int, checkpoint: Dictionary) -> void:
	var seconds := (Time.get_ticks_usec() - _started_usec) / 1000000.0
	print("WP02_RESULT tick=%d digest=%s checkpoint=%s frames=%d seconds=%.3f fps=%.1f trace=%s" % [
		tick, _digest.finish().hex_encode(), var_to_bytes(checkpoint).hex_encode().sha256_text(),
		_frames, seconds, _frames / seconds, _diagnostics,
	])


func _fail(reason: String) -> void:
	set_physics_process(false)
	push_error("WP02_FIXTURE " + reason)
	get_tree().quit(1)
