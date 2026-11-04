extends RefCounted
## Rigging subsystem: skeleton model, distance skinning jobs, FABRIK IK and the
## pose library.
##
## Document owns one instance. `reset()` clears subsystem state; the object is
## never freed by `_clear_runtime()`. Bone keys always go through the Document
## contract, so there is exactly one animation store.

const Skinning = preload("res://src/core/skinning.gd")
const IkSolver = preload("res://src/core/ik_solver.gd")
const PoseLibrary = preload("res://src/core/pose_library.gd")
const ObjImporterScript = preload("res://src/core/obj_importer.gd")

const DEFAULT_BONE_LENGTH := 0.4
const MAX_BIND_VERTICES := Skinning.MAX_VERTICES

var _document = null
var _rigs: Array[Dictionary] = []
var _jobs: Dictionary = {}
var _next_rig := 1
var _next_job := 1
var _next_ik := 1
var _next_pose := 1
var _active_rig := ""
var _edit_depth := 0


func setup(document) -> void:
	_document = document


func reset() -> void:
	_rigs.clear()
	_jobs.clear()
	_next_rig = 1
	_next_job = 1
	_next_ik = 1
	_next_pose = 1
	_active_rig = ""
	_edit_depth = 0


# -------------------------------------------------------------------------
# Serialization
# -------------------------------------------------------------------------

func to_data() -> Dictionary:
	var out: Array = []
	for rig in _rigs:
		out.append(_rig_to_json(rig))
	return {"rigs": out}


func _rig_to_json(rig: Dictionary) -> Dictionary:
	var bones: Array = []
	for bone in rig.get("bones", []):
		bones.append({
			"name": str(bone.get("name", "")),
			"parent": int(bone.get("parent", -1)),
			"rest": {
				"p": PoseLibrary.vec3_to_array(bone.get("p", Vector3.ZERO)),
				"r": PoseLibrary.quat_to_array(bone.get("r", Quaternion.IDENTITY)),
				"s": PoseLibrary.vec3_to_array(bone.get("s", Vector3.ONE)),
			},
			"length": float(bone.get("length", DEFAULT_BONE_LENGTH)),
			"influence_scale": float(bone.get("influence_scale", 1.0)),
		})
	var skins: Array = []
	for skin in rig.get("skins", []):
		skins.append(skin.duplicate(true))
	var poses: Array = []
	for pose in rig.get("poses", []):
		poses.append({
			"id": str(pose.get("id", "")),
			"name": str(pose.get("name", "")),
			"bones": (pose.get("bones", {}) as Dictionary).duplicate(true),
			"root_position": PoseLibrary.vec3_to_array(PoseLibrary.array_to_vec3(pose.get("root_position", [0, 0, 0]))),
		})
	var current_pose: Dictionary = rig.get("pose", {})
	var node: Node3D = _document.nodes.get(str(rig.get("object_id", ""))) if _document != null else null
	if node != null:
		var skeleton := node.get_node_or_null("Skeleton3D") as Skeleton3D
		if skeleton != null:
			current_pose = PoseLibrary.capture(skeleton, node)
	return {
		"id": str(rig.get("id", "")),
		"object_id": str(rig.get("object_id", "")),
		"name": str(rig.get("name", "Rig")),
		"bones": bones,
		"skins": skins,
		"ik": (rig.get("ik", []) as Array).duplicate(true),
		"poses": poses,
		"pose": current_pose.duplicate(true),
		"active_bone": str(rig.get("active_bone", "")),
		"imported": bool(rig.get("imported", false)),
	}


func load_data(data: Dictionary, nodes: Dictionary) -> void:
	_rigs.clear()
	_jobs.clear()
	_next_rig = 1
	_next_job = 1
	_next_ik = 1
	_next_pose = 1
	_active_rig = ""
	for raw in data.get("rigs", []):
		if not raw is Dictionary:
			continue
		var rig := _rig_from_json(raw)
		if rig.is_empty():
			continue
		_rigs.append(rig)
		_bump_counters(rig)
		var node: Node3D = nodes.get(rig["object_id"])
		if node == null:
			continue
		_remove_fallback_visual(node)
		if bool(rig.get("imported", false)):
			if node.get_node_or_null("Skeleton3D") is Skeleton3D:
				_apply_all_skins(rig)
			else:
				_build_skeleton(rig, node)
		else:
			_remove_fallback_visual(node)
			_build_skeleton(rig, node)
		var pose: Dictionary = rig.get("pose", {})
		if not pose.is_empty():
			var skeleton := node.get_node_or_null("Skeleton3D") as Skeleton3D
			if skeleton != null:
				# Bone channels only: the document object's transform stays
				# authoritative on load. This runs inside the loading guard.
				PoseLibrary.apply_bones(skeleton, pose)
	if not _rigs.is_empty():
		_active_rig = str(_rigs[0]["object_id"])


func _rig_from_json(raw: Dictionary) -> Dictionary:
	var object_id := str(raw.get("object_id", ""))
	if object_id == "":
		return {}
	var bones: Array = []
	for raw_bone in raw.get("bones", []):
		if not raw_bone is Dictionary:
			continue
		var raw_rest: Dictionary = raw_bone.get("rest", {})
		bones.append({
			"name": str(raw_bone.get("name", "")),
			"parent": int(raw_bone.get("parent", -1)),
			"p": PoseLibrary.array_to_vec3(raw_rest.get("p", raw_bone.get("p", [0, 0, 0]))),
			"r": PoseLibrary.array_to_quat(raw_rest.get("r", raw_bone.get("r", [0, 0, 0, 1]))),
			"s": PoseLibrary.array_to_vec3(raw_rest.get("s", raw_bone.get("s", [1, 1, 1]))),
			"length": maxf(0.0001, float(raw_bone.get("length", DEFAULT_BONE_LENGTH))),
			"influence_scale": maxf(0.0, float(raw_bone.get("influence_scale", 1.0))),
		})
	if bones.is_empty():
		bones.append(_new_bone("Root", -1, Vector3.ZERO, DEFAULT_BONE_LENGTH))
	var ik: Array = []
	for raw_chain in raw.get("ik", []):
		if not raw_chain is Dictionary:
			continue
		ik.append({
			"id": str(raw_chain.get("id", "ik_%d" % (_next_ik + ik.size()))),
			"name": str(raw_chain.get("name", "IK")),
			"root": str(raw_chain.get("root", "")),
			"end": str(raw_chain.get("end", "")),
			"target_object_id": str(raw_chain.get("target_object_id", "")),
			"weight": clampf(float(raw_chain.get("weight", 1.0)), 0.0, 1.0),
			"iterations": IkSolver.clamp_iterations(int(raw_chain.get("iterations", 12))),
			"pole_angle": float(raw_chain.get("pole_angle", 0.0)),
			"enabled": bool(raw_chain.get("enabled", true)),
		})
	var poses: Array = []
	for raw_pose in raw.get("poses", []):
		if not raw_pose is Dictionary:
			continue
		var pose_bones: Dictionary = {}
		var source_bones: Dictionary = raw_pose.get("bones", {})
		for bone_name in source_bones.keys():
			var value: Variant = source_bones[bone_name]
			if value is Dictionary:
				pose_bones[str(bone_name)] = (value as Dictionary).duplicate(true)
			else:
				pose_bones[str(bone_name)] = {
					"r": PoseLibrary.quat_to_array(PoseLibrary.array_to_quat(value)),
				}
		poses.append({
			"id": str(raw_pose.get("id", "pose_%d" % (_next_pose + poses.size()))),
			"name": str(raw_pose.get("name", "Pose")),
			"bones": pose_bones,
			"root_position": PoseLibrary.array_to_vec3(raw_pose.get("root_position", [0, 0, 0])),
		})
	var active_bone := str(raw.get("active_bone", str(bones[0].get("name", ""))))
	return {
		"id": str(raw.get("id", "rig_%d" % _next_rig)),
		"object_id": object_id,
		"name": str(raw.get("name", "Rig")),
		"bones": bones,
		"skins": (raw.get("skins", []) as Array).duplicate(true),
		"ik": ik,
		"poses": poses,
		"pose": (raw.get("pose", {}) as Dictionary).duplicate(true),
		"active_bone": active_bone,
		"imported": bool(raw.get("imported", false)),
	}


