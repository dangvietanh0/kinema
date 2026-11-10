extends Control
## Wave 3 timeline suite: curve families, atomic key edits, the channel signal
## and the Animate workspace pane. The suite proves maths and document state; it
## never fabricates a rendered pixel.

const DocumentScript = preload("res://src/core/document.gd")
const SpeedCurveScript = preload("res://src/core/speed_curve.gd")
const TimelineScript = preload("res://src/ui/timeline.gd")

var _failures: Array[String] = []
var _checks := 0
var _tmp_dir := ""


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("TIMELINE FAIL: " + message)
	else:
		print("TIMELINE OK: " + message)


func _ready() -> void:
	_tmp_dir = ProjectSettings.globalize_path("user://timeline_workspace_tests")
	_rmrf(_tmp_dir)
	DirAccess.make_dir_recursive_absolute(_tmp_dir)
	await get_tree().process_frame
	await _test_speed_curves()
	await _test_apply_key_edits()
	await _test_bake_curve_segment()
	await _test_timeline_channel_signal()
	await _test_timeline_workspace()
	_finish()


func _finish() -> void:
	_rmrf(_tmp_dir)
	if _failures.is_empty():
		print("SUITE RESULT: PASS (%d checks)" % _checks)
	else:
		printerr("SUITE RESULT: FAIL (%d failures of %d checks)" % [_failures.size(), _checks])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _rmrf(path: String) -> void:
	if path == "" or not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for name in dir.get_files():
		dir.remove(name)
	for name in dir.get_directories():
		_rmrf(path.path_join(name))
	DirAccess.remove_absolute(path)


func _new_doc() -> Node3D:
	var doc = DocumentScript.new()
	add_child(doc)
	doc.new_project("Timeline Test", "blank")
	doc.project_dir = _tmp_dir
	return doc


func _keys(doc: Node3D, channel: String) -> Array:
	return doc.get_channel_keys(doc.selected_id, channel)


func _approx(a: float, b: float, epsilon: float = 0.0001) -> bool:
	return absf(a - b) <= epsilon


func _vec_close(a: Vector3, b: Vector3, epsilon: float = 0.0001) -> bool:
	return a.distance_to(b) <= epsilon


# -------------------------------------------------------------------------
# Task 10 — curve math and atomic key edits
# -------------------------------------------------------------------------

func _test_speed_curves() -> void:
	var expected := [
		"bounce_out", "bounce_in", "bounce_in_out",
		"elastic_out", "elastic_in", "back_out", "back_in", "spring",
		"sine_in", "sine_out", "sine_in_out",
		"expo_in", "expo_out", "expo_in_out",
	]
	var ids := SpeedCurveScript.family_ids()
	_check(ids.size() == 14, "SpeedCurve exposes exactly 14 families")
	for id in expected:
		_check(ids.has(id), "SpeedCurve contains the %s family" % id)
	for id in ids:
		_check(_approx(SpeedCurveScript.evaluate(id, 0.0), 0.0),
			"%s starts at 0" % id)
		_check(_approx(SpeedCurveScript.evaluate(id, 1.0), 1.0),
			"%s ends at 1" % id)
		var finite := true
		var low := 0.0
		var high := 0.0
		for step in range(21):
			var t := float(step) * 0.05
			var value: float = SpeedCurveScript.evaluate(id, t)
			if is_nan(value) or is_inf(value):
				finite = false
			low = minf(low, value)
			high = maxf(high, value)
		_check(finite, "%s stays finite across the curve" % id)
		if id.begins_with("bounce"):
			_check(low >= -0.001 and high <= 1.001,
				"%s stays inside the standard bounce bounds" % id)
		if id == "elastic_out" or id == "back_out":
			_check(high > 1.001 or low < -0.001,
				"%s produces real overshoot" % id)
	_check(SpeedCurveScript.family_label("bounce_out") == "Bounce",
		"family_label names the Bounce family")
	_check(SpeedCurveScript.family_label("sine_in_out") == "Sine",
		"family_label names the Sine family")
	_check(SpeedCurveScript.family_label("expo_out") == "Expo",
		"family_label names the Expo family")
	_check(_approx(SpeedCurveScript.evaluate("nope", 0.5), 0.0),
		"an unknown family evaluates to 0")


