extends VBoxContainer
## Sequence clip lane.
##
## Layer rows and strip blocks are 44 dp. A strip tap selects its clip through
## `Document.set_active_clip()` and emits a configured `StripSheet`; drag moves
## the strip, the edge handles trim it and the fade handles resize the
## smoothstep envelopes. Overlapping strips are marked with a 1 px hatch.

signal strip_selected(strip_id: String, clip_id: String)
signal sheet_requested(control: Control, title: String, subtitle: String)
signal layers_requested
signal notice(text: String)

const ROW_H := 44.0
const RULER_H := 22.0
const LABEL_W := 92.0
const PAD := 8.0
const STRIP_SHEET_PATH := "res://src/ui/strip_sheet.gd"
const LAYER_SHEET_PATH := "res://src/ui/layer_sheet.gd"

class LaneCanvas:
	extends Control

	var lane = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		if lane != null:
			lane._draw_lane(self)

	func _gui_input(event: InputEvent) -> void:
		if lane != null:
			lane._lane_input(event, self)


var doc = null
var _toolbar: HBoxContainer
var _canvas: LaneCanvas
var _add_button: Button
var _layers_button: Button
var _play_button: Button
var _fit_button: Button
var _time_label: Label
var _selected_strip := ""
var _zoom := 1.0
var _offset := 0.0
var _layer_hits: Array = []
var _strip_hits: Array = []
var _trim_hits: Array = []
var _fade_hits: Array = []
var _drag: Dictionary = {}
var _built := false


func _ready() -> void:
	_ensure_built()
	set_process(true)


func setup(document) -> void:
	if doc != null and doc.has_signal("clips_changed"):
		if doc.clips_changed.is_connected(refresh):
			doc.clips_changed.disconnect(refresh)
	if doc != null and doc.has_signal("active_clip_changed"):
		if doc.active_clip_changed.is_connected(_on_active_clip_changed):
			doc.active_clip_changed.disconnect(_on_active_clip_changed)
	if doc != null and doc.has_signal("playback_changed"):
		if doc.playback_changed.is_connected(_on_playback_changed):
			doc.playback_changed.disconnect(_on_playback_changed)
	doc = document
	_ensure_built()
	if doc != null:
		if doc.has_signal("clips_changed"):
			doc.clips_changed.connect(refresh)
		if doc.has_signal("active_clip_changed"):
			doc.active_clip_changed.connect(_on_active_clip_changed)
		if doc.has_signal("playback_changed"):
			doc.playback_changed.connect(_on_playback_changed)
	refresh()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 0)

	_toolbar = HBoxContainer.new()
	_toolbar.custom_minimum_size.y = 44.0
	_toolbar.add_theme_constant_override("separation", 2)
	add_child(_toolbar)

	_add_button = Kit.text_button("+ Clip", "", false, true)
	_add_button.tooltip_text = "Create a clip and place a strip on the active layer"
	_add_button.pressed.connect(_on_add_clip)
	_toolbar.add_child(_add_button)

	_layers_button = Kit.text_button("Layers", "", false, true)
	_layers_button.tooltip_text = "Open the layer sheet"
	_layers_button.pressed.connect(_on_layers)
	_toolbar.add_child(_layers_button)

	_play_button = Kit.text_button("Play sequence", "play", false, true)
	_play_button.tooltip_text = "Play or pause the whole sequence"
	_play_button.pressed.connect(_on_play)
	_toolbar.add_child(_play_button)

	_fit_button = Kit.text_button("Fit", "", false, true)
	_fit_button.tooltip_text = "Fit the sequence into the lane"
	_fit_button.pressed.connect(_on_fit)
	_toolbar.add_child(_fit_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toolbar.add_child(spacer)

	_time_label = Kit.mono_label("0.00 / 0.00", 10, Kit.TEXT_DIM)
	_toolbar.add_child(_time_label)

	_canvas = LaneCanvas.new()
	_canvas.lane = self
	_canvas.custom_minimum_size = Vector2(0, RULER_H + ROW_H)
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_canvas)


