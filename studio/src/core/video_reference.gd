extends RefCounted
## Video-reference frame proxies.
##
## A reference is a directory of numbered JPEG frames plus a `reference.json`
## manifest. MP4/M4V/MOV extraction happens in the Android Java backend; on
## Linux the import reports that honestly. OGV is not a frame proxy: it plays
## through `VideoStreamPlayer` and is stored with `kind: "ogv"`.

const MANIFEST_NAME := "reference.json"
const DEFAULT_OPACITY := 0.5
const DEFAULT_FIT := "contain"
const DEFAULT_START := 0.0
const DEFAULT_SCALE := 1.0
const VIDEO_EXTENSIONS := ["mp4", "m4v", "mov"]
const OGV_EXTENSION := "ogv"
const PROXY_FPS_PRESETS := [6, 12, 24]
const PROXY_FPS_DEFAULT := 12
const PROXY_WIDTH_PRESETS := [640, 960, 1280, 1920]
const PROXY_WIDTH_DEFAULT := 1280


static func source_kind(path: String) -> String:
	var ext := path.get_extension().to_lower()
	if ext == OGV_EXTENSION:
		return "ogv"
	if ext in VIDEO_EXTENSIONS:
		return "video"
	return "unsupported"


static func is_video_reference(path: String) -> bool:
	return source_kind(path) != "unsupported"


static func default_ref(id: String, name: String, dir: String, fps: float, duration: float, width: int, height: int) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"dir": dir,
		"fps": maxf(1.0, fps),
		"duration": maxf(0.0, duration),
		"width": maxi(0, width),
		"height": maxi(0, height),
		"start": DEFAULT_START,
		"opacity": DEFAULT_OPACITY,
		"fit": DEFAULT_FIT,
		"offset": [0.0, 0.0],
		"scale": DEFAULT_SCALE,
		"flip_h": false,
		"visible": true,
	}


## Fill in every §17.9 default without dropping unknown fields the backend may
## have written. `offset` is always a two-element array in JSON.
static func normalize(raw: Dictionary) -> Dictionary:
	var ref: Dictionary = raw.duplicate(true)
	ref["id"] = str(ref.get("id", ""))
	ref["name"] = str(ref.get("name", str(ref.get("id", "Reference"))))
	ref["dir"] = str(ref.get("dir", ""))
	ref["fps"] = maxf(1.0, float(ref.get("fps", 12.0)))
	ref["duration"] = maxf(0.0, float(ref.get("duration", 0.0)))
	ref["width"] = maxi(0, int(ref.get("width", 0)))
	ref["height"] = maxi(0, int(ref.get("height", 0)))
	ref["start"] = float(ref.get("start", DEFAULT_START))
	ref["opacity"] = clampf(float(ref.get("opacity", DEFAULT_OPACITY)), 0.0, 1.0)
	ref["fit"] = str(ref.get("fit", DEFAULT_FIT))
	if not ref["fit"] in ["contain", "cover"]:
		ref["fit"] = DEFAULT_FIT
	var offset = ref.get("offset", [0.0, 0.0])
	if offset is Vector2:
		ref["offset"] = [offset.x, offset.y]
	elif offset is Array and offset.size() >= 2:
		ref["offset"] = [float(offset[0]), float(offset[1])]
	else:
		ref["offset"] = [0.0, 0.0]
	ref["scale"] = maxf(0.01, float(ref.get("scale", DEFAULT_SCALE)))
	ref["flip_h"] = bool(ref.get("flip_h", false))
	ref["visible"] = bool(ref.get("visible", true))
	return ref


static func reference_dir(project_dir: String, ref: Dictionary) -> String:
	var dir := str(ref.get("dir", ""))
	if dir == "":
		return ""
	if dir.is_absolute_path() or dir.begins_with("user://") or dir.begins_with("res://"):
		return dir
	return project_dir.path_join(dir)


## Read `reference.json` from a reference directory. Returns
## {ok, manifest, path, error}. The manifest is validated enough that a broken
## proxy fails loudly instead of rendering a blank overlay.
static func load_manifest(project_dir: String, dir: String) -> Dictionary:
	var base := dir
	if not (base.is_absolute_path() or base.begins_with("user://") or base.begins_with("res://")):
		base = project_dir.path_join(dir)
	var path := base.path_join(MANIFEST_NAME)
	if not FileAccess.file_exists(path):
		return {"ok": false, "manifest": {}, "path": path, "error": "Video reference manifest is missing: %s" % path}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {"ok": false, "manifest": {}, "path": path, "error": "Video reference manifest is not valid JSON: %s" % path}
	var manifest: Dictionary = parsed
	if not manifest.has("frames") or not manifest["frames"] is Array:
		return {"ok": false, "manifest": manifest, "path": path, "error": "Video reference manifest has no frame list."}
	return {"ok": true, "manifest": manifest, "path": path, "error": ""}


static func manifest_for(project_dir: String, ref: Dictionary) -> Dictionary:
	return load_manifest(project_dir, str(ref.get("dir", "")))


static func frame_count(project_dir: String, ref: Dictionary) -> int:
	var loaded := manifest_for(project_dir, ref)
	if not bool(loaded.get("ok", false)):
		return 0
	return Array(loaded["manifest"].get("frames", [])).size()


## Frame index for a sequence time. Floor(time * fps), clamped to the proxy.
static func frame_index(time: float, fps: float, count: int) -> int:
	if count <= 0:
		return -1
	var index := int(floor(maxf(0.0, time) * maxf(1.0, fps)))
	return clampi(index, 0, count - 1)


static func frame_path(project_dir: String, ref: Dictionary, index: int) -> String:
	var loaded := manifest_for(project_dir, ref)
	if not bool(loaded.get("ok", false)):
		return ""
	return frame_path_for_manifest(project_dir, ref, loaded["manifest"], index)


static func frame_path_for_manifest(project_dir: String, ref: Dictionary, manifest: Dictionary, index: int) -> String:
	var frames: Array = manifest.get("frames", [])
	if index < 0 or index >= frames.size():
		return ""
	var base := reference_dir(project_dir, ref)
	var name := str(frames[index])
	if name.contains("/") or name.contains("\\"):
		return base.path_join(name)
	return base.path_join("frames").path_join(name)


static func frame_image(project_dir: String, ref: Dictionary, index: int) -> Image:
	var path := frame_path(project_dir, ref, index)
	if path == "" or not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return image


## Clip mode is preview only: the active strip's start plus the clip-local
## time selects the frame. No strip means frame zero, never a guessed time.
static func clip_preview_time(strip: Dictionary, local_time: float) -> float:
	if strip.is_empty():
		return 0.0
	return float(strip.get("start", 0.0)) + maxf(0.0, local_time)


## Delete a proxy directory recursively. This is deliberately not undoable:
## the JPEGs are project data, not document JSON.
static func delete_dir(project_dir: String, ref: Dictionary) -> bool:
	var dir := reference_dir(project_dir, ref)
	if dir == "":
		return false
	if not DirAccess.dir_exists_absolute(dir):
		return true
	return _remove_tree(dir)


static func _remove_tree(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return false
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
	return DirAccess.remove_absolute(path) == OK
