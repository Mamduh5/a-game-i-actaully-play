extends GutTest
## WP01 · project baseline guards: renderer, typed GDScript, entry scene and release split.


func test_compatibility_renderer_is_selected() -> void:
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "gl_compatibility")
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile"), "gl_compatibility")


func test_untyped_declarations_are_errors() -> void:
	# 2 == error. Vendored add-ons are covered by the default exclude_addons setting.
	assert_eq(int(ProjectSettings.get_setting("debug/gdscript/warnings/untyped_declaration")), 2)


func test_main_scene_loads_and_instantiates() -> void:
	var path := str(ProjectSettings.get_setting("application/run/main_scene"))
	assert_eq(path, "res://src/app/main.tscn")
	var packed := load(path) as PackedScene
	assert_not_null(packed, "main scene must load")
	var root := packed.instantiate()
	assert_not_null(root.get_node_or_null("%IdentityLabel"), "identity label must exist")
	root.free()


func test_dev_fixture_loads() -> void:
	var packed := load("res://dev/fixtures/harness_probe.tscn") as PackedScene
	assert_not_null(packed, "dev fixture must load in development runs")


func test_player_preset_excludes_development_tooling() -> void:
	var presets := ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK)
	var player := _find_preset(presets, "Windows Player")
	assert_ne(player, "", "Windows Player preset must exist")
	var exclude := str(presets.get_value(player, "exclude_filter", ""))
	for required: String in ["addons/gut/*", "addons/godot_mcp_toolkit/*", "tests/*", "dev/*", ".gutconfig.json"]:
		assert_string_contains(exclude, required)
	assert_eq(str(presets.get_value(player, "custom_features", "")), "", "player must not carry the dev feature")


func test_dev_preset_carries_dev_feature() -> void:
	var presets := ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK)
	var dev := _find_preset(presets, "Windows Dev")
	assert_ne(dev, "", "Windows Dev preset must exist")
	var exclude := str(presets.get_value(dev, "exclude_filter", ""))
	for required: String in ["addons/gut/*", "addons/godot_mcp_toolkit/*", "tests/*", ".gutconfig.json"]:
		assert_string_contains(exclude, required)
	assert_eq(str(presets.get_value(dev, "custom_features", "")), BuildInfo.DEV_FEATURE)


func _find_preset(presets: ConfigFile, preset_name: String) -> String:
	for section: String in presets.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			if str(presets.get_value(section, "name", "")) == preset_name:
				return section
	return ""
