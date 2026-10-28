extends RefCounted
## Sequence frame renderer shared by PNG sequence, GIF and MP4 export.
##
## The renderer owns no UI: it seeks the document, waits one frame for the
## mixer/IK/skinning to settle, captures through `EditorView.capture_with_camera`
## at the exact requested size, and writes numbered PNGs. Cancelling removes
## the temporary directory, so a cancelled export never leaves a final output.

const FRAME_PATTERN := "frame_%04d.png"

var _document = null
var _view = null


func setup(document, view) -> void:
	_document = document
	_view = view


static func frame_name(index: int) -> String:
	return FRAME_PATTERN % (index + 1)


## options: width, height, fps, start, end, frame_count, output_dir,
## camera_id, msaa, transparent_bg.
## progress is called with (done, total); cancel returns true to stop.
func render(options: Dictionary, progress: Callable = Callable(), cancel: Callable = Callable()) -> Dictionary:
	if _document == null or _view == null:
		return {"ok": false, "error": "The sequence renderer needs a document and a viewport.", "frames_dir": "", "frame_count": 0}
	var original_time := float(_document.sequence_time()) if _document.has_method("sequence_time") else 0.0
	var was_playing := bool(_document.is_sequence_playing()) if _document.has_method("is_sequence_playing") else false
	if was_playing and _document.has_method("pause_sequence"):
		_document.pause_sequence()
	var width := maxi(2, int(options.get("width", 1280)))
	var height := maxi(2, int(options.get("height", 720)))
	var fps := maxi(1, int(options.get("fps", 24)))
	var start := float(options.get("start", 0.0))
	var end := float(options.get("end", start + 1.0))
	var frame_count := int(options.get("frame_count", 0))
	if frame_count <= 0:
		frame_count = maxi(1, int(round(maxf(1.0 / fps, end - start) * fps)))
	var output_dir := str(options.get("output_dir", ""))
	if output_dir == "":
		output_dir = _unique_dir("user://renders/tmp_" + Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_"))
	else:
		output_dir = _unique_dir(output_dir)
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		_restore_transport(was_playing, original_time)
		return {"ok": false, "error": "Could not create the render folder: %s" % output_dir, "frames_dir": output_dir, "frame_count": 0}
	var camera_id := str(options.get("camera_id", ""))
	var msaa := int(options.get("msaa", 2))
	var transparent_bg := bool(options.get("transparent_bg", false))
	var size := Vector2i(width, height)
	for index in range(frame_count):
		if cancel.is_valid() and bool(cancel.call()):
			_remove_tree(output_dir)
			_restore_transport(was_playing, original_time)
			return {"ok": false, "cancelled": true, "error": "Render cancelled.", "frames_dir": "", "frame_count": 0}
		var time := start + float(index) / float(fps)
		if _document.has_method("seek_sequence"):
			_document.seek_sequence(time, true)
		if _document.is_inside_tree():
			await _document.get_tree().process_frame
		if _document.rig_system != null and _document.rig_system.has_method("solve_ik"):
			_document.rig_system.solve_ik("")
		var camera := _camera_for(camera_id)
		var image: Image = await _view.capture_with_camera(size, msaa, camera["transform"], camera["fov"], transparent_bg)
		if image == null:
			_restore_transport(was_playing, original_time)
			return {"ok": false, "error": "Capture failed at frame %d." % (index + 1), "frames_dir": output_dir, "frame_count": index}
		if image.get_width() != width or image.get_height() != height:
			image.resize(width, height, Image.INTERPOLATE_LANCZOS)
		var path := output_dir.path_join(frame_name(index))
		if image.save_png(path) != OK:
			_restore_transport(was_playing, original_time)
			return {"ok": false, "error": "Could not write frame %d." % (index + 1), "frames_dir": output_dir, "frame_count": index}
		if progress.is_valid():
			progress.call(index + 1, frame_count)
	_restore_transport(was_playing, original_time)
	return {
		"ok": true,
		"cancelled": false,
		"frames_dir": output_dir,
		"frame_count": frame_count,
		"width": width,
		"height": height,
		"fps": fps,
		"error": "",
	}


func _restore_transport(was_playing: bool, original_time: float) -> void:
	if _document == null:
		return
	if _document.has_method("seek_sequence"):
		_document.seek_sequence(original_time, true)
	if was_playing and _document.has_method("play_sequence"):
		_document.play_sequence()


func _camera_for(camera_id: String) -> Dictionary:
	if camera_id != "" and _document != null:
		var node: Node3D = _document.nodes.get(camera_id)
		if node != null:
			var fov := 45.0
			var camera_node: Camera3D = node.get_node_or_null("Camera") as Camera3D
			if camera_node != null:
				fov = camera_node.fov
			else:
				var obj: Dictionary = _document.get_object(camera_id)
				fov = float(obj.get("camera_fov", 45.0))
			return {"transform": node.global_transform, "fov": fov}
	if _view != null:
		var editor_camera = _view.get("_camera")
		if editor_camera is Camera3D and is_instance_valid(editor_camera):
			return {"transform": editor_camera.global_transform, "fov": editor_camera.fov}
	return {"transform": Transform3D.IDENTITY, "fov": 45.0}


func _unique_dir(base: String) -> String:
	var path := base
	var serial := 2
	while DirAccess.dir_exists_absolute(path) or FileAccess.file_exists(path):
		path = "%s_%d" % [base, serial]
		serial += 1
	return path


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
