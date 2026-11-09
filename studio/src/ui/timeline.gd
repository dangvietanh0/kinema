extends VBoxContainer
## The timeline pane: a 44 dp transport, a pane header with the real
## Dope/Graph switch, an optional graph header, and the dope sheet or the
## segment graph body.
##
## The sheet intentionally shows one object's three transform channels instead
## of a full scene-wide spreadsheet. That keeps the timeline legible on a phone
## while still allowing keys to be created, retimed and deleted directly.

signal notice(text: String)
## Emitted when the user asks to fold the timeline.
signal close_requested
## Emitted when the sheet actually switches between dope and graph mode.
signal mode_changed(mode: String)
## The duration chip asked for a row that can edit the active clip length.
signal duration_row_changed(open: bool)
## A shrink would delete keys; the editor owns the confirmation sheet.
signal duration_confirmation_requested(value: float, message: String)
## The active channel changed, whether by the graph tab strip or a dope row.
signal channel_selected(channel: String)
## A segment was selected in the graph body (or forwarded from the dope sheet).
signal segment_selected(span: Dictionary)
## The Animate timecode asked for the editor's real time entry sheet.
signal time_entry_requested
## The fps chip changed the document frame rate.
signal fps_changed(fps: int)
## The graph header's Key button asked the editor for the key info sheet.
signal key_info_requested(index: int)

class DopeSheet:
	extends Control

	var timeline
	var _drawn := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		_drawn = true
		if timeline != null:
			timeline._draw_sheet(self)

	func _gui_input(event: InputEvent) -> void:
		if timeline != null:
			timeline._sheet_input(event, self)

const DocumentScript = preload("res://src/core/document.gd")
const NumberFieldScript = preload("res://src/ui/num_field.gd")
const SegmentGraphScript = preload("res://src/ui/segment_graph.gd")
const FPS_CHOICES := [12, 24, 30, 60]
const COMPONENTS := ["all", "x", "y", "z"]
const COMPONENT_LABELS := {"all": "All", "x": "X", "y": "Y", "z": "Z"}

var doc: DocumentScript = null

var _sheet: Control
var _segment_graph: Control
var _selected_span: Dictionary = {}
var _play_button: Button
var _clip_transport_enabled := true
var _loop_button: Button
var _snap_button: Button
var _delete_button: Button
var _time_button: Button
var _fps_button: Button
var _add_key_button: Button
var _fit_button: Button

var _transport_panel: PanelContainer
var _transport_style: StyleBoxFlat
var _gesture_hint: Label
var _duration_chip: Button
var _duration_row: PanelContainer
var _duration_field
var _match_button: Button
var _extend_button: Button
var _duration_close_button: Button
var _duration_open := false
var _hint_seen := false

# Pane header (clip/layer, Dope/Graph, segment navigation).
var _pane_header_panel: PanelContainer
var _clip_selector: Button
var _dope_tab: Button
var _graph_tab: Button
var _prev_button: Button
var _next_button: Button
var _segment_label: Label
var _pane_tab_group: ButtonGroup
var _merged_tab_group: ButtonGroup

# Graph header (channel, component, Ease/Value/Speed, Key).
var _graph_header_panel: PanelContainer
var _graph_header_wide: HBoxContainer
var _graph_header_narrow: VBoxContainer
var _merged_header_panel: PanelContainer
var _merged_row: HBoxContainer
var _wide_channel_button: Button
var _narrow_channel_button: Button
var _merged_channel_button: Button
var _key_button: Button
var _narrow_key_button: Button
var _merged_key_button: Button
var _presets_button: Button
var _narrow_presets_button: Button
var _component_menu_button: Button
var _component_menu: PopupMenu
var _more_button: Button
var _more_menu: PopupMenu
var _component_buttons: Array[Button] = []
var _wide_tabs_host: HBoxContainer
var _narrow_tabs_host: HBoxContainer
var _merged_tabs_host: HBoxContainer
var _merged_dope_tab: Button
var _merged_graph_tab: Button

var _selected_channel := "position"
var _selected_index := -1
var _selected_data_id := ""
var _key_hits: Array = []
var _channel_hits: Array = []
var _scrubbing := false
var _dragging_key := false
var _sync_flags := false
var _mode := "dope"
var _short_layout := false
var _sheet_rule: ColorRect
var _sheet_open := true
var _chrome_mode := "studio"
## Width the editor has actually reserved for the sheet, before the transport's
## own minimum size is applied. A container reports its forced size, so using
## that to decide the overflow layout made the transport's minimum width widen
## the center column and hide its own narrow state.
var _available_width := -1.0
var _transport_buttons: Array[Button] = []

# --- Time viewport (horizontal pan/zoom over the duration) -----------------
## The dope sheet maps time to pixels through this visible window instead of
## squeezing the whole duration into the canvas width. The initial window is
## the full duration, so the default view is unchanged.
const SCROLLBAR_HIT := 44.0
const SCROLLBAR_TRACK_H := 6.0
const MIN_VIEW_SPAN := 0.5
const TRANSPORT_H := 44.0
const HEADER_H := 44.0
const DOPE_RULER_H := 44.0
const CHANNEL_EDGE := 1.0
const KEY_HIT_RADIUS := 22.0
var _view_start := 0.0
var _view_span := -1.0
var _view_duration_seen := -1.0
var _scroll_dragging := false
var _scroll_grab_x := 0.0
var _touches: Dictionary = {}
var _panning_view := false
var _pan_last_mid := Vector2.ZERO
var _pinch_dist := -1.0
## Snapshot taken on the first touch. A second touch cancels whatever the
## single-finger press started and restores this exact state.
var _gesture_time_snapshot := 0.0
var _gesture_playing_snapshot := false
var _gesture_edit_snapshot := false
var _gesture_view_snapshot := Vector2.ZERO
var _gesture_active := false

var _label_width := 104.0
var _ruler_h := DOPE_RULER_H
var _row_h := 26.0
var _grid_left := 110.0
var _grid_width := 200.0

