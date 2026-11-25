extends GutTest


func test_proof_is_bound_to_paired_guest_attempt_run_host_purpose_and_epoch() -> void:
	var crypto := Crypto.new()
	var signing_key := crypto.generate_rsa(2048)
	var stranger := crypto.generate_rsa(2048)
	var paired_key := CryptoKey.new()
	assert_eq(paired_key.load_from_string(signing_key.save_to_string(true), true), OK)
	var host := "paired-certificate".sha256_buffer()
	var run := "prepared-run".sha256_buffer()
	var purpose := NativeJoinChallenge.Purpose.INITIAL
	var issued := NativeJoinChallenge.issue(purpose, 2, 9, host, run, paired_key)
	var fresh := NativeJoinChallenge.issue(purpose, 2, 9, host, run, paired_key)
	assert_eq(issued.size(), NativeJoinChallenge.SIZE)
	assert_ne(issued, fresh)
	var proof := NativeJoinChallenge.sign_challenge(issued, purpose, 2, 9, host, run, signing_key)
	assert_eq(proof.size(), 256)
	assert_true(NativeJoinChallenge.verify_challenge(issued, proof, issued, paired_key))
	assert_false(NativeJoinChallenge.verify_challenge(fresh, proof, fresh, paired_key))
	assert_false(NativeJoinChallenge.verify_challenge(issued, proof, fresh, paired_key))
	assert_false(NativeJoinChallenge.verify_challenge(issued, proof, issued, stranger))
	assert_false(NativeJoinChallenge.verify_challenge(issued, proof, issued, null))
	assert_true(NativeJoinChallenge.sign_challenge(issued, purpose, 3, 9, host, run, signing_key).is_empty())
	assert_true(NativeJoinChallenge.sign_challenge(issued, purpose, 2, 10, host, run, signing_key).is_empty())
	assert_true(NativeJoinChallenge.sign_challenge(issued, purpose, 2, 9, run, host, signing_key).is_empty())
	assert_true(NativeJoinChallenge.sign_challenge(issued, purpose, 2, 9, host, run, paired_key).is_empty())
	assert_true(NativeJoinChallenge.sign_challenge(issued, NativeJoinChallenge.Purpose.RECLAIM,
		2, 9, host, run, signing_key).is_empty())
	var malformed := issued.duplicate()
	malformed[0] = 99
	assert_false(NativeJoinChallenge.verify_challenge(malformed, proof, malformed, paired_key))
	assert_false(NativeJoinChallenge.verify_challenge(issued.slice(1), proof, issued, paired_key))
