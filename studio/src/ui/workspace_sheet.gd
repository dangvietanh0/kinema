extends VBoxContainer
## Workspace and interface scale.
##
## The sheet never changes the layout on its own. It reports the arrangement
## the user picked; Main resolves the real mode from the window and the saved
## preference. Desktop is a first-class choice on a phone and shrinks to fit
## instead of falling back to Studio.

signal layout_selected(mode: String)
signal orientation_selected(value: String)
signal ui_scale_changed(value: float)

const ScaleSliderScript = preload("res://src/ui/components/scale_slider.gd")

const MODES := [
	{"label": "Auto", "value": "auto"},
	{"label": "Compact", "value": "compact"},
	{"label": "Studio", "value": "studio"},
	{"label": "Desktop", "value": "desktop"},
]

var editor: Node = null
var current_mode := "studio"
var resolved_mode := "studio"
var fit_percent := 100.0
var user_scale_enabled := true
var clamped := false

var _scale_control: ScaleSliderScript
var _fit_label: Label
var _warning: Label
var _studio_shortcut: Button
var _mode_buttons: Dictionary = {}
var _orientation_track: PanelContainer
## A narrow sheet stacks the orientation label above a full-width segmented
## control. Side by side, three options plus a label were crushed into a strip
## of loose words on a phone and looked cramped even on a 560 dp sheet.
var _orientation_stacked := false
## A landscape phone has width to spare and no height: arrangement on the left,
## orientation and scale on the right, so the scale slider never hides below a
## prose block.
var _two_column := false


func setup(editor_ref: Node) -> void:
	editor = editor_ref


func open(p_current_mode: String, p_fit_percent: float, p_user_scale_enabled: bool, p_clamped: bool) -> void:
	current_mode = p_current_mode if p_current_mode in ["auto", "compact", "studio", "desktop"] else "studio"
	resolved_mode = _resolved_mode()
	fit_percent = clampf(p_fit_percent, 1.0, 100.0)
	user_scale_enabled = p_user_scale_enabled
	clamped = p_clamped
	_rebuild()


func close() -> void:
	if editor != null and editor.get("_overlay") != null:
		editor.get("_overlay").close_modal()


## Keep an open sheet honest when the host reports a new fit (rotation or a
## window resize). The sheet structure changes at the fit and warning
## thresholds, so crossing one rebuilds it once.
func refresh_fit(percent: float, enabled: bool, is_clamped: bool) -> void:
	var next_fit := clampf(percent, 1.0, 100.0)
	var needs_fit_label := next_fit < 99.9
	var needs_warning := is_clamped or next_fit < 60.0
	var had_fit_label := _fit_label != null
	var had_warning := _warning != null
	fit_percent = next_fit
	user_scale_enabled = enabled
	clamped = is_clamped
	if needs_fit_label != had_fit_label or needs_warning != had_warning:
		_rebuild()
		return
	if _fit_label != null:
		_fit_label.text = "Desktop fit %d%% · UI scale still applies" % int(round(fit_percent))
	if _scale_control != null:
		# A fit change never takes the scale away from the user.
		_scale_control.slider.editable = true


