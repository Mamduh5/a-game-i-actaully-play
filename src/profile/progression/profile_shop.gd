class_name ProfileShop
extends RefCounted
## Permanent progression purchases for one opened local profile. The offer
## table is supplied by the approved catalog owner and pinned for this shop.

const COMMON := "currency/common"
const RARE := "currency/rare"
const PROTOTYPE_STAT_CAP := 2500
const UPGRADE_STATS := [&"maximum_hp", &"base_damage", &"physical_defense", &"magical_defense", &"movement",
	&"automatic_attack_frequency", &"manual_cooldown_recovery"]

class Offer:
	var id: StringName
	var rank: int
	var account: String
	var price: Quantity
	var basis_points: int

	func copy() -> Offer:
		var result := Offer.new()
		result.id = id
		result.rank = rank
		result.account = account
		result.price = price
		result.basis_points = basis_points
		return result

var _rules: String
var _catalog: DefinitionCatalog
var _store: ProfileStore
var _facts: ProfileProgression
var _run: RunAuthority
var _offers: Dictionary[String, Offer] = {}


static func open(store: ProfileStore, catalog: DefinitionCatalog, rules: String,
		offers: Array[Offer], active_run: RunAuthority = null) -> ProfileShop:
	var facts := ProfileProgression.open(store, catalog)
	if facts == null or not ProfileMutation.valid_id(rules) or not ProfileMutation.valid_id(String(catalog.revision)):
		return null
	var result := ProfileShop.new()
	result._store = store
	result._catalog = catalog
	result._facts = facts
	result._rules = rules
	result._run = active_run
	for offer: Offer in offers:
		if not result._valid_offer(offer):
			return null
		var key := _key(offer.id, offer.rank)
		if result._offers.has(key):
			return null
		result._offers[key] = offer.copy()
	for offer: Offer in result._offers.values():
		if offer.rank <= 1:
			continue
		var previous: Offer = result._offers.get(_key(offer.id, offer.rank - 1))
		if (previous == null or previous.basis_points != offer.basis_points
				or (previous.account == offer.account and offer.price.compare(previous.price) <= 0)):
			return null
	return result


func quote(id: StringName, rank: int) -> Offer:
	var offer: Offer = _offers.get(_key(id, rank))
	return offer.copy() if offer != null and _facts.same_profile() else null


## Repeating a request uses the original operation ID and exact mutation.
## The included one-time claim fences a different request for the same item.
func buy(request: String, id: StringName, rank: int = 0) -> ProfileStore.Receipt:
	var operation := "progression/purchase/%s" % request
	var offer: Offer = _offers.get(_key(id, rank))
	if not _facts.same_profile():
		return _receipt(ProfileStore.CommitResult.UNAVAILABLE, operation)
	if offer == null or not ProfileMutation.valid_id(request) or not ProfileMutation.valid_id(operation):
		return _receipt(ProfileStore.CommitResult.INVALID, operation)
	var purchase := ProfileMutation.new()
	purchase.id = operation
	purchase.rules = _rules
	purchase.catalog = String(_catalog.revision)
	purchase.deltas[offer.account] = offer.price.negated()
	purchase.claims.append(_facts.ownership_claim(id) if rank == 0 else _key(id, rank))
	var prior := _store.lookup(operation)
	# A live run can still have qualified earnings newer than the durable balance.
	if _run != null and prior.status != ProfileStore.CommitResult.COMMITTED:
		if not _run.flush_ordinary_currency(_store.identity()):
			return _receipt(ProfileStore.CommitResult.UNAVAILABLE, operation)
		prior = _store.lookup(operation)
	if prior.status == ProfileStore.CommitResult.COMMITTED:
		return _store.commit_confirmed(purchase)
	if prior.status != ProfileStore.CommitResult.MISSING:
		return prior
	if not _eligible(offer):
		return _receipt(ProfileStore.CommitResult.MISSING, operation)
	return _store.commit_confirmed(purchase)


func upgrade_basis_points(id: StringName) -> int:
	var total := 0
	var rank := 1
	var key := _key(id, rank)
	while _offers.has(key) and _facts.has_claim(key):
		total += _offers[key].basis_points
		rank += 1
		key = _key(id, rank)
	return total


func _eligible(offer: Offer) -> bool:
	if offer.rank > 0:
		return offer.rank == 1 or _facts.has_claim(_key(offer.id, offer.rank - 1))
	if not _facts.has_claim(_facts.discovery_claim(offer.id)):
		return false
	var unlocks := _facts.preparation_unlocks()
	unlocks[offer.id] = true
	return offer.id in RunPreparation.available(_catalog, _facts.definition(offer.id).kind, unlocks)


func _valid_offer(offer: Offer) -> bool:
	if (offer == null or offer.price == null or offer.price.sign_value <= 0 or offer.account not in [COMMON, RARE]
			or offer.rank < 0):
		return false
	if offer.rank == 0:
		return offer.basis_points == 0 and not _facts.ownership_claim(offer.id).is_empty()
	return (offer.id in UPGRADE_STATS and offer.rank <= ProfileMutation.MAX_ITEMS
		and offer.basis_points > 0 and offer.basis_points <= PROTOTYPE_STAT_CAP
		and offer.rank * offer.basis_points <= PROTOTYPE_STAT_CAP
		and (offer.rank != 1 or offer.account == COMMON))


static func _key(id: StringName, rank: int) -> String:
	return "progression/upgrade/%s/%d" % [id, rank]


static func _receipt(status: ProfileStore.CommitResult, operation: String) -> ProfileStore.Receipt:
	var result := ProfileStore.Receipt.new()
	result.status = status
	result.id = operation
	return result
