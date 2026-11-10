# Kinema Studio wave 3 — renderer risk, rig workbench, timeline workspace, materials

Date: 2026-11-03
Base: `feat/professional-rebuild` @ `3281d52`
Extends: `2026-11-02-device-defect-wave-2-design.md` (binding formatting model,
touch rules, renderer gate, timeline budget, rig subset, hierarchy contract).
Supersedes: any earlier statement that Android Forward+ may never unlock its
high-end effects, that the speed graph is a transition-scalar editor only, or
that materials are limited to a primitive base colour.

## 1. Intent

Wave 2 made the studio usable on a phone. Wave 3 makes the hard paths
production-grade:

1. Forward+ on Android is no longer permanently clamped. A single, explicit
   risk setting lets the user unlock the real high-end feature set, with a
   boot probe that returns to the mobile-safe profile if the launch fails.
2. Rigging becomes a Blender-shaped touch workbench: imported glTF/GLB
   skeletons are detected and announced, pose rotation and translation are
   precise, poses persist, and bone position/scale keys are real animation
   data. FBX gets an honest conversion path instead of a hidden rejection.
3. The timeline stops sacrificing the speed graph for the clip rows. A
   landscape **Timeline Workspace** gives clips/dope and curve editing real
   space; the compact sheet keeps quick edits. The graph edits real key time
   and value, with bounce/elastic/back/spring families baked into real keys.
4. Android MP4 export actually reaches its Java MediaCodec backend.
5. Shading becomes a project material library: PBR texture maps, UV
   transform, and PBR/Unlit/Toon/Rim shading models on real
   `StandardMaterial3D` resources (and `ORMMaterial3D` only when a packed ORM
   map is used), assignable per object, part and surface.

Material scope is **texture maps + shading models**. Direct model painting and
a shader-node graph are explicitly out of scope.

## 2. Rulings

- **One renderer risk switch, not scattered overrides.** The user opts into
  high-end Forward+ effects once. Turning it on writes the probe state before
  applying anything. A launch that never reaches the editor reverts to the
  mobile-safe profile and says why. The switch is reversible at any time with
  "Restore mobile-safe".
- **Imported skeleton rest stays locked.** Its rest transforms belong to the
  asset's bind pose and its imported animation. Pose, numeric pose editing,
  translation, rotation, IK and keying are fully editable. The lock is
  explained, never silent.
- **FBX is not pretended.** Godot's FBX importer is editor-only. The picker
  accepts `.fbx` so the user can discover the limitation, then shows a real
  conversion sheet (Blender → glTF 2.0 `.glb`), not an error toast that looks
  like a bug.
- **The timeline workspace is landscape-first.** Compact remains the default
  and the only surface below 720 dp width. The workspace never appears as a
  surprise: it is opened by an explicit Expand action and closed first by the
  Android back gesture (after modals and the drawer, before project close).
- **The graph edits keys, not decorations.** No fake Bezier handles. Scalar
  transition presets stay. Bounce/elastic/back/spring are baked into real
  keys at a capped sample rate, and the result is undoable as one edit.
- **Materials are real resources.** Every map maps to a real
  `StandardMaterial3D` property; a packed ORM map selects `ORMMaterial3D`,
  because `StandardMaterial3D` exposes `orm_texture` but does not generate the
  ORM shader path in Godot 4.7. Every shading model maps to a real enum.
  Missing textures, missing UVs and unsupported images are reported, never
  silently approximated without a notice.
- **Only mesh parts receive part-level materials.** A part path must resolve
  to a `MeshInstance3D` with a real mesh. Non-mesh parts remain selectable in
  the hierarchy but expose no material assignment and no recursive write.
  Object-level assignment covers whole models.
- **Project format 3 is additive.** Wave-1/2 projects load unchanged and keep
  their legacy primitive colours until a library material is assigned.

## 3. Global constraints

- Touch-first Android 15–17, landscape priority. Every visible target is at
  least 44 dp; primary actions are 96×44; corners are square; IBM Plex only;
  achromatic chrome; pure black background; red only for destructive/error.
- No fake feature: unavailable controls are disabled with the exact reason.
  A device-only path is never reported as verified from a Linux headless run.
- No new custom shaders. All shading uses `StandardMaterial3D` and its real
  properties, plus `ORMMaterial3D` for the packed-ORM case (same
  `BaseMaterial3D` property set, different shader path).
- All user-visible copy is English, concise and specific. No placeholder
  lorem, no "coming soon".
- Worktrees are isolated and branch from this document's commit. The lead
  merges workstreams; subagents never push.
- Builds only through GitHub Actions `assembleStandardDebug`, arm64-v8a, CI
  debug keystore, package `studio.kinema.app`. A local export is not an
  acceptable substitute.
- Tests are written first and watched failing. Full gates after every
  workstream: parse 0; smoke, layout (headless + xvfb), animation, media, rig,
  hierarchy, gizmo, environment, object_visuals all PASS, plus the new
  `graphics`, `timeline_workspace` and `materials` suites.

## 4. Workstreams and merge model

| ID | Scope | Primary files |
|----|-------|---------------|
| W1 | Android MP4 gate, Forward+ risk | `android_video.gd`, `media_system.gd`, `gfx.gd`, `settings_panel.gd` (graphics section), `main.gd`, tests `graphics.gd`, `media.gd` |
| W2 | Import + rig workbench | `rig_system.gd`, `pose_library.gd`, `rig_overlay.gd`, `rig_panel.gd`, `rig_toolbar.gd`, `project_store.gd` (model import), `document.gd` (bone tracks), `editor.gd` (import notices/FBX sheet), `tests/rig.gd` |
| W3 | Timeline workspace + speed graph | `timeline.gd`, `src/ui/speed_graph.gd` (new), `src/core/speed_curve.gd` (new), `editor.gd` (timeline layout/back), `document.gd` (insert at time), `tests/timeline_workspace.gd` (new), `tests/layout.gd` |
| W4 | Material library + shading + textures | `src/core/material_system.gd` (new), `document.gd` (format/materials), `project_store.gd` (texture import), `inspector.gd`, `src/ui/material_sheet.gd` (new), `src/ui/material_editor_sheet.gd` (new), `editor.gd` (sheets/picker), `tests/materials.gd` (new), `tests/smoke.gd`, `tests/object_visuals.gd` |

Shared files `document.gd`, `editor.gd`, `project_store.gd` and
`tests/smoke.gd` are merged in W1 → W2 → W3 → W4 order. Subagents must keep
their diffs confined to the named sections and must not reformat unrelated
code. Any conflict outside a workstream's named section is resolved by the
lead, never by a broad rewrite.

Each subagent gets at most two fix rounds: one self-review/fix pass after its
own gates, then one pass for failures found by the lead's merge gates. If a
gate still fails after round two, the subagent stops and reports the exact
failure instead of entering a loop.

## 5. W1 — Android MP4 and the Forward+ risk switch

### 5.1 MP4 platform gate

The backend and the Java encoder are already staged. The failure is string
equality:

- `studio/src/core/android_video.gd:31` and `:57` compare `OS.get_name()` to
  lowercase `"android"`.
- `studio/src/core/media_system.gd:347` does the same before loading the
  backend.

`OS.get_name()` returns `"Android"` on device, so every Android path is
rejected and every non-Android path is not.

Changes:

- Add `AndroidVideo.is_android(platform: String = OS.get_name()) -> bool`
  returning `platform == "Android"`. Both `available()` and
  `frames_available()` use it.
- Add `AndroidVideo.video_reference_supported(platform: String = OS.get_name())
  -> bool` and make `MediaSystem.import_video_reference` use it instead of the
  raw comparison. Keep the exact refusal text on non-Android platforms.
- Audit the repository for any other lowercase `"android"` comparison and fix
  only real platform gates.

Regression tests (in `tests/media.gd`):

- `is_android("Android")` is true; `is_android("android")`, `"Linux"`,
  `"Windows"` and `""` are false.
