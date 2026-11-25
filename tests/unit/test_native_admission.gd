extends GutTest

const INITIAL := NativeJoinChallenge.Purpose.INITIAL
const RECLAIM := NativeJoinChallenge.Purpose.RECLAIM

var _host := "fixture-host".sha256_buffer()
var _run := "fixture-run".sha256_buffer()
var _key: CryptoKey
var _public_key: CryptoKey
var _admission: NativeAdmission


func before_all() -> void:
	_key = Crypto.new().generate_rsa(2048)
	_public_key = CryptoKey.new()
	assert_eq(_public_key.load_from_string(_key.save_to_string(true), true), OK)


func before_each() -> void:
	_admission = NativeAdmission.new(_host, _run, 2)


func test_invite_is_single_use_and_requires_current_key_proof_before_admission() -> void:
	var token := _admission.offer(1, _public_key, 0, 20)
	assert_eq(token.size(), 32)
	assert_true(_admission.begin(10, 1, 1, INITIAL, token, 1, 5).is_empty())
	assert_true(_admission.begin(10, 2, 2, INITIAL, token, 1, 5).is_empty())
	assert_true(_admission.begin(10, 2, 1, INITIAL, token, 20, 21).is_empty())
	var first := _admission.begin(10, 2, 1, INITIAL, token, 1, 5)
	assert_false(_admission.owns(10, 2, 1))
	assert_null(_admission.complete(10, _sign(first, INITIAL), 5))
	var second := _admission.begin(11, 2, 1, INITIAL, token, 5, 10)
	assert_null(_admission.complete(11, _sign(first, INITIAL), 6))
	var third := _admission.begin(12, 2, 1, INITIAL, token, 7, 10)
	var competing := _admission.begin(13, 2, 1, INITIAL, token, 7, 10)
	assert_ne(second, third)
	assert_not_null(_admission.complete(12, _sign(third, INITIAL), 8))
	assert_true(_admission.owns(12, 2, 1))
	assert_false(_admission.owns(12, 1, 1))
	assert_null(_admission.complete(13, _sign(competing, INITIAL), 8))
	assert_true(_admission.begin(14, 2, 1, INITIAL, token, 8, 10).is_empty())
	_admission.seal_new_seats()
	assert_true(_admission.offer(2, _public_key, 8, 10).is_empty())


func test_reclaim_rotates_fences_and_retries_a_lost_acceptance_through_fresh_proof() -> void:
	var token := _admission.offer(1, _public_key, 0, 30)
	var first := _admission.begin(10, 2, 1, INITIAL, token, 1, 10)
	var initialized := _admission.complete(10, _sign(first, INITIAL), 2)
	assert_not_null(initialized)
	assert_true(_admission.begin(11, 2, 1, RECLAIM, initialized.credential, 3, 13).is_empty())
	_admission.seal_new_seats()
	_admission.drop_connection(10)
	var reclaim := _admission.begin(11, 2, 1, RECLAIM, initialized.credential, 4, 14)
	var lost := _admission.complete(11, _sign(reclaim, RECLAIM), 5)
	assert_not_null(lost)
	assert_ne(lost.credential, initialized.credential)
	assert_true(_admission.owns(11, 2, 1))
	var retry := _admission.begin(12, 2, 1, RECLAIM, initialized.credential, 6, 16)
	var competing := _admission.begin(13, 2, 1, RECLAIM, initialized.credential, 6, 16)
	assert_ne(retry, reclaim)
	var replaced := _admission.complete(12, _sign(retry, RECLAIM), 7)
	assert_not_null(replaced)
	assert_eq(replaced.replaced_controller, 11)
	assert_false(_admission.owns(11, 2, 1))
	assert_null(_admission.complete(13, _sign(competing, RECLAIM), 7))
	assert_true(_admission.acknowledge(12, 2))
	_admission.drop_connection(11)
	assert_true(_admission.owns(12, 2, 1))
	_admission.drop_connection(12)
	assert_true(_admission.begin(14, 2, 1, RECLAIM, initialized.credential, 8, 18).is_empty())
	assert_true(_admission.begin(14, 2, 1, RECLAIM, lost.credential, 8, 18).is_empty())
	var next := _admission.begin(14, 2, 1, RECLAIM, replaced.credential, 8, 18)
	assert_not_null(_admission.complete(14, _sign(next, RECLAIM), 9))


func _sign(challenge: PackedByteArray, purpose: NativeJoinChallenge.Purpose) -> PackedByteArray:
	var attempt := challenge.decode_s64(NativeJoinChallenge.ATTEMPT_OFFSET)
	return NativeJoinChallenge.sign_challenge(challenge, purpose, 2, attempt, _host, _run, _key)
