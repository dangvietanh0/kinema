extends Control
## Rigging workstream suite: model, skinning, IK, poses, bone keys and UI.
##
## The suite tests maths and arrays, never GPU deformation. Bind progress is
## polled for real; no test fabricates a progress value.

const DocumentScript = preload("res://src/core/document.gd")
const RigSystemScript = preload("res://src/core/rig_system.gd")
const SkinningScript = preload("res://src/core/skinning.gd")
const IkSolverScript = preload("res://src/core/ik_solver.gd")
const PoseLibraryScript = preload("res://src/core/pose_library.gd")
const RigPanelScript = preload("res://src/ui/rig_panel.gd")
const BoneTreeScript = preload("res://src/ui/bone_tree.gd")
const PosePanelScript = preload("res://src/ui/pose_panel.gd")
const IkPanelScript = preload("res://src/ui/ik_panel.gd")
const RigOverlayScript = preload("res://src/ui/rig_overlay.gd")
const EditorAppScript = preload("res://src/app/editor.gd")

const CAPTURE_DIR := "/tmp/opencode/wave2-rig-captures"

var _failures: Array[String] = []
var _tmp_dir := ""
var _checks := 0


class FakeView:
	extends Control
	var scale_px := 100.0
	var origin := Vector2(220, 260)

	func world_to_screen(world: Vector3) -> Vector2:
		return origin + Vector2(world.x * scale_px, -world.y * scale_px)

	func screen_ray(screen: Vector2) -> Dictionary:
		# A ray perpendicular to the z=0 editing plane. World x/y follow the
		# orthographic projection above, so a screen drag maps to the same
		# world delta the real camera would produce on that plane.
		return {
			"origin": Vector3((screen.x - origin.x) / scale_px, -(screen.y - origin.y) / scale_px, 0.0),
			"direction": Vector3.FORWARD,
		}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("RIG FAIL: " + message)
	else:
		print("RIG OK: " + message)


func _close(a: float, b: float, epsilon: float = 0.0001) -> bool:
	return absf(a - b) <= epsilon


func _ready() -> void:
	_tmp_dir = ProjectSettings.globalize_path("user://rig_tests")
	_rmrf(_tmp_dir)
	DirAccess.make_dir_recursive_absolute(_tmp_dir)
	if _capture_requested():
		get_window().size = Vector2i(915, 412)
	await get_tree().process_frame
	await _test_model()
	await _test_skinning()
	await _test_undo()
	await _test_ik()
	await _test_pose_and_bone_keys()
	await _test_pose_v2()
	await _test_pose_transactions()
	await _test_one_gesture_and_edit_parity()
	await _test_gizmo()
	await _test_touch_pose_editing()
	await _test_imported_adoption()
	await _test_gltf_external_buffers()
	await _test_fbx_and_adoption()
	await _test_ui()
	await _test_overlay()
	await _test_overlay_hit_transform()
	await _test_octahedral_bones()
	await _test_rig_toolbar()
	await _test_viewport_modes()
	await _test_extrude()
	if _capture_requested():
		await _capture_visuals()
	_finish()


func _finish() -> void:
	_rmrf(_tmp_dir)
	if _failures.is_empty():
		print("RIG RESULT: PASS (%d checks)" % _checks)
	else:
		printerr("RIG RESULT: %d FAILURE(S) of %d checks" % [_failures.size(), _checks])
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


func _new_doc(title: String = "Rig Test") -> Node3D:
	var doc = DocumentScript.new()
	add_child(doc)
	doc.new_project(title, "blank")
	doc.project_dir = _tmp_dir
	return doc


func _rest(p: Vector3 = Vector3.ZERO, length: float = 0.4, scale: float = 1.0) -> Dictionary:
	return {
		"p": p,
		"r": Quaternion.IDENTITY,
		"s": Vector3.ONE,
		"length": length,
		"influence_scale": scale,
	}


func _make_chain_rig(doc: Node3D) -> String:
	var rs = doc.rig_system
	var rig_id: String = rs.create_rig("Rig", Vector3.ZERO)
	rs.set_bone_rest(rig_id, "Root", _rest(Vector3.ZERO, 1.0))
	rs.add_bone(rig_id, "Spine", "Root", _rest(Vector3(0, 1, 0), 1.0))
	return rig_id


func _skeleton(doc: Node3D, rig_id: String) -> Skeleton3D:
	var node: Node3D = doc.nodes.get(rig_id)
	if node == null:
		return null
	return node.get_node_or_null("Skeleton3D") as Skeleton3D


func _bone_index(rig: Dictionary, name: String) -> int:
	var bones: Array = rig.get("bones", [])
	for i in range(bones.size()):
		if str(bones[i].get("name", "")) == name:
			return i
	return -1


func _bone_global_rest(rig: Dictionary, index: int) -> Transform3D:
	var bone: Dictionary = rig["bones"][index]
	var p: Vector3 = bone.get("p", Vector3.ZERO)
	var r: Quaternion = bone.get("r", Quaternion.IDENTITY)
	var s: Vector3 = bone.get("s", Vector3.ONE)
	var local := Transform3D(Basis(r).scaled(s), p)
	var parent := int(bone.get("parent", -1))
	if parent < 0:
		return local
	return _bone_global_rest(rig, parent) * local


func _end_effector_world(doc: Node3D, rig_id: String, end_bone: String) -> Vector3:
	var rig: Dictionary = doc.rig_system.get_rig(rig_id)
	var idx := _bone_index(rig, end_bone)
	var skel := _skeleton(doc, rig_id)
	if idx < 0 or skel == null:
		return Vector3.ZERO
	var pose := skel.get_bone_global_pose(idx)
	var length := float(rig["bones"][idx].get("length", 0.4))
	var local_tail := pose.origin + pose.basis.y.normalized() * length
	return skel.to_global(local_tail)


# -------------------------------------------------------------------------
# C1 — rig model and skeleton
# -------------------------------------------------------------------------

func _test_model() -> void:
	print("RIG STEP: model")
	var doc := _new_doc()
	var rs = doc.rig_system
	var rig_id: String = rs.create_rig("Rig", Vector3(1, 0, 0))
	_check(rig_id != "", "create_rig returns an object id")
	_check(rs.rig_ids().has(rig_id), "rig_ids lists the new rig")
	_check(rs.active_rig_id() == rig_id, "the new rig becomes active")
	var obj: Dictionary = doc.get_object(rig_id)
	_check(str(obj.get("kind", "")) == "rig", "rig object uses kind rig")
	var node: Node3D = doc.nodes.get(rig_id)
	_check(node != null, "rig object has a runtime node")
	_check(node != null and node.get_node_or_null("Skeleton3D") is Skeleton3D, "rig node owns a Skeleton3D named Skeleton3D")
	_check(node != null and node.get_node_or_null("Mesh") == null, "rig object does not keep the fallback mesh visual")
	var rig: Dictionary = rs.get_rig(rig_id)
	_check(not rig.is_empty(), "get_rig returns the record")
	var bones: Array = rig.get("bones", [])
	_check(bones.size() == 1, "a new rig has one bone")
	_check(bones.size() == 1 and str(bones[0].get("name", "")) == "Root", "the default bone is Root")
	_check(bones.size() == 1 and _close(float(bones[0].get("length", 0.0)), 0.4), "Root length is 0.4")
	_check(bones.size() == 1 and (bones[0].get("p", Vector3.ZERO) as Vector3).length() < 0.0001, "Root rest is identity")
	var skel := _skeleton(doc, rig_id)
	_check(skel != null and skel.get_bone_count() == 1, "Skeleton3D has the Root bone")

	var spine: int = rs.add_bone(rig_id, "Spine", "Root", _rest(Vector3(0, 0.4, 0), 0.5))
	_check(spine == 1, "add_bone returns the child index")
	rig = rs.get_rig(rig_id)
	_check(rig["bones"].size() == 2, "add_bone appends the bone")
	_check(int(rig["bones"][1].get("parent", -1)) == 0, "the child records its parent index")
	skel = _skeleton(doc, rig_id)
	_check(skel.get_bone_count() == 2 and skel.get_bone_parent(1) == 0, "Skeleton3D rebuilds the parent/child chain")
	_check(rs.add_bone(rig_id, "Spine", "Root", _rest()) == -1, "duplicate bone names are rejected")
	_check(rs.add_bone(rig_id, "Ghost", "Missing", _rest()) == -1, "a missing parent is rejected")

	# Cycle prevention.
	_check(not rs.set_bone_parent(rig_id, "Root", "Spine"), "reparenting a bone under its child is rejected")
	_check(not rs.set_bone_parent(rig_id, "Root", "Root"), "reparenting a bone under itself is rejected")

	# Reparent keeps the global rest pose.
	var tip: int = rs.add_bone(rig_id, "Tip", "Spine", _rest(Vector3(0, 0.5, 0), 0.4))
	rig = rs.get_rig(rig_id)
	var before := _bone_global_rest(rig, tip).origin
	_check(rs.set_bone_parent(rig_id, "Tip", "Root"), "reparenting Tip to Root succeeds")
	rig = rs.get_rig(rig_id)
	var tip_index := _bone_index(rig, "Tip")
	var after := _bone_global_rest(rig, tip_index).origin
	_check(before.distance_to(after) < 0.0001, "reparent keeps the global rest position")
	skel = _skeleton(doc, rig_id)
	_check(skel.get_bone_parent(tip_index) == 0, "Skeleton3D rebuilds after reparent")
	_check(_bone_index(rig, "Spine") < _bone_index(rig, "Tip"), "bones stay parent-first after reparent")

	# Rename cascades to tracks, IK, poses and the skeleton.
	doc.current_time = 1.0
	doc.insert_bone_key(rig_id, "Spine", Quaternion(Vector3.RIGHT, 0.3))
	var chain: String = rs.add_ik_chain(rig_id, "Root", "Spine", "")
	_check(chain != "", "an IK chain can reference a bone by name")
	var pose_id: String = rs.save_pose(rig_id, "Before rename")
	_check(pose_id != "", "save_pose returns a pose id")
	if rs.has_method("rename_bone"):
		_check(rs.rename_bone(rig_id, "Spine", "Chest"), "rename_bone succeeds")
	else:
		_check(false, "rename_bone exists")
	rig = rs.get_rig(rig_id)
	_check(_bone_index(rig, "Chest") >= 0 and _bone_index(rig, "Spine") < 0, "the bone is renamed in the rig record")
	_check(_skeleton(doc, rig_id).find_bone("Chest") >= 0, "the Skeleton3D uses the new bone name")
	_check(doc.get_bone_keys(rig_id, "Chest").size() == 1, "bone tracks are remapped on rename")
	_check(doc.get_bone_keys(rig_id, "Spine").size() == 0, "the old bone track is gone")
	var chains: Array = rig.get("ik", [])
	_check(chains.size() == 1 and str(chains[0].get("end", "")) == "Chest", "IK chains follow the rename")
	var poses: Array = rig.get("poses", [])
	_check(poses.size() == 1 and poses[0].get("bones", {}).has("Chest"), "pose keys follow the rename")

	# Delete guards.
	_check(not rs.remove_bone(rig_id, "Root"), "a bone with children cannot be deleted")
	_check(not rs.remove_bone(rig_id, "Chest"), "a bone referenced by IK or a pose cannot be deleted")
	var leaf: int = rs.add_bone(rig_id, "Leaf", "Root", _rest(Vector3(0, 0.2, 0), 0.2))
	_check(leaf >= 0 and rs.remove_bone(rig_id, "Leaf"), "an unreferenced leaf bone can be deleted")

	# Rest edit rebuilds the skeleton and preserves the current pose.
	skel = _skeleton(doc, rig_id)
	skel.set_bone_pose_rotation(0, Quaternion(Vector3.UP, 0.5))
	rs.set_bone_rest(rig_id, "Root", _rest(Vector3(0.1, 0, 0), 0.6))
	var rebuilt := _skeleton(doc, rig_id)
	_check(rebuilt != null and rebuilt != skel, "set_bone_rest rebuilds the Skeleton3D")
	_check(rebuilt.get_bone_pose_rotation(0).angle_to(Quaternion(Vector3.UP, 0.5)) < 0.001, "rest rebuild preserves the existing pose")
	_check(_close(rebuilt.get_bone_rest(0).origin.x, 0.1), "rest rebuild applies the new rest")

	# Roundtrip.
	var data: Dictionary = doc.to_data()
	_check(data.get("rigs", []).size() == 1, "to_data writes one rig")
	var raw_rest: Dictionary = data["rigs"][0]["bones"][0]["rest"]
	_check(raw_rest.get("p", null) is Array, "rig rest is JSON-safe in to_data")
	var doc2 := _new_doc("Rig Roundtrip")
	_check(doc2.load_project(data, _tmp_dir), "load_project accepts the rig snapshot")
	var rig2: Dictionary = doc2.rig_system.get_rig(rig_id)
	_check(not rig2.is_empty(), "rig survives save/load")
	_check(rig2.get("bones", []).size() == 3, "bones survive save/load")
	_check(_skeleton(doc2, rig_id) != null and _skeleton(doc2, rig_id).get_bone_count() == 3, "the loaded rig rebuilds its Skeleton3D")
	_check(rig2.get("poses", []).size() == 1, "poses survive save/load")
	_check(str(rig2.get("active_bone", "")) != "", "active bone survives save/load")
	doc.queue_free()
	doc2.queue_free()


# -------------------------------------------------------------------------
# C2 — skinning and bind job
# -------------------------------------------------------------------------

