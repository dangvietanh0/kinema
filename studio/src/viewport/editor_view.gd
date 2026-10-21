extends Control
## The 3D preview, editor camera and touch transform gizmo.
##
## A SubViewport renders the document world. The surrounding Control draws the
## selection box, the axis gizmo, the orientation compass and transient
## transform readouts. One finger orbits, two fingers pan and pinch, tapping
## selects, dragging an axis manipulates the selected object.

const HUD_BG := Color(0.043, 0.059, 0.078, 0.86)

const DocumentScript = preload("res://src/core/document.gd")
var doc: DocumentScript = null
var tool := "select"

var target := Vector3(0.0, 0.8, 0.0)
var yaw := deg_to_rad(38.0)
var pitch := deg_to_rad(18.0)
var distance := 7.4

var _viewport: SubViewport
var _surface: TextureRect
var _camera: Camera3D
var _grid_root: Node3D
var _grid_mesh: MeshInstance3D
var _status_label: Label
var _view_chip: Button
var _grid_button: Button
var _preset := "Persp"

var _touches: Dictionary = {}
var _mode := "idle"  # idle | orbit | gizmo | multi | pan
var _gesture_start := Vector2.ZERO
var _tap_candidate := false
var _gizmo_axis := ""
var _gizmo_start_pos := Vector3.ZERO
var _gizmo_start_rot := Quaternion.IDENTITY
var _gizmo_start_scale := Vector3.ONE
var _gizmo_start_screen := Vector2.ZERO
var _gizmo_screen_dir := Vector2.RIGHT
var _gizmo_world_len := 1.0
var _gizmo_drag := Vector2.ZERO
var _gizmo_handles: Array = []
var _hud_text := ""
var _multi_mid := Vector2.ZERO
var _multi_dist := 1.0
var _pan_last := Vector2.ZERO
var _camera_ready := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	_build_viewport()
	_build_hud()
	resized.connect(_on_resized)
	call_deferred("_on_resized")
	set_process(true)

func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "PreviewViewport"
	_viewport.gui_disable_input = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.size = Vector2i(1280, 800)
	add_child(_viewport)

	_surface = TextureRect.new()
	_surface.name = "PreviewSurface"
	_surface.texture = _viewport.get_texture()
	_surface.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_surface.stretch_mode = TextureRect.STRETCH_SCALE
	_surface.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.show_behind_parent = true
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_surface)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.051, 0.066, 0.086)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.61, 0.68, 0.78)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	_viewport.add_child(env_node)

	_camera = Camera3D.new()
	_camera.name = "EditorCamera"
	_camera.fov = 46.0
	_camera.near = 0.04
	_camera.far = 400.0
	_camera.current = true
	_viewport.add_child(_camera)

	_build_stage()

func _build_stage() -> void:
	_grid_root = Node3D.new()
	_grid_root.name = "StudioStage"
	_viewport.add_child(_grid_root)

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	ground.mesh = plane
	ground.position.y = -0.012
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.043, 0.055, 0.071)
	ground_mat.roughness = 1.0
	ground_mat.metallic = 0.0
	ground.material_override = ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grid_root.add_child(ground)

	var mesh := ArrayMesh.new()
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var half := 12
	var step := 0.5
	var major := 2.0
	var minor_color := Color(0.105, 0.129, 0.163)
	var major_color := Color(0.145, 0.176, 0.218)
	for i in range(-half * 2, half * 2 + 1):
		var v := float(i) * step
		var is_major := absf(fmod(v, major)) < 0.001
		var c := major_color if is_major else minor_color
		_add_grid_line(verts, colors, Vector3(v, 0.0, -half), Vector3(v, 0.0, half), c)
		_add_grid_line(verts, colors, Vector3(-half, 0.0, v), Vector3(half, 0.0, v), c)
	_add_grid_line(verts, colors, Vector3(-half, 0.003, 0.0), Vector3(half, 0.003, 0.0), Color(0.32, 0.14, 0.14))
	_add_grid_line(verts, colors, Vector3(0.0, 0.003, -half), Vector3(0.0, 0.003, half), Color(0.13, 0.19, 0.33))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var grid := MeshInstance3D.new()
	grid.name = "Grid"
	grid.mesh = mesh
	grid.material_override = mat
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grid_root.add_child(grid)
	_grid_mesh = grid

