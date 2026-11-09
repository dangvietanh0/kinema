extends Control
## The segment graph: one editable time/value interval from the selected
## channel, with real cubic handles, a preset rail and the engine-ease fallback.
##
## It samples the document's Animation resource for the drawn curve and always
## edits through Document bake APIs, so playback and export see exactly the
## keys the graph shows.

signal notice(text: String)
signal span_selected(span: Dictionary)
signal span_changed
signal tab_changed(tab: String)
signal key_selected(index: int)
signal key_info_requested(index: int)

const DocumentScript = preload("res://src/core/document.gd")
const NumberFieldScript = preload("res://src/ui/num_field.gd")
const SpeedCurveScript = preload("res://src/core/speed_curve.gd")

const MIN_PLOT_H := 120.0
const HIT_RADIUS := 22.0
const TAB_EASE := "ease"
const TAB_VALUE := "value"
const TAB_SPEED := "speed"

const RULER_H := 44.0
const RAIL_H := 44.0
const PAD_X := 16.0
const BOTTOM_GUTTER := 28.0

const PRESET_DEFS := [
	{"id": "linear", "label": "Linear", "family": "cubic", "x1": 1.0 / 3.0, "y1": 1.0 / 3.0, "x2": 2.0 / 3.0, "y2": 2.0 / 3.0},
	{"id": "ease_in", "label": "Ease in", "family": "cubic", "x1": 0.42, "y1": 0.0, "x2": 1.0, "y2": 1.0},
	{"id": "ease_out", "label": "Ease out", "family": "cubic", "x1": 0.0, "y1": 0.0, "x2": 0.58, "y2": 1.0},
	{"id": "ease_in_out", "label": "Ease in-out", "family": "cubic", "x1": 0.42, "y1": 0.0, "x2": 0.58, "y2": 1.0},
	{"id": "slow_in_fast_out", "label": "Slow in, fast out", "family": "cubic", "x1": 0.7, "y1": 0.0, "x2": 1.0, "y2": 1.0},
	{"id": "back_out", "label": "Back out", "family": "cubic", "x1": 0.34, "y1": 1.56, "x2": 0.64, "y2": 1.0},
	{"id": "bounce", "label": "Bounce", "family": "preset", "curve": "bounce_out"},
	{"id": "elastic", "label": "Elastic", "family": "preset", "curve": "elastic_out"},
	{"id": "spring", "label": "Spring", "family": "preset", "curve": "spring"},
]

const TAB_IDS := [TAB_EASE, TAB_VALUE, TAB_SPEED]
const TAB_LABELS := {"ease": "Ease", "value": "Value", "speed": "Speed"}

var doc: DocumentScript = null

var _object_id := ""
var _channel := "position"
var _component := "all"
var _tab := TAB_EASE
var _span: Dictionary = {}
var _preview_handles: Dictionary = {}

var _rail_scroll: ScrollContainer
var _rail_row: HBoxContainer
var _preset_chips: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _tab_holder: HBoxContainer
var _engine_field
var _bake_ease_button: Button
var _convert_button: Button
var _clear_button: Button
var _edit_ease_button: Button
var _baked_badge: Label

var _dragging_handle := ""
var _drag_handle_start := Vector2.ZERO
var _selected_key := -1
var _press_key := -1
var _press_position := Vector2.ZERO
var _press_time := 0.0
var _press_value := 0.0
var _press_plot := Rect2()
var _press_window := Vector2.ZERO
var _press_range := Vector2.ZERO
var _press_curve := Rect2()
var _connected := false

# The plot converts thousands of points per draw. Resolving the selection and
# resampling the value range inside every conversion is quadratic, so both are
# cached until the document, selection, tab or component actually changes.
var _window_cache := Vector2.ZERO
var _window_cache_valid := false
var _range_cache := Vector2.ZERO
var _range_cache_valid := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_NONE
	if _rail_row == null:
		_build_controls()
	resized.connect(_layout_controls)
	_layout_controls()
	queue_redraw()


func setup(document: Node3D) -> void:
	doc = document as DocumentScript
	if _rail_row == null:
		_build_controls()
	if doc != null and not _connected:
		_connected = true
		doc.keyframes_changed.connect(_on_keyframes_changed)
		doc.playback_changed.connect(_on_playback_changed)
		doc.selection_changed.connect(_on_selection_changed)
		doc.object_changed.connect(_on_object_changed)
		doc.scene_changed.connect(_on_scene_changed)
	refresh()


func set_context(object_id: String, channel: String) -> void:
	if _rail_row == null:
		_build_controls()
	if _object_id == object_id and _channel == channel:
		refresh()
		return
	_object_id = object_id
	_channel = channel if channel in DocumentScript.CHANNELS else "position"
	_span = {}
	_preview_handles = {}
	_selected_key = -1
	refresh()


func context_object() -> String:
	return _object_id


func context_channel() -> String:
	return _channel


func set_selection(span: Dictionary) -> void:
	_span = span.duplicate(true) if not span.is_empty() else {}
	_preview_handles = {}
	refresh()


func selection() -> Dictionary:
	return _span.duplicate(true)


func clear_selection() -> void:
	_span = {}
	_preview_handles = {}
	_selected_key = -1
	refresh()


func refresh() -> void:
	_invalidate_plot_caches()
	_resolve_selection()
	_sync_actions()
	queue_redraw()


func _invalidate_plot_caches() -> void:
	_window_cache_valid = false
	_range_cache_valid = false


func set_tab(tab: String) -> void:
	if not (tab in TAB_IDS):
		return
	var changed := tab != _tab
	_tab = tab
	for id in _tab_buttons.keys():
		var button: Button = _tab_buttons[id]
		if button != null and is_instance_valid(button):
			button.set_pressed_no_signal(id == _tab)
	_invalidate_plot_caches()
	_sync_actions()
	queue_redraw()
	if changed:
		tab_changed.emit(_tab)


func tab() -> String:
	return _tab


func set_component(component: String) -> void:
	var next := component.to_lower()
	if not (next in ["all", "x", "y", "z"]):
		return
	_component = next
	_invalidate_plot_caches()
	queue_redraw()


func component() -> String:
	return _component


func value_editable() -> bool:
	## A single component of a vector channel can be dragged in the Value tab.
	## `All` is a read-only overview, Speed is read-only, and quaternions belong
	## to the rig gizmo.
	return _tab == TAB_VALUE and doc != null and _object_id != "" \
		and _channel in ["position", "scale"] \
		and _component in ["x", "y", "z"]


func value_hint() -> String:
	if _channel == "rotation":
		return "Rotation values are quaternion components; edit them with the rig gizmo."
	if _component == "all":
		return "Choose X, Y or Z to edit values."
	return "Drag a key to edit its time and value."


