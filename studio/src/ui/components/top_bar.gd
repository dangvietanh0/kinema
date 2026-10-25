extends PanelContainer
## The workbench header.
##
## Three arrangements share one set of actions:
##   compact  48 dp - back, title, undo/redo, overflow.
##   studio   44 dp - back, title, undo/redo, render, settings, overflow.
##   desktop  36 dp - a real menu bar, then undo/redo, the renderer chip and
##                    settings. The 36 dp row is a mouse target; every action
##                    that a finger reaches keeps a 44 dp target.
##
## The bar only reports intent. The editor owns every action.

signal action_requested(action: String)
signal layout_requested
signal renderer_requested

const ACTION_BACK := "back"
const ACTION_UNDO := "undo"
const ACTION_REDO := "redo"
const ACTION_SAVE := "save"
const ACTION_RENDER := "render"
const ACTION_SETTINGS := "settings"
const ACTION_PERFORMANCE := "performance"
const ACTION_IMPORT := "import"
const ACTION_FRAME := "frame"
const ACTION_DUPLICATE := "duplicate"
const ACTION_DELETE := "delete"
const ACTION_KEYS := "keys"
const ACTION_FRAME_ALL := "frame_all"
const ACTION_TOGGLE_GRID := "toggle_grid"
const ACTION_RENDER_STILL := "render_still"
const ACTION_RENDER_SEQUENCE := "render_sequence"
const ACTION_RESET_LAYOUT := "reset_layout"
const ACTION_ABOUT := "about"
const ACTION_SHORTCUTS := "shortcuts"

const MENUS := [
	{
		"label": "Kinema",
		"items": [
			{"id": ACTION_ABOUT, "text": "About Kinema"},
			{"id": ACTION_SHORTCUTS, "text": "Keyboard shortcuts"},
		],
	},
	{
		"label": "Project",
		"items": [
			{"id": ACTION_SAVE, "text": "Save", "shortcut": "Ctrl+S"},
			{"id": ACTION_IMPORT, "text": "Import model"},
			{"id": ACTION_BACK, "text": "Close project"},
		],
	},
	{
		"label": "Edit",
		"items": [
			{"id": ACTION_UNDO, "text": "Undo", "shortcut": "Ctrl+Z"},
			{"id": ACTION_REDO, "text": "Redo", "shortcut": "Ctrl+Y"},
			{"id": ACTION_DUPLICATE, "text": "Duplicate"},
			{"id": ACTION_DELETE, "text": "Delete"},
		],
	},
	{
		"label": "View",
		"items": [
			{"id": ACTION_FRAME, "text": "Frame selection", "shortcut": "F"},
			{"id": ACTION_FRAME_ALL, "text": "Frame all"},
			{"id": ACTION_TOGGLE_GRID, "text": "Toggle grid"},
			{"id": ACTION_RESET_LAYOUT, "text": "Fit interface to screen"},
		],
	},
	{
		"label": "Render",
		"items": [
			{"id": ACTION_RENDER, "text": "Render settings"},
			{"id": ACTION_RENDER_STILL, "text": "Quick still"},
			{"id": ACTION_RENDER_SEQUENCE, "text": "PNG sequence"},
		],
	},
	{
		"label": "Help",
		"items": [
			{"id": ACTION_PERFORMANCE, "text": "Performance"},
			{"id": ACTION_SETTINGS, "text": "Settings"},
		],
	},
]

var _mode := "studio"
var _row: HBoxContainer
var _title_label: Label
var _subtitle_label: Label
var _dirty_dot: ColorRect
var _undo_button: Button
var _redo_button: Button
var _back_button: Button
var _menu_button: Button
var _settings_button: Button
var _renderer_button: Button
var _render_button: Button
var _fit_label: Label
var _menu_bar: HBoxContainer
var _overflow: PopupMenu
var _can_undo := false
var _can_redo := false


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_build()
	_apply_mode()


