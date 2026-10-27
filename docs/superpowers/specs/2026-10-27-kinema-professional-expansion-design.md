# Kinema Studio — Thiết kế mở rộng chuyên nghiệp (multi-clip, media, rigging)

- **Ngày:** 2026-10-27
- **Trạng thái:** Chờ duyệt — chưa viết code sản phẩm cho phần mở rộng này
- **Kế thừa:** `docs/superpowers/specs/2026-10-23-kinema-professional-rebuild-design.md` (gọi là **Spec cũ**). Spec cũ vẫn là nguồn sự thật cho mọi điểm không bị tài liệu này ghi đè.
- **Tài liệu này ghi đè:** các non-goal của Spec cũ về **MP4/WebM, audio, video timeline, IK, layer system**. Các non-goal còn lại của Spec cũ vẫn giữ nguyên.
- **Hướng đã chọn:** **A — contract-first, bốn workstream song song trong worktree riêng, merge tuần tự, tích hợp shell một lần.**
- **Nền tảng:** Android 15–17, Godot 4.7.2-stable (Android fork), GDScript + Java cho MediaCodec.
- **Đóng gói:** chỉ build qua GitHub Actions `assembleStandardDebug`, `arm64-v8a`, debug keystore của CI, package `studio.kinema.app`.
- **Người kiểm thử cuối:** bạn, trực tiếp trên Godot engine và thiết bị Android.

---

## 0. Tóm tắt một trang

Bản dựng lại trước đã đưa Kinema từ một prototype có pipeline thật thành một workbench ba chế độ, có token, layout matrix, renderer/settings thật và render PNG/ZIP thật. Bản mở rộng này không làm lại nền đó. Nó thêm **bốn nhóm năng lực** và hợp nhất ngôn ngữ hình ảnh mới:

| Nhóm | Năng lực | Kết quả nhìn thấy |
|---|---|---|
| **A. Animation** | Nhiều clip, transition, layer, blend, glTF animation tự chạy | Clip lane + layer panel; timeline vẫn là dope sheet/graph của clip đang sửa; sequence playback |
| **B. Media** | Audio track, video reference, GIF, MP4 có audio, camera-animation export | Media lanes, media export sheet, reference overlay, camera selector |
| **C. Rigging** | Skeleton, skinning, IK, pose library | Rig tab, bone tree, bind mesh, auto weights, IK chain, pose grid |
| **D. Redesign** | Token/kit mới, chrome, viewport header, mật độ, icon | Giao diện đúng ảnh before/after: nền đen thật, panel graphite, gutter 1 px, IBM Plex |

**Nguyên tắc bất biến:** không có nút giả, không có progress giả, không có file rỗng. Mọi năng lực mới phải có đường chạy thật, có test logic, có báo lỗi cụ thể, và có giới hạn được nói thẳng trên UI.

**Cách làm:** một **contract commit** duy nhất định nghĩa token, extension point của `document.gd`, và API rỗng của ba subsystem. Sau đó bốn agent làm trong bốn worktree riêng, mỗi agent chỉ sở hữu một tập file rời nhau. Merge theo thứ tự `redesign → animation → media → rig`, rồi một task tích hợp shell duy nhất nối các panel vào editor. Không agent nào được sửa file dùng chung ngoài tập file của mình.

**Điểm phải xác minh trên thiết bị:** MP4/MediaCodec, audio sync, video reference extraction, skinning/IK performance, cảm giác chạm của rig, safe area, xoay màn hình. Môi trường này không có thiết bị Android, nên mọi tuyên bố về các điểm đó chỉ là "đã build, chờ test".

---

## 1. Ý định và hiện trạng

### 1.1 Vì sao mở rộng

Kinema hiện là một công cụ dựng cảnh và keyframe transform cho một cảnh, một take. Nó chưa đủ để gọi là studio animation:

- chỉ có một `Animation` tên `Take 01`; không có clip, không có transition, không có layer;
- không có audio, không có video reference;
- render chỉ ra PNG/ZIP; MP4 bị từ chối có chủ đích;
- không có xương, skin, IK hay pose library;
- giao diện đã được dựng lại nhưng chưa lấy đúng ngôn ngữ của bản redesign mới (nền đen thật, gutter, mật độ, viewport header).

### 1.2 Những gì đang chạy đúng và phải giữ

- `document.gd`: scene graph, object record, key insert/retime/delete, easing scalar, undo/redo, serialize v1, imported glTF/OBJ.
- `project_store.gd`: project folder, recent list, save/load, import copy.
- `render_export.gd`: PNG still, PNG sequence, ZIP thật.
- `editor_view.gd`: SubViewport, editor camera, gizmo, picking, HUD, capture still.
- `timeline.gd`: dope sheet, speed graph, transport, ease editing.
- `editor.gd`: shell ba chế độ, settings, workspace sheet, render mode, autosave.
- `smoke.gd`, `layout.gd`, `capture.gd`: regression, layout matrix, ảnh QA.
- Toàn bộ token/kit hiện tại: graphite, 0 px radius, 44 dp, IBM Plex.

Không viết lại các phần này. Chỉ thêm extension point và thay lớp trình bày khi redesign yêu cầu.

### 1.3 Vấn đề gốc của bản mở rộng

1. **Model một take** ăn sâu vào `document.gd`, `timeline.gd`, `editor.gd`. Nếu thêm clip bằng cách nhân đôi code sẽ tạo hai nguồn sự thật.
2. **Không có lớp media**: audio/video cần một timeline toàn cục, trong khi dope sheet hiện là timeline của take.
3. **Rigging là subsystem mới**, không thể nhét vào `object` hiện tại mà không có skeleton/skin/IK data.
4. **MP4 cần native encoder**. GDScript thuần không có encoder; phải có Java MediaCodec/MediaMuxer thật, không được giả.
5. **Bốn nhóm chạm cùng file** nếu làm tuần tự trong một cây. Cần contract và phân quyền file trước khi song song.

---

## 2. Mục tiêu, không mục tiêu, anti-goal

### 2.1 Mục tiêu

| Mã | Mục tiêu | Cách đo |
|---|---|---|
| G1 | Nhiều clip trong một project | Tạo/duplicate/rename/delete clip; serialize v2; mở lại đúng |
| G2 | Transition và blend thật | Crossfade 0.5 s; layer weight 0.5; mute/solo; test mixer định lượng |
| G3 | Layer system thật | Ít nhất một base layer + một overlay layer; blend override/additive; UI sửa được |
| G4 | glTF/GLB animation tự chạy | Import GLB có animation; clip được tạo; phát ngay; test bằng GLB sinh tại runtime |
| G5 | Audio track thật | Import WAV/OGG/MP3; phát đúng sequence; volume/trim/fade; MP4 có audio |
| G6 | Video reference thật | Import video; trích frame proxy; scrub; overlay opacity/fit; xoá sạch |
| G7 | GIF thật | Encode GIF89a; mở được; đúng số frame; test cấu trúc |
| G8 | MP4 thật có audio | Java MediaCodec/MediaMuxer; H.264 + AAC; verify file; test trên thiết bị |
| G9 | Camera-animation export | Render từ scene camera đã animate; xuất camera track JSON; verify |
| G10 | Rigging thật | Tạo skeleton, bind mesh, auto weights, pose, key, IK; test toán học + device |
| G11 | Pose library thật | Lưu/áp dụng/key/delete pose; serialize; test |
| G12 | Redesign hợp nhất | Token mới; viewport header; chrome; icon; 44 dp; layout matrix pass |
| G13 | Không giả | Không nút/format nào không có đường chạy; UI nói rõ giới hạn |
| G14 | Bằng chứng trước khi tuyên bố | Parse sạch; tất cả suite pass; layout pass; CI APK; device checklist |

### 2.2 Không mục tiêu (trong pass này)

- Multi-select, group, reparenting object.
- Physics, particle, cloth, constraint solver đầy đủ.
- Weight painting bằng cọ; chỉ có auto weight theo khoảng cách + chỉnh hệ số ảnh hưởng từng xương (xem câu hỏi Q1).
- Bone envelope, twist bones, humanoid retargeting, motion capture.
- Import FBX nhị phân hoặc ASCII.
- Light theme, localization, cloud sync, collaboration, plugin system.
- Render farm/background export khi app đã thoát.
- Real-time video playback trong viewport cho MP4; dùng frame proxy (xem Q2).
- FOV animation của camera; FOV là thuộc tính tĩnh trong pass này.
- Chỉnh rest pose của skeleton import; chỉ pose/key.
- Multi-object import: mỗi file vẫn là một document object.
- Bezier/S-curve easing thật; transition của key vẫn là scalar hiện có.
- Thay Godot host bằng native Android UI.

### 2.3 Anti-goal (làm ra là thất bại dù có chạy)

- Nút MP4 bật nhưng file rỗng, hoặc encode bằng cách đổi đuôi PNG thành `.mp4`.
- Audio track chỉ là một block trang trí, không phát và không vào MP4.
- Video reference chỉ là ảnh tĩnh giả, không scrub được.
- Skeleton chỉ là các que vẽ overlay, không deform mesh.
- IK "chạy" bằng cách dịch node, không giải xương.
- Pose library lưu ảnh chụp, không lưu rotation.
- Clip lane đẹp nhưng playback vẫn chỉ phát `Take 01`.
- Layer weight thay đổi nhưng mixer bỏ qua.
- Redesign biến mọi thứ thành pill/gradient/glass, hoặc hạ hit target xuống 32 dp trên touch.
- Merge làm mất các tính năng đã có (settings, workspace, perf overlay, render mode).
- Test pass bằng cách xoá assertion hoặc bỏ qua nhánh khó.

---

## 3. Ràng buộc và quyết định nền

### 3.1 Ràng buộc kỹ thuật

- Godot **4.7.2-stable**, GDScript; project chạy từ raw assets, không cần editor import pass.
- Android host hiện tại; Java source được stage vào Godot Android app module; build chỉ qua CI.
- Không có thiết bị Android trong môi trường này. MP4/audio/video/skinning/IK phải có device checklist.
- `RenderingServer` không đổi renderer tại runtime; giữ restart flow hiện có.
- Android SAF có thể trả `content://`; audio/video import phải copy vào project hoặc báo lỗi rõ.
- `JavaClassWrapper` là cầu GDScript → Java trên Android; chỉ có trên Android runtime. Trên Linux/headless, facade phải trả `unsupported` có lý do.
- Không thêm GDExtension/native C++ mới. Java MediaCodec là backend native duy nhất được thêm.
- Không có ffmpeg/ImageMagick/PIL trong môi trường test; GIF/PNG/MP4 verification phải bằng Godot/Java.

