extends RefCounted
## Multi-clip animation subsystem.
##
## Clips own Animation resources. Layers own strips that reference clips. The
## document keeps `doc.duration`/`doc.current_time` clip-local and the system
## owns the global sequence clock. Only one of the two clocks runs at a time.
##
## Ownership: `Document` creates one instance in `_init()` and never frees it
## during `_clear_runtime()`; `reset()` clears subsystem state instead.

const ClipMixerScript = preload("res://src/core/clip_mixer.gd")
const POSITION := Animation.TYPE_POSITION_3D
const ROTATION := Animation.TYPE_ROTATION_3D
const SCALE := Animation.TYPE_SCALE_3D
const SUPPORTED_TYPES := [POSITION, ROTATION, SCALE]
const MIN_DURATION := 0.04
const IMPORTED_LAYER := "Imported"

var _document = null
var _clips: Dictionary = {}
var _layers: Array = []
var _active_clip := ""
var _active_layer := ""
var _sequence_time := 0.0
var _sequence_playing := false
var _next_clip := 1
var _next_layer := 1
var _next_strip := 1
var _silent := false

## Last concrete reason a destructive operation was refused.
var last_error := ""


func setup(document) -> void:
	_document = document


func reset() -> void:
	_clear_model()
	_sequence_time = 0.0
	_sequence_playing = false
	_silent = false
	last_error = ""


func _clear_model() -> void:
	_clips.clear()
	_layers.clear()
	_active_clip = ""
	_active_layer = ""
	_next_clip = 1
	_next_layer = 1
	_next_strip = 1


# -------------------------------------------------------------------------
# Clip model
# -------------------------------------------------------------------------

func ensure_default_clip() -> void:
	if not _clips.is_empty():
		_ensure_active()
		return
	var anim: Animation = null
	if _document != null and _document.animation != null:
		anim = _document.animation
	if anim == null:
		anim = Animation.new()
		anim.length = _document_duration()
		anim.loop_mode = Animation.LOOP_LINEAR if _document_loop() else Animation.LOOP_NONE
	var clip_id := _new_clip_id()
	_clips[clip_id] = {"id": clip_id, "name": "Take 01", "animation": anim}
	_active_clip = clip_id
	_ensure_default_layer(anim.length)


func _ensure_default_layer(duration: float) -> void:
	if not _layers.is_empty():
		return
	var layer_id := "layer_base"
	if _layer_exists(layer_id):
		layer_id = _new_layer_id()
	var clip_id := _active_clip if _clips.has(_active_clip) else _first_clip_id()
	if clip_id == "":
		return
	var strip := {
		"id": _new_strip_id(),
		"clip": clip_id,
		"start": 0.0,
		"trim_start": 0.0,
		"trim_end": maxf(MIN_DURATION, duration),
		"speed": 1.0,
		"weight": 1.0,
		"fade_in": 0.0,
		"fade_out": 0.0,
		"ease": 1.0,
	}
	_layers.append({
		"id": layer_id,
		"name": "Base",
		"weight": 1.0,
		"blend": "override",
		"muted": false,
		"solo": false,
		"strips": [strip],
	})
	_active_layer = layer_id


func _ensure_active() -> void:
	if _clips.is_empty():
		var anim := Animation.new()
		anim.length = _document_duration()
		anim.loop_mode = Animation.LOOP_LINEAR if _document_loop() else Animation.LOOP_NONE
		var clip_id := _new_clip_id()
		_clips[clip_id] = {"id": clip_id, "name": "Take 01", "animation": anim}
	if not _clips.has(_active_clip):
		_active_clip = _first_clip_id()
	if _layers.is_empty():
		_ensure_default_layer(_clip_length(_active_clip))
	else:
		if not _layer_exists(_active_layer):
			_active_layer = str(_layers[0].get("id", ""))
		for layer in _layers:
			if not layer.get("strips", []) is Array:
				layer["strips"] = []
			var valid: Array = []
			for strip in layer.get("strips", []):
				if not strip is Dictionary:
					continue
				if _clips.has(str(strip.get("clip", ""))):
					valid.append(strip)
				else:
					push_warning("Kinema: dropped a strip that referenced a missing clip.")
			layer["strips"] = valid


func create_clip(name: String, duration: float) -> String:
	var clip_id := _new_clip_id()
	var anim := Animation.new()
	anim.length = maxf(MIN_DURATION, duration)
	anim.loop_mode = Animation.LOOP_LINEAR if _document_loop() else Animation.LOOP_NONE
	_clips[clip_id] = {
		"id": clip_id,
		"name": _unique_clip_name(name if name.strip_edges() != "" else "Clip"),
		"animation": anim,
	}
	if _active_clip == "":
		_active_clip = clip_id
	_notify_clips()
	return clip_id


func duplicate_clip(id: String) -> String:
	if not _clips.has(id):
		last_error = "The clip no longer exists."
		return ""
	var source: Dictionary = _clips[id]
	var source_anim: Animation = source.get("animation")
	if source_anim == null:
		return ""
	var copy: Animation = source_anim.duplicate(true)
	if copy == null:
		copy = Animation.new()
		copy.length = source_anim.length
		copy.loop_mode = source_anim.loop_mode
	var clip_id := _new_clip_id()
	_clips[clip_id] = {
		"id": clip_id,
		"name": _unique_clip_name(str(source.get("name", "Clip")) + " Copy"),
		"animation": copy,
	}
	_notify_clips()
	return clip_id


