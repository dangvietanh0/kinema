extends Control
## Workspace-only speed graph: real sampled channels, key selection and key
## edits. The control never mutates an Animation directly; every edit goes
## through Document so one gesture is one undo entry.

signal selection_changed(indices: PackedInt32Array)
signal notice(text: String)

const DocumentScript = preload("res://src/core/document.gd")
const SpeedCurveScript = preload("res://src/core/speed_curve.gd")
const NumberFieldScript = preload("res://src/ui/num_field.gd")

const EMPTY_SELECT_OBJECT := "Select an object"
const EMPTY_NO_KEYS := "No keys on this channel. Add a key at the playhead."
const EMPTY_NO_COMPONENT := "This channel has no editable value component."
const SPEED_VALUE_HINT := "Switch to Value to edit values."
const ROTATION_VALUE_HINT := "Rotation values are quaternion; drag rotates with the rig or gizmo."
const HEADER_H := 56.0
const KEY_ROW_H := 56.0
const MIN_PLOT_H := 120.0
const COMPONENTS := ["all", "x", "y", "z"]
const COMPONENT_LABELS := {"all": "All", "x": "X", "y": "Y", "z": "Z"}
const CURVE_VARIANTS := {
	"bounce_out": "Bounce out",
	"bounce_in": "Bounce in",
	"bounce_in_out": "Bounce in-out",
	"elastic_out": "Elastic out",
	"elastic_in": "Elastic in",
	"back_out": "Back out",
	"back_in": "Back in",
	"spring": "Spring",
	"sine_in": "Sine in",
	"sine_out": "Sine out",
	"sine_in_out": "Sine in-out",
	"expo_in": "Expo in",
	"expo_out": "Expo out",
	"expo_in_out": "Expo in-out",
}

var doc
var _object_id := ""
var _channel := "position"
var _view := "value"
var _component := "all"
var _indices := PackedInt32Array()
var _multi := false
var _time_start := 0.0
var _time_end := -1.0
var _value_min := -1.0
var _value_max := 1.0
var _clipboard: Array = []
var _last_error := ""
var _drag_mode := ""
var _drag_start := Vector2.ZERO
var _drag_time := 0.0
var _drag_indices := PackedInt32Array()
var _touches: Dictionary = {}
var _pinch_dist := -1.0
var _pinch_mid := Vector2.ZERO

var _header: PanelContainer
var _plot: Control
var _key_row: PanelContainer
var _channel_label: Label
var _count_label: Label
var _value_button: Button
var _speed_button: Button
var _fit_button: Button
var _multi_button: Button
var _presets_button: Button
var _ease_button: Button
var _time_field
var _value_field
var _component_menu: OptionButton
var _add_button: Button
var _delete_button: Button
var _presets_menu: PopupMenu


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_build_header()
	_build_plot()
	_build_key_row()
	resized.connect(_on_resized)
	_sync_header()


func setup(document) -> void:
	if doc != null and doc.keyframes_changed.is_connected(_on_keyframes_changed):
		doc.keyframes_changed.disconnect(_on_keyframes_changed)
	doc = document
	if doc != null and not doc.keyframes_changed.is_connected(_on_keyframes_changed):
		doc.keyframes_changed.connect(_on_keyframes_changed)
	fit()
	_sync_all()


func set_context(object_id: String) -> void:
	if _object_id == object_id:
		_sync_all()
		return
	_object_id = object_id
	_indices = PackedInt32Array()
	_value_min = -1.0
	_value_max = 1.0
	fit()
	_emit_selection()
	_sync_all()


func set_channel(channel: String) -> bool:
	if doc == null or not (channel in doc.CHANNELS):
		return false
	var changed := channel != _channel
	_channel = channel
	_indices = PackedInt32Array()
	_component = "all"
	fit()
	if changed:
		_emit_selection()
	_sync_all()
	return true


func get_channel() -> String:
	return _channel


func selected_indices() -> PackedInt32Array:
	return _indices.duplicate()


func select_indices(indices: PackedInt32Array, additive := false) -> void:
	var count := _key_count()
	var next: Array = [] if not additive else Array(_indices)
	for raw in indices:
		var index := int(raw)
		if index < 0 or index >= count:
			continue
		if not next.has(index):
			next.append(index)
	next.sort()
	_indices = PackedInt32Array(next)
	_sync_fields()
	_emit_selection()
	_redraw()


func clear_selection() -> void:
	if _indices.is_empty():
		return
	_indices = PackedInt32Array()
	_sync_fields()
	_emit_selection()
	_redraw()


