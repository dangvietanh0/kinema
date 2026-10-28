extends Control
## Project browser. A calm, local project list with one primary action.
##
## This is a tool screen, not a landing page: a page title, the projects that
## exist on this device, and a single obvious way to make another one. No
## marketing hero, no decorative illustration, no badges.

signal new_project_requested(title: String, template: String)
signal open_project_requested(id: String)
signal request_quit

const OverlayScript = preload("res://src/ui/overlay.gd")

const PAGE_MAX_WIDTH := 980.0
const ROW_HEIGHT := 44.0
const WIDE_MIN_WIDTH := 720.0

var _overlay: Control
var _top: PanelContainer
var _scroll: ScrollContainer
var _outer: MarginContainer
var _layout: Control
var _wide := true
var _template_choice := "blank"
var _template_cards: Dictionary = {}
var _name_field: LineEdit

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Kit.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build_top()
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = 48
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	Kit.style_scroll_container(_scroll)
	add_child(_scroll)
	_overlay = OverlayScript.new()
	add_child(_overlay)
	Store.recents_changed.connect(_rebuild_content)
	resized.connect(_on_resized)
	# Resolve the breakpoint from the real size before the first build so the
	# wide table never flashes on a phone.
	_on_resized()

func _build_top() -> void:
	_top = PanelContainer.new()
	var style := Kit.flat_style(Kit.SURFACE_2, Kit.R_PANEL, Color(0, 0, 0, 0), 0)
	style.content_margin_left = 20
	style.content_margin_right = 12
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	_top.add_theme_stylebox_override("panel", style)
	_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top.custom_minimum_size.y = 48
	add_child(_top)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_top.add_child(row)

	var mark := PanelContainer.new()
	mark.custom_minimum_size = Vector2(30, 30)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_3, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	row.add_child(mark)
	var mark_label := Kit.mono_label("K", Kit.TYPE_EMPHASIS, Kit.TEXT)
	mark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_child(mark_label)

	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 5)
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(brand)
	brand.add_child(Kit.label("KINEMA", Kit.TYPE_EMPHASIS, Kit.TEXT, 600))
	brand.add_child(Kit.label("STUDIO", Kit.TYPE_EMPHASIS, Kit.TEXT_DIM, 500))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var about := Kit.icon_button("info", "About Kinema", 44, 18)
	about.pressed.connect(_show_about)
	row.add_child(about)

func _on_resized() -> void:
	var wide := size.x >= WIDE_MIN_WIDTH
	if wide != _wide or _layout == null:
		_wide = wide
		_rebuild_content()
	else:
		_apply_page_margins()

## The browser is a list on phones and a table with metadata columns once the
## width can afford them. Public so the layout matrix can assert the breakpoint
## without depending on the live window.
func layout_for_width(width: float) -> String:
	return "table" if width >= WIDE_MIN_WIDTH else "list"

func _apply_page_margins() -> void:
	if _outer == null:
		return
	var side := _page_side_inset()
	_outer.add_theme_constant_override("margin_left", side)
	_outer.add_theme_constant_override("margin_right", side)

func _page_side_inset() -> int:
	var base := 20 if _wide else 16
	if not _wide:
		return base
	return int(round(maxf(float(base), (size.x - PAGE_MAX_WIDTH) * 0.5)))

func _rebuild_content() -> void:
	if _scroll == null or not is_inside_tree():
		return
	var scroll_pos := _scroll.scroll_vertical
	for child in _scroll.get_children():
		_scroll.remove_child(child)
		child.queue_free()
	_layout = null
	_outer = null

	var outer := MarginContainer.new()
	_outer = outer
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var side := _page_side_inset()
	outer.add_theme_constant_override("margin_left", side)
	outer.add_theme_constant_override("margin_right", side)
	outer.add_theme_constant_override("margin_top", 24)
	outer.add_theme_constant_override("margin_bottom", 24)
	_scroll.add_child(outer)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(column)

	_build_page_header(column)
	_build_projects(column)
	_build_footer(column)
	_layout = column
	await get_tree().process_frame
	_scroll.scroll_vertical = scroll_pos

