# Kinema Studio — Thiết kế bản dựng lại chuyên nghiệp

- **Ngày:** 2026-10-23
- **Cập nhật:** 2026-10-24 — áp dụng 3 quyết định cuối: Desktop thu nhỏ đều, Mobile mặc định, Android 15–17
- **Trạng thái:** Chờ duyệt lần cuối — chưa có code sản phẩm nào được viết cho bản dựng lại này
- **Nền tảng:** Android, Godot 4.7.2-stable (bản Android fork), GDScript
- **Thiết bị đích:** Android 15–17; 60 fps là mục tiêu, không phải cổng bắt buộc trên máy test
- **Hướng đã chọn:** **C — Hybrid workbench**, phong cách tối giản, chuyên nghiệp, vuông vức
- **Phạm vi:** toàn bộ lớp UI, responsive/scale/orientation, hiệu năng preview, hành vi keyframe, bề mặt renderer/graphics/performance/settings, render/export và import
- **Ngoài phạm vi:** multi-select, MP4, FBX nhị phân, light theme, localization, cloud sync, plugin system

---

## 0. Tóm tắt một trang

Kinema Studio hiện có một pipeline thật: document JSON, undo/redo, autosave, import glTF/OBJ+MTL, render still và PNG sequence, speed graph, Forward+/Mobile và một bộ graphics settings. Vấn đề không nằm ở engine. Vấn đề nằm ở **lớp trình bày được thiết kế như một trang web thu nhỏ**: Home dùng hero/card, editor giả định khung 1280×800, panel/drawer từng có lỗi đóng khi chạm vào bên trong (overlay hiện đã chặn, nhưng phải giữ bằng test hồi quy), nhiều hàng ngang không co giãn nên tràn ở portrait, và viewport render lại mọi frame dù cảnh đứng yên.

Bản dựng lại giữ nguyên engine, Android host, document model và các pipeline đang chạy đúng. Nó thay **toàn bộ lớp UI** bằng một shell duy nhất có ba chế độ:

| Chế độ | Dùng cho | Cấu trúc |
|---|---|---|
| **Compact** | điện thoại dọc (< 600 dp) | một cột; viewport; transport; timeline gập; panel dạng bottom sheet |
| **Studio** | điện thoại ngang, tablet dọc (600–959 dp) | rail trái + viewport + panel rail phải; dock là flyout overlay; timeline gập mặc định |
| **Desktop** | tablet ngang, DeX, màn hình lớn; **trên điện thoại vẫn chọn được** | menu bar + rail + viewport + panel rail + flyout + status bar; timeline gập mặc định; nếu không vừa, thu nhỏ đều toàn bộ UI |

Cùng một ngôn ngữ hình ảnh cho cả ba: nền graphite đơn sắc, hairline 1 px, góc 0 px, IBM Plex Sans + IBM Plex Mono. Trạng thái được phân biệt bằng **độ sáng**, không bằng hue: trắng gần tuyệt đối cho thao tác UI, xám cho thời gian (key, playhead, transport, selection 3D), và đỏ là tín hiệu màu duy nhất dành cho destructive/error. Mật độ đến từ chữ 11–13 sp, khoảng cách 4/8/12 px và đường kẻ 1 px — không đến từ việc thu nhỏ vùng chạm.

Ba lỗi gốc được sửa trước khi làm giao diện:

1. **Key tại playhead:** sửa transform tại thời điểm đang có key sẽ cập nhật chính key đó, kể cả khi autokey tắt. Autokey chỉ quyết định việc **tạo key mới**.
2. **Lag trong scene:** preview chỉ render khi có thay đổi; khi orbit/kéo gizmo/playback mới render liên tục; UI gộp refresh mỗi frame; chất lượng tự hạ khi frame time vượt ngưỡng.
3. **Tràn portrait:** layout được thiết kế lại theo dp với breakpoint 600/960, mọi sheet có scroll, mọi hàng ngang co giãn hoặc đưa vào menu tràn, và có test ma trận kích thước. Desktop trên màn hình hẹp không fallback: toàn bộ UI được thu nhỏ đều cho đến khi vừa, kèm chỉ báo tỉ lệ thu nhỏ.

Bề mặt mới có thật, không phải label giả:

- **Renderer:** **Mobile mặc định trên Android**; Forward+ / Mobile / Compatibility chọn được, chuyển bằng restart có kiểm chứng; hiển thị backend thực tế; tính năng không được hỗ trợ bị disable kèm lý do.
- **Graphics / Performance / Editor / Display:** các control map trực tiếp vào API Godot, lưu bền, có reset từng nhóm.
- **FPS / frame time / draw calls / preview resolution:** hiển thị thật, lấy từ `Performance` và `RenderingServer`.
- **Render:** PNG still và PNG sequence đóng ZIP thật; **MP4 không được hỗ trợ** và UI nói rõ.
- **Import:** glTF/GLB, OBJ+MTL; **FBX nhị phân không được hỗ trợ** và UI nói rõ.

Không có trong bản này: multi-select, reparenting, IK/constraints, physics, particle, audio, video export, light theme, localization. Đây là các non-goal có chủ đích, không phải phần bị bỏ quên.

---

## 1. Hiện trạng và bằng chứng

### 1.1 Những gì đang chạy đúng và sẽ được giữ

- `src/core/document.gd`: scene graph, object record, animation track, key insert/retime/delete, easing transition, study lighting, undo/redo, serialize/deserialize.
- `src/core/project_store.gd`: project folder `user://projects/<id>/`, danh sách recent, save/load, xoá/đổi tên.
- `src/core/obj_importer.gd`: parse OBJ/MTL tại runtime, copy texture, validate face index.
- `src/core/render_export.gd`: đóng ZIP sequence.
- `src/ui/timeline.gd`: dope sheet, transport, speed graph sample từ engine, ease handle.
- `src/core/gfx.gd`: preset, environment/viewport application, capability check.
- `src/ui/overlay.gd`: modal/toast, backdrop chỉ đóng khi chạm ra ngoài.
- `src/viewport/editor_view.gd`: SubViewport, camera, gizmo, picking, HUD, still capture.
- `tests/smoke.gd`: bộ regression headless đang là nguồn sự thật cho logic.

Bản dựng lại **không viết lại** các phần này trừ khi cần tách signal hoặc thêm API phục vụ UI mới.

### 1.2 Năm vấn đề gốc

#### Vấn đề 1 — Key tại B không cập nhật

**Tái hiện đã xác nhận:** hai key position tại 0 s và 2 s. Đặt playhead tại 2 s, gọi `set_object_transform()` với `autokey = false`. Node hiển thị giá trị mới, nhưng key tại 2 s vẫn giữ giá trị cũ. Seek hoặc playback sẽ kéo node về giá trị cũ.

**Nguyên nhân trong code:** `document.gd:887–903` chỉ gọi `_key_selected_transform()` khi `key and autokey and not _loading`. Trong khi đó playback và seek lấy giá trị từ key qua `sample_channel()`. Vì vậy thay đổi ở playhead chỉ là thay đổi tạm trên node, không đi vào key.

**Tác động:** đây là lỗi chức năng nghiêm trọng nhất. Người dùng sửa đúng vị trí đang xem, bấm play, và thấy công việc biến mất.

#### Vấn đề 2 — Lag trong scene

**Đo đạc đã thực hiện** (software Vulkan/lavapipe, chỉ dùng để so sánh tương đối, không phải số liệu thiết bị):

| Cấu hình | FPS | Process time |
|---|---:|---:|
| Baseline, SubViewport 963×1767, MSAA 2× | 1 | 1319 ms |
| Preview low-res | 2 | 849 ms |
| `UPDATE_ONCE` | 7 | 143 ms |
| Performance preset | 8 | 102 ms |

**Nguyên nhân chính, theo thứ tự bằng chứng:**

1. `editor_view.gd:65` đặt `render_target_update_mode = UPDATE_ALWAYS`. Cảnh đứng yên vẫn render 3D mỗi frame.
2. `_process()` trong `editor_view.gd` gọi `queue_redraw()` mỗi frame và cập nhật marker scale mỗi frame.
3. `document.object_changed` được phát cho từng bước kéo gizmo; outliner/inspector/timeline có thể rebuild toàn bộ theo signal này.
4. MSAA 2×, shadow atlas lớn và các hiệu ứng environment chạy trên GPU yếu.
5. Không có frame pacing, không có adaptive quality, không có thống kê FPS cho người dùng.

**Kết luận:** Forward+ không phải nguyên nhân duy nhất. Ngay cả khi đổi renderer, preview vẫn lag nếu vẫn `UPDATE_ALWAYS` và rebuild UI mỗi frame. Phải sửa toàn stack: update policy, UI refresh, chất lượng render, rồi mới đến renderer.

#### Vấn đề 3 — Tràn portrait

**Bằng chứng:** trên cửa sổ 1080×2400, UI logic khoảng 411×914 dp. Layout cũ được thiết kế quanh 1280×800, breakpoint duy nhất là `WIDE_MIN_WIDTH = 720` và `SHORT_MAX_HEIGHT = 520`. Top bar có 6 nút icon cố định; dock rộng tới 90% màn hình; timeline cao 154 dp; sheet không đặt max-height nhất quán nên panel dài có thể vượt màn hình; nhiều hàng ngang dùng `custom_minimum_size` cộng dồn vượt chiều rộng.

**Tác động:** control bị cắt, chữ bị đè, bottom bar biến mất ở landscape thấp, sheet không cuộn tới action.

**Kết luận:** không thể sửa bằng cách thu nhỏ font. Phải thiết kế lại theo dp, cho phép hàng co giãn, đưa hành động phụ vào overflow, và test ở nhiều kích thước.

#### Vấn đề 4 — Ngôn ngữ hình ảnh chưa đạt chất lượng công cụ chuyên nghiệp

Home hiện dùng hero lớn, card template, illustration trang trí. Editor dùng bo góc 4 px, chữ 9 sp ở nhiều chỗ, nút pill, mật độ không đồng nhất. Nó giống một landing page thu nhỏ hơn là một workbench. Các icon yếu (play/pause, key, graph, render, transform) không cùng một grid/stroke.

#### Vấn đề 5 — Thiếu bề mặt renderer và hiệu năng

Đã có graphics sheet với preset và nhiều environment option, nhưng chưa có:

- chọn renderer thật (Forward+/Mobile/Compatibility) và restart flow;
- FPS/frame time/draw call hiển thị cho người dùng;
- preview quality/adaptive quality/update policy;
- settings editor/display/orientation/layout;
- màn hình performance riêng.

---

## 2. Mục tiêu, không mục tiêu, anti-goal

### 2.1 Mục tiêu

| Mã | Mục tiêu | Cách đo |
|---|---|---|
| G1 | Dựng lại toàn bộ UI, không chỉ polish | Không còn hero/card ở Home; editor dùng shell mới; mọi màn hình đi qua token/component mới |
| G2 | Ba chế độ Compact/Studio/Desktop dùng chung một shell | Chuyển mode trong app; mode được lưu; layout đúng ở 360×640 → 1600×900; Desktop trên điện thoại thu nhỏ đều, không fallback |
| G3 | Không tràn/cắt UI ở portrait, landscape, tablet, desktop | Test ma trận assert mọi control visible nằm trong màn hình; screenshot xác nhận |
| G4 | Hết lag trong scene | Preview idle dùng `UPDATE_ONCE`; UI gộp refresh; có FPS/frame graph; đo lại trước/sau |
| G5 | Sửa key tại playhead | Regression test đỏ → xanh; playback tại B giữ giá trị mới |
| G6 | Renderer thật, không giả | Restart bằng `OS.set_restart_on_exit`; hiển thị backend thực; test args/persistence; device checklist |
| G7 | Settings sâu, có thật | Mọi control map vào API; lưu `user://`; reset từng nhóm; option không hỗ trợ bị disable kèm lý do |
| G8 | Render/export và import thật | PNG still + ZIP sequence mở được; glTF/GLB/OBJ+MTL import được; FBX/MP4 nói rõ không hỗ trợ |
| G9 | Ngôn ngữ hình ảnh chuyên nghiệp, vuông vức | Token 1 px/0 px; IBM Plex Sans + IBM Plex Mono; icon redraw; review screenshot |
| G10 | Bằng chứng trước khi tuyên bố hoàn thành | Smoke pass, parse sạch, screenshot, CI artifact; không claim khi chưa chạy |

### 2.2 Không mục tiêu

- Multi-select, group, reparenting, layer system.
- IK, constraints, physics, particle, audio, video timeline.
- MP4/WebM export.
- FBX nhị phân (và ASCII FBX trong bản này).
- Light theme, theme editor, localization.
- Cloud sync, collaboration, plugin system.
- Thay Godot host bằng native Android UI.
- Thay đổi schema project JSON theo cách phá vỡ project cũ.
- Per-object emission, per-light shadow toggle/size, chỉnh primitive size/segments trong Inspector — bản này chỉ hiển thị thuộc tính document đã có. Đây là authoring feature mới, không phải UI rebuild.
- Render từ scene camera; bản này render từ editor camera (đúng “render current scene/preview”). Scene camera là feature riêng.
- Multi-object import: mỗi file import tạo một document object, đúng với `add_imported()` hiện tại.
- Save As / project switching trong editor; New/Open/Close quay về Home.
- Bezier/S-curve easing thật; transition hiện tại là một scalar, và UI phải nói đúng như vậy.

### 2.3 Anti-goal (làm ra là thất bại, dù có chạy)

- Home kiểu landing page: hero, card lớn, illustration trang trí, tagline marketing.
- Bo tròn mọi thứ thành pill; gradient/glass/shadow trang trí.
- Icon emoji hoặc icon không cùng grid/stroke.
- Nút renderer chỉ đổi label nhưng không đổi backend.
- Nút MP4 giả, progress giả, file rỗng.
- Import FBX bằng cách đổi đuôi file hoặc báo thành công giả.
- Thu nhỏ font xuống 8–9 sp để nhét vừa; `clip_contents` che control bị tràn.
- Panel tự đóng khi chạm vào bên trong.
- Animation trang trí làm tụt frame.
- Thêm setting không map vào API nào.

---

## 3. Ràng buộc

### 3.1 Kỹ thuật

- Godot **4.7.2-stable**, bản Android fork; GDScript; project chạy từ raw assets, không cần editor import pass.
- Android host hiện tại; package `studio.kinema.app`; build **chỉ** qua GitHub Actions `assembleStandardDebug`, ABI `arm64-v8a`, debug keystore của CI.
- Thiết bị đích để xác minh: **Android 15–17**. 60 fps là mục tiêu hiệu năng, **không phải cổng chấp nhận** trên máy test; kết quả FPS thật phải được báo cáo, không suy đoán.
- Không có thiết bị Android trong môi trường này. Mọi kết luận về cảm giác chạm, orientation, renderer restart và FPS thật đều cần device verification.
- Android SAF trả content URI; file `.mtl`/texture cùng thư mục có thể không truy cập được. Không được giả vờ đã đọc.
- `RenderingServer` không có API đổi renderer tại runtime. Cách khả dụng: command-line `--rendering-method`/`--rendering-driver` + restart.
- `OS.set_restart_on_exit(true, args)` đã được xác nhận trong source Godot 4.7.2: đi qua `Main::cleanup` → `OS_Android::create_instance` → `onNewGodotInstanceRequested`. Chưa xác minh trên thiết bị.
- `DisplayServer.screen_set_orientation()` tồn tại; `FEATURE_ORIENTATION` trả false trên headless Linux. Chưa xác minh Android.
- `DisplayServer.screen_get_scale()` và `screen_get_dpi()` tồn tại. **OS font scale chưa được xác nhận**; không được giả định.
- Không có encoder MP4 trong stack; không thêm dependency native trong bản này.
- Không có parser FBX nhị phân; muốn có phải viết parser/GDExtension hoặc chuyển đổi ngoài app.
- Godot Android accessibility/screen-reader support còn hạn chế; sẽ làm phần tối thiểu (label, focus, contrast, touch target) và ghi rõ giới hạn.

