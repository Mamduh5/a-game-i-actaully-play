extends Control
## Native shell entry scene. Shows build identity; owns no gameplay state.

## User argument that prints identity and quits with exit code 0 (headless smoke checks).
const EXIT_AFTER_BOOT_ARG := "--agip-exit-after-boot"

@onready var _identity_label: Label = %IdentityLabel


func _ready() -> void:
	var info := BuildInfo.collect()
	print(BuildInfo.format_boot_line(info))
	_identity_label.text = BuildInfo.format_display(info)
	if BuildInfo.has_user_flag(OS.get_cmdline_user_args(), EXIT_AFTER_BOOT_ARG):
		get_tree().quit.call_deferred(0)
