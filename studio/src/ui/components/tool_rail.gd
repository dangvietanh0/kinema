extends PanelContainer
## The transform tool rail.
##
## A vertical column on studio and desktop, a horizontal strip on compact
## screens. When a compact window is too short for the strip, the four tools
## collapse into one 44x44 Tools button that opens the same list.

signal tool_selected(tool: String)
signal frame_requested
signal add_requested

const TOOLS := [
	{"id": "select", "icon": "tool-select", "label": "Select", "hint": "Tap to pick"},
	{"id": "move", "icon": "tool-move", "label": "Move", "hint": "Drag an axis"},
	{"id": "rotate", "icon": "tool-rotate", "label": "Rotate", "hint": "Drag an axis"},
	{"id": "scale", "icon": "tool-scale", "label": "Scale", "hint": "Drag an axis"},
]

const COLLAPSE_HEIGHT := 480.0

var _mode := "studio"
var _tool := "select"
var _box: BoxContainer
var _buttons: Dictionary = {}
var _tools_button: Button
var _tools_menu: PopupMenu
var _collapsed := false
var _frame_button: Button
var _add_button: Button
var _divider: ColorRect
var _available_height := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_tools_menu = PopupMenu.new()
	_tools_menu.add_theme_font_override("font", Kit.font_regular)
	_tools_menu.id_pressed.connect(_on_tools_menu_id)
	add_child(_tools_menu)
	_rebuild()
	_apply_tool_state()


func set_mode(mode: String) -> void:
	var next := mode if mode in ["compact", "studio", "desktop"] else "studio"
	if next == _mode:
		return
	_mode = next
	_rebuild()
	_apply_tool_state()


func mode() -> String:
	return _mode


func set_tool(tool: String) -> void:
	_tool = tool
	_apply_tool_state()


func current_tool() -> String:
	return _tool


func set_available_height(value: float) -> void:
	_available_height = value
	var should_collapse := _mode == "compact" and value > 0.0 and value < COLLAPSE_HEIGHT
	if should_collapse != _collapsed:
		_collapsed = should_collapse
		_apply_tool_state()


func rail_width() -> float:
	return 0.0 if _mode == "compact" else 48.0


func _rebuild() -> void:
	for child in get_children():
		if child is BoxContainer:
			remove_child(child)
			child.queue_free()
	if _box != null and is_instance_valid(_box):
		pass
	_box = HBoxContainer.new() if _mode == "compact" else VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2 if _mode == "compact" else 4)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER if _mode == "compact" else BoxContainer.ALIGNMENT_BEGIN
	add_child(_box)

	_buttons.clear()
	_tools_button = null
	_divider = null

	for tool in TOOLS:
		var entry: Dictionary = tool
		var button := Kit.icon_button(
			str(entry["icon"]),
			"%s  ·  %s" % [str(entry["label"]), str(entry["hint"])],
			44,
			20
		)
		button.set_meta("tool_id", str(entry["id"]))
		button.pressed.connect(func() -> void: tool_selected.emit(str(entry["id"])))
		_box.add_child(button)
		_buttons[str(entry["id"])] = button

	_tools_button = Kit.icon_button("mouse-pointer-2", "Tools", 44, 20)
	_tools_button.visible = false
	_tools_button.pressed.connect(_open_tools_menu)
	_box.add_child(_tools_button)

	if _mode != "compact":
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box.add_child(spacer)
		_divider = Kit.vsep()
		_box.add_child(_divider)
	else:
		var h_spacer := Control.new()
		h_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box.add_child(h_spacer)
		_divider = Kit.hairline(true)
		_box.add_child(_divider)

	_frame_button = Kit.icon_button("focus", "Frame selection", 44, 20)
	_frame_button.pressed.connect(func() -> void: frame_requested.emit())
	_box.add_child(_frame_button)

	_add_button = Kit.icon_button("plus", "Add object", 44, 20)
	_add_button.add_theme_color_override("icon_normal_color", Kit.TEXT)
	_add_button.add_theme_color_override("icon_hover_color", Kit.FOCUS_BRIGHT)
	_add_button.add_theme_color_override("icon_pressed_color", Kit.FOCUS_BRIGHT)
	_add_button.pressed.connect(func() -> void: add_requested.emit())
	_box.add_child(_add_button)

	var style := Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT, 0)
	if _mode == "compact":
		style.border_width_bottom = 1
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		custom_minimum_size = Vector2(0, 48)
	else:
		style.border_width_right = 1
		style.content_margin_top = 2
		style.content_margin_bottom = 8
		custom_minimum_size = Vector2(rail_width(), 0)
	add_theme_stylebox_override("panel", style)
	_apply_tool_state()


func _apply_tool_state() -> void:
	var edge := "bottom" if _mode == "compact" else "left"
	for id in _buttons:
		var button: Button = _buttons[id]
		Kit.set_icon_active(button, str(id) == _tool, edge)
	if _tools_button != null:
		_tools_button.visible = _collapsed
		if _collapsed:
			Kit.set_icon_active(_tools_button, true, edge)
	for id in _buttons:
		var button: Button = _buttons[id]
		button.visible = not _collapsed


func _open_tools_menu() -> void:
	_tools_menu.clear()
	for tool in TOOLS:
		var entry: Dictionary = tool
		_tools_menu.add_item("%s      %s" % [str(entry["label"]), str(entry["hint"])])
		_tools_menu.set_item_metadata(_tools_menu.get_item_count() - 1, str(entry["id"]))
	var rect := _tools_button.get_global_rect()
	_tools_menu.position = Vector2i(int(rect.position.x + rect.size.x), int(rect.position.y))
	_tools_menu.popup()


func _on_tools_menu_id(id: int) -> void:
	var index := _tools_menu.get_item_index(id)
	if index < 0:
		return
	var tool := str(_tools_menu.get_item_metadata(index))
	if tool != "":
		tool_selected.emit(tool)
