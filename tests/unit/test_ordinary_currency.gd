extends GutTest

const Commit := ProfileStore.CommitResult
const Add := OrdinaryCurrency.Eligibility
const Currency := "currency/permanent"
const Second := 1_000_000

class FixtureClock:
	var elapsed: int

	func sample() -> int:
		return elapsed

class LostResultStore extends ProfileStore:
	var keep := false

	func _commit_io() -> bool:
		if keep:
			super._commit_io()
		return false

class DeferredOpeningStore extends LostResultStore:
	var visible := false

	func lookup(operation: String) -> ProfileStore.Receipt:
		if not visible and operation.begins_with(ProfileStore.ORDINARY_SESSION_PREFIX) and operation.ends_with("/open"):
			var pending := ProfileStore.Receipt.new()
			pending.status = Commit.UNKNOWN
			pending.id = operation
			return pending
		return super.lookup(operation)

var _issuer: CryptoKey
var _guest: CryptoKey


func before_all() -> void:
	var crypto := Crypto.new()
	_issuer = crypto.generate_rsa(2048)
	_guest = crypto.generate_rsa(2048)


func test_fault_duration_samples_live_elapsed_time_without_a_service_step() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-ordinary-fault-clock")
	var store := ProfileStore.new()
	assert_eq(store.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var clock := FixtureClock.new()
	var earnings := OrdinaryCurrency.begin(store, _binding("alice", _issuer), _issuer, Currency, clock.sample)
	assert_eq(earnings.accrue("enemy-fault-clock", Quantity.from_count(7)), Add.QUEUED)
	clock.elapsed = 5 * Second - 1
	assert_eq(earnings.fault_elapsed_usec(), 0)
	clock.elapsed = 5 * Second + 123
	assert_eq(earnings.fault_elapsed_usec(), 123)
	clock.elapsed += 77
	assert_eq(earnings.fault_elapsed_usec(), 200)
	clock.elapsed -= 1
	assert_eq(earnings.fault_elapsed_usec(), 200)
	clock.elapsed = 7 * Second
	assert_true(earnings.flush())
	assert_eq(earnings.fault_elapsed_usec(), 2 * Second)
	clock.elapsed = 10 * Second
	assert_eq(earnings.fault_elapsed_usec(), 2 * Second)
	assert_true(store.close())


func test_newer_completion_preserves_original_in_flight_deadline_and_blocks_authority() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-ordinary-age")
	var store := ProfileStore.new()
	assert_eq(store.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var binding := _binding("alice", _issuer)
	var clock := FixtureClock.new()
	var earnings := OrdinaryCurrency.begin(store, binding, _issuer, Currency, clock.sample)
	var authority := _authority()
	assert_true(authority.attach_ordinary_currency(earnings))
	assert_false(authority.attach_ordinary_currency(OrdinaryCurrency.begin(store, binding, _issuer, Currency, clock.sample)))
	assert_eq(earnings.accrue("enemy-first", Quantity.from_count(7)), Add.QUEUED)
	clock.elapsed = 4 * Second - 1
	assert_eq(earnings.dispatch(), "")
	clock.elapsed += 1
	var first := earnings.dispatch()
	assert_false(first.is_empty())
	assert_eq(earnings.accrue("enemy-first", Quantity.from_count(7)), Add.DUPLICATE)
	assert_eq(earnings.accrue("enemy-second", Quantity.from_count(5)), Add.QUEUED)
	var second := earnings.dispatch(true)
	assert_ne(first, second)
	assert_eq(earnings.write_batch(second).status, Commit.COMMITTED)
	assert_eq(earnings.confirm_batch(second).status, Commit.COMMITTED)
	assert_eq(earnings.oldest_eligible_usec(), 0)
	assert_eq(earnings.pending_amount().native_at_scale(0), 7)
	assert_eq(store.balance(Currency).native_at_scale(0), 5)
	clock.elapsed = 5 * Second - 1
	assert_true(authority.close_tick())
	clock.elapsed += 1
	assert_false(authority.can_open_earning_group())
	assert_false(authority.close_tick())
	assert_eq(authority.next_tick(), 2)
	assert_eq(earnings.accrue("enemy-third", Quantity.from_count(11)), Add.FENCED)
	assert_eq(earnings.confirm_batch(first).status, Commit.MISSING)
	clock.elapsed = 6 * Second
	assert_eq(earnings.write_batch(first).status, Commit.COMMITTED)
	assert_false(authority.can_open_earning_group())
	assert_eq(earnings.oldest_eligible_usec(), 0)
	assert_true(authority.flush_ordinary_currency())
	assert_true(authority.close_tick())
	assert_eq(earnings.fault_elapsed_usec(), Second)
	assert_eq(earnings.oldest_eligible_usec(), -1)
	assert_eq(store.balance(Currency).native_at_scale(0), 12)
	assert_eq(store.checkpoint()["generation"], 2)
	assert_true(store.close())
	assert_eq(store.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var reopened := OrdinaryCurrency.begin(store, binding, _issuer, Currency, clock.sample)
	assert_eq(reopened.accrue("enemy-first", Quantity.from_count(7)), Add.QUEUED)
	assert_eq(reopened.accrue("enemy-second", Quantity.from_count(5)), Add.QUEUED)
	assert_true(reopened.flush())
	assert_eq(store.checkpoint()["generation"], 2)
	assert_eq(reopened.accrue("enemy-first", Quantity.from_count(700)), Add.QUEUED)
	assert_false(reopened.flush())
	assert_false(reopened.can_earn())
	assert_eq(store.balance(Currency).native_at_scale(0), 12)
	assert_true(store.close())


func test_orderly_quit_retries_the_same_receipt_and_seals_all_earning_before_exit() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-orderly-quit")
	var store := LostResultStore.new()
	assert_eq(store.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var authority := _authority()
	var binding := _binding("alice", _issuer)
	var earnings := OrdinaryCurrency.begin(store, binding, _issuer, Currency)
	assert_true(authority.attach_ordinary_currency(earnings))
	assert_eq(earnings.accrue("last-encounter", Quantity.from_count(9)), Add.QUEUED)
	var operation := earnings.dispatch(true)
	assert_false(authority.settle_orderly_quit())
	assert_true(authority.checkpoint().is_empty())
	assert_false(authority.close_tick())
	assert_eq(authority.next_tick(), 1)
	assert_eq(earnings.accrue("after-quit", Quantity.from_count(2)), Add.FENCED)
	assert_false(authority.attach_ordinary_currency(OrdinaryCurrency.begin(store, binding, _issuer, "currency/other")))
	assert_eq(store.lookup(operation).status, Commit.MISSING)
	store.keep = true
	assert_true(authority.settle_orderly_quit())
	assert_true(authority.settle_orderly_quit())
	assert_false(authority.can_open_earning_group())
	assert_eq(store.lookup(operation).status, Commit.COMMITTED)
	assert_true(store.close())
	assert_eq(store.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_eq(store.balance(Currency).native_at_scale(0), 9)
	assert_eq(store.checkpoint()["generation"], 1)
	assert_true(store.close())


func test_host_suspension_keeps_the_last_closed_frontier_until_earnings_are_durable() -> void:
	if not OS.has_feature("windows"):
		return
	var solo := _authority()
	assert_true(solo.prepare_orderly_suspension().is_empty())
	assert_true(solo.close_tick())
	var scratch := DirAccess.create_temp("agip-ordinary-suspension")
	var store := LostResultStore.new()
	assert_eq(store.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var authority := _authority(RunSetup.Role.HOST)
	var earnings := OrdinaryCurrency.begin(store, _binding("alice", _issuer), _issuer, Currency)
	assert_true(authority.attach_ordinary_currency(earnings))
	assert_true(authority.close_tick())
	var frontier := authority.checkpoint()
	assert_eq(earnings.accrue("last-before-suspension", Quantity.from_count(17)), Add.QUEUED)
	var operation := earnings.dispatch(true)
	assert_true(authority.prepare_orderly_suspension().is_empty())
	assert_eq(store.lookup(operation).status, Commit.MISSING)
	assert_eq(earnings.pending_amount().native_at_scale(0), 17)
	assert_eq(earnings.accrue("after-suspension", Quantity.from_count(1)), Add.FENCED)
	assert_true(authority.checkpoint().is_empty())
	assert_false(authority.close_tick())
	assert_eq(authority.next_tick(), 2)
	store.keep = true
	var settled := authority.prepare_orderly_suspension()
	assert_eq(settled, frontier)
	settled["tick"] = 9
	assert_eq(authority.prepare_orderly_suspension(), frontier)
	assert_eq(store.lookup(operation).status, Commit.COMMITTED)
	assert_false(authority.can_open_earning_group())
	assert_true(authority.settle_orderly_quit())
	assert_true(authority.prepare_orderly_suspension().is_empty())
	assert_true(store.close())
	assert_eq(store.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_eq(store.balance(Currency).native_at_scale(0), 17)
	assert_eq(store.checkpoint()["generation"], 1)
	assert_true(store.close())


func test_disclosure_marker_fences_start_and_closes_only_after_the_last_confirmed_earning() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-ordinary-disclosure")
	var store := LostResultStore.new()
	assert_eq(store.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var authority := _authority()
	var earnings := OrdinaryCurrency.begin(store, _binding("alice", _issuer), _issuer, Currency)
	assert_true(authority.attach_ordinary_currency(earnings))
	assert_false(authority.begin_ordinary_session(store))
	assert_false(authority.close_tick())
	assert_eq(ProfileOrdinarySession.reopen_status(store), ProfileOrdinarySession.ReopenStatus.CLEAR)
	store.keep = true
	assert_true(authority.begin_ordinary_session(store))
	assert_true(authority.begin_ordinary_session(store))
	assert_eq(store.checkpoint()["generation"], 1)
	assert_true(authority.close_tick())
	assert_eq(earnings.accrue("final-enemy", Quantity.from_count(17)), Add.QUEUED)
	store.keep = false
	assert_false(authority.settle_orderly_quit())
	assert_eq(earnings.pending_amount().native_at_scale(0), 17)
	assert_eq(ProfileOrdinarySession.reopen_status(store), ProfileOrdinarySession.ReopenStatus.POSSIBLE_EXPOSURE)
	store.keep = true
	assert_true(earnings.flush())
	store.keep = false
	assert_false(authority.settle_orderly_quit())
	assert_eq(store.balance(Currency).native_at_scale(0), 17)
	assert_eq(ProfileOrdinarySession.reopen_status(store), ProfileOrdinarySession.ReopenStatus.POSSIBLE_EXPOSURE)
	store.keep = true
	assert_true(authority.settle_orderly_quit())
	assert_true(authority.settle_orderly_quit())
	assert_true(store.close())
	assert_eq(store.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_eq(ProfileOrdinarySession.reopen_status(store), ProfileOrdinarySession.ReopenStatus.CLEAR)
	assert_eq(store.balance(Currency).native_at_scale(0), 17)
	assert_eq(store.checkpoint()["generation"], 3)
	assert_true(store.close())


func test_orderly_quit_after_a_refused_opening_leaves_no_activity_to_close() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-ordinary-unopened")
	var store := LostResultStore.new()
	assert_eq(store.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var authority := _authority()
	assert_false(authority.begin_ordinary_session(store))
	assert_false(authority.close_tick())
	assert_true(authority.settle_orderly_quit())
	assert_true(authority.settle_orderly_quit())
	assert_eq(store.checkpoint().generation, 0)
	assert_eq(ProfileOrdinarySession.reopen_status(store), ProfileOrdinarySession.ReopenStatus.CLEAR)
	assert_true(store.close())


func test_suspension_resolves_an_uncertain_opening_receipt_before_closing_it() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-ordinary-uncertain-open")
	var store := DeferredOpeningStore.new()
	assert_eq(store.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	store.keep = true
	var authority := _authority(RunSetup.Role.HOST)
	assert_false(authority.begin_ordinary_session(store))
	assert_false(authority.can_open_earning_group())
	assert_true(authority.prepare_orderly_suspension().is_empty())
	assert_eq(ProfileOrdinarySession.reopen_status(store), ProfileOrdinarySession.ReopenStatus.UNAVAILABLE)
	store.visible = true
	var suspended := authority.prepare_orderly_suspension()
	assert_false(suspended.is_empty())
	assert_eq(suspended.get("tick", -1), 0)
	assert_eq(authority.prepare_orderly_suspension(), suspended)
	assert_true(store.close())
	assert_eq(store.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_eq(store.checkpoint().generation, 2)
	assert_eq(ProfileOrdinarySession.reopen_status(store), ProfileOrdinarySession.ReopenStatus.CLEAR)
	assert_true(store.close())


func test_ordinary_disclosure_is_private_and_compares_the_latest_activity_markers() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-ordinary-disclosure-reopen")
	var root := scratch.get_current_dir()
	var store := ProfileStore.new()
	var other := ProfileStore.new()
	assert_eq(store.open("alice", root), ProfileStore.OpenResult.OPENED)
	assert_eq(other.open("bob", root), ProfileStore.OpenResult.OPENED)
	var original := _authority()
	assert_true(original.begin_ordinary_session(store))
	assert_false(original.begin_ordinary_session(other))
	var other_earnings := OrdinaryCurrency.begin(other, _binding("bob", _issuer), _issuer, Currency)
	assert_false(original.attach_ordinary_currency(other_earnings))
	assert_true(store.close())
	assert_eq(ProfileOrdinarySession.reopen_status(store), ProfileOrdinarySession.ReopenStatus.UNAVAILABLE)
	assert_eq(store.open("alice", root), ProfileStore.OpenResult.OPENED)
	assert_eq(ProfileOrdinarySession.reopen_status(store), ProfileOrdinarySession.ReopenStatus.POSSIBLE_EXPOSURE)
	assert_eq(ProfileOrdinarySession.reopen_status(other), ProfileOrdinarySession.ReopenStatus.CLEAR)
	var later := _authority()
	assert_true(later.begin_ordinary_session(store))
	assert_true(original.settle_orderly_quit())
	assert_eq(ProfileOrdinarySession.reopen_status(store), ProfileOrdinarySession.ReopenStatus.POSSIBLE_EXPOSURE)
	assert_true(later.settle_orderly_quit())
	assert_eq(ProfileOrdinarySession.reopen_status(store), ProfileOrdinarySession.ReopenStatus.CLEAR)
	assert_eq(store.checkpoint()["generation"], 4)
	assert_eq(other.checkpoint()["generation"], 0)
	assert_true(store.close())
	assert_true(other.close())


func test_failed_flush_retains_original_batch_then_reconciles_lost_success() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-ordinary-flush")
	var store := LostResultStore.new()
	assert_eq(store.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var clock := FixtureClock.new()
	var earnings := OrdinaryCurrency.begin(store, _binding("alice", _issuer), _issuer, Currency, clock.sample)
	assert_eq(earnings.accrue("first-life", Quantity.from_count(4)), Add.QUEUED)
	assert_eq(earnings.accrue("second-life", Quantity.from_count(6)), Add.QUEUED)
	var original := earnings.dispatch(true)
	assert_false(original.is_empty())
	assert_false(earnings.flush())
	assert_eq(earnings.pending_amount().native_at_scale(0), 10)
	assert_eq(earnings.oldest_eligible_usec(), 0)
	assert_eq(store.lookup(original).status, Commit.MISSING)
	clock.elapsed = 5 * Second
	assert_false(earnings.can_earn())
	store.keep = true
	assert_true(earnings.flush())
	assert_eq(store.lookup(original).status, Commit.COMMITTED)
	assert_eq(store.balance(Currency).native_at_scale(0), 10)
	assert_eq(store.checkpoint()["generation"], 1)
	assert_true(earnings.can_earn())
	assert_true(earnings.flush())
	assert_eq(store.checkpoint()["generation"], 1)
	assert_true(store.close())


func test_recipient_flush_issues_one_remote_batch_and_keeps_local_earnings_pending() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-ordinary-split")
	var issuer := ProfileStore.new()
	var guest := ProfileStore.new()
	assert_eq(issuer.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_eq(guest.open("bob", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var remote_binding := _binding("bob", _guest)
	assert_null(OrdinaryCurrency.begin(issuer, remote_binding, _issuer, Currency))
	assert_eq(ProfileGrantSettlement.retain_original_binding(issuer, remote_binding, _issuer).status, Commit.COMMITTED)
	assert_eq(ProfileGrantSettlement.retain_original_binding(guest, remote_binding, _guest).status, Commit.COMMITTED)
	var clock := FixtureClock.new()
	var remote := OrdinaryCurrency.begin(issuer, remote_binding, _issuer, Currency, clock.sample)
	var local := OrdinaryCurrency.begin(issuer, _binding("alice", _issuer), _issuer, Currency, clock.sample)
	var authority := _authority()
	assert_true(authority.attach_ordinary_currency(remote))
	assert_true(authority.attach_ordinary_currency(local))
	assert_eq(remote.accrue("a", Quantity.from_count(13)), Add.QUEUED)
	assert_eq(remote.accrue("b", Quantity.from_count(4)), Add.QUEUED)
	assert_eq(local.accrue("a", Quantity.from_count(10)), Add.QUEUED)
	assert_true(authority.flush_ordinary_currency("bob"))
	assert_eq(local.pending_amount().native_at_scale(0), 10)
	assert_eq(issuer.balance(Currency).native_at_scale(0), 0)
	var queued := issuer.pending_grants()
	assert_eq(queued.size(), 1)
	var applied := ProfileGrantSettlement.apply(guest, remote_binding, _guest, queued[0].body)
	assert_eq(applied.receipt.status, Commit.COMMITTED)
	assert_eq(guest.balance(Currency).native_at_scale(0), 17)
	assert_eq(ProfileGrantSettlement.acknowledge(issuer, remote_binding, applied.acknowledgement).status, Commit.COMMITTED)
	assert_true(authority.flush_ordinary_currency())
	assert_eq(issuer.balance(Currency).native_at_scale(0), 10)
	assert_eq(local.accrue("next", Quantity.from_count(2)), Add.QUEUED)
	clock.elapsed = 4 * Second - 1
	authority.service_ordinary_currency()
	assert_eq(issuer.balance(Currency).native_at_scale(0), 10)
	clock.elapsed += 1
	authority.service_ordinary_currency()
	assert_eq(issuer.balance(Currency).native_at_scale(0), 12)
	assert_true(issuer.pending_grants().is_empty())
	assert_true(issuer.close())
	assert_true(guest.close())


func test_important_issue_waits_for_its_recipient_currency_flush() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-ordinary-important")
	var store := LostResultStore.new()
	assert_eq(store.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var bound := _binding("alice", _issuer)
	var authority := _authority()
	var earnings := OrdinaryCurrency.begin(store, bound, _issuer, Currency)
	assert_true(authority.attach_ordinary_currency(earnings))
	assert_eq(earnings.accrue("ordinary/1", Quantity.from_count(4)), Add.QUEUED)
	var frontier := ProfileMutation.Frontier.new()
	frontier.run = bound.run
	frontier.epoch = 1
	frontier.tick = 1
	frontier.image = PackedByteArray([1])
	var important := ProfileGrantSettlement.Entitlement.new()
	important.binding = bound
	important.occurrence = "regional-boss/1"
	important.kind = ProfileGrant.Kind.CURRENCY
	important.award = Currency
	important.amount = Quantity.from_count(9)
	var pending := ProfileGrantSettlement.issue(store, _issuer, [important], frontier, authority)
	assert_eq(pending.status, Commit.UNAVAILABLE)
	assert_eq(earnings.pending_amount().native_at_scale(0), 4)
	assert_eq(store.balance(Currency).native_at_scale(0), 0)
	assert_true(store.frontier(bound.run).is_empty())
	store.keep = true
	var settled := ProfileGrantSettlement.issue(store, _issuer, [important], frontier, authority)
	assert_eq(settled.status, Commit.COMMITTED)
	assert_eq(settled.id, pending.id)
	assert_eq(settled.generation, 2)
	assert_eq(store.frontier(bound.run)["operation"], settled.id)
	assert_eq(store.balance(Currency).native_at_scale(0), 13)
	assert_eq(earnings.oldest_eligible_usec(), -1)
	assert_true(store.close())


func _binding(profile: String, recipient: CryptoKey) -> ProfileGrant.Binding:
	var result := ProfileGrant.Binding.new()
	result.run = "ordinary-run"
	result.rules = "V42.6/R1"
	result.catalog = "fixture"
	result.recipient = profile
	result.issuer = _issuer
	result.recipient_key = recipient
	return result


static func _authority(role: RunSetup.Role = RunSetup.Role.SOLO) -> RunAuthority:
	var setup := RunSetup.new()
	setup.role = role
	setup.run_id = &"ordinary-run"
	setup.epoch = 1
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = &"fixture"
	setup.authority_id = &"host"
	setup.challenge_id = &"normal"
	setup.initial_realms = {&"host": &"overworld"}
	var authority := RunAuthority.new()
	return authority if authority.start(setup, &"host") else null
