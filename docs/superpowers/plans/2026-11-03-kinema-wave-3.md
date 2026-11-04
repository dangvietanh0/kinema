# Kinema Studio Wave 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Android MP4 export reach its MediaCodec backend, add an explicit Forward+ risk switch, adopt imported skeletons with persistent p/r/s poses and precise touch editing, add a landscape timeline workspace with a real key-editing speed graph, and add a project material library with texture maps and PBR/Unlit/Toon/Rim shading.

**Architecture:** Four independent workstreams branch from the same commit and are merged in W1 → W2 → W3 → W4 order. W1 fixes the platform gate and the renderer risk state machine. W2 adds glTF external-resource import, FBX conversion guidance, pose v2, pose transactions and touch transforms. W3 extends `Timeline` for the compact graph budget and adds a workspace overlay with a `SpeedGraph` control. W4 adds `MaterialSystem`, format 3, texture import, adopted materials and the material UI. Shared files are edited only in named sections; the lead resolves merge conflicts.

**Tech Stack:** Godot 4.7.2, GDScript, `Animation`/`Skeleton3D`/`GLTFDocument`/`StandardMaterial3D`/`ORMMaterial3D`, headless and xvfb test scenes, GitHub Actions Android export.

**Spec:** `docs/superpowers/specs/2026-11-03-kinema-wave-3-design.md` (binding).

## Global Constraints

- Touch-first Android 15–17, landscape priority. Every visible target is at least 44 dp; primary actions are 96×44; corners are square; IBM Plex only; achromatic chrome; pure black background; red only for destructive/error states.
- No fake feature. Unavailable controls are disabled with the exact reason from the spec. A Linux headless pass never claims a device-only path is verified.
- No new custom shaders. Shading uses `StandardMaterial3D`, plus `ORMMaterial3D` only when a packed `orm_texture` is set.
- All user-visible copy is English, concise and specific. No lorem, no "coming soon".
- Tests are written first and watched failing. Test fixtures live in the project or `user://`; no test depends on `/tmp/opencode`.
- Worktrees are isolated and branch from the plan commit. Subagents commit locally and never push. The lead merges.
- Builds happen only through GitHub Actions `assembleStandardDebug`, arm64-v8a, CI debug keystore, package `studio.kinema.app`. A local export is not a substitute.
- Every workstream gets at most two fix rounds: one after its own gates, one for failures found by the lead's merge gates. After round two the subagent stops and reports the exact failure.
- The spec's global test floor remains: parse 0, and `smoke`, `layout` (headless + xvfb), `animation`, `media`, `rig`, `hierarchy`, `gizmo`, `environment`, `object_visuals` all PASS. Wave 3 adds `graphics`, `timeline_workspace` and `materials`.
- Out of scope: direct model/texture painting, vertex-colour painting, a shader graph or custom shader editor, runtime FBX import, editing imported rest transforms, fake Bezier handles, bone tracks in the dope sheet/speed graph, 4K MP4 guarantees, and automatic deletion of unused textures. None of these may appear as a stub or a disabled "coming soon" control.

## Review Focus

These are the failure modes the spec implies but no single task owns. Each line is pinned by a test in the task named in parentheses.

1. **Android is `"Android"`, not `"android"`.** MP4 import and export must work on a real device, and the Linux path must still refuse with the exact backend reason. (Task 1)
2. **A risk probe must survive its own crash.** Enabling high-end effects on a mobile Forward+ boot must persist `probing` before any profile is applied; the next launch that reaches the editor proves it, the next launch that does not reverts to safe and says why. Enabling under Mobile must not arm a probe that can never run. (Tasks 2–3)
3. **A `.gltf` and its `.bin` are one import.** A two-file fixture must import and render; a missing sibling must leave no half-created `models/<slug>` folder and must produce the exact "Move the .gltf, its .bin and its textures into one folder" message. (Task 5)
4. **The compact graph must not open as a 24 dp sliver.** At 915×412 graph mode must reach a ≥120 dp plot while dope keeps its wave-2 budget and lanes. A workspace must restore exact parents/order on close and close itself below 720×360. (Tasks 11–13)
5. **ORM and part targeting must be honest.** A non-empty ORM map must select `ORMMaterial3D` and suppress the separate roughness/metallic/AO slots; a non-mesh part must refuse with "This part has no mesh to shade.", write nothing and open no undo entry. (Tasks 15–16)

---

## Binding Shared Interfaces

These names, signatures and data shapes are frozen for the whole wave. A later task may add a helper, but it must not rename or change the meaning of anything here.

### W1 — platform and renderer

```text
AndroidVideo.is_android(platform: String = OS.get_name()) -> bool
AndroidVideo.video_reference_supported(platform: String = OS.get_name()) -> bool

Gfx.risk_enabled: bool
Gfx.risk_boot: String                 # "idle" | "probing" | "proven"
Gfx.risk_last_error: String
Gfx.risk_supported(platform: String = OS.get_name()) -> bool
Gfx.risk_active(platform: String = OS.get_name(), method: String = actual_method()) -> bool
Gfx.risk_profile(platform: String, method: String, enabled: bool) -> Dictionary
Gfx.begin_risk_boot(platform: String, method: String) -> Dictionary
Gfx.enable_risk(platform: String = OS.get_name(), method: String = actual_method()) -> bool
Gfx.disable_risk() -> void
Gfx.confirm_risk_probe() -> void
Gfx.safe_forward_plus_profile(platform := OS.get_name(), actual_method := renderer_name(), risk := risk_enabled) -> Dictionary
Gfx.capabilities_for(method: String, platform: String = OS.get_name(), risk: bool = false) -> Dictionary

SettingsPanel.risk_change_requested(enabled: bool)
SettingsPanel.risk_card_state(platform := OS.get_name(), method := Gfx.actual_method()) -> Dictionary
# {visible, toggle_on, warning, restore_visible, hint, renderer_note}
```

`risk_profile` and `safe_forward_plus_profile` return the same 12 keys: `msaa, taa, ssao, ssil, ssr, glow, volumetric_fog, shadow_quality, shadow_distance, shadow_splits, scale_3d, max_fps`.
`begin_risk_boot` returns `{action, preference, boot, risk_enabled, reason}` where `action` is `"revert"`, `"probe"`, `"clear"` or `"none"`. Its decision table is in Task 2.

### W2 — import, pose and bones

```text
Document.rig_adopted(object_id: String, bone_count: int)
Document.insert_pose_channel(rig_object_id: String, bone: String, channel: String, value: Variant) -> int
Document.insert_pose_keys(rig_object_id: String, pose: Dictionary) -> void

RigSystem.begin_pose_edit(label: String) -> void
RigSystem.end_pose_edit() -> void
RigSystem.set_bone_pose(rig_id: String, bone: String, patch: Dictionary) -> bool
RigSystem.apply_saved_pose(rig_id: String, pose_id: String) -> bool
RigSystem.reset_bone_pose(rig_id: String, bone: String) -> void
RigSystem.reset_all_poses(rig_id: String) -> void

PoseLibrary.capture(skeleton: Skeleton3D, root_node: Node3D) -> Dictionary
# {"bones": {name: {"p": [x,y,z], "r": [x,y,z,w], "s": [x,y,z]}}, "root_position": [x,y,z]}
PoseLibrary.apply(skeleton: Skeleton3D, root_node: Node3D, pose: Dictionary) -> void
PoseLibrary.apply_bones(skeleton: Skeleton3D, pose: Dictionary) -> void

RigToolbar.transform_mode() -> String   # "rotate" | "move"
RigToolbar.axis_mode() -> String        # "free" | "x" | "y" | "z"
RigOverlay.set_transform_mode(mode: String) -> void
RigOverlay.set_axis_mode(axis: String) -> void
```

`channel` is one of `"position"`, `"rotation"`, `"scale"`. Track paths keep the existing `%s/Skeleton3D:%s` form. Legacy quaternion/array pose bones remain readable as rotation-only.

### W3 — timeline and graph

```text
Document.apply_key_edits(id: String, channel: String, edits: Array, label := "Edit keys") -> Dictionary
# edits: [{index:int, time:float, value:Variant, transition:float, delete:bool}]
# index -1 inserts; omitted fields keep current values; indices refer to the pre-edit track
# result {ok, error, indices}
Document.bake_curve_segment(id: String, channel: String, key_index: int, curve_id: String) -> Dictionary
# {ok, inserted, reason, message}

Timeline.channel_selected(channel: String)
Timeline.channel() -> String
Timeline.set_workspace_mode(enabled: bool) -> void

SpeedCurve.SPEED_CURVES: Dictionary          # id -> Callable(t: float) -> float
SpeedCurve.family_ids() -> PackedStringArray
SpeedCurve.family_label(id: String) -> String
SpeedCurve.evaluate(id: String, t: float) -> float

SpeedGraph.setup(document: Node3D) -> void
SpeedGraph.set_context(object_id: String) -> void
SpeedGraph.set_channel(channel: String) -> bool
SpeedGraph.get_channel() -> String
SpeedGraph.selected_indices() -> PackedInt32Array
SpeedGraph.select_indices(indices: PackedInt32Array, additive := false) -> void
SpeedGraph.clear_selection() -> void
SpeedGraph.selected_segment() -> Dictionary
SpeedGraph.selection_changed(indices: PackedInt32Array)
SpeedGraph.set_view(view: String) -> bool   # "value" | "speed"
SpeedGraph.view() -> String
SpeedGraph.commit_key_edit(index: int, time: float, value: Variant = null) -> bool
SpeedGraph.apply_curve_family(curve_id: String) -> Dictionary
SpeedGraph.apply_easing(value: float) -> bool
SpeedGraph.copy_selection() -> void
SpeedGraph.paste_at(time: float) -> bool
SpeedGraph.add_key_at_playhead() -> bool
SpeedGraph.delete_selection() -> void
SpeedGraph.fit() -> void
SpeedGraph.plot_rect() -> Rect2

EditorShell.open_timeline_workspace() -> bool
EditorShell.close_timeline_workspace(restore_focus := true) -> void
EditorShell.timeline_workspace_open() -> bool
```

`selected_segment()` returns exactly `{ok:false, reason:"Select one key."}` for none/multiple, `{ok:false, reason:"The last key has no following segment."}` for the last key, and `{ok:true, start_index, end_index, t0, t1}` otherwise.

### W4 — materials

```text
Document.material_system: MaterialSystem
Document.FORMAT_VERSION := 3
Document.part_selection_changed(object_id, part_path)   # existing signal, now consumed by the inspector

MaterialSystem.signal materials_changed
MaterialSystem.last_error: String
MaterialSystem.setup(document) -> void
MaterialSystem.to_data() -> Dictionary
MaterialSystem.load_data(raw: Dictionary) -> void
MaterialSystem.material_ids() -> PackedStringArray
MaterialSystem.get_material(id: String) -> Dictionary
MaterialSystem.create_material(name := "Material", preset := "matte") -> String
MaterialSystem.duplicate_material(id: String) -> String
MaterialSystem.delete_material(id: String) -> bool
MaterialSystem.update_material(id: String, patch: Dictionary) -> bool
MaterialSystem.can_assign_part(object_id: String, part_path: String) -> bool
MaterialSystem.assign_material(object_id: String, material_id: String, part_path := "", surface := -1) -> bool
MaterialSystem.clear_material(object_id: String, part_path := "", surface := -1) -> bool
MaterialSystem.resolve_assignment(object_id: String, part_path := "", surface := -1) -> String
MaterialSystem.resource_for(material_id: String) -> BaseMaterial3D
MaterialSystem.apply_object(object_id: String) -> void
MaterialSystem.apply_all() -> void
MaterialSystem.adopt_import(object_id: String, generated: Node, model_name: String) -> Dictionary
MaterialSystem.missing_textures() -> Array[String]
MaterialSystem.clear_texture_cache() -> void

ProjectStore.import_texture(uri: String, project_dir: String, fallback_name := "Texture") -> Dictionary
# {ok, rel_path, width, height, resized_from} or {ok:false, error}

EditorShell.open_color_sheet(target: Object, property: String, current: Color, on_commit: Callable) -> void
```

