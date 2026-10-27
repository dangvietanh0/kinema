extends RefCounted
## Audio file loading, import and waveform inspection.
##
## Kinema copies imported audio into `<project>/audio/` so a project folder is
## self-contained. WAV files also get a peak cache for the timeline lane; OGG
## and MP3 are playable but deliberately report "waveform unavailable" instead
## of drawing a decorative fake waveform.

const SUPPORTED_EXTENSIONS := ["wav", "ogg", "mp3"]
const WAVEFORM_BUCKET := 512
const CACHE_DIR := "user://cache/waveforms"
const MIX_RATE := 44100
const MIX_CHANNELS := 2


static func extension_of(path: String) -> String:
	return path.get_extension().to_lower()


static func is_supported(path: String) -> bool:
	return extension_of(path) in SUPPORTED_EXTENSIONS


## Load a stream and describe it without pretending unsupported codecs work.
## Returns {ok, stream, format, duration, error}.
static func load_stream(path: String) -> Dictionary:
	var ext := extension_of(path)
	if not ext in SUPPORTED_EXTENSIONS:
		return {"ok": false, "stream": null, "format": ext, "duration": 0.0,
			"error": "Unsupported audio format .%s. Use WAV, OGG or MP3." % ext}
	if not FileAccess.file_exists(path):
		return {"ok": false, "stream": null, "format": ext, "duration": 0.0,
			"error": "Audio file not found: %s" % path}
	var stream: AudioStream = null
	match ext:
		"wav":
			stream = AudioStreamWAV.load_from_file(path)
		"ogg":
			stream = AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			stream = AudioStreamMP3.load_from_file(path)
	if stream == null:
		return {"ok": false, "stream": null, "format": ext, "duration": 0.0,
			"error": "Could not decode .%s audio: %s" % [ext, path]}
	return {
		"ok": true,
		"stream": stream,
		"format": ext,
		"duration": stream_duration(stream, ext),
		"error": "",
	}


static func stream_duration(stream: AudioStream, ext: String) -> float:
	if stream == null:
		return 0.0
	if ext == "wav" and stream is AudioStreamWAV:
		return wav_duration(stream)
	var length := stream.get_length()
	return maxf(0.0, length)


static func wav_duration(stream: AudioStreamWAV) -> float:
	if stream == null or stream.mix_rate <= 0:
		return 0.0
	var channels := 2 if stream.stereo else 1
	var bytes_per_sample := 0
	match stream.format:
		AudioStreamWAV.FORMAT_8_BITS:
			bytes_per_sample = 1
		AudioStreamWAV.FORMAT_16_BITS:
			bytes_per_sample = 2
		_:
			# IMA ADPCM and QOA need a decoder; report the engine length when
			# it has one instead of inventing a sample count.
			return maxf(0.0, stream.get_length())
	if bytes_per_sample == 0:
		return 0.0
	return float(stream.data.size()) / float(channels * bytes_per_sample * stream.mix_rate)


## Copy an imported file into `<project>/audio/` and validate that the copy
## decodes. A failed copy is removed so a broken import never leaves a file
## behind.
static func import_file(uri: String, project_dir: String) -> Dictionary:
	if uri.begins_with("content://"):
		return {"ok": false, "error": "Android content URIs cannot be copied by FileAccess. Pick the file from the project folder instead."}
	if not FileAccess.file_exists(uri):
		return {"ok": false, "error": "Audio file not found: %s" % uri}
	if not is_supported(uri):
		return {"ok": false, "error": "Unsupported audio format .%s. Use WAV, OGG or MP3." % extension_of(uri)}
	if project_dir == "":
		return {"ok": false, "error": "No project folder is open."}
	var bytes := FileAccess.get_file_as_bytes(uri)
	if bytes.is_empty():
		return {"ok": false, "error": "Could not read audio file: %s" % uri}
	var audio_dir := project_dir.path_join("audio")
	if DirAccess.make_dir_recursive_absolute(audio_dir) != OK:
		return {"ok": false, "error": "Could not create the project audio folder."}
	var file_name := _unique_name(audio_dir, uri.get_file())
	var target := audio_dir.path_join(file_name)
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not write %s." % target}
	file.store_buffer(bytes)
	file.close()
	var loaded := load_stream(target)
	if not bool(loaded.get("ok", false)):
		DirAccess.remove_absolute(target)
		return {"ok": false, "error": str(loaded.get("error", "Could not decode audio."))}
	return {
		"ok": true,
		"rel_path": "audio/".path_join(file_name),
		"path": target,
		"name": uri.get_file().get_basename(),
		"format": extension_of(uri),
		"duration": float(loaded.get("duration", 0.0)),
		"error": "",
	}