func _add_grid_line(verts: PackedVector3Array, colors: PackedColorArray, a: Vector3, b: Vector3, c: Color) -> void:
	verts.append(a)
	verts.append(b)
	colors.append(c)
	colors.append(c)

func _build_hud() -> void:
	var top_left := HBoxContainer.new()
	top_left.add_theme_constant_override("separation", 6)
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_left.offset_left = 12
	top_left.offset_top = 10
	top_left.grow_vertical = Control.GROW_DIRECTION_END
	add_child(top_left)

	_view_chip = Kit.text_button("Persp", "orbit", false, true)
	_view_chip.tooltip_text = "Cycle camera view"
	_view_chip.pressed.connect(_cycle_view)
	_override_hud_button(_view_chip)
	top_left.add_child(_view_chip)

	var top_right := HBoxContainer.new()
	top_right.add_theme_constant_override("separation", 6)
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.offset_right = -12
	top_right.offset_top = 10
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.grow_vertical = Control.GROW_DIRECTION_END
	add_child(top_right)

	var focus := Kit.icon_button("focus", "Frame selection (F)", 30, 15)
	_override_hud_button(focus)
	focus.pressed.connect(focus_selection)
	top_right.add_child(focus)

	_grid_button = Kit.icon_button("grid-3x3", "Toggle grid", 30, 15)
	_override_hud_button(_grid_button)
	_grid_button.toggle_mode = true
	_grid_button.button_pressed = true
	_grid_button.toggled.connect(_on_grid_toggled)
	top_right.add_child(_grid_button)

	_status_label = Kit.label("No selection", 10, Kit.TEXT_MUTED, 500)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var status_panel := PanelContainer.new()
	var status_style := Kit.flat_style(Color(0.035, 0.047, 0.062, 0.82), 5, Kit.BORDER_SOFT, 1)
	status_style.content_margin_left = 8
	status_style.content_margin_right = 8
	status_style.content_margin_top = 4
	status_style.content_margin_bottom = 4
	status_panel.add_theme_stylebox_override("panel", status_style)
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	status_panel.offset_left = 12
	status_panel.offset_bottom = -12
	status_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	status_panel.add_child(_status_label)
	add_child(status_panel)

func _override_hud_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", Kit.flat_style(HUD_BG, 5, Kit.BORDER_SOFT, 1))
	button.add_theme_stylebox_override("hover", Kit.flat_style(Kit.SURFACE_3, 5, Kit.BORDER, 1))
	button.add_theme_stylebox_override("pressed", Kit.flat_style(Kit.SURFACE_3, 5, Kit.ACCENT, 1))
	button.add_theme_stylebox_override("hover_pressed", Kit.flat_style(Kit.SURFACE_3, 5, Kit.ACCENT_BRIGHT, 1))
	button.add_theme_color_override("font_color", Kit.TEXT_MUTED)
	button.add_theme_color_override("font_pressed_color", Kit.ACCENT)

func set_document(document: Node3D) -> void:
	if doc == document:
		return
	doc = document
	_viewport.add_child(doc)
	doc.scene_changed.connect(_on_scene_changed)
	doc.selection_changed.connect(_on_selection_changed)
	doc.object_changed.connect(_on_object_changed)
	doc.playback_changed.connect(_on_playback_changed)
	_frame_all(false)
	call_deferred("_reframe_after_layout")
	_refresh_status()
	queue_redraw()

func set_tool(new_tool: String) -> void:
	tool = new_tool
	queue_redraw()

