extends Control
## W1 shell contract: layout/workspace API, WorkspaceBar, workspace and project
## menus, the context row and the transport.
##
## The suite boots the real application shell at the sizes the spec budgets for
## and reads the live controls. It never fabricates a control or a state.

const PROJECT_TITLE := "Shell suite"
const SettingsPanelScript = preload("res://src/ui/settings_panel.gd")

var _failures: Array[String] = []
var _checks := 0
var _main: Control = null


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("SHELL FAIL: " + message)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("SHELL OK: " + message)
	else:
		_fail(message)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_window().size = Vector2i(915, 412)
	await get_tree().process_frame
	await get_tree().process_frame
	await _test_layout_and_workspace_api()
	await _test_workspace_bar_and_menu()
	await _test_compact_top_bar()
	await _test_context_bar_overflow_and_icons()
	await _test_transport()
	await _test_shell_anatomy_and_panels()
	await _test_camera_view()
	await _test_workspace_switch_with_open_surfaces()
	await _test_back_precedence()
	await _test_desktop_shell()
	await _test_version_strings()
	_finish()


func _boot_main(width: int, height: int) -> Control:
	get_window().size = Vector2i(width, height)
	await get_tree().process_frame
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
		_main = null
	Prefs.set_value("editor.workspace", "scene")
	# Each boot owns its arrangement. The layout API test above persists an
	# explicit Studio choice; without this reset every later size would boot
	# Studio and the 360 dp case would be clamped to 480 logical pixels instead
	# of resolving Compact.
	Prefs.set_value("display.layout", "auto")
	var packed: PackedScene = load("res://src/app/main.tscn")
	var main: Control = packed.instantiate()
	add_child(main)
	await get_tree().process_frame
	main._on_new_project_requested(PROJECT_TITLE, "blank")
	for _i in 4:
		await get_tree().process_frame
	main._editor._overlay.clear_toast()
	_main = main
	return main


func _resize_main(main: Control, value: Vector2i) -> void:
	get_window().size = value
	for _i in 3:
		await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame


func _test_layout_and_workspace_api() -> void:
	var main = await _boot_main(915, 412)
	var editor = main._editor
	editor.set_layout_mode("studio")
	await get_tree().process_frame
	_check(editor.layout_mode() == "studio", "set_layout_mode resolves to studio")
	_check(Prefs.get_value("display.layout", "") == "studio",
		"the layout preference keeps the display.layout key")

	editor.set_workspace("render")
	await get_tree().process_frame
	_check(editor.workspace() == "render", "set_workspace switches to render")
	_check(Prefs.get_value("editor.workspace", "") == "render",
		"the workspace persists under editor.workspace")
	editor.set_workspace("scene", false)
	_check(editor.workspace() == "scene", "set_workspace(..., false) does not persist")
	_check(Prefs.get_value("editor.workspace", "") == "render",
		"a non-persisted switch leaves the saved workspace alone")

	editor.set_workspace("bogus")
	_check(editor.workspace() == "scene", "an invalid workspace id falls back to scene")


