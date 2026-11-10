extends Control
## Editor workspace.
##
## One stage-first shell for every workspace: a top bar, the current
## workspace's context row, the stage, and the transport (or the Animate pane).
## The scene tree, inspector, rig and shading surfaces share one workspace
## panel, reserved on wide windows and floating on narrow ones.
##
## The document owns all scene and animation state. This script only presents
## it and routes user intent; every mutation goes through Document so undo,
## autosave and serialization stay in one place.

signal exit_requested
## Emitted when the workbench arrangement changes, including when Main
## resolves a different mode for the same preference.
signal layout_mode_changed(mode: String)
signal workspace_changed(id: String)

const DocumentScript = preload("res://src/core/document.gd")
const RenderExport = preload("res://src/core/render_export.gd")
const EditorViewScript = preload("res://src/viewport/editor_view.gd")
const OutlinerScript = preload("res://src/ui/outliner.gd")
const InspectorScript = preload("res://src/ui/inspector.gd")
const TimelineScript = preload("res://src/ui/timeline.gd")
const OverlayScript = preload("res://src/ui/overlay.gd")
const WorkspaceBarScript = preload("res://src/ui/components/workspace_bar.gd")
const ContextBarScript = preload("res://src/ui/components/context_bar.gd")
const TransportBarScript = preload("res://src/ui/components/transport_bar.gd")
const MenuPanelScript = preload("res://src/ui/components/menu_panel.gd")
const StageHostScript = preload("res://src/ui/components/stage_host.gd")
const WorkspacePanelScript = preload("res://src/ui/components/workspace_panel.gd")
const AnimatePaneScript = preload("res://src/ui/animate_pane.gd")
const PerfOverlayScript = preload("res://src/ui/components/perf_overlay.gd")
const SettingsPanelScript = preload("res://src/ui/settings_panel.gd")
const InterfaceSheetScript = preload("res://src/ui/interface_sheet.gd")
const LayoutMathScript = preload("res://src/app/layout_math.gd")
const NumberFieldScript = preload("res://src/ui/num_field.gd")
const PoseLibrary = preload("res://src/core/pose_library.gd")
const ScrubBarScript = preload("res://src/ui/scrub_bar.gd")
const RigPanelScript = preload("res://src/ui/rig_panel.gd")
const RigOverlayScript = preload("res://src/ui/rig_overlay.gd")
const VideoReferenceOverlayScript = preload("res://src/ui/video_reference_overlay.gd")
const MediaExportSheetScript = preload("res://src/ui/media_export_sheet.gd")
const MediaImportSheetScript = preload("res://src/ui/media_import_sheet.gd")
const RenderPanelScript = preload("res://src/ui/render_panel.gd")
const ShadingPanelScript = preload("res://src/ui/shading_panel.gd")
const GlbExportScript = preload("res://src/core/glb_export.gd")
const AudioSheetScript = preload("res://src/ui/audio_sheet.gd")
const VideoReferencePanelScript = preload("res://src/ui/video_reference_panel.gd")
const SequenceRendererScript = preload("res://src/core/sequence_renderer.gd")
const CameraExportScript = preload("res://src/core/camera_export.gd")
const AndroidVideo = preload("res://src/core/android_video.gd")
const GifEncoder = preload("res://src/core/gif_encoder.gd")

## The Forward+ risk confirmation is owned here so every surface uses the same
## copy. `Enable risk` is a primary action, not a destructive one.
const RISK_CONFIRM_TITLE := "Enable high-end Forward+ effects?"
const RISK_CONFIRM_BODY := "Kinema will run the real Forward+ feature set. Some Android GPUs crash or overheat with these effects. If the next launch fails to reach the editor, Kinema returns to the mobile-safe profile automatically."
const RISK_CONFIRM_ACTIONS := [
	{"text": "Cancel", "compact": true},
	{"text": "Enable risk", "primary": true, "destructive": false},
]
const RISK_ENABLED_TOAST := "High-end Forward+ effects enabled"
const RISK_RESTORED_TOAST := "Mobile-safe graphics restored"

const AUTOSAVE_SECONDS := 30.0
const SHORT_MAX_HEIGHT := 520.0
## At this width the Shading/Rig/Render panel becomes part of the layout; the
## stage keeps at least 487 dp (768 - 280 - 1 dp gutter).
const PANEL_RESERVE_MIN_WIDTH := 768.0
const PANEL_RESERVED_MIN := 280.0
const PANEL_RESERVED_MAX := 360.0
const PANEL_OVERLAY_MAX := 400.0
const PANEL_OVERLAY_MARGIN := 16.0

## Material swatches are a graphite ramp. The hex field still accepts any
## colour, but the default palette never pulls the workbench off-message.
const COLOR_PALETTE := [
	"#F2F2F2", "#E0E0E0", "#C8C8C8", "#B0B0B0", "#989898", "#808080",
	"#686868", "#505050", "#3A3A3A", "#2A2A2A", "#1B1B1B", "#101010",
	"#D8D8D8", "#BDBDBD", "#A0A0A0", "#7A7A7A", "#4A4A4A", "#202020",
]

## The five workspaces are the shell's top-level mental model. They are
## independent from the layout preset: a phone can show any workspace in
## Compact or Studio, and the choice survives project open.
const WORKSPACES := ["scene", "shading", "rig", "animate", "render"]
const WORKSPACE_LABELS := {
	"scene": "Scene", "shading": "Shading", "rig": "Rig",
	"animate": "Animate", "render": "Render",
}

var doc: DocumentScript = null

var _project_meta: Dictionary = {}
var _layout: VBoxContainer
var _workspace_bar: PanelContainer
var _context_bar: PanelContainer
var _transport_bar: PanelContainer
var _instrumentation: PanelContainer
var _instrumentation_label: Label
var _instrumentation_visible := false
var _workspace_menu: Control
var _project_menu: Control
var _view_menu: Control
var _rig_axis_menu: Control
var _light_menu: Control
var _camera_menu: Control

var _main: HBoxContainer
var _center: VBoxContainer
var _stage_host: Control
var _workspace_panel: Control
var _workspace_panel_open := false
var _panel_spacer: Control
var _animate_pane: VBoxContainer
var _viewport_host: Control
var _view: Control
var _perf_overlay: PanelContainer
var _rig_overlay: Control
var _rig_mode := false
var _video_overlay: Control
var _timeline: VBoxContainer
var _outliner_panel: PanelContainer
var _inspector_panel: PanelContainer
var _outliner: VBoxContainer
var _inspector: VBoxContainer
var _rig_frame: PanelContainer
var _rig_panel: VBoxContainer
var _shading_panel: VBoxContainer
var _render_panel: VBoxContainer
var _overlay: Control
var _autosave: Timer

var _tool := "select"
var _short := false
var _fit_percent := 100.0
var _fit_user_scale_enabled := true
var _fit_clamped := false
var layout_info: Dictionary = {}
var _layout_preset := "studio"
var _workspace := "scene"
var _workspace_menu_open := false
var _context_workspace := ""
var _closing := false
var _last_save_auto := false

## Two-clock rule bookkeeping: while a sequence runs, the last clip-local
## playhead seen on `.playback_changed` is kept here so the clip transport can
## return to it when the sequence stops.
var _sequence_was_playing := false
var _clip_time_before_sequence := 0.0
var _restoring_clip := false

var _media_busy := false
var _media_cancel := false
var _media_export: Control
var _pending_glb_options: Dictionary = {}

var _color_sheet_active := false
var _color_id := ""
var _color_target: Dictionary = {}
var _color_property := ""
var _color_value := Color(0.6, 0.6, 0.6)
var _color_commit := Callable()
var _color_preview: PanelContainer
var _color_preview_label: Label
var _color_hex: LineEdit
var _color_rgb: Array = []
var _color_updating := false

var _time_frame_field: LineEdit
var _time_seconds_field: LineEdit
var _time_error: Label

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
var _interface_sheet: Control = null
## The material library and editor sheets, kept for smoke/test inspection.
var _material_sheet: Control = null
var _material_editor_sheet: Control = null
## Real-time render preview. The viewport plays the document at full quality
## with editing chrome removed; this flag owns the editor-side lifecycle.
var _render_mode := false
var _render_hud: PanelContainer = null
var _render_play_button: Button = null
var _render_time_label: Label = null
var _render_saved_time := 0.0
var _render_was_playing := false
var _render_ui_state: Dictionary = {}
## Look-through is the document camera's view. The view owns the camera and
## chrome; the editor owns header visibility and Android back precedence.
var _look_through := false
var _look_camera_id := ""
var _look_perf_was_visible := false
## The Animate stage preview split. The auto default is derived from the live
## window height; only the user's toggle writes `editor.animate_stage`.
var _animate_preview_visible := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_restore_animate_preview()
	_layout = VBoxContainer.new()
	_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout.add_theme_constant_override("separation", int(Kit.GUTTER))
	add_child(_layout)

	_build_workspace_bar()
	_build_context_bar()
	_build_body()
	_build_transport_bar()
	_build_instrumentation()
	_build_workspace_panel()
	_build_render_hud()
	_apply_collapsed_sections()

	_overlay = OverlayScript.new()
	add_child(_overlay)
	_overlay.modal_closed.connect(_on_modal_closed)
	_overlay.modal_opened.connect(_on_modal_opened)
	_overlay.set_toast_anchor(_viewport_host)

	# The two shell menus are persistent nodes so their rows and scrim do not
	# have to be rebuilt on every open. They paint above the workbench and below
	# the modal overlay (z 100).
	_workspace_menu = MenuPanelScript.new()
	_workspace_menu.name = "WorkspaceMenu"
	_workspace_menu.row_selected.connect(_on_workspace_menu_row)
	_workspace_menu.closed.connect(func() -> void: _workspace_menu_open = false)
	add_child(_workspace_menu)
	_project_menu = MenuPanelScript.new()
	_project_menu.name = "ProjectMenu"
	_project_menu.row_selected.connect(_on_project_menu_row)
	add_child(_project_menu)

	_view_menu = MenuPanelScript.new()
	_view_menu.name = "ViewMenu"
	_view_menu.row_selected.connect(_on_view_menu_row)
	add_child(_view_menu)
	_rig_axis_menu = MenuPanelScript.new()
	_rig_axis_menu.name = "RigAxisMenu"
	_rig_axis_menu.row_selected.connect(_on_rig_axis_menu_row)
	add_child(_rig_axis_menu)
	_light_menu = MenuPanelScript.new()
	_light_menu.name = "LightMenu"
	_light_menu.row_selected.connect(_on_light_menu_row)
	add_child(_light_menu)
	_camera_menu = MenuPanelScript.new()
	_camera_menu.name = "CameraMenu"
	_camera_menu.row_selected.connect(_on_camera_menu_row)
	add_child(_camera_menu)

	_autosave = Timer.new()
	_autosave.wait_time = _autosave_seconds()
	_autosave.autostart = _autosave.wait_time > 0.0
	_autosave.timeout.connect(_on_autosave)
	add_child(_autosave)

	Perf.sample_updated.connect(_on_perf_sample)
	workspace_changed.connect(_on_workspace_changed)
	_apply_editor_preferences()
	_apply_perf_preferences()

	resized.connect(_on_resized)
	call_deferred("_apply_shell")

# -------------------------------------------------------------------------
# Construction
# -------------------------------------------------------------------------

func _build_workspace_bar() -> void:
	_workspace_bar = WorkspaceBarScript.new()
	_workspace_bar.action_requested.connect(_on_chrome_action)
	_workspace_bar.workspace_tab_requested.connect(_on_workspace_tab_requested)
	_workspace_bar.more_workspaces_requested.connect(_toggle_workspace_menu)
	_workspace_bar.camera_exit_requested.connect(_exit_look_through)
	_layout.add_child(_workspace_bar)

func _build_context_bar() -> void:
	_context_bar = ContextBarScript.new()
	_context_bar.action_requested.connect(_on_context_action)
	_layout.add_child(_context_bar)

func _build_transport_bar() -> void:
	_transport_bar = TransportBarScript.new()
	_transport_bar.play_requested.connect(_on_transport_play)
	_transport_bar.skip_start_requested.connect(_on_transport_skip)
	_transport_bar.time_requested.connect(_open_time_entry_sheet)
	_transport_bar.add_key_requested.connect(_on_transport_add_key)
	_transport_bar.animate_requested.connect(_on_transport_animate)
	_layout.add_child(_transport_bar)

func _build_instrumentation() -> void:
	_instrumentation = PanelContainer.new()
	_instrumentation.name = "Instrumentation"
	_instrumentation.custom_minimum_size.y = 20
	_instrumentation.visible = false
	var style := Kit.flat_style(Kit.SURFACE_2, 0, Color(0, 0, 0, 0), 0)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	_instrumentation.add_theme_stylebox_override("panel", style)
	_instrumentation_label = Kit.mono_label("", 11, Kit.TEXT_MUTED)
	_instrumentation_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_instrumentation.add_child(_instrumentation_label)
	_layout.add_child(_instrumentation)
	_update_instrumentation()

func _build_body() -> void:
	_main = HBoxContainer.new()
	_main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main.add_theme_constant_override("separation", int(Kit.GUTTER))
	_layout.add_child(_main)

	_center = VBoxContainer.new()
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# A one-pixel gutter separates the stage from the Animate pane without
	# stacking same-valued panels edge to edge.
	_center.add_theme_constant_override("separation", int(Kit.GUTTER))
	_main.add_child(_center)

	_stage_host = StageHostScript.new()
	_stage_host.name = "StageHost"
	_stage_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage_host.custom_minimum_size.y = 120
	_stage_host.clip_contents = true
	_center.add_child(_stage_host)

	_view = EditorViewScript.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage_host.setup(_view)
	# Existing overlay code and tests keep their viewport hook; it is the one
	# real viewport host, now owned by StageHost.
	_viewport_host = _stage_host.view_host()
	_view.set_tool(_tool)
	_view.quick_render_requested.connect(_enter_render_mode)
	_view.performance_requested.connect(_toggle_performance_overlay)
	_view.grid_changed.connect(_on_view_grid_changed)
	_view.look_through_exited.connect(_on_view_look_through_exited)

	# The overlay is a sibling of the view so it floats above the 3D surface
	# without becoming part of the viewport's own HUD layout.
	_perf_overlay = PerfOverlayScript.new()
	_viewport_host.add_child(_perf_overlay)

	# Rig mode lives on its own overlay: it draws bones over the image and
	# takes the pointer only while rig mode is engaged.
	_rig_overlay = RigOverlayScript.new()
	_viewport_host.add_child(_rig_overlay)
	_rig_overlay.mode_changed.connect(_on_overlay_mode_changed)

	# The Animate pane is a real sibling below the stage. It owns the one
	# Timeline instance for the whole shell.
	_animate_pane = AnimatePaneScript.new()
	_animate_pane.name = "AnimatePane"
	_animate_pane.visible = false
	_center.add_child(_animate_pane)

	# The rotoscope layer sits on the preview surface itself: above the 3D
	# texture (which renders behind its parent) and below the HUD layer, so
	# buttons stay on top of the reference image.
	_video_overlay = VideoReferenceOverlayScript.new()
	_view.add_child(_video_overlay)
	_video_overlay.setup(doc, _view)
	if _view._hud_root != null:
		_view.move_child(_video_overlay, _view._hud_root.get_index())

	_build_timeline()

	# The reserved panel takes real layout width here. The panel surface itself
	# is a full-rect sibling of the shell; this spacer is the only thing that
	# changes the stage width.
	_panel_spacer = Control.new()
	_panel_spacer.name = "PanelSpacer"
	_panel_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_spacer.custom_minimum_size.x = 0.0
	_main.add_child(_panel_spacer)

	_build_panel_content()

