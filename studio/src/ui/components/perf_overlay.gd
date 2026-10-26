extends PanelContainer
## Live performance readout anchored inside the viewport host.
##
## The numbers are the same engine monitors the status bar uses, sampled at
## 4 Hz by Perf. The graph plots real frame times; a missing monitor is shown
## as a dash instead of an estimate.

const WIDTH := 248.0
const HEIGHT := 190.0
const TOP := 62.0
const MARGIN := 10

var _fps_label: Label
var _frame_label: Label
var _graph: Control
var _draw_label: Label
var _preview_label: Label
var _renderer_label: Label
var _context_label: Label
var _samples: Array = []
var _frame_graph := false


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -WIDTH - 12.0
	offset_top = TOP
	offset_right = -12.0
	offset_bottom = TOP + HEIGHT
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var style := Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER, 1)
	style.content_margin_left = MARGIN
	style.content_margin_right = MARGIN
	style.content_margin_top = 4
	style.content_margin_bottom = MARGIN
	add_theme_stylebox_override("panel", style)
	_build()


func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	header.custom_minimum_size.y = 44.0
	column.add_child(header)
	header.add_child(Kit.section_label("Performance"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)
	var close := Kit.icon_button("x", "Close performance", 30, 14)
	close.pressed.connect(close_overlay)
	header.add_child(close)

	var readout := HBoxContainer.new()
	readout.add_theme_constant_override("separation", 6)
	readout.custom_minimum_size.y = 30.0
	column.add_child(readout)
	_fps_label = Kit.mono_label("—", 22, Kit.TEXT_DIM)
	_fps_label.custom_minimum_size.x = 42.0
	readout.add_child(_fps_label)
	var unit := Kit.mono_label("fps", 11, Kit.TEXT_DIM)
	unit.size_flags_vertical = Control.SIZE_SHRINK_END
	readout.add_child(unit)
	var readout_spacer := Control.new()
	readout_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	readout_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout.add_child(readout_spacer)
	_frame_label = Kit.mono_label("— ms", 11, Kit.TEXT_MUTED)
	_frame_label.size_flags_vertical = Control.SIZE_SHRINK_END
	readout.add_child(_frame_label)

	_graph = Control.new()
	_graph.custom_minimum_size.y = 30.0
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_graph.draw.connect(_draw_graph)
	_graph.visible = _frame_graph
	column.add_child(_graph)

	_draw_label = Kit.mono_label("— draw · — prim", 11, Kit.TEXT_MUTED)
	column.add_child(_draw_label)
	_preview_label = Kit.mono_label("preview —", 11, Kit.TEXT_MUTED)
	column.add_child(_preview_label)
	_renderer_label = Kit.mono_label("—", 11, Kit.TEXT_MUTED)
	column.add_child(_renderer_label)
	_context_label = Kit.mono_label("—", 11, Kit.TEXT_DIM)
	column.add_child(_context_label)


func set_frame_graph(enabled: bool) -> void:
	_frame_graph = enabled
	if _graph != null:
		_graph.visible = enabled
		_graph.queue_redraw()


func open() -> void:
	visible = true


func close_overlay() -> void:
	visible = false


func toggle() -> void:
	visible = not visible


func set_sample(sample: Dictionary, objects: int, keys: int, preview_size: Vector2i) -> void:
	var fps := float(sample.get("fps", -1.0))
	if fps > 0.0:
		_fps_label.text = "%d" % int(round(fps))
		if fps >= 55.0:
			_fps_label.add_theme_color_override("font_color", Kit.TEXT)
		elif fps >= 30.0:
			_fps_label.add_theme_color_override("font_color", Kit.TEXT_MUTED)
		else:
			_fps_label.add_theme_color_override("font_color", Kit.DANGER)
	else:
		_fps_label.text = "—"
		_fps_label.add_theme_color_override("font_color", Kit.TEXT_DIM)
	var frame_ms := float(sample.get("frame_ms", -1.0))
	_frame_label.text = "%.1f ms" % frame_ms if frame_ms >= 0.0 else "— ms"
	var draw_calls := int(sample.get("draw_calls", -1))
	var primitives := int(sample.get("primitives", -1))
	_draw_label.text = "%s draw · %s prim" % [
		"—" if draw_calls < 0 else str(draw_calls),
		"—" if primitives < 0 else str(primitives),
	]
	var scale := float(sample.get("preview_scale", 1.0))
	var resolution := "—"
	if preview_size.x > 0 and preview_size.y > 0:
		resolution = "%d×%d" % [int(round(preview_size.x * scale)), int(round(preview_size.y * scale))]
	_preview_label.text = "preview %d%% · %s" % [int(round(scale * 100.0)), resolution]
	var preset := Gfx.preset
	_renderer_label.text = "%s · %s" % [Gfx.renderer_label(Gfx.renderer_name()), preset.capitalize()]
	_context_label.text = "%d obj · %d keys" % [objects, keys]
	_samples = sample.get("samples", [])
	if _graph != null:
		_graph.queue_redraw()


func _draw_graph() -> void:
	var rect := Rect2(Vector2.ZERO, _graph.size)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	_graph.draw_rect(rect, Kit.SURFACE_2, true)
	# A 30 fps reference line makes a regression readable without inventing a
	# target the device may not reach. The line is a tick, not a threshold.
	var budget := 1000.0 / 30.0
	var peak := maxf(33.4, budget)
	for value in _samples:
		peak = maxf(peak, float(value))
	var y30 := rect.size.y - clampf(budget / peak, 0.0, 1.0) * rect.size.y
	_graph.draw_line(Vector2(0, y30), Vector2(rect.size.x, y30), Kit.BORDER, 1.0)
	if _samples.size() < 2:
		return
	var color := Kit.TEXT_MUTED
	if float(_samples[_samples.size() - 1]) > budget:
		color = Kit.DANGER
	var step := rect.size.x / float(_samples.size() - 1)
	var points := PackedVector2Array()
	for i in range(_samples.size()):
		var value := clampf(float(_samples[i]) / peak, 0.0, 1.0)
		points.append(Vector2(float(i) * step, rect.size.y - value * rect.size.y))
	_graph.draw_polyline(points, color, 1.0, true)
