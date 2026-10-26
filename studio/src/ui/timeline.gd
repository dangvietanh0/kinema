extends VBoxContainer
## Compact dope sheet for the selected object.
##
## The sheet intentionally shows one object's three transform channels instead
## of a full scene-wide spreadsheet. That keeps the timeline legible on a phone
## while still allowing keys to be created, retimed and deleted directly.

signal notice(text: String)
## Emitted by the compact sheet header so the editor can fold the timeline.
signal close_requested

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
var _mode_button: Button
var _ease_button: Button
var _fold_button: Button

var _transport_panel: PanelContainer
var _transport_style: StyleBoxFlat
var _time_box: VBoxContainer
var _compact_header: PanelContainer
var _compact_mode_button: Button
var _compact_loop_button: Button
var _compact_snap_button: Button
var _compact_delete_button: Button
var _compact_close_button: Button

var _selected_channel := "position"
var _selected_index := -1
var _selected_data_id := ""
var _key_hits: Array = []
var _ease_hits: Array = []
var _scrubbing := false
var _dragging_key := false
var _dragging_ease := false
var _ease_start_y := 0.0
var _ease_start_value := 1.0
var _sync_flags := false
var _mode := "dope"
var _graph_max_speed := 0.0001
var _graph_baseline := 0.0
var _graph_top := 0.0
var _sheet_rule: ColorRect
var _sheet_open := true
var _chrome_mode := "studio"
## Width the editor has actually reserved for the sheet, before the transport's
## own minimum size is applied. A container reports its forced size, so using
## that to decide the overflow layout made the transport's minimum width widen
## the center column and hide its own narrow state.
var _available_width := -1.0
var _transport_buttons: Array[Button] = []

var _label_width := 104.0
var _ruler_h := 22.0
var _row_h := 26.0
var _grid_left := 110.0
var _grid_width := 200.0

