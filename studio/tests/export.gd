extends Node
## Export workstream suite: GLB scene export, the Render workspace panel and
## the embedded Shading panel.
##
## The GLB checks use the real Document and the real GLTFDocument round-trip;
## no hand-written GLB fixture is used. All files land under `user://`.

const DocumentScript = preload("res://src/core/document.gd")
const GlbExportScript = preload("res://src/core/glb_export.gd")

var _failures: Array[String] = []
var _checks := 0
var _tmp_dir := ""


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("EXPORT OK: " + message)
	else:
		_failures.append(message)
		printerr("EXPORT FAIL: " + message)


func _ready() -> void:
	await get_tree().process_frame
	await _test_static_scene_export()
	await _test_animation_export()
	await _test_selection_only_export()
	await _test_rigged_export()
	await _test_export_failure()
	await _test_render_panel()
	await _test_shading_panel()
	_finish()


func _finish() -> void:
	_cleanup_tmp_dir()
	var status := "PASS" if _failures.is_empty() else "FAIL"
	print("EXPORT RESULT: %s (%d OK, %d FAIL)" % [status, _checks, _failures.size()])
	if not _failures.is_empty():
		for failure in _failures:
			printerr("  - " + failure)
	print("SUITE RESULT: " + status)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _ensure_tmp_dir() -> void:
	if _tmp_dir == "":
		_tmp_dir = ProjectSettings.globalize_path("user://export_tests")
	if not DirAccess.dir_exists_absolute(_tmp_dir):
		DirAccess.make_dir_recursive_absolute(_tmp_dir)


func _cleanup_tmp_dir() -> void:
	if _tmp_dir == "":
		return
	var dir := DirAccess.open(_tmp_dir)
	if dir == null:
		return
	for name in dir.get_files():
		dir.remove(name)
	DirAccess.remove_absolute(_tmp_dir)


func _new_doc(title := "Export Test") -> Node3D:
	var doc = DocumentScript.new()
	add_child(doc)
	doc.new_project(title, "blank")
	# The blank template ships Cube + Main Camera + Key Light + Fill Light.
	# Export assertions count exact objects, so clear the starter scene first
	# and let each test add only the objects it is about.
	for obj in doc.objects.duplicate():
		doc.delete_object(str(obj.get("id", "")))
	return doc


