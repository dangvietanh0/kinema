extends VBoxContainer
## Material editor sheet.
##
## Every control writes a real record field through MaterialSystem; texture
## rows show the stored path and dimensions. The sheet owns its undo boundary.

signal changed(material_id: String)
signal delete_requested(material_id: String)
signal color_requested(property: String, current: Color)

const NumberFieldScript = preload("res://src/ui/num_field.gd")
const ScrubBarScript = preload("res://src/ui/scrub_bar.gd")

const TEXTURE_FILTER := "*.png, *.jpg, *.jpeg, *.webp;Images"
const MAP_LABELS := {
	"normal": "Normal",
	"orm": "ORM (R=AO · G=Roughness · B=Metallic)",
	"roughness": "Roughness",
	"metallic": "Metallic",
	"ao": "AO",
	"emission": "Emission",
}
const MAP_KEYS := {
	"normal": "normal_texture",
	"orm": "orm_texture",
	"roughness": "roughness_texture",
	"metallic": "metallic_texture",
	"ao": "ao_texture",
	"emission": "emission_texture",
}
const ORM_LOCK_REASON := "Packed ORM supplies AO, roughness and metallic. Clear ORM to use separate maps."

var _doc = null
var _ms = null
var _id := ""
var _record: Dictionary = {}
var _target: Dictionary = {}
var _shading_buttons: Dictionary = {}
var _map_rows: Dictionary = {}
var _uv_fields: Dictionary = {}
var _rim_box: VBoxContainer
var _emission_scrub: ScrubBarScript
var _orm_reason: Label
var _uv_warning: Label
var _name_edit: LineEdit
var _duplicate_button: Button
var _delete_button: Button
var _error_label: Label


func setup(document, material_id: String = "") -> void:
	_doc = document
	_ms = document.material_system if document != null else null
	_id = material_id


func set_target(target: Dictionary) -> void:
	_target = target.duplicate(true)
	if is_inside_tree() and _id != "":
		_refresh_warnings()


func open(material_id: String) -> void:
	_id = material_id
	if is_inside_tree():
		_build()


func material_id() -> String:
	return _id


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	if _id != "":
		_build()


func shading_button(model: String) -> Button:
	return _shading_buttons.get(model, null)


func orm_label_text() -> String:
	var row: Dictionary = _map_rows.get("orm", {})
	var label: Label = row.get("label", null)
	return label.text if label != null else ""


func orm_reason_text() -> String:
	return _orm_reason.text if _orm_reason != null else ""


func orm_reason_visible() -> bool:
	return _orm_reason != null and _orm_reason.visible


func slot_state(slot: String) -> String:
	var row: Dictionary = _map_rows.get(slot, {})
	var label: Label = row.get("state", null)
	return label.text if label != null else ""


func slot_state_color(slot: String) -> Color:
	var row: Dictionary = _map_rows.get(slot, {})
	var label: Label = row.get("state", null)
	return label.get_theme_color("font_color") if label != null else Kit.TEXT_MUTED


func slot_disabled(slot: String) -> bool:
	var row: Dictionary = _map_rows.get(slot, {})
	var button: Button = row.get("replace", null)
	return button == null or button.disabled


func uv_fields() -> Dictionary:
	return _uv_fields.duplicate()


func rim_visible() -> bool:
	return _rim_box != null and _rim_box.visible


func uv_warning_text() -> String:
	return _uv_warning.text if _uv_warning != null else ""


func uv_warning_visible() -> bool:
	return _uv_warning != null and _uv_warning.visible


func map_row_height(slot: String) -> float:
	var row: Dictionary = _map_rows.get(slot, {})
	var node: HBoxContainer = row.get("row", null)
	return node.custom_minimum_size.y if node != null else 0.0


func emission_scrub() -> ScrubBarScript:
	return _emission_scrub


func duplicate_button() -> Button:
	return _duplicate_button


func delete_button() -> Button:
	return _delete_button


