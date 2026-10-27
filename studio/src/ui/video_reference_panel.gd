extends VBoxContainer
## Video-reference inspector sheet.
##
## Controls opacity, fit, offset, scale, flip and visibility. Deleting removes
## the proxy directory, so the sheet shows the irreversible warning before the
## destructive button.

signal changed
signal delete_requested(id: String)
signal close_requested

var _media = null
var _id := ""
var _ref: Dictionary = {}
var _delete_button: Button
var _warning: Label
var _frame_label: Label


func setup(media) -> void:
	_media = media


func open(id: String) -> void:
	_id = id
	_rebuild()


func reference_id() -> String:
	return _id


func delete_warning() -> String:
	return _warning.text if _warning != null else ""


func frame_text() -> String:
	return _frame_label.text if _frame_label != null else ""


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_delete_button = null
	_warning = null
	_frame_label = null
	add_theme_constant_override("separation", 8)
	_ref = _media.video_reference(_id) if _media != null else {}
	if _ref.is_empty():
		add_child(Kit.label("Select a video reference.", Kit.TYPE_BODY, Kit.TEXT_MUTED))
		return

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 44
	add_child(header)
	var name := Kit.label(str(_ref.get("name", "Reference")), Kit.TYPE_TITLE, Kit.TEXT)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name)
	_delete_button = Kit.text_button("Delete reference", "", false, true)
	_delete_button.add_theme_color_override("font_color", Kit.DANGER)
	_delete_button.pressed.connect(func() -> void:
		_media.delete_video_reference(_id)
		delete_requested.emit(_id)
	)
	header.add_child(_delete_button)

	_frame_label = Kit.mono_label(
		"Frame proxy · %d fps · %d×%d · %.2f s" % [
			int(_ref.get("fps", 12)), int(_ref.get("width", 0)), int(_ref.get("height", 0)),
			float(_ref.get("duration", 0.0)),
		],
		Kit.TYPE_MONO,
		Kit.TEXT_MUTED
	)
	add_child(_frame_label)

	add_child(_opacity_row())
	add_child(_fit_row())
	add_child(_field("Offset X", "offset_x", float(Array(_ref.get("offset", [0, 0]))[0])))
	add_child(_field("Offset Y", "offset_y", float(Array(_ref.get("offset", [0, 0]))[1])))
	add_child(_field("Scale", "scale", float(_ref.get("scale", 1.0))))
	var flip := Kit.text_toggle("Flip H")
	flip.button_pressed = bool(_ref.get("flip_h", false))
	flip.toggled.connect(func(on: bool) -> void:
		_media.update_video_reference(_id, {"flip_h": on})
		changed.emit()
	)
	add_child(flip)
	var visible := Kit.text_toggle("Visible")
	visible.button_pressed = bool(_ref.get("visible", true))
	visible.toggled.connect(func(on: bool) -> void:
		_media.update_video_reference(_id, {"visible": on})
		changed.emit()
	)
	add_child(visible)

	_warning = Kit.label(
		"Deleting removes the proxy folder. This cannot be undone.",
		Kit.TYPE_CAPTION,
		Kit.DANGER
	)
	add_child(_warning)


func _opacity_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation", 8)
	var label := Kit.label("Opacity", Kit.TYPE_BODY, Kit.TEXT_MUTED)
	label.custom_minimum_size.x = 96
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = float(_ref.get("opacity", 0.5)) * 100.0
	slider.custom_minimum_size.y = 44
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float) -> void:
		_media.update_video_reference(_id, {"opacity": clampf(value / 100.0, 0.0, 1.0)})
		changed.emit()
	)
	row.add_child(slider)
	var value_label := Kit.mono_label("%d%%" % int(round(float(_ref.get("opacity", 0.5)) * 100.0)), Kit.TYPE_MONO, Kit.TEXT_MUTED)
	value_label.custom_minimum_size.x = 40
	row.add_child(value_label)
	return row


func _fit_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation", 8)
	var label := Kit.label("Fit", Kit.TYPE_BODY, Kit.TEXT_MUTED)
	label.custom_minimum_size.x = 96
	row.add_child(label)
	var option := OptionButton.new()
	option.custom_minimum_size.y = 44
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_item("Contain")
	option.add_item("Cover")
	option.selected = 0 if str(_ref.get("fit", "contain")) == "contain" else 1
	option.item_selected.connect(func(index: int) -> void:
		_media.update_video_reference(_id, {"fit": "contain" if index == 0 else "cover"})
		changed.emit()
	)
	row.add_child(option)
	return row


func _field(label_text: String, key: String, value: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation", 8)
	var label := Kit.label(label_text, Kit.TYPE_BODY, Kit.TEXT_MUTED)
	label.custom_minimum_size.x = 96
	row.add_child(label)
	var field := Kit.line_edit("0.00")
	field.text = "%.2f" % value
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_submitted.connect(func(text: String) -> void:
		var offset := Array(_ref.get("offset", [0.0, 0.0]))
		if key == "offset_x":
			offset[0] = text.to_float()
			_media.update_video_reference(_id, {"offset": offset})
		elif key == "offset_y":
			offset[1] = text.to_float()
			_media.update_video_reference(_id, {"offset": offset})
		else:
			_media.update_video_reference(_id, {key: maxf(0.01, text.to_float())})
		_ref = _media.video_reference(_id)
		changed.emit()
	)
	row.add_child(field)
	return row