func _bump_counters(rig: Dictionary) -> void:
	_next_rig = maxi(_next_rig, _suffix_number(str(rig.get("id", "")), "rig_") + 1)
	for chain in rig.get("ik", []):
		_next_ik = maxi(_next_ik, _suffix_number(str(chain.get("id", "")), "ik_") + 1)
	for pose in rig.get("poses", []):
		_next_pose = maxi(_next_pose, _suffix_number(str(pose.get("id", "")), "pose_") + 1)


func _suffix_number(value: String, prefix: String) -> int:
	if not value.begins_with(prefix):
		return 0
	return int(value.substr(prefix.length()))


# -------------------------------------------------------------------------
# Lifecycle hooks
# -------------------------------------------------------------------------

func on_object_spawned(obj: Dictionary, node: Node3D) -> void:
	if node == null:
		return
	if str(obj.get("kind", "")) == "rig":
		_remove_fallback_visual(node)
		var rig := _rig_for_object(str(obj.get("id", "")))
		if rig.is_empty():
			_ensure_skeleton(node)
		else:
			_build_skeleton(rig, node)


func on_object_properties(obj: Dictionary, node: Node3D) -> void:
	if node == null:
		return
	var id := str(obj.get("id", ""))
	for rig in _rigs:
		for skin in rig.get("skins", []):
			if str(skin.get("mesh_object_id", "")) != id:
				continue
			var rig_node: Node3D = _document.nodes.get(str(rig.get("object_id", "")))
			if rig_node != null:
				node.global_transform = rig_node.global_transform
			return


# -------------------------------------------------------------------------
# Rig CRUD
# -------------------------------------------------------------------------

func create_rig(name: String, at: Vector3) -> String:
	if _document == null:
		return ""
	_begin("Add Rig")
	var obj: Dictionary = _document._new_object_data("rig", name, at)
	_document.objects.append(obj)
	_document._spawn_object(obj)
	var object_id := str(obj.get("id", ""))
	var rig := _new_rig_record(object_id, str(obj.get("name", name)))
	_rigs.append(rig)
	_next_rig += 1
	_active_rig = object_id
	var node: Node3D = _document.nodes.get(object_id)
	if node != null:
		_build_skeleton(rig, node)
	_end()
	_document.set_selection(object_id)
	_emit_rigs()
	return object_id


func _new_rig_record(object_id: String, name: String) -> Dictionary:
	return {
		"id": "rig_%d" % _next_rig,
		"object_id": object_id,
		"name": name,
		"bones": [_new_bone("Root", -1, Vector3.ZERO, DEFAULT_BONE_LENGTH)],
		"skins": [],
		"ik": [],
		"poses": [],
		"pose": {},
		"active_bone": "Root",
		"imported": false,
	}


func _new_bone(name: String, parent: int, p: Vector3, length: float) -> Dictionary:
	return {
		"name": name,
		"parent": parent,
		"p": p,
		"r": Quaternion.IDENTITY,
		"s": Vector3.ONE,
		"length": maxf(0.0001, length),
		"influence_scale": 1.0,
	}


func delete_rig(object_id: String) -> bool:
	var rig := _rig_for_object(object_id)
	if rig.is_empty():
		return false
	_begin("Delete rig")
	for skin in (rig.get("skins", []) as Array).duplicate(true):
		_unbind_internal(rig, str(skin.get("mesh_object_id", "")))
	_remove_bone_tracks(object_id)
	_rigs.erase(rig)
	if _active_rig == object_id:
		_active_rig = str(_rigs[0]["object_id"]) if not _rigs.is_empty() else ""
	if _document != null and _document.nodes.has(object_id):
		_document.delete_object(object_id)
	_end()
	_emit_rigs()
	return true


func rig_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for rig in _rigs:
		out.append(str(rig.get("object_id", "")))
	return out


func get_rig(object_id: String) -> Dictionary:
	var rig := _rig_for_object(object_id)
	return rig


func active_rig_id() -> String:
	return _active_rig


func set_active_rig(object_id: String) -> void:
	if _rig_for_object(object_id).is_empty():
		return
	_active_rig = object_id
	var rig := _rig_for_object(object_id)
	_emit_selection(object_id, str(rig.get("active_bone", "")))


func _rig_for_object(object_id: String) -> Dictionary:
	for rig in _rigs:
		if str(rig.get("object_id", "")) == object_id:
			return rig
	return {}


# -------------------------------------------------------------------------
# Bones
# -------------------------------------------------------------------------

func add_bone(rig_id: String, name: String, parent: String, rest: Dictionary) -> int:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty() or bool(rig.get("imported", false)):
		return -1
	var clean := name.strip_edges()
	if clean == "" or _bone_index(rig, clean) >= 0:
		return -1
	var parent_index := -1
	if parent != "":
		parent_index = _bone_index(rig, parent)
		if parent_index < 0:
			return -1
	var normalized := _normalize_rest(rest, parent_index)
	_begin("Add bone")
	(rig["bones"] as Array).append(normalized.merged({"name": clean, "parent": parent_index}, true))
	_rebuild_skeleton(rig)
	_end()
	_emit_rigs()
	return (rig["bones"] as Array).size() - 1


## The next free `Bone N` name. The scan never advances a counter, so deleting
## a bone can never make a future add collide with an existing one.
func next_bone_name(rig_id: String) -> String:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty():
		return ""
	var number := 1
	while _bone_index(rig, "Bone %d" % number) >= 0:
		number += 1
	return "Bone %d" % number


