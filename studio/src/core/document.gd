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
signal playback_changed(time: float, is_playing: bool)
signal history_changed
signal dirty_changed(is_dirty: bool)

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
const TRACK_TYPES := {
	"position": Animation.TYPE_POSITION_3D,
	"rotation": Animation.TYPE_ROTATION_3D,
	"scale": Animation.TYPE_SCALE_3D,
}
const ANIMATION_NAME := "Take 01"
const FORMAT_VERSION := 1

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
var objects: Array[Dictionary] = []

var nodes: Dictionary = {}
var anim_player: AnimationPlayer
var animation: Animation
var current_time := 0.0
var is_playing := false
var markers_hidden := false

var _dirty := false
var _edit_snapshot: Dictionary = {}
var _edit_label := ""
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _loading := false
var _next_id := 1
var _last_emitted_time := -1.0

func _ready() -> void:
	_ensure_player()
	set_process(true)

func _process(_delta: float) -> void:
	if _loading or anim_player == null:
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
	_clear_runtime()
	_ensure_player()
	_create_animation()
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
	return {
		"format": FORMAT_VERSION,
		"title": title,
		"fps": fps,
		"duration": duration,
		"loop": loop,
		"interpolation": interpolation,
		"current_time": current_time,
		"selected_id": selected_id,
		"autokey": autokey,
		"snap": snap,
		"objects": json_objects,
		"animation": {
			"name": ANIMATION_NAME,
			"length": duration,
			"loop": loop,
			"tracks": tracks,
		},
	}

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
	_refresh_animation()
	_ensure_valid_selection()
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
	obj["color"] = str(raw.get("color", "#AAB2BF"))
	obj["roughness"] = clampf(float(raw.get("roughness", 0.48)), 0.0, 1.0)
	obj["metallic"] = clampf(float(raw.get("metallic", 0.0)), 0.0, 1.0)
	obj["light_type"] = str(raw.get("light_type", "directional"))
	obj["light_energy"] = float(raw.get("light_energy", 1.2))
	obj["light_color"] = str(raw.get("light_color", "#FFF0DB"))
	obj["light_range"] = float(raw.get("light_range", 8.0))
	obj["camera_fov"] = float(raw.get("camera_fov", 45.0))
	obj["model"] = str(raw.get("model", ""))
	return obj

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
		"color": "#AAB2BF",
		"roughness": 0.48,
		"metallic": 0.0,
		"light_type": "directional",
		"light_energy": 1.2,
		"light_color": "#FFF0DB",
		"light_range": 8.0,
		"camera_fov": 45.0,
		"model": "",
	}

func _build_blank() -> void:
	_add_camera_data("Main Camera", Vector3(4.0, 3.15, 5.2), Vector3(0.0, 0.65, 0.0), false)
	_add_light_data("Key Light", "directional", Vector3(0.0, 5.0, 0.0), Vector3(-38, -28, 0), false)
	var cube := _add_primitive_data("Cube", "box", Vector3(0.0, 0.5, 0.0), false)
	selected_id = str(cube["id"])
	_add_default_keys_for_cube(str(cube["id"]))

