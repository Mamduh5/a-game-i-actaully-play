extends "res://dev/fixtures/wp25_native_passage_probe.gd"
## Two native peers at a controlled Collapse boundary with the host's body
## in an optional realm. The guest uses the ordinary reliable click.

const Arena := RunSetup.FINAL_REALM
const Collapse := RunParty.COLLAPSE_TICK
const Settlement := RunAuthority.GatewayResult
const Currency := "currency/common"

class RefusedStore extends ProfileStore:
	var first := true

	func _commit_io() -> bool:
		if first:
			first = false
			return false
		return super._commit_io()

var _gateway: RunFinalGateway
var _catalog: DefinitionCatalog
var _store := RefusedStore.new()
var _waiting := false
var _body_wait: int


func _start_run() -> bool:
	var bundle: CatalogBundle = load("res://src/catalog/starter_roster.tres")
	_catalog = bundle.compile()
	if not super._start_run():
		return false
	var handle := _rooms[OUTSIDE].module_center(WorldTopology.ANCHORS[0])
	var command := PlayerCommand.new(PlayerCommand.INTERACT, handle.x, handle.y)
	var entry := RunIntent.new(RUN, EPOCH, OUTSIDE, HOST, 1, 1, command.action, command)
	if (_authority.submit(HOST, entry) != Queued or not _authority.close_tick()
			or not _authority.valid or not _passages.interact(entry)):
		return false
	# Fixture setup leaves one ordinary closed tick before the guest request.
	_authority._closed_tick = Collapse - 2
	_party._tick = Collapse - 2
	var source := _rooms[OUTSIDE]
	var gate := source.module_center(WorldTopology.GATEWAY)
	if not source.geometry().commit_circle_pose(GUEST, 0, RealmSweep.Point.new(gate.x - 12.0, gate.y)):
		return false
	var arena := RealmGeometry.new(Arena)
	var slots: Array[StringName] = []
	slots.resize(RunPreparation.CANDIDATE_SLOTS)
	slots.fill(&"")
	var prepared := RunPreparation.select(_catalog, &"H02", &"W01", [&"", &""], slots, {})
	var progression := PartyProgression.begin(_setup, {HOST: prepared, GUEST: prepared})
	_gateway = RunFinalGateway.register(_authority, _party, source, arena,
		{HOST: RealmSweep.Point.new(124, 128), GUEST: RealmSweep.Point.new(148, 128)}, 36.0, 10.0, progression)
	if _gateway == null or not _create_body() or not _bind_earnings():
		return false
	return true


func _catalog_revision() -> StringName:
	return _catalog.revision


func _create_body() -> bool:
	var floor := _rooms[GARDEN].geometry()
	var at := floor.circle_center(HOST, 0)
	var enemy := CombatantState.new()
	enemy.id = &"garden-spawn"
	enemy.owner = enemy.id
	enemy.realm = GARDEN
	enemy.life = 1
	enemy.provenance = CombatOrigin.Provenance.SPAWN
	enemy.max_hp = Quantity.from_count(20)
	enemy.hp = QuantityLayerLedger.Pool.new(enemy.max_hp, QuantityErrorBounds.new())
	if not _kernel.add_actor(enemy) or not floor.add_circle(enemy.id, 0, RealmSweep.Point.new(at.x + 18, at.y), RADIUS, 2):
		return false
	var tick := _authority.next_tick()
	var now := CombatInstant.at_tick(tick)
	var action := CombatAction.new()
	action.source = enemy.id
	action.source_life = 1
	action.family = &"fixture-attack"
	action.origin = CombatOrigin.new()
	action.origin.owner = enemy.id
	action.origin.provenance = enemy.provenance
	action.origin.activation = tick
	action.origin.committed_at = now
	var part := CombatAction.Component.new()
	part.base = Quantity.from_count(20)
	action.components = [part]
	var delivery := CombatDelivery.activate(_kernel, action, GARDEN)
	var proof := floor.certify_circle_snapshot(GARDEN, at, 0.0, 2)
	if (delivery == null or proof == null or proof.contacts.size() != 1
			or delivery.admit(tick, proof.contacts[0], 1, true) != CombatDelivery.Result.ADMITTED
			or not delivery.finish() or not _party.observe_combat(_kernel.resolve_next(now))
			or not _authority.close_tick() or not _authority.valid):
		return false
	var body := _party.view(HOST, now)
	if body.alive or body.wait_until == null:
		return false
	_body_wait = body.wait_until.tick
	return true


