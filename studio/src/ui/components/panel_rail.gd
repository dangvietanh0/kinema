extends PanelContainer
## Right-edge panel rail.
##
## The stage owns the width; panels are one tap away instead of permanently
## docked. Three 44 dp icon buttons open Scene, Properties or Rig in the
## overlay flyout. The active page keeps the same bright-edge treatment as the
## left tool rail.

signal page_requested(page: String)

const Tokens = preload("res://src/ui/tokens.gd")

const PAGES := [
	{"id": "scene", "label": "Scene", "icon": "layers"},
	{"id": "inspector", "label": "Properties", "icon": "sliders-horizontal"},
	{"id": "rig", "label": "Rig", "icon": "bone"},
]

var _buttons: Dictionary = {}


func _ready() -> void:
	_build()


func _build() -> void:
	if not _buttons.is_empty():
		return
	custom_minimum_size = Vector2(Tokens.PANEL_RAIL_WIDTH, 0.0)
	# No outline (2026-11-01 black-chrome override): the rail reads as a raised
	# column, and the active page keeps its bright-edge treatment instead.
	var style := Kit.flat_style(Kit.SURFACE_2, 0, Color(0, 0, 0, 0), 0)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 4
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	var descriptions := {
		"scene": "Open the scene outliner",
		"inspector": "Open the properties inspector",
		"rig": "Open the rig page",
	}
	for entry in PAGES:
		var data: Dictionary = entry
		var page := str(data.get("id", ""))
		var button := Kit.icon_button(
			str(data.get("icon", "layers")),
			str(data.get("label", page)),
			44,
			20
		)
		# Icon-only buttons must expose a stable name to assistive technology;
		# the tooltip stays for pointer users.
		button.accessibility_name = str(data.get("label", page))
		button.accessibility_description = str(descriptions.get(page, ""))
		button.pressed.connect(func() -> void: page_requested.emit(page))
		column.add_child(button)
		_buttons[page] = button

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)


func set_page(page: String, open: bool) -> void:
	for id in _buttons:
		var button: Button = _buttons[id]
		Kit.set_icon_active(button, open and str(id) == page, "left")


func page_button(page: String) -> Button:
	return _buttons.get(page) as Button


func page_ids() -> Array:
	return _buttons.keys()