func refresh() -> void:
	_ensure_built()
	if doc == null or doc.animation_system == null:
		return
	var layers: Array = doc.animation_system.layers()
	_rebuild_hits(layers)
	var wanted := RULER_H + ROW_H * float(maxi(1, layers.size())) + 4.0
	if _canvas != null:
		_canvas.custom_minimum_size.y = wanted
		_canvas.queue_redraw()
	_update_time_label()
	_sync_play_button()


func _rebuild_hits(layers: Array) -> void:
	_layer_hits.clear()
	_strip_hits.clear()
	_trim_hits.clear()
	_fade_hits.clear()
	var width := _canvas_width()
	var y := RULER_H
	for index in range(layers.size()):
		var layer: Dictionary = layers[index]
		var row := Rect2(0, y, width, ROW_H)
		_layer_hits.append({"id": str(layer.get("id", "")), "rect": row, "layer": layer})
		for strip in layer.get("strips", []):
			if not strip is Dictionary:
				continue
			var clip: Dictionary = doc.animation_system.get_clip(str(strip.get("clip", "")))
			if clip.is_empty():
				continue
			var start := float(strip.get("start", 0.0))
			var end := _strip_end(strip, clip)
			var x0 := _time_to_x(start)
			var x1 := _time_to_x(end)
			var rect := Rect2(x0, y, maxf(24.0, x1 - x0), ROW_H)
			var hit_width := maxf(44.0, rect.size.x)
			var hit_rect := Rect2(rect.position.x + rect.size.x * 0.5 - hit_width * 0.5, y, hit_width, ROW_H)
			_strip_hits.append({
				"strip_id": str(strip.get("id", "")),
				"clip_id": str(strip.get("clip", "")),
				"layer_id": str(layer.get("id", "")),
				"rect": rect,
				"hit_rect": hit_rect,
				"strip": strip,
				"clip": clip,
			})
			_trim_hits.append({
				"mode": "trim_start",
				"strip_id": str(strip.get("id", "")),
				"rect": Rect2(x0 - 22.0, y, 44.0, ROW_H),
			})
			_trim_hits.append({
				"mode": "trim_end",
				"strip_id": str(strip.get("id", "")),
				"rect": Rect2(x1 - 22.0, y, 44.0, ROW_H),
			})
			var fade_in_x := _time_to_x(start + float(strip.get("fade_in", 0.0)))
			var fade_out_x := _time_to_x(end - float(strip.get("fade_out", 0.0)))
			if float(strip.get("fade_in", 0.0)) > 0.0:
				_fade_hits.append({
					"mode": "fade_in",
					"strip_id": str(strip.get("id", "")),
					"rect": Rect2(fade_in_x - 22.0, y, 44.0, ROW_H),
				})
			if float(strip.get("fade_out", 0.0)) > 0.0:
				_fade_hits.append({
					"mode": "fade_out",
					"strip_id": str(strip.get("id", "")),
					"rect": Rect2(fade_out_x - 22.0, y, 44.0, ROW_H),
				})
		y += ROW_H


func layer_row_count() -> int:
	return _layer_hits.size()


func strip_block_count() -> int:
	return _strip_hits.size()


func row_height() -> float:
	return ROW_H


func play_sequence_button() -> Button:
	return _play_button


func strip_rect(strip_id: String) -> Rect2:
	for hit in _strip_hits:
		if str(hit.get("strip_id", "")) == strip_id:
			return hit["rect"]
	return Rect2()


func strip_hit_rect(strip_id: String) -> Rect2:
	for hit in _strip_hits:
		if str(hit.get("strip_id", "")) == strip_id:
			return hit.get("hit_rect", hit["rect"])
	return Rect2()


func fade_handle_rects() -> Array:
	var rects: Array = []
	for hit in _fade_hits:
		rects.append(hit["rect"])
	return rects


func tap_strip(strip_id: String) -> void:
	for hit in _strip_hits:
		if str(hit.get("strip_id", "")) == strip_id:
			_select_strip(strip_id, str(hit.get("clip_id", "")))
			return


