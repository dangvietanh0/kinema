# Device defect wave 2 — renderer, timeline, rig, hierarchy, MP4

Date: 2026-11-02
Base: `feat/professional-rebuild` @ `fe9ad71`
Supersedes: `2026-11-01-renderer-safety-design.md` §2 and the "Forward+ is
desktop-only" ruling. Adds the timeline, rig and hierarchy addenda to
`2026-10-31-kinema-studio-scene-design.md`.

## 1. User reports (verbatim)

1. "mất tùy chọn renderer forward plus (rất cần, và ý tôi không phải xoá nó mà
   sửa các lỗi gây crash và tối ưu lại hiệu năng)"
2. "dopesheet chỉ có đúng 7.5s trong khi animation có thể dài hơn và chưa thấy
   cách cuộn timeline"
3. "timeline vẫn đang chiếm màn hình khá nhiều"
4. "rigging chưa trực quan (cần dạng rigging giống blender)"
5. "chưa thấy Expand Hierarchy cho các file như glb, gltf, etc... (hoặc chưa
   tìm thấy nó)"
6. "chưa có mp4 export chất lượng cao (cái khá quan trọng cho export)"

No APK containing the U2 hierarchy work has ever been built: the last CI run
predates `fe9ad71`. The code must still make the affordance unmissable on a
fresh build, and the handoff must say that a new APK is required before the
user can re-test it.

## 2. Rulings

- **Forward+ stays selectable on Android.** It is labelled Experimental, runs
  a mobile-safe profile with high-end effects clamped, and falls back to the
  platform default after one failed boot. Removing it again is forbidden.
- **Timeline default is compact.** The open sheet defaults to at most 34% of
  the stage host and 208 dp, never below 104 dp. Folded 56 dp is unchanged.
  An explicit **More** control may raise it to 46% / 260 dp; that expanded
  state is session-only and never the default. Scrolling and duration must be
  visible, not hidden gestures.
- **Rigging is a touch-adapted Blender subset**: octahedral bones, explicit
  Edit/Pose modes, viewport head/tail manipulation, add/extrude from the
  viewport, and a floating rig toolbar that survives closing the dock.
- **Hierarchy is discoverable without hidden gestures.** New glTF/GLB imports
  auto-expand one level, the disclosure carries a part-count badge and an
  explicit "Expand hierarchy" tooltip, and the import toast names the part
  count. Project load still starts collapsed, preserving the U2 contract.
- **MP4 gets real quality controls**: Standard/High/Master presets, 4K UHD,
  up to 80 Mbps, H.264 High profile with VBR, 4× MSAA for High/Master, and
  capability gating with an honest reason when the device cannot serve 4K.
  Device verification remains outstanding.

## 3. Global constraints

- Touch-first Android 15–17, landscape priority. Every visible target is at
  least 44 dp; primary actions are 96×44; corners are square; IBM Plex only;
  achromatic chrome; pure-black background; red only for destructive/error.
- No fake feature: an unavailable control is disabled with the exact reason.
  A device-only path is never reported as verified from a Linux headless run.
- No public document-contract change beyond the named workstream needs.
- Worktrees are isolated and branch from this document's commit. No push.
  Builds and device checks remain the user's CI/device step.
- Tests are written first and must be watched failing. Full gates after every
  workstream: parse 0 errors; smoke, layout (headless + xvfb), animation,
  media, rig, hierarchy, gizmo all PASS/0 FAIL.

## 4. W1 — Android Forward+

`gfx.gd`:
- `supported_renderers("Android")` and `("iOS")` include `forward_plus`,
  `mobile`, `gl_compatibility`. Desktop is unchanged.
- `renderer_entries` marks Forward+ `experimental = true` on Android/iOS and
  returns a non-empty `note`: "Experimental on Android: high-end Forward+
  effects are clamped for stability." The label becomes
  "Forward+ (Experimental)" in that case.
- `renderer_unavailable_reason("forward_plus", "Android") == ""`.
- `build_restart_args("forward_plus", "Android")` returns the real Vulkan
  args. `sanitize_renderer_state` no longer rewrites a Forward+ preference
  on Android.
- `capabilities_for(method, platform)` gains a platform argument
  (default `OS.get_name()`). For Forward+ on Android/iOS it returns
  `ssil=false`, `ssr=false`, `taa=false`, `volumetric_fog=false`,
  `ssao=true`, `mobile_safe=true`, `msaa_cap=1` (2×), `scale_3d_cap=0.85`,
  `shadow_quality_cap=2`, `max_fps_cap=60`. Desktop Forward+ is unchanged.
