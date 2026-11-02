extends VBoxContainer
## Media export sheet: PNG sequence, GIF, Android MP4 and a scene-camera track.
##
## The sheet never fakes a format. MP4 is disabled with the exact backend
## reason on non-Android, GIF disables 60 fps because a centisecond delay cannot
## represent it, and the camera track is only offered when the scene has a real
## camera for CameraExport to sample.

signal export_requested(options: Dictionary)
signal cancel_requested
signal close_requested

const AndroidVideo = preload("res://src/core/android_video.gd")
const CameraExport = preload("res://src/core/camera_export.gd")
const GifEncoder = preload("res://src/core/gif_encoder.gd")

const FORMATS := ["png", "gif", "mp4", "camera"]
const CAMERA_REASON := "Add a scene camera to export a camera track."
const REASON_4K := "This device's encoder does not advertise 4K H.264."
const REASON_1440P := "This device's encoder does not advertise 1440p H.264."
const RESOLUTIONS := [
	{"label": "1280 × 720", "size": Vector2i(1280, 720)},
	{"label": "1920 × 1080", "size": Vector2i(1920, 1080)},
	{"label": "2560 × 1440", "size": Vector2i(2560, 1440)},
	{"label": "3840 × 2160", "size": Vector2i(3840, 2160)},
]
const FPS_OPTIONS := [12, 24, 30, 60]
const GIF_FPS := [12, 24, 30]
const BITRATE_MBPS := [4, 8, 12, 20, 30, 40, 60, 80]
const GIF_60_REASON := GifEncoder.FPS_60_REASON
## MP4 quality presets. `size`/`fps`/`bitrate`/`msaa`/`audio_bitrate` are the
## real encoder inputs: MSAA uses the Godot viewport index (2× = 1, 4× = 2).
const QUALITY_IDS := ["standard", "high", "master"]
const QUALITY_PRESETS := {
	"standard": {
		"label": "Standard", "size": Vector2i(1920, 1080), "fps": 30,
		"bitrate": 16000000, "msaa": 1, "audio_bitrate": 192000,
	},
	"high": {
		"label": "High", "size": Vector2i(2560, 1440), "fps": 60,
		"bitrate": 40000000, "msaa": 2, "audio_bitrate": 256000,
	},
	"master": {
		"label": "Master", "size": Vector2i(3840, 2160), "fps": 60,
		"bitrate": 80000000, "msaa": 2, "audio_bitrate": 256000,
	},
}
const CUSTOM_QUALITY := "custom"

var _doc = null
var _view = null
var _format := "png"
var _fps := 24
var _size := Vector2i(1920, 1080)
var _bitrate := 12
var _quality := "standard"
var _quality_chosen := false
var _msaa := 1
var _audio_bitrate := 192000
var _capabilities: Dictionary = {}
var _capabilities_loaded := false
var _quality_buttons: Dictionary = {}
var _quality_reason_label: Label
var _estimate_label: Label
var _camera_id := ""
var _camera_ids: Array[String] = []
var _include_audio := true
var _start := 0.0
var _end := 4.0
var _output_path_value := ""
var _gif_width := 640
var _gif_reason_label: Label
var _progress_label: Label
var _status_label: Label
var _result_label: Label
var _export_button: Button
var _cancel_button: Button


func setup(doc, view = null) -> void:
	_doc = doc
	_view = view
	_load_capabilities()
	_sync_cameras()
	if _format == "camera" and not camera_available():
		_format = "png"
	if _doc != null and _doc.has_method("sequence_duration"):
		_end = maxf(0.04, float(_doc.sequence_duration()))
	if _output_path_value == "":
		_output_path_value = _default_output_path()
	else:
		_output_path_value = _normalize_output_path(_output_path_value, _format)
	_rebuild()


func _load_capabilities() -> void:
	if _capabilities_loaded:
		return
	_capabilities_loaded = true
	_capabilities = AndroidVideo.new().capabilities()


