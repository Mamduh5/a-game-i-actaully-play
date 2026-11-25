class_name BuildInfo
extends RefCounted
## Read-only identity of the running build.
##
## Used for startup logs, MCP project-identity checks and evidence records.
## It owns no gameplay state and never participates in ordering, RNG or awards.

const FLAVOR_EDITOR := "editor"
const FLAVOR_DEV := "dev"
const FLAVOR_PLAYER := "player"

## Custom export feature carried only by the development export preset.
const DEV_FEATURE := "agip_dev"

## Paths that must be absent from the player export (TDS §9). Reported, never loaded.
const TOOLING_PROBES := {
	"dev_fixtures": "res://dev/fixtures/harness_probe.tscn",
	"gut": "res://addons/gut/gut_cmdln.gd",
	"mcp_runtime": "res://addons/godot_mcp_toolkit/runtime/mcp_runtime_server.gd",
	"tests": "res://tests/unit/test_build_info.gd",
}

const BOOT_PREFIX := "AGIP_BOOT"


## Pure flavor decision from a feature set. "editor" wins because an editor-launched
## game carries both the editor feature and any project feature tags.
static func flavor_for(features: PackedStringArray) -> String:
	if features.has("editor"):
		return FLAVOR_EDITOR
	if features.has(DEV_FEATURE):
		return FLAVOR_DEV
	return FLAVOR_PLAYER


static func current_features() -> PackedStringArray:
	var present := PackedStringArray()
	for feature: String in ["editor", DEV_FEATURE, "debug", "release", "template"]:
		if OS.has_feature(feature):
			present.append(feature)
	return present


static func has_user_flag(user_args: PackedStringArray, flag: String) -> bool:
	return user_args.has(flag)


## Collects the identity of this process as a flat dictionary of strings.
static func collect() -> Dictionary:
	var features := current_features()
	var info := {
		"app": str(ProjectSettings.get_setting("application/config/name", "")),
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"engine": str(Engine.get_version_info().get("string", "")),
		"flavor": flavor_for(features),
		"features": ",".join(features),
		"debug_build": str(OS.is_debug_build()).to_lower(),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"user_dir": OS.get_user_data_dir().get_file(),
		"profiles_root": AppPaths.profiles_root(),
	}
	for key: String in TOOLING_PROBES:
		info["has_" + key] = str(ResourceLoader.exists(TOOLING_PROBES[key])).to_lower()
	return info


## One grep-friendly line with keys in sorted order.
static func format_boot_line(info: Dictionary) -> String:
	var keys: Array = info.keys()
	keys.sort()
	var parts := PackedStringArray([BOOT_PREFIX])
	for key: Variant in keys:
		parts.append("%s=%s" % [key, str(info[key]).replace(" ", "_")])
	return " ".join(parts)


static func format_display(info: Dictionary) -> String:
	return "%s %s · %s · Godot %s" % [info.get("app", ""), info.get("version", ""), info.get("flavor", ""), info.get("engine", "")]
