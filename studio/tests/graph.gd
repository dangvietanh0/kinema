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
	await _test_cubic_bake_edges()
	await _test_v3_round_trip()
	await _test_segment_selection()
	await _test_ease_tab()
	await _test_preset_rail()
	await _test_value_tab()
	await _test_press_relative_value_drag()
	await _test_endpoint_rebake_and_invalidation()
	await _test_endpoint_shrink()
	await _test_speed_tab()
	await _test_family_presets_and_clear()
	await _test_all_presets()
	await _test_clip_isolation()
	await _test_timeline_transport_and_headers()
	await _test_animate_sizes()
	await _test_compact_curve_actions()
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


func _test_cubic_bake_edges() -> void:
	print("GRAPH STEP: cubic bake edges")
	var ctx = await _host_graph(600, 324)
	var doc = ctx["doc"]
	var graph = ctx["graph"]
	var timeline = ctx["timeline"]
	var id: String = ctx["id"]
	# A third key leaves a plain interval after the record so navigation has
	# somewhere real to land.
	doc.apply_key_edits(id, "position", [
		{"index": -1, "time": 2.0, "value": Vector3(0, 5, 0)},
	], "Third key")
	var undo_before: int = (doc._undo_stack as Array).size()
	doc.bake_cubic_segment(id, "position", 0.0, 1.0, 0.2, 0.8, 0.8, 0.2)
	_check((doc._undo_stack as Array).size() == undo_before + 1,
		"the edges bake is exactly one undo entry")
	var keys: Array = doc.get_channel_keys(id, "position")
	_check(keys.size() == 32, "the edges bake keeps the key after the record")
	var interior := 0
	for i in range(1, keys.size() - 1):
		var t := float(keys[i]["time"])
		if t > 0.001 and t < 0.999:
			interior += 1
	_check(interior == 29, "the edges bake writes 29 keys strictly inside 0-1 s")
	_check(absf(float(keys[keys.size() - 1]["time"]) - 2.0) < 0.0001,
		"the key at 2 s survives the bake untouched")

	# Sample the real baked track at five frame-grid times. This is the same
	# interpolation playback uses, not a separate UI approximation.
	var v0: Vector3 = keys[0]["value"]
	var v1: Vector3 = doc.sample_channel(id, "position", 1.0)
	var samples_ok := true
	for sample_time in [0.0, 0.2, 0.5, 0.8, 1.0]:
		doc.seek(float(sample_time))
		var played: Vector3 = doc.sample_channel(id, "position", float(sample_time))
		var expected: Vector3 = doc._curve_value("position", v0, v1,
			SpeedCurveScript.cubic_ease(float(sample_time), 0.2, 0.8, 0.8, 0.2))
		if played.distance_to(expected) > 0.002:
			samples_ok = false
	_check(samples_ok, "playback matches the cubic at five sample times")

	# A tap inside the bake selects the whole record; prev/next treat it as
	# one interval instead of 29 separate interior keys.
	graph.clear_selection()
	graph.set_tab("ease")
	var tap := Vector2(graph.time_to_point(0.5).x, graph.plot_rect().get_center().y)
	graph._press(tap)
	var tapped: Dictionary = graph.selection()
	_check(str(tapped.get("kind", "")) == "record",
		"a graph tap inside the bake selects the record")
	_check(absf(float(tapped.get("start", -1.0))) < 0.0001
		and absf(float(tapped.get("end", -1.0)) - 1.0) < 0.0001,
		"the tapped record keeps its authored 0-1 s span")
	_check(str(timeline.selected_span().get("kind", "")) == "record",
		"the tapped record is shared with the timeline")
	timeline.next_segment_button().pressed.emit()
	await get_tree().process_frame
	var next_span: Dictionary = timeline.selected_span()
	_check(str(next_span.get("kind", "")) == "plain"
		and absf(float(next_span.get("start", -1.0)) - 1.0) < 0.0001,
		"next segment skips the record's interior keys")
	timeline.prev_segment_button().pressed.emit()
	await get_tree().process_frame
	_check(str(timeline.selected_span().get("kind", "")) == "record",
		"prev segment returns to the record")
	ctx["timeline"].queue_free()
	doc.queue_free()


