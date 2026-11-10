extends VBoxContainer
## Audio-track inspector sheet.
##
## Every value here is a real track field. WAV tracks draw a peak waveform from
## the cached PCM analysis; OGG/MP3 say "waveform unavailable" instead of
## drawing a decorative band.

signal changed
signal delete_requested(id: String)
signal close_requested

const AudioLibrary = preload("res://src/core/audio_library.gd")

var _media = null
var _track_id := ""
var _track: Dictionary = {}
var _waveform: Control
var _waveform_label: Label
var _delete_button: Button
var _volume_label: Label


class WaveformView:
	extends Control
	var peaks: Array = []
	var available := false

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Kit.SURFACE_2)
		var mid := size.y * 0.5
		if not available or peaks.is_empty():
			draw_line(Vector2(0, mid), Vector2(size.x, mid), Kit.BORDER, 1.0)
			return
		var step := size.x / float(peaks.size())
		for index in range(peaks.size()):
			var peak := clampf(float(peaks[index]), 0.0, 1.0)
			var height := maxf(1.0, peak * (size.y - 4.0))
			var x := float(index) * step
			draw_line(Vector2(x, mid - height * 0.5), Vector2(x, mid + height * 0.5), Kit.TEXT_MUTED, maxf(1.0, step))


func setup(media) -> void:
	_media = media


func open(track_id: String) -> void:
	_track_id = track_id
	_rebuild()


func track_id() -> String:
	return _track_id


func waveform_status() -> String:
	return _waveform_label.text if _waveform_label != null else ""


func has_delete_confirm() -> bool:
	return _delete_button != null


func volume_text() -> String:
	return _volume_label.text if _volume_label != null else ""


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_waveform = null
	_waveform_label = null
	_delete_button = null
	_volume_label = null
	add_theme_constant_override("separation", 8)
	_track = _media.audio_track(_track_id) if _media != null else {}
	if _track.is_empty():
		add_child(Kit.label("Select an audio track.", Kit.TYPE_BODY, Kit.TEXT_MUTED))
		return

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 44
	add_child(header)
	var name := Kit.label(str(_track.get("name", "Audio")), Kit.TYPE_TITLE, Kit.TEXT)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name)
	_delete_button = Kit.text_button("Delete track", "", false, true)
	_delete_button.add_theme_color_override("font_color", Kit.DANGER)
	_delete_button.pressed.connect(func() -> void:
		_media.delete_audio_track(_track_id)
		delete_requested.emit(_track_id)
	)
	header.add_child(_delete_button)

	var peaks: Dictionary = AudioLibrary.waveform_peaks(_media.project_dir().path_join(str(_track.get("file", ""))))
	var view := WaveformView.new()
	view.custom_minimum_size.y = 56
	view.available = bool(peaks.get("ok", false))
	view.peaks = Array(peaks.get("peaks", []))
	_waveform = view
	add_child(view)
	_waveform_label = Kit.label(
		"Waveform · %d buckets" % view.peaks.size() if view.available else "waveform unavailable",
		Kit.TYPE_CAPTION,
		Kit.TEXT_MUTED if view.available else Kit.TEXT_DIM
	)
	add_child(_waveform_label)

	add_child(_field("Start", "start", float(_track.get("start", 0.0))))
	add_child(_field("Trim start", "trim_start", float(_track.get("trim_start", 0.0))))
	add_child(_field("Trim end", "trim_end", float(_track.get("trim_end", 0.0))))
	add_child(_volume_row())
	add_child(_field("Fade in", "fade_in", float(_track.get("fade_in", 0.0))))
	add_child(_field("Fade out", "fade_out", float(_track.get("fade_out", 0.0))))
	var mute := Kit.text_toggle("Mute")
	mute.button_pressed = bool(_track.get("muted", false))
	mute.toggled.connect(func(on: bool) -> void:
		_media.update_audio_track(_track_id, {"muted": on})
		changed.emit()
	)
	add_child(mute)


func _field(label_text: String, key: String, value: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation", 8)
	var label := Kit.label(label_text, Kit.TYPE_BODY, Kit.TEXT_MUTED)
	label.custom_minimum_size.x = 96
	row.add_child(label)
	var field := Kit.line_edit("0.00")
	field.text = "%.3f" % value
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_submitted.connect(func(text: String) -> void:
		_commit(key, text)
	)
	row.add_child(field)
	return row


func _volume_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation", 8)
	var label := Kit.label("Volume", Kit.TYPE_BODY, Kit.TEXT_MUTED)
	label.custom_minimum_size.x = 96
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = float(_track.get("volume", 1.0))
	slider.custom_minimum_size.y = 44
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float) -> void:
		_media.update_audio_track(_track_id, {"volume": value})
		if _volume_label != null:
			_volume_label.text = "%d%%" % int(round(value * 100.0))
		changed.emit()
	)
	row.add_child(slider)
	_volume_label = Kit.mono_label("%d%%" % int(round(float(_track.get("volume", 1.0)) * 100.0)), Kit.TYPE_MONO, Kit.TEXT_MUTED)
	_volume_label.custom_minimum_size.x = 40
	row.add_child(_volume_label)
	return row


func _commit(key: String, text: String) -> void:
	var value := text.to_float()
	_media.update_audio_track(_track_id, {key: value})
	_track = _media.audio_track(_track_id)
	changed.emit()
