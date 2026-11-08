extends PanelContainer
## The one top bar for every layout.
##
## Left: Back, the three permanent workspace tabs, the More workspaces control
## and a spacer. Right: Undo, Redo, Save and the project menu. Undo and Redo
## leave the bar below 600 dp and stay reachable in the project menu. The
## project title is not shown here; the secondary-workspace menu carries it.
##
## While looking through a camera the tabs give way to `Camera: <name>` and an
## Exit control replaces the edit actions. The bar only reports intent; the
## editor owns every action and every workspace switch.

signal action_requested(action: String)
signal workspace_tab_requested(id: String)
signal more_workspaces_requested
signal camera_exit_requested

const HEIGHT_TOUCH := 44
const HEIGHT_DESKTOP := 32
const TAB_HEIGHT_TOUCH := 44
const TAB_HEIGHT_DESKTOP := 28
const TAB_MIN_WIDTH := 44.0
const TAB_FONT_SIZE := 11
const MORE_MIN_WIDTH := 60.0
const NARROW_BAR := 600.0
const PRIMARY_TABS := ["scene", "shading", "animate"]
const SECONDARY_WORKSPACES := ["rig", "render"]

const ACTION_ICONS := {
	"back": "chevron-left",
	"undo": "undo-2",
	"redo": "redo-2",
	"save": "save",
	"menu": "menu",
	"exit_camera": "x",
}

var _layout_mode := "studio"
var _workspace := "scene"
var _project_title := "Untitled"
var _dirty := false
var _camera_mode := ""
var _available_width := -1.0

var _row: HBoxContainer
var _back_button: Button
var _tabs_group: HBoxContainer
var _tabs: Dictionary = {}
var _more_button: Button
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

	_back_button = _make_action_button("back", "Back")
	_row.add_child(_back_button)

	_tabs_group = HBoxContainer.new()
	_tabs_group.add_theme_constant_override("separation", 0)
	_tabs_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_tabs_group)
	for id in PRIMARY_TABS:
		var tab := _make_tab(str(id))
		_tabs_group.add_child(tab)
		_tabs[id] = tab

	_more_button = Button.new()
	_more_button.focus_mode = Control.FOCUS_NONE
	_more_button.custom_minimum_size = Vector2(TAB_MIN_WIDTH, TAB_HEIGHT_TOUCH)
	_more_button.tooltip_text = "More workspaces"
	_more_button.add_theme_font_override("font", Kit.font_medium)
	_more_button.add_theme_font_size_override("font_size", TAB_FONT_SIZE)
	_more_button.add_theme_constant_override("h_separation", 4)
	_more_button.pressed.connect(func() -> void: more_workspaces_requested.emit())
	_row.add_child(_more_button)

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

	_dirty_dot = ColorRect.new()
	_dirty_dot.color = Kit.TEXT
	_dirty_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dirty_dot.visible = false
	_dirty_dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_dirty_dot.offset_left = -8
	_dirty_dot.offset_top = 3
	_dirty_dot.offset_right = -2
	_dirty_dot.offset_bottom = 9
	_save_button.add_child(_dirty_dot)

	_camera_exit_button = _make_action_button("exit_camera", "Exit camera view")
	_camera_exit_button.pressed.connect(func() -> void: camera_exit_requested.emit())
	_row.add_child(_camera_exit_button)

	_apply_workspace_state()


func _make_tab(id: String) -> Button:
	var tab := Button.new()
	tab.text = _label_for(id)
	tab.focus_mode = Control.FOCUS_NONE
	tab.custom_minimum_size = Vector2(TAB_MIN_WIDTH, TAB_HEIGHT_TOUCH)
	tab.add_theme_font_override("font", Kit.font_medium)
	tab.add_theme_font_size_override("font_size", TAB_FONT_SIZE)
	tab.set_meta("workspace_tab", id)
	tab.pressed.connect(func() -> void: workspace_tab_requested.emit(id))
	return tab


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
	_apply_workspace_state()


func set_project(title: String, dirty: bool) -> void:
	_project_title = title if title != "" else "Untitled"
	_dirty = dirty
	_apply_dirty_state()
	_tabs_group.tooltip_text = _project_title


func set_history(can_undo: bool, can_redo: bool) -> void:
	_undo_button.disabled = not can_undo
	_redo_button.disabled = not can_redo


## An empty name restores the normal edit bar. A non-empty name is the
## look-through chip: no tabs, no edit actions, one Exit control.
func set_camera_mode(camera_name: String) -> void:
	_camera_mode = camera_name
	_apply_camera_mode()


func set_available_width(value: float) -> void:
	_available_width = value
	_refresh_visibility()


## The named workspace surface. Retained as a compatibility alias for older
## callers that read the current name or the camera chip; new code uses
## `more_button()`.
func workspace_chip() -> Button:
	return _more_button


## One permanent primary-workspace tab, or null for a secondary workspace.
func workspace_tab(id: String) -> Button:
	return _tabs.get(id, null)


## The compact control that carries the current name and opens the two-row
## secondary-workspace menu.
func more_button() -> Button:
	return _more_button


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


func _apply_workspace_state() -> void:
	for id in _tabs.keys():
		_apply_tab_style(_tabs[id], str(id) == _workspace)
	if _camera_mode == "":
		_refresh_more()


