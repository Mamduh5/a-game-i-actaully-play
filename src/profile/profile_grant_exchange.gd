class_name ProfileGrantExchange
extends RefCounted
## Reliable messages exchanged after native peer admission. The route selects
## original-run trust from the local profile. It does not authorize an award.

enum Kind { DELIVERY = 1, ACKNOWLEDGEMENT = 2 }

const TAG := 0x47
const VERSION := 1
const HEADER := 5

class Result:
	var receipt := ProfileStore.Receipt.new()
	var reply: PackedByteArray

var _store: ProfileStore
var _key: CryptoKey


func _init(store: ProfileStore, local_key: CryptoKey) -> void:
	_store = store
	_key = local_key


## Only a durable outstanding envelope can originate a delivery. The
## caller supplies the originally paired run and the intended peer profile.
func delivery(run: String, recipient: String, grant_key: String) -> PackedByteArray:
	if _store == null:
		return PackedByteArray()
	var bound := _store.grant_binding(run, recipient)
	var queued := _store.grant(grant_key)
	if (bound == null or not _holds(bound.issuer) or queued.get("recipient") != recipient
			or not queued.get("body") is PackedByteArray):
		return PackedByteArray()
	var grant := ProfileGrant.open_authorization(queued.body, bound)
	if grant == null or grant.key != grant_key or grant.digest != queued.digest:
		return PackedByteArray()
	return _pack(Kind.DELIVERY, bound, queued.body)


static func recognizes(frame: NativeSessionFrame) -> bool:
	return frame != null and not frame.payload.is_empty() and frame.payload[0] == TAG


func receive(frame: NativeSessionFrame) -> Result:
	var result := Result.new()
	result.receipt.status = ProfileStore.CommitResult.INVALID
	if _store == null or not recognizes(frame) or frame.kind != NativeSessionFrame.Kind.RELIABLE:
		return result
	var packet := frame.payload
	if packet.size() <= HEADER or packet.size() > NativeSessionFrame.MAX_PAYLOAD or packet[1] != VERSION:
		return result
	var route_end: int = HEADER + packet[3] + packet[4]
	if (packet.size() <= route_end or packet.size() - route_end > ProfileGrant.MAX_BYTES
			or packet[2] not in [Kind.DELIVERY, Kind.ACKNOWLEDGEMENT]):
		return result
	var run_bytes := packet.slice(HEADER, HEADER + packet[3])
	var recipient_bytes := packet.slice(HEADER + packet[3], route_end)
	var run := run_bytes.get_string_from_ascii()
	var recipient := recipient_bytes.get_string_from_ascii()
	if run.to_ascii_buffer() != run_bytes or recipient.to_ascii_buffer() != recipient_bytes:
		return result
	if packet[2] == Kind.DELIVERY and recipient != _store.identity():
		return result
	var binding := _store.grant_binding(run, recipient)
	if binding == null:
		return result
	var body := packet.slice(route_end)
	if packet[2] == Kind.DELIVERY:
		var applied := ProfileGrantSettlement.apply(_store, binding, _key, body)
		result.receipt = applied.receipt
		result.reply = _pack(Kind.ACKNOWLEDGEMENT, binding, applied.acknowledgement)
	elif _holds(binding.issuer):
		result.receipt = ProfileGrantSettlement.acknowledge(_store, binding, body)
	return result


func _holds(public_key: CryptoKey) -> bool:
	return (_key != null and not _key.is_public_only()
		and ProfileGrant.fingerprint(_key) == ProfileGrant.fingerprint(public_key))


static func _pack(kind: Kind, binding: ProfileGrant.Binding, body: PackedByteArray) -> PackedByteArray:
	if body.is_empty() or body.size() > ProfileGrant.MAX_BYTES:
		return PackedByteArray()
	var run := binding.run.to_ascii_buffer()
	var recipient := binding.recipient.to_ascii_buffer()
	return PackedByteArray([TAG, VERSION, kind, run.size(), recipient.size()]) + run + recipient + body