func delete_clip(id: String) -> bool:
	last_error = ""
	if not _clips.has(id):
		last_error = "The clip no longer exists."
		return false
	if _clips.size() <= 1:
		last_error = "A project needs at least one clip."
		return false
	for layer in _layers:
		for strip in layer.get("strips", []):
			if str(strip.get("clip", "")) == id:
				last_error = "Clip '%s' is used by a strip. Delete the strip first." % str(_clips[id].get("name", id))
				return false
	_clips.erase(id)
	if _active_clip == id:
		_active_clip = _first_clip_id()
	_notify_clips()
	return true


func rename_clip(id: String, name: String) -> void:
	if not _clips.has(id):
		return
	var clean := name.strip_edges()
	if clean == "":
		return
	_clips[id]["name"] = clean
	_notify_clips()


func clip_ids() -> PackedStringArray:
	return PackedStringArray(_clips.keys())


func get_clip(id: String) -> Dictionary:
	if not _clips.has(id):
		return {}
	var clip: Dictionary = _clips[id]
	var anim: Animation = clip.get("animation")
	return {
		"id": id,
		"name": str(clip.get("name", "")),
		"duration": maxf(MIN_DURATION, anim.length) if anim != null else MIN_DURATION,
		"loop": anim != null and anim.loop_mode != Animation.LOOP_NONE,
		"track_count": anim.get_track_count() if anim != null else 0,
	}


func animation_for(id: String) -> Animation:
	if not _clips.has(id):
		return null
	return _clips[id].get("animation")


func active_animation() -> Animation:
	if _clips.has(_active_clip):
		return _clips[_active_clip].get("animation")
	if _document != null:
		return _document.animation
	return null


func set_active_clip(id: String) -> void:
	if _clips.has(id):
		_active_clip = id


func active_clip_id() -> String:
	return _active_clip


func set_clip_duration(id: String, duration: float) -> void:
	if not _clips.has(id):
		return
	var anim: Animation = _clips[id].get("animation")
	if anim == null:
		return
	var next := maxf(MIN_DURATION, duration)
	anim.length = next
	for layer in _layers:
		for strip in layer.get("strips", []):
			if str(strip.get("clip", "")) != id:
				continue
			strip["trim_start"] = clampf(float(strip.get("trim_start", 0.0)), 0.0, next)
			strip["trim_end"] = clampf(float(strip.get("trim_end", next)), float(strip["trim_start"]) + 0.001, next)
	_notify_clips()


func set_clip_loop(id: String, enabled: bool) -> void:
	if not _clips.has(id):
		return
	var anim: Animation = _clips[id].get("animation")
	if anim == null:
		return
	anim.loop_mode = Animation.LOOP_LINEAR if enabled else Animation.LOOP_NONE
	_notify_clips()


# -------------------------------------------------------------------------
# Layers and strips
# -------------------------------------------------------------------------

func add_layer(name: String) -> String:
	var layer_id := _new_layer_id()
	_layers.append({
		"id": layer_id,
		"name": _unique_layer_name(name if name.strip_edges() != "" else "Layer"),
		"weight": 1.0,
		"blend": "override",
		"muted": false,
		"solo": false,
		"strips": [],
	})
	if _active_layer == "":
		_active_layer = layer_id
	_notify_clips()
	return layer_id


func delete_layer(id: String) -> bool:
	last_error = ""
	if not _layer_exists(id):
		last_error = "The layer no longer exists."
		return false
	if _layers.size() <= 1:
		last_error = "A project needs at least one layer."
		return false
	for index in range(_layers.size()):
		if str(_layers[index].get("id", "")) == id:
			_layers.remove_at(index)
			break
	if _active_layer == id:
		_active_layer = str(_layers[0].get("id", ""))
	_notify_clips()
	return true


func layers() -> Array:
	return _layers.duplicate(true)


func get_layer(id: String) -> Dictionary:
	for layer in _layers:
		if str(layer.get("id", "")) == id:
			return layer.duplicate(true)
	return {}


func update_layer(id: String, patch: Dictionary) -> void:
	for layer in _layers:
		if str(layer.get("id", "")) != id:
			continue
		if patch.has("name"):
			var clean := str(patch["name"]).strip_edges()
			if clean != "":
				layer["name"] = clean
		if patch.has("weight"):
			layer["weight"] = clampf(float(patch["weight"]), 0.0, 1.0)
		if patch.has("blend"):
			var blend := str(patch["blend"])
			layer["blend"] = blend if blend in ["override", "additive"] else "override"
		if patch.has("muted"):
			layer["muted"] = bool(patch["muted"])
		if patch.has("solo"):
			layer["solo"] = bool(patch["solo"])
		_notify_clips()
		return


func active_layer_id() -> String:
	return _active_layer


func set_active_layer(id: String) -> void:
	if _layer_exists(id):
		_active_layer = id


