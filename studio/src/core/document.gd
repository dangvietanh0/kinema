extends Node3D
## Scene + animation document.
##
## The document is also the world root inside the preview SubViewport. Object
## nodes are plain Node3D roots, which keeps the animation tracks stable and
## makes the file format straightforward. Transform animation is stored in a
## single Godot Animation resource and played by an AnimationPlayer.

signal scene_changed
signal selection_changed(id: String)
signal object_changed(id: String)
## Emitted when only the transform of an object changed. Listeners that need
## live values (preview, inspector values, gizmo) use this; listeners that
## rebuild structure (outliner rows, panel sections) ignore it.
signal transform_changed(id: String)
## Emitted after any track, key or interpolation edit.
signal keyframes_changed(id: String)
signal playback_changed(time: float, is_playing: bool)
signal history_changed
signal dirty_changed(is_dirty: bool)
signal clips_changed
signal active_clip_changed(id: String)
signal media_changed
signal rigs_changed
signal rig_selection_changed(rig_id: String, bone: String)
signal imported_scene_ready(object_id: String, node: Node)
signal rig_adopted(object_id: String, bone_count: int)
signal object_spawned(object_id: String, node: Node)
## Emitted when the selected import part changes. An empty id/path pair means
## the part highlight was cleared; the import root stays selected either way.
signal part_selection_changed(object_id: String, part_path: String)

const CHANNELS := ["position", "rotation", "scale"]
const CHANNEL_LABELS := {
	"position": "Position",
	"rotation": "Rotation",
	"scale": "Scale",
}
const CHANNEL_ICONS := {
	"position": "tool-move",
	"rotation": "tool-rotate",
	"scale": "tool-scale",
}
const ObjImporter = preload("res://src/core/obj_importer.gd")
const AnimationSystemScript = preload("res://src/core/animation_system.gd")
const MediaSystemScript = preload("res://src/core/media_system.gd")
const RigSystemScript = preload("res://src/core/rig_system.gd")
const TRACK_TYPES := {
	"position": Animation.TYPE_POSITION_3D,
	"rotation": Animation.TYPE_ROTATION_3D,
	"scale": Animation.TYPE_SCALE_3D,
}
const ANIMATION_NAME := "Take 01"
const FORMAT_VERSION := 2

var project_id := ""
var project_dir := ""
var title := "Untitled"
var fps := 24
var duration := 8.0
var loop := true
var interpolation := "linear"
var autokey := false
var snap := true
var selected_id := ""
## The selected part belongs to the selected import root; the inspector still
## edits the root transform.
var selected_part_object_id := ""
var selected_part_path := ""
var objects: Array[Dictionary] = []

var nodes: Dictionary = {}
var anim_player: AnimationPlayer
var animation: Animation
var current_time := 0.0
var is_playing := false
var markers_hidden := false
var animation_system
var media_system
var rig_system

var _dirty := false
var _edit_snapshot: Dictionary = {}
var _edit_label := ""
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _loading := false
var _next_id := 1
var _last_emitted_time := -1.0
var _sequence_playing := false

func _init() -> void:
	animation_system = AnimationSystemScript.new()
	animation_system.setup(self)
	media_system = MediaSystemScript.new()
	media_system.setup(self)
	rig_system = RigSystemScript.new()
	rig_system.setup(self)
	imported_scene_ready.connect(animation_system.on_imported_scene)
	imported_scene_ready.connect(rig_system.adopt_imported_skeleton)

func _ready() -> void:
	process_priority = 100
	_ensure_player()
	set_process(true)

func _process(delta: float) -> void:
	if _loading or anim_player == null:
		return
	# Exactly one clock runs at a time. Sequence mode owns the time update and
	# leaves the AnimationPlayer alone; clip mode keeps the player fast path.
	if _sequence_playing:
		animation_system.advance(delta)
		current_time = animation_system.active_local_time()
		if not animation_system.is_sequence_playing():
			_sequence_playing = false
			playback_changed.emit(current_time, false)
		elif absf(current_time - _last_emitted_time) > 0.0005:
			_last_emitted_time = current_time
			playback_changed.emit(current_time, true)
		rig_system.advance(delta)
		media_system.advance(delta)
		return
	if is_playing:
		if anim_player.is_playing():
			current_time = anim_player.current_animation_position
			if absf(current_time - _last_emitted_time) > 0.0005:
				_last_emitted_time = current_time
				playback_changed.emit(current_time, true)
		else:
			is_playing = false
			current_time = clampf(anim_player.current_animation_position, 0.0, duration)
			playback_changed.emit(current_time, false)
	animation_system.advance(delta)
	rig_system.advance(delta)
	media_system.advance(delta)

func _ensure_player() -> void:
	if anim_player != null and is_instance_valid(anim_player):
		return
	anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	anim_player.root_node = NodePath("..")
	anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	add_child(anim_player)
	anim_player.animation_finished.connect(_on_animation_finished)

func _on_animation_finished(_anim_name: StringName) -> void:
	if loop:
		# Looping animations are restarted by the AnimationPlayer itself.
		return
	is_playing = false
	current_time = duration
	playback_changed.emit(current_time, false)

# -------------------------------------------------------------------------
# Project lifecycle
# -------------------------------------------------------------------------

func new_project(p_title: String = "Untitled", template: String = "blank") -> void:
	_loading = true
	project_id = ""
	title = p_title
	fps = 24
	duration = 8.0
	loop = true
	interpolation = "linear"
	autokey = false
	snap = true
	_next_id = 1
	objects.clear()
	selected_id = ""
	selected_part_object_id = ""
	selected_part_path = ""
	_clear_runtime()
	_ensure_player()
	_create_animation()
	animation_system.ensure_default_clip()
	var active: Animation = animation_system.active_animation()
	if active != null:
		animation = active
	_dirty = false
	if template == "study":
		_build_study()
	else:
		_build_blank()
	_loading = false
	_dirty = false
	_undo_stack.clear()
	_redo_stack.clear()
	dirty_changed.emit(false)
	history_changed.emit()
	scene_changed.emit()
	if selected_id != "":
		selection_changed.emit(selected_id)
	seek(0.0, true)

func load_project(data: Dictionary, p_project_dir: String = "") -> bool:
	project_dir = p_project_dir
	_loading = true
	_clear_runtime()
	_ensure_player()
	_apply_data(data)
	_loading = false
	_dirty = false
	_undo_stack.clear()
	_redo_stack.clear()
	dirty_changed.emit(false)
	history_changed.emit()
	scene_changed.emit()
	selection_changed.emit(selected_id)
	seek(current_time, true)
	return true

func to_data() -> Dictionary:
	var tracks: Array = []
	if animation != null:
		for ti in range(animation.get_track_count()):
			var track: Dictionary = {
				"path": str(animation.track_get_path(ti)),
				"type": animation.track_get_type(ti),
				"interpolation": animation.track_get_interpolation_type(ti),
				"keys": [],
			}
			for ki in range(animation.track_get_key_count(ti)):
				track["keys"].append({
					"t": float(animation.track_get_key_time(ti, ki)),
					"v": _value_to_json(animation.track_get_key_value(ti, ki)),
					"e": float(animation.track_get_key_transition(ti, ki)),
				})
			tracks.append(track)
	var json_objects: Array = []
	for obj in objects:
		json_objects.append(_object_to_json(obj))
	var anim_data: Dictionary = animation_system.to_data() if animation_system != null else {}
	var rig_data: Dictionary = rig_system.to_data() if rig_system != null else {}
	var media_data: Dictionary = media_system.to_data() if media_system != null else {}
	var clips: Array = anim_data.get("clips", [])
	var data := {
		"format": FORMAT_VERSION,
		"title": title,
		"fps": fps,
		"duration": duration,
		"loop": loop,
		"interpolation": interpolation,
		"current_time": current_time,
		"selected_id": selected_id,
		"selected_part_object_id": selected_part_object_id,
		"selected_part_path": selected_part_path,
		"autokey": autokey,
		"snap": snap,
		"objects": json_objects,
		"clips": clips,
		"layers": anim_data.get("layers", []),
		"rigs": rig_data.get("rigs", []),
		"media": media_data.get("media", {}),
	}
	if anim_data.has("active_clip"):
		data["active_clip"] = anim_data["active_clip"]
	if anim_data.has("active_layer"):
		data["active_layer"] = anim_data["active_layer"]
	if clips.is_empty():
		# v1 bridge: single-clip projects keep the legacy mirror readable until
		# WS-A returns real clips. It disappears as soon as a clip exists.
		data["animation"] = {
			"name": ANIMATION_NAME,
			"length": duration,
			"loop": loop,
			"tracks": tracks,
		}
	return data

func _apply_data(data: Dictionary) -> void:
	title = str(data.get("title", "Untitled"))
	fps = int(data.get("fps", 24))
	duration = maxf(0.04, float(data.get("duration", 8.0)))
	loop = bool(data.get("loop", true))
	interpolation = str(data.get("interpolation", "linear"))
	autokey = bool(data.get("autokey", false))
	snap = bool(data.get("snap", true))
	current_time = clampf(float(data.get("current_time", 0.0)), 0.0, duration)
	selected_id = str(data.get("selected_id", ""))
	selected_part_object_id = str(data.get("selected_part_object_id", ""))
	selected_part_path = str(data.get("selected_part_path", ""))
	_next_id = 1

	objects.clear()
	var raw_objects: Array = data.get("objects", [])
	for raw in raw_objects:
		if raw is Dictionary:
			var obj := _normalize_object(raw)
			objects.append(obj)
			_next_id = maxi(_next_id, int(obj["id"]) + 1)

	_create_animation()
	for obj in objects:
		_spawn_object(obj)

	var anim_data: Dictionary = data.get("animation", {})
	if not anim_data.is_empty():
		_load_animation_tracks(anim_data)
	animation_system.load_data(data, nodes)
	rig_system.load_data(data, nodes)
	media_system.load_data(data, project_dir)
	var active: Animation = animation_system.active_animation()
	if active != null:
		animation = active
	_refresh_animation()
	_ensure_valid_selection()
	# A saved part path can outlive the model it pointed at. Drop it silently
	# instead of selecting the import root's stale highlight.
	if selected_part_object_id == "" or selected_part_path == "" \
			or get_import_part_node(selected_part_object_id, selected_part_path) == null:
		selected_part_object_id = ""
		selected_part_path = ""
	_queue_all_object_ui_updates()