func _resolved_mode() -> String:
	if editor != null and editor.has_method("workspace_mode"):
		return str(editor.call("workspace_mode"))
	return resolved_mode


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_mode_buttons.clear()
	_scale_control = null
	_fit_label = null
	_warning = null
	_studio_shortcut = null
	_orientation_track = null
	_two_column = editor != null and editor.size.y < 560.0 and editor.size.x >= 780.0
	_orientation_stacked = editor == null or editor.size.x < 700.0 or _two_column
	add_theme_constant_override("separation", 12)

	var primary: VBoxContainer = self
	var secondary: VBoxContainer = self
	if _two_column:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 24)
		add_child(row)
		primary = VBoxContainer.new()
		primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		primary.add_theme_constant_override("separation", 12)
		row.add_child(primary)
		secondary = VBoxContainer.new()
		secondary.custom_minimum_size.x = 280.0
		secondary.add_theme_constant_override("separation", 8)
		row.add_child(secondary)

	primary.add_child(Kit.section_label("Arrangement"))
	var track := PanelContainer.new()
	track.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_2, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	primary.add_child(track)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 2)
	track.add_child(strip)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for entry in MODES:
		var data: Dictionary = entry
		var value := str(data.get("value", "auto"))
		var button := Kit.text_toggle(str(data.get("label", value)), "", true)
		_style_segment(button)
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 44.0
		button.button_pressed = value == current_mode
		button.toggled.connect(func(on: bool) -> void:
			if on:
				_select_mode(value)
		)
		strip.add_child(button)
		_mode_buttons[value] = button

	var resolved := Kit.label(
		"Resolved: %s" % _mode_label(resolved_mode),
		Kit.TYPE_CAPTION,
		Kit.TEXT_MUTED
	)
	primary.add_child(resolved)
	if fit_percent < 99.9:
		_fit_label = Kit.label(
			"Desktop fit %d%% · UI scale still applies" % int(round(fit_percent)),
			Kit.TYPE_CAPTION,
			Kit.TEXT
		)
		primary.add_child(_fit_label)
	if clamped or fit_percent < 60.0:
		_warning = Kit.label(
			"Small UI. Desktop stays selected and the whole canvas shrinks to fit. " +
			"Switch to Studio for larger controls.",
			Kit.TYPE_CAPTION,
			Kit.TEXT_MUTED
		)
		_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		primary.add_child(_warning)
		_studio_shortcut = Kit.text_button("Switch to Studio", "monitor", false, true)
		_studio_shortcut.custom_minimum_size.y = 44.0
		_studio_shortcut.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_studio_shortcut.pressed.connect(func() -> void:
			current_mode = "studio"
			layout_selected.emit("studio")
		)
		primary.add_child(_studio_shortcut)
	else:
		var note := Kit.label(
			"Auto follows the screen. Studio and Desktop keep the dope sheet open with its media lanes; Compact folds it to the transport.",
			Kit.TYPE_CAPTION,
			Kit.TEXT_DIM
		)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		primary.add_child(note)

	if not _two_column:
		secondary.add_child(Kit.vsep())
	secondary.add_child(Kit.section_label("Orientation"))
	var orientation_supported := DisplayServer.has_feature(DisplayServer.FEATURE_ORIENTATION)
	var orientation_labels := VBoxContainer.new()
	orientation_labels.add_theme_constant_override("separation", 1)
	orientation_labels.add_child(Kit.label("Screen orientation", Kit.TYPE_BODY, Kit.TEXT))
	var orientation_hint := Kit.label(
		"" if orientation_supported else "Not supported on this platform",
		Kit.TYPE_CAPTION,
		Kit.TEXT_DIM
	)
	orientation_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	orientation_labels.add_child(orientation_hint)

	var orientation_track := PanelContainer.new()
	_orientation_track = orientation_track
	orientation_track.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_2, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	var orientation_strip := HBoxContainer.new()
	orientation_strip.add_theme_constant_override("separation", 2)
	orientation_track.add_child(orientation_strip)

	if _two_column:
		# The section title already names the control; a second "Screen
		# orientation" row only pushed the scale slider past the fold.
		secondary.add_child(orientation_track)
		if not orientation_supported:
			secondary.add_child(Kit.label(
				"Orientation is fixed by this platform",
				Kit.TYPE_CAPTION,
				Kit.TEXT_DIM
			))
	elif _orientation_stacked:
		secondary.add_child(orientation_labels)
		secondary.add_child(Kit.gap(0, 4))
		secondary.add_child(orientation_track)
	else:
		var orientation_row := HBoxContainer.new()
		orientation_row.add_theme_constant_override("separation", 8)
		secondary.add_child(orientation_row)
		orientation_labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		orientation_row.add_child(orientation_labels)
		orientation_track.custom_minimum_size.x = 280.0
		orientation_row.add_child(orientation_track)

	var orientation_group := ButtonGroup.new()
	orientation_group.allow_unpress = false
	var orientation_current := str(Prefs.get_value("display.orientation", "auto"))
	for entry in [
		{"label": "Auto", "value": "auto"},
		{"label": "Portrait", "value": "portrait"},
		{"label": "Landscape", "value": "landscape"},
	]:
		var data: Dictionary = entry
		var value := str(data.get("value", "auto"))
		var button := Kit.text_toggle(str(data.get("label", value)), "", true)
		_style_segment(button)
		button.button_group = orientation_group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 44.0
		button.button_pressed = value == orientation_current
		button.disabled = not orientation_supported
		button.toggled.connect(func(on: bool) -> void:
			if on:
				Prefs.set_value("display.orientation", value)
				orientation_selected.emit(value)
		)
		orientation_strip.add_child(button)

	if not _two_column:
		secondary.add_child(Kit.vsep())
	secondary.add_child(Kit.section_label("Interface scale"))
	var scale_hint := Kit.label(
		"50-200%, applies to the whole workbench." if _two_column else
		"Applies to the whole workbench. Below 85% controls render under the 44 dp touch floor.",
		Kit.TYPE_CAPTION,
		Kit.TEXT_DIM
	)
	scale_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var scale_row: HBoxContainer = null
	if _two_column:
		secondary.add_child(scale_hint)
	else:
		scale_row = HBoxContainer.new()
		scale_row.add_theme_constant_override("separation", 8)
		secondary.add_child(scale_row)
		var scale_labels := VBoxContainer.new()
		scale_labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scale_labels.add_theme_constant_override("separation", 1)
		scale_row.add_child(scale_labels)
		scale_labels.add_child(Kit.label("UI scale", Kit.TYPE_BODY, Kit.TEXT))
		scale_labels.add_child(scale_hint)
	_scale_control = ScaleSliderScript.new()
	_scale_control.custom_minimum_size.y = 44.0
	_scale_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale_control.set_percent_value(float(Prefs.get_value("display.user_scale", 1.0)) * 100.0)
	_scale_control.value_changed.connect(func(value: float) -> void:
		Prefs.set_value("display.user_scale", value)
		ui_scale_changed.emit(value)
	)
	if _two_column:
		secondary.add_child(_scale_control)
	else:
		scale_row.add_child(_scale_control)


func _select_mode(mode: String) -> void:
	current_mode = mode
	layout_selected.emit(mode)


func _mode_label(mode: String) -> String:
	match mode:
		"auto":
			return "Auto"
		"compact":
			return "Compact"
		"studio":
			return "Studio"
		"desktop":
			return "Desktop"
	return mode


func _style_segment(button: Button) -> void:
	button.add_theme_stylebox_override("normal", Kit.flat_style(Color(0, 0, 0, 0), Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("hover", Kit.flat_style(Kit.SURFACE_HOVER, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("pressed", Kit.flat_style(Kit.SURFACE_ACTIVE, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("hover_pressed", Kit.flat_style(Kit.SURFACE_ACTIVE.lightened(0.04), Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	button.add_theme_color_override("font_color", Kit.TEXT_MUTED)
	button.add_theme_color_override("font_hover_color", Kit.TEXT)
	button.add_theme_color_override("font_pressed_color", Kit.TEXT)
	button.add_theme_color_override("font_disabled_color", Kit.TEXT_DIM)
