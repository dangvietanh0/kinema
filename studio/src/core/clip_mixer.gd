extends RefCounted
## Pure clip mixer.
##
## `evaluate()` is scene-free: it samples Animation resources and returns final
## object and bone poses for the document to apply. Layer order is bottom to
## top; strips inside one layer are weighted averages, so a 0.5 s crossfade is
## a real 50/50 blend at its midpoint.

const POSITION := Animation.TYPE_POSITION_3D
const ROTATION := Animation.TYPE_ROTATION_3D
const SCALE := Animation.TYPE_SCALE_3D
const SUPPORTED := [POSITION, ROTATION, SCALE]

## Track lookup is cached by clip instance + path + type. Animation resources
## are stable while a project is open, so this removes `find_track()` from the
## per-frame hot path without holding references to clips.
static var _track_cache: Dictionary = {}


static func evaluate(
	clips: Dictionary,
	layers: Array,
	time: float,
	object_ids: PackedStringArray,
	base_poses: Dictionary,
	bone_paths: Dictionary
) -> Dictionary:
	var objects: Dictionary = {}
	for object_id in object_ids:
		objects[object_id] = _base_pose(base_poses.get(object_id, {}))
	var bones: Dictionary = {}
	for path in bone_paths.keys():
		var info: Dictionary = bone_paths[path]
		var rig_id := str(info.get("rig_id", ""))
		var bone := str(info.get("bone", ""))
		if rig_id == "" or bone == "":
			continue
		if not bones.has(rig_id):
			bones[rig_id] = {}
		if not bones[rig_id].has(bone):
			bones[rig_id][bone] = {
				"rotation": _as_quat(info.get("base", Quaternion.IDENTITY)),
				"weight": 0.0,
			}
	for layer in _active_layers(layers):
		var contributions: Dictionary = _collect_layer(clips, layer, time, bone_paths)
		_apply_layer(objects, bones, contributions, layer, base_poses, bone_paths)
	return {"objects": objects, "bones": bones}


static func _active_layers(layers: Array) -> Array:
	var has_solo := false
	for layer in layers:
		if bool(layer.get("solo", false)) and not bool(layer.get("muted", false)):
			has_solo = true
	var active: Array = []
	for layer in layers:
		if bool(layer.get("muted", false)):
			continue
		if has_solo and not bool(layer.get("solo", false)):
			continue
		active.append(layer)
	return active


static func _base_pose(raw: Dictionary) -> Dictionary:
	return {
		"position": _as_vec3(raw.get("position", Vector3.ZERO)),
		"rotation": _as_quat(raw.get("rotation", Quaternion.IDENTITY)),
		"scale": _as_vec3(raw.get("scale", Vector3.ONE)),
		"weight": 0.0,
	}


static func _as_vec3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


static func _as_quat(value: Variant) -> Quaternion:
	if value is Quaternion:
		return value.normalized()
	if value is Array and value.size() >= 4:
		return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()
	return Quaternion.IDENTITY


static func _span(strip: Dictionary, clip: Animation) -> Dictionary:
	var clip_length := maxf(0.001, clip.length)
	var speed := maxf(0.05, float(strip.get("speed", 1.0)))
	var trim_start := clampf(float(strip.get("trim_start", 0.0)), 0.0, clip_length)
	var trim_end := clampf(float(strip.get("trim_end", clip_length)), trim_start + 0.001, clip_length)
	var start := maxf(0.0, float(strip.get("start", 0.0)))
	var length := (trim_end - trim_start) / speed
	return {
		"start": start,
		"end": start + length,
		"length": length,
		"trim_start": trim_start,
		"trim_end": trim_end,
		"speed": speed,
	}


static func _fade(strip: Dictionary, span: Dictionary, time: float) -> float:
	var length := float(span.get("length", 0.0))
	if length <= 0.00001:
		return 0.0
	var fade_in := clampf(float(strip.get("fade_in", 0.0)), 0.0, length)
	var fade_out := clampf(float(strip.get("fade_out", 0.0)), 0.0, length)
	if fade_in + fade_out > length:
		var factor := length / (fade_in + fade_out)
		fade_in *= factor
		fade_out *= factor
	var local := time - float(span.get("start", 0.0))
	var weight := 1.0
	if fade_in > 0.0:
		weight *= smoothstep(0.0, fade_in, local)
	if fade_out > 0.0:
		weight *= 1.0 - smoothstep(length - fade_out, length, local)
	return clampf(weight, 0.0, 1.0)


static func _local_time(strip: Dictionary, clip: Animation, time: float, span: Dictionary) -> float:
	var length := float(span.get("length", 0.0))
	var u := 0.0
	if length > 0.00001:
		u = clampf((time - float(span.get("start", 0.0))) / length, 0.0, 1.0)
	var ease := clampf(float(strip.get("ease", 1.0)), 0.0, 4.0)
	if ease <= 0.0001:
		u = 0.0
	elif not is_equal_approx(ease, 1.0):
		u = pow(u, ease)
	var trim_start := float(span.get("trim_start", 0.0))
	var trim_end := float(span.get("trim_end", clip.length))
	var local := trim_start + u * (trim_end - trim_start)
	if clip.loop_mode != Animation.LOOP_NONE:
		local = fposmod(local, maxf(0.001, clip.length))
	else:
		local = clampf(local, trim_start, trim_end)
	return local