func _build_timeline() -> void:
	_timeline = TimelineScript.new()
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.notice.connect(_on_timeline_notice)
	_timeline.duration_confirmation_requested.connect(_on_timeline_duration_confirmation)
	_timeline.time_entry_requested.connect(_open_time_entry_sheet)
	_timeline.key_info_requested.connect(_open_key_info_sheet)
	_timeline.mode_changed.connect(_on_timeline_mode_changed)
	# The Animate pane is permanent, so fold is a sheet state, not a shell
	# state. The transport's chevron and the compact header's close action both
	# collapse the dope sheet and leave the transport reachable.
	_timeline.close_requested.connect(func() -> void:
		_timeline.set_sheet_visible(not _timeline.sheet_visible())
	)
	_animate_pane.setup(_timeline)
	# Ease/Value/Speed is graph state, unrelated to the Dope/Graph pane tabs.
	var graph: Control = _timeline.segment_graph()
	if graph != null:
		graph.connect("tab_changed", _on_graph_tab_changed)
		graph.call("set_tab", str(Prefs.get_value("editor.graph_tab", "ease")))

## The panel host owns the existing content. The outliner, inspector and rig
## panel keep their signals and state; only their mount point moves.
func _build_panel_content() -> void:
	_outliner_panel = PanelContainer.new()
	_outliner_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_outliner_panel.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE, 0, Color(0, 0, 0, 0), 0))

	_outliner = OutlinerScript.new()
	_outliner.add_requested.connect(_open_add_sheet)
	_outliner.collapse_toggled.connect(func(collapsed: bool) -> void:
		_set_section_collapsed("outliner", collapsed)
	)
	_outliner_panel.add_child(_outliner)

	_inspector_panel = PanelContainer.new()
	_inspector_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector_panel.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE, 0, Color(0, 0, 0, 0), 0))

	_inspector = InspectorScript.new()
	_inspector.add_requested.connect(_open_add_sheet)
	_inspector.color_requested.connect(_open_color_sheet)
	_inspector.choose_material_requested.connect(_edit_material_in_shading)
	_inspector.edit_material_requested.connect(_edit_material_in_shading)
	_inspector.look_through_requested.connect(_enter_camera_view)
	_inspector.collapse_toggled.connect(func(collapsed: bool) -> void:
		_set_section_collapsed("inspector", collapsed)
	)
	_inspector_panel.add_child(_inspector)

	_rig_frame = PanelContainer.new()
	_rig_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rig_frame.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE, 0, Color(0, 0, 0, 0), 0))

	_rig_panel = RigPanelScript.new()
	_rig_panel.rig_mode_changed.connect(_on_rig_mode_changed)
	_rig_panel.import_model_requested.connect(_pick_model)
	_rig_frame.add_child(_rig_panel)
	if doc != null:
		_rig_panel.setup(doc)

	# The Shading workspace embeds the real library and editor. The document
	# arrives with _adopt_document(); setup() is repeated there so both children
	# build against the live MaterialSystem.
	_shading_panel = ShadingPanelScript.new()
	_shading_panel.name = "ShadingPanel"
	_shading_panel.changed.connect(func() -> void: _on_material_sheet_changed(""))
	_shading_panel.delete_requested.connect(_confirm_delete_material)
	_shading_panel.color_requested.connect(_on_material_color_requested)

	_render_panel = RenderPanelScript.new()
	_render_panel.setup(doc, _view)
	_render_panel.export_requested.connect(_export_glb)
	_render_panel.tab_changed.connect(func(_tab: String) -> void:
		if _workspace == "render" and _workspace_panel != null:
			_workspace_panel.set_badge(_render_panel.current_output())
	)
	_media_export = _render_panel.media_sheet()
	_media_export.export_requested.connect(_run_media_export)
	_media_export.cancel_requested.connect(func() -> void: _media_cancel = true)

func _build_workspace_panel() -> void:
	_workspace_panel = WorkspacePanelScript.new()
	_workspace_panel.name = "WorkspacePanel"
	_workspace_panel.setup("Panel", _workspace_bar.custom_minimum_size.y)
	_workspace_panel.closed.connect(_on_workspace_panel_closed)
	add_child(_workspace_panel)

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
	var style := Kit.flat_style(Kit.SURFACE, Kit.R_FLOAT, Color(0, 0, 0, 0), 0)
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


# -------------------------------------------------------------------------
# Documents
# -------------------------------------------------------------------------

## Applies a resolved layout result from Main: the workbench arrangement and
## the interface fit. Main owns the resolution; the editor only presents it.
func apply_layout(layout: Dictionary) -> void:
	layout_info = layout
	# Main already knows the mode it resolved, so this path never notifies it.
	_apply_layout_mode(str(layout.get("mode", "studio")), false)
	apply_fit_info(
		float(layout.get("fit_percent", 100.0)),
		bool(layout.get("user_scale_enabled", true)),
		bool(layout.get("clamped", false))
	)


func layout_mode() -> String:
	return _layout_preset


func workspace() -> String:
	return _workspace


## Switches the workspace and, unless asked otherwise, remembers it for the
## next project open. An unknown id falls back to Scene rather than leaving the
## shell on a surface that does not exist.
func set_workspace(id: String, persist := true) -> void:
	var next := id if id in WORKSPACES else "scene"
	if persist:
		Prefs.set_value("editor.workspace", next)
	if next == _workspace:
		return
	_workspace = next
	_workspace_panel_open = next in ["shading", "rig", "render"]
	_workspace_menu_open = false
	workspace_changed.emit(next)
	call_deferred("_apply_shell")


func workspace_menu_open() -> bool:
	return _workspace_menu_open


## One compact menu for the two secondary workspaces. Rig and Render no longer
## own permanent tabs; the More control carries the active name while either is
## current. The header carries the project title the removed chip used to hold.
func _toggle_workspace_menu() -> void:
	if doc == null or _workspace_menu == null or _workspace_bar == null:
		return
	if _workspace_menu_open:
		_workspace_menu.close()
		_workspace_menu_open = false
		return
	if _project_menu != null:
		_project_menu.close()
	_workspace_menu.set_layout_mode(layout_mode())
	_workspace_menu.set_empty_text("")
	_workspace_menu.set_max_width(280.0)
	_workspace_menu.open_menu(
		_workspace_bar.more_button(),
		"Workspaces",
		doc.title if doc != null else "Untitled",
		false
	)
	var copy := {
		"rig": ["Skeletons, poses and IK", "bone"],
		"render": ["Stills, video, camera tracks and GLB", "clapperboard"],
	}
	for id in ["rig", "render"]:
		var detail: Array = copy[id]
		_workspace_menu.add_row(
			id,
			str(WORKSPACE_LABELS.get(id, id)),
			str(detail[1]),
			str(detail[0]),
			id == _workspace,
			true,
			"",
			44.0
		)
	_workspace_menu_open = true


func _on_workspace_tab_requested(id: String) -> void:
	if _workspace_menu_open and _workspace_menu != null:
		_workspace_menu.close()
		_workspace_menu_open = false
	set_workspace(id)
	_update_header()


func _on_workspace_menu_row(id: String) -> void:
	_workspace_menu_open = false
	set_workspace(id)
	_update_header()


func _on_workspace_changed(_id: String) -> void:
	_update_header()
	_update_rig_badge()
	if _workspace == "shading":
		_sync_shading_target()


# -------------------------------------------------------------------------
# Context row
# -------------------------------------------------------------------------

func _act(id: String, label: String, icon: String, priority: int,
		text := false, toggle := false, width := 0.0, group := "",
		trailing_icon := "") -> Dictionary:
	return {
		"id": id,
		"label": label,
		"icon": icon,
		"priority": priority,
		"text": text,
		"toggle": toggle,
		"menu": [],
		"disabled_reason": "",
		"width": width,
		"group": group,
		"trailing_icon": trailing_icon,
	}


func _context_actions(id: String) -> Array:
	match id:
		"scene":
			return [
				_act("select", "Select", "tool-select", 100, false, true),
				_act("move", "Move", "tool-move", 90, false, true),
				_act("rotate", "Rotate", "tool-rotate", 80, false, true),
				_act("scale", "Scale", "tool-scale", 70, false, true),
				_act("add", "Add", "plus", 60, true),
				_act("camera_view", "Camera", "camera", 50),
				_act("scene_tree", "Scene tree", "layers", 40, false, true),
				_act("inspector", "Properties", "sliders-horizontal", 30, false, true),
				_act("frame", "Frame selection", "focus", 20),
				_act("grid", "Grid", "grid-3x3", 10, false, true),
				_act("view", "View", "orbit", 5),
			]
		"shading":
			return [
				_act("assign", "Assign", "check", 100, true),
				_act("select", "Select", "tool-select", 98, false, true),
				_act("move", "Move", "tool-move", 97, false, true),
				_act("rotate", "Rotate", "tool-rotate", 96, false, true),
				_act("scale", "Scale", "tool-scale", 95, false, true),
				_act("material_new", "New", "plus", 90),
				_act("light_add", "Add light", "lightbulb", 80, false, false, 0.0,
					"", "chevron-down"),
				_act("panel", "Materials panel", "panel-right", 70),
				_act("frame", "Frame selection", "focus", 60),
				_act("grid", "Grid", "grid-3x3", 50, false, true),
				_act("view", "View", "orbit", 40),
				_act("camera_view", "Camera", "camera", 30),
			]
		"rig":
			return [
				_act("pose", "Pose", "", 100, true, false, 60.0, "rig_mode"),
				_act("edit", "Edit", "", 95, true, false, 60.0, "rig_mode"),
				_act("rig_rotate", "Rotate", "tool-rotate", 90, false, true),
				_act("rig_move", "Move", "tool-move", 85, false, true),
				_act("rig_axis", "Free", "", 80, true),
				_act("rig_add", "Add bone", "plus", 70, true),
				_act("rig_reset", "Reset pose", "rotate-ccw", 60),
				_act("rig_done", "Done", "check", 50, true),
				_act("frame", "Frame selection", "focus", 40),
				_act("panel", "Rig panel", "panel-right", 30),
			]
		"animate":
			return [
				_act("select", "Select", "tool-select", 100, false, true),
				_act("move", "Move", "tool-move", 95, false, true),
				_act("rotate", "Rotate", "tool-rotate", 90, false, true),
				_act("scale", "Scale", "tool-scale", 85, false, true),
				_act("dope", "Dope", "", 80, true, false, 60.0, "timeline_mode"),
				_act("graph", "Graph", "", 75, true, false, 60.0, "timeline_mode"),
				_act("fit", "Fit", "focus", 70),
				_stage_toggle_action(),
			]
		"render":
			return [
				_act("render", "Render", "clapperboard", 100, true),
				_act("select", "Select", "tool-select", 98, false, true),
				_act("move", "Move", "tool-move", 97, false, true),
				_act("rotate", "Rotate", "tool-rotate", 96, false, true),
				_act("scale", "Scale", "tool-scale", 95, false, true),
				_act("preview", "Preview", "eye", 90),
				_act("still", "Still", "image", 80),
				_act("panel", "Render panel", "panel-right", 70),
				_act("camera_view", "Camera", "camera", 60),
				_act("frame", "Frame selection", "focus", 50),
				_act("grid", "Grid", "grid-3x3", 40, false, true),
				_act("view", "View", "orbit", 30),
			]
	return []


func _sync_context_actions(force := false) -> void:
	if _context_bar == null:
		return
	if force or _context_workspace != _workspace:
		_context_bar.set_actions(_context_actions(_workspace))
		_context_workspace = _workspace
	_sync_context_state()