func selected_segment() -> Dictionary:
	var count := _key_count()
	if _indices.size() != 1 or count <= 0:
		return {"ok": false, "reason": "Select one key."}
	var index := int(_indices[0])
	if index < 0 or index >= count - 1:
		return {"ok": false, "reason": "The last key has no following segment."}
	var keys := _keys()
	return {
		"ok": true,
		"start_index": index,
		"end_index": index + 1,
		"t0": float(keys[index]["time"]),
		"t1": float(keys[index + 1]["time"]),
	}


func set_view(view: String) -> bool:
	if view != "value" and view != "speed":
		return false
	_view = view
	_sync_header()
	_redraw()
	return true


func view() -> String:
	return _view


func commit_key_edit(index: int, time: float, value: Variant = null) -> bool:
	if doc == null or _object_id == "":
		return false
	var keys := _keys()
	if index < 0 or index >= keys.size():
		return false
	if value != null and _channel == "rotation":
		_last_error = ROTATION_VALUE_HINT
		return false
	var edit := {"index": index, "time": clampf(time, 0.0, doc.duration)}
	if value != null:
		edit["value"] = _typed_value(value)
	var result: Dictionary = doc.apply_key_edits(_object_id, _channel, [edit], "Edit key")
	if not bool(result.get("ok", false)):
		_last_error = str(result.get("error", "This key could not be edited."))
		return false
	_last_error = ""
	var next := int(result["indices"][0]) if not result["indices"].is_empty() else index
	_indices = PackedInt32Array([next])
	_sync_fields()
	_emit_selection()
	_redraw()
	return true


func apply_easing(value: float) -> bool:
	var segment := selected_segment()
	if not bool(segment.get("ok", false)):
		_last_error = str(segment.get("reason", "Select one key."))
		return false
	doc.begin_edit("Ease key")
	doc.set_key_transition(_object_id, _channel, int(segment["start_index"]), value)
	doc.end_edit()
	_last_error = ""
	return true


func apply_curve_family(curve_id: String) -> Dictionary:
	var segment := selected_segment()
	if not bool(segment.get("ok", false)):
		var reason := str(segment.get("reason", "Select one key."))
		_last_error = reason
		return {"ok": false, "inserted": 0, "reason": reason, "message": reason}
	if not SpeedCurveScript.SPEED_CURVES.has(curve_id):
		_last_error = "Unknown curve family."
		return {"ok": false, "inserted": 0, "reason": _last_error, "message": _last_error}
	var result: Dictionary = doc.bake_curve_segment(
		_object_id, _channel, int(segment["start_index"]), curve_id)
	if bool(result.get("ok", false)):
		_last_error = ""
		var label := str(CURVE_VARIANTS.get(curve_id, SpeedCurveScript.family_label(curve_id)))
		result["message"] = "%s baked · %d keys" % [label, int(result.get("inserted", 0))]
		notice.emit(str(result["message"]))
	else:
		_last_error = str(result.get("reason", "The curve could not be baked."))
	_redraw()
	return result


func copy_selection() -> void:
	var keys := _keys()
	_clipboard = []
	if _indices.is_empty():
		return
	var base := float(keys[int(_indices[0])]["time"])
	for raw in _indices:
		var index := int(raw)
		if index < 0 or index >= keys.size():
			continue
		_clipboard.append({
			"time": float(keys[index]["time"]) - base,
			"transition": float(doc.get_key_transition(_object_id, _channel, index)),
			"value": keys[index]["value"],
		})


func paste_at(time: float) -> bool:
	if doc == null or _object_id == "" or _clipboard.is_empty():
		return false
	var max_offset := 0.0
	for entry in _clipboard:
		max_offset = maxf(max_offset, float(entry["time"]))
	var base := clampf(time, 0.0, maxf(0.0, doc.duration - max_offset))
	var edits: Array = []
	for entry in _clipboard:
		edits.append({
			"index": -1,
			"time": clampf(base + float(entry["time"]), 0.0, doc.duration),
			"value": entry["value"],
			"transition": float(entry["transition"]),
		})
	var result: Dictionary = doc.apply_key_edits(_object_id, _channel, edits, "Paste keys")
	if not bool(result.get("ok", false)):
		_last_error = str(result.get("error", "The keys could not be pasted."))
		return false
	_last_error = ""
	_indices = PackedInt32Array()
	for raw in result["indices"]:
		_indices.append(int(raw))
	_emit_selection()
	_sync_fields()
	_redraw()
	return true