func texture_filter() -> String:
	return TEXTURE_FILTER


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_shading_buttons.clear()
	_map_rows.clear()
	_uv_fields.clear()
	_rim_box = null
	_orm_reason = null
	_uv_warning = null
	_emission_scrub = null
	_error_label = null
	_record = _ms.get_material(_id) if _ms != null else {}
	if _record.is_empty():
		add_child(Kit.label("Select a material.", 11, Kit.TEXT_MUTED))
		return

	_name_edit = Kit.line_edit("Material name")
	_name_edit.text = str(_record.get("name", "Material"))
	_name_edit.text_submitted.connect(_on_name_submitted)
	add_child(_name_edit)

	add_child(Kit.section_label("Shading"))
	var shading_row := HBoxContainer.new()
	shading_row.add_theme_constant_override("separation", 4)
	add_child(shading_row)
	for model in [["pbr", "PBR"], ["unlit", "Unlit"], ["toon", "Toon"], ["rim", "Rim"]]:
		var button := Kit.text_button(str(model[1]), "", false, true)
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0.0, 44.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.button_pressed = str(_record.get("shading", "pbr")) == str(model[0])
		button.pressed.connect(func() -> void: _set_shading(str(model[0])))
		shading_row.add_child(button)
		_shading_buttons[str(model[0])] = button

	add_child(Kit.section_label("Base"))
	_add_color_row("Base colour", "albedo_color", str(_record.get("albedo_color", "#B8BCC2")))
	_add_scrub("Roughness", "roughness", 0.0, 1.0)
	_add_scrub("Metallic", "metallic", 0.0, 1.0)
	_add_scrub("Metallic specular", "metallic_specular", 0.0, 1.0)

	add_child(Kit.section_label("Emission"))
	_add_color_row("Emission colour", "emission_color", str(_record.get("emission_color", "#000000")))
	_add_scrub("Emission energy", "emission_energy", 0.0, 10.0, true)

	add_child(Kit.section_label("Maps"))
	for slot in ["normal", "orm", "roughness", "metallic", "ao", "emission"]:
		_add_map_row(slot)

	add_child(Kit.section_label("UV"))
	var uv_grid := GridContainer.new()
	uv_grid.columns = 2
	uv_grid.add_theme_constant_override("h_separation", 8)
	uv_grid.add_theme_constant_override("v_separation", 4)
	add_child(uv_grid)
	var scale: Array = _record.get("uv1_scale", [1.0, 1.0])
	var offset: Array = _record.get("uv1_offset", [0.0, 0.0])
	_add_uv_field(uv_grid, "scale_x", "Scale X", float(scale[0]))
	_add_uv_field(uv_grid, "scale_y", "Scale Y", float(scale[1]))
	_add_uv_field(uv_grid, "offset_x", "Offset X", float(offset[0]))
	_add_uv_field(uv_grid, "offset_y", "Offset Y", float(offset[1]))

	_rim_box = VBoxContainer.new()
	_rim_box.add_theme_constant_override("separation", 4)
	add_child(_rim_box)
	_rim_box.add_child(Kit.section_label("Rim"))
	_add_scrub("Rim strength", "rim", 0.0, 1.0, false, _rim_box)
	_add_scrub("Rim tint", "rim_tint", 0.0, 1.0, false, _rim_box)
	_rim_box.visible = str(_record.get("shading", "pbr")) == "rim"

	_uv_warning = Kit.label("This part has no UVs; a texture will sample a single point.", 10, Kit.WARNING)
	_uv_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_uv_warning.visible = false
	add_child(_uv_warning)

	_error_label = Kit.label("", 10, Kit.WARNING)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_error_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	add_child(footer)
	_duplicate_button = Kit.text_button("Duplicate", "copy", false, false)
	_duplicate_button.custom_minimum_size = Vector2(96.0, 44.0)
	_duplicate_button.pressed.connect(_on_duplicate)
	footer.add_child(_duplicate_button)
	_delete_button = Kit.text_button("Delete", "trash-2", false, false)
	_delete_button.custom_minimum_size = Vector2(96.0, 44.0)
	_delete_button.add_theme_color_override("font_color", Kit.DANGER)
	_delete_button.pressed.connect(func() -> void: delete_requested.emit(_id))
	footer.add_child(_delete_button)

	_refresh_locks()
	_refresh_warnings()


func _refresh_locks() -> void:
	var locked := str(_record.get("orm_texture", "")) != ""
	if _orm_reason != null:
		_orm_reason.visible = locked
	for slot in ["roughness", "metallic", "ao"]:
		var row: Dictionary = _map_rows.get(slot, {})
		var replace: Button = row.get("replace", null)
		var clear: Button = row.get("clear", null)
		if replace != null:
			replace.disabled = locked
		if clear != null:
			clear.disabled = locked


func _refresh_warnings() -> void:
	if _uv_warning == null:
		return
	_uv_warning.visible = _textures_assigned() and _target_part_has_no_uvs()
	_uv_warning.text = "This part has no UVs; a texture will sample a single point."


func _textures_assigned() -> bool:
	for key in MAP_KEYS.values():
		if str(_record.get(key, "")) != "":
			return true
	return false


