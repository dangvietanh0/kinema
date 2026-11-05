extends Control
## Wave 3 timeline workspace suite: curve families, atomic key edits, the
## speed graph control, and the landscape workspace. The suite proves maths and
## document state; it never fabricates a rendered pixel.

const DocumentScript = preload("res://src/core/document.gd")
const SpeedCurveScript = preload("res://src/core/speed_curve.gd")
const SpeedGraphScript = preload("res://src/ui/speed_graph.gd")
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
	await _test_speed_graph()
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

	# A segment shorter than two frames inserts one midpoint with the exact copy.
	var short_doc := _new_doc()
	short_doc.fps = 24
	short_doc.apply_key_edits(short_doc.selected_id, "scale", [
		{"index": -1, "time": 0.0, "value": Vector3.ONE},
		{"index": -1, "time": 0.05, "value": Vector3(2, 2, 2)},
	])
	var short_bake: Dictionary = short_doc.bake_curve_segment(short_doc.selected_id, "scale", 0, "sine_out")
	_check(bool(short_bake["ok"]), "a sub-two-frame segment bakes one midpoint")
	_check(int(short_bake["inserted"]) == 1 and _keys(short_doc, "scale").size() == 3,
		"the short segment inserts exactly one midpoint")
	_check(str(short_bake["message"]) == "Segment is shorter than two frames; baked one midpoint.",
		"the short-segment message is exact")


# -------------------------------------------------------------------------
# Task 12 — SpeedGraph control and the channel signal
# -------------------------------------------------------------------------

