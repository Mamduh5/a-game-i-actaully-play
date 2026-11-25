extends GutTest


func test_enroll_and_reopen_only_the_authenticated_name_and_certificate() -> void:
	var directory := DirAccess.create_temp("agip-host-pin")
	assert_not_null(directory)
	var root := directory.get_current_dir()
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var certificate := crypto.generate_self_signed_certificate(key, "CN=fixture.local", "20200101000000", "20350101000000")
	assert_eq(certificate.save(root.path_join("original.crt")), OK)
	var pem := FileAccess.get_file_as_bytes(root.path_join("original.crt"))
	var digest := NativeHostPin.fingerprint(pem)
	var wrong := digest.duplicate()
	wrong[0] ^= 1
	assert_eq(NativeHostPin.enroll(root, pem, "fixture.local", wrong), ERR_INVALID_DATA)
	assert_eq(NativeHostPin.enroll(root, pem, "../fixture.local", digest), ERR_INVALID_DATA)
	assert_eq(NativeHostPin.enroll(root, pem + pem, "fixture.local", NativeHostPin.fingerprint(pem + pem)), ERR_INVALID_DATA)
	assert_eq(NativeHostPin.enroll(root, pem, "fixture.local", digest), OK)
	assert_eq(NativeHostPin.enroll(root, pem, "fixture.local", digest), OK)
	var retained := NativeHostPin.reopen(root, "fixture.local", digest)
	assert_not_null(retained)
	assert_eq(retained.issuer, digest)
	assert_not_null(retained.certificate())
	assert_null(NativeHostPin.reopen(root, "other.local", digest))
	assert_null(NativeHostPin.reopen(root, "fixture.local", wrong))
	for filename: String in directory.get_files():
		if filename.ends_with(".pin"):
			var file := FileAccess.open(root.path_join(filename), FileAccess.WRITE)
			file.store_8(1)
			file.close()
	assert_null(NativeHostPin.reopen(root, "fixture.local", digest))
	assert_eq(NativeHostPin.enroll(root, pem, "fixture.local", digest), ERR_FILE_CORRUPT)
