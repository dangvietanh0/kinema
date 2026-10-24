extends Control
## Project browser. Restrained technical illustration on one side, projects and
## creation on the other. Everything is local; there is no account surface.

signal new_project_requested(title: String, template: String)
signal open_project_requested(id: String)
signal request_quit

const OverlayScript = preload("res://src/ui/overlay.gd")

class TechnicalIllustration:
	extends Control

	var angle := 0.7
	var _time := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		_time += delta
		angle += delta * 0.45
		queue_redraw()

	func _project(x: float, y: float, z: float) -> Vector2:
		var scale := minf(size.x / 420.0, size.y / 310.0)
		scale = maxf(0.6, scale)
		var iso := Vector2((x - z) * 0.86, (x + z) * 0.5 - y)
		var center := Vector2(size.x * 0.5, size.y * 0.60)
		return center + iso * scale * 60.0

	func _draw_axis_label(text: String, position: Vector2, color: Color) -> void:
		# Keep the axis tags out of the illustration's compact timeline strip.
		var p := Vector2(
			clampf(position.x, 10.0, size.x - 18.0),
			clampf(position.y, 16.0, size.y - 38.0)
		)
		draw_string(Kit.font_mono, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)

	func _draw() -> void:
		var center := Vector2(size.x * 0.5, size.y * 0.5)
		draw_line(Vector2(12, size.y - 26), Vector2(size.x - 12, size.y - 26), Kit.BORDER_SOFT, 1.0)
		draw_string(Kit.font_mono, Vector2(14, size.y - 10), "TAKE 01", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Kit.TEXT_DIM)
		draw_string(Kit.font_mono, Vector2(size.x - 62, size.y - 10), "03.20 SEC", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Kit.TEXT_DIM)
		var timeline_left := 74.0
		var timeline_right := size.x - 74.0
		var timeline_y := size.y - 18.0
		if timeline_right > timeline_left:
			draw_line(Vector2(timeline_left, timeline_y), Vector2(timeline_right, timeline_y), Kit.BORDER, 1.0)
			for i in range(9):
				var t := float(i) / 8.0
				var x := lerpf(timeline_left, timeline_right, t)
				draw_line(Vector2(x, timeline_y - 3), Vector2(x, timeline_y + 3), Kit.BORDER, 1.0)
			var play_x := lerpf(timeline_left, timeline_right, 0.54)
			draw_line(Vector2(play_x, timeline_y - 7), Vector2(play_x, timeline_y + 5), Kit.ACCENT, 1.2)
			draw_colored_polygon(PackedVector2Array([Vector2(play_x - 3, timeline_y - 9), Vector2(play_x + 3, timeline_y - 9), Vector2(play_x, timeline_y - 5)]), Kit.ACCENT)

		# Floor grid and construction axes.
		var grid_color := Color(Kit.BORDER_SOFT, 0.75)
		for i in range(-3, 4):
			var f := float(i)
			draw_line(_project(f, 0, -3), _project(f, 0, 3), grid_color, 1.0)
			draw_line(_project(-3, 0, f), _project(3, 0, f), grid_color, 1.0)
		draw_line(_project(-3.4, 0, 0), _project(3.4, 0, 0), Color(0.38, 0.22, 0.20), 1.0)
		draw_line(_project(0, 0, -3.4), _project(0, 0, 3.4), Color(0.20, 0.27, 0.42), 1.0)
		draw_line(_project(0, 0, 0), _project(0, 2.6, 0), Color(0.30, 0.38, 0.28), 1.0)
		_draw_axis_label("X", _project(3.6, 0, 0), Kit.AXIS_X)
		_draw_axis_label("Y", _project(0, 2.8, 0), Kit.AXIS_Y)
		_draw_axis_label("Z", _project(0, 0, 3.6), Kit.AXIS_Z)

		# Pedestal.
		var base_center := _project(0, 0.08, 0)
		var base_scale := maxf(0.6, minf(size.x / 420.0, size.y / 310.0)) * 60.0
		draw_set_transform(base_center, 0.0, Vector2(1.0, 0.38))
		draw_circle(Vector2.ZERO, 1.7 * base_scale, Color(0.10, 0.125, 0.16, 1.0))
		draw_arc(Vector2.ZERO, 1.7 * base_scale, 0.0, TAU, 72, Kit.BORDER, 1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# A restrained primitive study: sphere, orbit and three keys.
		var sphere_center := _project(0, 1.1, 0)
		var sphere_r := maxf(12.0, base_scale * 0.55)
		draw_circle(sphere_center, sphere_r, Color(0.14, 0.16, 0.18, 1.0))
		draw_arc(sphere_center, sphere_r, 0.0, TAU, 72, Kit.TEXT_MUTED, 1.2, true)
		draw_set_transform(sphere_center, 0.0, Vector2(1.0, 0.35))
		draw_arc(Vector2.ZERO, sphere_r, 0.0, TAU, 72, Color(Kit.TEXT_DIM, 0.8), 1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		var orbit_center := _project(0, 1.15, 0)
		var orbit_scale := maxf(0.6, minf(size.x / 420.0, size.y / 310.0)) * 60.0
		var orbit_pts := PackedVector2Array()
		for i in range(65):
			var a := TAU * float(i) / 64.0
			var p := _project(cos(a) * 1.55, 1.15 + sin(a) * 0.22, sin(a) * 1.55)
			orbit_pts.append(p)
		draw_polyline(orbit_pts, Kit.ACCENT * Color(1, 1, 1, 0.65), 1.2, true)
		var dot := _project(cos(angle) * 1.55, 1.15 + sin(angle) * 0.22, sin(angle) * 1.55)
		draw_circle(dot, 3.0, Kit.ACCENT_BRIGHT)
		draw_circle(dot, 6.5, Color(Kit.ACCENT, 0.16))

		# A small wireframe cube and dimension marks to explain the layout.
		var cube_origin := _project(-2.25, 0.45, -0.9)
		var cs := orbit_scale * 0.30
		var cube_pts := [
			Vector2(cube_origin.x - cs, cube_origin.y),
			Vector2(cube_origin.x, cube_origin.y - cs * 0.45),
			Vector2(cube_origin.x + cs, cube_origin.y),
			Vector2(cube_origin.x, cube_origin.y + cs * 0.45),
			Vector2(cube_origin.x - cs, cube_origin.y - cs),
			Vector2(cube_origin.x, cube_origin.y - cs * 1.45),
			Vector2(cube_origin.x + cs, cube_origin.y - cs),
			Vector2(cube_origin.x, cube_origin.y - cs * 0.55),
		]
		var edges := [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]
		for edge in edges:
			draw_line(cube_pts[edge[0]], cube_pts[edge[1]], Kit.ACCENT * Color(1, 1, 1, 0.55), 1.0, true)

		var top := _project(0, 1.66, 0)
		var bottom := _project(0, 0.08, 0)
		draw_dashed_line(top + Vector2(20, 0), bottom + Vector2(20, 0), Kit.BORDER, 1.0, 3.0, true)
		draw_line(top + Vector2(16, 0), top + Vector2(24, 0), Kit.TEXT_DIM, 1.0)
		draw_line(bottom + Vector2(16, 0), bottom + Vector2(24, 0), Kit.TEXT_DIM, 1.0)
		draw_string(Kit.font_mono, Vector2(top.x + 28, (top.y + bottom.y) * 0.5), "1.52", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Kit.TEXT_DIM)

		# Corner marks, deliberately quiet.
		var c := 10.0
		draw_line(Vector2(12, 12), Vector2(12 + c, 12), Kit.BORDER, 1.0)
		draw_line(Vector2(12, 12), Vector2(12, 12 + c), Kit.BORDER, 1.0)
		draw_line(Vector2(size.x - 12, 12), Vector2(size.x - 12 - c, 12), Kit.BORDER, 1.0)
		draw_line(Vector2(size.x - 12, 12), Vector2(size.x - 12, 12 + c), Kit.BORDER, 1.0)
		draw_string(Kit.font_mono, Vector2(16, 28), "PRIMITIVE STUDY / FORM + ORBIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Kit.TEXT_DIM)
		var frame_text := "FRAME %03d" % (int(_time * 24.0) % 240)
		draw_string(Kit.font_mono, Vector2(size.x - 86, 28), frame_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Kit.TEXT_DIM)
		draw_circle(Vector2(center.x, 12), 2.0, Kit.SUCCESS)

var _overlay: Control
var _top: PanelContainer
var _scroll: ScrollContainer
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
	_scroll.offset_top = 52
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_scroll)
	_overlay = OverlayScript.new()
	add_child(_overlay)
	Store.recents_changed.connect(_rebuild_content)
	resized.connect(_on_resized)
	_rebuild_content()

func _build_top() -> void:
	_top = PanelContainer.new()
	var style := Kit.flat_style(Kit.BG, 0, Kit.BORDER_SOFT, 0)
	style.border_width_bottom = 1
	style.content_margin_left = 18
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_top.add_theme_stylebox_override("panel", style)
	_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top.custom_minimum_size.y = 52
	add_child(_top)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_top.add_child(row)

	var mark := PanelContainer.new()
	mark.custom_minimum_size = Vector2(30, 30)
	mark.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_3, 6, Kit.ACCENT * Color(1, 1, 1, 0.42), 1))
	row.add_child(mark)
	var mark_label := Kit.mono_label("K", 15, Kit.ACCENT)
	mark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_child(mark_label)

	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 0)
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(brand)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 5)
	brand.add_child(name_row)
	name_row.add_child(Kit.label("KINEMA", 13, Kit.TEXT, 600))
	name_row.add_child(Kit.label("STUDIO", 13, Kit.TEXT_DIM, 500))
	brand.add_child(Kit.label("Touch-first 3D animation", 9, Kit.TEXT_DIM))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var local_chip := PanelContainer.new()
	local_chip.add_theme_stylebox_override("panel", Kit.flat_style(Color(0, 0, 0, 0), 4, Kit.BORDER_SOFT, 1))
	local_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(local_chip)
	var chip_margin := MarginContainer.new()
	chip_margin.add_theme_constant_override("margin_left", 7)
	chip_margin.add_theme_constant_override("margin_right", 7)
	chip_margin.add_theme_constant_override("margin_top", 3)
	chip_margin.add_theme_constant_override("margin_bottom", 3)
	local_chip.add_child(chip_margin)
	chip_margin.add_child(Kit.mono_label("LOCAL", 8, Kit.TEXT_DIM))

	var about := Kit.icon_button("info", "About Kinema", 30, 15)
	about.pressed.connect(_show_about)
	row.add_child(about)

