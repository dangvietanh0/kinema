# Kinema Studio — Professional Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. This plan is executed as one serial contract task, four isolated workstreams in parallel worktrees, then one serial integration task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Kinema Studio into a touch-first Android 3D animation tool that actually has multi-clip animation with transitions and layers, real media import/export (audio, video reference, GIF, MP4, camera JSON), and skeletal rigging (skinning, IK, pose library), while keeping the already-shipped workbench and its 44 dp touch contract.

**Architecture:** Contract-first. A single contract commit adds the design tokens, the `Document` subsystem lifecycle and extension points, the `EditorView` camera/ray APIs, and empty-but-callable subsystem facades. Four workstreams then build against that frozen contract in isolated git worktrees: redesign (WS-D), animation (WS-A), media (WS-B), rigging (WS-C). They are merged serially in the order `redesign → animation → media → rig`, and one integrator task wires the new panels into the shell. No workstream edits `document.gd` after the contract; the integrator owns that file.

**Tech Stack:** Godot 4.7.2-stable, GDScript, `Animation`/`AnimationPlayer`, `Skeleton3D`/`Skin`, `SubViewport`, `AudioStream*`, `GLTFDocument`, Java `MediaCodec`/`MediaMuxer`/`MediaMetadataRetriever`, GitHub Actions + Gradle `assembleStandardDebug`, Android 15–17, arm64-v8a, package `studio.kinema.app`.

**Spec:** `docs/superpowers/specs/2026-10-27-kinema-professional-expansion-design.md` (binding; §17 is the decision register and wins over earlier sections). Baseline: `f93f1bf`.

## Global Constraints

- **Touch:** every interactive control is at least **44 dp**; primary actions are **96×44 dp**; sheets and panels use square corners (`R_PANEL = 0`); controls use `R_CONTROL = 2`; menus/dialogs/toasts use `R_FLOAT = 4`. Desktop menu-bar chrome is pointer-only and may carry `qa_hit_exempt`.
- **Visual:** achromatic chrome; exact tokens in §5.1; IBM Plex Sans + IBM Plex Mono; no emoji, no gradients, no glass, no shadows, no decorative illustration. Only `DANGER` keeps a red channel.
- **Android:** Android 15–17, landscape priority, `arm64-v8a`, package `studio.kinema.app`, Gradle `assembleStandardDebug`, CI debug keystore. Never build an APK outside GitHub Actions.
- **No fake features:** if the engine/platform cannot do it, disable the control with a concrete reason. MP4 is real only through the Android Java backend; on Linux it reports unavailable. Video reference is a frame proxy, not real-time playback. Skinning uses distance auto-weights + per-bone influence scale + rebind; no weight-paint brush in this pass.
- **Time model:** `doc.duration` and `doc.current_time` are **clip-local**; `doc.sequence_duration()` and `doc.sequence_time()` are global. Audio/video follow sequence time. `doc.play()` plays the active clip; `doc.play_sequence()` plays the sequence. Never run both clocks.
- **Imported glTF/GLB:** embedded animations become Kinema clips, remapped to document paths, auto-play after import, and every imported `AnimationPlayer` is set `active = false`. Tracks that cannot be remapped are dropped and listed; never pretend they ran.
- **Lifecycle:** subsystems are `RefCounted`, owned by `Document`, created in `_init()`, reset by `_clear_runtime()`, loaded in the order `reset → _apply_data → animation.load_data → rig.load_data → media.load_data → assign active animation → seek`. `Document.process_priority = 100`; `AnimationPlayer` updates first, then mixer/IK/media advance.
- **Bind:** meshes are not reparented. Bind locks the mesh transform to the rig; unbind restores the saved source/transform. Skin weights live in binary sidecars, not undo JSON; bind is a polled job with real progress.
- **TDD:** every new module writes a failing test first, runs it, implements the minimum, runs the full suite, commits. RED evidence goes in the workstream report. Regression assertions may pass immediately, but must be labelled as regression.
- **Ownership:** workstreams may edit only the files assigned in §9.3 of the spec. `document.gd`, `project_store.gd`, `app/main.gd`, `tests/smoke.gd`, `tests/layout.gd`, `tests/capture.gd`, and the CI workflow belong to the integrator. `editor.gd` visual edits belong to WS-D; wiring edits belong to the integrator.
- **No push:** work happens on local branches/worktrees. The user pushes from `/root/kinema` with `git push origin HEAD:main` when ready. No APK, device, or CI success may be claimed without fresh evidence.
- **Language:** UI copy and commit subjects are English. The final response to the user is Vietnamese.

## Review Focus

These are the five failure classes most likely to ship broken. Each has a named test in the owning task.

1. **Crossfade/base-pose math.** Two strips overlap 0.5 s; at the midpoint the pose is 50/50, outside the overlap it is a single clip, and an object with no contribution returns to its static base pose. Test: `animation.gd` crossfade + base pose.
2. **Exact export geometry and GIF timing.** Video/PNG output is exactly 1280×720, 1920×1080, or 2560×1440; GIF delays use the centisecond accumulator and 60 fps is disabled. Test: `media.gd` exact-size render + GIF delay parse.
3. **Bind without double transform.** Binding a mesh to a rig does not reparent it, does not double-apply the rig transform, and unbind restores the static mesh. Test: `rig.gd` bind/unbind + transform.
4. **Imported glTF auto-play and no double clock.** The clip is created, remapped, selected, and played; the imported `AnimationPlayer` is inactive; `imported_scene_ready` fires only on import, not on load/undo. Test: `animation.gd` GLB roundtrip.
5. **Two clocks in the shell.** Sequence play updates the timeline's local time and disables clip play; clip play stops sequence audio/video. Test: `smoke.gd` transport integration.

## Worktree and Merge Protocol

Baseline for every worktree is the contract commit on `feat/professional-rebuild`. Do not branch from `main`.

```bash
# from the integration worktree root
git worktree add /root/kinema/.worktrees/kinema-ws-redesign -b ws/redesign HEAD
git worktree add /root/kinema/.worktrees/kinema-ws-animation -b ws/animation HEAD
git worktree add /root/kinema/.worktrees/kinema-ws-media -b ws/media HEAD
git worktree add /root/kinema/.worktrees/kinema-ws-rig -b ws/rig HEAD
```

Each workstream runs its own tests in its worktree and commits small. It does not push, merge, or touch another worktree. Merge in this order, running `parse + smoke + layout headless` after each merge:

1. `ws/redesign`
2. `ws/animation`
3. `ws/media`
4. `ws/rig`

If a merge conflicts outside the ownership table, the integrator keeps the owner's file and copies the owner's version; it does not rewrite the owner's logic.

---

## Task 0: Contract commit

**Why:** every workstream needs the same tokens, `Document` lifecycle, subsystem API, and `EditorView` camera/ray API before it can compile. This is the only commit that may change `document.gd` before integration.

