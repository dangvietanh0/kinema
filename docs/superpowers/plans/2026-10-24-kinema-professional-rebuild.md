# Kinema Studio — Professional Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Kinema Studio's entire UI as a three-mode touch-first workbench, fix editing at an existing keyframe, and make renderer, performance, settings, render, and import real, tested surfaces that can be built into an Android APK by GitHub Actions.

**Architecture:** Keep the Godot 4.7.2 Android host, the internal JSON project format, and the existing document/render/import foundations. Extract deterministic logic into testable modules (`LayoutMath`, `Prefs`, `Perf`), split transform/key signals in `Document`, then rebuild the editor as a composition root over focused UI components. Every control reads or writes a real engine/document/store API; unsupported capabilities are disabled with an explicit reason, never faked.

**Tech Stack:** Godot 4.7.2-stable, GDScript, `SubViewport`, `Animation`, `Environment`, `RenderingServer`, SVG icons, JSON persistence, GitHub Actions + Gradle `assembleStandardDebug`, Android 15–17, arm64-v8a.

**Spec:** `docs/superpowers/specs/2026-10-23-kinema-professional-rebuild-design.md`

## Global Constraints

- Android 15–17; Godot 4.7.2-stable; package `studio.kinema.app`; ABI `arm64-v8a`; Gradle task `assembleStandardDebug`; CI debug keystore. Do not build an APK outside GitHub Actions.
- UI copy is English. Single selection only. No Save As, no multi-select, no light theme, no localization, no cloud/network.
- Geometry: 0 px corners on panels/inputs/buttons/sheets; 1 px hairlines; type 11–13 sp; every number/timecode uses JetBrains Mono; every action has a **44 dp logical** hit target (48 dp for primary/transport); no shadows, blur, glass, gradients, or decorative illustration.
- Colour semantics: cool FOCUS blue (`#4C8DE6`) for UI selection/actions/focus; amber TIME (`#D9A565`) only for keys, playhead, transport, and 3D selection. `TEXT_DIM` is disabled/decorative only.
- Three modes `compact`, `studio`, `desktop` are always selectable. `Auto` resolves from **device dp** (`physical / density`, before user scale): `<600` Compact, `600–959` Studio, `>=960` Desktop. Breakpoints 600/960; panel policy uses layout width after scale.
- `base_factor = density`; `user_scale` 0.85–1.30 step 0.05; `content_scale_factor = base_factor × user_scale` before fit. Compact/Studio keep at least 320×480 logical. Desktop shrink-to-fit has **no floor**: reduce the factor uniformly until the logical canvas is at least 960×600. Desktop on a phone never falls back to Studio. When Desktop fit `<100%`, disable user scale and show the fit percentage plus a `Small UI` hint and a manual Studio suggestion below 60%.
- Desktop fit applies only while the editor is in Desktop; Home uses its own responsive layout; leaving Desktop restores the normal factor immediately.
- Android default renderer is **Mobile**; desktop/headless default is Forward+. `auto`, `forward_plus`, `mobile`, and `gl_compatibility` are selectable. Switching uses real restart args (`OS.set_restart_on_exit`), never an in-process fake switch.
- No MP4 encoder and no binary/ASCII FBX parser. MP4 is explicitly unsupported; FBX is disabled with a concrete conversion message. Render output is real PNG stills and a ZIP of PNG frames from the editor camera.
- Do not invent APIs or capabilities. If Godot cannot do it, disable the control and state why.
- Every task is TDD: write the failing test, run it, implement, run it green, run the full smoke/parse suite, commit. No completion claim without fresh command output.
- Respond to the user in Vietnamese; code, UI copy, and commit subjects are English.

## Review Focus

These are the five input classes most likely to break in production. Each has a test in the task that owns the behaviour.

1. **Editing an object while the playhead sits on an existing key, with autokey off.** Expected: the stored key updates, seeking back to it keeps the new pose, and undo restores both pose and key. Test in Task 1.
2. **Selecting Desktop on a 360×640 portrait phone.** Expected: still Desktop, uniformly shrunk, logical canvas ≥960×600, visible fit percentage, no fallback or overflow. Tests in Tasks 3, 6, and 14.
3. **Tapping or dragging inside a sheet, especially near its edge.** Expected: the sheet stays open; only scrim/back/close/drag-handle dismiss it. Test in Task 5.
4. **Long project/object names at 0.85 user scale and short height.** Expected: titles ellipsize, rows never push the layout wider, and no visible control leaves its parent. Tests in Tasks 4, 8, and 14.
5. **Choosing a renderer the device cannot start or whose backend falls back.** Expected: one bounded retry, platform-default fallback, real backend shown with a warning, no restart loop. Test in Task 11.

## File Structure

New files:

- `studio/src/app/layout_math.gd` — pure density/device-dp/auto-mode/fit calculations.
- `studio/src/core/prefs.gd` — autoload `Prefs`; `user://settings.json`, defaults, clamp, atomic save, migration.
- `studio/src/core/perf.gd` — autoload `Perf`; 4 Hz real samples, frame graph samples, adaptive preview scale, max FPS/V-Sync.
- `studio/src/ui/tokens.gd` — colour/type/spacing/hit-target tokens. `Kit` re-exports them.
- `studio/src/ui/components/top_bar.gd` — Compact/Studio top bar and Desktop menu bar.
- `studio/src/ui/components/tool_rail.gd` — Select/Move/Rotate/Scale, Frame, Add; mode-aware width.
- `studio/src/ui/components/status_bar.gd` — Desktop FPS/frame/renderer/count/save/fit readout.
- `studio/src/ui/components/bottom_bar.gd` — Compact `Add / Scene / Props / Timeline`.
- `studio/src/ui/components/perf_overlay.gd` — full FPS/frame-time/draw-call graph overlay.
- `studio/src/ui/settings_panel.gd` — one settings screen with category navigation.
- `studio/src/ui/render_panel.gd` — still/sequence render sheet and progress/cancel.
- `studio/src/ui/import_panel.gd` — glTF/GLB, OBJ+MTL, disabled FBX, options, SAF note.
- `studio/src/ui/workspace_sheet.gd` — Auto/Compact/Studio/Desktop selector and fit explanation.
- `studio/tests/layout.gd`, `studio/tests/layout.tscn` — size × mode layout matrix, overflow, hit targets, Desktop fit.
- `studio/tests/render.gd`, `studio/tests/render.tscn` — real still/sequence render under xvfb, file/image/ZIP verification.
- `studio/tests/capture.gd`, `studio/tests/capture.tscn` — reusable xvfb screenshot capture for the QA matrix.

Modified files:

- `studio/src/core/document.gd` — key-at-playhead rule, changed-channel detection, split signals.
- `studio/src/core/gfx.gd` — renderer preference/pending/retry, restart args, capability matrix, full graphics settings.
- `studio/src/core/project_store.gd` — `list_projects()`, `project_size()`, import options.
- `studio/src/core/obj_importer.gd` — optional material/texture loading.
- `studio/src/core/render_export.gd` — only if sequence verification needs a helper; ZIP path stays.
- `studio/src/viewport/editor_view.gd` — update policy, preview cap/scale, HUD, transform signal.
- `studio/src/app/main.gd` — new scale/fit formula, safe area, orientation, Perf/Prefs startup.
- `studio/src/app/home.gd` — project browser list/table, real all-project data, no hero/cards.
- `studio/src/app/editor.gd` — composition root; mode layout; keep `doc`, `_view`, `_timeline`, `_overlay`, `_settings_duration_field`, `_settings_fps_field`, `_preset_buttons` as test seams.
- `studio/src/ui/kit.gd` — re-export tokens; 0 px theme; shared constructors.
- `studio/src/ui/overlay.gd` — sheet/modal variants, max-height, drag handle, inside-tap contract.
- `studio/src/ui/outliner.gd` — dense rows, filters, inline rename, row spies.
- `studio/src/ui/inspector.gd` — sections, key states, lightweight transform updates, section spies.
- `studio/src/ui/timeline.gd` — transport/dope/graph rebuild, ghost unkeyed key, mode density.
- `studio/project.godot` — Prefs/Perf autoloads; `renderer/rendering_method.mobile="mobile"`.
- `studio/tests/smoke.gd` — logic, signal, settings, render, import regressions.
- `scripts/stage-android.sh` — required new runtime files.
- `.github/workflows/build.yml` — APK package/ABI/signature/assets verification.
- `README.md`, `BUILD.md` — modes, renderer default, limitations, local checks, device checklist.

## Spec Coverage

| Spec area | Owning tasks |
|---|---|
| 5 visual system, tokens, icons | 4 |
| 6 modes, Auto, Desktop fit, safe area, short height | 3, 6, 11, 14 |
| 7.1–7.6 top bar, rail, HUD, outliner, inspector, timeline | 6, 7, 8, 9, 10 |
| 7.7 sheet/modal contract | 5 |
| 7.8 settings surfaces | 11 |
| 7.9–7.10 render and import sheets | 13 |
| 7.11 Home project browser | 12 |
| 8 interaction, back, gestures | 1, 5, 6, 8, 9, 10 |
| 9 performance, adaptive preview | 2, 7, 14 |
| 10–11 renderer and graphics | 7, 11 |
| 12 settings catalog | 3, 11 |
| 13 render/export/import | 13 |
| 14 visual QA | 14 |
| 15 tests, CI, acceptance | 1–15, with CI checks in 15 |

---

### Task 1: Update the existing key at the playhead

**Files:**
- Modify: `studio/src/core/document.gd:887-1037`
- Test: `studio/tests/smoke.gd` (after the easing block, before `SMOKE STEP: graph editor`)

**Interfaces:**
- Consumes: `Document.add_primitive()`, `insert_transform_keys()`, `get_channel_keys()`, `get_key_transition()`, `begin_edit()`, `end_edit()`, `undo()`, `redo()`, `seek()`.
- Produces: unchanged public `set_object_transform(id: String, position: Vector3, rotation: Quaternion, p_scale: Vector3, key: bool = true)`. New private helpers `_key_index_at(id: String, channel: String, time: float) -> int` and `_write_key(id: String, channel: String, value: Variant, mode: String) -> int`, where `mode` is `"update_or_insert"`, `"insert_only"`, or `"update_only"`.

- [ ] **Step 1: Write the failing regression test**

Add this block to `smoke.gd` after the easing checks:

```gdscript
	print("SMOKE STEP: keyframe at playhead")
	var key_id: String = doc.add_primitive("cube", Vector3(3.0, 0.0, 0.0))
	doc.set_selection(key_id)
	doc.set_autokey(false)
	doc.seek(0.0)
	doc.set_object_transform(key_id, Vector3(1.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE, false)
	doc.insert_transform_keys()
	doc.seek(2.0)
	doc.set_object_transform(key_id, Vector3(2.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE, false)
	doc.insert_transform_keys()
	doc.set_key_transition(key_id, "position", 1, 0.75)
	doc.begin_edit("Move keyed object")
	doc.set_object_transform(key_id, Vector3(5.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE)
	doc.end_edit()
	var key_b: Array = doc.get_channel_keys(key_id, "position")
	_check(key_b.size() == 2, "editing at key B does not create a duplicate")
	_check(absf((key_b[1]["value"] as Vector3).x - 5.0) < 0.0001, "editing at key B updates stored key")
	_check(is_equal_approx(doc.get_key_transition(key_id, "position", 1), 0.75), "key update preserves easing")
	doc.seek(0.0)
	doc.seek(2.0)
	_check(absf((doc.get_object_transform(key_id)["position"] as Vector3).x - 5.0) < 0.0001, "seek after key update keeps value")
	doc.undo()
	await get_tree().process_frame
	_check(absf((doc.get_object_transform(key_id)["position"] as Vector3).x - 2.0) < 0.0001, "undo restores key B pose")
	doc.redo()
	await get_tree().process_frame
	_check(absf((doc.get_object_transform(key_id)["position"] as Vector3).x - 5.0) < 0.0001, "redo restores key B edit")

	doc.set_autokey(false)
	doc.seek(1.0)
	doc.set_object_transform(key_id, Vector3(7.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE)
	_check(doc.get_channel_keys(key_id, "position").size() == 2, "autokey off does not create a key")
	doc.seek(2.0)
	_check(absf((doc.get_object_transform(key_id)["position"] as Vector3).x - 5.0) < 0.0001, "unkeyed pose yields to animation")
	doc.set_autokey(true)
	doc.seek(1.0)
	doc.set_object_transform(key_id, Vector3(7.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE)
	_check(doc.get_channel_keys(key_id, "position").size() == 3, "autokey on inserts a missing key")
	doc.set_autokey(false)
```

- [ ] **Step 2: Run the test and verify it fails for the right reason**

Run:
```bash
GODOT=/data/data/com.termux/files/home/tools/Godot_v4.7.2-stable_linux.arm64
"$GODOT" --headless --path /root/kinema/studio res://tests/smoke.tscn
```
Expected: FAIL containing `editing at key B updates stored key`. Before the fix, the node shows `(5,0,0)` until seek, then the stored key snaps it back to `(2,0,0)`.

- [ ] **Step 3: Implement update-or-insert**

In `document.gd`, implement `_key_index_at()` as `get_key_index_at(id, channel, time, 0.5 / float(maxi(1, fps)))`. Implement `_write_key()` so `update_only`/`update_or_insert` call `set_key_value()` when an index exists, and `insert_only`/`update_or_insert` call `_insert_track_value()` only when no key exists. Preserve the existing transition when updating.

Change `set_object_transform()` to compare the incoming pose with the current node pose before applying it, collect changed channels into a `PackedStringArray` using the spec epsilons (position 1e-5, rotation 0.01°, scale 1e-5), then:
1. apply the pose and update the object record;
2. if `_loading`, stop;
3. for each changed channel, update an existing key at the playhead with `_write_key(..., "update_only")`;
4. if no key existed and `key and autokey`, insert with `_write_key(..., "insert_only")`;
5. leave `key=false` as a pure pose write (smoke setup relies on it).

Refactor `_key_selected_transform()`, `insert_channel_key()`, and `insert_transform_keys()` to use `_write_key(..., "update_or_insert")` so the KEY button always updates an existing key and inserts a missing one. Do not call `begin_edit()`/`end_edit()` from these helpers when the caller already owns an edit.

- [ ] **Step 4: Run the regression and the full suite**

Run the smoke command from Step 2, then:
```bash
"$GODOT" --headless --path /root/kinema/studio --quit-after 4
```
Expected: `SMOKE RESULT: PASS` and no parse errors.

- [ ] **Step 5: Commit**

```bash
git add studio/src/core/document.gd studio/tests/smoke.gd
git commit -m "fix: update existing keys at the playhead"
```

