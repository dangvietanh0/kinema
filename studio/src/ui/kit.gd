extends Node
## Shared visual language for Kinema Studio.
## Autoloaded as `Kit`. Owns the UI theme, fonts and the small SVG icon set.
## Everything here is deliberately conservative: graphite surfaces, grey
## hairlines and luminance-only state. No gradients, no hue in the chrome.

const Tokens = preload("res://src/ui/tokens.gd")

const BG := Tokens.BG
const SURFACE := Tokens.SURFACE
const SURFACE_2 := Tokens.SURFACE_2
const SURFACE_3 := Tokens.SURFACE_3
const SURFACE_HOVER := Tokens.SURFACE_HOVER
const BORDER := Tokens.BORDER
const BORDER_SOFT := Tokens.BORDER_SOFT
const TEXT := Tokens.TEXT
const TEXT_MUTED := Tokens.TEXT_MUTED
const TEXT_DIM := Tokens.TEXT_DIM

# Time and focus are separate luminance roles: keys, the playhead and the 3D
# selection are TIME; panels, tools and primary actions are FOCUS.
const TIME := Tokens.TIME
const TIME_BRIGHT := Tokens.TIME_BRIGHT
const TIME_DARK := Tokens.TIME_DARK
# Legacy aliases. Prefer the TIME names in new code.
const ACCENT := Tokens.TIME
const ACCENT_BRIGHT := Tokens.TIME_BRIGHT
const ACCENT_DARK := Tokens.TIME_DARK
const FOCUS := Tokens.FOCUS
const FOCUS_BRIGHT := Tokens.FOCUS_BRIGHT
const FOCUS_DARK := Tokens.FOCUS_DARK
const DANGER := Tokens.DANGER
const SUCCESS := Tokens.SUCCESS
const WARNING := Tokens.WARNING
const SCRIM := Tokens.SCRIM
const GRID := Tokens.GRID
const GRID_MAJOR := Tokens.GRID_MAJOR

const AXIS_X := Tokens.AXIS_X
const AXIS_Y := Tokens.AXIS_Y
const AXIS_Z := Tokens.AXIS_Z

# Type roles are re-exported so call sites never hand-pick a size.
const TYPE_CAPTION := Tokens.TYPE_CAPTION
const TYPE_BODY := Tokens.TYPE_BODY
const TYPE_EMPHASIS := Tokens.TYPE_EMPHASIS
const TYPE_TITLE := Tokens.TYPE_TITLE
const TYPE_PAGE := Tokens.TYPE_PAGE
const TYPE_MONO := Tokens.TYPE_MONO
const TYPE_MONO_LARGE := Tokens.TYPE_MONO_LARGE
const TYPE_RULER := Tokens.TYPE_RULER
const FIELD := Tokens.FIELD

# Action geometry: primary actions are landscape rectangles, never squares.
# Footer secondaries still clear the 44 dp touch floor with room for a label.
const ACTION_MIN_WIDTH := 96.0
const FOOTER_MIN_WIDTH := 80.0

const FONT_UI := "res://assets/fonts/IBMPlexSans-Regular.ttf"
const FONT_UI_MEDIUM := "res://assets/fonts/IBMPlexSans-Medium.ttf"
const FONT_UI_SEMIBOLD := "res://assets/fonts/IBMPlexSans-SemiBold.ttf"
const FONT_MONO := "res://assets/fonts/IBMPlexMono-Regular.ttf"
const ICON_DIR := "res://assets/icons/"

var theme: Theme
var font_regular: Font
var font_medium: Font
var font_semibold: Font
var font_mono: Font

var _fonts: Dictionary = {}
var _icons: Dictionary = {}
var _icon_cache: Dictionary = {}

func _ready() -> void:
	_load_fonts()
	_build_theme()
	# Autoloads are ready before the main scene, so the root window is the only
	# reliable place to install the theme for every screen and modal.
	if get_tree() != null:
		get_tree().root.theme = theme