func _select_strip(strip_id: String, clip_id: String) -> void:
	_selected_strip = strip_id
	if doc != null and clip_id != "" and doc.active_clip_id() != clip_id:
		doc.set_active_clip(clip_id)
	strip_selected.emit(strip_id, clip_id)
	var sheet := _build_strip_sheet(strip_id)
	if sheet != null:
		sheet_requested.emit(sheet, "Strip", "Trim, speed, weight and fades.")
	refresh()


func _build_strip_sheet(strip_id: String) -> Control:
	var script = load(STRIP_SHEET_PATH)
	if script == null:
		return null
	var sheet: Control = script.new()
	sheet.setup(doc)
	sheet.open(strip_id)
	return sheet


func _on_active_clip_changed(_id: String) -> void:
	refresh()


func _on_playback_changed(_time: float, _playing: bool) -> void:
	_update_time_label()
	_sync_play_button()
	if _canvas != null:
		_canvas.queue_redraw()


func _on_add_clip() -> void:
	if doc == null or doc.animation_system == null:
		return
	if doc.has_method("begin_edit"):
		doc.begin_edit("Add clip")
	var system = doc.animation_system
	var name := "Clip %d" % (system.clip_ids().size() + 1)
	var clip_id: String = system.create_clip(name, 2.0)
	var layer_id: String = system.active_layer_id()
	if layer_id == "" and not system.layers().is_empty():
		layer_id = str(system.layers()[0].get("id", ""))
	if layer_id != "":
		system.add_strip(layer_id, clip_id, doc.sequence_duration())
	doc.set_active_clip(clip_id)
	if doc.has_method("end_edit"):
		doc.end_edit()
	refresh()


func _on_layers() -> void:
	layers_requested.emit()
	var script = load(LAYER_SHEET_PATH)
	if script == null or doc == null:
		return
	var sheet: Control = script.new()
	sheet.setup(doc)
	sheet.open(doc.animation_system.active_layer_id())
	sheet_requested.emit(sheet, "Layers", "Blend, weight, mute and solo.")


func _on_play() -> void:
	if doc == null:
		return
	if doc.is_sequence_playing():
		doc.pause_sequence()
	else:
		doc.play_sequence()
	_sync_play_button()
	refresh()


func _on_fit() -> void:
	_zoom = 1.0
	_offset = 0.0
	refresh()


func _zoom_at(position: Vector2, factor: float) -> void:
	var anchor := _x_to_time(position.x)
	_zoom = clampf(_zoom * factor, 0.25, 16.0)
	# Keep the time under the pointer fixed while the scale changes.
	_offset = position.x - LABEL_W - anchor * _px_per_second()
	refresh()


func _sync_play_button() -> void:
	if _play_button == null or doc == null:
		return
	var playing: bool = doc.is_sequence_playing()
	_play_button.text = "Pause" if playing else "Play sequence"
	Kit.set_icon(_play_button, "pause" if playing else "play")


func _update_time_label() -> void:
	if _time_label == null or doc == null:
		return
	_time_label.text = "%.2f / %.2f" % [doc.sequence_time(), doc.sequence_duration()]


func _process(_delta: float) -> void:
	if doc != null and doc.is_sequence_playing() and _canvas != null:
		_canvas.queue_redraw()
		_update_time_label()


func _canvas_width() -> float:
	return maxf(320.0, _canvas.size.x if _canvas != null else 320.0)


func _px_per_second() -> float:
	if doc == null:
		return 1.0
	var duration := maxf(0.04, doc.sequence_duration())
	var available := maxf(40.0, _canvas_width() - LABEL_W - PAD)
	return available / duration * _zoom


func _time_to_x(time: float) -> float:
	return LABEL_W + time * _px_per_second() + _offset


func _x_to_time(x: float) -> float:
	return (x - LABEL_W - _offset) / maxf(0.0001, _px_per_second())