## Reads the document and the shell back into the row. It never changes either;
## hidden controls keep their real disabled state for the overflow popup.
func _sync_context_state() -> void:
	if _context_bar == null:
		return
	for tool in ["select", "move", "rotate", "scale"]:
		_context_bar.set_action_active(tool, _tool == tool)
	if _timeline != null:
		_context_bar.set_action_active("dope", _timeline.mode() == "dope")
		_context_bar.set_action_active("graph", _timeline.mode() == "graph")
	if _workspace == "animate":
		var preview_fits := _stage_preview_fits()
		_context_bar.set_action_enabled("stage_toggle", preview_fits,
			"Not enough height for stage preview")
		_context_bar.set_action_active("stage_toggle",
			_animate_preview_visible and preview_fits)
	if _view != null:
		_context_bar.set_action_active("grid", _view.grid_enabled())
	var panel_mode: int = _workspace_panel.mode() if _workspace_panel != null \
		else WorkspacePanelScript.Mode.HIDDEN
	var panel_overlay: bool = panel_mode == WorkspacePanelScript.Mode.OVERLAY
	var panel_reserved: bool = panel_mode == WorkspacePanelScript.Mode.RESERVED
	_context_bar.set_action_active(
		"scene_tree",
		_workspace == "scene" and panel_overlay and _workspace_panel.content() == _outliner_panel)
	_context_bar.set_action_active(
		"inspector",
		_workspace == "scene" and panel_overlay and _workspace_panel.content() == _inspector_panel)
	if _workspace in ["shading", "rig", "render"]:
		_context_bar.set_action_enabled(
			"panel", not panel_reserved, "The panel is already open.")
		_context_bar.set_action_active("panel", panel_reserved or panel_overlay)

	var selected := doc.selected_id if doc != null else ""
	var assign_reason := "Select an object to assign this material."
	var assign_ready := false
	if doc != null and selected != "" and doc.material_system != null:
		assign_reason = "Select a material to assign."
		assign_ready = _shading_panel != null and \
			_shading_panel.selected_material_id() != ""
	_context_bar.set_action_enabled("assign", assign_ready, assign_reason)
	for tool_id in ["select", "move", "rotate", "scale"]:
		_context_bar.set_action_enabled(tool_id, selected != "",
			"Select an object to transform.")

	var rig_id := ""
	var imported := false
	var mode := "pose"
	var transform_mode := "rotate"
	var axis := "free"
	if doc != null and doc.rig_system != null:
		rig_id = doc.rig_system.active_rig_id()
		if rig_id != "":
			imported = bool(doc.rig_system.get_rig(rig_id).get("imported", false))
	if _rig_overlay != null:
		mode = _rig_overlay.mode()
		transform_mode = _rig_overlay.transform_mode()
		axis = _rig_overlay.axis_mode()
	_context_bar.set_action_active("pose", mode == "pose")
	_context_bar.set_action_active("edit", mode == "edit")
	_context_bar.set_action_active("rig_rotate", transform_mode == "rotate")
	_context_bar.set_action_active("rig_move", transform_mode == "move")
	_context_bar.set_action_enabled("edit", not imported,
		"Imported skeleton: rest editing is locked.")
	for id in ["rig_rotate", "rig_move", "rig_axis", "rig_add", "rig_reset", "rig_done"]:
		_context_bar.set_action_enabled(id, rig_id != "", "There is no rig in this project.")
	if imported:
		_context_bar.set_action_enabled("rig_add", false,
			"Imported rig: bone structure is locked. Pose and IK remain editable.")
	var axis_button: Button = _context_bar.action_button("rig_axis")
	if axis_button != null:
		axis_button.text = "Free" if axis == "free" else axis.to_upper()


func _on_context_action(id: String) -> void:
	match id:
		"select", "move", "rotate", "scale":
			_select_tool(id)
		"add":
			_open_add_sheet()
		"camera_view":
			_open_camera_menu()
		"scene_tree":
			_toggle_scene_panel("scene")
		"inspector":
			_toggle_scene_panel("inspector")
		"frame":
			_focus_selection()
		"grid":
			if _view != null:
				_view.toggle_grid()
		"view":
			_open_view_menu(_context_bar.action_button("view"))
		"panel":
			_toggle_workspace_panel()
		"assign":
			_on_shading_assign()
		"material_new":
			_on_shading_new_material()
		"light_add":
			_open_light_menu(_context_bar.action_button("light_add"))
		"pose", "edit", "rig_rotate", "rig_move", "rig_axis", "rig_add", "rig_reset", "rig_done":
			_on_rig_context_action(id)
		"preview":
			_enter_render_mode()
		"render":
			_start_render_output()
		"still":
			_start_render_still()
		"dope", "graph":
			_timeline.set_mode(id)
		"fit":
			_fit_animate_pane()
		"stage_toggle":
			_toggle_animate_preview()
	_sync_context_state()


## The inspector, the Shading context row and the Shading workspace all lead
## here. The material library and editor are embedded children of the panel;
## nothing opens a material modal.
func _edit_material_in_shading(target: Dictionary) -> void:
	if doc == null or _shading_panel == null:
		return
	var object_id := str(target.get("object_id", ""))
	var part_path := str(target.get("part_path", ""))
	var surface := int(target.get("surface", -1))
	set_workspace("shading")
	_workspace_panel_open = true
	_shading_panel.set_target(object_id, part_path, surface)
	var material_id := ""
	if doc.material_system != null:
		material_id = doc.material_system.resolve_assignment(object_id, part_path, surface)
	if material_id != "":
		_shading_panel.select_material(material_id)
	_apply_shell()


func _on_shading_assign() -> void:
	if doc == null or _shading_panel == null:
		return
	set_workspace("shading")
	_workspace_panel_open = true
	_shading_panel.assign_selected()
	_apply_shell()


func _on_shading_new_material() -> void:
	if doc == null or _shading_panel == null:
		return
	set_workspace("shading")
	_workspace_panel_open = true
	_shading_panel.new_material()
	_apply_shell()


## Keeps the embedded panel pointed at the current selection. A part selection
## targets that part's surface; otherwise the whole object is the target.
func _sync_shading_target() -> void:
	if _shading_panel == null or doc == null:
		return
	var object_id := doc.selected_id
	var part_path := ""
	var surface := -1
	if doc.selected_part_object_id != "":
		object_id = doc.selected_part_object_id
		part_path = doc.selected_part_path
	if doc.get("selected_surface") != null:
		surface = int(doc.selected_surface)
	_shading_panel.set_target(object_id, part_path, surface)
	if _workspace == "shading" and _workspace_panel != null:
		_workspace_panel.set_badge(_shading_badge_text())


func _shading_badge_text() -> String:
	if doc == null or doc.selected_id == "":
		return ""
	var obj: Dictionary = doc.get_object(doc.selected_id)
	return str(obj.get("name", "")) if not obj.is_empty() else ""


func _open_light_menu(anchor: Control) -> void:
	if _light_menu == null or doc == null:
		return
	_light_menu.set_layout_mode(layout_mode())
	_light_menu.set_empty_text("")
	_light_menu.open_menu(
		anchor,
		"Light",
		"Add a light",
		layout_mode() != "desktop"
	)
	_light_menu.add_row(
		"directional", "Key light", "sun", "Directional light",
		false, true, "", 44.0
	)
	_light_menu.add_row(
		"omni", "Omni light", "circle-dot", "Omni light",
		false, true, "", 44.0
	)


func _on_light_menu_row(id: String) -> void:
	if id != "directional" and id != "omni":
		return
	_on_add_light(id)
	_sync_context_state()


## A light is a real document object: one undo entry from Document.add_light,
## selected immediately and framed so it never lands out of view.
func _on_add_light(kind: String) -> void:
	if doc == null:
		return
	var at := Vector3(0, 5, 0) if kind == "directional" \
		else _spawn_point() + Vector3(1.4, 2.4, 1.2)
	doc.add_light(kind, at)
	_focus_selection()


func _open_view_menu(anchor: Control) -> void:
	if _view_menu == null or _view == null:
		return
	_view_menu.set_layout_mode(layout_mode())
	_view_menu.set_empty_text("")
	_view_menu.open_menu(anchor, "View", "Camera preset", layout_mode() != "desktop")
	var presets := [
		["Persp", "orbit"],
		["Front", "scan"],
		["Right", "rotate-3d"],
		["Top", "panel-top"],
	]
	for pair in presets:
		_view_menu.add_row(
			str(pair[0]), str(pair[0]), str(pair[1]), "",
			_view.view_preset() == str(pair[0]), true, "", 44.0
		)


func _on_view_menu_row(id: String) -> void:
	if _view != null:
		_view.set_view_preset(id)
	_sync_context_state()


func _open_rig_axis_menu(anchor: Control) -> void:
	if _rig_axis_menu == null or _rig_overlay == null:
		return
	_rig_axis_menu.set_layout_mode(layout_mode())
	_rig_axis_menu.set_empty_text("")
	_rig_axis_menu.open_menu(anchor, "Axis", "Rotation axis", layout_mode() != "desktop")
	for axis in ["free", "x", "y", "z"]:
		var label: String = "Free" if axis == "free" else axis.to_upper()
		_rig_axis_menu.add_row(
			axis, label, "", "",
			_rig_overlay.axis_mode() == axis, true, "", 44.0
		)


func _on_rig_axis_menu_row(id: String) -> void:
	if _rig_overlay != null:
		_rig_overlay.set_axis_mode(id)
	_sync_context_state()


func _on_rig_context_action(id: String) -> void:
	match id:
		"pose", "edit":
			_rig_mode = true
			if doc != null and doc.rig_system != null and _rig_overlay != null:
				var rig_id: String = doc.rig_system.active_rig_id()
				if rig_id != "":
					_rig_overlay.set_rig(rig_id)
				_rig_overlay.set_mode(id)
				if _rig_panel != null:
					_rig_panel.set_mode(_rig_overlay.mode())
			_sync_rig_overlay()
		"rig_rotate":
			if _rig_overlay != null:
				_rig_overlay.set_transform_mode("rotate")
		"rig_move":
			if _rig_overlay != null:
				_rig_overlay.set_transform_mode("move")
		"rig_axis":
			_open_rig_axis_menu(_context_bar.action_button("rig_axis"))
		"rig_add":
			_on_rig_add_bone()
		"rig_reset":
			_confirm_reset_pose()
		"rig_done":
			_on_rig_done()
			set_workspace("scene")


## Reset is a document change, so it asks first. With nothing posed it does
## nothing at all instead of showing a confirmation with no effect.
func _confirm_reset_pose() -> void:
	if doc == null or doc.rig_system == null or _overlay == null:
		return
	var rig_id: String = doc.rig_system.active_rig_id()
	if rig_id == "":
		return
	var rig: Dictionary = doc.rig_system.get_rig(rig_id)
	if not _rig_has_rest_offset(rig):
		return
	_overlay.confirm(
		"Reset pose?",
		"Every posed bone returns to the rig's rest pose. Undo keeps the previous pose.",
		"Reset pose",
		func() -> void:
			doc.rig_system.reset_all_poses(rig_id)
			if _rig_overlay != null:
				_rig_overlay.set_rig(rig_id)
			if _rig_panel != null:
				_rig_panel.refresh()
			_sync_rig_overlay()
	)


func _rig_has_rest_offset(rig: Dictionary) -> bool:
	if rig.is_empty():
		return false
	var pose: Dictionary = rig.get("pose", {})
	var posed: Dictionary = pose.get("bones", {}) if pose.has("bones") else pose
	if posed.is_empty():
		return false
	var rest: Dictionary = {}
	for bone in rig.get("bones", []):
		rest[str(bone.get("name", ""))] = bone
	for bone_name in posed.keys():
		if not rest.has(bone_name):
			continue
		var entry: Dictionary = posed[bone_name]
		var rest_bone: Dictionary = rest[bone_name]
		if entry.has("p"):
			if PoseLibrary.array_to_vec3(entry["p"]).distance_to(
					rest_bone.get("p", Vector3.ZERO)) > 0.0001:
				return true
		if entry.has("r"):
			var posed_rotation: Quaternion = PoseLibrary.array_to_quat(entry["r"])
			var rest_rotation: Quaternion = rest_bone.get("r", Quaternion.IDENTITY)
			if absf(posed_rotation.angle_to(rest_rotation)) > 0.0001:
				return true
		if entry.has("s"):
			if PoseLibrary.array_to_vec3(entry["s"]).distance_to(
					rest_bone.get("s", Vector3.ONE)) > 0.0001:
				return true
	return false


func _fit_animate_pane() -> void:
	if doc == null or _timeline == null:
		return
	_timeline.fit_time_view()


func _visible_shell_action_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for bar in [_workspace_bar, _context_bar, _transport_bar]:
		if bar == null or not bar.visible:
			continue
		for id in bar.visible_action_ids():
			ids.append(id)
	return ids


func _shell_action_icon(id: String) -> String:
	for bar in [_workspace_bar, _context_bar, _transport_bar]:
		if bar == null:
			continue
		var button: Button = bar.action_button(id)
		if button != null:
			return str(button.get_meta("action_icon", ""))
	return ""


## The camera menu is the Scene/Render look-through entry point. It lists the
## document cameras, the Add camera row and, only while active, Exit.
func _open_camera_menu() -> void:
	if doc == null or _camera_menu == null:
		return
	_camera_menu.set_layout_mode(layout_mode())
	_camera_menu.set_empty_text("")
	var anchor: Control = _context_bar.action_button("camera_view") \
		if _context_bar != null else _workspace_bar.more_button()
	_camera_menu.open_menu(anchor, "CAMERA", "", layout_mode() != "desktop")
	var cameras: Array = []
	for obj in doc.objects:
		if str(obj.get("kind", "")) == "camera":
			cameras.append(obj)
	cameras.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	for obj in cameras:
		var camera_id := str(obj.get("id", ""))
		var visible := bool(obj.get("visible", true))
		_camera_menu.add_row(
			camera_id, str(obj.get("name", camera_id)), "camera", "",
			camera_id == _look_camera_id, visible,
			"" if visible else "Camera is hidden.", 44.0
		)
	_camera_menu.set_empty_text(
		"No scene cameras. Add one to look through it." if cameras.is_empty() else "")
	_camera_menu.add_separator()
	_camera_menu.add_action(
		"add_camera", "Add camera…", "plus", not _look_through,
		"Exit camera view to add a camera.")
	if _look_through:
		_camera_menu.add_action("exit_camera", "Exit camera view", "x")


func _on_camera_menu_row(id: String) -> void:
	if id == "add_camera":
		# The camera lives in the Add sheet with every other scene element.
		_open_add_sheet()
	elif id == "exit_camera":
		_exit_look_through()
	else:
		_enter_camera_view(id)


# -------------------------------------------------------------------------
# Stage transport and time entry
# -------------------------------------------------------------------------

func _on_transport_play() -> void:
	if doc != null:
		doc.toggle_play()
	_sync_transport_state()


func _on_transport_skip() -> void:
	if doc == null:
		return
	doc.pause()
	doc.seek(0.0)
	_sync_transport_state()


func _on_transport_add_key() -> void:
	if doc == null or doc.selected_id == "":
		return
	doc.insert_transform_keys()
	_sync_transport_state()


func _on_transport_animate() -> void:
	set_workspace("animate")


func _sync_transport_state() -> void:
	if _transport_bar == null:
		return
	if doc == null:
		_transport_bar.set_playing(false)
		_transport_bar.set_timecode("00:00:00")
		_transport_bar.set_add_key_enabled(false, "Select an object to add a key.")
		return
	_transport_bar.set_playing(doc.is_playing)
	_transport_bar.set_timecode(doc.format_timecode(doc.current_time))
	_transport_bar.set_add_key_enabled(
		doc.selected_id != "", "Select an object to add a key.")