func _bind_earnings() -> bool:
	if _store.open("gateway-fixture") != ProfileStore.OpenResult.OPENED:
		return false
	var key := Crypto.new().generate_rsa(2048)
	var binding := ProfileGrant.Binding.new()
	binding.issuer = key
	binding.recipient_key = key
	binding.recipient = _store.identity()
	binding.run = String(RUN)
	binding.rules = "V42.6/R1"
	binding.catalog = String(_catalog.revision)
	var earnings := OrdinaryCurrency.begin(_store, binding, key, Currency)
	return (_authority.attach_ordinary_currency(earnings)
		and earnings.accrue("before-gateway", Quantity.from_count(17)) == OrdinaryCurrency.Eligibility.QUEUED)


func _run_host() -> void:
	if _waiting:
		_waiting = false
		if _authority.retry_gateway() != Settlement.ENTERED:
			_finish(false)
			return
		_world_epoch += 1
		_baseline = 2
		var corpse := _party.view(HOST, CombatInstant.at_tick(Collapse))
		_facts["body_wait_preserved"] = not corpse.alive and corpse.realm == Arena and corpse.wait_until.tick == _body_wait
		_facts["settled"] = _store.balance(Currency).native_at_scale(0)
		_facts["generation"] = _store.checkpoint()["generation"]
		if not _publish_scope():
			_finish(false)
			return
	super._run_host()


func _close_and_publish() -> bool:
	_received_click = false
	_received_motion = false
	if not _authority.close_tick() or not _authority.valid:
		return false
	var state := _snapshot()
	if _baseline == 1:
		if (_authority.clicks.size() != 1 or state.tick != Collapse or state.acknowledged != 1
				or _kernel.advance_survival(CombatInstant.at_tick(state.tick)).result != CombatKernel.Result.CLOSED
				or _gateway.interact(_authority.clicks[0]) != Settlement.SETTLEMENT_WAIT):
			return false
		_facts["gated_before_rebaseline"] = (_authority.next_tick() == Collapse + 1
			and not _authority.can_open_earning_group() and _store.balance(Currency).sign_value == 0
			and _party.view(HOST, CombatInstant.at_tick(Collapse)).realm == GARDEN)
		_waiting = true
		return _facts["gated_before_rebaseline"]
	_facts["arena_movement_ack"] = state.acknowledged
	return state.acknowledged == 2 and _authority.clicks.is_empty() and _send(Kinds.STATE, state.pack())


func _host_verdict() -> bool:
	return (_authority.next_tick() == Collapse + 2 and _facts.get("stale_refused", false)
		and _facts.get("body_wait_preserved", false) and _facts.get("settled", 0) == 17
		and _facts.get("generation", 0) == 1)


func _receive_view(peer: ENetPacketPeer, frame: NativeSessionFrame, body: PackedByteArray) -> bool:
	if _replica.receive_frame(frame) != GuestReplica.Acceptance.APPLIED:
		return false
	var view := RecipientView.read(body)
	if view == null or view.party != {"host": "down", "guest": "living"}:
		return false
	if view.baseline == 1:
		if view.epoch != EPOCH or view.realm != String(OUTSIDE) or view.tick != Collapse - 1 or _replica.actor_ids() != ["guest"]:
			return false
		var at := _movement.position()
		_sent_click = _movement.interaction_packet(PlayerCommand.new(PlayerCommand.INTERACT, at.x + 12.0, at.y))
	else:
		if (view.baseline != 2 or view.epoch != EPOCH + 1 or view.realm != String(Arena) or view.tick != Collapse
				or _replica.actor_ids() != ["guest", "host"] or not view.explored.is_empty()):
			return false
		_facts["arena_epoch"] = view.epoch
		_facts["arrival_tick"] = view.tick
		_facts["party"] = view.party
		_facts["visible"] = _replica.actor_ids()
		_frames[RELIABLE] = true
	var movement := _movement.issue(PlayerCommand.new(PlayerCommand.MOVE_AXES, 1.0))
	return (_link.send(peer, SEQUENCED, EPOCH, view.baseline, movement) == OK
		and _link.send(peer, RELIABLE, EPOCH, view.baseline, _sent_click) == OK)


func _finish_guest_move(peer: ENetPacketPeer, scope: GuestMovement.Scope) -> bool:
	if scope.realm != Arena or scope.state.epoch != EPOCH + 1 or scope.state.acknowledged != 2 or scope.state.tick != Collapse + 1:
		return false
	_facts["arena_movement_ack"] = scope.state.acknowledged
	_frames[SEQUENCED] = true
	return _link.send(peer, ADMISSION, EPOCH, 4, NativeAdmissionMessage.leave()) == OK


func _finish(passed: bool) -> void:
	var closed := _store.close()
	super._finish(passed and closed)
