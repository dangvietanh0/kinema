extends PanelContainer
## 24 dp instrumentation strip. Desktop only.
##
## Left:  fps · frame time · renderer.
## Right: objects · keys · saved · interface fit.
##
## Every number comes from a real monitor. A value the engine does not report
## is shown as a dash, never as an estimate.

signal action_requested(action: String)

var _left: HBoxContainer
var _right: HBoxContainer
var _fps_label: Label
var _frame_label: Label
var _renderer_label: Label
var _objects_label: Label
var _keys_label: Label
var _saved_label: Label
var _fit_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_build()
	update({}, 0, 0, true, 100.0)


func _build() -> void:
	custom_minimum_size.y = 24
	var style := Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT, 0)
	style.border_width_top = 1
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	_left = HBoxContainer.new()
	_left.add_theme_constant_override("separation", 6)
	row.add_child(_left)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	_right = HBoxContainer.new()
	_right.add_theme_constant_override("separation", 6)
	row.add_child(_right)

	_fps_label = Kit.mono_label("—", 10, Kit.TEXT_MUTED)
	_fps_label.tooltip_text = "Frames per second  ·  tap for performance details"
	Kit.bind_tap(_fps_label, func() -> void: action_requested.emit("performance"))
	_fps_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_left.add_child(_fps_label)
	_left.add_child(_dot())
	_frame_label = Kit.mono_label("—", 10, Kit.TEXT_DIM)
	_left.add_child(_frame_label)
	_left.add_child(_dot())
	_renderer_label = Kit.mono_label("—", 10, Kit.TEXT_DIM)
	_left.add_child(_renderer_label)

	_objects_label = Kit.mono_label("—", 10, Kit.TEXT_DIM)
	_right.add_child(_objects_label)
	_right.add_child(_dot())
	_keys_label = Kit.mono_label("—", 10, Kit.TEXT_DIM)
	_right.add_child(_keys_label)
	_right.add_child(_dot())
	_saved_label = Kit.mono_label("—", 10, Kit.TEXT_DIM)
	_right.add_child(_saved_label)
	_right.add_child(_dot())
	_fit_label = Kit.mono_label("fit —", 11, Kit.TEXT_DIM)
	_fit_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_fit_label.tooltip_text = "Interface fit · choose a workspace"
	Kit.bind_tap(_fit_label, func() -> void: action_requested.emit("workspace"))
	_right.add_child(_fit_label)


func _dot() -> Label:
	var label := Kit.mono_label("·", 10, Kit.TEXT_DIM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func set_mode(mode: String) -> void:
	visible = mode == "desktop"


func update(sample: Dictionary, objects: int, keys: int, saved: bool, fit_percent: float) -> void:
	var fps := float(sample.get("fps", -1.0))
	if fps > 0.0:
		_fps_label.text = "%d fps" % int(round(fps))
		if fps >= 55.0:
			_fps_label.add_theme_color_override("font_color", Kit.TEXT)
		elif fps >= 30.0:
			_fps_label.add_theme_color_override("font_color", Kit.TEXT_MUTED)
		else:
			_fps_label.add_theme_color_override("font_color", Kit.DANGER)
	else:
		_fps_label.text = "— fps"
		_fps_label.add_theme_color_override("font_color", Kit.TEXT_DIM)
	var frame_ms := float(sample.get("frame_ms", -1.0))
	_frame_label.text = "%.1f ms" % frame_ms if frame_ms >= 0.0 else "— ms"
	var renderer := str(sample.get("renderer", ""))
	_renderer_label.text = Gfx.renderer_label(renderer) if renderer != "" else "—"
	_objects_label.text = "%d obj" % objects
	_keys_label.text = "%d keys" % keys
	_saved_label.text = "saved" if saved else "unsaved"
	_saved_label.add_theme_color_override("font_color", Kit.TEXT_DIM if saved else Kit.TEXT)
	_fit_label.text = "fit %d%%" % int(round(fit_percent))
	_fit_label.add_theme_color_override("font_color", Kit.TEXT if fit_percent < 60.0 else Kit.TEXT_DIM)
