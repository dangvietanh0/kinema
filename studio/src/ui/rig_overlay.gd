extends Control
## Viewport overlay for rig mode: bone sticks, joints, the active bone and IK
## targets. Hit-testing is done in screen space with a 22 dp radius so a finger
## can grab a bone without pixel precision.
##
## The overlay never owns state. It reads the rig record and the Skeleton3D pose,
## and writes back through the rig system (active bone) or the skeleton (drag
## rotation). Dragging a bone rotates it around its own head, which is the same
## pivot the viewport gizmo would use.

signal bone_selected(bone: String)

const HIT_RADIUS := 22.0
const JOINT_RADIUS := 3.0
const ACTIVE_JOINT_RADIUS := 5.0
const TARGET_HANDLE_RADIUS := 22.0
const DRAG_SENSITIVITY := 0.012

var doc = null
var view = null
var rig_system = null

var _rig_id := ""
var _enabled := false
var _dragging := false
var _drag_bone := ""
var _drag_origin := Vector2.ZERO
var _drag_start_rotation := Quaternion.IDENTITY
var _drag_target := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(true)


func setup(document, view_ref, rig_system_ref) -> void:
	doc = document
	view = view_ref
	rig_system = rig_system_ref
	if doc != null and not doc.rigs_changed.is_connected(_on_rigs_changed):
		doc.rigs_changed.connect(_on_rigs_changed)
	if doc != null and not doc.rig_selection_changed.is_connected(_on_rig_selection_changed):
		doc.rig_selection_changed.connect(_on_rig_selection_changed)
	queue_redraw()


func set_rig(rig_id: String) -> void:
	_rig_id = rig_id
	queue_redraw()


func set_enabled(value: bool) -> void:
	_enabled = value
	mouse_filter = Control.MOUSE_FILTER_STOP if _enabled else Control.MOUSE_FILTER_PASS
	if not _enabled:
		_dragging = false
		_drag_bone = ""
		_drag_target = ""
	queue_redraw()


func is_enabled() -> bool:
	return _enabled


func hit_radius() -> float:
	return HIT_RADIUS


func bone_at(screen: Vector2) -> String:
	if not _enabled or rig_system == null or _rig_id == "" or view == null:
		return ""
	var skeleton := _skeleton()
	if skeleton == null:
		return ""
	var rig: Dictionary = rig_system.get_rig(_rig_id)
	var bones: Array = rig.get("bones", [])
	var best := ""
	var best_distance := HIT_RADIUS
	for i in range(bones.size()):
		var name := str(bones[i].get("name", ""))
		var index := skeleton.find_bone(name)
		if index < 0:
			continue
		var pose := skeleton.get_bone_global_pose(index)
		var head := skeleton.to_global(pose.origin)
		var length := float(bones[i].get("length", 0.4))
		var tail := skeleton.to_global(pose.origin + pose.basis.y.normalized() * length)
		var head_screen: Vector2 = view.world_to_screen(head)
		var tail_screen: Vector2 = view.world_to_screen(tail)
		var distance := _distance_to_segment_2d(screen, head_screen, tail_screen)
		if distance < best_distance:
			best_distance = distance
			best = name
	return best


