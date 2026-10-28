extends Node
## Media workstream suite: audio tracks, video-reference proxies, GIF encoding,
## sequence rendering, camera tracks and the Android MP4 facade.
##
## Runs headless on Linux. Everything that needs a real GPU or the Android
## MediaCodec backend is asserted through an explicit unavailable reason or a
## capture spy; no device-only claim is made here.

const DocumentScript = preload("res://src/core/document.gd")
const AudioLibrary = preload("res://src/core/audio_library.gd")
const VideoReference = preload("res://src/core/video_reference.gd")
const GifEncoder = preload("res://src/core/gif_encoder.gd")
const SequenceRenderer = preload("res://src/core/sequence_renderer.gd")
const CameraExport = preload("res://src/core/camera_export.gd")
const AndroidVideo = preload("res://src/core/android_video.gd")
const MediaLanes = preload("res://src/ui/media_lanes.gd")
const AudioSheet = preload("res://src/ui/audio_sheet.gd")
const VideoReferencePanel = preload("res://src/ui/video_reference_panel.gd")
const MediaExportSheet = preload("res://src/ui/media_export_sheet.gd")
const MediaImportSheet = preload("res://src/ui/media_import_sheet.gd")

const PROJECT_DIR := "user://media_ws_b_project"
const FIXTURE_DIR := "user://media_ws_b_fixtures"

var _failures: Array[String] = []
var _oks := 0
var _doc


func _check(condition: bool, message: String) -> void:
	if condition:
		_oks += 1
		print("MEDIA OK: " + message)
	else:
		_failures.append(message)
		printerr("MEDIA FAIL: " + message)


func _near(a: float, b: float, epsilon: float = 0.0001) -> bool:
	return absf(a - b) <= epsilon