- `video_reference_supported("Android")` is true; `("Linux")` is false.
- On Linux the backend still reports unavailable with the exact reason, and
  `capabilities()` still reports unsupported. The test proves the gate, not
  an encode.
- Device-only: actual MediaCodec encode remains on the device checklist.

### 5.2 Renderer risk state

New persisted fields in `graphics.json`:

```json
{
  "risk_enabled": false,
  "risk_boot": "idle",
  "risk_last_error": ""
}
```

`risk_boot` is one of `idle`, `probing`, `proven`.

```text
startup (Gfx._ready, before any profile is applied)
  if risk_boot == "probing":                  # previous launch died
      risk_enabled = false
      risk_boot = "idle"
      risk_last_error = "High-end Forward+ effects were reverted because
                        the previous launch did not reach the editor."
      save()
  else if risk_enabled and mobile and actual == forward_plus:
      risk_boot = "probing"                   # write before apply
      save()
  apply profile

after the editor has drawn its first frame
  mark_renderer_ready():
      if risk_boot == "probing": risk_boot = "proven"; save()

user enables risk while running
  risk_enabled = true
  risk_boot = "probing"                       # write before apply_all
  risk_last_error = ""
  save()
  apply_all()
  editor awaits RenderingServer.frame_post_draw
  Gfx.confirm_risk_probe() -> risk_boot = "proven"; save()

user restores mobile-safe
  risk_enabled = false
  risk_boot = "idle"
  save()
  apply_all()                                 # clamps immediately
```

The probe is only armed when the platform is Android/iOS and the actual
backend is Forward+. Enabling the switch while Mobile is running is allowed
but has no effect until Forward+ runs; the UI states that.

Public API:

- `Gfx.risk_enabled: bool`
- `Gfx.risk_boot: String`
- `Gfx.risk_last_error: String`
- `Gfx.risk_supported(platform := OS.get_name()) -> bool`
- `Gfx.risk_active(platform := OS.get_name(), method := actual_method()) -> bool`
- `Gfx.enable_risk() -> bool`
- `Gfx.disable_risk() -> void`
- `Gfx.confirm_risk_probe() -> void`
- `Gfx.begin_risk_boot(platform, method) -> Dictionary` (pure decision helper
  used by tests, returns action/preference/boot/reason)
- `Gfx.risk_profile(platform, method, enabled) -> Dictionary` (pure, testable)

### 5.3 Effective profile

`safe_forward_plus_profile(platform, actual_method)` gains a third optional
argument `risk := risk_enabled` (default reads the live field).

With risk **off** on Android/iOS Forward+, the wave-2 clamp is unchanged:
TAA/SSIL/SSR/fog off, MSAA ≤ 2×, 3D scale ≤ 0.85, shadow quality ≤ 2,
distance ≤ 40 m, 2 cascades, FPS ≤ 60.

With risk **on** on Android/iOS Forward+, the profile uses the user's stored
values with these hard maxima:

| Setting | Risk-on maximum |
|---|---|
| MSAA | 8× (`msaa = 3`) |
| TAA / SSIL / SSR / volumetric fog | allowed |
| 3D scale | 1.0 |
| Shadow quality | Ultra (`3`) |
| Shadow distance | 100 m |
| Shadow cascades | 4 |
| Max FPS | 120 |

Desktop profiles are unchanged in both states. The hard maxima are the same
Desktop limits; the risk switch removes the mobile clamp, it does not invent
values the engine cannot serve.

`capabilities_for(method, platform, risk := false)` reports the effective
caps. On mobile Forward+ with risk on it returns `mobile_safe = true`,
`risk_unlocked = true`, the full caps above, and
`risk_reason = "High-end effects are on. Stability is not guaranteed."`.
Without risk it returns the existing clamped caps and
`risk_unlocked = false`.

### 5.4 Settings UI

Only on Android/iOS, at the top of **Graphics** (above Quality preset):

- A toggle row "High-end Forward+ effects" with the caption "Accept the risk
  of disabling the mobile-safe clamp". The toggle is 44 dp high; the whole row
  is tappable.
- Turning it on opens a confirmation sheet:
  - Title: "Enable high-end Forward+ effects?"
  - Body: "Kinema will run the real Forward+ feature set. Some Android GPUs
    crash or overheat with these effects. If the next launch fails to reach
    the editor, Kinema returns to the mobile-safe profile automatically."
  - Actions: `Cancel` and `Enable risk` (96×44). No fake "safe mode" claim.
- When enabled, a persistent warning card shows the exact state and a 96×44
  **Restore mobile-safe** action. `risk_last_error` is shown in the same card
  with `Kit.WARNING`.
- Clamped controls become enabled exactly per the risk profile: 4×/8× MSAA,
  TAA, SSIL, SSR, volumetric fog, Ultra shadows, 4 cascades, 60/100 m range,
  100% 3D scale. Their hint reads "High-end · risk accepted" instead of
  "Clamped on Android Forward+ for stability."
- If risk is enabled but the running backend is Mobile, the card says
  "High-end effects apply when Forward+ is running." and the clamps remain
  neutral for the current backend.
- The renderer entry note on mobile changes to "Experimental on Android:
  high-end effects follow your risk setting." when risk is enabled.

The settings panel emits `risk_change_requested(enabled)`; the editor owns the
confirmation sheet and calls `Gfx.enable_risk()` / `Gfx.disable_risk()`.

### 5.5 Tests (new `tests/graphics.gd`)

- `risk_profile("Android", "forward_plus", false)` matches every wave-2 clamp.
- `risk_profile("Android", "forward_plus", true)` allows all high-end values
  and clamps at the hard maxima above.
- `risk_profile("Linux", "forward_plus", true/false)` is identical.
- `risk_profile("Android", "mobile", true)` is not a Forward+ profile; no
  high-end effect is reported available.
- `begin_risk_boot`:
  - `probing` + enabled on the next launch → revert to safe, reason non-empty.
  - enabled + mobile + Forward+ from idle → probe.
  - enabled + Mobile → no probe.
  - disabled + probing → clear to idle without a scary reason.
- `enable_risk` writes `probing` before the profile is applied (test the
  serialized dictionary, not file timing), `confirm_risk_probe` moves it to
  `proven`.
- Persistence round-trip through `to_dict`/`load_preferences` keeps the three
  fields and defaults missing fields safely.
- `capabilities_for("forward_plus", "Android", true)` unlocks every gated
  control and reports `risk_unlocked`.

## 6. W2 — Import detection and the rig workbench

### 6.1 Import: glTF resources, FBX help, adoption notice

**glTF with external buffers/textures.** Today the importer copies the
`.gltf` bytes to a temp file with no siblings, so `append_from_file` cannot
resolve `.bin` or image URIs. Replace that path for `.gltf`:

1. Parse the JSON and collect `buffers[].uri` and `images[].uri`.
2. Skip `data:` URIs and absent URIs. Reject absolute paths and any path that
   escapes the source folder after `simplify_path()`.
3. Validate with
   `GLTFDocument.append_from_buffer(bytes, uri.get_base_dir(), state)` so
   relative resources resolve from the source folder. If validation fails,
   return the honest error and write nothing.
4. Copy the `.gltf` and every referenced file into
   `models/<unique-slug>/`, preserving relative paths. Validate that every
   target stays inside that folder.
5. Return `rel_path = "models/<slug>/<file>.gltf"`. `_build_import_visual`
   already resolves relative siblings from the project folder.
6. On any write failure, delete the destination folder recursively.

Missing external files get the exact message: "This .gltf references files
that are not next to it. Move the .gltf, its .bin and its textures into one
folder, or export a .glb." No partial project entry is left behind.

**FBX discoverability.** Add `*.fbx` to the native file picker filter. When an
FBX is selected, do not call `ProjectStore.import_model`; open a real
conversion sheet:

