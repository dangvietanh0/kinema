extends VBoxContainer
## Rig tab: skeleton, bind job, bone keys, poses and IK in one scrollable
## inspector. The integrator adds this panel to the dock and connects the
## overlay; nothing here edits the editor shell.

signal rig_mode_changed(enabled: bool)
signal import_model_requested

const BoneTreeScript = preload("res://src/ui/bone_tree.gd")
const PosePanelScript = preload("res://src/ui/pose_panel.gd")
const IkPanelScript = preload("res://src/ui/ik_panel.gd")
const NumberFieldScript = preload("res://src/ui/num_field.gd")
const ROW_HEIGHT := 44.0

var doc = null
var rig_system = null
var _scroll: ScrollContainer
var _content: VBoxContainer
var _empty_box: VBoxContainer
var _empty_label: Label
var _empty_add: Button
var _empty_import: Button
var _sections: VBoxContainer
var _mode_label: Label
var _mode_hint: Label
var _mode := "pose"
var _rig_picker: OptionButton
var _tree: VBoxContainer
var _inspector: VBoxContainer
var _inspector_title: Label
var _imported_note: Label
var _px: PanelContainer
var _py: PanelContainer
var _pz: PanelContainer
var _rx: PanelContainer
var _ry: PanelContainer
var _rz: PanelContainer
var _sx: PanelContainer
var _sy: PanelContainer
var _sz: PanelContainer
var _pose_px: PanelContainer
var _pose_py: PanelContainer
var _pose_pz: PanelContainer
var _pose_rx: PanelContainer
var _pose_ry: PanelContainer
var _pose_rz: PanelContainer
var _pose_sx: PanelContainer
var _pose_sy: PanelContainer
var _pose_sz: PanelContainer
var _rest_section: VBoxContainer
var _pose_section: VBoxContainer
var _length_field: PanelContainer
var _influence_field: PanelContainer
var _reset_button: Button
var _reset_all_button: Button
var _bind_picker: OptionButton
var _bind_button: Button
var _rebind_button: Button
var _unbind_button: Button
var _bind_progress: ProgressBar
var _bind_summary: Label
var _rebind_note: Label
var _key_bone_label: Label
var _key_count_label: Label
var _key_prev: Button
var _key_next: Button
var _key_delete: Button
var _key_bone: Button
var _key_pose: Button
var _pose_panel: VBoxContainer
var _ik_panel: VBoxContainer
var _selected_mesh := ""
var _active_job := ""
var _key_index := 0
var _updating := false
var _refreshing := false
var _connected := false


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)
	_build_shell()
	visibility_changed.connect(_on_visibility_changed)
	set_process(true)


func setup(document) -> void:
	doc = document
	rig_system = doc.rig_system if doc != null else null
	if not _connected and doc != null:
		_connected = true
		doc.rigs_changed.connect(_on_rigs_changed)
		doc.rig_selection_changed.connect(_on_rig_selection_changed)
		doc.scene_changed.connect(_on_scene_changed)
		doc.object_spawned.connect(_on_object_spawned)
		doc.keyframes_changed.connect(func(_id: String) -> void: _refresh_keys())
	_build_shell()
	if _tree != null:
		_tree.setup(doc, rig_system)
	if _pose_panel != null:
		_pose_panel.setup(doc, rig_system)
	if _ik_panel != null:
		_ik_panel.setup(doc, rig_system)
	refresh()


func empty_state_visible() -> bool:
	return _empty_box != null and _empty_box.visible


func empty_text() -> String:
	return _empty_label.text if _empty_label != null else ""


func empty_add_button() -> Button:
	return _empty_add


func empty_import_button() -> Button:
	return _empty_import


func mode() -> String:
	return _mode