func _ready() -> void:
	await get_tree().process_frame
	_remove_tree(PROJECT_DIR)
	_remove_tree(FIXTURE_DIR)
	DirAccess.make_dir_recursive_absolute(FIXTURE_DIR)
	DirAccess.make_dir_recursive_absolute(PROJECT_DIR)
	_doc = DocumentScript.new()
	add_child(_doc)
	_doc.new_project("Media WS-B")
	_doc.project_dir = PROJECT_DIR

	await _test_audio()
	await _test_video()
	await _test_video_cache()
	await _test_gif()
	await _test_render_and_camera()
	await _test_android_backend()
	await _test_ui()

	var status := "PASS" if _failures.is_empty() else "FAIL"
	print("MEDIA RESULT: %s (%d OK, %d FAIL)" % [status, _oks, _failures.size()])
	if not _failures.is_empty():
		for failure in _failures:
			printerr("  - " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


# -------------------------------------------------------------------------
# Audio
# -------------------------------------------------------------------------

func _test_audio() -> void:
	print("MEDIA STEP: audio library and tracks")
	var source := FIXTURE_DIR.path_join("footsteps.wav")
	_write_wav(source, 44100, 1, 1.0, 220.0)
	var imported: Dictionary = _doc.media_system.import_audio(source)
	_check(bool(imported.get("ok", false)), "WAV import succeeds")
	_check(str(imported.get("rel_path", "")).begins_with("audio/"), "WAV is copied into the project audio folder")
	_check(FileAccess.file_exists(PROJECT_DIR.path_join(str(imported.get("rel_path", "")))), "copied WAV exists on disk")
	_check(_near(float(imported.get("duration", 0.0)), 1.0, 0.01), "imported WAV duration is read from PCM")

	var track_id: String = _doc.media_system.add_audio_track(str(imported.get("rel_path", "")), 1.0)
	_check(track_id != "", "add_audio_track returns an id")
	var tracks: Array = _doc.media_system.audio_tracks()
	_check(tracks.size() == 1, "one audio track is stored")
	var track: Dictionary = tracks[0]
	_check(str(track.get("id", "")) == track_id, "stored track keeps its id")
	_check(_near(float(track.get("start", -1.0)), 1.0), "track start is stored")
	_check(_near(float(track.get("trim_start", -1.0)), 0.0), "track trim_start defaults to zero")
	_check(_near(float(track.get("trim_end", -1.0)), 1.0, 0.01), "track trim_end defaults to the source duration")
	_check(_near(float(track.get("volume", -1.0)), 1.0), "track volume defaults to unity")
	_check(bool(track.get("muted", true)) == false, "track is not muted by default")
	_check(_near(float(track.get("fade_in", -1.0)), 0.0), "fade_in defaults to zero")
	_check(_near(float(track.get("fade_out", -1.0)), 0.0), "fade_out defaults to zero")

	_doc.media_system.update_audio_track(track_id, {
		"trim_start": 0.25,
		"trim_end": 0.75,
		"volume": 0.8,
		"fade_in": 0.2,
		"fade_out": 0.2,
	})
	track = _doc.media_system.audio_tracks()[0]
	_check(_near(float(track.get("trim_start", -1.0)), 0.25), "trim_start update is stored")
	_check(_near(float(track.get("trim_end", -1.0)), 0.75), "trim_end update is stored")
	_check(_near(float(track.get("volume", -1.0)), 0.8), "volume update is stored")

	var data: Dictionary = _doc.media_system.to_data()
	var media: Dictionary = data.get("media", {})
	_check(media.has("audio"), "to_data returns the media key Document extracts")
	var serialized: Array = media.get("audio", [])
	_check(serialized.size() == 1, "audio track is serialized")
	var serialized_track: Dictionary = serialized[0]
	for key in ["start", "trim_start", "trim_end", "volume", "muted", "fade_in", "fade_out"]:
		_check(serialized_track.has(key), "serialized track has " + key)

	_check(_near(_doc.media_system.audio_offset(track, 1.5), 0.75), "playback offset is sequence_time - start + trim_start")
	_check(bool(_doc.media_system.audio_active(track, 1.25)), "track is active inside its trimmed window")
	_check(not bool(_doc.media_system.audio_active(track, 0.9)), "track is inactive before start")
	_check(not bool(_doc.media_system.audio_active(track, 1.6)), "track is inactive after trim_end")
	_check(_near(_doc.media_system.audio_volume_at(track, 1.0), 0.0), "fade_in starts at silence")
	_check(_near(_doc.media_system.audio_volume_at(track, 1.1), 0.4, 0.01), "fade_in smoothstep is half way at half the fade")
	_check(_near(_doc.media_system.audio_volume_at(track, 1.25), 0.8, 0.01), "volume is applied between fades")
	_check(_near(_doc.media_system.audio_volume_at(track, 1.4), 0.4, 0.01), "fade_out smoothstep is half way at half the fade")
	_check(_near(_doc.media_system.audio_volume_at(track, 1.5), 0.0), "fade_out ends at silence")
	_doc.media_system.update_audio_track(track_id, {"muted": true})
	track = _doc.media_system.audio_tracks()[0]
	_check(_near(_doc.media_system.audio_volume_at(track, 1.25), 0.0), "muted track is silent")
	_doc.media_system.update_audio_track(track_id, {"muted": false})
	track = _doc.media_system.audio_tracks()[0]

	var mix_path := FIXTURE_DIR.path_join("mix.wav")
	var mixed: Dictionary = _doc.media_system.mix_wav(mix_path)
	_check(bool(mixed.get("ok", false)), "WAV mixdown succeeds with WAV sources")
	_check(_valid_wav(mix_path), "WAV mixdown writes a valid RIFF/WAVE header")
	_check(int(mixed.get("sample_rate", 0)) == 44100, "WAV mixdown uses 44.1 kHz")

	_doc.media_system.update_audio_track(track_id, {"file": "audio/other.ogg"})
	var refused: Dictionary = _doc.media_system.mix_wav(FIXTURE_DIR.path_join("refused.wav"))
	_check(not bool(refused.get("ok", true)), "WAV mixdown refuses non-WAV sources")
	_check(str(refused.get("error", "")) == "WAV mixdown needs WAV sources; MP4 export decodes other formats in the Android backend.", "mixdown refusal uses the exact reason")
	_doc.media_system.update_audio_track(track_id, {"file": str(imported.get("rel_path", ""))})

	var waveform: Dictionary = AudioLibrary.waveform_peaks(PROJECT_DIR.path_join(str(imported.get("rel_path", ""))))
	_check(bool(waveform.get("ok", false)), "WAV waveform peaks are available")
	_check(Array(waveform.get("peaks", [])).size() > 0, "WAV waveform cache contains buckets")

	# Transport regression: pause must really pause, and play must clear the
	# paused flag instead of only seeking a paused player.
	_check(_doc.media_system.has_method("audio_player"), "media system exposes its AudioStreamPlayer")
	if _doc.media_system.has_method("audio_player"):
		var player: AudioStreamPlayer = _doc.media_system.audio_player(track_id)
		_check(player != null, "audio track has a real AudioStreamPlayer")
		if player != null:
			_doc.media_system.play_sequence(1.0)
			_check(player.playing and not player.stream_paused, "play_sequence starts an unpaused player")
			_check(_near(player.get_playback_position(), 0.25, 0.12), "play_sequence starts at the trimmed offset")
			_doc.media_system.pause_sequence()
			_check(player.stream_paused, "pause_sequence sets stream_paused")
			_doc.media_system.play_sequence(1.0)
			_check(player.playing and not player.stream_paused, "play after pause clears stream_paused")
			_doc.media_system.stop_sequence()
			_check(not player.playing, "stop_sequence stops the player")

	_doc.media_system.delete_audio_track(track_id)
	_check(_doc.media_system.audio_tracks().is_empty(), "delete_audio_track removes the track")


# -------------------------------------------------------------------------
# Video reference
# -------------------------------------------------------------------------

func _test_video() -> void:
	print("MEDIA STEP: video reference proxies")
	var ref_dir := PROJECT_DIR.path_join("video_refs").path_join("ref_1")
	var frames_dir := ref_dir.path_join("frames")
	DirAccess.make_dir_recursive_absolute(frames_dir)
	var names: Array = []
	for index in range(5):
		var name := "frame_%06d.jpg" % (index + 1)
		_make_jpeg(frames_dir.path_join(name), Color(0.1 + index * 0.15, 0.2, 0.2))
		names.append(name)
	var manifest := {
		"version": 1,
		"fps": 2,
		"duration": 2.5,
		"width": 16,
		"height": 16,
		"frames": names,
	}
	_write_json(ref_dir.path_join("reference.json"), manifest)
	var loaded := VideoReference.load_manifest(PROJECT_DIR, "video_refs/ref_1")
	_check(bool(loaded.get("ok", false)), "reference.json loads")
	_check(int(loaded.get("manifest", {}).get("fps", 0)) == 2, "reference fps is read")
	_check(Array(loaded.get("manifest", {}).get("frames", [])).size() == 5, "reference frame list is read")

	_doc.media_system.load_data({
		"media": {
			"audio": [],
			"video_refs": [{
				"id": "ref_1",
				"name": "Walk reference",
				"dir": "video_refs/ref_1",
				"fps": 2,
				"duration": 2.5,
				"width": 16,
				"height": 16,
			}],
		},
	}, PROJECT_DIR)
	var refs: Array = _doc.media_system.video_references()
	_check(refs.size() == 1, "video reference is loaded")
	var ref: Dictionary = refs[0]
	_check(_near(float(ref.get("start", -1.0)), 0.0), "video start defaults to zero")
	_check(_near(float(ref.get("opacity", -1.0)), 0.5), "video opacity defaults to 0.5")
	_check(str(ref.get("fit", "")) == "contain", "video fit defaults to contain")
	_check(Array(ref.get("offset", [])).size() == 2, "video offset defaults to a two-axis value")
	_check(_near(float(ref.get("scale", -1.0)), 1.0), "video scale defaults to one")
	_check(bool(ref.get("flip_h", true)) == false, "video flip_h defaults to false")
	_check(bool(ref.get("visible", false)) == true, "video visible defaults to true")

	_check(VideoReference.frame_index(0.0, 2, 5) == 0, "frame index starts at zero")
	_check(VideoReference.frame_index(0.6, 2, 5) == 1, "frame index is floor(time * fps)")
	_check(VideoReference.frame_index(-1.0, 2, 5) == 0, "frame index clamps at the start")
	_check(VideoReference.frame_index(99.0, 2, 5) == 4, "frame index clamps at the end")
	var first: Image = _doc.media_system.frame_for_time("ref_1", 0.0)
	var third: Image = _doc.media_system.frame_for_time("ref_1", 1.1)
	var last: Image = _doc.media_system.frame_for_time("ref_1", 99.0)
	_check(first != null and first.get_width() == 16, "frame_for_time returns a decoded frame")
	_check(third != null and third.get_pixel(0, 0).r > first.get_pixel(0, 0).r, "frame_for_time advances through the proxy")
	_check(last != null and last.get_pixel(0, 0).r > third.get_pixel(0, 0).r, "frame_for_time clamps to the last frame")

	var fake := FakeDoc.new()
	fake.project_dir = PROJECT_DIR
	add_child(fake)
	_doc.media_system.setup(fake)
	_check(_doc.media_system.preview_frame_index("ref_1") == 3, "clip preview maps strip.start + current_time")
	fake.animation_system.strip = {}
	_check(_doc.media_system.preview_frame_index("ref_1") == 0, "clip preview falls back to frame zero without a strip")
	fake.queue_free()
	_doc.media_system.setup(_doc)

	var dummy := FileAccess.open(FIXTURE_DIR.path_join("clip.mp4"), FileAccess.WRITE)
	dummy.store_string("not a real mp4")
	dummy.close()
	var unsupported: Dictionary = _doc.media_system.import_video_reference(FIXTURE_DIR.path_join("clip.mp4"))
	_check(not bool(unsupported.get("ok", true)), "MP4 reference import is unavailable on Linux")
	_check(str(unsupported.get("error", "")).contains("Android"), "MP4 reference refusal names the Android backend")
	_check(VideoReference.source_kind("clip.ogv") == "ogv", "OGV is recognised as a direct-play reference")
	_check(_doc.media_system.has_method("proxy_options"), "media system exposes proxy options")
	if _doc.media_system.has_method("proxy_options"):
		var proxy: Dictionary = _doc.media_system.proxy_options({"fps": 24, "max_width": 640})
		_check(int(proxy.get("fps", 0)) == 24 and int(proxy.get("max_width", 0)) == 640, "proxy options honour the import sheet")
		var clamped: Dictionary = _doc.media_system.proxy_options({"fps": 60, "max_width": 99999})
		_check(int(clamped.get("fps", 0)) == 12, "unsupported proxy fps falls back to 12")
		_check(int(clamped.get("max_width", 0)) == 1920, "proxy width clamps to the largest preset")
		var custom: Dictionary = _doc.media_system.import_video_reference(FIXTURE_DIR.path_join("clip.mp4"), {"fps": 24, "max_width": 640})
		_check(str(custom.get("error", "")).contains("Android"), "proxy import accepts explicit fps and width options")

	_check(str(_doc.media_system.delete_confirm_text("ref_1")).contains("cannot be undone"), "video delete exposes confirm metadata")
	_doc.media_system.delete_video_reference("ref_1")
	_check(_doc.media_system.video_references().is_empty(), "delete_video_reference removes the record")
	_check(not DirAccess.dir_exists_absolute(ref_dir), "delete_video_reference removes the proxy directory")


func _test_video_cache() -> void:
	print("MEDIA STEP: video frame and manifest caches")
	var ref_dir := PROJECT_DIR.path_join("video_refs").path_join("cache_ref")
	var frames_dir := ref_dir.path_join("frames")
	DirAccess.make_dir_recursive_absolute(frames_dir)
	var names: Array = []
	for index in range(16):
		var name := "frame_%06d.jpg" % (index + 1)
		_make_jpeg(frames_dir.path_join(name), Color(float(index) / 16.0, 0.3, 0.3))
		names.append(name)
	_write_json(ref_dir.path_join("reference.json"), {
		"version": 1, "fps": 8, "duration": 2.0, "width": 8, "height": 8, "frames": names,
	})
	_doc.media_system.load_data({"media": {"audio": [], "video_refs": [{
		"id": "cache_ref", "name": "Cache reference", "dir": "video_refs/cache_ref",
		"fps": 8, "duration": 2.0, "width": 8, "height": 8,
	}]}}, PROJECT_DIR)
	_check(_doc.media_system.has_method("frame_cache_size"), "media system exposes its decoded-frame cache size")
	var first: Image = _doc.media_system.frame_for_time("cache_ref", 0.0)
	_check(first != null, "cache reference decodes its first frame")

	# Rewrite the manifest behind the cache. Until the reference is updated the
	# cached manifest must keep serving the original frame count.
	_write_json(ref_dir.path_join("reference.json"), {
		"version": 1, "fps": 8, "duration": 2.0, "width": 8, "height": 8, "frames": [names[0]],
	})
	_check(_doc.media_system.video_frame_index("cache_ref", 99.0) == 15, "manifest is cached instead of re-read per frame")
	_doc.media_system.update_video_reference("cache_ref", {"opacity": 0.6})
	_check(_doc.media_system.video_frame_index("cache_ref", 99.0) == 0, "manifest cache invalidates on update")

	_write_json(ref_dir.path_join("reference.json"), {
		"version": 1, "fps": 8, "duration": 2.0, "width": 8, "height": 8, "frames": names,
	})
	_doc.media_system.update_video_reference("cache_ref", {"opacity": 0.7})
	for index in range(16):
		_doc.media_system.frame_for_time("cache_ref", float(index) / 8.0)
	if _doc.media_system.has_method("frame_cache_size"):
		_check(_doc.media_system.frame_cache_size() > 0, "decoded frames are cached")
		_check(_doc.media_system.frame_cache_size() <= 12, "decoded-frame cache is capped")
	_doc.media_system.delete_video_reference("cache_ref")


class FakeAnimation:
	extends RefCounted
	var strip: Dictionary = {"start": 0.5}
	func strip_at(_time: float) -> Dictionary:
		return strip


class FakeDoc:
	extends Node
	var current_time := 1.0
	var project_dir := ""
	var animation_system = FakeAnimation.new()
	func sequence_time() -> float:
		return current_time


# -------------------------------------------------------------------------
# GIF encoder
# -------------------------------------------------------------------------

func _test_gif() -> void:
	print("MEDIA STEP: GIF encoder")
	var frames: Array = []
	for index in range(3):
		var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.1 + index * 0.3, 0.2, 0.3, 1.0))
		if index == 2:
			image.set_pixel(0, 0, Color(0, 0, 0, 0))
		frames.append(image)
	_check(GifEncoder.can_encode(12), "GIF accepts 12 fps")
	_check(GifEncoder.can_encode(24), "GIF accepts 24 fps")
	_check(GifEncoder.can_encode(30), "GIF accepts 30 fps")
	_check(not GifEncoder.can_encode(60), "GIF rejects 60 fps")
	_check(GifEncoder.unsupported_reason(60) == "GIF timing is centisecond-based; 60 fps cannot be represented", "GIF 60 fps refusal uses the exact reason")
	_check(GifEncoder.encode(frames, 60, true).is_empty(), "GIF 60 fps encodes no file")
	_check(GifEncoder.widths() == [320, 480, 640, 720], "GIF width presets are exact")
	_check(GifEncoder.height_for_width(320) == 180, "GIF 320 keeps 16:9")
	_check(GifEncoder.height_for_width(720) == 406, "GIF odd heights round to an even number")

	var bytes: PackedByteArray = GifEncoder.encode(frames, 24, true)
	_check(bytes.size() > 0, "GIF encode returns bytes")
	_check(bytes.slice(0, 6).get_string_from_ascii() == "GIF89a", "GIF header is GIF89a")
	_check(bytes.decode_u16(6) == 16 and bytes.decode_u16(8) == 16, "GIF logical screen size matches the frames")
	_check(_index_of(bytes, "NETSCAPE2.0".to_ascii_buffer()) >= 0, "GIF has the NETSCAPE loop extension")
	_check(bytes[bytes.size() - 1] == 0x3B, "GIF ends with the trailer byte")
	var parsed := _parse_gif(bytes)
	_check(int(parsed.get("frames", 0)) == 3, "GIF contains three image frames")
	var delays: Array = parsed.get("delays", [])
	_check(delays == [4, 4, 5], "GIF delays use the centisecond accumulator")
	_check(Array(parsed.get("disposals", [])) == [1, 1, 1], "GIF frames use disposal method 1")

	var once_bytes: PackedByteArray = GifEncoder.encode(frames, 24, false)
	_check(_index_of(once_bytes, "NETSCAPE2.0".to_ascii_buffer()) < 0, "GIF loop=false omits the NETSCAPE loop extension")

	var transparent := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	transparent.fill(Color(1, 1, 1, 0))
	var opaque_black := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	opaque_black.fill(Color(0, 0, 0, 1))
	var opaque_white := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	opaque_white.fill(Color(1, 1, 1, 1))
	var transparent_bytes: PackedByteArray = GifEncoder.encode([transparent], 12, true)
	var black_bytes: PackedByteArray = GifEncoder.encode([opaque_black], 12, true)
	var white_bytes: PackedByteArray = GifEncoder.encode([opaque_white], 12, true)
	_check(transparent_bytes == black_bytes, "GIF alpha below 0.5 composites to the background")
	_check(transparent_bytes != white_bytes, "GIF alpha is not silently treated as opaque")

	var long_frames: Array = []
	for index in range(30):
		var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(Color(float(index) / 30.0, 0.4, 0.4, 1.0))
		long_frames.append(image)
	var long_bytes: PackedByteArray = GifEncoder.encode(long_frames, 24, true)
	var long_delays: Array = _parse_gif(long_bytes).get("delays", [])
	var total := 0
	for delay in long_delays:
		total += int(delay)
	var average := float(total) / maxf(1.0, float(long_delays.size()))
	var nominal := 100.0 / 24.0
	_check(absf(average - nominal) <= nominal * 0.005, "GIF average delay is within 0.5% of nominal over a full second")