func _build_study() -> void:
	_add_camera_data("Main Camera", Vector3(5.2, 3.5, 6.4), Vector3(0.0, 0.8, 0.0), false)
	# Three-point studio lighting: a warm key with real soft shadows, a cool
	# fill to keep the shadow side readable, and a warm rim for separation.
	var key := _add_light_data("Key Light", "directional", Vector3(0.0, 5.0, 0.0), Vector3(-42, -34, 0), false)
	key["light_energy"] = 1.75
	key["light_color"] = "#FFF0D8"
	_spawn_refresh(str(key["id"]))
	var fill := _add_light_data("Fill Light", "omni", Vector3(3.1, 2.1, 2.7), Vector3.ZERO, false)
	fill["light_energy"] = 0.55
	fill["light_color"] = "#C9DCFF"
	fill["light_range"] = 9.0
	_spawn_refresh(str(fill["id"]))
	var rim := _add_light_data("Rim Light", "omni", Vector3(-2.4, 2.7, -2.2), Vector3.ZERO, false)
	rim["light_energy"] = 1.35
	rim["light_color"] = "#FFD8AA"
	_spawn_refresh(str(rim["id"]))
	var sphere := _add_primitive_data("Form", "sphere", Vector3(0.0, 1.0, 0.0), false)
	sphere["color"] = "#C0A27E"
	sphere["roughness"] = 0.34
	_spawn_refresh(str(sphere["id"]))
	var ring := _add_primitive_data("Orbit", "torus", Vector3(0.0, 1.15, 0.0), false)
	ring["color"] = "#8C9AAE"
	ring["rotation"] = Quaternion(Vector3.RIGHT, deg_to_rad(62.0))
	ring["scale"] = Vector3(1.5, 1.5, 1.5)
	_spawn_refresh(str(ring["id"]))
	var base := _add_primitive_data("Base", "cylinder", Vector3(0.0, 0.14, 0.0), false)
	base["color"] = "#3D4654"
	base["scale"] = Vector3(2.05, 0.28, 2.05)
	base["roughness"] = 0.62
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
			pass
		"import":
			_build_import_visual(node, obj)
		_:
			_build_mesh_visual(node, obj)

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
	_add_marker(node, _make_camera_marker(), Color(0.62, 0.72, 0.86))

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
	light.light_color = _hex_color(str(obj.get("light_color", "#FFF0DB")))
	light.light_specular = 0.55
	_configure_shadows(light)
	node.add_child(light)
	_add_marker(node, _make_light_marker(light_type == "omni"), Color(0.92, 0.78, 0.48))

func _configure_shadows(light: Light3D) -> void:
	## Shadow quality is driven by the graphics preferences. Directional lights
	## get cascaded splits, a filtered soft edge and a physical angular size so
	## the PCSS path produces real penumbrae instead of a hard cutout.
	if light == null:
		return
	light.shadow_enabled = true
	light.shadow_bias = 0.022
	light.shadow_normal_bias = 0.9
	light.shadow_blur = 1.05
	if light is DirectionalLight3D:
		var sun := light as DirectionalLight3D
		sun.light_angular_distance = 0.55
		sun.directional_shadow_max_distance = Gfx.shadow_distance
		sun.directional_shadow_blend_splits = true
		sun.directional_shadow_fade_start = 0.82
		sun.directional_shadow_pancake_size = 18.0
		match int(Gfx.shadow_splits):
			1:
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			3, 4:
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			_:
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	elif light is OmniLight3D:
		pass

func apply_graphics() -> void:
	for id in nodes.keys():
		var node: Node3D = nodes[id]
		if node == null:
			continue
		var light := node.get_node_or_null("Light") as Light3D
		if light != null:
			_configure_shadows(light)

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
		material.albedo_color = Color(0.36, 0.13, 0.13)
		board.material_override = material
		node.add_child(board)
		push_warning("Kinema: could not load imported model '%s'." % rel)
		return
	generated.name = "Model"
	node.add_child(generated)

func _add_marker(node: Node3D, mesh: Mesh, color: Color) -> void:
	var marker := MeshInstance3D.new()
	marker.name = "Marker"
	marker.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = false
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(marker)