func _ready() -> void:
	add_theme_constant_override("separation", 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_transport()
	_build_compact_header()
	_build_sheet()
	resized.connect(_refresh_compact)

func setup(document: Node3D) -> void:
	doc = document
	doc.playback_changed.connect(_on_playback_changed)
	doc.selection_changed.connect(_on_selection_changed)
	doc.object_changed.connect(_on_object_changed)
	doc.transform_changed.connect(_on_transform_changed)
	doc.keyframes_changed.connect(_on_keyframes_changed)
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
	_transport_panel = panel
	var style := Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT, 0)
	style.border_width_top = 1
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	_transport_style = style
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	panel.add_child(row)

	var time_box := VBoxContainer.new()
	_time_box = time_box
	time_box.add_theme_constant_override("separation", 0)
	time_box.custom_minimum_size.x = 76
	row.add_child(time_box)
	_time_label = Kit.mono_label("00:00:00", 12, Kit.TEXT)
	time_box.add_child(_time_label)
	_frame_label = Kit.mono_label("F 0 · 24fps", 8, Kit.TEXT_DIM)
	time_box.add_child(_frame_label)

	_mode_button = Kit.icon_button("speed-graph", "Speed graph editor", 28, 14)
	_mode_button.toggle_mode = true
	_mode_button.toggled.connect(_on_mode_toggled)
	row.add_child(_mode_button)
	_transport_buttons.append(_mode_button)

	var spacer_l := Control.new()
	spacer_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer_l)

	_start_button = Kit.icon_button("skip-back", "Go to start", 28, 14)
	_start_button.pressed.connect(_on_start)
	row.add_child(_start_button)
	_transport_buttons.append(_start_button)
	var prev := Kit.icon_button("chevron-left", "Previous key", 28, 15)
	prev.pressed.connect(_on_prev_key)
	row.add_child(prev)
	_transport_buttons.append(prev)

	_play_button = Kit.icon_button("play", "Play / pause", 32, 15)
	# Transport is a tool, not a call to action. A bright glyph on a dark
	# surface keeps it legible without turning the row into a white slab.
	_play_button.add_theme_color_override("icon_normal_color", Kit.TIME_BRIGHT)
	_play_button.add_theme_color_override("icon_hover_color", Kit.FOCUS_BRIGHT)
	_play_button.add_theme_color_override("icon_pressed_color", Kit.BG)
	_play_button.add_theme_stylebox_override("normal", Kit.flat_style(Kit.SURFACE_2, 0, Color(0, 0, 0, 0), 0))
	_play_button.add_theme_stylebox_override("hover", Kit.flat_style(Kit.SURFACE_3, 0, Color(0, 0, 0, 0), 0))
	_play_button.add_theme_stylebox_override("pressed", Kit.flat_style(Kit.TIME_BRIGHT, 0, Kit.TIME_BRIGHT, 0))
	_play_button.pressed.connect(_on_play)
	row.add_child(_play_button)

	var next := Kit.icon_button("chevron-right", "Next key", 28, 15)
	next.pressed.connect(_on_next_key)
	row.add_child(next)
	_transport_buttons.append(next)
	_end_button = Kit.icon_button("skip-forward", "Go to end", 28, 14)
	_end_button.pressed.connect(_on_end)
	row.add_child(_end_button)
	_transport_buttons.append(_end_button)

	var spacer_r := Control.new()
	spacer_r.custom_minimum_size.x = 6
	row.add_child(spacer_r)

	_loop_button = Kit.icon_button("repeat", "Loop playback", 28, 14)
	_loop_button.toggle_mode = true
	_loop_button.toggled.connect(_on_loop_toggled)
	row.add_child(_loop_button)
	_transport_buttons.append(_loop_button)

	_auto_button = Kit.text_toggle("AUTO", "", true)
	_auto_button.custom_minimum_size = Vector2(38, 26)
	_auto_button.tooltip_text = "Auto-key transforms while editing"
	_auto_button.add_theme_stylebox_override("normal", Kit.style_with_margins(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector4(4, 2, 4, 2)))
	_auto_button.add_theme_stylebox_override("hover", Kit.style_with_margins(Kit.SURFACE_HOVER, 0, Color(0, 0, 0, 0), 0, Vector4(4, 2, 4, 2)))
	_auto_button.add_theme_stylebox_override("pressed", Kit.style_with_margins(Kit.FOCUS_DARK, 0, Kit.FOCUS * Color(1, 1, 1, 0.34), 0, Vector4(4, 2, 4, 2)))
	_auto_button.add_theme_stylebox_override("hover_pressed", Kit.style_with_margins(Kit.FOCUS_DARK.lightened(0.03), 0, Kit.FOCUS * Color(1, 1, 1, 0.52), 0, Vector4(4, 2, 4, 2)))
	_auto_button.toggled.connect(_on_auto_toggled)
	row.add_child(_auto_button)

	_snap_button = Kit.icon_button("magnet", "Snap keys to frames", 28, 14)
	_snap_button.toggle_mode = true
	_snap_button.toggled.connect(_on_snap_toggled)
	row.add_child(_snap_button)
	_transport_buttons.append(_snap_button)

	var key_button := Kit.icon_button("diamond-plus", "Insert transform keys at playhead", 28, 14)
	key_button.pressed.connect(_on_key_all)
	row.add_child(key_button)
	_transport_buttons.append(key_button)

	_delete_button = Kit.icon_button("trash-2", "Delete selected key", 28, 13)
	_delete_button.disabled = true
	_delete_button.add_theme_color_override("icon_disabled_color", Kit.TEXT_DIM * Color(1, 1, 1, 0.4))
	_delete_button.pressed.connect(_on_delete_key)
	row.add_child(_delete_button)
	_transport_buttons.append(_delete_button)

	_ease_button = Kit.text_button("EASE", "", false, true)
	_ease_button.custom_minimum_size = Vector2(44, 26)
	_ease_button.tooltip_text = "Easing presets for the selected key"
	_ease_button.visible = false
	_ease_button.pressed.connect(_open_ease_menu)
	row.add_child(_ease_button)

	# The sheet can fold without leaving the workbench: the transport stays,
	# and this control flips between fold and open. Compact uses the bottom
	# action bar as its explicit toggle instead.
	_fold_button = Kit.icon_button("chevron-down", "Fold the timeline", 44, 18)
	_fold_button.pressed.connect(func() -> void: close_requested.emit())
	row.add_child(_fold_button)
	_transport_buttons.append(_fold_button)


