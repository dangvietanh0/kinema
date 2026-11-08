extends Control
## Viewport overlay for rig mode: octahedral bones, joints, the active bone and
## IK targets. Hit-testing is done in screen space with a 22 dp radius so a
## finger can grab a bone without pixel precision. Edit mode adds 22 dp rest
## head/tail handles; both rest drags commit once through set_bone_rest, so one
## gesture is one undo entry.
##
## The overlay never owns state. It reads the rig record and the Skeleton3D pose,
## and writes back through the rig system (active bone) or the skeleton (drag
## rotation). Dragging a bone rotates it around its own head, which is the same
## pivot the viewport gizmo would use.

signal bone_selected(bone: String)
signal mode_changed(mode: String)

const HIT_RADIUS := 22.0
const JOINT_RADIUS := 4.0
const ACTIVE_JOINT_RADIUS := 6.0
const TARGET_HANDLE_RADIUS := 22.0
const DRAG_SENSITIVITY := 0.012
const BONE_WIDTH_RATIO := 0.22
const MIN_BONE_WIDTH := 12.0
const MAX_BONE_WIDTH := 44.0
const SHOULDER_RATIO := 0.2
const EDIT_HANDLE_RADIUS := 22.0
const EDIT_HANDLE_DRAW_RADIUS := 10.0
const MIN_BONE_LENGTH := 0.01
const MAX_BONE_LENGTH := 100.0
const REST_LIMIT := 100.0
const GIZMO_RING_SEGMENTS := 32
const GIZMO_RING_PX := 64.0
const GIZMO_FREE_RING_PX := 96.0
const GIZMO_ARROW_PX := 64.0
const GIZMO_HIT_RADIUS := 22.0
const GIZMO_CENTER_RADIUS := 22.0
const GIZMO_AXIS_COLORS := {"x": Kit.DANGER, "y": Kit.SUCCESS, "z": Kit.FOCUS_BRIGHT}

var doc = null
var view = null
var rig_system = null

var _rig_id := ""
var _enabled := false
var _mode := "pose"
var _transform := "rotate"
var _axis := "free"
var _dragging := false
var _drag_bone := ""
var _drag_origin := Vector2.ZERO
var _drag_start_rotation := Quaternion.IDENTITY
var _drag_start_position := Vector3.ZERO
var _drag_start_scale := Vector3.ONE
var _drag_target := ""
var _drag_kind := ""
var _drag_rest_start: Dictionary = {}
var _drag_rest_current: Dictionary = {}
var _drag_head_world := Vector3.ZERO
var _drag_plane := Plane()
var _readout_text := ""
var _readout_screen := Vector2.ZERO
var _gizmo_hover_axis := ""
var _gizmo_active_axis := ""
var _draw_count := 0


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
	if _rig_id != rig_id:
		_cancel_drag()
	_rig_id = rig_id
	queue_redraw()


func set_enabled(value: bool) -> void:
	if not value and _drag_kind != "":
		_end_drag()
	_enabled = value
	mouse_filter = Control.MOUSE_FILTER_STOP if _enabled else Control.MOUSE_FILTER_PASS
	if not _enabled:
		_dragging = false
		_drag_bone = ""
		_drag_target = ""
		_drag_kind = ""
		_drag_rest_current = {}
		_gizmo_active_axis = ""
		_gizmo_hover_axis = ""
	queue_redraw()


func is_enabled() -> bool:
	return _enabled


func hit_radius() -> float:
	return HIT_RADIUS


func mode() -> String:
	return _mode


func transform_mode() -> String:
	return _transform


## The gesture in flight. A bone body drag is "bone" in both Pose and Edit; the
## rest handles and gizmo kinds only start in Edit.
func current_drag_kind() -> String:
	if _drag_kind != "":
		return _drag_kind
	return "bone" if _dragging else ""


func axis_mode() -> String:
	return _axis


func gizmo_axes() -> PackedStringArray:
	return PackedStringArray(["x", "y", "z", "free"])


func gizmo_active_axis() -> String:
	return _gizmo_active_axis


func draw_count() -> int:
	return _draw_count


func set_transform_mode(mode: String) -> void:
	var clean := mode if mode in ["rotate", "move"] else "rotate"
	if _transform == clean:
		return
	_transform = clean
	_gizmo_hover_axis = ""
	queue_redraw()


func set_axis_mode(axis: String) -> void:
	var clean := axis if axis in ["free", "x", "y", "z"] else "free"
	if _axis == clean:
		return
	_axis = clean
	queue_redraw()


func readout_visible() -> bool:
	return _dragging and _readout_text != ""


func readout_text() -> String:
	return _readout_text


func is_edit_mode() -> bool:
	return _mode == "edit"


## Pose is the default workbench mode. Edit is refused on an imported
## skeleton because its rest transforms belong to the imported asset.
func set_mode(mode: String) -> void:
	var clean := mode if mode in ["pose", "edit"] else "pose"
	if clean == "edit" and _imported():
		clean = "pose"
	if _mode == clean:
		return
	_cancel_drag()
	_mode = clean
	queue_redraw()
	mode_changed.emit(_mode)


