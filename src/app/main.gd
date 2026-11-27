extends Control
## The active authority owns gameplay and durable quit settlement.

## User argument that prints identity and quits with exit code 0 (headless smoke checks).
const EXIT_AFTER_BOOT_ARG := "--agip-exit-after-boot"
const ORDINARY_EXPOSURE_TEXT := "Some ordinary earnings from the previous run may be missing.\nThe amount could not be determined."
const SOLO_CONTROLS := "W A S D or right-click to move  ·  Left-click to use your ability"
const ROSTER: CatalogBundle = preload("res://src/catalog/starter_roster.tres")

@onready var _identity_label: Label = %IdentityLabel
@onready var _layout: VBoxContainer = $Layout
@onready var _entry: VBoxContainer = %ProfileEntry
@onready var _profile_choice: HBoxContainer = %ProfileChoice
@onready var _profile_name: LineEdit = %ProfileName
@onready var _open_profile_button: Button = %OpenProfile
@onready var _preparation: HBoxContainer = %RunChoice
@onready var _hero_choice: OptionButton = %HeroChoice
@onready var _weapon_choice: OptionButton = %WeaponChoice
@onready var _start_button: Button = %StartSolo
@onready var _status: Label = %ProfileStatus
var _profile: ProfileStore
var _authority: RunAuthority
var _progression: ProfileProgression
var _solo: SoloStarterRun
var _starting: SoloStarterRun
var _owns_profile: bool
var _return_pending: bool
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
		return
	if get_parent() == get_tree().root:
		_identity_label.hide()
		_entry.show()
		_profile_name.max_length = ProfileStore.MAX_PROFILE_ID_LENGTH
		_open_profile_button.pressed.connect(_open_local_profile)
		_profile_name.text_submitted.connect(func(_value: String) -> void: _open_local_profile())
		_start_button.pressed.connect(_start_solo)


func _open_local_profile() -> void:
	if _profile != null or _quit_requested:
		return
	var id := _profile_name.text.strip_edges()
	if not ProfileStore.valid_identity(id):
		_status.text = "Use lowercase letters, numbers, hyphens or underscores for the profile ID."
		return
	var profile := ProfileStore.new()
	match profile.open(id):
		ProfileStore.OpenResult.OPENED: pass
		ProfileStore.OpenResult.BUSY:
			_status.text = "This profile is already open. Close the other session and try again."
			return
		ProfileStore.OpenResult.UNSUPPORTED:
			_status.text = "Local profiles require the native Windows build."
			return
		_:
			_status.text = "This profile could not be opened."
			return
	var catalog := ROSTER.compile()
	var progression := ProfileProgression.open(profile, catalog)
	if progression == null or not bind_profile(profile):
		profile.close()
		_status.text = "Profile data could not be read."
		return
	_owns_profile = true
	_progression = progression
	_profile_choice.hide()
	var unlocked := progression.preparation_unlocks()
	_fill_choice(_hero_choice, RunPreparation.available(catalog, CatalogEntry.Kind.HERO, unlocked))
	_fill_choice(_weapon_choice, RunPreparation.available(catalog, CatalogEntry.Kind.WEAPON, unlocked))
	_preparation.show()
	_refresh_preparation_status()
	_start_button.grab_focus()


static func _fill_choice(choice: OptionButton, available: Array[StringName]) -> void:
	choice.clear()
	for id: StringName in available:
		choice.add_item(ROSTER.display_names.get(id, String(id)))
		choice.set_item_metadata(choice.item_count - 1, id)
	if not available.is_empty():
		choice.select(0)


func _start_solo() -> void:
	if _quit_requested or _progression == null or _solo != null:
		return
	if _starting == null:
		var candidates: Array[StringName] = []
		candidates.resize(RunPreparation.CANDIDATE_SLOTS)
		candidates.fill(&"")
		var hero: StringName = _hero_choice.get_selected_metadata()
		var weapon: StringName = _weapon_choice.get_selected_metadata()
		_starting = SoloStarterRun.assemble(_profile, _progression.prepare(hero, weapon, [&"", &""], candidates))
	if _starting == null:
		_status.text = "The run could not be prepared."
		return
	if not bind_run(_starting.authority):
		_hero_choice.disabled = true
		_weapon_choice.disabled = true
		_status.text = "The run could not be recorded. Select Start solo to retry."
		return
	_solo = _starting
	_starting = null
	_layout.hide()
	_solo.end_requested.connect(_return_to_preparation)
	add_child(_solo)


func _return_to_preparation() -> void:
	if _quit_requested or _solo == null:
		return
	_return_pending = true
	_solo.freeze_for_exit()
	if not _authority.settle_orderly_quit():
		_retry_at = Time.get_ticks_msec() + 1000
		set_process(true)
		return
	_solo.queue_free()
	_solo = null
	_authority = null
	_return_pending = false
	_hero_choice.disabled = false
	_weapon_choice.disabled = false
	_refresh_preparation_status()
	_layout.show()
	_start_button.grab_focus()
	set_process(false)


func _refresh_preparation_status() -> void:
	var saved := _profile.balance(StarterEncounter.COMMON_CURRENCY)
	var shown := saved.magnitude_text() if saved != null else "Unavailable"
	_status.text = "Profile %s  ·  Common currency %s\n%s" % [_profile.identity(), shown, SOLO_CONTROLS]


func bind_profile(profile: ProfileStore) -> bool:
	if not is_node_ready() or _profile != null or _authority != null or _quit_requested:
		return false
	var settlement := ProfileOrdinarySession.reopen_status(profile)
	if settlement == ProfileOrdinarySession.ReopenStatus.UNAVAILABLE:
		return false
	_profile = profile
	if settlement == ProfileOrdinarySession.ReopenStatus.POSSIBLE_EXPOSURE:
		_identity_label.text = ORDINARY_EXPOSURE_TEXT if _entry.visible else _identity_label.text + "\n\n" + ORDINARY_EXPOSURE_TEXT
		_identity_label.show()
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
	if _solo != null:
		_solo.freeze_for_exit()
	var pending: RunAuthority = _authority if _starting == null else _starting.authority
	if pending == null or pending.settle_orderly_quit():
		set_process(false)
		get_tree().quit()
		return
	if _solo != null:
		_solo.hide()
		_layout.show()
		_entry.hide()
	_identity_label.text = "Saving run earnings. Retrying before exit.\nForcing the game closed can lose uncommitted earnings."
	_identity_label.show()
	_retry_at = Time.get_ticks_msec() + 1000
	set_process(true)


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() >= _retry_at:
		if _quit_requested:
			request_orderly_quit()
		elif _return_pending:
			_return_to_preparation()


func _exit_tree() -> void:
	if _starting != null:
		_starting.free()
	if _owns_profile:
		_profile.close()