static func _unique_name(directory: String, file_name: String) -> String:
	var base := file_name.get_basename()
	var ext := file_name.get_extension()
	var candidate := file_name
	var serial := 2
	while FileAccess.file_exists(directory.path_join(candidate)):
		candidate = "%s_%d.%s" % [base, serial, ext]
		serial += 1
	return candidate


## Peak cache for the timeline lane. WAV only; OGG/MP3 return an explicit
## reason because decoding them would need a full codec pass we do not run.
static func waveform_peaks(path: String) -> Dictionary:
	if extension_of(path) != "wav":
		return {"ok": false, "peaks": [], "error": "waveform unavailable"}
	if not FileAccess.file_exists(path):
		return {"ok": false, "peaks": [], "error": "Audio file not found."}
	var key := _cache_key(path)
	var cache_path := CACHE_DIR.path_join(key + ".json")
	if FileAccess.file_exists(cache_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(cache_path))
		if parsed is Dictionary and parsed.has("peaks"):
			return {"ok": true, "peaks": parsed["peaks"], "error": ""}
	var stream := AudioStreamWAV.load_from_file(path)
	if stream == null:
		return {"ok": false, "peaks": [], "error": "Could not decode WAV audio."}
	var channels := 2 if stream.stereo else 1
	var bytes_per_sample := 2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1
	if stream.format != AudioStreamWAV.FORMAT_16_BITS and stream.format != AudioStreamWAV.FORMAT_8_BITS:
		return {"ok": false, "peaks": [], "error": "waveform unavailable"}
	var frame_count := int(stream.data.size() / (channels * bytes_per_sample))
	var peaks: Array = []
	var index := 0
	while index < frame_count:
		var end := mini(frame_count, index + WAVEFORM_BUCKET)
		var peak := 0.0
		for frame in range(index, end):
			for channel in range(channels):
				var offset := (frame * channels + channel) * bytes_per_sample
				var sample := 0.0
				if bytes_per_sample == 2:
					sample = float(stream.data.decode_s16(offset)) / 32768.0
				else:
					sample = (float(stream.data.decode_u8(offset)) - 128.0) / 128.0
				peak = maxf(peak, absf(sample))
		peaks.append(snappedf(peak, 0.0001))
		index = end
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var file := FileAccess.open(cache_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"version": 1, "path": path, "bucket": WAVEFORM_BUCKET, "peaks": peaks}))
		file.close()
	return {"ok": true, "peaks": peaks, "error": ""}


static func _cache_key(path: String) -> String:
	var size := 0
	var modified := 0
	if FileAccess.file_exists(path):
		size = FileAccess.get_file_as_bytes(path).size()
		modified = int(FileAccess.get_modified_time(path))
	return ("%s|%d|%d" % [path, size, modified]).md5_text()


