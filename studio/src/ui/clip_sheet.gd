extends VBoxContainer
## Clip list and clip properties.
##
## New/Duplicate/Rename/Delete are real operations on the animation system.
## Deleting a clip still referenced by a strip is refused with the system's
## concrete reason instead of silently orphaning the strip.

signal notice(text: String)
signal changed

const NumFieldScript = preload("res://src/ui/num_field.gd")

var doc = null
var _list: VBoxContainer
var _name_edit: LineEdit
var _duration_field
var _loop_button: Button
var _error_label: Label
var _new_button: Button
var _duplicate_button: Button
var _rename_button: Button
var _delete_button: Button
var _selected := ""
var _syncing := false
var _built := false


func _ready() -> void:
	_ensure_built()


func setup(document) -> void:
	if doc != null and doc.has_signal("clips_changed") and doc.clips_changed.is_connected(refresh):
		doc.clips_changed.disconnect(refresh)
	if doc != null and doc.has_signal("active_clip_changed") and doc.active_clip_changed.is_connected(_on_active_changed):
		doc.active_clip_changed.disconnect(_on_active_changed)
	doc = document
	_ensure_built()
	if doc != null:
		if doc.has_signal("clips_changed"):
			doc.clips_changed.connect(refresh)
		if doc.has_signal("active_clip_changed"):
			doc.active_clip_changed.connect(_on_active_changed)
	refresh()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 12)

	add_child(Kit.section_label("Clips"))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 2)
	add_child(actions)
	_new_button = Kit.text_button("New", "", false, true)
	_new_button.pressed.connect(_on_new)
	actions.add_child(_new_button)
	_duplicate_button = Kit.text_button("Duplicate", "", false, true)
	_duplicate_button.pressed.connect(_on_duplicate)
	actions.add_child(_duplicate_button)
	_rename_button = Kit.text_button("Rename", "", false, true)
	_rename_button.pressed.connect(_on_rename)
	actions.add_child(_rename_button)
	_delete_button = Kit.text_button("Delete", "", false, true)
	_delete_button.pressed.connect(_on_delete)
	actions.add_child(_delete_button)

	var list_panel := Kit.panel(Kit.SURFACE_2, Kit.BORDER_SOFT)
	add_child(list_panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	list_panel.add_child(_list)

	add_child(Kit.section_label("Active clip"))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	add_child(name_row)
	var name_label := Kit.label("Name", 12, Kit.TEXT_MUTED)
	name_label.custom_minimum_size.x = 92
	name_row.add_child(name_label)
	_name_edit = Kit.line_edit("Clip name")
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_text: String) -> void: _on_rename())
	name_row.add_child(_name_edit)

	var duration_row := HBoxContainer.new()
	duration_row.add_theme_constant_override("separation", 8)
	add_child(duration_row)
	var duration_label := Kit.label("Duration", 12, Kit.TEXT_MUTED)
	duration_label.custom_minimum_size.x = 92
	duration_row.add_child(duration_label)
	_duration_field = NumFieldScript.new()
	_duration_field.axis = "S"
	_duration_field.suffix = "s"
	_duration_field.min_value = 0.04
	_duration_field.max_value = 600.0
	_duration_field.step = 0.01
	_duration_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_duration_field.value_changed.connect(_on_duration_changed)
	duration_row.add_child(_duration_field)

	var loop_row := HBoxContainer.new()
	loop_row.add_theme_constant_override("separation", 8)
	add_child(loop_row)
	var loop_label := Kit.label("Loop", 12, Kit.TEXT_MUTED)
	loop_label.custom_minimum_size.x = 92
	loop_row.add_child(loop_label)
	_loop_button = Kit.text_toggle("Loop clip", "", true)
	_loop_button.toggled.connect(_on_loop_toggled)
	loop_row.add_child(_loop_button)

	_error_label = Kit.label("", 11, Kit.WARNING)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.visible = false
	add_child(_error_label)


func open() -> void:
	refresh()


