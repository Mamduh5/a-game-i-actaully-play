extends GutTest
## WP01 · local profile root convention (storage itself is WP13 behind WP05).


func test_default_profiles_root_without_args() -> void:
	assert_eq(AppPaths.profiles_root_from_args(PackedStringArray()), "user://profiles")


func test_profile_root_override_is_used() -> void:
	var args := PackedStringArray(["--profile-root=user://peer_b"])
	assert_eq(AppPaths.profiles_root_from_args(args), "user://peer_b")


func test_blank_override_falls_back_to_default() -> void:
	var args := PackedStringArray(["--profile-root=   "])
	assert_eq(AppPaths.profiles_root_from_args(args), AppPaths.DEFAULT_PROFILES_ROOT)


func test_unrelated_args_are_ignored() -> void:
	var args := PackedStringArray(["--profile-rootx=user://wrong", "--agip-exit-after-boot"])
	assert_eq(AppPaths.profiles_root_from_args(args), AppPaths.DEFAULT_PROFILES_ROOT)


func test_editor_runs_use_the_development_user_dir() -> void:
	assert_eq(OS.get_user_data_dir().get_file(), "AGameIActuallyPlay-dev")