## Extrude a new child at `parent`'s rest tail. An empty parent (or the missing
## active bone the viewport passes) adds a root. The new bone becomes active and
## the whole add is a single "Add bone" undo entry through add_bone.
func extrude_bone(rig_id: String, parent: String = "") -> String:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty() or bool(rig.get("imported", false)):
		return ""
	var parent_index := -1
	if parent != "":
		parent_index = _bone_index(rig, parent)
		if parent_index < 0:
			return ""
	var parent_global := Transform3D.IDENTITY
	var head := Vector3.ZERO
	if parent_index >= 0:
		parent_global = _bone_global_rest(rig, parent_index)
		var parent_length := float((rig["bones"] as Array)[parent_index].get("length", DEFAULT_BONE_LENGTH))
		head = parent_global.origin + parent_global.basis.y.normalized() * parent_length
	var local_origin := head if parent_index < 0 else parent_global.affine_inverse() * head
	var name := next_bone_name(rig_id)
	var index := add_bone(rig_id, name, parent, {
		"p": local_origin,
		"r": Quaternion.IDENTITY,
		"s": Vector3.ONE,
		"length": DEFAULT_BONE_LENGTH,
	})
	if index < 0:
		return ""
	set_active_bone(rig_id, name)
	return name


func _normalize_rest(rest: Dictionary, parent: int) -> Dictionary:
	return {
		"name": "",
		"parent": parent,
		"p": PoseLibrary.array_to_vec3(rest.get("p", [0, 0, 0])),
		"r": PoseLibrary.array_to_quat(rest.get("r", [0, 0, 0, 1])),
		"s": PoseLibrary.array_to_vec3(rest.get("s", [1, 1, 1])),
		"length": maxf(0.0001, float(rest.get("length", DEFAULT_BONE_LENGTH))),
		"influence_scale": maxf(0.0, float(rest.get("influence_scale", 1.0))),
	}


func remove_bone(rig_id: String, name: String) -> bool:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty() or bool(rig.get("imported", false)):
		return false
	var index := _bone_index(rig, name)
	if index < 0:
		return false
	var bones: Array = rig["bones"]
	for bone in bones:
		if int(bone.get("parent", -1)) == index:
			return false
	for skin in rig.get("skins", []):
		if (skin.get("bone_names", []) as Array).has(name):
			return false
	for chain in rig.get("ik", []):
		if str(chain.get("root", "")) == name or str(chain.get("end", "")) == name:
			return false
	for pose in rig.get("poses", []):
		if (pose.get("bones", {}) as Dictionary).has(name):
			return false
	_begin("Remove bone")
	bones.remove_at(index)
	for bone in bones:
		var parent := int(bone.get("parent", -1))
		if parent > index:
			bone["parent"] = parent - 1
	if str(rig.get("active_bone", "")) == name:
		rig["active_bone"] = str(bones[0].get("name", "")) if not bones.is_empty() else ""
	_rebuild_skeleton(rig)
	_end()
	_emit_rigs()
	return true


func set_bone_rest(rig_id: String, name: String, rest: Dictionary) -> void:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty() or bool(rig.get("imported", false)):
		return
	var bone := _bone(rig, name)
	if bone.is_empty():
		return
	var normalized := _normalize_rest(rest, int(bone.get("parent", -1)))
	_begin("Edit bone rest")
	bone["p"] = normalized["p"]
	bone["r"] = normalized["r"]
	bone["s"] = normalized["s"]
	bone["length"] = normalized["length"]
	_rebuild_skeleton(rig)
	_end()
	_emit_rigs()


func set_bone_parent(rig_id: String, name: String, parent: String) -> bool:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty() or bool(rig.get("imported", false)):
		return false
	var index := _bone_index(rig, name)
	if index < 0:
		return false
	var parent_index := -1
	if parent != "":
		parent_index = _bone_index(rig, parent)
		if parent_index < 0 or parent_index == index:
			return false
		if _is_descendant(rig, parent_index, index):
			return false
	var global_before := _bone_global_rest(rig, index)
	var parent_global := Transform3D.IDENTITY
	if parent_index >= 0:
		parent_global = _bone_global_rest(rig, parent_index)
	var local := parent_global.affine_inverse() * global_before
	var bone: Dictionary = (rig["bones"] as Array)[index]
	_begin("Reparent bone")
	bone["parent"] = parent_index
	bone["p"] = local.origin
	bone["r"] = local.basis.get_rotation_quaternion().normalized()
	bone["s"] = local.basis.get_scale()
	_sort_bones_parent_first(rig)
	_rebuild_skeleton(rig)
	_end()
	_emit_rigs()
	return true


func set_active_bone(rig_id: String, name: String) -> void:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty() or _bone_index(rig, name) < 0:
		return
	rig["active_bone"] = name
	_emit_selection(rig_id, name)


func set_bone_influence_scale(rig_id: String, bone_name: String, scale: float) -> void:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty():
		return
	var bone := _bone(rig, bone_name)
	if bone.is_empty():
		return
	_begin("Change bone influence")
	bone["influence_scale"] = maxf(0.0, scale)
	_end()
	_emit_rigs()


func rename_bone(rig_id: String, old_name: String, new_name: String) -> bool:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty() or bool(rig.get("imported", false)):
		return false
	var clean := new_name.strip_edges()
	if clean == "" or clean == old_name or _bone_index(rig, clean) >= 0:
		return false
	var bone := _bone(rig, old_name)
	if bone.is_empty():
		return false
	_begin("Rename bone")
	bone["name"] = clean
	if str(rig.get("active_bone", "")) == old_name:
		rig["active_bone"] = clean
	for skin in rig.get("skins", []):
		var names: Array = skin.get("bone_names", [])
		for i in range(names.size()):
			if str(names[i]) == old_name:
				names[i] = clean
	for chain in rig.get("ik", []):
		if str(chain.get("root", "")) == old_name:
			chain["root"] = clean
		if str(chain.get("end", "")) == old_name:
			chain["end"] = clean
	for pose in rig.get("poses", []):
		var pose_bones: Dictionary = pose.get("bones", {})
		if pose_bones.has(old_name):
			pose_bones[clean] = pose_bones[old_name]
			pose_bones.erase(old_name)
	_rename_bone_tracks(rig_id, old_name, clean)
	_rebuild_skeleton(rig)
	_end()
	_emit_rigs()
	return true


func _bone(rig: Dictionary, name: String) -> Dictionary:
	var index := _bone_index(rig, name)
	if index < 0:
		return {}
	return (rig["bones"] as Array)[index]


func _bone_index(rig: Dictionary, name: String) -> int:
	var bones: Array = rig.get("bones", [])
	for i in range(bones.size()):
		if str(bones[i].get("name", "")) == name:
			return i
	return -1


func _is_descendant(rig: Dictionary, candidate: int, ancestor: int) -> bool:
	var cursor := candidate
	var guard := 0
	while cursor >= 0 and guard < 256:
		if cursor == ancestor:
			return true
		cursor = int((rig["bones"] as Array)[cursor].get("parent", -1))
		guard += 1
	return false