### 3.2 Ràng buộc thiết kế

- Touch-first: **mọi control tương tác ≥ 44 dp** ở cả ba mode. Đây là quyết định giữ nguyên, kể cả khi ảnh redesign ghi Studio 40/Desktop 32.
- Primary action: 96×44 dp; secondary footer: 80×44 dp; action chính không bao giờ là hình vuông.
- Landscape ưu tiên; portrait vẫn phải dùng được.
- Góc: panel 0 px, control 2 px, floating 4 px (theo redesign).
- Gutter 1 px màu đen giữa các vùng; hairline 1 px cho separator.
- Achromatic chrome; chỉ DANGER và trục X/Y/Z có hue.
- IBM Plex Sans cho UI; IBM Plex Mono cho timecode/ruler/số liệu cần tabular.
- Không gradient/glass/shadow trang trí; không animation trang trí.
- Text tối thiểu 11 sp; 10 sp chỉ cho ruler tick.
- Không dùng màu làm tín hiệu duy nhất.
- Mọi sheet có scroll, max-height, safe-area; không cắt control.

### 3.3 Ràng buộc hiệu năng

- Preview idle vẫn `UPDATE_ONCE`; playback mới render liên tục.
- Mixer + IK + skinning phải chạy trong budget UI < 8 ms/frame ở cảnh test; số đo thật ghi trong report.
- Không cấp phát mảng mới mỗi frame trong mixer/IK; cache track index và buffer.
- Auto weight chạy một lần khi bind, không chạy mỗi frame.
- Video proxy extraction chạy nền (Java thread), có progress/cancel; không block UI.
- MP4 encode chạy nền (Java thread); GDScript chỉ poll trạng thái.

---

## 4. Phương án và quyết định

### 4.1 Phương án A — Contract-first, bốn workstream song song (đã chọn)

Một contract commit định nghĩa token, extension point và API rỗng. Bốn worktree riêng, mỗi worktree chỉ sửa file thuộc sở hữu của mình. Merge tuần tự, rồi tích hợp shell một lần.

**Ưu:** tận dụng song song; file ownership rõ; review diff sạch; ít conflict; có contract để test trước.
**Nhược:** cần đầu tư thiết kế contract; nếu contract sai, cả bốn workstream lệch.
**Giảm thiểu:** contract có test riêng; API rỗng có `push_error` rõ; integrator giữ quyền sửa file dùng chung.

### 4.2 Phương án B — Tuần tự một cây

Làm A → B → C → D trên cùng worktree.

**Ưu:** đơn giản, không conflict.
**Nhược:** chậm; mỗi nhóm chờ nhóm trước; khó tận dụng agent; review khổng lồ.
**Kết luận:** loại, vì yêu cầu là bốn nhóm đầy đủ trong pass này.

### 4.3 Phương án C — Bốn cây độc lập rồi chép file

Mỗi agent copy cả project, làm xong, integrator chép file vào cây chính.

**Ưu:** cô lập tối đa.
**Nhược:** mất lịch sử git theo task; khó review; dễ chép nhầm file; test tích hợp muộn.
**Kết luận:** loại. Dùng worktree + merge; nếu conflict, integrator chép đúng file theo ownership.

### 4.4 Quyết định đã chốt trong hội thoại

- Bạn chọn **A**.
- Bạn test trực tiếp trên Godot engine/thiết bị; automated test vẫn phải có.
- Agent làm trong thư mục riêng, copy file cần thiết, merge cuối.
- Bốn nhóm phải đầy đủ trong pass này, không mock.
- MP4 dùng MediaCodec/MediaMuxer thật; GIF thuần GDScript; video reference cần decoder/proxy.
- Rigging là subsystem mới.
- Redesign chỉ là tham chiếu hình ảnh/component; không thay thế toàn bộ cây hiện tại.

---

## 5. Ngôn ngữ hình ảnh hợp nhất

### 5.1 Token

Lấy đúng bảng của redesign, trừ hit target:

| Token | Giá trị | Ghi chú |
|---|---|---|
| `BG` | `#000000` | void, gutter, letterbox |
| `SURFACE` | `#0E0E0E` | panel body |
| `SURFACE_2` | `#151515` | bar, panel header |
| `SURFACE_3` | `#1D1D1D` | control/input well |
| `SURFACE_HOVER` | `#272727` | hover |
| `SURFACE_ACTIVE` | `#333333` | selected row/toggle on |
| `BORDER` | `#3C3C3C` | hairline mạnh |
| `BORDER_SOFT` | `#242424` | hairline yếu |
| `TEXT` | `#EBEBEB` | primary |
| `TEXT_MUTED` | `#A6A6A6` | secondary |
| `TEXT_DIM` | `#858585` | tertiary, chỉ trên SURFACE_3 |
| `FOCUS` | `#EDEDED` | primary fill |
| `TIME` | `#B8B8B8` | key/playhead/transport |
| `DANGER` | `#E5706B` | destructive/error |
| `AXIS_X/Y/Z` | `#C1675F` / `#86A87B` / `#6F90B8` | chỉ viewport gizmo/compass |
| `R_PANEL` | `0` | panel, sheet body |
| `R_CONTROL` | `2` | button, field, chip |
| `R_FLOAT` | `4` | menu, dialog, toast |
| `GUTTER` | `1` | gutter đen giữa vùng |

### 5.2 Mật độ và hit target

| Mode | Bar | Header | Row | Control | Hit floor |
|---|---:|---:|---:|---:|---:|
| Compact | 48 | 44 | 44 | 44 | **44** |
| Studio | 44 | 36 | 44 | 44 | **44** |
| Desktop | 36 (menu bar) | 32 | 40 | 40 | **44** cho control tương tác; menu bar pointer được miễn |

Quyết định: **không hạ hit target xuống 40/32**. Redesign dùng 40/32 để dày hơn; điều đó xung đột với ràng buộc touch 44 dp của bạn. Ta giữ 44 dp cho mọi control tương tác, chỉ giảm chiều cao **chrome không tương tác** (header, bar, gutter) và dùng glyph 18/20 px. Desktop menu bar là pointer-only, được miễn bằng `qa_hit_exempt` như hiện tại.

### 5.3 Thành phần mới

- **Viewport header** (mới): strip trên viewport, `Perspective` + `Add` bên trái, `Grid` + `Frame` bên phải. Không nổi trên ảnh; thuộc về viewport.
- **Clip lane** (mới): dải clip/layer phía trên timeline. Cao 64 dp; strip 44 dp; playhead global; nút play sequence; nút Layers.
- **Media lanes** (mới): audio lane 48 dp/track; video reference lane 40 dp; nằm dưới dope sheet, có thể gập.
- **Rig tab** (mới): trong dock, cạnh Scene/Props; bone tree + bone inspector + bind + IK + pose.
- **Media export sheet** (mới): thay render sheet cũ; format PNG/GIF/MP4; camera; audio; range; output; progress.
- **Media import sheet** (mới): audio/video reference; format, copy, proxy options.
- **Pose grid** (mới): chip 44 dp, name + apply/key/delete.
- **IK chain row** (mới): root/end/target/weight/pole/iterations/bake.
- **Audio track inspector** (mới): start/trim/volume/mute/fade in/out; waveform nếu WAV.
- **Video reference panel** (mới): opacity/fit/offset/scale/flip; frame info.
- **Camera selector** (mới): Editor / scene camera; trong media export sheet.

### 5.4 Icon

- Grid 24, stroke 1.5, glyph 18/20, cùng một family.
- Thêm: `blend`, `layers`, `key-round`, `film`, `audio-wave`, `video`, `gif`, `mp4`, `camera`, `bone`, `pose`, `target`, `link`, `unlink`, `weight`, `scissors`, `transition`, `proxy`.
- Không emoji, không icon ngoài grid, không fill lẫn outline trong cùng cấp.

### 5.5 Motion và accessibility

- `MOTION_FAST 0.10`, `MOTION_BASE 0.16`; chỉ dùng cho sheet/toggle/hover; không animation trang trí.
- Mọi action có label hoặc tooltip; icon-only có accessible name qua tooltip + text fallback.
- Focus ring 1 px FOCUS; không bỏ focus khi dùng bàn phím.
- Contrast: text thường ≥ 4.5:1 trên surface đang đứng; control boundary ≥ 3:1.
- Reduced motion: setting `display.reduce_motion` tắt animation chuyển cảnh.

---

## 6. Kiến trúc multi-clip

### 6.1 Model dữ liệu (format v2)

```json
{
  "format": 2,
  "title": "Walk cycle",
  "fps": 24,
  "interpolation": "linear",
  "active_clip": "clip_walk",
  "active_layer": "layer_base",
  "clips": [
    {
      "id": "clip_walk",
      "name": "Walk",
      "duration": 2.0,
      "loop": true,
      "tracks": [
        {"path": "Cube:position", "type": "position_3d", "keys": [{"t": 0.0, "v": [0,0,0], "e": 1.0}]}
      ]
    }
  ],
  "layers": [
    {
      "id": "layer_base",
      "name": "Base",
      "weight": 1.0,
      "blend": "override",
      "muted": false,
      "solo": false,
      "strips": [
        {
          "id": "strip_1",
          "clip": "clip_walk",
          "start": 0.0,
          "trim_start": 0.0,
          "trim_end": 2.0,
          "speed": 1.0,
          "weight": 1.0,
          "fade_in": 0.0,
          "fade_out": 0.0,
          "ease": 1.0
        }
      ]
    }
  ],
  "objects": [],
  "rigs": [],
  "media": {}
}
```

- `clips` giữ dữ liệu nguồn. Mỗi clip sở hữu một `Animation` resource trong bộ nhớ; serialize thành mảng track như trên.
- `layers` là NLA đơn giản: mỗi layer có nhiều strip; strip tham chiếu clip; strip có trim/speed/weight/fade.
- `duration` toàn cục **không lưu**; tính từ `sequence_duration()` = max(strip end) trên các layer không mute, tối thiểu 0.04.
- `active_clip` là clip đang sửa trong dope sheet/graph. `active_layer` là layer đang chọn trong clip lane.
- Format v1 migrate: `animation` cũ → một clip tên `Take 01`, một strip ở `layer_base` start 0, fade 0. Không mất key, duration, loop.