func add_strip(layer_id: String, clip_id: String, start: float) -> String:
	if not _layer_exists(layer_id) or not _clips.has(clip_id):
		last_error = "The layer or clip no longer exists."
		return ""
	var strip_id := _new_strip_id()
	var length := _clip_length(clip_id)
	var strip := {
		"id": strip_id,
		"clip": clip_id,
		"start": maxf(0.0, start),
		"trim_start": 0.0,
		"trim_end": length,
		"speed": 1.0,
		"weight": 1.0,
		"fade_in": 0.0,
		"fade_out": 0.0,
		"ease": 1.0,
	}
	for layer in _layers:
		if str(layer.get("id", "")) == layer_id:
			layer["strips"].append(strip)
			break
	_notify_clips()
	return strip_id


func update_strip(strip_id: String, patch: Dictionary) -> void:
	var found := _find_strip(strip_id)
	if found.is_empty():
		return
	var strip: Dictionary = found["strip"]
	var clip: Animation = animation_for(str(strip.get("clip", "")))
	if clip == null:
		return
	var length := maxf(0.001, clip.length)
	if patch.has("start"):
		strip["start"] = maxf(0.0, float(patch["start"]))
	if patch.has("trim_start"):
		strip["trim_start"] = clampf(float(patch["trim_start"]), 0.0, length)
	if patch.has("trim_end"):
		strip["trim_end"] = clampf(float(patch["trim_end"]), float(strip.get("trim_start", 0.0)) + 0.001, length)
	if float(strip.get("trim_end", length)) <= float(strip.get("trim_start", 0.0)):
		strip["trim_end"] = minf(length, float(strip.get("trim_start", 0.0)) + 0.001)
	if patch.has("speed"):
		strip["speed"] = clampf(float(patch["speed"]), 0.05, 8.0)
	if patch.has("weight"):
		strip["weight"] = clampf(float(patch["weight"]), 0.0, 1.0)
	if patch.has("ease"):
		strip["ease"] = clampf(float(patch["ease"]), 0.0, 4.0)
	if patch.has("fade_in"):
		strip["fade_in"] = maxf(0.0, float(patch["fade_in"]))
	if patch.has("fade_out"):
		strip["fade_out"] = maxf(0.0, float(patch["fade_out"]))
	_clamp_fades(strip, length)
	_notify_clips()


func delete_strip(strip_id: String) -> void:
	for layer in _layers:
		var strips: Array = layer.get("strips", [])
		for index in range(strips.size() - 1, -1, -1):
			if str(strips[index].get("id", "")) == strip_id:
				strips.remove_at(index)
				_notify_clips()
				return


func get_strip(strip_id: String) -> Dictionary:
	var found := _find_strip(strip_id)
	if found.is_empty():
		return {}
	var strip: Dictionary = found["strip"]
	var copy := strip.duplicate(true)
	copy["layer_id"] = str(found["layer"].get("id", ""))
	copy["layer_name"] = str(found["layer"].get("name", ""))
	return copy


func sequence_duration() -> float:
	var end := 0.0
	for layer in _layers:
		if bool(layer.get("muted", false)):
			continue
		for strip in layer.get("strips", []):
			end = maxf(end, _strip_end(strip))
	return maxf(MIN_DURATION, end)


func strip_at(time: float) -> Dictionary:
	var has_solo := false
	for layer in _layers:
		if bool(layer.get("solo", false)) and not bool(layer.get("muted", false)):
			has_solo = true
	for index in range(_layers.size() - 1, -1, -1):
		var layer: Dictionary = _layers[index]
		if bool(layer.get("muted", false)):
			continue
		if has_solo and not bool(layer.get("solo", false)):
			continue
		var best: Dictionary = {}
		var best_start := -INF
		for strip in layer.get("strips", []):
			if not _strip_covers(strip, time):
				continue
			var start := float(strip.get("start", 0.0))
			if start >= best_start:
				best_start = start
				best = strip.duplicate(true)
				best["layer_id"] = str(layer.get("id", ""))
				best["layer_name"] = str(layer.get("name", ""))
		if not best.is_empty():
			return best
	return {}


func local_time(strip: Dictionary, time: float) -> float:
	var clip: Animation = animation_for(str(strip.get("clip", "")))
	if clip == null:
		return 0.0
	var length := maxf(0.001, clip.length)
	var trim_start := clampf(float(strip.get("trim_start", 0.0)), 0.0, length)
	var trim_end := clampf(float(strip.get("trim_end", length)), trim_start + 0.001, length)
	var speed := maxf(0.05, float(strip.get("speed", 1.0)))
	var span := (trim_end - trim_start) / speed
	var start := maxf(0.0, float(strip.get("start", 0.0)))
	var u := 0.0
	if span > 0.00001:
		u = clampf((time - start) / span, 0.0, 1.0)
	var ease := clampf(float(strip.get("ease", 1.0)), 0.0, 4.0)
	if ease <= 0.0001:
		u = 0.0
	elif not is_equal_approx(ease, 1.0):
		u = pow(u, ease)
	var local := trim_start + u * (trim_end - trim_start)
	if clip.loop_mode != Animation.LOOP_NONE:
		local = fposmod(local, length)
	else:
		local = clampf(local, trim_start, trim_end)
	return local


# -------------------------------------------------------------------------
# Evaluation and application
# -------------------------------------------------------------------------

func evaluate(time: float) -> Dictionary:
	if _document == null:
		return {"objects": {}, "bones": {}}
	var animations: Dictionary = {}
	for id in _clips.keys():
		var anim: Animation = _clips[id].get("animation")
		if anim != null:
			animations[id] = anim
	var object_ids := PackedStringArray()
	for obj in _document.objects:
		object_ids.append(str(obj.get("id", "")))
	var base_poses := _base_poses()
	var bones := _bone_paths()
	var result: Dictionary = ClipMixerScript.evaluate(animations, _layers, time, object_ids, base_poses, bones)
	_merge_node_aliases(result)
	return result


func _base_poses() -> Dictionary:
	var poses: Dictionary = {}
	if _document == null:
		return poses
	for obj in _document.objects:
		var id := str(obj.get("id", ""))
		var node: Node = _document.nodes.get(id)
		var node_name := str(node.name) if node != null else ""
		var pose := {
			"position": _as_vec3(obj.get("position", Vector3.ZERO)),
			"rotation": _as_quat(obj.get("rotation", Quaternion.IDENTITY)),
			"scale": _as_vec3(obj.get("scale", Vector3.ONE)),
		}
		poses[id] = pose
		if node_name != "":
			poses[node_name] = pose
		if str(obj.get("kind", "")) == "import" and node != null:
			_collect_import_bases(node, node_name, poses)
	return poses


func _collect_import_bases(root: Node, root_name: String, poses: Dictionary) -> void:
	for child in root.get_children():
		var rel := str(root.get_path_to(child))
		var key := root_name + "/" + rel
		if child is Node3D:
			poses[key] = {
				"position": (child as Node3D).position,
				"rotation": (child as Node3D).quaternion,
				"scale": (child as Node3D).scale,
			}
		_collect_import_bases(child, root_name, poses)


func _bone_paths() -> Dictionary:
	var paths: Dictionary = {}
	for id in _clips.keys():
		var anim: Animation = _clips[id].get("animation")
		if anim == null:
			continue
		for track_index in range(anim.get_track_count()):
			if anim.track_get_type(track_index) != ROTATION:
				continue
			var path := str(anim.track_get_path(track_index))
			if path.find("/Skeleton3D") < 0:
				continue
			var colon := path.find(":")
			if colon < 0:
				continue
			var node_path := path.substr(0, colon)
			var bone := path.substr(colon + 1)
			var marker := node_path.find("/Skeleton3D")
			var rig_prefix := node_path.substr(0, marker)
			var rig_node := _resolve_target_node(rig_prefix)
			var skeleton: Skeleton3D = null
			if rig_node is Skeleton3D:
				skeleton = rig_node
			elif rig_node != null:
				skeleton = rig_node.find_child("Skeleton3D", true, false) as Skeleton3D
			var base := Quaternion.IDENTITY
			if skeleton != null:
				var bone_index := skeleton.find_bone(bone)
				if bone_index >= 0:
					base = skeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion()
			paths[path] = {
				"rig_id": _object_id_for_prefix(rig_prefix),
				"bone": bone,
				"base": base,
			}
	return paths


func _merge_node_aliases(result: Dictionary) -> void:
	if _document == null:
		return
	var objects: Dictionary = result.get("objects", {})
	for id in _document.nodes.keys():
		var node: Node = _document.nodes[id]
		var alias := str(node.name)
		if alias == str(id) or not objects.has(alias):
			continue
		objects[id] = objects[alias]
		objects.erase(alias)
	result["objects"] = objects


func _apply_result(result: Dictionary) -> void:
	if _document == null:
		return
	for key in result.get("objects", {}).keys():
		var node := _resolve_target_node(str(key))
		if node is Node3D:
			var pose: Dictionary = result["objects"][key]
			(node as Node3D).position = _as_vec3(pose.get("position", Vector3.ZERO))
			(node as Node3D).quaternion = _as_quat(pose.get("rotation", Quaternion.IDENTITY))
			(node as Node3D).scale = _as_vec3(pose.get("scale", Vector3.ONE))
	var bones: Dictionary = result.get("bones", {})
	for rig_id in bones.keys():
		var rig_node: Node = _document.nodes.get(str(rig_id))
		if rig_node == null:
			rig_node = _resolve_target_node(str(rig_id))
		if rig_node == null:
			continue
		var skeleton: Skeleton3D = null
		if rig_node is Skeleton3D:
			skeleton = rig_node
		else:
			skeleton = rig_node.find_child("Skeleton3D", true, false) as Skeleton3D
		if skeleton == null:
			continue
		var rig_bones: Dictionary = bones[rig_id]
		for bone in rig_bones.keys():
			var bone_index := skeleton.find_bone(str(bone))
			if bone_index < 0:
				continue
			var data: Dictionary = rig_bones[bone]
			skeleton.set_bone_pose_rotation(bone_index, _as_quat(data.get("rotation", Quaternion.IDENTITY)))


func _resolve_target_node(key: String) -> Node:
	if _document == null or key == "":
		return null
	if _document.nodes.has(key):
		return _document.nodes[key]
	var direct: Node = _document.get_node_or_null(NodePath(key))
	if direct != null:
		return direct
	var slash := key.find("/")
	if slash >= 0:
		var root_name := key.substr(0, slash)
		var relative := key.substr(slash + 1)
		var root: Node = _document.get_node_or_null(NodePath(root_name))
		if root != null:
			var nested: Node = root.get_node_or_null(NodePath(relative))
			if nested != null:
				return nested
			return root.find_node(relative, true, false)
	return _document.find_node(key, true, false)