func _object_to_json(obj: Dictionary) -> Dictionary:
	var copy := obj.duplicate(true)
	copy["position"] = _value_to_json(obj.get("position", Vector3.ZERO))
	copy["rotation"] = _value_to_json(obj.get("rotation", Quaternion.IDENTITY))
	copy["scale"] = _value_to_json(obj.get("scale", Vector3.ONE))
	return copy

func _normalize_object(raw: Dictionary) -> Dictionary:
	var kind := str(raw.get("kind", "mesh"))
	var obj := _base_object(str(raw.get("id", str(_next_id * 7))), str(raw.get("name", "Object")), kind)
	obj["primitive"] = str(raw.get("primitive", "box"))
	obj["visible"] = bool(raw.get("visible", true))
	obj["position"] = _json_to_vec3(raw.get("position", [0, 0, 0]))
	obj["rotation"] = _json_to_quat(raw.get("rotation", [0, 0, 0, 1]))
	obj["scale"] = _json_to_vec3(raw.get("scale", [1, 1, 1]))
	obj["color"] = str(raw.get("color", "#A8A8A8"))
	obj["roughness"] = clampf(float(raw.get("roughness", 0.48)), 0.0, 1.0)
	obj["metallic"] = clampf(float(raw.get("metallic", 0.0)), 0.0, 1.0)
	obj["light_type"] = str(raw.get("light_type", "directional"))
	obj["light_energy"] = float(raw.get("light_energy", 1.2))
	obj["light_color"] = str(raw.get("light_color", "#F0F0F0"))
	obj["light_range"] = float(raw.get("light_range", 8.0))
	obj["light_shadow"] = bool(raw.get("light_shadow", true))
	obj["camera_fov"] = float(raw.get("camera_fov", 45.0))
	obj["model"] = str(raw.get("model", ""))
	obj["part_visibility"] = _normalize_part_visibility(raw.get("part_visibility", {}))
	return obj


func _normalize_part_visibility(raw: Variant) -> Dictionary:
	var result := {}
	if not (raw is Dictionary):
		return result
	for key in raw.keys():
		var value: Variant = raw[key]
		if not (key is String):
			continue
		if not (value is bool):
			continue
		result[key] = value
	return result


func _base_object(id: String, p_name: String, kind: String) -> Dictionary:
	return {
		"id": id,
		"name": p_name,
		"kind": kind,
		"primitive": "box",
		"visible": true,
		"position": Vector3.ZERO,
		"rotation": Quaternion.IDENTITY,
		"scale": Vector3.ONE,
		"color": "#A8A8A8",
		"roughness": 0.48,
		"metallic": 0.0,
		"light_type": "directional",
		"light_energy": 1.2,
		"light_color": "#F0F0F0",
		"light_range": 8.0,
		"light_shadow": true,
		"camera_fov": 45.0,
		"model": "",
		"part_visibility": {},
	}

func _build_blank() -> void:
	_add_camera_data("Main Camera", Vector3(4.0, 3.15, 5.2), Vector3(0.0, 0.65, 0.0), false)
	_add_light_data("Key Light", "directional", Vector3(0.0, 5.0, 0.0), Vector3(-38, -28, 0), false)
	# A real selectable fill so the shadow side is readable out of the box.
	# It is an honest document object, not an editor-only cheat: it appears in
	# the outliner, the inspector and the render with shadows deliberately off.
	var fill := _add_light_data("Fill Light", "omni", Vector3(2.6, 2.2, 3.0), Vector3.ZERO, false)
	fill["light_energy"] = 0.35
	fill["light_range"] = 7.0
	fill["light_shadow"] = false
	_spawn_refresh(str(fill["id"]))
	var cube := _add_primitive_data("Cube", "box", Vector3(0.0, 0.5, 0.0), false)
	selected_id = str(cube["id"])
	_add_default_keys_for_cube(str(cube["id"]))
	_sync_sun_sky_mode()

func _build_study() -> void:
	_add_camera_data("Main Camera", Vector3(5.2, 3.5, 6.4), Vector3(0.0, 0.8, 0.0), false)
	# Three-point studio lighting with neutral white lights: a key with real
	# soft shadows, a fill to keep the shadow side readable, and a rim for
	# separation. The starter scene is a graphite sculpture, not a colour demo.
	var key := _add_light_data("Key Light", "directional", Vector3(0.0, 5.0, 0.0), Vector3(-42, -34, 0), false)
	key["light_energy"] = 1.8
	key["light_color"] = "#F2F2F2"
	_spawn_refresh(str(key["id"]))
	var fill := _add_light_data("Fill Light", "omni", Vector3(3.1, 2.1, 2.7), Vector3.ZERO, false)
	fill["light_energy"] = 0.5
	fill["light_color"] = "#D0D0D0"
	fill["light_range"] = 9.0
	fill["light_shadow"] = false
	_spawn_refresh(str(fill["id"]))
	var rim := _add_light_data("Rim Light", "omni", Vector3(-2.4, 2.7, -2.2), Vector3.ZERO, false)
	rim["light_energy"] = 1.2
	rim["light_color"] = "#E6E6E6"
	rim["light_shadow"] = false
	_spawn_refresh(str(rim["id"]))
	var sphere := _add_primitive_data("Form", "sphere", Vector3(0.0, 1.0, 0.0), false)
	sphere["color"] = "#B8B8B8"
	sphere["roughness"] = 0.38
	_spawn_refresh(str(sphere["id"]))
	var ring := _add_primitive_data("Orbit", "torus", Vector3(0.0, 1.15, 0.0), false)
	ring["color"] = "#D8D8D8"
	ring["rotation"] = Quaternion(Vector3.RIGHT, deg_to_rad(62.0))
	ring["scale"] = Vector3(1.5, 1.5, 1.5)
	_spawn_refresh(str(ring["id"]))
	var base := _add_primitive_data("Base", "cylinder", Vector3(0.0, 0.14, 0.0), false)
	base["color"] = "#2E2E2E"
	base["scale"] = Vector3(2.05, 0.28, 2.05)
	base["roughness"] = 0.68
	_spawn_refresh(str(base["id"]))
	selected_id = str(ring["id"])
	_animate_study(str(ring["id"]), str(sphere["id"]))

func _animate_study(ring_id: String, sphere_id: String) -> void:
	# A restrained six second loop that immediately demonstrates the animation
	# pipeline without turning the starter scene into a game demo.
	duration = 6.0
	animation.length = duration
	var st := _ensure_track(ring_id, "rotation")
	animation.rotation_track_insert_key(st, 0.0, Quaternion(Vector3.RIGHT, deg_to_rad(62.0)))
	animation.rotation_track_insert_key(st, 3.0, Quaternion(Vector3.RIGHT, deg_to_rad(62.0)) * Quaternion(Vector3.UP, deg_to_rad(180.0)))
	animation.rotation_track_insert_key(st, 6.0, Quaternion(Vector3.RIGHT, deg_to_rad(62.0)) * Quaternion(Vector3.UP, deg_to_rad(360.0)))
	var pt := _ensure_track(sphere_id, "position")
	animation.position_track_insert_key(pt, 0.0, Vector3(0, 1.0, 0))
	animation.position_track_insert_key(pt, 1.5, Vector3(0, 1.22, 0))
	animation.position_track_insert_key(pt, 3.0, Vector3(0, 1.0, 0))
	animation.position_track_insert_key(pt, 4.5, Vector3(0, 1.22, 0))
	animation.position_track_insert_key(pt, 6.0, Vector3(0, 1.0, 0))
	# Cubic interpolation gives the bob a natural pause at each extreme. The
	# speed graph plots this track straight from the animation resource, so
	# the starter scene and the graph agree by construction.
	animation.track_set_interpolation_type(pt, Animation.INTERPOLATION_CUBIC)
	animation.loop_mode = Animation.LOOP_LINEAR
	_refresh_animation()

func _add_default_keys_for_cube(id: String) -> void:
	# No keys by default. The cube stays a clean, editable base pose.
	pass

func _queue_all_object_ui_updates() -> void:
	for obj in objects:
		object_changed.emit(str(obj["id"]))

func _ensure_valid_selection() -> void:
	if selected_id != "" and not nodes.has(selected_id):
		selected_id = ""
	if selected_id == "" and not objects.is_empty():
		for obj in objects:
			if str(obj.get("kind", "")) != "camera":
				selected_id = str(obj["id"])
				break
		if selected_id == "":
			selected_id = str(objects[0]["id"])

# -------------------------------------------------------------------------
# Runtime scene construction
# -------------------------------------------------------------------------

func _clear_runtime() -> void:
	# Subsystems are RefCounted owners of data, not scene children. Reset them
	# before the runtime nodes disappear; never free them here.
	if animation_system != null:
		animation_system.reset()
	if media_system != null:
		media_system.reset()
	if rig_system != null:
		rig_system.reset()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	nodes.clear()
	anim_player = null
	animation = null

func _create_animation() -> void:
	_ensure_player()
	if anim_player.has_animation_library(""):
		anim_player.remove_animation_library("")
	animation = Animation.new()
	animation.length = duration
	animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var library := AnimationLibrary.new()
	library.add_animation(ANIMATION_NAME, animation)
	anim_player.add_animation_library("", library)
	anim_player.play(ANIMATION_NAME)
	anim_player.pause()
	anim_player.seek(0.0, true)