### 3.2 Thiết kế

- Touch-first: vùng chạm tối thiểu **44 dp**, primary transport **48 dp**.
- Safe area: tai thỏ, status bar, gesture bar phải được trừ qua `DisplayServer.get_display_safe_area()`.
- Một tay dùng được trên điện thoại: hành động chính nằm trong nửa dưới màn hình hoặc bottom sheet.
- Không dùng màu làm tín hiệu duy nhất; luôn kèm icon/chữ.
- Text đọc được tối thiểu 11 sp; 10 sp chỉ cho label uppercase phụ, không cho nội dung cần đọc.
- Góc vuông 0 px; hairline 1 px; không gradient/glass/shadow trang trí.
- Chỉ dark theme trong bản này.

### 3.3 Hiệu năng

- Mục tiêu: 60 fps trên thiết bị tầm trung ở preset Balanced; sàn mềm 30 fps để phát hiện regression; UI frame < 8 ms. 60 fps **không phải cổng bắt buộc** trên thiết bị test; nếu không đạt, ghi nhận số đo thật và hành vi adaptive quality, không tuyên bố đạt.
- Preview idle không được render 3D liên tục.
- Không cấp phát/str allocation trong `_process` mỗi frame.
- Không rebuild outliner/inspector/timeline khi chỉ kéo transform.
- Adaptive quality phải có trần/sàn và hiển thị trạng thái cho người dùng.

---

## 4. Phương án và quyết định

### 4.1 Phương án A — Polish UI hiện tại

Giữ cấu trúc hiện tại, sửa spacing/màu/font, thêm overflow menu, sửa vài chỗ tràn.

**Ưu:** rủi ro thấp, nhanh.
**Nhược:** không giải quyết Home kiểu landing page; không có ba mode thật; dock/drawer vẫn là mô hình cũ; khó đạt mật độ và cảm giác công cụ chuyên nghiệp; các vấn đề portrait chỉ được vá.
**Kết luận:** loại. Yêu cầu là dựng lại, không phải polish.

### 4.2 Phương án B — UI immediate-mode tự vẽ hoàn toàn

Vẽ toàn bộ shell, panel, input, scroll, focus bằng `_draw()` và xử lý input thủ công.

**Ưu:** kiểm soát tuyệt đối pixel, mật độ, animation.
**Nhược:** phải tự làm text input/IME, scroll, focus, accessibility, clipboard, keyboard, sheet gesture; rủi ro cao; khó test; dễ tái tạo lỗi cũ; thời gian lớn.
**Kết luận:** loại. Không tương xứng với lợi ích.

### 4.3 Phương án C — Hybrid workbench (đã chọn)

Dùng Godot `Control` cho cấu trúc, input, scroll, focus, sheet; dùng `_draw()` cho những nơi cần mật độ cao: viewport overlay, timeline/dope sheet, speed graph, frame graph. Một shell duy nhất, ba mode, một bộ token/component.

**Ưu:**

- Tận dụng những gì engine làm tốt, giữ pipeline đang chạy.
- Cho phép mật độ và ngôn ngữ hình ảnh riêng ở những bề mặt quan trọng.
- Testable: layout assert được, logic tách khỏi vẽ.
- Incremental: sửa keyframe/perf trước, rồi thay UI từng lớp.
- Phù hợp CI hiện tại, không thêm dependency.

**Nhược:**

- Phải kỷ luật với layout Godot: min size, size flags, scroll, clip.
- Cần test ma trận kích thước để tránh tràn.
- Một số control mặc định của Godot phải style lại hoặc thay bằng control tự vẽ.

**Kết luận:** chọn C. Đây là phương án duy nhất vừa giải quyết được cấu trúc, vừa giữ được engine thật, vừa có thể kiểm chứng trong môi trường hiện tại.

### 4.4 Các quyết định đã chốt trong hội thoại

- Hướng C.
- Tối giản, chuyên nghiệp, vuông vức.
- Ba mode Compact/Studio/Desktop, chọn được trong app.
- Trắng FOCUS cho UI; xám TIME cho thời gian; chỉ DANGER giữ sắc đỏ.
- Không fake renderer/MP4/FBX.
- Key tại playhead phải cập nhật key.
- Build qua GitHub Actions, package `studio.kinema.app`, arm64-v8a.
- Desktop trên điện thoại: thu nhỏ đều toàn bộ UI cho đến khi vừa; không fallback Studio.
- Renderer mặc định trên Android: Mobile; Forward+/Mobile/Compatibility chọn được; không có Auto giả.
- Thiết bị xác minh: Android 15–17; 60 fps là mục tiêu, không bắt buộc.

---

## 5. Hệ thống hình ảnh

### 5.1 Nguyên tắc

1. **Đây là công cụ, không phải trang web.** Không hero, không card marketing, không illustration trang trí. Thông tin và điều khiển là nội dung.
2. **Một điểm nhấn mỗi lúc.** Trắng FOCUS đánh dấu lựa chọn/hành động UI. Xám TIME đánh dấu thời gian. Hai nghĩa không tranh nhau.
3. **Đường kẻ thay cho bóng đổ.** Phân cấp bằng surface step + hairline 1 px. Không drop shadow, không blur, không glass.
4. **Vuông vức.** Góc 0 px cho panel, input, button, sheet. Không pill trừ khi đó là toggle trạng thái có lý do (ví dụ chip AUTO), và ngay cả khi đó cũng dùng hình chữ nhật 2 px.
5. **Số phải thẳng hàng.** Mọi số, timecode, giá trị transform dùng IBM Plex Mono, tabular. Không để số nhảy layout khi đổi giá trị.
6. **Mật độ đến từ nhịp, không từ thu nhỏ.** Chữ 11–13 sp, padding 4/8/12, hàng 44 dp; không dùng 8–9 sp.
7. **Không trang trí làm chậm.** Animation chỉ để giải thích thay đổi trạng thái; không animation nền, không particle, không glow UI.
8. **Trạng thái phải nhìn thấy.** Selected, active, disabled, dirty, unkeyed, unsaved, renderer-pending đều có dấu hiệu hình học + chữ, không chỉ màu.

### 5.2 Token màu

Tất cả nằm trong `Kit` (hoặc file token mới `src/ui/tokens.gd` được `Kit` re-export). Không hardcode hex trong screen/component.

| Token | Hex | Dùng cho | Tương phản đo được |
|---|---|---|---|
| `BG` | `#080808` | nền app, khoảng trống viewport | — |
| `SURFACE` | `#101010` | panel, top bar, dock | — |
| `SURFACE_2` | `#151515` | field, segmented track, sheet body | — |
| `SURFACE_3` | `#1B1B1B` | row active, segment selected, button pressed | — |
| `SURFACE_HOVER` | `#232323` | hover/focus nền | — |
| `BORDER` | `#3A3A3A` | hairline chính, divider, field frame | 1 px |
| `BORDER_SOFT` | `#292929` | hairline phụ, tách section | 1 px |
| `TEXT` | `#F0F0F0` | chữ chính | 17.6:1 trên BG, 16.7:1 trên SURFACE |
| `TEXT_MUTED` | `#A6A6A6` | chữ phụ, metadata đọc được | 7.8:1 trên SURFACE, 7.1:1 trên SURFACE_3 |
| `TEXT_DIM` | `#8C8C8C` | chữ cấp ba, hint ngắn; **không** cho disabled-only | 5.7:1 trên SURFACE, 5.1:1 trên SURFACE_3 |
| `FOCUS` | `#E6E6E6` | selection UI, primary action, focus ring | 16.0:1 trên BG |
| `FOCUS_BRIGHT` | `#FFFFFF` | hover/active của FOCUS, icon active | cao nhất |
| `FOCUS_DARK` | `#262626` | nền selected row, toggle on | — |
| `TIME` | `#C8C8C8` | key, playhead, transport, selection 3D | 12.0:1 trên BG |
| `TIME_BRIGHT` | `#F2F2F2` | hover key/playhead | — |
| `TIME_DARK` | `#2A2A2A` | nền key/selection thời gian | — |
| `WARNING` | `#C8C8C8` | unkeyed, pending restart, cảnh báo | dùng hình học + chữ, không dựa vào hue |
| `DANGER` | `#E06C6C` | xoá, lỗi | 5.9:1 trên SURFACE |
| `SUCCESS` | `#B0B0B0` | lưu xong, render xong | trạng thái bằng độ sáng + icon |
| `AXIS_X` | `#A66A66` | trục X, gizmo X | chỉ trong viewport |
| `AXIS_Y` | `#7F9A78` | trục Y, gizmo Y | chỉ trong viewport |
| `AXIS_Z` | `#6D8099` | trục Z, gizmo Z | chỉ trong viewport |
| `SCRIM` | `rgba(0,0,0,0.68)` | nền sau sheet/modal | không blur |
| `GRID` | `rgba(255,255,255,0.07)` | grid viewport | — |
| `GRID_MAJOR` | `rgba(255,255,255,0.14)` | grid 10 đơn vị | — |

**Quy tắc màu:**

- Không có hue trong chrome. Trạng thái UI dùng `FOCUS`/`FOCUS_BRIGHT`; trạng thái thời gian dùng `TIME`/`TIME_BRIGHT`. Hai nghĩa không hoán đổi.
- `DANGER` là tín hiệu màu duy nhất; chỉ cho destructive/error, không cho “đang ghi”.
- `WARNING` và `SUCCESS` là bậc độ sáng, luôn đi kèm icon/chữ: `Unkeyed` + ngoặc, `Restart required` + icon, `Saved` + check.
- `TEXT_DIM` chỉ dùng cho hint ngắn hoặc nhãn cấp ba; hướng dẫn và metadata quan trọng dùng `TEXT_MUTED`.
- Màu trục chỉ tồn tại trong viewport (gizmo, selection, grid axis). Không dùng màu trục cho chrome.
- Không hardcode hex ngoài `src/ui/tokens.gd`; `Kit` re-export mọi token.

### 5.3 Typography

| Vai trò | Token | Font | Size | Weight | Dùng |
|---|---|---|---|---|---|
| Page | `TYPE_PAGE` | IBM Plex Sans | 18 | 600 | tiêu đề Home, empty state lớn |
| Title | `TYPE_TITLE` | IBM Plex Sans | 15 | 600 | tên project, sheet title |
| Emphasis | `TYPE_EMPHASIS` | IBM Plex Sans | 13 | 500 | section heading, field value, button label |
| Body | `TYPE_BODY` | IBM Plex Sans | 12 | 400 | mô tả, nội dung sheet, nhãn điều khiển |
| Caption | `TYPE_CAPTION` | IBM Plex Sans | 11 | 400/500 | metadata, hint, trạng thái; **sàn đọc** |
| Mono | `TYPE_MONO` | IBM Plex Mono | 11 | 400 | FPS, draw call, ID, eyebrow uppercase |
| Mono Large | `TYPE_MONO_LARGE` | IBM Plex Mono | 12 | 400 | transform, duration, timecode |
| Ruler | `TYPE_RULER` | IBM Plex Mono | 10 | 400 | **chỉ** tick số trên ruler timeline |

- `Kit.label()` và `Kit.mono_label()` clamp mọi cỡ về tối thiểu 11 sp; chỉ ruler tự vẽ 10 sp.
- Không dùng quá 3 cỡ chữ trong một panel.
- Số trong field, timecode và mọi giá trị kỹ thuật dùng IBM Plex Mono; nhãn dùng IBM Plex Sans.
- Section eyebrow dùng IBM Plex Mono uppercase 11 sp, không dùng làm nội dung dài.
- Cả hai họ font đều có glyph tiếng Việt; font dự phòng của engine chỉ dùng khi file font không tải được và phải phát warning.
- Không dùng font mặc định của engine cho UI.

### 5.4 Spacing, hình học, hit target

- Base unit: **4 dp**. Dãy: 2, 4, 6, 8, 12, 16, 24, 32.
- Panel padding: 12 dp; sheet padding: 16 dp; section gap: 16 dp; row gap: 4 dp.
- Hàng tương tác: **44 dp logic** tối thiểu; transport/primary: **48 dp logic**. Trong Desktop shrink-to-fit hoặc user scale < 1.0, kích thước vật lý nhỏ hơn 44 dp theo tỉ lệ; đây là ngoại lệ có chủ đích và phải được chỉ báo (xem 6.6).
- Icon: 16/20/24 px trong khung 24; stroke 1.5 px; join miter; corner radius tối đa 2 px.
- Button: cao 36 dp cho dense toolbar nhưng **hit target 44 dp** bằng wrapper/padding; primary 44–48 dp.
- Góc: 0 px. Focus ring: 2 px `FOCUS`, inset 1 px, không bo.
- Divider: 1 px `BORDER_SOFT`; border ngoài panel: 1 px `BORDER`.
- Không dùng shadow. Sheet/modal phân cấp bằng scrim + border top.
- Touch slop: 8 dp; long-press: 450 ms; drag start: 6 dp; double-tap: 280 ms.
- Scrollbar: 3 px, chỉ hiện khi scroll/hover; không chiếm layout.

### 5.5 Icon system

- Tất cả icon là SVG trong `assets/icons/`, tint bằng `modulate`/`icon_normal_color`.
- Grid 24×24, stroke 1.5, square-ish joins, không fill trừ trạng thái active (play, record, selected).
- Không dùng emoji.
- Bộ icon phải redraw các icon yếu hiện tại:
  - **play / pause / stop**: tam giác cân, khoảng nghỉ 2 px; pause là hai bar 3×12.
  - **key / diamond-plus**: diamond 10×10, cạnh 1.5; dấu + ở góc dưới phải.
  - **speed-graph**: trục + đường cong 2 đoạn, không dùng icon “chart” chung.
  - **render / clapperboard**: board 16×12 với hai vạch chéo, không thêm tia.
  - **import / upload**: mũi tên lên + khay 16×6.
  - **transform tools**: select (mũi tên 4 hướng), move (crosshair 4 mũi tên), rotate (cung 3/4 + mũi tên), scale (ô vuông + mũi tên chéo).
  - **eye / eye-off, lock / unlock**: cùng tỉ lệ, cùng stroke.
  - **camera / light / cube / empty**: hình học đơn giản, không perspective quá nhiều.
  - **layout**: phone/tablet/monitor ba biến thể, cùng khung.
  - **FPS / gauge**: kim + cung, không dùng icon tốc độ chung.
  - **restart**: mũi tên vòng cung 270°, đứt ở đầu.
- Icon button phải có `tooltip_text` và, nếu chỉ có icon, một label ẩn/accessible khi API cho phép.

### 5.6 Motion

| Thành phần | Thời lượng | Easing | Ghi chú |
|---|---:|---|---|
| Press/hover màu | 80 ms | ease-out | không đổi layout |
| Sheet vào/ra | 180 ms | cubic(0.2, 0, 0, 1) | slide từ bottom/right; scrim 150 ms |
| Modal | 150 ms | ease-out | fade + 8 px rise, không scale |
| Toast | 160 ms | ease-out | vào từ dưới, ra nhanh hơn |
| Mode switch | 120 ms | crossfade | không animate layout |
| Selection/gizmo | 0 ms | — | phải tức thời |
| Playhead | 0 ms | — | theo playback |

- `Prefs.reduce_motion = true` biến tất cả thành 0 ms (trừ playhead).
- Không dùng bounce/overshoot.
- Không animate chiều cao panel trong lúc kéo gizmo/playback.

### 5.7 Density theo mode

| Token | Compact | Studio | Desktop |
|---|---|---|---|
| Hàng tương tác | 44 dp | 44 dp | 44 dp |
| Transport | 52 dp | 44 dp | 44 dp |
| Top bar | 48 dp | 44 dp | 36 dp |
| Panel padding | 16 dp | 12 dp | 12 dp |
| Body text | 12 sp | 12 sp | 12 sp |
| Meta | 11 sp | 11 sp | 11 sp |
| Section gap | 16 dp | 16 dp | 12 dp |
| Timeline mặc định | 150 dp (gập) | 180 dp | 220 dp |

