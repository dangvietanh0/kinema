extends PanelContainer
## 48 dp action bar for compact screens.
##
## Four equal actions: Add, Scene, Properties, Timeline. Scene and Properties
## open the same drawer the dock uses on wider screens; Timeline folds the
## dope sheet away so the 3D view keeps the height.

signal action_requested(action: String)

const ACTION_ADD := "add"
const ACTION_SCENE := "scene"
const ACTION_PROPS := "props"
const ACTION_TIMELINE := "timeline"

var _buttons: Dictionary = {}
var _active: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_build()


func _build() -> void:
	custom_minimum_size.y = 48
	var style := Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT, 0)
	style.border_width_top = 1
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)

	_add_action(row, ACTION_ADD, "Add", "plus", true)
	_add_action(row, ACTION_SCENE, "Scene", "layers", false)
	_add_action(row, ACTION_PROPS, "Props", "sliders-horizontal", false)
	_add_action(row, ACTION_TIMELINE, "Timeline", "panel-bottom", false)


func _add_action(parent: Control, action: String, label: String, icon_name: String, focus: bool) -> void:
	var button := Kit.text_button(label, icon_name, false, true)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(44, 44)
	button.add_theme_font_size_override("font_size", 11)
	if focus:
		button.add_theme_color_override("font_color", Kit.TEXT)
		button.add_theme_color_override("icon_normal_color", Kit.TEXT)
	button.pressed.connect(func() -> void: action_requested.emit(action))
	parent.add_child(button)
	_buttons[action] = button


func set_mode(mode: String) -> void:
	visible = mode == "compact"


func set_timeline_open(open: bool) -> void:
	var button: Button = _buttons.get(ACTION_TIMELINE)
	if button == null:
		return
	button.tooltip_text = "Hide timeline" if open else "Show timeline"
	set_active(ACTION_TIMELINE, open)


func set_active(action: String, active: bool) -> void:
	var button: Button = _buttons.get(action)
	if button == null:
		return
	_active[action] = active
	Kit.set_icon_active(button, active)
	if active:
		button.add_theme_color_override("font_color", Kit.TEXT)
	else:
		button.add_theme_color_override("font_color", Kit.TEXT_MUTED)


func is_active(action: String) -> bool:
	return bool(_active.get(action, false))