func _test_skinning() -> void:
	print("RIG STEP: skinning")
	var doc := _new_doc("Skin Test")
	var rs = doc.rig_system
	var rig_id := _make_chain_rig(doc)
	var mesh_id: String = doc.add_primitive("box", Vector3(0, 0.5, 0))
	var mesh_node: Node3D = doc.nodes[mesh_id]
	var rig_node: Node3D = doc.nodes[rig_id]
	var mesh_instance := mesh_node.get_node("Mesh") as MeshInstance3D
	var original_vertices := _surface_vertex_count(mesh_instance.mesh)
	var original_position := mesh_node.position
	var original_transform := mesh_node.transform

	# Static weight maths: 1k vertices, two bones.
	var verts := PackedVector3Array()
	for i in range(1000):
		var t := float(i) / 999.0
		verts.append(Vector3(0.18 * sin(float(i)), t * 2.0, 0.18 * cos(float(i))))
	var segments := [
		{"name": "Root", "head": Vector3(0, 0, 0), "tail": Vector3(0, 1, 0), "influence_scale": 1.0},
		{"name": "Spine", "head": Vector3(0, 1, 0), "tail": Vector3(0, 2, 0), "influence_scale": 1.0},
	]
	var weights: Dictionary = SkinningScript.compute_weights(verts, segments, 4)
	_check(weights.get("bones", PackedInt32Array()).size() == 4000, "auto weights emit 4 influences per vertex")
	_check(weights.get("weights", PackedFloat32Array()).size() == 4000, "auto weights emit 4 floats per vertex")
	var sums_ok := true
	var max_influences := 0
	var bones: PackedInt32Array = weights["bones"]
	var values: PackedFloat32Array = weights["weights"]
	for v in range(1000):
		var total := 0.0
		var used := 0
		for k in range(4):
			var w := values[v * 4 + k]
			total += w
			if w > 0.000001:
				used += 1
		max_influences = maxi(max_influences, used)
		if absf(total - 1.0) > 0.0001:
			sums_ok = false
	_check(sums_ok, "every vertex weight sums to 1")
	_check(max_influences <= 4, "a vertex has at most 4 influences")
	var low_vertex := 0
	_check(bones[low_vertex * 4] == 0, "the nearest bone dominates a vertex near the root")
	_check(values[low_vertex * 4] > 0.5, "the dominant weight is greater than half")
	var high_vertex := 999
	_check(bones[high_vertex * 4] == 1, "the nearest bone dominates a vertex near the spine")
	var scaled: Dictionary = SkinningScript.compute_weights(
		PackedVector3Array([Vector3(0.5, 0.1, 0)]),
		[
			{"name": "Root", "head": Vector3(0, 0, 0), "tail": Vector3(0, 1, 0), "influence_scale": 1.0},
			{"name": "Spine", "head": Vector3(0, 1, 0), "tail": Vector3(0, 2, 0), "influence_scale": 100.0},
		],
		4)
	var scaled_bones: PackedInt32Array = scaled["bones"]
	_check(scaled_bones[0] == 1, "influence_scale can make a farther bone dominate")

	# Real bind job.
	var job: String = rs.start_bind(rig_id, mesh_id, {})
	_check(job != "", "start_bind returns a job id")
	var state := {"state": "running", "progress": 0.0}
	var polls := 0
	while polls < 120 and str(state.get("state", "")) == "running":
		state = rs.poll_bind(job)
		polls += 1
	_check(str(state.get("state", "")) == "done", "the bind job completes")
	_check(_close(float(state.get("progress", 0.0)), 1.0), "the bind job reports real progress 1.0")
	var result: Dictionary = state.get("result", {})
	var vertex_count := int(result.get("vertex_count", 0))
	_check(vertex_count == original_vertices, "the bind job reports the true vertex count")
	_check(int(result.get("influences", 0)) == 4, "the bind job reports 4 influences")

	_check(mesh_node.get_parent() == doc and rig_node.get_parent() == doc, "bind does not reparent the mesh")
	_check(mesh_node.global_transform.is_equal_approx(rig_node.global_transform), "bind locks the mesh global transform to the rig")
	mesh_instance = mesh_node.get_node("Mesh") as MeshInstance3D
	_check(mesh_instance.skin != null, "bind assigns a Skin")
	# Godot Skin binds are per bone, not per vertex. `create_skin_from_rest_transforms()`
	# creates one bind per skeleton bone; vertex coverage is proven by ARRAY_BONES.
	_check(mesh_instance.skin.get_bind_count() == 2, "Skin bind count equals the skeleton bone count")
	var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
	_check(arrays[Mesh.ARRAY_BONES] != null and arrays[Mesh.ARRAY_BONES].size() == vertex_count * 4, "bound ArrayMesh has ARRAY_BONES")
	_check(arrays[Mesh.ARRAY_WEIGHTS] != null and arrays[Mesh.ARRAY_WEIGHTS].size() == vertex_count * 4, "bound ArrayMesh has ARRAY_WEIGHTS")
	var bound_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var bound_ok := true
	for v in range(vertex_count):
		var total := 0.0
		for k in range(4):
			total += bound_weights[v * 4 + k]
		if absf(total - 1.0) > 0.001:
			bound_ok = false
	_check(bound_ok, "bound mesh weights sum to 1")
	var rig: Dictionary = rs.get_rig(rig_id)
	var skins: Array = rig.get("skins", [])
	_check(skins.size() == 1, "the rig records one skin")
	var skin: Dictionary = skins[0]
	_check(str(skin.get("mesh_object_id", "")) == mesh_id, "the skin records the mesh object id")
	_check(int(skin.get("vertex_count", 0)) == vertex_count, "the skin metadata records the vertex count")
	_check(int(skin.get("influences", 0)) == 4, "the skin metadata records 4 influences")
	_check(skin.get("bone_names", []) == ["Root", "Spine"], "the skin metadata records bone names")
	_check(str(skin.get("file", "")).begins_with("skins/"), "the sidecar path is relative to the project")
	var sidecar := _tmp_dir.path_join(str(skin.get("file", "")))
	_check(FileAccess.file_exists(sidecar), "the binary sidecar exists")
	if FileAccess.file_exists(sidecar):
		var file := FileAccess.open(sidecar, FileAccess.READ)
		_check(file != null and file.get_buffer(4).get_string_from_ascii() == "KNSK", "the sidecar has the KNSK header")
		_check(file != null and file.get_32() > 0, "the sidecar stores a version")
		if file != null:
			file.close()

	# Unbind restores the source mesh and the saved transform. A rebind after a
	# weight change must keep the original source transform and the old sidecar.
	var first_file := str(skin.get("file", ""))
	rs.set_bone_influence_scale(rig_id, "Spine", 100.0)
	rig_node.position = Vector3(2, 0, 0)
	rs.advance(0.0)
	var rebind_job: String = rs.start_bind(rig_id, mesh_id, {})
	var rebind_state := {"state": "running", "progress": 0.0}
	var rebind_polls := 0
	while rebind_polls < 120 and str(rebind_state.get("state", "")) == "running":
		rebind_state = rs.poll_bind(rebind_job)
		rebind_polls += 1
	_check(str(rebind_state.get("state", "")) == "done", "the rebind job completes")
	var rebind_skin: Dictionary = rs.get_rig(rig_id).get("skins", [])[0]
	var second_file := str(rebind_skin.get("file", ""))
	_check(second_file != first_file, "rebind writes a new sidecar generation")
	_check(FileAccess.file_exists(sidecar), "rebind keeps the old sidecar")
	_check(FileAccess.file_exists(_tmp_dir.path_join(second_file)), "rebind writes the new sidecar")

	# Unbind restores the source mesh and the saved transform.
	var original_arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
	_check(rs.unbind_mesh(rig_id, mesh_id), "unbind_mesh succeeds")
	mesh_instance = mesh_node.get_node("Mesh") as MeshInstance3D
	_check(mesh_instance.skin == null, "unbind clears the Skin")
	var restored: Array = mesh_instance.mesh.surface_get_arrays(0)
	_check(restored[Mesh.ARRAY_BONES] == null or restored[Mesh.ARRAY_BONES].size() == 0, "unbind restores a static mesh")
	_check(_surface_vertex_count(mesh_instance.mesh) == original_vertices, "unbind restores the original vertex count")
	_check(mesh_node.transform.is_equal_approx(original_transform), "unbind restores the saved mesh transform")
	_check(rs.get_rig(rig_id).get("skins", []).is_empty(), "unbind removes the skin record")
	_check(FileAccess.file_exists(sidecar), "unbind keeps the old sidecar for undo")

	# 50k limit.
	var big := ArrayMesh.new()
	var big_vertices := PackedVector3Array()
	big_vertices.resize(50001)
	for i in range(50001):
		big_vertices[i] = Vector3(float(i % 200) * 0.01, float(i / 200) * 0.01, 0)
	var big_arrays := []
	big_arrays.resize(Mesh.ARRAY_MAX)
	big_arrays[Mesh.ARRAY_VERTEX] = big_vertices
	big.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, big_arrays)
	mesh_instance.mesh = big
	var limit_job: String = rs.start_bind(rig_id, mesh_id, {})
	var limit_state: Dictionary = rs.poll_bind(limit_job)
	_check(str(limit_state.get("state", "")) == "error", "the bind job rejects a mesh over 50,000 vertices")
	_check(str(limit_state.get("error", "")).contains("50,000"), "the 50k error names the limit")
	doc.queue_free()


func _test_undo() -> void:
	print("RIG STEP: undo")
	var doc := _new_doc("Undo Test")
	var rs = doc.rig_system
	var rig_id := _make_chain_rig(doc)
	var mesh_id: String = doc.add_primitive("box", Vector3(0, 0.5, 0))
	var job: String = rs.start_bind(rig_id, mesh_id, {})
	var state := {"state": "running", "progress": 0.0}
	var polls := 0
	while polls < 120 and str(state.get("state", "")) == "running":
		state = rs.poll_bind(job)
		polls += 1
	_check(str(state.get("state", "")) == "done", "undo test bind completes")
	_check(doc.undo_label() == "Bind mesh", "bind finalization is one undo step")
	doc.undo()
	_check(rs.get_rig(rig_id).get("skins", []).is_empty(), "undo removes the skin record")
	var node: Node3D = doc.nodes.get(mesh_id)
	_check(node != null, "undo keeps the mesh object")
	if node != null:
		var mesh_instance := node.get_node_or_null("Mesh") as MeshInstance3D
		_check(mesh_instance != null and mesh_instance.skin == null, "undo restores the static mesh")
	doc.redo()
	_check(rs.get_rig(rig_id).get("skins", []).size() == 1, "redo restores the skin record")
	node = doc.nodes.get(mesh_id)
	if node != null:
		var rebound := node.get_node_or_null("Mesh") as MeshInstance3D
		_check(rebound != null and rebound.skin != null, "redo re-applies the skin")

	# Bone structure.
	var bones_before: int = (rs.get_rig(rig_id).get("bones", []) as Array).size()
	_check(rs.add_bone(rig_id, "Hand", "Spine", _rest(Vector3(0, 0.5, 0), 0.3)) >= 0, "undo test adds a bone")
	_check(doc.undo_label() == "Add bone", "add_bone is one undo step")
	doc.undo()
	_check((rs.get_rig(rig_id).get("bones", []) as Array).size() == bones_before, "undo removes the added bone")
	doc.redo()
	_check((rs.get_rig(rig_id).get("bones", []) as Array).size() == bones_before + 1, "redo restores the added bone")

	rs.set_bone_rest(rig_id, "Root", _rest(Vector3(0.2, 0, 0), 0.9))
	_check(doc.undo_label() == "Edit bone rest", "set_bone_rest is one undo step")
	doc.undo()
	var root_bone: Dictionary = rs.get_rig(rig_id)["bones"][0]
	_check(_close((root_bone.get("p", Vector3.ZERO) as Vector3).x, 0.0), "undo restores the root rest")
	doc.redo()
	root_bone = rs.get_rig(rig_id)["bones"][0]
	_check(_close((root_bone.get("p", Vector3.ZERO) as Vector3).x, 0.2), "redo restores the edited root rest")

	_check(rs.set_bone_parent(rig_id, "Hand", "Root"), "undo test reparents Hand")
	_check(doc.undo_label() == "Reparent bone", "set_bone_parent is one undo step")
	doc.undo()
	var hand_index := _bone_index(rs.get_rig(rig_id), "Hand")
	_check(int(rs.get_rig(rig_id)["bones"][hand_index].get("parent", -1)) == _bone_index(rs.get_rig(rig_id), "Spine"), "undo restores the bone parent")
	doc.redo()
	hand_index = _bone_index(rs.get_rig(rig_id), "Hand")
	_check(int(rs.get_rig(rig_id)["bones"][hand_index].get("parent", -1)) == _bone_index(rs.get_rig(rig_id), "Root"), "redo restores the reparent")

	_check(rs.rename_bone(rig_id, "Hand", "Fist"), "undo test renames Hand")
	_check(doc.undo_label() == "Rename bone", "rename_bone is one undo step")
	doc.undo()
	_check(_bone_index(rs.get_rig(rig_id), "Hand") >= 0, "undo restores the old bone name")
	doc.redo()
	_check(_bone_index(rs.get_rig(rig_id), "Fist") >= 0, "redo restores the new bone name")

	rs.set_bone_influence_scale(rig_id, "Fist", 2.5)
	_check(doc.undo_label() == "Change bone influence", "influence scale is one undo step")
	doc.undo()
	var fist_bone: Dictionary = rs.get_rig(rig_id)["bones"][_bone_index(rs.get_rig(rig_id), "Fist")]
	_check(_close(float(fist_bone.get("influence_scale", 0.0)), 1.0), "undo restores influence scale")
	doc.redo()
	fist_bone = rs.get_rig(rig_id)["bones"][_bone_index(rs.get_rig(rig_id), "Fist")]
	_check(_close(float(fist_bone.get("influence_scale", 0.0)), 2.5), "redo restores influence scale")

	_check(rs.remove_bone(rig_id, "Fist"), "undo test removes Fist")
	_check(doc.undo_label() == "Remove bone", "remove_bone is one undo step")
	doc.undo()
	_check(_bone_index(rs.get_rig(rig_id), "Fist") >= 0, "undo restores the removed bone")
	doc.redo()
	_check(_bone_index(rs.get_rig(rig_id), "Fist") < 0, "redo removes the bone again")

	# Pose library.
	var pose_id: String = rs.save_pose(rig_id, "Undo Pose")
	_check(pose_id != "", "undo test saves a pose")
	_check(doc.undo_label() == "Save pose", "save_pose is one undo step")
	doc.undo()
	_check((rs.get_rig(rig_id).get("poses", []) as Array).is_empty(), "undo removes the saved pose")
	doc.redo()
	_check((rs.get_rig(rig_id).get("poses", []) as Array).size() == 1, "redo restores the saved pose")
	var restored_poses: Array = rs.get_rig(rig_id).get("poses", [])
	pose_id = str((restored_poses[0] as Dictionary).get("id", "")) if not restored_poses.is_empty() else ""

	_check(rs.rename_pose(rig_id, pose_id, "Renamed"), "undo test renames the pose")
	_check(doc.undo_label() == "Rename pose", "rename_pose is one undo step")
	doc.undo()
	var undone_poses: Array = rs.get_rig(rig_id).get("poses", [])
	_check(not undone_poses.is_empty() and str((undone_poses[0] as Dictionary).get("name", "")) == "Undo Pose", "undo restores the pose name")
	doc.redo()
	var redone_poses: Array = rs.get_rig(rig_id).get("poses", [])
	_check(not redone_poses.is_empty() and str((redone_poses[0] as Dictionary).get("name", "")) == "Renamed", "redo restores the pose name")

	var copy_id: String = rs.duplicate_pose(rig_id, pose_id)
	_check(copy_id != "", "undo test duplicates the pose")
	_check(doc.undo_label() == "Duplicate pose", "duplicate_pose is one undo step")
	doc.undo()
	_check((rs.get_rig(rig_id).get("poses", []) as Array).size() == 1, "undo removes the duplicate pose")
	doc.redo()
	_check((rs.get_rig(rig_id).get("poses", []) as Array).size() == 2, "redo restores the duplicate pose")

	rs.delete_pose(rig_id, pose_id)
	_check(doc.undo_label() == "Delete pose", "delete_pose is one undo step")
	doc.undo()
	_check((rs.get_rig(rig_id).get("poses", []) as Array).size() == 2, "undo restores the deleted pose")
	doc.redo()
	_check((rs.get_rig(rig_id).get("poses", []) as Array).size() == 1, "redo removes the deleted pose")

	# IK chains.
	var chain: String = rs.add_ik_chain(rig_id, "Root", "Spine", mesh_id)
	_check(chain != "", "undo test adds an IK chain")
	_check(doc.undo_label() == "Add IK chain", "add_ik_chain is one undo step")
	doc.undo()
	_check((rs.get_rig(rig_id).get("ik", []) as Array).is_empty(), "undo removes the IK chain")
	doc.redo()
	_check((rs.get_rig(rig_id).get("ik", []) as Array).size() == 1, "redo restores the IK chain")
	chain = str((rs.get_rig(rig_id)["ik"][0] as Dictionary).get("id", ""))

	rs.update_ik_chain(rig_id, chain, {"weight": 0.5})
	_check(doc.undo_label() == "Update IK chain", "update_ik_chain is one undo step")
	doc.undo()
	_check(_close(float((rs.get_rig(rig_id)["ik"][0] as Dictionary).get("weight", 0.0)), 1.0), "undo restores the IK weight")
	doc.redo()
	_check(_close(float((rs.get_rig(rig_id)["ik"][0] as Dictionary).get("weight", 0.0)), 0.5), "redo restores the IK weight")

	rs.delete_ik_chain(rig_id, chain)
	_check(doc.undo_label() == "Delete IK chain", "delete_ik_chain is one undo step")
	doc.undo()
	_check((rs.get_rig(rig_id).get("ik", []) as Array).size() == 1, "undo restores the deleted IK chain")
	doc.redo()
	_check((rs.get_rig(rig_id).get("ik", []) as Array).is_empty(), "redo removes the IK chain again")
	doc.queue_free()


func _surface_vertex_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for i in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(i)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return total


# -------------------------------------------------------------------------
# C3 — FABRIK IK
# -------------------------------------------------------------------------