---

### Task 2: Split refresh signals and stop idle preview rendering

**Files:**
- Modify: `studio/src/core/document.gd` (signals and emit sites)
- Modify: `studio/src/viewport/editor_view.gd`
- Modify: `studio/src/ui/outliner.gd`, `studio/src/ui/inspector.gd`, `studio/src/ui/timeline.gd`
- Create: `studio/src/core/perf.gd`
- Modify: `studio/project.godot` (add `Perf` autoload)
- Test: `studio/tests/smoke.gd`

**Interfaces:**
- Consumes: Task 1's `set_object_transform()` changed-channel list.
- Produces:
  - `Document.transform_changed(id: String, channels: PackedStringArray)`.
  - `Document.keyframes_changed(id: String, channel: String)`; empty `channel` means all channels.
  - `EditorView.set_interactive(active: bool) -> void`, `request_preview_update() -> void`, `set_preview_cap(long_edge: int) -> void`, `set_preview_scale(scale: float) -> void`, `preview_size() -> Vector2i`.
  - `Perf.next_preview_scale(current: float, measured_fps: float, target_fps: int, min_scale: float) -> float`, `Perf.reset_stats()`, signal `Perf.sample_updated(sample: Dictionary)`, fields `fps`, `frame_ms`, `process_ms`, `physics_ms`, `draw_calls`, `primitives`, `samples`, `preview_scale`, `max_fps`, `vsync`, `adaptive_quality`, `preview_update`, `preview_cap`.

- [ ] **Step 1: Write the failing signal/performance test**

Add to `smoke.gd` after the Task 1 keyframe block and before the graph-editor block:

```gdscript
	print("SMOKE STEP: refresh and preview policy")
	var view = editor._view
	view.set_interactive(false)
	view.request_preview_update()
	_check(view._viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "idle preview requests one frame")
	await get_tree().process_frame
	_check(view._viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "idle preview stops rendering")
	view.set_interactive(true)
	_check(view._viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "gesture preview renders continuously")
	view.set_interactive(false)
	_check(view._viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "gesture end stops continuous preview")

	doc.set_selection(ease_id)
	await get_tree().process_frame
	var outliner_before: int = editor._outliner.rebuild_count
	var inspector_sections_before: int = editor._inspector.section_build_count
	var old_pose: Vector3 = doc.get_object_transform(ease_id)["position"]
	doc.set_object_transform(ease_id, old_pose + Vector3(0.25, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE)
	await get_tree().process_frame
	_check(editor._outliner.rebuild_count == outliner_before, "transform does not rebuild the outliner")
	_check(editor._inspector.section_build_count == inspector_sections_before, "transform does not rebuild inspector sections")
	_check(Perf.next_preview_scale(1.0, 20.0, 60, 0.6) < 1.0, "adaptive quality lowers preview scale")
	_check(Perf.next_preview_scale(0.8, 70.0, 60, 0.6) > 0.8, "adaptive quality raises preview scale when there is headroom")
	_check(is_equal_approx(Perf.next_preview_scale(0.6, 20.0, 60, 0.6), 0.6), "adaptive quality respects the floor")
```

- [ ] **Step 2: Run the test and verify it fails**

Run the smoke command from Task 1. Expected: failure at `idle preview requests one frame` or `Perf` is not defined.

- [ ] **Step 3: Add signals and change emit sites**

Add the two signals. Emit `transform_changed` only from `set_object_transform()`, with the exact changed channels. Emit `keyframes_changed` from key insert/update/delete/retime/transition sites. Keep `object_changed` for rename, visibility, material, light, camera FOV, and other non-transform properties. Update `editor_view.gd`, `outliner.gd`, `inspector.gd`, and `timeline.gd` listeners: outliner ignores transform changes; inspector refreshes values only; timeline redraws keys only; viewport requests one preview frame and redraws its 2D overlay.

Add `rebuild_count` to `outliner.gd`, incremented at the start of `_build()`, and `section_build_count` to `inspector.gd`, incremented in `_rebuild()`.

- [ ] **Step 4: Add `Perf` and the preview update policy**

Create `perf.gd` as an autoload. Sample `Performance.get_monitor(Performance.TIME_FPS)`, `TIME_PROCESS`, `TIME_PHYSICS`, `OBJECT_NODE_COUNT`, `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, and `RENDER_TOTAL_PRIMITIVES_IN_FRAME`; do not invent missing values. Keep 120 frame-time samples and emit `sample_updated` every 0.25 s. `next_preview_scale()` lowers by 0.10 below 80% of target and raises by 0.05 above 95%, clamped to `min_scale..1.0`; the autoload adds a 1 s cooldown and applies the result to `EditorView`.

In `editor_view.gd`, start the preview at `UPDATE_ONCE`, call `set_interactive(true)` for orbit/pan/zoom/gizmo/playback and `false` when the gesture/playback ends, and call `request_preview_update()` for transform/material/light/camera changes. `_process()` must not call `queue_redraw()` unconditionally; redraw only while interactive or after a request. Compute the preview size from the control size, `preview_scale`, and `preview_cap` (long edge).

Register `Perf` in `project.godot` (Task 3 adds `Prefs`):
```ini
[autoload]
Perf="*res://src/core/perf.gd"
```

- [ ] **Step 5: Run the test and the full suite**

Run the smoke command. Expected: all new checks pass and `SMOKE RESULT: PASS`. Run the headless parse command from Task 1. Expected: no parse errors.

- [ ] **Step 6: Commit**

```bash
git add studio/src/core/document.gd studio/src/core/perf.gd studio/src/viewport/editor_view.gd \
  studio/src/ui/outliner.gd studio/src/ui/inspector.gd studio/src/ui/timeline.gd \
  studio/project.godot studio/tests/smoke.gd
git commit -m "perf: split refresh signals and render preview on demand"
```

---

### Task 3: Prefs, scale math, Desktop fit, and orientation

**Files:**
- Create: `studio/src/core/prefs.gd`
- Create: `studio/src/app/layout_math.gd`
- Modify: `studio/src/app/main.gd`
- Modify: `studio/project.godot`
- Test: `studio/tests/smoke.gd`

**Interfaces:**
- Consumes: `DisplayServer.window_get_size()`, `screen_get_dpi()`, `get_display_safe_area()`, `OS.get_name()`, `Prefs`.
- Produces:
  - `Prefs.get_value(key: String, default: Variant = null) -> Variant`, `Prefs.set_value(key: String, value: Variant, save: bool = true) -> void`, `Prefs.reset_section(section: String) -> void`, `Prefs.reset_all() -> void`, `Prefs.load_settings() -> void`, `Prefs.save_settings() -> void`, signal `changed(key: String, value: Variant)`, and a settable `settings_path`.
  - `LayoutMath.resolve(physical: Vector2i, dpi: float, platform: String, user_scale: float, mode_preference: String, fit_desktop: bool) -> Dictionary` with keys `mode`, `device_dp`, `base_factor`, `user_scale`, `logical_before`, `fit`, `fit_percent`, `factor`, `logical_after`, `clamped`, `user_scale_enabled`.
  - `LayoutMath.orientation_constant(value: String) -> int`.
  - `Main.refresh_layout_scale() -> Dictionary`, `Main.apply_orientation(value: String) -> bool`.

- [ ] **Step 1: Write the failing pure-logic tests**

Add to `smoke.gd` before editor setup:

```gdscript
	print("SMOKE STEP: layout math")
	var LayoutMathScript = load("res://src/app/layout_math.gd")
	_check(LayoutMathScript != null, "layout math module exists")
	if LayoutMathScript != null:
		var phone = LayoutMathScript.resolve(Vector2i(1080, 2400), 420.0, "Android", 1.0, "auto", true)
		_check(phone["mode"] == "compact", "auto resolves a phone to compact")
		var tablet = LayoutMathScript.resolve(Vector2i(1280, 800), 160.0, "Linux", 1.0, "auto", true)
		_check(tablet["mode"] == "desktop", "auto resolves a wide tablet to desktop")
		var phone_desktop = LayoutMathScript.resolve(Vector2i(1080, 2400), 420.0, "Android", 1.0, "desktop", true)
		_check(phone_desktop["mode"] == "desktop", "desktop is selectable on a phone")
		_check(phone_desktop["fit"] < 1.0, "desktop on a phone shrinks to fit")
		_check(phone_desktop["logical_after"].x >= 959.0 and phone_desktop["logical_after"].y >= 599.0, "desktop fit keeps 960x600 logical")
		_check(not phone_desktop["user_scale_enabled"], "desktop fit disables user scale")
		var desktop_min = LayoutMathScript.resolve(Vector2i(960, 600), 160.0, "Linux", 1.0, "desktop", true)
		_check(is_equal_approx(desktop_min["fit"], 1.0), "960x600 desktop has 100 percent fit")
		var scaled_phone = LayoutMathScript.resolve(Vector2i(360, 640), 160.0, "Android", 1.3, "compact", false)
		_check(scaled_phone["factor"] <= 1.125, "compact scale clamps to keep 320x480")
		_check(scaled_phone["logical_after"].x >= 319.0 and scaled_phone["logical_after"].y >= 479.0, "compact minimum canvas holds")
		_check(LayoutMathScript.orientation_constant("portrait") == DisplayServer.SCREEN_PORTRAIT, "portrait maps to the engine constant")
		_check(LayoutMathScript.orientation_constant("landscape") == DisplayServer.SCREEN_LANDSCAPE, "landscape maps to the engine constant")
		_check(not main.apply_orientation("portrait"), "orientation is disabled when the display server has no feature")

	print("SMOKE STEP: prefs persistence")
	var PrefsScript = load("res://src/core/prefs.gd")
	_check(PrefsScript != null, "prefs module exists")
	if PrefsScript != null:
		var test_path := "user://settings_test.json"
		var prefs_a = PrefsScript.new()
		prefs_a.settings_path = test_path
		prefs_a.load_settings()
		_check(prefs_a.get_value("display.layout", "") == "auto", "prefs provide display defaults")
		prefs_a.set_value("display.user_scale", 1.3)
		var prefs_b = PrefsScript.new()
		prefs_b.settings_path = test_path
		prefs_b.load_settings()
		_check(is_equal_approx(float(prefs_b.get_value("display.user_scale", 0.0)), 1.3), "prefs persist values")
		prefs_a.free()
		prefs_b.free()
		DirAccess.remove_absolute(test_path)
```

- [ ] **Step 2: Run the test and verify it fails**

Run the smoke command. Expected: failure at `layout math module exists` / `prefs module exists`.

- [ ] **Step 3: Implement `Prefs`**

Create the autoload with the following flat default keys. Unknown or malformed values fall back to the default and are clamped. Write atomically to `<path>.tmp` then rename; on parse failure rename the bad file to `<path>.bak`, reload defaults, and expose `last_error` for a toast.

```text
display.layout=auto  display.orientation=auto  display.user_scale=1.0
display.safe_area_preview=false  display.keep_screen_on=true  display.fullscreen=false
editor.autosave_seconds=30  editor.confirm_delete=true  editor.gizmo_size=1.0
editor.translate_snap=0.25  editor.rotate_snap=15.0  editor.scale_snap=0.25
editor.default_interpolation=cubic  editor.timeline_default=dope
editor.show_fps=true  editor.reduce_motion=false  editor.haptics=false
editor.collapsed_sections=[]  editor.project_sort=recent
performance.overlay=compact  performance.frame_graph=false
performance.adaptive_quality=true  performance.target_fps=60
performance.min_preview_scale=0.6  performance.preview_update=on_demand
performance.preview_cap=1920  performance.max_fps=60  performance.vsync=true
render.mode=still  render.resolution=1920  render.msaa=2  render.transparent=false
render.start_frame=0  render.end_frame=-1  render.output_dir=user://renders
import.scale=1.0  import.materials=true  import.textures=true
```

- [ ] **Step 4: Implement `LayoutMath` and wire `Main`**

`LayoutMath.resolve()`: density is `clamp(dpi/160, 1.0, 4.0)` on Android/iOS and `1.0` elsewhere; `device_dp = physical / density`; `auto` resolves by `device_dp.x`; `base_factor = density`; `logical_before = physical / (base_factor * user_scale)`; for Compact/Studio clamp the factor so the logical canvas stays at least 320×480; for Desktop with `fit_desktop=true`, `fit = min(1, logical_before.x/960, logical_before.y/600)` with no floor and `factor *= fit`; `fit_percent = fit * 100`; `user_scale_enabled = fit >= 1`. The function is pure and deterministic.

In `main.gd`, delete `BASE_WIDTH`, `BASE_HEIGHT`, and the `density/stretch` formula. Compute with `LayoutMath.resolve()`, set `get_window().content_scale_factor`, and divide safe-area insets by that factor. `fit_desktop` is true only when the editor is open and the resolved mode is Desktop. Add `refresh_layout_scale()` and call it on window resize, mode change, and user-scale change. `apply_orientation()` checks `DisplayServer.has_feature(DisplayServer.FEATURE_ORIENTATION)`; when unavailable, return false and let Settings disable the control with a reason.

Add `Prefs` to `[autoload]` before `Perf`.

- [ ] **Step 5: Run the test and the full suite**

Run smoke and parse. Expected: all new layout/prefs checks pass; `SMOKE RESULT: PASS`; no parse errors.

- [ ] **Step 6: Commit**

```bash
git add studio/src/core/prefs.gd studio/src/app/layout_math.gd studio/src/app/main.gd \
  studio/project.godot studio/tests/smoke.gd