func _strip_end(strip: Dictionary, clip: Dictionary) -> float:
	var length := maxf(0.001, float(clip.get("duration", 0.04)))
	var trim_start := clampf(float(strip.get("trim_start", 0.0)), 0.0, length)
	var trim_end := clampf(float(strip.get("trim_end", length)), trim_start + 0.001, length)
	var speed := maxf(0.05, float(strip.get("speed", 1.0)))
	return maxf(0.0, float(strip.get("start", 0.0))) + (trim_end - trim_start) / speed


func _hit_at(position: Vector2) -> Dictionary:
	# On a strip narrower than the 44 px handles the two trim rects (and any
	# fade rects) cover the whole block. Let the centre and the padded area
	# outside the visual block win so move/tap-select stays reachable; only the
	# thin visual edges keep the trim/fade handles.
	for hit in _strip_hits:
		var strip_rect: Rect2 = hit["rect"]
		var hit_rect: Rect2 = hit.get("hit_rect", strip_rect)
		if strip_rect.size.x > 44.0 or not hit_rect.has_point(position):
			continue
		var edge := clampf(strip_rect.size.x * 0.25, 4.0, 10.0)
		var in_visual := position.x >= strip_rect.position.x and position.x <= strip_rect.end.x
		if not in_visual or (position.x > strip_rect.position.x + edge and position.x < strip_rect.end.x - edge):
			return _strip_move_hit(hit)
	for hit in _fade_hits:
		if hit["rect"].has_point(position):
			var strip := _strip_hit(str(hit["strip_id"]))
			return {
				"kind": "fade",
				"mode": str(hit["mode"]),
				"strip_id": str(hit["strip_id"]),
				"clip_id": str(strip.get("clip_id", "")),
			}
	for hit in _trim_hits:
		if hit["rect"].has_point(position):
			var strip := _strip_hit(str(hit["strip_id"]))
			return {
				"kind": "trim",
				"mode": str(hit["mode"]),
				"strip_id": str(hit["strip_id"]),
				"clip_id": str(strip.get("clip_id", "")),
			}
	for hit in _strip_hits:
		var hit_rect: Rect2 = hit.get("hit_rect", hit["rect"])
		if hit_rect.has_point(position):
			return _strip_move_hit(hit)
	return {}


func _strip_move_hit(hit: Dictionary) -> Dictionary:
	return {
		"kind": "strip",
		"mode": "move",
		"strip_id": str(hit["strip_id"]),
		"clip_id": str(hit["clip_id"]),
	}


func _strip_hit(strip_id: String) -> Dictionary:
	for hit in _strip_hits:
		if str(hit.get("strip_id", "")) == strip_id:
			return hit
	return {}


func _lane_input(event: InputEvent, _canvas: Control) -> void:
	if Kit.is_emulated_mouse(event):
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if button.pressed:
				_zoom_at(button.position, 1.25 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8)
				accept_event()
			return
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_begin_drag(button.position)
		else:
			_end_drag()
		accept_event()
	elif event is InputEventMouseMotion and not _drag.is_empty():
		_update_drag((event as InputEventMouseMotion).position)
		accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin_drag(touch.position)
		else:
			_end_drag()
		accept_event()
	elif event is InputEventScreenDrag and not _drag.is_empty():
		_update_drag((event as InputEventScreenDrag).position)
		accept_event()


func _begin_drag(position: Vector2) -> void:
	var hit := _hit_at(position)
	if hit.is_empty():
		return
	if str(hit.get("kind", "")) == "strip":
		_select_strip(str(hit.get("strip_id", "")), str(hit.get("clip_id", "")))
	var strip: Dictionary = doc.animation_system.get_strip(str(hit.get("strip_id", "")))
	if strip.is_empty():
		return
	_drag = {
		"mode": str(hit.get("mode", "move")),
		"strip_id": str(hit.get("strip_id", "")),
		"start_pos": position,
		"origin": strip,
		"moved": false,
	}
	if doc.has_method("begin_edit"):
		doc.begin_edit("Edit strip")


