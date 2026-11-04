extends Node3D
## Real 3D transform gizmo for the stage SubViewport.
##
## The node is built once from MeshInstance3D parts: tapered cylinder shafts
## with cone arrowheads for move, torus rings plus a brighter front arc for
## rotate, tapered shafts with cube tips for scale, and a centre handle that
## really moves (screen-plane), scales (uniform) or rotates (Y) the selection.
##
## Its world scale is derived from the camera FOV and the real SubViewport
## height, so the 1.0-unit arm keeps a constant screen size at any camera
## distance. The effective size in dp is clamped between MIN and MAX so a
## tiny object still gets a usable gizmo and a huge one never gets an absurd
## one.
##
## Materials are unshaded, double sided and ignore the depth buffer so the
## document cannot hide a handle. The per-axis render priority is rewritten
## from camera-space depth every frame, so the nearer axis draws over the
## farther one: real inter-axis depth, not sorted guesses.

## On-screen arm length in dp at gizmo_scale 1.0.
const BASE_ARM_DP := 92.0
const MIN_ARM_DP := 72.0
const MAX_ARM_DP := 160.0
const AXES := ["x", "y", "z"]
const AXIS_NAMES := {"x": "AxisX", "y": "AxisY", "z": "AxisZ"}
const RING_RADIUS := 0.74

var _tool := "move"
var _axis_groups: Dictionary = {}
var _materials: Dictionary = {}
var _arc_materials: Dictionary = {}
var _arc_instances: Dictionary = {}
var _priorities: Dictionary = {}
var _center_material: StandardMaterial3D
var _active_axis := ""
var _hover_axis := ""
## Held while a capture probe renders, so the per-frame rebuild cannot
## resurrect chrome into an export.
var _suppressed := false
## Pixels per UI unit for the stage viewport. EditorView writes this so the
## screen-size formula can use the real SubViewport resolution and still keep
## the arm in dp instead of physical pixels.
var px_per_dp := 1.0


func _ready() -> void:
	_build()


func _build() -> void:
	if not _axis_groups.is_empty():
		return
	for axis in AXES:
		_materials[axis] = _make_material(_axis_color(axis))
		_arc_materials[axis] = _make_material(_bright_color(_axis_color(axis)))
	var center := Node3D.new()
	center.name = "Center"
	add_child(center)
	_center_material = _make_material(Kit.TEXT_MUTED)
	var center_sphere := SphereMesh.new()
	center_sphere.radius = 0.10
	center_sphere.height = 0.20
	var move_center := _mesh_instance(center_sphere, _center_material)
	move_center.name = "CenterSphereMove"
	move_center.set_meta("mode", "move")
	center.add_child(move_center)
	var rotate_center := _mesh_instance(center_sphere, _center_material)
	rotate_center.name = "CenterSphereRotate"
	rotate_center.set_meta("mode", "rotate")
	center.add_child(rotate_center)
	var center_cube_mesh := BoxMesh.new()
	center_cube_mesh.size = Vector3(0.17, 0.17, 0.17)
	var scale_center := _mesh_instance(center_cube_mesh, _center_material)
	scale_center.name = "CenterCubeScale"
	scale_center.set_meta("mode", "scale")
	center.add_child(scale_center)

	for axis in AXES:
		var group := Node3D.new()
		group.name = AXIS_NAMES[axis]
		add_child(group)
		_axis_groups[axis] = group
		var material: StandardMaterial3D = _materials[axis]
		# Move: tapered shaft + a clear cone arrowhead ending on the 1.0 tip.
		var move_shaft := _cylinder(0.062, 0.042, 0.66)
		var shaft_instance := _mesh_instance(move_shaft, material)
		shaft_instance.name = "MoveShaft"
		shaft_instance.set_meta("mode", "move")
		group.add_child(shaft_instance)
		_place_on_axis(shaft_instance, axis, 0.33)
		var move_tip := _cylinder(0.13, 0.0, 0.34)
		var tip_instance := _mesh_instance(move_tip, material)
		tip_instance.name = "MoveTip"
		tip_instance.set_meta("mode", "move")
		group.add_child(tip_instance)
		_place_on_axis(tip_instance, axis, 0.83)
		# Rotate: a full torus ring plus a brighter front arc segment that
		# always turns towards the camera, so the ring reads as a circle in
		# space and the near side is unmistakable.
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = RING_RADIUS - 0.070
		ring_mesh.outer_radius = RING_RADIUS + 0.070
		ring_mesh.rings = 64
		ring_mesh.ring_segments = 12
		var ring_instance := _mesh_instance(ring_mesh, material)
		ring_instance.name = "RotateRing"
		ring_instance.set_meta("mode", "rotate")
		group.add_child(ring_instance)
		_orient_to_axis(ring_instance, axis)
		var arc_instance := _mesh_instance(_make_front_arc(axis), _arc_materials[axis])
		arc_instance.name = "RotateFrontArc"
		arc_instance.set_meta("mode", "rotate")
		group.add_child(arc_instance)
		_arc_instances[axis] = arc_instance
		# Scale: tapered shaft + cube tip.
		var scale_shaft := _cylinder(0.055, 0.038, 0.72)
		var scale_shaft_instance := _mesh_instance(scale_shaft, material)
		scale_shaft_instance.name = "ScaleShaft"
		scale_shaft_instance.set_meta("mode", "scale")
		group.add_child(scale_shaft_instance)
		_place_on_axis(scale_shaft_instance, axis, 0.36)
		var cube_mesh := BoxMesh.new()
		cube_mesh.size = Vector3(0.20, 0.20, 0.20)
		var cube_instance := _mesh_instance(cube_mesh, material)
		cube_instance.name = "ScaleTip"
		cube_instance.set_meta("mode", "scale")
		group.add_child(cube_instance)
		_place_on_axis(cube_instance, axis, 0.88)
	set_tool(_tool)
	_apply_colors()
	set_visible_gizmo(false)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.disable_receive_shadows = true
	material.render_priority = 1
	return material