func _test_workspace_bar_and_menu() -> void:
	var main = await _boot_main(915, 412)
	var editor = main._editor
	var bar = editor._workspace_bar
	_check(bar.size.y >= 43.5 and bar.size.y <= 44.5, "touch top bar is 44 dp")
	_check(not bar.visible_action_ids().has("render"), "no render action lives in the top bar")

	# Three permanent text tabs; Rig and Render never appear as tabs.
	for id in ["scene", "shading", "animate"]:
		var tab: Button = bar.workspace_tab(id)
		_check(tab != null, "the %s tab exists" % id)
		if tab == null:
			continue
		_check(tab.visible, "the %s tab is visible" % id)
		_check(tab.text == str(editor.WORKSPACE_LABELS.get(id, id)),
			"the %s tab names its workspace" % id)
		_check(tab.custom_minimum_size.x >= 44.0,
			"the %s tab keeps the 44 dp minimum width" % id)
		_check(tab.custom_minimum_size.y >= 43.5,
			"the %s tab keeps the 44 dp touch height" % id)
		_check(tab.get_theme_font_size("font_size") == 11,
			"the %s tab uses an 11 sp label" % id)
		_check(tab.get_meta("workspace_tab", "") == id,
			"the %s tab carries its id" % id)
	_check(bar.workspace_tab("rig") == null and bar.workspace_tab("render") == null,
		"Rig and Render are not permanent tabs")
	_check(_is_filled(bar.workspace_tab("scene")), "the active tab uses the focus fill")
	_check(not _is_filled(bar.workspace_tab("shading")),
		"an inactive tab has no focus fill")

	var more: Button = bar.more_button()
	_check(more != null and more.visible, "the bar exposes the More workspaces control")
	_check(more.custom_minimum_size.x >= 43.5 and more.custom_minimum_size.y >= 43.5,
		"More keeps the 44 dp touch target")
	_check(more.get_meta("action_icon", "") == "ellipsis-horizontal",
		"More uses the ellipsis-horizontal glyph")
	_check(more.tooltip_text == "More workspaces", "More carries an accessible name")

	bar.workspace_tab("shading").pressed.emit()
	await get_tree().process_frame
	_check(editor.workspace() == "shading", "a primary tab switches workspace")
	_check(_is_filled(bar.workspace_tab("shading")), "the new tab takes the focus fill")
	_check(not _is_filled(bar.workspace_tab("scene")), "the old tab loses the focus fill")
	_check(bar.more_button().text == "",
		"More stays an ellipsis in a primary workspace")

	more.pressed.emit()
	await get_tree().process_frame
	_check(editor.workspace_menu_open(), "More opens the secondary-workspace menu")
	var menu = editor._workspace_menu
	_check(menu._centered == false, "the secondary menu opens as an anchored dropdown")
	_check(not menu.scrim().visible, "the anchored secondary menu shows no scrim")
	_check(menu.scrim().mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"the anchored menu never steals the More tap")
	_check(menu.row_count() == 2, "the secondary menu has exactly two rows")
	for id in ["rig", "render"]:
		var row: Button = menu.row_button(id)
		_check(row != null, "the secondary menu has the %s row" % id)
		if row == null:
			continue
		_check(row.custom_minimum_size.y >= 43.5 and row.custom_minimum_size.y <= 44.5,
			"the %s row is 44 dp" % id)
		_check(row.get_meta("action_icon", "") ==
			("bone" if id == "rig" else "clapperboard"),
			"the %s row uses its icon" % id)
		_check(row.get_meta("workspace_row", "") == id,
			"the %s row carries its id" % id)
	_check(menu._panel.size.x <= 280.0, "the secondary menu is at most 280 dp wide")
	_check(menu._header.custom_minimum_size.y <= 32.5,
		"the secondary menu header is 32 dp")
	_check(not menu.row_button("rig").button_pressed,
		"no secondary row is checked in a primary workspace")

	more.pressed.emit()
	await get_tree().process_frame
	_check(not editor.workspace_menu_open(), "tapping More again closes the menu")

	more.pressed.emit()
	await get_tree().process_frame
	menu.row_button("rig").pressed.emit()
	await get_tree().process_frame
	_check(editor.workspace() == "rig", "the Rig row switches workspace")
	_check(not editor.workspace_menu_open(), "selecting a row closes the menu")
	_check(bar.more_button().text == "Rig",
		"More shows the active secondary workspace name")
	_check(bar.more_button().get_meta("action_icon", "") == "chevron-down",
		"the named More control pairs the name with a chevron")
	_check(bar.more_button().custom_minimum_size.x >= 60.0,
		"the named More control keeps a 60 dp minimum")
	_check(_is_filled(bar.more_button()),
		"the named More control uses the active fill")

	more.pressed.emit()
	await get_tree().process_frame
	_check(menu.row_button("rig").button_pressed, "the Rig row is checked while Rig is current")
	_check(menu.row_button("render") != null, "the Render row is still reachable")
	menu.row_button("render").pressed.emit()
	await get_tree().process_frame
	_check(editor.workspace() == "render" and bar.more_button().text == "Render",
		"the Render row switches workspace and renames More")
	bar.workspace_tab("scene").pressed.emit()
	await get_tree().process_frame
	_check(editor.workspace() == "scene", "a tab returns from a secondary workspace")
	_check(bar.more_button().text == "" and
		bar.more_button().get_meta("action_icon", "") == "ellipsis-horizontal",
		"More returns to the ellipsis")

	# Back is one control with an honest name: from a secondary workspace it
	# returns to Scene, not to the project browser.
	_check(bar.action_button("back").tooltip_text == "Back",
		"the Back control has the accessible name Back")
	for workspace_id in ["rig", "render"]:
		editor.set_workspace(workspace_id)
		await get_tree().process_frame
		bar.action_button("back").pressed.emit()
		await get_tree().process_frame
		_check(editor.workspace() == "scene",
			"the actual Back control returns from %s" % workspace_id)

	# Project menu order and rows at a width that keeps Undo/Redo on the bar.
	bar.action_button("menu").pressed.emit()
	await get_tree().process_frame
	var project = editor._project_menu
	var expected := ["settings", "import", "graphics", "interface", "performance",
		"instrumentation", "shortcuts", "about", "close"]
	_check(project.row_count() == expected.size(), "the project menu has nine rows")
	for id in expected:
		_check(project.row_button(id) != null, "project menu row %s exists" % id)
	_check(not project.row_button("instrumentation").visible,
		"the instrumentation strip row is hidden in touch layouts")
	_check(project.row_button("settings").custom_minimum_size.y >= 43.5,
		"the project menu keeps 44 dp rows")
	_check(project._panel.size.x <= 320.0, "the project menu keeps a 320 dp cap")
	_check(project.row_button("undo") == null and project.row_button("redo") == null,
		"the wide project menu does not duplicate the bar history")
	project.close()


