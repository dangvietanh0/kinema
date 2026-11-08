extends VBoxContainer
## Render workspace panel: embeds the existing media export sheet and adds a
## GLB scene export tab. The panel never opens a modal; the host workspace
## header carries the title and the current output badge.

signal export_requested(options: Dictionary)
signal close_requested
signal tab_changed(tab: String)

const MediaExportSheetScript = preload("res://src/ui/media_export_sheet.gd")
const TAB_RENDER := "render"
const TAB_EXPORT := "3d"
const SELECT_REASON := "Select one object to export."

var _doc = null
var _view = null
var _tab := TAB_RENDER
var _built := false
var _tabs: HBoxContainer
var _render_tab: Button
var _export_tab: Button
var _render_page: ScrollContainer
var _export_page: ScrollContainer
var _media_sheet: Control
var _scope_label: Label
var _animations_toggle: Button
var _selection_toggle: Button
var _export_button: Button
var _status_label: Label
var _result_label: Label
var _exported_with_selection := false
var _result_text := ""


func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 0)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 2)
	_tabs.custom_minimum_size.y = 44
	add_child(_tabs)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	_render_tab = Kit.text_toggle("Render")
	_render_tab.button_group = group
	_render_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_render_tab.button_pressed = true
	_render_tab.toggled.connect(func(on: bool) -> void:
		if on:
			set_active_tab(TAB_RENDER)
	)
	_tabs.add_child(_render_tab)
	_export_tab = Kit.text_toggle("3D export")
	_export_tab.button_group = group
	_export_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_export_tab.toggled.connect(func(on: bool) -> void:
		if on:
			set_active_tab(TAB_EXPORT)
	)
	_tabs.add_child(_export_tab)

	_render_page = _make_page()
	var render_margin := _make_margin()
	_render_page.add_child(render_margin)
	var render_box := VBoxContainer.new()
	render_box.add_theme_constant_override("separation", 8)
	render_margin.add_child(render_box)
	_media_sheet = MediaExportSheetScript.new()
	render_box.add_child(_media_sheet)
	add_child(_render_page)

	_export_page = _make_page()
	_export_page.visible = false
	var export_margin := _make_margin()
	_export_page.add_child(export_margin)
	var export_box := VBoxContainer.new()
	export_box.add_theme_constant_override("separation", 10)
	export_margin.add_child(export_box)
	export_box.add_child(Kit.section_label("Scene export"))
	_scope_label = Kit.label("Whole scene", Kit.TYPE_BODY, Kit.TEXT_MUTED)
	_scope_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	export_box.add_child(_scope_label)
	_animations_toggle = Kit.text_toggle("Animations")
	_animations_toggle.button_pressed = true
	_animations_toggle.tooltip_text = "Export the active clip as a real glTF animation."
	export_box.add_child(_animations_toggle)
	_selection_toggle = Kit.text_toggle("Selection only")
	_selection_toggle.tooltip_text = SELECT_REASON
	_selection_toggle.toggled.connect(func(_on: bool) -> void: _update_scope())
	export_box.add_child(_selection_toggle)
	_export_button = Kit.text_button("Export GLB", "download", true, true)
	_export_button.pressed.connect(_on_export_pressed)
	export_box.add_child(_export_button)
	_status_label = Kit.label("", Kit.TYPE_CAPTION, Kit.TEXT_MUTED)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	export_box.add_child(_status_label)
	_result_label = Kit.label("", Kit.TYPE_CAPTION, Kit.TEXT)
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.visible = false
	export_box.add_child(_result_label)
	add_child(_export_page)
	if _doc != null:
		_media_sheet.setup(_doc, _view)
		refresh()


func _make_page() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return scroll


func _make_margin() -> MarginContainer:
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	return margin


func setup(doc, view = null) -> void:
	_ensure_built()
	_doc = doc
	_view = view
	if _media_sheet != null:
		_media_sheet.setup(doc, view)
	refresh()


func set_active_tab(tab: String) -> void:
	_ensure_built()
	var next := TAB_EXPORT if tab == TAB_EXPORT else TAB_RENDER
	_tab = next
	if _render_tab != null:
		_render_tab.set_pressed_no_signal(next == TAB_RENDER)
	if _export_tab != null:
		_export_tab.set_pressed_no_signal(next == TAB_EXPORT)
	if _render_page != null:
		_render_page.visible = next == TAB_RENDER
	if _export_page != null:
		_export_page.visible = next == TAB_EXPORT
	tab_changed.emit(_tab)


func active_tab() -> String:
	return _tab


func export_button() -> Button:
	_ensure_built()
	return _export_button


func result_text() -> String:
	return _result_text


func media_sheet() -> Control:
	_ensure_built()
	return _media_sheet


func scope_text() -> String:
	var selected := _selected_object()
	if _selection_toggle != null and _selection_toggle.button_pressed \
			and not selected.is_empty():
		return "Selected: " + str(selected.get("name", "Object"))
	return "Whole scene"


func selection_toggle() -> Button:
	_ensure_built()
	return _selection_toggle


func animations_toggle() -> Button:
	_ensure_built()
	return _animations_toggle


func current_output() -> String:
	if _tab == TAB_EXPORT:
		return "GLB"
	if _media_sheet != null:
		var current: Variant = _media_sheet.get("_format")
		if current != null:
			return str(current).to_upper()
	return "PNG"


func set_export_status(text: String) -> void:
	_ensure_built()
	if _status_label != null:
		_status_label.text = text
	_result_text = ""
	if _result_label != null:
		_result_label.text = ""
		_result_label.visible = false


func set_export_result(result: Dictionary) -> void:
	_ensure_built()
	if not bool(result.get("ok", false)):
		set_export_status(str(result.get("error", "The GLB export failed.")))
		return
	var path := str(result.get("path", ""))
	var animations := int(result.get("animations", 0))
	var animation_text := "%d animation" % animations
	if animations != 1:
		animation_text = "%d animations" % animations
	if animations == 0 and _exported_with_selection:
		animation_text = "No animation on this selection"
	var parts: Array[String] = [
		path.get_file(),
		_format_bytes(int(result.get("bytes", 0))),
		"%d nodes" % int(result.get("nodes", 0)),
		"%d meshes" % int(result.get("meshes", 0)),
		animation_text,
	]
	_result_text = " · ".join(parts) + "\n" + path
	if _status_label != null:
		_status_label.text = "Export complete."
	if _result_label != null:
		_result_label.text = _result_text
		_result_label.visible = true


func refresh() -> void:
	_ensure_built()
	var selected := _selected_object()
	var valid := not selected.is_empty()
	if _selection_toggle != null:
		_selection_toggle.disabled = not valid
		_selection_toggle.tooltip_text = "" if valid else SELECT_REASON
		if not valid:
			_selection_toggle.set_pressed_no_signal(false)
	_update_scope()


func _update_scope() -> void:
	if _scope_label != null:
		_scope_label.text = scope_text()


func _selected_object() -> Dictionary:
	if _doc == null or str(_doc.selected_id) == "":
		return {}
	return _doc.get_object(str(_doc.selected_id))


func _on_export_pressed() -> void:
	_exported_with_selection = _selection_toggle.button_pressed and not _selection_toggle.disabled
	export_requested.emit({
		"animations": _animations_toggle.button_pressed,
		"selection_only": _exported_with_selection,
	})


func _format_bytes(value: int) -> String:
	if value >= 1024 * 1024:
		return "%.1f MB" % (float(value) / (1024.0 * 1024.0))
	if value >= 1024:
		return "%.1f KB" % (float(value) / 1024.0)
	return "%d B" % value