- Title "FBX needs a conversion".
- Body: "Godot's FBX importer only exists in the editor, so it cannot run on
  Android. Convert the model to glTF 2.0 first."
- Steps: 1) Open the model in Blender. 2) File → Export → glTF 2.0. 3) Choose
  glTF Binary (`.glb`). 4) Import the `.glb` in Kinema.
- Actions: `Choose another file` (96×44, reopens the picker) and `Cancel`.

`ProjectStore.import_model` still rejects FBX with its existing reason if
called directly; the picker path never presents it as a supported format.

**Skeleton adoption notice.** Adoption already works for glTF/GLB and finds
any `Skeleton3D`, including armature-only files without a skinned mesh
(`adopt_imported_skeleton` scans the whole generated tree). Add an explicit
signal so detection is visible:

- `Document.rig_adopted(object_id: String, bone_count: int)` emitted once after
  a successful import-time adoption. Load/undo never re-emit it.
- Editor shows one toast: "Skeleton detected · <N> bones · Pose mode is
  ready." with no modal. The rig tab count and the existing imported note
  remain the persistent evidence.
- If an import has no skeleton, no notice is emitted. No fake "rig ready".

Imported rest editing stays locked. The Rig toolbar's Edit and Add bone
controls remain disabled with
"Imported skeleton: rest editing is locked. Pose and IK still work." The rig
panel keeps the same note above the read-only rest fields.

### 6.2 Pose model v2 and persistence

`PoseLibrary` stores full local transforms:

```json
{
  "bones": {
    "Hips": {"p": [0, 0, 0], "r": [0, 0, 0, 1], "s": [1, 1, 1]}
  },
  "root_position": [0, 0, 0]
}
```

- `capture()` writes p/r/s for every bone and the rig root position.
- `apply()` sets position, rotation and scale, and the root position.
- `serialize()`/`deserialize()` preserve the new shape. A legacy pose whose
  bone value is a quaternion array is read as rotation-only; missing p/s stay
  at the skeleton's current values. No legacy file is rejected.
- `root_position` remains for compatibility; it never replaces the object's
  transform on load (the document object transform is authoritative). It is
  applied only when a saved pose is explicitly applied.

Rig JSON gains a top-level `"pose"` field holding the current pose. Rules:

- `RigSystem.to_data()` captures the live skeleton pose when the node exists;
  otherwise it keeps the last stored pose.
- `load_data()` reads `"pose"` and applies it after the skeleton is rebuilt,
  inside the loading guard, without opening a history entry.
- Undo/redo works because `Document.to_data()`/`_apply_data()` already carry
  the full rig record; pose changes made through transactions become part of
  the snapshot.
- Saving and reopening a project restores the pose exactly (p/r/s).

### 6.3 Pose transactions, autokey and bone keys

The overlay currently writes `skeleton.set_bone_pose_rotation` directly, so a
pose drag is not undoable and autokey never sees it. Fix this at the rig
system boundary:

- `RigSystem.begin_pose_edit(label: String) -> void` calls `_begin(label)`.
- `RigSystem.end_pose_edit() -> void` calls `_end()`.
- `RigSystem.set_bone_pose(rig_id, bone, patch: Dictionary) -> bool` applies
  `p`/`r`/`s` to the live `Skeleton3D`; when `doc.autokey` is on it inserts
  keys for exactly the changed channels at `doc.current_time`.
- `RigSystem.apply_saved_pose(rig_id, pose_id) -> bool` wraps
  `PoseLibrary.apply` in one transaction, applies autokey when enabled, and
  refreshes the panel.
- `RigSystem.reset_bone_pose` / `reset_all_poses` use the same path.
- The overlay opens one transaction in `_begin_drag`, writes through
  `set_bone_pose` on every drag update, and closes it in `_end_drag`. A drag
  with no change creates no undo entry because `Document.end_edit` compares
  before/after snapshots. Cancelling a drag restores the captured start pose.

Bone keying:

- `Document.insert_pose_keys(rig_id, pose)` accepts both the legacy
  quaternion/array shape and the new `{p,r,s}` shape.
- For each bone it writes rotation, position and scale tracks at the current
  time, updating an existing key at that time rather than duplicating it.
- `RigSystem.key_pose` captures p/r/s and inserts all three channels as one
  undo entry. A per-bone "Key pose" action keys every bone in the rig.
- The rig panel's existing key buttons keep their labels; a small caption
  states "Rotation, position and scale" so the behavior is not a surprise.

### 6.4 Touch pose editing

**Floating Rig toolbar** (`rig_toolbar.gd`):

- Keep Pose/Edit, Add bone (edit only) and Done.
- Add a 44 dp **Transform** segment: `Rotate` / `Move`. Pose mode only; Edit
  keeps its rest handles.
- Add a 44 dp **Axis** segment: `Free` / `X` / `Y` / `Z`. This is the touch
  replacement for Blender's axis keys and removes the "vague screen rotation"
  problem.
- On imported rigs, Edit/Add remain disabled; Transform and Axis stay enabled
  in Pose.

**Overlay** (`rig_overlay.gd`):

- Rotate with axis Free: current camera-relative yaw/pitch, but the drag is
  computed from the captured start rotation and committed through
  `set_bone_pose`.
- Rotate with X/Y/Z: build the delta around the bone's local axis (converted
  to world for the camera-facing sign) and ignore the other screen delta.
  Sensitivity stays 0.012 rad/px, clamped to ±π per gesture.
- Move with axis Free: translate in the camera's right/up plane, scaled by the
  bone's world length and camera distance so short bones are not impossible
  to move. Snap to 0.01 units when `doc.snap` is on.
- Move with axis X/Y/Z: project the screen delta onto that world axis.
- Show a live readout near the active bone: rotation angle in degrees or
  translation distance in units while dragging. It disappears on release.
- Hit radius stays 22 dp; handles stay 22 dp. One gesture = one undo entry.
- Never write the skeleton directly. All pose writes go through
  `RigSystem.set_bone_pose`.

**Rig panel** (`rig_panel.gd`):

- Split the bone inspector into **Rest** and **Pose** sections.
- Rest keeps the existing p/r/s/length/influence fields; on imported rigs they
  are disabled with the existing note.
- Pose adds p/r/s numeric fields (9 fields, 44 dp rows) that are always
  editable, including imported rigs. Each commit goes through
  `set_bone_pose` in one transaction; autokey applies.
- Add a 96×44 "Reset pose" per bone beside the existing reset-all action.
- The imported note moves directly above Rest; it no longer implies Pose is
  locked.
- Pose changes do not rebuild the whole panel; values refresh from the
  skeleton after each edit, preserving scroll position.

### 6.5 Tests (`tests/rig.gd` additions)

- Pose v2 capture/apply round-trips p/r/s; legacy quaternion poses still
  apply rotation and do not throw.
- Rig JSON persists `pose`; save → new document load → pose values match
  (position, rotation, scale) and undo after a pose drag restores the start.
- A pose drag opens exactly one undo entry; a zero-movement tap opens none.
- Autokey on: `set_bone_pose` at a new time creates rotation, position and
  scale keys; at an existing time it updates instead of duplicating.
- `key_pose` writes three track types per bone with the same time.
- Imported rig: Rest fields disabled, Pose fields editable, Edit/Add disabled,
  Transform/Axis enabled.
- Axis-locked rotation changes only the selected local axis (within epsilon);
  axis-locked move changes only that world axis.
- Free move translates the active bone and does not rotate it.
- `.gltf` external-buffer import: a generated two-file fixture imports and
  loads its mesh; a missing `.bin` is rejected with the exact message and
  leaves no `models/<slug>` folder.
- FBX help sheet opens from a selected `.fbx`; `ProjectStore.import_model`
  still refuses it with the existing reason.
- Skeleton adoption emits `rig_adopted` once for a GLB fixture and once for
  an armature-only fixture; loading the project does not re-emit it.

## 7. W3 — Timeline workspace and speed graph

