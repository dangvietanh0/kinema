extends Control
## 116x116 navigation gizmo for the stage HUD.
##
## A transparent SubViewport with its own World3D and an orthographic camera
## renders three real 3D axis arrows mirrored from the editor camera's yaw and
## pitch. X/Y/Z labels are drawn in 2D at the projected positive tips, so they
## stay crisp at every display density and never become billboard text meshes.
## Only the three 44 dp positive tips take input; every other tap falls through
## to the stage so it cannot steal an orbit gesture.

signal view_requested(label: String)

const AXES := ["x", "y", "z"]
const AXIS_NAMES := {"x": "AxisX", "y": "AxisY", "z": "AxisZ"}
const AXIS_LABELS := {"x": "X", "y": "Y", "z": "Z"}
const PRESETS := {"x": "Right", "y": "Top", "z": "Front"}
const GIZMO_SIZE := 116.0
const TIP_RADIUS := 22.0
const ORTHO_SIZE := 2.8
const LABEL_SIZE := 12
## Distance in dp between the arrowhead apex and the nearest edge of a label.
const LABEL_GAP := 9.0
## Minimum dp gap between two label rectangles.
const LABEL_MARGIN := 1.0

var px_per_dp := 1.0

var _viewport: SubViewport
var _camera: Camera3D
var _texture: TextureRect
var _axes_root: Node3D
var _axis_groups: Dictionary = {}
var _materials: Dictionary = {}
var _muted_materials: Dictionary = {}
var _tip_points: Dictionary = {}
var _label_points: Dictionary = {}
var _orientation_set := false


func _ready() -> void:
	custom_minimum_size = Vector2(GIZMO_SIZE, GIZMO_SIZE)
	size = Vector2(GIZMO_SIZE, GIZMO_SIZE)
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	_build_viewport()
	_build_axes()
	set_orientation(deg_to_rad(38.0), deg_to_rad(18.0))


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "NavViewport"
	_viewport.size = _pixel_size()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.world_3d = World3D.new()
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)

	_texture = TextureRect.new()
	_texture.name = "NavTexture"
	_texture.texture = _viewport.get_texture()
	_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture.stretch_mode = TextureRect.STRETCH_SCALE
	_texture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The 3D arrows draw behind the parent so the 2D labels, painted by this
	# control's own _draw(), stay on top of the image.
	_texture.show_behind_parent = true
	_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_texture)

	_camera = Camera3D.new()
	_camera.name = "NavCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = ORTHO_SIZE
	_camera.near = 0.01
	_camera.far = 20.0
	_camera.current = true
	_viewport.add_child(_camera)


func _build_axes() -> void:
	_axes_root = Node3D.new()
	_axes_root.name = "Axes"
	_viewport.add_child(_axes_root)
	for axis in AXES:
		var color := _axis_color(axis)
		_materials[axis] = _make_material(color, 1)
		_muted_materials[axis] = _make_material(color.lerp(Kit.TEXT_DIM, 0.72), 0)
		var group := Node3D.new()
		group.name = AXIS_NAMES[axis]
		_axes_root.add_child(group)
		_axis_groups[axis] = group
		var material: StandardMaterial3D = _materials[axis]
		# Positive arm: the labelled control. A tapered shaft ends at 0.74 and
		# the cone apex sits exactly on the 1.0 unit tip used for projection
		# and taps, so the label and the arrowhead agree.
		var shaft := _cylinder(0.030, 0.050, 0.74)
		var shaft_instance := _mesh_instance(shaft, material)
		shaft_instance.name = "PositiveShaft"
		group.add_child(shaft_instance)
		_place_on_axis(shaft_instance, axis, 0.37)
		var cone := _cylinder(0.0, 0.12, 0.30)
		var cone_instance := _mesh_instance(cone, material)
		cone_instance.name = "PositiveTip"
		group.add_child(cone_instance)
		_place_on_axis(cone_instance, axis, 0.85)
		# Negative end: smaller and muted, never a second tap target.
		var tail := _cylinder(0.020, 0.034, 0.30)
		var tail_instance := _mesh_instance(tail, _muted_materials[axis])
		tail_instance.name = "NegativeShaft"
		group.add_child(tail_instance)
		_place_on_axis(tail_instance, axis, -0.15)
		var tail_tip_mesh := SphereMesh.new()
		tail_tip_mesh.radius = 0.06
		tail_tip_mesh.height = 0.12
		var tail_tip := _mesh_instance(tail_tip_mesh, _muted_materials[axis])
		tail_tip.name = "NegativeTip"
		group.add_child(tail_tip)
		_place_on_axis(tail_tip, axis, -0.36)