func _on_resized() -> void:
	if _viewport == null:
		return
	# Render the preview at device resolution instead of at UI units. Phones
	# scale the canvas by their display density, so the raw control size would
	# produce a soft, upscaled 3D image.
	var pixel_scale := 1.0
	var win := get_window()
	var visible := get_viewport().get_visible_rect().size
	if win != null and visible.x > 1.0 and visible.y > 1.0:
		pixel_scale = clampf(minf(float(win.size.x) / visible.x, float(win.size.y) / visible.y), 1.0, 4.0)
	var target := Vector2(size.x * pixel_scale, size.y * pixel_scale)
	var longest := maxf(target.x, target.y)
	if longest > 2560.0:
		target *= 2560.0 / longest
	var w := maxi(2, int(round(target.x)))
	var h := maxi(2, int(round(target.y)))
	_viewport.size = Vector2i(w, h)
	queue_redraw()

func _process(_delta: float) -> void:
	if _camera == null:
		return
	var offset := Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw)
	) * distance
	_camera.global_position = target + offset
	_camera.look_at(target, Vector3.UP)
	if doc == null:
		return
	doc.update_marker_scales(_camera)
	# The overlay is cheap and must track selection, gizmo and compass changes
	# even when no input event arrives, so it redraws with the preview.
	queue_redraw()

# -------------------------------------------------------------------------
# Document events and view helpers
# -------------------------------------------------------------------------

func _on_scene_changed() -> void:
	_refresh_status()
	queue_redraw()

func _on_selection_changed(_id: String) -> void:
	_refresh_status()
	queue_redraw()

func _on_object_changed(_id: String) -> void:
	_refresh_status()
	queue_redraw()

func _on_playback_changed(_time: float, _playing: bool) -> void:
	queue_redraw()

func _refresh_status() -> void:
	if _status_label == null:
		return
	if doc == null or doc.selected_id == "":
		_status_label.text = "No selection  ·  tap an object"
		return
	var obj: Dictionary = doc.get_selected_object()
	if obj.is_empty():
		_status_label.text = "No selection"
		return
	var kind := str(obj.get("kind", "mesh"))
	var label := str(obj.get("name", "Object"))
	var detail := kind.capitalize()
	if kind == "mesh":
		detail = str(obj.get("primitive", "mesh")).capitalize()
	elif kind == "import":
		detail = "Imported model"
	elif kind == "light":
		detail = "Omni light" if str(obj.get("light_type", "")) == "omni" else "Directional light"
	var keys := 0
	for channel in doc.CHANNELS:
		keys += doc.get_channel_keys(doc.selected_id, channel).size()
	var suffix := "  ·  %d key%s" % [keys, "" if keys == 1 else "s"] if keys > 0 else ""
	_status_label.text = "%s  ·  %s%s" % [label, detail, suffix]

func _cycle_view() -> void:
	match _preset:
		"Persp":
			_apply_preset("Front", 0.0, 0.0)
		"Front":
			_apply_preset("Right", PI * 0.5, 0.0)
		"Right":
			_apply_preset("Top", 0.0, 1.45)
		_:
			_apply_preset("Persp", deg_to_rad(38.0), deg_to_rad(18.0))

func _apply_preset(label: String, new_yaw: float, new_pitch: float) -> void:
	_preset = label
	yaw = new_yaw
	pitch = new_pitch
	_view_chip.text = label
	queue_redraw()

func _on_grid_toggled(enabled: bool) -> void:
	if _grid_mesh != null:
		_grid_mesh.visible = enabled
	queue_redraw()

func focus_selection() -> void:
	if doc == null:
		return
	var id: String = doc.selected_id
	if id == "":
		_frame_all(true)
		return
	var aabb: AABB = doc.get_object_aabb(id)
	if aabb.size.length() < 0.001:
		var node: Node3D = doc.nodes.get(id)
		if node == null:
			return
		_tween_view(node.global_position + Vector3.UP * 0.2, 3.2)
		return
	var center := aabb.get_center()
	_tween_view(center, _fit_distance(aabb.size.length()))

func _reframe_after_layout() -> void:
	await get_tree().process_frame
	if is_inside_tree() and doc != null:
		_frame_all(false)