func add_key_at_playhead() -> bool:
	if doc == null or _object_id == "":
		return false
	var value: Variant = doc.sample_channel(_object_id, _channel, doc.current_time)
	if value == null:
		value = doc._channel_value(_object_id, _channel)
	if value == null:
		return false
	var result: Dictionary = doc.apply_key_edits(_object_id, _channel, [{
		"index": -1,
		"time": doc.current_time,
		"value": value,
		"transition": 1.0,
	}], "Add key")
	if not bool(result.get("ok", false)):
		_last_error = str(result.get("error", "The key could not be added."))
		return false
	_last_error = ""
	_indices = PackedInt32Array()
	if not result["indices"].is_empty():
		_indices.append(int(result["indices"][0]))
	_emit_selection()
	_sync_fields()
	_redraw()
	return true


func delete_selection() -> void:
	if doc == null or _object_id == "" or _indices.is_empty():
		return
	var edits: Array = []
	for raw in _indices:
		edits.append({"index": int(raw), "delete": true})
	doc.apply_key_edits(_object_id, _channel, edits, "Delete keys")
	_indices = PackedInt32Array()
	_emit_selection()
	_sync_fields()
	_redraw()


func fit() -> void:
	_time_start = 0.0
	_time_end = maxf(0.1, float(doc.duration) if doc != null else 8.0)
	_fit_value_range()


func plot_rect() -> Rect2:
	return Rect2(
		Vector2.ZERO,
		Vector2(maxf(0.0, size.x), maxf(0.0, size.y - HEADER_H - KEY_ROW_H)))


# --- Introspection helpers used by the workspace tests ---------------------

func last_error() -> String:
	return _last_error


func empty_state() -> String:
	if doc == null or _object_id == "" or doc.get_object(_object_id).is_empty():
		return EMPTY_SELECT_OBJECT
	if _keys().is_empty():
		return EMPTY_NO_KEYS
	if _view == "value" and _component != "all" and _channel == "rotation":
		return EMPTY_NO_COMPONENT
	return ""


func drag_hint() -> String:
	if _view == "speed":
		return SPEED_VALUE_HINT
	if _channel == "rotation":
		return ROTATION_VALUE_HINT
	return ""


func component_label() -> String:
	return str(COMPONENT_LABELS.get(_component, "All"))


func component_enabled() -> bool:
	return _channel != "rotation"


func easing_enabled() -> bool:
	return bool(selected_segment().get("ok", false))


func curve_enabled() -> bool:
	return easing_enabled()


func key_count() -> int:
	return _key_count()


func select_component(component: String) -> void:
	if not (component in COMPONENTS):
		return
	if _channel == "rotation":
		_component = "all"
		return
	_component = component
	_sync_component()
	_redraw()


# --- Model helpers -------------------------------------------------------

func _keys() -> Array:
	if doc == null or _object_id == "":
		return []
	return doc.get_channel_keys(_object_id, _channel)


func _key_count() -> int:
	return _keys().size()


func _typed_value(value: Variant) -> Variant:
	if _channel == "rotation":
		return value
	if _channel == "position" or _channel == "scale":
		if value is Vector3:
			return value
		var keys := _keys()
		var current := Vector3.ZERO
		if _indices.size() == 1 and int(_indices[0]) < keys.size():
			current = keys[int(_indices[0])]["value"]
		var axis: int = {"x": 0, "y": 1, "z": 2}.get(_component, -1)
		if axis >= 0:
			current[axis] = float(value)
			return current
		return Vector3(float(value), float(value), float(value))
	return value


func _emit_selection() -> void:
	selection_changed.emit(_indices.duplicate())


func _on_keyframes_changed(id: String) -> void:
	if id != _object_id:
		return
	# Re-resolve by time: no stale index survives a track rebuild.
	var keys := _keys()
	var old_times: Array = []
	for raw in _indices:
		var index := int(raw)
		if index >= 0 and index < keys.size():
			old_times.append(float(keys[index]["time"]))
	var next: Array = []
	for old_time in old_times:
		var best := -1
		var best_dist := 0.002
		for i in range(keys.size()):
			var dist := absf(float(keys[i]["time"]) - float(old_time))
			if dist <= best_dist:
				best_dist = dist
				best = i
		if best >= 0 and not next.has(best):
			next.append(best)
	next.sort()
	_indices = PackedInt32Array(next)
	_fit_value_range()
	_sync_fields()
	_sync_header()
	_redraw()