func _build_page_header(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(titles)
	var title := Kit.label("Projects", Kit.TYPE_PAGE, Kit.TEXT, 600)
	titles.add_child(title)
	titles.add_child(Kit.label("Local projects on this device", Kit.TYPE_BODY, Kit.TEXT_MUTED))

	var new_button := Kit.text_button("New project", "plus", true)
	new_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	new_button.pressed.connect(_open_new_project_sheet)
	row.add_child(new_button)

func _build_projects(parent: Control) -> void:
	var recents := Store.recent_projects()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE, 0, Color(0, 0, 0, 0), 0))
	parent.add_child(panel)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 0)
	panel.add_child(list)

	if recents.is_empty():
		_build_empty_state(list)
		return

	if _wide:
		list.add_child(_column_header())
	for i in range(recents.size()):
		list.add_child(_recent_row(recents[i], i == recents.size() - 1))

func _column_header() -> Control:
	var panel := PanelContainer.new()
	var style := Kit.flat_style(Kit.SURFACE_2, 0, Kit.BORDER_SOFT, 0)
	style.border_width_bottom = 1
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.y = 36

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	row.add_child(Kit.gap(32))
	var name := Kit.section_label("Name")
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name)
	row.add_child(_column_label("Objects", 84))
	row.add_child(_column_label("Duration", 84))
	row.add_child(_column_label("Modified", 132))
	row.add_child(Kit.gap(44))
	return panel

func _column_label(text_value: String, width: float) -> Label:
	var label := Kit.section_label(text_value)
	label.custom_minimum_size.x = width
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label

