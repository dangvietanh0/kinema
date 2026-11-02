extends VBoxContainer
## Flat scene outliner with search, visibility toggles and animation markers.
##
## Imported glTF/GLB objects can be expanded into the Node3D tree of their
## generated model. The tree is derived from the live document on every
## rebuild; only the expansion state lives here, and it is never serialised.

signal add_requested
signal collapse_toggled(collapsed: bool)
## The persistent scene column collapses to its rail rather than folding the
## list inside a dock page.
signal panel_collapse_requested

const DocumentScript = preload("res://src/core/document.gd")
var doc: DocumentScript = null

const ROW_HEIGHT := 44.0
const ROW_GAP := 1.0
const LIST_TOP := 6.0
const LIST_BOTTOM := 10.0
## Import children indent by 12 dp per level. Deeper levels keep the indent;
## the name label truncates instead of pushing the eye control out.
const PART_INDENT := 12.0
const KEY_SEP := "\u001f"

var _list: VBoxContainer
var _scroll: ScrollContainer
var _bottom_guard: Control
var _count: Label
var _search: LineEdit
var _search_margin: MarginContainer
var _rule: ColorRect
var _header_margin: MarginContainer
var _collapse_button: Button
var _empty: VBoxContainer
## Root rows by object id. Part rows use a root-id + path key so the same path
## on two imports cannot collide.
var _rows: Dictionary = {}
var _part_rows: Dictionary = {}
## One derived part list per import root for the current rebuild. Part rows and
## row refreshes read this instead of re-walking the live model per row.
var _parts_by_root: Dictionary = {}
## UI-only expansion state: object ids for roots, root id + path for parts.
var _expanded: Dictionary = {}
var _identity := ""
var _filter := ""
## Collapsing keeps the section header and its controls, and gives the rest of
## the dock back to the other panel. The editor owns persistence.
var collapsed := false
## True while the outliner is mounted in the persistent scene column. The
## header chevron then collapses the whole column to its rail; the dock keeps
## the old list-fold behaviour.
var persistent_panel := false
## Rebuild counter for diagnostics and the smoke suite.
var rebuild_count := 0

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)
	_build()

func setup(document: Node3D) -> void:
	doc = document
	doc.scene_changed.connect(_on_scene_changed)
	doc.selection_changed.connect(_on_selection_changed)
	doc.object_changed.connect(_on_object_changed)
	doc.part_selection_changed.connect(_on_part_selection_changed)
	# Transform edits change values, not rows: the outliner ignores them.
	doc.keyframes_changed.connect(_on_keyframes_changed)
	_rebuild()

func _build() -> void:
	if _list != null:
		return
	var header_margin := MarginContainer.new()
	_header_margin = header_margin
	header_margin.add_theme_constant_override("margin_left", 12)
	header_margin.add_theme_constant_override("margin_right", 8)
	header_margin.add_theme_constant_override("margin_top", 10)
	header_margin.add_theme_constant_override("margin_bottom", 6)
	add_child(header_margin)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header_margin.add_child(header)
	var title := Kit.section_label("Scene")
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	_count = Kit.label("0", 10, Kit.TEXT_DIM, 500)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_count)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var add := Kit.icon_button("plus", "Add object", 26, 14)
	add.pressed.connect(func() -> void: add_requested.emit())
	header.add_child(add)
	_collapse_button = Kit.icon_button("chevron-up", "Collapse the scene list", 44, 18)
	_collapse_button.pressed.connect(_on_collapse_pressed)
	header.add_child(_collapse_button)

	var search_margin := MarginContainer.new()
	_search_margin = search_margin
	search_margin.add_theme_constant_override("margin_left", 10)
	search_margin.add_theme_constant_override("margin_right", 10)
	search_margin.add_theme_constant_override("margin_bottom", 8)
	add_child(search_margin)
	_search = Kit.line_edit("Search scene", Kit.TYPE_EMPHASIS)
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search_changed)
	search_margin.add_child(_search)

	var rule := Kit.vsep()
	_rule = rule
	add_child(rule)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	Kit.style_scroll_container(_scroll)
	add_child(_scroll)
	_scroll.resized.connect(_schedule_fit_rows)

	# The list clips at the viewport edge. Rounding the viewport down to whole
	# rows keeps the last visible row intact instead of showing a sliver of the
	# next one against the panel hairline.
	_bottom_guard = Control.new()
	_bottom_guard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bottom_guard)

	var list_margin := MarginContainer.new()
	list_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_margin.add_theme_constant_override("margin_left", 6)
	list_margin.add_theme_constant_override("margin_right", 6)
	list_margin.add_theme_constant_override("margin_top", int(LIST_TOP))
	list_margin.add_theme_constant_override("margin_bottom", int(LIST_BOTTOM))
	list_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(list_margin)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 1)
	list_margin.add_child(_list)

	_empty = VBoxContainer.new()
	_empty.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty.add_theme_constant_override("separation", 4)
	_empty.visible = false
	list_margin.add_child(_empty)
	var empty_icon := Kit.icon("layers", Kit.TEXT_DIM, 22)
	empty_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_empty.add_child(empty_icon)
	var empty_title := Kit.label("The scene is empty", 12, Kit.TEXT_MUTED, 500)
	empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_child(empty_title)
	var empty_sub := Kit.label("Use the + button to add an object.", 10, Kit.TEXT_DIM)
	empty_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_child(empty_sub)