func _parse_gif(bytes: PackedByteArray) -> Dictionary:
	var frames := 0
	var delays: Array = []
	var disposals: Array = []
	var index := 13
	if bytes.size() < 14:
		return {"frames": 0, "delays": delays, "disposals": disposals}
	var packed := bytes[10]
	if packed & 0x80:
		index += 3 * (1 << ((packed & 0x07) + 1))
	while index < bytes.size():
		var marker := bytes[index]
		if marker == 0x3B:
			break
		if marker == 0x21:
			index += 1
			if index >= bytes.size():
				break
			var label := bytes[index]
			index += 1
			if label == 0xF9:
				var size := bytes[index]
				index += 1
				if size >= 4:
					delays.append(bytes.decode_u16(index + 1))
					disposals.append((bytes[index] >> 2) & 0x07)
				index += size
				index += 1
			else:
				index = _skip_sub_blocks(bytes, index)
		elif marker == 0x2C:
			frames += 1
			index += 1
			if index + 9 > bytes.size():
				break
			var image_packed := bytes[index + 8]
			index += 9
			if image_packed & 0x80:
				index += 3 * (1 << ((image_packed & 0x07) + 1))
			index += 1
			index = _skip_sub_blocks(bytes, index)
		else:
			break
	return {"frames": frames, "delays": delays, "disposals": disposals}