func bone_color(active: bool) -> Color:
	return Kit.FOCUS_BRIGHT if active else Kit.TEXT_MUTED


## Octahedral bone silhouette in screen space: head, one shoulder, tail, the
## other shoulder. The shoulders sit 20% of the bone width off the axis and
## 20% of the way along the bone, so the quad stays a convex diamond.
func bone_polygon(head_screen: Vector2, tail_screen: Vector2, width: float) -> PackedVector2Array:
	var axis := tail_screen - head_screen
	var length := axis.length()
	if length <= 0.000001:
		axis = Vector2.DOWN
	else:
		axis /= length
	var perpendicular := Vector2(-axis.y, axis.x)
	var shoulder_center := head_screen + axis * (length * SHOULDER_RATIO)
	var offset := perpendicular * (maxf(0.0, width) * SHOULDER_RATIO)
	return PackedVector2Array([head_screen, shoulder_center + offset, tail_screen, shoulder_center - offset])


func edit_handle_radius() -> float:
	return EDIT_HANDLE_RADIUS


## Bone width follows the projected length, like a Blender octahedral bone, so
## a long bone reads as a shape instead of a hairline at any zoom.
func bone_width(screen_length: float) -> float:
	return clampf(screen_length * BONE_WIDTH_RATIO, MIN_BONE_WIDTH, MAX_BONE_WIDTH)


func head_handle_at(screen: Vector2) -> bool:
	if not _enabled or not is_edit_mode() or _imported():
		return false
	var segment := _active_rest_segment()
	return not segment.is_empty() and screen.distance_to(segment["head"]) <= EDIT_HANDLE_RADIUS


func tail_handle_at(screen: Vector2) -> bool:
	if not _enabled or not is_edit_mode() or _imported():
		return false
	var segment := _active_rest_segment()
	return not segment.is_empty() and screen.distance_to(segment["tail"]) <= EDIT_HANDLE_RADIUS


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
	var use_rest := is_edit_mode()
	for i in range(bones.size()):
		var name := str(bones[i].get("name", ""))
		var index := skeleton.find_bone(name)
		if index < 0:
			continue
		var segment := _bone_world_segment(bones, index, skeleton, use_rest, {})
		if segment.is_empty():
			continue
		var head_screen: Vector2 = view.world_to_screen(skeleton.to_global(segment["head"]))
		var tail_screen: Vector2 = view.world_to_screen(skeleton.to_global(segment["tail"]))
		var distance := _distance_to_segment_2d(screen, head_screen, tail_screen)
		if distance < best_distance:
			best_distance = distance
			best = name
	return best


func _imported() -> bool:
	if rig_system == null or _rig_id == "":
		return false
	return bool(rig_system.get_rig(_rig_id).get("imported", false))


func _active_bone_name() -> String:
	if rig_system == null or _rig_id == "":
		return ""
	return str(rig_system.get_rig(_rig_id).get("active_bone", ""))


func _bone_rest_transform(skeleton: Skeleton3D, bones: Array, index: int, override: Dictionary) -> Transform3D:
	if not override.is_empty() and index >= 0:
		var parent := skeleton.get_bone_parent(index)
		var parent_global := Transform3D.IDENTITY
		if parent >= 0:
			parent_global = skeleton.get_bone_global_rest(parent)
		var local := Transform3D(
			Basis(override.get("r", Quaternion.IDENTITY)).scaled(override.get("s", Vector3.ONE)),
			override.get("p", Vector3.ZERO))
		return parent_global * local
	return skeleton.get_bone_global_rest(index)


## Skeleton-space head/tail for one bone, in pose or rest space. An override
## makes the active rest bone follow the drag preview before the single
## set_bone_rest write at release.
func _bone_world_segment(bones: Array, index: int, skeleton: Skeleton3D, use_rest: bool, override: Dictionary) -> Dictionary:
	if index < 0 or index >= bones.size():
		return {}
	var bone: Dictionary = bones[index]
	var length := float(bone.get("length", 0.4))
	var head := Vector3.ZERO
	var tail := Vector3.ZERO
	if use_rest:
		var rest := _bone_rest_transform(skeleton, bones, index, override)
		if not override.is_empty():
			length = float(override.get("length", length))
		head = rest.origin
		tail = head + rest.basis.y.normalized() * length
	else:
		var pose := skeleton.get_bone_global_pose(index)
		head = pose.origin
		tail = head + pose.basis.y.normalized() * length
	return {"head": head, "tail": tail, "length": length}


func _active_rest_segment() -> Dictionary:
	if rig_system == null or _rig_id == "" or view == null:
		return {}
	var skeleton := _skeleton()
	if skeleton == null:
		return {}
	var rig: Dictionary = rig_system.get_rig(_rig_id)
	var bones: Array = rig.get("bones", [])
	var name := _active_bone_name()
	for i in range(bones.size()):
		if str(bones[i].get("name", "")) != name:
			continue
		var override := _drag_rest_current if name == _drag_bone else {}
		var segment := _bone_world_segment(bones, i, skeleton, true, override)
		if segment.is_empty():
			return {}
		return {
			"head": view.world_to_screen(skeleton.to_global(segment["head"])),
			"tail": view.world_to_screen(skeleton.to_global(segment["tail"])),
		}
	return {}


