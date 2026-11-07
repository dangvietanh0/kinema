extends VBoxContainer
## Device and application settings.
##
## One screen, ten categories. Wide workbenches get a fixed navigation column;
## compact screens get a category list followed by a detail page with Back.
## Every control maps to a real Prefs key or a real Godot API. Options the
## current platform or renderer cannot honour are disabled with a reason rather
## than pretending to work.

signal renderer_restart_requested(preference: String)
signal orientation_requested(value: String)
signal risk_change_requested(enabled: bool)
signal open_render_requested
signal open_import_requested

const CATEGORIES := ["general", "editor", "display", "graphics", "performance", "render", "import", "media", "rig", "about"]
const LABELS := {
	"general": "General",
	"editor": "Editor",
	"display": "Display",
	"graphics": "Graphics",
	"performance": "Performance",
	"render": "Render",
	"import": "Import",
	"media": "Media",
	"rig": "Rig",
	"about": "About",
}
const ICONS := {
	"general": "settings",
	"editor": "sliders-horizontal",
	"display": "monitor",
	"graphics": "gauge",
	"performance": "timer",
	"render": "clapperboard",
	"import": "upload",
	"media": "film",
	"rig": "bone",
	"about": "info",
}
const PACKAGE_NAME := "studio.kinema.app"
const APP_VERSION := "0.1.5"
const ScaleSliderScript = preload("res://src/ui/components/scale_slider.gd")

# Graphics risk copy. The panel emits the request; the editor owns the
# confirmation sheet and the actual enable/disable calls.
const RISK_TOGGLE_TITLE := "High-end Forward+ effects"
const RISK_TOGGLE_CAPTION := "Accept the risk of disabling the mobile-safe clamp"
const RISK_CLAMP_HINT := "Clamped on Android Forward+ for stability."
const RISK_ACCEPTED_HINT := "High-end · risk accepted"
const RISK_ACTIVE_WARNING := "High-end effects are on. Stability is not guaranteed."
const RISK_MOBILE_WARNING := "High-end effects apply when Forward+ is running."
const RISK_RENDERER_NOTE := "Experimental on %s: high-end effects follow your risk setting."
const RISK_CLAMPED_RENDERER_NOTE := "Experimental on %s: high-end Forward+ effects are clamped for stability."
const RISK_RESTORE_LABEL := "Restore mobile-safe"

var editor: Node = null
var active := "general"
var _wide := false
var _short := false
var _compact_detail := false
var _nav_buttons: Dictionary = {}
var _ui_scale_control: ScaleSliderScript
var _fit_label: Label
var _stats_labels: Dictionary = {}
var _renderer_choice := ""
var _renderer_restart: Button


func setup(editor_ref: Node) -> void:
	editor = editor_ref
	_wide = editor != null and editor.size.x >= 700.0
	# A short landscape window cannot show eight 44 dp navigation rows beside
	# the page without scrolling the navigation itself. Use a two-column grid
	# there so every category stays on screen and keeps its touch target.
	_short = editor != null and editor.size.y < 560.0


func categories() -> Array[String]:
	var out: Array[String] = []
	for category in CATEGORIES:
		out.append(category)
	return out


func active_category() -> String:
	return active


func open(category: String = "general") -> void:
	active = category if category in CATEGORIES else "general"
	_compact_detail = active != "general"
	_rebuild()


func close() -> void:
	if editor != null and editor.get("_overlay") != null:
		editor.get("_overlay").close_modal()


func set_option(key: String, value: Variant) -> void:
	Prefs.set_value(key, value)
	_after_pref_change(key)


func sync_preset_buttons() -> void:
	if editor != null and editor.has_method("_sync_preset_buttons"):
		editor.call("_sync_preset_buttons")


## A live fit change (rotation, window resize, Desktop scale) must reach the
## open sheet immediately. Without this the UI-scale row kept saying 100% while
## the workbench was already scaled down. The slider stays live under fit: the
## fit is a density baseline, so the user scale still has a real effect.
func refresh_fit() -> void:
	if _ui_scale_control == null or _fit_label == null:
		return
	var fit := 100.0
	if editor != null and editor.has_method("fit_percent"):
		fit = float(editor.call("fit_percent"))
	_ui_scale_control.slider.editable = true
	if fit < 99.9:
		_fit_label.text = "Fit %d%% · UI scale still applies" % int(round(fit))
		_fit_label.visible = true
	else:
		_fit_label.visible = false


# -------------------------------------------------------------------------
# Layout
# -------------------------------------------------------------------------

func _rebuild() -> void:
	_clear()
	add_theme_constant_override("separation", 0)
	if _wide:
		_build_wide()
	else:
		_build_compact()


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_nav_buttons.clear()
	_stats_labels.clear()
	_ui_scale_control = null
	_fit_label = null
	_renderer_restart = null


func _build_wide() -> void:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 20)
	add_child(root)

	var nav := VBoxContainer.new()
	nav.custom_minimum_size.x = 240.0 if _short else 200.0
	nav.add_theme_constant_override("separation", 2)
	root.add_child(nav)
	nav.add_child(Kit.section_label("Settings"))
	var nav_list: Container = GridContainer.new() if _short else VBoxContainer.new()
	if nav_list is GridContainer:
		(nav_list as GridContainer).columns = 2
	nav_list.add_theme_constant_override("h_separation", 2)
	nav_list.add_theme_constant_override("v_separation", 2)
	nav.add_child(nav_list)
	for category in CATEGORIES:
		nav_list.add_child(_nav_button(category))
	nav.add_child(Kit.gap(0, 8))
	var close_hint := Kit.label("Changes are stored on this device.", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	close_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nav.add_child(close_hint)

	var rule := Kit.hairline(true)
	root.add_child(rule)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	root.add_child(content)
	_build_category(content, active)


func _build_compact() -> void:
	if not _compact_detail:
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 2)
		add_child(list)
		list.add_child(Kit.section_label("Settings"))
		for category in CATEGORIES:
			var row := _nav_button(category)
			row.custom_minimum_size.y = 48.0
			list.add_child(row)
		var hint := Kit.label("Changes are stored on this device.", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(Kit.gap(0, 8))
		list.add_child(hint)
		return

	var back := Kit.text_button("All settings", "chevron-left", false, true)
	back.custom_minimum_size.y = 44.0
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func() -> void:
		_compact_detail = false
		active = "general"
		_rebuild()
	)
	add_child(back)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	add_child(content)
	_build_category(content, active)


