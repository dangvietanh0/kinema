extends VBoxContainer
## Layer properties: name, weight, blend mode, mute and solo.
##
## The last layer cannot be deleted; the sheet shows the system's concrete
## reason instead of disabling the action without an explanation.

signal changed
signal notice(text: String)

const NumFieldScript = preload("res://src/ui/num_field.gd")

var doc = null
var layer_id := ""
var _name_edit: LineEdit
var _weight_slider: HSlider
var _weight_field
var _blend_option: OptionButton
var _mute_button: Button
var _solo_button: Button
var _new_button: Button
var _delete_button: Button
var _error_label: Label
var _syncing := false
var _built := false


func _ready() -> void:
	_ensure_built()


func setup(document) -> void:
	if doc != null and doc.has_signal("clips_changed") and doc.clips_changed.is_connected(refresh):
		doc.clips_changed.disconnect(refresh)
	doc = document
	_ensure_built()
	if doc != null and doc.has_signal("clips_changed"):
		doc.clips_changed.connect(refresh)
	refresh()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 12)

	add_child(Kit.section_label("Layer"))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	add_child(name_row)
	var name_label := Kit.label("Name", 12, Kit.TEXT_MUTED)
	name_label.custom_minimum_size.x = 92
	name_row.add_child(name_label)
	_name_edit = Kit.line_edit("Layer name")
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_text: String) -> void: _on_name_changed())
	name_row.add_child(_name_edit)

	var weight_row := HBoxContainer.new()
	weight_row.add_theme_constant_override("separation", 8)
	add_child(weight_row)
	var weight_label := Kit.label("Weight", 12, Kit.TEXT_MUTED)
	weight_label.custom_minimum_size.x = 92
	weight_row.add_child(weight_label)
	_weight_slider = HSlider.new()
	_weight_slider.min_value = 0.0
	_weight_slider.max_value = 1.0
	_weight_slider.step = 0.01
	_weight_slider.custom_minimum_size = Vector2(120, 44)
	_weight_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weight_slider.value_changed.connect(_on_weight_slider)
	weight_row.add_child(_weight_slider)
	_weight_field = NumFieldScript.new()
	_weight_field.axis = "W"
	_weight_field.min_value = 0.0
	_weight_field.max_value = 1.0
	_weight_field.step = 0.01
	_weight_field.custom_minimum_size.x = 104
	_weight_field.value_changed.connect(_on_weight_field)
	weight_row.add_child(_weight_field)

	var blend_row := HBoxContainer.new()
	blend_row.add_theme_constant_override("separation", 8)
	add_child(blend_row)
	var blend_label := Kit.label("Blend", 12, Kit.TEXT_MUTED)
	blend_label.custom_minimum_size.x = 92
	blend_row.add_child(blend_label)
	_blend_option = OptionButton.new()
	_blend_option.custom_minimum_size = Vector2(160, 44)
	_blend_option.add_item("Override")
	_blend_option.add_item("Additive")
	_blend_option.item_selected.connect(_on_blend_selected)
	blend_row.add_child(_blend_option)

	var flags_row := HBoxContainer.new()
	flags_row.add_theme_constant_override("separation", 8)
	add_child(flags_row)
	var flags_label := Kit.label("State", 12, Kit.TEXT_MUTED)
	flags_label.custom_minimum_size.x = 92
	flags_row.add_child(flags_label)
	_mute_button = Kit.text_toggle("Mute", "", true)
	_mute_button.toggled.connect(_on_mute_toggled)
	flags_row.add_child(_mute_button)
	_solo_button = Kit.text_toggle("Solo", "", true)
	_solo_button.toggled.connect(_on_solo_toggled)
	flags_row.add_child(_solo_button)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 2)
	add_child(actions)
	_new_button = Kit.text_button("New layer", "", false, true)
	_new_button.pressed.connect(_on_new_layer)
	actions.add_child(_new_button)
	_delete_button = Kit.text_button("Delete layer", "trash-2", false, true)
	_delete_button.pressed.connect(_on_delete)
	actions.add_child(_delete_button)

	_error_label = Kit.label("", 11, Kit.WARNING)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.visible = false
	add_child(_error_label)


func open(id: String) -> void:
	layer_id = id
	refresh()