func _update_drag(position: Vector2) -> void:
	var start_pos: Vector2 = _drag.get("start_pos", position)
	var dx := position.x - start_pos.x
	if absf(dx) > 2.0:
		_drag["moved"] = true
	var origin: Dictionary = _drag.get("origin", {})
	var mode := str(_drag.get("mode", "move"))
	var speed := maxf(0.05, float(origin.get("speed", 1.0)))
	var trim_start := float(origin.get("trim_start", 0.0))
	var trim_end := float(origin.get("trim_end", 0.04))
	var span := (trim_end - trim_start) / speed
	var dt := dx / maxf(0.0001, _px_per_second())
	var patch: Dictionary = {}
	match mode:
		"move":
			patch["start"] = maxf(0.0, float(origin.get("start", 0.0)) + dt)
		"trim_start":
			patch["start"] = maxf(0.0, float(origin.get("start", 0.0)) + dt)
			patch["trim_start"] = clampf(trim_start + dt * speed, 0.0, trim_end - 0.001)
		"trim_end":
			patch["trim_end"] = clampf(trim_end + dt * speed, trim_start + 0.001, _clip_length(str(origin.get("clip", ""))))
		"fade_in":
			patch["fade_in"] = clampf(float(origin.get("fade_in", 0.0)) + dt, 0.0, maxf(0.0, span - float(origin.get("fade_out", 0.0))))
		"fade_out":
			patch["fade_out"] = clampf(float(origin.get("fade_out", 0.0)) - dt, 0.0, maxf(0.0, span - float(origin.get("fade_in", 0.0))))
		_:
			return
	doc.animation_system.update_strip(str(_drag.get("strip_id", "")), patch)
	refresh()


func _end_drag() -> void:
	if _drag.is_empty():
		return
	_drag = {}
	if doc.has_method("end_edit"):
		doc.end_edit()
	refresh()


func _clip_length(clip_id: String) -> float:
	var clip: Dictionary = doc.animation_system.get_clip(clip_id)
	return maxf(0.04, float(clip.get("duration", 0.04)))