func _nav_button(category: String) -> Button:
	var button := Kit.text_button(LABELS[category], ICONS[category], false, true)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_constant_override("h_separation", 8)
	button.pressed.connect(func() -> void:
		active = category
		_compact_detail = true
		_rebuild()
	)
	var selected := category == active
	Kit.set_icon_active(button, selected, "left")
	button.add_theme_color_override("font_color", Kit.TEXT if selected else Kit.TEXT_MUTED)
	button.add_theme_color_override("font_hover_color", Kit.TEXT)
	button.add_theme_color_override("font_pressed_color", Kit.TEXT)
	_nav_buttons[category] = button
	return button


func _build_category(parent: Control, category: String) -> void:
	_page_header(parent, LABELS[category], _subtitle_for(category))
	match category:
		"general": _general(parent)
		"editor": _editor(parent)
		"display": _display(parent)
		"graphics": _graphics(parent)
		"performance": _performance(parent)
		"render": _render(parent)
		"import": _import(parent)
		"media": _media(parent)
		"rig": _rig(parent)
		"about": _about(parent)


func _subtitle_for(category: String) -> String:
	match category:
		"general": return "Application identity and a full preference reset."
		"editor": return "How the workbench behaves while you animate."
		"display": return "Arrangement, orientation and interface scale."
		"graphics": return "Real engine features, with unsupported options disabled."
		"performance": return "Preview policy and live engine monitors."
		"render": return "Real PNG stills and PNG sequences. No video encoder."
		"import": return "glTF, GLB and OBJ. Binary FBX is not supported."
		"media": return "Video reference proxies. MP4 needs the Android encoder."
		"rig": return "Skeleton overlay, bone handles and rig display."
		"about": return "Build information and open-source licenses."
	return ""