func _on_resized() -> void:
	var wide := size.x >= 860.0
	if wide != _wide or _layout == null:
		_wide = wide
		_rebuild_content()

func _rebuild_content() -> void:
	if _scroll == null or not is_inside_tree():
		return
	var scroll_pos := _scroll.scroll_vertical if _scroll != null else 0
	for child in _scroll.get_children():
		_scroll.remove_child(child)
		child.queue_free()
	_layout = null
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 24 if _wide else 16)
	margin.add_theme_constant_override("margin_right", 24 if _wide else 16)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 30)
	_scroll.add_child(margin)

	if _wide:
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", 34)
		cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.add_child(cols)
		var left := VBoxContainer.new()
		left.add_theme_constant_override("separation", 18)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.size_flags_stretch_ratio = 1.08
		cols.add_child(left)
		_build_hero(left, 40)
		_build_recent(left)
		var right := VBoxContainer.new()
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.size_flags_stretch_ratio = 0.92
		cols.add_child(right)
		_build_illustration(right, 480)
		_build_footer(right)
		_layout = cols
	else:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 18)
		margin.add_child(column)
		_build_hero(column, 32)
		_build_illustration(column, 220)
		_build_recent(column)
		_build_footer(column)
		_layout = column
	await get_tree().process_frame
	_scroll.scroll_vertical = scroll_pos