func _test_compact_top_bar() -> void:
	var main = await _boot_main(360, 640)
	var editor = main._editor
	var bar = editor._workspace_bar
	var ids: PackedStringArray = bar.visible_action_ids()
	_check(not ids.has("undo") and not ids.has("redo"),
		"the 360 dp top bar hides Undo and Redo")
	_check(ids.has("back") and ids.has("save") and ids.has("menu"),
		"Back, Save and the project menu stay on the compact bar")
	_check(bar.get_combined_minimum_size().x <= 360.5,
		"the compact top bar fits the 360 dp budget")
	for workspace_id in ["rig", "render"]:
		editor.set_workspace(workspace_id)
		await get_tree().process_frame
		_check(bar.more_button().text != "",
			"the named More control is readable in %s" % workspace_id)
		_check(bar.get_combined_minimum_size().x <= 360.5,
			"the top bar keeps the 360 dp budget with %s named" % workspace_id)
	editor.set_workspace("scene")
	await get_tree().process_frame

	# Compact keeps the secondary menu anchored; the scrim would cover the
	# 44 dp More control and make the second-tap close physically unreachable.
	bar.more_button().pressed.emit()
	await get_tree().process_frame
	_check(editor._workspace_menu._centered == false,
		"the compact secondary menu opens anchored")
	_check(not editor._workspace_menu.scrim().visible,
		"the compact secondary menu has no scrim")
	editor._workspace_menu.close()
	await get_tree().process_frame

	bar.action_button("menu").pressed.emit()
	await get_tree().process_frame
	var project = editor._project_menu
	_check(project.row_button("undo") != null and project.row_button("redo") != null,
		"the compact project menu carries Undo and Redo")
	_check(project.row_button("undo").disabled and project.row_button("redo").disabled,
		"both history rows start disabled")
	_check(project.row_button("settings") != null and project.row_button("close") != null,
		"the history rows join the existing project rows")
	_check(project.row_button("settings").custom_minimum_size.y >= 43.5,
		"the compact project menu keeps 44 dp rows")
	_check(project._panel.size.x <= 320.0, "the compact project menu keeps its 320 dp cap")
	project.close()
	await get_tree().process_frame

	var added: String = editor.doc.add_primitive("box")
	await get_tree().process_frame
	bar.action_button("menu").pressed.emit()
	await get_tree().process_frame
	_check(not project.row_button("undo").disabled,
		"Undo enables when history exists")
	_check(project.row_button("redo").disabled,
		"Redo stays disabled at the head of history")
	project.row_button("undo").pressed.emit()
	await get_tree().process_frame
	_check(editor.doc.get_object(added).is_empty(),
		"the project-menu Undo row routes to the document")
	bar.action_button("menu").pressed.emit()
	await get_tree().process_frame
	_check(not project.row_button("redo").disabled,
		"Redo enables after an undo")
	project.row_button("redo").pressed.emit()
	await get_tree().process_frame
	_check(not editor.doc.get_object(added).is_empty(),
		"the project-menu Redo row routes to the document")

	# At exactly 600 dp the bar owns history again and the menu rows go away.
	await _resize_main(main, Vector2i(600, 960))
	editor.set_workspace("scene")
	await get_tree().process_frame
	ids = bar.visible_action_ids()
	_check(ids.has("undo") and ids.has("redo"),
		"600 dp returns Undo and Redo to the bar")
	bar.action_button("menu").pressed.emit()
	await get_tree().process_frame
	_check(project.row_button("undo") == null and project.row_button("redo") == null,
		"the 600 dp project menu drops the duplicate history rows")
	project.close()


func _is_filled(button: Button) -> bool:
	if button == null:
		return false
	var style := button.get_theme_stylebox("normal")
	return style is StyleBoxFlat and \
		(style as StyleBoxFlat).bg_color.is_equal_approx(Kit.FOCUS)