- `safe_forward_plus_profile(platform, actual_method)` returns the clamped
  values for the running backend. On Android + Forward+ it forces
  `taa/ssil/ssr/volumetric_fog=false`, `msaa<=1`, `scale_3d<=0.85`,
  `shadow_quality<=2`, `shadow_distance<=40`, `shadow_splits<=2`,
  `max_fps<=60`. `apply_globals`/`apply_viewport`/`apply_environment` use it.
- Crash fallback: persist `renderer_ready` after the first rendered frame.
  A pending renderer that never reached ready counts as a failed attempt on
  the next launch. On Android Forward+, one failed attempt falls back to the
  platform default with a readable `last_renderer_error`. A clean launch then
  marks ready and clears the count. No restart loop.
- `main.gd` calls `Gfx.mark_renderer_ready()` after the editor is on screen.
- Settings/renderer sheet show the Experimental note and the mobile-safe
  reason for any disabled high-end toggle. The old "requires the desktop
  Vulkan feature set" copy is removed.

## 5. W2 — Timeline duration, scroll affordance, footprint

`timeline.gd` + `editor.gd`:
- Duration chip in the sheet header: active clip length always; when
  `doc.sequence_duration() > doc.duration + 0.05`, it also shows
  `Seq <n> s`. Tapping it opens a 44 dp row with a numeric duration field
  (0.25–3600 s), **Match sequence** (only when the sequence is longer) and
  **Extend +1 s**. Extending never deletes keys; shrinking keeps the existing
  key-deletion contract and asks for confirmation first.
- The time viewport gets a permanent affordance: the scrollbar track is
  painted even when the whole duration fits, with a full-width thumb at 40%
  opacity and a caption `Fit · pinch to zoom`. When zoomed, the normal thumb
  and `Drag to pan` caption appear. A one-time hint in the sheet header names
  both gestures. `scrollbar_track_rect()` must return a non-empty rect when
  fit (new contract), while `scrollbar_owns_press()` stays false when there
  is nothing to pan.
- The default open budget is `min(208, max(104, stage_height * 0.34))`;
  folded stays 56. `More` toggles a session-only full state capped at
  `min(260, stage_height * 0.46)`, and resets to compact on close/reopen.
  At 915×412 the compact open height must be <=112 dp.
- The compact pass must still expose the transport, ruler, playhead and at
  least one key lane. The clip lane and media header may fold in compact;
  `More` must reveal them. No content may become unreachable at 915×412.
- Keep clip/sequence clocks distinct. Never pretend the dope sheet covers a
  sequence it does not show.

## 6. W3 — Blender-like rig viewport

`rig_overlay.gd`, `rig_panel.gd`, `editor.gd`, minor `rig_system.gd` helpers,
`tests/rig.gd`:
- Bones draw as octahedral solids (filled 4-point polygon: head, 20%-width
  shoulders, tail) with a 1 px outline. Active bone uses `FOCUS_BRIGHT`,
  others `TEXT_MUTED`; joints are 4 dp / active 6 dp.
- Explicit `pose` / `edit` mode. A floating `RigToolbar` in the stage shows a
  44 dp segmented Pose/Edit control, **Add bone** (96×44), and **Done**.
  It is visible whenever a rig is selected and stays visible when the Rig dock
  is closed. `Done` exits rig mode and hides the overlay.
- Pose mode keeps the existing drag-rotate behavior, with 22 dp hit radius.
- Edit mode draws 22 dp head and tail handles. Drag head translates the rest
  bone in the parent's local space; drag tail aims the rest bone at the
  pointer and sets its length. Both go through `set_bone_rest` (undoable).
- **Add bone**: with an active bone, adds a child at the active tail
  (extrude); with no active bone, adds a root bone. New bone gets a unique
  `Bone N` name, becomes active, and is selected in the tree.
- Imported skeletons keep rest editing locked; the toolbar's Edit control is
  disabled with the existing imported-skeleton reason. Pose/IK remain usable.
- The Rig panel mirrors the mode and shows a one-line touch hint. Closing the
  dock does not reset the mode or the active bone.
- Preserve every existing rig behavior (bind, skinning, IK, poses, keys).
  The rig suite must stay green and gain the new viewport/mode assertions.

## 7. W4 — Imported hierarchy discoverability

