class_name RunProgressionPanel
extends PanelContainer
## Ordinary GUI controls for preparing a seat and choosing a frozen reward.
## The run owner binds these requests and decides when to publish the result.

signal preparation_requested(preparation: RunPreparation)
signal choice_requested(ordinal: int, id: StringName)
signal compensation_requested(ordinal: int)
signal dismissed

var _catalog: DefinitionCatalog
var _unlocked: Dictionary[StringName, bool] = {}
var _names: Dictionary[StringName, String] = {}
var _content: VBoxContainer
var _feedback: Label
var _hero: OptionButton
var _weapon: OptionButton
var _runes: Array[OptionButton] = []
var _candidates: Array[OptionButton] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.x = 320.0
	var margins := MarginContainer.new()
	for direction: String in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + direction, 14)
	add_child(margins)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	margins.add_child(_content)


func show_preparation(catalog: DefinitionCatalog, unlocked: Dictionary[StringName, bool],
		display_names: Dictionary[StringName, String]) -> void:
	_catalog = catalog
	_unlocked = unlocked.duplicate()
	_names = display_names.duplicate()
	_clear("Prepare for the run")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 280.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var fields := VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(fields)
	_hero = _picker(fields, "Hero", CatalogEntry.Kind.HERO)
	_weapon = _picker(fields, "Weapon", CatalogEntry.Kind.WEAPON)
	for slot: int in RunPreparation.RUNE_SLOTS:
		_runes.append(_picker(fields, "Rune %d" % (slot + 1), CatalogEntry.Kind.RUNE, "Empty"))
	for slot: int in RunPreparation.CANDIDATE_SLOTS:
		_candidates.append(_picker(fields, "Candidate %d" % (slot + 1), CatalogEntry.Kind.POWER, "Wildcard"))
	var confirm := Button.new()
	confirm.text = "Confirm preparation"
	confirm.disabled = _hero.item_count == 0 or _weapon.item_count == 0
	confirm.pressed.connect(_request_preparation)
	_content.add_child(confirm)
	_add_feedback()
	show()


func show_offer(offer: RunRewardQueue.Offer, display_names: Dictionary[StringName, String]) -> void:
	if offer == null:
		return
	_names = display_names.duplicate()
	_clear("Reward %d" % offer.ordinal)
	for id: StringName in offer.options:
		var option := Button.new()
		option.text = _option_text(offer, id)
		option.pressed.connect(choice_requested.emit.bind(offer.ordinal, id))
		_content.add_child(option)
	if offer.options.is_empty():
		var compensation := Button.new()
		compensation.text = "Claim compensation"
		compensation.pressed.connect(compensation_requested.emit.bind(offer.ordinal))
		_content.add_child(compensation)
	var later := Button.new()
	later.text = "Choose later"
	later.pressed.connect(dismissed.emit)
	_content.add_child(later)
	_add_feedback()
	show()


func show_feedback(message: String) -> void:
	if _feedback != null:
		_feedback.text = message
		_feedback.visible = not message.is_empty()


func _clear(title: String) -> void:
	for old: Node in _content.get_children():
		_content.remove_child(old)
		old.queue_free()
	_runes.clear()
	_candidates.clear()
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 20)
	_content.add_child(heading)


func _add_feedback() -> void:
	_feedback = Label.new()
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.hide()
	_content.add_child(_feedback)


func _picker(parent: VBoxContainer, label: String, kind: CatalogEntry.Kind, blank: String = "") -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var title := Label.new()
	title.custom_minimum_size.x = 100.0
	title.text = label
	row.add_child(title)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)
	if not blank.is_empty():
		picker.add_item(blank)
		picker.set_item_metadata(0, &"")
	for id: StringName in RunPreparation.available(_catalog, kind, _unlocked):
		picker.add_item(_display(id))
		picker.set_item_metadata(picker.item_count - 1, id)
	return picker


func _request_preparation() -> void:
	var runes: Array[StringName] = []
	for slot: OptionButton in _runes:
		runes.append(slot.get_selected_metadata())
	var candidates: Array[StringName] = []
	for slot: OptionButton in _candidates:
		candidates.append(slot.get_selected_metadata())
	var result := RunPreparation.select(_catalog, _hero.get_selected_metadata(), _weapon.get_selected_metadata(),
		runes, candidates, _unlocked)
	if result == null:
		show_feedback("Choose different runes and powers for the filled slots.")
		return
	preparation_requested.emit(result)


func _option_text(offer: RunRewardQueue.Offer, id: StringName) -> String:
	match offer.kind:
		RunRewardQueue.Kind.POWER: return "%s · Rank %d" % [_display(id), offer.options[id]]
		RunRewardQueue.Kind.OVERFLOW:
			var step: int = RunRewardQueue.OVERFLOW_STEPS[offer.options[id] - 1]
			return "%s +%g%%" % [_display(id), step / 100.0]
		RunRewardQueue.Kind.UTILITY: return "1 Trade Shard"
	return _display(id)


func _display(id: StringName) -> String:
	match id:
		&"overflow.damage": return "Damage"
		&"overflow.max_hp": return "Maximum HP"
		&"overflow.physical_defense": return "Physical defense"
	return _names.get(id, String(id))