func _axis_color(axis: String) -> Color:
	match axis:
		"x":
			return Kit.AXIS_X
		"y":
			return Kit.AXIS_Y
		"z":
			return Kit.AXIS_Z
	return Kit.TEXT_MUTED


func _bright_color(color: Color) -> Color:
	return color.lightened(0.34)


## The ring plane basis for one axis. The front arc is generated directly in
## this basis, so its spin around the axis is a single quaternion multiply.
func _ring_basis(axis: String) -> Array:
	match axis:
		"x":
			return [Vector3.UP, Vector3.BACK]
		"y":
			return [Vector3.RIGHT, Vector3.BACK]
	return [Vector3.RIGHT, Vector3.UP]


## Torus segment: 150 degrees of tube around the ring, centred on the basis a
## vector, rebuilt once per axis in gizmo-local space.
func _make_front_arc(axis: String) -> ArrayMesh:
	var basis: Array = _ring_basis(axis)
	var a: Vector3 = basis[0]
	var b: Vector3 = basis[1]
	var axis_vec := _axis_vector(axis)
	var arc := deg_to_rad(150.0)
	var segments := 20
	var tube_segments := 8
	var radius := RING_RADIUS
	var tube := 0.085
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := arc * 0.5
	for i in range(segments):
		var t0 := -half + arc * float(i) / float(segments)
		var t1 := -half + arc * float(i + 1) / float(segments)
		for j in range(tube_segments):
			var p0 := TAU * float(j) / float(tube_segments)
			var p1 := TAU * float(j + 1) / float(tube_segments)
			var q00 := _arc_point(a, b, axis_vec, radius, tube, t0, p0)
			var q10 := _arc_point(a, b, axis_vec, radius, tube, t1, p0)
			var q01 := _arc_point(a, b, axis_vec, radius, tube, t0, p1)
			var q11 := _arc_point(a, b, axis_vec, radius, tube, t1, p1)
			for vertex in [q00, q10, q01, q01, q10, q11]:
				st.add_vertex(vertex)
	return st.commit()


func _arc_point(a: Vector3, b: Vector3, axis_vec: Vector3, radius: float, tube: float, theta: float, phi: float) -> Vector3:
	var ring := radius + tube * cos(phi)
	return a * (ring * cos(theta)) + b * (ring * sin(theta)) + axis_vec * (tube * sin(phi))


