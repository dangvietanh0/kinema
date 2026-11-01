extends Node
## Gizmo suite: the transform gizmo and the navigation gizmo are real 3D
## geometry inside the stage, not fixed-length screen-space symbols.
##
## Runs headless on Linux. Every assertion measures the projected geometry or
## the live scene tree; nothing here depends on a GPU draw pass.

const DocumentScript = preload("res://src/core/document.gd")
const EditorViewScript = preload("res://src/viewport/editor_view.gd")
const NavGizmoScript = preload("res://src/ui/components/nav_gizmo.gd")

const AXES := ["x", "y", "z"]
## On-screen arm in dp at gizmo_scale 1.0, and the clamps around it.
const MOVED_TIP := 92.0
const MIN_ARM := 72.0
const MAX_ARM := 160.0
const NAV_SIZE := 116.0
const CAPTURE_DIR := "/tmp/opencode/i4-followup"

var _failures: Array[String] = []
var _oks := 0
var _doc = null
var _view = null
var _gizmo = null
var _nav = null
var _id := ""


func _check(condition: bool, message: String) -> void:
	if condition:
		_oks += 1
		print("GIZMO OK: " + message)
	else:
		_failures.append(message)
		printerr("GIZMO FAIL: " + message)


func _main_ready() -> void:
	# The stretch mode is disabled, so pin a real canvas before building the
	# view. This is the short landscape stage the workbench has to survive.
	# Capture runs use the desktop stage so the 3D forms are easier to inspect.
	get_window().size = _capture_size() if _capture_requested() else Vector2i(915, 412)
	await get_tree().process_frame
	await get_tree().process_frame

	var root := Control.new()
	root.name = "GizmoStage"
	root.size = Vector2(get_window().size)
	add_child(root)

	# The view adopts the document into its stage viewport; the suite must not
	# parent it first or set_document cannot re-parent it.
	_doc = DocumentScript.new()
	_doc.new_project("Gizmo Suite")
	await get_tree().process_frame

	_view = EditorViewScript.new()
	_view.name = "View"
	root.add_child(_view)
	_view.size = root.size
	_view.set_document(_doc)
	for _i in 3:
		await get_tree().process_frame

	_id = str(_doc.selected_id)
	_gizmo = _view.get("_gizmo")
	_nav = _view.get("_nav_gizmo")