func plot_rect() -> Rect2:
	var top := RULER_H + (RAIL_H if rail_visible() else 0.0)
	var height := maxf(0.0, size.y - top)
	return Rect2(PAD_X, top, maxf(0.0, size.x - PAD_X * 2.0), height)


func rail_visible() -> bool:
	return size.y - RULER_H - RAIL_H >= MIN_PLOT_H


func time_to_point(t: float) -> Vector2:
	var plot := plot_rect()
	var window := _window()
	var span := maxf(0.000001, window.y - window.x)
	var x := plot.position.x + (t - window.x) / span * plot.size.x
	var curve := _curve_rect()
	var value: Variant = _sample(t)
	var y := curve.position.y + curve.size.y * 0.5
	if value != null:
		y = _value_to_y(_scalar(value))
	return Vector2(x, y)


func point_to_time(p: Vector2) -> float:
	return _time_at_point(p, plot_rect(), _window())


func _time_at_point(p: Vector2, plot: Rect2, window: Vector2) -> float:
	if plot.size.x <= 0.0:
		return window.x
	return window.x + (p.x - plot.position.x) / plot.size.x * (window.y - window.x)


func handle_positions() -> Dictionary:
	if _tab != TAB_EASE:
		return {}
	if not _preview_handles.is_empty():
		return _preview_handles.duplicate(true)
	var handles := _authored_handles()
	if handles.is_empty():
		return {}
	var span := _active_span()
	if span.is_empty():
		return {}
	var pair := _handle_points(span, handles)
	return {"out": pair[0], "in": pair[1]}


func handle_hit_radius() -> float:
	return HIT_RADIUS


func key_hit_radius() -> float:
	return HIT_RADIUS


func key_points() -> Array:
	if doc == null or _object_id == "":
		return []
	var keys: Array = doc.get_channel_keys(_object_id, _channel)
	var out: Array = []
	for key in keys:
		var time := float(key["time"])
		out.append({
			"index": int(key["index"]),
			"position": time_to_point(time),
			"time": time,
			"value": key["value"],
			"component": _scalar(key["value"]),
		})
	return out


func handle_drag(out_position: Vector2, in_position: Vector2) -> bool:
	var span := _active_span()
	if span.is_empty():
		notice.emit("Select a segment before shaping its handles.")
		return false
	var out_handle := _point_to_handle(span, out_position)
	var in_handle := _point_to_handle(span, in_position)
	return _bake_handles(span,
		clampf(out_handle.x, 0.0, 1.0), clampf(out_handle.y, -2.0, 3.0),
		clampf(in_handle.x, 0.0, 1.0), clampf(in_handle.y, -2.0, 3.0))


func preset_chip(preset_id: String) -> Button:
	return _preset_chips.get(preset_id)


func preset_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for def in PRESET_DEFS:
		ids.append(str(def["id"]))
	return ids


func engine_ease_visible() -> bool:
	if _tab != TAB_EASE:
		return false
	var span := _active_span()
	if span.is_empty():
		return false
	if not _record_for_span(span).is_empty():
		return false
	return absf(_start_transition() - 1.0) > 0.001


func bake_ease_button() -> Button:
	return _bake_ease_button


func convert_button() -> Button:
	return _convert_button


func clear_button() -> Button:
	return _clear_button


func tab_button(tab_id: String) -> Button:
	return _tab_buttons.get(tab_id)


func edit_ease_button() -> Button:
	return _edit_ease_button


func baked_label() -> String:
	var record := _record_for_span(_active_span())
	if record.is_empty():
		return ""
	if str(record.get("family", "")) in ["preset", "baked"]:
		return "Baked preset"
	return ""


func baked_badge() -> Label:
	return _baked_badge


func bake_ease_available() -> bool:
	return engine_ease_visible()


func convert_available() -> bool:
	var record := _record_for_span(_active_span())
	return not record.is_empty() and str(record.get("family", "")) in ["preset", "baked"]


func clear_available() -> bool:
	return not _record_for_span(_active_span()).is_empty()


func edit_ease_available() -> bool:
	return _tab != TAB_EASE


func speed_summary() -> Dictionary:
	var span := _active_span()
	var start := 0.0
	var end: float = doc.duration if doc != null else 0.0
	if not span.is_empty():
		start = float(span.get("start", 0.0))
		end = float(span.get("end", end))
	if doc == null or _object_id == "" or end <= start:
		return {"average": 0.0, "peak": 0.0}
	var dt := 1.0 / maxf(1.0, float(doc.fps))
	var total := 0.0
	var peak := 0.0
	var samples := 0
	var t := start
	while t < end - 0.0000001:
		var next := minf(t + dt, end)
		var speed := _speed_between(t, next)
		if is_finite(speed):
			total += speed
			peak = maxf(peak, speed)
			samples += 1
		t = next
	if samples == 0:
		return {"average": 0.0, "peak": 0.0}
	return {"average": total / float(samples), "peak": peak}


func _speed_at(time: float) -> float:
	if doc == null:
		return 0.0
	var dt := 1.0 / maxf(1.0, float(doc.fps))
	var t0 := clampf(time, 0.0, doc.duration)
	var t1 := minf(t0 + dt, doc.duration)
	return _speed_between(t0, t1)


func _speed_between(t0: float, t1: float) -> float:
	var span := t1 - t0
	if span <= 0.0000001:
		return 0.0
	var a: Variant = _sample(t0)
	var b: Variant = _sample(t1)
	if a == null or b == null:
		return 0.0
	var speed := 0.0
	if a is Quaternion and b is Quaternion:
		var q0 := (a as Quaternion).normalized()
		var q1 := (b as Quaternion).normalized()
		speed = 2.0 * acos(clampf(q0.dot(q1), -1.0, 1.0)) / span
	elif a is Vector3 and b is Vector3:
		speed = ((b as Vector3) - (a as Vector3)).length() / span
	else:
		speed = absf(float(b) - float(a)) / span
	return speed if is_finite(speed) else 0.0


func add_key_at_playhead() -> bool:
	if doc == null or _object_id == "" or not (_channel in DocumentScript.CHANNELS):
		_notify("Select an object and channel first.")
		return false
	var sampled: Variant = doc.sample_channel(_object_id, _channel, doc.current_time)
	if sampled == null:
		_notify("No keys on this channel. Insert a key at the playhead.")
		return false
	var result: Dictionary = doc.apply_key_edits(_object_id, _channel, [
		{"index": -1, "time": doc.current_time, "value": sampled},
	], "Add key")
	if not bool(result.get("ok", false)):
		_notify(str(result.get("error", "Could not insert the key.")))
		return false
	var indices: Array = result.get("indices", [])
	_selected_key = int(indices[0]) if not indices.is_empty() else -1
	refresh()
	if _selected_key >= 0:
		key_selected.emit(_selected_key)
	span_changed.emit()
	return true


