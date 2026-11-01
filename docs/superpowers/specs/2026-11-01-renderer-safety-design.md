# Renderer safety — never launch Forward+ on Android

Date: 2026-11-01
Branch: `ws/renderer-safety` (base `ab0af22`)
Supersedes: the "every renderer is selectable everywhere" claims in
`2026-10-23-kinema-professional-rebuild-design.md` §11 and §18.2.

## 1. Crash report

The user device-tested the Android build. Selecting **Forward+** in
Settings → Graphics and restarting crashed the app. **No device log is
available**, so this document does not claim a reproduction and does not
describe a stack trace. What is known is the code path:

1. `editor._restart_with_renderer()` built the restart argument by hand:
   `OS.set_restart_on_exit(true, ["--rendering-method", value])`.
2. The process restarted with `--rendering-method forward_plus` on Android.
3. Vulkan initialisation happens before any GDScript recovery code runs. If the
   device/driver does not provide the desktop Vulkan feature set Godot's
   Forward+ renderer needs, the engine can crash at that point — the app never
   reaches `Gfx`, `main.gd` or `ensure_renderer()` to fall back.
4. A stored `renderer_pending = "forward_plus"` written before the fix can make
   `Gfx.resolve_startup_renderer()`/`ensure_renderer()` request the same
   restart again on the next launch, and again on the launch after that.

The fix closes exactly that deterministic path. It is preventive: the gate is
proven on every platform parameter, but the Android crash itself remains
device-unverified until someone runs the Android build on a device and reads
its log.

Godot's `renderer/rendering_method.mobile="mobile"` project override already
keeps the default launcher path off Forward+ on Android. The defect was the
CLI override and the stored preference, not the project default.

## 2. Why Forward+ is desktop-only

Forward+ is Godot's desktop Vulkan renderer. It depends on the full desktop
Vulkan feature set (descriptor indexing and the desktop feature profile the
renderer declares); Godot's own mobile platforms use the `mobile` renderer or
`gl_compatibility`. On Android/iOS the honest capability list is therefore:

| Platform | Supported renderers |
| --- | --- |
| Android, iOS | `mobile`, `gl_compatibility` |
| Everything else (desktop, headless) | `forward_plus`, `mobile`, `gl_compatibility` |

`gl_compatibility` stays available everywhere because it is a real OpenGL
fallback, not a pretend option. The desktop default remains `forward_plus`;
the Android default remains `mobile` (unchanged `project.godot`:
`renderer/rendering_method="forward_plus"`, `.mobile="mobile"`,
`rendering_device/fallback_to_opengl3=true`).

## 3. Gate contract (`studio/src/core/gfx.gd`)

All functions are pure and take the platform explicitly (default
`OS.get_name()`), so tests can pass `"Android"`, `"iOS"` or `"Linux"`.

- `supported_renderers(platform) -> Array[String]`
  - Android/iOS: `["mobile", "gl_compatibility"]`
  - otherwise: `["forward_plus", "mobile", "gl_compatibility"]`
- `is_renderer_supported(method, platform) -> bool`
- `renderer_unavailable_reason(method, platform) -> String`
  - `""` when supported; for Forward+ on Android/iOS it names the missing
    desktop Vulkan feature set and the crash risk.
- `renderer_entries(platform) -> Array`
  - one `{label, value, supported, reason}` per renderer, in display order
    (Forward+, Mobile, Compatibility). UI and tests consume this; there is no
    duplicated renderer list in the UI.
- `sanitize_renderer_state(preference, pending, platform) -> Dictionary`
  - `{preference, pending, changed, reason}`. An unsupported preference or
    pending is repaired to the platform default
    (`renderer_default_for_platform`), pending clears, `changed` is true and
    `reason` explains why. Idempotent: sanitising the repaired state again
    changes nothing.
- `build_restart_args(preference, platform) -> PackedStringArray`
  - empty for any unsupported method or `auto`/`""`. It is impossible to get
    `--rendering-method forward_plus` on Android/iOS from this function.
- `prepare_renderer_switch(preference, platform) -> Dictionary`
  - blocked (unsupported target):
    `{restart_required: false, blocked: true, reason: <sentence>,
    preference: actual_method(), args: <empty>}`. It does not store the
    unsupported method, clears pending/attempts and never requests a restart.
  - supported target: today's shape
    `{restart_required, preference, args, actual}` plus `blocked: false`.
