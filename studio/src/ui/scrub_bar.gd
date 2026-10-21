extends Control
## Thin horizontal value track used for material and light properties.

signal value_changed(value: float)
signal drag_started
signal drag_ended

var min_value := 0.0
var max_value := 1.0
var value := 0.0
var fill_color := Color(0.851, 0.647, 0.396, 1.0)
var height := 24.0
var _dragging := false

func _ready() -> void:
	custom_minimum_size.y = height
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	focus_mode = Control.FOCUS_NONE
	queue_redraw()

func set_value(new_value: float, notify: bool = false) -> void:
	value = clampf(new_value, min_value, max_value)
	queue_redraw()
	if notify:
		value_changed.emit(value)

func _normalized() -> float:
	if is_equal_approx(max_value, min_value):
		return 0.0
	return clampf((value - min_value) / (max_value - min_value), 0.0, 1.0)

func _set_from_x(x: float) -> void:
	var t := clampf(x / maxf(1.0, size.x), 0.0, 1.0)
	var next := lerpf(min_value, max_value, t)
	if not is_equal_approx(next, value):
		value = next
		queue_redraw()
		value_changed.emit(value)

func _draw() -> void:
	var y := size.y * 0.5
	var track := Rect2(0, y - 2, size.x, 4)
	draw_rect(track, Kit.BORDER_SOFT, true)
	var fill := Rect2(0, y - 2, size.x * _normalized(), 4)
	if fill.size.x > 0.0:
		draw_rect(fill, fill_color, true)
	var knob := Vector2(size.x * _normalized(), y)
	draw_circle(knob, 6.0, Kit.SURFACE)
	draw_arc(knob, 5.0, 0.0, TAU, 24, fill_color, 2.0, true)

func _gui_input(event: InputEvent) -> void:
	if Kit.is_emulated_mouse(event):
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_dragging = true
			drag_started.emit()
			_set_from_x(button.position.x)
		else:
			_finish()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_set_from_x((event as InputEventMouseMotion).position.x)
		accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_dragging = true
			drag_started.emit()
			_set_from_x(touch.position.x)
		else:
			_finish()
		accept_event()
	elif event is InputEventScreenDrag and _dragging:
		_set_from_x((event as InputEventScreenDrag).position.x)
		accept_event()

func _finish() -> void:
	if not _dragging:
		return
	_dragging = false
	drag_ended.emit()