## Real frame/time entry. The frame field wins when both are filled; the time
## field is converted to frames when the frame field is empty. Invalid input
## stays in the sheet with an inline message and never seeks.
func _open_time_entry_sheet() -> void:
	if doc == null or _overlay == null:
		return
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size.y = 44.0
	body.add_child(row)

	var frame_box := VBoxContainer.new()
	frame_box.add_theme_constant_override("separation", 2)
	frame_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame_box.add_child(Kit.mono_label("FRAME", 10, Kit.TEXT_DIM))
	_time_frame_field = Kit.line_edit("Frame")
	_time_frame_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_time_frame_field.custom_minimum_size.y = 44.0
	frame_box.add_child(_time_frame_field)
	row.add_child(frame_box)

	var seconds_box := VBoxContainer.new()
	seconds_box.add_theme_constant_override("separation", 2)
	seconds_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seconds_box.add_child(Kit.mono_label("SECONDS", 10, Kit.TEXT_DIM))
	_time_seconds_field = Kit.line_edit("Seconds")
	_time_seconds_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_time_seconds_field.custom_minimum_size.y = 44.0
	seconds_box.add_child(_time_seconds_field)
	row.add_child(seconds_box)

	_time_error = Kit.label("", 11, Kit.DANGER)
	_time_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_time_error.visible = false
	body.add_child(_time_error)

	_time_frame_field.text_submitted.connect(func(_text: String) -> void:
		_apply_time_entry()
	)
	_time_seconds_field.text_submitted.connect(func(_text: String) -> void:
		_apply_time_entry()
	)

	_overlay.show_sheet(
		"Go to time",
		"Enter a frame or a time in seconds.",
		body,
		[
			{"text": "Cancel", "compact": true},
			{"text": "Go", "primary": true, "callback": _apply_time_entry},
		],
		{"on_close": _return_focus_to_timeline}
	)
	_time_frame_field.grab_focus()


## Numeric key sheet for the selected graph key. Position/scale are edited as
## real component values; quaternions stay with the rig gizmo because a
## component-wise quaternion edit is not the rotation the user sees.
func _open_key_info_sheet(index: int) -> void:
	if doc == null or _overlay == null or _timeline == null:
		return
	var graph: Control = _timeline.segment_graph()
	var object_id: String = doc.selected_id
	var channel := "position"
	if graph != null:
		if str(graph.call("context_object")) != "":
			object_id = str(graph.call("context_object"))
		if str(graph.call("context_channel")) != "":
			channel = str(graph.call("context_channel"))
	var keys: Array = doc.get_channel_keys(object_id, channel)
	if index < 0 or index >= keys.size():
		_timeline.notice.emit("Select a key first.")
		return
	var key: Dictionary = keys[index]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	if channel == "rotation":
		var warning := Kit.label(
			"Rotation values are quaternion components; edit them with the rig gizmo.",
			Kit.TYPE_BODY, Kit.TEXT_DIM)
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(warning)
		_overlay.show_sheet("Key", "Rotation keys are edited with the rig gizmo.",
			body, [{"text": "Close", "compact": true}])
		return

	var time_box := VBoxContainer.new()
	time_box.add_theme_constant_override("separation", 2)
	time_box.add_child(Kit.mono_label("TIME (S)", 10, Kit.TEXT_DIM))
	var time_field = Kit.line_edit("Seconds")
	time_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	time_field.custom_minimum_size.y = 44.0
	time_field.text = "%.3f" % float(key["time"])
	time_box.add_child(time_field)
	body.add_child(time_box)

	var value_row := HBoxContainer.new()
	value_row.add_theme_constant_override("separation", 8)
	value_row.custom_minimum_size.y = 44.0
	body.add_child(value_row)
	var value: Vector3 = key["value"] if key["value"] is Vector3 else Vector3.ZERO
	var components := [value.x, value.y, value.z]
	var fields: Array = []
	for axis in range(3):
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(Kit.mono_label(["X", "Y", "Z"][axis], 10, Kit.TEXT_DIM))
		var field = Kit.line_edit(["X", "Y", "Z"][axis])
		field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
		field.custom_minimum_size.y = 44.0
		field.text = "%.3f" % float(components[axis])
		box.add_child(field)
		value_row.add_child(box)
		fields.append(field)

	var error := Kit.label("", 11, Kit.DANGER)
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error.visible = false
	body.add_child(error)

	var apply := func() -> void:
		if not is_instance_valid(time_field):
			return
		var seconds_text: String = str(time_field.text).strip_edges()
		if seconds_text == "" or not seconds_text.is_valid_float():
			error.text = "Enter a time in seconds."
			error.visible = true
			return
		var parts: Array = []
		for field in fields:
			var axis_text: String = field.text.strip_edges()
			if axis_text == "" or not axis_text.is_valid_float():
				error.text = "Enter X, Y and Z values."
				error.visible = true
				return
			parts.append(axis_text.to_float())
		var new_value := Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		var result: Dictionary = doc.move_key(object_id, channel, index,
			seconds_text.to_float(), new_value)
		if not bool(result.get("ok", false)):
			error.text = str(result.get("error", "Curve data no longer matches these keys."))
			error.visible = true
			return
		_overlay.close_modal()

	_overlay.show_sheet("Key", "Move the selected key in time or edit its value.",
		body,
		[
			{"text": "Cancel", "compact": true},
			{"text": "Apply", "primary": true, "callback": apply},
		],
		{"on_close": _return_focus_to_timeline})
	time_field.grab_focus()


## The Animate timecode opens the same sheet as the shared transport; closing
## it returns focus to the timeline so keyboard shortcuts stay in the pane.
func _return_focus_to_timeline() -> void:
	if _workspace != "animate" or _timeline == null or not _timeline.visible:
		return
	if _timeline.time_button() != null and _timeline.time_button().visible:
		_timeline.time_button().grab_focus()


func _apply_time_entry() -> void:
	if doc == null or _overlay == null:
		return
	if _time_frame_field == null or not is_instance_valid(_time_frame_field):
		return
	var frame_text := _time_frame_field.text.strip_edges()
	var seconds_text := _time_seconds_field.text.strip_edges() if _time_seconds_field != null else ""
	var frame := -1.0
	if frame_text != "":
		if frame_text.is_valid_float():
			frame = frame_text.to_float()
	elif seconds_text != "":
		if seconds_text.is_valid_float():
			frame = seconds_text.to_float() * float(doc.fps)
	if frame < 0.0:
		if _time_error != null:
			_time_error.text = "Enter a frame or a time in seconds."
			_time_error.visible = true
		return
	var last_frame := maxf(roundf(doc.duration * float(doc.fps)), 0.0)
	frame = clampf(roundf(frame), 0.0, last_frame)
	doc.pause()
	doc.seek(frame / float(doc.fps))
	_overlay.close_modal()
	_sync_transport_state()





## User intent. Persists the preference and, when the shell is hosted by Main,
## asks it to re-resolve; without a host the mode is resolved here so pure
## scenes and tests behave identically.
func set_layout_mode(mode: String) -> void:
	var next := mode if mode in ["auto", "compact", "studio", "desktop"] else "auto"
	Prefs.set_value("display.layout", next)
	if _layout_hosted():
		# Main re-resolves and calls apply_layout, which applies the mode and
		# emits layout_mode_changed if the arrangement actually changed.
		var host := get_parent()
		while host != null and not host.has_method("refresh_layout_scale"):
			host = host.get_parent()
		if host != null:
			host.call("refresh_layout_scale")
		return
	_apply_layout_mode(_resolve_local(next), true)


func apply_fit_info(fit_percent: float, user_scale_enabled: bool, clamped: bool) -> void:
	_fit_percent = clampf(fit_percent, 1.0, 100.0)
	_fit_user_scale_enabled = user_scale_enabled
	_fit_clamped = clamped
	if _settings_panel != null and is_instance_valid(_settings_panel) and _settings_panel.has_method("refresh_fit"):
		_settings_panel.call("refresh_fit")
	if _interface_sheet != null and is_instance_valid(_interface_sheet) and _interface_sheet.has_method("refresh_fit"):
		_interface_sheet.call("refresh_fit", _fit_percent, _fit_clamped)


func fit_percent() -> float:
	return _fit_percent


func fit_user_scale_enabled() -> bool:
	return _fit_user_scale_enabled


func fit_clamped() -> bool:
	return _fit_clamped


func _apply_layout_mode(mode: String, notify: bool) -> void:
	var next := mode if mode in ["compact", "studio", "desktop"] else "studio"
	var changed := next != _layout_preset
	_layout_preset = next
	_apply_shell()
	if changed and notify:
		layout_mode_changed.emit(next)


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
	var fit_desktop := layout_mode() != "compact"
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
	if doc != null and is_instance_valid(doc) and doc != document \
			and doc.rig_adopted.is_connected(_on_rig_adopted):
		doc.rig_adopted.disconnect(_on_rig_adopted)
	doc = document
	_rig_mode = false
	if not Gfx.changed.is_connected(_on_graphics_changed):
		Gfx.changed.connect(_on_graphics_changed)
	doc.apply_graphics()
	if _view != null:
		_view.set_document(doc)
		_view.set_tool(_tool)
	_outliner.setup(doc)
	_inspector.setup(doc)
	_timeline.setup(doc)
	_rig_panel.setup(doc)
	_shading_panel.setup(doc)
	# Existing tests inspect the embedded children through these aliases; they
	# are the only material library and editor instances.
	_material_sheet = _shading_panel.material_sheet()
	_material_editor_sheet = _shading_panel.material_editor()
	_sync_shading_target()
	_render_panel.setup(doc, _view)
	if _video_overlay != null:
		_video_overlay.setup(doc, _view)
	if _rig_overlay != null:
		_rig_overlay.setup(doc, _view, doc.rig_system)
	doc.scene_changed.connect(_on_document_scene_changed)
	if not doc.rigs_changed.is_connected(_on_document_rigs_changed):
		doc.rigs_changed.connect(_on_document_rigs_changed)
	if not doc.rig_selection_changed.is_connected(_on_document_rig_selection_changed):
		doc.rig_selection_changed.connect(_on_document_rig_selection_changed)
	if not doc.rig_adopted.is_connected(_on_rig_adopted):
		doc.rig_adopted.connect(_on_rig_adopted)
	doc.selection_changed.connect(_on_document_selection_changed)
	doc.dirty_changed.connect(_on_document_dirty_changed)
	doc.history_changed.connect(_on_document_history_changed)
	if not doc.playback_changed.is_connected(_on_document_playback_changed):
		doc.playback_changed.connect(_on_document_playback_changed)
	doc.seek(doc.current_time, true)
	# A load restores the playhead with a silent seek, so no playback event can
	# carry it into the sequence snapshot. Adopt it explicitly.
	_clip_time_before_sequence = float(doc.current_time)
	_sequence_was_playing = false
	if _rig_overlay != null:
		_rig_overlay.set_rig("")
		_sync_rig_overlay()
	if _video_overlay != null:
		_video_overlay.refresh()
	_sync_sequence_transport()
	_update_header()
	_update_history_buttons()
	_select_tool(_tool)
	var saved_workspace := str(Prefs.get_value("editor.workspace", "scene"))
	_workspace = saved_workspace if saved_workspace in WORKSPACES else "scene"
	_workspace_panel_open = _workspace in ["shading", "rig", "render"]
	_workspace_menu_open = false
	# Both calls end with a deferred reframe; arrange the shell once the new
	# document's deferred work has run so the first frame is already correct.
	call_deferred("_apply_shell")

func _on_document_scene_changed() -> void:
	_update_header()
	_sync_transport_state()
	_guard_camera_view()
	if _render_panel != null:
		_render_panel.refresh()


## A deleted or hidden camera must never leave the editor stuck in a view whose
## source object is gone. The exit restores the saved editing layout first, then
## the toast explains the jump.
func _guard_camera_view() -> void:
	if not _look_through or _look_camera_id == "":
		return
	if _camera_target_valid(_look_camera_id):
		return
	_exit_look_through()
	if _overlay != null:
		_overlay.toast("Camera removed — returned to the editor view.", "camera", Kit.WARNING)

func _on_document_rigs_changed() -> void:
	if doc != null and _rig_overlay != null and _rig_mode:
		_rig_overlay.set_rig(doc.rig_system.active_rig_id())
	_sync_rig_overlay()
	_update_rig_badge()


func _on_document_rig_selection_changed(_rig_id: String, _bone: String) -> void:
	_sync_context_state()
	_update_rig_badge()


## The Rig workspace panel's state badge names the active rig, or says there
## is none. Every other workspace keeps an empty badge.
func _update_rig_badge() -> void:
	if _workspace_panel == null:
		return
	if _workspace != "rig":
		_workspace_panel.set_badge("")
		return
	var badge := "No rig"
	if doc != null and doc.rig_system != null:
		var rig_id: String = doc.rig_system.active_rig_id()
		if rig_id != "":
			var rig: Dictionary = doc.rig_system.get_rig(rig_id)
			if not rig.is_empty():
				badge = str(rig.get("name", "Rig"))
	_workspace_panel.set_badge(badge)

func _on_rig_mode_changed(_enabled: bool) -> void:
	_sync_rig_overlay()

func _on_overlay_mode_changed(mode: String) -> void:
	if _rig_panel != null:
		_rig_panel.set_mode(mode)

func _on_toolbar_mode_changed(mode: String) -> void:
	if _rig_overlay != null:
		_rig_overlay.set_mode(mode)

func _on_rig_add_bone() -> void:
	if doc == null or doc.rig_system == null:
		return
	var rig_id: String = doc.rig_system.active_rig_id()
	if rig_id == "":
		return
	var rig: Dictionary = doc.rig_system.get_rig(rig_id)
	if rig.is_empty() or bool(rig.get("imported", false)):
		return
	var created: String = doc.rig_system.extrude_bone(rig_id, str(rig.get("active_bone", "")))
	if created == "":
		return
	if _rig_mode and _rig_overlay != null:
		_rig_overlay.set_rig(rig_id)
	if _rig_panel != null:
		# The new bone is active in rig_system; refresh re-renders the tree row
		# and inspector so the selection is visible, not just stored.
		_rig_panel.refresh()
	_sync_rig_overlay()

func _on_rig_done() -> void:
	# Done leaves the rig in the document. It only clears the workbench state:
	# the overlay stops drawing and the workbench returns to Scene.
	_rig_mode = false
	if _rig_overlay != null:
		_rig_overlay.set_rig("")
		_rig_overlay.set_enabled(false)
	_sync_rig_overlay()

