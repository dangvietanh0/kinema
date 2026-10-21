# Kinema Studio

Kinema Studio is a touch-first 3D animation workspace for Android. It is a
small, local tool: open a project, place geometry, move it through time, and
capture a still. The interface follows a restrained Blender/Godot-like layout
rather than a game-style dashboard.

The app is built on **Godot Engine 4.7.2-stable**, using its 3D renderer, scene
graph, `Animation` resources, and glTF importer. The product layer is a custom
GDScript interface; the Android package is assembled from Godot's official
Android Gradle app.

> **Status: 0.1.0 prototype.** The source is complete and the headless test
> suite passes. A debug APK is built by GitHub Actions. The app has not yet been
> validated on a physical Android device, and no release build is provided.

---

## What it does

- **Project browser** — create a blank stage or a small animated study, reopen
  recent projects, rename or delete them. Project files stay on the device.
- **Scene authoring** — cube, sphere, cylinder, cone, torus, plane, empty,
  camera, directional light, omni light, and imported glTF models.
- **Direct manipulation** — select, move, rotate, and scale with a touch-sized
  axis gizmo; the same transforms are editable numerically in the inspector.
  The preview renders at device resolution, so edges and gizmos stay crisp on
  a phone screen.
- **Animation** — per-object position, rotation, and scale tracks in a compact
  dope sheet. Insert keys at the playhead, drag keys to retime, snap to frames,
  enable autokey, choose linear or cubic interpolation, and loop playback.
- **Responsive workspace** — a permanent scene/properties dock on wide screens;
  the dock becomes a drawer when the window is narrow. The timeline can be
  collapsed when the viewport needs room.
- **Still capture** — hide the grid and helper markers, re-render the current
  framing off-screen at a 1920 px long edge, and save a real PNG through
  Android's document picker (or directly to app storage if the picker is
  unavailable).
- **Local persistence** — human-readable JSON projects, a `models/` folder for
  imported assets, atomic writes, 30-second autosave, and undo/redo.
- **No network permission** — projects, imports, and exports are local.

### Not included

Kinema Studio 0.1 is intentionally narrow. It does **not** provide:

- video, MP4, GIF, image-sequence, or camera-animation export;
- skeletal rigging, skinning, constraints, IK, or pose libraries;
- physics simulation, particles, cloth, or destruction tools;
- text, curves, booleans, modifiers, sculpting, UV editing, or texture painting;
- a shader graph, scripting console, add-on system, or asset store;
- cloud sync, accounts, collaboration, or telemetry;
- glTF animation playback (models are imported as static scene references);
- `.gltf` files that depend on external `.bin` or texture files.

Only the current viewport frame is rendered to PNG. Nothing in the app claims
to produce video.

---

## Interface

### Home

The left column holds the project list and creation flow; the right side shows
a quiet preview of the workspace. **New project** asks for a name and a starting
point:

- **Blank stage** — camera, key light, and a neutral cube.
- **Primitive study** — a short looping form-and-orbit study with existing keys.

Recent projects expose **Rename** and **Delete** from their overflow menu.
Deleting a project also deletes its imported models.

### Editor

| Region | Purpose |
| --- | --- |
| Top bar | Back, project title, save, undo/redo, project menu |
| Left rail | Select, move, rotate, scale, frame selection, add object |
| Viewport | 3D stage, selection outline, axis gizmo, view compass |
| Compact bar | Add, Scene, Properties, timeline toggle (narrow screens) |
| Timeline | Playback, timecode, ruler, per-channel keys and tools |
| Right dock | Scene outliner and object inspector |
| Project menu | Settings, import, still render, help, about, close |

The inspector adapts to the selected object: transforms for every object,
material properties for meshes, field of view for cameras, and color, energy,
and range for lights.

A small **AUTO** indicator in the timeline shows when autokey is active.
Autosave runs every 30 seconds while the editor is open and the document is
dirty, but pauses while a modal sheet is open.

---

## Touch and keyboard controls

### Viewport

| Gesture | Action |
| --- | --- |
| One-finger drag | Orbit |
| Two-finger drag | Pan |
| Pinch | Zoom |
| One-finger tap | Select object |
| Drag an axis handle | Move, rotate, or scale on that axis |
| Mouse wheel | Zoom |
| Right/middle mouse drag | Pan |

The gizmo is large enough for a finger and ignores the synthesized mouse events
that Android produces from touch, so a gesture is never applied twice.

### Timeline

