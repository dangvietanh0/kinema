extends Control
## Editor workspace.
##
## The editor is deliberately quiet: one top bar, a slim transform rail, the
## viewport, a single-object dope sheet, and a right dock with the scene list
## and object properties. On compact screens the dock becomes a drawer instead
## of shrinking the viewport into a postage stamp.
##
## The document owns all scene and animation state. This script only presents
## it and routes user intent; every mutation goes through Document so undo,
## autosave and serialization stay in one place.

signal exit_requested
## Emitted when the workbench arrangement changes, including when Main
## resolves a different mode for the same preference.
signal workspace_mode_changed(mode: String)

const DocumentScript = preload("res://src/core/document.gd")
const RenderExport = preload("res://src/core/render_export.gd")
const EditorViewScript = preload("res://src/viewport/editor_view.gd")
const OutlinerScript = preload("res://src/ui/outliner.gd")
const InspectorScript = preload("res://src/ui/inspector.gd")
const TimelineScript = preload("res://src/ui/timeline.gd")
const OverlayScript = preload("res://src/ui/overlay.gd")
const TopBarScript = preload("res://src/ui/components/top_bar.gd")
const ViewportHeaderScript = preload("res://src/ui/components/viewport_header.gd")
const ToolRailScript = preload("res://src/ui/components/tool_rail.gd")
const StatusBarScript = preload("res://src/ui/components/status_bar.gd")
const BottomBarScript = preload("res://src/ui/components/bottom_bar.gd")
const PerfOverlayScript = preload("res://src/ui/components/perf_overlay.gd")
const SettingsPanelScript = preload("res://src/ui/settings_panel.gd")
const WorkspaceSheetScript = preload("res://src/ui/workspace_sheet.gd")
const LayoutMathScript = preload("res://src/app/layout_math.gd")
const NumberFieldScript = preload("res://src/ui/num_field.gd")
const ScrubBarScript = preload("res://src/ui/scrub_bar.gd")

const AUTOSAVE_SECONDS := 30.0
const WIDE_MIN_WIDTH := 720.0
const SHORT_MAX_HEIGHT := 520.0
## 44 dp transport plus its 1 px rules and vertical padding. Leaving the
## folded strip at 52 clipped the ruler baseline on landscape phones.
const FOLDED_TIMELINE := 56.0

## Material swatches are a graphite ramp. The hex field still accepts any
## colour, but the default palette never pulls the workbench off-message.
const COLOR_PALETTE := [
	"#F2F2F2", "#E0E0E0", "#C8C8C8", "#B0B0B0", "#989898", "#808080",
	"#686868", "#505050", "#3A3A3A", "#2A2A2A", "#1B1B1B", "#101010",
	"#D8D8D8", "#BDBDBD", "#A0A0A0", "#7A7A7A", "#4A4A4A", "#202020",
]

var doc: DocumentScript = null

var _project_meta: Dictionary = {}
var _layout: VBoxContainer
var _top_bar: PanelContainer
var _status_bar: PanelContainer
var _bottom_bar: PanelContainer

var _body: HBoxContainer
var _rail: PanelContainer
var _center: VBoxContainer
var _view_header: PanelContainer
var _viewport_host: Control
var _view: Control
var _perf_overlay: PanelContainer
var _timeline_panel: PanelContainer
var _timeline: VBoxContainer
var _dock_slot: Control
var _dock: PanelContainer
var _dock_box: VBoxContainer
var _dock_close_row: MarginContainer
var _dock_close_button: Button
var _drawer_scene_tab: Button
var _drawer_props_tab: Button
var _outliner_panel: PanelContainer
var _inspector_panel: PanelContainer
var _outliner: VBoxContainer
var _inspector: VBoxContainer
var _drawer_scrim: ColorRect
var _overlay: Control
var _autosave: Timer

var _tool := "select"
var _wide := true
var _short := false
## True when the user has folded or opened the dope sheet themselves. A manual
## choice survives rotation; automatic landscape folding does not override it.
var _timeline_user_override := false
var _fit_percent := 100.0
var _fit_user_scale_enabled := true
var _fit_clamped := false
var _drawer_open := false
var _compact_tab := "scene"
var layout_info: Dictionary = {}
var workbench_mode := "studio"
var _timeline_visible := true
var _closing := false
var _last_save_auto := false

var _color_sheet_active := false
var _color_id := ""
var _color_property := ""
var _color_value := Color(0.6, 0.6, 0.6)
var _color_preview: PanelContainer
var _color_preview_label: Label
var _color_hex: LineEdit
var _color_rgb: Array = []
var _color_updating := false

var _settings_duration_field
var _settings_fps_field
var _settings_linear: Button
var _settings_cubic: Button
var _settings_interp := "linear"

var _pending_still: Image = null
var _pending_zip := ""
var _last_render_path := ""
var _render_resolution := 1920
var _render_msaa := Viewport.MSAA_4X
var _sequence_resolution := 1080
var _sequence_msaa := Viewport.MSAA_2X
var _render_busy := false
var _render_progress: ProgressBar
var _render_status: Label
var _render_sequence_button: Button
var _render_still_button: Button
var _render_save_button: Button
var _preset_buttons: Array[Button] = []
var _renderer_pending := ""
var _settings_panel: Control = null
var _workspace_sheet: Control = null
## Real-time render preview. The viewport plays the document at full quality
## with editing chrome removed; this flag owns the editor-side lifecycle.
var _render_mode := false
var _render_hud: PanelContainer = null
var _render_play_button: Button = null
var _render_time_label: Label = null
var _render_saved_time := 0.0
var _render_was_playing := false
var _render_ui_state: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_layout = VBoxContainer.new()
	_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout.add_theme_constant_override("separation", int(Kit.GUTTER))
	add_child(_layout)

	_build_top_bar()
	_build_body()
	_build_status_bar()
	_build_bottom_bar()
	# The scrim is added before the dock so GUI picking gives the drawer the
	# first chance at taps inside it; the scrim only sees taps outside.
	_build_drawer_scrim()
	_build_dock()
	_build_render_hud()
	_apply_collapsed_sections()

	_overlay = OverlayScript.new()
	add_child(_overlay)
	_overlay.modal_closed.connect(_on_modal_closed)
	_overlay.modal_opened.connect(_on_modal_opened)
	_overlay.set_toast_anchor(_viewport_host)

	_autosave = Timer.new()
	_autosave.wait_time = _autosave_seconds()
	_autosave.autostart = _autosave.wait_time > 0.0
	_autosave.timeout.connect(_on_autosave)
	add_child(_autosave)

	Perf.sample_updated.connect(_on_perf_sample)
	_apply_editor_preferences()
	_apply_perf_preferences()

	resized.connect(_on_resized)
	call_deferred("_apply_shell")

# -------------------------------------------------------------------------
# Construction
# -------------------------------------------------------------------------

func _build_top_bar() -> void:
	_top_bar = TopBarScript.new()
	_top_bar.action_requested.connect(_on_chrome_action)
	_top_bar.layout_requested.connect(_open_workspace_sheet)
	_layout.add_child(_top_bar)

func _build_body() -> void:
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", int(Kit.GUTTER))
	_layout.add_child(_body)

	_rail = ToolRailScript.new()
	_rail.tool_selected.connect(_select_tool)
	_rail.frame_requested.connect(_focus_selection)
	_rail.add_requested.connect(_open_add_sheet)
	_body.add_child(_rail)

	_center = VBoxContainer.new()
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# A one-pixel gutter lets the black shell show between the stage, the
	# header and the sheet instead of stacking same-valued panels edge to edge.
	_center.add_theme_constant_override("separation", int(Kit.GUTTER))
	_body.add_child(_center)

	# The view header is part of the layout, not a floating plate: it owns the
	# camera preset, Add, grid and frame without covering the image.
	_view_header = ViewportHeaderScript.new()
	_view_header.add_requested.connect(_open_add_sheet)
	_view_header.frame_requested.connect(_focus_selection)
	_center.add_child(_view_header)

	_viewport_host = Control.new()
	_viewport_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_host.custom_minimum_size.y = 120
	_viewport_host.clip_contents = true
	_center.add_child(_viewport_host)

	_view = EditorViewScript.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport_host.add_child(_view)
	_view.set_tool(_tool)
	_view.quick_render_requested.connect(_enter_render_mode)
	_view.performance_requested.connect(_toggle_performance_overlay)
	# The header and the view share one source of truth. The view reports a
	# free-orbit camera or a grid change; the header writes intent back.
	_view.view_changed.connect(_on_view_changed)
	_view.grid_changed.connect(_on_view_grid_changed)
	_view.bind_header_controls(_view_header.grid_button(), _view_header.frame_button())
	_view_header.view_requested.connect(_on_view_requested)
	_view_header.grid_toggled.connect(_on_view_header_grid_toggled)

	# The overlay is a sibling of the view so it floats above the 3D surface
	# without becoming part of the viewport's own HUD layout.
	_perf_overlay = PerfOverlayScript.new()
	_viewport_host.add_child(_perf_overlay)

	_build_timeline()

	_dock_slot = Control.new()
	_dock_slot.custom_minimum_size.x = 320
	_body.add_child(_dock_slot)

func _build_status_bar() -> void:
	_status_bar = StatusBarScript.new()
	_status_bar.action_requested.connect(_on_chrome_action)
	_layout.add_child(_status_bar)


func _build_bottom_bar() -> void:
	_bottom_bar = BottomBarScript.new()
	_bottom_bar.action_requested.connect(_on_bottom_action)
	_layout.add_child(_bottom_bar)

func _build_timeline() -> void:
	_timeline_panel = PanelContainer.new()
	_timeline_panel.custom_minimum_size.y = 190
	_timeline_panel.size_flags_vertical = Control.SIZE_FILL
	var style := Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT, 0)
	style.border_width_top = 0
	_timeline_panel.add_theme_stylebox_override("panel", style)
	_center.add_child(_timeline_panel)

	_timeline = TimelineScript.new()
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.notice.connect(_on_timeline_notice)
	_timeline.close_requested.connect(_on_timeline_close_requested)
	_timeline.mode_changed.connect(_on_timeline_mode_changed)
	_timeline_panel.add_child(_timeline)

func _build_dock() -> void:
	_dock = PanelContainer.new()
	_dock.z_index = 12
	_dock.anchor_left = 1.0
	_dock.anchor_right = 1.0
	_dock.anchor_top = 0.0
	_dock.anchor_bottom = 1.0
	_dock.offset_top = 44.0
	_dock.offset_bottom = 0.0
	_dock.offset_left = -320.0
	var style := Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT, 0)
	style.border_width_left = 1
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	_dock.add_theme_stylebox_override("panel", style)
	add_child(_dock)

	_dock_box = VBoxContainer.new()
	_dock_box.add_theme_constant_override("separation", int(Kit.GUTTER))
	_dock.add_child(_dock_box)

	_dock_close_row = MarginContainer.new()
	_dock_close_row.add_theme_constant_override("margin_left", 8)
	_dock_close_row.add_theme_constant_override("margin_right", 6)
	_dock_close_row.add_theme_constant_override("margin_top", 2)
	_dock_close_row.add_theme_constant_override("margin_bottom", 2)
	_dock_close_row.visible = false
	_dock_box.add_child(_dock_close_row)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	_dock_close_row.add_child(tabs)
	_drawer_scene_tab = Kit.text_toggle("Scene", "layers", true)
	_drawer_scene_tab.custom_minimum_size.y = 44
	_drawer_scene_tab.pressed.connect(func() -> void: _set_compact_tab("scene"))
	tabs.add_child(_drawer_scene_tab)
	_drawer_props_tab = Kit.text_toggle("Properties", "sliders-horizontal", true)
	_drawer_props_tab.custom_minimum_size.y = 44
	_drawer_props_tab.pressed.connect(func() -> void: _set_compact_tab("inspector"))
	tabs.add_child(_drawer_props_tab)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.add_child(spacer)
	_dock_close_button = Kit.icon_button("x", "Close panels", 44, 20)
	_dock_close_button.pressed.connect(_close_drawer)
	tabs.add_child(_dock_close_button)

	_dock_box.add_child(Kit.vsep())

	_outliner_panel = PanelContainer.new()
	_outliner_panel.custom_minimum_size.y = 172
	_outliner_panel.size_flags_vertical = Control.SIZE_FILL
	var out_style := Kit.flat_style(Kit.SURFACE, Kit.R_PANEL, Color(0, 0, 0, 0), 0)
	_outliner_panel.add_theme_stylebox_override("panel", out_style)
	_dock_box.add_child(_outliner_panel)

	_outliner = OutlinerScript.new()
	_outliner.add_requested.connect(_open_add_sheet)
	_outliner.collapse_toggled.connect(func(collapsed: bool) -> void:
		_set_section_collapsed("outliner", collapsed)
	)
	_outliner_panel.add_child(_outliner)

	_inspector_panel = PanelContainer.new()
	_inspector_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector_panel.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT, 0))
	_dock_box.add_child(_inspector_panel)

	_inspector = InspectorScript.new()
	_inspector.add_requested.connect(_open_add_sheet)
	_inspector.color_requested.connect(_open_color_sheet)
	_inspector.collapse_toggled.connect(func(collapsed: bool) -> void:
		_set_section_collapsed("inspector", collapsed)
	)
	_inspector_panel.add_child(_inspector)

