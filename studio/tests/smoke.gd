extends Node
## Temporary headless smoke test. Not part of the app.

var _failures: Array[String] = []

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		printerr("SMOKE FAIL: " + message)
	else:
		print("SMOKE OK: " + message)

func _ready() -> void:
	await get_tree().process_frame
	_check(get_tree().root.theme != null, "app theme installed on root")
	_check(Kit.font_regular != null, "Inter loaded")
	_check(Kit.icon_texture("box") != null, "box icon loaded")

	var packed: PackedScene = load("res://src/app/main.tscn")
	var main: Control = packed.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._on_new_project_requested("Smoke Test", "study")
	await get_tree().process_frame
	await get_tree().process_frame
	var editor = main._editor
	_check(editor != null, "editor opened")
	if editor == null:
		_finish()
		return
	var doc = editor.doc
	_check(doc != null and doc.objects.size() >= 3, "study template has objects")
	_check(editor._view != null and editor._view._viewport != null, "preview viewport built")
	_check(doc.get_channel_keys(str(doc.objects[0]["id"]), "position").size() >= 0, "channels readable")

	# Settings sheet exercises NumberField construction and the apply callback.
	editor._open_settings()
	await get_tree().process_frame
	_check(editor._settings_duration_field != null, "settings duration field built")
	_check(editor._settings_fps_field != null, "settings fps field built")
	if editor._settings_duration_field != null:
		_check(is_equal_approx(editor._settings_duration_field.value, doc.duration), "settings field reads duration")
	editor._overlay.close_modal()
	await get_tree().process_frame

	# Add sheet + primitive creation.
	editor._open_add_sheet()
	await get_tree().process_frame
	editor._overlay.close_modal()
	await get_tree().process_frame
	var before_add: int = doc.objects.size()
	editor._add_primitive("sphere")
	await get_tree().process_frame
	_check(doc.objects.size() == before_add + 1, "primitive added")
	_check(doc.selected_id != "", "new primitive selected")

	# Keying + retime.
	doc.insert_transform_keys()
	var key_count := 0
	for channel in doc.CHANNELS:
		key_count += doc.get_channel_keys(doc.selected_id, channel).size()
	_check(key_count == 3, "three transform channels keyed")
	var key_index: int = doc.get_key_index_at(doc.selected_id, "position", doc.current_time, 0.02)
	_check(key_index >= 0, "position key found at playhead")
	if key_index >= 0:
		var new_index: int = doc.set_key_time(doc.selected_id, "position", key_index, 1.25)
		_check(new_index >= 0, "key retimed")

	# Color sheet and material write.
	var mesh_id: String = doc.selected_id
	editor._open_color_sheet("color")
	await get_tree().process_frame
	_check(editor._color_sheet_active, "color sheet active")
	editor._set_color_value(Color(0.2, 0.3, 0.4))
	_check(str(doc.get_object(mesh_id).get("color", "")).to_upper() == "#334D66", "color written to object")
	editor._overlay.close_modal()
	await get_tree().process_frame
	_check(not editor._color_sheet_active, "color sheet closed cleanly")

	print("SMOKE STEP: gizmo")
	# Gizmo drag must accumulate.
	var view = editor._view
	doc.set_selection(mesh_id)
	view.set_tool("move")
	await get_tree().process_frame
	var before_x: float = doc.get_selected_node().position.x
	view._start_gizmo("x", Vector2(100, 100))
	view._apply_gizmo_drag(Vector2(24, 0))
	var step_x: float = doc.get_selected_node().position.x
	view._apply_gizmo_drag(Vector2(24, 0))
	var total_x: float = doc.get_selected_node().position.x
	view._finish_gizmo()
	_check(not is_equal_approx(step_x, before_x), "gizmo drag changes value")
	_check(absf(total_x - before_x) > absf(step_x - before_x) + 0.01, "gizmo drag accumulates")

	print("SMOKE STEP: picking")
	var picked_light := false
	for obj in doc.objects:
		if str(obj.get("kind", "")) != "light":
			continue
		var lid := str(obj.get("id", ""))
		var lnode: Node3D = doc.nodes.get(lid)
		if lnode == null or view._camera.is_position_behind(lnode.global_position):
			continue
		var sp: Vector2 = view._to_ui(view._camera.unproject_position(lnode.global_position))
		if not Rect2(Vector2.ZERO, view.size).has_point(sp):
			continue
		view._pick(sp)
		picked_light = true
		_check(doc.selected_id == lid, "light picked near its marker")
		break
	if not picked_light:
		print("SMOKE SKIP: no on-screen light to pick")
	doc.set_selection(mesh_id)

	print("SMOKE STEP: viewport gizmos")
	_check(view._surface.show_behind_parent, "viewport marks draw above preview")
	_check(editor._overlay._toast_anchor == editor._viewport_host, "toast anchored to viewport")
	var marker_cam := Camera3D.new()
	marker_cam.position = Vector3(0.0, 2.0, 8.0)
	add_child(marker_cam)
	var light_id := ""
	for obj in doc.objects:
		if str(obj.get("kind", "")) == "light":
			light_id = str(obj.get("id", ""))
			break
	_check(light_id != "", "study has a light")
	if light_id != "":
		var light_node: Node3D = doc.nodes.get(light_id)
		var marker := light_node.get_node_or_null("Marker") as Node3D
		doc.update_marker_scales(marker_cam)
		_check(marker != null and marker.visible, "light marker visible at range")
		_check(marker.scale.x < 1.0, "light marker uses screen-space scale")
		marker_cam.position = light_node.global_position + Vector3(0.0, 0.0, 0.05)
		doc.update_marker_scales(marker_cam)
		_check(not marker.visible, "near light marker hidden")
		doc.markers_hidden = true
		marker_cam.position = Vector3(0.0, 2.0, 8.0)
		doc.update_marker_scales(marker_cam)
		_check(not marker.visible, "markers hidden for stills")
		doc.markers_hidden = false
	marker_cam.queue_free()

	# Undo / redo.
	var after_gizmo: float = doc.get_selected_node().position.x
	doc.undo()
	await get_tree().process_frame
	_check(absf(doc.get_selected_node().position.x - after_gizmo) > 0.001, "undo restores transform")
	doc.redo()
	await get_tree().process_frame

	print("SMOKE STEP: save/load")
	# Save, load and verify the document round trip.
	var saved_ok: bool = Store.save_project(doc)
	_check(saved_ok, "project saved")
	var loaded: Dictionary = Store.load_project(doc.project_id)
	_check(not loaded.is_empty(), "project loaded")
	if not loaded.is_empty():
		var other = preload("res://src/core/document.gd").new()
		add_child(other)
		var loaded_ok: bool = other.load_project(loaded.get("data", {}), str(loaded.get("meta", {}).get("path", "")))
		_check(loaded_ok, "document load returned true")
		_check(other.objects.size() == doc.objects.size(), "object count round trip")
		var source_keys := 0
		var loaded_keys := 0
		for channel in doc.CHANNELS:
			source_keys += doc.get_channel_keys(mesh_id, channel).size()
		for channel in other.CHANNELS:
			loaded_keys += other.get_channel_keys(mesh_id, channel).size()
		_check(source_keys == loaded_keys, "animation key count round trip")
		other.queue_free()
		await get_tree().process_frame

	# Leave and clean up the temporary project.
	var project_id: String = doc.project_id
	editor._leave(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(main._editor == null, "editor closed")
	_check(Store.delete_project(project_id), "temporary project deleted")
	_finish()

func _finish() -> void:
	if _failures.is_empty():
		print("SMOKE RESULT: PASS")
	else:
		printerr("SMOKE RESULT: %d FAILURE(S)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