Mật độ Desktop đến từ top bar thấp hơn, padding ngang nhỏ hơn, nhiều cột hơn và metadata dày hơn — **không** từ hit target nhỏ hơn 44 dp. Khi Desktop shrink-to-fit, toàn bộ bảng này thu nhỏ cùng một tỉ lệ; hit target vật lý giảm nhưng vẫn là 44 dp logic.

---

## 6. Ba chế độ layout

### 6.1 Chọn mode

- Nút **Layout** trên top bar (icon monitor/tablet/phone) mở sheet **Workspace**.
- Lựa chọn: `Auto`, `Compact`, `Studio`, `Desktop`.
- `Auto` chọn theo **device dp** (physical px / density, **trước** user scale):
  - < 600 dp → Compact
  - 600–959 dp → Studio
  - ≥ 960 dp → Desktop
- **Mọi mode luôn chọn được.** Không có mode nào bị disable hay tự fallback vì kích thước màn hình.
- Mode này là **workspace của editor**. Home tự chọn layout list/table theo width của nó; không bị ép theo mode editor đã lưu.
- `short` khi **layout height** (sau scale) < 520 dp: giảm top bar, timeline gập mặc định, dock flyout dùng một page Scene/Properties/Rig.
- Mode được lưu vào `user://settings.json` và áp dụng ngay.
- **Desktop trên màn hình hẹp (kể cả điện thoại):**
  - Desktop luôn dùng bố cục Desktop đầy đủ (menu bar + rail + panel rail + flyout + status bar); timeline gập mặc định.
  - `desktop_fit` tính từ density để canvas logic đạt tối thiểu **960×600 dp** ở user scale 100%. Toàn bộ UI — chữ, icon, panel, hit target — thu nhỏ cùng một tỉ lệ.
  - User scale nhân lên trên fit; slider không bị khoá. Ở scale > 100%, canvas có thể nhỏ hơn 960×600 — đó là lựa chọn của người dùng, sheet cảnh báo thay vì chặn.
  - Không chuyển sang Studio, không ẩn panel, không đổi mode.
  - Status bar và sheet Workspace hiển thị `Desktop fit 43%` (hoặc tỉ lệ thực). Khi fit < 60%, hiện chip cảnh báo `UI nhỏ` + nút `Chuyển sang Studio`; chỉ là gợi ý, không tự đổi.
  - Hệ quả đã được chấp nhận: chữ và vùng chạm vật lý nhỏ hơn 44 dp trên điện thoại. 44 dp là kích thước **logic**; test chỉ assert 44 dp logic trong mode này.
- **Phân biệt hai đại lượng:**
  - `device_dp` = physical / density; quyết định mode của `Auto`, không đổi khi user scale.
  - `layout_width` = `size.x` sau `content_scale_factor`; quyết định panel policy bên trong Studio/Compact.
  - Ở user scale 1.3, tablet 600 dp vẫn là Studio; dock luôn là flyout overlay nên không còn ngưỡng `layout_width < 720`, không tự đổi mode và không tràn.
  - Desktop không dùng panel policy theo `layout_width`; nó dùng fit để giữ canvas ở mức đọc được tại scale 100%.
  - Fit không đổi `device_dp`, nên `Auto` không bị đổi mode khi fit bật; chuyển mode chỉ do người dùng hoặc do device dp thay đổi.

### 6.2 Compact — điện thoại dọc

```
┌──────────────────────────────────┐
│ ←  Project name            ⋮     │ 48
├──┬───────────────────────────────┤
│▣ │                               │
│✥ │          VIEWPORT             │
│⟳ │   Persp   Grid         60 fps │
│⤢ │                               │
│  │   [selection info]            │
├──┴───────────────────────────────┤
│ ◀   ▶   ▶|   00:02:12   AUTO KEY │ 52
│ [timeline ▲]                     │
├──────────────────────────────────┤
│ + Add    Scene    Props    ⏱     │ 48
└──────────────────────────────────┘
```

- **Top bar 48 dp:** back, tên project (ellipsis), dirty dot, overflow `⋮`. Undo/redo/render/save nằm trong overflow hoặc bottom action bar; không nhồi 6 icon.
- **Tool rail 44 dp** dọc trái, overlay trên viewport: select/move/rotate/scale, frame, add. Nút 44×44; icon 20.
- **Viewport** chiếm phần còn lại; HUD:
  - góc trái trên: camera preset (`Persp`) + grid toggle;
  - góc phải trên: FPS chip (bật/tắt trong Performance);
  - góc trái dưới: selection info 1 dòng, ellipsis;
  - gizmo ở giữa selection.
- **Transport 52 dp:** prev key, play 48×48, next key, timecode mono, `AUTO` toggle, `KEY` button. Loop và graph nằm trong timeline header.
- **Timeline** gập mặc định; khi mở cao 150 dp và **đẩy viewport lên**, không overlay che cảnh. Header timeline 44 dp có dope/graph, loop, snap, close.
- **Bottom action bar 48 dp:** `+ Add`, `Scene`, `Props`, `Timeline`. Đây là điểm chạm một tay.
- **Panel** (Scene/Properties/Add/Settings/Render/Import/Help): bottom sheet, header 48 dp, body scroll, footer action 48 dp. Tap bên trong **không** đóng; chỉ scrim/back/close.
  - Properties cao tối đa **72%** để vẫn thấy viewport khi sửa; Settings/Render/Import cao tối đa 86%.
  - Properties có thể kéo handle giữa 50% và 72%; trạng thái không cần lưu.
  - Khi sửa transform/material trong sheet, mỗi thay đổi gọi `UPDATE_ONCE` để preview cập nhật ngay — không đóng băng preview.
- **Empty state** trong viewport: “Chạm + để thêm vật thể” + nút Add; không illustration lớn.

### 6.3 Studio — ngang/tablet

```
┌──────────────────────────────────────────────────┐
│ ← Project · saved      ↶ ↷    Render   ⚙   ⋮    │ 44
├──┬───────────────────────────────┬───────────────┤
│▣ │                               │ SCENE      +  │
│✥ │          VIEWPORT             │ search        │
│⟳ │                               │ □ Cube        │
│⤢ │                               │ ○ Key light   │
│  │                               ├───────────────┤
│  │                               │ PROPERTIES    │
│  │                               │ Transform     │
│  │                               │ X  Y  Z       │
├──┴───────────────────────────────┴───────────────┤
│ ◀  ▶  ▶|  00:00:00   AUTO  KEY  [dope|graph]     │ 44
│ timeline tracks / speed graph                     │ 180
└──────────────────────────────────────────────────┘
```

- **Top bar 44 dp:** back, title + dirty, undo/redo, render, settings, overflow. Không dùng menu bar kiểu desktop.
- **Rail trái 44 dp** cho công cụ; **panel rail phải 44 dp** cho `Scene`, `Properties`, `Rig` (mỗi nút 44×44, accessible name, active edge). Xem addendum 2026-10-30.
- **Dock phải là overlay flyout**, không chiếm cột: một page mỗi lần, rộng tối đa 400 dp, header 44 dp (tên page + close), scrim đóng khi tap ngoài. `_dock_slot` bị xoá.
- **Timeline gập mặc định ở mọi mode**, còn đúng **56 dp** transport; clip lane và media header chỉ hiện khi sheet mở. Người dùng mở dope sheet từ fold control hoặc bottom-bar Timeline; khi mở, sheet đẩy viewport lên và giữ sàn viewport 96 dp trên màn hình thấp.
- **Panel rail** thu về nút panel trên top bar khi canvas hẹp hơn sàn Studio 480 dp; cùng một flyout, stage không phải trả giá cho hai rail.
- **Panel sheets** vẫn là modal/bottom sheet; dock flyout không thay đổi sheet contract.
- **Sheet** (Add/Settings/Render/Import) dùng modal giữa hoặc bottom sheet tùy chiều cao; trên tablet ưu tiên modal 560–720 dp rộng. Sheet Graphics dùng 860 dp khi editor đủ rộng để hai cột không tràn.

### 6.4 Desktop — màn hình lớn

```
┌──────────────────────────────────────────────────────────────┐
│ Kinema   Project ▾   Edit ▾   View ▾   Render ▾        ⚙    │ 36
├──┬───────────────────────────────────────┬───────────────────┤
│▣ │                                       │ SCENE       +     │
│✥ │              VIEWPORT                 │ search            │
│⟳ │                                       │ □ Cube            │
│⤢ │                                       │ ○ Key light       │
│  │                                       ├───────────────────┤
│  │                                       │ PROPERTIES        │
│  │                                       │ Transform         │
│  │                                       │ ...               │
├──┴───────────────────────────────────────┴───────────────────┤
│ ◀  ▶  ▶|  00:02:12 / 00:06:00  AUTO  KEY  [dope|graph]       │ 44
│ timeline 220                                                 │
├──────────────────────────────────────────────────────────────┤
│ 60 fps · 16.6 ms · Mobile · 3 objects · 12 keys · saved      │ 24
└──────────────────────────────────────────────────────────────┘
```

- **Menu bar 36 dp:** `Project` (New, Open, Save, Close), `Edit` (Undo, Redo, Delete), `View` (Frame, Grid, Camera, Panels, Layout), `Render` (Still, Sequence, Settings), `Help`. Dùng `PopupMenu` thật, có shortcut.
- `Project → New/Open/Close` đều confirm lưu nếu dirty, rồi quay về Home; `New` mở New Project sheet ở Home. **Không có Save As** trong bản này (non-goal 2.2); không giả vờ đã copy project.
- **Rail 40 dp** (vẫn hit 44 bằng padding ngang).
- **Panel rail phải 44 dp** cho Scene/Properties/Rig; **dock phải là overlay flyout** một page, rộng tối đa 400 dp, có scrim và close (addendum 2026-10-30). Không còn dock cột 320–380 dp.
- **Timeline gập mặc định** còn 56 dp transport; mở theo yêu cầu, cao 220 dp khi mở.
- **Status bar 24 dp:** FPS, frame time, renderer, object count, key count, autosave state. Đây là nơi đặt thông tin kỹ thuật, không phải viewport.
- **Hover/pointer:** hover state, cursor shape, right-click context menu, scroll wheel zoom, middle-drag orbit, `F` frame, `G/R/S` tools, `Space` play, arrow frame step, `Ctrl+Z/Y`, `Ctrl+S`, `Ctrl+R`.
- **Desktop trên điện thoại:** vẫn là Desktop đầy đủ; toàn bộ canvas được thu nhỏ đều cho đến khi vừa (xem 6.1, 6.6). Không fallback Studio. Status bar hiển thị tỉ lệ fit; chip `UI nhỏ` + nút chuyển Studio khi fit < 60%. Trên tablet 1280×800 hoặc DeX, fit = 100% và không có thay đổi.

### 6.5 Orientation

- Setting **Display → Orientation**: `Auto`, `Portrait`, `Landscape`.
- Android: gọi `DisplayServer.screen_set_orientation()` với `SCREEN_SENSOR`, `SCREEN_PORTRAIT`, `SCREEN_LANDSCAPE`.
- Manifest giữ `fullSensor` để app tự quyết định; nếu API không khả dụng, setting bị disable kèm lý do “Thiết bị không hỗ trợ đổi orientation trong app.”
- Desktop OS/headless: setting ẩn hoặc disabled; không giả vờ. (Đây là desktop OS, không phải mode Desktop trên Android.)
- Đổi orientation làm layout reflow; phải chờ 2 frame trước khi đo lại (theo kinh nghiệm overlay hiện tại), test wait 5 frame.
- **Chưa xác minh trên thiết bị.** Device checklist bắt buộc.

### 6.6 Scale

- `density = clamp(screen_get_dpi()/160, 1.0, 4.0)` trên Android; nếu dpi <= 0 thì dùng 160. Desktop OS/headless = 1.0.
- `device_dp = physical_size / density` — chỉ dùng cho `Auto` chọn mode.
- `base_factor = density` (bỏ công thức `density / stretch` cũ; nó kéo layout về 1280×800 và là một nguyên nhân tràn portrait).
- `user_scale` **0.50–2.00**, step 0.01, default 1.0. Đây là slider liên tục 50–200%, không còn dropdown 10 giá trị. Không disable khi Desktop fit (addendum 2026-10-30).
- `effective_factor = base_factor × user_scale × desktop_fit`.
- `logical_width = physical_width / effective_factor`, `logical_height = physical_height / effective_factor`.
- **Fit theo mode:**
  - Compact: giữ tối thiểu 320×480; Studio: giữ tối thiểu **480×320** vì landscape là bề mặt ưu tiên. Nếu logical nhỏ hơn, giảm `effective_factor` vừa đủ; hiển thị “UI scale bị giới hạn bởi màn hình.” Không ghi đè preference.
  - Điện thoại ngang 915×412 và 800×360 phải resolve **factor 1.0**, không bị thu nhỏ oan vì minimum portrait.
  - Desktop: `desktop_fit = min(1, physical_width / (density × 960), physical_height / (density × 600))`. Fit tính từ density, **không** từ user scale, để slider còn tác dụng. `effective_factor = density × user_scale × desktop_fit`. Khi user scale > 100%, canvas logic có thể nhỏ hơn 960×600; đây là lựa chọn của người dùng, shell hiển thị fit và cảnh báo thay vì khoá slider.
  - Khi `desktop_fit < 1`, Workspace/Settings hiển thị `Desktop fit <fit>%` cạnh slider; slider vẫn hoạt động.
- `content_scale_factor = effective_factor`; áp dụng ngay, không restart; lưu `user_scale` và mode vào `Prefs`.
- Fit chỉ áp dụng khi **editor đang ở mode Desktop**. Home, Compact và Studio dùng `effective_factor` không desktop fit; rời Desktop phải khôi phục factor ngay trong cùng frame để Home/editor kế tiếp không bị thu nhỏ ké.
- Passive scale: density. **Không** dùng OS font scale vì chưa xác nhận; ghi rõ trong code comment và settings.
- Hệ quả vật lý: ở mức scale dưới 85%, 44 dp logic có thể nhỏ hơn 44 dp vật lý. Đây là lựa chọn của người dùng; sheet cảnh báo rõ, không âm thầm fallback.
- Test tại 0.50, 0.85, 1.0, 1.15, 1.30, 2.0 trên 360×640 và 411×914; thêm Desktop ở 360×640, 411×914, 914×411; assert không tràn, fit đúng, slider không bị disable, và chuyển về Compact/Studio khôi phục factor.

### 6.7 Safe area và overflow

- `DisplayServer.get_display_safe_area()` → insets trái/top/phải/bottom (physical px); chia cho `content_scale_factor` trước khi áp vào `MarginContainer` gốc, nếu không inset sẽ sai khi Desktop fit hoặc user scale.
- Top bar và bottom action bar nằm trong safe area; sheet footer cộng bottom inset.
- Mọi sheet body dùng `ScrollContainer` + `VBoxContainer`; footer tách khỏi scroll.
- Mọi hàng ngang:
  - `size_flags_horizontal = SIZE_EXPAND_FILL` cho phần co giãn;
  - `custom_minimum_size.x = 0` cho label có thể cắt;
  - `text_overrun_behavior = OVERRUN_TRIM_ELLIPSIS` + `clip_text = true` cho title;
  - hành động phụ đưa vào overflow nếu width < 480 dp.
- Không đặt `custom_minimum_size` cộng dồn lớn hơn chiều rộng khả dụng.
- Root editor đặt `clip_contents = true`; nhưng clip chỉ là lưới an toàn, không phải cách che lỗi.
- Test assert: với mỗi control visible, `global_rect` nằm trong `get_viewport_rect()` và trong parent; không có scroll ngang ngoài ý muốn; hit target ≥ 44 dp.
- Keyboard mở: sheet cuộn field đang focus vào view; bottom inset tăng; không che action.

