extends Node
## Shared visual language for Kinema Studio.
## Autoloaded as `Kit`. Owns the UI theme, fonts and the small SVG icon set.
## Everything here is deliberately conservative: two surfaces, one accent,
## generous spacing and 1 px hairlines. No gradients, no decorative chrome.

const BG := Color(0.043, 0.059, 0.078, 1.0)
const SURFACE := Color(0.067, 0.086, 0.114, 1.0)
const SURFACE_2 := Color(0.082, 0.106, 0.137, 1.0)
const SURFACE_3 := Color(0.106, 0.133, 0.169, 1.0)
const SURFACE_HOVER := Color(0.118, 0.149, 0.188, 1.0)
const BORDER := Color(0.137, 0.173, 0.216, 1.0)
const BORDER_SOFT := Color(0.098, 0.125, 0.157, 1.0)
const TEXT := Color(0.910, 0.925, 0.949, 1.0)
const TEXT_MUTED := Color(0.533, 0.580, 0.651, 1.0)
const TEXT_DIM := Color(0.353, 0.400, 0.467, 1.0)
const ACCENT := Color(0.851, 0.647, 0.396, 1.0)
const ACCENT_BRIGHT := Color(0.929, 0.733, 0.478, 1.0)
const ACCENT_DARK := Color(0.227, 0.173, 0.110, 1.0)
const DANGER := Color(0.843, 0.424, 0.424, 1.0)
const SUCCESS := Color(0.435, 0.714, 0.541, 1.0)
const WARNING := Color(0.894, 0.678, 0.365, 1.0)

const AXIS_X := Color(0.851, 0.412, 0.384, 1.0)
const AXIS_Y := Color(0.514, 0.710, 0.427, 1.0)
const AXIS_Z := Color(0.365, 0.553, 0.847, 1.0)

const FONT_UI := "res://assets/fonts/Inter.ttf"
const FONT_MONO := "res://assets/fonts/JetBrainsMono.ttf"
const ICON_DIR := "res://assets/icons/"

var theme: Theme
var font_regular: Font
var font_medium: Font
var font_semibold: Font
var font_mono: Font

var _font_file: FontFile
var _mono_file: FontFile
var _fonts: Dictionary = {}
var _icons: Dictionary = {}
var _icon_cache: Dictionary = {}
var _wght_tag: int = 0

func _ready() -> void:
	_wght_tag = TextServerManager.get_primary_interface().name_to_tag("wght")
	_load_fonts()
	_build_theme()
	# Autoloads are ready before the main scene, so the root window is the only
	# reliable place to install the theme for every screen and modal.
	if get_tree() != null:
		get_tree().root.theme = theme

func _load_fonts() -> void:
	_font_file = FontFile.new()
	var err := _font_file.load_dynamic_font(FONT_UI)
	if err != OK:
		push_warning("Kinema: Inter could not be loaded, using the engine UI font.")
		_font_file = null

	_mono_file = FontFile.new()
	err = _mono_file.load_dynamic_font(FONT_MONO)
	if err != OK:
		_mono_file = null

	font_regular = _variation(_font_file, 430)
	font_medium = _variation(_font_file, 540)
	font_semibold = _variation(_font_file, 650)
	font_mono = _variation(_mono_file, 460)
	_fonts = {
		400: font_regular,
		500: font_medium,
		600: font_semibold,
	}

