extends VBoxContainer
## IK chains: root/end dropdowns, target picker, weight, pole angle,
## iterations, enabled and Bake. The solver itself lives in ik_solver.gd.

signal changed

const ROW_HEIGHT := 44.0
const NumberFieldScript = preload("res://src/ui/num_field.gd")

var doc = null
var rig_system = null
var _rig_id := ""
var _root_picker: OptionButton
var _end_picker: OptionButton
var _target_picker: OptionButton
var _target_empty: Label
var _add_button: Button
var _rows_box: VBoxContainer
var _message: Label
var _chain_rows: Array[PanelContainer] = []
var _bake_button: Button


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


func get_chain_rows() -> Array:
	return _chain_rows


func _build() -> void:
	if _rows_box != null:
		return
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	add_child(header)
	var title := Kit.section_label("IK")
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_bake_button = Kit.text_button("Bake IK", "diamond-plus", true)
	_bake_button.name = "BakeIKButton"
	_bake_button.custom_minimum_size = Vector2(96, ROW_HEIGHT)
	_bake_button.pressed.connect(_on_bake)
	header.add_child(_bake_button)

	var form := HBoxContainer.new()
	form.add_theme_constant_override("separation", 4)
	add_child(form)
	_root_picker = _make_picker("RootBonePicker")
	form.add_child(_root_picker)
	_end_picker = _make_picker("EndBonePicker")
	form.add_child(_end_picker)
	_target_picker = _make_picker("IKTargetPicker")
	form.add_child(_target_picker)
	_add_button = Kit.text_button("Add chain", "plus", false, true)
	_add_button.name = "AddChainButton"
	_add_button.custom_minimum_size = Vector2(96, ROW_HEIGHT)
	_add_button.pressed.connect(_on_add_chain)
	form.add_child(_add_button)

	_target_empty = Kit.label("No target objects yet. Add an empty or mesh to use as an IK target.", Kit.TYPE_CAPTION, Kit.TEXT_MUTED)
	_target_empty.name = "IKTargetEmpty"
	_target_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_target_empty)

	_message = Kit.label("", Kit.TYPE_CAPTION, Kit.WARNING)
	_message.name = "IKMessage"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_message)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 4)
	add_child(_rows_box)


func _make_picker(name_value: String) -> OptionButton:
	var picker := OptionButton.new()
	picker.name = name_value
	picker.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return picker


func refresh() -> void:
	if _rows_box == null:
		return
	_message.text = ""
	_chain_rows.clear()
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	if rig_system == null or _rig_id == "":
		return
	var rig: Dictionary = rig_system.get_rig(_rig_id)
	if rig.is_empty():
		return
	var bones: Array = rig.get("bones", [])
	var previous_root := _selected_bone(_root_picker)
	var previous_end := _selected_bone(_end_picker)
	_root_picker.clear()
	_end_picker.clear()
	for bone in bones:
		var bone_name := str(bone.get("name", ""))
		_root_picker.add_item(bone_name)
		_root_picker.set_item_metadata(_root_picker.item_count - 1, bone_name)
		_end_picker.add_item(bone_name)
		_end_picker.set_item_metadata(_end_picker.item_count - 1, bone_name)
	_select_bone(_root_picker, previous_root if previous_root != "" else str(rig.get("active_bone", "")))
	_select_bone(_end_picker, previous_end if previous_end != "" else str(rig.get("active_bone", "")))

	var previous_target := _selected_object(_target_picker)
	_target_picker.clear()
	for obj in doc.objects:
		var kind := str(obj.get("kind", ""))
		if kind == "rig" or kind == "camera" or kind == "light":
			continue
		_target_picker.add_item(str(obj.get("name", "Object")))
		_target_picker.set_item_metadata(_target_picker.item_count - 1, str(obj.get("id", "")))
	_target_empty.visible = _target_picker.item_count == 0
	_add_button.disabled = _target_picker.item_count == 0
	_select_object(_target_picker, previous_target)

	for chain in rig.get("ik", []):
		var row := _make_chain_row(rig, chain)
		_rows_box.add_child(row)
		_chain_rows.append(row)


func _selected_bone(picker: OptionButton) -> String:
	if picker == null or picker.selected < 0:
		return ""
	return str(picker.get_item_metadata(picker.selected))


func _selected_object(picker: OptionButton) -> String:
	if picker == null or picker.selected < 0:
		return ""
	return str(picker.get_item_metadata(picker.selected))