func _spawn_object(obj: Dictionary) -> void:
	var id := str(obj["id"])
	var node := Node3D.new()
	node.name = "Object_" + id
	node.position = _as_vec3(obj.get("position", Vector3.ZERO))
	node.quaternion = _as_quat(obj.get("rotation", Quaternion.IDENTITY))
	node.scale = _as_vec3(obj.get("scale", Vector3.ONE))
	node.visible = bool(obj.get("visible", true))
	node.set_meta("kinema_id", id)
	add_child(node)
	nodes[id] = node
	var kind := str(obj.get("kind", "mesh"))
	match kind:
		"mesh":
			_build_mesh_visual(node, obj)
		"camera":
			_build_camera_visual(node, obj)
		"light":
			_build_light_visual(node, obj)
		"empty":
			_build_empty_visual(node, obj)
		"import":
			_build_import_visual(node, obj)
		_:
			_build_mesh_visual(node, obj)
	if kind == "import":
		# Reapply the saved overrides after the model loads, on fresh imports and
		# on project load / undo alike.
		_apply_import_part_visibility(node, obj)
	if kind == "light":
		_sync_sun_sky_mode()
	if rig_system != null:
		rig_system.on_object_spawned(obj, node)
	object_spawned.emit(id, node)

func _spawn_refresh(id: String) -> void:
	var obj := get_object(id)
	if obj.is_empty():
		return
	var node: Node3D = nodes.get(id)
	if node == null:
		return
	node.position = _as_vec3(obj.get("position", Vector3.ZERO))
	node.quaternion = _as_quat(obj.get("rotation", Quaternion.IDENTITY))
	node.scale = _as_vec3(obj.get("scale", Vector3.ONE))
	_apply_visual_properties(node, obj)

func _build_mesh_visual(node: Node3D, obj: Dictionary) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = _make_primitive(str(obj.get("primitive", "box")))
	var material := StandardMaterial3D.new()
	material.albedo_color = _hex_color(str(obj.get("color", "#AAB2BF")))
	material.roughness = clampf(float(obj.get("roughness", 0.48)), 0.0, 1.0)
	material.metallic = clampf(float(obj.get("metallic", 0.0)), 0.0, 1.0)
	material.metallic_specular = 0.5
	material.rim_enabled = false
	mesh_instance.material_override = material
	node.add_child(mesh_instance)

func _build_camera_visual(node: Node3D, obj: Dictionary) -> void:
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = clampf(float(obj.get("camera_fov", 45.0)), 12.0, 100.0)
	camera.near = 0.05
	camera.far = 500.0
	node.add_child(camera)
	_add_marker(node, _make_camera_marker())

func _build_light_visual(node: Node3D, obj: Dictionary) -> void:
	var light_type := str(obj.get("light_type", "directional"))
	var light: Light3D
	if light_type == "omni":
		var omni := OmniLight3D.new()
		omni.omni_range = float(obj.get("light_range", 8.0))
		omni.omni_attenuation = 1.1
		omni.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
		light = omni
	else:
		var directional := DirectionalLight3D.new()
		light = directional
	light.name = "Light"
	light.light_energy = float(obj.get("light_energy", 1.2))
	light.light_color = _hex_color(str(obj.get("light_color", "#F0F0F0")))
	light.light_specular = 0.55
	_configure_shadows(light, obj)
	node.add_child(light)
	_add_marker(node, _make_light_marker(light_type == "omni"))

func _build_empty_visual(node: Node3D, _obj: Dictionary) -> void:
	# An empty is a real axis triad at the object origin, not a flat dashed
	# icon. It lives under the object node so moving or keying the object moves
	# the triad with it.
	_add_marker(node, _make_empty_marker())

func _configure_shadows(light: Light3D, obj: Dictionary = {}, profile: Dictionary = {}) -> void:
	## Shadow quality is driven by the graphics preferences. Directional lights
	## get cascaded splits, a filtered soft edge and a physical angular size so
	## the PCSS path produces real penumbrae instead of a hard cutout. The
	## document's `light_shadow` flag is honoured here so a fill light can stay
	## honest about not casting. `profile` is the effective, platform-clamped
	## profile; when omitted it is resolved for the running backend.
	if light == null:
		return
	var effective: Dictionary = profile if not profile.is_empty() else Gfx.safe_forward_plus_profile()
	light.shadow_enabled = bool(obj.get("light_shadow", true))
	light.shadow_opacity = 0.55
	light.shadow_bias = 0.022
	light.shadow_normal_bias = 0.9
	light.shadow_blur = 1.05
	if light is DirectionalLight3D:
		var sun := light as DirectionalLight3D
		sun.light_angular_distance = 0.55
		sun.directional_shadow_max_distance = float(effective.get("shadow_distance", Gfx.shadow_distance))
		sun.directional_shadow_blend_splits = true
		sun.directional_shadow_fade_start = 0.82
		sun.directional_shadow_pancake_size = 18.0
		match int(effective.get("shadow_splits", Gfx.shadow_splits)):
			1:
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			3, 4:
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			_:
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	elif light is OmniLight3D:
		pass

func apply_graphics(platform: String = "", actual_method: String = "") -> void:
	var profile: Dictionary = Gfx.safe_forward_plus_profile()
	if platform != "":
		profile = Gfx.safe_forward_plus_profile(platform, actual_method)
	for id in nodes.keys():
		var node: Node3D = nodes[id]
		if node == null:
			continue
		var light := node.get_node_or_null("Light") as Light3D
		if light != null:
			_configure_shadows(light, get_object(str(id)), profile)
	_sync_sun_sky_mode()

## Exactly one visible directional light feeds the procedural sky. The first
## in document order with positive energy owns SKY_MODE_LIGHT_AND_SKY; every
## other directional light is scene-only, so no second disc can appear and the
## disc disappears when no directional light contributes.
func _sync_sun_sky_mode() -> void:
	var assigned := false
	for obj in objects:
		if str(obj.get("kind", "")) != "light":
			continue
		if str(obj.get("light_type", "")) != "directional":
			continue
		var node: Node3D = nodes.get(str(obj.get("id", "")))
		if node == null:
			continue
		var light := node.get_node_or_null("Light") as DirectionalLight3D
		if light == null:
			continue
		var visible := bool(obj.get("visible", true))
		var energy := float(obj.get("light_energy", 1.2))
		if not assigned and visible and energy > 0.0:
			light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
			assigned = true
		else:
			light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY

func _build_import_visual(node: Node3D, obj: Dictionary) -> void:
	var rel := str(obj.get("model", ""))
	var path := project_dir.path_join(rel) if rel != "" else ""
	var generated: Node = null
	if path != "" and FileAccess.file_exists(path):
		if path.get_extension().to_lower() == "obj":
			generated = ObjImporter.new().build(path)
		else:
			var gltf := GLTFDocument.new()
			var state := GLTFState.new()
			var err := gltf.append_from_file(path, state)
			if err == OK:
				generated = gltf.generate_scene(state)
	if generated == null:
		var board := MeshInstance3D.new()
		board.name = "MissingModel"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.6, 0.6, 0.6)
		board.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.22, 0.22, 0.22)
		board.material_override = material
		node.add_child(board)
		push_warning("Kinema: could not load imported model '%s'." % rel)
		return
	generated.name = "Model"
	node.add_child(generated)

func _add_marker(node: Node3D, parts: Array) -> MeshInstance3D:
	# A marker is one shaded MeshInstance3D named "Marker" so it keeps the
	# document's existing bounds contract (marker geometry never inflates the
	# object AABB) while still reading as a solid camera, light or empty.
	var mesh := ArrayMesh.new()
	var colors: Array = []
	for part in parts:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(part["mesh"] as Mesh, 0, part["transform"] as Transform3D)
		st.generate_normals()
		st.set_material(_marker_material(part["color"] as Color))
		st.commit(mesh)
		colors.append(part["color"])
	var marker := MeshInstance3D.new()
	marker.name = "Marker"
	marker.mesh = mesh
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for surface in range(mesh.get_surface_count()):
		var material := _marker_material(colors[surface] as Color)
		marker.set_surface_override_material(surface, material)
	marker.set_meta("kinema_marker_colors", colors)
	node.add_child(marker)
	return marker

func _marker_part(mesh: Mesh, transform: Transform3D, color: Color) -> Dictionary:
	return {"mesh": mesh, "transform": transform, "color": color}

func _marker_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.albedo_color = color
	material.roughness = 0.52
	material.metallic = 0.06
	material.metallic_specular = 0.45
	material.rim_enabled = false
	return material

func _make_camera_marker() -> Array:
	# Local -Z is the view direction. The body block sits behind the lens
	# barrel and the brighter ring closes the barrel, so the silhouette reads
	# as a camera from any orbit angle instead of a generic cube.
	var body := Color(0.48, 0.50, 0.53)
	var body_dark := Color(0.34, 0.36, 0.39)
	var lens := Color(0.66, 0.68, 0.71)
	var glass := Color(0.12, 0.14, 0.17)
	var block := BoxMesh.new()
	block.size = Vector3(0.52, 0.38, 0.40)
	var hump := BoxMesh.new()
	hump.size = Vector3(0.24, 0.11, 0.20)
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.15
	barrel.bottom_radius = 0.17
	barrel.height = 0.26
	barrel.radial_segments = 28
	var ring := TorusMesh.new()
	ring.inner_radius = 0.145
	ring.outer_radius = 0.21
	ring.rings = 32
	ring.ring_segments = 12
	var glass_mesh := CylinderMesh.new()
	glass_mesh.top_radius = 0.12
	glass_mesh.bottom_radius = 0.12
	glass_mesh.height = 0.02
	glass_mesh.radial_segments = 24
	var along_z := Basis(Vector3.RIGHT, PI * 0.5)
	return [
		_marker_part(block, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.16)), body),
		_marker_part(hump, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.24, 0.13)), body_dark),
		_marker_part(barrel, Transform3D(along_z, Vector3(0.0, 0.0, -0.06)), body_dark),
		_marker_part(ring, Transform3D(along_z, Vector3(0.0, 0.0, -0.215)), lens),
		_marker_part(glass_mesh, Transform3D(along_z, Vector3(0.0, 0.0, -0.225)), glass),
	]

