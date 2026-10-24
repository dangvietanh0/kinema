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

const DocumentScript = preload("res://src/core/document.gd")
const RenderExport = preload("res://src/core/render_export.gd")
const EditorViewScript = preload("res://src/viewport/editor_view.gd")
const OutlinerScript = preload("res://src/ui/outliner.gd")
const InspectorScript = preload("res://src/ui/inspector.gd")
const TimelineScript = preload("res://src/ui/timeline.gd")
const OverlayScript = preload("res://src/ui/overlay.gd")
const NumberFieldScript = preload("res://src/ui/num_field.gd")
const ScrubBarScript = preload("res://src/ui/scrub_bar.gd")

const AUTOSAVE_SECONDS := 30.0
const WIDE_MIN_WIDTH := 720.0
const SHORT_MAX_HEIGHT := 520.0

const COLOR_PALETTE := [
	"#AAB2BF", "#B3A28B", "#D9C7A7", "#C8B18A", "#D9A45B", "#C97C5D",
	"#A96A6A", "#8C9A7A", "#6F8F86", "#6B7F9E", "#7A6F9E", "#9E7A8C",
	"#FFFFFF", "#D9DEE6", "#8A94A3", "#4B5563", "#232A33", "#11151B",
]

var doc: DocumentScript = null

var _project_meta: Dictionary = {}
var _layout: VBoxContainer
var _topbar: PanelContainer
var _title_label: Label
var _subtitle_label: Label
var _dirty_dot: ColorRect
var _undo_button: Button
var _redo_button: Button
var _save_button: Button

var _body: HBoxContainer
var _rail: PanelContainer
var _center: VBoxContainer
var _viewport_host: Control
var _view: Control
var _compact_bar: PanelContainer
var _add_compact: Button
var _scene_compact: Button
var _props_compact: Button
var _timeline_compact: Button
var _timeline_panel: PanelContainer
var _timeline: VBoxContainer
var _dock_slot: Control
var _dock: PanelContainer
var _dock_box: VBoxContainer
var _dock_close_row: MarginContainer
var _drawer_scene_tab: Button
var _drawer_props_tab: Button
var _outliner_panel: PanelContainer
var _inspector_panel: PanelContainer
var _outliner: VBoxContainer
var _inspector: VBoxContainer
var _drawer_scrim: ColorRect
var _overlay: Control
var _autosave: Timer

var _rail_column: VBoxContainer
var _rail_buttons: Array[Button] = []
var _rail_style: StyleBoxFlat
var _tool := "select"
var _tool_buttons: Dictionary = {}
var _wide := true
var _short := false
var _drawer_open := false
var _compact_tab := "scene"
var _timeline_visible := true
var _short_timeline_open := false
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

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_layout = VBoxContainer.new()
	_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout.add_theme_constant_override("separation", 0)
	add_child(_layout)

	_build_topbar()
	_build_body()
	_build_dock()
	_build_drawer_scrim()

	_overlay = OverlayScript.new()
	add_child(_overlay)
	_overlay.modal_closed.connect(_on_modal_closed)
	_overlay.set_toast_anchor(_viewport_host)

	_autosave = Timer.new()
	_autosave.wait_time = AUTOSAVE_SECONDS
	_autosave.autostart = true
	_autosave.timeout.connect(_on_autosave)
	add_child(_autosave)

	resized.connect(_on_resized)
	call_deferred("_apply_responsive")

# -------------------------------------------------------------------------
# Construction
# -------------------------------------------------------------------------

