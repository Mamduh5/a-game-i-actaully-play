extends GutTest

const Result := ProfileStore.OpenResult


func test_profile_identity_is_a_bounded_path_token() -> void:
	for profile_id: String in ["", ".", "a/../b", "A", "co:guest", "guest\\other", "é", "a".repeat(65)]:
		assert_false(ProfileStore.valid_identity(profile_id), profile_id)
		assert_eq(ProfileStore.new().open(profile_id), Result.INVALID_ID)
	assert_true(ProfileStore.valid_identity("guest-a_02"))
	assert_true(ProfileStore.valid_identity("a".repeat(64)))


func test_native_profile_owns_one_identity_and_reopens_after_close() -> void:
	if not OS.has_feature("windows"):
		assert_eq(ProfileStore.new().open("host"), Result.UNSUPPORTED)
		return
	var folder := DirAccess.create_temp("agip-profile")
	assert_not_null(folder)
	var root := folder.get_current_dir()
	var host := ProfileStore.new()
	var guest := ProfileStore.new()
	assert_eq(host.open("host", root), Result.OPENED)
	assert_eq(host.mode(), {"sqlite": "3.51.0", "journal": "delete", "synchronous": 3, "locking": "exclusive"})
	assert_eq(host.identity(), "host")
	assert_eq(host.open("guest", root), Result.HELD)
	assert_eq(guest.open("guest", root), Result.OPENED)
	assert_true(guest.close())
	assert_true(host.close())
	assert_eq(host.identity(), "")
	assert_true(host.mode().is_empty())
	assert_eq(host.open("host", root), Result.OPENED)
	assert_true(host.close())
	var source := root.path_join("profile-host/profile.db")
	var target := root.path_join("profile-guest/profile.db")
	assert_eq(DirAccess.copy_absolute(source, target), OK)
	assert_eq(guest.open("guest", root), Result.QUARANTINED)
	assert_eq(guest.identity(), "")


func test_unrecognized_schema_is_quarantined_without_modification() -> void:
	if not OS.has_feature("windows"):
		return
	var folder := DirAccess.create_temp("agip-future-profile")
	var root := folder.get_current_dir()
	var store := ProfileStore.new()
	assert_eq(store.open("future", root), Result.OPENED)
	assert_true(store.close())
	var path := root.path_join("profile-future/profile.db")
	var connection: Object = ClassDB.instantiate(&"SQLite")
	connection.set(&"path", path)
	assert_true(bool(connection.call(&"open_db")))
	assert_true(bool(connection.call(&"query", "PRAGMA user_version=999")))
	assert_true(bool(connection.call(&"close_db")))
	var before := FileAccess.get_sha256(path)
	assert_eq(store.open("future", root), Result.QUARANTINED)
	assert_eq(FileAccess.get_sha256(path), before)