func _make_light_marker(omni: bool) -> Array:
	var housing := Color(0.46, 0.48, 0.51)
	var nose := Color(0.34, 0.36, 0.39)
	var bulb := Color(0.74, 0.74, 0.70)
	if omni:
		var globe := SphereMesh.new()
		globe.radius = 0.20
		globe.height = 0.42
		globe.radial_segments = 28
		globe.rings = 14
		var neck := CylinderMesh.new()
		neck.top_radius = 0.09
		neck.bottom_radius = 0.10
		neck.height = 0.15
		neck.radial_segments = 20
		var base := CylinderMesh.new()
		base.top_radius = 0.13
		base.bottom_radius = 0.14
		base.height = 0.06
		base.radial_segments = 20
		return [
			_marker_part(globe, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 0.0)), bulb),
			_marker_part(neck, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.20, 0.0)), housing),
			_marker_part(base, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.30, 0.0)), nose),
		]
	var box := BoxMesh.new()
	box.size = Vector3(0.36, 0.24, 0.34)
	var collar := CylinderMesh.new()
	collar.top_radius = 0.17
	collar.bottom_radius = 0.19
	collar.height = 0.10
	collar.radial_segments = 24
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.16
	cone.height = 0.30
	cone.radial_segments = 24
	var forward := Basis(Vector3.RIGHT, -PI * 0.5)
	return [
		_marker_part(box, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.06)), housing),
		_marker_part(collar, Transform3D(forward, Vector3(0.0, 0.0, -0.03)), nose),
		_marker_part(cone, Transform3D(forward, Vector3(0.0, 0.0, -0.22)), nose),
	]

func _make_empty_marker() -> Array:
	# A three-axis triad, one surface per axis so the body can brighten with
	# the selection while keeping the X/Y/Z colour reading.
	var x_axis := BoxMesh.new()
	x_axis.size = Vector3(0.36, 0.03, 0.03)
	var y_axis := BoxMesh.new()
	y_axis.size = Vector3(0.03, 0.36, 0.03)
	var z_axis := BoxMesh.new()
	z_axis.size = Vector3(0.03, 0.03, 0.36)
	return [
		_marker_part(x_axis, Transform3D(Basis.IDENTITY, Vector3(0.18, 0.0, 0.0)), Color(0.86, 0.38, 0.36)),
		_marker_part(y_axis, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.18, 0.0)), Color(0.42, 0.84, 0.52)),
		_marker_part(z_axis, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.18)), Color(0.40, 0.64, 0.94)),
	]

func _make_primitive(kind: String) -> Mesh:
	match kind:
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			sphere.radial_segments = 48
			sphere.rings = 24
			return sphere
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.5
			cylinder.bottom_radius = 0.5
			cylinder.height = 1.0
			cylinder.radial_segments = 48
			return cylinder
		"cone":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.5
			cone.height = 1.0
			cone.radial_segments = 48
			return cone
		"torus":
			var torus := TorusMesh.new()
			torus.inner_radius = 0.34
			torus.outer_radius = 0.5
			torus.rings = 48
			torus.ring_segments = 20
			return torus
		"plane":
			var plane := PlaneMesh.new()
			plane.size = Vector2(2.0, 2.0)
			return plane
		_:
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			return box

func _apply_visual_properties(node: Node3D, obj: Dictionary) -> void:
	node.visible = bool(obj.get("visible", true))
	var kind := str(obj.get("kind", "mesh"))
	if kind == "mesh":
		var mi := node.get_node_or_null("Mesh") as MeshInstance3D
		if mi != null and mi.material_override is StandardMaterial3D:
			var mat := mi.material_override as StandardMaterial3D
			mat.albedo_color = _hex_color(str(obj.get("color", "#AAB2BF")))
			mat.roughness = clampf(float(obj.get("roughness", 0.48)), 0.0, 1.0)
			mat.metallic = clampf(float(obj.get("metallic", 0.0)), 0.0, 1.0)
			mat.metallic_specular = 0.5
	elif kind == "light":
		var light := node.get_node_or_null("Light") as Light3D
		if light != null:
			light.light_energy = float(obj.get("light_energy", 1.2))
			light.light_color = _hex_color(str(obj.get("light_color", "#F0F0F0")))
			if light is OmniLight3D:
				(light as OmniLight3D).omni_range = float(obj.get("light_range", 8.0))
			_configure_shadows(light, obj)
	elif kind == "camera":
		var camera := node.get_node_or_null("Camera") as Camera3D
		if camera != null:
			camera.fov = clampf(float(obj.get("camera_fov", 45.0)), 12.0, 100.0)
	if kind == "light":
		_sync_sun_sky_mode()
	if rig_system != null:
		rig_system.on_object_properties(obj, node)

# -------------------------------------------------------------------------
# Objects
# -------------------------------------------------------------------------

func _new_id() -> String:
	var id := str(_next_id)
	_next_id += 1
	return id

func _unique_name(base: String) -> String:
	var candidate := base
	var n := 2
	while _has_name(candidate):
		candidate = "%s %d" % [base, n]
		n += 1
	return candidate

func _has_name(p_name: String) -> bool:
	for obj in objects:
		if str(obj.get("name", "")) == p_name:
			return true
	return false

func _new_object_data(kind: String, p_name: String, at: Vector3) -> Dictionary:
	var id := _new_id()
	var obj := _base_object(id, _unique_name(p_name), kind)
	obj["position"] = at
	return obj

func add_primitive(primitive: String, at: Vector3 = Vector3.ZERO) -> String:
	begin_edit("Add " + primitive.capitalize())
	var obj := _add_primitive_data(_default_name_for(primitive), primitive, at, false)
	end_edit()
	_dirty = true
	dirty_changed.emit(true)
	scene_changed.emit()
	set_selection(str(obj["id"]))
	return str(obj["id"])

func _add_primitive_data(p_name: String, primitive: String, at: Vector3, notify: bool = true) -> Dictionary:
	var obj := _new_object_data("mesh", p_name, at)
	obj["primitive"] = primitive
	obj["scale"] = _default_scale_for(primitive)
	obj["color"] = _default_color_for(primitive)
	objects.append(obj)
	_spawn_object(obj)
	if notify:
		scene_changed.emit()
	return obj

func _default_name_for(primitive: String) -> String:
	match primitive:
		"sphere": return "Sphere"
		"cylinder": return "Cylinder"
		"cone": return "Cone"
		"torus": return "Torus"
		"plane": return "Plane"
		_: return "Cube"

func _default_scale_for(primitive: String) -> Vector3:
	if primitive == "plane":
		return Vector3.ONE
	return Vector3.ONE

func _default_color_for(primitive: String) -> String:
	match primitive:
		"sphere": return "#B0B0B0"
		"torus": return "#C8C8C8"
		"plane": return "#3A3A3A"
		_: return "#A8A8A8"

func add_empty(at: Vector3 = Vector3.ZERO) -> String:
	begin_edit("Add Empty")
	var obj := _new_object_data("empty", "Empty", at)
	objects.append(obj)
	_spawn_object(obj)
	end_edit()
	_dirty = true
	dirty_changed.emit(true)
	scene_changed.emit()
	set_selection(str(obj["id"]))
	return str(obj["id"])

func add_camera(at: Vector3 = Vector3.ZERO) -> String:
	begin_edit("Add Camera")
	var obj := _add_camera_data(_unique_name("Camera"), at, Vector3.ZERO, false)
	end_edit()
	_dirty = true
	dirty_changed.emit(true)
	scene_changed.emit()
	set_selection(str(obj["id"]))
	return str(obj["id"])

func _add_camera_data(p_name: String, at: Vector3, look_at_target: Vector3, notify: bool = true) -> Dictionary:
	var obj := _new_object_data("camera", p_name, at)
	if at.distance_to(look_at_target) > 0.001:
		var direction := (look_at_target - at).normalized()
		obj["rotation"] = Basis.looking_at(direction, Vector3.UP).get_rotation_quaternion()
	objects.append(obj)
	_spawn_object(obj)
	if notify:
		scene_changed.emit()
	return obj

func add_light(kind: String = "directional", at: Vector3 = Vector3(0, 4, 0)) -> String:
	begin_edit("Add Light")
	var light_name := "Omni Light" if kind == "omni" else "Key Light"
	var obj := _new_object_data("light", light_name, at)
	obj["light_type"] = "omni" if kind == "omni" else "directional"
	obj["rotation"] = Quaternion(Vector3.RIGHT, deg_to_rad(-40.0)) * Quaternion(Vector3.UP, deg_to_rad(-30.0))
	obj["light_color"] = "#F0F0F0"
	obj["light_energy"] = 1.0 if kind == "omni" else 1.25
	objects.append(obj)
	_spawn_object(obj)
	end_edit()
	_dirty = true
	dirty_changed.emit(true)
	scene_changed.emit()
	set_selection(str(obj["id"]))
	return str(obj["id"])

func _add_light_data(p_name: String, kind: String, at: Vector3, rotation_euler: Vector3, notify: bool = true) -> Dictionary:
	var obj := _new_object_data("light", p_name, at)
	obj["light_type"] = kind
	obj["rotation"] = Quaternion.from_euler(rotation_euler * (PI / 180.0))
	obj["light_energy"] = 1.1 if kind == "omni" else 1.35
	obj["light_color"] = "#E8E8E8" if kind == "omni" else "#F0F0F0"
	if kind == "omni":
		obj["light_range"] = 10.0
	objects.append(obj)
	_spawn_object(obj)
	if notify:
		scene_changed.emit()
	return obj

func add_imported(model_rel_path: String, p_name: String, at: Vector3 = Vector3.ZERO) -> String:
	begin_edit("Import model")
	var obj := _new_object_data("import", p_name, at)
	obj["model"] = model_rel_path
	objects.append(obj)
	_spawn_object(obj)
	# Import-only signal: load and undo use `object_spawned` and never re-scan
	# the model, so clips cannot be duplicated on every restore.
	var id := str(obj["id"])
	if nodes.has(id):
		imported_scene_ready.emit(id, nodes[id])
	end_edit()
	_dirty = true
	dirty_changed.emit(true)
	scene_changed.emit()
	set_selection(str(obj["id"]))
	return str(obj["id"])

func duplicate_selected() -> void:
	var src := get_object(selected_id)
	if src.is_empty():
		return
	begin_edit("Duplicate")
	var copy := src.duplicate(true)
	copy["id"] = _new_id()
	copy["name"] = _unique_name(str(src.get("name", "Object")) + " Copy")
	copy["position"] = _as_vec3(src.get("position", Vector3.ZERO)) + Vector3(0.35, 0.0, 0.35)
	objects.append(copy)
	_spawn_object(copy)
	end_edit()
	_dirty = true
	dirty_changed.emit(true)
	scene_changed.emit()
	set_selection(str(copy["id"]))

