extends Node
## Temporary headless smoke test. Not part of the app.

const RenderExport = preload("res://src/core/render_export.gd")

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

	print("SMOKE STEP: easing")
	# A fresh object with a clean two-key segment so the sampled curve is
	# unambiguous: x goes from 0 at t=0 to 2 at t=2.
	editor._add_primitive("box")
	await get_tree().process_frame
	var ease_id: String = doc.selected_id
	doc.seek(0.0)
	doc.set_object_transform(ease_id, Vector3.ZERO, Quaternion.IDENTITY, Vector3.ONE, false)
	doc.insert_transform_keys()
	doc.seek(2.0)
	doc.set_object_transform(ease_id, Vector3(2.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE, false)
	doc.insert_transform_keys()
	var ease_keys: Array = doc.get_channel_keys(ease_id, "position")
	_check(ease_keys.size() == 2, "easing segment has two position keys")
	if ease_keys.size() == 2:
		_check(is_equal_approx(doc.get_key_transition(ease_id, "position", 0), 1.0), "key transition defaults to linear")
		var midpoint: Vector3 = doc.sample_channel(ease_id, "position", 1.0)
		_check(absf(midpoint.x - 1.0) < 0.01, "linear easing samples the midpoint")
		doc.set_key_transition(ease_id, "position", 0, 0.5)
		_check(is_equal_approx(doc.get_key_transition(ease_id, "position", 0), 0.5), "key transition can be set")
		var eased_out: Vector3 = doc.sample_channel(ease_id, "position", 0.5)
		_check(eased_out.x > 0.6, "low transition eases out")
		doc.set_key_transition(ease_id, "position", 0, 2.0)
		var eased_in: Vector3 = doc.sample_channel(ease_id, "position", 0.5)
		_check(eased_in.x < 0.4, "high transition eases in")
		doc.set_key_transition(ease_id, "position", 0, 0.0)
		var held: Vector3 = doc.sample_channel(ease_id, "position", 1.0)
		_check(absf(held.x) < 0.01, "zero transition holds the previous key")
		doc.set_key_transition(ease_id, "position", 0, 0.75)
		var moved_index: int = doc.set_key_time(ease_id, "position", 0, 0.5)
		_check(moved_index >= 0, "eased key retimed")
		_check(is_equal_approx(doc.get_key_transition(ease_id, "position", moved_index), 0.75), "retiming preserves easing")
		doc.seek(0.0)

	print("SMOKE STEP: graph editor")
	var timeline = editor._timeline
	_check(timeline != null, "timeline exists")
	if timeline != null:
		timeline.set_mode("graph")
		_check(timeline._mode == "graph", "graph mode activates")
		var graph_speed: float = timeline._channel_speed(ease_id, "position", 1.0)
		_check(graph_speed > 0.01, "graph samples real channel speed")
		timeline.set_mode("dope")
		_check(timeline._mode == "dope", "dope mode restores")

	print("SMOKE STEP: render export")
	var frame_dir := "user://render_export_fixture"
	DirAccess.make_dir_recursive_absolute(frame_dir)
	for i in range(3):
		var frame := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		frame.fill(Color(0.1 * float(i), 0.2, 0.3))
		frame.save_png(frame_dir.path_join("frame_%04d.png" % i))
	var sequence_zip := "user://render_export_fixture.zip"
	_check(RenderExport.zip_directory(frame_dir, sequence_zip), "sequence zip written")
	var zip_reader := ZIPReader.new()
	_check(zip_reader.open(sequence_zip) == OK, "sequence zip readable")
	if zip_reader.open(sequence_zip) == OK:
		_check(zip_reader.get_files().size() == 3, "sequence zip contains every frame")
		zip_reader.close()
	var first_seq_dir := RenderExport.sequence_dir("user://sequence_fixture")
	DirAccess.make_dir_recursive_absolute(first_seq_dir)
	var second_seq_dir := RenderExport.sequence_dir("user://sequence_fixture")
	_check(first_seq_dir != second_seq_dir, "sequence directories do not collide")
	DirAccess.remove_absolute(first_seq_dir)
	DirAccess.remove_absolute("user://sequence_fixture")
	for i in range(3):
		DirAccess.remove_absolute(frame_dir.path_join("frame_%04d.png" % i))
	DirAccess.remove_absolute(frame_dir)
	DirAccess.remove_absolute(sequence_zip)

	print("SMOKE STEP: render sheet")
	editor._open_render_sheet()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._overlay.has_modal(), "render sheet opens")
	_check(editor._render_sequence_button != null, "render sheet has sequence action")
	_check(editor._render_progress != null, "render sheet has progress readout")
	_check(editor._sequence_frame_count() == 144, "sequence frame count follows duration and fps")
	_check(not editor._render_busy, "render sheet is idle on open")
	editor._overlay.close_modal()
	await get_tree().process_frame

	print("SMOKE STEP: graphics preset state")
	editor._open_graphics_settings()
	await get_tree().process_frame
	_check(editor._preset_buttons.size() == 3, "graphics preset chips exist")
	var original_preset: String = Gfx.preset
	Gfx.preset = "custom"
	editor._sync_preset_buttons()
	var any_preset_lit := false
	for button in editor._preset_buttons:
		if button.button_pressed:
			any_preset_lit = true
	_check(not any_preset_lit, "custom settings clear the preset selection")
	Gfx.preset = "balanced"
	editor._sync_preset_buttons()
	var balanced_lit := false
	for chip in editor._preset_buttons:
		if str(chip.get_meta("preset", "")) == "balanced" and chip.button_pressed:
			balanced_lit = true
	_check(balanced_lit, "balanced preset reselects its chip")
	Gfx.preset = original_preset
	editor._overlay.close_modal()
	await get_tree().process_frame

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
		_check(is_equal_approx(other.get_key_transition(mesh_id, "position", 0), 0.75), "key easing round trip")
		other.queue_free()
		await get_tree().process_frame

	print("SMOKE STEP: OBJ import")
	# A real OBJ+MTL+texture fixture exercises copying, reference rewriting and
	# the runtime mesh parser end to end.
	var fixture := "user://obj_import_fixture"
	DirAccess.make_dir_recursive_absolute(fixture)
	var texture := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	texture.fill(Color(0.9, 0.4, 0.1))
	texture.save_png(fixture.path_join("tex.png"))
	_write_test_text(fixture.path_join("sample.mtl"), "newmtl Painted\nKd 0.8 0.2 0.1\nNs 250\nmap_Kd tex.png\n")
	_write_test_text(
		fixture.path_join("sample.obj"),
		"mtllib sample.mtl\no Quad\nv\t-1 0 -1\nv 1 0 -1\nv 1 0 1\nv -1 0 1\nvt 0 0\nvt 1 0\nvt 1 1\nvt 0 1\nusemtl Painted\nf\t1/1 2/2 3/3 4/4\n"
	)
	var import_result: Dictionary = Store.import_model(fixture.path_join("sample.obj"), doc.project_dir, "Sample")
	_check(bool(import_result.get("ok", false)), "obj import succeeds")
	if bool(import_result.get("ok", false)):
		var imported_rel := str(import_result.get("rel_path", ""))
		var imported_folder: String = doc.project_dir.path_join(imported_rel).get_base_dir()
		_check(FileAccess.file_exists(imported_folder.path_join("materials/sample.mtl")), "obj material copied")
		_check(FileAccess.file_exists(imported_folder.path_join("textures/tex.png")), "obj texture copied")
		var imported_mtl := FileAccess.get_file_as_string(imported_folder.path_join("materials/sample.mtl"))
		_check(imported_mtl.contains("../textures/tex.png"), "obj texture reference rewritten")
		var imported_obj := FileAccess.get_file_as_string(doc.project_dir.path_join(imported_rel))
		_check(imported_obj.contains("mtllib materials/sample.mtl"), "obj material reference rewritten")
		var obj_id: String = doc.add_imported(imported_rel, "Sample", Vector3.ZERO)
		await get_tree().process_frame
		var imported_node: Node3D = doc.nodes.get(obj_id)
		_check(imported_node != null, "obj object spawned")
		var mesh_instance: MeshInstance3D = null
		if imported_node != null:
			for child in imported_node.find_children("*", "MeshInstance3D", true, false):
				mesh_instance = child
				break
		_check(mesh_instance != null and mesh_instance.mesh != null, "obj mesh built")
		if mesh_instance != null and mesh_instance.mesh != null:
			_check(mesh_instance.mesh.get_surface_count() == 1, "obj material group became one surface")
			var surface_material := mesh_instance.mesh.surface_get_material(0) as StandardMaterial3D
			_check(surface_material != null and surface_material.albedo_texture != null, "obj material texture loaded")
			var arrays := mesh_instance.mesh.surface_get_arrays(0)
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			_check(normals.size() >= 3 and normals[0].length() > 0.9, "obj normals generated")
			_check((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == 6, "obj quad triangulated")
		DirAccess.remove_absolute(fixture.path_join("sample.obj"))
		DirAccess.remove_absolute(fixture.path_join("sample.mtl"))
		DirAccess.remove_absolute(fixture.path_join("tex.png"))
		DirAccess.remove_absolute(fixture)

	# Leave and clean up the temporary project.
	var project_id: String = doc.project_id
	editor._leave(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(main._editor == null, "editor closed")
	_check(Store.delete_project(project_id), "temporary project deleted")
	_finish()

func _write_test_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()

func _finish() -> void:
	if _failures.is_empty():
		print("SMOKE RESULT: PASS")
	else:
		printerr("SMOKE RESULT: %d FAILURE(S)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