func _cylinder(bottom_radius: float, top_radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 18
	mesh.rings = 1
	return mesh


func _mesh_instance(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _axis_vector(axis: String) -> Vector3:
	match axis:
		"x":
			return Vector3.RIGHT
		"y":
			return Vector3.UP
		"z":
			return Vector3.BACK
	return Vector3.ZERO


## Cylinders and cones are built along +Y, so the axis becomes a rotation.
func _orient_to_axis(instance: Node3D, axis: String) -> void:
	match axis:
		"x":
			instance.rotation_degrees = Vector3(0, 0, -90)
		"z":
			instance.rotation_degrees = Vector3(90, 0, 0)
		_:
			instance.rotation_degrees = Vector3.ZERO


func _place_on_axis(instance: Node3D, axis: String, distance: float) -> void:
	instance.position = _axis_vector(axis) * distance
	_orient_to_axis(instance, axis)


func set_tool(tool: String) -> void:
	_tool = tool if tool == "move" or tool == "rotate" or tool == "scale" else "move"
	for child in get_children():
		if not (child is Node3D):
			continue
		var group := child as Node3D
		for part in group.get_children():
			var mesh_instance := part as MeshInstance3D
			if mesh_instance == null:
				continue
			mesh_instance.visible = str(mesh_instance.get_meta("mode", "")) == _tool


## Active (being dragged) wins over hover; both brighten the axis colour so
## the tint stays inside the axis palette instead of introducing a new hue.
func set_active_axis(axis: String) -> void:
	if axis == _active_axis:
		return
	_active_axis = axis
	_apply_colors()


func set_hover_axis(axis: String) -> void:
	if axis == _hover_axis:
		return
	_hover_axis = axis
	_apply_colors()


func _apply_colors() -> void:
	for key in AXES:
		var base := _axis_color(key)
		var color := base
		if key == _active_axis:
			color = _bright_color(base).lerp(Color.WHITE, 0.14)
		elif key == _hover_axis:
			color = _bright_color(base)
		var material: StandardMaterial3D = _materials.get(key, null)
		if material != null:
			material.albedo_color = color
		var arc_material: StandardMaterial3D = _arc_materials.get(key, null)
		if arc_material != null:
			arc_material.albedo_color = (
				_bright_color(base).lerp(Color.WHITE, 0.2)
				if key == _active_axis
				else _bright_color(base)
			)
	if _center_material != null:
		_center_material.albedo_color = (
			_bright_color(Kit.TEXT_MUTED) if _active_axis == "free" or _hover_axis == "free"
			else Kit.TEXT_MUTED
		)


## Position the gizmo at a world origin and give it a constant screen size.
## `viewport_height` is the real SubViewport height in pixels. The effective
## arm is clamped between MIN_ARM_DP and MAX_ARM_DP dp before the camera FOV
## turns it into world units.
func set_target(origin: Vector3, camera: Camera3D, viewport_height: int, gizmo_scale: float) -> void:
	if camera == null:
		return
	global_position = origin
	var depth := -(camera.global_transform.basis.z).dot(origin - camera.global_position)
	depth = maxf(0.05, depth)
	var height := maxf(1.0, float(viewport_height))
	var arm_dp := clampf(BASE_ARM_DP * maxf(0.01, gizmo_scale), MIN_ARM_DP, MAX_ARM_DP)
	var target_px := arm_dp * maxf(0.01, px_per_dp)
	var world := target_px * 2.0 * tan(deg_to_rad(camera.fov) * 0.5) * depth / height
	scale = Vector3.ONE * clampf(world, 0.0001, 10000.0)
	_update_render_priorities(camera)
	_face_front_arcs(camera)


## Turn each rotate ring's bright arc towards the camera so the near side of
## the ring is always obvious.
func _face_front_arcs(camera: Camera3D) -> void:
	if _tool != "rotate" or _arc_instances.is_empty():
		return
	var direction := camera.global_position - global_position
	if direction.length_squared() < 0.0000001:
		return
	direction = direction.normalized()
	for axis in AXES:
		var arc: MeshInstance3D = _arc_instances.get(axis, null)
		if arc == null:
			continue
		var basis: Array = _ring_basis(axis)
		var angle := atan2(direction.dot(basis[1]), direction.dot(basis[0]))
		var spin := 1.0 if axis == "x" or axis == "z" else -1.0
		arc.quaternion = Quaternion(_axis_vector(axis), spin * angle)


func set_visible_gizmo(on: bool) -> void:
	visible = on and not _suppressed


## Suppression outranks every visibility request until it is cleared, which is
## what keeps the gizmo out of a still and every sequence frame.
func set_suppressed(on: bool) -> void:
	_suppressed = on
	if on:
		visible = false


func _update_render_priorities(camera: Camera3D) -> void:
	var entries: Array = []
	for axis in AXES:
		var tip := axis_tip_world(axis)
		var depth := -(camera.global_transform.basis.z).dot(tip - camera.global_position)
		entries.append({"axis": axis, "depth": depth})
	entries.sort_custom(func(a, b) -> bool:
		if is_equal_approx(float(a["depth"]), float(b["depth"])):
			return AXES.find(str(a["axis"])) < AXES.find(str(b["axis"]))
		return float(a["depth"]) > float(b["depth"])
	)
	for index in entries.size():
		var axis := str(entries[index]["axis"])
		_priorities[axis] = index + 1
		var material: StandardMaterial3D = _materials.get(axis, null)
		if material != null:
			material.render_priority = index + 1
		var arc_material: StandardMaterial3D = _arc_materials.get(axis, null)
		if arc_material != null:
			arc_material.render_priority = index + 1


func axis_group(axis: String) -> Node3D:
	return _axis_groups.get(axis, null)


func axis_material(axis: String) -> Material:
	return _materials.get(axis, null)


func axis_render_priority(axis: String) -> int:
	return int(_priorities.get(axis, 0))


func axis_tip_world(axis: String) -> Vector3:
	return to_global(_axis_vector(axis))


## One point of the projected torus ring, before projection. The editor samples
## 32 of these per axis so a tap on the visible ring selects that axis.
func ring_point_world(axis: String, angle: float) -> Vector3:
	var basis: Array = _ring_basis(axis)
	return to_global((basis[0] * cos(angle) + basis[1] * sin(angle)) * RING_RADIUS)


func tool_name() -> String:
	return _tool
