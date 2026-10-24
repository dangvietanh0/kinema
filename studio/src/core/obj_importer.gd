extends RefCounted
## Runtime Wavefront OBJ loader.
##
## Godot only ships an OBJ importer inside the editor, so a shipped app cannot
## import OBJ through ResourceLoader. This parser builds a real ArrayMesh at
## runtime: positions, UVs, normals, material groups, MTL base colours and
## diffuse textures. Unsupported MTL features fall back to a plain PBR material
## instead of failing the import.

class Surface:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

var _positions: Array[Vector3] = []
var _uvs: Array[Vector2] = []
var _normals: Array[Vector3] = []
var _surfaces: Dictionary = {}
var _materials: Dictionary = {}
var _current_material := ""
var _base_dir := ""

func build(path: String) -> Node3D:
	return _parse(path)

func _parse(path: String) -> Node3D:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	_base_dir = path.get_base_dir()
	var text := file.get_as_text()
	file.close()
	if text.is_empty():
		return null

	var lines := text.split("\n")
	for raw_line in lines:
		# OBJ whitespace is not guaranteed to be spaces; exporters also emit
		# tabs between tokens.
		var line := raw_line.replace("\t", " ").strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts := line.split(" ", false)
		if parts.is_empty():
			continue
		match parts[0]:
			"v":
				if parts.size() >= 4:
					_positions.append(Vector3(_f(parts[1]), _f(parts[2]), _f(parts[3])))
			"vt":
				if parts.size() >= 3:
					_uvs.append(Vector2(_f(parts[1]), 1.0 - _f(parts[2])))
			"vn":
				if parts.size() >= 4:
					_normals.append(Vector3(_f(parts[1]), _f(parts[2]), _f(parts[3])))
			"usemtl":
				_current_material = line.substr(7).strip_edges() if line.length() > 7 else ""
			"mtllib":
				_load_mtl_line(line.substr(6).strip_edges())
			"f":
				_add_face(parts)

	if _positions.is_empty():
		return null

	var mesh := ArrayMesh.new()
	var materials := {}
	for key in _surfaces.keys():
		var surface: Surface = _surfaces[key]
		if surface.indices.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface.positions
		if surface.normals.size() == surface.positions.size():
			arrays[Mesh.ARRAY_NORMAL] = surface.normals
		if surface.uvs.size() == surface.positions.size():
			arrays[Mesh.ARRAY_TEX_UV] = surface.uvs
		arrays[Mesh.ARRAY_INDEX] = surface.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var index := mesh.get_surface_count() - 1
		var material := _material_for(str(key))
		materials[index] = material
	for index in materials.keys():
		mesh.surface_set_material(int(index), materials[index])

	if mesh.get_surface_count() == 0:
		return null
	var instance := MeshInstance3D.new()
	instance.name = "Model"
	instance.mesh = mesh
	var root := Node3D.new()
	root.name = "ImportedModel"
	root.add_child(instance)
	return root

func _add_face(parts: PackedStringArray) -> void:
	if parts.size() < 4:
		return
	var surface := _surface_for(_current_material)
	var verts: Array[Vector3i] = []
	for i in range(1, parts.size()):
		var token := parts[i]
		var bits := token.split("/", true)
		var vi := _index(bits[0], _positions.size())
		if vi < 0:
			return
		var uv := _index(bits[1], _uvs.size()) if bits.size() > 1 else -1
		var normal := _index(bits[2], _normals.size()) if bits.size() > 2 else -1
		verts.append(Vector3i(vi, uv, normal))
	if verts.size() < 3:
		return
	# Fan triangulation, reversed to Godot's clockwise front-face winding.
	for i in range(1, verts.size() - 1):
		_emit(surface, [verts[0], verts[i + 1], verts[i]])

func _emit(surface: Surface, face: Array) -> void:
	var face_normal := Vector3.ZERO
	if face.size() == 3:
		# The face was reversed for Godot's front-face winding, so compute the
		# normal from the original order to keep it pointing outward.
		var a := _positions[(face[0] as Vector3i).x]
		var b := _positions[(face[2] as Vector3i).x]
		var c := _positions[(face[1] as Vector3i).x]
		face_normal = (b - a).cross(c - a).normalized()
	for entry in face:
		var vertex: Vector3i = entry
		surface.indices.append(surface.positions.size())
		surface.positions.append(_positions[vertex.x])
		if vertex.z >= 0 and vertex.z < _normals.size():
			surface.normals.append(_normals[vertex.z])
		else:
			surface.normals.append(face_normal)
		if vertex.y >= 0 and vertex.y < _uvs.size():
			surface.uvs.append(_uvs[vertex.y])
		else:
			surface.uvs.append(Vector2.ZERO)

