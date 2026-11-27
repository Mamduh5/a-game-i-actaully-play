class_name ProfileStore
extends RefCounted
## Owns the native SQLite connection for exactly one writable local identity.

enum OpenResult { OPENED, BUSY, INVALID_ID, UNSUPPORTED, HELD, QUARANTINED, FAILED }
enum CommitResult { COMMITTED, DUPLICATE, MISSING, CONFLICT, INSUFFICIENT, INVALID, UNAVAILABLE, UNKNOWN, STALE_FRONTIER, CORRUPT }
enum BackupResult { SAVED, RESTORED, INVALID, EXISTS, MISSING, QUARANTINED, FAILED }

class Receipt:
	var status: CommitResult
	var id: String
	var digest: String
	var generation: int
	var anchor: String
	var balances: Dictionary[String, Quantity] = {}
	var grant_binding: ProfileGrant.Binding

const APPLICATION_ID := 1095190864 # ASCII AGIP.
const SCHEMA_VERSION := 2
const LEGACY_VERSION := 1
const SQLITE_VERSION := "3.51.0"
const MAX_PROFILE_ID_LENGTH := 64
const FILENAME := "profile.db"
const GENESIS := "0000000000000000000000000000000000000000000000000000000000000000"
const ORDINARY_SESSION_PREFIX := "ordinary-session/"
const LEDGER_SCHEMA := [
	"CREATE TABLE ledger_meta (singleton INTEGER PRIMARY KEY CHECK(singleton=1), generation INTEGER NOT NULL CHECK(generation>=0), anchor TEXT NOT NULL) STRICT",
	"CREATE TABLE balances (account TEXT PRIMARY KEY, amount BLOB NOT NULL) STRICT",
	"CREATE TABLE receipts (operation TEXT PRIMARY KEY, digest TEXT NOT NULL, generation INTEGER NOT NULL UNIQUE CHECK(generation>0), anchor TEXT NOT NULL, result TEXT NOT NULL, request TEXT NOT NULL) STRICT",
	"CREATE TABLE claims (claim TEXT PRIMARY KEY, operation TEXT NOT NULL REFERENCES receipts(operation)) STRICT",
	"CREATE TABLE outbox (grant_key TEXT PRIMARY KEY, recipient TEXT NOT NULL, digest TEXT NOT NULL, body BLOB, issue_op TEXT NOT NULL REFERENCES receipts(operation), ack_op TEXT REFERENCES receipts(operation), CHECK((body IS NULL)=(ack_op IS NOT NULL))) STRICT",
	"CREATE INDEX outbox_pending ON outbox(grant_key) WHERE ack_op IS NULL",
	"CREATE TABLE frontiers (run_id TEXT PRIMARY KEY, epoch INTEGER NOT NULL CHECK(epoch>0), tick INTEGER NOT NULL CHECK(tick>=0), image BLOB NOT NULL, operation TEXT NOT NULL REFERENCES receipts(operation)) STRICT",
]

var _db: Object
var _identity: String
var _diagnostic: String
var _pending_operation: String
var _needs_reopen := false


func open(profile_id: String, root: String = "") -> OpenResult:
	if _db != null:
		return OpenResult.HELD
	_diagnostic = ""
	if not valid_identity(profile_id):
		return OpenResult.INVALID_ID
	if not OS.has_feature("windows") or not ClassDB.class_exists(&"SQLite"):
		return OpenResult.UNSUPPORTED
	var absolute_root := ProjectSettings.globalize_path(AppPaths.profiles_root() if root.is_empty() else root)
	if not absolute_root.is_absolute_path():
		return OpenResult.FAILED
	var directory := absolute_root.simplify_path().path_join("profile-" + profile_id)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return OpenResult.FAILED
	var connection := _connection_for(directory.path_join(FILENAME))
	if connection == null:
		return OpenResult.UNSUPPORTED
	if not bool(connection.call(&"open_db")):
		return _failure(connection)
	var result := _acquire(connection, profile_id)
	if result != OpenResult.OPENED:
		connection.call(&"close_db")
		return result
	_db = connection
	_identity = profile_id
	_pending_operation = ""
	_needs_reopen = false
	return OpenResult.OPENED


func close() -> bool:
	if _db == null:
		return true
	if not bool(_db.call(&"close_db")):
		_failure(_db)
		return false
	_db = null
	_identity = ""
	_pending_operation = ""
	_needs_reopen = false
	return true


func identity() -> String:
	return _identity


func diagnostic() -> String:
	return _diagnostic


func mode() -> Dictionary:
	return _read_mode(_db) if _db != null else {}


func balance(account: String) -> Quantity:
	return _read_balance(_db, account) if _available() and ProfileMutation.valid_id(account) else null


func checkpoint() -> Dictionary:
	return _checkpoint(_db) if _available() else {}


