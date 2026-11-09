extends Control
## Temporary headless smoke test. Not part of the app.

const RenderExport = preload("res://src/core/render_export.gd")
const DocumentScript = preload("res://src/core/document.gd")
const WorkspacePanelScript = preload("res://src/ui/components/workspace_panel.gd")

var _failures: Array[String] = []
func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		printerr("SMOKE FAIL: " + message)
	else:
		print("SMOKE OK: " + message)

func _collect_group_buttons(node: Node, acc: Array) -> void:
	for child in node.get_children():
		if child is Button:
			var button := child as Button
			if button.button_group != null:
				acc.append(button)
		_collect_group_buttons(child, acc)

## Resize the whole canvas, not the anchored editor. Assigning `editor.size`
## while the editor is full-rect produced stale layout measurements; a real
## window resize goes through the same path the app uses on a device.
func _resize_shell(main: Control, editor: Control, value: Vector2) -> void:
	get_window().size = Vector2i(value)
	await get_tree().process_frame
	await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame
	await get_tree().process_frame
	editor._apply_shell()
	await get_tree().process_frame

## Minimal PCM WAV fixture for the media-record migration. The old smoke test
## drove the removed lane rows; the document records still need a real file.
func _write_smoke_wav(path: String) -> void:
	var sample_rate := 44100
	var frames := sample_rate
	var pcm := PackedByteArray()
	pcm.resize(frames * 2)
	for i in range(frames):
		pcm.encode_s16(i * 2, int(sin(TAU * 220.0 * float(i) / float(sample_rate)) * 12000.0))
	var header := PackedByteArray()
	header.resize(44)
	header.encode_u32(0, 0x46464952) # RIFF
	header.encode_u32(4, 36 + pcm.size())
	header.encode_u32(8, 0x45564157) # WAVE
	header.encode_u32(12, 0x20746D66) # fmt
	header.encode_u32(16, 16)
	header.encode_u16(20, 1)
	header.encode_u16(22, 1)
	header.encode_u32(24, sample_rate)
	header.encode_u32(28, sample_rate * 2)
	header.encode_u16(32, 2)
	header.encode_u16(34, 16)
	header.encode_u32(36, 0x61746164) # data
	header.encode_u32(40, pcm.size())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(header + pcm)
	file.close()

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
	# Black chrome (2026-11-01 override): a pure black window, hierarchy from
	# near-black elevation, and text contrast as the readability floor.
	_check(Kit.BG == Color(0, 0, 0), "the app background is pure black")
	_check(ProjectSettings.get_setting(
			"rendering/environment/defaults/default_clear_color", Color(0, 0, 0, 1)) == Color(0, 0, 0, 1),
		"the window clears to pure black")
	_check(Kit.SURFACE.get_luminance() < Kit.SURFACE_2.get_luminance()
		and Kit.SURFACE_2.get_luminance() < Kit.SURFACE_3.get_luminance()
		and Kit.SURFACE_3.get_luminance() < Kit.SURFACE_HOVER.get_luminance()
		and Kit.SURFACE_HOVER.get_luminance() < Kit.SURFACE_ACTIVE.get_luminance(),
		"surface elevation is a near-black ladder")
	_check(_contrast(Kit.BG, Kit.SURFACE_ACTIVE) < 4.0, "every elevation step stays near-black")
	_check(_contrast(Kit.TEXT_MUTED, Kit.BG) >= 4.5, "muted chrome text keeps 4.5:1 on the stage")
	_check(_contrast(Kit.TEXT_DIM, Kit.SURFACE_2) >= 4.5, "dim text keeps 4.5:1 on the raised fill")
	_check(_contrast(Kit.FOCUS_BRIGHT, Kit.BG) >= 3.0, "focus rings keep 3:1 on black")
	var separator := Kit.vsep()
	_check(separator.color == Kit.BORDER_SOFT and separator.custom_minimum_size.y <= 1.5,
		"a hairline separator survives the black-chrome pass")
	var field_style: StyleBoxFlat = Kit.theme.get_stylebox("normal", "LineEdit")
	_check(field_style.get_border_width(SIDE_BOTTOM) >= 1,
		"fields keep their boundary hairline")
	# Fix round 1: a control boundary is not a decorative divider. The field
	# hairline has to clear 3:1 against the fill it sits on; the quiet
	# separator token is deliberately exempt because it never delimits a
	# control.
	_check(_contrast(field_style.border_color, field_style.bg_color) >= 3.0,
		"the field boundary clears 3:1 against its fill")
	_check(field_style.border_color == Kit.CONTROL_BORDER,
		"the field hairline uses the control boundary token")
	_check(_contrast(Kit.BORDER_SOFT, Kit.SURFACE_2) < 3.0,
		"separators stay quiet rather than turning into control edges")
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
		_check(bool(phone_desktop["user_scale_enabled"]), "desktop fit keeps user scale enabled")
		var desktop_min = LayoutMathScript.resolve(Vector2i(960, 600), 160.0, "Linux", 1.0, "desktop", true)
		_check(is_equal_approx(desktop_min["fit"], 1.0), "960x600 desktop has 100 percent fit")
		var huge_scale = LayoutMathScript.resolve(Vector2i(1440, 900), 160.0, "Linux", 2.0, "desktop", true)
		_check(is_equal_approx(float(huge_scale["user_scale"]), 2.0), "layout math accepts 200 percent")
		_check(is_equal_approx(float(huge_scale["factor"]), 2.0), "200 percent doubles the effective factor")
		_check(huge_scale["logical_after"].x <= 721.0 and huge_scale["logical_after"].y <= 451.0, "200 percent halves the logical canvas")
		_check(bool(huge_scale["user_scale_enabled"]), "200 percent is never locked out")
		var tiny_scale = LayoutMathScript.resolve(Vector2i(1440, 900), 160.0, "Linux", 0.5, "desktop", true)
		_check(is_equal_approx(float(tiny_scale["user_scale"]), 0.5), "layout math accepts 50 percent")
		_check(is_equal_approx(float(tiny_scale["factor"]), 0.5), "50 percent halves the effective factor")
		var fit_scale_1 = LayoutMathScript.resolve(Vector2i(1080, 2400), 420.0, "Android", 1.0, "desktop", true)
		var fit_scale_2 = LayoutMathScript.resolve(Vector2i(1080, 2400), 420.0, "Android", 2.0, "desktop", true)
		_check(float(fit_scale_2["factor"]) > float(fit_scale_1["factor"]), "user scale still changes the factor under desktop fit")
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
		prefs_a.set_value("display.user_scale", 1.8)
		var prefs_b = PrefsScript.new()
		prefs_b.settings_path = test_path
		prefs_b.load_settings()
		_check(is_equal_approx(float(prefs_b.get_value("display.user_scale", 0.0)), 1.8), "prefs persist values outside the old range")
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
	_check(editor.layout_mode() == str(live_layout.get("mode", "")), "editor receives the resolved mode")
	# The shell follows the preference even when the window itself cannot be
	# measured. Restore the editor to the live window mode afterwards.
	editor.apply_layout(LayoutMathScript.resolve(Vector2i(1080, 2400), 420.0, "Android", 1.0, "compact", true))
	_check(editor.layout_mode() == "compact", "editor switches to the compact shell")
	editor.apply_layout(LayoutMathScript.resolve(Vector2i(1080, 2400), 420.0, "Android", 1.0, "desktop", true))
	_check(editor.layout_mode() == "desktop", "desktop stays selected on a phone")
	_check(float(editor.layout_info.get("fit", 1.0)) < 1.0, "desktop fit is reported to the editor")
	editor.apply_layout(live_layout)
	_check(editor.layout_mode() == str(live_layout.get("mode", "")), "editor returns to the live mode")
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
	_check(int(contract_data.get("format", 0)) == 3, "documents serialize as format 3")
	for key in ["clips", "layers", "rigs", "media", "materials"]:
		_check(contract_data.has(key), "format 3 carries %s" % key)
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
	editor.set_layout_mode("compact")
	# The workspace is persisted, so a previous run can leave any of the five
	# active. Pin Scene before asserting its context row.
	editor.set_workspace("scene")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor.layout_mode() == "compact", "compact mode applies")
	_check(editor._workspace_bar.size.y >= 43.5, "compact top bar is 44 dp")
	_check(editor._context_bar.size.y >= 43.5, "compact context row is 44 dp")
	_check(editor._transport_bar.size.y >= 43.5, "compact transport is 44 dp")
	await _resize_shell(main, editor, Vector2(360.0, 640.0))
	var compact_min: float = editor._layout.get_combined_minimum_size().x
	print("SMOKE INFO: compact shell minimum width ", compact_min)
	_check(compact_min <= 360.5, "compact shell fits the 360x640 budget")
	_check(editor._workspace_bar.get_combined_minimum_size().x <= 360.5, "the top bar fits 360 dp")
	_check(editor._context_bar.get_combined_minimum_size().x <= 360.5, "the context row fits 360 dp")
	_check(editor._transport_bar.get_combined_minimum_size().x <= 360.5, "the transport fits 360 dp")
	_check(not editor._context_bar.visible_action_ids().has("view"),
		"the context row demotes the lowest-priority scene action on a phone")
	var move_button: Button = editor._context_bar.action_button("move")
	_check(move_button != null, "the context row exposes the Move tool")
	if move_button != null:
		move_button.pressed.emit()
		await get_tree().process_frame
		_check(editor._tool == "move" and move_button.button_pressed,
			"the context row selects the active tool")
		editor._context_bar.action_button("select").pressed.emit()
		await get_tree().process_frame
	# Scene tree and Inspector share the one overlay slot.
	await _resize_shell(main, editor, Vector2(412.0, 915.0))
	editor.set_workspace("scene")
	await get_tree().process_frame
	var stage_width: float = editor._stage_host.size.x
	editor._toggle_scene_panel("scene")
	for _i in 2:
		await get_tree().process_frame
	_check(editor._workspace_panel.mode() == WorkspacePanelScript.Mode.OVERLAY,
		"the scene tree opens as an overlay")
	_check(editor._workspace_panel.content() == editor._outliner_panel,
		"the overlay owns the one outliner")
	_check(editor._workspace_panel.scrim().visible, "the overlay dims the stage")
	_check(absf(editor._stage_host.size.x - stage_width) < 0.5,
		"opening the overlay does not resize the stage")
	_check(editor._workspace_panel.panel_rect().size.x <= 400.0,
		"the phone overlay respects the 400 dp cap")
	editor._toggle_scene_panel("inspector")
	for _i in 2:
		await get_tree().process_frame
	_check(editor._workspace_panel.content() == editor._inspector_panel,
		"opening the inspector replaces the scene tree")
	editor._workspace_panel.close_button().pressed.emit()
	for _i in 2:
		await get_tree().process_frame
	_check(editor._workspace_panel.mode() == WorkspacePanelScript.Mode.HIDDEN,
		"the overlay close button returns the stage")

	print("SMOKE STEP: black chrome")
	_check(Kit.theme.get_stylebox("panel", "PanelContainer").get_border_width(SIDE_LEFT) == 0,
		"the default panel stylebox draws no border")
	for shell_panel_name in ["_outliner_panel", "_inspector_panel", "_rig_frame"]:
		var shell_panel = editor.get(shell_panel_name)
		_check(shell_panel != null, "black chrome: %s is mounted" % shell_panel_name)
		if shell_panel != null:
			var shell_style: StyleBoxFlat = shell_panel.get_theme_stylebox("panel")
			_check(shell_style.get_border_width(SIDE_LEFT) == 0
				and shell_style.get_border_width(SIDE_TOP) == 0
				and shell_style.get_border_width(SIDE_RIGHT) == 0
				and shell_style.get_border_width(SIDE_BOTTOM) == 0,
				"the shell panel %s draws no outline" % shell_panel_name)
	var transport_style: StyleBoxFlat = editor._timeline.transport_panel().get_theme_stylebox("panel")
	_check(transport_style != null and transport_style.get_border_width(SIDE_LEFT) == 0
		and transport_style.get_border_width(SIDE_TOP) == 0
		and transport_style.get_border_width(SIDE_RIGHT) == 0
		and transport_style.get_border_width(SIDE_BOTTOM) == 0,
		"the timeline transport draws no border")
	var panel_style: StyleBoxFlat = editor._workspace_panel._panel.get_theme_stylebox("panel")
	_check(panel_style.get_border_width(SIDE_LEFT) <= 1
		and panel_style.get_border_width(SIDE_TOP) == 0
		and panel_style.get_border_width(SIDE_RIGHT) == 0
		and panel_style.get_border_width(SIDE_BOTTOM) == 0,
		"the workspace panel keeps at most a quiet leading edge")
	if panel_style.get_border_width(SIDE_LEFT) > 0:
		_check(panel_style.border_color == Kit.BORDER_SOFT,
			"the workspace panel edge uses the quiet separator token")
	var shell_separators := 0
	for node in editor.find_children("*", "ColorRect", true, false):
		var chrome_line := node as ColorRect
		if chrome_line.color == Kit.BORDER_SOFT and (chrome_line.size.x <= 1.5 or chrome_line.size.y <= 1.5):
			shell_separators += 1
	_check(shell_separators > 0, "the shell keeps at least one separator")
	# Transient cards are floating surfaces too. They separate by elevation; a
	# 1 px frame re-introduces the outline the override removed.
	var toast_style: StyleBoxFlat = editor._overlay._toast_panel.get_theme_stylebox("panel")
	_check(toast_style.get_border_width(SIDE_LEFT) == 0
		and toast_style.get_border_width(SIDE_TOP) == 0
		and toast_style.get_border_width(SIDE_RIGHT) == 0
		and toast_style.get_border_width(SIDE_BOTTOM) == 0,
		"the toast card draws no border")
	var hud_style: StyleBoxFlat = editor._render_hud.get_theme_stylebox("panel")
	_check(hud_style.get_border_width(SIDE_LEFT) == 0
		and hud_style.get_border_width(SIDE_TOP) == 0
		and hud_style.get_border_width(SIDE_RIGHT) == 0
		and hud_style.get_border_width(SIDE_BOTTOM) == 0,
		"the render HUD card draws no border")

	print("SMOKE STEP: control boundaries")
	# Fix round 2: every swept control edge is pinned. A future revert of any
	# one of these to BORDER_SOFT would drop it to 1.26:1 and fail here.
	var inspector_color_button: Button = editor._inspector._color_button
	_check(inspector_color_button != null, "the inspector exposes its colour button")
	if inspector_color_button != null:
		_check_control_edge(inspector_color_button.get_theme_stylebox("normal"),
			"the inspector colour button", Kit.SURFACE_2)
	var vector_field = editor._inspector._fields["position"][0]
	var vector_frame: PanelContainer = vector_field.get_parent().get_parent()
	_check_control_edge(vector_frame.get_theme_stylebox("panel"),
		"the inspector vector frame", Kit.SURFACE_2)
	_check_control_edge(home._template_style(false),
		"the home template card", Kit.SURFACE_2)
	var pose_probe = load("res://src/ui/pose_panel.gd").new()
	add_child(pose_probe)
	var pose_chip: PanelContainer = pose_probe._make_chip({"id": "probe", "name": "Probe"})
	add_child(pose_chip)
	_check_control_edge(pose_chip.get_theme_stylebox("panel"),
		"the pose chip", Kit.SURFACE_2)
	pose_chip.queue_free()
	pose_probe.queue_free()
	editor._open_color_sheet("color")
	for _i in 4:
		await get_tree().process_frame
	var swatch_checked := false
	for node in editor._overlay.find_children("*", "Button", true, false):
		var swatch_button := node as Button
		if swatch_button == null or not swatch_button.tooltip_text.begins_with("#"):
			continue
		var swatch_style: StyleBoxFlat = swatch_button.get_theme_stylebox("normal")
		if swatch_style != null and swatch_style.border_color == Kit.CONTROL_BORDER:
			_check_control_edge(swatch_style, "the colour swatch", Kit.SURFACE_2)
			swatch_checked = true
			break
	_check(swatch_checked, "the colour sheet exposes a control-edged swatch")
	editor._overlay.close_modal(true)
	await get_tree().process_frame

	print("SMOKE STEP: material workspace")
	var smoke_target_id: String = doc.selected_id
	var smoke_material: String = doc.material_system.create_material("Smoke Paint", "matte")
	editor.set_workspace("shading")
	for _i in 2:
		await get_tree().process_frame
	_check(editor.workspace() == "shading", "the Shading workspace opens")
	_check(not editor._overlay.has_modal(), "Shading is embedded, not modal")
	var shading_panel = editor._shading_panel
	_check(shading_panel != null, "the embedded Shading panel is mounted")
	var library_sheet = shading_panel.material_sheet()
	var editor_sheet = shading_panel.material_editor()
	_check(library_sheet != null and library_sheet.get_parent() != null,
		"the material library is an embedded child")
	_check(editor_sheet != null and editor_sheet.get_parent() != null,
		"the material editor is an embedded child")
	_check(editor._material_sheet == library_sheet,
		"the library alias points at the embedded sheet")
	_check(editor._material_editor_sheet == editor_sheet,
		"the editor alias points at the embedded sheet")
	shading_panel.set_target(smoke_target_id)
	shading_panel.select_material(smoke_material)
	await get_tree().process_frame
	_check(library_sheet.row_count() > 0, "the material library lists real records")
	_check(library_sheet.row_height(smoke_material) >= 44.0, "a material row is 44 dp tall")
	_check(library_sheet.assign_button(smoke_material).custom_minimum_size.y >= 44.0,
		"Assign is 44 dp tall")
	_check(editor_sheet.material_id() == smoke_material, "selecting a row loads the editor")
	var assign_undo: int = (doc._undo_stack as Array).size()
	_check(shading_panel.assign_selected(), "Assign succeeds for the selected object")
	_check((doc._undo_stack as Array).size() == assign_undo + 1, "Assign is one undo entry")
	_check(str(doc.get_object(smoke_target_id).get("material_id", "")) == smoke_material,
		"Assign writes the real target assignment")
	_check(not editor._overlay.has_modal(), "Assign keeps the Shading panel embedded")

	# The inspector hands the real target to the same embedded panel.
	editor.set_workspace("scene")
	for _i in 2:
		await get_tree().process_frame
	doc.set_selection(smoke_target_id)
	editor._inspector._rebuild()
	await get_tree().process_frame
	_check(editor._inspector.edit_material_button() != null \
		and editor._inspector.edit_material_button().custom_minimum_size == Vector2(96.0, 44.0),
		"the inspector exposes the 96x44 Shading handoff")
	editor._inspector.edit_material_button().pressed.emit()
	for _i in 2:
		await get_tree().process_frame
	_check(editor.workspace() == "shading", "the inspector handoff switches workspace")
	_check(editor._shading_panel.material_editor().material_id() == smoke_material,
		"the handoff loads the assigned material")
	_check(not editor._overlay.has_modal(), "the inspector handoff opens no modal")
	editor.set_workspace("scene")
	await get_tree().process_frame

	_check(editor_sheet.texture_filter() == "*.png, *.jpg, *.jpeg, *.webp;Images",
		"the editor sheet carries the texture filter")
	for model in ["pbr", "unlit", "toon", "rim"]:
		_check(editor_sheet.shading_button(model).custom_minimum_size.y >= 44.0,
			"the %s segment is 44 dp tall" % model)

	var color_capture: Dictionary = {}
	editor.open_color_sheet(
		{"kind": "material", "id": smoke_material},
		"albedo_color",
		Color(0.2, 0.4, 0.6),
		func(color: Color) -> void: color_capture["color"] = color
	)
	for _i in 4:
		await get_tree().process_frame
	_check(editor._overlay.has_modal(), "the generalized colour sheet opens")
	editor._set_color_value(Color(0.12, 0.34, 0.56))
	_check((color_capture.get("color", Color.BLACK) as Color).is_equal_approx(Color(0.12, 0.34, 0.56)),
		"the generalized colour sheet commits through the callback")
	editor._overlay.close_modal(true)
	await get_tree().process_frame
	editor._open_color_sheet("color")
	for _i in 4:
		await get_tree().process_frame
	_check(editor._overlay.has_modal(), "the object colour caller still opens")
	editor._overlay.close_modal(true)
	await get_tree().process_frame
	doc.material_system.delete_material(smoke_material)
	await get_tree().process_frame

	var view_before: float = editor._view.size.x
	editor._toggle_scene_panel("inspector")
	for _i in 4:
		await get_tree().process_frame
	_check(editor._workspace_panel.mode() == WorkspacePanelScript.Mode.OVERLAY,
		"studio opens the properties overlay")
	_check(editor._workspace_panel.scrim().visible, "the overlay dims the stage it covers")
	_check(editor._workspace_panel.content() == editor._inspector_panel,
		"the properties overlay owns the inspector")
	_check(absf(editor._view.size.x - view_before) < 1.0, "opening the overlay does not shrink the viewport")
	_check(absf(editor._workspace_panel.panel_rect().end.y - editor.size.y) <= 1.0,
		"the overlay reaches the bottom edge")
	_check(editor._inspector_panel.size.y >= 320.0, "the properties page owns the overlay height")
	editor._workspace_panel.close_button().pressed.emit()
	await get_tree().process_frame
	_check(editor._workspace_panel.mode() == WorkspacePanelScript.Mode.HIDDEN,
		"the overlay close button returns the stage")

	print("SMOKE STEP: scene panel state")
	await _resize_shell(main, editor, Vector2(1280.0, 800.0))
	editor.set_layout_mode("studio")
	await get_tree().process_frame
	editor.set_workspace("scene")
	editor._toggle_scene_panel("scene")
	for _i in 3:
		await get_tree().process_frame
	_check(editor._workspace_panel.mode() == WorkspacePanelScript.Mode.OVERLAY,
		"the scene tree is an overlay at 1280 dp")
	var stage_before: float = editor._stage_host.size.x
	_check(editor._workspace_panel.content() == editor._outliner_panel,
		"the scene overlay owns the one outliner")
	_check(absf(editor._stage_host.size.x - stage_before) < 0.5,
		"the overlay never reserves a scene column")

	var scene_outliner = editor._outliner
	var scene_pick: String = doc.selected_id
	if scene_pick == "" and not doc.objects.is_empty():
		scene_pick = str(doc.objects[0]["id"])
	doc.set_selection(scene_pick)
	scene_outliner._on_scene_changed()
	await get_tree().process_frame
	_check(scene_outliner._count.text == str(doc.objects.size()),
		"the outliner count badge tracks the object count")

	# Filter and scroll state survives switching pages and closing the overlay.
	var fill_ids: Array[String] = []
	for i in 16:
		fill_ids.append(doc.add_primitive("plane", Vector3(float(i) * 0.6 - 4.0, -6.0, 0.0)))
	doc.set_selection(scene_pick)
	var scene_filter := "a"
	scene_outliner._search.text = scene_filter
	scene_outliner._on_search_changed(scene_filter)
	for _i in 2:
		await get_tree().process_frame
	scene_outliner._scroll.scroll_vertical = 200
	await get_tree().process_frame
	var scene_scroll: int = scene_outliner._scroll.scroll_vertical
	_check(scene_scroll > 0, "the scene list scrolls to a non-zero offset")

	editor._toggle_scene_panel("inspector")
	for _i in 2:
		await get_tree().process_frame
	_check(editor._workspace_panel.content() == editor._inspector_panel,
		"Properties replaces the scene tree in the same slot")
	editor._toggle_scene_panel("scene")
	for _i in 2:
		await get_tree().process_frame
	_check(editor._workspace_panel.content() == editor._outliner_panel,
		"Scene returns the outliner to the slot")
	_check(editor._outliner == scene_outliner, "the outliner instance survives page switches")
	_check(doc.selected_id == scene_pick, "switching pages preserves the selection")
	_check(scene_outliner._search.text == scene_filter,
		"switching pages preserves the scene search")
	_check(scene_outliner._scroll.scroll_vertical == scene_scroll,
		"switching pages preserves the scene scroll")

	editor._workspace_panel.close_button().pressed.emit()
	for _i in 2:
		await get_tree().process_frame
	_check(editor._workspace_panel.mode() == WorkspacePanelScript.Mode.HIDDEN,
		"closing the overlay returns the stage")
	_check(editor._outliner == scene_outliner and doc.selected_id == scene_pick,
		"closing the overlay keeps the one outliner and the selection")
	editor._toggle_scene_panel("scene")
	for _i in 2:
		await get_tree().process_frame
	_check(scene_outliner._search.text == scene_filter
		and scene_outliner._scroll.scroll_vertical == scene_scroll,
		"reopening the overlay preserves the scene state")

	scene_outliner._search.text = ""
	scene_outliner._on_search_changed("")
	await get_tree().process_frame
	for fill_id in fill_ids:
		doc.delete_object(fill_id)
	doc.set_selection(scene_pick)
	await get_tree().process_frame
	var outliner = editor._outliner
	var outliner_overflow: bool = outliner._list.get_combined_minimum_size().y + 16.0 > outliner._scroll.size.y
	_check(not outliner_overflow or absf(fmod(outliner._scroll.size.y - 6.0, 45.0)) < 0.6,
		"scene list viewport ends on a whole row")
	editor._workspace_panel.close_button().pressed.emit()
	await get_tree().process_frame
	editor.set_layout_mode("desktop")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor.layout_mode() == "desktop", "desktop mode applies on any screen")
	_check(editor._workspace_bar.size.y >= 31.5 and editor._workspace_bar.size.y <= 32.5,
		"desktop top bar is 32 dp")
	_check(editor._context_bar.size.y >= 35.5 and editor._context_bar.size.y <= 36.5,
		"desktop context row is 36 dp")
	_check(editor._transport_bar.size.y >= 31.5 and editor._transport_bar.size.y <= 32.5,
		"desktop transport is 32 dp")
	_check(not editor._instrumentation.visible,
		"the desktop instrumentation strip stays off by default")
	_check(str(Prefs.get_value("display.layout", "")) == "desktop", "workspace mode persists")

	print("SMOKE STEP: animate pane timeline")
	await _resize_shell(main, editor, Vector2(1280.0, 800.0))
	editor.set_layout_mode("studio")
	await get_tree().process_frame
	editor.set_workspace("animate")
	for _i in 2:
		await get_tree().process_frame
	_check(editor._animate_pane.visible, "the Animate workspace opens the pane")
	_check(editor._timeline.get_parent() == editor._animate_pane,
		"the timeline is mounted in the Animate pane")
	_check(editor._stage_host.get_global_rect().end.y <=
		editor._animate_pane.get_global_rect().position.y + 0.5,
		"the pane sits below the stage and never covers it")
	_check(not editor._transport_bar.visible,
		"the shared transport yields to the timeline transport")
	var animate_transport: Control = editor._timeline.transport_panel()
	_check(animate_transport != null and editor._animate_pane.is_ancestor_of(animate_transport),
		"the timeline transport lives inside the pane")
	_check(editor._timeline.sheet_visible(), "the dope sheet opens with the workspace")
	var animate_view_before: Vector2 = editor._view.size
	editor._timeline.set_mode("graph")
	await get_tree().process_frame
	_check(editor._timeline.mode() == "graph", "the pane switches to graph mode")
	_check(editor._timeline.graph_plot_rect().size.x > 100.0,
		"the graph plot has a real drawing area")
	editor._timeline.set_mode("dope")
	await get_tree().process_frame
	editor._timeline.set_sheet_visible(false)
	await get_tree().process_frame
	_check(not editor._timeline.sheet_visible(),
		"the pane folds the sheet without leaving Animate")
	_check(editor._animate_pane.visible
		and editor._timeline.transport_panel().is_visible_in_tree(),
		"the folded pane keeps its transport reachable")
	editor._timeline.set_sheet_visible(true)
	await get_tree().process_frame
	_check(editor._timeline.sheet_visible(), "the sheet reopens")
	# Time viewport: pan and zoom remap time to pixels without changing the
	# document duration, and every hit test shares the same mapping.
	var time_tl = editor._timeline
	var sheet = time_tl._sheet
	var duration: float = doc.duration
	doc.set_selection(key_id)
	for _i in 2:
		await get_tree().process_frame
	var full_view: Vector2 = time_tl.time_view()
	_check(absf(full_view.x) < 0.001 and absf(full_view.y - duration) < 0.01,
		"the time view starts at the full duration")
	time_tl.pan_time_view(1.0)
	_check(absf(time_tl.time_view().x) < 0.001,
		"panning a full-duration view is a no-op")
	var fit_track: Rect2 = time_tl.scrollbar_track_rect()
	_check(fit_track.size.x > 0.0,
		"the scrollbar track is painted even when the whole duration fits")
	var fit_thumb: Rect2 = time_tl.scrollbar_thumb_rect()
	_check(is_equal_approx(fit_thumb.size.x, fit_track.size.x),
		"fit mode paints a full-width thumb")
	_check(not time_tl.scrollbar_owns_press(fit_track.position + fit_track.size * 0.5),
		"fit mode never lets the scrollbar steal a press")
	_check(time_tl.has_method("scrollbar_caption"),
		"the sheet exposes its scrollbar caption")
	if time_tl.has_method("scrollbar_caption"):
		_check(time_tl.scrollbar_caption() == "Fit · pinch to zoom",
			"fit mode captions the pinch gesture")
	# Duration truth: the chip always names the active clip and, when the
	# sequence is longer, keeps the two clocks visibly distinct.
	var clip_id: String = doc.active_clip_id()
	var layer_id: String = doc.animation_system.active_layer_id()
	var long_clip: String = doc.animation_system.create_clip(
		"Duration probe", maxf(duration + 3.0, 10.0))
	var long_strip: String = doc.animation_system.add_strip(layer_id, long_clip, 0.0)
	doc.animation_system.set_active_clip(clip_id)
	await get_tree().process_frame
	# The probe mutates the animation system directly rather than through the
	# transport, so force the refresh a real clip-length edit would send.
	time_tl._sync_duration_row()
	_check(doc.sequence_duration() > doc.duration + 0.05,
		"the duration probe makes the sequence longer than the clip")
	_check(time_tl.has_method("duration_chip_text"),
		"the sheet exposes the duration chip text")
	if time_tl.has_method("duration_chip_text"):
		var chip_text: String = time_tl.duration_chip_text()
		_check(chip_text.contains("Seq"), "the chip names the longer sequence clock")
		_check(chip_text.contains("s"), "the chip names the clip length in seconds")
		var chip: Button = time_tl.duration_chip()
		var chip_font: Font = chip.get_theme_font("font")
		var chip_size: int = chip.get_theme_font_size("font_size")
		var full_width: float = chip_font.get_string_size(
			chip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, chip_size).x
		_check(chip.text == chip_text,
			"the chip renders its full clip and sequence string")
		_check(not chip.clip_text,
			"the duration chip is not clipped")
		_check(chip.get_combined_minimum_size().x >= full_width,
			"the chip lays out the full sequence half (needs %.1f dp)" % full_width)
	_check(time_tl.has_method("duration_chip") and time_tl.has_method("open_duration_row"),
		"the chip is a tappable control")
	if time_tl.has_method("duration_chip") and time_tl.has_method("open_duration_row"):
		time_tl.duration_chip().pressed.emit()
		await get_tree().process_frame
		_check(time_tl.duration_row_visible(), "tapping the chip opens the duration row")
		_check(time_tl._duration_row.get_combined_minimum_size().y >= 44.0 - 0.5,
			"the duration row keeps a 44 dp target")
		_check(time_tl._duration_field.min_value <= 0.25 + 0.001
			and time_tl._duration_field.max_value >= 3599.0,
			"the duration field spans 0.25 to 3600 seconds")
		_check(time_tl._match_button.visible,
			"Match sequence appears while the sequence is longer")
		_check(time_tl._match_button.text == "Match sequence",
			"the match action uses the specified visible copy")
		_check(time_tl._extend_button.text == "Extend +1 s",
			"the extend action uses the specified visible copy")
		var keys_before_extend: int = doc.get_channel_keys(key_id, "position").size()
		var before_extend: float = doc.duration
		time_tl._extend_button.pressed.emit()
		await get_tree().process_frame
		_check(absf(doc.duration - (before_extend + 1.0)) < 0.01,
			"Extend +1 s grows the active clip")
		_check(doc.get_channel_keys(key_id, "position").size() == keys_before_extend,
			"extending the clip never deletes keys")
		# A shrink that would delete keys asks first and leaves the document
		# untouched until the editor's confirmation runs.
		var confirmations := [0]
		var confirmation_value := [0.0]
		time_tl.duration_confirmation_requested.connect(
			func(value: float, _message: String) -> void:
				confirmations[0] += 1
				confirmation_value[0] = value)
		var before_shrink: float = doc.duration
		var applied: bool = time_tl.request_duration(0.25)
		_check(not applied and confirmations[0] == 1,
			"a destructive shrink asks for confirmation before applying")
		_check(absf(confirmation_value[0] - 0.25) < 0.001,
			"the confirmation carries the requested duration")
		_check(absf(doc.duration - before_shrink) < 0.001,
			"the unconfirmed shrink leaves the clip duration alone")
		# The editor owns the confirmation surface. Dismiss it so the rest of
		# the smoke run continues with an unobstructed stage.
		_check(editor._overlay.has_modal(),
			"the shrink request opens the editor confirmation sheet")
		editor._overlay.close_modal()
		await get_tree().process_frame
		# Match sequence applies the longer sequence clock, and the clip can
		# then return to its original length without touching in-range keys.
		# Close and reopen first so this exercises the real reopen path instead
		# of toggling the still-open row closed.
		time_tl.close_duration_row()
		await get_tree().process_frame
		_check(not time_tl.duration_row_visible(),
			"the duration row closes before the reopen path")
		time_tl.open_duration_row()
		await get_tree().process_frame
		_check(time_tl.duration_row_visible(),
			"the duration row reopens for the match action")
		time_tl._match_button.pressed.emit()
		await get_tree().process_frame
		_check(absf(doc.duration - doc.sequence_duration()) < 0.01,
			"Match sequence sets the clip to the sequence length")
		time_tl.request_duration(duration)
		_check(absf(doc.duration - duration) < 0.01,
			"the clip duration returns to its original value")
		time_tl.close_duration_row()
		await get_tree().process_frame
	if long_strip != "":
		doc.animation_system.delete_strip(long_strip)
	if long_clip != "":
		doc.animation_system.delete_clip(long_clip)
	await get_tree().process_frame
	time_tl.set_time_view(duration * 0.1, duration * 0.7)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(absf(time_tl.time_view().x - duration * 0.1) < 0.01 and
		absf(time_tl.time_view().y - duration * 0.7) < 0.01,
		"the time view maps a real window")
	time_tl._geometry(sheet)
	_check(absf(time_tl._time_to_x(time_tl.time_view().x, sheet) - time_tl._grid_left) < 0.5,
		"the window start maps to the grid left edge")
	_check(absf(time_tl._time_to_x(time_tl.time_view().y, sheet) -
		(time_tl._grid_left + time_tl._grid_width)) < 0.5,
		"the window end maps to the grid right edge")
	var mid_time: float = (time_tl.time_view().x + time_tl.time_view().y) * 0.5
	var mapped_mid: float = time_tl._x_to_time(
		time_tl._grid_left + time_tl._grid_width * 0.5, sheet)
	_check(absf(mapped_mid - mid_time) < 0.01,
		"pointer mapping uses the same viewport as drawing")
	var track: Rect2 = time_tl.scrollbar_track_rect()
	_check(track.size.x > 0.0, "the scrollbar appears once the window is zoomed")
	_check(absf(time_tl.scrollbar_hit_rect().size.y - 44.0) < 0.5,
		"the scrollbar keeps a 44 dp hit band")
	var thumb: Rect2 = time_tl.scrollbar_thumb_rect()
	_check(thumb.size.x > 0.0 and thumb.size.x <= track.size.x,
		"the scrollbar thumb is a real handle")
	_check(thumb.size.y <= 6.5, "the painted scrollbar thumb stays slim")

	# Plain wheel zooms about the pointer; Shift+wheel pans.
	var span_before: float = time_tl.time_view().y - time_tl.time_view().x
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(time_tl._grid_left + time_tl._grid_width * 0.5, 40.0)
	time_tl._sheet_input(wheel, sheet)
	_check(time_tl.time_view().y - time_tl.time_view().x < span_before,
		"wheel up zooms into the window")
	var pan_before: float = time_tl.time_view().x
	var shift_wheel := InputEventMouseButton.new()
	shift_wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	shift_wheel.pressed = true
	shift_wheel.shift_pressed = true
	shift_wheel.position = Vector2(time_tl._grid_left + time_tl._grid_width * 0.5, 40.0)
	time_tl._sheet_input(shift_wheel, sheet)
	_check(time_tl.time_view().x > pan_before, "shift+wheel pans the window")
	_check(time_tl.scrollbar_caption() == "Drag to pan",
		"a zoomed window captions drag-to-pan")
	# M3: horizontal wheel buttons pan instead of falling through to a scrub.
	var wheel_pan_before: float = time_tl.time_view().x
	var time_before_wheel: float = doc.current_time
	var wheel_left := InputEventMouseButton.new()
	wheel_left.button_index = MOUSE_BUTTON_WHEEL_LEFT
	wheel_left.pressed = true
	wheel_left.position = Vector2(time_tl._grid_left + time_tl._grid_width * 0.5, 40.0)
	time_tl._sheet_input(wheel_left, sheet)
	var after_left: float = time_tl.time_view().x
	_check(after_left < wheel_pan_before,
		"wheel-left pans the time window backwards")
	_check(is_equal_approx(doc.current_time, time_before_wheel) and not time_tl._scrubbing,
		"wheel-left never starts a scrub")
	var wheel_right := InputEventMouseButton.new()
	wheel_right.button_index = MOUSE_BUTTON_WHEEL_RIGHT
	wheel_right.pressed = true
	wheel_right.position = wheel_left.position
	time_tl._sheet_input(wheel_right, sheet)
	_check(time_tl.time_view().x > after_left + 0.001,
		"wheel-right pans the time window forwards")

	# Dragging the scrollbar thumb pans the window.
	time_tl.set_time_view(duration * 0.1, duration * 0.4)
	await get_tree().process_frame
	thumb = time_tl.scrollbar_thumb_rect()
	track = time_tl.scrollbar_track_rect()
	var grab: Vector2 = thumb.position + thumb.size * 0.5
	var scroll_press := InputEventMouseButton.new()
	scroll_press.button_index = MOUSE_BUTTON_LEFT
	scroll_press.pressed = true
	scroll_press.position = grab
	time_tl._sheet_input(scroll_press, sheet)
	var drag_start: float = time_tl.time_view().x
	var scroll_drag := InputEventMouseMotion.new()
	scroll_drag.position = grab + Vector2(track.size.x * 0.35, 0.0)
	time_tl._sheet_input(scroll_drag, sheet)
	_check(time_tl.time_view().x > drag_start, "dragging the scrollbar pans the window")
	var scroll_release := InputEventMouseButton.new()
	scroll_release.button_index = MOUSE_BUTTON_LEFT
	scroll_release.pressed = false
	scroll_release.position = scroll_drag.position
	time_tl._sheet_input(scroll_release, sheet)
	_check(not time_tl._scroll_dragging, "the scrollbar releases cleanly")

	# Two-finger pan and pinch. The touches land on the ruler so the first
	# contact never starts a scrub or key drag.
	time_tl.set_time_view(duration * 0.1, duration * 0.4)
	await get_tree().process_frame
	var gesture_start: float = time_tl.time_view().x
	var touch_a := InputEventScreenTouch.new()
	touch_a.index = 0
	touch_a.pressed = true
	touch_a.position = Vector2(300, 5)
	time_tl._sheet_input(touch_a, sheet)
	var touch_b := InputEventScreenTouch.new()
	touch_b.index = 1
	touch_b.pressed = true
	touch_b.position = Vector2(400, 5)
	time_tl._sheet_input(touch_b, sheet)
	var drag_a := InputEventScreenDrag.new()
	drag_a.index = 0
	drag_a.position = Vector2(280, 5)
	time_tl._sheet_input(drag_a, sheet)
	var drag_b := InputEventScreenDrag.new()
	drag_b.index = 1
	drag_b.position = Vector2(380, 5)
	time_tl._sheet_input(drag_b, sheet)
	_check(time_tl.time_view().x > gesture_start, "two-finger drag pans the window")
	var pinch_before: float = time_tl.time_view().y - time_tl.time_view().x
	var pinch_a := InputEventScreenDrag.new()
	pinch_a.index = 0
	pinch_a.position = Vector2(250, 5)
	time_tl._sheet_input(pinch_a, sheet)
	var pinch_b := InputEventScreenDrag.new()
	pinch_b.index = 1
	pinch_b.position = Vector2(410, 5)
	time_tl._sheet_input(pinch_b, sheet)
	_check(time_tl.time_view().y - time_tl.time_view().x < pinch_before,
		"pinching apart zooms the window")
	for index in [0, 1]:
		var lift := InputEventScreenTouch.new()
		lift.index = index
		lift.pressed = false
		lift.position = Vector2(300, 5)
		time_tl._sheet_input(lift, sheet)
	_check(not time_tl._panning_view, "lifting both fingers ends the gesture")

	# I1: a two-finger gesture that starts on a key row must roll back the
	# seek, pause and key edit the first touch began. No key is retimed, no
	# undo entry is pushed and the document returns to its snapshot.
	time_tl.set_time_view(duration * 0.1, duration * 0.6)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(doc.has_method("has_open_edit"), "the document reports a pending edit")
	doc.seek(duration * 0.3)
	doc.pause()
	var undo_before: int = doc._undo_stack.size()
	var position_keys: Array = doc.get_channel_keys(key_id, "position")
	var gesture_key_index := -1
	var key_time_before := 0.0
	for ki in range(position_keys.size()):
		var candidate := float(position_keys[ki]["time"])
		if candidate > time_tl.time_view().x + 0.05 and candidate < time_tl.time_view().y - 0.05:
			gesture_key_index = ki
			key_time_before = candidate
			break
	_check(gesture_key_index >= 0, "the key-row gesture has a visible position key")
	if gesture_key_index >= 0:
		var key_x: float = time_tl._time_to_x(key_time_before, sheet)
		var key_y: float = time_tl._ruler_h + time_tl._row_h * 0.5
		var time_snapshot: float = doc.current_time
		var key_touch_a := InputEventScreenTouch.new()
		key_touch_a.index = 0
		key_touch_a.pressed = true
		key_touch_a.position = Vector2(key_x, key_y)
		time_tl._sheet_input(key_touch_a, sheet)
		_check(time_tl._dragging_key and doc.has_open_edit(),
			"the first touch on a key row starts the normal retime edit")
		var key_touch_b := InputEventScreenTouch.new()
		key_touch_b.index = 1
		key_touch_b.pressed = true
		key_touch_b.position = Vector2(key_x + 120.0, key_y)
		time_tl._sheet_input(key_touch_b, sheet)
		_check(not time_tl._dragging_key and not doc.has_open_edit(),
			"the second touch cancels the pending key edit")
		_check(absf(doc.current_time - time_snapshot) < 0.001 and not doc.is_playing,
			"the second touch restores the paused snapshot time")
		_check(doc._undo_stack.size() == undo_before,
			"the cancelled gesture pushes no undo entry")
		var restored_keys: Array = doc.get_channel_keys(key_id, "position")
		_check(restored_keys.size() == position_keys.size() and
			absf(float(restored_keys[gesture_key_index]["time"]) - key_time_before) < 0.001,
			"the key keeps its time through the cancelled gesture")
		var view_before_key_gesture: float = time_tl.time_view().x
		var key_drag_a := InputEventScreenDrag.new()
		key_drag_a.index = 0
		key_drag_a.position = Vector2(key_x - 20.0, key_y)
		time_tl._sheet_input(key_drag_a, sheet)
		var key_drag_b := InputEventScreenDrag.new()
		key_drag_b.index = 1
		key_drag_b.position = Vector2(key_x + 100.0, key_y)
		time_tl._sheet_input(key_drag_b, sheet)
		_check(time_tl.time_view().x > view_before_key_gesture,
			"the key-row gesture still pans the view window")
		_check(doc._undo_stack.size() == undo_before and not doc.has_open_edit(),
			"panning after the cancel leaves no edit behind")
		for index in [0, 1]:
			var lift_key := InputEventScreenTouch.new()
			lift_key.index = index
			lift_key.pressed = false
			lift_key.position = Vector2(key_x, key_y)
			time_tl._sheet_input(lift_key, sheet)

	# A playing snapshot resumes after the second touch; a paused snapshot
	# stays paused. This is the same gesture path, starting on the ruler.
	doc.seek(duration * 0.2)
	doc.play()
	var playing_snapshot: bool = doc.is_playing
	var play_time_snapshot: float = doc.current_time
	var play_touch_a := InputEventScreenTouch.new()
	play_touch_a.index = 0
	play_touch_a.pressed = true
	play_touch_a.position = Vector2(320, 5)
	time_tl._sheet_input(play_touch_a, sheet)
	_check(not doc.is_playing, "the first touch pauses playback for the gesture")
	var play_touch_b := InputEventScreenTouch.new()
	play_touch_b.index = 1
	play_touch_b.pressed = true
	play_touch_b.position = Vector2(420, 5)
	time_tl._sheet_input(play_touch_b, sheet)
	_check(playing_snapshot and doc.is_playing,
		"the second touch resumes playback that was running before the gesture")
	_check(absf(doc.current_time - play_time_snapshot) < 0.12,
		"the resumed gesture restores the snapshot playhead")
	for index in [0, 1]:
		var lift_play := InputEventScreenTouch.new()
		lift_play.index = index
		lift_play.pressed = false
		lift_play.position = Vector2(320, 5)
		time_tl._sheet_input(lift_play, sheet)
	doc.pause()

	# Ruler scrub and key retime still hit-test through the zoomed viewport.
	time_tl.set_time_view(duration * 0.1, duration * 0.7)
	await get_tree().process_frame
	await get_tree().process_frame
	var scrub_x: float = time_tl._grid_left + time_tl._grid_width * 0.75
	var scrub_press := InputEventMouseButton.new()
	scrub_press.button_index = MOUSE_BUTTON_LEFT
	scrub_press.pressed = true
	scrub_press.position = Vector2(scrub_x, 5.0)
	time_tl._sheet_input(scrub_press, sheet)
	var scrub_release := InputEventMouseButton.new()
	scrub_release.button_index = MOUSE_BUTTON_LEFT
	scrub_release.pressed = false
	scrub_release.position = scrub_press.position
	time_tl._sheet_input(scrub_release, sheet)
	_check(absf(doc.current_time - time_tl._x_to_time(scrub_x, sheet)) < 0.05,
		"ruler scrub maps through the zoomed viewport")
	var key_hit := -1
	for i in range(time_tl._key_hits.size()):
		var entry: Dictionary = time_tl._key_hits[i]
		var point: Vector2 = entry["pos"]
		if str(entry["channel"]) == "position" and point.x > time_tl._grid_left + 8.0 and \
			point.x < time_tl._grid_left + time_tl._grid_width - 20.0:
			key_hit = i
			break
	_check(key_hit >= 0, "a position diamond is visible inside the zoomed window")
	if key_hit >= 0:
		var hit: Dictionary = time_tl._key_hits[key_hit]
		var key_pos: Vector2 = hit["pos"]
		var from_time: float = time_tl._x_to_time(key_pos.x, sheet)
		var key_press := InputEventMouseButton.new()
		key_press.button_index = MOUSE_BUTTON_LEFT
		key_press.pressed = true
		key_press.position = key_pos
		time_tl._sheet_input(key_press, sheet)
		var to_time: float = from_time + (time_tl.time_view().y - time_tl.time_view().x) * 0.08
		var key_drag := InputEventMouseMotion.new()
		key_drag.position = Vector2(time_tl._time_to_x(to_time, sheet), key_pos.y)
		time_tl._sheet_input(key_drag, sheet)
		var key_release := InputEventMouseButton.new()
		key_release.button_index = MOUSE_BUTTON_LEFT
		key_release.pressed = false
		key_release.position = key_drag.position
		time_tl._sheet_input(key_release, sheet)
		_check(doc.get_key_index_at(key_id, "position", to_time, 0.08) >= 0,
			"dragging a key retimes it through the zoomed viewport")
		doc.undo()
		await get_tree().process_frame
		_check(doc.get_key_index_at(key_id, "position", from_time, 0.08) >= 0,
			"undo restores the retimed key")
	time_tl.set_time_view(0.0, duration)
	doc.seek(0.0)
	await get_tree().process_frame

	editor._timeline.set_mode("dope")
	editor._timeline.set_sheet_visible(false)
	for _i in 3:
		await get_tree().process_frame
	_check(not editor._timeline.sheet_visible(), "the folded pane keeps only the transport")
	_check(is_equal_approx(editor._view.size.x, animate_view_before.x) and
		is_equal_approx(editor._view.size.y, animate_view_before.y),
		"folding the pane leaves the 3D view untouched")
	editor.set_workspace("scene")
	await get_tree().process_frame

	print("SMOKE STEP: media records")
	var audio_source := "user://smoke_footsteps.wav"
	_write_smoke_wav(audio_source)
	var imported_audio: Dictionary = doc.media_system.import_audio(audio_source)
	_check(bool(imported_audio.get("ok", false)), "WAV import succeeds")
	var audio_rel := str(imported_audio.get("rel_path", ""))
	_check(audio_rel.begins_with("audio/"), "WAV is copied into the project audio folder")
	var track_id: String = doc.media_system.add_audio_track(audio_rel, 2.0)
	_check(track_id != "", "the imported WAV becomes a real audio track")
	var audio_record: Dictionary = doc.media_system.audio_track(track_id)
	_check(str(audio_record.get("file", "")) == audio_rel, "the audio record stores its copied file")
	_check(is_equal_approx(float(audio_record.get("start", 0.0)), 2.0),
		"the audio record stores its sequence start")
	doc.media_system.update_audio_track(track_id, {"volume": 0.25, "muted": true})
	audio_record = doc.media_system.audio_track(track_id)
	_check(is_equal_approx(float(audio_record.get("volume", 1.0)), 0.25) and bool(audio_record.get("muted", false)),
		"the audio track records volume and mute edits")
	doc.media_system.delete_audio_track(track_id)
	_check(doc.media_system.audio_track(track_id).is_empty(),
		"deleting the audio track clears the record")

	var video_source := "user://smoke_reference.ogv"
	var video_file := FileAccess.open(video_source, FileAccess.WRITE)
	video_file.store_buffer(PackedByteArray([0x4f, 0x67, 0x67, 0x53]))
	video_file.close()
	var imported_video: Dictionary = doc.media_system.import_video_reference(video_source)
	_check(bool(imported_video.get("ok", false)), "an OGV video reference imports")
	var video_refs: Array = doc.media_system.video_references()
	_check(video_refs.size() == 1, "the video reference is recorded")
	if not video_refs.is_empty():
		var video_id := str((video_refs[0] as Dictionary).get("id", ""))
		_check(video_id != "", "the video reference has an id")
		doc.media_system.update_video_reference(video_id, {"opacity": 0.5})
		var video_record: Dictionary = doc.media_system.video_reference(video_id)
		_check(is_equal_approx(float(video_record.get("opacity", 1.0)), 0.5),
			"the video reference records its opacity edit")
		doc.media_system.delete_video_reference(video_id)
		_check(doc.media_system.video_references().is_empty(),
			"deleting the video reference clears the record")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(audio_source))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(video_source))

	print("SMOKE STEP: editor type and touch floor")
	await _resize_shell(main, editor, Vector2(412.0, 915.0))
	editor.set_layout_mode("studio")
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
	await _resize_shell(main, editor, Vector2(915.0, 412.0))
	editor.set_layout_mode("studio")
	await get_tree().process_frame
	_check(editor._short, "915x412 resolves as a short landscape shell")
	_check(editor._workspace_bar.size.y >= 43.5, "landscape top bar is 44 dp")
	_check(editor._context_bar.size.y >= 43.5, "landscape context row is 44 dp")
	_check(editor._transport_bar.visible, "Scene keeps the shared transport in landscape")
	_check(editor._stage_host.size.y >= 96.0, "landscape keeps a usable stage")
	editor.set_workspace("animate")
	for _i in 2:
		await get_tree().process_frame
	_check(editor._animate_pane.visible, "landscape Animate opens the pane")
	_check(editor._animate_pane.size.y >= 120.0, "landscape gives the pane a real share")
	_check(editor._timeline.size.x <= editor._animate_pane.size.x + 1.0,
		"the landscape timeline fits the pane")
	# A hidden sheet keeps the size it had before the resize, so its cached plot
	# rect would be a stale measurement from the previous shell. Open it first.
	editor._timeline.set_sheet_visible(true)
	editor._timeline.set_mode("graph")
	for _i in 3:
		await get_tree().process_frame
	_check(editor._timeline.sheet_visible(), "the landscape graph opens the sheet")
	_check(editor._timeline.graph_plot_rect().size.y < 120.0,
		"the short landscape pane reports a short graph plot")
	_check(editor._timeline.graph_caption() == "Rotate upright for more curve-editing space",
		"the short graph states the honest rotation caption")
	editor._timeline.set_mode("dope")
	editor.set_workspace("scene")
	await get_tree().process_frame
	await _resize_shell(main, editor, Vector2(412.0, 915.0))
	_check(not editor._short, "412x915 resolves as a tall studio shell")
	_check(editor._workspace_bar.size.y >= 43.5, "the tall phone keeps a 44 dp top bar")

	print("SMOKE STEP: narrow studio drawer")
	await _resize_shell(main, editor, Vector2(412.0, 915.0))
	editor.set_layout_mode("studio")
	editor.set_workspace("scene")
	await get_tree().process_frame
	_check(editor._workspace_panel.mode() == WorkspacePanelScript.Mode.HIDDEN,
		"the narrow shell starts with no reserved panel")
	_check(editor._panel_spacer.custom_minimum_size.x <= 0.5,
		"the narrow shell reserves no panel width")
	_check(editor._stage_host.size.x >= 300.0, "narrow studio stage keeps a usable width")
	var view_rect: Rect2 = editor._view.get_global_rect()
	var hud_rect: Rect2 = editor._view._quick_render_button.get_global_rect()
	_check(view_rect.encloses(hud_rect), "narrow studio HUD stays inside the viewport")
	editor._toggle_scene_panel("scene")
	for _i in 4:
		await get_tree().process_frame
	_check(editor._workspace_panel.mode() == WorkspacePanelScript.Mode.OVERLAY,
		"the narrow scene panel opens as an overlay")
	_check(editor._workspace_panel.scrim().visible, "the narrow overlay has a scrim")
	_check(editor._workspace_panel.content() == editor._outliner_panel,
		"the narrow overlay shows the one outliner")
	editor._toggle_scene_panel("inspector")
	for _i in 2:
		await get_tree().process_frame
	_check(editor._workspace_panel.content() == editor._inspector_panel,
		"the narrow overlay swaps to Properties")
	editor._workspace_panel.close_button().pressed.emit()
	await get_tree().process_frame
	_check(editor._workspace_panel.mode() == WorkspacePanelScript.Mode.HIDDEN,
		"closing the narrow overlay returns the stage")

	print("SMOKE STEP: timeline fold control")
	editor.set_layout_mode("studio")
	editor.set_workspace("animate")
	for _i in 2:
		await get_tree().process_frame
	editor._timeline.set_sheet_visible(true)
	await get_tree().process_frame
	_check(editor._timeline._fold_button != null, "timeline exposes a fold control")
	if editor._timeline._fold_button != null:
		_check(editor._timeline._fold_button.custom_minimum_size.y >= 44.0,
			"timeline fold control keeps a 44 dp target")
		editor._timeline._fold_button.pressed.emit()
		await get_tree().process_frame
		_check(not editor._timeline.sheet_visible(), "timeline fold control folds the sheet")
		editor._timeline._fold_button.pressed.emit()
		await get_tree().process_frame
		_check(editor._timeline.sheet_visible(), "timeline fold control reopens the sheet")
	editor._timeline.set_sheet_visible(false)
	editor.set_workspace("scene")
	await get_tree().process_frame

	print("SMOKE STEP: sequence shell wiring")
	await _resize_shell(main, editor, Vector2(412.0, 915.0))
	editor.set_layout_mode("studio")
	editor.set_workspace("scene")
	for _i in 2:
		await get_tree().process_frame
	var tl_play: Button = editor._timeline._play_button
	_check(tl_play != null, "the dope sheet keeps a clip transport")
	doc.seek(1.0)
	doc.play_sequence()
	_check(doc.is_sequence_playing(), "the document runs the sequence clock")
	_check(not doc.is_playing, "the sequence does not run both clocks")
	_check(tl_play.disabled, "timeline clip transport is disabled while the sequence plays")
	_check(editor._timeline.has_method("set_clip_transport_enabled"),
		"the timeline owns the clip transport state")
	_check(tl_play.tooltip_text == "Stop the sequence first",
		"the timeline owns the disabled transport reason")
	var sequence_time_before: float = doc.current_time
	# Wait a fixed slice instead of two raw frames: format_timecode is
	# frame-quantized, so two uncapped headless frames can land inside the
	# same frame and make the label comparison flake.
	await get_tree().create_timer(0.2).timeout
	_check(doc.is_sequence_playing() and doc.current_time > sequence_time_before + 0.05,
		"the sequence clock advances while it plays")
	_check(editor._timeline._time_label.text == doc.format_timecode(doc.current_time),
		"the timeline follows the advancing sequence time")
	_check(editor._timeline._time_label.text != doc.format_timecode(sequence_time_before),
		"the timeline label moved with the sequence")
	doc.pause_sequence()
	_check(not doc.is_sequence_playing(), "pause_sequence stops the sequence clock")
	_check(is_equal_approx(doc.current_time, 1.0),
		"pausing the sequence restores the saved clip time")
	doc.seek(1.0)
	doc.play_sequence()
	doc.stop_sequence()
	_check(not doc.is_sequence_playing(), "stop_sequence stops the sequence clock")
	_check(is_equal_approx(doc.current_time, 1.0),
		"stopping the sequence restores the saved clip time")
	doc.seek(1.0)
	doc.play_sequence()
	_check(doc.is_sequence_playing(), "the sequence restarts")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	editor._unhandled_key_input(space)
	_check(not doc.is_sequence_playing(), "space pauses the sequence clock")
	_check(is_equal_approx(doc.current_time, 1.0), "space restores the saved clip time")
	tl_play.pressed.emit()
	_check(doc.is_playing and not doc.is_sequence_playing(),
		"the timeline transport plays the clip clock")
	_check(not tl_play.disabled,
		"timeline clip transport re-enables when the sequence stops")
	doc.pause()
	doc.seek(0.0)
	await get_tree().process_frame

	var rig_panel = editor._rig_panel
	var rig_overlay = editor._rig_overlay
	_check(rig_panel != null, "the Rig panel is mounted")
	_check(rig_overlay != null, "the rig overlay floats over the viewport")
	await _resize_shell(main, editor, Vector2(915.0, 412.0))
	editor.set_workspace("rig")
	for _i in 2:
		await get_tree().process_frame
	_check(editor.workspace() == "rig", "the Rig workspace activates")
	_check(editor._workspace_panel.mode() == WorkspacePanelScript.Mode.RESERVED,
		"the Rig workspace reserves its panel at 915 dp")
	_check(editor._workspace_panel.content() == rig_panel,
		"the reserved panel owns the one rig frame")
	_check(editor._panel_spacer.custom_minimum_size.x >= 280.0,
		"the reserved panel takes its clamped 34 percent width")
	var rig_id: String = doc.rig_system.create_rig("Smoke Rig", Vector3.ZERO)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(rig_id != "" and not rig_panel.empty_state_visible(),
		"creating a rig clears the empty state")
	var pose_button: Button = editor._context_bar.action_button("pose")
	_check(pose_button != null and not pose_button.disabled,
		"the Rig context row enables Pose with a rig")
	if pose_button != null:
		pose_button.pressed.emit()
		await get_tree().process_frame
		_check(editor._rig_mode, "the Rig context row engages rig mode")
		_check(rig_overlay != null and rig_overlay.is_enabled(),
			"the Rig context row enables the rig overlay")
		_check(rig_overlay.mode() == "pose", "Pose selects the rig pose mode")
		editor._context_bar.action_button("rig_done").pressed.emit()
		await get_tree().process_frame
		_check(not editor._rig_mode, "Done leaves rig mode")
		_check(not rig_overlay.is_enabled(), "Done hides the rig overlay")
	doc.rig_system.delete_rig(rig_id)
	await get_tree().process_frame
	_check(rig_panel.empty_state_visible(), "deleting the rig restores the empty state")
	if rig_overlay != null:
		_check(str(rig_overlay._rig_id) == "", "the rig overlay clears with the last rig")
		_check(not rig_overlay.is_enabled(), "deleting the last rig disables the overlay")
	editor.set_workspace("scene")
	await get_tree().process_frame
	await get_tree().process_frame

	var video_overlay = editor.get("_video_overlay")
	_check(video_overlay != null, "a video reference overlay sits behind the HUD")
	if video_overlay != null:
		_check(video_overlay.get_parent() == editor._view, "the video overlay lives on the viewport")
		var view_kids: Array = editor._view.get_children()
		_check(view_kids[view_kids.size() - 1] == editor._view._hud_root,
			"the HUD stays the top viewport layer")
		_check(view_kids.find(video_overlay) < view_kids.find(editor._view._hud_root),
			"the video overlay draws below the HUD")
		_check(view_kids.find(video_overlay) > view_kids.find(editor._view._surface),
			"the video overlay draws over the 3D surface")
		_check(video_overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"the video overlay ignores every pointer")
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

	# The context row is the view's control surface: View and Grid must reach
	# the real view, not a duplicate control.
	editor._open_view_menu(editor._context_bar.action_button("view"))
	await get_tree().process_frame
	_check(editor._view_menu.is_open(), "the context row opens the view menu")
	var prior_view: String = editor._view.view_preset()
	if editor._view_menu.row_button("Front") != null:
		editor._view_menu.row_button("Front").pressed.emit()
		_check(editor._view.view_preset() == "Front", "the view menu drives the view")
		editor._view.set_view_preset(prior_view)
	var prior_grid: bool = editor._view.grid_enabled()
	editor._context_bar.action_button("grid").pressed.emit()
	_check(editor._view.grid_enabled() == (not prior_grid),
		"the context grid action drives the view")
	editor._context_bar.action_button("grid").pressed.emit()
	_check(editor._view.grid_enabled() == prior_grid, "the grid action toggles back")
	editor._context_bar.action_button("add").pressed.emit()
	await get_tree().process_frame
	_check(editor._overlay.has_modal(), "the context Add action opens the add sheet")
	editor._overlay.close_modal()
	await get_tree().process_frame

	if editor._workspace_panel.mode() == WorkspacePanelScript.Mode.OVERLAY:
		editor._close_workspace_panel()
	# Render preview is a clip-clock surface: a running sequence must stop
	# first, and its saved clip playhead must survive the round trip.
	doc.seek(1.0)
	doc.play_sequence()
	_check(doc.is_sequence_playing(), "the sequence can run before render preview")
	editor._enter_render_mode()
	_check(editor._render_mode, "render preview engages")
	_check(not doc.is_sequence_playing(), "render preview stops the sequence clock")
	_check(doc.is_playing, "render preview plays the clip clock")
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

	editor.set_workspace("render")
	await get_tree().process_frame
	var media_export = editor.get("_media_export")
	_check(editor._render_panel != null, "the Render workspace panel is mounted")
	_check(editor._render_panel.media_sheet() == media_export,
		"the Render workspace embeds the media export sheet")
	_check(not editor._overlay.has_modal(), "the Render workspace stays out of the modal overlay")

	print("SMOKE STEP: camera track export")
	# The camera exporter can only sample a real scene camera. The sheet must
	# expose the format, select that camera, and build the camera options the
	# editor routes to CameraExport.
	var _camera_added: String = doc.add_camera(Vector3(1.0, 2.0, 3.0))
	var camera_sheet = editor.get("_media_export")
	_check(camera_sheet != null and camera_sheet.has_method("camera_available"),
		"the media export sheet exposes a camera format")
	if camera_sheet != null and camera_sheet.has_method("camera_available"):
		camera_sheet.setup(doc, editor._view)
		_check(camera_sheet.format_ids().has("camera"), "the media export sheet offers a camera track")
		_check(camera_sheet.camera_available(), "a scene camera enables the camera export")
		camera_sheet.set_format("camera")
		var camera_options: Dictionary = camera_sheet.build_options()
		_check(str(camera_options.get("format", "")) == "camera", "camera export builds camera options")
		var exported_camera := str(camera_options.get("camera_id", ""))
		var exported_camera_obj: Dictionary = doc.get_object(exported_camera)
		_check(exported_camera != "" and str(exported_camera_obj.get("kind", "")) == "camera",
			"camera export targets a real scene camera")
		_check(str(camera_options.get("output_path", "")).ends_with(".json"), "camera export writes a JSON track")
		camera_sheet.set_format("png")
	doc.set_selection("")

	editor.set_workspace("animate")
	await get_tree().process_frame
	await get_tree().process_frame
	editor._timeline.set_sheet_visible(false)
	await get_tree().process_frame

	print("SMOKE STEP: graph fold contract")
	editor._timeline.set_mode("graph")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not editor._timeline.sheet_visible(), "graph mode does not reopen a folded sheet")
	_check(editor._timeline.transport_panel().is_visible_in_tree(),
		"folded graph keeps the transport reachable")
	_check(not editor._timeline._sheet.visible, "folded graph hides the sheet body")
	editor._timeline.set_sheet_visible(true)
	editor._timeline.set_mode("dope")
	await get_tree().process_frame

	print("SMOKE STEP: collapsible panels")
	await _resize_shell(main, editor, Vector2(412.0, 915.0))
	editor.set_workspace("scene")
	editor._toggle_scene_panel("scene")
	for _i in 2:
		await get_tree().process_frame
	editor._set_section_collapsed("outliner", true)
	await get_tree().process_frame
	_check(editor._outliner.collapsed, "outliner collapses")
	_check(not editor._outliner._scroll.visible, "collapsed outliner hides its list")
	_check(editor._outliner_panel.custom_minimum_size.y <= 48.0,
		"collapsed outliner keeps a 44 dp header")
	_check("outliner" in Prefs.get_value("editor.collapsed_sections", []),
		"outliner collapse persists")
	editor._set_section_collapsed("inspector", true)
	await get_tree().process_frame
	_check(editor._inspector.collapsed, "inspector collapses")
	_check(not editor._inspector._scroll.visible, "collapsed inspector hides its fields")
	_check(editor._inspector_panel.custom_minimum_size.y <= 48.0,
		"collapsed inspector keeps a 44 dp header")
	editor._set_section_collapsed("outliner", false)
	editor._set_section_collapsed("inspector", false)
	await get_tree().process_frame
	_check(not editor._outliner.collapsed and not editor._inspector.collapsed,
		"panels expand again")

	print("SMOKE STEP: graph editor")
	var timeline = editor._timeline
	_check(timeline != null, "timeline exists")
	if timeline != null:
		editor.set_workspace("animate")
		await get_tree().process_frame
		await get_tree().process_frame
		timeline.set_sheet_visible(true)
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
			_check(is_equal_approx(doc.get_key_transition(key_id, "position", 0), 4.0),
				"channel transition clamps high")
			doc.set_channel_transition(key_id, "position", -1.0)
			_check(is_equal_approx(doc.get_key_transition(key_id, "position", 0), 0.0),
				"channel transition clamps low")
			doc.set_channel_transition(key_id, "position", 1.0)

		timeline.set_mode("graph")
		_check(timeline.mode() == "graph", "graph mode activates")
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
		var graph_panel_height: float = timeline.size.y
		_check(graph_panel_height > 180.0, "the Animate pane gives the graph a real height")
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
		await _resize_shell(main, editor, Vector2(915.0, 412.0))
		editor.set_layout_mode("studio")
		editor.set_workspace("animate")
		timeline.set_sheet_visible(true)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(timeline.get("_short_layout") == true, "timeline tracks the short landscape layout")
		_check(editor._stage_host.size.y >= 96.0, "915x412 graph keeps a usable viewport")
		_check(timeline.graph_plot_rect().size.y < 120.0,
			"the 915x412 split reports a short graph plot")
		_check(timeline.graph_caption() == "Rotate upright for more curve-editing space",
			"915x412 graph states the honest rotation caption")
		await _resize_shell(main, editor, Vector2(800.0, 360.0))
		editor.set_layout_mode("studio")
		editor.set_workspace("animate")
		timeline.set_sheet_visible(true)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(editor._stage_host.size.y >= 96.0, "800x360 graph keeps a usable viewport")
		_check(timeline.graph_plot_rect().size.y < 120.0,
			"800x360 graph reports a short plot")
		_check(timeline.graph_caption() == "Rotate upright for more curve-editing space",
			"800x360 graph states the honest rotation caption")
		await _resize_shell(main, editor, Vector2(412.0, 915.0))
		editor.set_layout_mode("studio")
		editor.set_workspace("animate")
		timeline.set_sheet_visible(true)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(timeline.graph_plot_rect().size.y >= 120.0,
			"the tall pane keeps the 120 dp graph plot floor")

		timeline.set_mode("dope")
		await get_tree().process_frame
		_check(timeline.mode() == "dope", "dope mode restores")
		_check(timeline.size.y <= graph_panel_height + 0.5,
			"dope mode stays inside the graph's pane height")
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

	print("SMOKE STEP: render workspace")
	editor.set_workspace("render")
	for _i in 4:
		await get_tree().process_frame
	_check(editor._render_panel != null and editor._render_panel.active_tab() == "render",
		"the Render workspace opens on its output tab")
	_check(editor._render_panel.media_sheet().format_ids().has("png"),
		"the embedded media sheet keeps PNG")
	_check(editor._render_panel.media_sheet().status_text() == "",
		"the render workspace starts with no error status")
	_check(editor._sequence_frame_count() == 144, "sequence frame count follows duration and fps")
	_check(not editor._render_busy, "the render workspace is idle on open")

	print("SMOKE STEP: export error reporting")
	media_export = editor.get("_media_export")
	_check(media_export != null and media_export.has_method("status_text"),
		"the media export sheet exposes its status line")
	if media_export != null and media_export.has_method("status_text"):
		editor._export_failed("Fixture export failure")
		_check(media_export.status_text() == "Fixture export failure",
			"export errors live in the status line")
		_check(media_export.result_text() == "", "export errors are not result metadata")

	print("SMOKE STEP: export output directories")
	# Headless cannot wait for frame_post_draw, so exercise the writer seam
	# directly: the GIF writer must create a missing parent directory, and the
	# MP4 handoff must ensure its output folder exists.
	var gif_output := "user://export_dir_fixture/nested/kinema.gif"
	var stale_dir := "user://export_dir_fixture"
	if DirAccess.dir_exists_absolute(stale_dir):
		_remove_tree(stale_dir)
	_check(editor.has_method("_write_gif_file"), "the editor exposes the GIF writer seam")
	if editor.has_method("_write_gif_file"):
		var gif_bytes := PackedByteArray([71, 73, 70, 56, 57, 97])
		_check(editor._write_gif_file(gif_output, gif_bytes), "the GIF writer creates a missing output directory")
		_check(FileAccess.file_exists(gif_output), "the GIF lands below the created directory")
		var mp4_output := "user://export_dir_fixture/mp4/nested/kinema.mp4"
		if editor.has_method("_ensure_output_dir"):
			_check(editor._ensure_output_dir(mp4_output), "the MP4 output directory can be created")
			_check(DirAccess.dir_exists_absolute(mp4_output.get_base_dir()), "the MP4 parent directory exists")
		else:
			_check(false, "the editor exposes an output directory helper")
	_remove_tree(stale_dir)
	editor._overlay.close_modal()
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

	# Wave-2 renderer contract: Forward+ is selectable on Android/iOS as an
	# experimental backend with a mobile-safe profile and a one-failed-boot
	# fallback. The old "Forward+ is desktop-only" gate is obsolete.
	var android_renderers := Gfx.supported_renderers("Android")
	_check(android_renderers.size() == 3, "Android supports exactly three renderers")
	_check(android_renderers.has("forward_plus"), "Android capability list includes Forward+")
	_check(android_renderers.has("mobile"), "Android capability list includes Mobile")
	_check(android_renderers.has("gl_compatibility"), "Android capability list includes Compatibility")
	_check(Gfx.is_renderer_supported("forward_plus", "Android"), "Forward+ is supported on Android")
	_check(Gfx.renderer_unavailable_reason("forward_plus", "Android") == "", "Forward+ has no unavailable reason on Android")
	_check(Gfx.renderer_unavailable_reason("forward_plus", "iOS") == "", "Forward+ has no unavailable reason on iOS")
	_check(Gfx.supported_renderers("Linux").size() == 3, "desktop capability list includes every renderer")
	_check(Gfx.is_renderer_supported("forward_plus", "Linux"), "Forward+ is supported on desktop")

	var android_entries: Array = Gfx.renderer_entries("Android")
	_check(android_entries.size() == 3, "Android renderer entries list every renderer")
	var android_forward: Dictionary = {}
	var android_all_supported := true
	for entry in android_entries:
		var data: Dictionary = entry
		if str(data.get("value", "")) == "forward_plus":
			android_forward = data
		if not bool(data.get("supported", false)):
			android_all_supported = false
	_check(android_all_supported, "every Android renderer entry is supported")
	_check(str(android_forward.get("label", "")) == "Forward+ (Experimental)", "Android Forward+ is labelled Experimental")
	_check(bool(android_forward.get("experimental", false)), "Android Forward+ entry is marked experimental")
	_check(str(android_forward.get("note", "")) == "Experimental on Android: high-end Forward+ effects are clamped for stability.", "Android Forward+ note is exact")
	var ios_forward_note := ""
	for entry in Gfx.renderer_entries("iOS"):
		var data: Dictionary = entry
		if str(data.get("value", "")) == "forward_plus":
			ios_forward_note = str(data.get("note", ""))
	_check(ios_forward_note == "Experimental on iOS: high-end Forward+ effects are clamped for stability.", "iOS Forward+ note names the platform")
	var linux_forward: Dictionary = {}
	var linux_mobile: Dictionary = {}
	var linux_all_supported := true
	for entry in Gfx.renderer_entries("Linux"):
		var data: Dictionary = entry
		if str(data.get("value", "")) == "forward_plus":
			linux_forward = data
		if str(data.get("value", "")) == "mobile":
			linux_mobile = data
		if not bool(data.get("supported", false)):
			linux_all_supported = false
	_check(linux_all_supported, "desktop renderer entries are all supported")
	_check(not bool(linux_forward.get("experimental", true)) and str(linux_forward.get("note", "missing")) == "", "desktop Forward+ is not experimental and has no note")
	_check(not bool(linux_mobile.get("experimental", true)) and str(linux_mobile.get("note", "missing")) == "", "desktop Mobile is not experimental and has no note")

	# Exact restart arguments: Forward+ on Android is a real Vulkan launch.
	var forward_android_args := Gfx.build_restart_args("forward_plus", "Android")
	_check(forward_android_args == PackedStringArray(["--rendering-method", "forward_plus", "--rendering-driver", "vulkan"]), "Forward+ restart args are exact on Android")
	var mobile_android_args := Gfx.build_restart_args("mobile", "Android")
	_check(mobile_android_args == PackedStringArray(["--rendering-method", "mobile", "--rendering-driver", "vulkan"]), "Mobile restart args are exact on Android")
	_check(Gfx.build_restart_args("vulkan", "Android").is_empty(), "an unknown renderer has no restart args")

	# Sanitising: a Forward+ preference is legal on Android, an empty preference
	# is unset (not an error), and a stale unsupported method still repairs.
	var sanitized_state: Dictionary = Gfx.sanitize_renderer_state("forward_plus", "forward_plus", "Android")
	_check(str(sanitized_state["preference"]) == "forward_plus", "Forward+ preference survives on Android")
	_check(str(sanitized_state["pending"]) == "forward_plus", "Forward+ pending survives on Android")
	_check(not bool(sanitized_state["changed"]), "Forward+ state is not repaired on Android")
	_check(str(sanitized_state["reason"]) == "", "Forward+ state has no error on Android")
	var empty_state: Dictionary = Gfx.sanitize_renderer_state("", "", "Android")
	_check(str(empty_state["preference"]) == "mobile", "an empty preference maps to the platform default")
	_check(not bool(empty_state["changed"]), "an empty preference is unset, not an error")
	_check(str(empty_state["reason"]) == "", "an empty preference writes no error")
	var stale_state: Dictionary = Gfx.sanitize_renderer_state("vulkan", "vulkan", "Android")
	_check(str(stale_state["preference"]) == "mobile" and bool(stale_state["changed"]) and str(stale_state["reason"]) != "", "a stale unsupported renderer still repairs")

	# prepare_renderer_switch mutates the autoload state; restore it afterwards
	# so the live settings/renderer paths later in the suite see real state.
	var saved_preference: String = Gfx.renderer_preference
	var saved_pending: String = Gfx.renderer_pending
	var saved_attempts: int = Gfx.renderer_attempts
	var saved_attempt_at: float = Gfx.renderer_attempt_at
	var saved_ready: bool = Gfx.renderer_ready
	var saved_error: String = Gfx.last_renderer_error
	var saved_choice: String = Gfx.renderer_choice
	var prepared: Dictionary = Gfx.prepare_renderer_switch("forward_plus", "Android")
	_check(bool(prepared["restart_required"]), "Forward+ requests a restart on Android")
	_check(not bool(prepared["blocked"]), "Forward+ is not blocked on Android")
	_check(Gfx.renderer_pending == "forward_plus", "Forward+ is stored as the pending renderer")
	_check(prepared["args"] == PackedStringArray(["--rendering-method", "forward_plus", "--rendering-driver", "vulkan"]), "the prepared Forward+ restart carries the exact args")
	_check(not Gfx.renderer_ready, "a renderer switch clears renderer_ready before the restart")

	# One-failed-boot fallback and the normal retry path.
	var booted: Dictionary = Gfx.resolve_startup_renderer("forward_plus", "forward_plus", "forward_plus", 0, "Android", false)
	_check(str(booted["action"]) == "none", "a Forward+ boot that reached the editor is accepted")
	var failed_boot: Dictionary = Gfx.resolve_startup_renderer("forward_plus", "forward_plus", "mobile", 0, "Android", false)
	_check(str(failed_boot["action"]) == "fallback", "one failed Android Forward+ boot falls back")
	_check(str(failed_boot["preference"]) == "mobile", "the failed boot falls back to the platform default")
	_check(str(failed_boot["pending"]) == "", "the failed boot clears the pending request")
	_check(failed_boot["args"].size() == 0, "the failed boot needs no restart args")
	_check(str(failed_boot.get("reason", "")) != "", "the failed boot has a readable reason")
	var normal_retry: Dictionary = Gfx.resolve_startup_renderer("forward_plus", "forward_plus", "mobile", 0, "Android", true)
	_check(str(normal_retry["action"]) == "restart", "a supported backend keeps the two-attempt retry path")
	# A launch that reached the pending backend but never marked ready (for
	# example a first-frame Vulkan crash) keeps the request. The following
	# launch must treat that as the failed attempt instead of clearing it.
	var unproven_boot: Dictionary = Gfx.resolve_startup_renderer("forward_plus", "forward_plus", "forward_plus", 1, "Android", false)
	_check(str(unproven_boot["action"]) == "none", "an unproven pending backend does not restart on its own launch")
	_check(str(unproven_boot["pending"]) == "forward_plus", "an unproven pending backend keeps its request")
	var after_unproven: Dictionary = Gfx.resolve_startup_renderer("forward_plus", str(unproven_boot["pending"]), "mobile", 1, "Android", false)
	_check(str(after_unproven["action"]) == "fallback", "the next launch after an unmarked boot falls back")
	_check(str(after_unproven["pending"]) == "", "the failed-over pending request is cleared")
	var stale_pending_state: Dictionary = Gfx.resolve_startup_renderer("mobile", "vulkan", "mobile", 0, "Android")
	_check(str(stale_pending_state["action"]) == "fallback", "an unsupported pending renderer falls back")
	_check(str(stale_pending_state["pending"]) == "", "an unsupported pending renderer is cleared")
	_check(stale_pending_state["args"].size() == 0, "an unsupported pending renderer has no restart args")
	_check(str(stale_pending_state.get("reason", "")) != "", "an unsupported pending renderer explains the fallback")

	# mark_renderer_ready persists readiness without erasing the last reason.
	Gfx.renderer_ready = false
	Gfx.last_renderer_error = "keep the fallback explanation"
	Gfx.mark_renderer_ready()
	_check(Gfx.renderer_ready, "mark_renderer_ready writes renderer_ready")
	_check(Gfx.last_renderer_error == "keep the fallback explanation", "mark_renderer_ready keeps the fallback explanation readable")
	_check(bool(Gfx.to_dict().get("renderer_ready", false)), "renderer_ready survives to_dict")

	# The home shell runs ensure_renderer but must not clear an unproven
	# request: readiness is only written after the editor's first 3D frame.
	var actual_now: String = Gfx.actual_method()
	Gfx.renderer_preference = actual_now
	Gfx.renderer_choice = actual_now
	Gfx.renderer_pending = actual_now
	Gfx.renderer_attempts = 1
	Gfx.renderer_attempt_at = 0.0
	Gfx.renderer_ready = false
	Gfx.last_renderer_error = ""
	var unproven_run: Dictionary = Gfx.ensure_renderer()
	_check(str(unproven_run.get("action", "")) == "none", "an unproven pending backend does not restart again")
	_check(Gfx.renderer_pending == actual_now, "an unproven pending backend keeps its request through the home shell")
	_check(not Gfx.renderer_ready, "the home shell does not mark an unproven backend ready")
	Gfx.mark_renderer_ready()
	_check(Gfx.renderer_ready and Gfx.renderer_pending == "", "the editor's first frame clears the proven request")

	# Mobile-safe profile: clamps a stored quality preset on Android Forward+,
	# leaves the same values untouched on a desktop backend.
	var saved_msaa: int = Gfx.msaa
	var saved_taa: bool = Gfx.taa
	var saved_ssil: bool = Gfx.ssil
	var saved_ssr: bool = Gfx.ssr
	var saved_fog: bool = Gfx.volumetric_fog
	var saved_shadow_quality: int = Gfx.shadow_quality
	var saved_shadow_distance: float = Gfx.shadow_distance
	var saved_shadow_splits: int = Gfx.shadow_splits
	var saved_scale: float = Gfx.scale_3d
	var saved_max_fps: int = Gfx.max_fps
	Gfx.msaa = 2
	Gfx.taa = true
	Gfx.ssil = true
	Gfx.ssr = true
	Gfx.volumetric_fog = true
	Gfx.shadow_quality = 3
	Gfx.shadow_distance = 60.0
	Gfx.shadow_splits = 4
	Gfx.scale_3d = 1.0
	Gfx.max_fps = 120
	var android_profile: Dictionary = Gfx.safe_forward_plus_profile("Android", "forward_plus")
	_check(int(android_profile["msaa"]) <= 1, "the Android Forward+ profile caps MSAA at 2x")
	_check(not bool(android_profile["taa"]) and not bool(android_profile["ssil"]) and not bool(android_profile["ssr"]) and not bool(android_profile["volumetric_fog"]), "the Android Forward+ profile clamps high-end effects")
	_check(float(android_profile["scale_3d"]) <= 0.85, "the Android Forward+ profile caps 3D scale")
	_check(int(android_profile["shadow_quality"]) <= 2, "the Android Forward+ profile caps shadow quality")
	_check(float(android_profile["shadow_distance"]) <= 40.0, "the Android Forward+ profile caps shadow distance")
	_check(int(android_profile["shadow_splits"]) <= 2, "the Android Forward+ profile caps shadow splits")
	_check(int(android_profile["max_fps"]) <= 60 and int(android_profile["max_fps"]) >= 1, "the Android Forward+ profile caps the frame rate")
	var desktop_profile: Dictionary = Gfx.safe_forward_plus_profile("Linux", "forward_plus")
	_check(int(desktop_profile["msaa"]) == 2 and bool(desktop_profile["taa"]) and bool(desktop_profile["ssil"]) and bool(desktop_profile["ssr"]) and bool(desktop_profile["volumetric_fog"]), "the desktop profile keeps stored quality values")
	_check(float(desktop_profile["scale_3d"]) == 1.0 and int(desktop_profile["shadow_quality"]) == 3 and int(desktop_profile["max_fps"]) == 120, "the desktop profile keeps every cap open")

	# Capability matrix.
	var android_caps: Dictionary = Gfx.capabilities_for("forward_plus", "Android")
	_check(bool(android_caps["mobile_safe"]), "Android Forward+ reports a mobile-safe profile")
	_check(not bool(android_caps["ssil"]) and not bool(android_caps["ssr"]) and not bool(android_caps["taa"]) and not bool(android_caps["volumetric_fog"]), "Android Forward+ clamps high-end feature flags")
	_check(bool(android_caps["ssao"]) and bool(android_caps["glow"]), "Android Forward+ keeps SSAO and glow")
	_check(int(android_caps["msaa_cap"]) == 1, "Android Forward+ caps MSAA at 2x")
	_check(is_equal_approx(float(android_caps["scale_3d_cap"]), 0.85), "Android Forward+ caps 3D scale at 0.85")
	_check(int(android_caps["shadow_quality_cap"]) == 2, "Android Forward+ caps shadow quality")
	_check(int(android_caps["max_fps_cap"]) == 60, "Android Forward+ caps the frame rate")
	var linux_caps: Dictionary = Gfx.capabilities_for("forward_plus", "Linux")
	_check(not bool(linux_caps["mobile_safe"]), "desktop Forward+ is not mobile-safe")
	_check(int(linux_caps["msaa_cap"]) == 3 and is_equal_approx(float(linux_caps["scale_3d_cap"]), 1.0) and int(linux_caps["shadow_quality_cap"]) == 3 and int(linux_caps["max_fps_cap"]) == 0, "desktop Forward+ keeps every cap open")
	_check(bool(linux_caps["taa"]) and not bool(Gfx.capabilities_for("mobile", "Linux")["taa"]), "TAA stays Forward+-only")

	# I2: both renderer surfaces resolve the project request with the mobile
	# feature override instead of the base project setting.
	_check(Gfx.project_renderer_request(PackedStringArray(["mobile"])) == "mobile", "the mobile feature override resolves the project request")
	_check(Gfx.project_renderer_request() == "forward_plus", "the empty feature set resolves the desktop project request")

	# M1: a blocked switch leaves every stored field untouched.
	Gfx.renderer_preference = "mobile"
	Gfx.renderer_choice = "mobile"
	Gfx.renderer_pending = ""
	Gfx.renderer_attempts = 0
	Gfx.renderer_attempt_at = 0.0
	var blocked_result: Dictionary = Gfx.prepare_renderer_switch("vulkan", "Android")
	_check(bool(blocked_result["blocked"]), "an unsupported renderer is blocked")
	_check(Gfx.renderer_preference == "mobile", "a blocked switch preserves the stored preference")
	_check(Gfx.renderer_pending == "", "a blocked switch preserves the stored pending state")
	_check(Gfx.renderer_attempts == 0 and is_zero_approx(Gfx.renderer_attempt_at), "a blocked switch preserves the attempt bookkeeping")

	Gfx.renderer_preference = saved_preference
	Gfx.renderer_pending = saved_pending
	Gfx.renderer_attempts = saved_attempts
	Gfx.renderer_attempt_at = saved_attempt_at
	Gfx.renderer_ready = saved_ready
	Gfx.last_renderer_error = saved_error
	Gfx.renderer_choice = saved_choice
	Gfx.msaa = saved_msaa
	Gfx.taa = saved_taa
	Gfx.ssil = saved_ssil
	Gfx.ssr = saved_ssr
	Gfx.volumetric_fog = saved_fog
	Gfx.shadow_quality = saved_shadow_quality
	Gfx.shadow_distance = saved_shadow_distance
	Gfx.shadow_splits = saved_shadow_splits
	Gfx.scale_3d = saved_scale
	Gfx.max_fps = saved_max_fps

	# M2/11: a stored renderer error is shown readably in the sheet, and the
	# sheet still offers exactly the live supported set on Linux.
	Gfx.last_renderer_error = "Forward+ did not reach the editor on the previous launch."
	editor._open_renderer_sheet()
	await get_tree().process_frame
	_check(editor._overlay.has_modal(), "renderer sheet opens with a stored error")
	var sheet_error_shown := false
	for label in _labels_under(editor._overlay._body_host):
		if label.text.contains("did not reach the editor"):
			sheet_error_shown = true
	_check(sheet_error_shown, "the renderer sheet shows the stored renderer error")
	var error_sheet_buttons: Array = []
	_collect_group_buttons(editor._overlay._body_host, error_sheet_buttons)
	_check(error_sheet_buttons.size() == Gfx.supported_renderers(OS.get_name()).size(), "the renderer sheet offers the live supported set")
	editor._overlay.close_modal()
	await get_tree().process_frame
	Gfx.last_renderer_error = saved_error

	# 12: capability gating is reported without mutating the running platform.
	_check(not bool(Gfx.capabilities_for("forward_plus", "Android")["taa"]), "simulated Android Forward+ reports TAA unavailable")
	_check(int(Gfx.capabilities_for("forward_plus", "Android")["msaa_cap"]) < 2, "simulated Android Forward+ reports MSAA above 2x unavailable")

	editor._open_settings("graphics")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._overlay.has_modal(), "settings opens")
	_check(editor._settings_panel.categories() == ["general", "editor", "display", "graphics", "performance", "render", "import", "media", "rig", "about"], "settings categories are complete")
	var graphics_labels: Array[String] = []
	for label in _labels_under(editor._overlay):
		graphics_labels.append(label.text)
	_check(_label_contains(graphics_labels, "% · max "),
		"the 3D resolution cap renders its percent hint")
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
	editor._open_settings("media")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._settings_panel.active_category() == "media", "the media settings page opens")
	var media_texts: Array[String] = []
	for label in _labels_under(editor._overlay):
		media_texts.append(label.text)
	_check(_label_contains(media_texts, "video reference proxy"), "media settings show the proxy section")
	_check("Proxy fps" in media_texts, "media settings show the proxy fps control")
	_check("Proxy width" in media_texts, "media settings show the proxy width control")
	_check(_button_with_text(editor._overlay, "6") != null, "media settings offer the real 6 fps proxy option")
	editor._settings_panel.set_option("media.proxy_fps", 6)
	_check(int(Prefs.get_value("media.proxy_fps", 0)) == 6, "the 6 fps proxy option writes Prefs")
	editor._open_settings("rig")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._settings_panel.active_category() == "rig", "the rig settings page opens")
	var rig_texts: Array[String] = []
	for label in _labels_under(editor._overlay):
		rig_texts.append(label.text)
	_check(_label_contains(rig_texts, "viewport"), "rig settings show the viewport section")
	_check("Show overlay" in rig_texts, "rig settings show the overlay control")
	editor._settings_panel.set_option("rig.show_overlay", false)
	_check(bool(Prefs.get_value("rig.show_overlay", true)) == false, "the rig overlay option writes Prefs")
	editor._settings_panel.set_option("rig.show_overlay", true)
	editor.set_layout_mode("compact")
	await get_tree().process_frame
	editor._open_settings("display")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._settings_panel._resolved_mode() == "Compact", "settings reports the resolved workspace")
	_check(editor._settings_panel._ui_scale_control != null, "settings exposes the UI scale slider")
	if editor._settings_panel._ui_scale_control != null:
		var settings_scale = editor._settings_panel._ui_scale_control.slider
		_check(is_equal_approx(settings_scale.min_value, 50.0) and is_equal_approx(settings_scale.max_value, 200.0), "settings UI scale spans 50 to 200 percent")
		_check(settings_scale.step <= 1.0, "settings UI scale is continuous in one-percent steps")
	editor.apply_fit_info(43.0, false, false)
	await get_tree().process_frame
	_check(editor._settings_panel._ui_scale_control.slider.editable, "UI scale stays editable while Desktop fit is active")
	_check(editor._settings_panel._fit_label.text.contains("43"), "settings shows the fit percentage")
	_check(editor._settings_panel._fit_label.text.contains("still applies"), "settings explains the slider still works under fit")
	editor.apply_fit_info(100.0, true, false)
	await get_tree().process_frame
	_check(editor._settings_panel._ui_scale_control.slider.editable, "UI scale works at 100 percent fit")
	editor._settings_panel._ui_scale_control.set_percent_value(120.0, true)
	await get_tree().process_frame
	_check(is_equal_approx(float(Prefs.get_value("display.user_scale", 0.0)), 1.2),
		"the settings slider persists a 120 percent scale")
	editor._settings_panel._ui_scale_control.set_percent_value(100.0, true)
	editor._settings_panel.open("render")
	await get_tree().process_frame
	_check(editor._settings_panel.active_category() == "render", "the render settings page opens")
	_check(_button_with_text(editor._overlay, "Render sheet") == null,
		"Settings exposes no render-sheet entry point")
	_check(_button_with_text(editor._overlay, "Quick still") == null,
		"Settings exposes no quick-still action")
	var render_labels: Array[String] = []
	for label in _labels_under(editor._overlay):
		render_labels.append(label.text)
	_check(_label_contains(render_labels, "Long edge") or
		_button_with_text(editor._overlay, "1920") != null,
		"the render settings page keeps its real preferences")
	editor._overlay.close_modal()
	await get_tree().process_frame

	print("SMOKE STEP: workspace fit refresh")
	editor._open_interface_sheet()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._interface_sheet != null, "workspace sheet opens")
	_check(editor._interface_sheet._mode_buttons["compact"].button_pressed, "workspace shows the saved arrangement preference")
	_check(editor._interface_sheet._resolved_mode() == "compact", "workspace reports the resolved mode")
	_check(editor._interface_sheet._orientation_stacked, "workspace stacks orientation on a narrow sheet")
	_check(editor._interface_sheet._orientation_track != null, "workspace exposes a real orientation control")
	_check(editor._interface_sheet._scale_control != null, "workspace exposes the UI scale slider")
	if editor._interface_sheet._scale_control != null:
		var workspace_scale = editor._interface_sheet._scale_control.slider
		_check(is_equal_approx(workspace_scale.min_value, 50.0) and is_equal_approx(workspace_scale.max_value, 200.0), "workspace UI scale spans 50 to 200 percent")
	editor.apply_fit_info(43.0, false, false)
	await get_tree().process_frame
	_check(editor._interface_sheet._scale_control.slider.editable, "workspace UI scale stays editable while fit is active")
	_check(editor._interface_sheet._fit_label.text.contains("43"), "workspace reports the live fit percentage")
	_check(editor._interface_sheet._fit_label.text.begins_with("Fit 43%"),
		"the workspace fit label names the fit, not a mode")
	_check(not editor._interface_sheet._fit_label.text.contains("Desktop fit"),
		"the fit label is not reused as Desktop-only copy")
	editor.apply_fit_info(100.0, true, false)
	await get_tree().process_frame
	_check(editor._interface_sheet._scale_control.slider.editable, "workspace UI scale stays editable at 100 percent")
	editor._interface_sheet._scale_control.set_percent_value(150.0, true)
	await get_tree().process_frame
	_check(is_equal_approx(float(Prefs.get_value("display.user_scale", 0.0)), 1.5),
		"the workspace slider persists a 150 percent scale")
	_check(is_equal_approx(editor._interface_sheet._scale_control.scale_value(), 1.5),
		"the workspace slider exposes its scale as a factor")
	editor._interface_sheet._scale_control.set_percent_value(100.0, true)
	editor._overlay.close_modal()
	await get_tree().process_frame

	print("SMOKE STEP: workspace clamp copy and rotation")
	await _resize_shell(main, editor, Vector2(915.0, 412.0))
	editor.set_layout_mode("studio")
	editor._open_interface_sheet()
	await get_tree().process_frame
	await get_tree().process_frame
	var workspace = editor._interface_sheet
	_check(workspace._two_column, "a landscape phone opens the workspace in two columns")
	var landscape_text := ""
	for workspace_label in _labels_under(workspace):
		landscape_text += workspace_label.text + "\n"
	_check(landscape_text.contains("Below 85%"),
		"the two-column scale hint keeps the touch-floor warning")
	editor.apply_fit_info(100.0, true, true)
	await get_tree().process_frame
	_check(workspace._warning != null and workspace._warning.text.contains("Limited to fit this screen"),
		"a clamped non-Desktop canvas uses the fit-limited copy")
	_check(workspace._warning != null and not workspace._warning.text.contains("Desktop stays selected"),
		"the clamp copy does not claim Desktop is selected")
	var stored_mode := str(Prefs.get_value("display.layout", ""))
	await _resize_shell(main, editor, Vector2(412.0, 915.0))
	editor.apply_fit_info(100.0, true, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not workspace._two_column, "rotating to portrait rebuilds the sheet as one column")
	_check(workspace._orientation_stacked, "rotating to portrait stacks orientation again")
	_check(str(Prefs.get_value("display.layout", "")) == stored_mode,
		"a clamped sheet does not rewrite the saved arrangement")
	editor._overlay.close_modal()
	await get_tree().process_frame

	await _resize_shell(main, editor, Vector2(1440.0, 900.0))
	editor._open_interface_sheet()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not editor._interface_sheet._orientation_stacked, "wide workspace keeps orientation inline")
	_check(editor._interface_sheet._orientation_track.custom_minimum_size.x >= 280.0, "wide orientation strip keeps a real target width")
	editor._overlay.close_modal()
	await get_tree().process_frame
	await _resize_shell(main, editor, Vector2(412.0, 915.0))
	editor.set_layout_mode("compact")
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
	var sheet_buttons: Array = []
	_collect_group_buttons(editor._overlay._body_host, sheet_buttons)
	_check(sheet_buttons.size() == Gfx.supported_renderers(OS.get_name()).size(), "renderer sheet offers the supported renderer set")
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
	# Frame and Grid moved from the old view header into the Scene context row.
	editor.set_workspace("scene")
	await get_tree().process_frame
	await get_tree().process_frame
	var render_frame_action: Button = editor._context_bar.action_button("frame")
	var render_grid_action: Button = editor._context_bar.action_button("grid")
	_check(render_frame_action != null and render_frame_action.custom_minimum_size.y >= 44.0,
		"the context Frame action keeps a 44 dp target")
	_check(render_grid_action != null and render_grid_action.custom_minimum_size.y >= 44.0,
		"the context Grid action keeps a 44 dp target")
	var render_was_playing: bool = doc.is_playing
	doc.pause()
	doc.seek(1.0)
	# I2: render mode owns the whole frame. The shell bars and the Animate pane
	# hide, and exiting restores them without resizing the 3D view.
	await _resize_shell(main, editor, Vector2(1280.0, 800.0))
	editor.set_layout_mode("studio")
	editor.set_workspace("animate")
	await get_tree().process_frame
	editor._timeline.set_sheet_visible(true)
	await get_tree().process_frame
	_check(editor._animate_pane.visible, "render mode starts from the Animate pane")
	var render_view_size: Vector2 = editor._view.size
	editor._enter_render_mode()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._render_mode, "quick render enters a real-time render mode")
	_check(render_view.render_mode, "viewport enters render mode")
	_check(not editor._workspace_bar.visible, "render mode hides the workspace bar")
	_check(not editor._context_bar.visible, "render mode hides the context row")
	_check(not editor._transport_bar.visible, "render mode hides the shared transport")
	_check(not editor._animate_pane.visible, "render mode hides the Animate pane")
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
	_check(editor._workspace_bar.visible, "editing chrome returns")
	_check(editor._animate_pane.visible, "render mode restores the Animate pane")
	_check(is_equal_approx(editor._view.size.x, render_view_size.x) and
		is_equal_approx(editor._view.size.y, render_view_size.y),
		"entering and leaving render mode never resizes the 3D view")
	_check(not editor._render_hud.visible, "render transport hides")
	_check(is_equal_approx(doc.current_time, 1.0), "exiting restores the playhead")
	_check(doc.is_playing == render_was_playing, "exiting restores the prior playback state")
	editor.set_workspace("scene")
	await get_tree().process_frame
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
	_check(is_equal_approx(float(view.gizmo_scale), float(Prefs.get_value("editor.gizmo_size", 1.25))),
		"the editor applies the stored gizmo scale")
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

	# Capture entry points share one guard: a still or sequence must not start
	# while a GIF/MP4/PNG export owns the render path.
	_check(editor.has_method("_capture_blocked"),
		"the editor exposes the shared capture guard")
	if editor.has_method("_capture_blocked"):
		editor._render_busy = false
		editor._media_busy = true
		_check(editor._capture_blocked(), "capture guard blocks during a media export")
		editor._quick_still()
		editor._render_still()
		editor._render_sequence(false)
		_check(not editor._render_busy,
			"capture entry points refuse to start during a media export")
		editor._media_busy = false
		editor._render_busy = true
		_check(editor._capture_blocked(), "capture guard blocks during a render")
		editor._render_busy = false
		_check(not editor._capture_blocked(), "capture guard opens when idle")

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
		# Import success toast: OBJ stays one mesh; a glTF import names its
		# part count so the hierarchy is discoverable from the confirmation.
		editor._on_model_selected(true, PackedStringArray([fixture.path_join("sample.obj")]), 0)
		await get_tree().process_frame
		_check(editor._overlay._toast_label.text.begins_with("Imported ") and
			editor._overlay._toast_label.text.ends_with("· single mesh"),
			"an OBJ import toast says single mesh")
		var toast_root := Node3D.new()
		toast_root.name = "ToastModel"
		var toast_mesh := MeshInstance3D.new()
		toast_mesh.name = "ToastBody"
		toast_mesh.mesh = BoxMesh.new()
		toast_root.add_child(toast_mesh)
		add_child(toast_root)
		await get_tree().process_frame
		var toast_glb := fixture.path_join("toast_fixture.glb")
		var toast_gltf := GLTFDocument.new()
		var toast_state := GLTFState.new()
		var toast_err := toast_gltf.append_from_scene(toast_root, toast_state)
		if toast_err == OK:
			toast_err = toast_gltf.write_to_filesystem(toast_state, toast_glb)
		toast_root.queue_free()
		await get_tree().process_frame
		_check(toast_err == OK, "the toast GLB fixture is written")
		if toast_err == OK:
			editor._on_model_selected(true, PackedStringArray([toast_glb]), 0)
			await get_tree().process_frame
			_check(editor._overlay._toast_label.text.begins_with("Imported ") and
				editor._overlay._toast_label.text.ends_with("· 1 hierarchy nodes"),
				"a glTF import toast names its hierarchy node count")
		DirAccess.remove_absolute(fixture.path_join("sample.obj"))
		DirAccess.remove_absolute(fixture.path_join("sample.mtl"))
		DirAccess.remove_absolute(fixture.path_join("tex.png"))
		DirAccess.remove_absolute(fixture.path_join("toast_fixture.glb"))
		DirAccess.remove_absolute(fixture)

	print("SMOKE STEP: sequence clock snapshots")
	# The clip playhead is the document's own state, not the last clip event.
	# A project loaded at t=3 must still be at 3 after a sequence run, and a
	# clip that advanced while playing must be restored, not the last pause.
	var reopen: Dictionary = Store.load_project(doc.project_id)
	_check(not reopen.is_empty(), "the project reopens for the clock snapshots")
	if not reopen.is_empty():
		var reopen_data: Dictionary = reopen.get("data", {}).duplicate(true)
		reopen_data["current_time"] = 3.0
		editor.open_loaded(reopen.get("meta", {}), reopen_data)
		await get_tree().process_frame
		await get_tree().process_frame
		var clock_doc = editor.doc
		_check(is_equal_approx(clock_doc.current_time, 3.0), "a loaded project keeps its saved playhead")
		clock_doc.play_sequence()
		_check(clock_doc.is_sequence_playing(), "the loaded project can run its sequence")
		clock_doc.pause_sequence()
		_check(is_equal_approx(clock_doc.current_time, 3.0),
			"stopping a sequence restores the loaded playhead")

		clock_doc.seek(0.5)
		clock_doc.play()
		await get_tree().create_timer(0.15).timeout
		var advanced_clip: float = clock_doc.current_time
		_check(advanced_clip > 0.55, "the clip clock advanced before the sequence")
		clock_doc.play_sequence()
		clock_doc.pause_sequence()
		_check(is_equal_approx(clock_doc.current_time, advanced_clip),
			"a sequence restores the clip time that was playing")

		clock_doc.pause()
		clock_doc.seek(0.5)
		clock_doc.play()
		await get_tree().create_timer(0.15).timeout
		var preview_clip: float = clock_doc.current_time
		editor._enter_render_mode()
		_check(editor._render_mode, "the render preview opens for the snapshot test")
		editor._exit_render_mode()
		await get_tree().process_frame
		clock_doc.play_sequence()
		clock_doc.pause_sequence()
		_check(is_equal_approx(clock_doc.current_time, preview_clip),
			"a silent render-exit restore becomes the saved clip playhead")
		clock_doc.pause()

	# Leave and clean up the temporary project.
	var project_id: String = editor.doc.project_id
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


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			var child := path.path_join(name)
			if dir.current_is_dir():
				_remove_tree(child)
			else:
				DirAccess.remove_absolute(child)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