func delete_selected_key() -> void:
	if doc == null or _object_id == "" or _selected_key < 0:
		return
	var keys: Array = doc.get_channel_keys(_object_id, _channel)
	if _selected_key >= keys.size():
		_selected_key = -1
		return
	var result: Dictionary = doc.apply_key_edits(_object_id, _channel, [
		{"index": _selected_key, "delete": true},
	], "Delete key")
	if bool(result.get("ok", false)):
		_selected_key = -1
		refresh()
		span_changed.emit()


func selected_key_info() -> Dictionary:
	if doc == null or _object_id == "" or _selected_key < 0:
		return {}
	var keys: Array = doc.get_channel_keys(_object_id, _channel)
	if _selected_key >= keys.size():
		return {}
	var key: Dictionary = keys[_selected_key]
	return {
		"index": _selected_key,
		"time": float(key["time"]),
		"value": key["value"],
		"component": _component,
		"editable": value_editable(),
	}


func request_key_info() -> void:
	if _selected_key < 0:
		_notify("Select a key first.")
		return
	key_info_requested.emit(_selected_key)


## Direct manipulation used by the test harness and by the real touch path.
## One call is one document transaction; the caller never has to wrap it.
func drag_key(index: int, point: Vector2) -> bool:
	return _drag_key_to(index, point_to_time(point), _y_to_value(point.y))


## Shared drag body. `time` and `scalar` are already resolved against the view
## the user pressed in, so a selection-driven re-zoom cannot remap the release.
func _drag_key_to(index: int, time: float, scalar: float) -> bool:
	if doc == null or _object_id == "":
		return false
	var keys: Array = doc.get_channel_keys(_object_id, _channel)
	if index < 0 or index >= keys.size():
		return false
	if not value_editable():
		_notify(value_hint())
		return false
	if doc.snap and doc.fps > 0:
		time = roundf(time * float(doc.fps)) / float(doc.fps)
	var value: Vector3 = keys[index]["value"]
	match _component:
		"x":
			value.x = scalar
		"y":
			value.y = scalar
		"z":
			value.z = scalar
	var result: Dictionary = doc.move_key(_object_id, _channel, index, time, value)
	if not bool(result.get("ok", false)):
		_notify(str(result.get("error", "Curve data no longer matches these keys.")))
		return false
	_selected_key = int(result.get("index", -1))
	# The document may clamp or re-bake the requested time. Resolve the new
	# selection from the moved key's real time, never from the raw point.
	var moved_time := time
	var live: Array = doc.get_channel_keys(_object_id, _channel)
	if _selected_key >= 0 and _selected_key < live.size():
		moved_time = float(live[_selected_key]["time"])
	_span = doc.segment_span_at(_object_id, _channel, moved_time)
	refresh()
	if _selected_key >= 0:
		key_selected.emit(_selected_key)
	span_changed.emit()
	return true


## Private control binding used by the timeline header. The graph owns the real
## tab buttons so callers never get a fake control; the header may reparent and
## show them without losing the pressed state.
func bind_tab_buttons(parent: Control) -> void:
	if _tab_holder == null:
		_build_controls()
	for id in _tab_buttons.keys():
		var button: Button = _tab_buttons[id]
		if button.get_parent() == parent:
			continue
		if button.get_parent() != null:
			button.reparent(parent, false)
		else:
			parent.add_child(button)
		button.visible = true


# -------------------------------------------------------------------------
# Controls
# -------------------------------------------------------------------------

func _build_controls() -> void:
	if _rail_row != null:
		return
	_rail_scroll = ScrollContainer.new()
	_rail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_rail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rail_scroll.clip_contents = true
	_rail_scroll.focus_mode = Control.FOCUS_NONE
	add_child(_rail_scroll)
	_rail_row = HBoxContainer.new()
	_rail_row.add_theme_constant_override("separation", 4)
	_rail_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rail_scroll.add_child(_rail_row)

	for def in PRESET_DEFS:
		var chip := Kit.text_button(str(def["label"]), "", false, true)
		chip.toggle_mode = true
		chip.focus_mode = Control.FOCUS_NONE
		chip.custom_minimum_size = Vector2(maxf(44.0, chip.get_combined_minimum_size().x), RAIL_H)
		chip.add_theme_font_size_override("font_size", Kit.TYPE_CAPTION)
		var id := str(def["id"])
		chip.pressed.connect(_on_preset_pressed.bind(id))
		_rail_row.add_child(chip)
		_preset_chips[id] = chip

	_engine_field = NumberFieldScript.new()
	_engine_field.axis = "E"
	_engine_field.suffix = "×"
	_engine_field.min_value = 0.0
	_engine_field.max_value = 4.0
	_engine_field.step = 0.01
	_engine_field.custom_minimum_size = Vector2(96, RAIL_H)
	_engine_field.text_committed.connect(_on_engine_committed)
	_rail_row.add_child(_engine_field)

	_bake_ease_button = _action_button("Bake ease", _on_bake_ease_pressed)
	_convert_button = _action_button("Convert to cubic", _on_convert_pressed)
	_clear_button = _action_button("Clear curve", _on_clear_pressed)
	_edit_ease_button = _action_button("Edit ease", func() -> void:
		set_tab(TAB_EASE)
	)
	_edit_ease_button.visible = false

	# A rendered family badge, not only an accessor: it sits in the ruler so it
	# survives the rail being hidden at the 800x360 budget.
	_baked_badge = Label.new()
	_baked_badge.text = "Baked preset"
	_baked_badge.add_theme_font_size_override("font_size", Kit.TYPE_CAPTION)
	_baked_badge.add_theme_color_override("font_color", Kit.TEXT_MUTED)
	_baked_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_baked_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_baked_badge.visible = false
	add_child(_baked_badge)

	# Real tab buttons. The timeline's graph header adopts them in Task 17;
	# until then they stay in this hidden holder so the API is already real.
	_tab_holder = HBoxContainer.new()
	_tab_holder.visible = false
	add_child(_tab_holder)
	for id in TAB_IDS:
		var button := Kit.text_button(str(TAB_LABELS.get(id, id)), "", false, true)
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(60, RAIL_H)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(set_tab.bind(id))
		_tab_holder.add_child(button)
		_tab_buttons[id] = button
	set_tab(_tab)
	_sync_actions()
	_layout_controls()


func _action_button(text_value: String, handler: Callable) -> Button:
	var button := Kit.text_button(text_value, "", false, false)
	button.custom_minimum_size = Vector2(96, RAIL_H)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(handler)
	_rail_row.add_child(button)
	return button


