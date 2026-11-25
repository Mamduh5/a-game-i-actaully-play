extends Control
## DEVELOPMENT FIXTURE — harness probe. Not gameplay.
##
## Gives MCP and the export checks a minimal rendered target: a GUI button that
## counts presses arriving through the normal input route (viewport → Control
## hit testing → BaseButton.pressed). Excluded from the player export.

signal probe_pressed(count: int)

var press_count: int = 0

@onready var _button: Button = %ProbeButton
@onready var _status: Label = %StatusLabel


func _ready() -> void:
	_button.pressed.connect(_on_probe_button_pressed)
	_refresh()
	print("AGIP_PROBE ready flavor=%s" % BuildInfo.flavor_for(BuildInfo.current_features()))


func _on_probe_button_pressed() -> void:
	press_count += 1
	_refresh()
	print("AGIP_PROBE pressed count=%d" % press_count)
	probe_pressed.emit(press_count)


func _refresh() -> void:
	_status.text = "Probe presses: %d" % press_count
