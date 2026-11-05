extends PanelContainer
## The shared stage transport: play, skip to start, timecode, add key, Animate.
##
## It reports intent and renders document state; the editor owns the document.
## Animate is text only because it navigates, it does not mutate the clip.

signal play_requested
signal skip_start_requested
signal time_requested
signal add_key_requested
signal animate_requested

const HEIGHT_TOUCH := 44
const HEIGHT_DESKTOP := 32
const DEFAULT_KEY_REASON := "Select an object to add a key."

var _layout_mode := "studio"
var _playing := false

var _row: HBoxContainer
var _play_button: Button
var _skip_button: Button
var _time_button: Button
var _add_key_button: Button
var _animate_button: Button


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_build()
	_apply_mode()


func _build() -> void:
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 4)
	add_child(_row)

	_play_button = _make_icon("play", "Play")
	_play_button.pressed.connect(func() -> void: play_requested.emit())
	_row.add_child(_play_button)

	_skip_button = _make_icon("skip-back", "Skip to start")
	_skip_button.pressed.connect(func() -> void: skip_start_requested.emit())
	_row.add_child(_skip_button)

	_time_button = Kit.text_button("00:00:00", "", false, true)
	_time_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_button.add_theme_font_override("font", Kit.font_mono)
	_time_button.add_theme_font_size_override("font_size", 12)
	_time_button.tooltip_text = "Go to time"
	_time_button.set_meta("action_id", "time")
	_time_button.set_meta("action_icon", "")
	_time_button.pressed.connect(func() -> void: time_requested.emit())
	_row.add_child(_time_button)

	_add_key_button = _make_icon("diamond-plus", "Add a key at the playhead")
	_add_key_button.set_meta("action_id", "add_key")
	_add_key_button.pressed.connect(func() -> void: add_key_requested.emit())
	_row.add_child(_add_key_button)

	_animate_button = Kit.text_button("Animate", "", false, true)
	_animate_button.add_theme_font_size_override("font_size", 13)
	_animate_button.tooltip_text = "Open the Animate workspace"
	_animate_button.set_meta("action_id", "animate")
	_animate_button.set_meta("action_icon", "")
	_animate_button.pressed.connect(func() -> void: animate_requested.emit())
	_row.add_child(_animate_button)


func _make_icon(icon_name: String, tooltip: String) -> Button:
	var button := Kit.icon_button(icon_name, tooltip)
	button.set_meta("action_id", icon_name)
	button.set_meta("action_icon", icon_name)
	return button


func set_layout_mode(mode: String) -> void:
	_layout_mode = mode if mode in ["compact", "studio", "desktop"] else "studio"
	_apply_mode()


func set_playing(playing: bool) -> void:
	_playing = playing
	if _play_button == null:
		return
	_play_button.icon = Kit.icon_texture("pause" if playing else "play")
	_play_button.set_meta("action_icon", "pause" if playing else "play")
	_play_button.tooltip_text = "Pause" if playing else "Play"
	_play_button.set_meta("action_id", "pause" if playing else "play")


func set_timecode(text: String) -> void:
	if _time_button != null:
		_time_button.text = text


func set_add_key_enabled(enabled: bool, reason := "") -> void:
	if _add_key_button == null:
		return
	_add_key_button.disabled = not enabled
	_add_key_button.tooltip_text = (reason if reason != "" else DEFAULT_KEY_REASON) \
		if not enabled else "Add a key at the playhead"


func play_button() -> Button:
	return _play_button


func add_key_button() -> Button:
	return _add_key_button


func animate_button() -> Button:
	return _animate_button


func time_button() -> Button:
	return _time_button


func action_button(id: String) -> Button:
	if _row == null:
		return null
	for child in _row.get_children():
		if child is Button and str(child.get_meta("action_id", "")) == id:
			return child
	return null


func visible_action_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	if _row == null:
		return ids
	for child in _row.get_children():
		if child is Button and child.visible:
			var id := str(child.get_meta("action_id", ""))
			if id != "":
				ids.append(id)
	return ids


func _apply_mode() -> void:
	var desktop := _layout_mode == "desktop"
	var height := float(HEIGHT_DESKTOP if desktop else HEIGHT_TOUCH)
	var icon_side := 28.0 if desktop else 44.0
	custom_minimum_size.y = height
	var style := Kit.flat_style(Kit.SURFACE_2, 0, Color(0, 0, 0, 0), 0)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	add_theme_stylebox_override("panel", style)
	for button in [_play_button, _skip_button, _add_key_button]:
		if button == null:
			continue
		button.custom_minimum_size = Vector2(icon_side, icon_side)
		button.add_theme_constant_override("icon_max_width", 18 if desktop else 20)
		if desktop:
			Kit.exempt_from_hit_floor(button)
	if _time_button != null:
		_time_button.custom_minimum_size = Vector2(96.0, height)
		_time_button.add_theme_font_size_override("font_size", 11 if desktop else 12)
		if desktop:
			Kit.exempt_from_hit_floor(_time_button)
	if _animate_button != null:
		_animate_button.custom_minimum_size = Vector2(96.0, height)
		if desktop:
			Kit.exempt_from_hit_floor(_animate_button)