### 6.2 Ý nghĩa thời gian

Đây là quyết định quan trọng để không phá timeline hiện tại:

- `doc.duration` = **duration của active clip** (clip-local). Với project v1 đã migrate, bằng duration cũ.
- `doc.current_time` = **thời gian local của active clip**. `doc.seek(t)` tua clip đang sửa.
- `doc.sequence_duration()` = độ dài sequence toàn cục.
- `doc.sequence_time()` = playhead toàn cục.
- `doc.seek_sequence(t)` đặt sequence time, tìm strip đang active, đặt active clip + local time tương ứng, và đánh giá mixer.
- `doc.play()` phát clip đang sửa (loop theo clip). `doc.play_sequence()` phát toàn bộ sequence, cập nhật `current_time` theo strip đang active.
- Timeline dope/graph tiếp tục đọc `duration/current_time`; không phải sửa hợp đồng của nó.
- Clip lane đọc `sequence_duration/sequence_time`; có play/pause/stop riêng.
- Audio và video reference bám **sequence time**, không bám clip-local. Khi sửa clip, chúng dừng; UI ghi rõ "Audio follows the sequence".

### 6.3 Mixer

`src/core/clip_mixer.gd` là class thuần, không phụ thuộc scene:

```gdscript
static func evaluate(
    clips: Dictionary,        # clip_id -> Animation
    layers: Array,            # layer dictionaries
    time: float,              # sequence time
    object_ids: PackedStringArray,
    base_poses: Dictionary,   # object_id -> {position, rotation, scale}
    bone_paths: Dictionary    # track path -> {rig_id, bone}
) -> Dictionary
```

Trả về:

```gdscript
{
  "objects": {
    "obj_1": {"position": Vector3, "rotation": Quaternion, "scale": Vector3, "weight": float}
  },
  "bones": {
    "obj_rig": {"Hips": {"rotation": Quaternion, "weight": float}}
  }
}
```

Thuật toán:

1. Duyệt layer từ dưới lên. Bỏ layer mute. Nếu có layer solo, chỉ xét các layer solo.
2. Với mỗi strip đang phủ `time`:
   - local = `trim_start + (time - start) * speed`.
   - Nếu clip loop: `fmod(local, clip.duration)`; nếu không: clamp.
   - `weight = layer.weight * strip.weight * fade(time)`.
   - `fade` dùng smoothstep cho `fade_in`/`fade_out`; `ease` là scalar time-warp giống key transition.
3. Trong cùng layer, nếu hai strip cùng phủ (crossfade), chuẩn hoá weight của chúng rồi blend theo thứ tự start.
4. Với mỗi track của clip:
   - Object channel: sample bằng `position_track_interpolate`, `rotation_track_interpolate`, `scale_track_interpolate`.
   - Bone rotation: sample `rotation_track_interpolate`; path dạng `"<rig_node>/Skeleton3D:<bone>"`.
   - Override: `acc = lerp(acc, value, w)`; rotation dùng `slerp`.
   - Additive: position `acc += (value - base) * w`; rotation `acc *= slerp(IDENTITY, value * base.inverse(), w)`; scale `acc *= lerp(ONE, value / base, w)`.
   - Không có contribution thì giữ base pose.
5. Trả về pose cuối; document áp lên node/skeleton.

**Base pose:** object base là transform tĩnh lưu trong `objects` (giá trị inspector khi không có animation đóng góp), không phải pose tạm đang hiển thị. Bone base là rest pose lưu trong rig (`Skeleton3D.get_bone_rest`), không phải bind pose của skin. `base_poses` được dựng lại từ hai nguồn này mỗi lần evaluate, không serialize riêng. Không có contribution thì giữ base; weight < 1 thì blend từ base.

**Fade:** `fade_in` và `fade_out` nằm **trong** strip, không mở rộng strip. Envelope smoothstep từ 0 tại `start` lên 1 tại `start + fade_in`, và từ 1 tại `end - fade_out` xuống 0 tại `end`. Crossfade 0.5 s = hai strip chồng nhau 0.5 s, mỗi strip có fade tương ứng; sequence duration vẫn là max(strip end). Nếu `fade_in + fade_out > duration`, clamp tỉ lệ và ghi warning.

**Fast path:** nếu sequence tại `time` chỉ có một strip weight 1, không layer phụ, không fade, document dùng `AnimationPlayer` như hiện tại. Khi có transition/layer/fade, document tắt `AnimationPlayer.active` và áp mixer. Điều này giữ nguyên hành vi/test hiện có cho project một clip, đồng thời cho phép blend thật.

### 6.4 Track path và bone

- Object: `"<node_name>:position"`, `"<node_name>:rotation"`, `"<node_name>:scale"`.
- Bone: `"<rig_node_name>/Skeleton3D:<bone_name>"`, type `rotation_3d`.
- Rig object có root transform riêng; root motion đi qua object transform, không qua bone root.
- Mixer cache `find_track` theo clip + path; không gọi `find_track` mỗi frame.

### 6.5 UI

**Clip lane** (mới, `src/ui/clip_lane.gd`):
- Hàng layer (44 dp): tên, weight, mute/solo, blend mode, thêm layer.
- Mỗi strip: block 44 dp, tên clip, màu luminance theo layer; selected có viền 1 px FOCUS.
- Kéo block để move; kéo handle trái/phải để trim; handle fade 44×44 hit area (có thể nằm ngoài block).
- Nút `+ Clip`, `Layers`, `Play sequence`, `Fit`.
- Tap strip → chọn active clip + strip; mở strip sheet (bottom sheet) để sửa start/trim/speed/weight/fade/ease/blend.
- Transition: khi hai strip chồng nhau, vẽ vùng crossfade bằng hatch 1 px; kéo fade handle để đổi thời lượng.

**Clip sheet** (mới): danh sách clip; New/Duplicate/Rename/Delete; duration; loop; active. Delete clip đang được strip tham chiếu phải hỏi và xoá strip hoặc chặn — chọn chặn kèm lý do.

**Layer sheet** (mới): name, weight slider + numeric, blend override/additive, mute/solo, delete (không xoá layer cuối).

**Dope/graph**: giữ nguyên; thêm label `Clip: Walk · 2.0 s` ở header timeline. Không thêm tab mới vào timeline để tránh conflict với WS-D.

**Sequence playback**: nút play trong clip lane; khi chạy, timeline transport hiển thị playhead local của strip đang active và disable play clip để tránh hai clock. Audio/video reference chạy theo sequence.

### 6.6 glTF/GLB embedded animation

- `imported_scene_ready(object_id, node)` chỉ phát **một lần trên đường import** (sau khi object đã spawn), không phát khi load/undo. `_spawn_object()` chỉ phát `object_spawned(object_id, node)` nội bộ; vì vậy load/undo không quét lại GLB và không tạo clip trùng.
- `AnimationSystem` quét `AnimationPlayer` trong scene imported:
  - Mỗi animation → một clip mới, tên `<object> · <animation>`.
  - Remap track path từ scene imported sang path trong document: `<object_node>/<imported_path>`.
  - Tạo strip trên layer `Imported` (tạo nếu chưa có), start = 0, fade 0, weight 1.
  - Nếu có nhiều animation, active clip = animation đầu; `doc.play()` ngay sau import.
  - Sau khi copy, đặt **tất cả** `AnimationPlayer` trong scene imported thành `active = false`. Giữ node để đọc dữ liệu nguồn, nhưng không cho nó chạy song song với mixer. Track không remap được (blend shape, method track, node ngoài document) bị bỏ và liệt kê trong báo cáo import; không giả rằng chúng đã chạy.
- `RigSystem` cũng nhận signal này để adopt `Skeleton3D` (pose/IK), nhưng không sửa animation.
- Nếu animation track trỏ tới node không tồn tại, bỏ track đó và ghi warning; không làm hỏng clip.
- Nếu GLB không có animation, không tạo clip; import vẫn thành công.
- Test: tạo scene Node3D + AnimationPlayer + animation, export GLB bằng `GLTFDocument.append_from_scene`/`write_to_filesystem`, import qua `Store`, assert clip + auto-play + track path.

### 6.7 Migration và serialize

- `FORMAT_VERSION = 2`.
- `load_project`:
  - Nếu `format <= 1`: tạo `AnimationSystem` từ `animation` cũ; một clip `Take 01`; một strip; `active_clip`; `duration`/`loop` giữ nguyên.
  - Nếu `format == 2`: load clips/layers/rigs/media.
- `to_data` ghi `format: 2`, `clips`, `layers`, `rigs`, `media`; không ghi `animation` cũ (hoặc ghi mirror để tool cũ đọc? Không cần).
- Undo/redo: snapshot hiện tại là `to_data()`; clip/layer/rig/media changes phải nằm trong snapshot. Các thao tác lớn (bind mesh, auto weight, pose key) là một undo step.
- Autosave/save/load giữ nguyên; project v1 mở được, save thành v2.

### 6.8 Test animation

- `tests/animation.gd`:
  - v1 → v2 migration giữ key/duration/loop.
  - clip CRUD; duplicate độc lập key.
  - strip move/trim/speed; sequence duration.
  - crossfade 0.5 s: tại midpoint, giá trị = trung bình theo weight; tại start/end đúng clip.
  - layer override weight 0.5; additive; mute/solo.
  - fade in/out smoothstep.
  - bone track sample.
  - glTF embedded animation import + auto-play.
  - mixer performance: 200 track, 60 sample, dưới ngưỡng (ghi số đo).
- RED trước khi implement từng nhóm.

---

## 7. Kiến trúc media

### 7.1 Audio track

**Dữ liệu:**

```json
{
  "audio": [
    {
      "id": "aud_1",
      "name": "Footsteps",
      "file": "audio/footsteps.wav",
      "start": 0.0,
      "trim_start": 0.0,
      "trim_end": 4.0,
      "volume": 1.0,
      "muted": false,
      "fade_in": 0.1,
      "fade_out": 0.2
    }
  ]
}
```

**Import:**
- Hỗ trợ `.wav`, `.ogg`, `.mp3`; copy vào `<project>/audio/`; load bằng `AudioStreamWAV.load_from_file`, `AudioStreamOggVorbis.load_from_file`, `AudioStreamMP3.load_from_file` (đã xác nhận có trong ClassDB 4.7.2).
- Nếu load fail: xoá file copy, báo lỗi cụ thể.
- Tên track lấy từ file; cho rename.

