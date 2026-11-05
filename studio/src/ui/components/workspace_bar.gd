extends PanelContainer
## The one top bar for every layout.
##
## Left: Back and the workspace chip. Right: Undo, Redo, Save and the project
## menu. The project title is not shown here; it lives in the chip tooltip and
## the workspace menu header. While looking through a camera the chip becomes
## `Camera: <name>` and an Exit control replaces the edit actions.
##
## The bar only reports intent. The editor owns every action.

signal action_requested(action: String)
signal workspace_requested
signal camera_exit_requested

const HEIGHT_TOUCH := 44
const HEIGHT_DESKTOP := 32

const ACTION_ICONS := {
	"back": "chevron-left",
	"undo": "undo-2",
	"redo": "redo-2",
	"save": "save",
	"menu": "menu",
	"camera_exit": "x",
}

var _layout_mode := "studio"
var _workspace := "scene"
var _project_title := "Untitled"
var _dirty := false
var _camera_mode := ""
var _available_width := -1.0

var _row: HBoxContainer
var _back_button: Button
var _chip_group: HBoxContainer
var _chip_button: Button
var _dirty_dot: ColorRect
var _undo_button: Button
var _redo_button: Button
var _save_button: Button
var _menu_button: Button
var _camera_exit_button: Button
var _action_buttons: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_build()
	_apply_mode()
	_apply_camera_mode()


func _build() -> void:
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 4)
	add_child(_row)

	_back_button = _make_action_button("back", "Back to projects")
	_row.add_child(_back_button)

	_chip_group = HBoxContainer.new()
	_chip_group.add_theme_constant_override("separation", 4)
	_chip_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_chip_group)

	_chip_button = Kit.text_button(_label_for(_workspace), "chevron-down", false, true)
	_chip_button.custom_minimum_size = Vector2(96, HEIGHT_TOUCH)
	_chip_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_chip_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_chip_button.pressed.connect(func() -> void: workspace_requested.emit())
	_chip_group.add_child(_chip_button)

	_dirty_dot = ColorRect.new()
	_dirty_dot.color = Color(0, 0, 0, 0)
	_dirty_dot.custom_minimum_size = Vector2(6, 6)
	_dirty_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dirty_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_group.add_child(_dirty_dot)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(spacer)

	_undo_button = _make_action_button("undo", "Undo")
	_redo_button = _make_action_button("redo", "Redo")
	_save_button = _make_action_button("save", "Save project")
	_menu_button = _make_action_button("menu", "Project menu")
	for button in [_undo_button, _redo_button, _save_button, _menu_button]:
		_row.add_child(button)

	_camera_exit_button = _make_action_button("camera_exit", "Exit camera view")
	_camera_exit_button.pressed.connect(func() -> void: camera_exit_requested.emit())
	_row.add_child(_camera_exit_button)


func _make_action_button(action_id: String, tooltip: String) -> Button:
	var button := Kit.icon_button(str(ACTION_ICONS.get(action_id, "")), tooltip)
	button.set_meta("action_id", action_id)
	button.set_meta("action_icon", str(ACTION_ICONS.get(action_id, "")))
	button.pressed.connect(func() -> void: action_requested.emit(action_id))
	_action_buttons[action_id] = button
	return button


func set_layout_mode(mode: String) -> void:
	_layout_mode = mode if mode in ["compact", "studio", "desktop"] else "studio"
	_apply_mode()


## Compatibility spelling for the pre-WorkspaceBar shell paths.
func set_mode(mode: String) -> void:
	set_layout_mode(mode)


func set_workspace(id: String) -> void:
	_workspace = id if id in ["scene", "shading", "rig", "animate", "render"] else "scene"
	if _camera_mode == "":
		_chip_button.text = _label_for(_workspace)


func set_project(title: String, dirty: bool) -> void:
	_project_title = title if title != "" else "Untitled"
	_dirty = dirty
	_dirty_dot.color = Kit.TEXT if _dirty and _camera_mode == "" else Color(0, 0, 0, 0)
	_chip_button.tooltip_text = "%s workspace" % _project_title


func set_history(can_undo: bool, can_redo: bool) -> void:
	_undo_button.disabled = not can_undo
	_redo_button.disabled = not can_redo


## An empty name restores the normal edit bar. A non-empty name is the
## look-through chip: no workspace icon, no edit actions, one Exit control.
func set_camera_mode(camera_name: String) -> void:
	_camera_mode = camera_name
	_apply_camera_mode()


func set_available_width(value: float) -> void:
	_available_width = value
	if _chip_button != null:
		# The chip is a name, not a title bar: 96 dp is enough for every
		# workspace label plus the chevron. It never grows into the actions.
		_chip_button.custom_minimum_size.x = 96.0


func workspace_chip() -> Button:
	return _chip_button


func action_button(action_id: String) -> Button:
	return _action_buttons.get(action_id, null)


func visible_action_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for action_id in _action_buttons.keys():
		var button: Button = _action_buttons[action_id]
		if button != null and button.visible:
			ids.append(str(action_id))
	return ids


func _label_for(id: String) -> String:
	match id:
		"scene":
			return "Scene"
		"shading":
			return "Shading"
		"rig":
			return "Rig"
		"animate":
			return "Animate"
		"render":
			return "Render"
	return "Scene"


func _apply_mode() -> void:
	var desktop := _layout_mode == "desktop"
	var height := float(HEIGHT_DESKTOP if desktop else HEIGHT_TOUCH)
	custom_minimum_size.y = height
	var style := Kit.flat_style(Kit.SURFACE_2, 0, Color(0, 0, 0, 0), 0)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	add_theme_stylebox_override("panel", style)
	var button_size := Vector2(28, 28) if desktop else Vector2(44, 44)
	for action_id in _action_buttons.keys():
		var button: Button = _action_buttons[action_id]
		if button == null:
			continue
		button.custom_minimum_size = button_size
		button.add_theme_constant_override("icon_max_width", 18 if desktop else 20)
		if desktop:
			Kit.exempt_from_hit_floor(button)
	_chip_button.custom_minimum_size.y = height
	_chip_button.add_theme_font_size_override("font_size", 11 if desktop else Kit.TYPE_BODY)
	_chip_button.add_theme_constant_override("icon_max_width", 14)
	if desktop:
		Kit.exempt_from_hit_floor(_chip_button)


func _apply_camera_mode() -> void:
	var active := _camera_mode != ""
	_dirty_dot.visible = not active
	_chip_button.text = ("Camera: " + _camera_mode) if active else _label_for(_workspace)
	_chip_button.icon = null if active else Kit.icon_texture("chevron-down")
	_chip_button.disabled = active
	_chip_button.tooltip_text = ("Looking through %s" % _camera_mode) if active else ("%s workspace" % _project_title)
	_undo_button.visible = not active
	_redo_button.visible = not active
	_save_button.visible = not active
	_menu_button.visible = not active
	_camera_exit_button.visible = active