### 7.1 Compact sheet: the graph gets its space back

The current graph is measured at 915×412 with a 24 dp plot because the sheet
is 109.5–148.1 dp and the graph top is fixed at 88 dp. That is unusable.

Entering graph mode is an explicit user action, so it may raise the sheet for
the session:

- `_timeline_more = true` when graph mode opens. Dope keeps the existing More
  contract (session-only, 46% / 260 dp cap). Graph mode gets its own
  session-only budget: up to **62% of stage height / 300 dp**, because the
  user explicitly entered graph mode and the 46% cap cannot yield a usable
  plot. Closing and reopening the sheet resets both.
- In graph mode, the clip lane and media lanes fold, and the header folds to
  one 44 dp row. The compact graph keeps its existing Timeline-owned channel
  tab strip (three 44 dp targets); compact graph drawing stays in
  `timeline.gd`, and `SpeedGraph` remains workspace-only.
- The measured plot is the area between the channel tab strip + 12 dp and the
  key row − 12 dp. It must be at least **120 dp** whenever graph mode is open.
  At 915 × 412 the 62% budget yields about 131 dp. If the stage cannot afford
  120 dp even at 62% (a very short window), show the honest caption "Rotate or
  open the timeline workspace for curve editing" instead of a 24 dp sliver.
- Dope mode keeps the wave-2 budget, lanes and behavior. Switching back to
  dope restores them.
- The compact graph keeps quick actions: select/retime keys, transition
  presets, and a 44 dp Expand button. Deep value editing lives in the
  workspace.

### 7.2 Timeline Workspace

Entry:

- A 44 dp `maximize` icon button in the timeline header, tooltip "Open
  timeline workspace". Visible when the sheet is open.
- Available only at width ≥ 720 dp and height ≥ 360 dp. Below that it is
  disabled with the reason "Landscape workspace needs at least 720 × 360 dp".
  If the window drops below either bound while open, close the workspace and
  show one toast explaining why.

Exact layout inside a full-rect stage overlay:

```text
┌──────────────────────────────────────────────────────────────┐
│ Timeline · <clip name>                         [Close 96×44] │ 56 dp
├───────────────────────────────┬──────────────────────────────┤
│ clip lane (≤ 96 dp)           │ Speed graph                  │
│ dope sheet / channels         │ header + plot + key row      │
│                               │                              │
│        52% width              │         48% width            │
├───────────────────────────────┴──────────────────────────────┤
│ transport (single existing instance)                         │ 56 dp
└──────────────────────────────────────────────────────────────┘
```

- The body gutter is 8 dp. At 1280×800 the graph plot is at least 480 dp
  tall; the 120 dp floor is a hard minimum, not the target.
- The left column is the existing `Timeline` in workspace mode (dope only,
  no mode tabs, no More), with `_lane_scroll` above it. The right column is
  the new `SpeedGraph`. The bottom is the existing transport panel, reparented
  with `mount_transport`.
- Opening reparents `_lane_scroll` and `_timeline` into the workspace and
  mounts the transport at the footer. Closing restores the exact previous
  parents and child order. The compact panel is hidden while open.
- The header has a 96×44 **Close** button and the clip name. No duplicate
  transport, no second document, no separate selection model for clip rows.
- Back precedence in `editor.handle_back()`:
  1. look-through
  2. render mode
  3. overlay modal / sheet
  4. side drawer
  5. timeline workspace
  6. project close request
- Any project close path calls `_close_timeline_workspace(false)` before the
  close sheet, so the workspace cannot outlive the project.
- Rotating to a supported portrait width (≥720 dp, unusual but possible)
  keeps the workspace; below the bound closes it as above.

### 7.3 `SpeedGraph` control

New `studio/src/ui/speed_graph.gd`, used only by the workspace. Shared curve
math lives in `studio/src/core/speed_curve.gd` and is also used by the
compact sheet's preset menu.

Layout inside the right column:

- Header 56 dp: channel name and key count on the left; 44 dp `Value` /
  `Speed` segmented; `Fit` (44 dp); `Multi` toggle (44 dp); `Presets`
  (96×44, or a 44 dp `curve` icon with the tooltip "Curve family presets"
  when the right column is narrower than 420 dp).
- Plot: everything between the header and the key row, minimum 120 dp. A
  time ruler sits on top, value labels on the left, playhead in `Kit.TIME`.
- Key row 56 dp: selected key time field, value field, component menu (44 dp;
  position/scale Value view only, options `All` `X` `Y` `Z`), `Add key`
  (96×44), `Delete` (44 dp). Numeric fields commit on enter/focus loss and
  open one undo entry. Delete is undoable, no modal.
- Empty states name the real cause: "Select an object", "No keys on this
  channel. Add a key at the playhead.", "This channel has no editable value
  component." Never draw a fake curve.

Channel binding and selection API:

- The graph has no independent channel picker. The left dope sheet is the
  picker: `Timeline` gains `signal channel_selected(channel: String)`, emitted
  by `set_channel()` and by a tap on a channel row (the full 44 dp label
  area). The workspace connects it to `SpeedGraph.set_channel`.
- The object is always `Document.selected_id`. Changing the object clears the
  graph selection and re-resolves keys by time. The graph header names the
  active channel and key count.
- Workspace-facing API: `set_context(object_id)`, `set_channel(channel) ->
  bool`, `get_channel() -> String`, `selected_indices() -> PackedInt32Array`,
  `select_indices(indices, additive := false)`, `clear_selection()`,
  `selected_segment() -> Dictionary`, and
  `signal selection_changed(indices)`. All edits go through `Document`; the
  control never mutates `Animation` directly.
- `selected_segment()` is the single source of enablement for **Easing** and
  **Curve family**. It returns `{ok: false, reason: "Select one key."}` when
  none or several keys are selected, and `{ok: false, reason: "The last key
  has no following segment."}` when the selected key is last. Otherwise it
  returns `{ok: true, start_index, end_index, t0, t1}`.

Views:

- **Value** (default): plots the real channel value. Position/scale show the
  selected component; `All` shows normalized components. Rotation shows Euler
  degrees for inspection, time editing only, with the caption "Rotation values
  are quaternion; drag rotates with the rig or gizmo." No fake Euler write.
- **Speed**: plots `|dv/dt|` sampled from the real animation, same as the
  compact graph. Keys are selectable and retimeable; vertical value drag is
  disabled with the caption "Switch to Value to edit values."
- The component menu is disabled for rotation in Value view with the reason
  above; it shows `All` for rotation so the disabled state has a stable label.

Editing:

- Tap selects one key. `Multi` turns tap into toggle-select; selected keys use
  `Kit.FOCUS_BRIGHT`.
- Drag horizontally retimes the key (snap to `1/fps` when `doc.snap`).
  Drag vertically edits the value in Value view for position/scale. A drag is
  one undo entry; multi-key drags commit all selected keys on release after a
  ghost preview.
- `Add key` inserts at the playhead using the sampled channel value and
  transition 1.0. `Delete` removes all selected keys in one edit.
- Copy stores `{time, transition, value}` relative to the first selected key;
  paste places the set at the playhead (clamped to duration), one undo entry.
- Fit sets the time window to `[0, duration]` and auto-fits the value range
  with 10% padding. Pinch zooms time around the pinch centre; `−`/`+` are not
  required because pinch and Fit are both explicit. Pan follows the existing
  two-finger timeline gesture. Minimum window is 0.1 s.
- Key selection is independent of the dope key selection; the channel is
  shared through `channel_selected`. Both edit the same document and both
  refresh on `keyframes_changed`; no stale key index survives a track change
  (re-resolve by time after a refresh, clear indices that no longer match).

Curve families and baking:

`SPEED_CURVES` in `speed_curve.gd`:

