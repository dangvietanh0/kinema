extends Control
## Modal surfaces and transient messages.
##
## The overlay owns one surface at a time and a single toast slot. On compact
## screens the surface is a bottom sheet with a drag handle; on studio and
## desktop screens it is a centred modal. Only the scrim, the close button,
## Escape/back and the drag handle dismiss it: taps, drags and scrolls that
## land inside the surface never close it.

signal modal_opened
signal modal_closed

const HIT := 44.0
const SHEET_RATIO := 0.86
const MODAL_MAX_HEIGHT := 640.0
const DRAG_DISMISS := 72.0

var _layout_mode := "studio"
var _variant := "modal"
var _options: Dictionary = {}
var _on_close := Callable()

var _backdrop: ColorRect
var _sheet_holder: VBoxContainer
var _sheet_row: HBoxContainer
var _sheet_margin: MarginContainer
var _panel: PanelContainer
var _panel_style: StyleBoxFlat
var _handle_row: MarginContainer
var _body_scroll: ScrollContainer
var _body_host: VBoxContainer
var _footer_margin: MarginContainer
var _footer_panel: PanelContainer
var _footer: HBoxContainer
var _header_margin: MarginContainer
var _title_label: Label
var _subtitle_label: Label
var _panel_content: VBoxContainer
var _toast_holder: VBoxContainer
var _toast_panel: PanelContainer
var _toast_icon: TextureRect
var _toast_label: Label
var _toast_center: CenterContainer
var _toast_margin: MarginContainer
var _toast_anchor: Control
var _toast_layout := Rect2()
var _toast_modal := false
var _modal_open := false
var _modal_serial := 0
var _toast_serial := 0
var _prompt_field: LineEdit
var _prompt_submit := Callable()
var _drag_active := false
var _drag_total := 0.0
var _foot_padding_top := 8
var _foot_padding_bottom := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	_build()


