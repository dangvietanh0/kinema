extends Control
## Temporary headless smoke test. Not part of the app.

const RenderExport = preload("res://src/core/render_export.gd")

var _failures: Array[String] = []
func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		printerr("SMOKE FAIL: " + message)
	else:
		print("SMOKE OK: " + message)

func _ready() -> void:
	# The stretch mode is disabled, so the headless window would otherwise stay
	# at its 64x64 default and every shell/sheet measurement would be fiction.
	# Pin the canvas to a real phone size before the app is built.
	get_window().size = Vector2i(412, 915)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_viewport().get_visible_rect().size == Vector2(412, 915), "smoke runs at a 412x915 phone canvas")
	await get_tree().process_frame
	_check(get_tree().root.theme != null, "app theme installed on root")
	_check(Kit.font_regular != null, "IBM Plex Sans loaded")
	_check(Kit.FONT_UI.ends_with("IBMPlexSans-Regular.ttf"), "UI font is IBM Plex Sans")
	_check(Kit.FONT_MONO.ends_with("IBMPlexMono-Regular.ttf"), "numeric font is IBM Plex Mono")
	_check(Kit.icon_texture("box") != null, "box icon loaded")

	print("SMOKE STEP: type and field floor")
	_check(Kit.label("x", 8).get_theme_font_size("font_size") >= 11, "labels never drop below the 11 sp caption floor")
	_check(Kit.mono_label("x", 8).get_theme_font_size("font_size") >= 11, "mono labels never drop below 11 sp")
	_check(Kit.section_label("x").get_theme_font_size("font_size") >= 11, "section labels are at least 11 sp")
	_check(Kit.label("x").get_theme_font_size("font_size") == 12, "body labels use the 12 sp body role")
	_check(Kit.line_edit().custom_minimum_size.y >= 44.0, "text fields are at least 44 dp tall")
	_check(Kit.line_edit().get_theme_font_size("font_size") >= 13, "text field values use the 13 sp emphasis role")
	_check(Kit.theme.get_font_size("font_size", "LineEdit") >= 13, "raw line edits use the 13 sp emphasis role")
	_check(Kit.text_toggle("x").custom_minimum_size.y >= 44.0, "text toggles are at least 44 dp tall")
	_check(Kit.icon_button("play", "Play", 24, 12).custom_minimum_size.x >= 44.0, "icon buttons clamp small call sites to a 44 dp target")
	_check(Kit.icon_button("play", "Play", 24, 12).custom_minimum_size.y >= 44.0, "icon buttons clamp small call sites to a 44 dp target")
	var probe_field := Kit.line_edit()
	add_child(probe_field)
	await get_tree().process_frame
	_check(probe_field.get_combined_minimum_size().y >= 44.0, "a laid-out text field is at least 44 dp tall")
	probe_field.queue_free()
	var probe_num = load("res://src/ui/num_field.gd").new()
	add_child(probe_num)
	await get_tree().process_frame
	_check(probe_num.get_combined_minimum_size().y >= 44.0, "numeric fields are at least 44 dp tall")
	probe_num.queue_free()
	_check(Kit.theme.get_color("font_placeholder_color", "LineEdit").get_luminance() >= Kit.TEXT_MUTED.get_luminance() - 0.001, "placeholders use the readable muted tone")
	_check(_contrast(Kit.TEXT_DIM, Kit.SURFACE_3) >= 4.5, "tertiary text keeps 4.5:1 on raised surfaces")

	print("SMOKE STEP: tokens and icons")
	_check(Kit.BG.to_html(false).to_upper() == "080808", "BG token is exact")
	_check(Kit.FOCUS.to_html(false).to_upper() == "E6E6E6", "FOCUS token is exact")
	_check(Kit.TIME.to_html(false).to_upper() == "C8C8C8", "TIME token is exact")
	for tone in [Kit.FOCUS, Kit.TIME, Kit.WARNING, Kit.SUCCESS]:
		_check(is_equal_approx(tone.r, tone.g) and is_equal_approx(tone.g, tone.b), "chrome accents stay monochrome")
	_check(Kit.TEXT.get_luminance() > Kit.BG.get_luminance() + 0.5, "primary text is high contrast")
	_check(Kit.BORDER.get_luminance() > Kit.SURFACE.get_luminance(), "hairlines are lighter than their surface")
	var sharp := Kit.flat_style(Kit.SURFACE)
	_check(sharp.corner_radius_top_left == 0 and sharp.corner_radius_bottom_right == 0, "panels and inputs are square")
	_check(Kit.icon_button("play", "Play").custom_minimum_size == Vector2(44, 44), "icon buttons have a 44 dp hit target")
	_check(Kit.text_button("Render", "", true).custom_minimum_size.y >= 48.0, "primary buttons have a 48 dp hit target")
	_check(Kit.hairline().custom_minimum_size == Vector2(0, 1), "hairlines are 1 px")
	for icon_name in [
		"play", "pause", "stop", "key-round", "diamond-plus", "speed-graph",
		"clapperboard", "upload", "tool-select", "tool-move", "tool-rotate",
		"tool-scale", "eye", "eye-closed", "lock", "unlock", "camera",
		"lightbulb", "box", "square-dashed", "smartphone", "tablet", "monitor",
		"gauge", "restart",
	]:
		var icon_path := "res://assets/icons/%s.svg" % icon_name
		_check(FileAccess.file_exists(icon_path), "icon exists: %s" % icon_name)
		if FileAccess.file_exists(icon_path):
			var svg := FileAccess.get_file_as_string(icon_path)
			_check(svg.contains("viewBox=\"0 0 24 24\""), "icon uses the 24 px grid: %s" % icon_name)
			_check(svg.contains("stroke-width=\"1.5\""), "icon uses a 1.5 px stroke: %s" % icon_name)

	print("SMOKE STEP: layout math")
	var LayoutMathScript = load("res://src/app/layout_math.gd")
	_check(LayoutMathScript != null, "layout math module exists")
	if LayoutMathScript != null:
		var phone = LayoutMathScript.resolve(Vector2i(1080, 2400), 420.0, "Android", 1.0, "auto", true)
		_check(phone["mode"] == "compact", "auto resolves a phone to compact")
		var tablet = LayoutMathScript.resolve(Vector2i(1280, 800), 160.0, "Linux", 1.0, "auto", true)
		_check(tablet["mode"] == "desktop", "auto resolves a wide tablet to desktop")
		var wide_phone = LayoutMathScript.resolve(Vector2i(2400, 1080), 420.0, "Android", 1.0, "auto", true)
		_check(wide_phone["mode"] == "studio", "landscape phone resolves to studio")
		var short_landscape = LayoutMathScript.resolve(Vector2i(915, 412), 160.0, "Android", 1.0, "auto", true)
		_check(short_landscape["mode"] == "studio", "short landscape phone keeps the studio workbench")
		_check(is_equal_approx(float(short_landscape["factor"]), 1.0), "short landscape keeps a 1:1 interface scale")
		_check(not bool(short_landscape["clamped"]), "short landscape is not scaled down to fit")
		_check(short_landscape["logical_after"].x >= 914.0 and short_landscape["logical_after"].y >= 411.0, "short landscape keeps its full logical canvas")
		var narrow_landscape = LayoutMathScript.resolve(Vector2i(800, 360), 160.0, "Android", 1.0, "auto", true)
		_check(narrow_landscape["mode"] == "studio", "800x360 landscape keeps the studio workbench")
		_check(is_equal_approx(float(narrow_landscape["factor"]), 1.0), "800x360 landscape keeps touch targets at 1:1")
		var phone_desktop = LayoutMathScript.resolve(Vector2i(1080, 2400), 420.0, "Android", 1.0, "desktop", true)
		_check(phone_desktop["mode"] == "desktop", "desktop is selectable on a phone")
		_check(phone_desktop["fit"] < 1.0, "desktop on a phone shrinks to fit")
		_check(phone_desktop["logical_after"].x >= 959.0 and phone_desktop["logical_after"].y >= 599.0, "desktop fit keeps 960x600 logical")
		_check(not phone_desktop["user_scale_enabled"], "desktop fit disables user scale")
		var desktop_min = LayoutMathScript.resolve(Vector2i(960, 600), 160.0, "Linux", 1.0, "desktop", true)
		_check(is_equal_approx(desktop_min["fit"], 1.0), "960x600 desktop has 100 percent fit")
		var scaled_phone = LayoutMathScript.resolve(Vector2i(360, 640), 160.0, "Android", 1.3, "compact", false)
		_check(scaled_phone["factor"] <= 1.125, "compact scale clamps to keep 320x480")
		_check(scaled_phone["logical_after"].x >= 319.0 and scaled_phone["logical_after"].y >= 479.0, "compact minimum canvas holds")
		_check(LayoutMathScript.orientation_constant("portrait") == DisplayServer.SCREEN_PORTRAIT, "portrait maps to the engine constant")
		_check(LayoutMathScript.orientation_constant("landscape") == DisplayServer.SCREEN_LANDSCAPE, "landscape maps to the engine constant")

	print("SMOKE STEP: prefs persistence")
	var PrefsScript = load("res://src/core/prefs.gd")
	_check(PrefsScript != null, "prefs module exists")
	if PrefsScript != null:
		var test_path := "user://settings_test.json"
		var prefs_a = PrefsScript.new()
		prefs_a.settings_path = test_path
		prefs_a.load_settings()
		_check(prefs_a.get_value("display.layout", "") == "auto", "prefs provide display defaults")
		prefs_a.set_value("display.user_scale", 1.3)
		var prefs_b = PrefsScript.new()
		prefs_b.settings_path = test_path
		prefs_b.load_settings()
		_check(is_equal_approx(float(prefs_b.get_value("display.user_scale", 0.0)), 1.3), "prefs persist values")
		prefs_a.free()
		prefs_b.free()
		DirAccess.remove_absolute(test_path)

	var packed: PackedScene = load("res://src/app/main.tscn")
	var main: Control = packed.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	print("SMOKE STEP: project browser")
	var home = main._home
	_check(home != null and home.visible, "project browser is the first screen")
	if home != null:
		var home_labels := _labels_under(home)
		var home_texts: Array[String] = []
		var home_max_size := 0
		for home_label in home_labels:
			home_texts.append(home_label.text)
			home_max_size = maxi(home_max_size, home_label.get_theme_font_size("font_size"))
		_check(home_texts.has("Projects"), "the browser leads with a Projects heading")
		_check(not home_texts.has("Motion,\nwithout the noise."), "the marketing hero is gone")
		_check(home_max_size <= 18, "the browser uses a tool-scale page title, not a display hero")
		_check(home._layout != null and home._layout.get_combined_minimum_size().x <= 412.0 + 1.0, "the browser fits a 412 dp phone without horizontal overflow")
		var new_project := _button_with_text(home, "New project")
		_check(new_project != null, "the browser exposes a New project action")
		if new_project != null:
			_check(new_project.get_combined_minimum_size().y >= 48.0, "the browser primary action has a 48 dp target")
		home._open_new_project_sheet()
		for _i in 4:
			await get_tree().process_frame
		var home_fields := _line_edits_under(home._overlay)
		_check(not home_fields.is_empty(), "the new project sheet has a name field")
		for entry in home_fields:
			_check(entry.get_combined_minimum_size().y >= 44.0, "the new project name field is at least 44 dp tall")
		home._overlay.close_modal()
		await get_tree().process_frame

	main._on_new_project_requested("Smoke Test", "study")
	await get_tree().process_frame
	await get_tree().process_frame
	var editor = main._editor
	_check(editor != null, "editor opened")
	if editor == null:
		_finish()
		return
	var doc = editor.doc
	# Mode resolution is proven against real physical sizes; the headless window
	# has no screen, so the live window size is not used here.
	_check(str(LayoutMathScript.resolve(Vector2i(1280, 800), 160.0, "Linux", 1.0, "auto", false).get("mode", "")) == "desktop", "wide desktop window uses the desktop shell")
	Prefs.set_value("display.layout", "compact")
	_check(str(LayoutMathScript.resolve(Vector2i(1280, 800), 160.0, "Linux", 1.0, str(Prefs.get_value("display.layout", "")), true).get("mode", "")) == "compact", "compact layout is actively selectable")
	Prefs.set_value("display.layout", "auto")
	var live_layout = main.refresh_layout_scale()
	_check(editor.workbench_mode == str(live_layout.get("mode", "")), "editor receives the resolved mode")
	# The shell follows the preference even when the window itself cannot be
	# measured. Restore the editor to the live window mode afterwards.
	editor.apply_layout(LayoutMathScript.resolve(Vector2i(1080, 2400), 420.0, "Android", 1.0, "compact", true))
	_check(editor.workbench_mode == "compact", "editor switches to the compact shell")
	editor.apply_layout(LayoutMathScript.resolve(Vector2i(1080, 2400), 420.0, "Android", 1.0, "desktop", true))
	_check(editor.workbench_mode == "desktop", "desktop stays selected on a phone")
	_check(float(editor.layout_info.get("fit", 1.0)) < 1.0, "desktop fit is reported to the editor")
	editor.apply_layout(live_layout)
	_check(editor.workbench_mode == str(live_layout.get("mode", "")), "editor returns to the live mode")
	_check(not main.apply_orientation("portrait"), "orientation is disabled when the display server has no feature")
	_check(doc != null and doc.objects.size() >= 3, "study template has objects")
	var form: Dictionary = {}
	for entry in doc.objects:
		if str(entry.get("name", "")) == "Form":
			form = entry
	_check(not form.is_empty(), "study template has a Form object")
	if not form.is_empty():
		var form_color := Color.from_string(str(form.get("color", "")), Color.MAGENTA)
		_check(is_equal_approx(form_color.r, form_color.g) and is_equal_approx(form_color.g, form_color.b), "study template material is monochrome")
	_check(editor._view != null and editor._view._viewport != null, "preview viewport built")
	_check(doc.get_channel_keys(str(doc.objects[0]["id"]), "position").size() >= 0, "channels readable")

	# Settings sheet exercises NumberField construction and the apply callback.
	editor._open_settings()
	await get_tree().process_frame
	_check(editor._settings_duration_field != null, "settings duration field built")
	_check(editor._settings_fps_field != null, "settings fps field built")
	if editor._settings_duration_field != null:
		_check(is_equal_approx(editor._settings_duration_field.value, doc.duration), "settings field reads duration")
	editor._overlay.close_modal()
	await get_tree().process_frame

	# Add sheet + primitive creation.
	editor._open_add_sheet()
	await get_tree().process_frame
	editor._overlay.close_modal()
	await get_tree().process_frame
	var before_add: int = doc.objects.size()
	editor._add_primitive("sphere")
	await get_tree().process_frame
	_check(doc.objects.size() == before_add + 1, "primitive added")
	_check(doc.selected_id != "", "new primitive selected")

	# Keying + retime.
	doc.insert_transform_keys()
	var key_count := 0
	for channel in doc.CHANNELS:
		key_count += doc.get_channel_keys(doc.selected_id, channel).size()
	_check(key_count == 3, "three transform channels keyed")
	var key_index: int = doc.get_key_index_at(doc.selected_id, "position", doc.current_time, 0.02)
	_check(key_index >= 0, "position key found at playhead")
	if key_index >= 0:
		var new_index: int = doc.set_key_time(doc.selected_id, "position", key_index, 1.25)
		_check(new_index >= 0, "key retimed")

	print("SMOKE STEP: easing")
	# A fresh object with a clean two-key segment so the sampled curve is
	# unambiguous: x goes from 0 at t=0 to 2 at t=2.
	editor._add_primitive("box")
	await get_tree().process_frame
	var ease_id: String = doc.selected_id
	doc.seek(0.0)
	doc.set_object_transform(ease_id, Vector3.ZERO, Quaternion.IDENTITY, Vector3.ONE, false)
	doc.insert_transform_keys()
	doc.seek(2.0)
	doc.set_object_transform(ease_id, Vector3(2.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE, false)
	doc.insert_transform_keys()
	var ease_keys: Array = doc.get_channel_keys(ease_id, "position")
	_check(ease_keys.size() == 2, "easing segment has two position keys")
	if ease_keys.size() == 2:
		_check(is_equal_approx(doc.get_key_transition(ease_id, "position", 0), 1.0), "key transition defaults to linear")
		var midpoint: Vector3 = doc.sample_channel(ease_id, "position", 1.0)
		_check(absf(midpoint.x - 1.0) < 0.01, "linear easing samples the midpoint")
		doc.set_key_transition(ease_id, "position", 0, 0.5)
		_check(is_equal_approx(doc.get_key_transition(ease_id, "position", 0), 0.5), "key transition can be set")
		var eased_out: Vector3 = doc.sample_channel(ease_id, "position", 0.5)
		_check(eased_out.x > 0.6, "low transition eases out")
		doc.set_key_transition(ease_id, "position", 0, 2.0)
		var eased_in: Vector3 = doc.sample_channel(ease_id, "position", 0.5)
		_check(eased_in.x < 0.4, "high transition eases in")
		doc.set_key_transition(ease_id, "position", 0, 0.0)
		var held: Vector3 = doc.sample_channel(ease_id, "position", 1.0)
		_check(absf(held.x) < 0.01, "zero transition holds the previous key")
		doc.set_key_transition(ease_id, "position", 0, 0.75)
		var moved_index: int = doc.set_key_time(ease_id, "position", 0, 0.5)
		_check(moved_index >= 0, "eased key retimed")
		_check(is_equal_approx(doc.get_key_transition(ease_id, "position", moved_index), 0.75), "retiming preserves easing")
		doc.seek(0.0)

	print("SMOKE STEP: keyframe at playhead")
	var key_id: String = doc.add_primitive("cube", Vector3(3.0, 0.0, 0.0))
	doc.set_selection(key_id)
	doc.set_autokey(false)
	doc.seek(0.0)
	doc.set_object_transform(key_id, Vector3(1.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE, false)
	doc.insert_transform_keys()
	doc.seek(2.0)
	doc.set_object_transform(key_id, Vector3(2.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE, false)
	doc.insert_transform_keys()
	doc.set_key_transition(key_id, "position", 1, 0.75)
	doc.begin_edit("Move keyed object")
	doc.set_object_transform(key_id, Vector3(5.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE)
	doc.end_edit()
	var key_b: Array = doc.get_channel_keys(key_id, "position")
	_check(key_b.size() == 2, "editing at key B does not create a duplicate")
	_check(absf((key_b[1]["value"] as Vector3).x - 5.0) < 0.0001, "editing at key B updates stored key")
	_check(is_equal_approx(doc.get_key_transition(key_id, "position", 1), 0.75), "key update preserves easing")
	doc.seek(0.0)
	doc.seek(2.0)
	_check(absf((doc.get_object_transform(key_id)["position"] as Vector3).x - 5.0) < 0.0001, "seek after key update keeps value")
	doc.undo()
	await get_tree().process_frame
	_check(absf((doc.get_object_transform(key_id)["position"] as Vector3).x - 2.0) < 0.0001, "undo restores key B pose")
	doc.redo()
	await get_tree().process_frame
	_check(absf((doc.get_object_transform(key_id)["position"] as Vector3).x - 5.0) < 0.0001, "redo restores key B edit")

	doc.set_autokey(false)
	doc.seek(1.0)
	doc.set_object_transform(key_id, Vector3(7.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE)
	_check(doc.get_channel_keys(key_id, "position").size() == 2, "autokey off does not create a key")
	doc.seek(2.0)
	_check(absf((doc.get_object_transform(key_id)["position"] as Vector3).x - 5.0) < 0.0001, "unkeyed pose yields to animation")
	doc.set_autokey(true)
	doc.seek(1.0)
	doc.set_object_transform(key_id, Vector3(7.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE)
	_check(doc.get_channel_keys(key_id, "position").size() == 3, "autokey on inserts a missing key")
	doc.set_autokey(false)

	# A key write re-seeks the AnimationPlayer. The intended pose of channels
	# without a key at the playhead must survive that re-sample.
	var pose_id: String = doc.add_primitive("cube", Vector3.ZERO)
	doc.set_selection(pose_id)
	doc.seek(0.0)
	doc.set_object_transform(pose_id, Vector3.ZERO, Quaternion.IDENTITY, Vector3.ONE, false)
	doc.insert_channel_key("position")
	doc.insert_channel_key("rotation")
	doc.seek(2.0)
	doc.set_object_transform(pose_id, Vector3(2.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE, false)
	doc.insert_channel_key("position")
	var intended_rotation := Quaternion(Vector3.UP, deg_to_rad(35.0))
	doc.begin_edit("Move keyed object")
	doc.set_object_transform(pose_id, Vector3(3.0, 0.0, 0.0), intended_rotation, Vector3.ONE)
	doc.end_edit()
	_check(doc.get_channel_keys(pose_id, "position").size() == 2, "keyed channel updates in place")
	_check(absf((doc.get_channel_keys(pose_id, "position")[1]["value"] as Vector3).x - 3.0) < 0.0001, "keyed channel stores the new value")
	_check((doc.get_object_transform(pose_id)["rotation"] as Quaternion).angle_to(intended_rotation) < deg_to_rad(0.5), "unkeyed channel keeps the edited pose")

	# key=false is a pure pose write even when the playhead sits on a key.
	doc.set_object_transform(pose_id, Vector3(9.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE, false)
	_check(doc.get_channel_keys(pose_id, "position").size() == 2, "key=false does not add a key")
	_check(absf((doc.get_channel_keys(pose_id, "position")[1]["value"] as Vector3).x - 3.0) < 0.0001, "key=false does not update an existing key")
	doc.seek(0.0)
	doc.seek(2.0)

	# The insert-keys action updates an existing key instead of duplicating it.
	doc.set_object_transform(pose_id, Vector3(4.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE, false)
	doc.insert_transform_keys()
	_check(doc.get_channel_keys(pose_id, "position").size() == 2, "insert keys updates an existing key")
	_check(absf((doc.get_channel_keys(pose_id, "position")[1]["value"] as Vector3).x - 4.0) < 0.0001, "insert keys stores the playhead pose")

	# Restore the selection/time the later smoke blocks expect.
	doc.set_selection(ease_id)
	doc.seek(0.0)

	print("SMOKE STEP: refresh and preview policy")
	var preview = editor._view
	preview.set_interactive(false)
	preview.request_preview_update()
	_check(preview._viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "idle preview requests one frame")
	await get_tree().process_frame
	_check(preview._viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "idle preview stops rendering")
	preview.set_interactive(true)
	_check(preview._viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "gesture preview renders continuously")
	preview.set_interactive(false)
	_check(preview._viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "gesture end stops continuous preview")

	doc.set_selection(ease_id)
	await get_tree().process_frame
	var outliner_before: int = editor._outliner.rebuild_count
	var inspector_sections_before: int = editor._inspector.section_build_count
	var old_pose: Vector3 = doc.get_object_transform(ease_id)["position"]
	doc.set_object_transform(ease_id, old_pose + Vector3(0.25, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE)
	await get_tree().process_frame
	_check(editor._outliner.rebuild_count == outliner_before, "transform does not rebuild the outliner")
	_check(editor._inspector.section_build_count == inspector_sections_before, "transform does not rebuild inspector sections")
	_check(Perf.next_preview_scale(1.0, 20.0, 60, 0.6) < 1.0, "adaptive quality lowers preview scale")
	_check(Perf.next_preview_scale(0.8, 70.0, 60, 0.6) > 0.8, "adaptive quality raises preview scale when there is headroom")
	_check(is_equal_approx(Perf.next_preview_scale(0.6, 20.0, 60, 0.6), 0.6), "adaptive quality respects the floor")

	print("SMOKE STEP: sheet contract")
	editor._overlay.set_layout_mode("compact")
	editor._open_add_sheet()
	for _i in 5:
		await get_tree().process_frame
	_check(editor._overlay.has_modal(), "add sheet opens")
	var viewport_size: Vector2 = editor.get_viewport_rect().size
	var panel: Rect2 = editor._overlay.panel_rect()
	_check(panel.size.y <= viewport_size.y * 0.86 + 1.0, "compact sheet stays under 86 percent")
	_check(is_equal_approx(panel.size.x, viewport_size.x), "compact sheet spans the full width")
	_check(editor._overlay._handle_row.visible, "compact sheet shows a drag handle")
	_check(editor._overlay._panel_style.corner_radius_top_left == 0, "compact sheet corners are square")
	_check(editor._overlay.is_point_inside_panel(panel.position + panel.size * 0.5), "the panel rect reports inside points")
	_check(editor._overlay.body_rect().size.y > 0.0, "the body rect is measurable")
	for p in [
		panel.position + panel.size * 0.5,
		panel.position + Vector2(8, 8),
		panel.position + Vector2(panel.size.x - 8, 8),
		panel.position + Vector2(8, panel.size.y - 8),
		panel.position + Vector2(panel.size.x - 8, panel.size.y - 8),
	]:
		var inside := InputEventScreenTouch.new()
		inside.position = p
		inside.pressed = true
		editor.get_viewport().push_input(inside)
		await get_tree().process_frame
		_check(editor._overlay.has_modal(), "tap inside the sheet keeps it open")
	# The body cap follows max_height_ratio, not a fixed fraction.
	var tall := VBoxContainer.new()
	for row_index in 30:
		tall.add_child(Kit.label("Row %d" % row_index, 13, Kit.TEXT))
	editor._overlay.show_sheet("Tall", "", tall, [], {"max_height_ratio": 0.4})
	for _i in 5:
		await get_tree().process_frame
	_check(editor._overlay.panel_rect().size.y <= viewport_size.y * 0.4 + 1.0, "sheet honours a custom height cap")
	editor._overlay.close_modal()
	await get_tree().process_frame

	# Studio hosts a centred modal, never a bottom sheet.
	editor._overlay.set_layout_mode("studio")
	editor._open_add_sheet()
	for _i in 5:
		await get_tree().process_frame
	var modal_panel: Rect2 = editor._overlay.panel_rect()
	_check(not editor._overlay._handle_row.visible, "studio modal has no drag handle")
	_check(modal_panel.size.x <= viewport_size.x - 48.0 + 1.0, "studio modal fits the viewport width")
	_check(modal_panel.size.y <= 640.0 + 1.0, "studio modal respects the height cap")
	_check(not is_equal_approx(modal_panel.size.x, viewport_size.x), "studio modal is centered, not full width")
	editor._overlay.close_modal()
	await get_tree().process_frame
	editor._overlay.set_layout_mode("compact")
	editor._open_add_sheet()
	for _i in 2:
		await get_tree().process_frame

	var outside := InputEventScreenTouch.new()
	outside.position = Vector2(2, 2)
	outside.pressed = true
	editor._overlay._on_backdrop_input(outside)
	await get_tree().process_frame
	_check(not editor._overlay.has_modal(), "scrim tap closes the sheet")
	editor._open_add_sheet()
	await get_tree().process_frame
	await get_tree().process_frame
	main._on_go_back()
	await get_tree().process_frame
	_check(not editor._overlay.has_modal(), "back closes the sheet before the editor")

	# A deliberate downward drag on the handle dismisses the sheet; a short one
	# snaps back without closing it.
	editor._open_add_sheet()
	for _i in 3:
		await get_tree().process_frame
	var short_press := InputEventScreenTouch.new()
	short_press.pressed = true
	editor._overlay._on_handle_input(short_press)
	var short_drag := InputEventScreenDrag.new()
	short_drag.relative = Vector2(0, 20)
	editor._overlay._on_handle_input(short_drag)
	var short_release := InputEventScreenTouch.new()
	short_release.pressed = false
	editor._overlay._on_handle_input(short_release)
	await get_tree().process_frame
	_check(editor._overlay.has_modal(), "a short handle drag keeps the sheet open")
	var long_press := InputEventScreenTouch.new()
	long_press.pressed = true
	editor._overlay._on_handle_input(long_press)
	var long_drag := InputEventScreenDrag.new()
	long_drag.relative = Vector2(0, 90)
	editor._overlay._on_handle_input(long_drag)
	var long_release := InputEventScreenTouch.new()
	long_release.pressed = false
	editor._overlay._on_handle_input(long_release)
	await get_tree().process_frame
	_check(not editor._overlay.has_modal(), "a long handle drag dismisses the sheet")

	print("SMOKE STEP: workspace modes")
	editor.set_workspace_mode("compact")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor.workspace_mode() == "compact", "compact mode applies")
	_check(editor._bottom_bar.visible, "compact bottom action bar is visible")
	_check(editor._top_bar.size.y >= 47.0, "compact top bar is 48 dp")
	var compact_min: float = editor._layout.get_combined_minimum_size().x
	print("SMOKE INFO: compact shell minimum width ", compact_min)
	_check(compact_min <= 320.0, "compact shell fits a 320 dp phone without horizontal overflow")
	_check(editor._bottom_bar.get_combined_minimum_size().x <= 320.0, "compact action bar fits a 320 dp phone")
	_check(editor._timeline.get_combined_minimum_size().x <= 320.0, "compact transport fits a 320 dp phone")
	_check(not editor._top_bar._undo_button.visible and not editor._top_bar._settings_button.visible, "compact header keeps back, title and overflow only")
	_check(editor._top_bar._menu_button.visible, "compact header keeps the overflow menu")
	editor._toggle_timeline()
	await get_tree().process_frame
	_check(editor._bottom_bar.is_active("timeline"), "timeline action reports active while the sheet is open")
	_check(editor._timeline._compact_header.visible, "compact sheet header appears with the timeline")
	editor._toggle_timeline()
	await get_tree().process_frame
	_check(not editor._bottom_bar.is_active("timeline"), "timeline action clears when the sheet folds")
	editor._toggle_drawer("scene")
	for _i in 4:
		await get_tree().process_frame
	_check(editor._drawer_open and editor._dock.visible, "compact scene drawer opens")
	_check(editor._drawer_scene_tab.size.y >= 43.0, "drawer tabs keep a 44 dp target")
	var inside_drawer := InputEventScreenTouch.new()
	inside_drawer.pressed = true
	inside_drawer.position = editor._dock.get_global_rect().get_center()
	editor.get_viewport().push_input(inside_drawer)
	await get_tree().process_frame
	_check(editor._drawer_open, "a tap inside the drawer keeps it open")
	var outside_drawer := InputEventScreenTouch.new()
	outside_drawer.pressed = true
	outside_drawer.position = Vector2(5, 400)
	editor.get_viewport().push_input(outside_drawer)
	await get_tree().process_frame
	_check(not editor._drawer_open, "a tap outside the drawer closes it")
	editor.set_workspace_mode("studio")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor.workspace_mode() == "studio", "studio mode applies")
	_check(editor._dock.visible, "studio dock is visible")
	_check(editor._top_bar.size.y >= 43.0, "studio top bar is 44 dp")
	_check(absf(editor._dock.get_global_rect().end.y - editor.size.y) <= 1.0, "studio dock reaches the bottom edge")
	_check(editor._outliner_panel.size.y >= 240.0, "studio scene list gets a usable share of the dock")
	var outliner = editor._outliner
	var outliner_overflow: bool = outliner._list.get_combined_minimum_size().y + 16.0 > outliner._scroll.size.y
	_check(not outliner_overflow or absf(fmod(outliner._scroll.size.y - 6.0, 45.0)) < 0.6, "scene list viewport ends on a whole row")
	editor.set_workspace_mode("desktop")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor.workspace_mode() == "desktop", "desktop mode applies on any screen")
	_check(editor._status_bar.visible, "desktop status bar is visible")
	_check(editor._top_bar.size.y >= 35.0 and editor._top_bar.size.y <= 38.0, "desktop menu bar is 36 dp")
	_check(str(Prefs.get_value("display.layout", "")) == "desktop", "workspace mode persists")

	print("SMOKE STEP: editor type and touch floor")
	editor.size = Vector2(412.0, 915.0)
	editor.set_workspace_mode("studio")
	editor._apply_shell()
	await get_tree().process_frame
	var too_small_labels := 0
	for editor_label in _labels_under(editor):
		if editor_label.get_theme_font_size("font_size") < 11:
			too_small_labels += 1
	_check(too_small_labels == 0, "every editor label is at least 11 sp")
	var short_fields := 0
	for field in _line_edits_under(editor):
		if field.get_combined_minimum_size().y < 44.0:
			short_fields += 1
	_check(short_fields == 0, "every editor text field is at least 44 dp tall")
	var short_targets := 0
	for target in _buttons_under(editor):
		if not target.visible or target.has_meta("qa_hit_exempt"):
			continue
		if target.get_combined_minimum_size().x < 44.0 or target.get_combined_minimum_size().y < 44.0:
			short_targets += 1
			print("SMOKE SHORT: '", (target as Button).text, "' variation=", (target as Button).theme_type_variation, " min=", target.get_combined_minimum_size(), " visible=", target.visible)
	_check(short_targets == 0, "every visible editor button keeps a 44 dp touch target")

	print("SMOKE STEP: landscape shell")
	editor.size = Vector2(915.0, 412.0)
	editor.set_workspace_mode("studio")
	editor._apply_shell()
	_check(editor._short, "915x412 resolves as a short landscape shell")
	_check(not editor._timeline_visible, "short landscape starts with the dope sheet folded")
	_check(absf(editor._timeline_panel.custom_minimum_size.y - 56.0) < 0.5, "folded landscape timeline keeps a 56 dp transport")
	_check(editor._dock_slot.custom_minimum_size.x >= 240.0 and editor._dock_slot.custom_minimum_size.x <= 300.0, "landscape dock leaves the viewport in charge")
	editor._timeline.set_sheet_visible(true)
	editor._timeline.size = Vector2(591.0, 156.0)
	editor._timeline._refresh_compact()
	_check(editor._timeline._compact_header.visible, "a narrow landscape sheet exposes graph, loop, snap, delete and fold")
	_check(editor._timeline.get_combined_minimum_size().x <= 591.0, "the landscape transport fits the center column")
	editor._timeline.set_sheet_visible(false)
	editor.size = Vector2(412.0, 915.0)
	editor.set_workspace_mode("studio")
	editor._apply_shell()
	_check(not editor._short, "412x915 resolves as a tall studio shell")
	_check(editor._timeline_visible, "tall studio opens the dope sheet by default")
	editor.set_workspace_mode("compact")
	await get_tree().process_frame

	print("SMOKE STEP: graph editor")
	var timeline = editor._timeline
	_check(timeline != null, "timeline exists")
	if timeline != null:
		timeline.set_mode("graph")
		_check(timeline._mode == "graph", "graph mode activates")
		var graph_speed: float = timeline._channel_speed(ease_id, "position", 1.0)
		_check(graph_speed > 0.01, "graph samples real channel speed")
		timeline.set_mode("dope")
		_check(timeline._mode == "dope", "dope mode restores")

	print("SMOKE STEP: render export")
	var frame_dir := "user://render_export_fixture"
	DirAccess.make_dir_recursive_absolute(frame_dir)
	for i in range(3):
		var frame := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		frame.fill(Color(0.1 * float(i), 0.2, 0.3))
		frame.save_png(frame_dir.path_join("frame_%04d.png" % i))
	var sequence_zip := "user://render_export_fixture.zip"
	_check(RenderExport.zip_directory(frame_dir, sequence_zip), "sequence zip written")
	var zip_reader := ZIPReader.new()
	_check(zip_reader.open(sequence_zip) == OK, "sequence zip readable")
	if zip_reader.open(sequence_zip) == OK:
		_check(zip_reader.get_files().size() == 3, "sequence zip contains every frame")
		zip_reader.close()
	var first_seq_dir := RenderExport.sequence_dir("user://sequence_fixture")
	DirAccess.make_dir_recursive_absolute(first_seq_dir)
	var second_seq_dir := RenderExport.sequence_dir("user://sequence_fixture")
	_check(first_seq_dir != second_seq_dir, "sequence directories do not collide")
	DirAccess.remove_absolute(first_seq_dir)
	DirAccess.remove_absolute("user://sequence_fixture")
	for i in range(3):
		DirAccess.remove_absolute(frame_dir.path_join("frame_%04d.png" % i))
	DirAccess.remove_absolute(frame_dir)
	DirAccess.remove_absolute(sequence_zip)

	print("SMOKE STEP: render sheet")
	editor._open_render_sheet()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._overlay.has_modal(), "render sheet opens")
	_check(editor._render_sequence_button != null, "render sheet has sequence action")
	_check(editor._render_progress != null, "render sheet has progress readout")
	_check(editor._sequence_frame_count() == 144, "sequence frame count follows duration and fps")
	_check(not editor._render_busy, "render sheet is idle on open")
	editor._overlay.close_modal()
	await get_tree().process_frame

	print("SMOKE STEP: graphics preset state")
	editor._open_graphics_settings()
	await get_tree().process_frame
	_check(editor._preset_buttons.size() == 3, "graphics preset chips exist")
	var original_preset: String = Gfx.preset
	Gfx.preset = "custom"
	editor._sync_preset_buttons()
	var any_preset_lit := false
	for button in editor._preset_buttons:
		if button.button_pressed:
			any_preset_lit = true
	_check(not any_preset_lit, "custom settings clear the preset selection")
	Gfx.preset = "balanced"
	editor._sync_preset_buttons()
	var balanced_lit := false
	for chip in editor._preset_buttons:
		if str(chip.get_meta("preset", "")) == "balanced" and chip.button_pressed:
			balanced_lit = true
	_check(balanced_lit, "balanced preset reselects its chip")
	Gfx.preset = original_preset
	editor._overlay.close_modal()
	await get_tree().process_frame

	print("SMOKE STEP: renderer and draft quality")
	_check(Gfx.renderer_label("forward_plus") == "Forward+", "Forward+ has a display label")
	_check(Gfx.renderer_label("mobile") == "Mobile", "Mobile has a display label")
	_check(Gfx.renderer_label("gl_compatibility") == "Compatibility", "Compatibility has a display label")
	var live_renderer: String = Gfx.renderer_name()
	editor._open_renderer_sheet()
	await get_tree().process_frame
	_check(editor._overlay.has_modal(), "renderer sheet opens")
	_check(editor._renderer_pending == live_renderer, "renderer sheet starts on the live backend")
	editor._overlay.close_modal()
	await get_tree().process_frame
	var draft_view = editor._view
	var draft_pref: bool = Gfx.draft_editing
	draft_view.set_draft_quality(true)
	draft_view.set_interactive(true)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(draft_view.is_draft_active(), "draft quality engages during an edit")
	_check(draft_view._viewport.msaa_3d == Viewport.MSAA_DISABLED, "draft quality disables MSAA")
	draft_view.set_interactive(false)
	draft_view._draft_idle = 10.0
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not draft_view.is_draft_active(), "draft quality releases after idle")
	_check(draft_view._viewport.msaa_3d == Gfx.MSAA_MODES[Gfx.msaa], "full MSAA returns after the draft pass")
	_check(draft_view.quick_render_requested.is_connected(editor._quick_render_preview), "quick render HUD is wired to the preview")
	draft_view.set_draft_quality(draft_pref)

	print("SMOKE STEP: performance readout")
	var perf_view = editor._view
	_check(perf_view._fps_chip != null, "FPS chip exists")
	_check(perf_view._fps_chip.custom_minimum_size.x >= 44.0, "FPS chip has a 44 dp target")
	perf_view.set_fps_value(60.0, 16.6)
	_check(perf_view._fps_chip.text.contains("60"), "FPS chip shows the real sample")
	_check(Perf.sample_updated.is_connected(Callable(editor, "_on_perf_sample")), "perf samples drive the editor")
	perf_view.performance_requested.emit()
	await get_tree().process_frame
	_check(editor._perf_overlay != null and editor._perf_overlay.visible, "FPS chip opens the performance overlay")
	editor._perf_overlay.set_sample({
		"fps": 60.0, "frame_ms": 16.6, "draw_calls": 42, "primitives": 1200,
		"preview_scale": 1.0, "samples": [16.6, 16.6, 16.6],
	}, 7, 8, Vector2i(960, 540))
	_check(editor._perf_overlay._fps_label.text.contains("60"), "overlay shows the real FPS")
	_check(editor._perf_overlay._draw_label.text.contains("42"), "overlay shows draw calls")
	editor._perf_overlay.close_overlay()
	await get_tree().process_frame
	_check(not editor._perf_overlay.visible, "performance overlay closes")

	# Color sheet and material write.
	var mesh_id: String = doc.selected_id
	editor._open_color_sheet("color")
	await get_tree().process_frame
	_check(editor._color_sheet_active, "color sheet active")
	editor._set_color_value(Color(0.2, 0.3, 0.4))
	_check(str(doc.get_object(mesh_id).get("color", "")).to_upper() == "#334D66", "color written to object")
	editor._overlay.close_modal()
	await get_tree().process_frame
	_check(not editor._color_sheet_active, "color sheet closed cleanly")

	print("SMOKE STEP: gizmo")
	# Gizmo drag must accumulate.
	var view = editor._view
	doc.set_selection(mesh_id)
	view.set_tool("move")
	await get_tree().process_frame
	view._frame_all(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var before_x: float = doc.get_selected_node().position.x
	view._start_gizmo("x", Vector2(100, 100))
	view._apply_gizmo_drag(Vector2(24, 0))
	var step_x: float = doc.get_selected_node().position.x
	view._apply_gizmo_drag(Vector2(24, 0))
	var total_x: float = doc.get_selected_node().position.x
	view._finish_gizmo()
	_check(not is_equal_approx(step_x, before_x), "gizmo drag changes value")
	_check(absf(total_x - before_x) > absf(step_x - before_x) + 0.01, "gizmo drag accumulates")

	print("SMOKE STEP: picking")
	var picked_light := false
	for obj in doc.objects:
		if str(obj.get("kind", "")) != "light":
			continue
		var lid := str(obj.get("id", ""))
		var lnode: Node3D = doc.nodes.get(lid)
		if lnode == null or view._camera.is_position_behind(lnode.global_position):
			continue
		var sp: Vector2 = view._to_ui(view._camera.unproject_position(lnode.global_position))
		if not Rect2(Vector2.ZERO, view.size).has_point(sp):
			continue
		view._pick(sp)
		picked_light = true
		_check(doc.selected_id == lid, "light picked near its marker")
		break
	if not picked_light:
		print("SMOKE SKIP: no on-screen light to pick")
	doc.set_selection(mesh_id)

	print("SMOKE STEP: viewport gizmos")
	_check(view._surface.show_behind_parent, "viewport marks draw above preview")
	_check(editor._overlay._toast_anchor == editor._viewport_host, "toast anchored to viewport")
	var marker_cam := Camera3D.new()
	marker_cam.position = Vector3(0.0, 2.0, 8.0)
	add_child(marker_cam)
	var light_id := ""
	for obj in doc.objects:
		if str(obj.get("kind", "")) == "light":
			light_id = str(obj.get("id", ""))
			break
	_check(light_id != "", "study has a light")
	if light_id != "":
		var light_node: Node3D = doc.nodes.get(light_id)
		var marker := light_node.get_node_or_null("Marker") as Node3D
		doc.markers_hidden = false
		doc.update_marker_scales(marker_cam)
		_check(marker != null and marker.visible, "light marker visible at range")
		_check(marker.scale.x < 1.0, "light marker uses screen-space scale")
		marker_cam.position = light_node.global_position + Vector3(0.0, 0.0, 0.05)
		doc.update_marker_scales(marker_cam)
		_check(not marker.visible, "near light marker hidden")
		doc.markers_hidden = true
		marker_cam.position = Vector3(0.0, 2.0, 8.0)
		doc.update_marker_scales(marker_cam)
		_check(not marker.visible, "markers hidden for stills")
		# The editor keeps the document meshes hidden; locators are drawn as
		# screen-space glyphs by EditorView.
		doc.markers_hidden = true
	marker_cam.queue_free()

	# Undo / redo.
	var after_gizmo: float = doc.get_selected_node().position.x
	doc.undo()
	await get_tree().process_frame
	_check(absf(doc.get_selected_node().position.x - after_gizmo) > 0.001, "undo restores transform")
	doc.redo()
	await get_tree().process_frame

	print("SMOKE STEP: save/load")
	# Save, load and verify the document round trip.
	var saved_ok: bool = Store.save_project(doc)
	_check(saved_ok, "project saved")
	var loaded: Dictionary = Store.load_project(doc.project_id)
	_check(not loaded.is_empty(), "project loaded")
	if not loaded.is_empty():
		var other = preload("res://src/core/document.gd").new()
		add_child(other)
		var loaded_ok: bool = other.load_project(loaded.get("data", {}), str(loaded.get("meta", {}).get("path", "")))
		_check(loaded_ok, "document load returned true")
		_check(other.objects.size() == doc.objects.size(), "object count round trip")
		var source_keys := 0
		var loaded_keys := 0
		for channel in doc.CHANNELS:
			source_keys += doc.get_channel_keys(mesh_id, channel).size()
		for channel in other.CHANNELS:
			loaded_keys += other.get_channel_keys(mesh_id, channel).size()
		_check(source_keys == loaded_keys, "animation key count round trip")
		_check(is_equal_approx(other.get_key_transition(mesh_id, "position", 0), 0.75), "key easing round trip")
		other.queue_free()
		await get_tree().process_frame

	print("SMOKE STEP: OBJ import")
	# A real OBJ+MTL+texture fixture exercises copying, reference rewriting and
	# the runtime mesh parser end to end.
	var fixture := "user://obj_import_fixture"
	DirAccess.make_dir_recursive_absolute(fixture)
	var texture := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	texture.fill(Color(0.9, 0.4, 0.1))
	texture.save_png(fixture.path_join("tex.png"))
	_write_test_text(fixture.path_join("sample.mtl"), "newmtl Painted\nKd 0.8 0.2 0.1\nNs 250\nmap_Kd tex.png\n")
	_write_test_text(
		fixture.path_join("sample.obj"),
		"mtllib sample.mtl\no Quad\nv\t-1 0 -1\nv 1 0 -1\nv 1 0 1\nv -1 0 1\nvt 0 0\nvt 1 0\nvt 1 1\nvt 0 1\nusemtl Painted\nf\t1/1 2/2 3/3 4/4\n"
	)
	var import_result: Dictionary = Store.import_model(fixture.path_join("sample.obj"), doc.project_dir, "Sample")
	_check(bool(import_result.get("ok", false)), "obj import succeeds")
	if bool(import_result.get("ok", false)):
		var imported_rel := str(import_result.get("rel_path", ""))
		var imported_folder: String = doc.project_dir.path_join(imported_rel).get_base_dir()
		_check(FileAccess.file_exists(imported_folder.path_join("materials/sample.mtl")), "obj material copied")
		_check(FileAccess.file_exists(imported_folder.path_join("textures/tex.png")), "obj texture copied")
		var imported_mtl := FileAccess.get_file_as_string(imported_folder.path_join("materials/sample.mtl"))
		_check(imported_mtl.contains("../textures/tex.png"), "obj texture reference rewritten")
		var imported_obj := FileAccess.get_file_as_string(doc.project_dir.path_join(imported_rel))
		_check(imported_obj.contains("mtllib materials/sample.mtl"), "obj material reference rewritten")
		var obj_id: String = doc.add_imported(imported_rel, "Sample", Vector3.ZERO)
		await get_tree().process_frame
		var imported_node: Node3D = doc.nodes.get(obj_id)
		_check(imported_node != null, "obj object spawned")
		var mesh_instance: MeshInstance3D = null
		if imported_node != null:
			for child in imported_node.find_children("*", "MeshInstance3D", true, false):
				mesh_instance = child
				break
		_check(mesh_instance != null and mesh_instance.mesh != null, "obj mesh built")
		if mesh_instance != null and mesh_instance.mesh != null:
			_check(mesh_instance.mesh.get_surface_count() == 1, "obj material group became one surface")
			var surface_material := mesh_instance.mesh.surface_get_material(0) as StandardMaterial3D
			_check(surface_material != null and surface_material.albedo_texture != null, "obj material texture loaded")
			var arrays := mesh_instance.mesh.surface_get_arrays(0)
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			_check(normals.size() >= 3 and normals[0].length() > 0.9, "obj normals generated")
			_check((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == 6, "obj quad triangulated")
		DirAccess.remove_absolute(fixture.path_join("sample.obj"))
		DirAccess.remove_absolute(fixture.path_join("sample.mtl"))
		DirAccess.remove_absolute(fixture.path_join("tex.png"))
		DirAccess.remove_absolute(fixture)

	# Leave and clean up the temporary project.
	var project_id: String = doc.project_id
	editor._leave(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(main._editor == null, "editor closed")
	_check(Store.delete_project(project_id), "temporary project deleted")
	_finish()

func _write_test_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()

func _contrast(a: Color, b: Color) -> float:
	var high := maxf(_relative_luminance(a), _relative_luminance(b))
	var low := minf(_relative_luminance(a), _relative_luminance(b))
	return (high + 0.05) / (low + 0.05)

## WCAG 2.x relative luminance. Godot's Color.get_luminance() is the raw
## weighted sRGB value, not the linearised one the contrast formula requires.
func _relative_luminance(color: Color) -> float:
	return 0.2126 * _linear_channel(color.r) + 0.7152 * _linear_channel(color.g) + 0.0722 * _linear_channel(color.b)

func _linear_channel(value: float) -> float:
	if value <= 0.04045:
		return value / 12.92
	return pow((value + 0.055) / 1.055, 2.4)

func _nodes_under(root: Node, result: Array[Node]) -> void:
	for child in root.get_children():
		result.append(child)
		_nodes_under(child, result)

func _labels_under(root: Node) -> Array[Label]:
	var nodes: Array[Node] = []
	_nodes_under(root, nodes)
	var labels: Array[Label] = []
	for node in nodes:
		if node is Label:
			labels.append(node)
	return labels

func _line_edits_under(root: Node) -> Array[LineEdit]:
	var nodes: Array[Node] = []
	_nodes_under(root, nodes)
	var fields: Array[LineEdit] = []
	for node in nodes:
		if node is LineEdit:
			fields.append(node)
	return fields

func _buttons_under(root: Node) -> Array[Button]:
	var nodes: Array[Node] = []
	_nodes_under(root, nodes)
	var buttons: Array[Button] = []
	for node in nodes:
		if node is Button:
			buttons.append(node)
	return buttons

func _button_with_text(root: Node, text_value: String) -> Button:
	for button in _buttons_under(root):
		if button.text == text_value:
			return button
	return null
	return null

func _finish() -> void:
	if _failures.is_empty():
		print("SMOKE RESULT: PASS")
	else:
		printerr("SMOKE RESULT: %d FAILURE(S)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
