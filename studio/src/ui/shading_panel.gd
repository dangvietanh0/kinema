extends VBoxContainer
## Shading workspace panel: the existing material library and material editor
## embedded in one live column. The library scrolls at up to 45% of the panel
## height; the editor fills the rest. There is no panel footer and no second
## title row.

signal changed
signal delete_requested(material_id: String)
signal color_requested(property: String, current: Color, material_id: String)

const MaterialSheetScript = preload("res://src/ui/material_sheet.gd")
const MaterialEditorSheetScript = preload("res://src/ui/material_editor_sheet.gd")
const ASSIGN_REASON := "Select an object to assign this material."

var _doc = null
var _built := false
var _library_scroll: ScrollContainer
var _editor_scroll: ScrollContainer
var _library: Control
var _editor: Control
var _target: Dictionary = {}


func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 8)
	_library_scroll = ScrollContainer.new()
	_library_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_library_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	Kit.style_scroll_container(_library_scroll)
	_library_scroll.custom_minimum_size.y = 44.0
	add_child(_library_scroll)

	_editor_scroll = ScrollContainer.new()
	_editor_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_editor_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	Kit.style_scroll_container(_editor_scroll)
	add_child(_editor_scroll)
	resized.connect(_apply_library_height)
	_apply_library_height()


func setup(doc) -> void:
	_ensure_built()
	_doc = doc
	if _library == null:
		_library = MaterialSheetScript.new()
		_library.setup(doc, _target)
		_library.changed.connect(_on_library_changed)
		_library.assigned.connect(func(_id: String) -> void: changed.emit())
		_library.delete_requested.connect(func(id: String) -> void: delete_requested.emit(id))
		_library_scroll.add_child(_library)
	else:
		_library.setup(doc, _target)
	if _editor == null:
		_editor = MaterialEditorSheetScript.new()
		_editor.setup(doc)
		_editor.delete_requested.connect(func(id: String) -> void: delete_requested.emit(id))
		_editor.color_requested.connect(func(property: String, current: Color) -> void:
			color_requested.emit(property, current, str(_editor.material_id()))
		)
		_editor.changed.connect(_on_editor_changed)
		_editor_scroll.add_child(_editor)
	else:
		_editor.setup(doc)
	refresh()


func set_target(object_id: String, part_path := "", surface := -1) -> void:
	_target = {"object_id": object_id, "part_path": part_path, "surface": surface}
	_ensure_built()
	if _library != null:
		_library.set_target(_target)
	if _editor != null:
		_editor.set_target(_target)
	if _library == null or _editor == null:
		return
	var assigned := _assigned_material()
	if assigned != "":
		select_material(assigned)
	else:
		_editor.open("")
		if not str(_target.get("object_id", "")) == "":
			_library.refresh()


func target() -> Dictionary:
	return _target.duplicate(true)


func select_material(material_id: String) -> void:
	if _library == null or _editor == null:
		return
	_library.select(material_id)
	_editor.set_target(_target)
	_editor.open(material_id)


func material_sheet() -> Control:
	_ensure_built()
	return _library


func material_editor() -> Control:
	_ensure_built()
	return _editor


func assign_button() -> Button:
	if _library == null:
		return null
	var selected := str(_library.selected_id())
	if selected == "":
		return null
	return _library.assign_button(selected)


func selected_material_id() -> String:
	return "" if _library == null else str(_library.selected_id())


func assign_selected() -> bool:
	if _library == null or _doc == null or _doc.material_system == null:
		return false
	var material_id := str(_library.selected_id())
	var object_id := str(_target.get("object_id", ""))
	if object_id == "" or material_id == "":
		var button := assign_button()
		if button != null:
			button.disabled = true
			button.tooltip_text = ASSIGN_REASON
		return false
	_library.assign_material(material_id)
	var resolved: String = _doc.material_system.resolve_assignment(
		object_id, str(_target.get("part_path", "")), int(_target.get("surface", -1)))
	return resolved == material_id


func refresh() -> void:
	_ensure_built()
	if _library != null:
		_library.set_target(_target)
		_library.refresh()
	if _editor != null:
		_editor.set_target(_target)
		var material_id := str(_library.selected_id()) if _library != null else ""
		_editor.open(material_id)
	_apply_library_height()


func new_material() -> String:
	_ensure_built()
	if _library == null:
		return ""
	var material_id: String = _library.new_material()
	if material_id != "":
		select_material(material_id)
	return material_id


func _assigned_material() -> String:
	if _doc == null or _doc.material_system == null:
		return ""
	var object_id := str(_target.get("object_id", ""))
	if object_id == "":
		return ""
	return _doc.material_system.resolve_assignment(
		object_id, str(_target.get("part_path", "")), int(_target.get("surface", -1)))


func _on_library_changed(material_id: String) -> void:
	select_material(material_id)
	changed.emit()


func _on_editor_changed(_material_id: String) -> void:
	if _library != null:
		_library.refresh()
	if _editor != null:
		_editor.set_target(_target)
	changed.emit()


func _apply_library_height() -> void:
	if _library_scroll == null:
		return
	_library_scroll.custom_minimum_size.y = clampf(size.y * 0.45, 44.0, 360.0)
