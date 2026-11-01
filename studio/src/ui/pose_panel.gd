extends VBoxContainer
## Pose library grid. Two columns on Compact, three on Studio and wider.
##
## Chips carry the pose name and bone count. Apply, Key and Delete are separate
## 44 dp targets; no thumbnails are stored in this pass.

signal pose_applied(pose_id: String)
signal pose_keyed(pose_id: String)
signal pose_deleted(pose_id: String)
signal changed

const CHIP_HEIGHT := 44.0

var doc = null
var rig_system = null
var _rig_id := ""
var _grid: GridContainer
var _empty: Label
var _search: LineEdit
var _name_field: LineEdit
var _message: Label
var _chips: Array[PanelContainer] = []
var _poses: Array = []
var _filter := ""


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	_build()
	resized.connect(_apply_columns)


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


func get_pose_chips() -> Array:
	return _chips


func columns_for_width(width: float) -> int:
	return 2 if width < 600.0 else 3


func _build() -> void:
	if _grid != null:
		return
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	add_child(header)
	var title := Kit.section_label("Poses")
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 4)
	add_child(save_row)
	_name_field = Kit.line_edit("Pose name")
	_name_field.name = "PoseNameField"
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_name_field)
	var save := Kit.text_button("Save pose", "save", true)
	save.name = "SavePoseButton"
	save.custom_minimum_size = Vector2(96, CHIP_HEIGHT)
	save.pressed.connect(_on_save)
	save_row.add_child(save)

	_search = Kit.line_edit("Search poses")
	_search.name = "PoseSearch"
	_search.visible = false
	_search.text_changed.connect(func(text: String) -> void:
		_filter = text.strip_edges().to_lower()
		_rebuild_chips())
	add_child(_search)

	_empty = Kit.label("No poses yet. Pose the rig, then Save pose.", Kit.TYPE_CAPTION, Kit.TEXT_MUTED)
	_empty.name = "PoseEmpty"
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_empty)

	_message = Kit.label("", Kit.TYPE_CAPTION, Kit.WARNING)
	_message.name = "PoseMessage"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_message)

	_grid = GridContainer.new()
	_grid.name = "PoseGrid"
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	_grid.columns = columns_for_width(size.x)
	add_child(_grid)


func _apply_columns() -> void:
	if _grid != null:
		_grid.columns = columns_for_width(size.x)


func refresh() -> void:
	if _grid == null:
		return
	_message.text = ""
	_poses.clear()
	if rig_system != null and _rig_id != "":
		var rig: Dictionary = rig_system.get_rig(_rig_id)
		_poses = (rig.get("poses", []) as Array).duplicate(true)
	_search.visible = _poses.size() > 12
	_empty.visible = _poses.is_empty()
	_rebuild_chips()


func _rebuild_chips() -> void:
	if _grid == null:
		return
	_chips.clear()
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for pose in _poses:
		var pose_name := str(pose.get("name", "Pose"))
		if _filter != "" and not pose_name.to_lower().contains(_filter):
			continue
		_grid.add_child(_make_chip(pose))
	_empty.visible = _poses.is_empty()


func _make_chip(pose: Dictionary) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = "PoseChip"
	chip.custom_minimum_size.y = CHIP_HEIGHT
	chip.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_2, 0, Kit.CONTROL_BORDER, 1))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	chip.add_child(body)
	var pose_id := str(pose.get("id", ""))
	var apply := Kit.text_button(str(pose.get("name", "Pose")), "", false, false)
	apply.name = "ApplyPose"
	apply.custom_minimum_size = Vector2(0, CHIP_HEIGHT)
	apply.alignment = HORIZONTAL_ALIGNMENT_LEFT
	apply.pressed.connect(func() -> void:
		if rig_system != null and _rig_id != "":
			rig_system.apply_pose(_rig_id, pose_id)
			pose_applied.emit(pose_id))
	body.add_child(apply)
	var count := Kit.mono_label("%d bones" % int((pose.get("bones", {}) as Dictionary).size()), Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	count.name = "PoseBoneCount"
	body.add_child(count)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 2)
	body.add_child(actions)
	var key := Kit.icon_button("diamond-plus", "Key this pose", 44, 18)
	key.name = "KeyPose"
	key.pressed.connect(func() -> void:
		if rig_system != null and _rig_id != "":
			rig_system.apply_pose(_rig_id, pose_id)
			if rig_system.key_pose(_rig_id):
				pose_keyed.emit(pose_id))
	actions.add_child(key)
	var duplicate := Kit.icon_button("copy", "Duplicate pose", 44, 18)
	duplicate.name = "DuplicatePose"
	duplicate.pressed.connect(func() -> void:
		if rig_system != null and _rig_id != "" and rig_system.has_method("duplicate_pose"):
			rig_system.duplicate_pose(_rig_id, pose_id)
			changed.emit()
			refresh())
	actions.add_child(duplicate)
	var remove := Kit.icon_button("trash-2", "Delete pose", 44, 18)
	remove.name = "DeletePose"
	remove.pressed.connect(func() -> void:
		if rig_system != null and _rig_id != "":
			rig_system.delete_pose(_rig_id, pose_id)
			pose_deleted.emit(pose_id)
			changed.emit()
			refresh())
	actions.add_child(remove)
	_chips.append(chip)
	return chip


func _on_save() -> void:
	if rig_system == null or _rig_id == "":
		return
	var pose_id: String = rig_system.save_pose(_rig_id, _name_field.text)
	if pose_id == "":
		_message.text = "Pose name is required."
		return
	_name_field.text = ""
	changed.emit()
	refresh()