---

## 7. Thành phần

Mỗi component có một file riêng trong `src/ui/components/` (mới) hoặc ở lại file hiện tại nếu đã đủ nhỏ. Không component nào tự hardcode màu/spacing; tất cả lấy từ `Kit`/`Tokens`.

### 7.1 Top bar / menu bar

**Compact (48 dp):** back 44×44, title + dirty dot (expand), overflow 44×44. Overflow chứa Undo, Redo, Save, Render, Settings, Help, Close.
**Studio (44 dp):** back, title + dirty, undo, redo, render, settings, overflow.
**Desktop (36 dp):** logo “Kinema” 12 sp semibold, menu buttons `Project`, `Edit`, `View`, `Render`, `Help`; bên phải là undo/redo, settings. Menu dùng `PopupMenu` với shortcut hiển thị bên phải.
- Title ellipsis; dirty dot 5×5 `TIME` khi có thay đổi, rỗng khi sạch.
- Save state: “Saved” 11 sp `TEXT_MUTED` cạnh title; khi đang lưu, “Saving…” + spinner 12 px (không animation nếu reduce motion).
- Renderer **không** lặp ở top bar. Backend thực nằm ở status bar (Desktop) và sheet Graphics/Renderer; tránh hai nguồn sự thật.
- Không hiển thị FPS ở top bar; FPS ở HUD/status bar.

### 7.2 Tool rail

- Nút 44×44, icon 20, tooltip; selected có nền `FOCUS_DARK`, icon `FOCUS_BRIGHT`, viền trái 2 px `FOCUS`.
- Tools: Select, Move, Rotate, Scale; divider; Frame; Add.
- Compact: rail nổi trên viewport, nền `SURFACE` 92% opacity? Không dùng opacity/glass; dùng `SURFACE` đặc + border. Có thể thu gọn thành một nút “Tools” mở popover nếu height < 480.
- Desktop: rail 40 dp visual, hit 44; thêm label tooltip.
- Keyboard: `Q/W/E/R` cho select/move/rotate/scale (desktop), `F` frame.

### 7.3 Viewport và HUD

- `SubViewport` + `TextureRect`/`Control` surface như hiện tại; camera orbit/pan/zoom giữ nguyên.
- HUD (đều nằm trong một `_hud_root` để ẩn khi modal/sheet mở):
  - top-left: camera preset chip (`Persp`, `Front`, `Right`, `Top`) + grid toggle; hit 44.
  - top-right: FPS chip **48×44 dp** mono 11 sp, cập nhật 4 Hz; tap mở Performance overlay. Màu: ≥55 `TEXT`, 30–54 `TEXT_MUTED`, <30 `DANGER`; không có sample thì `—`.
  - top-right, cạnh FPS: nút `Render` mở **quick render** ngay trong editor.
  - draft tag nhỏ chỉ hiện khi quality đang hạ trong lúc camera/gizmo/playback/inspector edit; idle và capture không hiện.
  - bottom-left: selection info: icon + name + type + “3 keys” hoặc “No keys”; 1 dòng, ellipsis; tap focus inspector.
  - bottom-right: preview scale indicator khi adaptive quality hạ (`75%`), chỉ hiện khi khác 100%.
  - center: gizmo; selection outline `TIME` 1.5 px; hover outline `TIME` 50%.
  - camera/light/empty locators là glyph SVG screen-space (không phải mesh 3D); marker mesh của document ẩn trong lúc edit và capture. Locator chọn được, sáng hơn khi selected, và không được nuốt tap của object khác.
- Grid: hai mức; toggle; màu `GRID`/`GRID_MAJOR` đã hạ độ tương phản để không tranh với hình.
- Empty scene: text “Scene trống” + nút `Add object`; không illustration.
- Khi render/sequence: HUD ẩn (trừ progress do editor quản lý); camera giữ nguyên.
- Khi sheet mở: HUD ẩn hoàn toàn để chip sáng không nổi trên scrim; viewport vẫn hiển thị và freeze update (`UPDATE_ONCE`).
- FPS overlay (khi bật Full):
  - panel **248×190 dp**, nền `SURFACE`, border 1 px, neo góc phải trên của viewport;
  - FPS lớn 22 sp mono; frame time 12 sp; graph 120 sample thật, cập nhật 4 Hz, có đường tham chiếu 30 fps;
  - dòng thật: `42 draw · 1200 prim`, `preview 72% · 960×540`, renderer + preset, `7 obj · 8 keys`;
  - nút `Close` 44×44; không có nút Reset giả.
- Không vẽ FPS bằng text mỗi frame; cập nhật 4 Hz từ `Perf.sample_updated`.

### 7.4 Outliner

- Header 44 dp: “Scene” + count + `+` 44×44; search field 36 dp (hit 44) khi > 6 object; filter chips `All`, `Mesh`, `Light`, `Camera` (horizontal scroll nếu hẹp).
- Row **44 dp**, gap 1, list top 6, bottom 10; row hit guard phủ toàn hàng nên tap vào khoảng trống giữa các control vẫn chọn object, không rơi xuống viewport.
- Selected: nền `FOCUS_DARK`, text `TEXT`, viền trái 2 px `FOCUS`.
- Hover: `SURFACE_HOVER`; pressed: `SURFACE_3`.
- Double-tap/Enter: rename inline (LineEdit 36 dp); Esc huỷ; Enter commit; validate empty → giữ tên cũ + toast.
- Long-press/right-click: context menu (Rename, Duplicate? non-goal, Delete, Focus, Hide/Show). Không thêm Duplicate nếu document chưa hỗ trợ; chỉ hiện action thật.
- `+` mở Add sheet.
- Empty: “Chưa có vật thể” + Add.
- Không rebuild toàn bộ khi transform đổi; chỉ update row label/icon khi scene structural change. Việc fit rows chạy deferred sau layout để row cuối không bị cắt.

### 7.5 Inspector

- Header: type icon 20, name 13 sp semibold, kind 11 sp muted, overflow.
- Sections (collapsible, mặc định mở Transform + Material/Light/Camera):
  - **Transform:** Position X/Y/Z, Rotation X/Y/Z (độ), Scale X/Y/Z. Mỗi hàng: label 24 dp, field 3 phần, key button 32 (hit 44) hình diamond. Field dùng `NumField` hiện có (drag scrub, +/-).
  - **Geometry:** read-only cho imported mesh (vertex count, surface count). Không chỉnh size/segments trong bản này.
  - **Material:** color swatch 44×44 + hex; metallic 0–1; roughness 0–1. Đây là các property document đã hỗ trợ.
  - **Light:** type (Directional/Omni), color, energy, range. Đây là các property document đã hỗ trợ; shadow toàn cục nằm trong Graphics.
  - **Camera:** FOV 20–120. Không có active/near/far trong bản này.
  - **Animation:** channel list (Position/Rotation/Scale), key count, key button per channel, “Key all transform” 44 dp.
- **Không thêm authoring property mới trong bản này.** Emission, per-light shadow toggle/size, primitive size/segments, scene camera active là non-goal (xem 2.2). Inspector chỉ phơi bày những gì `document.gd` thực sự lưu và áp dụng; nếu thiếu API, control không xuất hiện — không hiển thị control giả.
- Key button:
  - có key tại playhead → diamond đặc `TIME`;
  - không có key → diamond rỗng `TEXT_MUTED`;
  - có thay đổi unkeyed → diamond rỗng + chấm `WARNING`.
  - tap = insert/update key cho channel đó; long-press = xoá key tại playhead (confirm nếu >1 channel?).
- Field states: normal, focus (`FOCUS` border 2 px), invalid (`DANGER` border + message 11 sp), disabled (`TEXT_DIM`, no tap).
- Numeric: tap chọn toàn bộ; drag ngang để scrub; Enter/blur commit; Esc revert; clamp; một drag = một undo step.
- Section header 44 dp, chevron 16, uppercase 10 sp; tap toggle; state lưu trong `Prefs`.
- Scroll: toàn bộ body; header dính trên (sticky) nếu Godot cho phép; nếu không, header nằm ngoài scroll.
- Empty: “Chọn một vật thể để xem thuộc tính.”

### 7.6 Timeline, transport, speed graph

**Transport (44/52 dp):**
- prev key 44, play/pause 48 (amber), next key 44; timecode mono 13; `AUTO` toggle 44 (amber khi on, outline khi off); `KEY` button 44; loop 44; graph/dope toggle 44.
- Timecode: `MM:SS:FF` (frame), click để nhập thời gian; hiển thị `current / duration` ở Desktop.
- Scrub bar 24 dp dưới transport? Hiện có `scrub_bar.gd`; giữ, nhưng hit 44 bằng wrapper.
- Khi play: play icon → pause; timecode cập nhật; playhead di chuyển; preview `UPDATE_ALWAYS` trong lúc play.

**Dope sheet:**
- Ruler 24 dp: tick mỗi frame (minor) và mỗi giây (major); label giây mono 10 sp.
- Track list trái 140 dp (Compact 120): channel name + key count; row 32 dp visual, hit 44.
- Key diamond 10×10, hit 32 (mở rộng 44 trong row 44); selected `TIME_BRIGHT` + outline; hover `TIME`; key ngoài playhead `TIME` 80%; ghost unkeyed `WARNING` outline.
- Playhead 1.5 px `TIME` + tam giác đầu; kéo được; snap theo frame nếu snap on.
- Tap key = select; drag = retime; long-press = menu (Delete, Ease presets, Go to key); double-tap = go to key.
- Pinch = zoom; two-finger drag = pan; double-tap ruler = fit.
- Snap toggle 44; `Snap 1f` label; nếu tắt, tự do.
- `Key all` / `Delete key` trong overflow hoặc header; không nhồi vào transport.

**Speed graph:**
- Giữ cách sample speed từ engine (`_channel_speed`) — đây là điểm mạnh, không thay bằng công thức tự chế.
- Trục ngang = thời gian; trục dọc = tốc độ; baseline 0; label `×` mono.
- Đường cong 2 px `FOCUS`; fill 12% `FOCUS`; handle tròn 8 px (hit 44) `TIME`; kéo dọc đổi transition; snap preset.
- Presets: `Hold` (transition 0), `Ease Out` (0.5), `Linear` (1.0), `Ease In` (2.0), `Custom` (giá trị hiện tại). **Không có `Ease In Out`** vì document chỉ lưu một transition scalar; S-curve/bezier thật cần schema mới và là non-goal.
- Readout khi kéo: `EASE 0.75× · Ease Out`; hiển thị đúng scalar, không gọi tên đường cong không tồn tại.
- Không vẽ graph nếu chưa chọn object/channel; empty state text.
- Graph và dope dùng chung playhead/time mapping.

### 7.7 Sheet / modal system

- Một `Overlay` duy nhất; chỉ một modal tại một thời điểm.
- **Bottom sheet (Compact):**
  - scrim `SCRIM`; panel `SURFACE`, border-top 1 px `BORDER`;
  - góc 0; cao tối đa 86% màn hình; header 48 dp (title 13 semibold, subtitle 11 muted, close 44);
  - drag handle 4×32 `BORDER` ở giữa header, chỉ vùng handle mới drag-to-dismiss; body scroll; footer 48 dp + safe inset;
  - footer là một strip `SURFACE` đặc, hairline trên 1 px, tách khỏi body scroll; action không bao giờ trôi trên nội dung;
  - tap body **không** đóng; scrim tap đóng; back đóng; Esc đóng (desktop).
- **Modal (Studio/Desktop):**
  - rộng `min(720, width - 48)`; cao `min(640, height - 48)`; header 48; body scroll; footer;
  - không kéo; chỉ close/back/scrim.
- Focus: mở sheet đặt focus vào control đầu tiên; đóng trả focus về nút mở.
- Keyboard: Tab trong modal; không thoát ra nền; Enter action primary; Esc close.
- Nếu có thay đổi chưa lưu trong sheet (settings áp dụng ngay; render đang chạy): confirm trước khi đóng.
- Không mở sheet mới chồng sheet cũ; thay nội dung hoặc đóng trước.

### 7.8 Settings surfaces

Settings là **một màn hình** có nav, không phải một sheet dài vô tận.

- **Desktop:** modal 860×640; nav trái 200 dp (General, Editor, Display, Graphics, Performance, Render, Import, About); content phải scroll; search 36 dp ở đầu nav (optional, nếu làm được).
- **Studio:** modal 720×600; nav trái 180; content scroll.
- **Compact:** full-screen sheet; danh sách category (row 44) → trang detail có back; mỗi trang scroll; footer reset.
- Row chuẩn: label 12 sp + hint 11 sp muted; control bên phải (switch 44×24 hit 44, segmented, stepper, dropdown). Row cao 44–56 dp.
- Section header dùng IBM Plex Mono uppercase **11 sp** + divider.
- Thay đổi áp dụng ngay (trừ renderer: restart; layout: ngay; orientation: ngay nếu API).
- Mỗi section có `Reset` (confirm nhẹ, toast “Đã đặt lại”).
- Giá trị invalid bị clamp + hiển thị lý do; không crash.
- Không có setting nào không map vào API; nếu API không có, disable + hint.

### 7.9 Render sheet

- **Quick render trong editor:** nút `Render` trên HUD chụp **full quality** qua `capture_still`, rồi mở sheet preview ngay trong editor (ảnh cao 160 dp trên landscape thấp, 300 dp trên màn cao) với `Save PNG`. Không ghi MP4, không giả video.
- Header `Render`; segmented `Still` / `Sequence`.
- **Still:** resolution long edge 1280/1920/2560/3840; MSAA Off/2x/4x/8x; transparent background toggle (nếu probe hỗ trợ); render từ **editor camera hiện tại**; nút `Render PNG` 48 dp.
- **Sequence:** frame range start/end (mặc định 0..duration×fps, số frame = end−start), FPS hiển thị (project), resolution, MSAA, transparent; nút `Render ZIP` 48 dp; ước lượng số frame + dung lượng (frame_count × resolution ước tính, ghi “ước tính”).
- **Không có camera dropdown.** Scene camera là non-goal (2.2); render đúng những gì đang thấy trong preview.
- Output: `Save to…` dùng SAF; nếu không chọn, lưu `user://renders/`; hiển thị đường dẫn thực.
- Progress: bar + `Frame 42 / 144` + cancel 44; không cho đóng app giữa chừng mà không confirm.
- Kết quả: toast + `Open folder` (nếu API) hoặc path copy; lỗi hiển thị message thật.
- **MP4:** không có nút MP4. Ghi chú: “MP4 không được hỗ trợ trong bản này. Xuất PNG sequence rồi encode bên ngoài.” Không fake.
- Render dùng `capture_still` thật; sequence render từng frame, đóng ZIP; cleanup frame tạm; không để file rỗng.

### 7.10 Import sheet

- Nguồn: `glTF / GLB`, `OBJ + MTL`, `FBX`.
- FBX row disabled + giải thích: “FBX nhị phân cần parser riêng; bản này không hỗ trợ. Hãy chuyển sang glTF/GLB hoặc OBJ.” Không có nút giả.
- File picker: `FileDialog`/Android SAF; filter đúng đuôi.
- Options: scale 0.01/0.1/1/10/100; import materials/textures on/off; merge by material on/off (nếu importer hỗ trợ).
- Progress + lỗi cụ thể: file hỏng, thiếu MTL, texture không đọc được, SAF sibling không truy cập được.
- SAF note: “Android có thể không cho phép đọc file .mtl/texture cùng thư mục với file được chọn. Nếu import thiếu material, hãy copy cả thư mục vào bộ nhớ app hoặc chọn file trong thư mục đó.”
- Import thành công: object mới được chọn, frame vào nó, toast; một undo step.

### 7.11 Home / project browser

Home được dựng lại hoàn toàn, không hero/card.