func _fit_distance(span: float) -> float:
	# The vertical FOV is fixed, so a portrait viewport needs a longer camera
	# distance to keep the same object inside the narrower horizontal field.
	var aspect := clampf(size.x / maxf(1.0, size.y), 0.4, 2.4)
	var dist := maxf(3.2, span * 1.4)
	if aspect < 1.0:
		dist /= aspect
	return clampf(dist, 2.2, 80.0)

func _frame_all(animate: bool) -> void:
	if doc == null:
		return
	var bounds: AABB = doc.get_scene_bounds()
	var center := Vector3(0.0, 0.8, 0.0)
	var dist := _fit_distance(5.3)
	if bounds.size.length() > 0.001:
		center = bounds.get_center()
		dist = _fit_distance(bounds.size.length())
	if animate:
		_tween_view(center, dist)
	else:
		target = center
		distance = dist

func _tween_view(new_target: Vector3, new_distance: float) -> void:
	if not is_inside_tree():
		target = new_target
		distance = new_distance
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "target", new_target, 0.24)
	tween.tween_property(self, "distance", new_distance, 0.24)

# -------------------------------------------------------------------------
# Input
# -------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if Kit.is_emulated_mouse(event):
		return
	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_gesture_start = event.position
			_tap_candidate = true
			var hit := _hit_gizmo(event.position)
			if hit != "":
				_start_gizmo(hit, event.position)
			else:
				_mode = "orbit"
		elif _touches.size() == 2 and _mode != "gizmo":
			_mode = "multi"
			_tap_candidate = false
			_update_multi_anchor()
		accept_event()
	else:
		_touches.erase(event.index)
		if _mode == "gizmo":
			_finish_gizmo()
		elif _mode == "orbit" and _tap_candidate:
			if event.position.distance_to(_gesture_start) < 9.0:
				_pick(event.position)
		if _touches.size() == 1:
			_mode = "orbit"
			_tap_candidate = false
		elif _touches.is_empty():
			_mode = "idle"
			_tap_candidate = false
		accept_event()

func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	_touches[event.index] = event.position
	if event.position.distance_to(_gesture_start) > 9.0:
		_tap_candidate = false
	if _mode == "gizmo":
		_apply_gizmo_drag(event.relative)
	elif _mode == "orbit":
		_orbit(event.relative)
	elif _mode == "multi" and _touches.size() >= 2:
		_update_multi_gesture()
	accept_event()

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		distance = clampf(distance * 0.9, 0.9, 80.0)
		accept_event()
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		distance = clampf(distance * 1.1, 0.9, 80.0)
		accept_event()
		return
	if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT and event.button_index != MOUSE_BUTTON_MIDDLE:
		return
	if event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_gesture_start = event.position
			_tap_candidate = true
			var hit := _hit_gizmo(event.position)
			if hit != "":
				_start_gizmo(hit, event.position)
			else:
				_mode = "orbit"
		else:
			_mode = "pan"
			_pan_last = event.position
		accept_event()
	else:
		if _mode == "gizmo":
			_finish_gizmo()
		elif _mode == "orbit" and _tap_candidate:
			_pick(event.position)
		_mode = "idle"
		_tap_candidate = false
		accept_event()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _mode == "gizmo":
		_apply_gizmo_drag(event.relative)
	elif _mode == "orbit":
		_orbit(event.relative)
	else:
		return
	accept_event()

func _orbit(relative: Vector2) -> void:
	if relative.length() < 0.01:
		return
	if absf(relative.x) + absf(relative.y) > 2.0:
		_tap_candidate = false
	yaw -= relative.x * 0.0062
	pitch = clampf(pitch + relative.y * 0.0062, -1.35, 1.45)
	_preset = "Free"
	_view_chip.text = "Free"
	queue_redraw()

func _update_multi_anchor() -> void:
	var ids := _touches.keys()
	ids.sort()
	if ids.size() < 2:
		return
	var a: Vector2 = _touches[ids[0]]
	var b: Vector2 = _touches[ids[1]]
	_multi_mid = (a + b) * 0.5
	_multi_dist = maxf(1.0, a.distance_to(b))