func _sync_rig_overlay() -> void:
	var active := ""
	var imported := false
	if doc != null:
		active = doc.rig_system.active_rig_id()
		if active != "":
			imported = bool(doc.rig_system.get_rig(active).get("imported", false))
	# Look-through is the document camera's clean view: the rig workbench layer
	# is suppressed until the view exits.
	var engaged := _rig_mode and active != "" and not _render_mode and not _look_through
	if _rig_overlay != null:
		if engaged:
			if str(_rig_overlay._rig_id) != active:
				_rig_overlay.set_rig(active)
		elif not _rig_mode:
			_rig_overlay.set_rig("")
		if imported and _rig_overlay.mode() == "edit":
			_rig_overlay.set_mode("pose")
		_rig_overlay.set_enabled(engaged and bool(Prefs.get_value("rig.show_overlay", true)))
	if _rig_panel != null and _rig_overlay != null:
		_rig_panel.set_mode(_rig_overlay.mode())

func _on_graphics_changed() -> void:
	if doc != null:
		doc.apply_graphics()
	_sync_preset_buttons()

func _on_document_selection_changed(_id: String) -> void:
	_update_history_buttons()
	_sync_transport_state()
	_sync_context_state()
	_sync_shading_target()
	if _render_panel != null:
		_render_panel.refresh()

func _on_document_dirty_changed(_is_dirty: bool) -> void:
	_update_header()
	_update_history_buttons()

func _on_document_history_changed() -> void:
	_update_history_buttons()

# -------------------------------------------------------------------------
# Header and status
# -------------------------------------------------------------------------

func _update_header() -> void:
	if _workspace_bar == null:
		return
	_workspace_bar.set_workspace(_workspace)
	if doc == null:
		_workspace_bar.set_project("Untitled", false)
		return
	_workspace_bar.set_project(doc.title, doc.is_dirty())

func _update_history_buttons() -> void:
	if _workspace_bar == null:
		return
	var has_undo := doc != null and doc.can_undo()
	var has_redo := doc != null and doc.can_redo()
	_workspace_bar.set_history(has_undo, has_redo)

## Reports the renderer the engine is actually running. Godot selects a
## renderer when the process starts; the chips request one for the next launch
## and the actual value below is always read back from RenderingServer.
func _open_renderer_sheet() -> void:
	var current := Gfx.renderer_name()
	var requested := Gfx.project_renderer_request()
	_renderer_pending = current
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var headline := Kit.label(Gfx.display_name(), 13, Kit.TEXT, 500)
	body.add_child(headline)

	var strip := _segment_strip(body)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	var blocked_reasons: Array[String] = []
	var entry_notes: Array[String] = []
	for entry in Gfx.renderer_entries(OS.get_name()):
		var data: Dictionary = entry
		if not bool(data["supported"]):
			blocked_reasons.append(str(data["reason"]))
			continue
		var note := str(data.get("note", ""))
		if note != "":
			entry_notes.append(note)
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

	for note in entry_notes:
		var note_label := Kit.label(note, 11, Kit.TEXT_MUTED)
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(note_label)
	if Gfx.last_renderer_error != "":
		var error_label := Kit.label(Gfx.last_renderer_error, 11, Kit.WARNING)
		error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(error_label)

	var note := Kit.label(
		"Godot chooses the renderer before the first frame. Restart applies the selected backend with a real engine flag and never launches a backend this platform cannot use; the row above keeps reporting the renderer that is actually in use.",
		11, Kit.TEXT_DIM
	)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	for reason in blocked_reasons:
		var reason_label := Kit.label(reason, 11, Kit.TEXT_DIM)
		reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(reason_label)
	_overlay.show_sheet("Renderer", "Graphics backend reported by the engine", body, [
		{"text": "Close", "compact": true},
		{"text": "Restart", "primary": true, "callback": _restart_with_renderer},
	], {"width": 720.0})

func _restart_with_renderer() -> void:
	var value := _renderer_pending
	if value == "" or value == Gfx.renderer_name():
		_overlay.toast("That renderer is already running", "info", Kit.TEXT_MUTED)
		return
	# The gate lives in Gfx: it refuses a backend the platform cannot serve and
	# only ever hands back engine restart arguments it built itself.
	var result: Dictionary = Gfx.prepare_renderer_switch(value)
	if bool(result.get("blocked", false)):
		_overlay.toast(str(result.get("reason", "")), "triangle-alert", Kit.WARNING)
		return
	var args: PackedStringArray = result.get("args", PackedStringArray())
	if not bool(result.get("restart_required", false)):
		_overlay.toast("%s is already running" % Gfx.renderer_label(value), "info", Kit.TEXT_MUTED)
		return
	if args.is_empty() or DisplayServer.get_name() == "headless":
		_overlay.toast("The renderer request was stored and will apply on the next launch", "restart", Kit.WARNING)
		return
	if doc != null and doc.is_dirty():
		_save_project(false, true)
	OS.set_restart_on_exit(true, args)
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
	_update_instrumentation(sample)


func _on_timeline_notice(text_value: String) -> void:
	if _overlay != null:
		_overlay.toast(text_value, "diamond", Kit.ACCENT)


## The pane header tabs and the context pair are the same segmented state.
## `Timeline.set_mode` is idempotent, so this cannot recurse.
func _on_timeline_mode_changed(mode: String) -> void:
	if _context_bar == null:
		return
	_context_bar.set_action_active("dope", mode == "dope")
	_context_bar.set_action_active("graph", mode == "graph")

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
	if _look_through:
		_exit_look_through()
		return true
	if _render_mode:
		_exit_render_mode()
		return true
	if _overlay != null and _overlay.has_modal():
		_overlay.close_modal()
		return true
	if _workspace_panel != null and _workspace_panel.mode() == WorkspacePanelScript.Mode.OVERLAY:
		_close_workspace_panel()
		return true
	if _workspace_menu_open and _workspace_menu != null:
		_workspace_menu.close()
		_workspace_menu_open = false
		return true
	if _workspace != "scene":
		set_workspace("scene")
		return true
	request_close()
	return true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		if doc != null and doc.is_dirty():
			_save_project(false, true)

# -------------------------------------------------------------------------
# Animate stage preview
# -------------------------------------------------------------------------

## The body the Animate split divides: everything below the two fixed bars.
## Bar sizes are real after layout; their minimums are the honest fallback on
## the first build.
func _shell_body_height() -> float:
	var top := 0.0
	if _workspace_bar != null:
		top = _workspace_bar.size.y if _workspace_bar.size.y > 0.0 \
			else _workspace_bar.custom_minimum_size.y
	var context := 0.0
	if _context_bar != null:
		context = _context_bar.size.y if _context_bar.size.y > 0.0 \
			else _context_bar.custom_minimum_size.y
	var instrumentation := 0.0
	if _instrumentation != null and _instrumentation.visible:
		instrumentation = _instrumentation.size.y if _instrumentation.size.y > 0.0 \
			else _instrumentation.custom_minimum_size.y
	return maxf(0.0, size.y - top - context - instrumentation)


func _animate_preview_height() -> float:
	return clampf(_shell_body_height() * 0.22, 96.0, 200.0)


## The tightest case is Graph: the preview must still leave the 120 dp plot
## floor after the transport, one header and the dope/graph ruler, plus the
## preset rail (44). A merged header keeps the same total fixed height.
func _stage_preview_fits() -> bool:
	var pane_height := _shell_body_height() - _animate_preview_height()
	return pane_height - 132.0 - 44.0 >= 120.0


func _stage_toggle_action() -> Dictionary:
	var action := _act("stage_toggle", "Stage", "panel-top", 65, false, true, 44.0)
	if not _stage_preview_fits():
		action["disabled_reason"] = "Not enough height for stage preview"
	return action


## An explicit choice always wins across sizes; the automatic rule only
## describes a session that never touched the toggle, and never writes Prefs.
func _restore_animate_preview() -> void:
	if Prefs.has_explicit("editor.animate_stage"):
		_animate_preview_visible = bool(Prefs.get_value("editor.animate_stage", true))
	else:
		_animate_preview_visible = size.y >= 480.0


func _toggle_animate_preview() -> void:
	_animate_preview_visible = not _animate_preview_visible
	Prefs.set_value("editor.animate_stage", _animate_preview_visible)
	_apply_shell()


func _on_graph_tab_changed(tab: String) -> void:
	Prefs.set_value("editor.graph_tab", tab)


# -------------------------------------------------------------------------
# Responsive shell
# -------------------------------------------------------------------------

func _on_resized() -> void:
	_apply_shell()


## Arranges the shell for the current workbench mode. Idempotent: it is safe to
## call on every resize, mode change and preference change.
func _apply_shell() -> void:
	if _workspace_panel == null or not is_inside_tree():
		return
	# Render mode owns the whole frame. A resize or preference change must not
	# re-show the workbench chrome over the live image; exiting render mode
	# reapplies the shell in one pass.
	if _render_mode:
		return
	_restore_animate_preview()
	_short = size.y < SHORT_MAX_HEIGHT
	# The Animate body is exactly the two fixed bars plus the split; the
	# spec's dp arithmetic counts the pane, not the 1 dp separators.
	var animate := _workspace == "animate"
	_layout.add_theme_constant_override("separation",
		0 if animate else int(Kit.GUTTER))
	_center.add_theme_constant_override("separation",
		0 if animate else int(Kit.GUTTER))
	var preview_height := _animate_preview_height()
	var preview_on := animate and _animate_preview_visible and _stage_preview_fits()
	_stage_host.visible = not animate or preview_on
	if preview_on:
		_stage_host.custom_minimum_size.y = preview_height
		_stage_host.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	else:
		_stage_host.custom_minimum_size.y = 96.0 if _short else 120.0
		_stage_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_animate_pane.set_stage_preview(preview_on, preview_height)
	_timeline.set_short_layout(_short)
	_workspace_bar.set_layout_mode(layout_mode())
	_workspace_bar.set_available_width(size.x)
	_context_bar.set_layout_mode(layout_mode())
	_context_bar.set_available_width(size.x)
	_transport_bar.set_layout_mode(layout_mode())
	_instrumentation.visible = _instrumentation_visible and layout_mode() == "desktop"
	if _overlay != null:
		_overlay.set_layout_mode(layout_mode())
	_timeline.set_chrome_mode(layout_mode())
	_workspace_panel.set_top_bar_height(_workspace_bar.custom_minimum_size.y)
	_workspace_bar.set_workspace(_workspace)

	# Camera look-through is the clean document view: the top bar keeps only
	# Back, the camera chip and Exit, while every editing row and the workspace
	# panel yield their height to the stage. The branch survives every resize
	# and preference change because it is derived from the live flags.
	if _look_through:
		_workspace_bar.set_camera_mode(_camera_name(_look_camera_id))
		_context_bar.visible = false
		_transport_bar.visible = false
		_workspace_panel.set_mode(WorkspacePanelScript.Mode.HIDDEN)
		_panel_spacer.custom_minimum_size.x = 0.0
		_animate_pane.visible = false
		_stage_host.visible = true
		_stage_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_timeline.set_available_width(size.x)
		_refresh_chrome_values()
		return

	_workspace_bar.set_camera_mode("")
	_context_bar.visible = true
	_transport_bar.visible = _workspace != "animate"
	_animate_pane.visible = _workspace == "animate"
	_update_workspace_panel()
	_sync_context_actions()
	_sync_transport_state()
	var reserved: float = _panel_spacer.custom_minimum_size.x
	_timeline.set_available_width(maxf(size.x - reserved, 320.0))
	_refresh_chrome_values()


## One panel host for the scene overlays and the three workspace panels.
## Scene overlays are always floating; Shading, Rig and Render reserve layout
## width at 768 dp and above and become overlays below it.
func _update_workspace_panel() -> void:
	var mode := WorkspacePanelScript.Mode.HIDDEN
	var width := 0.0
	var spacer := 0.0
	match _workspace:
		"scene":
			if _workspace_panel_open:
				mode = WorkspacePanelScript.Mode.OVERLAY
				width = maxf(0.0, minf(size.x - PANEL_OVERLAY_MARGIN, PANEL_OVERLAY_MAX))
		"shading":
			_workspace_panel.set_content(_shading_panel)
			_workspace_panel.set_title("Shading")
			_workspace_panel.set_badge(_shading_badge_text())
		"rig":
			_workspace_panel.set_content(_rig_panel)
			_workspace_panel.set_title("Rig")
		"render":
			_workspace_panel.set_content(_render_panel)
			_workspace_panel.set_title("Render")
			_workspace_panel.set_badge(_render_panel.current_output())
		_:
			_workspace_panel_open = false
	if _workspace in ["shading", "rig", "render"] and _workspace_panel_open:
		if size.x >= PANEL_RESERVE_MIN_WIDTH:
			mode = WorkspacePanelScript.Mode.RESERVED
			width = clampf(size.x * 0.34, PANEL_RESERVED_MIN, PANEL_RESERVED_MAX)
			spacer = width
		else:
			mode = WorkspacePanelScript.Mode.OVERLAY
			width = maxf(0.0, minf(size.x - PANEL_OVERLAY_MARGIN, PANEL_OVERLAY_MAX))
	_workspace_panel.set_panel_width(width)
	_workspace_panel.set_mode(mode)
	_panel_spacer.custom_minimum_size.x = spacer
	_update_rig_badge()


## Scene tree and Inspector share the one overlay slot. Opening either closes
## the other; tapping the action that is already showing closes the panel.
func _toggle_scene_panel(kind := "scene") -> void:
	if _workspace != "scene" or _workspace_panel == null:
		return
	var target: Control = _outliner_panel if kind == "scene" else _inspector_panel
	var title := "Scene tree" if kind == "scene" else "Inspector"
	if _workspace_panel_open and _workspace_panel.mode() == WorkspacePanelScript.Mode.OVERLAY 			and _workspace_panel.content() == target:
		_close_workspace_panel()
		return
	_workspace_panel_open = true
	_workspace_panel.set_content(target)
	_workspace_panel.set_title(title)
	_workspace_panel.set_badge("")
	_apply_shell()


## The context-row panel action: a reserved panel is permanent, so the action
## reports why instead of pretending it can toggle. Narrow overlays toggle.
func _toggle_workspace_panel() -> void:
	if _workspace not in ["shading", "rig", "render"]:
		return
	if _workspace_panel != null and _workspace_panel.mode() == WorkspacePanelScript.Mode.RESERVED:
		return
	_workspace_panel_open = not _workspace_panel_open
	_apply_shell()