## The phone sheet header. Compact transport carries only the actions a thumb
## needs while scrubbing; graph, loop, snap, delete and fold live here, where
## they belong to the sheet the user is actually looking at. Keeping them out
## of the transport row is what lets the shell fit a 320 dp phone.
func _build_compact_header() -> void:
	_compact_header = PanelContainer.new()
	_compact_header.custom_minimum_size.y = 48
	_compact_header.visible = false
	var style := Kit.flat_style(Kit.SURFACE_2, 0, Kit.BORDER_SOFT, 0)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	_compact_header.add_theme_stylebox_override("panel", style)
	add_child(_compact_header)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_compact_header.add_child(row)

	_compact_mode_button = Kit.icon_button("speed-graph", "Speed graph editor", 44, 18)
	_compact_mode_button.toggle_mode = true
	_compact_mode_button.toggled.connect(_on_compact_mode_toggled)
	row.add_child(_compact_mode_button)

	_compact_loop_button = Kit.icon_button("repeat", "Loop playback", 44, 18)
	_compact_loop_button.toggle_mode = true
	_compact_loop_button.toggled.connect(_on_compact_loop_toggled)
	row.add_child(_compact_loop_button)

	_compact_snap_button = Kit.icon_button("magnet", "Snap keys to frames", 44, 18)
	_compact_snap_button.toggle_mode = true
	_compact_snap_button.toggled.connect(_on_compact_snap_toggled)
	row.add_child(_compact_snap_button)

	_compact_delete_button = Kit.icon_button("trash-2", "Delete selected key", 44, 17)
	_compact_delete_button.disabled = true
	_compact_delete_button.pressed.connect(_on_delete_key)
	row.add_child(_compact_delete_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	_compact_close_button = Kit.icon_button("chevron-down", "Fold the timeline", 44, 18)
	_compact_close_button.pressed.connect(func() -> void: close_requested.emit())
	row.add_child(_compact_close_button)


func _sync_compact_header() -> void:
	if _compact_mode_button == null:
		return
	_sync_flags = true
	_compact_mode_button.set_pressed_no_signal(_mode == "graph")
	_compact_loop_button.set_pressed_no_signal(doc != null and doc.loop)
	_compact_snap_button.set_pressed_no_signal(doc != null and doc.snap)
	_sync_flags = false
	_style_flag_button(_compact_mode_button, _mode == "graph")
	_style_flag_button(_compact_loop_button, doc != null and doc.loop)
	_style_flag_button(_compact_snap_button, doc != null and doc.snap)
	var has_key := doc != null and _selected_index >= 0 and _selected_data_id == doc.selected_id
	_compact_delete_button.disabled = not has_key


func _on_compact_mode_toggled(enabled: bool) -> void:
	if _sync_flags:
		return
	set_mode("graph" if enabled else "dope")
	if _mode == "graph" and doc != null and doc.selected_id == "":
		notice.emit("Select an object to edit its speed graph.")


func _on_compact_loop_toggled(enabled: bool) -> void:
	if _sync_flags or doc == null:
		return
	doc.set_loop(enabled)
	_loop_button.set_pressed_no_signal(enabled)
	_style_flag_button(_loop_button, enabled)
	_style_flag_button(_compact_loop_button, enabled)


func _on_compact_snap_toggled(enabled: bool) -> void:
	if _sync_flags or doc == null:
		return
	doc.set_snap(enabled)
	_snap_button.set_pressed_no_signal(enabled)
	_style_flag_button(_snap_button, enabled)
	_style_flag_button(_compact_snap_button, enabled)

func _build_sheet() -> void:
	_sheet_rule = Kit.vsep(Kit.BORDER_SOFT)
	add_child(_sheet_rule)
	_sheet = DopeSheet.new()
	_sheet.timeline = self
	_sheet.custom_minimum_size.y = 96
	_sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_sheet)


