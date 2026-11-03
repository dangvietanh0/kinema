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
const LayoutMath = preload("res://src/app/layout_math.gd")
const HIT_FLOOR := 43.5
const PROJECT_TITLE := "Layout Matrix"
const SCENE_PANEL_MIN := 480.0
const SCENE_EXPANDED_MIN := 760.0
const STAGE_FLOOR := Vector2(560.0, 230.0)
const FOLDED_TIMELINE := 56.0

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
			_check(editor._dock.size.x <= 400.5,
				label + ": the panel flyout respects the 400 dp cap")
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
					var body_kids: Array = editor._body.get_children()
					_check(body_kids.find(editor._center) < body_kids.find(scene_column),
						label + ": the scene column sits to the right of the stage")
					if panel_rail != null and panel_rail.visible:
						_check(body_kids.find(scene_column) < body_kids.find(panel_rail),
							label + ": the scene column sits left of the panel rail")
						_check(scene_column.get_global_rect().end.x <=
							panel_rail.get_global_rect().position.x + 0.5,
							label + ": the scene column ends before the panel rail")
					_check(scene_column.get_global_rect().position.x >=
						editor._viewport_host.get_global_rect().end.x - 0.5,
						label + ": the scene column hangs off the right edge of the stage")
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

	# A 200% interface is the worst case for the shell: the logical canvas
	# halves while every control keeps its dp minimum. Headless cannot render
	# the scaled canvas, so it prints LAYOUT SKIP and the xvfb run proves the
	# pixels; both runs still prove the mode resolves and the rail survives.
	Prefs.set_value("display.user_scale", 2.0)
	for scale_spec in [
		{"size": Vector2i(1440, 900), "mode": "desktop"},
		{"size": Vector2i(1280, 800), "mode": "studio"},
	]:
		var scaled: Dictionary = scale_spec
		await _resize(main, scaled["size"])
		editor.set_workspace_mode(str(scaled["mode"]))
		await get_tree().process_frame
		await get_tree().process_frame
		main.refresh_layout_scale()
		await get_tree().process_frame
		var scaled_label := "%dx%d %s at 200%%" % [
			scaled["size"].x, scaled["size"].y, scaled["mode"]
		]
		_check(editor.workspace_mode() == str(scaled["mode"]),
			scaled_label + ": the workbench mode applies")
		_check(not editor._timeline_visible,
			scaled_label + ": the dope sheet starts folded")
		var scaled_rail = editor.get("_panel_rail")
		_check(scaled_rail != null and scaled_rail.visible,
			scaled_label + ": the panel rail survives the double scale")
		if _headless:
			print("LAYOUT SKIP (headless 200% scale): " + scaled_label)
		else:
			_check_no_overflow(editor, scaled_label)
			_check_no_overflow(main, scaled_label)
			_check_hit_targets(editor, str(scaled["mode"]), scaled_label)
		print("LAYOUT OK: " + scaled_label)
	Prefs.set_value("display.user_scale", 1.0)

	# Populate the media lanes so the hit-target walk sees the real rows, not
	# only the empty-state labels. A 40 dp video row must fail this matrix.
	var media_system = editor.doc.media_system
	media_system.load_data({"media": {
		"audio": [{
			"id": "aud_layout", "name": "Layout scratch", "file": "audio/layout.wav",
			"start": 0.0, "trim_start": 0.0, "trim_end": 1.0,
		}],
		"video_refs": [{
			"id": "vid_layout", "name": "Layout reference", "dir": "video_refs/vid_layout",
			"fps": 12, "duration": 1.0, "width": 16, "height": 16,
			"start": 0.0, "opacity": 0.5, "visible": true,
		}],
	}}, editor.doc.project_dir)

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

	# The user override (2026-11-01) puts the persistent tree on the right
	# edge: rail, stage, scene column, then the 44 dp panel rail. Verified at
	# a wide desktop and at the short 915x412 Studio floor.
	print("LAYOUT STEP: scene column on the right edge")
	for size in [Vector2i(1280, 800), Vector2i(915, 412)]:
		await _resize(main, size)
		editor.set_workspace_mode("studio")
		await get_tree().process_frame
		await get_tree().process_frame
		main.refresh_layout_scale()
		await get_tree().process_frame
		var edge_label := "%dx%d right-edge scene column" % [size.x, size.y]
		_check(editor._scene_column.visible and editor._outliner_panel.visible,
			edge_label + ": the persistent column is open")
		var kids: Array = editor._body.get_children()
		_check(kids.find(editor._center) < kids.find(editor._scene_column) and
			kids.find(editor._scene_column) < kids.find(editor._panel_rail),
			edge_label + ": rail, stage, scene column, panel rail is the body order")
		_check(editor._viewport_host.get_global_rect().end.x <=
			editor._scene_column.get_global_rect().position.x + 0.5,
			edge_label + ": the stage ends before the scene column")
		_check(editor._scene_column.get_global_rect().end.x <=
			editor._panel_rail.get_global_rect().position.x + 0.5,
			edge_label + ": the scene column ends before the 44 dp panel rail")
		_check_no_overflow(editor, edge_label)
		print("LAYOUT OK: " + edge_label)
	await _resize(main, Vector2i(1440, 900))
	editor.set_workspace_mode("desktop")
	await get_tree().process_frame
	await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame

	var overlay_host: Control = editor._viewport_host
	var view_before_overlay: Vector2 = editor._view.size
	editor._timeline_visible = true
	editor._timeline.set_mode("dope")
	editor._sync_timeline_visibility()
	await get_tree().process_frame
	await get_tree().process_frame
	# M4: literal breakpoints, not a live recomputation of the same formula.
	# Contract: min(208, max(104, stage * 0.34)). The 104 dp floor binds below
	# ~306 dp (transport 56 + 48 dp sheet floor); the 208 dp cap binds above
	# ~612 dp. The stage-96 cap can only bind under the 104 floor and therefore
	# never wins at these independent heights.
	_check(absf(editor._timeline_overlay_budget(1000.0) - 208.0) < 0.5,
		"stage 1000 hits the 208 dp cap")
	_check(absf(editor._timeline_overlay_budget(500.0) - 170.0) < 0.5,
		"stage 500 uses 34 percent of its host")
	_check(absf(editor._timeline_overlay_budget(320.0) - 108.8) < 0.5,
		"stage 320 uses the literal 108.8 dp budget")
	_check(absf(editor._timeline_overlay_budget(200.0) - 104.0) < 0.5,
		"stage 200 keeps the 104 dp floor above the cap")
	var overlay_stage_h: float = overlay_host.size.y
	# Binding 2026-11-02 compact budget: min(208, max(104, stage * 0.34)).
	var dope_budget := minf(208.0, maxf(FOLDED_TIMELINE + 48.0, overlay_stage_h * 0.34))
	_check(editor._timeline_panel.size.y <= dope_budget + 0.5,
		"the dope overlay stays inside the compact 34 percent budget")
	_check(editor._timeline_panel.size.y >= FOLDED_TIMELINE + 48.0 - 0.5,
		"the dope overlay keeps the transport plus a 48 dp sheet")
	_check(overlay_stage_h - editor._timeline_panel.size.y >= overlay_stage_h * 0.55 - 1.0,
		"the open dope overlay leaves at least 55 percent of the stage")
	# More is session-only: it raises the cap to min(260, stage * 0.46) and
	# returns to the compact budget on the next open.
	_check(editor.has_method("_on_timeline_more_requested"),
		"the editor owns the session-only More state")
	if editor.has_method("_on_timeline_more_requested"):
		var compact_open: float = editor._timeline_panel.size.y
		editor._on_timeline_more_requested()
		await get_tree().process_frame
		await get_tree().process_frame
		var full_budget := minf(260.0, maxf(FOLDED_TIMELINE + 48.0, overlay_stage_h * 0.46))
		_check(editor._timeline_panel.size.y <= full_budget + 0.5,
			"More stays inside the 46 percent / 260 dp cap")
		_check(editor._timeline_panel.size.y >= compact_open - 0.5,
			"More never shrinks the open sheet")
		editor._on_timeline_more_requested()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(is_equal_approx(editor._timeline_panel.size.y, compact_open),
			"leaving More restores the compact open height")
	_check(is_equal_approx(editor._view.size.x, view_before_overlay.x) and
		is_equal_approx(editor._view.size.y, view_before_overlay.y),
		"opening the timeline does not resize the 3D view")
	_check(editor._view.size.y - editor._timeline_panel.size.y >= 95.0,
		"the open dope overlay leaves at least 96 dp of stage visible")
	_check(absf(editor._timeline_panel.get_global_rect().end.y -
		overlay_host.get_global_rect().end.y) <= 1.0,
		"the timeline overlay anchors to the stage bottom")
	_check(absf(editor._timeline.mount_target().get_global_rect().end.y -
		overlay_host.get_global_rect().end.y) <= 1.0,
		"the transport row is the bottom edge of the stage")
	editor._timeline.set_mode("graph")
	editor._sync_timeline_visibility()
	await get_tree().process_frame
	await get_tree().process_frame
	var graph_budget := dope_budget
	_check(editor._timeline_panel.size.y <= graph_budget + 0.5,
		"the graph overlay shares the same 42 percent cap")
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

	# The binding short-screen case: at 915x412 the open dope sheet keeps at
	# least 55 percent of the stage and folds the clip lane and media header
	# before it squeezes the sheet below transport + 72 dp.
	await _resize(main, Vector2i(915, 412))
	editor.set_workspace_mode("studio")
	await get_tree().process_frame
	await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame
	var short_host: Control = editor._viewport_host
	editor._timeline.set_mode("dope")
	editor._timeline_visible = true
	editor._sync_timeline_visibility()
	await get_tree().process_frame
	await get_tree().process_frame
	var short_budget := minf(208.0, maxf(FOLDED_TIMELINE + 48.0, short_host.size.y * 0.34))
	_check(editor._timeline_panel.size.y <= short_budget + 0.5,
		"915x412 dope stays inside the compact 34 percent budget")
	_check(editor._timeline_panel.size.y <= 112.0,
		"915x412 compact open height stays at or below 112 dp")
	_check(editor._timeline_panel.size.y >= FOLDED_TIMELINE + 48.0 - 0.5,
		"915x412 dope keeps transport plus a 48 dp sheet")
	_check(short_host.size.y - editor._timeline_panel.size.y >= short_host.size.y * 0.55 - 1.0,
		"915x412 dope leaves at least 55 percent of the stage")
	_check(not editor._clip_lane.visible and not editor._media_lanes.visible,
		"915x412 compact folds the clip lane and media header first")
	# The compact pass still exposes the transport, the ruler and one key lane.
	_check(editor._timeline.transport_panel().is_visible_in_tree(),
		"915x412 keeps the transport visible")
	_check(editor._timeline.sheet_visible() and editor._timeline._sheet.is_visible_in_tree(),
		"915x412 keeps the dope sheet visible")
	var compact_sheet_h: float = editor._timeline.sheet_min_height()
	editor._timeline._geometry(editor._timeline._sheet)
	_check(compact_sheet_h >= FOLDED_TIMELINE + 48.0 - FOLDED_TIMELINE - 0.5,
		"915x412 keeps a 48 dp sheet floor")
	_check(editor._timeline._ruler_h + editor._timeline._row_h <= compact_sheet_h + 1.0,
		"915x412 exposes the ruler and at least one key lane")
	# More reveals the folded lanes without leaving the compact budget class.
	if editor.has_method("_on_timeline_more_requested"):
		editor._on_timeline_more_requested()
		await get_tree().process_frame
		await get_tree().process_frame
		var short_full := minf(260.0, maxf(FOLDED_TIMELINE + 48.0, short_host.size.y * 0.46))
		_check(editor._timeline_panel.size.y <= short_full + 0.5,
			"915x412 More stays inside the 46 percent cap")
		_check(editor._media_lanes.visible,
			"915x412 More reveals the folded media header")
		# Key-step navigation must stay reachable at 915x412. The transport
		# keeps the pair because this surface is wide enough for it, with the
		# normal 44 dp touch target.
		_check(editor._timeline._prev_button.is_visible_in_tree(),
			"915x412 keeps Previous key reachable")
		_check(editor._timeline._next_button.is_visible_in_tree(),
			"915x412 keeps Next key reachable")
		_check(editor._timeline._prev_button.custom_minimum_size.x >= 44.0
			and editor._timeline._next_button.custom_minimum_size.x >= 44.0,
			"915x412 key-step controls keep the 44 dp target")
		_check(editor._timeline.transport_panel().get_combined_minimum_size().x <=
			editor._timeline.size.x + 0.5,
			"915x412 keeps key-step inside the transport width")
		editor._on_timeline_more_requested()
		await get_tree().process_frame
	# The gesture hint lives on the sheet surface, survives the folded compact
	# header, and only appears on the user's open path. Reopening does not
	# repeat it.
	editor._timeline_visible = false
	editor._sync_timeline_visibility()
	await get_tree().process_frame
	editor._toggle_timeline()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._timeline.has_method("gesture_hint_visible"),
		"the sheet exposes its one-time gesture hint")
	if editor._timeline.has_method("gesture_hint_visible"):
		_check(editor._timeline.gesture_hint_visible(),
			"opening the sheet shows the gesture hint once")
		_check(editor._timeline._gesture_hint.text == "Pinch to zoom · drag to pan",
			"the hint names both time-view gestures")
	editor._toggle_timeline()
	await get_tree().process_frame
	editor._toggle_timeline()
	await get_tree().process_frame
	await get_tree().process_frame
	if editor._timeline.has_method("gesture_hint_visible"):
		_check(not editor._timeline.gesture_hint_visible(),
			"the gesture hint is one-time and does not repeat on reopen")
	editor._timeline_visible = false
	editor._sync_timeline_visibility()
	await get_tree().process_frame

	# M6: the nav gizmo sits above the 56 dp folded transport strip, and every
	# axis tip stays inside the stage and left of the scene column at 915x412.
	var nav = editor._view.get("_nav_gizmo")
	_check(nav != null, "the stage mounts the navigation gizmo")
	if nav != null:
		_check(-nav.offset_bottom >= FOLDED_TIMELINE + 12.0 - 0.5,
			"the nav gizmo clears the folded 56 dp transport strip")
		var stage_rect: Rect2 = editor._viewport_host.get_global_rect()
		var column_rect: Rect2 = editor._scene_column.get_global_rect()
		for axis_name in ["x", "y", "z"]:
			var tip_global: Vector2 = nav.get_global_rect().position + nav.tip_position(axis_name)
			_check(stage_rect.has_point(tip_global),
				"the %s nav tip stays inside the stage at 915x412" % axis_name.to_upper())
			_check(tip_global.x <= column_rect.position.x + 0.5,
				"the scene column never covers the %s nav tip" % axis_name.to_upper())
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
	_check(editor._scene_rail_expand.tooltip_text.contains("320 dp"),
		"the disabled rail says the stage needs 320 dp")
	_check_no_overflow(editor, "600x960 studio scene rail")

	# M8: the exact thresholds. 480 dp turns the persistent column into a
	# rail; 479 dp hands the same outliner back to the dock. Independently,
	# the sub-760 expansion is legal only while the stage keeps exactly 320 dp
	# (611 dp shell), and illegal one dp below it.
	await _resize(main, Vector2i(480, 960))
	editor.set_workspace_mode("studio")
	await get_tree().process_frame
	await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame
	_check(editor._scene_column.visible and editor._scene_rail.visible,
		"a 480 dp studio shell keeps the 44 dp scene rail")
	_check(editor._outliner_panel.get_parent() == editor._scene_column,
		"the 480 dp shell keeps the outliner in the scene column")
	# One dp below the threshold. Studio clamps its canvas to its own 480 dp
	# minimum (LayoutMath.STUDIO_MIN), so a real window can never produce a
	# 479 dp Studio canvas; headless keeps factor 1.0 and can. The pixel case
	# therefore runs only where the canvas is honestly 479 dp, and the clamped
	# window still proves the threshold is that same minimum.
	var below_threshold := LayoutMath.resolve(Vector2i(479, 960), 160.0, "Linux", 1.0, "studio", true)
	_check(bool(below_threshold["clamped"]) and
		absf((below_threshold["logical_after"] as Vector2).x - SCENE_PANEL_MIN) < 0.5,
		"a 479 dp Studio window clamps to the 480 dp column threshold")
	await _resize(main, Vector2i(479, 960))
	editor.set_workspace_mode("studio")
	await get_tree().process_frame
	await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame
	if absf(editor.size.x - 479.0) < 0.5:
		_check(not editor._scene_column.visible,
			"a 479 dp shell hides the persistent scene column")
		_check(editor._outliner_panel.get_parent() == editor._dock_box,
			"a 479 dp shell returns the outliner to the dock")
	else:
		print("LAYOUT SKIP: 479 dp scene column: Studio clamped the canvas to %d dp" % roundi(editor.size.x))
		_check(editor.size.x >= SCENE_PANEL_MIN - 0.5,
			"the Studio canvas never falls below the 480 dp scene column threshold")
		_check(editor._scene_column.visible,
			"the clamped 480 dp canvas keeps the scene column available")

	Prefs.set_value("editor.scene_panel_expanded", false)
	for entry in [[611, true], [610, false]]:
		await _resize(main, Vector2i(int(entry[0]), 960))
		editor.set_workspace_mode("studio")
		await get_tree().process_frame
		await get_tree().process_frame
		main.refresh_layout_scale()
		await get_tree().process_frame
		var stage_label := "%d dp shell scene expansion" % int(entry[0])
		_check(editor._scene_rail.visible, stage_label + ": the rail is the collapsed state")
		if bool(entry[1]):
			_check(not editor._scene_rail_expand.disabled,
				stage_label + ": exactly 320 dp of stage still expands")
			_check(editor._scene_rail_expand.tooltip_text == "Expand the scene panel",
				stage_label + ": the enabled rail keeps its expand tooltip")
		else:
			_check(editor._scene_rail_expand.disabled,
				stage_label + ": one dp below the 320 dp stage floor disables expansion")
			_check(editor._scene_rail_expand.tooltip_text.contains("320 dp"),
				stage_label + ": the disabled rail explains the stage floor")
	Prefs.set_value("editor.scene_panel_expanded", true)

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
				_check(media_lanes.video_row_count() == 1 and media_lanes.audio_row_count() == 1,
					label + ": the populated media lanes expose their real rows")
				_check(media_lanes.video_row_height() >= 44.0,
					label + ": video rows keep the 44 dp touch floor")
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
			_fail("%s: %s is %.1fx%.1f, below the 44 dp floor" % [context, control.get_path(), width, height])
		if control is BaseButton:
			_buttons_checked += 1
			# The laid-out size, not the authored minimum: a container that
			# squeezes a button must fail even when its minimum is 44 dp.
			if control.size != Vector2.ZERO and (control.size.x < HIT_FLOOR or control.size.y < HIT_FLOOR):
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
	else:
		printerr("LAYOUT RESULT: %d FAILURE(S)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
