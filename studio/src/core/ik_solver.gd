extends RefCounted
## FABRIK for a chain of Skeleton3D bones.
##
## The solver works in skeleton space, keeps every bone length, and converts
## the solved joint positions back to local pose rotations using the rest and
## parent transforms. Weight 0 returns the current rotations unchanged.

const MIN_ITERATIONS := 8
const MAX_ITERATIONS := 24
const TOLERANCE := 0.001
const DEFAULT_END_LENGTH := 0.4


static func solve(skeleton: Skeleton3D, chain: PackedStringArray, target_world: Vector3, weight: float, pole_angle: float = 0.0, iterations: int = 12, tolerance: float = TOLERANCE, end_length: float = -1.0) -> Dictionary:
	if skeleton == null or chain.size() < 2:
		return {}
	var indices: Array[int] = []
	for bone_name in chain:
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			return {}
		indices.append(index)
	var current := {}
	for bone_name in chain:
		var index := skeleton.find_bone(bone_name)
		current[bone_name] = skeleton.get_bone_pose_rotation(index)
	if weight <= 0.000001:
		return current

	var target := skeleton.to_local(target_world)
	var joints: Array[Vector3] = []
	for index in indices:
		joints.append(skeleton.get_bone_global_pose(index).origin)
	var lengths: Array[float] = []
	for i in range(indices.size() - 1):
		lengths.append(maxf(joints[i].distance_to(joints[i + 1]), 0.0001))
	var last_length := end_length
	if last_length <= 0.0:
		var last_pose := skeleton.get_bone_global_pose(indices[indices.size() - 1])
		last_length = maxf(last_pose.basis.y.length() * DEFAULT_END_LENGTH, 0.0001)
	lengths.append(maxf(last_length, 0.0001))
	var last_direction := (joints[joints.size() - 1] - joints[joints.size() - 2]).normalized()
	if last_direction.length_squared() < 0.5:
		last_direction = skeleton.get_bone_global_pose(indices[indices.size() - 1]).basis.y.normalized()
	joints.append(joints[joints.size() - 1] + last_direction * lengths[lengths.size() - 1])

	var root := joints[0]
	var total_length := 0.0
	for length in lengths:
		total_length += length
	var to_target := target - root
	var target_distance := to_target.length()
	if target_distance >= total_length:
		var direction := to_target.normalized() if target_distance > 0.000001 else Vector3.UP
		for i in range(1, joints.size()):
			joints[i] = joints[i - 1] + direction * lengths[i - 1]
	else:
		var limit := clampi(iterations, MIN_ITERATIONS, MAX_ITERATIONS)
		for _iteration in range(limit):
			joints[joints.size() - 1] = target
			for i in range(joints.size() - 2, -1, -1):
				var direction := (joints[i] - joints[i + 1])
				if direction.length_squared() < 0.0000001:
					direction = Vector3.UP
				joints[i] = joints[i + 1] + direction.normalized() * lengths[i]
			joints[0] = root
			for i in range(joints.size() - 1):
				var direction := (joints[i + 1] - joints[i])
				if direction.length_squared() < 0.0000001:
					direction = Vector3.UP
				joints[i + 1] = joints[i] + direction.normalized() * lengths[i]
			if joints[joints.size() - 1].distance_to(target) <= maxf(tolerance, 0.00001):
				break

	# A pole angle rotates the bend around the root-to-end axis. The end point
	# lies on that axis, so the rotation preserves every bone length.
	if absf(pole_angle) > 0.000001:
		var axis := joints[joints.size() - 1] - joints[0]
		if axis.length_squared() > 0.0000001:
			var rotation := Quaternion(axis.normalized(), pole_angle)
			for i in range(1, joints.size() - 1):
				joints[i] = joints[0] + rotation * (joints[i] - joints[0])

	var solved: Dictionary = {}
	var solved_global: Array[Basis] = []
	var blend := clampf(weight, 0.0, 1.0)
	for i in range(indices.size()):
		var index := indices[i]
		var parent_index := skeleton.get_bone_parent(index)
		var parent_basis := Basis.IDENTITY
		if i > 0 and parent_index == indices[i - 1]:
			parent_basis = solved_global[i - 1]
		elif parent_index >= 0:
			parent_basis = skeleton.get_bone_global_pose(parent_index).basis
		var base := parent_basis * skeleton.get_bone_rest(index).basis
		var current_direction := base.y.normalized()
		var desired_direction := (joints[i + 1] - joints[i]).normalized()
		if desired_direction.length_squared() < 0.5:
			desired_direction = current_direction
		var delta := Quaternion(current_direction, desired_direction)
		var desired_basis := Basis(delta) * base
		var pose_basis := base.inverse() * desired_basis
		var rotation := pose_basis.get_rotation_quaternion().normalized()
		var bone_name := str(chain[i])
		solved[bone_name] = current[bone_name].slerp(rotation, blend) if blend < 1.0 else rotation
		solved_global.append(desired_basis)
	return solved


static func clamp_iterations(value: int) -> int:
	return clampi(value, MIN_ITERATIONS, MAX_ITERATIONS)
