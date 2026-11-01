extends RefCounted
## Design tokens for the whole application.
##
## One source of truth for colour, spacing, hit targets and type sizes. `Kit`
## re-exports every value, so call sites read `Kit.SURFACE` while the numbers
## live here. Colours are exact: the hex code is the specification.
##
## Black chrome (user override, 2026-11-01): the window and the stage are pure
## black. Hierarchy comes from a near-black elevation ladder, not from grey
## fills, and panels do not draw outlines by default. State and separation stay
## luminance rather than hue. Only DANGER keeps a red channel, because
## destructive actions need to be unmistakable.
##
## The elevation ladder, each step a few luminance points above the last so the
## raise still reads on the phone screen while the stage stays black:
##   BG             #000000  window clear colour, stage and gutter gaps.
##   SURFACE        #060606  panel bodies (dock, sheets, centre columns).
##   SURFACE_2      #0C0C0C  raised fills: fields, bars, cards, the stage HUD.
##   SURFACE_3      #121212  highest panel fill: raised inputs, chips.
##   SURFACE_HOVER  #1E1E1E  hover state on any surface.
##   SURFACE_ACTIVE #333333  active/pressed fill, the brightest chrome fill.
##
## Two light greys carry meaning and must not be swapped:
##   FOCUS (near-white) - UI selection, active tools, primary actions.
##   TIME  (grey)       - keys, playhead, transport, 3D selection.
##
## Hairlines split into two jobs. BORDER_SOFT separates dense rows and stays
## quiet; CONTROL_BORDER delimits a control and clears 3:1 against the fills it
## sits on, so a field edge is readable without re-outlining every panel.

# --- Surfaces -------------------------------------------------------------
const BG := Color("000000")
const SURFACE := Color("060606")
const SURFACE_2 := Color("0C0C0C")
const SURFACE_3 := Color("121212")
const SURFACE_HOVER := Color("1E1E1E")
const SURFACE_ACTIVE := Color("333333")
## A separator/divider hairline. Deliberately quiet: dividers do not delimit a
## control, so they are exempt from the 3:1 non-text floor.
const BORDER_SOFT := Color("242424")
## A control boundary hairline (field edges, selectable cards). It must clear
## 3:1 against every fill a control sits on: 3.41:1 on SURFACE_2 and 3.26:1 on
## SURFACE_3. Do not use it for separators; that would turn the chrome back
## into a wireframe.
const CONTROL_BORDER := Color("666666")
const BORDER := Color("3C3C3C")

# --- Text -----------------------------------------------------------------
const TEXT := Color("EBEBEB")
const TEXT_MUTED := Color("A6A6A6")
## Tertiary text must stay above 4.5:1 on SURFACE_3, not only on the darkest
## panel. The old #7C7C7C fell to 4.0:1 on raised surfaces.
const TEXT_DIM := Color("858585")

# --- Focus (UI) -----------------------------------------------------------
const FOCUS := Color("EDEDED")
const FOCUS_BRIGHT := Color("FFFFFF")
const FOCUS_DARK := Color("262626")

# --- Time (animation) -----------------------------------------------------
const TIME := Color("B8B8B8")
const TIME_BRIGHT := Color("F2F2F2")
const TIME_DARK := Color("2A2A2A")

# --- Status ---------------------------------------------------------------
## Success and warning are luminance states; danger is the only chromatic
## signal in the chrome.
const WARNING := Color("C8C8C8")
const DANGER := Color("E5706B")
const SUCCESS := Color("B0B0B0")

# --- Axes -----------------------------------------------------------------
## Desaturated so the viewport reads as a graphite study, while X/Y/Z stay
## distinguishable on touch screens.
const AXIS_X := Color("C1675F")
const AXIS_Y := Color("86A87B")
const AXIS_Z := Color("6F90B8")

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

# --- Radii (px) -----------------------------------------------------------
const R_PANEL := 0
const R_CONTROL := 2
const R_FLOAT := 4
const GUTTER := 1

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
## One shared panel-rail width: the rail element, the flyout inset and the
## timeline reserve all read this so a width change cannot desync the shell.
const PANEL_RAIL_WIDTH := 44.0

# --- Motion ---------------------------------------------------------------
const MOTION_FAST := 0.10
const MOTION_BASE := 0.16
