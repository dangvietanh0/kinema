extends PanelContainer
## The context row: one workspace's actions, ordered by priority.
##
## The row never scrolls. When the declared actions do not fit it keeps the
## highest-priority ones and moves the rest into a `more` popup. Every button
## carries `action_id`/`action_icon` metadata so the icon-contract test can read
## what the user actually sees.

signal action_requested(action_id: String)

const HEIGHT_TOUCH := 44
const HEIGHT_DESKTOP := 36
const PAD := 4
const GAP := 4
const DEFAULT_TEXT_WIDTH := 96.0

var _layout_mode := "studio"
var _available_width := -1.0
var _actions: Array = []
var _row: HBoxContainer
var _more_button: Button
var _popup: PopupMenu
var _buttons: Dictionary = {}
var _items: Array = []
var _hidden_order: Array[String] = []


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_build()
	_apply_mode()


func _build() -> void:
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", GAP)
	add_child(_row)

	_more_button = Kit.icon_button("ellipsis-vertical", "More actions")
	_more_button.set_meta("action_id", "more")
	_more_button.set_meta("action_icon", "ellipsis-vertical")
	_more_button.set_meta("is_text", false)
	_more_button.tooltip_text = "More actions"
	_more_button.visible = false
	_more_button.pressed.connect(_show_more)
	_row.add_child(_more_button)
	_buttons["more"] = _more_button

	_popup = PopupMenu.new()
	_popup.id_pressed.connect(_on_popup_id)
	add_child(_popup)


func set_layout_mode(mode: String) -> void:
	_layout_mode = mode if mode in ["compact", "studio", "desktop"] else "studio"
	_apply_mode()


func set_available_width(value: float) -> void:
	_available_width = value
	_apply_overflow()


func set_actions(actions: Array) -> void:
	_actions.clear()
	for action in actions:
		if typeof(action) == TYPE_DICTIONARY:
			_actions.append(action.duplicate(true))
	_actions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("priority", 0)) > int(b.get("priority", 0))
	)
	if _row == null:
		return
	_rebuild()
	_apply_mode()


func set_action_enabled(id: String, enabled: bool, reason := "") -> void:
	var button: Button = _buttons.get(id, null)
	if button == null:
		return
	button.disabled = not enabled
	button.tooltip_text = reason if (not enabled and reason != "") else _button_label(button)