func _skip_sub_blocks(bytes: PackedByteArray, index: int) -> int:
	while index < bytes.size():
		var size := bytes[index]
		index += 1
		if size == 0:
			break
		index += size
	return index


func _index_of(haystack: PackedByteArray, needle: PackedByteArray) -> int:
	if needle.is_empty() or haystack.size() < needle.size():
		return -1
	for index in range(haystack.size() - needle.size() + 1):
		var matched := true
		for offset in range(needle.size()):
			if haystack[index + offset] != needle[offset]:
				matched = false
				break
		if matched:
			return index
	return -1


# -------------------------------------------------------------------------
# Sequence renderer and camera export
# -------------------------------------------------------------------------

func _test_render_and_camera() -> void:
	print("MEDIA STEP: sequence renderer and camera export")
	var view := FakeView.new()
	add_child(view)
	var renderer = SequenceRenderer.new()
	renderer.setup(_doc, view)
	var out_dir := FIXTURE_DIR.path_join("render_64")
	var result: Dictionary = await renderer.render({
		"width": 64,
		"height": 64,
		"fps": 24,
		"start": 0.0,
		"end": 0.125,
		"frame_count": 3,
		"output_dir": out_dir,
	})
	_check(bool(result.get("ok", false)), "sequence renderer completes")
	_check(int(result.get("frame_count", 0)) == 3, "sequence renderer reports three frames")
	_check(not bool(result.get("cancelled", true)), "sequence renderer is not cancelled")
	var files := _files(out_dir)
	_check(files.size() == 3, "sequence renderer writes three PNG files")
	_check(files.has("frame_0001.png") and files.has("frame_0003.png"), "sequence renderer numbers frames from one")
	var first := Image.new()
	var load_err := first.load(out_dir.path_join("frame_0001.png"))
	_check(load_err == OK, "rendered PNG opens")
	_check(first.get_width() == 64 and first.get_height() == 64, "rendered PNG has the exact requested size")
	_check(view.sizes.size() == 3 and view.sizes[0] == Vector2i(64, 64), "renderer passes the exact size to capture_with_camera")

	var cancel_dir := FIXTURE_DIR.path_join("render_cancelled")
	var spy := CancelSpy.new()
	var cancelled: Dictionary = await renderer.render({
		"width": 64,
		"height": 64,
		"fps": 24,
		"start": 0.0,
		"end": 0.5,
		"frame_count": 8,
		"output_dir": cancel_dir,
	}, Callable(), spy.should_cancel)
	_check(not bool(cancelled.get("ok", true)), "cancelled render reports failure")
	_check(bool(cancelled.get("cancelled", false)), "cancelled render reports cancellation")
	_check(not DirAccess.dir_exists_absolute(cancel_dir), "cancelled render leaves no final output")

	var transport := TransportSpyDoc.new()
	add_child(transport)
	transport.playing = true
	transport.time = 0.5
	var transport_renderer = SequenceRenderer.new()
	transport_renderer.setup(transport, view)
	var transport_dir := FIXTURE_DIR.path_join("render_transport")
	var transport_result: Dictionary = await transport_renderer.render({
		"width": 32,
		"height": 32,
		"fps": 12,
		"start": 0.0,
		"end": 0.2,
		"frame_count": 2,
		"output_dir": transport_dir,
	})
	_check(bool(transport_result.get("ok", false)), "transport-spy render completes")
	_check(transport.pause_calls == 1, "renderer pauses the sequence clock before exporting")
	_check(transport.play_calls == 1, "renderer restores the sequence clock after exporting")
	_check(transport.playing, "renderer leaves a previously playing sequence playing")

	for size in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		view.sizes.clear()
		var exact_dir := FIXTURE_DIR.path_join("exact_%dx%d" % [size.x, size.y])
		var exact: Dictionary = await renderer.render({
			"width": size.x,
			"height": size.y,
			"fps": 12,
			"start": 0.0,
			"end": 1.0 / 12.0,
			"frame_count": 1,
			"output_dir": exact_dir,
		})
		_check(bool(exact.get("ok", false)), "exact-size render completes for %dx%d" % [size.x, size.y])
		_check(view.sizes.size() == 1 and view.sizes[0] == size, "capture spy receives the exact %dx%d size" % [size.x, size.y])
		var image := Image.new()
		image.load(exact_dir.path_join("frame_0001.png"))
		_check(image.get_width() == size.x and image.get_height() == size.y, "PNG is exactly %dx%d with no crop or letterbox" % [size.x, size.y])

	var camera_id: String = _doc.add_camera(Vector3(1.0, 2.0, 3.0))
	_doc.set_object_transform(camera_id, Vector3(1.0, 2.0, 3.0), Quaternion(Vector3.UP, 0.5), Vector3.ONE, false)
	_doc.set_camera_fov(camera_id, 46.0)
	var exporter = CameraExport.new()
	exporter.setup(_doc)
	var camera_path := FIXTURE_DIR.path_join("camera.json")
	var exported: Dictionary = await exporter.export(camera_path, camera_id, 24, 1.0)
	_check(bool(exported.get("ok", false)), "camera track exports")
	_check(FileAccess.file_exists(camera_path), "camera JSON exists")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(camera_path))
	_check(parsed is Dictionary, "camera JSON parses")
	var track: Dictionary = parsed
	_check(int(track.get("version", 0)) == 1, "camera JSON version is one")
	_check(int(track.get("fps", 0)) == 24, "camera JSON fps matches")
	_check(_near(float(track.get("duration", 0.0)), 1.0), "camera JSON duration matches")
	_check(_near(float(track.get("fov", 0.0)), 46.0), "camera JSON keeps the static fov")
	var frames: Array = track.get("frames", [])
	_check(frames.size() == 24, "camera JSON frame count matches fps x duration")
	var first_frame: Dictionary = frames[0]
	_check(Array(first_frame.get("position", [])).size() == 3, "camera frame has a position")
	_check(Array(first_frame.get("rotation", [])).size() == 4, "camera frame has a quaternion rotation")
	var position: Array = first_frame.get("position", [])
	_check(_near(float(position[0]), 1.0) and _near(float(position[1]), 2.0) and _near(float(position[2]), 3.0), "camera position roundtrips")
	var rotation: Array = first_frame.get("rotation", [])
	var quat := Quaternion(float(rotation[0]), float(rotation[1]), float(rotation[2]), float(rotation[3]))
	var expected := Quaternion(Vector3.UP, 0.5)
	_check(absf(quat.dot(expected)) > 0.999, "camera rotation roundtrips")

	transport.reset_transport()
	transport.playing = true
	transport.time = 0.5
	var spy_exporter = CameraExport.new()
	spy_exporter.setup(transport)
	var spy_camera_path := FIXTURE_DIR.path_join("camera_spy.json")
	var spy_exported: Dictionary = await spy_exporter.export(spy_camera_path, "cam", 12, 0.5)
	_check(bool(spy_exported.get("ok", false)), "camera export with a transport spy completes")
	_check(transport.pause_calls == 1, "camera export pauses the sequence clock")
	_check(transport.play_calls == 1, "camera export restores the sequence clock")
	_check(transport.playing, "camera export leaves a playing sequence playing")
	_check(_near(transport.time, 0.5), "camera export restores the original sequence time")


