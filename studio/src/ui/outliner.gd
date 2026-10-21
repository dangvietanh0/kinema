extends VBoxContainer
## Flat scene outliner with search, visibility toggles and animation markers.

signal add_requested

const DocumentScript = preload("res://src/core/document.gd")
var doc: DocumentScript = null

var _list: VBoxContainer
var _scroll: ScrollContainer
var _count: Label
var _search: LineEdit
var _empty: VBoxContainer
var _rows: Dictionary = {}
var _filter := ""

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)
	_build()

func setup(document: Node3D) -> void:
	doc = document
	doc.scene_changed.connect(_on_scene_changed)
	doc.selection_changed.connect(_on_selection_changed)
	doc.object_changed.connect(_on_object_changed)
	_rebuild()

func _build() -> void:
	if _list != null:
		return
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 12)
	header_margin.add_theme_constant_override("margin_right", 8)
	header_margin.add_theme_constant_override("margin_top", 10)
	header_margin.add_theme_constant_override("margin_bottom", 6)
	add_child(header_margin)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header_margin.add_child(header)
	var title := Kit.section_label("Scene")
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	_count = Kit.label("0", 10, Kit.TEXT_DIM, 500)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_count)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var add := Kit.icon_button("plus", "Add object", 26, 14)
	add.pressed.connect(func() -> void: add_requested.emit())
	header.add_child(add)

	var search_margin := MarginContainer.new()
	search_margin.add_theme_constant_override("margin_left", 10)
	search_margin.add_theme_constant_override("margin_right", 10)
	search_margin.add_theme_constant_override("margin_bottom", 8)
	add_child(search_margin)
	_search = Kit.line_edit("Search scene", 11)
	_search.custom_minimum_size.y = 28
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search_changed)
	search_margin.add_child(_search)

	var rule := Kit.vsep()
	add_child(rule)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_scroll)

	var list_margin := MarginContainer.new()
	list_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_margin.add_theme_constant_override("margin_left", 6)
	list_margin.add_theme_constant_override("margin_right", 6)
	list_margin.add_theme_constant_override("margin_top", 6)
	list_margin.add_theme_constant_override("margin_bottom", 10)
	list_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(list_margin)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 1)
	list_margin.add_child(_list)

	_empty = VBoxContainer.new()
	_empty.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty.add_theme_constant_override("separation", 4)
	_empty.visible = false
	list_margin.add_child(_empty)
	var empty_icon := Kit.icon("layers", Kit.TEXT_DIM, 22)
	empty_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_empty.add_child(empty_icon)
	var empty_title := Kit.label("The scene is empty", 12, Kit.TEXT_MUTED, 500)
	empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_child(empty_title)
	var empty_sub := Kit.label("Use the + button to add an object.", 10, Kit.TEXT_DIM)
	empty_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_child(empty_sub)

func _on_search_changed(text_value: String) -> void:
	_filter = text_value.strip_edges().to_lower()
	_rebuild()

func _on_scene_changed() -> void:
	_rebuild()

func _on_selection_changed(_id: String) -> void:
	_refresh_selection()

func _on_object_changed(id: String) -> void:
	_update_row(id)
	_refresh_selection()

func _rebuild() -> void:
	if doc == null or _list == null:
		return
	var scroll_pos := _scroll.scroll_vertical
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	var visible_count := 0
	for obj in doc.objects:
		var name := str(obj.get("name", "Object"))
		if _filter != "" and not name.to_lower().contains(_filter):
			continue
		visible_count += 1
		var row := _make_row(obj)
		_list.add_child(row)
		_rows[str(obj["id"])] = row
	_count.text = str(doc.objects.size())
	_empty.visible = visible_count == 0
	if not _empty.visible:
		for child in _list.get_children():
			child.visible = true
	# Keep the search / empty messaging honest.
	var empty_title := _empty.get_child(1) as Label
	if empty_title != null:
		empty_title.text = "No matching objects" if _filter != "" and not doc.objects.is_empty() else "The scene is empty"
	_refresh_selection()
	_scroll.scroll_vertical = scroll_pos

