extends Node
## Internal project storage for Kinema Studio.
##
## A project is a directory under `user://projects/<id>/` containing a
## `project.json` document and, optionally, a `models/` folder. Nothing is
## written to shared storage unless the user explicitly exports something.
## The store is autoloaded as `Store`.

signal recents_changed

const ROOT := "user://projects"
const RECENT_FILE := "user://recent_projects.json"
const PROJECT_FILE := "project.json"
const MAX_RECENTS := 12

var _recents: Array = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	_load_recents()

# -------------------------------------------------------------------------
# Project records
# -------------------------------------------------------------------------

func create_record(title: String) -> Dictionary:
	var clean := title.strip_edges()
	if clean == "":
		clean = "Untitled Project"
	var id := _unique_id(clean)
	var path := ROOT.path_join(id)
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		push_error("Kinema: could not create project directory at %s (error %d)." % [path, err])
		return {}
	return {
		"id": id,
		"title": clean,
		"path": path,
		"modified": Time.get_unix_time_from_system(),
	}

func save_project(doc) -> bool:
	if doc == null or not is_instance_valid(doc):
		return false
	if doc.project_id == "":
		doc.project_id = _unique_id(doc.title)
	if doc.project_dir == "":
		doc.project_dir = ROOT.path_join(doc.project_id)
	DirAccess.make_dir_recursive_absolute(doc.project_dir)

	var data: Dictionary = doc.to_data()
	var path: String = doc.project_dir.path_join(PROJECT_FILE)
	var err := _write_json(path, data)
	if err != OK:
		push_error("Kinema: failed to save project (error %d)." % err)
		return false

	doc.mark_saved()
	_touch_recent(doc)
	return true

