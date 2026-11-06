extends Control
## One reusable panel host for Scene overlays and the Shading/Rig/Render
## workspace panels.
##
## The host never owns document state: the editor reparents the existing
## outliner, inspector or rig frame into `_content_host` and swaps them without
## rebuilding them. Reserved mode takes layout width through the editor's
## spacer; overlay mode floats over the stage with a scrim.

signal closed

enum Mode { HIDDEN, RESERVED, OVERLAY }

const HEADER_H := 44.0
const MIN_WIDTH := 280.0
const MAX_WIDTH := 360.0
const OVERLAY_MAX := 400.0

var _mode: Mode = Mode.HIDDEN
var _requested_width := 300.0
var _top_inset := 44.0
var _title := ""
var _badge := ""

var _scrim: ColorRect
var _panel: PanelContainer
var _header: HBoxContainer
var _title_label: Label
var _badge_label: Label
var _close: Button
var _content_host: VBoxContainer
var _content: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 12
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	resized.connect(_apply_geometry)


func _build() -> void:
	_scrim = ColorRect.new()
	_scrim.color = Kit.SCRIM
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.visible = false
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)

	_panel = PanelContainer.new()
	_panel.name = "WorkspacePanelSurface"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT, 0)
	style.border_width_left = 1
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	_panel.add_child(column)

	_header = HBoxContainer.new()
	_header.custom_minimum_size.y = HEADER_H
	_header.add_theme_constant_override("separation", 6)
	var head_margin := MarginContainer.new()
	head_margin.add_theme_constant_override("margin_left", 12)
	head_margin.add_theme_constant_override("margin_right", 4)
	head_margin.add_theme_constant_override("margin_top", 0)
	head_margin.add_theme_constant_override("margin_bottom", 0)
	head_margin.add_child(_header)
	column.add_child(head_margin)

	_title_label = Kit.label("", 13, Kit.TEXT, 600)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.clip_text = true
	_header.add_child(_title_label)

	_badge_label = Kit.label("", 11, Kit.TEXT_MUTED)
	_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_badge_label.clip_text = true
	_badge_label.visible = false
	_header.add_child(_badge_label)

	_close = Kit.icon_button("x", "Close the panel", 44, 20)
	_close.visible = false
	_close.pressed.connect(_on_close_pressed)
	_header.add_child(_close)

	_content_host = VBoxContainer.new()
	_content_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_host.add_theme_constant_override("separation", 0)
	column.add_child(_content_host)

	_apply_geometry()


## The panel starts at the top bar's bottom edge and never covers it.
func setup(title: String, top_bar_height := 44.0) -> void:
	_top_inset = maxf(top_bar_height, 0.0)
	set_title(title)
	_apply_geometry()


func set_top_bar_height(value: float) -> void:
	_top_inset = maxf(value, 0.0)
	_apply_geometry()


func set_mode(mode: int) -> void:
	_mode = mode as Mode
	match _mode:
		Mode.HIDDEN:
			_panel.visible = false
			_scrim.visible = false
		Mode.RESERVED:
			_panel.visible = true
			_scrim.visible = false
			_close.visible = false
		Mode.OVERLAY:
			_panel.visible = true
			_scrim.visible = true
			_close.visible = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_geometry()


## Store the requested width and clamp it for the current mode. Reserved panels
## stay between 280 and 360 dp; overlays never exceed 400 dp.
func set_panel_width(width: float) -> void:
	_requested_width = maxf(width, 0.0)
	_apply_geometry()


func set_title(value: String) -> void:
	_title = value
	if _title_label != null:
		_title_label.text = _title


func set_badge(value: String) -> void:
	_badge = value
	if _badge_label != null:
		_badge_label.text = _badge
		_badge_label.visible = _badge != ""


func set_content(control: Control) -> void:
	if _content_host == null:
		return
	if control == _content:
		control.visible = true
		return
	if _content != null and is_instance_valid(_content) and _content.get_parent() == _content_host:
		_content_host.remove_child(_content)
	_content = control
	if control != null:
		if control.get_parent() != null and control.get_parent() != _content_host:
			control.get_parent().remove_child(control)
		if control.get_parent() != _content_host:
			_content_host.add_child(control)
		control.visible = true


func content() -> Control:
	return _content


func mode() -> int:
	return _mode


func panel_rect() -> Rect2:
	if _panel == null:
		return Rect2()
	return _panel.get_global_rect()


func close_button() -> Button:
	return _close


func scrim() -> ColorRect:
	return _scrim


func state_title() -> String:
	return _title


func state_badge() -> String:
	return _badge


func _panel_width() -> float:
	if _mode == Mode.RESERVED:
		return clampf(_requested_width, MIN_WIDTH, MAX_WIDTH)
	if _mode == Mode.OVERLAY:
		return minf(_requested_width, OVERLAY_MAX)
	return _requested_width


func _apply_geometry() -> void:
	if _panel == null:
		return
	var width := _panel_width()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -width
	_panel.offset_right = 0.0
	_panel.offset_top = _top_inset
	_panel.offset_bottom = 0.0
	_panel.custom_minimum_size.x = width


func _on_close_pressed() -> void:
	set_mode(Mode.HIDDEN)
	closed.emit()


func _on_scrim_input(event: InputEvent) -> void:
	if _mode != Mode.OVERLAY:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_on_close_pressed()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_on_close_pressed()