- **Top bar 56 dp:** wordmark `KINEMA` 13 sp semibold + `STUDIO` 13 sp dim, mark vuông 30 dp; bên phải `About` 44×44. Không có marketing nav.
- **Compact:** search 44; project row 56 dp; bottom `New project` 48.
- **Studio:** hai cột khi width ≥ 720 dp: list + cột giá trị; detail hiển thị tên, modified, objects, duration, path; actions Open/Rename/Delete.
- **Desktop:** cùng list dạng bảng: Name, Objects, Duration, Modified; header 32; row 56; toolbar New/Search/Sort; nội dung tối đa 980 dp và căn giữa.
- Project row: icon 15 trong ô 32, name 13, meta 11 (`3 objects · 6.0s · 2h ago`), overflow 44. Không card, không viền từng hàng; chỉ hover fill và một hairline dưới header.
- New project sheet: name field; template list (Blank, Study) dạng row 56 dp với icon + mô tả, radio 20; `Create` primary 48. Không card lớn.
- Empty: icon 24, “No projects yet”, “Start a blank stage, or load the primitive study…” + New.
- Search: filter theo tên; không có kết quả → empty state.
- Sort: Recent / Name; lưu lựa chọn.
- **Nguồn dữ liệu:** Home liệt kê **tất cả project** dưới `user://projects/` qua `Store.list_projects()` mới (quét folder, đọc `project.json`, trả id/title/modified/objects/duration/path). `recent_projects()` chỉ dùng để xếp thứ tự “Recent”, không phải nguồn duy nhất. Không hiển thị template vì project JSON hiện không lưu template.
- Size: tính bằng cách quét dung lượng folder khi mở detail hoặc footer; cache 5 s; không quét mỗi frame.
- Delete: confirm nêu rõ tên + không thể hoàn tác; xoá folder thật; nếu lỗi, báo.
- Storage: dòng “X project · Y MB” ở footer; lấy từ filesystem thật. Footer phone là stack 2 dòng, không tranh ngang.
- Không hiển thị recent dạng card; không illustration trang trí.

### 7.12 Status bar, toast, help, about

- **Status bar (Desktop):** 24 dp, `SURFACE`, border-top 1 px; trái: FPS + frame time + renderer; phải: object count + key count + save state + fit. Text **11 sp mono**; click FPS mở Performance. Khi Desktop fit < 100%, thêm `fit 43%` cạnh renderer; fit < 60% dùng `WARNING`.
- **Toast:** bottom-center trên transport, 1 dòng 12 sp, icon 16, nền `SURFACE_3`, không viền; tự ẩn 2.7 s; không chặn tap; lỗi 4 s.
- **Help:** shortcuts + gestures + limitations; dạng bảng 2 cột; scroll; không text marketing.
- **About:** version, engine 4.7.2, package, renderer thực, build type, licenses; nút copy build info.
- **Empty states:** scene trống, không selection, không key, không project, không render, không search result; mỗi empty state có một hành động chính.
- **Error states:** save fail, load fail, import fail, render fail, renderer unsupported, orientation unsupported; message cụ thể + hành động (Retry, Choose another folder, Convert file, Use Auto).

---

## 8. Tương tác

### 8.1 Panel không đóng khi chạm bên trong

Đây là yêu cầu cứng, đã từng là lỗi.

- Scrim là control duy nhất nhận tap ngoài panel.
- Panel và toàn bộ body đặt `mouse_filter = MOUSE_FILTER_STOP`.
- Không dùng `gui_input` trên root để đóng khi bất kỳ tap nào xảy ra.
- Bottom sheet chỉ đóng khi: tap scrim, back, nút close, hoặc kéo handle xuống quá 25% chiều cao.
- Test: mở sheet, tap 5 điểm bên trong body (trên/xuống/trái/phải/giữa), assert `overlay.has_modal() == true`; tap scrim, assert false.
- Drawer Studio/Compact: dock là flyout overlay; tap bên trong không đóng; chỉ scrim/close/back đóng.

### 8.2 Cử chỉ viewport

| Cử chỉ | Hành vi |
|---|---|
| 1 ngón kéo trên vùng trống | orbit camera |
| 1 ngón kéo trên gizmo axis | di chuyển theo axis |
| 2 ngón kéo | pan camera |
| 2 ngón pinch | zoom |
| tap | select object |
| tap vùng trống | bỏ chọn |
| double-tap object | frame object |
| long-press object | context menu (Focus, Hide, Delete nếu hợp lệ) |
| 1 ngón kéo trên HUD | không orbit; HUD nuốt event |

- Không cho orbit bắt đầu trong 8 dp đầu nếu chạm gần gizmo; ưu tiên gizmo.
- Không có gesture nào là cách duy nhất để làm một việc quan trọng; luôn có nút/menu tương đương.
- Trong lúc kéo gizmo, camera bị khoá; HUD ẩn tooltip.
- Trong lúc play, orbit vẫn được; playback không dừng trừ khi user bấm pause.

### 8.3 Timeline

- Tap ruler/scrub = seek; kéo = scrub; thả = dừng.
- Tap key = select; kéo = retime; snap nếu bật; hiển thị time tooltip.
- Long-press key = menu Delete/Ease/Go to.
- Pinch = zoom; two-finger pan = pan; double-tap = fit to keys.
- Kéo ngoài biên = auto-pan? Bản này không; giữ đơn giản, tránh lỗi.
- Không cho timeline ăn gesture của viewport; biên rõ ràng.
- Khi autokey on, key mới xuất hiện ngay; khi off, ghost key màu `WARNING` nếu có unkeyed change.

### 8.4 Numeric field

- Tap: focus + select all.
- Drag ngang: scrub giá trị theo step; shift = step nhỏ; không cần bàn phím.
- +/- stepper 32 dp (hit 44) hai bên; long-press = repeat.
- Enter/blur: commit; Esc: revert.
- Clamp theo min/max; invalid → border `DANGER` + message; không tự sửa im lặng trừ khi clamp.
- Một drag = một undo step; `begin_edit` khi bắt đầu, `end_edit` khi thả/blur.
- Không update transform mỗi pixel nếu frame time quá cao; throttle 60 Hz hoặc theo frame.

### 8.5 Autokey và unkeyed

- `AUTO` toggle trong transport:
  - on: pill `TIME` 20% + text `AUTO` + chấm; tất cả thay đổi transform tạo key nếu chưa có;
  - off: outline `BORDER`, text `TEXT_MUTED`; không tạo key.
- `KEY` button luôn tạo/cập nhật key cho transform channels tại playhead, bất kể autokey.
- Khi sửa mà không có key và autokey off:
  - inspector hiện chip `Unkeyed` `WARNING` cạnh Transform;
  - timeline hiện ghost diamond rỗng `WARNING` tại playhead;
  - toast 1 lần: “Thay đổi chưa được key. Bấm KEY để giữ.” (không lặp mỗi frame).
- Khi seek/play, animation sample thắng; unkeyed pose mất. Đây là hành vi chuẩn của DCC, nhưng phải báo trước.
- Không tự động tạo key khi autokey off. Không fake.

### 8.6 Keyboard shortcuts (Desktop/Studio có bàn phím)

| Phím | Hành vi |
|---|---|
| `Q/W/E/R` | select/move/rotate/scale |
| `F` | frame selection |
| `Space` | play/pause |
| `←/→` | frame step |
| `Shift+←/→` | 10 frame |
| `Home/End` | start/end |
| `K` | key transform |
| `Delete` | xoá key selected hoặc object (confirm) |
| `Ctrl/Cmd+Z` | undo |
| `Ctrl/Cmd+Shift+Z` hoặc `Ctrl+Y` | redo |
| `Ctrl/Cmd+S` | save |
| `Ctrl/Cmd+R` | render sheet |
| `1/2/3/4` | camera Front/Right/Top/Persp |
| `G` | grid toggle? conflict với move; dùng `Shift+G` |
| `Esc` | đóng sheet / bỏ chọn |
| `Tab` | focus next |
| `Enter` | activate |

- Không dùng shortcut xung đột với IME; kiểm tra khi field focus thì không xử lý global shortcut trừ `Esc`.
- Hiển thị shortcut trong menu/help.

### 8.7 Back hierarchy

1. Nếu modal mở → đóng modal.
2. Nếu drawer mở → đóng drawer.
3. Nếu timeline đang mở ở Compact và đang focus? → không đóng; timeline không phải modal.
4. Nếu đang play → pause (không thoát).
5. Nếu có thay đổi chưa lưu → confirm save/discard/cancel.
6. Về Home.
7. Từ Home → thoát app (confirm nếu có project đang mở? Home không có).

- `handle_back()` trả `true` nếu đã xử lý; main chỉ thoát khi false.
- Không để back xuyên qua sheet làm mất dữ liệu.

### 8.8 Feedback và haptics

- Press feedback ≤ 80 ms: đổi nền/viền, không đổi layout.
- Key insert/delete: toast nhẹ + haptic 10 ms nếu `Prefs.haptics` on.
- Snap: haptic 5 ms.
- Lỗi: haptic 20 ms + toast đỏ.
- Haptics dùng `Input.vibrate_handheld(ms)` nếu API khả dụng; nếu không, im lặng, không giả.
- Không rung khi playback/scroll liên tục.

### 8.9 Accessibility

- Tương phản: body ≥ 4.5:1; large text/icon ≥ 3:1; `TEXT_DIM` chỉ disabled/decorative.
- Touch target ≥ 44 dp; kiểm tra bằng test.
- Mọi icon-only button có `tooltip_text` và text label trong Help; nếu Godot API cho phép accessible name, đặt thêm.
- Focus ring 2 px `FOCUS`, luôn hiện khi keyboard focus; không ẩn bằng outline none.
- Thứ tự focus theo visual order; modal trap focus; đóng trả focus.
- Không dùng màu làm tín hiệu duy nhất: selected có nền + viền + icon; autokey có chữ; lỗi có icon + text.
- UI scale 0.50–2.00 (slider liên tục); test không cắt chữ ở 100%, cảnh báo dưới 85%; cho phép wrap ở body, ellipsis ở title.
- Reduce motion setting.
- Screen reader: Godot Android support hạn chế; ghi rõ trong About/Help. Không tuyên bố hỗ trợ đầy đủ.
- IME: field có label; keyboard type đúng; cuộn field vào view; không che action.

---

## 9. Kiến trúc hiệu năng

### 9.1 Nguyên tắc

Không có một “nút tăng tốc” duy nhất. Lag là kết quả của bốn tầng:

1. **Render 3D:** preview render mọi frame dù không đổi.
2. **UI refresh:** rebuild panel theo từng bước kéo.
3. **Chất lượng render:** MSAA/shadow/environment quá cao so với GPU.
4. **Frame pacing:** không có adaptive quality, không có ngân sách frame.

Thiết kế sửa cả bốn, theo thứ tự đo được.

### 9.2 Preview update policy

| Trạng thái | `render_target_update_mode` | Ghi chú |
|---|---|---|
| Idle, không thay đổi | `UPDATE_ONCE` sau frame cuối | Không render 3D liên tục |
| Orbit/pan/zoom | `UPDATE_ALWAYS` | Trong lúc gesture |
| Kéo gizmo | `UPDATE_ALWAYS` | Trong lúc drag |
| Playback | `UPDATE_ALWAYS` | Trong lúc play |
| Sheet mở | `UPDATE_ONCE` mỗi edit | Không render liên tục; sửa transform/material vẫn thấy preview cập nhật ngay |
| App background | `UPDATE_DISABLED` | Dừng hẳn; lưu project |
| Render still | `UPDATE_ONCE` trên probe viewport | Không đụng preview |
| Sequence | `UPDATE_ONCE` từng frame | Progress/cancel |

- Sau khi gesture kết thúc: đặt `UPDATE_ONCE`, render một frame, rồi để yên.
- Không dùng `UPDATE_ALWAYS` làm mặc định.
- Khi playback dừng: `UPDATE_ONCE` ngay tại frame hiện tại.
- Khi đổi selection: chỉ overlay redraw; preview không cần render lại nếu camera/cảnh không đổi (trừ khi gizmo/outline nằm trong 3D; hiện overlay vẽ 2D nên không cần).
- Khi đổi material/light: `UPDATE_ONCE`.
- Khi đổi camera: `UPDATE_ONCE` (hoặc ALWAYS trong lúc orbit).

### 9.3 UI refresh

**Vấn đề hiện tại:** `object_changed` phát mỗi bước kéo; outliner/inspector/timeline có thể refresh toàn bộ.

**Thiết kế:**

- Thêm signal `transform_changed(id: String, channels: PackedStringArray)` trong Document.
- `object_changed` chỉ phát cho thay đổi cấu trúc/không phải transform: thêm/xoá/rename/material/light/camera/visibility.
- `transform_changed` phát cho position/rotation/scale; editor chuyển tiếp đến:
  - viewport: `queue_redraw()` overlay + `UPDATE_ONCE`;
  - inspector: chỉ cập nhật field của channel thay đổi, không rebuild section;
  - timeline: chỉ cập nhật playhead/key row nếu cần; không rebuild track list;
  - outliner: **không** nghe transform_changed.
- Coalesce: editor giữ `_ui_dirty_flags` (outliner, inspector, timeline, header) và flush tối đa 1 lần/frame bằng `call_deferred`.
- Không rebuild row khi chỉ đổi giá trị; dùng `set_value_no_signal` cho NumField.
- Không tạo Label/Button mới trong `_process`; pool row nếu cần.
- Timeline chỉ rebuild khi: selection đổi, key set đổi, duration/fps đổi, mode đổi. Playhead chỉ `queue_redraw` canvas.
- Outliner chỉ rebuild khi: scene_changed, rename, visibility/lock, selection. Không rebuild khi transform.
- Inspector: cache section nodes; cập nhật text/visibility; không free/rebuild.
- Header: chỉ update khi title/dirty/save state đổi.

### 9.4 Chất lượng render và adaptive quality

- Preview resolution cap theo mode:
  - Compact: long edge 1280;
  - Studio: 1600;
  - Desktop: 1920, nhưng khi Desktop fit trên điện thoại thì cap = `min(1920, physical long edge)` để không render vượt màn hình;
  - user setting có thể hạ xuống 720/1080.
- **Draft edit quality** (mặc định bật):
  - khi camera orbit/pan/zoom, kéo gizmo, playback hoặc đang sửa inspector: preview scale 0.72, cap 1400, MSAA tắt, SSAO/SSIL/SSR/glow/volumetric fog tắt, shadow filtering rẻ hơn;
  - sau **0.45 s** không tương tác, khôi phục đúng preset đầy đủ;
  - `capture_still` luôn khôi phục full quality trước khi chụp, và chỉ bật lại draft nếu vẫn đang tương tác/playback;
  - tag `Draft` chỉ hiện trong lúc hạ chất lượng; không bao giờ nằm trong ảnh render.
- `scaling_3d_scale` mặc định theo preset; adaptive quality:
  - đo frame time trung bình 30 frame;
  - nếu > 20 ms trong 30 frame → giảm scale 0.1 (sàn 0.6);
  - nếu < 14 ms trong 120 frame → tăng 0.05 (trần 1.0);
  - hiển thị `Preview 75%` khi khác 1.0;
  - không dao động: hysteresis 2 bước, cooldown 1 s.
- MSAA: preset Performance 0, Balanced 2×, Quality 4×; user override.
- TAA chỉ bật nếu `Gfx.is_forward()`; nếu không, disable + hint.
- SSAO/SSIL/SSR: chỉ bật nếu capability trả true; nếu không, disable + hint.
- Shadow: preset Performance 1024/quality 1/distance 28; Balanced 2048/2/40; Quality 4096/3/60.
- Glow: Balanced on, Performance off, Quality on; nếu backend không hỗ trợ, disable.
- `Engine.max_fps`: 60 default; 30/60/90/120/0 (unlimited). Trên pin, 30 tiết kiệm.
- `DisplayServer.window_set_vsync_mode` nếu khả dụng; nếu không, ẩn.
- Không bật volumetric fog mặc định; nếu bật, cảnh báo chi phí.