## Compact screens keep the transport and fold the sheet away, so the 3D view
## keeps its height until the user asks for the dope sheet.
func set_sheet_visible(open: bool) -> void:
	_sheet_open = open
	_sheet_rule.visible = open
	if _sheet != null:
		_sheet.visible = open
	if _fold_button != null:
		Kit.set_icon(_fold_button, "chevron-down" if open else "chevron-up")
		_fold_button.tooltip_text = "Fold the timeline" if open else "Open the timeline"
	_refresh_compact()


func sheet_visible() -> bool:
	return _sheet_open


## The editor reserves width for the center column; the sheet must not infer
## its own available width from a size that its own minimum has already forced.
func set_available_width(value: float) -> void:
	_available_width = value
	_refresh_compact()


## Touch mode grows every transport control to a 44 dp target. The same target
## is kept in Studio and Desktop: a phone can host any of the three modes and a
## transport is the most-used control in the app.
func set_chrome_mode(mode: String) -> void:
	_chrome_mode = mode if mode in ["compact", "studio", "desktop"] else "studio"
	var target := 44
	var icon := 20 if _chrome_mode == "compact" else 18
	for button in _transport_buttons:
		if button == null or not is_instance_valid(button):
			continue
		button.custom_minimum_size = Vector2(target, target)
		button.add_theme_constant_override("icon_max_width", icon)
	if _play_button != null:
		_play_button.custom_minimum_size = Vector2(target, target)
		_play_button.add_theme_constant_override("icon_max_width", icon)
	if _mode_button != null:
		_mode_button.custom_minimum_size = Vector2(target, target)
	for button in [_auto_button, _ease_button]:
		if button != null:
			button.custom_minimum_size = Vector2(target, target)
	_refresh_compact()

func _refresh_compact() -> void:
	if _start_button == null:
		return
	var touch := _chrome_mode == "compact"
	# A Studio landscape split by the dock can leave the sheet narrower than a
	# phone. The same overflow header keeps graph, loop, snap, delete and fold
	# reachable instead of silently dropping them from the transport. The
	# threshold is measured against the transport's real 44 dp controls, not
	# the old 28 dp icons. Prefer the width the editor reserved: this Control's
	# own size may already be widened by the transport minimum.
	var measured := size.x
	if _available_width > 0.0:
		measured = minf(measured, _available_width)
	var narrow := measured < 640.0
	var narrow_chrome := touch or narrow
	var show_header := _sheet_open and narrow_chrome
	_start_button.visible = not narrow_chrome
	_end_button.visible = not narrow_chrome
	_snap_button.visible = not narrow_chrome
	_mode_button.visible = not narrow_chrome
	_loop_button.visible = not narrow_chrome
	_delete_button.visible = not narrow_chrome
	if _fold_button != null:
		_fold_button.visible = not touch
	_frame_label.visible = not narrow_chrome and size.x >= 420.0
	_time_box.custom_minimum_size.x = 58 if touch else 76
	_transport_style.content_margin_left = 4 if touch else 6
	_transport_style.content_margin_right = 4 if touch else 6
	if _compact_header != null:
		_compact_header.visible = show_header
	if _ease_button != null:
		_ease_button.visible = not narrow_chrome and _mode == "graph"
	_sync_compact_header()
	if _sheet != null:
		_sheet.queue_redraw()

func set_mode(mode: String) -> void:
	_mode = "graph" if mode == "graph" else "dope"
	if _mode_button != null:
		_sync_flags = true
		_mode_button.set_pressed_no_signal(_mode == "graph")
		_sync_flags = false
		_style_flag_button(_mode_button, _mode == "graph")
	_refresh_compact()

func _on_mode_toggled(enabled: bool) -> void:
	if _sync_flags:
		return
	set_mode("graph" if enabled else "dope")
	if _mode == "graph" and doc != null and doc.selected_id == "":
		notice.emit("Select an object to edit its speed graph.")

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
	_sync_compact_header()

