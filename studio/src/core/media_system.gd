extends RefCounted
## Media subsystem: audio tracks that follow sequence time, video-reference
## frame proxies, and the WAV mixdown used by the Android MP4 backend.
##
## `Document` owns one instance for the whole session. Scene children such as
## `AudioStreamPlayer` are attached to the document node, never to this
## `RefCounted`, so resetting a project cannot leave orphan players behind.

const AudioLibrary = preload("res://src/core/audio_library.gd")

const AUDIO_DEFAULTS := {
	"start": 0.0,
	"trim_start": 0.0,
	"volume": 1.0,
	"muted": false,
	"fade_in": 0.0,
	"fade_out": 0.0,
}
const DRIFT_TOLERANCE := 0.08

var _document = null
var _project_dir := ""
var _audio: Array[Dictionary] = []
var _video_refs: Array[Dictionary] = []
var _players: Dictionary = {}
var _next_audio := 1
var _next_video := 1
var _sequence_time := 0.0
var _sequence_playing := false


func setup(document) -> void:
	_document = document


func reset() -> void:
	_stop_all_players(true)
	_audio.clear()
	_video_refs.clear()
	_project_dir = ""
	_next_audio = 1
	_next_video = 1
	_sequence_time = 0.0
	_sequence_playing = false


func to_data() -> Dictionary:
	return {
		"media": {
			"audio": _audio.duplicate(true),
			"video_refs": _video_refs.duplicate(true),
		},
	}


func load_data(data: Dictionary, project_dir: String) -> void:
	_project_dir = project_dir
	_stop_all_players(true)
	_audio.clear()
	_video_refs.clear()
	_next_audio = 1
	_next_video = 1
	var media: Dictionary = data.get("media", {}) if data is Dictionary else {}
	for raw in media.get("audio", []):
		if raw is Dictionary:
			_audio.append(_normalize_audio(raw))
	for raw in media.get("video_refs", []):
		if raw is Dictionary:
			_video_refs.append(_normalize_video(raw))
	_emit_changed()


func advance(delta: float) -> void:
	if not _sequence_playing:
		return
	var time := _sequence_time + delta
	if _document != null and _document.has_method("sequence_time"):
		time = float(_document.sequence_time())
	_sequence_time = time
	_sync_players()


# -------------------------------------------------------------------------
# Audio
# -------------------------------------------------------------------------

func import_audio(uri: String) -> Dictionary:
	var result := AudioLibrary.import_file(uri, _root())
	if bool(result.get("ok", false)):
		_emit_changed()
	return result


func add_audio_track(rel_path: String, start: float) -> String:
	var loaded := AudioLibrary.load_stream(_root().path_join(rel_path))
	if not bool(loaded.get("ok", false)):
		return ""
	var track := {
		"id": "aud_%d" % _next_audio,
		"name": rel_path.get_file().get_basename(),
		"file": rel_path,
		"start": maxf(0.0, start),
		"trim_start": 0.0,
		"trim_end": maxf(0.0, float(loaded.get("duration", 0.0))),
		"volume": 1.0,
		"muted": false,
		"fade_in": 0.0,
		"fade_out": 0.0,
	}
	_next_audio += 1
	_audio.append(track)
	_emit_changed()
	return str(track["id"])


func update_audio_track(id: String, patch: Dictionary) -> void:
	var index := _audio_index(id)
	if index < 0:
		return
	var track: Dictionary = _audio[index]
	for key in patch.keys():
		if key in ["name", "file", "start", "trim_start", "trim_end", "volume", "muted", "fade_in", "fade_out"]:
			track[key] = patch[key]
	track["start"] = maxf(0.0, float(track.get("start", 0.0)))
	track["trim_start"] = maxf(0.0, float(track.get("trim_start", 0.0)))
	track["trim_end"] = maxf(float(track.get("trim_start", 0.0)), float(track.get("trim_end", 0.0)))
	track["volume"] = clampf(float(track.get("volume", 1.0)), 0.0, 1.0)
	track["fade_in"] = maxf(0.0, float(track.get("fade_in", 0.0)))
	track["fade_out"] = maxf(0.0, float(track.get("fade_out", 0.0)))
	_audio[index] = track
	var player: AudioStreamPlayer = _players.get(id)
	if player != null and patch.has("file"):
		var loaded := AudioLibrary.load_stream(_root().path_join(str(track.get("file", ""))))
		if bool(loaded.get("ok", false)):
			player.stream = loaded.get("stream")
	_emit_changed()


func delete_audio_track(id: String) -> void:
	var index := _audio_index(id)
	if index < 0:
		return
	_audio.remove_at(index)
	var player: AudioStreamPlayer = _players.get(id)
	if player != null and is_instance_valid(player):
		player.stop()
		player.queue_free()
	_players.erase(id)
	_emit_changed()


func audio_tracks() -> Array:
	return _audio.duplicate(true)


## Sequence-time position inside the source file. `sequence_time - start +
## trim_start` is the single formula used by playback, the UI and the mixdown.
func audio_offset(track: Dictionary, sequence_time: float) -> float:
	return sequence_time - float(track.get("start", 0.0)) + float(track.get("trim_start", 0.0))