func _update_multi_gesture() -> void:
	var ids := _touches.keys()
	ids.sort()
	if ids.size() < 2:
		return
	var a: Vector2 = _touches[ids[0]]
	var b: Vector2 = _touches[ids[1]]
	var mid := (a + b) * 0.5
	var dist := maxf(1.0, a.distance_to(b))
	var pan := mid - _multi_mid
	var scale := _multi_dist / dist
	var basis := _camera.global_transform.basis
	target += -basis.x * pan.x * distance * 0.0016 + basis.y * pan.y * distance * 0.0016
	distance = clampf(distance * scale, 0.9, 80.0)
	_multi_mid = mid
	_multi_dist = dist
	_preset = "Free"
	_view_chip.text = "Free"
	queue_redraw()

# -------------------------------------------------------------------------
# Picking and gizmo
# -------------------------------------------------------------------------

func _pick(point: Vector2) -> void:
	if doc == null:
		return
	var best_id := ""
	var best_depth := INF
	for obj in doc.objects:
		var id := str(obj.get("id", ""))
		if id == "" or not bool(obj.get("visible", true)):
			continue
		var node: Node3D = doc.nodes.get(id)
		if node == null or not node.visible:
			continue
		var kind := str(obj.get("kind", "mesh"))
		var hit := false
		var depth := INF
		var aabb: AABB = doc.get_object_aabb(id)
		if aabb.size.length() > 0.002:
			var rect := _project_aabb_rect(aabb)
			if rect.has_area() and rect.grow(5.0).has_point(point):
				hit = true
				depth = _camera.global_position.distance_to(aabb.get_center())
		if not hit and (kind == "camera" or kind == "light" or kind == "empty"):
			# Camera, light and empty markers shrink with distance, so their
			# bounds alone make them hard to tap. Give them a fixed screen-space
			# target around the object origin.
			if not _camera.is_position_behind(node.global_position):
				var screen := _to_ui(_camera.unproject_position(node.global_position))
				if screen.distance_to(point) < 26.0:
					hit = true
					depth = _camera.global_position.distance_to(node.global_position)
		if hit and depth < best_depth:
			best_depth = depth
			best_id = id
	doc.set_selection(best_id)

func _project_aabb_rect(aabb: AABB) -> Rect2:
	var corners := _aabb_corners(aabb)
	var rect := Rect2()
	var first := true
	for c in corners:
		if _camera.is_position_behind(c):
			continue
		var p := _to_ui(_camera.unproject_position(c))
		if first:
			rect = Rect2(p, Vector2.ZERO)
			first = false
		else:
			rect = rect.expand(p)
	return rect

func _aabb_corners(aabb: AABB) -> Array:
	var p := aabb.position
	var s := aabb.size
	return [
		p + Vector3(0, 0, 0), p + Vector3(s.x, 0, 0), p + Vector3(0, s.y, 0), p + Vector3(s.x, s.y, 0),
		p + Vector3(0, 0, s.z), p + Vector3(s.x, 0, s.z), p + Vector3(0, s.y, s.z), p + Vector3(s.x, s.y, s.z),
	]

func _to_ui(viewport_pos: Vector2) -> Vector2:
	if _viewport == null or _viewport.size.x <= 0 or _viewport.size.y <= 0:
		return viewport_pos
	var ratio := Vector2(float(size.x) / float(_viewport.size.x), float(size.y) / float(_viewport.size.y))
	return viewport_pos * ratio

func _hit_gizmo(point: Vector2) -> String:
	if tool == "select" or doc == null or doc.selected_id == "":
		return ""
	for handle in _gizmo_handles:
		var handle_pos: Vector2 = handle["pos"]
		if point.distance_to(handle_pos) <= 22.0:
			return str(handle["axis"])
	return ""