`outliner.gd`, `editor.gd`, `tests/hierarchy.gd`, `tests/smoke.gd`:
- When an import root with parts is added after the outliner is mounted, the
  outliner auto-expands **one level** (`_expanded[id]=true`). Project load
  still starts collapsed. Manual collapse is respected afterwards.
- The root disclosure becomes a 44×44 button with a `list.svg` icon when
  collapsed and `chevron-down` when expanded; tooltip is exactly
  `Expand hierarchy · N nodes` / `Collapse hierarchy · N nodes`.
- A `part-count` badge shows `N` next to the import name (10 px, `TEXT_DIM`,
  `role="part-count"`), so the user can see a hierarchy exists even when
  collapsed. It must fit at 196 dp; the name truncates first.
- Import success toast becomes `Imported <name> · N hierarchy nodes`, or
  `Imported <name> · single mesh` for OBJ/zero-part imports.
- Search-forced expansion and OBJ flatness are unchanged. Selecting a root
  does not override a user collapse.
- Add tests for: auto-expand on new import, no auto-expand on load, count
  badge value, tooltip text, 44 dp target, 196 dp no-overflow, collapse
  persistence, and the toast count.

## 8. W5 — High-quality MP4

`media_export_sheet.gd`, `editor.gd`, `android_video.gd`, Java encoder,
`tests/media.gd`:
- Quality presets (MP4 only): Standard = 1080p30 / 16 Mbps / 2× MSAA;
  High = 1440p60 / 40 Mbps / 4× MSAA; Master = 4K60 / 80 Mbps / 4× MSAA.
  Changing resolution, fps or bitrate switches the preset to `Custom`.
- Resolution list adds `3840 × 2160`; bitrate list adds 30/40/60/80 Mbps.
  FPS stays 12/24/30/60.
- `build_options()` carries `quality`, `msaa` and `audio_bitrate`
  (192 kbps Standard/Custom, 256 kbps High/Master). `editor._export_mp4`
  passes `msaa` to `SequenceRenderer` and the audio bitrate to the manifest.
- Launcher capability gating: `AndroidVideo.capabilities()` returns
  `supports_4k`, `supports_1440p`, `supports_high_profile` and
  `supports_vbr`. The sheet disables 4K with the exact reason when
  `supports_4k` is false; Master falls back to High and says so. On
  non-Android MP4 stays disabled with the existing reason.
- Java encoder: choose an H.264 profile/level the codec advertises (prefer
  High), set `KEY_PROFILE`/`KEY_LEVEL` only when supported, set VBR when
  advertised, keep I-frame interval 1 s, and use the manifest audio bitrate.
  If the codec rejects the profile/level at configure time, retry once
  without them rather than failing the export.
- Estimate in the sheet: `~<n> MB/min` from bitrate; label it as video-only.
- Device honesty: media tests prove the UI/manifest/pure gating only. The
  report must state that encoder profile, 4K support and output quality are
  device-unverified until a new APK runs on hardware.

## 9. Verification and handoff

Per workstream: RED evidence, GREEN evidence, parse 0, smoke, layout headless
+ xvfb, animation, media, rig, hierarchy, gizmo. Captures where the change is
visual (timeline 915×412, rig toolbar/octahedra, hierarchy expanded, MP4
sheet). Commit locally; no push; no subagents.

Handoff must list: commits, suite counts, capture paths, residual risks, and
the exact CI/device checks still needed (Forward+ boot/fallback, 4K encode,
MP4 quality, hierarchy chevron on device, timeline pan).

## 10. Final whole-branch review findings folded into this wave

The whole-branch review of `bee2d48..fe9ad71` found no critical issues, two
important defects and six minor findings. They are assigned to the workstream
that already owns the code, so this wave does not need a separate fix round.

- **I1 (timeline touch state)** → W2, mandatory. A two-finger pan/pinch that
  starts with one finger on the ruler or a key must not seek, pause, retime a
  key or leave an edit open. Snapshot time/playback/pending edit on touch
  down; a second touch restores the time, resumes playback and cancels the
  pending edit. Tests must assert time, playback and edit state, including a
  gesture that starts on a key row.
- **I2 (project renderer label)** → W1, mandatory. Both renderer surfaces must
  use the mobile feature override, not the base project setting, and must show
  the effective backend. Add a test that the `mobile` feature set resolves to
  `mobile`.
