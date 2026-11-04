extends VBoxContainer
## Material library sheet.
##
## Every row is a real library record. Assign is an explicit button; tapping a
## row only selects it. The sheet owns the undo boundary for its own mutations.

signal assigned(material_id: String)
signal changed(material_id: String)
signal delete_requested(material_id: String)

var _doc = null
var _target: Dictionary = {}
var _selected := ""
var _list: VBoxContainer
var _empty_label: Label
var _new_button: Button
var _duplicate_button: Button
var _rows: Dictionary = {}


func setup(document, target: Dictionary) -> void:
	_doc = document
	_target = target.duplicate(true)


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	open()


func open() -> void:
	_selected = ""
	_build()


func target() -> Dictionary:
	return _target.duplicate(true)


func selected_id() -> String:
	return _selected


func row_count() -> int:
	return _rows.size()


func empty_text() -> String:
	return _empty_label.text if _empty_label != null else ""


func assign_button(material_id: String) -> Button:
	var row: Dictionary = _rows.get(material_id, {})
	return row.get("assign", null)


func row_height(material_id: String) -> float:
	var row: Dictionary = _rows.get(material_id, {})
	var panel: PanelContainer = row.get("panel", null)
	return panel.custom_minimum_size.y if panel != null else 0.0


func select(material_id: String) -> void:
	if not _rows.has(material_id):
		return
	_selected = material_id
	_duplicate_button.visible = true
	for id in _rows.keys():
		var row: Dictionary = _rows[id]
		var button: Button = row.get("select", null)
		if button != null:
			button.button_pressed = str(id) == _selected
			button.add_theme_stylebox_override("normal", Kit.flat_style(
				Kit.SURFACE_ACTIVE if str(id) == _selected else Kit.SURFACE_2,
				Kit.R_CONTROL,
				Kit.FOCUS_DARK if str(id) == _selected else Kit.CONTROL_BORDER, 1))


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_rows.clear()
	_empty_label = null
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	add_child(header)
	_new_button = Kit.text_button("New material", "", false, false)
	_new_button.custom_minimum_size = Vector2(96.0, 44.0)
	_new_button.pressed.connect(_on_new)
	header.add_child(_new_button)
	_duplicate_button = Kit.text_button("Duplicate", "", false, false)
	_duplicate_button.custom_minimum_size = Vector2(96.0, 44.0)
	_duplicate_button.visible = false
	_duplicate_button.pressed.connect(_on_duplicate)
	header.add_child(_duplicate_button)

	var materials = _doc.material_system if _doc != null else null
	var ids: PackedStringArray = materials.material_ids() if materials != null else PackedStringArray()
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	add_child(_list)
	if ids.is_empty():
		_empty_label = Kit.label("No materials yet. Create one to use textures and shading models.",
			11, Kit.TEXT_DIM)
		_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(_empty_label)
		return
	for id in ids:
		_add_row(str(id), materials.get_material(str(id)))


func _add_row(material_id: String, record: Dictionary) -> void:
	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size.y = 44.0
	row_panel.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_2, Kit.R_CONTROL, Kit.CONTROL_BORDER, 1))
	_list.add_child(row_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row_panel.add_child(row)
	var swatch := PanelContainer.new()
	swatch.custom_minimum_size = Vector2(44.0, 44.0)
	var color := Color.from_string(str(record.get("albedo_color", "#B8BCC2")), Kit.SURFACE_3)
	swatch.add_theme_stylebox_override("panel", Kit.flat_style(color, Kit.R_CONTROL, Kit.CONTROL_BORDER, 1))
	row.add_child(swatch)
	var select := Kit.text_button(str(record.get("name", "Material")), "", false, true)
	select.toggle_mode = true
	select.custom_minimum_size = Vector2(0.0, 44.0)
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select.pressed.connect(func() -> void: select_material(material_id))
	row.add_child(select)
	var badge := Kit.mono_label(str(record.get("shading", "pbr")).to_upper(), 9, Kit.TEXT_DIM)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var assign := Kit.text_button("Assign", "", false, false)
	assign.custom_minimum_size = Vector2(96.0, 44.0)
	assign.pressed.connect(func() -> void: assign_material(material_id))
	row.add_child(assign)
	_rows[material_id] = {"select": select, "assign": assign, "panel": row_panel}


func select_material(material_id: String) -> void:
	select(material_id)


func _on_new() -> void:
	if _doc == null:
		return
	_doc.begin_edit("Create material")
	var material_id: String = _doc.material_system.create_material()
	_doc.end_edit()
	_selected = material_id
	changed.emit(_selected)
	_build()
	select(material_id)


func _on_duplicate() -> void:
	if _doc == null or _selected == "":
		return
	_doc.begin_edit("Duplicate material")
	var copy_id: String = _doc.material_system.duplicate_material(_selected)
	_doc.end_edit()
	if copy_id != "":
		_selected = copy_id
		changed.emit(_selected)
		_build()
		select(copy_id)


func assign_material(material_id: String) -> void:
	if _doc == null:
		return
	var object_id := str(_target.get("object_id", ""))
	if object_id == "":
		return
	_doc.begin_edit("Assign material")
	var ok: bool = _doc.material_system.assign_material(
		object_id, material_id, str(_target.get("part_path", "")), int(_target.get("surface", -1)))
	_doc.end_edit()
	if ok:
		assigned.emit(material_id)
		changed.emit(material_id)
