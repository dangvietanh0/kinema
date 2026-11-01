extends VBoxContainer
## Media lanes under the dope sheet.
##
## Audio rows are 48 dp because they carry a mute control; video-reference rows
## are 40 dp and select on tap. Both lanes are collapsible, show honest empty
## states, and never invent a waveform or a frame.

signal audio_selected(id: String)
signal video_selected(id: String)
signal video_dragged(id: String, patch: Dictionary)
signal add_audio_requested
signal add_video_requested
signal collapsed_changed(collapsed: bool)

const AUDIO_ROW_HEIGHT := 48.0
const VIDEO_ROW_HEIGHT := 40.0
const HEADER_HEIGHT := 44.0
const PIXELS_PER_SECOND := 80.0

var _doc = null
var _body: VBoxContainer
var _body_scroll: ScrollContainer
var _empty_audio: Label
var _empty_video: Label
var _audio_rows: Array[Control] = []
var _video_rows: Array[Control] = []
var _collapsed := false
var _connected := false
var _dragging_id := ""
var _drag_origin_x := 0.0
var _drag_origin_start := 0.0
## Height cap the timeline overlay hands the section. -1 means "no cap":
## the body takes its natural height like before.
var _fit_height := -1.0


func setup(doc) -> void:
	_doc = doc
	if _doc != null and _doc.has_signal("media_changed") and not _connected:
		_doc.media_changed.connect(_on_media_changed)
		_connected = true
	refresh()


func audio_row_height() -> float:
	return AUDIO_ROW_HEIGHT


func video_row_height() -> float:
	return VIDEO_ROW_HEIGHT


func is_collapsed() -> bool:
	return _collapsed


func set_collapsed(collapsed: bool) -> void:
	var changed := _collapsed != collapsed
	_collapsed = collapsed
	if _body != null:
		_body.visible = not _collapsed
	_sync_capacity()
	if changed:
		collapsed_changed.emit(_collapsed)


## Caps the section height to `height` dp (header included). The body then
## scrolls inside the cap, so a tight overlay budget never hides the header
## and its collapse control. Pass -1 to restore the natural height.
func fit_height(height: float) -> void:
	_fit_height = height
	_sync_capacity()


func _sync_capacity() -> void:
	if _body_scroll == null or not is_instance_valid(_body_scroll):
		return
	var want := 0.0
	if _body != null and not _collapsed:
		want = _body.get_combined_minimum_size().y
	if _fit_height < 0.0:
		_body_scroll.custom_minimum_size.y = want
	else:
		_body_scroll.custom_minimum_size.y = clampf(_fit_height - HEADER_HEIGHT, 0.0, want)


func audio_row_count() -> int:
	return _audio_rows.size()


func video_row_count() -> int:
	return _video_rows.size()


func empty_audio_text() -> String:
	return _empty_audio.text if _empty_audio != null else ""


func empty_video_text() -> String:
	return _empty_video.text if _empty_video != null else ""


func refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_audio_rows.clear()
	_video_rows.clear()
	add_theme_constant_override("separation", 0)
	_build_header()
	# The body lives in a scroll shell: when the overlay budget caps the
	# section, the header stays put and the rows scroll instead of the whole
	# media section vanishing.
	_body_scroll = ScrollContainer.new()
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_body_scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_scroll.add_child(_body)
	_build_audio()
	_build_video()
	_body.visible = not _collapsed
	_sync_capacity()