## Mirrors the viewport mode. The panel is a reader here: the overlay owns the
## mode and the floating toolbar owns the switch.
func set_mode(mode: String) -> void:
	_mode = mode if mode in ["pose", "edit"] else "pose"
	if _mode_label == null:
		return
	if _mode == "edit":
		_mode_label.text = "Edit"
		_mode_label.add_theme_color_override("font_color", Kit.FOCUS_BRIGHT)
		_mode_hint.text = "Edit · drag the body to rotate, or the head/tail handles. One drag is one undo."
	else:
		_mode_label.text = "Pose"
		_mode_label.add_theme_color_override("font_color", Kit.TEXT_MUTED)
		_mode_hint.text = "Pose · drag a bone to rotate, or use the gizmo."


func _build_shell() -> void:
	if _scroll != null:
		return
	var mode_margin := MarginContainer.new()
	mode_margin.add_theme_constant_override("margin_left", 12)
	mode_margin.add_theme_constant_override("margin_right", 12)
	mode_margin.add_theme_constant_override("margin_top", 4)
	mode_margin.add_theme_constant_override("margin_bottom", 4)
	add_child(mode_margin)
	var mode_box := VBoxContainer.new()
	mode_box.add_theme_constant_override("separation", 2)
	mode_margin.add_child(mode_box)
	_mode_label = Kit.mono_label("Pose", Kit.TYPE_CAPTION, Kit.FOCUS_BRIGHT)
	_mode_label.name = "RigModeLabel"
	mode_box.add_child(_mode_label)
	_mode_hint = Kit.label("Pose · drag a bone to rotate, or use the gizmo.", Kit.TYPE_CAPTION, Kit.TEXT_MUTED)
	_mode_hint.name = "RigModeHint"
	_mode_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	mode_box.add_child(_mode_hint)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Kit.style_scroll_container(_scroll)
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

	_empty_box = VBoxContainer.new()
	_empty_box.name = "RigEmptyState"
	_empty_box.add_theme_constant_override("separation", 10)
	_content.add_child(_empty_box)

	_empty_label = Kit.label("No rig on the selected object.", Kit.TYPE_BODY, Kit.TEXT_MUTED)
	_empty_label.name = "RigEmpty"
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_box.add_child(_empty_label)

	var empty_actions := HBoxContainer.new()
	empty_actions.add_theme_constant_override("separation", 8)
	_empty_box.add_child(empty_actions)
	_empty_add = Kit.text_button("Add rig", "plus", true)
	_empty_add.name = "AddRigButton"
	_empty_add.custom_minimum_size = Vector2(96, ROW_HEIGHT)
	_empty_add.pressed.connect(_on_add_rig)
	empty_actions.add_child(_empty_add)
	_empty_import = Kit.text_button("Import model", "upload", false)
	_empty_import.name = "ImportModelButton"
	_empty_import.custom_minimum_size = Vector2(96, ROW_HEIGHT)
	_empty_import.pressed.connect(func() -> void: import_model_requested.emit())
	empty_actions.add_child(_empty_import)

	_sections = VBoxContainer.new()
	_sections.add_theme_constant_override("separation", 10)
	_content.add_child(_sections)

	var rig_row := HBoxContainer.new()
	rig_row.add_theme_constant_override("separation", 4)
	_sections.add_child(rig_row)
	_rig_picker = OptionButton.new()
	_rig_picker.name = "RigPicker"
	_rig_picker.custom_minimum_size = Vector2(44, ROW_HEIGHT)
	_rig_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rig_picker.item_selected.connect(_on_rig_picked)
	rig_row.add_child(_rig_picker)

	_tree = BoneTreeScript.new()
	_tree.name = "BoneTree"
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.bone_selected.connect(_on_bone_selected)
	_tree.changed.connect(_on_tree_changed)
	_sections.add_child(_tree)

	_build_inspector()
	_build_bind()
	_build_keys()
	_pose_panel = PosePanelScript.new()
	_pose_panel.name = "PosePanel"
	_pose_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pose_panel.changed.connect(_on_pose_changed)
	_sections.add_child(_pose_panel)
	_ik_panel = IkPanelScript.new()
	_ik_panel.name = "IKPanel"
	_ik_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ik_panel.changed.connect(_on_ik_changed)
	_sections.add_child(_ik_panel)


