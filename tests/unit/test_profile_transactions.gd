extends GutTest

const Commit := ProfileStore.CommitResult
const Backup := ProfileStore.BackupResult

class UnconfirmedStore extends ProfileStore:
	var commit_anyway := false

	func _commit_io() -> bool:
		if commit_anyway:
			super._commit_io()
		return false


func test_exact_balance_and_original_receipt_survive_reopen_and_conflicting_replay() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-ledger-replay")
	var store := _open(scratch)
	var large := Quantity.from_canonical(false, 3, "1" + "0".repeat(402) + "125")
	var first := _mutation("original", large)
	first.claims = ["unique-entitlement"]
	var original := store.commit(first)
	assert_eq(original.status, Commit.COMMITTED)
	assert_eq(QuantityCodec.encode(original.balances["coins"]), QuantityCodec.encode(large))
	assert_eq(original.generation, 1)
	var add := Quantity.from_count(1, 3)
	assert_eq(store.commit(_mutation("small-credit", add)).status, Commit.COMMITTED)
	assert_true(store.close())
	assert_eq(store.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var duplicate := store.commit(first)
	assert_eq(duplicate.status, Commit.DUPLICATE)
	assert_eq(duplicate.anchor, original.anchor)
	assert_eq(QuantityCodec.encode(duplicate.balances["coins"]), QuantityCodec.encode(large))
	assert_eq(QuantityCodec.encode(store.balance("coins")), QuantityCodec.encode(large.add(add)))
	assert_eq(store.commit(_mutation("original", add)).status, Commit.CONFLICT)
	var other := _mutation("new-operation", add)
	other.claims = ["unique-entitlement"]
	assert_eq(store.commit(other).status, Commit.CONFLICT)
	assert_eq(store.lookup("new-operation").status, Commit.MISSING)
	assert_eq(store.commit(_mutation("too-much", large.add(Quantity.from_count(1)).negated())).status, Commit.INSUFFICIENT)
	assert_eq(store.checkpoint()["generation"], 2)
	assert_true(store.close())


func test_outbox_frontier_and_receipt_share_the_rollback_boundary() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-outbox")
	var store := _open(scratch)
	var issued := _mutation("issued", Quantity.from_count(7))
	var bytes := PackedByteArray([0, 1, 2, 0, 255])
	issued.grants = [_grant("grant-1", bytes)]
	const FRONTIER_TICK := 9007199254740993
	issued.frontier = _frontier(3, FRONTIER_TICK, bytes)
	assert_eq(store.commit(issued).status, Commit.COMMITTED)
	assert_eq(store.frontier("run")["tick"], FRONTIER_TICK)
	assert_eq(store.frontier("run")["image"], bytes)
	assert_eq(store.pending_grants()[0]["body"], bytes)
	var stale := _mutation("stale", Quantity.from_count(4))
	stale.grants = [_grant("grant-2", bytes)]
	stale.frontier = _frontier(4, FRONTIER_TICK - 1, bytes)
	assert_eq(store.commit(stale).status, Commit.STALE_FRONTIER)
	assert_eq(store.lookup("stale").status, Commit.MISSING)
	assert_true(store.grant("grant-2").is_empty())
	assert_eq(store.balance("coins").native_at_scale(0), 7)
	var bad := _mutation("bad-ack")
	bad.acknowledgements["grant-1"] = "f".repeat(64)
	assert_eq(store.commit(bad).status, Commit.CONFLICT)
	var ack := _mutation("acked")
	ack.acknowledgements["grant-1"] = ProfileMutation.sha256(bytes)
	assert_eq(store.commit(ack).status, Commit.COMMITTED)
	assert_true(store.pending_grants().is_empty())
	assert_eq(store.grant("grant-1")["digest"], ProfileMutation.sha256(bytes))
	assert_eq(store.grant("grant-1")["ack_op"], "acked")
	assert_null(store.grant("grant-1")["body"])
	assert_eq(store.commit(ack).status, Commit.DUPLICATE)
	assert_true(store.close())


func test_unknown_commit_hides_balances_until_lookup_distinguishes_commit_from_rollback() -> void:
	if not OS.has_feature("windows"):
		return
	for persisted: bool in [false, true]:
		var scratch := DirAccess.create_temp("agip-unknown-commit")
		var store := UnconfirmedStore.new()
		store.commit_anyway = persisted
		assert_eq(store.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
		assert_eq(store.commit(_mutation("unknown", Quantity.from_count(9))).status, Commit.UNKNOWN)
		assert_null(store.balance("coins"))
		assert_eq(store.lookup("unrelated").status, Commit.UNKNOWN)
		assert_eq(store.commit(_mutation("later")).status, Commit.UNKNOWN)
		assert_eq(store.lookup("unknown").status, Commit.COMMITTED if persisted else Commit.MISSING)
		assert_eq(store.balance("coins").native_at_scale(0), 9 if persisted else 0)
		assert_true(store.close())


func test_backup_restore_requires_a_verified_anchor_and_rejects_a_receipt_gap() -> void:
	if not OS.has_feature("windows"):
		return
	var original := DirAccess.create_temp("agip-original-ledger")
	var store := _open(original)
	var early := _mutation("early", Quantity.from_count(7))
	early.grants = [_grant("earlier", PackedByteArray([21]))]
	early.frontier = _frontier(1, 1, PackedByteArray([23]))
	assert_eq(store.commit(early).status, Commit.COMMITTED)
	var old := store.checkpoint()
	assert_eq(store.save_backup("early"), Backup.SAVED)
	assert_eq(store.save_backup("early"), Backup.EXISTS)
	assert_eq(store.commit(_mutation("later", Quantity.from_count(11))).status, Commit.COMMITTED)
	var latest := store.checkpoint()
	assert_eq(store.save_backup("latest"), Backup.SAVED)
	assert_eq(store.restore_backup("early", latest.generation, latest.anchor), Backup.QUARANTINED)
	assert_eq(store.restore_backup("early", old.generation, old.anchor), Backup.QUARANTINED)
	assert_eq(store.balance("coins").native_at_scale(0), 18)
	assert_true(store.close())
	var replacement := DirAccess.create_temp("agip-replacement-ledger")
	store = _open(replacement)
	for tag: String in ["early", "latest"]:
		var file := "profile-alice/backup-" + tag + ".db"
		assert_eq(DirAccess.copy_absolute(original.get_current_dir().path_join(file), replacement.get_current_dir().path_join(file)), OK)
	assert_eq(store.restore_backup("early", latest.generation, latest.anchor), Backup.QUARANTINED)
	var tampered := replacement.get_current_dir().path_join("profile-alice/backup-tampered.db")
	assert_eq(DirAccess.copy_absolute(replacement.get_current_dir().path_join("profile-alice/backup-latest.db"), tampered), OK)
	var sqlite: Object = ClassDB.instantiate(&"SQLite")
	sqlite.set(&"path", tampered)
	sqlite.set(&"verbosity_level", 0)
	assert_true(bool(sqlite.call(&"open_db")))
	assert_true(bool(sqlite.call(&"query", "UPDATE frontiers SET image=x'22'")))
	assert_true(bool(sqlite.call(&"close_db")))
	assert_eq(store.restore_backup("tampered", latest.generation, latest.anchor), Backup.QUARANTINED)
	assert_eq(store.restore_backup("latest", latest.generation, latest.anchor), Backup.RESTORED)
	assert_eq(store.checkpoint(), latest)
	assert_eq(store.pending_grants()[0]["grant_key"], "earlier")
	assert_eq(ProfileStore.new().open("alice", replacement.get_current_dir()), ProfileStore.OpenResult.BUSY)
	assert_engine_error("database is locked")
	assert_eq(store.lookup("later").status, Commit.COMMITTED)
	assert_eq(store.balance("coins").native_at_scale(0), 18)
	assert_true(store.close())
	assert_eq(store.open("alice", replacement.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_eq(store.checkpoint(), latest)
	assert_true(store.close())


func test_migration_validates_a_version_one_copy_and_preserves_the_legacy_database() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-legacy-ledger")
	var folder := scratch.get_current_dir().path_join("profile-alice")
	assert_eq(DirAccess.make_dir_recursive_absolute(folder), OK)
	var sqlite: Object = ClassDB.instantiate(&"SQLite")
	sqlite.set(&"path", folder.path_join("profile.db"))
	sqlite.set(&"verbosity_level", 0)
	assert_true(bool(sqlite.call(&"open_db")))
	for sql: String in ["CREATE TABLE profile_identity (singleton INTEGER PRIMARY KEY CHECK(singleton=1), profile_id TEXT NOT NULL, lease_marker INTEGER NOT NULL CHECK(lease_marker IN (0,1))) STRICT",
			"INSERT INTO profile_identity VALUES (1, 'alice', 0)", "PRAGMA user_version=1", "PRAGMA application_id=1095190864"]:
		assert_true(bool(sqlite.call(&"query", sql)))
	assert_true(bool(sqlite.call(&"close_db")))
	var store := _open(scratch)
	assert_eq(store.checkpoint()["generation"], 0)
	assert_eq(store.commit(_mutation("after-migration", Quantity.from_count(2))).status, Commit.COMMITTED)
	assert_true(store.close())
	var backups := DirAccess.get_files_at(folder)
	var found := false
	for file: String in backups:
		if file.begins_with("legacy-v1-"):
			found = true
			sqlite.set(&"path", folder.path_join(file))
			assert_true(bool(sqlite.call(&"open_db")))
			assert_true(bool(sqlite.call(&"query", "PRAGMA user_version")))
			assert_eq(sqlite.get(&"query_result")[0]["user_version"], 1)
			assert_true(bool(sqlite.call(&"close_db")))
	assert_true(found)


func _open(scratch: DirAccess) -> ProfileStore:
	var store := ProfileStore.new()
	assert_eq(store.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED, store.diagnostic())
	return store


static func _mutation(id: String, amount: Quantity = null) -> ProfileMutation:
	var mutation := ProfileMutation.new()
	mutation.id = id
	mutation.rules = "V42.6/R1"
	mutation.catalog = "fixture"
	if amount != null:
		mutation.deltas["coins"] = amount
	return mutation


static func _grant(key: String, bytes: PackedByteArray) -> ProfileMutation.Grant:
	var entry := ProfileMutation.Grant.new()
	entry.key = key
	entry.recipient = "guest"
	entry.envelope = bytes
	return entry


static func _frontier(epoch: int, tick: int, bytes: PackedByteArray) -> ProfileMutation.Frontier:
	var value := ProfileMutation.Frontier.new()
	value.run = "run"
	value.epoch = epoch
	value.tick = tick
	value.image = bytes
	return value