func _build() -> void:
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 4)
	add_child(_row)

	_back_button = Kit.icon_button("chevron-left", "Back to projects")
	_back_button.pressed.connect(func() -> void: action_requested.emit(ACTION_BACK))
	_row.add_child(_back_button)

	_menu_bar = HBoxContainer.new()
	_menu_bar.add_theme_constant_override("separation", 0)
	_row.add_child(_menu_bar)

	_overflow = PopupMenu.new()
	_overflow.add_theme_font_override("font", Kit.font_regular)
	_overflow.id_pressed.connect(_emit_menu_id)
	add_child(_overflow)

	for menu in MENUS:
		var button := Kit.text_toggle(str(menu["label"]), "", false)
		button.add_theme_font_override("font", Kit.font_medium)
		button.set_meta("qa_hit_exempt", true)
		button.pressed.connect(_open_menu.bind(button, menu))
		_menu_bar.add_child(button)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_box.add_theme_constant_override("separation", 0)
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(title_box)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.add_child(title_row)

	_title_label = Kit.label("Untitled", 13, Kit.TEXT, 600)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.clip_text = true
	_title_label.custom_minimum_size.x = 40
	title_row.add_child(_title_label)

	_dirty_dot = ColorRect.new()
	_dirty_dot.color = Color(0, 0, 0, 0)
	_dirty_dot.custom_minimum_size = Vector2(5, 5)
	_dirty_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dirty_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(_dirty_dot)

	_subtitle_label = Kit.mono_label("", 10, Kit.TEXT_DIM)
	_subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_subtitle_label.clip_text = true
	title_box.add_child(_subtitle_label)

	_undo_button = Kit.icon_button("undo-2", "Undo")
	_undo_button.disabled = true
	_undo_button.pressed.connect(func() -> void: action_requested.emit(ACTION_UNDO))
	_row.add_child(_undo_button)

	_redo_button = Kit.icon_button("redo-2", "Redo")
	_redo_button.disabled = true
	_redo_button.pressed.connect(func() -> void: action_requested.emit(ACTION_REDO))
	_row.add_child(_redo_button)

	_renderer_button = Kit.text_button("Mobile", "", false, true)
	_renderer_button.tooltip_text = "Renderer  ·  tap to switch"
	_renderer_button.pressed.connect(func() -> void: renderer_requested.emit())
	_row.add_child(_renderer_button)

	_fit_label = Kit.mono_label("", 10, Kit.TEXT_DIM)
	_fit_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fit_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_fit_label)

	_render_button = Kit.icon_button("clapperboard", "Render and export")
	_render_button.pressed.connect(func() -> void: action_requested.emit(ACTION_RENDER))
	_row.add_child(_render_button)

	_settings_button = Kit.icon_button("settings", "Settings")
	_settings_button.pressed.connect(func() -> void: action_requested.emit(ACTION_SETTINGS))
	_row.add_child(_settings_button)

	_menu_button = Kit.icon_button("ellipsis-vertical", "More actions")
	_menu_button.pressed.connect(_open_overflow)
	_row.add_child(_menu_button)


func set_mode(mode: String) -> void:
	_mode = mode if mode in ["compact", "studio", "desktop"] else "studio"
	_apply_mode()


func mode() -> String:
	return _mode


func set_project(title: String, dirty: bool, saved: bool) -> void:
	_title_label.text = title if title != "" else "Untitled"
	_dirty_dot.color = Kit.WARNING if dirty else Color(0, 0, 0, 0)
	_subtitle_label.text = ("Unsaved edits" if dirty else "Saved") if saved else ""


func set_renderer(text: String, fallback: bool) -> void:
	_renderer_button.text = text
	_renderer_button.add_theme_color_override("font_color", Kit.WARNING if fallback else Kit.TEXT_MUTED)


func set_fit(percent: float, small: bool) -> void:
	if percent >= 99.5:
		_fit_label.text = ""
		return
	_fit_label.text = "Fit %d%%" % int(round(percent))
	_fit_label.add_theme_color_override("font_color", Kit.WARNING if small else Kit.TEXT_DIM)


func set_history(can_undo: bool, can_redo: bool) -> void:
	_can_undo = can_undo
	_can_redo = can_redo
	_undo_button.disabled = not can_undo
	_redo_button.disabled = not can_redo