func latest_ordinary_session() -> Receipt:
	if not _available():
		return _receipt(CommitResult.UNAVAILABLE, "")
	# The fixed-width session sequence sorts on the existing operation index.
	var row: Variant = _select_one(_db, ("SELECT operation FROM receipts WHERE operation>=? AND operation<? "
		+ "ORDER BY operation DESC LIMIT 1"), [ORDINARY_SESSION_PREFIX, "ordinary-session0"])
	if row == null:
		return _receipt(CommitResult.UNAVAILABLE, "")
	return _receipt(CommitResult.MISSING, "") if row.is_empty() else _lookup(_db, row.operation)


func frontier(run_id: String) -> Dictionary:
	return _frontier(_db, run_id) if _available() and ProfileMutation.valid_id(run_id) else {}


func grant(key: String) -> Dictionary:
	return _grant(_db, key) if _available() and ProfileMutation.valid_id(key) else {}


func grant_binding(run: String, recipient: String) -> ProfileGrant.Binding:
	if not ProfileGrant.valid_field(run) or not valid_identity(recipient):
		return null
	if _db == null or _needs_reopen or not bool(_db.call(&"get_autocommit")):
		return null
	var operation := ProfileGrant.binding_id(run, recipient)
	# Immutable trust can be read while a different operation is unresolved.
	# Settlement still has to look up that exact pending receipt to unfence it.
	var saved := lookup(operation) if _pending_operation == operation else _lookup(_db, operation)
	return saved.grant_binding if saved.status == CommitResult.COMMITTED else null


func pending_grants(after_key: String = "", limit: int = 64) -> Array:
	if not _available() or (not after_key.is_empty() and not ProfileMutation.valid_id(after_key)) or limit < 1 or limit > 64:
		return []
	if not _query(_db, "SELECT grant_key, recipient, digest, body FROM outbox WHERE ack_op IS NULL AND grant_key > ? ORDER BY grant_key LIMIT ?", [after_key, limit]):
		return []
	return _db.get(&"query_result")


func save_backup(tag: String) -> BackupResult:
	if not _available() or not valid_identity(tag):
		return BackupResult.INVALID
	var destination := _backup_path(tag)
	if FileAccess.file_exists(destination):
		return BackupResult.EXISTS
	var staging := destination + "." + Crypto.new().generate_random_bytes(16).hex_encode() + ".db"
	var succeeded := bool(_db.call(&"backup_to", staging))
	if succeeded:
		var copy := _connection_for(staging)
		if bool(copy.call(&"open_db")):
			succeeded = _validate_image(copy, _identity) and _checkpoint(copy) == checkpoint()
			copy.call(&"close_db")
		else:
			succeeded = false
	if succeeded and not FileAccess.file_exists(destination) and DirAccess.rename_absolute(staging, destination) == OK:
		return BackupResult.SAVED
	if FileAccess.file_exists(staging):
		DirAccess.remove_absolute(staging)
	return BackupResult.FAILED


## The caller must supply the last known authoritative ledger generation and
## anchor from outside this backup. A file alone cannot prove its freshness.
func restore_backup(tag: String, expected_generation: int, expected_anchor: String) -> BackupResult:
	if not _available() or not valid_identity(tag) or expected_generation < 0 or not ProfileMutation.valid_digest(expected_anchor):
		return BackupResult.INVALID
	var path := _backup_path(tag)
	if not FileAccess.file_exists(path):
		return BackupResult.MISSING
	var live := checkpoint()
	if live.is_empty():
		return BackupResult.FAILED
	var copy := _connection_for(path)
	if not bool(copy.call(&"open_db")):
		return BackupResult.QUARANTINED
	var target := _checkpoint(copy)
	var compatible: bool = (not target.is_empty() and target.generation == expected_generation and target.anchor == expected_anchor
		and live.generation <= target.generation and _contains_anchor(copy, live) and _validate_image(copy, _identity))
	# Restore using a private snapshot of the exact image that was inspected.
	var custody := DirAccess.create_temp("agip-restore") if compatible else null
	var staged := custody.get_current_dir().path_join(FILENAME) if custody != null else ""
	var copied := not staged.is_empty() and bool(copy.call(&"backup_to", staged))
	copy.call(&"close_db")
	if not compatible:
		return BackupResult.QUARANTINED
	if not copied:
		return BackupResult.FAILED
	var sealed := _connection_for(staged)
	if not bool(sealed.call(&"open_db")):
		return BackupResult.FAILED
	compatible = _validate_image(sealed, _identity) and _checkpoint(sealed) == target and _contains_anchor(sealed, live)
	sealed.call(&"close_db")
	if not compatible:
		return BackupResult.QUARANTINED
	if not bool(_db.call(&"restore_from", staged)) or _checkpoint(_db) != target or not _qualified_mode(_db):
		_needs_reopen = true
		return BackupResult.FAILED
	return BackupResult.RESTORED