func _variation(base: FontFile, weight: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base if base != null else ThemeDB.fallback_font
	if base != null and _wght_tag != 0:
		fv.variation_opentype = { _wght_tag: weight }
	return fv

func _build_theme() -> void:
	theme = Theme.new()
	theme.default_font = font_regular
	theme.default_font_size = 13

	# ---- Core controls ------------------------------------------------
	var transparent := flat_style(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0))
	var base_button := flat_style(Color(0, 0, 0, 0), 4, Color(0, 0, 0, 0))
	var hover_button := flat_style(SURFACE_HOVER, 4, BORDER_SOFT)
	var pressed_button := flat_style(SURFACE_3, 4, BORDER)
	var disabled_button := flat_style(Color(0, 0, 0, 0), 4, Color(0, 0, 0, 0))

	theme.set_stylebox("normal", "Button", base_button)
	theme.set_stylebox("hover", "Button", hover_button)
	theme.set_stylebox("pressed", "Button", pressed_button)
	theme.set_stylebox("disabled", "Button", disabled_button)
	theme.set_stylebox("focus", "Button", flat_style(Color(0, 0, 0, 0), 4, ACCENT * Color(1, 1, 1, 0.28)))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", TEXT)
	theme.set_color("font_focus_color", "Button", TEXT)
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)
	theme.set_color("icon_normal_color", "Button", TEXT_MUTED)
	theme.set_color("icon_hover_color", "Button", TEXT)
	theme.set_color("icon_pressed_color", "Button", ACCENT)
	theme.set_color("icon_focus_color", "Button", TEXT)
	theme.set_color("icon_disabled_color", "Button", TEXT_DIM * Color(1, 1, 1, 0.45))
	theme.set_font("font", "Button", font_medium)
	theme.set_font_size("font_size", "Button", 13)
	theme.set_constant("h_separation", "Button", 7)

	# Primary action.
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", flat_style(ACCENT, 4, ACCENT))
	theme.set_stylebox("hover", "PrimaryButton", flat_style(ACCENT_BRIGHT, 4, ACCENT_BRIGHT))
	theme.set_stylebox("pressed", "PrimaryButton", flat_style(ACCENT.darkened(0.12), 4, ACCENT.darkened(0.12)))
	theme.set_stylebox("focus", "PrimaryButton", flat_style(Color(0, 0, 0, 0), 4, ACCENT_BRIGHT))
	theme.set_color("font_color", "PrimaryButton", Color(0.09, 0.07, 0.05, 1))
	theme.set_color("font_hover_color", "PrimaryButton", Color(0.09, 0.07, 0.05, 1))
	theme.set_color("font_pressed_color", "PrimaryButton", Color(0.09, 0.07, 0.05, 1))
	theme.set_color("icon_normal_color", "PrimaryButton", Color(0.09, 0.07, 0.05, 1))
	theme.set_color("icon_hover_color", "PrimaryButton", Color(0.09, 0.07, 0.05, 1))
	theme.set_color("icon_pressed_color", "PrimaryButton", Color(0.09, 0.07, 0.05, 1))
	theme.set_font("font", "PrimaryButton", font_semibold)

	# Quiet action.
	theme.set_type_variation("QuietButton", "Button")
	theme.set_stylebox("normal", "QuietButton", flat_style(SURFACE_2, 4, BORDER_SOFT))
	theme.set_stylebox("hover", "QuietButton", flat_style(SURFACE_3, 4, BORDER))
	theme.set_stylebox("pressed", "QuietButton", flat_style(SURFACE_2, 4, BORDER))
	theme.set_color("font_color", "QuietButton", TEXT)
	theme.set_color("icon_normal_color", "QuietButton", TEXT_MUTED)

	# Small action.
	theme.set_type_variation("SmallButton", "Button")
	theme.set_font("font", "SmallButton", font_medium)
	theme.set_font_size("font_size", "SmallButton", 11)
	theme.set_stylebox("normal", "SmallButton", flat_style(SURFACE_2, 4, BORDER_SOFT))
	theme.set_stylebox("hover", "SmallButton", flat_style(SURFACE_HOVER, 4, BORDER))
	theme.set_stylebox("pressed", "SmallButton", flat_style(SURFACE_3, 4, BORDER))
	theme.set_constant("h_separation", "SmallButton", 5)

	# Label.
	theme.set_color("font_color", "Label", TEXT)
	theme.set_font("font", "Label", font_regular)
	theme.set_font_size("font_size", "Label", 13)

	# Panels.
	theme.set_stylebox("panel", "PanelContainer", flat_style(SURFACE, 0, BORDER_SOFT))
	theme.set_stylebox("panel", "Panel", flat_style(SURFACE, 0, BORDER_SOFT))

	# LineEdit.
	var field := flat_style(SURFACE_2, 4, BORDER_SOFT)
	field.content_margin_left = 9
	field.content_margin_right = 9
	field.content_margin_top = 7
	field.content_margin_bottom = 7
	var field_focus := flat_style(SURFACE_2, 4, ACCENT * Color(1, 1, 1, 0.65))
	field_focus.content_margin_left = 9
	field_focus.content_margin_right = 9
	field_focus.content_margin_top = 7
	field_focus.content_margin_bottom = 7
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", field_focus)
	theme.set_stylebox("read_only", "LineEdit", field)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("selection_color", "LineEdit", ACCENT * Color(1, 1, 1, 0.22))
	theme.set_font("font", "LineEdit", font_regular)
	theme.set_font_size("font_size", "LineEdit", 13)

	# Scrollbars: thin, almost invisible until hovered.
	theme.set_stylebox("scroll", "VScrollBar", flat_style(Color(0, 0, 0, 0), 3, Color(0, 0, 0, 0)))
	theme.set_stylebox("grabber", "VScrollBar", flat_style(BORDER, 3, Color(0, 0, 0, 0)))
	theme.set_stylebox("grabber_highlight", "VScrollBar", flat_style(TEXT_DIM, 3, Color(0, 0, 0, 0)))
	theme.set_stylebox("grabber_pressed", "VScrollBar", flat_style(TEXT_MUTED, 3, Color(0, 0, 0, 0)))
	theme.set_stylebox("scroll", "HScrollBar", flat_style(Color(0, 0, 0, 0), 3, Color(0, 0, 0, 0)))
	theme.set_stylebox("grabber", "HScrollBar", flat_style(BORDER, 3, Color(0, 0, 0, 0)))
	theme.set_stylebox("grabber_highlight", "HScrollBar", flat_style(TEXT_DIM, 3, Color(0, 0, 0, 0)))
	theme.set_stylebox("grabber_pressed", "HScrollBar", flat_style(TEXT_MUTED, 3, Color(0, 0, 0, 0)))

	# Popup menus (only used where a native dropdown is genuinely useful).
	theme.set_stylebox("panel", "PopupMenu", flat_style(SURFACE_2, 6, BORDER))
	theme.set_stylebox("hover", "PopupMenu", flat_style(SURFACE_3, 3, Color(0, 0, 0, 0)))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", TEXT)
	theme.set_color("font_accelerator_color", "PopupMenu", TEXT_DIM)
	theme.set_font("font", "PopupMenu", font_regular)
	theme.set_font_size("font_size", "PopupMenu", 13)

	# Tooltip.
	theme.set_stylebox("panel", "TooltipPanel", flat_style(Color(0.05, 0.065, 0.083, 0.98), 4, BORDER))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_font("font", "TooltipLabel", font_regular)
	theme.set_font_size("font_size", "TooltipLabel", 11)

	# Progress, mostly for render operations.
	theme.set_stylebox("background", "ProgressBar", flat_style(SURFACE_2, 3, BORDER_SOFT))
	theme.set_stylebox("fill", "ProgressBar", flat_style(ACCENT, 3, ACCENT))
	theme.set_color("font_color", "ProgressBar", TEXT_MUTED)
	theme.set_font_size("font_size", "ProgressBar", 10)