func _fit_value_range() -> void:
	var keys := _keys()
	if keys.is_empty():
		_value_min = -1.0
		_value_max = 1.0
		return
	var low := INF
	var high := -INF
	for key in keys:
		var scalar: Variant = _value_scalar(key["value"])
		if scalar == null:
			continue
		low = minf(low, scalar)
		high = maxf(high, scalar)
	if not is_finite(low) or not is_finite(high):
		_value_min = -1.0
		_value_max = 1.0
		return
	var span := high - low
	if span < 0.0001:
		span = 1.0
	_value_min = low - span * 0.1
	_value_max = high + span * 0.1


func _value_scalar(value: Variant) -> Variant:
	if _channel == "rotation":
		var q: Quaternion = value if value is Quaternion else Quaternion.IDENTITY
		return rad_to_deg(q.get_euler().x)
	if value is Vector3:
		var vec: Vector3 = value
		match _component:
			"x": return vec.x
			"y": return vec.y
			"z": return vec.z
			_: return vec.length()
	return float(value) if value != null else null


func _sample_scalar(time: float) -> Variant:
	if doc == null or _object_id == "":
		return null
	return _value_scalar(doc.sample_channel(_object_id, _channel, time))


# --- UI ------------------------------------------------------------------

func _build_header() -> void:
	_header = PanelContainer.new()
	_header.anchor_right = 1.0
	_header.offset_bottom = HEADER_H
	_header.add_theme_stylebox_override("panel",
		Kit.flat_style(Kit.SURFACE_2, 0, Kit.BORDER_SOFT, 0))
	add_child(_header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_header.add_child(row)

	_channel_label = Kit.label("Position", Kit.TYPE_CAPTION, Kit.TEXT, 600)
	_channel_label.custom_minimum_size.x = 64
	row.add_child(_channel_label)
	_count_label = Kit.mono_label("0", 10, Kit.TEXT_DIM)
	_count_label.custom_minimum_size.x = 30
	row.add_child(_count_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	_value_button = Kit.text_button("Value", "", false, true)
	_value_button.toggle_mode = true
	_value_button.custom_minimum_size = Vector2(56, 44)
	_value_button.pressed.connect(func() -> void: set_view("value"))
	row.add_child(_value_button)
	_speed_button = Kit.text_button("Speed", "", false, true)
	_speed_button.toggle_mode = true
	_speed_button.custom_minimum_size = Vector2(56, 44)
	_speed_button.pressed.connect(func() -> void: set_view("speed"))
	row.add_child(_speed_button)

	_fit_button = Kit.text_button("Fit", "", false, true)
	_fit_button.custom_minimum_size = Vector2(44, 44)
	_fit_button.pressed.connect(func() -> void:
		fit()
		_redraw()
	)
	row.add_child(_fit_button)

	_multi_button = Kit.icon_button("layers", "Multi-select keys", 44, 18)
	_multi_button.toggle_mode = true
	_multi_button.toggled.connect(func(on: bool) -> void: _multi = on)
	row.add_child(_multi_button)

	_ease_button = Kit.icon_button("sliders-horizontal", "Easing presets", 44, 18)
	_ease_button.pressed.connect(_open_ease_menu)
	row.add_child(_ease_button)

	_presets_button = Kit.text_button("Presets", "", false, true)
	_presets_button.custom_minimum_size = Vector2(96, 44)
	_presets_button.pressed.connect(_open_presets_menu)
	row.add_child(_presets_button)
	_presets_menu = PopupMenu.new()
	_presets_menu.add_theme_font_size_override("font_size", Kit.TYPE_CAPTION)
	for id in SpeedCurveScript.family_ids():
		_presets_menu.add_item(str(CURVE_VARIANTS.get(id, id)))
		_presets_menu.set_item_metadata(_presets_menu.item_count - 1, id)
	_presets_menu.id_pressed.connect(func(index: int) -> void:
		apply_curve_family(str(_presets_menu.get_item_metadata(index)))
	)
	add_child(_presets_menu)
	_presets_menu.visible = false


func _build_plot() -> void:
	_plot = Control.new()
	_plot.anchor_right = 1.0
	_plot.anchor_bottom = 1.0
	_plot.offset_top = HEADER_H
	_plot.offset_bottom = -KEY_ROW_H
	_plot.mouse_filter = Control.MOUSE_FILTER_STOP
	_plot.gui_input.connect(_on_plot_input)
	_plot.draw.connect(_draw_plot)
	add_child(_plot)


func _build_key_row() -> void:
	_key_row = PanelContainer.new()
	_key_row.anchor_right = 1.0
	_key_row.anchor_top = 1.0
	_key_row.anchor_bottom = 1.0
	_key_row.offset_top = -KEY_ROW_H
	_key_row.add_theme_stylebox_override("panel",
		Kit.flat_style(Kit.SURFACE_2, 0, Kit.BORDER_SOFT, 0))
	add_child(_key_row)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_key_row.add_child(row)

	_time_field = NumberFieldScript.new()
	_time_field.axis = "T"
	_time_field.suffix = " s"
	_time_field.min_value = 0.0
	_time_field.step = 1.0 / 24.0
	_time_field.custom_minimum_size = Vector2(84, 44)
	_time_field.text_committed.connect(_on_time_committed)
	row.add_child(_time_field)

	_value_field = NumberFieldScript.new()
	_value_field.axis = "X"
	_value_field.step = 0.01
	_value_field.custom_minimum_size = Vector2(84, 44)
	_value_field.text_committed.connect(_on_value_committed)
	row.add_child(_value_field)

	_component_menu = OptionButton.new()
	_component_menu.custom_minimum_size = Vector2(64, 44)
	_component_menu.add_theme_font_size_override("font_size", Kit.TYPE_CAPTION)
	for component in COMPONENTS:
		_component_menu.add_item(str(COMPONENT_LABELS[component]))
	_component_menu.item_selected.connect(func(index: int) -> void:
		select_component(str(COMPONENTS[index]))
	)
	row.add_child(_component_menu)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	_add_button = Kit.text_button("Add key", "", true)
	_add_button.custom_minimum_size = Vector2(96, 44)
	_add_button.pressed.connect(func() -> void: add_key_at_playhead())
	row.add_child(_add_button)

	_delete_button = Kit.icon_button("trash-2", "Delete selected keys", 44, 17)
	_delete_button.pressed.connect(delete_selection)
	row.add_child(_delete_button)


func _sync_all() -> void:
	_sync_header()
	_sync_component()
	_sync_fields()
	_redraw()


func _sync_header() -> void:
	if _channel_label == null:
		return
	_channel_label.text = str(doc.CHANNEL_LABELS.get(_channel, _channel)) if doc != null else _channel.capitalize()
	_count_label.text = str(_key_count())
	if _value_button != null:
		_set_segment(_value_button, _view == "value")
		_set_segment(_speed_button, _view == "speed")
	if _ease_button != null:
		_ease_button.disabled = not easing_enabled()
		_ease_button.tooltip_text = "Easing presets" if easing_enabled() else str(selected_segment().get("reason", ""))
	if _presets_button != null:
		_presets_button.disabled = not curve_enabled()
		_presets_button.tooltip_text = "Curve family presets" if curve_enabled() else str(selected_segment().get("reason", ""))
	if _multi_button != null:
		_set_segment(_multi_button, _multi)


func _set_segment(button: Button, active: bool) -> void:
	button.set_pressed_no_signal(active)
	button.add_theme_color_override("font_color", Kit.TEXT if active else Kit.TEXT_MUTED)
	button.add_theme_color_override("icon_normal_color", Kit.FOCUS_BRIGHT if active else Kit.TEXT_MUTED)


func _sync_component() -> void:
	if _component_menu == null:
		return
	if _channel == "rotation":
		_component = "all"
	var index := COMPONENTS.find(_component)
	if index >= 0:
		_component_menu.select(index)
	_component_menu.disabled = not component_enabled()
	_component_menu.tooltip_text = ROTATION_VALUE_HINT if not component_enabled() else "Value component"
	_set_field_editable(_value_field, _view == "value" and _channel != "rotation")


## NumberField owns an inner LineEdit; the field is read-only in states where a
## value cannot be committed, but the control stays on screen so the reason is
## visible rather than silently hidden.
func _set_field_editable(field, editable: bool) -> void:
	if field == null:
		return
	var edit = field.get("_edit")
	if edit != null:
		edit.editable = editable


func _sync_fields() -> void:
	if _time_field == null:
		return
	_set_field_editable(_time_field, _indices.size() == 1)
	_set_field_editable(_value_field, _view == "value" and _channel != "rotation" and _indices.size() == 1)
	var keys := _keys()
	if _indices.size() == 1 and int(_indices[0]) < keys.size():
		var key: Dictionary = keys[int(_indices[0])]
		_time_field.set_value_silent(float(key["time"]))
		var scalar = _value_scalar(key["value"])
		_value_field.set_value_silent(float(scalar) if scalar != null else 0.0)
	else:
		_time_field.set_value_silent(0.0)
		_value_field.set_value_silent(0.0)


func _on_resized() -> void:
	if _presets_button != null:
		var narrow := size.x < 420.0
		_presets_button.text = "" if narrow else "Presets"
		_presets_button.icon = Kit.icon_texture("curve") if narrow else null
		_presets_button.custom_minimum_size = Vector2(44, 44) if narrow else Vector2(96, 44)
		_presets_button.tooltip_text = "Curve family presets"
	_redraw()


func _on_time_committed(value: float) -> void:
	if _indices.size() != 1:
		return
	commit_key_edit(int(_indices[0]), value)


func _on_value_committed(value: float) -> void:
	if _indices.size() != 1 or _view != "value":
		return
	commit_key_edit(int(_indices[0]), float(_time_field.value), value)


func _open_ease_menu() -> void:
	if not easing_enabled():
		return
	var menu := PopupMenu.new()
	menu.add_theme_font_size_override("font_size", Kit.TYPE_CAPTION)
	var presets := [
		{"name": "Hold", "value": 0.0},
		{"name": "Ease out strong", "value": 0.25},
		{"name": "Ease out", "value": 0.5},
		{"name": "Soft out", "value": 0.75},
		{"name": "Linear", "value": 1.0},
		{"name": "Soft in", "value": 1.35},
		{"name": "Ease in", "value": 2.0},
		{"name": "Ease in strong", "value": 3.0},
	]
	for preset in presets:
		menu.add_item(str(preset["name"]))
		menu.set_item_metadata(menu.item_count - 1, float(preset["value"]))
	add_child(menu)
	menu.id_pressed.connect(func(index: int) -> void:
		apply_easing(float(menu.get_item_metadata(index)))
		menu.queue_free()
	)
	menu.popup_on_parent(Rect2(Vector2(size.x * 0.5, HEADER_H), Vector2(1, 1)))


func _open_presets_menu() -> void:
	if not curve_enabled() or _presets_menu == null:
		return
	_presets_menu.popup_on_parent(Rect2(Vector2(size.x * 0.5, HEADER_H), Vector2(1, 1)))


# --- Drawing -------------------------------------------------------------

func _redraw() -> void:
	if _plot != null:
		_plot.queue_redraw()


func _draw_plot() -> void:
	var w := _plot.size.x
	var h := _plot.size.y
	_plot.draw_rect(Rect2(0, 0, w, h), Kit.SURFACE)
	var plot := Rect2(8.0, 20.0, maxf(0.0, w - 16.0), maxf(0.0, h - 28.0))
	_plot.draw_rect(plot, Kit.SURFACE)
	for frac in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var y := plot.position.y + plot.size.y * float(frac)
		_plot.draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y),
			Kit.BORDER_SOFT * Color(1, 1, 1, 0.55), 1.0)
	var major := _major_step()
	var tick := floorf(_time_start / major) * major
	while tick <= _time_end + 0.0001:
		if tick >= _time_start - 0.0001:
			var x := plot.position.x + (tick - _time_start) / maxf(0.0001, _time_end - _time_start) * plot.size.x
			_plot.draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y),
				Kit.BORDER_SOFT * Color(1, 1, 1, 0.35), 1.0)
			_plot.draw_string(Kit.font_mono, Vector2(x + 3.0, 14.0),
				"%.1fs" % tick if major < 1.0 else "%ds" % int(round(tick)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.TYPE_RULER, Kit.TEXT_MUTED)
		tick += major
	var caption := empty_state()
	if caption != "":
		_plot.draw_string(Kit.font_for(400), Vector2(plot.position.x + 12.0, plot.position.y + plot.size.y * 0.5),
			caption, HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, plot.size.x - 24.0),
			Kit.TYPE_CAPTION, Kit.TEXT_DIM)
		_draw_playhead(plot)
		return
	if _view == "value" and _channel == "rotation":
		_plot.draw_string(Kit.font_for(400), Vector2(plot.position.x + 8.0, 14.0),
			"Euler degrees · time editing only", HORIZONTAL_ALIGNMENT_LEFT,
			maxf(0.0, plot.size.x - 16.0), Kit.TYPE_RULER, Kit.TEXT_DIM)
	var samples := 96
	var points := PackedVector2Array()
	for i in range(samples):
		var t := lerpf(_time_start, _time_end, float(i) / float(samples - 1))
		var scalar
		if _view == "speed":
			scalar = _speed_at(t)
		else:
			scalar = _sample_scalar(t)
		if scalar == null:
			continue
		var y := plot.position.y + (1.0 - (float(scalar) - _value_min) / maxf(0.0001, _value_max - _value_min)) * plot.size.y
		var x := plot.position.x + float(i) / float(samples - 1) * plot.size.x
		points.append(Vector2(x, clampf(y, plot.position.y, plot.end.y)))
	if points.size() >= 2:
		_plot.draw_polyline(points, Kit.FOCUS_BRIGHT * Color(1, 1, 1, 0.9), 1.4, true)
	var keys := _keys()
	for i in range(keys.size()):
		var key: Dictionary = keys[i]
		if float(key["time"]) < _time_start - 0.0001 or float(key["time"]) > _time_end + 0.0001:
			continue
		var scalar = _value_scalar(key["value"])
		if scalar == null:
			continue
		var x := plot.position.x + (float(key["time"]) - _time_start) / maxf(0.0001, _time_end - _time_start) * plot.size.x
		var y := plot.position.y + (1.0 - (float(scalar) - _value_min) / maxf(0.0001, _value_max - _value_min)) * plot.size.y
		var selected := _indices.has(i)
		var r := 5.5 if selected else 4.0
		var color := Kit.FOCUS_BRIGHT if selected else Kit.ACCENT
		_plot.draw_colored_polygon(PackedVector2Array([
			Vector2(x, y - r), Vector2(x + r, y), Vector2(x, y + r), Vector2(x - r, y)
		]), color)
	_draw_playhead(plot)