func _backup_path(tag: String) -> String:
	return String(_db.get(&"path")).get_base_dir().path_join("backup-" + tag + ".db")


## Resolve an unknown commit by its durable receipt before balances are exposed.
func lookup(operation: String) -> Receipt:
	if _db == null or _needs_reopen or not ProfileMutation.valid_id(operation):
		return _receipt(CommitResult.UNAVAILABLE, operation)
	if not _pending_operation.is_empty() and (operation != _pending_operation or not bool(_db.call(&"get_autocommit"))):
		return _receipt(CommitResult.UNKNOWN, operation)
	var result := _lookup(_db, operation)
	if operation == _pending_operation and result.status in [CommitResult.COMMITTED, CommitResult.MISSING]:
		_pending_operation = ""
	return result


func lookup_claim(claim: String) -> Receipt:
	if not ProfileMutation.valid_id(claim):
		return _receipt(CommitResult.INVALID, "")
	if not _available():
		return _receipt(CommitResult.UNAVAILABLE, "")
	var row: Variant = _select_one(_db, "SELECT operation FROM claims WHERE claim=?", [claim])
	if row == null:
		return _receipt(CommitResult.UNAVAILABLE, "")
	return _receipt(CommitResult.MISSING, "") if row.is_empty() else _lookup(_db, row.operation)


func commit(mutation: ProfileMutation) -> Receipt:
	var id := mutation.id if mutation != null else ""
	if not _available():
		return _receipt(CommitResult.UNKNOWN if not _pending_operation.is_empty() else CommitResult.UNAVAILABLE, id)
	var request := mutation.record() if mutation != null else ""
	if request.is_empty():
		return _receipt(CommitResult.INVALID, id)
	var digest := request.sha256_text()
	if not _query(_db, "BEGIN IMMEDIATE"):
		return _receipt(CommitResult.UNAVAILABLE, id)
	var result := _lookup(_db, id)
	if result.status == CommitResult.COMMITTED:
		if result.digest != digest:
			return _rollback(_receipt(CommitResult.CONFLICT, id))
		result.status = CommitResult.DUPLICATE
		return _rollback(result)
	if result.status != CommitResult.MISSING:
		return _rollback(result)
	result = _draft_commit(mutation, digest, request)
	if result.status != CommitResult.COMMITTED:
		return _rollback(result)
	if not _commit_io():
		_diagnostic = str(_db.get(&"error_message"))
		_pending_operation = id
		if not bool(_db.call(&"get_autocommit")):
			_query(_db, "ROLLBACK")
		return _receipt(CommitResult.UNKNOWN, id)
	return result


## Resolve a lost commit result against the exact submitted operation.
func commit_confirmed(mutation: ProfileMutation) -> Receipt:
	var verdict := commit(mutation)
	if verdict.status != CommitResult.UNKNOWN or mutation == null:
		return verdict
	var found := lookup(mutation.id)
	if found.status == CommitResult.COMMITTED:
		if found.digest != mutation.record().sha256_text():
			found.status = CommitResult.CONFLICT
		return found
	return found if found.status == CommitResult.MISSING else verdict


func _commit_io() -> bool:
	return _query(_db, "COMMIT")


func _rollback(result: Receipt) -> Receipt:
	if bool(_db.call(&"get_autocommit")) or _query(_db, "ROLLBACK"):
		return result
	_pending_operation = result.id
	return _receipt(CommitResult.UNKNOWN, result.id)


func _available() -> bool:
	return _db != null and not _needs_reopen and _pending_operation.is_empty() and bool(_db.call(&"get_autocommit"))