func flat_style(color: Color, radius: int = 4, border: Color = BORDER, border_width: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = border
	sb.set_border_width_all(border_width if border.a > 0.0 else 0)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	return sb

func style_with_margins(color: Color, radius: int, border: Color, border_width: int, margins: Vector4) -> StyleBoxFlat:
	var sb := flat_style(color, radius, border, border_width)
	sb.content_margin_left = margins.x
	sb.content_margin_top = margins.y
	sb.content_margin_right = margins.z
	sb.content_margin_bottom = margins.w
	return sb

# ---- Small constructors -------------------------------------------------

func label(text_value: String, size: int = 13, color: Color = TEXT, weight: int = 400) -> Label:
	var l := Label.new()
	l.text = text_value
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", font_for(weight))
	l.add_theme_font_size_override("font_size", size)
	return l

func section_label(text_value: String) -> Label:
	var l := label(text_value.to_upper(), 10, TEXT_MUTED, 600)
	l.add_theme_constant_override("outline_size", 0)
	return l

func mono_label(text_value: String, size: int = 12, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text_value
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", font_mono)
	l.add_theme_font_size_override("font_size", size)
	return l

func font_for(weight: int) -> Font:
	var key := 400
	if weight >= 600:
		key = 600
	elif weight >= 500:
		key = 500
	return _fonts.get(key, font_regular)

## Touch input is translated to mouse events for standard Godot controls.
## Custom controls handle the original touch event, so they ignore the
## synthesized mouse copy to avoid acting twice on one finger.
func is_emulated_mouse(event: InputEvent) -> bool:
	return event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION

## Makes a Control activate on a clean tap or click rather than on press.
## This lets a ScrollContainer start a drag when the same gesture begins on
## the control, and prevents a scroll flick from opening an item.
func bind_tap(control: Control, on_tap: Callable, touch_threshold: float = 12.0, mouse_threshold: float = 6.0) -> void:
	control.gui_input.connect(_tap_input.bind(control, on_tap, touch_threshold, mouse_threshold))

func _tap_input(event: InputEvent, control: Control, on_tap: Callable, touch_threshold: float, mouse_threshold: float) -> void:
	if is_emulated_mouse(event):
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			control.set_meta("_kinema_tap_active", true)
			control.set_meta("_kinema_tap_start", touch.position)
			control.set_meta("_kinema_tap_travel", 0.0)
			return
		var travel := float(control.get_meta("_kinema_tap_travel", 0.0))
		var active := bool(control.get_meta("_kinema_tap_active", false))
		control.set_meta("_kinema_tap_active", false)
		if active and travel <= touch_threshold:
			on_tap.call()
	elif event is InputEventScreenDrag:
		if bool(control.get_meta("_kinema_tap_active", false)):
			control.set_meta("_kinema_tap_travel", float(control.get_meta("_kinema_tap_travel", 0.0)) + (event as InputEventScreenDrag).relative.length())
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			control.set_meta("_kinema_tap_active", true)
			control.set_meta("_kinema_tap_start", button.position)
			control.set_meta("_kinema_tap_travel", 0.0)
			return
		var travel := float(control.get_meta("_kinema_tap_travel", 0.0))
		var start := Vector2(control.get_meta("_kinema_tap_start", button.position))
		var active := bool(control.get_meta("_kinema_tap_active", false))
		control.set_meta("_kinema_tap_active", false)
		if active and maxf(travel, button.position.distance_to(start)) <= mouse_threshold:
			on_tap.call()
	elif event is InputEventMouseMotion:
		if bool(control.get_meta("_kinema_tap_active", false)):
			var motion := event as InputEventMouseMotion
			var start := Vector2(control.get_meta("_kinema_tap_start", motion.position))
			control.set_meta("_kinema_tap_travel", motion.position.distance_to(start))

func icon_texture(icon_name: String) -> Texture2D:
	if _icons.has(icon_name):
		return _icons[icon_name]
	var path := ICON_DIR + icon_name + ".svg"
	if not FileAccess.file_exists(path):
		path = ICON_DIR + "circle-dot.svg"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var svg := f.get_as_text()
	var image := Image.new()
	if image.load_svg_from_string(svg, 2.5) != OK:
		return null
	var texture := ImageTexture.create_from_image(image)
	_icons[icon_name] = texture
	return texture

func icon(icon_name: String, color: Color = TEXT_MUTED, size: int = 16) -> TextureRect:
	var t := TextureRect.new()
	t.texture = icon_texture(icon_name)
	t.custom_minimum_size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func icon_button(icon_name: String, tooltip: String = "", size: int = 34, icon_size: int = 17) -> Button:
	var b := Button.new()
	b.icon = icon_texture(icon_name)
	b.expand_icon = false
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(size, size)
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_constant_override("icon_max_width", icon_size)
	b.add_theme_constant_override("h_separation", 0)
	b.add_theme_color_override("icon_normal_color", TEXT_MUTED)
	b.add_theme_color_override("icon_hover_color", TEXT)
	b.add_theme_color_override("icon_pressed_color", ACCENT)
	b.add_theme_stylebox_override("normal", flat_style(Color(0, 0, 0, 0), 5, Color(0, 0, 0, 0), 0))
	b.add_theme_stylebox_override("hover", flat_style(SURFACE_HOVER, 5, BORDER_SOFT))
	b.add_theme_stylebox_override("pressed", flat_style(SURFACE_3, 5, BORDER))
	b.add_theme_stylebox_override("focus", flat_style(Color(0, 0, 0, 0), 5, Color(0, 0, 0, 0), 0))
	return b

func text_button(text_value: String, icon_name: String = "", primary: bool = false, compact: bool = false) -> Button:
	var b := Button.new()
	b.text = text_value
	b.focus_mode = Control.FOCUS_NONE
	if icon_name != "":
		b.icon = icon_texture(icon_name)
		b.add_theme_constant_override("icon_max_width", 15)
	b.custom_minimum_size.y = 30 if compact else 34
	b.add_theme_constant_override("h_separation", 6)
	if primary:
		b.theme_type_variation = "PrimaryButton"
	elif compact:
		b.theme_type_variation = "SmallButton"
	else:
		b.theme_type_variation = "QuietButton"
	return b

func set_icon(button: Button, icon_name: String) -> void:
	button.icon = icon_texture(icon_name)

func set_icon_active(button: Button, active: bool) -> void:
	if active:
		button.add_theme_color_override("icon_normal_color", ACCENT)
		button.add_theme_color_override("icon_hover_color", ACCENT_BRIGHT)
		button.add_theme_color_override("icon_pressed_color", ACCENT)
		button.add_theme_stylebox_override("normal", flat_style(ACCENT_DARK, 5, ACCENT * Color(1, 1, 1, 0.4)))
		button.add_theme_stylebox_override("hover", flat_style(ACCENT_DARK.lightened(0.04), 5, ACCENT * Color(1, 1, 1, 0.55)))
		button.add_theme_stylebox_override("pressed", flat_style(ACCENT_DARK.darkened(0.06), 5, ACCENT))
	else:
		button.add_theme_color_override("icon_normal_color", TEXT_MUTED)
		button.add_theme_color_override("icon_hover_color", TEXT)
		button.add_theme_color_override("icon_pressed_color", ACCENT)
		button.add_theme_stylebox_override("normal", flat_style(Color(0, 0, 0, 0), 5, Color(0, 0, 0, 0), 0))
		button.add_theme_stylebox_override("hover", flat_style(SURFACE_HOVER, 5, BORDER_SOFT))
		button.add_theme_stylebox_override("pressed", flat_style(SURFACE_3, 5, BORDER))

func text_toggle(text_value: String, icon_name: String = "", accent: bool = false) -> Button:
	var b := Button.new()
	b.text = text_value
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 26
	b.add_theme_font_override("font", font_medium)
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", TEXT_MUTED)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", ACCENT if accent else TEXT)
	b.add_theme_color_override("font_hover_pressed_color", ACCENT if accent else TEXT)
	b.add_theme_color_override("icon_normal_color", TEXT_MUTED)
	b.add_theme_color_override("icon_hover_color", TEXT)
	b.add_theme_color_override("icon_pressed_color", ACCENT if accent else TEXT)
	b.add_theme_color_override("icon_hover_pressed_color", ACCENT if accent else TEXT)
	b.add_theme_stylebox_override("normal", style_with_margins(Color(0, 0, 0, 0), 4, Color(0, 0, 0, 0), 0, Vector4(9, 2, 9, 2)))
	b.add_theme_stylebox_override("hover", style_with_margins(SURFACE_HOVER, 4, Color(0, 0, 0, 0), 0, Vector4(9, 2, 9, 2)))
	b.add_theme_stylebox_override("pressed", style_with_margins(ACCENT_DARK, 4, ACCENT * Color(1, 1, 1, 0.32), 0, Vector4(9, 2, 9, 2)))
	b.add_theme_stylebox_override("hover_pressed", style_with_margins(ACCENT_DARK.lightened(0.03), 4, ACCENT * Color(1, 1, 1, 0.5), 0, Vector4(9, 2, 9, 2)))
	b.add_theme_stylebox_override("focus", flat_style(Color(0, 0, 0, 0), 4, Color(0, 0, 0, 0), 0))
	if icon_name != "":
		b.icon = icon_texture(icon_name)
		b.add_theme_constant_override("icon_max_width", 14)
		b.add_theme_constant_override("h_separation", 5)
	return b

func panel(color: Color = SURFACE, border: Color = BORDER_SOFT, radius: int = 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat_style(color, radius, border))
	return p

func style_panel(p: Control, color: Color = SURFACE, border: Color = BORDER_SOFT, radius: int = 0, border_width: int = 1) -> void:
	p.add_theme_stylebox_override("panel", flat_style(color, radius, border, border_width))

func line_edit(placeholder: String = "", size: int = 13) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.add_theme_font_override("font", font_regular)
	e.add_theme_font_size_override("font_size", size)
	e.custom_minimum_size.y = 30
	return e

func hsep(color: Color = BORDER_SOFT) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.custom_minimum_size = Vector2(1, 0)
	c.size_flags_vertical = Control.SIZE_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func vsep(color: Color = BORDER_SOFT) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.custom_minimum_size = Vector2(0, 1)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func gap(width: float, height: float = 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func set_margins(container: Control, left: int, top: int, right: int, bottom: int) -> void:
	container.add_theme_constant_override("margin_left", left)
	container.add_theme_constant_override("margin_top", top)
	container.add_theme_constant_override("margin_right", right)
	container.add_theme_constant_override("margin_bottom", bottom)

func tooltip_icon(button: Control, text_value: String) -> void:
	button.tooltip_text = text_value