## Inject the launcher's capability result. The editor probes the real
## backend; tests use this seam to prove gating without a MediaCodec device.
func set_capabilities(caps: Dictionary) -> void:
	_capabilities = caps.duplicate(true)
	_capabilities_loaded = true
	if _quality == "master" and not supports_4k():
		_apply_preset("high")
	elif _quality == "high" and not supports_1440p():
		_apply_preset("standard")
	_rebuild()


func capabilities() -> Dictionary:
	_load_capabilities()
	return _capabilities.duplicate(true)


func mp4_available() -> bool:
	_load_capabilities()
	return bool(_capabilities.get("supported", false))


func supports_4k() -> bool:
	_load_capabilities()
	return bool(_capabilities.get("supports_4k", false))


func supports_1440p() -> bool:
	_load_capabilities()
	return bool(_capabilities.get("supports_1440p", false))


func output_path() -> String:
	return _output_path()


func set_output_path(path: String) -> void:
	_output_path_value = path


func set_format(id: String) -> void:
	if not id in FORMATS:
		return
	if id == "camera" and not camera_available():
		return
	_format = id
	if _format == "gif" and _fps == 60:
		_fps = 30
		# GIF cannot represent 60 fps, so the quality preset no longer matches
		# the real values. Keep the sheet honest instead of mislabelling it.
		if _quality != CUSTOM_QUALITY:
			_mark_custom()
	if _format == "mp4" and not _quality_chosen:
		_apply_preset("standard")
	_output_path_value = _normalize_output_path(_output_path_value, _format)
	_rebuild()


# -------------------------------------------------------------------------
# MP4 quality presets
# -------------------------------------------------------------------------

func quality_presets() -> Dictionary:
	return QUALITY_PRESETS.duplicate(true)


func quality() -> String:
	return _quality


func quality_controls_visible() -> bool:
	return _format == "mp4" and mp4_available()


func quality_reason_visible() -> bool:
	return _quality_reason_label != null and _quality_reason_label.visible


func estimate_label_text() -> String:
	return _estimate_label.text if _estimate_label != null else ""


func quality_button(id: String) -> Button:
	var button: Variant = _quality_buttons.get(id)
	return button as Button


func quality_reason_text() -> String:
	if not mp4_available():
		return ""
	var parts: Array[String] = []
	if not supports_4k():
		parts.append(REASON_4K + " Master falls back to High.")
	if not supports_1440p():
		parts.append(REASON_1440P + " High falls back to Standard.")
	return " ".join(parts)


func resolution_disabled_reason(size: Vector2i) -> String:
	# Encoder gating only applies to the MP4 encode. PNG and GIF render on the
	# GPU, so their resolution list keeps every size.
	if _format != "mp4":
		return ""
	if size == Vector2i(3840, 2160) and not supports_4k():
		return REASON_4K
	if size == Vector2i(2560, 1440) and not supports_1440p():
		return REASON_1440P
	return ""


## Choosing a preset writes resolution, fps, bitrate and audio bitrate. A
## preset the device cannot encode falls back one step and says so.
func set_quality(id: String) -> void:
	if not id in QUALITY_IDS:
		return
	_quality_chosen = true
	if id == "master" and not supports_4k():
		_apply_preset("high")
	elif id == "high" and not supports_1440p():
		_apply_preset("standard")
	else:
		_apply_preset(id)
	_rebuild()


func set_resolution(size: Vector2i) -> void:
	_size = size
	_mark_custom()
	_rebuild()


func set_fps(fps: int) -> void:
	_fps = fps
	_mark_custom()
	_rebuild()


func set_bitrate(mbps: int) -> void:
	_bitrate = mbps
	_mark_custom()
	_rebuild()


func estimate_text() -> String:
	return "~%d MB/min video only" % int(round(float(_bitrate) * 60.0 / 8.0))


func _apply_preset(id: String) -> void:
	var preset: Dictionary = QUALITY_PRESETS.get(id, {})
	if preset.is_empty():
		return
	_size = preset["size"]
	_fps = int(preset["fps"])
	_bitrate = int(preset["bitrate"]) / 1000000
	_msaa = int(preset["msaa"])
	_audio_bitrate = int(preset["audio_bitrate"])
	_quality = id