**Files:**
- Modify: `studio/src/ui/tokens.gd`
- Modify: `studio/src/ui/kit.gd` (aliases and new style helpers only; visual refinement belongs to WS-D)
- Create: `studio/src/core/animation_system.gd`
- Create: `studio/src/core/media_system.gd`
- Create: `studio/src/core/rig_system.gd`
- Modify: `studio/src/core/document.gd`
- Modify: `studio/src/viewport/editor_view.gd`
- Modify: `scripts/stage-android.sh`
- Modify: `studio/tests/smoke.gd` (contract block + exact token assertions)

**Interfaces produced (binding for all workstreams):**

`AnimationSystem` (`src/core/animation_system.gd`) must expose at least:

```gdscript
func setup(document) -> void
func reset() -> void
func ensure_default_clip() -> void
func to_data() -> Dictionary
func load_data(data: Dictionary, nodes: Dictionary) -> void
func advance(delta: float) -> void

func create_clip(name: String, duration: float) -> String
func duplicate_clip(id: String) -> String
func delete_clip(id: String) -> bool
func rename_clip(id: String, name: String) -> void
func clip_ids() -> PackedStringArray
func get_clip(id: String) -> Dictionary
func animation_for(id: String) -> Animation
func active_animation() -> Animation
func set_active_clip(id: String) -> void
func active_clip_id() -> String

func add_layer(name: String) -> String
func delete_layer(id: String) -> bool
func layers() -> Array
func add_strip(layer_id: String, clip_id: String, start: float) -> String
func update_strip(strip_id: String, patch: Dictionary) -> void
func delete_strip(strip_id: String) -> void
func sequence_duration() -> float
func evaluate(time: float) -> Dictionary
func strip_at(time: float) -> Dictionary
func local_time(strip: Dictionary, time: float) -> float

func sequence_time() -> float
func active_local_time() -> float
func is_sequence_playing() -> bool
func seek_sequence(time: float) -> void
func play_sequence() -> void
func pause_sequence() -> void
func stop_sequence() -> void

func import_gltf_animations(object_id: String, node: Node) -> PackedStringArray
func on_imported_scene(object_id: String, node: Node) -> void
```

`MediaSystem` (`src/core/media_system.gd`) must expose at least:

```gdscript
func setup(document) -> void
func reset() -> void
func to_data() -> Dictionary
func load_data(data: Dictionary, project_dir: String) -> void
func advance(delta: float) -> void

func import_audio(uri: String) -> Dictionary
func add_audio_track(rel_path: String, start: float) -> String
func update_audio_track(id: String, patch: Dictionary) -> void
func delete_audio_track(id: String) -> void
func audio_tracks() -> Array

func import_video_reference(uri: String) -> Dictionary
func video_references() -> Array
func update_video_reference(id: String, patch: Dictionary) -> void
func delete_video_reference(id: String) -> void
func frame_for_time(id: String, time: float) -> Image

func seek_sequence(time: float, playing: bool) -> void
func play_sequence(time: float) -> void
func pause_sequence() -> void
func stop_sequence() -> void
func mix_wav(output_path: String) -> Dictionary
```

`RigSystem` (`src/core/rig_system.gd`) must expose at least:

```gdscript
func setup(document) -> void
func reset() -> void
func to_data() -> Dictionary
func load_data(data: Dictionary, nodes: Dictionary) -> void
func advance(delta: float) -> void

func create_rig(name: String, at: Vector3) -> String
func delete_rig(object_id: String) -> bool
func rig_ids() -> PackedStringArray
func get_rig(object_id: String) -> Dictionary
func active_rig_id() -> String
func set_active_rig(object_id: String) -> void

func add_bone(rig_id: String, name: String, parent: String, rest: Dictionary) -> int
func remove_bone(rig_id: String, name: String) -> bool
func set_bone_rest(rig_id: String, name: String, rest: Dictionary) -> void
func set_bone_parent(rig_id: String, name: String, parent: String) -> bool
func set_active_bone(rig_id: String, name: String) -> void
func set_bone_influence_scale(rig_id: String, bone: String, scale: float) -> void

func start_bind(rig_id: String, mesh_object_id: String, options: Dictionary) -> String
func poll_bind(job_id: String) -> Dictionary
func cancel_bind(job_id: String) -> void
func unbind_mesh(rig_id: String, mesh_object_id: String) -> bool

func add_ik_chain(rig_id: String, root: String, end: String, target_object_id: String) -> String
func update_ik_chain(rig_id: String, chain_id: String, patch: Dictionary) -> void
func delete_ik_chain(rig_id: String, chain_id: String) -> void
func solve_ik(rig_id: String) -> void
func bake_ik(rig_id: String) -> bool

func save_pose(rig_id: String, name: String) -> String
func apply_pose(rig_id: String, pose_id: String) -> void
func delete_pose(rig_id: String, pose_id: String) -> void
func key_pose(rig_id: String) -> bool

func adopt_imported_skeleton(object_id: String, node: Node) -> bool
func on_object_spawned(obj: Dictionary, node: Node3D) -> void
func on_object_properties(obj: Dictionary, node: Node3D) -> void
```

`Document` additions:

```gdscript
signal clips_changed
signal active_clip_changed(id: String)
signal media_changed
signal rigs_changed
signal rig_selection_changed(rig_id: String, bone: String)
signal imported_scene_ready(object_id: String, node: Node)
signal object_spawned(object_id: String, node: Node)

var animation_system
var media_system
var rig_system

func sequence_duration() -> float
func sequence_time() -> float
func seek_sequence(time: float, silent := false) -> void
func play_sequence() -> void
func pause_sequence() -> void
func stop_sequence() -> void
func is_sequence_playing() -> bool
func set_active_clip(id: String) -> void
func active_clip_id() -> String

func insert_bone_key(rig_object_id: String, bone: String, rotation: Quaternion) -> int
func get_bone_keys(rig_object_id: String, bone: String) -> Array
func delete_bone_key(rig_object_id: String, bone: String, index: int) -> void
func sample_bone(rig_object_id: String, bone: String, time: float) -> Quaternion
func insert_pose_keys(rig_object_id: String, pose: Dictionary) -> void
```

`EditorView` additions:

```gdscript
func capture_with_camera(size: Vector2i, msaa: int, xform: Transform3D, fov: float, transparent_bg := false) -> Image
func world_to_screen(world: Vector3) -> Vector2
func screen_ray(screen: Vector2) -> Dictionary   # {origin, direction}
```

**Step 0.1 — Tokens and kit**