func _test_apply_key_edits() -> void:
	var doc := _new_doc()
	var channel := "position"
	# Insert three keys in one call.
	var insert: Dictionary = doc.apply_key_edits(doc.selected_id, channel, [
		{"index": -1, "time": 0.0, "value": Vector3(0, 0, 0)},
		{"index": -1, "time": 1.0, "value": Vector3(1, 0, 0)},
		{"index": -1, "time": 2.0, "value": Vector3(2, 0, 0)},
	], "Insert keys")
	_check(bool(insert["ok"]), "apply_key_edits inserts keys")
	_check(_keys(doc, channel).size() == 3, "three keys land on the track")
	_check(int(insert["indices"][0]) == 0 and int(insert["indices"][2]) == 2,
		"insert indices point at the sorted keys")

	# Retime one key and change one value in the same call.
	var edited: Dictionary = doc.apply_key_edits(doc.selected_id, channel, [
		{"index": 1, "time": 1.5},
		{"index": 0, "value": Vector3(0, 1, 0)},
	])
	_check(bool(edited["ok"]), "apply_key_edits retimes and edits values")
	var keys := _keys(doc, channel)
	_check(_approx(float(keys[1]["time"]), 1.5), "the retimed key moves to 1.5 s")
	_check(_vec_close(keys[0]["value"], Vector3(0, 1, 0)), "the first value changes")

	# A multi-key move still sorts deterministically.
	var moved: Dictionary = doc.apply_key_edits(doc.selected_id, channel, [
		{"index": 0, "time": 2.5},
		{"index": 1, "time": 0.25},
		{"index": 2, "time": 3.0},
	])
	keys = _keys(doc, channel)
	_check(bool(moved["ok"]), "apply_key_edits applies a multi-key move")
	_check(_approx(float(keys[0]["time"]), 0.25) and _approx(float(keys[1]["time"]), 2.5) and _approx(float(keys[2]["time"]), 3.0),
		"a multi-key move lands sorted by time")
	_check(int(moved["indices"][0]) == 1, "the moved key index points at its new slot")

	# Four edits in one call are one undo entry.
	var before := _keys(doc, channel).duplicate(true)
	var stack_before: int = doc._undo_stack.size()
	var batch: Dictionary = doc.apply_key_edits(doc.selected_id, channel, [
		{"index": 0, "time": 0.4},
		{"index": 1, "time": 2.2},
		{"index": 2, "value": Vector3(4, 0, 0)},
		{"index": -1, "time": 3.5, "value": Vector3(5, 0, 0)},
	], "Four edits")
	_check(bool(batch["ok"]), "a four-edit batch succeeds")
	_check(doc._undo_stack.size() == stack_before + 1, "four edits open exactly one undo entry")
	doc.undo()
	keys = _keys(doc, channel)
	_check(keys.size() == before.size(), "undo restores the original key count")
	var restored := true
	for i in range(mini(keys.size(), before.size())):
		if not _approx(float(keys[i]["time"]), float(before[i]["time"])):
			restored = false
	_check(restored, "undo restores the original key times")

	# Deleting and out-of-range guards.
	var count_before := _keys(doc, channel).size()
	var deleted: Dictionary = doc.apply_key_edits(doc.selected_id, channel, [
		{"index": 1, "delete": true},
	])
	_check(bool(deleted["ok"]) and _keys(doc, channel).size() == count_before - 1,
		"apply_key_edits deletes one key")
	var snapshot := _keys(doc, channel).duplicate(true)
	var refused: Dictionary = doc.apply_key_edits(doc.selected_id, channel, [
		{"index": 99, "time": 1.0},
	])
	_check(not bool(refused["ok"]), "an out-of-range index is refused")
	_check(_keys(doc, channel).size() == snapshot.size(), "a refused batch writes nothing")
	_check(not doc.has_open_edit(), "a refused batch opens no undo entry")

	# Interpolation survives a rebuild.
	doc.interpolation = "cubic"
	var cubic_key: Dictionary = doc.apply_key_edits(doc.selected_id, "scale", [
		{"index": -1, "time": 0.0, "value": Vector3.ONE},
		{"index": -1, "time": 1.0, "value": Vector3(2, 2, 2)},
	])
	var track: int = doc.get_track(doc.selected_id, "scale")
	_check(bool(cubic_key["ok"]) and track >= 0, "a new scale track is created")
	_check(doc.animation.track_get_interpolation_type(track) == Animation.INTERPOLATION_CUBIC,
		"apply_key_edits preserves the track interpolation type")