func _layout_controls() -> void:
	if _rail_scroll == null:
		return
	var visible_rail := rail_visible()
	_rail_scroll.visible = visible_rail
	_rail_scroll.position = Vector2(0.0, RULER_H)
	_rail_scroll.size = Vector2(size.x, RAIL_H)
	_engine_field.visible = engine_ease_visible()
	_rail_scroll.queue_sort()
	if _baked_badge != null:
		_baked_badge.position = Vector2(maxf(PAD_X, size.x - 160.0), 4.0)
		_baked_badge.size = Vector2(144.0, 18.0)


func _sync_actions() -> void:
	if _bake_ease_button == null:
		return
	var span := _active_span()
	var record := _record_for_span(span)
	var engine := engine_ease_visible()
	_bake_ease_button.visible = bake_ease_available()
	_engine_field.visible = engine
	_convert_button.visible = convert_available()
	_clear_button.visible = clear_available()
	_edit_ease_button.visible = _tab == TAB_SPEED
	if _baked_badge != null:
		var baked_text := baked_label()
		_baked_badge.text = baked_text
		_baked_badge.visible = baked_text != ""
	if engine:
		var start_index := _start_key_index(span)
		if start_index >= 0:
			_engine_field.set_value_silent(doc.get_key_transition(_object_id, _channel, start_index))
	var checked := _checked_preset(record, span)
	for id in _preset_chips.keys():
		var chip: Button = _preset_chips[id]
		chip.set_pressed_no_signal(id == checked)
	_layout_controls()


func _checked_preset(record: Dictionary, span: Dictionary) -> String:
	if record.is_empty():
		if span.is_empty():
			return ""
		if absf(_start_transition() - 1.0) <= 0.001:
			return "linear"
		return ""
	if str(record.get("family", "")) != "cubic":
		return ""
	var x1 := float(record.get("x1", 0.0))
	var y1 := float(record.get("y1", 0.0))
	var x2 := float(record.get("x2", 0.0))
	var y2 := float(record.get("y2", 0.0))
	for def in PRESET_DEFS:
		if str(def["family"]) != "cubic":
			continue
		if absf(x1 - float(def["x1"])) <= 0.01 and absf(y1 - float(def["y1"])) <= 0.01 \
				and absf(x2 - float(def["x2"])) <= 0.01 and absf(y2 - float(def["y2"])) <= 0.01:
			return str(def["id"])
	return ""


func _on_preset_pressed(preset_id: String) -> void:
	if doc == null:
		return
	var span := _active_span()
	if span.is_empty():
		notice.emit("Select a segment before applying a preset.")
		return
	var def := _preset_def(preset_id)
	if def.is_empty():
		return
	var start := float(span.get("start", 0.0))
	var end := float(span.get("end", 0.0))
	var result: Dictionary
	if str(def["family"]) == "cubic":
		result = doc.bake_cubic_segment(_object_id, _channel, start, end,
			float(def["x1"]), float(def["y1"]), float(def["x2"]), float(def["y2"]), preset_id)
	else:
		result = doc.bake_curve_family_segment(_object_id, _channel, start, end, str(def["curve"]))
	_after_bake(span, result, str(def["label"]))


func _on_bake_ease_pressed() -> void:
	if doc == null:
		return
	var span := _active_span()
	var index := _start_key_index(span)
	if index < 0:
		notice.emit("Curve data no longer matches these keys.")
		return
	var result: Dictionary = doc.bake_engine_ease(_object_id, _channel, index)
	_after_bake(span, result, "Bake ease")


func _on_convert_pressed() -> void:
	if doc == null:
		return
	var span := _active_span()
	if span.is_empty():
		return
	var result: Dictionary = doc.convert_segment_to_cubic(_object_id, _channel,
		float(span.get("start", 0.0)), float(span.get("end", 0.0)))
	_after_bake(span, result, "Convert to cubic")


func _on_clear_pressed() -> void:
	if doc == null:
		return
	var span := _active_span()
	if span.is_empty():
		return
	var result: Dictionary = doc.clear_curve_segment(_object_id, _channel,
		float(span.get("start", 0.0)), float(span.get("end", 0.0)))
	if bool(result.get("ok", false)):
		_span = doc.segment_span_at(_object_id, _channel,
			float(span.get("start", 0.0)) + 0.000001)
		_notify("Curve cleared.")
	else:
		_notify(str(result.get("reason", "Curve data no longer matches these keys.")))
	refresh()
	span_changed.emit()


func _on_engine_committed(value: float) -> void:
	if doc == null:
		return
	var span := _active_span()
	var index := _start_key_index(span)
	if index < 0:
		return
	doc.begin_edit("Edit engine ease")
	doc.set_key_transition(_object_id, _channel, index, clampf(value, 0.0, 4.0))
	doc.end_edit()
	refresh()
	span_changed.emit()


func _after_bake(old_span: Dictionary, result: Dictionary, label: String) -> void:
	if bool(result.get("ok", false)):
		var start := float(old_span.get("start", 0.0))
		var end := float(old_span.get("end", 0.0))
		_span = doc.segment_span_at(_object_id, _channel, (start + end) * 0.5)
		_notify("%s applied." % label)
	else:
		_notify(str(result.get("reason", "Curve data no longer matches these keys.")))
	refresh()
	span_changed.emit()


# -------------------------------------------------------------------------
# Selection and handles
# -------------------------------------------------------------------------

func _active_span() -> Dictionary:
	if doc == null or _object_id == "":
		return {}
	if _span.is_empty():
		return {}
	return _resolve_selection()


func _resolve_selection() -> Dictionary:
	if _span.is_empty():
		return {}
	if str(_span.get("object", "")) != _object_id \
			or str(_span.get("channel", "")) != _channel:
		_span = {}
		return {}
	var kind := str(_span.get("kind", "plain"))
	var start := float(_span.get("start", 0.0))
	var end := float(_span.get("end", 0.0))
	if kind == "record":
		var record := _record_for_span(_span)
		if record.is_empty():
			return _fallback_selection()
		return {
			"object": _object_id,
			"channel": _channel,
			"start": float(record.get("start", start)),
			"end": float(record.get("end", end)),
			"kind": "record",
			"record": record.duplicate(true),
		}
	var keys := doc.get_channel_keys(_object_id, _channel)
	var has_start := false
	var has_end := false
	for key in keys:
		if absf(float(key["time"]) - start) <= 0.001:
			has_start = true
		if absf(float(key["time"]) - end) <= 0.001:
			has_end = true
	if has_start and has_end:
		return {
			"object": _object_id,
			"channel": _channel,
			"start": start,
			"end": end,
			"kind": "plain",
		}
	return _fallback_selection()


func _fallback_selection() -> Dictionary:
	var resolved := doc.segment_span_at(_object_id, _channel, doc.current_time)
	_span = resolved.duplicate(true)
	return _span