func _test_speed_graph() -> void:
	var doc := _new_doc()
	doc.apply_key_edits(doc.selected_id, "position", [
		{"index": -1, "time": 0.0, "value": Vector3(0, 0, 0)},
		{"index": -1, "time": 1.0, "value": Vector3(1, 0, 0)},
		{"index": -1, "time": 2.0, "value": Vector3(2, 0, 0)},
	], "Graph position")
	doc.apply_key_edits(doc.selected_id, "rotation", [
		{"index": -1, "time": 0.0, "value": Quaternion.IDENTITY},
		{"index": -1, "time": 1.0, "value": Quaternion(Vector3.UP, deg_to_rad(45.0))},
		{"index": -1, "time": 2.0, "value": Quaternion(Vector3.UP, deg_to_rad(90.0))},
	], "Graph rotation")

	var graph = SpeedGraphScript.new()
	add_child(graph)
	await get_tree().process_frame
	graph.size = Vector2(600.0, 400.0)
	graph.setup(doc)
	graph.set_context(doc.selected_id)
	await get_tree().process_frame

	# Channel validation.
	_check(graph.set_channel("scale") and graph.get_channel() == "scale",
		"set_channel accepts a valid channel")
	_check(not graph.set_channel("bogus") and graph.get_channel() == "scale",
		"an invalid channel is refused and the old channel stays")

	# No object selected.
	graph.set_context("")
	_check(graph.empty_state() == "Select an object",
		"an empty context shows the exact select-an-object state")
	_check(graph.selected_indices().is_empty(),
		"an empty context clears the selection")
	graph.set_context(doc.selected_id)

	# A channel with no keys is honest about it.
	graph.set_channel("scale")
	_check(graph.empty_state() == "No keys on this channel. Add a key at the playhead.",
		"an empty channel shows the exact no-keys state")

	# selected_segment refusals and the real segment record.
	graph.set_channel("position")
	graph.clear_selection()
	var none: Dictionary = graph.selected_segment()
	_check(not bool(none["ok"]) and str(none["reason"]) == "Select one key.",
		"no selection refuses the segment with the exact reason")
	graph.select_indices(PackedInt32Array([0, 1]))
	var several: Dictionary = graph.selected_segment()
	_check(not bool(several["ok"]) and str(several["reason"]) == "Select one key.",
		"multiple selection refuses the segment with the exact reason")
	graph.select_indices(PackedInt32Array([2]))
	var last: Dictionary = graph.selected_segment()
	_check(not bool(last["ok"]) and str(last["reason"]) == "The last key has no following segment.",
		"the last key refuses the segment with the exact reason")
	graph.select_indices(PackedInt32Array([0]))
	var segment: Dictionary = graph.selected_segment()
	var pos_keys := _keys(doc, "position")
	_check(bool(segment["ok"]) and int(segment["start_index"]) == 0 and int(segment["end_index"]) == 1,
		"a non-last key exposes its segment indices")
	_check(_approx(float(segment["t0"]), float(pos_keys[0]["time"])) and
		_approx(float(segment["t1"]), float(pos_keys[1]["time"])),
		"the segment times match the document keys")

	# Selection mutations and the signal payloads.
	var seen: Array = []
	var on_selection: Callable = func(indices: PackedInt32Array) -> void:
		seen.append(indices.duplicate())
	graph.selection_changed.connect(on_selection)
	graph.select_indices(PackedInt32Array([0]))
	_check(seen.size() == 1 and seen[0] == PackedInt32Array([0]),
		"select_indices selects one key and reports it")
	graph.select_indices(PackedInt32Array([1]), true)
	_check(seen.size() == 2 and seen[1] == PackedInt32Array([0, 1]),
		"an additive selection adds without clearing")
	graph.clear_selection()
	_check(seen.size() == 3 and (seen[2] as PackedInt32Array).is_empty(),
		"clear_selection empties the selection and reports it")
	graph.selection_changed.disconnect(on_selection)

	# Stale indices never survive a channel switch.
	graph.select_indices(PackedInt32Array([0]))
	graph.set_channel("rotation")
	_check(graph.selected_indices().is_empty(),
		"changing the channel clears stale indices")

	# A retime plus value edit is one undo entry.
	graph.set_channel("position")
	graph.select_indices(PackedInt32Array([0]))
	var stack_before: int = doc._undo_stack.size()
	_check(graph.commit_key_edit(0, 0.5, Vector3(0.5, 0.25, 0)),
		"commit_key_edit retimes and writes one value")
	var edited := _keys(doc, "position")
	_check(_approx(float(edited[0]["time"]), 0.5) and
		_vec_close(edited[0]["value"], Vector3(0.5, 0.25, 0)),
		"the committed key lands at its new time and value")
	_check(doc._undo_stack.size() == stack_before + 1,
		"a committed key edit opens exactly one undo entry")

	# Quaternion values are read-only; time editing still works.
	graph.set_channel("rotation")
	graph.select_indices(PackedInt32Array([0]))
	var refused_stack: int = doc._undo_stack.size()
	_check(not graph.commit_key_edit(0, 0.5, Quaternion.IDENTITY),
		"a rotation value edit is refused")
	_check(graph.last_error() == "Rotation values are quaternion; drag rotates with the rig or gizmo.",
		"the rotation refusal uses the exact copy")
	_check(doc._undo_stack.size() == refused_stack and not doc.has_open_edit(),
		"a refused rotation edit writes nothing")
	_check(graph.commit_key_edit(0, 0.25),
		"a rotation key can still be retimed")

	# Easing writes the scalar transition of the selected start key.
	graph.set_channel("position")
	graph.select_indices(PackedInt32Array([0]))
	_check(graph.apply_easing(0.5), "apply_easing accepts a selected segment")
	_check(_approx(doc.get_key_transition(doc.selected_id, "position", 0), 0.5),
		"apply_easing writes the start key transition")

	# Curve family baking reports the exact notice.
	graph.select_indices(PackedInt32Array([1]))
	var notices: Array = []
	var on_notice: Callable = func(text: String) -> void:
		notices.append(text)
	graph.notice.connect(on_notice)
	var bake: Dictionary = graph.apply_curve_family("bounce_out")
	var expected_inserted := clampi(int(round((2.0 - 1.0) * float(doc.fps))), 8, 48) - 1
	var expected_notice := "Bounce out baked · %d keys" % expected_inserted
	_check(bool(bake["ok"]) and int(bake["inserted"]) == expected_inserted,
		"apply_curve_family bakes the selected segment")
	_check(str(bake["message"]) == expected_notice,
		"the bake result carries the exact notice")
	_check(notices.size() == 1 and str(notices[0]) == expected_notice,
		"the bake emits the exact notice")
	graph.notice.disconnect(on_notice)

	# Copy stores relative times; paste places them at the playhead.
	graph.select_indices(PackedInt32Array([0, 1]))
	graph.copy_selection()
	var count_before_paste := _keys(doc, "position").size()
	var paste_stack: int = doc._undo_stack.size()
	_check(graph.paste_at(3.0), "paste_at places a copied key set")
	var pasted := _keys(doc, "position")
	_check(pasted.size() == count_before_paste + 2,
		"paste adds the whole copied set")
	_check(doc._undo_stack.size() == paste_stack + 1,
		"paste is exactly one undo entry")
	var has_three := false
	var has_three_half := false
	for key in pasted:
		if _approx(float(key["time"]), 3.0):
			has_three = true
		if _approx(float(key["time"]), 3.5):
			has_three_half = true
	_check(has_three and has_three_half,
		"paste keeps the relative offsets at the playhead")

	# Add samples the channel at the playhead; delete removes all selected.
	graph.set_channel("scale")
	doc.seek(3.0)
	var scale_before := _keys(doc, "scale").size()
	_check(graph.add_key_at_playhead(), "add_key_at_playhead inserts a key")
	var added := _keys(doc, "scale")
	_check(added.size() == scale_before + 1,
		"the sampled key lands on the scale track")
	_check(_approx(doc.get_key_transition(doc.selected_id, "scale", int(graph.selected_indices()[0])), 1.0),
		"the added key uses transition 1.0")
	var delete_before := _keys(doc, "scale").size()
	var delete_stack: int = doc._undo_stack.size()
	graph.delete_selection()
	_check(_keys(doc, "scale").size() == delete_before - 1,
		"delete_selection removes every selected key")
	_check(doc._undo_stack.size() == delete_stack + 1,
		"delete_selection is exactly one undo entry")

	# Fit resets the window and pads the value range.
	graph.set_channel("position")
	graph.fit()
	_check(_approx(graph._time_start, 0.0) and _approx(graph._time_end, float(doc.duration)),
		"fit resets the time window to the whole duration")
	_check(graph._value_min < graph._value_max,
		"fit leaves a padded value range")
	_check(graph.plot_rect().size.y >= 0.0,
		"plot_rect reports a non-negative height after layout")

	# Empty and hint copy for the remaining states.
	graph.set_channel("rotation")
	graph.set_view("value")
	graph._component = "x"
	_check(graph.empty_state() == "This channel has no editable value component.",
		"a rotation value component shows the exact no-component state")
	graph.select_component("all")
	_check(not graph.set_view("bogus") and graph.view() == "value",
		"an invalid view is refused and the old view stays")
	graph.set_channel("position")
	graph.set_view("speed")
	_check(graph.drag_hint() == "Switch to Value to edit values.",
		"speed view explains the exact way back to value editing")
	graph.set_channel("rotation")
	graph.set_view("value")
	_check(graph.drag_hint() == "Rotation values are quaternion; drag rotates with the rig or gizmo.",
		"the rotation hint uses the exact quaternion copy")

	# The component menu is disabled for rotation and still reads All.
	_check(not graph.component_enabled() and graph.component_label() == "All",
		"rotation disables the component menu and shows All")
	graph.select_component("x")
	_check(graph.component_label() == "All",
		"a component tap cannot leave All while rotation is active")

	graph.queue_free()
	doc.queue_free()
	await get_tree().process_frame