class FakeView:
	extends Node
	var sizes: Array[Vector2i] = []

	func capture_with_camera(size: Vector2i, _msaa: int, _xform: Transform3D, _fov: float, _transparent_bg := false) -> Image:
		sizes.append(size)
		var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.2, 0.2, 0.2, 1.0))
		return image


class CancelSpy:
	var calls := 0
	func should_cancel() -> bool:
		calls += 1
		return calls >= 2


class TransportSpyDoc:
	extends Node
	var playing := false
	var time := 0.0
	var current_time := 0.0
	var pause_calls := 0
	var play_calls := 0
	var seek_calls := 0
	var rig_system = null
	var objects: Array = [{"id": "cam", "kind": "camera", "name": "Spy camera", "camera_fov": 45.0}]
	var nodes: Dictionary = {"cam": Node3D.new()}

	func sequence_time() -> float:
		return time

	func seek_sequence(value: float, _silent := true) -> void:
		time = value
		seek_calls += 1

	func play_sequence() -> void:
		playing = true
		play_calls += 1

	func pause_sequence() -> void:
		playing = false
		pause_calls += 1

	func is_sequence_playing() -> bool:
		return playing

	func get_object(id: String) -> Dictionary:
		for obj in objects:
			if str(obj.get("id", "")) == id:
				return obj
		return {}

	func reset_transport() -> void:
		pause_calls = 0
		play_calls = 0
		seek_calls = 0