func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.66)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.visible = false
	_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_backdrop)

	_sheet_holder = VBoxContainer.new()
	_sheet_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet_holder.add_theme_constant_override("separation", 0)
	_sheet_holder.visible = false
	add_child(_sheet_holder)

	var top_spacer := Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet_holder.add_child(top_spacer)

	_sheet_row = HBoxContainer.new()
	_sheet_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_sheet_row.size_flags_vertical = Control.SIZE_SHRINK_END
	_sheet_holder.add_child(_sheet_row)

	_sheet_margin = MarginContainer.new()
	_sheet_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet_row.add_child(_sheet_margin)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_style = Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER, 1)
	_panel.add_theme_stylebox_override("panel", _panel_style)
	_sheet_margin.add_child(_panel)

	_panel_content = VBoxContainer.new()
	_panel_content.add_theme_constant_override("separation", 0)
	_panel.add_child(_panel_content)

	# Drag handle: the only part of the panel body that can dismiss a sheet.
	_handle_row = MarginContainer.new()
	_handle_row.custom_minimum_size.y = 20
	_handle_row.mouse_filter = Control.MOUSE_FILTER_STOP
	_handle_row.gui_input.connect(_on_handle_input)
	_panel_content.add_child(_handle_row)
	var handle_center := CenterContainer.new()
	handle_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_handle_row.add_child(handle_center)
	var handle := Panel.new()
	handle.custom_minimum_size = Vector2(32, 4)
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var handle_style := Kit.flat_style(Kit.BORDER, 0, Color(0, 0, 0, 0), 0)
	handle.add_theme_stylebox_override("panel", handle_style)
	handle_center.add_child(handle)

	_header_margin = MarginContainer.new()
	_header_margin.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_content.add_child(_header_margin)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	_header_margin.add_child(header)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	title_box.mouse_filter = Control.MOUSE_FILTER_STOP
	header.add_child(title_box)

	_title_label = Kit.label("", 18, Kit.TEXT, 600)
	title_box.add_child(_title_label)
	_subtitle_label = Kit.label("", 11, Kit.TEXT_MUTED, 400)
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_box.add_child(_subtitle_label)

	var close := Kit.icon_button("x", "Close", int(HIT), 20)
	close.pressed.connect(close_modal)
	header.add_child(close)

	_body_scroll = ScrollContainer.new()
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_body_scroll.custom_minimum_size = Vector2(0, 0)
	_body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	Kit.style_scroll_container(_body_scroll)
	_panel_content.add_child(_body_scroll)

	_body_host = VBoxContainer.new()
	_body_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_host.add_theme_constant_override("separation", 10)
	_body_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_body_scroll.add_child(_body_host)

	_footer_margin = MarginContainer.new()
	_footer_margin.mouse_filter = Control.MOUSE_FILTER_STOP
	_footer_margin.visible = false
	_panel_content.add_child(_footer_margin)

	# Actions sit on their own solid strip. The body scrolls behind a fixed
	# action bar, so a long settings list can never show through the buttons.
	_footer_panel = PanelContainer.new()
	_footer_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_footer_panel.add_theme_stylebox_override("panel", _footer_style())
	_footer_margin.add_child(_footer_panel)

	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 8)
	_footer.alignment = BoxContainer.ALIGNMENT_END
	_footer.mouse_filter = Control.MOUSE_FILTER_STOP
	_footer_panel.add_child(_footer)

	# Toasts stay independent of the modal so saving and small confirmations
	# can still report a result.
	_toast_holder = VBoxContainer.new()
	_toast_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toast_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_holder.add_theme_constant_override("separation", 0)
	_toast_holder.visible = false
	add_child(_toast_holder)
	_toast_center = CenterContainer.new()
	_toast_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toast_holder.add_child(_toast_center)
	_toast_margin = MarginContainer.new()
	_toast_margin.add_theme_constant_override("margin_left", 16)
	_toast_margin.add_theme_constant_override("margin_right", 16)
	_toast_margin.add_theme_constant_override("margin_top", 62)
	_toast_margin.add_theme_constant_override("margin_bottom", 0)
	_toast_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_center.add_child(_toast_margin)
	_toast_panel = PanelContainer.new()
	_toast_panel.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_3, 0, Color(0, 0, 0, 0), 0))
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_margin.add_child(_toast_panel)
	var toast_row := HBoxContainer.new()
	toast_row.add_theme_constant_override("separation", 8)
	_toast_panel.add_child(toast_row)
	_toast_icon = Kit.icon("check", Kit.SUCCESS, 14)
	toast_row.add_child(_toast_icon)
	_toast_label = Kit.label("", 12, Kit.TEXT, 500)
	toast_row.add_child(_toast_label)

	_apply_variant()


func set_toast_anchor(anchor: Control) -> void:
	# Anchoring the toast to the 3D view keeps it clear of the app header, the
	# compact drawer tabs and the timeline transport on phones.
	_toast_anchor = anchor
	_toast_layout = Rect2()
	_sync_toast_layout()


func set_layout_mode(mode: String) -> void:
	## Compact hosts bottom sheets; studio and desktop hosts centred modals.
	## An open surface is re-laid out in place so the contract never depends on
	## when the mode changed.
	_layout_mode = mode if mode in ["compact", "studio", "desktop"] else "studio"
	if _modal_open:
		_apply_variant()
		_fit_to_viewport()


func _process(_delta: float) -> void:
	_sync_toast_layout()


func _sync_toast_layout() -> void:
	if _toast_holder == null:
		return
	var anchored := _toast_anchor != null and is_instance_valid(_toast_anchor)
	var target := Rect2(Vector2.ZERO, size)
	if anchored:
		var host := _toast_anchor.get_global_rect()
		target = Rect2(host.position - get_global_rect().position, host.size)
	# A toast over an open sheet would cover its controls, so move it to the
	# top of the screen while a modal is visible.
	var modal := _modal_open
	if target == _toast_layout and modal == _toast_modal:
		return
	_toast_layout = target
	_toast_modal = modal
	var bottom_anchored := anchored and not modal
	_toast_holder.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_toast_holder.position = target.position
	_toast_holder.size = target.size
	_toast_holder.alignment = BoxContainer.ALIGNMENT_END if bottom_anchored else BoxContainer.ALIGNMENT_BEGIN
	_toast_margin.add_theme_constant_override("margin_top", 0 if bottom_anchored else 62)
	_toast_margin.add_theme_constant_override("margin_bottom", 44 if bottom_anchored else 0)


