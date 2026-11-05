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


func _finish() -> void:
	if _failures.is_empty():
		print("SUITE RESULT: PASS (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		printerr("SUITE RESULT: FAIL (%d failures)" % _failures.size())
		get_tree().quit(1)