func _object_id_for_prefix(prefix: String) -> String:
	if _document == null:
		return prefix
	var first := prefix.get_slice("/", 0)
	for id in _document.nodes.keys():
		var node: Node = _document.nodes[id]
		if str(node.name) == first:
			return str(id)
	return prefix


# -------------------------------------------------------------------------
# Sequence transport
# -------------------------------------------------------------------------

func sequence_time() -> float:
	return _sequence_time


func active_local_time() -> float:
	var strip := strip_at(_sequence_time)
	if strip.is_empty():
		return 0.0
	return local_time(strip, _sequence_time)


func is_sequence_playing() -> bool:
	return _sequence_playing


func seek_sequence(time: float) -> void:
	_sequence_time = clampf(time, 0.0, sequence_duration())
	var strip := strip_at(_sequence_time)
	if not strip.is_empty():
		var clip_id := str(strip.get("clip", ""))
		if _clips.has(clip_id):
			_active_clip = clip_id
	_apply_result(evaluate(_sequence_time))


func play_sequence() -> void:
	if sequence_duration() <= MIN_DURATION + 0.0001:
		return
	_sequence_playing = true
	if _sequence_time >= sequence_duration() - 0.0001:
		_sequence_time = 0.0
	_set_player_active(false)
	seek_sequence(_sequence_time)


func pause_sequence() -> void:
	_sequence_playing = false
	_set_player_active(true)


func stop_sequence() -> void:
	_sequence_playing = false
	_sequence_time = 0.0
	_set_player_active(true)
	seek_sequence(0.0)


func advance(delta: float) -> void:
	if not _sequence_playing:
		return
	var duration := sequence_duration()
	_sequence_time += maxf(0.0, delta)
	if _sequence_time >= duration:
		if _document != null and bool(_document.loop):
			_sequence_time = fposmod(_sequence_time, duration)
		else:
			_sequence_time = duration
			_sequence_playing = false
			_set_player_active(true)
	var strip := strip_at(_sequence_time)
	if not strip.is_empty():
		var clip_id := str(strip.get("clip", ""))
		if _clips.has(clip_id) and _active_clip != clip_id:
			_active_clip = clip_id
			_sync_document_clip()
	_apply_result(evaluate(_sequence_time))


func _set_player_active(active: bool) -> void:
	if _document != null and _document.anim_player != null:
		_document.anim_player.active = active


func _sync_document_clip() -> void:
	if _document == null:
		return
	var anim: Animation = active_animation()
	if anim == null:
		return
	_document.animation = anim
	_document.duration = maxf(MIN_DURATION, anim.length)
	if _document.has_method("_refresh_animation"):
		_document._refresh_animation()


# -------------------------------------------------------------------------
# glTF/GLB embedded animation
# -------------------------------------------------------------------------

func import_gltf_animations(object_id: String, node: Node) -> PackedStringArray:
	var dropped := PackedStringArray()
	last_error = ""
	if _document == null or node == null:
		return dropped
	var object_name := str(node.name)
	var object: Dictionary = _document.get_object(object_id)
	if not object.is_empty():
		object_name = str(object.get("name", object_name))
	var players: Array = []
	_scan_players(node, players)
	var created: Array[String] = []
	for player in players:
		if not player is AnimationPlayer:
			continue
		var anim_player := player as AnimationPlayer
		for animation_name in anim_player.get_animation_list():
			var source: Animation = anim_player.get_animation(animation_name)
			if source == null:
				continue
			var copy := _copy_imported_animation(anim_player, source, node, dropped)
			# Every imported animation becomes a clip, even when all of its
			# tracks are unsupported. The dropped list explains what did not run.
			var clip_id := _new_clip_id()
			_clips[clip_id] = {
				"id": clip_id,
				"name": _unique_clip_name("%s · %s" % [object_name, str(animation_name)]),
				"animation": copy,
			}
			created.append(clip_id)
		anim_player.active = false
		anim_player.stop()
	if created.is_empty():
		return dropped
	var layer_id := _layer_id_by_name(IMPORTED_LAYER)
	if layer_id == "":
		layer_id = add_layer(IMPORTED_LAYER)
	var strip_id := add_strip(layer_id, created[0], 0.0)
	if strip_id != "":
		update_strip(strip_id, {"fade_in": 0.0, "fade_out": 0.0, "weight": 1.0})
	_active_clip = created[0]
	if _document.has_method("set_active_clip"):
		_document.set_active_clip(created[0])
	if _document.has_method("play"):
		_document.play()
	_notify_clips()
	return dropped


func on_imported_scene(object_id: String, node: Node) -> void:
	var dropped := import_gltf_animations(object_id, node)
	if not dropped.is_empty():
		push_warning("Kinema: dropped %d unsupported imported animation track(s): %s" % [dropped.size(), ", ".join(dropped)])


func _scan_players(node: Node, out: Array) -> void:
	if node is AnimationPlayer:
		out.append(node)
	for child in node.get_children():
		_scan_players(child, out)