func _record_for_span(span: Dictionary) -> Dictionary:
	if doc == null or span.is_empty() or str(span.get("kind", "")) != "record":
		return {}
	var start := float(span.get("start", 0.0))
	var end := float(span.get("end", 0.0))
	# Always resolve against the live clip. A selection may still carry the
	# record copy it was built from after an undo removed it.
	for record in doc.segments_for(_object_id, _channel):
		if absf(float(record.get("start", 0.0)) - start) <= 0.001 \
				and absf(float(record.get("end", 0.0)) - end) <= 0.001:
			return record
	return {}


func _authored_handles() -> Dictionary:
	var span := _active_span()
	if span.is_empty():
		return {}
	var record := _record_for_span(span)
	if not record.is_empty():
		if str(record.get("family", "")) != "cubic":
			return {}
		return {
			"x1": float(record.get("x1", 1.0 / 3.0)),
			"y1": float(record.get("y1", 1.0 / 3.0)),
			"x2": float(record.get("x2", 2.0 / 3.0)),
			"y2": float(record.get("y2", 2.0 / 3.0)),
		}
	if absf(_start_transition() - 1.0) <= 0.001:
		return {"x1": 1.0 / 3.0, "y1": 1.0 / 3.0, "x2": 2.0 / 3.0, "y2": 2.0 / 3.0}
	return {}


func _handle_points(span: Dictionary, handles: Dictionary) -> Array:
	var plot := plot_rect()
	var curve := _curve_rect()
	var start := float(span.get("start", 0.0))
	var end := float(span.get("end", 0.0))
	var duration := maxf(0.000001, end - start)
	var out_time := start + float(handles.get("x1", 1.0 / 3.0)) * duration
	var in_time := start + float(handles.get("x2", 2.0 / 3.0)) * duration
	var values := _segment_values(span)
	var out_value := lerpf(values.x, values.y, float(handles.get("y1", 1.0 / 3.0)))
	var in_value := lerpf(values.x, values.y, float(handles.get("y2", 2.0 / 3.0)))
	var out_point := Vector2(
		plot.position.x + (out_time - _window().x) / maxf(0.000001, _window().y - _window().x) * plot.size.x,
		_value_to_y(out_value))
	var in_point := Vector2(
		plot.position.x + (in_time - _window().x) / maxf(0.000001, _window().y - _window().x) * plot.size.x,
		_value_to_y(in_value))
	if curve.size.y <= 0.0:
		return [out_point, in_point]
	return [out_point, in_point]


func _point_to_handle(span: Dictionary, point: Vector2) -> Vector2:
	var start := float(span.get("start", 0.0))
	var end := float(span.get("end", 0.0))
	var time := point_to_time(point)
	var x := (time - start) / maxf(0.000001, end - start)
	var values := _segment_values(span)
	var curve := _curve_rect()
	var y := 0.5
	if absf(values.y - values.x) > 0.000001 and curve.size.y > 0.0:
		var value := _y_to_value(point.y)
		y = (value - values.x) / (values.y - values.x)
	elif curve.size.y > 0.0:
		y = 1.0 - (point.y - curve.position.y) / curve.size.y
	return Vector2(x, y)


func _bake_handles(span: Dictionary, x1: float, y1: float, x2: float, y2: float) -> bool:
	if doc == null:
		return false
	var result: Dictionary = doc.bake_cubic_segment(_object_id, _channel,
		float(span.get("start", 0.0)), float(span.get("end", 0.0)),
		clampf(x1, 0.0, 1.0), clampf(y1, -2.0, 3.0),
		clampf(x2, 0.0, 1.0), clampf(y2, -2.0, 3.0), "custom")
	if not bool(result.get("ok", false)):
		_notify(str(result.get("reason", "Curve data no longer matches these keys.")))
		_preview_handles = {}
		return false
	_preview_handles = {}
	_span = doc.segment_span_at(_object_id, _channel,
		(float(span.get("start", 0.0)) + float(span.get("end", 0.0))) * 0.5)
	refresh()
	span_changed.emit()
	return true


func _start_transition() -> float:
	var span := _active_span()
	var index := _start_key_index(span)
	if index < 0:
		return 1.0
	return doc.get_key_transition(_object_id, _channel, index)


func _start_key_index(span: Dictionary) -> int:
	if doc == null or span.is_empty() or _object_id == "":
		return -1
	var start := float(span.get("start", 0.0))
	var keys: Array = doc.get_channel_keys(_object_id, _channel)
	for key in keys:
		if absf(float(key["time"]) - start) <= 0.001:
			return int(key["index"])
	return -1


func _segment_values(span: Dictionary) -> Vector2:
	if doc == null or span.is_empty():
		return Vector2(0, 1)
	var start := float(span.get("start", 0.0))
	var end := float(span.get("end", 0.0))
	var a: Variant = _sample(start)
	var b: Variant = _sample(end)
	if a == null or b == null:
		return Vector2(0, 1)
	return Vector2(_scalar(a), _scalar(b))


# -------------------------------------------------------------------------
# Drawing
# -------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Kit.TIME_DARK)
	_draw_ruler()
	if doc == null:
		_draw_empty("Select an object to shape its curve.")
		return
	if _object_id == "":
		_draw_empty("Select an object to shape its curve.")
		return
	var keys: Array = doc.get_channel_keys(_object_id, _channel)
	if keys.is_empty():
		_draw_empty("No keys on this channel. Insert a key at the playhead.")
		return
	_draw_grid()
	_draw_selection_band()
	if _tab == TAB_VALUE:
		_draw_value_tab(keys)
	elif _tab == TAB_SPEED:
		_draw_speed_tab()
	else:
		_draw_curve(keys)
	_draw_keys(keys)
	_draw_handles()
	_draw_playhead()
	if _tab == TAB_VALUE:
		_draw_hint(value_hint())
	elif _tab == TAB_SPEED:
		_draw_hint("Speed is read-only.")
		_draw_speed_summary()


func _draw_hint(text_value: String) -> void:
	var plot := plot_rect()
	draw_string(Kit.font_for(400), Vector2(plot.position.x + 8.0, plot.position.y + 18.0),
		text_value, HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, plot.size.x - 16.0),
		Kit.TYPE_CAPTION, Kit.TEXT_DIM)


func _draw_value_tab(keys: Array) -> void:
	if _channel == "rotation":
		_draw_curve(keys)
		return
	if _component == "all":
		# Three thin achromatic curves: a real overview, not an editable plot.
		for component in ["x", "y", "z"]:
			_draw_component_curve(component)
		return
	_draw_curve(keys)