Material record keys are exactly the spec §8.1 keys. Assignment keys are exactly `material_id`, `part_materials`, `part_surface_materials`.

### Measured graph-budget correction

The spec's "62% of stage height → ~131 dp plot at 915×412" was computed against the 480 dp editor height, not the 288 dp stage host measured by the layout probe. The binding outcome in §7.1 is the **120 dp plot floor** at 915×412. Therefore:

- Graph mode gives the **sheet** the stage share: `overlay = FOLDED_TIMELINE + sheet`.
- The graph overlay budget is `min(300.0, stage_height)` and the sheet receives `budget - FOLDED_TIMELINE`. At 915×412 this is a 288 dp overlay, a 232 dp sheet and a 126 dp plot. The 300 dp cap still binds on taller stages.
- Dope keeps the wave-2 budgets exactly: default `min(208, max(104, stage*0.34))`; More `min(260, max(104, stage*0.46))`.
- Graph mode sets `_timeline_more = true`; returning to dope leaves More on, so dope shows its 46% / 260 dp behaviour and lanes. Closing and reopening the sheet resets More to false.
- The compact graph plot top is `ruler 22 + tabs 44 + 12 = 78`; the bottom is `sheet - 28`. The 22 dp stats line is removed from the plot area.
- `graph_plot_rect().size.y >= 120` is asserted at 915×412.

---

## File Structure

| File | Responsibility in this wave |
|---|---|
| `studio/src/core/android_video.gd` | Exact Android platform detection for MP4 import/export. |
| `studio/src/core/media_system.gd` | Route video references through that gate. |
| `studio/src/core/gfx.gd` | Persisted risk state, boot decision, risk-aware profile/capabilities. |
| `studio/src/ui/settings_panel.gd` | Graphics risk toggle, warning card, risk-aware control hints. |
| `studio/src/app/editor.gd` | Risk confirm/restore, import notices, FBX sheet, timeline budget/workspace/back, material sheets and color routing. |
| `studio/src/core/project_store.gd` | `.gltf` external resources and texture import. |
| `studio/src/core/pose_library.gd` | Pose v2 capture/apply/serialize with legacy reads. |
| `studio/src/core/rig_system.gd` | Adoption signal, pose transactions, three-channel bone keys, reset/apply. |
| `studio/src/core/document.gd` | Rig pose/keys, atomic key edits, curve bake, format 3, material owner and assignments. |
| `studio/src/ui/rig_toolbar.gd` | Transform/axis segments. |
| `studio/src/ui/rig_overlay.gd` | Precise rotate/move drags, readout, transaction boundary. |
| `studio/src/ui/rig_panel.gd` | Rest/Pose sections and per-bone reset. |
| `studio/src/core/speed_curve.gd` (new) | Curve-family math shared by the graph and compact presets. |
| `studio/src/ui/speed_graph.gd` (new) | Workspace-only key graph: plot, selection, edits, menus. |
| `studio/src/ui/timeline.gd` | Channel signal/getter, workspace mode, compact graph geometry. |
| `studio/src/core/material_system.gd` (new) | Material records, resources, textures, assignments, adoption. |
| `studio/src/ui/inspector.gd` | Object/part/surface material targets. |
| `studio/src/ui/material_sheet.gd` (new) | Material library list and assignment. |
| `studio/src/ui/material_editor_sheet.gd` (new) | Record editor, map slots, shading, UV, ORM lock. |
| `studio/tests/graphics.gd` + `.tscn` (new) | Risk state, profiles, UI state. |
| `studio/tests/timeline_workspace.gd` + `.tscn` (new) | Curve math, key edits, graph, workspace. |
| `studio/tests/materials.gd` + `.tscn` (new) | Material CRUD, resources, textures, assignment, UI. |
| `studio/tests/media.gd`, `rig.gd`, `layout.gd`, `object_visuals.gd`, `smoke.gd` | Existing suites extended in their owning tasks. |

## Worktree and Merge Protocol

Each workstream starts from the same plan commit. Use one worktree per workstream and never share a working tree between agents.

```bash
git worktree add ../kinema-w1 -b wave3/w1 HEAD
git worktree add ../kinema-w2 -b wave3/w2 HEAD
git worktree add ../kinema-w3 -b wave3/w3 HEAD
git worktree add ../kinema-w4 -b wave3/w4 HEAD
```

Rules:

- A subagent edits only the files named in its task and keeps shared-file diffs inside the named sections.
- A subagent runs its own suite and commits on its branch. It never pushes, rebases onto another workstream, or touches another worktree.
- The lead merges `wave3/w1` → `wave3/w2` → `wave3/w3` → `wave3/w4` into a `wave3/integration` branch.
- Conflicts in `studio/src/core/document.gd`, `studio/src/app/editor.gd`, `studio/src/core/project_store.gd` and `studio/tests/smoke.gd` are resolved by hand, preserving both workstreams' sections. Never "regenerate" a shared file from one branch.
- After each merge, run the full gate set. A failure returns to the owning subagent for round two with the exact log.
- If round two still fails, stop and report. Do not start a third round or swap models.

## Gate Commands

Use the project-local Godot binary. The lead's runner is external tooling; do not commit it.

```bash
GODOT=${GODOT:-/tmp/onyx-godot/Godot_v4.7.2-stable_linux.arm64}
"$GODOT" --headless --path studio res://tests/graphics.tscn
"$GODOT" --headless --path studio res://tests/timeline_workspace.tscn
"$GODOT" --headless --path studio res://tests/materials.tscn
"$GODOT" --headless --path studio res://tests/rig.tscn
"$GODOT" --headless --path studio res://tests/media.tscn
"$GODOT" --headless --path studio res://tests/layout.tscn
```

