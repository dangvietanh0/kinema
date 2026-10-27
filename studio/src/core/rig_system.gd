extends RefCounted
## Rigging subsystem contract: skeleton model, skinning jobs, FABRIK IK and
## the pose library.
##
## The contract commit installs safe no-ops so the shell and document can be
## wired before WS-C lands. Bind jobs report a real error instead of a fake
## progress value. WS-C replaces this file and keeps these signatures.

var _document = null

func setup(document) -> void:
	_document = document

func reset() -> void:
	pass

func to_data() -> Dictionary:
	return {"rigs": []}

func load_data(_data: Dictionary, _nodes: Dictionary) -> void:
	pass

func advance(_delta: float) -> void:
	pass

func create_rig(_name: String, _at: Vector3) -> String:
	return ""

func delete_rig(_object_id: String) -> bool:
	return false

func rig_ids() -> PackedStringArray:
	return PackedStringArray()

func get_rig(_object_id: String) -> Dictionary:
	return {}

func active_rig_id() -> String:
	return ""

func set_active_rig(_object_id: String) -> void:
	pass

func add_bone(_rig_id: String, _name: String, _parent: String, _rest: Dictionary) -> int:
	return -1

func remove_bone(_rig_id: String, _name: String) -> bool:
	return false

func set_bone_rest(_rig_id: String, _name: String, _rest: Dictionary) -> void:
	pass

func set_bone_parent(_rig_id: String, _name: String, _parent: String) -> bool:
	return false

func set_active_bone(_rig_id: String, _name: String) -> void:
	pass

func set_bone_influence_scale(_rig_id: String, _bone: String, _scale: float) -> void:
	pass

func start_bind(_rig_id: String, _mesh_object_id: String, _options: Dictionary) -> String:
	return ""

func poll_bind(_job_id: String) -> Dictionary:
	return {
		"state": "error",
		"progress": 0.0,
		"result": {},
		"error": "Rigging is not implemented yet.",
	}

func cancel_bind(_job_id: String) -> void:
	pass

func unbind_mesh(_rig_id: String, _mesh_object_id: String) -> bool:
	return false

func add_ik_chain(_rig_id: String, _root: String, _end: String, _target_object_id: String) -> String:
	return ""

func update_ik_chain(_rig_id: String, _chain_id: String, _patch: Dictionary) -> void:
	pass

func delete_ik_chain(_rig_id: String, _chain_id: String) -> void:
	pass

func solve_ik(_rig_id: String) -> void:
	pass

func bake_ik(_rig_id: String) -> bool:
	return false

func save_pose(_rig_id: String, _name: String) -> String:
	return ""

func apply_pose(_rig_id: String, _pose_id: String) -> void:
	pass

func delete_pose(_rig_id: String, _pose_id: String) -> void:
	pass

func key_pose(_rig_id: String) -> bool:
	return false

func adopt_imported_skeleton(_object_id: String, _node: Node) -> bool:
	return false

func on_object_spawned(_obj: Dictionary, _node: Node3D) -> void:
	pass

func on_object_properties(_obj: Dictionary, _node: Node3D) -> void:
	pass