func _test_ik() -> void:
	print("RIG STEP: IK")
	var doc := _new_doc("IK Test")
	var rs = doc.rig_system
	var rig_id := _make_chain_rig(doc)
	var target_id: String = doc.add_empty(Vector3(1.2, 0.8, 0))
	var target_node: Node3D = doc.nodes[target_id]
	var chain: String = rs.add_ik_chain(rig_id, "Root", "Spine", target_id)
	_check(chain != "", "add_ik_chain returns a chain id")
	var chains: Array = rs.get_rig(rig_id).get("ik", [])
	_check(chains.size() == 1 and int(chains[0].get("iterations", 0)) == 12, "IK defaults to 12 iterations")
	_check(chains.size() == 1 and bool(chains[0].get("enabled", false)), "IK is enabled by default")
	rs.solve_ik(rig_id)
	var end := _end_effector_world(doc, rig_id, "Spine")
	_check(end.distance_to(target_node.global_position) < 0.001, "a reachable target puts the end effector within 1e-3")

	# Weight 0 leaves the pose untouched.
	var skel := _skeleton(doc, rig_id)
	var before := [
		skel.get_bone_pose_rotation(0),
		skel.get_bone_pose_rotation(1),
	]
	rs.update_ik_chain(rig_id, chain, {"weight": 0.0})
	rs.solve_ik(rig_id)
	_check(skel.get_bone_pose_rotation(0).angle_to(before[0]) < 0.0001, "weight 0 leaves the root rotation unchanged")
	_check(skel.get_bone_pose_rotation(1).angle_to(before[1]) < 0.0001, "weight 0 leaves the end rotation unchanged")
	rs.update_ik_chain(rig_id, chain, {"weight": 1.0})

	# Unreachable target straightens the chain toward it.
	target_node.position = Vector3(10, 0, 0)
	rs.solve_ik(rig_id)
	var root_head: Vector3 = skel.to_global(skel.get_bone_global_pose(0).origin)
	end = _end_effector_world(doc, rig_id, "Spine")
	var reach := 2.0
	_check(absf(root_head.distance_to(end) - reach) < 0.001, "an unreachable target keeps the chain at maximum length")
	var direction := (end - root_head).normalized()
	_check(direction.dot((target_node.global_position - root_head).normalized()) > 0.999, "an unreachable chain points straight at the target")

	# Pole angle changes the bend plane.
	target_node.position = Vector3(1.2, 0.8, 0)
	rs.update_ik_chain(rig_id, chain, {"pole_angle": 0.0})
	rs.solve_ik(rig_id)
	var mid_a: Vector3 = skel.to_global(skel.get_bone_global_pose(1).origin)
	rs.update_ik_chain(rig_id, chain, {"pole_angle": PI * 0.5})
	rs.solve_ik(rig_id)
	var mid_b: Vector3 = skel.to_global(skel.get_bone_global_pose(1).origin)
	_check(mid_a.distance_to(mid_b) > 0.001, "pole angle moves the chain out of the old plane")

	# Iteration and tolerance contract.
	_check(IkSolverScript.MIN_ITERATIONS == 8, "IK clamps to at least 8 iterations")
	_check(IkSolverScript.MAX_ITERATIONS == 24, "IK clamps to at most 24 iterations")
	_check(_close(IkSolverScript.TOLERANCE, 0.001), "IK tolerance is 0.001")
	rs.update_ik_chain(rig_id, chain, {"iterations": 99})
	_check(int(rs.get_rig(rig_id)["ik"][0].get("iterations", 0)) == 24, "update_ik_chain clamps iterations to 24")

	# advance() is the Document hook and runs after animation.
	skel.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	skel.set_bone_pose_rotation(1, Quaternion.IDENTITY)
	rs.advance(0.016)
	end = _end_effector_world(doc, rig_id, "Spine")
	_check(end.distance_to(target_node.global_position) < 0.001, "advance() solves enabled chains")

	# Bake writes keys for every chain bone in one undo step.
	rs.solve_ik(rig_id)
	_check(rs.bake_ik(rig_id), "bake_ik succeeds")
	_check(doc.get_bone_keys(rig_id, "Root").size() >= 1, "bake_ik keys the chain root")
	_check(doc.get_bone_keys(rig_id, "Spine").size() >= 1, "bake_ik keys the chain end")
	_check(doc.can_undo(), "bake_ik creates an undo step")
	doc.undo()
	_check(doc.get_bone_keys(rig_id, "Root").is_empty(), "one undo removes every baked chain key")

	# Chain CRUD.
	rs.delete_ik_chain(rig_id, chain)
	_check(rs.get_rig(rig_id).get("ik", []).is_empty(), "delete_ik_chain removes the chain")
	doc.queue_free()


# -------------------------------------------------------------------------
# C4 — pose library and bone animation
# -------------------------------------------------------------------------

func _test_pose_and_bone_keys() -> void:
	print("RIG STEP: poses")
	var doc := _new_doc("Pose Test")
	var rs = doc.rig_system
	var rig_id := _make_chain_rig(doc)
	var skel := _skeleton(doc, rig_id)
	var q_root := Quaternion(Vector3.UP, 0.6)
	var q_spine := Quaternion(Vector3.RIGHT, -0.4)
	skel.set_bone_pose_rotation(0, q_root)
	skel.set_bone_pose_rotation(1, q_spine)
	doc.nodes[rig_id].position = Vector3(0.3, 0.1, -0.2)
	var pose_id: String = rs.save_pose(rig_id, "Reach")
	_check(pose_id != "", "save_pose stores a named pose")
	var rig: Dictionary = rs.get_rig(rig_id)
	var poses: Array = rig.get("poses", [])
	_check(poses.size() == 1, "the pose is in the rig record")
	var pose: Dictionary = poses[0]
	_check(pose.get("bones", {}).size() == 2, "the pose captures every bone rotation")
	_check(pose.get("root_position", null) is Array, "the pose captures the root position as JSON")
	_check(str(rs.save_pose(rig_id, "  ")) == "", "a pose name is required")

	skel.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	skel.set_bone_pose_rotation(1, Quaternion.IDENTITY)
	doc.nodes[rig_id].position = Vector3.ZERO
	rs.apply_pose(rig_id, pose_id)
	_check(skel.get_bone_pose_rotation(0).angle_to(q_root) < 0.001, "apply_pose restores the root rotation")
	_check(skel.get_bone_pose_rotation(1).angle_to(q_spine) < 0.001, "apply_pose restores the end rotation")
	_check(doc.nodes[rig_id].position.distance_to(Vector3(0.3, 0.1, -0.2)) < 0.001, "apply_pose restores the root position")
	_check(doc.get_bone_keys(rig_id, "Root").is_empty(), "apply_pose does not key")

	# Key pose is one undo step and stores the captured rotations.
	doc.current_time = 1.5
	var expected_root: Quaternion = skel.get_bone_pose_rotation(0)
	var expected_spine: Quaternion = skel.get_bone_pose_rotation(1)
	_check(rs.key_pose(rig_id), "key_pose succeeds")
	var root_keys: Array = doc.get_bone_keys(rig_id, "Root")
	var spine_keys: Array = doc.get_bone_keys(rig_id, "Spine")
	_check(root_keys.size() == 1, "key_pose keys the root at current_time")
	_check(spine_keys.size() == 1, "key_pose keys every bone")
	_check(root_keys.size() == 1 and (root_keys[0].get("value", Quaternion.IDENTITY) as Quaternion).angle_to(expected_root) < 0.001, "key_pose stores the captured root rotation")
	_check(spine_keys.size() == 1 and (spine_keys[0].get("value", Quaternion.IDENTITY) as Quaternion).angle_to(expected_spine) < 0.001, "key_pose stores the captured spine rotation")
	_check(doc.undo_label() == "Key pose", "key_pose is one undo step")
	doc.undo()
	_check(doc.get_bone_keys(rig_id, "Root").is_empty(), "one undo removes every pose key")

	# Bone key sample and delete through the Document contract.
	doc.current_time = 0.0
	doc.insert_bone_key(rig_id, "Root", Quaternion(Vector3.UP, 0.0))
	doc.current_time = 2.0
	doc.insert_bone_key(rig_id, "Root", Quaternion(Vector3.UP, 1.0))
	_check(doc.get_bone_keys(rig_id, "Root").size() == 2, "the Document stores two bone keys")
	var sampled: Quaternion = doc.sample_bone(rig_id, "Root", 1.0)
	_check(sampled.angle_to(Quaternion(Vector3.UP, 0.5)) < 0.01, "sample_bone interpolates between keys")
	doc.delete_bone_key(rig_id, "Root", 0)
	_check(doc.get_bone_keys(rig_id, "Root").size() == 1, "delete_bone_key removes one key")

	# Rename, duplicate and delete poses.
	if rs.has_method("rename_pose"):
		_check(rs.rename_pose(rig_id, pose_id, "Reach High"), "rename_pose succeeds")
	else:
		_check(false, "rename_pose exists")
	if rs.has_method("duplicate_pose"):
		var copy: String = rs.duplicate_pose(rig_id, pose_id)
		_check(copy != "" and rs.get_rig(rig_id).get("poses", []).size() == 2, "duplicate_pose deep-copies a pose")
	else:
		_check(false, "duplicate_pose exists")
	rs.delete_pose(rig_id, pose_id)
	_check(rs.get_rig(rig_id).get("poses", []).size() == 1, "delete_pose removes one pose")

	# Pose survives save/load.
	var data: Dictionary = doc.to_data()
	var doc2 := _new_doc("Pose Roundtrip")
	doc2.load_project(data, _tmp_dir)
	var rig2: Dictionary = doc2.rig_system.get_rig(rig_id)
	_check(rig2.get("poses", []).size() == 1, "poses survive save/load")
	var loaded_id: String = str(rig2["poses"][0].get("id", ""))
	doc2.rig_system.apply_pose(rig_id, loaded_id)
	var skel2 := _skeleton(doc2, rig_id)
	_check(skel2.get_bone_pose_rotation(0).angle_to(q_root) < 0.001, "a loaded pose can be applied")
	doc.queue_free()
	doc2.queue_free()


# -------------------------------------------------------------------------
# C4b — pose v2 and persistence
# -------------------------------------------------------------------------

func _test_pose_v2() -> void:
	print("RIG STEP: pose v2")
	var doc := _new_doc("Pose V2")
	var rs = doc.rig_system
	var rig_id := _make_chain_rig(doc)
	var skel := _skeleton(doc, rig_id)
	var node: Node3D = doc.nodes[rig_id]
	var p_root := Vector3(0.2, 0.3, 0.4)
	var q_root := Quaternion(Vector3.UP, 0.5)
	var s_root := Vector3(1.2, 1.3, 1.4)
	skel.set_bone_pose_position(0, p_root)
	skel.set_bone_pose_rotation(0, q_root)
	skel.set_bone_pose_scale(0, s_root)
	skel.set_bone_pose_position(1, Vector3(0.1, 0.5, 0.0))
	skel.set_bone_pose_rotation(1, Quaternion(Vector3.RIGHT, -0.2))
	skel.set_bone_pose_scale(1, Vector3(0.9, 1.1, 1.0))
	node.position = Vector3(0.4, -0.2, 0.7)
	doc.get_object(rig_id)["position"] = Vector3(0.4, -0.2, 0.7)

	var pose: Dictionary = PoseLibraryScript.capture(skel, node)
	var bones: Dictionary = pose.get("bones", {})
	_check(bones.size() == 2, "pose capture writes every bone")
	var root_pose: Dictionary = bones.get("Root", {})
	_check(root_pose.get("p", []) is Array and (root_pose["p"] as Array).size() == 3, "pose capture writes a p array")
	_check(root_pose.get("r", []) is Array and (root_pose["r"] as Array).size() == 4, "pose capture writes an r array")
	_check(root_pose.get("s", []) is Array and (root_pose["s"] as Array).size() == 3, "pose capture writes an s array")
	_check(PoseLibraryScript.array_to_vec3(root_pose.get("p", [])) == p_root, "pose capture stores the real position")
	_check(PoseLibraryScript.array_to_quat(root_pose.get("r", [])).angle_to(q_root) < 0.001, "pose capture stores the real rotation")
	_check(PoseLibraryScript.array_to_vec3(root_pose.get("s", [])) == s_root, "pose capture stores the real scale")
	_check(pose.get("root_position", []) is Array, "pose capture keeps a JSON root position")

	# apply_bones never moves the root node.
	skel.set_bone_pose_position(0, Vector3.ZERO)
	skel.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	skel.set_bone_pose_scale(0, Vector3.ONE)
	node.position = Vector3(9, 9, 9)
	PoseLibraryScript.apply_bones(skel, pose)
	_check(node.position == Vector3(9, 9, 9), "apply_bones leaves the root node untouched")
	_check(skel.get_bone_pose_position(0).distance_to(p_root) < 0.0001, "apply_bones restores the bone position")
	_check(skel.get_bone_pose_rotation(0).angle_to(q_root) < 0.001, "apply_bones restores the bone rotation")
	_check(skel.get_bone_pose_scale(0).distance_to(s_root) < 0.0001, "apply_bones restores the bone scale")

	PoseLibraryScript.apply(skel, node, pose)
	_check(node.position.distance_to(Vector3(0.4, -0.2, 0.7)) < 0.0001, "apply restores the root position explicitly")

	# A legacy quaternion pose stays readable and changes rotation only.
	skel.set_bone_pose_position(0, Vector3(0.25, 0.1, -0.1))
	skel.set_bone_pose_scale(0, Vector3(1.5, 1.6, 1.7))
	var legacy_q := Quaternion(Vector3.RIGHT, 0.35)
	var legacy := {"bones": {"Root": [legacy_q.x, legacy_q.y, legacy_q.z, legacy_q.w]}}
	PoseLibraryScript.apply_bones(skel, legacy)
	_check(skel.get_bone_pose_rotation(0).angle_to(legacy_q) < 0.001, "a legacy quaternion pose applies rotation")
	_check(skel.get_bone_pose_position(0).distance_to(Vector3(0.25, 0.1, -0.1)) < 0.0001, "a legacy pose leaves the position untouched")
	_check(skel.get_bone_pose_scale(0).distance_to(Vector3(1.5, 1.6, 1.7)) < 0.0001, "a legacy pose leaves the scale untouched")
	var legacy_serialized: Dictionary = PoseLibraryScript.deserialize(legacy)
	_check(legacy_serialized.get("bones", {}).has("Root"), "deserialize keeps a legacy pose bone")
	var serialized: Dictionary = PoseLibraryScript.serialize(pose)
	_check((serialized.get("bones", {}).get("Root", {}) as Dictionary).has("s"), "serialize preserves the v2 shape")

	skel.set_bone_pose_position(0, p_root)
	skel.set_bone_pose_rotation(0, q_root)
	skel.set_bone_pose_scale(0, s_root)

	# Rig JSON carries the live pose.
	var data: Dictionary = doc.to_data()
	var rigs: Array = data.get("rigs", [])
	_check(rigs.size() == 1 and (rigs[0] as Dictionary).has("pose"), "to_data writes a top-level rig pose")
	var json_pose: Dictionary = (rigs[0] as Dictionary).get("pose", {})
	_check((json_pose.get("bones", {}) as Dictionary).has("Root"), "the rig pose holds every bone")

	# Save, rebuild and load restores p/r/s without a history entry.
	var doc2 := _new_doc("Pose V2 Load")
	doc2.load_project(data, _tmp_dir)
	var skel2 := _skeleton(doc2, rig_id)
	_check(skel2 != null, "the pose roundtrip rebuilds the skeleton")
	if skel2 != null:
		_check(skel2.get_bone_pose_position(0).distance_to(p_root) < 0.001 and skel2.get_bone_pose_rotation(0).angle_to(q_root) < 0.001, "load restores the bone position and rotation")
		_check(skel2.get_bone_pose_scale(0).distance_to(s_root) < 0.001, "load restores the bone scale")
	_check(not doc2.has_open_edit(), "loading a pose opens no edit")
	_check(not doc2.can_undo(), "loading a pose creates no undo entry")

	# The object transform stays authoritative: a stale root_position in the
	# saved pose cannot move the loaded object.
	(data["rigs"][0] as Dictionary)["pose"]["root_position"] = [9, 9, 9]
	var doc3 := _new_doc("Pose V2 Root")
	doc3.load_project(data, _tmp_dir)
	var node3: Node3D = doc3.nodes[rig_id]
	_check(node3.position.distance_to(Vector3(0.4, -0.2, 0.7)) < 0.001, "load ignores the saved pose root_position")
	_check(node3.position.distance_to(Vector3(9, 9, 9)) > 1.0, "the saved pose cannot move the object root")

	# save_pose stores the v2 bone map and apply_pose restores all channels.
	node.position = Vector3(0.4, -0.2, 0.7)
	var pose_id: String = rs.save_pose(rig_id, "V2 Pose")
	var stored_poses: Array = rs.get_rig(rig_id).get("poses", [])
	_check(pose_id != "" and not stored_poses.is_empty(), "save_pose stores a v2 pose")
	if not stored_poses.is_empty():
		var stored_bones: Dictionary = (stored_poses[0] as Dictionary).get("bones", {})
		var stored_root: Dictionary = stored_bones.get("Root", {})
		_check(stored_root.has("p") and stored_root.has("r") and stored_root.has("s"), "save_pose stores p, r and s")
	skel.set_bone_pose_position(0, Vector3.ZERO)
	skel.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	skel.set_bone_pose_scale(0, Vector3.ONE)
	doc.get_object(rig_id)["position"] = Vector3(0.4, -0.2, 0.7)
	rs.apply_pose(rig_id, pose_id)
	_check(skel.get_bone_pose_position(0).distance_to(p_root) < 0.001, "apply_pose restores the position")
	_check(skel.get_bone_pose_scale(0).distance_to(s_root) < 0.001, "apply_pose restores the scale")
	doc.queue_free()
	doc2.queue_free()
	doc3.queue_free()