func _draft_commit(mutation: ProfileMutation, digest: String, request: String) -> Receipt:
	var id := mutation.id
	var previous := _checkpoint(_db)
	if previous.is_empty() or previous.generation == 9223372036854775807:
		return _receipt(CommitResult.CORRUPT, id)
	var generation: int = previous.generation + 1
	var posted: Dictionary[String, Quantity] = {}
	var encoded := {}
	for account: String in mutation.deltas:
		var before := _read_balance(_db, account)
		if before == null:
			return _receipt(CommitResult.CORRUPT, id)
		var amount := before.add(mutation.deltas[account])
		if amount == null:
			return _receipt(CommitResult.INVALID, id)
		if amount.sign_value < 0:
			return _receipt(CommitResult.INSUFFICIENT, id)
		posted[account] = amount
		encoded[account] = QuantityCodec.encode(amount).hex_encode()
	var original := JSON.stringify(encoded, "", true)
	var anchor := _anchor(_identity, previous.anchor, generation, id, digest, original)
	if not _query(_db, "INSERT INTO receipts VALUES (?, ?, ?, ?, ?, ?)", [id, digest, generation, anchor, original, request]):
		return _receipt(CommitResult.UNAVAILABLE, id)
	for account: String in posted:
		if not _query(_db, "INSERT INTO balances VALUES (?, ?) ON CONFLICT(account) DO UPDATE SET amount=excluded.amount",
				[account, QuantityCodec.encode(posted[account])]):
			return _receipt(CommitResult.UNAVAILABLE, id)
	for key: String in mutation.claims:
		if not _query(_db, "INSERT INTO claims VALUES (?, ?) ON CONFLICT(claim) DO NOTHING", [key, id]):
			return _receipt(CommitResult.UNAVAILABLE, id)
		if not _changed(_db):
			return _receipt(CommitResult.CONFLICT, id)
	var outbox_result := _draft_outbox(mutation)
	if outbox_result != CommitResult.COMMITTED:
		return _receipt(outbox_result, id)
	if mutation.frontier != null:
		var written := _draft_frontier(mutation.frontier, id)
		if written != CommitResult.COMMITTED:
			return _receipt(written, id)
	if not _query(_db, "UPDATE ledger_meta SET generation=?, anchor=? WHERE singleton=1", [generation, anchor]) or not _changed(_db):
		return _receipt(CommitResult.UNAVAILABLE, id)
	var result := _receipt(CommitResult.COMMITTED, id)
	result.digest = digest
	result.generation = generation
	result.anchor = anchor
	result.balances = posted
	if mutation.grant_binding != null:
		# The receipt never retains a reference to a caller's private key.
		result.grant_binding = ProfileMutation.restore_binding(JSON.parse_string(request))
	return result


func _draft_outbox(mutation: ProfileMutation) -> CommitResult:
	for entry: ProfileMutation.Grant in mutation.grants:
		if not _query(_db, "INSERT INTO outbox VALUES (?, ?, ?, ?, ?, NULL) ON CONFLICT(grant_key) DO NOTHING",
				[entry.key, entry.recipient, ProfileMutation.sha256(entry.envelope), entry.envelope, mutation.id]):
			return CommitResult.UNAVAILABLE
		if not _changed(_db):
			return CommitResult.CONFLICT
	for key: String in mutation.acknowledgements:
		var entry: Variant = _select_one(_db, "SELECT digest, ack_op FROM outbox WHERE grant_key=?", [key])
		if entry == null:
			return CommitResult.UNAVAILABLE
		if entry.get("digest") != mutation.acknowledgements[key]:
			return CommitResult.CONFLICT
		if entry.get("ack_op") == null and not _query(_db, "UPDATE outbox SET body=NULL, ack_op=? WHERE grant_key=?", [mutation.id, key]):
			return CommitResult.UNAVAILABLE
	return CommitResult.COMMITTED


func _draft_frontier(value: ProfileMutation.Frontier, operation: String) -> CommitResult:
	var previous: Variant = _select_one(_db, "SELECT epoch, tick, image FROM frontiers WHERE run_id=?", [value.run])
	if previous == null:
		return CommitResult.UNAVAILABLE
	if not previous.is_empty():
		if value.tick < previous.tick or value.epoch < previous.epoch:
			return CommitResult.STALE_FRONTIER
		if value.tick == previous.tick and value.epoch == previous.epoch:
			return CommitResult.COMMITTED if value.image == previous.image else CommitResult.CONFLICT
	if not _query(_db, ("INSERT INTO frontiers VALUES (?, ?, ?, ?, ?) ON CONFLICT(run_id) DO UPDATE SET "
			+ "epoch=excluded.epoch, tick=excluded.tick, image=excluded.image, operation=excluded.operation"),
			[value.run, value.epoch, value.tick, value.image, operation]):
		return CommitResult.UNAVAILABLE
	return CommitResult.COMMITTED


static func _read_balance(connection: Object, account: String) -> Quantity:
	var saved: Variant = _select_one(connection, "SELECT amount FROM balances WHERE account=?", [account])
	if saved == null:
		return null
	if saved.is_empty():
		return Quantity.from_count(0)
	return _decode_amount(saved.get("amount"))


static func _checkpoint(connection: Object) -> Dictionary:
	var saved: Variant = _select_one(connection, "SELECT generation, anchor FROM ledger_meta WHERE singleton=1")
	if (saved == null or not saved.get("generation") is int or saved.generation < 0
			or not saved.get("anchor") is String or not ProfileMutation.valid_digest(saved.anchor)):
		return {}
	return saved


static func _frontier(connection: Object, run_id: String) -> Dictionary:
	var saved: Variant = _select_one(connection, "SELECT epoch, tick, image, operation FROM frontiers WHERE run_id=?", [run_id])
	return saved if saved != null else {}


static func _grant(connection: Object, key: String) -> Dictionary:
	var saved: Variant = _select_one(connection, "SELECT recipient, digest, body, issue_op, ack_op FROM outbox WHERE grant_key=?", [key])
	return saved if saved != null else {}