func _apply_mode() -> void:
	var height := 48.0
	var icon_size := 20
	var button_size := 44
	match _mode:
		"compact":
			height = 48.0
		"studio":
			height = 44.0
		"desktop":
			height = 36.0
			button_size = 36
			icon_size = 16
	custom_minimum_size.y = height
	var style := Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT, 0)
	style.border_width_bottom = 1
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	add_theme_stylebox_override("panel", style)
	_menu_bar.visible = _mode == "desktop"
	_back_button.visible = _mode != "desktop"
	_subtitle_label.visible = _mode != "compact"
	_renderer_button.visible = _mode == "desktop"
	_fit_label.visible = _mode == "desktop"
	# Compact is a phone header, not a toolbar: back, title/dirty and one
	# overflow. Undo, redo, save, render and settings live in that menu.
	_undo_button.visible = _mode != "compact"
	_redo_button.visible = _mode != "compact"
	_settings_button.visible = _mode != "compact"
	if _render_button != null:
		_render_button.visible = _mode != "compact"
	# The renderer chip is a 36 dp bar citizen; every touch-mode control keeps
	# a 44 dp target regardless of how dense the bar looks.
	_renderer_button.custom_minimum_size.y = height - 8 if _mode == "desktop" else Kit.Tokens.HIT
	_renderer_button.add_theme_font_size_override("font_size", 11 if _mode == "desktop" else 12)
	# Desktop is a mouse surface: the 36 dp bar may use 36 dp targets there.
	# Every touch arrangement keeps 44 dp, which is why the list below is
	# resized by mode rather than fixed at construction time.
	for button in [_back_button, _undo_button, _redo_button, _render_button, _settings_button, _menu_button]:
		if button == null:
			continue
		var exempt := _mode == "desktop"
		button.custom_minimum_size = Vector2(button_size if exempt else maxi(button_size, 44), maxi(36, height - 2))
		button.add_theme_constant_override("icon_max_width", icon_size if not exempt else 18)


func _open_menu(button: Control, menu: Dictionary) -> void:
	_overflow.clear()
	for item in menu["items"]:
		var entry: Dictionary = item
		var label := str(entry["text"])
		if entry.has("shortcut"):
			label += "    " + str(entry["shortcut"])
		_overflow.add_item(label)
		_overflow.set_item_metadata(_overflow.get_item_count() - 1, str(entry["id"]))
	var rect := button.get_global_rect()
	_overflow.position = Vector2i(int(rect.position.x), int(rect.position.y + rect.size.y))
	_overflow.popup()


func _emit_menu_id(id: int) -> void:
	var index := _overflow.get_item_index(id)
	if index < 0:
		return
	var action := str(_overflow.get_item_metadata(index))
	if action != "":
		action_requested.emit(action)


func _open_overflow() -> void:
	_overflow.clear()
	var actions := [
		{"id": ACTION_UNDO, "text": "Undo", "disabled": not _can_undo},
		{"id": ACTION_REDO, "text": "Redo", "disabled": not _can_redo},
		{"id": ACTION_SAVE, "text": "Save"},
		{"id": ACTION_RENDER, "text": "Render and export"},
		{"id": ACTION_RENDER_STILL, "text": "Quick still"},
		{"id": ACTION_IMPORT, "text": "Import model"},
		{"id": ACTION_PERFORMANCE, "text": "Performance"},
		{"id": ACTION_SETTINGS, "text": "Settings"},
		{"id": ACTION_FRAME_ALL, "text": "Frame all"},
	]
	if _mode == "desktop":
		actions.push_front({"id": ACTION_RESET_LAYOUT, "text": "Fit interface to screen"})
	for action in actions:
		var entry: Dictionary = action
		_overflow.add_item(str(entry["text"]))
		var index := _overflow.get_item_count() - 1
		_overflow.set_item_metadata(index, str(entry["id"]))
		if bool(entry.get("disabled", false)):
			_overflow.set_item_disabled(index, true)
	var rect := _menu_button.get_global_rect()
	_overflow.position = Vector2i(int(rect.position.x), int(rect.position.y + rect.size.y))
	_overflow.popup()