func _style_flag_button(button: Button, active: bool) -> void:
	if active:
		button.add_theme_color_override("icon_normal_color", Kit.FOCUS_BRIGHT)
		button.add_theme_color_override("icon_pressed_color", Kit.FOCUS_BRIGHT)
		button.add_theme_stylebox_override("normal", Kit.flat_style(Kit.FOCUS_DARK, 0, Color(0, 0, 0, 0), 0))
	else:
		button.add_theme_color_override("icon_normal_color", Kit.TEXT_MUTED)
		button.add_theme_stylebox_override("normal", Kit.flat_style(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0))

func _refresh_transport(time: float, playing: bool) -> void:
	if doc == null:
		return
	_time_label.text = doc.format_timecode(time)
	_frame_label.text = "F %d · %dfps" % [doc.time_to_frame(time), doc.fps]
	_play_button.icon = Kit.icon_texture("pause" if playing else "play")
	_play_button.tooltip_text = "Pause" if playing else "Play"
	var has_key := _selected_index >= 0 and _selected_data_id == doc.selected_id
	_delete_button.disabled = not has_key
	if _compact_delete_button != null:
		_compact_delete_button.disabled = not has_key

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

func _on_transform_changed(_id: String) -> void:
	# The sheet only plots keys and the playhead; live values do not redraw it.
	pass

func _on_keyframes_changed(_id: String) -> void:
	_selected_index = -1
	_refresh_transport(doc.current_time, doc.is_playing)
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
	_sync_compact_header()

func _on_auto_toggled(enabled: bool) -> void:
	if _sync_flags or doc == null:
		return
	doc.set_autokey(enabled)