func _sort_bones_parent_first(rig: Dictionary) -> void:
	var bones: Array = rig["bones"]
	var pending: Array[int] = []
	for i in range(bones.size()):
		pending.append(i)
	var order: Array[int] = []
	var done: Dictionary = {}
	while not pending.is_empty():
		var progressed := false
		for old_index in pending.duplicate():
			var parent := int(bones[old_index].get("parent", -1))
			if parent < 0 or done.has(parent):
				order.append(old_index)
				done[old_index] = true
				pending.erase(old_index)
				progressed = true
		if not progressed:
			order.append_array(pending)
			break
	var new_index: Dictionary = {}
	for i in range(order.size()):
		new_index[order[i]] = i
	var sorted: Array = []
	for old_index in order:
		var bone: Dictionary = (bones[old_index] as Dictionary).duplicate(true)
		var parent := int(bone.get("parent", -1))
		bone["parent"] = -1 if parent < 0 else int(new_index.get(parent, -1))
		sorted.append(bone)
	rig["bones"] = sorted


func _bone_global_rest(rig: Dictionary, index: int) -> Transform3D:
	var bones: Array = rig["bones"]
	if index < 0 or index >= bones.size():
		return Transform3D.IDENTITY
	var bone: Dictionary = bones[index]
	var local := Transform3D(
		Basis(bone.get("r", Quaternion.IDENTITY)).scaled(bone.get("s", Vector3.ONE)),
		bone.get("p", Vector3.ZERO))
	var parent := int(bone.get("parent", -1))
	if parent < 0 or parent >= index:
		return local
	return _bone_global_rest(rig, parent) * local


# -------------------------------------------------------------------------
# Skeleton build
# -------------------------------------------------------------------------

func _ensure_skeleton(node: Node3D) -> void:
	if node.get_node_or_null("Skeleton3D") is Skeleton3D:
		return
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	node.add_child(skeleton)


func _remove_fallback_visual(node: Node3D) -> void:
	for child in node.get_children():
		if child is Skeleton3D:
			continue
		if child.name == "Mesh" or child is MeshInstance3D:
			node.remove_child(child)
			child.queue_free()


func _build_skeleton(rig: Dictionary, node: Node3D) -> void:
	if node == null:
		return
	var existing := node.get_node_or_null("Skeleton3D") as Skeleton3D
	var saved_pose: Dictionary = {}
	if existing != null:
		for i in range(existing.get_bone_count()):
			var bone_name := existing.get_bone_name(i)
			saved_pose[bone_name] = {
				"p": existing.get_bone_pose_position(i),
				"r": existing.get_bone_pose_rotation(i),
				"s": existing.get_bone_pose_scale(i),
			}
		node.remove_child(existing)
		existing.queue_free()
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	node.add_child(skeleton)
	var bones: Array = rig.get("bones", [])
	for i in range(bones.size()):
		skeleton.add_bone(str(bones[i].get("name", "Bone%d" % i)))
	for i in range(bones.size()):
		var bone: Dictionary = bones[i]
		var parent := int(bone.get("parent", -1))
		if parent >= i:
			parent = -1
		skeleton.set_bone_parent(i, parent)
		var basis := Basis(bone.get("r", Quaternion.IDENTITY)).scaled(bone.get("s", Vector3.ONE))
		skeleton.set_bone_rest(i, Transform3D(basis, bone.get("p", Vector3.ZERO)))
	skeleton.reset_bone_poses()
	for bone_name in saved_pose.keys():
		var index := skeleton.find_bone(str(bone_name))
		if index < 0:
			continue
		var pose: Dictionary = saved_pose[bone_name]
		skeleton.set_bone_pose_position(index, pose["p"])
		skeleton.set_bone_pose_rotation(index, pose["r"])
		skeleton.set_bone_pose_scale(index, pose["s"])
	_apply_all_skins(rig)


func _rebuild_skeleton(rig: Dictionary) -> void:
	if _document == null:
		return
	var node: Node3D = _document.nodes.get(str(rig.get("object_id", "")))
	if node == null:
		return
	if bool(rig.get("imported", false)) and node.get_node_or_null("Skeleton3D") is Skeleton3D:
		_apply_all_skins(rig)
		return
	_build_skeleton(rig, node)


# -------------------------------------------------------------------------
# Bone tracks
# -------------------------------------------------------------------------

func _animations() -> Array:
	var out: Array = []
	if _document == null:
		return out
	if _document.animation != null:
		out.append(_document.animation)
	var system = _document.animation_system
	if system != null and system.has_method("clip_ids"):
		for clip_id in system.clip_ids():
			var animation = system.animation_for(clip_id)
			if animation != null and not out.has(animation):
				out.append(animation)
	return out


func _bone_track_prefix(object_id: String) -> String:
	var node: Node = _document.nodes.get(object_id)
	var node_name := str(node.name) if node != null else "Object_" + object_id
	return "%s/Skeleton3D:" % node_name


func _rename_bone_tracks(object_id: String, old_name: String, new_name: String) -> void:
	var prefix := _bone_track_prefix(object_id)
	var old_path := prefix + old_name
	var new_path := prefix + new_name
	for animation in _animations():
		for i in range(animation.get_track_count()):
			if str(animation.track_get_path(i)) == old_path:
				animation.track_set_path(i, NodePath(new_path))


func _remove_bone_tracks(object_id: String) -> void:
	var prefix := _bone_track_prefix(object_id)
	for animation in _animations():
		for i in range(animation.get_track_count() - 1, -1, -1):
			if str(animation.track_get_path(i)).begins_with(prefix):
				animation.track_remove_track(i)


# -------------------------------------------------------------------------
# Skinning
# -------------------------------------------------------------------------

func start_bind(rig_id: String, mesh_object_id: String, _options: Dictionary) -> String:
	var job_id := "bind_%d" % _next_job
	_next_job += 1
	var rig := _rig_for_object(rig_id)
	var mesh_node: Node3D = _document.nodes.get(mesh_object_id) if _document != null else null
	var mesh_instance := _find_mesh_instance(mesh_node) if mesh_node != null else null
	if rig.is_empty() or mesh_node == null or mesh_instance == null or mesh_instance.mesh == null:
		_jobs[job_id] = _error_job("Select a rig and a mesh with geometry.")
		return job_id
	var mesh := mesh_instance.mesh
	var surfaces: Array = []
	var total := 0
	for i in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(i)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		total += count
		surfaces.append({
			"arrays": arrays.duplicate(true),
			"primitive": _surface_primitive(mesh, i),
			"material": mesh.surface_get_material(i),
			"vertex_count": count,
		})
	if total == 0:
		_jobs[job_id] = _error_job("The selected mesh has no vertices.")
		return job_id
	if total > MAX_BIND_VERTICES:
		_jobs[job_id] = _error_job("Mesh has %d vertices; the bind limit is 50,000 vertices." % total)
		return job_id
	var rig_node: Node3D = _document.nodes.get(rig_id)
	var rig_space := rig_node.global_transform.affine_inverse() * mesh_node.global_transform
	# A rebind happens after the mesh was locked to the rig. Keep the source
	# transform captured by the first bind so Unbind can restore it.
	var source := {}
	var bind_transform := _transform_to_array(rig_node.global_transform)
	for skin in rig.get("skins", []):
		if str(skin.get("mesh_object_id", "")) != mesh_object_id:
			continue
		if skin.get("source", {}) is Dictionary:
			source = (skin["source"] as Dictionary).duplicate(true)
		if skin.get("bind_transform", null) is Array:
			bind_transform = (skin["bind_transform"] as Array).duplicate()
		break
	if source.is_empty():
		source = _mesh_source(_document.get_object(mesh_object_id), mesh_node.transform)
	_jobs[job_id] = {
		"id": job_id,
		"state": "running",
		"progress": 0.0,
		"error": "",
		"result": {},
		"rig_id": rig_id,
		"mesh_id": mesh_object_id,
		"rig": rig,
		"rig_node": rig_node,
		"mesh_node": mesh_node,
		"mesh_instance": mesh_instance,
		"surfaces": surfaces,
		"surface_index": 0,
		"vertex_index": 0,
		"processed": 0,
		"total": total,
		"rig_space": rig_space,
		"segments": _bone_segments(rig),
		"bone_names": _bone_names(rig),
		"source": source,
		"bind_transform": bind_transform,
		"current_bones": PackedInt32Array(),
		"current_weights": PackedFloat32Array(),
		"all_bones": PackedInt32Array(),
		"all_weights": PackedFloat32Array(),
		"surface_counts": [],
	}
	return job_id


