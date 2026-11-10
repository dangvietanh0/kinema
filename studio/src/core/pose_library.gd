extends RefCounted
## Pose capture/apply and JSON conversion.
##
## Pose v2 stores every bone's local position, rotation and scale plus the rig
## root position. The record is JSON-safe: quaternions and vectors are arrays.
## Legacy poses that stored a bare quaternion per bone are read as
## rotation-only, so older project files keep working.


static func capture(skeleton: Skeleton3D, root_node: Node3D) -> Dictionary:
	var bones: Dictionary = {}
	if skeleton != null:
		for i in range(skeleton.get_bone_count()):
			bones[skeleton.get_bone_name(i)] = {
				"p": vec3_to_array(skeleton.get_bone_pose_position(i)),
				"r": quat_to_array(skeleton.get_bone_pose_rotation(i)),
				"s": vec3_to_array(skeleton.get_bone_pose_scale(i)),
			}
	var root_position := Vector3.ZERO
	if root_node != null:
		root_position = root_node.position
	return {"bones": bones, "root_position": vec3_to_array(root_position)}


static func apply(skeleton: Skeleton3D, root_node: Node3D, pose: Dictionary) -> void:
	apply_bones(skeleton, pose)
	if root_node != null and pose.has("root_position"):
		root_node.position = array_to_vec3(pose["root_position"])


## Apply only the bone transforms. Project load uses this so a saved pose can
## never override the document object's authoritative transform.
static func apply_bones(skeleton: Skeleton3D, pose: Dictionary) -> void:
	if skeleton == null:
		return
	var bones: Dictionary = pose.get("bones", {})
	if not pose.has("bones"):
		bones = pose
	for bone_name in bones.keys():
		var index := skeleton.find_bone(str(bone_name))
		if index < 0:
			continue
		var value: Variant = bones[bone_name]
		if value is Dictionary and (_has_channel(value, "p") or _has_channel(value, "r") or _has_channel(value, "s")):
			var channels: Dictionary = value
			if channels.has("p"):
				skeleton.set_bone_pose_position(index, array_to_vec3(channels["p"]))
			if channels.has("r"):
				skeleton.set_bone_pose_rotation(index, array_to_quat(channels["r"]))
			if channels.has("s"):
				skeleton.set_bone_pose_scale(index, array_to_vec3(channels["s"]))
		else:
			# Legacy pose: a bare quaternion array (or Quaternion) per bone.
			skeleton.set_bone_pose_rotation(index, array_to_quat(value))


static func _has_channel(value: Dictionary, channel: String) -> bool:
	return value.has(channel)


static func bone_count(pose: Dictionary) -> int:
	return (pose.get("bones", {}) as Dictionary).size()


static func serialize(pose: Dictionary) -> Dictionary:
	var bones: Dictionary = {}
	var raw_bones: Dictionary = pose.get("bones", {})
	for bone_name in raw_bones.keys():
		bones[str(bone_name)] = _serialize_bone(raw_bones[bone_name])
	return {
		"bones": bones,
		"root_position": vec3_to_array(array_to_vec3(pose.get("root_position", [0, 0, 0]))),
	}


static func deserialize(pose: Dictionary) -> Dictionary:
	var bones: Dictionary = {}
	var raw_bones: Dictionary = pose.get("bones", {})
	for bone_name in raw_bones.keys():
		bones[str(bone_name)] = _serialize_bone(raw_bones[bone_name])
	return {
		"bones": bones,
		"root_position": vec3_to_array(array_to_vec3(pose.get("root_position", [0, 0, 0]))),
	}


static func _serialize_bone(value: Variant) -> Variant:
	if value is Dictionary:
		var channels: Dictionary = value
		var out: Dictionary = {}
		if channels.has("p"):
			out["p"] = vec3_to_array(array_to_vec3(channels["p"]))
		if channels.has("r"):
			out["r"] = quat_to_array(array_to_quat(channels["r"]))
		if channels.has("s"):
			out["s"] = vec3_to_array(array_to_vec3(channels["s"]))
		if not out.is_empty():
			return out
	return {"r": quat_to_array(array_to_quat(value))}


static func quat_to_array(value: Quaternion) -> Array:
	var q := value.normalized()
	return [q.x, q.y, q.z, q.w]


static func array_to_quat(value) -> Quaternion:
	if value is Quaternion:
		return (value as Quaternion).normalized()
	if value is Array and (value as Array).size() >= 4:
		var arr: Array = value
		var q := Quaternion(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
		return q.normalized() if q.length_squared() > 0.000001 else Quaternion.IDENTITY
	return Quaternion.IDENTITY


static func vec3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func array_to_vec3(value) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() >= 3:
		var arr: Array = value
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO
