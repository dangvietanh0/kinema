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
				_check(not bool(info.get("user_scale_enabled", true)), label + ": desktop fit disables UI scale")
				_check(editor.fit_percent() < 100.0, label + ": the editor reports the fit percentage")
			print("LAYOUT OK: " + label)

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
			_check_no_overflow(editor, label)
			_check_no_overflow(main, label)
			_check_hit_targets(editor, mode, label)
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
	for node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if control == null or control is BaseButton or not control.is_visible_in_tree():
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


## A tap/drag surface is a non-Button control that accepts pointer input:
## text fields and ranges, controls marked `qa_hit_target` (media rows) or a
## script that overrides `_gui_input` (the clip-lane canvas). Scroll-bar
## internals are engine chrome, not a authored touch target.
func _is_interactive(control: Control) -> bool:
	if control is ScrollBar:
		return false
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