func _error_job(message: String) -> Dictionary:
	return {
		"state": "error",
		"progress": 0.0,
		"result": {},
		"error": message,
	}


func poll_bind(job_id: String) -> Dictionary:
	if not _jobs.has(job_id):
		return _error_job("Unknown bind job.")
	var job: Dictionary = _jobs[job_id]
	if str(job.get("state", "")) != "running":
		return _job_snapshot(job)
	var chunk := 0
	while chunk < Skinning.CHUNK_SIZE and str(job.get("state", "")) == "running":
		var surfaces: Array = job["surfaces"]
		if int(job["surface_index"]) >= surfaces.size():
			_finish_bind(job)
			break
		var surface: Dictionary = surfaces[int(job["surface_index"])]
		var arrays: Array = surface["arrays"]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if int(job["vertex_index"]) >= vertices.size():
			_finish_surface(job, surface)
			continue
		var count := mini(Skinning.CHUNK_SIZE - chunk, vertices.size() - int(job["vertex_index"]))
		var batch := PackedVector3Array()
		batch.resize(count)
		var xform: Transform3D = job["rig_space"]
		for i in range(count):
			batch[i] = xform * vertices[int(job["vertex_index"]) + i]
		var computed: Dictionary = Skinning.compute_weights(batch, job["segments"], Skinning.MAX_INFLUENCES)
		var bones: PackedInt32Array = job["current_bones"]
		var weights: PackedFloat32Array = job["current_weights"]
		bones.append_array(computed["bones"])
		weights.append_array(computed["weights"])
		job["current_bones"] = bones
		job["current_weights"] = weights
		job["vertex_index"] = int(job["vertex_index"]) + count
		job["processed"] = int(job["processed"]) + count
		chunk += count
		job["progress"] = float(job["processed"]) / maxf(1.0, float(job["total"]))
		if int(job["vertex_index"]) >= vertices.size():
			_finish_surface(job, surface)
	_jobs[job_id] = job
	return _job_snapshot(job)


func _job_snapshot(job: Dictionary) -> Dictionary:
	return {
		"state": str(job.get("state", "error")),
		"progress": float(job.get("progress", 0.0)),
		"result": job.get("result", {}),
		"error": str(job.get("error", "")),
	}


func _finish_surface(job: Dictionary, surface: Dictionary) -> void:
	var arrays: Array = surface["arrays"]
	var bones: PackedInt32Array = job["current_bones"]
	var weights: PackedFloat32Array = job["current_weights"]
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	surface["arrays"] = arrays
	var all_bones: PackedInt32Array = job["all_bones"]
	var all_weights: PackedFloat32Array = job["all_weights"]
	all_bones.append_array(bones)
	all_weights.append_array(weights)
	job["all_bones"] = all_bones
	job["all_weights"] = all_weights
	var counts: Array = job["surface_counts"]
	counts.append(int(surface["vertex_count"]))
	job["surface_counts"] = counts
	job["current_bones"] = PackedInt32Array()
	job["current_weights"] = PackedFloat32Array()
	job["surface_index"] = int(job["surface_index"]) + 1
	job["vertex_index"] = 0


func _finish_bind(job: Dictionary) -> void:
	var rig: Dictionary = job["rig"]
	var mesh_id := str(job["mesh_id"])
	var bone_names: Array = job["bone_names"]
	var hash := Skinning.sidecar_hash(str(rig.get("id", "")), mesh_id, int(job["total"]), bone_names, job["all_bones"], job["all_weights"])
	var file := "skins/%s_%s_%s.bin" % [str(rig.get("id", "")), mesh_id, hash]
	var sidecar := _sidecar_path(file)
	if not Skinning.write_sidecar(sidecar, job["all_bones"], job["all_weights"], int(job["total"]), Skinning.MAX_INFLUENCES):
		job["state"] = "error"
		job["error"] = "Could not write the skin sidecar."
		return
	_begin("Bind mesh")
	var mesh: ArrayMesh = ArrayMesh.new()
	for surface in job["surfaces"]:
		var arrays: Array = surface["arrays"]
		var index := mesh.get_surface_count()
		mesh.add_surface_from_arrays(int(surface["primitive"]), arrays)
		if surface.get("material") != null:
			mesh.surface_set_material(index, surface["material"])
	var mesh_instance: MeshInstance3D = job["mesh_instance"]
	mesh_instance.mesh = mesh
	var rig_node: Node3D = job["rig_node"]
	var skeleton := rig_node.get_node_or_null("Skeleton3D") as Skeleton3D
	if skeleton != null:
		mesh_instance.skin = skeleton.create_skin_from_rest_transforms()
		mesh_instance.skeleton = mesh_instance.get_path_to(skeleton)
	var mesh_node: Node3D = job["mesh_node"]
	mesh_node.global_transform = rig_node.global_transform
	var metadata := {
		"mesh_object_id": mesh_id,
		"file": file,
		"hash": hash,
		"vertex_count": int(job["total"]),
		"influences": Skinning.MAX_INFLUENCES,
		"bone_names": bone_names.duplicate(),
		"source": job["source"],
		"bind_transform": job["bind_transform"],
		"surface_counts": (job["surface_counts"] as Array).duplicate(),
	}
	var skins: Array = rig.get("skins", [])
	for i in range(skins.size() - 1, -1, -1):
		if str(skins[i].get("mesh_object_id", "")) == mesh_id:
			skins.remove_at(i)
	skins.append(metadata)
	rig["skins"] = skins
	job["result"] = {
		"vertex_count": int(job["total"]),
		"influences": Skinning.MAX_INFLUENCES,
		"bone_names": bone_names,
		"file": file,
		"hash": hash,
		"surface_count": (job["surfaces"] as Array).size(),
	}
	job["state"] = "done"
	job["progress"] = 1.0
	_end()
	_emit_rigs()


