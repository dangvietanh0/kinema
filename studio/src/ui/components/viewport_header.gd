extends PanelContainer
## The strip above the 3D view.
##
## View controls belong to the view, so they sit in a header attached to it
## rather than floating over the picture: the camera preset and Add on the
## left, grid and frame on the right. The stage underneath stays clean.
##
## The header is layout, not an overlay. It reserves its own height, so the
## viewport never loses pixels to a control plate and the render never has to
## hide floating buttons.

signal add_requested
signal view_requested(label: String)
signal grid_toggled(enabled: bool)
signal frame_requested

const VIEWS := [
	{"id": "Persp", "text": "Perspective"},
	{"id": "Front", "text": "Front"},
	{"id": "Right", "text": "Right"},
	{"id": "Top", "text": "Top"},
]

var _mode := "studio"
var _row: HBoxContainer
var _view_button: Button
var _add_button: Button
var _grid_button: Button
var _frame_button: Button
var _menu: PopupMenu
var _icon_buttons: Array[Button] = []


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_build()
	set_mode("studio")


func _build() -> void:
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 2)
	add_child(_row)

	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu_id)
	add_child(_menu)

	_view_button = Button.new()
	_view_button.text = "Perspective"
	_view_button.icon = Kit.icon_texture("chevron-down")
	_view_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_view_button.expand_icon = false
	_view_button.focus_mode = Control.FOCUS_NONE
	_view_button.tooltip_text = "Camera view"
	_view_button.theme_type_variation = "QuietButton"
	_view_button.add_theme_font_override("font", Kit.font_medium)
	_view_button.add_theme_font_size_override("font_size", Kit.TYPE_BODY)
	_view_button.add_theme_constant_override("icon_max_width", 18)
	_view_button.add_theme_constant_override("h_separation", 6)
	_view_button.pressed.connect(_open_views)
	_row.add_child(_view_button)

	_add_button = Button.new()
	_add_button.text = "Add"
	_add_button.icon = Kit.icon_texture("plus")
	_add_button.focus_mode = Control.FOCUS_NONE
	_add_button.tooltip_text = "Add an object to the scene"
	_add_button.theme_type_variation = "QuietButton"
	_add_button.add_theme_font_override("font", Kit.font_medium)
	_add_button.add_theme_font_size_override("font_size", Kit.TYPE_BODY)
	_add_button.add_theme_constant_override("icon_max_width", 18)
	_add_button.add_theme_constant_override("h_separation", 6)
	_add_button.pressed.connect(func() -> void: add_requested.emit())
	_row.add_child(_add_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(spacer)

	_grid_button = Kit.icon_button("grid-3x3", "Show grid")
	_grid_button.toggle_mode = true
	_grid_button.button_pressed = true
	_grid_button.toggled.connect(_on_grid_toggled)
	_row.add_child(_grid_button)
	_icon_buttons.append(_grid_button)

	_frame_button = Kit.icon_button("focus", "Frame selection. Shortcut F.")
	_frame_button.pressed.connect(func() -> void: frame_requested.emit())
	_row.add_child(_frame_button)
	_icon_buttons.append(_frame_button)
	_sync_grid_style(true)


## The strip is 44 dp in both touch modes and on the desktop pointer surface.
## A 36 dp bar cannot honestly contain a 44 dp touch target, so the control
## keeps the floor and the header grows to hold it.
func set_mode(mode: String) -> void:
	_mode = mode if mode in ["compact", "studio", "desktop"] else "studio"
	if _row == null:
		return
	var height := float(Kit.Tokens.HIT)
	var icon := 20 if _mode == "compact" else 18
	custom_minimum_size.y = height
	var style := Kit.flat_style(Kit.SURFACE_2, Kit.R_PANEL, Color(0, 0, 0, 0), 0)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	add_theme_stylebox_override("panel", style)
	for button in _icon_buttons:
		button.custom_minimum_size = Vector2(height, height)
		button.add_theme_constant_override("icon_max_width", icon)
	for button in [_view_button, _add_button]:
		button.custom_minimum_size = Vector2(0, height)
		button.add_theme_constant_override("icon_max_width", icon)


## The view keeps references to the real header buttons so older call sites
## and the frozen shell test can inspect them without a hidden duplicate.
func grid_button() -> Button:
	return _grid_button


func frame_button() -> Button:
	return _frame_button


func set_view_label(text_value: String) -> void:
	if _view_button == null:
		return
	_view_button.text = _display_name(text_value)


func set_grid(enabled: bool) -> void:
	if _grid_button == null:
		return
	_grid_button.set_pressed_no_signal(enabled)
	_sync_grid_style(enabled)


func _display_name(label: String) -> String:
	match label:
		"Persp":
			return "Perspective"
		_:
			return label


func _on_grid_toggled(enabled: bool) -> void:
	_sync_grid_style(enabled)
	grid_toggled.emit(enabled)


func _sync_grid_style(enabled: bool) -> void:
	Kit.set_icon_active(_grid_button, enabled)


func _open_views() -> void:
	_menu.clear()
	for entry in VIEWS:
		_menu.add_item(str(entry["text"]))
		_menu.set_item_metadata(_menu.get_item_count() - 1, str(entry["id"]))
	var rect := _view_button.get_global_rect()
	var popup_size := _menu.get_contents_minimum_size()
	var view_size := get_viewport_rect().size
	# A popup opened near the right or bottom edge must stay on screen; the
	# header sits inside the viewport, so clamping here is enough.
	var pos := Vector2i(
		clampi(int(rect.position.x), 0, maxi(0, int(view_size.x - popup_size.x))),
		clampi(int(rect.position.y + rect.size.y), 0, maxi(0, int(view_size.y - popup_size.y)))
	)
	_menu.position = pos
	_menu.popup()


func _on_menu_id(id: int) -> void:
	var index := _menu.get_item_index(id)
	if index >= 0:
		view_requested.emit(str(_menu.get_item_metadata(index)))