| id | family |
|---|---|
| `bounce_out`, `bounce_in`, `bounce_in_out` | Bounce |
| `elastic_out`, `elastic_in` | Elastic |
| `back_out`, `back_in` | Back |
| `spring` | Spring (damped) |
| `sine_in`, `sine_out`, `sine_in_out` | Sine |
| `expo_in`, `expo_out`, `expo_in_out` | Expo |

Every function maps `t ∈ [0,1]` to a finite scalar with `f(0)=0`, `f(1)=1`.
Bounce uses the standard 7.5625/2.75 piecewise curve. Elastic uses the
`2^(-10t) · sin(...) + 1` form. Back uses the 1.70158 overshoot constants.
Spring is a normalized damped cosine. Sine/Expo are the standard Penner
curves. No curve returns NaN or infinity.

Applying a family replaces one selected segment with baked keys. A segment
exists only when exactly one key is selected and that key is not the last key
of the channel; `selected_segment()` is the authority. Multi-select and the
last key disable both menus with the exact reason above. The segment runs from
the selected key to the next key.

1. `t0,t1` are the segment endpoints, `v0,v1` the key values.
2. Sample count `n = clamp(round((t1 - t0) * fps), 8, 48)`.
3. For `u = 1..n-1`, insert a key at `t0 + u/n * (t1 - t0)` with value
   evaluated at `f(u/n)`:
   - position/scale: `v0.lerp(v1, f)` (overshoot allowed, real curve);
   - rotation: axis-angle extrapolation between `q0` and `q1` scaled by `f`,
     so elastic/back overshoot remains a real quaternion;
   - any other type: numeric `lerp`.
4. Inserted keys use transition 1.0. The endpoint keys keep their values.
   Track interpolation type is unchanged; dense sampling keeps cubic close to
   the intended shape.
5. The whole bake is one undo entry. A notice states "Bounce out baked · 23
   keys". If the segment is shorter than two frames, insert one midpoint key
   and state "Segment is shorter than two frames; baked one midpoint."

Scalar transition presets from wave 2 remain available under **Easing** and
apply to the selected segment's start key exactly as today. The two menus stay
separate and are never merged into one list: **Easing** writes one
Godot-native transition scalar; **Curve family** bakes new keys. Both use
`selected_segment()` and are disabled together when it returns `ok = false`.
Baking from the last key is impossible, not silently redirected to another
segment.

### 7.4 Tests (new `tests/timeline_workspace.gd`)

- Compact graph at 915×412: after `set_mode("graph")` the sheet respects the
  62% / 300 dp graph budget, the plot is ≥120 dp, `_timeline_more` is true,
  clip and media lanes are out of the budget, and switching back to dope
  restores the 46% / 260 dp behavior and the lanes.
- Workspace at 915×412 and 1280×800: left width 45–55%, graph plot ≥120 dp,
  header and footer 56 dp, every button ≥44 dp.
- Open reparents timeline, lane and transport into the workspace; close
  restores their original parents and order; opening twice is idempotent.
- Back precedence: modal → drawer → workspace → close, in that order.
- Workspace closes when the window drops below 720×360 and leaves the compact
  sheet usable.
- Tapping a dope channel row emits `channel_selected` and the workspace graph
  switches channel; switching the selected object clears the graph selection
  and re-resolves keys by time.
- `selected_segment()` is false for no selection, multi-selection and the last
  key (each with its exact reason); both Easing and Curve family are disabled
  in those states and enabled for one non-last key.
- Changing the graph channel clears stale key indices and never selects a key
  from the previous channel.
- `SpeedCurve` endpoints are 0/1, all values finite, bounce/elastic/back
  overshoot within expected bounds.
- Baking a segment inserts 8–48 keys, keeps endpoints, is one undo entry, and
  a subsequent undo returns the original key count and value.
- Select/multi-select retime/value drag, copy/paste, add/delete all round-trip
  through document keys and undo.
- Value view time edit on a rotation channel is refused with the exact reason;
  time edit still works.

## 8. W4 — Material library, texture maps and shading models

### 8.1 Material record

Project-level `materials` array. One record:

```json
{
  "id": "mat_2",
  "name": "Brushed steel",
  "shading": "pbr",
  "albedo_color": "#B8BCC2",
  "albedo_texture": "textures/brushed-steel/albedo.png",
  "normal_texture": "",
  "normal_scale": 1.0,
  "orm_texture": "",
  "roughness_texture": "",
  "roughness_texture_channel": 1,
  "metallic_texture": "",
  "metallic_texture_channel": 2,
  "ao_texture": "",
  "ao_texture_channel": 0,
  "emission_color": "#000000",
  "emission_energy": 0.0,
  "emission_texture": "",
  "roughness": 0.42,
  "metallic": 0.0,
  "metallic_specular": 0.5,
  "rim": 1.0,
  "rim_tint": 0.5,
  "uv1_scale": [1.0, 1.0],
  "uv1_offset": [0.0, 0.0],
  "texture_filter": 3,
  "texture_repeat": true
}
```

Rules:

- `shading` is one of `pbr`, `unlit`, `toon`, `rim`.
- Texture paths are project-relative, forward-slash, and must not escape the
  project folder. Empty means no map.
- `roughness` and `metallic` are the scalar fallbacks, always meaningful even
  with a map present (the map wins where Godot uses it).
- `orm_texture` is a packed map: R = ambient occlusion, G = roughness,
  B = metallic. A non-empty `orm_texture` selects `ORMMaterial3D` for that
  record and is authoritative over the separate `roughness_texture`,
  `metallic_texture` and `ao_texture` slots. Those slots keep their stored
  paths but are not applied while ORM is set; clearing ORM re-enables them.
  This is not cosmetic: `StandardMaterial3D` exposes `orm_texture` but only
  `ORMMaterial3D` builds the ORM shader path in Godot 4.7.
- `emission_energy` 0 disables emission; the UI uses a 0–10 scrub.
- `uv1_scale/offset` map to `Vector3(x, y, 1)` / `Vector3(x, y, 0)`.
- Missing texture files are reported in the material editor and fall back to
  colour/scalars; the render never crashes.

### 8.2 `MaterialSystem` API

`src/core/material_system.gd` is a `RefCounted` owned by `Document` (same
pattern as `RigSystem`). It owns the array, JSON conversion, texture cache,
assignment resolution and material construction. Construction returns
`ORMMaterial3D` iff the record has a non-empty `orm_texture`, and
`StandardMaterial3D` otherwise. Toggling ORM therefore rebuilds the resource
and re-applies every assignment in the same edit.

```text
signal materials_changed
var last_error: String
func setup(document)
func to_data() -> Dictionary                 # {"materials": [...]}
func load_data(raw: Dictionary) -> void
func material_ids() -> PackedStringArray
func get_material(id) -> Dictionary
func create_material(name := "Material", preset := "matte") -> String
func duplicate_material(id) -> String
func delete_material(id) -> bool             # clears assignments first
func update_material(id, patch: Dictionary) -> bool
func can_assign_part(object_id, part_path) -> bool
func assign_material(object_id, material_id, part_path := "", surface := -1) -> bool
func clear_material(object_id, part_path := "", surface := -1) -> bool
func resolve_assignment(object_id, part_path := "", surface := -1) -> String
func apply_object(object_id) -> void
func apply_all() -> void
func adopt_import(object_id, generated: Node, model_name: String) -> Dictionary
func missing_textures() -> Array[String]
```

`assign_material` and `clear_material` are strict:

- An empty `part_path` targets the object root and is always valid. It applies
  to every mesh surface under the object that has no more specific part or
  surface assignment.
- A non-empty part path must resolve to a `MeshInstance3D` with a non-null
  mesh.
  Non-mesh parts are selectable in the hierarchy but are not assignable; the
  call returns `false`, writes nothing, opens no undo entry, and sets
  `last_error = "This part has no mesh to shade."` No recursion to child
  meshes is performed; the object-level assignment is the whole-model path.
