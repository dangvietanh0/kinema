extends RefCounted
## Camera-animation track export.
##
## The track samples the scene camera's transform once per frame at the export
## fps. FOV is static in this pass; rotation is a quaternion. The JSON is a
## plain, versioned document that any downstream tool can read.

const VERSION := 1

var _document = null


func setup(document) -> void:
	_document = document


func camera_names() -> Array:
	var names: Array = []
	if _document == null:
		return names
	for obj in _document.objects:
		if str(obj.get("kind", "")) == "camera":
			names.append({"id": str(obj.get("id", "")), "name": str(obj.get("name", "Camera"))})
	return names


func camera_fov(camera_id: String) -> float:
	if _document == null:
		return 45.0
	var obj: Dictionary = _document.get_object(camera_id)
	if obj.is_empty():
		return 45.0
	return clampf(float(obj.get("camera_fov", 45.0)), 12.0, 100.0)


func build(camera_id: String, fps: int, duration: float, frame_count: int = -1) -> Dictionary:
	if _document == null:
		return {}
	var obj: Dictionary = _document.get_object(camera_id)
	if obj.is_empty():
		return {}
	var node: Node3D = _document.nodes.get(camera_id)
	if node == null:
		return {}
	var rate := maxi(1, fps)
	var length := maxf(0.0, duration)
	var count := frame_count if frame_count > 0 else maxi(1, int(round(length * rate)))
	var frames: Array = []
	var original_time := float(_document.sequence_time()) if _document.has_method("sequence_time") else 0.0
	for index in range(count):
		var time := float(index) / float(rate)
		if _document.has_method("seek_sequence"):
			_document.seek_sequence(time, true)
		var xform := node.global_transform
		var rotation := xform.basis.get_rotation_quaternion()
		frames.append({
			"t": snappedf(time, 0.000001),
			"position": [snappedf(xform.origin.x, 0.000001), snappedf(xform.origin.y, 0.000001), snappedf(xform.origin.z, 0.000001)],
			"rotation": [snappedf(rotation.x, 0.000001), snappedf(rotation.y, 0.000001), snappedf(rotation.z, 0.000001), snappedf(rotation.w, 0.000001)],
		})
	if _document.has_method("seek_sequence"):
		_document.seek_sequence(original_time, true)
	return {
		"version": VERSION,
		"fps": rate,
		"duration": length,
		"camera": str(obj.get("name", "Camera")),
		"fov": camera_fov(camera_id),
		"frames": frames,
	}


func export(path: String, camera_id: String, fps: int, duration: float, frame_count: int = -1) -> Dictionary:
	if _document == null:
		return {"ok": false, "error": "No document is open."}
	var data := build(camera_id, fps, duration, frame_count)
	if data.is_empty():
		return {"ok": false, "error": "Select a scene camera before exporting a camera track."}
	if path.get_base_dir() != "":
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not write %s." % path}
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return {"ok": true, "path": path, "frame_count": Array(data.get("frames", [])).size(), "error": ""}