**Playback:**
- Mỗi track một `AudioStreamPlayer` con của `MediaSystem`.
- Chỉ phát ở sequence mode. Khi `play_sequence`/`seek_sequence`, tính expected = `sequence_time - start + trim_start`; nếu trong [trim_start, trim_end], `play(expected)`; nếu lệch > 0.08 s, `seek(expected)`.
- Volume: `linear_to_db(volume * fade_envelope)`; fade cập nhật mỗi frame.
- Pause/stop: dừng tất cả; seek: restart đúng vị trí.
- Không phát khi clip mode; UI ghi rõ.

**Waveform:**
- WAV: đọc PCM, tính peak 512-sample bucket, vẽ trong lane.
- OGG/MP3: không decode waveform; vẽ band phẳng có nhãn "waveform unavailable" (không giả).
- Waveform cache trong `user://cache/waveforms/<hash>.json`.

**WAV mixdown (optional):**
- Nếu tất cả track là WAV: mix PCM 44.1 kHz stereo, áp start/trim/volume/fade, ghi `.wav`; verify header.
- Nếu có OGG/MP3: nút disabled, lý do "WAV mixdown needs WAV sources; MP4 export decodes other formats in the Android backend." Không giả.

**UI:**
- Audio lane dưới dope sheet; mỗi track một hàng 48 dp; block từ start đến trim_end; selected có viền.
- Tap track → audio sheet: start, trim start/end, volume, mute, fade in/out, delete.
- Nút `+ Audio` trong lane hoặc Add sheet.
- Media tab? Không; dùng sheet từ lane để tránh nhồi dock.

### 7.2 Video reference

**Mục tiêu:** đưa video tham chiếu vào để rotoscope/so sánh, không phải phát video real-time trong 3D.

**Import:**
- Android: `.mp4`, `.m4v`, `.mov` → Java `KinemaVideoFrames.extract(videoPath, outDir, fps, maxWidth)` dùng `MediaMetadataRetriever.getFrameAtTime` (microseconds), ghi JPEG + `reference.json`.
- Mọi nền tảng: `.ogv` → dùng `VideoStreamPlayer` trực tiếp, không trích frame.
- Proxy mặc định: 12 fps, max width 1280; setting trong Media.
- Progress/cancel; chạy Java thread; GDScript poll.
- Output: `<project>/video_refs/<id>/frames/frame_000001.jpg` + `reference.json`:
```json
{"version":1,"fps":12,"duration":4.0,"width":1280,"height":720,"frames":["frame_000001.jpg", "..."]}
```
- Nếu extract fail: xoá thư mục, báo lỗi; không tạo reference rỗng.

**Hiển thị:**
- `VideoReferenceOverlay` (Control) nằm trên `PreviewSurface`, dưới HUD; `mouse_filter = IGNORE`; texture frame theo `sequence_time`.
- Điều khiển: opacity 0–100%, fit contain/cover, offset X/Y, scale, flip H, visible.
- Frame index = `floor(sequence_time * fps)`; clamp; nếu sequence dừng, giữ frame.
- Trong clip mode: dùng `strip.start + current_time` của active strip để chọn frame; nếu không có strip, frame 0.
- Timeline lane: block từ 0 đến duration; tap để bật/tắt; kéo để đổi offset (start).
- Xoá reference: xoá data + thư mục; undo không khôi phục file (cảnh báo).

**Giới hạn:**
- MP4 extraction chỉ Android; Linux/editor trả unsupported. `.ogv` phát được mọi nền tảng có VideoStreamPlayer.
- Proxy không có audio; audio reference không thuộc scope.
- Dung lượng: giới hạn 2 GB/thư mục proxy; cảnh báo trước khi extract.

### 7.3 GIF export

`src/core/gif_encoder.gd`:
- GIF89a, global color table 256 màu, NETSCAPE loop extension, disposal 1.
- Delay từng frame bằng accumulator: `round((i+1)*100/fps) - round(i*100/fps)` centiseconds, tối thiểu 1. Nhờ vậy 24 fps và 30 fps đúng trung bình dù GIF chỉ có centisecond. Chỉ bật 12/24/30 fps; 60 fps disable với lý do "GIF timing is centisecond-based; 60 fps cannot be represented".
- Quantize: median-cut trên histogram RGBA; Floyd–Steinberg optional (setting); alpha < 0.5 → background.
- LZW encode đúng spec; clear code/end code.
- `encode(frames: Array[Image], fps: int, loop: bool) -> PackedByteArray`.
- Kích thước: 320/480/640/720 max width; giữ aspect; frame count = range × fps.
- Verify: header `GIF89a`, trailer `0x3B`, logical screen size, frame count, file size > 0; test parse cấu trúc.
- UI: format GIF trong media export sheet; progress theo frame; output `.gif`; mở bằng gallery/device.

### 7.4 MP4 export — Java MediaCodec/MediaMuxer

**Kiến trúc:**

```
GDScript MediaExport
  → render frames PNG vào user://renders/tmp_<id>/
  → AndroidVideo.encode(manifest_json, output_path)
      → Java KinemaVideoEncoder (thread)
          → MediaCodec H.264 (video/avc)
          → MediaCodec AAC (audio/mp4a-latm)
          → MediaMuxer MP4
      → poll progress/done/error
  → verify + cleanup
```

**Java class:** `studio/android/app/java/studio/kinema/media/KinemaVideoEncoder.java`
- `public static void encode(String manifestJson, String outputPath)`
- `public static int progress()`, `public static boolean done()`, `public static String error()`, `public static void cancel()`
- `public static String capabilities()` → JSON: supported AVC profiles/levels, max width/height, AAC sample rates.
- `public static String probe(String path)` → JSON: duration, width, height, video/audio track, mime.
- Manifest:
```json
{
  "width": 1920, "height": 1080, "fps": 24,
  "bitrate": 12000000,
  "frameDir": "/data/user/0/studio.kinema.app/files/renders/tmp_x",
  "framePattern": "frame_%04d.png",
  "frameCount": 144,
  "audio": [
    {"path": "...", "start": 0.0, "trimStart": 0.0, "trimEnd": 4.0, "volume": 0.8, "fadeIn": 0.1, "fadeOut": 0.2}
  ]
}
```
- Video: decode PNG bằng `BitmapFactory`; chuyển ARGB → YUV420 planar; feed `MediaCodec` input buffer; presentation time = frame/fps; drain output; mux.
- Audio: `MediaExtractor` + `MediaCodec` decode từng file (AAC/MP3/Vorbis/Opus/FLAC tùy thiết bị); mix PCM 44.1 kHz stereo; áp start/trim/volume/fade; encode AAC 128/192 kbps; mux.
- Nếu audio decode fail: dừng, error nêu tên file; không bỏ im lặng.
- Nếu không có audio: chỉ video track.
- Cancel: flag; dọn output dở.
- Verify: file > 0; `probe` duration ±1 frame; có video track; có audio track nếu manifest có audio.
- Thread: một encode tại một thời điểm; nếu đang chạy, từ chối encode mới.

**GDScript facade:** `src/core/android_video.gd`
- `available() -> bool`: `OS.get_name() == "android"` và `JavaClassWrapper.wrap("studio.kinema.media.KinemaVideoEncoder")` thành công.
- `capabilities() -> Dictionary`.
- `encode(manifest, output_path) -> Dictionary`; `poll() -> Dictionary`; `cancel()`; `probe(path)`.
- Trên Linux/headless: `available=false`, `reason="MP4 encoding uses the Android MediaCodec backend. Build the Android APK to export MP4."`.
- Không gọi Java khi không Android.

**Stage/build:**
- `scripts/stage-android.sh` copy `studio/android/app/java` → `$APP/src/main/java`.
- CI compile Java bằng Gradle; thêm bước kiểm tra file `.java` tồn tại trong app module trước khi build.
- CI không chạy được MediaCodec; device test bắt buộc.

**UI:**
- Media export sheet: format PNG/GIF/MP4; MP4 disabled trên non-Android với lý do.
- Resolution: **1280×720 / 1920×1080 / 2560×1440 chính xác** (disable nếu vượt capability); fps 12/24/30/60; bitrate 4/8/12/20 Mbps; range; camera; audio mix toggle; output. Probe và camera dùng đúng size, không suy từ aspect viewport.
- Progress: `Frame 42/144` → `Encoding video` → `Verifying`; cancel.
- Kết quả: path, size, duration, tracks; nút "Open folder" nếu SAF cho phép.
- Không toast success trước khi `probe` pass.

### 7.5 Camera animation export

- **Render camera:** media export sheet chọn `Editor camera` hoặc một scene camera object. Nếu chọn scene camera, `SequenceRenderer` lấy transform/FOV tại từng frame từ document (position/rotation đã animate; FOV tĩnh).
- **Capture:** `EditorView.capture_with_camera(long_edge, msaa, transform, fov)` (extension point contract). Probe SubViewport dùng camera transform/FOV, `UPDATE_ONCE`, đọc Image.
- **Camera track JSON:**
```json
{
  "version": 1,
  "fps": 24,
  "duration": 4.0,
  "camera": "Camera",
  "fov": 46.0,
  "frames": [
    {"t": 0.0, "position": [0,1,4], "rotation": [0,0,0,1]}
  ]
}
```
- Verify: JSON parse; frame count; mỗi frame có position/rotation; duration khớp.
- UI: nút "Export camera track (.json)" trong media export sheet, chỉ bật khi chọn scene camera.
- Giới hạn: FOV tĩnh; không xuất lens shift/roll riêng; rotation là quaternion.

### 7.6 Sequence renderer

`src/core/sequence_renderer.gd` (mới):
- Nhận doc, editor_view, options (width/height/fps/range/camera/format), callbacks progress/cancel.
- Với mỗi frame:
  - `doc.seek_sequence(t)` (hoặc clip mode? sequence).
  - Chờ mixer/IK/skinning settle (1 frame nếu cần).
  - Capture bằng editor camera hoặc scene camera.
  - Ghi PNG tạm.
- Không block UI: `await process_frame` giữa các frame.
- Trả về `{ok, frames_dir, frame_count, error}`.
- Dùng chung cho PNG sequence, GIF, MP4.
- Không ghi đè file; timestamp + sequence.
- Cleanup: xoá temp sau khi ZIP/GIF/MP4 thành công; giữ temp + path nếu fail.

### 7.7 Media test

