extends GutTest

const STARTERS := preload("res://src/catalog/starter_roster.tres")
const RECIPES := preload("res://dev/fixtures/catalog_reciprocal.tres")
const STATUS := ProfileStore.CommitResult

var _catalog: DefinitionCatalog
var _scratch: DirAccess
var _alice: ProfileStore


func before_each() -> void:
	if not OS.has_feature("windows"):
		return
	var entries: Array[CatalogEntry] = []
	for entry: CatalogEntry in STARTERS.entries:
		if entry.id not in [&"P07", &"P12"]:
			entries.append(entry)
	entries.append_array(RECIPES.entries)
	entries.append(_definition(&"H99", CatalogEntry.Kind.HERO, CatalogEntry.Eligibility.OWNERSHIP))
	entries.append(_definition(&"R99", CatalogEntry.Kind.RUNE, CatalogEntry.Eligibility.DISCOVERY))
	_catalog = DefinitionCatalog.compile(&"wp21-fixture-v1", entries)
	_scratch = DirAccess.create_temp("agip-profile-progression")
	_alice = ProfileStore.new()
	assert_true(_catalog.is_valid(), str(_catalog.issues()))
	assert_eq(_alice.open("alice", _scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)


func after_each() -> void:
	if _alice != null:
		assert_true(_alice.close())


func test_discovery_and_paid_ownership_have_different_preparation_access() -> void:
	if not OS.has_feature("windows"):
		return
	var progression := ProfileProgression.open(_alice, _catalog)
	var shop := ProfileShop.open(_alice, _catalog, "rules-v1", _offers())
	assert_not_null(progression.prepare(&"H01", &"W01", [&"", &""], _empty_candidates()))
	assert_null(progression.prepare(&"H99", &"W01", [&"", &""], _empty_candidates()))
	assert_eq(progression.access_to(&"H99"), ProfileProgression.Access.LOCKED)
	assert_eq(shop.buy("locked", &"H99").status, STATUS.MISSING)
	assert_eq(_claim(_alice, "reached-hero-condition", progression.discovery_claim(&"H99")), STATUS.COMMITTED)
	assert_eq(_claim(_alice, "reached-rune-condition", progression.discovery_claim(&"R99")), STATUS.COMMITTED)
	assert_eq(progression.access_to(&"H99"), ProfileProgression.Access.DISCOVERED)
	assert_false(progression.preparation_unlocks().has(&"H99"))
	assert_true(progression.preparation_unlocks().has(&"R99"))
	assert_eq(shop.buy("too-poor", &"H99").status, STATUS.INSUFFICIENT)
	assert_eq(_fund(_alice, "initial-earnings", ProfileShop.COMMON, 30), STATUS.COMMITTED)
	var quote := shop.quote(&"H99", 0)
	quote.price = Quantity.from_count(1)
	var purchase := shop.buy("legal-purchase", &"H99")
	assert_eq(purchase.status, STATUS.COMMITTED)
	assert_eq(_alice.balance(ProfileShop.COMMON).native_at_scale(0), 21)
	assert_eq(progression.access_to(&"H99"), ProfileProgression.Access.OWNED)
	assert_not_null(progression.prepare(&"H99", &"W01", [&"R99", &""], _empty_candidates()))
	assert_eq(shop.buy("other-request", &"H99").status, STATUS.CONFLICT)
	assert_true(_alice.close())
	assert_eq(_alice.open("alice", _scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var replay := shop.buy("legal-purchase", &"H99")
	assert_eq(replay.status, STATUS.DUPLICATE)
	assert_eq(replay.anchor, purchase.anchor)
	assert_eq(shop.buy("legal-purchase", &"movement", 1).status, STATUS.CONFLICT)
	assert_eq(_alice.balance(ProfileShop.COMMON).native_at_scale(0), 21)
	assert_eq(progression.access_to(&"H99"), ProfileProgression.Access.OWNED)


func test_rank_prerequisite_and_private_balances_hold_under_contending_requests() -> void:
	if not OS.has_feature("windows"):
		return
	var shop := ProfileShop.open(_alice, _catalog, "rules-v1", _offers())
	assert_eq(shop.upgrade_basis_points(&"movement"), 0)
	assert_eq(_fund(_alice, "common-award", ProfileShop.COMMON, 30), STATUS.COMMITTED)
	assert_eq(_fund(_alice, "rare-award", ProfileShop.RARE, 2), STATUS.COMMITTED)
	assert_eq(shop.buy("early-rank", &"movement", 2).status, STATUS.MISSING)
	assert_eq(shop.buy("first-rank", &"movement", 1).status, STATUS.COMMITTED)
	assert_eq(shop.buy("competing-rank", &"movement", 1).status, STATUS.CONFLICT)
	assert_eq(shop.upgrade_basis_points(&"movement"), 500)
	assert_eq(shop.buy("later-rank", &"movement", 2).status, STATUS.COMMITTED)
	assert_eq(shop.buy("exceeds-authored-cap", &"movement", 3).status, STATUS.INVALID)
	assert_eq(shop.upgrade_basis_points(&"movement"), 1000)
	assert_eq(_alice.balance(ProfileShop.COMMON).native_at_scale(0), 24)
	assert_eq(_alice.balance(ProfileShop.RARE).native_at_scale(0), 0)
	var bob := ProfileStore.new()
	assert_eq(bob.open("bob", _scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var bob_shop := ProfileShop.open(bob, _catalog, "rules-v1", _offers())
	assert_eq(bob_shop.upgrade_basis_points(&"movement"), 0)
	assert_eq(bob_shop.buy("first-rank", &"movement", 1).status, STATUS.INSUFFICIENT)
	assert_true(bob.close())


func test_shop_rejects_invalid_rank_schedules() -> void:
	if not OS.has_feature("windows"):
		return
	assert_null(ProfileShop.open(_alice, _catalog, "rules-v1", [_offer(&"movement", 2, ProfileShop.COMMON, 10, 400)]))
	assert_null(ProfileShop.open(_alice, _catalog, "rules-v1", [
		_offer(&"movement", 1, ProfileShop.COMMON, 9, 400),
		_offer(&"movement", 2, ProfileShop.COMMON, 9, 400),
	]))
	assert_null(ProfileShop.open(_alice, _catalog, "rules-v1", [
		_offer(&"movement", 1, ProfileShop.COMMON, 8, 1500),
		_offer(&"movement", 2, ProfileShop.COMMON, 10, 1500),
	]))


func test_personal_fusion_identification_and_evolution_verification_preserve_recipe_visibility() -> void:
	if not OS.has_feature("windows"):
		return
	var journal := ProfileProgression.open(_alice, _catalog)
	assert_null(journal.recipe(&"F06"))
	assert_null(journal.recipe(&"E12A"))
	assert_eq(journal.recipe_claim(&"E12A", ProfileProgression.Knowledge.IDENTIFIED), "")
	assert_eq(_claim(_alice, "found-fusion-rumor", journal.recipe_claim(&"F06", ProfileProgression.Knowledge.RUMORED)), STATUS.COMMITTED)
	assert_eq(journal.recipe(&"F06").stage, ProfileProgression.Knowledge.RUMORED)
	assert_true(journal.recipe(&"F06").components.is_empty())
	assert_eq(_claim(_alice, "found-fusion-clue", journal.recipe_claim(&"F06", ProfileProgression.Knowledge.PARTIAL)), STATUS.COMMITTED)
	assert_eq(journal.recipe(&"F06").stage, ProfileProgression.Knowledge.PARTIAL)
	assert_true(journal.recipe(&"F06").components.is_empty())
	assert_eq(_claim(_alice, "identified-fusion", journal.recipe_claim(&"F06", ProfileProgression.Knowledge.IDENTIFIED)), STATUS.COMMITTED)
	var identified := journal.recipe(&"F06")
	assert_eq(identified.stage, ProfileProgression.Knowledge.IDENTIFIED)
	assert_eq(identified.components, [&"E07A", &"E12A"])
	assert_false(journal.preparation_unlocks().has(&"F06"))
	assert_eq(_claim(_alice, "heard-evolution-hint", journal.recipe_claim(&"E12A", ProfileProgression.Knowledge.PARTIAL)), STATUS.COMMITTED)
	assert_true(journal.recipe(&"E12A").catalyst.is_empty())
	assert_eq(_claim(_alice, "personal-evolution-verification", journal.recipe_claim(&"E12A", ProfileProgression.Knowledge.VERIFIED)), STATUS.COMMITTED)
	assert_true(_alice.close())
	assert_eq(_alice.open("alice", _scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var verified := journal.recipe(&"E12A")
	assert_eq(verified.stage, ProfileProgression.Knowledge.VERIFIED)
	assert_eq(verified.base, &"P12")
	assert_eq(verified.catalyst, &"P07")
	assert_true(_alice.close())
	assert_eq(_alice.open("bob", _scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_null(journal.recipe(&"E12A"))
	assert_null(journal.recipe(&"F06"))
	var teammate := ProfileProgression.open(_alice, _catalog)
	assert_null(teammate.recipe(&"E12A"))
	assert_null(teammate.recipe(&"F06"))


static func _definition(id: StringName, kind: CatalogEntry.Kind, eligibility: CatalogEntry.Eligibility) -> CatalogEntry:
	var value := CatalogEntry.new()
	value.id = id
	value.kind = kind
	value.lifetime = CatalogEntry.Lifetime.PREPARATION
	value.targeting = CatalogEntry.Targeting.NONE
	value.eligibility = eligibility
	return value


static func _empty_candidates() -> Array[StringName]:
	var slots: Array[StringName] = []
	slots.resize(RunPreparation.CANDIDATE_SLOTS)
	slots.fill(&"")
	return slots


func _claim(store: ProfileStore, id: String, claim: String) -> ProfileStore.CommitResult:
	var change := _mutation(id)
	change.claims.append(claim)
	return store.commit_confirmed(change).status


func _fund(store: ProfileStore, id: String, account: String, amount: int) -> ProfileStore.CommitResult:
	var change := _mutation(id)
	change.deltas[account] = Quantity.from_count(amount)
	return store.commit_confirmed(change).status


func _mutation(id: String) -> ProfileMutation:
	var change := ProfileMutation.new()
	change.id = id
	change.rules = "rules-v1"
	change.catalog = String(_catalog.revision)
	return change


static func _offers() -> Array[ProfileShop.Offer]:
	return [_offer(&"H99", 0, ProfileShop.COMMON, 9, 0),
		_offer(&"movement", 1, ProfileShop.COMMON, 6, 500),
		_offer(&"movement", 2, ProfileShop.RARE, 2, 500)]


static func _offer(id: StringName, rank: int, account: String, cost: int, basis_points: int) -> ProfileShop.Offer:
	var offer := ProfileShop.Offer.new()
	offer.id = id
	offer.rank = rank
	offer.account = account
	offer.price = Quantity.from_count(cost)
	offer.basis_points = basis_points
	return offer