# -------------------------------------------------------------------------
# Android MP4 backend
# -------------------------------------------------------------------------

func _test_android_backend() -> void:
	print("MEDIA STEP: Android MP4 backend")
	var backend = AndroidVideo.new()
	_check(not backend.available(), "MP4 backend is unavailable on Linux")
	_check(backend.reason() == AndroidVideo.REASON, "MP4 refusal uses the exact reason")
	_check(backend.reason() == "MP4 encoding uses the Android MediaCodec backend. Build the Android APK to export MP4.", "MP4 reason text is exact")
	var capabilities: Dictionary = backend.capabilities()
	_check(not bool(capabilities.get("supported", true)), "capabilities report unsupported on Linux")
	_check(str(capabilities.get("reason", "")) == AndroidVideo.REASON, "capabilities carry the same reason")

	var manifest: Dictionary = backend.build_manifest({
		"width": 1920,
		"height": 1080,
		"fps": 24,
		"start": 0.0,
		"end": 6.0,
		"bitrate": 12000000,
		"frame_dir": "/tmp/frames",
		"frame_pattern": "frame_%04d.png",
		"audio": [
			{"file": "/tmp/a.wav", "start": 0.0, "trim_start": 0.0, "trim_end": 4.0, "volume": 0.8, "fade_in": 0.1, "fade_out": 0.2},
			{"file": "/tmp/b.wav", "start": 1.0, "trim_start": 0.5, "trim_end": 3.0, "volume": 1.0, "fade_in": 0.0, "fade_out": 0.0},
		],
	})
	_check(int(manifest.get("frameCount", 0)) == 144, "manifest frame count is range x fps")
	_check(str(manifest.get("framePattern", "")) == "frame_%04d.png", "manifest keeps the frame pattern")
	_check(Array(manifest.get("audio", [])).size() == 2, "manifest keeps both audio entries")
	var audio_entry: Dictionary = Array(manifest.get("audio", []))[0]
	_check(audio_entry.has("trimStart") and audio_entry.has("fadeIn"), "manifest uses the Java camelCase keys")
	var json: String = backend.manifest_json({
		"width": 1280, "height": 720, "fps": 30, "start": 0.0, "end": 1.0,
		"frame_dir": "/tmp/frames", "audio": [],
	})
	_check(JSON.parse_string(json) is Dictionary, "manifest JSON parses")
	var relative: Dictionary = backend.build_manifest({
		"width": 1280, "height": 720, "fps": 24, "start": 0.0, "end": 1.0,
		"frame_dir": "/tmp/frames", "project_dir": "/tmp/kinema_project",
		"audio": [{"file": "audio/step.wav"}],
	})
	_check(str(Array(relative.get("audio", []))[0].get("path", "")) == "/tmp/kinema_project/audio/step.wav", "manifest resolves relative audio paths against the project")

	var encoded: Dictionary = backend.encode(manifest, "/tmp/out.mp4")
	_check(not bool(encoded.get("ok", true)), "encode refuses on Linux")
	_check(str(encoded.get("error", "")) == AndroidVideo.REASON, "encode refusal uses the exact reason")
	var polled: Dictionary = backend.poll()
	_check(str(polled.get("state", "")) == "unavailable", "poll reports unavailable on Linux")
	_check(str(polled.get("error", "")) == AndroidVideo.REASON, "poll carries the exact reason")
	_check(not bool(backend.probe("/tmp/out.mp4").get("ok", true)), "probe refuses on Linux")
	backend.cancel()
	var extraction: Dictionary = await backend.extract_frames("/tmp/in.mp4", "/tmp/out", 12, 1280)
	_check(not bool(extraction.get("ok", true)), "frame extraction refuses on Linux")

	var root := ProjectSettings.globalize_path("res://").simplify_path().get_base_dir()
	var stage := FileAccess.get_file_as_string(root.path_join("scripts/stage-android.sh"))
	_check(stage.contains("studio/android/app/java"), "stage script copies the Java media sources")
	_check(stage.contains("src/main/java"), "stage script targets the Android app java folder")
	var java_dir := root.path_join("studio/android/app/java/studio/kinema/media")
	var encoder_source := FileAccess.get_file_as_string(java_dir.path_join("KinemaVideoEncoder.java"))
	var frames_source := FileAccess.get_file_as_string(java_dir.path_join("KinemaVideoFrames.java"))
	for method in [
		"public static void encode(",
		"public static int progress()",
		"public static boolean done()",
		"public static String error()",
		"public static void cancel()",
		"public static String capabilities()",
		"public static String probe(",
	]:
		_check(encoder_source.contains(method), "KinemaVideoEncoder declares " + method)
	_check(frames_source.contains("public static String extract("), "KinemaVideoFrames declares extract")
	_check(frames_source.contains("MediaMetadataRetriever"), "KinemaVideoFrames uses MediaMetadataRetriever")
	_check(frames_source.contains("reference.json"), "KinemaVideoFrames writes reference.json")
	_check(frames_source.contains("OPTION_CLOSEST)"), "KinemaVideoFrames requests the closest frame, not only sync frames")
	_check(encoder_source.contains("colorFormats"), "KinemaVideoEncoder inspects codec color formats")
	_check(encoder_source.contains("COLOR_FormatYUV420SemiPlanar"), "KinemaVideoEncoder supports NV12/SemiPlanar")
	_check(encoder_source.contains("fillNV12"), "KinemaVideoEncoder converts I420 to NV12 when needed")
	_check(encoder_source.contains("getSupportedSampleRates"), "KinemaVideoEncoder reads AAC sample rates from codec capabilities")
	_check(encoder_source.contains("idle"), "KinemaVideoEncoder bounds the end-of-stream drain")
	_check(encoder_source.contains("if (!RUNNING.compareAndSet(false, true)) {\n            return;"), "a second encode does not corrupt the running encode state")