func _draw_playhead(plot: Rect2) -> void:
	if doc == null:
		return
	var x := plot.position.x + (float(doc.current_time) - _time_start) / maxf(0.0001, _time_end - _time_start) * plot.size.x
	if x < plot.position.x - 1.0 or x > plot.end.x + 1.0:
		return
	_plot.draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Kit.TIME, 1.2)
	_plot.draw_colored_polygon(PackedVector2Array([
		Vector2(x - 4, plot.position.y), Vector2(x + 4, plot.position.y), Vector2(x, plot.position.y + 5)
	]), Kit.TIME)


func _speed_at(time: float) -> Variant:
	if doc == null or _object_id == "":
		return null
	var dt := 1.0 / 240.0
	var a = _sample_scalar(maxf(_time_start, time - dt))
	var b = _sample_scalar(minf(_time_end, time + dt))
	if a == null or b == null:
		return null
	return absf(float(b) - float(a)) / maxf(0.0001, 2.0 * dt)


func _major_step() -> float:
	var span := maxf(0.1, _time_end - _time_start)
	for step in [0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0]:
		if span / float(step) <= 8.0:
			return float(step)
	return 120.0


# --- Plot input ----------------------------------------------------------

func _on_plot_input(event: InputEvent) -> void:
	if doc == null or _object_id == "":
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_press_plot(button.position)
		else:
			_release_plot(button.position)
		_plot.accept_event()
	elif event is InputEventMouseMotion and _drag_mode != "":
		_drag_plot((event as InputEventMouseMotion).position)
		_plot.accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touches[int(touch.index)] = touch.position
			if _touches.size() == 1:
				_press_plot(touch.position)
			else:
				_pinch_dist = _touch_distance()
				_pinch_mid = _touch_mid()
				_drag_mode = ""
		else:
			_touches.erase(int(touch.index))
			if _touches.is_empty():
				_release_plot(touch.position)
			_pinch_dist = -1.0
		_plot.accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_touches[int(drag.index)] = drag.position
		if _touches.size() >= 2:
			var distance := _touch_distance()
			var mid := _touch_mid()
			if _pinch_dist > 4.0 and distance > 4.0:
				_zoom_time(_pinch_dist / distance, _x_to_time(mid.x))
			_pan_time(-(mid.x - _pinch_mid.x) / maxf(1.0, _plot.size.x) * (_time_end - _time_start))
			_pinch_dist = distance
			_pinch_mid = mid
		else:
			_drag_plot(drag.position)
		_plot.accept_event()