# -------------------------------------------------------------------------
# C4c — pose transactions, autokey and three-channel bone keys
# -------------------------------------------------------------------------

func _bone_track_index(doc: Node3D, rig_id: String, bone: String, type: int) -> int:
	if doc.animation == null:
		return -1
	var path: NodePath = doc._bone_track_path(rig_id, bone)
	for ti in range(doc.animation.get_track_count()):
		if doc.animation.track_get_type(ti) == type and doc.animation.track_get_path(ti) == path:
			return ti
	return -1


func _bone_key_at(doc: Node3D, rig_id: String, bone: String, type: int, time: float) -> int:
	var track := _bone_track_index(doc, rig_id, bone, type)
	if track < 0:
		return -1
	return doc.animation.track_find_key(track, time, Animation.FIND_MODE_EXACT)


func _bone_key_count(doc: Node3D, rig_id: String, bone: String, type: int) -> int:
	var track := _bone_track_index(doc, rig_id, bone, type)
	if track < 0:
		return 0
	return doc.animation.track_get_key_count(track)


func _test_pose_transactions() -> void:
	print("RIG STEP: pose transactions")
	var doc := _new_doc("Pose Transactions")
	var rs = doc.rig_system
	var rig_id := _make_chain_rig(doc)
	var skel := _skeleton(doc, rig_id)

	var p_root := Vector3(0.15, 0.25, 0.35)
	var q_root := Quaternion(Vector3.UP, 0.45)
	var s_root := Vector3(1.1, 1.2, 1.3)

	# insert_pose_channel writes one track per channel at current_time.
	doc.current_time = 1.25
	var rot_key: int = doc.insert_pose_channel(rig_id, "Root", "rotation", q_root)
	var pos_key: int = doc.insert_pose_channel(rig_id, "Root", "position", p_root)
	var scale_key: int = doc.insert_pose_channel(rig_id, "Root", "scale", s_root)
	_check(rot_key >= 0 and pos_key >= 0 and scale_key >= 0, "insert_pose_channel returns a key index")
	_check(_bone_track_index(doc, rig_id, "Root", Animation.TYPE_ROTATION_3D) >= 0, "insert_pose_channel creates a rotation track")
	_check(_bone_track_index(doc, rig_id, "Root", Animation.TYPE_POSITION_3D) >= 0, "insert_pose_channel creates a position track")
	_check(_bone_track_index(doc, rig_id, "Root", Animation.TYPE_SCALE_3D) >= 0, "insert_pose_channel creates a scale track")
	_check(_bone_key_count(doc, rig_id, "Root", Animation.TYPE_ROTATION_3D) == 1, "the rotation track holds one key")
	_check(_bone_key_count(doc, rig_id, "Root", Animation.TYPE_POSITION_3D) == 1, "the position track holds one key")
	_check(_bone_key_count(doc, rig_id, "Root", Animation.TYPE_SCALE_3D) == 1, "the scale track holds one key")

	# A second call at the same time updates instead of duplicating.
	var updated_q := Quaternion(Vector3.RIGHT, 0.2)
	doc.insert_pose_channel(rig_id, "Root", "rotation", updated_q)
	var rot_track := _bone_track_index(doc, rig_id, "Root", Animation.TYPE_ROTATION_3D)
	_check(_bone_key_count(doc, rig_id, "Root", Animation.TYPE_ROTATION_3D) == 1, "insert_pose_channel updates an existing key")
	if rot_track >= 0:
		_check((doc.animation.track_get_key_value(rot_track, 0) as Quaternion).angle_to(updated_q) < 0.001, "the updated key stores the new rotation")

	# insert_pose_keys writes all three channels for a v2 bone.
	doc.current_time = 2.0
	doc.insert_pose_keys(rig_id, {"bones": {"Spine": {
		"p": Vector3(0.1, 0.5, 0.0),
		"r": [0.0, 0.2, 0.0, 0.98],
		"s": Vector3(0.9, 1.0, 1.1),
	}}})
	var rotation_type := Animation.TYPE_ROTATION_3D
	var position_type := Animation.TYPE_POSITION_3D
	var scale_type := Animation.TYPE_SCALE_3D
	for type in [position_type, rotation_type, scale_type]:
		_check(_bone_key_count(doc, rig_id, "Spine", type) == 1, "insert_pose_keys writes channel %d" % type)

	# A legacy quaternion map still writes rotation only.
	doc.current_time = 2.5
	doc.insert_pose_keys(rig_id, {"bones": {"Spine": [0.0, 0.0, 0.0, 1.0]}})
	_check(_bone_key_count(doc, rig_id, "Spine", rotation_type) == 2, "a legacy map writes a rotation key")
	_check(_bone_key_count(doc, rig_id, "Spine", position_type) == 1, "a legacy map writes no position key")
	_check(_bone_key_count(doc, rig_id, "Spine", scale_type) == 1, "a legacy map writes no scale key")

	# set_bone_pose applies only the supplied channels and autokeys them.
	doc.set_autokey(true)
	doc.current_time = 3.0
	skel.set_bone_pose_position(0, Vector3.ZERO)
	skel.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	skel.set_bone_pose_scale(0, Vector3.ONE)
	var q_set := Quaternion(Vector3.FORWARD, 0.3)
	_check(rs.set_bone_pose(rig_id, "Root", {"r": q_set}), "set_bone_pose applies a rotation patch")
	_check(skel.get_bone_pose_rotation(0).angle_to(q_set) < 0.001, "set_bone_pose changes the live rotation")
	_check(_bone_key_at(doc, rig_id, "Root", rotation_type, 3.0) >= 0, "autokey writes a rotation key")
	_check(_bone_key_at(doc, rig_id, "Root", position_type, 3.0) < 0, "a rotation patch writes no position key")
	_check(_bone_key_at(doc, rig_id, "Root", scale_type, 3.0) < 0, "a rotation patch writes no scale key")

	var p_set := Vector3(0.2, 0.3, 0.4)
	var s_set := Vector3(1.2, 1.3, 1.4)
	_check(rs.set_bone_pose(rig_id, "Root", {"p": p_set, "s": s_set}), "set_bone_pose applies a position and scale patch")
	_check(skel.get_bone_pose_position(0).distance_to(p_set) < 0.0001 and skel.get_bone_pose_scale(0).distance_to(s_set) < 0.0001, "set_bone_pose changes position and scale")
	_check(skel.get_bone_pose_rotation(0).angle_to(q_set) < 0.001, "a p/s patch leaves the rotation untouched")
	_check(_bone_key_at(doc, rig_id, "Root", position_type, 3.0) >= 0, "autokey writes a position key")
	_check(_bone_key_at(doc, rig_id, "Root", scale_type, 3.0) >= 0, "autokey writes a scale key")

	# An existing time updates the key.
	var p_updated := Vector3(-0.2, -0.3, -0.4)
	doc.insert_pose_channel(rig_id, "Root", "position", p_set)
	rs.set_bone_pose(rig_id, "Root", {"p": p_updated})
	var pos_track := _bone_track_index(doc, rig_id, "Root", position_type)
	_check(_bone_key_at(doc, rig_id, "Root", position_type, 3.0) >= 0, "autokey keeps the existing position key")
	if pos_track >= 0:
		var pos_at: int = doc.animation.track_find_key(pos_track, 3.0, Animation.FIND_MODE_EXACT)
		_check(pos_at >= 0 and (doc.animation.track_get_key_value(pos_track, pos_at) as Vector3).distance_to(p_updated) < 0.0001, "autokey updates the key value")

	# Autokey off changes the skeleton and writes nothing.
	doc.set_autokey(false)
	doc.current_time = 4.0
	_check(rs.set_bone_pose(rig_id, "Root", {"p": Vector3(0.9, 0.9, 0.9)}), "set_bone_pose works with autokey off")
	_check(skel.get_bone_pose_position(0).distance_to(Vector3(0.9, 0.9, 0.9)) < 0.0001, "autokey off still moves the bone")
	_check(_bone_key_at(doc, rig_id, "Root", position_type, 4.0) < 0, "autokey off writes no key")
	_check(not rs.set_bone_pose(rig_id, "Missing", {"r": q_set}), "set_bone_pose refuses a missing bone")

	# apply_saved_pose is one transaction and applies autokey.
	skel.set_bone_pose_position(0, p_root)
	skel.set_bone_pose_rotation(0, q_root)
	skel.set_bone_pose_scale(0, s_root)
	var saved_pose: String = rs.save_pose(rig_id, "Transaction Pose")
	skel.set_bone_pose_position(0, Vector3.ZERO)
	skel.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	skel.set_bone_pose_scale(0, Vector3.ONE)
	doc.set_autokey(true)
	doc.current_time = 5.0
	_check(rs.apply_saved_pose(rig_id, saved_pose), "apply_saved_pose succeeds")
	_check(skel.get_bone_pose_position(0).distance_to(p_root) < 0.001, "apply_saved_pose restores the position")
	_check(skel.get_bone_pose_rotation(0).angle_to(q_root) < 0.001, "apply_saved_pose restores the rotation")
	_check(skel.get_bone_pose_scale(0).distance_to(s_root) < 0.001, "apply_saved_pose restores the scale")
	_check(_bone_key_at(doc, rig_id, "Root", position_type, 5.0) >= 0, "apply_saved_pose autokeys the position")
	_check(_bone_key_at(doc, rig_id, "Root", rotation_type, 5.0) >= 0, "apply_saved_pose autokeys the rotation")
	_check(_bone_key_at(doc, rig_id, "Root", scale_type, 5.0) >= 0, "apply_saved_pose autokeys the scale")
	_check(doc.undo_label() == "Apply pose", "apply_saved_pose is one undo entry")
	doc.undo()
	skel = _skeleton(doc, rig_id)
	_check(_bone_key_at(doc, rig_id, "Root", position_type, 5.0) < 0, "one undo removes the applied pose keys")
	_check(_bone_key_at(doc, rig_id, "Root", rotation_type, 5.0) < 0, "one undo removes the applied rotation keys")

	# Reset uses the same transaction and autokey path.
	doc.set_autokey(true)
	doc.current_time = 6.0
	skel.set_bone_pose_position(0, Vector3(1.0, 2.0, 3.0))
	skel.set_bone_pose_rotation(0, Quaternion(Vector3.UP, 0.8))
	skel.set_bone_pose_scale(0, Vector3(2.0, 2.0, 2.0))
	rs.reset_bone_pose(rig_id, "Root")
	_check(skel.get_bone_pose_position(0).length() < 0.0001 and skel.get_bone_pose_rotation(0).angle_to(Quaternion.IDENTITY) < 0.001 and skel.get_bone_pose_scale(0).distance_to(Vector3.ONE) < 0.0001, "reset_bone_pose resets p, r and s")
	_check(_bone_key_at(doc, rig_id, "Root", position_type, 6.0) >= 0 and _bone_key_at(doc, rig_id, "Root", rotation_type, 6.0) >= 0 and _bone_key_at(doc, rig_id, "Root", scale_type, 6.0) >= 0, "reset_bone_pose autokeys every channel")
	_check(doc.undo_label() == "Reset pose", "reset_bone_pose is one undo entry")

	skel.set_bone_pose_position(1, Vector3(1.0, 1.0, 1.0))
	skel.set_bone_pose_rotation(1, Quaternion(Vector3.RIGHT, 0.5))
	skel.set_bone_pose_scale(1, Vector3(2.0, 2.0, 2.0))
	rs.reset_all_poses(rig_id)
	_check(skel.get_bone_pose_position(0).length() < 0.0001 and skel.get_bone_pose_position(1).length() < 0.0001, "reset_all_poses resets every bone position")
	_check(skel.get_bone_pose_rotation(0).angle_to(Quaternion.IDENTITY) < 0.001 and skel.get_bone_pose_rotation(1).angle_to(Quaternion.IDENTITY) < 0.001, "reset_all_poses resets every bone rotation")
	_check(skel.get_bone_pose_scale(0).distance_to(Vector3.ONE) < 0.0001 and skel.get_bone_pose_scale(1).distance_to(Vector3.ONE) < 0.0001, "reset_all_poses resets every bone scale")
	_check(_bone_key_at(doc, rig_id, "Spine", position_type, 6.0) >= 0 and _bone_key_at(doc, rig_id, "Spine", rotation_type, 6.0) >= 0 and _bone_key_at(doc, rig_id, "Spine", scale_type, 6.0) >= 0, "reset_all_poses autokeys every channel")

	# key_pose writes all three channels and one undo restores the counts.
	var key_doc := _new_doc("Key Pose Three")
	var key_rs = key_doc.rig_system
	var key_rig := _make_chain_rig(key_doc)
	var key_skel := _skeleton(key_doc, key_rig)
	key_doc.current_time = 0.0
	key_doc.insert_pose_channel(key_rig, "Root", "position", Vector3.ZERO)
	key_doc.current_time = 1.0
	key_skel.set_bone_pose_position(0, Vector3(0.1, 0.2, 0.3))
	key_skel.set_bone_pose_rotation(0, Quaternion(Vector3.UP, 0.2))
	key_skel.set_bone_pose_scale(0, Vector3(1.1, 1.1, 1.1))
	key_skel.set_bone_pose_position(1, Vector3(0.0, 0.9, 0.0))
	key_skel.set_bone_pose_rotation(1, Quaternion(Vector3.RIGHT, -0.1))
	key_skel.set_bone_pose_scale(1, Vector3(0.95, 1.05, 1.0))
	_check(key_rs.key_pose(key_rig), "key_pose succeeds with the full pose")
	for type in [position_type, rotation_type, scale_type]:
		_check(_bone_key_at(key_doc, key_rig, "Root", type, 1.0) >= 0, "key_pose writes the root channel %d" % type)
		_check(_bone_key_at(key_doc, key_rig, "Spine", type, 1.0) >= 0, "key_pose writes the spine channel %d" % type)
	_check(key_doc.undo_label() == "Key pose", "key_pose is one undo entry")
	key_doc.undo()
	for type in [position_type, rotation_type, scale_type]:
		_check(_bone_key_at(key_doc, key_rig, "Root", type, 1.0) < 0, "one undo removes the keyed root channel %d" % type)
	_check(_bone_key_at(key_doc, key_rig, "Root", position_type, 0.0) >= 0, "undo returns the previous key counts")

	# The rotation-only Document contract is unchanged.
	key_doc.current_time = 2.0
	key_doc.insert_bone_key(key_rig, "Root", Quaternion(Vector3.UP, 0.3))
	_check(_bone_key_at(key_doc, key_rig, "Root", rotation_type, 2.0) >= 0, "insert_bone_key writes a rotation key")
	_check(_bone_key_at(key_doc, key_rig, "Root", position_type, 2.0) < 0 and _bone_key_at(key_doc, key_rig, "Root", scale_type, 2.0) < 0, "insert_bone_key stays rotation-only")

	# One pose gesture is one transaction; a tap opens none.
	var drag_doc := _new_doc("Pose Drag")
	var drag_rig := _make_chain_rig(drag_doc)
	var drag_skel := _skeleton(drag_doc, drag_rig)
	drag_doc.rig_system.set_active_bone(drag_rig, "Root")
	var view := FakeView.new()
	add_child(view)
	var overlay = RigOverlayScript.new()
	add_child(overlay)
	overlay.setup(drag_doc, view, drag_doc.rig_system)
	overlay.set_rig(drag_rig)
	overlay.set_enabled(true)
	await get_tree().process_frame
	var head: Vector3 = drag_skel.to_global(drag_skel.get_bone_global_pose(0).origin)
	var screen: Vector2 = view.world_to_screen(head)
	var undo_before: int = (drag_doc._undo_stack as Array).size()
	overlay.press_at(screen)
	overlay.release_drag()
	_check(not drag_doc.has_open_edit(), "a zero-movement tap closes its transaction")
	_check((drag_doc._undo_stack as Array).size() == undo_before, "a zero-movement tap creates no undo entry")

	var before: Quaternion = drag_skel.get_bone_pose_rotation(0)
	overlay.press_at(screen)
	_check(drag_doc.has_open_edit(), "a pose drag opens one transaction")
	overlay.drag_at(screen + Vector2(48, 0))
	overlay.release_drag()
	_check(not drag_doc.has_open_edit(), "the pose drag closes its transaction")
	_check(drag_skel.get_bone_pose_rotation(0).angle_to(before) > 0.001, "dragging rotates the bone")
	_check((drag_doc._undo_stack as Array).size() == undo_before + 1, "a pose drag is one undo entry")
	drag_doc.undo()
	drag_skel = _skeleton(drag_doc, drag_rig)
	_check(drag_skel.get_bone_pose_rotation(0).angle_to(before) < 0.001, "undo restores the start pose")

	overlay.queue_free()
	view.queue_free()
	key_doc.queue_free()
	drag_doc.queue_free()
	doc.queue_free()