- [ ] Write the new token values in `tokens.gd` exactly as §5.1: `BG #000000`, `SURFACE #0E0E0E`, `SURFACE_2 #151515`, `SURFACE_3 #1D1D1D`, `SURFACE_HOVER #272727`, add `SURFACE_ACTIVE #333333`, `BORDER #3C3C3C`, `BORDER_SOFT #242424`, `TEXT #EBEBEB`, `TEXT_MUTED #A6A6A6`, `TEXT_DIM #858585`, `FOCUS #EDEDED`, `TIME #B8B8B8`, `DANGER #E5706B`, axes `#C1675F/#86A87B/#6F90B8`, `R_PANEL 0`, `R_CONTROL 2`, `R_FLOAT 4`, `GUTTER 1`, `MOTION_FAST 0.10`, `MOTION_BASE 0.16`.
- [ ] Re-export the new constants from `kit.gd`. Add `panel_style()`, `control_style()`, `float_style()` helpers that call `flat_style` with the matching radius. Do **not** restyle every control in this task; WS-D owns the visual pass.
- [ ] Update `smoke.gd` exact-token assertions to `000000`, `EDEDED`, `B8B8B8`; add `SURFACE_ACTIVE`, `R_CONTROL`, `R_FLOAT` existence assertions.
- [ ] Run parse + smoke. Expected: 0 errors, smoke PASS.

**Step 0.2 — Subsystem facades**

- [ ] Create `animation_system.gd` as a legacy bridge. It owns `_document`, `_clips`, `_layers`. `reset()` clears them. `ensure_default_clip()` is a no-op in the bridge. `active_animation()` returns `_document.animation` (legacy fallback). `sequence_duration()` returns `_document.duration`. `sequence_time()` returns `_document.current_time`. `active_local_time()` returns `_document.current_time`. `is_sequence_playing()` returns false. `to_data()` returns `{"clips": [], "layers": []}`. All CRUD returns empty/`""`/false; `advance()` and transport are no-ops. Every unimplemented method has a `## WS-A:` comment naming the workstream.
- [ ] Create `media_system.gd` with the full API and safe no-ops. `to_data()` returns `{"media": {"audio": [], "video_refs": []}}`. Import methods return `{"ok": false, "error": "Media import is not implemented yet."}`. `frame_for_time()` returns `null`. `mix_wav()` returns `{"ok": false, "error": "WAV mixdown is not implemented yet."}`.
- [ ] Create `rig_system.gd` with the full API and safe no-ops. `to_data()` returns `{"rigs": []}`. `get_rig()` returns `{}`. `start_bind()` returns `""`. `poll_bind()` returns `{"state": "error", "progress": 0.0, "result": {}, "error": "Rigging is not implemented yet."}`. All mutators return false/empty.
- [ ] Run parse. Expected: no parse errors.

**Step 0.3 — Document lifecycle and extension points**

- [ ] Preload the three scripts and create the three subsystems in `_init()`, calling `setup(self)` on each.
- [ ] In `_ready()`, set `process_priority = 100` before `_ensure_player()`.
- [ ] In `_clear_runtime()`, call `reset()` on all three subsystems before removing children; do not free them. Keep `anim_player = null` and `animation = null`.
- [ ] In `new_project()`, after `_create_animation()`, call `animation_system.ensure_default_clip()` and then `animation = animation_system.active_animation()` if non-null.
- [ ] In `_apply_data()`: after spawning objects, if `data` has a legacy `animation` dictionary, call `_load_animation_tracks(anim_data)`; then call `animation_system.load_data(data, nodes)`, `rig_system.load_data(data, nodes)`, `media_system.load_data(data, project_dir)`, assign `animation = animation_system.active_animation()` if non-null, then `_refresh_animation()`.
- [ ] In `to_data()`: always write `"format": 2`; merge `animation_system.to_data()` keys `clips`/`layers`, `rig_system.to_data()` key `rigs`, and `media_system.to_data()` key `media`. If the animation system returns no clips, keep the legacy `"animation"` mirror so the contract remains usable; WS-A will return real clips and the mirror will disappear naturally.
- [ ] In `_process()`: run exactly one advance pass per frame. If `_sequence_playing`, call `animation_system.advance(delta)`, read `active_local_time()`, update `current_time`, and emit `playback_changed` only when the time changed; when `is_sequence_playing()` becomes false, clear the flag and emit a stopped state. Do not read `anim_player` while sequence playing. Otherwise run the existing clip-playback block, then call `animation_system.advance(delta)`. In both branches call `rig_system.advance(delta)` and `media_system.advance(delta)` once after the animation advance.
- [ ] In `_spawn_object()`: after the visual is built, call `rig_system.on_object_spawned(obj, node)` and emit `object_spawned(id, node)`.
- [ ] In `_apply_visual_properties()`: call `rig_system.on_object_properties(obj, node)` at the end.
- [ ] In `_init()`, connect `imported_scene_ready` to `animation_system.on_imported_scene` and `rig_system.adopt_imported_skeleton`. In `add_imported()`, after `_spawn_object(obj)`, emit `imported_scene_ready(id, nodes[id])`. Do not emit it from `_spawn_object()`.
- [ ] In `seek()`, `play()`, `pause()`, and `stop()`: clear `_sequence_playing`, call `animation_system.pause_sequence()`, and `media_system.pause_sequence()` before the clip transport. `seek()` then seeks the active clip as today.
- [ ] Implement `sequence_duration/sequence_time/seek_sequence/play_sequence/pause_sequence/stop_sequence/is_sequence_playing` as delegates to the animation system plus `media_system` sequence calls. `seek_sequence` also updates `current_time = animation_system.active_local_time()` and emits `playback_changed` unless silent. `play_sequence` sets `_sequence_playing = true`; `pause/stop` clear it.
- [ ] Implement `Document.set_active_clip(id)` as `animation_system.set_active_clip(id)` → `animation = animation_system.active_animation()` → `_refresh_animation()` → `active_clip_changed.emit(id)`. Implement `Document.active_clip_id()` as a delegate. WS-A's clip UI must call these document methods, never the system directly, so `doc.animation` never goes stale.
- [ ] Implement the bone-key document APIs directly against `animation` so WS-C can build before the rig system is complete: path `"<rig_node_name>/Skeleton3D:<bone>"`, type `TYPE_ROTATION_3D`, keys at `current_time`, `get_bone_keys()` returns `[{"time": float, "value": Quaternion, "index": int}]`, `delete_bone_key()` removes by index, `sample_bone()` uses `rotation_track_interpolate`, `insert_pose_keys()` inserts one rotation key per bone in the pose dictionary.
- [ ] Run parse + smoke + layout headless. Expected: 0 errors, smoke PASS, layout PASS.

**Step 0.4 — EditorView camera and ray APIs**