func _distance_to_segment_2d(point: Vector2, head: Vector2, tail: Vector2) -> float:
	var segment := tail - head
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(head)
	var t := clampf((point - head).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(head + segment * t)


func _distance_to_polyline(point: Vector2, points: PackedVector2Array) -> float:
	var best := INF
	var count := points.size()
	if count == 0:
		return best
	for i in range(count):
		best = minf(best, _distance_to_segment_2d(point, points[i], points[(i + 1) % count]))
	return best


func _gizmo_origin_world() -> Vector3:
	if rig_system == null or _rig_id == "":
		return Vector3.ZERO
	var skeleton := _skeleton()
	if skeleton == null:
		return Vector3.ZERO
	var rig: Dictionary = rig_system.get_rig(_rig_id)
	var bones: Array = rig.get("bones", [])
	var name := str(rig.get("active_bone", ""))
	var index := skeleton.find_bone(name)
	if index < 0:
		return Vector3.ZERO
	var override := _drag_rest_current if name == _drag_bone else {}
	var segment := _bone_world_segment(bones, index, skeleton, is_edit_mode(), override)
	if segment.is_empty():
		return Vector3.ZERO
	return skeleton.to_global(segment["head"])


func _gizmo_origin_screen() -> Vector2:
	if view == null:
		return Vector2.ZERO
	return view.world_to_screen(_gizmo_origin_world())


func _gizmo_camera_basis() -> Basis:
	if view == null:
		return Basis.IDENTITY
	if view.has_method("camera_transform"):
		return view.camera_transform().basis
	var camera = view.get("_camera")
	if camera is Camera3D:
		return (camera as Camera3D).global_transform.basis
	return Basis.IDENTITY


func _gizmo_ring_basis(axis: String) -> Array:
	match axis:
		"x":
			return [Vector3.UP, Vector3.BACK]
		"y":
			return [Vector3.RIGHT, Vector3.BACK]
		"z":
			return [Vector3.RIGHT, Vector3.UP]
	var basis := _gizmo_camera_basis()
	return [basis.x.normalized(), basis.y.normalized()]


func _gizmo_world_axis(axis: String) -> Vector3:
	match axis:
		"x":
			return Vector3.RIGHT
		"y":
			return Vector3.UP
		"z":
			return Vector3.BACK
	return Vector3.ZERO


func _gizmo_ring_radius(origin: Vector3, axis: String) -> float:
	var pair := _gizmo_ring_basis(axis)
	var basis_a: Vector3 = pair[0]
	var px: float = (view.world_to_screen(origin + basis_a) - view.world_to_screen(origin)).length()
	var target := GIZMO_FREE_RING_PX if axis == "free" else GIZMO_RING_PX
	return clampf(target / maxf(px, 0.0001), 0.05, 50.0)


func _gizmo_ring_screen_radius(axis: String) -> float:
	var origin := _gizmo_origin_world()
	var pair := _gizmo_ring_basis(axis)
	var basis_a: Vector3 = pair[0]
	var px: float = (view.world_to_screen(origin + basis_a) - view.world_to_screen(origin)).length()
	return _gizmo_ring_radius(origin, axis) * px


func _gizmo_axis_color(axis: String, active: bool) -> Color:
	var color: Color = GIZMO_AXIS_COLORS.get(axis, Kit.FOCUS_BRIGHT)
	if not active:
		color.a *= 0.45
	return color


func _closed_polyline(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	closed.append(points[0])
	return closed


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
	_draw_count += 1
	var bones: Array = rig.get("bones", [])
	var active := str(rig.get("active_bone", ""))
	var use_rest := is_edit_mode()
	for i in range(bones.size()):
		var bone: Dictionary = bones[i]
		var name := str(bone.get("name", ""))
		var index := skeleton.find_bone(name)
		if index < 0:
			continue
		var override := _drag_rest_current if name == _drag_bone else {}
		var segment := _bone_world_segment(bones, index, skeleton, use_rest, override)
		if segment.is_empty():
			continue
		var head: Vector2 = view.world_to_screen(skeleton.to_global(segment["head"]))
		var tail: Vector2 = view.world_to_screen(skeleton.to_global(segment["tail"]))
		var color := bone_color(name == active)
		var polygon := bone_polygon(head, tail, bone_width(head.distance_to(tail)))
		draw_colored_polygon(polygon, color)
		var outline := polygon.duplicate()
		outline.append(polygon[0])
		draw_polyline(outline, Kit.BORDER_SOFT, 1.0, true)
		draw_circle(head, ACTIVE_JOINT_RADIUS if name == active else JOINT_RADIUS, color)
		draw_circle(tail, JOINT_RADIUS, Kit.TEXT_DIM)
	if use_rest and active != "":
		var segment := _active_rest_segment()
		if not segment.is_empty():
			draw_arc(segment["head"], EDIT_HANDLE_DRAW_RADIUS, 0.0, TAU, 24, Kit.FOCUS_BRIGHT, 2.0)
			draw_circle(segment["head"], 3.0, Kit.FOCUS_BRIGHT)
			draw_arc(segment["tail"], EDIT_HANDLE_DRAW_RADIUS, 0.0, TAU, 24, Kit.FOCUS_BRIGHT, 2.0)
			draw_circle(segment["tail"], 3.0, Kit.FOCUS_BRIGHT)
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
	if gizmo_visible():
		_draw_gizmo()
	if _dragging and _readout_text != "":
		var font := ThemeDB.fallback_font
		var text_size := font.get_string_size(_readout_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		var anchor := _readout_screen + Vector2(14, -18)
		var rect := Rect2(anchor - Vector2(6, text_size.y), text_size + Vector2(12, 8))
		draw_rect(rect, Kit.SURFACE_3, true)
		draw_string(font, anchor, _readout_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Kit.TEXT)


func _draw_gizmo() -> void:
	var origin := _gizmo_origin_screen()
	var active := _gizmo_active_axis if _gizmo_active_axis != "" else _gizmo_hover_axis
	if _transform == "move":
		for axis in ["x", "y", "z"]:
			var shaft := gizmo_arrow_points(axis)
			if shaft.size() < 2:
				continue
			var color := _gizmo_axis_color(axis, active == axis)
			draw_line(shaft[0], shaft[1], color, 2.0, true)
			var tip := _gizmo_arrow_tip(axis)
			if tip.size() >= 3:
				draw_colored_polygon(tip, color)
		var center_color := Kit.FOCUS_BRIGHT if active == "free" else Kit.FOCUS
		if active != "free":
			center_color.a *= 0.45
		draw_rect(Rect2(origin - Vector2(5, 5), Vector2(10, 10)), center_color, true)
		return
	var free_points := gizmo_ring_points("free")
	if free_points.size() >= 2:
		var free_color := Kit.FOCUS_BRIGHT if active == "free" else Kit.FOCUS
		if active != "free":
			free_color.a *= 0.45
		draw_polyline(_closed_polyline(free_points), free_color, 1.0, true)
	for axis in ["x", "y", "z"]:
		var points := gizmo_ring_points(axis)
		if points.size() < 2:
			continue
		draw_polyline(_closed_polyline(points), _gizmo_axis_color(axis, active == axis), 2.0, true)


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
			press_at(button.position)
			accept_event()
		elif _dragging or _drag_target != "" or _drag_kind != "":
			release_drag()
			accept_event()
	elif event is InputEventMouseMotion:
		if Kit.is_emulated_mouse(event):
			return
		var motion := event as InputEventMouseMotion
		if not _dragging and _drag_target == "" and _drag_kind == "":
			var hover := gizmo_handle_at(motion.position)
			if hover != _gizmo_hover_axis:
				_gizmo_hover_axis = hover
				queue_redraw()
		drag_at(motion.position)
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			press_at(touch.position)
			accept_event()
		elif _dragging or _drag_target != "" or _drag_kind != "":
			release_drag()
			accept_event()
	elif event is InputEventScreenDrag:
		drag_at((event as InputEventScreenDrag).position)


func press_at(screen: Vector2) -> void:
	if is_edit_mode():
		if _imported():
			return
		if head_handle_at(screen):
			_begin_rest_drag("head", screen)
			return
		if tail_handle_at(screen):
			_begin_rest_drag("tail", screen)
			return
		if _gizmo_enabled() and gizmo_handle_at(screen) != "":
			_begin_gizmo_drag(gizmo_handle_at(screen), screen)
			return
		var edit_target := bone_at(screen)
		if edit_target != "":
			_begin_edit_body_drag(edit_target, screen)
		return
	if _gizmo_enabled() and gizmo_handle_at(screen) != "":
		_begin_gizmo_drag(gizmo_handle_at(screen), screen)
		return
	var chain_id := _chain_at(screen)
	if chain_id != "":
		_drag_target = chain_id
		return
	var bone := bone_at(screen)
	if bone != "":
		_begin_drag(bone, screen)


func gizmo_visible() -> bool:
	if not _enabled or rig_system == null or _rig_id == "" or view == null:
		return false
	if is_edit_mode() and _imported():
		return false
	var rig: Dictionary = rig_system.get_rig(_rig_id)
	if str(rig.get("active_bone", "")) == "":
		return false
	return _skeleton() != null


func _gizmo_enabled() -> bool:
	return gizmo_visible()


## The projected ring for one gizmo axis. The free ring lives in the camera
## plane and is wider so it never overlaps an axis ring inside the 22 dp band.
func gizmo_ring_points(axis: String) -> PackedVector2Array:
	if not gizmo_visible() or not (axis in ["x", "y", "z", "free"]):
		return PackedVector2Array()
	var origin := _gizmo_origin_world()
	var pair := _gizmo_ring_basis(axis)
	var basis_a: Vector3 = pair[0]
	var basis_b: Vector3 = pair[1]
	var radius := _gizmo_ring_radius(origin, axis)
	var points := PackedVector2Array()
	for i in range(GIZMO_RING_SEGMENTS):
		var angle := TAU * float(i) / float(GIZMO_RING_SEGMENTS)
		points.append(view.world_to_screen(
			origin + basis_a * (cos(angle) * radius) + basis_b * (sin(angle) * radius)))
	return points


func gizmo_polyline(axis: String) -> PackedVector2Array:
	return gizmo_ring_points(axis)


func gizmo_arrow_points(axis: String) -> PackedVector2Array:
	if not gizmo_visible() or not (axis in ["x", "y", "z"]):
		return PackedVector2Array()
	var origin := _gizmo_origin_world()
	var world_axis := _gizmo_world_axis(axis)
	var px: float = (view.world_to_screen(origin + world_axis) - view.world_to_screen(origin)).length()
	var radius := clampf(GIZMO_ARROW_PX / maxf(px, 0.0001), 0.05, 50.0)
	return PackedVector2Array([
		view.world_to_screen(origin),
		view.world_to_screen(origin + world_axis * radius),
	])


func _gizmo_arrow_tip(axis: String) -> PackedVector2Array:
	var shaft := gizmo_arrow_points(axis)
	if shaft.size() < 2:
		return PackedVector2Array()
	var direction := (shaft[1] - shaft[0]).normalized()
	if direction.length_squared() <= 0.000001:
		return PackedVector2Array()
	var normal := Vector2(-direction.y, direction.x)
	return PackedVector2Array([
		shaft[1],
		shaft[1] - direction * 8.0 + normal * 4.0,
		shaft[1] - direction * 8.0 - normal * 4.0,
	])


## Hit testing never mixes the rotate rings with the move arrows. A ring hit
## also has to sit at the ring's projected radius, so an edge-on ring cannot
## steal a press in the middle of the bone it circles.
func gizmo_handle_at(screen: Vector2) -> String:
	if not gizmo_visible():
		return ""
	if _transform == "move":
		var center := _gizmo_origin_screen()
		if center.distance_to(screen) <= GIZMO_CENTER_RADIUS:
			return "free"
		for axis in ["x", "y", "z"]:
			var shaft := gizmo_arrow_points(axis)
			if shaft.size() >= 2 \
					and _distance_to_segment_2d(screen, shaft[0], shaft[1]) <= GIZMO_HIT_RADIUS:
				return axis
		return ""
	var origin := _gizmo_origin_screen()
	for axis in ["free", "x", "y", "z"]:
		var points := gizmo_ring_points(axis)
		if points.size() < 2:
			continue
		if absf(origin.distance_to(screen) - _gizmo_ring_screen_radius(axis)) > GIZMO_HIT_RADIUS:
			continue
		if _distance_to_polyline(screen, points) <= GIZMO_HIT_RADIUS:
			return axis
	return ""


func _begin_gizmo_drag(axis: String, screen: Vector2) -> void:
	var clean := axis if axis in ["x", "y", "z", "free"] else "free"
	_gizmo_active_axis = clean
	_gizmo_hover_axis = clean
	_axis = clean
	var kind := "gizmo_move" if _transform == "move" else "gizmo_rotate"
	if is_edit_mode():
		_begin_rest_drag(kind, screen)
	else:
		var name := _active_bone_name()
		if name != "":
			_begin_drag(name, screen)
			_drag_kind = kind
	if _drag_kind == "":
		_gizmo_active_axis = ""
	queue_redraw()


func drag_at(screen: Vector2) -> void:
	if _drag_kind.begins_with("gizmo_"):
		if is_edit_mode():
			_drag_rest(screen)
		else:
			_drag_gizmo(screen)
	elif _drag_kind == "bone":
		if is_edit_mode():
			_drag_edit_body(screen)
		elif _transform == "move":
			_move_drag(screen)
		else:
			_rotate_drag(screen)
	elif _drag_kind != "":
		_drag_rest(screen)
	elif _drag_target != "":
		_move_target(screen)
	elif _dragging:
		if _transform == "move":
			_move_drag(screen)
		else:
			_rotate_drag(screen)


func release_drag() -> void:
	_end_drag()


func _begin_drag(bone: String, screen: Vector2) -> void:
	_dragging = true
	_drag_kind = "bone"
	_drag_bone = bone
	_drag_origin = screen
	var skeleton := _skeleton()
	if skeleton != null:
		var index := skeleton.find_bone(bone)
		if index >= 0:
			_drag_start_rotation = skeleton.get_bone_pose_rotation(index)
			_drag_start_position = skeleton.get_bone_pose_position(index)
			_drag_start_scale = skeleton.get_bone_pose_scale(index)
			_drag_head_world = skeleton.to_global(skeleton.get_bone_global_pose(index).origin)
	_readout_text = ""
	_drag_plane = _camera_plane(_drag_head_world)
	rig_system.set_active_bone(_rig_id, bone)
	bone_selected.emit(bone)
	rig_system.begin_pose_edit("Pose bone")


func _end_drag() -> void:
	var commits_rest := is_edit_mode() \
		and _drag_kind in ["head", "tail", "gizmo_rotate", "gizmo_move", "bone"]
	if commits_rest and _drag_bone != "" and not _drag_rest_current.is_empty():
		if _rest_changed(_drag_rest_start, _drag_rest_current):
			# One gesture, one undo entry: the preview only becomes a rest
			# edit when the finger lifts.
			rig_system.set_bone_rest(_rig_id, _drag_bone, _drag_rest_current)
	if _dragging and _drag_bone != "":
		rig_system.end_pose_edit()
	_readout_text = ""
	_dragging = false
	_drag_bone = ""
	_drag_target = ""
	_drag_rest_start = {}
	_drag_rest_current = {}
	_drag_kind = ""
	_gizmo_active_axis = ""
	queue_redraw()


func _cancel_drag() -> void:
	if _dragging and _drag_bone != "":
		# Cancel restores the pose captured on press, then closes the one
		# transaction the gesture opened.
		rig_system.set_bone_pose(_rig_id, _drag_bone, {
			"p": _drag_start_position,
			"r": _drag_start_rotation,
			"s": _drag_start_scale,
		})
		rig_system.end_pose_edit()
	_readout_text = ""
	_dragging = false
	_drag_bone = ""
	_drag_target = ""
	_drag_kind = ""
	_drag_rest_start = {}
	_drag_rest_current = {}
	_gizmo_active_axis = ""
	_gizmo_hover_axis = ""
	queue_redraw()


func _rest_changed(before: Dictionary, after: Dictionary) -> bool:
	if before.is_empty() or after.is_empty():
		return false
	if (before.get("p", Vector3.ZERO) as Vector3).distance_to(after.get("p", Vector3.ZERO)) > 0.000001:
		return true
	if absf(float(before.get("length", 0.0)) - float(after.get("length", 0.0))) > 0.000001:
		return true
	return (before.get("r", Quaternion.IDENTITY) as Quaternion).angle_to(
		after.get("r", Quaternion.IDENTITY)) > 0.000001


func _begin_rest_drag(kind: String, screen: Vector2) -> void:
	var rig: Dictionary = rig_system.get_rig(_rig_id)
	if rig.is_empty() or bool(rig.get("imported", false)):
		return
	var skeleton := _skeleton()
	if skeleton == null:
		return
	var name := str(rig.get("active_bone", ""))
	var bones: Array = rig.get("bones", [])
	var index := skeleton.find_bone(name)
	if index < 0 or index >= bones.size():
		return
	var bone: Dictionary = bones[index]
	var segment := _bone_world_segment(bones, index, skeleton, true, {})
	if segment.is_empty():
		return
	_drag_kind = kind
	_drag_bone = name
	_drag_origin = screen
	_drag_start_rotation = bone.get("r", Quaternion.IDENTITY)
	_drag_start_position = bone.get("p", Vector3.ZERO)
	_drag_rest_start = {
		"p": bone.get("p", Vector3.ZERO),
		"r": bone.get("r", Quaternion.IDENTITY),
		"s": bone.get("s", Vector3.ONE),
		"length": float(bone.get("length", 0.4)),
	}
	_drag_rest_current = _drag_rest_start.duplicate(true)
	_drag_head_world = skeleton.to_global(segment["head"])
	_drag_plane = _camera_plane(_drag_head_world)


## A plane facing the camera through the drag origin. Reads the viewport
## camera when it exposes one, so a real perspective camera and the test view
## share the same code path.
func _camera_plane(origin_world: Vector3) -> Plane:
	var direction := Vector3.FORWARD
	if view != null and view.has_method("camera_transform"):
		direction = (view.camera_transform().basis.z as Vector3)
	elif view != null:
		var camera = view.get("_camera")
		if camera is Camera3D:
			direction = (camera as Camera3D).global_transform.basis.z
	var normal := -direction
	if normal.length_squared() <= 0.000001:
		normal = Vector3.BACK
	normal = normal.normalized()
	return Plane(normal, normal.dot(origin_world))


func _begin_edit_body_drag(bone: String, screen: Vector2) -> void:
	var rig: Dictionary = rig_system.get_rig(_rig_id)
	if rig.is_empty() or bool(rig.get("imported", false)):
		return
	var skeleton := _skeleton()
	if skeleton == null:
		return
	var bones: Array = rig.get("bones", [])
	var index := skeleton.find_bone(bone)
	if index < 0 or index >= bones.size():
		return
	var segment := _bone_world_segment(bones, index, skeleton, true, {})
	if segment.is_empty():
		return
	_drag_kind = "bone"
	_drag_bone = bone
	_drag_origin = screen
	_drag_start_rotation = bones[index].get("r", Quaternion.IDENTITY)
	_drag_start_position = bones[index].get("p", Vector3.ZERO)
	_drag_rest_start = {
		"p": _drag_start_position,
		"r": _drag_start_rotation,
		"s": bones[index].get("s", Vector3.ONE),
		"length": float(bones[index].get("length", 0.4)),
	}
	_drag_rest_current = _drag_rest_start.duplicate(true)
	_drag_head_world = skeleton.to_global(segment["head"])
	_drag_plane = _camera_plane(_drag_head_world)
	rig_system.set_active_bone(_rig_id, bone)
	bone_selected.emit(bone)


## Edit body drag is a free rotation of the rest bone around its own head. It
## previews in _drag_rest_current and commits once, on release, through
## set_bone_rest; the bone length is never touched.
func _drag_edit_body(screen: Vector2) -> void:
	if _drag_rest_current.is_empty():
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
	_drag_rest_current["r"] = (yaw * pitch * _drag_start_rotation).normalized()
	queue_redraw()


func _plane_hit(screen: Vector2):
	if view == null:
		return null
	var ray: Dictionary = view.screen_ray(screen)
	var origin: Vector3 = ray.get("origin", Vector3.ZERO)
	var direction: Vector3 = ray.get("direction", Vector3.FORWARD)
	if direction.length_squared() <= 0.000001:
		return null
	return _drag_plane.intersects_ray(origin, direction)


func _drag_rest(screen: Vector2) -> void:
	if _drag_kind == "gizmo_rotate":
		_drag_edit_gizmo_rotate(screen)
		return
	if _drag_kind == "gizmo_move":
		_drag_edit_gizmo_move(screen)
		return
	if _drag_kind != "head" and _drag_kind != "tail":
		return
	var hit = _plane_hit(screen)
	if hit == null:
		return
	var skeleton := _skeleton()
	if skeleton == null:
		return
	var bones: Array = rig_system.get_rig(_rig_id).get("bones", [])
	var index := skeleton.find_bone(_drag_bone)
	if index < 0 or index >= bones.size():
		return
	var parent := skeleton.get_bone_parent(index)
	var parent_global := Transform3D.IDENTITY
	if parent >= 0:
		parent_global = skeleton.get_bone_global_rest(parent)
	var local_hit := skeleton.to_local(hit)
	var local_start := skeleton.to_local(_drag_head_world)
	var local_delta := parent_global.basis.inverse() * (local_hit - local_start)
	if _drag_kind == "head":
		var start := _drag_rest_start.get("p", Vector3.ZERO) as Vector3
		var moved := start + local_delta
		_drag_rest_current["p"] = Vector3(
			clampf(moved.x, -REST_LIMIT, REST_LIMIT),
			clampf(moved.y, -REST_LIMIT, REST_LIMIT),
			clampf(moved.z, -REST_LIMIT, REST_LIMIT))
	else:
		if local_delta.length_squared() <= 0.000001:
			return
		# The rest bone points along its local +Y, exactly like the skeleton
		# pose. Aim that axis at the pointer and take the new length.
		_drag_rest_current["r"] = Quaternion(Vector3.UP, local_delta.normalized())
		_drag_rest_current["length"] = clampf(
			local_delta.length(), MIN_BONE_LENGTH, MAX_BONE_LENGTH)
	queue_redraw()


## Pose gizmo drags reuse the existing axis-locked pose paths; Edit gizmo
## drags preview the rest transform and commit once on release.
func _drag_gizmo(screen: Vector2) -> void:
	if _transform == "move":
		_move_drag(screen)
	else:
		_rotate_drag(screen)


func _drag_edit_gizmo_rotate(screen: Vector2) -> void:
	if _drag_rest_current.is_empty():
		return
	var next := _drag_start_rotation
	if _axis == "free":
		var delta := screen - _drag_origin
		var basis := _gizmo_camera_basis()
		var up := basis.y.normalized()
		var right := basis.x.normalized()
		var yaw := Quaternion(up, -delta.x * DRAG_SENSITIVITY)
		var pitch := Quaternion(right, -delta.y * DRAG_SENSITIVITY)
		next = (yaw * pitch * _drag_start_rotation).normalized()
	else:
		var origin_screen := _gizmo_origin_screen()
		var start_vec := _drag_origin - origin_screen
		var now_vec := screen - origin_screen
		if start_vec.length_squared() <= 0.000001 or now_vec.length_squared() <= 0.000001:
			return
		var angle := start_vec.angle_to(now_vec)
		var parent_axis := _gizmo_parent_axis(_gizmo_world_axis(_axis))
		next = (Quaternion(parent_axis, angle) * _drag_start_rotation).normalized()
	_drag_rest_current["r"] = next
	queue_redraw()


func _drag_edit_gizmo_move(screen: Vector2) -> void:
	if _drag_rest_current.is_empty():
		return
	var skeleton := _skeleton()
	if skeleton == null:
		return
	var index := skeleton.find_bone(_drag_bone)
	if index < 0:
		return
	var parent_basis := Basis.IDENTITY
	var parent := skeleton.get_bone_parent(index)
	if parent >= 0:
		parent_basis = skeleton.get_bone_global_rest(parent).basis
	var delta := Vector3.ZERO
	if _axis == "free":
		var hit = _plane_hit(screen)
		if hit == null:
			return
		delta = parent_basis.inverse() * (
			skeleton.to_local(hit) - skeleton.to_local(_drag_head_world))
	else:
		var axis_world := _gizmo_world_axis(_axis)
		var screen_axis := _screen_axis(axis_world, _drag_head_world)
		if screen_axis.length_squared() <= 0.000001:
			return
		var units := (screen - _drag_origin).dot(screen_axis.normalized()) / screen_axis.length()
		var axis_skeleton := skeleton.global_transform.basis.inverse() * axis_world
		delta = parent_basis.inverse() * (axis_skeleton * units)
	var start := _drag_rest_start.get("p", Vector3.ZERO) as Vector3
	var moved := start + delta
	_drag_rest_current["p"] = Vector3(
		clampf(moved.x, -REST_LIMIT, REST_LIMIT),
		clampf(moved.y, -REST_LIMIT, REST_LIMIT),
		clampf(moved.z, -REST_LIMIT, REST_LIMIT))
	queue_redraw()


## A world axis expressed in the bone's parent rest space, so it can compose
## with the stored local rest rotation.
func _gizmo_parent_axis(world_axis: Vector3) -> Vector3:
	var skeleton := _skeleton()
	if skeleton == null:
		return world_axis.normalized()
	var skeleton_axis := (skeleton.global_transform.basis.inverse() * world_axis).normalized()
	var index := skeleton.find_bone(_drag_bone)
	if index < 0:
		return skeleton_axis
	var parent := skeleton.get_bone_parent(index)
	if parent < 0:
		return skeleton_axis
	return (skeleton.get_bone_global_rest(parent).basis.inverse() * skeleton_axis).normalized()


func _rotate_drag(screen: Vector2) -> void:
	var skeleton := _skeleton()
	if skeleton == null or _drag_bone == "":
		return
	var index := skeleton.find_bone(_drag_bone)
	if index < 0:
		return
	var delta := screen - _drag_origin
	var next_rotation := _drag_start_rotation
	if _axis == "free":
		var up := Vector3.UP
		var right := Vector3.RIGHT
		if view != null:
			var camera = view.get("_camera")
			if camera is Camera3D:
				up = (camera as Camera3D).global_transform.basis.y.normalized()
				right = (camera as Camera3D).global_transform.basis.x.normalized()
		var yaw := Quaternion(up, -delta.x * DRAG_SENSITIVITY)
		var pitch := Quaternion(right, -delta.y * DRAG_SENSITIVITY)
		next_rotation = (yaw * pitch * _drag_start_rotation).normalized()
	else:
		var local_axis := _axis_vector()
		var world_axis := (skeleton.global_transform.basis * (skeleton.get_bone_global_pose(index).basis * local_axis)).normalized()
		var screen_axis := _screen_axis(world_axis, _drag_head_world)
		if screen_axis.length_squared() <= 0.000001:
			return
		var sign := 1.0
		if delta.dot(screen_axis) < 0.0:
			sign = -1.0
		var projected := absf(delta.dot(screen_axis.normalized()))
		var angle := clampf(sign * projected * DRAG_SENSITIVITY, -PI, PI)
		next_rotation = (_drag_start_rotation * Quaternion(local_axis, angle)).normalized()
	rig_system.set_bone_pose(_rig_id, _drag_bone, {"r": next_rotation})
	_set_readout("%.0f°" % rad_to_deg(next_rotation.angle_to(_drag_start_rotation)),
		view.world_to_screen(_drag_head_world) if view != null else screen)
	queue_redraw()


func _move_drag(screen: Vector2) -> void:
	var skeleton := _skeleton()
	if skeleton == null or _drag_bone == "" or view == null:
		return
	var index := skeleton.find_bone(_drag_bone)
	if index < 0:
		return
	var parent := skeleton.get_bone_parent(index)
	var parent_basis := Basis.IDENTITY
	if parent >= 0:
		parent_basis = skeleton.get_bone_global_pose(parent).basis
	var delta_parent := Vector3.ZERO
	if _axis == "free":
		var hit = _plane_hit(screen)
		if hit == null:
			return
		delta_parent = parent_basis.inverse() * (skeleton.to_local(hit) - skeleton.to_local(_drag_head_world))
	else:
		var axis_world := _axis_world_vector()
		var screen_axis := _screen_axis(axis_world, _drag_head_world)
		if screen_axis.length_squared() <= 0.000001:
			return
		var units := (screen - _drag_origin).dot(screen_axis.normalized()) / screen_axis.length()
		var axis_skeleton := skeleton.global_transform.basis.inverse() * axis_world
		delta_parent = parent_basis.inverse() * (axis_skeleton * units)
	var next_position := _drag_start_position + delta_parent
	if doc != null and doc.snap:
		next_position = Vector3(
			roundf(next_position.x / 0.01) * 0.01,
			roundf(next_position.y / 0.01) * 0.01,
			roundf(next_position.z / 0.01) * 0.01)
	rig_system.set_bone_pose(_rig_id, _drag_bone, {"p": next_position})
	_set_readout("%.2f u" % next_position.distance_to(_drag_start_position),
		view.world_to_screen(_drag_head_world))
	queue_redraw()


func _axis_vector() -> Vector3:
	match _axis:
		"x":
			return Vector3.RIGHT
		"y":
			return Vector3.UP
		"z":
			return Vector3.BACK
	return Vector3.ZERO


func _axis_world_vector() -> Vector3:
	match _axis:
		"x":
			return Vector3.RIGHT
		"y":
			return Vector3.UP
		"z":
			return Vector3.BACK
	return Vector3.ZERO


func _screen_axis(world_axis: Vector3, origin_world: Vector3) -> Vector2:
	if view == null:
		return Vector2.ZERO
	return view.world_to_screen(origin_world + world_axis) - view.world_to_screen(origin_world)


func _set_readout(text: String, screen: Vector2) -> void:
	_readout_text = text
	_readout_screen = screen


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
