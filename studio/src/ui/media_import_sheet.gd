extends VBoxContainer
## Media import sheet: audio tracks and video-reference proxies.
##
## Audio accepts WAV/OGG/MP3 and copies the file into `<project>/audio/`.
## Video proxies extract JPEG frames on Android through the Java backend; on
## other platforms MP4/MOV import is refused with the exact reason and only OGV
## direct playback remains. The sheet never pretends a proxy was created.

signal audio_import_requested(uri: String)
signal video_import_requested(uri: String, options: Dictionary)
signal cancel_requested
signal close_requested

const AndroidVideo = preload("res://src/core/android_video.gd")
const AudioLibrary = preload("res://src/core/audio_library.gd")
const VideoReference = preload("res://src/core/video_reference.gd")

const PROXY_FPS := VideoReference.PROXY_FPS_PRESETS
const MAX_WIDTHS := VideoReference.PROXY_WIDTH_PRESETS
const PROXY_LIMIT_BYTES := 2 * 1024 * 1024 * 1024

var _doc = null
var _audio_path := ""
var _video_path := ""
var _proxy_fps := 12
var _max_width := 1280
var _video_button: Button
var _video_field: LineEdit
var _progress_label: Label
var _status_label: Label


func setup(doc) -> void:
	_doc = doc
	_seed_proxy_defaults()
	_rebuild()


func _seed_proxy_defaults() -> void:
	# Feed the sheet's selections from the persisted prefs, snapped to the
	# presets this sheet offers. The preset list is shared with the media
	# system and includes 6 fps, so a 6 fps preference is never coerced.
	var fps := int(Prefs.get_value("media.proxy_fps", 12))
	if not (fps in PROXY_FPS):
		var best: int = int(PROXY_FPS[0])
		for fps_option in PROXY_FPS:
			if absi(int(fps_option) - fps) < absi(best - fps):
				best = int(fps_option)
		fps = best
	_proxy_fps = fps
	var width := int(Prefs.get_value("media.proxy_max_width", 1280))
	if not (width in MAX_WIDTHS):
		var best_width: int = int(MAX_WIDTHS[0])
		for width_option in MAX_WIDTHS:
			if absi(int(width_option) - width) < absi(best_width - width):
				best_width = int(width_option)
		width = best_width
	_max_width = width


func proxy_fps_options() -> Array:
	return PROXY_FPS.duplicate()


func max_width_options() -> Array:
	return MAX_WIDTHS.duplicate()


func proxy_limit_text() -> String:
	return "Proxy folders are limited to 2 GB; an oversized proxy is deleted and the import fails."


func unsupported_reason(kind: String) -> String:
	match kind:
		"mp4", "m4v", "mov":
			return AndroidVideo.REASON
		"ogv":
			return "OGV plays directly through VideoStreamPlayer on every platform; no frame proxy is extracted."
	return ""


func video_import_enabled() -> bool:
	return _video_button != null and not _video_button.disabled


func set_video_path(path: String) -> void:
	_video_path = path
	if _video_field != null:
		_video_field.text = path
	_sync_video_button()


func can_import_video(kind: String) -> bool:
	if kind == "ogv":
		return true
	if kind in ["mp4", "m4v", "mov"]:
		return AndroidVideo.new().available()
	return false