- [ ] Add `capture_with_camera(size, msaa, xform, fov, transparent_bg := false)`: use a probe `SubViewport` at exactly `size`, `msaa_3d = msaa`, `world_3d = _viewport.world_3d`, `transparent_bg = transparent_bg`, a `Camera3D` with `global_transform = xform`, `fov = fov`, `keep_aspect = Camera3D.KEEP_HEIGHT`, hide the grid and markers, wait two `RenderingServer.frame_post_draw` frames, return the image, restore grid/markers/draft state. Return `null` if `_viewport`/`_camera` is missing or `size` is smaller than 2×2.
- [ ] Add `world_to_screen(world)` returning `_to_ui(_camera.unproject_position(world))`, and `screen_ray(screen)` returning `{"origin": ..., "direction": ...}` by mapping UI coordinates into the preview viewport and calling `project_ray_origin`/`project_ray_normal`. Guard missing camera/viewport.
- [ ] Add smoke assertions that `main._editor._view.has_method("capture_with_camera")`, `world_to_screen`, and `screen_ray`.
- [ ] Run parse + smoke + layout headless + layout xvfb. Expected: PASS.

**Step 0.5 — Android staging**

- [ ] In `scripts/stage-android.sh`, after copying assets, add a guarded copy of `studio/android/app/java` into `$APP/src/main/java` when the directory exists. Do not fail when it is absent (WS-B creates it).
- [ ] Add a shell check to the contract evidence: `grep -q 'studio/android/app/java' scripts/stage-android.sh`.

**Step 0.6 — Contract smoke block**

- [ ] Add a `SMOKE STEP: expansion contract` block after the existing document checks:
  - `doc.has_signal("clips_changed")`, `active_clip_changed`, `media_changed`, `rigs_changed`, `rig_selection_changed`, `imported_scene_ready`, `object_spawned`.
  - `doc.animation_system != null`, `doc.media_system != null`, `doc.rig_system != null`, and each `.document == doc` (or `_document == doc`).
  - `doc.to_data().get("format") == 2`; keys `clips`, `layers`, `rigs`, `media` exist.
  - `doc.sequence_duration() == doc.duration`; `doc.sequence_time() == doc.current_time`; `doc.is_sequence_playing() == false`.
  - Build a minimal v1 dictionary with one object and a legacy `animation` track; `load_project` on a fresh `Document` returns true; duration/loop/object count survive. Free the probe document.
  - `doc.insert_bone_key` exists and `doc.get_bone_keys` returns an Array; call them only if a rig object is present, otherwise assert the methods exist.
- [ ] Run parse + smoke + layout headless + layout xvfb. Expected: all PASS.

**Step 0.7 — Commit**

```bash
git add studio/src/ui/tokens.gd studio/src/ui/kit.gd \
  studio/src/core/animation_system.gd studio/src/core/media_system.gd studio/src/core/rig_system.gd \
  studio/src/core/document.gd studio/src/viewport/editor_view.gd \
  scripts/stage-android.sh studio/tests/smoke.gd
git commit -m "feat: add the expansion contract for clips, media and rigs"
```

**Gate:** parse clean, smoke PASS (record the OK count), layout headless PASS, layout xvfb PASS. Do not create worktrees until this gate is green.

---

## Workstream D — Redesign visual pass

**Goal:** Apply the redesign visual language to the existing shell without changing behavior or the contract APIs. This is the first merge because it changes tokens/kit/chrome that the other workstreams render inside.

**Files owned:** `src/ui/tokens.gd`, `kit.gd`, `assets/icons/*`, `src/ui/components/top_bar.gd`, `bottom_bar.gd`, `tool_rail.gd`, `status_bar.gd`, `viewport_header.gd`, `src/ui/outliner.gd`, `inspector.gd`, `timeline.gd`, `overlay.gd`, `num_field.gd`, `scrub_bar.gd`, `src/app/home.gd`, `src/app/editor.gd` (visual only), `src/ui/settings_panel.gd`, `workspace_sheet.gd`, `src/ui/components/perf_overlay.gd`, `src/viewport/editor_view.gd` (HUD/header only).

**Must not touch:** `document.gd`, `project_store.gd`, `app/main.gd`, `animation_system.gd`, `media_system.gd`, `rig_system.gd`, `tests/smoke.gd`, `tests/layout.gd`, `tests/capture.gd`, CI.

**Reference:** `/storage/emulated/0/Download/kinema-redesign/kinema-professional-rebuild/` and `/storage/emulated/0/Download/before-after.png`. Treat them as visual evidence, not code to copy. The binding token table is §5.1; the 44 dp floor wins over the reference's 40/32 dp density.

**Task D1 — Tokens, kit, icons**

- [ ] Add the new icon set from §5.4: `blend`, `layers`, `key-round`, `film`, `audio-wave`, `video`, `gif`, `mp4`, `camera`, `bone`, `pose`, `target`, `link`, `unlink`, `weight`, `scissors`, `transition`, `proxy`. Use one 24-grid, 1.5 stroke family. Keep existing icon names working.
- [ ] Update `Kit` theme styleboxes: panels 0, buttons/fields/chips 2, popups/tooltips/dialogs 4. Use `SURFACE_ACTIVE` for selected rows/toggles. Do not change the exact token values from Task 0.
- [ ] Add a `qa_hit_exempt` meta for pointer-only desktop menu-bar chrome; keep every touch control at 44 dp.
- [ ] Test: extend `smoke.gd`? **No** — WS-D may not edit smoke. Instead run the existing smoke and layout; if a visual change breaks an assertion, fix the visual, not the test. Add a small `tests/redesign.gd` only if you need local proof, and do not commit it unless it is useful to the integrator. Prefer capture evidence.
- [ ] Run parse + smoke + layout headless. Expected: PASS.

**Task D2 — Chrome and viewport header**

- [ ] Build `components/viewport_header.gd`: a 36–44 dp strip owned by the viewport, with `Perspective` + `Add` on the left and `Grid` + `Frame` on the right. It must not float over the image; it occupies layout space. Buttons are 44 dp hit targets.
- [ ] Rework top bar, bottom bar, tool rail, status bar to the redesign proportions: Compact bar 48, Studio bar 44, Desktop menu bar 36; headers 44/36/32; rows 44/44/40; controls always 44. Use 18/20 px glyphs.
- [ ] Home: list at narrow widths, table at wide widths; no hero/card marketing; project rows are real and readable; empty state is honest.
- [ ] Editor chrome: dock tabs Scene/Props, timeline header, transport, rulers, sheet chrome, settings, workspace, performance overlay. Keep existing behavior and test seams (`doc`, `_view`, `_timeline`, `_overlay`, `_settings_duration_field`, `_settings_fps_field`, `_preset_buttons`).
- [ ] Do not add ClipLane, MediaLanes, RigPanel, or new sheet wiring; those are integration.
- [ ] Run parse + smoke + layout headless + layout xvfb. Expected: PASS.

**Task D3 — Visual QA**

- [ ] Run the capture harness for the existing actions at 412×915, 915×412, 1440×900: `home`, `timeline`, `drawer-scene`, `drawer-props`, `add-sheet`, `settings`, `performance`, `renderer`, `graphics`, `render`, `quick-render`, `workspace`, `draft`, `graph`.
- [ ] Inspect the captures for clipping, overlap, unreadable text, missing icons, and controls under 44 dp. Fix what you find in WS-D files.
- [ ] Record the capture paths and a short visual-QA table in the report. Do not claim device verification.