- `surface = -1` targets the part-level slot. `surface >= 0` requires
  `0 <= surface < mesh.get_surface_count()`; otherwise the call returns
  `false` with `last_error = "Surface N is out of range."`
- `last_error` is cleared at the start of every successful mutation.

Preset ids: `matte`, `satin`, `metal`, `plastic`, `emissive`, `toon`,
`unlit`. They only set real fields in the record.

Assignments live on the object:

```json
{
  "material_id": "mat_2",
  "part_materials": {"Model/Body": "mat_3"},
  "part_surface_materials": {"Model/Body#2": "mat_4"}
}
```

Resolution for a rendered surface: `part_surface_materials["path#N"]` →
`part_materials["path"]` → object `material_id` → legacy primitive fields.
`path#N` is the Nth surface of the `MeshInstance3D` at `path`; the index is the
mesh surface index, not a child index. `surface = -1` means the part-level
slot. Empty paths mean the object root. Imported part paths are the existing
stable `Model/...` hierarchy paths. `Document.import_parts()` stays
hierarchy-wide so users can inspect every node; material targeting is the
stricter mesh check above.

All mutations run inside `Document.begin_edit`/`end_edit` at the UI boundary;
assignments and material edits are undoable. Deleting a material clears every
assignment that referenced it in the same edit and re-applies the affected
objects.

### 8.3 Material construction and property mapping

Class selection: `orm_texture != ""` → `ORMMaterial3D`; otherwise
`StandardMaterial3D`. Both derive from `BaseMaterial3D`, so shading, albedo,
normal, emission, UV and filter properties below are valid on either class.
The separate roughness/metallic/AO map rows are not applied when ORM is set;
their stored values survive for when ORM is cleared.

| Record | Property |
|---|---|
| `albedo_color` | `albedo_color` |
| `albedo_texture` | `albedo_texture` |
| `normal_texture` + `normal_scale` | `normal_enabled = texture != ""`, `normal_texture`, `normal_scale` |
| `orm_texture` | `orm_texture` on `ORMMaterial3D` (R=AO, G=roughness, B=metallic) |
| `roughness_texture` / channel | `roughness_texture`, `roughness_texture_channel` (not applied while ORM is set) |
| `metallic_texture` / channel | `metallic_texture`, `metallic_texture_channel` (not applied while ORM is set) |
| `ao_texture` / channel | `ao_enabled = texture != ""`, `ao_texture`, `ao_texture_channel` (not applied while ORM is set) |
| `emission_color` + energy | `emission_enabled = energy > 0`, `emission`, `emission_energy_multiplier` |
| `emission_texture` | `emission_texture` |
| `roughness`, `metallic`, `metallic_specular` | same scalars |
| `uv1_scale`, `uv1_offset` | `uv1_scale = Vector3(x, y, 1)`, `uv1_offset = Vector3(x, y, 0)` |
| `texture_filter`, `texture_repeat` | same |

Shading:

- `pbr`: `shading_mode = SHADING_MODE_PER_PIXEL`, default diffuse/specular.
- `unlit`: `shading_mode = SHADING_MODE_UNSHADED`; lighting-only fields are
  hidden in the editor with the note "Unlit ignores lighting."
- `toon`: `SHADING_MODE_PER_PIXEL`, `diffuse_mode = DIFFUSE_TOON`,
  `specular_mode = SPECULAR_TOON`.
- `rim`: `SHADING_MODE_PER_PIXEL`, `rim_enabled = true`, `rim`, `rim_tint`.

One material resource is built per library id and reused across assignments,
so editing a material updates every assigned surface immediately. Toggling
`orm_texture` between empty and set rebuilds that one resource and re-applies
it to every assignment. Texture resources are cached by project-relative path
with a `clear_texture_cache()` hook for tests and texture replacement.

### 8.4 Texture import

`ProjectStore.import_texture(uri, project_dir, fallback_name := "Texture")`:

- Accept `.png`, `.jpg`, `.jpeg`, `.webp`; anything else returns
  "Kinema imports PNG, JPEG and WebP textures."
- Load with `Image.load_from_file(uri)`. A null image returns "This image could
  not be read."
- If the largest side is **≤ 4096 px**, copy the original bytes unchanged to
  `textures/<slug>/<original-name>.<ext>` (unique slug, no overwrite). The
  stored file keeps its extension and encoding. `resized_from` is `""`;
  `width`/`height` are the image dimensions.
- If the largest side exceeds 4096 px, downscale with bilinear filtering to a
  4096 px largest side and save the **downscaled image** as
  `textures/<slug>/<slug>.png`. PNG is mandatory here so alpha and
  normal-map precision survive the re-encode; JPEG/WebP sources are not
  written back in their lossy format. The original file is not kept.
  `resized_from` is `"<original W>x<original H>"` (ASCII `x`) so the UI can say
  "Resized from 8192x4096 to 4096x2048."; `width`/`height` are the stored
  dimensions.
- Return `{ok, rel_path, width, height, resized_from}`; `rel_path` always
  points at the stored file. On any write failure, remove the partial file and
  the per-texture folder before returning the error.
- No `.import` file, no editor import pipeline: the runtime loads the image
  from the project file through the material system.

The native picker filter is `*.png, *.jpg, *.jpeg, *.webp;Images`.

### 8.5 Imported material adoption

When a new glTF/GLB is added (`Document.add_imported`, never on project load):

- Walk every `MeshInstance3D` in the generated model and every surface.
- For each real `StandardMaterial3D`/`BaseMaterial3D`, create one library
  material per unique resource (dedupe by resource instance), named
  `<Model> · <material name or Material N>`.
- Copy the supported scalars and flags (albedo colour, roughness, metallic,
  metallic specular, shading/toon/rim, UV scale/offset, emission).
- Persist supported textures by extracting `Texture2D.get_image()` and saving
  PNGs under `textures/imported/<model-slug>-<n>-<slot>.png`:
  albedo, normal, ORM, roughness, metallic, AO, emission. An imported
  `ORMMaterial3D` keeps its packed ORM map and the adopted record selects
  `ORMMaterial3D`; an imported `StandardMaterial3D` keeps separate maps. If
  `get_image()` returns null (compressed/unsupported), leave that slot empty
  and record a note on the material; the scalar fallback still applies.
- Assign each source surface to its adopted material via
  `part_surface_materials["<part>#<surface>"]`. This preserves per-surface
  differences and makes the material editable/duplicable.
- Cap adoption at 32 materials and 64 textures per import. Beyond that, leave
  the remaining surfaces on their embedded glTF materials and return a
  notice: "Adopted 32 of N materials; the rest keep their embedded
  materials."
- If adoption fails entirely, the generated glTF materials remain untouched
  and the import still works. No loss of the model.

Duplicating an object shares material ids (correct: one library material, many
assignments). Deleting a material never deletes texture files (they may be
shared); the editor reports orphaned files only as a count, it does not
silently clean them.

### 8.6 UI

**Inspector** for a selected mesh or import:

- **Object material** section always appears:
  - Current object material swatch/name or "Legacy colour" for primitives
    without an assignment.
  - `Choose material` (96×44) opens the library sheet; target is the object.
  - `Edit material` (96×44) opens the editor for the resolved object material.
- When the selected part is a `MeshInstance3D`, a **Part material** section
  appears with "Part · <name>", its own `Choose`/`Edit` actions, and — when
  the mesh has more than one surface — a 44 dp row of surface chips
  `All · 0 · 1 · …`. Assignment targets follow the selected chip; `All` means
  the part-level slot (`surface = -1`), `N` means `path#N`.
- When the selected part is not a mesh, show "Part · <name> · No mesh.
  Materials apply at the object level." No part assignment actions are shown,
  and the object section above remains the only target.
- The inspector connects `Document.part_selection_changed` and rebuilds the
  part/surface section. Today it does not, which is why imported part
  selection has no material UI.
- Legacy primitive colour/roughness/metallic controls remain visible only when
  no library material is assigned. Assigning one replaces the legacy look.
  Clearing the assignment restores the legacy fields.

