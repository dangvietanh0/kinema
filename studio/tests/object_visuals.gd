extends Node
## Object visuals suite (Wave-2 G5 / W7).
##
## Proves camera, light and empty objects are real 3D bodies with direction,
## range and look-through chrome. Runs headless; the xvfb capture half prints a
## clear skip when no display is available.

const DocumentScript = preload("res://src/core/document.gd")
const EditorAppScript = preload("res://src/app/editor.gd")

const STAGE_SIZE := Vector2i(915, 412)
const CAPTURE_DIR := "/tmp/opencode/wave2-object-visuals-captures"
const EPS := 0.01
const SHORT_EPS := 0.001

var _failures: Array[String] = []
var _oks := 0
var _doc = null
var _editor = null
var _view = null
var _root: Control = null
var _cam_id := ""
var _light_id := ""
var _omni_id := ""
var _empty_id := ""


func _check(condition: bool, message: String) -> void:
	if condition:
		_oks += 1
		print("OBJECT VISUALS OK: " + message)
	else:
		_failures.append(message)
		printerr("OBJECT VISUALS FAIL: " + message)


func _has(node: Object, method_name: String) -> bool:
	return node != null and node.has_method(method_name)


func _near(a: float, b: float, epsilon: float = EPS) -> bool:
	return absf(a - b) <= epsilon


func _v_near(a: Vector3, b: Vector3, epsilon: float = EPS) -> bool:
	return a.distance_to(b) <= epsilon


func _ready() -> void:
	await _setup()
	if _doc == null or _view == null:
		_check(false, "the object visuals stage is built")
		_finish()
		return
	await _test_editing_markers()
	await _test_marker_bodies()
	await _test_frustum()
	await _test_directional_light()
	await _test_omni_light()
	await _test_picking()
	await _test_inspector_action()
	await _test_look_through()
	await _test_capture()
	_finish()