**Task D4 — Commit and report**

```bash
git add studio/src/ui studio/src/app/home.gd studio/src/app/editor.gd studio/src/viewport/editor_view.gd studio/assets/icons
git commit -m "feat(ui): apply the graphite redesign to the workbench"
```

**Report contract:** status, commits, files changed, parse/smoke/layout evidence with OK/FAIL counts, capture paths, any behavior you had to touch, and concerns. Return only status + commits + one-line test summary + concerns; write the full report to the brief's report path.

---

## Workstream A — Multi-clip animation

**Goal:** Real clips, layers, strips, transitions, fades, glTF embedded animation import, and the clip-lane/sheet UI.

**Files owned:** `src/core/animation_system.gd`, `src/core/clip_mixer.gd`, `src/ui/clip_lane.gd`, `clip_sheet.gd`, `layer_sheet.gd`, `strip_sheet.gd`, `tests/animation.gd`, `tests/animation.tscn`.

**Must not touch:** `document.gd`, `editor.gd`, `smoke.gd`, `layout.gd`, `capture.gd`, media/rig files.

**Contract consumed:** `Document.animation_system`, `doc.animation` (active clip), `doc.duration/current_time`, `doc.sequence_*`, `doc.begin_edit/end_edit`, `doc.keyframes_changed`, `doc.imported_scene_ready`, `EditorView` not needed.

**Task A1 — Pure mixer**

- [ ] Write `tests/animation.gd` + `.tscn` first. The harness prints `ANIMATION OK/FAIL` and ends with `ANIMATION RESULT: PASS` or `FAIL`.
- [ ] RED: add a test that builds two one-track clips (`position` 0→1 and 0→3) and two strips overlapping 0.5 s; call `ClipMixer.evaluate()` at the midpoint and assert the position is the 50/50 average. Run the test and record the failure (`clip_mixer.gd` missing).
- [ ] Implement `clip_mixer.gd` as a static `evaluate(clips, layers, time, object_ids, base_poses, bone_paths) -> Dictionary` exactly per §6.3. Support override/additive, mute/solo, layer/strip weight, smoothstep fade, ease time-warp, loop/clamp, object position/rotation/scale, bone rotation, base pose, and no-contribution fallback. Cache track lookup by clip+path.
- [ ] Add tests: layer weight 0.5, additive position/rotation/scale, mute/solo, fade in/out endpoints, bone track sample, base pose gap, crossfade at start/mid/end, and a 200-track/60-sample performance measurement printed as `ANIMATION PERF: <ms>`.
- [ ] Run `animation.gd` green; run parse + smoke.

**Task A2 — AnimationSystem model and serialization**

- [ ] RED: v1 migration test — build a v1 document with a legacy `animation` and load it through `Document.load_project`; assert one clip named `Take 01`, one layer, one strip, same keys/duration/loop.
- [ ] RED: clip CRUD test — create two clips, duplicate A to B, edit B's key, assert A unchanged; delete a clip referenced by a strip is blocked with a reason; rename works.
- [ ] Implement the full `AnimationSystem` API. Clips own `Animation` resources; serialize tracks as `{path,type,interpolation,keys:[{t,v,e}]}`. Layers own strips; `sequence_duration()` = max strip end on unmuted layers, min 0.04. `strip_at(time)` returns the topmost active strip; `local_time()` implements trim/speed/loop/clamp. `evaluate(time)` calls `ClipMixer` with document objects/base poses/bone paths.
- [ ] Implement `ensure_default_clip()`, `active_animation()`, `set_active_clip()`, and keep `doc.animation` pointing at the active clip's `Animation`. `ensure_default_clip()` adopts `document.animation` when no clip exists, otherwise creates a new `Animation`; the contract's `new_project`/`_apply_data` then assign `doc.animation`. The clip UI must call `doc.set_active_clip(id)`, never the system directly.
- [ ] Implement sequence transport: `sequence_time`, `active_local_time`, `is_sequence_playing`, `seek_sequence`, `play_sequence`, `pause_sequence`, `stop_sequence`. Sequence playback advances in `advance(delta)`, evaluates the mixer, applies object/bone poses, and updates active local time. Clip mode uses the `AnimationPlayer` fast path; sequence mode disables the player and applies the mixer.
- [ ] RED: strip move/trim/speed/sequence-duration tests; layer add/delete/weight/mute/solo; save/load v2 roundtrip; v1→v2 save. Implement until green.
- [ ] Add the `import_gltf_animations`/`on_imported_scene` implementation in Task A4.
- [ ] Run `animation.gd` green; run parse + smoke.

**Task A3 — Clip lane and sheets**

- [ ] Build `clip_lane.gd`: layer rows 44 dp, strip blocks 44 dp, global playhead, `+ Clip`, `Layers`, `Play sequence`, `Fit`. Strip tap selects active clip + strip and opens `strip_sheet`; drag moves; left/right handles trim; fade handles are 44×44 hit areas; overlapping strips draw a 1 px hatch.
- [ ] Build `clip_sheet.gd` (list, New/Duplicate/Rename/Delete, duration, loop, active), `layer_sheet.gd` (name, weight slider+numeric, blend, mute/solo, delete-last guard), `strip_sheet.gd` (start/trim/speed/weight/fade/ease/blend).
- [ ] Add UI tests in `animation.gd`: instantiate `ClipLane` with a Document, assert layer row count, strip block count, 44 dp minimums, play-sequence button exists, and a tap selects the strip. No fake controls.
- [ ] Do not wire into `editor.gd`; the integrator does that. Expose public `setup(document)`, `refresh()`, and signals the integrator can connect.
- [ ] Run `animation.gd` green; run parse + smoke.

**Task A4 — glTF/GLB embedded animation**

- [ ] RED: build a `Node3D` + `AnimationPlayer` with one position animation, export a GLB at runtime with `GLTFDocument.append_from_scene`/`write_to_filesystem`, import it through `ProjectStore`/`Document.add_imported`, and assert: a clip appears, its track path is `<object_node>/...`, the imported player is inactive, and `doc.play()` was called. Also assert `imported_scene_ready` fires once on import and not on `load_project`/undo.
- [ ] Implement scanning of `AnimationPlayer` nodes under the imported scene, copy each animation into a new clip, remap track paths, create an `Imported` layer and a strip at start 0, set the first animation active, call `doc.play()`, and set every imported `AnimationPlayer.active = false`. Drop unsupported tracks with a warning and return the list in the import summary.
- [ ] Add a test for a GLB with no animation: import succeeds, no clip created.
- [ ] Run `animation.gd` green; run parse + smoke.

**Task A5 — Commit and report**