func _refresh_more() -> void:
	var secondary := _workspace in SECONDARY_WORKSPACES
	if secondary:
		_more_button.text = _label_for(_workspace)
		_more_button.icon = Kit.icon_texture("chevron-down")
		_more_button.set_meta("action_icon", "chevron-down")
		_more_button.custom_minimum_size.x = MORE_MIN_WIDTH
		_more_button.add_theme_constant_override("icon_max_width", 12)
		_more_button.tooltip_text = "More workspaces"
		_apply_tab_style(_more_button, true)
	else:
		_more_button.text = ""
		_more_button.icon = Kit.icon_texture("ellipsis-horizontal")
		_more_button.set_meta("action_icon", "ellipsis-horizontal")
		_more_button.custom_minimum_size.x = _icon_side()
		_more_button.add_theme_constant_override("icon_max_width", 18)
		_more_button.tooltip_text = "More workspaces"
		_apply_tab_style(_more_button, false)


func _apply_tab_style(button: Button, active: bool) -> void:
	if active:
		button.add_theme_stylebox_override("normal", _tab_style(Kit.FOCUS))
		button.add_theme_stylebox_override("hover", _tab_style(Kit.FOCUS_BRIGHT))
		button.add_theme_stylebox_override("pressed", _tab_style(Kit.FOCUS.darkened(0.14)))
		button.add_theme_stylebox_override("hover_pressed",
			_tab_style(Kit.FOCUS.darkened(0.14)))
		button.add_theme_stylebox_override("focus",
			_tab_style(Color(0, 0, 0, 0), Kit.FOCUS_BRIGHT))
		for slot in ["font_color", "font_hover_color", "font_pressed_color",
				"font_hover_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(slot, Kit.BG)
		for slot in ["icon_normal_color", "icon_hover_color", "icon_pressed_color",
				"icon_hover_pressed_color"]:
			button.add_theme_color_override(slot, Kit.BG)
	else:
		button.add_theme_stylebox_override("normal", _tab_style(Color(0, 0, 0, 0)))
		button.add_theme_stylebox_override("hover", _tab_style(Kit.SURFACE_HOVER))
		button.add_theme_stylebox_override("pressed", _tab_style(Kit.SURFACE_ACTIVE))
		button.add_theme_stylebox_override("hover_pressed", _tab_style(Kit.SURFACE_ACTIVE))
		button.add_theme_stylebox_override("focus", _tab_style(Color(0, 0, 0, 0)))
		button.add_theme_color_override("font_color", Kit.TEXT)
		button.add_theme_color_override("font_hover_color", Kit.TEXT)
		button.add_theme_color_override("font_pressed_color", Kit.FOCUS_BRIGHT)
		button.add_theme_color_override("font_hover_pressed_color", Kit.FOCUS_BRIGHT)
		button.add_theme_color_override("font_focus_color", Kit.TEXT)
		button.add_theme_color_override("icon_normal_color", Kit.TEXT_MUTED)
		button.add_theme_color_override("icon_hover_color", Kit.TEXT)
		button.add_theme_color_override("icon_pressed_color", Kit.FOCUS_BRIGHT)
		button.add_theme_color_override("icon_hover_pressed_color", Kit.FOCUS_BRIGHT)


func _tab_style(fill: Color, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	return Kit.style_with_margins(fill, Kit.R_CONTROL, border, 0, Vector4(4, 0, 4, 0))


func _icon_side() -> float:
	return 28.0 if _layout_mode == "desktop" else 44.0


func _tab_height() -> float:
	return TAB_HEIGHT_DESKTOP if _layout_mode == "desktop" else TAB_HEIGHT_TOUCH


func _apply_mode() -> void:
	var desktop := _layout_mode == "desktop"
	var height := float(HEIGHT_DESKTOP if desktop else HEIGHT_TOUCH)
	custom_minimum_size.y = height
	var style := Kit.flat_style(Kit.SURFACE_2, 0, Color(0, 0, 0, 0), 0)
	style.content_margin_left = 2
	style.content_margin_right = 2
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	add_theme_stylebox_override("panel", style)
	var button_size := Vector2(28, 28) if desktop else Vector2(44, 44)
	for action_id in _action_buttons.keys():
		var button: Button = _action_buttons[action_id]
		if button == null:
			continue
		button.custom_minimum_size = button_size
		button.add_theme_constant_override("icon_max_width", 18)
		if desktop:
			Kit.exempt_from_hit_floor(button)
	var tab_height := _tab_height()
	for id in _tabs.keys():
		var tab: Button = _tabs[id]
		tab.custom_minimum_size = Vector2(TAB_MIN_WIDTH, tab_height)
		if desktop:
			Kit.exempt_from_hit_floor(tab)
	_more_button.custom_minimum_size.y = tab_height
	if desktop:
		Kit.exempt_from_hit_floor(_more_button)
	if _camera_mode == "":
		_refresh_more()
	else:
		_more_button.custom_minimum_size.y = tab_height
	_refresh_visibility()


func _apply_camera_mode() -> void:
	var active := _camera_mode != ""
	_tabs_group.visible = not active
	if active:
		_more_button.text = "Camera: " + _camera_mode
		_more_button.icon = null
		_more_button.set_meta("action_icon", "")
		_more_button.custom_minimum_size.x = 0.0
		_more_button.tooltip_text = "Looking through %s" % _camera_mode
		_more_button.disabled = true
		_apply_tab_style(_more_button, false)
	else:
		_more_button.disabled = false
		_refresh_more()
	_apply_dirty_state()
	_refresh_visibility()


func _apply_dirty_state() -> void:
	_dirty_dot.visible = _dirty and _camera_mode == ""


func _refresh_visibility() -> void:
	var camera := _camera_mode != ""
	var narrow := _available_width > 0.0 and _available_width < NARROW_BAR
	_undo_button.visible = not camera and not narrow
	_redo_button.visible = not camera and not narrow
	_save_button.visible = not camera
	_menu_button.visible = not camera
	_camera_exit_button.visible = camera
