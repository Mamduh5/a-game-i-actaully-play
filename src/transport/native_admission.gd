class_name NativeAdmission
extends RefCounted
## Original-host admission state for the active run generation. Association of a
## connection ID with a protected ENet peer belongs to the caller.

const MAX_GUESTS := 3
const MAX_ATTEMPT := 9223372036854775807

class Offer:
	var guest: CryptoKey
	var credential_hash: PackedByteArray
	var expires_at: int

class Seat:
	var guest: CryptoKey
	var controller: int
	var credential_hash: PackedByteArray
	var retry_hash: PackedByteArray

class Attempt:
	var seat: int
	var purpose: NativeJoinChallenge.Purpose
	var credential_hash: PackedByteArray
	var transcript: PackedByteArray
	var expires_at: int

class Admission:
	var seat: int
	var generation: int
	var replaced_controller: int
	var credential: PackedByteArray

var _host: PackedByteArray
var _run: PackedByteArray
var _generation: int
var _offers: Dictionary[int, Offer] = {}
var _seats: Dictionary[int, Seat] = {}
var _attempts: Dictionary[int, Attempt] = {}
var _last_attempt := 0
var _sealed := false
var _crypto := Crypto.new()


func _init(host: PackedByteArray, run: PackedByteArray, generation: int) -> void:
	_host = host
	_run = run
	_generation = generation


## The owner transfers this short-lived credential privately to the paired guest.
func offer(seat_id: int, guest: CryptoKey, now: int, expires_at: int) -> PackedByteArray:
	if (_sealed or seat_id < 1 or seat_id > MAX_GUESTS or _seats.has(seat_id) or guest == null
			or not guest.is_public_only() or now < 0 or expires_at <= now):
		return PackedByteArray()
	var credential := _crypto.generate_random_bytes(NativeJoinChallenge.DIGEST_SIZE)
	if credential.size() != NativeJoinChallenge.DIGEST_SIZE:
		return PackedByteArray()
	var invitation := Offer.new()
	invitation.guest = guest
	invitation.credential_hash = _hash(credential)
	invitation.expires_at = expires_at
	_offers[seat_id] = invitation
	return credential


func seal_new_seats() -> void:
	_sealed = true
	_offers.clear()


func begin(connection: int, generation: int, seat_id: int, purpose: NativeJoinChallenge.Purpose,
		credential: PackedByteArray, now: int, expires_at: int) -> PackedByteArray:
	if (connection <= 0 or generation <= 0 or generation != _generation or now < 0 or expires_at <= now
			or credential.size() != NativeJoinChallenge.DIGEST_SIZE or _controller_seat(connection) != 0
			or _last_attempt == MAX_ATTEMPT):
		return PackedByteArray()
	for pending: int in _attempts.keys():
		if now >= _attempts[pending].expires_at:
			_attempts.erase(pending)
	if _attempts.has(connection) or _attempts.size() >= NativeDtlsLink.MAX_PEERS:
		return PackedByteArray()
	var attempt := Attempt.new()
	attempt.seat = seat_id
	attempt.purpose = purpose
	attempt.credential_hash = _hash(credential)
	attempt.expires_at = expires_at
	var guest := _eligible_key(attempt, now)
	if guest == null:
		return PackedByteArray()
	_last_attempt += 1
	attempt.transcript = NativeJoinChallenge.issue(purpose, _generation, _last_attempt, _host, _run, guest)
	if not attempt.transcript.is_empty():
		_attempts[connection] = attempt
	return attempt.transcript.duplicate()


func complete(connection: int, proof: PackedByteArray, now: int) -> Admission:
	var attempt: Attempt = _attempts.get(connection)
	if attempt == null:
		return null
	_attempts.erase(connection)
	if now < 0 or now >= attempt.expires_at:
		return null
	var guest := _eligible_key(attempt, now)
	if guest == null or not NativeJoinChallenge.verify_challenge(attempt.transcript, proof, attempt.transcript, guest):
		return null
	var replacement := _crypto.generate_random_bytes(NativeJoinChallenge.DIGEST_SIZE)
	if replacement.size() != NativeJoinChallenge.DIGEST_SIZE:
		return null
	var seat: Seat = _seats.get(attempt.seat)
	if seat == null:
		seat = Seat.new()
		seat.guest = guest
		_seats[attempt.seat] = seat
		_offers.erase(attempt.seat)
	else:
		seat.retry_hash = attempt.credential_hash
	var admission := Admission.new()
	admission.seat = attempt.seat
	admission.generation = _generation
	admission.replaced_controller = seat.controller
	admission.credential = replacement
	seat.controller = connection
	seat.credential_hash = _hash(replacement)
	for pending: int in _attempts.keys():
		if _attempts[pending].seat == attempt.seat:
			_attempts.erase(pending)
	return admission


## Confirm receipt of the rotated credential after the authenticated acceptance.
func acknowledge(connection: int, generation: int) -> bool:
	var seat_id := _controller_seat(connection)
	if seat_id == 0 or generation != _generation:
		return false
	_seats[seat_id].retry_hash.clear()
	return true


func drop_connection(connection: int) -> void:
	_attempts.erase(connection)
	var seat_id := _controller_seat(connection)
	if seat_id > 0:
		_seats[seat_id].controller = 0


func owns(connection: int, generation: int, seat_id: int) -> bool:
	var seat: Seat = _seats.get(seat_id)
	return connection > 0 and generation == _generation and seat != null and seat.controller == connection


func _eligible_key(attempt: Attempt, now: int) -> CryptoKey:
	if attempt.purpose == NativeJoinChallenge.Purpose.INITIAL:
		var invitation: Offer = _offers.get(attempt.seat)
		if (invitation != null and now < invitation.expires_at
				and _crypto.constant_time_compare(invitation.credential_hash, attempt.credential_hash)):
			return invitation.guest
	elif attempt.purpose == NativeJoinChallenge.Purpose.RECLAIM:
		var seat: Seat = _seats.get(attempt.seat)
		if seat == null:
			return null
		var retry := not seat.retry_hash.is_empty() and _crypto.constant_time_compare(seat.retry_hash, attempt.credential_hash)
		if retry or (seat.controller == 0 and _crypto.constant_time_compare(seat.credential_hash, attempt.credential_hash)):
			return seat.guest
	return null


func _controller_seat(connection: int) -> int:
	if connection <= 0:
		return 0
	for seat_id: int in _seats:
		if _seats[seat_id].controller == connection:
			return seat_id
	return 0


static func _hash(credential: PackedByteArray) -> PackedByteArray:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(credential)
	return hash.finish()