- **M1 (blocked switch clobbers preference)** → W1. A blocked switch leaves
  the stored preference untouched; test the exact prior value.
- **M2 (first-run sanitize reason, dead error)** → W1. An empty preference is
  unset, not unsupported: map it to the platform default with no error. Show
  `last_renderer_error` in the renderer sheet/settings after a fallback instead
  of leaving it unread.
- **M3 (horizontal wheel misroute)** → W2. Wheel-left/right pans the time
  window instead of starting a scrub. Add a regression test.
- **M4 (budget tests echo the formula)** → W2. Replace live recomputation
  with literal breakpoint assertions at independent stage heights and document
  floor precedence.
- **M5 (196 dp part-name truncation)** → W4. Part names get a tooltip with the
  full name and the 196 dp width is tested for no overflow.
- **M6 (nav bottom tip occluded)** → W2. The nav gizmo sits above the 56 dp
  folded transport strip so all three tips remain tappable; add a hit test.
- U2-1, R1, R3, R4 and the older ledger minors stay deferred: none has a
  production caller or blocks this wave.
- Physical device checks remain unverified and must be listed in the handoff:
  Forward+ boot/fallback, 4K profile/VBR encode, MP4 quality, hierarchy
  chevron, timeline pan two-finger state, nav tips.

## 11. Sky, sunlight and object legibility (2 Nov follow-up)

The user reported three more defects after the five workstreams were
specified. They are binding for this wave and are assigned to two new
contracts, W6 and W7. The word-for-word Vietnamese reports are not recorded;
the entries below are the maintained translations.

7. "missing skybox or environment light — the scene background reads as
   flat black."
8. "shadows are too dark; no sunlight is visible."
9. "camera and light objects still read as 2D/2.5D; their view direction and
   light direction are not visible."

### 11.1 Ruling W6 — procedural studio sky with a real sun

- Ship a procedural studio sky. Do not add HDRI import in this wave; the
  user accepted "hdri hoặc khác", and a procedural sky that visibly reads as
  an environment satisfies the report.
- The sky is driven by Godot's real sky built-ins: `LIGHT0_ENABLED`,
  `LIGHT0_DIRECTION`, `LIGHT0_COLOR`, `LIGHT0_ENERGY`, `LIGHT0_SIZE`. No
  hand-authored fake sun direction and no second source of truth.
- Exactly one visible `DirectionalLight3D` is the sky sun
  (`sky_mode = SKY_MODE_LIGHT_AND_SKY`); every other directional light uses
  `SKY_MODE_LIGHT_ONLY`. When no visible directional light exists the sky
  built-ins disable themselves and the disc disappears.
- `studio_sky.gdshader` must show a sun disc plus a wide halo. Angular
  radius is `max(LIGHT0_SIZE, 0.030)` rad so the disc stays legible even
  when the light's shadow-softening angle is small. The disc colour is
  `LIGHT0_COLOR`; brightness scales with `LIGHT0_ENERGY`.
- Lift the environment so ambient light and the horizon are visibly present:
  `ambient_light_energy >= 1.35`, lifted sky zenith/horizon/ground values,
  and `shadow_opacity <= 0.65` on every shadow-casting light.
- Reduce contact-shadow darkening: SSAO intensity `<= 1.5`,
  `ssao_light_affect <= 0.10`. Keep SSAO on; this is a correction, not a
  removal.
- The blank template gets a real, selectable `Fill Light` omni at
  `(2.6, 2.2, 3.0)`, energy `0.35`, range `7.0`, shadows off. Add a
  `light_shadow` object property (default `true`) so the fill is honest in
  the document and the inspector can show it.
- Tests: new `tests/environment.tscn` + `environment.gd`. Assert the shader
  contains the five `LIGHT0_*` built-ins and a halo term; assert ambient
  energy, SSAO intensity, and shadow opacity thresholds; assert exactly one
  sky-mode sun and that the blank template has the fill light with shadows
  off; render a sky capture under xvfb and assert the sun core is brighter
  than its halo and the halo is brighter than the surrounding sky, and that
  the sky is not near-black.

### 11.2 Ruling W7 — camera/light bodies, direction, look-through

- Stop hiding the document's 3D markers (`doc.markers_hidden = false` in
  the editing view). Flat screen-space icons may remain only as a name tag
  for an off-screen or occluded object; they are not the object's body.