func _copy_imported_animation(
	player: AnimationPlayer,
	source: Animation,
	object_node: Node,
	dropped: PackedStringArray
) -> Animation:
	var copy := Animation.new()
	copy.length = maxf(MIN_DURATION, source.length)
	copy.loop_mode = source.loop_mode
	for track_index in range(source.get_track_count()):
		var track_type := source.track_get_type(track_index)
		var path := str(source.track_get_path(track_index))
		if track_type not in SUPPORTED_TYPES:
			dropped.append("%s (unsupported track type %d)" % [path, track_type])
			continue
		var remap := _remap_imported_track(player, path, track_type, object_node)
		if not bool(remap.get("ok", false)):
			dropped.append("%s (%s)" % [path, str(remap.get("reason", "unsupported"))])
			continue
		var new_track := copy.add_track(track_type)
		copy.track_set_path(new_track, NodePath(str(remap["path"])))
		copy.track_set_interpolation_type(new_track, source.track_get_interpolation_type(track_index))
		for key_index in range(source.track_get_key_count(track_index)):
			var time := source.track_get_key_time(track_index, key_index)
			var value: Variant = source.track_get_key_value(track_index, key_index)
			var transition := source.track_get_key_transition(track_index, key_index)
			var inserted := -1
			match track_type:
				POSITION:
					inserted = copy.position_track_insert_key(new_track, time, value as Vector3)
				ROTATION:
					inserted = copy.rotation_track_insert_key(new_track, time, value as Quaternion)
				SCALE:
					inserted = copy.scale_track_insert_key(new_track, time, value as Vector3)
			if inserted >= 0:
				copy.track_set_key_transition(new_track, inserted, transition)
	return copy


func _remap_imported_track(
	player: AnimationPlayer,
	path: String,
	track_type: int,
	object_node: Node
) -> Dictionary:
	var np := NodePath(path)
	var names: Array[String] = []
	for index in range(np.get_name_count()):
		names.append(str(np.get_name(index)))
	var relative := "/".join(names)
	var subname := str(np.get_concatenated_subnames())
	if subname == "":
		# Godot's glTF importer writes transform tracks as "Node" and lets the
		# track type carry the channel. Derive the property from the type.
		match track_type:
			POSITION:
				subname = "position"
			ROTATION:
				subname = "rotation"
			SCALE:
				subname = "scale"
	var root: Node = player.get_node_or_null(player.root_node)
	if root == null:
		root = player.get_parent()
	var target: Node = null
	if relative == "":
		target = root
	elif root != null:
		target = root.get_node_or_null(NodePath(relative))
	if target == null and object_node != null:
		target = object_node.get_node_or_null(NodePath(relative))
	if target == null and object_node != null:
		target = object_node.find_node(relative, true, false)
	if target == null:
		return {"ok": false, "reason": "missing node"}
	if _document == null:
		return {"ok": false, "reason": "no document"}
	if not _document.is_ancestor_of(target) and target != _document:
		return {"ok": false, "reason": "node outside the document"}
	var document_path := str(_document.get_path_to(target))
	if target is Skeleton3D and subname not in ["position", "rotation", "scale"]:
		if track_type != ROTATION:
			return {"ok": false, "reason": "only bone rotation is supported"}
		var skeleton := target as Skeleton3D
		if skeleton.find_bone(subname) < 0:
			return {"ok": false, "reason": "missing bone"}
		return {"ok": true, "path": document_path + ":" + subname}
	if subname not in ["position", "rotation", "scale"]:
		return {"ok": false, "reason": "unsupported property '%s'" % subname}
	var expected := POSITION if subname == "position" else (ROTATION if subname == "rotation" else SCALE)
	if track_type != expected:
		return {"ok": false, "reason": "track type does not match property '%s'" % subname}
	return {"ok": true, "path": document_path + ":" + subname}


# -------------------------------------------------------------------------
# Load and serialize
# -------------------------------------------------------------------------

func load_data(data: Dictionary, _nodes: Dictionary) -> void:
	_silent = true
	_clear_model()
	last_error = ""
	var raw_clips: Array = data.get("clips", []) if data.get("clips", []) is Array else []
	if raw_clips.is_empty():
		_migrate_v1(data)
	else:
		for raw in raw_clips:
			if raw is Dictionary:
				_load_clip(raw)
		_load_layers(data.get("layers", []))
		_active_clip = str(data.get("active_clip", ""))
		_active_layer = str(data.get("active_layer", ""))
	_ensure_active()
	_sequence_time = clampf(float(data.get("current_time", 0.0)), 0.0, sequence_duration())
	_sequence_playing = false
	_silent = false


func _migrate_v1(data: Dictionary) -> void:
	var anim: Animation = null
	if _document != null:
		anim = _document.animation
	if anim == null:
		anim = Animation.new()
		anim.length = maxf(MIN_DURATION, float(data.get("duration", 8.0)))
		anim.loop_mode = Animation.LOOP_LINEAR if bool(data.get("loop", true)) else Animation.LOOP_NONE
	elif anim.length <= 0.0:
		anim.length = maxf(MIN_DURATION, float(data.get("duration", 8.0)))
	var clip_id := _new_clip_id()
	_clips[clip_id] = {"id": clip_id, "name": "Take 01", "animation": anim}
	_active_clip = clip_id
	_ensure_default_layer(anim.length)