func _test_v3_round_trip() -> void:
	print("GRAPH STEP: format 4 and v3 round trip")
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

	# The reloaded record is a live curve, not frozen metadata: its handles
	# still resolve and a drag rewrites it in one transaction.
	var timeline = TimelineScript.new()
	add_child(timeline)
	timeline.setup(copy)
	timeline.set_available_width(600)
	timeline.size = Vector2(600, 324)
	await get_tree().process_frame
	timeline.set_mode("graph")
	await get_tree().process_frame
	var graph = timeline.segment_graph()
	graph.set_context(id, "position")
	graph.set_tab("ease")
	graph.set_selection(copy.segment_span_at(id, "position", 0.5))
	_check(graph.handle_positions().size() == 2,
		"the reloaded record exposes two draggable handles")
	var undo_before: int = (copy._undo_stack as Array).size()
	var op: Vector2 = graph.plot_rect().position
	var plot_size: Vector2 = graph.plot_rect().size
	graph.handle_drag(op + plot_size * Vector2(0.3, 0.8), op + plot_size * Vector2(0.7, 0.2))
	_check((copy._undo_stack as Array).size() == undo_before + 1,
		"a reloaded handle drag is one undo entry")
	_check(absf(float(copy.curve_segments()[0].get("x1", 0.0)) - 0.42) > 0.001,
		"a reloaded handle drag rewrites the cubic record")
	timeline.queue_free()

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

	# Tapping the middle plain segment selects it through the real graph path,
	# and the shared timeline receives the same span.
	graph.clear_selection()
	graph.set_tab("ease")
	var tap := Vector2(graph.time_to_point(1.5).x, graph.plot_rect().get_center().y)
	graph._press(tap)
	graph._release(tap)
	var tapped: Dictionary = graph.selection()
	_check(str(tapped.get("kind", "")) == "plain"
		and absf(float(tapped.get("start", -1.0)) - 1.0) < 0.0001
		and absf(float(tapped.get("end", -1.0)) - 2.0) < 0.0001,
		"tapping the middle plain segment selects its real 1-2 s span")
	_check(str(ctx["timeline"].selected_span().get("kind", "")) == "plain"
		and absf(float(ctx["timeline"].selected_span().get("start", -1.0)) - 1.0) < 0.0001,
		"the tapped segment is shared with the timeline")

	# The graph zooms to the selected span with 24 dp padding.
	var point: Vector2 = graph.time_to_point(float(tapped["start"]))
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
	# The real tab buttons switch the Three views without losing context.
	for tab_id in ["value", "speed", "ease"]:
		graph.tab_button(tab_id).pressed.emit()
		_check(graph.tab() == tab_id, "the %s tab button switches tabs" % tab_id)
	var span: Dictionary = doc.segment_span_at(id, "position", 0.5)
	graph.set_selection(span)
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
	_check(doc.get_channel_keys(id, "position").size() > 2,
		"Bake ease writes real interior keys")
	_check((doc._undo_stack as Array).size() == engine_undo + 1,
		"Bake ease is one undo entry")
	_check(graph.convert_button().visible, "a baked preset offers Convert to cubic")
	var convert_undo: int = (doc._undo_stack as Array).size()
	graph.convert_button().pressed.emit()
	await get_tree().process_frame
	_check(str(doc.curve_segments()[0].get("family", "")) == "cubic",
		"Convert to cubic writes linear handles")
	_check((doc._undo_stack as Array).size() == convert_undo + 1,
		"Convert to cubic is one undo entry")
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
		_check(graph.preset_chip(preset).custom_minimum_size.x >= 43.5
			and graph.preset_chip(preset).custom_minimum_size.y >= 43.5,
			"%s chip keeps a 44 dp target" % preset)
	graph.preset_chip("ease_in_out").pressed.emit()
	await get_tree().process_frame
	var record: Dictionary = doc.curve_segments()[0]
	_check(absf(float(record.get("x1", 0.0)) - 0.42) < 0.001, "Ease in-out applies x1 0.42")
	_check(str(record.get("preset", "")) == "ease_in_out", "the preset id is recorded")
	doc.undo()
	_check(doc.curve_segments().is_empty(), "undo removes the preset record")
	_check(doc.get_channel_keys(id, "position").size() == 2,
		"undo restores the preset's original keys")
	ctx["timeline"].queue_free()
	doc.queue_free()


# -------------------------------------------------------------------------
# Task 17 — transport, pane header, graph header and dope selection
# -------------------------------------------------------------------------