func _draw_component_curve(component: String) -> void:
	var plot := plot_rect()
	var curve := _curve_rect()
	if plot.size.x <= 1.0 or curve.size.y <= 1.0 or doc == null:
		return
	var columns := clampi(int(plot.size.x), 2, 900)
	var sampled := PackedVector2Array()
	for i in range(columns):
		var t := point_to_time(Vector2(plot.position.x + float(i), plot.position.y))
		var value: Variant = _sample(t)
		if value == null:
			continue
		var scalar := _value_scalar(value, component)
		sampled.append(Vector2(plot.position.x + float(i), _value_to_y(scalar)))
	if sampled.size() < 2:
		return
	var tint := Kit.TIME_BRIGHT * Color(1, 1, 1, 0.82)
	match component:
		"y":
			tint = Kit.TEXT_MUTED * Color(1, 1, 1, 0.82)
		"z":
			tint = Kit.TEXT_DIM * Color(1, 1, 1, 0.82)
	draw_polyline(sampled, tint, 1.0, true)


func _draw_empty(text: String) -> void:
	var plot := plot_rect()
	draw_string(Kit.font_for(400), Vector2(plot.position.x + 12.0, plot.position.y + 28.0),
		text, HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, plot.size.x - 24.0),
		Kit.TYPE_CAPTION, Kit.TEXT_DIM)


func _draw_ruler() -> void:
	draw_rect(Rect2(0.0, 0.0, size.x, RULER_H), Kit.SURFACE_2)
	draw_line(Vector2(0.0, RULER_H), Vector2(size.x, RULER_H), Kit.BORDER_SOFT, 1.0)
	var plot := plot_rect()
	if plot.size.x <= 0.0:
		return
	var window := _window()
	var px_per_second := plot.size.x / maxf(0.000001, window.y - window.x)
	var step := _time_step(px_per_second)
	var first := floorf(window.x / step) * step
	var tick := first
	while tick <= window.y + 0.000001:
		var x := plot.position.x + (tick - window.x) / maxf(0.000001, window.y - window.x) * plot.size.x
		if x >= plot.position.x - 1.0 and x <= plot.end.x + 1.0:
			draw_line(Vector2(x, RULER_H - 8.0), Vector2(x, RULER_H), Kit.BORDER, 1.0)
			if tick >= -0.0001:
				var label := "%.2fs" % tick if step < 1.0 else "%ds" % int(round(tick))
				draw_string(Kit.font_mono, Vector2(x + 3.0, RULER_H - 12.0),
					label, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.TYPE_RULER, Kit.TEXT_MUTED)
		tick += step


func _draw_grid() -> void:
	var plot := plot_rect()
	var window := _window()
	var px_per_second := plot.size.x / maxf(0.000001, window.y - window.x)
	var step := _time_step(px_per_second)
	var first := floorf(window.x / step) * step
	var tick := first
	while tick <= window.y + 0.000001:
		var x := plot.position.x + (tick - window.x) / maxf(0.000001, window.y - window.x) * plot.size.x
		if x >= plot.position.x and x <= plot.end.x:
			draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y - BOTTOM_GUTTER),
				Kit.BORDER_SOFT * Color(1, 1, 1, 0.55), 1.0)
		tick += step
	var curve := _curve_rect()
	for i in range(1, 4):
		var y := curve.position.y + curve.size.y * float(i) / 4.0
		draw_line(Vector2(curve.position.x, y), Vector2(curve.end.x, y),
			Kit.BORDER_SOFT * Color(1, 1, 1, 0.45), 1.0)
	var range_values := _value_range()
	for i in range(5):
		var value := lerpf(range_values.x, range_values.y, float(4 - i) / 4.0)
		var y := curve.position.y + curve.size.y * float(i) / 4.0
		draw_string(Kit.font_mono, Vector2(curve.position.x + 4.0, y + 10.0),
			_short_value(value), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Kit.TEXT_DIM)


func _draw_selection_band() -> void:
	var span := _active_span()
	if span.is_empty():
		return
	var plot := plot_rect()
	var curve := _curve_rect()
	var start_x := _time_to_x(float(span.get("start", 0.0)), plot)
	var end_x := _time_to_x(float(span.get("end", 0.0)), plot)
	var left := maxf(plot.position.x, start_x)
	var right := minf(plot.end.x, end_x)
	if right <= left:
		return
	draw_rect(Rect2(left, curve.position.y, right - left, curve.size.y),
		Kit.TIME * Color(1, 1, 1, 0.10))
	draw_line(Vector2(start_x, curve.position.y), Vector2(start_x, curve.end.y),
		Kit.TIME * Color(1, 1, 1, 0.55), 1.0)
	draw_line(Vector2(end_x, curve.position.y), Vector2(end_x, curve.end.y),
		Kit.TIME * Color(1, 1, 1, 0.55), 1.0)


func _draw_curve(keys: Array) -> void:
	var plot := plot_rect()
	var curve := _curve_rect()
	if plot.size.x <= 1.0 or curve.size.y <= 1.0:
		return
	var columns := clampi(int(plot.size.x), 2, 900)
	var sampled := PackedVector2Array()
	for i in range(columns):
		var t := point_to_time(Vector2(plot.position.x + float(i), plot.position.y))
		var value: Variant = _sample(t)
		if value == null:
			continue
		sampled.append(Vector2(plot.position.x + float(i), _value_to_y(_scalar(value))))
	if sampled.size() >= 2:
		draw_polyline(sampled, Kit.ACCENT * Color(1, 1, 1, 0.82), 1.2, true)
	var handles := _authored_handles()
	var span := _active_span()
	if handles.is_empty() or span.is_empty():
		_draw_key_polyline(keys)
		return
	var start := float(span.get("start", 0.0))
	var end := float(span.get("end", 0.0))
	var values := _segment_values(span)
	var points := PackedVector2Array()
	for i in range(64):
		var u := float(i) / 63.0
		var t := lerpf(start, end, u)
		var eased := SpeedCurveScript.cubic_ease(u, float(handles["x1"]), float(handles["y1"]),
			float(handles["x2"]), float(handles["y2"]))
		var value := lerpf(values.x, values.y, eased)
		points.append(Vector2(_time_to_x(t, plot), _value_to_y(value)))
	if points.size() >= 2:
		draw_polyline(points, Kit.TIME_BRIGHT, 2.0, true)


func _draw_key_polyline(keys: Array) -> void:
	var curve := _curve_rect()
	var points := PackedVector2Array()
	for key in keys:
		var value: Variant = key["value"]
		points.append(Vector2(_time_to_x(float(key["time"]), plot_rect()), _value_to_y(_scalar(value))))
	if points.size() >= 2:
		draw_polyline(points, Kit.ACCENT * Color(1, 1, 1, 0.7), 1.2, true)