### 9.5 Instrumentation

- Nguồn thật:
  - `Performance.get_monitor(Performance.TIME_FPS)`;
  - `TIME_PROCESS`, `TIME_PHYSICS`; thời gian render lấy từ frame time tổng nếu đo được, ngược lại hiển thị `—` (không bịa monitor);
  - `OBJECT_NODE_COUNT`, `OBJECT_COUNT`;
  - `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, `RENDER_TOTAL_PRIMITIVES_IN_FRAME`;
  - `RenderingServer.get_current_rendering_method()`, `get_video_adapter_name()` (nếu có).
- Cập nhật 4 Hz, không mỗi frame.
- FPS chip: `60` + màu (>=55 success, 30–54 warning, <30 danger); click mở overlay.
- Overlay Full: FPS lớn, frame time, UI/3D split nếu đo được, draw calls, primitives, preview resolution, renderer, preset, object/key count.
- Frame graph: 120 sample, mỗi sample 250 ms; vẽ bằng `_draw`; không dùng 120 Label.
- Không hiển thị số liệu giả; nếu API trả 0/không có, hiển thị `—`.
- Log một dòng khi frame > 50 ms (chỉ debug build): trạng thái, object count, preview size; không spam.

### 9.6 Ngân sách và tiêu chí chấp nhận

| Hạng mục | Mục tiêu | Cách đo |
|---|---|---|
| UI frame | < 8 ms | `TIME_PROCESS` trong scene tĩnh |
| 3D preview | mục tiêu < 16.6 ms (60 fps) | frame time overlay; **không phải gate** trên máy test |
| Orbit | không frame > 50 ms | frame graph |
| Key edit | < 16 ms | test headless + device |
| Scene mở | < 1 s với project nhỏ | log |
| Idle | 0 render 3D/frame | `UPDATE_ONCE` |
| Bộ nhớ | không tăng theo thời gian | profile 5 phút |

**Chưa có thiết bị Android trong môi trường này.** Các con số trên là mục tiêu thiết kế; phải xác minh trên thiết bị thật (Android 15–17). Headless chỉ đo tương đối. 60 fps không phải điều kiện chấp nhận; phải báo cáo FPS thật và trạng thái adaptive quality.

---

## 10. Hành vi keyframe

### 10.1 Bảng chân trị

| Autokey | Có key tại playhead? | Khi sửa transform | Khi seek/play |
|---|---|---|---|
| Off | Có | Cập nhật key tại playhead | Giữ giá trị mới |
| Off | Không | Chỉ đổi pose live; hiện `Unkeyed` | Animation sample thắng; pose mất |
| On | Có | Cập nhật key tại playhead | Giữ giá trị mới |
| On | Không | Tạo key tại playhead | Giữ giá trị mới |

Đây là quy tắc cốt lõi: **autokey chỉ kiểm soát việc tạo key mới; sửa tại key có sẵn luôn cập nhật key đó.**

### 10.2 Phạm vi channel

- Position, rotation, scale là ba channel độc lập.
- Chỉ channel thực sự thay đổi mới được cập nhật/tạo key. Không key cả 3 nếu chỉ đổi X.
- So sánh với epsilon:
  - position: 1e-5;
  - rotation: góc 0.01°;
  - scale: 1e-5.
- Nếu không xác định được channel nào đổi (ví dụ field commit), dùng channel được chỉ định bởi field đó.

### 10.3 "Tại playhead" nghĩa là gì

- Tolerance = `0.5 / fps` (nửa frame). Nếu playhead nằm trong tolerance của key, coi là tại key.
- Không tạo key trùng: nếu `get_key_index_at()` trả index >= 0, update index đó.
- Nếu có nhiều key trong tolerance (dữ liệu cũ bị trùng), chọn key gần nhất; không tự xoá key khác trừ khi user yêu cầu.
- Retime key không đổi transition/easing.
- Update key không đổi thứ tự key; nếu giá trị làm key trùng thời gian với key khác, giữ key hiện tại và báo? Tốt nhất: update tại chỗ, không tạo mới, nên không có trùng mới.

### 10.4 Luồng code đề xuất

`document.gd`:

```gdscript
func set_object_transform(id, position, rotation, p_scale, key := true) -> void:
    # 1. áp pose lên node + record
    # 2. xác định channel thay đổi
    # 3. nếu _loading: chỉ áp pose
    # 4. nếu có key tại playhead: _update_keys_at_time(id, current_time, changed)
    # 5. elif key and autokey: _insert_keys_at_time(id, current_time, changed)
    # 6. phát transform_changed(id, changed)
```

- `_update_keys_at_time` dùng `get_key_index_at(id, channel, time, tolerance)` và `set_key_value(...)`, không insert.
- `_insert_keys_at_time` dùng `insert_channel_key`/`_insert_key` hiện có.
- `_key_selected_transform` được refactor thành `_key_channels(id, channels, mode)` với mode `update_or_insert` / `insert_only`.
- `insert_transform_keys()` (nút KEY) dùng mode `update_or_insert` cho cả 3 channel, bất kể autokey.
- Không đổi public API nếu có thể; giữ `set_object_transform` signature, thêm tham số optional `channels` nếu cần.
- `_loading` guard giữ nguyên: load không tạo key.

### 10.5 Undo và UX

- Một gesture kéo gizmo/field = một undo step:
  - `doc.begin_edit("Move object")` khi bắt đầu;
  - update liên tục trong lúc kéo (không tạo undo mỗi frame);
  - `doc.end_edit()` khi thả/blur.
- Key update nằm trong cùng undo step.
- Nếu user kéo rồi huỷ (Esc), revert pose + key; cần snapshot trước khi kéo.
- Toast sau khi update key? Không; tránh spam. Chỉ toast khi insert key mới hoặc xoá.
- `Unkeyed` chip xuất hiện khi autokey off + không có key + pose khác giá trị sample; biến mất khi key hoặc seek.
- Timeline ghost diamond `WARNING` tại playhead khi unkeyed.

### 10.6 Test TDD

1. **Red:** tái hiện đúng lỗi:
   - tạo object, key position tại 0 và 2;
   - seek 2;
   - `set_object_transform(... (5,0,0), autokey=false)`;
   - assert key tại 2 có giá trị (5,0,0);
   - seek 0 rồi 2; assert node position (5,0,0).
   - Trước fix, test fail ở assert key value.
2. **Green:** implement rule; test pass.
3. **Regression:**
   - autokey on + no key → insert;
   - autokey off + no key → không insert; seek reverts;
   - chỉ đổi X → chỉ position key đổi, rotation/scale keys không đổi;
   - easing của key được giữ;
   - undo một gesture trả cả pose và key;
   - playback tại B giữ giá trị;
   - key tại 2.0001 với tolerance nửa frame → update, không tạo trùng.
4. **Manual/device:** kéo gizmo tại B, play, xem giá trị; kiểm tra không lag.

---

## 11. Renderer

### 11.1 Lựa chọn

| Giá trị | Ý nghĩa | Args |
|---|---|---|
| `auto` | Không override; resolve theo nền tảng: Android → Mobile, desktop/headless → Forward+ | — |
| `mobile` | Mobile / Vulkan — **mặc định trên Android** | `--rendering-method mobile --rendering-driver vulkan` |
| `forward_plus` | Forward+ / Vulkan | `--rendering-method forward_plus --rendering-driver vulkan` |
| `gl_compatibility` | Compatibility / OpenGL | `--rendering-method gl_compatibility --rendering-driver opengl3` |

- **Mặc định trên Android là `mobile`**, không phải `auto`. Trên desktop/headless mặc định là `forward_plus`. `auto` vẫn là lựa chọn và resolve theo nền tảng; UI hiển thị cả giá trị chọn và backend thực.
- Đổi `project.godot`:
  - `renderer/rendering_method="forward_plus"` (desktop/headless);
  - `renderer/rendering_method.mobile="mobile"` (Android mặc định Mobile, nhẹ hơn Forward+).
  - Hiện file đang đặt `.mobile="forward_plus"`; đây là thay đổi bắt buộc của bản dựng lại.
- `Gfx` default khi chưa có preference: Android → `mobile`, desktop/headless → `forward_plus`. Nếu preference đã có, giữ nguyên.
- Nếu Vulkan không khả dụng, `fallback_to_opengl3=true` hiện tại sẽ fallback; UI hiển thị backend thực (Compatibility/OpenGL) và cảnh báo. Fallback này là của backend, không phải fallback mode layout.
- Không có chuyển renderer tức thời. Không giả vờ.

### 11.2 Restart flow

1. User chọn renderer trong Settings → Graphics.
2. Nếu giống backend hiện tại: chỉ lưu preference, toast “Đã lưu”; không restart.
3. Nếu khác:
   - confirm: “Cần khởi động lại app để đổi renderer. Project sẽ được lưu.”
   - lưu project + `Prefs`/`Gfx`;
   - set `renderer_pending = requested`;
   - `OS.set_restart_on_exit(true, args)`;
   - `get_tree().quit()`.
4. Android tạo instance mới với args; app khởi động; `Gfx` đọc actual method.
5. Nếu actual == requested:
   - clear pending; toast “Renderer: Mobile”; hiển thị trong Settings/Status.
6. Nếu actual != requested:
   - thử restart một lần nữa (tối đa 1 retry) nếu pending còn;
   - nếu vẫn sai: fallback về **platform default** (Android → Mobile, desktop → Forward+), clear pending, hiện lỗi “Không thể khởi động renderer X trên thiết bị này. Đã dùng <default>.”
   - không loop vô hạn.
7. Nếu app bị kill giữa restart: lần mở sau đọc pending; thử một lần; nếu fail, fallback platform default.

- Startup apply: `Gfx.ensure_renderer()` chạy sớm (autoload `_ready`), so sánh preference với `RenderingServer.get_current_rendering_method()`. Nếu khác và preference không phải auto, schedule restart một lần. Điều này đảm bảo preference được áp dụng cả khi user mở app từ launcher, không chỉ từ restart.
- Guard: lưu timestamp/attempt count trong `user://graphics.json`; nếu 2 attempt trong 60 s, fallback **platform default** (Android → Mobile, desktop → Forward+).
- Test headless: không thể restart; test hàm `build_restart_args()`, persistence, pending guard, fallback logic. Device checklist bắt buộc.

### 11.3 Capability matrix

- Không hardcode “Mobile không có X” nếu chưa xác minh. `Gfx` cung cấp:
  - `renderer_name()`;
  - `is_forward()`;
  - `supports_environment_extras()`;
  - các hàm `supports_ssao()`, `supports_ssil()`, `supports_ssr()`, `supports_taa()`, `supports_glow()`, `supports_volumetric_fog()` — implement dựa trên renderer + thực tế engine.
- UI đọc capability và disable option với hint:
  - “Không khả dụng trên Mobile renderer.”
  - “Cần Forward+.”
- Khi đổi renderer, settings không hỗ trợ được giữ trong file nhưng không áp dụng; khi quay lại Forward+, áp dụng lại.
- Không tự bật option không hỗ trợ; không silently ignore.

### 11.4 UI

- Settings → Graphics → **Renderer**:
  - hàng `Renderer` hiển thị backend thực + nút `Change` 44 dp mở sheet Renderer;
  - segmented **Forward+ / Mobile / Compatibility**; **Mobile được chọn sẵn trên Android**; không có lựa chọn Auto giả;
  - dòng `Renderer in use` đọc trực tiếp `RenderingServer.get_current_rendering_method()`;
  - dòng `Project request` đọc `rendering/renderer/rendering_method`;
  - dòng `Driver` và `Adapter` nếu engine trả;
  - nút `Restart` 48 dp khi khác; gọi `OS.set_restart_on_exit(true, ["--rendering-method", value])` và lưu project trước;
  - ghi chú thật: nếu platform bỏ qua flag, dòng `Renderer in use` vẫn báo backend đang chạy;
  - không có dropdown nhỏ, không có reset giả, không đổi renderer tại runtime.
- Status bar/Desktop hiển thị renderer thực; HUD chỉ hiện FPS, không lặp renderer.

---

## 12. Settings catalog

Tất cả setting lưu trong `user://settings.json` (Prefs) hoặc `user://graphics.json` (Gfx). Không lưu trong project JSON trừ khi thuộc về project (duration, fps, interpolation).

### 12.1 Graphics

| Setting | Giá trị | Mặc định | API |
|---|---|---|---|
| Renderer | forward_plus/mobile/gl_compatibility | mobile (Android) / forward_plus (desktop) | restart args |
| Preset | performance/balanced/quality/custom | balanced | `Gfx.apply_preset` |
| 3D scale | 0.5–1.0 | preset | `Viewport.scaling_3d_scale` |
| MSAA | off/2x/4x/8x | 2x | `Viewport.msaa_3d` |
| TAA | on/off | off | `Viewport.use_taa` (Forward+) |
| SSAO | on/off + quality | on (Forward+) | `Environment.ssao_*` |
| SSIL | on/off | off | `Environment.ssil_*` |
| SSR | on/off | off | `Environment.ssr_*` |
| Glow | on/off + intensity | on | `Environment.glow_*` |
| Tonemap | linear/reinhard/filmic/aces | aces | `Environment.tonemap_mode` |
| Exposure | 0.25–4.0 | 1.0 | `Environment.tonemap_exposure` |
| Shadow quality | low/medium/high/ultra | medium | `RenderingServer` soft shadow quality |
| Shadow distance | 10–100 | 40 | `DirectionalLight3D.directional_shadow_max_distance` |
| Shadow splits | 1/2/4 | 2 | `DirectionalLight3D.directional_shadow_split_*` |
| Shadow atlas | 1024/2048/4096 | 2048 | `RenderingServer.directional_shadow_atlas_set_size` |
| Volumetric fog | on/off | off | `Environment.volumetric_fog_enabled` (Forward+) |
| Sky | studio/off | studio | environment sky |
| Background color | color | BG | `Environment.background_color` |

- Preset thay đổi nhiều giá trị; edit một giá trị → preset `custom`.
- Preset chip sync như hiện tại; test.
- Reset section = `Gfx.apply_preset("balanced")` + defaults.

### 12.2 Performance

| Setting | Giá trị | Mặc định |
|---|---|---|
| FPS overlay | off/compact/full | compact |
| Frame graph | on/off | off |
| Adaptive quality | on/off | on |
| Target FPS | 30/60 | 60 |
| Min preview scale | 0.5/0.6/0.75 | 0.6 |
| Preview update | on_demand/continuous | on_demand |
| Preview resolution cap | 720/1080/1280/1600/1920 | theo mode |
| Max FPS | 30/60/90/120/unlimited | 60 |
| V-Sync | on/off | on (nếu hỗ trợ) |
| Renderer info | read-only | — |
| Stats | read-only | — |
| Reset stats | action | — |

- `continuous` chỉ dành cho debug; mặc định `on_demand`.
- Nếu `continuous`, hiển thị warning “Tốn pin và GPU”.
- `max_fps` map `Engine.max_fps`; unlimited = 0.
- V-Sync ẩn nếu API không khả dụng.

### 12.3 Editor

| Setting | Giá trị | Mặc định |
|---|---|---|
| Autosave | off/15/30/60 s | 30 s |
| Confirm delete | on/off | on |
| Gizmo size | 0.75–1.5 | 1.0 |
| Translate snap | 0.1/0.25/0.5/1.0 | 0.25 |
| Rotate snap | 5/15/30/45° | 15° |
| Scale snap | 0.1/0.25/0.5 | 0.25 |
| Default interpolation | linear/cubic | cubic |
| Timeline default | dope/graph | dope |
| Show FPS in viewport | on/off | on |
| Reduce motion | on/off | off |
| Haptics | on/off | off |
| Reset editor settings | action | — |