func _build_topbar() -> void:
	_topbar = PanelContainer.new()
	_topbar.custom_minimum_size.y = 48
	var style := Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT, 0)
	style.border_width_bottom = 1
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	_topbar.add_theme_stylebox_override("panel", style)
	_layout.add_child(_topbar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	_topbar.add_child(row)

	var back := Kit.icon_button("chevron-left", "Back to projects", 34, 17)
	back.pressed.connect(request_close)
	row.add_child(back)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_box.add_theme_constant_override("separation", 0)
	row.add_child(title_box)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	title_box.add_child(title_row)

	_title_label = Kit.label("Untitled", 13, Kit.TEXT, 600)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.clip_text = true
	_title_label.custom_minimum_size.x = 40
	title_row.add_child(_title_label)

	_dirty_dot = ColorRect.new()
	_dirty_dot.color = Color(0, 0, 0, 0)
	_dirty_dot.custom_minimum_size = Vector2(5, 5)
	_dirty_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dirty_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(_dirty_dot)

	_subtitle_label = Kit.mono_label("Untitled project", 8, Kit.TEXT_DIM)
	_subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_subtitle_label.clip_text = true
	title_box.add_child(_subtitle_label)

	_undo_button = Kit.icon_button("undo-2", "Undo", 32, 15)
	_undo_button.disabled = true
	_undo_button.pressed.connect(_undo)
	row.add_child(_undo_button)

	_redo_button = Kit.icon_button("redo-2", "Redo", 32, 15)
	_redo_button.disabled = true
	_redo_button.pressed.connect(_redo)
	row.add_child(_redo_button)

	var render := Kit.icon_button("clapperboard", "Render and export", 32, 16)
	render.pressed.connect(_open_render_sheet)
	row.add_child(render)

	_save_button = Kit.icon_button("save", "Save project", 32, 15)
	_save_button.pressed.connect(func() -> void: _save_project(true))
	row.add_child(_save_button)

	var more := Kit.icon_button("ellipsis-vertical", "Project menu", 32, 16)
	more.pressed.connect(_open_project_menu)
	row.add_child(more)

func _build_body() -> void:
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 0)
	_layout.add_child(_body)

	_build_rail()

	_center = VBoxContainer.new()
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center.add_theme_constant_override("separation", 0)
	_body.add_child(_center)

	_viewport_host = Control.new()
	_viewport_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_host.custom_minimum_size.y = 120
	_viewport_host.clip_contents = true
	_center.add_child(_viewport_host)

	_view = EditorViewScript.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport_host.add_child(_view)
	_view.set_tool(_tool)

	_build_compact_bar()
	_build_timeline()

	_dock_slot = Control.new()
	_dock_slot.custom_minimum_size.x = 320
	_body.add_child(_dock_slot)

func _build_rail() -> void:
	_rail = PanelContainer.new()
	_rail.custom_minimum_size.x = 44
	var style := Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT, 0)
	style.border_width_right = 1
	style.content_margin_left = 3
	style.content_margin_right = 3
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_rail_style = style
	_rail.add_theme_stylebox_override("panel", style)
	_body.add_child(_rail)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_rail_column = column
	_rail.add_child(column)

	_add_tool_button(column, "select", "mouse-pointer-2", "Select  ·  tap to pick")
	_add_tool_button(column, "move", "tool-move", "Move  ·  drag an axis")
	_add_tool_button(column, "rotate", "tool-rotate", "Rotate  ·  drag an axis")
	_add_tool_button(column, "scale", "tool-scale", "Scale  ·  drag an axis")

	var mid_spacer := Control.new()
	mid_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(mid_spacer)

	column.add_child(Kit.vsep())
	var focus := Kit.icon_button("focus", "Frame selection", 34, 16)
	focus.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	focus.pressed.connect(_focus_selection)
	column.add_child(focus)
	_rail_buttons.append(focus)

	var add := Kit.icon_button("plus", "Add object", 34, 16)
	add.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add.add_theme_color_override("icon_normal_color", Kit.FOCUS_BRIGHT)
	add.add_theme_color_override("icon_hover_color", Kit.FOCUS_BRIGHT)
	add.pressed.connect(_open_add_sheet)
	column.add_child(add)
	_rail_buttons.append(add)