# -------------------------------------------------------------------------
# UI
# -------------------------------------------------------------------------

func _test_ui() -> void:
	print("MEDIA STEP: media lanes and sheets")
	_doc.media_system.reset()
	var lanes = MediaLanes.new()
	lanes.setup(_doc)
	add_child(lanes)
	lanes.refresh()
	await get_tree().process_frame
	_check(lanes.audio_row_height() == 48.0, "audio lane rows are 48 dp")
	_check(lanes.video_row_height() == 40.0, "video lane rows are 40 dp")
	_check(lanes.audio_row_count() == 0 and lanes.video_row_count() == 0, "empty media lanes have no rows")
	_check(lanes.empty_audio_text().contains("No audio tracks"), "audio empty state names the missing tracks")
	_check(lanes.empty_video_text().contains("No video reference"), "video empty state names the missing reference")
	_check(lanes.is_collapsed() == false, "media lanes start expanded")
	lanes.set_collapsed(true)
	_check(lanes.is_collapsed(), "media lanes collapse")
	lanes.set_collapsed(false)

	var ids := _prepare_ui_media()
	lanes.refresh()
	await get_tree().process_frame
	_check(lanes.audio_row_count() == 1, "audio lane shows the track row")
	_check(lanes.video_row_count() == 1, "video lane shows the reference row")
	_check(_all_controls_44(lanes), "media lane controls keep the 44 dp floor")
	var dragged_events: Array = []
	lanes.video_dragged.connect(func(id: String, patch: Dictionary) -> void: dragged_events.append({"id": id, "patch": patch}))
	lanes.drag_video("ui_ref", 0.5)
	var dragged: Dictionary = _doc.media_system.video_reference("ui_ref")
	_check(_near(float(dragged.get("start", -1.0)), 0.5), "video lane drag changes the reference start")
	_check(dragged_events.size() == 1 and _near(float(dragged_events[0]["patch"].get("start", -1.0)), 0.5), "video lane drag emits the start patch")

	var audio_sheet = AudioSheet.new()
	audio_sheet.setup(_doc.media_system)
	audio_sheet.open(str(ids.get("track_id", "")))
	add_child(audio_sheet)
	await get_tree().process_frame
	_check(audio_sheet.track_id() == str(ids.get("track_id", "")), "audio sheet opens the requested track")
	_check(audio_sheet.waveform_status().begins_with("Waveform"), "WAV audio sheet shows a real waveform")
	_check(audio_sheet.has_delete_confirm(), "audio sheet has a delete action")
	_check(_all_controls_44(audio_sheet), "audio sheet controls keep the 44 dp floor")
	var audio_slider := _find_slider(audio_sheet)
	_check(audio_slider != null, "audio sheet has a volume slider")
	if audio_slider != null:
		audio_slider.value = 0.5
		_check(audio_sheet.volume_text() == "50%", "audio volume label follows the slider")

	var video_panel = VideoReferencePanel.new()
	video_panel.setup(_doc.media_system)
	video_panel.open(str(ids.get("ref_id", "")))
	add_child(video_panel)
	await get_tree().process_frame
	_check(video_panel.reference_id() == str(ids.get("ref_id", "")), "video panel opens the requested reference")
	_check(video_panel.delete_warning().contains("cannot be undone"), "video panel warns that deletion cannot be undone")
	_check(video_panel.frame_text().contains("fps"), "video panel reports the frame proxy rate")
	_check(_all_controls_44(video_panel), "video panel controls keep the 44 dp floor")
	var opacity_slider := _find_slider(video_panel)
	_check(opacity_slider != null, "video panel has an opacity slider")
	if opacity_slider != null:
		opacity_slider.value = 80.0
		_check(video_panel.opacity_text() == "80%", "video opacity label follows the slider")
	_check(not video_panel.request_delete(), "first delete press only arms confirmation")
	_check(not _doc.media_system.video_references().is_empty(), "first delete press keeps the reference")
	_check(video_panel.request_delete(), "second delete press confirms deletion")
	_check(_doc.media_system.video_references().is_empty(), "confirmed delete removes the reference")

	var export_sheet = MediaExportSheet.new()
	export_sheet.setup(_doc, null)
	add_child(export_sheet)
	await get_tree().process_frame
	_check(export_sheet.resolution_sizes() == [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)], "export sheet offers the three exact sizes")
	_check(export_sheet.gif_fps_options() == [12, 24, 30], "GIF fps options are 12/24/30")
	_check(export_sheet.gif_disabled_reason(60) == "GIF timing is centisecond-based; 60 fps cannot be represented", "export sheet explains the disabled GIF 60 fps")
	_check(export_sheet.mp4_reason() == AndroidVideo.REASON, "export sheet explains the unavailable MP4 backend")
	_check(export_sheet.progress_text("frames", 42, 144) == "Frame 42/144", "export progress shows frame n/N")
	_check(export_sheet.progress_text("encoding", 0, 0) == "Encoding video", "export progress shows the encoding phase")
	_check(export_sheet.progress_text("verifying", 0, 0) == "Verifying", "export progress shows the verifying phase")
	_check(export_sheet.format_ids() == ["png", "gif", "mp4"], "export sheet offers PNG, GIF and MP4")
	_check(_all_controls_44(export_sheet), "export sheet controls keep the 44 dp floor")
	_check(_all_primary_96(export_sheet), "export primary action is 96 dp wide")
	export_sheet.set_output_path("user://exports/custom.png")
	_check(export_sheet.build_options().get("output_path", "") == "user://exports/custom.png", "export sheet uses the typed output path")
	export_sheet.set_format("gif")
	await get_tree().process_frame
	_check(str(export_sheet.build_options().get("output_path", "")).ends_with(".gif"), "format change keeps a valid output extension")
	_check(export_sheet.gif_width_options() == [320, 480, 640, 720], "export sheet offers the GIF width presets")
	_check(export_sheet.gif_reason_visible(), "GIF 60 fps reason is visible as a caption")
	_check(export_sheet.gif_reason_text() == "GIF timing is centisecond-based; 60 fps cannot be represented", "GIF reason caption uses the exact text")

	var import_sheet = MediaImportSheet.new()
	import_sheet.setup(_doc)
	add_child(import_sheet)
	await get_tree().process_frame
	_check(import_sheet.proxy_fps_options() == [12, 24], "import proxy fps options are 12/24")
	_check(import_sheet.max_width_options().has(1280), "import proxy offers a 1280 max width")
	_check(import_sheet.unsupported_reason("mp4").contains("Android"), "import sheet explains MP4 extraction is Android-only")
	_check(import_sheet.unsupported_reason("ogv").contains("VideoStreamPlayer"), "import sheet explains the OGV direct-play path")
	_check(_all_controls_44(import_sheet), "import sheet controls keep the 44 dp floor")
	_check(_all_primary_96(import_sheet), "import primary actions are 96 dp wide")
	import_sheet.set_video_path("clip.mp4")
	_check(not import_sheet.video_import_enabled(), "MP4 import button is disabled on Linux")
	import_sheet.set_video_path("clip.ogv")
	_check(import_sheet.video_import_enabled(), "OGV import button stays enabled")