func _ready() -> void:
	add_theme_constant_override("separation", 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_transport()
	_build_pane_header()
	_build_graph_header()
	_build_merged_header()
	_build_duration_row()
	_build_sheet()
	_build_segment_graph()
	resized.connect(_refresh_layout)
	_refresh_layout()

func setup(document: Node3D) -> void:
	doc = document
	if _segment_graph != null:
		_segment_graph.setup(doc)
	doc.playback_changed.connect(_on_playback_changed)
	doc.selection_changed.connect(_on_selection_changed)
	doc.object_changed.connect(_on_object_changed)
	doc.transform_changed.connect(_on_transform_changed)
	doc.keyframes_changed.connect(_on_keyframes_changed)
	doc.scene_changed.connect(_on_scene_changed)
	if doc.has_signal("active_clip_changed") \
			and not doc.active_clip_changed.is_connected(_on_active_clip_changed):
		doc.active_clip_changed.connect(_on_active_clip_changed)
	_sync_flag_states()
	_refresh_transport(doc.current_time, doc.is_playing)
	_refresh_layout()
	_sheet.queue_redraw()

# -------------------------------------------------------------------------
# Transport
# -------------------------------------------------------------------------

func _build_transport() -> void:
	var panel := PanelContainer.new()
	_transport_panel = panel
	panel.custom_minimum_size.y = TRANSPORT_H
	var style := Kit.flat_style(Kit.SURFACE_2, Kit.R_PANEL, Color(0, 0, 0, 0), 0)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", style)
	_transport_style = style
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	panel.add_child(row)

	_play_button = _transport_icon("play", "Play / pause")
	_play_button.add_theme_color_override("icon_normal_color", Kit.TIME_BRIGHT)
	_play_button.add_theme_color_override("icon_hover_color", Kit.FOCUS_BRIGHT)
	_play_button.add_theme_color_override("icon_pressed_color", Kit.BG)
	_play_button.add_theme_stylebox_override("normal",
		Kit.flat_style(Kit.SURFACE_2, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	_play_button.add_theme_stylebox_override("hover",
		Kit.flat_style(Kit.SURFACE_HOVER, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	_play_button.add_theme_stylebox_override("pressed",
		Kit.flat_style(Kit.TIME_BRIGHT, Kit.R_CONTROL, Kit.TIME_BRIGHT, 0))
	_play_button.pressed.connect(_on_play)
	row.add_child(_play_button)

	_loop_button = _transport_icon("repeat", "Loop playback")
	_loop_button.toggle_mode = true
	_loop_button.toggled.connect(_on_loop_toggled)
	row.add_child(_loop_button)

	_time_button = Kit.text_button("00:00:00", "", false, true)
	_time_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_button.custom_minimum_size = Vector2(96, TRANSPORT_H)
	_time_button.add_theme_font_override("font", Kit.font_mono)
	_time_button.add_theme_font_size_override("font_size", 12)
	_time_button.tooltip_text = "Go to time"
	_time_button.set_meta("action_id", "time")
	_time_button.set_meta("action_icon", "")
	_time_button.pressed.connect(func() -> void: time_entry_requested.emit())
	row.add_child(_time_button)

	_fps_button = Kit.text_button("24 fps", "", false, true)
	_fps_button.custom_minimum_size = Vector2(56, TRANSPORT_H)
	_fps_button.add_theme_font_override("font", Kit.font_mono)
	_fps_button.add_theme_font_size_override("font_size", 12)
	_fps_button.tooltip_text = "Frame rate"
	_fps_button.set_meta("action_id", "fps")
	_fps_button.pressed.connect(_open_fps_menu)
	row.add_child(_fps_button)

	_snap_button = _transport_icon("magnet", "Snap keys to frames")
	_snap_button.toggle_mode = true
	_snap_button.toggled.connect(_on_snap_toggled)
	row.add_child(_snap_button)

	_add_key_button = _transport_icon("diamond-plus", "Insert transform keys at playhead")
	_add_key_button.pressed.connect(_on_key_all)
	row.add_child(_add_key_button)

	_delete_button = _transport_icon("trash-2", "Delete selected key")
	_delete_button.disabled = true
	_delete_button.add_theme_color_override("icon_disabled_color", Kit.TEXT_DIM * Color(1, 1, 1, 0.4))
	_delete_button.pressed.connect(_on_delete_key)
	row.add_child(_delete_button)

	_fit_button = _transport_icon("focus", "Fit the whole clip")
	_fit_button.pressed.connect(fit_time_view)
	row.add_child(_fit_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	_duration_chip = Kit.text_button("", "", false, true)
	_duration_chip.custom_minimum_size = Vector2(56, TRANSPORT_H)
	_duration_chip.clip_text = false
	_duration_chip.tooltip_text = "Clip duration and sequence length"
	_duration_chip.add_theme_font_size_override("font_size", Kit.TYPE_CAPTION)
	_duration_chip.pressed.connect(open_duration_row)
	row.add_child(_duration_chip)


func _transport_icon(icon_name: String, tooltip: String) -> Button:
	var button := Kit.icon_button(icon_name, tooltip, 44, 18)
	button.set_meta("action_id", icon_name)
	button.set_meta("action_icon", icon_name)
	_transport_buttons.append(button)
	return button


func _open_fps_menu() -> void:
	if doc == null:
		return
	var menu := PopupMenu.new()
	for choice in FPS_CHOICES:
		menu.add_item("%d fps" % int(choice), int(choice))
		if int(choice) == doc.fps:
			menu.set_item_checked(menu.item_count - 1, true)
	menu.id_pressed.connect(func(value: int) -> void:
		_set_fps(value)
		menu.queue_free()
	)
	menu.popup_hide.connect(menu.queue_free)
	_fps_button.add_child(menu)
	menu.popup_on_parent(Rect2(0.0, _fps_button.size.y, 1.0, 1.0))


func _set_fps(value: int) -> void:
	if doc == null:
		return
	doc.set_fps(value)
	_refresh_transport(doc.current_time, doc.is_playing)
	fps_changed.emit(value)

# -------------------------------------------------------------------------
# Pane header
# -------------------------------------------------------------------------

func _build_pane_header() -> void:
	_pane_header_panel = _header_panel()
	add_child(_pane_header_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_pane_header_panel.add_child(row)

	_clip_selector = Kit.text_button("", "", false, true)
	_clip_selector.custom_minimum_size = Vector2(112, HEADER_H)
	_clip_selector.clip_text = true
	_clip_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_clip_selector.tooltip_text = "Active clip and layer"
	_clip_selector.pressed.connect(_open_clip_menu)
	row.add_child(_clip_selector)

	_pane_tab_group = ButtonGroup.new()
	_dope_tab = _mode_tab("Dope", _pane_tab_group)
	_dope_tab.pressed.connect(func() -> void: set_mode("dope"))
	row.add_child(_dope_tab)
	_graph_tab = _mode_tab("Graph", _pane_tab_group)
	_graph_tab.pressed.connect(func() -> void: set_mode("graph"))
	row.add_child(_graph_tab)

	_prev_button = Kit.icon_button("chevron-left", "Previous segment", 44, 16)
	_prev_button.set_meta("action_id", "prev_segment")
	_prev_button.set_meta("action_icon", "chevron-left")
	_prev_button.pressed.connect(func() -> void: _step_segment(-1))
	row.add_child(_prev_button)

	_next_button = Kit.icon_button("chevron-right", "Next segment", 44, 16)
	_next_button.set_meta("action_id", "next_segment")
	_next_button.set_meta("action_icon", "chevron-right")
	_next_button.pressed.connect(func() -> void: _step_segment(1))
	row.add_child(_next_button)

	_segment_label = Kit.mono_label("", 11, Kit.TEXT_MUTED)
	_segment_label.clip_text = true
	_segment_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_segment_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_segment_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_segment_label)


func _header_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = HEADER_H
	var style := Kit.flat_style(Kit.SURFACE_2, Kit.R_PANEL, Color(0, 0, 0, 0), 0)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _mode_tab(label: String, group: ButtonGroup) -> Button:
	var button := Kit.text_button(label, "", false, true)
	button.toggle_mode = true
	button.button_group = group
	button.custom_minimum_size = Vector2(60, HEADER_H)
	button.add_theme_font_size_override("font_size", 11)
	return button


func _open_clip_menu() -> void:
	if doc == null or doc.animation_system == null:
		return
	var menu := PopupMenu.new()
	var targets: Array = []
	var clips: PackedStringArray = doc.animation_system.clip_ids()
	for clip_id in clips:
		var clip: Dictionary = doc.animation_system.get_clip(clip_id)
		menu.add_item("Clip · " + str(clip.get("name", clip_id)))
		targets.append({"kind": "clip", "id": str(clip_id)})
	if not clips.is_empty():
		menu.add_separator()
	for layer in doc.animation_system.layers():
		if not layer is Dictionary:
			continue
		menu.add_item("Layer · " + str(layer.get("name", layer.get("id", ""))))
		targets.append({"kind": "layer", "id": str(layer.get("id", ""))})
	menu.id_pressed.connect(func(index: int) -> void:
		if index < 0 or index >= targets.size():
			menu.queue_free()
			return
		var target: Dictionary = targets[index]
		if str(target["kind"]) == "clip":
			doc.set_active_clip(str(target["id"]))
		else:
			doc.animation_system.set_active_layer(str(target["id"]))
		_selected_span = {}
		_sync_header_state()
		_refresh_graph_context()
		if _sheet != null:
			_sheet.queue_redraw()
		menu.queue_free()
	)
	menu.popup_hide.connect(menu.queue_free)
	_clip_selector.add_child(menu)
	menu.popup_on_parent(Rect2(0.0, _clip_selector.size.y, 1.0, 1.0))

# -------------------------------------------------------------------------
# Graph header
# -------------------------------------------------------------------------

func _build_graph_header() -> void:
	_graph_header_panel = _header_panel()
	add_child(_graph_header_panel)

	_graph_header_wide = HBoxContainer.new()
	_graph_header_wide.add_theme_constant_override("separation", 4)
	_graph_header_panel.add_child(_graph_header_wide)

	_wide_channel_button = _channel_button()
	_wide_channel_button.pressed.connect(func() -> void: _open_channel_menu(_wide_channel_button))
	_graph_header_wide.add_child(_wide_channel_button)

	for component in COMPONENTS:
		var chip := Kit.text_button(str(COMPONENT_LABELS.get(component, component)), "", false, true)
		chip.toggle_mode = true
		chip.custom_minimum_size = Vector2(44, HEADER_H)
		chip.add_theme_font_size_override("font_size", 11)
		chip.tooltip_text = "Show " + str(COMPONENT_LABELS.get(component, component))
		chip.pressed.connect(func() -> void: _set_component(component))
		_component_buttons.append(chip)
		_graph_header_wide.add_child(chip)

	_wide_tabs_host = HBoxContainer.new()
	_wide_tabs_host.add_theme_constant_override("separation", 0)
	_graph_header_wide.add_child(_wide_tabs_host)

	_key_button = Kit.text_button("Key", "", false, true)
	_key_button.custom_minimum_size = Vector2(44, HEADER_H)
	_key_button.add_theme_font_size_override("font_size", 11)
	_key_button.tooltip_text = "Key time and value"
	_key_button.pressed.connect(_request_key_info)
	_graph_header_wide.add_child(_key_button)

	_presets_button = Kit.icon_button("sliders-horizontal", "Curve presets", 44, 16)
	_presets_button.set_meta("action_id", "presets")
	_presets_button.pressed.connect(func() -> void: _open_presets_menu(_presets_button))
	_graph_header_wide.add_child(_presets_button)

	_graph_header_narrow = VBoxContainer.new()
	_graph_header_narrow.add_theme_constant_override("separation", 0)
	_graph_header_panel.add_child(_graph_header_narrow)

	var narrow_top := HBoxContainer.new()
	narrow_top.add_theme_constant_override("separation", 4)
	_graph_header_narrow.add_child(narrow_top)
	_narrow_channel_button = _channel_button()
	_narrow_channel_button.custom_minimum_size.x = 96
	_narrow_channel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_narrow_channel_button.pressed.connect(func() -> void: _open_channel_menu(_narrow_channel_button))
	narrow_top.add_child(_narrow_channel_button)
	_narrow_key_button = Kit.text_button("Key", "", false, true)
	_narrow_key_button.custom_minimum_size = Vector2(44, HEADER_H)
	_narrow_key_button.add_theme_font_size_override("font_size", 11)
	_narrow_key_button.pressed.connect(_request_key_info)
	narrow_top.add_child(_narrow_key_button)
	_narrow_presets_button = Kit.icon_button("sliders-horizontal", "Curve presets", 44, 16)
	_narrow_presets_button.pressed.connect(func() -> void: _open_presets_menu(_narrow_presets_button))
	narrow_top.add_child(_narrow_presets_button)

	var narrow_bottom := HBoxContainer.new()
	narrow_bottom.add_theme_constant_override("separation", 4)
	_graph_header_narrow.add_child(narrow_bottom)
	_component_menu_button = Kit.text_button("All", "chevron-down", false, true)
	_component_menu_button.custom_minimum_size = Vector2(64, HEADER_H)
	_component_menu_button.add_theme_font_size_override("font_size", 11)
	_component_menu_button.pressed.connect(_open_component_menu)
	narrow_bottom.add_child(_component_menu_button)
	_narrow_tabs_host = HBoxContainer.new()
	_narrow_tabs_host.add_theme_constant_override("separation", 0)
	narrow_bottom.add_child(_narrow_tabs_host)

	_component_menu = PopupMenu.new()
	for i in range(COMPONENTS.size()):
		_component_menu.add_check_item(str(COMPONENT_LABELS.get(COMPONENTS[i], COMPONENTS[i])), i)
	_component_menu.id_pressed.connect(func(index: int) -> void:
		if index >= 0 and index < COMPONENTS.size():
			_set_component(str(COMPONENTS[index]))
	)
	add_child(_component_menu)


func _channel_button() -> Button:
	var button := Kit.text_button("", "", false, true)
	button.custom_minimum_size = Vector2(112, HEADER_H)
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.tooltip_text = "Object and channel"
	return button


func _build_merged_header() -> void:
	_merged_header_panel = _header_panel()
	add_child(_merged_header_panel)

	_merged_row = HBoxContainer.new()
	_merged_row.add_theme_constant_override("separation", 4)
	_merged_header_panel.add_child(_merged_row)

	_merged_tab_group = ButtonGroup.new()
	_merged_dope_tab = _mode_tab("Dope", _merged_tab_group)
	_merged_dope_tab.pressed.connect(func() -> void: set_mode("dope"))
	_merged_row.add_child(_merged_dope_tab)
	_merged_graph_tab = _mode_tab("Graph", _merged_tab_group)
	_merged_graph_tab.pressed.connect(func() -> void: set_mode("graph"))
	_merged_row.add_child(_merged_graph_tab)

	_merged_channel_button = _channel_button()
	_merged_channel_button.custom_minimum_size.x = 96
	_merged_channel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_merged_channel_button.pressed.connect(func() -> void: _open_channel_menu(_merged_channel_button))
	_merged_row.add_child(_merged_channel_button)

	_merged_tabs_host = HBoxContainer.new()
	_merged_tabs_host.add_theme_constant_override("separation", 0)
	_merged_row.add_child(_merged_tabs_host)

	_merged_key_button = Kit.text_button("Key", "", false, true)
	_merged_key_button.custom_minimum_size = Vector2(44, HEADER_H)
	_merged_key_button.add_theme_font_size_override("font_size", 11)
	_merged_key_button.pressed.connect(_request_key_info)
	_merged_row.add_child(_merged_key_button)

	_more_button = Kit.icon_button("ellipsis-vertical", "More graph actions", 44, 16)
	_more_button.set_meta("action_id", "more")
	_more_button.set_meta("action_icon", "ellipsis-vertical")
	_more_button.pressed.connect(_open_more_menu)
	_merged_row.add_child(_more_button)

	_more_menu = PopupMenu.new()
	_more_menu.id_pressed.connect(_on_more_menu_id)
	add_child(_more_menu)


func _open_channel_menu(anchor: Button) -> void:
	if doc == null:
		return
	var menu := PopupMenu.new()
	var targets: Array = []
	var objects: Array = doc.objects
	for raw in objects:
		if not raw is Dictionary:
			continue
		var obj: Dictionary = raw
		menu.add_item("Object · " + str(obj.get("name", obj.get("id", ""))))
		targets.append({"kind": "object", "id": str(obj.get("id", ""))})
	if not objects.is_empty():
		menu.add_separator()
	for channel in doc.CHANNELS:
		menu.add_item("Channel · " + str(doc.CHANNEL_LABELS.get(channel, channel)))
		targets.append({"kind": "channel", "id": str(channel)})
	menu.id_pressed.connect(func(index: int) -> void:
		if index < 0 or index >= targets.size():
			menu.queue_free()
			return
		var target: Dictionary = targets[index]
		if str(target["kind"]) == "object":
			doc.set_selection(str(target["id"]))
		else:
			set_channel(str(target["id"]))
		menu.queue_free()
	)
	menu.popup_hide.connect(menu.queue_free)
	anchor.add_child(menu)
	menu.popup_on_parent(Rect2(0.0, anchor.size.y, 1.0, 1.0))


func _open_component_menu() -> void:
	_update_component_menu()
	_component_menu.popup_on_parent(Rect2(0.0, _component_menu_button.size.y, 1.0, 1.0))


func _update_component_menu() -> void:
	var active := _graph_component()
	for i in range(COMPONENTS.size()):
		var item_index := &""
		# PopupMenu items are indexed by position; every row here is a check item.
		_component_menu.set_item_checked(i, str(COMPONENTS[i]) == active)
	if _component_menu_button != null:
		_component_menu_button.text = str(COMPONENT_LABELS.get(active, "All"))
		_component_menu_button.tooltip_text = "Component: " + str(COMPONENT_LABELS.get(active, "All"))


func _set_component(component: String) -> void:
	if _segment_graph != null:
		_segment_graph.set_component(component)
	_sync_component_chips()
	_update_component_menu()


func _graph_component() -> String:
	if _segment_graph != null and _segment_graph.has_method("component"):
		return str(_segment_graph.component())
	return "all"


func _sync_component_chips() -> void:
	var active := _graph_component()
	for i in range(_component_buttons.size()):
		var chip: Button = _component_buttons[i]
		if chip == null or not is_instance_valid(chip):
			continue
		var component := str(COMPONENTS[i]) if i < COMPONENTS.size() else "all"
		chip.set_pressed_no_signal(component == active)
	_update_component_menu()


func _request_key_info() -> void:
	if doc == null or doc.selected_id == "" or _selected_index < 0 \
			or _selected_data_id != doc.selected_id:
		notice.emit("Select a key first.")
		return
	key_info_requested.emit(_selected_index)


func _open_presets_menu(anchor: Button) -> void:
	if _segment_graph == null:
		return
	var menu := PopupMenu.new()
	var ids: PackedStringArray = _segment_graph.preset_ids()
	for i in range(ids.size()):
		var preset_id := str(ids[i])
		menu.add_item(_preset_label(preset_id), i)
	menu.id_pressed.connect(func(index: int) -> void:
		if index >= 0 and index < ids.size():
			var chip: Button = _segment_graph.preset_chip(str(ids[index]))
			if chip != null:
				chip.pressed.emit()
		menu.queue_free()
	)
	menu.popup_hide.connect(menu.queue_free)
	anchor.add_child(menu)
	menu.popup_on_parent(Rect2(0.0, anchor.size.y, 1.0, 1.0))


func _preset_label(preset_id: String) -> String:
	for def in SegmentGraphScript.PRESET_DEFS:
		if str(def.get("id", "")) == preset_id:
			return str(def.get("label", preset_id))
	return preset_id


func _open_more_menu() -> void:
	if _more_menu == null:
		return
	_more_menu.clear()
	var active := _graph_component()
	for i in range(COMPONENTS.size()):
		_more_menu.add_check_item(str(COMPONENT_LABELS.get(COMPONENTS[i], COMPONENTS[i])), i)
		_more_menu.set_item_checked(i, str(COMPONENTS[i]) == active)
	_more_menu.add_separator()
	var prev_id := _more_menu.item_count
	_more_menu.add_item("Previous segment", 10)
	_more_menu.set_item_disabled(prev_id, _prev_button != null and _prev_button.disabled)
	var next_id := _more_menu.item_count
	_more_menu.add_item("Next segment", 11)
	_more_menu.set_item_disabled(next_id, _next_button != null and _next_button.disabled)
	if not _graph_rail_fits():
		_more_menu.add_separator()
		_more_menu.add_item("Presets…", 12)
	_more_menu.popup_on_parent(Rect2(_more_button.size.x - 1.0, _more_button.size.y, 1.0, 1.0))


func _on_more_menu_id(index: int) -> void:
	match index:
		0, 1, 2, 3:
			_set_component(str(COMPONENTS[index]))
		10:
			_step_segment(-1)
		11:
			_step_segment(1)
		12:
			call_deferred("_open_presets_menu", _more_button)

# -------------------------------------------------------------------------
# Duration row
# -------------------------------------------------------------------------

## A 44 dp row that temporarily replaces the dope sheet when the duration chip
## is tapped. It is built before the sheet so the VBox keeps a stable order;
## only one of the two is ever visible.
func _build_duration_row() -> void:
	_duration_row = PanelContainer.new()
	_duration_row.custom_minimum_size.y = 44
	_duration_row.visible = false
	var style := Kit.flat_style(Kit.SURFACE_2, Kit.R_PANEL, Color(0, 0, 0, 0), 0)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	_duration_row.add_theme_stylebox_override("panel", style)
	add_child(_duration_row)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_duration_row.add_child(row)

	_duration_field = NumberFieldScript.new()
	_duration_field.axis = "S"
	_duration_field.suffix = " s"
	_duration_field.min_value = 0.25
	_duration_field.max_value = 3600.0
	_duration_field.step = 1.0
	_duration_field.tooltip_text = "Active clip length in seconds"
	_duration_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_duration_field.text_committed.connect(func(value: float) -> void:
		request_duration(value)
	)
	row.add_child(_duration_field)

	_match_button = Kit.text_button("Match sequence", "", false, true)
	_match_button.tooltip_text = "Match the longer sequence length"
	_match_button.add_theme_font_size_override("font_size", Kit.TYPE_CAPTION)
	_match_button.pressed.connect(func() -> void:
		if doc != null:
			request_duration(doc.sequence_duration())
	)
	row.add_child(_match_button)

	_extend_button = Kit.text_button("Extend +1 s", "", false, true)
	_extend_button.tooltip_text = "Extend the clip by one second"
	_extend_button.add_theme_font_size_override("font_size", Kit.TYPE_CAPTION)
	_extend_button.pressed.connect(func() -> void:
		if doc != null:
			request_duration(doc.duration + 1.0)
	)
	row.add_child(_extend_button)

	_duration_close_button = Kit.icon_button("chevron-down", "Close the duration row", 44, 16)
	_duration_close_button.pressed.connect(close_duration_row)
	row.add_child(_duration_close_button)


## The chip always names the active clip, and keeps a longer sequence clock
## visibly distinct instead of pretending the dope sheet covers it.
func duration_chip_text() -> String:
	if doc == null:
		return "0 s"
	var text := _seconds_text(doc.duration)
	var sequence := doc.sequence_duration()
	if sequence > doc.duration + 0.05:
		text += " · Seq " + _seconds_text(sequence)
	return text


func _seconds_text(value: float) -> String:
	var text := "%.2f" % maxf(0.0, value)
	text = text.rstrip("0").rstrip(".")
	return text + " s"


func duration_chip() -> Button:
	return _duration_chip


func duration_row_visible() -> bool:
	return _duration_open


func open_duration_row() -> void:
	if doc == null:
		return
	if _duration_open:
		close_duration_row()
		return
	_duration_open = true
	_duration_row.visible = true
	_dismiss_gesture_hint()
	_sync_body_visibility()
	_sync_duration_row()
	_refresh_layout()
	duration_row_changed.emit(true)


func close_duration_row() -> void:
	if not _duration_open:
		return
	_duration_open = false
	_duration_row.visible = false
	_sync_body_visibility()
	_refresh_layout()
	duration_row_changed.emit(false)


func _sync_duration_row() -> void:
	if doc == null:
		return
	if _duration_field != null:
		_duration_field.set_value_silent(doc.duration)
	if _match_button != null:
		_match_button.visible = doc.sequence_duration() > doc.duration + 0.05
	if _duration_chip != null:
		_duration_chip.text = duration_chip_text()
		_duration_chip.tooltip_text = _duration_chip.text
		var chip_font := _duration_chip.get_theme_font("font")
		var chip_size := _duration_chip.get_theme_font_size("font_size")
		var text_width := chip_font.get_string_size(
			_duration_chip.text, HORIZONTAL_ALIGNMENT_LEFT, -1, chip_size).x
		_duration_chip.custom_minimum_size.x = maxf(56.0, ceilf(text_width) + 8.0)
		_duration_chip.custom_minimum_size.y = TRANSPORT_H


## Applies a duration request. A shrink that would delete keys asks the editor
## for confirmation first and leaves the document untouched until it runs.
func request_duration(value: float) -> bool:
	if doc == null:
		return false
	var target := clampf(value, 0.25, 3600.0)
	if _would_delete_keys(target):
		duration_confirmation_requested.emit(target,
			"Shortening the clip to %s deletes keys after that point." % _seconds_text(target))
		return false
	apply_duration(target)
	return true


func apply_duration(value: float) -> void:
	if doc == null:
		return
	doc.set_duration(clampf(value, 0.25, 3600.0))
	_sync_duration_row()
	if _sheet != null:
		_sheet.queue_redraw()


func _would_delete_keys(value: float) -> bool:
	if doc == null or doc.animation == null:
		return false
	for track in range(doc.animation.get_track_count()):
		for index in range(doc.animation.track_get_key_count(track)):
			if doc.animation.track_get_key_time(track, index) > value + 0.0001:
				return true
	return false

# -------------------------------------------------------------------------
# Body
# -------------------------------------------------------------------------

func _build_sheet() -> void:
	_sheet_rule = Kit.vsep(Kit.BORDER_SOFT)
	add_child(_sheet_rule)
	_sheet = DopeSheet.new()
	_sheet.timeline = self
	_sheet.custom_minimum_size.y = 96
	_sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_sheet)

	# One-time hint at the top of the sheet itself, so it survives the compact
	# header folding away. The outline keeps it legible over the ruler without
	# adding another permanent row to the 44 dp ruler.
	_gesture_hint = Kit.label("Pinch to zoom · drag to pan", Kit.TYPE_CAPTION, Kit.TEXT, 500)
	_gesture_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_gesture_hint.offset_left = 8
	_gesture_hint.offset_right = -8
	_gesture_hint.offset_top = 2
	_gesture_hint.offset_bottom = 40
	_gesture_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gesture_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gesture_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gesture_hint.add_theme_color_override("font_outline_color", Kit.SURFACE)
	_gesture_hint.add_theme_constant_override("outline_size", 4)
	_gesture_hint.visible = false
	_sheet.add_child(_gesture_hint)


## The graph body is a sibling of the dope sheet in the same stacked body slot:
## exactly one of them is visible, so the VBox never allocates half a pane to a
## hidden editor.
func _build_segment_graph() -> void:
	_segment_graph = SegmentGraphScript.new()
	_segment_graph.custom_minimum_size.y = 120
	_segment_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_segment_graph.visible = false
	add_child(_segment_graph)
	_segment_graph.span_selected.connect(_on_graph_span_selected)
	_segment_graph.span_changed.connect(_on_graph_span_changed)
	_segment_graph.notice.connect(func(text: String) -> void: notice.emit(text))


func _sync_body_visibility() -> void:
	var body_visible := _sheet_open and not _duration_open
	if _sheet_rule != null:
		_sheet_rule.visible = body_visible
	if _sheet != null:
		_sheet.visible = body_visible and _mode != "graph"
	if _segment_graph != null:
		_segment_graph.visible = body_visible and _mode == "graph"


func segment_graph() -> Control:
	return _segment_graph


func segment_selected_span() -> Dictionary:
	return _selected_span.duplicate(true)


func selected_span() -> Dictionary:
	return _selected_span.duplicate(true)


func dope_sheet_visible() -> bool:
	return _sheet != null and _sheet.visible


func _on_graph_span_selected(span: Dictionary) -> void:
	_apply_span_selection(span, true, false)


func _on_graph_span_changed() -> void:
	_sync_header_state()
	if _sheet != null:
		_sheet.queue_redraw()


func _apply_span_selection(span: Dictionary, emit_change := true, sync_graph := true) -> void:
	_selected_span = span.duplicate(true) if not span.is_empty() else {}
	if _selected_span.is_empty():
		_selected_index = -1
		_selected_data_id = ""
	else:
		var start := float(_selected_span.get("start", 0.0))
		_selected_index = _key_index_at(start)
		_selected_data_id = doc.selected_id if doc != null else ""
	if sync_graph and _segment_graph != null:
		if _selected_span.is_empty():
			_segment_graph.clear_selection()
		else:
			_segment_graph.set_selection(_selected_span)
	_refresh_transport(doc.current_time, doc.is_playing) if doc != null else null
	_sync_segment_nav()
	_sync_segment_label()
	if _sheet != null:
		_sheet.queue_redraw()
	if emit_change:
		segment_selected.emit(span.duplicate(true))


func _key_index_at(time: float) -> int:
	if doc == null or doc.selected_id == "":
		return -1
	var keys: Array = doc.get_channel_keys(doc.selected_id, _selected_channel)
	for key in keys:
		if absf(float(key["time"]) - time) <= 0.001:
			return int(key["index"])
	return -1


func select_span_at_time(time: float) -> bool:
	if doc == null or doc.selected_id == "":
		return false
	var span: Dictionary = doc.segment_span_at(
		doc.selected_id, _selected_channel, clampf(time, 0.0, doc.duration))
	if span.is_empty():
		return false
	_apply_span_selection(span, true, true)
	return true


func select_segment_at_time(time: float) -> bool:
	return select_span_at_time(time)


func _step_segment(direction: int) -> void:
	if doc == null or doc.selected_id == "":
		return
	var start := doc.current_time
	if not _selected_span.is_empty() \
			and str(_selected_span.get("object", "")) == doc.selected_id \
			and str(_selected_span.get("channel", "")) == _selected_channel:
		start = float(_selected_span.get("start", start))
	else:
		var current: Dictionary = doc.segment_span_at(doc.selected_id, _selected_channel, start)
		if not current.is_empty():
			start = float(current.get("start", start))
	var span: Dictionary = doc.next_segment_span(doc.selected_id, _selected_channel, start, direction)
	if span.is_empty():
		return
	_apply_span_selection(span, true, true)


## Re-resolves the selection against the live document. A missing exact span
## falls back to the interval containing the playhead, then clears.
func _resolve_current_span() -> Dictionary:
	if doc == null or _selected_span.is_empty() or doc.selected_id == "":
		return {}
	if str(_selected_span.get("object", "")) != doc.selected_id \
			or str(_selected_span.get("channel", "")) != _selected_channel:
		return {}
	var start := float(_selected_span.get("start", 0.0))
	var end := float(_selected_span.get("end", 0.0))
	var candidate: Dictionary = doc.segment_span_at(
		doc.selected_id, _selected_channel, start + 0.000001)
	if not candidate.is_empty() \
			and absf(float(candidate.get("start", 0.0)) - start) <= 0.001 \
			and absf(float(candidate.get("end", 0.0)) - end) <= 0.001:
		return candidate
	return doc.segment_span_at(doc.selected_id, _selected_channel, doc.current_time)


func _sync_segment_nav() -> void:
	if _prev_button == null or _next_button == null:
		return
	var has_object := doc != null and doc.selected_id != ""
	var prev_span: Dictionary = {}
	var next_span: Dictionary = {}
	if has_object:
		var start := doc.current_time
		if not _selected_span.is_empty():
			start = float(_selected_span.get("start", start))
		prev_span = doc.next_segment_span(doc.selected_id, _selected_channel, start, -1)
		next_span = doc.next_segment_span(doc.selected_id, _selected_channel, start, 1)
	_prev_button.disabled = prev_span.is_empty()
	_next_button.disabled = next_span.is_empty()
	_prev_button.tooltip_text = "Previous segment" if not _prev_button.disabled \
		else ("No previous segment." if has_object else "Select an object first.")
	_next_button.tooltip_text = "Next segment" if not _next_button.disabled \
		else ("No next segment." if has_object else "Select an object first.")


func _sync_segment_label() -> void:
	if _segment_label == null:
		return
	if _selected_span.is_empty():
		_segment_label.text = "No segment selected"
		_segment_label.tooltip_text = ""
		return
	var start := float(_selected_span.get("start", 0.0))
	var end := float(_selected_span.get("end", 0.0))
	var kind := "Curve" if str(_selected_span.get("kind", "")) == "record" else "Keys"
	_segment_label.text = "%s · %.2f → %.2f s" % [kind, start, end]
	_segment_label.tooltip_text = _segment_label.text

# -------------------------------------------------------------------------
# Header and layout state
# -------------------------------------------------------------------------

func pane_compacted() -> bool:
	return size.y < 400.0 and _measured_width() >= 600.0


func _measured_width() -> float:
	var width := size.x
	if _available_width > 0.0:
		width = minf(width, _available_width) if width > 0.0 else _available_width
	return width


func _graph_header_height() -> float:
	if pane_compacted():
		return 0.0
	return 88.0 if _measured_width() < 600.0 else HEADER_H


func _pane_header_height() -> float:
	if pane_compacted():
		return HEADER_H
	if _pane_header_panel != null and _pane_header_panel.visible:
		return HEADER_H
	return 0.0


func _graph_body_height() -> float:
	var header := _pane_header_height()
	if _mode == "graph" and not pane_compacted():
		header += _graph_header_height()
	return maxf(0.0, size.y - TRANSPORT_H - header)


func _graph_rail_fits() -> bool:
	var body := _graph_body_height()
	return body - SegmentGraphScript.RULER_H - SegmentGraphScript.RAIL_H \
		>= SegmentGraphScript.MIN_PLOT_H


func plot_height() -> float:
	if _mode == "graph" and _segment_graph != null:
		return _segment_graph.plot_rect().size.y
	var rule_h := 0.0
	if _sheet_rule != null and _sheet_rule.visible:
		rule_h = maxf(0.0, _sheet_rule.custom_minimum_size.y)
	return maxf(0.0, size.y - TRANSPORT_H - _pane_header_height() - rule_h - DOPE_RULER_H)


func _refresh_layout() -> void:
	if _transport_panel == null:
		return
	var measured := _measured_width()
	var compacted := pane_compacted()
	if _pane_header_panel != null:
		_pane_header_panel.visible = not compacted
	if _merged_header_panel != null:
		_merged_header_panel.visible = compacted
	if _graph_header_panel != null:
		_graph_header_panel.visible = not compacted and _mode == "graph"
	var narrow := measured < 600.0
	if _graph_header_wide != null:
		_graph_header_wide.visible = not narrow
	if _graph_header_narrow != null:
		_graph_header_narrow.visible = narrow
	if _segment_label != null:
		_segment_label.visible = not compacted and not narrow
	if _dope_tab != null:
		_dope_tab.visible = not compacted
	if _graph_tab != null:
		_graph_tab.visible = not compacted
	if _clip_selector != null:
		_clip_selector.visible = not compacted
	if _prev_button != null:
		_prev_button.visible = not compacted
	if _next_button != null:
		_next_button.visible = not compacted

	# The transport drops its lower-priority controls before the pane's
	# minimum width can push the centre column wider than the canvas.
	var hide_loop := measured < 560.0
	var hide_snap := measured < 460.0
	_loop_button.visible = not hide_loop
	_fps_button.visible = not hide_loop
	_snap_button.visible = not hide_snap
	_fit_button.visible = not hide_snap
	_time_button.custom_minimum_size.x = 76.0 if hide_snap else 96.0
	_transport_style.content_margin_left = 2 if measured < 420.0 else 4
	_transport_style.content_margin_right = 2 if measured < 420.0 else 4

	var host: HBoxContainer = _wide_tabs_host
	if compacted:
		host = _merged_tabs_host
	elif narrow:
		host = _narrow_tabs_host
	if _segment_graph != null and host != null:
		_segment_graph.bind_tab_buttons(host)

	var presets_shown := _mode == "graph" and not _graph_rail_fits()
	if _presets_button != null:
		_presets_button.visible = presets_shown
	if _narrow_presets_button != null:
		_narrow_presets_button.visible = presets_shown
	_sync_mode_buttons()
	_sync_component_chips()
	_sync_header_state()
	if _sheet != null:
		_sheet.queue_redraw()


func _sync_header_state() -> void:
	_sync_mode_buttons()
	_sync_component_chips()
	_sync_segment_nav()
	_sync_segment_label()
	if _clip_selector != null:
		_clip_selector.text = _clip_selector_text()
		_clip_selector.tooltip_text = _clip_selector.text
	var channel_text := _channel_selector_text()
	for button in [_wide_channel_button, _narrow_channel_button, _merged_channel_button]:
		if button != null:
			button.text = channel_text
			button.tooltip_text = channel_text


func _clip_selector_text() -> String:
	if doc == null or doc.animation_system == null:
		return "No clip"
	var clip: Dictionary = doc.animation_system.get_clip(doc.active_clip_id())
	var layer: Dictionary = doc.animation_system.get_layer(
		doc.animation_system.active_layer_id())
	var clip_name := str(clip.get("name", "Clip"))
	var layer_name := str(layer.get("name", "Layer"))
	return "%s · %s" % [clip_name, layer_name]


func _channel_selector_text() -> String:
	var channel := str(doc.CHANNEL_LABELS.get(_selected_channel, _selected_channel)) if doc != null \
		else _selected_channel.capitalize()
	if doc == null or doc.selected_id == "":
		return "No object · " + channel
	var obj: Dictionary = doc.get_object(doc.selected_id)
	return "%s · %s" % [str(obj.get("name", "Object")), channel]


func _sync_mode_buttons() -> void:
	_sync_flags = true
	if _dope_tab != null:
		_dope_tab.set_pressed_no_signal(_mode == "dope")
	if _graph_tab != null:
		_graph_tab.set_pressed_no_signal(_mode == "graph")
	if _merged_dope_tab != null:
		_merged_dope_tab.set_pressed_no_signal(_mode == "dope")
	if _merged_graph_tab != null:
		_merged_graph_tab.set_pressed_no_signal(_mode == "graph")
	_sync_flags = false


func clip_selector() -> Button:
	return _clip_selector


func segment_label() -> Label:
	return _segment_label


func dope_tab() -> Button:
	return _dope_tab


func graph_tab_button() -> Button:
	return _graph_tab


func prev_segment_button() -> Button:
	return _prev_button


func next_segment_button() -> Button:
	return _next_button


func pane_header() -> Control:
	return _merged_header_panel if pane_compacted() else _pane_header_panel


func graph_header() -> Control:
	return _merged_header_panel if pane_compacted() else _graph_header_panel


func transport_panel() -> Control:
	return _transport_panel


func play_button() -> Button:
	return _play_button


func fps_button() -> Button:
	return _fps_button


func snap_button() -> Button:
	return _snap_button


func add_key_button() -> Button:
	return _add_key_button


func delete_key_button() -> Button:
	return _delete_button


func time_button() -> Button:
	return _time_button


func fit_button() -> Button:
	return _fit_button


func set_available_width(value: float) -> void:
	_available_width = value
	_refresh_layout()


## Touch mode keeps every transport control on the 44 dp target. The icon
## inside may shrink; the target never does.
func set_chrome_mode(mode: String) -> void:
	_chrome_mode = mode if mode in ["compact", "studio", "desktop"] else "studio"
	var icon := 20 if _chrome_mode == "compact" else 18
	for button in _transport_buttons:
		if button == null or not is_instance_valid(button):
			continue
		button.custom_minimum_size = Vector2(44, 44)
		button.add_theme_constant_override("icon_max_width", icon)
	_refresh_layout()


func set_short_layout(value: bool) -> void:
	if _short_layout == value:
		return
	_short_layout = value
	if _sheet_rule != null:
		_sheet_rule.custom_minimum_size.y = 0.0 if _short_layout else 1.0
	_refresh_layout()


func set_sheet_visible(open: bool) -> void:
	_sheet_open = open
	if not open and _duration_open:
		_duration_open = false
		if _duration_row != null:
			_duration_row.visible = false
	_sync_body_visibility()
	if not open:
		_dismiss_gesture_hint()
	_refresh_layout()


## Called by the editor's user-open path, never from a layout sync. The hint
## lives on the sheet surface so it remains visible even when the compact
## header is folded, and only survives the first session open.
func show_gesture_hint_once() -> void:
	if _hint_seen or _gesture_hint == null or not _sheet_open:
		return
	_hint_seen = true
	_gesture_hint.visible = true


func gesture_hint_visible() -> bool:
	return _gesture_hint != null and _gesture_hint.visible


func _dismiss_gesture_hint() -> void:
	if _gesture_hint != null:
		_gesture_hint.visible = false


func sheet_visible() -> bool:
	return _sheet_open


func mode() -> String:
	return _mode


func set_mode(mode: String) -> void:
	var next := "graph" if mode == "graph" else "dope"
	var changed := next != _mode
	_mode = next
	_refresh_graph_context()
	if _segment_graph != null and not _selected_span.is_empty():
		_segment_graph.set_selection(_selected_span)
	_sync_body_visibility()
	_refresh_layout()
	_sync_header_state()
	if _sheet != null:
		_sheet.queue_redraw()
	if _segment_graph != null:
		_segment_graph.queue_redraw()
	if changed:
		mode_changed.emit(_mode)


func _refresh_graph_context() -> void:
	if _segment_graph != null and doc != null:
		_segment_graph.set_context(doc.selected_id, _selected_channel)


func _sync_flag_states() -> void:
	if doc == null:
		return
	_sync_flags = true
	_loop_button.set_pressed_no_signal(doc.loop)
	_snap_button.set_pressed_no_signal(doc.snap)
	_sync_flags = false
	_style_flag_button(_loop_button, doc.loop)
	_style_flag_button(_snap_button, doc.snap)


func _style_flag_button(button: Button, active: bool) -> void:
	if button == null:
		return
	if active:
		button.add_theme_color_override("icon_normal_color", Kit.FOCUS_BRIGHT)
		button.add_theme_color_override("icon_pressed_color", Kit.FOCUS_BRIGHT)
		button.add_theme_color_override("font_color", Kit.FOCUS_BRIGHT)
		button.add_theme_color_override("font_pressed_color", Kit.FOCUS_BRIGHT)
		button.add_theme_stylebox_override("normal",
			Kit.flat_style(Kit.SURFACE_ACTIVE, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	else:
		button.add_theme_color_override("icon_normal_color", Kit.TEXT_MUTED)
		button.add_theme_color_override("font_color", Kit.TEXT_MUTED)
		button.add_theme_stylebox_override("normal",
			Kit.flat_style(Color(0, 0, 0, 0), Kit.R_CONTROL, Color(0, 0, 0, 0), 0))


## The clip transport is disabled while the sequence clock owns time. The
## timeline owns the disabled flag and its reason so a playback refresh cannot
## overwrite the shell's tooltip.
func set_clip_transport_enabled(enabled: bool) -> void:
	_clip_transport_enabled = enabled
	_sync_play_control()


func clip_transport_enabled() -> bool:
	return _clip_transport_enabled


func _sync_play_control() -> void:
	if _play_button == null:
		return
	_play_button.disabled = not _clip_transport_enabled
	if not _clip_transport_enabled:
		_play_button.tooltip_text = "Stop the sequence first"
	else:
		var playing: bool = doc != null and doc.is_playing
		_play_button.tooltip_text = "Pause" if playing else "Play"


func _refresh_transport(time: float, playing: bool) -> void:
	if doc == null:
		return
	_time_button.text = doc.format_timecode(time)
	_fps_button.text = "%d fps" % doc.fps
	_play_button.icon = Kit.icon_texture("pause" if playing else "play")
	_play_button.set_meta("action_id", "pause" if playing else "play")
	_play_button.set_meta("action_icon", "pause" if playing else "play")
	_sync_play_control()
	var has_key := _selected_index >= 0 and _selected_data_id == doc.selected_id
	_delete_button.disabled = not has_key
	_sync_duration_row()


func _on_playback_changed(time: float, playing: bool) -> void:
	_follow_playhead()
	_refresh_transport(time, playing)
	if _sheet != null:
		_sheet.queue_redraw()


func _on_selection_changed(_id: String) -> void:
	_selected_index = -1
	_selected_data_id = ""
	_selected_span = {}
	if _segment_graph != null:
		_segment_graph.set_context(doc.selected_id, _selected_channel)
		_segment_graph.clear_selection()
	_sync_header_state()
	_refresh_transport(doc.current_time, doc.is_playing)
	if _sheet != null:
		_sheet.queue_redraw()


func _on_object_changed(_id: String) -> void:
	if _segment_graph != null:
		_segment_graph.refresh()
	_sync_header_state()
	if _sheet != null:
		_sheet.queue_redraw()


func _on_transform_changed(_id: String) -> void:
	# The sheet only plots keys and the playhead; live values do not redraw it.
	pass


func _on_keyframes_changed(_id: String) -> void:
	var resolved := _resolve_current_span()
	_selected_span = resolved
	if _selected_span.is_empty():
		_selected_index = -1
		_selected_data_id = ""
	else:
		_selected_index = _key_index_at(float(_selected_span.get("start", 0.0)))
		_selected_data_id = doc.selected_id if doc != null else ""
	if _segment_graph != null:
		_segment_graph.refresh()
		if _selected_span.is_empty():
			_segment_graph.clear_selection()
		else:
			_segment_graph.set_selection(_selected_span)
	_sync_header_state()
	_refresh_transport(doc.current_time, doc.is_playing)
	if _sheet != null:
		_sheet.queue_redraw()


func _on_scene_changed() -> void:
	_sync_flag_states()
	if _segment_graph != null:
		_segment_graph.refresh()
	_sync_header_state()
	_refresh_transport(doc.current_time, doc.is_playing)
	if _sheet != null:
		_sheet.queue_redraw()


func _on_active_clip_changed(_id: String) -> void:
	_selected_span = {}
	_selected_index = -1
	_selected_data_id = ""
	if _segment_graph != null:
		_segment_graph.set_context(doc.selected_id, _selected_channel)
		_segment_graph.clear_selection()
	_sync_header_state()
	_refresh_transport(doc.current_time, doc.is_playing)
	if _sheet != null:
		_sheet.queue_redraw()


func _on_prev_key() -> void:
	if doc == null:
		return
	doc.pause()
	doc.seek(doc.nearest_key_time(-1))


func _on_next_key() -> void:
	if doc == null:
		return
	doc.pause()
	doc.seek(doc.nearest_key_time(1))


func _on_play() -> void:
	if doc != null and _clip_transport_enabled:
		doc.toggle_play()


func _on_loop_toggled(enabled: bool) -> void:
	if _sync_flags or doc == null:
		return
	doc.set_loop(enabled)
	_style_flag_button(_loop_button, enabled)


func _on_snap_toggled(enabled: bool) -> void:
	if _sync_flags or doc == null:
		return
	doc.set_snap(enabled)
	_style_flag_button(_snap_button, enabled)


func _on_key_all() -> void:
	if doc == null:
		return
	if doc.selected_id == "":
		notice.emit("Select an object before inserting keys.")
		return
	doc.insert_transform_keys()
	notice.emit("Keys inserted at " + doc.format_timecode(doc.current_time))
	if _sheet != null:
		_sheet.queue_redraw()


func _on_delete_key() -> void:
	if doc == null or _selected_index < 0 or _selected_data_id != doc.selected_id:
		return
	var keys: Array = doc.get_channel_keys(doc.selected_id, _selected_channel)
	var old_time := doc.format_timecode(doc.current_time)
	if _selected_index < keys.size():
		old_time = doc.format_timecode(float(keys[_selected_index]["time"]))
	doc.delete_key(doc.selected_id, _selected_channel, _selected_index)
	_selected_index = -1
	_selected_data_id = ""
	_refresh_transport(doc.current_time, doc.is_playing)
	notice.emit("Key deleted at " + old_time)
	if _sheet != null:
		_sheet.queue_redraw()

# -------------------------------------------------------------------------
# Time viewport (pan and zoom)
# -------------------------------------------------------------------------

## Re-derives the viewport against the document. A duration change resets the
## window to the whole duration so the default view never hides keys.
func _normalize_view() -> void:
	if doc == null:
		return
	var duration := maxf(0.001, doc.duration)
	if _view_duration_seen != duration:
		_view_duration_seen = duration
		_view_start = 0.0
		_view_span = -1.0
	if _view_span <= 0.0:
		_view_start = 0.0
		return
	_view_span = clampf(_view_span, MIN_VIEW_SPAN, duration)
	_view_start = clampf(_view_start, 0.0, duration - _view_span)
	if is_equal_approx(_view_start, 0.0) and _view_span >= duration:
		_view_span = -1.0


func viewport_span() -> float:
	_normalize_view()
	if doc == null:
		return maxf(0.001, _view_span)
	return maxf(0.001, _view_span if _view_span > 0.0 else doc.duration)


func viewport_start() -> float:
	_normalize_view()
	return _view_start


func viewport_end() -> float:
	return viewport_start() + viewport_span()


## Visible window as seconds (`x` = start, `y` = end) for tests and sheets.
func time_view() -> Vector2:
	return Vector2(viewport_start(), viewport_end())


func set_time_view(start: float, end: float) -> void:
	if doc == null:
		return
	var duration := maxf(0.001, doc.duration)
	_view_duration_seen = duration
	var span := maxf(MIN_VIEW_SPAN, end - start)
	span = minf(span, duration)
	start = clampf(start, 0.0, duration - span)
	_view_start = start
	_view_span = span if span < duration - 0.0001 else -1.0
	if _sheet != null:
		_sheet.queue_redraw()


## The transport's Fit button: drop any zoom and show the whole clip.
func fit_time_view() -> void:
	if doc == null:
		return
	_view_duration_seen = doc.duration
	_view_start = 0.0
	_view_span = -1.0
	if _sheet != null:
		_sheet.queue_redraw()


## Pans the window by `delta` seconds. A full-duration view has nothing to
## pan, which is what keeps the default view stable.
func pan_time_view(delta: float) -> void:
	if doc == null or _normalize_or_full():
		return
	var lo := 0.0
	var hi: float = doc.duration - _view_span
	_view_start = clampf(_view_start + delta, lo, maxf(lo, hi))
	if _sheet != null:
		_sheet.queue_redraw()


func zoom_time_view(factor: float, anchor: float = -1.0) -> void:
	if doc == null:
		return
	_normalize_view()
	var span0 := _view_span if _view_span > 0.0 else doc.duration
	var span := clampf(span0 * factor, MIN_VIEW_SPAN, doc.duration)
	if anchor < 0.0:
		anchor = _view_start + span0 * 0.5
	var frac := (anchor - _view_start) / maxf(0.001, span0)
	_view_start = clampf(anchor - frac * span, 0.0, maxf(0.0, doc.duration - span))
	_view_span = span if span < doc.duration - 0.0001 else -1.0
	if _sheet != null:
		_sheet.queue_redraw()


## True when the window already covers the whole duration (nothing to pan).
func _normalize_or_full() -> bool:
	_normalize_view()
	return _view_span <= 0.0


## Keeps the playhead inside the window during playback and scrubs.
func _follow_playhead() -> void:
	if doc == null or _sheet == null or not _sheet.visible:
		return
	if _normalize_or_full():
		return
	var t := doc.current_time
	var end := viewport_end()
	if t < _view_start or t > end:
		_view_start = clampf(t - _view_span * 0.15, 0.0, maxf(0.0, doc.duration - _view_span))
		_sheet.queue_redraw()


## The track is painted even when the whole duration fits (the permanent
## affordance), so this only answers whether the sheet can show a scrollbar at
## all, not whether there is anything to pan.
func scrollbar_track_rect() -> Rect2:
	if _scrollbar_hidden():
		return Rect2()
	_normalize_view()
	var h := _sheet.size.y if _sheet != null else 0.0
	var thumb_h := SCROLLBAR_TRACK_H
	return Rect2(_grid_left, h - thumb_h - 4.0, _grid_width, thumb_h)


func _scrollbar_hidden() -> bool:
	if doc == null or _sheet == null or not _sheet.is_visible_in_tree():
		return true
	return false


## True while the visible window is narrower than the clip, i.e. there is
## something to pan. The thumb and its drag band only own input then.
func _view_pannable() -> bool:
	return not _normalize_or_full()


func scrollbar_caption() -> String:
	return "Drag to pan" if _view_pannable() else "Fit · pinch to zoom"


func scrollbar_thumb_rect() -> Rect2:
	var track := scrollbar_track_rect()
	if track.size.x <= 0.0:
		return Rect2()
	var t0 := _view_start / maxf(0.001, doc.duration)
	var t1 := viewport_end() / maxf(0.001, doc.duration)
	var width := maxf(20.0, (t1 - t0) * track.size.x)
	var x0 := track.position.x + t0 * track.size.x
	x0 = clampf(x0, track.position.x, track.end.x - width)
	return Rect2(x0, track.position.y, width, track.size.y)


## The whole bottom band is the 44 dp touch target; only the slim thumb is
## painted so the hit area stays generous without adding visual weight.
func scrollbar_hit_rect() -> Rect2:
	if _sheet == null:
		return Rect2()
	var h := _sheet.size.y
	return Rect2(0.0, h - SCROLLBAR_HIT, _sheet.size.x, SCROLLBAR_HIT)


# Debug/testing hook: map a press to whether the scrollbar owns it. In fit
# mode the track is visible but there is nothing to pan, so it owns nothing.
func scrollbar_owns_press(pos: Vector2) -> bool:
	if _scrollbar_hidden() or not _view_pannable():
		return false
	var hit := scrollbar_hit_rect()
	if not hit.has_point(pos):
		return false
	var thumb := scrollbar_thumb_rect()
	var band := Rect2(thumb.position.x - 8.0, hit.position.y, thumb.size.x + 16.0, hit.size.y)
	return band.has_point(pos)

# -------------------------------------------------------------------------
# Dope sheet drawing
# -------------------------------------------------------------------------

func _geometry(canvas: Control) -> void:
	_ruler_h = DOPE_RULER_H
	_label_width = 92.0 if canvas.size.x < 500.0 else 112.0
	var available_h := maxf(60.0, canvas.size.y - _ruler_h - 6.0)
	_row_h = clampf(available_h / 3.0, 20.0, 34.0)
	_grid_left = _label_width + 6.0
	_grid_width = maxf(20.0, canvas.size.x - _grid_left - 8.0)


func _time_to_x(time: float, _canvas: Control) -> float:
	if doc == null:
		return _grid_left
	return _grid_left + (time - viewport_start()) / viewport_span() * _grid_width


func _x_to_time(x: float, _canvas: Control) -> float:
	return viewport_start() + (x - _grid_left) / maxf(1.0, _grid_width) * viewport_span()


func _draw_sheet(canvas: Control) -> void:
	_geometry(canvas)
	_key_hits.clear()
	var w := canvas.size.x
	var h := canvas.size.y
	canvas.draw_rect(Rect2(0, 0, w, h), Kit.SURFACE)
	canvas.draw_rect(Rect2(0, 0, w, _ruler_h), Kit.SURFACE_2)
	canvas.draw_line(Vector2(_label_width, 0), Vector2(_label_width, h), Kit.BORDER_SOFT, 1.0)
	canvas.draw_line(Vector2(0, _ruler_h), Vector2(w, _ruler_h), Kit.BORDER_SOFT, 1.0)
	canvas.draw_string(Kit.font_for(600), Vector2(12, 27), "CHANNELS",
		HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.TYPE_CAPTION, Kit.TEXT_DIM)

	if doc == null:
		return

	var major := _major_step()
	# Ticks span the visible window, not the whole duration: a zoomed window
	# still gets labels at the right times without drawing off-canvas.
	var first_tick := floorf(viewport_start() / major) * major
	var tick := first_tick
	while tick <= viewport_end() + 0.001:
		if tick >= -0.001 and tick <= doc.duration + 0.001:
			var x := _time_to_x(tick, canvas)
			canvas.draw_line(Vector2(x, 0), Vector2(x, h),
				Kit.BORDER_SOFT * Color(1, 1, 1, 0.55), 1.0)
			if x < w - 26.0:
				var label := "%.1fs" % tick if major < 1.0 else "%ds" % int(round(tick))
				canvas.draw_string(Kit.font_mono, Vector2(x + 3, 27), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.TYPE_RULER, Kit.TEXT_MUTED)
		tick += major

	var row_top := _ruler_h
	var channels: Array = doc.CHANNELS
	for ci in range(channels.size()):
		var channel := str(channels[ci])
		var top := row_top + float(ci) * _row_h
		var center_y := top + _row_h * 0.5
		if channel == _selected_channel:
			canvas.draw_rect(Rect2(0, top, w, _row_h), Kit.SURFACE_ACTIVE)
			canvas.draw_rect(Rect2(0, top, CHANNEL_EDGE, _row_h), Kit.ACCENT)
		elif ci % 2 == 1:
			canvas.draw_rect(Rect2(_label_width, top, w - _label_width, _row_h),
				Kit.SURFACE * Color(1, 1, 1, 0.35))
		canvas.draw_line(Vector2(0, top + _row_h), Vector2(w, top + _row_h), Kit.BORDER_SOFT, 1.0)

		var label := str(doc.CHANNEL_LABELS.get(channel, channel))
		canvas.draw_string(Kit.font_for(500), Vector2(20, center_y + 4), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.TYPE_CAPTION,
			Kit.TEXT if channel == _selected_channel else Kit.TEXT_MUTED)
		# Channel identity lives in the label. Coloured dots would introduce a
		# second semantic palette into an otherwise luminance-only workbench.
		var dot_color: Color = [Kit.TEXT_MUTED, Kit.TEXT_DIM, Kit.BORDER][ci]
		canvas.draw_circle(Vector2(12, center_y), 2.4, dot_color)

		var keys: Array = doc.get_channel_keys(doc.selected_id, channel) if doc.selected_id != "" else []
		if keys.is_empty():
			continue
		var count_text := str(keys.size())
		var count_size := Kit.font_mono.get_string_size(
			count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.TYPE_MONO)
		canvas.draw_string(Kit.font_mono,
			Vector2(_label_width - 10 - count_size.x, center_y + 3), count_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.TYPE_MONO, Kit.TEXT_DIM)

	_draw_selected_band(canvas, row_top, w)

	for ci in range(channels.size()):
		var channel := str(channels[ci])
		var center_y := row_top + float(ci) * _row_h + _row_h * 0.5
		var keys: Array = doc.get_channel_keys(doc.selected_id, channel) if doc.selected_id != "" else []
		for key in keys:
			if key["time"] > doc.duration + 0.001:
				continue
			var x := _time_to_x(float(key["time"]), canvas)
			var selected := _selected_data_id == doc.selected_id \
				and _selected_index == int(key["index"]) and _selected_channel == channel
			var r := 6.0 if selected else 4.6
			var color := Kit.ACCENT_BRIGHT if selected else Kit.ACCENT
			var points := PackedVector2Array([
				Vector2(x, center_y - r), Vector2(x + r, center_y),
				Vector2(x, center_y + r), Vector2(x - r, center_y),
			])
			canvas.draw_colored_polygon(points, color)
			if selected:
				canvas.draw_polyline(PackedVector2Array([
					points[0], points[1], points[2], points[3], points[0],
				]), Color(1, 1, 1, 0.85), 1.0, true)
			_key_hits.append({"channel": channel, "index": int(key["index"]), "pos": Vector2(x, center_y)})

	var play_x := _time_to_x(doc.current_time, canvas)
	canvas.draw_line(Vector2(play_x, 0), Vector2(play_x, h), Kit.ACCENT * Color(1, 1, 1, 0.75), 1.2)
	var head := PackedVector2Array([Vector2(play_x - 4, 0), Vector2(play_x + 4, 0), Vector2(play_x, 5)])
	canvas.draw_colored_polygon(head, Kit.ACCENT)

	if doc.selected_id == "":
		canvas.draw_string(Kit.font_for(400), Vector2(_label_width + 20, _ruler_h + 32),
			"Select an object to view its animation channels.",
			HORIZONTAL_ALIGNMENT_LEFT, w - _label_width - 24, Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	else:
		var rows_bottom := row_top + float(channels.size()) * _row_h
		if h > rows_bottom + 12.0:
			canvas.draw_string(Kit.font_for(400), Vector2(_label_width + 8, rows_bottom + 14),
				"Drag diamonds to retime · tap a band to select its segment",
				HORIZONTAL_ALIGNMENT_LEFT, w - _label_width - 16, Kit.TYPE_CAPTION, Kit.TEXT_DIM)

	_draw_scrollbar(canvas, w, h)


func _draw_selected_band(canvas: Control, row_top: float, w: float) -> void:
	if _selected_span.is_empty() or doc == null:
		return
	if str(_selected_span.get("object", "")) != doc.selected_id \
			or str(_selected_span.get("channel", "")) != _selected_channel:
		return
	var x0 := _time_to_x(float(_selected_span.get("start", 0.0)), canvas)
	var x1 := _time_to_x(float(_selected_span.get("end", 0.0)), canvas)
	var left := maxf(_grid_left, minf(x0, x1))
	var right := minf(w, maxf(x0, x1))
	if right <= left:
		return
	var height := _row_h * float(doc.CHANNELS.size())
	canvas.draw_rect(Rect2(left, row_top, right - left, height), Kit.TIME_DARK)


## The sheet draws its own slim horizontal scrollbar: a thin thumb over a
## faint track, with a full 44 dp hit band so fingers can grab either. Fit mode
## keeps the track and a 40% thumb as a permanent affordance and captions the
## pinch gesture; a zoomed window gets the normal thumb and drag caption.
func _draw_scrollbar(canvas: Control, _w: float, _h: float) -> void:
	var track := scrollbar_track_rect()
	if track.size.x <= 0.0:
		return
	canvas.draw_rect(Rect2(track.position.x, track.position.y - 2.0, track.size.x, track.size.y + 4.0),
		Kit.SURFACE * Color(1.0, 1.0, 1.0, 0.55))
	var pannable := _view_pannable()
	var thumb := scrollbar_thumb_rect()
	var thumb_color := Kit.ACCENT if _scroll_dragging else Kit.TEXT_DIM
	if not pannable:
		thumb_color = Kit.TEXT_DIM * Color(1.0, 1.0, 1.0, 0.4)
	canvas.draw_rect(thumb, thumb_color)
	var caption := scrollbar_caption()
	var caption_size := Kit.font_for(400).get_string_size(
		caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var caption_x := maxf(track.position.x, track.end.x - caption_size)
	canvas.draw_string(Kit.font_for(400), Vector2(caption_x, track.position.y - 4.0),
		caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Kit.TEXT_DIM)


func _major_step() -> float:
	var px_per_second := _grid_width / viewport_span()
	var candidates := [0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 60.0, 120.0, 300.0, 600.0]
	for value in candidates:
		if float(value) * px_per_second >= 46.0:
			return float(value)
	return 600.0

# -------------------------------------------------------------------------
# Channel selection
# -------------------------------------------------------------------------

func set_channel(channel: String) -> void:
	if doc == null or not (channel in doc.CHANNELS):
		return
	var changed := channel != _selected_channel
	_selected_channel = channel
	_selected_index = -1
	_selected_data_id = ""
	_selected_span = {}
	# The hit rects describe the previous channel until the next draw. A tap
	# between the switch and that draw must not select a stale segment or key.
	_channel_hits.clear()
	_key_hits.clear()
	if _segment_graph != null:
		_segment_graph.set_context(doc.selected_id, _selected_channel)
		_segment_graph.clear_selection()
	_sync_header_state()
	_refresh_transport(doc.current_time, doc.is_playing)
	if _sheet != null:
		_sheet.queue_redraw()
	if changed:
		channel_selected.emit(channel)


func channel() -> String:
	return _selected_channel

# -------------------------------------------------------------------------
# Dope sheet interaction
# -------------------------------------------------------------------------

func _sheet_input(event: InputEvent, canvas: Control) -> void:
	if doc == null:
		return
	if Kit.is_emulated_mouse(event):
		return
	if (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) or \
		(event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed):
		_dismiss_gesture_hint()
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			if button.pressed:
				_wheel_time_view(button)
				canvas.accept_event()
			return
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_press_sheet(button.position, canvas)
		else:
			_release_sheet(button.position)
		canvas.accept_event()
	elif event is InputEventMouseMotion and (_scrubbing or _dragging_key or _scroll_dragging):
		_drag_sheet((event as InputEventMouseMotion).position, canvas)
		canvas.accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _touches.is_empty():
				_snapshot_gesture_state()
			_touches[int(touch.index)] = touch.position
			if _touches.size() >= 2:
				_start_view_gesture()
			else:
				_press_sheet(touch.position, canvas)
		else:
			_touches.erase(int(touch.index))
			if _touches.size() < 2:
				if _panning_view:
					_panning_view = false
				_pinch_dist = -1.0
			if _touches.is_empty():
				_gesture_active = false
				_release_sheet(touch.position)
		canvas.accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _touches.has(int(drag.index)):
			_touches[int(drag.index)] = drag.position
		if _panning_view:
			_update_view_gesture()
			canvas.accept_event()
			return
		_drag_sheet(drag.position, canvas)
		canvas.accept_event()


## Shift+wheel pans the window horizontally; plain wheel zooms around the
## cursor. Horizontal wheel buttons pan too, for trackpads that send them.
func _wheel_time_view(button: InputEventMouseButton) -> void:
	var span := viewport_span()
	var horizontal := button.shift_pressed or button.button_index in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
	if horizontal:
		var dir := 1.0
		if button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT]:
			dir = -1.0
		pan_time_view(dir * span * 0.2)
	else:
		# Wheel up zooms in, wheel down zooms out; the anchor stays under the
		# cursor so the time beneath the pointer does not jump.
		var factor := 1.0 / 1.15 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.15
		zoom_time_view(factor, _x_to_time(button.position.x, _sheet))


func _snapshot_gesture_state() -> void:
	if doc == null:
		return
	_gesture_active = true
	_gesture_time_snapshot = doc.current_time
	_gesture_playing_snapshot = doc.is_playing
	_gesture_edit_snapshot = doc.has_open_edit()
	_gesture_view_snapshot = time_view()


## A second finger always starts the view gesture. Anything the first touch
## began (scrub, key retime) is rolled back to the snapshot taken before that
## touch, including an edit transaction the press opened. A pre-existing edit
## is never ended or cancelled here.
func _start_view_gesture() -> void:
	_scroll_dragging = false
	_scrubbing = false
	_dragging_key = false
	if doc != null:
		if not _gesture_edit_snapshot and doc.has_open_edit():
			doc.cancel_edit()
		if _gesture_active:
			doc.seek(_gesture_time_snapshot)
			if _gesture_playing_snapshot:
				doc.play()
			# Restoring the playhead must not move the window the user is about
			# to pan: put the exact snapshot window back after the seek.
			set_time_view(_gesture_view_snapshot.x, _gesture_view_snapshot.y)
	_gesture_active = false
	var indexes := _touches.keys()
	if indexes.size() < 2:
		return
	var p0: Vector2 = _touches[indexes[0]]
	var p1: Vector2 = _touches[indexes[1]]
	_panning_view = true
	_pinch_dist = p0.distance_to(p1)
	_pan_last_mid = (p0 + p1) * 0.5
	if _sheet != null:
		_sheet.queue_redraw()


func _update_view_gesture() -> void:
	var indexes := _touches.keys()
	if indexes.size() < 2:
		return
	var p0: Vector2 = _touches[indexes[0]]
	var p1: Vector2 = _touches[indexes[1]]
	var mid := (p0 + p1) * 0.5
	var dx := mid.x - _pan_last_mid.x
	_pan_last_mid = mid
	if absf(dx) >= 0.5:
		pan_time_view(-dx / maxf(1.0, _grid_width) * viewport_span())
	var dist := p0.distance_to(p1)
	if _pinch_dist > 4.0 and dist > 4.0:
		var anchor := _x_to_time(mid.x, _sheet)
		zoom_time_view(_pinch_dist / dist, anchor)
	_pinch_dist = dist


func button_mask_down() -> bool:
	return _scrubbing or _dragging_key


func _press_sheet(pos: Vector2, canvas: Control) -> void:
	_geometry(canvas)
	# The scrollbar band owns its thumb drag and its track tap while there is
	# something to pan. Keys keep a chance to win first so a diamond at the
	# bottom row stays grabbable. The ruler always wins: a touch on the ruler
	# must scrub (and pause) rather than silently pan the window.
	if _view_pannable() and pos.y > _ruler_h and scrollbar_hit_rect().has_point(pos) and _key_at(pos) < 0:
		var thumb: Rect2 = scrollbar_thumb_rect()
		if pos.x >= thumb.position.x - 8.0 and pos.x <= thumb.end.x + 8.0:
			_scroll_dragging = true
			_scroll_grab_x = pos.x - thumb.position.x
		else:
			# A track tap centers the window under the finger, then drags.
			_scroll_dragging = true
			_scroll_grab_x = thumb.size.x * 0.5
			_scroll_follow_track(pos.x)
		canvas.queue_redraw()
		return
	_selected_data_id = doc.selected_id
	if doc.selected_id == "":
		return
	if pos.y <= _ruler_h or pos.x < _label_width:
		if pos.y > _ruler_h and pos.x < _label_width:
			var ci := int(floor((pos.y - _ruler_h) / maxf(1.0, _row_h)))
			if ci >= 0 and ci < doc.CHANNELS.size():
				# The full 44 dp channel row is the target, not just the label.
				set_channel(str(doc.CHANNELS[ci]))
			return
		_scrubbing = true
		if doc.is_playing:
			doc.pause()
		doc.seek(clampf(_x_to_time(pos.x, canvas), 0.0, doc.duration))
		_follow_playhead()
		canvas.queue_redraw()
		return
	var hit := _key_at(pos)
	var time := clampf(_x_to_time(pos.x, canvas), 0.0, doc.duration)
	if hit >= 0:
		var data: Dictionary = _key_hits[hit]
		_selected_channel = str(data["channel"])
		select_span_at_time(float(data["time"])) if data.has("time") else select_span_at_time(time)
		_selected_index = int(data["index"])
		_selected_data_id = doc.selected_id
		_dragging_key = true
		doc.begin_edit("Retime key")
		_refresh_transport(doc.current_time, doc.is_playing)
		canvas.queue_redraw()
		return
	var ci := int(floor((pos.y - _ruler_h) / maxf(1.0, _row_h)))
	if ci >= 0 and ci < doc.CHANNELS.size():
		set_channel(str(doc.CHANNELS[ci]))
	select_span_at_time(time)
	_selected_index = -1
	_refresh_transport(doc.current_time, doc.is_playing)
	_scrubbing = true
	if doc.is_playing:
		doc.pause()
	doc.seek(time)
	_follow_playhead()
	canvas.queue_redraw()


## Maps a scrollbar drag to a window start. The grab offset keeps the finger
## anchored to the thumb instead of snapping it to the cursor.
func _scroll_follow_track(x: float) -> void:
	if doc == null or _normalize_or_full():
		return
	var track := scrollbar_track_rect()
	var frac := clampf((x - _scroll_grab_x - track.position.x) / maxf(1.0, track.size.x), 0.0, 1.0)
	var span := viewport_span()
	var start := clampf(frac * (doc.duration - span), 0.0, maxf(0.0, doc.duration - span))
	set_time_view(start, start + span)


func _drag_sheet(pos: Vector2, canvas: Control) -> void:
	if _scroll_dragging:
		_scroll_follow_track(pos.x)
		canvas.queue_redraw()
		return
	if doc.selected_id == "":
		return
	if _dragging_key and _selected_index >= 0:
		var key_index := _selected_index
		var key_data_id := _selected_data_id
		var key_channel := _selected_channel
		var t := clampf(_x_to_time(pos.x, canvas), 0.0, doc.duration)
		var index := doc.set_key_time(key_data_id, key_channel, key_index, t)
		_restore_selection(index if index >= 0 else key_index, key_data_id, key_channel)
	elif _scrubbing:
		doc.seek(clampf(_x_to_time(pos.x, canvas), 0.0, doc.duration))
		_follow_playhead()
		canvas.queue_redraw()


func _release_sheet(_pos: Vector2) -> void:
	_scroll_dragging = false
	if _dragging_key:
		_dragging_key = false
		doc.end_edit()
		if _selected_index >= 0 and doc.selected_id != "":
			var keys: Array = doc.get_channel_keys(doc.selected_id, _selected_channel)
			if _selected_index < keys.size():
				notice.emit("Key at " + doc.format_timecode(float(keys[_selected_index]["time"])))
	_scrubbing = false
	if _sheet != null:
		_sheet.queue_redraw()


func _restore_selection(index: int, data_id: String, channel: String) -> void:
	_selected_index = index
	_selected_data_id = data_id
	_selected_channel = channel
	_refresh_transport(doc.current_time, doc.is_playing)
	if _sheet != null:
		_sheet.queue_redraw()


func _key_at(pos: Vector2) -> int:
	var best := -1
	var best_dist := KEY_HIT_RADIUS
	for i in range(_key_hits.size()):
		var hit: Dictionary = _key_hits[i]
		var d: float = (hit["pos"] as Vector2).distance_to(pos)
		if d < best_dist:
			best_dist = d
			best = i
	return best
