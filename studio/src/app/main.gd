extends Control
## Application shell.
##
## Owns the safe-area inset, the project browser and the editor instance, and
## routes Android back gestures. Only one screen is visible at a time; the home
## screen is kept alive so its scroll position and recent-project list survive a
## round trip into the editor.

const HomeScript = preload("res://src/app/home.gd")
const EditorShellScript = preload("res://src/app/editor.gd")

const BASE_WIDTH := 1280.0
const BASE_HEIGHT := 800.0

var _safe_margin: MarginContainer
var _host: Control
var _home: Control
var _editor: Control
var _opening := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_display_scale()
	var window := get_window()
	if not window.size_changed.is_connected(_update_display_scale):
		window.size_changed.connect(_update_display_scale)

	var background := ColorRect.new()
	background.color = Kit.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_safe_margin = MarginContainer.new()
	_safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_safe_margin)

	_host = Control.new()
	_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe_margin.add_child(_host)

	_home = HomeScript.new()
	_home.new_project_requested.connect(_on_new_project_requested)
	_home.open_project_requested.connect(_on_open_project_requested)
	_home.request_quit.connect(_quit_app)
	_host.add_child(_home)

	get_tree().quit_on_go_back = false
	get_tree().auto_accept_quit = false
	if not window.go_back_requested.is_connected(_on_go_back):
		window.go_back_requested.connect(_on_go_back)

	resized.connect(_update_safe_area)
	get_viewport().size_changed.connect(_update_safe_area)
	call_deferred("_update_safe_area")

# -------------------------------------------------------------------------
# Display scale
# -------------------------------------------------------------------------

func _update_display_scale() -> void:
	# Android reports the window in physical pixels. Map one UI unit to roughly
	# one dp on phones so text, hit targets and the compact-layout threshold
	# behave like a native app instead of a desktop window. Desktop runs keep
	# the 1:1 layout used by the headless tests and screenshots.
	if OS.get_name() != "Android" and OS.get_name() != "iOS":
		return
	var window := get_window()
	if window == null:
		return
	var physical := DisplayServer.window_get_size()
	if physical.x <= 0 or physical.y <= 0:
		return
	var stretch := minf(float(physical.x) / BASE_WIDTH, float(physical.y) / BASE_HEIGHT)
	if stretch <= 0.0:
		return
	var dpi := DisplayServer.screen_get_dpi()
	if dpi <= 0:
		dpi = 160
	var density := clampf(float(dpi) / 160.0, 1.0, 4.0)
	var factor := clampf(density / stretch, 1.0, 4.0)
	if absf(window.content_scale_factor - factor) > 0.02:
		window.content_scale_factor = factor

# -------------------------------------------------------------------------
# Safe area
# -------------------------------------------------------------------------

func _update_safe_area() -> void:
	if _safe_margin == null:
		return
	var left := 0
	var top := 0
	var right := 0
	var bottom := 0
	var os_name := OS.get_name()
	if os_name == "Android" or os_name == "iOS":
		var window_size := DisplayServer.window_get_size()
		var safe := DisplayServer.get_display_safe_area()
		var viewport_size := get_viewport_rect().size
		if window_size.x > 0 and window_size.y > 0 and safe.size.x > 0 and safe.size.y > 0:
			var sx := viewport_size.x / float(window_size.x)
			var sy := viewport_size.y / float(window_size.y)
			left = int(round(maxf(0.0, float(safe.position.x)) * sx))
			top = int(round(maxf(0.0, float(safe.position.y)) * sy))
			right = int(round(maxf(0.0, float(window_size.x - (safe.position.x + safe.size.x))) * sx))
			bottom = int(round(maxf(0.0, float(window_size.y - (safe.position.y + safe.size.y))) * sy))
	_safe_margin.add_theme_constant_override("margin_left", left)
	_safe_margin.add_theme_constant_override("margin_top", top)
	_safe_margin.add_theme_constant_override("margin_right", right)
	_safe_margin.add_theme_constant_override("margin_bottom", bottom)

# -------------------------------------------------------------------------
# Routing
# -------------------------------------------------------------------------

func _on_new_project_requested(title: String, template: String) -> void:
	if _opening or _editor != null:
		return
	_opening = true
	var record: Dictionary = Store.create_record(title)
	if record.is_empty():
		_opening = false
		_show_home_error("The project folder could not be created.", "Check that Kinema has free storage space.")
		return
	_open_editor(record, template, false)
	_opening = false

func _on_open_project_requested(id: String) -> void:
	if _opening or _editor != null:
		return
	_opening = true
	var loaded: Dictionary = Store.load_project(id)
	if loaded.is_empty():
		_opening = false
		_show_home_error("This project could not be opened.", "The project file may be missing or incomplete.")
		return
	_open_editor(loaded, "", true)
	_opening = false

func _open_editor(record: Dictionary, template: String, loaded: bool) -> void:
	var editor := EditorShellScript.new()
	_host.add_child(editor)
	editor.exit_requested.connect(_on_editor_exit)
	if loaded:
		editor.open_loaded(record.get("meta", {}), record.get("data", {}))
	else:
		editor.open_new(record, template)
	_editor = editor
	if _home != null:
		_home.visible = false

func _on_editor_exit() -> void:
	if _editor == null:
		return
	var closing := _editor
	_editor = null
	closing.visible = false
	closing.queue_free()
	if _home != null:
		_home.visible = true
		if _home.has_method("refresh"):
			_home.refresh()
	call_deferred("_update_safe_area")

func _show_home_error(message: String, detail: String) -> void:
	if _home != null and _home.visible and _home.has_method("notify_error"):
		_home.notify_error(message + " " + detail)

# -------------------------------------------------------------------------
# Back and quit
# -------------------------------------------------------------------------

func _on_go_back() -> void:
	if _editor != null:
		_editor.handle_back()
		return
	if _home != null and _home.has_method("handle_back") and _home.handle_back():
		return
	_quit_app()

func _quit_app() -> void:
	if _editor != null and is_instance_valid(_editor):
		_editor.save_now()
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_app()
