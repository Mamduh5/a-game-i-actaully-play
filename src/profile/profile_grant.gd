class_name ProfileGrant
extends RefCounted
## A versioned award authorized by the original issuer. The caller supplies
## the retained pairing for the original run, independent of transport roles.

enum Kind { CURRENCY, DISCOVERY }

const VERSION := 1
const MAX_BYTES := 3600
const MAX_BODY := 3072
const MAX_SIGNATURE := 512
const HEADER := 3
const GRANT_DOMAIN := "AGIP/profile-grant/v1"
const ACK_DOMAIN := "AGIP/profile-grant-ack/v1"

class Binding:
	var run: String
	var rules: String
	var catalog: String
	var recipient: String
	var issuer: CryptoKey
	var recipient_key: CryptoKey

	func fields() -> Array[String]:
		return [run, rules, catalog, recipient, ProfileGrant.fingerprint(issuer),
			ProfileGrant.fingerprint(recipient_key)]

	func is_valid() -> bool:
		return (ProfileGrant.valid_field(run) and ProfileGrant.valid_field(rules)
			and ProfileGrant.valid_field(catalog) and ProfileStore.valid_identity(recipient)
			and not ProfileGrant.fingerprint(issuer).is_empty()
			and not ProfileGrant.fingerprint(recipient_key).is_empty())

var occurrence: String
var kind: Kind
var award: String
var amount: Quantity
var key: String
var digest: String
var _binding: Array[String]


static func sign_authorization(binding: Binding, signer: CryptoKey, source: String, award_kind: Kind,
		award_id: String, value: Quantity) -> PackedByteArray:
	if (binding == null or not binding.is_valid() or fingerprint(signer) != fingerprint(binding.issuer)
			or not valid_field(source) or not _valid_award(award_kind, award_id, value)):
		return PackedByteArray()
	var body: Array = binding.fields()
	body.append_array([source, str(award_kind), award_id, QuantityCodec.encode(value).hex_encode()])
	return _sign(GRANT_DOMAIN, body, signer)


static func open_authorization(bytes: PackedByteArray, binding: Binding) -> ProfileGrant:
	if binding == null or not binding.is_valid():
		return null
	var contents := _open(GRANT_DOMAIN, bytes, binding.issuer)
	var expected := binding.fields()
	if contents.size() != 10 or contents.slice(0, 6) != expected:
		return null
	var source: String = contents[6]
	var encoded_kind: String = contents[7]
	var award_id: String = contents[8]
	var encoded_amount: String = contents[9]
	if encoded_kind not in ["0", "1"] or not valid_field(source):
		return null
	var award_kind := encoded_kind.to_int() as Kind
	var amount_bytes := encoded_amount.hex_decode()
	if amount_bytes.hex_encode() != encoded_amount:
		return null
	var value := QuantityCodec.decode(amount_bytes)
	if not _valid_award(award_kind, award_id, value) or QuantityCodec.encode(value) != amount_bytes:
		return null
	var opened := ProfileGrant.new()
	opened._binding = expected
	opened.occurrence = source
	opened.kind = award_kind
	opened.award = award_id
	opened.amount = value
	opened.key = _identity([expected[4], expected[0], source, encoded_kind, award_id, expected[3], expected[5]])
	opened.digest = ProfileMutation.sha256(bytes)
	return opened


func issue_id() -> String:
	return "issue/" + _identity([_binding[4], _binding[0], occurrence, str(kind), award])


func application(discovery_already_recorded: bool = false) -> ProfileMutation:
	var mutation := ProfileMutation.new()
	mutation.id = "apply/" + key
	mutation.rules = _binding[1]
	mutation.catalog = _binding[2]
	mutation.claims.append("grant-body/" + digest)
	if kind == Kind.DISCOVERY:
		if not discovery_already_recorded:
			mutation.claims.append("discovery/" + award)
			mutation.deltas["discovery/" + award] = amount
	else:
		mutation.deltas[award] = amount
	return mutation