func set_persistent_panel(value: bool) -> void:
	if persistent_panel == value:
		return
	persistent_panel = value
	if persistent_panel:
		# The column has its own rail; the list inside an expanded column is
		# always expanded.
		set_collapsed(false)
		# The column hangs off the right edge, so the collapse chevron points
		# toward the rail on its right.
		Kit.set_icon(_collapse_button, "chevron-right")
		_collapse_button.tooltip_text = "Collapse the scene panel"
	else:
		set_collapsed(collapsed)
		_collapse_button.tooltip_text = "Expand the scene list" if collapsed else "Collapse the scene list"


func _on_collapse_pressed() -> void:
	if persistent_panel:
		panel_collapse_requested.emit()
		return
	set_collapsed(not collapsed, true)


func set_collapsed(value: bool, emit_signal: bool = false) -> void:
	collapsed = value
	if _search_margin != null:
		_search_margin.visible = not value
	if _rule != null:
		_rule.visible = not value
	if _scroll != null:
		_scroll.visible = not value
	if _bottom_guard != null:
		_bottom_guard.visible = not value
	if _header_margin != null:
		_header_margin.add_theme_constant_override("margin_top", 0 if value else 10)
		_header_margin.add_theme_constant_override("margin_bottom", 0 if value else 6)
	if _collapse_button != null and not persistent_panel:
		Kit.set_icon(_collapse_button, "chevron-down" if value else "chevron-up")
		_collapse_button.tooltip_text = "Expand the scene list" if value else "Collapse the scene list"
	if emit_signal:
		collapse_toggled.emit(collapsed)


func _on_search_changed(text_value: String) -> void:
	_filter = text_value.strip_edges().to_lower()
	_rebuild()

func _on_scene_changed() -> void:
	_rebuild()

func _on_selection_changed(_id: String) -> void:
	_refresh_selection()

func _on_object_changed(id: String) -> void:
	# Material, visibility and camera edits only change a row's badges, but the
	# derived list also carries visibility, so refresh that root's snapshot.
	if _parts_by_root.has(id):
		_parts_by_root[id] = doc.import_parts(id)
	_update_row(id)
	for panel in _part_rows.values():
		if is_instance_valid(panel) and str(panel.get_meta("object_id", "")) == id:
			_update_part_row(panel)
	_refresh_selection()

func _on_part_selection_changed(object_id: String, _part_path: String) -> void:
	# A part switch with the same root emits no selection_changed, so refresh
	# only the rows this root owns. Never rebuild: the tree stays put.
	if doc == null:
		return
	if object_id == "":
		_refresh_selection()
		return
	_update_row(object_id)
	var root_row: Control = _rows.get(object_id)
	if root_row != null:
		_apply_panel_style(root_row)
	for panel in _part_rows.values():
		if not is_instance_valid(panel) or str(panel.get_meta("object_id", "")) != object_id:
			continue
		_update_part_row(panel)
		_apply_panel_style(panel)

func _on_keyframes_changed(id: String) -> void:
	if doc != null and id != "" and _rows.has(id):
		_update_row(id)
	else:
		_refresh_animation_markers()

func _refresh_animation_markers() -> void:
	# Key changes only affect the animated dot on each row.
	for id in _rows.keys():
		_update_row(str(id))