func _test_context_bar_overflow_and_icons() -> void:
	var main = await _boot_main(360, 640)
	var editor = main._editor
	var bar = editor._context_bar
	_check(bar.size.y >= 43.5 and bar.size.y <= 44.5, "touch context row is 44 dp")

	editor.set_workspace("scene")
	await get_tree().process_frame
	var visible: PackedStringArray = bar.visible_action_ids()
	for id in ["select", "move", "rotate", "scale", "add", "more"]:
		_check(visible.has(id), "scene 360 dp keeps %s visible" % id)
	for id in ["camera_view", "scene_tree", "inspector", "frame", "grid", "view"]:
		_check(not visible.has(id), "scene 360 dp moves %s into more" % id)
	_check(not bar.overflow_visible() or visible.has("more"),
		"overflow is represented by the more button")

	editor.set_workspace("rig")
	await get_tree().process_frame
	for id in ["pose", "edit", "rig_rotate", "rig_move", "more"]:
		_check(bar.visible_action_ids().has(id), "rig 360 dp keeps %s visible" % id)

	editor.set_workspace("render")
	await get_tree().process_frame
	_check(bar.visible_action_ids().has("render"), "render keeps its primary action")

	# The transform group is real in every transform workspace, 44 dp each,
	# and keeps all four controls visible on the 360 dp context row.
	var transforms := ["select", "move", "rotate", "scale"]
	for workspace_id in ["scene", "shading", "animate", "render"]:
		editor.set_workspace(workspace_id)
		await get_tree().process_frame
		var row: PackedStringArray = bar.visible_action_ids()
		for id in transforms:
			_check(row.has(id), "%s 360 dp keeps %s visible" % [workspace_id, id])
			var button: Button = bar.action_button(id)
			_check(button != null, "%s exposes %s" % [workspace_id, id])
			if button == null:
				continue
			_check(button.custom_minimum_size.x >= 43.5 and
				button.custom_minimum_size.y >= 43.5,
				"%s %s keeps the 44 dp target" % [workspace_id, id])
			_check(button.get_theme_constant("icon_max_width") == 18,
				"%s %s uses an 18 px glyph" % [workspace_id, id])
			_check(button.get_meta("action_icon", "") == "tool-" + id,
				"%s %s uses the tool icon" % [workspace_id, id])
			_check(button.toggle_mode, "%s %s is a toggle" % [workspace_id, id])

	# Priority order: Shading after Assign, Animate first, Render after Render.
	editor.set_workspace("shading")
	await get_tree().process_frame
	var order: PackedStringArray = bar.visible_action_ids()
	_check(order.find("assign") >= 0 and order.find("select") > order.find("assign"),
		"Shading puts the transform group after Assign")
	editor.set_workspace("animate")
	await get_tree().process_frame
	order = bar.visible_action_ids()
	_check(order.size() > 0 and order[0] == "select",
		"Animate puts the transform group first")
	editor.set_workspace("render")
	await get_tree().process_frame
	order = bar.visible_action_ids()
	_check(order.find("render") >= 0 and order.find("select") > order.find("render"),
		"Render puts the transform group after Render")

	# The current tool survives a workspace switch and shows the active fill.
	bar.action_button("move").pressed.emit()
	await get_tree().process_frame
	_check(editor._tool == "move", "Move becomes the current tool")
	_check(_is_filled(bar.action_button("move")), "the active tool uses the fill")
	editor.set_workspace("scene")
	await get_tree().process_frame
	_check(editor._tool == "move" and bar.action_button("move").button_pressed,
		"the current tool survives a workspace switch")
	editor.set_workspace("animate")
	await get_tree().process_frame
	_check(bar.action_button("move").button_pressed,
		"Animate restores the active tool without a reset")

	# No editable selection disables the four tools with a real reason.
	editor.doc.set_selection("")
	for id in transforms:
		var button: Button = bar.action_button(id)
		_check(button.disabled, "%s disables with no selection" % id)
		_check(button.tooltip_text == "Select an object to transform.",
			"%s states the real disabled reason" % id)
	var added: String = editor.doc.add_primitive("box")
	_check(added != "", "a real object exists for the enabled-tool check")
	for id in transforms:
		_check(not bar.action_button(id).disabled,
			"%s enables with an editable selection" % id)

	# Task 24: Assign, New and Add light are 96 dp text actions. Add light
	# also advertises its menu with a trailing chevron-down.
	editor.set_workspace("shading")
	await get_tree().process_frame
	for id in ["assign", "material_new", "light_add"]:
		var action_button: Button = bar.action_button(id)
		_check(action_button != null and action_button.get_meta("is_text", false),
			"Shading %s keeps the text form" % id)
		_check(action_button != null and action_button.custom_minimum_size.x >= 96.0,
			"Shading %s keeps the 96 dp width" % id)
	_check(bar.action_button("material_new").get_meta("action_icon", "") == "plus",
		"Shading New uses the plus glyph")
	_check(bar.action_button("light_add").get_meta("action_icon", "") == "lightbulb",
		"Shading Add light uses the lightbulb glyph")
	_check(bar.action_button("light_add").get_meta("trailing_icon", "") == "chevron-down",
		"Shading Add light advertises its menu with chevron-down")
	_check(bar.action_button("light_add").icon != null,
		"Shading Add light renders the combined glyph")
	editor.set_workspace("render")
	await get_tree().process_frame
	_check(bar.action_button("render").get_meta("is_text", false),
		"Render keeps the text primary action")
	for id in ["preview", "still"]:
		_check(not bar.action_button(id).get_meta("is_text", true),
			"Render %s became an icon action" % id)
		_check(bar.action_button(id).custom_minimum_size.x <= 44.5,
			"Render %s is a 44 dp icon action" % id)
	editor.set_workspace("scene")
	await get_tree().process_frame
	_check(bar.action_button("add").get_meta("is_text", false),
		"Scene Add keeps the text form")

	# Rig keeps its Pose/Edit and Rotate/Move pair and never offers Scale.
	editor.set_workspace("rig")
	await get_tree().process_frame
	_check(bar.action_button("rig_rotate") != null and bar.action_button("rig_move") != null,
		"Rig keeps Rotate and Move")
	_check(bar.action_button("pose") != null and bar.action_button("edit") != null,
		"Rig keeps Pose and Edit")
	_check(bar.action_button("scale") == null and bar.action_button("select") == null,
		"Rig has no generic transform group")

	# Icon deviations outside the shell action row: Media is video reference,
	# and every key action uses diamond-plus.
	_check(SettingsPanelScript.ICONS["media"] == "video",
		"Media settings uses the video reference icon")
	_check(FileAccess.file_exists("res://assets/icons/video.svg"),
		"the video reference icon exists")
	var key_pose: Button = editor._rig_panel.find_child("KeyPoseButton", true, false)
	_check(key_pose != null and key_pose.icon == Kit.icon_texture("diamond-plus"),
		"Key pose uses diamond-plus like every key action")

	# Icon contract: no two visible action ids share an icon in one workspace,
	# and every referenced icon file exists.
	for workspace_id in editor.WORKSPACES:
		editor.set_workspace(workspace_id)
		await get_tree().process_frame
		var icons := {}
		for id in editor._visible_shell_action_ids():
			var icon_name: String = editor._shell_action_icon(id)
			if icon_name == "":
				# Text-only actions (Pose, Edit, Dope, Graph) carry no glyph.
				continue
			_check(FileAccess.file_exists("res://assets/icons/%s.svg" % icon_name),
				"%s/%s icon file exists" % [workspace_id, icon_name])
			_check(not icons.has(icon_name),
				"%s: %s and %s do not share the %s icon" %
				[workspace_id, icons.get(icon_name, ""), id, icon_name])
			icons[icon_name] = id


