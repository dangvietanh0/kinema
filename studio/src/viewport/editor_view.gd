extends Control
## The 3D preview, editor camera and touch transform gizmo.
##
## A SubViewport renders the document world. The surrounding Control draws the
## selection box, the axis gizmo, the orientation compass and transient
## transform readouts. One finger orbits, two fingers pan and pinch, tapping
## selects, dragging an axis manipulates the selected object.

const HUD_BG := Color(0.063, 0.063, 0.063, 0.90)
const DRAFT_SCALE := 0.72
const DRAFT_CAP := 1400
const DRAFT_IDLE_DELAY := 0.45

signal quick_render_requested
signal performance_requested
## The viewport header owns the visible camera/grid controls; the view reports
## its state so the two never disagree.
signal view_changed(label: String)
signal grid_changed(enabled: bool)

const DocumentScript = preload("res://src/core/document.gd")
const TransformGizmo3DScript = preload("res://src/viewport/transform_gizmo_3d.gd")
const NavGizmoScript = preload("res://src/ui/components/nav_gizmo.gd")
var doc: DocumentScript = null
var tool := "select"

var target := Vector3(0.0, 0.8, 0.0)
var yaw := deg_to_rad(38.0)
var pitch := deg_to_rad(18.0)
var distance := 7.4

var _viewport: SubViewport
var _surface: TextureRect
var _camera: Camera3D
var _env_node: WorldEnvironment
var _grid_root: Node3D
var _grid_mesh: MeshInstance3D
## The transform gizmo is one real 3D node in the stage, not a document child.
var _gizmo: Node3D
## While a capture probe renders, editing chrome must stay out of the shared
## world. _draw_gizmo() runs every frame and would otherwise re-show it.
var _gizmo_suppressed := false
## Captures can overlap: a quick still can start while a sequence frame or a
## media export is between its probe awaits. Each holder takes one level and
## the chrome returns only when the last one releases.
var _gizmo_suppression := 0
var _nav_gizmo: Control
var _nav_yaw := INF
var _nav_pitch := INF
var _nav_density := -1.0
var _fps_chip: Button
var _quick_render_button: Button
## The viewport header owns the visible grid and frame controls. These two
## references keep the frozen shell test (and any older call site) able to
## inspect the real buttons without a second, invisible copy in the HUD.
var _grid_button: Button = null
var _focus_button: Button = null
var _hud_root: Control
var _preset := "Persp"
var _grid_on := true
## Real-time render preview. The editor chrome disappears, the document plays
## at full quality, and only the render transport stays on screen.
var render_mode := false
var _render_grid_was_on := true
var _render_draft_was_on := true
var _render_hud_was_on := true
var _render_markers_were_hidden := true

var _touches: Dictionary = {}
var _mode := "idle"  # idle | orbit | gizmo | multi | pan
var _gesture_start := Vector2.ZERO
var _tap_candidate := false
var _gizmo_axis := ""
## The handle under the real pointer, if any. Touch has no hover; a mouse
## highlights the axis it is about to grab.
var _hover_axis := ""
var _gizmo_start_pos := Vector3.ZERO
var _gizmo_start_rot := Quaternion.IDENTITY
var _gizmo_start_scale := Vector3.ONE
var _gizmo_start_screen := Vector2.ZERO
var _gizmo_screen_dir := Vector2.RIGHT
var _gizmo_world_len := 1.0
var _gizmo_drag := Vector2.ZERO
var _gizmo_handles: Array = []
## Workbench preferences that affect direct manipulation. Defaults match the
## historical behaviour; Settings writes the real values.
var gizmo_scale := 1.0
var translate_snap := 0.25
var rotate_snap := 15.0
var scale_snap := 0.25
var _hud_text := ""
var _multi_mid := Vector2.ZERO
var _multi_dist := 1.0
var _pan_last := Vector2.ZERO
var _camera_ready := false
var _interactive := false
var _preview_scale := 1.0
var _preview_cap := 1920
var _dirty_visual := true
var _redraw_needed := true
var _draft_enabled := true
var _draft_active := false
var _draft_idle := 0.0
var _playback_active := false
var _draft_chip: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	_draft_enabled = Gfx.draft_editing if Gfx != null else true
	_build_viewport()
	_build_hud()
	resized.connect(_on_resized)
	call_deferred("_on_resized")
	set_process(true)
	if Perf != null:
		Perf.watch(self)

func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "PreviewViewport"
	_viewport.gui_disable_input = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.size = Vector2i(1280, 800)
	_viewport.add_to_group("kinema_viewport")
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
	env_node.name = "StudioEnvironment"
	var env := Environment.new()
	Gfx.default_environment(env)
	env_node.environment = env
	env_node.add_to_group("kinema_environment")
	_viewport.add_child(env_node)
	_env_node = env_node

	_camera = Camera3D.new()
	_camera.name = "EditorCamera"
	_camera.fov = 46.0
	_camera.near = 0.04
	_camera.far = 400.0
	_camera.current = true
	_viewport.add_child(_camera)

	_build_stage()

	# The gizmo is parented once to the stage SubViewport. It is not part of
	# the document, so selecting, deleting or reloading objects never orphans
	# it and its geometry is never serialised.
	_gizmo = TransformGizmo3DScript.new()
	_gizmo.name = "TransformGizmo3D"
	_gizmo.set_visible_gizmo(false)
	_viewport.add_child(_gizmo)

	Gfx.apply_viewport(_viewport)
	if not Gfx.changed.is_connected(_on_graphics_changed):
		Gfx.changed.connect(_on_graphics_changed)