func _rebuild() -> void:
	if doc == null or _list == null:
		return
	_track_identity()
	rebuild_count += 1
	var scroll_pos := _scroll.scroll_vertical
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	_part_rows.clear()
	_parts_by_root.clear()
	var visible_count := 0
	for obj in doc.objects:
		var id := str(obj.get("id", ""))
		var name := str(obj.get("name", "Object"))
		var parts: Array = _parts_for(id)
		var root_match := _filter == "" or name.to_lower().contains(_filter)
		var matched: Array = []
		if _filter != "":
			for part in parts:
				if str(part.get("name", "")).to_lower().contains(_filter):
					matched.append(part)
		if _filter != "" and not root_match and matched.is_empty():
			continue
		visible_count += 1
		var forced := not matched.is_empty()
		var root_expanded := _is_root_expanded(id) or forced
		var has_parts := not parts.is_empty()
		var root := _make_root_row(obj, has_parts, root_expanded, not forced)
		_list.add_child(root)
		_rows[id] = root
		if not root_expanded:
			continue
		var display_parts: Array = _matched_parts(parts, matched) if forced else _browsing_parts(id, parts)
		var child_parents := {}
		for part in display_parts:
			var parent := str(part.get("parent", ""))
			if parent != "":
				child_parents[parent] = true
		for part in display_parts:
			var row := _make_part_row(id, part, child_parents.has(str(part.get("path", ""))), not forced)
			_list.add_child(row)
			_part_rows[_part_key(id, str(part.get("path", "")))] = row
	_count.text = str(doc.objects.size())
	_empty.visible = visible_count == 0
	if not _empty.visible:
		for child in _list.get_children():
			child.visible = true
	# Keep the search / empty messaging honest.
	var empty_title := _empty.get_child(1) as Label
	if empty_title != null:
		empty_title.text = "No matching objects" if _filter != "" and not doc.objects.is_empty() else "The scene is empty"
	_refresh_selection()
	_scroll.scroll_vertical = scroll_pos
	_schedule_fit_rows()

## Expansion is UI state, not document data. A project identity change
## (different id or title) starts every import root collapsed again.
func _track_identity() -> void:
	var next := str(doc.project_id) + KEY_SEP + str(doc.title)
	if next != _identity:
		_identity = next
		_expanded.clear()


func _part_key(id: String, path: String) -> String:
	return id + KEY_SEP + path


func _is_root_expanded(id: String) -> bool:
	return _expanded.has(id)


func _is_part_expanded(id: String, path: String) -> bool:
	return _expanded.has(_part_key(id, path))


func _toggle_root(id: String) -> void:
	if _expanded.has(id):
		_expanded.erase(id)
	else:
		_expanded[id] = true
	_rebuild()


func _toggle_part(id: String, path: String) -> void:
	var key := _part_key(id, path)
	if _expanded.has(key):
		_expanded.erase(key)
	else:
		_expanded[key] = true
	_rebuild()


## Parts visible while browsing: direct children of the expanded root, plus
## the children of every expanded part.
func _browsing_parts(id: String, parts: Array) -> Array:
	var result: Array = []
	var shown := {}
	for part in parts:
		var path := str(part.get("path", ""))
		var parent := str(part.get("parent", ""))
		var show := parent == "" or (shown.has(parent) and _is_part_expanded(id, parent))
		if show:
			shown[path] = true
			result.append(part)
	return result


## Parts visible while searching: every match plus its listed ancestors, with
## siblings hidden so the path stays readable.
func _matched_parts(parts: Array, matched: Array) -> Array:
	var keep := {}
	for part in matched:
		var path := str(part.get("path", ""))
		keep[path] = true
		var parent := str(part.get("parent", ""))
		while parent != "":
			keep[parent] = true
			var entry: Dictionary = {}
			for candidate in parts:
				if str(candidate.get("path", "")) == parent:
					entry = candidate
					break
			parent = str(entry.get("parent", ""))
	var result: Array = []
	for part in parts:
		if keep.has(str(part.get("path", ""))):
			result.append(part)
	return result