func _glb_json(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 20:
		return {}
	var json_len := bytes.decode_u32(12)
	var json_bytes := bytes.slice(20, 20 + json_len)
	var parsed = JSON.parse_string(json_bytes.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


func _scene_names(node: Node, out: Array[String] = []) -> Array[String]:
	if node.name != "":
		out.append(str(node.name))
	for child in node.get_children():
		_scene_names(child, out)
	return out


func _count_mesh_instances(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and (node as MeshInstance3D).mesh != null else 0
	for child in node.get_children():
		count += _count_mesh_instances(child)
	return count


func _count_cameras(node: Node) -> int:
	var count := 1 if node is Camera3D else 0
	for child in node.get_children():
		count += _count_cameras(child)
	return count


func _count_lights(node: Node) -> int:
	var count := 1 if node is Light3D else 0
	for child in node.get_children():
		count += _count_lights(child)
	return count


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _find_skinned_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).skin != null:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_skinned_mesh(child)
		if found != null:
			return found
	return null


func _rest(p: Vector3, length: float) -> Dictionary:
	return {
		"p": p,
		"r": Quaternion.IDENTITY,
		"s": Vector3.ONE,
		"length": length,
		"influence_scale": 1.0,
	}


func _test_static_scene_export() -> void:
	print("EXPORT STEP: static scene")
	_ensure_tmp_dir()
	var doc := _new_doc("Static Export")
	var cube: String = doc.add_primitive("box", Vector3(0, 0.5, 0))
	var hidden: String = doc.add_primitive("box", Vector3(2, 0.5, 0))
	doc.set_object_visible(hidden, false)
	var camera: String = doc.add_camera(Vector3(4, 3, 5))
	var light: String = doc.add_light("directional", Vector3(0, 5, 0))
	var live_names := _scene_names(doc)
	var exporter = GlbExportScript.new()
	var path := _tmp_dir.path_join("static.glb")
	var result: Dictionary = exporter.export_scene(doc, path)
	_check(bool(result.get("ok", false)), "the static scene exports")
	_check(FileAccess.file_exists(path), "the GLB file exists")
	var bytes := FileAccess.get_file_as_bytes(path)
	_check(bytes.size() >= 12 and bytes.slice(0, 4).get_string_from_utf8() == "glTF",
		"the file starts with glTF")
	_check(bytes.decode_u32(4) == 2, "the GLB version is 2")
	_check(bytes.decode_u32(8) == bytes.size(), "the GLB length matches the file")
	var json := _glb_json(path)
	_check(not json.is_empty(), "the GLB JSON chunk parses")
	var names: Array = []
	for node in json.get("nodes", []):
		names.append(str((node as Dictionary).get("name", "")))
	_check(not names.has("Marker"), "editor markers are stripped")
	_check(not names.has(str(doc.nodes[hidden].name)), "the hidden object is stripped")
	_check(not names.has(""), "every exported node keeps a real name")
	_check(not JSON.stringify(json).contains("KHR_node_visibility"),
		"hidden nodes are removed instead of relying on KHR_node_visibility")
	_check((json.get("meshes", []) as Array).size() == 1, "only the visible cube mesh is exported")
	_check((json.get("cameras", []) as Array).size() == 1, "the camera is a real glTF camera")
	_check((json.get("extensions", {}).get("KHR_lights_punctual", {}).get("lights", []) as Array).size() == 1,
		"the directional light is a real punctual light")

	var state := GLTFState.new()
	var gltf := GLTFDocument.new()
	var err := gltf.append_from_file(path, state)
	_check(err == OK, "the exported GLB re-imports")
	var imported: Node = gltf.generate_scene(state) if err == OK else null
	_check(imported != null and _count_mesh_instances(imported) == 1,
		"the re-imported scene has exactly one mesh")
	if imported != null:
		_check(_count_cameras(imported) == 1, "the re-imported scene has one camera")
		_check(_count_lights(imported) == 1, "the re-imported scene has one light")
		imported.free()
	_check(doc.objects.size() == 4, "export never mutates the live object list")
	_check(doc.nodes[hidden].visible == false, "export never unhides a live node")
	_check(_scene_names(doc) == live_names, "export never renames a live node")
	doc.queue_free()


func _test_animation_export() -> void:
	print("EXPORT STEP: animation")
	var doc := _new_doc("Animation Export")
	var cube: String = doc.add_primitive("box", Vector3(0, 0.5, 0))
	doc.set_selection(cube)
	doc.seek(0.0, true)
	doc.set_object_transform(cube, Vector3(0, 0.5, 0), Quaternion.IDENTITY, Vector3.ONE, false)
	doc.insert_transform_keys()
	doc.seek(1.0, true)
	doc.set_object_transform(cube, Vector3(1, 0.5, 0), Quaternion.IDENTITY, Vector3.ONE, false)
	doc.insert_transform_keys()
	_check(doc.animation.get_track_count() > 0, "the fixture animates the cube")

	var exporter = GlbExportScript.new()
	var path := _tmp_dir.path_join("animation.glb")
	var result: Dictionary = exporter.export_scene(doc, path, {"animations": true})
	_check(bool(result.get("ok", false)), "the animated scene exports")
	_check(int(result.get("animations", 0)) == 1, "the export reports the active clip")
	var json := _glb_json(path)
	_check(not (json.get("animations", []) as Array).is_empty(), "the GLB carries a real animation")

	var state := GLTFState.new()
	var gltf := GLTFDocument.new()
	var err := gltf.append_from_file(path, state)
	_check(err == OK, "the animated GLB re-imports")
	var imported: Node = gltf.generate_scene(state) if err == OK else null
	var player := _find_animation_player(imported) if imported != null else null
	_check(player != null and not player.get_animation_list().is_empty(),
		"the re-imported scene has an AnimationPlayer")
	var endpoint: Variant = null
	if player != null and not player.get_animation_list().is_empty():
		var anim: Animation = player.get_animation(player.get_animation_list()[0])
		for ti in range(anim.get_track_count()):
			if anim.track_get_type(ti) != Animation.TYPE_POSITION_3D:
				continue
			var keys := anim.track_get_key_count(ti)
			if keys > 0:
				endpoint = anim.track_get_key_value(ti, keys - 1)
	_check(endpoint is Vector3 and (endpoint as Vector3).distance_to(Vector3(1, 0.5, 0)) < 0.01,
		"the position track keeps its endpoint")
	if imported != null:
		imported.free()
	doc.queue_free()


func _test_selection_only_export() -> void:
	print("EXPORT STEP: selection only")
	var doc := _new_doc("Selection Export")
	var first: String = doc.add_primitive("box", Vector3(-1, 0.5, 0))
	var second: String = doc.add_primitive("box", Vector3(1, 0.5, 0))
	doc.set_selection(first)
	var exporter = GlbExportScript.new()
	var path := _tmp_dir.path_join("selection.glb")
	var result: Dictionary = exporter.export_scene(
		doc, path, {"selection_only": true, "animations": true})
	_check(bool(result.get("ok", false)), "the selection-only scene exports")
	_check(int(result.get("animations", -1)) == 0,
		"a selected object with no tracks exports no animation")
	var json := _glb_json(path)
	_check((json.get("meshes", []) as Array).size() == 1,
		"selection-only exports only the selected mesh")
	_check((json.get("animations", []) as Array).is_empty(),
		"the empty animation scope writes no animation channel")
	_check(not JSON.stringify(json).contains("AnimationPlayer"),
		"no empty AnimationPlayer is fabricated")

	# One track on each cube. The selected export must keep only the selected
	# object's track, not the whole document clip.
	doc.seek(0.0, true)
	doc.set_selection(first)
	doc.set_object_transform(first, Vector3(-1, 1, 0), Quaternion.IDENTITY, Vector3.ONE, false)
	doc.insert_channel_key("position")
	doc.set_selection(second)
	doc.set_object_transform(second, Vector3(1, 2, 0), Quaternion.IDENTITY, Vector3.ONE, false)
	doc.insert_channel_key("position")
	doc.set_selection(first)
	var selected_path := _tmp_dir.path_join("selection_animated.glb")
	var selected: Dictionary = exporter.export_scene(
		doc, selected_path, {"selection_only": true, "animations": true})
	_check(bool(selected.get("ok", false)), "the selected animated object exports")
	_check(int(selected.get("animations", 0)) == 1, "selection-only keeps one retained track")
	var selected_json := _glb_json(selected_path)
	var animations: Array = selected_json.get("animations", [])
	var channel_count := 0
	if not animations.is_empty():
		channel_count = ((animations[0] as Dictionary).get("channels", []) as Array).size()
	_check(channel_count == 1, "only the selected object's track survives")

	var whole_path := _tmp_dir.path_join("whole_scene.glb")
	var whole: Dictionary = exporter.export_scene(doc, whole_path, {"animations": false})
	_check(bool(whole.get("ok", false)), "the whole scene exports")
	var whole_json := _glb_json(whole_path)
	_check((whole_json.get("meshes", []) as Array).size() == 2,
		"the whole scene includes both meshes")
	doc.queue_free()


func _test_rigged_export() -> void:
	print("EXPORT STEP: rigged mesh")
	var doc := _new_doc("Rigged Export")
	doc.project_dir = _tmp_dir
	var rs = doc.rig_system
	var rig_id: String = rs.create_rig("Rig", Vector3.ZERO)
	rs.set_bone_rest(rig_id, "Root", _rest(Vector3.ZERO, 1.0))
	rs.add_bone(rig_id, "Spine", "Root", _rest(Vector3(0, 1, 0), 1.0))
	var mesh_id: String = doc.add_primitive("box", Vector3(0, 0.5, 0))
	var job: String = rs.start_bind(rig_id, mesh_id, {})
	var state := {"state": "running", "progress": 0.0}
	var polls := 0
	while polls < 120 and str(state.get("state", "")) == "running":
		state = rs.poll_bind(job)
		polls += 1
	_check(str(state.get("state", "")) == "done", "the rig fixture binds a real mesh")

	var exporter = GlbExportScript.new()
	var path := _tmp_dir.path_join("rigged.glb")
	var result: Dictionary = exporter.export_scene(doc, path, {"animations": false})
	_check(bool(result.get("ok", false)), "the rigged scene exports")
	var json := _glb_json(path)
	var skins: Array = json.get("skins", [])
	_check(not skins.is_empty(), "the rigged scene exports a real skin")
	if not skins.is_empty():
		var import_state := GLTFState.new()
		var gltf := GLTFDocument.new()
		var err := gltf.append_from_file(path, import_state)
		var imported: Node = gltf.generate_scene(import_state) if err == OK else null
		var skinned := _find_skinned_mesh(imported) if imported != null else null
		_check(skinned != null, "the re-imported rigged mesh keeps its skin")
		if imported != null:
			imported.free()
	doc.queue_free()


func _test_export_failure() -> void:
	print("EXPORT STEP: failure")
	var doc := _new_doc("Failure Export")
	var cube: String = doc.add_primitive("box", Vector3.ZERO)
	var exporter = GlbExportScript.new()
	var path := "/proc/kinema/forbidden.glb"
	var result: Dictionary = exporter.export_scene(doc, path)
	_check(not bool(result.get("ok", true)), "an unwritable destination fails")
	_check(str(result.get("error", "")) != "", "the failure states a real reason")
	_check(not FileAccess.file_exists(path), "the failure writes no destination file")
	_check(not FileAccess.file_exists(path + ".tmp.glb"),
		"the failure leaves no temporary sibling")
	doc.queue_free()


func _test_render_panel() -> void:
	print("EXPORT STEP: render panel")
	var doc := _new_doc("Render Panel")
	var cube: String = doc.add_primitive("box", Vector3.ZERO)
	var camera: String = doc.add_camera(Vector3(4, 3, 5))
	var panel = preload("res://src/ui/render_panel.gd").new()
	add_child(panel)
	panel.setup(doc, null)
	await get_tree().process_frame
	_check(panel.active_tab() == "render", "Render is the default tab")
	_check(panel.media_sheet() != null, "the existing media export sheet is embedded")
	_check(panel.media_sheet().get_parent() != null, "the media sheet is mounted, not modal")
	_check(panel.media_sheet().format_ids().has("mp4"),
		"MP4 stays in the format list")
	if not panel.media_sheet().mp4_available():
		_check(panel.media_sheet().mp4_reason() != "",
			"MP4 keeps its exact reason when the backend is unavailable")
	panel.set_active_tab("3d")
	_check(panel.active_tab() == "3d", "the 3D export tab can be selected")
	_check(panel.export_button().custom_minimum_size == Vector2(96, 44),
		"Export GLB is a 96x44 target")
	_check(panel.scope_text().contains("Whole scene"), "the scope is stated")
	doc.set_selection("")
	panel.refresh()
	_check(panel.selection_toggle().disabled, "selection-only disables without one selected object")
	_check(panel.selection_toggle().tooltip_text == "Select one object to export.",
		"selection-only states the exact reason")
	var requests: Array[Dictionary] = []
	panel.export_requested.connect(func(options: Dictionary) -> void: requests.append(options))
	panel.export_button().pressed.emit()
	_check(requests.size() == 1 and bool(requests[0].get("animations", false)),
		"Export GLB requests the real options")
	panel.queue_free()
	doc.queue_free()


func _test_shading_panel() -> void:
	print("EXPORT STEP: shading panel")
	var doc := _new_doc("Shading Panel")
	var cube: String = doc.add_primitive("box", Vector3.ZERO)
	doc.set_selection(cube)
	var panel = preload("res://src/ui/shading_panel.gd").new()
	add_child(panel)
	panel.setup(doc)
	panel.set_target(cube)
	await get_tree().process_frame
	_check(panel.material_sheet() != null, "the material library is embedded")
	_check(panel.material_editor() != null, "the material editor is embedded")
	_check(panel.material_sheet().get_parent() != null, "the library is mounted, not modal")
	_check(panel.material_editor().get_parent() != null, "the editor is mounted, not modal")
	_check(panel.material_editor().visible == false or panel.material_editor().material_id() == "",
		"with no material selected the editor shows the empty state")

	var material: String = panel.new_material()
	_check(material != "", "New creates a real material")
	_check(doc.material_system.has_material(material), "the material exists in MaterialSystem")
	_check(panel.material_sheet().row_count() >= 1, "the library gained a row")
	_check(panel.material_editor().material_id() == material,
		"New loads the created material in the editor")

	var undo_before: int = (doc._undo_stack as Array).size()
	panel.select_material(material)
	_check(panel.assign_selected(), "Assign succeeds for the selected object")
	_check((doc._undo_stack as Array).size() == undo_before + 1,
		"Assign is one undo entry")
	_check(doc.material_system.resolve_assignment(cube) == material,
		"Assign writes the real target assignment")
	doc.undo()
	_check(doc.material_system.resolve_assignment(cube) != material,
		"undo removes the assignment")

	doc.set_selection("")
	panel.set_target("")
	panel.refresh()
	_check(panel.assign_button().disabled, "Assign disables without an object")
	_check(panel.assign_button().tooltip_text == "Select an object to assign this material.",
		"Assign states the exact reason")

	# The inspector only builds its Edit action for a selected object that
	# really has a material; restore both before creating it.
	doc.set_selection(cube)
	panel.set_target(cube)
	panel.select_material(material)
	_check(panel.assign_selected(), "the cube is assigned again for the inspector handoff")

	# The inspector hands off to Shading instead of opening a modal.
	var inspector = preload("res://src/ui/inspector.gd").new()
	add_child(inspector)
	inspector.setup(doc)
	_check(inspector.edit_material_button().custom_minimum_size.y >= 43.5,
		"Edit in Shading is a 44 dp action")
	_check(inspector.edit_material_button().text == "Edit in Shading",
		"the inspector names the action Edit in Shading")
	var targets: Array[Dictionary] = []
	inspector.edit_material_requested.connect(func(target: Dictionary) -> void: targets.append(target))
	inspector.edit_material_button().pressed.emit()
	_check(targets.size() == 1, "the inspector emits the real target")
	panel.queue_free()
	inspector.queue_free()
	doc.queue_free()
