extends VBoxContainer
## Compact dope sheet for the selected object.
##
## The sheet intentionally shows one object's three transform channels instead
## of a full scene-wide spreadsheet. That keeps the timeline legible on a phone
## while still allowing keys to be created, retimed and deleted directly.

signal notice(text: String)

class DopeSheet:
	extends Control

	var timeline
	var _drawn := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		_drawn = true
		if timeline != null:
			timeline._draw_sheet(self)

	func _gui_input(event: InputEvent) -> void:
		if timeline != null:
			timeline._sheet_input(event, self)

const DocumentScript = preload("res://src/core/document.gd")
var doc: DocumentScript = null

var _sheet: Control
var _time_label: Label
var _frame_label: Label
var _play_button: Button
var _loop_button: Button
var _auto_button: Button
var _snap_button: Button
var _delete_button: Button
var _start_button: Button
var _end_button: Button

var _selected_channel := "position"
var _selected_index := -1
var _selected_data_id := ""
var _key_hits: Array = []
var _scrubbing := false
var _dragging_key := false
var _sync_flags := false

var _label_width := 104.0
var _ruler_h := 22.0
var _row_h := 26.0
var _grid_left := 110.0
var _grid_width := 200.0

func _ready() -> void:
	add_theme_constant_override("separation", 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_transport()
	_build_sheet()
	resized.connect(_refresh_compact)

func setup(document: Node3D) -> void:
	doc = document
	doc.playback_changed.connect(_on_playback_changed)
	doc.selection_changed.connect(_on_selection_changed)
	doc.object_changed.connect(_on_object_changed)
	doc.scene_changed.connect(_on_scene_changed)
	_sync_flags = true
	_loop_button.button_pressed = doc.loop
	_auto_button.button_pressed = doc.autokey
	_snap_button.button_pressed = doc.snap
	_sync_flags = false
	_style_flag_button(_loop_button, doc.loop)
	_style_flag_button(_snap_button, doc.snap)
	_refresh_transport(doc.current_time, doc.is_playing)
	_refresh_compact()
	_sheet.queue_redraw()

func _build_transport() -> void:
	var panel := PanelContainer.new()
	var style := Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT, 0)
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	panel.add_child(row)

	var time_box := VBoxContainer.new()
	time_box.add_theme_constant_override("separation", 0)
	time_box.custom_minimum_size.x = 76
	row.add_child(time_box)
	_time_label = Kit.mono_label("00:00:00", 12, Kit.TEXT)
	time_box.add_child(_time_label)
	_frame_label = Kit.mono_label("F 0 · 24fps", 8, Kit.TEXT_DIM)
	time_box.add_child(_frame_label)

	var spacer_l := Control.new()
	spacer_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer_l)

	_start_button = Kit.icon_button("skip-back", "Go to start", 28, 14)
	_start_button.pressed.connect(_on_start)
	row.add_child(_start_button)
	var prev := Kit.icon_button("chevron-left", "Previous key", 28, 15)
	prev.pressed.connect(_on_prev_key)
	row.add_child(prev)

	_play_button = Kit.icon_button("play", "Play / pause", 32, 15)
	_play_button.add_theme_color_override("icon_normal_color", Color(0.09, 0.07, 0.05))
	_play_button.add_theme_color_override("icon_hover_color", Color(0.09, 0.07, 0.05))
	_play_button.add_theme_stylebox_override("normal", Kit.flat_style(Kit.ACCENT, 16, Kit.ACCENT, 0))
	_play_button.add_theme_stylebox_override("hover", Kit.flat_style(Kit.ACCENT_BRIGHT, 16, Kit.ACCENT_BRIGHT, 0))
	_play_button.add_theme_stylebox_override("pressed", Kit.flat_style(Kit.ACCENT.darkened(0.1), 16, Kit.ACCENT, 0))
	_play_button.pressed.connect(_on_play)
	row.add_child(_play_button)

	var next := Kit.icon_button("chevron-right", "Next key", 28, 15)
	next.pressed.connect(_on_next_key)
	row.add_child(next)
	_end_button = Kit.icon_button("skip-forward", "Go to end", 28, 14)
	_end_button.pressed.connect(_on_end)
	row.add_child(_end_button)

	var spacer_r := Control.new()
	spacer_r.custom_minimum_size.x = 6
	row.add_child(spacer_r)

	_loop_button = Kit.icon_button("repeat", "Loop playback", 28, 14)
	_loop_button.toggle_mode = true
	_loop_button.toggled.connect(_on_loop_toggled)
	row.add_child(_loop_button)

	_auto_button = Kit.text_toggle("AUTO", "", true)
	_auto_button.custom_minimum_size = Vector2(38, 26)
	_auto_button.tooltip_text = "Auto-key transforms while editing"
	_auto_button.toggled.connect(_on_auto_toggled)
	row.add_child(_auto_button)

	_snap_button = Kit.icon_button("magnet", "Snap keys to frames", 28, 14)
	_snap_button.toggle_mode = true
	_snap_button.toggled.connect(_on_snap_toggled)
	row.add_child(_snap_button)

	var key_button := Kit.icon_button("diamond-plus", "Insert transform keys at playhead", 28, 14)
	key_button.pressed.connect(_on_key_all)
	row.add_child(key_button)

	_delete_button = Kit.icon_button("trash-2", "Delete selected key", 28, 13)
	_delete_button.disabled = true
	_delete_button.add_theme_color_override("icon_disabled_color", Kit.TEXT_DIM * Color(1, 1, 1, 0.4))
	_delete_button.pressed.connect(_on_delete_key)
	row.add_child(_delete_button)

