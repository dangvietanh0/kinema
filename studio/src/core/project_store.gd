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

	var kind := _detect_model_kind(uri, bytes)
	if kind == "fbx":
		return {
			"ok": false,
			"error": "FBX needs an editor-side importer that Godot only ships in the editor. Export the model as GLB or OBJ instead.",
		}
	if kind == "obj":
		return _import_obj(uri, bytes, project_dir, fallback_name)
	if kind != "glb" and kind != "gltf":
		return {"ok": false, "error": "Kinema imports glTF (.glb/.gltf) and Wavefront OBJ (.obj) models."}

	var base_name := _display_name_for(uri, fallback_name)
	var extension := kind
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

# Wavefront OBJ is not importable through ResourceLoader in an exported build,
# because Godot's OBJ importer exists only in the editor. The runtime parser in
# obj_importer.gd reads the mesh; this function copies the OBJ, its MTL files
# and diffuse textures into the project and rewrites the relative references so
# the model keeps working after the source folder is gone.
func _import_obj(uri: String, bytes: PackedByteArray, project_dir: String, fallback_name: String) -> Dictionary:
	var text := bytes.get_string_from_utf8()
	if not _looks_like_obj(text):
		return {"ok": false, "error": "This does not look like a Wavefront OBJ file."}

	var models_dir := project_dir.path_join("models")
	DirAccess.make_dir_recursive_absolute(models_dir)
	var safe_base := _safe_slug(fallback_name, "model")
	var folder_name := _unique_dir_name(models_dir, safe_base)
	var folder := models_dir.path_join(folder_name)
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return {"ok": false, "error": "Kinema could not create a folder for this model."}

	var warnings := 0
	var libraries := _obj_mtl_libraries(text)
	if not libraries.is_empty():
		DirAccess.make_dir_recursive_absolute(folder.path_join("materials"))
		DirAccess.make_dir_recursive_absolute(folder.path_join("textures"))
		var mappings := {}
		for raw_library in libraries:
			var chosen := ""
			var source_uri := ""
			for candidate in _reference_candidates(raw_library):
				source_uri = _resolve_sibling_uri(uri, candidate)
				if source_uri != "":
					chosen = candidate
					break
			if source_uri == "":
				warnings += 1
				continue
			var library_bytes := _read_uri_bytes(source_uri)
			if library_bytes.is_empty():
				warnings += 1
				continue
			var library_name := _safe_file_name(chosen.get_file(), "material.mtl")
			if library_name.get_extension().to_lower() != "mtl":
				library_name += ".mtl"
			library_name = _unique_name_in(folder.path_join("materials"), library_name)
			var texture_memo := {}
			var material_text := _rewrite_mtl_textures(
				library_bytes.get_string_from_utf8(), source_uri, folder.path_join("textures"), texture_memo
			)
			var material_path := folder.path_join("materials").path_join(library_name)
			if not _write_text(material_path, material_text):
				warnings += 1
				continue
			warnings += int(texture_memo.get("__missing", 0))
			mappings[chosen] = "materials/" + library_name
		if not mappings.is_empty():
			text = _rewrite_obj_libraries(text, mappings)

	var obj_name := _safe_file_name(_uri_file_name(uri), safe_base + ".obj")
	if obj_name.get_extension().to_lower() != "obj":
		obj_name = safe_base + ".obj"
	if not _write_text(folder.path_join(obj_name), text):
		_remove_dir_recursive(folder)
		return {"ok": false, "error": "Kinema could not write the OBJ into this project."}

	var result := {
		"ok": true,
		"rel_path": "models".path_join(folder_name).path_join(obj_name),
		"name": _display_name_for(uri, fallback_name),
		"extension": "obj",
	}
	if warnings > 0:
		result["warning"] = "Imported, but some MTL or texture files could not be read. Default materials were used."
	return result

func _detect_model_kind(uri: String, bytes: PackedByteArray) -> String:
	if bytes.size() >= 4 and bytes[0] == 0x67 and bytes[1] == 0x6C and bytes[2] == 0x54 and bytes[3] == 0x46:
		return "glb"
	var extension := _uri_file_name(uri).get_extension().to_lower()
	if extension == "fbx" or bytes.size() >= 18 and bytes.slice(0, 18).get_string_from_ascii() == "Kaydara FBX Binary":
		return "fbx"
	var head := bytes.slice(0, mini(bytes.size(), 512)).get_string_from_utf8().strip_edges()
	if extension == "obj":
		return "obj"
	if extension == "gltf" or head.begins_with("{"):
		return "gltf"
	if head.begins_with("v ") or head.begins_with("mtllib ") or head.begins_with("#"):
		return "obj"
	var text_head := bytes.slice(0, mini(bytes.size(), 4096)).get_string_from_utf8()
	if text_head.contains("\nv ") or text_head.contains("\nf "):
		return "obj"
	return ""

func _looks_like_obj(text: String) -> bool:
	# Require both geometry and at least one face. A file that only starts with
	# '#' or contains vertices but no faces cannot produce a renderable mesh, so
	# reject it now instead of importing a placeholder object.
	var has_vertex := false
	var has_face := false
	for raw_line in text.split("\n"):
		var line := raw_line.replace("\t", " ").strip_edges()
		if line.begins_with("v "):
			has_vertex = true
		elif line.begins_with("f "):
			has_face = true
		if has_vertex and has_face:
			return true
	return false