func _finish() -> void:
	var status := "PASS" if _failures.is_empty() else "FAIL"
	print("OBJECT VISUALS RESULT: %s (%d OK, %d FAIL)" % [status, _oks, _failures.size()])
	if not _failures.is_empty():
		for failure in _failures:
			printerr("  - " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


# -------------------------------------------------------------------------
# Setup
# -------------------------------------------------------------------------

func _setup() -> void:
	get_window().size = STAGE_SIZE
	await get_tree().process_frame
	await get_tree().process_frame
	_root = Control.new()
	_root.name = "ObjectVisualsStage"
	_root.size = Vector2(STAGE_SIZE)
	add_child(_root)
	_editor = EditorAppScript.new()
	_editor.name = "Editor"
	_editor.size = Vector2(STAGE_SIZE)
	_root.add_child(_editor)
	await get_tree().process_frame
	await get_tree().process_frame
	_doc = DocumentScript.new()
	_doc.new_project("Object Visuals", "blank")
	_editor._adopt_document(_doc)
	for _i in 4:
		await get_tree().process_frame
	_view = _editor._view
	if _view == null:
		return
	_view._frame_all(false)
	_omni_id = _doc.add_light("omni", Vector3(2.0, 2.2, 1.0))
	_empty_id = _doc.add_empty(Vector3(-1.2, 0.8, 1.4))
	for obj in _doc.objects:
		var kind := str(obj.get("kind", ""))
		if kind == "camera" and _cam_id == "":
			_cam_id = str(obj.get("id", ""))
		elif kind == "light" and str(obj.get("light_type", "")) == "directional" and _light_id == "":
			_light_id = str(obj.get("id", ""))
	_doc.set_light_property(_omni_id, "light_range", 3.5)
	_doc.set_selection(_cam_id)
	# Pull the orbit camera back so the blank template's document camera, the
	# lights and the empty all sit in front of the editor camera. The default
	# 3.2 m frame puts the camera body behind the near plane.
	_view.target = Vector3(0.0, 1.0, 0.0)
	_view.distance = 10.0
	if _has(_view, "_apply_orbit_camera"):
		_view._apply_orbit_camera()
	for _i in 4:
		await get_tree().process_frame
	_doc.update_marker_scales(_view._camera)
	_check(_cam_id != "" and _light_id != "" and _omni_id != "" and _empty_id != "", "the stage has a camera, a directional light, an omni and an empty")


func _refresh() -> void:
	for _i in 2:
		await get_tree().process_frame
	if _doc != null and _view != null:
		_doc.update_marker_scales(_view._camera)
		if _has(_view, "_apply_orbit_camera") and not _view.is_look_through():
			_view._apply_orbit_camera()


func _marker_of(id: String) -> Node:
	var node: Node3D = _doc.nodes.get(id)
	if node == null:
		return null
	return node.get_node_or_null("Marker")


func _is_mesh(marker: Node) -> bool:
	return marker != null and marker is MeshInstance3D


# -------------------------------------------------------------------------
# 1. Editing view shows markers; render mode still hides them
# -------------------------------------------------------------------------

func _test_editing_markers() -> void:
	print("OBJECT VISUALS STEP: editing markers")
	_doc.markers_hidden = false
	_view.set_document(_doc)
	await get_tree().process_frame
	_check(_doc.markers_hidden == false, "the editing view keeps the document's 3D markers visible")
	for id in [_cam_id, _light_id, _omni_id, _empty_id]:
		var marker := _marker_of(id)
		if marker is MeshInstance3D:
			_doc.update_marker_scales(_view._camera)
			_check(marker.visible, "the 3D marker for %s is visible in the editing view" % id)
	_view.set_render_mode(true)
	await get_tree().process_frame
	_check(_doc.markers_hidden == true, "render mode hides the document markers")
	_view.set_render_mode(false)
	await get_tree().process_frame
	_check(_doc.markers_hidden == false, "leaving render mode restores the editing marker state")


# -------------------------------------------------------------------------
# 2. Real 3D bodies
# -------------------------------------------------------------------------

func _test_marker_bodies() -> void:
	print("OBJECT VISUALS STEP: 3D marker bodies")
	for entry in [["camera", _cam_id], ["directional light", _light_id], ["omni", _omni_id], ["empty", _empty_id]]:
		var label: String = entry[0]
		var id: String = entry[1]
		var node: Node3D = _doc.nodes.get(id)
		var marker := _marker_of(id)
		_check(marker != null and marker.get_parent() == node, "the %s marker is attached to its object node" % label)
		_check(_is_mesh(marker), "the %s marker is a real mesh body, not a screen icon" % label)
		if not _is_mesh(marker):
			continue
		var mesh_instance := marker as MeshInstance3D
		_check(mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the %s marker casts no shadow" % label)
		var mesh: Mesh = mesh_instance.mesh
		_check(mesh != null and mesh.get_surface_count() >= 1, "the %s marker has shaded surfaces" % label)
		_check(mesh_instance.get_aabb().size.length() > 0.08, "the %s marker has real 3D volume" % label)
		var shaded := mesh != null and mesh.get_surface_count() > 0
		if mesh != null:
			for surface in range(mesh.get_surface_count()):
				var material = mesh_instance.get_active_material(surface)
				if material is StandardMaterial3D:
					if (material as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
						shaded = false
		_check(shaded, "the %s body is shaded, not an unshaded wireframe" % label)
	var camera_marker := _marker_of(_cam_id)
	var light_marker := _marker_of(_light_id)
	var empty_marker := _marker_of(_empty_id)
	if _is_mesh(camera_marker):
		_check((camera_marker as MeshInstance3D).mesh.get_surface_count() >= 3, "the camera body has a block, a lens barrel and a lens ring")
	if _is_mesh(light_marker):
		_check((light_marker as MeshInstance3D).mesh.get_surface_count() >= 2, "the light body has a solid housing plus a directional nose")
	if _is_mesh(empty_marker):
		_check((empty_marker as MeshInstance3D).mesh.get_surface_count() == 3, "the empty is a three-axis 3D triad")
	if not _has(_view, "flat_locator_needed"):
		_check(false, "EditorView exposes flat_locator_needed(id)")
		return
	_check(_view.flat_locator_needed(_cam_id) == false, "an on-screen camera does not use the flat locator")
	var cam_node: Node3D = _doc.nodes.get(_cam_id)
	var saved_pos := cam_node.position
	var saved_rot := cam_node.quaternion
	var cam := _view._camera as Camera3D
	var behind := cam.global_position + cam.global_transform.basis.z * 4.0
	_doc.set_object_transform(_cam_id, behind, Quaternion.IDENTITY, Vector3.ONE, false)
	_doc.update_marker_scales(cam)
	_check(_view.flat_locator_needed(_cam_id) == true, "a camera behind the editor camera falls back to the flat name tag")
	_doc.set_object_transform(_cam_id, saved_pos, saved_rot, Vector3.ONE, false)
	await _refresh()


# -------------------------------------------------------------------------
# 3. Frustum
# -------------------------------------------------------------------------

func _frustum_bounds(segments: Array) -> Rect2:
	var rect := Rect2()
	var first := true
	for poly in segments:
		for point in poly:
			var p: Vector2 = point
			if first:
				rect = Rect2(p, Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(p)
	return rect


func _test_frustum() -> void:
	print("OBJECT VISUALS STEP: camera frustum")
	if not _has(_view, "frustum_corners") or not _has(_view, "camera_frustum_segments"):
		_check(false, "EditorView exposes frustum_corners() and camera_frustum_segments()")
		return
	var corners: Array = _view.frustum_corners(30.0, 1.5, 2.0)
	_check(corners.size() == 4, "frustum_corners returns the four far-plane corners")
	for c in corners:
		_check(_near((c as Vector3).z, -2.0, SHORT_EPS), "every far-plane corner sits at the display depth")
	var half_h := tan(deg_to_rad(15.0)) * 2.0
	var width := (corners[1] as Vector3).x - (corners[0] as Vector3).x
	var height := (corners[0] as Vector3).y - (corners[2] as Vector3).y
	_check(_near(width, 2.0 * half_h * 1.5, 0.002), "the frustum applies the real stage aspect")
	_check(_near(width / height, 1.5, 0.002), "the far-plane rectangle keeps the stage aspect ratio")
	var wide: Array = _view.frustum_corners(75.0, 1.5, 2.0)
	var wide_width := (wide[1] as Vector3).x - (wide[0] as Vector3).x
	_check(wide_width > width + 0.01, "the far-plane corner spread strictly grows with FOV")

	_check(_near(_view.stage_aspect(), float(_view._viewport.size.x) / maxf(1.0, float(_view._viewport.size.y)), 0.01), "stage_aspect reports the live stage aspect")
	var before: Array = _view.camera_frustum_segments(_cam_id)
	_check(before.size() >= 5, "the camera frustum has four rays plus the far-plane rectangle")
	var before_rect := _frustum_bounds(before)
	_doc.set_camera_fov(_cam_id, 70.0)
	await get_tree().process_frame
	var after_fov: Array = _view.camera_frustum_segments(_cam_id)
	var after_rect := _frustum_bounds(after_fov)
	_check(after_rect.size.x > before_rect.size.x + 1.0, "the frustum overlay updates when the camera FOV changes")
	_doc.set_camera_fov(_cam_id, 45.0)
	var cam_node: Node3D = _doc.nodes.get(_cam_id)
	var saved_pos := cam_node.position
	var saved_rot := cam_node.quaternion
	_doc.set_object_transform(_cam_id, saved_pos + Vector3(1.4, 0.0, 0.0), saved_rot, Vector3.ONE, false)
	await get_tree().process_frame
	var after_move: Array = _view.camera_frustum_segments(_cam_id)
	var moved_rect := _frustum_bounds(after_move)
	_check(moved_rect.position.distance_to(before_rect.position) > 1.0, "the frustum overlay follows the camera when it moves")
	_doc.set_object_transform(_cam_id, saved_pos, saved_rot, Vector3.ONE, false)
	var old_size: Vector2 = _view.size
	_view.size = Vector2(700.0, 412.0)
	_view._on_resized()
	var after_resize: Array = _view.camera_frustum_segments(_cam_id)
	var resized_rect := _frustum_bounds(after_resize)
	_check(resized_rect.size != before_rect.size, "the frustum overlay recomputes when the stage resizes")
	_view.size = old_size
	_view._on_resized()
	await get_tree().process_frame


# -------------------------------------------------------------------------
# 4. Directional light
# -------------------------------------------------------------------------

func _test_directional_light() -> void:
	print("OBJECT VISUALS STEP: directional light")
	if not _has(_view, "light_ground_hit") or not _has(_view, "light_arrow_segments") or not _has(_view, "arrow_endpoint"):
		_check(false, "EditorView exposes light_ground_hit(), arrow_endpoint() and light_arrow_segments()")
		return
	var down_hit: Dictionary = _view.light_ground_hit(Vector3(1.0, 4.0, 2.0), Vector3(0.0, -1.0, 0.0))
	_check(bool(down_hit.get("visible", false)), "a downward light reports a ground hit")
	_check(_v_near(down_hit.get("point", Vector3.ZERO), Vector3(1.0, 0.0, 2.0), SHORT_EPS), "the ground hit equals the analytic intersection")
	var up_hit: Dictionary = _view.light_ground_hit(Vector3(1.0, 4.0, 2.0), Vector3(0.0, 1.0, 0.0))
	_check(not bool(up_hit.get("visible", true)), "an upward light reports no ground hit")
	var flat_hit: Dictionary = _view.light_ground_hit(Vector3(1.0, 4.0, 2.0), Vector3(1.0, 0.0, 0.0))
	_check(not bool(flat_hit.get("visible", true)), "a horizontal light reports no ground hit")

	# Point the document light straight down so the analytic endpoint is known.
	var down_rot := Quaternion(Vector3.RIGHT, deg_to_rad(-90.0))
	_doc.set_object_transform(_light_id, Vector3(0.0, 4.0, 2.0), down_rot, Vector3.ONE, false)
	await _refresh()
	var node: Node3D = _doc.nodes.get(_light_id)
	var direction := (-node.global_transform.basis.z).normalized()
	_check(_near(direction.y, -1.0, SHORT_EPS), "the light's real direction is -basis.z")
	var hit: Dictionary = _view.light_ground_hit(node.global_position, direction)
	_check(bool(hit.get("visible", false)), "the document directional light hits the ground")
	_check(_v_near(hit.get("point", Vector3.ZERO), Vector3(0.0, 0.0, 2.0), SHORT_EPS), "the document light endpoint is the analytic ground point")
	_check(_v_near(_view.arrow_endpoint(_light_id), hit.get("point", Vector3.ZERO), 0.02), "the arrow endpoint uses the ground-hit helper")
	var segments: Array = _view.light_arrow_segments(_light_id)
	_check(segments.size() >= 3, "the directional arrow includes a shaft, an arrowhead and a ground ring")
	if not segments.is_empty() and (segments[0] as PackedVector2Array).size() >= 2:
		var shaft: PackedVector2Array = segments[0]
		var projected_end := shaft[shaft.size() - 1]
		_check(projected_end.distance_to(_view.world_to_screen(hit.get("point", Vector3.ZERO))) < 1.5, "the projected arrow endpoint matches the helper")
		_check(shaft[0].distance_to(_view.world_to_screen(node.global_position)) < 1.5, "the arrow starts at the light body")
	# An upward light draws no fake ground ring.
	var up_rot := Quaternion(Vector3.RIGHT, deg_to_rad(90.0))
	_doc.set_object_transform(_light_id, Vector3(0.0, 4.0, 2.0), up_rot, Vector3.ONE, false)
	await _refresh()
	_check(not bool(_view.light_ground_hit(node.global_position, (-node.global_transform.basis.z).normalized()).get("visible", true)), "the document upward light has no ground hit")
	if _has(_view, "light_ground_ring_visible"):
		_check(not _view.light_ground_ring_visible(_light_id), "the ground ring is hidden when the light points up")
	_doc.set_object_transform(_light_id, Vector3(0.0, 4.0, 2.0), down_rot, Vector3.ONE, false)
	await _refresh()


# -------------------------------------------------------------------------
# 5. Omni footprint
# -------------------------------------------------------------------------

func _test_omni_light() -> void:
	print("OBJECT VISUALS STEP: omni footprint")
	if not _has(_view, "footprint_radius") or not _has(_view, "footprint_segments") or not _has(_view, "footprint_visible"):
		_check(false, "EditorView exposes footprint_radius(), footprint_segments() and footprint_visible()")
		return
	var obj: Dictionary = _doc.get_object(_omni_id)
	_check(_near(_view.footprint_radius(obj), float(obj.get("light_range", 0.0)), SHORT_EPS), "footprint_radius equals the object's real light_range")
	var segments: Array = _view.footprint_segments(_omni_id)
	_check(segments.size() == 3, "the omni footprint draws the outer ring plus two inner rings")
	if segments.size() == 3:
		for i in range(segments.size()):
			var ring: PackedVector2Array = segments[i]
			_check(ring.size() >= 24, "omni footprint ring %d is a real projected circle" % (i + 1))
	_check(_view.footprint_visible(_omni_id), "the footprint is drawn for an omni above the ground")
	_check(_view.light_arrow_segments(_omni_id).is_empty(), "an omni gets no directional arrow")
	var node: Node3D = _doc.nodes.get(_omni_id)
	var saved := node.position
	_doc.set_object_transform(_omni_id, Vector3(saved.x, -1.0, saved.z), node.quaternion, node.scale, false)
	await _refresh()
	_check(not _view.footprint_visible(_omni_id), "the footprint hides when the omni is below the ground plane")
	_check(_view.footprint_segments(_omni_id).is_empty(), "no footprint geometry is drawn below the ground plane")
	_doc.set_object_transform(_omni_id, saved, node.quaternion, node.scale, false)
	await _refresh()


# -------------------------------------------------------------------------
# 6. Overlay picking
# -------------------------------------------------------------------------

func _midpoint(poly: PackedVector2Array) -> Vector2:
	if poly.size() < 2:
		return Vector2.INF
	return (poly[0] + poly[poly.size() - 1]) * 0.5


func _only_visible(ids: Array) -> void:
	for entry in _doc.objects:
		var id := str(entry.get("id", ""))
		_doc.set_object_visible(id, ids.has(id))
	for _i in 2:
		await get_tree().process_frame


func _test_picking() -> void:
	print("OBJECT VISUALS STEP: overlay picking")
	if not _has(_view, "pick_marker_overlay"):
		_check(false, "EditorView exposes pick_marker_overlay()")
		return
	await _only_visible([_cam_id])
	var frustum: Array = _view.camera_frustum_segments(_cam_id)
	_check(not frustum.is_empty(), "the camera frustum is available for picking")
	if not frustum.is_empty():
		var point := _midpoint(frustum[0] as PackedVector2Array)
		_check(_view.pick_marker_overlay(point) == _cam_id, "tapping the camera frustum selects the camera")
		_view._pick(point)
		_check(_doc.selected_id == _cam_id, "the normal tap path selects the camera on its frustum")

	await _only_visible([_light_id])
	var arrow: Array = _view.light_arrow_segments(_light_id)
	_check(not arrow.is_empty(), "the directional arrow is available for picking")
	if not arrow.is_empty():
		var point := _midpoint(arrow[0] as PackedVector2Array)
		_check(_view.pick_marker_overlay(point) == _light_id, "tapping the directional arrow selects the light")

	await _only_visible([_omni_id])
	var footprint: Array = _view.footprint_segments(_omni_id)
	_check(not footprint.is_empty(), "the omni footprint is available for picking")
	if not footprint.is_empty():
		var point := _midpoint(footprint[0] as PackedVector2Array)
		_check(_view.pick_marker_overlay(point) == _omni_id, "tapping the omni footprint selects the omni")

	await _only_visible([_empty_id])
	var node: Node3D = _doc.nodes.get(_empty_id)
	var origin_point: Vector2 = _view.world_to_screen(node.global_position)
	_check(_view.pick_marker_overlay(origin_point + Vector2(0.0, 18.0)) == _empty_id, "the existing 26 px origin target still selects the object")

	await _only_visible([_omni_id])
	var hidden_point: Vector2 = _view.world_to_screen(_doc.nodes.get(_omni_id).global_position)
	_doc.set_object_visible(_omni_id, false)
	await get_tree().process_frame
	_check(_view.pick_marker_overlay(hidden_point) == "", "a hidden object is not pickable through its overlay")
	_doc.set_object_visible(_omni_id, true)
	for entry in _doc.objects:
		_doc.set_object_visible(str(entry.get("id", "")), true)
	for _i in 2:
		await get_tree().process_frame


# -------------------------------------------------------------------------
# 7. Inspector action
# -------------------------------------------------------------------------

func _labels_under(root: Node) -> Array[Label]:
	var found: Array[Label] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Label:
			found.append(node as Label)
	return found


func _buttons_under(root: Node) -> Array[Button]:
	var found: Array[Button] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Button:
			found.append(node as Button)
	return found


func _button_with_text(root: Node, text_value: String) -> Button:
	for button in _buttons_under(root):
		if button.text.strip_edges() == text_value:
			return button
	return null


func _label_text(root: Node) -> String:
	var text_value := ""
	for label in _labels_under(root):
		text_value += label.text + "\n"
	return text_value


func _test_inspector_action() -> void:
	print("OBJECT VISUALS STEP: inspector look through")
	_doc.set_selection(_cam_id)
	await get_tree().process_frame
	await get_tree().process_frame
	var inspector = _editor._inspector
	_check(inspector != null, "the editor inspector is available")
	if inspector == null:
		return
	var text_value := _label_text(inspector)
	_check(not text_value.contains("layout reference"), "the old layout-reference-only hint is gone")
	var action := _button_with_text(inspector, "Look through")
	_check(action != null, "the Camera section exposes a Look through action")
	if action == null:
		return
	_check(action.custom_minimum_size == Vector2(96.0, 44.0), "Look through is a 96x44 primary action")
	_check(_view.is_look_through() == false, "pressing the action is required to enter look-through")
	action.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_view.is_look_through(), "pressing Look through enters a real look-through mode")
	_editor._exit_look_through()
	await get_tree().process_frame
	await get_tree().process_frame


# -------------------------------------------------------------------------
# 8. Look-through
# -------------------------------------------------------------------------

func _xform_near(a: Transform3D, b: Transform3D) -> bool:
	if a.origin.distance_to(b.origin) > 0.002:
		return false
	return (
		a.basis.x.distance_to(b.basis.x) < 0.002
		and a.basis.y.distance_to(b.basis.y) < 0.002
		and a.basis.z.distance_to(b.basis.z) < 0.002
	)


func _test_look_through() -> void:
	print("OBJECT VISUALS STEP: look-through")
	if not _has(_editor, "_enter_look_through") or not _has(_editor, "_exit_look_through") or not _has(_view, "enter_look_through") or not _has(_view, "exit_look_through") or not _has(_view, "is_look_through"):
		_check(false, "the editor and view expose the look-through lifecycle")
		return
	var cam_node: Node3D = _doc.nodes.get(_cam_id)
	if cam_node == null:
		_check(false, "the camera object exists for look-through")
		return
	var saved_xform: Transform3D = _view._camera.global_transform
	var saved_fov: float = _view._camera.fov
	var saved_target: Vector3 = _view.target
	var saved_yaw: float = _view.yaw
	var saved_pitch: float = _view.pitch
	var saved_distance: float = _view.distance
	var saved_grid: bool = _view.grid_enabled()
	var saved_markers: bool = _doc.markers_hidden
	var saved_hud: bool = _view._hud_root.visible
	var saved_nav: bool = _view._nav_gizmo.visible
	var timeline_visible: bool = _editor._timeline_panel.visible
	var dock_visible: bool = _editor._dock.visible
	var scene_visible: bool = _editor._scene_column.visible
	var bottom_visible: bool = _editor._bottom_bar.visible

	_editor._enter_look_through(_cam_id)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_view.is_look_through(), "the view reports look-through mode")
	_check(_view.look_through_camera_id() == _cam_id, "look-through names the document camera it copied")
	var doc_camera := cam_node.get_node_or_null("Camera") as Camera3D
	_check(doc_camera != null and not doc_camera.current, "the document camera node stays inactive")
	_check(_xform_near(_view._camera.global_transform, cam_node.global_transform), "the editor camera copies the document camera transform")
	_check(doc_camera != null and _near(_view._camera.fov, doc_camera.fov, SHORT_EPS), "the editor camera copies the document camera FOV")
	_check(not _view.grid_enabled(), "the grid hides in look-through")
	_check(_doc.markers_hidden, "3D markers hide in look-through")
	_check(not _view._hud_root.visible, "the editor HUD hides in look-through")
	_check(not _view._nav_gizmo.visible, "the navigation gizmo hides in look-through")
	_check(not _view._gizmo.visible, "the transform gizmo hides in look-through")
	if _has(_view, "editing_chrome_visible"):
		_check(not _view.editing_chrome_visible(), "selection and editing chrome are suppressed in look-through")
	_check(not _editor._view_header.visible, "the viewport header hides in look-through")
	_check(_editor._timeline_panel.visible == timeline_visible, "the timeline stays visible in look-through")
	_check(_editor._dock.visible == dock_visible, "the dock keeps its state in look-through")
	_check(_editor._scene_column.visible == scene_visible, "the scene tree keeps its state in look-through")
	_check(_editor._bottom_bar.visible == bottom_visible, "the transport keeps its state in look-through")

	# Orbit and pan gestures are ignored, and _process must not overwrite the
	# copied camera with the orbit target.
	var frozen: Transform3D = _view._camera.global_transform
	_view._orbit(Vector2(90.0, 45.0))
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(300.0, 200.0)
	drag.relative = Vector2(60.0, 20.0)
	_view._gui_input(drag)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_xform_near(_view._camera.global_transform, frozen), "a simulated orbit drag does not move the look-through camera")

	# Playback and the timeline stay live.
	_doc.seek(0.0, true)
	_doc.play()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_doc.is_playing, "playback keeps running in look-through")
	_check(_doc.current_time > 0.0, "the timeline clock advances in look-through")
	_doc.pause()

	var exit_button: Button = _view.look_through_exit_button() if _has(_view, "look_through_exit_button") else null
	_check(exit_button != null and exit_button.visible, "the persistent Exit camera control is visible")
	if exit_button != null:
		_check(exit_button.size == Vector2(96.0, 44.0) or exit_button.custom_minimum_size == Vector2(96.0, 44.0), "Exit camera is exactly 96x44")
		_check(_near(exit_button.position.x, 12.0, 0.5) and _near(exit_button.position.y, 12.0, 0.5), "Exit camera sits at the stage's top-left with a 12 dp inset")
		exit_button.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
	_check(not _view.is_look_through(), "pressing Exit camera leaves look-through")
	_check(_xform_near(_view._camera.global_transform, saved_xform), "exiting restores the exact saved editor transform")
	_check(_near(_view._camera.fov, saved_fov, SHORT_EPS), "exiting restores the saved editor FOV")
	_check(_near(_view.target.x, saved_target.x, SHORT_EPS) and _near(_view.yaw, saved_yaw, SHORT_EPS) and _near(_view.pitch, saved_pitch, SHORT_EPS) and _near(_view.distance, saved_distance, SHORT_EPS), "exiting restores the saved orbit state")
	_check(_view.grid_enabled() == saved_grid, "exiting restores the grid state")
	_check(_doc.markers_hidden == saved_markers, "exiting restores the marker state")
	_check(_view._hud_root.visible == saved_hud, "exiting restores the editor HUD")
	_check(_view._nav_gizmo.visible == saved_nav, "exiting restores the navigation gizmo")
	_check(_editor._view_header.visible, "exiting restores the viewport header")
	if exit_button != null:
		_check(not exit_button.visible, "the Exit camera control hides when look-through ends")

	# Android back exits look-through first and never closes the project.
	_editor._enter_look_through(_cam_id)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_view.is_look_through(), "look-through re-enters for the back test")
	_editor._closing = false
	var handled: bool = _editor.handle_back()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(handled, "handle_back consumes the Android back event")
	_check(not _view.is_look_through(), "Android back exits look-through")
	_check(not _editor._closing, "Android back does not close the editor while look-through is active")
	_check(_editor.doc != null and is_instance_valid(_editor) and _editor.is_inside_tree(), "the editor and project stay open after back")