func _make_root_row(obj: Dictionary, has_parts: bool, expanded: bool, disclosure_enabled: bool = true) -> Control:
	var id := str(obj.get("id", ""))
	var selected := id == doc.selected_id and not _root_has_selected_part(id)
	var panel := _make_panel(selected, _root_has_selected_part(id))
	panel.set_meta("object_id", id)
	var row := panel.get_child(0) as HBoxContainer
	if has_parts and disclosure_enabled:
		var disclosure := _disclosure_button(expanded, _toggle_root.bind(id))
		row.add_child(disclosure)
	elif has_parts:
		# A forced part-name filter ignores expansion, so the chevron there
		# would be a fake affordance. Keep the slot for alignment only.
		row.add_child(_disclosure_spacer())
	var icon := Kit.icon(_icon_for(obj), Kit.TEXT_DIM, 14)
	icon.set_meta("role", "icon")
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var name := Kit.label(str(obj.get("name", "Object")), 12, Kit.TEXT_MUTED, 400)
	name.set_meta("role", "name")
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name)
	var key_marker := Kit.icon("diamond", Kit.ACCENT, 8)
	key_marker.set_meta("role", "key")
	key_marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	key_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(key_marker)
	key_marker.visible = _has_keys(id)
	var hidden := not bool(obj.get("visible", true))
	var eye := _eye_button(hidden)
	eye.set_meta("role", "eye")
	eye.pressed.connect(func() -> void:
		if doc == null:
			return
		var current: Dictionary = doc.get_object(id)
		if not current.is_empty():
			doc.set_object_visible(id, not bool(current.get("visible", true)))
	)
	row.add_child(eye)
	Kit.bind_tap(panel, _on_root_tapped.bind(id))
	_update_row(id)
	return panel


func _make_part_row(root_id: String, part: Dictionary, children_shown: bool, disclosure_enabled: bool = true) -> Control:
	var path := str(part.get("path", ""))
	var panel := _make_panel(_is_part_selected(root_id, path), false)
	panel.set_meta("object_id", root_id)
	panel.set_meta("part_path", path)
	var row := panel.get_child(0) as HBoxContainer
	var indent := Control.new()
	indent.set_meta("role", "indent")
	indent.custom_minimum_size = Vector2(PART_INDENT * float(maxi(1, int(part.get("depth", 1)))), 0.0)
	indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(indent)
	var has_children := bool(part.get("has_children", false))
	if has_children and disclosure_enabled:
		var disclosure := _disclosure_button(children_shown, _toggle_part.bind(root_id, path))
		row.add_child(disclosure)
	else:
		row.add_child(_disclosure_spacer())
	var icon := Kit.icon(_icon_for_part(part), Kit.TEXT_DIM, 14)
	icon.set_meta("role", "icon")
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var name := Kit.label(str(part.get("name", "Part")), 12, Kit.TEXT_MUTED, 400)
	name.set_meta("role", "name")
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name)
	# A root key does not key its parts: the marker keeps its slot but never
	# lights up in this wave.
	var key_marker := Kit.icon("diamond", Kit.ACCENT, 8)
	key_marker.set_meta("role", "key")
	key_marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	key_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_marker.visible = false
	row.add_child(key_marker)
	var eye := _eye_button(not bool(part.get("visible", true)))
	eye.set_meta("role", "eye")
	eye.pressed.connect(func() -> void:
		if doc == null:
			return
		var current: Dictionary = _find_part(root_id, path)
		if not current.is_empty():
			doc.set_import_part_visible(root_id, path, not bool(current.get("visible", true)))
	)
	row.add_child(eye)
	Kit.bind_tap(panel, _on_part_tapped.bind(root_id, path))
	_update_part_row(panel)
	return panel


func _make_panel(selected: bool, context: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = ROW_HEIGHT
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel", _style_for(selected, context, false))
	panel.mouse_entered.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", _style_for(_is_row_selected(panel), _is_context_row(panel), true))
	)
	panel.mouse_exited.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", _style_for(_is_row_selected(panel), _is_context_row(panel), false))
	)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.offset_right = -4
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	return panel


func _disclosure_spacer() -> Control:
	var slot := Control.new()
	slot.set_meta("role", "disclosure-slot")
	slot.custom_minimum_size = Vector2(ROW_HEIGHT, ROW_HEIGHT)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot


func _disclosure_button(expanded: bool, on_toggle: Callable) -> Button:
	var button := Kit.icon_button("chevron-down" if expanded else "chevron-right",
		"Collapse parts" if expanded else "Expand parts", int(ROW_HEIGHT), 16)
	button.set_meta("disclosure", true)
	button.set_meta("role", "disclosure")
	button.pressed.connect(on_toggle)
	return button


func _eye_button(hidden: bool) -> Button:
	var eye := Kit.icon_button("eye-closed" if hidden else "eye", "Show" if hidden else "Hide", 24, 12)
	eye.add_theme_color_override("icon_normal_color", Kit.TEXT_DIM if hidden else Kit.TEXT_MUTED)
	eye.add_theme_color_override("icon_hover_color", Kit.TEXT)
	return eye