func _build_header() -> void:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = HEADER_HEIGHT
	header.add_theme_constant_override("separation", 4)
	add_child(header)
	var collapse := Kit.icon_button("chevron-down" if not _collapsed else "chevron-right", "Collapse media", 44)
	collapse.pressed.connect(func() -> void: set_collapsed(not _collapsed))
	header.add_child(collapse)
	var title := Kit.label("Media", Kit.TYPE_EMPHASIS, Kit.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var add_audio := Kit.icon_button("plus", "Add audio track", 44)
	add_audio.pressed.connect(func() -> void: add_audio_requested.emit())
	header.add_child(add_audio)
	var add_video := Kit.icon_button("film", "Add video reference", 44)
	add_video.pressed.connect(func() -> void: add_video_requested.emit())
	header.add_child(add_video)


func _build_audio() -> void:
	var section := Kit.section_label("Audio · follows sequence")
	_body.add_child(section)
	var tracks: Array = _doc.media_system.audio_tracks() if _doc != null and _doc.media_system != null else []
	_empty_audio = Kit.label("No audio tracks. Add a WAV, OGG or MP3; audio follows the sequence.", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	_empty_audio.visible = tracks.is_empty()
	_body.add_child(_empty_audio)
	for raw in tracks:
		var track: Dictionary = raw
		var row := PanelContainer.new()
		row.custom_minimum_size.y = AUDIO_ROW_HEIGHT
		row.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT))
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		row.add_child(box)
		var name := Kit.label(str(track.get("name", "Audio")), Kit.TYPE_BODY, Kit.TEXT)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(name)
		var time := Kit.mono_label("%.2f – %.2f" % [float(track.get("start", 0.0)), float(track.get("start", 0.0)) + float(track.get("trim_end", 0.0)) - float(track.get("trim_start", 0.0))], Kit.TYPE_MONO, Kit.TEXT_MUTED)
		box.add_child(time)
		var id := str(track.get("id", ""))
		var mute := Kit.text_toggle("Mute")
		mute.button_pressed = bool(track.get("muted", false))
		mute.toggled.connect(func(on: bool) -> void:
			_doc.media_system.update_audio_track(id, {"muted": on})
		)
		box.add_child(mute)
		row.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_select_audio(id, row)
		)
		_body.add_child(row)
		_audio_rows.append(row)


func _build_video() -> void:
	var section := Kit.section_label("Video reference · frame proxy")
	_body.add_child(section)
	var refs: Array = _doc.media_system.video_references() if _doc != null and _doc.media_system != null else []
	_empty_video = Kit.label("No video reference. Import a video to scrub a frame proxy.", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	_empty_video.visible = refs.is_empty()
	_body.add_child(_empty_video)
	for raw in refs:
		var ref: Dictionary = raw
		var row := PanelContainer.new()
		row.custom_minimum_size.y = VIDEO_ROW_HEIGHT
		row.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_2, 0, Kit.BORDER_SOFT))
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		row.add_child(box)
		var name := Kit.label(str(ref.get("name", "Reference")), Kit.TYPE_CAPTION, Kit.TEXT)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(name)
		var info := Kit.mono_label("%d fps · %d%%" % [int(ref.get("fps", 12)), int(round(float(ref.get("opacity", 0.5)) * 100.0))], Kit.TYPE_RULER, Kit.TEXT_MUTED)
		box.add_child(info)
		var id := str(ref.get("id", ""))
		row.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					_select_video(id, row)
					_dragging_id = id
					_drag_origin_x = event.position.x
					_drag_origin_start = float(ref.get("start", 0.0))
				else:
					_dragging_id = ""
			elif event is InputEventMouseMotion and _dragging_id == id:
				var delta: float = (event.position.x - _drag_origin_x) / PIXELS_PER_SECOND
				_apply_video_drag(id, delta, _drag_origin_start)
		)
		_body.add_child(row)
		_video_rows.append(row)


func _select_audio(id: String, row: Control) -> void:
	for child in _audio_rows:
		child.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT))
	row.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_2, 0, Kit.FOCUS))
	audio_selected.emit(id)


func _select_video(id: String, row: Control) -> void:
	for child in _video_rows:
		child.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_2, 0, Kit.BORDER_SOFT))
	row.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_3, 0, Kit.FOCUS))
	video_selected.emit(id)


## Public drag hook used by the timeline and the tests. `delta_seconds` is the
## horizontal distance converted to sequence seconds; start is clamped at zero.
func drag_video(id: String, delta_seconds: float) -> void:
	var ref: Dictionary = _doc.media_system.video_reference(id) if _doc != null else {}
	if ref.is_empty():
		return
	_dragging_id = id
	_apply_video_drag(id, delta_seconds, float(ref.get("start", 0.0)))
	_dragging_id = ""


func _apply_video_drag(id: String, delta_seconds: float, base_start: float) -> void:
	var start := maxf(0.0, base_start + delta_seconds)
	var patch := {"start": start}
	_doc.media_system.update_video_reference(id, patch)
	video_dragged.emit(id, patch)


func _on_media_changed() -> void:
	if _dragging_id != "":
		return
	refresh()