func _build_render_hud() -> void:
	_render_hud = PanelContainer.new()
	_render_hud.name = "RenderTransport"
	_render_hud.visible = false
	_render_hud.z_index = 50
	_render_hud.anchor_left = 0.5
	_render_hud.anchor_right = 0.5
	_render_hud.anchor_top = 1.0
	_render_hud.anchor_bottom = 1.0
	_render_hud.offset_bottom = -24.0
	_render_hud.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_render_hud.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := Kit.flat_style(Kit.SURFACE, Kit.R_FLOAT, Kit.BORDER, 1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_render_hud.add_theme_stylebox_override("panel", style)
	add_child(_render_hud)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_render_hud.add_child(row)

	var live := Kit.section_label("Render")
	live.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(live)
	var spacer_l := Control.new()
	spacer_l.custom_minimum_size.x = 8
	row.add_child(spacer_l)

	_render_time_label = Kit.mono_label("00:00:00", 13, Kit.TEXT)
	_render_time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_render_time_label.custom_minimum_size.x = 88
	row.add_child(_render_time_label)

	_render_play_button = Kit.icon_button("pause", "Pause the render preview", 44, 20)
	_render_play_button.add_theme_color_override("icon_normal_color", Kit.TIME_BRIGHT)
	_render_play_button.add_theme_color_override("icon_pressed_color", Kit.FOCUS_BRIGHT)
	_render_play_button.pressed.connect(_toggle_render_playback)
	row.add_child(_render_play_button)

	var restart: Button = Kit.icon_button("restart", "Restart from the first frame", 44, 20)
	restart.pressed.connect(_restart_render_playback)
	row.add_child(restart)

	var spacer_r := Control.new()
	spacer_r.custom_minimum_size.x = 8
	row.add_child(spacer_r)

	var exit: Button = Kit.icon_button("x", "Exit render preview", 44, 20)
	exit.pressed.connect(_exit_render_mode)
	row.add_child(exit)


func _build_drawer_scrim() -> void:
	_drawer_scrim = ColorRect.new()
	_drawer_scrim.color = Color(0, 0, 0, 0.58)
	_drawer_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drawer_scrim.offset_top = 44.0
	# The scrim is built before the dock, so the drawer receives taps inside
	# its own rectangle first. Only taps outside reach the scrim and close it.
	_drawer_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_drawer_scrim.visible = false
	_drawer_scrim.z_index = 11
	_drawer_scrim.gui_input.connect(_on_drawer_scrim_input)
	add_child(_drawer_scrim)


func _on_drawer_scrim_input(event: InputEvent) -> void:
	if not _drawer_open:
		return
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_close_drawer()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_close_drawer()

# -------------------------------------------------------------------------
# Documents
# -------------------------------------------------------------------------

## Applies a resolved layout result from Main: the workbench arrangement and
## the interface fit. Main owns the resolution; the editor only presents it.
func apply_layout(layout: Dictionary) -> void:
	layout_info = layout
	# Main already knows the mode it resolved, so this path never notifies it.
	_apply_workspace_mode(str(layout.get("mode", "studio")), false)
	apply_fit_info(
		float(layout.get("fit_percent", 100.0)),
		bool(layout.get("user_scale_enabled", true)),
		bool(layout.get("clamped", false))
	)


func workspace_mode() -> String:
	return workbench_mode


## User intent. Persists the preference and, when the shell is hosted by Main,
## asks it to re-resolve; without a host the mode is resolved here so pure
## scenes and tests behave identically.
func set_workspace_mode(mode: String) -> void:
	var next := mode if mode in ["auto", "compact", "studio", "desktop"] else "auto"
	Prefs.set_value("display.layout", next)
	if _layout_hosted():
		# Main re-resolves and calls apply_layout, which applies the mode and
		# emits workspace_mode_changed if the arrangement actually changed.
		var host := get_parent()
		while host != null and not host.has_method("refresh_layout_scale"):
			host = host.get_parent()
		if host != null:
			host.call("refresh_layout_scale")
		return
	_apply_workspace_mode(_resolve_local(next), true)


func apply_fit_info(fit_percent: float, user_scale_enabled: bool, clamped: bool) -> void:
	_fit_percent = clampf(fit_percent, 1.0, 100.0)
	_fit_user_scale_enabled = user_scale_enabled
	_fit_clamped = clamped
	if _top_bar != null:
		_top_bar.set_fit(_fit_percent, _fit_percent < 60.0)
	if _status_bar != null:
		_update_chrome_sample()
	if _settings_panel != null and is_instance_valid(_settings_panel) and _settings_panel.has_method("refresh_fit"):
		_settings_panel.call("refresh_fit")
	if _workspace_sheet != null and is_instance_valid(_workspace_sheet) and _workspace_sheet.has_method("refresh_fit"):
		_workspace_sheet.call("refresh_fit", _fit_percent, _fit_user_scale_enabled, _fit_clamped)


func fit_percent() -> float:
	return _fit_percent


func fit_user_scale_enabled() -> bool:
	return _fit_user_scale_enabled


func fit_clamped() -> bool:
	return _fit_clamped


func _apply_workspace_mode(mode: String, notify: bool) -> void:
	var next := mode if mode in ["compact", "studio", "desktop"] else "studio"
	var changed := next != workbench_mode
	workbench_mode = next
	if changed:
		# A mode switch is a deliberate arrangement change, so it resets the
		# manual sheet choice and uses the mode default.
		_timeline_user_override = false
		_timeline_visible = _default_timeline_visible(next)
	_apply_shell()
	if changed and notify:
		workspace_mode_changed.emit(next)


## The dope sheet opens by default in a tall workbench and folds on a short
## landscape phone, where height belongs to the viewport. Compact always folds.
func _default_timeline_visible(mode: String) -> bool:
	if mode == "compact":
		return false
	if mode == "studio" and size.y < SHORT_MAX_HEIGHT:
		return false
	return true


func _layout_hosted() -> bool:
	var node := get_parent()
	while node != null:
		if node.has_method("refresh_layout_scale"):
			return true
		node = node.get_parent()
	return false


func _resolve_local(preference: String) -> String:
	var physical := Vector2i(1280, 800)
	var window := get_window()
	if window != null:
		physical = Vector2i(window.size)
	if physical.x <= 0 or physical.y <= 0:
		physical = Vector2i(get_viewport_rect().size)
	if DisplayServer.get_name() == "headless" or physical.x <= 0 or physical.y <= 0:
		physical = Vector2i(get_viewport_rect().size)
	if physical.x <= 0 or physical.y <= 0:
		physical = Vector2i(1280, 800)
	var dpi := float(DisplayServer.screen_get_dpi())
	if dpi <= 0.0:
		dpi = 160.0
	var user_scale := float(Prefs.get_value("display.user_scale", 1.0))
	var fit_desktop := workbench_mode != "compact"
	var result: Dictionary = LayoutMathScript.resolve(physical, dpi, OS.get_name(), user_scale, preference, fit_desktop)
	return str(result.get("mode", "studio"))

func open_new(meta: Dictionary, template: String) -> void:
	_project_meta = meta.duplicate(true)
	var document := DocumentScript.new()
	document.new_project(str(meta.get("title", "Untitled")), template)
	document.project_id = str(meta.get("id", ""))
	document.project_dir = str(meta.get("path", ""))
	_adopt_document(document)
	_save_project(false)
	_overlay.toast("Project created", "check", Kit.SUCCESS)

func open_loaded(meta: Dictionary, data: Dictionary) -> void:
	_project_meta = meta.duplicate(true)
	var document := DocumentScript.new()
	document.project_id = str(meta.get("id", ""))
	document.project_dir = str(meta.get("path", ""))
	document.load_project(data, document.project_dir)
	_adopt_document(document)
	_last_save_auto = false
	_update_header()

func _adopt_document(document: Node3D) -> void:
	doc = document
	if not Gfx.changed.is_connected(_on_graphics_changed):
		Gfx.changed.connect(_on_graphics_changed)
	doc.apply_graphics()
	if _view != null:
		_view.set_document(doc)
		_view.set_tool(_tool)
	_outliner.setup(doc)
	_inspector.setup(doc)
	_timeline.setup(doc)
	doc.scene_changed.connect(_on_document_scene_changed)
	doc.selection_changed.connect(_on_document_selection_changed)
	doc.dirty_changed.connect(_on_document_dirty_changed)
	doc.history_changed.connect(_on_document_history_changed)
	if not doc.playback_changed.is_connected(_on_document_playback_changed):
		doc.playback_changed.connect(_on_document_playback_changed)
	doc.seek(doc.current_time, true)
	_update_header()
	_update_history_buttons()
	_select_tool(_tool)
	# Both calls end with a deferred reframe; arrange the shell once the new
	# document's deferred work has run so the first frame is already correct.
	call_deferred("_apply_shell")

func _on_document_scene_changed() -> void:
	_update_header()

func _on_graphics_changed() -> void:
	if doc != null:
		doc.apply_graphics()
	_sync_preset_buttons()

func _on_document_selection_changed(_id: String) -> void:
	_update_history_buttons()

func _on_document_dirty_changed(_is_dirty: bool) -> void:
	_update_header()
	_update_history_buttons()

func _on_document_history_changed() -> void:
	_update_history_buttons()

# -------------------------------------------------------------------------
# Header and status
# -------------------------------------------------------------------------

func _update_header() -> void:
	if _top_bar == null:
		return
	if doc == null:
		_top_bar.set_project("Untitled", false, false)
		return
	_top_bar.set_project(doc.title, doc.is_dirty(), true)

func _update_history_buttons() -> void:
	if _top_bar == null:
		return
	var has_undo := doc != null and doc.can_undo()
	var has_redo := doc != null and doc.can_redo()
	_top_bar.set_history(has_undo, has_redo)

## Reports the renderer the engine is actually running. Godot selects a
## renderer when the process starts; the chips request one for the next launch
## and the actual value below is always read back from RenderingServer.
func _open_renderer_sheet() -> void:
	var current := Gfx.renderer_name()
	var requested := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus"))
	_renderer_pending = current
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var headline := Kit.label(Gfx.display_name(), 13, Kit.TEXT, 500)
	body.add_child(headline)

	var strip := _segment_strip(body)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for entry in [
		{"label": "Forward+", "value": "forward_plus"},
		{"label": "Mobile", "value": "mobile"},
		{"label": "Compatibility", "value": "gl_compatibility"},
	]:
		var data: Dictionary = entry
		var value := str(data["value"])
		var button := Kit.text_toggle(str(data["label"]), "", true)
		_style_segment(button)
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.button_pressed = value == current
		button.toggled.connect(func(on: bool) -> void:
			if on:
				_renderer_pending = value
		)
		strip.add_child(button)

	var rows := [
		["Renderer in use", Gfx.renderer_label(current)],
		["Project request", Gfx.renderer_label(requested)],
		["Driver", RenderingServer.get_current_rendering_driver_name()],
		["Adapter", RenderingServer.get_video_adapter_name()],
	]
	for row in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var key := Kit.label(str(row[0]), 12, Kit.TEXT_MUTED)
		key.custom_minimum_size.x = 132
		line.add_child(key)
		var value_label := Kit.mono_label(str(row[1]), 12, Kit.TEXT)
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.add_child(value_label)
		body.add_child(line)

	var note := Kit.label(
		"Godot chooses the renderer before the first frame. Restart applies the selected backend with a real engine flag; if this platform ignores the flag, the row above keeps reporting the renderer that is actually in use. Android builds default to Mobile.",
		11, Kit.TEXT_DIM
	)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	_overlay.show_sheet("Renderer", "Graphics backend reported by the engine", body, [
		{"text": "Close", "compact": true},
		{"text": "Restart", "primary": true, "callback": _restart_with_renderer},
	], {"width": 720.0})

func _restart_with_renderer() -> void:
	var value := _renderer_pending
	if value == "" or value == Gfx.renderer_name():
		_overlay.toast("That renderer is already running", "info", Kit.TEXT_MUTED)
		return
	Gfx.set_renderer_choice(value)
	if doc != null and doc.is_dirty():
		_save_project(false, true)
	OS.set_restart_on_exit(true, PackedStringArray(["--rendering-method", value]))
	get_tree().quit()


func _open_shortcuts_sheet() -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	for pair in [
		["Space", "Play or pause"],
		["F", "Frame the selection"],
		["1 / 2 / 3 / 4", "Select, move, rotate, scale"],
		["Delete", "Remove the selected object"],
		["Ctrl+Z / Ctrl+Y", "Undo and redo"],
		["Ctrl+S", "Save the project"],
	]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		var key := Kit.mono_label(str(pair[0]), 12, Kit.TEXT)
		key.custom_minimum_size.x = 128
		line.add_child(key)
		var action := Kit.label(str(pair[1]), 12, Kit.TEXT_MUTED)
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(action)
		body.add_child(line)
	_overlay.show_sheet("Keyboard shortcuts", "Physical keyboards and the desktop shell", body, [
		{"text": "Close", "primary": true},
	])


func _open_performance_overlay() -> void:
	_toggle_performance_overlay()

func _toggle_performance_overlay() -> void:
	if _perf_overlay == null:
		return
	if _perf_overlay.visible:
		_perf_overlay.close_overlay()
		return
	_sync_perf_overlay()
	_perf_overlay.open()

func _sync_perf_overlay() -> void:
	if _perf_overlay == null or _view == null:
		return
	var objects := 0 if doc == null else doc.objects.size()
	_perf_overlay.set_sample(Perf.sample(), objects, _total_keys(), _view.preview_size())

func _apply_perf_preferences() -> void:
	if Perf == null:
		return
	Perf.set_adaptive_quality(bool(Prefs.get_value("performance.adaptive_quality", true)))
	Perf.set_target_fps(int(Prefs.get_value("performance.target_fps", 60)))
	Perf.min_preview_scale = clampf(float(Prefs.get_value("performance.min_preview_scale", 0.6)), 0.25, 1.0)
	Perf.set_preview_update(str(Prefs.get_value("performance.preview_update", "on_demand")))
	Perf.set_preview_cap(int(Prefs.get_value("performance.preview_cap", 1920)))
	Engine.max_fps = clampi(int(Prefs.get_value("performance.max_fps", 60)), 0, 240)
	var vsync := bool(Prefs.get_value("performance.vsync", true))
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	var overlay_mode := str(Prefs.get_value("performance.overlay", "compact"))
	var show_fps := bool(Prefs.get_value("editor.show_fps", true))
	if _view != null:
		_view.set_fps_chip_visible(show_fps and overlay_mode != "off")
	if _perf_overlay != null:
		_perf_overlay.set_frame_graph(bool(Prefs.get_value("performance.frame_graph", false)))
		if overlay_mode == "full":
			_sync_perf_overlay()
			_perf_overlay.open()
		else:
			_perf_overlay.close_overlay()

func _on_perf_sample(sample: Dictionary) -> void:
	if _view != null:
		_view.set_fps_value(float(sample.get("fps", -1.0)), float(sample.get("frame_ms", -1.0)))
	if _perf_overlay != null and _perf_overlay.visible:
		var objects := 0 if doc == null else doc.objects.size()
		var preview: Vector2i = _view.preview_size() if _view != null else Vector2i.ZERO
		_perf_overlay.set_sample(sample, objects, _total_keys(), preview)
	_update_chrome_sample(sample)


func _on_timeline_notice(text_value: String) -> void:
	if _overlay != null:
		_overlay.toast(text_value, "diamond", Kit.ACCENT)

# -------------------------------------------------------------------------
# Saving and leaving
# -------------------------------------------------------------------------

func _save_project(notify: bool, automatic: bool = false) -> bool:
	if doc == null:
		return false
	var ok := Store.save_project(doc)
	_last_save_auto = automatic
	if ok:
		if notify:
			_overlay.toast("Project saved", "check", Kit.SUCCESS)
	else:
		_overlay.toast("Could not save this project", "triangle-alert", Kit.DANGER)
	_update_header()
	return ok

func _on_autosave() -> void:
	if doc == null or not doc.is_dirty() or _overlay.has_modal():
		return
	_save_project(false, true)

func save_now() -> bool:
	return _save_project(false)

func request_close() -> void:
	if _closing:
		return
	if _render_mode:
		_exit_render_mode()
		return
	if _overlay != null and _overlay.has_modal():
		_overlay.close_modal()
		return
	if _drawer_open:
		_close_drawer()
		return
	if doc == null or not doc.is_dirty():
		_leave(false)
		return

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	var message := Kit.label("This project has unsaved changes. Save them before returning to the project browser?", 12, Kit.TEXT_MUTED)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(message)
	var note := Kit.label("Autosave runs every %d seconds while the editor is open." % int(AUTOSAVE_SECONDS), 9, Kit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	_overlay.show_modal("Leave project?", "Unsaved work", body, [
		{"text": "Cancel", "compact": true},
		{
			"text": "Discard",
			"destructive": true,
			"callback": func() -> void: _leave(false)
		},
		{
			"text": "Save and leave",
			"primary": true,
			"callback": _save_and_leave,
		},
	])

func _save_and_leave() -> void:
	if _save_project(false):
		_leave(false)

func _leave(save_first: bool = false) -> void:
	if _closing:
		return
	if _render_busy:
		if _overlay != null:
			_overlay.toast("Wait for the render to finish", "film", Kit.WARNING)
		return
	if save_first and doc != null and doc.is_dirty():
		if not _save_project(false):
			return
	_closing = true
	exit_requested.emit()

func handle_back() -> bool:
	if _render_mode:
		_exit_render_mode()
		return true
	if _overlay != null and _overlay.has_modal():
		_overlay.close_modal()
		return true
	if _drawer_open:
		_close_drawer()
		return true
	request_close()
	return true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		if doc != null and doc.is_dirty():
			_save_project(false, true)

# -------------------------------------------------------------------------
# Responsive shell
# -------------------------------------------------------------------------

func _on_resized() -> void:
	_apply_shell()


## Arranges the shell for the current workbench mode. Idempotent: it is safe to
## call on every resize, mode change and preference change.
func _apply_shell() -> void:
	if _dock == null or not is_inside_tree():
		return
	# Render mode owns the whole frame. A resize or preference change must not
	# re-show the workbench chrome over the live image; exiting render mode
	# reapplies the shell in one pass.
	if _render_mode:
		return
	var compact := workbench_mode == "compact"
	# Studio is landscape-first. On a narrow portrait screen a side dock would
	# leave a 150 dp viewport, so the same dock becomes an overlay drawer while
	# the arrangement still reports Studio. The mode never falls back.
	var dock_overlay := _dock_overlay_mode()
	var tabs_only := dock_overlay or size.y < SHORT_MAX_HEIGHT
	_wide = not tabs_only
	var was_short := _short
	_short = size.y < SHORT_MAX_HEIGHT
	_viewport_host.custom_minimum_size.y = 96.0 if _short else 120.0
	_timeline.set_short_layout(_short)
	# Rotation between portrait and landscape changes the default. A manual
	# fold/open choice is respected until the next mode switch.
	if _short != was_short and not _timeline_user_override:
		_timeline_visible = _default_timeline_visible(workbench_mode)
	_top_bar.set_mode(workbench_mode)
	_top_bar.set_available_width(size.x)
	_rail.set_mode(workbench_mode)
	_rail.set_available_height(size.y)
	_view_header.set_mode(workbench_mode)
	if _view != null:
		_view_header.set_view_label(_view.view_preset())
		_view_header.set_grid(_view.grid_enabled())
	_bottom_bar.set_mode(workbench_mode)
	_status_bar.set_mode(workbench_mode)
	if _overlay != null:
		_overlay.set_layout_mode(workbench_mode)
	_timeline.set_chrome_mode(workbench_mode)

	# The rail is a column on wide screens and a strip under the header on
	# phones, so it is re-parented instead of duplicated.
	var want_parent: Control = _center if compact else _body
	if _rail.get_parent() != want_parent:
		_rail.reparent(want_parent, false)
		want_parent.move_child(_rail, 0)

	if dock_overlay:
		_dock.visible = _drawer_open
		_drawer_scrim.visible = _drawer_open
	else:
		_drawer_open = false
		_dock.visible = true
		_drawer_scrim.visible = false
		_dock.modulate.a = 1.0
	_dock_close_row.visible = tabs_only
	# A wide Studio keeps the dock open, so a close button there would be
	# inert. Every drawer arrangement can dismiss its dock.
	_dock_close_button.visible = dock_overlay
	if _top_bar != null:
		_top_bar.set_panels_button_visible(dock_overlay and not compact)
		_top_bar.set_panels_open(_drawer_open)
	_outliner_panel.visible = not tabs_only or _compact_tab == "scene"
	_inspector_panel.visible = not tabs_only or _compact_tab == "inspector"
	var outliner_collapsed: bool = _outliner != null and _outliner.collapsed
	var inspector_collapsed: bool = _inspector != null and _inspector.collapsed
	if outliner_collapsed:
		_outliner_panel.custom_minimum_size.y = 44.0
		_outliner_panel.size_flags_vertical = Control.SIZE_FILL
	elif tabs_only:
		_outliner_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_outliner_panel.custom_minimum_size.y = 180.0 if _short else 190.0
	elif inspector_collapsed:
		# The scene list is the only expanded section, so it takes the dock.
		_outliner_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_outliner_panel.custom_minimum_size.y = 180.0
	else:
		_outliner_panel.size_flags_vertical = Control.SIZE_FILL
		# The scene list owns roughly 40 percent of the dock; the inspector
		# scrolls in the rest. A fixed 190 dp cut the list mid-row.
		var chrome := _top_bar.custom_minimum_size.y
		if _status_bar.visible:
			chrome += _status_bar.custom_minimum_size.y
		if _bottom_bar.visible:
			chrome += _bottom_bar.custom_minimum_size.y
		var dock_height := maxf(320.0, size.y - chrome)
		_outliner_panel.custom_minimum_size.y = clampf(dock_height * 0.38, 180.0, 320.0)

	if inspector_collapsed:
		_inspector_panel.custom_minimum_size.y = 44.0
		_inspector_panel.size_flags_vertical = Control.SIZE_FILL
	else:
		_inspector_panel.custom_minimum_size.y = 0.0
		_inspector_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var dock_width := 0.0
	if dock_overlay:
		dock_width = clampf(size.x * 0.92, 280.0, 420.0)
	else:
		var ratio := 0.26 if workbench_mode == "desktop" else 0.28
		var min_width := 320.0 if workbench_mode == "desktop" else 280.0
		var max_width := 380.0 if workbench_mode == "desktop" else 340.0
		dock_width = clampf(size.x * ratio, min_width, max_width)
		# The dock reserves at least its own content minimum. The inspector's
		# transform fields have a real floor; a dock narrower than that would
		# grow past the right edge instead of shrinking the viewport.
		dock_width = maxf(dock_width, _dock.get_combined_minimum_size().x)
	_dock_slot.visible = not dock_overlay
	_dock_slot.custom_minimum_size.x = dock_width if not dock_overlay else 0.0
	# The timeline decides between its full transport and the overflow header.
	# Give it the width the shell can actually reserve, not the width its own
	# minimum would force on the center column.
	var rail_reserve := 0.0
	if not compact:
		rail_reserve = float(_rail.call("rail_width"))
	var dock_reserve := dock_width if not dock_overlay else 0.0
	_timeline.set_available_width(size.x - rail_reserve - dock_reserve)
	var bottom_inset := 0.0
	if _status_bar.visible:
		bottom_inset += _status_bar.custom_minimum_size.y
	if _bottom_bar.visible:
		bottom_inset += _bottom_bar.custom_minimum_size.y
	_dock.offset_left = -dock_width
	_dock.offset_right = 0.0
	_dock.offset_top = _top_bar.custom_minimum_size.y
	_dock.offset_bottom = -bottom_inset
	_drawer_scrim.offset_top = _top_bar.custom_minimum_size.y
	_drawer_scrim.offset_bottom = -(_bottom_bar.custom_minimum_size.y if _bottom_bar.visible else 0.0)
	_sync_timeline_visibility()
	_update_bottom_bar()
	_update_drawer_tabs()
	_sync_view_header_visibility()
	_refresh_chrome_values()


## A drawer or sheet can begin inside the camera label and cut it mid-word
## ("Persp"). The header is layout, so it yields the space while a surface
## covers the viewport instead of leaving a clipped fragment behind an edge.
func _sync_view_header_visibility() -> void:
	if _view_header == null:
		return
	var covered := _render_mode or _drawer_open
	if _overlay != null and _overlay.has_modal():
		covered = true
	_view_header.visible = not covered


func _refresh_chrome_values() -> void:
	if doc != null:
		_update_header()
	_update_history_buttons()
	_update_chrome_sample()


func _update_chrome_sample(sample: Dictionary = {}) -> void:
	if _status_bar == null:
		return
	if sample.is_empty():
		sample = Perf.sample()
	var keys := 0
	if doc != null and doc.animation != null:
		for track in range(doc.animation.get_track_count()):
			keys += doc.animation.track_get_key_count(track)
	sample["renderer"] = Gfx.renderer_name()
	var objects := 0 if doc == null else doc.objects.size()
	var saved := doc == null or not doc.is_dirty()
	_status_bar.update(sample, objects, keys, saved, _fit_percent)


func _timeline_should_show() -> bool:
	return _timeline_visible


func _apply_collapsed_sections() -> void:
	var raw = Prefs.get_value("editor.collapsed_sections", [])
	var sections: Array = []
	if raw is Array:
		sections.assign(raw)
	_set_section_collapsed("outliner", sections.has("outliner"), false)
	_set_section_collapsed("inspector", sections.has("inspector"), false)


func _set_section_collapsed(section: String, collapsed: bool, persist: bool = true) -> void:
	if section == "outliner" and _outliner != null:
		_outliner.set_collapsed(collapsed)
	elif section == "inspector" and _inspector != null:
		_inspector.set_collapsed(collapsed)
	else:
		return
	if persist:
		var raw = Prefs.get_value("editor.collapsed_sections", [])
		var sections: Array = []
		if raw is Array:
			sections.assign(raw)
		var found := sections.has(section)
		if collapsed and not found:
			sections.append(section)
		elif not collapsed and found:
			sections.erase(section)
		Prefs.set_value("editor.collapsed_sections", sections)
	if is_inside_tree() and _dock != null:
		_apply_shell()


func _sync_timeline_visibility() -> void:
	if _timeline_panel == null:
		return
	# The transport row is always present; only the dope sheet folds away, so
	# a phone keeps the 3D view height until the sheet is asked for.
	var sheet := _timeline_should_show()
	_timeline.set_sheet_visible(sheet)
	# Landscape phones are a first-class surface: the dope sheet gives back
	# height on short screens so the viewport keeps a usable working area.
	match workbench_mode:
		"compact":
			_timeline_panel.custom_minimum_size.y = 180.0 if sheet else FOLDED_TIMELINE
		"desktop":
			_timeline_panel.custom_minimum_size.y = 180.0 if _short else 220.0
			if not sheet:
				_timeline_panel.custom_minimum_size.y = FOLDED_TIMELINE
		_:
			_timeline_panel.custom_minimum_size.y = 156.0 if _short else 180.0
			if not sheet:
				_timeline_panel.custom_minimum_size.y = FOLDED_TIMELINE
	if sheet:
		var extra: float = _timeline.graph_height_hint()
		if _short:
			extra = minf(extra, 40.0)
		_timeline_panel.custom_minimum_size.y += extra

func _on_timeline_mode_changed(_mode: String) -> void:
	_sync_timeline_visibility()

func _toggle_drawer(tab: String) -> void:
	if not _dock_overlay_mode():
		return
	if _drawer_open and _compact_tab == tab:
		_close_drawer()
		return
	_compact_tab = tab
	_open_drawer()

func _open_drawer() -> void:
	if not _dock_overlay_mode():
		return
	_drawer_open = true
	_overlay.clear_toast()
	_drawer_scrim.visible = true
	_dock.visible = true
	_dock.modulate.a = 0.0
	_drawer_scrim.modulate.a = 0.0
	_sync_view_header_visibility()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_dock, "modulate:a", 1.0, 0.13)
	tween.tween_property(_drawer_scrim, "modulate:a", 1.0, 0.13)
	_set_compact_tab(_compact_tab)
	_update_bottom_bar()

func _close_drawer() -> void:
	if not _dock_overlay_mode():
		return
	_drawer_open = false
	_drawer_scrim.visible = false
	_dock.visible = false
	_dock.modulate.a = 1.0
	_sync_view_header_visibility()
	_update_bottom_bar()

func _dock_overlay_mode() -> bool:
	# Compact is always a drawer. Studio keeps its dock only when there is
	# enough width for a real viewport beside it; portrait phones get the same
	# overlay while staying in Studio. Desktop always shrinks to fit, so its
	# logical canvas is never this narrow.
	return workbench_mode == "compact" or (workbench_mode == "studio" and size.x < WIDE_MIN_WIDTH)

func _compact_shell() -> bool:
	return workbench_mode == "compact"


func _set_compact_tab(tab: String) -> void:
	_compact_tab = tab if tab in ["scene", "inspector"] else "scene"
	if (_dock_overlay_mode() or _short) and _dock != null:
		_outliner_panel.visible = _compact_tab == "scene"
		_inspector_panel.visible = _compact_tab == "inspector"
	_update_drawer_tabs()
	_update_bottom_bar()

func _update_drawer_tabs() -> void:
	if _drawer_scene_tab == null:
		return
	var tabbed := _dock_overlay_mode() or _short
	_drawer_scene_tab.set_pressed_no_signal(tabbed and _compact_tab == "scene")
	_drawer_props_tab.set_pressed_no_signal(tabbed and _compact_tab == "inspector")
	if _top_bar != null:
		_top_bar.set_panels_open(_drawer_open)

func _update_bottom_bar() -> void:
	if _bottom_bar == null:
		return
	_bottom_bar.set_timeline_open(_timeline_should_show())
	_bottom_bar.set_active(BottomBarScript.ACTION_SCENE, _drawer_open and _compact_tab == "scene")
	_bottom_bar.set_active(BottomBarScript.ACTION_PROPS, _drawer_open and _compact_tab == "inspector")


func _on_bottom_action(action: String) -> void:
	match action:
		BottomBarScript.ACTION_ADD:
			_open_add_sheet()
		BottomBarScript.ACTION_SCENE:
			_toggle_drawer("scene")
		BottomBarScript.ACTION_PROPS:
			_toggle_drawer("inspector")
		BottomBarScript.ACTION_TIMELINE:
			_toggle_timeline()


func _on_chrome_action(action: String) -> void:
	match action:
		TopBarScript.ACTION_BACK:
			request_close()
		TopBarScript.ACTION_UNDO:
			_undo()
		TopBarScript.ACTION_REDO:
			_redo()
		TopBarScript.ACTION_SAVE:
			_save_project(true)
		TopBarScript.ACTION_RENDER:
			_open_render_sheet()
		TopBarScript.ACTION_RENDER_STILL:
			_open_render_sheet()
		TopBarScript.ACTION_RENDER_SEQUENCE:
			_open_render_sheet()
		TopBarScript.ACTION_SETTINGS:
			_open_settings()
		TopBarScript.ACTION_PANELS:
			_toggle_drawer(_compact_tab)
		TopBarScript.ACTION_TIMELINE:
			_toggle_timeline()
		TopBarScript.ACTION_PERFORMANCE:
			_open_performance_overlay()
		TopBarScript.ACTION_IMPORT:
			_pick_model()
		TopBarScript.ACTION_FRAME:
			_focus_selection()
		TopBarScript.ACTION_FRAME_ALL:
			if _view != null:
				_view.frame_all()
		TopBarScript.ACTION_TOGGLE_GRID:
			if _view != null:
				_view.toggle_grid()
		TopBarScript.ACTION_DUPLICATE:
			if doc != null:
				doc.duplicate_selected()
		TopBarScript.ACTION_DELETE:
			if doc != null:
				doc.delete_selected()
		TopBarScript.ACTION_RESET_LAYOUT:
			set_workspace_mode("auto")
		TopBarScript.ACTION_ABOUT:
			_show_about()
		TopBarScript.ACTION_SHORTCUTS:
			_open_shortcuts_sheet()


func _toggle_timeline() -> void:
	_timeline_user_override = true
	_timeline_visible = not _timeline_visible
	_sync_timeline_visibility()
	_update_bottom_bar()


func _on_timeline_close_requested() -> void:
	# The transport stays on screen while the sheet folds, so the same control
	# has to reopen it. Treating close as one-way left a folded timeline with
	# no way back on Studio and Desktop.
	_toggle_timeline()


# -------------------------------------------------------------------------
# Tools, editing and shortcuts
# -------------------------------------------------------------------------

func _select_tool(tool_id: String) -> void:
	_tool = tool_id
	if _view != null:
		_view.set_tool(_tool)
	if _rail != null:
		_rail.set_tool(_tool)

func _focus_selection() -> void:
	if _view != null:
		_view.focus_selection()

func _on_view_requested(label: String) -> void:
	if _view != null:
		_view.set_view_preset(label)

func _on_view_changed(label: String) -> void:
	if _view_header != null:
		_view_header.set_view_label(label)

func _on_view_grid_changed(enabled: bool) -> void:
	if _view_header != null:
		_view_header.set_grid(enabled)

func _on_view_header_grid_toggled(enabled: bool) -> void:
	if _view != null:
		_view.set_grid_enabled(enabled)

func _undo() -> void:
	if doc == null or not doc.can_undo():
		return
	doc.undo()
	_update_header()
	_update_history_buttons()

func _redo() -> void:
	if doc == null or not doc.can_redo():
		return
	doc.redo()
	_update_header()
	_update_history_buttons()

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if _overlay != null and _overlay.has_modal():
		return
	if key.ctrl_pressed or key.meta_pressed:
		match key.keycode:
			KEY_Z:
				if key.shift_pressed:
					_redo()
				else:
					_undo()
				get_viewport().set_input_as_handled()
			KEY_Y:
				_redo()
				get_viewport().set_input_as_handled()
			KEY_S:
				_save_project(true)
				get_viewport().set_input_as_handled()
		return
	match key.keycode:
		KEY_SPACE:
			if doc != null:
				doc.toggle_play()
			get_viewport().set_input_as_handled()
		KEY_F:
			_focus_selection()
			get_viewport().set_input_as_handled()
		KEY_DELETE:
			if doc != null and doc.selected_id != "":
				doc.delete_selected()
			get_viewport().set_input_as_handled()
		KEY_1:
			_select_tool("select")
		KEY_2:
			_select_tool("move")
		KEY_3:
			_select_tool("rotate")
		KEY_4:
			_select_tool("scale")
		KEY_ESCAPE:
			if _drawer_open:
				_close_drawer()
				get_viewport().set_input_as_handled()

# -------------------------------------------------------------------------
# Add object sheet
# -------------------------------------------------------------------------

func _open_add_sheet() -> void:
	if doc == null:
		return
	if _drawer_open:
		_close_drawer()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)

	body.add_child(Kit.section_label("Geometry"))
	var geometry := GridContainer.new()
	geometry.columns = 2
	geometry.add_theme_constant_override("h_separation", 5)
	geometry.add_theme_constant_override("v_separation", 5)
	body.add_child(geometry)
	geometry.add_child(_sheet_button("Cube", "box", _add_primitive.bind("box")))
	geometry.add_child(_sheet_button("Sphere", "circle", _add_primitive.bind("sphere")))
	geometry.add_child(_sheet_button("Cylinder", "cylinder", _add_primitive.bind("cylinder")))
	geometry.add_child(_sheet_button("Cone", "cone", _add_primitive.bind("cone")))
	geometry.add_child(_sheet_button("Torus", "torus", _add_primitive.bind("torus")))
	geometry.add_child(_sheet_button("Plane", "square", _add_primitive.bind("plane")))

	body.add_child(Kit.vsep())
	body.add_child(Kit.section_label("Scene"))
	var scene_grid := GridContainer.new()
	scene_grid.columns = 2
	scene_grid.add_theme_constant_override("h_separation", 5)
	scene_grid.add_theme_constant_override("v_separation", 5)
	body.add_child(scene_grid)
	scene_grid.add_child(_sheet_button("Empty", "circle-dot-dashed", _add_empty))
	scene_grid.add_child(_sheet_button("Camera", "camera", _add_camera))
	scene_grid.add_child(_sheet_button("Key light", "sun", _add_directional_light))
	scene_grid.add_child(_sheet_button("Omni light", "lightbulb", _add_omni_light))

	body.add_child(Kit.vsep())
	body.add_child(Kit.section_label("Assets"))
	body.add_child(_sheet_button("Import 3D model", "upload", _pick_model))

	var hint := Kit.label("Primitives are placed on the ground at the center of the current view.", 9, Kit.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint)

	_overlay.show_modal("Add object", "Scene elements are independent and can be keyed immediately.", body, [
		{"text": "Close", "compact": true},
	])