func delete_object(id: String) -> void:
	if not nodes.has(id):
		return
	var obj := get_object(id)
	begin_edit("Delete " + str(obj.get("name", "object")))
	var node: Node3D = nodes[id]
	var prefix := node.name + ":"
	if animation != null:
		for i in range(animation.get_track_count() - 1, -1, -1):
			if str(animation.track_get_path(i)).begins_with(prefix):
				animation.track_remove_track(i)
	objects.erase(obj)
	nodes.erase(id)
	remove_child(node)
	node.queue_free()
	if selected_id == id:
		selected_id = ""
		_ensure_valid_selection()
	if selected_part_object_id == id:
		selected_part_object_id = ""
		selected_part_path = ""
	end_edit()
	_dirty = true
	dirty_changed.emit(true)
	scene_changed.emit()
	selection_changed.emit(selected_id)

func delete_selected() -> void:
	if selected_id != "":
		delete_object(selected_id)

func rename_object(id: String, new_name: String) -> void:
	var obj := get_object(id)
	if obj.is_empty():
		return
	var clean := new_name.strip_edges()
	if clean == "":
		return
	begin_edit("Rename object")
	obj["name"] = clean
	end_edit()
	_dirty = true
	dirty_changed.emit(true)
	object_changed.emit(id)
	scene_changed.emit()

func set_object_visible(id: String, visible: bool) -> void:
	var obj := get_object(id)
	if obj.is_empty():
		return
	begin_edit("Toggle visibility")
	obj["visible"] = visible
	var node: Node3D = nodes.get(id)
	if node != null:
		node.visible = visible
	if str(obj.get("kind", "")) == "light":
		_sync_sun_sky_mode()
	end_edit()
	_dirty = true
	dirty_changed.emit(true)
	object_changed.emit(id)
	scene_changed.emit()

func get_object(id: String) -> Dictionary:
	for obj in objects:
		if str(obj.get("id", "")) == id:
			return obj
	return {}

func get_selected_object() -> Dictionary:
	return get_object(selected_id)

func get_selected_node() -> Node3D:
	return nodes.get(selected_id) as Node3D

func set_selection(id: String) -> void:
	if id != "" and not nodes.has(id):
		return
	if selected_part_object_id != "" and selected_part_object_id != id:
		selected_part_object_id = ""
		selected_part_path = ""
		part_selection_changed.emit("", "")
	if selected_id == id:
		return
	selected_id = id
	selection_changed.emit(selected_id)

func get_object_transform(id: String) -> Dictionary:
	var node: Node3D = nodes.get(id)
	if node == null:
		return {"position": Vector3.ZERO, "rotation": Quaternion.IDENTITY, "scale": Vector3.ONE}
	return {
		"position": node.position,
		"rotation": node.quaternion,
		"scale": node.scale,
	}

func set_object_transform(id: String, position: Vector3, rotation: Quaternion, p_scale: Vector3, key: bool = true) -> void:
	var node: Node3D = nodes.get(id)
	if node == null:
		return
	var next_rotation := rotation.normalized()
	var changed := PackedStringArray()
	if not _vec3_close(node.position, position, 0.00001):
		changed.append("position")
	if node.quaternion.angle_to(next_rotation) > deg_to_rad(0.01):
		changed.append("rotation")
	if not _vec3_close(node.scale, p_scale, 0.00001):
		changed.append("scale")
	var values := {
		"position": position,
		"rotation": next_rotation,
		"scale": p_scale,
	}
	_apply_pose_to_node(id, position, next_rotation, p_scale)
	var wrote_key := false
	if key and not _loading:
		for channel in changed:
			var existing := _key_index_at(id, channel, current_time)
			if existing >= 0:
				# Editing on a key updates that key even when autokey is off.
				_write_key(id, channel, values[channel], "update_only")
				wrote_key = true
			elif autokey:
				_write_key(id, channel, values[channel], "insert_only")
				wrote_key = true
		# A key write re-seeks the AnimationPlayer, which re-samples every
		# track. Restore the intended pose so unkeyed channels are not lost.
		_apply_pose_to_node(id, position, next_rotation, p_scale)
	if not changed.is_empty():
		_dirty = true
		dirty_changed.emit(true)
		transform_changed.emit(id)
		if wrote_key:
			keyframes_changed.emit(id)

func _apply_pose_to_node(id: String, position: Vector3, rotation: Quaternion, p_scale: Vector3) -> void:
	var node: Node3D = nodes.get(id)
	if node == null:
		return
	node.position = position
	node.quaternion = rotation
	node.scale = p_scale
	var obj := get_object(id)
	if not obj.is_empty():
		obj["position"] = node.position
		obj["rotation"] = node.quaternion
		obj["scale"] = node.scale

func _vec3_close(a: Vector3, b: Vector3, epsilon: float) -> bool:
	return absf(a.x - b.x) <= epsilon and absf(a.y - b.y) <= epsilon and absf(a.z - b.z) <= epsilon

func _key_index_at(id: String, channel: String, time: float) -> int:
	return get_key_index_at(id, channel, time, 0.5 / float(maxi(1, fps)))

func _write_key(id: String, channel: String, value: Variant, mode: String) -> int:
	if mode != "update_only" and mode != "insert_only" and mode != "update_or_insert":
		push_error("Unknown key write mode: " + mode)
		return -1
	var existing := _key_index_at(id, channel, current_time)
	if existing >= 0:
		if mode != "insert_only":
			set_key_value(id, channel, existing, value)
		return existing
	if mode == "update_only":
		return -1
	var track := _ensure_track(id, channel)
	if track < 0:
		return -1
	animation.track_set_interpolation_type(track, _interpolation_value())
	return _insert_track_value(track, channel, current_time, value)

func set_transform_uniform(id: String, position: Vector3, rotation: Quaternion, p_scale: Vector3) -> void:
	set_object_transform(id, position, rotation, p_scale, true)

func set_material_color(id: String, color: Color) -> void:
	var obj := get_object(id)
	if obj.is_empty():
		return
	obj["color"] = "#" + color.to_html(false)
	var node: Node3D = nodes.get(id)
	if node != null:
		_apply_visual_properties(node, obj)
	_dirty = true
	dirty_changed.emit(true)
	object_changed.emit(id)

func set_material_property(id: String, property: String, value: float) -> void:
	var obj := get_object(id)
	if obj.is_empty():
		return
	obj[property] = value
	var node: Node3D = nodes.get(id)
	if node != null:
		_apply_visual_properties(node, obj)
	_dirty = true
	dirty_changed.emit(true)
	object_changed.emit(id)

func set_camera_fov(id: String, fov: float) -> void:
	var obj := get_object(id)
	if obj.is_empty():
		return
	obj["camera_fov"] = fov
	var node: Node3D = nodes.get(id)
	if node != null:
		_apply_visual_properties(node, obj)
	_dirty = true
	dirty_changed.emit(true)
	object_changed.emit(id)

func set_light_property(id: String, property: String, value: Variant) -> void:
	var obj := get_object(id)
	if obj.is_empty():
		return
	obj[property] = value
	var node: Node3D = nodes.get(id)
	if node != null:
		_apply_visual_properties(node, obj)
	_dirty = true
	dirty_changed.emit(true)
	object_changed.emit(id)

# -------------------------------------------------------------------------
# Animation and transport
# -------------------------------------------------------------------------

func get_track(id: String, channel: String) -> int:
	var node: Node3D = nodes.get(id)
	if node == null or animation == null:
		return -1
	return animation.find_track(NodePath("%s:%s" % [node.name, channel]), int(TRACK_TYPES.get(channel, Animation.TYPE_VALUE)))

func _ensure_track(id: String, channel: String) -> int:
	var node: Node3D = nodes.get(id)
	if node == null or animation == null:
		return -1
	var path := NodePath("%s:%s" % [node.name, channel])
	var ttype := int(TRACK_TYPES.get(channel, Animation.TYPE_VALUE))
	var index := animation.find_track(path, ttype)
	if index != -1:
		return index
	index = animation.add_track(ttype)
	animation.track_set_path(index, path)
	animation.track_set_interpolation_type(index, _interpolation_value())
	return index

func _interpolation_value() -> int:
	return Animation.INTERPOLATION_CUBIC if interpolation == "cubic" else Animation.INTERPOLATION_LINEAR

func _channel_value(id: String, channel: String) -> Variant:
	var node: Node3D = nodes.get(id)
	if node == null:
		return null
	match channel:
		"position": return node.position
		"rotation": return node.quaternion
		"scale": return node.scale
	return null

func _insert_track_value(track: int, channel: String, time: float, value: Variant) -> int:
	match channel:
		"position":
			return animation.position_track_insert_key(track, time, value as Vector3)
		"rotation":
			return animation.rotation_track_insert_key(track, time, value as Quaternion)
		"scale":
			return animation.scale_track_insert_key(track, time, value as Vector3)
		_:
			return animation.track_insert_key(track, time, value)

func _key_selected_transform() -> void:
	if selected_id == "":
		return
	begin_edit("Insert keys")
	var values := {}
	for channel in CHANNELS:
		var value: Variant = _channel_value(selected_id, channel)
		if value != null:
			values[channel] = value
	for channel in CHANNELS:
		if values.has(channel):
			_write_key(selected_id, channel, values[channel], "update_or_insert")
	if values.size() == 3:
		_apply_pose_to_node(selected_id, values["position"], values["rotation"], values["scale"])
	end_edit()
	_dirty = true
	dirty_changed.emit(true)
	keyframes_changed.emit(selected_id)

func insert_transform_keys() -> void:
	_key_selected_transform()

func insert_channel_key(channel: String) -> void:
	if selected_id == "":
		return
	begin_edit("Insert " + channel + " key")
	var values := {}
	for name in CHANNELS:
		var value: Variant = _channel_value(selected_id, name)
		if value != null:
			values[name] = value
	if values.has(channel):
		_write_key(selected_id, channel, values[channel], "update_or_insert")
	if values.size() == 3:
		_apply_pose_to_node(selected_id, values["position"], values["rotation"], values["scale"])
	end_edit()
	_dirty = true
	dirty_changed.emit(true)
	keyframes_changed.emit(selected_id)

