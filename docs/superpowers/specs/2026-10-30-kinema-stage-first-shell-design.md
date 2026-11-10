# Kinema Studio — stage-first workbench addendum

Date: 2026-10-30
Status: approved by the user's direct request ("chỉnh lại giao diện phần studio
… không gian 3D bé tí … thêm scale UI tự do thay vì giới hạn")
Supersedes, for the points below only:
`2026-10-23-kinema-professional-rebuild-design.md` §6.3, §6.4 and §6.6.

## Why

The workbench kept a 280–340 dp dock and a 180–220 dp timeline permanently
docked. At 915×412 the 3D viewport was about 630×250; at 1440×900 it was about
800 px wide beside a 320 px dock. The stage — the reason the editor exists — was
the smallest surface on screen. The UI-scale control also stopped at 130% and
was disabled whenever Desktop fit was active, so the user could not choose the
density that suited their eyes or device.

## What changes

### 1. Stage first

- The right dock is **always an overlay flyout**, never a reserved column.
  `_dock_slot` and its reserved width are removed.
- A **44 dp panel rail** sits on the right edge in Studio and Desktop:
  `Scene`, `Properties`, `Rig`, each 44×44 with an accessible name and an
  active edge. Tapping a rail button opens that page in the flyout; tapping the
  same button again closes it.
- The flyout is one page at a time, max 400 dp wide, with a 44 dp header
  (page title + close). It starts below the top bar and ends above the bottom
  chrome. A scrim closes it on an outside tap; Back also closes it.
- Compact stays on the bottom action bar (no second rail). Its drawer keeps the
  three tabs because it has no rail.
- Below the Studio minimum canvas (480 dp wide, e.g. a 412 dp phone that has
  not been clamped yet), the rail folds into the top-bar panel button. It opens
  the same flyout, so the stage never pays for two rails it cannot afford.
- The left tool rail, viewport header, status bar and transport keep their
  current roles.

### 2. Timeline folded by default in every mode

- The folded stage is the **56 dp transport row** and nothing else. The clip
  lane and the media headers belong to the open sheet: keeping a 114 dp
  sequence canvas under a folded dope sheet was what left the landscape
  viewport 107 dp tall.
- The dope sheet starts folded in Compact, Studio and Desktop. It opens only
  when the user asks (transport fold control or bottom-bar Timeline action).
  Opening it reveals the clip lane, the sheet and the media headers together.
- Opening the timeline still pushes the viewport rather than covering it; the
  viewport keeps its 96 dp floor on short screens. When the height budget
  cannot hold every lane, the media header folds first, then the clip lane.
- Mode switches reset to the folded default; a manual choice survives rotation
  until the next mode switch, as before.

### 3. Free interface scale

- `display.user_scale` is a continuous **50%–200%** value, step 1%, default
  100%. Both the Workspace sheet and Settings → Display use the same slider
  with a live percentage label.
- The scale control is **never disabled** by Desktop fit. The old rule that
  fit locks the control is removed because it made the control look broken.
- Desktop fit keeps its job (avoid an unusably large canvas at 100%), but it is
  computed from the density only, not from the user scale. User scale then
  multiplies on top, so the slider has a real effect in every mode.
- Compact and Studio still clamp the effective factor to their minimum logical
  canvas (320×480 / 480×320) so the shell cannot overflow. When that happens
  the sheet says “Limited to fit this screen”; the stored preference is not
  rewritten.
- Below 85%, the sheet warns that 44 dp controls render smaller than the touch
  floor. The app does not silently pretend the target grew.
- The user's choice is persisted and applied to Home and the editor.

## User override — black chrome (2026-11-01, binding)

The user device-tested the stage-first shell on Android and rejected the grey
chrome:

- The app background is **pure black** (`project.godot` default clear color and
  the `BG` token). Root, stage gaps, bars and panel bases all read black; the
  stage is not a grey/graphite sheet. Hierarchy comes from near-black
  elevation steps a few luminance points apart (the ladder documented in
  `studio/src/ui/tokens.gd`), never from grey fills.
- **Remove most outlines.** Panel containers, rails, bars, cards and the
  flyout do not draw a 1 px border by default. Thin separators remain only
  where dense rows and fields need them; focus rings and the single
  destructive red keep their marks. A surface never says the same thing three
  ways (border + fill + shadow).
- The UI must not become an unreadable black slab: normal text keeps
  >= 4.5:1 contrast and control boundaries >= 3:1. Verified on captured
  pixels, not just on tokens.

Non-goals are unchanged: no new visual primitives, no hue in the chrome, no
gradients; Delete remains the only red action.

## Non-goals

- No new panel content, no new modes, no change to document/animation/media/rig
  contracts.
- No weight-paint brush, no real-time MP4 playback, no fake features.
- The 44 dp touch floor remains the design target at 100%; free scaling is an
  explicit user override, not permission to shrink the default.

## Verification

- Layout matrix: at 915×412 Studio, 1280×800 Studio and 1440×900 Desktop the
  viewport gains the dock's former width, the rail is 44 dp, and no horizontal
  overflow appears. Below the 480 dp Studio canvas the rail yields to the
  top-bar panel button.
- Timeline folded by default at 412×915 Studio, 915×412 Studio and 1440×900
  Desktop; folded means a 56 dp transport with no clip lane or media header.
- Opening the sheet at each of those sizes reveals the clip lane, dope sheet
  and media headers without horizontal overflow.
- LayoutMath accepts 0.5 and 2.0, reports `user_scale_enabled = true` under
  Desktop fit, and gives the user scale a real effect on `factor`.
- Smoke: rail opens/closes each page; settings/workspace sliders expose
  50–200, persist a 120/150% value, and are not disabled after
  `apply_fit_info(43, false, false)`.
- Full local gates: parse, smoke, layout headless + xvfb, animation, media, rig.
