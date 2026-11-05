extends Control
## W1 shell contract: layout/workspace API, WorkspaceBar, workspace and project
## menus, the context row and the transport.
##
## The suite boots the real application shell at the sizes the spec budgets for
## and reads the live controls. It never fabricates a control or a state.

const PROJECT_TITLE := "Shell suite"

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
	await _test_context_bar_overflow_and_icons()
	await _test_transport()
	_finish()


func _boot_main(width: int, height: int) -> Control:
	get_window().size = Vector2i(width, height)
	await get_tree().process_frame
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
		_main = null
	Prefs.set_value("editor.workspace", "scene")
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
	_check(bar.workspace_chip().text == "Scene", "the chip shows the current workspace name")
	_check(bar.workspace_chip().custom_minimum_size.x >= 96.0,
		"the chip keeps the 96 dp minimum")
	_check(not bar.visible_action_ids().has("render"), "no render action lives in the top bar")

	bar.workspace_chip().pressed.emit()
	await get_tree().process_frame
	_check(editor.workspace_menu_open(), "the chip opens the workspace menu")
	var menu = editor._workspace_menu
	_check(menu.row_count() == 5, "the workspace menu has exactly five rows")
	var ids := ["scene", "shading", "rig", "animate", "render"]
	for id in ids:
		var row: Button = menu.row_button(id)
		_check(row != null and row.custom_minimum_size.y >= 52.0,
			"workspace row %s is at least 52 dp" % id)
		_check(row.get_meta("workspace_row", "") == id,
			"workspace row %s carries its id" % id)
	_check(menu.row_button("scene").button_pressed, "the current workspace row is checked")

	menu.row_button("animate").pressed.emit()
	await get_tree().process_frame
	_check(editor.workspace() == "animate", "selecting a row switches workspace")
	_check(not editor.workspace_menu_open(), "selecting a row closes the menu")
	_check(bar.workspace_chip().text == "Animate", "the chip follows the workspace")

	# Project menu order and rows.
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


func _finish() -> void:
	if _failures.is_empty():
		print("SUITE RESULT: PASS (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		printerr("SUITE RESULT: FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