func _contrast(a: Color, b: Color) -> float:
	var high := maxf(_relative_luminance(a), _relative_luminance(b))
	var low := minf(_relative_luminance(a), _relative_luminance(b))
	return (high + 0.05) / (low + 0.05)

## A control edge must be drawn, use the control-boundary token, and clear
## 3:1 against the surface behind it. `fill` is the panel fill, not the
## stylebox bg (a colour swatch's bg is the colour it previews).
func _check_control_edge(style: StyleBoxFlat, label: String, fill: Color) -> void:
	_check(style != null, label + " has a stylebox")
	if style == null:
		return
	_check(style.get_border_width(SIDE_LEFT) >= 1,
		label + " draws a boundary")
	_check(style.border_color == Kit.CONTROL_BORDER,
		label + " uses the control boundary token")
	_check(_contrast(style.border_color, fill) >= 3.0,
		label + " boundary clears 3:1 against its surface")

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


func _label_contains(texts: Array[String], needle: String) -> bool:
	for text in texts:
		if text.to_lower().contains(needle.to_lower()):
			return true
	return false

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
	var status := "PASS" if _failures.is_empty() else "FAIL"
	if _failures.is_empty():
		print("SMOKE RESULT: PASS")
	else:
		printerr("SMOKE RESULT: %d FAILURE(S)" % _failures.size())
	print("SUITE RESULT: " + status)
	get_tree().quit(0 if _failures.is_empty() else 1)
