extends Node
## Screenshot harness for the QA matrix. Not part of the app.
##
## Usage (inside a real window, e.g. under xvfb):
##   godot --path studio --resolution 412x915 res://tests/capture.tscn -- compact 412x915 /tmp/shot.png
##
## The optional user args are: layout mode, the expected viewport size, and the
## output path. The harness opens the study template, waits for the shell to
## settle, and writes the framebuffer as a PNG.

const OutputDir := "user://captures"


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
	if mode != "auto":
		Prefs.set_value("display.layout", mode)
	# Let the window reach its requested size before the shell is built.
	for _i in 8:
		await get_tree().process_frame
	var packed: PackedScene = load("res://src/app/main.tscn")
	var main: Control = packed.instantiate()
	add_child(main)
	for _i in 3:
		await get_tree().process_frame
	main._on_new_project_requested("Capture", "study")
	for _i in 30:
		await get_tree().process_frame
	var viewport_size := get_viewport().get_visible_rect().size
	var image := get_viewport().get_texture().get_image()
	var dir := out_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := image.save_png(out_path)
	print("CAPTURE size=%s expected=%s path=%s err=%d" % [str(viewport_size), str(expected), out_path, err])
	get_tree().quit()