- Tap or drag the ruler to scrub.
- Drag a diamond to retime a key.
- Use the transport for start, previous key, play/pause, next key, and end.
- Toggle **AUTO** to insert/update transform keys while editing.
- Toggle **snap** to keep keys and transforms on clean frame/step values.
- Toggle **loop** for repeated playback.

### Hardware keyboard (optional)

| Shortcut | Action |
| --- | --- |
| `1` / `2` / `3` / `4` | Select / move / rotate / scale |
| `Space` | Play or pause |
| `F` | Frame selection |
| `Delete` | Delete selected object |
| `Ctrl+Z`, `Ctrl+Shift+Z` | Undo, redo (`Ctrl+Y` also redoes) |
| `Ctrl+S` | Save |
| `Esc` | Close the compact drawer or current modal |

The app is designed for touch first. A keyboard is a convenience, not a
requirement.

---

## Projects and storage

Everything is stored under Godot's `user://` directory, which maps to
**app-private storage** on Android. The logical layout is:

```
user://
├── recent_projects.json
└── projects/
    └── <timestamp>-<slug>/
        ├── project.json
        └── models/
            └── <imported>.glb
```

`project.json` is a versioned, human-readable document containing:

- title, frame rate, duration, loop, interpolation, current playhead, and
  selection;
- object records (kind, name, transform, color/material, camera/light fields,
  imported model path);
- animation tracks and keys in seconds.

Writes go to a temporary file and are then renamed, so an interrupted save does
not leave a half-written project. Recent entries are validated against the
filesystem when the app starts. Removing a project removes its folder and
models.

Projects are not exported to shared storage. PNG stills are the only files
written outside the app sandbox, and only when you choose a destination.

### Importing glTF

Use **Project → Import glTF model** or **Add object → Assets**. Kinema accepts:

- binary glTF (`.glb`);
- embedded glTF (`.gltf`) whose buffers and images are data URIs.

The file is copied into the project's `models/` folder, parsed with Godot's
`GLTFDocument`, and only added to the scene if parsing succeeds. External
buffers/textures are rejected with an explanatory message. Imported models are
static: animation or skinning data inside the file is not played.

Android's document picker may list files beyond glTF depending on the provider;
the import is validated after selection.

### Still export

**Project → Render still (PNG)** pauses playback, hides the grid and scene
helpers, then renders the same camera framing into an off-screen viewport whose
long edge is 1920 px, with 4× MSAA. The PNG is written through
`ACTION_CREATE_DOCUMENT`. If the native picker cannot be opened, the image is
saved in app storage and the location is shown in a toast. This is a real
render, not a placeholder.

---

## Building and testing

The Android APK cannot be built inside Termux. The authoritative build is the
GitHub Actions workflow; see **[BUILD.md](BUILD.md)** for the exact pinned
source, SDK/NDK versions, Gradle command, keystore, and local headless test
commands.

Quick reference:

- Package: `studio.kinema.app`
- Version: `0.1.0` (code `1`)
- ABI: `arm64-v8a`
- Minimum Android: API 24
- Target/compile SDK: API 36
- Renderer: Mobile / Vulkan, OpenGL 3 fallback
- Build type: debug, signed with a CI-generated debug key
- Output: `android_debug.apk`

The workflow runs on pushes to `main`, pull requests, and manual dispatch. The
APK and its SHA-256 are uploaded as a workflow artifact.

---

## Source layout

```
studio/
├── project.godot              app configuration and autoloads
├── assets/fonts/              Inter and JetBrains Mono (OFL)
├── assets/icons/              Lucide SVGs (ISC)
├── assets/licenses/           engine, font and icon notices
├── src/app/                   shell, home, editor
├── src/core/                  document model and project storage
├── src/ui/                    theme, inspector, outliner, timeline, overlays
├── src/viewport/              SubViewport, camera, gizmo, gestures, capture
├── android/app/               manifest and Android resources overlay
├── tests/smoke.gd             headless regression test
└── tools/                     icon rasterizer
scripts/stage-android.sh       stage project + overlay into Godot source
.github/workflows/build.yml    pinned Android debug build
```

The project uses raw assets inside the APK. There is no editor import pass and
no `.pck`; `project.godot`, scripts, fonts, and icons are read from the APK's
`assets/` directory at runtime.

---

## License

Original Kinema Studio code is released under the MIT License (see
[LICENSE](LICENSE)). Godot Engine and the bundled fonts/icons keep their own
licenses; see [THIRD_PARTY.md](THIRD_PARTY.md).