func set_action_active(id: String, active: bool) -> void:
	var button: Button = _buttons.get(id, null)
	if button == null:
		return
	button.set_pressed_no_signal(active and button.toggle_mode)
	if active:
		button.add_theme_stylebox_override("normal", Kit.flat_style(
			Kit.FOCUS, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
		button.add_theme_stylebox_override("hover", Kit.flat_style(
			Kit.FOCUS.lightened(0.08), Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
		button.add_theme_color_override("font_color", Color(0, 0, 0))
		button.add_theme_color_override("font_hover_color", Color(0, 0, 0))
		button.add_theme_color_override("font_pressed_color", Color(0, 0, 0))
		button.add_theme_color_override("icon_normal_color", Color(0, 0, 0))
		button.add_theme_color_override("icon_hover_color", Color(0, 0, 0))
		button.add_theme_color_override("icon_pressed_color", Color(0, 0, 0))
	else:
		button.remove_theme_stylebox_override("normal")
		button.remove_theme_stylebox_override("hover")
		button.remove_theme_color_override("font_color")
		button.remove_theme_color_override("font_hover_color")
		button.remove_theme_color_override("font_pressed_color")
		button.remove_theme_color_override("icon_normal_color")
		button.remove_theme_color_override("icon_hover_color")
		button.remove_theme_color_override("icon_pressed_color")


func action_button(id: String) -> Button:
	return _buttons.get(id, null)


func visible_action_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for item in _items:
		var node: Control = item.get("node")
		if node == null or not node.visible:
			continue
		for id in item.get("ids", []):
			ids.append(str(id))
	if _more_button != null and _more_button.visible:
		ids.append("more")
	return ids


func overflow_visible() -> bool:
	return _more_button != null and _more_button.visible


func _rebuild() -> void:
	for child in _row.get_children():
		if child == _more_button:
			continue
		_row.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_items.clear()
	var groups: Dictionary = {}

	for action in _actions:
		var id := str(action.get("id", ""))
		if id == "":
			continue
		var group_id := str(action.get("group", ""))
		var button := _make_button(action)
		_buttons[id] = button
		if group_id == "":
			_row.add_child(button)
			_items.append({"node": button, "ids": [id]})
		else:
			if not groups.has(group_id):
				var group := HBoxContainer.new()
				group.add_theme_constant_override("separation", 0)
				_row.add_child(group)
				groups[group_id] = group
				_items.append({"node": group, "ids": []})
			var group_node: HBoxContainer = groups[group_id]
			group_node.add_child(button)
			for item in _items:
				if item.get("node") == group_node:
					item["ids"].append(id)
					break
	# More is always the last child, even after groups are appended.
	_row.move_child(_more_button, _row.get_child_count() - 1)


func _make_button(action: Dictionary) -> Button:
	var id := str(action.get("id", ""))
	var label := str(action.get("label", id))
	var icon_name := str(action.get("icon", ""))
	var text := bool(action.get("text", false))
	var toggle := bool(action.get("toggle", false))
	var width := float(action.get("width", 0.0))
	var button: Button
	if text:
		button = Kit.text_button(label, icon_name, false, true)
		button.add_theme_font_size_override("font_size", 13)
	else:
		button = Kit.icon_button(icon_name, label)
	button.toggle_mode = toggle
	button.set_meta("action_id", id)
	button.set_meta("action_icon", icon_name)
	button.set_meta("is_text", text)
	button.set_meta("pref_width", width)
	button.set_meta("label", label)
	button.pressed.connect(func() -> void: action_requested.emit(id))
	return button


func _apply_mode() -> void:
	var desktop := _layout_mode == "desktop"
	var height := float(HEIGHT_DESKTOP if desktop else HEIGHT_TOUCH)
	var icon_side := 28.0 if desktop else 44.0
	custom_minimum_size.y = height
	var style := Kit.flat_style(Kit.SURFACE_2, 0, Color(0, 0, 0, 0), 0)
	style.content_margin_left = PAD
	style.content_margin_right = PAD
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	add_theme_stylebox_override("panel", style)
	for id in _buttons.keys():
		var button: Button = _buttons[id]
		if button == null:
			continue
		if id == "more" or not bool(button.get_meta("is_text", false)):
			button.custom_minimum_size = Vector2(icon_side, icon_side)
			button.add_theme_constant_override("icon_max_width", 18 if desktop else 20)
			if desktop:
				Kit.exempt_from_hit_floor(button)
		else:
			var width := float(button.get_meta("pref_width", 0.0))
			button.custom_minimum_size = Vector2(width if width > 0.0 else DEFAULT_TEXT_WIDTH, height)
			if desktop:
				Kit.exempt_from_hit_floor(button)
	if _row != null:
		_row.add_theme_constant_override("separation", GAP)
	_apply_overflow()


func _apply_overflow() -> void:
	if _row == null or _items.is_empty():
		if _more_button != null:
			_more_button.visible = false
		return
	var desktop := _layout_mode == "desktop"
	var more_width := 28.0 if desktop else 44.0
	var total := 0.0
	for i in range(_items.size()):
		var node: Control = _items[i].get("node")
		total += node.get_combined_minimum_size().x
		if i > 0:
			total += GAP
	var budget := INF
	if _available_width > 0.0:
		budget = _available_width - float(PAD) * 2.0
	if total <= budget:
		for item in _items:
			var node: Control = item.get("node")
			node.visible = true
		_more_button.visible = false
		_hidden_order.clear()
		return
	_more_button.visible = true
	var used := more_width
	var shown := 0
	_hidden_order.clear()
	for item in _items:
		var node: Control = item.get("node")
		var width: float = node.get_combined_minimum_size().x
		if shown == 0 or used + GAP + width <= budget:
			node.visible = true
			used += GAP + width
			shown += 1
		else:
			node.visible = false
			for id in item.get("ids", []):
				_hidden_order.append(str(id))


func _show_more() -> void:
	if _popup == null:
		return
	_popup.clear()
	for index in range(_hidden_order.size()):
		var id := _hidden_order[index]
		var button: Button = _buttons.get(id, null)
		if button == null:
			continue
		var label := _button_label(button)
		_popup.add_item(label, index)
		if button.disabled:
			_popup.set_item_disabled(index, true)
		if button.tooltip_text != "":
			_popup.set_item_tooltip(index, button.tooltip_text)
	_popup.position = Vector2i(_more_button.get_screen_position() + Vector2(0, _more_button.size.y))
	_popup.popup()


func _on_popup_id(index: int) -> void:
	if index >= 0 and index < _hidden_order.size():
		action_requested.emit(_hidden_order[index])


func _button_label(button: Button) -> String:
	var stored := str(button.get_meta("label", ""))
	return stored if stored != "" else button.text