func _build_sheet() -> void:
	var rule := Kit.vsep(Kit.BORDER_SOFT)
	add_child(rule)
	_sheet = DopeSheet.new()
	_sheet.timeline = self
	_sheet.custom_minimum_size.y = 96
	_sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_sheet)

func _refresh_compact() -> void:
	if _start_button == null:
		return
	var compact := size.x < 560.0
	_start_button.visible = not compact
	_end_button.visible = not compact
	_snap_button.visible = not compact
	_frame_label.visible = size.x >= 420.0
	if _sheet != null:
		_sheet.queue_redraw()

func _sync_flag_states() -> void:
	if doc == null:
		return
	_sync_flags = true
	_loop_button.set_pressed_no_signal(doc.loop)
	_auto_button.set_pressed_no_signal(doc.autokey)
	_snap_button.set_pressed_no_signal(doc.snap)
	_sync_flags = false
	_style_flag_button(_loop_button, doc.loop)
	_style_flag_button(_snap_button, doc.snap)

func _style_flag_button(button: Button, active: bool) -> void:
	if active:
		button.add_theme_color_override("icon_normal_color", Kit.ACCENT)
		button.add_theme_color_override("icon_pressed_color", Kit.ACCENT)
		button.add_theme_stylebox_override("normal", Kit.flat_style(Kit.ACCENT_DARK, 5, Kit.ACCENT * Color(1, 1, 1, 0.35), 1))
	else:
		button.add_theme_color_override("icon_normal_color", Kit.TEXT_MUTED)
		button.add_theme_stylebox_override("normal", Kit.flat_style(Color(0, 0, 0, 0), 5, Color(0, 0, 0, 0), 0))

func _refresh_transport(time: float, playing: bool) -> void:
	if doc == null:
		return
	_time_label.text = doc.format_timecode(time)
	_frame_label.text = "F %d · %dfps" % [doc.time_to_frame(time), doc.fps]
	_play_button.icon = Kit.icon_texture("pause" if playing else "play")
	_play_button.tooltip_text = "Pause" if playing else "Play"
	var has_key := _selected_index >= 0 and _selected_data_id == doc.selected_id
	_delete_button.disabled = not has_key

func _on_playback_changed(time: float, playing: bool) -> void:
	_refresh_transport(time, playing)
	if _sheet != null:
		_sheet.queue_redraw()

func _on_selection_changed(_id: String) -> void:
	_selected_index = -1
	_selected_data_id = ""
	_refresh_transport(doc.current_time, doc.is_playing)
	if _sheet != null:
		_sheet.queue_redraw()

func _on_object_changed(_id: String) -> void:
	if _sheet != null:
		_sheet.queue_redraw()

