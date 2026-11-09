extends Node
## Layout matrix for the workspace shell. Runs headless and under xvfb.
##
## Nine window sizes x three workbench modes prove the shell applies the mode
## it was asked for, keeps the exact band heights, never overflows
## horizontally, keeps every visible action a 44 dp target in the touch
## arrangements, and gives the stage and the workspace panel their real space.
##
## Desktop is a real arrangement at every size: it shrinks to fit on a small
## window and never falls back to another mode. The touch arrangements are
## measured directly; Desktop buttons are mouse-sized and carry the product's
## `qa_hit_exempt` marker, so the 44 dp floor is asserted for compact/studio.

const SIZES := [
	Vector2i(360, 640),
	Vector2i(412, 915),
	Vector2i(600, 960),
	Vector2i(915, 412),
	Vector2i(800, 360),
	Vector2i(1024, 768),
	Vector2i(1280, 800),
	Vector2i(1440, 900),
	Vector2i(2560, 1600),
]
const MODES := ["compact", "studio", "desktop"]
const LayoutMath = preload("res://src/app/layout_math.gd")
const PROJECT_TITLE := "Layout Matrix"
const PANEL_THRESHOLD := 768.0
const STAGE_FLOOR := 480.0
const TIMELINE_FLOOR := 140.0
const HIT_FLOOR := 43.5
const DESKTOP_FIT_MIN := Vector2(960.0, 600.0)