func _make_material(color: Color, priority: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.render_priority = priority
	material.disable_receive_shadows = true
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


func _axis_vector(axis: String) -> Vector3:
	match axis:
		"x":
			return Vector3.RIGHT
		"y":
			return Vector3.UP
		"z":
			return Vector3.BACK
	return Vector3.ZERO


func _cylinder(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 14
	mesh.rings = 1
	return mesh


func _mesh_instance(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _place_on_axis(instance: Node3D, axis: String, distance: float) -> void:
	instance.position = _axis_vector(axis) * distance
	match axis:
		"x":
			instance.rotation_degrees = Vector3(0, 0, -90)
		"z":
			instance.rotation_degrees = Vector3(90, 0, 0)
		_:
			instance.rotation_degrees = Vector3.ZERO


func _pixel_size() -> Vector2i:
	var px := maxi(1, int(round(GIZMO_SIZE * px_per_dp)))
	return Vector2i(px, px)


## The control stays 116 dp; only the off-screen render resolution follows the
## device density, matching the stage SubViewport. A 2x/3x phone then shows a
## crisp gizmo instead of an upscaled 116 px image.
func set_pixel_density(value: float) -> void:
	var density := clampf(value, 1.0, 4.0)
	if is_equal_approx(density, px_per_dp):
		return
	px_per_dp = density
	if _viewport == null:
		return
	var px := _pixel_size()
	if _viewport.size != px:
		_viewport.size = px
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_update_tips()
	queue_redraw()


## Mirror the editor camera orbit direction. Called only when yaw or pitch
## actually changes, so the SubViewport renders once per camera change.
func set_orientation(yaw: float, pitch: float) -> void:
	if _camera == null:
		return
	var direction := Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw)
	)
	if direction.length() < 0.0001:
		direction = Vector3.BACK
	direction = direction.normalized()
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.995:
		up = Vector3.BACK
	_camera.global_position = direction * 4.0
	_camera.look_at(Vector3.ZERO, up)
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_orientation_set = true
	_update_tips()
	queue_redraw()


func _update_tips() -> void:
	if _camera == null or _viewport == null or _viewport.size.x <= 0 or _viewport.size.y <= 0:
		return
	var tips := {}
	for axis in AXES:
		# unproject_position() is in SubViewport pixels; the Control paints in
		# dp, so divide by the same density the viewport rendered at.
		tips[axis] = _camera.unproject_position(_axis_vector(axis)) / px_per_dp
	for axis in AXES:
		_tip_points[axis] = tips[axis]
	_layout_labels(tips)


func _head_disc(tip: Vector2) -> Array:
	var centre := Vector2(GIZMO_SIZE, GIZMO_SIZE) * 0.5
	var arm := tip - centre
	# The cone occupies the last 30% of the positive arm, so its centre sits at
	# 0.85 and its radius follows the projected arm length.
	return [centre + arm * 0.85, arm.length() * 0.12 + 2.0]


## Shortest gap between two axis-aligned rectangles; zero when they overlap.
func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy := maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return sqrt(dx * dx + dy * dy)


## How much room a candidate has before it touches a head disc or a label that
## was already placed. Negative means it collides with one of them.
func _label_clearance(rect: Rect2, heads: Dictionary, placed: Dictionary) -> float:
	var clearance := INF
	for axis in AXES:
		var head: Array = heads[axis]
		var head_centre: Vector2 = head[0]
		var head_radius: float = head[1]
		var closest := Vector2(
			clampf(head_centre.x, rect.position.x, rect.end.x),
			clampf(head_centre.y, rect.position.y, rect.end.y))
		clearance = minf(clearance, head_centre.distance_to(closest) - head_radius)
	for axis in placed:
		clearance = minf(clearance, _rect_gap(rect, placed[axis]) - LABEL_MARGIN)
	return clearance


func _label_rect_at(anchor: Vector2, text_size: Vector2) -> Rect2:
	var pos := Vector2(
		clampf(anchor.x - text_size.x * 0.5, 1.0, GIZMO_SIZE - text_size.x - 1.0),
		clampf(anchor.y - text_size.y * 0.5, 1.0, GIZMO_SIZE - text_size.y - 1.0))
	return Rect2(pos, text_size)


## Labels are laid out jointly, not one axis at a time in isolation. Every
## candidate must clear the control edges, all three axis heads (not just its
## own) and every label already placed. A negative-pitch orbit can project two
## axes close together, so the radial direction is only a preference; side and
## opposite offsets are tried before a dense scan gives up on the ideal ring.
func _layout_labels(tips: Dictionary) -> void:
	var heads := {}
	for axis in AXES:
		heads[axis] = _head_disc(tips[axis])
	var placed := {}
	var centre := Vector2(GIZMO_SIZE, GIZMO_SIZE) * 0.5
	for axis in AXES:
		var tip: Vector2 = tips[axis]
		var text := str(AXIS_LABELS[axis])
		var text_size := Kit.font_mono.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
		var outward := tip - centre
		if outward.length() < 1.0:
			outward = Vector2(0.62, -0.78)
		var base_angle := outward.angle()
		var gap := LABEL_GAP + maxf(text_size.x, text_size.y) * 0.5
		var best := _label_rect_at(tip + outward.normalized() * gap, text_size)
		var best_clearance := -INF
		var chosen := false
		var steps := [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 7, -7, 8, -8]
		var rings := [gap, gap + 6.0, gap + 12.0]
		for ring in rings:
			if chosen:
				break
			for step in steps:
				var angle := base_angle + PI * float(step) / 8.0
				var rect := _label_rect_at(
					tip + Vector2.from_angle(angle) * ring, text_size)
				var clearance := _label_clearance(rect, heads, placed)
				if clearance >= 0.0:
					best = rect
					chosen = true
					break
				if clearance > best_clearance:
					best_clearance = clearance
					best = rect
		if not chosen:
			# Last resort: scan the control for the clearest free spot. This
			# only runs when every radial and side ring is blocked.
			var step_size := 4.0
			var y := 1.0
			while y <= GIZMO_SIZE - text_size.y - 1.0 and not chosen:
				var x := 1.0
				while x <= GIZMO_SIZE - text_size.x - 1.0:
					var rect := Rect2(Vector2(x, y), text_size)
					var clearance := _label_clearance(rect, heads, placed)
					if clearance >= 0.0:
						best = rect
						chosen = true
						break
					if clearance > best_clearance:
						best_clearance = clearance
						best = rect
					x += step_size
				y += step_size
		_label_points[axis] = best.position
		placed[axis] = best


func tip_position(axis: String) -> Vector2:
	return _tip_points.get(axis, Vector2.ZERO)


func label_position(axis: String) -> Vector2:
	return _label_points.get(axis, Vector2.ZERO)


func axis_group(axis: String) -> Node3D:
	return _axis_groups.get(axis, null)


func _hit_tip(point: Vector2) -> String:
	var best := ""
	var best_distance := TIP_RADIUS
	for axis in AXES:
		var distance := point.distance_to(tip_position(axis))
		if distance <= best_distance:
			best_distance = distance
			best = axis
	return best


func _gui_input(event: InputEvent) -> void:
	if Kit.is_emulated_mouse(event):
		return
	var pressed := false
	var point := Vector2.ZERO
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		pressed = touch.pressed
		point = touch.position
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		pressed = button.pressed and button.button_index == MOUSE_BUTTON_LEFT
		point = button.position
	else:
		return
	if not pressed:
		return
	var axis := _hit_tip(point)
	if axis == "":
		# Not one of the three targets: let the stage own the gesture.
		return
	accept_event()
	view_requested.emit(str(PRESETS[axis]))


func _draw() -> void:
	if not _orientation_set:
		return
	# label_position() is the visual top-left used by the collision layout, so
	# move the baseline down by the font ascent instead of drawing above it.
	var ascent := Kit.font_mono.get_ascent(LABEL_SIZE)
	for axis in AXES:
		var point: Vector2 = _label_points.get(axis, Vector2.ZERO)
		var label := str(AXIS_LABELS[axis])
		# A dark shadow keeps the letter legible over the bright axis arrow.
		draw_string(
			Kit.font_mono,
			point + Vector2(1, 1 + ascent),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			LABEL_SIZE,
			Color(0.02, 0.02, 0.02, 0.9)
		)
		draw_string(
			Kit.font_mono,
			point + Vector2(0, ascent),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			LABEL_SIZE,
			_axis_color(axis)
		)
