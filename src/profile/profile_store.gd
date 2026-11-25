class_name ProfileStore
extends RefCounted
## Owns the native SQLite connection for exactly one writable local identity.

enum OpenResult { OPENED, BUSY, INVALID_ID, UNSUPPORTED, HELD, QUARANTINED, FAILED }

const APPLICATION_ID := 1095190864 # ASCII AGIP.
const SCHEMA_VERSION := 1
const SQLITE_VERSION := "3.51.0"
const MAX_PROFILE_ID_LENGTH := 64
const FILENAME := "profile.db"

var _db: Object
var _identity: String
var _diagnostic: String


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
	var connection: Object = ClassDB.instantiate(&"SQLite")
	if connection == null:
		return OpenResult.UNSUPPORTED
	connection.set(&"path", directory.path_join(FILENAME))
	connection.set(&"verbosity_level", 0)
	connection.set(&"foreign_keys", true)
	if not bool(connection.call(&"open_db")):
		return _failure(connection)
	var result := _acquire(connection, profile_id)
	if result != OpenResult.OPENED:
		connection.call(&"close_db")
		return result
	_db = connection
	_identity = profile_id
	return OpenResult.OPENED


func close() -> bool:
	if _db == null:
		return true
	if not bool(_db.call(&"close_db")):
		_failure(_db)
		return false
	_db = null
	_identity = ""
	return true


func identity() -> String:
	return _identity


func diagnostic() -> String:
	return _diagnostic


func mode() -> Dictionary:
	return _read_mode(_db) if _db != null else {}


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
	if version == SCHEMA_VERSION:
		var identity_result := _check_identity(connection, profile_id)
		if identity_result != OpenResult.OPENED:
			return identity_result
	if (not _query(connection, "PRAGMA locking_mode=EXCLUSIVE")
			or not _query(connection, "PRAGMA journal_mode=DELETE")
			or not _query(connection, "PRAGMA synchronous=EXTRA")
			or not _query(connection, "PRAGMA trusted_schema=OFF")):
		return _failure(connection)
	if _read_mode(connection) != {"sqlite": SQLITE_VERSION, "journal": "delete", "synchronous": 3, "locking": "exclusive"}:
		return OpenResult.UNSUPPORTED
	if not _query(connection, "BEGIN IMMEDIATE"):
		return _failure(connection)
	var result := _claim(connection, profile_id)
	if result == OpenResult.OPENED and not _query(connection, "COMMIT"):
		result = _failure(connection)
	if result != OpenResult.OPENED:
		_query(connection, "ROLLBACK")
	return result


func _claim(connection: Object, profile_id: String) -> OpenResult:
	var version: Variant = _value(connection, "PRAGMA user_version", "user_version")
	var app_id: Variant = _value(connection, "PRAGMA application_id", "application_id")
	if version == null or app_id == null:
		return _failure(connection)
	if not _recognized_header(version, app_id):
		return OpenResult.QUARANTINED
	if version == 0:
		var tables: Variant = _value(connection, "SELECT count(*) AS objects FROM sqlite_schema", "objects")
		if tables == null:
			return _failure(connection)
		if tables != 0:
			return OpenResult.QUARANTINED
		if (not _query(connection, "CREATE TABLE profile_identity (singleton INTEGER PRIMARY KEY CHECK(singleton=1),"
				+ "profile_id TEXT NOT NULL, lease_marker INTEGER NOT NULL CHECK(lease_marker IN (0,1))) STRICT")
				or not _query(connection, "INSERT INTO profile_identity VALUES (1, ?, 0)", [profile_id])
				or not _query(connection, "PRAGMA application_id=%d" % APPLICATION_ID)
				or not _query(connection, "PRAGMA user_version=%d" % SCHEMA_VERSION)):
			return _failure(connection)
	else:
		var identity_result := _check_identity(connection, profile_id)
		if identity_result != OpenResult.OPENED:
			return identity_result
	# A real write holds the approved exclusive SQLite lock after COMMIT.
	if not _query(connection, "UPDATE profile_identity SET lease_marker=1-lease_marker WHERE singleton=1"):
		return _failure(connection)
	return OpenResult.OPENED


func _check_identity(connection: Object, profile_id: String) -> OpenResult:
	var saved: Variant = _value(connection, "SELECT profile_id FROM profile_identity WHERE singleton=1", "profile_id")
	if saved == null and not str(connection.get(&"error_message")).is_empty():
		return _failure(connection)
	return OpenResult.OPENED if saved is String and saved == profile_id else OpenResult.QUARANTINED


func _failure(connection: Object) -> OpenResult:
	_diagnostic = str(connection.get(&"error_message"))
	return OpenResult.BUSY if "locked" in _diagnostic.to_lower() or "busy" in _diagnostic.to_lower() else OpenResult.FAILED


static func _recognized_header(version: int, app_id: int) -> bool:
	return (version == 0 and app_id == 0) or (version == SCHEMA_VERSION and app_id == APPLICATION_ID)


static func _read_mode(connection: Object) -> Dictionary:
	return {"sqlite": _value(connection, "SELECT sqlite_version() AS version", "version"),
		"journal": _value(connection, "PRAGMA journal_mode", "journal_mode"),
		"synchronous": _value(connection, "PRAGMA synchronous", "synchronous"),
		"locking": _value(connection, "PRAGMA locking_mode", "locking_mode")}


static func _value(connection: Object, sql: String, column: String) -> Variant:
	if not _query(connection, sql):
		return null
	var rows: Array = connection.get(&"query_result")
	return rows[0].get(column) if rows.size() == 1 else null


static func _query(connection: Object, sql: String, values: Array = []) -> bool:
	return bool(connection.call(&"query_with_bindings", sql, values))