func _on_scene_changed() -> void:
	_sync_flag_states()
	_refresh_transport(doc.current_time, doc.is_playing)
	if _sheet != null:
		_sheet.queue_redraw()

func _on_start() -> void:
	if doc == null:
		return
	doc.pause()
	doc.seek(0.0)

func _on_end() -> void:
	if doc == null:
		return
	doc.pause()
	doc.seek(doc.duration)

func _on_prev_key() -> void:
	if doc == null:
		return
	doc.pause()
	doc.seek(doc.nearest_key_time(-1))

func _on_next_key() -> void:
	if doc == null:
		return
	doc.pause()
	doc.seek(doc.nearest_key_time(1))

func _on_play() -> void:
	if doc != null:
		doc.toggle_play()

func _on_loop_toggled(enabled: bool) -> void:
	if _sync_flags or doc == null:
		return
	doc.set_loop(enabled)
	_style_flag_button(_loop_button, enabled)

func _on_auto_toggled(enabled: bool) -> void:
	if _sync_flags or doc == null:
		return
	doc.set_autokey(enabled)

func _on_snap_toggled(enabled: bool) -> void:
	if _sync_flags or doc == null:
		return
	doc.set_snap(enabled)
	_style_flag_button(_snap_button, enabled)

func _on_key_all() -> void:
	if doc == null:
		return
	if doc.selected_id == "":
		notice.emit("Select an object before inserting keys.")
		return
	doc.insert_transform_keys()
	notice.emit("Keys inserted at " + doc.format_timecode(doc.current_time))
	if _sheet != null:
		_sheet.queue_redraw()

func _on_delete_key() -> void:
	if doc == null or _selected_index < 0 or _selected_data_id != doc.selected_id:
		return
	var keys: Array = doc.get_channel_keys(doc.selected_id, _selected_channel)
	var old_time := doc.format_timecode(doc.current_time)
	if _selected_index < keys.size():
		old_time = doc.format_timecode(float(keys[_selected_index]["time"]))
	doc.delete_key(doc.selected_id, _selected_channel, _selected_index)
	_selected_index = -1
	_selected_data_id = ""
	_refresh_transport(doc.current_time, doc.is_playing)
	notice.emit("Key deleted at " + old_time)
	if _sheet != null:
		_sheet.queue_redraw()

# -------------------------------------------------------------------------
# Dope sheet drawing
# -------------------------------------------------------------------------

func _geometry(canvas: Control) -> void:
	_label_width = 92.0 if canvas.size.x < 500.0 else 112.0
	_ruler_h = 22.0
	var available_h := maxf(60.0, canvas.size.y - _ruler_h - 6.0)
	_row_h = clampf(available_h / 3.0, 20.0, 34.0)
	_grid_left = _label_width + 6.0
	_grid_width = maxf(20.0, canvas.size.x - _grid_left - 8.0)

func _time_to_x(time: float, canvas: Control) -> float:
	if doc == null:
		return _grid_left
	return _grid_left + clampf(time / maxf(0.001, doc.duration), 0.0, 1.0) * _grid_width

func _x_to_time(x: float, _canvas: Control) -> float:
	var t := clampf((x - _grid_left) / maxf(1.0, _grid_width), 0.0, 1.0)
	return t * doc.duration

