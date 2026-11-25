class_name NativeJoinChallenge
extends RefCounted
## Versioned transcript for a paired guest. The admission owner supplies the
## expected context and consumes the challenged attempt before granting control.

enum Purpose { INITIAL = 1, RECLAIM = 2 }

const VERSION := 1
const DIGEST_SIZE := 32
const MAX_SIGNATURE := 512
const GENERATION_OFFSET := 2
const ATTEMPT_OFFSET := 10
const HOST_OFFSET := 18
const RUN_OFFSET := HOST_OFFSET + DIGEST_SIZE
const GUEST_OFFSET := RUN_OFFSET + DIGEST_SIZE
const NONCE_OFFSET := GUEST_OFFSET + DIGEST_SIZE
const SIZE := NONCE_OFFSET + DIGEST_SIZE
const SIGNING_DOMAIN := "AGIP/native-join/v1"


static func issue(purpose: Purpose, generation: int, attempt: int, host: PackedByteArray,
		run: PackedByteArray, guest: CryptoKey) -> PackedByteArray:
	var guest_id := key_fingerprint(guest)
	if (not _valid_purpose(purpose) or generation <= 0 or attempt <= 0 or host.size() != DIGEST_SIZE
			or run.size() != DIGEST_SIZE or guest_id.size() != DIGEST_SIZE):
		return PackedByteArray()
	var nonce := Crypto.new().generate_random_bytes(DIGEST_SIZE)
	if nonce.size() != DIGEST_SIZE:
		return PackedByteArray()
	var bytes := PackedByteArray()
	bytes.resize(HOST_OFFSET)
	bytes[0] = VERSION
	bytes[1] = purpose
	bytes.encode_s64(GENERATION_OFFSET, generation)
	bytes.encode_s64(ATTEMPT_OFFSET, attempt)
	bytes.append_array(host)
	bytes.append_array(run)
	bytes.append_array(guest_id)
	bytes.append_array(nonce)
	return bytes


static func sign_challenge(bytes: PackedByteArray, purpose: Purpose, generation: int, attempt: int,
		host: PackedByteArray, run: PackedByteArray, guest_key: CryptoKey) -> PackedByteArray:
	if guest_key == null or guest_key.is_public_only():
		return PackedByteArray()
	if not matches(bytes, purpose, generation, attempt, host, run, guest_key):
		return PackedByteArray()
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, _digest(bytes), guest_key)
	return signature if signature.size() <= MAX_SIGNATURE else PackedByteArray()


static func verify_challenge(bytes: PackedByteArray, proof: PackedByteArray, expected: PackedByteArray,
		guest: CryptoKey) -> bool:
	if (not _valid_frame(expected) or bytes != expected or proof.is_empty() or proof.size() > MAX_SIGNATURE
			or guest == null or bytes.slice(GUEST_OFFSET, NONCE_OFFSET) != key_fingerprint(guest)):
		return false
	return Crypto.new().verify(HashingContext.HASH_SHA256, _digest(bytes), proof, guest)


static func matches(bytes: PackedByteArray, purpose: Purpose, generation: int, attempt: int,
		host: PackedByteArray, run: PackedByteArray, guest: CryptoKey) -> bool:
	return (_valid_frame(bytes) and bytes[1] == purpose and bytes.decode_s64(GENERATION_OFFSET) == generation
		and bytes.decode_s64(ATTEMPT_OFFSET) == attempt and bytes.slice(HOST_OFFSET, RUN_OFFSET) == host
		and bytes.slice(RUN_OFFSET, GUEST_OFFSET) == run
		and bytes.slice(GUEST_OFFSET, NONCE_OFFSET) == key_fingerprint(guest))


static func key_fingerprint(key: CryptoKey) -> PackedByteArray:
	if key == null:
		return PackedByteArray()
	var pem := key.save_to_string(true)
	return pem.sha256_buffer() if not pem.is_empty() else PackedByteArray()


static func _valid_frame(bytes: PackedByteArray) -> bool:
	return (bytes.size() == SIZE and bytes[0] == VERSION and _valid_purpose(bytes[1])
		and bytes.decode_s64(GENERATION_OFFSET) > 0 and bytes.decode_s64(ATTEMPT_OFFSET) > 0)


static func _valid_purpose(value: int) -> bool:
	return value == Purpose.INITIAL or value == Purpose.RECLAIM


static func _digest(bytes: PackedByteArray) -> PackedByteArray:
	var input := SIGNING_DOMAIN.to_utf8_buffer()
	input.append_array(bytes)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(input)
	return hash.finish()
