extends Node

const Result := ProfileStore.OpenResult

var _profile := ProfileStore.new()
var _until: int
var _release: String
var _receipt: Dictionary


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() not in [2, 4]:
		get_tree().quit(2)
		return
	var result := _profile.open(args[1], args[0])
	_receipt = {"open": Result.keys()[result], "mode": _profile.mode(), "diagnostic": _profile.diagnostic()}
	if result != Result.OPENED or args.size() == 2:
		_finish()
		return
	_release = args[3]
	_until = Time.get_ticks_msec() + 12000
	var ready := FileAccess.open(args[2], FileAccess.WRITE)
	if ready == null:
		get_tree().quit(2)
		return
	ready.store_8(1)
	ready.close()


func _process(_delta: float) -> void:
	if not _release.is_empty() and FileAccess.file_exists(_release):
		_finish()
	elif _until > 0 and Time.get_ticks_msec() >= _until:
		get_tree().quit(2)


func _finish() -> void:
	_receipt["closed"] = _profile.close()
	print("WP13_PROFILE ", JSON.stringify(_receipt))
	get_tree().quit(0 if _receipt["closed"] else 1)