func _add_tool_button(parent: Control, tool_id: String, icon_name: String, tooltip: String) -> void:
	var button := Kit.icon_button(icon_name, tooltip, 34, 16)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(_select_tool.bind(tool_id))
	parent.add_child(button)
	_tool_buttons[tool_id] = button
	_rail_buttons.append(button)

func _build_compact_bar() -> void:
	_compact_bar = PanelContainer.new()
	var style := Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT, 0)
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_compact_bar.add_theme_stylebox_override("panel", style)
	_center.add_child(_compact_bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_compact_bar.add_child(row)

	_add_compact = _compact_button("Add", "plus")
	_add_compact.add_theme_color_override("font_color", Kit.FOCUS_BRIGHT)
	_add_compact.add_theme_color_override("icon_normal_color", Kit.FOCUS_BRIGHT)
	_add_compact.pressed.connect(_open_add_sheet)
	row.add_child(_add_compact)

	_scene_compact = _compact_button("Scene", "layers")
	_scene_compact.pressed.connect(func() -> void: _toggle_drawer("scene"))
	row.add_child(_scene_compact)

	_props_compact = _compact_button("Properties", "sliders-horizontal")
	_props_compact.pressed.connect(func() -> void: _toggle_drawer("inspector"))
	row.add_child(_props_compact)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	_timeline_compact = Kit.icon_button("panel-bottom", "Show or hide timeline", 30, 15)
	_timeline_compact.pressed.connect(_toggle_timeline)
	row.add_child(_timeline_compact)

func _compact_button(text_value: String, icon_name: String) -> Button:
	var button := Kit.text_button(text_value, icon_name, false, true)
	button.custom_minimum_size = Vector2(0, 30)
	button.add_theme_stylebox_override("normal", _compact_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	button.add_theme_stylebox_override("hover", _compact_style(Kit.SURFACE_HOVER, Kit.BORDER_SOFT))
	button.add_theme_stylebox_override("pressed", _compact_style(Kit.SURFACE_3, Kit.BORDER))
	return button

func _compact_style(color: Color, border: Color) -> StyleBoxFlat:
	var style := Kit.flat_style(color, 4, border, 1 if border.a > 0.0 else 0)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

func _build_timeline() -> void:
	_timeline_panel = PanelContainer.new()
	_timeline_panel.custom_minimum_size.y = 190
	_timeline_panel.size_flags_vertical = Control.SIZE_FILL
	var style := Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT, 0)
	style.border_width_top = 1
	_timeline_panel.add_theme_stylebox_override("panel", style)
	_center.add_child(_timeline_panel)

	_timeline = TimelineScript.new()
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.notice.connect(_on_timeline_notice)
	_timeline_panel.add_child(_timeline)

func _build_dock() -> void:
	_dock = PanelContainer.new()
	_dock.z_index = 12
	_dock.anchor_left = 1.0
	_dock.anchor_right = 1.0
	_dock.anchor_top = 0.0
	_dock.anchor_bottom = 1.0
	_dock.offset_top = 48.0
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
	_dock_box.add_theme_constant_override("separation", 0)
	_dock.add_child(_dock_box)

	_dock_close_row = MarginContainer.new()
	_dock_close_row.add_theme_constant_override("margin_left", 8)
	_dock_close_row.add_theme_constant_override("margin_right", 6)
	_dock_close_row.add_theme_constant_override("margin_top", 5)
	_dock_close_row.add_theme_constant_override("margin_bottom", 5)
	_dock_close_row.visible = false
	_dock_box.add_child(_dock_close_row)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	_dock_close_row.add_child(tabs)
	_drawer_scene_tab = Kit.text_toggle("Scene", "layers", true)
	_drawer_scene_tab.pressed.connect(func() -> void: _set_compact_tab("scene"))
	tabs.add_child(_drawer_scene_tab)
	_drawer_props_tab = Kit.text_toggle("Properties", "sliders-horizontal", true)
	_drawer_props_tab.pressed.connect(func() -> void: _set_compact_tab("inspector"))
	tabs.add_child(_drawer_props_tab)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.add_child(spacer)
	var close := Kit.icon_button("x", "Close panels", 28, 14)
	close.pressed.connect(_close_drawer)
	tabs.add_child(close)

	_dock_box.add_child(Kit.vsep())

	_outliner_panel = PanelContainer.new()
	_outliner_panel.custom_minimum_size.y = 172
	_outliner_panel.size_flags_vertical = Control.SIZE_FILL
	var out_style := Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT, 0)
	out_style.border_width_bottom = 1
	_outliner_panel.add_theme_stylebox_override("panel", out_style)
	_dock_box.add_child(_outliner_panel)

	_outliner = OutlinerScript.new()
	_outliner.add_requested.connect(_open_add_sheet)
	_outliner_panel.add_child(_outliner)

	_inspector_panel = PanelContainer.new()
	_inspector_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector_panel.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT, 0))
	_dock_box.add_child(_inspector_panel)

	_inspector = InspectorScript.new()
	_inspector.add_requested.connect(_open_add_sheet)
	_inspector.color_requested.connect(_open_color_sheet)
	_inspector_panel.add_child(_inspector)