func _start_gizmo(axis: String, screen_pos: Vector2) -> void:
	if doc == null or doc.selected_id == "":
		return
	if doc.is_playing:
		doc.pause()
	_mode = "gizmo"
	_gizmo_axis = axis
	_gizmo_start_screen = screen_pos
	_gizmo_drag = Vector2.ZERO
	_gizmo_start_pos = doc.get_selected_node().position
	_gizmo_start_rot = doc.get_selected_node().quaternion
	_gizmo_start_scale = doc.get_selected_node().scale
	var origin := doc.get_selected_node().global_position
	if _gizmo_axis != "free" and not _camera.is_position_behind(origin):
		var p0 := _to_ui(_camera.unproject_position(origin))
		var end_world := origin + _axis_vector(_gizmo_axis) * maxf(0.35, distance * 0.1)
		if not _camera.is_position_behind(end_world):
			var p1 := _to_ui(_camera.unproject_position(end_world))
			if p0.distance_to(p1) > 0.5:
				_gizmo_screen_dir = (p1 - p0).normalized()
	var label: String = {"move": "Move", "rotate": "Rotate", "scale": "Scale"}.get(tool, "Transform")
	doc.begin_edit(label)
	_hud_text = ""
	queue_redraw()

func _apply_gizmo_drag(relative: Vector2) -> void:
	if doc == null or doc.selected_id == "":
		return
	_gizmo_drag += relative
	var axis_vec := _axis_vector(_gizmo_axis)
	var direction := _gizmo_screen_dir
	if axis_vec == Vector3.ZERO:
		direction = Vector2(1, 0)
	if tool == "move":
		var delta: Vector3
		if _gizmo_axis == "free":
			var basis := _camera.global_transform.basis
			var units := distance * 0.0018
			delta = basis.x * _gizmo_drag.x * units - basis.y * _gizmo_drag.y * units
		else:
			var units := 1.0 / maxf(0.08, _pixel_length_for_axis(axis_vec))
			delta = axis_vec * _gizmo_drag.dot(direction) * units
		var next := _gizmo_start_pos + delta
		if doc.snap:
			next = Vector3(snappedf(next.x, 0.1), snappedf(next.y, 0.1), snappedf(next.z, 0.1))
		doc.set_object_transform(doc.selected_id, next, _gizmo_start_rot, _gizmo_start_scale)
		_hud_text = "MOVE  %s  %.3f, %.3f, %.3f" % [_gizmo_axis.to_upper(), next.x, next.y, next.z]
	elif tool == "rotate":
		var angle := 0.0
		if _gizmo_axis == "free":
			angle = _gizmo_drag.x * 0.009
			axis_vec = Vector3.UP
		else:
			var perp := Vector2(-direction.y, direction.x)
			angle = _gizmo_drag.dot(perp) * 0.009
			if doc.snap:
				angle = snappedf(angle, deg_to_rad(5.0))
		var next_rot := Quaternion(axis_vec, angle) * _gizmo_start_rot
		doc.set_object_transform(doc.selected_id, _gizmo_start_pos, next_rot, _gizmo_start_scale)
		_hud_text = "ROTATE  %s  %.1f°" % [_gizmo_axis.to_upper(), angle * 180.0 / PI]
	else:
		var factor := 1.0
		if _gizmo_axis == "free":
			factor = maxf(0.05, 1.0 + _gizmo_drag.x * 0.007)
		else:
			factor = maxf(0.05, 1.0 + _gizmo_drag.dot(direction) * 0.007)
		if doc.snap:
			factor = snappedf(factor, 0.05)
		var next_scale := _gizmo_start_scale
		if _gizmo_axis == "x":
			next_scale.x = _gizmo_start_scale.x * factor
		elif _gizmo_axis == "y":
			next_scale.y = _gizmo_start_scale.y * factor
		elif _gizmo_axis == "z":
			next_scale.z = _gizmo_start_scale.z * factor
		else:
			next_scale = _gizmo_start_scale * factor
		doc.set_object_transform(doc.selected_id, _gizmo_start_pos, _gizmo_start_rot, next_scale)
		_hud_text = "SCALE  %s  ×%.2f" % [_gizmo_axis.to_upper(), factor]
	queue_redraw()

func _finish_gizmo() -> void:
	if doc != null:
		doc.end_edit()
	_mode = "idle"
	_gizmo_axis = ""
	_hud_text = ""
	queue_redraw()