func has_modal() -> bool:
	return _modal_open


func panel_rect() -> Rect2:
	if _panel == null:
		return Rect2()
	return _panel.get_global_rect()


func body_rect() -> Rect2:
	if _body_host == null:
		return Rect2()
	return _body_host.get_global_rect()


func is_point_inside_panel(point: Vector2) -> bool:
	return panel_rect().has_point(point)


func show_modal(title: String, subtitle: String = "", body: Control = null, actions: Array = []) -> void:
	## Legacy spelling. The working mode decides the surface: a bottom sheet on
	## compact screens, a centred modal on studio and desktop. Callers that need
	## one specific surface pass `variant` through `show_sheet()`.
	show_sheet(title, subtitle, body, actions, {})


func show_sheet(title: String, subtitle: String = "", body: Control = null,
		actions: Array = [], options: Dictionary = {}) -> void:
	# A transient message belongs to the surface that produced it. Opening a
	# sheet clears it so a stale "Project created" toast cannot float above the
	# new surface and look like part of it.
	clear_toast()
	close_modal(true)
	_modal_serial += 1
	var serial := _modal_serial
	_options = options.duplicate(true)
	_on_close = options.get("on_close", Callable())
	var requested := str(_options.get("variant", ""))
	if requested == "sheet" or requested == "modal":
		_variant = requested
	else:
		_variant = "sheet" if _layout_mode == "compact" else "modal"
	_modal_open = true
	_apply_variant()
	_title_label.text = title
	_subtitle_label.text = subtitle
	_subtitle_label.visible = subtitle != ""
	for child in _body_host.get_children():
		_body_host.remove_child(child)
		child.queue_free()
	if body != null:
		_body_host.add_child(body)
		_body_scroll.visible = true
	else:
		_body_scroll.visible = false
	for child in _footer.get_children():
		_footer.remove_child(child)
		child.queue_free()
	_footer_margin.visible = not actions.is_empty()
	for action in actions:
		if not action is Dictionary:
			continue
		var data: Dictionary = action
		var button := Kit.text_button(
			str(data.get("text", "OK")),
			str(data.get("icon", "")),
			bool(data.get("primary", false)),
			bool(data.get("compact", false))
		)
		if bool(data.get("destructive", false)):
			button.add_theme_color_override("font_color", Kit.DANGER)
		var callback: Callable = data.get("callback", Callable())
		button.pressed.connect(func() -> void:
			if callback.is_valid():
				callback.call()
			if bool(data.get("close", true)):
				close_modal()
		)
		_footer.add_child(button)

	# Lay the surface out invisibly first. Containers do not resolve their
	# final width while hidden, and measuring then reads a tall narrow layout
	# that pads short sheets out to the height cap.
	_body_scroll.custom_minimum_size.y = _natural_body_height()
	_backdrop.visible = true
	_sheet_holder.visible = true
	_panel.modulate.a = 0.0
	_backdrop.modulate.a = 0.0
	# Two frames: the first applies the panel width, the second lets autowrap
	# labels recompute their height at that width.
	await get_tree().process_frame
	await get_tree().process_frame
	if serial != _modal_serial:
		return
	_fit_to_viewport()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_backdrop, "modulate:a", 1.0, 0.14)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.18)
	modal_opened.emit()


func close_modal(silent: bool = false) -> void:
	if not _modal_open:
		return
	_modal_open = false
	_modal_serial += 1
	_drag_active = false
	_drag_total = 0.0
	_backdrop.visible = false
	_sheet_holder.visible = false
	var callback := _on_close
	_on_close = Callable()
	if callback.is_valid() and not silent:
		callback.call()
	modal_closed.emit()