func _rest_bone(doc: Node3D, rig_id: String, name: String) -> Dictionary:
	var rig: Dictionary = doc.rig_system.get_rig(rig_id)
	var index := _bone_index(rig, name)
	return rig["bones"][index] if index >= 0 else {}


func _test_one_gesture_and_edit_parity() -> void:
	print("RIG STEP: one gesture and edit parity")
	var doc := _new_doc("One Gesture")
	var rs = doc.rig_system
	var rig_id := _make_chain_rig(doc)
	var view := FakeView.new()
	add_child(view)
	var overlay = RigOverlayScript.new()
	add_child(overlay)
	overlay.setup(doc, view, rs)
	overlay.set_rig(rig_id)
	overlay.set_enabled(true)
	await get_tree().process_frame
	var skel := _skeleton(doc, rig_id)
	var spine := skel.find_bone("Spine")
	var press: Vector2 = view.world_to_screen(Vector3(0.0, 1.4, 0.0))

	var pose_before := skel.get_bone_pose_rotation(spine)
	var undo_before: int = (doc._undo_stack as Array).size()
	overlay.press_at(press)
	_check(str(rs.get_rig(rig_id).get("active_bone", "")) == "Spine",
		"pressing a bone body makes that bone active")
	_check(overlay.current_drag_kind() == "bone",
		"pressing a bone body starts the drag in the same gesture")
	overlay.drag_at(press + Vector2(46, 0))
	_check(skel.get_bone_pose_rotation(spine).angle_to(pose_before) > 0.01,
		"the pose rotation changes before release")
	overlay.release_drag()
	_check((doc._undo_stack as Array).size() == undo_before + 1,
		"one pose gesture is one undo entry")

	var undo_tap: int = (doc._undo_stack as Array).size()
	overlay.press_at(press)
	overlay.release_drag()
	_check((doc._undo_stack as Array).size() == undo_tap,
		"a tap with no motion selects but adds no undo entry")

	overlay.set_mode("edit")
	overlay.set_transform_mode("rotate")
	_check(overlay.transform_mode() == "rotate", "Edit mode accepts Rotate")
	var rest_before: Dictionary = _rest_bone(doc, rig_id, "Spine")
	var rest_rot: Quaternion = rest_before.get("r", Quaternion.IDENTITY)
	var rest_len := float(rest_before.get("length", 0.0))
	var edit_undo: int = (doc._undo_stack as Array).size()
	overlay.press_at(press)
	_check(overlay.current_drag_kind() == "bone",
		"pressing a bone body in Edit starts the drag")
	overlay.drag_at(press + Vector2(40, 12))
	overlay.release_drag()
	var rest_after: Dictionary = _rest_bone(doc, rig_id, "Spine")
	_check((rest_after.get("r", Quaternion.IDENTITY) as Quaternion).angle_to(rest_rot) > 0.01,
		"Edit body drag rotates the rest bone")
	_check(is_equal_approx(float(rest_after.get("length", 0.0)), rest_len),
		"Edit body drag never changes the bone length")
	_check((doc._undo_stack as Array).size() == edit_undo + 1,
		"one Edit body gesture is one undo entry")

	overlay.set_transform_mode("move")
	_check(overlay.transform_mode() == "move", "Edit mode accepts Move")
	overlay.queue_free()
	view.queue_free()
	doc.queue_free()


func _gizmo_sample(overlay, axis: String) -> Vector2:
	# 3/8 of the ring avoids the projected crossings with the other two axis
	# rings and with the free centre handle under the orthographic fake view.
	var points: PackedVector2Array = overlay.gizmo_ring_points(axis)
	return points[points.size() * 3 / 8] if not points.is_empty() else Vector2.ZERO


func _gizmo_arrow_sample(overlay, axis: String) -> Vector2:
	var points: PackedVector2Array = overlay.gizmo_arrow_points(axis)
	return (points[0] + points[1]) * 0.5 if points.size() >= 2 else Vector2.ZERO


func _test_gizmo() -> void:
	print("RIG STEP: rig gizmo")
	var doc := _new_doc("Rig Gizmo")
	var rs = doc.rig_system
	var rig_id := _make_chain_rig(doc)
	rs.set_active_bone(rig_id, "Spine")
	var view := FakeView.new()
	add_child(view)
	var overlay = RigOverlayScript.new()
	add_child(overlay)
	overlay.setup(doc, view, rs)
	overlay.set_rig(rig_id)
	overlay.set_enabled(true)
	await get_tree().process_frame

	_check(overlay.gizmo_axes() == PackedStringArray(["x", "y", "z", "free"]),
		"the gizmo exposes x/y/z/free")
	_check(overlay.gizmo_visible(), "the gizmo is visible with an active bone")
	for axis in ["x", "y", "z", "free"]:
		var sample := _gizmo_sample(overlay, axis)
		_check(overlay.gizmo_handle_at(sample) == axis,
			"a projected %s ring sample hits its axis" % axis)

	overlay.set_mode("edit")
	overlay.set_transform_mode("rotate")
	_check(overlay.gizmo_visible(), "the gizmo stays visible in Edit")
	var rest_before: Quaternion = _rest_bone(doc, rig_id, "Spine").get("r", Quaternion.IDENTITY)
	var undo_before: int = (doc._undo_stack as Array).size()
	var sample := _gizmo_sample(overlay, "x")
	overlay.press_at(sample)
	_check(overlay.current_drag_kind() == "gizmo_rotate",
		"pressing a ring starts a gizmo rotate")
	overlay.drag_at(sample + Vector2(60, 0))
	overlay.release_drag()
	var rest_after: Quaternion = _rest_bone(doc, rig_id, "Spine").get("r", Quaternion.IDENTITY)
	_check(rest_after.angle_to(rest_before) > 0.01, "the X ring rotates the rest bone")
	_check((doc._undo_stack as Array).size() == undo_before + 1,
		"one gizmo rotation is one undo entry")

	overlay.set_transform_mode("move")
	var p_before: Vector3 = _rest_bone(doc, rig_id, "Spine").get("p", Vector3.ZERO)
	var move_sample: Vector2 = _gizmo_arrow_sample(overlay, "x")
	overlay.press_at(move_sample)
	_check(overlay.current_drag_kind() == "gizmo_move",
		"pressing an arrow starts a gizmo move")
	overlay.drag_at(move_sample + Vector2(50, 0))
	overlay.release_drag()
	var p_after: Vector3 = _rest_bone(doc, rig_id, "Spine").get("p", Vector3.ZERO)
	_check(absf(p_after.x - p_before.x) > 0.001, "the X arrow moves the rest bone")
	_check(absf(p_after.y - p_before.y) < 0.001 and absf(p_after.z - p_before.z) < 0.001,
		"the X arrow keeps Y and Z near zero")
	overlay.queue_free()
	view.queue_free()
	doc.queue_free()


# -------------------------------------------------------------------------
# C4d — touch transform/axis editing and the Rest/Pose panel
# -------------------------------------------------------------------------

func _test_touch_pose_editing() -> void:
	print("RIG STEP: touch pose editing")
	# The floating toolbar is gone; its transform/axis surface lives in the Rig
	# context row. _test_rig_toolbar covers its defaults, 44 dp targets, mode
	# transitions and the imported-rig lock. This test owns the pose gestures.
	var doc := _new_doc("Touch Pose")
	var rs = doc.rig_system
	var rig_id := _make_chain_rig(doc)
	rs.set_active_bone(rig_id, "Root")
	var skel := _skeleton(doc, rig_id)
	var view := FakeView.new()
	add_child(view)
	var overlay = RigOverlayScript.new()
	add_child(overlay)
	overlay.setup(doc, view, rs)
	overlay.set_rig(rig_id)
	overlay.set_enabled(true)
	doc.set_autokey(false)
	await get_tree().process_frame

	# Axis-locked rotation: local X only, 0.012 rad per pixel, clamped.
	overlay.set_transform_mode("rotate")
	overlay.set_axis_mode("x")
	skel.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	var screen: Vector2 = view.world_to_screen(skel.to_global(skel.get_bone_global_pose(0).origin))
	var undo_before: int = (doc._undo_stack as Array).size()
	overlay.press_at(screen)
	overlay.drag_at(screen + Vector2(60, 0))
	_check(overlay.readout_visible(), "a rotation drag shows the live readout")
	_check(overlay.readout_text().ends_with("°"), "the rotation readout is in degrees")
	overlay.release_drag()
	_check(not overlay.readout_visible(), "the rotation readout hides on release")
	var rotated := skel.get_bone_pose_rotation(0)
	var delta := Quaternion.IDENTITY.inverse() * rotated
	var axis := delta.get_axis()
	var angle := delta.get_angle()
	_check(absf(absf(axis.x) - 1.0) < 0.001 and absf(axis.y) < 0.001 and absf(axis.z) < 0.001, "axis-locked rotation uses the local X axis")
	_check(absf(angle - 60.0 * 0.012) < 0.001, "axis rotation uses 0.012 rad per pixel")
	_check(absf(delta.get_euler().y) < 0.001 and absf(delta.get_euler().z) < 0.001, "axis-locked rotation leaves the other local axes at the start")
	_check((doc._undo_stack as Array).size() == undo_before + 1, "one rotation gesture is one undo entry")

	# Axis-locked move: world X only, never rotates.
	overlay.set_transform_mode("move")
	overlay.set_axis_mode("x")
	skel.set_bone_pose_position(0, Vector3.ZERO)
	skel.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	# Press the bone body, away from the gizmo's centre handle and arrows, so
	# this exercises the bone move path rather than a gizmo drag.
	screen = view.world_to_screen(skel.to_global(skel.get_bone_global_pose(0).origin)) + Vector2(20, -90)
	undo_before = (doc._undo_stack as Array).size()
	overlay.press_at(screen)
	overlay.drag_at(screen + Vector2(50, 40))
	_check(overlay.readout_visible(), "a move drag shows the live readout")
	_check(overlay.readout_text().ends_with(" u"), "the move readout is in units")
	overlay.release_drag()
	_check(not overlay.readout_visible(), "the move readout hides on release")
	var moved := skel.get_bone_pose_position(0)
	_check(moved.x > 0.01, "axis-locked move changes world X")
	_check(absf(moved.y) < 0.001 and absf(moved.z) < 0.001, "axis-locked move ignores the other world axes")
	_check(skel.get_bone_pose_rotation(0).angle_to(Quaternion.IDENTITY) < 0.001, "axis-locked move does not rotate")
	_check((doc._undo_stack as Array).size() == undo_before + 1, "one move gesture is one undo entry")

	# Free move translates in the camera plane and never rotates.
	overlay.set_axis_mode("free")
	skel.set_bone_pose_position(0, Vector3.ZERO)
	screen = view.world_to_screen(skel.to_global(skel.get_bone_global_pose(0).origin))
	overlay.press_at(screen)
	overlay.drag_at(screen + Vector2(30, -20))
	overlay.release_drag()
	var free_move := skel.get_bone_pose_position(0)
	_check(free_move.length() > 0.01, "free move translates the active bone")
	_check(absf(free_move.y) > 0.001, "free move follows the vertical drag")
	_check(skel.get_bone_pose_rotation(0).angle_to(Quaternion.IDENTITY) < 0.001, "free move does not rotate the bone")
	overlay.queue_free()
	view.queue_free()

	# Rest/Pose panel sections, pose commits and the per-bone reset.
	var panel_doc := _new_doc("Rest Pose Panel")
	var panel_rs = panel_doc.rig_system
	var panel_rig := _make_chain_rig(panel_doc)
	panel_rs.get_rig(panel_rig)["imported"] = true
	panel_rs.set_active_rig(panel_rig)
	panel_rs.set_active_bone(panel_rig, "Root")
	var panel = RigPanelScript.new()
	panel.name = "RestPosePanel"
	add_child(panel)
	panel.setup(panel_doc)
	await get_tree().process_frame
	await get_tree().process_frame
	var rest_section = panel.find_child("RestSection", true, false)
	var pose_section = panel.find_child("PoseSection", true, false)
	_check(rest_section != null and pose_section != null, "the bone inspector has Rest and Pose sections")
	var rest_label = panel.find_child("RestSectionLabel", true, false)
	var pose_label = panel.find_child("PoseSectionLabel", true, false)
	_check(rest_label != null and rest_label.text == "REST", "the Rest section is labelled")
	_check(pose_label != null and pose_label.text == "POSE", "the Pose section is labelled")
	var note = panel.find_child("ImportedRigNote", true, false)
	_check(note != null and note.visible and note.text.contains("Pose and IK still work."), "the imported note says Pose and IK still work")
	_check(note != null and rest_section != null and note.get_index() < rest_section.get_index(), "the imported note sits directly above Rest")

	var rest_px = panel.find_child("RestPX", true, false)
	var rest_len = panel.find_child("BoneLengthField", true, false)
	var pose_px = panel.find_child("PosePX", true, false)
	var pose_rx = panel.find_child("PoseRX", true, false)
	var pose_sz = panel.find_child("PoseSZ", true, false)
	_check(rest_px != null and rest_px.mouse_filter == Control.MOUSE_FILTER_IGNORE, "an imported rig disables the Rest position fields")
	_check(rest_len != null and rest_len.mouse_filter == Control.MOUSE_FILTER_IGNORE, "an imported rig disables the Rest length field")
	_check(pose_px != null and pose_px.mouse_filter == Control.MOUSE_FILTER_STOP, "an imported rig keeps the Pose position fields editable")
	_check(pose_rx != null and pose_rx.mouse_filter == Control.MOUSE_FILTER_STOP, "an imported rig keeps the Pose rotation fields editable")
	_check(pose_sz != null and pose_sz.mouse_filter == Control.MOUSE_FILTER_STOP, "an imported rig keeps the Pose scale fields editable")
	var pose_fields := ["PosePX", "PosePY", "PosePZ", "PoseRX", "PoseRY", "PoseRZ", "PoseSX", "PoseSY", "PoseSZ"]
	for field_name in pose_fields:
		var field = panel.find_child(field_name, true, false)
		_check(field != null and field.custom_minimum_size.y >= 43.5, "%s is a 44 dp row" % field_name)

	# A Pose commit goes through set_bone_pose in one transaction and autokeys.
	var panel_skel := _skeleton(panel_doc, panel_rig)
	panel_skel.set_bone_pose_position(0, Vector3.ZERO)
	panel_doc.set_autokey(true)
	panel_doc.current_time = 1.0
	var panel_undo: int = (panel_doc._undo_stack as Array).size()
	if pose_px != null:
		pose_px.set_value(0.5)
		pose_px.value_changed.emit(0.5)
		await get_tree().process_frame
	_check(panel_skel.get_bone_pose_position(0).distance_to(Vector3(0.5, 0.0, 0.0)) < 0.001, "a Pose field commit moves the bone")
	_check(_bone_key_at(panel_doc, panel_rig, "Root", Animation.TYPE_POSITION_3D, 1.0) >= 0, "a Pose field commit applies autokey")
	_check((panel_doc._undo_stack as Array).size() == panel_undo + 1, "a Pose field commit is one undo entry")

	var reset_button: Button = panel.find_child("ResetPoseButton", true, false)
	_check(reset_button != null and reset_button.custom_minimum_size == Vector2(96, 44), "Reset pose is a 96x44 target")
	_check(panel.find_child("ResetAllPoseButton", true, false) != null, "reset-all remains")
	var caption = panel.find_child("KeyChannelsCaption", true, false)
	_check(caption != null and caption.text == "Rotation, position and scale", "the key buttons state their three channels")
	_check(panel.find_child("KeyBoneButton", true, false) != null and panel.find_child("KeyPoseButton", true, false) != null, "the rig tab keeps its key buttons")

	panel.queue_free()
	panel_doc.queue_free()
	doc.queue_free()