func _select_bone(picker: OptionButton, bone_name: String) -> void:
	for i in range(picker.item_count):
		if str(picker.get_item_metadata(i)) == bone_name:
			picker.select(i)
			return


func _select_object(picker: OptionButton, object_id: String) -> void:
	for i in range(picker.item_count):
		if str(picker.get_item_metadata(i)) == object_id:
			picker.select(i)
			return


func _on_add_chain() -> void:
	if rig_system == null or _rig_id == "":
		return
	var root := _selected_bone(_root_picker)
	var end := _selected_bone(_end_picker)
	var target := _selected_object(_target_picker)
	if root == "" or end == "" or target == "":
		_message.text = "Choose a root bone, an end bone and a target object."
		return
	var chain_id: String = rig_system.add_ik_chain(_rig_id, root, end, target)
	if chain_id == "":
		_message.text = "The end bone must be a descendant of the root bone."
		return
	changed.emit()
	refresh()


func _make_chain_row(rig: Dictionary, chain: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.name = "IKChainRow"
	row.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_2, 0, Kit.BORDER_SOFT, 1))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	row.add_child(body)
	var chain_id := str(chain.get("id", ""))

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	body.add_child(head)
	var title := Kit.label(str(chain.get("name", "IK")), Kit.TYPE_BODY, Kit.TEXT, 500)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var enabled := Kit.text_toggle("Enabled", "", true)
	enabled.name = "IKEnabled"
	enabled.custom_minimum_size = Vector2(96, ROW_HEIGHT)
	enabled.button_pressed = bool(chain.get("enabled", true))
	enabled.toggled.connect(func(pressed: bool) -> void:
		rig_system.update_ik_chain(_rig_id, chain_id, {"enabled": pressed})
		changed.emit())
	head.add_child(enabled)
	var remove := Kit.icon_button("trash-2", "Delete IK chain", 44, 18)
	remove.name = "DeleteIKChain"
	remove.pressed.connect(func() -> void:
		rig_system.delete_ik_chain(_rig_id, chain_id)
		changed.emit()
		refresh())
	head.add_child(remove)

	var target_id := str(chain.get("target_object_id", ""))
	var target_name := "No target"
	if doc != null and doc.nodes.has(target_id):
		target_name = str(doc.get_object(target_id).get("name", target_id))
	var target_label := Kit.mono_label("%s → %s" % [str(chain.get("root", "")), str(chain.get("end", ""))], Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	body.add_child(target_label)
	var target := Kit.label("Target: %s" % target_name, Kit.TYPE_CAPTION, Kit.TEXT_MUTED)
	target.name = "IKTargetLabel"
	body.add_child(target)

	var fields := HBoxContainer.new()
	fields.add_theme_constant_override("separation", 4)
	body.add_child(fields)
	var weight: PanelContainer = _make_number("Weight", float(chain.get("weight", 1.0)), 0.0, 1.0, 0.01)
	weight.name = "IKWeightField"
	weight.value_changed.connect(func(value: float) -> void:
		rig_system.update_ik_chain(_rig_id, chain_id, {"weight": value}))
	fields.add_child(weight)
	var pole: PanelContainer = _make_number("Pole", rad_to_deg(float(chain.get("pole_angle", 0.0))), -360.0, 360.0, 1.0)
	pole.name = "IKPoleField"
	pole.suffix = "°"
	pole.value_changed.connect(func(value: float) -> void:
		rig_system.update_ik_chain(_rig_id, chain_id, {"pole_angle": deg_to_rad(value)}))
	fields.add_child(pole)
	var iterations := SpinBox.new()
	iterations.name = "IKIterationsField"
	iterations.custom_minimum_size = Vector2(84, ROW_HEIGHT)
	iterations.min_value = 8
	iterations.max_value = 24
	iterations.step = 1
	iterations.value = int(chain.get("iterations", 12))
	iterations.value_changed.connect(func(value: float) -> void:
		rig_system.update_ik_chain(_rig_id, chain_id, {"iterations": int(value)}))
	fields.add_child(iterations)
	return row


func _make_number(axis: String, value: float, minimum: float, maximum: float, step: float) -> PanelContainer:
	var field = NumberFieldScript.new()
	field.axis = axis
	field.min_value = minimum
	field.max_value = maximum
	field.step = step
	field.set_value_silent(value)
	field.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	return field


func _on_bake() -> void:
	if rig_system == null or _rig_id == "":
		return
	if rig_system.bake_ik(_rig_id):
		_message.text = "Baked IK rotations at the current time."
		changed.emit()
	else:
		_message.text = "No enabled IK chain with a target to bake."