func _draw_keys(keys: Array) -> void:
	if _tab == TAB_SPEED:
		return
	if _tab == TAB_VALUE and (_component == "all" or _channel == "rotation"):
		return
	var plot := plot_rect()
	var curve := _curve_rect()
	for key in keys:
		var time := float(key["time"])
		var x := _time_to_x(time, plot)
		if x < plot.position.x - 8.0 or x > plot.end.x + 8.0:
			continue
		var value: Variant = key["value"]
		var y := _value_to_y(_scalar(value))
		if y < curve.position.y - 8.0 or y > curve.end.y + 8.0:
			continue
		draw_circle(Vector2(x, y), 6.0, Kit.ACCENT_BRIGHT)
		draw_arc(Vector2(x, y), 6.0, 0.0, TAU, 18, Kit.TIME_DARK, 1.0, true)


func _draw_handles() -> void:
	if _tab != TAB_EASE:
		return
	var positions := handle_positions()
	if positions.is_empty():
		return
	for side in ["out", "in"]:
		var point: Vector2 = positions[side]
		draw_circle(point, 6.0, Kit.SURFACE)
		draw_arc(point, 6.0, 0.0, TAU, 20, Kit.TIME_BRIGHT, 2.0, true)


func _draw_playhead() -> void:
	if doc == null:
		return
	var plot := plot_rect()
	var curve := _curve_rect()
	var x := _time_to_x(doc.current_time, plot)
	if x < plot.position.x - 1.0 or x > plot.end.x + 1.0:
		return
	draw_line(Vector2(x, curve.position.y), Vector2(x, curve.end.y),
		Kit.ACCENT * Color(1, 1, 1, 0.75), 1.2)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x - 4.0, RULER_H - 5.0), Vector2(x + 4.0, RULER_H - 5.0), Vector2(x, RULER_H),
	]), Kit.ACCENT)


func _draw_speed_tab() -> void:
	var plot := plot_rect()
	var curve := _curve_rect()
	if doc == null or plot.size.x <= 1.0 or curve.size.y <= 1.0:
		return
	var columns := clampi(int(plot.size.x), 2, 900)
	var speeds: Array = []
	var peak := 0.0
	for i in range(columns):
		var t := point_to_time(Vector2(plot.position.x + float(i), plot.position.y))
		var speed := _speed_at(t)
		speeds.append(speed)
		peak = maxf(peak, speed)
	var top := maxf(0.001, peak * 1.10)
	var points := PackedVector2Array()
	for i in range(columns):
		var y := curve.end.y - (float(speeds[i]) / top) * curve.size.y
		points.append(Vector2(plot.position.x + float(i), y))
	if points.size() >= 2:
		draw_polyline(points, Kit.TIME_BRIGHT, 1.4, true)
	draw_line(Vector2(curve.position.x, curve.end.y), Vector2(curve.end.x, curve.end.y),
		Kit.BORDER_SOFT, 1.0)


func _draw_speed_summary() -> void:
	if doc == null:
		return
	var summary := speed_summary()
	var plot := plot_rect()
	var text := "Average %s   Peak %s" % [
		_speed_text(float(summary.get("average", 0.0))),
		_speed_text(float(summary.get("peak", 0.0))),
	]
	draw_string(Kit.font_mono, Vector2(plot.position.x, plot.position.y + 18.0),
		text, HORIZONTAL_ALIGNMENT_RIGHT, plot.size.x - 8.0,
		Kit.TYPE_CAPTION, Kit.TEXT_MUTED)


func _speed_text(value: float) -> String:
	if absf(value) >= 100.0:
		return "%.0f/s" % value
	if absf(value) >= 10.0:
		return "%.1f/s" % value
	return "%.2f/s" % value


# -------------------------------------------------------------------------
# Geometry and sampling
# -------------------------------------------------------------------------

func _curve_rect() -> Rect2:
	var plot := plot_rect()
	return Rect2(plot.position.x, plot.position.y,
		plot.size.x, maxf(1.0, plot.size.y - BOTTOM_GUTTER))


func _window() -> Vector2:
	if _window_cache_valid:
		return _window_cache
	var result := Vector2.ZERO
	var resolved := false
	if doc != null:
		var plot := plot_rect()
		var span := _active_span()
		if not span.is_empty():
			var start := float(span.get("start", 0.0))
			var end := float(span.get("end", 0.0))
			if end > start + 0.000001:
				var usable := maxf(1.0, plot.size.x - 48.0)
				var tpp := (end - start) / usable
				result = Vector2(start - 24.0 * tpp, end + 24.0 * tpp)
				resolved = true
		if not resolved:
			result = Vector2(0.0, maxf(0.001, doc.duration))
	else:
		result = Vector2(0.0, 1.0)
	_window_cache = result
	_window_cache_valid = true
	return result


func _time_to_x(time: float, plot: Rect2) -> float:
	var window := _window()
	return plot.position.x + (time - window.x) / maxf(0.000001, window.y - window.x) * plot.size.x


func _time_step(px_per_second: float) -> float:
	var candidates := [0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 60.0, 120.0]
	for value in candidates:
		if float(value) * px_per_second >= 44.0:
			return float(value)
	return 600.0


func _value_range() -> Vector2:
	if _range_cache_valid:
		return _range_cache
	var result := _compute_value_range()
	_range_cache = result
	_range_cache_valid = true
	return result


func _compute_value_range() -> Vector2:
	var curve := _curve_rect()
	if doc == null or _object_id == "":
		return Vector2(0.0, 1.0)
	var components: Array = ["x", "y", "z"] \
		if _tab == TAB_VALUE and _component == "all" and _channel != "rotation" \
		else [_component]
	var low := INF
	var high := -INF
	var count := maxi(2, int(curve.size.x))
	var keys: Array = doc.get_channel_keys(_object_id, _channel)
	for component in components:
		for i in range(count):
			var t := point_to_time(Vector2(curve.position.x + float(i), curve.position.y))
			var value: Variant = _sample(t)
			if value == null:
				continue
			var scalar := _value_scalar(value, str(component))
			low = minf(low, scalar)
			high = maxf(high, scalar)
		for key in keys:
			var scalar := _value_scalar(key["value"], str(component))
			low = minf(low, scalar)
			high = maxf(high, scalar)
	if not is_finite(low) or not is_finite(high):
		return Vector2(0.0, 1.0)
	if high - low < 0.000001:
		return Vector2(low - 0.5, high + 0.5)
	var pad := (high - low) * (0.10 if _tab == TAB_VALUE else 0.12)
	return Vector2(low - pad, high + pad)


func _value_to_y(value: float) -> float:
	var curve := _curve_rect()
	var range_values := _value_range()
	var span := maxf(0.000001, range_values.y - range_values.x)
	return curve.end.y - (value - range_values.x) / span * curve.size.y


func _y_to_value(y: float) -> float:
	return _value_at_y(y, _curve_rect(), _value_range())


func _value_at_y(y: float, curve: Rect2, range_values: Vector2) -> float:
	if curve.size.y <= 0.0:
		return range_values.x
	return range_values.x + (curve.end.y - y) / curve.size.y * (range_values.y - range_values.x)