func audio_active(track: Dictionary, sequence_time: float) -> bool:
	var trim_start := float(track.get("trim_start", 0.0))
	var trim_end := float(track.get("trim_end", 0.0))
	if trim_end <= trim_start:
		return false
	var expected := audio_offset(track, sequence_time)
	return expected >= trim_start - 0.00001 and expected <= trim_end + 0.00001


func audio_volume_at(track: Dictionary, sequence_time: float) -> float:
	if not audio_active(track, sequence_time):
		return 0.0
	return clampf(float(track.get("volume", 1.0)), 0.0, 1.0) * AudioLibrary._track_envelope(track, sequence_time)


func mix_wav(output_path: String) -> Dictionary:
	return AudioLibrary.mix_tracks(_audio, _root(), output_path)


func _normalize_audio(raw: Dictionary) -> Dictionary:
	var track: Dictionary = raw.duplicate(true)
	track["id"] = str(track.get("id", "aud_%d" % _next_audio))
	track["name"] = str(track.get("name", str(track.get("file", "Audio")).get_file().get_basename()))
	track["file"] = str(track.get("file", ""))
	for key in AUDIO_DEFAULTS.keys():
		if not track.has(key):
			track[key] = AUDIO_DEFAULTS[key]
	if not track.has("trim_end") or float(track.get("trim_end", 0.0)) <= float(track.get("trim_start", 0.0)):
		var loaded := AudioLibrary.load_stream(_root().path_join(str(track.get("file", ""))))
		track["trim_end"] = float(loaded.get("duration", 0.0)) if bool(loaded.get("ok", false)) else float(track.get("trim_start", 0.0))
	_next_audio = maxi(_next_audio, _id_serial(str(track["id"])) + 1)
	return track


func _audio_index(id: String) -> int:
	for index in range(_audio.size()):
		if str(_audio[index].get("id", "")) == id:
			return index
	return -1


func _id_serial(id: String) -> int:
	var parts := id.split("_")
	if parts.size() < 2:
		return 0
	return int(parts[parts.size() - 1])


func _ensure_player(track: Dictionary) -> AudioStreamPlayer:
	var id := str(track.get("id", ""))
	var player: AudioStreamPlayer = _players.get(id)
	if player != null and is_instance_valid(player):
		return player
	if _document == null or not _document is Node:
		return null
	player = AudioStreamPlayer.new()
	player.name = "Audio_" + id
	var loaded := AudioLibrary.load_stream(_root().path_join(str(track.get("file", ""))))
	if bool(loaded.get("ok", false)):
		player.stream = loaded.get("stream")
	_document.add_child(player)
	_players[id] = player
	return player


func _sync_players() -> void:
	for track in _audio:
		var player := _ensure_player(track)
		if player == null:
			continue
		var active := audio_active(track, _sequence_time)
		if _sequence_playing and active:
			var expected := audio_offset(track, _sequence_time)
			if not player.playing:
				player.play(expected)
			elif absf(player.get_playback_position() - expected) > DRIFT_TOLERANCE:
				player.seek(expected)
			var volume := audio_volume_at(track, _sequence_time)
			player.volume_db = linear_to_db(maxf(volume, 0.0001)) if volume > 0.0 else -80.0
		else:
			if player.playing:
				player.stop()
			player.volume_db = -80.0


func _stop_all_players(free_them: bool = false) -> void:
	for id in _players.keys():
		var player: AudioStreamPlayer = _players[id]
		if player != null and is_instance_valid(player):
			player.stop()
			if free_them:
				player.queue_free()
	if free_them:
		_players.clear()


# -------------------------------------------------------------------------
# Sequence transport
# -------------------------------------------------------------------------

func seek_sequence(time: float, playing: bool) -> void:
	_sequence_time = maxf(0.0, time)
	_sequence_playing = playing
	if playing:
		_sync_players()
	else:
		_pause_all_players()


func play_sequence(time: float) -> void:
	_sequence_time = maxf(0.0, time)
	_sequence_playing = true
	_sync_players()


func pause_sequence() -> void:
	_sequence_playing = false
	_pause_all_players()


func stop_sequence() -> void:
	_sequence_playing = false
	_sequence_time = 0.0
	for id in _players.keys():
		var player: AudioStreamPlayer = _players[id]
		if player != null and is_instance_valid(player):
			player.stop()
			player.volume_db = -80.0


func _pause_all_players() -> void:
	for id in _players.keys():
		var player: AudioStreamPlayer = _players[id]
		if player != null and is_instance_valid(player) and player.playing:
			player.pause()


# -------------------------------------------------------------------------
# Video references (implemented in the video half below)
# -------------------------------------------------------------------------

func import_video_reference(_uri: String) -> Dictionary:
	return {"ok": false, "error": "Video reference import is not implemented yet."}


func video_references() -> Array:
	return _video_refs.duplicate(true)


func update_video_reference(_id: String, _patch: Dictionary) -> void:
	pass


func delete_video_reference(_id: String) -> void:
	pass


func frame_for_time(_id: String, _time: float) -> Image:
	return null


func _normalize_video(raw: Dictionary) -> Dictionary:
	return raw.duplicate(true)


func _root() -> String:
	if _project_dir != "":
		return _project_dir
	if _document != null:
		var value = _document.get("project_dir")
		if value != null:
			return str(value)
	return ""


func _emit_changed() -> void:
	if _document != null and is_instance_valid(_document) and _document.has_signal("media_changed"):
		_document.emit_signal("media_changed")