func _build_empty_state(parent: Control) -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	parent.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	margin.add_child(inner)
	inner.add_child(Kit.label("No projects yet", Kit.TYPE_TITLE, Kit.TEXT, 500))
	var hint := Kit.label("Start a blank stage, or load the primitive study to see keys and playback in place.", Kit.TYPE_BODY, Kit.TEXT_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(hint)
	var create := Kit.text_button("New project", "plus", false)
	create.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	create.custom_minimum_size.y = 44
	create.pressed.connect(_open_new_project_sheet)
	inner.add_child(create)

func _recent_row(entry: Dictionary, last: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = ROW_HEIGHT
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel", _recent_style(false, last))
	panel.mouse_entered.connect(func() -> void: panel.add_theme_stylebox_override("panel", _recent_style(true, last)))
	panel.mouse_exited.connect(func() -> void: panel.add_theme_stylebox_override("panel", _recent_style(false, last)))
	var id := str(entry.get("id", ""))
	Kit.bind_tap(panel, _on_recent_tapped.bind(id))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(32, 32)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_3, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	row.add_child(icon_box)
	var icon_center := CenterContainer.new()
	icon_box.add_child(icon_center)
	# A cube reads as a 3D scene; a clapperboard reads as a video file.
	icon_center.add_child(Kit.icon("box", Kit.TEXT_MUTED, 15))

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	var name_label := Kit.label(str(entry.get("title", "Untitled")), Kit.TYPE_EMPHASIS, Kit.TEXT, 500)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	info.add_child(name_label)

	var objects := int(entry.get("objects", 0))
	var dur := float(entry.get("duration", 0.0))
	var modified := _relative_time(float(entry.get("modified", 0.0)))
	if _wide:
		row.add_child(_value_label("%d" % objects, 84))
		row.add_child(_value_label("%.1fs" % dur, 84))
		row.add_child(_value_label(modified, 132))
	else:
		var meta := "%d object%s · %.1fs · %s" % [objects, "" if objects == 1 else "s", dur, modified]
		var meta_label := Kit.label(meta, Kit.TYPE_CAPTION, Kit.TEXT_DIM)
		meta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		meta_label.clip_text = true
		info.add_child(meta_label)

	var menu := Kit.icon_button("ellipsis-vertical", "Project actions", 44, 16)
	menu.pressed.connect(_open_project_menu.bind(entry))
	row.add_child(menu)
	return panel

func _value_label(text_value: String, width: float) -> Label:
	var label := Kit.mono_label(text_value, Kit.TYPE_MONO, Kit.TEXT_MUTED)
	label.custom_minimum_size.x = width
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	return label

func _recent_style(hover: bool, _last: bool) -> StyleBoxFlat:
	# Project rows are separated by spacing and hover fill, not by a rule per
	# row. The only rule in the list is under the column header.
	var style := Kit.flat_style(Kit.SURFACE_2 if hover else Color(0, 0, 0, 0), Kit.R_PANEL, Color(0, 0, 0, 0), 0)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style

func _build_footer(parent: Control) -> void:
	var version := Engine.get_version_info()
	var version_text := "KINEMA 0.1 · GODOT %s" % str(version.get("string", "4.x"))
	var stored_text := "Stored on this device"
	if _wide:
		var footer := HBoxContainer.new()
		footer.add_theme_constant_override("separation", 12)
		parent.add_child(footer)
		footer.add_child(Kit.mono_label(version_text, Kit.TYPE_MONO, Kit.TEXT_DIM))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(spacer)
		footer.add_child(Kit.label(stored_text, Kit.TYPE_CAPTION, Kit.TEXT_DIM))
	else:
		# A phone footer is a stack, not a race for horizontal space. Sharing one
		# row clipped the version string on a 412 dp canvas.
		var footer := VBoxContainer.new()
		footer.add_theme_constant_override("separation", 3)
		parent.add_child(footer)
		footer.add_child(Kit.mono_label(version_text, Kit.TYPE_MONO, Kit.TEXT_DIM))
		footer.add_child(Kit.label(stored_text, Kit.TYPE_CAPTION, Kit.TEXT_DIM))

# -------------------------------------------------------------------------
# Sheets
# -------------------------------------------------------------------------

func _open_new_project_sheet() -> void:
	_template_choice = "blank"
	_template_cards.clear()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.add_child(Kit.section_label("Project name"))
	var name_field := Kit.line_edit("Untitled Project")
	name_field.text = "Untitled Project"
	name_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	body.add_child(name_field)
	_name_field = name_field
	body.add_child(Kit.section_label("Start from"))
	var cards := VBoxContainer.new()
	cards.add_theme_constant_override("separation", 6)
	body.add_child(cards)
	cards.add_child(_template_card("blank", "Blank stage", "Camera, key light and a neutral cube.", "box"))
	cards.add_child(_template_card("study", "Primitive study", "A short looping form-and-orbit study with keys.", "torus"))
	_overlay.show_modal("New project", "Create a local project. You can rename it at any time.", body, [
		{"text": "Cancel", "compact": true},
		{
			"text": "Create project",
			"primary": true,
			"callback": _create_project_from_sheet,
		},
	])
	await get_tree().process_frame
	name_field.grab_focus()
	name_field.select_all()

func _create_project_from_sheet() -> void:
	var title := "Untitled Project"
	if is_instance_valid(_name_field):
		title = _name_field.text.strip_edges()
		if title == "":
			title = "Untitled Project"
	new_project_requested.emit(title, _template_choice)

func _template_card(id: String, title: String, description: String, icon_name: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 64
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel", _template_style(id == _template_choice))
	Kit.bind_tap(panel, _on_template_tapped.bind(id))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var icon_center := CenterContainer.new()
	icon_center.custom_minimum_size = Vector2(30, 30)
	row.add_child(icon_center)
	icon_center.add_child(Kit.icon(icon_name, Kit.FOCUS_BRIGHT if id == _template_choice else Kit.TEXT_MUTED, 17))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	col.add_child(Kit.label(title, Kit.TYPE_BODY, Kit.TEXT, 500))
	var desc := Kit.label(description, Kit.TYPE_CAPTION, Kit.TEXT_MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc)
	_template_cards[id] = panel
	return panel

func _template_style(active: bool) -> StyleBoxFlat:
	var style := Kit.flat_style(Kit.SURFACE_ACTIVE if active else Kit.SURFACE_2, Kit.R_CONTROL, Kit.FOCUS if active else Kit.BORDER_SOFT, 1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _on_recent_tapped(id: String) -> void:
	open_project_requested.emit(id)

func _on_template_tapped(id: String) -> void:
	_template_choice = id
	_refresh_template_cards()

func _refresh_template_cards() -> void:
	for id in _template_cards:
		var card: Control = _template_cards[id]
		if card != null:
			card.add_theme_stylebox_override("panel", _template_style(str(id) == _template_choice))
			var row := card.get_child(0) as HBoxContainer
			if row != null:
				var center := row.get_child(0) as CenterContainer
				var icon := center.get_child(0) as TextureRect
				icon.modulate = Kit.FOCUS_BRIGHT if str(id) == _template_choice else Kit.TEXT_MUTED

func _open_project_menu(entry: Dictionary) -> void:
	var id := str(entry.get("id", ""))
	var title := str(entry.get("title", "Untitled"))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	var open := Kit.text_button("Open project", "folder", false, true)
	open.alignment = HORIZONTAL_ALIGNMENT_LEFT
	open.pressed.connect(func() -> void:
		_overlay.close_modal()
		open_project_requested.emit(id)
	)
	body.add_child(open)
	var rename := Kit.text_button("Rename", "type", false, true)
	rename.alignment = HORIZONTAL_ALIGNMENT_LEFT
	rename.pressed.connect(func() -> void:
		_overlay.close_modal()
		_overlay.prompt("Rename project", "The project folder stays in place.", title, "Project name", func(new_title: String) -> void:
			if Store.rename_project(id, new_title):
				_overlay.toast("Project renamed")
			else:
				_overlay.toast("Could not rename this project", "triangle-alert", Kit.DANGER)
		)
	)
	body.add_child(rename)
	var delete := Kit.text_button("Delete project", "trash-2", false, true)
	delete.alignment = HORIZONTAL_ALIGNMENT_LEFT
	delete.add_theme_color_override("font_color", Kit.DANGER)
	delete.add_theme_color_override("icon_normal_color", Kit.DANGER)
	delete.pressed.connect(func() -> void:
		_overlay.close_modal()
		_overlay.confirm("Delete project?", "“%s” and its imported models will be permanently removed from this device." % title, "Delete", func() -> void:
			if Store.delete_project(id):
				_overlay.toast("Project deleted")
			else:
				_overlay.toast("Could not delete this project", "triangle-alert", Kit.DANGER)
		)
	)
	body.add_child(delete)
	_overlay.show_modal(title, "Project actions", body)

func _show_about() -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var intro := Kit.label("Kinema Studio is a local-first 3D animation workspace for touch screens, built on the Godot renderer and animation system.", Kit.TYPE_BODY, Kit.TEXT_MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(intro)
	body.add_child(Kit.vsep())
	body.add_child(_info_row("Version", "0.1"))
	body.add_child(_info_row("Engine", _engine_version()))
	body.add_child(_info_row("Renderer", Gfx.display_name()))
	body.add_child(_info_row("Storage", "On-device app storage only"))
	body.add_child(Kit.vsep())
	var limits := Kit.label("Import: glTF and OBJ. Binary FBX needs conversion to GLB or OBJ because Godot's FBX importer is editor-only. On Android, an OBJ may not resolve sibling MTL/texture files through SAF. Export: PNG stills and ZIP frame sequences; MP4 encoding is not included.", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	limits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(limits)
	var note := Kit.label("Fonts: IBM Plex Sans and IBM Plex Mono (SIL OFL). Icons: Lucide (ISC). Both are bundled with their licenses.", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	_overlay.show_modal("About Kinema", "Local-first 3D animation", body, [{"text": "Close", "primary": true}])

func _info_row(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Kit.label(key, Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(label)
	var value_label := Kit.mono_label(value, Kit.TYPE_MONO, Kit.TEXT_MUTED)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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

func _relative_time(timestamp: float) -> String:
	if timestamp <= 0.0:
		return "unknown"
	var delta := maxf(0.0, Time.get_unix_time_from_system() - timestamp)
	if delta < 45.0:
		return "just now"
	if delta < 3600.0:
		return "%d min ago" % int(delta / 60.0)
	if delta < 86400.0:
		return "%d h ago" % int(delta / 3600.0)
	if delta < 7.0 * 86400.0:
		return "%d d ago" % int(delta / 86400.0)
	return Time.get_date_string_from_unix_time(int(timestamp))

# -------------------------------------------------------------------------
# Public hooks for the application shell
# -------------------------------------------------------------------------

func notify_error(message: String) -> void:
	if _overlay != null:
		_overlay.toast(message, "triangle-alert", Kit.DANGER)

func handle_back() -> bool:
	if _overlay != null and _overlay.has_modal():
		_overlay.close_modal()
		return true
	return false

func refresh() -> void:
	_rebuild_content()