func _index(token: String, count: int) -> int:
	if token == "":
		return -1
	var value := int(token)
	if value == 0:
		return -1
	var index := value - 1 if value > 0 else count + value
	# A malformed face must not index outside the vertex arrays.
	if index < 0 or index >= count:
		return -1
	return index

func _surface_for(material: String) -> Surface:
	if not _surfaces.has(material):
		_surfaces[material] = Surface.new()
	return _surfaces[material]

func _f(token: String) -> float:
	return float(token)

# -------------------------------------------------------------------------
# Materials
# -------------------------------------------------------------------------

func _load_mtl_line(relative: String) -> void:
	# A single mtllib line can name several files. A name containing spaces is
	# ambiguous, so try the whole line first and fall back to individual tokens.
	if _load_mtl(relative):
		return
	for token in relative.split(" ", false):
		_load_mtl(token)

func _load_mtl(relative: String) -> bool:
	var cleaned := relative.strip_edges().trim_prefix("\"").trim_suffix("\"")
	var mtl_path := _resolve(cleaned)
	if mtl_path == "":
		return false
	var file := FileAccess.open(mtl_path, FileAccess.READ)
	if file == null:
		return false
	var current := ""
	var pending := {}
	for raw_line in file.get_as_text().split("\n"):
		var line := raw_line.replace("\t", " ").strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts := line.split(" ", false)
		if parts.is_empty():
			continue
		match parts[0]:
			"newmtl":
				if current != "":
					_materials[current] = pending
				current = line.substr(6).strip_edges()
				pending = {"albedo": Color(0.72, 0.73, 0.76), "roughness": 0.55, "alpha": 1.0}
			"Kd":
				if parts.size() >= 4:
					pending["albedo"] = Color(_f(parts[1]), _f(parts[2]), _f(parts[3]))
			"Ks":
				if parts.size() >= 4:
					var spec := (_f(parts[1]) + _f(parts[2]) + _f(parts[3])) / 3.0
					pending["specular"] = clampf(spec, 0.0, 1.0)
			"Ns":
				if parts.size() >= 2:
					# Blinn-Phong exponent -> perceptual roughness.
					var exponent := clampf(_f(parts[1]), 0.0, 1000.0)
					pending["roughness"] = clampf(1.0 - sqrt(exponent / 1000.0), 0.04, 1.0)
			"d":
				if parts.size() >= 2:
					pending["alpha"] = clampf(_f(parts[1]), 0.0, 1.0)
			"Tr":
				if parts.size() >= 2:
					pending["alpha"] = clampf(1.0 - _f(parts[1]), 0.0, 1.0)
			"map_Kd":
				var map_path := line.substr(6).strip_edges()
				pending["texture"] = _resolve_texture(map_path, mtl_path.get_base_dir())
	if current != "":
		_materials[current] = pending
	file.close()
	return true

func _resolve_texture(value: String, base_dir: String) -> String:
	var cleaned := value.strip_edges().trim_prefix("\"").trim_suffix("\"").replace("\\", "/")
	var direct := _resolve(cleaned, base_dir)
	if direct != "":
		return direct
	# Strip MTL map options such as `-s 1 1 1` and retry the remaining suffix,
	# so file names containing spaces still resolve.
	var tokens := cleaned.split(" ", false)
	for i in range(1, tokens.size()):
		var candidate := _resolve(" ".join(tokens.slice(i)), base_dir)
		if candidate != "":
			return candidate
	return ""

func _material_for(name: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var data: Dictionary = _materials.get(name, {})
	material.albedo_color = data.get("albedo", Color(0.72, 0.73, 0.76))
	material.roughness = float(data.get("roughness", 0.55))
	material.metallic = 0.0
	material.metallic_specular = float(data.get("specular", 0.4))
	var alpha := float(data.get("alpha", 1.0))
	if alpha < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = alpha
	var texture_path := str(data.get("texture", ""))
	if texture_path != "" and FileAccess.file_exists(texture_path):
		var image := Image.load_from_file(texture_path)
		if image != null and not image.is_empty():
			material.albedo_texture = ImageTexture.create_from_image(image)
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material

func _resolve(relative: String, base_dir: String = "") -> String:
	if relative == "":
		return ""
	var root := base_dir if base_dir != "" else _base_dir
	var cleaned := relative.replace("\\", "/").strip_edges()
	while cleaned.begins_with("./"):
		cleaned = cleaned.substr(2)
	if cleaned.is_absolute_path() and FileAccess.file_exists(cleaned):
		return cleaned
	var candidate := root.path_join(cleaned)
	candidate = candidate.simplify_path()
	if FileAccess.file_exists(candidate):
		return candidate
	candidate = root.path_join(cleaned.get_file()).simplify_path()
	if FileAccess.file_exists(candidate):
		return candidate
	return ""