func _test_transport() -> void:
	var main = await _boot_main(915, 412)
	var editor = main._editor
	var bar = editor._transport_bar
	_check(bar.size.y >= 43.5 and bar.size.y <= 44.5, "touch transport is 44 dp")
	_check(bar.animate_button().custom_minimum_size.x >= 96.0,
		"Animate is a 96 dp text action")

	var doc = editor.doc
	_check(not doc.is_playing, "playback starts paused")
	bar.play_button().pressed.emit()
	await get_tree().process_frame
	_check(doc.is_playing, "play drives document playback")
	bar.play_button().pressed.emit()
	await get_tree().process_frame
	_check(not doc.is_playing, "the same control pauses")

	doc.seek(1.0)
	bar.skip_start_requested.emit()
	await get_tree().process_frame
	_check(absf(doc.current_time) < 0.001, "skip to start returns to 0")

	# Add key inserts a real transform key set at the playhead.
	doc.seek(0.5)
	var before: int = doc.get_channel_keys(doc.selected_id, "position").size()
	bar.add_key_button().pressed.emit()
	await get_tree().process_frame
	_check(doc.get_channel_keys(doc.selected_id, "position").size() == before + 1,
		"add key inserts a real position key")

	doc.set_selection("")
	editor._sync_transport_state()
	_check(bar.add_key_button().disabled, "add key disables with no selection")
	_check(bar.add_key_button().tooltip_text == "Select an object to add a key.",
		"the disabled key control states the real reason")

	bar.animate_button().pressed.emit()
	await get_tree().process_frame
	_check(editor.workspace() == "animate", "Animate switches workspace")
	_check(not bar.visible, "the shared transport hides in Animate")

	# Time entry sheet: tap the timecode, enter a frame, seek.
	var time_button: Button = bar.time_button()
	time_button.pressed.emit()
	await get_tree().process_frame
	_check(editor._overlay.has_modal(), "tapping the timecode opens the entry sheet")
	editor._time_frame_field.text = "12"
	editor._time_frame_field.text_submitted.emit("12")
	editor._apply_time_entry()
	await get_tree().process_frame
	_check(absf(doc.current_time - 12.0 / float(doc.fps)) < 0.01,
		"the frame field seeks to frame 12")