static func _track_index(clip: Animation, path: String, type: int) -> int:
	var key := "%d|%s|%d" % [clip.get_instance_id(), path, type]
	if _track_cache.has(key):
		return int(_track_cache[key])
	var index := clip.find_track(NodePath(path), type)
	if _track_cache.size() > 4096:
		_track_cache.clear()
	_track_cache[key] = index
	return index


static func _sample(clip: Animation, path: String, type: int, local: float) -> Variant:
	var index := _track_index(clip, path, type)
	if index < 0:
		return null
	var sample_time := clampf(local, 0.0, maxf(0.0, clip.length))
	match type:
		POSITION:
			return clip.position_track_interpolate(index, sample_time)
		ROTATION:
			return clip.rotation_track_interpolate(index, sample_time)
		SCALE:
			return clip.scale_track_interpolate(index, sample_time)
	return null


static func _channel_for(type: int) -> String:
	match type:
		POSITION:
			return "position"
		ROTATION:
			return "rotation"
		SCALE:
			return "scale"
	return ""


static func _track_target(path: String) -> Dictionary:
	var colon := path.find(":")
	var node_path := path if colon < 0 else path.substr(0, colon)
	var sub := "" if colon < 0 else path.substr(colon + 1)
	var bone_marker := node_path.find("/Skeleton3D")
	if bone_marker >= 0:
		return {
			"kind": "bone",
			"rig_prefix": node_path.substr(0, bone_marker),
			"bone": sub,
		}
	return {"kind": "object", "target": node_path, "channel": sub}


static func _add_object_sample(
	objects: Dictionary,
	target: String,
	channel: String,
	value: Variant,
	raw: float
) -> void:
	if target == "" or channel == "":
		return
	if not objects.has(target):
		objects[target] = {}
	var target_data: Dictionary = objects[target]
	var entry: Dictionary = target_data.get(channel, {})
	if entry.is_empty():
		target_data[channel] = {"value": value, "weight": raw}
		return
	var total := float(entry.get("weight", 0.0)) + raw
	if value is Quaternion:
		entry["value"] = (entry["value"] as Quaternion).slerp(value, raw / maxf(0.000001, total))
	else:
		entry["value"] = (entry["value"] as Vector3).lerp(value, raw / maxf(0.000001, total))
	entry["weight"] = total
	target_data[channel] = entry


static func _add_bone_sample(
	bones: Dictionary,
	rig_id: String,
	bone: String,
	value: Quaternion,
	raw: float
) -> void:
	if rig_id == "" or bone == "":
		return
	if not bones.has(rig_id):
		bones[rig_id] = {}
	var rig: Dictionary = bones[rig_id]
	var entry: Dictionary = rig.get(bone, {})
	if entry.is_empty():
		rig[bone] = {"value": value, "weight": raw}
		return
	var total := float(entry.get("weight", 0.0)) + raw
	entry["value"] = (entry["value"] as Quaternion).slerp(value, raw / maxf(0.000001, total))
	entry["weight"] = total
	rig[bone] = entry


static func _collect_layer(
	clips: Dictionary,
	layer: Dictionary,
	time: float,
	bone_paths: Dictionary
) -> Dictionary:
	var objects: Dictionary = {}
	var bones: Dictionary = {}
	var covering: Array = []
	var total_raw := 0.0
	for strip in layer.get("strips", []):
		if not strip is Dictionary:
			continue
		var clip: Animation = clips.get(str(strip.get("clip", "")))
		if clip == null:
			continue
		var span: Dictionary = _span(strip, clip)
		if time < float(span.get("start", 0.0)) - 0.000001:
			continue
		if time > float(span.get("end", 0.0)) + 0.000001:
			continue
		var fade := _fade(strip, span, time)
		var raw := clampf(float(strip.get("weight", 1.0)), 0.0, 1.0) * fade
		if raw <= 0.000001:
			continue
		covering.append({
			"clip": clip,
			"raw": raw,
			"local": _local_time(strip, clip, time, span),
			"start": float(span.get("start", 0.0)),
		})
		total_raw += raw
	if covering.is_empty():
		return {"objects": objects, "bones": bones, "total_raw": 0.0}
	covering.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("start", 0.0)) < float(b.get("start", 0.0))
	)
	for item in covering:
		var clip: Animation = item.get("clip")
		var raw := float(item.get("raw", 0.0))
		var local := float(item.get("local", 0.0))
		for track_index in range(clip.get_track_count()):
			var track_type := clip.track_get_type(track_index)
			if track_type not in SUPPORTED:
				continue
			var path := str(clip.track_get_path(track_index))
			var value: Variant = _sample(clip, path, track_type, local)
			if value == null:
				continue
			var target: Dictionary = _track_target(path)
			if str(target.get("kind", "")) == "bone":
				if track_type != ROTATION:
					continue
				var info: Dictionary = bone_paths.get(path, {})
				var rig_id := str(info.get("rig_id", target.get("rig_prefix", "")))
				var bone := str(info.get("bone", target.get("bone", "")))
				_add_bone_sample(bones, rig_id, bone, value as Quaternion, raw)
			else:
				var channel := str(target.get("channel", ""))
				if channel != _channel_for(track_type):
					channel = _channel_for(track_type)
				_add_object_sample(objects, str(target.get("target", "")), channel, value, raw)
	return {"objects": objects, "bones": bones, "total_raw": total_raw}


