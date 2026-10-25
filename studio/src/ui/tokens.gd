extends RefCounted
## Design tokens for the whole application.
##
## One source of truth for colour, spacing, hit targets and type sizes. `Kit`
## re-exports every value, so call sites read `Kit.SURFACE` while the numbers
## live here. Colours are exact: the hex code is the specification.
##
## Two colours carry meaning and must not be swapped:
##   FOCUS  (blue)  - UI selection, active tools, primary actions.
##   TIME   (amber) - keys, playhead, transport, 3D selection.

# --- Surfaces -------------------------------------------------------------
const BG := Color("0B0F14")
const SURFACE := Color("11161D")
const SURFACE_2 := Color("151B23")
const SURFACE_3 := Color("1B232D")
const SURFACE_HOVER := Color("202A36")
const BORDER := Color("26303C")
const BORDER_SOFT := Color("1A222C")

# --- Text -----------------------------------------------------------------
const TEXT := Color("E8ECF2")
const TEXT_MUTED := Color("8C97A8")
const TEXT_DIM := Color("5F6B7C")

# --- Focus (UI) -----------------------------------------------------------
const FOCUS := Color("4C8DE6")
const FOCUS_BRIGHT := Color("6BA6F2")
const FOCUS_DARK := Color("14243A")

# --- Time (animation) -----------------------------------------------------
const TIME := Color("D9A565")
const TIME_BRIGHT := Color("EDBE7F")
const TIME_DARK := Color("3A2C18")

# --- Status ---------------------------------------------------------------
const WARNING := Color("D98E5F")
const DANGER := Color("D76C6C")
const SUCCESS := Color("6FB68A")

# --- Axes -----------------------------------------------------------------
const AXIS_X := Color("D96962")
const AXIS_Y := Color("7FB069")
const AXIS_Z := Color("5B8FD9")

# --- Overlays and stage ---------------------------------------------------
const SCRIM := Color(0.008, 0.020, 0.031, 0.62)
const GRID := Color(1, 1, 1, 0.08)
const GRID_MAJOR := Color(1, 1, 1, 0.16)

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
const PRIMARY_HIT := 48.0

# --- Type sizes (sp) ------------------------------------------------------
const TYPE_10 := 10
const TYPE_11 := 11
const TYPE_12 := 12
const TYPE_13 := 13
const TYPE_18 := 18
const TYPE_22 := 22

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