`tests/media.gd`:
- Audio: tạo WAV PCM 1 s bằng code; import; track add; expected offset math; mute; fade; WAV mixdown header.
- Video: tạo 5 JPEG frame giả + `reference.json`; load reference; frame index theo time; xoá sạch.
- GIF: 3 frame 16×16; encode; parse header/trailer/frame count/size; loop extension.
- Camera JSON: export; parse; frame count; transform roundtrip.
- MP4 facade: trên Linux `available=false` và lý do đúng; manifest builder tạo đúng frame count/audio entries.
- Sequence renderer: render 3 frame 64×64 PNG; verify files; cancel giữa chừng không tạo output cuối.
- Không test MediaCodec thật trên Linux; ghi rõ.

---

## 8. Kiến trúc rigging

### 8.1 Model dữ liệu

```json
{
  "rigs": [
    {
      "id": "rig_1",
      "object_id": "obj_rig",
      "name": "Rig",
      "bones": [
        {"name": "Root", "parent": -1, "rest": {"p": [0,0,0], "r": [0,0,0,1], "s": [1,1,1]}, "length": 0.4, "influence_scale": 1.0},
        {"name": "Spine", "parent": 0, "rest": {"p": [0,0.4,0], "r": [0,0,0,1], "s": [1,1,1]}, "length": 0.5, "influence_scale": 1.0}
      ],
      "skins": [
        {"mesh_object_id": "obj_mesh", "file": "skins/rig_1_obj_mesh_ab12cd.bin", "hash": "ab12cd",
         "vertex_count": 1024, "influences": 4, "bone_names": ["Root", "Spine"],
         "source": {"kind": "primitive", "value": "cube"}, "bind_transform": [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]}
      ],
      "ik": [
        {"id": "ik_1", "name": "Arm IK", "root": "UpperArm", "end": "Hand",
         "target_object_id": "obj_target", "weight": 1.0, "iterations": 12,
         "pole_angle": 0.0, "enabled": true}
      ],
      "poses": [
        {"id": "pose_1", "name": "T-Pose", "bones": {"Root": [0,0,0,1]}, "root_position": [0,0,0]}
      ],
      "active_bone": "Root"
    }
  ]
}
```

- `bones` lưu local rest transform; thứ tự parent trước con.
- `skins` lưu weight per vertex; giới hạn 4 influence; tổng weight = 1.
- `ik` lưu chain theo tên xương; target là object id.
- `poses` lưu rotation từng xương + root position.
- Rig object là `kind: "rig"` trong `objects`; node chứa `Skeleton3D` tên `Skeleton3D`.

### 8.2 Tạo skeleton

- Add sheet → `Rig` tạo object + `RigSystem.create_rig(name, at)`.
- Mặc định 1 xương `Root` dài 0.4, rest identity.
- Rig tab:
  - Bone tree (parent/child, indent 12 dp, row 44 dp).
  - Add bone (con của bone chọn; offset mặc định theo trục Y dài 0.4).
  - Rename, reparent (chọn parent từ dropdown; chặn cycle), delete (chặn nếu còn con hoặc đang có skin; hỏi).
  - Bone inspector: rest position/rotation/scale, length; numeric fields 44 dp.
  - `Reset pose` cho bone/all.
- Skeleton3D build lại khi rest thay đổi; pose hiện tại giữ nếu bone còn tồn tại.

### 8.3 Skinning

**Bind mesh:**
- Chọn rig + mesh object (primitive hoặc imported mesh) → `Bind`.
- **Không reparent.** Mesh và rig vẫn là hai object anh em; bind xong mesh bị khoá transform theo rig (`mesh.global_transform = rig.global_transform`) và inspector hiện "Bound to Rig". Lý do: giữ outliner phẳng, selection và undo object hiện tại không đổi; tránh double transform.
- Lấy mesh arrays; transform vertex từ mesh local sang rig local.
- Với mỗi vertex:
  - Tính khoảng cách tới đoạn thẳng head→tail của từng bone (rig space).
  - Chọn 4 bone gần nhất; weight = `1 / (d + 0.001)^2`; chuẩn hoá.
  - Nếu bone có `influence_scale`, nhân weight trước khi chuẩn hoá.
- Ghi `bones`/`weights` vào rig data; build `ArrayMesh` với `ARRAY_BONES`/`ARRAY_WEIGHTS`; tạo `Skin` bằng `Skeleton3D.create_skin_from_rest_transforms()`; gán `MeshInstance3D.skin`, `skeleton` path.
- Với mesh có nhiều surface: bind từng surface, giữ material.
- Giới hạn 50.000 vertex; quá giới hạn → lỗi rõ, không treo.
- Imported skinned mesh: giữ skin gốc; rig adopt skeleton; không auto-bind lại trừ khi user chọn "Rebind".
- Unbind: xoá skin record, trả mesh về trạng thái tĩnh (duplicate mesh gốc? giữ bản gốc trong data? Cần lưu `source_mesh` arrays? Có thể rebuild từ primitive/imported model; nếu không, giữ mesh đã bind nhưng bỏ skin → biến dạng mất. Thiết kế: lưu `source` reference (primitive kind hoặc model path) và rebuild khi unbind. Với imported mesh, reload từ file. Nếu không reload được, báo lỗi và giữ bind.)
- UI hiển thị: `Bound 1,024 vertices · 4 influences · 2 bones` hoặc lỗi.

**Weight chỉnh tay (nếu Q1 chọn có):**
- Bổ sung sau khi duyệt; nếu không, chỉ có `influence_scale` per bone + rebind.

### 8.4 IK

`src/core/ik_solver.gd`:
- FABRIK cho chain N xương:
  - Lấy vị trí world của head/tail từ `Skeleton3D.get_bone_global_pose`.
  - Target world; pole vector từ `pole_angle` quay quanh trục chain.
  - Lặp: backward/forward reach; clamp reachable; giữ bone length.
  - Chuyển vị trí world về rotation local cho từng bone, dùng rest transform và parent.
- `solve(skeleton, chain, target_world, weight) -> Dictionary[bone_name -> Quaternion]`.
- Weight 0 → không đổi; weight 1 → end effector tại target nếu reachable; unreachable → chain thẳng về target.
- Iterations 8–24; tolerance 0.001.
- Áp dụng sau mixer, trước render; nếu bone có key trong clip, IK override theo weight.
- Hook: `Document.process_priority = 100` để `AnimationPlayer` cập nhật trước; `Document._process` gọi `rig_system.advance(delta)` sau `animation_system.advance()`. `advance()` giải mọi chain đang bật ở scrub, clip playback, sequence playback và export. `sequence_renderer` gọi thêm `solve_ik()` ngay trước `capture_with_camera()` để không phụ thuộc thứ tự frame.
- Bake: ghi rotation đã solve vào key tại `current_time` cho từng bone; một undo step.
- UI: add chain, root/end dropdown, target object picker (empty state nếu chưa có object), weight slider + numeric, pole angle, iterations, enabled, Bake.
- Không hỗ trợ constraint khác (look-at, copy rotation) trong pass này.

### 8.5 Pose library

- Save pose: chụp rotation tất cả bone + rig root position; tên bắt buộc; lưu vào rig data.
- Apply: set bone pose rotations; root position; không key.
- Key pose: apply + ghi rotation key cho tất cả bone tại `current_time` của active clip; một undo step.
- Rename/delete; duplicate.
- UI: grid 2 cột (Compact) / 3 cột (Studio+), chip 44 dp; empty state "No poses yet. Pose the rig, then Save pose."; search nếu > 12.
- Không lưu ảnh thumbnail trong pass này (tránh file rác); hiển thị tên + số bone.

### 8.6 Bone animation

- `document.insert_bone_key(rig_object_id, bone, rotation, time)`:
  - Track path `"<rig_node>/Skeleton3D:<bone>"`, type `rotation_3d`.
  - Ghi vào active clip Animation.
- `document.get_bone_keys(rig_object_id, bone)` trả local time.
- `document.sample_bone(...)` dùng `rotation_track_interpolate`.
- Clip mixer trả bone rotations; document áp `Skeleton3D.set_bone_pose_rotation`.
- Rig tab có mini key list cho bone chọn: prev/next/delete; `Key bone` 44 dp; `Key pose` 44 dp.
- Timeline dope sheet không hiển thị bone track trong pass này; rig tab là nơi quản lý. Ghi rõ trong Help.
- Imported glTF skeleton: bone names giữ nguyên; track path remap theo node imported; pose/IK dùng được; rest edit bị chặn.

### 8.7 Rig overlay

`src/ui/rig_overlay.gd`:
- Nằm trên viewport, dưới HUD; `mouse_filter = PASS` để không chặn orbit khi không ở rig mode.
- Vẽ xương: line 2 px màu TEXT_MUTED; selected FOCUS; joint circle 6 px; hit radius 22 dp (44 dp đường kính).
- Tap bone → select; drag bone → rotate quanh head theo screen-space trackball; numeric fields trong rig tab để chỉnh chính xác.
- IK target: line 1 px dashed tới target; target handle 44 dp.
- Chỉ bật khi rig object được chọn và tool `pose` (thêm tool id `pose` vào tool rail? Tool rail hiện có select/move/rotate/scale. Thêm `pose` chỉ hiện khi rig selected; hoặc rig tab tự bật overlay. Chọn: rig tab bật overlay; tool rail vẫn select/move/rotate/scale cho object.)
- Không sửa `editor_view.gd`; integrator thêm overlay như sibling và nối tín hiệu.

### 8.8 Rig test

`tests/rig.gd`:
- Rig data roundtrip; add/parent/rest; cycle prevention.
- Auto weights: tổng = 1; vertex gần bone A weight A cao; 4 influence; mesh 50k limit error.
- Bind: Skin bind count; ArrayMesh có ARRAY_BONES/ARRAY_WEIGHTS; vertex count.
- IK: 2-bone reachable → end effector trong 1e-3; unreachable → chain dài tối đa; weight 0 → không đổi; pole angle đổi plane.
- Pose: save/apply/key; bone keys sample; delete.
- Imported skeleton adoption: build Skeleton3D + MeshInstance3D + Skin; gọi adopt; assert rig record + pose được.
- UI smoke: rig tab build; add bone; bind; save pose; IK row.
- Không test deform trên GPU; test toán học + arrays; device xác nhận hình ảnh.

---

## 9. Contract, API và phân quyền file

### 9.1 Contract commit