func matches_application(receipt_digest: String) -> bool:
	return (receipt_digest == application().record().sha256_text()
		or (kind == Kind.DISCOVERY and receipt_digest == application(true).record().sha256_text()))


func sign_acknowledgement(receipt: ProfileStore.Receipt, signer: CryptoKey) -> PackedByteArray:
	if (receipt == null or receipt.status not in [ProfileStore.CommitResult.COMMITTED, ProfileStore.CommitResult.DUPLICATE]
			or receipt.id != "apply/" + key or not matches_application(receipt.digest)
			or fingerprint(signer) != _binding[5]):
		return PackedByteArray()
	var body: Array = _binding.duplicate()
	body.append_array([key, digest, receipt.digest])
	return _sign(ACK_DOMAIN, body, signer)


static func open_acknowledgement(bytes: PackedByteArray, binding: Binding) -> Array[String]:
	if binding == null or not binding.is_valid():
		return []
	var contents := _open(ACK_DOMAIN, bytes, binding.recipient_key)
	if contents.size() != 9 or contents.slice(0, 6) != binding.fields():
		return []
	var facts := contents.slice(6)
	for value: String in facts:
		if not ProfileMutation.valid_digest(value):
			return []
	return facts


static func fingerprint(key_value: CryptoKey) -> String:
	return NativeJoinChallenge.key_fingerprint(key_value).hex_encode()


static func valid_field(value: String) -> bool:
	return value.length() <= 96 and ProfileMutation.valid_id(value)


static func _valid_award(award_kind: Kind, award_id: String, value: Quantity) -> bool:
	return (award_kind in Kind.values() and valid_field(award_id) and value != null and value.sign_value > 0
		and (award_kind != Kind.DISCOVERY or value.compare(Quantity.from_count(1)) == 0)
		and (award_kind != Kind.CURRENCY or award_id.begins_with("currency/")))


static func _identity(fields: Array) -> String:
	return JSON.stringify([VERSION, fields]).sha256_text()


static func _sign(domain: String, fields: Array, key_value: CryptoKey) -> PackedByteArray:
	if key_value == null or key_value.is_public_only():
		return PackedByteArray()
	var payload := JSON.stringify(fields).to_utf8_buffer()
	if payload.is_empty() or payload.size() > MAX_BODY:
		return PackedByteArray()
	var signed := Crypto.new().sign(HashingContext.HASH_SHA256, _hash(domain, payload), key_value)
	if signed.is_empty() or signed.size() > MAX_SIGNATURE:
		return PackedByteArray()
	var bytes := PackedByteArray([VERSION, 0, 0])
	bytes.encode_u16(1, payload.size())
	bytes.append_array(payload)
	bytes.append_array(signed)
	return bytes


static func _open(domain: String, bytes: PackedByteArray, key_value: CryptoKey) -> Array[String]:
	if bytes.size() <= HEADER or bytes.size() > MAX_BYTES or bytes[0] != VERSION or key_value == null:
		return []
	var length := bytes.decode_u16(1)
	var signature_length := bytes.size() - HEADER - length
	if length <= 0 or length > MAX_BODY or signature_length <= 0 or signature_length > MAX_SIGNATURE:
		return []
	var payload := bytes.slice(HEADER, HEADER + length)
	var signature := bytes.slice(HEADER + length)
	if not Crypto.new().verify(HashingContext.HASH_SHA256, _hash(domain, payload), signature, key_value):
		return []
	var serialized := payload.get_string_from_utf8()
	var fields: Variant = JSON.parse_string(serialized)
	if not fields is Array or JSON.stringify(fields).to_utf8_buffer() != payload:
		return []
	var checked: Array[String] = []
	for entry: Variant in fields:
		if not entry is String:
			return []
		checked.append(entry)
	return checked


static func _hash(domain: String, bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update((domain + "\n").to_utf8_buffer())
	context.update(bytes)
	return context.finish()
