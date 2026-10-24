# Building Kinema Studio

Kinema Studio is packaged as a custom Godot 4.7.2 Android application. It does
**not** use a Godot export preset or a `.pck` file: the project is copied as raw
files into the APK's `assets/` directory and read directly by the template
runtime. The build is a normal Gradle build of Godot's Android app module with a
replacement manifest and resource overlay.

The guaranteed build path is GitHub Actions. Termux cannot build this APK.

---

## Pinned versions

| Component | Version |
| --- | --- |
| Godot source | `4.7.2-stable`, commit `ed1daf0bf001b61586d9930840f2f1394092c079` |
| JDK | 17 (Temurin) |
| Android compile/target SDK | 36 |
| Android build-tools | 36.1.0 |
| Android NDK | 29.0.14206865 |
| Gradle | 8.11.1 (wrapper in Godot source) |
| Android Gradle Plugin | 8.6.1 (from Godot source) |
| SCons | 4.8.1 |
| Python | 3.x |
| Package | `studio.kinema.app` |
| Version | `0.1.0` (code `1`) |
| ABI | `arm64-v8a` |

The workflow checks out the tag and then verifies the commit hash. If the tag is
moved or the clone is wrong, the build stops before compiling.

---

## CI build (recommended)

Workflow: [`.github/workflows/build.yml`](.github/workflows/build.yml)

Triggers:

- push to `main`;
- pull request;
- manual `workflow_dispatch`.

The job:

1. checks out this repository;
2. installs JDK 17;
3. installs Android SDK 36, build-tools 36.1.0, and NDK 29.0.14206865;
4. installs SCons 4.8.1 and ccache;
5. clones Godot at `4.7.2-stable` and verifies the pinned commit;
6. runs `scripts/stage-android.sh` against the Godot tree;
7. generates a throwaway debug keystore;
8. builds `:app:assembleStandardDebug` with native libraries;
9. copies, hashes, inspects, and uploads the APK.

Artifact name: `Kinema-Studio-0.1.0-arm64-debug`.

The artifact contains:

```
Kinema-Studio-0.1.0-arm64-debug.apk
Kinema-Studio-0.1.0-arm64-debug.apk.sha256
```

The workflow is a **debug** build. It is suitable for installation and testing,
not for Play Store submission.

---

## Local Linux build

You need a 64-bit Linux host, roughly 25 GB of free disk space, and enough RAM
for the native build. The Android native build is the slow part; the first run
can take tens of minutes.

### 1. Prerequisites

- Git
- JDK 17 (`JAVA_HOME` set, `java -version` reports 17)
- Android SDK with:
  - `platforms;android-36`
  - `build-tools;36.1.0`
  - `ndk;29.0.14206865`
- Python 3 with SCons 4.8.1 available as `scons`
- Optional but recommended: `ccache`
- `ANDROID_HOME` (or `ANDROID_SDK_ROOT`) pointing at the SDK

Example SDK installation:

```bash
yes | sdkmanager --licenses
sdkmanager --install \
  "platforms;android-36" \
  "build-tools;36.1.0" \
  "ndk;29.0.14206865"

# Use a venv on distributions with PEP 668 enabled.
python3 -m venv "$HOME/.local/scons-venv"
"$HOME/.local/scons-venv/bin/pip" install "scons==4.8.1"
export PATH="$HOME/.local/scons-venv/bin:$PATH"
```

### 2. Fetch the pinned engine

```bash
git clone --depth 1 --branch 4.7.2-stable \
  https://github.com/godotengine/godot.git godot
test "$(git -C godot rev-parse HEAD)" = \
  ed1daf0bf001b61586d9930840f2f1394092c079
```

Use a clean clone. The staging script replaces the app module's `assets/`
directory, so do not point it at a tree containing unrelated project assets.

### 3. Stage the project and Android overlay

From the Kinema Studio repository root:

```bash
bash scripts/stage-android.sh "$PWD/godot"
```

The script verifies that the target looks like Godot 4.7.2-stable and writes
only inside `godot/platform/android/java/app`:

- replaces `src/main/assets/` with `project.godot`, `assets/`, and `src/`;
- copies `studio/android/app/res/` over the app's resource directory;
- replaces `src/main/AndroidManifest.xml` with the Kinema manifest;
- verifies the staged entry scene, Inter font, themes, adaptive icon, and splash
  icon exist.

No C++ engine source is modified.

### 4. Create a debug keystore

The build uses Godot's custom debug-keystore properties. The key password must
match the store password because Godot's Gradle config supplies the store
password for both.

```bash
keytool -genkeypair \
  -keystore "$HOME/kinema-debug.keystore" \
  -storepass kinema-ci \
  -keypass kinema-ci \
  -alias kinema \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -dname "CN=Kinema Studio CI, OU=Android, O=Kinema Studio, C=US"
```

### 5. Build

```bash
cd godot/platform/android/java

./gradlew --no-daemon :app:assembleStandardDebug \
  -PgenerateNativeLibs=true \
  -Pexport_package_name=studio.kinema.app \
  -Pexport_enabled_abis=arm64-v8a \
  -Pexport_version_code=1 \
  -Pexport_version_name=0.1.0 \
  -Pperform_signing=true \
  -Pperform_zipalign=true \
  -Pdebug_keystore_file="$HOME/kinema-debug.keystore" \
  -Pdebug_keystore_password=kinema-ci \
  -Pdebug_keystore_alias=kinema
```

Output:

```
godot/platform/android/java/app/build/outputs/apk/standard/debug/android_debug.apk
```

`-PgenerateNativeLibs=true` enables the SCons tasks; without it, Gradle expects
prebuilt native libraries. The upstream `selectedAbis` list is `arm64`, so the
native build produces arm64 only. `-Pexport_enabled_abis=arm64-v8a` keeps the
same ABI in the APK.

To use ccache, put it on `PATH` and pass the SCons launcher variables:

```bash
export CCACHE_DIR="$PWD/.ccache"
export CCACHE_MAXSIZE=2G
export SCONSFLAGS="c_compiler_launcher=ccache cpp_compiler_launcher=ccache"
```

The CI workflow sets these automatically and caches `.ccache`.

### 6. Verify the APK

```bash
"$ANDROID_HOME/build-tools/36.1.0/aapt" dump badging \
  android_debug.apk | head -20

"$ANDROID_HOME/build-tools/36.1.0/apksigner" verify --print-certs \
  android_debug.apk

unzip -l android_debug.apk | grep -E \
  'assets/project\.godot|assets/src/app/main\.tscn|assets/assets/fonts/Inter\.ttf|lib/arm64-v8a/libgodot_android\.so'
```

Expected package line:

```
package: name='studio.kinema.app' versionCode='1' versionName='0.1.0'
```

Install on a connected arm64 device:

```bash
adb install -r android_debug.apk
```

Grant no storage permission: imports and exports use the Android document
picker (SAF). The APK requests no internet permission.

---

## Headless project tests

A desktop Godot 4.7.2-stable build can run the project and the smoke test. An
ARM64 Linux build is used in the development environment; an x86_64 build works
the same way.

```bash
GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64

# Boot the app, then quit after a few frames.
"$GODOT" --headless --path studio --quit-after 3

# Run the regression test. It exits 0 on success.
"$GODOT" --headless --path studio res://tests/smoke.tscn
```

Successful output ends with:

```
SMOKE RESULT: PASS
```

The smoke test covers theme/font/icon loading, editor construction, primitives,
transform keys, key retiming, material color writes, gizmo accumulation,
undo/redo, save/load round trips, and project cleanup. It creates a temporary
project under `user://` and deletes it at the end.

Notes:

- Run the smoke test rather than per-script `--check-only`. Individual scripts
  reference the `Kit` and `Store` autoloads, which are not present under
  `--check-only`.
- The Android file picker, Vulkan/OpenGL fallback, safe-area insets, and touch
  gestures cannot be exercised headlessly. Those require device testing.
- The test writes to the Godot user directory. Ensure it is writable.

---

## Android overlay details

`studio/android/app` is a replacement overlay for Godot's template app:

| File | Purpose |
| --- | --- |
| `AndroidManifest.xml` | app identity, launcher alias, orientation, resizeability, no network permission |
| `res/values/strings.xml` | `Kinema Studio` app label |
| `res/values/colors.xml` | app background, icon background, amber accent |
| `res/values/themes.xml` | splash theme and transparent system bars |
| `res/mipmap-*` | legacy and adaptive launcher icons |
| `res/mipmap-anydpi-v33/icon.xml` | Android 13 monochrome icon |
| `res/drawable-nodpi/kinema_splash.png` | 1152×1152 splash artwork |

Godot's template app supplies the `GodotApp` activity in `com.godot.game`; the
application ID remains `studio.kinema.app`. The manifest uses a launcher
`activity-alias`, so the launcher entry remains stable even if the activity
class changes.

The app is `fullSensor`, resizeable, and uses a custom-drawn responsive layout.
The manifest declares no `INTERNET` permission. It targets API 36 and supports
API 24 and newer.

The renderer is Forward+/Vulkan with an OpenGL 3 fallback. The app's boot splash
is disabled in `project.godot` because Android's native splash handles startup.

---

## Why there is no `export_presets.cfg`

The Android app is built directly from Godot's Gradle app module. There is no
Godot editor export step, no PCK generation, and no import pass. `project.godot`
and the runtime files are placed under the APK's `assets/` directory, where the
template build reads them. This is deliberate: it keeps the build scriptable and
avoids depending on editor state.

Do not run a normal Godot "Export Project" workflow against this repository and
expect the same APK. The supported path is `scripts/stage-android.sh` followed
by the Gradle command above.

---

## Troubleshooting

**`scons` not found** — install SCons 4.8.1 and ensure `scons` resolves on
`PATH`; Gradle invokes it directly. Restart the shell after changing `PATH`.

**Wrong Java version** — use JDK 17. Godot's Gradle config validates the Java
version, and AGP 8.6.1 is configured for Java 17.

**NDK/SDK missing** — confirm `ANDROID_HOME`, `platforms;android-36`,
`build-tools;36.1.0`, and `ndk;29.0.14206865`. The versions are pinned in
Godot's `app/config.gradle`.

**Native build runs out of disk** — clean old Godot build directories, remove
unused NDKs/system images, and build only arm64. The CI workflow limits the job
to one ABI for this reason.

**APK installs but shows a Godot error** — inspect logcat:

```bash
adb logcat -s godot:V Godot:V AndroidRuntime:E
```

Check that `assets/project.godot` and `assets/src/app/main.tscn` are present in
the APK and that the app has not been built from a stale `assets/` directory.

**Staging says a file is missing** — confirm the splash icon is at
`studio/android/app/res/drawable-nodpi/kinema_splash.png` and the adaptive icon at
`studio/android/app/res/mipmap-anydpi-v26/icon.xml`. Re-run the script from the
repository root.

**Touch scrolling or text entry misbehaves** — keep
`input_devices/pointing/emulate_mouse_from_touch=true` in `project.godot`.
Standard `ScrollContainer` and `LineEdit` controls depend on the synthesized
mouse events; custom viewport gestures ignore those events explicitly.

---

## Release status

There is no release signing configuration, no Play Store bundle, and no AAB
workflow. The CI artifact is an internally signed debug APK. Before distributing
the app, add a private release keystore, build `assembleStandardRelease`, test on
target devices, and complete the store listing and policy work separately.