func cancel_bind(job_id: String) -> void:
	if not _jobs.has(job_id):
		return
	var job: Dictionary = _jobs[job_id]
	if str(job.get("state", "")) == "running":
		job["state"] = "cancelled"
		job["error"] = "Bind cancelled."
		_jobs[job_id] = job


func unbind_mesh(rig_id: String, mesh_object_id: String) -> bool:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty():
		return false
	_begin("Unbind mesh")
	var ok := _unbind_internal(rig, mesh_object_id)
	_end()
	if ok:
		_emit_rigs()
	return ok


func _unbind_internal(rig: Dictionary, mesh_object_id: String) -> bool:
	var skins: Array = rig.get("skins", [])
	var index := -1
	for i in range(skins.size()):
		if str(skins[i].get("mesh_object_id", "")) == mesh_object_id:
			index = i
			break
	if index < 0:
		return false
	var skin: Dictionary = skins[index]
	var source: Dictionary = skin.get("source", {})
	var kind := str(source.get("kind", ""))
	var obj: Dictionary = _document.get_object(mesh_object_id) if _document != null else {}
	var node: Node3D = _document.nodes.get(mesh_object_id) if _document != null else null
	if node == null or obj.is_empty():
		return false
	if kind == "import":
		var rel := str(source.get("value", ""))
		if rel == "" or not FileAccess.file_exists(_document.project_dir.path_join(rel)):
			return false
	elif kind != "primitive":
		return false
	_clear_visual_children(node)
	if kind == "import":
		_document._build_import_visual(node, obj)
	else:
		_document._build_mesh_visual(node, obj)
	var transform_data: Dictionary = source.get("transform", {})
	if not transform_data.is_empty():
		node.position = PoseLibrary.array_to_vec3(transform_data.get("p", [0, 0, 0]))
		node.quaternion = PoseLibrary.array_to_quat(transform_data.get("r", [0, 0, 0, 1]))
		node.scale = PoseLibrary.array_to_vec3(transform_data.get("s", [1, 1, 1]))
	skins.remove_at(index)
	rig["skins"] = skins
	return true


func _mesh_source(obj: Dictionary, transform: Transform3D) -> Dictionary:
	var kind := str(obj.get("kind", "mesh"))
	var source := {
		"kind": "primitive",
		"value": str(obj.get("primitive", "box")),
	}
	if kind == "import":
		source = {"kind": "import", "value": str(obj.get("model", ""))}
	source["transform"] = {
		"p": PoseLibrary.vec3_to_array(transform.origin),
		"r": PoseLibrary.quat_to_array(transform.basis.get_rotation_quaternion()),
		"s": PoseLibrary.vec3_to_array(transform.basis.get_scale()),
	}
	return source


func _surface_primitive(mesh: Mesh, index: int) -> int:
	if mesh is ArrayMesh:
		return (mesh as ArrayMesh).surface_get_primitive_type(index)
	return Mesh.PRIMITIVE_TRIANGLES


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node == null:
		return null
	if node is MeshInstance3D:
		return node
	var named := node.get_node_or_null("Mesh")
	if named is MeshInstance3D:
		return named
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null


func _bone_names(rig: Dictionary) -> Array:
	var out: Array = []
	for bone in rig.get("bones", []):
		out.append(str(bone.get("name", "")))
	return out


func _bone_segments(rig: Dictionary) -> Array:
	var out: Array = []
	var bones: Array = rig.get("bones", [])
	for i in range(bones.size()):
		var bone: Dictionary = bones[i]
		var global_rest := _bone_global_rest(rig, i)
		var head := global_rest.origin
		var length := float(bone.get("length", DEFAULT_BONE_LENGTH))
		var tail := head + global_rest.basis.y.normalized() * length
		out.append({
			"name": str(bone.get("name", "")),
			"head": head,
			"tail": tail,
			"influence_scale": float(bone.get("influence_scale", 1.0)),
		})
	return out


func _apply_all_skins(rig: Dictionary) -> void:
	for skin in rig.get("skins", []):
		_apply_skin_record(rig, skin)


func _apply_skin_record(rig: Dictionary, skin: Dictionary) -> bool:
	if _document == null:
		return false
	var mesh_id := str(skin.get("mesh_object_id", ""))
	var mesh_node: Node3D = _document.nodes.get(mesh_id)
	var mesh_instance := _find_mesh_instance(mesh_node) if mesh_node != null else null
	if mesh_instance == null:
		return false
	var source_mesh := _source_mesh(rig, skin)
	if source_mesh == null:
		return false
	var sidecar := _sidecar_path(str(skin.get("file", "")))
	var data: Dictionary = Skinning.read_sidecar(sidecar)
	if not data.get("ok", false):
		push_warning("Kinema: %s" % str(data.get("error", "skin sidecar could not be read")))
		return false
	var counts: Array = skin.get("surface_counts", [])
	if counts.is_empty():
		counts.append(int(skin.get("vertex_count", 0)))
	var slices: Array = Skinning.split_surfaces(data["bones"], data["weights"], int(data["influences"]), counts)
	var bone_names: Array = skin.get("bone_names", [])
	var rig_node: Node3D = _document.nodes.get(str(rig.get("object_id", "")))
	var skeleton: Skeleton3D = rig_node.get_node_or_null("Skeleton3D") as Skeleton3D if rig_node != null else null
	if skeleton == null:
		return false
	var remap: Dictionary = {}
	for i in range(bone_names.size()):
		var current := skeleton.find_bone(str(bone_names[i]))
		if current < 0:
			push_warning("Kinema: skin references missing bone '%s'; keeping the mesh static." % str(bone_names[i]))
			return false
		remap[i] = current
	var mesh := ArrayMesh.new()
	for surface_index in range(source_mesh.get_surface_count()):
		if surface_index >= slices.size():
			break
		var arrays: Array = source_mesh.surface_get_arrays(surface_index).duplicate(true)
		var bones: PackedInt32Array = (slices[surface_index]["bones"] as PackedInt32Array).duplicate()
		var weights: PackedFloat32Array = (slices[surface_index]["weights"] as PackedFloat32Array).duplicate()
		for i in range(bones.size()):
			bones[i] = int(remap.get(bones[i], 0))
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		var index := mesh.get_surface_count()
		mesh.add_surface_from_arrays(_surface_primitive(source_mesh, surface_index), arrays)
		var material := source_mesh.surface_get_material(surface_index)
		if material != null:
			mesh.surface_set_material(index, material)
	mesh_instance.mesh = mesh
	mesh_instance.skin = skeleton.create_skin_from_rest_transforms()
	mesh_instance.skeleton = mesh_instance.get_path_to(skeleton)
	if rig_node != null:
		mesh_node.global_transform = rig_node.global_transform
	return true


