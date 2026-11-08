extends Control
## W3 graph suite: cubic math, format-4 curve metadata, the segment graph,
## the Animate layout and the W3 gate cases.
##
## One assertion per line, real document state only. The suite ends with
## `SUITE RESULT: PASS` and quits 0; any failure prints `GRAPH FAIL` and quits 1.

const DocumentScript = preload("res://src/core/document.gd")
const SpeedCurveScript = preload("res://src/core/speed_curve.gd")
const TimelineScript = preload("res://src/ui/timeline.gd")

var _failures: Array[String] = []
var _checks := 0


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("GRAPH OK: " + message)
	else:
		_failures.append(message)
		printerr("GRAPH FAIL: " + message)


func _ready() -> void:
	await get_tree().process_frame
	await _test_cubic_math()
	await _test_cubic_bake()
	await _test_bake_limits()
	await _test_format4_persistence()
	await _test_segment_selection()
	await _test_ease_tab()
	await _test_preset_rail()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("SUITE RESULT: PASS (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		printerr("SUITE RESULT: FAIL (%d failures of %d checks)" % [_failures.size(), _checks])
		get_tree().quit(1)


func _new_doc(title := "Graph Test") -> Node3D:
	var doc = DocumentScript.new()
	add_child(doc)
	doc.new_project(title, "blank")
	return doc


func _cube(doc) -> String:
	var id: String = doc.add_primitive("box", Vector3.ZERO)
	doc.set_fps(30)
	doc.set_duration(12.0)
	doc.set_selection(id)
	return id


func _two_keys(doc, id: String, t0 := 0.0, t1 := 1.0) -> void:
	doc.apply_key_edits(id, "position", [
		{"index": -1, "time": t0, "value": Vector3.ZERO},
		{"index": -1, "time": t1, "value": Vector3(10, 0, 0)},
	], "Seed keys")


# -------------------------------------------------------------------------
# Task 15 — cubic math and format 4
# -------------------------------------------------------------------------

func _test_cubic_math() -> void:
	print("GRAPH STEP: cubic math")
	_check(absf(SpeedCurveScript.cubic_ease(0.0, 0.42, 0.0, 0.58, 1.0)) < 0.000001,
		"cubic_ease(0) is 0")
	_check(absf(SpeedCurveScript.cubic_ease(1.0, 0.42, 0.0, 0.58, 1.0) - 1.0) < 0.000001,
		"cubic_ease(1) is 1")
	_check(absf(SpeedCurveScript.cubic_ease(0.5, 1.0 / 3.0, 1.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0) - 0.5) < 0.001,
		"linear handles produce the identity curve")
	var last := -1.0
	var monotonic := true
	for i in range(101):
		var v: float = SpeedCurveScript.cubic_ease(float(i) / 100.0, 0.2, 0.8, 0.8, 0.2)
		if v < last - 0.000001:
			monotonic = false
		last = v
	_check(monotonic, "x handles clamped to [0,1] keep the curve monotonic in t")
	_check(is_finite(SpeedCurveScript.cubic_ease(0.5, -5.0, -3.0, 5.0, 4.0)),
		"out-of-range handles still return a finite value")


func _test_cubic_bake() -> void:
	print("GRAPH STEP: cubic bake")
	var doc := _new_doc()
	var id := _cube(doc)
	_two_keys(doc, id, 0.0, 1.0)
	var undo_before: int = (doc._undo_stack as Array).size()
	var result: Dictionary = doc.bake_cubic_segment(id, "position", 0.0, 1.0, 0.2, 0.8, 0.8, 0.2)
	_check(bool(result.get("ok", false)), "a 1 s segment at 30 fps bakes")
	var keys: Array = doc.get_channel_keys(id, "position")
	_check(keys.size() == 31, "a 1 s, 30 fps segment has 2 endpoints + 29 interior keys")
	_check((doc._undo_stack as Array).size() == undo_before + 1,
		"one cubic bake is one undo entry")
	var interior := 0
	var grid_ok := true
	var inside_ok := true
	var transition_ok := true
	var value_ok := true
	var v0: Vector3 = keys[0]["value"]
	var v1: Vector3 = keys[keys.size() - 1]["value"]
	for i in range(1, keys.size() - 1):
		var t: float = keys[i]["time"]
		interior += 1
		var frame := t * 30.0
		if absf(frame - roundf(frame)) > 0.001:
			grid_ok = false
		if not (t > 0.001 and t < 0.999):
			inside_ok = false
		if absf(float(doc.get_key_transition(id, "position", i)) - 1.0) > 0.000001:
			transition_ok = false
		var expected: Vector3 = doc._curve_value("position", v0, v1,
			SpeedCurveScript.cubic_ease(t, 0.2, 0.8, 0.8, 0.2))
		if (keys[i]["value"] as Vector3).distance_to(expected) > 0.002:
			value_ok = false
	_check(interior == 29, "the bake writes exactly 29 interior samples")
	_check(grid_ok, "every interior key sits on the document frame grid")
	_check(inside_ok, "every interior key is strictly inside the segment")
	_check(transition_ok, "every baked key uses transition 1.0")
	_check(value_ok, "baked values match _curve_value(cubic_ease)")
	_check(absf(float(keys[0]["time"])) < 0.0001 and absf(float(keys[30]["time"]) - 1.0) < 0.0001,
		"endpoint keys are preserved")
	_check(doc.curve_segments().size() == 1, "the bake writes one curve record")
	var record: Dictionary = doc.curve_segments()[0]
	_check(str(record.get("family", "")) == "cubic", "the record family is cubic")
	_check(int(record.get("samples", 0)) == 29, "the record reports 29 samples")
	_check(str(record.get("preset", "")) == "custom", "a manual bake is a Custom preset")

	var span: Dictionary = doc.segment_span_at(id, "position", 0.5)
	_check(str(span.get("kind", "")) == "record", "an interior time resolves to the recorded segment")
	_check(absf(float(span.get("start", -1.0))) < 0.0001 and absf(float(span.get("end", -1.0)) - 1.0) < 0.0001,
		"the recorded segment keeps its authored span")

	doc.undo()
	_check(doc.get_channel_keys(id, "position").size() == 2, "undo restores the two endpoint keys")
	_check(doc.curve_segments().is_empty(), "undo removes the record")
	doc.redo()
	_check(doc.get_channel_keys(id, "position").size() == 31, "redo restores the baked keys")
	_check(doc.curve_segments().size() == 1, "redo restores the record")
	doc.queue_free()


func _test_bake_limits() -> void:
	print("GRAPH STEP: bake limits")
	var doc := _new_doc()
	var id := _cube(doc)
	doc.set_fps(30)
	_two_keys(doc, id, 0.0, 0.05)  # 1.5 frames
	var short: Dictionary = doc.bake_cubic_segment(id, "position", 0.0, 0.05, 0.2, 0.8, 0.8, 0.2)
	_check(not bool(short.get("ok", true)), "a sub-3-frame segment refuses the bake")
	_check(str(short.get("reason", "")) == "Segment too short to bake (3 frames minimum)",
		"the short-segment reason is exact")
	_check(doc.curve_segments().is_empty(), "a refused bake writes no metadata")

	var doc2 := _new_doc("Long Graph")
	var id2 := _cube(doc2)
	doc2.set_duration(12.0)
	_two_keys(doc2, id2, 0.0, 10.0)
	doc2.bake_cubic_segment(id2, "position", 0.0, 10.0, 0.2, 0.8, 0.8, 0.2)
	_check(doc2.get_channel_keys(id2, "position").size() == 50,
		"a 10 s segment at 30 fps caps at 48 interior keys")
	doc.queue_free()
	doc2.queue_free()


func _test_format4_persistence() -> void:
	print("GRAPH STEP: format 4 persistence")
	var doc := _new_doc()
	var id := _cube(doc)
	_two_keys(doc, id, 0.0, 1.0)
	doc.bake_cubic_segment(id, "position", 0.0, 1.0, 0.42, 0.0, 0.58, 1.0)
	var saved: Dictionary = doc.to_data()
	_check(int(saved.get("format", 0)) == 4, "saving writes format 4")
	var clips: Array = saved.get("clips", [])
	_check(clips.size() == 1 and (clips[0] as Dictionary).get("curve_segments", []).size() == 1,
		"the clip carries one curve_segments record")
	var copy = DocumentScript.new()
	add_child(copy)
	copy.load_project(saved)
	_check(copy.curve_segments().size() == 1, "loading format 4 keeps the record")
	var loaded: Dictionary = copy.curve_segments()[0]
	_check(absf(float(loaded.get("x1", 0.0)) - 0.42) < 0.000001
		and absf(float(loaded.get("x2", 0.0)) - 0.58) < 0.000001,
		"the cubic handles survive the round-trip")
	var span: Dictionary = copy.segment_span_at(id, "position", 0.5)
	_check(str(span.get("kind", "")) == "record", "the record is selectable by its span after reload")

	var v3: Dictionary = saved.duplicate(true)
	v3["format"] = 3
	((v3["clips"] as Array)[0] as Dictionary).erase("curve_segments")
	var old = DocumentScript.new()
	add_child(old)
	old.load_project(v3)
	_check(old.curve_segments().is_empty(), "a format-3 file loads with no curve metadata")
	_check(int(old.to_data().get("format", 0)) == 4, "a loaded v3 project saves as format 4")
	doc.queue_free()
	copy.queue_free()
	old.queue_free()


# -------------------------------------------------------------------------
# Task 16 — the segment graph
# -------------------------------------------------------------------------

func _host_graph(width: float, height: float):
	var doc := _new_doc()
	var id := _cube(doc)
	_two_keys(doc, id, 0.0, 1.0)
	var timeline = TimelineScript.new()
	add_child(timeline)
	timeline.setup(doc)
	timeline.set_available_width(width)
	timeline.size = Vector2(width, height)
	await get_tree().process_frame
	timeline.set_mode("graph")
	await get_tree().process_frame
	var graph = timeline.segment_graph()
	graph.set_context(id, "position")
	return {"doc": doc, "timeline": timeline, "graph": graph, "id": id}


func _test_segment_selection() -> void:
	print("GRAPH STEP: segment selection")
	var ctx = await _host_graph(600, 324)
	var doc = ctx["doc"]
	var graph = ctx["graph"]
	var id: String = ctx["id"]
	doc.apply_key_edits(id, "position", [
		{"index": -1, "time": 2.0, "value": Vector3(0, 5, 0)},
	], "Third key")
	var span: Dictionary = doc.segment_span_at(id, "position", 1.5)
	_check(str(span.get("kind", "")) == "plain", "between two keys is a plain segment")
	graph.set_selection(span)
	_check(graph.selection() == span, "the graph keeps the selected span")
	_check(graph.plot_rect().size.y >= 120.0, "the plot respects the 120 dp floor")
	_check(graph.key_points().size() == 3, "the graph draws every key")
	_check(graph.handle_hit_radius() == 22.0 and graph.key_hit_radius() == 22.0,
		"handles and keys keep 22 dp hit radii")
	var first: Dictionary = doc.segment_span_at(id, "position", 0.5)
	var next: Dictionary = doc.next_segment_span(id, "position", float(first["start"]), 1)
	_check(absf(float(next.get("start", -1.0)) - 1.0) < 0.0001,
		"next segment moves to the following interval")
	var prev: Dictionary = doc.next_segment_span(id, "position", float(first["start"]), -1)
	_check(prev.is_empty(), "previous at the first segment returns empty, not a wrap")
	var beyond: Dictionary = doc.next_segment_span(id, "position", float(span["start"]), 1)
	_check(beyond.is_empty(), "next after the last interval returns empty, not a wrap")

	# The graph zooms to the selected span with 24 dp padding.
	graph.set_selection(span)
	var point: Vector2 = graph.time_to_point(float(span["start"]))
	_check(absf(point.x - (graph.plot_rect().position.x + 24.0)) < 1.0,
		"the selected start sits 24 dp from the plot edge")
	ctx["timeline"].queue_free()
	doc.queue_free()


func _test_ease_tab() -> void:
	print("GRAPH STEP: ease tab")
	var ctx = await _host_graph(600, 324)
	var doc = ctx["doc"]
	var graph = ctx["graph"]
	var id: String = ctx["id"]
	var span: Dictionary = doc.segment_span_at(id, "position", 0.5)
	graph.set_selection(span)
	graph.set_tab("ease")
	_check(graph.tab() == "ease", "the Ease tab can be selected")
	_check(graph.handle_positions().size() == 2, "a linear segment shows two cubic handles")
	_check(not graph.engine_ease_visible(), "a transition-1.0 segment has no engine ease badge")
	var undo_before: int = (doc._undo_stack as Array).size()
	graph.handle_drag(
		graph.plot_rect().position + graph.plot_rect().size * Vector2(0.3, 0.8),
		graph.plot_rect().position + graph.plot_rect().size * Vector2(0.7, 0.2))
	_check(doc.curve_segments().size() == 1, "a handle drag writes a curve record")
	_check((doc._undo_stack as Array).size() == undo_before + 1,
		"a handle drag is exactly one undo entry")
	var record: Dictionary = doc.curve_segments()[0]
	_check(str(record.get("family", "")) == "cubic", "the dragged segment is cubic")
	_check(graph.convert_button() == null or not graph.convert_button().visible,
		"a cubic record does not offer Convert to cubic")
	_check(graph.clear_button() != null and graph.clear_button().visible,
		"a cubic record offers Clear curve")

	# A legacy engine transition exposes the scalar field, never fake handles.
	doc.undo()
	var keys: Array = doc.get_channel_keys(id, "position")
	doc.set_key_transition(id, "position", 0, 0.5)
	graph.set_selection(doc.segment_span_at(id, "position", 0.5))
	graph.refresh()
	_check(graph.engine_ease_visible(), "a transition-0.5 segment shows Engine ease")
	_check(graph.handle_positions().is_empty(), "engine ease shows no cubic handles")
	_check(graph.bake_ease_button() != null and graph.bake_ease_button().visible,
		"engine ease offers Bake ease")
	var engine_undo: int = (doc._undo_stack as Array).size()
	graph.bake_ease_button().pressed.emit()
	await get_tree().process_frame
	_check(doc.curve_segments().size() == 1, "Bake ease writes a baked record")
	_check(str(doc.curve_segments()[0].get("family", "")) == "baked", "the baked family is recorded")
	_check((doc._undo_stack as Array).size() == engine_undo + 1,
		"Bake ease is one undo entry")
	_check(graph.convert_button().visible, "a baked preset offers Convert to cubic")
	graph.convert_button().pressed.emit()
	await get_tree().process_frame
	_check(str(doc.curve_segments()[0].get("family", "")) == "cubic",
		"Convert to cubic writes linear handles")
	ctx["timeline"].queue_free()
	doc.queue_free()


func _test_preset_rail() -> void:
	print("GRAPH STEP: preset rail")
	var ctx = await _host_graph(600, 324)
	var graph = ctx["graph"]
	var doc = ctx["doc"]
	var id: String = ctx["id"]
	graph.set_selection(doc.segment_span_at(id, "position", 0.5))
	_check(graph.preset_ids() == PackedStringArray([
		"linear", "ease_in", "ease_out", "ease_in_out", "slow_in_fast_out",
		"back_out", "bounce", "elastic", "spring",
	]), "the rail lists the six cubic presets and three families")
	for preset in ["linear", "ease_in", "ease_out", "ease_in_out", "slow_in_fast_out", "back_out"]:
		_check(graph.preset_chip(preset) != null, "%s has a real chip" % preset)
		_check(graph.preset_chip(preset).custom_minimum_size.y >= 43.5,
			"%s chip is 44 dp tall" % preset)
	graph.preset_chip("ease_in_out").pressed.emit()
	await get_tree().process_frame
	var record: Dictionary = doc.curve_segments()[0]
	_check(absf(float(record.get("x1", 0.0)) - 0.42) < 0.001, "Ease in-out applies x1 0.42")
	_check(str(record.get("preset", "")) == "ease_in_out", "the preset id is recorded")
	ctx["timeline"].queue_free()
	doc.queue_free()