# -------------------------------------------------------------------------
# C2b — imported skeleton adoption
# -------------------------------------------------------------------------

func _test_imported_adoption() -> void:
	print("RIG STEP: imported adoption")
	var doc := _new_doc("Import Test")
	var object_id: String = doc.add_empty(Vector3.ZERO)
	var node: Node3D = doc.nodes[object_id]
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	node.add_child(skel)
	skel.add_bone("Hip")
	skel.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	skel.add_bone("Knee")
	skel.set_bone_parent(1, 0)
	skel.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0)))
	skel.reset_bone_poses()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Body"
	mesh_instance.mesh = BoxMesh.new()
	node.add_child(mesh_instance)
	var adopted: bool = doc.rig_system.adopt_imported_skeleton(object_id, node)
	_check(adopted, "adopt_imported_skeleton accepts a node with a Skeleton3D")
	var rig: Dictionary = doc.rig_system.get_rig(object_id)
	_check(not rig.is_empty(), "adoption creates a rig record")
	_check(rig.get("bones", []).size() == 2, "adoption copies the imported bones")
	_check(str(rig["bones"][1].get("name", "")) == "Knee", "adoption keeps imported bone names")
	_check(doc.rig_system.active_rig_id() == object_id, "the adopted rig becomes active")

	# Pose capture/apply works on the imported skeleton.
	var q_hip := Quaternion(Vector3.UP, 0.7)
	skel.set_bone_pose_rotation(0, q_hip)
	var pose_id: String = doc.rig_system.save_pose(object_id, "Imported")
	_check(pose_id != "", "the adopted rig can save a pose")
	skel.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	doc.rig_system.apply_pose(object_id, pose_id)
	_check(skel.get_bone_pose_rotation(0).angle_to(q_hip) < 0.001, "the adopted rig can apply a pose")

	# Imported bone structure is read-only; only pose/IK may change.
	var bones_before: int = (doc.rig_system.get_rig(object_id).get("bones", []) as Array).size()
	_check(doc.rig_system.add_bone(object_id, "Extra", "Hip", _rest()) == -1, "imported rigs reject add_bone")
	_check(not doc.rig_system.remove_bone(object_id, "Knee"), "imported rigs reject remove_bone")
	_check(not doc.rig_system.rename_bone(object_id, "Knee", "Leg"), "imported rigs reject rename_bone")
	_check(not doc.rig_system.set_bone_parent(object_id, "Knee", ""), "imported rigs reject set_bone_parent")
	_check((doc.rig_system.get_rig(object_id).get("bones", []) as Array).size() == bones_before, "imported bone structure stays unchanged")

	# The tree disables structural actions with a concrete reason.
	var panel = RigPanelScript.new()
	panel.name = "ImportedRigPanel"
	add_child(panel)
	panel.setup(doc)
	await get_tree().process_frame
	var tree = panel.find_child("BoneTree", true, false)
	_check(tree != null, "the imported rig tree builds")
	if tree != null:
		var add_button: Button = tree.find_child("AddBoneButton", true, false)
		var rename_button: Button = tree.find_child("RenameBoneButton", true, false)
		var reparent_button: Button = tree.find_child("ReparentBoneButton", true, false)
		var delete_button: Button = tree.find_child("DeleteBoneButton", true, false)
		_check(add_button != null and add_button.disabled, "the bone tree disables Add bone for an imported rig")
		_check(rename_button != null and rename_button.disabled, "the bone tree disables Rename for an imported rig")
		_check(reparent_button != null and reparent_button.disabled, "the bone tree disables Reparent for an imported rig")
		_check(delete_button != null and delete_button.disabled, "the bone tree disables Delete for an imported rig")
		var message: Label = tree.find_child("BoneTreeMessage", true, false)
		_check(message != null and message.text.contains("Imported"), "the bone tree explains the imported lock")
		if add_button != null:
			add_button.pressed.emit()
			_check((doc.rig_system.get_rig(object_id).get("bones", []) as Array).size() == bones_before, "pressing Add bone on an imported rig changes nothing")
	panel.queue_free()
	doc.queue_free()


# -------------------------------------------------------------------------
# C2c — glTF external buffers and textures
# -------------------------------------------------------------------------

const GLTF_MISSING := "This .gltf references files that are not next to it. Move the .gltf, its .bin and its textures into one folder, or export a .glb."
const GLTF_ESCAPE := "This .gltf references a file outside its folder. Export it as a .glb or keep every file in one folder."


func _test_gltf_external_buffers() -> void:
	print("RIG STEP: glTF external resources")
	var source_dir := _tmp_dir.path_join("gltf_source")
	_rmrf(source_dir)
	DirAccess.make_dir_recursive_absolute(source_dir)
	var bin_bytes := _gltf_bin_bytes()

	var valid_path := source_dir.path_join("mesh.gltf")
	_write_bytes(valid_path, _gltf_json("mesh.bin", true).to_utf8_buffer())
	_write_bytes(source_dir.path_join("mesh.bin"), bin_bytes)
	var valid: Dictionary = Store.import_model(valid_path, _tmp_dir, "Tri")
	_check(bool(valid.get("ok", false)), "a .gltf with its .bin imports")
	var rel_path := str(valid.get("rel_path", ""))
	_check(rel_path == "models/mesh/mesh.gltf", "the .gltf keeps a per-model folder: %s" % rel_path)
	_check(FileAccess.file_exists(_tmp_dir.path_join(rel_path)), "the copied .gltf exists in the project")
	_check(FileAccess.file_exists(_tmp_dir.path_join("models/mesh/mesh.bin")), "the sibling .bin is copied next to the .gltf")
	var copied: Array = _list_files(_tmp_dir.path_join("models/mesh"))
	_check(copied.size() == 2, "a data: URI is skipped and creates no file: %s" % str(copied))

	var doc := _new_doc("glTF Import")
	var object_id: String = doc.add_imported(rel_path, "Tri")
	var generated := _find_mesh_instance(doc.nodes.get(object_id))
	_check(generated != null and generated.mesh != null, "the imported .gltf spawns a node with a real mesh")
	doc.queue_free()

	var missing_path := source_dir.path_join("missing.gltf")
	_write_bytes(missing_path, _gltf_json("missing.bin", false).to_utf8_buffer())
	var missing: Dictionary = Store.import_model(missing_path, _tmp_dir, "Missing")
	_check(not bool(missing.get("ok", true)), "a .gltf with a missing sibling is rejected")
	_check(str(missing.get("error", "")) == GLTF_MISSING, "the missing-sibling refusal is exact")
	_check(not DirAccess.dir_exists_absolute(_tmp_dir.path_join("models/missing")), "a rejected import leaves no partial model folder")

	var escape_path := source_dir.path_join("escape.gltf")
	_write_bytes(escape_path, _gltf_json("../escape.bin", false).to_utf8_buffer())
	_write_bytes(_tmp_dir.path_join("escape.bin"), bin_bytes)
	var escaped: Dictionary = Store.import_model(escape_path, _tmp_dir, "Escape")
	_check(not bool(escaped.get("ok", true)), "a path that escapes the source folder is rejected")
	_check(str(escaped.get("error", "")) == GLTF_ESCAPE, "the escaping-path refusal is exact")
	_check(not DirAccess.dir_exists_absolute(_tmp_dir.path_join("models/escape")), "an escaping import writes nothing")

	var glb_path := source_dir.path_join("cube.glb")
	_write_bytes(glb_path, _glb_bytes(_gltf_glb_json()))
	var glb: Dictionary = Store.import_model(glb_path, _tmp_dir, "Cube")
	_check(bool(glb.get("ok", false)) and str(glb.get("extension", "")) == "glb", "a .glb still imports unchanged")

	var obj_path := source_dir.path_join("triangle.obj")
	_write_bytes(obj_path, "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n".to_utf8_buffer())
	var obj: Dictionary = Store.import_model(obj_path, _tmp_dir, "Triangle")
	_check(bool(obj.get("ok", false)) and str(obj.get("extension", "")) == "obj", "an .obj still imports unchanged")
	_rmrf(source_dir)


func _gltf_json(buffer_uri: String, include_data_image: bool = false) -> String:
	var data := {
		"asset": {"version": "2.0"},
		"scene": 0,
		"scenes": [{"nodes": [0]}],
		"nodes": [{"mesh": 0}],
		"meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1, "mode": 4}]}],
		"buffers": [{"uri": buffer_uri, "byteLength": 42}],
		"bufferViews": [
			{"buffer": 0, "byteOffset": 0, "byteLength": 36, "target": 34962},
			{"buffer": 0, "byteOffset": 36, "byteLength": 6, "target": 34963},
		],
		"accessors": [
			{
				"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
				"min": [0, 0, 0], "max": [1, 1, 0],
			},
			{"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"},
		],
	}
	if include_data_image:
		data["images"] = [{
			"uri": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
		}]
	return JSON.stringify(data)


func _gltf_glb_json() -> Dictionary:
	var data: Dictionary = JSON.parse_string(_gltf_json("", false))
	var buffer: Dictionary = (data["buffers"] as Array)[0]
	buffer.erase("uri")
	buffer["byteLength"] = 42
	return data


func _gltf_bin_bytes() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(42)
	var positions := [
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
	]
	for i in range(positions.size()):
		var p: Vector3 = positions[i]
		bytes.encode_float(i * 12, p.x)
		bytes.encode_float(i * 12 + 4, p.y)
		bytes.encode_float(i * 12 + 8, p.z)
	bytes.encode_u16(36, 0)
	bytes.encode_u16(38, 1)
	bytes.encode_u16(40, 2)
	return bytes


func _glb_bytes(json_data: Dictionary) -> PackedByteArray:
	var json_bytes := JSON.stringify(json_data).to_utf8_buffer()
	while json_bytes.size() % 4 != 0:
		json_bytes.append(0x20)
	var bin_bytes := _gltf_bin_bytes()
	while bin_bytes.size() % 4 != 0:
		bin_bytes.append(0)
	var stream := StreamPeerBuffer.new()
	stream.big_endian = false
	stream.put_data("glTF".to_utf8_buffer())
	stream.put_u32(2)
	stream.put_u32(12 + 8 + json_bytes.size() + 8 + bin_bytes.size())
	stream.put_u32(json_bytes.size())
	stream.put_u32(0x4E4F534A)
	stream.put_data(json_bytes)
	stream.put_u32(bin_bytes.size())
	stream.put_u32(0x004E4942)
	stream.put_data(bin_bytes)
	return stream.data_array


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(bytes)
	file.close()