func _build_drawer_scrim() -> void:
	_drawer_scrim = ColorRect.new()
	_drawer_scrim.color = Color(0.015, 0.022, 0.031, 0.55)
	_drawer_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drawer_scrim.offset_top = 48.0
	# Non-interactive: GUI picking follows tree order, not z_index, so a
	# click-catching scrim added after the dock swallows every tap inside
	# the drawer and closes it. The drawer closes via its own close button,
	# Escape, or the Android back gesture instead.
	_drawer_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer_scrim.visible = false
	_drawer_scrim.z_index = 11
	add_child(_drawer_scrim)

# -------------------------------------------------------------------------
# Documents
# -------------------------------------------------------------------------

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
	doc.seek(doc.current_time, true)
	_update_header()
	_update_history_buttons()
	_select_tool(_tool)
	_set_compact_tab(_compact_tab)

func _on_document_scene_changed() -> void:
	_update_header()

func _on_graphics_changed() -> void:
	if doc != null:
		doc.apply_graphics()

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
	if _title_label == null:
		return
	if doc == null:
		_title_label.text = "Untitled"
		_subtitle_label.text = "No project open"
		_dirty_dot.color = Color(0, 0, 0, 0)
		return
	_title_label.text = doc.title
	_title_label.tooltip_text = doc.title
	var objects := doc.objects.size()
	var dirty := doc.is_dirty()
	if dirty:
		_subtitle_label.text = "Unsaved · %d object%s · %d fps · %.1f s" % [
			objects, "" if objects == 1 else "s", doc.fps, doc.duration
		]
	else:
		var tag := "Autosaved" if _last_save_auto else "Saved"
		_subtitle_label.text = "%s · %d object%s · %d fps · %.1f s" % [
			tag, objects, "" if objects == 1 else "s", doc.fps, doc.duration
		]
	_dirty_dot.color = Kit.FOCUS_BRIGHT if dirty else Color(0, 0, 0, 0)
	_save_button.add_theme_color_override("icon_normal_color", Kit.FOCUS_BRIGHT if dirty else Kit.TEXT_MUTED)
	_save_button.add_theme_color_override("icon_hover_color", Kit.FOCUS_BRIGHT if dirty else Kit.TEXT)
	_save_button.tooltip_text = "Save project" if not dirty else "Save unsaved changes"

func _update_history_buttons() -> void:
	if _undo_button == null:
		return
	var has_undo := doc != null and doc.can_undo()
	var has_redo := doc != null and doc.can_redo()
	_undo_button.disabled = not has_undo
	_redo_button.disabled = not has_redo
	if has_undo:
		_undo_button.tooltip_text = "Undo " + doc.undo_label()
	else:
		_undo_button.tooltip_text = "Undo"
	if has_redo:
		_redo_button.tooltip_text = "Redo " + doc.redo_label()
	else:
		_redo_button.tooltip_text = "Redo"

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
	_apply_responsive()