func _distance_to_segment_2d(point: Vector2, head: Vector2, tail: Vector2) -> float:
	var segment := tail - head
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(head)
	var t := clampf((point - head).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(head + segment * t)


func _skeleton() -> Skeleton3D:
	if doc == null or _rig_id == "":
		return null
	var node: Node3D = doc.nodes.get(_rig_id)
	if node == null:
		return null
	return node.get_node_or_null("Skeleton3D") as Skeleton3D


func _process(_delta: float) -> void:
	if _enabled:
		queue_redraw()


func _draw() -> void:
	if not _enabled or rig_system == null or _rig_id == "" or view == null:
		return
	var skeleton := _skeleton()
	if skeleton == null:
		return
	var rig: Dictionary = rig_system.get_rig(_rig_id)
	if rig.is_empty():
		return
	var bones: Array = rig.get("bones", [])
	var active := str(rig.get("active_bone", ""))
	for i in range(bones.size()):
		var bone: Dictionary = bones[i]
		var name := str(bone.get("name", ""))
		var index := skeleton.find_bone(name)
		if index < 0:
			continue
		var pose := skeleton.get_bone_global_pose(index)
		var length := float(bone.get("length", 0.4))
		var head: Vector2 = view.world_to_screen(skeleton.to_global(pose.origin))
		var tail: Vector2 = view.world_to_screen(skeleton.to_global(pose.origin + pose.basis.y.normalized() * length))
		var color := Kit.FOCUS_BRIGHT if name == active else Kit.TEXT_MUTED
		draw_line(head, tail, color, 2.0)
		draw_circle(head, ACTIVE_JOINT_RADIUS if name == active else JOINT_RADIUS, color)
		draw_circle(tail, JOINT_RADIUS, Kit.TEXT_DIM)
	for chain in rig.get("ik", []):
		if not bool(chain.get("enabled", true)):
			continue
		var target: Node3D = doc.nodes.get(str(chain.get("target_object_id", "")))
		if target == null:
			continue
		var target_screen: Vector2 = view.world_to_screen(target.global_position)
		var end_bone := str(chain.get("end", ""))
		var end_index := skeleton.find_bone(end_bone)
		if end_index >= 0:
			var end_bone_data: Dictionary = bones[end_index]
			var end_pose := skeleton.get_bone_global_pose(end_index)
			var end_length := float(end_bone_data.get("length", 0.4))
			var effector: Vector2 = view.world_to_screen(skeleton.to_global(
				end_pose.origin + end_pose.basis.y.normalized() * end_length))
			draw_dashed_line(effector, target_screen, Kit.FOCUS_DARK, 1.0)
		draw_arc(target_screen, TARGET_HANDLE_RADIUS, 0.0, TAU, 32, Kit.FOCUS_BRIGHT, 1.0)
		draw_circle(target_screen, 4.0, Kit.FOCUS_BRIGHT)


func _gui_input(event: InputEvent) -> void:
	if not _enabled or rig_system == null or _rig_id == "":
		return
	if event is InputEventMouseButton:
		if Kit.is_emulated_mouse(event):
			return
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_press_at(button.position)
			accept_event()
		elif _dragging or _drag_target != "":
			_end_drag()
			accept_event()
	elif event is InputEventMouseMotion:
		if Kit.is_emulated_mouse(event):
			return
		_drag_at((event as InputEventMouseMotion).position)
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_press_at(touch.position)
			accept_event()
		elif _dragging or _drag_target != "":
			_end_drag()
			accept_event()
	elif event is InputEventScreenDrag:
		_drag_at((event as InputEventScreenDrag).position)


func _press_at(screen: Vector2) -> void:
	var chain_id := _chain_at(screen)
	if chain_id != "":
		_drag_target = chain_id
		return
	var bone := bone_at(screen)
	if bone != "":
		_begin_drag(bone, screen)


func _drag_at(screen: Vector2) -> void:
	if _drag_target != "":
		_move_target(screen)
	elif _dragging:
		_rotate_drag(screen)


func _begin_drag(bone: String, screen: Vector2) -> void:
	_dragging = true
	_drag_bone = bone
	_drag_origin = screen
	var skeleton := _skeleton()
	if skeleton != null:
		var index := skeleton.find_bone(bone)
		if index >= 0:
			_drag_start_rotation = skeleton.get_bone_pose_rotation(index)
	rig_system.set_active_bone(_rig_id, bone)
	bone_selected.emit(bone)


func _end_drag() -> void:
	_dragging = false
	_drag_bone = ""
	_drag_target = ""
	queue_redraw()


func _rotate_drag(screen: Vector2) -> void:
	var skeleton := _skeleton()
	if skeleton == null or _drag_bone == "":
		return
	var index := skeleton.find_bone(_drag_bone)
	if index < 0:
		return
	var delta := screen - _drag_origin
	var up := Vector3.UP
	var right := Vector3.RIGHT
	if view != null:
		var camera = view.get("_camera")
		if camera is Camera3D:
			up = (camera as Camera3D).global_transform.basis.y.normalized()
			right = (camera as Camera3D).global_transform.basis.x.normalized()
	var yaw := Quaternion(up, -delta.x * DRAG_SENSITIVITY)
	var pitch := Quaternion(right, -delta.y * DRAG_SENSITIVITY)
	skeleton.set_bone_pose_rotation(index, (yaw * pitch * _drag_start_rotation).normalized())
	queue_redraw()


func _chain_at(screen: Vector2) -> String:
	if doc == null or rig_system == null:
		return ""
	var rig: Dictionary = rig_system.get_rig(_rig_id)
	for chain in rig.get("ik", []):
		if not bool(chain.get("enabled", true)):
			continue
		var target: Node3D = doc.nodes.get(str(chain.get("target_object_id", "")))
		if target == null:
			continue
		if view.world_to_screen(target.global_position).distance_to(screen) <= TARGET_HANDLE_RADIUS:
			return str(chain.get("id", ""))
	return ""


func _move_target(screen: Vector2) -> void:
	if doc == null or rig_system == null:
		return
	var rig: Dictionary = rig_system.get_rig(_rig_id)
	for chain in rig.get("ik", []):
		if str(chain.get("id", "")) != _drag_target:
			continue
		var target: Node3D = doc.nodes.get(str(chain.get("target_object_id", "")))
		if target == null:
			return
		var ray: Dictionary = view.screen_ray(screen)
		var origin: Vector3 = ray.get("origin", Vector3.ZERO)
		var direction: Vector3 = ray.get("direction", Vector3.FORWARD)
		var normal := -direction
		if normal.length_squared() <= 0.000001:
			return
		normal = normal.normalized()
		var plane := Plane(normal, normal.dot(target.global_position))
		var hit = plane.intersects_ray(origin, direction)
		if hit != null:
			target.global_position = hit
			queue_redraw()
		return


func _on_rigs_changed() -> void:
	queue_redraw()


func _on_rig_selection_changed(rig_id: String, _bone: String) -> void:
	if rig_id == _rig_id:
		queue_redraw()
