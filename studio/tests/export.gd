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