```bash
git add studio/src/core/animation_system.gd studio/src/core/clip_mixer.gd \
  studio/src/ui/clip_lane.gd studio/src/ui/clip_sheet.gd studio/src/ui/layer_sheet.gd studio/src/ui/strip_sheet.gd \
  studio/tests/animation.gd studio/tests/animation.tscn
git commit -m "feat(animation): add clips, layers, transitions and glTF playback"
```

**Report contract:** status, commits, RED evidence for each new module, `animation.gd` PASS with OK/FAIL counts, parse/smoke evidence, performance number, and concerns (especially anything the integrator must wire).

---

## Workstream B — Media

**Goal:** Real audio tracks, video-reference frame proxies, GIF export, exact-size sequence rendering, camera JSON, and the Android MP4 backend.

**Files owned:** `src/core/media_system.gd`, `audio_library.gd`, `video_reference.gd`, `gif_encoder.gd`, `sequence_renderer.gd`, `camera_export.gd`, `android_video.gd`, `src/ui/media_lanes.gd`, `audio_sheet.gd`, `video_reference_panel.gd`, `media_export_sheet.gd`, `media_import_sheet.gd`, `studio/android/app/java/studio/kinema/media/*.java`, `scripts/stage-android.sh` (Java copy line only), `tests/media.gd`, `tests/media.tscn`.

**Must not touch:** `document.gd`, `editor.gd`, `smoke.gd`, `layout.gd`, `capture.gd`, animation/rig files.

**Contract consumed:** `Document.sequence_time/seek_sequence/play_sequence/pause_sequence/stop_sequence/is_sequence_playing`, `doc.project_dir`, `doc.animation_system.active_local_time()/strip_at()`, `EditorView.capture_with_camera`, `doc.begin_edit/end_edit`.

**Task B1 — Audio library and system**

- [ ] RED: generate a 1 s PCM WAV in code, import it, add a track, assert the track is serialized with start/trim/volume/mute/fade; assert expected playback offset math; assert mute and fade envelope; assert WAV mixdown produces a valid RIFF header.
- [ ] Implement `audio_library.gd` (load WAV/OGG/MP3, copy into `<project>/audio/`, waveform peak cache for WAV, honest `waveform unavailable` for OGG/MP3) and the audio half of `media_system.gd` (tracks, players, sequence seek/play/pause/stop, volume/fade, delete).
- [ ] Implement `mix_wav(output_path)` only when every source is WAV; otherwise return `{ok:false, error:"WAV mixdown needs WAV sources; MP4 export decodes other formats in the Android backend."}`.
- [ ] Run `media.gd` green for the audio block; run parse + smoke.

**Task B2 — Video reference proxy**

- [ ] RED: create five fake JPEG frames + `reference.json`, load the reference, assert frame index by sequence time, clamp at the end, clip-mode mapping via active strip, and delete removes the directory.
- [ ] Implement `video_reference.gd` + the video half of `media_system.gd`: schema/defaults from §17.9, frame loading/cache, `frame_for_time`, overlay data updates, delete with confirm metadata. Android MP4/M4V/MOV extraction calls `KinemaVideoFrames.extract`; non-Android returns unsupported; `.ogv` uses `VideoStreamPlayer` and reports that path honestly.
- [ ] Build `media_lanes.gd` (audio lane 48 dp/track, video lane 40 dp, collapsible, tap/drag, selected outline) and `audio_sheet.gd`/`video_reference_panel.gd`. UI tests in `media.gd`: row heights, empty states, 44 dp controls.
- [ ] Run `media.gd` green for the video block; run parse + smoke.

**Task B3 — GIF encoder**

- [ ] RED: encode three 16×16 frames at 24 fps; parse the GIF header `GIF89a`, logical screen size, NETSCAPE loop extension, frame count, trailer `0x3B`, and per-frame delays; assert the average delay is within 0.5% of nominal and 60 fps is rejected with the exact reason.
- [ ] Implement `gif_encoder.gd` per §7.3/§17.11: 256-color global table, median-cut quantization, Floyd–Steinberg optional, LZW clear/end codes, disposal 1, accumulator delays, alpha < 0.5 to background. `encode(frames, fps, loop)`.
- [ ] Run `media.gd` green for GIF; run parse + smoke.

**Task B4 — Sequence renderer and camera export**

- [ ] RED: render three 64×64 PNGs through `SequenceRenderer` with a fake camera, assert files exist, frame count, exact dimensions, and cancel leaves no final output. Add a camera JSON export test: parse, frame count, position/rotation roundtrip, duration.
- [ ] Implement `sequence_renderer.gd`: per frame `doc.seek_sequence(t)`, one `await process_frame`, `rig_system.solve_ik()` if present, capture with editor or scene camera at exact size, write numbered PNGs, progress/cancel, cleanup rules. Implement `camera_export.gd`: JSON version 1, fps, duration, camera name, static fov, frames `{t, position, rotation}`.
- [ ] Add exact-size tests for 1280×720, 1920×1080, 2560×1440 using a small fake viewport; if a size is not available headless, assert the requested size is passed to `capture_with_camera` via a spy and mark the pixel check as xvfb-only.
- [ ] Run `media.gd` green for renderer/camera; run parse + smoke.

**Task B5 — Android MP4 backend and facade**

- [ ] Write `KinemaVideoEncoder.java` and `KinemaVideoFrames.java` per §7.4/§7.2: static `encode/progress/done/error/cancel/capabilities/probe`, MediaCodec H.264 + AAC, MediaMuxer, manifest parsing, PNG frame input, audio decode/mix, thread-safe progress, cancel cleanup, one encode at a time; frame extraction via `MediaMetadataRetriever` with JPEG output and `reference.json`.
- [ ] Write `android_video.gd` facade: `available()` only on Android and only when `JavaClassWrapper.wrap("studio.kinema.media.KinemaVideoEncoder")` succeeds; `capabilities`, `encode`, `poll`, `cancel`, `probe`; non-Android returns `available=false` with the exact reason from §7.4. Never call Java on non-Android.
- [ ] Add `media.gd` tests: non-Android facade reason; manifest builder frame count/audio entries; stage script contains the Java copy line; Java files contain the required public methods (source-level check only; no Java runtime here).
- [ ] Build `media_export_sheet.gd` (PNG/GIF/MP4, exact resolutions, fps 12/24/30/60 with GIF 60 disabled, bitrate, range, camera, audio toggle, output, progress `Frame n/N` → `Encoding video` → `Verifying`, cancel, result path/size/duration/tracks) and `media_import_sheet.gd` (audio/video, copy, proxy fps/max width, unsupported reason). UI tests in `media.gd`.
- [ ] Run `media.gd` green; run parse + smoke. Do not claim MP4 works without device evidence.

**Task B6 — Commit and report**