## Mix every WAV track into a 44.1 kHz stereo 16-bit RIFF file. Returns
## {ok, path, sample_rate, channels, frames, error}. Non-WAV sources are
## refused with the reason the UI shows on the disabled button.
static func mix_tracks(tracks: Array, project_dir: String, output_path: String) -> Dictionary:
	for raw in tracks:
		if not raw is Dictionary:
			continue
		var file := str(raw.get("file", ""))
		if extension_of(file) != "wav":
			return {"ok": false, "error": "WAV mixdown needs WAV sources; MP4 export decodes other formats in the Android backend."}
	if tracks.is_empty():
		return {"ok": false, "error": "Add at least one WAV track before mixing."}
	var sources: Array = []
	var total_seconds := 0.0
	for raw in tracks:
		var track: Dictionary = raw
		var path := project_dir.path_join(str(track.get("file", "")))
		var stream := AudioStreamWAV.load_from_file(path)
		if stream == null:
			return {"ok": false, "error": "Could not decode WAV source: %s" % str(track.get("file", ""))}
		if stream.format != AudioStreamWAV.FORMAT_16_BITS and stream.format != AudioStreamWAV.FORMAT_8_BITS:
			return {"ok": false, "error": "WAV mixdown needs 8-bit or 16-bit PCM sources."}
		var start := float(track.get("start", 0.0))
		var trim_start := float(track.get("trim_start", 0.0))
		var trim_end := float(track.get("trim_end", 0.0))
		if trim_end <= trim_start:
			continue
		sources.append({"stream": stream, "track": track})
		total_seconds = maxf(total_seconds, start + (trim_end - trim_start))
	if sources.is_empty():
		return {"ok": false, "error": "No audio track has a non-empty trimmed range."}
	var frames := maxi(1, int(ceil(total_seconds * MIX_RATE)))
	var pcm := PackedByteArray()
	pcm.resize(frames * MIX_CHANNELS * 2)
	pcm.fill(0)
	for source in sources:
		var stream: AudioStreamWAV = source["stream"]
		var track: Dictionary = source["track"]
		var channels := 2 if stream.stereo else 1
		var bytes_per_sample := 2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1
		var source_frames := int(stream.data.size() / (channels * bytes_per_sample))
		var start := float(track.get("start", 0.0))
		var trim_start := float(track.get("trim_start", 0.0))
		var trim_end := float(track.get("trim_end", 0.0))
		var volume := float(track.get("volume", 1.0))
		var duration := trim_end - trim_start
		var first := int(floor(start * MIX_RATE))
		var last := mini(frames, int(ceil((start + duration) * MIX_RATE)))
		for out_frame in range(maxi(0, first), last):
			var sequence_time := float(out_frame) / MIX_RATE
			var envelope := _track_envelope(track, sequence_time)
			if envelope <= 0.0:
				continue
			var local := sequence_time - start
			var source_time := trim_start + local
			var source_frame := int(floor(source_time * stream.mix_rate))
			if source_frame < 0 or source_frame >= source_frames:
				continue
			var left := 0.0
			var right := 0.0
			for channel in range(channels):
				var offset := (source_frame * channels + channel) * bytes_per_sample
				var sample := 0.0
				if bytes_per_sample == 2:
					sample = float(stream.data.decode_s16(offset)) / 32768.0
				else:
					sample = (float(stream.data.decode_u8(offset)) - 128.0) / 128.0
				if channels == 1:
					left = sample
					right = sample
				elif channel == 0:
					left = sample
				else:
					right = sample
			var gain := volume * envelope
			var base := out_frame * MIX_CHANNELS * 2
			var mix_left := float(pcm.decode_s16(base)) / 32768.0 + left * gain
			var mix_right := float(pcm.decode_s16(base + 2)) / 32768.0 + right * gain
			pcm.encode_s16(base, int(clampf(mix_left, -1.0, 1.0) * 32767.0))
			pcm.encode_s16(base + 2, int(clampf(mix_right, -1.0, 1.0) * 32767.0))
	if output_path.get_base_dir() != "":
		DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var header := PackedByteArray()
	header.resize(44)
	header.encode_u32(0, 0x46464952)
	header.encode_u32(4, 36 + pcm.size())
	header.encode_u32(8, 0x45564157)
	header.encode_u32(12, 0x20746D66)
	header.encode_u32(16, 16)
	header.encode_u16(20, 1)
	header.encode_u16(22, MIX_CHANNELS)
	header.encode_u32(24, MIX_RATE)
	header.encode_u32(28, MIX_RATE * MIX_CHANNELS * 2)
	header.encode_u16(32, MIX_CHANNELS * 2)
	header.encode_u16(34, 16)
	header.encode_u32(36, 0x61746164)
	header.encode_u32(40, pcm.size())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not write %s." % output_path}
	file.store_buffer(header + pcm)
	file.close()
	return {"ok": true, "path": output_path, "sample_rate": MIX_RATE, "channels": MIX_CHANNELS, "frames": frames, "error": ""}


## Smoothstep envelope for a track at sequence time, including mute. Shared by
## playback volume and the WAV mixdown so both use identical maths.
static func _track_envelope(track: Dictionary, sequence_time: float) -> float:
	if bool(track.get("muted", false)):
		return 0.0
	var start := float(track.get("start", 0.0))
	var trim_start := float(track.get("trim_start", 0.0))
	var trim_end := float(track.get("trim_end", 0.0))
	var duration := trim_end - trim_start
	if duration <= 0.0:
		return 0.0
	var local := sequence_time - start
	if local < 0.0 or local > duration:
		return 0.0
	var envelope := 1.0
	var fade_in := clampf(float(track.get("fade_in", 0.0)), 0.0, duration)
	var fade_out := clampf(float(track.get("fade_out", 0.0)), 0.0, duration)
	if fade_in + fade_out > duration and duration > 0.0:
		var scale := duration / (fade_in + fade_out)
		fade_in *= scale
		fade_out *= scale
	if fade_in > 0.0 and local < fade_in:
		envelope = minf(envelope, _smoothstep(local / fade_in))
	if fade_out > 0.0 and local > duration - fade_out:
		envelope = minf(envelope, _smoothstep((duration - local) / fade_out))
	return clampf(envelope, 0.0, 1.0)


static func _smoothstep(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
