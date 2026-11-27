extends Control
## The active authority owns gameplay and durable quit settlement.

## User argument that prints identity and quits with exit code 0 (headless smoke checks).
const EXIT_AFTER_BOOT_ARG := "--agip-exit-after-boot"
const ORDINARY_EXPOSURE_TEXT := "Some ordinary earnings from the previous run may be missing.\nThe amount could not be determined."

@onready var _identity_label: Label = %IdentityLabel
var _profile: ProfileStore
var _authority: RunAuthority
var _quit_requested := false
var _retry_at: int


func _ready() -> void:
	get_tree().auto_accept_quit = false
	set_process(false)
	var info := BuildInfo.collect()
	print(BuildInfo.format_boot_line(info))
	_identity_label.text = BuildInfo.format_display(info)
	if BuildInfo.has_user_flag(OS.get_cmdline_user_args(), EXIT_AFTER_BOOT_ARG):
		get_tree().quit.call_deferred(0)


func bind_profile(profile: ProfileStore) -> bool:
	if not is_node_ready() or _profile != null or _authority != null or _quit_requested:
		return false
	var settlement := ProfileOrdinarySession.reopen_status(profile)
	if settlement == ProfileOrdinarySession.ReopenStatus.UNAVAILABLE:
		return false
	_profile = profile
	if settlement == ProfileOrdinarySession.ReopenStatus.POSSIBLE_EXPOSURE:
		_identity_label.text += "\n\n" + ORDINARY_EXPOSURE_TEXT
	return true


func bind_run(authority: RunAuthority) -> bool:
	if authority == null or authority.checkpoint().is_empty() or _authority != null or _quit_requested:
		return false
	if _profile != null and not authority.begin_ordinary_session(_profile):
		return false
	_authority = authority
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_node_ready():
		request_orderly_quit()


func request_orderly_quit() -> void:
	_quit_requested = true
	if _authority == null or _authority.settle_orderly_quit():
		set_process(false)
		get_tree().quit()
		return
	_identity_label.text = "Saving run earnings. Retrying before exit.\nForcing the game closed can lose uncommitted earnings."
	_retry_at = Time.get_ticks_msec() + 1000
	set_process(true)


func _process(_delta: float) -> void:
	if _quit_requested and Time.get_ticks_msec() >= _retry_at:
		request_orderly_quit()