func _target_part_has_no_uvs() -> bool:
	if _doc == null or _target.is_empty():
		return false
	var part_path := str(_target.get("part_path", ""))
	if part_path == "":
		return false
	var root: Node3D = _doc.nodes.get(str(_target.get("object_id", "")))
	if root == null:
		return false
	var node := root.get_node_or_null(NodePath(part_path))
	if not (node is MeshInstance3D) or (node as MeshInstance3D).mesh == null:
		return false
	var mesh_instance := node as MeshInstance3D
	var surface := int(_target.get("surface", -1))
	var surfaces: Array = [surface] if surface >= 0 else range(mesh_instance.mesh.get_surface_count())
	for index in surfaces:
		if index < 0 or index >= mesh_instance.mesh.get_surface_count():
			continue
		var arrays := mesh_instance.mesh.surface_get_arrays(index)
		var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV] if arrays.size() > Mesh.ARRAY_TEX_UV else null
		if uvs is PackedVector2Array and (uvs as PackedVector2Array).size() > 0:
			return false
	return true


func _on_name_submitted(text_value: String) -> void:
	var clean := text_value.strip_edges()
	if clean == "":
		return
	_commit({"name": clean}, "Rename material")


func _set_shading(model: String) -> void:
	_commit({"shading": model}, "Change shading")
	_build()


func set_color(property: String, color: Color) -> void:
	_commit({property: "#" + color.to_html(false)}, "Change material colour")
	_build()