func _source_mesh(rig: Dictionary, skin: Dictionary) -> Mesh:
	var source: Dictionary = skin.get("source", {})
	var kind := str(source.get("kind", ""))
	if kind == "primitive":
		return _document._make_primitive(str(source.get("value", "box")))
	if kind == "import":
		var path: String = _document.project_dir.path_join(str(source.get("value", "")))
		if not FileAccess.file_exists(path):
			return null
		var generated: Node = null
		if path.get_extension().to_lower() == "obj":
			generated = ObjImporterScript.new().build(path)
		else:
			var gltf := GLTFDocument.new()
			var state := GLTFState.new()
			if gltf.append_from_file(path, state) == OK:
				generated = gltf.generate_scene(state)
		var mesh_instance := _find_mesh_instance(generated)
		return mesh_instance.mesh if mesh_instance != null else null
	return null


func _sidecar_path(rel: String) -> String:
	var base := ""
	if _document != null and _document.project_dir != "":
		base = _document.project_dir
	else:
		base = ProjectSettings.globalize_path("user://rig_project")
	return base.path_join(rel)


func _clear_visual_children(node: Node3D) -> void:
	for child in node.get_children():
		if child is Skeleton3D:
			continue
		node.remove_child(child)
		child.queue_free()


func _transform_to_array(value: Transform3D) -> Array:
	var b := value.basis
	return [
		b.x.x, b.x.y, b.x.z,
		b.y.x, b.y.y, b.y.z,
		b.z.x, b.z.y, b.z.z,
		value.origin.x, value.origin.y, value.origin.z,
	]


# -------------------------------------------------------------------------
# IK
# -------------------------------------------------------------------------

func add_ik_chain(rig_id: String, root: String, end: String, target_object_id: String) -> String:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty():
		return ""
	var chain_bones := _chain_bones(rig, root, end)
	if chain_bones.size() < 2:
		return ""
	var chain_id := "ik_%d" % _next_ik
	_next_ik += 1
	_begin("Add IK chain")
	(rig["ik"] as Array).append({
		"id": chain_id,
		"name": "IK %d" % (_next_ik - 1),
		"root": root,
		"end": end,
		"target_object_id": target_object_id,
		"weight": 1.0,
		"iterations": 12,
		"pole_angle": 0.0,
		"enabled": true,
	})
	_end()
	_emit_rigs()
	return chain_id


func update_ik_chain(rig_id: String, chain_id: String, patch: Dictionary) -> void:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty():
		return
	for chain in rig.get("ik", []):
		if str(chain.get("id", "")) != chain_id:
			continue
		_begin("Update IK chain")
		for key in ["name", "root", "end", "target_object_id"]:
			if patch.has(key):
				chain[key] = str(patch[key])
		if patch.has("weight"):
			chain["weight"] = clampf(float(patch["weight"]), 0.0, 1.0)
		if patch.has("iterations"):
			chain["iterations"] = IkSolver.clamp_iterations(int(patch["iterations"]))
		if patch.has("pole_angle"):
			chain["pole_angle"] = float(patch["pole_angle"])
		if patch.has("enabled"):
			chain["enabled"] = bool(patch["enabled"])
		_end()
		_emit_rigs()
		return


func delete_ik_chain(rig_id: String, chain_id: String) -> void:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty():
		return
	var chains: Array = rig.get("ik", [])
	for i in range(chains.size() - 1, -1, -1):
		if str(chains[i].get("id", "")) == chain_id:
			_begin("Delete IK chain")
			chains.remove_at(i)
			rig["ik"] = chains
			_end()
			_emit_rigs()
			return


func solve_ik(rig_id: String) -> void:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty() or _document == null:
		return
	var node: Node3D = _document.nodes.get(rig_id)
	if node == null:
		return
	var skeleton := node.get_node_or_null("Skeleton3D") as Skeleton3D
	if skeleton == null:
		return
	for chain in rig.get("ik", []):
		if not bool(chain.get("enabled", true)):
			continue
		var target: Node3D = _document.nodes.get(str(chain.get("target_object_id", "")))
		if target == null:
			chain["enabled"] = false
			continue
		var chain_bones := _chain_bones(rig, str(chain.get("root", "")), str(chain.get("end", "")))
		if chain_bones.size() < 2:
			continue
		var end_bone := _bone(rig, str(chain.get("end", "")))
		var end_length := float(end_bone.get("length", DEFAULT_BONE_LENGTH)) if not end_bone.is_empty() else DEFAULT_BONE_LENGTH
		var solved: Dictionary = IkSolver.solve(
			skeleton,
			PackedStringArray(chain_bones),
			target.global_position,
			float(chain.get("weight", 1.0)),
			float(chain.get("pole_angle", 0.0)),
			int(chain.get("iterations", 12)),
			IkSolver.TOLERANCE,
			end_length)
		for bone_name in solved.keys():
			var index := skeleton.find_bone(str(bone_name))
			if index >= 0:
				skeleton.set_bone_pose_rotation(index, solved[bone_name])


func bake_ik(rig_id: String) -> bool:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty() or _document == null:
		return false
	solve_ik(rig_id)
	var node: Node3D = _document.nodes.get(rig_id)
	var skeleton := node.get_node_or_null("Skeleton3D") as Skeleton3D if node != null else null
	if skeleton == null:
		return false
	var keyed := 0
	_begin("Bake IK")
	for chain in rig.get("ik", []):
		if not bool(chain.get("enabled", true)):
			continue
		for bone_name in _chain_bones(rig, str(chain.get("root", "")), str(chain.get("end", ""))):
			var index := skeleton.find_bone(str(bone_name))
			if index < 0:
				continue
			if _document.insert_bone_key(rig_id, str(bone_name), skeleton.get_bone_pose_rotation(index)) >= 0:
				keyed += 1
	_end()
	return keyed > 0


func _chain_bones(rig: Dictionary, root: String, end: String) -> Array:
	var index := _bone_index(rig, end)
	var root_index := _bone_index(rig, root)
	if index < 0 or root_index < 0:
		return []
	var out: Array = []
	var guard := 0
	while index >= 0 and guard < 256:
		var bone: Dictionary = (rig["bones"] as Array)[index]
		out.push_front(str(bone.get("name", "")))
		if index == root_index:
			return out
		index = int(bone.get("parent", -1))
		guard += 1
	return []


# -------------------------------------------------------------------------
# Poses
# -------------------------------------------------------------------------

func save_pose(rig_id: String, name: String) -> String:
	var clean := name.strip_edges()
	if clean == "":
		return ""
	var rig := _rig_for_object(rig_id)
	if rig.is_empty() or _document == null:
		return ""
	var node: Node3D = _document.nodes.get(rig_id)
	var skeleton: Skeleton3D = null
	if node != null:
		skeleton = node.get_node_or_null("Skeleton3D") as Skeleton3D
	if skeleton == null:
		return ""
	var captured := PoseLibrary.capture(skeleton, node)
	var pose_id := "pose_%d" % _next_pose
	_next_pose += 1
	_begin("Save pose")
	(rig["poses"] as Array).append({
		"id": pose_id,
		"name": clean,
		"bones": captured["bones"],
		"root_position": captured["root_position"],
	})
	_end()
	_emit_rigs()
	return pose_id