func _axis_vector(axis: String) -> Vector3:
	match axis:
		"x": return Vector3.RIGHT
		"y": return Vector3.UP
		"z": return Vector3.BACK
	return Vector3.ZERO

func _pixel_length_for_axis(axis: Vector3) -> float:
	var origin := doc.get_selected_node().global_position
	if _camera.is_position_behind(origin) or _camera.is_position_behind(origin + axis):
		return 1.0
	var a := _to_ui(_camera.unproject_position(origin))
	var b := _to_ui(_camera.unproject_position(origin + axis))
	return maxf(0.08, a.distance_to(b))

# -------------------------------------------------------------------------
# Drawing
# -------------------------------------------------------------------------

func _draw() -> void:
	if _camera == null or doc == null:
		return
	_draw_selection()
	_draw_gizmo()
	_draw_compass()
	_draw_hud()

func _draw_selection() -> void:
	if doc.selected_id == "":
		return
	var node: Node3D = doc.nodes.get(doc.selected_id)
	if node == null or not node.visible:
		return
	var aabb: AABB = doc.get_object_aabb(doc.selected_id)
	if aabb.size.length() < 0.002:
		if not _camera.is_position_behind(node.global_position):
			var p := _to_ui(_camera.unproject_position(node.global_position))
			draw_arc(p, 15.0, 0.0, TAU, 28, Kit.ACCENT * Color(1, 1, 1, 0.75), 1.5, true)
		return
	var corners := _aabb_corners(aabb)
	var points: Array = []
	for c in corners:
		if _camera.is_position_behind(c):
			points.append(null)
		else:
			points.append(_to_ui(_camera.unproject_position(c)))
	var edges := [
		[0, 1], [1, 3], [3, 2], [2, 0],
		[4, 5], [5, 7], [7, 6], [6, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]
	var color := Kit.ACCENT * Color(1, 1, 1, 0.8)
	for edge in edges:
		var a = points[edge[0]]
		var b = points[edge[1]]
		if a != null and b != null:
			draw_line(a, b, Color(0.02, 0.03, 0.04, 0.45), 3.0, true)
			draw_line(a, b, color, 1.4, true)

func _draw_gizmo() -> void:
	_gizmo_handles.clear()
	if tool == "select" or doc.selected_id == "":
		return
	var node: Node3D = doc.nodes.get(doc.selected_id)
	if node == null or not node.visible:
		return
	var origin := node.global_position
	if _camera.is_position_behind(origin):
		return
	var p0 := _to_ui(_camera.unproject_position(origin))
	var world_len := maxf(0.35, distance * 0.1)
	var axes := [
		["x", Vector3.RIGHT, Kit.AXIS_X],
		["y", Vector3.UP, Kit.AXIS_Y],
		["z", Vector3.BACK, Kit.AXIS_Z],
	]
	var active_color := Kit.ACCENT_BRIGHT
	for entry in axes:
		var axis_name: String = entry[0]
		var axis_vec: Vector3 = entry[1]
		var color: Color = entry[2]
		var end_world := origin + axis_vec * world_len
		if _camera.is_position_behind(end_world):
			continue
		var end_projected := _to_ui(_camera.unproject_position(end_world))
		var raw := end_projected - p0
		if raw.length() < 5.0:
			continue
		var dir := raw.normalized()
		var end := p0 + dir * 48.0
		var is_active := _gizmo_axis == axis_name
		var line_color := active_color if is_active else color
		draw_line(p0, end, Color(0.02, 0.03, 0.04, 0.7), 5.0, true)
		draw_line(p0, end, line_color, 2.4 if is_active else 1.8, true)
		draw_circle(end, 7.0, Color(0.045, 0.06, 0.075, 0.95))
		draw_arc(end, 6.0, 0.0, TAU, 20, line_color, 1.6, true)
		if is_active:
			draw_circle(end, 2.6, line_color)
		_gizmo_handles.append({"axis": axis_name, "pos": end})
		if _gizmo_axis == axis_name:
			_gizmo_screen_dir = dir
	# Centre handle: screen-plane move, uniform scale, or rotation around Y.
	var center_color := active_color if _gizmo_axis == "free" else Kit.TEXT_MUTED
	draw_circle(p0, 6.0, Color(0.045, 0.06, 0.075, 0.95))
	draw_arc(p0, 5.0, 0.0, TAU, 18, center_color, 1.5, true)
	_gizmo_handles.append({"axis": "free", "pos": p0})
	if _gizmo_axis == "free":
		_gizmo_screen_dir = Vector2.RIGHT

func _draw_compass() -> void:
	var center := size - Vector2(34.0, 34.0)
	draw_circle(center, 25.0, Color(0.035, 0.047, 0.062, 0.72))
	draw_arc(center, 25.0, 0.0, TAU, 36, Kit.BORDER_SOFT, 1.0, true)
	var inv := _camera.global_transform.basis.inverse()
	var axes := [
		["X", inv * Vector3.RIGHT, Kit.AXIS_X],
		["Y", inv * Vector3.UP, Kit.AXIS_Y],
		["Z", inv * Vector3.BACK, Kit.AXIS_Z],
	]
	axes.sort_custom(func(a, b): return a[1].z < b[1].z)
	for entry in axes:
		var label: String = entry[0]
		var v: Vector3 = entry[1]
		var dir := Vector2(v.x, -v.y)
		if dir.length() < 0.01:
			dir = Vector2(0, -1)
		dir = dir.normalized()
		var end := center + dir * 16.0
		draw_line(center, end, entry[2], 1.4, true)
		draw_circle(end, 2.2, entry[2])
		var text_pos := center + dir * 22.0 + Vector2(-3.0, 3.0)
		draw_string(Kit.font_mono, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, entry[2])

func _draw_hud() -> void:
	if _hud_text == "":
		return
	var font := Kit.font_mono
	var text_size := font.get_string_size(_hud_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var rect := Rect2(Vector2((size.x - text_size.x) * 0.5 - 10.0, 46.0), text_size + Vector2(20, 12))
	draw_rect(rect, Color(0.03, 0.043, 0.058, 0.9), true)
	draw_rect(rect, Kit.BORDER, false, 1.0)
	draw_string(font, rect.position + Vector2(10, text_size.y + 2), _hud_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Kit.ACCENT_BRIGHT)

# -------------------------------------------------------------------------
# Still capture
# -------------------------------------------------------------------------

func capture_still() -> Image:
	if _viewport == null or _camera == null:
		return null
	var base := _viewport.size
	if base.x < 2 or base.y < 2:
		return null
	var grid_visible := _grid_mesh.visible if _grid_mesh != null else true
	if _grid_mesh != null:
		_grid_mesh.visible = false
	if doc != null:
		doc.markers_hidden = true
		doc.update_marker_scales(_camera)
	# Render the frame at a print-worthy resolution while keeping the exact
	# preview framing. The probe shares the editor world, so lights, materials
	# and the environment are identical to what the viewport shows.
	var factor := clampf(1920.0 / maxf(float(base.x), float(base.y)), 1.0, 4.0)
	var probe := SubViewport.new()
	probe.size = Vector2i(roundi(base.x * factor), roundi(base.y * factor))
	probe.msaa_3d = Viewport.MSAA_4X
	probe.world_3d = _viewport.world_3d
	probe.render_target_update_mode = SubViewport.UPDATE_ONCE
	var shot_camera := Camera3D.new()
	shot_camera.fov = _camera.fov
	shot_camera.near = _camera.near
	shot_camera.far = _camera.far
	shot_camera.global_transform = _camera.global_transform
	shot_camera.current = true
	probe.add_child(shot_camera)
	add_child(probe)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := probe.get_texture().get_image()
	probe.queue_free()
	if doc != null:
		doc.markers_hidden = false
		doc.update_marker_scales(_camera)
	if _grid_mesh != null:
		_grid_mesh.visible = grid_visible
	queue_redraw()
	return image