func _test_timeline_transport_and_headers() -> void:
	print("GRAPH STEP: timeline transport and headers")
	var ctx = await _host_graph(915, 500)
	var timeline = ctx["timeline"]
	var doc = ctx["doc"]
	var id: String = ctx["id"]
	_check(timeline.transport_panel().size.y >= 43.5, "the timeline transport is 44 dp")
	_check(timeline.pane_header().size.y >= 43.5, "the pane header is 44 dp")
	_check(timeline.graph_header().size.y >= 43.5, "the graph header is 44 dp")
	_check(timeline.play_button() != null, "the transport owns play/pause")
	_check(timeline.fps_button() != null, "the transport owns the fps chip")
	_check(timeline.snap_button() != null, "the transport owns snap")
	_check(timeline.add_key_button() != null, "the transport owns add key")
	_check(timeline.delete_key_button() != null, "the transport owns delete key")
	_check(timeline.fit_button() != null, "the transport owns fit")
	_check(timeline.duration_chip().custom_minimum_size.y >= 43.5,
		"the duration chip stays a 44 dp target")
	_check(timeline.clip_selector().custom_minimum_size.x >= 96.0
		and timeline.clip_selector().custom_minimum_size.x <= 160.0,
		"the clip selector is 96–160 dp")
	_check(timeline.dope_tab().custom_minimum_size.x >= 60.0
		and timeline.graph_tab_button().custom_minimum_size.x >= 60.0,
		"Dope and Graph are 60 dp tabs")
	_check(timeline.dope_tab().custom_minimum_size.y >= 43.5
		and timeline.graph_tab_button().custom_minimum_size.y >= 43.5,
		"Dope and Graph are 44 dp tall")
	_check(timeline.prev_segment_button().custom_minimum_size.x >= 44.0
		and timeline.next_segment_button().custom_minimum_size.x >= 44.0,
		"prev/next segment are 44 dp")
	var graph = timeline.segment_graph()
	for tab_id in ["ease", "value", "speed"]:
		var tab_button: Button = graph.tab_button(tab_id)
		_check(tab_button != null and tab_button.custom_minimum_size.x >= 43.5
			and tab_button.custom_minimum_size.y >= 43.5,
			"the %s tab keeps a 44 dp touch target" % tab_id)

	# The timeline asks the editor for the same real time entry sheet; the
	# editor connection is asserted in the booted shell test in Task 18.
	var time_requests: Array[String] = []
	timeline.time_entry_requested.connect(func() -> void: time_requests.append("time"))
	timeline.time_button().pressed.emit()
	_check(time_requests == ["time"],
		"the Animate timecode requests the real time entry sheet")

	# Graph mode uses the segment graph; Dope mode shows the dope sheet.
	timeline.set_mode("graph")
	_check(timeline.segment_graph().visible, "Graph shows the segment graph")
	_check(not timeline.dope_sheet_visible(), "Graph hides the dope sheet")
	timeline.set_mode("dope")
	_check(timeline.dope_sheet_visible(), "Dope shows the dope sheet")
	_check(not timeline.segment_graph().visible, "Dope hides the segment graph")

	# Dope tap selects the recorded span.
	doc.apply_key_edits(id, "position", [
		{"index": -1, "time": 2.0, "value": Vector3(20, 0, 0)},
	], "Third key")
	doc.bake_cubic_segment(id, "position", 0.0, 1.0, 0.2, 0.8, 0.8, 0.2)
	timeline.set_mode("dope")
	timeline.set_channel("position")
	_check(timeline.select_span_at_time(0.5), "a dope tap at an interior key selects its record")
	_check(str(timeline.selected_span().get("kind", "")) == "record",
		"the selected recorded segment is shared with the dope sheet")
	timeline.set_mode("graph")

	timeline.next_segment_button().pressed.emit()
	await get_tree().process_frame
	_check(str(timeline.selected_span().get("kind", "")) == "plain",
		"next segment skips the baked interior keys and lands on the next plain interval")
	timeline.prev_segment_button().pressed.emit()
	await get_tree().process_frame
	_check(str(timeline.selected_span().get("kind", "")) == "record",
		"prev segment returns to the recorded span")
	ctx["timeline"].queue_free()
	doc.queue_free()


# -------------------------------------------------------------------------
# Task 18 — Animate layout, stage preview and persisted state
# -------------------------------------------------------------------------

func _boot_main(width: int, height: int):
	get_window().size = Vector2i(width, height)
	await get_tree().process_frame
	var packed: PackedScene = load("res://src/app/main.tscn")
	var main: Control = packed.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main._on_new_project_requested("Animate Layout", "blank")
	await get_tree().process_frame
	await get_tree().process_frame
	return main


func _animate_at(width: int, height: int) -> Dictionary:
	# Auto-default tests need "never explicitly written"; tests share Prefs.
	Prefs.clear_value("editor.animate_stage")
	var main = await _boot_main(width, height)
	var editor = main._editor
	editor.set_workspace("animate")
	await get_tree().process_frame
	await get_tree().process_frame
	return {
		"main": main,
		"editor": editor,
		"stage": editor._stage_host.size.y,
		"pane": editor._animate_pane.size.y,
		"timeline": editor._timeline.size.y,
	}


func _menu_index(menu: PopupMenu, text_value: String) -> int:
	for i in range(menu.item_count):
		if menu.get_item_text(i) == text_value:
			return i
	return -1


func _test_compact_curve_actions() -> void:
	print("GRAPH STEP: compact curve actions")
	var ctx: Dictionary = await _animate_at(800, 360)
	var main = ctx["main"]
	var editor = ctx["editor"]
	var doc = editor.doc
	var id: String = doc.add_primitive("box", Vector3.ZERO)
	doc.set_fps(30)
	doc.set_duration(12.0)
	doc.set_selection(id)
	doc.apply_key_edits(id, "position", [
		{"index": -1, "time": 0.0, "value": Vector3.ZERO},
		{"index": -1, "time": 1.0, "value": Vector3(10, 0, 0)},
	], "Seed compact keys")
	var timeline = editor._timeline
	timeline.set_channel("position")
	timeline.set_mode("graph")
	await get_tree().process_frame
	var graph = timeline.segment_graph()
	graph.set_context(id, "position")
	timeline.select_span_at_time(0.5)
	graph.set_tab("ease")
	doc.set_key_transition(id, "position", 0, 0.5)
	graph.refresh()
	await get_tree().process_frame
	_check(not graph.rail_visible(), "800x360: the compact graph hides the rail")

	timeline._open_more_menu()
	var menu: PopupMenu = timeline._more_menu
	var bake_index := _menu_index(menu, "Bake ease")
	_check(bake_index >= 0, "800x360: More exposes Bake ease")
	_check(bake_index >= 0 and not menu.is_item_disabled(bake_index),
		"800x360: Bake ease is enabled for an engine transition")
	if bake_index >= 0:
		timeline._on_more_menu_id(menu.get_item_id(bake_index))
		await get_tree().process_frame
	_check(not doc.curve_segments().is_empty()
		and str(doc.curve_segments()[0].get("family", "")) == "baked",
		"800x360: More actually bakes the engine ease")

	timeline._open_more_menu()
	var convert_index := _menu_index(menu, "Convert to cubic")
	_check(convert_index >= 0, "800x360: More exposes Convert to cubic")
	_check(convert_index >= 0 and not menu.is_item_disabled(convert_index),
		"800x360: Convert to cubic is enabled for a baked record")
	if convert_index >= 0:
		timeline._on_more_menu_id(menu.get_item_id(convert_index))
		await get_tree().process_frame
	_check(not doc.curve_segments().is_empty()
		and str(doc.curve_segments()[0].get("family", "")) == "cubic",
		"800x360: More actually converts the record")

	timeline._open_more_menu()
	var clear_index := _menu_index(menu, "Clear curve")
	_check(clear_index >= 0, "800x360: More exposes Clear curve")
	_check(clear_index >= 0 and not menu.is_item_disabled(clear_index),
		"800x360: Clear curve is enabled for a record")
	if clear_index >= 0:
		timeline._on_more_menu_id(menu.get_item_id(clear_index))
		await get_tree().process_frame
	_check(doc.curve_segments().is_empty(), "800x360: More actually clears the curve")

	graph.set_tab("speed")
	timeline._open_more_menu()
	var edit_index := _menu_index(menu, "Edit ease")
	_check(edit_index >= 0, "800x360: More exposes Edit ease")
	_check(edit_index >= 0 and not menu.is_item_disabled(edit_index),
		"800x360: Edit ease is enabled outside the Ease tab")
	if edit_index >= 0:
		timeline._on_more_menu_id(menu.get_item_id(edit_index))
		await get_tree().process_frame
	_check(graph.tab() == "ease", "800x360: More actually opens the Ease tab")
	main.queue_free()
	await get_tree().process_frame


