extends RefCounted
## One in-flight frame. The child only receives the project's visible projection.

const MAX_LINE := 2048

var _pipe: FileAccess
var _received := PackedByteArray()
var _pid := -1
var _next_id := 0
var _waiting := false
var _failed := false


func start(python: String, policy_path: String) -> bool:
	var process := OS.execute_with_pipe(python, ["-I", "-u", policy_path], false)
	if process.is_empty():
		return false
	_pipe = process["stdio"]
	_pid = process["pid"]
	return true


func pending() -> bool:
	return _waiting


func failed() -> bool:
	return _failed or (_pid > 0 and not OS.is_process_running(_pid))


func send(view: Dictionary) -> bool:
	if _waiting or _pipe == null:
		return false
	_next_id += 1
	var line := (JSON.stringify({"protocol": 1, "id": _next_id, "view": view}) + "\n").to_utf8_buffer()
	if line.size() > MAX_LINE or not _pipe.store_buffer(line):
		_failed = true
		return false
	_waiting = true
	return true


func poll() -> Dictionary:
	if not _waiting or _pipe == null:
		return {}
	_received.append_array(_pipe.get_buffer(MAX_LINE))
	var newline := _received.find(10)
	if _received.size() > MAX_LINE or (newline >= 0 and newline != _received.size() - 1):
		_failed = true
		return {}
	if newline < 0:
		return {}
	var reply: Variant = JSON.parse_string(_received.get_string_from_utf8())
	_received.clear()
	_waiting = false
	if not reply is Dictionary or reply.size() != 3 or reply.get("protocol") != 1 \
			or reply.get("id") != _next_id or not reply.get("command") is Dictionary:
		_failed = true
		return {}
	return reply["command"]


func close() -> void:
	if _pipe != null:
		_pipe.close()
		_pipe = null
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