func _load_clip(raw: Dictionary) -> void:
	var id := str(raw.get("id", ""))
	if id == "" or _clips.has(id):
		id = _new_clip_id()
	var duration := maxf(MIN_DURATION, float(raw.get("duration", 1.0)))
	var anim := Animation.new()
	anim.length = duration
	anim.loop_mode = Animation.LOOP_LINEAR if bool(raw.get("loop", true)) else Animation.LOOP_NONE
	for raw_track in raw.get("tracks", []):
		if not raw_track is Dictionary:
			continue
		var track_type := int(raw_track.get("type", POSITION))
		if track_type not in SUPPORTED_TYPES:
			continue
		var track := anim.add_track(track_type)
		anim.track_set_path(track, NodePath(str(raw_track.get("path", ""))))
		anim.track_set_interpolation_type(track, int(raw_track.get("interpolation", Animation.INTERPOLATION_LINEAR)))
		for raw_key in raw_track.get("keys", []):
			if not raw_key is Dictionary:
				continue
			var time := float(raw_key.get("t", 0.0))
			var value: Variant = raw_key.get("v", null)
			var inserted := -1
			match track_type:
				POSITION:
					inserted = anim.position_track_insert_key(track, time, _json_to_vec3(value))
				ROTATION:
					inserted = anim.rotation_track_insert_key(track, time, _json_to_quat(value))
				SCALE:
					inserted = anim.scale_track_insert_key(track, time, _json_to_vec3(value))
			if inserted >= 0:
				anim.track_set_key_transition(track, inserted, clampf(float(raw_key.get("e", 1.0)), 0.0, 4.0))
	_clips[id] = {"id": id, "name": str(raw.get("name", "Clip")), "animation": anim}


func _load_layers(raw_layers: Variant) -> void:
	if not raw_layers is Array:
		return
	for raw in raw_layers:
		if not raw is Dictionary:
			continue
		var layer_id := str(raw.get("id", ""))
		if layer_id == "" or _layer_exists(layer_id):
			layer_id = _new_layer_id()
		var layer := {
			"id": layer_id,
			"name": str(raw.get("name", "Layer")),
			"weight": clampf(float(raw.get("weight", 1.0)), 0.0, 1.0),
			"blend": str(raw.get("blend", "override")),
			"muted": bool(raw.get("muted", false)),
			"solo": bool(raw.get("solo", false)),
			"strips": [],
		}
		if str(layer["blend"]) not in ["override", "additive"]:
			layer["blend"] = "override"
		for raw_strip in raw.get("strips", []):
			if not raw_strip is Dictionary:
				continue
			var clip_id := str(raw_strip.get("clip", ""))
			if not _clips.has(clip_id):
				push_warning("Kinema: dropped a loaded strip that referenced a missing clip.")
				continue
			var strip_id := str(raw_strip.get("id", ""))
			if strip_id == "":
				strip_id = _new_strip_id()
			var length := _clip_length(clip_id)
			var strip := {
				"id": strip_id,
				"clip": clip_id,
				"start": maxf(0.0, float(raw_strip.get("start", 0.0))),
				"trim_start": clampf(float(raw_strip.get("trim_start", 0.0)), 0.0, length),
				"trim_end": clampf(float(raw_strip.get("trim_end", length)), 0.0, length),
				"speed": clampf(float(raw_strip.get("speed", 1.0)), 0.05, 8.0),
				"weight": clampf(float(raw_strip.get("weight", 1.0)), 0.0, 1.0),
				"fade_in": maxf(0.0, float(raw_strip.get("fade_in", 0.0))),
				"fade_out": maxf(0.0, float(raw_strip.get("fade_out", 0.0))),
				"ease": clampf(float(raw_strip.get("ease", 1.0)), 0.0, 4.0),
			}
			if float(strip["trim_end"]) <= float(strip["trim_start"]):
				strip["trim_end"] = minf(length, float(strip["trim_start"]) + 0.001)
			_clamp_fades(strip, length)
			layer["strips"].append(strip)
		_layers.append(layer)


func to_data() -> Dictionary:
	var clips: Array = []
	for id in _clips.keys():
		clips.append(_clip_to_json(_clips[id]))
	var data := {
		"clips": clips,
		"layers": _layers.duplicate(true),
	}
	if _active_clip != "":
		data["active_clip"] = _active_clip
	if _active_layer != "":
		data["active_layer"] = _active_layer
	return data


func _clip_to_json(clip: Dictionary) -> Dictionary:
	var anim: Animation = clip.get("animation")
	var tracks: Array = []
	if anim != null:
		for track_index in range(anim.get_track_count()):
			var track := {
				"path": str(anim.track_get_path(track_index)),
				"type": anim.track_get_type(track_index),
				"interpolation": anim.track_get_interpolation_type(track_index),
				"keys": [],
			}
			for key_index in range(anim.track_get_key_count(track_index)):
				track["keys"].append({
					"t": float(anim.track_get_key_time(track_index, key_index)),
					"v": _value_to_json(anim.track_get_key_value(track_index, key_index)),
					"e": float(anim.track_get_key_transition(track_index, key_index)),
				})
			tracks.append(track)
	return {
		"id": str(clip.get("id", "")),
		"name": str(clip.get("name", "")),
		"duration": maxf(MIN_DURATION, anim.length) if anim != null else MIN_DURATION,
		"loop": anim != null and anim.loop_mode != Animation.LOOP_NONE,
		"tracks": tracks,
	}


# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

func _find_strip(strip_id: String) -> Dictionary:
	for layer in _layers:
		var strips: Array = layer.get("strips", [])
		for index in range(strips.size()):
			if str(strips[index].get("id", "")) == strip_id:
				return {"layer": layer, "strip": strips[index], "index": index}
	return {}


func _strip_end(strip: Dictionary) -> float:
	var clip: Animation = animation_for(str(strip.get("clip", "")))
	if clip == null:
		return 0.0
	var length := maxf(0.001, clip.length)
	var trim_start := clampf(float(strip.get("trim_start", 0.0)), 0.0, length)
	var trim_end := clampf(float(strip.get("trim_end", length)), trim_start + 0.001, length)
	var speed := maxf(0.05, float(strip.get("speed", 1.0)))
	return maxf(0.0, float(strip.get("start", 0.0))) + (trim_end - trim_start) / speed


func _strip_covers(strip: Dictionary, time: float) -> bool:
	var clip: Animation = animation_for(str(strip.get("clip", "")))
	if clip == null:
		return false
	var end := _strip_end(strip)
	return time >= maxf(0.0, float(strip.get("start", 0.0))) - 0.000001 and time <= end + 0.000001


func _clamp_fades(strip: Dictionary, clip_length: float) -> void:
	var trim_start := clampf(float(strip.get("trim_start", 0.0)), 0.0, clip_length)
	var trim_end := clampf(float(strip.get("trim_end", clip_length)), trim_start + 0.001, clip_length)
	var speed := maxf(0.05, float(strip.get("speed", 1.0)))
	var span := (trim_end - trim_start) / speed
	var fade_in := clampf(float(strip.get("fade_in", 0.0)), 0.0, span)
	var fade_out := clampf(float(strip.get("fade_out", 0.0)), 0.0, span)
	if fade_in + fade_out > span and fade_in + fade_out > 0.0:
		var factor := span / (fade_in + fade_out)
		fade_in *= factor
		fade_out *= factor
		push_warning("Kinema: clamped strip fades to the strip duration.")
	strip["fade_in"] = fade_in
	strip["fade_out"] = fade_out


func _new_clip_id() -> String:
	while _clips.has("clip_%d" % _next_clip):
		_next_clip += 1
	var id := "clip_%d" % _next_clip
	_next_clip += 1
	return id


func _new_layer_id() -> String:
	while _layer_exists("layer_%d" % _next_layer):
		_next_layer += 1
	var id := "layer_%d" % _next_layer
	_next_layer += 1
	return id


func _new_strip_id() -> String:
	var id := "strip_%d" % _next_strip
	_next_strip += 1
	return id


func _first_clip_id() -> String:
	if _clips.is_empty():
		return ""
	return str(_clips.keys()[0])


func _layer_exists(id: String) -> bool:
	for layer in _layers:
		if str(layer.get("id", "")) == id:
			return true
	return false


func _layer_id_by_name(name: String) -> String:
	for layer in _layers:
		if str(layer.get("name", "")) == name:
			return str(layer.get("id", ""))
	return ""


func _unique_clip_name(base: String) -> String:
	var clean := base.strip_edges()
	if clean == "":
		clean = "Clip"
	var candidate := clean
	var counter := 2
	while _clip_name_exists(candidate):
		candidate = "%s %d" % [clean, counter]
		counter += 1
	return candidate


func _clip_name_exists(name: String) -> bool:
	for id in _clips.keys():
		if str(_clips[id].get("name", "")) == name:
			return true
	return false


func _unique_layer_name(base: String) -> String:
	var clean := base.strip_edges()
	if clean == "":
		clean = "Layer"
	var candidate := clean
	var counter := 2
	while _layer_name_exists(candidate):
		candidate = "%s %d" % [clean, counter]
		counter += 1
	return candidate


func _layer_name_exists(name: String) -> bool:
	for layer in _layers:
		if str(layer.get("name", "")) == name:
			return true
	return false


func _clip_length(id: String) -> float:
	var anim: Animation = animation_for(id)
	return maxf(MIN_DURATION, anim.length) if anim != null else MIN_DURATION


func _document_duration() -> float:
	if _document == null:
		return 8.0
	return maxf(MIN_DURATION, float(_document.duration))


func _document_loop() -> bool:
	if _document == null:
		return true
	return bool(_document.loop)


func _notify_clips() -> void:
	if _silent or _document == null:
		return
	if _document.has_signal("clips_changed"):
		_document.clips_changed.emit()
	if _document.has_signal("dirty_changed"):
		_document.set("_dirty", true)
		_document.dirty_changed.emit(true)


func _value_to_json(value: Variant) -> Variant:
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Quaternion:
		return [value.x, value.y, value.z, value.w]
	return value


func _json_to_vec3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _json_to_quat(value: Variant) -> Quaternion:
	if value is Quaternion:
		return value.normalized()
	if value is Array and value.size() >= 4:
		return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()
	return Quaternion.IDENTITY


func _as_vec3(value: Variant) -> Vector3:
	return value if value is Vector3 else _json_to_vec3(value)


func _as_quat(value: Variant) -> Quaternion:
	return value if value is Quaternion else _json_to_quat(value)