func _build_hero(parent: Control, title_size: int) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	parent.add_child(box)

	var tag := HBoxContainer.new()
	tag.add_theme_constant_override("separation", 6)
	box.add_child(tag)
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", Kit.flat_style(Color(0, 0, 0, 0), 4, Kit.BORDER, 1))
	tag.add_child(pill)
	var pill_margin := MarginContainer.new()
	pill_margin.add_theme_constant_override("margin_left", 7)
	pill_margin.add_theme_constant_override("margin_right", 7)
	pill_margin.add_theme_constant_override("margin_top", 2)
	pill_margin.add_theme_constant_override("margin_bottom", 2)
	pill.add_child(pill_margin)
	pill_margin.add_child(Kit.mono_label("3D ANIMATION", 8, Kit.ACCENT))
	tag.add_child(Kit.mono_label("BUILD 0.1", 8, Kit.TEXT_DIM))

	var title := Kit.label("Motion,\nwithout the noise.", title_size, Kit.TEXT, 600)
	title.add_theme_constant_override("line_spacing", -2)
	box.add_child(title)
	var sub := Kit.label("A focused place to block, pose and preview animation with your hands. Built on the Godot renderer and made for touch first.", 12, Kit.TEXT_MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = 300
	box.add_child(sub)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	var new_button := Kit.text_button("New project", "plus", true)
	new_button.custom_minimum_size = Vector2(150, 40)
	new_button.pressed.connect(_open_new_project_sheet)
	actions.add_child(new_button)
	var manual := Kit.text_button("Quick start", "clapperboard", false)
	manual.custom_minimum_size = Vector2(132, 40)
	manual.pressed.connect(func() -> void: new_project_requested.emit("Primitive Study", "study"))
	actions.add_child(manual)

	var note := Kit.label("No account. Project files stay inside the app.", 9, Kit.TEXT_DIM)
	box.add_child(note)

func _build_recent(parent: Control) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	parent.add_child(section)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	section.add_child(header)
	header.add_child(Kit.section_label("Recent projects"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var recents := Store.recent_projects()
	header.add_child(Kit.mono_label(str(recents.size()), 9, Kit.TEXT_DIM))

	if recents.is_empty():
		var empty := PanelContainer.new()
		var empty_style := Kit.flat_style(Kit.SURFACE, 7, Kit.BORDER_SOFT, 1)
		empty_style.content_margin_left = 16
		empty_style.content_margin_right = 16
		empty_style.content_margin_top = 18
		empty_style.content_margin_bottom = 18
		empty.add_theme_stylebox_override("panel", empty_style)
		section.add_child(empty)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 5)
		empty.add_child(inner)
		inner.add_child(Kit.label("No projects yet", 13, Kit.TEXT, 600))
		var hint := Kit.label("Start with a blank stage, or press Quick start to load the primitive study.", 10, Kit.TEXT_MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inner.add_child(hint)
		var create := Kit.text_button("Create a project", "plus", false, true)
		create.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		create.pressed.connect(_open_new_project_sheet)
		inner.add_child(create)
		return

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	section.add_child(list)
	for entry in recents:
		list.add_child(_recent_row(entry))

func _recent_row(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 54
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel", _recent_style(false))
	panel.mouse_entered.connect(func() -> void: panel.add_theme_stylebox_override("panel", _recent_style(true)))
	panel.mouse_exited.connect(func() -> void: panel.add_theme_stylebox_override("panel", _recent_style(false)))
	var id := str(entry.get("id", ""))
	Kit.bind_tap(panel, _on_recent_tapped.bind(id))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(34, 34)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_3, 5, Kit.BORDER_SOFT, 1))
	row.add_child(icon_box)
	var icon_center := CenterContainer.new()
	icon_box.add_child(icon_center)
	icon_center.add_child(Kit.icon("clapperboard", Kit.ACCENT, 15))
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	info.add_child(Kit.label(str(entry.get("title", "Untitled")), 12, Kit.TEXT, 500))
	var objects := int(entry.get("objects", 0))
	var dur := float(entry.get("duration", 0.0))
	var meta := "%d object%s · %.1fs · %s" % [objects, "" if objects == 1 else "s", dur, _relative_time(float(entry.get("modified", 0.0)))]
	info.add_child(Kit.label(meta, 9, Kit.TEXT_DIM))
	var menu := Kit.icon_button("ellipsis-vertical", "Project actions", 28, 14)
	menu.pressed.connect(_open_project_menu.bind(entry))
	row.add_child(menu)
	return panel

func _recent_style(hover: bool) -> StyleBoxFlat:
	var style := Kit.flat_style(Kit.SURFACE_2 if hover else Kit.SURFACE, 6, Kit.BORDER_SOFT if hover else Color(0, 0, 0, 0), 1)
	style.content_margin_left = 10
	style.content_margin_right = 8
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

func _build_illustration(parent: Control, min_height: float) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = min_height
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_2, 8, Kit.BORDER_SOFT, 1))
	parent.add_child(panel)

	var art := TechnicalIllustration.new()
	art.custom_minimum_size.y = min_height - 2
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(art)