func _close_workspace_panel() -> void:
	_workspace_panel_open = false
	if _workspace_panel != null:
		_workspace_panel.set_mode(WorkspacePanelScript.Mode.HIDDEN)
	if _panel_spacer != null:
		_panel_spacer.custom_minimum_size.x = 0.0
	_apply_shell()


func _on_workspace_panel_closed() -> void:
	_workspace_panel_open = false
	_apply_shell()


func _refresh_chrome_values() -> void:
	if doc != null:
		_update_header()
	_update_history_buttons()
	_update_instrumentation()


## The desktop-only instrumentation strip. It shares the Performance sample but
## has its own session flag; nothing is written to preferences.
func _update_instrumentation(sample: Dictionary = {}) -> void:
	if _instrumentation == null or _instrumentation_label == null:
		return
	if not _instrumentation.visible:
		return
	if sample.is_empty():
		sample = Perf.sample()
	var fps := int(round(float(sample.get("fps", 0.0))))
	var frame_ms := float(sample.get("frame_ms", 0.0))
	_instrumentation_label.text = "%d FPS  ·  %.1f ms  ·  %s" % [
		fps, frame_ms, Gfx.renderer_name(),
	]


func _toggle_instrumentation() -> void:
	_instrumentation_visible = not _instrumentation_visible
	_apply_shell()
	if _instrumentation_visible:
		_update_instrumentation()


## The stage host's height drives any stage-relative layout. During the first
## shell pass the container has not been laid out yet, so keep a real floor.
func _stage_height() -> float:
	if _stage_host == null:
		return 120.0
	return maxf(_stage_host.stage_rect().size.y, 120.0)


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
	if is_inside_tree() and _workspace_panel != null:
		_apply_shell()


## Puts the clip clock back where the sequence took over. Runs on the actual
## sequence stop (lane pause, Space, natural end or stop_sequence), never while
## it still runs.
func _restore_clip_after_sequence() -> void:
	if doc == null or not _sequence_was_playing or doc.is_sequence_playing() or _restoring_clip:
		return
	_sequence_was_playing = false
	_restoring_clip = true
	# Not silent: the dope sheet and clip lane must show the restored playhead.
	doc.seek(_clip_time_before_sequence)
	_clip_time_before_sequence = float(doc.current_time)
	_restoring_clip = false

func _on_chrome_action(action: String) -> void:
	match action:
		"back":
			handle_back()
		"undo":
			_undo()
		"redo":
			_redo()
		"save":
			_save_project(true)
		"menu":
			_open_project_menu(_workspace_bar.action_button("menu"))


## A shrink that would delete keys asks first. The timeline has already left
## the document untouched; confirming applies the exact requested length.
func _on_timeline_duration_confirmation(value: float, message: String) -> void:
	var target := clampf(value, 0.25, 3600.0)
	_overlay.confirm("Shorten the clip?", message, "Shorten", func() -> void:
		if _timeline != null:
			_timeline.apply_duration(target)
	)


# -------------------------------------------------------------------------
# Tools, editing and shortcuts
# -------------------------------------------------------------------------

func _select_tool(tool_id: String) -> void:
	_tool = tool_id
	if _view != null:
		_view.set_tool(_tool)
	if _context_bar != null:
		_sync_context_state()

func _focus_selection() -> void:
	if _view != null:
		_view.focus_selection()

func _on_view_grid_changed(enabled: bool) -> void:
	if _context_bar != null:
		_sync_context_state()

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
				if doc.is_sequence_playing():
					doc.pause_sequence()
				else:
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
			if _workspace_panel != null and \
					_workspace_panel.mode() == WorkspacePanelScript.Mode.OVERLAY:
				_close_workspace_panel()
				get_viewport().set_input_as_handled()
			elif _workspace != "scene":
				set_workspace("scene")
				get_viewport().set_input_as_handled()

# -------------------------------------------------------------------------
# Add object sheet
# -------------------------------------------------------------------------

func _open_add_sheet() -> void:
	if doc == null:
		return
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)

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
	scene_grid.add_child(_sheet_button("Omni light", "circle-dot", _add_omni_light))
	scene_grid.add_child(_sheet_button("Rig", "bone", _add_rig))

	body.add_child(Kit.vsep())
	body.add_child(Kit.section_label("Assets"))
	var asset_grid := GridContainer.new()
	asset_grid.columns = 2
	asset_grid.add_theme_constant_override("h_separation", 5)
	asset_grid.add_theme_constant_override("v_separation", 5)
	body.add_child(asset_grid)
	asset_grid.add_child(_sheet_button("Import 3D model", "upload", _pick_model))
	asset_grid.add_child(_sheet_button("Audio", "audio-wave", _add_audio_entry))
	asset_grid.add_child(_sheet_button("Video reference", "video", _add_video_reference_entry))

	_overlay.show_modal("Add object", "Scene elements are independent and can be keyed immediately. Primitives are placed on the ground at the center of the current view.", body, [
		{"text": "Close", "compact": true},
	])

func _sheet_button(text_value: String, icon_name: String, action: Callable) -> Button:
	var button := Kit.text_button(text_value, icon_name, false, true)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(44, Kit.FIELD)
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
	_overlay.toast("Omni light added", "circle-dot", Kit.SUCCESS)

func _add_rig() -> void:
	if doc == null:
		return
	doc.rig_system.create_rig("Rig", _spawn_point())
	_overlay.toast("Rig added", "check", Kit.SUCCESS)
	_focus_selection()

func _add_audio_entry() -> void:
	_open_media_import_sheet()

func _add_video_reference_entry() -> void:
	_open_media_import_sheet()

func _open_media_import_sheet() -> void:
	if doc == null:
		return
	var sheet := MediaImportSheetScript.new()
	sheet.setup(doc)
	sheet.audio_import_requested.connect(_on_media_import_audio)
	sheet.video_import_requested.connect(_on_media_import_video)
	_overlay.show_sheet("Add media", "Audio and video references are copied into the project folder.", sheet, [
		{"text": "Close", "compact": true},
	])

func _on_media_import_audio(uri: String) -> void:
	if doc == null:
		return
	var media = doc.media_system
	var result: Dictionary = media.import_audio(uri)
	if not bool(result.get("ok", false)):
		_overlay.toast(str(result.get("error", "The audio could not be imported")), "triangle-alert", Kit.DANGER)
		return
	var track_id: String = media.add_audio_track(str(result.get("rel_path", "")), 0.0)
	if track_id == "":
		_overlay.toast("The audio track could not be added", "triangle-alert", Kit.DANGER)
		return
	_overlay.toast("Audio track added", "check", Kit.SUCCESS)

func _on_media_import_video(uri: String, options: Dictionary) -> void:
	if doc == null:
		return
	var proxy: Dictionary = {
		"fps": int(Prefs.get_value("media.proxy_fps", 12)),
		"max_width": int(Prefs.get_value("media.proxy_max_width", 1280)),
	}
	for key in options:
		proxy[key] = options[key]
	# Sheet options already carry the proxy the user confirmed; the Prefs
	# values above only seed the defaults for a plain import.
	var result: Dictionary = doc.media_system.import_video_reference(uri, proxy)
	if not bool(result.get("ok", false)):
		_overlay.toast(str(result.get("error", "The video reference could not be imported")), "triangle-alert", Kit.DANGER)
		return
	var note := str(result.get("note", ""))
	if note != "":
		_overlay.toast(note, "info", Kit.TIME)
	else:
		_overlay.toast("Video reference added", "check", Kit.SUCCESS)

# -------------------------------------------------------------------------
# Import and still rendering
# -------------------------------------------------------------------------

func _pick_model() -> void:
	if doc == null:
		return
	if doc.project_dir == "":
		_save_project(false)
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var filters: PackedStringArray = model_picker_filters()
		var err := DisplayServer.file_dialog_show(
			"Import 3D model", "", "", false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters, _on_model_selected
		)
		if err != OK:
			_overlay.toast("The file picker could not be opened", "triangle-alert", Kit.DANGER)
	else:
		_overlay.toast("This platform has no native file picker", "triangle-alert", Kit.DANGER)


static func model_picker_filters() -> PackedStringArray:
	return PackedStringArray([
		"*.glb, *.gltf, *.obj, *.fbx;3D models;model/gltf-binary,model/gltf+json,application/octet-stream",
	])


static func fbx_conversion_copy() -> Dictionary:
	return {
		"title": "FBX needs a conversion",
		"body": "Godot's FBX importer only exists in the editor, so it cannot run on Android. Convert the model to glTF 2.0 first.",
		"steps": [
			"Open the model in Blender.",
			"File → Export → glTF 2.0.",
			"Choose glTF Binary (.glb).",
			"Import the .glb in Kinema.",
		],
		"actions": [
			{"text": "Choose another file", "primary": true},
			{"text": "Cancel", "primary": false},
		],
	}


static func rig_adopted_toast(bone_count: int) -> String:
	return "Skeleton detected · %d bones · Pose mode is ready." % bone_count