func _ready() -> void:
	await _main_ready()

	print("GIZMO STEP: transform gizmo geometry")
	await _test_transform_geometry()
	print("GIZMO STEP: placement and visibility")
	await _test_placement()
	print("GIZMO STEP: projected handles and drag")
	await _test_handles_and_drag()
	print("GIZMO STEP: rotate rings")
	await _test_rotate_rings()
	print("GIZMO STEP: constant screen size")
	await _test_constant_size()
	print("GIZMO STEP: size clamp and highlights")
	await _test_size_clamp_and_highlight()
	print("GIZMO STEP: render priority")
	await _test_render_priority()
	print("GIZMO STEP: navigation gizmo")
	await _test_nav_gizmo()
	print("GIZMO STEP: render mode")
	await _test_render_mode()

	if _capture_requested():
		print("GIZMO STEP: captures")
		await _capture_visuals()

	var status := "PASS" if _failures.is_empty() else "FAIL"
	print("GIZMO RESULT: %s (%d OK, %d FAIL)" % [status, _oks, _failures.size()])
	if not _failures.is_empty():
		for failure in _failures:
			printerr("  - " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

func _refresh() -> void:
	await get_tree().process_frame
	if _view != null and _view.has_method("_draw_gizmo"):
		_view._draw_gizmo()


func _select_default() -> void:
	if _doc != null and _doc.selected_id != _id:
		_doc.set_selection(_id)


func _handle_pos(axis_name: String) -> Vector2:
	if _view == null:
		return Vector2.INF
	for handle in _view._gizmo_handles:
		if str(handle.get("axis", "")) == axis_name:
			return handle.get("pos", Vector2.INF)
	return Vector2.INF


func _handles_for(axis_name: String) -> Array:
	var found: Array = []
	if _view == null:
		return found
	for handle in _view._gizmo_handles:
		if str(handle.get("axis", "")) == axis_name:
			found.append(handle.get("pos", Vector2.INF))
	return found


func _visible_meshes(group: Node) -> Array:
	var found: Array = []
	if group == null:
		return found
	for child in group.get_children():
		if child is MeshInstance3D and child.visible:
			found.append(child)
	return found


func _has_mesh_of(meshes: Array, type_name: String) -> bool:
	for mesh_instance in meshes:
		var mesh: Mesh = mesh_instance.mesh
		if mesh == null:
			continue
		if mesh.get_class() == type_name:
			return true
	return false


func _has_cone(meshes: Array) -> bool:
	for mesh_instance in meshes:
		var mesh: Mesh = mesh_instance.mesh
		if mesh is CylinderMesh:
			var cylinder := mesh as CylinderMesh
			if is_zero_approx(cylinder.top_radius) and cylinder.bottom_radius > 0.0:
				return true
	return false


func _axis_world(axis_name: String) -> Vector3:
	match axis_name:
		"x":
			return Vector3.RIGHT
		"y":
			return Vector3.UP
		"z":
			return Vector3.BACK
	return Vector3.ZERO


func _nearest_axis_name() -> String:
	var camera: Camera3D = _view._camera
	var best := ""
	var best_depth := INF
	for axis_name in AXES:
		var tip: Vector3 = _gizmo.axis_tip_world(axis_name)
		var depth: float = -(camera.global_transform.basis.z).dot(tip - camera.global_position)
		if depth < best_depth:
			best_depth = depth
			best = axis_name
	return best


# -------------------------------------------------------------------------
# Transform gizmo
# -------------------------------------------------------------------------

func _test_transform_geometry() -> void:
	_check(_gizmo != null, "transform gizmo node exists under the stage SubViewport")
	if _gizmo == null:
		return
	_check(_gizmo.get_parent() == _view._viewport, "the transform gizmo is parented to the stage SubViewport")
	_check(_gizmo.get_parent() != _doc, "the transform gizmo is not parented to the document")

	_select_default()
	_view.set_tool("move")
	await _refresh()
	for axis_name in AXES:
		var group: Node = _gizmo.axis_group(axis_name)
		var expected: String = "Axis" + str(axis_name).to_upper()
		_check(group != null and group.name == expected, "move mode exposes the %s axis group" % expected)
		var meshes := _visible_meshes(group)
		_check(meshes.size() >= 2, "move %s has a shaft and a tip MeshInstance3D" % axis_name.to_upper())
		_check(_has_mesh_of(meshes, "CylinderMesh"), "move %s uses cylinder geometry" % axis_name.to_upper())
		_check(_has_cone(meshes), "move %s has a cone tip" % axis_name.to_upper())
	var center: Node = _gizmo.get_node_or_null("Center")
	var center_meshes := _visible_meshes(center)
	_check(center_meshes.size() >= 1, "move mode shows a centre handle")
	_check(_has_mesh_of(center_meshes, "SphereMesh"), "the move centre handle is a sphere")

	_view.set_tool("rotate")
	await _refresh()
	for axis_name in AXES:
		var meshes := _visible_meshes(_gizmo.axis_group(axis_name))
		_check(_has_mesh_of(meshes, "TorusMesh"), "rotate %s uses a torus ring" % axis_name.to_upper())
	_check(_has_mesh_of(_visible_meshes(_gizmo.get_node_or_null("Center")), "SphereMesh"),
		"the rotate centre handle is a sphere")

	_view.set_tool("scale")
	await _refresh()
	for axis_name in AXES:
		var meshes := _visible_meshes(_gizmo.axis_group(axis_name))
		_check(_has_mesh_of(meshes, "BoxMesh"), "scale %s has a cube tip" % axis_name.to_upper())
	_check(_has_mesh_of(_visible_meshes(_gizmo.get_node_or_null("Center")), "BoxMesh"),
		"the scale centre handle is a cube")

	# Materials: unshaded, no depth test, cull disabled, axis colours.
	for axis_name in AXES:
		var material: Material = _gizmo.axis_material(axis_name)
		var standard := material as StandardMaterial3D
		_check(standard != null, "%s has a StandardMaterial3D" % axis_name.to_upper())
		if standard == null:
			continue
		_check(standard.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
			"%s material is unshaded" % axis_name.to_upper())
		_check(standard.no_depth_test, "%s material ignores depth so the stage cannot hide it" % axis_name.to_upper())
		_check(standard.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"%s material is double sided on the stage" % axis_name.to_upper())
	var expected_colors := {"x": Kit.AXIS_X, "y": Kit.AXIS_Y, "z": Kit.AXIS_Z}
	for axis_name in AXES:
		var standard := _gizmo.axis_material(axis_name) as StandardMaterial3D
		if standard == null:
			continue
		_check(standard.albedo_color.is_equal_approx(expected_colors[axis_name]),
			"%s keeps the axis colour" % axis_name.to_upper())


func _test_placement() -> void:
	if _gizmo == null:
		return
	_select_default()
	_view.set_tool("move")
	await _refresh()
	var node: Node3D = _doc.get_selected_node()
	_check(node != null, "the suite has a selected object")
	if node == null:
		return
	_check(_gizmo.global_position.distance_to(node.global_position) < 0.0001,
		"the gizmo is positioned at the selected object's world origin")
	_check(_gizmo.visible, "the gizmo is visible for Move with a selection")

	_view.set_tool("select")
	await _refresh()
	_check(not _gizmo.visible, "the gizmo is hidden for the Select tool")

	_view.set_tool("move")
	await _refresh()
	_check(_gizmo.visible, "the gizmo returns for Move")

	var keep: String = _doc.selected_id
	_doc.set_selection("")
	await _refresh()
	_check(not _gizmo.visible, "the gizmo is hidden without a selection")
	_doc.set_selection(keep)
	await _refresh()
	_check(_gizmo.visible, "the gizmo returns after the selection is restored")


func _test_handles_and_drag() -> void:
	if _gizmo == null:
		return
	_select_default()
	_view.set_tool("move")
	await _refresh()

	var origin := _handle_pos("free")
	var tip := _handle_pos("x")
	_check(origin != Vector2.INF and tip != Vector2.INF, "move mode projects a centre and an X handle")
	if origin == Vector2.INF or tip == Vector2.INF:
		return
	_check(_view._hit_gizmo(tip) == "x", "a tap on the projected X tip hits the X axis")
	for axis_name in AXES:
		var axis_tip := _handle_pos(axis_name)
		_check(axis_tip != Vector2.INF and _view._hit_gizmo(axis_tip) == axis_name,
			"a tap on the projected %s tip hits that axis" % axis_name.to_upper())

	# The hit target scales with the visual: at least the 22 px floor, and
	# wider for the larger arm. Inside the radius hits, beyond it misses.
	var radius: float = _view.gizmo_hit_radius()
	_check(radius >= 22.0, "the hit radius keeps the 22 px floor")
	_check(radius > 22.0, "the hit radius scales with the larger gizmo")
	var direction := (tip - origin).normalized()
	_check(_view._hit_gizmo(tip + direction * (radius - 1.0)) == "x",
		"the hit target reaches the full radius around the tip")
	var outside := Vector2.INF
	for degrees in range(0, 360, 5):
		var candidate: Vector2 = tip + Vector2.RIGHT.rotated(deg_to_rad(float(degrees))) * (radius + 8.0)
		var clear := true
		for handle in _view._gizmo_handles:
			if candidate.distance_to(handle.get("pos", Vector2.ZERO)) <= radius + 1.0:
				clear = false
				break
		if clear:
			outside = candidate
			break
	_check(outside != Vector2.INF and _view._hit_gizmo(outside) == "",
		"a point beyond the hit radius misses every handle")

	var before: Vector3 = _doc.get_selected_node().position
	var snap_was: bool = _doc.snap
	_doc.snap = false
	_view._start_gizmo("x", tip)
	_view._apply_gizmo_drag(Vector2(24, 0))
	var after: Vector3 = _doc.get_selected_node().position
	_view._finish_gizmo()
	_doc.snap = snap_was
	_check(absf(after.x - before.x) > 0.0001, "a drag on the projected X tip changes the node position")
	_check(absf(after.y - before.y) < 0.0001 and absf(after.z - before.z) < 0.0001,
		"an X drag leaves the other axes untouched")

	_view.set_tool("scale")
	await _refresh()
	for axis_name in AXES:
		var scale_tip := _handle_pos(axis_name)
		_check(scale_tip != Vector2.INF and _view._hit_gizmo(scale_tip) == axis_name,
			"a tap on the projected scale %s tip hits that axis" % axis_name.to_upper())


func _test_rotate_rings() -> void:
	if _gizmo == null:
		return
	_select_default()
	_view.set_tool("rotate")
	await _refresh()
	for axis_name in AXES:
		var samples := _handles_for(axis_name)
		_check(samples.size() == 32, "rotate %s exposes 32 ring samples" % axis_name.to_upper())
		var hits := 0
		for sample in samples:
			if _view._hit_gizmo(sample) == axis_name:
				hits += 1
		_check(hits > 0, "a tap on the projected %s ring hits that axis" % axis_name.to_upper())
	_check(_handle_pos("free") != Vector2.INF, "rotate mode keeps the centre free handle")


func _test_constant_size() -> void:
	if _gizmo == null:
		return
	_select_default()
	_view.set_tool("move")
	# Look straight down the Z axis so X projects without foreshortening; the
	# gizmo then must keep its base arm at any camera distance.
	_view.set_view_preset("Front")
	_view.gizmo_scale = 1.0
	var arms: Array[float] = []
	for camera_distance in [6.0, 14.0]:
		_view.distance = camera_distance
		await get_tree().process_frame
		await _refresh()
		var origin := _handle_pos("free")
		var tip := _handle_pos("x")
		_check(origin != Vector2.INF and tip != Vector2.INF,
			"the X arm projects at %.0f m" % camera_distance)
		if origin == Vector2.INF or tip == Vector2.INF:
			return
		arms.append(origin.distance_to(tip))
	for index in arms.size():
		_check(absf(arms[index] - MOVED_TIP) <= 6.0,
			"the gizmo arm stays within 6 dp of %d dp at distance #%d (%.1f dp)" % [int(MOVED_TIP), index + 1, arms[index]])
	if arms.size() == 2:
		_check(absf(arms[0] - arms[1]) <= 6.0, "the arm length is constant across camera distances")
	# The Z arm points at the Front camera, so real perspective must collapse
	# it instead of drawing a fixed 48 dp line.
	var origin := _handle_pos("free")
	var z_tip := _handle_pos("z")
	_check(z_tip != Vector2.INF and origin.distance_to(z_tip) < 2.0,
		"the axis aligned with the view collapses instead of keeping a fixed arm")


func _arm_length() -> float:
	var origin := _handle_pos("free")
	var tip := _handle_pos("x")
	if origin == Vector2.INF or tip == Vector2.INF:
		return -1.0
	return origin.distance_to(tip)


func _test_size_clamp_and_highlight() -> void:
	if _gizmo == null:
		return
	_select_default()
	_view.set_tool("move")
	_view.set_view_preset("Front")
	# Base size at gizmo_scale 1.0, then both clamps.
	_view.set_gizmo_scale(1.0)
	await _refresh()
	var base_arm := _arm_length()
	_check(absf(base_arm - MOVED_TIP) <= 6.0, "gizmo_scale 1.0 gives the %.0f dp base arm (%.1f dp)" % [MOVED_TIP, base_arm])
	_view.set_gizmo_scale(0.5)
	await _refresh()
	var small_arm := _arm_length()
	_check(absf(small_arm - MIN_ARM) <= 6.0,
		"a small setting still gets a usable arm of at least %.0f dp (%.1f dp)" % [MIN_ARM, small_arm])
	_view.set_gizmo_scale(2.0)
	await _refresh()
	var large_arm := _arm_length()
	_check(large_arm <= MAX_ARM + 6.0,
		"a large setting never exceeds %.0f dp (%.1f dp)" % [MAX_ARM, large_arm])
	_check(_view.gizmo_scale >= 0.5 and _view.gizmo_scale <= 2.0,
		"the settings range for gizmo_scale is preserved")
	_view.set_gizmo_scale(1.0)
	await _refresh()

	# Hover and active highlights stay inside the axis colour.
	var material := _gizmo.axis_material("x") as StandardMaterial3D
	if material == null:
		_check(false, "the X axis material exists")
		return
	var idle := material.albedo_color
	_check(idle.is_equal_approx(Kit.AXIS_X), "an idle axis keeps the exact axis colour")
	_view._hover_axis = "x"
	_view._draw_gizmo()
	_check(material.albedo_color.get_luminance() > idle.get_luminance(),
		"hovering brightens the axis")
	_view._hover_axis = ""
	_view._draw_gizmo()
	_check(material.albedo_color.is_equal_approx(idle), "clearing hover restores the axis colour")
	var tip := _handle_pos("x")
	_view._start_gizmo("x", tip if tip != Vector2.INF else Vector2.ZERO)
	_view._draw_gizmo()
	_check(material.albedo_color.get_luminance() > idle.get_luminance(),
		"an active drag brightens the axis further")
	_view._finish_gizmo()
	_view._draw_gizmo()
	_check(material.albedo_color.is_equal_approx(idle), "finishing the drag restores the axis colour")

	# Rotate mode keeps the ring and adds a real front arc aimed at the camera.
	_view.set_tool("rotate")
	_view.set_view_preset("Front")
	await _refresh()
	var to_camera: Vector3 = (_view._camera.global_position - _gizmo.global_position).normalized()
	for axis_name in ["x", "y"]:
		var group: Node = _gizmo.axis_group(axis_name)
		var arc: Node = group.get_node_or_null("RotateFrontArc") if group != null else null
		_check(arc is MeshInstance3D and arc.visible,
			"rotate %s shows a front arc mesh" % axis_name.to_upper())
		if arc == null:
			continue
		var centre: Vector3 = arc.global_transform.basis * _gizmo._ring_basis(axis_name)[0]
		_check(centre.normalized().dot(to_camera) > 0.5,
			"the %s front arc turns towards the camera" % axis_name.to_upper())


func _test_render_priority() -> void:
	if _gizmo == null:
		return
	_select_default()
	_view.set_tool("move")
	_view.set_view_preset("Front")
	await _refresh()
	var priorities := {}
	for axis_name in AXES:
		priorities[axis_name] = int(_gizmo.axis_render_priority(axis_name))
	var values: Array = priorities.values()
	values.sort()
	_check(values[0] != values[1] and values[1] != values[2],
		"every axis has a distinct render priority")
	var nearest := _nearest_axis_name()
	_check(nearest == "z", "the Front camera puts Z nearest")
	_check(priorities[nearest] == values[2], "the nearest axis has the highest render priority")

	_view.set_view_preset("Right")
	await _refresh()
	var moved := {}
	for axis_name in AXES:
		moved[axis_name] = int(_gizmo.axis_render_priority(axis_name))
	var moved_nearest := _nearest_axis_name()
	_check(moved_nearest == "x", "the Right camera puts X nearest")
	_check(moved[moved_nearest] == 3, "the nearest axis draws on top after the camera moves")
	_check(moved["x"] != moved["z"], "a camera move changes the draw order")


# -------------------------------------------------------------------------
# Navigation gizmo
# -------------------------------------------------------------------------

func _test_nav_gizmo() -> void:
	_check(_nav != null, "navigation gizmo exists")
	if _nav == null:
		return
	_check(_nav.size.is_equal_approx(Vector2(NAV_SIZE, NAV_SIZE)),
		"the navigation gizmo is %dx%d dp" % [int(NAV_SIZE), int(NAV_SIZE)])
	var nav_viewport: SubViewport = _nav._viewport
	_check(nav_viewport != null, "the navigation gizmo owns a SubViewport")
	if nav_viewport == null:
		return
	_check(nav_viewport.size == Vector2i(int(NAV_SIZE), int(NAV_SIZE)),
		"the navigation SubViewport is %dx%d" % [int(NAV_SIZE), int(NAV_SIZE)])
	_check(nav_viewport.transparent_bg, "the navigation SubViewport renders on a transparent background")
	_check(nav_viewport.world_3d != _view._viewport.world_3d,
		"the navigation gizmo has its own World3D")
	_check(_nav.mouse_filter == Control.MOUSE_FILTER_PASS,
		"the navigation gizmo is pointer-transparent outside its tips")
	for axis_name in AXES:
		var group: Node = _nav.axis_group(axis_name)
		_check(group != null and group.name == "Axis" + axis_name.to_upper(),
			"the navigation gizmo has a real %s axis group" % axis_name.to_upper())
		var meshes := _visible_meshes(group)
		_check(meshes.size() >= 2, "navigation %s uses real meshes" % axis_name.to_upper())
		_check(_has_mesh_of(meshes, "CylinderMesh"), "navigation %s has a cylinder shaft" % axis_name.to_upper())
		_check(_has_cone(meshes), "navigation %s has a cone tip" % axis_name.to_upper())
	_check(_nav.find_children("*", "Label3D", true, false).is_empty(),
		"the navigation gizmo uses no 3D text meshes")

	var presets := {"x": "Right", "y": "Top", "z": "Front"}
	for axis_name in AXES:
		_view.set_view_preset("Persp")
		await get_tree().process_frame
		_nav.set_orientation(_view.yaw, _view.pitch)
		await get_tree().process_frame
		var tip: Vector2 = _nav.tip_position(axis_name)
		var label_pos: Vector2 = _nav.label_position(axis_name)
		_check(Rect2(Vector2.ZERO, Vector2(NAV_SIZE, NAV_SIZE)).has_point(label_pos)
			and label_pos.x >= 0.0 and label_pos.x <= NAV_SIZE
			and label_pos.y >= 0.0 and label_pos.y <= NAV_SIZE,
			"the %s label stays inside the %dx%d control" % [axis_name.to_upper(), int(NAV_SIZE), int(NAV_SIZE)])
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = true
		event.position = tip
		_nav._gui_input(event)
		_check(_view.view_preset() == presets[axis_name],
			"tapping the %s tip sets the %s preset" % [axis_name.to_upper(), presets[axis_name]])

	# A tap away from every tip must not consume the gesture.
	var caught := [false]
	var listener := func(_label: String) -> void:
		caught[0] = true
	_nav.view_requested.connect(listener)
	var outside := InputEventScreenTouch.new()
	outside.index = 0
	outside.pressed = true
	outside.position = Vector2(2, 2)
	_nav._gui_input(outside)
	_nav.view_requested.disconnect(listener)
	_check(not caught[0], "a tap outside the tips emits no view request")
	_check(_nav._hit_tip(Vector2(2, 2)) == "", "a tap outside the tips hits no control")
	# The tip target is at least the 22 dp radius in both directions.
	_check(NavGizmoScript.TIP_RADIUS >= 22.0,
		"the navigation tip target keeps the 22 dp radius (%.0f dp)" % NavGizmoScript.TIP_RADIUS)
	var tip_hit: Vector2 = _nav.tip_position("y")
	_check(_nav._hit_tip(tip_hit) == "y", "a tap on the Y tip hits Y")
	_check(_nav._hit_tip(tip_hit + Vector2(NavGizmoScript.TIP_RADIUS - 1.0, 0)) == "y",
		"the tip target reaches its full radius")
	_check(_nav._hit_tip(tip_hit + Vector2(NavGizmoScript.TIP_RADIUS + 6.0, 0)) != "y",
		"a tap beyond the tip radius misses")


func _test_render_mode() -> void:
	if _gizmo == null:
		return
	_select_default()
	_view.set_tool("move")
	await _refresh()
	_check(_gizmo.visible, "the transform gizmo is visible before render mode")
	_view.set_render_mode(true)
	await get_tree().process_frame
	_check(not _gizmo.visible, "render mode hides the transform gizmo")
	_check(_nav != null and not _nav.visible, "render mode hides the navigation gizmo")
	_view.set_render_mode(false)
	await get_tree().process_frame
	await _refresh()
	_check(_gizmo.visible, "the transform gizmo returns after render mode")
	_check(_nav != null and _nav.is_visible_in_tree(), "the navigation gizmo returns after render mode")
	_check(not _view.has_method("_draw_compass"), "no 2D compass drawing method remains")


# -------------------------------------------------------------------------
# Optional visual capture (run with `-- --capture`)
# -------------------------------------------------------------------------

func _capture_requested() -> bool:
	return OS.get_cmdline_user_args().has("--capture")


## The capture stage size. `--size=1440x900` or `-- --capture --size=915x412`.
func _capture_size() -> Vector2i:
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--size="):
			var parts := str(arg).substr(7).split("x")
			if parts.size() == 2:
				var width := int(parts[0])
				var height := int(parts[1])
				if width >= 320 and height >= 240:
					return Vector2i(width, height)
	return Vector2i(1440, 900)


func _capture_visuals() -> void:
	var out_dir := CAPTURE_DIR
	DirAccess.make_dir_recursive_absolute(out_dir)
	var tag := "%dx%d" % [_capture_size().x, _capture_size().y]
	_select_default()
	_view.set_view_preset("Persp")
	_view.set_gizmo_scale(1.5)
	for tool in ["move", "rotate", "scale"]:
		_view.set_tool(tool)
		_view.request_preview_update()
		for _i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var stage: Image = _view._viewport.get_texture().get_image()
		if stage != null:
			stage.save_png(out_dir.path_join("gizmo-%s-stage-%s.png" % [tool, tag]))
		var window: Image = get_viewport().get_texture().get_image()
		if window != null:
			window.save_png(out_dir.path_join("gizmo-%s-window-%s.png" % [tool, tag]))
			if tool == "move" and _nav != null:
				var rect := Rect2i(
					Vector2i(_nav.get_global_rect().position),
					Vector2i(_nav.get_global_rect().size)
				)
				var scale := Vector2(window.get_size()) / get_viewport().get_visible_rect().size
				rect.position = Vector2i(Vector2(rect.position) * scale)
				rect.size = Vector2i(Vector2(rect.size) * scale)
				rect = rect.intersection(Rect2i(Vector2i.ZERO, window.get_size()))
				if rect.has_area():
					var crop := window.get_region(rect)
					crop.save_png(out_dir.path_join("nav-gizmo-%s.png" % tag))
					crop.resize(384, 384, Image.INTERPOLATE_NEAREST)
					crop.save_png(out_dir.path_join("nav-gizmo-4x-%s.png" % tag))
		print("GIZMO CAPTURE: %s" % tool)
	# The real still path must not photograph editing chrome.
	var still: Image = await _view.capture_still(1280, Viewport.MSAA_2X)
	if still != null:
		still.save_png(out_dir.path_join("still-no-gizmo-%s.png" % tag))
	_view.set_gizmo_scale(1.0)