- Snap dùng khi kéo gizmo và retime key; toggle nhanh trong timeline.
- Gizmo size map vào scale overlay/gizmo; test.
- Autosave interval map vào Timer; 0 = off.
- Confirm delete áp cho object/key/render? Chỉ object và project; key delete có thể undo nên không confirm.

### 12.4 Display

| Setting | Giá trị | Mặc định |
|---|---|---|
| Workspace layout | auto/compact/studio/desktop | auto |
| Orientation | auto/portrait/landscape | auto |
| UI scale | 0.50–2.00, step 0.01 | 1.0 |
| Safe area preview | on/off | off |
| Keep screen on | on/off | on |
| Fullscreen | on/off | off (desktop OS only) |
| Reset display | action | — |

- Workspace layout: mọi mode luôn chọn được; Desktop trên màn hình hẹp dùng shrink-to-fit, không fallback.
- [Superseded by the 2026-10-30 stage-first addendum] UI scale là scale người dùng; khi fit < 100%, control **không còn bị disable** — scale vẫn chỉnh được và fit tính riêng theo density, user scale nhân lên trên đó. Xem "Free interface scale" trong addendum stage-first shell (2026-10-30).
- Orientation chỉ hiện trên Android; nếu `FEATURE_ORIENTATION` false, disable + hint.
- Fullscreen chỉ desktop OS; Android immersive nếu API xác nhận, nếu không ẩn.
- Safe area preview vẽ inset `WARNING` 1 px + label; chỉ debug.

### 12.5 Render

| Setting | Giá trị | Mặc định |
|---|---|---|
| Output | still/sequence | still |
| Resolution | 1280/1920/2560/3840 long edge | 1920 |
| MSAA | off/2x/4x/8x | 4x |
| Transparent background | on/off | off |
| Frame range | start/end | 0..duration |
| Output folder | SAF/user://renders | user://renders |
| Filename | pattern | `<project>_<timestamp>` |
| Reset render | action | — |

- Sequence dùng project FPS; không cho FPS khác trong bản này (tránh lệch animation).
- Transparent map `Viewport.transparent_bg`; nếu probe không hỗ trợ, disable + hint.
- Render still dùng `capture_still` hiện có; sequence dùng frame-by-frame; cả hai dùng **editor camera** và aspect của preview.
- MP4 không có.

### 12.6 Import

| Setting | Giá trị | Mặc định |
|---|---|---|
| Scale | 0.01/0.1/1/10/100 | 1 |
| Import materials | on/off | on |
| Import textures | on/off | on |
| Merge by material | on/off | on (nếu hỗ trợ) |
| Reset import | action | — |

- FBX row disabled + giải thích.
- SAF note hiển thị trong sheet, không chỉ trong docs.

### 12.7 Persistence và migration

- `Prefs` autoload mới (`src/core/prefs.gd`):
  - load `user://settings.json` nếu có;
  - defaults cho key thiếu;
  - validate/clamp;
  - save atomic (temp + rename) để tránh file hỏng;
  - signal `changed(key, value)`.
- `Gfx` giữ `user://graphics.json`; thêm `renderer_preference`, `renderer_pending`, `renderer_attempt_at`.
- Project JSON giữ nguyên schema; không thêm setting vào project trừ khi thuộc project.
- Migration: file cũ thiếu key → default; file hỏng → backup `.bak`, dùng default, toast lỗi.
- Reset từng section; reset all trong About? Có, confirm.
- Không lưu dữ liệu nhạy cảm; không network.

---

## 13. Render/export và import

### 13.1 Render still thật

- Dùng `EditorView.capture_still(long_edge, msaa)` hiện có: tạo probe `SubViewport`, gắn **editor camera hiện tại** (cùng transform/FOV với preview), set resolution theo long edge, giữ aspect của preview, MSAA, `transparent_bg` nếu chọn, `UPDATE_ONCE`, đọc `Image`.
- Lưu PNG vào `user://renders/<project>/<timestamp>/<name>.png`.
- Kiểm tra sau khi ghi:
  - file tồn tại;
  - `Image.load()` thành công;
  - kích thước đúng long edge (hoặc tỉ lệ);
  - file size > 0.
- Nếu fail: xoá file dở, báo lỗi cụ thể; không toast “success” giả.
- Quick still: nút trong overflow/menu Render → render long edge 1920, aspect preview, preset hiện tại; toast + mở sheet kết quả.
- Không render UI overlay/HUD vào ảnh; chỉ 3D + environment.

### 13.2 Sequence PNG → ZIP thật

- Full range: frame count = `round(duration × fps)`, frame index 0..N-1; khớp smoke hiện tại (6 s × 24 fps = 144).
- Subrange: `start`/`end` là frame index; số frame = `end - start`; frame i có thời gian `(start + i) / fps`; không ghi frame `end` (half-open).
- Với mỗi frame:
  - set `doc.current_time = (start + i) / fps`;
  - sample animation;
  - render probe `UPDATE_ONCE`;
  - lưu PNG tạm;
  - cập nhật progress;
  - nếu cancel: dừng, xoá temp, không tạo ZIP.
- Đóng ZIP bằng `RenderExport.zip_directory()`; kiểm tra ZIP mở được và đủ số file.
- Thư mục tạm không trùng: dùng timestamp + random/sequence; đã có fix collision-free, giữ.
- Cleanup temp sau khi ZIP xong; nếu lỗi, giữ temp và báo path để debug (không tự xoá bằng chứng).
- Progress UI: `Frame 42 / 144`, bar, cancel; không block UI thread quá lâu? Render từng frame trong `await process_frame` để UI cập nhật; chấp nhận chậm hơn.
- Không cho rời editor khi đang render mà không confirm; nếu thoát, cancel + cleanup.

### 13.3 MP4

- **Không implement.** Không có encoder trong stack.
- UI ghi rõ: “MP4 không được hỗ trợ trong bản này. Xuất PNG sequence rồi encode bằng ffmpeg hoặc công cụ khác.”
- Không có nút MP4, không có progress giả, không tạo file `.mp4` rỗng.
- Nếu sau này thêm, cần encoder native/GDExtension và một spec riêng.

### 13.4 Import glTF/GLB, OBJ+MTL

- glTF/GLB: dùng `GLTFDocument`/`GLTFState` của engine; import vào scene hiện tại; copy texture vào project folder nếu cần; báo lỗi nếu parse fail.
- OBJ+MTL: parser runtime hiện có; giữ các fix:
  - tab separator;
  - `usemtl` có khoảng trắng;
  - face index bounds check;
  - material groups;
  - normals;
  - texture copy/rewrite.
- Import options: scale, materials, textures; merge by material nếu hỗ trợ.
- Sau import:
  - **một document object cho mỗi file** (đúng `add_imported()` hiện tại), không tách multi-mesh thành nhiều object;
  - chọn object đó;
  - frame vào nó;
  - một undo step;
  - toast “Imported <name>”.
- Multi-object import (mỗi mesh/material group thành object riêng) là non-goal; cần spec riêng vì thay đổi document model/outliner/undo.
- Lỗi: message cụ thể (file hỏng, thiếu MTL, texture không đọc được, định dạng không hỗ trợ); không import một nửa rồi báo success.
- Import vào project hiện tại, không tạo project mới.

### 13.5 FBX

- Binary FBX cần parser riêng; không có trong engine/GDScript thuần.
- UI: row `FBX` disabled + giải thích; nếu user chọn file FBX, hiện message “FBX nhị phân chưa được hỗ trợ. Chuyển sang glTF/GLB hoặc OBJ.”
- Không đổi đuôi, không parse bằng text, không giả success.
- ASCII FBX cũng không nằm trong scope bản này; nếu muốn, cần spec riêng.

### 13.6 SAF limitation

- Android SAF có thể trả `content://` URI; GDScript `FileAccess`/`DirAccess` có thể không đọc được sibling `.mtl`/texture.
- Giải pháp UI:
  - khuyến nghị chọn file trong thư mục app hoặc copy cả thư mục;
  - nếu chỉ đọc được file chính, import hình học và báo “Materials/textures không đọc được do giới hạn SAF”;
  - không treo, không crash.
- Render save: ưu tiên `user://renders` (luôn ghi được); xuất ra Downloads qua SAF là best-effort, phải verify trên thiết bị. Nếu fail, hiển thị path thật và hướng dẫn.
- Ghi rõ trong Help/About.

---

## 14. Home và chất lượng hình ảnh

### 14.1 Home

Đã mô tả ở 7.11. Nguyên tắc:

- Home là **project browser**, không phải landing page.
- Không hero, không card lớn, không illustration.
- Thông tin thật từ `Store`: tên, modified, object count, duration, size; template chỉ có trong New Project sheet, không lưu vào project.
- Action thật: new, open, rename, delete, search, sort.
- Empty state có một hành động.
- Không hiển thị “recent” giả nếu Store không có.

### 14.2 Visual QA

- Các kích thước dưới đây là **logical dp** với density 1.0; mode được chọn trực tiếp, không phụ thuộc `Auto`.
- Chụp screenshot tại:
  - 360×640 (phone nhỏ, Compact);
  - 411×914 (phone, Compact);
  - 360×640 (phone, **Desktop shrink-to-fit**);
  - 411×914 (phone, **Desktop shrink-to-fit**);
  - 914×411 (phone ngang, Studio);
  - 914×411 (phone ngang, **Desktop shrink-to-fit**);
  - 600×960 (tablet nhỏ, Studio);
  - 800×1280 (tablet dọc, Studio);
  - 960×600 (Desktop tối thiểu, fit 100%);
  - 1280×800 (tablet ngang, Desktop);
  - 1600×900 (desktop, Desktop).
- Mỗi ảnh kiểm:
  - không tràn/cắt;
  - top bar/bottom bar/safe area;
  - text không bị đè;
  - hit target đủ lớn;
  - màu đúng token;
  - icon cùng stroke;
  - không còn hero/card;
  - sheet mở/đóng đúng;
  - Desktop-on-phone: UI thu nhỏ đều, không cắt, indicator fit hiển thị; chữ nhỏ là tradeoff đã chấp nhận, không tính là overflow.
- Chụp sau khi hoàn thành một cụm thay đổi, không chụp sau từng pixel.
- So sánh với reference tinh thần: Godot editor (mật độ, panel, timeline) + Prisma3D (touch ergonomics), không copy pixel.

---

## 15. Chiến lược kiểm thử

### 15.1 Tầng test

| Tầng | Công cụ | Phạm vi |
|---|---|---|
| Logic/headless | `tests/smoke.gd` | document, keyframe, easing, import, render, settings |
| Layout | scene test mới `tests/layout.gd` | ma trận size × mode, Desktop fit, overflow, hit target logic |
| Interaction | headless + input events | sheet, back, mode, orientation persistence, scale |
| Visual | screenshot | token, spacing, icon, overflow |
| Performance | headless relative + device | idle update, refresh count, frame time |
| CI | GitHub Actions | build APK, package, ABI, signature, assets |

`tests/smoke.gd` tiếp tục là nguồn sự thật; test mới không thay thế nó.

### 15.2 Test keyframe (bắt buộc, TDD)

- Viết test đỏ trước, chạy thấy fail đúng lý do, rồi mới sửa.
- Assert key value, node value sau seek, playback.
- Regression cho autokey on/off, channel riêng, easing, undo.
- Đây là test đầu tiên của implementation order.

### 15.3 Test layout

Với mỗi cặp `(size, mode)`:

- mở editor với project mẫu;
- chờ 5 frame (overlay hiện tại cần 2; dùng 5 cho chắc);
- assert:
  - `editor.size` khớp viewport;
  - mọi control visible có `global_rect` nằm trong `Rect2(0,0,w,h)` với tolerance 1 px;
  - không có control visible nằm ngoài parent;
  - `topbar`/`menu bar`, `transport`, `bottom bar`/`status bar` tùy mode đều visible và không overlap;
  - sheet body scroll được; footer visible;
  - hit target của các nút chính ≥ 44 dp **logic** (đo `size` hoặc wrapper); trong Desktop fit, không assert 44 dp vật lý;
  - không có horizontal scroll ngoài ý muốn;
  - text essential không bị clip (title được phép ellipsis);
  - Desktop ở mọi size: `desktop_fit` giữ logical canvas ≥ 960×600 tại user scale 100%; mode vẫn là Desktop; fit indicator hiển thị khi < 100%;
  - Desktop trên phone: không fallback; chuyển Desktop → Compact/Studio khôi phục `content_scale_factor` và không tràn;
  - Studio/Desktop: panel rail 44 dp hiện diện khi canvas đạt sàn Studio 480 dp; dưới ngưỡng đó nút panel trên top bar thay thế. Dock mặc định đóng, viewport chiếm toàn bộ chiều rộng còn lại; timeline gập mặc định chỉ còn 56 dp transport.
- Nếu fail, in rect của control vi phạm + parent + mode + size + `content_scale_factor`.

### 15.4 Test interaction

- Mở Scene sheet; tap 5 điểm trong body; assert modal vẫn mở.
- Tap scrim; assert đóng.
- Back: modal → đóng; back lần nữa → editor/home đúng.
- Chuyển mode Auto/Compact/Studio/Desktop; assert mode hiệu dụng; Desktop trên 360×640 vẫn là Desktop với fit < 100%, không fallback; restart app (headless reload) → mode + user scale lưu.
- Đổi UI scale 0.5/1.0/1.3/2.0 trong Compact/Studio/Desktop; assert factor + không tràn hoặc clamp có thông báo. Desktop fit < 100% vẫn cho slider hoạt động và hiển thị fit.
- Orientation setting: mock `DisplayServer`? Không mock được; test persistence + UI state; device verify.
- Renderer: default trên Android là Mobile, desktop là Forward+; test `build_restart_args()`, preference persistence, pending guard; không restart trong test.
- Settings: mỗi control đổi → giá trị lưu; reload → còn; reset → default.
- Render: still PNG tồn tại, load được, đúng size; sequence ZIP đủ frame; cancel cleanup.
- Import: fixture OBJ/MTL/texture; glTF fixture nếu có; lỗi FBX message.
- Project round trip: save/load giữ object, key, easing, settings.
- Undo: một gesture = một step; key update undo đúng.

### 15.5 Test performance

- Headless:
  - idle preview `render_target_update_mode == UPDATE_ONCE` sau khi ổn định;
  - orbit → ALWAYS; kết thúc → ONCE;
  - transform drag không trigger outliner rebuild (spy counter);
  - inspector chỉ update field, không rebuild section (counter);
  - FPS overlay update 4 Hz, không mỗi frame.
- Relative benchmark: ghi lại baseline trước/sau; không dùng làm tiêu chí tuyệt đối.
- Device checklist: FPS thật, cảm giác kéo, nhiệt, pin.

### 15.6 Test visual

- Screenshot matrix như 14.2.
- Kiểm token: không hex lạ trong screen/component (grep).
- Kiểm icon: file tồn tại, cùng viewBox, stroke 1.5.
- Kiểm không còn `hero`, `card`, `border-radius` lớn trong UI mới.
- Review mắt: mật độ, alignment, hierarchy.

### 15.7 CI

- Workflow hiện tại: `assembleStandardDebug`, arm64-v8a, debug keystore, package `studio.kinema.app`.
- Artifact: `app/build/outputs/apk/standard/debug/android_debug.apk`.
- Kiểm tra:
  - APK tồn tại;
  - `aapt dump badging` package/ABI;
  - signature debug;
  - assets chứa `project.godot`, `src/`, `assets/` mới;
  - không có file test trong APK.
- Nếu có thể, thêm job headless smoke dùng Godot binary; nếu CI không có binary, ghi rõ local smoke là bắt buộc trước push.
- Không tuyên bố CI pass khi chưa thấy workflow run.

### 15.8 Tiêu chí chấp nhận

