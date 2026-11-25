class_name NativeHostPin
extends RefCounted
## Durable public pairing data enrolled from an authenticated local transfer.
## The caller retains the selected name/fingerprint independently of discovery.

const VERSION := 1
const HEADER := 5
const MAX_NAME := 253
const MAX_CERTIFICATE := 16384
const BEGIN := "-----BEGIN CERTIFICATE-----"
const END := "-----END CERTIFICATE-----"

var name: String:
	get: return _name
var issuer: PackedByteArray:
	get: return _fingerprint.duplicate()

var _name: String
var _fingerprint: PackedByteArray
var _pem: PackedByteArray


static func enroll(root: String, certificate: PackedByteArray, expected_name: String,
		expected_fingerprint: PackedByteArray) -> Error:
	var path := _path(root, expected_name, expected_fingerprint)
	if path.is_empty() or _parse_certificate(certificate, expected_fingerprint) == null:
		return ERR_INVALID_DATA
	if FileAccess.file_exists(path):
		return OK if reopen(root, expected_name, expected_fingerprint) != null else ERR_FILE_CORRUPT
	var nonce := Crypto.new().generate_random_bytes(16)
	if nonce.size() != 16:
		return ERR_CANT_CREATE
	var staged := path + "." + nonce.hex_encode() + ".tmp"
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var image := PackedByteArray([VERSION, 0, 0, 0, 0])
	image.encode_u16(1, expected_name.length())
	image.encode_u16(3, certificate.size())
	image.append_array(expected_name.to_ascii_buffer())
	image.append_array(certificate)
	var stored := file.store_buffer(image)
	file.flush()
	var code := file.get_error()
	file.close()
	if stored and code == OK:
		# Concurrent valid enrollments for the same path have identical contents.
		code = DirAccess.rename_absolute(staged, path)
		if code == OK:
			return OK
	DirAccess.remove_absolute(staged)
	return code if code != OK else ERR_FILE_CANT_WRITE


static func reopen(root: String, expected_name: String, expected_fingerprint: PackedByteArray) -> NativeHostPin:
	var path := _path(root, expected_name, expected_fingerprint)
	if path.is_empty():
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var size := file.get_length()
	if size < HEADER or size > HEADER + MAX_NAME + MAX_CERTIFICATE:
		return null
	var image := file.get_buffer(size)
	if image.size() != size or image[0] != VERSION:
		return null
	var name_size := image.decode_u16(1)
	var pem_size := image.decode_u16(3)
	if name_size != expected_name.length() or pem_size == 0 or size != HEADER + name_size + pem_size:
		return null
	if image.slice(HEADER, HEADER + name_size) != expected_name.to_ascii_buffer():
		return null
	var pem := image.slice(HEADER + name_size)
	if _parse_certificate(pem, expected_fingerprint) == null:
		return null
	var pin := NativeHostPin.new()
	pin._name = expected_name
	pin._fingerprint = expected_fingerprint.duplicate()
	pin._pem = pem
	return pin


func certificate() -> X509Certificate:
	return _parse_certificate(_pem, _fingerprint)


static func fingerprint(pem: PackedByteArray) -> PackedByteArray:
	if pem.is_empty() or pem.size() > MAX_CERTIFICATE:
		return PackedByteArray()
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(pem)
	return hash.finish()


static func _parse_certificate(pem: PackedByteArray, expected_fingerprint: PackedByteArray) -> X509Certificate:
	if expected_fingerprint.size() != 32 or fingerprint(pem) != expected_fingerprint:
		return null
	var text := pem.get_string_from_ascii().strip_edges()
	if not text.begins_with(BEGIN) or not text.ends_with(END) or text.count(BEGIN) != 1 or text.count(END) != 1:
		return null
	var cert := X509Certificate.new()
	return cert if cert.load_from_string(text + "\n") == OK else null


static func _path(root: String, expected_name: String, expected_fingerprint: PackedByteArray) -> String:
	if not root.is_absolute_path() or expected_fingerprint.size() != 32 or expected_name.length() > MAX_NAME:
		return ""
	for label: String in expected_name.split(".", true):
		if label.is_empty() or label.length() > 63 or label.begins_with("-") or label.ends_with("-"):
			return ""
		for index: int in label.length():
			var code := label.unicode_at(index)
			if code != 45 and not (48 <= code and code <= 57) and not (97 <= code and code <= 122):
				return ""
	return root.path_join("%s-%s.pin" % [expected_fingerprint.hex_encode(), expected_name.sha256_text()])
