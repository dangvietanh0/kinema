extends Control
## One reusable dropdown/modal surface for the workspace and project menus.
##
## The panel is a real full-rect control with explicit z-order: the scrim only
## catches input in centred mode, and the menu owns every row it adds. It never
## changes document state; it only reports the selected row id.

signal closed
signal row_selected(id: String)

const MAX_WIDTH := 360.0
const HEADER_H := 40.0

var _open := false
var _centered := true
var _anchor: Control = null
var _layout_mode := "studio"
var _empty_text := ""

var _scrim: ColorRect
var _panel: PanelContainer
var _column: VBoxContainer
var _header: MarginContainer
var _eyebrow: Label
var _subtitle: Label
var _rows_box: VBoxContainer
var _empty_label: Label
var _rows: Array[Button] = []
var _row_map: Dictionary = {}
var _empty_margin: MarginContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 14
	visible = false
	_build()
	resized.connect(_apply_geometry)


func _build() -> void:
	_scrim = ColorRect.new()
	_scrim.color = Kit.SCRIM
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.visible = false
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Kit.float_style(Kit.SURFACE_2, Kit.BORDER))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 0)
	_panel.add_child(_column)

	_header = MarginContainer.new()
	_header.custom_minimum_size.y = HEADER_H
	_header.add_theme_constant_override("margin_left", 12)
	_header.add_theme_constant_override("margin_right", 12)
	_header.add_theme_constant_override("margin_top", 6)
	_header.add_theme_constant_override("margin_bottom", 6)
	_column.add_child(_header)
	var header_box := VBoxContainer.new()
	header_box.add_theme_constant_override("separation", 0)
	_header.add_child(header_box)
	_eyebrow = Kit.mono_label("", 11, Kit.TEXT_DIM)
	_eyebrow.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_eyebrow.clip_text = true
	header_box.add_child(_eyebrow)
	_subtitle = Kit.label("", 13, Kit.TEXT, 500)
	_subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_subtitle.clip_text = true
	header_box.add_child(_subtitle)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 0)
	_column.add_child(_rows_box)

	_empty_label = Kit.label("", 12, Kit.TEXT_MUTED)
	_empty_label.custom_minimum_size = Vector2(0, 52)
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.add_theme_constant_override("line_spacing", 2)
	_empty_label.visible = false
	var empty_margin := MarginContainer.new()
	empty_margin.add_theme_constant_override("margin_left", 12)
	empty_margin.add_theme_constant_override("margin_right", 12)
	empty_margin.add_child(_empty_label)
	empty_margin.visible = false
	_empty_margin = empty_margin
	_rows_box.add_child(empty_margin)


func set_layout_mode(mode: String) -> void:
	_layout_mode = mode if mode in ["compact", "studio", "desktop"] else "studio"


func open_menu(anchor: Control, title: String, subtitle: String, centered: bool) -> void:
	_clear_rows()
	_anchor = anchor
	_centered = centered
	_open = true
	visible = true
	_eyebrow.text = title.to_upper()
	_subtitle.text = subtitle
	_scrim.visible = centered
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP if centered else Control.MOUSE_FILTER_IGNORE
	_update_empty()
	_apply_geometry()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed.emit()


func is_open() -> bool:
	return _open


