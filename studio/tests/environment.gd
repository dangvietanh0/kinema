extends Node
## Environment suite (wave-2 W6).
##
## Checks the procedural studio sky, the lifted environment defaults, the
## shadow readability contract and the single sky-sun rule. Under a real
## display it also renders a SubViewport with the studio environment and
## asserts that the sun core is brighter than its halo and the halo is
## brighter than the surrounding sky. Headless runs print an explicit skip
## for the capture step and still assert every logic contract.

const DocumentScript = preload("res://src/core/document.gd")

const CAPTURE_DIR := "/tmp/opencode/wave2-environment-captures"
const CAPTURE_PATH := CAPTURE_DIR + "/blank-sky.png"
const CAPTURE_SIZE := Vector2i(915, 412)

var _ok := 0
var _failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
	if condition:
		_ok += 1
		print("ENVIRONMENT OK: " + message)
	else:
		_failures.append(message)
		printerr("ENVIRONMENT FAIL: " + message)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_test_shader_builtins()
	_test_environment_defaults()
	await _test_blank_fill_light()
	await _test_sky_sun_mode()
	await _test_shadow_opacity()
	await _test_visual_capture()
	_finish()


func _finish() -> void:
	var status := "PASS" if _failures.is_empty() else "FAIL"
	print("ENVIRONMENT RESULT: %s (%d OK, %d FAIL)" % [status, _ok, _failures.size()])
	if not _failures.is_empty():
		for failure in _failures:
			printerr("  - " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


# -------------------------------------------------------------------------
# 1. Shader built-ins
# -------------------------------------------------------------------------

func _test_shader_builtins() -> void:
	var source := FileAccess.get_file_as_string("res://src/viewport/studio_sky.gdshader")
	_check(source != "", "the studio sky shader is readable")
	for builtin in [
		"LIGHT0_ENABLED", "LIGHT0_DIRECTION", "LIGHT0_COLOR",
		"LIGHT0_ENERGY", "LIGHT0_SIZE",
	]:
		_check(source.contains(builtin), "the sky shader uses %s" % builtin)
	_check(source.contains("halo"), "the sky shader has an explicit halo term")
	_check(source.contains("max(LIGHT0_SIZE, 0.030)"),
		"the sun disc radius clamps LIGHT0_SIZE to 0.030 rad")
	_check(source.contains("dot(EYEDIR, LIGHT0_DIRECTION)"),
		"the sun position comes from the real light direction")
	_check(not source.contains("sun_position") and not source.contains("SUN_POSITION"),
		"the sky shader has no hard-coded sun position")
	_check(not source.contains("fake_sun") and not source.contains("fixed_sun"),
		"the sky shader has no second, decorative sun source")


# -------------------------------------------------------------------------
# 2. Environment defaults
# -------------------------------------------------------------------------

func _test_environment_defaults() -> void:
	var env := Environment.new()
	Gfx.default_environment(env)
	_check(env.ambient_light_energy >= 1.35,
		"ambient light energy is lifted (%.2f)" % env.ambient_light_energy)
	_check(env.background_energy_multiplier >= 1.05,
		"background energy is lifted (%.2f)" % env.background_energy_multiplier)
	_check(env.ssao_enabled, "SSAO stays enabled")
	_check(env.ssao_intensity <= 1.5,
		"SSAO intensity is softened (%.2f)" % env.ssao_intensity)
	_check(env.ssao_light_affect <= 0.10,
		"SSAO light affect is softened (%.2f)" % env.ssao_light_affect)
	_check(env.glow_enabled, "glow stays enabled")
	_check(env.background_mode == Environment.BG_SKY, "the background is the studio sky")
	_check(env.sky != null and env.sky.sky_material is ShaderMaterial,
		"the sky is driven by the procedural studio shader")

	var sun_source := FileAccess.get_file_as_string("res://src/core/document.gd")
	_check(sun_source.contains("light.shadow_opacity = 0.55"),
		"shadow-casting lights get the readable shadow opacity")


# -------------------------------------------------------------------------
# 3. Blank template fill light
# -------------------------------------------------------------------------

func _new_doc(title: String, template: String = "blank") -> Node3D:
	var doc: Node3D = DocumentScript.new()
	add_child(doc)
	await get_tree().process_frame
	doc.new_project(title, template)
	await get_tree().process_frame
	return doc


func _test_blank_fill_light() -> void:
	var doc := await _new_doc("Environment blank", "blank")
	var fill: Dictionary = {}
	for obj in doc.objects:
		if str(obj.get("name", "")) == "Fill Light":
			fill = obj
	_check(not fill.is_empty(), "the blank template contains a Fill Light")
	if fill.is_empty():
		doc.queue_free()
		return
	_check(str(fill.get("light_type", "")) == "omni", "the fill light is a real omni light")
	_check(fill.get("light_shadow", true) == false, "the fill light has light_shadow off")
	_check(is_equal_approx(float(fill.get("light_energy", 0.0)), 0.35),
		"the fill light uses energy 0.35")
	_check(is_equal_approx(float(fill.get("light_range", 0.0)), 7.0),
		"the fill light uses range 7.0")
	var fill_node: Node3D = doc.nodes.get(str(fill.get("id", "")))
	var fill_light: OmniLight3D = null
	if fill_node != null:
		fill_light = fill_node.get_node_or_null("Light") as OmniLight3D
	_check(fill_light != null, "the fill light has a real OmniLight3D node")
	if fill_light != null:
		_check(fill_light.shadow_enabled == false, "the fill light node casts no shadow")
		_check(fill_light.omni_range >= 6.99, "the fill light node has a real range")
	var has_key := false
	for obj in doc.objects:
		if str(obj.get("name", "")) == "Key Light" and str(obj.get("light_type", "")) == "directional":
			has_key = true
	_check(has_key, "the blank template keeps its existing key light")
	_check(doc.objects.size() >= 3, "the blank template keeps at least three objects")
	await get_tree().process_frame
	doc.queue_free()
	await get_tree().process_frame


# -------------------------------------------------------------------------
# 4/5. Sky sun and shadow opacity
# -------------------------------------------------------------------------

func _directional_lights(doc: Node3D) -> Array:
	var lights: Array = []
	for obj in doc.objects:
		if str(obj.get("kind", "")) != "light":
			continue
		if str(obj.get("light_type", "")) != "directional":
			continue
		var node: Node3D = doc.nodes.get(str(obj.get("id", "")))
		if node == null:
			continue
		var light := node.get_node_or_null("Light") as DirectionalLight3D
		if light != null:
			lights.append({"id": str(obj.get("id", "")), "obj": obj, "light": light})
	return lights


func _sky_suns(doc: Node3D) -> Array:
	var suns: Array = []
	for item in _directional_lights(doc):
		var light: DirectionalLight3D = item["light"]
		if light.sky_mode == DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY:
			suns.append(item)
	return suns


func _test_sky_sun_mode() -> void:
	var doc := await _new_doc("Environment sky", "blank")
	var key_id := ""
	for obj in doc.objects:
		if str(obj.get("name", "")) == "Key Light":
			key_id = str(obj.get("id", ""))
	_check(key_id != "", "the blank template has a key light id")
	var suns := _sky_suns(doc)
	_check(suns.size() == 1, "exactly one directional light is the sky sun")
	if suns.size() == 1:
		_check(str(suns[0]["id"]) == key_id, "the key light is the sky sun")
		_check(str(suns[0]["obj"].get("light_type", "")) == "directional",
			"the sky sun is a directional light")

	var second_id: String = doc.add_light("directional")
	await get_tree().process_frame
	_check(second_id != "", "a second directional light can be added")
	_check(_sky_suns(doc).size() == 1, "adding a directional light never creates a second sun")
	if _sky_suns(doc).size() == 1:
		_check(str(_sky_suns(doc)[0]["id"]) == key_id,
			"the first directional light in document order stays the sun")

	doc.set_object_visible(key_id, false)
	await get_tree().process_frame
	var promoted := _sky_suns(doc)
	_check(promoted.size() == 1, "hiding the sun promotes the next visible directional light")
	if promoted.size() == 1:
		_check(str(promoted[0]["id"]) == second_id, "the promoted light is the next directional light")

	doc.set_object_visible(second_id, false)
	await get_tree().process_frame
	_check(_sky_suns(doc).is_empty(), "with no visible directional light the sky sun disappears")
	for item in _directional_lights(doc):
		var light: DirectionalLight3D = item["light"]
		_check(light.sky_mode == DirectionalLight3D.SKY_MODE_LIGHT_ONLY,
			"every non-sun directional light uses SKY_MODE_LIGHT_ONLY")

	# Zero energy is not a sun either: restoring the key energy promotes it back.
	doc.set_object_visible(key_id, true)
	doc.set_object_visible(second_id, true)
	doc.set_light_property(key_id, "light_energy", 0.0)
	await get_tree().process_frame
	_check(_sky_suns(doc).size() == 1 and str(_sky_suns(doc)[0]["id"]) == second_id,
		"a zero-energy directional light does not own the sky")
	doc.set_light_property(key_id, "light_energy", 1.35)
	await get_tree().process_frame
	_check(_sky_suns(doc).size() == 1 and str(_sky_suns(doc)[0]["id"]) == key_id,
		"restoring the key energy restores the first sun")
	doc.queue_free()
	await get_tree().process_frame


func _test_shadow_opacity() -> void:
	var blank := await _new_doc("Environment shadows", "blank")
	var casting := 0
	for obj in blank.objects:
		if str(obj.get("kind", "")) != "light":
			continue
		var node: Node3D = blank.nodes.get(str(obj.get("id", "")))
		var light: Light3D = null
		if node != null:
			light = node.get_node_or_null("Light") as Light3D
		if light == null:
			continue
		if light.shadow_enabled:
			casting += 1
			_check(light.shadow_opacity <= 0.65,
				"light '%s' casts readable shadows (%.2f)" % [str(obj.get("name", "")), light.shadow_opacity])
	_check(casting >= 1, "the blank template has a shadow-casting light")
	blank.queue_free()
	await get_tree().process_frame

	var study := await _new_doc("Environment study", "study")
	var study_casting := 0
	for obj in study.objects:
		if str(obj.get("kind", "")) != "light":
			continue
		var node: Node3D = study.nodes.get(str(obj.get("id", "")))
		var light: Light3D = null
		if node != null:
			light = node.get_node_or_null("Light") as Light3D
		if light == null:
			continue
		if light.shadow_enabled:
			study_casting += 1
			_check(light.shadow_opacity <= 0.65,
				"study light '%s' casts readable shadows (%.2f)" % [str(obj.get("name", "")), light.shadow_opacity])
	_check(study_casting >= 1, "the study template keeps a shadow-casting key light")
	study.queue_free()
	await get_tree().process_frame


# -------------------------------------------------------------------------
# 6. Visual capture (display only)
# -------------------------------------------------------------------------

func _test_visual_capture() -> void:
	if DisplayServer.get_name() == "headless":
		print("ENVIRONMENT SKIP: visual capture requires a display; rerun under xvfb to assert the sky.")
		return
	var viewport := SubViewport.new()
	viewport.size = CAPTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	add_child(viewport)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	Gfx.default_environment(env)
	world.environment = env
	viewport.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	sun.light_energy = 1.35
	sun.light_color = Color(1, 1, 1)
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 60.0
	camera.near = 0.05
	camera.far = 100.0
	viewport.add_child(camera)
	var sun_dir := sun.global_transform.basis.z.normalized()
	camera.look_at(camera.global_position + sun_dir, Vector3.FORWARD)
	camera.current = true
	for _i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	_check(image != null and not image.is_empty(), "the studio sky renders to an image")
	if image == null or image.is_empty():
		viewport.queue_free()
		return
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	var err := image.save_png(CAPTURE_PATH)
	_check(err == OK, "the studio sky capture is written to %s" % CAPTURE_PATH)

	var height := float(image.get_height())
	var focal := (height * 0.5) / tan(deg_to_rad(camera.fov * 0.5))
	var center := Vector2i(image.get_width() / 2, image.get_height() / 2)
	var halo_angle := 0.09
	var sky_angle := 0.42
	var halo := Vector2i(center.x + int(round(tan(halo_angle) * focal)), center.y)
	var sky_point := Vector2i(center.x + int(round(tan(sky_angle) * focal)), center.y)
	var core_luma := _luminance(image, center)
	var halo_luma := _luminance(image, halo)
	var sky_luma := _luminance(image, sky_point)
	print("ENVIRONMENT CAPTURE: core=%.4f halo=%.4f sky=%.4f" % [core_luma, halo_luma, sky_luma])
	_check(core_luma > halo_luma, "the sun core is brighter than its halo")
	_check(halo_luma > sky_luma, "the halo is visibly brighter than the surrounding sky")
	_check(sky_luma > 0.02, "the sky is not near-black (%.4f)" % sky_luma)

	# The disc must move with the real light. Rotate the sun 90 degrees and
	# confirm the old core is no longer the brightest point.
	sun.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var moved: Image = viewport.get_texture().get_image()
	if moved != null and not moved.is_empty():
		var moved_old_core := _luminance(moved, center)
		_check(moved_old_core < core_luma * 0.75,
			"rotating the key light moves the visible sun disc")
	viewport.queue_free()
	await get_tree().process_frame


func _luminance(image: Image, at: Vector2i) -> float:
	var x := clampi(at.x, 0, image.get_width() - 1)
	var y := clampi(at.y, 0, image.get_height() - 1)
	var color := image.get_pixel(x, y)
	return 0.2126 * _linear_channel(color.r) \
		+ 0.7152 * _linear_channel(color.g) \
		+ 0.0722 * _linear_channel(color.b)


func _linear_channel(value: float) -> float:
	if value <= 0.04045:
		return value / 12.92
	return pow((value + 0.055) / 1.055, 2.4)