- Camera body: a solid, shaded 3D body (body block + lens barrel + lens
  ring) oriented so local `-Z` is the view direction. Attached to the
  camera node, not the editor camera; `cast_shadow = OFF`. The body uses
  the same neutral material family as the rest of the stage.
- Camera frustum: four rays from the lens to the far-plane corners plus the
  far-plane rectangle, computed from the document camera's real
  `camera_fov` and the stage aspect. Draw them as a 2 px projected overlay
  with a 1 px dark underlay so they survive on light and dark pixels. They
  must update when FOV changes, when the camera moves, and when the stage
  resizes; they must not be a fixed decorative triangle.
- Directional light: a solid 3D body plus an arrow along the light's real
  direction (`-basis.z`) to the ground hit point, an arrowhead, and a ground
  ring at the hit. The arrow length is clamped to the visible stage; when
  the light points up, draw the arrow to the stage ceiling or hide the
  ground ring instead of faking a hit.
- Omni light: a solid 3D bulb body plus a projected ground footprint circle
  whose radius is the real `light_range` at the ground plane, with two
  inner rings. The footprint is the direction/range cue; an omni gets no
  directional arrow.
- Empty: a 3D axis triad at the object origin, not a flat dashed icon.
- Picking: tapping the camera frustum, the light arrow, or the omni
  footprint selects that object. The existing 22 px origin target stays.
- Look-through: the inspector's camera section replaces the "layout
  reference only" hint with a real **Look through** primary action
  (96×44). It enters a real look-through mode: the editor camera copies the
  document camera's global transform and FOV; the grid, markers, selection,
  gizmo, nav gizmo and editor HUD hide; playback and timeline stay live;
  orbit/pan/gizmo gestures are ignored. A persistent **Exit camera**
  96×44 control sits at the stage's top-left, 12 dp inset, above the
  transport and clear of the scene tree; Android back exits look-through
  before any other navigation. Exit restores the saved editor transform,
  FOV, grid and marker state. The document camera node itself stays
  inactive; only the editor camera moves.
- Tests: new `tests/object_visuals.tscn` + `object_visuals.gd`. Assert the
  camera body and frustum exist and the frustum corner spread grows with
  FOV; the directional arrow endpoint matches the light direction and the
  ground hit; the omni footprint radius matches `light_range`; frustum,
  arrow and footprint are pickable; look-through copies the transform and
  FOV, hides editing chrome, blocks orbit, exits via the 96×44 control and
  restores the exact saved transform/FOV; the inspector hint is gone and
  the action exists at 96×44. Add an xvfb capture proving the camera body,
  frustum and light arrow are visible against the sky.

## 12. Dispatch grouping (user ruling, 2 Nov)

The user asked for easy work to be folded into hard work instead of
occupying its own parallel seat. Five worktrees, not seven:

- **G1 (hard + easy): W1 + W6.** Branch `ws/renderer-environment`,
  worktree `kinema-renderer-environment`. Both own `gfx.gd`; one owner
  removes the renderer/environment conflict and keeps the sky tied to the
  real renderer capability matrix.
- **G2 (hard + easy): W2 + W4.** Branch `ws/timeline-hierarchy`,
  worktree `kinema-timeline-hierarchy`. Both are discoverability fixes that
  share `editor.gd`; one owner keeps the timeline budget and the outliner
  auto-expand wiring coherent.
- **G3 (hard): W3.** Branch `ws/rig-blender`, worktree
  `kinema-rig-blender`.
- **G4 (hard): W5.** Branch `ws/mp4-quality`, worktree
  `kinema-mp4-quality`.
- **G5 (hard): W7.** Branch `ws/camera-lights`, worktree
  `kinema-camera-lights`.

A grouped branch must satisfy both workstreams' contracts, tests and
captures; its report lists evidence per workstream. Reviews are scoped to
the combined diff and may raise findings for either half. The old
`ws/renderer-android`, `ws/timeline-compact` and `ws/hierarchy-discover`
branches are retired without merging.

## 13. Verification and handoff additions

The G1 gate adds `environment.tscn`; the G5 gate adds
`object_visuals.tscn`. Both must run headless and under xvfb for their
capture assertions. W6 and W7 also run the full existing suite list from §9.

The handoff must add these device-only checks: the sky and sun are visible
on a real panel, shadows are readable but not black, the camera frustum and
directional arrow show direction, the omni footprint matches range, and
look-through exits from the 96×44 control. No APK containing any of this
wave exists until CI runs `assembleStandardDebug` after the user pushes.
