class_name RunRandom
extends RefCounted
## Named deterministic streams. Only run rules receive the draw interface.

class Stream:
	var rng := RandomNumberGenerator.new()
	var draws: int


var _seed: int
var _streams: Dictionary[StringName, Stream] = {}


func _init(run_seed: int) -> void:
	_seed = run_seed


func draw(stream_id: StringName) -> int:
	if not _streams.has(stream_id):
		_streams[stream_id] = _make_stream(stream_id)
	var stream: Stream = _streams[stream_id]
	stream.draws += 1
	return stream.rng.randi()


func checkpoint() -> Dictionary:
	var names: Array[StringName] = _streams.keys()
	names.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	var result: Dictionary = {}
	for stream_id: StringName in names:
		var stream: Stream = _streams[stream_id]
		result[stream_id] = [stream.rng.state, stream.draws]
	return result


## Local checkpoint import. The caller pins the build before restoring.
func restore(data: Dictionary) -> bool:
	var restored: Dictionary[StringName, Stream] = {}
	for stream_id: Variant in data:
		var pair: Variant = data[stream_id]
		if not stream_id is StringName or not pair is Array or pair.size() != 2:
			return false
		if not pair[0] is int or not pair[1] is int or pair[1] < 1:
			return false
		var stream := _make_stream(stream_id)
		stream.rng.state = pair[0]
		stream.draws = pair[1]
		restored[stream_id] = stream
	_streams = restored
	return true


func _make_stream(stream_id: StringName) -> Stream:
	var stream := Stream.new()
	var material := "%d/%s" % [_seed, stream_id]
	stream.rng.seed = material.sha256_buffer().decode_s64(0)
	return stream