func _row_style(selected: bool, hover: bool = false) -> StyleBoxFlat:
	if selected:
		# The selected row is a full ACTIVE fill with a single bright edge. The
		# fill carries the selection; the 1 px edge keeps it findable when the
		# row is partly scrolled under the dock header.
		var sb := Kit.flat_style(Kit.SURFACE_ACTIVE, Kit.R_PANEL, Color(0, 0, 0, 0), 0)
		sb.border_width_left = 1
		sb.border_color = Kit.FOCUS_BRIGHT
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		return sb
	var bg := Kit.SURFACE_2 if hover else Color(0, 0, 0, 0)
	var plain := Kit.flat_style(bg, 0, Color(0, 0, 0, 0), 0)
	plain.content_margin_left = 4
	plain.content_margin_right = 4
	return plain


## The root of a selected part is context, not a second selection: a quiet
## surface fill with the same 1 px edge, never the bright active fill.
func _context_style(hover: bool = false) -> StyleBoxFlat:
	var bg := Kit.SURFACE_2 if hover else Kit.SURFACE
	var sb := Kit.flat_style(bg, Kit.R_PANEL, Color(0, 0, 0, 0), 0)
	sb.border_width_left = 1
	sb.border_color = Kit.BORDER_SOFT
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	return sb


func _style_for(selected: bool, context: bool, hover: bool) -> StyleBoxFlat:
	if context:
		return _context_style(hover)
	return _row_style(selected, hover)


func _is_part_selected(root_id: String, path: String) -> bool:
	return doc != null and doc.selected_part_object_id == root_id and doc.selected_part_path == path


func _root_has_selected_part(id: String) -> bool:
	return doc != null and doc.selected_part_path != "" and doc.selected_part_object_id == id


func _is_row_selected(panel: Control) -> bool:
	if doc == null:
		return false
	if panel.has_meta("part_path"):
		return _is_part_selected(str(panel.get_meta("object_id", "")), str(panel.get_meta("part_path")))
	var id := str(panel.get_meta("object_id", ""))
	return id == doc.selected_id and not _root_has_selected_part(id)


func _is_context_row(panel: Control) -> bool:
	if doc == null or panel.has_meta("part_path"):
		return false
	return _root_has_selected_part(str(panel.get_meta("object_id", "")))


func _apply_panel_style(panel: Control, hover: bool = false) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", _style_for(_is_row_selected(panel), _is_context_row(panel), hover))


func _on_root_tapped(id: String) -> void:
	if doc == null:
		return
	doc.set_selection(id)
	# Selecting the already-selected root is a no-op in the document, so the
	# outliner owns clearing the part highlight for that case.
	doc.clear_selected_part()


func _on_part_tapped(root_id: String, path: String) -> void:
	if doc == null:
		return
	doc.set_selected_part(root_id, path)


func _refresh_selection() -> void:
	if doc == null:
		return
	for id in _rows:
		var row: Control = _rows[id]
		if row == null or not is_instance_valid(row):
			continue
		_apply_panel_style(row)
		_update_row(str(id))
	for key in _part_rows:
		var row: Control = _part_rows[key]
		if row == null or not is_instance_valid(row):
			continue
		_apply_panel_style(row)
		_update_part_row(row)


func _child_role(panel: Control, role: String) -> Node:
	if panel == null:
		return null
	var row := panel.get_child(0) as HBoxContainer
	if row == null:
		return null
	for child in row.get_children():
		if str(child.get_meta("role", "")) == role:
			return child
	return null


func _update_row(id: String) -> void:
	if doc == null or not _rows.has(id):
		return
	var obj: Dictionary = doc.get_object(id)
	var panel: Control = _rows[id]
	if obj.is_empty() or panel == null:
		return
	var selected := _is_row_selected(panel)
	var icon := _child_role(panel, "icon") as TextureRect
	if icon != null:
		icon.texture = Kit.icon_texture(_icon_for(obj))
		icon.modulate = Kit.TEXT_MUTED if selected else Kit.TEXT_DIM
	var name := _child_role(panel, "name") as Label
	if name != null and not name.has_meta("editing"):
		name.text = str(obj.get("name", "Object"))
		name.add_theme_color_override("font_color", Kit.TEXT if selected else Kit.TEXT_MUTED)
		name.add_theme_font_override("font", Kit.font_for(500 if selected else 400))
	var key_marker := _child_role(panel, "key") as TextureRect
	if key_marker != null:
		key_marker.visible = _has_keys(id)
	var hidden := not bool(obj.get("visible", true))
	var eye := _child_role(panel, "eye") as Button
	if eye != null:
		eye.icon = Kit.icon_texture("eye-closed" if hidden else "eye")
		eye.tooltip_text = "Show" if hidden else "Hide"
		eye.add_theme_color_override("icon_normal_color", Kit.TEXT_DIM if hidden else Kit.TEXT_MUTED)


