class_name ProfileMutation
extends RefCounted
## A trusted progression request. The caller owns authorization and stable IDs.

const MAX_ID_BYTES := 512
const MAX_BYTES := 1024 * 1024
const MAX_ITEMS := 64

class Frontier:
	var run: String
	var epoch: int
	var tick: int
	var image: PackedByteArray

class Grant:
	var key: String
	var recipient: String
	var envelope: PackedByteArray

var id: String
var rules: String
var catalog: String
var deltas: Dictionary[String, Quantity] = {}
var claims: Array[String] = []
var grants: Array[Grant] = []
var acknowledgements: Dictionary[String, String] = {}
var frontier: Frontier


## Preserve exact deltas and payload digests for replay and backup validation.
func record() -> String:
	if not valid_id(id) or not valid_id(rules) or not valid_id(catalog):
		return ""
	if deltas.size() > MAX_ITEMS or claims.size() > MAX_ITEMS or grants.size() > MAX_ITEMS or acknowledgements.size() > MAX_ITEMS:
		return ""
	var amounts := {}
	for account: String in deltas:
		var delta := deltas[account]
		if not valid_id(account) or delta == null:
			return ""
		amounts[account] = QuantityCodec.encode(delta).hex_encode()
	var unique_claims := {}
	for claim: String in claims:
		if not valid_id(claim) or unique_claims.has(claim):
			return ""
		unique_claims[claim] = true
	var grant_digests := {}
	var payload_size := 0
	for grant: Grant in grants:
		if (grant == null or not valid_id(grant.key) or not valid_id(grant.recipient)
				or grant.envelope.is_empty() or grant_digests.has(grant.key) or acknowledgements.has(grant.key)):
			return ""
		payload_size += grant.envelope.size()
		if payload_size > MAX_BYTES:
			return ""
		grant_digests[grant.key] = [grant.recipient, sha256(grant.envelope)]
	for key: String in acknowledgements:
		if not valid_id(key) or not valid_digest(acknowledgements[key]):
			return ""
	var saved: Array = []
	if frontier != null:
		if (not valid_id(frontier.run) or frontier.epoch <= 0 or frontier.tick < 0
				or frontier.tick > RunAuthority.MAX_TICK or frontier.image.is_empty()
				or frontier.image.size() > MAX_BYTES - payload_size):
			return ""
		saved = [frontier.run, str(frontier.epoch), str(frontier.tick), sha256(frontier.image)]
	return JSON.stringify([1, id, rules, catalog, amounts, unique_claims, grant_digests, acknowledgements, saved], "", true)


static func valid_id(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_ID_BYTES:
		return false
	for byte: int in value.to_utf8_buffer():
		if byte < 33 or byte > 126:
			return false
	return true


static func valid_digest(value: String) -> bool:
	if value.length() != 64:
		return false
	for byte: int in value.to_utf8_buffer():
		if not ((byte >= 48 and byte <= 57) or (byte >= 97 and byte <= 102)):
			return false
	return true


static func sha256(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()