func _mark_custom() -> void:
	_quality = CUSTOM_QUALITY
	_quality_chosen = true
	# Custom uses the Standard audio budget, per the product contract.
	_audio_bitrate = 192000


func gif_width_options() -> Array:
	return GifEncoder.widths()


func gif_reason_visible() -> bool:
	return _gif_reason_label != null and _gif_reason_label.visible


func gif_reason_text() -> String:
	return _gif_reason_label.text if _gif_reason_label != null else ""


func format_ids() -> Array:
	return FORMATS.duplicate()


func camera_available() -> bool:
	return not _camera_ids.is_empty()


func camera_reason() -> String:
	return "" if camera_available() else CAMERA_REASON


func camera_id() -> String:
	return _camera_id


func _sync_cameras() -> void:
	_camera_ids.clear()
	if _doc == null:
		_camera_id = ""
		return
	var exporter = CameraExport.new()
	exporter.setup(_doc)
	for entry in exporter.camera_names():
		var data: Dictionary = entry
		var id := str(data.get("id", ""))
		if id != "":
			_camera_ids.append(id)
	if _camera_ids.is_empty():
		_camera_id = ""
	elif not _camera_id in _camera_ids:
		_camera_id = _camera_ids[0]


func resolution_sizes() -> Array:
	var sizes: Array = []
	for entry in RESOLUTIONS:
		sizes.append(entry["size"])
	return sizes


func gif_fps_options() -> Array:
	return GIF_FPS.duplicate()


func gif_disabled_reason(fps: int) -> String:
	return GIF_60_REASON if fps == 60 else ""


func mp4_reason() -> String:
	return AndroidVideo.REASON


func bitrate_options() -> Array:
	return BITRATE_MBPS.duplicate()


func progress_text(kind: String, done: int, total: int) -> String:
	match kind:
		"frames":
			return "Frame %d/%d" % [done, total]
		"encoding":
			return "Encoding video"
		"verifying":
			return "Verifying"
		"done":
			return "Done"
		"cancelled":
			return "Cancelled"
		"error":
			return "Export failed"
	return "Ready"


func set_progress(kind: String, done: int = 0, total: int = 0) -> void:
	if _progress_label != null:
		_progress_label.text = progress_text(kind, done, total)
	if _status_label != null:
		_status_label.text = "Exporting" if kind in ["frames", "encoding", "verifying"] else progress_text(kind, done, total)


func set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func status_text() -> String:
	return _status_label.text if _status_label != null else ""


func result_text() -> String:
	return _result_label.text if _result_label != null else ""


func clear_result() -> void:
	if _result_label == null:
		return
	_result_label.text = ""
	_result_label.visible = false


func set_result(path: String, size_bytes: int, duration: float, tracks: String) -> void:
	if _result_label == null:
		return
	_result_label.text = "%s · %.1f MB · %.2f s · %s" % [path, float(size_bytes) / (1024.0 * 1024.0), duration, tracks]
	_result_label.visible = true