func _test_animate_sizes() -> void:
	print("GRAPH STEP: animate layout sizes")
	var ctx: Dictionary = await _animate_at(915, 412)
	var main = ctx["main"]
	var e = ctx["editor"]
	_check(absf(float(ctx["pane"]) - 324.0) <= 1.0, "915x412: the pane is 324 dp")
	_check(not e._animate_preview_visible, "915x412: stage preview is off")
	_check(e._timeline.pane_compacted(), "915x412: the headers are compacted")
	e._timeline.set_mode("dope")
	_check(absf(e._timeline.plot_height() - 192.0) <= 1.0, "915x412: Dope keeps a 192 dp plot")
	e._timeline.set_mode("graph")
	_check(e._timeline.segment_graph().rail_visible(), "915x412: Graph keeps the preset rail")
	_check(absf(e._timeline.segment_graph().plot_rect().size.y - 148.0) <= 1.0,
		"915x412: Graph keeps a 148 dp plot")
	_check(e._stage_toggle_action().get("disabled_reason", "") ==
		"Not enough height for stage preview", "915x412: the stage toggle states the reason")
	main.queue_free()
	await get_tree().process_frame

	ctx = await _animate_at(800, 360)
	main = ctx["main"]
	e = ctx["editor"]
	_check(absf(float(ctx["pane"]) - 272.0) <= 1.0, "800x360: the pane is 272 dp")
	e._timeline.set_mode("dope")
	_check(absf(e._timeline.plot_height() - 140.0) <= 1.0, "800x360: Dope keeps 140 dp")
	e._timeline.set_mode("graph")
	_check(not e._timeline.segment_graph().rail_visible(), "800x360: the rail is hidden")
	_check(e._timeline._presets_button.visible or e._timeline._narrow_presets_button.visible,
		"800x360: Graph offers its presets through the menu")
	_check(absf(e._timeline.segment_graph().plot_rect().size.y - 140.0) <= 1.0,
		"800x360: Graph keeps a 140 dp plot through the Presets menu")
	main.queue_free()
	await get_tree().process_frame

	ctx = await _animate_at(1280, 800)
	main = ctx["main"]
	e = ctx["editor"]
	_check(absf(float(ctx["stage"]) - 161.0) <= 1.0, "1280x800: the preview is 161 dp")
	_check(e._animate_preview_visible, "1280x800: the preview is on by default")
	_check(absf(float(ctx["pane"]) - 571.0) <= 1.0, "1280x800: the pane is 571 dp with the preview")
	_check(e._animate_pane.get_parent() == e._stage_host.get_parent(),
		"the Animate pane is a layout sibling of the stage")
	_check(not e._stage_host.is_ancestor_of(e._animate_pane)
		and not e._stage_host.is_ancestor_of(e._timeline),
		"the Animate pane and Timeline are not children of the stage host")
	e._toggle_animate_preview()
	await get_tree().process_frame
	_check(absf(e._animate_pane.size.y - 732.0) <= 1.0,
		"toggling the preview off restores the 732 dp pane")
	_check(bool(Prefs.get_value("editor.animate_stage", true)) == false,
		"the stage toggle persists under editor.animate_stage")
	main.queue_free()
	await get_tree().process_frame

	# A fresh boot restores the explicit choice instead of the auto default.
	var restored = await _boot_main(1280, 800)
	restored._editor.set_workspace("animate")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not restored._editor._animate_preview_visible,
		"a fresh boot restores the persisted stage choice")
	restored.queue_free()
	Prefs.clear_value("editor.animate_stage")


# -------------------------------------------------------------------------
# Task 19 — Value tab and key info
# -------------------------------------------------------------------------