**Material library sheet**:

- Full-width sheet, list of material rows: 44 dp swatch (colour or texture
  thumbnail), name, shading badge, `Assign` 96×44.
- Header actions: `New material` 96×44, `Duplicate` when a row is selected.
- Empty state: "No materials yet. Create one to use textures and shading
  models."
- Tapping a row selects it; double action is explicit, never hidden.
- `Assign` applies to the current inspector target (object/part/surface) and
  closes the sheet.

**Material editor sheet**:

- Name field.
- Shading segmented `PBR` / `Unlit` / `Toon` / `Rim` (4 × 44 dp).
- Base: colour row, albedo texture slot, roughness/metallic scrubs,
  metallic specular.
- Maps: Normal, ORM, Roughness, Metallic, AO, Emission. Each slot is a 44 dp
  row with a 44 dp thumbnail, state text ("None" or file name and dimensions),
  and `Import` / `Replace` / `Clear` actions. Import opens the native picker;
  Replace reuses the slot once a map exists.
- The ORM slot is labelled "ORM (R=AO · G=Roughness · B=Metallic)". When ORM
  is set, the Roughness, Metallic and AO slots are disabled with the exact
  reason "Packed ORM supplies AO, roughness and metallic. Clear ORM to use
  separate maps." Their stored files are not deleted and return when ORM is
  cleared.
- Emission colour + energy.
- UV: scale X/Y and offset X/Y numeric fields.
- Rim: rim strength and tint visible only for `rim`.
- Footer: `Duplicate` (96×44) and `Delete` (96×44, danger, confirmation).
- Missing texture: the slot shows the missing path in `Kit.WARNING` and the
  material keeps rendering with scalars.
- No UVs: if any map is assigned to a part whose mesh has no UV array, show
  "This part has no UVs; a texture will sample a single point." It is a
  warning, not a block.

Colour selection reuses the existing colour sheet. Generalize the editor path
to `open_color_sheet(target, property, current, on_commit)`; the existing
object `color`/`light_color` path becomes one caller. The palette and hex/RGB
controls stay as they are.

### 8.7 Persistence and compatibility

- `Document.FORMAT_VERSION` becomes `3`.
- `to_data()` includes `"materials": material_system.to_data()["materials"]`.
- `_apply_data()` loads materials **before** spawning objects so assignments
  resolve on the first frame.
- `_base_object()` adds `material_id: ""`, `part_materials: {}`,
  `part_surface_materials: {}`; `_normalize_object()` validates them
  (string ids, dictionary of path→id, reject non-string values).
- v1/v2 projects without materials load with an empty library and the legacy
  primitive look. No migration writes files.
- Material ids are `mat_N`; `_next_material_id` is derived on load like the
  rig counters, so duplicate ids cannot collide.
- Undo snapshots include the library because they serialize the whole
  document. Texture files are not versioned or deleted by undo.
- `smoke.gd` contract checks move from format 2 to 3 and assert that the new
  keys are present; a v2 fixture must still load.

### 8.8 Tests (new `tests/materials.gd`)

- Create/update/duplicate/delete material; persistence round-trip; `format` 3
  and the materials array present.
- v2 document load keeps legacy colours and creates no materials.
- Assignment resolution: surface → part → object → legacy; clearing a slot
  falls back correctly; deleting a material clears assignments and re-applies.
- Shading mapping: `pbr` per-pixel, `unlit` unshaded, `toon` toon diffuse and
  specular, `rim` rim enabled. Emission toggles with energy.
- Texture import: an in-cap PNG/JPEG/WebP copies unchanged into the project and
  returns dimensions; unsupported extension and unreadable file return exact
  errors. An oversized image is downscaled to 4096, stored as a new `.png`
  (not re-encoded as JPEG/WebP), returns `resized_from` in `"WxH"` form, and
  leaves no original copy.
- Applying a material sets albedo/normal/emission textures, normal/ao/emission
  flags, UV scale/offset and texture filter/repeat on the real resource.
- ORM: a record with `orm_texture` builds an `ORMMaterial3D` with that map and
  does not apply the separate roughness/metallic/AO maps; clearing ORM builds
  a `StandardMaterial3D` and reapplies the separate maps. Toggling ORM
  re-applies the resource to every assignment.
- Missing texture file falls back to scalars and is reported by
  `missing_textures()`.
- Part targeting: assigning to a real `MeshInstance3D` part and to a valid
  `path#N` surface writes the expected assignment; assigning to a non-mesh
  part or an out-of-range surface returns `false`, sets the exact
  `last_error`, writes nothing, and opens no undo entry.
- Imported adoption: a runtime-built `MeshInstance3D` with two surfaces and a
  `StandardMaterial3D` produces two library entries or one deduped entry as
  appropriate, persists its texture, and assigns both surfaces. An imported
  `ORMMaterial3D` keeps its packed ORM map and adopts as an `ORMMaterial3D`
  record. Adoption never runs on project load.
- Inspector rebuilds on `part_selection_changed` and exposes a surface chip row
  for a multi-surface part; `Choose material` targets the part when a mesh part
  is selected, and shows the object-level target with no part actions when a
  non-mesh part is selected.
- Object visuals: a material-assigned primitive differs materially from the
  legacy primitive (texture/normal flags set), and an unlit material has
  `shading_mode == UNSHADED`.

## 9. Data contract summary

### Document v3

```json
{
  "format": 3,
  "materials": [],
  "objects": [
    {
      "material_id": "",
      "part_materials": {},
      "part_surface_materials": {},
      "rig": "unchanged",
      "pose": "inside rigs"
    }
  ],
  "rigs": [
    {
      "pose": {"bones": {"Bone": {"p": [], "r": [], "s": []}}, "root_position": []}
    }
  ]
}
```

### graphics.json

```json
{
  "risk_enabled": false,
  "risk_boot": "idle",
  "risk_last_error": "",
  "renderer_preference": "mobile",
  "renderer_pending": "",
  "renderer_ready": true
}
```

Missing keys default to the safe values. `risk_boot = "probing"` on a launch is
always treated as a failed previous launch, never as a reason to retry.

## 10. UI and touch rules for new surfaces

- Workspace header/footer: 56 dp; buttons 44 dp; Close 96×44.
- SpeedGraph header: 56 dp; Presets 96×44 (or a 44 dp icon below 420 dp
  column width); every button and menu is at least 44 dp.
- Material rows: 44 dp swatch, 44 dp actions, 96×44 primary.
- Confirmation sheets: destructive primary on the right, Cancel on the left;
  risk "Enable risk" is not styled as destructive (it is an informed opt-in);
  "Restore mobile-safe" is neutral, not red.
- Nothing new uses hover, right-click or a hidden long-press as the only path.
- All new icons exist in `assets/icons` (`maximize`, `image`, `layers`,
  `sparkles`, `chevron-down`, `tool-move`, `tool-rotate`, `copy`, `trash-2`,
  `plus`, `zoom-in`, `zoom-out`).

## 11. Test and gate plan

Per workstream, test-first:

1. Write the failing assertions in the named suite and run them.
2. Implement.
3. Run the suite until green.
4. Self-review and fix (round 1).
5. Hand off; the lead runs the full gate set and returns only real failures
   (round 2).

New suites and scene wrappers:

- `studio/tests/graphics.gd` + `graphics.tscn`
- `studio/tests/timeline_workspace.gd` + `timeline_workspace.tscn`
- `studio/tests/materials.gd` + `materials.tscn`

The gate runner adds them in the same order as the existing suites. Full gate
set:

```text
parse (0 script errors)
smoke
layout (headless)
layout (xvfb)
animation
media
rig
hierarchy
gizmo
environment
object_visuals
graphics
timeline_workspace
materials
```

Test fixtures are generated inside the project or in `user://`; no test may
depend on `/tmp/opencode`. The GLB/glTF fixtures for adoption and external
buffers are built by the test at runtime and cleaned up.

