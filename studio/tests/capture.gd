extends Control
## Screenshot harness for the QA matrix. Not part of the app.
##
## Usage (inside a real window, e.g. under xvfb):
##   godot --path studio --resolution 412x915 res://tests/capture.tscn -- compact 412x915 /tmp/shot.png
##
## The optional user args are: layout mode, the expected viewport size, the
## output path and an action. The harness opens the study template, waits for
## the shell to settle, and writes the framebuffer as a PNG.
##
## Actions: home, home-new, timeline, timeline-folded, drawer-scene,
## drawer-props, add-sheet, settings, performance, renderer, graphics, render,
## quick-render, workspace, draft, graph, scene-rail, scene-expanded.
##
## Screenshots are evidence, so the harness must not photograph its own
## history: Home is seeded with representative recent projects, the editor uses
## a real project name, transient toasts are cleared before the shutter, and the
## temporary project is deleted afterwards.

const OutputDir := "user://captures"
const CAPTURE_TITLE := "Orbit Study"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "auto"
	var expected := Vector2.ZERO
	var out_path := OutputDir + "/capture.png"
	if args.size() >= 1:
		mode = args[0]
	if args.size() >= 2:
		var parts := args[1].split("x")
		if parts.size() == 2:
			expected = Vector2(float(parts[0]), float(parts[1]))
	if args.size() >= 3:
		out_path = args[2]
	var action := args[3] if args.size() >= 4 else ""
	# The harness must not inherit a layout or scale from an earlier capture:
	# the QA matrix is only meaningful when every run starts from the same
	# state and the physical window is exactly the requested size.
	Prefs.set_value("display.user_scale", 1.0)
	Prefs.set_value("display.layout", mode)
	if expected != Vector2.ZERO:
		get_window().size = Vector2i(expected)
	# Let the window reach its requested size before the shell is built.
	for _i in 8:
		await get_tree().process_frame
	# Home reads the store when it is built, so seed the browser before the app
	# shell exists. This list is in memory only and never touches the real
	# recent-projects file.
	if action == "home" or action == "home-new":
		_seed_recents()
	var packed: PackedScene = load("res://src/app/main.tscn")
	var main: Control = packed.instantiate()
	add_child(main)
	for _i in 3:
		await get_tree().process_frame
	var created_id := ""
	if action == "home" or action == "home-new":
		for _i in 15:
			await get_tree().process_frame
	else:
		main._on_new_project_requested(CAPTURE_TITLE, "study")
		for _i in 30:
			await get_tree().process_frame
		if main._editor != null:
			created_id = str(main._editor.doc.project_id)
			main._editor._overlay.clear_toast()
	match action:
		"home-new":
			main._home._open_new_project_sheet()
		"timeline":
			if not main._editor._timeline_visible:
				main._editor._toggle_timeline()
		"timeline-folded":
			if main._editor._timeline_visible:
				main._editor._toggle_timeline()
		"scene-rail":
			main._editor._set_scene_expanded_from_ui(false)
		"scene-expanded":
			main._editor._set_scene_expanded_from_ui(true)
		"drawer-scene":
			main._editor._toggle_drawer("scene")
		"drawer-props":
			main._editor._toggle_drawer("inspector")
		"add-sheet":
			main._editor._open_add_sheet()
		"settings":
			main._editor._open_settings()
		"performance":
			main._editor._open_performance_overlay()
		"renderer":
			main._editor._open_renderer_sheet()
		"graphics":
			main._editor._open_graphics_settings()
		"render":
			main._editor._open_render_sheet()
		"quick-render":
			main._editor._enter_render_mode()
		"workspace":
			main._editor._open_workspace_sheet()
		"draft":
			main._editor._view.set_interactive(true)
		"graph":
			if not main._editor._timeline_visible:
				main._editor._toggle_timeline()
			var timeline = main._editor._timeline
			var graph_doc = main._editor.doc
			timeline.set_mode("graph")
			timeline.set_channel("position")
			# The study selects the orbiting torus, whose keys are on rotation;
			# photograph a channel that actually carries keys so the segment
			# highlight and the speed stats are real.
			if graph_doc.get_channel_keys(graph_doc.selected_id, "position").size() < 2:
				for channel in ["rotation", "scale"]:
					if graph_doc.get_channel_keys(graph_doc.selected_id, channel).size() >= 2:
						timeline.set_channel(channel)
						break
			# The playhead can sit before the first key on a fresh study; fall
			# back to the middle of the range so a segment is always selected.
			if not timeline.select_segment_at_time(graph_doc.current_time):
				timeline.select_segment_at_time(graph_doc.duration * 0.5)
	if action != "":
		for _i in 15:
			await get_tree().process_frame
	# A toast belongs to the action that produced it, not to the screenshot of
	# the next screen. Clear it after the action has settled.
	if main._editor != null:
		main._editor._overlay.clear_toast()
	elif main._home != null and main._home._overlay != null:
		main._home._overlay.clear_toast()
	# Transient chrome (a bottom bar settling after a rotation, a toast fading)
	# needs a few frames to disappear before the shutter.
	for _i in 3:
		await get_tree().process_frame
	# Geometry is not visible in the PNG; when a shot looks off, this makes the
	# measured rects recoverable from the capture log.
	if main._editor != null and OS.get_environment("KINEMA_CAPTURE_GEOMETRY") == "1":
		print("GEOMETRY host=%s view=%s timeline=%s scene=%s body=%s" % [
			str(main._editor._viewport_host.get_global_rect()),
			str(main._editor._view.get_global_rect()),
			str(main._editor._timeline_panel.get_global_rect()),
			str(main._editor._scene_column.get_global_rect()),
			str(main._editor._body.get_global_rect()),
		])
	var viewport_size := get_viewport().get_visible_rect().size
	var image := get_viewport().get_texture().get_image()
	var dir := out_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := image.save_png(out_path)
	print("CAPTURE size=%s expected=%s path=%s err=%d" % [str(viewport_size), str(expected), out_path, err])
	# Do not leave a "Capture" project behind for the next screenshot.
	if created_id != "":
		Store.delete_project(created_id)
	get_tree().quit()

## A realistic project browser. The names, object counts, durations and ages
## are deliberately varied so the list is exercised at its real density.
func _seed_recents() -> void:
	var now := Time.get_unix_time_from_system()
	Store._recents = [
		_recent("orbit-study", "Orbit Study", 9, 6.0, now - 8.0 * 60.0),
		_recent("form-studies", "Form Studies", 6, 4.0, now - 3.0 * 3600.0),
		_recent("lighting-tests", "Lighting Tests", 12, 10.0, now - 2.0 * 86400.0),
		_recent("title-sequence", "Title Sequence", 4, 8.5, now - 5.0 * 86400.0),
		_recent("turntable", "Turntable", 1, 2.0, now - 12.0 * 86400.0),
	]

func _recent(id: String, title: String, objects: int, duration: float, modified: float) -> Dictionary:
	return {
		"id": id,
		"title": title,
		"path": "user://projects/" + id,
		"objects": objects,
		"duration": duration,
		"fps": 24,
		"modified": modified,
	}