func _build_inspector() -> void:
	_inspector = VBoxContainer.new()
	_inspector.name = "BoneInspector"
	_inspector.add_theme_constant_override("separation", 4)
	_sections.add_child(_inspector)
	var head := HBoxContainer.new()
	_inspector.add_child(head)
	_inspector_title = Kit.section_label("Bone")
	_inspector_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_inspector_title)
	_reset_button = Kit.text_button("Reset pose", "rotate-ccw", false, true)
	_reset_button.name = "ResetPoseButton"
	_reset_button.custom_minimum_size = Vector2(96, ROW_HEIGHT)
	_reset_button.pressed.connect(_on_reset_pose)
	head.add_child(_reset_button)
	_reset_all_button = Kit.icon_button("rotate-ccw", "Reset all bone poses", 44, 18)
	_reset_all_button.name = "ResetAllPoseButton"
	_reset_all_button.pressed.connect(_on_reset_all_poses)
	head.add_child(_reset_all_button)

	_imported_note = Kit.label("Imported skeleton: rest editing is locked. Pose and IK still work.", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	_imported_note.name = "ImportedRigNote"
	_imported_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_imported_note.visible = false
	_inspector.add_child(_imported_note)

	_rest_section = VBoxContainer.new()
	_rest_section.name = "RestSection"
	_rest_section.add_theme_constant_override("separation", 4)
	_inspector.add_child(_rest_section)
	var rest_label := Kit.section_label("Rest")
	rest_label.name = "RestSectionLabel"
	_rest_section.add_child(rest_label)
	var position_row := HBoxContainer.new()
	position_row.add_theme_constant_override("separation", 2)
	_rest_section.add_child(position_row)
	_px = _num("X", "RestPX", position_row)
	_py = _num("Y", "RestPY", position_row)
	_pz = _num("Z", "RestPZ", position_row)
	var rotation_row := HBoxContainer.new()
	rotation_row.add_theme_constant_override("separation", 2)
	_rest_section.add_child(rotation_row)
	_rx = _num("X°", "RestRX", rotation_row)
	_ry = _num("Y°", "RestRY", rotation_row)
	_rz = _num("Z°", "RestRZ", rotation_row)
	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 2)
	_rest_section.add_child(scale_row)
	_sx = _num("X", "RestSX", scale_row)
	_sy = _num("Y", "RestSY", scale_row)
	_sz = _num("Z", "RestSZ", scale_row)

	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 4)
	_rest_section.add_child(metrics)
	_length_field = _num("Len", "BoneLengthField", metrics, 0.0001, 100.0, 0.01)
	_influence_field = _num("Inf", "BoneInfluenceField", metrics, 0.0, 1000.0, 0.05)
	_length_field.value_changed.connect(func(_value: float) -> void: _apply_rest())
	_influence_field.value_changed.connect(func(value: float) -> void: _apply_influence(value))
	for field in [_px, _py, _pz, _rx, _ry, _rz, _sx, _sy, _sz]:
		field.value_changed.connect(func(_value: float) -> void: _apply_rest())

	_pose_section = VBoxContainer.new()
	_pose_section.name = "PoseSection"
	_pose_section.add_theme_constant_override("separation", 4)
	_inspector.add_child(_pose_section)
	var pose_label := Kit.section_label("Pose")
	pose_label.name = "PoseSectionLabel"
	_pose_section.add_child(pose_label)
	var pose_position_row := HBoxContainer.new()
	pose_position_row.add_theme_constant_override("separation", 2)
	_pose_section.add_child(pose_position_row)
	_pose_px = _num("X", "PosePX", pose_position_row)
	_pose_py = _num("Y", "PosePY", pose_position_row)
	_pose_pz = _num("Z", "PosePZ", pose_position_row)
	var pose_rotation_row := HBoxContainer.new()
	pose_rotation_row.add_theme_constant_override("separation", 2)
	_pose_section.add_child(pose_rotation_row)
	_pose_rx = _num("X°", "PoseRX", pose_rotation_row)
	_pose_ry = _num("Y°", "PoseRY", pose_rotation_row)
	_pose_rz = _num("Z°", "PoseRZ", pose_rotation_row)
	var pose_scale_row := HBoxContainer.new()
	pose_scale_row.add_theme_constant_override("separation", 2)
	_pose_section.add_child(pose_scale_row)
	_pose_sx = _num("X", "PoseSX", pose_scale_row)
	_pose_sy = _num("Y", "PoseSY", pose_scale_row)
	_pose_sz = _num("Z", "PoseSZ", pose_scale_row)
	_pose_px.value_changed.connect(func(_value: float) -> void: _apply_pose_position())
	_pose_py.value_changed.connect(func(_value: float) -> void: _apply_pose_position())
	_pose_pz.value_changed.connect(func(_value: float) -> void: _apply_pose_position())
	_pose_rx.value_changed.connect(func(_value: float) -> void: _apply_pose_rotation())
	_pose_ry.value_changed.connect(func(_value: float) -> void: _apply_pose_rotation())
	_pose_rz.value_changed.connect(func(_value: float) -> void: _apply_pose_rotation())
	_pose_sx.value_changed.connect(func(_value: float) -> void: _apply_pose_scale())
	_pose_sy.value_changed.connect(func(_value: float) -> void: _apply_pose_scale())
	_pose_sz.value_changed.connect(func(_value: float) -> void: _apply_pose_scale())