func _press_plot(pos: Vector2) -> void:
	var key := _key_at(pos)
	if key >= 0:
		if _multi:
			var next := Array(_indices)
			if next.has(key):
				next.erase(key)
			else:
				next.append(key)
			next.sort()
			_indices = PackedInt32Array(next)
		else:
			_indices = PackedInt32Array([key])
		_drag_mode = "key"
		_drag_start = pos
		_drag_indices = _indices.duplicate()
		_emit_selection()
		_sync_fields()
		_sync_header()
		_redraw()
		return
	_indices = PackedInt32Array()
	_emit_selection()
	_sync_fields()
	_sync_header()
	if pos.y < 20.0:
		doc.seek(_x_to_time(pos.x))
	_redraw()


func _drag_plot(pos: Vector2) -> void:
	if _drag_mode != "key" or _drag_indices.is_empty():
		return
	_drag_time = _x_to_time(pos.x)
	_redraw()


func _release_plot(pos: Vector2) -> void:
	if _drag_mode != "key" or _drag_indices.is_empty():
		_drag_mode = ""
		return
	var dx := pos.x - _drag_start.x
	var dy := pos.y - _drag_start.y
	_drag_mode = ""
	if absf(dx) < 3.0 and absf(dy) < 3.0:
		return
	var keys := _keys()
	var edits: Array = []
	for raw in _drag_indices:
		var index := int(raw)
		if index < 0 or index >= keys.size():
			continue
		var entry := {"index": index}
		if absf(dx) >= 3.0:
			var delta := dx / maxf(1.0, _plot.size.x) * (_time_end - _time_start)
			var new_time := float(keys[index]["time"]) + delta
			if doc.snap:
				new_time = snappedf(new_time, 1.0 / float(doc.fps))
			entry["time"] = clampf(new_time, 0.0, doc.duration)
		if absf(dy) >= 3.0 and _view == "value" and _channel != "rotation":
			var span := _value_max - _value_min
			var delta_value := -dy / maxf(1.0, _plot.size.y) * span
			var current = keys[index]["value"]
			var scalar = _value_scalar(current)
			if scalar != null:
				entry["value"] = _typed_value(float(scalar) + delta_value)
		edits.append(entry)
	if edits.is_empty():
		return
	var result: Dictionary = doc.apply_key_edits(_object_id, _channel, edits, "Edit keys")
	if bool(result.get("ok", false)):
		_indices = PackedInt32Array()
		for raw in result["indices"]:
			_indices.append(int(raw))
		_emit_selection()
		_sync_fields()
		_sync_header()
	_redraw()


