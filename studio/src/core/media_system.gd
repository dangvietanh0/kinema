extends RefCounted
## Media subsystem contract: audio tracks, video-reference proxies, sequence
## playback and export helpers.
##
## The contract commit installs safe no-ops so the shell can be wired before
## WS-B lands. Every import/export method returns an explicit error instead of
## pretending to succeed. WS-B replaces this file with the real implementation
## and keeps these signatures.

var _document = null
var _project_dir := ""

func setup(document) -> void:
	_document = document

func reset() -> void:
	_project_dir = ""

func to_data() -> Dictionary:
	return {"media": {"audio": [], "video_refs": []}}

func load_data(_data: Dictionary, project_dir: String) -> void:
	_project_dir = project_dir

func advance(_delta: float) -> void:
	pass

func import_audio(_uri: String) -> Dictionary:
	return {"ok": false, "error": "Audio import is not implemented yet."}

func add_audio_track(_rel_path: String, _start: float) -> String:
	return ""

func update_audio_track(_id: String, _patch: Dictionary) -> void:
	pass

func delete_audio_track(_id: String) -> void:
	pass

func audio_tracks() -> Array:
	return []

func import_video_reference(_uri: String) -> Dictionary:
	return {"ok": false, "error": "Video reference import is not implemented yet."}

func video_references() -> Array:
	return []

func update_video_reference(_id: String, _patch: Dictionary) -> void:
	pass

func delete_video_reference(_id: String) -> void:
	pass

func frame_for_time(_id: String, _time: float) -> Image:
	return null

func seek_sequence(_time: float, _playing: bool) -> void:
	pass

func play_sequence(_time: float) -> void:
	pass

func pause_sequence() -> void:
	pass

func stop_sequence() -> void:
	pass

func mix_wav(_output_path: String) -> Dictionary:
	return {"ok": false, "error": "WAV mixdown is not implemented yet."}