func _sheet_button(text_value: String, icon_name: String, action: Callable) -> Button:
	var button := Kit.text_button(text_value, icon_name, false, true)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, Kit.FIELD)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void:
		_overlay.close_modal()
		action.call()
	)
	return button

func _spawn_point() -> Vector3:
	var center := Vector3(0, 0, 0)
	if _view != null:
		center = _view.target
	return Vector3(snappedf(center.x, 0.25), 0.0, snappedf(center.z, 0.25))

func _add_primitive(kind: String) -> void:
	if doc == null:
		return
	var at := _spawn_point()
	at.y = 0.01 if kind == "plane" else 0.5
	doc.add_primitive(kind, at)
	_overlay.toast("%s added" % kind.capitalize(), "check", Kit.SUCCESS)

func _add_empty() -> void:
	if doc == null:
		return
	doc.add_empty(_spawn_point())
	_overlay.toast("Empty added", "check", Kit.SUCCESS)

func _add_camera() -> void:
	if doc == null:
		return
	var at := _spawn_point() + Vector3(2.2, 2.0, 2.8)
	doc.add_camera(at)
	_overlay.toast("Camera added", "camera", Kit.SUCCESS)

func _add_directional_light() -> void:
	if doc == null:
		return
	doc.add_light("directional", Vector3(0, 5, 0))
	_overlay.toast("Key light added", "sun", Kit.SUCCESS)