func _find_part(root_id: String, path: String) -> Dictionary:
	if doc == null:
		return {}
	for part in _parts_for(root_id):
		if str(part.get("path", "")) == path:
			return part
	return {}


## Derived parts for one import root. The rebuild fills this once per root and
## every row refresh reads the same snapshot instead of re-walking the model.
func _parts_for(root_id: String) -> Array:
	if _parts_by_root.has(root_id):
		return _parts_by_root[root_id]
	var parts: Array = doc.import_parts(root_id) if doc != null else []
	_parts_by_root[root_id] = parts
	return parts


func _update_part_row(panel: Control) -> void:
	if doc == null or panel == null:
		return
	var root_id := str(panel.get_meta("object_id", ""))
	var path := str(panel.get_meta("part_path", ""))
	var part := _find_part(root_id, path)
	if part.is_empty():
		return
	var selected := _is_part_selected(root_id, path)
	var icon := _child_role(panel, "icon") as TextureRect
	if icon != null:
		icon.texture = Kit.icon_texture(_icon_for_part(part))
		icon.modulate = Kit.TEXT_MUTED if selected else Kit.TEXT_DIM
	var name := _child_role(panel, "name") as Label
	if name != null:
		name.add_theme_color_override("font_color", Kit.TEXT if selected else Kit.TEXT_MUTED)
		name.add_theme_font_override("font", Kit.font_for(500 if selected else 400))
	var key_marker := _child_role(panel, "key") as TextureRect
	if key_marker != null:
		key_marker.visible = false
	var hidden := not bool(part.get("visible", true))
	var eye := _child_role(panel, "eye") as Button
	if eye != null:
		eye.icon = Kit.icon_texture("eye-closed" if hidden else "eye")
		eye.tooltip_text = "Show" if hidden else "Hide"
		eye.add_theme_color_override("icon_normal_color", Kit.TEXT_DIM if hidden else Kit.TEXT_MUTED)
	# Ancestor visibility dims the whole row, matching what the stage shows.
	panel.modulate = Color(1, 1, 1, 1) if bool(part.get("effective_visible", true)) else Color(1, 1, 1, 0.45)


func _has_keys(id: String) -> bool:
	if doc == null:
		return false
	for channel in doc.CHANNELS:
		if doc.get_channel_keys(id, channel).size() > 0:
			return true
	return false


func _icon_for_part(part: Dictionary) -> String:
	match str(part.get("kind", "empty")):
		"skeleton": return "bone"
		"light": return "lightbulb"
		"camera": return "camera"
		"mesh": return "box"
		_: return "circle-dot-dashed"


func _icon_for(obj: Dictionary) -> String:
	match str(obj.get("kind", "mesh")):
		"camera": return "camera"
		"light": return "lightbulb"
		"empty": return "circle-dot-dashed"
		"import": return "package-open"
		_:
			match str(obj.get("primitive", "box")):
				"sphere": return "circle"
				"cylinder": return "cylinder"
				"cone": return "cone"
				"torus": return "torus"
				"plane": return "square"
				_: return "box"

## The guard is derived from the total space the list owns, so shrinking the
## scroll viewport does not feed back into a new guard height. It only runs
## while the list is taller than the viewport; short lists keep every pixel.
func _schedule_fit_rows() -> void:
	_fit_rows.call_deferred()

func _fit_rows() -> void:
	if _scroll == null or _bottom_guard == null or _list == null:
		return
	var total := _scroll.size.y + _bottom_guard.size.y
	var pitch := ROW_HEIGHT + ROW_GAP
	var content := _list.get_combined_minimum_size().y + LIST_TOP + LIST_BOTTOM
	var guard := 0.0
	if total > pitch and content > total:
		var full_rows := floorf((total - LIST_TOP) / pitch)
		if full_rows >= 1.0:
			guard = total - (LIST_TOP + full_rows * pitch)
			guard = clampf(guard, 0.0, pitch - 1.0)
	if absf(_bottom_guard.custom_minimum_size.y - guard) > 0.5:
		_bottom_guard.custom_minimum_size.y = guard