func _test_value_tab() -> void:
	print("GRAPH STEP: value tab")
	var ctx = await _host_graph(600, 324)
	var doc = ctx["doc"]
	var graph = ctx["graph"]
	var timeline = ctx["timeline"]
	var id: String = ctx["id"]
	graph.set_selection(doc.segment_span_at(id, "position", 0.5))
	graph.set_tab("value")
	_check(graph.tab() == "value", "the Value tab can be selected")
	graph.set_component("x")
	_check(graph.component() == "x", "the X component can be selected")
	_check(graph.value_editable(), "a single position component is editable")
	var undo_before: int = (doc._undo_stack as Array).size()
	var keys_before: Array = doc.get_channel_keys(id, "position")
	var target: Vector2 = graph.time_to_point(0.8) + Vector2(0, -30)
	graph.drag_key(1, target)
	var keys_after: Array = doc.get_channel_keys(id, "position")
	_check(absf(float(keys_after[1]["time"]) - 0.8) < 0.05,
		"horizontal drag retimes the key on the frame grid")
	_check((keys_after[1]["value"] as Vector3).x > (keys_before[1]["value"] as Vector3).x,
		"vertical drag raises the X value")
	_check((doc._undo_stack as Array).size() == undo_before + 1,
		"one key drag is one undo entry")

	graph.set_component("all")
	_check(not graph.value_editable(), "All is read-only")
	_check(graph.value_hint() == "Choose X, Y or Z to edit values.",
		"All states the exact read-only hint")

	graph.set_context(id, "rotation")
	graph.set_tab("value")
	_check(not graph.value_editable(), "rotation values are not directly editable")
	_check(graph.value_hint().to_lower().contains("rotation") and graph.value_hint().contains("gizmo"),
		"rotation states the quaternion/gizmo warning")

	# Add key at the playhead samples the real channel value.
	doc.seek(0.25)
	graph.set_context(id, "position")
	graph.set_component("x")
	var count_before: int = doc.get_channel_keys(id, "position").size()
	var sampled_before: Vector3 = doc.sample_channel(id, "position", 0.25)
	_check(graph.add_key_at_playhead(), "Add key inserts at the playhead")
	_check(doc.get_channel_keys(id, "position").size() == count_before + 1,
		"Add key writes a real key")
	var added_index: int = doc.get_key_index_at(id, "position", 0.25)
	_check(added_index >= 0, "the inserted key sits at the playhead")
	var added: Dictionary = doc.get_channel_keys(id, "position")[added_index]
	_check((added["value"] as Vector3).distance_to(sampled_before) < 0.01,
		"Add key samples the real channel value")
	graph.delete_selected_key()
	_check(doc.get_channel_keys(id, "position").size() == count_before,
		"Delete key removes the selected key")
	ctx["timeline"].queue_free()
	doc.queue_free()


