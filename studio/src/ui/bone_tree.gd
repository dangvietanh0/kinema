extends VBoxContainer
## Bone tree for the rig tab.
##
## Rows are 44 dp and indent 12 dp per depth. Add/rename/reparent/delete are
## guarded in the rig system; this control only collects the intent and shows
## the reason when an operation is refused.

signal bone_selected(bone: String)
signal changed

const ROW_HEIGHT := 44.0
const INDENT := 12.0

var doc = null
var rig_system = null
var _rig_id := ""
var _rows: Array[Button] = []
var _list: VBoxContainer
var _message: Label
var _rename_row: HBoxContainer
var _rename_field: LineEdit
var _reparent_row: HBoxContainer
var _reparent_picker: OptionButton
var _delete_button: Button
var _pending_delete := false
var _add_button: Button
var _rename_button: Button
var _reparent_button: Button


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	_build()


func setup(document, rig_system_ref) -> void:
	doc = document
	rig_system = rig_system_ref
	if not is_inside_tree():
		return
	_build()
	refresh()


func set_rig(rig_id: String) -> void:
	_rig_id = rig_id
	refresh()


func get_bone_rows() -> Array:
	return _rows


func indent_for_depth(depth: int) -> int:
	return int(depth * INDENT)


func _build() -> void:
	if _list != null:
		return
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	add_child(header)
	var title := Kit.section_label("Bones")
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_add_button = Kit.text_button("Add bone", "plus", false, true)
	_add_button.name = "AddBoneButton"
	_add_button.custom_minimum_size = Vector2(96, ROW_HEIGHT)
	_add_button.pressed.connect(_on_add)
	header.add_child(_add_button)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	add_child(_list)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	add_child(actions)
	_rename_button = Kit.text_button("Rename", "", false, true)
	_rename_button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	_rename_button.pressed.connect(_show_rename)
	actions.add_child(_rename_button)
	_reparent_button = Kit.text_button("Reparent", "", false, true)
	_reparent_button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	_reparent_button.pressed.connect(_show_reparent)
	actions.add_child(_reparent_button)
	_delete_button = Kit.text_button("Delete", "trash-2", false, true)
	_delete_button.name = "DeleteBoneButton"
	_delete_button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	_delete_button.pressed.connect(_on_delete)
	actions.add_child(_delete_button)

	_rename_row = HBoxContainer.new()
	_rename_row.add_theme_constant_override("separation", 4)
	_rename_row.visible = false
	add_child(_rename_row)
	_rename_field = Kit.line_edit("Bone name")
	_rename_field.name = "RenameBoneField"
	_rename_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rename_row.add_child(_rename_field)
	var rename_ok := Kit.text_button("Rename", "check", true)
	rename_ok.name = "ConfirmRenameBone"
	rename_ok.custom_minimum_size = Vector2(96, ROW_HEIGHT)
	rename_ok.pressed.connect(_confirm_rename)
	_rename_row.add_child(rename_ok)

	_reparent_row = HBoxContainer.new()
	_reparent_row.add_theme_constant_override("separation", 4)
	_reparent_row.visible = false
	add_child(_reparent_row)
	_reparent_picker = OptionButton.new()
	_reparent_picker.name = "ReparentBonePicker"
	_reparent_picker.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	_reparent_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reparent_row.add_child(_reparent_picker)
	var reparent_ok := Kit.text_button("Move", "check", true)
	reparent_ok.name = "ConfirmReparentBone"
	reparent_ok.custom_minimum_size = Vector2(96, ROW_HEIGHT)
	reparent_ok.pressed.connect(_confirm_reparent)
	_reparent_row.add_child(reparent_ok)

	_message = Kit.label("", Kit.TYPE_CAPTION, Kit.WARNING)
	_message.name = "BoneTreeMessage"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_message)


func refresh() -> void:
	if _list == null:
		return
	_rows.clear()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_message.text = ""
	_pending_delete = false
	_delete_button.text = "Delete"
	if rig_system == null or _rig_id == "":
		return
	var rig: Dictionary = rig_system.get_rig(_rig_id)
	if rig.is_empty():
		return
	var bones: Array = rig.get("bones", [])
	var active := str(rig.get("active_bone", ""))
	for i in range(bones.size()):
		var bone: Dictionary = bones[i]
		var depth := _depth_of(bones, i)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		_list.add_child(row)
		var indent := Control.new()
		indent.custom_minimum_size = Vector2(indent_for_depth(depth), ROW_HEIGHT)
		indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(indent)
		var button := Kit.text_button(str(bone.get("name", "")), "", false, false)
		button.name = "BoneRow"
		button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.set_meta("bone_name", str(bone.get("name", "")))
		if str(bone.get("name", "")) == active:
			button.add_theme_color_override("font_color", Kit.FOCUS_BRIGHT)
			button.add_theme_stylebox_override("normal", Kit.flat_style(Kit.SURFACE_3, 0, Color(0, 0, 0, 0), 0))
		button.pressed.connect(_select_bone.bind(str(bone.get("name", ""))))
		row.add_child(button)
		_rows.append(button)