func _page_header(parent: Control, title: String, subtitle: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	parent.add_child(box)
	box.add_child(Kit.label(title, Kit.TYPE_PAGE, Kit.TEXT, 600))
	var hint := Kit.label(subtitle, Kit.TYPE_CAPTION, Kit.TEXT_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	parent.add_child(Kit.vsep())


# -------------------------------------------------------------------------
# General
# -------------------------------------------------------------------------

func _general(parent: Control) -> void:
	parent.add_child(Kit.section_label("Application"))
	_info_line(parent, "Name", "Kinema Studio")
	_info_line(parent, "Version", APP_VERSION)
	_info_line(parent, "Engine", _engine_version())
	_info_line(parent, "Package", PACKAGE_NAME)
	_info_line(parent, "Build", "debug" if OS.is_debug_build() else "release")
	_info_line(parent, "Platform", OS.get_name())

	parent.add_child(Kit.vsep())
	parent.add_child(Kit.section_label("Reset"))
	var note := Kit.label("Resetting preferences restores every editor, display and performance value to its default. Project documents are not changed.", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(note)
	var reset := Kit.text_button("Reset all preferences", "rotate-ccw", false, true)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(_confirm_reset_all)
	parent.add_child(reset)


func _confirm_reset_all() -> void:
	if editor == null:
		return
	var overlay: Control = editor.get("_overlay")
	if overlay == null:
		return
	overlay.confirm(
		"Reset preferences",
		"Every preference returns to its default. Projects, renders and imported models are untouched.",
		"Reset",
		func() -> void:
			Prefs.reset_all()
			Gfx.apply_preset("balanced")
			editor.call("_apply_perf_preferences")
			editor.call("_on_settings_pref_changed", "display.user_scale")
			editor.call_deferred("_open_settings", "general"),
		true
	)


# -------------------------------------------------------------------------
# Editor
# -------------------------------------------------------------------------

func _editor(parent: Control) -> void:
	parent.add_child(Kit.section_label("Workflow"))
	_choice_row(parent, "Autosave", "seconds", [
		{"label": "Off", "value": 0},
		{"label": "15", "value": 15},
		{"label": "30", "value": 30},
		{"label": "60", "value": 60},
	], int(Prefs.get_value("editor.autosave_seconds", 30)), func(value: Variant) -> void:
		set_option("editor.autosave_seconds", value)
	)
	_toggle_row(parent, "Confirm delete", "Ask before removing an object", bool(Prefs.get_value("editor.confirm_delete", true)), func(value: bool) -> void:
		set_option("editor.confirm_delete", value)
	)
	_choice_row(parent, "Timeline opens as", "", [
		{"label": "Dope sheet", "value": "dope"},
		{"label": "Speed graph", "value": "graph"},
	], str(Prefs.get_value("editor.timeline_default", "dope")), func(value: Variant) -> void:
		set_option("editor.timeline_default", value)
	)
	_toggle_row(parent, "Show FPS chip", "Viewport monitor", bool(Prefs.get_value("editor.show_fps", true)), func(value: bool) -> void:
		set_option("editor.show_fps", value)
	)
	_toggle_row(parent, "Reduce motion", "Skip non-essential transitions", bool(Prefs.get_value("editor.reduce_motion", false)), func(value: bool) -> void:
		set_option("editor.reduce_motion", value)
	)
	var haptics_available := OS.get_name() == "Android" or OS.get_name() == "iOS"
	_toggle_row(parent, "Haptics", "" if haptics_available else "Not available on this platform", bool(Prefs.get_value("editor.haptics", false)), func(value: bool) -> void:
		set_option("editor.haptics", value)
		if value and haptics_available:
			Input.vibrate_handheld(12)
	, not haptics_available)

	parent.add_child(Kit.vsep())
	parent.add_child(Kit.section_label("Transform"))
	_number_row(parent, "Gizmo size", "scale", 0.5, 2.0, 0.05, float(Prefs.get_value("editor.gizmo_size", 1.25)), func(value: float) -> void:
		set_option("editor.gizmo_size", value)
	)
	_number_row(parent, "Translate snap", "units", 0.01, 10.0, 0.05, float(Prefs.get_value("editor.translate_snap", 0.25)), func(value: float) -> void:
		set_option("editor.translate_snap", value)
	)
	_number_row(parent, "Rotate snap", "degrees", 1.0, 90.0, 1.0, float(Prefs.get_value("editor.rotate_snap", 15.0)), func(value: float) -> void:
		set_option("editor.rotate_snap", value)
	)
	_number_row(parent, "Scale snap", "factor", 0.01, 1.0, 0.05, float(Prefs.get_value("editor.scale_snap", 0.25)), func(value: float) -> void:
		set_option("editor.scale_snap", value)
	)
	var interpolation := Kit.label("Default interpolation is set per project in Project settings so existing keys keep their authored curve.", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	interpolation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(interpolation)

	parent.add_child(Kit.vsep())
	_section_reset(parent, "editor", "Reset editor settings")


# -------------------------------------------------------------------------
# Display
# -------------------------------------------------------------------------

func _display(parent: Control) -> void:
	parent.add_child(Kit.section_label("Arrangement"))
	_choice_row(parent, "Layout", "Resolved: %s" % _resolved_mode(), [
		{"label": "Auto", "value": "auto"},
		{"label": "Compact", "value": "compact"},
		{"label": "Studio", "value": "studio"},
		{"label": "Desktop", "value": "desktop"},
	], str(Prefs.get_value("display.layout", "auto")), func(value: Variant) -> void:
		if editor != null and editor.has_method("set_layout_mode"):
			editor.call("set_layout_mode", str(value))
		else:
			Prefs.set_value("display.layout", value)
		_rebuild()
	)

	var orientation_supported := DisplayServer.has_feature(DisplayServer.FEATURE_ORIENTATION)
	_choice_row(parent, "Orientation", "" if orientation_supported else "Not supported on this platform", [
		{"label": "Auto", "value": "auto"},
		{"label": "Portrait", "value": "portrait"},
		{"label": "Landscape", "value": "landscape"},
	], str(Prefs.get_value("display.orientation", "auto")), func(value: Variant) -> void:
		set_option("display.orientation", value)
		if orientation_supported:
			orientation_requested.emit(str(value))
	, not orientation_supported)

	parent.add_child(Kit.vsep())
	parent.add_child(Kit.section_label("Interface"))
	var fit := 100.0 if editor == null else float(editor.call("fit_percent"))
	_fit_label = Kit.label("Fit %d%%" % int(round(fit)), Kit.TYPE_CAPTION, Kit.TEXT_MUTED)
	_fit_label.visible = fit < 99.9
	parent.add_child(_fit_label)

	_ui_scale_control = ScaleSliderScript.new()
	_ui_scale_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ui_scale_control.set_percent_value(float(Prefs.get_value("display.user_scale", 1.0)) * 100.0)
	_ui_scale_control.value_changed.connect(func(value: float) -> void:
		set_option("display.user_scale", value)
	)
	var scale_row := _row(
		parent,
		"UI scale",
		"Applies to the whole workbench. Below 85% controls render under the 44 dp touch floor."
	)
	scale_row.add_child(_ui_scale_control)
	if fit < 99.9:
		_fit_label.text = "Fit %d%% · UI scale still applies" % int(round(fit))
		_fit_label.visible = true
	else:
		_fit_label.visible = false

	_toggle_row(parent, "Keep screen on", "Prevent sleep while editing", bool(Prefs.get_value("display.keep_screen_on", true)), func(value: bool) -> void:
		set_option("display.keep_screen_on", value)
		DisplayServer.screen_set_keep_on(value)
	)
	var desktop_os := OS.get_name() != "Android" and OS.get_name() != "iOS"
	_toggle_row(parent, "Fullscreen", "" if desktop_os else "Android manages the window", bool(Prefs.get_value("display.fullscreen", false)), func(value: bool) -> void:
		set_option("display.fullscreen", value)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED)
	, not desktop_os)

	parent.add_child(Kit.vsep())
	_section_reset(parent, "display", "Reset display settings")


func _resolved_mode() -> String:
	if editor != null and editor.has_method("layout_mode"):
		return str(editor.call("layout_mode")).capitalize()
	return "Studio"


# -------------------------------------------------------------------------
# Graphics
# -------------------------------------------------------------------------

## Single source for the risk card copy and visibility. Tests and `_graphics()`
## both read this, so the panel cannot drift from the stated behavior.
func risk_card_state(platform: String = OS.get_name(), method: String = Gfx.actual_method()) -> Dictionary:
	var resolved := platform if platform != "" else OS.get_name()
	var supported := Gfx.risk_supported(resolved)
	var enabled := Gfx.risk_enabled
	var forward := method == "forward_plus"
	var unlocked := supported and enabled and forward
	var warning := ""
	if supported and enabled:
		if Gfx.risk_last_error != "":
			warning = Gfx.risk_last_error
		elif forward:
			warning = RISK_ACTIVE_WARNING
		else:
			warning = RISK_MOBILE_WARNING
	var hint := "Requires Forward+"
	if unlocked:
		hint = RISK_ACCEPTED_HINT
	elif supported and forward:
		hint = RISK_CLAMP_HINT
	var renderer_note := ""
	if supported:
		if enabled:
			renderer_note = RISK_RENDERER_NOTE % resolved
		else:
			renderer_note = RISK_CLAMPED_RENDERER_NOTE % resolved
	return {
		"visible": supported,
		"toggle_on": enabled,
		"warning": warning,
		"restore_visible": supported and enabled,
		"hint": hint,
		"renderer_note": renderer_note,
	}


## A full-width 44 dp row. Toggling on only requests the editor's confirmation;
## the visual state stays put until the editor confirms the change.
func risk_toggle_button(state: Dictionary) -> Button:
	var button := Kit.text_toggle(RISK_TOGGLE_TITLE, "", true)
	button.name = "RiskToggle"
	button.custom_minimum_size.y = 44.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.button_pressed = bool(state.get("toggle_on", false))
	button.toggled.connect(func(on: bool) -> void:
		if on:
			risk_change_requested.emit(true)
		button.set_pressed_no_signal(bool(risk_card_state().get("toggle_on", false)))
	)
	return button


## A neutral 96x44 action: restoring the safe profile is not destructive.
func risk_restore_button() -> Button:
	var button := Kit.text_button(RISK_RESTORE_LABEL, "", false, false)
	button.custom_minimum_size = Vector2(96.0, 44.0)
	button.pressed.connect(func() -> void:
		risk_change_requested.emit(false)
	)
	return button


func _graphics(parent: Control) -> void:
	var risk_state := risk_card_state()
	parent.add_child(Kit.section_label("Renderer"))
	_info_line(parent, "In use", Gfx.display_name())
	_info_line(parent, "Project request", Gfx.renderer_label(Gfx.project_renderer_request()))
	_renderer_choice = Gfx.renderer_preference
	if _renderer_choice == "":
		_renderer_choice = Gfx.actual_method()
	var strip := _segment(parent)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	var blocked_reasons: Array[String] = []
	var entry_notes: Array[String] = []
	for entry in Gfx.renderer_entries(OS.get_name()):
		var data: Dictionary = entry
		if not bool(data["supported"]):
			blocked_reasons.append(str(data["reason"]))
			continue
		var entry_note := str(data.get("note", ""))
		if entry_note != "":
			entry_notes.append(entry_note)
		var value := str(data["value"])
		var button := _segment_button(str(data["label"]))
		button.button_group = group
		button.button_pressed = value == _renderer_choice
		button.toggled.connect(func(on: bool) -> void:
			if on:
				_renderer_choice = value
				_update_renderer_restart()
		)
		strip.add_child(button)
	_renderer_restart = Kit.text_button("Restart", "restart", true, true)
	_renderer_restart.custom_minimum_size.y = 48.0
	_renderer_restart.pressed.connect(func() -> void:
		renderer_restart_requested.emit(_renderer_choice)
	)
	parent.add_child(_renderer_restart)
	_update_renderer_restart()
	if bool(risk_state.get("visible", false)):
		# The renderer entry note is the risk-aware mobile note, not the static
		# clamped note built by Gfx.renderer_entries().
		entry_notes.clear()
		var risk_note := str(risk_state.get("renderer_note", ""))
		if risk_note != "":
			entry_notes.append(risk_note)
	for note in entry_notes:
		var entry_note_label := Kit.label(note, Kit.TYPE_CAPTION, Kit.TEXT_MUTED)
		entry_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(entry_note_label)
	if Gfx.last_renderer_error != "":
		var error_label := Kit.label(Gfx.last_renderer_error, Kit.TYPE_CAPTION, Kit.WARNING)
		error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(error_label)
	var renderer_note := Kit.label("Godot chooses the renderer before the first frame. Restart applies the selected backend with a real engine flag and never launches a backend this platform cannot use; the row above keeps reporting the backend actually in use.", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	renderer_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(renderer_note)
	for reason in blocked_reasons:
		var reason_label := Kit.label(reason, Kit.TYPE_CAPTION, Kit.TEXT_DIM)
		reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(reason_label)

	if bool(risk_state.get("visible", false)):
		parent.add_child(Kit.vsep())
		parent.add_child(Kit.section_label("Forward+ risk"))
		parent.add_child(risk_toggle_button(risk_state))
		var risk_caption := Kit.label(RISK_TOGGLE_CAPTION, Kit.TYPE_CAPTION, Kit.TEXT_DIM)
		risk_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(risk_caption)
		if bool(risk_state.get("restore_visible", false)):
			var card := PanelContainer.new()
			card.name = "RiskCard"
			card.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_2, Kit.R_CONTROL, Kit.BORDER_SOFT))
			var card_body := VBoxContainer.new()
			card_body.add_theme_constant_override("separation", 6)
			card.add_child(card_body)
			var warning_text := str(risk_state.get("warning", ""))
			if warning_text != "":
				var warning := Kit.label(warning_text, Kit.TYPE_CAPTION, Kit.WARNING)
				warning.name = "RiskWarning"
				warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				card_body.add_child(warning)
			card_body.add_child(risk_restore_button())
			parent.add_child(card)

	parent.add_child(Kit.vsep())
	parent.add_child(Kit.section_label("Quality preset"))
	if editor != null and editor.has_method("graphics_preset_row"):
		editor.call("graphics_preset_row", parent, false)
	else:
		parent.add_child(Kit.label("Preset controls are unavailable in this host.", Kit.TYPE_CAPTION, Kit.TEXT_DIM))

	# Capability gating uses the running platform and the persisted risk
	# switch. On Android/iOS Forward+ without risk the stored preference may
	# stay high, but the controls report the clamped values actually applied.
	var running_caps := Gfx.capabilities_for(Gfx.actual_method(), OS.get_name(), Gfx.risk_enabled)
	var risk_unlocked := bool(running_caps.get("risk_unlocked", false))
	var forward_clamped := Gfx.actual_method() == "forward_plus" and bool(running_caps.get("mobile_safe", false)) and not risk_unlocked
	var clamp_reason := RISK_CLAMP_HINT
	var msaa_cap := int(running_caps.get("msaa_cap", 3))
	var scale_cap := float(running_caps.get("scale_3d_cap", 1.0))
	var shadow_quality_cap := int(running_caps.get("shadow_quality_cap", 3))
	var shadow_splits_cap := 2 if forward_clamped else 4
	var shadow_distance_cap := 40.0 if forward_clamped else 100.0
	var taa_available := bool(running_caps.get("taa", false))
	var ssil_available := bool(running_caps.get("ssil", false))
	var ssr_available := bool(running_caps.get("ssr", false))
	var fog_available := bool(running_caps.get("volumetric_fog", false))
	var effects_hint := RISK_ACCEPTED_HINT if risk_unlocked else (clamp_reason if forward_clamped else "Requires Forward+")

	parent.add_child(Kit.vsep())
	parent.add_child(Kit.section_label("Anti-aliasing"))
	_choice_row(parent, "Samples", RISK_ACCEPTED_HINT if risk_unlocked else (clamp_reason if msaa_cap < 2 else "MSAA"), [
		{"label": "Off", "value": 0},
		{"label": "2×", "value": 1},
		{"label": "4×", "value": 2, "disabled": msaa_cap < 2},
		{"label": "8×", "value": 3, "disabled": msaa_cap < 3},
	], Gfx.msaa, func(value: Variant) -> void: Gfx.set_option("msaa", value))
	_gfx_choice(parent, "Temporal", effects_hint, [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.taa, func(value: Variant) -> void: Gfx.set_option("taa", value), not taa_available)

	parent.add_child(Kit.vsep())
	parent.add_child(Kit.section_label("Lighting and surfaces"))
	_gfx_choice(parent, "Ambient occlusion", "Screen-space", [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.ssao, func(value: Variant) -> void: Gfx.set_option("ssao", value), not bool(running_caps.get("ssao", false)))
	_gfx_choice(parent, "AO quality", "", [
		{"label": "Low", "value": 0},
		{"label": "Medium", "value": 1},
		{"label": "High", "value": 2},
		{"label": "Ultra", "value": 3},
	], Gfx.ssao_quality, func(value: Variant) -> void: Gfx.set_option("ssao_quality", value))
	_gfx_choice(parent, "Indirect lighting", effects_hint, [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.ssil, func(value: Variant) -> void: Gfx.set_option("ssil", value), not ssil_available)
	_gfx_choice(parent, "Screen-space reflections", effects_hint, [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.ssr, func(value: Variant) -> void: Gfx.set_option("ssr", value), not ssr_available)
	_gfx_choice(parent, "Glow", "", [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.glow, func(value: Variant) -> void: Gfx.set_option("glow", value))
	_gfx_choice(parent, "Volumetric fog", effects_hint, [
		{"label": "Off", "value": false},
		{"label": "On", "value": true},
	], Gfx.volumetric_fog, func(value: Variant) -> void: Gfx.set_option("volumetric_fog", value), not fog_available)

	parent.add_child(Kit.vsep())
	parent.add_child(Kit.section_label("Shadows"))
	_choice_row(parent, "Filter quality", RISK_ACCEPTED_HINT if risk_unlocked else (clamp_reason if shadow_quality_cap < 3 else ""), [
		{"label": "Low", "value": 0},
		{"label": "Medium", "value": 1},
		{"label": "High", "value": 2},
		{"label": "Ultra", "value": 3, "disabled": shadow_quality_cap < 3},
	], Gfx.shadow_quality, func(value: Variant) -> void: Gfx.set_option("shadow_quality", value))
	_choice_row(parent, "Cascades", RISK_ACCEPTED_HINT if risk_unlocked else "%s · max %d" % ["sun", shadow_splits_cap], [
		{"label": "1", "value": 1},
		{"label": "2", "value": 2},
		{"label": "4", "value": 4, "disabled": shadow_splits_cap < 4},
	], Gfx.shadow_splits, func(value: Variant) -> void: Gfx.set_option("shadow_splits", value))
	_choice_row(parent, "Range", RISK_ACCEPTED_HINT if risk_unlocked else "meters · max %d" % int(round(shadow_distance_cap)), [
		{"label": "25", "value": 25.0},
		{"label": "40", "value": 40.0},
		{"label": "60", "value": 60.0, "disabled": forward_clamped},
		{"label": "100", "value": 100.0, "disabled": forward_clamped},
	], Gfx.shadow_distance, func(value: Variant) -> void: Gfx.set_option("shadow_distance", value))

	parent.add_child(Kit.vsep())
	parent.add_child(Kit.section_label("Performance"))
	_choice_row(parent, "3D resolution", RISK_ACCEPTED_HINT if risk_unlocked else "% · max %d%%" % int(round(scale_cap * 100.0)), [
		{"label": "60", "value": 0.6},
		{"label": "80", "value": 0.8},
		{"label": "100", "value": 1.0, "disabled": scale_cap < 1.0},
	], Gfx.scale_3d, func(value: Variant) -> void: Gfx.set_option("scale_3d", value))
	_toggle_row(parent, "Draft while editing", "Lower quality during camera, gizmo, playback and inspector edits", Gfx.draft_editing, func(value: bool) -> void:
		Gfx.set_draft_editing(value)
		if editor != null and editor.get("_view") != null:
			editor.get("_view").call("set_draft_quality", value)
	)
	var draft_note := Kit.label("Full quality returns after 0.45 s idle and before every capture. The Draft tag only appears while the preview is actually reduced.", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	draft_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(draft_note)

	parent.add_child(Kit.vsep())
	_section_reset(parent, "graphics", "Reset graphics to Balanced")


func _update_renderer_restart() -> void:
	if _renderer_restart == null:
		return
	var pending := _renderer_choice != Gfx.actual_method()
	_renderer_restart.disabled = not pending
	_renderer_restart.text = "Restart with %s" % Gfx.renderer_label(_renderer_choice) if pending else "Already using %s" % Gfx.renderer_label(_renderer_choice)


func _gfx_choice(parent: Control, title: String, hint: String, options: Array, current: Variant, on_change: Callable, disabled: bool = false) -> void:
	if editor != null and editor.has_method("_graphics_choice"):
		editor.call("_graphics_choice", parent, title, hint, options, current, on_change, disabled)
		return
	_choice_row(parent, title, hint, options, current, on_change, disabled)


# -------------------------------------------------------------------------
# Performance
# -------------------------------------------------------------------------

func _performance(parent: Control) -> void:
	parent.add_child(Kit.section_label("Live monitors"))
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 4)
	parent.add_child(stats)
	for key in ["fps", "frame", "draw", "preview", "renderer"]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var label := Kit.label(_stat_label(key), Kit.TYPE_BODY, Kit.TEXT_MUTED)
		label.custom_minimum_size.x = 112
		line.add_child(label)
		var value := Kit.mono_label("—", Kit.TYPE_MONO_LARGE, Kit.TEXT)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(value)
		stats.add_child(line)
		_stats_labels[key] = value
	_refresh_stats(Perf.sample())

	parent.add_child(Kit.vsep())
	parent.add_child(Kit.section_label("Preview policy"))
	_choice_row(parent, "Overlay", "", [
		{"label": "Off", "value": "off"},
		{"label": "Chip", "value": "compact"},
		{"label": "Full", "value": "full"},
	], str(Prefs.get_value("performance.overlay", "compact")), func(value: Variant) -> void:
		set_option("performance.overlay", value)
	)
	_toggle_row(parent, "Frame graph", "120 real frame-time samples", bool(Prefs.get_value("performance.frame_graph", false)), func(value: bool) -> void:
		set_option("performance.frame_graph", value)
	)
	_toggle_row(parent, "Adaptive quality", "Lower preview resolution when frame time rises", bool(Prefs.get_value("performance.adaptive_quality", true)), func(value: bool) -> void:
		set_option("performance.adaptive_quality", value)
	)
	_number_row(parent, "Target FPS", "fps", 15, 240, 1, float(Prefs.get_value("performance.target_fps", 60)), func(value: float) -> void:
		set_option("performance.target_fps", int(round(value)))
	)
	_number_row(parent, "Minimum preview", "percent", 25, 100, 5, float(Prefs.get_value("performance.min_preview_scale", 0.6)) * 100.0, func(value: float) -> void:
		set_option("performance.min_preview_scale", clampf(value / 100.0, 0.25, 1.0))
	)
	_choice_row(parent, "Preview update", "", [
		{"label": "On demand", "value": "on_demand"},
		{"label": "Always", "value": "always"},
	], str(Prefs.get_value("performance.preview_update", "on_demand")), func(value: Variant) -> void:
		set_option("performance.preview_update", value)
	)
	_number_row(parent, "Preview cap", "long edge", 480, 7680, 120, float(Prefs.get_value("performance.preview_cap", 1920)), func(value: float) -> void:
		set_option("performance.preview_cap", int(round(value)))
	)

	parent.add_child(Kit.vsep())
	parent.add_child(Kit.section_label("Frame pacing"))
	_choice_row(parent, "Max FPS", "", [
		{"label": "30", "value": 30},
		{"label": "60", "value": 60},
		{"label": "90", "value": 90},
		{"label": "120", "value": 120},
	], int(Prefs.get_value("performance.max_fps", 60)), func(value: Variant) -> void:
		set_option("performance.max_fps", value)
	)
	_toggle_row(parent, "V-Sync", "Window presentation", bool(Prefs.get_value("performance.vsync", true)), func(value: bool) -> void:
		set_option("performance.vsync", value)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
	)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	parent.add_child(actions)
	var open_overlay := Kit.text_button("Open overlay", "gauge", false, true)
	open_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_overlay.pressed.connect(func() -> void:
		close()
		if editor != null and editor.has_method("_toggle_performance_overlay"):
			editor.call_deferred("_toggle_performance_overlay")
	)
	actions.add_child(open_overlay)
	var reset := Kit.text_button("Reset graph", "rotate-ccw", false, true)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func() -> void:
		Perf.reset_stats()
		_refresh_stats(Perf.sample())
	)
	actions.add_child(reset)

	parent.add_child(Kit.vsep())
	_section_reset(parent, "performance", "Reset performance settings")


func _stat_label(key: String) -> String:
	match key:
		"fps": return "Frames / second"
		"frame": return "Frame time"
		"draw": return "Draw calls"
		"preview": return "Preview"
		"renderer": return "Renderer"
	return key


func _refresh_stats(sample: Dictionary) -> void:
	if _stats_labels.is_empty():
		return
	var fps := float(sample.get("fps", -1.0))
	_set_stat("fps", "%d" % int(round(fps)) if fps > 0.0 else "—")
	var frame := float(sample.get("frame_ms", -1.0))
	_set_stat("frame", "%.1f ms" % frame if frame >= 0.0 else "—")
	var draw := int(sample.get("draw_calls", -1))
	_set_stat("draw", str(draw) if draw >= 0 else "—")
	var scale := float(sample.get("preview_scale", 1.0))
	var size := Vector2i.ZERO
	if editor != null and editor.get("_view") != null:
		size = editor.get("_view").call("preview_size")
	var resolution := "—" if size.x <= 0 else "%d×%d" % [int(round(size.x * scale)), int(round(size.y * scale))]
	_set_stat("preview", "%d%% · %s" % [int(round(scale * 100.0)), resolution])
	_set_stat("renderer", "%s · %s" % [Gfx.renderer_label(Gfx.actual_method()), Gfx.preset.capitalize()])


func _set_stat(key: String, text_value: String) -> void:
	var label: Label = _stats_labels.get(key)
	if label != null and is_instance_valid(label):
		label.text = text_value


# -------------------------------------------------------------------------
# Render
# -------------------------------------------------------------------------

func _render(parent: Control) -> void:
	parent.add_child(Kit.section_label("Still image"))
	_choice_row(parent, "Long edge", "px", [
		{"label": "1280", "value": 1280},
		{"label": "1920", "value": 1920},
		{"label": "2560", "value": 2560},
		{"label": "3840", "value": 3840},
	], int(Prefs.get_value("render.resolution", 1920)), func(value: Variant) -> void:
		set_option("render.resolution", value)
	)
	_choice_row(parent, "Anti-aliasing", "MSAA", [
		{"label": "Off", "value": 0},
		{"label": "2×", "value": 1},
		{"label": "4×", "value": 2},
		{"label": "8×", "value": 3},
	], int(Prefs.get_value("render.msaa", 1)), func(value: Variant) -> void:
		set_option("render.msaa", value)
	)
	_toggle_row(parent, "Transparent background", "PNG alpha", bool(Prefs.get_value("render.transparent", false)), func(value: bool) -> void:
		set_option("render.transparent", value)
	)

	parent.add_child(Kit.vsep())
	parent.add_child(Kit.section_label("Frame sequence"))
	var start := int(Prefs.get_value("render.start_frame", 0))
	var end := int(Prefs.get_value("render.end_frame", -1))
	var count := _sequence_count()
	_number_row(parent, "Start frame", "index", 0, 1000000, 1, float(start), func(value: float) -> void:
		set_option("render.start_frame", int(round(value)))
	)
	_number_row(parent, "End frame", "index", -1, 1000000, 1, float(end), func(value: float) -> void:
		set_option("render.end_frame", int(round(value)))
	)
	var estimate := Kit.mono_label("%d frames · PNG sequence · estimate %s" % [count, _estimate_size(count)], Kit.TYPE_MONO, Kit.TEXT_MUTED)
	parent.add_child(estimate)
	var output := Kit.label("Output: %s" % str(Prefs.get_value("render.output_dir", "user://renders")), Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	output.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(output)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	parent.add_child(actions)
	var open := Kit.text_button("Render sheet", "clapperboard", true, true)
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.pressed.connect(func() -> void:
		close()
		open_render_requested.emit()
	)
	actions.add_child(open)
	var quick := Kit.text_button("Quick still", "image", false, true)
	quick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quick.pressed.connect(func() -> void:
		close()
		if editor != null and editor.has_method("_quick_still"):
			editor.call_deferred("_quick_still")
	)
	actions.add_child(quick)

	var note := Kit.label("MP4 is not encoded in this build. Render a PNG sequence and encode it externally. Every still and frame is a real engine capture.", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(note)


func _sequence_count() -> int:
	var start := maxi(0, int(Prefs.get_value("render.start_frame", 0)))
	var end := int(Prefs.get_value("render.end_frame", -1))
	if editor == null:
		return maxi(1, end - start + 1) if end >= start else 1
	var doc: Object = editor.get("doc")
	if doc == null:
		return 1
	var last := int(round(float(doc.get("duration")) * float(maxi(1, int(doc.get("fps"))))))
	if end < 0:
		end = last
	return maxi(1, end - start + 1)


func _estimate_size(frames: int) -> String:
	var resolution := int(Prefs.get_value("render.resolution", 1920))
	var bytes := int(float(frames) * float(resolution) * float(resolution) * 0.35)
	if bytes >= 1024 * 1024:
		return "%.1f MB" % (float(bytes) / (1024.0 * 1024.0))
	return "%d KB" % maxi(1, bytes / 1024)


# -------------------------------------------------------------------------
# Import
# -------------------------------------------------------------------------

func _import(parent: Control) -> void:
	parent.add_child(Kit.section_label("Supported"))
	_info_line(parent, "glTF / GLB", "Supported")
	_info_line(parent, "Wavefront OBJ", "Supported with MTL and textures")
	_info_line(parent, "Binary FBX", "Not supported in this build")

	parent.add_child(Kit.vsep())
	parent.add_child(Kit.section_label("Options"))
	_choice_row(parent, "Scale", "model units", [
		{"label": "0.01", "value": 0.01},
		{"label": "0.1", "value": 0.1},
		{"label": "1", "value": 1.0},
		{"label": "10", "value": 10.0},
		{"label": "100", "value": 100.0},
	], float(Prefs.get_value("import.scale", 1.0)), func(value: Variant) -> void:
		set_option("import.scale", value)
	)
	_toggle_row(parent, "Materials", "Read MTL libraries for OBJ", bool(Prefs.get_value("import.materials", true)), func(value: bool) -> void:
		set_option("import.materials", value)
	)
	_toggle_row(parent, "Textures", "Copy diffuse textures next to the model", bool(Prefs.get_value("import.textures", true)), func(value: bool) -> void:
		set_option("import.textures", value)
	)

	var open := Kit.text_button("Import model", "upload", true)
	open.custom_minimum_size.y = 48.0
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.pressed.connect(func() -> void:
		close()
		open_import_requested.emit()
	)
	parent.add_child(open)

	var fbx := Kit.label("FBX needs an editor-side importer that Godot does not ship in an exported build. Export the model as GLB or OBJ first. Kinema never fakes a successful FBX import.", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	fbx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(fbx)
	var saf := Kit.label("On Android, the system file picker may not grant access to an OBJ's sibling .mtl and texture files. Copy the whole model folder into app storage or select a GLB with embedded materials.", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	saf.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(saf)


# -------------------------------------------------------------------------
# Media
# -------------------------------------------------------------------------

func _media(parent: Control) -> void:
	parent.add_child(Kit.section_label("Video reference proxy"))
	var note := Kit.label("Imported video becomes a frame proxy for rotoscoping. The proxy keeps the source aspect at the chosen width; scrubbing reads frames, it never plays video in the viewport.", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(note)
	_choice_row(parent, "Proxy fps", "frames per second", [
		{"label": "6", "value": 6},
		{"label": "12", "value": 12},
		{"label": "24", "value": 24},
	], int(Prefs.get_value("media.proxy_fps", 12)), func(value: Variant) -> void:
		set_option("media.proxy_fps", value)
	)
	_choice_row(parent, "Proxy width", "max px", [
		{"label": "640", "value": 640},
		{"label": "960", "value": 960},
		{"label": "1280", "value": 1280},
		{"label": "1920", "value": 1920},
	], int(Prefs.get_value("media.proxy_max_width", 1280)), func(value: Variant) -> void:
		set_option("media.proxy_max_width", value)
	)

	parent.add_child(Kit.vsep())
	parent.add_child(Kit.section_label("Encoding"))
	_info_line(parent, "PNG still / sequence", "Every platform")
	_info_line(parent, "GIF", "Encoded in the app")
	_info_line(parent, "MP4", "Android encoder only")
	var mp4 := Kit.label("On this platform MP4 reports unavailable; Kinema never fakes an encoder. Export PNG frames or a GIF instead.", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	mp4.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(mp4)


# -------------------------------------------------------------------------
# Rig
# -------------------------------------------------------------------------

func _rig(parent: Control) -> void:
	parent.add_child(Kit.section_label("Viewport"))
	_toggle_row(parent, "Show overlay", "Bones and IK handles over the viewport", bool(Prefs.get_value("rig.show_overlay", true)), func(value: bool) -> void:
		set_option("rig.show_overlay", value)
	)
	var note := Kit.label("The rig tab always stays available. With no rig in the project it shows an empty state instead of placeholder bones.", Kit.TYPE_CAPTION, Kit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(note)


# -------------------------------------------------------------------------
# About
# -------------------------------------------------------------------------

func _about(parent: Control) -> void:
	parent.add_child(Kit.section_label("Build"))
	_info_line(parent, "App", "Kinema Studio")
	_info_line(parent, "Version", APP_VERSION)
	_info_line(parent, "Engine", _engine_version())
	_info_line(parent, "Package", PACKAGE_NAME)
	_info_line(parent, "Build type", "debug" if OS.is_debug_build() else "release")
	_info_line(parent, "Renderer", Gfx.display_name())
	_info_line(parent, "Driver", RenderingServer.get_current_rendering_driver_name())
	_info_line(parent, "Adapter", RenderingServer.get_video_adapter_name())

	parent.add_child(Kit.vsep())
	parent.add_child(Kit.section_label("Licenses"))
	var licenses := Kit.label("IBM Plex Sans and IBM Plex Mono · SIL Open Font License 1.1\nLucide icons · ISC License\nGodot Engine · MIT License", Kit.TYPE_BODY, Kit.TEXT_MUTED)
	licenses.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(licenses)

	var copy := Kit.text_button("Copy build info", "copy", false, true)
	copy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_build_info())
		if editor != null and editor.get("_overlay") != null:
			editor.get("_overlay").toast("Build info copied", "check", Kit.SUCCESS)
	)
	parent.add_child(copy)


func _build_info() -> String:
	return "Kinema Studio %s · engine %s · package %s · %s · %s · %s" % [
		APP_VERSION,
		_engine_version(),
		PACKAGE_NAME,
		"debug" if OS.is_debug_build() else "release",
		Gfx.actual_method(),
		OS.get_name(),
	]


# -------------------------------------------------------------------------
# Controls
# -------------------------------------------------------------------------

func _row(parent: Control, title: String, hint: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.add_theme_constant_override("separation", 1)
	row.add_child(labels)
	labels.add_child(Kit.label(title, Kit.TYPE_BODY, Kit.TEXT))
	if hint != "":
		var hint_label := Kit.label(hint, Kit.TYPE_CAPTION, Kit.TEXT_DIM)
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		labels.add_child(hint_label)
	return row


func _info_line(parent: Control, key: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var key_label := Kit.label(key, Kit.TYPE_BODY, Kit.TEXT_MUTED)
	key_label.custom_minimum_size.x = 120
	row.add_child(key_label)
	var value_label := Kit.mono_label(value, Kit.TYPE_MONO_LARGE, Kit.TEXT)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(value_label)


func _toggle_row(parent: Control, title: String, hint: String, value: bool, on_change: Callable, disabled: bool = false) -> void:
	var row := _row(parent, title, hint)
	var strip := _segment(row)
	strip.custom_minimum_size.x = 132.0
	var group := ButtonGroup.new()
	group.allow_unpress = false
	var off := _segment_button("Off")
	off.button_group = group
	off.button_pressed = not value
	off.disabled = disabled
	off.toggled.connect(func(on: bool) -> void:
		if on:
			on_change.call(false)
	)
	strip.add_child(off)
	var on := _segment_button("On")
	on.button_group = group
	on.button_pressed = value
	on.disabled = disabled
	on.toggled.connect(func(selected: bool) -> void:
		if selected:
			on_change.call(true)
	)
	strip.add_child(on)


func _choice_row(parent: Control, title: String, hint: String, options: Array, current: Variant, on_change: Callable, disabled: bool = false) -> void:
	var row := _row(parent, title, hint)
	if options.size() > 4:
		var option := _option_control(options, current, on_change)
		option.disabled = disabled
		row.add_child(option)
		return
	var strip := _segment(row)
	strip.custom_minimum_size.x = 132.0
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for entry in options:
		var data: Dictionary = entry
		var value: Variant = data.get("value")
		var button := _segment_button(str(data.get("label", "")))
		button.button_group = group
		button.button_pressed = value == current
		# A capability row can disable individual options (for example 4K shadows
		# on a mobile-safe profile) without disabling the whole row.
		button.disabled = disabled or bool(data.get("disabled", false))
		button.toggled.connect(func(selected: bool) -> void:
			if selected:
				on_change.call(value)
		)
		strip.add_child(button)


func _segment(parent: Control) -> HBoxContainer:
	var track := PanelContainer.new()
	track.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_2, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	parent.add_child(track)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 2)
	track.add_child(strip)
	return strip


func _segment_button(text_value: String) -> Button:
	var button := Kit.text_toggle(text_value, "", true)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_stylebox_override("normal", Kit.flat_style(Color(0, 0, 0, 0), Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("hover", Kit.flat_style(Kit.SURFACE_HOVER, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("pressed", Kit.flat_style(Kit.SURFACE_ACTIVE, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("hover_pressed", Kit.flat_style(Kit.SURFACE_ACTIVE.lightened(0.04), Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	button.add_theme_color_override("font_color", Kit.TEXT_MUTED)
	button.add_theme_color_override("font_hover_color", Kit.TEXT)
	button.add_theme_color_override("font_pressed_color", Kit.TEXT)
	return button


func _option_control(options: Array, current: Variant, on_change: Callable) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(132, 44)
	option.focus_mode = Control.FOCUS_NONE
	option.add_theme_font_override("font", Kit.font_medium)
	option.add_theme_font_size_override("font_size", Kit.TYPE_BODY)
	option.add_theme_color_override("font_color", Kit.TEXT)
	option.add_theme_color_override("font_hover_color", Kit.TEXT)
	option.add_theme_color_override("font_pressed_color", Kit.TEXT)
	option.add_theme_color_override("font_disabled_color", Kit.TEXT_DIM)
	for state in ["normal", "hover", "pressed", "focus"]:
		var fill := Kit.SURFACE_2
		if state == "hover":
			fill = Kit.SURFACE_HOVER
		elif state == "pressed":
			fill = Kit.SURFACE_ACTIVE
		option.add_theme_stylebox_override(state, Kit.flat_style(fill, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	option.add_theme_stylebox_override("disabled", Kit.flat_style(Kit.SURFACE, Kit.R_CONTROL, Color(0, 0, 0, 0), 0))
	var selected := 0
	for i in range(options.size()):
		var data: Dictionary = options[i]
		option.add_item(str(data.get("label", "")), i)
		option.set_item_metadata(i, data.get("value"))
		option.set_item_disabled(i, bool(data.get("disabled", false)))
		if data.get("value") == current:
			selected = i
	option.selected = selected
	var popup := option.get_popup()
	popup.add_theme_font_override("font", Kit.font_regular)
	popup.add_theme_font_size_override("font_size", Kit.TYPE_BODY)
	popup.add_theme_stylebox_override("panel", Kit.flat_style(Kit.SURFACE_2, Kit.R_FLOAT, Kit.BORDER, 1))
	popup.add_theme_color_override("font_color", Kit.TEXT)
	popup.add_theme_color_override("font_hover_color", Kit.TEXT)
	popup.add_theme_color_override("font_disabled_color", Kit.TEXT_DIM)
	option.item_selected.connect(func(index: int) -> void:
		on_change.call(option.get_item_metadata(index))
	)
	return option


func _number_row(parent: Control, title: String, unit: String, minimum: float, maximum: float, step: float, value: float, on_change: Callable) -> void:
	var row := _row(parent, title, "")
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	row.add_child(box)
	var field := Kit.line_edit()
	field.custom_minimum_size = Vector2(96, 44)
	field.text = _format_number(value, step)
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	box.add_child(field)
	if unit != "":
		var unit_label := Kit.mono_label(unit, Kit.TYPE_MONO, Kit.TEXT_DIM)
		unit_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(unit_label)
	var apply := func() -> void:
		var text := field.text.strip_edges()
		var parsed := value
		if text.is_valid_float():
			parsed = float(text)
		parsed = clampf(snappedf(parsed, step), minimum, maximum)
		field.text = _format_number(parsed, step)
		on_change.call(parsed)
	field.text_submitted.connect(func(_text: String) -> void: apply.call())
	field.focus_exited.connect(func() -> void: apply.call())


func _format_number(value: float, step: float) -> String:
	if step >= 1.0:
		return "%d" % int(round(value))
	if step >= 0.1:
		return "%.1f" % value
	return "%.2f" % value


func _section_reset(parent: Control, section: String, label_text: String) -> void:
	var button := Kit.text_button(label_text, "rotate-ccw", false, true)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.pressed.connect(func() -> void:
		Prefs.reset_section(section)
		if section == "graphics":
			Gfx.apply_preset("balanced")
		if editor != null and editor.has_method("_on_settings_pref_changed"):
			editor.call("_on_settings_pref_changed", section + ".reset")
		_rebuild()
	)
	parent.add_child(button)


# -------------------------------------------------------------------------
# Runtime wiring
# -------------------------------------------------------------------------

func _ready() -> void:
	Perf.sample_updated.connect(_refresh_stats)
	_refresh_stats(Perf.sample())


func _exit_tree() -> void:
	if Perf.sample_updated.is_connected(_refresh_stats):
		Perf.sample_updated.disconnect(_refresh_stats)


func _after_pref_change(key: String) -> void:
	if editor != null and editor.has_method("_on_settings_pref_changed"):
		editor.call("_on_settings_pref_changed", key)
	if key.begins_with("performance.") or key == "editor.show_fps":
		_refresh_stats(Perf.sample())


func _engine_version() -> String:
	var info := Engine.get_version_info()
	return "%d.%d.%d-%s" % [
		int(info.get("major", 4)),
		int(info.get("minor", 0)),
		int(info.get("patch", 0)),
		str(info.get("status", "stable")),
	]
