extends RefCounted
## Distance auto-weighting and the binary skin sidecar.
##
## Bind weights never enter the undo JSON. A sidecar stores the per-vertex bone
## indices and weights; the project JSON keeps only metadata. The maths here is
## pure and testable without a GPU.

const MAX_INFLUENCES := 4
const MAX_VERTICES := 50000
const CHUNK_SIZE := 500
const SIDECAR_MAGIC := "KNSK"
const SIDECAR_VERSION := 1

## Squared-distance falloff. The epsilon keeps a vertex exactly on a bone from
## producing an infinite weight; the squared falloff makes the nearest bone
## dominate without a hard cut.
const DISTANCE_EPSILON := 0.001


static func distance_to_segment(point: Vector3, head: Vector3, tail: Vector3) -> float:
	var segment := tail - head
	var length_squared := segment.length_squared()
	if length_squared <= 0.0000001:
		return point.distance_to(head)
	var t := clampf((point - head).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(head + segment * t)


## `segments` is an array of {name, head, tail, influence_scale}. The result is
## flat: `influences` bone indices and weights per vertex, padded with zero
## weights. Every vertex sums to 1.0.
static func compute_weights(vertices: PackedVector3Array, segments: Array, max_influences: int = MAX_INFLUENCES) -> Dictionary:
	var influences := clampi(max_influences, 1, MAX_INFLUENCES)
	var count := vertices.size()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(count * influences)
	weights.resize(count * influences)
	if segments.is_empty():
		return {"bones": bones, "weights": weights, "influences": influences}
	for v in range(count):
		var point := vertices[v]
		var candidates: Array = []
		for b in range(segments.size()):
			var segment: Dictionary = segments[b]
			var head: Vector3 = segment.get("head", Vector3.ZERO)
			var tail: Vector3 = segment.get("tail", head)
			var distance := distance_to_segment(point, head, tail)
			var scale := maxf(0.0, float(segment.get("influence_scale", 1.0)))
			var weight := (1.0 / pow(distance + DISTANCE_EPSILON, 2.0)) * scale
			candidates.append({"index": b, "weight": weight})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["weight"]) > float(b["weight"]))
		var total := 0.0
		var used := mini(influences, candidates.size())
		for k in range(used):
			total += float(candidates[k]["weight"])
		for k in range(influences):
			var base := v * influences + k
			if k < used and total > 0.0:
				bones[base] = int(candidates[k]["index"])
				weights[base] = float(candidates[k]["weight"]) / total
			else:
				bones[base] = 0
				weights[base] = 0.0
	return {"bones": bones, "weights": weights, "influences": influences}


static func transform_vertices(vertices: PackedVector3Array, xform: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(vertices.size())
	for i in range(vertices.size()):
		out[i] = xform * vertices[i]
	return out


static func sidecar_hash(rig_id: String, mesh_id: String, vertex_count: int, bone_names: Array, bones: PackedInt32Array, weights: PackedFloat32Array) -> String:
	# Include a weight digest so a rebind with changed weights writes a new
	# generation and leaves the old sidecar for undo until save-time GC.
	var digest := 17
	for value in bones:
		digest = (digest * 31 + int(value)) & 0x7fffffff
	for value in weights:
		digest = (digest * 31 + int(round(float(value) * 100000.0))) & 0x7fffffff
	var seed := "%s|%s|%d|%s|%d" % [rig_id, mesh_id, vertex_count, str(bone_names), digest]
	return seed.md5_text().substr(0, 6)


## Header: "KNSK", uint16 version, uint16 influences, uint32 vertex_count,
## then all uint16 bone indices followed by all float32 weights.
static func write_sidecar(path: String, bones: PackedInt32Array, weights: PackedFloat32Array, vertex_count: int, influences: int) -> bool:
	var dir := path.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Kinema: could not write skin sidecar '%s'." % path)
		return false
	file.store_buffer(SIDECAR_MAGIC.to_ascii_buffer())
	file.store_16(SIDECAR_VERSION)
	file.store_16(influences)
	file.store_32(vertex_count)
	var bone_bytes := PackedByteArray()
	bone_bytes.resize(bones.size() * 2)
	for i in range(bones.size()):
		bone_bytes.encode_u16(i * 2, clampi(bones[i], 0, 65535))
	file.store_buffer(bone_bytes)
	file.store_buffer(weights.to_byte_array())
	file.close()
	return true


static func read_sidecar(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Skin sidecar is missing."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Skin sidecar could not be opened."}
	if file.get_length() < 12:
		file.close()
		return {"ok": false, "error": "Skin sidecar is truncated."}
	var magic := file.get_buffer(4).get_string_from_ascii()
	var version := file.get_16()
	var influences := file.get_16()
	var count := file.get_32()
	file.close()
	if magic != SIDECAR_MAGIC:
		return {"ok": false, "error": "Skin sidecar has the wrong header."}
	if version != SIDECAR_VERSION:
		return {"ok": false, "error": "Unsupported skin sidecar version %d." % version}
	if influences < 1 or influences > MAX_INFLUENCES:
		return {"ok": false, "error": "Skin sidecar has an invalid influence count."}
	var expected := 12 + count * influences * 6
	if FileAccess.get_file_as_bytes(path).size() < expected:
		return {"ok": false, "error": "Skin sidecar is truncated."}
	var again := FileAccess.open(path, FileAccess.READ)
	again.seek(12)
	var bone_bytes := again.get_buffer(count * influences * 2)
	var weight_bytes := again.get_buffer(count * influences * 4)
	again.close()
	var bones := PackedInt32Array()
	bones.resize(count * influences)
	for i in range(bones.size()):
		bones[i] = bone_bytes.decode_u16(i * 2)
	var weights := weight_bytes.to_float32_array()
	return {
		"ok": true,
		"version": version,
		"influences": influences,
		"vertex_count": count,
		"bones": bones,
		"weights": weights,
	}


## Replace a surface's arrays with skinned ones. The caller supplies the flat
## bone/weight slices for this surface.
static func skinned_surface_arrays(arrays: Array, bones: PackedInt32Array, weights: PackedFloat32Array) -> Array:
	var out := arrays.duplicate(true)
	out[Mesh.ARRAY_BONES] = bones
	out[Mesh.ARRAY_WEIGHTS] = weights
	return out


## Split a flat sidecar into per-surface slices using the recorded counts.
static func split_surfaces(bones: PackedInt32Array, weights: PackedFloat32Array, influences: int, surface_counts: Array) -> Array:
	var result: Array = []
	var cursor := 0
	for raw_count in surface_counts:
		var count := int(raw_count)
		var surface_bones := PackedInt32Array()
		var surface_weights := PackedFloat32Array()
		surface_bones.resize(count * influences)
		surface_weights.resize(count * influences)
		for i in range(count * influences):
			surface_bones[i] = bones[cursor + i] if cursor + i < bones.size() else 0
			surface_weights[i] = weights[cursor + i] if cursor + i < weights.size() else 0.0
		result.append({"bones": surface_bones, "weights": surface_weights})
		cursor += count * influences
	return result