func _depth_of(bones: Array, index: int) -> int:
	var depth := 0
	var cursor := int(bones[index].get("parent", -1))
	var guard := 0
	while cursor >= 0 and cursor < bones.size() and guard < 64:
		depth += 1
		cursor = int(bones[cursor].get("parent", -1))
		guard += 1
	return depth


func _select_bone(bone: String) -> void:
	if rig_system == null or _rig_id == "":
		return
	rig_system.set_active_bone(_rig_id, bone)
	bone_selected.emit(bone)
	refresh()


func _on_add() -> void:
	if rig_system == null or _rig_id == "":
		return
	var rig: Dictionary = rig_system.get_rig(_rig_id)
	if rig.is_empty():
		return
	var parent := str(rig.get("active_bone", ""))
	var base := "Bone"
	var name := base
	var n := 2
	var names: Array = []
	for bone in rig.get("bones", []):
		names.append(str(bone.get("name", "")))
	while names.has(name):
		name = "%s %d" % [base, n]
		n += 1
	var index: int = rig_system.add_bone(_rig_id, name, parent, {
		"p": Vector3(0, 0.4, 0),
		"r": Quaternion.IDENTITY,
		"s": Vector3.ONE,
		"length": 0.4,
	})
	if index < 0:
		_message.text = "Could not add a bone under %s." % parent
		return
	rig_system.set_active_bone(_rig_id, name)
	changed.emit()
	refresh()


func _show_rename() -> void:
	if rig_system == null or _rig_id == "":
		return
	var rig: Dictionary = rig_system.get_rig(_rig_id)
	if rig.is_empty():
		return
	_rename_field.text = str(rig.get("active_bone", ""))
	_rename_row.visible = true
	_reparent_row.visible = false
	_rename_field.grab_focus()


func _confirm_rename() -> void:
	if rig_system == null or _rig_id == "":
		return
	var rig: Dictionary = rig_system.get_rig(_rig_id)
	var active := str(rig.get("active_bone", ""))
	if rig_system.rename_bone(_rig_id, active, _rename_field.text):
		_rename_row.visible = false
		changed.emit()
		refresh()
	else:
		_message.text = "Rename failed: the name is empty or already used."


func _show_reparent() -> void:
	if rig_system == null or _rig_id == "":
		return
	var rig: Dictionary = rig_system.get_rig(_rig_id)
	if rig.is_empty():
		return
	var active := str(rig.get("active_bone", ""))
	_reparent_picker.clear()
	_reparent_picker.add_item("None (root)")
	_reparent_picker.set_item_metadata(0, "")
	for bone in rig.get("bones", []):
		var bone_name := str(bone.get("name", ""))
		if bone_name == active:
			continue
		_reparent_picker.add_item(bone_name)
		_reparent_picker.set_item_metadata(_reparent_picker.item_count - 1, bone_name)
	_rename_row.visible = false
	_reparent_row.visible = true


func _confirm_reparent() -> void:
	if rig_system == null or _rig_id == "":
		return
	var rig: Dictionary = rig_system.get_rig(_rig_id)
	var active := str(rig.get("active_bone", ""))
	var parent := ""
	if _reparent_picker.selected >= 0:
		parent = str(_reparent_picker.get_item_metadata(_reparent_picker.selected))
	if rig_system.set_bone_parent(_rig_id, active, parent):
		_reparent_row.visible = false
		changed.emit()
		refresh()
	else:
		_message.text = "Reparent failed: that parent would create a cycle."


func _on_delete() -> void:
	if rig_system == null or _rig_id == "":
		return
	if not _pending_delete:
		_pending_delete = true
		_delete_button.text = "Confirm delete"
		var rig: Dictionary = rig_system.get_rig(_rig_id)
		_message.text = "Delete %s? Children, skins, IK and poses must not reference it." % str(rig.get("active_bone", "bone"))
		return
	var rig: Dictionary = rig_system.get_rig(_rig_id)
	var active := str(rig.get("active_bone", ""))
	_pending_delete = false
	_delete_button.text = "Delete"
	if rig_system.remove_bone(_rig_id, active):
		changed.emit()
		refresh()
	else:
		_message.text = "Cannot delete %s: it still has children, a skin, an IK chain or a pose." % active