## 12. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Risk-on profile crashes before the probe is written | `probing` is persisted before `apply_all` on enable and at startup before profile application. A write failure leaves the previous safe state. |
| Unrelated crash reverts an accepted risk profile | Accepted: the contract is "reach the editor or return to safe". The settings card explains it and the user can re-enable. |
| Forward+ high-end effects overheat a device | Persistent warning, explicit opt-in, immediate Restore mobile-safe, no default change. Device checklist measures a short session. |
| Timeline reparenting causes layout loops or lost state | Dedicated workspace container, idempotent open/close, parent-order tests, `_workspace_switching` guard, full layout gates under xvfb. |
| Curve baking explodes key count or undo size | Samples capped at 48 per segment; only the selected segment is baked; one edit; undo restores the snapshot. |
| Rotation curve baking produces invalid quaternions | Axis-angle extrapolation with normalized results and finite guards; tests assert finite values and endpoints. |
| Texture memory on mobile | 4096 px cap with downscale notice; oversized files are stored only as the downscaled PNG; adoption caps 32 materials / 64 textures; one shared material resource per library id. |
| Packed ORM silently does nothing | The record selects `ORMMaterial3D` whenever ORM is set; the separate-map slots are disabled with the exact reason; class-switch tests cover set/clear. |
| `.gltf` path traversal or partial imports | Reject absolute/escaping URIs before writing; validate with `append_from_buffer`; delete the destination folder on any failure. |
| FBX expectations remain unmet | Picker accepts it only to show the conversion sheet; the store still refuses it. No pretend import. |
| Imported material textures are compressed and cannot be extracted | Slot left empty with a note; scalars still adopted; original material remains available if adoption fails. |
| Material adoption duplicates textures across imports | Dedupe per import by resource; future cross-import dedupe is out of scope and reported as orphan count only. |
| v3 format breaks older projects | Additive fields, v2 load test, legacy primitive fallback, no file migration. |
| MP4 still fails on a specific codec | The platform gate is fixed and tested; the device checklist verifies a real encode and names the exact MediaCodec failure if one remains. |

## 13. Device verification checklist (user)

Build gate: CI `assembleStandardDebug`, arm64-v8a, `studio.kinema.app`. Only
this APK is device-testable.

1. **MP4**: import an MP4 reference, confirm the proxy frames appear, export
   1080p High, play the MP4 in the gallery and confirm duration, audio and
   seek.
2. **Renderer risk**: open Settings → Graphics, enable high-end Forward+,
   confirm the warning and the unlocked controls (TAA, SSIL, SSR, fog, 8×
   MSAA, 4 cascades, 100 m). Restart into Forward+; confirm the effects and
   the persistent warning. Tap Restore mobile-safe; confirm the clamps return.
   If a boot fails, relaunch and confirm the safe profile and the revert
   message.
3. **Rig import**: import a skinned GLB and an armature-only glTF; confirm the
   "Skeleton detected · N bones" toast, the rig tab, imported rest lock, pose
   rotation with Free/X/Y/Z, pose move, numeric pose fields, key pose with
   rotation/position/scale, undo, save/reload pose.
4. **glTF external buffers**: import a `.gltf` with its `.bin` and textures in
   one folder; confirm the mesh and textures load. Import a `.gltf` with a
   missing `.bin`; confirm the exact error and no half-created object.
5. **FBX**: select an `.fbx`; confirm the conversion sheet and that `Choose
   another file` returns to the picker.
6. **Timeline workspace**: in landscape open Expand; confirm clips/dope left,
   graph right, transport bottom. Edit a key time and value, multi-select,
   copy/paste, add/delete, Fit, pinch zoom. Apply Bounce out and Elastic out;
   confirm the motion and a single undo step. Back closes workspace, then
   drawer/modal ordering. Rotate/resize below 720 × 360; confirm the compact
   fallback.
7. **Materials**: import PNG/JPEG/WebP textures (including one over 4096 px);
   create materials from each preset; switch PBR/Unlit/Toon/Rim; assign to an
   object, an imported mesh part and a surface; assign a packed ORM map and
   confirm the separate roughness/metallic/AO slots disable; confirm
   normal/ORM/emission maps render; select a non-mesh part and confirm no part
   assignment is offered; save/reload and confirm assignments and textures;
   export a still and a video with the material applied.
8. **Legacy project**: open a wave-2 project; confirm it loads, keeps colours,
   and can be upgraded by assigning library materials.

## 14. Non-goals

- Direct texture painting on models, vertex colour painting, or a layer-based
  paint system.
- A shader graph or custom shader editor. Shading models are
  `StandardMaterial3D` presets, with `ORMMaterial3D` only for packed ORM.
- Runtime FBX import. The conversion sheet is the honest path.
- Editing imported skeleton rest transforms or rebinding imported animations.
- Fake Bezier handles or arbitrary curve handles. Transition scalars and baked
  key families are the supported curve model.
- Bone tracks in the dope sheet/speed graph. Rig keys are created and live in
  the animation resource; the rig panel is their editor in wave 3.
- 4K MP4 guarantees on devices that do not advertise 4K.
- Automatic deletion of unused textures.

## 15. Builder-check resolutions

These are builder calls, not product-scope changes. They are recorded here so
the implementation plan can quote one authority.

1. **ORM uses `ORMMaterial3D`.** Godot 4.7.2 exposes `orm_texture` on
   `StandardMaterial3D`, but only `ORMMaterial3D` (constructed with
   `BaseMaterial3D(true)`) generates the ORM shader path. A non-empty
   `orm_texture` therefore selects `ORMMaterial3D`, wins over the separate
   roughness/metallic/AO maps, and disables those slots with an exact reason.
   Clearing ORM returns to `StandardMaterial3D` and re-enables them. No ORM
   unpacking and no fourth "both" behavior.
2. **Compact graph stays in `Timeline`; `SpeedGraph` is workspace-only.**
   Compact keeps its Timeline-owned channel tab strip. Graph mode gets a
   session-only 62% / 300 dp budget so the 120 dp plot floor is real; the
   dope More budget remains 46% / 260 dp.
3. **The workspace graph follows the dope sheet's channel selection.** The
   object is `Document.selected_id`; `Timeline.channel_selected` drives
   `SpeedGraph.set_channel`. The graph has no second channel picker. Key
   selection is graph-local, exposed through `selected_indices()` /
   `select_indices()` / `selection_changed`, and re-resolved by time after
   any track change. `selected_segment()` is the single gate for Easing and
   Curve family.
4. **An oversized texture is stored as the downscaled image.** The original
   is not kept. The stored file is PNG when downscaling (lossless alpha and
   normal-map precision), and the original bytes with their extension when
   within the 4096 px cap. `rel_path` points at the stored file; `width`/
   `height` are stored dimensions; `resized_from` is ASCII `"WxH"` or empty.
5. **A curve family bakes the segment from the selected key to the next key.**
   Exactly one selected key that is not the last key is required.
   `selected_segment()` returns the exact refusal reason otherwise. Easing
   (scalar transition) and Curve family (baked keys) remain two separate
   menus; neither is silently redirected to another segment.
6. **Part materials exist only on real meshes.** `assign_material` /
   `clear_material` return `false` with `last_error = "This part has no mesh
   to shade."` for a non-mesh part, write nothing, and open no undo entry. No
   recursive assignment. The inspector shows the object-level material section
   and no part actions for a non-mesh part. `path#N` is the Nth surface of the
   `MeshInstance3D` at `path`; an out-of-range surface returns `false` with
   `"Surface N is out of range."`

## 16. Approval gate

This document is the implementation contract. Builder-check questions are
resolved above. The next step is `writing-plans`, then four isolated
worktrees on `opencode/deepseek-v4.1-flash-free` with the merge order and
two-round fix limit above. Implementation does not start before explicit
approval.
