extends Control
## Modal sheets and transient messages.
##
## The overlay owns one modal at a time and a single toast slot. It is
## deliberately simple: a dimmed backdrop, a bottom-anchored sheet with a
## scrollable body, and an optional button row.

signal modal_opened
signal modal_closed

var _backdrop: ColorRect
var _sheet_holder: VBoxContainer
var _panel: PanelContainer
var _body_scroll: ScrollContainer
var _body_host: VBoxContainer
var _footer: HBoxContainer
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

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	_build()

func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.015, 0.022, 0.031, 0.66)
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

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.size_flags_vertical = Control.SIZE_SHRINK_END
	_sheet_holder.add_child(center)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(margin)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := Kit.flat_style(Kit.SURFACE, 10, Kit.BORDER, 1)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", style)
	margin.add_child(_panel)

	_panel_content = VBoxContainer.new()
	_panel_content.add_theme_constant_override("separation", 12)
	_panel.add_child(_panel_content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	_panel_content.add_child(header)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	header.add_child(title_box)

	_title_label = Kit.label("", 18, Kit.TEXT, 600)
	title_box.add_child(_title_label)
	_subtitle_label = Kit.label("", 11, Kit.TEXT_MUTED, 400)
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_box.add_child(_subtitle_label)

	var close := Kit.icon_button("x", "Close", 30, 15)
	close.pressed.connect(close_modal)
	header.add_child(close)

	_body_scroll = ScrollContainer.new()
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_body_scroll.custom_minimum_size = Vector2(0, 0)
	_body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel_content.add_child(_body_scroll)

	_body_host = VBoxContainer.new()
	_body_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_host.add_theme_constant_override("separation", 10)
	_body_scroll.add_child(_body_host)

	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 8)
	_footer.alignment = BoxContainer.ALIGNMENT_END
	_panel_content.add_child(_footer)
	_footer.visible = false

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
	_toast_panel.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_3, 7, Kit.BORDER, 1))
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_margin.add_child(_toast_panel)
	var toast_row := HBoxContainer.new()
	toast_row.add_theme_constant_override("separation", 8)
	_toast_panel.add_child(toast_row)
	_toast_icon = Kit.icon("check", Kit.SUCCESS, 14)
	toast_row.add_child(_toast_icon)
	_toast_label = Kit.label("", 12, Kit.TEXT, 500)
	toast_row.add_child(_toast_label)

func set_toast_anchor(anchor: Control) -> void:
	# Anchoring the toast to the 3D view keeps it clear of the app header, the
	# compact drawer tabs and the timeline transport on phones.
	_toast_anchor = anchor
	_toast_layout = Rect2()
	_sync_toast_layout()

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

func show_modal(title: String, subtitle: String = "", body: Control = null, actions: Array = []) -> void:
	close_modal()
	_modal_serial += 1
	var serial := _modal_serial
	_modal_open = true
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
	_footer.visible = not actions.is_empty()
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

	# Keep the sheet inside the viewport while allowing long content to scroll.
	var available_w := maxf(240.0, get_viewport_rect().size.x - 24.0)
	var available_h := maxf(220.0, get_viewport_rect().size.y - 80.0)
	_panel.custom_minimum_size.x = minf(460.0, available_w)
	_body_scroll.custom_minimum_size.y = 0
	# Lay the sheet out invisibly first. Containers do not resolve their final
	# width while hidden, and measuring then reads a tall narrow layout that
	# pads short sheets out to the 62% cap.
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
	# A ScrollContainer reports a zero minimum size by design, so measure the
	# content host instead. Without this every sheet collapses its body to
	# nothing while the children still exist off-screen.
	var natural := _body_host.get_combined_minimum_size().y
	var max_body := minf(available_h * 0.62, natural)
	_body_scroll.custom_minimum_size.y = maxf(0.0, minf(natural, max_body))
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_backdrop, "modulate:a", 1.0, 0.14)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.18)
	modal_opened.emit()

func close_modal() -> void:
	if not _modal_open:
		return
	_modal_open = false
	_modal_serial += 1
	_backdrop.visible = false
	_sheet_holder.visible = false
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