func confirm(title: String, message: String, confirm_text: String, on_confirm: Callable, destructive: bool = true) -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	var label := Kit.label(message, 12, Kit.TEXT_MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(label)
	show_modal(title, "", body, [
		{"text": "Cancel", "compact": true},
		{"text": confirm_text, "primary": not destructive, "destructive": destructive, "callback": on_confirm},
	])


func prompt(title: String, subtitle: String, initial: String, placeholder: String, on_submit: Callable, submit_text: String = "Save") -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	var field := Kit.line_edit(placeholder)
	field.text = initial
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	body.add_child(field)
	_prompt_field = field
	_prompt_submit = on_submit
	show_modal(title, subtitle, body, [
		{"text": "Cancel", "compact": true},
		{
			"text": submit_text,
			"primary": true,
			"callback": _submit_prompt,
		},
	])
	await get_tree().process_frame
	field.grab_focus()
	field.select_all()


func _submit_prompt() -> void:
	if not is_instance_valid(_prompt_field):
		return
	var value := _prompt_field.text.strip_edges()
	if value != "" and _prompt_submit.is_valid():
		_prompt_submit.call(value)


func toast(message: String, icon_name: String = "check", tone: Color = Kit.SUCCESS) -> void:
	_toast_serial += 1
	var serial := _toast_serial
	_toast_label.text = message
	_toast_icon.texture = Kit.icon_texture(icon_name)
	_toast_icon.modulate = tone
	_toast_holder.visible = true
	_toast_panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_toast_panel, "modulate:a", 1.0, 0.15)
	await get_tree().create_timer(2.7).timeout
	if serial != _toast_serial:
		return
	var fade := create_tween()
	fade.tween_property(_toast_panel, "modulate:a", 0.0, 0.2)
	await fade.finished
	if serial == _toast_serial:
		_toast_holder.visible = false


func clear_toast() -> void:
	# Opening a panel dismisses the transient message so it never sits on top
	# of the drawer controls.
	_toast_serial += 1
	if _toast_holder != null:
		_toast_holder.visible = false


# -------------------------------------------------------------------------
# Surface layout
# -------------------------------------------------------------------------

func _footer_style() -> StyleBoxFlat:
	var style := Kit.flat_style(Kit.SURFACE, 0, Kit.BORDER_SOFT, 0)
	style.border_width_top = 1
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 10
	style.content_margin_bottom = 0
	return style

func _apply_variant() -> void:
	var viewport_size := get_viewport_rect().size
	var width := clampf(float(_options.get("width", 720.0)), 240.0, maxf(240.0, viewport_size.x - 48.0))
	if _variant == "sheet":
		var inset := clampf(float(_options.get("bottom_inset", 0.0)), 0.0, maxf(0.0, viewport_size.y * 0.25))
		_sheet_margin.add_theme_constant_override("margin_left", 0)
		_sheet_margin.add_theme_constant_override("margin_right", 0)
		_sheet_margin.add_theme_constant_override("margin_top", 0)
		_sheet_margin.add_theme_constant_override("margin_bottom", int(round(inset)))
		_sheet_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_panel.custom_minimum_size.x = 0.0
		_panel_style.set_corner_radius_all(0)
		_panel_style.set_border_width_all(0)
		_panel_style.border_width_top = 1
		_panel_style.border_color = Kit.BORDER
		_panel_style.content_margin_left = 16
		_panel_style.content_margin_right = 16
		_panel_style.content_margin_top = 4
		_panel_style.content_margin_bottom = 0
		_set_margins(_header_margin, 4, 0, 16, 16)
		# The header is a 48 dp row; the drag handle sits above it.
		_header_margin.custom_minimum_size.y = 48.0
		_handle_row.visible = bool(_options.get("draggable", true))
		_foot_padding_top = 0
		_foot_padding_bottom = 12 + int(round(inset))
		_set_margins(_footer_margin, _foot_padding_top, _foot_padding_bottom, 0, 0)
		_footer.custom_minimum_size.y = HIT
	elif _variant == "modal":
		_sheet_margin.add_theme_constant_override("margin_left", 12)
		_sheet_margin.add_theme_constant_override("margin_right", 12)
		_sheet_margin.add_theme_constant_override("margin_top", 12)
		_sheet_margin.add_theme_constant_override("margin_bottom", 12)
		_sheet_margin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_panel.custom_minimum_size.x = width
		_panel_style.set_corner_radius_all(0)
		_panel_style.set_border_width_all(1)
		_panel_style.border_color = Kit.BORDER
		_panel_style.content_margin_left = 20
		_panel_style.content_margin_right = 20
		_panel_style.content_margin_top = 16
		_panel_style.content_margin_bottom = 16
		_set_margins(_header_margin, 0, 0, 0, 0)
		_header_margin.custom_minimum_size.y = 0.0
		_handle_row.visible = false
		_foot_padding_top = 0
		_foot_padding_bottom = 0
		_set_margins(_footer_margin, _foot_padding_top, _foot_padding_bottom, 0, 0)
		_footer.custom_minimum_size.y = 0.0