func _add_omni_light() -> void:
	if doc == null:
		return
	doc.add_light("omni", _spawn_point() + Vector3(1.4, 2.4, 1.2))
	_overlay.toast("Omni light added", "lightbulb", Kit.SUCCESS)

# -------------------------------------------------------------------------
# Import and still rendering
# -------------------------------------------------------------------------

func _pick_model() -> void:
	if doc == null:
		return
	if doc.project_dir == "":
		_save_project(false)
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var filters := PackedStringArray([
			"*.glb, *.gltf, *.obj;3D models;model/gltf-binary,model/gltf+json,application/octet-stream",
		])
		var err := DisplayServer.file_dialog_show(
			"Import 3D model", "", "", false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters, _on_model_selected
		)
		if err != OK:
			_overlay.toast("The file picker could not be opened", "triangle-alert", Kit.DANGER)
	else:
		_overlay.toast("This platform has no native file picker", "triangle-alert", Kit.DANGER)

func _on_model_selected(status: bool, paths: PackedStringArray, _filter_index: int) -> void:
	if not status or paths.is_empty() or doc == null:
		return
	var uri := paths[0]
	var result: Dictionary = Store.import_model(uri, doc.project_dir, "Model")
	if not bool(result.get("ok", false)):
		_overlay.toast(str(result.get("error", "The model could not be imported")), "triangle-alert", Kit.DANGER)
		return
	var at := _spawn_point()
	at.y = 0.0
	doc.add_imported(str(result.get("rel_path", "")), str(result.get("name", "Model")), at)
	_save_project(false)
	var warning := str(result.get("warning", ""))
	if warning != "":
		_overlay.toast(warning, "triangle-alert", Kit.WARNING)
	else:
		_overlay.toast("Imported " + str(result.get("name", "model")), "package-open", Kit.SUCCESS)
	_focus_selection()