var _failures: Array[String] = []
var _headless := false
var _buttons_checked := 0


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("LAYOUT FAIL: " + message)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	await get_tree().process_frame
	var packed: PackedScene = load("res://src/app/main.tscn")
	var main: Control = packed.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	# The browser arranges itself from its own width, independent of the
	# workbench mode, so it is checked at one phone and one wide size.
	await _resize(main, Vector2i(360, 640))
	_check(main._home.layout_for_width(360.0) == "list", "home uses a list at 360 dp")
	_check_no_overflow(main._home, "home 360x640")
	await _resize(main, Vector2i(1280, 800))
	_check(main._home.layout_for_width(1280.0) == "table", "home uses a table at 1280 dp")
	_check_no_overflow(main._home, "home 1280x800")

	main._on_new_project_requested(PROJECT_TITLE, "study")
	for _i in 4:
		await get_tree().process_frame
	var editor = main._editor
	_check(editor != null, "the editor opens for the layout matrix")
	if editor == null:
		_finish()
		return
	# The creation toast is transient chrome, not part of the arrangement.
	editor._overlay.clear_toast()
	Prefs.set_value("editor.workspace", "scene")

	for size in SIZES:
		await _resize(main, size)
		for mode in MODES:
			editor.set_layout_mode(mode)
			await get_tree().process_frame
			await get_tree().process_frame
			main.refresh_layout_scale()
			await get_tree().process_frame
			var label := "%dx%d %s" % [size.x, size.y, mode]
			_check(editor.layout_mode() == mode, label + ": the layout mode applies")
			# The band heights below describe the Scene arrangement; earlier
			# iterations end in Animate, where the shared transport is hidden.
			editor.set_workspace("scene")
			await get_tree().process_frame
			var top_h := 44.0 if mode != "desktop" else 32.0
			var context_h := 44.0 if mode != "desktop" else 36.0
			var transport_h := 44.0 if mode != "desktop" else 32.0
			_check(absf(editor._workspace_bar.size.y - top_h) < 1.0,
				label + ": top bar height")
			_check(absf(editor._context_bar.size.y - context_h) < 1.0,
				label + ": context row height")
			_check(absf(editor._transport_bar.size.y - transport_h) < 1.0,
				label + ": transport height in Scene")
			_check(editor._stage_host.size.x > 0.0 and editor._stage_host.size.y > 0.0,
				label + ": the stage owns real pixels")
			_check(not editor._stage_host.is_ancestor_of(editor._timeline),
				label + ": no timeline node over the stage in Scene")

			# Workspace-specific panel rules at every size. The threshold is
			# measured on the shell's real canvas: Desktop fit can make a small
			# window wider in logical dp than its physical size.
			for workspace_id in ["scene", "shading", "rig", "render"]:
				editor.set_workspace(workspace_id)
				await get_tree().process_frame
				if workspace_id != "scene":
					var wide: bool = editor.size.x >= PANEL_THRESHOLD
					var expected_mode: int = editor._workspace_panel.Mode.RESERVED if wide \
						else editor._workspace_panel.Mode.OVERLAY
					_check(editor._workspace_panel.mode() == expected_mode,
						label + "/" + workspace_id +
						": panel mode follows the 768 dp threshold")
					if wide:
						_check(editor._stage_host.size.x >= STAGE_FLOOR,
							label + "/" + workspace_id +
							": stage keeps 480 dp beside the panel")
				else:
					_check(editor._workspace_panel.mode() ==
						editor._workspace_panel.Mode.HIDDEN,
						label + ": scene has no reserved panel")

			# Animate plot budget.
			editor.set_workspace("animate")
			await get_tree().process_frame
			_check(editor._animate_pane.visible, label + ": animate pane visible")
			_check(not editor._stage_host.visible or
				editor._animate_pane.get_global_rect().position.y >=
				editor._stage_host.get_global_rect().end.y - 0.5,
				label + ": animate pane below the stage")
			_check(editor._timeline.size.y >= TIMELINE_FLOOR,
				label + ": animate keeps a usable timeline")
			for button in editor._workspace_bar.find_children(
					"*", "BaseButton", true, false) + \
					editor._context_bar.find_children("*", "BaseButton", true, false) + \
					editor._transport_bar.find_children("*", "BaseButton", true, false):
				if button.is_visible_in_tree():
					var floor_h := 28.0 if mode == "desktop" else HIT_FLOOR
					_check(button.size.y >= floor_h - 0.5,
						label + ": " + str(button.name) + " hit target")

			# Headless cannot render a scaled Desktop canvas; the xvfb run
			# proves the pixels. Both runs still prove the mode resolves.
			var scaled_desktop: bool = _headless and mode == "desktop" and \
				float(main.layout.get("fit", 1.0)) < 1.0
			if scaled_desktop:
				print("LAYOUT SKIP (headless scaled desktop): %dx%d desktop" % [
					size.x, size.y])
			else:
				_check_no_overflow(editor, label)
				_check_no_overflow(main, label)
				_check_hit_targets(editor, mode, label)
			if mode == "desktop" and size.x < 960:
				_check(float(main.layout.get("fit", 1.0)) < 1.0,
					label + ": desktop shrinks to fit")
				var logical: Vector2 = main.layout.get("logical_after", Vector2.ZERO)
				_check(logical.x >= DESKTOP_FIT_MIN.x - 1.0 and
					logical.y >= DESKTOP_FIT_MIN.y - 1.0,
					label + ": desktop keeps a 960x600 logical canvas")
				_check(bool(main.layout.get("user_scale_enabled", false)),
					label + ": desktop fit keeps UI scale enabled")
				_check(editor.fit_percent() < 100.0,
					label + ": the editor reports the fit percentage")
			print("LAYOUT OK: " + label)

	# The secondary-workspace menu is capped at 280 dp and never overflows even
	# on the narrowest phone and the shortest landscape window. The top bar
	# itself must still fit its width with a named secondary workspace.
	editor.set_workspace("scene")
	for menu_size in [Vector2i(360, 640), Vector2i(800, 360)]:
		await _resize(main, menu_size)
		editor.set_layout_mode("studio")
		await get_tree().process_frame
		await get_tree().process_frame
		main.refresh_layout_scale()
		await get_tree().process_frame
		var menu_label := "%dx%d workspace menu" % [menu_size.x, menu_size.y]
		_check(editor._workspace_bar.get_combined_minimum_size().x <=
			float(menu_size.x) + 0.5,
			menu_label + ": the top bar fits the width")
		for workspace_id in ["rig", "render"]:
			editor.set_workspace(workspace_id)
			await get_tree().process_frame
			_check(editor._workspace_bar.get_combined_minimum_size().x <=
				float(menu_size.x) + 0.5,
				menu_label + ": the named top bar fits with " + workspace_id)
		editor.set_workspace("scene")
		await get_tree().process_frame
		editor._workspace_bar.more_button().pressed.emit()
		await get_tree().process_frame
		_check_no_overflow(editor._workspace_menu, menu_label)
		# MenuPanel is the full-rect overlay; its surface is the floating
		# panel that must fit, not the scrim that catches the outside tap.
		_check(editor._workspace_menu._panel.size.x <= 280.0,
			menu_label + ": secondary menu <= 280 dp")
		_check(editor._workspace_menu.row_count() == 2,
			menu_label + ": the secondary menu has two rows")
		_check(editor._workspace_menu._header.custom_minimum_size.y <= 32.5,
			menu_label + ": the secondary menu header is 32 dp")
		for row_id in ["rig", "render"]:
			var row: Button = editor._workspace_menu.row_button(row_id)
			_check(row != null and row.custom_minimum_size.y >= HIT_FLOOR,
				menu_label + ": the " + row_id + " row keeps the 44 dp floor")
		_check(editor._workspace_menu.is_open(), menu_label + ": the menu opens")
		editor._workspace_menu.close()
		await get_tree().process_frame

	# The project menu is taller than the 800x360 viewport at studio scale.
	# Its fixed header stays put and the rows scroll, so Close project remains
	# reachable instead of clipping below the window.
	await _resize(main, Vector2i(800, 360))
	editor.set_layout_mode("studio")
	await get_tree().process_frame
	await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame
	editor.set_workspace("scene")
	await get_tree().process_frame
	editor._workspace_bar.action_button("menu").pressed.emit()
	await get_tree().process_frame
	var project = editor._project_menu
	var project_label := "800x360 project menu"
	_check(project.is_open(), project_label + ": the menu opens")
	_check(project._panel.size.y <= 360.0 - 16.0 + 0.5,
		project_label + ": the panel fits the viewport")
	_check(project._header.custom_minimum_size.y <= 32.5,
		project_label + ": the header stays fixed at 32 dp")
	var scroll: ScrollContainer = project._scroll
	_check(scroll != null, project_label + ": the rows live in a scroll container")
	if scroll != null:
		var close_row: Button = project.row_button("close")
		_check(close_row != null, project_label + ": the close row exists")
		if close_row != null:
			_check(scroll.get_v_scroll_bar().max_value > scroll.size.y + 0.5,
				project_label + ": the rows overflow and scroll")
			scroll.ensure_control_visible(close_row)
			await get_tree().process_frame
			var close_rect := close_row.get_global_rect()
			var panel_rect: Rect2 = project._panel.get_global_rect()
			_check(close_rect.position.y >= panel_rect.position.y and
				close_rect.end.y <= panel_rect.end.y + 0.5,
				project_label + ": Close project scrolls into view")
	project.close()
	await get_tree().process_frame

	# The 200% interface is the worst case for the touch shell: every control
	# keeps its dp minimum while the logical canvas shrinks. Headless cannot
	# apply the scale, so those pixel checks run under xvfb only.
	Prefs.set_value("display.user_scale", 2.0)
	for scale_spec in [
		{"size": Vector2i(1440, 900), "mode": "desktop"},
		{"size": Vector2i(1280, 800), "mode": "studio"},
	]:
		var scaled: Dictionary = scale_spec
		await _resize(main, scaled["size"])
		editor.set_layout_mode(str(scaled["mode"]))
		await get_tree().process_frame
		await get_tree().process_frame
		main.refresh_layout_scale()
		await get_tree().process_frame
		var scaled_label := "%dx%d %s at 200%%" % [
			scaled["size"].x, scaled["size"].y, scaled["mode"]
		]
		_check(editor.layout_mode() == str(scaled["mode"]),
			scaled_label + ": the layout mode applies")
		_check(editor._workspace_bar.size.y >= (31.5 if scaled["mode"] == "desktop" else 43.5),
			scaled_label + ": the top bar keeps its band height")
		if _headless:
			print("LAYOUT SKIP (headless 200% scale): " + scaled_label)
		else:
			_check_no_overflow(editor, scaled_label)
			_check_no_overflow(main, scaled_label)
			_check_hit_targets(editor, str(scaled["mode"]), scaled_label)
		print("LAYOUT OK: " + scaled_label)
	Prefs.set_value("display.user_scale", 1.0)

	# Leave the machine as the matrix found it, and the project folder behind.
	Prefs.set_value("display.layout", "auto")
	Prefs.set_value("editor.workspace", "scene")
	Prefs.set_value("display.user_scale", 1.0)
	await _resize(main, Vector2i(1280, 800))
	var project_id: String = editor.doc.project_id
	editor._leave(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(project_id != "" and Store.delete_project(project_id),
		"the layout matrix project is deleted")
	# Coverage guard: the walker must really visit composed buttons, not skip
	# them. A regression to a non-Button-only sweep lands here at zero.
	_check(_buttons_checked > 0,
		"the hit-target walker measures laid-out BaseButtons (%d checked)" % _buttons_checked)
	print("LAYOUT BUTTONS: %d laid-out BaseButton targets checked" % _buttons_checked)
	_finish()


# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

func _resize(main: Control, size: Vector2i) -> void:
	get_window().size = size
	for _i in 3:
		await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame


## Horizontal overflow only. Portrait vertical scrolling is legal, so the
## walker never asserts on the vertical axis.
func _check_no_overflow(root: Control, context: String) -> void:
	var width := root.get_viewport_rect().size.x
	for child in root.get_children():
		if child is Control:
			_walk_overflow(child, width, context, false)


func _walk_overflow(control: Control, width: float, context: String, clipped: bool) -> void:
	if not control.is_visible_in_tree():
		return
	var rect := control.get_global_rect()
	if not clipped and rect.size != Vector2.ZERO:
		if rect.position.x < -2.0 or rect.end.x > width + 2.0:
			_fail("%s: %s spans x %.1f..%.1f on a %.0f dp canvas" % [
				context, control.get_path(), rect.position.x, rect.end.x, width
			])
	# A clip or scroll container owns the overflow inside it, so its subtree is
	# not a defect even when it is wider than the canvas.
	var next_clipped := clipped or control.clip_contents or control is ScrollContainer
	for child in control.get_children():
		if child is Control:
			_walk_overflow(child, width, context, next_clipped)


## Every visible action keeps the 44 dp touch floor. Buttons are checked twice:
## at their authored minimum (what the control promises) and at their real
## laid-out rect (what a container actually gave them), so a container that
## squeezes a button cannot pass on the minimum alone. The matrix settles its
## frames before walking, so a visible button with a real rect has been laid
## out. The exemptions are the product's own: `qa_hit_exempt` marks desktop
## menu-bar chrome, which is a mouse surface, and a MenuBar's children are the
## same chrome.
func _check_hit_targets(root: Control, mode: String, context: String) -> void:
	for node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		if not _is_interactive(control):
			continue
		if control.has_meta("qa_hit_exempt"):
			continue
		if _inside_window(control, root):
			continue
		if mode == "desktop" and control.get_parent() is MenuBar:
			continue
		var width := maxf(control.size.x, control.custom_minimum_size.x)
		var height := maxf(control.size.y, control.custom_minimum_size.y)
		if width < HIT_FLOOR or height < HIT_FLOOR:
			_fail("%s: %s is %.1fx%.1f, below the 44 dp floor" % [
				context, control.get_path(), width, height])
		if control is BaseButton:
			_buttons_checked += 1
			# The laid-out size, not the authored minimum: a container that
			# squeezes a button must fail even when its minimum is 44 dp.
			if control.size != Vector2.ZERO and (control.size.x < HIT_FLOOR or
					control.size.y < HIT_FLOOR):
				_fail("%s: %s lays out at %.1fx%.1f, below the 44 dp floor" % [
					context, control.get_path(), control.size.x, control.size.y
				])


## A tap/drag surface is a Button or a control that accepts pointer input:
## text fields and ranges, controls marked `qa_hit_target` (media rows) or a
## script that overrides `_gui_input` (the clip-lane canvas). Scroll-bar
## internals are engine chrome, not an authored touch target.
func _is_interactive(control: Control) -> bool:
	if control is ScrollBar:
		return false
	if control is BaseButton:
		return true
	if control is LineEdit or control is TextEdit or control is Range:
		return true
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return false
	if control.has_meta("qa_hit_target"):
		return true
	var script = control.get_script()
	return script != null and script.has_method("_gui_input")


func _inside_window(node: Control, root: Control) -> bool:
	var parent := node.get_parent()
	while parent != null and parent != root:
		if parent is Window or parent is PopupMenu:
			return true
		parent = parent.get_parent()
	return false


func _finish() -> void:
	if _failures.is_empty():
		print("LAYOUT RESULT: PASS")
		print("SUITE RESULT: PASS")
	else:
		printerr("LAYOUT RESULT: %d FAILURE(S)" % _failures.size())
		printerr("SUITE RESULT: FAIL (%d failures)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
