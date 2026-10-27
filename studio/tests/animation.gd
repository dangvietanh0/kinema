extends Node
## Multi-clip animation suite.
##
## Covers the pure mixer, the clip/layer/strip model, sequence transport,
## v1 migration, v2 roundtrip and runtime GLB animation import. The harness
## prints one OK/FAIL line per assertion and ends with ANIMATION RESULT.

const DocumentScript = preload("res://src/core/document.gd")
const MIXER_PATH := "res://src/core/clip_mixer.gd"
const LANE_PATH := "res://src/ui/clip_lane.gd"
const CLIP_SHEET_PATH := "res://src/ui/clip_sheet.gd"
const LAYER_SHEET_PATH := "res://src/ui/layer_sheet.gd"
const STRIP_SHEET_PATH := "res://src/ui/strip_sheet.gd"

const EPS := 0.001

var _failures: Array[String] = []
var _checks := 0
var _import_signal_count := 0
var _ui_signal_count := 0
var _ui_selected_strip := ""
var _ui_sheet: Control = null


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("ANIMATION OK: " + message)
	else:
		_failures.append(message)
		printerr("ANIMATION FAIL: " + message)


func _approx(a: float, b: float, epsilon: float = EPS) -> bool:
	return absf(a - b) <= epsilon


func _vec_approx(a: Vector3, b: Vector3, epsilon: float = EPS) -> bool:
	return a.distance_to(b) <= epsilon


func _quat_approx(a: Quaternion, b: Quaternion, epsilon: float = 0.002) -> bool:
	return absf(a.dot(b)) >= 1.0 - epsilon