func build_options() -> Dictionary:
	var width := _size.x
	var height := _size.y
	if _format == "gif":
		width = _gif_width
		height = GifEncoder.height_for_width(_gif_width)
	var options := {
		"format": _format,
		"width": width,
		"height": height,
		"fps": _fps,
		"start": _start,
		"end": _end,
		"bitrate": _bitrate * 1000000,
		"camera_id": _camera_id,
		"include_audio": _include_audio,
		"output_path": _output_path(),
	}
	# Only MP4 has real quality options. PNG, GIF and the camera track keep
	# exactly the option shape they had before.
	if _format == "mp4":
		options["quality"] = _quality
		options["msaa"] = _msaa
		options["audio_bitrate"] = _audio_bitrate
	return options


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_progress_label = null
	_status_label = null
	_result_label = null
	_export_button = null
	_cancel_button = null
	_gif_reason_label = null
	_quality_reason_label = null
	_estimate_label = null
	_quality_buttons = {}
	add_theme_constant_override("separation", 8)
	add_child(Kit.section_label("Media export"))

	var formats := HBoxContainer.new()
	formats.add_theme_constant_override("separation", 2)
	add_child(formats)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for id in FORMATS:
		var button := Kit.text_toggle(id.to_upper(), "", true)
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.button_pressed = id == _format
		if id == "mp4" and not mp4_available():
			button.disabled = true
			button.tooltip_text = AndroidVideo.REASON
		if id == "camera" and not camera_available():
			button.disabled = true
			button.tooltip_text = CAMERA_REASON
		button.toggled.connect(func(on: bool) -> void:
			if on:
				set_format(id)
		)
		formats.add_child(button)

	if quality_controls_visible():
		add_child(_quality_row_control())
		_quality_reason_label = Kit.label(quality_reason_text(), Kit.TYPE_CAPTION, Kit.TEXT_DIM)
		_quality_reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_quality_reason_label.visible = quality_reason_text() != ""
		add_child(_quality_reason_label)

	add_child(_labeled_option("Resolution", resolution_option()))
	if _format == "gif":
		add_child(_labeled_option("GIF width", _gif_width_option()))
	add_child(_labeled_option("FPS", _fps_option()))
	_gif_reason_label = Kit.label(GIF_60_REASON, Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	_gif_reason_label.visible = _format == "gif"
	add_child(_gif_reason_label)
	add_child(_labeled_option("Bitrate", _bitrate_option()))
	if _format == "mp4":
		_estimate_label = Kit.label(estimate_text(), Kit.TYPE_CAPTION, Kit.TEXT_MUTED)
		add_child(_estimate_label)
	add_child(_range_row())
	add_child(_labeled_option("Camera", _camera_option()))
	var audio := Kit.text_toggle("Include audio mix")
	audio.button_pressed = _include_audio
	audio.toggled.connect(func(on: bool) -> void: _include_audio = on)
	add_child(audio)
	add_child(_labeled_field("Output", _output_path()))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	add_child(actions)
	_export_button = Kit.text_button("Export", "download", true)
	_export_button.pressed.connect(_on_export)
	actions.add_child(_export_button)
	_cancel_button = Kit.text_button("Cancel", "", false, true)
	_cancel_button.custom_minimum_size.x = 80
	_cancel_button.pressed.connect(func() -> void: cancel_requested.emit())
	actions.add_child(_cancel_button)

	_progress_label = Kit.mono_label(progress_text("ready", 0, 0), Kit.TYPE_MONO, Kit.TEXT_MUTED)
	add_child(_progress_label)
	_status_label = Kit.label("", Kit.TYPE_CAPTION, Kit.TEXT_MUTED)
	add_child(_status_label)
	_result_label = Kit.label("", Kit.TYPE_CAPTION, Kit.TEXT)
	_result_label.visible = false
	add_child(_result_label)


func _quality_row_control() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation", 8)
	var label := Kit.label("Quality", Kit.TYPE_BODY, Kit.TEXT_MUTED)
	label.custom_minimum_size.x = 96
	row.add_child(label)
	var track := PanelContainer.new()
	track.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_2, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(track)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 2)
	track.add_child(strip)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for id in QUALITY_IDS:
		var preset: Dictionary = QUALITY_PRESETS[id]
		var button := Kit.text_toggle(str(preset["label"]), "", true)
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.button_pressed = id == _quality
		var reason := ""
		if id == "master":
			reason = resolution_disabled_reason(Vector2i(3840, 2160))
		elif id == "high":
			reason = resolution_disabled_reason(Vector2i(2560, 1440))
		if reason != "":
			button.disabled = true
			button.tooltip_text = reason
		button.toggled.connect(func(on: bool) -> void:
			if on:
				set_quality(id)
		)
		strip.add_child(button)
		_quality_buttons[id] = button
	return row


func resolution_option() -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size.y = 44
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selected := 0
	for index in range(RESOLUTIONS.size()):
		var entry: Dictionary = RESOLUTIONS[index]
		option.add_item(str(entry["label"]))
		var reason := resolution_disabled_reason(entry["size"])
		if reason != "":
			option.set_item_disabled(index, true)
			option.get_popup().set_item_tooltip(index, reason)
		if entry["size"] == _size:
			selected = index
			if reason != "":
				option.tooltip_text = reason
	option.selected = selected
	option.item_selected.connect(func(index: int) -> void:
		set_resolution(RESOLUTIONS[index]["size"])
	)
	return option