A suite passes only when its log ends with `SUITE RESULT: PASS` (or the suite's existing `RIG RESULT: PASS` / `MEDIA RESULT: PASS`) and the process exits 0.

---

## W1 — Android MP4 and renderer risk

### Task 1: Android platform gate

**Files:**
- Modify: `studio/src/core/android_video.gd`
- Modify: `studio/src/core/media_system.gd:339-352`
- Test: `studio/tests/media.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `AndroidVideo.is_android(platform := OS.get_name()) -> bool`; `AndroidVideo.video_reference_supported(platform := OS.get_name()) -> bool`.

- [ ] **Step 1: Write the failing gate tests**

Add `_test_android_platform_gate()` to `media.gd` and call it immediately before `_test_android_backend()`.

Assertions:
- `AndroidVideo.is_android("Android")` is `true`.
- `is_android("android")`, `is_android("Linux")`, `is_android("Windows")`, `is_android("")` are `false`.
- `video_reference_supported("Android")` is `true`; `video_reference_supported("Linux")` is `false`.
- `AndroidVideo.new().available()` is `false` on Linux and its reason contains `"Android MediaCodec backend"`.
- `MediaSystem.import_video_reference("user://missing.mp4")` on Linux returns the exact existing refusal when the file exists: create a tiny temporary MP4-named file first so the file-exists check passes.

- [ ] **Step 2: Run the suite to verify it fails**

Run: `"$GODOT" --headless --path studio res://tests/media.tscn`
Expected: FAIL/parse error because `is_android` and `video_reference_supported` do not exist.

- [ ] **Step 3: Implement the gate**

`android_video.gd`:

- Add both static helpers. `is_android` returns `platform == "Android"`; `video_reference_supported` returns `is_android(platform)`.
- Replace both lowercase comparisons in `available()` and `frames_available()` with `is_android()`.
- Keep `REASON` and `FRAMES_REASON` byte-for-byte unchanged.

`media_system.gd`:

- Load the backend script or use `preload("res://src/core/android_video.gd")` and replace `OS.get_name() != "android"` with `not AndroidVideoScript.video_reference_supported()`.
- Keep the exact refusal string.

Audit: `grep -rn '"android"' studio/src` must return no platform gate. A string inside a comment or a path is acceptable only if it is not a platform comparison.

- [ ] **Step 4: Run the suite to verify it passes**

Run: `"$GODOT" --headless --path studio res://tests/media.tscn`
Expected: `MEDIA RESULT: PASS`.

- [ ] **Step 5: Commit**

```bash
git add studio/src/core/android_video.gd studio/src/core/media_system.gd studio/tests/media.gd
git commit -m "fix: match Android platform name in video backend"
```

### Task 2: Renderer risk state machine

**Files:**
- Modify: `studio/src/core/gfx.gd`
- Create: `studio/tests/graphics.gd`
- Create: `studio/tests/graphics.tscn`

**Interfaces:**
- Consumes: `Gfx.renderer_preference`, `Gfx.actual_method()`, `Gfx.save_preferences()`, `Gfx.apply_all()`.
- Produces: `risk_enabled`, `risk_boot`, `risk_last_error`, `risk_supported`, `risk_active`, `begin_risk_boot`, `enable_risk`, `disable_risk`, `confirm_risk_probe`.

- [ ] **Step 1: Create the suite and write the failing state tests**

`graphics.tscn` is a `Control` root with `script = ExtResource("1_graphics")`, matching `rig.tscn`. The script extends `Control`, prints `GRAPHICS OK`/`GRAPHICS FAIL`, ends with `SUITE RESULT: PASS|FAIL` and quits 0/1.

Tests:

- `to_dict()` carries `risk_enabled=false`, `risk_boot="idle"`, `risk_last_error=""` by default.
- `load_preferences()` on a dictionary missing the three keys leaves the safe defaults; an unknown `risk_boot` value normalizes to `"idle"`; `"probing"` survives a reload so startup can act on it.
- `begin_risk_boot("Android", "forward_plus")` with `risk_enabled=true` and `risk_boot="idle"` returns `action="probe"`, `boot="probing"`.
- With `risk_boot="probing"` and `risk_enabled=true` it returns `action="revert"`, `boot="idle"`, `risk_enabled=false`, non-empty reason containing `"previous launch did not reach the editor"`.
- With `risk_boot="probing"` and `risk_enabled=false` it returns `action="clear"`, `boot="idle"`, empty reason.
- With `risk_enabled=true` and method `"mobile"` it returns `action="none"`, `boot="idle"` (no probe).
- `risk_supported("Android")` and `("iOS")` are true; `("Linux")` false.
- `risk_active("Android", "forward_plus")` is true only when the switch is enabled and supported.
- `enable_risk("Android", "forward_plus")` serializes `risk_boot="probing"` before any apply, returns true, and `confirm_risk_probe()` moves it to `"proven"`.
- `enable_risk("Android", "mobile")` serializes `risk_boot="idle"`.
- `disable_risk()` serializes `risk_enabled=false`, `risk_boot="idle"` and leaves `risk_last_error` untouched so the settings card can still explain a previous revert.
- `mark_renderer_ready()` promotes `"probing"` to `"proven"`.

- [ ] **Step 2: Run the suite to verify it fails**

Run: `"$GODOT" --headless --path studio res://tests/graphics.tscn`
Expected: FAIL/parse error for the missing members.

- [ ] **Step 3: Implement the state machine**

Add the three fields next to the existing renderer fields. Add them to `to_dict()` and normalize them in `load_preferences()`.

Startup order in `_ready()`, before `apply_globals()` runs indirectly:

1. `load_preferences()`.
2. Sanitize the renderer preference exactly as today.
3. Adopt the platform default when the preference is empty.
4. `var decision := begin_risk_boot(OS.get_name(), actual_method())`.
5. Apply `risk_enabled`, `risk_boot` and `risk_last_error` from the decision; save when `action != "none"`.
6. Continue to the existing profile application.

`begin_risk_boot` is pure and reads the live fields:

```text
if risk_boot == "probing":
    if risk_enabled: revert -> risk_enabled=false, boot=idle, reason="High-end Forward+ effects were reverted because the previous launch did not reach the editor."
    else: clear -> boot=idle, reason=""
elif risk_enabled and risk_supported(platform) and method == "forward_plus":
    probe -> boot=probing, reason=""
else:
    none -> boot=idle, reason=""
```

`enable_risk(platform, method)`:

- Return `false` when `risk_supported(platform)` is false.
- Set `risk_enabled=true`, `risk_last_error=""`.
- Set `risk_boot="probing"` only when `platform` is mobile and `method == "forward_plus"`; otherwise `"idle"`.
- Save. Call `apply_all()` only when the arguments match the live platform/method, so pure tests do not touch globals.
- Return `true`.

`disable_risk()` sets `risk_enabled=false`, `risk_boot="idle"`, saves and calls `apply_all()`.

`confirm_risk_probe()` promotes `"probing"` to `"proven"` and saves.

`mark_renderer_ready()` also promotes `"probing"` to `"proven"` before its existing save.

- [ ] **Step 4: Run the suite to verify it passes**

Run: `"$GODOT" --headless --path studio res://tests/graphics.tscn`
Expected: `SUITE RESULT: PASS`.

- [ ] **Step 5: Commit**

```bash
git add studio/src/core/gfx.gd studio/tests/graphics.gd studio/tests/graphics.tscn
git commit -m "feat: persist renderer risk probe state"
```

### Task 3: Risk-aware profiles and capabilities

**Files:**
- Modify: `studio/src/core/gfx.gd:228-278`
- Test: `studio/tests/graphics.gd`

**Interfaces:**
- Consumes: Task 2's fields.
- Produces: `risk_profile`, the extended `safe_forward_plus_profile`, the extended `capabilities_for`.

- [ ] **Step 1: Write the failing profile tests**

Assertions:

- `risk_profile("Android", "forward_plus", false)` matches every wave-2 clamp: `taa=false`, `ssil=false`, `ssr=false`, `volumetric_fog=false`, `msaa <= 1`, `scale_3d <= 0.85`, `shadow_quality <= 2`, `shadow_distance <= 40.0`, `shadow_splits <= 2`, `max_fps <= 60`.
- With a stored maximum (`msaa=3`, TAA/SSIL/SSR/fog on, `scale_3d=1.0`, `shadow_quality=3`, distance `100`, splits `4`, `max_fps=120`), `risk_profile("Android", "forward_plus", true)` returns exactly those maxima.
- `risk_profile("Linux", "forward_plus", false)` and `risk_profile("Linux", "forward_plus", true)` are equal and equal the stored values.
- `risk_profile("Android", "mobile", true)` returns the stored values and does not report a Forward+ unlock.
- `capabilities_for("forward_plus", "Android", false)` keeps the mobile caps and `risk_unlocked=false`.
- `capabilities_for("forward_plus", "Android", true)` returns `ssil/ssr/taa/volumetric_fog=true`, `msaa_cap=3`, `scale_3d_cap=1.0`, `shadow_quality_cap=3`, `max_fps_cap=120`, `mobile_safe=true`, `risk_unlocked=true`, `risk_reason="High-end effects are on. Stability is not guaranteed."`.
- `capabilities_for("forward_plus", "Linux", true)` and `(..., false)` are identical.
- `safe_forward_plus_profile("Android", "forward_plus", false)` delegates to the disabled profile; `(..., true)` delegates to the enabled profile.

- [ ] **Step 2: Run the suite to verify it fails**

Run: `"$GODOT" --headless --path studio res://tests/graphics.tscn`
Expected: FAIL for the missing `risk_profile` and third arguments.

- [ ] **Step 3: Implement the profiles**

`risk_profile(platform, method, enabled)`:

- Start from the 12 stored values.
- If `method != "forward_plus"` or the platform is not Android/iOS, return them unchanged.
- When `enabled` is false, apply the wave-2 clamps exactly.
- When `enabled` is true, apply only the hard maxima: `msaa <= 3`, `scale_3d <= 1.0`, `shadow_quality <= 3`, `shadow_distance <= 100.0`, `shadow_splits <= 4`, `max_fps <= 120`; leave TAA/SSIL/SSR/fog as stored.

`safe_forward_plus_profile` becomes a one-line delegate to `risk_profile(platform, actual_method, risk)`.

`capabilities_for` gains the third `risk: bool = false` argument and appends `risk_unlocked` and `risk_reason`. The unlock applies only when `forward and mobile and risk`; desktop stays exactly as today.

- [ ] **Step 4: Run the suite to verify it passes**

Run: `"$GODOT" --headless --path studio res://tests/graphics.tscn`
Expected: `SUITE RESULT: PASS`.

- [ ] **Step 5: Commit**

```bash
git add studio/src/core/gfx.gd studio/tests/graphics.gd
git commit -m "feat: unlock mobile Forward+ profile behind the risk switch"
```

### Task 4: Graphics risk UI and editor wiring

**Files:**
- Modify: `studio/src/ui/settings_panel.gd:446-605`
- Modify: `studio/src/app/editor.gd:3433-3470`
- Test: `studio/tests/graphics.gd`

**Interfaces:**
- Consumes: Task 2/3 APIs.
- Produces: `SettingsPanel.risk_change_requested(enabled)`; `SettingsPanel.risk_card_state(platform, method) -> Dictionary`; editor confirmation and restore handlers.

- [ ] **Step 1: Write the failing UI-state tests**

Assertions on `SettingsPanelScript.new().risk_card_state(...)`:

- On `("Android", "forward_plus")` with risk disabled: `visible=true`, `toggle_on=false`, `restore_visible=false`, `hint="Clamped on Android Forward+ for stability."`, `renderer_note` unchanged.
- With risk enabled on Forward+: `toggle_on=true`, `restore_visible=true`, `hint="High-end · risk accepted"`, `warning` contains `"High-end effects are on. Stability is not guaranteed."`.
- With risk enabled on `"mobile"`: `warning` is `"High-end effects apply when Forward+ is running."`, `renderer_note="Experimental on Android: high-end effects follow your risk setting."`.
- With a non-empty `risk_last_error`, the warning contains that exact text. The built label uses `Kit.WARNING`; the helper returns the text only.
- On `("Linux", "forward_plus")`: `visible=false` and no warning.
- The sheet copy is exact: title `"Enable high-end Forward+ effects?"`, body `"Kinema will run the real Forward+ feature set. Some Android GPUs crash or overheat with these effects. If the next launch fails to reach the editor, Kinema returns to the mobile-safe profile automatically."`, actions `Cancel` and `Enable risk`. `Enable risk` is not destructive; `Restore mobile-safe` is neutral.

- [ ] **Step 2: Run the suite to verify it fails**

Run: `"$GODOT" --headless --path studio res://tests/graphics.tscn`
Expected: FAIL for the missing helper and signal.

- [ ] **Step 3: Implement the panel state and controls**

Add `signal risk_change_requested(enabled: bool)` above the existing signals.

`risk_card_state(platform, method)` returns the six documented keys, reading `Gfx.risk_enabled`, `Gfx.risk_last_error`, `Gfx.risk_supported(platform)` and `Gfx.risk_active(platform, method)`. It is the single source for both the tests and `_graphics()`.

In `_graphics()`, above Quality preset and only when `state.visible`:

- A 44 dp toggle row named `RiskToggle`, title `"High-end Forward+ effects"`, caption `"Accept the risk of disabling the mobile-safe clamp"`. The whole row is tappable; toggling on emits `risk_change_requested(true)` and does not flip the visual state until the editor confirms.
- When enabled, a warning card named `RiskCard` with the exact warning text and a 96×44 `Restore mobile-safe` button that emits `risk_change_requested(false)`. Do not style it red.
- Clamped rows read the risk-aware capabilities: 4×/8× MSAA, TAA, SSIL, SSR, fog, Ultra shadows, 4 cascades, 60/100 m, 100% 3D scale. Their hint is `"High-end · risk accepted"` when unlocked.
- The renderer entry note uses `state.renderer_note`.

In `editor.gd`:

- Connect `panel.risk_change_requested` to `_on_settings_risk_change`.
- Enabling opens a modal via `_overlay.show_modal` with the exact copy and `Cancel` / `Enable risk` actions. `Enable risk` is `primary` and not `destructive`.
- The confirm callback calls `Gfx.enable_risk()`, awaits `RenderingServer.frame_post_draw`, calls `Gfx.confirm_risk_probe()`, shows a toast `"High-end Forward+ effects enabled"` and reopens Graphics settings.
- Cancel reopens Graphics settings.
- Restore calls `Gfx.disable_risk()`, reopens Graphics settings and toasts `"Mobile-safe graphics restored"`.
- Both handlers are no-ops when `Gfx.risk_supported()` is false.

- [ ] **Step 4: Run the suite to verify it passes**

Run: `"$GODOT" --headless --path studio res://tests/graphics.tscn`
Expected: `SUITE RESULT: PASS`.

- [ ] **Step 5: Commit**

```bash
git add studio/src/ui/settings_panel.gd studio/src/app/editor.gd studio/tests/graphics.gd
git commit -m "feat: add explicit Forward+ risk controls"
```

---

## W2 — Import and rig workbench

### Task 5: glTF external buffers and textures

**Files:**
- Modify: `studio/src/core/project_store.gd:145-217`
- Test: `studio/tests/rig.gd`

**Interfaces:**
- Consumes: `GLTFDocument.append_from_buffer(bytes, base_path, state)`.
- Produces: `.gltf` imports with sibling `.bin`/image files; missing-sibling refusal with the exact message.

- [ ] **Step 1: Write the failing import tests**

In `rig.gd`, add `_test_gltf_external_buffers()` after `_test_imported_adoption()`.

Build a minimal two-file glTF fixture at runtime in `_tmp_dir`:

- A `.gltf` JSON with one buffer whose `uri` is `"mesh.bin"`, one mesh primitive, one node and one scene.
- A `mesh.bin` containing the little-endian positions/indices the glTF describes.
- A second variant referencing `"missing.bin"`.
- A third with `uri: "../escape.bin"`.

Assertions:

- The valid fixture imports with `ok=true`; `rel_path` is `models/<slug>/<name>.gltf`; both the `.gltf` and `mesh.bin` exist under that folder.
- A `Document.add_imported(rel_path, "Gltf")` spawns a node whose generated tree contains a `MeshInstance3D` with a non-null mesh.
- The missing fixture returns `ok=false` and exactly `"This .gltf references files that are not next to it. Move the .gltf, its .bin and its textures into one folder, or export a .glb."`; no `models/<slug>` folder exists afterwards.
- The escaping fixture returns `ok=false`, writes nothing, and does not read outside the source folder.
- A `data:` URI is skipped and does not create a file.
- `Store.import_model` still accepts a `.glb` and an `.obj` exactly as before.

- [ ] **Step 2: Run the suite to verify it fails**

Run: `"$GODOT" --headless --path studio res://tests/rig.tscn`
Expected: FAIL because the external-buffer import returns the old "export as .glb" error.

- [ ] **Step 3: Implement the `.gltf` path**

In `import_model`, route `kind == "gltf"` to a new `_import_gltf(uri, bytes, project_dir, base_name)`. Keep the `.glb`/`.obj` paths unchanged and keep the FBX rejection exact.

`_import_gltf`:

1. Parse the JSON; reject invalid JSON with the existing parse error.
2. Collect `buffers[].uri` and `images[].uri`; skip empty and `data:` URIs.
3. Reject absolute paths and any path whose `simplify_path()` escapes the source folder. Use a new error: `"This .gltf references a file outside its folder. Export it as a .glb or keep every file in one folder."`
4. Validate with `GLTFDocument.append_from_buffer(bytes, uri.get_base_dir(), state)` and `generate_scene(state)`. Free the generated node.
5. Create a unique `models/<slug>` folder; copy the `.gltf` and every referenced file, preserving their relative paths. Validate every target stays inside the destination folder.
6. On any failure, recursively delete the destination folder and return the exact missing-sibling error when a referenced file is absent.
7. Return `{ok, rel_path, name, extension}` with `rel_path = "models/<slug>/<file>.gltf"`.

Do not copy an unvalidated model. Do not leave a partial folder.

- [ ] **Step 4: Run the suite to verify it passes**

Run: `"$GODOT" --headless --path studio res://tests/rig.tscn`
Expected: `RIG RESULT: PASS`.

- [ ] **Step 5: Commit**

```bash
git add studio/src/core/project_store.gd studio/tests/rig.gd
git commit -m "feat: import glTF external buffers and textures"
```

### Task 6: FBX conversion sheet and skeleton adoption notice

**Files:**
- Modify: `studio/src/app/editor.gd:2328-2365`
- Modify: `studio/src/core/document.gd` (`rig_adopted` signal, `setup`)
- Modify: `studio/src/core/rig_system.gd:1492-1537`
- Test: `studio/tests/rig.gd`

**Interfaces:**
- Consumes: `RigSystem.adopt_imported_skeleton`, `Document.imported_scene_ready`.
- Produces: `Document.rig_adopted(object_id, bone_count)`; `EditorShell.fbx_conversion_copy() -> Dictionary`; `EditorShell.model_picker_filters() -> PackedStringArray`.

- [ ] **Step 1: Write the failing tests**

Assertions:

- `EditorShell.fbx_conversion_copy()` returns exactly:
  - title `"FBX needs a conversion"`;
  - body `"Godot's FBX importer only exists in the editor, so it cannot run on Android. Convert the model to glTF 2.0 first."`;
  - four steps: open in Blender; File → Export → glTF 2.0; choose glTF Binary (`.glb`); import the `.glb` in Kinema;
  - actions `Choose another file` (primary) and `Cancel`.
- `EditorShell.model_picker_filters()` contains `"*.fbx"` and still contains `"*.glb"`, `"*.gltf"` and `"*.obj"`.
- `Store.import_model("user://x.fbx", ...)` still returns the existing FBX rejection string.
- `Document.rig_adopted` exists. Importing the skinned GLB fixture emits it once with the real bone count. Importing an armature-only glTF fixture emits it once. Loading the saved project into a new document does not emit it.
- An import with no skeleton emits nothing.
- The editor toast copy is `"Skeleton detected · <N> bones · Pose mode is ready."` No modal is shown.

- [ ] **Step 2: Run the suite to verify it fails**

Run: `"$GODOT" --headless --path studio res://tests/rig.tscn`
Expected: FAIL for the missing signal/helpers.

- [ ] **Step 3: Implement the import surfaces**

`rig_system.gd`: after a successful adoption and after the rig record is appended, emit `_document.rig_adopted.emit(object_id, bones.size())` once. Because `adopt_imported_skeleton` returns early when a rig already exists and is connected only to `imported_scene_ready`, load and undo cannot re-emit it.

`document.gd`: declare `signal rig_adopted(object_id: String, bone_count: int)` next to `imported_scene_ready`.

`editor.gd`:

- Add the two static helpers. `_pick_model()` uses `model_picker_filters()`.
- `_on_model_selected` checks the extension. For `.fbx`, do not call `Store.import_model`; call `_show_fbx_conversion_sheet()`.
- The sheet uses `fbx_conversion_copy()` and a `Choose another file` action that reopens `_pick_model()`.
- Connect `doc.rig_adopted` to a toast with the exact copy. Do this in the same setup path that connects the other document signals, and disconnect/rebind when the document is replaced.
- Keep the existing imported rest lock note in the rig toolbar and panel unchanged.

- [ ] **Step 4: Run the suite to verify it passes**

Run: `"$GODOT" --headless --path studio res://tests/rig.tscn`
Expected: `RIG RESULT: PASS`.

- [ ] **Step 5: Commit**

```bash
git add studio/src/app/editor.gd studio/src/core/document.gd studio/src/core/rig_system.gd studio/tests/rig.gd
git commit -m "feat: add FBX conversion sheet and skeleton adoption notice"
```

### Task 7: Pose v2 and persistence

**Files:**
- Modify: `studio/src/core/pose_library.gd`
- Modify: `studio/src/core/rig_system.gd:47-130, 1344-1431`
- Test: `studio/tests/rig.gd`

**Interfaces:**
- Consumes: `Skeleton3D` p/r/s APIs.
- Produces: the pose v2 shape in the shared interfaces; rig JSON top-level `pose`.

- [ ] **Step 1: Write the failing pose tests**

Assertions:

- `PoseLibrary.capture` writes `{p,r,s}` arrays for every bone and `root_position`.
- `PoseLibrary.apply` restores p/r/s on a skeleton, and the root node position.
- A legacy pose `{bones: {Hip: [0,0,0,1]}}` applies the rotation and leaves p/s at their current values; it does not throw.
- `RigSystem.to_data()` includes a top-level `"pose"` for every rig. `load_data()` restores the pose after rebuilding the skeleton, inside the loading guard, with no history entry.
- Save → new document → load → the skeleton's p/r/s match the saved values.
- A pose drag that changes a bone creates exactly one undo entry; `undo()` restores the start pose. A zero-movement drag creates no entry.
- `root_position` never overwrites the document object's transform on load; it is applied only by an explicit pose apply.
- `PoseLibrary.apply_bones` applies only the bone p/r/s and leaves the root node untouched.

- [ ] **Step 2: Run the suite to verify it fails**

Run: `"$GODOT" --headless --path studio res://tests/rig.tscn`
Expected: FAIL because capture stores only quaternions and rig JSON has no `pose`.

- [ ] **Step 3: Implement pose v2**

`pose_library.gd`:

- `capture` returns the new shape. Use `PoseLibrary.vec3_to_array`, `quat_to_array` and the existing array converters.
- `apply_bones` reads a bone value as a dictionary when it has `p`/`r`/`s`; otherwise as a legacy quaternion array or `Quaternion`. Missing p/s leave the current skeleton value.
- `apply` calls `apply_bones` and then applies `root_position`.
- Keep `serialize()`/`deserialize()` accepting both shapes and never rejecting a legacy file.
- Keep `root_position` on the record but have `load_data` call `apply_bones`, never `apply`, so a saved pose cannot move the object root.

`rig_system.gd`:

- `_rig_to_json` captures the live skeleton pose when the node exists; otherwise it keeps `rig["pose"]`.
- `_rig_from_json` stores `raw["pose"]` on the rig record.
- `load_data` applies the stored pose after `_build_skeleton`, while `_loading` is true, without opening an edit.
- `save_pose` stores the v2 bone map; `apply_pose` uses `PoseLibrary.apply`.

- [ ] **Step 4: Run the suite to verify it passes**

Run: `"$GODOT" --headless --path studio res://tests/rig.tscn`
Expected: `RIG RESULT: PASS`.

- [ ] **Step 5: Commit**

```bash
git add studio/src/core/pose_library.gd studio/src/core/rig_system.gd studio/tests/rig.gd
git commit -m "feat: persist full bone poses"
```

### Task 8: Pose transactions, autokey and three-channel bone keys

**Files:**
- Modify: `studio/src/core/document.gd:1940-2016`
- Modify: `studio/src/core/rig_system.gd:1344-1431, 1584-1598`
- Modify: `studio/src/ui/rig_overlay.gd:399-430`
- Test: `studio/tests/rig.gd`

**Interfaces:**
- Consumes: Task 7's pose shape.
- Produces: `Document.insert_pose_channel`, the extended `Document.insert_pose_keys`, `RigSystem.begin_pose_edit` / `end_pose_edit` / `set_bone_pose` / `apply_saved_pose` / `reset_bone_pose` / `reset_all_poses`.

- [ ] **Step 1: Write the failing transaction tests**

Assertions:

- `Document.insert_pose_channel` creates one position, rotation or scale track at `current_time`; a second call at the same time updates the key instead of duplicating it.
- `Document.insert_pose_keys` with `{bones: {Hip: {p,r,s}}}` writes all three track types for `Hip` at the same time. A legacy quaternion map still writes rotation only.
- `RigSystem.set_bone_pose` changes only the supplied `p`/`r`/`s` keys and leaves the others untouched.
- Autokey on: `set_bone_pose(rig, bone, {"r": q})` inserts only a rotation key; `{"p": v, "s": s}` inserts position and scale keys. At an existing time it updates.
- Autokey off: `set_bone_pose` changes the live skeleton but writes no keys.
- `apply_saved_pose` is one undo entry and applies autokey when enabled.
- `reset_bone_pose` and `reset_all_poses` use the same transaction and autokey path.
- `key_pose` writes rotation, position and scale for every bone in one undo entry. `undo()` returns the previous key counts.
- A pose drag opens one transaction; a zero-movement tap opens none.
- `Document.insert_bone_key`, `get_bone_keys`, `sample_bone` and `delete_bone_key` keep their rotation-only behaviour.

- [ ] **Step 2: Run the suite to verify it fails**

Run: `"$GODOT" --headless --path studio res://tests/rig.tscn`
Expected: FAIL for the missing pose APIs and the rotation-only tracks.

- [ ] **Step 3: Implement the transaction and key paths**

`document.gd`:

- Add `_bone_track_typed(rig_object_id, bone, type, create)`. Keep `_bone_track` as the rotation wrapper.
- Add `insert_pose_channel(rig_object_id, bone, channel, value) -> int`:
  - `position` → `Animation.TYPE_POSITION_3D`, `position_track_insert_key`;
  - `rotation` → `TYPE_ROTATION_3D`, `rotation_track_insert_key`, normalize the quaternion;
  - `scale` → `TYPE_SCALE_3D`, `scale_track_insert_key`.
  - Use `track_find_key(track, current_time, Animation.FIND_MODE_EXACT)` to update an existing key; otherwise insert.
  - Emit `keyframes_changed` once per call only when a key changed.
- `insert_pose_keys` accepts `{bones: {...}}` or a bare bone map. A dictionary value with `p`/`r`/`s` writes all three channels; a quaternion/array value writes rotation only.
- Keep `insert_bone_key` delegating to the rotation channel.

`rig_system.gd`:

- Add `begin_pose_edit(label)` / `end_pose_edit()` delegating to `_begin`/`_end`.
- `set_bone_pose(rig_id, bone, patch) -> bool` finds the skeleton, captures the current p/r/s, applies the supplied keys, then, when `doc.autokey`, calls `insert_pose_channel` for exactly the changed channels. Return false when the rig/bone/skeleton is missing.
- `apply_saved_pose` wraps `PoseLibrary.apply` in one transaction, applies autokey for every bone, and emits rigs.
- `reset_bone_pose` / `reset_all_poses` set p=0/r=identity/s=1 through the same path. Keep `reset_pose(rig_id, bone_name := "")` delegating to them.
- `key_pose` uses `PoseLibrary.capture`, calls `insert_pose_keys` inside one transaction, and returns false when there is no skeleton.
- The overlay `_begin_drag` calls `rig_system.begin_pose_edit("Pose bone")`; `_rotate_drag` computes from the captured start and calls `set_bone_pose`; `_end_drag` calls `end_pose_edit`. On cancel, restore the captured start through `set_bone_pose` before closing.

- [ ] **Step 4: Run the suite to verify it passes**

Run: `"$GODOT" --headless --path studio res://tests/rig.tscn`
Expected: `RIG RESULT: PASS`.

- [ ] **Step 5: Commit**

```bash
git add studio/src/core/document.gd studio/src/core/rig_system.gd studio/src/ui/rig_overlay.gd studio/tests/rig.gd
git commit -m "feat: make pose edits and bone keys transactional"
```

### Task 9: Touch transform/axis editing and the Rest/Pose panel

**Files:**
- Modify: `studio/src/ui/rig_toolbar.gd`
- Modify: `studio/src/ui/rig_overlay.gd`
- Modify: `studio/src/ui/rig_panel.gd`
- Test: `studio/tests/rig.gd`

**Interfaces:**
- Consumes: Task 8's `set_bone_pose` and transactions.
- Produces: toolbar transform/axis state, overlay setters, the Rest/Pose panel sections and per-bone reset.

- [ ] **Step 1: Write the failing touch tests**

Assertions:

- The toolbar has a 44 dp Transform segment (`Rotate`/`Move`) and a 44 dp Axis segment (`Free`/`X`/`Y`/`Z`). `transform_mode()` defaults to `"rotate"`; `axis_mode()` defaults to `"free"`.
- Imported rigs keep Edit/Add disabled and Transform/Axis enabled in Pose.
- Axis-locked rotation changes only the selected local axis within `0.001`; the other two axes stay at the start value.
- Axis-locked move changes only that world axis.
- Free move translates the active bone and does not rotate it.
- The live readout appears during a drag and disappears on release; its text is degrees for rotation and units for move.
- One gesture creates one undo entry.
- The rig panel has separate `Rest` and `Pose` sections. On an imported rig, Rest p/r/s/length/influence are disabled with the existing note; Pose p/r/s fields are enabled.
- A Pose field commit goes through `set_bone_pose` in one transaction and applies autokey.
- Each bone has a 96×44 `Reset pose` action; reset-all remains.
- The panel's existing key buttons keep their labels and show the caption `"Rotation, position and scale"`.

- [ ] **Step 2: Run the suite to verify it fails**

Run: `"$GODOT" --headless --path studio res://tests/rig.tscn`
Expected: FAIL for the missing segments, setters and panel fields.

- [ ] **Step 3: Implement the toolbar, overlay and panel**

`rig_toolbar.gd`:

- Add two segmented groups with the exact labels and 44 dp targets.
- Emit `transform_mode_changed(mode)` and `axis_mode_changed(axis)`; expose `transform_mode()` and `axis_mode()`.
- On imported rigs, keep Edit/Add disabled with the exact imported note.

`rig_overlay.gd`:

- Add `set_transform_mode` / `set_axis_mode`.
- Rotate Free: keep the current camera-relative yaw/pitch, but compute from the captured start rotation and commit through `set_bone_pose`.
- Rotate X/Y/Z: build the delta around the bone's local axis converted to world for the camera-facing sign; ignore the other screen delta; sensitivity `0.012` rad/px, clamped to ±π per gesture.
- Move Free: translate in the camera right/up plane, scaled by bone world length and camera distance; snap `0.01` when `doc.snap`.
- Move X/Y/Z: project the screen delta onto that world axis.
- Show the readout near the active bone during a drag; hide it on release.
- Keep the 22 dp hit radius and handles. Never write the skeleton directly.

`rig_panel.gd`:

- Split the bone inspector into `Rest` and `Pose` sections. Rest keeps the existing fields and lock note.
- Pose adds nine 44 dp rows (p/r/s). Each commit calls `set_bone_pose` in one transaction.
- Add the per-bone `Reset pose` 96×44 action and keep reset-all.
- Move the imported note directly above Rest and state that Pose/IK still work.
- Refresh values from the skeleton after each edit without rebuilding the whole panel.

- [ ] **Step 4: Run the suite to verify it passes**

Run: `"$GODOT" --headless --path studio res://tests/rig.tscn`
Expected: `RIG RESULT: PASS`.

- [ ] **Step 5: Commit**

```bash
git add studio/src/ui/rig_toolbar.gd studio/src/ui/rig_overlay.gd studio/src/ui/rig_panel.gd studio/tests/rig.gd
git commit -m "feat: add precise touch pose transform and axis controls"
```

---

## W3 — Timeline workspace and speed graph

### Task 10: SpeedCurve math and atomic key edits

**Files:**
- Create: `studio/src/core/speed_curve.gd`
- Modify: `studio/src/core/document.gd` (new key-edit helpers)
- Create: `studio/tests/timeline_workspace.gd`
- Create: `studio/tests/timeline_workspace.tscn`

**Interfaces:**
- Consumes: `Document.get_track`, `get_channel_keys`, `sample_channel`, `begin_edit`/`end_edit`.
- Produces: `SpeedCurve` and the two `Document` key-edit helpers in the shared interfaces.

- [ ] **Step 1: Create the suite and write the failing math/edit tests**

`timeline_workspace.tscn` follows `rig.tscn`'s root pattern. The script extends `Control`, prints `TIMELINE OK`/`TIMELINE FAIL`, ends with `SUITE RESULT: PASS|FAIL`.

Assertions:

- `SpeedCurve.evaluate(id, 0.0) == 0.0` and `evaluate(id, 1.0) == 1.0` for every id.
- Every sampled value for `t` in `[0, 0.05, …, 1.0]` is finite.
- Bounce overshoot stays within the standard bounce bounds; elastic and back produce real overshoot (some value outside `[0,1]` for the out variants).
- `SpeedCurve.family_ids()` contains exactly the 14 ids from the spec table and `family_label` returns the family name.
- `Document.apply_key_edits` retimes one key, changes one value, inserts at `-1`, deletes, and applies a multi-key move; the result is sorted by time and `indices` points at the edited keys.
- Four edits in one call open exactly one undo entry; `undo()` restores the original time/value/count.
- `Document.bake_curve_segment` on a one-key selection bakes the selected→next segment:
  - inserted count is `clamp(round((t1-t0)*fps), 8, 48) - 1`;
  - endpoints keep their original values;
  - inserted transition is `1.0`;
  - one undo entry restores the original key count and values;
  - every value is finite and a rotation bake produces normalized quaternions.
- A segment shorter than two frames inserts exactly one midpoint and returns the exact message `"Segment is shorter than two frames; baked one midpoint."`

- [ ] **Step 2: Run the suite to verify it fails**

Run: `"$GODOT" --headless --path studio res://tests/timeline_workspace.tscn`
Expected: FAIL for the missing files/APIs.

- [ ] **Step 3: Implement the curve math and atomic edits**

`speed_curve.gd`:

- `SPEED_CURVES` maps the 14 ids to callables (static helpers or lambdas).
- Bounce uses the 7.5625/2.75 piecewise curve.
- Elastic uses `2^(-10t) · sin(...) + 1`.
- Back uses the 1.70158 overshoot constants.
- Spring is a normalized damped cosine.
- Sine/Expo are the standard Penner curves.
- `evaluate` clamps `t` to `[0,1]` and returns `0.0` for an unknown id.

`document.gd`:

- `apply_key_edits(id, channel, edits, label)` snapshots the current track keys `{time, value, transition}`, applies each edit by its original index (or inserts when `index < 0`), sorts by time, then rebuilds the track in one `begin_edit`/`end_edit`. Preserve the track interpolation type. Return `{ok, error, indices}`; an out-of-range edit returns `ok=false` and writes nothing.
- `bake_curve_segment(id, channel, key_index, curve_id)` validates the channel/key, takes `t0/t1/v0/v1`, computes `n = clampi(int(round((t1-t0)*fps)), 8, 48)`, builds insert edits at `u/n` with `SpeedCurve.evaluate`, and calls `apply_key_edits` once. For position/scale use `v0.lerp(v1, f)`; for rotation use axis-angle extrapolation scaled by `f` and normalize; for other types use numeric lerp. Inserted keys use transition 1.0. If the segment is shorter than two frames, insert one midpoint and return the exact message `"Segment is shorter than two frames; baked one midpoint."` The result includes `{ok, inserted, reason, message}`.

- [ ] **Step 4: Run the suite to verify it passes**

Run: `"$GODOT" --headless --path studio res://tests/timeline_workspace.tscn`
Expected: `SUITE RESULT: PASS`.

- [ ] **Step 5: Commit**

```bash
git add studio/src/core/speed_curve.gd studio/src/core/document.gd studio/tests/timeline_workspace.gd studio/tests/timeline_workspace.tscn
git commit -m "feat: add speed curve families and atomic key edits"
```

### Task 11: Compact graph budget and plot geometry

**Files:**
- Modify: `studio/src/app/editor.gd:1680-1838, 2018-2040`
- Modify: `studio/src/ui/timeline.gd:760-804, 1218-1226, 1551-1560`
- Test: `studio/tests/layout.gd`

**Interfaces:**
- Consumes: `Timeline.set_mode`, `Timeline.graph_plot_rect`, `EditorShell._timeline_overlay_budget`.
- Produces: the measured graph-budget correction; `graph_plot_rect().size.y >= 120` at 915×412.

- [ ] **Step 1: Write the failing layout tests**

Add a graph block to `layout.gd` after the existing More checks, at `Vector2i(915, 412)`:

- `editor._timeline_visible = true`; `editor._timeline.set_mode("graph")`; `editor._sync_timeline_visibility()`; wait two frames.
- `editor._timeline_more == true` after entering graph mode.
- `editor._timeline_overlay_budget(stage_h) <= 300.0` and `_timeline_panel.size.y <= min(300.0, stage_h) + 0.5`.
- The clip lane and media lanes are not visible and are excluded from the budget.
- `editor._timeline.graph_plot_rect().size.y >= 120.0`.
- The compact header is folded; every visible graph control is ≥44 dp.
- Switching back to dope leaves `_timeline_more == true`, the overlay budget is `min(260, max(104, stage*0.46))`, and the lanes are eligible again.
- On a stage too short to yield a 120 dp plot (test `stage_height = 200`), the graph draws the exact caption `"Rotate or open the timeline workspace for curve editing"` instead of a sliver, and `graph_plot_rect().size.y < 120`.
- Closing and reopening the timeline resets the mode to dope, More to false, and the 34% / 208 dp dope budget. Leave the editor in that reset state at the end of the block so later layout checks are unaffected.
- The old dope assertions still pass: stage 1000 → 208, 500 → 170, 320 → 108.8, 200 → 104; the overlay leaves at least 55% of the stage free; More is `min(260, stage*0.46)`.

Also update the comment block that still says "42/46 percent" to the actual `34/46` values and the new graph rule.

- [ ] **Step 2: Run the suite to verify it fails**

Run: `"$GODOT" --headless --path studio res://tests/layout.tscn`
Expected: FAIL: graph plot is ~24–54 dp and the budget is not mode-aware.

- [ ] **Step 3: Implement the mode-aware budget and geometry**

`editor.gd`:

- Add `_timeline_graph_mode` derived from `_timeline.mode()`.
- `_timeline_overlay_budget(stage_height)`:
  - folded → `FOLDED_TIMELINE`;
  - graph → `minf(300.0, maxf(104.0, stage_height))`;
  - dope → the existing `0.46/260` or `0.34/208` branch.
- `_on_timeline_mode_changed("graph")` sets `_timeline_more = true` and calls `_timeline.set_more_state(true)` before `_sync_timeline_visibility()`. Dope does not clear More.
- In `_sync_timeline_visibility`, when graph mode: force `_timeline.set_header_folded(true)`, hide `_clip_lane` and `_media_lanes`, zero the lane height, and give the final sheet the full `budget - FOLDED_TIMELINE` room. Skip the lane/header fitting passes.
- `_toggle_timeline` resets the sheet to dope and `_timeline_more=false` on every open/close, so the compact default is restored and a reopened sheet cannot inherit the full-stage graph budget.

`timeline.gd`:

- In `_geometry`, graph top is `_ruler_h + GRAPH_TAB_HEIGHT + 12.0`; baseline is `maxf(_graph_top + 24.0, canvas.size.y - 28.0)`.
- Remove the 22 dp stats line from the plot area; draw stats only in the tab strip/header if still needed.
- `graph_plot_rect` uses the same top/bottom.
- `fit_sheet_height` in graph mode uses the full available room (minimum 48, preferred `maxf(120.0, available - header - rule)`) instead of the old 112/160 preferred height.
- When the resulting `graph_plot_rect().size.y < 120`, draw the exact caption `"Rotate or open the timeline workspace for curve editing"` centred in the plot area and do not draw a miniature curve. This is the honest short-window state.
- `_apply_sheet_height` uses a 120 dp graph floor, not 112/160.
- `set_short_layout` comment and behaviour match the new budget; the short separator still collapses.

- [ ] **Step 4: Run the suite to verify it passes**

Run: `"$GODOT" --headless --path studio res://tests/layout.tscn`
Expected: layout log ends PASS at 915×412 and every other size.

- [ ] **Step 5: Commit**

```bash
git add studio/src/app/editor.gd studio/src/ui/timeline.gd studio/tests/layout.gd
git commit -m "fix: give the compact speed graph a usable plot"
```

### Task 12: `SpeedGraph` control and channel selection

**Files:**
- Create: `studio/src/ui/speed_graph.gd`
- Modify: `studio/src/ui/timeline.gd`
- Test: `studio/tests/timeline_workspace.gd`

**Interfaces:**
- Consumes: Task 10's `Document.apply_key_edits`, `bake_curve_segment`, `SpeedCurve`.
- Produces: `Timeline.channel_selected`, `Timeline.channel()`; the full `SpeedGraph` API in the shared interfaces.

- [ ] **Step 1: Write the failing graph-control tests**

Instantiate a `Document`, create a mesh, write position/rotation/scale keys, then `SpeedGraphScript.new()`, `setup(doc)`, `set_context(doc.selected_id)`.

Assertions:

- `set_channel("position")` returns true for a valid channel; an invalid channel returns false and leaves the old channel.
- `set_context("")` clears selection and shows the `"Select an object"` empty state.
- `selected_segment()` returns the three exact refusals for none, multiple and last-key selections.
- One non-last selection returns `{ok:true, start_index, end_index, t0, t1}` matching the document keys.
- `select_indices([0])` selects one; `select_indices([1], true)` adds; `clear_selection()` empties; `selection_changed` fires with the new indices.
- Changing the channel clears stale indices and never selects a key from the previous channel.
- `commit_key_edit` retimes/values in one undo entry; a rotation value edit is refused with `"Rotation values are quaternion; drag rotates with the rig or gizmo."` while retime still works.
- `apply_easing` applies the scalar transition to the selected start key.
- `apply_curve_family("bounce_out")` bakes the selected→next segment and returns the exact notice `"Bounce out baked · N keys"`.
- `copy_selection`/`paste_at` place the relative set at the playhead clamped to duration, one undo entry.
- `add_key_at_playhead` inserts the sampled value with transition 1.0; `delete_selection` removes all selected in one edit.
- `fit()` sets the time window to `[0, duration]` and a padded value range; `plot_rect().size.y >= 0` after layout.
- The empty-state captions are exact:
  - `"Select an object"`;
  - `"No keys on this channel. Add a key at the playhead."`;
  - `"This channel has no editable value component."`;
  - `"Switch to Value to edit values."`;
  - `"Rotation values are quaternion; drag rotates with the rig or gizmo."`.
- The component menu is disabled for rotation in Value view and shows `All`.
- `Timeline.set_channel("scale")` emits `channel_selected("scale")`; tapping a dope channel row emits it too.

- [ ] **Step 2: Run the suite to verify it fails**

Run: `"$GODOT" --headless --path studio res://tests/timeline_workspace.tscn`
Expected: FAIL for the missing `SpeedGraph` and signal.

- [ ] **Step 3: Implement `SpeedGraph` and the channel signal**

`speed_graph.gd`:

- Extend `Control`; expose the exact API above. Own the key selection, time viewport, value range and view mode. Never mutate `Animation` directly.
- Build the 56 dp header (channel name/key count, `Value`/`Speed` segmented, `Fit`, `Multi`, `Presets` 96×44 or 44 dp `curve` icon below 420 dp), the plot, and the 56 dp key row (time field, value field, component menu, `Add key` 96×44, `Delete` 44 dp).
- Draw the real sampled channel: Value plots the channel value (position/scale component or normalized `All`; rotation Euler degrees for inspection only), Speed plots `|dv/dt|`.
- Empty states are drawn exactly; never draw a fake curve.
- Tap selects; `Multi` toggles. Horizontal drag retimes with `1/fps` snap when `doc.snap`. Vertical drag edits position/scale values in Value view. A drag uses a ghost preview and commits all selected keys on release through one `apply_key_edits` call.
- `Add key` samples at `doc.current_time`; `Delete` removes all selected in one edit.
- Copy stores `{time, transition, value}` relative to the first selected; paste clamps to duration.
- `Fit` resets time to `[0,duration]` and pads the value range by 10%. Pinch zooms time around the pinch centre; pan uses the existing two-finger gesture. Minimum time window is `0.1 s`.
- Re-resolve selected indices by time after every `keyframes_changed`; clear indices that no longer match.
- `selected_segment()` is the single enablement source for both `Easing` and `Curve family`. Both menus stay separate. Easing writes one transition scalar; Curve family calls `Document.bake_curve_segment`.

`timeline.gd`:

- Add `signal channel_selected(channel: String)`.
- Add `channel() -> String` returning `_selected_channel`.
- `set_channel()` emits `channel_selected` after a successful change.
- A tap on the full 44 dp dope channel row calls `set_channel()`. The compact graph tab strip already calls it.

- [ ] **Step 4: Run the suite to verify it passes**

Run: `"$GODOT" --headless --path studio res://tests/timeline_workspace.tscn`
Expected: `SUITE RESULT: PASS`.

- [ ] **Step 5: Commit**

```bash
git add studio/src/ui/speed_graph.gd studio/src/ui/timeline.gd studio/tests/timeline_workspace.gd
git commit -m "feat: add a real speed graph control"
```

### Task 13: Timeline workspace, reparenting and back precedence

**Files:**
- Modify: `studio/src/app/editor.gd` (`_build_timeline`, `handle_back`, resize, project close)
- Modify: `studio/src/ui/timeline.gd` (`set_workspace_mode`)
- Test: `studio/tests/timeline_workspace.gd`, `studio/tests/layout.gd`

**Interfaces:**
- Consumes: Task 12's `SpeedGraph`, `Timeline.channel_selected`.
- Produces: `EditorShell.open_timeline_workspace`, `close_timeline_workspace`, `timeline_workspace_open`; `Timeline.set_workspace_mode`.

- [ ] **Step 1: Write the failing workspace tests**

Assertions:

- At `915×412` and `1280×800`, `editor.open_timeline_workspace()` returns true when the sheet is open and the bounds are met. The left column is 45–55% of the body width, the graph plot is ≥120 dp at 915×412 and ≥480 dp at 1280×800, the header and footer are 56 dp, and every button is ≥44 dp. The header Close is 96×44.
- Opening reparents `_lane_scroll` and `_timeline` into the left column and the transport into the footer. Closing restores each node's exact original parent and child index. Opening twice is idempotent (no duplicate reparent/undo).
- The compact `_timeline_panel` is hidden while open; closing restores its visibility and the compact sheet remains usable.
- Below `720×360`, opening is refused with `"Landscape workspace needs at least 720 × 360 dp"`. If the window drops below either bound while open, the workspace closes once and a single toast explains why. Resizing from 720×360 to a supported 800×700 keeps the workspace open.
- Back precedence: with a modal open, Back closes the modal; with a drawer open and no modal, Back closes the drawer; with the workspace open and neither, Back closes the workspace; otherwise Back requests project close.
- Any project close path calls `close_timeline_workspace(false)` before the close sheet.
- `Timeline.channel_selected` drives `SpeedGraph.set_channel`; changing `doc.selected_id` clears the graph selection and re-resolves keys by time.
- The workspace is dope-only, with no mode tabs and no More; the transport is the single existing instance.
- Layout gates at both sizes still report no overflow and all hit targets ≥44 dp.

- [ ] **Step 2: Run the suites to verify they fail**

Run: `"$GODOT" --headless --path studio res://tests/timeline_workspace.tscn`
Expected: FAIL for the missing workspace methods.

- [ ] **Step 3: Implement the workspace**

`timeline.gd`:

- `set_workspace_mode(enabled)` forces dope, hides the mode tabs, compact header/more and clip/media chrome, and keeps the sheet's dope drawing. Restore the normal chrome on false.
- Expose `channel_selected` and emit it from `set_channel` and the dope row tap.

`editor.gd`:

- Add `_timeline_workspace` (PanelContainer, z 50, full stage rect) as a child of `_viewport_host`; hidden initially. Build a 56 dp header with the clip name and a 96×44 Close, a `HBoxContainer` body with a left VBox (`_lane_scroll` above `_timeline`) at 52% and a right `SpeedGraph` at 48%, an 8 dp gutter, and a 56 dp footer.
- `open_timeline_workspace()`:
  - require `sheet_visible()`, width ≥720 and height ≥360;
  - save `_workspace_previous_mode = _timeline.mode()` and `{node, parent, index}` for `_lane_scroll`, `_timeline` and the transport;
  - reparent them into the workspace, hide `_timeline_panel`, set `Timeline.set_workspace_mode(true)`, connect `channel_selected` to the graph, call `graph.set_context(doc.selected_id)` and `graph.set_channel(timeline.channel())`;
  - if the workspace is already open, return true without reparenting again.
- `close_timeline_workspace(restore_focus := true)` restores the saved parents and indices, calls `set_workspace_mode(false)`, restores `_workspace_previous_mode`, shows `_timeline_panel`, re-syncs the compact visibility, and optionally restores focus to the Expand button.
- `_on_resized`/`_on_viewport_resized` close the workspace below the bounds with one toast `"The timeline workspace needs at least 720 × 360 dp."`.
- `handle_back` checks the workspace after the drawer and before `request_close`.
- Every project close path calls `close_timeline_workspace(false)` first.
- Connect `doc.selection_changed` to `graph.set_context`; connect `Timeline.channel_selected` to `graph.set_channel`.

Add the 44 dp `maximize` Expand button to the timeline header, disabled below the bounds with the exact reason, and connect it to `open_timeline_workspace()`.

- [ ] **Step 4: Run the suites to verify they pass**

Run: `"$GODOT" --headless --path studio res://tests/timeline_workspace.tscn`
Run: `"$GODOT" --headless --path studio res://tests/layout.tscn`
Expected: both PASS.

- [ ] **Step 5: Commit**

```bash
git add studio/src/app/editor.gd studio/src/ui/timeline.gd studio/tests/timeline_workspace.gd studio/tests/layout.gd
git commit -m "feat: add the landscape timeline workspace"
```

---

## W4 — Materials, textures and shading

### Task 14: Material record, CRUD and format 3

**Files:**
- Create: `studio/src/core/material_system.gd`
- Modify: `studio/src/core/document.gd` (`FORMAT_VERSION`, setup, `to_data`, `_apply_data`, `_base_object`, `_normalize_object`)
- Test: `studio/tests/materials.gd`
- Create: `studio/tests/materials.tscn`
- Test: `studio/tests/smoke.gd`

**Interfaces:**
- Consumes: `Document.project_dir`, `begin_edit`/`end_edit`.
- Produces: the MaterialSystem record/CRUD API and format 3 persistence.

- [ ] **Step 1: Create the suite and write the failing persistence tests**

`materials.tscn` follows the suite pattern. The script prints `MATERIALS OK`/`MATERIALS FAIL`, ends with `SUITE RESULT: PASS|FAIL`.

Assertions:

- `MaterialSystem.create_material("Steel", "metal")` returns `mat_1`, appends one record with every §8.1 key, and emits `materials_changed`.
- `update_material` applies a partial patch, clamps roughness/metallic to 0–1, and rejects an unknown `shading` or a non-existent id with `last_error` set and no mutation.
- Texture paths must be project-relative with forward slashes. An absolute path or any `..` escape is rejected with `last_error = "Texture paths must stay inside the project."` and no mutation.
- `duplicate_material` returns a new `mat_N`, copies the record and names it `"Steel Copy"`. `delete_material` removes it.
- `to_data()` → `load_data()` round-trips every field. Duplicate ids cannot collide: `_next_material_id` is derived from the loaded ids.
- `Document.to_data()["format"] == 3` and carries a `materials` array. A v2 fixture with no materials loads with an empty library, legacy colours intact and never writes files.
- `_base_object()` includes `material_id: ""`, `part_materials: {}`, `part_surface_materials: {}`; `_normalize_object()` rejects non-string ids and non-dictionary assignment maps.
- `smoke.gd`: change the contract check from format 2 to 3 and assert `materials` is present. Keep the v1/v2 fixture loadable.

- [ ] **Step 2: Run the suites to verify they fail**

Run: `"$GODOT" --headless --path studio res://tests/materials.tscn`
Expected: FAIL for the missing file/API.
Run: `"$GODOT" --headless --path studio res://tests/smoke.tscn`
Expected: FAIL at the format-2 assertion.

- [ ] **Step 3: Implement the record and persistence**

`material_system.gd`:

- `extends RefCounted`; `signal materials_changed`; `var last_error := ""`.
- Default record exactly matches the §8.1 JSON shape; `notes: []` is an additive field used by adoption.
- Presets `matte`, `satin`, `metal`, `plastic`, `emissive`, `toon`, `unlit` set real fields only.
- `create_material` / `duplicate_material` / `delete_material` / `update_material` open no history by themselves; the UI boundary wraps them in `Document.begin_edit`/`end_edit`. `delete_material` clears every assignment that referenced the id in the same call.
- `material_ids()` returns a `PackedStringArray` in creation order.

`document.gd`:

- Add `const FORMAT_VERSION := 3`, `var material_system = MaterialSystemScript.new()`, `setup(document)`.
- `to_data()` adds `"materials": material_system.to_data()["materials"]`.
- `_apply_data()` calls `material_system.load_data(data)` **before** the `_spawn_object` loop, then applies all assignments after spawning.
- Add the three object keys to `_base_object` and normalize them in `_normalize_object`.
- Connect the existing `imported_scene_ready` to `material_system.adopt_import` in Task 17; do not add a second import path.

- [ ] **Step 4: Run the suites to verify they pass**

Run: `"$GODOT" --headless --path studio res://tests/materials.tscn`
Run: `"$GODOT" --headless --path studio res://tests/smoke.tscn`
Expected: both PASS.

- [ ] **Step 5: Commit**

```bash
git add studio/src/core/material_system.gd studio/src/core/document.gd studio/tests/materials.gd studio/tests/materials.tscn studio/tests/smoke.gd
git commit -m "feat: add the format 3 material library"
```

### Task 15: Material construction, shading and packed ORM

**Files:**
- Modify: `studio/src/core/material_system.gd`
- Test: `studio/tests/materials.gd`

**Interfaces:**
- Consumes: Task 14's records.
- Produces: `resource_for`, `build_material`, `missing_textures`, `clear_texture_cache`.

- [ ] **Step 1: Write the failing construction tests**

Assertions:

- A PBR record builds a `StandardMaterial3D` with `shading_mode == SHADING_MODE_PER_PIXEL`, the albedo colour, roughness, metallic and metallic specular.
- Unlit builds `SHADING_MODE_UNSHADED`; Toon sets `DIFFUSE_TOON` and `SPECULAR_TOON`; Rim sets `rim_enabled=true`, `rim`, `rim_tint`.
- Emission is disabled at energy 0 and enabled above 0, with `emission` and `emission_energy_multiplier` set.
- Albedo/normal/emission textures and normal/ao/emission flags are set; `normal_scale` is applied. UV scale/offset map to `Vector3(x,y,1)` / `Vector3(x,y,0)`, and filter/repeat match the record.
- A record with `orm_texture` builds an `ORMMaterial3D` with that map; separate roughness/metallic/AO maps are **not** applied. Clearing ORM builds a `StandardMaterial3D` and re-applies the separate maps.
- Toggling ORM rebuilds the resource and re-applies it to every assignment.
- A missing texture path leaves the property empty/disabled, does not crash, and appears in `missing_textures()`.
- One resource is built per material id and reused across assignments; `clear_texture_cache()` and a texture replacement rebuild the resource.

- [ ] **Step 2: Run the suite to verify it fails**

Run: `"$GODOT" --headless --path studio res://tests/materials.tscn`
Expected: FAIL for the missing construction APIs.

- [ ] **Step 3: Implement construction**

- `build_material(record)` chooses `ORMMaterial3D.new()` iff `orm_texture != ""`, else `StandardMaterial3D.new()`.
- Apply the §8.3 property table exactly. Use `texture_filter`, `texture_repeat`, `uv1_scale`, `uv1_offset` on the base class.
- Load textures through a path-keyed cache: `FileAccess.get_file_as_bytes(doc.project_dir.path_join(rel))`, then `Image.load_png_from_buffer` / `load_jpg_from_buffer` / `load_webp_from_buffer`, `ImageTexture.create_from_image`. Enable mipmaps for normal maps. A failed load records the path in `_missing_textures` and returns null.
- `resource_for(id)` caches one resource per id. `update_material` invalidates only that id. `clear_texture_cache()` clears image textures and resources.
- Shading switch does not invent properties: Unlit ignores lighting-only fields; the editor hides them with the exact note.

- [ ] **Step 4: Run the suite to verify it passes**

Run: `"$GODOT" --headless --path studio res://tests/materials.tscn`
Expected: `SUITE RESULT: PASS`.

- [ ] **Step 5: Commit**

```bash
git add studio/src/core/material_system.gd studio/tests/materials.gd
git commit -m "feat: build PBR, Unlit, Toon and Rim materials"
```

### Task 16: Assignment resolution and strict part targeting

**Files:**
- Modify: `studio/src/core/material_system.gd`
- Modify: `studio/src/core/document.gd` (only the material application hooks)
- Test: `studio/tests/materials.gd`

**Interfaces:**
- Consumes: Task 15's `resource_for`.
- Produces: `can_assign_part`, `assign_material`, `clear_material`, `resolve_assignment`, `apply_object`, `apply_all`.

- [ ] **Step 1: Write the failing assignment tests**

Assertions:

- Resolution order is `part_surface_materials["path#N"]` → `part_materials["path"]` → object `material_id` → legacy primitive fields.
- An empty `part_path` targets the object root and is always valid.
- A real `MeshInstance3D` part accepts a part assignment; a valid `path#N` accepts a surface assignment; clearing each slot falls back to the next level and finally to legacy.
- A non-mesh part returns `false`, sets `last_error = "This part has no mesh to shade."`, writes nothing and opens no undo entry.
- An out-of-range surface returns `false` with `last_error = "Surface N is out of range."`.
- `delete_material` clears every referencing assignment in the same edit, re-applies the affected objects and restores legacy visuals.
- `apply_object` walks every real surface, sets `surface_override_material` from the resolved id, and clears overrides when no assignment exists so legacy colours return.
- Duplicating an object shares material ids. Undo restores the assignments and the rendered overrides.

- [ ] **Step 2: Run the suite to verify it fails**

Run: `"$GODOT" --headless --path studio res://tests/materials.tscn`
Expected: FAIL for the missing assignment APIs.

- [ ] **Step 3: Implement assignment and application**

- `assign_material` / `clear_material` validate the object, material id, part path and surface before writing. They never recurse to child meshes.
- `can_assign_part` returns true only for a `MeshInstance3D` with a non-null mesh at the exact path.
- `resolve_assignment` implements the four-level order; `surface = -1` means the part slot.
- `apply_object` walks the generated tree, computes each mesh's stable part path, applies the resolved resource per surface, and restores embedded/legacy materials where no assignment exists. `apply_all` loops the object ids.
- Empty `last_error` at the start of every successful mutation; set it exactly on refusal.
- `Document` calls `material_system.apply_object(id)` after assignment changes and after undo/redo; no duplicate material path.

- [ ] **Step 4: Run the suite to verify it passes**

Run: `"$GODOT" --headless --path studio res://tests/materials.tscn`
Expected: `SUITE RESULT: PASS`.

- [ ] **Step 5: Commit**

```bash
git add studio/src/core/material_system.gd studio/src/core/document.gd studio/tests/materials.gd
git commit -m "feat: resolve object, part and surface materials"
```

### Task 17: Texture import and imported-material adoption

**Files:**
- Modify: `studio/src/core/project_store.gd` (texture import)
- Modify: `studio/src/core/material_system.gd` (`adopt_import`)
- Modify: `studio/src/core/document.gd` (adoption connection)
- Test: `studio/tests/materials.gd`

**Interfaces:**
- Consumes: Task 14's record, Task 15's texture loader.
- Produces: `ProjectStore.import_texture` and `MaterialSystem.adopt_import` with the spec's cap/summary contract.

- [ ] **Step 1: Write the failing import/adoption tests**

Assertions:

- `import_texture` accepts `.png`, `.jpg`, `.jpeg`, `.webp`; anything else returns exactly `"Kinema imports PNG, JPEG and WebP textures."`.
- An unreadable image returns exactly `"This image could not be read."`.
- A PNG/JPEG/WebP with both sides ≤4096 copies the original bytes unchanged into `textures/<slug>/<original-name>.<ext>`, returns the real dimensions, and `resized_from=""`.
- An oversized image is resized to a 4096 px largest side, stored only as `textures/<slug>/<slug>.png`, returns `resized_from="WxH"` with an ASCII `x`, and leaves no original copy.
- A write failure removes the partial file and folder. No `.import` file and no editor import pipeline is created; the runtime loads the stored image through the material system.
- Adoption of a runtime-built two-surface `MeshInstance3D` with a `StandardMaterial3D` creates one library entry per unique resource (deduped by instance), persists every supported texture, and assigns both surfaces through `part_surface_materials["<part>#<surface>"]`.
- An imported `ORMMaterial3D` keeps its packed ORM map and adopts as an `ORMMaterial3D` record.
- A compressed texture whose `get_image()` is null leaves the slot empty, records a note, and still applies the adopted scalars.
- Adoption caps at 32 materials / 64 textures and returns the exact notice `"Adopted 32 of N materials; the rest keep their embedded materials."`
- Adoption never runs on project load; an import with no materials still imports the model unchanged.

- [ ] **Step 2: Run the suite to verify it fails**

Run: `"$GODOT" --headless --path studio res://tests/materials.tscn`
Expected: FAIL for the missing texture import/adoption.

- [ ] **Step 3: Implement texture import and adoption**

`project_store.gd`:

- `import_texture(uri, project_dir, fallback_name)` follows §8.4 exactly. Use `Image.load_from_file(uri)` (or the buffer loaders in `material_system`) for dimensions, unique slug folders, and the ≤4096 vs >4096 split. Downscale with `Image.resize(..., Image.INTERPOLATE_BILINEAR)`; `Image.save_png` for the downscaled case. Return the exact keys/errors.

`material_system.gd`:

- `adopt_import(object_id, generated, model_name)` walks all `MeshInstance3D` surfaces, dedupes by `BaseMaterial3D.get_instance_id()`, copies scalars/flags/UV/emission, and saves supported `Texture2D.get_image()` maps as PNGs under `textures/imported/<model-slug>-<n>-<slot>.png`.
- Names are `<Model> · <material name or Material N>`.
- Assign each surface via `part_surface_materials`. Cap at 32/64 and return `{ok, adopted, capped, notice, materials, textures}`.
- On failure, return `{ok:false, error}` and leave the generated glTF materials untouched.
- `Document.setup` connects `imported_scene_ready` once and passes the object name to `adopt_import`. No load path emits it.

- [ ] **Step 4: Run the suite to verify it passes**

Run: `"$GODOT" --headless --path studio res://tests/materials.tscn`
Expected: `SUITE RESULT: PASS`.

- [ ] **Step 5: Commit**

```bash
git add studio/src/core/project_store.gd studio/src/core/material_system.gd studio/src/core/document.gd studio/tests/materials.gd
git commit -m "feat: import textures and adopt imported materials"
```

### Task 18: Inspector, material sheets, color reuse and object visuals

**Files:**
- Modify: `studio/src/ui/inspector.gd`
- Create: `studio/src/ui/material_sheet.gd`
- Create: `studio/src/ui/material_editor_sheet.gd`
- Modify: `studio/src/app/editor.gd` (sheets, picker, color API)
- Test: `studio/tests/materials.gd`, `studio/tests/object_visuals.gd`, `studio/tests/smoke.gd`

**Interfaces:**
- Consumes: Task 14–17 APIs.
- Produces: the object/part/surface material UI, the library and editor sheets, the generalized `open_color_sheet`, and the object-visual assertions.

- [ ] **Step 1: Write the failing UI tests**

Assertions:

- The inspector rebuilds on `part_selection_changed`.
- A mesh part shows `Part material` with its name, `Choose`/`Edit` actions, and a 44 dp surface chip row `All · 0 · 1 · …` for a multi-surface mesh. `All` calls `surface=-1`; `N` calls `surface=N`.
- A non-mesh part shows exactly `"Part · <name> · No mesh. Materials apply at the object level."` and no part actions; the object section remains.
- The object section shows the current material swatch/name, or `"Legacy colour"`; `Choose material` 96×44 and `Edit material` 96×44.
- Legacy colour/roughness/metallic controls appear only when no library material is assigned.
- The material library sheet lists 44 dp rows with a swatch, name, shading badge and 96×44 `Assign`; header `New material` and `Duplicate`; the empty state is exact. Tapping a row selects it; `Assign` and `Duplicate` are explicit buttons, never a hidden double-tap. `Assign` targets the current object/part/surface and closes.
- The material editor sheet has the name, the four 44 dp shading segments, base fields, map rows (Normal, ORM, Roughness, Metallic, AO, Emission), a 0–10 emission-energy scrub, UV numeric fields, and rim-only fields. The ORM slot label is exact. When ORM is set, the three separate slots are disabled with exactly `"Packed ORM supplies AO, roughness and metallic. Clear ORM to use separate maps."` and their files survive.
- A missing texture slot shows the path in `Kit.WARNING`; a mesh without UVs shows `"This part has no UVs; a texture will sample a single point."`
- The texture picker filter is `*.png, *.jpg, *.jpeg, *.webp;Images`.
- `open_color_sheet(target, property, current, on_commit)` opens the existing palette/hex/RGB sheet; the object `color` and `light_color` callers still work and commit through `on_commit`.
- `object_visuals.gd`: a material-assigned primitive's resource differs from the legacy primitive (texture/normal flags set), and an unlit material's `shading_mode == SHADING_MODE_UNSHADED`.
- `smoke.gd` still checks every visible new sheet action is ≥44 dp and the material row is 44 dp.

- [ ] **Step 2: Run the suites to verify they fail**

Run: `"$GODOT" --headless --path studio res://tests/materials.tscn`
Run: `"$GODOT" --headless --path studio res://tests/object_visuals.tscn`
Expected: FAIL for the missing UI/sheets.

- [ ] **Step 3: Implement the UI**

`inspector.gd`:

- Connect `doc.part_selection_changed` in `setup`; rebuild the part/surface section only.
- `_build_material` becomes the object material section and the part section described above. Use `doc.material_system.can_assign_part`, `resolve_assignment`, `assign_material` and `clear_material`. Wrap mutations in `begin_edit`/`end_edit` at the UI boundary.
- Surface chips set the active `surface`. The object section always targets `part_path=""`, `surface=-1`.

`material_sheet.gd` and `material_editor_sheet.gd`:

- Build the sheets exactly per §8.6. Use `Kit` 44 dp controls. Import/Replace/Clear call `ProjectStore.import_texture` and `update_material`; updates are undoable at the editor boundary.
- The editor sheet receives the material id and a `changed` callback; it refreshes from `MaterialSystem.get_material`.
- Delete uses the overlay confirmation and is destructive.

`editor.gd`:

- Add the library/editor sheet openers and the texture picker (`*.png, *.jpg, *.jpeg, *.webp;Images`).
- Generalize the color path to `open_color_sheet(target, property, current, on_commit)`. Keep the old object/light call sites working.
- Connect inspector `choose_material` / `edit_material` requests to the sheets with the object/part/surface target.
- No new hover, right-click or hidden long-press path.

`object_visuals.gd` and `smoke.gd`:

- Add the material/unlit assertions and the new format-3/UI checks. Keep the existing visual and contract checks.

- [ ] **Step 4: Run the suites to verify they pass**

Run: `"$GODOT" --headless --path studio res://tests/materials.tscn`
Run: `"$GODOT" --headless --path studio res://tests/object_visuals.tscn`
Run: `"$GODOT" --headless --path studio res://tests/smoke.tscn`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add studio/src/ui/inspector.gd studio/src/ui/material_sheet.gd studio/src/ui/material_editor_sheet.gd studio/src/app/editor.gd studio/tests/materials.gd studio/tests/object_visuals.gd studio/tests/smoke.gd
git commit -m "feat: add material library and editor sheets"
```

---

## Final Integration (Lead)

This is not a subagent task. Run it after all four branches merge.

- [ ] **Step 1: Update the external gate runner**

`/tmp/opencode/kinema-gates.sh` is tooling, not repository content. Change its suite loop to:

```bash
for suite in animation media rig hierarchy gizmo environment object_visuals graphics timeline_workspace materials; do
```

Do not commit the runner.

- [ ] **Step 2: Run the full gate set**

```bash
/tmp/opencode/kinema-gates.sh . /tmp/opencode/wave3-gates --with-xvfb
```

Required: parse log has 0 `SCRIPT ERROR`/`Parse Error`, and every suite reports PASS. `layout` runs both headless and xvfb.

- [ ] **Step 3: Verify the merge contract**

- `git diff --check` is clean.
- `git grep -n '"android"' -- studio/src` has no platform comparison.
- `Document.FORMAT_VERSION == 3`; a v2 project fixture loads.
- `graph_plot_rect().size.y >= 120` at 915×412.
- ORM class switch and strict part refusal tests are present.
- Every new visible button is ≥44 dp; primary actions are 96×44.

- [ ] **Step 4: Push and build**

Push `wave3/integration` to `feat/professional-rebuild`. Trigger GitHub Actions `assembleStandardDebug`, arm64-v8a, CI debug keystore, package `studio.kinema.app`. Download the APK artifact and record its byte size and SHA-256.

- [ ] **Step 5: Hand off the device checklist**

Give the user the APK and the spec §13 checklist. State clearly which items were verified by CI/headless and which remain device-only: MediaCodec encode, Forward+/Vulkan boot and risk revert, high-end effects, imported rig touch precision, timeline gestures, texture rendering and shading.

---

## Self-Review Notes

- Spec coverage: W1 §5, W2 §6, W3 §7, W4 §8, format §9, UI §10, gates §11, risks §12, device checklist §13, non-goals §14 and builder resolutions §15 each map to a task above.
- The graph budget is the one measured correction: the plan encodes the 120 dp outcome and the 300 dp cap, not the spec's miscalculated 62% figure. Task 11 states the arithmetic and the fallback to full stage.
- All later-task names match the binding interface block: `insert_pose_channel`, `apply_key_edits`, `bake_curve_segment`, `resource_for`, `open_color_sheet`, `risk_card_state`.
- Every Review Focus line has a named test in its owning task.
- No task leaves a "handle edge cases" step or an undefined helper.