func _test_shell_anatomy_and_panels() -> void:
	var main = await _boot_main(915, 412)
	var editor = main._editor

	editor.set_workspace("scene")
	await get_tree().process_frame
	_check(editor._workspace_bar.size.y >= 43.5, "scene: 44 dp top bar")
	_check(editor._context_bar.size.y >= 43.5, "scene: 44 dp context row")
	_check(editor._transport_bar.visible, "scene: transport visible")
	_check(editor._stage_host.size.x >= 480.0, "scene: stage keeps the centre")
	_check(editor._workspace_panel.mode() == editor._workspace_panel.Mode.HIDDEN,
		"scene: no reserved panel")
	_check(not editor._timeline.get_parent() == editor._stage_host,
		"scene: the timeline is not a stage child")

	# Scene tree/inspector overlays close each other and never resize the stage.
	var stage_width: float = editor._stage_host.size.x
	editor._toggle_scene_panel("scene")
	await get_tree().process_frame
	_check(editor._workspace_panel.mode() == editor._workspace_panel.Mode.OVERLAY,
		"scene tree opens as an overlay")
	_check(absf(editor._stage_host.size.x - stage_width) < 0.5,
		"opening an overlay does not resize the stage")
	editor._toggle_scene_panel("inspector")
	await get_tree().process_frame
	_check(editor._workspace_panel.content() == editor._inspector_panel,
		"opening the inspector closes the scene tree")
	editor._toggle_scene_panel("inspector")
	await get_tree().process_frame
	_check(editor._workspace_panel.mode() == editor._workspace_panel.Mode.HIDDEN,
		"tapping the same action closes the panel")

	# Reserved panels at 915 dp, with the stage floor.
	for id in ["shading", "rig", "render"]:
		editor.set_workspace(id)
		await get_tree().process_frame
		var mode: int = editor._workspace_panel.mode()
		_check(mode == editor._workspace_panel.Mode.RESERVED,
			"%s: 915 dp reserves the panel" % id)
		var width: float = editor._workspace_panel.panel_rect().size.x
		_check(width >= 280.0 and width <= 360.0,
			"%s: reserved width is 280–360 dp" % id)
		_check(editor._stage_host.size.x >= 480.0,
			"%s: the stage keeps at least 480 dp" % id)
		_check(editor._workspace_panel.close_button().visible == false,
			"%s: a reserved panel has no close button" % id)

	# Overlay panels below 768 dp.
	await _resize_main(main, Vector2i(600, 960))
	editor.set_workspace("shading")
	await get_tree().process_frame
	_check(editor._workspace_panel.mode() == editor._workspace_panel.Mode.OVERLAY,
		"600 dp turns the shading panel into an overlay")
	_check(editor._workspace_panel.scrim().visible, "the overlay has a scrim")
	_check(editor._workspace_panel.panel_rect().size.x <= 400.0,
		"the overlay respects the 400 dp cap")
	_check(editor._workspace_panel.close_button().visible and
		editor._workspace_panel.close_button().size.x >= 43.5,
		"the overlay close button is a 44 dp target")
	editor._workspace_panel.close_button().pressed.emit()
	await get_tree().process_frame
	_check(editor._workspace_panel.mode() == editor._workspace_panel.Mode.HIDDEN,
		"the close button closes the overlay")

	# Animate pane is a real layout sibling below the stage and does not cover it.
	await _resize_main(main, Vector2i(915, 412))
	editor.set_workspace("animate")
	await get_tree().process_frame
	_check(editor._animate_pane.visible, "animate: the pane is visible")
	_check(editor._animate_pane.get_parent() == editor._center, "animate: pane is in the centre column")
	_check(editor._animate_pane.get_index() > editor._stage_host.get_index(),
		"animate: the pane sits below the stage")
	_check(editor._animate_pane.timeline() == editor._timeline,
		"animate: the mounted Timeline is the existing component")
	_check(editor._timeline.get_parent() == editor._animate_pane,
		"animate: the timeline is not a stage overlay")
	_check(editor._stage_host.get_global_rect().end.y <=
		editor._animate_pane.get_global_rect().position.y + 0.5,
		"animate: the pane never covers the stage")
	_check(not editor._transport_bar.visible, "animate: the shared transport is replaced")
	var dead_more := false
	for node in editor._timeline.find_children("*", "BaseButton", true, false):
		var button := node as Button
		if button != null and button.text == "More" and \
				button.tooltip_text == "Show the full timeline":
			dead_more = true
	_check(not dead_more, "animate: no dead More control remains")
	_check(not editor._timeline.has_signal("more_requested"),
		"animate: no dead More signal remains")

	# Non-animate workspaces have no timeline over the stage.
	for id in ["scene", "shading", "rig", "render"]:
		editor.set_workspace(id)
		await get_tree().process_frame
		_check(not editor._animate_pane.visible,
			"%s: the animate pane is hidden" % id)
		_check(not editor._stage_host.is_ancestor_of(editor._timeline),
			"%s: no timeline node lives inside the stage host" % id)


