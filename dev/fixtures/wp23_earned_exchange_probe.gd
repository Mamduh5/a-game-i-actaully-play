extends "res://dev/fixtures/wp23_exchange_probe.gd"
## Reconcile ordinary grants whose source is a settled encounter elimination.

const ROSTER: CatalogBundle = preload("res://src/catalog/starter_roster.tres")
const HOST := &"host"
const GUEST := &"guest"
const REALM := WorldTopology.OVERWORLD


func _issue() -> bool:
	var catalog := ROSTER.compile()
	var setup := RunSetup.new()
	setup.role = RunSetup.Role.HOST
	setup.run_id = StringName(Original)
	setup.authority_id = HOST
	setup.initial_realms = {HOST: REALM, GUEST: REALM}
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = catalog.revision
	setup.challenge_id = &"normal"
	setup.seed = 3207
	setup.epoch = EPOCH
	var positions := {HOST: 62.0, GUEST: 322.0}
	var builds: Dictionary[StringName, StarterEncounter.Build] = {}
	var candidates: Array[StringName] = []
	candidates.resize(RunPreparation.CANDIDATE_SLOTS)
	candidates.fill(&"")
	var preparation := RunPreparation.select(catalog, &"H01", &"W01", [&"", &""], candidates, {})
	for id: StringName in [HOST, GUEST]:
		var build := StarterEncounter.Build.new()
		build.preparation = preparation
		build.powers = RunRewardQueue.begin(preparation, RunRandom.new(setup.seed), id)
		build.start = RealmSweep.Point.new(positions[id], 128.0)
		build.maximum_hp = Quantity.from_count(100)
		builds[id] = build
	var floor := WorldExploration.create(WorldTopology.generate(setup.seed), [HOST, GUEST])
	var encounter := StarterEncounter.assemble(setup, HOST, floor, builds)
	var remote := _store.grant_binding(Original, "bob")
	var local := ProfileGrant.Binding.new()
	local.run = Original
	local.rules = String(setup.rules_revision)
	local.catalog = String(setup.catalog_revision)
	local.recipient = "alice"
	local.issuer = _identity_key
	local.recipient_key = _identity_key
	var account := _currency_account()
	var issuer := OrdinaryCurrency.begin(_store, local, _identity_key, account)
	var guest := OrdinaryCurrency.begin(_store, remote, _identity_key, account)
	if (encounter == null or not encounter.bind_enemy_currency({HOST: issuer, GUEST: guest})
			or not encounter.place_enemy(&"first", _foe(20), RealmSweep.Point.new(110, 128), 17)
			or not encounter.place_enemy(&"second", _foe(24), RealmSweep.Point.new(155, 128), 23)
			or not encounter.begin_ordinary_session(_store) or not encounter.close_tick()):
		return false
	if not _earned_only(encounter, &"first") or not encounter.flush_ordinary_currency():
		return false
	var manual := PlayerCommand.new(PlayerCommand.MANUAL, 155, 128)
	var intent := RunIntent.new(setup.run_id, setup.epoch, REALM, HOST, 2, 1, manual.action, manual)
	if (encounter.submit(HOST, intent) != RunAuthority.Admission.QUEUED or not encounter.close_tick()
			or not _earned_only(encounter, &"second") or not encounter.settle_orderly_quit()):
		return false
	print("WP23_PEER_EARNINGS ", JSON.stringify({"kills": ["first", "second"], "guest_damage": false,
		"host_balance": _store.balance(account).native_at_scale(0), "guest_pending_grants": _store.pending_grants().size()}))
	return true


static func _earned_only(encounter: StarterEncounter, id: StringName) -> bool:
	var kills: Array[StringName] = []
	for outcome: Dictionary in encounter.closed_result().outcomes:
		if outcome.get("owner") == GUEST and outcome.get("damage", false):
			return false
		if outcome.get("eliminated", false) and outcome.get("owner") == HOST:
			kills.append(outcome.target)
	return kills == [id]


static func _foe(hp: int) -> WorldEnemy.Rules:
	var rules := WorldEnemy.Rules.new()
	rules.faction = &"witness"
	rules.foes = [WorldEnemy.PARTY]
	rules.family = &"fixture/earnings"
	rules.hp = Quantity.from_count(hp)
	rules.damage = Quantity.from_count(16)
	rules.radius = 12.0
	rules.sight = 154.0
	rules.attack_range = 103.0
	rules.attack_radius = 26.0
	rules.windup_ticks = 39
	rules.recovery_ticks = 78
	return rules


func _catalog_revision() -> String:
	return String(ROSTER.revision)


func _delivery_index(item: ProfileGrant) -> int:
	if (item == null or item.kind != ProfileGrant.Kind.CURRENCY
			or item.award != _currency_account() or not item.occurrence.begins_with("ordinary/")):
		return -1
	match item.amount.native_at_scale(0):
		17: return 0
		23: return 1
		_: return -1


func _currency_account() -> String:
	return StarterEncounter.COMMON_CURRENCY


func _expected_balance() -> int:
	return 40 if _original_issuer else super._expected_balance()