func _list_files(path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	for name in dir.get_files():
		out.append(name)
	return out


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node == null:
		return null
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null


# -------------------------------------------------------------------------
# C2d — FBX guidance and skeleton adoption notice
# -------------------------------------------------------------------------

func _test_fbx_and_adoption() -> void:
	print("RIG STEP: FBX and adoption notice")
	var copy: Dictionary = EditorAppScript.fbx_conversion_copy()
	_check(str(copy.get("title", "")) == "FBX needs a conversion", "the FBX sheet title is exact")
	_check(str(copy.get("body", "")) == "Godot's FBX importer only exists in the editor, so it cannot run on Android. Convert the model to glTF 2.0 first.", "the FBX sheet body is exact")
	var steps: Array = copy.get("steps", [])
	_check(steps == [
		"Open the model in Blender.",
		"File → Export → glTF 2.0.",
		"Choose glTF Binary (.glb).",
		"Import the .glb in Kinema.",
	], "the FBX sheet lists the four conversion steps")
	var actions: Array = copy.get("actions", [])
	_check(actions.size() == 2, "the FBX sheet has two actions")
	if actions.size() == 2:
		_check(str((actions[0] as Dictionary).get("text", "")) == "Choose another file" and bool((actions[0] as Dictionary).get("primary", false)), "Choose another file is the primary FBX action")
		_check(str((actions[1] as Dictionary).get("text", "")) == "Cancel" and not bool((actions[1] as Dictionary).get("primary", true)), "Cancel closes the FBX sheet")

	var filters: PackedStringArray = EditorAppScript.model_picker_filters()
	var joined := " ".join(filters)
	_check(joined.contains("*.fbx"), "the model picker offers .fbx for the conversion sheet")
	_check(joined.contains("*.glb") and joined.contains("*.gltf") and joined.contains("*.obj"), "the model picker keeps glTF and OBJ")

	var fbx_path := _tmp_dir.path_join("x.fbx")
	_write_bytes(fbx_path, "Kaydara FBX Binary  \n".to_utf8_buffer())
	var fbx: Dictionary = Store.import_model(fbx_path, _tmp_dir, "Fbx")
	_check(not bool(fbx.get("ok", true)), "Store.import_model still refuses FBX")
	_check(str(fbx.get("error", "")) == "FBX needs an editor-side importer that Godot only ships in the editor. Export the model as GLB or OBJ instead.", "the FBX refusal keeps its existing reason")

	_check(EditorAppScript.rig_adopted_toast(7) == "Skeleton detected · 7 bones · Pose mode is ready.", "the adoption toast copy is exact")

	# Fixtures are exported with the engine's own writer so the test exercises
	# a real imported skeleton, not a hand-built scene.
	var fixture_dir := _tmp_dir.path_join("fixtures")
	_rmrf(fixture_dir)
	DirAccess.make_dir_recursive_absolute(fixture_dir)

	var skinned_scene := _skinned_fixture_scene()
	var skinned_path := fixture_dir.path_join("skinned.glb")
	_check(_write_scene_fixture(skinned_path, skinned_scene), "the skinned GLB fixture is written")
	var skinned: Dictionary = Store.import_model(skinned_path, _tmp_dir, "Skinned")
	_check(bool(skinned.get("ok", false)), "the skinned GLB fixture imports")

	var doc := _new_doc("Adoption Notice")
	var emissions: Array = []
	doc.rig_adopted.connect(func(object_id: String, bone_count: int) -> void:
		emissions.append({"id": object_id, "bones": bone_count}))
	var skinned_id: String = doc.add_imported(str(skinned.get("rel_path", "")), "Skinned")
	_check(emissions.size() == 1, "importing a skinned GLB emits rig_adopted once")
	if emissions.size() == 1:
		_check(str((emissions[0] as Dictionary).get("id", "")) == skinned_id, "the adoption signal names the imported object")
		_check(int((emissions[0] as Dictionary).get("bones", 0)) == 2, "the adoption signal reports the real bone count")

	var data: Dictionary = doc.to_data()
	var loaded := _new_doc("Adoption Reload")
	var reload_emissions := [0]
	loaded.rig_adopted.connect(func(_object_id: String, _bone_count: int) -> void:
		reload_emissions[0] += 1)
	loaded.load_project(data, _tmp_dir)
	_check(int(reload_emissions[0]) == 0, "loading a saved project does not emit rig_adopted")
	_check(not loaded.rig_system.get_rig(skinned_id).is_empty(), "the loaded project keeps the adopted rig")

	var armature_scene := _skinned_fixture_scene()
	var armature_path := fixture_dir.path_join("armature.gltf")
	_check(_write_scene_fixture(armature_path, armature_scene), "the armature-only glTF fixture is written")
	_strip_mesh_from_gltf(armature_path)
	var armature: Dictionary = Store.import_model(armature_path, _tmp_dir, "Armature")
	_check(bool(armature.get("ok", false)), "the armature-only glTF fixture imports")
	var armature_emissions: Array = []
	doc.rig_adopted.connect(func(_object_id: String, bone_count: int) -> void:
		armature_emissions.append(bone_count))
	doc.add_imported(str(armature.get("rel_path", "")), "Armature")
	_check(armature_emissions == [2], "an armature-only glTF emits rig_adopted once with its bone count")

	var mesh_only_path := fixture_dir.path_join("plain.glb")
	_write_bytes(mesh_only_path, _glb_bytes(_gltf_glb_json()))
	var plain: Dictionary = Store.import_model(mesh_only_path, _tmp_dir, "Plain")
	_check(bool(plain.get("ok", false)), "the mesh-only fixture imports")
	var plain_emissions := [0]
	doc.rig_adopted.connect(func(_object_id: String, _bone_count: int) -> void:
		plain_emissions[0] += 1)
	doc.add_imported(str(plain.get("rel_path", "")), "Plain")
	_check(int(plain_emissions[0]) == 0, "an import with no skeleton emits nothing")

	doc.queue_free()
	loaded.queue_free()


func _skinned_fixture_scene() -> Node3D:
	var root := Node3D.new()
	root.name = "SkinnedFixture"
	var skeleton := _fixture_skeleton()
	root.add_child(skeleton)
	var mesh := MeshInstance3D.new()
	mesh.name = "Body"
	mesh.mesh = BoxMesh.new()
	root.add_child(mesh)
	mesh.skin = skeleton.create_skin_from_rest_transforms()
	mesh.skeleton = mesh.get_path_to(skeleton)
	return root


func _strip_mesh_from_gltf(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	for key in ["meshes", "materials", "textures", "images", "samplers"]:
		data.erase(key)
	for node in data.get("nodes", []):
		if node is Dictionary:
			(node as Dictionary).erase("mesh")
	_write_bytes(path, JSON.stringify(data).to_utf8_buffer())


func _fixture_skeleton() -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	skeleton.add_bone("Hip")
	skeleton.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	skeleton.add_bone("Knee")
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0)))
	skeleton.reset_bone_poses()
	return skeleton


func _write_scene_fixture(path: String, scene: Node) -> bool:
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_scene(scene, state)
	if err == OK:
		err = gltf.write_to_filesystem(state, path)
	scene.free()
	return err == OK


# -------------------------------------------------------------------------
# C1/C2/C3/C4 — UI
# -------------------------------------------------------------------------

func _test_ui() -> void:
	print("RIG STEP: UI")
	var doc := _new_doc("Rig UI")
	var rs = doc.rig_system
	var rig_id := _make_chain_rig(doc)
	var mesh_id: String = doc.add_primitive("box", Vector3(0, 0.5, 0))
	var target_id: String = doc.add_empty(Vector3(0.8, 0.6, 0))
	rs.add_ik_chain(rig_id, "Root", "Spine", target_id)
	rs.set_active_rig(rig_id)
	var panel = RigPanelScript.new()
	panel.name = "RigPanel"
	add_child(panel)
	panel.setup(doc)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(panel.is_inside_tree(), "the rig panel builds")
	var tree = panel.find_child("BoneTree", true, false)
	_check(tree != null, "the rig tab contains a bone tree")
	_check(tree != null and tree.get_bone_rows().size() == 2, "the bone tree lists both bones")
	if tree != null:
		var row: Button = tree.get_bone_rows()[0]
		_check(row != null and row.custom_minimum_size.y >= 43.5, "bone rows are 44 dp")
		_check(tree.indent_for_depth(2) == 24, "bone rows indent 12 dp per depth")
		var add_button: Button = tree.find_child("AddBoneButton", true, false)
		_check(add_button != null and add_button.custom_minimum_size.y >= 43.5, "the add-bone control is 44 dp")
		if add_button != null:
			add_button.pressed.emit()
			await get_tree().process_frame
			_check(rs.get_rig(rig_id).get("bones", []).size() == 3, "the add-bone control adds a child bone")

	# Bone inspector.
	var inspector = panel.find_child("BoneInspector", true, false)
	_check(inspector != null, "the rig tab contains a bone inspector")
	var length_field = panel.find_child("BoneLengthField", true, false)
	_check(length_field != null and length_field.custom_minimum_size.y >= 43.5, "the bone length field is 44 dp")
	var influence_field = panel.find_child("BoneInfluenceField", true, false)
	_check(influence_field != null, "the bone inspector exposes influence_scale")
	_check(panel.find_child("RebindNote", true, false) != null, "the bind section explains that influence changes need Rebind")

	# Bind UI.
	var picker: OptionButton = panel.find_child("BindMeshPicker", true, false)
	_check(picker != null, "the bind section has a mesh picker")
	var mesh_item := -1
	if picker != null:
		for i in range(picker.item_count):
			if str(picker.get_item_metadata(i)) == mesh_id:
				mesh_item = i
		if mesh_item >= 0:
			picker.select(mesh_item)
			picker.item_selected.emit(mesh_item)
	var bind_button: Button = panel.find_child("BindButton", true, false)
	_check(bind_button != null, "the bind section has a Bind button")
	_check(panel.bind_selected_mesh() != "", "the Bind button starts a real job")
	for _i in 30:
		panel.poll_bind_once()
		await get_tree().process_frame
	var summary: Label = panel.find_child("BindSummary", true, false)
	_check(summary != null and summary.text.contains("Bound"), "the bind summary reports the bound vertex count")
	_check(summary != null and summary.text.contains("influences"), "the bind summary reports influences")

	# Pose UI.
	var pose_panel = panel.find_child("PosePanel", true, false)
	_check(pose_panel != null, "the rig tab contains a pose panel")
	_check(pose_panel.columns_for_width(412.0) == 2, "the pose grid is two columns on compact")
	_check(pose_panel.columns_for_width(1024.0) == 3, "the pose grid is three columns on studio")
	var pose_name: LineEdit = panel.find_child("PoseNameField", true, false)
	var save_pose: Button = panel.find_child("SavePoseButton", true, false)
	_check(pose_name != null and save_pose != null, "the pose panel has a name field and Save pose")
	if pose_name != null and save_pose != null:
		pose_name.text = "T-Pose"
		save_pose.pressed.emit()
		await get_tree().process_frame
		_check(rs.get_rig(rig_id).get("poses", []).size() == 1, "Save pose adds a pose")
		_check(pose_panel.get_pose_chips().size() == 1, "the pose panel renders one chip")
	_check(pose_panel.find_child("PoseEmpty", true, false) == null or not pose_panel.find_child("PoseEmpty", true, false).visible, "the pose empty state hides once a pose exists")

	# IK UI.
	var ik_panel = panel.find_child("IKPanel", true, false)
	_check(ik_panel != null, "the rig tab contains an IK panel")
	_check(ik_panel.get_chain_rows().size() == 1, "the IK panel lists the chain")
	_check(ik_panel.find_child("AddChainButton", true, false) != null, "the IK panel has an Add chain control")
	_check(ik_panel.find_child("BakeIKButton", true, false) != null, "the IK panel has a Bake control")
	_check(panel.find_child("KeyBoneButton", true, false) != null, "the rig tab has a Key bone control")
	_check(panel.find_child("KeyPoseButton", true, false) != null, "the rig tab has a Key pose control")

	# Every interactive control clears the touch floor.
	var short := _short_controls(panel)
	_check(short.is_empty(), "every rig-tab control is at least 44 dp: %s" % str(short))
	panel.queue_free()

	# Empty state.
	var empty_doc := _new_doc("Rig Empty")
	var empty_panel = RigPanelScript.new()
	add_child(empty_panel)
	empty_panel.setup(empty_doc)
	await get_tree().process_frame
	_check(empty_panel.empty_state_visible(), "the rig tab shows an empty state when no rig exists")
	var add_rig: Button = empty_panel.find_child("AddRigButton", true, false)
	_check(add_rig != null and add_rig.custom_minimum_size.y >= 43.5, "the empty state offers a 44 dp Add rig action")
	if add_rig != null:
		add_rig.pressed.emit()
		await get_tree().process_frame
		_check(empty_doc.rig_system.rig_ids().size() == 1, "Add rig creates the first rig")
	empty_panel.queue_free()
	doc.queue_free()
	empty_doc.queue_free()


func _short_controls(root: Node) -> Array[String]:
	var out: Array[String] = []
	var nodes: Array[Node] = [root]
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()
		for child in node.get_children():
			nodes.append(child)
		if node is Button or node is LineEdit or node is OptionButton or node is SpinBox:
			var control := node as Control
			if control.is_visible_in_tree() and control.custom_minimum_size.y < 43.5 and control.custom_minimum_size.y > 0.0:
				out.append("%s(%s)" % [control.name, str(control.custom_minimum_size.y)])
			elif control.is_visible_in_tree() and control.custom_minimum_size.y == 0.0 and control.get_combined_minimum_size().y < 43.5:
				out.append("%s(auto=%s)" % [control.name, str(control.get_combined_minimum_size().y)])
	return out


# -------------------------------------------------------------------------
# C5 — rig overlay
# -------------------------------------------------------------------------

func _test_overlay() -> void:
	print("RIG STEP: overlay")
	var doc := _new_doc("Overlay Test")
	var rs = doc.rig_system
	var rig_id := _make_chain_rig(doc)
	var view := FakeView.new()
	add_child(view)
	var overlay = RigOverlayScript.new()
	overlay.name = "RigOverlay"
	add_child(overlay)
	overlay.setup(doc, view, rs)
	overlay.set_rig(rig_id)
	overlay.set_enabled(false)
	await get_tree().process_frame
	_check(overlay.mouse_filter == Control.MOUSE_FILTER_PASS, "the overlay passes input through when rig mode is off")
	var skel := _skeleton(doc, rig_id)
	var head := skel.to_global(skel.get_bone_global_pose(0).origin)
	var screen := view.world_to_screen(head)
	_check(overlay.bone_at(screen) == "", "a disabled overlay does not hit-test bones")
	overlay.set_enabled(true)
	await get_tree().process_frame
	_check(overlay.mouse_filter == Control.MOUSE_FILTER_STOP, "the overlay captures input in rig mode")
	_check(overlay.bone_at(screen) == "Root", "the overlay hit-tests the nearest bone within 22 dp")
	var far := screen + Vector2(300, 300)
	_check(overlay.bone_at(far) == "", "the overlay rejects a tap outside the hit radius")
	_check(overlay.hit_radius() == 22.0, "the overlay hit radius is 22 dp")
	overlay.queue_free()
	view.queue_free()
	doc.queue_free()


## The rig object carries a transform: drawn bones and hit-testing must both
## go through the skeleton's global transform. An origin-only fixture hides
## this regression, so this test translates the rig.
func _test_overlay_hit_transform() -> void:
	print("RIG STEP: overlay hit transform")
	var doc := _new_doc("Overlay Transform")
	var rs = doc.rig_system
	var rig_id: String = rs.create_rig("Offset Rig", Vector3(2.0, 1.0, 0.0))
	var view := FakeView.new()
	add_child(view)
	var overlay = RigOverlayScript.new()
	add_child(overlay)
	overlay.setup(doc, view, rs)
	overlay.set_rig(rig_id)
	overlay.set_enabled(true)
	await get_tree().process_frame
	var skel := _skeleton(doc, rig_id)
	var head: Vector3 = skel.to_global(skel.get_bone_global_rest(0).origin)
	var screen: Vector2 = view.world_to_screen(head)
	_check(overlay.bone_at(screen) == "Root", "a translated rig still hit-tests its bone head")
	overlay.queue_free()
	view.queue_free()
	doc.queue_free()


# -------------------------------------------------------------------------
# C6 — octahedral bones and the touch toolbar
# -------------------------------------------------------------------------

func _test_octahedral_bones() -> void:
	print("RIG STEP: octahedral bones")
	var overlay = RigOverlayScript.new()
	add_child(overlay)
	await get_tree().process_frame
	var head := Vector2(100, 200)
	var tail := Vector2(200, 200)
	var width := 10.0
	var poly: PackedVector2Array = overlay.bone_polygon(head, tail, width)
	_check(poly.size() == 4, "bone_polygon returns exactly four points")
	if poly.size() == 4:
		_check(poly[0].distance_to(head) < 0.001, "the polygon starts at the bone head")
		_check(poly[2].distance_to(tail) < 0.001, "the polygon ends at the bone tail")
		_check(absf(absf(poly[1].y - head.y) - width * 0.2) < 0.001, "the first shoulder is 20% of the bone width off the axis")
		_check(absf(absf(poly[3].y - head.y) - width * 0.2) < 0.001, "the second shoulder is 20% of the bone width off the axis")
		_check((poly[1].y - head.y) * (poly[3].y - head.y) < 0.0, "the shoulders sit on opposite sides of the bone axis")
	_check(overlay.bone_color(true) == Kit.FOCUS_BRIGHT, "the active bone uses the focus color")
	_check(overlay.bone_color(false) == Kit.TEXT_MUTED, "inactive bones use the muted color")
	_check(overlay.edit_handle_radius() == 22.0, "the rest head and tail handles use a 22 dp touch radius")
	overlay.queue_free()