```bash
git add studio/src/core/media_system.gd studio/src/core/audio_library.gd studio/src/core/video_reference.gd \
  studio/src/core/gif_encoder.gd studio/src/core/sequence_renderer.gd studio/src/core/camera_export.gd studio/src/core/android_video.gd \
  studio/src/ui/media_lanes.gd studio/src/ui/audio_sheet.gd studio/src/ui/video_reference_panel.gd \
  studio/src/ui/media_export_sheet.gd studio/src/ui/media_import_sheet.gd \
  studio/android/app/java/studio/kinema/media scripts/stage-android.sh \
  studio/tests/media.gd studio/tests/media.tscn
git commit -m "feat(media): add audio, video reference, GIF, MP4 and camera export"
```

**Report contract:** status, commits, RED evidence, `media.gd` PASS with OK/FAIL counts, parse/smoke evidence, what is Linux-tested vs device-only, and concerns.

---

## Workstream C — Rigging

**Goal:** Real skeletons, distance auto-weights, bind/unbind, FABRIK IK, pose library, bone animation, and the rig tab/overlay.

**Files owned:** `src/core/rig_system.gd`, `skinning.gd`, `ik_solver.gd`, `pose_library.gd`, `src/ui/rig_panel.gd`, `bone_tree.gd`, `pose_panel.gd`, `ik_panel.gd`, `rig_overlay.gd`, `tests/rig.gd`, `tests/rig.tscn`.

**Must not touch:** `document.gd`, `editor.gd`, `smoke.gd`, `layout.gd`, `capture.gd`, animation/media files.

**Contract consumed:** `Document.insert_bone_key/get_bone_keys/delete_bone_key/sample_bone/insert_pose_keys`, `doc.animation` (active clip), `doc.nodes`, `doc.project_dir`, `doc.begin_edit/end_edit`, `doc.imported_scene_ready`, `EditorView.world_to_screen/screen_ray`.

**Task C1 — Rig model, skeleton build, bone editing**

- [ ] RED: rig data roundtrip; create rig with Root; add child bone; reparent; reject cycles; rename; delete blocked while children/skin/IK/pose reference; rest changes rebuild `Skeleton3D` and preserve existing pose.
- [ ] Implement `rig_system.gd` model + `Skeleton3D` build. Rig objects are `kind:"rig"` with a `Skeleton3D` named `Skeleton3D`. Bone records are parent-first local rest transforms with `influence_scale`; active bone; active rig. Serialize per §8.1.
- [ ] Build `bone_tree.gd` (44 dp rows, indent 12, parent/child, add/rename/reparent/delete with guards) and the bone-inspector part of `rig_panel.gd` (rest p/r/s, length, influence scale, reset pose).
- [ ] UI tests in `rig.gd`: rig tab builds, bone rows, add bone, empty state, 44 dp controls.
- [ ] Run `rig.gd` green; run parse + smoke.

**Task C2 — Skinning and bind job**

- [ ] RED: auto-weight test with a 2-bone chain and a 1k-vertex mesh; assert weight sums 1, nearest bone dominates, max 4 influences, 50k limit error. Bind test: mesh and rig remain siblings (no reparent), mesh global transform equals rig global transform, `ArrayMesh` has `ARRAY_BONES`/`ARRAY_WEIGHTS`, `Skin` bind count equals vertex count. Unbind test: static mesh restored from saved source/transform.
- [ ] Implement `skinning.gd`: mesh arrays, vertex transform to rig space, distance-to-bone-segment weights `1/(d+0.001)^2 * influence_scale`, top 4, normalize, binary sidecar `<project>/skins/<rig_id>_<mesh_id>_<hash>.bin` with version/count/influences, uint16 bones, float32 weights; metadata in JSON per §17.3. Implement `start_bind/poll_bind/cancel_bind` as a chunked main-thread job (500 vertices/frame) with real progress; `unbind_mesh` restores source/transform.
- [ ] Build the bind UI in `rig_panel.gd`: mesh picker, Bind/Rebind/Unbind, progress, `Bound N vertices · 4 influences · M bones`, `influence_scale` field with "Rebind to apply" note. UI tests in `rig.gd`.
- [ ] Run `rig.gd` green; run parse + smoke.

**Task C3 — FABRIK IK**

- [ ] RED: 2-bone chain reachable → end effector within 1e-3; unreachable → chain straight toward target at max length; weight 0 → unchanged; pole angle changes the plane; iterations 8–24; tolerance 0.001.
- [ ] Implement `ik_solver.gd` per §8.4: world head/tail from `Skeleton3D.get_bone_global_pose`, backward/forward reach, clamp, convert world positions to local rotations using rest/parent, weight blend, pole vector. Implement rig-system chain CRUD, `solve_ik`, `bake_ik` (one undo step), and `advance()` hook. Apply after mixer, before render; `sequence_renderer` calls `solve_ik()` before capture.
- [ ] Build `ik_panel.gd`: chain rows, root/end dropdowns, target picker with empty state, weight, pole angle, iterations, enabled, Bake; 44 dp controls. UI tests in `rig.gd`.
- [ ] Run `rig.gd` green; run parse + smoke.

**Task C4 — Pose library and bone animation**

- [ ] RED: save pose captures all bone rotations + root position; apply sets pose; key pose writes rotation keys for all bones at `current_time` as one undo step; rename/delete; bone key sample/delete; pose survives save/load.
- [ ] Implement `pose_library.gd` and the pose part of `rig_system.gd`. Use `Document.insert_bone_key/get_bone_keys/delete_bone_key/sample_bone/insert_pose_keys`.
- [ ] Build `pose_panel.gd`: 2-column grid Compact / 3-column Studio+, 44 dp chips, name + bone count, apply/key/delete, empty state "No poses yet. Pose the rig, then Save pose.", search when > 12. UI tests in `rig.gd`.
- [ ] Run `rig.gd` green; run parse + smoke.

**Task C5 — Rig overlay**

- [ ] Build `rig_overlay.gd`: draws bones 2 px TEXT_MUTED, selected FOCUS, joints 6 px, hit radius 22 dp; tap selects, drag rotates around head using screen-space trackball; IK target dashed 1 px + 44 dp handle; `mouse_filter = PASS` when not in rig mode. Use `EditorView.world_to_screen/screen_ray`; do not edit `editor_view.gd`.
- [ ] UI test: overlay hit test selects the nearest bone within 22 dp; outside does not; overlay does not consume orbit when disabled.
- [ ] Run `rig.gd` green; run parse + smoke.

**Task C6 — Commit and report**

```bash
git add studio/src/core/rig_system.gd studio/src/core/skinning.gd studio/src/core/ik_solver.gd studio/src/core/pose_library.gd \
  studio/src/ui/rig_panel.gd studio/src/ui/bone_tree.gd studio/src/ui/pose_panel.gd studio/src/ui/ik_panel.gd studio/src/ui/rig_overlay.gd \
  studio/tests/rig.gd studio/tests/rig.tscn
git commit -m "feat(rig): add skeletons, auto weights, IK and pose library"
```