func _test_bake_curve_segment() -> void:
	var doc := _new_doc()
	doc.fps = 24
	var channel := "position"
	doc.apply_key_edits(doc.selected_id, channel, [
		{"index": -1, "time": 0.0, "value": Vector3(0, 0, 0)},
		{"index": -1, "time": 2.0, "value": Vector3(10, 0, 0)},
	])
	var original := _keys(doc, channel).duplicate(true)
	var stack_before: int = doc._undo_stack.size()
	var bake: Dictionary = doc.bake_curve_segment(doc.selected_id, channel, 0, "bounce_out")
	var expected_inserted := clampi(int(round(2.0 * 24.0)), 8, 48) - 1
	_check(bool(bake["ok"]), "bake_curve_segment bakes a segment")
	_check(int(bake["inserted"]) == expected_inserted,
		"the bake inserts clamp(round(span*fps), 8, 48) - 1 keys")
	var baked := _keys(doc, channel)
	_check(baked.size() == original.size() + expected_inserted,
		"the inserted keys really land on the track")
	_check(_vec_close(baked[0]["value"], Vector3(0, 0, 0)) and _vec_close(baked[baked.size() - 1]["value"], Vector3(10, 0, 0)),
		"the segment endpoints keep their values")
	var transitions_ok := true
	for i in range(1, baked.size() - 1):
		if not _approx(float(doc.get_key_transition(doc.selected_id, channel, i)), 1.0):
			transitions_ok = false
	_check(transitions_ok, "inserted keys use transition 1.0")
	_check(doc._undo_stack.size() == stack_before + 1, "the bake is exactly one undo entry")
	doc.undo()
	_check(_keys(doc, channel).size() == original.size(), "undo restores the original key count")
	_check(_vec_close(_keys(doc, channel)[1]["value"], Vector3(10, 0, 0)),
		"undo restores the original endpoint value")

	# Rotation baking produces real normalized quaternions, overshoot included.
	var rot_doc := _new_doc()
	rot_doc.fps = 24
	rot_doc.apply_key_edits(rot_doc.selected_id, "rotation", [
		{"index": -1, "time": 0.0, "value": Quaternion.IDENTITY},
		{"index": -1, "time": 1.0, "value": Quaternion(Vector3.UP, deg_to_rad(90.0))},
	])
	var rot_bake: Dictionary = rot_doc.bake_curve_segment(rot_doc.selected_id, "rotation", 0, "elastic_out")
	_check(bool(rot_bake["ok"]), "a rotation segment bakes")
	var normalized := true
	for key in _keys(rot_doc, "rotation"):
		var q: Quaternion = key["value"]
		if not _approx(q.length(), 1.0, 0.001):
			normalized = false
	_check(normalized, "rotation bake keeps every quaternion normalized")

	# A segment shorter than three frames is refused: there is no honest
	# interior sample to bake and writing one would fake a curve.
	var short_doc := _new_doc()
	short_doc.fps = 24
	short_doc.apply_key_edits(short_doc.selected_id, "scale", [
		{"index": -1, "time": 0.0, "value": Vector3.ONE},
		{"index": -1, "time": 0.05, "value": Vector3(2, 2, 2)},
	])
	var short_bake: Dictionary = short_doc.bake_curve_segment(short_doc.selected_id, "scale", 0, "sine_out")
	_check(not bool(short_bake["ok"]), "a sub-three-frame segment refuses to bake")
	_check(int(short_bake["inserted"]) == 0 and _keys(short_doc, "scale").size() == 2,
		"a refused short bake writes no keys")
	_check(str(short_bake["message"]) == "Segment too short to bake (3 frames minimum)",
		"the short-segment message is exact")
	_check(short_doc.curve_segments().is_empty(), "a refused short bake writes no metadata")


