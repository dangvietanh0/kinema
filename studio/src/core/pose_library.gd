extends RefCounted
## Pose capture/apply and JSON conversion.
##
## A pose stores every bone's local pose rotation plus the rig root position.
## The record is JSON-safe: quaternions and vectors are arrays.


static func capture(skeleton: Skeleton3D, root_node: Node3D) -> Dictionary:
	var bones: Dictionary = {}
	if skeleton != null:
		for i in range(skeleton.get_bone_count()):
			bones[skeleton.get_bone_name(i)] = quat_to_array(skeleton.get_bone_pose_rotation(i))
	var root_position := Vector3.ZERO
	if root_node != null:
		root_position = root_node.position
	return {"bones": bones, "root_position": vec3_to_array(root_position)}


static func apply(skeleton: Skeleton3D, root_node: Node3D, pose: Dictionary) -> void:
	if skeleton != null:
		var bones: Dictionary = pose.get("bones", {})
		for bone_name in bones.keys():
			var index := skeleton.find_bone(str(bone_name))
			if index < 0:
				continue
			skeleton.set_bone_pose_rotation(index, array_to_quat(bones[bone_name]))
	if root_node != null and pose.has("root_position"):
		root_node.position = array_to_vec3(pose["root_position"])


static func bone_count(pose: Dictionary) -> int:
	return (pose.get("bones", {}) as Dictionary).size()


static func serialize(pose: Dictionary) -> Dictionary:
	var bones: Dictionary = {}
	var raw_bones: Dictionary = pose.get("bones", {})
	for bone_name in raw_bones.keys():
		bones[str(bone_name)] = quat_to_array(raw_bones[bone_name])
	return {
		"bones": bones,
		"root_position": vec3_to_array(pose.get("root_position", Vector3.ZERO)),
	}


static func deserialize(pose: Dictionary) -> Dictionary:
	var bones: Dictionary = {}
	var raw_bones: Dictionary = pose.get("bones", {})
	for bone_name in raw_bones.keys():
		bones[str(bone_name)] = array_to_quat(raw_bones[bone_name])
	return {
		"bones": bones,
		"root_position": array_to_vec3(pose.get("root_position", [0, 0, 0])),
	}


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