func add_row(id: String, label: String, icon: String, description: String,
		checked: bool, enabled := true, reason := "", height := 52.0) -> Button:
	var row := Button.new()
	row.toggle_mode = true
	row.button_pressed = checked
	row.focus_mode = Control.FOCUS_NONE
	row.clip_text = true
	row.custom_minimum_size = Vector2(0, height)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.text = ""
	row.set_meta("workspace_row", id)
	row.set_meta("row_id", id)
	row.set_meta("action_id", id)
	row.set_meta("action_icon", icon)
	row.tooltip_text = description if description != "" else label
	if not enabled:
		row.disabled = true
		row.tooltip_text = reason if reason != "" else label
	if checked:
		row.add_theme_stylebox_override("normal", Kit.flat_style(Kit.SURFACE_ACTIVE, 0, Color(0, 0, 0, 0), 0))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(margin)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(line)

	if icon != "":
		var glyph := Kit.icon(icon, Kit.TEXT_MUTED, 20)
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(glyph)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 0)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(text_box)

	var title := Kit.label(label, 13, Kit.TEXT, 500)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(title)
	if description != "":
		var detail := Kit.label(description, 11, Kit.TEXT_MUTED)
		detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		detail.clip_text = true
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_box.add_child(detail)

	var check := Kit.icon("check", Kit.FOCUS_BRIGHT, 20)
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	check.visible = checked
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(check)

	row.pressed.connect(func() -> void:
		close()
		row_selected.emit(id)
	)
	_rows_box.add_child(row)
	_rows.append(row)
	_row_map[id] = row
	_apply_geometry()
	return row


func add_action(id: String, label: String, icon: String,
		enabled := true, reason := "") -> Button:
	var row := Kit.text_button(label, icon, false, true)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.custom_minimum_size = Vector2(0, 32.0 if _layout_mode == "desktop" else 44.0)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_font_size_override("font_size", 13)
	row.add_theme_constant_override("margin_left", 12)
	row.set_meta("row_id", id)
	row.set_meta("action_id", id)
	row.set_meta("action_icon", icon)
	row.tooltip_text = label
	if not enabled:
		row.disabled = true
		row.tooltip_text = reason if reason != "" else label
	row.pressed.connect(func() -> void:
		close()
		row_selected.emit(id)
	)
	_rows_box.add_child(row)
	_rows.append(row)
	_row_map[id] = row
	_apply_geometry()
	return row


func add_separator() -> void:
	_rows_box.add_child(Kit.vsep())
	_apply_geometry()


func row_count() -> int:
	return _rows.size()


func row_button(id: String) -> Button:
	return _row_map.get(id, null)


func set_empty_text(text: String) -> void:
	_empty_text = text
	_update_empty()


func empty_text() -> String:
	return _empty_text


func scrim() -> ColorRect:
	return _scrim


func _clear_rows() -> void:
	for child in _rows_box.get_children():
		if child == _empty_margin:
			continue
		_items_remove(child)
	_rows.clear()
	_row_map.clear()


func _items_remove(node: Node) -> void:
	_rows_box.remove_child(node)
	node.queue_free()


func _update_empty() -> void:
	if _empty_label == null:
		return
	_empty_label.text = _empty_text
	var show := _open and _empty_text != ""
	_empty_label.visible = show
	if _empty_margin != null:
		_empty_margin.visible = show


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			close()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			close()


func _apply_geometry() -> void:
	if _panel == null:
		return
	var view := size
	if view.x <= 1.0 or view.y <= 1.0:
		return
	var width := minf(MAX_WIDTH, view.x - 32.0) if _centered else minf(MAX_WIDTH, view.x - 16.0)
	width = maxf(width, 200.0)
	var height := _panel.get_combined_minimum_size().y
	height = minf(height, maxf(view.y - 16.0, 44.0))
	var pos := Vector2.ZERO
	if _centered:
		pos = Vector2((view.x - width) * 0.5, (view.y - height) * 0.5)
	else:
		var screen := Vector2.ZERO
		if _anchor != null and is_instance_valid(_anchor):
			var rect := _anchor.get_global_rect()
			screen = rect.position - get_global_rect().position
			screen.y += rect.size.y
		pos = Vector2(screen.x, screen.y)
		pos.x = clampf(pos.x, 8.0, maxf(8.0, view.x - width - 8.0))
		pos.y = clampf(pos.y, 8.0, maxf(8.0, view.y - height - 8.0))
	_panel.position = pos
	_panel.size = Vector2(width, height)