- [ ] Keyframe tại B cập nhật; playback giữ; test đỏ→xanh.
- [ ] Idle preview không render liên tục; FPS/frame graph thật.
- [ ] Không tràn ở ma trận 11 ảnh (3 mode layout, Auto resolve đúng), gồm Desktop trên phone portrait/landscape.
- [ ] Panel không đóng khi tap trong.
- [ ] Compact/Studio/Desktop luôn chọn được, lưu; Desktop hẹp thu nhỏ đều đến khi vừa, có indicator, không fallback.
- [ ] Desktop fit < 100% hiển thị tỉ lệ; chuyển mode khôi phục scale.
- [ ] Orientation setting hoạt động hoặc disable có lý do.
- [ ] UI scale 0.50–2.00 không tràn (Compact/Studio clamp có thông báo); Desktop fit < 100% vẫn cho slider hoạt động.
- [ ] Studio/Desktop: panel rail 44 dp khi đủ sàn 480 dp, dock flyout mặc định đóng, timeline gập còn 56 dp transport, viewport rộng tối đa.
- [ ] Renderer mặc định Mobile trên Android; switch Forward+/Compatibility restart thật; backend hiển thị đúng; fallback backend có thông báo.
- [ ] Settings graphics/performance/editor/display/render/import đầy đủ, lưu bền, reset.
- [ ] Render still/sequence thật, mở được; MP4 nói rõ không hỗ trợ.
- [ ] Import glTF/OBJ+MTL; FBX nói rõ không hỗ trợ.
- [ ] Home không còn hero/card; list/table dùng dữ liệu thật.
- [ ] Icon redraw, token 1 px/0 px, không emoji.
- [ ] FPS thật được đo/báo cáo trên Android 15–17; 60 fps không phải gate.
- [ ] Smoke pass; parse sạch; screenshot matrix; CI artifact (sau khi push).

---

## 16. Migration, rủi ro, device checklist

### 16.1 Migration

- Project JSON schema giữ nguyên; project cũ mở được.
- `graphics.json` cũ: thiếu key mới → default; giữ preset/giá trị cũ; thêm `renderer_preference=<platform default>` (Android: `mobile`; desktop: `forward_plus`).
- `settings.json` mới: nếu chưa có → default; nếu hỏng → backup + default + toast.
- Không đổi tên project folder/id.
- Autosave giữ 30 s; có thể đổi qua settings.
- Backup branch/commit trước khi bắt đầu; không rewrite history.

### 16.2 Rủi ro

| Rủi ro | Khả năng | Tác động | Giảm thiểu |
|---|---|---|---|
| Renderer restart không hoạt động trên thiết bị | Trung bình | Cao | Feature flag, fallback platform default, device checklist, log |
| `screen_set_orientation` không hoạt động | Trung bình | Trung bình | Disable + hint; manifest fullSensor; device test |
| Layout Godot vẫn tràn ở edge case | Cao | Cao | Test matrix, scroll, overflow menu, screenshot |
| Desktop trên điện thoại quá nhỏ để đọc/chạm | Cao | Trung bình | Indicator fit + chip `UI nhỏ` + nút chuyển Studio; không fallback tự động; tradeoff đã chốt |
| Đổi mode gây nhảy scale/oscillation | Trung bình | Trung bình | Tính fit từ `device_dp` + deterministic; test chuyển mode; lưu `user_scale` |
| Perf không đạt 60 fps trên máy yếu | Trung bình | Trung bình | Adaptive quality, preview cap, Mobile preset, on-demand; 60 fps không phải gate |
| Keyframe fix gây regression easing/undo | Thấp | Cao | TDD, regression, smoke |
| SAF không đọc được MTL/texture | Cao | Trung bình | Copy flow, message rõ, không fake |
| UI rewrite làm mất thao tác cũ | Trung bình | Cao | Smoke, feature parity checklist, incremental |
| CI build fail do asset mới | Trung bình | Cao | Stage script cập nhật, local parse, artifact check |
| Accessibility không đầy đủ | Cao | Trung bình | Contrast/touch/focus; ghi rõ giới hạn Godot |
| Thời gian lớn | Cao | Trung bình | Chia bước, commit sớm, không big-bang |

### 16.3 Device checklist (sau khi có APK)

1. Cài APK debug trên Android 15, 16 và 17 (nếu có máy); mở app; không crash.
2. Home: tạo project, mở, rename, delete, search.
3. Compact: xoay dọc; mở Scene/Properties/Add/Settings/Render; tap trong không đóng; scroll tới cuối.
4. Studio: xoay ngang; panel rail + flyout; timeline gập mặc định; short height; panel không tràn.
5. Desktop: tablet/DeX; menu bar; status bar; keyboard shortcuts. Trên điện thoại: chọn Desktop, xác nhận UI thu nhỏ đều, không fallback, indicator fit, chuyển lại Studio/Compact.
6. Keyframe: 2 key, sửa tại B, play, seek; autokey on/off; undo.
7. Performance: FPS overlay; orbit; kéo gizmo; play; idle; nhiệt/pin 5 phút. Ghi FPS thật; 60 fps không phải gate.
8. Renderer: fresh install phải là Mobile; đổi Forward+/Compatibility; restart; backend hiển thị đúng; fallback backend.
9. Orientation: Auto/Portrait/Landscape; app xoay đúng; layout reflow.
10. UI scale: 0.5/1.0/1.3/2.0; không tràn; cảnh báo dưới 85%.
11. Render: still PNG mở được; sequence ZIP đủ frame; cancel cleanup.
12. Import: OBJ+MTL từ bộ nhớ app; glTF/GLB; thử SAF; FBX message.
13. Safe area: tai thỏ/gesture bar; sheet footer không bị che.
14. Background/foreground: autosave; preview dừng; quay lại đúng state.
15. Back hierarchy: sheet → drawer → editor → home → thoát.

---

## 17. Thứ tự thực hiện

Mỗi bước: viết test trước nếu là logic/UI behavior; chạy smoke; commit; screenshot nếu là UI.

1. **Baseline + keyframe (TDD).**
   - Ghi lại baseline smoke/perf.
   - Viết test đỏ tái hiện key B.
   - Sửa `document.gd`; test xanh; regression.
   - Chưa đụng UI.
2. **Performance instrumentation + update policy.**
   - Thêm FPS/frame graph/status.
   - `UPDATE_ONCE` idle; coalesce UI; tách `transform_changed`.
   - Đo lại baseline; ghi số.
3. **Prefs + scale/orientation + layout modes.**
   - `Prefs` autoload; settings.json.
   - Scale clamp; orientation; breakpoint 600/960.
   - Layout matrix test; Desktop shrink-to-fit + indicator; không fallback.
4. **Token + icon + shell + Home.**
   - `tokens.gd`/`Kit` mới; icon redraw.
   - Top bar/rail/status; Home list/table; New project sheet.
5. **Outliner + Inspector + Timeline + sheet system.**
   - Component mới; panel behavior; transport; dope/graph.
   - Interaction tests; screenshot.
6. **Settings + renderer.**
   - Settings surfaces; graphics/performance/editor/display/render/import.
   - Renderer mặc định Mobile trên Android; restart flow; capability gating.
7. **Render/import polish + visual QA.**
   - Render sheet; sequence; import; SAF messages.
   - Screenshot matrix; fix overflow.
8. **CI + docs + final verification.**
   - Stage script; workflow; README/BUILD.
   - Smoke/parse; commit; push; CI; artifact verify.

Không làm big-bang: mỗi bước phải giữ app chạy được. Cuối bước 8, UI cũ đã được thay hoàn toàn.

---

## 18. Quyết định đã chốt và xác nhận cuối

Ba mục 18.1–18.3 đã được bạn trả lời trong hội thoại. Tài liệu đã cập nhật theo đúng câu trả lời; không còn câu hỏi mở nào trong ba mục này.

### 18.1 Desktop mode trên điện thoại — đã chốt: thu nhỏ đều

- Desktop **luôn chọn được** trên điện thoại.
- Nếu không vừa, toàn bộ UI Desktop được thu nhỏ đều cho đến khi vừa; không fallback Studio, không ẩn panel, không đổi mode.
- Cơ chế: giảm `content_scale_factor` để canvas logic đạt tối thiểu 960×600; xem 6.1 và 6.6.
- Hệ quả: chữ và vùng chạm vật lý nhỏ hơn 44 dp trên điện thoại. Bạn đã chấp nhận tradeoff này. UI hiển thị tỉ lệ fit và gợi ý chuyển mode, nhưng không tự đổi. [Superseded by the 2026-10-30 stage-first addendum] Khi fit < 100%, control UI scale **không bị disable**; fit là density-only và user scale nhân lên trên đó.

### 18.2 Renderer mặc định trên Android — đã chốt: Mobile

- Mặc định trên Android là **Mobile**; desktop/headless là Forward+.
- `Forward+`, `Mobile`, `Compatibility` chọn được; đổi bằng restart có kiểm chứng. Không có Auto giả.
- `project.godot` phải đổi `renderer/rendering_method.mobile` từ `forward_plus` sang `mobile`.
- Fallback backend (Vulkan → OpenGL) là thật và được hiển thị; không fake.

### 18.3 Thiết bị tham chiếu và mức xác minh — đã chốt: Android 15–17, 60 fps không bắt buộc

- Xác minh trên **Android 15–17** (máy cụ thể do bạn test).
- **60 fps là mục tiêu, không phải cổng chấp nhận** trên máy test. Phải đo và báo cáo FPS thật; không tuyên bố đạt 60 nếu chưa có số đo.
- Trạng thái cuối nếu chưa test đủ: “logic verified, device-unverified”; không claim cảm giác chạm/orientation/renderer restart/FPS khi chưa có thiết bị.

### 18.4 Những quyết định tôi đã tự chốt (bạn check khi đọc)

Các mục này không cần bạn trả lời; chúng đã được ghi trong doc. Nếu thấy sai, nói rõ.

- Home dạng list/table; liệt kê **tất cả project** qua `Store.list_projects()` mới; `recent_projects()` chỉ dùng để sort; không hiển thị template vì project JSON không lưu.
- 44 dp logic cho mọi hành động, kể cả Desktop; mật độ đến từ typography/padding. Desktop fit và user scale < 1.0 làm giảm kích thước vật lý; có indicator. [Superseded by the 2026-10-30 stage-first addendum] Desktop fit < 100% **không disable** UI scale control.
- Export: PNG still + PNG sequence ZIP; không MP4.
- Import: glTF/GLB + OBJ+MTL; FBX báo không hỗ trợ; một document object mỗi file.
- UI tiếng Anh; single-select; không Save As.
- Render từ **editor camera**, aspect preview; không có scene camera trong bản này.
- Inspector chỉ phơi bày property `document.gd` đã hỗ trợ: transform, material color/metallic/roughness, light type/color/energy/range, camera FOV.
- Ease preset: Hold / Ease Out / Linear / Ease In / Custom; không có Ease In Out vì transition là một scalar.
- Compact Properties sheet cao tối đa 72%, mỗi edit gọi `UPDATE_ONCE` để preview cập nhật.
- Desktop `Project → New/Open/Close` quay về Home sau khi confirm lưu; không Save As.
- `Auto` dùng **device dp**; panel policy của Studio/Compact dùng **layout width** sau scale; Desktop dùng shrink-to-fit, không dùng panel fallback.

Tài liệu đã sẵn sàng để duyệt. Nếu đồng ý, chỉ cần nói **“duyệt”**; bước tiếp theo là lập kế hoạch triển khai (writing-plans), rồi implement test-first theo thứ tự ở mục 17.

---

## 19. Phụ lục

### 19.1 File map dự kiến

| File | Vai trò |
|---|---|
| `src/ui/tokens.gd` (mới) | màu, spacing, type, radius, motion |
| `src/ui/kit.gd` | theme, font, icon, control factory |
| `src/ui/components/top_bar.gd` (mới) | top bar/menu bar |
| `src/ui/components/tool_rail.gd` (mới) | rail |
| `src/ui/components/sheet.gd` (mới) | bottom sheet/modal wrapper |
| `src/ui/components/row.gd` (mới) | setting/outliner row primitives |
| `src/ui/components/segmented.gd` (mới) | segmented control |
| `src/ui/components/number_field.gd` | giữ/refactor `num_field.gd` |
| `src/ui/outliner.gd` | rebuild |
| `src/ui/inspector.gd` | rebuild |
| `src/ui/timeline.gd` | rebuild transport/dope/graph |
| `src/app/editor.gd` | shell, mode, panels |
| `src/app/home.gd` | project browser rebuild |
| `src/app/main.gd` | safe area, scale, routing |
| `src/core/prefs.gd` (mới) | settings persistence |
| `src/core/document.gd` | keyframe fix, signal split |
| `src/core/gfx.gd` | renderer preference/capability |
| `src/viewport/editor_view.gd` | update policy, FPS, preview cap |
| `src/ui/overlay.gd` | sheet behavior |
| `tests/smoke.gd` | logic regression |
| `tests/layout.gd` (mới) | layout matrix |
| `docs/superpowers/specs/...` | tài liệu này |

### 19.2 Lệnh kiểm chứng

```bash
# Smoke
/data/data/com.termux/files/home/tools/Godot_v4.7.2-stable_linux.arm64 \
  --headless --path /root/kinema/studio res://tests/smoke.tscn

# Parse
/data/data/com.termux/files/home/tools/Godot_v4.7.2-stable_linux.arm64 \
  --headless --path /root/kinema/studio --quit-after 4
```

- Kết quả smoke phải in `SMOKE RESULT: PASS`.
- Parse không được có error.
- Screenshot lưu tại `/root/.local/share/KinemaStudio/` (hoặc thư mục harness hiện tại).

### 19.3 API notes

- `OS.set_restart_on_exit(true, args)` — restart với args; source-confirmed, device-unverified.
- `DisplayServer.screen_set_orientation(orientation, screen=-1)` — constants `SCREEN_SENSOR`, `SCREEN_PORTRAIT`, `SCREEN_LANDSCAPE`; device-unverified.
- `DisplayServer.get_display_safe_area()` — safe insets.
- `DisplayServer.screen_get_dpi()` / `screen_get_scale()` — density; OS font scale chưa xác nhận.
- `RenderingServer.get_current_rendering_method()` — backend thực. Default: Android `mobile`, desktop/headless `forward_plus`; `project.godot` phải đặt `.mobile="mobile"`.
- `Window.content_scale_factor` — scale UI; Desktop fit giảm factor để canvas logic đạt 960×600.
- `Viewport.scaling_3d_scale`, `msaa_3d`, `use_taa`, `transparent_bg`.
- `Environment` — SSAO/SSIL/SSR/glow/tonemap/volumetric fog; capability-gated.
- `Performance` — FPS/frame time/draw calls.
- `OS.set_restart_on_exit` path: `Main::cleanup` → `OS_Android::create_instance` → `onNewGodotInstanceRequested`.

### 19.4 Glossary

- **dp:** density-independent pixel; UI unit.
- **device dp:** `physical px / density`; dùng cho `Auto` chọn mode.
- **layout width:** chiều rộng logic sau `content_scale_factor`; dùng cho panel policy của Studio/Compact.
- **Desktop fit:** tỉ lệ thu nhỏ đều của toàn bộ UI Desktop khi canvas logic không đạt 960×600; không phải fallback mode.
- **Compact/Studio/Desktop:** ba mode layout.
- **Autokey:** chế độ tự tạo key khi transform đổi.
- **Unkeyed:** thay đổi pose chưa có key tại playhead.
- **Preview:** SubViewport 3D trong editor.
- **Probe viewport:** SubViewport tạm dùng để render still/sequence.
- **Capability:** khả năng thật của renderer/backend, kiểm tra runtime.
- **SAF:** Android Storage Access Framework.
- **CI:** GitHub Actions build.

---

*Hết tài liệu. Trạng thái: chờ duyệt lần cuối. Sau khi duyệt, bước tiếp theo là lập kế hoạch triển khai (writing-plans), rồi implement test-first theo thứ tự ở mục 17.*
