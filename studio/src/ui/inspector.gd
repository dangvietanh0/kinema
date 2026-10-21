extends VBoxContainer
## Object properties for the selected scene object.
##
## Fields are created once per selection and then refreshed from the document.
## Dragging a field or slider opens a single history entry, while typed values
## commit as one discrete edit.

signal add_requested
signal color_requested(property: String)

const NumberFieldScript = preload("res://src/ui/num_field.gd")
const ScrubBarScript = preload("res://src/ui/scrub_bar.gd")
const AXIS_COLORS := [Color(0.851, 0.412, 0.384), Color(0.514, 0.710, 0.427), Color(0.365, 0.553, 0.847)]

const DocumentScript = preload("res://src/core/document.gd")
var doc: DocumentScript = null

var _scroll: ScrollContainer
var _content: VBoxContainer
var _badge: Label
var _name_edit: LineEdit
var _built_for := ""
var _updating := false
var _fields: Dictionary = {"position": [], "rotation": [], "scale": []}
var _scrubs: Dictionary = {}
var _scrub_values: Dictionary = {}
var _color_button: Button
var _key_buttons: Dictionary = {}
var _swatch_value := Color(0.6, 0.6, 0.6)
var _field_drag := false

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)
	_build_shell()

func setup(document: Node3D) -> void:
	doc = document
	doc.selection_changed.connect(_on_selection_changed)
	doc.object_changed.connect(_on_object_changed)
	doc.scene_changed.connect(_on_scene_changed)
	_rebuild()

func _build_shell() -> void:
	if _content != null:
		return
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 12)
	header_margin.add_theme_constant_override("margin_right", 12)
	header_margin.add_theme_constant_override("margin_top", 10)
	header_margin.add_theme_constant_override("margin_bottom", 6)
	add_child(header_margin)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header_margin.add_child(header)
	var title := Kit.section_label("Object")
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_badge = Kit.mono_label("", 9, Kit.TEXT_DIM)
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_badge)

	add_child(Kit.vsep())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 16)
	_scroll.add_child(margin)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	margin.add_child(_content)

func _on_selection_changed(_id: String) -> void:
	_rebuild()

func _on_scene_changed() -> void:
	if doc == null:
		return
	if doc.selected_id != _built_for or not doc.nodes.has(_built_for):
		_rebuild()
	elif _built_for != "":
		_refresh_values()
		_refresh_keys()

func _on_object_changed(id: String) -> void:
	if id != _built_for:
		return
	_refresh_values()
	_refresh_keys()

func _rebuild() -> void:
	if _content == null:
		return
	if _field_drag:
		_field_drag = false
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_fields = {"position": [], "rotation": [], "scale": []}
	_scrubs.clear()
	_scrub_values.clear()
	_key_buttons.clear()
	_color_button = null
	_name_edit = null
	_built_for = ""
	_badge.text = ""
	_scroll.scroll_vertical = 0

	if doc == null or doc.selected_id == "" or not doc.nodes.has(doc.selected_id):
		_build_empty()
		return
	var obj: Dictionary = doc.get_selected_object()
	if obj.is_empty():
		_build_empty()
		return
	_built_for = str(obj.get("id", ""))
	_badge.text = _kind_badge(obj)
	_build_identity(obj)
	_build_transform_section()
	_build_specifics(obj)
	_build_actions()
	_refresh_values()
	_refresh_keys()