static func _lookup(connection: Object, operation: String) -> Receipt:
	var saved: Variant = _select_one(connection, "SELECT digest, generation, anchor, result, request FROM receipts WHERE operation=?", [operation])
	if saved == null:
		return _receipt(CommitResult.UNAVAILABLE, operation)
	if saved.is_empty():
		return _receipt(CommitResult.MISSING, operation)
	if not saved.get("request") is String or saved.request.sha256_text() != saved.digest:
		return _receipt(CommitResult.CORRUPT, operation)
	return _decode_receipt(saved, operation)


static func _decode_receipt(saved: Dictionary, operation: String) -> Receipt:
	if not _valid_receipt_row(saved):
		return _receipt(CommitResult.CORRUPT, operation)
	var result := _receipt(CommitResult.COMMITTED, operation)
	var stored: Variant = JSON.parse_string(saved.result)
	if not stored is Dictionary:
		return _receipt(CommitResult.CORRUPT, operation)
	for account: String in stored:
		var hex: Variant = stored[account]
		if not ProfileMutation.valid_id(account) or not hex is String:
			return _receipt(CommitResult.CORRUPT, operation)
		var amount := _decode_amount(hex.hex_decode())
		if amount == null or QuantityCodec.encode(amount).hex_encode() != hex:
			return _receipt(CommitResult.CORRUPT, operation)
		result.balances[account] = amount
	result.generation = saved.generation
	result.digest = saved.digest
	result.anchor = saved.anchor
	if operation.begins_with(ProfileGrant.BINDING_PREFIX):
		var request: Variant = JSON.parse_string(saved.request)
		# Older ledgers allowed the prefix for ordinary mutation IDs.
		if request is Array and request.size() == 9 and request[0] == 1:
			return result
		result.grant_binding = ProfileMutation.restore_binding(request)
		if (result.grant_binding == null or not result.balances.is_empty()
				or ProfileGrant.binding_id(result.grant_binding.run, result.grant_binding.recipient) != operation):
			return _receipt(CommitResult.CORRUPT, operation)
	return result


static func _decode_amount(bytes: Variant) -> Quantity:
	if not bytes is PackedByteArray:
		return null
	var decoded := QuantityCodec.decode(bytes)
	return decoded if decoded != null and decoded.sign_value >= 0 else null


static func _valid_receipt_row(row: Dictionary) -> bool:
	return (row.get("digest") is String and ProfileMutation.valid_digest(row.digest) and row.get("anchor") is String
		and ProfileMutation.valid_digest(row.anchor) and row.get("generation") is int and row.generation > 0
		and row.get("result") is String)


static func _anchor(profile_id: String, previous: String, generation: int, operation: String, digest: String, result: String) -> String:
	return JSON.stringify([profile_id, previous, str(generation), operation, digest, result]).sha256_text()


static func _receipt(status: CommitResult, operation: String) -> Receipt:
	var result := Receipt.new()
	result.status = status
	result.id = operation
	return result


static func _select_one(connection: Object, sql: String, values: Array = []) -> Variant:
	if not _query(connection, sql, values):
		return null
	var rows: Array = connection.get(&"query_result")
	return {} if rows.is_empty() else rows[0] if rows.size() == 1 else null


static func _changed(connection: Object) -> bool:
	return _value(connection, "SELECT changes() AS changed", "changed") == 1