static func _apply_layer(
	objects: Dictionary,
	bones: Dictionary,
	contributions: Dictionary,
	layer: Dictionary,
	base_poses: Dictionary,
	bone_paths: Dictionary
) -> void:
	var layer_weight := clampf(float(layer.get("weight", 1.0)), 0.0, 1.0)
	if layer_weight <= 0.0:
		return
	var blend := str(layer.get("blend", "override"))
	var coverage := minf(1.0, float(contributions.get("total_raw", 0.0)))
	if coverage <= 0.0:
		return
	var effective := layer_weight * coverage

	for target in contributions.get("objects", {}).keys():
		var raw_base: Dictionary = base_poses.get(target, {})
		var base := _base_pose(raw_base)
		if not objects.has(target):
			objects[target] = base
		var acc: Dictionary = objects[target]
		var channels: Dictionary = contributions["objects"][target]
		for channel in ["position", "rotation", "scale"]:
			if not channels.has(channel):
				continue
			var entry: Dictionary = channels[channel]
			# `entry.weight` is already the summed strip weight/fade for this
			# channel, so the layer weight is the only factor left to apply.
			var weight := layer_weight * minf(1.0, float(entry.get("weight", 0.0)))
			if weight <= 0.0:
				continue
			var value: Variant = entry.get("value")
			if blend == "additive":
				match channel:
					"position":
						acc["position"] = (acc["position"] as Vector3) + ((value as Vector3) - (base["position"] as Vector3)) * weight
					"rotation":
						var base_rotation: Quaternion = base["rotation"]
						var relative: Quaternion = (value as Quaternion) * base_rotation.inverse()
						var delta: Quaternion = Quaternion.IDENTITY.slerp(relative.normalized(), weight)
						acc["rotation"] = ((acc["rotation"] as Quaternion) * delta).normalized()
					"scale":
						var base_scale: Vector3 = base["scale"]
						var ratio := Vector3(
							(value as Vector3).x / _safe(base_scale.x),
							(value as Vector3).y / _safe(base_scale.y),
							(value as Vector3).z / _safe(base_scale.z)
						)
						acc["scale"] = (acc["scale"] as Vector3) * (Vector3.ONE.lerp(ratio, weight))
			else:
				match channel:
					"position":
						acc["position"] = (acc["position"] as Vector3).lerp(value as Vector3, weight)
					"rotation":
						acc["rotation"] = (acc["rotation"] as Quaternion).slerp(value as Quaternion, weight).normalized()
					"scale":
						acc["scale"] = (acc["scale"] as Vector3).lerp(value as Vector3, weight)
		acc["weight"] = maxf(float(acc.get("weight", 0.0)), effective)

	for rig_id in contributions.get("bones", {}).keys():
		if not bones.has(rig_id):
			bones[rig_id] = {}
		var rig: Dictionary = bones[rig_id]
		var bone_data: Dictionary = contributions["bones"][rig_id]
		for bone in bone_data.keys():
			if not rig.has(bone):
				rig[bone] = {"rotation": Quaternion.IDENTITY, "weight": 0.0}
			var acc: Dictionary = rig[bone]
			var entry: Dictionary = bone_data[bone]
			var weight := layer_weight * minf(1.0, float(entry.get("weight", 0.0)))
			if weight <= 0.0:
				continue
			var value: Quaternion = entry.get("value", Quaternion.IDENTITY)
			if blend == "additive":
				var info: Dictionary = {}
				for path in bone_paths.keys():
					var candidate: Dictionary = bone_paths[path]
					if str(candidate.get("rig_id", "")) == rig_id and str(candidate.get("bone", "")) == bone:
						info = candidate
						break
				var base_rotation := _as_quat(info.get("base", Quaternion.IDENTITY))
				var relative := value * base_rotation.inverse()
				var delta := Quaternion.IDENTITY.slerp(relative.normalized(), weight)
				acc["rotation"] = ((acc["rotation"] as Quaternion) * delta).normalized()
			else:
				acc["rotation"] = (acc["rotation"] as Quaternion).slerp(value, weight).normalized()
			acc["weight"] = maxf(float(acc.get("weight", 0.0)), effective)
			rig[bone] = acc


static func _safe(value: float) -> float:
	return value if absf(value) > 0.000001 else 0.000001
