#!/usr/bin/env bash
# Stage the Kinema Studio project and Android resources into a pinned Godot
# source tree before a Gradle build.
#
# Usage:
#   scripts/stage-android.sh /path/to/godot-4.7.2-stable
#
# The Godot tree must be 4.7.2-stable. The script only writes inside
# platform/android/java/app; it does not modify engine C++ sources.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STUDIO="$ROOT/studio"
OVERLAY="$STUDIO/android/app"

if [[ $# -lt 1 ]]; then
    echo "usage: $0 /path/to/godot-4.7.2-stable" >&2
    exit 2
fi

GODOT_SRC="$(cd "$1" && pwd)"
APP="$GODOT_SRC/platform/android/java/app"

if [[ ! -f "$GODOT_SRC/version.py" || ! -f "$APP/build.gradle" ]]; then
    echo "error: '$GODOT_SRC' does not look like a Godot source tree" >&2
    exit 1
fi

if ! grep -q '^minor = 7$' "$GODOT_SRC/version.py" \
    || ! grep -q '^patch = 2$' "$GODOT_SRC/version.py" \
    || ! grep -q '^status = "stable"$' "$GODOT_SRC/version.py"; then
    echo "error: expected Godot 4.7.2-stable at '$GODOT_SRC'" >&2
    exit 1
fi

echo "Staging Kinema Studio into $APP"

# Project data is read directly from the APK's assets directory at runtime.
# Only runtime files are copied: the project manifest, fonts/icons, and source.
rm -rf "$APP/src/main/assets"
mkdir -p "$APP/src/main/assets"
cp "$STUDIO/project.godot" "$APP/src/main/assets/project.godot"
cp -R "$STUDIO/assets" "$APP/src/main/assets/assets"
cp -R "$STUDIO/src" "$APP/src/main/assets/src"

# Android resources and manifest override Godot's template defaults.
mkdir -p "$APP/res"
cp -R "$OVERLAY/res/." "$APP/res/"
cp "$OVERLAY/AndroidManifest.xml" "$APP/src/main/AndroidManifest.xml"

for required in \
    "$APP/src/main/assets/project.godot" \
    "$APP/src/main/assets/src/app/main.tscn" \
    "$APP/src/main/assets/src/core/gfx.gd" \
    "$APP/src/main/assets/src/core/obj_importer.gd" \
    "$APP/src/main/assets/src/core/render_export.gd" \
    "$APP/src/main/assets/src/viewport/studio_sky.gdshader" \
    "$APP/src/main/assets/assets/fonts/Inter.ttf" \
    "$APP/src/main/assets/assets/icons/tool-move.svg" \
    "$APP/src/main/assets/assets/icons/speed-graph.svg" \
    "$APP/src/main/assets/assets/licenses/godot/LICENSE.txt" \
    "$APP/res/values/themes.xml" \
    "$APP/res/mipmap-anydpi-v26/icon.xml" \
    "$APP/res/mipmap-xxxhdpi/icon_foreground.png" \
    "$APP/res/drawable-nodpi/kinema_splash.png"; do
    if [[ ! -f "$required" ]]; then
        echo "error: missing staged file: $required" >&2
        exit 1
    fi
done

echo "Staged project: $(find "$APP/src/main/assets" -type f | wc -l | tr -d ' ') files"
