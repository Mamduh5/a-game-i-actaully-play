extends GutTest

const STARTERS := preload("res://src/catalog/starter_roster.tres")
const RECIPES := preload("res://dev/fixtures/catalog_reciprocal.tres")
const STATUS := ProfileStore.CommitResult

class RefusableStore extends ProfileStore:
	var refuse_commit: bool

	func _commit_io() -> bool:
		return false if refuse_commit else super._commit_io()

var _catalog: DefinitionCatalog
var _scratch: DirAccess
var _alice: RefusableStore


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
	_alice = RefusableStore.new()
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


func test_signed_discoveries_survive_reopen_and_unlock_only_the_original_recipient() -> void:
	if not OS.has_feature("windows"):
		return
	var issuer := Crypto.new().generate_rsa(2048)
	var recipient := Crypto.new().generate_rsa(2048)
	var binding := ProfileGrant.Binding.new()
	binding.issuer = issuer
	binding.recipient_key = recipient
	binding.recipient = "alice"
	binding.run = "discovery-run"
	binding.rules = "rules-v1"
	binding.catalog = String(_catalog.revision)
	assert_eq(ProfileGrantSettlement.retain_original_binding(_alice, binding, recipient).status, STATUS.COMMITTED)
	for id: String in ["H99", "R99"]:
		var envelope := ProfileGrant.sign_authorization(binding, issuer, "found-" + id,
			ProfileGrant.Kind.DISCOVERY, id, Quantity.from_count(1))
		assert_eq(ProfileGrantSettlement.apply(_alice, binding, recipient, envelope).receipt.status, STATUS.COMMITTED)
		assert_eq(ProfileGrantSettlement.apply(_alice, binding, recipient, envelope).receipt.status, STATUS.DUPLICATE)
	assert_true(_alice.close())
	assert_eq(_alice.open("alice", _scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var facts := ProfileProgression.open(_alice, _catalog)
	assert_true(facts.preparation_unlocks().has(&"R99"))
	assert_eq(facts.access_to(&"H99"), ProfileProgression.Access.DISCOVERED)
	assert_false(facts.preparation_unlocks().has(&"H99"))
	assert_eq(_fund(_alice, "earnings", ProfileShop.COMMON, 9), STATUS.COMMITTED)
	var shop := ProfileShop.open(_alice, _catalog, binding.rules, _offers())
	assert_eq(shop.buy("hero", &"H99").status, STATUS.COMMITTED)
	assert_eq(shop.buy("hero", &"H99").status, STATUS.DUPLICATE)
	assert_not_null(facts.prepare(&"H99", &"W01", [&"R99", &""], _empty_candidates()))
	assert_true(_alice.close())
	assert_eq(_alice.open("bob", _scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_false(facts.has_discovery(&"R99"))
	assert_eq(ProfileProgression.open(_alice, _catalog).access_to(&"H99"), ProfileProgression.Access.LOCKED)


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


func test_live_run_purchase_waits_for_pending_earnings_and_retries_once() -> void:
	if not OS.has_feature("windows"):
		return
	var setup := RunSetup.new()
	setup.run_id = &"purchase-run"
	setup.epoch = 1
	setup.rules_revision = &"rules-v1"
	setup.catalog_revision = _catalog.revision
	setup.authority_id = &"host"
	setup.challenge_id = &"normal"
	setup.initial_realms = {&"host": &"overworld"}
	var run := RunAuthority.new()
	assert_true(run.start(setup, &"host"))
	var signer := Crypto.new().generate_rsa(2048)
	var binding := ProfileGrant.Binding.new()
	binding.run = String(setup.run_id)
	binding.rules = String(setup.rules_revision)
	binding.catalog = String(setup.catalog_revision)
	binding.issuer = signer
	binding.recipient_key = signer
	binding.recipient = "alice"
	var earned := OrdinaryCurrency.begin(_alice, binding, signer, ProfileShop.COMMON)
	assert_true(run.attach_ordinary_currency(earned))
	assert_eq(earned.accrue("defeated/wildborn", Quantity.from_count(10)), OrdinaryCurrency.Eligibility.QUEUED)
	var shop := ProfileShop.open(_alice, _catalog, "rules-v1", _offers(), run)
	_alice.refuse_commit = true
	var held := shop.buy("pending-rank", &"movement", 1)
	assert_eq(held.status, STATUS.UNAVAILABLE)
	assert_eq(_alice.lookup(held.id).status, STATUS.MISSING)
	assert_eq(_alice.balance(ProfileShop.COMMON).native_at_scale(0), 0)
	assert_eq(earned.pending_amount().native_at_scale(0), 10)
	assert_eq(shop.upgrade_basis_points(&"movement"), 0)
	_alice.refuse_commit = false
	var settled := shop.buy("pending-rank", &"movement", 1)
	assert_eq(settled.status, STATUS.COMMITTED)
	assert_eq(settled.id, held.id)
	assert_eq(_alice.balance(ProfileShop.COMMON).native_at_scale(0), 4)
	assert_eq(shop.upgrade_basis_points(&"movement"), 500)
	assert_eq(earned.accrue("defeated/legion", Quantity.from_count(3)), OrdinaryCurrency.Eligibility.QUEUED)
	assert_eq(shop.buy("pending-rank", &"movement", 1).status, STATUS.DUPLICATE)
	assert_eq(_alice.balance(ProfileShop.COMMON).native_at_scale(0), 4)
	assert_eq(earned.pending_amount().native_at_scale(0), 3)


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