func _add_color_row(label_text: String, property: String, hex: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var label := Kit.label(label_text, 11, Kit.TEXT_MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var hex_label := Kit.mono_label(hex.to_upper(), 9, Kit.TEXT_DIM)
	hex_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hex_label)
	var color := Color.from_string(hex, Color(0.6, 0.6, 0.6))
	var button := Button.new()
	button.custom_minimum_size = Vector2(44.0, 44.0)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", Kit.flat_style(color, Kit.R_CONTROL, Kit.CONTROL_BORDER, 1))
	button.pressed.connect(func() -> void: color_requested.emit(property, color))
	row.add_child(button)


func _add_scrub(label_text: String, property: String, min_value: float, max_value: float,
		emission: bool = false, parent: VBoxContainer = null) -> ScrubBarScript:
	var host: VBoxContainer = parent if parent != null else self
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	host.add_child(row)
	var label := Kit.label(label_text, 11, Kit.TEXT_MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var value_label := Kit.mono_label("%.2f" % float(_record.get(property, 0.0)), 9, Kit.TEXT_DIM)
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value_label)
	var bar := ScrubBarScript.new()
	bar.min_value = min_value
	bar.max_value = max_value
	bar.value = float(_record.get(property, 0.0))
	bar.fill_color = Kit.FOCUS
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.value_changed.connect(func(value: float) -> void:
		value_label.text = "%.2f" % value
		if _ms != null and _id != "":
			_ms.update_material(_id, {property: value})
	)
	bar.drag_started.connect(func() -> void:
		if _doc != null:
			_doc.begin_edit("Edit material")
	)
	bar.drag_ended.connect(func() -> void:
		if _doc != null:
			_doc.end_edit()
		_record = _ms.get_material(_id) if _ms != null else {}
		changed.emit(_id)
	)
	host.add_child(bar)
	if emission:
		_emission_scrub = bar
	return bar


func _add_uv_field(parent: GridContainer, key: String, label_text: String, value: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label := Kit.label(label_text, 11, Kit.TEXT_MUTED)
	label.custom_minimum_size.x = 70
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var field = NumberFieldScript.new()
	field.axis = ""
	field.suffix = ""
	field.step = 0.05
	field.min_value = -1000.0
	field.max_value = 1000.0
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.set_value(value)
	field.text_committed.connect(func(new_value: float) -> void: _set_uv(key, new_value))
	row.add_child(field)
	_uv_fields[key] = field


func _set_uv(key: String, value: float) -> void:
	var scale: Array = _record.get("uv1_scale", [1.0, 1.0]).duplicate()
	var offset: Array = _record.get("uv1_offset", [0.0, 0.0]).duplicate()
	match key:
		"scale_x":
			scale[0] = value
		"scale_y":
			scale[1] = value
		"offset_x":
			offset[0] = value
		"offset_y":
			offset[1] = value
	_commit({"uv1_scale": scale, "uv1_offset": offset}, "Edit material UV")
	_record = _ms.get_material(_id) if _ms != null else {}


func _add_map_row(slot: String) -> void:
	var key := str(MAP_KEYS[slot])
	var path := str(_record.get(key, ""))
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 44.0
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	var thumbnail := PanelContainer.new()
	thumbnail.custom_minimum_size = Vector2(44.0, 44.0)
	var swatch := Color.from_string(str(_record.get("albedo_color", "#3A3A3A")), Kit.SURFACE_3) \
		if slot == "albedo" else Kit.SURFACE_3
	thumbnail.add_theme_stylebox_override("panel", Kit.flat_style(swatch, Kit.R_CONTROL, Kit.CONTROL_BORDER, 1))
	row.add_child(thumbnail)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)
	var label := Kit.label(str(MAP_LABELS[slot]), 11, Kit.TEXT_MUTED)
	info.add_child(label)
	var state := _texture_state(path)
	var state_label := Kit.label(str(state["text"]), 9, state["color"])
	state_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	info.add_child(state_label)
	var replace := Kit.text_button("Replace" if path != "" else "Import", "", false, true)
	replace.custom_minimum_size = Vector2(96.0, 44.0)
	replace.pressed.connect(func() -> void: _pick_map(slot))
	row.add_child(replace)
	var clear := Kit.text_button("Clear", "", false, true)
	clear.custom_minimum_size = Vector2(96.0, 44.0)
	clear.visible = path != ""
	clear.pressed.connect(func() -> void: clear_map(slot))
	row.add_child(clear)
	_map_rows[slot] = {
		"row": row,
		"label": label,
		"state": state_label,
		"replace": replace,
		"clear": clear,
		"thumbnail": thumbnail,
	}
	if slot == "orm":
		_orm_reason = Kit.label(ORM_LOCK_REASON, 10, Kit.TEXT_DIM)
		_orm_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_orm_reason.visible = false
		add_child(_orm_reason)


func _texture_state(path: String) -> Dictionary:
	if path == "":
		return {"text": "None", "color": Kit.TEXT_DIM}
	if _doc == null or str(_doc.project_dir) == "":
		return {"text": path, "color": Kit.WARNING}
	var absolute := str(_doc.project_dir).path_join(path)
	if not FileAccess.file_exists(absolute):
		return {"text": path, "color": Kit.WARNING}
	var image := Image.load_from_file(absolute)
	if image != null and not image.is_empty():
		return {"text": "%s · %dx%d" % [path.get_file(), image.get_width(), image.get_height()],
			"color": Kit.TEXT_MUTED}
	return {"text": path.get_file(), "color": Kit.TEXT_MUTED}


func _pick_map(slot: String) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		_set_error("This platform has no native file picker")
		return
	var filters := PackedStringArray([TEXTURE_FILTER])
	var error := DisplayServer.file_dialog_show(
		"Import texture", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters,
		func(status: bool, paths: PackedStringArray, _index: int) -> void:
			if status and not paths.is_empty():
				import_texture_file(paths[0], slot)
	)
	if error != OK:
		_set_error("The file picker could not be opened")


func import_texture_file(uri: String, slot: String) -> bool:
	if _doc == null or _ms == null or _id == "":
		return false
	var fallback := str(_record.get("name", "Material")) + " " + str(MAP_LABELS.get(slot, slot))
	var result: Dictionary = Store.import_texture(uri, str(_doc.project_dir), fallback)
	if not bool(result.get("ok", false)):
		_set_error(str(result.get("error", "The texture could not be imported.")))
		return false
	_commit({str(MAP_KEYS[slot]): str(result.get("rel_path", ""))}, "Import texture")
	_build()
	return true


func set_map(slot: String, rel_path: String) -> void:
	_commit({str(MAP_KEYS[slot]): rel_path}, "Set texture")
	_build()


func clear_map(slot: String) -> void:
	_commit({str(MAP_KEYS[slot]): ""}, "Clear texture")
	_build()


func _set_error(message: String) -> void:
	if _error_label != null:
		_error_label.text = message


func _commit(patch: Dictionary, label_text: String) -> void:
	if _doc == null or _ms == null or _id == "":
		return
	_doc.begin_edit(label_text)
	_ms.update_material(_id, patch)
	_doc.end_edit()
	_record = _ms.get_material(_id)
	changed.emit(_id)


func _on_duplicate() -> void:
	if _doc == null or _id == "":
		return
	_doc.begin_edit("Duplicate material")
	var copy_id: String = _ms.duplicate_material(_id)
	_doc.end_edit()
	if copy_id != "":
		_id = copy_id
		_record = _ms.get_material(_id)
		changed.emit(_id)
		_build()