func _build_footer(parent: Control) -> void:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	parent.add_child(footer)
	var version := Engine.get_version_info()
	footer.add_child(Kit.mono_label("KINEMA 0.1 · GODOT %s" % str(version.get("string", "4.x")), 8, Kit.TEXT_DIM))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var about := Kit.text_button("About", "info", false, true)
	about.pressed.connect(_show_about)
	footer.add_child(about)

# -------------------------------------------------------------------------
# Sheets
# -------------------------------------------------------------------------

func _open_new_project_sheet() -> void:
	_template_choice = "blank"
	_template_cards.clear()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	var name_label := Kit.section_label("Project name")
	body.add_child(name_label)
	var name_field := Kit.line_edit("Untitled Project")
	name_field.text = "Untitled Project"
	name_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	body.add_child(name_field)
	_name_field = name_field
	var template_label := Kit.section_label("Start from")
	body.add_child(template_label)
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
	panel.custom_minimum_size.y = 58
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
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	col.add_child(Kit.label(title, 12, Kit.TEXT, 500))
	var desc := Kit.label(description, 9, Kit.TEXT_MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc)
	_template_cards[id] = panel
	return panel

func _template_style(active: bool) -> StyleBoxFlat:
	var style := Kit.flat_style(Kit.SURFACE_3 if active else Kit.SURFACE_2, 6, Kit.FOCUS if active else Kit.BORDER_SOFT, 1)
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
	var intro := Kit.label("Kinema Studio is a small, local-first 3D animation workspace for touch screens. It uses the Godot 4.7 renderer, animation system and scene runtime as its foundation.", 11, Kit.TEXT_MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(intro)
	body.add_child(Kit.vsep())
	body.add_child(_info_row("Version", "0.1"))
	body.add_child(_info_row("Engine", _engine_version()))
	body.add_child(_info_row("Renderer", Gfx.display_name()))
	body.add_child(_info_row("Storage", "On-device app storage only"))
	body.add_child(Kit.vsep())
	var limits := Kit.label("Import: glTF and OBJ. Binary FBX needs conversion to GLB or OBJ because Godot's FBX importer is editor-only. On Android, an OBJ may not resolve sibling MTL/texture files through SAF. Export: PNG stills and ZIP frame sequences; MP4 encoding is not included.", 9, Kit.TEXT_DIM)
	limits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(limits)
	var note := Kit.label("Fonts: Inter and JetBrains Mono (SIL OFL). Icons: Lucide (ISC). Both are bundled with their licenses.", 9, Kit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	_overlay.show_modal("About Kinema", "A quiet tool for motion.", body, [{"text": "Close", "primary": true}])

func _info_row(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Kit.label(key, 10, Kit.TEXT_DIM)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(label)
	var value_label := Kit.mono_label(value, 9, Kit.TEXT_MUTED)
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