func _on_snap_toggled(enabled: bool) -> void:
	if _sync_flags or doc == null:
		return
	doc.set_snap(enabled)
	_style_flag_button(_snap_button, enabled)
	_sync_compact_header()

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
	canvas.draw_string(Kit.font_for(600), Vector2(12, 15), channel_header, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.TYPE_CAPTION, Kit.TEXT_DIM)

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
			canvas.draw_string(Kit.font_mono, Vector2(x + 3, 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.TYPE_RULER, Kit.TEXT_MUTED)

	if _mode == "graph":
		_draw_graph(canvas, w, h)
		return

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
		canvas.draw_string(Kit.font_for(500), Vector2(20, center_y + 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.TYPE_CAPTION, Kit.TEXT if channel == _selected_channel else Kit.TEXT_MUTED)
		# Channel identity lives in the label. Coloured dots would introduce a
		# second semantic palette into an otherwise luminance-only workbench.
		var dot_color: Color = [Kit.TEXT_MUTED, Kit.TEXT_DIM, Kit.BORDER][ci]
		canvas.draw_circle(Vector2(12, center_y), 2.4, dot_color)

		var keys: Array = doc.get_channel_keys(doc.selected_id, channel) if doc.selected_id != "" else []
		if keys.is_empty():
			continue
		var count_text := str(keys.size())
		var count_size := Kit.font_mono.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.TYPE_MONO)
		canvas.draw_string(Kit.font_mono, Vector2(_label_width - 10 - count_size.x, center_y + 3), count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.TYPE_MONO, Kit.TEXT_DIM)
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
		canvas.draw_string(Kit.font_for(400), Vector2(_label_width + 20, _ruler_h + 32), "Select an object to view its animation channels.", HORIZONTAL_ALIGNMENT_LEFT, w - _label_width - 24, Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	else:
		var rows_bottom := row_top + float(channels.size()) * _row_h
		if h > rows_bottom + 12.0:
			canvas.draw_string(Kit.font_for(400), Vector2(_label_width + 8, rows_bottom + 14), "Drag diamonds to retime · tap the ruler to scrub", HORIZONTAL_ALIGNMENT_LEFT, w - _label_width - 16, Kit.TYPE_CAPTION, Kit.TEXT_DIM)

# -------------------------------------------------------------------------
# Speed graph
# -------------------------------------------------------------------------

func _draw_graph(canvas: Control, w: float, h: float) -> void:
	_ease_hits.clear()
	var channels: Array = doc.CHANNELS
	var row_top := _ruler_h
	for ci in range(channels.size()):
		var channel := str(channels[ci])
		var top := row_top + float(ci) * _row_h
		var center_y := top + _row_h * 0.5
		if channel == _selected_channel:
			canvas.draw_rect(Rect2(0, top, _label_width, _row_h), Kit.SURFACE_2)
			canvas.draw_rect(Rect2(0, top, 2, _row_h), Kit.ACCENT)
		canvas.draw_line(Vector2(0, top + _row_h), Vector2(_label_width, top + _row_h), Kit.BORDER_SOFT, 1.0)
		var label := str(doc.CHANNEL_LABELS.get(channel, channel))
		canvas.draw_string(Kit.font_for(500), Vector2(20, center_y + 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.TYPE_CAPTION, Kit.TEXT if channel == _selected_channel else Kit.TEXT_MUTED)
		var dot_color: Color = [Kit.TEXT_MUTED, Kit.TEXT_DIM, Kit.BORDER][ci]
		canvas.draw_circle(Vector2(12, center_y), 2.4, dot_color)
	_graph_top = _ruler_h + 6.0
	_graph_baseline = h - 26.0
	if _graph_baseline < _graph_top + 24.0:
		_graph_baseline = _graph_top + 24.0
	var graph_h := maxf(8.0, _graph_baseline - _graph_top)
	canvas.draw_line(Vector2(_grid_left, _graph_baseline), Vector2(w - 8.0, _graph_baseline), Kit.BORDER, 1.0)
	for frac in [0.25, 0.5, 0.75]:
		var gy := _graph_baseline - graph_h * float(frac)
		canvas.draw_line(Vector2(_grid_left, gy), Vector2(w - 8.0, gy), Kit.BORDER_SOFT * Color(1, 1, 1, 0.5), 1.0)
	canvas.draw_rect(Rect2(_grid_left, _graph_baseline + 1.0, maxf(0.0, w - _grid_left - 8.0), maxf(0.0, h - _graph_baseline - 1.0)), Kit.SURFACE_2)

	if doc.selected_id == "":
		canvas.draw_string(Kit.font_for(400), Vector2(_grid_left + 14.0, _graph_top + 22.0), "Select an object to shape its speed.", HORIZONTAL_ALIGNMENT_LEFT, _grid_width - 20.0, Kit.TYPE_CAPTION, Kit.TEXT_DIM)
		_draw_graph_playhead(canvas, h)
		return

	var keys: Array = doc.get_channel_keys(doc.selected_id, _selected_channel)
	if keys.is_empty():
		canvas.draw_string(Kit.font_for(400), Vector2(_grid_left + 14.0, _graph_top + 22.0), "No keys on this channel. Insert a key at the playhead.", HORIZONTAL_ALIGNMENT_LEFT, _grid_width - 20.0, Kit.TYPE_CAPTION, Kit.TEXT_DIM)
		_draw_graph_playhead(canvas, h)
		return

	var count := clampi(int(_grid_width / 2.5), 32, 180)
	var speeds := PackedFloat32Array()
	speeds.resize(count)
	var max_speed := 0.0001
	for i in range(count):
		var t := doc.duration * float(i) / float(maxi(1, count - 1))
		var speed := _channel_speed(doc.selected_id, _selected_channel, t)
		speeds[i] = speed
		max_speed = maxf(max_speed, speed)
	_graph_max_speed = max_speed
	var scale_speed := max_speed * 1.12

	var points := PackedVector2Array()
	for i in range(count):
		var x := _grid_left + float(i) / float(maxi(1, count - 1)) * _grid_width
		var y := _graph_baseline - (speeds[i] / scale_speed) * graph_h
		points.append(Vector2(x, y))
	var fill := PackedVector2Array(points)
	fill.append(Vector2(points[points.size() - 1].x, _graph_baseline))
	fill.append(Vector2(points[0].x, _graph_baseline))
	canvas.draw_colored_polygon(fill, Kit.ACCENT * Color(1, 1, 1, 0.10))
	canvas.draw_polyline(points, Kit.ACCENT_BRIGHT * Color(1, 1, 1, 0.9), 1.4, true)

	for key in keys:
		if float(key["time"]) > doc.duration + 0.001:
			continue
		var x := _time_to_x(float(key["time"]), canvas)
		var y := _graph_baseline + 12.0
		var selected := _selected_data_id == doc.selected_id and _selected_index == int(key["index"])
		var r := 5.5 if selected else 4.0
		var color := Kit.ACCENT_BRIGHT if selected else Kit.ACCENT
		var diamond := PackedVector2Array([
			Vector2(x, y - r), Vector2(x + r, y),
			Vector2(x, y + r), Vector2(x - r, y),
		])
		canvas.draw_colored_polygon(diamond, color)
		if selected:
			canvas.draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color(1, 1, 1, 0.9), 1.0, true)
		_key_hits.append({"channel": _selected_channel, "index": int(key["index"]), "pos": Vector2(x, y)})

	for i in range(keys.size() - 1):
		var key_index := int(keys[i]["index"])
		var t0 := float(keys[i]["time"])
		var t1 := float(keys[i + 1]["time"])
		var mid := (t0 + t1) * 0.5
		var x := _time_to_x(mid, canvas)
		if x - _grid_left < 12.0 or (_grid_left + _grid_width) - x < 12.0:
			continue
		var speed := _channel_speed(doc.selected_id, _selected_channel, mid)
		var y := _graph_baseline - (speed / scale_speed) * graph_h
		var transition := doc.get_key_transition(doc.selected_id, _selected_channel, key_index)
		var selected_seg := _selected_index == key_index and _selected_data_id == doc.selected_id
		canvas.draw_line(Vector2(x, _graph_baseline), Vector2(x, y), Kit.BORDER * Color(1, 1, 1, 0.8), 1.0)
		canvas.draw_circle(Vector2(x, y), 6.0, Kit.SURFACE)
		canvas.draw_arc(Vector2(x, y), 5.0, 0.0, TAU, 18, Kit.ACCENT_BRIGHT if selected_seg else Kit.ACCENT, 1.4, true)
		_ease_hits.append({"index": key_index, "pos": Vector2(x, y), "transition": transition})
		if selected_seg:
			var readout := "EASE %.2f× · %s" % [transition, _ease_name(transition)]
			var text_size := Kit.font_mono.get_string_size(readout, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.TYPE_MONO)
			var text_pos := Vector2(minf(w - text_size.x - 12.0, x + 8.0), maxf(_graph_top + 8.0, y - 8.0))
			canvas.draw_rect(Rect2(text_pos - Vector2(4, 8), text_size + Vector2(8, 4)), Kit.SURFACE * Color(1, 1, 1, 0.92))
			canvas.draw_string(Kit.font_mono, text_pos, readout, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.TYPE_MONO, Kit.TEXT)
	_draw_graph_playhead(canvas, h)

func _draw_graph_playhead(canvas: Control, h: float) -> void:
	var play_x := _time_to_x(doc.current_time, canvas)
	canvas.draw_line(Vector2(play_x, 0), Vector2(play_x, h), Kit.ACCENT * Color(1, 1, 1, 0.75), 1.2)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(play_x - 4, 0), Vector2(play_x + 4, 0), Vector2(play_x, 5)]), Kit.ACCENT)