func _load_fonts() -> void:
	font_regular = _load_face(FONT_UI)
	font_medium = _load_face(FONT_UI_MEDIUM)
	font_semibold = _load_face(FONT_UI_SEMIBOLD)
	font_mono = _load_face(FONT_MONO)
	if font_regular == ThemeDB.fallback_font:
		push_warning("Kinema: IBM Plex Sans could not be loaded, using the engine UI font.")
	_fonts = {
		400: font_regular,
		500: font_medium,
		600: font_semibold,
	}

func _load_face(path: String) -> Font:
	var file := FontFile.new()
	var err := file.load_dynamic_font(path)
	if err != OK:
		return ThemeDB.fallback_font
	return file

func _build_theme() -> void:
	theme = Theme.new()
	theme.default_font = font_regular
	theme.default_font_size = TYPE_BODY

	# ---- Core controls ------------------------------------------------
	var transparent := flat_style(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0))
	var base_button := flat_style(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0)
	var hover_button := flat_style(SURFACE_HOVER, 0, Color(0, 0, 0, 0), 0)
	var pressed_button := flat_style(SURFACE_3, 0, Color(0, 0, 0, 0), 0)
	var disabled_button := flat_style(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0))

	theme.set_stylebox("normal", "Button", base_button)
	theme.set_stylebox("hover", "Button", hover_button)
	theme.set_stylebox("pressed", "Button", pressed_button)
	theme.set_stylebox("disabled", "Button", disabled_button)
	theme.set_stylebox("focus", "Button", flat_style(Color(0, 0, 0, 0), 0, FOCUS * Color(1, 1, 1, 0.35)))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", FOCUS_BRIGHT)
	theme.set_color("font_focus_color", "Button", TEXT)
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)
	theme.set_color("icon_normal_color", "Button", TEXT_MUTED)
	theme.set_color("icon_hover_color", "Button", TEXT)
	theme.set_color("icon_pressed_color", "Button", FOCUS_BRIGHT)
	theme.set_color("icon_focus_color", "Button", TEXT)
	theme.set_color("icon_disabled_color", "Button", TEXT_DIM * Color(1, 1, 1, 0.45))
	theme.set_font("font", "Button", font_medium)
	theme.set_font_size("font_size", "Button", TYPE_BODY)
	theme.set_constant("h_separation", "Button", 7)

	# Primary action: the one white fill in the interface. Black type on white
	# keeps the workbench monochrome and makes the intended action obvious.
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", flat_style(FOCUS, 0, FOCUS))
	theme.set_stylebox("hover", "PrimaryButton", flat_style(FOCUS_BRIGHT, 0, FOCUS_BRIGHT))
	theme.set_stylebox("pressed", "PrimaryButton", flat_style(FOCUS.darkened(0.14), 0, FOCUS.darkened(0.14)))
	theme.set_stylebox("focus", "PrimaryButton", flat_style(Color(0, 0, 0, 0), 0, FOCUS_BRIGHT))
	theme.set_color("font_color", "PrimaryButton", BG)
	theme.set_color("font_hover_color", "PrimaryButton", BG)
	theme.set_color("font_pressed_color", "PrimaryButton", BG)
	theme.set_color("icon_normal_color", "PrimaryButton", BG)
	theme.set_color("icon_hover_color", "PrimaryButton", BG)
	theme.set_color("icon_pressed_color", "PrimaryButton", BG)
	theme.set_font("font", "PrimaryButton", font_semibold)

	# Quiet action: no frame, only a surface on hover.
	theme.set_type_variation("QuietButton", "Button")
	theme.set_stylebox("normal", "QuietButton", flat_style(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0))
	theme.set_stylebox("hover", "QuietButton", flat_style(SURFACE_3, 0, Color(0, 0, 0, 0), 0))
	theme.set_stylebox("pressed", "QuietButton", flat_style(SURFACE_3, 0, Color(0, 0, 0, 0), 0))
	theme.set_color("font_color", "QuietButton", TEXT)
	theme.set_color("icon_normal_color", "QuietButton", TEXT_MUTED)

	# Small action: a compact chip. The fill separates it from the panel; a
	# hairline around every chip made the workbench look like a wireframe.
	theme.set_type_variation("SmallButton", "Button")
	theme.set_font("font", "SmallButton", font_medium)
	theme.set_font_size("font_size", "SmallButton", TYPE_CAPTION)
	theme.set_stylebox("normal", "SmallButton", flat_style(SURFACE_2, 0, Color(0, 0, 0, 0), 0))
	theme.set_stylebox("hover", "SmallButton", flat_style(SURFACE_3, 0, Color(0, 0, 0, 0), 0))
	theme.set_stylebox("pressed", "SmallButton", flat_style(SURFACE_3, 0, Color(0, 0, 0, 0), 0))
	theme.set_constant("h_separation", "SmallButton", 5)

	# Label.
	theme.set_color("font_color", "Label", TEXT)
	theme.set_font("font", "Label", font_regular)
	theme.set_font_size("font_size", "Label", TYPE_BODY)

	# Panels.
	theme.set_stylebox("panel", "PanelContainer", flat_style(SURFACE, 0, BORDER_SOFT))
	theme.set_stylebox("panel", "Panel", flat_style(SURFACE, 0, BORDER_SOFT))

	# LineEdit. Fields are 44 dp tall everywhere: a comfortable touch target
	# with 12 dp of horizontal breathing room and a 13 sp value.
	var field := flat_style(SURFACE_2, 0, BORDER_SOFT)
	field.content_margin_left = 12
	field.content_margin_right = 12
	field.content_margin_top = 10
	field.content_margin_bottom = 10
	var field_focus := flat_style(SURFACE_2, 0, FOCUS * Color(1, 1, 1, 0.65))
	field_focus.content_margin_left = 12
	field_focus.content_margin_right = 12
	field_focus.content_margin_top = 10
	field_focus.content_margin_bottom = 10
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", field_focus)
	theme.set_stylebox("read_only", "LineEdit", field)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)
	theme.set_color("caret_color", "LineEdit", FOCUS_BRIGHT)
	theme.set_color("selection_color", "LineEdit", FOCUS * Color(1, 1, 1, 0.24))
	theme.set_font("font", "LineEdit", font_regular)
	theme.set_font_size("font_size", "LineEdit", TYPE_EMPHASIS)

	# Scrollbars: thin, almost invisible until hovered.
	theme.set_stylebox("scroll", "VScrollBar", flat_style(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0)))
	theme.set_stylebox("grabber", "VScrollBar", flat_style(BORDER, 0, Color(0, 0, 0, 0)))
	theme.set_stylebox("grabber_highlight", "VScrollBar", flat_style(TEXT_DIM, 0, Color(0, 0, 0, 0)))
	theme.set_stylebox("grabber_pressed", "VScrollBar", flat_style(TEXT_MUTED, 0, Color(0, 0, 0, 0)))
	theme.set_stylebox("scroll", "HScrollBar", flat_style(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0)))
	theme.set_stylebox("grabber", "HScrollBar", flat_style(BORDER, 0, Color(0, 0, 0, 0)))
	theme.set_stylebox("grabber_highlight", "HScrollBar", flat_style(TEXT_DIM, 0, Color(0, 0, 0, 0)))
	theme.set_stylebox("grabber_pressed", "HScrollBar", flat_style(TEXT_MUTED, 0, Color(0, 0, 0, 0)))

	# Popup menus (only used where a native dropdown is genuinely useful).
	theme.set_stylebox("panel", "PopupMenu", flat_style(SURFACE_2, 0, BORDER))
	theme.set_stylebox("hover", "PopupMenu", flat_style(SURFACE_3, 0, Color(0, 0, 0, 0)))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", TEXT)
	theme.set_color("font_accelerator_color", "PopupMenu", TEXT_DIM)
	theme.set_font("font", "PopupMenu", font_regular)
	theme.set_font_size("font_size", "PopupMenu", 12)
	# Native menu rows still have to clear the 44 dp touch floor. Godot builds
	# a row as max(font_height, icon_height) + v_separation; IBM Plex Sans at
	# 12 sp is 17 px, so 28 gives a 45 dp row.
	theme.set_constant("v_separation", "PopupMenu", 28)
	theme.set_constant("item_start_padding", "PopupMenu", 12)
	theme.set_constant("item_end_padding", "PopupMenu", 12)

	# Tooltip.
	theme.set_stylebox("panel", "TooltipPanel", flat_style(SURFACE_2, 0, BORDER))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_font("font", "TooltipLabel", font_regular)
	theme.set_font_size("font_size", "TooltipLabel", 11)

	# Progress, mostly for render operations.
	theme.set_stylebox("background", "ProgressBar", flat_style(SURFACE_2, 0, BORDER_SOFT))
	theme.set_stylebox("fill", "ProgressBar", flat_style(FOCUS, 0, FOCUS))
	theme.set_color("font_color", "ProgressBar", TEXT_MUTED)
	theme.set_font_size("font_size", "ProgressBar", TYPE_CAPTION)