func _apply_responsive() -> void:
	if _dock == null or not is_inside_tree():
		return
	var wide := size.x >= WIDE_MIN_WIDTH
	var short := size.y < SHORT_MAX_HEIGHT
	_wide = wide
	_short = short
	if wide:
		_drawer_open = false
		_drawer_scrim.visible = false
		_dock.visible = true
		_dock.modulate.a = 1.0
	else:
		_dock.visible = _drawer_open
		_drawer_scrim.visible = _drawer_open

	_topbar.custom_minimum_size.y = 42.0 if short else 48.0
	if _drawer_scrim != null:
		_drawer_scrim.offset_top = 42.0 if short else 48.0
	# The tool rail is the one column that cannot scroll. Shrink its buttons and
	# margins in a short landscape window so it never forces the editor body
	# past the bottom edge (which used to hide the compact bar entirely).
	var rail_size := 30.0 if short else 34.0
	var rail_icon := 15 if short else 16
	_rail.custom_minimum_size.x = 40.0 if short else 44.0
	_rail_column.add_theme_constant_override("separation", 2 if short else 4)
	_rail_style.content_margin_top = 4 if short else 8
	_rail_style.content_margin_bottom = 4 if short else 8
	for button in _rail_buttons:
		button.custom_minimum_size = Vector2(rail_size, rail_size)
		button.add_theme_constant_override("icon_max_width", rail_icon)
	_dock_slot.visible = wide
	_compact_bar.visible = not wide
	_dock_close_row.visible = not wide
	_outliner_panel.visible = wide or _compact_tab == "scene"
	_inspector_panel.visible = wide or _compact_tab == "inspector"
	_outliner_panel.size_flags_vertical = Control.SIZE_FILL if wide else Control.SIZE_EXPAND_FILL
	# In short landscape the dock has only ~400 dp of height. A 112 dp
	# outliner left room for the header and search but barely one scene row,
	# so give the scene list a useful share and let the inspector scroll.
	_outliner_panel.custom_minimum_size.y = 210.0 if short else 172.0
	_timeline_panel.custom_minimum_size.y = 126.0 if short else (190.0 if wide else 154.0)
	_subtitle_label.visible = size.x >= 540.0 and not short

	var dock_width := clampf(size.x * 0.25, 288.0, 340.0) if wide else clampf(size.x * 0.9, 280.0, 360.0)
	if wide and short:
		dock_width = clampf(size.x * 0.34, 272.0, 320.0)
	_dock_slot.custom_minimum_size.x = dock_width
	_dock.offset_left = -dock_width
	_dock.offset_right = 0.0
	_dock.offset_top = 42.0 if short else 48.0
	_sync_timeline_visibility()
	_update_compact_bar()
	_update_drawer_tabs()

func _timeline_should_show() -> bool:
	if not _timeline_visible:
		return false
	# On a phone held sideways the timeline would eat most of the viewport.
	# It starts folded away there and the bottom bar button brings it back.
	return not _short or _short_timeline_open

func _sync_timeline_visibility() -> void:
	if _timeline_panel != null:
		_timeline_panel.visible = _timeline_should_show()

func _toggle_drawer(tab: String) -> void:
	if _wide:
		return
	if _drawer_open and _compact_tab == tab:
		_close_drawer()
		return
	_compact_tab = tab
	_open_drawer()

func _open_drawer() -> void:
	if _wide:
		return
	_drawer_open = true
	_overlay.clear_toast()
	_drawer_scrim.visible = true
	_dock.visible = true
	_dock.modulate.a = 0.0
	_drawer_scrim.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_dock, "modulate:a", 1.0, 0.13)
	tween.tween_property(_drawer_scrim, "modulate:a", 1.0, 0.13)
	_set_compact_tab(_compact_tab)
	_update_compact_bar()