func _test_camera_view() -> void:
	var main = await _boot_main(915, 412)
	var editor = main._editor
	var doc = editor.doc
	editor.set_workspace("scene")
	await get_tree().process_frame

	var cam_a: String = doc.add_camera(Vector3(2, 2, 3))
	var cam_b: String = doc.add_camera(Vector3(-2, 2, 3))
	doc.rename_object(cam_a, "A camera")
	doc.rename_object(cam_b, "B camera")
	await get_tree().process_frame

	editor._context_bar.action_button("camera_view").pressed.emit()
	await get_tree().process_frame
	var menu = editor._camera_menu
	_check(menu.is_open(), "the camera control opens the camera menu")
	_check(menu.row_count() >= 2, "the menu lists the scene cameras")
	_check(menu.row_button(cam_a) != null and menu.row_button(cam_b) != null,
		"both cameras are rows")
	var add_camera: Button = menu.row_button("add_camera")
	_check(add_camera != null, "the camera menu has the Add camera row")
	if add_camera != null and add_camera.get_index() > 0:
		var before_add: Node = add_camera.get_parent().get_child(add_camera.get_index() - 1)
		_check(before_add is ColorRect,
			"a separator divides the camera rows from Add camera")

	var exits: Array = []
	editor._view.look_through_exited.connect(func() -> void: exits.append(true))
	menu.row_button(cam_a).pressed.emit()
	await get_tree().process_frame
	_check(editor.is_look_through(), "selecting a camera enters look-through")
	_check(editor._view.look_through_camera_id() == cam_a, "the view holds camera A")
	_check(not editor._context_bar.visible and not editor._transport_bar.visible,
		"look-through hides context and transport")
	_check(editor._workspace_bar.action_button("undo").visible == false,
		"look-through hides undo")
	_check(editor._workspace_bar.more_button().text == "Camera: A camera",
		"the bar names the active camera")

	var saved_before: Dictionary = editor._view._look_saved.duplicate(true)
	editor._enter_camera_view(cam_b)
	await get_tree().process_frame
	_check(editor._view.look_through_camera_id() == cam_b, "switching updates the camera")
	_check(exits.is_empty(), "switching does not emit look_through_exited")
	_check(editor._view._look_saved == saved_before, "switching preserves the saved editor state")
	_check(editor._workspace_bar.more_button().text == "Camera: B camera",
		"the bar follows the camera switch")

	editor._workspace_bar.action_button("exit_camera").pressed.emit()
	await get_tree().process_frame
	_check(not editor.is_look_through(), "the top-bar X exits camera view")
	_check(exits.size() == 1, "exit emits look_through_exited once")

	# Deletion guard.
	editor._enter_camera_view(cam_b)
	doc.set_selection(cam_b)
	doc.delete_selected()
	await get_tree().process_frame
	_check(not editor.is_look_through(), "deleting the active camera exits look-through")
	_check(editor._overlay.toast_text() == "Camera removed — returned to the editor view.",
		"deletion shows the exact toast")

	# Hidden camera row is disabled with the reason.
	var cam_hidden: String = doc.add_camera(Vector3(0, 2, 4))
	doc.set_object_visible(cam_hidden, false)
	editor._open_camera_menu()
	await get_tree().process_frame
	var hidden_row: Button = editor._camera_menu.row_button(cam_hidden)
	_check(hidden_row.disabled, "a hidden camera is disabled")
	_check(hidden_row.tooltip_text == "Camera is hidden.", "the hidden reason is exact")
	editor._camera_menu.close()

	# Empty camera menu stays honest. Delete every camera, including the
	# blank template's Main Camera, so "no scene cameras" is real.
	for obj in doc.objects.duplicate():
		if str(obj.get("kind", "")) == "camera":
			doc.set_selection(str(obj.get("id", "")))
			doc.delete_selected()
	editor.set_workspace("scene")
	editor._open_camera_menu()
	await get_tree().process_frame
	_check(editor._camera_menu.row_count() == 1,
		"an empty camera menu has the Add camera row")
	_check(editor._camera_menu.empty_text() == "No scene cameras. Add one to look through it.",
		"the empty camera message is exact")
	editor._camera_menu.close()