func get_channel_keys(id: String, channel: String) -> Array:
	var track := get_track(id, channel)
	if track < 0:
		return []
	var keys: Array = []
	for ki in range(animation.track_get_key_count(track)):
		keys.append({
			"index": ki,
			"time": animation.track_get_key_time(track, ki),
			"value": animation.track_get_key_value(track, ki),
		})
	return keys

func get_key_transition(id: String, channel: String, key_index: int) -> float:
	## Easing for the segment that starts at this key. 1.0 is a linear time
	## warp, below 1.0 eases out, above 1.0 eases in and 0.0 holds the value.
	var track := get_track(id, channel)
	if track < 0 or key_index < 0 or key_index >= animation.track_get_key_count(track):
		return 1.0
	return animation.track_get_key_transition(track, key_index)

func set_key_transition(id: String, channel: String, key_index: int, value: float) -> void:
	var track := get_track(id, channel)
	if track < 0 or key_index < 0 or key_index >= animation.track_get_key_count(track):
		return
	animation.track_set_key_transition(track, key_index, clampf(value, 0.0, 4.0))
	_dirty = true
	dirty_changed.emit(true)
	keyframes_changed.emit(id)
	if anim_player != null:
		anim_player.seek(current_time, true)

func set_channel_transition(id: String, channel: String, value: float) -> void:
	## Godot stores one transition scalar per key, so a channel-wide easing is
	## the same clamped value written to every key in the track.
	var track := get_track(id, channel)
	if track < 0:
		return
	var clamped := clampf(value, 0.0, 4.0)
	for key_index in range(animation.track_get_key_count(track)):
		animation.track_set_key_transition(track, key_index, clamped)
	_dirty = true
	dirty_changed.emit(true)
	keyframes_changed.emit(id)
	if anim_player != null:
		anim_player.seek(current_time, true)

func sample_channel(id: String, channel: String, time: float) -> Variant:
	## Interpolated value at an arbitrary time, straight from the animation
	## resource. The graph editor plots this so the curve matches playback
	## exactly instead of approximating it in UI code.
	var track := get_track(id, channel)
	if track < 0:
		return null
	var t := clampf(time, 0.0, duration)
	match channel:
		"position":
			return animation.position_track_interpolate(track, t)
		"rotation":
			return animation.rotation_track_interpolate(track, t)
		"scale":
			return animation.scale_track_interpolate(track, t)
	return null

func get_key_index_at(id: String, channel: String, time: float, tolerance: float = 0.04) -> int:
	var track := get_track(id, channel)
	if track < 0:
		return -1
	var best := -1
	var best_dist := tolerance
	for ki in range(animation.track_get_key_count(track)):
		var dist := absf(animation.track_get_key_time(track, ki) - time)
		if dist <= best_dist:
			best_dist = dist
			best = ki
	return best

func delete_key(id: String, channel: String, key_index: int) -> void:
	if key_index < 0:
		return
	begin_edit("Delete key")
	var track := get_track(id, channel)
	if track < 0:
		end_edit()
		return
	animation.track_remove_key(track, key_index)
	if animation.track_get_key_count(track) == 0:
		animation.track_remove_track(track)
	end_edit()
	_dirty = true
	dirty_changed.emit(true)
	keyframes_changed.emit(id)
	scene_changed.emit()
	if anim_player != null:
		anim_player.seek(current_time, true)

func set_key_time(id: String, channel: String, key_index: int, new_time: float) -> int:
	var track := get_track(id, channel)
	if track < 0 or key_index < 0 or key_index >= animation.track_get_key_count(track):
		return -1
	new_time = clampf(snappedf(new_time, 1.0 / float(fps)) if snap else new_time, 0.0, duration)
	var value = animation.track_get_key_value(track, key_index)
	var transition := animation.track_get_key_transition(track, key_index)
	animation.track_remove_key(track, key_index)
	var new_index := _insert_track_value(track, channel, new_time, value)
	if new_index >= 0:
		animation.track_set_key_transition(track, new_index, transition)
	animation.length = duration
	_dirty = true
	dirty_changed.emit(true)
	keyframes_changed.emit(id)
	if anim_player != null:
		anim_player.seek(current_time, true)
	return new_index

func set_key_value(id: String, channel: String, key_index: int, value: Variant) -> void:
	var track := get_track(id, channel)
	if track < 0 or key_index < 0 or key_index >= animation.track_get_key_count(track):
		return
	animation.track_set_key_value(track, key_index, value)
	_dirty = true
	dirty_changed.emit(true)
	keyframes_changed.emit(id)
	if anim_player != null:
		anim_player.seek(current_time, true)

func _remove_keys_outside_duration() -> void:
	if animation == null:
		return
	for ti in range(animation.get_track_count() - 1, -1, -1):
		for ki in range(animation.track_get_key_count(ti) - 1, -1, -1):
			if animation.track_get_key_time(ti, ki) > duration + 0.0001:
				animation.track_remove_key(ti, ki)

func seek(time: float, silent: bool = false) -> void:
	_ensure_player()
	_stop_sequence_playback()
	current_time = clampf(time, 0.0, duration)
	is_playing = false
	if anim_player != null:
		if anim_player.assigned_animation == "":
			anim_player.play(ANIMATION_NAME)
		anim_player.pause()
		anim_player.seek(current_time, true)
	if not silent:
		playback_changed.emit(current_time, false)

func play() -> void:
	_stop_sequence_playback()
	if anim_player == null or duration <= 0.001:
		return
	if current_time >= duration - 0.0001:
		current_time = 0.0
	if anim_player.assigned_animation != ANIMATION_NAME:
		anim_player.play(ANIMATION_NAME)
	else:
		anim_player.play()
	# Keep the current playhead when resuming, then let the player run.
	anim_player.seek(current_time, true)
	is_playing = true
	_last_emitted_time = current_time
	playback_changed.emit(current_time, true)

func pause() -> void:
	_stop_sequence_playback()
	if anim_player != null:
		current_time = anim_player.current_animation_position
		anim_player.pause()
	is_playing = false
	playback_changed.emit(current_time, false)

func toggle_play() -> void:
	if is_playing:
		pause()
	else:
		play()

func stop() -> void:
	seek(0.0)

# -------------------------------------------------------------------------
# Sequence transport (clip lane). Clip time and sequence time are two clocks;
# only one of them may run at a time.
# -------------------------------------------------------------------------

## Stop the sequence clock (and its audio/video) before the clip transport
## takes over. The playhead itself is left where the sequence was.
func _stop_sequence_playback() -> void:
	_sequence_playing = false
	if animation_system != null:
		animation_system.pause_sequence()
	if media_system != null:
		media_system.pause_sequence()

## Keep `doc.animation` and `doc.duration` tied to the active clip when the
## animation system switches clips during a sequence seek.
func _adopt_active_animation() -> void:
	if animation_system == null:
		return
	var active: Animation = animation_system.active_animation()
	if active == null or active == animation:
		return
	animation = active
	duration = maxf(0.04, animation.length)
	current_time = clampf(current_time, 0.0, duration)
	_refresh_animation()

func sequence_duration() -> float:
	if animation_system == null:
		return duration
	return animation_system.sequence_duration()

func sequence_time() -> float:
	if animation_system == null:
		return current_time
	return animation_system.sequence_time()

func seek_sequence(time: float, silent: bool = false) -> void:
	if animation_system == null:
		return
	is_playing = false
	if anim_player != null:
		anim_player.pause()
	animation_system.seek_sequence(time)
	_adopt_active_animation()
	current_time = animation_system.active_local_time()
	if media_system != null:
		media_system.seek_sequence(animation_system.sequence_time(), _sequence_playing)
	if not silent:
		playback_changed.emit(current_time, _sequence_playing)

func play_sequence() -> void:
	if animation_system == null or sequence_duration() <= 0.001:
		return
	is_playing = false
	if anim_player != null:
		anim_player.pause()
	_sequence_playing = true
	animation_system.play_sequence()
	if media_system != null:
		media_system.play_sequence(animation_system.sequence_time())
	current_time = animation_system.active_local_time()
	_last_emitted_time = current_time
	playback_changed.emit(current_time, true)

func pause_sequence() -> void:
	if animation_system == null:
		return
	_sequence_playing = false
	animation_system.pause_sequence()
	if media_system != null:
		media_system.pause_sequence()
	current_time = animation_system.active_local_time()
	playback_changed.emit(current_time, false)

func stop_sequence() -> void:
	if animation_system == null:
		return
	_sequence_playing = false
	animation_system.stop_sequence()
	if media_system != null:
		media_system.stop_sequence()
	_adopt_active_animation()
	current_time = animation_system.active_local_time()
	playback_changed.emit(current_time, false)

func is_sequence_playing() -> bool:
	return _sequence_playing

## The clip lane and sheets must call this document method, never the animation
## system directly, so `doc.animation` can never point at a stale clip.
func set_active_clip(id: String) -> void:
	if animation_system == null:
		return
	animation_system.set_active_clip(id)
	var active: Animation = animation_system.active_animation()
	if active != null:
		animation = active
		duration = maxf(0.04, animation.length)
		current_time = clampf(current_time, 0.0, duration)
	_refresh_animation()
	active_clip_changed.emit(id)

func active_clip_id() -> String:
	if animation_system == null:
		return ""
	return animation_system.active_clip_id()

func set_loop(enabled: bool) -> void:
	loop = enabled
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if enabled else Animation.LOOP_NONE
	_dirty = true
	dirty_changed.emit(true)

func set_fps(value: int) -> void:
	fps = clampi(value, 1, 120)
	_dirty = true
	dirty_changed.emit(true)
	playback_changed.emit(current_time, is_playing)

func set_duration(value: float) -> void:
	duration = clampf(value, 0.25, 3600.0)
	if animation != null:
		animation.length = duration
		_remove_keys_outside_duration()
	current_time = clampf(current_time, 0.0, duration)
	if anim_player != null:
		anim_player.seek(current_time, true)
	_dirty = true
	dirty_changed.emit(true)
	scene_changed.emit()
	playback_changed.emit(current_time, is_playing)