func _close_drawer() -> void:
	if _wide:
		return
	_drawer_open = false
	_drawer_scrim.visible = false
	_dock.visible = false
	_dock.modulate.a = 1.0
	_update_compact_bar()

func _set_compact_tab(tab: String) -> void:
	_compact_tab = tab if tab in ["scene", "inspector"] else "scene"
	if not _wide and _dock != null:
		_outliner_panel.visible = _compact_tab == "scene"
		_inspector_panel.visible = _compact_tab == "inspector"
	_update_drawer_tabs()
	_update_compact_bar()

func _update_drawer_tabs() -> void:
	if _drawer_scene_tab == null:
		return
	_drawer_scene_tab.set_pressed_no_signal(not _wide and _compact_tab == "scene")
	_drawer_props_tab.set_pressed_no_signal(not _wide and _compact_tab == "inspector")

func _update_compact_bar() -> void:
	if _scene_compact == null:
		return
	_style_compact_active(_scene_compact, _drawer_open and _compact_tab == "scene")
	_style_compact_active(_props_compact, _drawer_open and _compact_tab == "inspector")
	Kit.set_icon_active(_timeline_compact, _timeline_should_show())
	_timeline_compact.tooltip_text = "Hide timeline" if _timeline_should_show() else "Show timeline"
	_sync_timeline_visibility()

func _style_compact_active(button: Button, active: bool) -> void:
	if active:
		button.add_theme_color_override("font_color", Kit.FOCUS_BRIGHT)
		button.add_theme_color_override("icon_normal_color", Kit.FOCUS_BRIGHT)
		button.add_theme_stylebox_override("normal", _compact_style(Kit.FOCUS_DARK, Kit.FOCUS * Color(1, 1, 1, 0.4)))
		button.add_theme_stylebox_override("hover", _compact_style(Kit.FOCUS_DARK.lightened(0.04), Kit.FOCUS * Color(1, 1, 1, 0.55)))
		button.add_theme_stylebox_override("pressed", _compact_style(Kit.FOCUS_DARK.darkened(0.06), Kit.FOCUS))
	else:
		button.add_theme_color_override("font_color", Kit.TEXT_MUTED)
		button.add_theme_color_override("icon_normal_color", Kit.TEXT_MUTED)
		button.add_theme_stylebox_override("normal", _compact_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
		button.add_theme_stylebox_override("hover", _compact_style(Kit.SURFACE_HOVER, Kit.BORDER_SOFT))
		button.add_theme_stylebox_override("pressed", _compact_style(Kit.SURFACE_3, Kit.BORDER))

func _toggle_timeline() -> void:
	_timeline_visible = not _timeline_visible
	if _short:
		_short_timeline_open = _timeline_visible
	_sync_timeline_visibility()
	_update_compact_bar()

# -------------------------------------------------------------------------
# Tools, editing and shortcuts
# -------------------------------------------------------------------------

func _select_tool(tool_id: String) -> void:
	_tool = tool_id
	if _view != null:
		_view.set_tool(_tool)
	for id in _tool_buttons:
		var button: Button = _tool_buttons[id]
		Kit.set_icon_active(button, str(id) == _tool)

func _focus_selection() -> void:
	if _view != null:
		_view.focus_selection()

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
	button.custom_minimum_size = Vector2(0, 40)
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
	_render_still_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_render_still_button.tooltip_text = "Capture now and save in app storage"
	_render_still_button.pressed.connect(_quick_still)
	still_actions.add_child(_render_still_button)
	_render_save_button = Kit.text_button("Save still…", "download", false, true)
	_render_save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_render_progress.add_theme_stylebox_override("background", Kit.flat_style(Kit.SURFACE_3, 3, Kit.BORDER_SOFT, 0))
	_render_progress.add_theme_stylebox_override("fill", Kit.flat_style(Kit.FOCUS, 3, Kit.FOCUS, 0))
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
	button.custom_minimum_size = Vector2(0, 38)
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
	body.add_child(_menu_button("Project settings", "sliders-horizontal", _open_settings))
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

func _open_settings() -> void:
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
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 4)
	body.add_child(modes)
	var mode_group := ButtonGroup.new()
	mode_group.allow_unpress = false
	_settings_linear = Kit.text_toggle("Linear", "", true)
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