Contract commit là commit duy nhất trước khi tách worktree. Nó chứa:

1. Token/kit mới (đọc được bởi cả bốn WS).
2. `document.gd` extension point:
   - `var animation_system`, `var media_system`, `var rig_system` là **`RefCounted` do `Document` sở hữu**, không phải node con. Chúng được tạo trong `Document._init()` trước mọi lời gọi `new_project`/`load_project`, và **không bị `_clear_runtime()` huỷ**. `_clear_runtime()` chỉ gọi `reset()` trên từng subsystem.
   - Thứ tự nạp cố định: `_clear_runtime()` → `_ensure_player()` → `reset()` cả ba → `_apply_data()` (spawn object; hook `on_object_spawned` chỉ dựng phần runtime) → `animation_system.load_data()` → `rig_system.load_data()` → `media_system.load_data()` → gán `animation = animation_system.active_animation()` → `seek()`. Undo/redo dùng đúng thứ tự này trên snapshot.
   - `_process` của `Document` đặt `process_priority = 100` để `AnimationPlayer` con (priority 0) cập nhật trước, rồi mới gọi `animation_system.advance()`, `rig_system.advance()` và `media_system.advance()`.
   - Signal: `clips_changed`, `active_clip_changed(id)`, `media_changed`, `rigs_changed`, `rig_selection_changed(rig_id, bone)`, `imported_scene_ready(object_id, node)`.
   - `to_data`/`_apply_data` gọi subsystem serialize.
   - `_spawn_object` gọi `rig_system.on_object_spawned(obj, node)`; `_apply_visual_properties` gọi `rig_system.on_object_properties(obj, node)`.
   - `_process` gọi `animation_system.advance(delta)` và `media_system.advance(...)`; fast path giữ AnimationPlayer.
   - `seek/play/pause/stop` gọi subsystem transport.
   - `capture_with_camera` trên `editor_view.gd`.
   - `world_to_screen`/`screen_ray` public trên `editor_view.gd` cho rig overlay.
3. API rỗng của `animation_system.gd`, `media_system.gd`, `rig_system.gd` với comment hợp đồng và `push_error("not implemented")`.
4. `project_store.gd` không đổi; import signal do document phát.
5. Test contract:
   - v1 project load không lỗi; subsystem rỗng không phá.
   - `to_data` có `format: 2`.
   - extension point được gọi (spy).
6. `scripts/stage-android.sh` copy Java source (có thể để sau, WS-B sở hữu file; contract thêm dòng copy).
7. `.github/workflows/build.yml` thêm test job (có thể ở task CI riêng; contract chỉ cần build không vỡ).

Contract commit phải xanh parse + smoke + layout trước khi tách nhánh.

### 9.2 API hợp đồng

**AnimationSystem** (`src/core/animation_system.gd`):

```gdscript
func setup(document) -> void
func reset() -> void
func to_data() -> Dictionary
func load_data(data: Dictionary, nodes: Dictionary) -> void

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

func import_gltf_animations(object_id: String, node: Node) -> PackedStringArray
func on_imported_scene(object_id: String, node: Node) -> void
```

**MediaSystem** (`src/core/media_system.gd`):

```gdscript
func setup(document) -> void
func reset() -> void
func to_data() -> Dictionary
func load_data(data: Dictionary, project_dir: String) -> void

func import_audio(uri: String) -> Dictionary
func add_audio_track(rel_path: String, start: float) -> String
func update_audio_track(id: String, patch: Dictionary) -> void
func delete_audio_track(id: String) -> void
func audio_tracks() -> Array

func import_video_reference(uri: String) -> Dictionary   # async; emits progress
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

**RigSystem** (`src/core/rig_system.gd`):

```gdscript
func setup(document) -> void
func reset() -> void
func to_data() -> Dictionary
func load_data(data: Dictionary, nodes: Dictionary) -> void

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

func start_bind(rig_id: String, mesh_object_id: String, options: Dictionary) -> String  # job id
func poll_bind(job_id: String) -> Dictionary  # {state, progress, result, error}
func cancel_bind(job_id: String) -> void
func unbind_mesh(rig_id: String, mesh_object_id: String) -> bool
func set_bone_influence_scale(rig_id: String, bone: String, scale: float) -> void

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

**Document bổ sung:**

```gdscript
func sequence_duration() -> float
func sequence_time() -> float
func seek_sequence(time: float, silent := false) -> void
func play_sequence() -> void
func pause_sequence() -> void
func stop_sequence() -> void
func is_sequence_playing() -> bool

func insert_bone_key(rig_object_id: String, bone: String, rotation: Quaternion) -> int
func get_bone_keys(rig_object_id: String, bone: String) -> Array
func delete_bone_key(rig_object_id: String, bone: String, index: int) -> void
func sample_bone(rig_object_id: String, bone: String, time: float) -> Quaternion
func insert_pose_keys(rig_object_id: String, pose: Dictionary) -> void
```

**EditorView bổ sung:**

```gdscript
func capture_with_camera(size: Vector2i, msaa: int, xform: Transform3D, fov: float, transparent_bg := false) -> Image
func world_to_screen(world: Vector3) -> Vector2
func screen_ray(screen: Vector2) -> Dictionary   # {origin, direction}
```

### 9.3 Phân quyền file

| File / nhóm | Chủ sở hữu | Ghi chú |
|---|---|---|
| `src/ui/tokens.gd`, `kit.gd`, `assets/icons/*` | **WS-D** | Contract tạo bản mới; D tinh chỉnh |
| `src/ui/components/top_bar.gd`, `bottom_bar.gd`, `tool_rail.gd`, `status_bar.gd`, `viewport_header.gd` | WS-D | Chrome |
| `src/ui/outliner.gd`, `inspector.gd`, `timeline.gd`, `overlay.gd`, `num_field.gd`, `scrub_bar.gd` | WS-D | Visual; không đổi hành vi |
| `src/app/home.gd`, `editor.gd` (visual), `settings_panel.gd`, `workspace_sheet.gd`, `perf_overlay.gd` | WS-D | `editor.gd` sau merge do integrator sửa |
| `src/viewport/editor_view.gd` (HUD/header) | WS-D | Contract thêm API camera/ray |
| `src/core/animation_system.gd`, `clip_mixer.gd` | WS-A | Mới |
| `src/ui/clip_lane.gd`, `clip_sheet.gd`, `layer_sheet.gd`, `strip_sheet.gd` | WS-A | Mới |
| `src/core/media_system.gd`, `audio_library.gd`, `video_reference.gd`, `gif_encoder.gd`, `sequence_renderer.gd`, `camera_export.gd`, `android_video.gd` | WS-B | Mới |
| `src/ui/media_lanes.gd`, `audio_sheet.gd`, `video_reference_panel.gd`, `media_export_sheet.gd`, `media_import_sheet.gd` | WS-B | Mới |
| `studio/android/app/java/studio/kinema/media/*.java` | WS-B | Mới |
| `scripts/stage-android.sh` (dòng copy Java) | WS-B | Chỉ thêm copy; integrator review |
| `src/core/rig_system.gd`, `skinning.gd`, `ik_solver.gd`, `pose_library.gd` | WS-C | Mới |
| `src/ui/rig_panel.gd`, `bone_tree.gd`, `pose_panel.gd`, `ik_panel.gd`, `rig_overlay.gd` | WS-C | Mới |
| `tests/animation.gd`, `media.gd`, `rig.gd` + `.tscn` | WS-A/B/C tương ứng | Mới |
| `src/core/document.gd`, `project_store.gd`, `app/main.gd` | **Integrator** | Contract + tích hợp |
| `src/app/editor.gd` (wiring), `tests/smoke.gd`, `layout.gd`, `capture.gd`, CI workflow | **Integrator** | Sau merge |

**Luật:** không WS nào sửa file ngoài bảng trên. Nếu cần API mới, gửi yêu cầu cho integrator; integrator thêm vào contract hoặc tự nối sau merge. Không sửa `document.gd` sau contract.

### 9.4 Worktree và merge

- Nhánh chính: `feat/professional-rebuild` (hiện tại).
- Contract commit trên nhánh chính.
- Tạo bốn worktree từ contract:
  - `.worktrees/kinema-ws-redesign`
  - `.worktrees/kinema-ws-animation`
  - `.worktrees/kinema-ws-media`
  - `.worktrees/kinema-ws-rig`
- Mỗi WS chạy test riêng; commit nhỏ theo TDD; không push.
- Merge thứ tự:
  1. **redesign** — vì nó đổi token/kit/chrome; các WS khác đọc token từ contract, không bị ảnh hưởng.
  2. **animation** — clip lane + mixer; không chạm editor.
  3. **media** — media lanes + export; không chạm editor.
  4. **rig** — rig tab + overlay; không chạm editor.
- Sau mỗi merge: parse + smoke + layout headless. Nếu fail, sửa ngay trên nhánh merge trước khi merge tiếp.
- Integrator task cuối: nối panel vào editor, thêm tab/nút/sheet, cập nhật smoke/layout/capture, chạy full suite, capture ảnh, review.
- Nếu conflict ngoài dự kiến: integrator giữ file theo ownership, chép phiên bản của chủ sở hữu, không tự viết lại logic.

---

## 10. Tích hợp shell (serial)

Sau bốn merge, integrator làm một task duy nhất:

1. **Editor shell**
   - Thêm `ClipLane` trên timeline; thêm `MediaLanes` dưới timeline; thêm `RigPanel` vào dock tab.
   - Add sheet thêm `Rig`, `Audio`, `Video reference`.
   - Render sheet thay bằng `MediaExportSheet`; giữ quick still/render mode.
   - Settings thêm category `Media`, `Rig`.
   - Workspace sheet giữ nguyên; cập nhật mô tả panel mới.
2. **Transport**
   - Clip lane play sequence ↔ document `play_sequence`; timeline play clip ↔ `play`.
   - Khi sequence playing, timeline transport phản ánh local time; không có hai clock chạy.
   - Audio/video reference chỉ chạy sequence.
3. **Dock**
   - Tabs Scene/Props/Rig; tab Rig chỉ bật khi có rig object hoặc luôn hiện với empty state. Chọn luôn hiện để khám phá.
   - Rig tab thay thế inspector khi rig selected? Không; tab là panel riêng, inspector vẫn cho object transform.
4. **Viewport**
   - Rig overlay sibling; bật khi rig tab active; tắt khi render mode.
   - Video reference overlay dưới HUD; tắt trong render mode (trừ khi user bật "include reference"? Không; render không ghi reference).
