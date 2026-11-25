extends GutTest

const ADMISSION := NativeSessionFrame.Kind.ADMISSION
const RELIABLE := NativeSessionFrame.Kind.RELIABLE
const SEQUENCED := NativeSessionFrame.Kind.SEQUENCED
const INITIAL := NativeJoinChallenge.Purpose.INITIAL

var _host := "fixture-host".sha256_buffer()
var _run := "fixture-run".sha256_buffer()
var _key: CryptoKey
var _public_key: CryptoKey


func before_all() -> void:
	_key = Crypto.new().generate_rsa(2048)
	_public_key = CryptoKey.new()
	assert_eq(_public_key.load_from_string(_key.save_to_string(true), true), OK)


func test_protected_dispatch_gates_commands_on_complete_admission_and_fences_duplicates() -> void:
	var authority := NativeAdmission.new(_host, _run, 2)
	var driver := NativePeerAdmission.new(authority, 2)
	assert_true(driver.attach(10, 0, 30))
	assert_true(driver.receive(10, _wire(RELIABLE, 1, PackedByteArray([1])), 1).disconnect)
	assert_false(authority.owns(10, 2, 1))
	assert_true(driver.attach(11, 1, 5))
	assert_eq(driver.expired(5), [11])
	var offered := authority.offer(1, _public_key, 0, 34)
	assert_true(driver.attach(12, 6, 20))
	var malformed := NativeAdmissionMessage.open_for(1, INITIAL, offered)
	malformed.append(0)
	assert_true(driver.receive(12, _wire(ADMISSION, 1, malformed), 7).disconnect)
	assert_true(driver.attach(13, 8, 20))
	var opening := _wire(ADMISSION, 1, NativeAdmissionMessage.open_for(1, INITIAL, offered))
	var challenge := NativeAdmissionMessage.decode(driver.receive(13, opening, 9).reply)
	assert_eq(challenge.operation, NativeAdmissionMessage.Operation.CHALLENGE)
	var attempt := challenge.bytes.decode_s64(NativeJoinChallenge.ATTEMPT_OFFSET)
	var proof := NativeJoinChallenge.sign_challenge(challenge.bytes, INITIAL, 2, attempt, _host, _run, _key)
	var accepted := driver.receive(13, _wire(ADMISSION, 2, NativeAdmissionMessage.proof(proof)), 10)
	assert_eq(accepted.seat, 0)
	assert_eq(NativeAdmissionMessage.decode(accepted.reply).operation, NativeAdmissionMessage.Operation.ACCEPT)
	var acknowledged := driver.receive(13, _wire(ADMISSION, 3, NativeAdmissionMessage.acknowledge()), 11)
	assert_eq(acknowledged.seat, 1)
	assert_eq(NativeAdmissionMessage.decode(acknowledged.reply).operation, NativeAdmissionMessage.Operation.READY)
	assert_not_null(driver.receive(13, _wire(RELIABLE, 1, PackedByteArray([7])), 12).command)
	assert_null(driver.receive(13, _wire(RELIABLE, 1, PackedByteArray([7])), 13).command)
	assert_not_null(driver.receive(13, _wire(SEQUENCED, 2, PackedByteArray([8])), 14).command)
	assert_null(driver.receive(13, _wire(SEQUENCED, 1, PackedByteArray([8])), 15).command)
	var departure := driver.receive(13, _wire(ADMISSION, 4, NativeAdmissionMessage.leave()), 16)
	assert_true(departure.disconnect and departure.voluntary)
	assert_false(authority.owns(13, 2, 1))
	assert_false(driver.can_send(13))


func test_duplicate_frames_count_against_only_the_sending_peer_window() -> void:
	var authority := NativeAdmission.new(_host, _run, 2)
	var driver := NativePeerAdmission.new(authority, 2, 4)
	assert_true(_admit(driver, authority, 10, 1))
	assert_true(_admit(driver, authority, 11, 2))
	var command := _wire(RELIABLE, 1, PackedByteArray([1]))
	assert_not_null(driver.receive(10, command, 20).command)
	assert_true(driver.receive(10, command, 21).disconnect)
	assert_false(authority.owns(10, 2, 1))
	assert_not_null(driver.receive(11, command, 21).command)
	var next := _wire(RELIABLE, 2, PackedByteArray([2]))
	assert_not_null(driver.receive(11, next, NativePeerAdmission.FRAME_WINDOW_MS).command)
	assert_true(authority.owns(11, 2, 2))


func _admit(driver: NativePeerAdmission, authority: NativeAdmission, connection: int, seat: int) -> bool:
	if not driver.attach(connection, 0, 100):
		return false
	var offered := authority.offer(seat, _public_key, 0, 100)
	var opening := _wire(ADMISSION, 1, NativeAdmissionMessage.open_for(seat, INITIAL, offered))
	var challenge := NativeAdmissionMessage.decode(driver.receive(connection, opening, 1).reply)
	if challenge == null:
		return false
	var attempt := challenge.bytes.decode_s64(NativeJoinChallenge.ATTEMPT_OFFSET)
	var signed := NativeJoinChallenge.sign_challenge(challenge.bytes, INITIAL, 2, attempt, _host, _run, _key)
	if driver.receive(connection, _wire(ADMISSION, 2, NativeAdmissionMessage.proof(signed)), 2).disconnect:
		return false
	return driver.receive(connection, _wire(ADMISSION, 3, NativeAdmissionMessage.acknowledge()), 3).seat == seat


func _wire(kind: NativeSessionFrame.Kind, sequence: int, payload: PackedByteArray) -> NativeSessionFrame:
	return NativeSessionFrame.read(NativeSessionFrame.pack(kind, 2, sequence, payload), NativeSessionFrame.channel(kind))