func _open_import_sheet() -> void:
	# The import options live in the file picker flow until the dedicated
	# import panel lands. Keeping one entry point means Settings never calls a
	# missing method.
	_pick_model()


func _open_render_sheet() -> void:
	if doc == null or _view == null:
		return
	_overlay.clear_toast()
	doc.pause()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)

	var format_row := HBoxContainer.new()
	format_row.add_theme_constant_override("separation", 8)
	format_row.add_child(Kit.label("Output", 12, Kit.TEXT))
	var format_spacer := Control.new()
	format_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	format_row.add_child(format_spacer)
	format_row.add_child(Kit.mono_label("PNG · still + sequence", 9, Kit.TEXT_MUTED))
	body.add_child(format_row)

	body.add_child(Kit.section_label("Still image"))
	_graphics_choice(body, "Long edge", "px", [
		{"label": "1280", "value": 1280},
		{"label": "1920", "value": 1920},
		{"label": "2560", "value": 2560},
		{"label": "3840", "value": 3840},
	], _render_resolution, func(value: Variant) -> void: _render_resolution = int(value))
	_graphics_choice(body, "Anti-aliasing", "MSAA", [
		{"label": "Off", "value": Viewport.MSAA_DISABLED},
		{"label": "2×", "value": Viewport.MSAA_2X},
		{"label": "4×", "value": Viewport.MSAA_4X},
		{"label": "8×", "value": Viewport.MSAA_8X},
	], _render_msaa, func(value: Variant) -> void: _render_msaa = int(value))

	var still_actions := HBoxContainer.new()
	still_actions.add_theme_constant_override("separation", 8)
	body.add_child(still_actions)
	_render_still_button = Kit.text_button("Quick still", "camera", true, true)
	_render_still_button.tooltip_text = "Capture now and save in app storage"
	_render_still_button.pressed.connect(_quick_still)
	still_actions.add_child(_render_still_button)
	_render_save_button = Kit.text_button("Save still…", "download", false, true)
	_render_save_button.pressed.connect(_render_still)
	still_actions.add_child(_render_save_button)

	body.add_child(Kit.vsep())
	body.add_child(Kit.section_label("Frame sequence"))
	var frame_count := _sequence_frame_count()
	var info := Kit.label(
		"%d frames · %.2f s · %d fps" % [frame_count, doc.duration, maxi(1, doc.fps)],
		10, Kit.TEXT_MUTED
	)
	body.add_child(info)
	_graphics_choice(body, "Frame size", "px", [
		{"label": "720", "value": 720},
		{"label": "1080", "value": 1080},
		{"label": "1440", "value": 1440},
	], _sequence_resolution, func(value: Variant) -> void: _sequence_resolution = int(value))
	_graphics_choice(body, "Anti-aliasing", "MSAA", [
		{"label": "Off", "value": Viewport.MSAA_DISABLED},
		{"label": "2×", "value": Viewport.MSAA_2X},
		{"label": "4×", "value": Viewport.MSAA_4X},
	], _sequence_msaa, func(value: Variant) -> void: _sequence_msaa = int(value))

	_render_sequence_button = Kit.text_button("Render PNG sequence", "film", true, true)
	_render_sequence_button.pressed.connect(_render_sequence)
	body.add_child(_render_sequence_button)

	var progress_box := VBoxContainer.new()
	progress_box.add_theme_constant_override("separation", 5)
	progress_box.visible = false
	body.add_child(progress_box)
	_render_progress = ProgressBar.new()
	_render_progress.min_value = 0.0
	_render_progress.max_value = 1.0
	_render_progress.step = 0.001
	_render_progress.show_percentage = false
	_render_progress.custom_minimum_size.y = 5
	_render_progress.add_theme_stylebox_override("background", Kit.flat_style(Kit.SURFACE_3, Kit.R_CONTROL, Kit.BORDER_SOFT, 0))
	_render_progress.add_theme_stylebox_override("fill", Kit.flat_style(Kit.FOCUS, Kit.R_CONTROL, Kit.FOCUS, 0))
	progress_box.add_child(_render_progress)
	_render_status = Kit.mono_label("", 9, Kit.TEXT_MUTED)
	_render_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress_box.add_child(_render_status)

	var note := Kit.label(
		"Captures use the live 3D renderer, including lights, shadows and materials. " +
		"Sequences are saved as a ZIP of numbered PNG frames; MP4 encoding is not available in this build.",
		9, Kit.TEXT_DIM
	)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)

	_overlay.show_modal("Render", "Real engine captures, saved as image files.", body, [
		{"text": "Done", "primary": true},
	])

func _quick_still() -> void:
	if doc == null or _view == null or _render_busy:
		return
	doc.pause()
	_set_render_busy(true)
	_set_render_progress(0.0, "Capturing still…")
	var image: Image = await _view.capture_still(_render_resolution, _render_msaa)
	_set_render_busy(false)
	if image == null:
		_set_render_progress(0.0, "The still could not be captured.")
		_overlay.toast("The still could not be captured", "triangle-alert", Kit.DANGER)
		return
	_save_still_internal(image)
	_set_render_progress(1.0, "Still captured at %d px." % _render_resolution)

## Quick render is the review loop: the editor becomes a live, full-quality
## playback surface instead of showing a static capture of the current frame.
## Nothing is captured here; the renderer keeps drawing the document in real
## time. Saving a still or a sequence stays in the Render sheet.
func _enter_render_mode() -> void:
	if _render_mode or doc == null or _view == null or _render_busy:
		return
	if _overlay != null and _overlay.has_modal():
		_overlay.close_modal()
	_render_mode = true
	_render_saved_time = doc.current_time
	_render_was_playing = doc.is_playing
	_capture_render_chrome()
	if _drawer_open:
		_close_drawer()
	if _perf_overlay != null:
		_perf_overlay.visible = false
	if _overlay != null:
		_overlay.clear_toast()
	_set_render_chrome_hidden()
	_view.set_render_mode(true)
	if _render_hud != null:
		_render_hud.visible = true
	# A render starts at the first frame. The prior playhead is restored when
	# the user returns to editing, so the review never loses their place.
	doc.seek(0.0, true)
	doc.play()
	_sync_render_hud()


func _exit_render_mode() -> void:
	if not _render_mode:
		return
	_render_mode = false
	if doc != null:
		doc.pause()
		doc.seek(_render_saved_time, true)
		if _render_was_playing:
			doc.play()
	if _view != null:
		_view.set_render_mode(false)
	if _render_hud != null:
		_render_hud.visible = false
	_restore_render_chrome()
	_apply_shell()
	_sync_render_hud()


func _toggle_render_playback() -> void:
	if not _render_mode or doc == null:
		return
	if doc.is_playing:
		doc.pause()
	else:
		doc.play()
	_sync_render_hud()


func _restart_render_playback() -> void:
	if not _render_mode or doc == null:
		return
	doc.seek(0.0, true)
	doc.play()
	_sync_render_hud()


func _sync_render_hud() -> void:
	if doc == null:
		return
	if _render_time_label != null:
		_render_time_label.text = doc.format_timecode(doc.current_time)
	if _render_play_button != null:
		var playing := doc.is_playing
		Kit.set_icon(_render_play_button, "pause" if playing else "play")
		_render_play_button.tooltip_text = "Pause the render preview" if playing else "Resume the render preview"


func _on_document_playback_changed(_time: float, _playing: bool) -> void:
	if _render_mode:
		_sync_render_hud()


func _capture_render_chrome() -> void:
	_render_ui_state = {
		"top": _top_bar != null and _top_bar.visible,
		"status": _status_bar != null and _status_bar.visible,
		"bottom": _bottom_bar != null and _bottom_bar.visible,
		"rail": _rail != null and _rail.visible,
		"header": _view_header != null and _view_header.visible,
		"timeline": _timeline_panel != null and _timeline_panel.visible,
		"dock": _dock != null and _dock.visible,
		"dock_slot": _dock_slot != null and _dock_slot.visible,
		"scrim": _drawer_scrim != null and _drawer_scrim.visible,
		"perf": _perf_overlay != null and _perf_overlay.visible,
		"drawer": _drawer_open,
	}


func _set_render_chrome_hidden() -> void:
	if _top_bar != null:
		_top_bar.visible = false
	if _status_bar != null:
		_status_bar.visible = false
	if _bottom_bar != null:
		_bottom_bar.visible = false
	if _rail != null:
		_rail.visible = false
	if _view_header != null:
		_view_header.visible = false
	if _timeline_panel != null:
		_timeline_panel.visible = false
	if _dock != null:
		_dock.visible = false
	if _dock_slot != null:
		# The slot reserves the dock's width in the HBox. Hiding only the dock
		# panel would leave a dead strip beside the render image.
		_dock_slot.visible = false
	if _drawer_scrim != null:
		_drawer_scrim.visible = false