func _build_empty() -> void:
	var wrap := VBoxContainer.new()
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_theme_constant_override("separation", 8)
	wrap.custom_minimum_size.y = 180
	_content.add_child(wrap)
	var icon := Kit.icon("mouse-pointer-click", Kit.TEXT_DIM, 26)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrap.add_child(icon)
	var title := Kit.label("Nothing selected", 12, Kit.TEXT_MUTED, 500)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(title)
	var hint := Kit.label("Tap an object in the viewport or the scene list to edit its transforms.", 10, Kit.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wrap.add_child(hint)
	var add := Kit.text_button("Add object", "plus", false, true)
	add.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add.pressed.connect(func() -> void: add_requested.emit())
	wrap.add_child(add)

func _build_identity(obj: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)

	var icon := Kit.icon(_icon_for(obj), Kit.TEXT_MUTED, 16)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	_name_edit = Kit.line_edit("Object name", 13)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text = str(obj.get("name", "Object"))
	_name_edit.text_submitted.connect(_on_name_submitted)
	_name_edit.focus_exited.connect(_on_name_focus_lost)
	row.add_child(_name_edit)

func _build_transform_section() -> void:
	_content.add_child(Kit.vsep())
	for channel in doc.CHANNELS:
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 4)
		_content.add_child(section)

		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 4)
		section.add_child(head)
		var channel_label := Kit.label(str(doc.CHANNEL_LABELS.get(channel, channel)).to_upper(), 9, Kit.TEXT_MUTED, 600)
		channel_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(channel_label)
		var head_spacer := Control.new()
		head_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(head_spacer)
		var key_button := Kit.icon_button("diamond-plus", "Key " + channel, 22, 11)
		key_button.pressed.connect(_on_key_channel.bind(channel))
		head.add_child(key_button)
		_key_buttons[channel] = key_button

		var fields := HBoxContainer.new()
		fields.add_theme_constant_override("separation", 4)
		section.add_child(fields)
		for i in range(3):
			var field = NumberFieldScript.new()
			field.axis = ["X", "Y", "Z"][i]
			field.axis_color = AXIS_COLORS[i]
			field.suffix = ""
			if channel == "position":
				field.step = 0.02
				field.min_value = -10000.0
				field.max_value = 10000.0
			elif channel == "rotation":
				field.step = 0.6
				field.min_value = -3600.0
				field.max_value = 3600.0
			else:
				field.step = 0.01
				field.min_value = 0.01
				field.max_value = 1000.0
			field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			fields.add_child(field)
			_fields[channel].append(field)
			field.drag_started.connect(_on_field_drag_started.bind(channel))
			field.drag_ended.connect(_on_field_drag_ended)
			field.value_changed.connect(_on_field_value_changed.bind(channel, i))
			field.text_committed.connect(_on_field_text_committed.bind(channel, i))

	var key_all := Kit.text_button("Insert all transform keys", "diamond-plus", false, true)
	key_all.pressed.connect(_on_key_all)
	_content.add_child(key_all)
	_content.add_child(Kit.vsep())

func _build_specifics(obj: Dictionary) -> void:
	var kind := str(obj.get("kind", "mesh"))
	if kind == "mesh":
		_build_material(obj)
	elif kind == "light":
		_build_light(obj)
	elif kind == "camera":
		_build_camera(obj)
	elif kind == "import":
		_build_import(obj)
	else:
		var hint := Kit.label("An empty transform. Use it as a motion anchor for other objects.", 11, Kit.TEXT_DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(hint)
	_content.add_child(Kit.vsep())

func _build_material(obj: Dictionary) -> void:
	_content.add_child(Kit.section_label("Material"))
	_build_color_row("Base color", "color", str(obj.get("color", "#AAB2BF")))
	_add_scrub("Roughness", "roughness", 0.0, 1.0)
	_add_scrub("Metallic", "metallic", 0.0, 1.0)

func _build_light(obj: Dictionary) -> void:
	_content.add_child(Kit.section_label("Light"))
	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 6)
	_content.add_child(type_row)
	var type_label := Kit.label("Type", 11, Kit.TEXT_MUTED)
	type_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_row.add_child(type_label)
	var omni := str(obj.get("light_type", "directional")) == "omni"
	type_row.add_child(Kit.mono_label("OMNI" if omni else "DIRECTIONAL", 9, Kit.TEXT_DIM))
	_build_color_row("Light color", "light_color", str(obj.get("light_color", "#FFE8CA")))
	_add_scrub("Energy", "light_energy", 0.0, 6.0)
	if omni:
		_add_scrub("Range", "light_range", 0.5, 40.0)