func set_interpolation(mode: String) -> void:
	interpolation = mode if mode in ["linear", "cubic"] else "linear"
	if animation != null:
		for ti in range(animation.get_track_count()):
			animation.track_set_interpolation_type(ti, _interpolation_value())
	_dirty = true
	dirty_changed.emit(true)
	keyframes_changed.emit("")

func frame_to_time(frame: int) -> float:
	return clampf(float(frame) / float(fps), 0.0, duration)

func time_to_frame(time: float) -> int:
	return int(round(time * float(fps)))

func format_timecode(time: float) -> String:
	var total_frames := int(round(time * float(fps)))
	var secs := total_frames / fps
	var frames := total_frames % fps
	return "%02d:%02d:%02d" % [secs / 60, secs % 60, frames]

func nearest_key_time(direction: int) -> float:
	var times: Array = []
	var object_ids: Array = [selected_id] if selected_id != "" else []
	if object_ids.is_empty():
		for obj in objects:
			object_ids.append(str(obj["id"]))
	for id in object_ids:
		for channel in CHANNELS:
			for key in get_channel_keys(str(id), channel):
				var t: float = key["time"]
				if not times.has(t):
					times.append(t)
	times.sort()
	var best := current_time
	if direction > 0:
		best = duration
		for t in times:
			if t > current_time + 0.001:
				best = t
				break
	else:
		best = 0.0
		for i in range(times.size() - 1, -1, -1):
			if times[i] < current_time - 0.001:
				best = times[i]
				break
	return best

func get_animation_time() -> float:
	if anim_player != null and is_playing:
		return anim_player.current_animation_position
	return current_time

# -------------------------------------------------------------------------
# History
# -------------------------------------------------------------------------

func begin_edit(label_text: String) -> void:
	if _loading:
		return
	if _edit_snapshot.is_empty():
		_edit_snapshot = to_data()
		_edit_label = label_text

func end_edit() -> void:
	if _edit_snapshot.is_empty():
		return
	var before := JSON.stringify(_edit_snapshot)
	var after := JSON.stringify(to_data())
	if before != after:
		_undo_stack.append({"label": _edit_label, "data": _edit_snapshot})
		if _undo_stack.size() > 40:
			_undo_stack.pop_front()
		_redo_stack.clear()
		history_changed.emit()
		_dirty = true
		dirty_changed.emit(true)
	_edit_snapshot = {}
	_edit_label = ""

func cancel_edit() -> void:
	if _edit_snapshot.is_empty():
		return
	var snapshot := _edit_snapshot
	_edit_snapshot = {}
	_edit_label = ""
	_apply_snapshot(snapshot)


## True while a begin_edit()/end_edit() transaction is open. The timeline uses
## this to decide whether a two-finger gesture must cancel an edit it started.
func has_open_edit() -> bool:
	return not _edit_snapshot.is_empty()

func can_undo() -> bool:
	return not _undo_stack.is_empty()

func can_redo() -> bool:
	return not _redo_stack.is_empty()

func undo_label() -> String:
	return str(_undo_stack.back().get("label", "Action")) if not _undo_stack.is_empty() else ""

func redo_label() -> String:
	return str(_redo_stack.back().get("label", "Action")) if not _redo_stack.is_empty() else ""

func undo() -> void:
	if _undo_stack.is_empty():
		return
	var current := to_data()
	var entry: Dictionary = _undo_stack.pop_back()
	_redo_stack.append({"label": entry["label"], "data": current})
	_apply_snapshot(entry["data"])
	_dirty = true
	dirty_changed.emit(true)
	history_changed.emit()

func redo() -> void:
	if _redo_stack.is_empty():
		return
	var current := to_data()
	var entry: Dictionary = _redo_stack.pop_back()
	_undo_stack.append({"label": entry["label"], "data": current})
	_apply_snapshot(entry["data"])
	_dirty = true
	dirty_changed.emit(true)
	history_changed.emit()

func _apply_snapshot(data: Dictionary) -> void:
	_loading = true
	_clear_runtime()
	_ensure_player()
	_apply_data(data)
	_loading = false
	scene_changed.emit()
	selection_changed.emit(selected_id)
	seek(current_time, true)
	playback_changed.emit(current_time, false)

func mark_saved() -> void:
	_dirty = false
	dirty_changed.emit(false)

func is_dirty() -> bool:
	return _dirty

func set_title(value: String) -> void:
	var clean := value.strip_edges()
	if clean == "":
		return
	title = clean
	_dirty = true
	dirty_changed.emit(true)

# -------------------------------------------------------------------------
# Animation serialization
# -------------------------------------------------------------------------

func _value_to_json(value: Variant) -> Variant:
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Quaternion:
		return [value.x, value.y, value.z, value.w]
	if value is Color:
		return [value.r, value.g, value.b, value.a]
	return value

func _json_to_vec3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO

func _json_to_quat(value: Variant) -> Quaternion:
	if value is Quaternion:
		return value
	if value is Array and value.size() >= 4:
		var q := Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
		return q.normalized()
	return Quaternion.IDENTITY

func _as_vec3(value: Variant) -> Vector3:
	return value if value is Vector3 else _json_to_vec3(value)

func _as_quat(value: Variant) -> Quaternion:
	return value if value is Quaternion else _json_to_quat(value)

func _hex_color(value: String) -> Color:
	return Color.from_string(value, Color(0.66, 0.66, 0.66))

func _load_animation_tracks(anim_data: Dictionary) -> void:
	animation.length = maxf(0.04, float(anim_data.get("length", duration)))
	animation.loop_mode = Animation.LOOP_LINEAR if bool(anim_data.get("loop", loop)) else Animation.LOOP_NONE
	var raw_tracks: Array = anim_data.get("tracks", [])
	for raw in raw_tracks:
		if not raw is Dictionary:
			continue
		var type := int(raw.get("type", Animation.TYPE_VALUE))
		var track := animation.add_track(type)
		animation.track_set_path(track, NodePath(str(raw.get("path", ""))))
		animation.track_set_interpolation_type(track, int(raw.get("interpolation", _interpolation_value())))
		var keys: Array = raw.get("keys", [])
		for key in keys:
			if not key is Dictionary:
				continue
			var time := float(key.get("t", 0.0))
			var value: Variant = key.get("v", null)
			var key_index := -1
			if type == Animation.TYPE_POSITION_3D:
				key_index = animation.position_track_insert_key(track, time, _json_to_vec3(value))
			elif type == Animation.TYPE_ROTATION_3D:
				key_index = animation.rotation_track_insert_key(track, time, _json_to_quat(value))
			elif type == Animation.TYPE_SCALE_3D:
				key_index = animation.scale_track_insert_key(track, time, _json_to_vec3(value))
			else:
				key_index = animation.track_insert_key(track, time, value)
			if key_index >= 0:
				animation.track_set_key_transition(track, key_index, clampf(float(key.get("e", 1.0)), 0.0, 4.0))

func _refresh_animation() -> void:
	if animation == null or anim_player == null:
		return
	animation.length = duration
	animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	# The player always plays the active clip under ANIMATION_NAME. Re-binding
	# here keeps the fast path valid after the animation system swaps clips.
	var library: AnimationLibrary
	if anim_player.has_animation_library(""):
		library = anim_player.get_animation_library("")
	else:
		library = AnimationLibrary.new()
		anim_player.add_animation_library("", library)
	if library.has_animation(ANIMATION_NAME):
		library.remove_animation(ANIMATION_NAME)
	library.add_animation(ANIMATION_NAME, animation)
	anim_player.play(ANIMATION_NAME)
	anim_player.pause()
	anim_player.seek(current_time, true)

# -------------------------------------------------------------------------
# Bone keys (shared contract with the rig workstream)
# -------------------------------------------------------------------------

func _bone_track_path(rig_object_id: String, bone: String) -> NodePath:
	var node: Node = nodes.get(rig_object_id)
	var node_name := str(node.name) if node != null else "Object_" + rig_object_id
	return NodePath("%s/Skeleton3D:%s" % [node_name, bone])

func _bone_track(rig_object_id: String, bone: String, create: bool) -> int:
	if animation == null:
		return -1
	var path := _bone_track_path(rig_object_id, bone)
	for ti in range(animation.get_track_count()):
		if animation.track_get_type(ti) == Animation.TYPE_ROTATION_3D \
				and animation.track_get_path(ti) == path:
			return ti
	if not create:
		return -1
	var track := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, path)
	animation.track_set_interpolation_type(track, _interpolation_value())
	return track

func insert_bone_key(rig_object_id: String, bone: String, rotation: Quaternion) -> int:
	var track := _bone_track(rig_object_id, bone, true)
	if track < 0:
		return -1
	var q := rotation if rotation.length_squared() > 0.000001 else Quaternion.IDENTITY
	var index := animation.rotation_track_insert_key(track, current_time, q.normalized())
	if index >= 0:
		_dirty = true
		dirty_changed.emit(true)
		keyframes_changed.emit(rig_object_id)
	return index

func get_bone_keys(rig_object_id: String, bone: String) -> Array:
	var result: Array = []
	var track := _bone_track(rig_object_id, bone, false)
	if track < 0:
		return result
	for ki in range(animation.track_get_key_count(track)):
		result.append({
			"time": float(animation.track_get_key_time(track, ki)),
			"value": animation.track_get_key_value(track, ki),
			"index": ki,
		})
	return result

func delete_bone_key(rig_object_id: String, bone: String, index: int) -> void:
	var track := _bone_track(rig_object_id, bone, false)
	if track < 0 or index < 0 or index >= animation.track_get_key_count(track):
		return
	animation.track_remove_key(track, index)
	_dirty = true
	dirty_changed.emit(true)
	keyframes_changed.emit(rig_object_id)

func sample_bone(rig_object_id: String, bone: String, time: float) -> Quaternion:
	var track := _bone_track(rig_object_id, bone, false)
	if track < 0 or animation.track_get_key_count(track) == 0:
		return Quaternion.IDENTITY
	var value: Quaternion = animation.rotation_track_interpolate(track, time)
	return value.normalized()

