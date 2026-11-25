class_name AppPaths
extends RefCounted
## Local data locations.
##
## Player and development flavors use different user directories through the
## project setting feature overrides of application/config/custom_user_dir_name,
## so development runs never touch a player's profiles. Profile storage itself
## belongs to WP13 behind the WP05 storage gate; this only fixes where it lives.

const DEFAULT_PROFILES_ROOT := "user://profiles"

## Lets separate local processes (for example two native peers) use isolated
## profile roots: `-- --profile-root=<absolute or user:// path>`.
const PROFILES_ROOT_ARG := "--profile-root="


static func profiles_root_from_args(user_args: PackedStringArray) -> String:
	for arg: String in user_args:
		if arg.begins_with(PROFILES_ROOT_ARG):
			var value := arg.substr(PROFILES_ROOT_ARG.length()).strip_edges()
			if not value.is_empty():
				return value
	return DEFAULT_PROFILES_ROOT


static func profiles_root() -> String:
	return profiles_root_from_args(OS.get_cmdline_user_args())