func _uri_file_name(uri: String) -> String:
	var raw := uri.get_file()
	if raw.contains("?"):
		raw = raw.get_slice("?", 0)
	if raw.contains("#"):
		raw = raw.get_slice("#", 0)
	return raw.uri_decode()

func _safe_file_name(value: String, fallback: String) -> String:
	var name := value.get_file().strip_edges()
	if name == "" or name.begins_with("."):
		name = fallback
	for ch in ["\\", "/", ":", "\"", "*", "?", "<", ">", "|"]:
		name = name.replace(ch, "_")
	return name

func _unique_dir_name(parent: String, base: String) -> String:
	var name := base
	var counter := 2
	while DirAccess.dir_exists_absolute(parent.path_join(name)):
		name = "%s-%d" % [base, counter]
		counter += 1
	return name

func _unique_name_in(dir: String, file_name: String) -> String:
	var stem := file_name.get_basename()
	var extension := file_name.get_extension()
	var name := file_name
	var counter := 2
	while FileAccess.file_exists(dir.path_join(name)):
		name = "%s-%d.%s" % [stem, counter, extension] if extension != "" else "%s-%d" % [stem, counter]
		counter += 1
	return name

func _obj_mtl_libraries(text: String) -> Array:
	var libraries := []
	var seen := {}
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if not line.begins_with("mtllib"):
			continue
		var rest := line.substr(6).strip_edges()
		if rest == "" or seen.has(rest):
			continue
		seen[rest] = true
		libraries.append(rest)
	return libraries

func _reference_candidates(reference: String) -> Array:
	var cleaned := reference.strip_edges().trim_prefix("\"").trim_suffix("\"")
	var candidates := [cleaned]
	for token in cleaned.split(" ", false):
		if not candidates.has(token):
			candidates.append(token)
	# Allow "folder with spaces/file.mtl" by retrying every suffix.
	var tokens := cleaned.split(" ", false)
	for i in range(1, tokens.size()):
		var suffix := " ".join(tokens.slice(i))
		if not candidates.has(suffix):
			candidates.append(suffix)
	return candidates

func _resolve_sibling_uri(base_uri: String, reference: String) -> String:
	var cleaned := reference.strip_edges().trim_prefix("\"").trim_suffix("\"").replace("\\", "/")
	if cleaned == "":
		return ""
	var candidates := []
	if cleaned.is_absolute_path():
		candidates.append(cleaned)
	candidates.append(base_uri.get_base_dir().path_join(cleaned))
	candidates.append(base_uri.get_base_dir().path_join(cleaned.get_file()))
	for candidate in candidates:
		if _file_readable(candidate):
			return candidate
	for candidate in candidates:
		if _file_readable(candidate.uri_decode()):
			return candidate.uri_decode()
	return ""

func _file_readable(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	file.close()
	return true

func _read_uri_bytes(uri: String) -> PackedByteArray:
	var file := FileAccess.open(uri, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes

func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	var error := file.get_error()
	file.close()
	return error == OK

func _rewrite_obj_libraries(text: String, mappings: Dictionary) -> String:
	var output := PackedStringArray()
	for raw_line in text.split("\n"):
		var stripped := raw_line.strip_edges()
		if not stripped.begins_with("mtllib"):
			output.append(raw_line)
			continue
		var rest := stripped.substr(6).strip_edges()
		if mappings.has(rest):
			output.append("mtllib " + str(mappings[rest]))
			continue
		var replaced := PackedStringArray()
		for token in rest.split(" ", false):
			replaced.append(str(mappings.get(token, token)))
		output.append("mtllib " + " ".join(replaced))
	return "\n".join(output)

func _rewrite_mtl_textures(mtl_text: String, mtl_uri: String, texture_dir: String, memo: Dictionary) -> String:
	var missing := 0
	var output := PackedStringArray()
	for raw_line in mtl_text.split("\n"):
		var stripped := raw_line.strip_edges()
		if not stripped.begins_with("map_Kd"):
			output.append(raw_line)
			continue
		var reference := stripped.substr(6).strip_edges()
		var resolved := ""
		for candidate in _reference_candidates(reference):
			resolved = _resolve_sibling_uri(mtl_uri, candidate)
			if resolved != "":
				break
		if resolved == "":
			missing += 1
			output.append(raw_line)
			continue
		var destination := str(memo.get(resolved, ""))
		if destination == "":
			var texture_name := _safe_file_name(_uri_file_name(resolved), "texture.png")
			texture_name = _unique_name_in(texture_dir, texture_name)
			var texture_bytes := _read_uri_bytes(resolved)
			if texture_bytes.is_empty() or not _write_bytes(texture_dir.path_join(texture_name), texture_bytes):
				missing += 1
				output.append(raw_line)
				continue
			destination = "../textures/" + texture_name
			memo[resolved] = destination
		output.append("map_Kd " + destination)
	memo["__missing"] = missing
	return "\n".join(output)

func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	var error := file.get_error()
	file.close()
	return error == OK

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
