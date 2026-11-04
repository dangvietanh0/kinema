extends PanelContainer
## Floating Pose/Edit toolbar for the rig workbench.
##
## The toolbar lives in the stage, above the rig overlay, so it survives
## closing the Rig dock or showing another dock page. It never owns the rig:
## it reports intent through signals and mirrors the mode the overlay owns.

signal mode_changed(mode: String)
signal transform_mode_changed(mode: String)
signal axis_mode_changed(axis: String)
signal add_bone_requested
signal done_requested

const HIT := 44.0
const ACTION_WIDTH := 96.0
const IMPORTED_REASON := "Imported skeleton: rest editing is locked. Pose and IK still work."

var _mode := "pose"
var _transform := "rotate"
var _axis := "free"
var _imported := false
var _pose_button: Button
var _edit_button: Button
var _add_button: Button
var _done_button: Button
var _transform_buttons: Dictionary = {}
var _axis_buttons: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_sync()


func current_mode() -> String:
	return _mode


func transform_mode() -> String:
	return _transform


func axis_mode() -> String:
	return _axis


func set_transform_mode(mode: String) -> void:
	var clean := mode if mode in ["rotate", "move"] else "rotate"
	if _transform == clean:
		_sync()
		return
	_transform = clean
	_sync()
	transform_mode_changed.emit(_transform)


func set_axis_mode(axis: String) -> void:
	var clean := axis if axis in ["free", "x", "y", "z"] else "free"
	if _axis == clean:
		_sync()
		return
	_axis = clean
	_sync()
	axis_mode_changed.emit(_axis)


func set_mode(mode: String) -> void:
	var clean := mode if mode in ["pose", "edit"] else "pose"
	if clean == "edit" and _imported:
		clean = "pose"
	_mode = clean
	_sync()


func set_imported(value: bool) -> void:
	_imported = value
	if _imported and _mode == "edit":
		_mode = "pose"
	_sync()


func _build() -> void:
	if _done_button != null:
		return
	var style := Kit.flat_style(Kit.SURFACE_2, Kit.R_FLOAT, Kit.BORDER)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.name = "RigToolbarRow"
	row.add_theme_constant_override("separation", 4)
	add_child(row)

	var segments := HBoxContainer.new()
	segments.name = "RigModeSegments"
	segments.add_theme_constant_override("separation", 0)
	row.add_child(segments)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	_pose_button = Kit.text_toggle("Pose", "", false)
	_pose_button.name = "PoseModeButton"
	_pose_button.tooltip_text = "Pose: drag a bone to rotate it"
	_pose_button.custom_minimum_size = Vector2(HIT, HIT)
	_pose_button.button_group = group
	_pose_button.pressed.connect(func() -> void: _choose_mode("pose"))
	segments.add_child(_pose_button)
	_edit_button = Kit.text_toggle("Edit", "", false)
	_edit_button.name = "EditModeButton"
	_edit_button.tooltip_text = "Edit: drag the head or tail handle to change the rest"
	_edit_button.custom_minimum_size = Vector2(HIT, HIT)
	_edit_button.button_group = group
	_edit_button.pressed.connect(func() -> void: _choose_mode("edit"))
	segments.add_child(_edit_button)

	var transform_group := ButtonGroup.new()
	transform_group.allow_unpress = false
	var transform_segments := HBoxContainer.new()
	transform_segments.name = "RigTransformSegments"
	transform_segments.add_theme_constant_override("separation", 0)
	row.add_child(transform_segments)
	for spec in [["rotate", "Rotate", "TransformRotateButton"], ["move", "Move", "TransformMoveButton"]]:
		var button := Kit.text_toggle(str(spec[1]), "", false)
		button.name = str(spec[2])
		button.tooltip_text = "Rotate the active bone" if str(spec[0]) == "rotate" else "Move the active bone"
		button.custom_minimum_size = Vector2(HIT, HIT)
		button.button_group = transform_group
		button.pressed.connect(func() -> void: set_transform_mode(str(spec[0])))
		transform_segments.add_child(button)
		_transform_buttons[str(spec[0])] = button

	var axis_group := ButtonGroup.new()
	axis_group.allow_unpress = false
	var axis_segments := HBoxContainer.new()
	axis_segments.name = "RigAxisSegments"
	axis_segments.add_theme_constant_override("separation", 0)
	row.add_child(axis_segments)
	for spec in [["free", "Free", "AxisFreeButton"], ["x", "X", "AxisXButton"], ["y", "Y", "AxisYButton"], ["z", "Z", "AxisZButton"]]:
		var button := Kit.text_toggle(str(spec[1]), "", false)
		button.name = str(spec[2])
		button.tooltip_text = "Move or rotate on the free camera plane" if str(spec[0]) == "free" else "Lock to the %s axis" % str(spec[1])
		button.custom_minimum_size = Vector2(HIT, HIT)
		button.button_group = axis_group
		button.pressed.connect(func() -> void: set_axis_mode(str(spec[0])))
		axis_segments.add_child(button)
		_axis_buttons[str(spec[0])] = button

	_add_button = Kit.text_button("Add bone", "plus", false, true)
	_add_button.name = "ToolbarAddBoneButton"
	_add_button.tooltip_text = "Add a child bone at the active tail, or a root bone"
	_add_button.custom_minimum_size = Vector2(ACTION_WIDTH, HIT)
	_add_button.pressed.connect(func() -> void: add_bone_requested.emit())
	row.add_child(_add_button)

	_done_button = Kit.text_button("Done", "check", true)
	_done_button.name = "RigDoneButton"
	_done_button.tooltip_text = "Exit rig mode"
	_done_button.custom_minimum_size = Vector2(ACTION_WIDTH, HIT)
	_done_button.pressed.connect(func() -> void: done_requested.emit())
	row.add_child(_done_button)


func _choose_mode(mode: String) -> void:
	if mode == "edit" and _imported:
		_sync()
		return
	if _mode == mode:
		_sync()
		return
	_mode = mode
	_sync()
	mode_changed.emit(mode)


func _sync() -> void:
	if _pose_button == null:
		return
	_pose_button.set_pressed_no_signal(_mode == "pose")
	_edit_button.set_pressed_no_signal(_mode == "edit")
	_edit_button.disabled = _imported
	_add_button.disabled = _imported
	_edit_button.tooltip_text = IMPORTED_REASON if _imported else "Edit: drag the head or tail handle to change the rest"
	_add_button.tooltip_text = IMPORTED_REASON if _imported else "Add a child bone at the active tail, or a root bone"
	for key in _transform_buttons.keys():
		var transform_button: Button = _transform_buttons[key]
		transform_button.set_pressed_no_signal(_transform == str(key))
		transform_button.disabled = _mode == "edit"
	for key in _axis_buttons.keys():
		var axis_button: Button = _axis_buttons[key]
		axis_button.set_pressed_no_signal(_axis == str(key))
		axis_button.disabled = _mode == "edit"