func _show_fbx_conversion_sheet() -> void:
	var copy: Dictionary = fbx_conversion_copy()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var paragraph := Kit.label(str(copy.get("body", "")), Kit.TYPE_BODY, Kit.TEXT)
	paragraph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(paragraph)
	var steps := VBoxContainer.new()
	steps.add_theme_constant_override("separation", 6)
	var index := 1
	for step in copy.get("steps", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var number := Kit.mono_label("%d" % index, Kit.TYPE_CAPTION, Kit.TEXT_MUTED)
		number.custom_minimum_size.x = 18
		row.add_child(number)
		var text := Kit.label(str(step), Kit.TYPE_BODY, Kit.TEXT)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		steps.add_child(row)
		index += 1
	body.add_child(steps)
	var actions: Array = []
	for raw in copy.get("actions", []):
		if not raw is Dictionary:
			continue
		var action: Dictionary = (raw as Dictionary).duplicate(true)
		if bool(action.get("primary", false)):
			action["callback"] = _pick_model
		actions.append(action)
	_overlay.show_sheet(str(copy.get("title", "")), "", body, actions)


func _on_rig_adopted(_object_id: String, bone_count: int) -> void:
	if _overlay == null:
		return
	_overlay.toast(rig_adopted_toast(bone_count), "user-round", Kit.SUCCESS)


func _on_model_selected(status: bool, paths: PackedStringArray, _filter_index: int) -> void:
	if not status or paths.is_empty() or doc == null:
		return
	var uri := paths[0]
	if uri.get_extension().to_lower() == "fbx":
		_show_fbx_conversion_sheet()
		return
	var result: Dictionary = Store.import_model(uri, doc.project_dir, "Model")
	if not bool(result.get("ok", false)):
		_overlay.toast(str(result.get("error", "The model could not be imported")), "triangle-alert", Kit.DANGER)
		return
	var at := _spawn_point()
	at.y = 0.0
	var imported_id: String = doc.add_imported(
		str(result.get("rel_path", "")), str(result.get("name", "Model")), at)
	_save_project(false)
	var warning := str(result.get("warning", ""))
	if warning != "":
		_overlay.toast(warning, "triangle-alert", Kit.WARNING)
	else:
		# Name the hierarchy the import just made discoverable: OBJ stays one
		# mesh row, while glTF/GLB reports the real part count.
		var parts: Array = doc.import_parts(imported_id)
		var detail := "single mesh" if parts.is_empty() else "%d hierarchy nodes" % parts.size()
		_overlay.toast("Imported " + str(result.get("name", "model")) + " · " + detail,
			"package-open", Kit.SUCCESS)
	_focus_selection()

func _open_import_sheet() -> void:
	# The import options live in the file picker flow until the dedicated
	# import panel lands. Keeping one entry point means Settings never calls a
	# missing method.
	_pick_model()


## Every capture entry point shares this guard. A still or sequence must not
## start while another render or a media export owns the probe renderer:
## overlapping captures would interleave their chrome suppression and their
## progress state.
func _capture_blocked() -> bool:
	return _render_busy or _media_busy

func _quick_still() -> void:
	if doc == null or _view == null or _capture_blocked():
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

# -------------------------------------------------------------------------
# Render workspace: GLB scene export
# -------------------------------------------------------------------------

func _start_render_output() -> void:
	if doc == null or _media_export == null:
		return
	_media_export.start_export()


func _start_render_still() -> void:
	if doc == null or _media_export == null:
		return
	_media_export.set_format("png")
	_media_export.start_export()


func _export_glb(options: Dictionary) -> void:
	if doc == null or _render_panel == null:
		return
	var desktop := OS.get_name() in ["Windows", "macOS", "Linux", "FreeBSD"] \
		and DisplayServer.get_name() != "headless"
	if desktop and DisplayServer.has_method("file_dialog_show"):
		_pending_glb_options = options.duplicate(true)
		var suggested := "Kinema_%s.glb" % _glb_project_slug()
		DisplayServer.file_dialog_show(
			"Export GLB", "", suggested, false,
			DisplayServer.FILE_DIALOG_MODE_SAVE_FILE,
			PackedStringArray(["*.glb"]), _on_glb_path_selected)
		return
	_export_glb_to(_default_glb_path(), options)


func _on_glb_path_selected(status: bool, paths: PackedStringArray, _filter_index: int) -> void:
	if not status or paths.is_empty():
		return
	var path := str(paths[0])
	if path.get_extension().to_lower() != "glb":
		path += ".glb"
	_export_glb_to(path, _pending_glb_options)


func _export_glb_to(path: String, options: Dictionary) -> void:
	if doc == null or _render_panel == null:
		return
	var resolved := ProjectSettings.globalize_path(path)
	var dir := resolved.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	_render_panel.set_export_status("Exporting…")
	var exporter = GlbExportScript.new()
	var result: Dictionary = exporter.export_scene(doc, resolved, options)
	if bool(result.get("ok", false)):
		_render_panel.set_export_result(result)
		if _overlay != null:
			_overlay.toast("GLB exported", "check", Kit.SUCCESS)
	else:
		var reason := str(result.get("error", "The GLB export failed."))
		_render_panel.set_export_status(reason)
		if _overlay != null:
			_overlay.toast(reason, "triangle-alert", Kit.DANGER)


func _default_glb_path() -> String:
	var now := Time.get_datetime_dict_from_system()
	var stamp := "%04d%02d%02d_%02d%02d%02d" % [
		int(now.get("year", 0)), int(now.get("month", 1)), int(now.get("day", 1)),
		int(now.get("hour", 0)), int(now.get("minute", 0)), int(now.get("second", 0)),
	]
	return "user://exports/Kinema_%s_%s.glb" % [_glb_project_slug(), stamp]


func _glb_project_slug() -> String:
	var title: String = doc.title if doc != null else ""
	var slug := title.strip_edges().to_snake_case()
	return slug if slug != "" else "project"

# -------------------------------------------------------------------------
# Media export sheet (PNG sequence / GIF / MP4 / camera). The quick still and
# quick PNG sequence actions above keep their own one-tap paths.
# -------------------------------------------------------------------------

func _run_media_export(options: Dictionary) -> void:
	if doc == null or _view == null or _media_export == null or _capture_blocked():
		return
	_media_busy = true
	_media_cancel = false
	match str(options.get("format", "png")):
		"png", "png_sequence":
			await _export_png_sequence(options)
		"gif":
			await _export_gif(options)
		"mp4":
			await _export_mp4(options)
		"camera":
			await _export_camera(options)
		_:
			_export_failed("Unsupported export format: %s" % str(options.get("format", "")))
	_media_busy = false

func _export_failed(message: String) -> void:
	if _media_export != null:
		_media_export.set_progress("error")
		# Errors are a status, not a result row: a result renders as
		# "path · size · duration · tracks", which is meaningless here.
		_media_export.clear_result()
		_media_export.set_status(message)
	_overlay.toast(message, "triangle-alert", Kit.DANGER)

func _export_progress(kind: String) -> Callable:
	return func(done: int, total: int) -> void:
		if _media_export != null:
			_media_export.set_progress(kind, done, total)

func _export_cancelled() -> Callable:
	return func() -> bool:
		return _media_cancel

func _export_png_sequence(options: Dictionary) -> void:
	var renderer := SequenceRendererScript.new()
	renderer.setup(doc, _view)
	var result: Dictionary = await renderer.render(options, _export_progress("frames"), _export_cancelled())
	var frames_dir := str(result.get("frames_dir", ""))
	if not bool(result.get("ok", false)):
		# A capture failure stops mid-render and returns the partial directory.
		if frames_dir != "":
			_clean_dir(frames_dir)
		_export_failed(str(result.get("error", "The PNG sequence could not be rendered.")))
		return
	if _media_cancel:
		if frames_dir != "":
			_clean_dir(frames_dir)
		_export_failed("Export cancelled.")
		return
	var output := str(options.get("output_path", ""))
	if output == "":
		output = RenderExport.sequence_dir() + ".zip"
	elif not output.ends_with(".zip"):
		output = output.get_basename() + ".zip"
	if not RenderExport.zip_directory(frames_dir, output):
		_clean_dir(frames_dir)
		_export_failed("The ZIP archive could not be written.")
		return
	_clean_dir(frames_dir)
	var duration: float = float(options.get("end", doc.sequence_duration())) - float(options.get("start", 0.0))
	if _media_export != null:
		_media_export.set_progress("done")
		_media_export.set_result(output, _file_size(output), duration, "%d PNG frames" % int(result.get("frame_count", 0)))
	_overlay.toast("PNG sequence exported", "check", Kit.SUCCESS)

func _export_gif(options: Dictionary) -> void:
	var fps := maxi(1, int(options.get("fps", 24)))
	if not GifEncoder.can_encode(fps):
		_export_failed(GifEncoder.unsupported_reason(fps))
		return
	var width := int(options.get("width", GifEncoder.widths()[0]))
	var height := GifEncoder.height_for_width(width)
	var renderer := SequenceRendererScript.new()
	renderer.setup(doc, _view)
	var frame_options: Dictionary = {
		"width": width,
		"height": height,
		"fps": fps,
		"start": float(options.get("start", 0.0)),
		"end": float(options.get("end", doc.sequence_duration())),
	}
	var result: Dictionary = await renderer.render(frame_options, _export_progress("frames"), _export_cancelled())
	var frames_dir := str(result.get("frames_dir", ""))
	if not bool(result.get("ok", false)):
		if frames_dir != "":
			_clean_dir(frames_dir)
		_export_failed(str(result.get("error", "The GIF frames could not be rendered.")))
		return
	var frames: Array = []
	var dir := DirAccess.open(frames_dir)
	if dir != null:
		var names: Array = []
		dir.list_dir_begin()
		var file := dir.get_next()
		while file != "":
			if file.ends_with(".png"):
				names.append(file)
			file = dir.get_next()
		dir.list_dir_end()
		names.sort()
		for file_name in names:
			var image := Image.new()
			if image.load(frames_dir.path_join(file_name)) == OK:
				frames.append(image)
	_clean_dir(frames_dir)
	if _media_cancel:
		_export_failed("Export cancelled.")
		return
	if frames.is_empty():
		_export_failed("The GIF could not be encoded because no frames were captured.")
		return
	var bytes := GifEncoder.encode(frames, fps, true)
	if bytes.is_empty():
		_export_failed("The GIF encoder returned no data.")
		return
	var output := str(options.get("output_path", ""))
	if output == "":
		output = "user://export.gif"
	elif not output.ends_with(".gif"):
		output = output.get_basename() + ".gif"
	if not _write_gif_file(output, bytes):
		_export_failed("The GIF file could not be written.")
		return
	var duration: float = float(frame_options["end"]) - float(frame_options["start"])
	if _media_export != null:
		_media_export.set_progress("done")
		_media_export.set_result(output, _file_size(output), duration, "%d GIF frames" % frames.size())
	_overlay.toast("GIF exported", "check", Kit.SUCCESS)

## Pure builders for the MP4 path, so the options the renderer and the Java
## manifest receive can be inspected without running the Android encoder.
## `msaa` uses the Godot viewport index: 2× = 1, 4× = 2. The sheet always
## sends it; the default keeps older callers on the previous 4× behaviour.
static func mp4_frame_options(options: Dictionary, fallback_end: float) -> Dictionary:
	return {
		"width": int(options.get("width", 1280)),
		"height": int(options.get("height", 720)),
		"fps": int(options.get("fps", 24)),
		"start": float(options.get("start", 0.0)),
		"end": float(options.get("end", fallback_end)),
		"msaa": int(options.get("msaa", 2)),
	}


static func mp4_manifest_options(options: Dictionary) -> Dictionary:
	return {
		"width": int(options.get("width", 1920)),
		"height": int(options.get("height", 1080)),
		"fps": int(options.get("fps", 24)),
		"start": float(options.get("start", 0.0)),
		"end": float(options.get("end", 0.0)),
		"bitrate": int(options.get("bitrate", 12000000)),
		"audio_bitrate": int(options.get("audio_bitrate", 192000)),
	}


func _export_mp4(options: Dictionary) -> void:
	var backend = AndroidVideo.new()
	if not bool(backend.available()):
		# Never fake MP4: report the exact backend reason on this platform.
		_export_failed(AndroidVideo.REASON)
		return
	var renderer := SequenceRendererScript.new()
	renderer.setup(doc, _view)
	var frame_options: Dictionary = mp4_frame_options(options, doc.sequence_duration())
	var result: Dictionary = await renderer.render(frame_options, _export_progress("frames"), _export_cancelled())
	var frames_dir := str(result.get("frames_dir", ""))
	if not bool(result.get("ok", false)):
		if frames_dir != "":
			_clean_dir(frames_dir)
		_export_failed(str(result.get("error", "The MP4 frames could not be rendered.")))
		return
	var audio: Array = []
	if bool(options.get("include_audio", true)):
		for track in doc.media_system.audio_tracks():
			if not bool(track.get("muted", false)):
				audio.append(track)
	var manifest_input: Dictionary = mp4_manifest_options(options)
	manifest_input["project_dir"] = doc.project_dir
	manifest_input["frame_count"] = int(result.get("frame_count", 0))
	manifest_input["frame_dir"] = frames_dir
	manifest_input["audio"] = audio
	var manifest: Dictionary = backend.build_manifest(manifest_input)
	var output := str(options.get("output_path", ""))
	if output == "":
		output = "user://export.mp4"
	elif not output.ends_with(".mp4"):
		output = output.get_basename() + ".mp4"
	if not _ensure_output_dir(output):
		_clean_dir(frames_dir)
		_export_failed("The MP4 output folder could not be created.")
		return
	var started: Dictionary = backend.encode(manifest, output)
	if not bool(started.get("ok", false)):
		_clean_dir(frames_dir)
		_export_failed(str(started.get("error", AndroidVideo.REASON)))
		return
	var timeout_seconds := AndroidVideo.encode_timeout_seconds(int(result.get("frame_count", 0)))
	var deadline_msec := Time.get_ticks_msec() + int(ceil(timeout_seconds * 1000.0))
	while true:
		var poll: Dictionary = backend.poll()
		if _media_export != null:
			_media_export.set_progress("encoding", int(round(float(poll.get("progress", 0.0)) * 100.0)), 100)
		if bool(poll.get("done", false)) and str(poll.get("state", "")) == "done":
			break
		if bool(poll.get("done", false)) or str(poll.get("error", "")) != "":
			backend.cancel()
			_clean_dir(frames_dir)
			_export_failed(str(poll.get("error", "The MP4 encode failed.")))
			return
		if _media_cancel:
			backend.cancel()
			_clean_dir(frames_dir)
			_export_failed("Export cancelled.")
			return
		# A wedged native encoder must end the export, not leave the sheet busy.
		if Time.get_ticks_msec() >= deadline_msec:
			backend.cancel()
			_clean_dir(frames_dir)
			_export_failed("The MP4 encoder did not finish within %d s, so the export was cancelled." % int(round(timeout_seconds)))
			return
		await get_tree().create_timer(0.05).timeout
	_clean_dir(frames_dir)
	var verified: Dictionary = backend.verify(output, not audio.is_empty(), int(frame_options["fps"]), float(frame_options["end"]) - float(frame_options["start"]))
	if not bool(verified.get("ok", false)):
		_export_failed(str(verified.get("error", "The MP4 file could not be verified.")))
		return
	var duration: float = float(frame_options["end"]) - float(frame_options["start"])
	if _media_export != null:
		_media_export.set_progress("done")
		_media_export.set_result(output, _file_size(output), duration, "%d audio tracks" % audio.size() if not audio.is_empty() else "no audio")
	_overlay.toast("MP4 exported", "check", Kit.SUCCESS)

func _export_camera(options: Dictionary) -> void:
	var exporter := CameraExportScript.new()
	exporter.setup(doc)
	var fps := maxi(1, int(options.get("fps", 24)))
	var duration: float = float(options.get("end", doc.sequence_duration())) - float(options.get("start", 0.0))
	var output := str(options.get("output_path", ""))
	if output == "":
		output = "user://camera_track.json"
	elif not output.ends_with(".json"):
		output = output.get_basename() + ".json"
	var result: Dictionary = await exporter.export(
		output,
		str(options.get("camera_id", "")),
		fps,
		duration)
	if not bool(result.get("ok", false)):
		_export_failed(str(result.get("error", "The camera export failed.")))
		return
	if _media_export != null:
		_media_export.set_progress("done")
		_media_export.set_result(output, _file_size(output), duration, "camera track")
	_overlay.toast("Camera track exported", "check", Kit.SUCCESS)

func _write_gif_file(path: String, bytes: PackedByteArray) -> bool:
	if not _ensure_output_dir(path):
		return false
	var writer := FileAccess.open(path, FileAccess.WRITE)
	if writer == null:
		return false
	writer.store_buffer(bytes)
	writer.close()
	return true


## `FileAccess.open(..., WRITE)` never creates parent directories. Default
## exports point below `user://exports`, so every writer creates its parent
## first instead of failing the first time.
func _ensure_output_dir(path: String) -> bool:
	var directory := path.get_base_dir()
	if directory == "" or directory == ".":
		return true
	return DirAccess.make_dir_recursive_absolute(directory) == OK


func _clean_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		# The timeout and failure paths depend on this cleanup, so a silent
		# no-op would leave a frames directory behind with no diagnostic.
		push_warning("Kinema: could not open %s to clean it; frames may remain." % path)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := int(file.get_length())
	file.close()
	return size

## Camera view is a viewing mode, not a document change. The view copies the
## document camera; the editor owns the session flag, the chip and the chrome.
## Entering another camera while active is a switch, never an exit/re-entry.
func _enter_camera_view(camera_id: String) -> void:
	if _view == null or _render_mode:
		return
	var was_looking := _look_through
	var entered := false
	if was_looking:
		entered = _view.switch_look_through_camera(camera_id)
	else:
		entered = _view.enter_look_through(camera_id)
	if not entered:
		return
	_look_through = true
	_look_camera_id = camera_id
	if not was_looking:
		_look_perf_was_visible = _perf_overlay != null and _perf_overlay.visible
		if _perf_overlay != null:
			_perf_overlay.visible = false
		# The rotoscope and rig handles are workbench layers, not part of the
		# document camera's view. _sync_rig_overlay() gates on _look_through.
		if _video_overlay != null:
			_video_overlay.set_render_mode(true)
		if _rig_overlay != null:
			_rig_overlay.set_enabled(false)
		_sync_rig_overlay()
	_workspace_bar.set_camera_mode(_camera_name(camera_id))
	_apply_shell()


## Compatibility spelling for the pre-camera-view shell paths.
func _enter_look_through(camera_id: String) -> void:
	_enter_camera_view(camera_id)


## The view can leave look-through by itself (the Exit control lives inside
## it), so the editor restores its own chrome from this one handler. Calling
## `_exit_look_through()` therefore just asks the view to exit, and the restore
## happens exactly once from here.
func _on_view_look_through_exited() -> void:
	_look_through = false
	_look_camera_id = ""
	_workspace_bar.set_camera_mode("")
	if _perf_overlay != null:
		_perf_overlay.visible = _look_perf_was_visible
	if _video_overlay != null:
		_video_overlay.set_render_mode(false)
	_sync_rig_overlay()
	_apply_shell()


func _exit_look_through() -> void:
	if _view != null and _view.is_look_through():
		_view.exit_look_through()
		return
	if _look_through:
		_on_view_look_through_exited()


## The live document name for a camera id, or "" when the object is gone.
func _camera_name(camera_id: String) -> String:
	if doc == null or camera_id == "":
		return ""
	var obj := doc.get_object(camera_id)
	if obj.is_empty():
		return ""
	return str(obj.get("name", camera_id))


## A camera is a valid view target only while its object and live node both
## exist as a visible camera.
func _camera_target_valid(camera_id: String) -> bool:
	if doc == null or camera_id == "":
		return false
	var obj := doc.get_object(camera_id)
	if obj.is_empty() or str(obj.get("kind", "")) != "camera":
		return false
	var node: Node3D = doc.nodes.get(camera_id)
	return node != null and node.visible

func is_look_through() -> bool:
	return _look_through

## Quick render is the review loop: the editor becomes a live, full-quality
## playback surface instead of showing a static capture of the current frame.
## Nothing is captured here; the renderer keeps drawing the document in real
## time. Saving a still or a sequence stays in the Render workspace.
func _enter_render_mode() -> void:
	if _render_mode or doc == null or _view == null or _render_busy:
		return
	if _look_through:
		_exit_look_through()
	if _overlay != null and _overlay.has_modal():
		_overlay.close_modal()
	# Render preview runs the clip clock. Stop a sequence first so its stop
	# handler restores the clip playhead before we save it.
	if doc.is_sequence_playing():
		doc.pause_sequence()
	_render_mode = true
	_render_saved_time = doc.current_time
	_render_was_playing = doc.is_playing
	_capture_render_chrome()
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
		# The restore is silent, so the sequence snapshot must be told about it
		# here; otherwise a later sequence stop rewinds to a stale clip time.
		_clip_time_before_sequence = float(doc.current_time)
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
	_sync_transport_state()
	if _render_mode:
		_sync_render_hud()
	_sync_sequence_transport()
	if doc == null or _restoring_clip:
		return
	if doc.is_sequence_playing():
		_sequence_was_playing = true
		return
	if _sequence_was_playing and not _playing:
		# Every stop path (lane pause, Space, natural end, stop_sequence) goes
		# through here, so the clip clock always returns to its saved playhead.
		# Do not snapshot the sequence's local time over the saved clip time.
		_restore_clip_after_sequence()
		return
	# Every other non-sequence event is clip time, including while the clip
	# plays. `play_sequence()` overwrites `current_time` without a preceding
	# clip emit, so this snapshot must already be current when the lane takes
	# over.
	_clip_time_before_sequence = float(doc.current_time)
	if _sequence_was_playing:
		# A clip play superseded the sequence without a stop emit; drop the
		# stale flag so the next clip pause does not rewind the new run.
		_sequence_was_playing = false

func _sync_sequence_transport() -> void:
	if doc == null:
		return
	if _timeline != null:
		# The timeline owns its disabled flag and reason; the shell only says
		# whether the clip clock may run.
		_timeline.set_clip_transport_enabled(not doc.is_sequence_playing())


func _capture_render_chrome() -> void:
	_render_ui_state = {
		"top": _workspace_bar != null and _workspace_bar.visible,
		"context": _context_bar != null and _context_bar.visible,
		"transport": _transport_bar != null and _transport_bar.visible,
		"instrumentation": _instrumentation != null and _instrumentation.visible,
		"panel_open": _workspace_panel_open,
		"perf": _perf_overlay != null and _perf_overlay.visible,
	}


func _set_render_chrome_hidden() -> void:
	if _workspace_bar != null:
		_workspace_bar.visible = false
	if _context_bar != null:
		_context_bar.visible = false
	if _transport_bar != null:
		_transport_bar.visible = false
	if _instrumentation != null:
		_instrumentation.visible = false
	if _animate_pane != null:
		_animate_pane.visible = false
	if _workspace_panel != null:
		_workspace_panel.set_mode(WorkspacePanelScript.Mode.HIDDEN)
	if _panel_spacer != null:
		_panel_spacer.custom_minimum_size.x = 0.0
	# Neither overlay may draw over the review image: the rig handles and the
	# rotoscope layer belong to the workbench, not to the render.
	if _video_overlay != null:
		_video_overlay.set_render_mode(true)
	if _rig_overlay != null:
		_rig_overlay.set_enabled(false)


func _restore_render_chrome() -> void:
	if _workspace_bar != null:
		_workspace_bar.visible = bool(_render_ui_state.get("top", true))
	if _context_bar != null:
		_context_bar.visible = bool(_render_ui_state.get("context", true))
	if _transport_bar != null:
		_transport_bar.visible = bool(_render_ui_state.get("transport", true))
	if _instrumentation != null:
		_instrumentation.visible = bool(_render_ui_state.get("instrumentation", false))
	if _perf_overlay != null:
		_perf_overlay.visible = bool(_render_ui_state.get("perf", false))
	_workspace_panel_open = bool(_render_ui_state.get("panel_open", false))
	if _video_overlay != null:
		_video_overlay.set_render_mode(false)
	_render_ui_state.clear()
	_sync_rig_overlay()


func _render_still() -> void:
	if doc == null or _view == null or _capture_blocked():
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
	if doc == null or _view == null or _capture_blocked():
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

func _open_project_menu(anchor: Control) -> void:
	if doc == null:
		return
	if _project_menu == null:
		return
	if _workspace_menu != null:
		_workspace_menu.close()
	_workspace_menu_open = false
	_project_menu.set_layout_mode(layout_mode())
	_project_menu.set_max_width(320.0)
	_project_menu.open_menu(anchor, "Project", doc.title, layout_mode() != "desktop")
	# Below 600 dp the top bar keeps only Back, the tabs, More, Save and this
	# menu. History moves here rather than disappearing; at 600 dp and above
	# the bar owns the same two actions and the menu does not duplicate them.
	if size.x < 600.0:
		_project_menu.add_action("undo", "Undo", "undo-2",
			doc.can_undo(), "Nothing to undo.")
		_project_menu.add_action("redo", "Redo", "redo-2",
			doc.can_redo(), "Nothing to redo.")
		_project_menu.add_separator()
	_project_menu.add_action("settings", "Project settings", "sliders-horizontal")
	_project_menu.add_action("import", "Import 3D model", "upload")
	_project_menu.add_action("graphics", "Graphics and performance", "gauge")
	_project_menu.add_action("interface", "Interface and scale", "monitor")
	_project_menu.add_action("performance", "Performance overlay", "timer")
	var instrumentation: Button = _project_menu.add_action(
		"instrumentation", "Instrumentation strip", "rows-3")
	instrumentation.visible = layout_mode() == "desktop"
	_project_menu.add_separator()
	_project_menu.add_action("shortcuts", "Gesture guide and shortcuts", "keyboard")
	_project_menu.add_action("about", "About Kinema", "info")
	_project_menu.add_separator()
	_project_menu.add_action("close", "Close project", "x")


func _on_project_menu_row(id: String) -> void:
	match id:
		"undo":
			_undo()
		"redo":
			_redo()
		"settings":
			_open_settings()
		"import":
			_pick_model()
		"graphics":
			_open_settings("graphics")
		"interface":
			_open_interface_sheet()
		"performance":
			_open_performance_overlay()
		"instrumentation":
			_toggle_instrumentation()
		"shortcuts":
			_open_shortcuts_sheet()
		"about":
			_show_about()
		"close":
			request_close()


## The interface sheet: arrangement, orientation and interface scale.
func _open_interface_sheet() -> void:
	if doc == null:
		return
	var sheet = InterfaceSheetScript.new()
	sheet.setup(self)
	sheet.layout_selected.connect(func(mode: String) -> void:
		set_layout_mode(mode)
		sheet.call_deferred("close")
	)
	sheet.orientation_selected.connect(_on_settings_orientation)
	sheet.ui_scale_changed.connect(func(value: float) -> void:
		Prefs.set_value("display.user_scale", value)
	)
	_interface_sheet = sheet
	sheet.open(
		str(Prefs.get_value("display.layout", "auto")),
		_fit_percent,
		_fit_clamped
	)
	# A landscape phone has width to spare, so the sheet opens wide enough for
	# two columns and the scale slider stays above the fold. Portrait keeps the
	# single 560 dp column.
	var sheet_width := 560.0
	if size.y < 560.0 and size.x >= 780.0:
		sheet_width = clampf(size.x - 120.0, 620.0, 760.0)
	_overlay.show_sheet(
		"Interface",
		"Choose an arrangement. Desktop shrinks to fit instead of falling back.",
		sheet,
		[{"text": "Done", "primary": true}],
		{"width": sheet_width}
	)


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
	panel.risk_change_requested.connect(_on_settings_risk_change)
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
	if bool(result.get("blocked", false)):
		if _overlay != null:
			_overlay.toast(str(result.get("reason", "")), "triangle-alert", Kit.WARNING)
		if _settings_panel != null and is_instance_valid(_settings_panel):
			_settings_panel.call("sync_preset_buttons")
		return
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


func _on_settings_risk_change(enabled: bool) -> void:
	if not Gfx.risk_supported():
		return
	if not enabled:
		Gfx.disable_risk()
		if _overlay != null:
			_overlay.toast(RISK_RESTORED_TOAST, "check", Kit.SUCCESS)
		_open_graphics_settings()
		return
	if _overlay == null:
		return
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	var message := Kit.label(RISK_CONFIRM_BODY, Kit.TYPE_BODY, Kit.TEXT_MUTED)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(message)
	var actions: Array = RISK_CONFIRM_ACTIONS.duplicate(true)
	actions[0]["callback"] = func() -> void: _open_graphics_settings()
	actions[1]["callback"] = _confirm_risk_enable
	_overlay.show_modal(RISK_CONFIRM_TITLE, "", body, actions)


func _confirm_risk_enable() -> void:
	if not Gfx.risk_supported():
		return
	# The probe is persisted inside enable_risk() before the profile applies.
	Gfx.enable_risk()
	await RenderingServer.frame_post_draw
	Gfx.confirm_risk_probe()
	if _overlay != null:
		_overlay.toast(RISK_ENABLED_TOAST, "check", Kit.SUCCESS)
	_open_graphics_settings()


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
		"rig.show_overlay":
			_sync_rig_overlay()
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
		_view.set_gizmo_scale(float(Prefs.get_value("editor.gizmo_size", 1.25)))
	if _view.has_method("set_snap_values"):
		_view.set_snap_values(
			float(Prefs.get_value("editor.translate_snap", 0.25)),
			float(Prefs.get_value("editor.rotate_snap", 15.0)),
			float(Prefs.get_value("editor.scale_snap", 0.25))
		)


func _autosave_seconds() -> float:
	return clampf(float(Prefs.get_value("editor.autosave_seconds", AUTOSAVE_SECONDS)), 0.0, 600.0)


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
# Material surfaces
# -------------------------------------------------------------------------

func _on_material_sheet_changed(_material_id: String) -> void:
	if _inspector != null:
		_inspector._rebuild()
	_sync_context_state()


func _on_material_color_requested(property: String, current: Color, material_id: String) -> void:
	var target_material := material_id
	open_color_sheet(
		{"kind": "material", "id": target_material},
		property,
		current,
		func(color: Color) -> void:
			if doc != null and doc.material_system != null:
				doc.material_system.update_material(
					target_material, {property: "#" + color.to_html(false)}
				)
	)


func _confirm_delete_material(material_id: String) -> void:
	if doc == null or doc.material_system == null:
		return
	var record: Dictionary = doc.material_system.get_material(material_id)
	if record.is_empty():
		return
	var label := str(record.get("name", "this material"))
	_overlay.confirm(
		"Delete material?",
		"Delete %s? Objects keep their shapes but lose this material." % label,
		"Delete",
		func() -> void: _delete_material(material_id)
	)


func _delete_material(material_id: String) -> void:
	if doc == null or doc.material_system == null:
		return
	doc.begin_edit("Delete material")
	var ok: bool = doc.material_system.delete_material(material_id)
	doc.end_edit()
	if ok:
		_on_material_sheet_changed(material_id)
		if _shading_panel != null:
			_shading_panel.refresh()
		_overlay.toast("Material deleted", "trash-2", Kit.TEXT_MUTED)


# -------------------------------------------------------------------------
# Color sheet
# -------------------------------------------------------------------------

func _open_color_sheet(property: String) -> void:
	if doc == null or doc.selected_id == "":
		return
	var obj: Dictionary = doc.get_selected_object()
	if obj.is_empty():
		return
	var selected := doc.selected_id
	var current := Color.from_string(str(obj.get(property, "#A8A8A8")), Color(0.6, 0.6, 0.6))
	var commit := func(color: Color) -> void:
		if property == "color":
			doc.set_material_color(selected, color)
		else:
			doc.set_light_property(selected, property, "#" + color.to_html(false))
	open_color_sheet(
		{"kind": "light" if property != "color" else "object", "id": selected},
		property,
		current,
		commit
	)


## One color surface for every target. The target carries the object, light or
## material identity; `on_commit` writes the field and the caller owns the edit
## semantics. The sheet itself owns the undo boundary for the whole change.
func open_color_sheet(target: Dictionary, property: String, current: Color, on_commit: Callable) -> void:
	if doc == null:
		return
	_color_sheet_active = true
	_color_target = target.duplicate(true)
	_color_id = str(_color_target.get("id", ""))
	_color_property = property
	_color_value = current
	_color_commit = on_commit
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
		swatch.add_theme_stylebox_override("normal", Kit.flat_style(color, Kit.R_CONTROL, Kit.CONTROL_BORDER, 1))
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

	var sheet_title := "Color"
	var sheet_subtitle := "Base color"
	match str(_color_target.get("kind", "object")):
		"light":
			sheet_title = "Light color"
			sheet_subtitle = "Light tint"
		"material":
			sheet_title = "Material colour"
			sheet_subtitle = "Base colour"
	_overlay.show_modal(sheet_title, sheet_subtitle, body, [{"text": "Done", "primary": true}])
	_sync_color_controls()

func _color_preview_style() -> StyleBoxFlat:
	var style := Kit.flat_style(_color_value, Kit.R_CONTROL, Kit.CONTROL_BORDER, 1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style

func _set_color_value(color: Color) -> void:
	if not _color_sheet_active or doc == null:
		return
	_color_value = Color(clampf(color.r, 0.0, 1.0), clampf(color.g, 0.0, 1.0), clampf(color.b, 0.0, 1.0), 1.0)
	if _color_commit.is_valid():
		_color_commit.call(_color_value)
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

func _on_modal_closed() -> void:
	if _view != null and not _render_mode and not _look_through:
		_view.set_hud_visible(true)
	if not _color_sheet_active:
		return
	_color_sheet_active = false
	if doc != null and is_instance_valid(doc):
		doc.end_edit()
	_color_commit = Callable()
	_color_target.clear()
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
	body.add_child(_help_row("Still", "Capture now at the selected size and MSAA"))
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