5. **Smoke/layout/capture**
   - Smoke: panel build, actions, empty states, no fake labels, 44 dp.
   - Layout: thêm clip lane/media lanes/rig tab vào matrix; 9 sizes × 3 modes; no overflow.
   - Capture: actions `clips`, `layers`, `audio`, `video`, `rig`, `pose`, `media-export`, `gif`, `camera`.
6. **CI**
   - Test job + build job; artifact APK.

---

## 11. Chiến lược kiểm thử

### 11.1 Tầng test

| Tầng | File | Chạy |
|---|---|---|
| Parse | `--headless --quit-after 4` | Local + CI |
| Contract | `tests/smoke.gd` (contract block) | Local + CI |
| Animation | `tests/animation.gd` | Local + CI |
| Media | `tests/media.gd` | Local + CI |
| Rig | `tests/rig.gd` | Local + CI |
| Shell smoke | `tests/smoke.gd` | Local + CI |
| Layout | `tests/layout.gd` | Headless + xvfb, local + CI |
| Visual | `tests/capture.gd` | xvfb, local + CI artifact |
| Android build | GitHub Actions | CI |
| Device | checklist | Bạn |

### 11.2 TDD

- Mỗi module mới: viết test đỏ trước, chạy thấy fail đúng lý do, rồi implement tối thiểu.
- Test phải assert hành vi thật, không mock mixer/IK.
- Không thêm test sau khi code xong để "chứng minh"; nếu lỡ viết code trước, xoá và làm lại.
- Mỗi WS ghi RED evidence trong report (command + output tóm tắt).
- Regression assertion được phép pass ngay; ghi rõ là regression, không phải TDD mới.

### 11.3 CI

Thêm job `test` trước `build`:

- Tải Godot 4.7.2-stable Linux x86_64 chính thức; verify version.
- Chạy parse, smoke, animation, media, rig, layout headless, layout xvfb.
- Upload log + ảnh capture.
- Job `build` chạy sau test; stage Java; Gradle `assembleStandardDebug`; upload APK.
- Nếu test fail, không build APK.

### 11.4 Tiêu chí pass

- Parse: 0 error.
- Smoke: `SMOKE RESULT: PASS`, số OK tăng, 0 FAIL.
- Animation/Media/Rig: `... RESULT: PASS`, 0 FAIL.
- Layout headless + xvfb: `LAYOUT RESULT: PASS`, 0 skip ngoài các skip headless-desktop đã định.
- Capture: không clipping/overlap; review ảnh.
- CI: APK artifact tồn tại, đúng package, có `lib/arm64-v8a/libgodot_android.so`, có Java class trong dex (kiểm tra tối thiểu).
- Device: checklist mục 12.3.

---

## 12. Rủi ro và giới hạn xác minh

### 12.1 Rủi ro kỹ thuật

| Rủi ro | Ảnh hưởng | Giảm thiểu |
|---|---|---|
| `JavaClassWrapper` không gọi được static method/byte[] như mong đợi | MP4 không chạy | Test trên device sớm; fallback gọi qua `GodotPlugin` nếu cần; facade báo lỗi rõ |
| MediaCodec khác nhau giữa thiết bị | MP4 fail | Capability query; profile/level fallback; error cụ thể; device checklist |
| Audio decode không hỗ trợ codec | MP4 thiếu audio | MediaExtractor capability; báo tên file; không bỏ im lặng |
| Trích video frame chậm/ tốn RAM | UI treo | Java thread; giới hạn fps/width; progress/cancel; 2 GB cap |
| Auto weight 50k vertex chậm | Bind treo | Giới hạn; chạy async với progress; báo lỗi |
| FABRIK không ổn định với chain dài | IK rung | Iterations/tolerance; clamp; test reachable/unreachable; weight blend |
| JSON skin weights quá lớn | Save chậm | Giới hạn 50k vertex; nén base64? Không; dùng mảng số; cảnh báo |
| glTF animation path remap sai | Animation không chạy | Test GLB sinh runtime; log warning; fallback embedded player |
| Merge conflict ngoài dự kiến | Mất code | Ownership table; integrator giữ file chủ; merge từng nhánh + test |
| 44 dp vs redesign density | UI dày hơn mock | Quyết định đã chốt; ghi trong design; layout test 44 dp |
| SAF content URI | Audio/video import fail | Copy ngay khi chọn; báo lỗi; không giả success |
| Renderer restart | Không đổi được backend | Giữ flow cũ; device test |

### 12.2 Giới hạn môi trường

- Không có thiết bị Android; không thể chạy MediaCodec/audio/skinning GPU.
- Không có Java runtime trong test GDScript; chỉ compile qua CI.
- Không có ffmpeg/PIL/ImageMagick; verify GIF/MP4 bằng cấu trúc + Java probe.
- Không có video decoder trên Linux headless; test video proxy bằng frame giả.
- Không có cảm giác chạm; user test.

### 12.3 Device checklist (sau khi có APK)

- [ ] Cài APK, mở app, safe area đúng ở portrait/landscape.
- [ ] Tạo project, thêm 2 clip, transition 0.5 s, layer weight 0.5; phát sequence mượt.
- [ ] Import GLB có animation; clip xuất hiện và tự phát.
- [ ] Import WAV; phát sequence; volume/trim/fade đúng; không lệch tiếng.
- [ ] Import MP4 reference; trích frame; scrub; overlay opacity/fit; xoá sạch.
- [ ] Export GIF; mở bằng gallery; đúng loop/fps.
- [ ] Export MP4 720p/1080p có audio; mở bằng player; đúng duration/track.
- [ ] Export camera track JSON; kiểm tra frame count/transform.
- [ ] Tạo rig, thêm 3 bone, bind mesh, auto weight; pose; key; phát lại thấy deform.
- [ ] Tạo IK chain; kéo target; end effector bám; bake; phát lại.
- [ ] Save/apply/key pose; mở lại project còn pose.
- [ ] Chạm bone/joint 44 dp; không chọn nhầm; orbit vẫn hoạt động ngoài rig mode.
- [ ] Xoay màn hình khi đang mở rig/clip/media; không mất state, không tràn.
- [ ] Render mode ẩn chrome đúng; video reference không lọt vào render.
- [ ] Không crash khi huỷ MP4/GIF/video extraction giữa chừng.
- [ ] FPS/frame time thật khi phát sequence có skinning/IK; ghi số đo.

---

## 13. Tiêu chí chấp nhận

### 13.1 Animation

- Tạo 2 clip; clip B duplicate từ A; sửa key B không đổi A.
- Strip A 0–2.0 s, strip B 1.5–3.5 s, overlap 0.5 s (A.fade_out = B.fade_in = 0.5, fade nằm trong strip); tại 1.75 s pose là crossfade 50/50; tại 2.25 s chỉ còn B; sequence duration = 3.5 s.
- Layer overlay weight 0.5; additive; mute/solo đúng.
- Sequence duration = 4 s; play sequence cập nhật timeline local time đúng.
- Import GLB animation; clip tạo; tự phát; track path đúng.
- Save/load v2 giữ clip/layer/strip/key; v1 mở được.

### 13.2 Media

- Audio WAV/OGG/MP3 import; track; play sequence; seek; volume/trim/fade; WAV mixdown.
- Video reference MP4 → frame proxy; scrub; overlay; delete.
- GIF 3 frame mở được; đúng kích thước/loop.
- MP4 720p/1080p có audio trên device; probe đúng; cancel sạch.
- Camera JSON đúng frame count/transform; render từ scene camera đúng.
- Không có nút MP4 trên non-Android mà không có lý do.

### 13.3 Rigging

- Rig + 3 bone; parent/rest; save/load.
- Bind mesh 1k vertex; weight sum 1; deform khi pose.
- IK reachable/unreachable; weight; bake.
- Pose save/apply/key; bone key sample; delete.
- Imported skeleton adopt; pose được; không sửa rest.
- UI 44 dp; empty states; không fake.

### 13.4 Redesign

- Token đúng bảng; viewport header; top/bottom bar; dock; timeline; home.
- 44 dp mọi control tương tác; layout matrix pass 9×3.
- Ảnh capture 412×915, 915×412, 1440×900 không clipping/overlap.
- Không còn hero/card marketing; IBM Plex; icon cùng grid.
- Settings/workspace/perf/render mode vẫn hoạt động.

### 13.5 Bằng chứng

- Parse sạch; tất cả suite PASS; layout PASS; capture reviewed.
- CI APK artifact; package đúng; arm64.
- Report ghi rõ phần đã test và phần chờ device.
- Không tuyên bố "MP4 chạy" khi chưa có device test.

---

## 14. File map dự kiến

```
studio/src/core/
  document.gd                 # contract + tích hợp (integrator)
  animation_system.gd         # WS-A
  clip_mixer.gd               # WS-A
  media_system.gd             # WS-B
  audio_library.gd            # WS-B
  video_reference.gd          # WS-B
  gif_encoder.gd              # WS-B
  sequence_renderer.gd        # WS-B
  camera_export.gd            # WS-B
  android_video.gd            # WS-B
  rig_system.gd               # WS-C
  skinning.gd                 # WS-C
  ik_solver.gd                # WS-C
  pose_library.gd             # WS-C

studio/src/ui/
  clip_lane.gd                # WS-A
  clip_sheet.gd               # WS-A
  layer_sheet.gd              # WS-A
  strip_sheet.gd              # WS-A
  media_lanes.gd              # WS-B
  audio_sheet.gd              # WS-B
  video_reference_panel.gd    # WS-B
  media_export_sheet.gd       # WS-B
  media_import_sheet.gd       # WS-B
  rig_panel.gd                # WS-C
  bone_tree.gd                # WS-C
  pose_panel.gd               # WS-C
  ik_panel.gd                 # WS-C
  rig_overlay.gd              # WS-C
  components/viewport_header.gd # WS-D
  tokens.gd, kit.gd           # WS-D

studio/android/app/java/studio/kinema/media/
  KinemaVideoEncoder.java     # WS-B
  KinemaVideoFrames.java      # WS-B

studio/tests/
  animation.gd/.tscn          # WS-A
  media.gd/.tscn              # WS-B
  rig.gd/.tscn                # WS-C
  smoke.gd, layout.gd, capture.gd # integrator/WS-D
```

---

## 15. Những quyết định tôi đã tự chốt (bạn check khi đọc)