# -------------------------------------------------------------------------
# Task 12 — the channel signal
# -------------------------------------------------------------------------

func _test_timeline_channel_signal() -> void:
	var doc := _new_doc()
	var timeline = TimelineScript.new()
	add_child(timeline)
	await get_tree().process_frame
	timeline.setup(doc)
	timeline.set_available_width(600.0)
	timeline.size = Vector2(600.0, 260.0)
	await get_tree().process_frame

	var emitted: Array = []
	var on_channel: Callable = func(channel: String) -> void:
		emitted.append(channel)
	timeline.channel_selected.connect(on_channel)

	timeline.set_channel("scale")
	_check(timeline.channel() == "scale",
		"Timeline.channel reports the active channel")
	_check(emitted.size() == 1 and str(emitted[0]) == "scale",
		"Timeline.set_channel emits channel_selected")

	# A tap anywhere on the 44 dp channel row switches the channel too.
	timeline._geometry(timeline._sheet)
	var row_y: float = timeline._ruler_h + timeline._row_h * 1.5
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(20.0, row_y)
	timeline._sheet_input(press, timeline._sheet)
	_check(emitted.size() == 2 and str(emitted[1]) == "rotation",
		"a dope channel-row tap emits channel_selected")

	var press_grid := InputEventMouseButton.new()
	press_grid.button_index = MOUSE_BUTTON_LEFT
	press_grid.pressed = true
	press_grid.position = Vector2(timeline._label_width + 30.0, timeline._ruler_h + timeline._row_h * 2.5)
	timeline._sheet_input(press_grid, timeline._sheet)
	_check(emitted.size() == 3 and str(emitted[2]) == "scale",
		"the full row, not just the label column, selects the channel")

	timeline.channel_selected.disconnect(on_channel)
	timeline.queue_free()
	doc.queue_free()
	await get_tree().process_frame


# -------------------------------------------------------------------------
# -------------------------------------------------------------------------
# Task 13 (W1) — the Animate workspace owns the real Timeline pane
# -------------------------------------------------------------------------