func flat_style(color: Color, radius: int = 0, border: Color = BORDER, border_width: int = 1) -> StyleBoxFlat:
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

func label(text_value: String, size: int = TYPE_BODY, color: Color = TEXT, weight: int = 400) -> Label:
	var l := Label.new()
	l.text = text_value
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", font_for(weight))
	# 11 sp is the readable floor for product UI. Ten sp survives only on the
	# timeline ruler, where the glyphs are ticks rather than prose.
	l.add_theme_font_size_override("font_size", maxi(size, TYPE_CAPTION))
	return l

func section_label(text_value: String) -> Label:
	# Section eyebrows are the one place the UI uses the mono face at label
	# scale. It reads as instrumentation rather than prose and gives the
	# workbench a voice distinct from the previous sans-only pass.
	var l := mono_label(text_value.to_upper(), TYPE_CAPTION, TEXT_DIM)
	return l

func mono_label(text_value: String, size: int = TYPE_MONO, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text_value
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", font_mono)
	l.add_theme_font_size_override("font_size", maxi(size, TYPE_MONO))
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

func icon_button(icon_name: String, tooltip: String = "", size: int = 44, icon_size: int = 20) -> Button:
	var b := Button.new()
	b.icon = icon_texture(icon_name)
	b.expand_icon = false
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Call sites sometimes ask for a visually small glyph. The target still has
	# to be a full 44 dp; only the icon inside it shrinks.
	var target := maxi(size, int(Tokens.HIT))
	b.custom_minimum_size = Vector2(target, target)
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_constant_override("icon_max_width", icon_size)
	b.add_theme_constant_override("h_separation", 0)
	b.add_theme_color_override("icon_normal_color", TEXT_MUTED)
	b.add_theme_color_override("icon_hover_color", TEXT)
	b.add_theme_color_override("icon_pressed_color", FOCUS_BRIGHT)
	b.add_theme_stylebox_override("normal", flat_style(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0))
	b.add_theme_stylebox_override("hover", flat_style(SURFACE_HOVER, 0, Color(0, 0, 0, 0), 0))
	b.add_theme_stylebox_override("pressed", flat_style(SURFACE_3, 0, Color(0, 0, 0, 0), 0))
	b.add_theme_stylebox_override("focus", flat_style(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0))
	return b

func text_button(text_value: String, icon_name: String = "", primary: bool = false, compact: bool = false) -> Button:
	var b := Button.new()
	b.text = text_value
	b.focus_mode = Control.FOCUS_NONE
	if icon_name != "":
		b.icon = icon_texture(icon_name)
		b.add_theme_constant_override("icon_max_width", 15)
	b.custom_minimum_size = Vector2(ACTION_MIN_WIDTH, Tokens.HIT) if primary else Vector2(Tokens.HIT, Tokens.HIT)
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

func set_icon_active(button: Button, active: bool, edge: String = "left") -> void:
	if active:
		button.add_theme_color_override("icon_normal_color", FOCUS_BRIGHT)
		button.add_theme_color_override("icon_hover_color", FOCUS_BRIGHT)
		button.add_theme_color_override("icon_pressed_color", FOCUS_BRIGHT)
		# Active tools read from a filled cell plus a single bright edge. A
		# full outline competed with the field frames in the inspector. The
		# edge follows the rail: left for a column, bottom for a strip.
		button.add_theme_stylebox_override("normal", _active_edge_style(FOCUS_DARK, edge))
		button.add_theme_stylebox_override("hover", _active_edge_style(FOCUS_DARK.lightened(0.04), edge))
		button.add_theme_stylebox_override("pressed", _active_edge_style(FOCUS_DARK.darkened(0.06), edge))
	else:
		button.add_theme_color_override("icon_normal_color", TEXT_MUTED)
		button.add_theme_color_override("icon_hover_color", TEXT)
		button.add_theme_color_override("icon_pressed_color", FOCUS_BRIGHT)
		button.add_theme_stylebox_override("normal", flat_style(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0))
		button.add_theme_stylebox_override("hover", flat_style(SURFACE_HOVER, 0, Color(0, 0, 0, 0), 0))
		button.add_theme_stylebox_override("pressed", flat_style(SURFACE_3, 0, Color(0, 0, 0, 0), 0))

func _active_edge_style(fill: Color, edge: String) -> StyleBoxFlat:
	var style := flat_style(fill, 0, FOCUS_BRIGHT, 0)
	if edge == "bottom":
		style.border_width_bottom = 1
	else:
		style.border_width_left = 1
	return style

func text_toggle(text_value: String, icon_name: String = "", accent: bool = false) -> Button:
	var b := Button.new()
	b.text = text_value
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = Tokens.HIT
	b.add_theme_font_override("font", font_medium)
	b.add_theme_font_size_override("font_size", TYPE_BODY)
	b.add_theme_color_override("font_color", TEXT_MUTED)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", TEXT)
	b.add_theme_color_override("font_hover_pressed_color", TEXT)
	b.add_theme_color_override("icon_normal_color", TEXT_MUTED)
	b.add_theme_color_override("icon_hover_color", TEXT)
	b.add_theme_color_override("icon_pressed_color", TEXT)
	b.add_theme_color_override("icon_hover_pressed_color", TEXT)
	b.add_theme_stylebox_override("normal", style_with_margins(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector4(9, 2, 9, 2)))
	b.add_theme_stylebox_override("hover", style_with_margins(SURFACE_HOVER, 0, Color(0, 0, 0, 0), 0, Vector4(9, 2, 9, 2)))
	b.add_theme_stylebox_override("pressed", style_with_margins(FOCUS_DARK, 0, Color(0, 0, 0, 0), 0, Vector4(9, 2, 9, 2)))
	b.add_theme_stylebox_override("hover_pressed", style_with_margins(FOCUS_DARK.lightened(0.04), 0, Color(0, 0, 0, 0), 0, Vector4(9, 2, 9, 2)))
	b.add_theme_stylebox_override("focus", flat_style(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0))
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

func line_edit(placeholder: String = "", size: int = TYPE_EMPHASIS) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.add_theme_font_override("font", font_regular)
	e.add_theme_font_size_override("font_size", size)
	e.custom_minimum_size.y = Tokens.FIELD
	return e

## A thin graphite scrollbar that belongs to the workbench rather than to the
## platform theme. The theme already carries these styles, but ScrollContainer
## instances are occasionally built before the root theme is inherited; setting
## them on the instance makes the result deterministic.
func style_scroll_container(scroll: ScrollContainer) -> void:
	if scroll == null:
		return
	var v := scroll.get_v_scroll_bar()
	if v != null:
		v.custom_minimum_size = Vector2(6, 0)
		_style_scroll_bar(v)
	var h := scroll.get_h_scroll_bar()
	if h != null:
		h.custom_minimum_size = Vector2(0, 6)
		_style_scroll_bar(h)

func _style_scroll_bar(bar: ScrollBar) -> void:
	bar.add_theme_stylebox_override("scroll", flat_style(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0))
	bar.add_theme_stylebox_override("grabber", flat_style(BORDER, 0, Color(0, 0, 0, 0), 0))
	bar.add_theme_stylebox_override("grabber_highlight", flat_style(TEXT_DIM, 0, Color(0, 0, 0, 0), 0))
	bar.add_theme_stylebox_override("grabber_pressed", flat_style(TEXT_MUTED, 0, Color(0, 0, 0, 0), 0))

## A 1 px separator line. `vertical` swaps the axis.
func hairline(vertical: bool = false) -> ColorRect:
	var c := ColorRect.new()
	c.color = BORDER_SOFT
	c.custom_minimum_size = Vector2(1, 0) if vertical else Vector2(0, 1)
	if vertical:
		c.size_flags_vertical = Control.SIZE_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

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