func _on_graphics_changed() -> void:
	if _viewport != null:
		Gfx.apply_viewport(_viewport)
	if _env_node != null and _env_node.environment != null:
		Gfx.apply_environment(_env_node.environment)
	# A settings edit during an interaction must not silently restore full
	# quality; the draft pass is the last word until the gesture ends.
	if _draft_active:
		_apply_draft_state()
	_repaint()

func _build_stage() -> void:
	_grid_root = Node3D.new()
	_grid_root.name = "StudioStage"
	_viewport.add_child(_grid_root)

	# A single large floor with a procedural, distance-faded grid. Drawing the
	# grid as a line mesh produced heavy moire and temporal smearing in
	# Forward+, and it z-fought the floor at grazing angles.
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	ground.mesh = plane
	ground.position.y = -0.012
	var ground_mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.035, 0.035, 0.035, 1.0);
uniform vec4 minor_color : source_color = vec4(0.075, 0.075, 0.075, 1.0);
uniform vec4 major_color : source_color = vec4(0.135, 0.135, 0.135, 1.0);
uniform vec4 axis_x_color : source_color = vec4(0.190, 0.190, 0.190, 1.0);
uniform vec4 axis_z_color : source_color = vec4(0.155, 0.155, 0.155, 1.0);
uniform float cell_size = 0.5;
uniform float major_every = 4.0;
uniform float grid_strength : hint_range(0.0, 1.0) = 1.0;
uniform float fade_start = 7.0;
uniform float fade_end = 26.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_mask(vec2 coord) {
	vec2 grid = abs(fract(coord - 0.5) - 0.5) / max(fwidth(coord), vec2(0.00001));
	return 1.0 - min(min(grid.x, grid.y), 1.0);
}

