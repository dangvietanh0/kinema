extends RefCounted
## Design tokens for the whole application.
##
## One source of truth for colour, spacing, hit targets and type sizes. `Kit`
## re-exports every value, so call sites read `Kit.SURFACE` while the numbers
## live here. Colours are exact: the hex code is the specification.
##
## The workbench is deliberately achromatic. Surfaces are graphite, hairlines
## are grey, and state is carried by luminance rather than hue. Only DANGER
## keeps a red channel, because destructive actions need to be unmistakable.
##
## Two light greys carry meaning and must not be swapped:
##   FOCUS (near-white) - UI selection, active tools, primary actions.
##   TIME  (grey)       - keys, playhead, transport, 3D selection.

# --- Surfaces -------------------------------------------------------------
const BG := Color("080808")
const SURFACE := Color("101010")
const SURFACE_2 := Color("151515")
const SURFACE_3 := Color("1B1B1B")
const SURFACE_HOVER := Color("232323")
const BORDER := Color("3A3A3A")
const BORDER_SOFT := Color("292929")

# --- Text -----------------------------------------------------------------
const TEXT := Color("F0F0F0")
const TEXT_MUTED := Color("A6A6A6")
## Tertiary text must stay above 4.5:1 on SURFACE_3, not only on the darkest
## panel. The old #7C7C7C fell to 4.0:1 on raised surfaces.
const TEXT_DIM := Color("8C8C8C")

# --- Focus (UI) -----------------------------------------------------------
const FOCUS := Color("E6E6E6")
const FOCUS_BRIGHT := Color("FFFFFF")
const FOCUS_DARK := Color("262626")

# --- Time (animation) -----------------------------------------------------
const TIME := Color("C8C8C8")
const TIME_BRIGHT := Color("F2F2F2")
const TIME_DARK := Color("2A2A2A")

# --- Status ---------------------------------------------------------------
## Success and warning are luminance states; danger is the only chromatic
## signal in the chrome.
const WARNING := Color("C8C8C8")
const DANGER := Color("E06C6C")
const SUCCESS := Color("B0B0B0")

# --- Axes -----------------------------------------------------------------
## Desaturated so the viewport reads as a graphite study, while X/Y/Z stay
## distinguishable on touch screens.
const AXIS_X := Color("A66A66")
const AXIS_Y := Color("7F9A78")
const AXIS_Z := Color("6D8099")

# --- Overlays and stage ---------------------------------------------------
const SCRIM := Color(0.0, 0.0, 0.0, 0.68)
const GRID := Color(1, 1, 1, 0.07)
const GRID_MAJOR := Color(1, 1, 1, 0.14)

# --- Spacing (dp) ---------------------------------------------------------
const SPACE_2 := 2.0
const SPACE_4 := 4.0
const SPACE_6 := 6.0
const SPACE_8 := 8.0
const SPACE_12 := 12.0
const SPACE_16 := 16.0
const SPACE_24 := 24.0
const SPACE_32 := 32.0

# --- Hit targets (dp) -----------------------------------------------------
const HIT := 44.0
const FIELD := 44.0
const TOUCH_GAP := 8.0

# --- Type roles (sp) ------------------------------------------------------
## One fixed scale, Material-like roles with a 1.18 step. Product UI needs
## fewer, more stable steps than a marketing page. 11 sp is the readable floor;
## 10 sp is reserved for canvas ruler ticks only.
const TYPE_CAPTION := 11
const TYPE_BODY := 12
const TYPE_EMPHASIS := 13
const TYPE_TITLE := 15
const TYPE_PAGE := 18
const TYPE_MONO := 11
const TYPE_MONO_LARGE := 12
const TYPE_RULER := 10

# --- Chrome heights (dp) --------------------------------------------------
const TOP_BAR_COMPACT := 48.0
const TOP_BAR_STUDIO := 44.0
const TOP_BAR_DESKTOP := 36.0
const STATUS_BAR := 24.0
const RAIL_COMPACT := 48.0
const RAIL_STUDIO := 44.0
const RAIL_DESKTOP := 40.0

# --- Motion ---------------------------------------------------------------
const MOTION_FAST := 0.12
const MOTION_BASE := 0.18
