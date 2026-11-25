extends GutTest


func test_transport_channels_and_signed_64bit_sequence_round_trip() -> void:
	var epoch := 9_223_372_036_854_775_807
	var id := 4_294_967_297
	var payload := PackedByteArray([44, 17, 0, 99])
	for kind: NativeSessionFrame.Kind in [NativeSessionFrame.Kind.ADMISSION, NativeSessionFrame.Kind.RELIABLE,
			NativeSessionFrame.Kind.SEQUENCED]:
		var channel := NativeSessionFrame.channel(kind)
		var bytes := NativeSessionFrame.pack(kind, epoch, id, payload)
		var result := NativeSessionFrame.read(bytes, channel)
		assert_not_null(result)
		if result != null:
			assert_eq(result.kind, kind)
			assert_eq(result.generation, epoch)
			assert_eq(result.sequence, id)
			assert_eq(result.payload, payload)
		assert_null(NativeSessionFrame.read(bytes, (channel + 1) % 3))


func test_decoder_rejects_bad_lengths_versions_and_unset_identifiers() -> void:
	var bytes := NativeSessionFrame.pack(NativeSessionFrame.Kind.ADMISSION, 1, 1, PackedByteArray([15]))
	assert_null(NativeSessionFrame.read(bytes.slice(0, -1), 0))
	var over := bytes.duplicate()
	over.append(22)
	assert_null(NativeSessionFrame.read(over, 0))
	var altered := bytes.duplicate()
	altered[0] = 99
	assert_null(NativeSessionFrame.read(altered, 0))
	altered = bytes.duplicate()
	altered[1] = 99
	assert_null(NativeSessionFrame.read(altered, 0))
	altered = bytes.duplicate()
	altered.encode_u16(2, 65535)
	assert_null(NativeSessionFrame.read(altered, 0))
	altered = bytes.duplicate()
	altered.encode_s64(4, 0)
	assert_null(NativeSessionFrame.read(altered, 0))
	altered = bytes.duplicate()
	altered.encode_s64(12, -1)
	assert_null(NativeSessionFrame.read(altered, 0))
	var oversized := PackedByteArray()
	oversized.resize(NativeSessionFrame.MAX_PAYLOAD + 1)
	assert_true(NativeSessionFrame.pack(NativeSessionFrame.Kind.RELIABLE, 1, 1, oversized).is_empty())


func test_bind_filter_keeps_wildcards_public_endpoints_and_dns_outside_the_adapter() -> void:
	for address: String in ["127.0.0.1", "192.168.5.40", "10.6.7.8", "172.16.0.1", "172.31.255.255",
			"::1", "fd00::ab"]:
		assert_true(NativeDtlsLink.private_ip(address), address)
	for address: String in ["", "*", "0.0.0.0", "::", "192.169.0.1", "172.15.0.9", "172.32.0.9",
			"example.com", "127.000.0.1", "2001:4860::1", "::ffff:127.0.0.1"]:
		assert_false(NativeDtlsLink.private_ip(address), address)
	var link := NativeDtlsLink.new()
	assert_eq(link.listen("0.0.0.0", 9100, null, null), ERR_INVALID_PARAMETER)
	assert_eq(link.dial("127.0.0.1", 9100, "paired.example", null), ERR_INVALID_PARAMETER)
	assert_false(link.is_open())
