extends RefCounted
## Validated GLB scene exporter.
##
## Builds a copy of the live document scene, strips editor-only markers and
## hidden objects/parts, keeps real cameras, lights and the active animation,
## then writes a binary GLB and re-imports it before the destination is
## accepted. The live document is never mutated.

const EDITOR_ONLY_GROUP := "kinema_editor_only"
const MARKER_META := "kinema_marker_colors"
const ROOT_NAME := "KinemaScene"
const CLIP_NAME := "Clip"


func export_scene(doc, path: String, options: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": false,
		"error": "",
		"path": "",
		"bytes": 0,
		"nodes": 0,
		"meshes": 0,
		"animations": 0,
	}
	if doc == null:
		return _fail(result, null, "There is no document to export.")
	if path.strip_edges() == "" or path.get_extension().to_lower() != "glb":
		return _fail(result, null, "Choose a .glb destination.")
	var live_objects: Array = doc.objects if doc.get("objects") != null else []
	if live_objects.is_empty():
		return _fail(result, null, "The scene is empty.")
	var selection_only := bool(options.get("selection_only", false))
	var selected_id := str(doc.selected_id) if doc.get("selected_id") != null else ""
	if selection_only and (selected_id == "" or doc.get_object(selected_id).is_empty()):
		return _fail(result, null, "Select one object to export.")

	var resolved := _resolve_path(path)
	result["path"] = resolved
	var root := Node3D.new()
	root.name = ROOT_NAME
	var skipped_all := true
	for obj in live_objects:
		if not (obj is Dictionary):
			continue
		if not bool((obj as Dictionary).get("visible", true)):
			continue
		var id := str((obj as Dictionary).get("id", ""))
		if selection_only and id != selected_id:
			continue
		var clone := _clone_object(doc, obj as Dictionary)
		if clone == null:
			continue
		root.add_child(clone)
		_strip_clone(clone)
		skipped_all = false
	if skipped_all:
		return _fail(result, root, "The scene has no visible objects to export.")

	var animations_requested := bool(options.get("animations", true))
	var animation_count := _attach_animation(doc, root, animations_requested)

	var state := GLTFState.new()
	var gltf := GLTFDocument.new()
	var err: int = gltf.append_from_scene(root, state)
	if err != OK:
		return _fail(result, root, "The scene could not be prepared for GLB export.")

	var destination_dir := resolved.get_base_dir()
	if destination_dir != "" and not DirAccess.dir_exists_absolute(destination_dir):
		if DirAccess.make_dir_recursive_absolute(destination_dir) != OK:
			return _fail(result, root, "The export folder could not be created.")

	var temp := resolved + ".tmp.glb"
	if FileAccess.file_exists(temp):
		DirAccess.remove_absolute(temp)
	err = gltf.write_to_filesystem(state, temp)
	if err != OK:
		_remove_if_exists(temp)
		return _fail(result, root, "The GLB file could not be written.")

	var validation := _validate_glb(temp, animation_count)
	if validation != "":
		_remove_if_exists(temp)
		return _fail(result, root, validation)

	if DirAccess.rename_absolute(temp, resolved) != OK:
		var data := FileAccess.get_file_as_bytes(temp)
		var out := FileAccess.open(resolved, FileAccess.WRITE)
		if out == null or data.is_empty():
			if out != null:
				out.close()
			_remove_if_exists(temp)
			_remove_if_exists(resolved)
			return _fail(result, root, "The GLB file could not be moved into place.")
		var stored := out.store_buffer(data)
		out.close()
		if not stored:
			_remove_if_exists(temp)
			_remove_if_exists(resolved)
			return _fail(result, root, "The GLB file could not be moved into place.")
		_remove_if_exists(temp)

	var bytes := FileAccess.get_file_as_bytes(resolved)
	result["ok"] = true
	result["error"] = ""
	result["bytes"] = bytes.size()
	result["nodes"] = _count_nodes(root)
	result["meshes"] = _count_meshes(root)
	result["animations"] = animation_count
	root.free()
	return result


func _resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


func _fail(result: Dictionary, root: Node, message: String) -> Dictionary:
	result["ok"] = false
	result["error"] = message
	if root != null:
		if not root.is_queued_for_deletion():
			root.free()
	return result


func _remove_if_exists(path: String) -> void:
	if path != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _clone_object(doc, obj: Dictionary) -> Node3D:
	var id := str(obj.get("id", ""))
	var live: Node3D = doc.nodes.get(id) as Node3D if doc.get("nodes") != null else null
	if live == null:
		return null
	var clone := live.duplicate() as Node3D
	if clone == null:
		return null
	clone.name = live.name
	if str(obj.get("kind", "")) == "import":
		var overrides: Variant = obj.get("part_visibility", {})
		if overrides is Dictionary:
			for part_path in (overrides as Dictionary).keys():
				if bool((overrides as Dictionary)[part_path]):
					continue
				var part := clone.get_node_or_null(NodePath(str(part_path)))
				if part != null:
					clone.remove_child(part)
					part.free()
	return clone


## Removes hidden subtrees and every editor-only marker from the copy.
func _strip_clone(node: Node) -> void:
	for child in node.get_children():
		if _is_editor_only(child) or (child is Node3D and not (child as Node3D).visible):
			node.remove_child(child)
			child.free()
			continue
		_strip_clone(child)


func _is_editor_only(node: Node) -> bool:
	if node.is_in_group(EDITOR_ONLY_GROUP):
		return true
	# Duplicate() carries groups and metadata, so this is only a defensive
	# guard for a marker built before the group was introduced.
	return node.name == "Marker" and node.has_meta(MARKER_META)


func _attach_animation(doc, root: Node3D, requested: bool) -> int:
	if not requested:
		return 0
	var source: Animation = doc.get("animation") as Animation if doc.get("animation") != null else null
	if source == null:
		return 0
	var anim := source.duplicate(true) as Animation
	if anim == null:
		return 0
	for ti in range(anim.get_track_count() - 1, -1, -1):
		var target := str(anim.track_get_path(ti)).split(":")[0]
		if target == "" or root.get_node_or_null(NodePath(target)) == null:
			anim.remove_track(ti)
	if anim.get_track_count() == 0:
		return 0
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.root_node = NodePath("..")
	var library := AnimationLibrary.new()
	library.add_animation(CLIP_NAME, anim)
	player.add_animation_library("", library)
	root.add_child(player)
	return 1


func _validate_glb(path: String, animations: int) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 12 or bytes.slice(0, 4).get_string_from_utf8() != "glTF":
		return "The exported file is not a GLB."
	if bytes.decode_u32(4) != 2:
		return "The exported GLB is not version 2."
	if bytes.decode_u32(8) != bytes.size():
		return "The exported GLB length does not match the declared length."
	var state := GLTFState.new()
	var gltf := GLTFDocument.new()
	var err: int = gltf.append_from_file(path, state)
	if err != OK:
		return "The exported GLB could not be read back."
	var generated: Node = gltf.generate_scene(state)
	if generated == null:
		return "The exported GLB produced no scene."
	var nodes := _count_nodes(generated)
	var failure := ""
	if nodes <= 0:
		failure = "The exported GLB produced an empty scene."
	elif animations > 0:
		var player := _find_animation_player(generated)
		if player == null or player.get_animation_list().is_empty():
			failure = "The exported animation could not be read back."
	generated.free()
	return failure


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count


func _count_meshes(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and (node as MeshInstance3D).mesh != null else 0
	for child in node.get_children():
		count += _count_meshes(child)
	return count