1. **44 dp thắng mật độ redesign.** Mọi control tương tác giữ 44 dp; chỉ chrome không tương tác dày theo redesign. Nếu bạn muốn Desktop 32 dp thật, layout test và ràng buộc touch phải đổi.
2. **Clip-local editing + sequence playback.** Dope/graph sửa clip đang chọn; clip lane phát sequence. Đây là cách ít phá timeline hiện tại nhất.
3. **Audio chỉ chạy ở sequence.** Video reference có thể preview theo `strip.start + current_time` khi đang sửa clip và clip có strip trên layer active; đây là preview, không phát audio, và UI ghi rõ "Preview from active strip". Khi export, cả hai bám sequence time.
4. **MP4 bằng Java MediaCodec trong app module**, không GDExtension, không ffmpeg.
5. **Video reference bằng frame proxy** cho MP4; `.ogv` dùng VideoStreamPlayer. Không real-time MP4 overlay.
6. **Rigging auto weight theo khoảng cách**, không weight painting; có thể chỉnh influence scale từng bone.
7. **Bone keys chỉ hiện trong rig tab**, không nhét vào dope sheet timeline trong pass này.
8. **Camera animation chỉ transform**, FOV tĩnh.
9. **glTF animation được copy thành clip Kinema** và tự phát; `AnimationPlayer` gốc trong imported scene bị `active = false` để không chạy hai lần. Track không hỗ trợ được báo trong import summary, không giả là đã chạy.
10. **Contract commit là bắt buộc**; không agent nào sửa `document.gd`/`editor.gd` sau contract ngoài integrator.

---

## 16. Ba quyết định phạm vi đã chốt để bắt đầu

Bạn đã yêu cầu bắt đầu. Ba mặc định dưới đây là contract của pass này; nếu muốn đổi, phải nói **trước khi merge** vì chúng đổi schema/UI đáng kể.

- **Q1 — Skinning:** **auto weight theo khoảng cách + `influence_scale` từng xương + rebind**. Không có cọ weight painting trong pass này. Lý do: giữ pass trong ngân sách; weight painting cần brush UI, undo riêng và thêm nhiều ngày kiểm thử.
- **Q2 — Video reference:** **frame proxy** (trích frame từ MP4 khi import, scrub như chuỗi ảnh; không phát real-time trong viewport). `.ogv` dùng `VideoStreamPlayer`. Lý do: không có decoder native/texture bridge, và môi trường này không có thiết bị để xác minh real-time.
- **Q3 — Camera export:** **(a) render MP4/GIF/PNG từ scene camera đã animate + (b) JSON transform/FOV theo frame**. Không xuất Blender/AE/FBX chuyên dụng. Lý do: JSON là định dạng trung lập, kiểm chứng được bằng test; exporter chuyên dụng cần tool bên ngoài để xác minh.

Ba mặc định này đã được phản ánh trong §7, §8, §13 và §17.

---

## 17. Chốt các câu hỏi builder-check

Mục này là **decision register**. Nếu mục nào xung đột với phần trước, mục này thắng.

### 17.1 Vòng đời subsystem và thứ tự nạp

- Ba subsystem là `RefCounted`, tạo trong `Document._init()`; không phải node con, không bị `_clear_runtime()` huỷ.
- Thứ tự: `_clear_runtime()` → `_ensure_player()` → `reset()` → `_apply_data()` → `animation_system.load_data()` → `rig_system.load_data()` → `media_system.load_data()` → gán `animation` → `seek()`.
- `Document.process_priority = 100`; `AnimationPlayer` con cập nhật trước, rồi `animation_system.advance()`, `rig_system.advance()`, `media_system.advance()`.
- Undo/redo dùng cùng thứ tự trên snapshot; hook `on_object_spawned` chỉ dựng runtime, không nạp dữ liệu lần hai.

### 17.2 Bind mesh không reparent

- Mesh và rig vẫn là hai object anh em dưới `Document`; outliner phẳng không đổi.
- Khi bind: đưa vertex về rig-local bằng `rig_node.global_transform.affine_inverse() * mesh_node.global_transform`, gán `Skin` + `skeleton` path, rồi **khoá transform của mesh theo rig** (mesh node transform = rig transform). Inspector hiện "Bound to Rig" và disable các field transform của mesh.
- Di chuyển rig → mesh đi theo. Di chuyển mesh độc lập bị chặn khi đang bind.
- Xoá rig: unbind mọi mesh (khôi phục source + transform đã lưu), rồi xoá rig. Xoá mesh: xoá skin record, giữ rig.

### 17.3 Skin storage, undo và job

- Weight không nằm trong JSON undo snapshot. Mỗi skin ghi một **sidecar nhị phân** `<project>/skins/<rig_id>_<mesh_id>_<hash>.bin` với header version/count/influences và mảng `uint16` bones + `float32` weights.
- JSON chỉ giữ metadata: `file`, `hash`, `vertex_count`, `influences`, `bone_names`, `source`, `bind_transform`.
- Bind/auto-weight là **job có progress thật**: `start_bind()` → `poll_bind()` → `cancel_bind()`. Chạy theo chunk trên main thread (500 vertex/frame), progress = processed/total; không có progress giả. Giới hạn cứng 50.000 vertex.
- Undo bind/unbind khôi phục metadata; sidecar cũ không bị xoá ngay. `project_store` GC sidecar không còn được tham chiếu khi save.
- `influence_scale` lưu trong bone record, sửa trong bone inspector; đổi giá trị yêu cầu **Rebind** để áp dụng, UI nói rõ.

### 17.4 Fade và crossfade

- `fade_in`/`fade_out` nằm trong strip, không mở rộng strip; envelope smoothstep; `fade_in + fade_out ≤ duration` (clamp kèm warning).
- Crossfade 0.5 s = overlap 0.5 s: A 0–2.0, B 1.5–3.5; tại 1.75 weight 50/50; tại 2.25 chỉ B; sequence duration 3.5 s.
- `ease` là time-warp local time, không phải fade curve.

### 17.5 Base pose

- Object base = transform tĩnh trong `objects` (giá trị inspector khi không có animation), không phải pose tạm.
- Bone base = rest pose trong rig (`Skeleton3D.get_bone_rest`), không phải bind pose.
- Không contribution → base; weight < 1 → blend từ base. `base_poses` dựng lại mỗi lần evaluate, không serialize.

### 17.6 Kích thước export

- Video/PNG sequence dùng **kích thước chính xác**: 1280×720, 1920×1080, 2560×1440. Probe được đặt đúng size; camera đặt `keep_aspect` theo chiều cao để framing ổn định. Không crop/letterbox ảnh viewport.
- Still ảnh đơn vẫn dùng "long edge" + aspect viewport như hiện tại.
- GIF dùng aspect 16:9 của preset video, width 320/480/640/720, height làm tròn chẵn.
- `capture_with_camera(size: Vector2i, ...)`; camera JSON ghi đúng size/FOV đã dùng.

### 17.7 IK hook

- `Document._process` gọi `rig_system.advance(delta)` sau animation; chạy ở scrub, clip playback, sequence playback và export.
- `sequence_renderer` gọi `solve_ik()` ngay trước capture để không phụ thuộc frame order.
- Fast path vẫn chạy IK; test riêng cho fast path.

### 17.8 Imported player và signal

- `imported_scene_ready` chỉ phát trên import; load/undo dùng `load_data`, không quét lại.
- Copy xong thì `active = false` cho mọi `AnimationPlayer` imported. Không chạy hai lần.
- Track không remap được bị bỏ và liệt kê trong import summary.

### 17.9 Video reference time và schema

- Sequence time là nguồn sự thật khi play/export.
- Clip mode chỉ preview: `strip.start + current_time` nếu clip có strip trên layer active; nếu không, frame 0. Không phát audio.
- Schema `media.video_refs[]`: `id`, `name`, `dir`, `fps`, `duration`, `width`, `height`, `start`, `opacity`, `fit`, `offset`, `scale`, `flip_h`, `visible`. Default: start 0, opacity 0.5, fit contain, offset 0, scale 1, flip false, visible true.
- Xoá reference là thao tác không undo được (file bị xoá); phải confirm.

### 17.10 Cascade khi xoá/đổi tên

| Thao tác | Hành vi |
|---|---|
| Xoá object | Xoá track `<node>:` khỏi mọi clip; nếu là rig thì unbind mesh, xoá bone track, pose, IK; nếu là mesh bound thì xoá skin record. |
| Đổi tên object | Remap track path `<old>:` → `<new>:` và `<old>/Skeleton3D:` → `<new>/Skeleton3D:`. |
| Đổi tên bone | Cập nhật rig, skin `bone_names`, IK root/end, pose keys, bone track path; rebuild skeleton. |
| Reparent bone | Chặn cycle; giữ global rest pose; rebuild skeleton; skin dùng tên bone. |
| Xoá bone | Chặn nếu còn con, skin, IK hoặc pose tham chiếu; UI liệt kê tham chiếu. |
| Xoá rig | Unbind mesh, xoá track/pose/IK của rig. |
| Xoá clip | Chặn nếu còn strip tham chiếu; duplicate deep-copy Animation. |
| Xoá layer | Chặn nếu là layer cuối; xoá strip kèm confirm. |
| Xoá IK target | Chain mất target → disable + warning; không xoá chain. |

- Skin tham chiếu bone bằng **tên**, không bằng index trong JSON; sidecar lưu index tại thời điểm bind + `bone_names` để remap khi load. Thiếu tên → load báo lỗi rõ và giữ mesh tĩnh, không silently deform sai.

### 17.11 GIF timing

- Delay từng frame theo accumulator: `delay_i = round((i+1)*100/fps) - round(i*100/fps)`, tối thiểu 1 cs.
- GIF fps chỉ 12/24/30; 60 fps bị disable với lý do "GIF timing is centisecond-based; 60 fps cannot be represented". Không giả 60 fps.
- Test parse delay và assert average trong 0.5% của nominal.

### 17.12 Test contract cho các quyết định này

- Contract test: v1 load, v2 roundtrip, subsystem spy, undo không mất system.
- Animation: fade 50/50 tại 1.75, base pose gap, imported player inactive, signal chỉ một lần.
- Media: exact dimensions, GIF delay average, video schema/defaults, clip preview mapping.
- Rig: bind không reparent, sidecar roundtrip, job progress/cancel, IK fast path, cascade delete/rename.