func _mouse_button(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	return event


func _test_press_relative_value_drag() -> void:
	print("GRAPH STEP: press-relative value drag")
	var ctx = await _host_graph(600, 324)
	var doc = ctx["doc"]
	var graph = ctx["graph"]
	var id: String = ctx["id"]
	graph.clear_selection()
	graph.set_tab("value")
	graph.set_component("x")
	graph.refresh()
	var press: Vector2 = graph.time_to_point(1.0)
	var release: Vector2 = press + Vector2(6, -24)
	# Resolve the expected time against the view that is on screen before the
	# press selects (and zooms to) the 0-1 s segment.
	var expected_time: float = graph.point_to_time(release)
	_check(expected_time > 1.1, "the pre-zoom 6 px drag resolves past 1.1 s")
	graph._gui_input(_mouse_button(press, true))
	graph._gui_input(_mouse_button(release, false))
	var keys: Array = doc.get_channel_keys(id, "position")
	var end_key: int = keys.size() - 1
	_check(absf(float(keys[end_key]["time"]) - expected_time) <= 1.0 / 30.0 + 0.001,
		"a 6 px press-release drag moves the key by the pre-zoom delta")
	_check(float(keys[end_key]["time"]) > 1.0,
		"the release point does not jump to the re-zoomed view")
	var info: Dictionary = graph.selected_key_info()
	_check(int(info.get("index", -1)) == end_key,
		"selection follows the moved key index")
	_check(absf(float(graph.selection().get("end", -1.0)) - float(keys[end_key]["time"])) < 0.001,
		"selection uses the moved key time, not the raw release point")
	ctx["timeline"].queue_free()
	doc.queue_free()


func _test_endpoint_shrink() -> void:
	print("GRAPH STEP: endpoint shrink")
	var ctx = await _host_graph(600, 324)
	var doc = ctx["doc"]
	var graph = ctx["graph"]
	var id: String = ctx["id"]
	doc.bake_cubic_segment(id, "position", 0.0, 1.0, 0.2, 0.8, 0.8, 0.2)
	graph.set_selection(doc.segment_span_at(id, "position", 0.5))
	graph.set_tab("value")
	graph.set_component("x")
	var end_key: int = doc.get_channel_keys(id, "position").size() - 1
	graph.drag_key(end_key, graph.time_to_point(0.5))
	var keys: Array = doc.get_channel_keys(id, "position")
	_check(absf(float(keys[keys.size() - 1]["time"]) - 0.5) < 0.001,
		"an endpoint shrinks past the adjacent baked interior keys")
	_check(keys.size() == 16, "shrinking rebakes the interior and drops stale keys")
	var record: Dictionary = doc.curve_segments()[0] if not doc.curve_segments().is_empty() else {}
	_check(absf(float(record.get("end", -1.0)) - 0.5) < 0.001,
		"the record span follows the shrunk endpoint")
	ctx["timeline"].queue_free()
	doc.queue_free()

	# Shrinking all the way onto the other endpoint merges the duplicate times
	# (Godot keeps one key per time). The merged key must keep the moved value
	# and be the one the graph selects, not the authored start.
	ctx = await _host_graph(600, 324)
	doc = ctx["doc"]
	graph = ctx["graph"]
	id = ctx["id"]
	doc.bake_cubic_segment(id, "position", 0.0, 1.0, 0.2, 0.8, 0.8, 0.2)
	graph.set_selection(doc.segment_span_at(id, "position", 0.5))
	graph.set_tab("value")
	graph.set_component("x")
	var start_value: Vector3 = doc.get_channel_keys(id, "position")[0]["value"]
	end_key = doc.get_channel_keys(id, "position").size() - 1
	graph.drag_key(end_key, graph.time_to_point(0.0) + Vector2(0, -20))
	keys = doc.get_channel_keys(id, "position")
	_check(keys.size() == 1, "a zero-length shrink merges the duplicate times")
	_check(keys.size() == 1 and absf(float(keys[0]["time"])) < 0.000001,
		"the merged key sits at the authored start time")
	_check(doc.curve_segments().is_empty(),
		"a zero-length endpoint move drops the record instead of guessing a span")
	var info: Dictionary = graph.selected_key_info()
	_check(int(info.get("index", -1)) == 0,
		"duplicate-time selection resolves to the merged moved key")
	_check(keys.size() == 1
		and float((keys[0]["value"] as Vector3).x) > float(start_value.x),
		"the merged key keeps the moved value, not the authored start")
	ctx["timeline"].queue_free()
	doc.queue_free()


func _test_endpoint_rebake_and_invalidation() -> void:
	print("GRAPH STEP: value endpoint rebake")
	var ctx = await _host_graph(600, 324)
	var doc = ctx["doc"]
	var graph = ctx["graph"]
	var id: String = ctx["id"]
	doc.bake_cubic_segment(id, "position", 0.0, 1.0, 0.2, 0.8, 0.8, 0.2)
	graph.set_selection(doc.segment_span_at(id, "position", 0.5))
	graph.set_tab("value")
	graph.set_component("x")
	var undo_before: int = (doc._undo_stack as Array).size()
	var end_key: int = doc.get_channel_keys(id, "position").size() - 1
	graph.drag_key(end_key, graph.time_to_point(1.5))
	_check((doc._undo_stack as Array).size() == undo_before + 1,
		"an endpoint drag and its re-bake are one undo entry")
	var record: Dictionary = doc.curve_segments()[0]
	_check(absf(float(record.get("end", 0.0)) - 1.5) < 0.05,
		"the record span follows the moved endpoint")
	_check(doc.get_channel_keys(id, "position").size() > 31,
		"the new span is re-baked with real interior keys")

	# Dragging an interior key invalidates the record and keeps the edit.
	# Move it in value, not time: baked interior keys sit one frame apart, so
	# a horizontal drag would clamp against its neighbour and prove nothing.
	var interior := 5
	var interior_time: float = doc.get_channel_keys(id, "position")[interior]["time"]
	graph.drag_key(interior, graph.time_to_point(interior_time) + Vector2(0, -30))
	_check(doc.curve_segments().is_empty(), "an interior key edit invalidates the record")
	_check(doc.get_channel_keys(id, "position").size() > 2,
		"the edited key is kept as a normal key")
	ctx["timeline"].queue_free()
	doc.queue_free()

	# Deleting an interior key is the same edit path: the record that owned it
	# is dropped in the same transaction and every other key survives.
	ctx = await _host_graph(600, 324)
	doc = ctx["doc"]
	graph = ctx["graph"]
	id = ctx["id"]
	doc.bake_cubic_segment(id, "position", 0.0, 1.0, 0.2, 0.8, 0.8, 0.2)
	graph.set_selection(doc.segment_span_at(id, "position", 0.5))
	graph.set_tab("value")
	graph.set_component("x")
	var delete_keys: Array = doc.get_channel_keys(id, "position")
	var delete_time := float(delete_keys[5]["time"])
	var delete_point: Vector2 = graph.time_to_point(delete_time)
	var delete_undo: int = (doc._undo_stack as Array).size()
	graph._press(delete_point)
	graph._release(delete_point)
	_check(graph.selected_key_info().size() > 0,
		"a value-tab tap selects the interior key before deletion")
	graph.delete_selected_key()
	_check(doc.curve_segments().is_empty(),
		"deleting an interior key invalidates the record")
	_check(doc.get_channel_keys(id, "position").size() == delete_keys.size() - 1,
		"deleting an interior key keeps every other key")
	_check((doc._undo_stack as Array).size() == delete_undo + 1,
		"delete key inside a record is one undo entry")
	ctx["timeline"].queue_free()
	doc.queue_free()


# -------------------------------------------------------------------------
# Task 20 — Speed tab, family presets and conversion
# -------------------------------------------------------------------------

func _test_speed_tab() -> void:
	print("GRAPH STEP: speed tab")
	var ctx = await _host_graph(600, 324)
	var doc = ctx["doc"]
	var graph = ctx["graph"]
	var id: String = ctx["id"]
	graph.set_selection(doc.segment_span_at(id, "position", 0.5))
	graph.set_tab("speed")
	var summary: Dictionary = graph.speed_summary()
	_check(is_finite(float(summary.get("average", NAN))), "speed average is finite")
	_check(is_finite(float(summary.get("peak", NAN))), "speed peak is finite")
	_check(absf(float(summary.get("average", 0.0)) - 10.0) < 0.5,
		"a 10-unit move over 1 s averages 10 units/s")
	_check(absf(float(summary.get("peak", 0.0)) - 10.0) < 0.5,
		"linear speed peaks at the same 10 units/s")
	_check(graph.handle_positions().is_empty(), "Speed never draws draggable handles")
	_check(graph.value_editable() == false, "Speed is read-only")
	var before_tab: String = graph.tab()
	graph.edit_ease_button().pressed.emit()
	_check(graph.tab() == "ease" and before_tab == "speed",
		"Edit ease switches to Ease with the same segment")
	_check(graph.selection() == doc.segment_span_at(id, "position", 0.5),
		"the selection survives the tab switch")

	# Rotation speed is angular, not a component delta. Use a second cube in
	# the same document: the graph is bound to `doc` and cannot sample another
	# document's objects.
	var rid: String = _cube(doc)
	doc.apply_key_edits(rid, "rotation", [
		{"index": -1, "time": 0.0, "value": Quaternion.IDENTITY},
		{"index": -1, "time": 1.0, "value": Quaternion(Vector3.UP, PI / 2.0)},
	], "Rotation keys")
	graph.set_context(rid, "rotation")
	graph.set_selection(doc.segment_span_at(rid, "rotation", 0.5))
	graph.set_tab("speed")
	var rsummary: Dictionary = graph.speed_summary()
	_check(absf(float(rsummary.get("average", 0.0)) - PI / 2.0) < 0.15,
		"rotation speed is angular radians per second")
	ctx["timeline"].queue_free()
	doc.queue_free()


func _test_family_presets_and_clear() -> void:
	print("GRAPH STEP: family presets and clear")
	var ctx = await _host_graph(600, 324)
	var doc = ctx["doc"]
	var graph = ctx["graph"]
	var id: String = ctx["id"]
	graph.set_selection(doc.segment_span_at(id, "position", 0.5))
	graph.set_tab("ease")
	var expected_curves := {
		"bounce": "bounce_out",
		"elastic": "elastic_out",
		"spring": "spring",
	}
	for family_id in expected_curves.keys():
		graph.set_selection(doc.segment_span_at(id, "position", 0.5))
		graph.preset_chip(family_id).pressed.emit()
		await get_tree().process_frame
		var family_record: Dictionary = doc.curve_segments()[0]
		_check(str(family_record.get("family", "")) == "preset",
			"%s records the preset family" % family_id)
		_check(str(family_record.get("preset", "")) == str(expected_curves[family_id]),
			"%s records its curve id" % family_id)
		_check(int(family_record.get("samples", 0)) > 0,
			"%s bakes real samples" % family_id)
	var undo_before: int = (doc._undo_stack as Array).size()
	graph.preset_chip("bounce").pressed.emit()
	await get_tree().process_frame
	_check(doc.curve_segments().size() == 1, "Bounce writes a record")
	_check(str(doc.curve_segments()[0].get("family", "")) == "preset",
		"Bounce records the preset family")
	_check(graph.handle_positions().is_empty(), "a family preset shows no cubic handles")
	_check(graph.baked_label().contains("Baked preset"), "a family preset says Baked preset")
	var badge: Label = graph.baked_badge() if graph.has_method("baked_badge") else null
	_check(badge != null and badge.visible and badge.text == "Baked preset",
		"a family preset renders the Baked preset label")
	_check((doc._undo_stack as Array).size() == undo_before + 1,
		"one family preset is one undo entry")
	_check(graph.convert_button().visible, "a family preset offers Convert to cubic")
	graph.convert_button().pressed.emit()
	await get_tree().process_frame
	_check(str(doc.curve_segments()[0].get("family", "")) == "cubic",
		"Convert to cubic changes the family")
	_check(graph.baked_badge() == null or not graph.baked_badge().visible,
		"the Baked preset label disappears for a cubic record")
	_check(graph.handle_positions().size() == 2,
		"the converted segment exposes linear cubic handles")
	var converted_undo: int = (doc._undo_stack as Array).size()
	var record: Dictionary = doc.curve_segments()[0]
	_check(absf(float(record.get("x1", 0.0)) - 1.0 / 3.0) < 0.001
		and absf(float(record.get("y1", 0.0)) - 1.0 / 3.0) < 0.001,
		"Convert to cubic starts at the linear handles")
	var op: Vector2 = graph.plot_rect().position
	var plot_size: Vector2 = graph.plot_rect().size
	graph.handle_drag(op + plot_size * Vector2(0.3, 0.8),
		op + plot_size * Vector2(0.7, 0.2))
	_check((doc._undo_stack as Array).size() == converted_undo + 1,
		"the first handle drag after conversion is one undo entry")
	_check(str(doc.curve_segments()[0].get("preset", "")) == "custom",
		"dragging after conversion marks the preset Custom")

	var live: Dictionary = doc.curve_segments()[0]
	_check(live.has("restore_transition"),
		"the handle drag keeps the recorded restore transition")
	var start_transition := float(live.get("restore_transition", 1.0))
	var clear_undo: int = (doc._undo_stack as Array).size()
	graph.clear_button().pressed.emit()
	await get_tree().process_frame
	_check(doc.curve_segments().is_empty(), "Clear curve removes the record")
	_check(doc.get_channel_keys(id, "position").size() == 2,
		"Clear curve keeps the two endpoint keys")
	_check(absf(float(doc.get_key_transition(id, "position", 0)) - start_transition) < 0.000001,
		"Clear curve restores the recorded start transition")
	_check((doc._undo_stack as Array).size() == clear_undo + 1,
		"Clear curve is one undo entry")
	doc.undo()
	_check(doc.curve_segments().size() == 1, "undo restores the cleared record")
	var restored: Dictionary = doc.curve_segments()[0]
	_check(str(restored.get("preset", "")) == "custom"
		and absf(float(restored.get("x1", 0.0)) - float(live.get("x1", 0.0))) < 0.000001,
		"undo restores the record's metadata")
	_check(absf(float(restored.get("restore_transition", 0.0)) - start_transition) < 0.000001,
		"undo restores the recorded transition")
	ctx["timeline"].queue_free()
	doc.queue_free()


func _test_all_presets() -> void:
	print("GRAPH STEP: preset handles")
	var expected := {
		"linear": [1.0 / 3.0, 1.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0],
		"ease_in": [0.42, 0.0, 1.0, 1.0],
		"ease_out": [0.0, 0.0, 0.58, 1.0],
		"ease_in_out": [0.42, 0.0, 0.58, 1.0],
		"slow_in_fast_out": [0.7, 0.0, 1.0, 1.0],
		"back_out": [0.34, 1.56, 0.64, 1.0],
	}
	for preset_id in expected.keys():
		var ctx = await _host_graph(600, 324)
		var doc = ctx["doc"]
		var graph = ctx["graph"]
		var id: String = ctx["id"]
		graph.set_selection(doc.segment_span_at(id, "position", 0.5))
		graph.set_tab("ease")
		graph.preset_chip(preset_id).pressed.emit()
		await get_tree().process_frame
		var record: Dictionary = doc.curve_segments()[0]
		var values: Array = expected[preset_id]
		_check(absf(float(record.get("x1", 0.0)) - float(values[0])) < 0.001
			and absf(float(record.get("y1", 0.0)) - float(values[1])) < 0.001
			and absf(float(record.get("x2", 0.0)) - float(values[2])) < 0.001
			and absf(float(record.get("y2", 0.0)) - float(values[3])) < 0.001,
			"%s writes its exact handles" % preset_id)
		ctx["timeline"].queue_free()
		doc.queue_free()


func _test_clip_isolation() -> void:
	print("GRAPH STEP: clip curve isolation")
	var ctx = await _host_graph(600, 324)
	var doc = ctx["doc"]
	var graph = ctx["graph"]
	var id: String = ctx["id"]
	doc.bake_cubic_segment(id, "position", 0.0, 1.0, 0.2, 0.8, 0.8, 0.2)
	var first_clip: String = doc.active_clip_id()
	_check(doc.curve_segments().size() == 1, "the first clip owns its record")
	var second: String = doc.animation_system.create_clip("Second", 12.0)
	doc.set_active_clip(second)
	_check(doc.curve_segments().is_empty(), "a fresh clip starts with no records")
	doc.apply_key_edits(id, "position", [
		{"index": -1, "time": 0.0, "value": Vector3.ZERO},
		{"index": -1, "time": 2.0, "value": Vector3(0, 10, 0)},
	], "Second clip keys")
	doc.bake_cubic_segment(id, "position", 0.0, 2.0, 0.42, 0.0, 0.58, 1.0)
	_check(doc.curve_segments().size() == 1, "the second clip writes its own record")
	var second_record: Dictionary = doc.curve_segments()[0]
	_check(absf(float(second_record.get("x1", 0.0)) - 0.42) < 0.000001
		and absf(float(second_record.get("end", 0.0)) - 2.0) < 0.000001,
		"the second clip keeps its own handles and span")
	doc.set_active_clip(first_clip)
	var first_record: Dictionary = doc.curve_segments()[0]
	_check(absf(float(first_record.get("x1", 0.0)) - 0.2) < 0.000001
		and absf(float(first_record.get("end", 0.0)) - 1.0) < 0.000001,
		"switching back restores the first clip's metadata")
	graph.set_context(id, "position")
	graph.set_selection(doc.segment_span_at(id, "position", 0.5))
	var first_span: Dictionary = graph.selection()
	_check(str(first_span.get("kind", "")) == "record"
		and absf(float(first_span.get("end", 0.0)) - 1.0) < 0.0001,
		"the graph follows the first clip's span")
	doc.set_active_clip(second)
	var second_span: Dictionary = doc.segment_span_at(id, "position", 1.0)
	_check(str(second_span.get("kind", "")) == "record"
		and absf(float(second_span.get("end", 0.0)) - 2.0) < 0.0001,
		"the second clip resolves its own 2 s record")
	_check(doc.curve_segments().size() == 1
		and absf(float(doc.curve_segments()[0].get("x2", 0.0)) - 0.58) < 0.000001,
		"the second clip does not inherit the first clip's metadata")
	ctx["timeline"].queue_free()
	doc.queue_free()
