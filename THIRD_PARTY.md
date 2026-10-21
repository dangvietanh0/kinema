# Third-party notices

Kinema Studio's original source is licensed under the MIT License (see
[LICENSE](LICENSE)). The following components are used by the application and
remain under their own licenses.

The full engine notice and the exhaustive Godot copyright file are bundled in
the APK under the project's `res://assets/licenses/godot/` path. The font and
icon license texts are also bundled with their assets.

---

## Godot Engine 4.7.2-stable

- **Project:** https://godotengine.org / https://github.com/godotengine/godot
- **License:** MIT (Expat)
- **Copyright:** 2014-present Godot Engine contributors; 2007-2014 Juan
  Linietsky, Ariel Manzur.
- **Use here:** 3D renderer, scene graph, animation runtime, glTF importer,
  Android platform layer, and the Android application template.
- **Source:** fetched from the upstream repository at build time and pinned to
  commit `ed1daf0bf001b61586d9930840f2f1394092c079`. The engine C++ source is not
  vendored in this repository and is not modified by the staging script.

Bundled notices:

- `studio/assets/licenses/godot/LICENSE.txt`
- `studio/assets/licenses/godot/COPYRIGHT.txt` (all Godot source files and
  third-party libraries compiled into the engine)

```
Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md).
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Inter

- **Project:** https://github.com/rsms/inter
- **License:** SIL Open Font License 1.1
- **Copyright:** 2020 The Inter Project Authors.
- **Files:** `studio/assets/fonts/Inter.ttf`
- **License text:** `studio/assets/fonts/OFL-Inter.txt`

The font is bundled unmodified and used for the interface. It is not sold on its
own.

---

## JetBrains Mono

- **Project:** https://github.com/JetBrains/JetBrainsMono
- **License:** SIL Open Font License 1.1
- **Copyright:** JetBrains s.r.o.
- **Files:** `studio/assets/fonts/JetBrainsMono.ttf`
- **License text:** `studio/assets/fonts/OFL-JetBrainsMono.txt`

The font is bundled unmodified and used for timecodes, numeric readouts, and
technical labels.

---

## Lucide icons

- **Project:** https://lucide.dev / https://github.com/lucide-icons/lucide
- **License:** ISC
- **Copyright:** Lucide Icons and Contributors.
- **Files:** SVG files under `studio/assets/icons/`
- **License text:** `studio/assets/icons/LICENSE.txt`

The SVGs are bundled unmodified. The app tints them at runtime through
`TextureRect` modulation; it does not redistribute modified icon files.

```
ISC License

Copyright (c) 2026 Lucide Icons and Contributors

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
```

---

## Build-time dependencies

The Android build resolves AndroidX, Kotlin, and Gradle components through the
Godot Android Gradle project. These components are not copied into this
repository; they are downloaded during the build under their own licenses
(primarily the Apache License 2.0). The resulting APK includes those binaries.
Before a public release, review the dependency licenses and add any notices
required by the exact resolved versions, including a user-visible open-source
licenses screen if the distribution policy requires one.

Godot's `COPYRIGHT.txt` covers the Godot engine and the third-party libraries
compiled into `libgodot_android.so`. It does not replace the AndroidX/Kotlin
notices.

---

## Trademarks

Godot is a trademark of the Godot Engine contributors. Android is a trademark
of Google LLC. Kinema Studio is an independent project and is not endorsed by
the Godot or Android projects.