func _test_timeline_workspace() -> void:
	var original_window := get_window().size
	var packed: PackedScene = load("res://src/app/main.tscn")
	var main: Control = packed.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	get_window().size = Vector2i(915, 412)
	for _i in 3:
		await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame
	Prefs.set_value("editor.workspace", "scene")
	main._on_new_project_requested("Timeline workspace suite", "study")
	for _i in 5:
		await get_tree().process_frame
	var editor = main._editor
	_check(editor != null, "the editor opens for the Animate workspace suite")
	if editor == null:
		main.queue_free()
		get_window().size = original_window
		await get_tree().process_frame
		return
	editor._overlay.clear_toast()

	editor.set_workspace("animate")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor.workspace() == "animate", "set_workspace opens the Animate workspace")
	_check(editor._animate_pane.visible, "the Animate pane is visible")
	_check(editor._timeline.get_parent() == editor._animate_pane,
		"the Timeline is mounted in the Animate pane")
	_check(editor._animate_pane.get_index() > editor._stage_host.get_index(),
		"the Animate pane sits below the stage in the centre column")
	_check(not editor._stage_host.visible
		or editor._stage_host.get_global_rect().end.y <=
			editor._animate_pane.get_global_rect().position.y + 0.5,
		"the Animate pane never covers the stage")
	_check(not editor._transport_bar.visible,
		"the shared stage transport yields to the Timeline transport")

	var transport: Control = editor._timeline.transport_panel()
	_check(transport != null and editor._animate_pane.is_ancestor_of(transport),
		"the Timeline transport lives inside the Animate pane")
	var visible_buttons := 0
	for node in transport.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button == null or not button.is_visible_in_tree():
			continue
		visible_buttons += 1
		_check(button.custom_minimum_size.x >= 43.5 and button.custom_minimum_size.y >= 43.5,
			"the Animate transport keeps a 44 dp target: %s" % str(button.name))
	_check(visible_buttons >= 5, "the Animate transport exposes its core controls")

	# The pane drives the same document and Timeline state the shell shows.
	var doc = editor.doc
	if doc.selected_id == "":
		doc.add_primitive("cube")
	var object_id: String = doc.selected_id
	_check(object_id != "", "the Animate workspace has a selected object")
	doc.apply_key_edits(object_id, "position", [
		{"index": -1, "time": 0.0, "value": Vector3(0, 0, 0)},
		{"index": -1, "time": 1.0, "value": Vector3(1, 0, 0)},
		{"index": -1, "time": 2.0, "value": Vector3(2, 0, 0)},
	], "Seed workspace keys")
	editor._timeline.set_mode("dope")
	editor._timeline.set_channel("position")
	await get_tree().process_frame
	_check(editor._timeline.sheet_visible(), "the Timeline sheet is open in the pane")
	_check(editor._timeline.mode() == "dope", "the pane keeps the dope sheet mode")
	_check(editor._timeline.channel() == "position", "the pane tracks the active channel")
	editor._timeline.set_channel("scale")
	await get_tree().process_frame
	_check(editor._timeline.channel() == "scale",
		"the pane still follows a channel change")
	editor._timeline.set_channel("position")

	# The 44 dp pane transport replaces the removed compact start/end pair.
	var transport_panel: Control = editor._timeline.transport_panel()
	var pane_header: Control = editor._timeline.pane_header()
	_check(transport_panel.size.y >= 43.5, "the Animate transport is 44 dp")
	_check(pane_header.size.y >= 43.5, "the Animate pane header is 44 dp")
	_check(editor._timeline.clip_selector() != null,
		"the pane header owns the clip selector")
	_check(editor._timeline.fps_button() != null, "the transport owns the fps chip")
	_check(editor._timeline.delete_key_button() != null,
		"the transport owns delete key")
	_check(editor._timeline.fit_button() != null, "the transport owns fit")
	editor._timeline.set_time_view(0.0, 0.25)
	editor._timeline.fit_button().pressed.emit()
	_check(absf(editor._timeline.viewport_end() - doc.duration) < 0.01,
		"the transport fit button restores the whole clip view")
	editor._timeline.set_mode("graph")
	_check(editor._timeline.mode() == "graph" and not editor._timeline.dope_sheet_visible(),
		"the pane header Graph tab shows the segment graph")
	editor._timeline.dope_tab().pressed.emit()
	_check(editor._timeline.mode() == "dope" and editor._timeline.dope_sheet_visible(),
		"the pane header Dope tab restores the dope sheet")
	var time_requests: Array[String] = []
	var on_time := func() -> void: time_requests.append("time")
	editor._timeline.time_entry_requested.connect(on_time)
	editor._timeline.time_button().pressed.emit()
	_check(time_requests == ["time"],
		"the pane timecode asks the editor for the shared time sheet")
	editor._timeline.time_entry_requested.disconnect(on_time)
	editor._timeline.play_button().pressed.emit()
	await get_tree().process_frame
	_check(doc.is_playing, "the pane transport play button starts playback")
	editor._timeline.play_button().pressed.emit()
	await get_tree().process_frame
	_check(not doc.is_playing, "the pane transport play button pauses playback")

	# A non-animate workspace releases the pane and restores the shared bar.
	editor.set_workspace("scene")
	await get_tree().process_frame
	_check(not editor._animate_pane.visible, "Scene hides the Animate pane")
	_check(editor._transport_bar.visible, "Scene restores the shared transport")
	if doc.is_playing:
		doc.pause()

	# Clean up.
	var project_id: String = doc.project_id
	editor._leave(false)
	await get_tree().process_frame
	await get_tree().process_frame
	if project_id != "":
		Store.delete_project(project_id)
	main.queue_free()
	await get_tree().process_frame
	get_window().size = original_window
	for _i in 3:
		await get_tree().process_frame
