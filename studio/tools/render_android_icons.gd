extends SceneTree
## Renders the Android launcher and splash assets from the SVG sources in
## `android/icon/`. Run from the project root:
##   godot --headless --script res://tools/render_android_icons.gd

const ICON_DIR := "res://android/icon/"
const RES_DIR := "res://android/app/res/"
const LEGACY_SIZES := {
	"mipmap-mdpi": 48,
	"mipmap-hdpi": 72,
	"mipmap-xhdpi": 96,
	"mipmap-xxhdpi": 144,
	"mipmap-xxxhdpi": 192,
}
const ADAPTIVE_SIZES := {
	"mipmap-mdpi": 108,
	"mipmap-hdpi": 162,
	"mipmap-xhdpi": 216,
	"mipmap-xxhdpi": 324,
	"mipmap-xxxhdpi": 432,
}

func _initialize() -> void:
	var failures := 0
	var icon := _svg("icon.svg")
	var foreground := _svg("foreground.svg")
	var monochrome := _svg("monochrome.svg")
	var splash := _svg("splash.svg")
	if icon == "" or foreground == "" or monochrome == "" or splash == "":
		printerr("Kinema: icon SVG sources are missing.")
		quit(1)
		return

	for dir in LEGACY_SIZES:
		failures += _render(icon, RES_DIR + dir + "/icon.png", int(LEGACY_SIZES[dir]))
	for dir in ADAPTIVE_SIZES:
		failures += _render(foreground, RES_DIR + dir + "/icon_foreground.png", int(ADAPTIVE_SIZES[dir]))
		failures += _render(monochrome, RES_DIR + dir + "/icon_monochrome.png", int(ADAPTIVE_SIZES[dir]))
	failures += _render(splash, RES_DIR + "drawable-nodpi/kinema_splash.png", 1152)

	if failures == 0:
		print("Kinema: Android icons rendered.")
		quit(0)
	else:
		printerr("Kinema: %d icon(s) failed to render." % failures)
		quit(1)

func _svg(file_name: String) -> String:
	var path := ICON_DIR + file_name
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()

func _render(svg: String, path: String, target_size: int) -> int:
	var image := Image.new()
	var err := image.load_svg_from_string(svg, 8.0)
	if err != OK:
		printerr("Kinema: could not rasterize %s." % path)
		return 1
	image.resize(target_size, target_size, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	err = image.save_png(path)
	if err != OK:
		printerr("Kinema: could not write %s (error %d)." % [path, err])
		return 1
	return 0