func _ready() -> void:
	await get_tree().process_frame
	print("ANIMATION STEP: mixer")
	_test_mixer()
	print("ANIMATION STEP: model and transport")
	await _test_model()
	print("ANIMATION STEP: glTF import")
	await _test_import()
	print("ANIMATION STEP: clip lane and sheets")
	await _test_ui()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("ANIMATION RESULT: PASS (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		print("ANIMATION RESULT: FAIL (%d checks, %d failures)" % [_checks, _failures.size()])
		for failure in _failures:
			printerr("  - " + failure)
		get_tree().quit(1)


# -------------------------------------------------------------------------
# Mixer
# -------------------------------------------------------------------------

func _position_anim(length: float, from: Vector3, to: Vector3) -> Animation:
	var anim := Animation.new()
	anim.length = length
	var track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(track, NodePath("obj_1:position"))
	anim.position_track_insert_key(track, 0.0, from)
	anim.position_track_insert_key(track, length, to)
	return anim


func _constant_position_anim(value: Vector3, length: float = 2.0) -> Animation:
	var anim := Animation.new()
	anim.length = length
	var track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(track, NodePath("obj_1:position"))
	anim.position_track_insert_key(track, 0.0, value)
	anim.position_track_insert_key(track, length, value)
	return anim


func _base(position: Vector3 = Vector3.ZERO, rotation: Quaternion = Quaternion.IDENTITY, scale: Vector3 = Vector3.ONE) -> Dictionary:
	return {"position": position, "rotation": rotation, "scale": scale}


func _strip(clip_id: String, start: float, trim_start: float, trim_end: float, extra: Dictionary = {}) -> Dictionary:
	var data := {
		"id": "strip_" + clip_id,
		"clip": clip_id,
		"start": start,
		"trim_start": trim_start,
		"trim_end": trim_end,
		"speed": 1.0,
		"weight": 1.0,
		"fade_in": 0.0,
		"fade_out": 0.0,
		"ease": 1.0,
	}
	for key in extra.keys():
		data[key] = extra[key]
	return data


func _layer(id: String, strips: Array, extra: Dictionary = {}) -> Dictionary:
	var data := {
		"id": id,
		"name": id,
		"weight": 1.0,
		"blend": "override",
		"muted": false,
		"solo": false,
		"strips": strips,
	}
	for key in extra.keys():
		data[key] = extra[key]
	return data


func _mixer_eval(clips: Dictionary, layers: Array, time: float, base_poses: Dictionary = {"obj_1": _base()}, bone_paths: Dictionary = {}) -> Dictionary:
	var Mixer = load(MIXER_PATH)
	if Mixer == null:
		return {}
	return Mixer.evaluate(clips, layers, time, PackedStringArray(["obj_1"]), base_poses, bone_paths)


func _test_mixer() -> void:
	var Mixer = load(MIXER_PATH)
	_check(Mixer != null, "clip_mixer.gd exists")
	if Mixer == null:
		return

	# Two strips overlap by 0.5 s. A is 0 -> 1 over 2 s, B is 0 -> 3 over 2 s.
	# At 1.75 A samples 0.875 and B samples 0.375, so the 50/50 blend is 0.625.
	var clips := {
		"a": _position_anim(2.0, Vector3.ZERO, Vector3(1, 0, 0)),
		"b": _position_anim(2.0, Vector3.ZERO, Vector3(3, 0, 0)),
	}
	var cross := [_layer("base", [
		_strip("a", 0.0, 0.0, 2.0, {"fade_out": 0.5}),
		_strip("b", 1.5, 0.0, 2.0, {"fade_in": 0.5}),
	])]
	var mid := _mixer_eval(clips, cross, 1.75)
	var mid_pos: Vector3 = mid.get("objects", {}).get("obj_1", {}).get("position", Vector3.ZERO)
	_check(_approx(mid_pos.x, 0.625), "crossfade midpoint is the 50/50 weighted sample (%.3f)" % mid_pos.x)
	_check(_approx(float(mid.get("objects", {}).get("obj_1", {}).get("weight", 0.0)), 1.0), "crossfade midpoint weight is 1")

	var at_start := _mixer_eval(clips, cross, 1.5)
	var start_pos: Vector3 = at_start.get("objects", {}).get("obj_1", {}).get("position", Vector3.ZERO)
	_check(_approx(start_pos.x, 0.75), "crossfade start uses clip A only")
	var at_end := _mixer_eval(clips, cross, 2.0)
	var end_pos: Vector3 = at_end.get("objects", {}).get("obj_1", {}).get("position", Vector3.ZERO)
	_check(_approx(end_pos.x, 0.75), "crossfade end uses clip B only (local 0.5 s)")
	var after_end := _mixer_eval(clips, cross, 2.25)
	var after_pos: Vector3 = after_end.get("objects", {}).get("obj_1", {}).get("position", Vector3.ZERO)
	_check(_approx(after_pos.x, 1.125), "crossfade after the overlap uses clip B")

	# Layer weight 0.5 blends from the base pose.
	var weighted := [_layer("base", [_strip("a", 0.0, 0.0, 2.0)], {"weight": 0.5})]
	var w := _mixer_eval({"a": _constant_position_anim(Vector3(2, 0, 0))}, weighted, 1.0)
	var w_pos: Vector3 = w.get("objects", {}).get("obj_1", {}).get("position", Vector3.ZERO)
	_check(_vec_approx(w_pos, Vector3(1, 0, 0)), "override layer weight 0.5 blends from the base pose")

	# Additive position, rotation and scale.
	var additive := [_layer("base", [_strip("a", 0.0, 0.0, 2.0)], {"blend": "additive"})]
	var add_anim := Animation.new()
	add_anim.length = 2.0
	var p_track := add_anim.add_track(Animation.TYPE_POSITION_3D)
	add_anim.track_set_path(p_track, NodePath("obj_1:position"))
	add_anim.position_track_insert_key(p_track, 0.0, Vector3(2, 0, 0))
	add_anim.position_track_insert_key(p_track, 2.0, Vector3(2, 0, 0))
	var r_track := add_anim.add_track(Animation.TYPE_ROTATION_3D)
	add_anim.track_set_path(r_track, NodePath("obj_1:rotation"))
	var quarter := Quaternion(Vector3.UP, PI * 0.5)
	add_anim.rotation_track_insert_key(r_track, 0.0, quarter)
	add_anim.rotation_track_insert_key(r_track, 2.0, quarter)
	var s_track := add_anim.add_track(Animation.TYPE_SCALE_3D)
	add_anim.track_set_path(s_track, NodePath("obj_1:scale"))
	add_anim.scale_track_insert_key(s_track, 0.0, Vector3(4, 4, 4))
	add_anim.scale_track_insert_key(s_track, 2.0, Vector3(4, 4, 4))
	var add_res := _mixer_eval(
		{"a": add_anim},
		additive,
		1.0,
		{"obj_1": _base(Vector3(1, 0, 0), Quaternion.IDENTITY, Vector3(2, 2, 2))}
	)
	var add_obj: Dictionary = add_res.get("objects", {}).get("obj_1", {})
	_check(_vec_approx(add_obj.get("position", Vector3.ZERO), Vector3(2, 0, 0)), "additive position adds value minus base")
	_check(_quat_approx(add_obj.get("rotation", Quaternion.IDENTITY), quarter), "additive rotation composes the delta")
	_check(_vec_approx(add_obj.get("scale", Vector3.ONE), Vector3(4, 4, 4)), "additive scale multiplies the ratio")

	# Mute and solo.
	var two_layers := [
		_layer("base", [_strip("a", 0.0, 0.0, 2.0)]),
		_layer("over", [_strip("b", 0.0, 0.0, 2.0)]),
	]
	var both := _mixer_eval(
		{"a": _constant_position_anim(Vector3(1, 0, 0)), "b": _constant_position_anim(Vector3(3, 0, 0))},
		two_layers,
		1.0
	)
	_check(_vec_approx(both.get("objects", {}).get("obj_1", {}).get("position", Vector3.ZERO), Vector3(3, 0, 0)), "top layer overrides the base layer")
	two_layers[0]["muted"] = true
	var muted := _mixer_eval(
		{"a": _constant_position_anim(Vector3(1, 0, 0)), "b": _constant_position_anim(Vector3(3, 0, 0))},
		two_layers,
		1.0
	)
	_check(_vec_approx(muted.get("objects", {}).get("obj_1", {}).get("position", Vector3.ZERO), Vector3(3, 0, 0)), "muted layers are skipped")
	two_layers[0]["muted"] = false
	two_layers[1]["solo"] = true
	var solo := _mixer_eval(
		{"a": _constant_position_anim(Vector3(1, 0, 0)), "b": _constant_position_anim(Vector3(3, 0, 0))},
		two_layers,
		1.0
	)
	_check(_vec_approx(solo.get("objects", {}).get("obj_1", {}).get("position", Vector3.ZERO), Vector3(3, 0, 0)), "solo limits evaluation to solo layers")

	# Fade endpoints use smoothstep inside the strip.
	var fade_layer := [_layer("base", [_strip("a", 0.0, 0.0, 2.0, {"fade_in": 0.5, "fade_out": 0.5})])]
	var fade_clip := {"a": _constant_position_anim(Vector3(2, 0, 0))}
	_check(_vec_approx(_mixer_eval(fade_clip, fade_layer, 0.0).get("objects", {}).get("obj_1", {}).get("position", Vector3.ZERO), Vector3.ZERO), "fade in starts at the base pose")
	_check(_vec_approx(_mixer_eval(fade_clip, fade_layer, 0.5).get("objects", {}).get("obj_1", {}).get("position", Vector3.ZERO), Vector3(2, 0, 0)), "fade in reaches full weight")
	_check(_vec_approx(_mixer_eval(fade_clip, fade_layer, 1.5).get("objects", {}).get("obj_1", {}).get("position", Vector3.ZERO), Vector3(2, 0, 0)), "fade out starts at full weight")
	_check(_vec_approx(_mixer_eval(fade_clip, fade_layer, 2.0).get("objects", {}).get("obj_1", {}).get("position", Vector3.ZERO), Vector3.ZERO), "fade out ends at the base pose")

	# Bone rotation sampling.
	var bone_anim := Animation.new()
	bone_anim.length = 2.0
	var bone_track := bone_anim.add_track(Animation.TYPE_ROTATION_3D)
	bone_anim.track_set_path(bone_track, NodePath("Rig/Skeleton3D:Hips"))
	bone_anim.rotation_track_insert_key(bone_track, 0.0, Quaternion.IDENTITY)
	bone_anim.rotation_track_insert_key(bone_track, 2.0, Quaternion(Vector3.UP, PI * 0.5))
	var bone_layer := [_layer("base", [_strip("rig", 0.0, 0.0, 2.0)])]
	var bone_paths := {
		"Rig/Skeleton3D:Hips": {"rig_id": "rig", "bone": "Hips", "base": Quaternion.IDENTITY},
	}
	var bone_res: Dictionary = Mixer.evaluate({"rig": bone_anim}, bone_layer, 1.0, PackedStringArray(), {}, bone_paths)
	var hips: Dictionary = bone_res.get("bones", {}).get("rig", {}).get("Hips", {})
	_check(_quat_approx(hips.get("rotation", Quaternion.IDENTITY), Quaternion(Vector3.UP, PI * 0.25)), "bone rotation track samples at half time")
	_check(_approx(float(hips.get("weight", 0.0)), 1.0), "bone track reports a full weight")

	# No contribution keeps the base pose.
	var empty := _mixer_eval({"a": _constant_position_anim(Vector3(2, 0, 0))}, [_layer("base", [])], 1.0, {"obj_1": _base(Vector3(4, 0, 0))})
	var empty_obj: Dictionary = empty.get("objects", {}).get("obj_1", {})
	_check(_vec_approx(empty_obj.get("position", Vector3.ZERO), Vector3(4, 0, 0)), "no contribution keeps the base position")
	_check(_approx(float(empty_obj.get("weight", 0.0)), 0.0), "no contribution reports zero weight")

	# Ease warps time inside the strip: u = 0.5 with ease 2 samples 0.25 s.
	var ease_layer := [_layer("base", [_strip("a", 0.0, 0.0, 2.0, {"ease": 2.0})])]
	var ease_pos: Vector3 = _mixer_eval({"a": _position_anim(2.0, Vector3.ZERO, Vector3(1, 0, 0))}, ease_layer, 1.0).get("objects", {}).get("obj_1", {}).get("position", Vector3.ZERO)
	_check(_vec_approx(ease_pos, Vector3(0.25, 0, 0)), "ease warps strip time")

	# A loop clip wraps at the strip end; a clamped clip holds the last key.
	var loop_anim := _position_anim(2.0, Vector3.ZERO, Vector3(1, 0, 0))
	loop_anim.loop_mode = Animation.LOOP_LINEAR
	var slow_layer := [_layer("base", [_strip("a", 0.0, 0.0, 2.0, {"speed": 0.5})])]
	var loop_end: Vector3 = _mixer_eval({"a": loop_anim}, slow_layer, 4.0).get("objects", {}).get("obj_1", {}).get("position", Vector3.ZERO)
	_check(_vec_approx(loop_end, Vector3.ZERO), "a loop clip wraps at the strip end")
	var clamp_end: Vector3 = _mixer_eval({"a": _position_anim(2.0, Vector3.ZERO, Vector3(1, 0, 0))}, slow_layer, 4.0).get("objects", {}).get("obj_1", {}).get("position", Vector3.ZERO)
	_check(_vec_approx(clamp_end, Vector3(1, 0, 0)), "a non-looping clip clamps at the strip end")

	# 200 tracks x 60 samples, evaluated 60 times.
	var perf_clips := {}
	var perf_tracks := 200
	var perf_anim := Animation.new()
	perf_anim.length = 2.0
	for i in range(perf_tracks):
		var track := perf_anim.add_track(Animation.TYPE_POSITION_3D)
		perf_anim.track_set_path(track, NodePath("obj_%d:position" % i))
		for k in range(60):
			var t := 2.0 * float(k) / 59.0
			perf_anim.position_track_insert_key(track, t, Vector3(float(i), t, 0.0))
	perf_clips["perf"] = perf_anim
	var perf_ids := PackedStringArray()
	var perf_bases := {}
	for i in range(perf_tracks):
		perf_ids.append("obj_%d" % i)
		perf_bases["obj_%d" % i] = _base()
	var perf_layer := [_layer("base", [_strip("perf", 0.0, 0.0, 2.0)])]
	var started := Time.get_ticks_usec()
	for s in range(60):
		Mixer.evaluate(perf_clips, perf_layer, 2.0 * float(s) / 59.0, perf_ids, perf_bases, {})
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	print("ANIMATION PERF: %.2f ms" % elapsed_ms)
	_check(elapsed_ms < 750.0, "mixer evaluates 200 tracks x 60 samples under 750 ms (%.2f ms)" % elapsed_ms)


# -------------------------------------------------------------------------
# Model, serialization and transport
# -------------------------------------------------------------------------

func _new_doc() -> Node3D:
	var doc = DocumentScript.new()
	add_child(doc)
	await get_tree().process_frame
	return doc


func _free_doc(doc: Node3D) -> void:
	if doc != null and is_instance_valid(doc):
		doc.queue_free()
		await get_tree().process_frame


func _v1_data() -> Dictionary:
	return {
		"format": 1,
		"title": "V1 Take",
		"fps": 24,
		"duration": 2.0,
		"loop": false,
		"interpolation": "linear",
		"current_time": 0.0,
		"selected_id": "1",
		"autokey": false,
		"snap": true,
		"objects": [{
			"id": "1",
			"name": "Cube",
			"kind": "mesh",
			"primitive": "box",
			"position": [0, 0, 0],
			"rotation": [0, 0, 0, 1],
			"scale": [1, 1, 1],
		}],
		"animation": {
			"name": "Take 01",
			"length": 2.0,
			"loop": false,
			"tracks": [{
				"path": "Object_1:position",
				"type": Animation.TYPE_POSITION_3D,
				"interpolation": Animation.INTERPOLATION_LINEAR,
				"keys": [
					{"t": 0.0, "v": [0, 0, 0], "e": 1.0},
					{"t": 2.0, "v": [1, 0, 0], "e": 1.0},
				],
			}],
		},
	}


func _test_model() -> void:
	# v1 migration through Document.load_project.
	var doc := await _new_doc()
	_check(doc.load_project(_v1_data()), "a v1 project loads")
	var sys = doc.animation_system
	_check(sys.clip_ids().size() == 1, "v1 migration creates exactly one clip")
	var migrated_id: String = sys.clip_ids()[0] if sys.clip_ids().size() > 0 else ""
	var migrated: Dictionary = sys.get_clip(migrated_id)
	_check(str(migrated.get("name", "")) == "Take 01", "v1 clip is named Take 01")
	_check(_approx(float(migrated.get("duration", 0.0)), 2.0), "v1 clip keeps its duration")
	_check(bool(migrated.get("loop", true)) == false, "v1 clip keeps its loop flag")
	var migrated_layers: Array = sys.layers()
	_check(migrated_layers.size() == 1, "v1 migration creates one layer")
	var migrated_strips: Array = migrated_layers[0].get("strips", []) if migrated_layers.size() > 0 else []
	_check(migrated_strips.size() == 1, "v1 migration creates one strip")
	if migrated_strips.size() == 1:
		_check(_approx(float(migrated_strips[0].get("start", -1.0)), 0.0), "v1 strip starts at zero")
	var migrated_anim: Animation = sys.animation_for(migrated_id)
	_check(migrated_anim != null and migrated_anim.get_track_count() == 1, "v1 migration keeps the track")
	_check(migrated_anim != null and migrated_anim.track_get_key_count(0) == 2, "v1 migration keeps both keys")
	var saved_v2: Dictionary = doc.to_data()
	_check(int(saved_v2.get("format", 0)) == 2, "v1 save upgrades the format to v2")
	_check(saved_v2.has("clips") and not saved_v2.has("animation"), "v2 save writes clips and drops the v1 mirror")

	# v2 roundtrip.
	var doc2 := await _new_doc()
	_check(doc2.load_project(saved_v2), "a v2 project loads")
	var sys2 = doc2.animation_system
	_check(sys2.clip_ids().size() == 1, "v2 roundtrip keeps one clip")
	var round_anim: Animation = sys2.animation_for(sys2.clip_ids()[0])
	_check(round_anim != null and round_anim.track_get_key_count(0) == 2, "v2 roundtrip keeps keys")
	if round_anim != null and round_anim.track_get_key_count(0) == 2:
		var key_value: Vector3 = round_anim.track_get_key_value(0, 1)
		_check(_vec_approx(key_value, Vector3(1, 0, 0)), "v2 roundtrip keeps key values")
	_check(str(round_anim.track_get_path(0)) == "Object_1:position", "v2 roundtrip keeps track paths")
	await _free_doc(doc2)

	# Clip CRUD and independent duplicates.
	var crud := await _new_doc()
	crud.new_project("CRUD", "blank")
	var csys = crud.animation_system
	var clip_a: String = csys.create_clip("A", 2.0)
	var anim_a: Animation = csys.animation_for(clip_a)
	var tr := anim_a.add_track(Animation.TYPE_POSITION_3D)
	anim_a.track_set_path(tr, NodePath("Object_1:position"))
	anim_a.position_track_insert_key(tr, 0.0, Vector3.ZERO)
	anim_a.position_track_insert_key(tr, 2.0, Vector3(1, 0, 0))
	var clip_c: String = csys.duplicate_clip(clip_a)
	_check(clip_c != "" and clip_c != clip_a, "duplicate_clip returns a new id")
	var anim_c: Animation = csys.animation_for(clip_c)
	_check(anim_c != null and anim_c != anim_a, "duplicate_clip deep-copies the Animation resource")
	if anim_c != null:
		anim_c.track_set_key_value(0, 1, Vector3(9, 0, 0))
		_check(_vec_approx(anim_a.track_get_key_value(0, 1), Vector3(1, 0, 0)), "editing a duplicate leaves the source clip unchanged")
	csys.rename_clip(clip_a, "Walk")
	_check(str(csys.get_clip(clip_a).get("name", "")) == "Walk", "rename_clip updates the clip name")
	var default_id: String = csys.clip_ids()[0]
	var referenced: bool = bool(csys.delete_clip(default_id))
	_check(not referenced, "delete_clip blocks a clip referenced by a strip")
	_check(str(csys.last_error) != "", "blocked clip deletion reports a concrete reason")

	# Strip move, trim and speed.
	for layer in csys.layers():
		for strip in layer.get("strips", []):
			csys.delete_strip(str(strip.get("id", "")))
	var strip_id: String = csys.add_strip(str(csys.layers()[0]["id"]), clip_a, 0.0)
	_check(strip_id != "", "add_strip creates a strip")
	_check(_approx(float(csys.sequence_duration()), 2.0), "sequence duration starts at the clip length")
	csys.update_strip(strip_id, {"start": 1.0})
	_check(_approx(float(csys.sequence_duration()), 3.0), "moving a strip extends the sequence")
	csys.update_strip(strip_id, {"trim_end": 1.0})
	_check(_approx(float(csys.sequence_duration()), 2.0), "trimming the strip shortens the sequence")
	csys.update_strip(strip_id, {"speed": 2.0})
	_check(_approx(float(csys.sequence_duration()), 1.5), "strip speed scales the sequence end")
	csys.update_strip(strip_id, {"start": 0.5, "trim_start": 0.5, "trim_end": 1.5, "speed": 2.0})
	var strip_data: Dictionary = csys.strip_at(0.75)
	_check(not strip_data.is_empty(), "strip_at finds the active strip")
	if not strip_data.is_empty():
		_check(_approx(float(csys.local_time(strip_data, 0.75)), 1.0), "local_time applies trim, speed and start")

	# Layer weight, mute, solo and the last-layer guard.
	var layer_b: String = csys.add_layer("Overlay")
	_check(layer_b != "", "add_layer creates a layer")
	csys.update_layer(layer_b, {"weight": 0.5, "blend": "additive", "muted": true, "solo": true})
	var layer_data: Dictionary = csys.get_layer(layer_b)
	_check(_approx(float(layer_data.get("weight", 0.0)), 0.5), "update_layer stores weight")
	_check(str(layer_data.get("blend", "")) == "additive", "update_layer stores the blend mode")
	_check(bool(layer_data.get("muted", false)) and bool(layer_data.get("solo", false)), "update_layer stores mute and solo")
	_check(csys.delete_layer(layer_b), "delete_layer removes a non-last layer")
	_check(not csys.delete_layer(str(csys.layers()[0]["id"])), "delete_layer blocks the last layer")
	_check(str(csys.last_error) != "", "blocked layer deletion reports a concrete reason")

	# Per-clip loop survives switching the active clip.
	var loop_doc := await _new_doc()
	loop_doc.new_project("Loop", "blank")
	var loopsys = loop_doc.animation_system
	var loop_a: String = loopsys.active_clip_id()
	loopsys.set_clip_loop(loop_a, true)
	var loop_b: String = loopsys.create_clip("No loop", 1.0)
	loopsys.set_clip_loop(loop_b, false)
	loop_doc.set_active_clip(loop_b)
	_check(not bool(loop_doc.loop), "switching to a non-looping clip updates doc.loop")
	loop_doc.set_active_clip(loop_a)
	_check(bool(loop_doc.loop), "switching back restores the looping clip flag")
	await _free_doc(loop_doc)

	# Sequence transport keeps clip and sequence clocks exclusive.
	var seq := await _new_doc()
	seq.new_project("Sequence", "blank")
	seq.set_process(false)
	var seqsys = seq.animation_system
	seq.seek_sequence(0.5)
	_check(_approx(seq.sequence_time(), 0.5), "seek_sequence sets the global playhead")
	_check(_approx(seq.animation_system.active_local_time(), 0.5), "active_local_time follows the active strip")
	seq.play_sequence()
	_check(seq.is_sequence_playing() and seqsys.is_sequence_playing(), "play_sequence starts the sequence clock")
	seqsys.advance(0.25)
	_check(_approx(seq.sequence_time(), 0.75), "advance moves the sequence clock")
	seq.pause_sequence()
	_check(not seq.is_sequence_playing() and not seqsys.is_sequence_playing(), "pause_sequence stops the sequence clock")
	seq.play_sequence()
	seq.play()
	_check(not seq.is_sequence_playing() and not seqsys.is_sequence_playing(), "clip play stops sequence playback")
	seq.stop_sequence()
	_check(_approx(seq.sequence_time(), 0.0), "stop_sequence rewinds the sequence")
	await _free_doc(seq)

	await _free_doc(crud)
	await _free_doc(doc)


# -------------------------------------------------------------------------
# glTF/GLB embedded animation
# -------------------------------------------------------------------------

func _export_glb(path: String, with_animation: bool) -> bool:
	var root := Node3D.new()
	root.name = "AnimRoot"
	var mesh := MeshInstance3D.new()
	mesh.name = "Cube"
	mesh.mesh = BoxMesh.new()
	root.add_child(mesh)
	if with_animation:
		var player := AnimationPlayer.new()
		player.name = "AnimationPlayer"
		player.root_node = NodePath("..")
		var anim := Animation.new()
		anim.length = 2.0
		var track := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(track, NodePath("Cube:position"))
		anim.position_track_insert_key(track, 0.0, Vector3.ZERO)
		anim.position_track_insert_key(track, 2.0, Vector3(0, 1, 0))
		var library := AnimationLibrary.new()
		library.add_animation("Bounce", anim)
		player.add_animation_library("", library)
		root.add_child(player)
	add_child(root)
	await get_tree().process_frame
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_scene(root, state)
	if err == OK:
		err = gltf.write_to_filesystem(state, path)
	root.queue_free()
	await get_tree().process_frame
	return err == OK


func _test_import() -> void:
	var doc := await _new_doc()
	doc.new_project("Import", "blank")
	doc.project_dir = "user://projects/ws_a_import"
	DirAccess.make_dir_recursive_absolute(doc.project_dir)
	var sys = doc.animation_system
	var before_count: int = sys.clip_ids().size()
	var signal_counter := func(_object_id: String, _node: Node) -> void:
		_import_signal_count += 1
	doc.imported_scene_ready.connect(signal_counter)

	var glb_path := "user://ws_a_anim_%d.glb" % Time.get_ticks_msec()
	var exported := await _export_glb(glb_path, true)
	_check(exported, "a runtime GLB with an embedded animation is written")
	if not exported:
		await _free_doc(doc)
		return
	var imported := Store.import_model(glb_path, doc.project_dir, "Anim")
	_check(bool(imported.get("ok", false)), "ProjectStore imports the runtime GLB")
	if bool(imported.get("ok", false)):
		var object_id: String = doc.add_imported(str(imported.get("rel_path", "")), "Anim")
		_check(object_id != "", "Document.add_imported spawns the object")
		_check(_import_signal_count == 1, "imported_scene_ready fires once on import")
		_check(sys.clip_ids().size() == before_count + 1, "embedded animation becomes one clip")
		var imported_clip: String = sys.clip_ids()[sys.clip_ids().size() - 1] if sys.clip_ids().size() > 0 else ""
		var imported_anim: Animation = sys.animation_for(imported_clip)
		_check(imported_anim != null and imported_anim.get_track_count() == 1, "imported clip keeps the supported track")
		if imported_anim != null and imported_anim.get_track_count() == 1:
			var object_node: Node = doc.nodes.get(object_id)
			var object_name := str(object_node.name) if object_node != null else ""
			_check(str(imported_anim.track_get_path(0)).begins_with(object_name + "/"), "imported track path is remapped under the object node")
		_check(str(sys.get_clip(imported_clip).get("name", "")).contains("·"), "imported clip is named object · animation")
		var imported_layer: Dictionary = {}
		for layer in sys.layers():
			if str(layer.get("name", "")) == "Imported":
				imported_layer = layer
		_check(not imported_layer.is_empty(), "import creates an Imported layer")
		var imported_strips: Array = imported_layer.get("strips", [])
		_check(imported_strips.size() == 1 and _approx(float(imported_strips[0].get("start", -1.0)), 0.0), "import places the first animation on an Imported strip at zero")
		var players: Array = doc.nodes[object_id].find_children("*", "AnimationPlayer", true, false) if doc.nodes.has(object_id) else []
		var all_inactive := true
		for player in players:
			if bool(player.active):
				all_inactive = false
		_check(all_inactive, "every imported AnimationPlayer is inactive")
		_check(bool(doc.is_playing), "the first imported clip auto-plays")

		# Undo/redo and load must not fire the import-only signal.
		doc.undo()
		_check(_import_signal_count == 1, "undo does not re-fire imported_scene_ready")
		doc.redo()
		_check(_import_signal_count == 1, "redo does not re-fire imported_scene_ready")
		var saved: Dictionary = doc.to_data()
		var saved_dir: String = doc.project_dir
		doc.load_project(saved, saved_dir)
		_check(_import_signal_count == 1, "load_project does not re-fire imported_scene_ready")
		_check(sys.clip_ids().size() == before_count + 1, "v2 load restores the imported clip")

	# A GLB without animation imports but creates no clip.
	var count_before_empty: int = sys.clip_ids().size()
	var empty_path := "user://ws_a_empty_%d.glb" % Time.get_ticks_msec()
	var exported_empty := await _export_glb(empty_path, false)
	_check(exported_empty, "a runtime GLB without animation is written")
	if exported_empty:
		var imported_empty := Store.import_model(empty_path, doc.project_dir, "Empty")
		_check(bool(imported_empty.get("ok", false)), "ProjectStore imports the animation-free GLB (%s)" % str(imported_empty.get("error", "")))
		if bool(imported_empty.get("ok", false)):
			var empty_id: String = doc.add_imported(str(imported_empty.get("rel_path", "")), "Empty")
			_check(empty_id != "", "the animation-free object spawns")
			_check(sys.clip_ids().size() == count_before_empty, "an animation-free GLB creates no clip")
	await _free_doc(doc)


# -------------------------------------------------------------------------
# Clip lane and sheets
# -------------------------------------------------------------------------

func _test_ui() -> void:
	var lane_script = load(LANE_PATH)
	_check(lane_script != null, "clip_lane.gd exists")
	if lane_script == null:
		return
	var doc := await _new_doc()
	doc.new_project("Lane", "blank")
	doc.set_process(false)
	var sys = doc.animation_system
	var clip_b: String = sys.create_clip("Second", 3.0)
	var layer_b: String = sys.add_layer("Overlay")
	var strip_b: String = sys.add_strip(layer_b, clip_b, 0.5)
	_check(strip_b != "", "the lane fixture has a second strip")

	var host := Control.new()
	host.size = Vector2(900, 420)
	add_child(host)
	var lane: Control = lane_script.new()
	host.add_child(lane)
	lane.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	lane.setup(doc)
	lane.strip_selected.connect(func(strip_id: String, clip_id: String) -> void:
		_ui_signal_count += 1
		_ui_selected_strip = strip_id
	)
	lane.sheet_requested.connect(func(control: Control, _title: String, _subtitle: String) -> void:
		_ui_sheet = control
	)
	await get_tree().process_frame
	lane.refresh()
	await get_tree().process_frame
	_check(lane.layer_row_count() == 2, "clip lane draws one row per layer")
	_check(lane.strip_block_count() == 2, "clip lane draws one block per strip")
	_check(lane.play_sequence_button() != null and lane.play_sequence_button().custom_minimum_size.y >= 44.0, "clip lane has a 44 dp Play sequence button")
	_check(lane.play_sequence_button().custom_minimum_size.x >= 44.0, "Play sequence keeps a 44 dp width")
	var rect: Rect2 = lane.strip_rect(strip_b)
	_check(rect.size.y >= 44.0, "strip blocks are 44 dp tall")
	var fade_rects: Array = lane.fade_handle_rects()
	var fade_ok := not fade_rects.is_empty()
	for fade_rect in fade_rects:
		if fade_rect.size.x < 44.0 or fade_rect.size.y < 44.0:
			fade_ok = false
	_check(fade_ok, "fade handles expose 44x44 hit areas")
	_check(lane.row_height() >= 44.0, "layer rows are 44 dp")
	lane.tap_strip(strip_b)
	await get_tree().process_frame
	_check(doc.active_clip_id() == clip_b, "tapping a strip selects its clip through Document")
	_check(_ui_signal_count == 1 and _ui_selected_strip == strip_b, "tapping a strip emits strip_selected")
	_check(_ui_sheet != null, "tapping a strip builds a strip sheet")

	var clip_sheet_script = load(CLIP_SHEET_PATH)
	_check(clip_sheet_script != null, "clip_sheet.gd exists")
	if clip_sheet_script != null:
		var clip_sheet: Control = clip_sheet_script.new()
		host.add_child(clip_sheet)
		clip_sheet.setup(doc)
		clip_sheet.open()
		await get_tree().process_frame
		_check(clip_sheet.clip_row_count() == sys.clip_ids().size(), "clip sheet lists every clip")
		_check(clip_sheet.new_button().custom_minimum_size.y >= 44.0, "clip sheet New is a 44 dp target")
		_check(clip_sheet.duplicate_button().custom_minimum_size.y >= 44.0, "clip sheet Duplicate is a 44 dp target")
		clip_sheet.queue_free()

	var layer_sheet_script = load(LAYER_SHEET_PATH)
	_check(layer_sheet_script != null, "layer_sheet.gd exists")
	if layer_sheet_script != null:
		var layer_sheet: Control = layer_sheet_script.new()
		host.add_child(layer_sheet)
		layer_sheet.setup(doc)
		layer_sheet.open(layer_b)
		await get_tree().process_frame
		_check(layer_sheet.weight_slider().custom_minimum_size.y >= 44.0, "layer weight slider is a 44 dp target")
		_check(layer_sheet.new_layer_button() != null and layer_sheet.new_layer_button().custom_minimum_size.y >= 44.0, "layer sheet New layer is a 44 dp target")
		_check(layer_sheet.delete_button() != null, "layer sheet has a delete action")
		layer_sheet.queue_free()

	var strip_sheet_script = load(STRIP_SHEET_PATH)
	_check(strip_sheet_script != null, "strip_sheet.gd exists")
	if strip_sheet_script != null:
		var strip_sheet: Control = strip_sheet_script.new()
		host.add_child(strip_sheet)
		strip_sheet.setup(doc)
		strip_sheet.open(strip_b)
		await get_tree().process_frame
		_check(strip_sheet.field("speed") != null and strip_sheet.field("speed").custom_minimum_size.y >= 44.0, "strip speed field is a 44 dp target")
		_check(strip_sheet.field("fade_in") != null, "strip sheet exposes fade in")
		_check(strip_sheet.field("fade_out") != null, "strip sheet exposes fade out")
		strip_sheet.queue_free()

	await _free_doc(doc)