func _sample(time: float) -> Variant:
	if doc == null or _object_id == "":
		return null
	return doc.sample_channel(_object_id, _channel, time)


func _scalar(value: Variant) -> float:
	return _value_scalar(value, _component)


func _value_scalar(value: Variant, component: String) -> float:
	if value is Vector3:
		var v := value as Vector3
		match component:
			"x":
				return v.x
			"y":
				return v.y
			"z":
				return v.z
		return v.length()
	if value is Quaternion:
		return (value as Quaternion).w
	if value is float or value is int:
		return float(value)
	return 0.0


func _delta(a: Variant, b: Variant) -> float:
	if a is Vector3 and b is Vector3:
		return ((b as Vector3) - (a as Vector3)).length()
	if a is Quaternion and b is Quaternion:
		return (a as Quaternion).angle_to(b as Quaternion)
	if a is float or a is int:
		return absf(float(b) - float(a))
	return 0.0


func _short_value(value: float) -> String:
	var abs_value := absf(value)
	if abs_value >= 1000.0:
		return "%.0f" % value
	if abs_value >= 10.0:
		return "%.1f" % value
	return "%.2f" % value


func _notify(text: String) -> void:
	notice.emit(text)


# -------------------------------------------------------------------------
# Input
# -------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if doc == null:
		return
	if Kit.is_emulated_mouse(event):
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_press(button.position)
		else:
			_release(button.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging_handle != "":
		_preview_handles = _preview_for_drag((event as InputEventMouseMotion).position)
		queue_redraw()
		accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_press(touch.position)
		else:
			_release(touch.position)
		accept_event()
	elif event is InputEventScreenDrag and _dragging_handle != "":
		_preview_handles = _preview_for_drag((event as InputEventScreenDrag).position)
		queue_redraw()
		accept_event()


func _press(position: Vector2) -> void:
	var plot := plot_rect()
	if not plot.has_point(position):
		return
	_press_key = -1
	_press_position = position
	# Snapshot the view before selecting a span may zoom the plot. The release
	# resolves its delta against this view, not the re-zoomed one.
	_press_time = point_to_time(position)
	_press_value = _y_to_value(position.y)
	_press_plot = plot
	_press_window = _window()
	_press_range = _value_range()
	_press_curve = _curve_rect()
	if _tab == TAB_EASE:
		var positions := handle_positions()
		if not positions.is_empty():
			for side in ["out", "in"]:
				var point: Vector2 = positions[side]
				if position.distance_to(point) <= HIT_RADIUS:
					_dragging_handle = side
					_drag_handle_start = point
					_preview_handles = positions.duplicate(true)
					_preview_handles[side] = position
					return
	# Resolve the tapped key against the view that is on screen before the
	# span selection may zoom the plot to a different interval.
	var hit := -1
	if _tab == TAB_VALUE and value_editable():
		hit = _key_at(position)
	var time := point_to_time(position)
	var span: Dictionary = doc.segment_span_at(_object_id, _channel, time)
	_span = span.duplicate(true)
	_preview_handles = {}
	if hit >= 0:
		_selected_key = hit
		_press_key = hit
	refresh()
	if hit >= 0:
		key_selected.emit(hit)
	span_selected.emit(_span.duplicate(true))


func _release(position: Vector2) -> void:
	if _dragging_handle != "":
		var span := _active_span()
		var preview := _preview_for_drag(position)
		_dragging_handle = ""
		if span.is_empty():
			_preview_handles = {}
			return
		var out_handle := _point_to_handle(span, preview.get("out", _drag_handle_start))
		var in_handle := _point_to_handle(span, preview.get("in", _drag_handle_start))
		_bake_handles(span,
			clampf(out_handle.x, 0.0, 1.0), clampf(out_handle.y, -2.0, 3.0),
			clampf(in_handle.x, 0.0, 1.0), clampf(in_handle.y, -2.0, 3.0))
		return
	if _press_key < 0:
		return
	var index := _press_key
	_press_key = -1
	# A tap selects; only a deliberate 6 px drag edits the document.
	if position.distance_to(_press_position) >= 6.0:
		_drag_key_from_press(index, position)


func _drag_key_from_press(index: int, position: Vector2) -> bool:
	if doc == null or _object_id == "":
		return false
	var keys: Array = doc.get_channel_keys(_object_id, _channel)
	if index < 0 or index >= keys.size():
		return false
	var time := float(keys[index]["time"]) \
		+ (_time_at_point(position, _press_plot, _press_window) - _press_time)
	var scalar := _scalar(keys[index]["value"]) \
		+ (_value_at_y(position.y, _press_curve, _press_range) - _press_value)
	return _drag_key_to(index, time, scalar)


func _key_at(position: Vector2) -> int:
	var best := -1
	var best_dist := HIT_RADIUS
	for point in key_points():
		var dist := position.distance_to(point["position"] as Vector2)
		if dist <= best_dist:
			best_dist = dist
			best = int(point["index"])
	return best


func _preview_for_drag(position: Vector2) -> Dictionary:
	var span := _active_span()
	var handles := _authored_handles()
	if span.is_empty() or handles.is_empty():
		return {}
	var out_handle := _point_to_handle(span, position if _dragging_handle == "out" else _handle_points(span, handles)[0])
	var in_handle := _point_to_handle(span, position if _dragging_handle == "in" else _handle_points(span, handles)[1])
	return {
		"out": _handle_point_from_handle(span, out_handle),
		"in": _handle_point_from_handle(span, in_handle),
	}


func _handle_point_from_handle(span: Dictionary, handle: Vector2) -> Vector2:
	var plot := plot_rect()
	var start := float(span.get("start", 0.0))
	var end := float(span.get("end", 0.0))
	var time := start + clampf(handle.x, 0.0, 1.0) * (end - start)
	var values := _segment_values(span)
	var value := lerpf(values.x, values.y, clampf(handle.y, -2.0, 3.0))
	return Vector2(_time_to_x(time, plot), _value_to_y(value))


# -------------------------------------------------------------------------
# Document signals
# -------------------------------------------------------------------------

func _on_keyframes_changed(_id: String) -> void:
	_preview_handles = {}
	refresh()


func _on_playback_changed(_time: float, _playing: bool) -> void:
	queue_redraw()


func _on_selection_changed(_id: String) -> void:
	if _span.is_empty():
		queue_redraw()
		return
	_preview_handles = {}
	refresh()


func _on_object_changed(_id: String) -> void:
	queue_redraw()


func _on_scene_changed() -> void:
	refresh()


func _preset_def(preset_id: String) -> Dictionary:
	for def in PRESET_DEFS:
		if str(def["id"]) == preset_id:
			return def
	return {}