func _graphics_choice(parent: Control, title: String, hint: String, options: Array, current_value: Variant, on_change: Callable) -> void:
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
		head.add_child(Kit.label(hint, 9, Kit.TEXT_DIM))
	block.add_child(head)

	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 3)
	block.add_child(strip)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for option in options:
		var data: Dictionary = option
		var value: Variant = data.get("value")
		var button := Kit.text_toggle(str(data.get("label", "")), "", true)
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.button_pressed = value == current_value
		button.toggled.connect(func(on: bool) -> void:
			if on:
				on_change.call(value)
				# A single option edit moves the preset to Custom; keep the
				# preset chips honest instead of leaving the old one lit.
				_sync_preset_buttons()
		)
		strip.add_child(button)

func _open_graphics_settings() -> void:
	if doc == null:
		return
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)

	var renderer_row := HBoxContainer.new()
	renderer_row.add_theme_constant_override("separation", 8)
	renderer_row.add_child(Kit.label("Renderer", 12, Kit.TEXT))
	var renderer_spacer := Control.new()
	renderer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	renderer_row.add_child(renderer_spacer)
	var renderer_text := Gfx.display_name()
	renderer_row.add_child(Kit.mono_label(renderer_text, 9, Kit.TEXT_MUTED))
	body.add_child(renderer_row)

	var unavailable := ""
	if not Gfx.is_forward():
		unavailable = "Requires Forward+"

	body.add_child(Kit.section_label("Quality preset"))
	graphics_preset_row(body)
	body.add_child(Kit.vsep())

	body.add_child(Kit.section_label("Anti-aliasing"))
	_graphics_choice(body, "Samples", "MSAA", [
		{"label": "Off", "value": 0},
		{"label": "2×", "value": 1},
		{"label": "4×", "value": 2},
		{"label": "8×", "value": 3},
	], Gfx.msaa, func(value: Variant) -> void: Gfx.set_option("msaa", value))
	_graphics_choice(body, "Temporal", unavailable, [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.taa, func(value: Variant) -> void: Gfx.set_option("taa", value))
	body.add_child(Kit.vsep())

	body.add_child(Kit.section_label("Lighting and surfaces"))
	_graphics_choice(body, "Ambient occlusion", unavailable, [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.ssao, func(value: Variant) -> void: Gfx.set_option("ssao", value))
	_graphics_choice(body, "AO quality", "", [
		{"label": "Low", "value": 0},
		{"label": "Medium", "value": 1},
		{"label": "High", "value": 2},
		{"label": "Ultra", "value": 3},
	], Gfx.ssao_quality, func(value: Variant) -> void: Gfx.set_option("ssao_quality", value))
	_graphics_choice(body, "Indirect lighting", unavailable, [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.ssil, func(value: Variant) -> void: Gfx.set_option("ssil", value))
	_graphics_choice(body, "Screen-space reflections", unavailable, [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.ssr, func(value: Variant) -> void: Gfx.set_option("ssr", value))
	_graphics_choice(body, "Glow", "", [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.glow, func(value: Variant) -> void: Gfx.set_option("glow", value))
	_graphics_choice(body, "Volumetric fog", unavailable, [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.volumetric_fog, func(value: Variant) -> void: Gfx.set_option("volumetric_fog", value))
	body.add_child(Kit.vsep())

	body.add_child(Kit.section_label("Shadows"))
	_graphics_choice(body, "Filter quality", "", [
		{"label": "Low", "value": 0},
		{"label": "Medium", "value": 1},
		{"label": "High", "value": 2},
		{"label": "Ultra", "value": 3},
	], Gfx.shadow_quality, func(value: Variant) -> void: Gfx.set_option("shadow_quality", value))
	_graphics_choice(body, "Cascades", "sun", [
		{"label": "1", "value": 1},
		{"label": "2", "value": 2},
		{"label": "4", "value": 4},
	], Gfx.shadow_splits, func(value: Variant) -> void: Gfx.set_option("shadow_splits", value))
	_graphics_choice(body, "Range", "meters", [
		{"label": "25", "value": 25.0},
		{"label": "40", "value": 40.0},
		{"label": "60", "value": 60.0},
		{"label": "100", "value": 100.0},
	], Gfx.shadow_distance, func(value: Variant) -> void: Gfx.set_option("shadow_distance", value))
	body.add_child(Kit.vsep())

	body.add_child(Kit.section_label("Performance"))
	_graphics_choice(body, "3D resolution", "%", [
		{"label": "60", "value": 0.6},
		{"label": "80", "value": 0.8},
		{"label": "100", "value": 1.0},
	], Gfx.scale_3d, func(value: Variant) -> void: Gfx.set_option("scale_3d", value))
	_graphics_choice(body, "Frame cap", "fps", [
		{"label": "30", "value": 30},
		{"label": "60", "value": 60},
		{"label": "90", "value": 90},
		{"label": "120", "value": 120},
	], Gfx.max_fps, func(value: Variant) -> void: Gfx.set_option("max_fps", value))

	var note := Kit.label("Changes apply immediately and are stored on this device. Render output resolution and anti-aliasing are set in the Render sheet.", 9, Kit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)

	_overlay.show_modal("Graphics and performance", "Real engine settings, not decoration.", body, [
		{"text": "Done", "primary": true},
	])

func graphics_preset_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	_preset_buttons.clear()
	for entry in [
		{"label": "Performance", "value": "performance"},
		{"label": "Balanced", "value": "balanced"},
		{"label": "Quality", "value": "quality"},
	]:
		var data: Dictionary = entry
		var preset_name := str(data.get("value"))
		var button := Kit.text_toggle(str(data.get("label")), "", true)
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_meta("preset", preset_name)
		button.button_pressed = Gfx.preset == preset_name
		button.toggled.connect(func(on: bool) -> void:
			if on:
				Gfx.apply_preset(preset_name)
				call_deferred("_open_graphics_settings")
		)
		row.add_child(button)
		_preset_buttons.append(button)

func _sync_preset_buttons() -> void:
	for button in _preset_buttons:
		if not is_instance_valid(button):
			continue
		button.set_pressed_no_signal(str(button.get_meta("preset", "")) == Gfx.preset)

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
	_color_value = Color.from_string(str(obj.get(property, "#AAB2BF")), Color(0.6, 0.6, 0.6))
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
		swatch.custom_minimum_size = Vector2(30, 28)
		swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		swatch.tooltip_text = str(hex)
		swatch.add_theme_stylebox_override("normal", Kit.flat_style(color, 4, Kit.BORDER, 1))
		swatch.add_theme_stylebox_override("hover", Kit.flat_style(color.lightened(0.09), 4, Kit.TEXT_MUTED, 1))
		swatch.add_theme_stylebox_override("pressed", Kit.flat_style(color.darkened(0.12), 4, Kit.FOCUS, 1))
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
		bar.fill_color = Color(0.72, 0.55, 0.38) if i == 0 else (Color(0.48, 0.63, 0.43) if i == 1 else Color(0.38, 0.53, 0.75))
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
	var style := Kit.flat_style(_color_value, 7, Kit.BORDER, 1)
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
		_color_preview_label.add_theme_color_override("font_color", Color(0.05, 0.06, 0.07) if luminance > 0.58 else Color(0.93, 0.94, 0.95))
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

func _on_modal_closed() -> void:
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
	var licenses := Kit.label("Engine: Godot (MIT). Fonts: Inter and JetBrains Mono (SIL OFL). Icons: Lucide (ISC). Full notices are bundled with this build.", 9, Kit.TEXT_DIM)
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
