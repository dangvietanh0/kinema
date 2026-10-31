# Kinema Studio — studio scene, timeline and 3D gizmos

Date: 2026-10-31
Status: approved by the user's direct request
Supersedes, for the points below only:
`2026-10-30-kinema-stage-first-shell-design.md` §1 (dock/rail), §2 (timeline
pushes the viewport) and the 2D gizmo/compass descriptions in the viewport.
The frozen document contract is amended only for the import-hierarchy methods
listed in §5; animation, media and rig APIs are untouched.

## Why

The stage-first shell removed the reserved inspector column, but the scene tree
still lives inside a modal flyout. At 1440×900 the user must open a drawer and
cover the stage to pick an object; at 915×412 the same drawer covers most of
the image. The timeline still pushes the viewport up when it opens, so the
working image changes size exactly when the user starts animating. The
transform gizmo and the orientation compass are drawn as flat screen-space
lines with a fixed arm length: foreshortening is discarded, so they read as
2.5D symbols rather than an object in the scene. Imported glTF/GLB files are a
single black-box row, so a user cannot inspect or hide the parts inside a
model.

This addendum makes the scene tree a first-class, non-modal column, turns the
timeline into a sheet that overlays the stage instead of resizing it, renders
both gizmos as real 3D geometry, and adds an expandable import hierarchy.

## 1. Workbench zones

### Desktop and Studio

```
┌ top bar ─────────────────────────────────────────────────────────────┐
│ tool rail 44 │ scene panel 44–280 │ stage + view header │ panel rail 44 │
│              │ expandable rail    │ timeline overlay    │ Properties/Rig │
│              │                    │ transport 56        │ flyout        │
└ status bar / bottom bar ──────────────────────────────────────────────┘
```

- The **scene panel** is persistent whenever the mode is Studio or Desktop and
  the logical shell is at least **480 dp** wide. It is never a modal drawer on
  those surfaces and never installs a scrim.
- Between 480 and 759 dp the scene panel is a **44 dp rail**: layers icon and
  the object count, with a 44×44 expand action. The stage keeps the width.
- At 760 dp and above the scene panel defaults to its **expanded** width:
  `clamp(shell_width × 0.20, 196, 280)`. At 915 dp that is 196 dp; at 1440 dp
  it is 280 dp. The stage still owns the majority of the canvas.
- The user can collapse the expanded panel with the chevron in the outliner
  header (44×44) and expand it again from the 44 dp rail. The choice persists
  in `editor.scene_panel_expanded`; a width below 760 dp temporarily forces
  the rail without overwriting the stored preference.
- While the scene panel is open the user can orbit, select, drag the gizmo,
  scrub the transport and open the Properties/Rig flyout. There is no scrim
  and no focus trap.
- The right panel rail keeps `Scene`, `Properties`, `Rig`. When the scene
  panel is persistent, the `Scene` rail button toggles the scene panel
  expanded state instead of opening a duplicate scene flyout. `Properties`
  and `Rig` still open the overlay flyout, which stops 44 dp short of the
  rail.
- Compact remains the phone portrait arrangement: bottom action bar, scene,
  properties and rig as modal bottom tabs. No persistent column is forced
  into a canvas that cannot hold it.
- The outliner panel is re-parented between the scene panel and the dock. It
  is one instance, one selection model, one search state.

### Scene panel anatomy

- Header: `SCENE` label, object count, add (44×44), collapse chevron (44×44).
- Search field with 44 dp height and a clear action.
- Tree list: 44 dp rows, 1 px gap, selected row = active fill + 1 px bright
  left edge. Nested import children indent 16 dp per level, capped at 5
  visible levels; deeper nodes keep the cap instead of pushing names off the
  panel.
- Each row keeps its visibility toggle and animation diamond. The name
  truncates with an ellipsis; it never pushes the eye control out of the
  panel.
- The list ends on a whole row; no sliver of the next row under the border.
- Collapsed rail: 44 dp wide, 44 dp expand button at the top, vertical `SCENE`
  label below, and a count badge. The rail is a mount point, not a fake
  header.

## 2. Timeline overlays the stage

- The **folded transport remains exactly 56 dp**, and opening the timeline no
  longer changes the viewport size. The stage and the camera framing stay
  still; the sheet grows upward over the image.
- The transport row sits at the bottom edge of the stage. The expanded sheet
  is a non-modal panel anchored to the same edge, above the transport.
- Expanded height: `min(320, max(180, viewport_height × 0.55))` for dope and
  `min(360, max(200, viewport_height × 0.66))` for graph, always leaving at
  least **96 dp** of visible stage. On a 412 dp landscape stage this is about
  180–210 dp, not the full lower half.
- The clip lane and the media headers belong to the open sheet. On short
  screens they fold first, then the graph hint shrinks, so the sheet never
  covers the whole stage.
- The sheet has a 1 px top border and a soft shadow so it reads as a surface
  above the image, not a hole in the render. It uses the existing square
  corners and graphite surfaces.
- The sheet is not modal: the stage stays interactive where it is visible and
  the sheet stays open until the user folds it. The fold control is in the
  transport/compact header at 44×44.
- Z-order: stage < timeline overlay < panel flyout/scrim < modal sheets. The
  navigation gizmo sits above the stage and below the timeline.
- Render mode hides the timeline exactly as it hides the rest of the chrome.

## 3. Transform gizmo — real 3D

The current gizmo projects three world axes and then replaces each projected
vector with a fixed 48 dp arm. A camera looking down an axis still gets a full
length line, so the view has no depth cue. Replace the drawing, not the drag
math.