static func valid_identity(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_PROFILE_ID_LENGTH:
		return false
	for digit: int in value.to_utf8_buffer():
		if not ((digit >= 97 and digit <= 122) or (digit >= 48 and digit <= 57) or digit in [45, 95]):
			return false
	return true


func _acquire(connection: Object, profile_id: String) -> OpenResult:
	var version: Variant = _value(connection, "PRAGMA user_version", "user_version")
	if version == null:
		return _failure(connection)
	var app_id: Variant = _value(connection, "PRAGMA application_id", "application_id")
	if app_id == null:
		return _failure(connection)
	if not _recognized_header(version, app_id):
		return OpenResult.QUARANTINED
	var preflight := _check_empty_schema(connection) if version == 0 else _check_identity(connection, profile_id)
	if preflight != OpenResult.OPENED:
		return preflight
	if version == LEGACY_VERSION and not _legacy_image(connection):
		return OpenResult.QUARANTINED
	var journal: Variant = _value(connection, "PRAGMA journal_mode", "journal_mode")
	if journal == null:
		return _failure(connection)
	if journal != "delete":
		return OpenResult.QUARANTINED
	if (not _query(connection, "PRAGMA locking_mode=EXCLUSIVE")
			or not _query(connection, "PRAGMA synchronous=EXTRA")
			or not _query(connection, "PRAGMA trusted_schema=OFF")):
		return _failure(connection)
	if not _qualified_mode(connection):
		return OpenResult.UNSUPPORTED
	if not _query(connection, "BEGIN IMMEDIATE"):
		return _failure(connection)
	var result := _claim(connection, profile_id)
	if result == OpenResult.OPENED and not _query(connection, "COMMIT"):
		result = _failure(connection)
	if result != OpenResult.OPENED:
		_query(connection, "ROLLBACK")
		return result
	var committed_version: Variant = _value(connection, "PRAGMA user_version", "user_version")
	if committed_version == LEGACY_VERSION:
		return _migrate_legacy(connection, profile_id)
	return OpenResult.OPENED if committed_version == SCHEMA_VERSION else OpenResult.FAILED


func _claim(connection: Object, profile_id: String) -> OpenResult:
	var version: Variant = _value(connection, "PRAGMA user_version", "user_version")
	var app_id: Variant = _value(connection, "PRAGMA application_id", "application_id")
	if version == null or app_id == null:
		return _failure(connection)
	if not _recognized_header(version, app_id):
		return OpenResult.QUARANTINED
	if _value(connection, "PRAGMA journal_mode", "journal_mode") != "delete":
		return OpenResult.QUARANTINED
	if version == 0:
		var schema := _check_empty_schema(connection)
		if schema != OpenResult.OPENED:
			return schema
		if (not _query(connection, "CREATE TABLE profile_identity (singleton INTEGER PRIMARY KEY CHECK(singleton=1),"
				+ "profile_id TEXT NOT NULL, lease_marker INTEGER NOT NULL CHECK(lease_marker IN (0,1))) STRICT")
				or not _query(connection, "INSERT INTO profile_identity VALUES (1, ?, 0)", [profile_id])
				or not _query(connection, "PRAGMA application_id=%d" % APPLICATION_ID)
				or not _create_ledger(connection)):
			return _failure(connection)
	else:
		var identity_result := _check_identity(connection, profile_id)
		if identity_result != OpenResult.OPENED:
			return identity_result
		if version == LEGACY_VERSION and not _legacy_image(connection):
			return OpenResult.QUARANTINED
		if version == SCHEMA_VERSION and _checkpoint(connection).is_empty():
			return OpenResult.QUARANTINED
	# A real write holds the approved exclusive SQLite lock after COMMIT.
	if not _query(connection, "UPDATE profile_identity SET lease_marker=1-lease_marker WHERE singleton=1"):
		return _failure(connection)
	return OpenResult.OPENED


func _check_identity(connection: Object, profile_id: String) -> OpenResult:
	if not _query(connection, "SELECT profile_id FROM profile_identity WHERE singleton=1"):
		return _failure(connection)
	var rows: Array = connection.get(&"query_result")
	return OpenResult.OPENED if rows.size() == 1 and rows[0].get("profile_id") == profile_id else OpenResult.QUARANTINED


func _check_empty_schema(connection: Object) -> OpenResult:
	var objects: Variant = _value(connection, "SELECT count(*) AS objects FROM sqlite_schema", "objects")
	if objects == null:
		return _failure(connection)
	return OpenResult.OPENED if objects == 0 else OpenResult.QUARANTINED


func _migrate_legacy(source: Object, profile_id: String) -> OpenResult:
	if not _legacy_image(source):
		return OpenResult.QUARANTINED
	var custody := DirAccess.create_temp("agip-profile-migration")
	if custody == null:
		return OpenResult.FAILED
	var staged := custody.get_current_dir().path_join(FILENAME)
	if not bool(source.call(&"backup_to", staged)):
		return _failure(source)
	var original := String(source.get(&"path")).get_base_dir().path_join("legacy-v1-" + Crypto.new().generate_random_bytes(16).hex_encode() + ".db")
	if not bool(source.call(&"backup_to", original)):
		return _failure(source)
	var copy := _connection_for(staged)
	if not bool(copy.call(&"open_db")):
		return _failure(copy)
	var migrated := (_legacy_image(copy) and _check_identity(copy, profile_id) == OpenResult.OPENED
		and _query(copy, "PRAGMA synchronous=EXTRA") and _query(copy, "BEGIN IMMEDIATE")
		and _create_ledger(copy) and _query(copy, "COMMIT") and _validate_image(copy, profile_id))
	if not migrated and not bool(copy.call(&"get_autocommit")):
		_query(copy, "ROLLBACK")
	if not bool(copy.call(&"close_db")) or not migrated:
		return _failure(copy)
	if not bool(source.call(&"restore_from", staged)) or not _qualified_mode(source) or not _validate_image(source, profile_id):
		return _failure(source)
	return OpenResult.OPENED


static func _legacy_image(connection: Object) -> bool:
	return (_value(connection, "PRAGMA user_version", "user_version") == LEGACY_VERSION
		and _value(connection, "PRAGMA application_id", "application_id") == APPLICATION_ID
		and _value(connection, "SELECT count(*) AS total FROM sqlite_schema", "total") == 1
		and _integrity_ok(connection))


static func _integrity_ok(connection: Object) -> bool:
	if _value(connection, "PRAGMA integrity_check", "integrity_check") != "ok" or not _query(connection, "PRAGMA foreign_key_check"):
		return false
	return connection.get(&"query_result").is_empty()


static func _contains_anchor(connection: Object, known: Dictionary) -> bool:
	if known.generation == 0:
		return known.anchor == GENESIS
	var head: Variant = _select_one(connection, "SELECT anchor FROM receipts WHERE generation=?", [known.generation])
	return head != null and head.get("anchor") == known.anchor


static func _validate_image(connection: Object, profile_id: String) -> bool:
	if (_value(connection, "PRAGMA application_id", "application_id") != APPLICATION_ID
			or _value(connection, "PRAGMA user_version", "user_version") != SCHEMA_VERSION
			or _value(connection, "PRAGMA journal_mode", "journal_mode") != "delete"
			or _value(connection, "SELECT profile_id FROM profile_identity WHERE singleton=1", "profile_id") != profile_id
			or not _integrity_ok(connection)):
		return false
	var head := _checkpoint(connection)
	if head.is_empty():
		return false
	var generation := 0
	var anchor := GENESIS
	var history := {"balances": {}, "claims": {}, "grants": {}, "frontiers": {}}
	while generation < head.generation:
		if not _query(connection, "SELECT operation, digest, generation, anchor, result, request FROM receipts WHERE generation>? ORDER BY generation LIMIT 256", [generation]):
			return false
		var rows: Array = connection.get(&"query_result")
		if rows.is_empty():
			return false
		for row: Dictionary in rows:
			var receipt := _decode_receipt(row, row.operation)
			generation += 1
			if (receipt.status != CommitResult.COMMITTED or receipt.generation != generation
					or receipt.anchor != _anchor(profile_id, anchor, generation, receipt.id, receipt.digest, row.result)
					or row.request.sha256_text() != receipt.digest or not _replay_request(row.request, receipt, history)):
				return false
			anchor = receipt.anchor
	if (generation != head.generation or anchor != head.anchor
			or _value(connection, "SELECT count(*) AS total FROM receipts", "total") != head.generation
			or not _query(connection, "SELECT account, amount FROM balances")):
		return false
	var actual: Array = connection.get(&"query_result")
	if actual.size() != history.balances.size():
		return false
	for row: Dictionary in actual:
		if not history.balances.has(row.account) or row.amount != QuantityCodec.encode(history.balances[row.account]):
			return false
	return _verify_claims_and_frontiers(connection, history) and _verify_payloads(connection, history.grants)


static func _replay_request(body: String, receipt: Receipt, history: Dictionary) -> bool:
	if receipt.grant_binding != null:
		return true # _decode_receipt validated the binding-only request.
	var request: Variant = JSON.parse_string(body)
	if (not request is Array or request.size() != 9 or request[0] != 1 or request[1] != receipt.id
			or not request[2] is String or not request[3] is String or not ProfileMutation.valid_id(receipt.id)
			or not ProfileMutation.valid_id(request[2]) or not ProfileMutation.valid_id(request[3])):
		return false
	for index: int in range(4, 8):
		if not request[index] is Dictionary:
			return false
	if request[4].size() != receipt.balances.size():
		return false
	for account: String in request[4]:
		var hex: Variant = request[4][account]
		if not receipt.balances.has(account) or not hex is String:
			return false
		var delta := QuantityCodec.decode(hex.hex_decode())
		if delta == null or QuantityCodec.encode(delta).hex_encode() != hex:
			return false
		var current: Quantity = history.balances.get(account, Quantity.from_count(0))
		var next := current.add(delta)
		if next == null or next.compare(receipt.balances[account]) != 0:
			return false
		history.balances[account] = next
	for key: String in request[5]:
		if not ProfileMutation.valid_id(key) or history.claims.has(key):
			return false
		history.claims[key] = receipt.id
	for key: String in request[6]:
		var grant: Variant = request[6][key]
		if (not ProfileMutation.valid_id(key) or history.grants.has(key) or not grant is Array or grant.size() != 2
				or not grant[0] is String or not grant[1] is String or not ProfileMutation.valid_digest(grant[1])):
			return false
		history.grants[key] = {"recipient": grant[0], "digest": grant[1], "issue_op": receipt.id, "ack_op": null}
	for key: String in request[7]:
		var grant: Dictionary = history.grants.get(key, {})
		if grant.get("digest") != request[7][key] or grant.is_empty():
			return false
		if grant.ack_op == null:
			grant.ack_op = receipt.id
	return _replay_frontier(request[8], receipt.id, history.frontiers)


static func _replay_frontier(value: Variant, operation: String, frontiers: Dictionary) -> bool:
	if not value is Array:
		return false
	if value.is_empty():
		return true
	if value.size() != 4 or not value[0] is String or not ProfileMutation.valid_id(value[0]):
		return false
	for index: int in range(1, 4):
		if not value[index] is String:
			return false
	var epoch: int = value[1].to_int()
	var tick: int = value[2].to_int()
	if (epoch <= 0 or tick < 0 or tick > RunAuthority.MAX_TICK or str(epoch) != value[1] or str(tick) != value[2]
			or not ProfileMutation.valid_digest(value[3])):
		return false
	var known: Dictionary = frontiers.get(value[0], {})
	if not known.is_empty():
		if epoch < known.epoch or tick < known.tick:
			return false
		if epoch == known.epoch and tick == known.tick:
			return value[3] == known.digest
	frontiers[value[0]] = {"epoch": epoch, "tick": tick, "digest": value[3], "operation": operation}
	return true


static func _verify_claims_and_frontiers(connection: Object, history: Dictionary) -> bool:
	if not _query(connection, "SELECT claim, operation FROM claims"):
		return false
	var claims: Array = connection.get(&"query_result")
	if claims.size() != history.claims.size():
		return false
	for claim: Dictionary in claims:
		if history.claims.get(claim.claim) != claim.operation:
			return false
	if not _query(connection, "SELECT run_id FROM frontiers"):
		return false
	if connection.get(&"query_result").size() != history.frontiers.size():
		return false
	for id: String in history.frontiers:
		var expected: Dictionary = history.frontiers[id]
		var actual := _frontier(connection, id)
		if (actual.is_empty() or expected.epoch != actual.epoch or expected.tick != actual.tick
				or expected.operation != actual.operation or expected.digest != ProfileMutation.sha256(actual.image)):
			return false
	return true


static func _verify_payloads(connection: Object, expected: Dictionary) -> bool:
	if _value(connection, "SELECT count(*) AS total FROM outbox", "total") != expected.size():
		return false
	var after := ""
	while true:
		if not _query(connection, "SELECT grant_key, recipient, digest, body, issue_op, ack_op FROM outbox WHERE grant_key > ? ORDER BY grant_key LIMIT 32", [after]):
			return false
		var grants: Array = connection.get(&"query_result")
		if grants.is_empty():
			return true
		for entry: Dictionary in grants:
			var recorded: Dictionary = expected.get(entry.grant_key, {})
			if (recorded.is_empty() or entry.recipient != recorded.recipient or entry.digest != recorded.digest
					or entry.ack_op != recorded.ack_op or entry.issue_op != recorded.issue_op
					or (entry.body != null and ProfileMutation.sha256(entry.body) != entry.digest)):
				return false
			after = entry.grant_key
	return false


func _failure(connection: Object) -> OpenResult:
	_diagnostic = str(connection.get(&"error_message"))
	return OpenResult.BUSY if "locked" in _diagnostic.to_lower() or "busy" in _diagnostic.to_lower() else OpenResult.FAILED


static func _recognized_header(version: int, app_id: int) -> bool:
	return (version == 0 and app_id == 0) or (version in [LEGACY_VERSION, SCHEMA_VERSION] and app_id == APPLICATION_ID)


static func _connection_for(path: String) -> Object:
	var connection: Object = ClassDB.instantiate(&"SQLite")
	if connection != null:
		connection.set(&"path", path)
		connection.set(&"verbosity_level", 0)
		connection.set(&"foreign_keys", true)
	return connection


static func _create_ledger(connection: Object) -> bool:
	for sql: String in LEDGER_SCHEMA:
		if not _query(connection, sql):
			return false
	return (_query(connection, "INSERT INTO ledger_meta VALUES (1, 0, ?)", [GENESIS])
		and _query(connection, "PRAGMA user_version=%d" % SCHEMA_VERSION))


static func _read_mode(connection: Object) -> Dictionary:
	return {"sqlite": _value(connection, "SELECT sqlite_version() AS version", "version"),
		"journal": _value(connection, "PRAGMA journal_mode", "journal_mode"),
		"synchronous": _value(connection, "PRAGMA synchronous", "synchronous"),
		"locking": _value(connection, "PRAGMA locking_mode", "locking_mode")}


static func _qualified_mode(connection: Object) -> bool:
	return _read_mode(connection) == {"sqlite": SQLITE_VERSION, "journal": "delete", "synchronous": 3, "locking": "exclusive"}


static func _value(connection: Object, sql: String, column: String) -> Variant:
	if not _query(connection, sql):
		return null
	var rows: Array = connection.get(&"query_result")
	return rows[0].get(column) if rows.size() == 1 else null


static func _query(connection: Object, sql: String, values: Array = []) -> bool:
	return bool(connection.call(&"query_with_bindings", sql, values))
