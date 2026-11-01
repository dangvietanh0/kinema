extends Node
## Layout matrix. Runs headless and under xvfb.
##
## Nine window sizes x three workbench modes prove the shell applies the mode
## it was asked for, never overflows horizontally, keeps every visible action a
## 44 dp target in the touch arrangements, and keeps Desktop Desktop: shrunk to
## fit on a small screen, never fallen back to another mode.
##
## Under --headless Main forcibly keeps content_scale_factor at 1.0, so the
## pixel geometry of a scaled Desktop canvas cannot honestly be measured there;
## those size/mode pairs still assert the fit maths and print LAYOUT SKIP
## instead of pretending the pixels were checked. The xvfb run covers them.

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
const HIT_FLOOR := 43.5
const PROJECT_TITLE := "Layout Matrix"
const SCENE_PANEL_MIN := 480.0
const SCENE_EXPANDED_MIN := 760.0
const STAGE_FLOOR := Vector2(560.0, 230.0)
const FOLDED_TIMELINE := 56.0

var _failures: Array[String] = []
var _headless := false


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
	Prefs.set_value("editor.scene_panel_expanded", true)

	for size in SIZES:
		await _resize(main, size)
		for mode in MODES:
			editor.set_workspace_mode(mode)
			await get_tree().process_frame
			await get_tree().process_frame
			main.refresh_layout_scale()
			await get_tree().process_frame
			var label := "%dx%d %s" % [size.x, size.y, mode]
			var info: Dictionary = main.layout
			_check(editor.workspace_mode() == mode, label + ": the workbench mode applies")
			_check(str(info.get("mode", "")) == mode, label + ": the resolved layout reports the mode")
			_check(not editor._timeline_visible, label + ": the dope sheet starts folded")
			var panel_rail = editor.get("_panel_rail")
			var rail_expected: bool = mode != "compact" and editor.size.x >= 480.0
			if mode == "compact":
				_check(panel_rail == null or not panel_rail.visible,
					label + ": compact uses the bottom bar instead of a panel rail")
				_check(not editor._top_bar._panels_button.visible,
					label + ": compact keeps panels in the bottom bar")
			elif rail_expected:
				_check(panel_rail != null and panel_rail.visible,
					label + ": the stage keeps a right panel rail")
				_check(not editor._top_bar._panels_button.visible,
					label + ": the rail replaces the top-bar panel toggle")
				if panel_rail != null:
					_check(absf(panel_rail.size.x - 44.0) < 1.0,
						label + ": the panel rail is 44 dp wide")
			else:
				_check(panel_rail == null or not panel_rail.visible,
					label + ": a sub-minimum stage folds the rail into the top bar")
				if mode == "studio":
					_check(editor._top_bar._panels_button.visible,
						label + ": the top-bar toggle still opens the flyout")
				else:
					# Headless cannot apply the Desktop fit, so this is a 412 dp
					# Desktop canvas that a real window would scale to 960. The
					# menu bar keeps the panel routes there.
					_check(editor._top_bar.mode() == "desktop",
						label + ": desktop keeps its menu-bar panel routes")
			var scene_expected: bool = mode != "compact" and editor.size.x >= SCENE_PANEL_MIN
			var scene_column = editor.get("_scene_column")
			var outliner_panel = editor.get("_outliner_panel")
			var scene_rail = editor.get("_scene_rail")
			_check(scene_column != null and outliner_panel != null and scene_rail != null,
				label + ": the scene column, rail and outliner exist")
			if scene_column != null and outliner_panel != null and scene_rail != null:
				_check(scene_column.visible == scene_expected,
					label + ": the persistent scene column follows the mode and minimum width")
				if scene_expected:
					_check(outliner_panel.get_parent() == scene_column,
						label + ": the single outliner mounts in the scene column")
					if editor.size.x >= SCENE_EXPANDED_MIN:
						var expected_width := clampf(editor.size.x * 0.20, 196.0, 280.0)
						_check(absf(scene_column.size.x - expected_width) < 1.0,
							label + ": the expanded scene panel uses the clamped 20 percent width")
						_check(outliner_panel.visible and not scene_rail.visible,
							label + ": the expanded panel shows the tree instead of the rail")
					else:
						_check(absf(scene_column.size.x - 44.0) < 1.0,
							label + ": a sub-760 dp stage keeps the 44 dp scene rail")
						_check(scene_rail.visible and not outliner_panel.visible,
							label + ": the rail replaces the expanded panel")
					_check(not editor._drawer_open and not editor._drawer_scrim.visible,
						label + ": the scene panel installs no scrim and no flyout")
				else:
					_check(outliner_panel.get_parent() == editor._dock_box,
						label + ": compact and sub-480 shells keep the outliner in the dock")
			_check(editor._timeline_panel.get_parent() == editor._viewport_host,
				label + ": the timeline overlays the stage host")
			_check(absf(editor._timeline_panel.size.y - FOLDED_TIMELINE) < 1.0,
				label + ": the folded timeline is exactly a 56 dp transport")
			if mode != "compact":
				_check(not editor._drawer_open, label + ": the panel flyout starts closed")
				var scene_reserve: float = scene_column.size.x if scene_expected else 0.0
				_check(editor._view.size.x >= size.x - 160.0 - scene_reserve,
					label + ": the viewport owns the stage after the rails and scene column")
				_check(editor._view.size.y >= 140.0,
					label + ": the folded timeline leaves a usable 3D height")
			if size == Vector2i(915, 412) and mode == "studio":
				_check(editor._view.size.x >= STAGE_FLOOR.x and editor._view.size.y >= STAGE_FLOOR.y,
					label + ": the live stage keeps at least 560x230 with the scene panel open")
			# Headless cannot render a scaled Desktop canvas, so its pixel
			# assertions would be fiction. The fit maths below still run.
			var scaled_desktop: bool = _headless and mode == "desktop" and float(info.get("fit", 1.0)) < 1.0
			if scaled_desktop:
				print("LAYOUT SKIP (headless scaled desktop): %dx%d desktop" % [size.x, size.y])
			else:
				_check_no_overflow(editor, label)
				_check_no_overflow(main, label)
				_check_hit_targets(editor, mode, label)
			if mode == "desktop" and size.x < 960:
				_check(float(info.get("fit", 1.0)) < 1.0, label + ": desktop shrinks to fit")
				var logical: Vector2 = info.get("logical_after", Vector2.ZERO)
				_check(logical.x >= 959.0 and logical.y >= 599.0, label + ": desktop keeps a 960x600 logical canvas")
				_check(bool(info.get("user_scale_enabled", false)), label + ": desktop fit keeps UI scale enabled")
				_check(editor.fit_percent() < 100.0, label + ": the editor reports the fit percentage")
			print("LAYOUT OK: " + label)

	# The scene panel and the timeline overlay are the point of this contract.
	# They are measured at Desktop, at the 915x412 Studio stage floor, and on
	# the sub-760 and sub-480 boundaries where the scene panel becomes a rail
	# or returns to the dock.
	print("LAYOUT STEP: scene panel and timeline overlay")
	Prefs.set_value("editor.scene_panel_expanded", true)
	await _resize(main, Vector2i(1440, 900))
	editor.set_workspace_mode("desktop")
	await get_tree().process_frame
	await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame
	_check(absf(editor._scene_column.size.x - 280.0) < 1.0,
		"1440 desktop expands the scene panel to its 280 dp cap")
	_check(editor._outliner_panel.get_parent() == editor._scene_column,
		"desktop mounts the one outliner in the scene column")
	_check(not editor._drawer_scrim.visible and not editor._drawer_open,
		"the expanded scene panel has no scrim and no focus trap")
	_check_no_overflow(editor, "1440x900 desktop scene panel")
	_check_hit_targets(editor, "desktop", "1440x900 desktop scene panel")

	var overlay_host: Control = editor._viewport_host
	var view_before_overlay: Vector2 = editor._view.size
	editor._timeline_visible = true
	editor._sync_timeline_visibility()
	await get_tree().process_frame
	await get_tree().process_frame
	var overlay_stage_h: float = overlay_host.size.y
	var dope_budget := minf(320.0, maxf(180.0, overlay_stage_h * 0.55))
	dope_budget = minf(dope_budget, maxf(FOLDED_TIMELINE, overlay_stage_h - 96.0))
	_check(absf(editor._timeline_panel.size.y - dope_budget) < 1.0,
		"the dope overlay uses the clamped 55 percent budget")
	_check(is_equal_approx(editor._view.size.x, view_before_overlay.x) and
		is_equal_approx(editor._view.size.y, view_before_overlay.y),
		"opening the timeline does not resize the 3D view")
	_check(editor._view.size.y - editor._timeline_panel.size.y >= 95.0,
		"the open dope overlay leaves at least 96 dp of stage visible")
	_check(absf(editor._timeline_panel.get_global_rect().end.y -
		overlay_host.get_global_rect().end.y) <= 1.0,
		"the timeline overlay anchors to the stage bottom")
	_check(absf(editor._timeline._transport_panel.get_global_rect().end.y -
		overlay_host.get_global_rect().end.y) <= 1.0,
		"the transport row is the bottom edge of the stage")
	editor._timeline.set_mode("graph")
	editor._sync_timeline_visibility()
	await get_tree().process_frame
	await get_tree().process_frame
	var graph_budget := minf(360.0, maxf(200.0, overlay_host.size.y * 0.66))
	graph_budget = minf(graph_budget, maxf(FOLDED_TIMELINE, overlay_host.size.y - 96.0))
	_check(absf(editor._timeline_panel.size.y - graph_budget) < 1.0,
		"the graph overlay uses the taller 66 percent budget")
	_check(editor._view.size.y - editor._timeline_panel.size.y >= 95.0,
		"the open graph overlay still leaves a visible stage")
	editor._timeline.set_mode("dope")
	editor._timeline_visible = false
	editor._sync_timeline_visibility()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(absf(editor._timeline_panel.size.y - FOLDED_TIMELINE) < 1.0,
		"folding the timeline returns it to exactly 56 dp")
	_check(is_equal_approx(editor._view.size.x, view_before_overlay.x) and
		is_equal_approx(editor._view.size.y, view_before_overlay.y),
		"folding the timeline restores the same 3D view size")

	editor.set_scene_panel_expanded(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(absf(editor._scene_column.size.x - 44.0) < 1.0 and editor._scene_rail.visible,
		"the collapse chevron turns the scene panel into the 44 dp rail")
	_check(not bool(Prefs.get_value("editor.scene_panel_expanded", true)),
		"the collapsed scene panel persists the preference")
	editor._apply_shell()
	await get_tree().process_frame
	_check(editor._scene_rail.visible,
		"the collapsed scene panel survives _apply_shell")
	Prefs.load_settings()
	editor._apply_shell()
	await get_tree().process_frame
	_check(editor._scene_rail.visible,
		"the collapsed scene panel survives a preference reload")
	Prefs.set_value("editor.scene_panel_expanded", true)
	editor._apply_shell()
	await get_tree().process_frame

	await _resize(main, Vector2i(600, 960))
	editor.set_workspace_mode("studio")
	await get_tree().process_frame
	await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame
	_check(absf(editor._scene_column.size.x - 44.0) < 1.0 and editor._scene_rail.visible,
		"a 600 dp studio stage keeps the scene rail")
	_check(editor._scene_rail_expand.disabled,
		"the rail explains why it cannot expand into a stage below 320 dp")
	_check_no_overflow(editor, "600x960 studio scene rail")

	await _resize(main, Vector2i(700, 960))
	editor.set_workspace_mode("studio")
	await get_tree().process_frame
	await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame
	_check(not editor._scene_rail_expand.disabled,
		"a 700 dp studio stage can expand without starving the stage")
	Prefs.set_value("editor.scene_panel_expanded", false)
	editor._apply_shell()
	await get_tree().process_frame
	editor._scene_rail_expand.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._outliner_panel.visible and editor._outliner_panel.get_parent() == editor._scene_column,
		"the rail expand action transiently opens the scene panel")
	_check(not bool(Prefs.get_value("editor.scene_panel_expanded", true)),
		"a transient sub-760 expansion never overwrites the stored preference")
	_check_no_overflow(editor, "700x960 studio transient scene panel")
	Prefs.set_value("editor.scene_panel_expanded", true)
	editor._apply_shell()
	await get_tree().process_frame

	# The expansion surfaces: clip lane, media lanes and the rig tab. They are
	# laid out at the three sizes the expansion targets, in the two touch
	# arrangements, with the lanes open and the rig page active.
	for size in [Vector2i(412, 915), Vector2i(915, 412), Vector2i(1440, 900)]:
		await _resize(main, size)
		for mode in ["compact", "studio"]:
			editor.set_workspace_mode(mode)
			await get_tree().process_frame
			await get_tree().process_frame
			main.refresh_layout_scale()
			await get_tree().process_frame
			var label := "%dx%d %s expansion" % [size.x, size.y, mode]
			var clip_lane = editor.get("_clip_lane")
			var media_lanes = editor.get("_media_lanes")
			var rig_panel = editor.get("_rig_panel")
			_check(clip_lane != null and media_lanes != null and rig_panel != null,
				label + ": clip lane, media lanes and rig panel are mounted")
			editor._timeline_visible = true
			editor._sync_timeline_visibility()
			if media_lanes != null:
				media_lanes.set_collapsed(false)
			editor._set_compact_tab("rig")
			if editor._dock_overlay_mode():
				editor._open_drawer()
			await get_tree().process_frame
			await get_tree().process_frame
			_check(rig_panel != null and rig_panel.is_visible_in_tree(),
				label + ": the rig tab shows its panel")
			if mode == "studio" and editor._panel_rail != null and editor._panel_rail.visible:
				_check(editor._dock.get_global_rect().end.x <=
					editor._panel_rail.get_global_rect().position.x + 0.5,
					label + ": the flyout leaves the panel rail reachable")
				editor._panel_rail.page_button("inspector").pressed.emit()
				await get_tree().process_frame
				_check(editor._compact_tab == "inspector" and editor._drawer_open,
					label + ": the rail switches pages while the flyout is open")
				editor._panel_rail.page_button("rig").pressed.emit()
				await get_tree().process_frame
			_check_no_overflow(editor, label)
			_check_no_overflow(main, label)
			_check_hit_targets(editor, mode, label)
			if size == Vector2i(915, 412) and mode == "studio":
				# The scale slider is the point of this sheet; a landscape
				# phone must not hide it below a prose block and a scroll.
				editor._open_workspace_sheet()
				for _i in 6:
					await get_tree().process_frame
				var workspace = editor._workspace_sheet
				_check(workspace != null, label + ": workspace sheet opens")
				_check(workspace.get("_two_column") == true,
					label + ": workspace keeps two columns on a landscape phone")
				var slider = workspace._scale_control.slider
				var body: Rect2 = editor._overlay._body_scroll.get_global_rect()
				var slider_rect: Rect2 = slider.get_global_rect()
				_check(editor._overlay._body_scroll.scroll_vertical == 0,
					label + ": workspace does not need scrolling")
				_check(body.encloses(slider_rect),
					label + ": the UI scale slider is fully visible without scrolling")
				editor._overlay.close_modal(true)
				for _i in 2:
					await get_tree().process_frame
			print("LAYOUT OK: " + label)
			if media_lanes != null:
				media_lanes.set_collapsed(true)
			if editor._drawer_open:
				editor._close_drawer()
			editor._set_compact_tab("scene")
			editor._timeline_visible = false
			editor._sync_timeline_visibility()
			await get_tree().process_frame

	# Desktop on a portrait phone must stay Desktop, never fall back to Studio.
	for phone in [Vector2i(360, 640), Vector2i(412, 915)]:
		await _resize(main, phone)
		editor.set_workspace_mode("desktop")
		await get_tree().process_frame
		main.refresh_layout_scale()
		await get_tree().process_frame
		await get_tree().process_frame
		var label := "desktop %dx%d" % [phone.x, phone.y]
		_check(editor.workspace_mode() == "desktop", label + ": desktop never falls back")
		_check(str(main.layout.get("mode", "")) == "desktop", label + ": the shell resolves desktop")
		_check(editor._status_bar.visible, label + ": the desktop status bar stays visible")
		_check(editor._top_bar.size.y <= 38.0, label + ": the desktop menu bar stays at most 38 dp")

	# Desktop properties keep their actions on screen. The scroll body holds the
	# fields; Duplicate and Delete belong to a fixed footer, not to content that
	# can end a few pixels below the viewport.
	await _resize(main, Vector2i(1440, 900))
	editor.set_workspace_mode("desktop")
	await get_tree().process_frame
	await get_tree().process_frame
	main.refresh_layout_scale()
	editor._set_compact_tab("inspector")
	editor._open_drawer()
	for _i in 4:
		await get_tree().process_frame
	var actions = editor._inspector.get("_actions_row")
	_check(actions != null, "desktop properties expose their actions")
	if actions != null:
		_check(actions.get_parent() == editor._inspector._footer,
			"desktop properties keep actions in a fixed footer")
		var inspector_rect: Rect2 = editor._inspector.get_global_rect()
		_check(inspector_rect.encloses(actions.get_global_rect()),
			"desktop properties actions stay inside the panel")
	editor._close_drawer()
	await get_tree().process_frame

	# Leave the machine as the matrix found it, and the project folder behind.
	Prefs.set_value("display.layout", "auto")
	Prefs.set_value("display.user_scale", 1.0)
	main.refresh_layout_scale()
	await get_tree().process_frame
	var project_id: String = editor.doc.project_id
	editor._leave(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(project_id != "" and Store.delete_project(project_id), "the layout matrix project is deleted")
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


## Every visible action keeps the 44 dp touch floor. The exemptions are the
## product's own: `qa_hit_exempt` marks desktop menu-bar chrome, which is a
## mouse surface, and a MenuBar's children are the same chrome.
func _check_hit_targets(root: Control, mode: String, context: String) -> void:
	for node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null or not button.is_visible_in_tree():
			continue
		if button.has_meta("qa_hit_exempt"):
			continue
		if _inside_window(button, root):
			continue
		if mode == "desktop" and button.get_parent() is MenuBar:
			continue
		var width := maxf(button.size.x, button.custom_minimum_size.x)
		var height := maxf(button.size.y, button.custom_minimum_size.y)
		if width < HIT_FLOOR or height < HIT_FLOOR:
			_fail("%s: %s is %.1fx%.1f, below the 44 dp floor" % [context, button.get_path(), width, height])


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
	else:
		printerr("LAYOUT RESULT: %d FAILURE(S)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