func _restore_render_chrome() -> void:
	if _top_bar != null:
		_top_bar.visible = bool(_render_ui_state.get("top", true))
	if _status_bar != null:
		_status_bar.visible = bool(_render_ui_state.get("status", false))
	if _bottom_bar != null:
		_bottom_bar.visible = bool(_render_ui_state.get("bottom", false))
	if _rail != null:
		_rail.visible = bool(_render_ui_state.get("rail", true))
	if _view_header != null:
		_view_header.visible = bool(_render_ui_state.get("header", true))
	if _timeline_panel != null:
		_timeline_panel.visible = bool(_render_ui_state.get("timeline", true))
	if _perf_overlay != null:
		_perf_overlay.visible = bool(_render_ui_state.get("perf", false))
	# The drawer only exists in Compact. _apply_shell reads _drawer_open and
	# re-shows the dock and scrim together, so restore the flag, not the nodes.
	_drawer_open = bool(_render_ui_state.get("drawer", false)) and workbench_mode == "compact"
	_render_ui_state.clear()

func _render_still() -> void:
	if doc == null or _view == null or _render_busy:
		return
	doc.pause()
	_set_render_busy(true)
	_set_render_progress(0.0, "Capturing still…")
	var image: Image = await _view.capture_still(_render_resolution, _render_msaa)
	_set_render_busy(false)
	if image == null:
		_set_render_progress(0.0, "The still could not be captured.")
		_overlay.toast("The still could not be captured", "triangle-alert", Kit.DANGER)
		return
	_set_render_progress(1.0, "Still captured at %d px." % _render_resolution)
	_pending_still = image
	var filename := _still_filename()
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var filters := PackedStringArray(["*.png;PNG image;image/png"])
		var err := DisplayServer.file_dialog_show(
			"Export still", "", filename, false,
			DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, filters, _on_still_destination
		)
		if err != OK:
			_save_still_internal()
	else:
		_save_still_internal()

func _on_still_destination(status: bool, paths: PackedStringArray, _filter_index: int) -> void:
	if not status or paths.is_empty():
		_pending_still = null
		return
	var path := paths[0]
	if not path.to_lower().ends_with(".png"):
		path += ".png"
	var image := _pending_still
	_pending_still = null
	if image == null:
		return
	if image.save_png(path) == OK:
		_set_render_progress(1.0, "Still exported.")
		_overlay.toast("Still exported", "image", Kit.SUCCESS)
	else:
		_save_still_internal(image)

func _save_still_internal(image: Image = null) -> String:
	if image == null:
		image = _pending_still
	_pending_still = null
	if image == null:
		return ""
	var dir := "user://renders"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := RenderExport.still_path(dir, _still_base_name())
	if image.save_png(path) == OK:
		_last_render_path = path
		_overlay.toast("Still saved in app storage", "image", Kit.SUCCESS)
		return path
	_overlay.toast("The still could not be written", "triangle-alert", Kit.DANGER)
	return ""

func _still_filename() -> String:
	return _still_base_name() + ".png"

func _still_base_name() -> String:
	var base := ""
	for i in range(doc.title.length()):
		var ch := doc.title.substr(i, 1).to_lower()
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			base += ch
		elif ch == " " or ch == "-" or ch == "_":
			base += "-"
	if base == "":
		base = "kinema"
	if base.length() > 36:
		base = base.substr(0, 36)
	return "%s-%d-%d" % [base, int(Time.get_unix_time_from_system()), Time.get_ticks_msec() % 1000]

func _sequence_frame_count() -> int:
	if doc == null:
		return 0
	return maxi(1, roundi(doc.duration * float(maxi(1, doc.fps))))

func _set_render_busy(busy: bool) -> void:
	_render_busy = busy
	for button in [_render_still_button, _render_save_button, _render_sequence_button]:
		if is_instance_valid(button):
			button.disabled = busy
	if is_instance_valid(_render_progress):
		var parent := _render_progress.get_parent()
		if is_instance_valid(parent):
			parent.visible = busy or (_render_progress.value > 0.0)

func _set_render_progress(value: float, text: String) -> void:
	# The sheet may be closed while an awaited capture is still running, which
	# frees these controls. The render itself should finish quietly, so guard
	# every UI write instead of touching a freed node.
	if not is_instance_valid(_render_progress):
		return
	_render_progress.value = clampf(value, 0.0, 1.0)
	var parent := _render_progress.get_parent()
	if is_instance_valid(parent):
		parent.visible = true
	if is_instance_valid(_render_status):
		_render_status.text = text

func _render_sequence(with_dialog: bool = true) -> void:
	if doc == null or _view == null or _render_busy:
		return
	doc.pause()
	_set_render_busy(true)
	var saved_time: float = doc.current_time
	var fps := maxi(1, doc.fps)
	var count := _sequence_frame_count()
	var dir := RenderExport.sequence_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var started := Time.get_ticks_msec()
	var failed := false
	for i in range(count):
		doc.seek(float(i) / float(fps))
		await get_tree().process_frame
		var image: Image = await _view.capture_still(_sequence_resolution, _sequence_msaa)
		if image == null:
			failed = true
			break
		var frame_path := dir.path_join(RenderExport.frame_name(i + 1))
		if image.save_png(frame_path) != OK:
			failed = true
			break
		_set_render_progress(
			float(i + 1) / float(count),
			"Frame %d of %d · %d px long edge" % [i + 1, count, _sequence_resolution]
		)
	doc.seek(saved_time)
	if failed:
		_remove_sequence_frames(dir)
		_set_render_busy(false)
		_set_render_progress(0.0, "The sequence stopped before every frame was written.")
		_overlay.toast("The sequence could not be completed", "triangle-alert", Kit.DANGER)
		return
	_set_render_progress(1.0, "Packaging %d frames…" % count)
	await get_tree().process_frame
	var zip_path := RenderExport.archive_path("user://renders", _still_base_name())
	var packaged := RenderExport.zip_directory(dir, zip_path)
	if packaged:
		_last_render_path = zip_path
	if packaged:
		# The PNG frames are only an intermediate. Removing them keeps app
		# storage predictable while the ZIP remains a lossless archive.
		_remove_sequence_frames(dir)
	_set_render_busy(false)
	if not packaged:
		_set_render_progress(0.0, "The ZIP archive could not be written. Frames remain in app storage.")
		_overlay.toast("The sequence archive could not be written", "triangle-alert", Kit.DANGER)
		return
	var seconds := float(Time.get_ticks_msec() - started) / 1000.0
	_set_render_progress(1.0, "%d frames packaged in %.1f s." % [count, seconds])
	_pending_zip = zip_path
	if with_dialog and DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var filters := PackedStringArray(["*.zip;ZIP archive;application/zip"])
		var err := DisplayServer.file_dialog_show(
			"Export PNG sequence", "", _still_base_name() + ".zip", false,
			DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, filters, _on_zip_destination
		)
		if err == OK:
			return
	_keep_zip_internal()

func _on_zip_destination(status: bool, paths: PackedStringArray, _filter_index: int) -> void:
	if not status or paths.is_empty():
		_keep_zip_internal()
		return
	var path := paths[0]
	if not path.to_lower().ends_with(".zip"):
		path += ".zip"
	var source := _pending_zip
	if source == "":
		return
	var bytes := FileAccess.get_file_as_bytes(source)
	var file := FileAccess.open(path, FileAccess.WRITE)
	var wrote := false
	if file != null:
		if not bytes.is_empty():
			wrote = file.store_buffer(bytes)
		file.close()
	if wrote:
		_pending_zip = ""
		DirAccess.remove_absolute(source)
		_set_render_progress(1.0, "Sequence exported.")
		_overlay.toast("Sequence exported", "film", Kit.SUCCESS)
	else:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		_keep_zip_internal()

func _remove_sequence_frames(dir: String) -> void:
	var dir_access := DirAccess.open(dir)
	if dir_access == null:
		return
	for name in dir_access.get_files():
		DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)

func _keep_zip_internal() -> void:
	if _pending_zip == "":
		return
	var path := _pending_zip
	_pending_zip = ""
	_set_render_progress(1.0, "Sequence kept in app storage: " + path)
	_overlay.toast("Sequence saved in app storage", "film", Kit.SUCCESS)

# -------------------------------------------------------------------------
# Project menu and settings
# -------------------------------------------------------------------------

func _menu_button(text_value: String, icon_name: String, action: Callable, danger: bool = false) -> Button:
	var button := Kit.text_button(text_value, icon_name, false, true)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, Kit.FIELD)
	if danger:
		button.add_theme_color_override("font_color", Kit.DANGER)
		button.add_theme_color_override("icon_normal_color", Kit.DANGER)
	button.pressed.connect(func() -> void:
		_overlay.close_modal()
		action.call()
	)
	return button

func _open_project_menu() -> void:
	if doc == null:
		return
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	body.add_child(_menu_button("Project settings", "sliders-horizontal", _open_project_settings))
	body.add_child(_menu_button("Graphics and performance", "gauge", _open_graphics_settings))
	body.add_child(_menu_button("Import 3D model", "upload", _pick_model))
	body.add_child(_menu_button("Render and export", "clapperboard", _open_render_sheet))
	body.add_child(Kit.vsep())
	body.add_child(_menu_button("Frame selection", "focus", _focus_selection))
	body.add_child(_menu_button("Show or hide timeline", "panel-bottom", _toggle_timeline))
	body.add_child(Kit.vsep())
	body.add_child(_menu_button("Gesture guide and shortcuts", "keyboard", _show_help))
	body.add_child(_menu_button("About Kinema", "info", _show_about))
	body.add_child(Kit.vsep())
	body.add_child(_menu_button("Close project", "chevron-left", request_close))
	_overlay.show_modal("Project", doc.title, body, [{"text": "Close", "compact": true}])

func _open_project_settings() -> void:
	if doc == null:
		return
	_settings_interp = doc.interpolation
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)

	body.add_child(Kit.section_label("Project name"))
	var name_field := Kit.line_edit("Project name")
	name_field.text = doc.title
	name_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	body.add_child(name_field)

	body.add_child(Kit.section_label("Timing"))
	_settings_duration_field = _number_row(body, "Duration", "SEC", 0.25, 3600.0, 0.1, doc.duration, 46)
	_settings_fps_field = _number_row(body, "Frame rate", "FPS", 1.0, 120.0, 1.0, float(doc.fps), 40)

	body.add_child(Kit.section_label("Interpolation"))
	var modes := _segment_strip(body)
	var mode_group := ButtonGroup.new()
	mode_group.allow_unpress = false
	_settings_linear = Kit.text_toggle("Linear", "", true)
	_style_segment(_settings_linear)
	_settings_linear.button_group = mode_group
	_settings_linear.custom_minimum_size.x = 82
	_settings_linear.button_pressed = _settings_interp == "linear"
	_settings_linear.toggled.connect(func(on: bool) -> void:
		if on:
			_settings_interp = "linear"
			_sync_interpolation_buttons()
	)
	modes.add_child(_settings_linear)
	_settings_cubic = Kit.text_toggle("Cubic", "", true)
	_style_segment(_settings_cubic)
	_settings_cubic.button_group = mode_group
	_settings_cubic.custom_minimum_size.x = 82
	_settings_cubic.button_pressed = _settings_interp == "cubic"
	_settings_cubic.toggled.connect(func(on: bool) -> void:
		if on:
			_settings_interp = "cubic"
			_sync_interpolation_buttons()
	)
	modes.add_child(_settings_cubic)

	var note := Kit.label("Shortening the take removes keys beyond the new end. Frame rate changes the timecode ruler but not the stored key times.", 9, Kit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)

	body.add_child(Kit.vsep())
	var stats := Kit.mono_label("%d objects · %d keys" % [doc.objects.size(), _total_keys()], 9, Kit.TEXT_DIM)
	body.add_child(stats)

	var apply := func() -> void:
		var clean := name_field.text.strip_edges()
		if clean == "":
			clean = doc.title
		doc.begin_edit("Project settings")
		doc.set_title(clean)
		doc.set_fps(int(round(_settings_fps_field.value)))
		doc.set_duration(_settings_duration_field.value)
		doc.set_interpolation(_settings_interp)
		doc.end_edit()
		_save_project(false)
		_overlay.toast("Project settings updated", "check", Kit.SUCCESS)

	_overlay.show_modal("Project settings", "Stored locally with the project document.", body, [
		{"text": "Cancel", "compact": true},
		{"text": "Apply", "primary": true, "callback": apply},
	])

func _segment_strip(parent: Control) -> HBoxContainer:
	# Segmented controls sit on a quiet track. The selected segment is a
	# lighter fill, so the group reads without a frame around every option.
	var track := PanelContainer.new()
	track.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_2, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	parent.add_child(track)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 2)
	track.add_child(strip)
	return strip