func _draw_sheet(canvas: Control) -> void:
	_geometry(canvas)
	_key_hits.clear()
	var w := canvas.size.x
	var h := canvas.size.y
	canvas.draw_rect(Rect2(0, 0, w, h), Kit.SURFACE)
	canvas.draw_rect(Rect2(0, 0, w, _ruler_h), Kit.SURFACE_2)
	canvas.draw_line(Vector2(_label_width, 0), Vector2(_label_width, h), Kit.BORDER_SOFT, 1.0)
	canvas.draw_line(Vector2(0, _ruler_h), Vector2(w, _ruler_h), Kit.BORDER_SOFT, 1.0)

	var channel_header := "CHANNELS"
	canvas.draw_string(Kit.font_for(600), Vector2(12, 15), channel_header, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Kit.TEXT_DIM)

	if doc == null:
		return

	var major := _major_step()
	var minor_count := maxi(1, int(round(doc.duration / maxf(0.001, major))))
	for i in range(minor_count + 1):
		var time := float(i) * major
		if time > doc.duration + 0.001:
			break
		var x := _time_to_x(time, canvas)
		canvas.draw_line(Vector2(x, 0), Vector2(x, h), Kit.BORDER_SOFT * Color(1, 1, 1, 0.55), 1.0)
		if x < w - 26.0:
			var label := "%.1fs" % time if major < 1.0 else "%ds" % int(round(time))
			canvas.draw_string(Kit.font_mono, Vector2(x + 3, 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Kit.TEXT_DIM)

	var row_top := _ruler_h
	var channels: Array = doc.CHANNELS
	for ci in range(channels.size()):
		var channel := str(channels[ci])
		var top := row_top + float(ci) * _row_h
		var center_y := top + _row_h * 0.5
		if channel == _selected_channel:
			canvas.draw_rect(Rect2(0, top, w, _row_h), Kit.SURFACE_2)
			canvas.draw_rect(Rect2(0, top, 2, _row_h), Kit.ACCENT)
		elif ci % 2 == 1:
			canvas.draw_rect(Rect2(_label_width, top, w - _label_width, _row_h), Kit.SURFACE * Color(1, 1, 1, 0.35))
		canvas.draw_line(Vector2(0, top + _row_h), Vector2(w, top + _row_h), Kit.BORDER_SOFT, 1.0)

		var label := str(doc.CHANNEL_LABELS.get(channel, channel))
		canvas.draw_string(Kit.font_for(500), Vector2(20, center_y + 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Kit.TEXT if channel == _selected_channel else Kit.TEXT_MUTED)
		var dot_color: Color = [Kit.AXIS_X, Kit.AXIS_Y, Kit.AXIS_Z][ci]
		canvas.draw_circle(Vector2(12, center_y), 2.4, dot_color)

		var keys: Array = doc.get_channel_keys(doc.selected_id, channel) if doc.selected_id != "" else []
		if keys.is_empty():
			continue
		var count_text := str(keys.size())
		var count_size := Kit.font_mono.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
		canvas.draw_string(Kit.font_mono, Vector2(_label_width - 10 - count_size.x, center_y + 3), count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Kit.TEXT_DIM)
		for key in keys:
			if key["time"] > doc.duration + 0.001:
				continue
			var x := _time_to_x(float(key["time"]), canvas)
			var selected := _selected_data_id == doc.selected_id and _selected_index == int(key["index"]) and _selected_channel == channel
			var r := 6.0 if selected else 4.6
			var color := Kit.ACCENT_BRIGHT if selected else Kit.ACCENT
			var points := PackedVector2Array([
				Vector2(x, center_y - r), Vector2(x + r, center_y),
				Vector2(x, center_y + r), Vector2(x - r, center_y),
			])
			canvas.draw_colored_polygon(points, color)
			if selected:
				canvas.draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), Color(1, 1, 1, 0.85), 1.0, true)
			_key_hits.append({"channel": channel, "index": int(key["index"]), "pos": Vector2(x, center_y)})

	var play_x := _time_to_x(doc.current_time, canvas)
	canvas.draw_line(Vector2(play_x, 0), Vector2(play_x, h), Kit.ACCENT * Color(1, 1, 1, 0.75), 1.2)
	var head := PackedVector2Array([Vector2(play_x - 4, 0), Vector2(play_x + 4, 0), Vector2(play_x, 5)])
	canvas.draw_colored_polygon(head, Kit.ACCENT)

	if doc.selected_id == "":
		canvas.draw_string(Kit.font_for(400), Vector2(_label_width + 20, _ruler_h + 32), "Select an object to view its animation channels.", HORIZONTAL_ALIGNMENT_LEFT, w - _label_width - 24, 10, Kit.TEXT_DIM)
	else:
		var rows_bottom := row_top + float(channels.size()) * _row_h
		if h > rows_bottom + 12.0:
			canvas.draw_string(Kit.font_for(400), Vector2(_label_width + 8, rows_bottom + 14), "Drag diamonds to retime · tap the ruler to scrub", HORIZONTAL_ALIGNMENT_LEFT, w - _label_width - 16, 9, Kit.TEXT_DIM)