- The gizmo is a `Node3D` parented to the stage SubViewport. It is built from
  real meshes: move = cylinder shafts + cone tips, rotate = torus rings,
  scale = cylinder shafts + cube tips, plus a small centre sphere/cube.
- Each axis uses the established axis colours (`Kit.AXIS_X/Y/Z`), unshaded
  materials, no depth test so the stage cannot hide the handle, and a
  per-frame `render_priority` based on camera-space depth so the nearer axis
  draws over the farther one. The result has true foreshortening, occlusion
  between the gizmo's own parts and shaded 3D forms.
- The gizmo keeps a constant screen size: its world scale is derived from the
  camera distance and `gizmo_scale`, so it is usable on a phone and a desktop.
- Handle hit-testing still uses projected positions with a 22 px radius
  (44 dp target) and returns the same `x`, `y`, `z`, `free` axis names. The
  existing drag accumulation, snapping, undo begin/end and HUD readout stay
  unchanged.
- In rotate mode the torus rings are the surfaces; the hit test samples each
  projected ring so a tap on the visible ring selects that axis.
- The gizmo is hidden in render mode, when no object is selected, and for the
  Select tool.

## 4. Navigation gizmo — real 3D

- Replace `_draw_compass()` with a 96×96 `NavGizmo` control in the bottom-right
  of the stage (12 dp inset). It contains a transparent SubViewport with an
  orthographic camera and three real 3D axis arrows, mirrored from the editor
  camera's yaw/pitch every frame.
- X/Y/Z labels are drawn in a 2D overlay at the projected tips. They are not
  billboard text meshes, so they stay crisp at every density.
- Negative axis ends get a smaller muted tip; positive ends are the labelled
  control. Tapping X/Y/Z sets Right/Top/Front view through the existing
  `view_requested` path. A tap outside the tips does nothing.
- The gizmo is mouse-transparent except for its three 44 dp tips; it never
  steals an orbit gesture that starts on the stage.
- Hidden in render mode and when the view is covered by a modal.

## 5. Import hierarchy (Expand Hierarchy)

An imported glTF/GLB is no longer an opaque row. The outliner shows the node
tree inside the file:

- The import row gets a 44×44 disclosure control. Expanding it lists the
  generated scene's `Node3D` descendants (mesh, skeleton, light, camera,
  empty) with type icons, indentation and their own disclosure controls.
- The tree is derived from the loaded model at runtime, not copied into the
  document as duplicate objects. The document stores only UI state: part
  visibility overrides and the selected part path.
- Selecting a part selects the import root (so the inspector still edits the
  root transform) and highlights that part's world AABB in the stage. The
  selected part row is visibly distinct from the root row.
- The eye control toggles a part's `Node3D.visible`. The override is stored in
  the import object's `part_visibility` dictionary and reapplied on load and
  undo. A hidden part row is dimmed.
- Search matches both root names and part names; matching parts keep their
  ancestors visible so the path stays readable.
- Expansion state is UI-only and is not saved as document data. Reopening a
  project shows roots collapsed.
- **Scope:** this wave supports browse, select/highlight, visibility and
  search. Part-level transform animation, keyframes and skinning edits remain
  on the root; the UI must not pretend a child row can be keyed.
- Scoped `document.gd` additions (contract amendment): `import_parts()`,
  `set_import_part_visible()`, `get_import_part_node()`,
  `get_import_part_aabb()`, `set_selected_part()`/`clear_selected_part()` and
  the matching signal. No edit to animation, media, rig, undo or serialise
  behaviour beyond carrying the `part_visibility` dictionary.

## 6. Interaction and visual rules

- 44 dp targets everywhere; 96×44 for primary actions; square corners; IBM
  Plex; achromatic chrome with red reserved for destructive/error.
- The scene panel and the timeline are work surfaces, not cards: hairline
  separators, one active fill, no decorative gradients or shadows except the
  timeline lift.
- A live stage is always visible: at 915×412 Studio the stage is at least
  560×230 with the scene panel expanded and the transport folded.
- No fake affordance. A disabled or unavailable part action explains itself or
  is absent.

## 7. Verification

- Layout matrix: scene panel visible/rail/expanded per size and mode; no scrim
  while it is open; stage remains at least 560×230 at 915×412 Studio; timeline
  open/fold leaves `view.size` unchanged; expanded sheet height within budget
  and at least 96 dp stage visible; no horizontal overflow; every visible
  action ≥43.5 dp.
- Smoke: scene panel collapse persists; right rail Scene focuses the panel;
  outliner re-parents without losing selection; timeline overlay anchors to
  the stage bottom; import hierarchy expands/collapses, searches, selects and
  toggles visibility; reload keeps visibility overrides; render mode hides
  the timeline, both gizmos and the scene stage overlays.
- Gizmo suite: 3D node exists with real MeshInstance3D children per axis and
  tool mode; screen handles project; hit radius; constant screen size; axis
  draw order changes with camera; render mode hides; nav gizmo taps set the
  three canonical views; no 2D `_draw_compass` remains.
- Captures at 1440×900 Desktop, 915×412 Studio landscape and 412×915 Compact,
  with the scene panel expanded/collapsed, timeline folded/open, gizmo and nav
  gizmo visible, and a GLB hierarchy expanded.
- Full gates on the merged head: parse, smoke, layout headless + xvfb,
  animation, media, rig, plus the new gizmo suite.

## 8. Non-goals

- No docked inspector column, no second Properties instance, no multi-select.
- No part-level transform/keyframe editing in this wave.
- No change to MP4/video export, skinning, IK, audio or camera export.
- No fake hierarchy for unsupported formats (OBJ stays a single mesh row).