func _style_segment(button: Button) -> void:
	button.add_theme_stylebox_override("normal", Kit.flat_style(Color(0, 0, 0, 0), Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("hover", Kit.flat_style(Kit.SURFACE_HOVER, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("pressed", Kit.flat_style(Kit.SURFACE_ACTIVE, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("hover_pressed", Kit.flat_style(Kit.SURFACE_ACTIVE.lightened(0.04), Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	button.add_theme_color_override("font_color", Kit.TEXT_MUTED)
	button.add_theme_color_override("font_hover_color", Kit.TEXT)
	button.add_theme_color_override("font_pressed_color", Kit.TEXT)
	button.add_theme_color_override("font_hover_pressed_color", Kit.TEXT)
	button.add_theme_color_override("icon_normal_color", Kit.TEXT_MUTED)
	button.add_theme_color_override("icon_pressed_color", Kit.TEXT)

func _graphics_choice(parent: Control, title: String, hint: String, options: Array, current_value: Variant, on_change: Callable, disabled: bool = false) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 5)
	parent.add_child(block)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(Kit.label(title, 12, Kit.TEXT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	if hint != "":
		head.add_child(Kit.label(hint, 11, Kit.TEXT_DIM if disabled else Kit.TEXT_MUTED))
	block.add_child(head)

	var strip := _segment_strip(block)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for option in options:
		var data: Dictionary = option
		var value: Variant = data.get("value")
		var button := Kit.text_toggle(str(data.get("label", "")), "", true)
		_style_segment(button)
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.button_pressed = value == current_value
		button.disabled = disabled
		button.toggled.connect(func(on: bool) -> void:
			if on:
				on_change.call(value)
				# A single option edit moves the preset to Custom; keep the
				# preset chips honest instead of leaving the old one lit.
				_sync_preset_buttons()
		)
		strip.add_child(button)

func _open_graphics_settings() -> void:
	_open_settings("graphics")


func _open_settings(category: String = "general") -> void:
	if doc == null:
		return
	var panel = SettingsPanelScript.new()
	panel.setup(self)
	panel.renderer_restart_requested.connect(_on_settings_renderer_restart)
	panel.orientation_requested.connect(_on_settings_orientation)
	panel.open_render_requested.connect(_open_render_sheet)
	panel.open_import_requested.connect(_open_import_sheet)
	_settings_panel = panel
	panel.open(category)
	_show_settings_surface(panel)


func _show_settings_surface(panel: Control) -> void:
	if _overlay == null:
		return
	_overlay.show_sheet(
		"Settings",
		"Device preferences, graphics, performance and output.",
		panel,
		[{"text": "Done", "primary": true}],
		{"width": 860.0}
	)


func _on_settings_renderer_restart(preference: String) -> void:
	var result: Dictionary = Gfx.prepare_renderer_switch(preference)
	if not bool(result.get("restart_required", false)):
		if _overlay != null:
			_overlay.toast("%s is already running" % Gfx.renderer_label(preference), "info", Kit.TEXT_MUTED)
		if _settings_panel != null and is_instance_valid(_settings_panel):
			_settings_panel.call("sync_preset_buttons")
		return
	var args: PackedStringArray = result.get("args", PackedStringArray())
	if args.is_empty() or DisplayServer.get_name() == "headless":
		if _overlay != null:
			_overlay.toast("The renderer request was stored and will apply on the next launch", "restart", Kit.WARNING)
		return
	if doc != null and doc.is_dirty():
		_save_project(false, true)
	OS.set_restart_on_exit(true, args)
	get_tree().quit()


func _on_settings_orientation(value: String) -> void:
	if value == "auto":
		if DisplayServer.has_feature(DisplayServer.FEATURE_ORIENTATION):
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
		return
	var host := get_parent()
	while host != null and not host.has_method("apply_orientation"):
		host = host.get_parent()
	if host == null or not bool(host.call("apply_orientation", value)):
		if _overlay != null:
			_overlay.toast("This device does not allow apps to lock orientation", "triangle-alert", Kit.WARNING)


func _on_settings_pref_changed(key: String) -> void:
	match key:
		"editor.autosave_seconds":
			var seconds := _autosave_seconds()
			if _autosave != null:
				_autosave.wait_time = maxf(0.05, seconds)
				if seconds > 0.0:
					_autosave.start()
				else:
					_autosave.stop()
		"editor.show_fps", "performance.overlay", "performance.frame_graph", \
		"performance.adaptive_quality", "performance.target_fps", \
		"performance.min_preview_scale", "performance.preview_update", \
		"performance.preview_cap", "performance.max_fps", "performance.vsync":
			_apply_perf_preferences()
		"editor.reduce_motion":
			if _overlay != null and _overlay.has_method("set_reduce_motion"):
				_overlay.set_reduce_motion(bool(Prefs.get_value("editor.reduce_motion", false)))
		"editor.haptics":
			if bool(Prefs.get_value("editor.haptics", false)):
				Input.vibrate_handheld(12)
		"editor.gizmo_size", "editor.translate_snap", "editor.rotate_snap", "editor.scale_snap":
			_apply_transform_preferences()
		"editor.timeline_default":
			if _timeline != null:
				_timeline.set_mode(str(Prefs.get_value("editor.timeline_default", "dope")))
		"display.keep_screen_on":
			DisplayServer.screen_set_keep_on(bool(Prefs.get_value("display.keep_screen_on", true)))
		"display.fullscreen":
			if OS.get_name() != "Android" and OS.get_name() != "iOS":
				var fullscreen := bool(Prefs.get_value("display.fullscreen", false))
				DisplayServer.window_set_mode(
					DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
				)
		"display.orientation":
			_on_settings_orientation(str(Prefs.get_value("display.orientation", "auto")))
		_:
			if key.ends_with(".reset"):
				_apply_editor_preferences()
				_apply_perf_preferences()
				if key.begins_with("display"):
					DisplayServer.screen_set_keep_on(bool(Prefs.get_value("display.keep_screen_on", true)))
				if _view != null:
					_view.queue_redraw()
	if _view != null:
		_view.request_preview_update()


func _apply_editor_preferences() -> void:
	if _timeline != null:
		_timeline.set_mode(str(Prefs.get_value("editor.timeline_default", "dope")))
	_apply_transform_preferences()
	if _overlay != null and _overlay.has_method("set_reduce_motion"):
		_overlay.set_reduce_motion(bool(Prefs.get_value("editor.reduce_motion", false)))


func _apply_transform_preferences() -> void:
	if _view == null:
		return
	if _view.has_method("set_gizmo_scale"):
		_view.set_gizmo_scale(float(Prefs.get_value("editor.gizmo_size", 1.0)))
	if _view.has_method("set_snap_values"):
		_view.set_snap_values(
			float(Prefs.get_value("editor.translate_snap", 0.25)),
			float(Prefs.get_value("editor.rotate_snap", 15.0)),
			float(Prefs.get_value("editor.scale_snap", 0.25))
		)


func _autosave_seconds() -> float:
	return clampf(float(Prefs.get_value("editor.autosave_seconds", AUTOSAVE_SECONDS)), 0.0, 600.0)


func _open_workspace_sheet() -> void:
	if doc == null:
		return
	var sheet = WorkspaceSheetScript.new()
	sheet.setup(self)
	sheet.layout_selected.connect(func(mode: String) -> void:
		set_workspace_mode(mode)
		sheet.call_deferred("close")
	)
	sheet.orientation_selected.connect(_on_settings_orientation)
	sheet.ui_scale_changed.connect(func(value: float) -> void:
		Prefs.set_value("display.user_scale", value)
	)
	_workspace_sheet = sheet
	sheet.open(
		str(Prefs.get_value("display.layout", "auto")),
		_fit_percent,
		_fit_user_scale_enabled,
		_fit_clamped
	)
	_overlay.show_sheet(
		"Workspace",
		"Choose an arrangement. Desktop shrinks to fit instead of falling back.",
		sheet,
		[{"text": "Done", "primary": true}],
		{"width": 560.0}
	)


func _graphics_antialiasing(parent: Control, unavailable: String) -> void:
	parent.add_child(Kit.section_label("Anti-aliasing"))
	_graphics_choice(parent, "Samples", "MSAA", [
		{"label": "Off", "value": 0},
		{"label": "2×", "value": 1},
		{"label": "4×", "value": 2},
		{"label": "8×", "value": 3},
	], Gfx.msaa, func(value: Variant) -> void: Gfx.set_option("msaa", value))
	_graphics_choice(parent, "Temporal", unavailable, [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.taa, func(value: Variant) -> void: Gfx.set_option("taa", value))

func _graphics_lighting(parent: Control, unavailable: String) -> void:
	parent.add_child(Kit.vsep())
	parent.add_child(Kit.section_label("Lighting and surfaces"))
	_graphics_choice(parent, "Ambient occlusion", unavailable, [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.ssao, func(value: Variant) -> void: Gfx.set_option("ssao", value))
	_graphics_choice(parent, "AO quality", "", [
		{"label": "Low", "value": 0},
		{"label": "Medium", "value": 1},
		{"label": "High", "value": 2},
		{"label": "Ultra", "value": 3},
	], Gfx.ssao_quality, func(value: Variant) -> void: Gfx.set_option("ssao_quality", value))
	_graphics_choice(parent, "Indirect lighting", unavailable, [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.ssil, func(value: Variant) -> void: Gfx.set_option("ssil", value))
	_graphics_choice(parent, "Screen-space reflections", unavailable, [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.ssr, func(value: Variant) -> void: Gfx.set_option("ssr", value))
	_graphics_choice(parent, "Glow", "", [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.glow, func(value: Variant) -> void: Gfx.set_option("glow", value))
	_graphics_choice(parent, "Volumetric fog", unavailable, [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.volumetric_fog, func(value: Variant) -> void: Gfx.set_option("volumetric_fog", value))

func _graphics_shadows(parent: Control) -> void:
	parent.add_child(Kit.section_label("Shadows"))
	_graphics_choice(parent, "Filter quality", "", [
		{"label": "Low", "value": 0},
		{"label": "Medium", "value": 1},
		{"label": "High", "value": 2},
		{"label": "Ultra", "value": 3},
	], Gfx.shadow_quality, func(value: Variant) -> void: Gfx.set_option("shadow_quality", value))
	_graphics_choice(parent, "Cascades", "sun", [
		{"label": "1", "value": 1},
		{"label": "2", "value": 2},
		{"label": "4", "value": 4},
	], Gfx.shadow_splits, func(value: Variant) -> void: Gfx.set_option("shadow_splits", value))
	_graphics_choice(parent, "Range", "meters", [
		{"label": "25", "value": 25.0},
		{"label": "40", "value": 40.0},
		{"label": "60", "value": 60.0},
		{"label": "100", "value": 100.0},
	], Gfx.shadow_distance, func(value: Variant) -> void: Gfx.set_option("shadow_distance", value))

func _graphics_performance(parent: Control) -> void:
	parent.add_child(Kit.vsep())
	parent.add_child(Kit.section_label("Performance"))
	_graphics_choice(parent, "3D resolution", "%", [
		{"label": "60", "value": 0.6},
		{"label": "80", "value": 0.8},
		{"label": "100", "value": 1.0},
	], Gfx.scale_3d, func(value: Variant) -> void: Gfx.set_option("scale_3d", value))
	_graphics_choice(parent, "Draft while editing", "interaction", [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.draft_editing, func(value: Variant) -> void:
		Gfx.set_draft_editing(value)
		if _view != null:
			_view.set_draft_quality(value)
	)
	_graphics_choice(parent, "Frame cap", "fps", [
		{"label": "30", "value": 30},
		{"label": "60", "value": 60},
		{"label": "90", "value": 90},
		{"label": "120", "value": 120},
	], Gfx.max_fps, func(value: Variant) -> void: Gfx.set_option("max_fps", value))

func graphics_preset_row(parent: Control, reopen: bool = true) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)
	var grid := GridContainer.new()
	grid.columns = 4 if size.x >= 700.0 else 2
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	box.add_child(grid)
	_preset_buttons.clear()
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for entry in [
		{"label": "Performance", "value": "performance"},
		{"label": "Balanced", "value": "balanced"},
		{"label": "Quality", "value": "quality"},
	]:
		var data: Dictionary = entry
		var preset_name := str(data.get("value"))
		var button := Kit.text_toggle(str(data.get("label")), "", true)
		_style_segment(button)
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_meta("preset", preset_name)
		button.button_pressed = Gfx.preset == preset_name
		button.toggled.connect(func(on: bool) -> void:
			if on:
				Gfx.apply_preset(preset_name)
				_sync_preset_buttons()
				if reopen:
					call_deferred("_open_graphics_settings")
		)
		grid.add_child(button)
		_preset_buttons.append(button)

	# Custom is a state readout, not an action. A single option edit already
	# moves the preset there; tapping it would only pretend to do something.
	var custom := Kit.text_toggle("Custom", "", true)
	_style_segment(custom)
	custom.set_meta("preset", "custom")
	custom.button_pressed = Gfx.preset == "custom"
	custom.disabled = true
	custom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(custom)
	_preset_buttons.append(custom)

	var reset := Kit.text_button("Reset to Balanced", "rotate-ccw", false, true)
	reset.custom_minimum_size.y = 44.0
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		Gfx.apply_preset("balanced")
		_sync_preset_buttons()
		if reopen:
			call_deferred("_open_graphics_settings")
	)
	box.add_child(reset)
	_preset_buttons.append(reset)


func _sync_preset_buttons() -> void:
	for button in _preset_buttons:
		if not is_instance_valid(button):
			continue
		var name := str(button.get_meta("preset", ""))
		if name == "":
			continue
		button.set_pressed_no_signal(name == Gfx.preset)
		if name == "custom":
			button.add_theme_color_override(
				"font_disabled_color", Kit.TEXT if name == Gfx.preset else Kit.TEXT_DIM
			)

func _number_row(parent: Control, label_text: String, badge: String, min_value: float, max_value: float, step: float, value: float, badge_width: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label := Kit.label(label_text, 11, Kit.TEXT_MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var field = NumberFieldScript.new()
	field.axis = badge
	field.badge_width = badge_width
	field.axis_color = Kit.TEXT_MUTED
	field.min_value = min_value
	field.max_value = max_value
	field.step = step
	field.custom_minimum_size.x = 134
	field.set_value(value)
	row.add_child(field)
	return field

func _sync_interpolation_buttons() -> void:
	if _settings_linear == null:
		return
	_settings_linear.set_pressed_no_signal(_settings_interp == "linear")
	_settings_cubic.set_pressed_no_signal(_settings_interp == "cubic")

func _total_keys() -> int:
	if doc == null:
		return 0
	var count := 0
	for obj in doc.objects:
		var id := str(obj.get("id", ""))
		for channel in doc.CHANNELS:
			count += doc.get_channel_keys(id, channel).size()
	return count

# -------------------------------------------------------------------------
# Color sheet
# -------------------------------------------------------------------------

func _open_color_sheet(property: String) -> void:
	if doc == null or doc.selected_id == "":
		return
	var obj: Dictionary = doc.get_selected_object()
	if obj.is_empty():
		return
	_color_sheet_active = true
	_color_id = doc.selected_id
	_color_property = property
	_color_value = Color.from_string(str(obj.get(property, "#A8A8A8")), Color(0.6, 0.6, 0.6))
	doc.begin_edit("Change color")

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)

	_color_preview = PanelContainer.new()
	_color_preview.custom_minimum_size.y = 54
	_color_preview.add_theme_stylebox_override("panel", _color_preview_style())
	body.add_child(_color_preview)
	_color_preview_label = Kit.mono_label("#" + _color_value.to_html(false).to_upper(), 11, Kit.TEXT)
	_color_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_color_preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_color_preview.add_child(_color_preview_label)

	body.add_child(Kit.section_label("Palette"))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	body.add_child(grid)
	for hex in COLOR_PALETTE:
		var color := Color.from_string(str(hex), Color.GRAY)
		var swatch := Button.new()
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.custom_minimum_size = Vector2(Kit.FIELD, Kit.FIELD)
		swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		swatch.tooltip_text = str(hex)
		swatch.add_theme_stylebox_override("normal", Kit.flat_style(color, Kit.R_CONTROL, Kit.BORDER, 1))
		swatch.add_theme_stylebox_override("hover", Kit.flat_style(color.lightened(0.09), Kit.R_CONTROL, Kit.TEXT_MUTED, 1))
		swatch.add_theme_stylebox_override("pressed", Kit.flat_style(color.darkened(0.12), Kit.R_CONTROL, Kit.FOCUS, 1))
		swatch.pressed.connect(_set_color_value.bind(color))
		grid.add_child(swatch)

	body.add_child(Kit.section_label("Hex value"))
	_color_hex = Kit.line_edit("#RRGGBB")
	_color_hex.text = "#" + _color_value.to_html(false).to_upper()
	_color_hex.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_color_hex.text_submitted.connect(_on_hex_submitted)
	_color_hex.focus_exited.connect(_on_hex_focus_lost)
	body.add_child(_color_hex)

	body.add_child(Kit.section_label("Channels"))
	for i in range(3):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		body.add_child(row)
		var channel_label := Kit.mono_label(["R", "G", "B"][i], 9, Kit.TEXT_MUTED)
		channel_label.custom_minimum_size.x = 12
		channel_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(channel_label)
		var bar = ScrubBarScript.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = _color_value[i]
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.fill_color = Kit.AXIS_X if i == 0 else (Kit.AXIS_Y if i == 1 else Kit.AXIS_Z)
		bar.value_changed.connect(_on_rgb_changed.bind(i))
		row.add_child(bar)
		_color_rgb.append(bar)

	var note := Kit.label("Colors are written to the object as you edit. Use Undo to revert the whole change.", 9, Kit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)

	_overlay.show_modal(
		"Color" if _color_property == "color" else "Light color",
		"Base color" if _color_property == "color" else "Light tint",
		body,
		[{"text": "Done", "primary": true}]
	)
	_sync_color_controls()

func _color_preview_style() -> StyleBoxFlat:
	var style := Kit.flat_style(_color_value, Kit.R_CONTROL, Kit.BORDER, 1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style

func _set_color_value(color: Color) -> void:
	if not _color_sheet_active or doc == null:
		return
	_color_value = Color(clampf(color.r, 0.0, 1.0), clampf(color.g, 0.0, 1.0), clampf(color.b, 0.0, 1.0), 1.0)
	if _color_property == "color":
		doc.set_material_color(_color_id, _color_value)
	else:
		doc.set_light_property(_color_id, _color_property, "#" + _color_value.to_html(false))
	_sync_color_controls()

func _sync_color_controls() -> void:
	if _color_preview != null:
		_color_preview.add_theme_stylebox_override("panel", _color_preview_style())
	if _color_preview_label != null:
		var luminance := _color_value.r * 0.299 + _color_value.g * 0.587 + _color_value.b * 0.114
		_color_preview_label.add_theme_color_override("font_color", Color(0.03, 0.03, 0.03) if luminance > 0.58 else Color(0.94, 0.94, 0.94))
		_color_preview_label.text = "#" + _color_value.to_html(false).to_upper()
	_color_updating = true
	for i in range(mini(3, _color_rgb.size())):
		_color_rgb[i].set_value(_color_value[i])
	_color_updating = false
	if _color_hex != null and not _color_hex.has_focus():
		_color_hex.text = "#" + _color_value.to_html(false).to_upper()

func _on_rgb_changed(value: float, index: int) -> void:
	if _color_updating:
		return
	var color := _color_value
	color[index] = clampf(value, 0.0, 1.0)
	_set_color_value(color)

func _on_hex_submitted(text_value: String) -> void:
	var clean := text_value.strip_edges()
	if not clean.begins_with("#"):
		clean = "#" + clean
	if not clean.is_valid_html_color():
		if _color_hex != null:
			_color_hex.text = "#" + _color_value.to_html(false).to_upper()
		return
	_set_color_value(Color.from_string(clean, _color_value))

func _on_hex_focus_lost() -> void:
	if _color_hex != null:
		_on_hex_submitted(_color_hex.text)

func _on_modal_opened() -> void:
	# A modal dims the workbench, so its floating HUD must not peek above the
	# surface. The 3D scene remains visible through the scrim.
	if _view != null:
		_view.set_hud_visible(false)
	_sync_view_header_visibility()

func _on_modal_closed() -> void:
	if _view != null and not _render_mode:
		_view.set_hud_visible(true)
	_sync_view_header_visibility()
	if not _color_sheet_active:
		return
	_color_sheet_active = false
	if doc != null and is_instance_valid(doc):
		doc.end_edit()
	_color_preview = null
	_color_preview_label = null
	_color_hex = null
	_color_rgb.clear()

# -------------------------------------------------------------------------
# Help and about
# -------------------------------------------------------------------------

func _show_help() -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 9)
	var intro := Kit.label("Direct manipulation first. Every gesture is reversible from the undo buttons in the top bar.", 11, Kit.TEXT_MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(intro)
	body.add_child(Kit.section_label("Viewport"))
	body.add_child(_help_row("One finger", "Orbit around the scene"))
	body.add_child(_help_row("Two fingers", "Pan and pinch to zoom"))
	body.add_child(_help_row("Tap", "Select an object"))
	body.add_child(_help_row("Drag an axis", "Move, rotate or scale with the active tool"))
	body.add_child(_help_row("Compass chip", "Cycle perspective, front, right and top"))
	body.add_child(Kit.section_label("Animation"))
	body.add_child(_help_row("Timeline ruler", "Scrub the playhead"))
	body.add_child(_help_row("Diamond button", "Key all transforms at the playhead"))
	body.add_child(_help_row("AUTO", "Write a key whenever a transform changes"))
	body.add_child(_help_row("Drag a key", "Retime it, snapped to frames when enabled"))
	body.add_child(_help_row("Speed graph", "Plot engine-sampled speed for the selected channel"))
	body.add_child(_help_row("Ease handles", "Drag a handle or use EASE to change the source key"))
	body.add_child(Kit.section_label("Render and import"))
	body.add_child(_help_row("Render and export", "Still images and PNG frame sequences"))
	body.add_child(_help_row("Quick still", "Capture now at the selected size and MSAA"))
	body.add_child(_help_row("Import model", "glTF/GLB and OBJ; FBX must be converted first"))
	body.add_child(_help_row("Android SAF", "An OBJ may not read sibling MTL/texture files"))
	body.add_child(_help_row("MP4", "Not available; sequences are ZIP files of PNG frames"))
	body.add_child(Kit.section_label("Hardware keyboard"))
	body.add_child(_help_row("Space", "Play or pause"))
	body.add_child(_help_row("F", "Frame selection"))
	body.add_child(_help_row("1 – 4", "Select, move, rotate, scale"))
	body.add_child(_help_row("Ctrl + Z / Shift + Z", "Undo / redo"))
	body.add_child(_help_row("Ctrl + S", "Save project"))
	_overlay.show_modal("Gesture guide", "Kinema is built for touch, not for a mouse.", body, [
		{"text": "Close", "primary": true},
	])

func _help_row(key: String, description: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var key_label := Kit.mono_label(key, 9, Kit.FOCUS_BRIGHT)
	key_label.custom_minimum_size.x = 116
	key_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(key_label)
	var text_label := Kit.label(description, 11, Kit.TEXT_MUTED)
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text_label)
	return row

func _show_about() -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var intro := Kit.label("Kinema Studio is a local-first 3D animation workspace for touch screens. It uses the Godot renderer, animation system and scene runtime as its foundation.", 11, Kit.TEXT_MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(intro)
	body.add_child(Kit.vsep())
	body.add_child(_info_row("Version", "0.1"))
	body.add_child(_info_row("Engine", _engine_version()))
	body.add_child(_info_row("Renderer", Gfx.display_name()))
	body.add_child(_info_row("Project", doc.title if doc != null else "Untitled"))
	body.add_child(Kit.vsep())
	var note := Kit.label("Projects and imported models stay in on-device app storage. Stills are real PNG captures at the selected size and MSAA. Sequences are real PNG frames packaged as a ZIP; MP4 encoding is not included.", 9, Kit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	var limits := Kit.label("Import: glTF/GLB and OBJ. Binary FBX must be converted to GLB or OBJ first because Godot's FBX importer is editor-only. On Android, SAF may prevent an OBJ from reading sibling MTL/texture files.", 9, Kit.TEXT_DIM)
	limits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(limits)
	var licenses := Kit.label("Engine: Godot (MIT). Fonts: IBM Plex Sans and IBM Plex Mono (SIL OFL). Icons: Lucide (ISC). Full notices are bundled with this build.", 9, Kit.TEXT_DIM)
	licenses.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(licenses)
	_overlay.show_modal("About Kinema", "A quiet tool for motion.", body, [
		{"text": "Close", "primary": true},
	])

func _info_row(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Kit.label(key, 10, Kit.TEXT_DIM)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(label)
	var value_label := Kit.mono_label(value, 9, Kit.TEXT_MUTED)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.custom_minimum_size.x = 80
	row.add_child(value_label)
	return row

func _engine_version() -> String:
	var info := Engine.get_version_info()
	return "%d.%d.%d-%s" % [
		int(info.get("major", 4)),
		int(info.get("minor", 0)),
		int(info.get("patch", 0)),
		str(info.get("status", "stable")),
	]