func _prepare_ui_media() -> Dictionary:
	var source := FIXTURE_DIR.path_join("ui_track.wav")
	_write_wav(source, 44100, 1, 1.0, 330.0)
	var imported: Dictionary = _doc.media_system.import_audio(source)
	var track_id: String = _doc.media_system.add_audio_track(str(imported.get("rel_path", "")), 0.0)
	var track: Dictionary = _doc.media_system.audio_tracks()[0]
	var ref_dir := PROJECT_DIR.path_join("video_refs").path_join("ui_ref")
	var frames_dir := ref_dir.path_join("frames")
	DirAccess.make_dir_recursive_absolute(frames_dir)
	var names: Array = []
	for index in range(2):
		var name := "frame_%06d.jpg" % (index + 1)
		_make_jpeg(frames_dir.path_join(name), Color(0.2 + index * 0.2, 0.3, 0.3))
		names.append(name)
	_write_json(ref_dir.path_join("reference.json"), {
		"version": 1, "fps": 12, "duration": 1.0, "width": 16, "height": 16, "frames": names,
	})
	var ref := {
		"id": "ui_ref", "name": "UI Reference", "dir": "video_refs/ui_ref",
		"fps": 12, "duration": 1.0, "width": 16, "height": 16,
	}
	_doc.media_system.load_data({"media": {"audio": [track], "video_refs": [ref]}}, PROJECT_DIR)
	return {"track_id": track_id, "ref_id": "ui_ref"}


func _all_controls_44(node: Node) -> bool:
	var ok := true
	for child in node.get_children():
		if child is Button or child is LineEdit or child is OptionButton or child is HSlider:
			var control: Control = child
			if control.get_combined_minimum_size().y < 43.5:
				printerr("MEDIA: control below 44 dp: %s (%s) %.1f" % [child.name, child.get_class(), control.get_combined_minimum_size().y])
				ok = false
		if not _all_controls_44(child):
			ok = false
	return ok


func _all_primary_96(node: Node) -> bool:
	var ok := true
	for child in node.get_children():
		if child is Button and str(child.text) in ["Export", "Import audio", "Import video"]:
			var button: Button = child
			if button.get_combined_minimum_size().x < 95.5:
				printerr("MEDIA: primary action narrower than 96 dp: %s %.1f" % [button.text, button.get_combined_minimum_size().x])
				ok = false
		if not _all_primary_96(child):
			ok = false
	return ok


func _find_slider(node: Node) -> HSlider:
	for child in node.get_children():
		if child is HSlider:
			return child
		var found := _find_slider(child)
		if found != null:
			return found
	return null


# -------------------------------------------------------------------------
# Fixtures
# -------------------------------------------------------------------------

func _files(directory: String) -> PackedStringArray:
	if not DirAccess.dir_exists_absolute(directory):
		return PackedStringArray()
	var files := DirAccess.get_files_at(directory)
	files.sort()
	return files

func _write_wav(path: String, sample_rate: int, channels: int, seconds: float, frequency: float) -> void:
	var frames := int(round(sample_rate * seconds))
	var pcm := PackedByteArray()
	pcm.resize(frames * channels * 2)
	for i in range(frames):
		var value := int(sin(TAU * frequency * float(i) / float(sample_rate)) * 12000.0)
		for c in range(channels):
			pcm.encode_s16((i * channels + c) * 2, value)
	var header := PackedByteArray()
	header.resize(44)
	header.encode_u32(0, 0x46464952) # RIFF
	header.encode_u32(4, 36 + pcm.size())
	header.encode_u32(8, 0x45564157) # WAVE
	header.encode_u32(12, 0x20746D66) # fmt
	header.encode_u32(16, 16)
	header.encode_u16(20, 1)
	header.encode_u16(22, channels)
	header.encode_u32(24, sample_rate)
	header.encode_u32(28, sample_rate * channels * 2)
	header.encode_u16(32, channels * 2)
	header.encode_u16(34, 16)
	header.encode_u32(36, 0x61746164) # data
	header.encode_u32(40, pcm.size())
	var bytes := header + pcm
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _make_jpeg(path: String, color: Color) -> int:
	var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
	image.fill(color)
	return image.save_jpg(path, 0.95)


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _valid_wav(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44:
		return false
	return bytes.slice(0, 4).get_string_from_ascii() == "RIFF" \
		and bytes.slice(8, 12).get_string_from_ascii() == "WAVE" \
		and bytes.slice(12, 16).get_string_from_ascii() == "fmt " \
		and bytes.slice(36, 40).get_string_from_ascii() == "data"


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child := path.path_join(entry)
			if dir.current_is_dir():
				_remove_tree(child)
			else:
				DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