func _natural_body_height() -> float:
	if _body_scroll == null or not _body_scroll.visible:
		return 0.0
	return maxf(0.0, _body_host.get_combined_minimum_size().y)


func _set_margins(container: MarginContainer, top: int, bottom: int, left: int, right: int) -> void:
	container.add_theme_constant_override("margin_top", top)
	container.add_theme_constant_override("margin_bottom", bottom)
	container.add_theme_constant_override("margin_left", left)
	container.add_theme_constant_override("margin_right", right)


func _fit_to_viewport() -> void:
	## Clamp the surface to the viewport. The body is measured against the real
	## chrome (header, footer, handle, paddings) so a long body scrolls instead
	## of growing the surface past the cap.
	if _panel == null or _sheet_holder == null:
		return
	var viewport_size := get_viewport_rect().size
	var ratio := clampf(float(_options.get("max_height_ratio", SHEET_RATIO)), 0.30, 0.95)
	var cap := 0.0
	if _variant == "sheet":
		cap = viewport_size.y * ratio
	else:
		cap = minf(MODAL_MAX_HEIGHT, maxf(240.0, viewport_size.y - 48.0))
	var natural := _natural_body_height()
	var body_h := _body_scroll.size.y
	var panel_h := _panel.size.y
	var chrome := maxf(0.0, panel_h - body_h)
	var max_body := maxf(0.0, cap - chrome)
	if natural <= max_body:
		_body_scroll.custom_minimum_size.y = natural
	else:
		_body_scroll.custom_minimum_size.y = max_body
	if _variant == "sheet":
		_panel.custom_minimum_size.y = 0.0
	else:
		_panel.custom_minimum_size.y = 0.0


func _on_handle_input(event: InputEvent) -> void:
	# Only a deliberate downward drag on the handle dismisses the sheet. The
	# header, body and footer below it never dismiss anything.
	if Kit.is_emulated_mouse(event):
		return
	if event is InputEventScreenTouch:
		_drag_active = event.pressed
		if not event.pressed:
			if _drag_total >= DRAG_DISMISS:
				close_modal()
			_drag_total = 0.0
		accept_event()
	elif event is InputEventScreenDrag:
		if _drag_active:
			_drag_total = maxf(0.0, _drag_total + event.relative.y)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag_active = event.pressed
		if not event.pressed:
			if _drag_total >= DRAG_DISMISS:
				close_modal()
			_drag_total = 0.0
		accept_event()
	elif event is InputEventMouseMotion:
		if _drag_active:
			_drag_total = maxf(0.0, _drag_total + event.relative.y)
		accept_event()


func _on_backdrop_input(event: InputEvent) -> void:
	if Kit.is_emulated_mouse(event):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		close_modal()
	elif event is InputEventScreenTouch and event.pressed:
		close_modal()


func _unhandled_key_input(event: InputEvent) -> void:
	if not _modal_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close_modal()
		get_viewport().set_input_as_handled()