func refresh() -> void:
	_ensure_built()
	if doc == null or doc.animation_system == null:
		return
	_syncing = true
	var system = doc.animation_system
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for id in system.clip_ids():
		var clip: Dictionary = system.get_clip(id)
		var button := Kit.text_button("%s · %.2f s" % [str(clip.get("name", "Clip")), float(clip.get("duration", 0.04))], "", false, true)
		button.custom_minimum_size.y = 44.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if id == system.active_clip_id():
			button.add_theme_color_override("font_color", Kit.FOCUS_BRIGHT)
			button.add_theme_stylebox_override("normal", Kit.flat_style(Kit.SURFACE_ACTIVE, 0, Kit.FOCUS_DARK, 1))
		button.pressed.connect(func() -> void: _select_clip(id))
		_list.add_child(button)
	_selected = system.active_clip_id()
	var active: Dictionary = system.get_clip(_selected)
	if not active.is_empty():
		_name_edit.text = str(active.get("name", ""))
		_duration_field.set_value_silent(float(active.get("duration", 0.04)))
		_loop_button.set_pressed_no_signal(bool(active.get("loop", true)))
	_error_label.visible = false
	_syncing = false


func clip_row_count() -> int:
	return _list.get_child_count() if _list != null else 0


func new_button() -> Button:
	return _new_button


func duplicate_button() -> Button:
	return _duplicate_button


func rename_button() -> Button:
	return _rename_button


func delete_button() -> Button:
	return _delete_button


func _select_clip(id: String) -> void:
	if doc == null:
		return
	doc.set_active_clip(id)
	refresh()


func _on_active_changed(_id: String) -> void:
	if not _syncing:
		refresh()


func _on_new() -> void:
	if doc == null:
		return
	if doc.has_method("begin_edit"):
		doc.begin_edit("New clip")
	var system = doc.animation_system
	var id: String = system.create_clip("Clip %d" % (system.clip_ids().size() + 1), 2.0)
	if id != "":
		doc.set_active_clip(id)
	if doc.has_method("end_edit"):
		doc.end_edit()
	refresh()
	changed.emit()


func _on_duplicate() -> void:
	if doc == null:
		return
	if doc.has_method("begin_edit"):
		doc.begin_edit("Duplicate clip")
	var system = doc.animation_system
	var id: String = system.duplicate_clip(system.active_clip_id())
	if id != "":
		doc.set_active_clip(id)
	if doc.has_method("end_edit"):
		doc.end_edit()
	refresh()
	changed.emit()


func _on_rename() -> void:
	if doc == null or _syncing:
		return
	if doc.has_method("begin_edit"):
		doc.begin_edit("Rename clip")
	doc.animation_system.rename_clip(doc.animation_system.active_clip_id(), _name_edit.text)
	if doc.has_method("end_edit"):
		doc.end_edit()
	refresh()
	changed.emit()


func _on_delete() -> void:
	if doc == null:
		return
	if doc.has_method("begin_edit"):
		doc.begin_edit("Delete clip")
	var system = doc.animation_system
	var ok: bool = system.delete_clip(system.active_clip_id())
	var reason := ""
	if ok:
		doc.set_active_clip(system.active_clip_id())
	else:
		reason = str(system.last_error)
	if doc.has_method("end_edit"):
		doc.end_edit()
	refresh()
	# Refresh rebuilds the list and hides the label, so publish the refusal last.
	_error_label.text = reason
	_error_label.visible = not ok
	changed.emit()


func _on_duration_changed(value: float) -> void:
	if doc == null or _syncing:
		return
	if doc.has_method("begin_edit"):
		doc.begin_edit("Clip duration")
	var system = doc.animation_system
	system.set_clip_duration(system.active_clip_id(), value)
	doc.set_active_clip(system.active_clip_id())
	if doc.has_method("end_edit"):
		doc.end_edit()
	changed.emit()


func _on_loop_toggled(enabled: bool) -> void:
	if doc == null or _syncing:
		return
	if doc.has_method("begin_edit"):
		doc.begin_edit("Clip loop")
	doc.animation_system.set_clip_loop(doc.animation_system.active_clip_id(), enabled)
	doc.set_loop(enabled)
	if doc.has_method("end_edit"):
		doc.end_edit()
	changed.emit()