**Report contract:** status, commits, RED evidence, `rig.gd` PASS with OK/FAIL counts, parse/smoke evidence, what is math-tested vs GPU/device-only, and concerns.

---

## Integration Task I — Shell, persistence, cascade, CI

**Goal:** Wire the four workstreams into the real shell, finish cross-subsystem behavior that belongs to `Document`, and produce the final evidence.

**Files owned:** `src/core/document.gd`, `project_store.gd`, `app/main.gd`, `src/app/editor.gd` (wiring), `tests/smoke.gd`, `tests/layout.gd`, `tests/capture.gd`, `.github/workflows/build.yml`, `README.md`, `BUILD.md`.

**Task I1 — Shell wiring**

- [ ] Add `ClipLane` above the timeline; `MediaLanes` below the dope sheet; `RigPanel` as a dock tab next to Scene/Props. Rig tab is always present with an empty state.
- [ ] Add `Rig`, `Audio`, `Video reference` to the Add sheet. Replace the render sheet with `MediaExportSheet` while keeping quick still/render mode. Add Settings categories `Media` and `Rig`. Update Workspace descriptions.
- [ ] Transport: clip lane play sequence ↔ `doc.play_sequence`; timeline play clip ↔ `doc.play`; while sequence playing, timeline transport shows the active strip's local time and clip play is disabled; audio/video follow sequence only.
- [ ] Viewport: `RigOverlay` sibling of `EditorView`, enabled when the Rig tab is active, disabled in render mode. `VideoReferenceOverlay` below the HUD, disabled in render mode. `ViewportHeader` actions wired to Perspective/Add/Grid/Frame.
- [ ] Ensure no two clocks: `doc.seek/play/pause/stop` clear sequence state; `doc.play_sequence` disables clip transport; stopping sequence restores clip local time.
- [ ] Run parse + smoke + layout headless + layout xvfb. Expected: PASS.

**Task I2 — Persistence and cascade**

- [ ] Remove the legacy `"animation"` mirror from `to_data()` once WS-A returns real clips. Assert saved v2 has `format:2`, `clips`, `layers`, `rigs`, `media`, and no `animation`.
- [ ] Implement §17.10 cascade:
  - Delete object: remove tracks from every clip; if rig, unbind meshes, delete bone tracks, poses, IK; if bound mesh, delete skin record.
  - Rename object: remap `<old>:` and `<old>/Skeleton3D:` in every clip.
  - Rename bone: update rig, skin `bone_names`, IK root/end, pose keys, bone track paths; rebuild skeleton.
  - Reparent bone: reject cycles; preserve global rest; rebuild; skins use names.
  - Delete bone: block if children, skin, IK, or pose references; list references.
  - Delete rig: unbind meshes; delete tracks/poses/IK.
  - Delete clip: block if strips reference it; duplicate deep-copies the Animation.
  - Delete layer: block if last; delete strips with confirm.
  - Delete IK target: disable chain + warning, do not delete the chain.
- [ ] Add smoke/rig/animation tests for each cascade rule. Use the existing `begin_edit/end_edit` one-step undo.
- [ ] Run all suites. Expected: PASS.

**Task I3 — CI and final evidence**

- [ ] Update `.github/workflows/build.yml`: add a `test` job before `build` that downloads Godot 4.7.2-stable Linux x86_64, verifies the version, runs parse, smoke, animation, media, rig, layout headless, layout xvfb; upload logs/captures. `build` runs after test, stages Java, runs `assembleStandardDebug`, uploads the APK. A test failure blocks the APK.
- [ ] Verify the staged Java source exists before Gradle; verify the APK package `studio.kinema.app`, `lib/arm64-v8a/libgodot_android.so`, and the Java class in the dex (minimum check).
- [ ] Update `README.md`/`BUILD.md`: features, limitations (no weight painting, video is a frame proxy, MP4 is Android-only, no device claims), local checks, device checklist.
- [ ] Run the full local suite: parse, smoke, animation, media, rig, layout headless, layout xvfb, captures for `clips`, `layers`, `audio`, `video`, `rig`, `pose`, `media-export`, `gif`, `camera` at 412×915, 915×412, 1440×900.
- [ ] Inspect captures for clipping/overlap/44 dp; fix.
- [ ] Final whole-branch review: spec compliance + quality. Fix Critical/Important findings. Do not claim APK/device/MP4 success without CI/device evidence.

**Commit:**

```bash
git add studio/src/app/editor.gd studio/src/core/document.gd studio/src/core/project_store.gd studio/src/app/main.gd \
  studio/tests/smoke.gd studio/tests/layout.gd studio/tests/capture.gd .github/workflows/build.yml README.md BUILD.md
git commit -m "feat: integrate clips, media and rigging into the workbench"
```

---

## Acceptance Gates

- **Parse:** `timeout 120 "$GODOT" --headless --path studio --quit-after 4` → 0 errors.
- **Smoke:** `timeout 300 "$GODOT" --headless --path studio res://tests/smoke.tscn` → `SMOKE RESULT: PASS`, 0 FAIL, OK count ≥ contract baseline + new checks.
- **Animation:** `timeout 300 "$GODOT" --headless --path studio res://tests/animation.tscn` → `ANIMATION RESULT: PASS`, 0 FAIL.
- **Media:** `timeout 300 "$GODOT" --headless --path studio res://tests/media.tscn` → `MEDIA RESULT: PASS`, 0 FAIL.
- **Rig:** `timeout 300 "$GODOT" --headless --path studio res://tests/rig.tscn` → `RIG RESULT: PASS`, 0 FAIL.
- **Layout headless:** `timeout 300 "$GODOT" --headless --path studio res://tests/layout.tscn` → `LAYOUT RESULT: PASS`.
- **Layout xvfb:** `timeout 300 xvfb-run -a -s "-screen 0 2560x1600x24" "$GODOT" --path studio res://tests/layout.tscn` → `LAYOUT RESULT: PASS`.
- **Captures:** 412×915, 915×412, 1440×900 for every new action; no clipping/overlap; all touch controls ≥44 dp.
- **CI:** APK artifact exists, package `studio.kinema.app`, arm64-v8a, Java class present. Not claimed until the workflow actually runs.
- **Device:** user tests the checklist in §12.3; no device claim from this environment.

## Spec Coverage

| Spec area | Owning task |
|---|---|
| §5 tokens, icons, density | Task 0, D1–D2 |
| §6 clips, mixer, glTF, UI | A1–A4 |
| §7 audio, video, GIF, MP4, camera, renderer | B1–B5 |
| §8 rig, skinning, IK, poses, overlay | C1–C5 |
| §9 contract, API, ownership, worktrees | Task 0, merge protocol |
| §10 shell integration | I1 |
| §11 tests, CI | A1–A4, B1–B5, C1–C5, I3 |
| §12 risks/device checklist | I3, final report |
| §13 acceptance | all |
| §17 decisions | Task 0, A1–A4, B1–B5, C1–C5, I2 |
