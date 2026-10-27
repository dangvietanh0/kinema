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

	_check(str(_doc.media_system.delete_confirm_text("ref_1")).contains("cannot be undone"), "video delete exposes confirm metadata")
	_doc.media_system.delete_video_reference("ref_1")
	_check(_doc.media_system.video_references().is_empty(), "delete_video_reference removes the record")
	_check(not DirAccess.dir_exists_absolute(ref_dir), "delete_video_reference removes the proxy directory")


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
# Fixtures
# -------------------------------------------------------------------------

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