func insert_pose_keys(rig_object_id: String, pose: Dictionary) -> void:
	for bone in pose.keys():
		var value: Variant = pose[bone]
		var rotation := Quaternion.IDENTITY
		if value is Quaternion:
			rotation = value
		elif value is Array:
			rotation = _json_to_quat(value)
		else:
			continue
		insert_bone_key(rig_object_id, str(bone), rotation)

func set_autokey(enabled: bool) -> void:
	autokey = enabled
	_dirty = true
	dirty_changed.emit(true)

func set_snap(enabled: bool) -> void:
	snap = enabled
	_dirty = true
	dirty_changed.emit(true)

# -------------------------------------------------------------------------
# Render helpers
# -------------------------------------------------------------------------

func update_marker_scales(view: Camera3D) -> void:
	# Camera and light markers are world-space gizmos. Scaling them with the
	# view distance keeps them the same size on screen, and hiding the ones
	# behind the editor camera stops a nearby gizmo from clipping across the
	# whole viewport.
	if view == null:
		return
	var cam_pos := view.global_position
	for id in nodes:
		var node: Node3D = nodes[id]
		if node == null or not is_instance_valid(node):
			continue
		var marker := node.get_node_or_null("Marker") as Node3D
		if marker == null:
			continue
		if markers_hidden:
			marker.visible = false
			continue
		var dist := cam_pos.distance_to(node.global_position)
		# A gizmo is a locator, not a miniature object: keep it large enough to
		# read as a camera or light instead of a speck, and let the selection
		# brighten it so the outliner and the viewport agree.
		marker.scale = Vector3.ONE * clampf(dist * 0.072, 0.05, 3.0)
		_tint_marker(marker, str(id) == selected_id)
		marker.visible = dist > 0.6 and not view.is_position_behind(node.global_position)

## Brighten every body surface together. The marker is normally one
## MeshInstance3D with one surface per body part, so a single material walk
## keeps the block, barrel and ring in step. A future group-of-meshes marker
## still works because the walk visits every MeshInstance3D underneath.
func _tint_marker(marker: Node3D, bright: bool) -> void:
	var colors: Array = marker.get_meta("kinema_marker_colors", [])
	var color_index := 0
	var stack: Array[Node] = [marker]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if not node is MeshInstance3D:
			continue
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			var material := mesh_instance.get_surface_override_material(surface)
			if material == null:
				material = mesh_instance.get_active_material(surface)
			if material is StandardMaterial3D:
				var base := Color(0.5, 0.5, 0.5)
				if color_index < colors.size():
					base = colors[color_index] as Color
				var tint := base.lerp(Color(0.94, 0.94, 0.94), 0.38) if bright else base
				(material as StandardMaterial3D).albedo_color = tint
			color_index += 1

func get_scene_bounds() -> AABB:
	var result := AABB()
	var first := true
	for obj in objects:
		var kind := str(obj.get("kind", ""))
		if kind == "camera" or kind == "light":
			continue
		var box := get_object_aabb(str(obj.get("id", "")))
		if box.size == Vector3.ZERO:
			continue
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result

func get_object_aabb(id: String) -> AABB:
	var node: Node3D = nodes.get(id)
	if node == null:
		return AABB()
	return _node_world_aabb(node)

# -------------------------------------------------------------------------
# Import hierarchy
# -------------------------------------------------------------------------
#
# Imported glTF/GLB objects keep their generated node tree live. The document
# stores only the UI state (visibility overrides and the selected part path);
# the part list itself is derived from the loaded model on every call.

## One entry per listed Node3D descendant of the import's generated model, in
## deterministic tree order. Returns [] for a non-import, a missing object or a
## model that failed to load.
func import_parts(id: String) -> Array:
	var model := _import_model_node(id)
	if model == null:
		return []
	var root: Node3D = nodes.get(id) as Node3D
	if root == null:
		return []
	var obj := get_object(id)
	if not _exposes_import_parts(str(obj.get("model", ""))):
		# Spec §8 keeps Wavefront OBJ a single mesh row. Its runtime parser
		# still builds a wrapper tree, so the format gate lives here rather
		# than in every caller.
		return []
	var parts: Array = []
	var index := {}
	_collect_import_parts(model, "Model", 1, "", root, parts, index)
	return parts


## Only glTF/GLB imports carry a meaningful scene hierarchy. OBJ is imported as
## one flat mesh by design.
func _exposes_import_parts(model_rel_path: String) -> bool:
	var extension := model_rel_path.get_extension().to_lower()
	return extension == "gltf" or extension == "glb"


func get_import_part_node(id: String, part_path: String) -> Node3D:
	if part_path == "":
		return null
	var node: Node3D = _resolve_import_part_node(id, part_path)
	if node == null:
		return null
	# Only listed parts are selectable: the Model wrapper and arbitrary children
	# of the model are not part rows.
	for part in import_parts(id):
		if str(part.get("path", "")) == part_path:
			return node
	return null


func set_import_part_visible(id: String, part_path: String, visible: bool) -> void:
	var node := get_import_part_node(id, part_path)
	if node == null:
		return
	var obj := get_object(id)
	if obj.is_empty():
		return
	begin_edit("Toggle part visibility")
	node.visible = visible
	var overrides: Dictionary = obj.get("part_visibility", {})
	var copy := overrides.duplicate()
	copy[part_path] = visible
	obj["part_visibility"] = copy
	end_edit()
	object_changed.emit(id)
	scene_changed.emit()


func get_import_part_aabb(id: String, part_path: String) -> AABB:
	var node := get_import_part_node(id, part_path)
	if node == null:
		return AABB()
	# AABB() is reserved for invalid input. Hidden parts still answer their
	# world bounds here; the stage applies the visibility gate through
	# get_selected_part_aabb().
	return _node_world_aabb(node, true)


func set_selected_part(id: String, part_path: String) -> void:
	if get_import_part_node(id, part_path) == null:
		return
	# Store the part first: set_selection() clears a part that belongs to a
	# different root, but never the part of the root we are selecting.
	selected_part_object_id = id
	selected_part_path = part_path
	set_selection(id)
	part_selection_changed.emit(id, part_path)


func clear_selected_part() -> void:
	if selected_part_object_id == "" and selected_part_path == "":
		return
	selected_part_object_id = ""
	selected_part_path = ""
	part_selection_changed.emit("", "")


func get_selected_part_aabb() -> AABB:
	if selected_part_object_id == "" or selected_part_path == "":
		return AABB()
	# One derived list per query: resolve validity and effective visibility
	# from the same snapshot instead of calling import_parts() twice.
	var entry: Dictionary = {}
	for part in import_parts(selected_part_object_id):
		if str(part.get("path", "")) == selected_part_path:
			entry = part
			break
	if entry.is_empty() or not bool(entry.get("effective_visible", false)):
		return AABB()
	var node := _resolve_import_part_node(selected_part_object_id, selected_part_path)
	if node == null:
		return AABB()
	return _node_world_aabb(node)


func _import_model_node(id: String) -> Node3D:
	var obj := get_object(id)
	if obj.is_empty() or str(obj.get("kind", "")) != "import":
		return null
	var root: Node3D = nodes.get(id) as Node3D
	if root == null:
		return null
	return root.get_node_or_null("Model") as Node3D


func _resolve_import_part_node(id: String, part_path: String) -> Node3D:
	var root: Node3D = nodes.get(id) as Node3D
	if root == null or not part_path.begins_with("Model/"):
		return null
	return root.get_node_or_null(NodePath(part_path)) as Node3D


func _collect_import_parts(container: Node3D, prefix: String, depth: int,
		listed_parent: String, root: Node3D, out: Array, index: Dictionary) -> void:
	for child in container.get_children():
		if not (child is Node3D):
			continue
		var part := child as Node3D
		var path := prefix + "/" + str(part.name)
		# The parent entry is appended before its children recurse, so the
		# whole subtree relation is derived in one pass without a nested scan.
		if listed_parent != "" and index.has(listed_parent):
			out[int(index[listed_parent])]["has_children"] = true
		index[path] = out.size()
		out.append({
			"path": path,
			"name": str(part.name),
			"kind": _import_part_kind(part),
			"depth": depth,
			"parent": listed_parent,
			"has_children": false,
			"visible": part.visible,
			"effective_visible": _visible_through(part, root),
		})
		_collect_import_parts(part, path, depth + 1, path, root, out, index)


func _import_part_kind(node: Node3D) -> String:
	if node is Skeleton3D:
		return "skeleton"
	if node is Light3D:
		return "light"
	if node is Camera3D:
		return "camera"
	if node is MeshInstance3D:
		return "mesh"
	return "empty"


func _visible_through(node: Node3D, root: Node3D) -> bool:
	var current: Node = node
	while current != null:
		if current is Node3D and not (current as Node3D).visible:
			return false
		if current == root:
			break
		current = current.get_parent()
	return true


func _apply_import_part_visibility(node: Node3D, obj: Dictionary) -> void:
	var overrides: Variant = obj.get("part_visibility", {})
	if not (overrides is Dictionary):
		return
	var id := str(obj.get("id", ""))
	for path in overrides.keys():
		var part := _resolve_import_part_node(id, str(path))
		if part == null:
			# The runtime node may not be registered in `nodes` yet during
			# spawn; resolve directly from the fresh import object then.
			part = node.get_node_or_null(NodePath(str(path))) as Node3D
		if part != null:
			part.visible = bool(overrides[path])


func _node_world_aabb(root: Node3D, include_hidden: bool = false) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Light3D:
			# Light nodes carry a large editor gizmo AABB that is not visible
			# geometry. Only their small marker mesh below should affect
			# framing, picking and selection outlines.
			continue
		if node is VisualInstance3D:
			var vi := node as VisualInstance3D
			# Hidden marker meshes must not contribute bounds. A camera marker
			# a metre from the editor camera would otherwise project across the
			# whole viewport and swallow taps meant for nearby lights.
			if (not include_hidden and not vi.visible) or vi.name == "Marker":
				continue
			var local := vi.get_aabb()
			var xf := vi.global_transform
			var world := xf * local
			if first:
				result = world
				first = false
			else:
				result = result.merge(world)
	return result