func _major_step() -> float:
	var px_per_second := _grid_width / maxf(0.001, doc.duration)
	var candidates := [0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 60.0, 120.0, 300.0, 600.0]
	for value in candidates:
		if float(value) * px_per_second >= 46.0:
			return float(value)
	return 600.0

# -------------------------------------------------------------------------
# Dope sheet interaction
# -------------------------------------------------------------------------

func _sheet_input(event: InputEvent, canvas: Control) -> void:
	if doc == null:
		return
	if Kit.is_emulated_mouse(event):
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_press_sheet(button.position, canvas)
		else:
			_release_sheet(button.position)
		canvas.accept_event()
	elif event is InputEventMouseMotion and (_scrubbing or _dragging_key):
		_drag_sheet((event as InputEventMouseMotion).position, canvas)
		canvas.accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_press_sheet(touch.position, canvas)
		else:
			_release_sheet(touch.position)
		canvas.accept_event()
	elif event is InputEventScreenDrag:
		_drag_sheet((event as InputEventScreenDrag).position, canvas)
		canvas.accept_event()

func button_mask_down() -> bool:
	return _scrubbing or _dragging_key

func _press_sheet(pos: Vector2, canvas: Control) -> void:
	_geometry(canvas)
	_selected_data_id = doc.selected_id
	if doc.selected_id == "":
		return
	if pos.y <= _ruler_h or pos.x < _label_width:
		if pos.y > _ruler_h and pos.x < _label_width:
			var ci := int(floor((pos.y - _ruler_h) / maxf(1.0, _row_h)))
			if ci >= 0 and ci < doc.CHANNELS.size():
				_selected_channel = str(doc.CHANNELS[ci])
				_selected_index = -1
				_refresh_transport(doc.current_time, doc.is_playing)
				canvas.queue_redraw()
			return
		_scrubbing = true
		if doc.is_playing:
			doc.pause()
		doc.seek(_x_to_time(pos.x, canvas))
		canvas.queue_redraw()
		return
	var hit := _key_at(pos)
	if hit >= 0:
		var data: Dictionary = _key_hits[hit]
		_selected_channel = str(data["channel"])
		_selected_index = int(data["index"])
		_selected_data_id = doc.selected_id
		_dragging_key = true
		doc.begin_edit("Retime key")
		_refresh_transport(doc.current_time, doc.is_playing)
		canvas.queue_redraw()
		return
	var ci := int(floor((pos.y - _ruler_h) / maxf(1.0, _row_h)))
	if ci >= 0 and ci < doc.CHANNELS.size():
		_selected_channel = str(doc.CHANNELS[ci])
	_selected_index = -1
	_refresh_transport(doc.current_time, doc.is_playing)
	_scrubbing = true
	if doc.is_playing:
		doc.pause()
	doc.seek(_x_to_time(pos.x, canvas))
	canvas.queue_redraw()

func _drag_sheet(pos: Vector2, canvas: Control) -> void:
	if doc.selected_id == "":
		return
	if _dragging_key and _selected_index >= 0:
		var t := _x_to_time(pos.x, canvas)
		var index := doc.set_key_time(doc.selected_id, _selected_channel, _selected_index, t)
		if index >= 0:
			_selected_index = index
		_refresh_transport(doc.current_time, doc.is_playing)
		canvas.queue_redraw()
	elif _scrubbing:
		doc.seek(_x_to_time(pos.x, canvas))
		canvas.queue_redraw()

func _release_sheet(_pos: Vector2) -> void:
	if _dragging_key:
		_dragging_key = false
		doc.end_edit()
		if _selected_index >= 0 and doc.selected_id != "":
			var keys: Array = doc.get_channel_keys(doc.selected_id, _selected_channel)
			if _selected_index < keys.size():
				notice.emit("Key at " + doc.format_timecode(float(keys[_selected_index]["time"])))
	_scrubbing = false
	_sheet.queue_redraw()

func _key_at(pos: Vector2) -> int:
	var best := -1
	var best_dist := 16.0
	for i in range(_key_hits.size()):
		var hit: Dictionary = _key_hits[i]
		var d: float = (hit["pos"] as Vector2).distance_to(pos)
		if d < best_dist:
			best_dist = d
			best = i
	return best