func _make_camera_marker() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var verts := PackedVector3Array([
		Vector3(-0.34, -0.23, -0.4), Vector3(0.34, -0.23, -0.4), Vector3(0.0, 0.23, -0.4),
		Vector3(-0.34, -0.23, -0.4), Vector3(0.0, 0.23, -0.4), Vector3(0.0, 0.0, 0.35),
		Vector3(0.34, -0.23, -0.4), Vector3(0.0, 0.0, 0.35), Vector3(0.0, 0.23, -0.4),
		Vector3(-0.34, -0.23, -0.4), Vector3(0.0, 0.0, 0.35), Vector3(0.34, -0.23, -0.4),
		Vector3(0.0, 0.0, 0.35), Vector3(0.0, 0.23, -0.4), Vector3(-0.34, -0.23, -0.4),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _make_light_marker(omni: bool) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var r := 0.25
	var segments := 24
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		var b := TAU * float(i + 1) / float(segments)
		mesh.surface_add_vertex(Vector3(cos(a) * r, sin(a) * r, 0))
		mesh.surface_add_vertex(Vector3(cos(b) * r, sin(b) * r, 0))
		mesh.surface_add_vertex(Vector3(cos(a) * r, 0, sin(a) * r))
		mesh.surface_add_vertex(Vector3(cos(b) * r, 0, sin(b) * r))
		mesh.surface_add_vertex(Vector3(0, cos(a) * r, sin(a) * r))
		mesh.surface_add_vertex(Vector3(0, cos(b) * r, sin(b) * r))
	if not omni:
		for i in range(8):
			var a := TAU * float(i) / 8.0
			mesh.surface_add_vertex(Vector3.ZERO)
			mesh.surface_add_vertex(Vector3(cos(a) * r, sin(a) * r, -1.1))
	mesh.surface_end()
	return mesh

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
			light.light_color = _hex_color(str(obj.get("light_color", "#FFF0DB")))
			if light is OmniLight3D:
				(light as OmniLight3D).omni_range = float(obj.get("light_range", 8.0))
	elif kind == "camera":
		var camera := node.get_node_or_null("Camera") as Camera3D
		if camera != null:
			camera.fov = clampf(float(obj.get("camera_fov", 45.0)), 12.0, 100.0)

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
		"sphere": return "#A9A39A"
		"torus": return "#8B95A4"
		"plane": return "#3B4450"
		_: return "#B3A28B"

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
	obj["light_color"] = "#FFE7C4"
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
	obj["light_color"] = "#FFE8CA" if kind == "omni" else "#FFF2DF"
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
	node.position = position
	node.quaternion = rotation.normalized()
	node.scale = p_scale
	var obj := get_object(id)
	if not obj.is_empty():
		obj["position"] = node.position
		obj["rotation"] = node.quaternion
		obj["scale"] = node.scale
	if key and autokey and not _loading:
		_key_selected_transform(false)
	_dirty = true
	dirty_changed.emit(true)
	object_changed.emit(id)

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

func _key_selected_transform(record_history: bool = true) -> void:
	if selected_id == "":
		return
	if record_history:
		begin_edit("Insert keys")
	for channel in CHANNELS:
		var node: Node3D = nodes.get(selected_id)
		if node == null:
			continue
		var track := _ensure_track(selected_id, channel)
		if track < 0:
			continue
		animation.track_set_interpolation_type(track, _interpolation_value())
		_insert_track_value(track, channel, current_time, _channel_value(selected_id, channel))
	if record_history:
		end_edit()
	_dirty = true
	dirty_changed.emit(true)
	object_changed.emit(selected_id)

func insert_transform_keys() -> void:
	_key_selected_transform(true)

func insert_channel_key(channel: String) -> void:
	if selected_id == "":
		return
	begin_edit("Insert " + channel + " key")
	var track := _ensure_track(selected_id, channel)
	if track >= 0:
		_insert_track_value(track, channel, current_time, _channel_value(selected_id, channel))
	end_edit()
	_dirty = true
	dirty_changed.emit(true)
	object_changed.emit(selected_id)

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
	object_changed.emit(id)
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
	object_changed.emit(id)
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
	object_changed.emit(selected_id)

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
	return Color.from_string(value, Color(0.667, 0.698, 0.749))

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
	anim_player.play(ANIMATION_NAME)
	anim_player.pause()
	anim_player.seek(current_time, true)

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
		marker.scale = Vector3.ONE * clampf(dist * 0.045, 0.04, 3.0)
		marker.visible = dist > 0.6 and not view.is_position_behind(node.global_position)

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

func _node_world_aabb(root: Node3D) -> AABB:
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
			var local := vi.get_aabb()
			var xf := vi.global_transform
			var world := xf * local
			if first:
				result = world
				first = false
			else:
				result = result.merge(world)
	return result