func _num(axis: String, node_name: String, parent: HBoxContainer, minimum: float = -1000.0, maximum: float = 1000.0, step: float = 0.01) -> PanelContainer:
	var field = NumberFieldScript.new()
	field.name = node_name
	field.axis = axis
	field.min_value = minimum
	field.max_value = maximum
	field.step = step
	field.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	parent.add_child(field)
	return field


func _build_bind() -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)
	_sections.add_child(section)
	var title := Kit.section_label("Skin")
	section.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	section.add_child(row)
	_bind_picker = OptionButton.new()
	_bind_picker.name = "BindMeshPicker"
	_bind_picker.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	_bind_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bind_picker.item_selected.connect(_on_bind_picked)
	row.add_child(_bind_picker)
	_bind_button = Kit.text_button("Bind", "link", true)
	_bind_button.name = "BindButton"
	_bind_button.custom_minimum_size = Vector2(96, ROW_HEIGHT)
	_bind_button.pressed.connect(func() -> void: bind_selected_mesh())
	row.add_child(_bind_button)
	_rebind_button = Kit.text_button("Rebind", "", false, true)
	_rebind_button.name = "RebindButton"
	_rebind_button.custom_minimum_size = Vector2(44, ROW_HEIGHT)
	_rebind_button.pressed.connect(func() -> void: bind_selected_mesh())
	row.add_child(_rebind_button)
	_unbind_button = Kit.text_button("Unbind", "", false, true)
	_unbind_button.name = "UnbindButton"
	_unbind_button.custom_minimum_size = Vector2(44, ROW_HEIGHT)
	_unbind_button.pressed.connect(_on_unbind)
	row.add_child(_unbind_button)

	_bind_progress = ProgressBar.new()
	_bind_progress.name = "BindProgress"
	_bind_progress.min_value = 0
	_bind_progress.max_value = 100
	_bind_progress.value = 0
	_bind_progress.show_percentage = false
	_bind_progress.custom_minimum_size = Vector2(0, 6)
	section.add_child(_bind_progress)
	_bind_summary = Kit.mono_label("Not bound.", Kit.TYPE_CAPTION, Kit.TEXT_MUTED)
	_bind_summary.name = "BindSummary"
	_bind_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(_bind_summary)
	_rebind_note = Kit.label("Change influence scale, then Rebind to apply.", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	_rebind_note.name = "RebindNote"
	_rebind_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(_rebind_note)


func _build_keys() -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)
	_sections.add_child(section)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	section.add_child(head)
	var title := Kit.section_label("Bone keys")
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	_key_bone_label = Kit.mono_label("", Kit.TYPE_CAPTION, Kit.TEXT_MUTED)
	_key_bone_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_key_bone_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_key_bone_label)
	_key_count_label = Kit.mono_label("", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	_key_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_key_count_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	section.add_child(row)
	_key_prev = Kit.icon_button("chevron-left", "Previous bone key", 44, 18)
	_key_prev.name = "PrevBoneKey"
	_key_prev.pressed.connect(func() -> void: _step_key(-1))
	row.add_child(_key_prev)
	_key_next = Kit.icon_button("chevron-right", "Next bone key", 44, 18)
	_key_next.name = "NextBoneKey"
	_key_next.pressed.connect(func() -> void: _step_key(1))
	row.add_child(_key_next)
	_key_delete = Kit.icon_button("trash-2", "Delete the selected bone key", 44, 18)
	_key_delete.name = "DeleteBoneKey"
	_key_delete.pressed.connect(_on_delete_key)
	row.add_child(_key_delete)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_key_bone = Kit.text_button("Key bone", "diamond-plus", false, true)
	_key_bone.name = "KeyBoneButton"
	_key_bone.custom_minimum_size = Vector2(96, ROW_HEIGHT)
	_key_bone.pressed.connect(_on_key_bone)
	row.add_child(_key_bone)
	_key_pose = Kit.text_button("Key pose", "diamond-plus", false, true)
	_key_pose.name = "KeyPoseButton"
	_key_pose.custom_minimum_size = Vector2(96, ROW_HEIGHT)
	_key_pose.pressed.connect(_on_key_pose)
	row.add_child(_key_pose)
	var caption := Kit.label("Rotation, position and scale", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	caption.name = "KeyChannelsCaption"
	section.add_child(caption)


func refresh() -> void:
	if _sections == null or _refreshing:
		return
	_refreshing = true
	var rig_ids: PackedStringArray = rig_system.rig_ids() if rig_system != null else PackedStringArray()
	_empty_box.visible = rig_ids.is_empty()
	_sections.visible = not rig_ids.is_empty()
	if not rig_ids.is_empty():
		var active: String = rig_system.active_rig_id()
		if active == "" or not rig_ids.has(active):
			active = rig_ids[0]
			rig_system.set_active_rig(active)
		_fill_rig_picker(rig_ids, active)
		_tree.set_rig(active)
		_pose_panel.set_rig(active)
		_ik_panel.set_rig(active)
		_refresh_inspector()
		_refresh_bind()
		_refresh_keys()
	_refreshing = false


func _fill_rig_picker(rig_ids: PackedStringArray, active: String) -> void:
	_rig_picker.clear()
	for rig_id in rig_ids:
		var rig: Dictionary = rig_system.get_rig(rig_id)
		_rig_picker.add_item(str(rig.get("name", "Rig")))
		_rig_picker.set_item_metadata(_rig_picker.item_count - 1, rig_id)
		if rig_id == active:
			_rig_picker.select(_rig_picker.item_count - 1)


func _active_rig() -> Dictionary:
	if rig_system == null:
		return {}
	return rig_system.get_rig(rig_system.active_rig_id())


func _refresh_inspector() -> void:
	var rig := _active_rig()
	if rig.is_empty():
		return
	var bone_name := str(rig.get("active_bone", ""))
	var index := -1
	var bones: Array = rig.get("bones", [])
	for i in range(bones.size()):
		if str(bones[i].get("name", "")) == bone_name:
			index = i
			break
	if index < 0:
		return
	var bone: Dictionary = bones[index]
	_inspector_title.text = "Bone · %s" % bone_name
	var imported := bool(rig.get("imported", false))
	_imported_note.visible = imported
	_updating = true
	_px.set_value_silent((bone.get("p", Vector3.ZERO) as Vector3).x)
	_py.set_value_silent((bone.get("p", Vector3.ZERO) as Vector3).y)
	_pz.set_value_silent((bone.get("p", Vector3.ZERO) as Vector3).z)
	var euler: Vector3 = (bone.get("r", Quaternion.IDENTITY) as Quaternion).get_euler()
	_rx.set_value_silent(rad_to_deg(euler.x))
	_ry.set_value_silent(rad_to_deg(euler.y))
	_rz.set_value_silent(rad_to_deg(euler.z))
	_sx.set_value_silent((bone.get("s", Vector3.ONE) as Vector3).x)
	_sy.set_value_silent((bone.get("s", Vector3.ONE) as Vector3).y)
	_sz.set_value_silent((bone.get("s", Vector3.ONE) as Vector3).z)
	_length_field.set_value_silent(float(bone.get("length", 0.4)))
	_influence_field.set_value_silent(float(bone.get("influence_scale", 1.0)))
	for field in [_px, _py, _pz, _rx, _ry, _rz, _sx, _sy, _sz, _length_field, _influence_field]:
		_set_field_editable(field, not imported)
	var node: Node3D = doc.nodes.get(str(rig.get("object_id", ""))) if doc != null else null
	var skeleton := node.get_node_or_null("Skeleton3D") as Skeleton3D if node != null else null
	_refresh_pose_fields(skeleton, bone_name)
	_updating = false

func _refresh_pose_fields(skeleton: Skeleton3D, bone_name: String) -> void:
	if _pose_px == null:
		return
	var position := Vector3.ZERO
	var rotation := Quaternion.IDENTITY
	var scale := Vector3.ONE
	if skeleton != null:
		var index := skeleton.find_bone(bone_name)
		if index >= 0:
			position = skeleton.get_bone_pose_position(index)
			rotation = skeleton.get_bone_pose_rotation(index)
			scale = skeleton.get_bone_pose_scale(index)
	var euler := rotation.get_euler()
	_pose_px.set_value_silent(position.x)
	_pose_py.set_value_silent(position.y)
	_pose_pz.set_value_silent(position.z)
	_pose_rx.set_value_silent(rad_to_deg(euler.x))
	_pose_ry.set_value_silent(rad_to_deg(euler.y))
	_pose_rz.set_value_silent(rad_to_deg(euler.z))
	_pose_sx.set_value_silent(scale.x)
	_pose_sy.set_value_silent(scale.y)
	_pose_sz.set_value_silent(scale.z)
	for field in [_pose_px, _pose_py, _pose_pz, _pose_rx, _pose_ry, _pose_rz, _pose_sx, _pose_sy, _pose_sz]:
		_set_field_editable(field, true)


func _apply_pose_patch(patch: Dictionary) -> void:
	if _updating or rig_system == null:
		return
	var rig := _active_rig()
	if rig.is_empty():
		return
	var bone_name := str(rig.get("active_bone", ""))
	if bone_name == "":
		return
	_updating = true
	rig_system.begin_pose_edit("Pose bone")
	rig_system.set_bone_pose(str(rig.get("object_id", "")), bone_name, patch)
	rig_system.end_pose_edit()
	var node: Node3D = doc.nodes.get(str(rig.get("object_id", ""))) if doc != null else null
	var skeleton := node.get_node_or_null("Skeleton3D") as Skeleton3D if node != null else null
	_refresh_pose_fields(skeleton, bone_name)
	_updating = false


func _apply_pose_position() -> void:
	_apply_pose_patch({"p": Vector3(_pose_px.value, _pose_py.value, _pose_pz.value)})


func _apply_pose_rotation() -> void:
	_apply_pose_patch({"r": Quaternion.from_euler(Vector3(
		deg_to_rad(_pose_rx.value), deg_to_rad(_pose_ry.value), deg_to_rad(_pose_rz.value)))})


func _apply_pose_scale() -> void:
	_apply_pose_patch({"s": Vector3(_pose_sx.value, _pose_sy.value, _pose_sz.value)})


func _set_field_editable(field: Control, value: bool) -> void:
	if field == null:
		return
	field.mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	field.modulate = Color.WHITE if value else Color(1, 1, 1, 0.45)
	if field.has_method("set_editable"):
		field.set_editable(value)


func _apply_rest() -> void:
	if _updating:
		return
	var rig := _active_rig()
	if rig.is_empty() or bool(rig.get("imported", false)):
		return
	var bone_name := str(rig.get("active_bone", ""))
	var rotation := Quaternion.from_euler(Vector3(
		deg_to_rad(_rx.value), deg_to_rad(_ry.value), deg_to_rad(_rz.value)))
	rig_system.set_bone_rest(rig.get("object_id", ""), bone_name, {
		"p": Vector3(_px.value, _py.value, _pz.value),
		"r": rotation,
		"s": Vector3(_sx.value, _sy.value, _sz.value),
		"length": _length_field.value,
	})
	_refresh_inspector()


func _apply_influence(value: float) -> void:
	if _updating:
		return
	var rig := _active_rig()
	if rig.is_empty():
		return
	rig_system.set_bone_influence_scale(str(rig.get("object_id", "")), str(rig.get("active_bone", "")), value)
	_refresh_bind()


func _refresh_bind() -> void:
	var rig := _active_rig()
	if rig.is_empty() or doc == null:
		return
	var previous := _selected_mesh
	_bind_picker.clear()
	_selected_mesh = ""
	for obj in doc.objects:
		var kind := str(obj.get("kind", ""))
		if kind != "mesh" and kind != "import":
			continue
		_bind_picker.add_item(str(obj.get("name", "Mesh")))
		_bind_picker.set_item_metadata(_bind_picker.item_count - 1, str(obj.get("id", "")))
		if str(obj.get("id", "")) == previous:
			_bind_picker.select(_bind_picker.item_count - 1)
			_selected_mesh = previous
	if _bind_picker.item_count > 0 and _selected_mesh == "":
		_bind_picker.select(0)
		_selected_mesh = str(_bind_picker.get_item_metadata(0))
	_refresh_bind_summary()


func _refresh_bind_summary() -> void:
	var rig := _active_rig()
	if rig.is_empty():
		return
	var found: Dictionary = {}
	for skin in rig.get("skins", []):
		if str(skin.get("mesh_object_id", "")) == _selected_mesh:
			found = skin
			break
	if found.is_empty():
		_bind_summary.text = "Not bound."
		_unbind_button.disabled = true
		return
	_bind_summary.text = "Bound %s vertices · %d influences · %d bones" % [
		_thousands(int(found.get("vertex_count", 0))),
		int(found.get("influences", 4)),
		(found.get("bone_names", []) as Array).size(),
	]
	_unbind_button.disabled = false


func _thousands(value: int) -> String:
	var text := str(value)
	var out := ""
	var count := 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


func bind_selected_mesh() -> String:
	var rig := _active_rig()
	if rig.is_empty() or _selected_mesh == "":
		return ""
	_active_job = rig_system.start_bind(str(rig.get("object_id", "")), _selected_mesh, {})
	_bind_progress.value = 0
	_bind_summary.text = "Binding…"
	return _active_job


func poll_bind_once() -> void:
	if _active_job == "":
		return
	var result: Dictionary = rig_system.poll_bind(_active_job)
	_bind_progress.value = float(result.get("progress", 0.0)) * 100.0
	var state := str(result.get("state", ""))
	if state == "done":
		_active_job = ""
		_refresh_bind_summary()
	elif state == "error":
		_active_job = ""
		_bind_summary.text = str(result.get("error", "Bind failed."))
	elif state == "cancelled":
		_active_job = ""
		_bind_summary.text = str(result.get("error", "Bind cancelled."))


func _process(_delta: float) -> void:
	if _active_job != "" and is_visible_in_tree():
		poll_bind_once()


func _refresh_keys() -> void:
	var rig := _active_rig()
	if rig.is_empty() or doc == null:
		return
	var bone := str(rig.get("active_bone", ""))
	var keys: Array = doc.get_bone_keys(str(rig.get("object_id", "")), bone)
	_key_bone_label.text = bone
	_key_count_label.text = "%d key%s" % [keys.size(), "" if keys.size() == 1 else "s"]
	_key_index = clampi(_key_index, 0, maxi(0, keys.size() - 1))
	_key_prev.disabled = keys.is_empty()
	_key_next.disabled = keys.is_empty()
	_key_delete.disabled = keys.is_empty()
	_key_bone.disabled = bone == ""
	_key_pose.disabled = bone == ""


func _step_key(direction: int) -> void:
	var rig := _active_rig()
	if rig.is_empty() or doc == null:
		return
	var bone := str(rig.get("active_bone", ""))
	var keys: Array = doc.get_bone_keys(str(rig.get("object_id", "")), bone)
	if keys.is_empty():
		return
	_key_index = clampi(_key_index + direction, 0, keys.size() - 1)
	doc.seek(float(keys[_key_index].get("time", 0.0)), true)


func _on_delete_key() -> void:
	var rig := _active_rig()
	if rig.is_empty() or doc == null:
		return
	var bone := str(rig.get("active_bone", ""))
	var keys: Array = doc.get_bone_keys(str(rig.get("object_id", "")), bone)
	if keys.is_empty():
		return
	doc.delete_bone_key(str(rig.get("object_id", "")), bone, clampi(_key_index, 0, keys.size() - 1))
	_refresh_keys()


func _on_key_bone() -> void:
	var rig := _active_rig()
	if rig.is_empty() or doc == null:
		return
	var bone := str(rig.get("active_bone", ""))
	var node: Node3D = doc.nodes.get(str(rig.get("object_id", "")))
	var skeleton := node.get_node_or_null("Skeleton3D") as Skeleton3D if node != null else null
	if skeleton == null:
		return
	var index := skeleton.find_bone(bone)
	if index < 0:
		return
	doc.insert_bone_key(str(rig.get("object_id", "")), bone, skeleton.get_bone_pose_rotation(index))
	_refresh_keys()


func _on_key_pose() -> void:
	var rig := _active_rig()
	if rig.is_empty():
		return
	rig_system.key_pose(str(rig.get("object_id", "")))
	_refresh_keys()


func _on_reset_pose() -> void:
	var rig := _active_rig()
	if rig.is_empty():
		return
	rig_system.reset_pose(str(rig.get("object_id", "")), str(rig.get("active_bone", "")))
	_refresh_inspector()


func _on_reset_all_poses() -> void:
	var rig := _active_rig()
	if rig.is_empty():
		return
	rig_system.reset_pose(str(rig.get("object_id", "")), "")
	_refresh_inspector()


func _on_add_rig() -> void:
	if rig_system == null:
		return
	rig_system.create_rig("Rig", Vector3.ZERO)
	refresh()


func _on_rig_picked(index: int) -> void:
	if _refreshing or rig_system == null:
		return
	var rig_id := str(_rig_picker.get_item_metadata(index))
	rig_system.set_active_rig(rig_id)
	refresh()


func _on_bind_picked(index: int) -> void:
	_selected_mesh = str(_bind_picker.get_item_metadata(index))
	_refresh_bind_summary()


func _on_unbind() -> void:
	var rig := _active_rig()
	if rig.is_empty() or _selected_mesh == "":
		return
	rig_system.unbind_mesh(str(rig.get("object_id", "")), _selected_mesh)
	_refresh_bind()


func _on_bone_selected(_bone: String) -> void:
	_refresh_inspector()
	_refresh_keys()


func _on_tree_changed() -> void:
	refresh()


func _on_pose_changed() -> void:
	_refresh_keys()


func _on_ik_changed() -> void:
	pass


func _on_rigs_changed() -> void:
	refresh()


func _on_visibility_changed() -> void:
	rig_mode_changed.emit(is_visible_in_tree())


func _on_rig_selection_changed(rig_id: String, _bone: String) -> void:
	if _refreshing:
		return
	if rig_system != null and rig_id != rig_system.active_rig_id():
		return
	_refresh_inspector()
	_refresh_keys()


func _on_scene_changed() -> void:
	refresh()


func _on_object_spawned(_id: String, _node: Node) -> void:
	refresh()