func apply_pose(rig_id: String, pose_id: String) -> void:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty() or _document == null:
		return
	var pose := _find_pose(rig, pose_id)
	if pose.is_empty():
		return
	var node: Node3D = _document.nodes.get(rig_id)
	var skeleton: Skeleton3D = null
	if node != null:
		skeleton = node.get_node_or_null("Skeleton3D") as Skeleton3D
	_begin("Apply pose")
	PoseLibrary.apply(skeleton, node, pose)
	_end()
	_emit_rigs()


func reset_pose(rig_id: String, bone_name: String = "") -> void:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty() or _document == null:
		return
	var node: Node3D = _document.nodes.get(rig_id)
	var skeleton: Skeleton3D = null
	if node != null:
		skeleton = node.get_node_or_null("Skeleton3D") as Skeleton3D
	if skeleton == null:
		return
	var names: Array = []
	if bone_name == "":
		for bone in rig.get("bones", []):
			names.append(str(bone.get("name", "")))
	else:
		names.append(bone_name)
	_begin("Reset pose")
	for name in names:
		var index := skeleton.find_bone(str(name))
		if index < 0:
			continue
		skeleton.set_bone_pose_position(index, Vector3.ZERO)
		skeleton.set_bone_pose_rotation(index, Quaternion.IDENTITY)
		skeleton.set_bone_pose_scale(index, Vector3.ONE)
	_end()
	_emit_rigs()


func key_pose(rig_id: String) -> bool:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty() or _document == null:
		return false
	var node: Node3D = _document.nodes.get(rig_id)
	var skeleton: Skeleton3D = null
	if node != null:
		skeleton = node.get_node_or_null("Skeleton3D") as Skeleton3D
	if skeleton == null:
		return false
	var captured := PoseLibrary.capture(skeleton, node)
	var rotations: Dictionary = {}
	for bone_name in captured.get("bones", {}).keys():
		var value: Variant = captured["bones"][bone_name]
		rotations[bone_name] = value.get("r", [0, 0, 0, 1]) if value is Dictionary else value
	_begin("Key pose")
	_document.insert_pose_keys(rig_id, rotations)
	_end()
	return true


func delete_pose(rig_id: String, pose_id: String) -> void:
	var rig := _rig_for_object(rig_id)
	if rig.is_empty():
		return
	var poses: Array = rig.get("poses", [])
	for i in range(poses.size() - 1, -1, -1):
		if str(poses[i].get("id", "")) == pose_id:
			_begin("Delete pose")
			poses.remove_at(i)
			rig["poses"] = poses
			_end()
			_emit_rigs()
			return


func rename_pose(rig_id: String, pose_id: String, name: String) -> bool:
	var clean := name.strip_edges()
	if clean == "":
		return false
	var rig := _rig_for_object(rig_id)
	var pose := _find_pose(rig, pose_id)
	if pose.is_empty():
		return false
	_begin("Rename pose")
	pose["name"] = clean
	_end()
	_emit_rigs()
	return true


func duplicate_pose(rig_id: String, pose_id: String) -> String:
	var rig := _rig_for_object(rig_id)
	var pose := _find_pose(rig, pose_id)
	if pose.is_empty():
		return ""
	var copy: Dictionary = pose.duplicate(true)
	var new_id := "pose_%d" % _next_pose
	_next_pose += 1
	copy["id"] = new_id
	copy["name"] = str(pose.get("name", "Pose")) + " Copy"
	_begin("Duplicate pose")
	(rig["poses"] as Array).append(copy)
	_end()
	_emit_rigs()
	return new_id


func _find_pose(rig: Dictionary, pose_id: String) -> Dictionary:
	for pose in rig.get("poses", []):
		if str(pose.get("id", "")) == pose_id:
			return pose
	return {}


# -------------------------------------------------------------------------
# Imported skeletons
# -------------------------------------------------------------------------

func adopt_imported_skeleton(object_id: String, node: Node) -> bool:
	if object_id == "" or node == null or _document == null:
		return false
	if not _rig_for_object(object_id).is_empty():
		return true
	var skeleton := _find_skeleton(node)
	if skeleton == null:
		return false
	var bones: Array = []
	for i in range(skeleton.get_bone_count()):
		var rest := skeleton.get_bone_rest(i)
		var length := DEFAULT_BONE_LENGTH
		for child in range(skeleton.get_bone_count()):
			if skeleton.get_bone_parent(child) == i:
				var child_rest := skeleton.get_bone_global_rest(child)
				length = maxf(rest.origin.distance_to(child_rest.origin), 0.0001)
				break
		bones.append({
			"name": skeleton.get_bone_name(i),
			"parent": skeleton.get_bone_parent(i),
			"p": rest.origin,
			"r": rest.basis.get_rotation_quaternion().normalized(),
			"s": rest.basis.get_scale(),
			"length": length,
			"influence_scale": 1.0,
		})
	if bones.is_empty():
		return false
	var rig := {
		"id": "rig_%d" % _next_rig,
		"object_id": object_id,
		"name": str(_document.get_object(object_id).get("name", "Rig")),
		"bones": bones,
		"skins": [],
		"ik": [],
		"poses": [],
		"pose": {},
		"active_bone": str(bones[0].get("name", "")),
		"imported": true,
	}
	_next_rig += 1
	_rigs.append(rig)
	_active_rig = object_id
	_emit_rigs()
	if _document != null and _document.has_signal("rig_adopted"):
		_document.rig_adopted.emit(object_id, bones.size())
	return true


func _find_skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


# -------------------------------------------------------------------------
# Frame hook
# -------------------------------------------------------------------------

func advance(_delta: float) -> void:
	if _document == null or _document._loading:
		return
	for rig in _rigs:
		_sync_bound_transforms(rig)
		var has_chain := false
		for chain in rig.get("ik", []):
			if bool(chain.get("enabled", true)) and _document.nodes.has(str(chain.get("target_object_id", ""))):
				has_chain = true
				break
		if has_chain:
			solve_ik(str(rig.get("object_id", "")))


func _sync_bound_transforms(rig: Dictionary) -> void:
	if _document == null:
		return
	var rig_node: Node3D = _document.nodes.get(str(rig.get("object_id", "")))
	if rig_node == null:
		return
	for skin in rig.get("skins", []):
		var mesh_node: Node3D = _document.nodes.get(str(skin.get("mesh_object_id", "")))
		if mesh_node != null:
			mesh_node.global_transform = rig_node.global_transform


# -------------------------------------------------------------------------
# Edit/signal helpers
# -------------------------------------------------------------------------

func _begin(label: String) -> void:
	if _document == null:
		return
	if _edit_depth == 0:
		_document.begin_edit(label)
	_edit_depth += 1


func _end() -> void:
	if _document == null:
		return
	_edit_depth = maxi(0, _edit_depth - 1)
	if _edit_depth == 0:
		_document.end_edit()


func _emit_rigs() -> void:
	if _document != null and _document.has_signal("rigs_changed"):
		_document.rigs_changed.emit()


func _emit_selection(rig_id: String, bone: String) -> void:
	if _document != null and _document.has_signal("rig_selection_changed"):
		_document.rig_selection_changed.emit(rig_id, bone)