func _test_timeline_channel_signal() -> void:
	var doc := _new_doc()
	var timeline = TimelineScript.new()
	add_child(timeline)
	await get_tree().process_frame
	var transport_host := Control.new()
	add_child(transport_host)
	timeline.mount_transport(transport_host)
	timeline.setup(doc)
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
	transport_host.queue_free()
	doc.queue_free()
	await get_tree().process_frame


# -------------------------------------------------------------------------
# Task 13 — Landscape timeline workspace and back precedence
# -------------------------------------------------------------------------

func _check_workspace_hit_targets(editor, label: String) -> void:
	var buttons: Array = editor._timeline_workspace.find_children("*", "BaseButton", true, false)
	for node in buttons:
		var button := node as BaseButton
		if button == null or not button.is_visible_in_tree():
			continue
		_check(button.size.x >= 43.5 and button.size.y >= 43.5,
			"%s: %s keeps a 44 dp target" % [label, str(button.name)])


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
	main._on_new_project_requested("Timeline workspace suite", "study")
	for _i in 5:
		await get_tree().process_frame
	var editor = main._editor
	_check(editor != null, "the editor opens for the workspace suite")
	if editor == null:
		main.queue_free()
		get_window().size = original_window
		await get_tree().process_frame
		return
	editor._overlay.clear_toast()
	editor.set_layout_mode("studio")
	await get_tree().process_frame

	var doc = editor.doc
	if doc.selected_id == "":
		doc.add_primitive("cube")
	var object_id: String = doc.selected_id
	_check(object_id != "", "the workspace suite has a selected object")
	doc.apply_key_edits(object_id, "position", [
		{"index": -1, "time": 0.0, "value": Vector3(0, 0, 0)},
		{"index": -1, "time": 1.0, "value": Vector3(1, 0, 0)},
		{"index": -1, "time": 2.0, "value": Vector3(2, 0, 0)},
	], "Seed workspace keys")
	editor._timeline.set_mode("dope")
	editor._timeline.set_channel("position")
	editor._timeline_visible = true
	editor._sync_timeline_visibility()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._timeline.sheet_visible(), "the sheet is open before the workspace opens")

	# Capture the exact original homes.
	var timeline_parent: Node = editor._timeline.get_parent()
	var timeline_index: int = editor._timeline.get_index()
	var lane_parent: Node = editor._lane_scroll.get_parent()
	var lane_index: int = editor._lane_scroll.get_index()
	var transport: Control = editor._timeline.transport_panel()
	var transport_parent: Node = transport.get_parent()
	var transport_index: int = transport.get_index()

	_check(editor.open_timeline_workspace(), "the workspace opens at 915x412")
	await get_tree().process_frame
	_check(editor.timeline_workspace_open(), "timeline_workspace_open reports the workspace")
	_check(editor._workspace_left.get_child_count() == 2,
		"the left column holds the lane stack and the dope sheet")
	_check(editor._timeline.get_parent() == editor._workspace_left,
		"the dope sheet is reparented into the left column")
	_check(editor._lane_scroll.get_parent() == editor._workspace_left,
		"the lane scroll is reparented into the left column")
	_check(transport.get_parent() == editor._workspace_footer,
		"the single transport is reparented into the footer")
	_check(not editor._timeline_panel.visible,
		"the compact timeline panel is hidden while the workspace is open")

	var body_width: float = editor._workspace_body.size.x
	var left_ratio: float = editor._workspace_left.size.x / body_width
	_check(left_ratio >= 0.45 and left_ratio <= 0.55,
		"the left column is 45-55 percent of the body")
	_check(editor._workspace_graph.plot_rect().size.y >= 120.0,
		"the workspace graph plot reaches 120 dp at 915x412")
	_check(absf(editor._workspace_header.size.y - 56.0) <= 0.5,
		"the workspace header is 56 dp")
	_check(absf(editor._workspace_footer.size.y - 56.0) <= 0.5,
		"the workspace footer is 56 dp")
	_check(absf(editor._workspace_close_button.size.x - 96.0) <= 0.5
		and absf(editor._workspace_close_button.size.y - 44.0) <= 0.5,
		"the header Close is 96x44")
	_check_workspace_hit_targets(editor, "915x412")

	# Dope-only workspace: no mode tabs and no More.
	_check(not editor._timeline._mode_button.visible,
		"the workspace hides the mode tabs")
	_check(not editor._timeline._more_button.visible,
		"the workspace hides the More control")
	_check(not editor._timeline._compact_header.visible,
		"the workspace hides the compact header")

	# Opening twice is idempotent.
	var timeline_index_open: int = editor._timeline.get_index()
	_check(editor.open_timeline_workspace(), "opening an open workspace returns true")
	_check(editor._workspace_left.get_child_count() == 2
		and editor._timeline.get_index() == timeline_index_open,
		"opening twice does not duplicate the reparent")

	# Channel selection drives the graph.
	editor._timeline.set_channel("scale")
	await get_tree().process_frame
	_check(editor._workspace_graph.get_channel() == "scale",
		"Timeline.channel_selected drives SpeedGraph.set_channel")
	editor._timeline.set_channel("position")

	# Selection changes clear the graph context and its indices.
	editor._workspace_graph.select_indices(PackedInt32Array([0]))
	_check(editor._workspace_graph.selected_indices().size() == 1,
		"the workspace graph selects a key before the selection change")
	var other_id: String = doc.add_primitive("sphere")
	doc.set_selection(other_id)
	await get_tree().process_frame
	_check(editor._workspace_graph.selected_indices().is_empty(),
		"changing doc.selected_id clears the graph selection")
	doc.set_selection(object_id)
	await get_tree().process_frame

	# Close restores the exact homes and the compact sheet.
	editor.close_timeline_workspace()
	await get_tree().process_frame
	_check(not editor.timeline_workspace_open(), "closing hides the workspace")
	_check(editor._timeline.get_parent() == timeline_parent
		and editor._timeline.get_index() == timeline_index,
		"closing restores the dope sheet's exact parent and index")
	_check(editor._lane_scroll.get_parent() == lane_parent
		and editor._lane_scroll.get_index() == lane_index,
		"closing restores the lane scroll's exact parent and index")
	_check(transport.get_parent() == transport_parent
		and transport.get_index() == transport_index,
		"closing restores the transport's exact parent and index")
	_check(editor._timeline_panel.visible,
		"closing restores the compact timeline panel")
	_check(editor._timeline.sheet_visible(),
		"the compact sheet remains usable after close")
	_check(editor._timeline.mode() == "dope",
		"closing returns the sheet to dope")

	# The wide size gets a much taller plot.
	get_window().size = Vector2i(1280, 800)
	for _i in 3:
		await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame
	editor._timeline_visible = true
	editor._sync_timeline_visibility()
	await get_tree().process_frame
	_check(editor.open_timeline_workspace(), "the workspace opens at 1280x800")
	await get_tree().process_frame
	_check(editor._workspace_graph.plot_rect().size.y >= 480.0,
		"the workspace graph plot reaches 480 dp at 1280x800")
	var wide_body: float = editor._workspace_body.size.x
	var wide_ratio: float = editor._workspace_left.size.x / wide_body
	_check(wide_ratio >= 0.45 and wide_ratio <= 0.55,
		"the wide left column stays at 45-55 percent")
	_check(absf(editor._workspace_header.size.y - 56.0) <= 0.5
		and absf(editor._workspace_footer.size.y - 56.0) <= 0.5,
		"the wide header and footer are 56 dp")
	_check_workspace_hit_targets(editor, "1280x800")
	editor.close_timeline_workspace()
	await get_tree().process_frame

	# Below the bounds the Expand control refuses with the exact reason.
	get_window().size = Vector2i(700, 359)
	for _i in 3:
		await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame
	editor._timeline_visible = true
	editor._sync_timeline_visibility()
	await get_tree().process_frame
	_check(not editor.open_timeline_workspace(),
		"the workspace refuses below 720x360")
	_check(editor._timeline.expand_button() != null
		and editor._timeline.expand_button().disabled,
		"the Expand control is disabled below the bounds")
	_check(editor._timeline.expand_button().tooltip_text == "Landscape workspace needs at least 720 × 360 dp",
		"the disabled Expand control carries the exact reason")

	# Dropping below the bounds while open closes once with one toast.
	get_window().size = Vector2i(915, 412)
	for _i in 3:
		await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame
	editor._timeline_visible = true
	editor._sync_timeline_visibility()
	await get_tree().process_frame
	_check(editor.open_timeline_workspace(), "the workspace reopens at 915x412")
	await get_tree().process_frame
	var toast_serial: int = editor._overlay._toast_serial
	get_window().size = Vector2i(700, 359)
	for _i in 3:
		await get_tree().process_frame
	_check(not editor.timeline_workspace_open(),
		"resizing below the bounds closes the workspace")
	_check(editor._overlay._toast_serial == toast_serial + 1,
		"the resize close shows exactly one toast")
	_check(editor._overlay._toast_label.text == "The timeline workspace needs at least 720 × 360 dp.",
		"the resize toast carries the exact copy")

	# The 720x360 boundary is supported and survives a resize upward.
	get_window().size = Vector2i(720, 360)
	for _i in 3:
		await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame
	editor._timeline_visible = true
	editor._sync_timeline_visibility()
	await get_tree().process_frame
	_check(editor.open_timeline_workspace(), "exactly 720x360 opens the workspace")
	get_window().size = Vector2i(800, 700)
	for _i in 3:
		await get_tree().process_frame
	_check(editor.timeline_workspace_open(),
		"resizing from 720x360 to 800x700 keeps the workspace open")

	# Back precedence: modal, then drawer, then workspace, then project close.
	editor._overlay.show_modal("Test modal", "", null, [{"text": "Close", "compact": true}])
	await get_tree().process_frame
	editor.handle_back()
	await get_tree().process_frame
	_check(not editor._overlay.has_modal() and editor.timeline_workspace_open(),
		"Back closes an open modal before the workspace")
	editor._open_drawer()
	await get_tree().process_frame
	_check(editor._drawer_open, "the drawer opened for the precedence check")
	editor.handle_back()
	await get_tree().process_frame
	_check(not editor._drawer_open and editor.timeline_workspace_open(),
		"Back closes the drawer before the workspace")
	editor.handle_back()
	await get_tree().process_frame
	_check(not editor.timeline_workspace_open(),
		"Back closes the workspace when nothing else is open")
	doc._dirty = true
	editor.handle_back()
	await get_tree().process_frame
	_check(editor._overlay.has_modal(),
		"Back requests project close when the workspace is closed")
	editor._overlay.close_modal()
	await get_tree().process_frame

	# A project close path closes the workspace before the close sheet.
	get_window().size = Vector2i(915, 412)
	for _i in 3:
		await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame
	editor._timeline_visible = true
	editor._sync_timeline_visibility()
	await get_tree().process_frame
	_check(editor.open_timeline_workspace(), "the workspace reopens for the close check")
	await get_tree().process_frame
	editor.request_close()
	await get_tree().process_frame
	_check(not editor.timeline_workspace_open(),
		"a project close closes the workspace first")
	_check(editor._overlay.has_modal(),
		"the project close sheet opens after the workspace closes")
	editor._overlay.close_modal()
	await get_tree().process_frame

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