func _ease_name(transition: float) -> String:
	if transition <= 0.01:
		return "HOLD"
	if transition < 0.95:
		return "EASE OUT"
	if transition > 1.05:
		return "EASE IN"
	return "LINEAR"

func _channel_speed(id: String, channel: String, time: float) -> float:
	## Magnitude of the channel's velocity at a time, sampled from the real
	## animation resource. This is what the graph draws, so easing edits are
	## visible exactly as the AnimationPlayer will evaluate them.
	if doc == null or id == "":
		return 0.0
	var dt := 1.0 / 240.0
	var a_time := maxf(0.0, time - dt)
	var b_time := minf(doc.duration, time + dt)
	var span := b_time - a_time
	if span <= 0.0001:
		return 0.0
	var a: Variant = doc.sample_channel(id, channel, a_time)
	var b: Variant = doc.sample_channel(id, channel, b_time)
	if a == null or b == null:
		return 0.0
	if channel == "rotation":
		var qa := a as Quaternion
		var qb := b as Quaternion
		return qa.angle_to(qb) / span
	var va := a as Vector3
	var vb := b as Vector3
	return (vb - va).length() / span

func _ease_at(pos: Vector2) -> int:
	var best := -1
	var best_dist := 15.0
	for i in range(_ease_hits.size()):
		var hit: Dictionary = _ease_hits[i]
		var d: float = (hit["pos"] as Vector2).distance_to(pos)
		if d < best_dist:
			best_dist = d
			best = i
	return best

