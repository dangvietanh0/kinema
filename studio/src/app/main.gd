extends Control
## Application shell.
##
## Owns the safe-area inset, the project browser and the editor instance, and
## routes Android back gestures. Only one screen is visible at a time; the home
## screen is kept alive so its scroll position and recent-project list survive a
## round trip into the editor.

const HomeScript = preload("res://src/app/home.gd")
const EditorShellScript = preload("res://src/app/editor.gd")
const LayoutMath = preload("res://src/app/layout_math.gd")

var _safe_margin: MarginContainer
var _host: Control
var _home: Control
var _editor: Control
var _opening := false
## Last resolution result. The shell reads `mode` to pick its workbench layout.
var layout: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_display_scale()
	var window := get_window()
	if not window.size_changed.is_connected(_update_display_scale):
		window.size_changed.connect(_update_display_scale)
	if not Prefs.changed.is_connected(_on_pref_changed):
		Prefs.changed.connect(_on_pref_changed)

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
	call_deferred("_apply_startup_display")
	call_deferred("_ensure_startup_renderer")

func _apply_startup_display() -> void:
	var orientation := str(Prefs.get_value("display.orientation", "auto"))
	if orientation != "auto":
		apply_orientation(orientation)
	if bool(Prefs.get_value("display.keep_screen_on", true)):
		DisplayServer.screen_set_keep_on(true)

## A pending renderer is verified once, before the user starts working. The
## restart happens only outside headless tests and only through Godot's own
## restart-on-exit path. Reaching the home shell is not proof: the crash this
## gate catches happens on the editor's first 3D frame, so readiness is marked
## from `_open_editor()` instead.
func _ensure_startup_renderer() -> void:
	var result: Dictionary = Gfx.ensure_renderer()
	if str(result.get("action", "none")) != "restart":
		return
	var args := Gfx.consume_restart_request()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		return
	OS.set_restart_on_exit(true, args)
	get_tree().quit()

# -------------------------------------------------------------------------
# Display scale
# -------------------------------------------------------------------------

func _update_display_scale() -> void:
	refresh_layout_scale()

func refresh_layout_scale() -> Dictionary:
	var window := get_window()
	if window == null:
		return layout
	# Headless runs (tests, CI) have no display: nothing can be scaled, so the
	# canvas keeps the 1:1 layout and the mode is read from the canvas itself.
	var headless := DisplayServer.get_name() == "headless"
	# The display server reports physical pixels even when the window node
	# still carries logical coordinates.
	var physical := DisplayServer.window_get_size()
	if physical.x <= 0 or physical.y <= 0:
		physical = Vector2i(window.size)
	if headless or physical.x <= 0 or physical.y <= 0:
		physical = Vector2i(get_viewport().get_visible_rect().size)
	if physical.x <= 0 or physical.y <= 0:
		physical = Vector2i(1280, 800)
	var dpi := float(DisplayServer.screen_get_dpi())
	if dpi <= 0.0:
		dpi = 160.0
	var user_scale := float(Prefs.get_value("display.user_scale", 1.0))
	var preference := str(Prefs.get_value("display.layout", "auto"))
	# Fit only applies to the editor: the browser is arranged by the layout
	# mode and never needs the 960x600 desktop canvas.
	var fit_desktop := _editor != null
	layout = LayoutMath.resolve(physical, dpi, OS.get_name(), user_scale, preference, fit_desktop)
	var factor := float(layout["factor"])
	if headless:
		factor = 1.0
	if absf(window.content_scale_factor - factor) > 0.002:
		window.content_scale_factor = factor
	if _editor != null and _editor.has_method("apply_layout"):
		_editor.apply_layout(layout)
	_update_safe_area()
	queue_redraw()
	return layout


func layout_mode() -> String:
	if layout.is_empty():
		refresh_layout_scale()
	return str(layout.get("mode", "studio"))


func apply_orientation(value: String) -> bool:
	## Returns false when the platform cannot force an orientation, so Settings
	## can leave the control disabled with an honest reason.
	if not DisplayServer.has_feature(DisplayServer.FEATURE_ORIENTATION):
		return false
	DisplayServer.screen_set_orientation(LayoutMath.orientation_constant(value))
	return true


func _on_pref_changed(key: String, _value: Variant) -> void:
	# Only layout preferences move the canvas; everything else is the editor's
	# business and must not trigger a re-layout in the middle of an edit.
	if key == "display.layout" or key == "display.user_scale":
		refresh_layout_scale()

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
		var factor := float(layout.get("factor", 1.0)) if not layout.is_empty() else 1.0
		if factor <= 0.0:
			factor = 1.0
		if window_size.x > 0 and window_size.y > 0 and safe.size.x > 0 and safe.size.y > 0:
			# Inset in logical UI units: of a scaled canvas, a 24 px status bar
			# occupies the same 24 px of screen regardless of canvas scaling.
			var sx := 1.0 / factor
			var sy := 1.0 / factor
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
	if not editor.layout_mode_changed.is_connected(_on_layout_mode_changed):
		editor.layout_mode_changed.connect(_on_layout_mode_changed)
	if loaded:
		editor.open_loaded(record.get("meta", {}), record.get("data", {}))
	else:
		editor.open_new(record, template)
	_editor = editor
	if _home != null:
		_home.visible = false
	refresh_layout_scale()
	_await_editor_first_frame()


## The renderer request is proven only when the editor's own 3D viewport has
## drawn. This one-shot wait keeps `renderer_ready` false through the home
## shell, so a Vulkan crash on the first editor frame still counts as the one
## failed attempt on the next launch. Headless runs have no drawable frame; the
## shell is the only surface and the suite never relies on device readiness.
func _await_editor_first_frame() -> void:
	if DisplayServer.get_name() == "headless":
		Gfx.mark_renderer_ready()
		return
	await RenderingServer.frame_post_draw
	Gfx.mark_renderer_ready()

func _on_layout_mode_changed(_mode: String) -> void:
	refresh_layout_scale()


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