- `resolve_startup_renderer(preference, pending, actual, attempts, platform)`
  - sanitises both inputs. An unsupported pending is an immediate
    `action: "fallback"` with the platform default and `pending: ""`; args are
    only present when that default differs from `actual`. It can never return
    `action: "restart"` for an unsupported pending.
- `ensure_renderer()` passes `OS.get_name()` and acts on the sanitised result.

## 4. Repair on load

`Gfx._ready()` runs `sanitize_renderer_state()` right after
`load_preferences()` and before `apply_globals()`:

- a preferences file written by an older build cannot leave Forward+ as the
  preference or the pending request on Android;
- the repaired state is persisted, so the next launch starts clean;
- `last_renderer_error` carries the human reason.

`main.gd` still verifies a legitimate pending request through
`Gfx.ensure_renderer()`; the gate inside `resolve_startup_renderer()` means a
stale or hostile pending falls back instead of restarting. The restart loop is
bounded at two attempts, as before.

## 5. UI rule

`editor._open_renderer_sheet()` and `settings_panel._graphics()` build their
segments from `Gfx.renderer_entries(OS.get_name())`:

- only supported entries become selectable segments;
- on Android that is Mobile and Compatibility only; the sheet shows the real
  `renderer_unavailable_reason()` for Forward+, not a "coming soon" placeholder;
- desktop still shows all three;
- the note under the list says the restart never launches a backend the
  platform cannot use, and the "Renderer in use" row still reports the backend
  read back from `RenderingServer`.

Both restart entry points (`editor._restart_with_renderer()` and
`editor._on_settings_renderer_restart()`) call
`Gfx.prepare_renderer_switch()`. A blocked choice shows the reason in a toast
and leaves the running backend alone. No code outside `Gfx` builds
`--rendering-method` arguments any more.

## 6. Acceptance tests (`studio/tests/smoke.gd`, renderer steps)

- `supported_renderers("Android")` has exactly Mobile and Compatibility;
  `supported_renderers("Linux")` includes Forward+.
- `is_renderer_supported("forward_plus", "Android") == false` with a non-empty
  reason; `is_renderer_supported("forward_plus", "Linux") == true`.
- `sanitize_renderer_state("forward_plus", "forward_plus", "Android")` returns
  preference `mobile`, pending `""`, `changed == true`; a second call is
  unchanged.
- `build_restart_args("forward_plus", "Android").is_empty()`; Mobile args are
  `["--rendering-method", "mobile", "--rendering-driver", "vulkan"]` and never
  mention `forward_plus`.
- `prepare_renderer_switch("forward_plus", "Android")` is not required, is
  blocked, has empty args and does not leave `Gfx.renderer_preference` as
  `forward_plus`.
- `resolve_startup_renderer("mobile", "forward_plus", "mobile", 0, "Android")`
  is `fallback` with empty pending and no args; it never restarts.
- `renderer_entries("Android")` has three entries with Forward+ unsupported and
  Mobile supported; `renderer_entries("Linux")` is all supported.
- the editor renderer sheet's segment count equals
  `supported_renderers(OS.get_name()).size()` on the test platform.
- the pre-existing renderer assertions (restart args, bounded retry, platform
  default, renderer labels, sheet opens on the live backend) are kept.

Tests restore the `Gfx` renderer state after the blocked/Android calls so later
smoke steps observe the live state.

## 7. Proven headless vs. what still needs a device

Proven headless (Linux): the pure capability matrix, the empty Android restart
args, the blocked switch contract, the repair-on-load logic, the startup
fallback, the entry list and the UI segment filtering/note text.

Not proven: that the real Android build now launches Mobile (the APK was not
rebuilt or installed), and that Forward+ is what actually crashed the user's
device. The report of a crash comes from the user; there is no device log.
A device pass with the rebuilt APK should select Forward+ on Android (it must
not be offered), restart into Mobile and confirm the app stays up.

## Related

- `2026-10-23-kinema-professional-rebuild-design.md` §11/§18.2 — the renderer
  claims superseded here.
- `2026-10-27-kinema-professional-expansion-design.md` — §"Renderer restart"
  keeps the restart flow but the capability gate is defined by this document.