func _gif_width_option() -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size.y = 44
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for width in GifEncoder.widths():
		option.add_item("%d × %d" % [width, GifEncoder.height_for_width(width)])
		if width == _gif_width:
			option.selected = option.item_count - 1
	option.item_selected.connect(func(index: int) -> void:
		_gif_width = int(GifEncoder.widths()[index])
	)
	return option


func _fps_option() -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size.y = 44
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for fps in FPS_OPTIONS:
		option.add_item("%d fps" % fps)
		if fps == _fps:
			option.selected = option.item_count - 1
		if _format == "gif" and fps == 60:
			option.set_item_disabled(option.item_count - 1, true)
	option.tooltip_text = GIF_60_REASON if _format == "gif" else ""
	option.item_selected.connect(func(index: int) -> void:
		set_fps(int(FPS_OPTIONS[index]))
	)
	return option


func _bitrate_option() -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size.y = 44
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for mbps in BITRATE_MBPS:
		option.add_item("%d Mbps" % mbps)
		if mbps == _bitrate:
			option.selected = option.item_count - 1
	option.item_selected.connect(func(index: int) -> void:
		set_bitrate(int(BITRATE_MBPS[index]))
	)
	return option


func _camera_option() -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size.y = 44
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not camera_available():
		option.add_item(CAMERA_REASON)
		option.disabled = true
		option.tooltip_text = CAMERA_REASON
		return option
	for id in _camera_ids:
		var label := "Camera"
		if _doc != null:
			var obj: Dictionary = _doc.get_object(id)
			label = str(obj.get("name", label))
		option.add_item(label)
		var index := option.item_count - 1
		option.set_item_metadata(index, id)
		if id == _camera_id:
			option.selected = index
	option.item_selected.connect(func(index: int) -> void:
		_camera_id = str(option.get_item_metadata(index))
	)
	return option


func _range_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation", 8)
	row.add_child(Kit.label("Range", Kit.TYPE_BODY, Kit.TEXT_MUTED))
	var start := Kit.line_edit("Start")
	start.text = "%.2f" % _start
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.text_submitted.connect(func(text: String) -> void: _start = maxf(0.0, text.to_float()))
	row.add_child(start)
	var end := Kit.line_edit("End")
	end.text = "%.2f" % _end
	end.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end.text_submitted.connect(func(text: String) -> void: _end = maxf(_start, text.to_float()))
	row.add_child(end)
	return row


func _labeled_field(label_text: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation", 8)
	var label := Kit.label(label_text, Kit.TYPE_BODY, Kit.TEXT_MUTED)
	label.custom_minimum_size.x = 96
	row.add_child(label)
	var field := Kit.line_edit("Output path")
	field.text = value
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_changed.connect(func(text: String) -> void:
		_output_path_value = text
	)
	row.add_child(field)
	return row


func _labeled_option(label_text: String, option: OptionButton) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation", 8)
	var label := Kit.label(label_text, Kit.TYPE_BODY, Kit.TEXT_MUTED)
	label.custom_minimum_size.x = 96
	row.add_child(label)
	row.add_child(option)
	return row


func _default_output_path() -> String:
	return "user://exports/kinema_export." + _extension_for(_format)


func _extension_for(format: String) -> String:
	return "json" if format == "camera" else format


func _normalize_output_path(path: String, format: String) -> String:
	var value := path if path != "" else _default_output_path()
	var extension := _extension_for(format)
	if value.get_extension().to_lower() == extension:
		return value
	return value.get_basename() + "." + extension


func _output_path() -> String:
	return _normalize_output_path(_output_path_value, _format)


func _on_export() -> void:
	if _format == "mp4" and not AndroidVideo.new().available():
		set_progress("error")
		if _status_label != null:
			_status_label.text = AndroidVideo.REASON
		return
	if _format == "camera" and not camera_available():
		set_progress("error")
		if _status_label != null:
			_status_label.text = CAMERA_REASON
		return
	export_requested.emit(build_options())