void fragment() {
	float dist = length(world_pos.xz - CAMERA_POSITION_WORLD.xz);
	float fade = (1.0 - smoothstep(fade_start, fade_end, dist)) * grid_strength;
	float minor = grid_mask(world_pos.xz / cell_size);
	float major = grid_mask(world_pos.xz / (cell_size * major_every));
	float axis_x = 1.0 - smoothstep(0.0, fwidth(world_pos.z) * 1.6, abs(world_pos.z));
	float axis_z = 1.0 - smoothstep(0.0, fwidth(world_pos.x) * 1.6, abs(world_pos.x));

	vec3 color = base_color.rgb;
	color = mix(color, minor_color.rgb, minor * 0.55 * fade);
	color = mix(color, major_color.rgb, major * 0.80 * fade);
	color = mix(color, axis_x_color.rgb, axis_x * 0.60 * fade);
	color = mix(color, axis_z_color.rgb, axis_z * 0.60 * fade);
	color *= mix(0.52, 1.0, 1.0 - smoothstep(5.0, 24.0, dist));

	ALBEDO = color;
	ROUGHNESS = 0.94;
	SPECULAR = 0.22;
	METALLIC = 0.0;
}
"""
	ground_mat.shader = shader
	ground.material_override = ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grid_root.add_child(ground)
	_grid_mesh = ground

func _set_grid_strength(value: float) -> void:
	if _grid_mesh == null:
		return
	var material := _grid_mesh.material_override as ShaderMaterial
	if material != null:
		material.set_shader_parameter("grid_strength", clampf(value, 0.0, 1.0))

func _build_hud() -> void:
	_hud_root = Control.new()
	_hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud_root)

	var top_left := HBoxContainer.new()
	top_left.add_theme_constant_override("separation", 6)
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_left.offset_left = 12
	top_left.offset_top = 10
	top_left.grow_vertical = Control.GROW_DIRECTION_END
	_hud_root.add_child(top_left)

	# Camera, grid and frame moved to the viewport header, which occupies
	# layout space instead of floating over the image. The HUD keeps only the
	# transient draft tag, the FPS chip and the render shortcut.
	# A quiet draft tag explains the softer image during gestures; it never
	# appears on the idle viewport or in a render.
	var draft_panel := PanelContainer.new()
	var draft_style := Kit.flat_style(HUD_BG, Kit.R_FLOAT, Color(0, 0, 0, 0), 0)
	draft_style.content_margin_left = 8
	draft_style.content_margin_right = 8
	draft_style.content_margin_top = 4
	draft_style.content_margin_bottom = 4
	draft_panel.add_theme_stylebox_override("panel", draft_style)
	draft_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draft_panel.visible = false
	_draft_chip = draft_panel
	_draft_chip.add_child(Kit.mono_label("DRAFT", 11, Kit.TEXT_DIM))
	top_left.add_child(_draft_chip)

	var top_right := HBoxContainer.new()
	top_right.add_theme_constant_override("separation", 6)
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.offset_right = -12
	top_right.offset_top = 10
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.grow_vertical = Control.GROW_DIRECTION_END
	_hud_root.add_child(top_right)

	# The FPS chip is the always-on performance readout on touch devices. It
	# is sampled at 4 Hz, not per frame, and opens the detailed overlay.
	_fps_chip = Button.new()
	_fps_chip.text = "—"
	_fps_chip.tooltip_text = "Frames per second · tap for performance details"
	_fps_chip.focus_mode = Control.FOCUS_NONE
	_fps_chip.custom_minimum_size = Vector2(48, 44)
	_fps_chip.add_theme_font_override("font", Kit.font_mono)
	_fps_chip.add_theme_font_size_override("font_size", 11)
	_fps_chip.add_theme_color_override("font_color", Kit.TEXT_MUTED)
	_fps_chip.add_theme_color_override("font_hover_color", Kit.TEXT)
	_fps_chip.add_theme_color_override("font_pressed_color", Kit.TEXT)
	_override_hud_button(_fps_chip)
	_fps_chip.pressed.connect(func() -> void: performance_requested.emit())
	top_right.add_child(_fps_chip)

	# Render is an icon-only 44 dp square, so the HUD row has one height and
	# one target size. A labelled button made the right cluster wider than the
	# viewport on a phone and read as a call to action rather than a tool.
	_quick_render_button = Kit.icon_button("camera", "Quick render at full quality", 44, 20)
	_override_hud_button(_quick_render_button)
	_quick_render_button.pressed.connect(func() -> void: quick_render_requested.emit())
	top_right.add_child(_quick_render_button)

	# Orientation control: a 116 dp floating surface in the stage's
	# bottom-right corner, 12 dp in from both edges. It sits in the HUD layer,
	# above the image but below the timeline and any modal sheet.
	_nav_gizmo = NavGizmoScript.new()
	_nav_gizmo.name = "NavGizmo"
	var nav_size: float = NavGizmoScript.GIZMO_SIZE
	_nav_gizmo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_nav_gizmo.offset_left = -(nav_size + 12.0)
	_nav_gizmo.offset_top = -(nav_size + 12.0)
	_nav_gizmo.offset_right = -12.0
	_nav_gizmo.offset_bottom = -12.0
	_nav_gizmo.view_requested.connect(_on_nav_view_requested)
	_hud_root.add_child(_nav_gizmo)

func _override_hud_button(button: Button) -> void:
	# HUD controls read as floating surfaces, not framed cards. State is
	# carried by fill and glyph luminance; only the field frames in the
	# inspector and the region hairlines keep an outline. A floating control
	# gets the 4 px radius so it reads as detached from the stage.
	button.add_theme_stylebox_override("normal", Kit.flat_style(HUD_BG, Kit.R_FLOAT, Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("hover", Kit.flat_style(Kit.SURFACE_HOVER, Kit.R_FLOAT, Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("pressed", Kit.flat_style(Kit.SURFACE_ACTIVE, Kit.R_FLOAT, Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("hover_pressed", Kit.flat_style(Kit.SURFACE_ACTIVE, Kit.R_FLOAT, Color(0, 0, 0, 0), 0))
	button.add_theme_color_override("font_color", Kit.TEXT_MUTED)
	button.add_theme_color_override("font_pressed_color", Kit.FOCUS_BRIGHT)
	button.add_theme_color_override("icon_pressed_color", Kit.FOCUS_BRIGHT)
	button.add_theme_color_override("icon_hover_pressed_color", Kit.FOCUS_BRIGHT)

func set_document(document: Node3D) -> void:
	if doc == document:
		return
	doc = document
	# Locators are drawn by the viewport overlay; the document's 3D marker
	# meshes remain available for tooling and still renders but stay out of
	# the editing view.
	doc.markers_hidden = true
	_viewport.add_child(doc)
	doc.scene_changed.connect(_on_scene_changed)
	doc.selection_changed.connect(_on_selection_changed)
	doc.transform_changed.connect(_on_transform_changed)
	doc.keyframes_changed.connect(_on_keyframes_changed)
	doc.object_changed.connect(_on_object_changed)
	doc.playback_changed.connect(_on_playback_changed)
	_frame_all(false)
	call_deferred("_reframe_after_layout")
	queue_redraw()

## Called by the shell once the viewport header exists. The view does not
## parent these controls; it only keeps the header and the view in step.
func bind_header_controls(grid_button: Button, frame_button: Button) -> void:
	_grid_button = grid_button
	_focus_button = frame_button
	if _grid_button != null:
		_grid_button.set_pressed_no_signal(_grid_on)

func set_tool(new_tool: String) -> void:
	tool = new_tool
	_hover_axis = ""
	_draw_gizmo()
	queue_redraw()


func set_gizmo_scale(value: float) -> void:
	gizmo_scale = clampf(value, 0.5, 2.0)
	_draw_gizmo()
	queue_redraw()


func set_snap_values(translate: float, rotate: float, scale: float) -> void:
	translate_snap = clampf(translate, 0.001, 100.0)
	rotate_snap = clampf(rotate, 0.1, 180.0)
	scale_snap = clampf(scale, 0.001, 10.0)

## Enter or leave the live render preview. Editing overlays, locators and the
## grid are hidden; the quality pass is forced back to the user's full
## settings. The document transport is owned by the editor.
func set_render_mode(enabled: bool) -> void:
	if render_mode == enabled:
		return
	render_mode = enabled
	if enabled:
		_render_grid_was_on = _grid_on
		_render_draft_was_on = _draft_enabled
		_render_hud_was_on = _hud_root != null and _hud_root.visible
		_render_markers_were_hidden = doc == null or doc.markers_hidden
		_grid_on = false
		grid_changed.emit(false)
		_set_grid_strength(0.0)
		set_hud_visible(false)
		if _nav_gizmo != null:
			# The nav gizmo is part of the HUD but is also checked on its own;
			# hide the control, not only its ancestor.
			_nav_gizmo.visible = false
		set_draft_quality(false)
		if doc != null:
			doc.markers_hidden = true
			doc.update_marker_scales(_camera)
		_touches.clear()
		_mode = "idle"
		_gizmo_axis = ""
		_hud_text = ""
		if _viewport != null:
			_viewport.render_target_update_mode = (
				SubViewport.UPDATE_ALWAYS if doc != null and doc.is_playing
				else SubViewport.UPDATE_ONCE
			)
	else:
		_grid_on = _render_grid_was_on
		grid_changed.emit(_grid_on)
		_set_grid_strength(1.0 if _render_grid_was_on else 0.0)
		set_hud_visible(_render_hud_was_on)
		if _nav_gizmo != null:
			_nav_gizmo.visible = true
		set_draft_quality(_render_draft_was_on)
		if doc != null:
			doc.markers_hidden = _render_markers_were_hidden
			doc.update_marker_scales(_camera)
		if _viewport != null and not _interactive and not _playback_active:
			_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_repaint()
	queue_redraw()

func _on_resized() -> void:
	_apply_viewport_size()
	_draw_gizmo()
	_repaint()

## Device pixels per UI unit. The window is in physical pixels while the
## canvas is in dp, so this ratio is the display density the stage, the nav
## gizmo and every capture must respect.
func _device_pixel_scale() -> float:
	var win := get_window()
	var visible := get_viewport().get_visible_rect().size
	if win != null and visible.x > 1.0 and visible.y > 1.0:
		return clampf(minf(float(win.size.x) / visible.x, float(win.size.y) / visible.y), 1.0, 4.0)
	return 1.0


func _apply_viewport_size() -> void:
	if _viewport == null:
		return
	# Render the preview at device resolution instead of at UI units. Phones
	# scale the canvas by their display density, so the raw control size would
	# produce a soft, upscaled 3D image. The adaptive quality scale and the cap
	# trade sharpness for frame time; both are reported in the performance HUD.
	var pixel_scale := _device_pixel_scale()
	var quality_scale := 1.0 if render_mode else _preview_scale
	var target := Vector2(size.x, size.y) * pixel_scale * quality_scale
	var cap := float(_preview_cap)
	if _draft_active:
		target *= DRAFT_SCALE
		cap = minf(cap, float(DRAFT_CAP))
	var longest := maxf(target.x, target.y)
	if longest > cap:
		target *= cap / longest
	var w := maxi(2, int(round(target.x)))
	var h := maxi(2, int(round(target.y)))
	if _viewport.size != Vector2i(w, h):
		_viewport.size = Vector2i(w, h)
		if _viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _process(delta: float) -> void:
	if _draft_enabled:
		if _interactive or _playback_active:
			_draft_idle = 0.0
			_begin_draft()
		else:
			_draft_idle += delta
			if _draft_active and _draft_idle >= DRAFT_IDLE_DELAY:
				_end_draft()
	if _camera == null:
		return
	var offset := Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw)
	) * distance
	_camera.global_position = target + offset
	_camera.look_at(target, Vector3.UP)
	_sync_nav()
	if doc == null:
		_draw_gizmo()
		return
	doc.update_marker_scales(_camera)
	# The 3D gizmo follows animated transforms and camera moves every frame;
	# its handles are rebuilt from the same projection the hit test uses.
	_draw_gizmo()
	_dirty_visual = true
	# The overlay only redraws when something visible changed; the old
	# unconditional redraw re-ran the compass, gizmo and HUD text every frame.
	if _redraw_needed:
		_redraw_needed = false
		queue_redraw()

# -------------------------------------------------------------------------
# Document events and view helpers
# -------------------------------------------------------------------------

func _on_scene_changed() -> void:
	_draw_gizmo()
	queue_redraw()

func _on_selection_changed(_id: String) -> void:
	_hover_axis = ""
	_draw_gizmo()
	queue_redraw()

func _on_object_changed(_id: String) -> void:
	_repaint()

func _on_transform_changed(_id: String) -> void:
	_note_edit_burst()
	_repaint()

func _on_keyframes_changed(_id: String) -> void:
	_note_edit_burst()
	_repaint()

func _on_playback_changed(_time: float, _playing: bool) -> void:
	_playback_active = _playing
	if _playing:
		_begin_draft()
	else:
		_draft_idle = 0.0
	# Render mode is a real-time preview: while the document plays it must
	# render every frame, not one frame per edit. Draft quality is disabled
	# for the duration, so playback here is the full-quality image.
	if render_mode and _viewport != null:
		_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if _playing else SubViewport.UPDATE_ONCE
		)
	_repaint()

## Inspector edits and keying can change the scene many times per second while
## a field is dragged. Keep the draft pass alive for the burst, then restore.
func _note_edit_burst() -> void:
	_draft_idle = 0.0
	if _draft_enabled:
		_begin_draft()

## Ask for exactly one rendered frame. On-demand previews keep the GPU idle
## while nothing moves; gestures switch to continuous rendering instead.
func request_preview_update() -> void:
	if _viewport == null:
		return
	_dirty_visual = true
	if _viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_redraw_needed = true

func set_interactive(active: bool) -> void:
	if _viewport == null:
		return
	_interactive = active
	if active:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	elif _viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_dirty_visual = true
	_redraw_needed = true

## Gestures render continuously from the first accepted event until the last
## finger or button is released; a tap that only changes the selection renders
## a single frame.
func _preview_busy_check() -> void:
	var busy := _mode == "gizmo" or _mode == "orbit" or _mode == "multi" or _mode == "pan"
	if busy != _interactive:
		set_interactive(busy)

func is_interactive() -> bool:
	return _interactive

## Called from Perf.sample_updated at 4 Hz. The chip is a real monitor readout,
## not a decoration: a missing sample shows a dash.
func set_fps_value(fps: float, frame_ms: float) -> void:
	if _fps_chip == null:
		return
	if fps > 0.0:
		_fps_chip.text = "%d" % int(round(fps))
		if fps >= 55.0:
			_fps_chip.add_theme_color_override("font_color", Kit.TEXT)
		elif fps >= 30.0:
			_fps_chip.add_theme_color_override("font_color", Kit.TEXT_MUTED)
		else:
			_fps_chip.add_theme_color_override("font_color", Kit.DANGER)
	else:
		_fps_chip.text = "—"
		_fps_chip.add_theme_color_override("font_color", Kit.TEXT_DIM)
	if frame_ms >= 0.0:
		_fps_chip.tooltip_text = "Frames per second · %.1f ms · tap for performance details" % frame_ms
	else:
		_fps_chip.tooltip_text = "Frames per second · tap for performance details"

func set_fps_chip_visible(on: bool) -> void:
	if _fps_chip != null:
		_fps_chip.visible = on

func set_hud_visible(on: bool) -> void:
	if _hud_root != null:
		_hud_root.visible = on

func preview_size() -> Vector2i:
	if _viewport == null:
		return Vector2i.ZERO
	return Vector2i(_viewport.size)

func is_draft_active() -> bool:
	return _draft_active

## Draft mode is the edit-time quality pass: no MSAA, no screen-space
## lighting, no glow, a lower internal resolution and cheap shadow filtering.
## It is only active while the camera, gizmo, playback or an inspector edit is
## moving; the idle scene and every render capture use the full settings.
func set_draft_quality(enabled: bool) -> void:
	_draft_enabled = enabled
	if not enabled:
		_end_draft()
	elif _interactive or _playback_active:
		_begin_draft()

func _begin_draft() -> void:
	if not _draft_enabled or _draft_active or _viewport == null:
		return
	_draft_active = true
	_apply_draft_state()
	_apply_viewport_size()
	_refresh_draft_chip()
	_repaint()

func _end_draft() -> void:
	if not _draft_active:
		return
	_draft_active = false
	if _viewport != null:
		Gfx.apply_viewport(_viewport)
	if _env_node != null and _env_node.environment != null:
		Gfx.apply_environment(_env_node.environment)
	Gfx.apply_globals()
	_apply_viewport_size()
	_refresh_draft_chip()
	_repaint()

func _apply_draft_state() -> void:
	if _viewport != null:
		_viewport.msaa_3d = Viewport.MSAA_DISABLED
		_viewport.scaling_3d_scale = minf(Gfx.scale_3d, 0.75)
	if _env_node != null and _env_node.environment != null:
		var env := _env_node.environment
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.ssr_enabled = false
		env.glow_enabled = false
		env.volumetric_fog_enabled = false
	RenderingServer.directional_soft_shadow_filter_set_quality(0)
	RenderingServer.positional_soft_shadow_filter_set_quality(0)

func _refresh_draft_chip() -> void:
	if _draft_chip != null:
		_draft_chip.visible = _draft_active

func set_preview_scale(value: float) -> void:
	_preview_scale = clampf(value, 0.25, 1.0)
	_apply_viewport_size()

func set_preview_cap(value: int) -> void:
	_preview_cap = clampi(value, 480, 7680)
	_apply_viewport_size()

func _repaint() -> void:
	_dirty_visual = true
	_redraw_needed = true
	_draw_gizmo()
	if _viewport != null and _viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

## The navigation gizmo's only output is a canonical view request. Keeping the
## route here means the header menu and the stage gizmo share one camera path.
func _on_nav_view_requested(label: String) -> void:
	set_view_preset(label)

## Applies one of the four canonical camera presets. The viewport header
## owns the menu; this method is the single entry point so a future camera
## selector can call the same path.
func set_view_preset(label: String) -> void:
	match label:
		"Front":
			_apply_preset("Front", 0.0, 0.0)
		"Right":
			_apply_preset("Right", PI * 0.5, 0.0)
		"Top":
			_apply_preset("Top", 0.0, 1.45)
		_:
			_apply_preset("Persp", deg_to_rad(38.0), deg_to_rad(18.0))

func _apply_preset(label: String, new_yaw: float, new_pitch: float) -> void:
	_preset = label
	yaw = new_yaw
	pitch = new_pitch
	_set_view_label(label)
	queue_redraw()

func _set_view_label(label: String) -> void:
	view_changed.emit(label)

## The navigation gizmo only re-renders when the orbit actually changes; an
## idle frame leaves its SubViewport untouched.
func _sync_nav() -> void:
	if _nav_gizmo == null:
		return
	var density := _device_pixel_scale()
	if not is_equal_approx(density, _nav_density):
		_nav_density = density
		_nav_gizmo.set_pixel_density(density)
	if is_equal_approx(_nav_yaw, yaw) and is_equal_approx(_nav_pitch, pitch):
		return
	_nav_yaw = yaw
	_nav_pitch = pitch
	_nav_gizmo.set_orientation(yaw, pitch)

func _on_grid_toggled(enabled: bool) -> void:
	_grid_on = enabled
	grid_changed.emit(enabled)
	_set_grid_strength(1.0 if enabled else 0.0)
	_repaint()


## Frames the whole scene. The shell's Frame all action and the empty-state
## button both route here.
func frame_all() -> void:
	_frame_all(true)


func toggle_grid() -> void:
	# The header button is the visible control; this entry point keeps the
	# stage, the header and any shortcut in step through one signal.
	_on_grid_toggled(not _grid_on)

func grid_enabled() -> bool:
	return _grid_on


## The header toggle is the source of intent; writing the requested state
## instead of flipping the current one keeps a queued duplicate toggle honest.
func set_grid_enabled(enabled: bool) -> void:
	if _grid_on == enabled:
		return
	_on_grid_toggled(enabled)

func view_preset() -> String:
	return _preset

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
	if render_mode:
		# The render preview is a viewing surface, not an editing one. The
		# transport is a sibling control, so its taps still arrive normally.
		return
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
		_preview_busy_check()
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
		_preview_busy_check()

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
	_preview_busy_check()

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		distance = clampf(distance * 0.9, 0.9, 80.0)
		accept_event()
		_preview_busy_check()
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		distance = clampf(distance * 1.1, 0.9, 80.0)
		accept_event()
		_preview_busy_check()
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
		_preview_busy_check()
	else:
		if _mode == "gizmo":
			_finish_gizmo()
		elif _mode == "orbit" and _tap_candidate:
			_pick(event.position)
		_mode = "idle"
		_tap_candidate = false
		accept_event()
		_preview_busy_check()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _mode == "idle":
		_update_hover(event.position)
		return
	if _mode == "gizmo":
		_apply_gizmo_drag(event.relative)
	elif _mode == "orbit":
		_orbit(event.relative)
	else:
		return
	accept_event()
	_preview_busy_check()

## Highlight the handle the pointer is over. Touch never produces this path,
## so a drag never depends on a hover state.
func _update_hover(point: Vector2) -> void:
	var next := ""
	if not render_mode and tool != "select" and doc != null and doc.selected_id != "":
		next = _hit_gizmo(point)
	if next == _hover_axis:
		return
	_hover_axis = next
	_draw_gizmo()

func _orbit(relative: Vector2) -> void:
	if relative.length() < 0.01:
		return
	if absf(relative.x) + absf(relative.y) > 2.0:
		_tap_candidate = false
	yaw -= relative.x * 0.0062
	pitch = clampf(pitch + relative.y * 0.0062, -1.35, 1.45)
	_preset = "Free"
	_set_view_label("Free")
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
	_set_view_label("Free")
	queue_redraw()

# -------------------------------------------------------------------------
# Picking and gizmo
# -------------------------------------------------------------------------

func _pick(point: Vector2) -> void:
	if doc == null or render_mode:
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

## Hit radius in UI units: always at least the 44 dp floor (22 px per side)
## and scaled with the visual arm, so a large gizmo is not a small target.
func gizmo_hit_radius() -> float:
	if _gizmo_handles.is_empty():
		return 22.0
	var origin := Vector2.INF
	for handle in _gizmo_handles:
		if str(handle.get("axis", "")) == "free":
			origin = handle.get("pos", Vector2.INF)
	if origin == Vector2.INF:
		return 22.0
	var reach := 0.0
	for handle in _gizmo_handles:
		if str(handle.get("axis", "")) != "free":
			reach = maxf(reach, origin.distance_to(handle.get("pos", Vector2.ZERO)))
	# Ring samples sit at 0.74 of the arm, so divide them back to the arm.
	if tool == "rotate":
		reach /= 0.74
	return maxf(22.0, reach * 0.30)


func _hit_gizmo(point: Vector2) -> String:
	if render_mode or tool == "select" or doc == null or doc.selected_id == "":
		return ""
	# Rebuild the projected handles from the current camera before testing, so
	# a tap after an orbit or a selection change never uses stale points.
	_draw_gizmo()
	var radius := gizmo_hit_radius()
	var best := ""
	var best_distance := radius
	for handle in _gizmo_handles:
		var distance := point.distance_to(handle["pos"])
		if distance <= best_distance:
			best_distance = distance
			best = str(handle["axis"])
	return best

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
		# The direction is the projected axis tip, not a fixed screen vector,
		# so the drag follows the real foreshortened arm.
		var end_world := origin + _axis_vector(_gizmo_axis) * maxf(0.35, distance * 0.1)
		if _gizmo != null and _gizmo.visible:
			end_world = _gizmo.axis_tip_world(_gizmo_axis)
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
			next = Vector3(
				snappedf(next.x, translate_snap),
				snappedf(next.y, translate_snap),
				snappedf(next.z, translate_snap)
			)
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
				angle = snappedf(angle, deg_to_rad(rotate_snap))
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
			factor = snappedf(factor, scale_snap)
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
	if render_mode:
		# Render mode is the clean frame. Locators, selection, gizmo, compass
		# and transient HUD text would all leak editing chrome into the shot.
		return
	_draw_object_markers()
	_draw_selection()
	_draw_gizmo()
	_draw_hud()

## Camera, light and empty locators are drawn in screen space. A world-space
## wireframe shrinks into an unreadable speck at typical edit distances; the
## same glyphs the outliner uses stay legible and make the scene structure
## obvious without adding chrome to the viewport.
func _draw_object_markers() -> void:
	if doc == null or _camera == null:
		return
	for obj in doc.objects:
		var kind := str(obj.get("kind", ""))
		if kind != "camera" and kind != "light" and kind != "empty":
			continue
		var id := str(obj.get("id", ""))
		var node: Node3D = doc.nodes.get(id)
		if node == null or not node.visible:
			continue
		if _camera.is_position_behind(node.global_position):
			continue
		if _camera.global_position.distance_to(node.global_position) < 0.6:
			continue
		var p := _to_ui(_camera.unproject_position(node.global_position))
		if p.x < -24.0 or p.y < -24.0 or p.x > size.x + 24.0 or p.y > size.y + 24.0:
			continue
		var icon_name := "camera"
		if kind == "light":
			icon_name = "lightbulb"
		elif kind == "empty":
			icon_name = "circle-dot-dashed"
		var selected := id == doc.selected_id
		var box := Rect2(p - Vector2(11, 11), Vector2(22, 22))
		var texture := Kit.icon_texture(icon_name)
		draw_texture_rect(texture, Rect2(box.position + Vector2(1, 1), box.size), false, Color(0, 0, 0, 0.6))
		draw_texture_rect(texture, box, false, Kit.TEXT if selected else Kit.TEXT_MUTED)
		if selected:
			draw_arc(p, 15.0, 0.0, TAU, 28, Kit.ACCENT * Color(1, 1, 1, 0.7), 1.0, true)

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
			draw_line(a, b, Color(0.01, 0.01, 0.01, 0.45), 3.0, true)
			draw_line(a, b, color, 1.4, true)

## Update the 3D gizmo and rebuild the projected handles it is tapped through.
## No gizmo pixels are drawn here: the stage SubViewport owns the geometry, and
## this overlay only keeps the screen-space hit points in step with it.
func _draw_gizmo() -> void:
	_gizmo_handles.clear()
	if _gizmo == null or _camera == null:
		return
	if _gizmo_suppressed:
		_gizmo.set_visible_gizmo(false)
		return
	var on := tool != "select" and doc != null and doc.selected_id != "" and not render_mode
	var node: Node3D = null
	if on:
		node = doc.get_selected_node()
		if node == null or not node.visible or _camera.is_position_behind(node.global_position):
			on = false
	_gizmo.set_visible_gizmo(on)
	if not on:
		_hover_axis = ""
		return
	var origin := node.global_position
	_gizmo.px_per_dp = float(_viewport.size.y) / maxf(1.0, size.y)
	_gizmo.set_tool(tool)
	_gizmo.set_active_axis(_gizmo_axis)
	_gizmo.set_hover_axis(_hover_axis)
	_gizmo.set_target(origin, _camera, _viewport.size.y, gizmo_scale)
	var p0 := _to_ui(_camera.unproject_position(origin))
	if tool == "rotate":
		# The torus is the surface. Sample its projected ring so a tap on the
		# visible ring returns the axis that owns it.
		for axis_name in ["x", "y", "z"]:
			for index in 32:
				var angle := TAU * float(index) / 32.0
				var point: Vector3 = _gizmo.ring_point_world(axis_name, angle)
				if _camera.is_position_behind(point):
					continue
				_gizmo_handles.append({
					"axis": axis_name,
					"pos": _to_ui(_camera.unproject_position(point)),
				})
	else:
		for axis_name in ["x", "y", "z"]:
			var tip: Vector3 = _gizmo.axis_tip_world(axis_name)
			if _camera.is_position_behind(tip):
				continue
			_gizmo_handles.append({
				"axis": axis_name,
				"pos": _to_ui(_camera.unproject_position(tip)),
			})
	# Centre handle: screen-plane move, uniform scale, or rotation around Y.
	_gizmo_handles.append({"axis": "free", "pos": p0})

func _draw_hud() -> void:
	if _hud_text == "":
		return
	var font := Kit.font_mono
	var text_size := font.get_string_size(_hud_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var rect := Rect2(Vector2((size.x - text_size.x) * 0.5 - 10.0, 46.0), text_size + Vector2(20, 12))
	draw_rect(rect, Color(0.063, 0.063, 0.063, 0.92), true)
	draw_rect(rect, Kit.BORDER, false, 1.0)
	draw_string(font, rect.position + Vector2(10, text_size.y + 2), _hud_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Kit.ACCENT_BRIGHT)

# -------------------------------------------------------------------------
# Still capture
# -------------------------------------------------------------------------

## Editing chrome never belongs in a capture. A one-shot hide cannot survive
## the per-frame rebuild, so the depth is held for the whole probe render and
## released only after the image has been read. Nested captures take one level
## each; the flag clears when the last holder releases.
func _set_gizmo_suppressed(on: bool) -> void:
	_gizmo_suppression = maxi(0, _gizmo_suppression + (1 if on else -1))
	_gizmo_suppressed = _gizmo_suppression > 0
	if _gizmo != null:
		_gizmo.set_suppressed(_gizmo_suppressed)


func capture_still(long_edge: int = 1920, msaa: int = Viewport.MSAA_4X) -> Image:
	if _viewport == null or _camera == null:
		return null
	var base := _viewport.size
	if base.x < 2 or base.y < 2:
		return null
	# A capture is never allowed to inherit the draft pass. Restore the full
	# viewport and environment, let one frame settle, then render the probe.
	var was_draft := _draft_active
	if _draft_active:
		_end_draft()
		await RenderingServer.frame_post_draw
	var grid_visible := _grid_on
	_set_grid_strength(0.0)
	# The transform gizmo lives in the stage world, so a world-sharing probe
	# would photograph it. The HUD and navigation gizmo are canvas items of the
	# main viewport, not part of this probe's world, so they cannot enter.
	_set_gizmo_suppressed(true)
	var markers_were_hidden := false
	if doc != null:
		markers_were_hidden = doc.markers_hidden
		doc.markers_hidden = true
		doc.update_marker_scales(_camera)
	# Render the frame at an explicit long edge while keeping the exact preview
	# framing. The probe shares the editor world, so lights, materials and the
	# environment are identical to what the viewport shows. Downscaling is
	# allowed so a resolution preset is honoured on large desktop viewports.
	var factor := clampf(float(long_edge) / maxf(float(base.x), float(base.y)), 0.1, 8.0)
	var probe := SubViewport.new()
	probe.size = Vector2i(maxi(2, roundi(base.x * factor)), maxi(2, roundi(base.y * factor)))
	probe.msaa_3d = msaa
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
	_set_gizmo_suppressed(false)
	if doc != null:
		doc.markers_hidden = markers_were_hidden
		doc.update_marker_scales(_camera)
	if _grid_mesh != null:
		_set_grid_strength(1.0 if grid_visible else 0.0)
	_draw_gizmo()
	# Resume the draft pass only if the editor is still moving; an idle
	# capture leaves the viewport at full quality.
	if was_draft and _draft_enabled and (_interactive or _playback_active):
		_begin_draft()
	queue_redraw()
	return image

## Render one frame from an explicit camera at an exact pixel size. Used by the
## sequence renderer, GIF and MP4 exporters; never crops or letterboxes.
func capture_with_camera(size: Vector2i, msaa: int, xform: Transform3D, fov: float, transparent_bg := false) -> Image:
	if _viewport == null or _camera == null:
		return null
	if size.x < 2 or size.y < 2:
		return null
	var was_draft := _draft_active
	if _draft_active:
		_end_draft()
		await RenderingServer.frame_post_draw
	var grid_visible := _grid_on
	_set_grid_strength(0.0)
	# The transform gizmo lives in the stage world, so a world-sharing probe
	# would photograph it. The HUD and navigation gizmo are canvas items of the
	# main viewport, not part of this probe's world, so they cannot enter.
	_set_gizmo_suppressed(true)
	var markers_were_hidden := false
	if doc != null:
		markers_were_hidden = doc.markers_hidden
		doc.markers_hidden = true
		doc.update_marker_scales(_camera)
	var probe := SubViewport.new()
	probe.size = size
	probe.msaa_3d = msaa
	probe.world_3d = _viewport.world_3d
	probe.transparent_bg = transparent_bg
	probe.render_target_update_mode = SubViewport.UPDATE_ONCE
	var shot_camera := Camera3D.new()
	shot_camera.fov = fov
	shot_camera.near = _camera.near
	shot_camera.far = _camera.far
	shot_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	probe.add_child(shot_camera)
	shot_camera.global_transform = xform
	shot_camera.current = true
	add_child(probe)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := probe.get_texture().get_image()
	probe.queue_free()
	_set_gizmo_suppressed(false)
	if doc != null:
		doc.markers_hidden = markers_were_hidden
		doc.update_marker_scales(_camera)
	if _grid_mesh != null:
		_set_grid_strength(1.0 if grid_visible else 0.0)
	if _gizmo != null:
		_draw_gizmo()
	if was_draft and _draft_enabled and (_interactive or _playback_active):
		_begin_draft()
	queue_redraw()
	return image

## UI-space projection for the rig overlay. The preview is stretched to fill
## the control, so the viewport point must be mapped through the same ratio.
func world_to_screen(world: Vector3) -> Vector2:
	if _camera == null or _viewport == null:
		return Vector2.ZERO
	return _to_ui(_camera.unproject_position(world))

## UI-space ray for bone picking and IK target drags.
func screen_ray(screen: Vector2) -> Dictionary:
	if _camera == null or _viewport == null:
		return {"origin": Vector3.ZERO, "direction": Vector3.FORWARD}
	var base := _viewport.size
	if base.x <= 0 or base.y <= 0 or size.x <= 0 or size.y <= 0:
		return {
			"origin": _camera.global_position,
			"direction": -_camera.global_transform.basis.z,
		}
	var ratio := Vector2(float(size.x) / float(base.x), float(size.y) / float(base.y))
	var viewport_pos := screen / ratio
	return {
		"origin": _camera.project_ray_origin(viewport_pos),
		"direction": _camera.project_ray_normal(viewport_pos),
	}
