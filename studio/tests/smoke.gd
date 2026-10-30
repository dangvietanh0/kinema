extends Control
## Temporary headless smoke test. Not part of the app.

const RenderExport = preload("res://src/core/render_export.gd")
const DocumentScript = preload("res://src/core/document.gd")

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
	_check(Kit.BG.to_html(false).to_upper() == "000000", "BG token is exact")
	_check(Kit.FOCUS.to_html(false).to_upper() == "EDEDED", "FOCUS token is exact")
	_check(Kit.TIME.to_html(false).to_upper() == "B8B8B8", "TIME token is exact")
	_check(Kit.SURFACE_ACTIVE.to_html(false).to_upper() == "333333", "SURFACE_ACTIVE token is exact")
	_check(Kit.R_PANEL == 0 and Kit.R_CONTROL == 2 and Kit.R_FLOAT == 4, "corner radii are exact")
	for tone in [Kit.FOCUS, Kit.TIME, Kit.WARNING, Kit.SUCCESS]:
		_check(is_equal_approx(tone.r, tone.g) and is_equal_approx(tone.g, tone.b), "chrome accents stay monochrome")
	_check(Kit.TEXT.get_luminance() > Kit.BG.get_luminance() + 0.5, "primary text is high contrast")
	_check(Kit.BORDER.get_luminance() > Kit.SURFACE.get_luminance(), "hairlines are lighter than their surface")
	var sharp := Kit.flat_style(Kit.SURFACE)
	_check(sharp.corner_radius_top_left == 0 and sharp.corner_radius_bottom_right == 0, "panels and inputs are square")
	_check(Kit.icon_button("play", "Play").custom_minimum_size == Vector2(44, 44), "icon buttons have a 44 dp hit target")
	var done_probe := Kit.text_button("Done", "", true)
	_check(done_probe.custom_minimum_size.x >= 96.0, "primary actions are landscape rectangles")
	_check(done_probe.custom_minimum_size.y == 44.0, "primary actions use a 44 dp target height")
	_check(done_probe.custom_minimum_size.x > done_probe.custom_minimum_size.y, "primary actions are wider than tall")
	_check(Kit._active_edge_style(Kit.FOCUS_DARK, "left").border_width_left == 1, "active left edge is 1 px")
	_check(Kit._active_edge_style(Kit.FOCUS_DARK, "bottom").border_width_bottom == 1, "active bottom edge is 1 px")
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
			_check(new_project.get_combined_minimum_size().y >= 44.0, "the browser primary action has a 44 dp target")
			_check(absf(new_project.size.y - 44.0) < 0.5, "the browser New project action is exactly 44 dp tall")
		home._open_new_project_sheet()
		for _i in 4:
			await get_tree().process_frame
		var home_fields := _line_edits_under(home._overlay)
		_check(not home_fields.is_empty(), "the new project sheet has a name field")
		for entry in home_fields:
			_check(entry.get_combined_minimum_size().y >= 44.0, "the new project name field is at least 44 dp tall")
		var cancel_action := _button_with_text(home._overlay, "Cancel")
		var create_action := _button_with_text(home._overlay, "Create project")
		_check(cancel_action != null, "the new project sheet exposes a secondary action")
		if cancel_action != null:
			_check(cancel_action.size.x >= 80.0, "secondary footer actions keep an 80 dp landscape width")
			_check(absf(cancel_action.size.y - 44.0) < 0.5, "secondary footer actions are exactly 44 dp tall")
		_check(create_action != null, "the new project sheet exposes its primary action")
		if create_action != null:
			_check(create_action.size.x >= 96.0, "the primary footer action keeps a 96 dp landscape width")
			_check(absf(create_action.size.y - 44.0) < 0.5, "the primary footer action is exactly 44 dp tall")
		home._overlay.close_modal()
		await get_tree().process_frame
		home._show_about()
		await get_tree().process_frame
		await get_tree().process_frame
		var home_about := ""
		for label in _labels_under(home._overlay):
			home_about += label.text + "\n"
		_check(not home_about.contains("Geist"), "Home About names the real UI font")
		_check(home_about.contains("IBM Plex Sans") and home_about.contains("IBM Plex Mono"), "Home About names IBM Plex Sans and Mono")
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

	print("SMOKE STEP: expansion contract")
	for signal_name in [
		"clips_changed", "active_clip_changed", "media_changed", "rigs_changed",
		"rig_selection_changed", "imported_scene_ready", "object_spawned",
	]:
		_check(doc.has_signal(signal_name), "document exposes signal: %s" % signal_name)
	_check(doc.animation_system != null, "animation subsystem exists")
	_check(doc.media_system != null, "media subsystem exists")
	_check(doc.rig_system != null, "rig subsystem exists")
	if doc.animation_system != null:
		_check(doc.animation_system._document == doc, "animation subsystem is owned by the document")
	if doc.media_system != null:
		_check(doc.media_system._document == doc, "media subsystem is owned by the document")
	if doc.rig_system != null:
		_check(doc.rig_system._document == doc, "rig subsystem is owned by the document")
	var contract_data: Dictionary = doc.to_data()
	_check(int(contract_data.get("format", 0)) == 2, "documents serialize as format 2")
	for key in ["clips", "layers", "rigs", "media"]:
		_check(contract_data.has(key), "format 2 carries %s" % key)
	_check(is_equal_approx(doc.sequence_duration(), doc.duration), "sequence duration falls back to the active clip")
	_check(is_equal_approx(doc.sequence_time(), doc.current_time), "sequence time falls back to the clip time")
	_check(not doc.is_sequence_playing(), "sequence is stopped by default")
	_check(doc.has_method("set_active_clip") and doc.has_method("active_clip_id"), "document exposes active-clip transport")
	_check(doc.has_method("insert_bone_key") and doc.has_method("get_bone_keys"), "document exposes bone-key helpers")
	_check(editor._view.has_method("capture_with_camera"), "editor view exposes capture_with_camera")
	_check(editor._view.has_method("world_to_screen"), "editor view exposes world_to_screen")
	_check(editor._view.has_method("screen_ray"), "editor view exposes screen_ray")
	var probe_doc = DocumentScript.new()
	add_child(probe_doc)
	var spawn_count := [0]
	var import_count := [0]
	probe_doc.object_spawned.connect(func(_id: String, _node: Node) -> void: spawn_count[0] += 1)
	probe_doc.imported_scene_ready.connect(func(_id: String, _node: Node) -> void: import_count[0] += 1)
	var v1_data := {
		"format": 1,
		"title": "V1 Contract",
		"fps": 24,
		"duration": 2.0,
		"loop": true,
		"objects": [{
			"id": "1", "name": "Cube", "kind": "mesh", "primitive": "cube",
			"position": [0, 0, 0], "rotation": [0, 0, 0, 1], "scale": [1, 1, 1],
			"visible": true,
		}],
		"animation": {
			"name": "Take 01", "length": 2.0, "loop": true,
			"tracks": [{
				"path": "Object_1:position", "type": Animation.TYPE_POSITION_3D,
				"interpolation": Animation.INTERPOLATION_LINEAR,
				"keys": [{"t": 0.0, "v": [0, 0, 0], "e": 1.0}, {"t": 2.0, "v": [2, 0, 0], "e": 1.0}],
			}],
		},
	}
	_check(probe_doc.load_project(v1_data), "a v1 project loads through the contract")
	_check(is_equal_approx(probe_doc.duration, 2.0), "v1 duration survives")
	_check(probe_doc.loop, "v1 loop survives")
	_check(probe_doc.objects.size() == 1, "v1 object survives")
	_check(probe_doc.animation != null and probe_doc.animation.get_track_count() == 1, "v1 track survives")
	_check(spawn_count[0] == 1, "object_spawned fires once while loading")
	_check(import_count[0] == 0, "loading a project does not re-import scenes")
	var bone_key := probe_doc.insert_bone_key("1", "Root", Quaternion(Vector3.UP, 0.5))
	_check(bone_key >= 0, "bone keys can be inserted")
	var bone_keys: Array = probe_doc.get_bone_keys("1", "Root")
	_check(bone_keys.size() == 1, "bone keys roundtrip")
	if bone_keys.size() == 1:
		var stored: Quaternion = bone_keys[0]["value"]
		_check(stored.is_equal_approx(Quaternion(Vector3.UP, 0.5)), "bone key value survives")
	probe_doc.delete_bone_key("1", "Root", 0)
	_check(probe_doc.get_bone_keys("1", "Root").is_empty(), "bone keys can be deleted")
	probe_doc.queue_free()

	# Project timing lives in Project settings; the device Settings screen is a
	# separate surface with eight categories.
	editor._open_project_settings()
	await get_tree().process_frame
	_check(editor._settings_duration_field != null, "project settings duration field built")
	_check(editor._settings_fps_field != null, "project settings fps field built")
	if editor._settings_duration_field != null:
		_check(is_equal_approx(editor._settings_duration_field.value, doc.duration), "project settings field reads duration")
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
	_check(not editor._timeline._fold_button.visible, "compact folds from the action bar, not the transport")
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
	# The window is still a portrait phone here, where Studio now uses an
	# overlay dock. Prove the side-by-side dock on a wide workbench.
	editor.size = Vector2(1280.0, 800.0)
	editor._apply_shell()
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

	print("SMOKE STEP: action geometry and chrome")
	_check(editor._outliner._row_style(true).border_width_left == 1, "selected outliner row uses a 1 px edge")
	_check(editor._timeline.get("CHANNEL_EDGE") == 1.0, "selected timeline channel uses a 1 px edge")
	_check(editor._view.get("_status_label") == null, "viewport HUD has no selection info strip")
	editor._open_settings("general")
	await get_tree().process_frame
	await get_tree().process_frame
	var done_button := _button_with_text(editor._overlay, "Done")
	_check(done_button != null, "sheet footer exposes Done")
	if done_button != null:
		_check(done_button.size.x >= 96.0, "Done keeps a 96 dp landscape width")
		_check(absf(done_button.size.y - 44.0) < 0.5, "Done is exactly 44 dp tall")
		_check(done_button.size.x > done_button.size.y, "Done renders as a landscape action")
	editor._overlay.close_modal()
	await get_tree().process_frame
	editor._show_about()
	await get_tree().process_frame
	await get_tree().process_frame
	var about_text := ""
	for label in _labels_under(editor._overlay):
		about_text += label.text + "\n"
	_check(not about_text.contains("Geist"), "About names the real UI font")
	_check(about_text.contains("IBM Plex"), "About names IBM Plex")
	editor._overlay.close_modal()
	await get_tree().process_frame

	print("SMOKE STEP: landscape shell")
	editor.size = Vector2(915.0, 412.0)
	editor.set_workspace_mode("studio")
	editor._apply_shell()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._short, "915x412 resolves as a short landscape shell")
	_check(not editor._timeline_visible, "short landscape starts with the dope sheet folded")
	var folded_stack := 56.0
	if editor.get("_clip_lane") != null and editor.get("_media_lanes") != null:
		var lane_min: float = editor.get("_clip_lane").get_combined_minimum_size().y
		var media_min: float = editor.get("_media_lanes").get_combined_minimum_size().y
		folded_stack = 56.0 + lane_min + media_min
	_check(absf(editor._timeline_panel.custom_minimum_size.y - folded_stack) < 0.5, "folded landscape timeline keeps transport, clip lane and media lanes")
	_check(editor._dock_slot.custom_minimum_size.x >= 240.0 and editor._dock_slot.custom_minimum_size.x <= 300.0, "landscape dock leaves the viewport in charge")
	editor._timeline.set_sheet_visible(true)
	await get_tree().process_frame
	editor._timeline._refresh_compact()
	_check(editor._timeline._compact_header.visible, "a narrow landscape sheet exposes graph, loop, snap, delete and fold")
	_check(editor._timeline.get_combined_minimum_size().x <= 591.0, "the landscape transport fits the center column")
	editor._timeline.set_sheet_visible(false)
	editor.size = Vector2(412.0, 915.0)
	editor.set_workspace_mode("studio")
	editor._apply_shell()
	_check(not editor._short, "412x915 resolves as a tall studio shell")
	_check(editor._timeline_visible, "tall studio opens the dope sheet by default")

	print("SMOKE STEP: narrow studio drawer")
	editor._apply_shell()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not editor._dock_slot.visible, "narrow studio gives the viewport the full width")
	_check(not editor._dock.visible, "narrow studio dock starts closed")
	_check(editor._top_bar._panels_button.visible, "narrow studio exposes a panel toggle")
	_check(editor._view.size.x >= 340.0, "narrow studio viewport keeps a usable width")
	var view_rect: Rect2 = editor._view.get_global_rect()
	var hud_rect: Rect2 = editor._view._quick_render_button.get_global_rect()
	_check(view_rect.encloses(hud_rect), "narrow studio HUD stays inside the viewport")
	editor._toggle_drawer("scene")
	for _i in 4:
		await get_tree().process_frame
	_check(editor._drawer_open and editor._dock.visible, "narrow studio drawer opens")
	_check(editor._drawer_scrim.visible, "narrow studio drawer has a scrim")
	_check(editor._dock_close_button.visible, "narrow studio drawer can be dismissed")
	editor._close_drawer()
	await get_tree().process_frame
	_check(not editor._dock.visible and not editor._dock_slot.visible, "closing the drawer returns the full width")
	editor.set_workspace_mode("compact")
	await get_tree().process_frame
	_check(not editor._top_bar._panels_button.visible, "compact uses the bottom bar for panels")
	await get_tree().process_frame

	print("SMOKE STEP: timeline fold control")
	editor._timeline_visible = true
	editor._sync_timeline_visibility()
	_check(editor._timeline._fold_button != null, "timeline exposes a fold control")
	if editor._timeline._fold_button != null:
		_check(editor._timeline._fold_button.custom_minimum_size.y >= 44.0, "timeline fold control keeps a 44 dp target")
	editor._on_timeline_close_requested()
	await get_tree().process_frame
	_check(not editor._timeline_visible, "timeline fold control folds the sheet")
	editor._on_timeline_close_requested()
	await get_tree().process_frame
	_check(editor._timeline_visible, "timeline fold control reopens the sheet")
	editor._timeline_visible = false
	editor._sync_timeline_visibility()

	print("SMOKE STEP: sequence shell wiring")
	editor.size = Vector2(412.0, 915.0)
	editor.set_workspace_mode("studio")
	editor._apply_shell()
	# A mode switch reopens the default sheet; this step is about the folded
	# stack, so fold explicitly first.
	editor._timeline_visible = false
	editor._sync_timeline_visibility()
	await get_tree().process_frame
	await get_tree().process_frame
	var lane = editor.get("_clip_lane")
	_check(lane != null, "the clip lane mounts above the dope sheet")
	var media_lanes = editor.get("_media_lanes")
	_check(media_lanes != null, "media lanes mount below the dope sheet")
	var stack = editor.get("_timeline_stack")
	_check(stack != null, "the timeline panel stacks clip lane, dope sheet and media lanes")
	if lane != null and media_lanes != null and stack != null:
		var stack_kids: Array = stack.get_children()
		_check(stack_kids.has(lane) and stack_kids.has(editor._timeline) and stack_kids.has(media_lanes),
			"clip lane, dope sheet and media lanes share one stack")
		var lane_at: int = stack_kids.find(lane)
		var sheet_at: int = stack_kids.find(editor._timeline)
		var media_at: int = stack_kids.find(media_lanes)
		_check(lane_at < sheet_at and sheet_at < media_at, "clip lane sits above the sheet and media lanes below it")
		_check(lane.doc == doc, "the clip lane reads the adopted document")
		_check(media_lanes._doc == doc, "media lanes read the adopted document")
	if lane != null:
		_check(lane.get_combined_minimum_size().y >= 44.0, "the clip lane keeps a real row height")
	if media_lanes != null:
		_check(media_lanes.is_collapsed(), "media lanes start collapsed")
		_check(absf(media_lanes.get_combined_minimum_size().y - 44.0) < 0.5, "collapsed media lanes cost a 44 dp header")
		if lane != null:
			var folded_total: float = 56.0 + lane.get_combined_minimum_size().y + media_lanes.get_combined_minimum_size().y
			_check(absf(editor._timeline_panel.custom_minimum_size.y - folded_total) < 0.5,
				"the folded sheet keeps transport, clip lane and collapsed media lanes")
		# Collapsing is a layout concern only: the panel must reserve the real
		# height as the body opens, and give it back when the lanes fold.
		editor._timeline_visible = true
		editor._sync_timeline_visibility()
		await get_tree().process_frame
		var folded_panel: float = editor._timeline_panel.custom_minimum_size.y
		media_lanes.set_collapsed(false)
		await get_tree().process_frame
		_check(not media_lanes.is_collapsed(), "media lanes expand on request")
		_check(editor._timeline_panel.custom_minimum_size.y > folded_panel,
			"expanding media lanes grows the timeline panel")
		media_lanes.set_collapsed(true)
		await get_tree().process_frame
		_check(absf(editor._timeline_panel.custom_minimum_size.y - folded_panel) < 0.5,
			"collapsing media lanes restores the timeline height")
		editor._timeline_visible = false
		editor._sync_timeline_visibility()

	var tl_play: Button = editor._timeline._play_button
	_check(tl_play != null, "the dope sheet keeps a clip transport")
	if lane == null or tl_play == null:
		_check(false, "the clip lane runs the sequence clock and the timeline runs the clip clock")
		_check(false, "stopping the sequence restores the saved clip time")
	if lane != null and tl_play != null:
		doc.seek(1.0)
		var lane_play: Button = lane.play_sequence_button()
		_check(lane_play != null and lane_play.custom_minimum_size.y >= 44.0, "the clip lane keeps a 44 dp transport")
		lane_play.pressed.emit()
		_check(doc.is_sequence_playing(), "the clip lane button plays the sequence clock")
		_check(not doc.is_playing, "the sequence does not run both clocks")
		_check(tl_play.disabled, "timeline clip transport is disabled while the sequence plays")
		_check(editor._timeline._time_label.text == doc.format_timecode(doc.current_time),
			"the timeline shows the active strip's local time while the sequence runs")
		lane_play.pressed.emit()
		_check(not doc.is_sequence_playing(), "the clip lane button pauses the sequence clock")
		_check(is_equal_approx(doc.current_time, 1.0), "stopping the sequence restores the saved clip time")
		# Space is the other transport: pausing the sequence with it must also
		# put the clip clock back where the sequence took over.
		doc.seek(1.0)
		lane_play.pressed.emit()
		_check(doc.is_sequence_playing(), "the sequence restarts from the lane button")
		var space := InputEventKey.new()
		space.keycode = KEY_SPACE
		space.pressed = true
		editor._unhandled_key_input(space)
		_check(not doc.is_sequence_playing(), "space pauses the sequence clock")
		_check(is_equal_approx(doc.current_time, 1.0), "space restores the saved clip time")
		tl_play.pressed.emit()
		_check(doc.is_playing and not doc.is_sequence_playing(), "the timeline transport plays the clip clock")
		_check(not tl_play.disabled, "timeline clip transport re-enables when the sequence stops")
		doc.pause()
		doc.seek(0.0)
		await get_tree().process_frame

	var rig_panel = editor.get("_rig_panel")
	_check(rig_panel != null, "a rig panel is docked next to scene and properties")
	_check(editor.get("_drawer_rig_tab") != null, "the drawer exposes a rig tab")
	var rig_overlay = editor.get("_rig_overlay")
	_check(rig_overlay != null, "a rig overlay floats over the viewport")
	if rig_panel == null or editor.get("_drawer_rig_tab") == null:
		_check(false, "the rig tab shows an honest empty state")
		_check(false, "the rig overlay follows the active rig tab")
		_check(false, "the drawer exposes a visible rig tab")
	if rig_panel != null and editor._drawer_rig_tab != null:
		_check(editor._drawer_rig_tab.visible, "the rig tab is visible on tabbed shells")
		_check(editor.get("_rig_panel") != null and editor.get("_rig_panel").visible, "the rig tab keeps the panel reachable")
		if rig_overlay != null:
			# Rig mode follows the active dock page: on the Rig tab the overlay
			# engages; hiding that page or switching tabs disengages it.
			editor._set_compact_tab("rig")
			if editor._dock_overlay_mode():
				editor._open_drawer()
			await get_tree().process_frame
			_check(rig_overlay.is_enabled(), "the rig overlay follows the active rig tab")
			if editor._dock_overlay_mode():
				editor._close_drawer()
				await get_tree().process_frame
				_check(not rig_overlay.is_enabled(), "the rig overlay yields when its page is dismissed")
			editor._set_compact_tab("scene")
			await get_tree().process_frame
			_check(not rig_overlay.is_enabled(), "the rig overlay yields when another tab is active")
		_check(rig_panel.empty_state_visible(), "the rig tab shows an honest empty state")
		var rig_id := ""
		rig_id = doc.rig_system.create_rig("Smoke Rig", Vector3.ZERO)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(rig_id != "" and not rig_panel.empty_state_visible(), "creating a rig clears the empty state")
		if rig_overlay != null and rig_id != "":
			_check(str(rig_overlay._rig_id) == doc.rig_system.active_rig_id(), "the rig overlay tracks the active rig")
		doc.rig_system.delete_rig(rig_id)
		await get_tree().process_frame
		_check(rig_panel.empty_state_visible(), "deleting the rig restores the empty state")
		if rig_overlay != null:
			_check(str(rig_overlay._rig_id) == "", "the rig overlay clears with the last rig")
		editor._set_compact_tab("scene")
		await get_tree().process_frame

	var video_overlay = editor.get("_video_overlay")
	_check(video_overlay != null, "a video reference overlay sits behind the HUD")
	if video_overlay != null:
		_check(video_overlay.get_parent() == editor._view, "the video overlay lives on the viewport")
		var view_kids: Array = editor._view.get_children()
		_check(view_kids[view_kids.size() - 1] == editor._view._hud_root, "the HUD stays the top viewport layer")
		_check(view_kids.find(video_overlay) < view_kids.find(editor._view._hud_root), "the video overlay draws below the HUD")
		_check(view_kids.find(video_overlay) > view_kids.find(editor._view._surface), "the video overlay draws over the 3D surface")
		_check(video_overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the video overlay ignores every pointer")
		_check(not video_overlay.visible, "the video overlay hides without a visible reference")
		# Clip mode reads the active strip's start; the sequence clock is used
		# only while a sequence actually runs.
		var anim_sys = doc.animation_system
		var base_layers: Array = anim_sys.layers()
		if not base_layers.is_empty() and not (base_layers[0]["strips"] as Array).is_empty():
			var base_layer: Dictionary = base_layers[0]
			var strip_id := str(base_layer["strips"][0]["id"])
			anim_sys.set_active_layer(str(base_layer["id"]))
			anim_sys.update_strip(strip_id, {"start": 3.0})
			doc.seek(0.5)
			_check(is_equal_approx(video_overlay._overlay_time(), 3.5),
				"clip mode previews the active strip's sequence time")
			anim_sys.update_strip(strip_id, {"start": 0.0})
			doc.seek(0.0)

	# The viewport header is the view's control surface: Perspective, Add,
	# Grid and Frame must reach the real view, not a duplicate control.
	var header = editor.get("_view_header")
	_check(header != null, "the viewport header is mounted")
	if header != null:
		_check(header.grid_button() != null and header.frame_button() != null,
			"the viewport header exposes grid and frame actions")
		var prior_view: String = editor._view.view_preset()
		header.view_requested.emit("Front")
		_check(editor._view.view_preset() == "Front", "the header perspective menu drives the view")
		header.view_requested.emit(prior_view)
		var prior_grid: bool = editor._view.grid_enabled()
		header.grid_toggled.emit(not prior_grid)
		_check(editor._view.grid_enabled() == (not prior_grid), "the header grid action drives the view")
		header.grid_toggled.emit(prior_grid)
		header.add_requested.emit()
		await get_tree().process_frame
		_check(editor._overlay.has_modal(), "the header Add action opens the add sheet")
		editor._overlay.close_modal()
		await get_tree().process_frame
		# Frame selection is a no-op without a selection, but must be wired.
		header.frame_requested.emit()

	if editor._drawer_open:
		editor._close_drawer()
	editor._enter_render_mode()
	_check(editor._render_mode, "render preview engages")
	if video_overlay != null:
		_check(not video_overlay.visible, "render mode hides the video overlay")
	if rig_overlay != null:
		_check(not rig_overlay.is_enabled(), "render mode disables the rig overlay")
	editor._exit_render_mode()
	if video_overlay != null:
		_check(editor._render_mode == false, "render mode exits cleanly")
	doc.pause()
	doc.seek(0.0)

	editor._open_add_sheet()
	await get_tree().process_frame
	var add_texts := {}
	for button in _buttons_under(editor._overlay):
		add_texts[button.text] = true
	_check(add_texts.has("Rig"), "the Add sheet offers a rig")
	_check(add_texts.has("Audio"), "the Add sheet offers an audio track")
	_check(add_texts.has("Video reference"), "the Add sheet offers a video reference")
	editor._overlay.close_modal()
	await get_tree().process_frame

	var media_export = editor.get("_media_export")
	editor._open_render_sheet()
	await get_tree().process_frame
	media_export = editor.get("_media_export")
	_check(editor._overlay.has_modal(), "the render sheet opens")
	_check(media_export != null, "the render sheet embeds the media export sheet")
	_check(editor._render_sequence_button != null, "the render sheet keeps the PNG sequence action")
	_check(editor._render_still_button != null, "the render sheet keeps the quick still action")
	editor._overlay.close_modal()
	await get_tree().process_frame

	# The following step expects the sheet left folded by the fold contract.
	editor._timeline_visible = false
	editor._sync_timeline_visibility()

	print("SMOKE STEP: graph fold contract")
	editor._timeline.set_mode("graph")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not editor._timeline_visible, "graph mode does not reopen a folded sheet")
	var folded_graph := 56.0
	if editor.get("_clip_lane") != null and editor.get("_media_lanes") != null:
		var lane_min_graph: float = editor.get("_clip_lane").get_combined_minimum_size().y
		var media_min_graph: float = editor.get("_media_lanes").get_combined_minimum_size().y
		folded_graph = 56.0 + lane_min_graph + media_min_graph
	_check(absf(editor._timeline_panel.custom_minimum_size.y - folded_graph) < 0.5, "folded graph keeps transport, clip lane and media lanes")
	editor._timeline_visible = true
	editor._sync_timeline_visibility()
	editor._timeline.set_mode("dope")
	await get_tree().process_frame

	print("SMOKE STEP: collapsible panels")
	editor.size = Vector2(412.0, 915.0)
	editor.set_workspace_mode("studio")
	editor._apply_shell()
	await get_tree().process_frame
	editor._set_section_collapsed("outliner", true)
	await get_tree().process_frame
	_check(editor._outliner.collapsed, "outliner collapses")
	_check(not editor._outliner._scroll.visible, "collapsed outliner hides its list")
	_check(editor._outliner_panel.custom_minimum_size.y <= 48.0, "collapsed outliner keeps a 44 dp header")
	_check("outliner" in Prefs.get_value("editor.collapsed_sections", []), "outliner collapse persists")
	editor._set_section_collapsed("inspector", true)
	await get_tree().process_frame
	_check(editor._inspector.collapsed, "inspector collapses")
	_check(not editor._inspector._scroll.visible, "collapsed inspector hides its fields")
	_check(editor._inspector_panel.custom_minimum_size.y <= 48.0, "collapsed inspector keeps a 44 dp header")
	editor._set_section_collapsed("outliner", false)
	editor._set_section_collapsed("inspector", false)
	await get_tree().process_frame
	_check(not editor._outliner.collapsed and not editor._inspector.collapsed, "panels expand again")
	editor.set_workspace_mode("compact")
	await get_tree().process_frame

	print("SMOKE STEP: graph editor")
	var timeline = editor._timeline
	_check(timeline != null, "timeline exists")
	if timeline != null:
		editor._timeline_visible = true
		editor._sync_timeline_visibility()
		doc.set_selection(key_id)
		var graph_keys: Array = doc.get_channel_keys(key_id, "position")
		_check(graph_keys.size() >= 3, "graph fixture has at least three position keys")

		_check(doc.has_method("set_channel_transition"), "document exposes channel easing")
		if doc.has_method("set_channel_transition") and graph_keys.size() >= 3:
			doc.set_channel_transition(key_id, "position", 0.5)
			var all_channel_eased := true
			for ki in range(graph_keys.size()):
				if not is_equal_approx(doc.get_key_transition(key_id, "position", ki), 0.5):
					all_channel_eased = false
			_check(all_channel_eased, "channel transition applies to every key")
			doc.set_channel_transition(key_id, "position", 9.0)
			_check(is_equal_approx(doc.get_key_transition(key_id, "position", 0), 4.0), "channel transition clamps high")
			doc.set_channel_transition(key_id, "position", -1.0)
			_check(is_equal_approx(doc.get_key_transition(key_id, "position", 0), 0.0), "channel transition clamps low")
			doc.set_channel_transition(key_id, "position", 1.0)

		timeline.set_mode("graph")
		_check(timeline._mode == "graph", "graph mode activates")
		_check(
			Kit.font_regular.get_height(Kit.TYPE_BODY) + int(Kit.theme.get_constant("v_separation", "PopupMenu")) >= 44,
			"easing menu rows meet the 44 dp touch floor"
		)
		var graph_speed: float = timeline._channel_speed(key_id, "position", 0.5)
		_check(graph_speed > 0.01, "graph samples real channel speed")
		var presets_raw = timeline.get("GRAPH_PRESETS")
		var presets: Array = presets_raw if presets_raw is Array else []
		_check(presets.size() >= 8, "graph exposes an expanded preset set")
		_check(timeline.has_method("graph_height_hint"), "graph reports a height hint")
		if timeline.has_method("graph_height_hint"):
			_check(timeline.graph_height_hint() > 0.0, "graph mode requests a taller sheet")
		await get_tree().process_frame
		await get_tree().process_frame
		var graph_panel_height: float = editor._timeline_panel.custom_minimum_size.y
		_check(graph_panel_height > 180.0, "graph mode gives the sheet more height")
		_check(timeline.has_method("graph_plot_rect"), "graph exposes its plot rect")
		if timeline.has_method("graph_plot_rect"):
			var graph_rect: Rect2 = timeline.graph_plot_rect()
			_check(graph_rect.size.x > 100.0, "graph plot has a real drawing area")
			_check(graph_rect.position.y >= timeline._ruler_h + 44.0, "channel tabs sit above the graph plot")
		_check(timeline.has_method("channel_tab_rects"), "graph exposes channel tab hit rects")
		if timeline.has_method("channel_tab_rects"):
			var tabs: Array = timeline.channel_tab_rects()
			_check(tabs.size() == 3, "graph exposes three channel tabs")
			if tabs.size() == 3:
				_check((tabs[0]["rect"] as Rect2).size.y >= 44.0, "graph channel tabs keep 44 dp targets")

		_check(timeline.has_method("set_channel"), "graph switches channels directly")
		if timeline.has_method("set_channel"):
			timeline.select_segment_at_time(0.5)
			_check(timeline._segments.size() > 0, "graph caches real segment hit rects")
			timeline.set_channel("rotation")
			_check(timeline._selected_channel == "rotation", "graph switches channels directly")
			_check(timeline._segments.is_empty(), "channel switch clears stale segment hit rects")
			timeline.set_channel("position")
			await get_tree().process_frame
			await get_tree().process_frame

		_check(timeline.has_method("select_segment_at_time"), "graph supports segment selection")
		if timeline.has_method("select_segment_at_time"):
			timeline.select_segment_at_time(0.5)
			_check(timeline._selected_index >= 0, "tapping a segment selects it")
		_check(timeline.has_method("graph_stats"), "graph exposes live stats")
		if timeline.has_method("graph_stats"):
			var stats: Dictionary = timeline.graph_stats()
			_check(int(stats.get("keys", 0)) >= 3, "graph stats report real key count")
			_check(float(stats.get("peak", 0.0)) > 0.0, "graph stats report a real peak speed")
			var segment_stats: Dictionary = stats.get("segment", {})
			_check(not segment_stats.is_empty(), "graph stats describe the selected segment")
			_check(float(segment_stats.get("duration", 0.0)) > 0.0, "segment stats include duration")

		_check(timeline.has_method("ease_value_for_drag"), "graph maps vertical drag to easing")
		if timeline.has_method("ease_value_for_drag"):
			_check(is_equal_approx(timeline.ease_value_for_drag(0.5, 100.0, 58.0), 1.0), "upward drag doubles the transition")
			_check(is_equal_approx(timeline.ease_value_for_drag(0.5, 100.0, 142.0), 0.25), "downward drag halves the transition")

		# Copy, paste and invert operate on the real Godot transition scalar.
		if timeline.has_method("copy_ease") and timeline.has_method("paste_ease") and timeline.has_method("invert_ease"):
			doc.set_key_transition(key_id, "position", 0, 0.5)
			timeline.select_segment_at_time(0.5)
			_check(timeline.copy_ease(), "graph copies the selected easing")
			_check(timeline._selected_index == 0 and timeline._selected_data_id == key_id and timeline._selected_channel == "position", "copy preserves the segment selection")
			doc.set_key_transition(key_id, "position", 1, 1.0)
			timeline.select_segment_at_time(1.5)
			_check(timeline.paste_ease(), "graph pastes easing onto another segment")
			_check(is_equal_approx(doc.get_key_transition(key_id, "position", 1), 0.5), "paste writes the copied transition")
			_check(timeline._selected_index == 1 and timeline._selected_data_id == key_id and timeline._selected_channel == "position", "paste preserves the segment selection")
			_check(timeline.invert_ease(), "graph inverts the selected easing")
			_check(is_equal_approx(doc.get_key_transition(key_id, "position", 1), 2.0), "invert maps 0.5 to 2.0")
			_check(timeline._selected_index == 1 and timeline._selected_data_id == key_id and timeline._selected_channel == "position", "invert preserves the segment selection")

		if timeline.has_method("apply_ease_to_channel"):
			timeline.select_segment_at_time(0.5)
			_check(timeline.apply_ease_to_channel(), "graph applies easing to the channel")
			var applied := true
			for ki in range(graph_keys.size()):
				if not is_equal_approx(doc.get_key_transition(key_id, "position", ki), 0.5):
					applied = false
			_check(applied, "apply-to-channel writes every segment")
			_check(timeline._selected_index == 0 and timeline._selected_data_id == key_id and timeline._selected_channel == "position", "apply preserves the segment selection")
			doc.set_channel_transition(key_id, "position", 1.0)

		timeline.select_segment_at_time(0.5)
		timeline._apply_ease_preset(4)
		_check(timeline._selected_index == 0 and timeline._selected_data_id == key_id, "preset preserves the segment selection")
		doc.set_channel_transition(key_id, "position", 1.0)

		print("SMOKE STEP: short landscape graph")
		editor.size = Vector2(915.0, 412.0)
		editor.set_workspace_mode("studio")
		editor._apply_shell()
		editor._timeline_visible = true
		editor._sync_timeline_visibility()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(timeline.get("_short_layout") == true, "timeline tracks the short landscape layout")
		_check(editor._view.size.y >= 96.0, "915x412 graph keeps a usable viewport")
		_check(editor._timeline_panel.size.y <= 270.0, "915x412 graph sheet stays within the short budget")
		_check(
			editor._view.size.y + editor._timeline_panel.size.y <= editor.size.y - editor._top_bar.custom_minimum_size.y + 1.0,
			"915x412 graph does not overflow the center column"
		)
		editor.size = Vector2(800.0, 360.0)
		editor._apply_shell()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(editor._view.size.y >= 96.0, "800x360 graph keeps a usable viewport")
		_check(editor._timeline_panel.size.y <= 212.0, "800x360 graph sheet stays within the short budget")
		_check(
			editor._view.size.y + editor._timeline_panel.size.y <= editor.size.y - editor._top_bar.custom_minimum_size.y + 1.0,
			"800x360 graph does not overflow the center column"
		)
		editor.size = Vector2(412.0, 915.0)
		editor.set_workspace_mode("compact")
		editor._apply_shell()
		editor._timeline_visible = true
		editor._sync_timeline_visibility()
		await get_tree().process_frame
		await get_tree().process_frame

		timeline.set_mode("dope")
		await get_tree().process_frame
		_check(timeline._mode == "dope", "dope mode restores")
		_check(editor._timeline_panel.custom_minimum_size.y < graph_panel_height, "dope mode returns the extra height")
		doc.set_selection(ease_id)
		doc.seek(0.0)

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
	# The compact sheet always has room to scroll; the desktop modal is the
	# surface that used to cap its primary action below the fold.
	var previous_layout: String = editor._overlay._layout_mode
	editor._overlay.set_layout_mode("desktop")
	editor._open_render_sheet()
	for _i in 4:
		await get_tree().process_frame
	_check(editor._overlay.has_modal(), "render sheet opens")
	_check(editor._render_sequence_button != null, "render sheet has sequence action")
	_check(editor._render_progress != null, "render sheet has progress readout")
	if editor._render_sequence_button != null:
		var scroll_rect: Rect2 = editor._overlay._body_scroll.get_global_rect()
		var action_rect: Rect2 = editor._render_sequence_button.get_global_rect()
		_check(action_rect.end.y <= scroll_rect.end.y + 0.5, "render sequence action is above the fold in the desktop modal")
	_check(editor._sequence_frame_count() == 144, "sequence frame count follows duration and fps")
	_check(not editor._render_busy, "render sheet is idle on open")
	editor._overlay.close_modal()
	editor._overlay.set_layout_mode(previous_layout)
	await get_tree().process_frame

	print("SMOKE STEP: renderer and settings")
	_check(Gfx.renderer_default_for_platform("Android") == "mobile", "Android default renderer is mobile")
	_check(Gfx.renderer_default_for_platform("Linux") == "forward_plus", "desktop default renderer is forward plus")
	_check(Gfx.build_restart_args("mobile") == PackedStringArray(["--rendering-method", "mobile", "--rendering-driver", "vulkan"]), "mobile restart args are real")
	_check(Gfx.build_restart_args("gl_compatibility") == PackedStringArray(["--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3"]), "compatibility restart args are real")
	_check(Gfx.capabilities_for("mobile")["taa"] == false, "Mobile does not claim TAA")
	_check(Gfx.capabilities_for("forward_plus")["taa"] == true, "Forward+ reports TAA")
	var restart_state: Dictionary = Gfx.resolve_startup_renderer("mobile", "mobile", "forward_plus", 0, "Linux")
	_check(restart_state["action"] == "restart", "pending renderer requests one restart")
	_check(restart_state["args"].size() == 4, "pending renderer has restart args")
	var fallback_state: Dictionary = Gfx.resolve_startup_renderer("mobile", "mobile", "forward_plus", 2, "Linux")
	_check(fallback_state["action"] == "fallback", "renderer retry is bounded")
	_check(fallback_state["preference"] == "forward_plus", "renderer fallback uses platform default")
	_check(str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile")) == "mobile", "project.godot defaults Android to Mobile")

	editor._open_settings("graphics")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._overlay.has_modal(), "settings opens")
	_check(editor._settings_panel.categories() == ["general", "editor", "display", "graphics", "performance", "render", "import", "media", "rig", "about"], "settings categories are complete")
	_check(editor._preset_buttons.size() == 5, "graphics has preset controls plus custom and reset")
	var original_preset: String = Gfx.preset
	Gfx.preset = "custom"
	editor._sync_preset_buttons()
	var any_preset_lit := false
	var custom_lit := false
	for button in editor._preset_buttons:
		var preset_name := str(button.get_meta("preset", ""))
		if preset_name in ["performance", "balanced", "quality"] and button.button_pressed:
			any_preset_lit = true
		if preset_name == "custom":
			custom_lit = button.button_pressed and button.disabled
	_check(not any_preset_lit, "custom settings clear the preset selection")
	_check(custom_lit, "custom settings light the disabled Custom status")
	Gfx.preset = "balanced"
	editor._sync_preset_buttons()
	var balanced_lit := false
	for chip in editor._preset_buttons:
		if str(chip.get_meta("preset", "")) == "balanced" and chip.button_pressed:
			balanced_lit = true
	_check(balanced_lit, "balanced preset reselects its chip")
	Gfx.preset = original_preset
	editor._settings_panel.set_option("editor.show_fps", false)
	_check(bool(Prefs.get_value("editor.show_fps", true)) == false, "settings write Prefs")
	editor._settings_panel.set_option("editor.show_fps", true)
	editor._open_settings("display")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._settings_panel._resolved_mode() == "Compact", "settings reports the resolved workspace")
	editor.apply_fit_info(43.0, false, false)
	await get_tree().process_frame
	_check(editor._settings_panel._ui_scale_control.disabled, "UI scale is disabled when Desktop fit is active")
	_check(editor._settings_panel._fit_label.text.contains("43"), "settings shows the fit percentage")
	editor.apply_fit_info(100.0, true, false)
	await get_tree().process_frame
	_check(not editor._settings_panel._ui_scale_control.disabled, "UI scale works at 100 percent fit")
	editor._overlay.close_modal()
	await get_tree().process_frame

	print("SMOKE STEP: workspace fit refresh")
	editor._open_workspace_sheet()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._workspace_sheet != null, "workspace sheet opens")
	_check(editor._workspace_sheet._mode_buttons["compact"].button_pressed, "workspace shows the saved arrangement preference")
	_check(editor._workspace_sheet._resolved_mode() == "compact", "workspace reports the resolved mode")
	_check(editor._workspace_sheet._orientation_stacked, "workspace stacks orientation on a narrow sheet")
	_check(editor._workspace_sheet._orientation_track != null, "workspace exposes a real orientation control")
	editor.apply_fit_info(43.0, false, false)
	await get_tree().process_frame
	_check(editor._workspace_sheet._scale_control.disabled, "workspace UI scale locks when fit is active")
	_check(editor._workspace_sheet._fit_label.text.contains("43"), "workspace reports the live fit percentage")
	editor.apply_fit_info(100.0, true, false)
	await get_tree().process_frame
	_check(not editor._workspace_sheet._scale_control.disabled, "workspace UI scale unlocks at 100 percent")
	editor._overlay.close_modal()
	await get_tree().process_frame

	editor.size = Vector2(1440.0, 900.0)
	editor._apply_shell()
	editor._open_workspace_sheet()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not editor._workspace_sheet._orientation_stacked, "wide workspace keeps orientation inline")
	_check(editor._workspace_sheet._orientation_track.custom_minimum_size.x >= 280.0, "wide orientation strip keeps a real target width")
	editor._overlay.close_modal()
	await get_tree().process_frame
	editor.size = Vector2(412.0, 915.0)
	editor.set_workspace_mode("compact")
	await get_tree().process_frame
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
	_check(draft_view.quick_render_requested.is_connected(editor._enter_render_mode), "quick render HUD is wired to the live render mode")
	draft_view.set_draft_quality(draft_pref)

	print("SMOKE STEP: real-time render mode")
	var render_view = editor._view
	_check(render_view._quick_render_button != null, "quick render HUD control exists")
	_check(render_view._quick_render_button.custom_minimum_size == Vector2(44, 44), "quick render HUD control is a 44 dp square")
	_check(render_view._fps_chip.custom_minimum_size.y >= 44.0, "FPS chip keeps a 44 dp height")
	_check(render_view._focus_button.custom_minimum_size.y >= 44.0, "focus HUD control keeps a 44 dp height")
	_check(render_view._grid_button.custom_minimum_size.y >= 44.0, "grid HUD control keeps a 44 dp height")
	var render_was_playing: bool = doc.is_playing
	doc.pause()
	doc.seek(1.0)
	editor._enter_render_mode()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._render_mode, "quick render enters a real-time render mode")
	_check(render_view.render_mode, "viewport enters render mode")
	_check(not editor._top_bar.visible, "render mode hides the top bar")
	_check(not editor._timeline_panel.visible, "render mode hides the timeline")
	_check(not render_view._hud_root.visible, "render mode hides the editing HUD")
	_check(editor._render_hud.visible, "render transport is visible")
	_check(doc.is_playing, "render mode plays the document in real time")
	_check(not render_view.is_draft_active(), "render mode uses full quality")
	_check(editor._render_play_button.custom_minimum_size.y >= 44.0, "render transport keeps 44 dp controls")
	editor._toggle_render_playback()
	await get_tree().process_frame
	_check(not doc.is_playing, "render transport pauses playback")
	editor._toggle_render_playback()
	await get_tree().process_frame
	_check(doc.is_playing, "render transport resumes playback")
	editor._restart_render_playback()
	await get_tree().process_frame
	_check(doc.current_time < 0.5, "render transport restarts at the first frame")
	editor._exit_render_mode()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not editor._render_mode, "render mode exits")
	_check(not render_view.render_mode, "viewport returns to editing")
	_check(editor._top_bar.visible, "editing chrome returns")
	_check(not editor._render_hud.visible, "render transport hides")
	_check(is_equal_approx(doc.current_time, 1.0), "exiting restores the playhead")
	_check(doc.is_playing == render_was_playing, "exiting restores the prior playback state")
	doc.pause()

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
