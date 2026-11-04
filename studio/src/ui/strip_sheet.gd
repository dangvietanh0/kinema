extends VBoxContainer
## Strip properties: start, trim, speed, weight, fades, ease and layer blend.
##
## Every field writes straight into the animation system; there is no local
## copy that can drift from the sequence.

signal changed
signal notice(text: String)

const NumFieldScript = preload("res://src/ui/num_field.gd")
const FIELDS := [
	{"key": "start", "label": "Start", "axis": "S", "suffix": "s", "min": 0.0, "max": 600.0, "step": 0.01},
	{"key": "trim_start", "label": "Trim in", "axis": "S", "suffix": "s", "min": 0.0, "max": 600.0, "step": 0.01},
	{"key": "trim_end", "label": "Trim out", "axis": "S", "suffix": "s", "min": 0.0, "max": 600.0, "step": 0.01},
	{"key": "speed", "label": "Speed", "axis": "×", "suffix": "", "min": 0.05, "max": 8.0, "step": 0.01},
	{"key": "weight", "label": "Weight", "axis": "W", "suffix": "", "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "fade_in", "label": "Fade in", "axis": "S", "suffix": "s", "min": 0.0, "max": 600.0, "step": 0.01},
	{"key": "fade_out", "label": "Fade out", "axis": "S", "suffix": "s", "min": 0.0, "max": 600.0, "step": 0.01},
	{"key": "ease", "label": "Ease", "axis": "E", "suffix": "", "min": 0.0, "max": 4.0, "step": 0.01},
]

var doc = null
var strip_id := ""
var _fields: Dictionary = {}
var _blend_option: OptionButton
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
	add_child(Kit.section_label("Strip"))
	for entry in FIELDS:
		var data: Dictionary = entry
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		add_child(row)
		var label := Kit.label(str(data.get("label", "")), 12, Kit.TEXT_MUTED)
		label.custom_minimum_size.x = 92
		row.add_child(label)
		var field = NumFieldScript.new()
		field.axis = str(data.get("axis", "X"))
		field.suffix = str(data.get("suffix", ""))
		field.min_value = float(data.get("min", 0.0))
		field.max_value = float(data.get("max", 1.0))
		field.step = float(data.get("step", 0.01))
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key := str(data.get("key", ""))
		field.value_changed.connect(func(value: float) -> void: _on_field_changed(key, value))
		row.add_child(field)
		_fields[key] = field

	var blend_row := HBoxContainer.new()
	blend_row.add_theme_constant_override("separation", 8)
	add_child(blend_row)
	var blend_label := Kit.label("Layer blend", 12, Kit.TEXT_MUTED)
	blend_label.custom_minimum_size.x = 92
	blend_row.add_child(blend_label)
	_blend_option = OptionButton.new()
	_blend_option.custom_minimum_size = Vector2(160, 44)
	_blend_option.add_item("Override")
	_blend_option.add_item("Additive")
	_blend_option.item_selected.connect(_on_blend_selected)
	blend_row.add_child(_blend_option)

	_delete_button = Kit.text_button("Delete strip", "trash-2", false, true)
	_delete_button.pressed.connect(_on_delete)
	add_child(_delete_button)

	_error_label = Kit.label("", 11, Kit.WARNING)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.visible = false
	add_child(_error_label)


func open(id: String) -> void:
	strip_id = id
	refresh()


func refresh() -> void:
	_ensure_built()
	if doc == null or doc.animation_system == null:
		return
	var strip: Dictionary = doc.animation_system.get_strip(strip_id)
	if strip.is_empty():
		return
	_syncing = true
	for key in _fields.keys():
		if strip.has(key):
			_fields[key].set_value_silent(float(strip[key]))
	var layer: Dictionary = doc.animation_system.get_layer(str(strip.get("layer_id", "")))
	if not layer.is_empty():
		_blend_option.select(1 if str(layer.get("blend", "override")) == "additive" else 0)
	_error_label.visible = false
	_syncing = false


func field(key: String):
	return _fields.get(key)


func strip() -> String:
	return strip_id


func delete_button() -> Button:
	return _delete_button


func _on_field_changed(key: String, value: float) -> void:
	if doc == null or _syncing:
		return
	if doc.has_method("begin_edit"):
		doc.begin_edit("Strip " + key)
	var patch: Dictionary = {key: value}
	doc.animation_system.update_strip(strip_id, patch)
	if doc.has_method("end_edit"):
		doc.end_edit()
	refresh()
	changed.emit()


func _on_blend_selected(index: int) -> void:
	if doc == null or _syncing:
		return
	var strip: Dictionary = doc.animation_system.get_strip(strip_id)
	if strip.is_empty():
		return
	if doc.has_method("begin_edit"):
		doc.begin_edit("Layer blend")
	doc.animation_system.update_layer(str(strip.get("layer_id", "")), {"blend": "additive" if index == 1 else "override"})
	if doc.has_method("end_edit"):
		doc.end_edit()
	changed.emit()


func _on_delete() -> void:
	if doc == null:
		return
	if doc.has_method("begin_edit"):
		doc.begin_edit("Delete strip")
	doc.animation_system.delete_strip(strip_id)
	if doc.has_method("end_edit"):
		doc.end_edit()
	strip_id = ""
	changed.emit()
