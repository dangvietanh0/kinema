extends RefCounted
## Android MP4 backend facade.
##
## Real MP4 export exists only in the Android Java MediaCodec backend. On
## Linux/headless this facade reports `available = false` with a concrete
## reason and never touches `JavaClassWrapper`. GDScript only builds manifests
## and polls the Java thread; it never pretends to encode video itself.

const ENCODER_CLASS := "studio.kinema.media.KinemaVideoEncoder"
const FRAMES_CLASS := "studio.kinema.media.KinemaVideoFrames"
const REASON := "MP4 encoding uses the Android MediaCodec backend. Build the Android APK to export MP4."
const FRAMES_REASON := "Video frame extraction uses the Android MediaCodec backend. Build the Android APK to import MP4/MOV references."
const DEFAULT_PATTERN := "frame_%04d.png"

var _encoder = null
var _frames = null
var _checked := false
var _available := false
var _reason := REASON


func available() -> bool:
	if _checked:
		return _available
	_checked = true
	_available = false
	_reason = REASON
	if OS.get_name() != "android":
		return false
	if not Engine.has_singleton("JavaClassWrapper"):
		_reason = "The Android Java bridge is not available in this runtime."
		return false
	var wrapper = Engine.get_singleton("JavaClassWrapper")
	if wrapper == null:
		_reason = "The Android Java bridge is not available in this runtime."
		return false
	var wrapped = wrapper.wrap(ENCODER_CLASS)
	if wrapped == null:
		_reason = "The Android MediaCodec backend is not staged in this build."
		return false
	_encoder = wrapped
	_available = true
	_reason = ""
	return true


func reason() -> String:
	if not _checked:
		available()
	return _reason


func frames_available() -> bool:
	if OS.get_name() != "android":
		return false
	if _frames == null:
		if not Engine.has_singleton("JavaClassWrapper"):
			return false
		var wrapper = Engine.get_singleton("JavaClassWrapper")
		if wrapper == null:
			return false
		_frames = wrapper.wrap(FRAMES_CLASS)
	return _frames != null


func capabilities() -> Dictionary:
	if not available():
		return {
			"supported": false,
			"reason": reason(),
			"avc": [],
			"aac": [],
			"max_width": 0,
			"max_height": 0,
		}
	var raw = _encoder.capabilities()
	var parsed: Variant = JSON.parse_string(str(raw))
	var result: Dictionary = parsed if parsed is Dictionary else {}
	result["supported"] = true
	result["reason"] = ""
	return result


func encode(manifest: Dictionary, output_path: String) -> Dictionary:
	if not available():
		return {"ok": false, "error": reason()}
	var json := JSON.stringify(manifest)
	_encoder.encode(json, output_path)
	return {"ok": true, "error": ""}


func poll() -> Dictionary:
	if not available():
		return {"state": "unavailable", "progress": 0.0, "done": false, "error": reason()}
	var done := bool(_encoder.done())
	var progress := int(_encoder.progress())
	var error := str(_encoder.error())
	return {
		"state": "done" if done and error == "" else ("error" if error != "" else "encoding"),
		"progress": clampf(float(progress) / 100.0, 0.0, 1.0),
		"percent": progress,
		"done": done,
		"error": error,
	}


func cancel() -> void:
	if available() and _encoder != null:
		_encoder.cancel()


func probe(path: String) -> Dictionary:
	if not available():
		return {"ok": false, "error": reason()}
	var raw = _encoder.probe(path)
	var parsed: Variant = JSON.parse_string(str(raw))
	if not parsed is Dictionary:
		return {"ok": false, "error": "The Android backend returned an unreadable probe result."}
	var result: Dictionary = parsed
	result["ok"] = not result.has("error") or str(result.get("error", "")) == ""
	return result


func extract_frames(video_path: String, out_dir: String, fps: int, max_width: int) -> Dictionary:
	if not frames_available():
		return {"ok": false, "error": FRAMES_REASON}
	var raw = _frames.extract(video_path, out_dir, maxi(1, fps), maxi(1, max_width))
	var parsed: Variant = JSON.parse_string(str(raw))
	if not parsed is Dictionary:
		return {"ok": false, "error": "The Android frame backend returned an unreadable result."}
	var started: Dictionary = parsed
	if not bool(started.get("started", false)):
		return started
	while not bool(_frames.done()):
		await Engine.get_main_loop().process_frame
	var finished: Variant = JSON.parse_string(str(_frames.result()))
	if not finished is Dictionary:
		return {"ok": false, "error": "The Android frame backend returned an unreadable result."}
	return finished


func cancel_frames() -> void:
	if frames_available() and _frames != null:
		_frames.cancel()


## Build the manifest the Java encoder reads. Frame count is the range times
## fps, matching the PNGs SequenceRenderer writes.
func build_manifest(options: Dictionary) -> Dictionary:
	var fps := maxi(1, int(options.get("fps", 24)))
	var start := float(options.get("start", 0.0))
	var end := float(options.get("end", start + 1.0))
	var count := int(options.get("frame_count", 0))
	if count <= 0:
		count = maxi(1, int(round(maxf(1.0 / float(fps), end - start) * float(fps))))
	var audio_out: Array = []
	for raw in options.get("audio", []):
		if not raw is Dictionary:
			continue
		var track: Dictionary = raw
		var path := str(track.get("path", track.get("file", "")))
		if path == "":
			continue
		audio_out.append({
			"path": path,
			"start": float(track.get("start", 0.0)),
			"trimStart": float(track.get("trimStart", track.get("trim_start", 0.0))),
			"trimEnd": float(track.get("trimEnd", track.get("trim_end", 0.0))),
			"volume": clampf(float(track.get("volume", 1.0)), 0.0, 1.0),
			"fadeIn": float(track.get("fadeIn", track.get("fade_in", 0.0))),
			"fadeOut": float(track.get("fadeOut", track.get("fade_out", 0.0))),
		})
	return {
		"width": maxi(2, int(options.get("width", 1920))),
		"height": maxi(2, int(options.get("height", 1080))),
		"fps": fps,
		"bitrate": maxi(1, int(options.get("bitrate", 12000000))),
		"frameDir": str(options.get("frame_dir", options.get("frameDir", ""))),
		"framePattern": str(options.get("frame_pattern", options.get("framePattern", DEFAULT_PATTERN))),
		"frameCount": count,
		"audio": audio_out,
	}


func manifest_json(options: Dictionary) -> String:
	return JSON.stringify(build_manifest(options))


## Verify a finished MP4: file exists, probe succeeds, duration is within one
## frame and the expected tracks are present. The UI calls this before it ever
## shows a success result.
func verify(path: String, expected_audio: bool, fps: int, expected_duration: float) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "The MP4 file was not written."}
	var info := probe(path)
	if not bool(info.get("ok", false)):
		return {"ok": false, "error": str(info.get("error", "Probe failed."))}
	var duration := float(info.get("duration", 0.0))
	var tolerance := 1.5 / float(maxi(1, fps))
	if absf(duration - expected_duration) > tolerance:
		return {"ok": false, "error": "Probe duration %.3f s does not match the requested %.3f s." % [duration, expected_duration]}
	if not bool(info.get("video", false)):
		return {"ok": false, "error": "The MP4 has no video track."}
	if expected_audio and not bool(info.get("audio", false)):
		return {"ok": false, "error": "The MP4 has no audio track."}
	return {"ok": true, "probe": info, "error": ""}