func _build_camera(obj: Dictionary) -> void:
	_content.add_child(Kit.section_label("Camera"))
	_add_scrub("Field of view", "camera_fov", 12.0, 100.0)
	var hint := Kit.label("The viewport uses its own editor camera. This camera object is a scene element for layout reference.", 10, Kit.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(hint)

func _build_import(obj: Dictionary) -> void:
	_content.add_child(Kit.section_label("Model"))
	var rel := str(obj.get("model", ""))
	var exists := rel != "" and doc.project_dir != "" and FileAccess.file_exists(doc.project_dir.path_join(rel))
	var path_label := Kit.mono_label(rel if rel != "" else "No file", 9, Kit.TEXT_MUTED if exists else Kit.DANGER)
	path_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_content.add_child(path_label)
	if not exists:
		var missing := Kit.label("The model file is missing from this project folder.", 10, Kit.DANGER)
		missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(missing)

func _build_color_row(label_text: String, property: String, hex: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)
	var label := Kit.label(label_text, 11, Kit.TEXT_MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var hex_label := Kit.mono_label(hex.to_upper(), 9, Kit.TEXT_DIM)
	hex_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hex_label)
	_color_button = Button.new()
	_color_button.custom_minimum_size = Vector2(30, 24)
	_color_button.focus_mode = Control.FOCUS_NONE
	_color_button.tooltip_text = "Choose %s" % label_text.to_lower()
	_color_button.set_meta("property", property)
	_color_button.set_meta("hex_label", hex_label)
	_color_button.pressed.connect(func() -> void: color_requested.emit(property))
	row.add_child(_color_button)
	_set_swatch(str_to_var_hex(hex))

func _add_scrub(label_text: String, property: String, min_value: float, max_value: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)
	var label := Kit.label(label_text, 11, Kit.TEXT_MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var value_label := Kit.mono_label("0.00", 9, Kit.TEXT_DIM)
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value_label)

	var bar = ScrubBarScript.new()
	bar.min_value = min_value
	bar.max_value = max_value
	bar.fill_color = Kit.ACCENT
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.value_changed.connect(_on_scrub_changed.bind(property))
	bar.drag_started.connect(_on_scrub_drag_started.bind(property))
	bar.drag_ended.connect(_on_scrub_drag_ended)
	_content.add_child(bar)
	_scrubs[property] = bar
	_scrub_values[property] = value_label

func _build_actions() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_content.add_child(row)
	var duplicate := Kit.text_button("Duplicate", "copy", false, true)
	duplicate.alignment = HORIZONTAL_ALIGNMENT_LEFT
	duplicate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duplicate.pressed.connect(_on_duplicate)
	row.add_child(duplicate)
	var delete := Kit.text_button("Delete", "trash-2", false, true)
	delete.alignment = HORIZONTAL_ALIGNMENT_LEFT
	delete.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete.add_theme_color_override("font_color", Kit.DANGER)
	delete.add_theme_color_override("icon_normal_color", Kit.DANGER)
	delete.pressed.connect(_on_delete)
	row.add_child(delete)

# -------------------------------------------------------------------------
# Editing
# -------------------------------------------------------------------------

func _on_field_drag_started(channel: String) -> void:
	if doc == null or _built_for == "":
		return
	_field_drag = true
	doc.begin_edit("Transform " + channel)

func _on_field_drag_ended() -> void:
	if doc == null:
		return
	_field_drag = false
	doc.end_edit()

func _on_field_value_changed(value: float, channel: String, axis: int) -> void:
	if _updating or doc == null or _built_for == "":
		return
	_apply_field(channel, axis, value)

func _on_field_text_committed(value: float, channel: String, axis: int) -> void:
	if doc == null or _built_for == "":
		return
	doc.begin_edit("Transform " + channel)
	_apply_field(channel, axis, value)
	doc.end_edit()

func _apply_field(channel: String, axis: int, value: float) -> void:
	var node: Node3D = doc.nodes.get(_built_for)
	if node == null:
		return
	var pos := node.position
	var rot := node.quaternion
	var scl := node.scale
	match channel:
		"position":
			pos[axis] = value
		"rotation":
			var euler := rot.get_euler()
			euler[axis] = deg_to_rad(value)
			rot = Quaternion.from_euler(euler)
		"scale":
			scl[axis] = maxf(0.01, value)
	doc.set_object_transform(_built_for, pos, rot, scl)
	_refresh_values()

func _refresh_values() -> void:
	if doc == null or _built_for == "" or _updating:
		return
	var node: Node3D = doc.nodes.get(_built_for)
	if node == null:
		return
	var obj: Dictionary = doc.get_object(_built_for)
	if obj.is_empty():
		return
	_updating = true
	var pos := node.position
	var rot_deg := node.quaternion.get_euler() * (180.0 / PI)
	var scl := node.scale
	var values := {
		"position": [pos.x, pos.y, pos.z],
		"rotation": [rot_deg.x, rot_deg.y, rot_deg.z],
		"scale": [scl.x, scl.y, scl.z],
	}
	for channel in values:
		var fields: Array = _fields.get(channel, [])
		for i in range(mini(fields.size(), 3)):
			fields[i].set_value(values[channel][i])
	if _name_edit != null and not _name_edit.has_focus():
		_name_edit.text = str(obj.get("name", "Object"))
	var material_props := {
		"roughness": float(obj.get("roughness", 0.48)),
		"metallic": float(obj.get("metallic", 0.0)),
		"light_energy": float(obj.get("light_energy", 1.2)),
		"light_range": float(obj.get("light_range", 8.0)),
		"camera_fov": float(obj.get("camera_fov", 45.0)),
	}
	for property in _scrubs:
		var bar = _scrubs[property]
		var value := float(material_props.get(property, 0.0))
		bar.set_value(value)
		if _scrub_values.has(property):
			_scrub_values[property].text = _format_scrub(value)
	if _color_button != null:
		var property := str(_color_button.get_meta("property", "color"))
		var hex := str(obj.get(property, "#AAB2BF"))
		_set_swatch(str_to_var_hex(hex))
		var hex_label = _color_button.get_meta("hex_label", null)
		if hex_label != null:
			hex_label.text = hex.to_upper()
	_updating = false

func _format_scrub(value: float) -> String:
	if absf(value) >= 100.0:
		return "%.0f" % value
	return "%.2f" % value

func _set_swatch(color: Color) -> void:
	_swatch_value = color
	if _color_button == null:
		return
	var normal := Kit.flat_style(color, 4, Kit.BORDER, 1)
	var hover := Kit.flat_style(color.lightened(0.08), 4, Kit.TEXT_MUTED, 1)
	var pressed := Kit.flat_style(color.darkened(0.08), 4, Kit.ACCENT, 1)
	_color_button.add_theme_stylebox_override("normal", normal)
	_color_button.add_theme_stylebox_override("hover", hover)
	_color_button.add_theme_stylebox_override("pressed", pressed)
	_color_button.add_theme_stylebox_override("focus", Kit.flat_style(Color(0, 0, 0, 0), 4, Kit.ACCENT, 1))

func str_to_var_hex(hex: String) -> Color:
	return Color.from_string(hex, Color(0.667, 0.698, 0.749))

func _refresh_keys() -> void:
	if doc == null or _built_for == "":
		return
	for channel in _key_buttons:
		var button: Button = _key_buttons[channel]
		var has_key := doc.get_key_index_at(_built_for, channel, doc.current_time, 0.5 / float(doc.fps)) >= 0
		button.add_theme_color_override("icon_normal_color", Kit.ACCENT if has_key else Kit.TEXT_MUTED)
		button.add_theme_color_override("icon_hover_color", Kit.ACCENT_BRIGHT if has_key else Kit.TEXT)
		button.tooltip_text = ("Replace" if has_key else "Insert") + " " + channel + " key"

func _on_key_channel(channel: String) -> void:
	if doc == null or _built_for == "":
		return
	doc.insert_channel_key(channel)
	_refresh_keys()

func _on_key_all() -> void:
	if doc == null or _built_for == "":
		return
	doc.insert_transform_keys()
	_refresh_keys()

func _on_scrub_drag_started(_property: String) -> void:
	if doc == null or _built_for == "":
		return
	doc.begin_edit("Material")

func _on_scrub_changed(value: float, property: String) -> void:
	if _updating or doc == null or _built_for == "":
		return
	if property == "camera_fov":
		doc.set_camera_fov(_built_for, value)
	elif property.begins_with("light_"):
		doc.set_light_property(_built_for, property, value)
	else:
		doc.set_material_property(_built_for, property, value)
	if _scrub_values.has(property):
		_scrub_values[property].text = _format_scrub(value)

func _on_scrub_drag_ended() -> void:
	if doc == null:
		return
	doc.end_edit()

func _on_name_submitted(_text: String) -> void:
	_commit_name()

func _on_name_focus_lost() -> void:
	_commit_name()

func _commit_name() -> void:
	if doc == null or _built_for == "" or _name_edit == null:
		return
	var clean := _name_edit.text.strip_edges()
	var current := str(doc.get_object(_built_for).get("name", ""))
	if clean == "":
		_name_edit.text = current
		return
	if clean == current:
		return
	doc.rename_object(_built_for, clean)

func _on_duplicate() -> void:
	if doc != null:
		doc.duplicate_selected()

func _on_delete() -> void:
	if doc != null:
		doc.delete_selected()

func _kind_badge(obj: Dictionary) -> String:
	match str(obj.get("kind", "mesh")):
		"mesh": return str(obj.get("primitive", "box")).to_upper()
		"import": return "GLTF"
		"camera": return "CAMERA"
		"light": return "OMNI" if str(obj.get("light_type", "")) == "omni" else "SUN"
	return str(obj.get("kind", "OBJECT")).to_upper()

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