func _key_at(pos: Vector2) -> int:
	var keys := _keys()
	if keys.is_empty():
		return -1
	var plot := Rect2(8.0, 20.0, maxf(0.0, _plot.size.x - 16.0), maxf(0.0, _plot.size.y - 28.0))
	var best := -1
	var best_dist := 16.0
	for i in range(keys.size()):
		var scalar = _value_scalar(keys[i]["value"])
		if scalar == null:
			continue
		var x := plot.position.x + (float(keys[i]["time"]) - _time_start) / maxf(0.0001, _time_end - _time_start) * plot.size.x
		var y := plot.position.y + (1.0 - (float(scalar) - _value_min) / maxf(0.0001, _value_max - _value_min)) * plot.size.y
		var dist := Vector2(x, y).distance_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = i
	return best


func _touch_distance() -> float:
	var keys := _touches.keys()
	if keys.size() < 2:
		return -1.0
	return Vector2(_touches[keys[0]]).distance_to(Vector2(_touches[keys[1]]))


func _touch_mid() -> Vector2:
	var keys := _touches.keys()
	if keys.size() < 2:
		return Vector2.ZERO
	return (Vector2(_touches[keys[0]]) + Vector2(_touches[keys[1]])) * 0.5


func _x_to_time(x: float) -> float:
	var plot_left := 8.0
	var plot_width := maxf(1.0, _plot.size.x - 16.0)
	return _time_start + (x - plot_left) / plot_width * (_time_end - _time_start)


func _zoom_time(factor: float, anchor: float) -> void:
	var span := clampf((_time_end - _time_start) * factor, 0.1, maxf(0.1, doc.duration))
	var frac := 0.5 if _time_end - _time_start <= 0.0001 else (anchor - _time_start) / (_time_end - _time_start)
	_time_start = clampf(anchor - span * frac, 0.0, maxf(0.0, doc.duration - span))
	_time_end = _time_start + span
	_redraw()


func _pan_time(delta: float) -> void:
	var span := _time_end - _time_start
	_time_start = clampf(_time_start + delta, 0.0, maxf(0.0, doc.duration - span))
	_time_end = _time_start + span
	_redraw()
