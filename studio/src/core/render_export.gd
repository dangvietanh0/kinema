extends RefCounted
## Render output helpers.
##
## Still captures are plain PNG files. Frame sequences are captured as numbered
## PNGs and packaged with Godot's own ZIPPacker, so the archive is a real ZIP
## that any editor or video tool can open. There is no video encoder here;
## MP4 export would require a native encoder and is deliberately not faked.

const FRAME_PREFIX := "frame_"
const FRAME_SUFFIX := ".png"

## Zero-padded frame name, e.g. frame_0007.png.
static func frame_name(index: int) -> String:
	return "%s%04d%s" % [FRAME_PREFIX, index, FRAME_SUFFIX]

## Directory for a new sequence render, e.g. user://renders/sequence_2026-10-23_142233.
static func sequence_dir(root: String = "user://renders") -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("T", "_").replace("-", "")
	var base := root.path_join("sequence_" + stamp)
	var path := base
	var serial := 2
	while DirAccess.dir_exists_absolute(path) or FileAccess.file_exists(path):
		path = "%s_%d" % [base, serial]
		serial += 1
	return path

## A collision-free PNG path for a single still.
static func still_path(root: String = "user://renders", label: String = "still") -> String:
	return _unique_path(root, label, ".png")

## A collision-free ZIP path for a frame sequence.
static func archive_path(root: String = "user://renders", label: String = "sequence") -> String:
	return _unique_path(root, label, ".zip")

static func _unique_path(root: String, label: String, extension: String) -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("T", "_").replace("-", "")
	var base := root.path_join("%s_%s" % [label, stamp])
	var path := base + extension
	var serial := 2
	while FileAccess.file_exists(path):
		path = "%s_%d%s" % [base, serial, extension]
		serial += 1
	return path

## Package every regular file in a directory into a ZIP archive.
##
## Files are written in name order so frame sequences stay ordered. Returns
## false when the source cannot be read, contains no files, or the archive
## cannot be written.
static func zip_directory(source_dir: String, zip_path: String) -> bool:
	var dir := DirAccess.open(source_dir)
	if dir == null:
		return false
	var names := PackedStringArray()
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and not entry.begins_with("."):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	if names.is_empty():
		return false
	names.sort()

	var parent := zip_path.get_base_dir()
	if parent != "" and not DirAccess.dir_exists_absolute(parent):
		if DirAccess.make_dir_recursive_absolute(parent) != OK:
			return false

	var packer := ZIPPacker.new()
	if packer.open(zip_path) != OK:
		return false
	var ok := true
	for name in names:
		var bytes := FileAccess.get_file_as_bytes(source_dir.path_join(name))
		if bytes.is_empty():
			ok = false
			break
		if packer.start_file(name) != OK:
			ok = false
			break
		if packer.write_file(bytes) != OK:
			ok = false
			break
		if packer.close_file() != OK:
			ok = false
			break
	packer.close()
	if not ok:
		DirAccess.remove_absolute(zip_path)
	return ok