func _test_workspace_switch_with_open_surfaces() -> void:
	var main = await _boot_main(915, 412)
	var editor = main._editor
	editor.set_workspace("shading")
	await get_tree().process_frame
	editor._toggle_workspace_panel()          # no-op at 915, reserved
	editor.set_workspace("rig")
	await get_tree().process_frame
	_check(editor._workspace_panel.content() == editor._rig_panel,
		"switching workspace swaps the panel content")
	editor._toggle_scene_panel("scene")       # nothing in rig; must not open a scene panel
	await get_tree().process_frame
	_check(editor._workspace_panel.mode() == editor._workspace_panel.Mode.RESERVED,
		"a scene overlay request never replaces a reserved rig panel")

	# A modal closes before the workspace changes on Back.
	editor.set_workspace("scene")
	editor._open_add_sheet()
	await get_tree().process_frame
	_check(editor._overlay.has_modal(), "the add sheet is open")
	editor.handle_back()
	await get_tree().process_frame
	_check(not editor._overlay.has_modal() and editor.workspace() == "scene",
		"Back closes the modal before switching workspace")

	# More workspaces -> menu -> Back closes the menu, not the project.
	editor._workspace_bar.more_button().pressed.emit()
	await get_tree().process_frame
	editor.handle_back()
	await get_tree().process_frame
	_check(not editor.workspace_menu_open() and editor.workspace() == "scene",
		"Back closes the secondary-workspace menu first")

func _test_back_precedence() -> void:
	var main = await _boot_main(600, 960)
	var editor = main._editor
	editor.set_workspace("shading")
	await get_tree().process_frame
	_check(editor._workspace_panel.mode() == editor._workspace_panel.Mode.OVERLAY,
		"600 dp uses the overlay panel")
	editor.handle_back()
	await get_tree().process_frame
	_check(editor._workspace_panel.mode() == editor._workspace_panel.Mode.HIDDEN and
		editor.workspace() == "shading", "Back closes the panel before the workspace")
	editor.handle_back()
	await get_tree().process_frame
	_check(editor.workspace() == "scene", "Back returns to Scene from another workspace")

func _test_desktop_shell() -> void:
	var main = await _boot_main(1280, 800)
	var editor = main._editor
	editor.set_layout_mode("desktop")
	await get_tree().process_frame
	_check(editor._workspace_bar.size.y >= 31.5 and editor._workspace_bar.size.y <= 32.5,
		"desktop top bar is 32 dp")
	_check(editor._context_bar.size.y >= 35.5 and editor._context_bar.size.y <= 36.5,
		"desktop context row is 36 dp")
	_check(editor._transport_bar.size.y >= 31.5 and editor._transport_bar.size.y <= 32.5,
		"desktop transport is 32 dp")
	_check(not editor._instrumentation.visible, "desktop strip is off by default")
	for id in ["scene", "shading", "animate"]:
		var tab: Button = editor._workspace_bar.workspace_tab(id)
		_check(tab != null and absf(tab.custom_minimum_size.y - 28.0) < 0.5,
			"desktop %s tab is 28 dp" % id)
	_check(absf(editor._workspace_bar.more_button().custom_minimum_size.y - 28.0) < 0.5,
		"desktop More is 28 dp")
	editor._workspace_bar.more_button().pressed.emit()
	await get_tree().process_frame
	_check(editor._workspace_menu.row_count() == 2,
		"desktop keeps the two-row secondary menu")
	editor._workspace_menu.close()
	editor._workspace_bar.action_button("menu").pressed.emit()
	await get_tree().process_frame
	_check(editor._project_menu.row_button("instrumentation") != null,
		"desktop exposes the instrumentation row")
	editor._project_menu.close()

func _test_version_strings() -> void:
	_check(SettingsPanelScript.APP_VERSION == "0.1.5", "settings reports 0.1.5")
	var manifest := FileAccess.get_file_as_string("res://android/app/AndroidManifest.xml")
	_check(manifest.contains('android:versionCode="2"'), "manifest versionCode is 2")
	_check(manifest.contains('android:versionName="0.1.5"'), "manifest versionName is 0.1.5")
	var repo_root := ProjectSettings.globalize_path("res://").simplify_path().get_base_dir()
	var workflow := FileAccess.get_file_as_string(
		repo_root.path_join(".github/workflows/build.yml"))
	_check(workflow.contains("-Pexport_version_code=2"), "CI exports versionCode 2")
	_check(workflow.contains("-Pexport_version_name=0.1.5"), "CI exports versionName 0.1.5")
	_check(workflow.contains("Kinema-Studio-0.1.5-arm64-debug"), "CI artifact uses 0.1.5")


func _finish() -> void:
	if _failures.is_empty():
		print("SUITE RESULT: PASS (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		printerr("SUITE RESULT: FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