func refresh() -> void:
	_ensure_built()
	if doc == null or doc.animation_system == null:
		return
	var layer: Dictionary = doc.animation_system.get_layer(layer_id)
	if layer.is_empty():
		var layers: Array = doc.animation_system.layers()
		if layers.is_empty():
			return
		layer_id = str(layers[0].get("id", ""))
		layer = doc.animation_system.get_layer(layer_id)
	if layer.is_empty():
		return
	_syncing = true
	_name_edit.text = str(layer.get("name", "Layer"))
	var weight := clampf(float(layer.get("weight", 1.0)), 0.0, 1.0)
	_weight_slider.set_value_no_signal(weight)
	_weight_field.set_value_silent(weight)
	_blend_option.select(1 if str(layer.get("blend", "override")) == "additive" else 0)
	_mute_button.set_pressed_no_signal(bool(layer.get("muted", false)))
	_solo_button.set_pressed_no_signal(bool(layer.get("solo", false)))
	var last: bool = doc.animation_system.layers().size() <= 1
	_delete_button.disabled = last
	_delete_button.tooltip_text = "A project needs at least one layer." if last else "Delete this layer and its strips"
	_error_label.visible = false
	_syncing = false


func weight_slider() -> HSlider:
	return _weight_slider


func new_layer_button() -> Button:
	return _new_button


func delete_button() -> Button:
	return _delete_button


func _on_new_layer() -> void:
	if doc == null or doc.animation_system == null:
		return
	if doc.has_method("begin_edit"):
		doc.begin_edit("Add layer")
	var id: String = doc.animation_system.add_layer("Layer")
	if id != "":
		doc.animation_system.set_active_layer(id)
		layer_id = id
	if doc.has_method("end_edit"):
		doc.end_edit()
	refresh()
	changed.emit()


func _on_name_changed() -> void:
	if doc == null or _syncing:
		return
	if doc.has_method("begin_edit"):
		doc.begin_edit("Layer name")
	doc.animation_system.update_layer(layer_id, {"name": _name_edit.text})
	if doc.has_method("end_edit"):
		doc.end_edit()
	changed.emit()


func _on_weight_slider(value: float) -> void:
	if doc == null or _syncing:
		return
	_syncing = true
	_weight_field.set_value_silent(value)
	_syncing = false
	if doc.has_method("begin_edit"):
		doc.begin_edit("Layer weight")
	doc.animation_system.update_layer(layer_id, {"weight": value})
	if doc.has_method("end_edit"):
		doc.end_edit()
	changed.emit()


func _on_weight_field(value: float) -> void:
	if doc == null or _syncing:
		return
	_syncing = true
	_weight_slider.set_value_no_signal(value)
	_syncing = false
	if doc.has_method("begin_edit"):
		doc.begin_edit("Layer weight")
	doc.animation_system.update_layer(layer_id, {"weight": value})
	if doc.has_method("end_edit"):
		doc.end_edit()
	changed.emit()


func _on_blend_selected(index: int) -> void:
	if doc == null or _syncing:
		return
	if doc.has_method("begin_edit"):
		doc.begin_edit("Layer blend")
	doc.animation_system.update_layer(layer_id, {"blend": "additive" if index == 1 else "override"})
	if doc.has_method("end_edit"):
		doc.end_edit()
	changed.emit()


func _on_mute_toggled(enabled: bool) -> void:
	if doc == null or _syncing:
		return
	if doc.has_method("begin_edit"):
		doc.begin_edit("Layer mute")
	doc.animation_system.update_layer(layer_id, {"muted": enabled})
	if doc.has_method("end_edit"):
		doc.end_edit()
	changed.emit()


func _on_solo_toggled(enabled: bool) -> void:
	if doc == null or _syncing:
		return
	if doc.has_method("begin_edit"):
		doc.begin_edit("Layer solo")
	doc.animation_system.update_layer(layer_id, {"solo": enabled})
	if doc.has_method("end_edit"):
		doc.end_edit()
	changed.emit()


func _on_delete() -> void:
	if doc == null:
		return
	if doc.has_method("begin_edit"):
		doc.begin_edit("Delete layer")
	var ok: bool = doc.animation_system.delete_layer(layer_id)
	var reason := ""
	if ok:
		layer_id = doc.animation_system.active_layer_id()
	else:
		reason = str(doc.animation_system.last_error)
	if doc.has_method("end_edit"):
		doc.end_edit()
	refresh()
	# Refresh hides the label, so publish the refusal last.
	_error_label.text = reason
	_error_label.visible = not ok
	changed.emit()
