extends Control
## Wave 3 timeline workspace suite: curve families, atomic key edits, the
## speed graph control, and the landscape workspace. The suite proves maths and
## document state; it never fabricates a rendered pixel.

const DocumentScript = preload("res://src/core/document.gd")
const SpeedCurveScript = preload("res://src/core/speed_curve.gd")

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
