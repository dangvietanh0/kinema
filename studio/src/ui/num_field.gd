extends HBoxContainer
## Compact numeric field with a draggable axis badge.
##
## Tapping the text opens the soft keyboard for precise entry; dragging the
## coloured badge scrubs the value, which is the fastest way to work on a
## touch screen. Both paths report history boundaries through `drag_started`,
## `drag_ended` and `text_committed`.

signal value_changed(value: float)
signal text_committed(value: float)
signal drag_started
signal drag_ended

const DECIMALS := 3

var value := 0.0
var min_value := -INF
var max_value := INF
var step := 0.01
var axis := "X"
var axis_color := Color(1, 1, 1)
var suffix := ""
var badge_width := 18

var _edit: LineEdit
var _dragging := false
var _drag_total := 0.0

func _ready() -> void:
	add_theme_constant_override("separation", 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var badge_panel := PanelContainer.new()
	var badge_style := Kit.flat_style(Kit.SURFACE_3, 4, Kit.BORDER_SOFT, 1)
	badge_style.content_margin_left = 0
	badge_style.content_margin_right = 0
	badge_panel.add_theme_stylebox_override("panel", badge_style)
	badge_panel.custom_minimum_size = Vector2(badge_width, 30)
	badge_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	badge_panel.tooltip_text = "Drag to adjust %s" % axis
	add_child(badge_panel)

	var badge := Kit.label(axis, 9, axis_color, 600)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_panel.add_child(badge)
	badge_panel.gui_input.connect(_on_badge_input)

	_edit = LineEdit.new()
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.custom_minimum_size = Vector2(40, 30)
	_edit.add_theme_font_override("font", Kit.font_regular)
	_edit.add_theme_font_size_override("font_size", 12)
	_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	_edit.text = _format(value)
	_edit.text_submitted.connect(_on_text_submitted)
	_edit.focus_exited.connect(_on_text_submitted)
	add_child(_edit)

func set_value(new_value: float, notify: bool = false) -> void:
	value = clampf(new_value, min_value, max_value)
	if _edit != null and not _edit.has_focus():
		_edit.text = _format(value)
	if notify:
		value_changed.emit(value)

func set_value_silent(new_value: float) -> void:
	set_value(new_value, false)

func _format(v: float) -> String:
	var safe := 0.0 if is_zero_approx(v) else v
	var text := String.num(safe, DECIMALS)
	if text.contains("."):
		text = text.rstrip("0")
		text = text.rstrip(".")
	if text == "-0":
		text = "0"
	return text + suffix

func _apply_drag(delta_x: float) -> void:
	_drag_total += delta_x * step
	var next := clampf(value + delta_x * step, min_value, max_value)
	if not is_equal_approx(next, value):
		value = next
		if _edit != null:
			_edit.text = _format(value)
		value_changed.emit(value)

func _on_badge_input(event: InputEvent) -> void:
	if Kit.is_emulated_mouse(event):
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_dragging = true
			drag_started.emit()
		else:
			_finish_drag()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_apply_drag((event as InputEventMouseMotion).relative.x)
		accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_dragging = true
			drag_started.emit()
		else:
			_finish_drag()
		accept_event()
	elif event is InputEventScreenDrag and _dragging:
		_apply_drag((event as InputEventScreenDrag).relative.x)
		accept_event()

func _finish_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	_drag_total = 0.0
	drag_ended.emit()

func _on_text_submitted(_text: String = "") -> void:
	if _edit == null:
		return
	var text := _edit.text.strip_edges().replace(",", ".")
	if text.ends_with(suffix) and suffix != "":
		text = text.substr(0, text.length() - suffix.length())
	var parsed := text.to_float()
	if text == "" or text == "-" or not text.is_valid_float():
		parsed = value
	parsed = clampf(parsed, min_value, max_value)
	var changed := not is_equal_approx(parsed, value)
	value = parsed
	_edit.text = _format(value)
	if _edit.has_focus():
		_edit.release_focus()
	if changed:
		text_committed.emit(value)

func focused() -> bool:
	return _edit != null and _edit.has_focus()