func _make_row(obj: Dictionary) -> Control:
	var id := str(obj["id"])
	var selected := id == doc.selected_id
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 30
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel", _row_style(selected))
	if not selected:
		panel.mouse_entered.connect(func() -> void:
			if doc != null and id != doc.selected_id:
				panel.add_theme_stylebox_override("panel", _row_style(false, true))
		)
		panel.mouse_exited.connect(func() -> void:
			if doc != null and id != doc.selected_id:
				panel.add_theme_stylebox_override("panel", _row_style(false))
		)
	Kit.bind_tap(panel, _on_row_tapped.bind(id))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.offset_right = -4
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	var icon := Kit.icon(_icon_for(obj), Kit.TEXT_MUTED if selected else Kit.TEXT_DIM, 14)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var name := Kit.label(str(obj.get("name", "Object")), 12, Kit.TEXT if selected else Kit.TEXT_MUTED, 500 if selected else 400)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name)

	var key_marker := Kit.icon("diamond", Kit.ACCENT, 8)
	key_marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	key_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(key_marker)
	key_marker.visible = _has_keys(id)

	var hidden := not bool(obj.get("visible", true))
	var eye := Kit.icon_button("eye-closed" if hidden else "eye", "Show" if hidden else "Hide", 24, 12)
	eye.add_theme_color_override("icon_normal_color", Kit.TEXT_DIM if hidden else Kit.TEXT_MUTED)
	eye.add_theme_color_override("icon_hover_color", Kit.TEXT)
	eye.pressed.connect(func() -> void:
		if doc == null:
			return
		var current: Dictionary = doc.get_object(id)
		if not current.is_empty():
			doc.set_object_visible(id, not bool(current.get("visible", true)))
	)
	row.add_child(eye)
	return panel

func _row_style(selected: bool, hover: bool = false) -> StyleBoxFlat:
	if selected:
		var sb := Kit.flat_style(Kit.SURFACE_3, 4, Color(0, 0, 0, 0), 0)
		sb.border_width_left = 2
		sb.border_color = Kit.ACCENT
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		return sb
	var bg := Kit.SURFACE_2 if hover else Color(0, 0, 0, 0)
	var plain := Kit.flat_style(bg, 4, Color(0, 0, 0, 0), 0)
	plain.content_margin_left = 4
	plain.content_margin_right = 4
	return plain

func _on_row_tapped(id: String) -> void:
	if doc == null:
		return
	doc.set_selection(id)

func _refresh_selection() -> void:
	if doc == null:
		return
	for id in _rows:
		var row: Control = _rows[id]
		if row == null or not is_instance_valid(row):
			continue
		row.add_theme_stylebox_override("panel", _row_style(str(id) == doc.selected_id))
		_update_row(str(id))

func _update_row(id: String) -> void:
	if doc == null or not _rows.has(id):
		return
	var obj: Dictionary = doc.get_object(id)
	var panel: Control = _rows[id]
	if obj.is_empty() or panel == null:
		return
	var row := panel.get_child(0) as HBoxContainer
	if row == null:
		return
	var selected := id == doc.selected_id
	var icon := row.get_child(0) as TextureRect
	icon.texture = Kit.icon_texture(_icon_for(obj))
	icon.modulate = Kit.TEXT_MUTED if selected else Kit.TEXT_DIM
	var name := row.get_child(1) as Label
	if name != null and not name.has_meta("editing"):
		name.text = str(obj.get("name", "Object"))
		name.add_theme_color_override("font_color", Kit.TEXT if selected else Kit.TEXT_MUTED)
		name.add_theme_font_override("font", Kit.font_for(500 if selected else 400))
	var key_marker := row.get_child(2) as TextureRect
	key_marker.visible = _has_keys(id)
	var hidden := not bool(obj.get("visible", true))
	var eye := row.get_child(3) as Button
	eye.icon = Kit.icon_texture("eye-closed" if hidden else "eye")
	eye.tooltip_text = "Show" if hidden else "Hide"
	eye.add_theme_color_override("icon_normal_color", Kit.TEXT_DIM if hidden else Kit.TEXT_MUTED)

func _has_keys(id: String) -> bool:
	if doc == null:
		return false
	for channel in doc.CHANNELS:
		if doc.get_channel_keys(id, channel).size() > 0:
			return true
	return false

func _icon_for(obj: Dictionary) -> String:
	match str(obj.get("kind", "mesh")):
		"camera": return "camera"
		"light": return "lightbulb"
		"empty": return "circle-dot-dashed"
		"import": return "package-open"
		_:
			match str(obj.get("primitive", "box")):
				"sphere": return "circle"
				"cylinder": return "cylinder"
				"cone": return "cone"
				"torus": return "torus"
				"plane": return "square"
				_: return "box"