func set_progress(kind: String, done: int = 0, total: int = 0) -> void:
	if _progress_label != null:
		match kind:
			"frames":
				_progress_label.text = "Extracting frame %d/%d" % [done, total]
			"cancelled":
				_progress_label.text = "Extraction cancelled"
			"error":
				_progress_label.text = "Extraction failed"
			"done":
				_progress_label.text = "Extraction complete"
			_:
				_progress_label.text = "Ready"
	if _status_label != null:
		_status_label.text = unsupported_reason(_video_extension())


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_progress_label = null
	_status_label = null
	_video_button = null
	_video_field = null
	add_theme_constant_override("separation", 8)
	add_child(Kit.section_label("Import media"))

	add_child(Kit.section_label("Audio · WAV, OGG, MP3"))
	var audio_row := HBoxContainer.new()
	audio_row.custom_minimum_size.y = 44
	audio_row.add_theme_constant_override("separation", 8)
	add_child(audio_row)
	var audio_field := Kit.line_edit("Audio file path")
	audio_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	audio_field.text_changed.connect(func(text: String) -> void: _audio_path = text)
	audio_row.add_child(audio_field)
	var audio_button := Kit.text_button("Import audio", "plus", true)
	audio_button.pressed.connect(func() -> void:
		if not _audio_path.is_empty():
			audio_import_requested.emit(_audio_path)
	)
	audio_row.add_child(audio_button)
	add_child(Kit.label(
		"Copied into the project audio folder. OGG and MP3 play but have no waveform.",
		Kit.TYPE_CAPTION,
		Kit.TEXT_DIM
	))

	add_child(Kit.section_label("Video reference · frame proxy"))
	var video_row := HBoxContainer.new()
	video_row.custom_minimum_size.y = 44
	video_row.add_theme_constant_override("separation", 8)
	add_child(video_row)
	_video_field = Kit.line_edit("Video file path")
	_video_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_video_field.text_changed.connect(func(text: String) -> void:
		_video_path = text
		_sync_video_button()
	)
	video_row.add_child(_video_field)
	_video_button = Kit.text_button("Import video", "film", true)
	_video_button.pressed.connect(func() -> void:
		if not _video_path.is_empty():
			video_import_requested.emit(_video_path, {"fps": _proxy_fps, "max_width": _max_width})
	)
	video_row.add_child(_video_button)
	_sync_video_button()

	add_child(_labeled_option("Proxy fps", _proxy_fps_option()))
	add_child(_labeled_option("Max width", _max_width_option()))

	_status_label = Kit.label(unsupported_reason(_video_extension()), Kit.TYPE_CAPTION, Kit.TEXT_MUTED)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)
	add_child(Kit.label(proxy_limit_text(), Kit.TYPE_CAPTION, Kit.TEXT_DIM))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	add_child(actions)
	var cancel := Kit.text_button("Cancel", "", false, true)
	cancel.pressed.connect(func() -> void: cancel_requested.emit())
	actions.add_child(cancel)
	_progress_label = Kit.mono_label("Ready", Kit.TYPE_MONO, Kit.TEXT_MUTED)
	actions.add_child(_progress_label)


func _proxy_fps_option() -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size.y = 44
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for fps in PROXY_FPS:
		option.add_item("%d fps" % fps)
		if fps == _proxy_fps:
			option.selected = option.item_count - 1
	option.item_selected.connect(func(index: int) -> void:
		_proxy_fps = int(PROXY_FPS[index])
		Prefs.set_value("media.proxy_fps", _proxy_fps)
	)
	return option


func _max_width_option() -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size.y = 44
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for width in MAX_WIDTHS:
		option.add_item("%d px" % width)
		if width == _max_width:
			option.selected = option.item_count - 1
	option.item_selected.connect(func(index: int) -> void:
		_max_width = int(MAX_WIDTHS[index])
		Prefs.set_value("media.proxy_max_width", _max_width)
	)
	return option


func _labeled_option(label_text: String, option: OptionButton) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation", 8)
	var label := Kit.label(label_text, Kit.TYPE_BODY, Kit.TEXT_MUTED)
	label.custom_minimum_size.x = 96
	row.add_child(label)
	row.add_child(option)
	return row


func _sync_video_button() -> void:
	if _video_button == null:
		return
	var kind := _video_extension()
	var blocked := kind in ["mp4", "m4v", "mov"] and not AndroidVideo.new().available()
	_video_button.disabled = blocked
	_video_button.tooltip_text = unsupported_reason(kind) if blocked else ""
	if _status_label != null:
		_status_label.text = unsupported_reason(kind)


func _video_extension() -> String:
	return _video_path.get_extension().to_lower()