func _draw_lane(canvas: Control) -> void:
	if doc == null or doc.animation_system == null:
		return
	var width := _canvas_width()
	var height := maxf(canvas.size.y, RULER_H + ROW_H)
	canvas.draw_rect(Rect2(0, 0, width, height), Kit.SURFACE)
	canvas.draw_rect(Rect2(0, 0, width, RULER_H), Kit.SURFACE_2)
	canvas.draw_line(Vector2(LABEL_W, 0), Vector2(LABEL_W, height), Kit.BORDER_SOFT, 1)

	var duration := maxf(0.04, doc.sequence_duration())
	for tick in [0.0, duration * 0.5, duration]:
		var x := _time_to_x(tick)
		canvas.draw_line(Vector2(x, RULER_H - 4.0), Vector2(x, RULER_H), Kit.BORDER, 1)
		canvas.draw_string(Kit.font_mono, Vector2(x + 3.0, 11.0), "%.2f" % tick, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Kit.TEXT_DIM)

	for index in range(_layer_hits.size()):
		var hit: Dictionary = _layer_hits[index]
		var row: Rect2 = hit["rect"]
		var layer: Dictionary = hit["layer"]
		canvas.draw_rect(row, Kit.SURFACE if index % 2 == 0 else Kit.SURFACE_2)
		canvas.draw_line(Vector2(0, row.end.y), Vector2(width, row.end.y), Kit.BORDER_SOFT, 1)
		canvas.draw_string(Kit.font_regular, Vector2(8, row.position.y + 17.0), str(layer.get("name", "Layer")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Kit.TEXT)
		var flags := ""
		if bool(layer.get("muted", false)):
			flags += " · M"
		if bool(layer.get("solo", false)):
			flags += " · S"
		var sub := "%.2f · %s%s" % [float(layer.get("weight", 1.0)), str(layer.get("blend", "override")), flags]
		canvas.draw_string(Kit.font_mono, Vector2(8, row.position.y + 33.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Kit.TEXT_DIM)

	var index := 0
	for hit in _strip_hits:
		var rect: Rect2 = hit["rect"]
		var strip: Dictionary = hit["strip"]
		var clip: Dictionary = hit["clip"]
		var selected := str(hit.get("strip_id", "")) == _selected_strip
		var shade := 0.16 + 0.035 * float(index % 4)
		var fill := Color(shade, shade, shade, 1.0)
		canvas.draw_rect(rect, fill)
		canvas.draw_rect(rect, Kit.FOCUS if selected else Kit.BORDER, false, 1)
		# Trim bars stay visible even when both fades are zero.
		canvas.draw_rect(Rect2(rect.position.x, rect.position.y, 2.0, rect.size.y), Kit.TEXT_DIM)
		canvas.draw_rect(Rect2(rect.end.x - 2.0, rect.position.y, 2.0, rect.size.y), Kit.TEXT_DIM)
		var clip_name := str(clip.get("name", "Clip"))
		canvas.draw_string(Kit.font_regular, Vector2(rect.position.x + 6.0, rect.position.y + 17.0), clip_name, HORIZONTAL_ALIGNMENT_LEFT, maxf(20.0, rect.size.x - 12.0), 10, Kit.TEXT)
		var start := float(strip.get("start", 0.0))
		var end := _strip_end(strip, clip)
		var meta := "%.2f–%.2f · ×%.2f" % [start, end, float(strip.get("speed", 1.0))]
		canvas.draw_string(Kit.font_mono, Vector2(rect.position.x + 6.0, rect.position.y + 33.0), meta, HORIZONTAL_ALIGNMENT_LEFT, maxf(20.0, rect.size.x - 12.0), 8, Kit.TEXT_DIM)
		var fade_in_x := _time_to_x(start + float(strip.get("fade_in", 0.0)))
		var fade_out_x := _time_to_x(end - float(strip.get("fade_out", 0.0)))
		if float(strip.get("fade_in", 0.0)) > 0.0:
			canvas.draw_line(Vector2(fade_in_x, rect.position.y), Vector2(fade_in_x, rect.end.y), Kit.TIME_DARK, 1)
			canvas.draw_rect(Rect2(fade_in_x - 1.0, rect.position.y, 2.0, rect.size.y), Kit.TIME)
		if float(strip.get("fade_out", 0.0)) > 0.0:
			canvas.draw_line(Vector2(fade_out_x, rect.position.y), Vector2(fade_out_x, rect.end.y), Kit.TIME_DARK, 1)
			canvas.draw_rect(Rect2(fade_out_x - 1.0, rect.position.y, 2.0, rect.size.y), Kit.TIME)
		index += 1

	_draw_overlap_hatch(canvas)

	var playhead_x := _time_to_x(doc.sequence_time())
	canvas.draw_line(Vector2(playhead_x, RULER_H), Vector2(playhead_x, height), Kit.FOCUS, 1)


func _draw_overlap_hatch(canvas: Control) -> void:
	var by_layer: Dictionary = {}
	for hit in _strip_hits:
		var layer_id := str(hit.get("layer_id", ""))
		if not by_layer.has(layer_id):
			by_layer[layer_id] = []
		by_layer[layer_id].append(hit)
	for layer_id in by_layer.keys():
		var rows: Array = by_layer[layer_id]
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["rect"] as Rect2).position.x < (b["rect"] as Rect2).position.x
		)
		for i in range(rows.size() - 1):
			var a: Rect2 = rows[i]["rect"]
			var b: Rect2 = rows[i + 1]["rect"]
			var x0 := maxf(a.position.x, b.position.x)
			var x1 := minf(a.end.x, b.end.x)
			if x1 <= x0 + 0.5:
				continue
			var y0 := maxf(a.position.y, b.position.y)
			var y1 := minf(a.end.y, b.end.y)
			var x := x0
			while x < x1:
				var bottom_x := minf(x + (y1 - y0), x1)
				canvas.draw_line(Vector2(x, y0), Vector2(bottom_x, y1), Kit.BORDER, 1)
				x += 4.0