func load_project(id: String) -> Dictionary:
	var meta := find_meta(id)
	if meta.is_empty():
		return {}
	var path: String = str(meta.get("path", ""))
	var project_path := path.path_join(PROJECT_FILE)
	var f := FileAccess.open(project_path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_warning("Kinema: project file is not valid JSON: %s" % project_path)
		return {}
	meta["title"] = str(parsed.get("title", meta.get("title", "Untitled")))
	return {"meta": meta, "data": parsed}

func find_meta(id: String) -> Dictionary:
	for entry in _recents:
		if str(entry.get("id", "")) == id:
			var meta: Dictionary = entry.duplicate(true)
			if meta.get("path", "") == "":
				meta["path"] = ROOT.path_join(id)
			return meta
	var path := ROOT.path_join(id)
	if not FileAccess.file_exists(path.path_join(PROJECT_FILE)):
		return {}
	return {
		"id": id,
		"title": "Untitled",
		"path": path,
		"modified": 0.0,
	}

func recent_projects() -> Array:
	return _recents.duplicate(true)

func rename_project(id: String, new_title: String) -> bool:
	var clean := new_title.strip_edges()
	if clean == "":
		return false
	var meta := find_meta(id)
	if meta.is_empty():
		return false
	var loaded := load_project(id)
	if loaded.is_empty():
		return false
	var data: Dictionary = loaded["data"]
	data["title"] = clean
	var err := _write_json(str(meta["path"]).path_join(PROJECT_FILE), data)
	if err != OK:
		return false
	for entry in _recents:
		if str(entry.get("id", "")) == id:
			entry["title"] = clean
			entry["modified"] = Time.get_unix_time_from_system()
	_save_recents()
	recents_changed.emit()
	return true

func delete_project(id: String) -> bool:
	var meta := find_meta(id)
	if meta.is_empty():
		return false
	var path := str(meta.get("path", ""))
	if not path.begins_with(ROOT + "/"):
		return false
	_remove_dir_recursive(path)
	var before := _recents.size()
	for i in range(_recents.size() - 1, -1, -1):
		if str(_recents[i].get("id", "")) == id:
			_recents.remove_at(i)
	_save_recents()
	if _recents.size() != before:
		recents_changed.emit()
	return true

# -------------------------------------------------------------------------
# Imported models
# -------------------------------------------------------------------------

func import_model(uri: String, project_dir: String, fallback_name: String = "Model") -> Dictionary:
	if uri == "" or project_dir == "":
		return {"ok": false, "error": "No destination project is open."}
	var source := FileAccess.open(uri, FileAccess.READ)
	if source == null:
		return {"ok": false, "error": "This file could not be read. Try selecting it again."}
	var bytes := source.get_buffer(source.get_length())
	source.close()
	if bytes.is_empty():
		return {"ok": false, "error": "The selected file is empty."}

	var is_glb := bytes.size() >= 4 and bytes[0] == 0x67 and bytes[1] == 0x6C and bytes[2] == 0x54 and bytes[3] == 0x46
	var is_gltf := false
	if not is_glb and bytes.size() > 2:
		var head := bytes.slice(0, mini(bytes.size(), 64)).get_string_from_utf8().strip_edges()
		is_gltf = head.begins_with("{")
	if not is_glb and not is_gltf:
		return {"ok": false, "error": "Kinema imports binary glTF (.glb) or embedded glTF (.gltf) files."}

	var base_name := _display_name_for(uri, fallback_name)
	var extension := "glb" if is_glb else "gltf"
	var temp_path := "user://import_%d.%s" % [Time.get_ticks_msec(), extension]
	var temp := FileAccess.open(temp_path, FileAccess.WRITE)
	if temp == null:
		return {"ok": false, "error": "Kinema could not create a temporary file for the import."}
	temp.store_buffer(bytes)
	temp.close()

	# Validate before the model enters the project so broken files do not
	# leave a permanent, unreadable object in the scene.
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_file(temp_path, state)
	var node: Node = null
	if err == OK:
		node = gltf.generate_scene(state)
	if node == null:
		DirAccess.remove_absolute(temp_path)
		return {
			"ok": false,
			"error": "The model could not be parsed. If this is a .gltf with external buffers or textures, export it as a .glb and try again.",
		}
	node.free()

	var models_dir := project_dir.path_join("models")
	DirAccess.make_dir_recursive_absolute(models_dir)
	var safe_base := _safe_slug(base_name, "model")
	var file_name := safe_base + "." + extension
	var counter := 2
	while FileAccess.file_exists(models_dir.path_join(file_name)):
		file_name = "%s-%d.%s" % [safe_base, counter, extension]
		counter += 1
	var dest_path := models_dir.path_join(file_name)
	var dest := FileAccess.open(dest_path, FileAccess.WRITE)
	if dest == null:
		DirAccess.remove_absolute(temp_path)
		return {"ok": false, "error": "Kinema could not copy the model into this project."}
	dest.store_buffer(bytes)
	var write_error := dest.get_error()
	dest.close()
	DirAccess.remove_absolute(temp_path)
	if write_error != OK:
		DirAccess.remove_absolute(dest_path)
		return {"ok": false, "error": "Kinema could not finish copying the model."}
	return {
		"ok": true,
		"rel_path": "models".path_join(file_name),
		"name": base_name,
		"extension": extension,
	}

# -------------------------------------------------------------------------
# Recent list and filesystem helpers
# -------------------------------------------------------------------------

func _touch_recent(doc) -> void:
	var id: String = doc.project_id
	var entry := {
		"id": id,
		"title": doc.title,
		"path": doc.project_dir,
		"modified": Time.get_unix_time_from_system(),
		"objects": doc.objects.size(),
		"duration": doc.duration,
		"fps": doc.fps,
	}
	for i in range(_recents.size() - 1, -1, -1):
		if str(_recents[i].get("id", "")) == id:
			_recents.remove_at(i)
	_recents.push_front(entry)
	while _recents.size() > MAX_RECENTS:
		_recents.pop_back()
	_save_recents()
	recents_changed.emit()

func _load_recents() -> void:
	_recents.clear()
	if not FileAccess.file_exists(RECENT_FILE):
		return
	var f := FileAccess.open(RECENT_FILE, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Array:
		return
	var changed := false
	for raw in parsed:
		if not raw is Dictionary:
			changed = true
			continue
		var meta := raw as Dictionary
		var id := str(meta.get("id", ""))
		var path := str(meta.get("path", ""))
		if id == "" or path == "":
			changed = true
			continue
		if not FileAccess.file_exists(path.path_join(PROJECT_FILE)):
			changed = true
			continue
		_recents.append(meta)
	if changed:
		_save_recents()

func _save_recents() -> void:
	_write_json(RECENT_FILE, _recents)

func _write_json(path: String, data: Variant) -> Error:
	var text := JSON.stringify(data, "\t")
	var temp := path + ".tmp"
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		return ERR_CANT_CREATE
	f.store_string(text)
	var err := f.get_error()
	f.close()
	if err != OK:
		DirAccess.remove_absolute(temp)
		return err
	var rename_err := DirAccess.rename_absolute(temp, path)
	if rename_err != OK:
		# Some filesystem providers refuse to replace an existing file.
		DirAccess.remove_absolute(path)
		rename_err = DirAccess.rename_absolute(temp, path)
	if rename_err != OK:
		DirAccess.remove_absolute(temp)
		return rename_err
	return OK

func _unique_id(title: String) -> String:
	var stamp := str(int(Time.get_unix_time_from_system()))
	var slug := _safe_slug(title, "project")
	var base := "%s-%s" % [stamp, slug]
	var candidate := base
	var n := 2
	while DirAccess.dir_exists_absolute(ROOT.path_join(candidate)):
		candidate = "%s-%d" % [base, n]
		n += 1
	return candidate

func _safe_slug(value: String, fallback: String) -> String:
	var source := value.strip_edges().to_lower()
	var out := ""
	for i in range(source.length()):
		var ch := source.substr(i, 1)
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch == "-" or ch == "_":
			out += "-"
		elif ch == " " or ch == ".":
			out += "-"
	if out.length() > 40:
		out = out.substr(0, 40)
	while out.begins_with("-"):
		out = out.substr(1)
	while out.ends_with("-"):
		out = out.substr(0, out.length() - 1)
	if out == "":
		out = fallback
	return out

func _display_name_for(uri: String, fallback: String) -> String:
	var raw := uri.get_file()
	if raw.contains("?"):
		raw = raw.get_slice("?", 0)
	if raw.contains("#"):
		raw = raw.get_slice("#", 0)
	raw = raw.uri_decode()
	var base := raw.get_basename().strip_edges()
	if base == "" or base == "." or base == "/" or base.to_lower() == "document":
		base = fallback
	return base

func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child := path.path_join(entry)
			if dir.current_is_dir():
				_remove_dir_recursive(child)
			else:
				DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
