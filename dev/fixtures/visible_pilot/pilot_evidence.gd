extends RefCounted
## Write-only observer. No policy or actuator receives this object or its path.

var _writer: FileAccess


func open(path: String) -> bool:
	_writer = FileAccess.open(path, FileAccess.WRITE)
	return _writer != null


func record(kind: String, tick: int, data: Dictionary) -> void:
	if _writer != null:
		_writer.store_line(JSON.stringify({
			"kind": kind, "tick": tick, "monotonic_usec": Time.get_ticks_usec(), "data": data,
		}))


func close() -> void:
	if _writer != null:
		_writer.close()
		_writer = null