git commit -m "feat: add prefs and deterministic desktop fit scaling"
```

---

### Task 4: Design tokens, sharp theme, and redrawn icons

**Files:**
- Create: `studio/src/ui/tokens.gd`
- Modify: `studio/src/ui/kit.gd`
- Modify: `studio/assets/icons/*.svg` (redraw the weak set; normalise stroke width)
- Test: `studio/tests/smoke.gd`

**Interfaces:**
- Consumes: existing `Kit` call sites.
- Produces: `Tokens` constants and `Kit` re-exports. `Kit.flat_style(color: Color, radius: int = 0, border: Color = BORDER, border_width: int = 1) -> StyleBoxFlat`; `Kit.icon_button(icon_name: String, tooltip: String = "", size: int = 44, icon_size: int = 20) -> Button`; `Kit.text_button(text_value: String, icon_name: String = "", primary: bool = false, compact: bool = false) -> Button` with a minimum height of 44 (48 primary); `Kit.hairline(vertical: bool = false) -> ColorRect`.

- [ ] **Step 1: Write the failing token/icon test**

Add to `smoke.gd` before editor setup:

```gdscript
	print("SMOKE STEP: tokens and icons")
	_check(Kit.BG.to_html(false).to_upper() == "0B0F14", "BG token is exact")
	_check(Kit.FOCUS.to_html(false).to_upper() == "4C8DE6", "FOCUS token is exact")
	_check(Kit.TIME.to_html(false).to_upper() == "D9A565", "TIME token is exact")
	var sharp := Kit.flat_style(Kit.SURFACE)
	_check(sharp.corner_radius_top_left == 0 and sharp.corner_radius_bottom_right == 0, "panels and inputs are square")
	_check(Kit.icon_button("play", "Play").custom_minimum_size == Vector2(44, 44), "icon buttons have a 44 dp hit target")
	_check(Kit.text_button("Render", "", true).custom_minimum_size.y >= 48.0, "primary buttons have a 48 dp hit target")
	for icon_name in [
		"play", "pause", "stop", "key-round", "diamond-plus", "speed-graph",
		"clapperboard", "upload", "tool-select", "tool-move", "tool-rotate",
		"tool-scale", "eye", "eye-closed", "lock", "unlock", "camera",
		"lightbulb", "box", "square-dashed", "smartphone", "tablet", "monitor",
		"gauge", "restart",
	]:
		var icon_path := "res://assets/icons/%s.svg" % icon_name
		_check(FileAccess.file_exists(icon_path), "icon exists: %s" % icon_name)
		if FileAccess.file_exists(icon_path):
			var svg := FileAccess.get_file_as_string(icon_path)
			_check(svg.contains("viewBox=\"0 0 24 24\""), "icon uses the 24 px grid: %s" % icon_name)
			_check(svg.contains("stroke-width=\"1.5\""), "icon uses a 1.5 px stroke: %s" % icon_name)
```

- [ ] **Step 2: Run the test and verify it fails**

Run smoke. Expected: failure at `BG token is exact` or the first missing icon.

- [ ] **Step 3: Implement tokens and the sharp theme**

Create `tokens.gd` with the exact colours from spec §5.2: `BG #0B0F14`, `SURFACE #11161D`, `SURFACE_2 #151B23`, `SURFACE_3 #1B232D`, `SURFACE_HOVER #202A36`, `BORDER #26303C`, `BORDER_SOFT #1A222C`, `TEXT #E8ECF2`, `TEXT_MUTED #8C97A8`, `TEXT_DIM #5F6B7C`, `FOCUS #4C8DE6`, `FOCUS_BRIGHT #6BA6F2`, `FOCUS_DARK #14243A`, `TIME #D9A565`, `TIME_BRIGHT #EDBE7F`, `WARNING #D98E5F`, `DANGER #D76C6C`, `SUCCESS #6FB68A`, `AXIS_X #D96962`, `AXIS_Y #7FB069`, `AXIS_Z #5B8FD9`, `SCRIM Color(0.008,0.02,0.031,0.62)`, `GRID Color(1,1,1,0.08)`, `GRID_MAJOR Color(1,1,1,0.16)`. Add spacing constants `SPACE_2/4/6/8/12/16/24/32`, hit targets `HIT=44`, `PRIMARY_HIT=48`, type sizes 10/11/12/13/18/22.

`Kit` preloads Tokens and aliases every colour so existing call sites keep working. Set the theme corner radius to 0 for Button, LineEdit, Panel, PopupMenu, TooltipPanel, ProgressBar, and focus rings. Remove all `radius` values from theme construction. Keep the existing font loading and variation logic; add Inter as the fallback for JetBrains Mono labels if a glyph is missing.

- [ ] **Step 4: Redraw and normalise icons**

Redraw the weak set with a 24×24 viewBox, `fill="none"`, `stroke="#FFFFFF"`, `stroke-width="1.5"`, round caps/joins for curved icons and miter joins for rectangular tool icons, and no decorative rays: play (balanced triangle), pause (two 3×12 bars), stop (square), key-round (10×10 diamond), diamond-plus (diamond + plus), speed-graph (axis + two-segment curve), clapperboard (16×12 board + two slashes), upload (arrow + tray), tool-select (four-way pointer), tool-move (crosshair arrows), tool-rotate (3/4 arc + arrow), tool-scale (square + diagonal arrow), eye/eye-closed, lock/unlock, camera, lightbulb, box, square-dashed, smartphone/tablet/monitor (same frame proportions), gauge, restart. Add missing files `stop.svg`, `diamond-plus.svg`, `tool-select.svg`, `tablet.svg`, `unlock.svg`, `restart.svg`. Replace `stroke-width="2"` and `stroke-width="1.8"` with `1.5` across the icon directory; do not change the drawings of icons outside the weak set.

- [ ] **Step 5: Run the test and parse check**

Run smoke; expected `SMOKE RESULT: PASS`. Run the headless parse command; expected no errors.

- [ ] **Step 6: Commit**

```bash
git add studio/src/ui/tokens.gd studio/src/ui/kit.gd studio/assets/icons studio/tests/smoke.gd
git commit -m "style: add sharp design tokens and redraw weak icons"
```

---

### Task 5: Sheet/modal contract and inside-tap regression

**Files:**
- Modify: `studio/src/ui/overlay.gd`
- Test: `studio/tests/smoke.gd`

**Interfaces:**
- Consumes: existing `show_modal(title, subtitle, body, actions)` call sites.
- Produces: `Overlay.set_layout_mode(mode: String) -> void`; `Overlay.show_sheet(title: String, subtitle: String, body: Control, actions: Array = [], options: Dictionary = {}) -> void`; `Overlay.panel_rect() -> Rect2` (global); `Overlay.body_rect() -> Rect2` (global); `Overlay.is_point_inside_panel(point: Vector2) -> bool`. `options` supports `variant` (`"sheet"`/`"modal"`), `max_height_ratio` (float), `draggable` (bool), `width` (float), `bottom_inset` (float), `on_close` (Callable).

- [ ] **Step 1: Write the failing inside-tap test**

Add to `smoke.gd` after the Task 2 refresh/preview block and before the existing graph-editor block, so the later Task 6–11 blocks can use `view`, `ease_id`, and `key_id`:

```gdscript
	print("SMOKE STEP: sheet contract")
	editor._overlay.set_layout_mode("compact")
	editor._open_add_sheet()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._overlay.has_modal(), "add sheet opens")
	var panel := editor._overlay.panel_rect()
	_check(panel.size.y <= editor.get_viewport_rect().size.y * 0.86 + 1.0, "compact sheet stays under 86 percent")
	for p in [
		panel.position + panel.size * 0.5,
		panel.position + Vector2(8, 8),
		panel.position + Vector2(panel.size.x - 8, 8),
		panel.position + Vector2(8, panel.size.y - 8),
		panel.position + Vector2(panel.size.x - 8, panel.size.y - 8),
	]:
		var inside := InputEventScreenTouch.new()
		inside.position = p
		inside.pressed = true
		editor.get_viewport().push_input(inside)
		await get_tree().process_frame
		_check(editor._overlay.has_modal(), "tap inside the sheet keeps it open")
	var outside := InputEventScreenTouch.new()
	outside.position = Vector2(2, 2)
	outside.pressed = true
	editor._overlay._on_backdrop_input(outside)
	await get_tree().process_frame
	_check(not editor._overlay.has_modal(), "scrim tap closes the sheet")
	editor._open_add_sheet()
	await get_tree().process_frame
	await get_tree().process_frame
	main._on_go_back()
	await get_tree().process_frame
	_check(not editor._overlay.has_modal(), "back closes the sheet before the editor")
```

- [ ] **Step 2: Run the test and verify it fails**

Run smoke. Expected: failure at `compact sheet stays under 86 percent` or an inside-tap assertion.

- [ ] **Step 3: Rebuild the overlay variants**

Keep one modal at a time and the existing toast slot. `show_modal()` delegates to `show_sheet()` with `variant="modal"`. In `compact` mode use a bottom sheet: 0 px corners, top hairline, drag handle 4×32, header 48 dp, body scroll, footer 48 dp plus `bottom_inset`, maximum height from `max_height_ratio` (default 0.86; Properties passes 0.72). In `studio`/`desktop` use a centred modal: width `min(options.width or 720, viewport_width - 48)`, height `min(640, viewport_height - 48)`. Only the scrim, close button, Escape/back, and drag handle can dismiss. Set `mouse_filter = STOP` on the panel, header, body host, and footer; never connect the panel root or body to `close_modal`.

Measure after two frames as today. Clamp all insets and heights to the viewport. Keep `_toast_anchor` and `_toast_modal` behaviour.

- [ ] **Step 4: Run the test and the full suite**

Run smoke. Expected all five inside taps keep the modal open, scrim tap closes it, and `SMOKE RESULT: PASS`.

- [ ] **Step 5: Commit**

```bash
git add studio/src/ui/overlay.gd studio/tests/smoke.gd
git commit -m "fix: enforce sheet and modal dismissal contract"
```

---

### Task 6: Editor shell, three modes, and chrome components

**Files:**
- Create: `studio/src/ui/components/top_bar.gd`
- Create: `studio/src/ui/components/tool_rail.gd`
- Create: `studio/src/ui/components/status_bar.gd`
- Create: `studio/src/ui/components/bottom_bar.gd`
- Modify: `studio/src/app/editor.gd`
- Modify: `studio/src/app/main.gd`
- Modify: `studio/project.godot` (no new autoload; wiring only)
- Test: `studio/tests/smoke.gd`

**Interfaces:**
- Consumes: `Document`, `EditorView`, `Timeline`, `Overlay`, `Prefs`, `Main.refresh_layout_scale()`, `Main.apply_orientation()`.
- Produces:
  - `TopBar.action_requested(action: String)`, `TopBar.layout_requested`, `TopBar.renderer_requested`, `set_mode(mode)`, `set_project(title, dirty, saved)`, `set_renderer(text, fallback)`, `set_fit(percent, small)`.
  - `ToolRail.tool_selected(tool)`, `frame_requested`, `add_requested`, `set_tool(tool)`, `set_mode(mode)`.
  - `StatusBar.update(sample: Dictionary, objects: int, keys: int, saved: bool, fit_percent: float)`, `set_mode(mode)`.
  - `BottomBar.action_requested(action)`, `set_mode(mode)`, `set_timeline_open(open)`.
  - `Editor.workspace_mode_changed(mode: String)`; `Editor.set_workspace_mode(mode: String)`; `Editor.workspace_mode() -> String`; `Editor.apply_fit_info(fit_percent: float, user_scale_enabled: bool, clamped: bool)`; `Editor.fit_percent() -> float`; fields `_top_bar`, `_bottom_bar`, `_status_bar`, `_dock`, `_viewport_host`.

- [ ] **Step 1: Write the failing shell test**

Add after the sheet-contract block:

```gdscript
	print("SMOKE STEP: workspace modes")
	editor.set_workspace_mode("compact")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor.workspace_mode() == "compact", "compact mode applies")
	_check(editor._bottom_bar.visible, "compact bottom action bar is visible")
	_check(editor._top_bar.size.y >= 47.0, "compact top bar is 48 dp")
	editor.set_workspace_mode("studio")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor.workspace_mode() == "studio", "studio mode applies")
	_check(editor._dock.visible, "studio dock is visible")
	_check(editor._top_bar.size.y >= 43.0, "studio top bar is 44 dp")
	editor.set_workspace_mode("desktop")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor.workspace_mode() == "desktop", "desktop mode applies on any screen")
	_check(editor._status_bar.visible, "desktop status bar is visible")
	_check(editor._top_bar.size.y >= 35.0 and editor._top_bar.size.y <= 38.0, "desktop menu bar is 36 dp")
	_check(str(Prefs.get_value("display.layout", "")) == "desktop", "workspace mode persists")
	editor.set_workspace_mode("compact")
	await get_tree().process_frame
```

- [ ] **Step 2: Run the test and verify it fails**

Run smoke. Expected: failure at `compact mode applies` or missing `_bottom_bar`.

- [ ] **Step 3: Build the four chrome components**

Implement the components as `PanelContainer` subclasses with the exact signals above. Top bar heights: Compact 48, Studio 44, Desktop 36. Compact shows back, title/dirty, overflow; Studio shows back, title/dirty, undo/redo, render, settings, overflow; Desktop shows `Kinema`, `Project`, `Edit`, `View`, `Render`, `Help`, then undo/redo, renderer chip, settings. Use real `PopupMenu`s with shortcuts in Desktop; overflow uses a `PopupMenu` in the other modes. Every icon-only button is 44×44 with `tooltip_text`. Desktop menu-bar items set `set_meta("qa_hit_exempt", true)`: the 36 dp bar is a mouse target, while every touch-mode action keeps a 44 dp target.

Tool rail: Select/Move/Rotate/Scale, divider, Frame, Add. Selected uses `FOCUS_DARK` background, `FOCUS_BRIGHT` icon, and a 2 px left `FOCUS` border. Every rail button is 44×44 with a 20 px icon; Desktop draws a 40 px visual cell inside the 44 px button. If height <480 in Compact, collapse to one 44×44 Tools button that opens the same actions.

Status bar: 24 dp, 10 sp mono, left `fps · frame ms · renderer`, right `objects · keys · saved · fit`. FPS colour follows the 55/30 thresholds. Clicking FPS emits `action_requested("performance")`; fit below 60% is `WARNING`.

Bottom bar: 48 dp, four equal actions `Add`, `Scene`, `Props`, `Timeline`; active Timeline state toggles.

- [ ] **Step 4: Recompose `editor.gd` and wire mode changes**

Keep the document/action methods and existing sheet entry points for now. Replace `_build_topbar`, `_build_body`, and `_build_compact_bar` with a mode-aware composition of `TopBar`, `ToolRail`, viewport host, outliner/inspector dock, timeline, status bar, and bottom bar. Keep the test seams `doc`, `_view`, `_timeline`, `_overlay`, `_viewport_host`, `_settings_duration_field`, `_settings_fps_field`, `_preset_buttons`. Do not delete or duplicate document mutation logic.

Layout rules: Compact top 48 + viewport + transport 52 + optional timeline 150 + bottom 48; timeline collapsed by default. Studio top 44 + rail 44 + viewport + dock `clamp(width*0.28, 280, 340)` + timeline 180. Desktop menu 36 + rail 40 + viewport + dock `clamp(width*0.26, 320, 380)` + timeline 220 + status 24. Height <520 switches the dock to Scene/Properties tabs and collapses the timeline to transport. `clip_contents = true` on the editor root.

`set_workspace_mode()` accepts `auto`, `compact`, `studio`, `desktop`, resolves Auto with `LayoutMath`, stores the preference in `Prefs`, rebuilds chrome, and emits `workspace_mode_changed`. `Main` connects that signal to `refresh_layout_scale()` and passes the resulting fit info back through `apply_fit_info()`. Do not fall back when Desktop is chosen on a small screen.

- [ ] **Step 5: Run smoke and the layout parse check**

Run smoke. Expected: all three modes apply, persist, and expose the correct chrome. Run the headless parse command; expected no errors.

- [ ] **Step 6: Commit**

```bash
git add studio/src/ui/components studio/src/app/editor.gd studio/src/app/main.gd studio/tests/smoke.gd
git commit -m "feat: rebuild editor shell with compact studio and desktop modes"
```

---

### Task 7: Viewport HUD, selection colour, and real lighting controls

**Files:**
- Create: `studio/src/ui/components/perf_overlay.gd`
- Modify: `studio/src/viewport/editor_view.gd`
- Modify: `studio/src/core/gfx.gd`
- Modify: `studio/src/core/document.gd` (light configuration call)
- Modify: `studio/src/app/editor.gd` (overlay host)
- Test: `studio/tests/smoke.gd`

**Interfaces:**
- Consumes: `Perf.sample_updated`, `Perf.samples`, `Document`, `Gfx.shadow_distance`, `Gfx.shadow_splits`, `Gfx.shadow_quality`.
- Produces: signals `EditorView.performance_requested`, `selection_info_requested`, `add_requested`; `EditorView.set_hud_mode(mode: String)`, `set_fps_value(fps: float, frame_ms: float)`, `set_preview_scale_indicator(scale: float)`, `refresh_empty_state()`. `PerfOverlay.open()`, `close()`, `set_sample(sample: Dictionary)`, `set_context(objects: int, keys: int)`; fields `_fps_label`, `_frame_label`, `_draw_label`, `_graph`. Editor alias `_perf_overlay`. `Gfx.configure_light(light: Light3D) -> void`.

- [ ] **Step 1: Write the failing HUD/lighting test**

Add after the workspace-mode block:

```gdscript
	print("SMOKE STEP: viewport HUD and lighting")
	view.set_hud_mode("desktop")
	_check(view._fps_chip != null, "FPS chip exists")
	_check(view._fps_chip.custom_minimum_size.x >= 44.0, "FPS chip has a 44 dp hit target")
	view.set_fps_value(60.0, 16.6)
	_check(view._fps_chip.text.contains("60"), "FPS chip shows the real sample")
	view.set_preview_scale_indicator(0.75)
	_check(view._preview_chip.visible, "preview scale indicator appears below 100 percent")
	view.set_preview_scale_indicator(1.0)
	_check(not view._preview_chip.visible, "preview scale indicator hides at 100 percent")
	view.performance_requested.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._perf_overlay != null and editor._perf_overlay.visible, "FPS chip opens the performance overlay")
	if editor._perf_overlay != null:
		editor._perf_overlay.set_sample({
			"fps": 60.0, "frame_ms": 16.6, "process_ms": 3.2,
			"draw_calls": 42, "primitives": 1200, "preview_size": Vector2i(960, 540),
		})
		_check(editor._perf_overlay._fps_label.text.contains("60"), "overlay shows the real FPS")
		_check(editor._perf_overlay._draw_label.text.contains("42"), "overlay shows real draw calls")
		editor._perf_overlay.close()
		_check(not editor._perf_overlay.visible, "overlay closes")
	var dir_light: DirectionalLight3D = null
	for obj in doc.objects:
		if str(obj.get("kind", "")) == "light" and str(obj.get("light_type", "")) == "directional":
			dir_light = doc.nodes[str(obj["id"])].find_children("*", "DirectionalLight3D", true, false)[0]
			break
	_check(dir_light != null, "study has a directional light")
	if dir_light != null:
		_check(dir_light.shadow_enabled, "directional light casts real shadows")
		_check(is_equal_approx(dir_light.directional_shadow_max_distance, Gfx.shadow_distance), "shadow distance follows graphics settings")
	_check(view.selection_color == Kit.TIME, "3D selection uses the TIME colour")
```

- [ ] **Step 2: Run the test and verify it fails**

Run smoke. Expected: failure at `FPS chip exists`.

- [ ] **Step 3: Rebuild the viewport HUD**

Replace the old HUD row with:

- top-left camera chip (`Persp`/`Front`/`Right`/`Top`) and grid toggle; 32 dp visual inside 44 dp buttons;
- top-right FPS chip; click emits `performance_requested`; colour thresholds `SUCCESS >=55`, `WARNING >=30`, `DANGER <30`;
- bottom-left one-line selection info (icon, name, kind, key count); click emits `selection_info_requested`;
- bottom-right `Preview 75%` chip, visible only when preview scale is below 1.0;
- centred empty state `Empty scene` with `Add object`, visible only when `doc.objects.is_empty()`;
- selection outline `TIME` at 1.5 px; hover at `TIME` 50%; gizmo axes keep `AXIS_X/Y/Z`.

Do not draw FPS text every frame. `set_fps_value()` is called from `Perf.sample_updated` at 4 Hz. Keep the existing orbit/pan/zoom/gizmo hit-testing and touch priority. HUD controls swallow input; they must not start an orbit.

- [ ] **Step 4: Build the full performance overlay**

Create `PerfOverlay` as a `PanelContainer` anchored top-right inside `_viewport_host`, 240×148 dp, `SURFACE` background, 1 px border, 0 px corners. It shows a large 22 sp mono FPS, 12 sp frame time, `UI 3.2 ms · 3D 11.8 ms` only when the split is measurable, `draw 42 · prim 1200`, preview resolution, renderer, preset, object/key count, and a 120-sample frame-time graph drawn in `_draw()` with a `FOCUS` line and no fill animation. `set_sample()` is called from `Perf.sample_updated` at 4 Hz, never per frame. `close()` hides it; `open()` shows it. The editor owns one instance; `view.performance_requested` toggles it. Settings `performance.overlay=off` hides the HUD chip, `compact` keeps the chip and overlay closed by default, `full` opens the overlay on entering the editor. Do not invent a 3D/UI split if `Performance` does not provide it; show `—`.

- [ ] **Step 5: Centralise real light configuration**

Add `Gfx.configure_light(light)` and call it from `Document._configure_shadows()`. It sets `shadow_enabled`, `directional_shadow_max_distance`, `directional_shadow_split_1/2/3` from the real settings, and leaves omni range/energy to the document. `Gfx.apply_all()` keeps applying environment/viewport settings and emitting `changed`; the editor's existing `Gfx.changed` handler calls `Document.apply_graphics()`, which re-applies every document light through `_configure_shadows()`. Do not add a new light group. Ensure `Gfx.default_environment()` does not overwrite a persisted exposure value.

- [ ] **Step 6: Run smoke and parse**

Run smoke. Expected `SMOKE RESULT: PASS`; run the parse command and expect no errors.

- [ ] **Step 7: Commit**

```bash
git add studio/src/ui/components/perf_overlay.gd studio/src/viewport/editor_view.gd \
  studio/src/core/gfx.gd studio/src/core/document.gd studio/src/app/editor.gd \
  studio/tests/smoke.gd
git commit -m "feat: rebuild viewport HUD and add a real performance overlay"
```

---

### Task 8: Outliner rows, filters, rename, visibility, and real lock

**Files:**
- Modify: `studio/src/ui/outliner.gd`
- Modify: `studio/src/core/document.gd` (persisted `locked` flag)
- Test: `studio/tests/smoke.gd`

**Interfaces:**
- Consumes: `Document.scene_changed`, `selection_changed`, `object_changed`; `Document.set_object_visible()`, `rename_object()`.
- Produces: `Outliner.rebuild_count`, `row_update_count`, `row_count() -> int`, `set_filter(kind: String)`, `row_for(id: String) -> Control`, `row_name_label(id: String) -> Label`; `Document.set_object_locked(id: String, locked: bool) -> void`, and `locked` persisted in the object record.

- [ ] **Step 1: Write the failing outliner test**

Add after the viewport HUD block, using the existing editor:

```gdscript
	print("SMOKE STEP: outliner")
	var outliner = editor._outliner
	var outliner_id: String = ease_id
	doc.set_selection(outliner_id)
	await get_tree().process_frame
	var row := outliner.row_for(outliner_id)
	_check(row != null, "outliner exposes the selected row")
	_check(row.size.y >= 44.0 or row.custom_minimum_size.y >= 44.0, "outliner rows are 44 dp")
	var row_rebuilds := outliner.rebuild_count
	doc.set_object_transform(outliner_id, Vector3(0.5, 0.5, 0.5), Quaternion.IDENTITY, Vector3.ONE)
	await get_tree().process_frame
	_check(outliner.rebuild_count == row_rebuilds, "transform does not rebuild outliner rows")
	doc.rename_object(outliner_id, "A very long object name that must not widen the dock")
	await get_tree().process_frame
	var name_label := outliner.row_name_label(outliner_id)
	_check(name_label.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "long outliner names ellipsize")
	doc.set_object_visible(outliner_id, false)
	_check(not bool(doc.get_object(outliner_id).get("visible", true)), "visibility writes the document")
	doc.set_object_visible(outliner_id, true)
	doc.set_object_locked(outliner_id, true)
	_check(bool(doc.get_object(outliner_id).get("locked", false)), "lock writes the document")
	var locked_pose: Vector3 = doc.get_object_transform(outliner_id)["position"]
	doc.set_object_transform(outliner_id, locked_pose + Vector3.ONE, Quaternion.IDENTITY, Vector3.ONE)
	_check((doc.get_object_transform(outliner_id)["position"] as Vector3).is_equal_approx(locked_pose), "locked objects reject transforms")
	doc.set_object_locked(outliner_id, false)
	var objects_before: int = outliner.row_count()
	doc.add_primitive("sphere", Vector3(1, 1, 1))
	await get_tree().process_frame
	_check(outliner.row_count() == objects_before + 1, "structural add rebuilds the outliner")
	_check(outliner.rebuild_count > row_rebuilds, "structural add increments rebuild count")
```

- [ ] **Step 2: Run the test and verify it fails**

Run smoke. Expected: failure at `outliner exposes the selected row` or `locked` missing.

- [ ] **Step 3: Add persisted lock semantics**

Add `locked` to `_base_object()`, `_normalize_object()`, and the serialized object. Implement `set_object_locked()` as one undo step, emit `object_changed`. Guard `set_object_transform()` and `delete_object()` when the object is locked; visibility and selection remain allowed. Do not hide the object when locked.

- [ ] **Step 4: Rebuild the outliner**

Header 44 dp: `Scene`, count, `+` 44×44. Search field appears when there are more than six objects; filter chips `All`, `Mesh`, `Light`, `Camera` (horizontal scroll when narrow). Rows 44 dp: indent, type icon 16, name 12 sp with ellipsis, visibility toggle 44×44 with a 32 px icon, lock toggle 44×44 with a 32 px icon, overflow 44×44. Selected uses `FOCUS_DARK` background, `TEXT` text, and a 2 px left `FOCUS` border. Double-tap/Enter starts inline rename; empty commit keeps the old name and toasts; Escape cancels. Long-press/right-click opens only real actions: Rename, Delete, Focus, Hide/Show, Lock/Unlock. No Duplicate because the document does not support it.

Rebuild only on `scene_changed`, selection change, rename, visibility/lock change, or filter change. `object_changed` for a row updates that row only. Transform never rebuilds. `row_update_count` increments on lightweight row updates.

- [ ] **Step 5: Run smoke and parse**

Run smoke. Expected all outliner checks pass, `SMOKE RESULT: PASS`, no parse errors.

- [ ] **Step 6: Commit**

```bash
git add studio/src/ui/outliner.gd studio/src/core/document.gd studio/tests/smoke.gd
git commit -m "feat: rebuild outliner with real lock and lightweight rows"
```

---

### Task 9: Inspector sections, key states, and unkeyed feedback

**Files:**
- Modify: `studio/src/ui/inspector.gd`
- Modify: `studio/src/core/document.gd` (key-state helpers)
- Test: `studio/tests/smoke.gd`

**Interfaces:**
- Consumes: `Document.CHANNELS`, `get_key_index_at()`, `sample_channel()`, `get_object_transform()`, `insert_channel_key()`, `delete_key()`.
- Produces: `Inspector.section_build_count`, `value_update_count`, `key_update_count`; `Inspector.key_state(id: String, channel: String) -> String` (`"keyed"`, `"empty"`, `"unkeyed"`); `Inspector.refresh_values()`, `refresh_keys()`; fields `_key_buttons`, `_key_all_button`, `_light_type_readonly`; `Document.has_key_at_playhead(id: String, channel: String) -> bool`, `Document.is_unkeyed(id: String, channel: String) -> bool`.

- [ ] **Step 1: Write the failing inspector test**

Add after the outliner block:

```gdscript
	print("SMOKE STEP: inspector")
	var inspector = editor._inspector
	doc.set_selection(key_id)
	await get_tree().process_frame
	_check(inspector._key_buttons.size() == 3, "inspector has one key button per transform channel")
	_check(inspector._key_all_button != null and inspector._key_all_button.custom_minimum_size.y >= 44.0, "inspector has a 44 dp key-all action")
	_check(inspector.key_state(key_id, "position") == "keyed", "inspector reports an existing key")
	doc.seek(0.5)
	doc.set_autokey(false)
	doc.set_object_transform(key_id, Vector3(8.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE)
	await get_tree().process_frame
	_check(inspector.key_state(key_id, "position") == "unkeyed", "inspector reports an unkeyed pose")
	var sections_before: int = inspector.section_build_count
	var values_before: int = inspector.value_update_count
	doc.set_object_transform(key_id, Vector3(9.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE)
	await get_tree().process_frame
	_check(inspector.section_build_count == sections_before, "transform updates do not rebuild inspector sections")
	_check(inspector.value_update_count > values_before, "transform updates refresh inspector values")
	doc.seek(2.0)
	_check(inspector.key_state(key_id, "position") == "keyed", "seeking to a key restores keyed state")
	for obj in doc.objects:
		if str(obj.get("kind", "")) == "light":
			doc.set_selection(str(obj["id"]))
			break
	await get_tree().process_frame
	_check(inspector._light_type_readonly != null, "light type is shown read-only")
	_check(not inspector.has_method("_set_light_type"), "inspector does not fake unsupported light type editing")
```

- [ ] **Step 2: Run the test and verify it fails**

Run smoke. Expected: failure at `inspector has one key button per transform channel`.

- [ ] **Step 3: Add key-state helpers**

Implement `has_key_at_playhead()` with the same half-frame tolerance as Task 1. Implement `is_unkeyed()` as: autokey off, no key at the playhead, a track exists, and the current pose differs from `sample_channel()` beyond the channel epsilon. These helpers are read-only.

- [ ] **Step 4: Rebuild the inspector**

Header: type icon 20, name 13 semibold with ellipsis, kind 11 muted, overflow. Sections: Transform, Geometry (read-only), Material, Light, Camera, Animation. Geometry shows the real vertex and surface counts from the imported `Mesh` and is read-only. Use only real document properties. Light type is a read-only label; expose colour, energy, and range. Camera exposes FOV 20–120. Material exposes colour, metallic, roughness. Animation shows the three channels, key counts, per-channel key buttons, and a 44 dp `Key all transform` action. Do not add emission, per-light shadow, primitive size/segments, or scene-camera active.

Transform rows: label 24, three `NumField`s, and a 44×44 key button with a 32 px diamond. Field states normal/focus/invalid/disabled. A drag uses one `begin_edit()`/`end_edit()` pair. Key button states: filled `TIME` for keyed, hollow `TEXT_MUTED` for empty, hollow plus `WARNING` dot for unkeyed. Tap inserts/updates the channel; long-press deletes the key at the playhead. Add an `Unkeyed` chip near Transform when any channel is unkeyed.

Cache section nodes. `transform_changed` calls `refresh_values()` only; `keyframes_changed` calls `refresh_keys()`; `scene_changed`/selection rebuild. Section headers 44 dp; collapse state persists in `Prefs.editor.collapsed_sections`.

- [ ] **Step 5: Run smoke and parse**

Run smoke. Expected `SMOKE RESULT: PASS`, no parse errors.

- [ ] **Step 6: Commit**

```bash
git add studio/src/ui/inspector.gd studio/src/core/document.gd studio/tests/smoke.gd
git commit -m "feat: rebuild inspector with real key states and unkeyed feedback"
```

---

### Task 10: Timeline transport, dope sheet, and speed graph

**Files:**
- Modify: `studio/src/ui/timeline.gd`
- Modify: `studio/src/app/editor.gd` (timeline host sizing only)
- Test: `studio/tests/smoke.gd`

**Interfaces:**
- Consumes: `Document` channels/keys/easing, `Prefs.editor.timeline_default`, `Prefs.editor.reduce_motion`.
- Produces: `Timeline.rebuild_count`, `Timeline.transport_height`, `Timeline.set_layout_mode(mode: String)`, `Timeline.ghost_channels() -> PackedStringArray`, `Timeline._ease_name(value: float) -> String`; preserve `set_mode(mode)`, `_channel_speed()`, `_mode`.

- [ ] **Step 1: Write the failing timeline test**

Add after the inspector block:

```gdscript
	print("SMOKE STEP: timeline rebuild")
	var timeline = editor._timeline
	doc.set_selection(key_id)
	await get_tree().process_frame
	timeline.set_layout_mode("compact")
	_check(timeline.transport_height >= 51.0, "compact transport is 52 dp")
	timeline.set_layout_mode("studio")
	_check(timeline.transport_height >= 43.0, "studio transport is 44 dp")
	var timeline_rebuilds: int = timeline.rebuild_count
	doc.set_object_transform(key_id, Vector3(5.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE)
	await get_tree().process_frame
	_check(timeline.rebuild_count == timeline_rebuilds, "transform does not rebuild timeline tracks")
	doc.seek(0.5)
	doc.set_autokey(false)
	doc.set_object_transform(key_id, Vector3(10.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ONE)
	await get_tree().process_frame
	_check(timeline.ghost_channels().has("position"), "unkeyed channel produces a ghost key")
	_check(timeline._ease_name(0.0) == "Hold", "ease name for hold")
	_check(timeline._ease_name(0.5) == "Ease Out", "ease name for ease out")
	_check(timeline._ease_name(1.0) == "Linear", "ease name for linear")
	_check(timeline._ease_name(2.0) == "Ease In", "ease name for ease in")
	_check(timeline._ease_name(0.75) == "Custom", "unknown scalar is labelled custom")
```

- [ ] **Step 2: Run the test and verify it fails**

Run smoke. Expected: failure at `compact transport is 52 dp` or `ghost_channels` missing.

- [ ] **Step 3: Rebuild the timeline**

Transport: previous key 44, play/pause 48 amber, next key 44, mono timecode 13, `AUTO` 44, `KEY` 44, loop 44, dope/graph toggle 44. Compact transport 52 dp; Studio/Desktop 44 dp. Timecode `MM:SS:FF`; Desktop shows `current / duration`. Tapping the timecode opens a mono `MM:SS:FF` field; Enter seeks, Escape cancels. Keep `scrub_bar.gd` as a 24 dp visual inside a 44 dp hit wrapper. Put `Key all transform` and `Delete key` in the timeline header overflow, not the transport. Playback switches the icon and keeps the preview interactive.

Dope sheet: 24 dp ruler, 140 dp track list (120 Compact), 32 dp visual rows with 44 dp hit, 10 px diamonds, selected `TIME_BRIGHT`, hover `TIME`, other keys `TIME` at 80%, ghost unkeyed `WARNING` outline. Playhead 1.5 px `TIME` with a triangle head. Tap seeks, drag scrubs, key drag retimes with snap, long-press opens Delete/Ease/Go to key, pinch zooms, two-finger drag pans, double-tap ruler fits. No auto-pan in this version.

Speed graph: keep engine-sampled `_channel_speed()`. 2 px `FOCUS` curve, 12% fill, 8 px handles with 44 hit, baseline 0, `×` labels. Presets `Hold`, `Ease Out`, `Linear`, `Ease In`, `Custom`; no `Ease In Out` because the document stores only one transition scalar. Readout `EASE 0.75× · Custom`. Empty state when no channel is selected.

Rebuild tracks only on selection, keyframes, duration/FPS, or mode change. Transform and playback redraw only. `reduce_motion` removes nonessential transitions but not playhead movement.

- [ ] **Step 4: Run smoke and parse**

Run smoke. Expected all timeline checks pass, the existing graph test still passes, and `SMOKE RESULT: PASS`.

- [ ] **Step 5: Commit**

```bash
git add studio/src/ui/timeline.gd studio/src/app/editor.gd studio/tests/smoke.gd
git commit -m "feat: rebuild timeline transport dope sheet and speed graph"
```

---

### Task 11: Settings screen, renderer switch, and capability matrix

**Files:**
- Create: `studio/src/ui/settings_panel.gd`
- Create: `studio/src/ui/workspace_sheet.gd`
- Modify: `studio/src/core/gfx.gd`
- Modify: `studio/src/app/editor.gd`
- Modify: `studio/src/app/main.gd`
- Modify: `studio/project.godot:49-50`
- Test: `studio/tests/smoke.gd`

**Interfaces:**
- Consumes: `Prefs`, `LayoutMath`, `Main.refresh_layout_scale()`, `Main.apply_orientation()`, `Gfx.changed`.
- Produces:
  - `SettingsPanel.categories() -> Array[String]` in this exact order: `general`, `editor`, `display`, `graphics`, `performance`, `render`, `import`, `about`.
  - `SettingsPanel.open(category: String = "general")`, `close()`, `active_category()`, `set_option(key: String, value: Variant)`, `sync_preset_buttons()`, signals `renderer_restart_requested(preference: String)`, `orientation_requested(value: String)`, `open_render_requested`, `open_import_requested`.
  - `WorkspaceSheet.open(current_mode: String, fit_percent: float, user_scale_enabled: bool, clamped: bool)`, signals `layout_selected(mode: String)`, `orientation_selected(value: String)`, `ui_scale_changed(value: float)`.
  - `Gfx.renderer_preference`, `renderer_pending`, `renderer_attempt_at`, `renderer_attempts`; `renderer_default_for_platform(platform: String) -> String`; `actual_method() -> String`; `build_restart_args(preference: String) -> PackedStringArray`; `capabilities_for(method: String) -> Dictionary`; `prepare_renderer_switch(preference: String) -> Dictionary`; `resolve_startup_renderer(preference: String, pending: String, actual: String, attempts: int, platform: String) -> Dictionary`; `ensure_renderer() -> Dictionary`; `consume_restart_request() -> PackedStringArray`.
  - Editor aliases: `_settings_panel`, `_settings_duration_field`, `_settings_fps_field`, `_preset_buttons`, `_perf_overlay`, `_open_settings(category: String = "general")`, `_open_graphics_settings()`, `_open_workspace_sheet()`, `_sync_preset_buttons()`.
  - `SettingsPanel` test fields `_ui_scale_control`, `_fit_label`.

- [ ] **Step 1: Write the failing renderer/settings test**

Add after the timeline block:

```gdscript
	print("SMOKE STEP: renderer and settings")
	_check(Gfx.renderer_default_for_platform("Android") == "mobile", "Android default renderer is mobile")
	_check(Gfx.renderer_default_for_platform("Linux") == "forward_plus", "desktop default renderer is forward plus")
	_check(Gfx.build_restart_args("mobile") == PackedStringArray(["--rendering-method", "mobile", "--rendering-driver", "vulkan"]), "mobile restart args are real")
	_check(Gfx.build_restart_args("gl_compatibility") == PackedStringArray(["--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3"]), "compatibility restart args are real")
	_check(Gfx.capabilities_for("mobile")["taa"] == false, "Mobile does not claim TAA")
	_check(Gfx.capabilities_for("forward_plus")["taa"] == true, "Forward+ reports TAA")
	var restart_state: Dictionary = Gfx.resolve_startup_renderer("mobile", "mobile", "forward_plus", 0, "Linux")
	_check(restart_state["action"] == "restart", "pending renderer requests one restart")
	_check(restart_state["args"].size() == 4, "pending renderer has restart args")
	var fallback_state: Dictionary = Gfx.resolve_startup_renderer("mobile", "mobile", "forward_plus", 2, "Linux")
	_check(fallback_state["action"] == "fallback", "renderer retry is bounded")
	_check(fallback_state["preference"] == "forward_plus", "renderer fallback uses platform default")
	_check(str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile")) == "mobile", "project.godot defaults Android to Mobile")

	editor._open_settings("graphics")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._overlay.has_modal(), "settings opens")
	_check(editor._settings_panel.categories() == ["general", "editor", "display", "graphics", "performance", "render", "import", "about"], "settings categories are complete")
	_check(editor._preset_buttons.size() == 5, "graphics has preset controls plus custom and reset")
	editor._settings_panel.set_option("editor.show_fps", false)
	_check(bool(Prefs.get_value("editor.show_fps", true)) == false, "settings write Prefs")
	editor._open_settings("display")
	editor.apply_fit_info(43.0, false, false)
	await get_tree().process_frame
	_check(editor._settings_panel._ui_scale_control.disabled, "UI scale is disabled when Desktop fit is active")
	_check(editor._settings_panel._fit_label.text.contains("43"), "settings shows the fit percentage")
	editor.apply_fit_info(100.0, true, false)
	await get_tree().process_frame
	_check(not editor._settings_panel._ui_scale_control.disabled, "UI scale works at 100 percent fit")
	editor._overlay.close_modal()
	await get_tree().process_frame
```

Also update the existing graphics-preset smoke block: change `_check(editor._preset_buttons.size() == 3, ...)` to `== 5`; when `Gfx.preset = "custom"`, assert no Performance/Balanced/Quality chip is pressed and the Custom chip is pressed; when `Gfx.preset = "balanced"`, assert Balanced is pressed.

- [ ] **Step 2: Run the test and verify it fails**

Run smoke. Expected: failure at `Android default renderer is mobile` or `settings opens`.

- [ ] **Step 3: Implement renderer state and restart logic**

In `gfx.gd`, default `renderer_preference` to `renderer_default_for_platform(OS.get_name())` when no saved value. Persist `renderer_preference`, `renderer_pending`, `renderer_attempt_at`, `renderer_attempts` in `graphics.json`. `auto` resolves to the platform default for UI display but produces empty restart args. `build_restart_args()` returns exactly:
```text
mobile            -> --rendering-method mobile --rendering-driver vulkan
forward_plus      -> --rendering-method forward_plus --rendering-driver vulkan
gl_compatibility  -> --rendering-method gl_compatibility --rendering-driver opengl3
auto              -> []
```

`capabilities_for(method)` is pure: `ssao` true for mobile/forward_plus, false for gl_compatibility; `ssil`, `ssr`, `taa`, `volumetric_fog` true only for forward_plus; `glow` true for all three. `is_forward()` keeps meaning Forward+ only.

`prepare_renderer_switch()` saves the preference, compares the requested resolved method with `actual_method()`, and if different sets pending + timestamp and returns `restart_required=true` with args. It does not quit. `resolve_startup_renderer()` returns `action="none"` when actual matches, `action="restart"` when attempts are below 2, and `action="fallback"` with the platform default after two attempts in 60 seconds. `ensure_renderer()` applies that pure result, clears pending on success, and records the fallback error. `consume_restart_request()` returns args once and clears the internal request flag.

`Main` calls `Gfx.ensure_renderer()` after startup. If it returns restart args and the display server is not headless, save the open project, call `OS.set_restart_on_exit(true, args)`, and quit. Never restart in headless tests. Change `project.godot` line 50 to `renderer/rendering_method.mobile="mobile"`.

- [ ] **Step 4: Build the settings screen and workspace sheet**

`SettingsPanel` is a single screen with a left nav (200 dp Desktop, 180 Studio; Compact uses category rows then a detail page with Back). Content scrolls; footer has section reset. Bind only real APIs:

- General: app name, version, engine version, package, build type, reset all.
- Editor: autosave 0/15/30/60, confirm delete, gizmo size 0.75–1.5, translate/rotate/scale snap, default interpolation, timeline default, show FPS, reduce motion, haptics.
- Display: workspace Auto/Compact/Studio/Desktop, orientation Auto/Portrait/Landscape, UI scale 0.85–1.30, safe-area preview, keep screen on, fullscreen (desktop OS only), reset. The UI scale row is a 44 dp button showing the current percentage; tapping opens 0.85/0.90/…/1.30 choices. `_ui_scale_control` is that button, so `.disabled` reflects the Desktop-fit lock.
- Graphics: renderer 2×2 segmented, current backend, adapter name, `Apply & restart`, reset to platform default, fallback warning, capability list. Then preset controls (Performance, Balanced, Quality, Custom status, Reset), 3D scale, MSAA, TAA, SSAO, SSIL, SSR, glow, tonemap, exposure, shadow quality/distance/splits/atlas, volumetric fog, sky, background colour.
- Performance: overlay off/compact/full, frame graph, adaptive quality, target FPS, minimum preview scale, preview update, preview cap, max FPS, V-Sync (hide if unavailable), stats, reset stats. `overlay=off` hides the HUD chip, `compact` shows the chip, `full` opens `Editor._perf_overlay` when the editor is entered. `frame_graph` toggles the graph inside the overlay. Each value writes `Prefs` and applies immediately.
- Render/Import: the same Prefs values used by the dedicated panels, plus buttons to open them.
- About: version, engine 4.7.2, package, actual renderer, build type, licenses, copy build info.

Every unsupported option is disabled with a reason. Changing a graphics value calls `Gfx.set_option()`, marks preset `custom`, and updates the Custom chip. Reset applies `Gfx.apply_preset("balanced")`. UI scale is disabled when `fit_percent < 100`; the row shows `Fit 43%` and the hint that switching to Studio/Compact enables scale. Orientation is Android-only and disabled when `DisplayServer.has_feature(DisplayServer.FEATURE_ORIENTATION)` is false.

`WorkspaceSheet` shows Auto/Compact/Studio/Desktop, the resolved mode, `Desktop fit 43%` when applicable, the `Small UI` warning and a manual `Switch to Studio` suggestion below 60%, and the scale control state. It never auto-switches mode.

- [ ] **Step 5: Run smoke and parse**

Run smoke. Expected `SMOKE RESULT: PASS`, including the updated 5-control preset assertions. Run parse; expected no errors.

- [ ] **Step 6: Commit**

```bash
git add studio/src/ui/settings_panel.gd studio/src/ui/workspace_sheet.gd \
  studio/src/core/gfx.gd studio/src/app/editor.gd studio/src/app/main.gd \
  studio/project.godot studio/tests/smoke.gd
git commit -m "feat: add full settings screen and real renderer switching"
```

---

### Task 12: Home project browser and all-project store

**Files:**
- Modify: `studio/src/core/project_store.gd`
- Modify: `studio/src/app/home.gd`
- Test: `studio/tests/smoke.gd`

**Interfaces:**
- Consumes: project folders under `user://projects/<id>/project.json`, `recent_projects()`, `Overlay`.
- Produces:
  - `Store.list_projects() -> Array[Dictionary]` with `id`, `title`, `path`, `modified`, `objects`, `duration`, `size_bytes` (`-1` until measured).
  - `Store.project_size(id: String) -> int`, `Store.total_size() -> int`, `Store.invalidate_size_cache() -> void`.
  - `Home.layout_for_width(width: float) -> String` (`"list"` below 600, `"split"` 600–959, `"table"` >=960), `Home.rebuild_count`, `Home.visible_project_count()`, `Home.project_row_count()`, `Home.set_search(text: String)`, `Home.set_sort(mode: String)`; test fields `_settings_button`, `_template_rows`, `_overlay`; `Home._open_new_project_sheet()`.

- [ ] **Step 1: Write the failing Home/Store test**

Add before the editor is closed in smoke:

```gdscript
	print("SMOKE STEP: home project browser")
	var unlisted_id := "all-projects-test"
	var unlisted_path: String = Store.ROOT.path_join(unlisted_id)
	DirAccess.make_dir_recursive_absolute(unlisted_path)
	_write_test_text(unlisted_path.path_join("project.json"), JSON.stringify({
		"title": "All Projects Test",
		"objects": [],
		"duration": 4.0,
		"fps": 24,
	}))
	var listed: Array = Store.list_projects()
	var found_unlisted := false
	for entry in listed:
		if str(entry.get("id", "")) == unlisted_id:
			found_unlisted = true
			_check(str(entry.get("title", "")) == "All Projects Test", "list_projects reads real titles")
			break
	_check(found_unlisted, "list_projects includes projects that are not in recents")
	_check(Store.project_size(unlisted_id) > 0, "project size is measured from the filesystem")
	var home = main._home
	_check(home.layout_for_width(360.0) == "list", "home uses a list on phones")
	_check(home.layout_for_width(800.0) == "split", "home uses two columns on tablets")
	_check(home.layout_for_width(1200.0) == "table", "home uses a table on desktop")
	home.refresh()
	home.set_search("All Projects Test")
	_check(home.visible_project_count() == 1, "home search filters real projects")
	home.set_search("")
	_check(home.visible_project_count() >= 1, "home lists projects after clearing search")
	_check(home.find_child("Hero", true, false) == null, "home has no hero")
	_check(home.find_child("Illustration", true, false) == null, "home has no decorative illustration")
	_check(home._settings_button.custom_minimum_size.x >= 44.0, "home settings has a 44 dp target")
	home._open_new_project_sheet()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(home._template_rows.size() == 2, "new project sheet has Blank and Study rows")
	for row in home._template_rows.values():
		_check(row.custom_minimum_size.y >= 56.0, "template rows are 56 dp")
	home._overlay.close_modal()
	await get_tree().process_frame
	_check(Store.delete_project(unlisted_id), "temporary unlisted project deleted")
```

- [ ] **Step 2: Run the test and verify it fails**

Run smoke. Expected: failure at `list_projects includes projects that are not in recents` or `home layout` missing.

- [ ] **Step 3: Implement `Store.list_projects()` and size cache**

Scan `ROOT` with `DirAccess.open()`, include every subdirectory containing `project.json`, parse title/objects/duration, and use the file modification time when the JSON has no timestamp. Do not depend on `_recents`. Sort by modified descending in the store; Home applies Recent/Name sorting. `project_size()` recursively sums file sizes, caches for 5 seconds, and returns `0` for a missing project. `total_size()` sums the cache or scans once. Never scan on every frame.

- [ ] **Step 4: Rebuild Home as a project browser**

Top bar 48 dp: `KINEMA` 12 sp semibold + `STUDIO` 10 sp muted; right Settings 44 and About 44. No hero, cards, or illustration.

- Width <600: search 44, 64 dp project rows, bottom `New project` 48.
- Width 600–959: list 60% + detail 40%; detail shows name, modified, objects, duration, path, size (on demand); actions Open/Rename/Delete.
- Width >=960: table with Name, Modified, Objects, Duration, Size; header 32, row 44; toolbar New/Search/Sort; right detail 280.

Rows show a type icon, name, meta (`Modified 2h ago · 3 objects · 6s`), and a 44 dp overflow. Search filters names; no result shows an empty state. Sort Recent/Name persists in `Prefs.editor.project_sort`. New project sheet: name field, Blank/Study rows 56 dp with icon/description/radio, Create 48. Delete confirms with the real name and is irreversible; errors are shown, never hidden. Footer shows `X projects · Y MB` from the real filesystem.

`refresh()` reloads `Store.list_projects()` and preserves search/sort. Do not display a template badge because project JSON does not store one.

- [ ] **Step 5: Run smoke and parse**

Run smoke. Expected all Home/Store checks pass, `SMOKE RESULT: PASS`, no parse errors.

- [ ] **Step 6: Commit**

```bash
git add studio/src/core/project_store.gd studio/src/app/home.gd studio/tests/smoke.gd
git commit -m "feat: rebuild home as a real project browser"
```

---

### Task 13: Real render and import sheets

**Files:**
- Create: `studio/src/ui/render_panel.gd`
- Create: `studio/src/ui/import_panel.gd`
- Modify: `studio/src/app/editor.gd`
- Modify: `studio/src/core/project_store.gd`
- Modify: `studio/src/core/document.gd`
- Modify: `studio/src/viewport/editor_view.gd`
- Create: `studio/tests/render.gd`
- Create: `studio/tests/render.tscn`
- Test: `studio/tests/smoke.gd`

**Interfaces:**
- Consumes: `EditorView.capture_still()`, `RenderExport.sequence_dir()`, `RenderExport.frame_name()`, `RenderExport.archive_path()`, `RenderExport.zip_directory()`, `Document.add_imported()`, `Store.import_model()`, `Prefs.render.*`, `Prefs.import.*`.
- Produces:
  - `RenderPanel` signals `still_requested(long_edge: int, msaa: int, export: bool)`, `sequence_requested(long_edge: int, msaa: int, export: bool)`, `cancel_requested`; fields `start_frame`, `end_frame`, `transparent`, `still_button`, `sequence_button`, `cancel_button`, `progress_bar`, `status_label`, `start_field`, `end_field`; methods `open(duration: float, fps: int)`, `set_range(start: int, end: int)`, `set_still_options(long_edge: int, msaa: int)`, `set_sequence_options(long_edge: int, msaa: int, transparent: bool)`, `frame_count(duration: float, fps: int) -> int`, `set_progress(value: float, text: String)`, `set_busy(busy: bool)`, `format_note() -> String`.
  - `ImportPanel` signals `pick_requested`, `import_requested(uri: String, options: Dictionary)`; fields `import_button`, `merge_control`, `saf_note`, `status_label`; methods `open()`, `set_picked(uri: String)`, `options() -> Dictionary`, `status_text() -> String`.
  - `EditorView.capture_still(long_edge: int = 1920, msaa: int = Viewport.MSAA_4X, transparent: bool = false) -> Image`.
  - `Editor.render_still(long_edge: int, msaa: int, transparent: bool) -> Image`, `Editor._save_still_internal(image: Image) -> String`, `Editor._open_import_sheet()`, fields `_render_panel`, `_import_panel`, `_last_sequence_dir`, `_last_render_path`; aliases `_render_sequence_button`, `_render_progress`, `_render_status`, `_render_busy` preserved.
  - `Store.import_model(uri: String, project_dir: String, fallback_name: String = "Model", options: Dictionary = {}) -> Dictionary`. It consumes `materials` (bool) and `textures` (bool); the editor consumes `scale` (float) and applies it to the document object. The three-argument call remains valid.
  - `Document.add_imported(model_rel_path: String, p_name: String, at: Vector3 = Vector3.ZERO, p_scale: Vector3 = Vector3.ONE) -> String`.

- [ ] **Step 1: Write the failing panel and import-option tests**

Replace the existing `SMOKE STEP: render sheet` block in `smoke.gd` with:

```gdscript
	print("SMOKE STEP: render panel")
	editor._open_render_sheet()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._overlay.has_modal(), "render sheet opens")
	_check(editor._render_panel != null, "render panel exists")
	_check(editor._render_sequence_button != null, "render sheet has sequence action")
	_check(editor._render_progress != null, "render sheet has progress readout")
	_check(editor._sequence_frame_count() == 144, "sequence frame count follows duration and fps")
	_check(not editor._render_busy, "render sheet is idle on open")
	if editor._render_panel != null:
		_check(editor._render_panel.format_note().contains("PNG"), "render sheet states the real format")
		_check(editor._render_panel.format_note().contains("MP4"), "render sheet states MP4 is unsupported")
		_check(editor._render_panel.start_field.value == 0.0, "sequence starts at frame zero")
		_check(editor._render_panel.end_field.value == 144.0, "sequence ends at duration times fps")
		editor._render_panel.set_range(12, 24)
		_check(editor._sequence_frame_count() == 12, "sequence range controls the frame count")
		editor._render_panel.set_range(0, 144)
	editor._overlay.close_modal()
	await get_tree().process_frame

	print("SMOKE STEP: import panel")
	editor._open_import_sheet()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor._overlay.has_modal(), "import sheet opens")
	_check(editor._import_panel != null, "import panel exists")
	if editor._import_panel != null:
		_check(editor._import_panel.import_button.disabled, "import is disabled before a file is picked")
		editor._import_panel.set_picked("user://fixture/model.fbx")
		_check(editor._import_panel.import_button.disabled, "FBX import is disabled")
		_check(editor._import_panel.status_text().contains("GLB or OBJ"), "FBX message names the conversion path")
		editor._import_panel.set_picked("user://fixture/model.obj")
		_check(not editor._import_panel.import_button.disabled, "OBJ import is enabled")
		var opts: Dictionary = editor._import_panel.options()
		_check(is_equal_approx(float(opts.get("scale", 0.0)), 1.0), "import scale defaults to one")
		_check(bool(opts.get("materials", false)), "import materials defaults on")
		_check(bool(opts.get("textures", false)), "import textures defaults on")
		_check(editor._import_panel.merge_control.disabled, "merge by material is disabled with a reason")
		_check(editor._import_panel.merge_control.tooltip_text.contains("already merges"), "merge reason is concrete")
		_check(editor._import_panel.saf_note.text.contains("sibling"), "SAF note explains sibling files")
	editor._overlay.close_modal()
	await get_tree().process_frame
```

Insert this block after the existing OBJ import assertions and before the fixture cleanup:

```gdscript
	print("SMOKE STEP: import options")
	var no_mat: Dictionary = Store.import_model(
		fixture.path_join("sample.obj"), doc.project_dir, "NoMat", {"materials": false}
	)
	_check(bool(no_mat.get("ok", false)), "OBJ imports without materials")
	if bool(no_mat.get("ok", false)):
		var no_mat_rel := str(no_mat.get("rel_path", ""))
		var no_mat_folder: String = doc.project_dir.path_join(no_mat_rel).get_base_dir()
		_check(not DirAccess.dir_exists_absolute(no_mat_folder.path_join("materials")), "materials off copies no MTL")
		_check(not FileAccess.get_file_as_string(doc.project_dir.path_join(no_mat_rel)).contains("mtllib"), "materials off strips MTL references")
	var no_tex: Dictionary = Store.import_model(
		fixture.path_join("sample.obj"), doc.project_dir, "NoTex", {"materials": true, "textures": false}
	)
	_check(bool(no_tex.get("ok", false)), "OBJ imports without textures")
	if bool(no_tex.get("ok", false)):
		var no_tex_rel := str(no_tex.get("rel_path", ""))
		var no_tex_folder: String = doc.project_dir.path_join(no_tex_rel).get_base_dir()
		_check(not DirAccess.dir_exists_absolute(no_tex_folder.path_join("textures")), "textures off copies no image")
		var no_tex_mtl := FileAccess.get_file_as_string(no_tex_folder.path_join("materials/sample.mtl"))
		_check(no_tex_mtl != "" and not no_tex_mtl.contains("map_Kd"), "textures off strips MTL texture maps")
		var before_import: int = doc.objects.size()
		var scaled_id: String = doc.add_imported(no_tex_rel, "Scaled", Vector3.ZERO, Vector3(10.0, 10.0, 10.0))
		_check(
			(doc.get_object_transform(scaled_id)["scale"] as Vector3).is_equal_approx(Vector3(10.0, 10.0, 10.0)),
			"import scale writes the object"
		)
		_check(doc.objects.size() == before_import + 1, "one import creates one object")
		doc.undo()
		await get_tree().process_frame
		_check(doc.objects.size() == before_import, "one undo removes the imported object")
		doc.redo()
		await get_tree().process_frame
		_check(doc.objects.size() == before_import + 1, "redo restores the imported object")
	var fbx_fixture := fixture.path_join("sample.fbx")
	_write_test_text(fbx_fixture, "Kaydara FBX Binary  ")
	var fbx_result: Dictionary = Store.import_model(fbx_fixture, doc.project_dir, "Bad", {})
	_check(not bool(fbx_result.get("ok", true)), "FBX import is rejected")
	_check(str(fbx_result.get("error", "")).contains("GLB or OBJ"), "FBX error names the real alternatives")
	DirAccess.remove_absolute(fbx_fixture)
```

Create `tests/render.tscn`:

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/render.gd" id="1_render"]

[node name="RenderTest" type="Node"]
script = ExtResource("1_render")
```

Create `tests/render.gd`:

```gdscript
extends Node
## Real render regression. Requires a display (xvfb), not --headless.

var _failures: Array[String] = []

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		printerr("RENDER FAIL: " + message)
	else:
		print("RENDER OK: " + message)

func _ready() -> void:
	await get_tree().process_frame
	var packed: PackedScene = load("res://src/app/main.tscn")
	var main: Control = packed.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main._on_new_project_requested("Render Test", "study")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var editor = main._editor
	_check(editor != null, "editor opened for render test")
	if editor == null:
		_finish()
		return
	var doc = editor.doc
	doc.set_fps(24)
	doc.set_duration(0.25)

	var opaque: Image = await editor.render_still(320, Viewport.MSAA_DISABLED, false)
	_check(opaque != null, "opaque still captured")
	if opaque != null:
		_check(maxi(opaque.get_width(), opaque.get_height()) == 320, "still honours the long edge")
		_check(opaque.get_pixel(2, 2).a > 0.99, "opaque still has an opaque background")
		var still_path: String = editor._save_still_internal(opaque)
		_check(still_path.contains(doc.project_id), "still saves under the project render folder")
		_check(FileAccess.file_exists(still_path), "still file exists")
		var reloaded := Image.load_from_file(still_path)
		_check(reloaded != null and reloaded.get_size() == opaque.get_size(), "saved PNG reloads at the same size")
		DirAccess.remove_absolute(still_path)

	var clear: Image = await editor.render_still(320, Viewport.MSAA_DISABLED, true)
	_check(clear != null, "transparent still captured")
	if clear != null:
		_check(clear.get_pixel(2, 2).a < 0.01, "transparent still has alpha at the corner")

	editor._open_render_sheet()
	await get_tree().process_frame
	await get_tree().process_frame
	editor._render_panel.set_range(0, 6)
	editor._render_panel.set_sequence_options(192, Viewport.MSAA_DISABLED, true)
	_check(editor._sequence_frame_count() == 6, "render test uses a six-frame range")
	await editor._render_sequence(false)
	var zip_path := editor._last_render_path
	_check(zip_path.ends_with(".zip") and FileAccess.file_exists(zip_path), "sequence ZIP exists")
	if zip_path.ends_with(".zip") and FileAccess.file_exists(zip_path):
		var reader := ZIPReader.new()
		_check(reader.open(zip_path) == OK, "sequence ZIP opens")
		if reader.open(zip_path) == OK:
			_check(reader.get_files().size() == 6, "sequence ZIP contains every frame")
			var frame_bytes := reader.read_file("frame_0001.png")
			_check(not frame_bytes.is_empty(), "first frame is readable from the ZIP")
			var frame := Image.new()
			_check(frame.load_png_from_buffer(frame_bytes) == OK, "first frame is a real PNG")
			_check(maxi(frame.get_width(), frame.get_height()) == 192, "frame honours the sequence long edge")
			_check(frame.get_pixel(2, 2).a < 0.01, "sequence honours the transparent option")
			reader.close()
		_check(not DirAccess.dir_exists_absolute(editor._last_sequence_dir), "temporary frames are cleaned up")
		DirAccess.remove_absolute(zip_path)

	var project_id: String = doc.project_id
	editor._leave(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(Store.delete_project(project_id), "render test project deleted")
	_finish()

func _finish() -> void:
	if _failures.is_empty():
		print("RENDER RESULT: PASS")
	else:
		printerr("RENDER RESULT: %d FAILURE(S)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
```

- [ ] **Step 2: Run both tests and verify they fail for the right reason**

Run smoke. Expected: failure at `render panel exists`, then the import-panel and import-option checks.
Run the render test:
```bash
GODOT=/data/data/com.termux/files/home/tools/Godot_v4.7.2-stable_linux.arm64
xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path /root/kinema/studio res://tests/render.tscn
```
Expected: failure at `editor.render_still` or `render panel exists`.

- [ ] **Step 3: Build the two panels and wire the editor**

`RenderPanel` is the body of the render sheet. It owns the Still/Sequence controls and reads/writes `Prefs.render.*`; it never captures. `set_still_options()` and `set_sequence_options()` accept any positive long edge in `64..7680` (the UI offers the preset choices; tests use 320/192 for speed). Still: long edge 1280/1920/2560/3840, MSAA Off/2×/4×/8×, transparent toggle, `Quick still` and `Save still…`. Sequence: frame range start/end fields, real frame count, long edge 720/1080/1440, MSAA Off/2×/4×, transparent, `Render ZIP`, progress, status, and `Cancel` only while busy. The format note must read exactly: `PNG still and PNG sequence ZIP. MP4 is not supported in this build.` The range is `[start, end)`; end defaults to `roundi(duration * fps)`. An empty range disables Render with `Frame range is empty`. Show a real upper bound: `≤ N MB raw RGBA` from `frames × width × height × 4`, labelled as an upper bound, not a file-size promise.

`ImportPanel` owns the source row, options, notes, and Import button. `Pick file…` emits `pick_requested`; `set_picked(uri)` enables Import for `.glb`, `.gltf`, `.obj` based on the extension, not on a pre-read (the store reports unreadable files), and disables it for `.fbx` with `FBX needs a dedicated parser. Convert the file to GLB or OBJ.` The scale choices are `0.01 / 0.1 / 1 / 10 / 100`. Materials and textures are toggles with the note `These options apply to OBJ. glTF keeps its embedded materials.` The merge row is a disabled toggle with tooltip `The OBJ importer already merges surfaces by material; glTF keeps its authored hierarchy.` The SAF note must contain: `Android may not allow reading sibling .mtl or texture files next to the picked file. If a material is missing, copy the whole folder into app storage or pick the file from that folder.` `status_label` is empty on open; errors are set by the editor and never hidden.

In `editor.gd`, replace the render-sheet construction with `RenderPanel`, and replace `_pick_model()`'s immediate import with: open the native picker, call `_import_panel.set_picked(uri)` on selection, and import only when the panel emits `import_requested`. `_import_selected(uri, options)` calls `Store.import_model(..., options)`, applies `Vector3.ONE * float(options.get("scale", 1.0))` through `add_imported()`, saves, focuses, and toasts. Keep the editor aliases `_render_sequence_button`, `_render_progress`, `_render_status`, `_render_busy` pointing at the panel widgets so existing tests and callers keep working. `_sequence_frame_count()` returns `_render_panel.frame_count(doc.duration, doc.fps)`.

- [ ] **Step 4: Make still, sequence, range, transparency, and cancel real**

In `editor_view.gd`, add the `transparent` parameter to `capture_still()`. When true, set `probe.transparent_bg = true`, temporarily switch the shared `WorldEnvironment.environment` to `Environment.BG_CLEAR_COLOR` with `Color(0, 0, 0, 0)`, capture, then restore the previous mode and colour. When false, keep the studio sky. Do not mutate the preview camera or the document markers permanently.

In `editor.gd`, add `render_still(long_edge, msaa, transparent)` that pauses playback and awaits `_view.capture_still()`. Add `_save_still_internal(image) -> String`, which writes a unique PNG under `user://renders/<project_id>/` and returns the real path. Use that root for stills and sequences; create it first and show the real path. After every still write, verify the file exists, reloads with `Image.load_from_file()`, has the requested long edge, and is larger than zero bytes; on failure delete the partial file and toast the concrete error. `_render_sequence()` reads `start_frame`, `end_frame`, `sequence_long_edge`, `sequence_msaa`, and `transparent` from `_render_panel`; seeks each frame index, saves `frame_name(index - start + 1)`, updates progress, and restores the saved time in all exit paths. Record `_last_sequence_dir = dir`. Reset `_last_render_path = ""` at the start. `_render_cancel_requested` is checked before each frame. On cancel, remove the temporary frames and toast `Render cancelled`. On failure, keep the temporary frames, set `_last_sequence_dir`, and toast `Render failed. Frames kept at <path>`. On either path, reset busy/progress and do not write a ZIP. The panel's Cancel button calls `cancel_render()`. `_leave()` checks `_render_busy`; if a render is running it asks `Cancel the render and leave?` and only proceeds after confirmation.

- [ ] **Step 5: Make the import options real**

In `project_store.gd`, add the optional `options` dictionary and pass it to `_import_obj()`. For glTF/GLB the file already contains its materials; the options do not apply, and the panel says so. For OBJ:
- `materials=false`: skip the MTL copy and remove `mtllib`/`usemtl` lines from the copied OBJ.
- `textures=false`: copy the MTL through a filter that removes `map_*`, `bump`, `disp`, `decal`, `refl`, and `norm` lines; do not create `textures/`.
- both true: keep today's copy/rewrite behaviour.
- `scale` is not a store concern; it is applied by `Document.add_imported()`.

In `document.gd`, add `p_scale` to `add_imported()` and write it to `obj["scale"]`. Keep the single `begin_edit("Import model")`/`end_edit()` pair so one import is exactly one undo step.

- [ ] **Step 6: Run the real render test, smoke, and parse**

Run the render command from Step 2. Expected: `RENDER RESULT: PASS`, a real six-frame ZIP, and no leftover sequence directory. Run smoke and the headless parse command. Expected: `SMOKE RESULT: PASS` and no parse errors.

- [ ] **Step 7: Commit**

```bash
git add studio/src/ui/render_panel.gd studio/src/ui/import_panel.gd \
  studio/src/app/editor.gd studio/src/core/project_store.gd \
  studio/src/core/document.gd studio/src/viewport/editor_view.gd \
  studio/tests/render.gd studio/tests/render.tscn studio/tests/smoke.gd
git commit -m "feat: rebuild render and import sheets with real options"
```

---

### Task 14: Layout matrix, overflow guards, visual capture, and relative performance

**Files:**
- Create: `studio/tests/layout.gd`
- Create: `studio/tests/layout.tscn`
- Create: `studio/tests/capture.gd`
- Create: `studio/tests/capture.tscn`
- Modify: whichever component owns a failure found by the matrix (do not weaken the assertions)
- Test: the two new scenes below

**Interfaces:**
- Consumes: `Main.refresh_layout_scale()`, `Editor.set_workspace_mode()`, `Editor.workspace_mode()`, `Editor.fit_percent()`, `Home.layout_for_width()`, `Perf.fps`, `Perf.frame_ms`, `Perf.reset_stats()`, `Outliner.rebuild_count`, `Inspector.section_build_count`, `Timeline.rebuild_count`.
- Produces: `tests/layout.gd` assertions and `tests/capture.gd` PNGs under `user://qa/`. No product API is added by this task.

- [ ] **Step 1: Write the layout matrix and capture runner**

Create `tests/layout.tscn`:

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/layout.gd" id="1_layout"]

[node name="LayoutTest" type="Node"]
script = ExtResource("1_layout")
```

Create `tests/layout.gd`:

```gdscript
extends Node
## Layout and performance matrix. Requires a display (xvfb), not --headless.

const SIZES := [
	Vector2i(360, 640),
	Vector2i(390, 844),
	Vector2i(411, 914),
	Vector2i(600, 960),
	Vector2i(800, 1280),
	Vector2i(914, 411),
	Vector2i(960, 600),
	Vector2i(1024, 768),
	Vector2i(1280, 800),
	Vector2i(1440, 900),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1600),
	Vector2i(800, 480),
]
const MODES := ["compact", "studio", "desktop"]

var _failures: Array[String] = []

func _fail(message: String) -> void:
	_failures.append(message)
	printerr("LAYOUT FAIL: " + message)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _ready() -> void:
	await get_tree().process_frame
	var packed: PackedScene = load("res://src/app/main.tscn")
	var main: Control = packed.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	# Home uses its own responsive layout, independent of the editor mode.
	await _resize(main, Vector2i(360, 640))
	_check(main._home.layout_for_width(360.0) == "list", "home is a list on a phone")
	_check_no_overflow(main._home, "home 360x640")
	await _resize(main, Vector2i(1280, 800))
	_check(main._home.layout_for_width(1280.0) == "table", "home is a table on desktop")
	_check_no_overflow(main._home, "home 1280x800")

	main._on_new_project_requested("Layout Test", "study")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var editor = main._editor
	_check(editor != null, "editor opened for layout matrix")
	if editor == null:
		_finish()
		return

	for size in SIZES:
		await _resize(main, size)
		for mode in MODES:
			editor.set_workspace_mode(mode)
			var info: Dictionary = main.refresh_layout_scale()
			await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().process_frame
			var label := "%dx%d %s" % [size.x, size.y, mode]
			_check(editor.workspace_mode() == mode, label + ": mode applies")
			_check(str(info.get("mode", "")) == mode, label + ": scale info matches the mode")
			_check_no_overflow(editor, label)
			_check_hit_targets(editor, mode, label)
			if mode == "desktop" and size.x < 960:
				_check(float(info.get("fit", 1.0)) < 1.0, label + ": desktop shrinks to fit")
				var logical: Vector2 = info.get("logical_after", Vector2.ZERO)
				_check(logical.x >= 959.0 and logical.y >= 599.0, label + ": desktop keeps 960x600 logical")
				_check(not bool(info.get("user_scale_enabled", true)), label + ": desktop fit disables UI scale")
				_check(editor.fit_percent() < 100.0, label + ": editor reports the fit percentage")
			print("LAYOUT OK: " + label)

	# Desktop on a portrait phone must stay Desktop, not fall back to Studio.
	await _resize(main, Vector2i(360, 640))
	editor.set_workspace_mode("desktop")
	main.refresh_layout_scale()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor.workspace_mode() == "desktop", "desktop stays selected on a phone")
	_check(editor._status_bar.visible, "desktop status bar remains visible on a phone")
	_check(editor._top_bar.size.y <= 38.0, "desktop menu bar remains 36 dp on a phone")
	_check_no_overflow(editor, "desktop phone final")

	# UI scale extremes must not overflow in the touch modes.
	for ui_scale in [0.85, 1.30]:
		Prefs.set_value("display.user_scale", ui_scale)
		for size in [Vector2i(360, 640), Vector2i(800, 1280)]:
			await _resize(main, size)
			for mode in ["compact", "studio"]:
				editor.set_workspace_mode(mode)
				main.refresh_layout_scale()
				await get_tree().process_frame
				await get_tree().process_frame
				_check_no_overflow(editor, "scale %.2f %s %dx%d" % [ui_scale, mode, size.x, size.y])
	Prefs.set_value("display.user_scale", 1.0)
	main.refresh_layout_scale()

	# Idle must not rebuild panels or render the 3D preview continuously.
	editor.set_workspace_mode("compact")
	main.refresh_layout_scale()
	await get_tree().process_frame
	await get_tree().process_frame
	var outliner_rebuilds: int = editor._outliner.rebuild_count
	var inspector_builds: int = editor._inspector.section_build_count
	var timeline_rebuilds: int = editor._timeline.rebuild_count
	Perf.reset_stats()
	for i in range(30):
		await get_tree().process_frame
	_check(Perf.fps > 0.0, "performance sampler reports a real FPS")
	_check(
		editor._view._viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS,
		"idle preview is not UPDATE_ALWAYS"
	)
	_check(editor._outliner.rebuild_count == outliner_rebuilds, "idle does not rebuild the outliner")
	_check(editor._inspector.section_build_count == inspector_builds, "idle does not rebuild inspector sections")
	_check(editor._timeline.rebuild_count == timeline_rebuilds, "idle does not rebuild timeline tracks")
	print("LAYOUT PERF: fps=%.1f frame_ms=%.2f" % [Perf.fps, Perf.frame_ms])

	var project_id: String = editor.doc.project_id
	editor._leave(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(Store.delete_project(project_id), "layout test project deleted")
	_finish()

func _resize(main: Control, size: Vector2i) -> void:
	get_window().size = size
	await get_tree().process_frame
	await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame

func _check_no_overflow(root: Control, context: String) -> void:
	var viewport_rect := Rect2(Vector2.ZERO, root.get_viewport_rect().size).grow(2.0)
	for child in root.get_children():
		if child is Control:
			_walk_overflow(child, viewport_rect, context, false)

func _walk_overflow(control: Control, viewport_rect: Rect2, context: String, clipped: bool) -> void:
	if not control.is_visible_in_tree():
		return
	if control is Window or control is PopupMenu:
		return
	var rect := control.get_global_rect()
	if not clipped and rect.size != Vector2.ZERO and not viewport_rect.encloses(rect):
		_fail("%s: %s overflows %s" % [context, control.get_path(), rect])
	var next_clipped := clipped or control.clip_contents or control is ScrollContainer
	for child in control.get_children():
		if child is Control:
			_walk_overflow(child, viewport_rect, context, next_clipped)

func _check_hit_targets(root: Control, mode: String, context: String) -> void:
	for node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null or not button.is_visible_in_tree():
			continue
		if bool(button.get_meta("qa_hit_exempt", false)):
			continue
		if mode == "desktop" and button.get_parent() is MenuBar:
			continue
		var height := maxf(button.size.y, button.custom_minimum_size.y)
		var width := maxf(button.size.x, button.custom_minimum_size.x)
		if height < 43.5 or width < 43.5:
			_fail("%s: %s is %.1fx%.1f, below 44 dp" % [context, button.get_path(), width, height])

func _finish() -> void:
	if _failures.is_empty():
		print("LAYOUT RESULT: PASS")
	else:
		printerr("LAYOUT RESULT: %d FAILURE(S)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
```

Create `tests/capture.tscn`:

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/capture.gd" id="1_capture"]

[node name="Capture" type="Node"]
script = ExtResource("1_capture")
```

Create `tests/capture.gd`:

```gdscript
extends Node
## Visual QA capture. Requires a display (xvfb), not --headless.

const SIZES := [
	Vector2i(360, 640),
	Vector2i(411, 914),
	Vector2i(600, 960),
	Vector2i(800, 1280),
	Vector2i(914, 411),
	Vector2i(960, 600),
	Vector2i(1280, 800),
	Vector2i(1600, 900),
	Vector2i(800, 480),
]
const MODES := ["compact", "studio", "desktop"]

func _ready() -> void:
	await get_tree().process_frame
	var out := "user://qa"
	DirAccess.make_dir_recursive_absolute(out)
	var packed: PackedScene = load("res://src/app/main.tscn")
	var main: Control = packed.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	for size in [Vector2i(360, 640), Vector2i(1280, 800)]:
		await _resize(main, size)
		await _snap(out.path_join("home_%dx%d.png" % [size.x, size.y]))

	main._on_new_project_requested("Visual QA", "study")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var editor = main._editor
	for size in SIZES:
		await _resize(main, size)
		for mode in MODES:
			editor.set_workspace_mode(mode)
			await get_tree().process_frame
			await get_tree().process_frame
			await _snap(out.path_join("editor_%dx%d_%s.png" % [size.x, size.y, mode]))
	var project_id: String = editor.doc.project_id
	editor._leave(false)
	await get_tree().process_frame
	await get_tree().process_frame
	Store.delete_project(project_id)
	print("CAPTURE RESULT: PASS -> " + ProjectSettings.globalize_path(out))
	get_tree().quit(0)

func _resize(main: Control, size: Vector2i) -> void:
	get_window().size = size
	await get_tree().process_frame
	await get_tree().process_frame
	main.refresh_layout_scale()
	await get_tree().process_frame

func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		printerr("CAPTURE FAIL: " + path)
		return
	image.save_png(path)
	print("CAPTURE " + path)
```

- [ ] **Step 2: Run the matrix and capture the current UI**

```bash
GODOT=/data/data/com.termux/files/home/tools/Godot_v4.7.2-stable_linux.arm64
xvfb-run -a -s "-screen 0 2560x1600x24" "$GODOT" --path /root/kinema/studio res://tests/layout.tscn
xvfb-run -a -s "-screen 0 2560x1600x24" "$GODOT" --path /root/kinema/studio res://tests/capture.tscn
```
Expected: `LAYOUT RESULT: PASS`, one `LAYOUT OK` line per size/mode, and 29 PNGs under `user://qa/` (2 Home + 9 sizes × 3 modes).

- [ ] **Step 3: Fix every failure in the owning component**

Do not relax the matrix. Typical fixes: make a row's label `text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS` and `size_flags_horizontal = SIZE_EXPAND_FILL`; replace a hard minimum width with a shrinkable child; add a `ScrollContainer` around a wide settings group; clamp sheet height to the viewport; switch the dock to tabs when height is below 520; collapse the rail to one button when Compact height is below 480. Re-run Step 2 after each fix. Inspect the PNGs at 360×640 Compact, 360×640 Desktop, 800×480 Compact, and 1280×800 Desktop before proceeding; fix clipped labels or overlapping controls even if the geometric assertion passes.

- [ ] **Step 4: Re-run layout, capture, smoke, and parse**

Run the two commands from Step 2, then smoke and parse. Expected: `LAYOUT RESULT: PASS`, `CAPTURE RESULT: PASS`, `SMOKE RESULT: PASS`, no parse errors.

- [ ] **Step 5: Commit**

```bash
git add studio/tests/layout.gd studio/tests/layout.tscn \
  studio/tests/capture.gd studio/tests/capture.tscn \
  studio/src
git commit -m "test: add layout matrix and visual capture"
```

---

### Task 15: Staging, CI APK verification, and documentation

**Files:**
- Modify: `scripts/stage-android.sh`
- Modify: `.github/workflows/build.yml`
- Modify: `README.md`
- Modify: `BUILD.md`
- Test: shell staging check, local test suite, workflow diff review

**Interfaces:**
- Consumes: every runtime file created by Tasks 1–14.
- Produces: a staging script that fails on a missing runtime file, a CI job that verifies package/ABI/signature/assets, and docs that match the shipped behaviour.

- [ ] **Step 1: Extend the staged-file contract**

Add these entries to the `for required in` list in `scripts/stage-android.sh`, using the same `$APP/src/main/assets/` prefix as the existing entries:

```text
"$APP/src/main/assets/src/app/layout_math.gd"
"$APP/src/main/assets/src/core/prefs.gd"
"$APP/src/main/assets/src/core/perf.gd"
"$APP/src/main/assets/src/ui/tokens.gd"
"$APP/src/main/assets/src/ui/components/top_bar.gd"
"$APP/src/main/assets/src/ui/components/tool_rail.gd"
"$APP/src/main/assets/src/ui/components/status_bar.gd"
"$APP/src/main/assets/src/ui/components/bottom_bar.gd"
"$APP/src/main/assets/src/ui/components/perf_overlay.gd"
"$APP/src/main/assets/src/ui/settings_panel.gd"
"$APP/src/main/assets/src/ui/workspace_sheet.gd"
"$APP/src/main/assets/src/ui/render_panel.gd"
"$APP/src/main/assets/src/ui/import_panel.gd"
"$APP/src/main/assets/assets/icons/stop.svg"
"$APP/src/main/assets/assets/icons/diamond-plus.svg"
"$APP/src/main/assets/assets/icons/tool-select.svg"
"$APP/src/main/assets/assets/icons/tablet.svg"
"$APP/src/main/assets/assets/icons/unlock.svg"
"$APP/src/main/assets/assets/icons/restart.svg"
```

- [ ] **Step 2: Verify staging against a fake Godot tree**

```bash
tmp="$(mktemp -d)"
mkdir -p "$tmp/platform/android/java/app"
printf 'minor = 7\npatch = 2\nstatus = "stable"\n' > "$tmp/version.py"
: > "$tmp/platform/android/java/app/build.gradle"
scripts/stage-android.sh "$tmp"
test -f "$tmp/platform/android/java/app/src/main/assets/src/ui/components/top_bar.gd"
test -f "$tmp/platform/android/java/app/src/main/assets/src/core/prefs.gd"
test -f "$tmp/platform/android/java/app/src/main/assets/assets/icons/stop.svg"
rm -rf "$tmp"
```
Expected: `Staged project: N files`, with no missing-file error.

- [ ] **Step 3: Harden the CI APK inspection**

Replace the `Inspect APK package and contents` step in `.github/workflows/build.yml` with:

```yaml
      - name: Verify package, ABI, signature, and staged assets
        run: |
          apk=Kinema-Studio-0.1.0-arm64-debug.apk
          "$ANDROID_HOME/build-tools/${ANDROID_BUILD_TOOLS}/aapt" dump badging "$apk" > badging.txt
          head -20 badging.txt
          grep -F "package: name='studio.kinema.app'" badging.txt
          grep -F "native-code: 'arm64-v8a'" badging.txt
          grep -E "targetSdkVersion:'3[5-7]'" badging.txt
          if grep -F "android.permission.INTERNET" badging.txt; then
            echo "error: the APK must not request INTERNET" >&2
            exit 1
          fi
          "$ANDROID_HOME/build-tools/${ANDROID_BUILD_TOOLS}/apksigner" verify --print-certs "$apk" | tee certs.txt
          grep -F "Android Debug" certs.txt
          unzip -l "$apk" | grep -E \
            'assets/project\.godot|assets/src/app/main\.tscn|assets/src/app/layout_math\.gd|assets/src/core/prefs\.gd|assets/src/core/perf\.gd|assets/src/ui/tokens\.gd|assets/src/ui/components/top_bar\.gd|assets/src/ui/components/perf_overlay\.gd|assets/src/ui/settings_panel\.gd|assets/src/ui/render_panel\.gd|assets/src/ui/import_panel\.gd|assets/assets/fonts/Inter\.ttf|assets/assets/licenses/godot/COPYRIGHT\.txt|lib/arm64-v8a/libgodot_android\.so'
```

The `Collect APK` step still copies from `app/build/outputs/apk/standard/debug/android_debug.apk`; do not add a local APK build path.

- [ ] **Step 4: Update the docs to the shipped behaviour**

In `README.md`:
- Replace the Forward+ only statement with: Android defaults to **Mobile / Vulkan**; Auto, Forward+, and Compatibility are selectable and switch through a real restart; the actual backend is shown; unsupported effects are disabled with a reason.
- Replace the responsive paragraph with the three modes: Compact (phone portrait), Studio (landscape/tablet), Desktop (menu bar, rail, dock, timeline, status bar). State that Desktop on a phone shrinks uniformly to a logical canvas of at least 960×600 and never falls back.
- Add the performance policy: preview renders on demand, continuous only during orbit/gizmo/playback, with adaptive preview scale and a real FPS/frame-time/draw-call readout.
- Update the render section: PNG still and PNG sequence ZIP only, transparent option, frame range `[start, end)`, real output path; MP4 is not supported.
- Update the import section: glTF/GLB and OBJ+MTL, scale/materials/textures options, FBX disabled with the conversion message, SAF sibling-file limitation.
- Update the tests section with the render and layout commands and the xvfb requirement.
- Remove claims that no longer match: old drawer-only responsive behaviour, Forward+ only, three presets, and “no transparent output” if present.

In `BUILD.md`:
- Add the same renderer default and restart explanation.
- Add the CI verification step and expected `aapt` lines.
- Add a device checklist for Android 15–17: cold start, portrait/landscape rotation, Compact/Studio/Desktop switching, Desktop fit percentage, inside-sheet taps, renderer restart and fallback, FPS overlay, OBJ/GLB import, still and sequence export, SAF cancel path.
- State explicitly that CI is the only APK build path and that no device verification is claimed until the checklist is run.

- [ ] **Step 5: Run the complete local verification**

```bash
GODOT=/data/data/com.termux/files/home/tools/Godot_v4.7.2-stable_linux.arm64
"$GODOT" --headless --path /root/kinema/studio res://tests/smoke.tscn
"$GODOT" --headless --path /root/kinema/studio --quit-after 4
xvfb-run -a -s "-screen 0 2560x1600x24" "$GODOT" --path /root/kinema/studio res://tests/render.tscn
xvfb-run -a -s "-screen 0 2560x1600x24" "$GODOT" --path /root/kinema/studio res://tests/layout.tscn
bash -n scripts/stage-android.sh
git diff --check
```
Expected: `SMOKE RESULT: PASS`, no parse errors, `RENDER RESULT: PASS`, `LAYOUT RESULT: PASS`, and no whitespace errors.

- [ ] **Step 6: Commit**

```bash
git add scripts/stage-android.sh .github/workflows/build.yml README.md BUILD.md
git commit -m "build: verify the APK contract and document the rebuild"
```

- [ ] **Step 7: Report, do not overclaim**

The final report must include the exact local command results, the CI workflow path, the expected artifact `app/build/outputs/apk/standard/debug/android_debug.apk`, and the fact that GitHub Actions has not run until the commit is pushed. Do not claim an APK, device performance, renderer restart, or orientation behaviour was verified without a CI run or a physical device.

---