# -------------------------------------------------------------------------
# 9. xvfb capture
# -------------------------------------------------------------------------

func _display_available() -> bool:
	return DisplayServer.get_name() != "headless"


func _capture_dir() -> String:
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	return CAPTURE_DIR


func _grab_window(tag: String) -> Image:
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image != null:
		image.save_png(_capture_dir().path_join(tag))
	return image


func _pixel_at(image: Image, ui_point: Vector2) -> Color:
	if image == null:
		return Color.BLACK
	var rect: Vector2 = get_viewport().get_visible_rect().size
	if rect.x <= 0.0 or rect.y <= 0.0:
		return Color.BLACK
	# `ui_point` is relative to the view control; the captured image is the
	# whole window, so shift by the stage's global origin first.
	var window_point := ui_point
	if _view != null:
		window_point += _view.get_global_rect().position
	var scale := Vector2(image.get_size()) / rect
	var p := Vector2i(window_point * scale)
	if p.x < 0 or p.y < 0 or p.x >= image.get_width() or p.y >= image.get_height():
		return Color.BLACK
	return image.get_pixel(p.x, p.y)


func _luma(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


func _sample_body(image: Image, id: String, label: String) -> void:
	var node: Node3D = _doc.nodes.get(id)
	if node == null:
		_check(false, "the %s is available for the capture sample" % label)
		return
	var center: Vector2 = _view.world_to_screen(node.global_position)
	var background: Vector2 = center + Vector2(70.0, 0.0)
	if background.x > _view.size.x - 8.0:
		background = center - Vector2(70.0, 0.0)
	var body_color := _pixel_at(image, center)
	var background_color := _pixel_at(image, background)
	var difference := absf(_luma(body_color) - _luma(background_color))
	_check(difference > 0.035, "the projected %s body reads against the nearby background (%.3f luma difference)" % [label, difference])


func _test_capture() -> void:
	print("OBJECT VISUALS STEP: captures")
	if not _display_available():
		print("OBJECT VISUALS SKIP: xvfb capture skipped (headless display)")
		return
	_capture_dir()
	_doc.markers_hidden = false
	_view.set_grid_enabled(true)
	_view.set_view_preset("Persp")
	# Frame the whole object set. Scene bounds ignore the marker bodies, so an
	# automatic frame only finds the cube and clips the light at the top.
	_view.target = Vector3(1.0, 2.0, 1.5)
	_view.distance = 16.0
	if _has(_view, "_apply_orbit_camera"):
		_view._apply_orbit_camera()
	if _has(_view, "_repaint"):
		_view._repaint()
	_doc.set_selection(_cam_id)
	for _i in 4:
		await get_tree().process_frame
	var image := await _grab_window("objects.png")
	_check(image != null, "the editing stage capture is written at 915x412")
	if image != null:
		_check(image.get_width() == STAGE_SIZE.x and image.get_height() == STAGE_SIZE.y, "the editing capture is exactly 915x412")
		_sample_body(image, _cam_id, "camera")
		_sample_body(image, _light_id, "directional light")

	# Close-up of the camera body, frustum and the directional arrow.
	_view.target = Vector3(2.0, 1.9, 2.6)
	_view.distance = 7.5
	if _has(_view, "_apply_orbit_camera"):
		_view._apply_orbit_camera()
	if _has(_view, "_repaint"):
		_view._repaint()
	for _i in 4:
		await get_tree().process_frame
	var camera_image := await _grab_window("camera-frustum-915x412.png")
	_check(camera_image != null, "the camera body and frustum capture is written at 915x412")
	if camera_image != null:
		_check(camera_image.get_width() == STAGE_SIZE.x and camera_image.get_height() == STAGE_SIZE.y, "the camera capture is exactly 915x412")

	# The omni footprint is the range cue.
	_view.target = Vector3(2.0, 0.7, 1.0)
	_view.distance = 8.0
	if _has(_view, "_apply_orbit_camera"):
		_view._apply_orbit_camera()
	if _has(_view, "_repaint"):
		_view._repaint()
	for _i in 4:
		await get_tree().process_frame
	var omni_image := await _grab_window("omni-footprint-915x412.png")
	_check(omni_image != null, "the omni footprint capture is written at 915x412")
	if omni_image != null:
		_check(omni_image.get_width() == STAGE_SIZE.x and omni_image.get_height() == STAGE_SIZE.y, "the omni capture is exactly 915x412")

	# The real look-through state, with the persistent Exit control on top.
	# Aim the blank document camera at the cube for the capture: its authored
	# rotation is almost horizontal and would show an empty stage. Restore the
	# authored transform afterwards.
	var cam_node: Node3D = _doc.nodes.get(_cam_id)
	var saved_position := cam_node.position
	var saved_rotation := cam_node.quaternion
	var saved_scale := cam_node.scale
	var aim := Transform3D(Basis.IDENTITY, Vector3(4.0, 3.15, 5.2))
	aim = aim.looking_at(Vector3(0.0, 0.6, 0.0), Vector3.UP)
	_doc.set_object_transform(
		_cam_id, aim.origin, aim.basis.get_rotation_quaternion(), Vector3.ONE, false
	)
	_editor._enter_look_through(_cam_id)
	if _has(_view, "_repaint"):
		_view._repaint()
	for _i in 4:
		await get_tree().process_frame
	var look_image := await _grab_window("look-through-915x412.png")
	_check(look_image != null, "the look-through capture is written at 915x412")
	if look_image != null:
		_check(look_image.get_width() == STAGE_SIZE.x and look_image.get_height() == STAGE_SIZE.y, "the look-through capture is exactly 915x412")
	_editor._exit_look_through()
	_doc.set_object_transform(_cam_id, saved_position, saved_rotation, saved_scale, false)
	await get_tree().process_frame
	await get_tree().process_frame
