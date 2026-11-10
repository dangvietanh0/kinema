extends HBoxContainer
## Continuous interface-scale control, 50-200%.
##
## A slider, not a fixed menu: the user can land on any percentage. The value
## label updates while dragging, but persistence is emitted on release (or on a
## keyboard step) so a drag does not write settings.json once per percent.
## The control is never disabled by Desktop fit; fit is shown beside it.

signal value_changed(value: float)

const MIN_PERCENT := 50.0
const MAX_PERCENT := 200.0
const DEFAULT_PERCENT := 100.0

var slider: HSlider
var value_label: Label

var _dragging := false
var _built := false
var _pending_percent := DEFAULT_PERCENT


func _ready() -> void:
	_build()
	if not slider.value_changed.is_connected(_on_value_changed):
		slider.value_changed.connect(_on_value_changed)
	slider.drag_started.connect(_on_drag_started)
	slider.drag_ended.connect(_on_drag_ended.unbind(1))
	set_percent_value(_pending_percent, false)


func _build() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 8)
	slider = HSlider.new()
	slider.min_value = MIN_PERCENT
	slider.max_value = MAX_PERCENT
	slider.step = 1.0
	slider.value = DEFAULT_PERCENT
	slider.custom_minimum_size = Vector2(132.0, 44.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_ALL
	slider.tooltip_text = "Interface scale 50-200%"
	add_child(slider)

	value_label = Kit.mono_label("100%", Kit.TYPE_BODY, Kit.TEXT)
	value_label.custom_minimum_size.x = 54.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(value_label)


## Sets the displayed value without emitting. `percent` is 50-200.
func set_percent_value(percent: float, notify: bool = false) -> void:
	_pending_percent = clampf(percent, MIN_PERCENT, MAX_PERCENT)
	if not _built:
		return
	slider.set_value_no_signal(_pending_percent)
	_update_label(_pending_percent)
	if notify:
		value_changed.emit(_pending_percent / 100.0)


func percent_value() -> float:
	if not _built:
		return _pending_percent
	return slider.value


func scale_value() -> float:
	return percent_value() / 100.0


func _on_value_changed(value: float) -> void:
	_update_label(value)
	# Keyboard and wheel steps arrive here without a drag; commit immediately.
	if not _dragging:
		value_changed.emit(value / 100.0)


func _on_drag_started() -> void:
	_dragging = true


func _on_drag_ended() -> void:
	_dragging = false
	value_changed.emit(slider.value / 100.0)


func _update_label(percent: float) -> void:
	if value_label != null:
		value_label.text = "%d%%" % int(round(percent))