func _test_rig_toolbar() -> void:
	print("RIG STEP: rig context controls")
	var original_window := get_window().size
	get_window().size = Vector2i(915, 412)
	await get_tree().process_frame
	var packed: PackedScene = load("res://src/app/main.tscn")
	var main: Control = packed.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame
	Prefs.set_value("editor.workspace", "scene")
	main._on_new_project_requested("Rig context suite", "blank")
	for _i in 5:
		await get_tree().process_frame
	var editor = main._editor
	_check(editor != null, "the editor opens for the rig context suite")
	if editor == null:
		main.queue_free()
		get_window().size = original_window
		await get_tree().process_frame
		return
	var doc = editor.doc
	var rig_id := _make_chain_rig(doc)
	_check(rig_id != "", "the suite creates an active rig")
	editor.set_workspace("rig")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor.workspace() == "rig", "the Rig workspace is active")

	var pose_button: Button = editor._context_bar.action_button("pose")
	var edit_button: Button = editor._context_bar.action_button("edit")
	_check(pose_button != null and edit_button != null,
		"the context row has Pose and Edit segments")
	if pose_button != null and edit_button != null:
		_check(pose_button.custom_minimum_size.y >= 43.5
			and pose_button.size.y >= 43.5, "the Pose segment is a 44 dp target")
		_check(edit_button.custom_minimum_size.y >= 43.5
			and edit_button.size.y >= 43.5, "the Edit segment is a 44 dp target")
		_check(pose_button.has_theme_stylebox_override("normal"),
			"Pose starts with the toggle fill")
		edit_button.pressed.emit()
		await get_tree().process_frame
		_check(editor._rig_overlay.mode() == "edit", "Edit puts the overlay in edit mode")
		_check(edit_button.has_theme_stylebox_override("normal")
			and not pose_button.has_theme_stylebox_override("normal"),
			"Edit moves the rig-mode toggle fill")
		pose_button.pressed.emit()
		await get_tree().process_frame
		_check(editor._rig_overlay.mode() == "pose", "Pose puts the overlay back in pose mode")
		_check(pose_button.has_theme_stylebox_override("normal")
			and not edit_button.has_theme_stylebox_override("normal"),
			"Pose moves the rig-mode toggle fill back")

	var rotate_button: Button = editor._context_bar.action_button("rig_rotate")
	var move_button: Button = editor._context_bar.action_button("rig_move")
	_check(rotate_button != null and move_button != null,
		"the context row has Rotate and Move transform modes")
	if rotate_button != null and move_button != null:
		_check(rotate_button.custom_minimum_size == Vector2(44, 44),
			"Rotate is a 44x44 target")
		_check(move_button.custom_minimum_size == Vector2(44, 44),
			"Move is a 44x44 target")
		move_button.pressed.emit()
		await get_tree().process_frame
		_check(editor._rig_overlay.transform_mode() == "move",
			"Move switches the overlay transform mode")
		rotate_button.pressed.emit()
		await get_tree().process_frame
		_check(editor._rig_overlay.transform_mode() == "rotate",
			"Rotate switches the overlay transform mode back")

	var axis_button: Button = editor._context_bar.action_button("rig_axis")
	_check(axis_button != null, "the context row has the axis control")
	if axis_button != null:
		_check(editor._rig_overlay.transform_mode() == "rotate",
			"the rig transform defaults to Rotate")
		_check(editor._rig_overlay.axis_mode() == "free" and axis_button.text == "Free",
			"the rig axis defaults to Free")
		_check(axis_button.custom_minimum_size.y >= 43.5
			and axis_button.size.y >= 43.5, "the axis control is a 44 dp target")
		axis_button.pressed.emit()
		await get_tree().process_frame
		var axis_menu = editor._rig_axis_menu
		_check(axis_menu.is_open(), "the axis control opens its menu")
		for axis in ["free", "x", "y", "z"]:
			var row: Button = axis_menu.row_button(axis)
			_check(row != null and row.custom_minimum_size.y >= 43.5,
				"the axis menu has a 44 dp %s row" % axis)
		axis_menu.row_button("x").pressed.emit()
		await get_tree().process_frame
		_check(editor._rig_overlay.axis_mode() == "x" and axis_button.text == "X",
			"X sets the rotation axis and updates the control")
		axis_button.pressed.emit()
		await get_tree().process_frame
		axis_menu.row_button("free").pressed.emit()
		await get_tree().process_frame
		_check(editor._rig_overlay.axis_mode() == "free" and axis_button.text == "Free",
			"Free restores the free rotation axis")

	var add_button: Button = editor._context_bar.action_button("rig_add")
	var done_button: Button = editor._context_bar.action_button("rig_done")
	_check(add_button != null and done_button != null,
		"the context row has Add bone and Done")
	if add_button != null:
		var before: int = (doc.rig_system.get_rig(rig_id)["bones"] as Array).size()
		add_button.pressed.emit()
		await get_tree().process_frame
		_check((doc.rig_system.get_rig(rig_id)["bones"] as Array).size() == before + 1,
			"Add bone really extrudes a bone")
	if edit_button != null:
		doc.rig_system.get_rig(rig_id)["imported"] = true
		editor._sync_context_state()
		await get_tree().process_frame
		_check(edit_button.disabled, "an imported rig disables the Edit segment")
		_check(edit_button.tooltip_text ==
			"Imported skeleton: rest editing is locked.",
			"the disabled Edit segment states the imported reason")
		doc.rig_system.get_rig(rig_id)["imported"] = false
		editor._sync_context_state()
		await get_tree().process_frame
		_check(not edit_button.disabled, "leaving an imported rig re-enables Edit")
	if done_button != null:
		done_button.pressed.emit()
		await get_tree().process_frame
		_check(editor.workspace() == "scene", "Done returns the workbench to Scene")
		_check(not editor._rig_mode and not editor._rig_overlay.is_enabled(),
			"Done disables the rig overlay")

	_check(editor.get("_rig_toolbar") == null, "the editor has no floating rig toolbar")
	_check(not ResourceLoader.exists("res://src/ui/rig_toolbar.gd"),
		"the floating rig toolbar script is gone")

	if editor.doc.is_playing:
		editor.doc.pause()
	var project_id: String = editor.doc.project_id
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


# -------------------------------------------------------------------------
# C7 — Pose/Edit modes and rest editing
# -------------------------------------------------------------------------

func _test_viewport_modes() -> void:
	print("RIG STEP: viewport modes")
	var doc := _new_doc("Viewport Modes")
	var rs = doc.rig_system
	var rig_id := _make_chain_rig(doc)
	rs.set_active_bone(rig_id, "Root")
	var view := FakeView.new()
	add_child(view)
	var overlay = RigOverlayScript.new()
	add_child(overlay)
	overlay.setup(doc, view, rs)
	overlay.set_rig(rig_id)
	overlay.set_enabled(true)
	await get_tree().process_frame
	_check(overlay.mode() == "pose", "rig mode defaults to Pose")
	_check(not overlay.is_edit_mode(), "the overlay starts in pose mode")
	overlay.set_mode("edit")
	_check(overlay.is_edit_mode(), "Edit switches the overlay to edit mode")
	overlay.set_mode("pose")
	_check(not overlay.is_edit_mode(), "Pose switches the overlay back")

	# Drag the rest head: one undo entry for the whole gesture.
	overlay.set_mode("edit")
	var skel := _skeleton(doc, rig_id)
	var root_index := skel.find_bone("Root")
	var head_world: Vector3 = skel.to_global(skel.get_bone_global_rest(root_index).origin)
	var head_screen: Vector2 = view.world_to_screen(head_world)
	var spine_before: Vector3 = rs.get_rig(rig_id)["bones"][1].get("p", Vector3.ZERO)
	overlay.press_at(head_screen)
	for i in range(5):
		overlay.drag_at(head_screen + Vector2(float(i + 1) * 6.0, 0.0))
	overlay.release_drag()
	var rig: Dictionary = rs.get_rig(rig_id)
	var root_rest: Vector3 = rig["bones"][0].get("p", Vector3.ZERO)
	_check(root_rest.x > 0.05, "dragging the head moves the rest bone")
	_check(absf(root_rest.y) < 0.0001 and absf(root_rest.z) < 0.0001, "the head drag follows the pointer plane")
	_check((rig["bones"][1].get("p", Vector3.ZERO) as Vector3).distance_to(spine_before) < 0.0001, "dragging the head leaves the other bones untouched")
	_check(doc.undo_label() == "Edit bone rest", "a rest drag is one undoable edit")
	doc.undo()
	_check((rs.get_rig(rig_id)["bones"][0].get("p", Vector3.ZERO) as Vector3).length() < 0.0001, "one undo restores the head after a multi-motion drag")

	# Drag the rest tail: aim the bone at the pointer and set its length.
	rs.set_bone_rest(rig_id, "Root", _rest(Vector3.ZERO, 1.0))
	skel = _skeleton(doc, rig_id)
	root_index = skel.find_bone("Root")
	var root_rest_xform: Transform3D = skel.get_bone_global_rest(root_index)
	var tail_world: Vector3 = skel.to_global(root_rest_xform.origin + root_rest_xform.basis.y.normalized() * 1.0)
	var tail_screen: Vector2 = view.world_to_screen(tail_world)
	var aim_screen: Vector2 = view.world_to_screen(Vector3(0.5, 1.0, 0.0))
	overlay.press_at(tail_screen)
	overlay.drag_at(aim_screen)
	overlay.release_drag()
	rig = rs.get_rig(rig_id)
	var tail_bone: Dictionary = rig["bones"][0]
	_check(absf(float(tail_bone.get("length", 0.0)) - Vector2(0.5, 1.0).length()) < 0.01, "dragging the tail sets the bone length from the head")
	var headless_aim: Vector3 = Basis(tail_bone.get("r", Quaternion.IDENTITY) as Quaternion) * Vector3.UP
	_check(headless_aim.dot(Vector3(0.5, 1.0, 0.0).normalized()) > 0.999, "dragging the tail aims the rest bone at the pointer")
	_check(doc.undo_label() == "Edit bone rest", "a tail drag is one undoable edit")
	doc.undo()
	var undone_tail: Dictionary = rs.get_rig(rig_id)["bones"][0]
	_check(_close(float(undone_tail.get("length", 0.0)), 1.0), "one undo restores the tail length")
	_check((undone_tail.get("r", Quaternion.IDENTITY) as Quaternion).angle_to(Quaternion.IDENTITY) < 0.001, "one undo restores the tail rotation")

	# Imported skeletons stay in Pose; rest editing is locked.
	var imported_doc := _new_doc("Viewport Imported")
	var object_id: String = imported_doc.add_empty(Vector3.ZERO)
	var node: Node3D = imported_doc.nodes[object_id]
	var imported_skel := Skeleton3D.new()
	imported_skel.name = "Skeleton3D"
	node.add_child(imported_skel)
	imported_skel.add_bone("Hip")
	imported_skel.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	imported_skel.reset_bone_poses()
	_check(imported_doc.rig_system.adopt_imported_skeleton(object_id, node), "the imported rig is adopted for the lock test")
	var imported_overlay = RigOverlayScript.new()
	add_child(imported_overlay)
	imported_overlay.setup(imported_doc, view, imported_doc.rig_system)
	imported_overlay.set_rig(object_id)
	imported_overlay.set_enabled(true)
	await get_tree().process_frame
	imported_overlay.set_mode("edit")
	_check(not imported_overlay.is_edit_mode(), "an imported skeleton refuses Edit mode")

	overlay.queue_free()
	imported_overlay.queue_free()
	view.queue_free()
	doc.queue_free()
	imported_doc.queue_free()


# -------------------------------------------------------------------------
# C8 — Add bone / extrude
# -------------------------------------------------------------------------

func _test_extrude() -> void:
	print("RIG STEP: extrude")
	var doc := _new_doc("Extrude Test")
	var rs = doc.rig_system
	var rig_id := _make_chain_rig(doc)
	var mesh_id: String = doc.add_primitive("box", Vector3(0, 0.5, 0))
	var job: String = rs.start_bind(rig_id, mesh_id, {})
	var state := {"state": "running", "progress": 0.0}
	var polls := 0
	while polls < 120 and str(state.get("state", "")) == "running":
		state = rs.poll_bind(job)
		polls += 1
	_check(str(state.get("state", "")) == "done", "the extrude bind completes")
	var skin_before: Dictionary = (rs.get_rig(rig_id).get("skins", []) as Array)[0]
	var pose_id: String = rs.save_pose(rig_id, "Extrude pose")
	var target_id: String = doc.add_empty(Vector3(1.2, 0.8, 0))
	var chain: String = rs.add_ik_chain(rig_id, "Root", "Spine", target_id)
	_check(pose_id != "" and chain != "", "the extrude test seeds a pose and an IK chain")
	rs.set_active_bone(rig_id, "Root")

	var created: String = rs.extrude_bone(rig_id, "Root")
	_check(created == "Bone 1", "extrude names the first added bone Bone 1")
	var rig: Dictionary = rs.get_rig(rig_id)
	var created_index := _bone_index(rig, created)
	_check(created_index >= 0, "extrude appends the bone to the rig")
	_check(created_index >= 0 and int(rig["bones"][created_index].get("parent", -1)) == _bone_index(rig, "Root"), "an extruded bone parents to the active bone")
	var root_index := _bone_index(rig, "Root")
	var root_global := _bone_global_rest(rig, root_index)
	var root_tail := root_global.origin + root_global.basis.y.normalized() * float(rig["bones"][root_index].get("length", 0.4))
	var created_global := _bone_global_rest(rig, created_index)
	_check(created_global.origin.distance_to(root_tail) < 0.001, "an extruded bone starts at the active tail")
	_check(str(rig.get("active_bone", "")) == created, "the new bone becomes active")
	_check(doc.undo_label() == "Add bone", "extrude is one undo entry")
	_check((rig.get("skins", []) as Array).size() == 1, "extrude keeps the existing skin")
	var skin_after: Dictionary = (rs.get_rig(rig_id).get("skins", []) as Array)[0]
	_check(str(skin_after.get("file", "")) == str(skin_before.get("file", "")), "extrude keeps the skin sidecar")
	var mesh_node: Node3D = doc.nodes.get(mesh_id)
	var mesh_instance := mesh_node.get_node_or_null("Mesh") as MeshInstance3D if mesh_node != null else null
	_check(mesh_instance != null and mesh_instance.skin != null, "extrude keeps the bound mesh skinned")
	_check((rs.get_rig(rig_id).get("poses", []) as Array).size() == 1, "extrude keeps the pose library")
	_check((rs.get_rig(rig_id).get("ik", []) as Array).size() == 1, "extrude keeps the IK chains")

	rs.set_active_bone(rig_id, created)
	var second: String = rs.extrude_bone(rig_id, created)
	_check(second == "Bone 2", "a second extrude increments the unique Bone N name")
	var second_rig: Dictionary = rs.get_rig(rig_id)
	var second_index := _bone_index(second_rig, second)
	_check(second_index >= 0 and int(second_rig["bones"][second_index].get("parent", -1)) == created_index, "a chained extrude parents to the new bone")

	var root_created: String = rs.extrude_bone(rig_id, "")
	_check(root_created == "Bone 3", "adding with no parent continues the unique name sequence")
	var root_index_added := _bone_index(rs.get_rig(rig_id), root_created)
	_check(root_index_added >= 0 and int(rs.get_rig(rig_id)["bones"][root_index_added].get("parent", 0)) == -1, "adding with no active bone creates a root bone")
	_check(str(rs.get_rig(rig_id).get("active_bone", "")) == root_created, "the root bone becomes active")
	var bones_before_undo: int = (rs.get_rig(rig_id).get("bones", []) as Array).size()
	doc.undo()
	_check((rs.get_rig(rig_id).get("bones", []) as Array).size() == bones_before_undo - 1, "one undo removes the extruded root bone")
	doc.queue_free()


func _capture_requested() -> bool:
	return OS.get_cmdline_user_args().has("--capture")


func _capture_visuals() -> void:
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	var doc := _new_doc("Rig Capture")
	var rs = doc.rig_system
	var rig_id := _make_chain_rig(doc)
	rs.set_bone_rest(rig_id, "Root", _rest(Vector3(-0.6, -0.2, 0), 1.0))
	rs.add_bone(rig_id, "Arm", "Spine", _rest(Vector3(0.7, 0.6, 0), 0.8))
	rs.set_active_bone(rig_id, "Spine")
	var stage := Control.new()
	stage.name = "CaptureStage"
	stage.size = Vector2(get_window().size)
	add_child(stage)
	var bg := ColorRect.new()
	bg.color = Kit.SURFACE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(bg)
	var view := FakeView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(view)
	var overlay = RigOverlayScript.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(overlay)
	overlay.setup(doc, view, rs)
	overlay.set_rig(rig_id)
	overlay.set_mode("pose")
	overlay.set_enabled(true)
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image != null:
		image.save_png(CAPTURE_DIR.path_join("rig-toolbar-bones-915x412.png"))
	overlay.set_mode("edit")
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var edit_image: Image = get_viewport().get_texture().get_image()
	if edit_image != null:
		edit_image.save_png(CAPTURE_DIR.path_join("rig-edit-handles-915x412.png"))
	stage.queue_free()
	doc.queue_free()