func _open_ease_menu() -> void:
	if doc == null or _selected_index < 0 or _selected_data_id != doc.selected_id:
		notice.emit("Select a key in the speed graph first.")
		return
	var menu := PopupMenu.new()
	menu.add_item("Linear", 0)
	menu.add_item("Ease out (fast start)", 1)
	menu.add_item("Ease in (slow start)", 2)
	menu.add_item("Hold until next key", 3)
	menu.add_item("Reset to linear", 4)
	menu.id_pressed.connect(func(id: int) -> void:
		_apply_ease_preset(id)
		menu.queue_free()
	)
	menu.popup_hide.connect(menu.queue_free)
	_ease_button.add_child(menu)
	menu.popup_on_parent(Rect2(0.0, _ease_button.size.y, 1.0, 1.0))

func _apply_ease_preset(id: int) -> void:
	if doc == null or _selected_index < 0 or _selected_data_id != doc.selected_id:
		return
	var value := 1.0
	match id:
		1: value = 0.5
		2: value = 2.0
		3: value = 0.0
	doc.begin_edit("Ease key")
	doc.set_key_transition(doc.selected_id, _selected_channel, _selected_index, value)
	doc.end_edit()
	notice.emit("Ease set to " + _ease_name(value).to_lower() + ".")
	if _sheet != null:
		_sheet.queue_redraw()

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
	elif event is InputEventMouseMotion and (_scrubbing or _dragging_key or _dragging_ease):
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
	return _scrubbing or _dragging_key or _dragging_ease

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
	if _mode == "graph":
		var ease_hit := _ease_at(pos)
		if ease_hit >= 0:
			var ease_data: Dictionary = _ease_hits[ease_hit]
			_selected_index = int(ease_data["index"])
			_selected_data_id = doc.selected_id
			_dragging_ease = true
			_ease_start_y = pos.y
			_ease_start_value = float(ease_data["transition"])
			doc.begin_edit("Ease key")
			_refresh_transport(doc.current_time, doc.is_playing)
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
	if _mode == "graph":
		_selected_index = -1
		_refresh_transport(doc.current_time, doc.is_playing)
		_scrubbing = true
		if doc.is_playing:
			doc.pause()
		doc.seek(_x_to_time(pos.x, canvas))
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
	if _dragging_ease and _selected_index >= 0:
		var base := _ease_start_value if _ease_start_value > 0.01 else 0.25
		var value := base * pow(2.0, (_ease_start_y - pos.y) / 42.0)
		if value < 0.08:
			value = 0.0
		doc.set_key_transition(doc.selected_id, _selected_channel, _selected_index, clampf(value, 0.0, 4.0))
		_refresh_transport(doc.current_time, doc.is_playing)
		canvas.queue_redraw()
	elif _dragging_key and _selected_index >= 0:
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
	if _dragging_ease:
		_dragging_ease = false
		doc.end_edit()
		if _selected_index >= 0 and doc.selected_id != "":
			var value := doc.get_key_transition(doc.selected_id, _selected_channel, _selected_index)
			notice.emit("Ease %.2f× · %s" % [value, _ease_name(value).to_lower()])
	elif _dragging_key:
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
