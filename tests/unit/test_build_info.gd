extends GutTest
## WP01 · build identity used by logs, MCP identity checks and release inspection.


func test_flavor_is_player_without_editor_or_dev_feature() -> void:
	assert_eq(BuildInfo.flavor_for(PackedStringArray(["release", "template"])), BuildInfo.FLAVOR_PLAYER)


func test_flavor_is_dev_with_dev_feature() -> void:
	assert_eq(BuildInfo.flavor_for(PackedStringArray(["debug", "template", BuildInfo.DEV_FEATURE])), BuildInfo.FLAVOR_DEV)


func test_editor_feature_wins_over_dev_feature() -> void:
	assert_eq(BuildInfo.flavor_for(PackedStringArray([BuildInfo.DEV_FEATURE, "editor"])), BuildInfo.FLAVOR_EDITOR)


func test_empty_feature_set_is_player() -> void:
	assert_eq(BuildInfo.flavor_for(PackedStringArray()), BuildInfo.FLAVOR_PLAYER)


func test_boot_line_has_prefix_and_sorted_keys() -> void:
	var line := BuildInfo.format_boot_line({"zeta": "1", "alpha": "two words", "mid": true})
	assert_eq(line, "AGIP_BOOT alpha=two_words mid=true zeta=1")


func test_collected_identity_names_this_project() -> void:
	var info := BuildInfo.collect()
	assert_eq(info["app"], "A Game I Actually Play")
	assert_eq(info["renderer"], "gl_compatibility")
	assert_true(str(info["engine"]).begins_with("4.7"), "engine %s should be 4.7.x" % info["engine"])


func test_test_runner_sees_development_tooling() -> void:
	# GUT runs inside the editor binary, so tooling must be visible here. The
	# player-export counterpart is asserted by tools/inspect_pack.ps1 and the
	# exported boot line, not by this suite.
	var info := BuildInfo.collect()
	assert_eq(info["flavor"], BuildInfo.FLAVOR_EDITOR)
	assert_eq(info["has_gut"], "true")
	assert_eq(info["has_tests"], "true")


func test_user_flag_detection_is_exact() -> void:
	var args := PackedStringArray(["--agip-exit-after-boot", "--other"])
	assert_true(BuildInfo.has_user_flag(args, "--agip-exit-after-boot"))
	assert_false(BuildInfo.has_user_flag(args, "--agip-exit"))
