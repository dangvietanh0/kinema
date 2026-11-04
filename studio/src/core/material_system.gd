extends RefCounted
## Project material library: records, resources, texture cache and assignments.
##
## Document owns one instance. The library is serialized with the document, so
## undo snapshots carry it too. Texture files are never versioned or deleted by
## undo; only the record paths are.

signal materials_changed

const SHADING_MODELS := ["pbr", "unlit", "toon", "rim"]
const PRESETS := ["matte", "satin", "metal", "plastic", "emissive", "toon", "unlit"]
const TEXTURE_KEYS := [
	"albedo_texture", "normal_texture", "orm_texture", "roughness_texture",
	"metallic_texture", "ao_texture", "emission_texture",
]
const PATH_ERROR := "Texture paths must stay inside the project."

var last_error := ""
var _document = null
var _materials: Array[Dictionary] = []
var _next_material_id := 1


func setup(document) -> void:
	_document = document


func reset() -> void:
	last_error = ""
	_materials.clear()
	_next_material_id = 1


# -------------------------------------------------------------------------
# Serialization
# -------------------------------------------------------------------------

func to_data() -> Dictionary:
	var out: Array = []
	for record in _materials:
		out.append(record.duplicate(true))
	return {"materials": out}


func load_data(raw: Dictionary) -> void:
	_materials.clear()
	_next_material_id = 1
	if raw == null:
		return
	var records: Variant = raw.get("materials", [])
	if not (records is Array):
		return
	for raw_record in records:
		if not (raw_record is Dictionary):
			continue
		var record := _record_from_json(raw_record)
		if record.is_empty():
			continue
		_materials.append(record)
		_next_material_id = maxi(_next_material_id, _id_number(str(record.get("id", ""))) + 1)


func _record_from_json(raw: Dictionary) -> Dictionary:
	var record := _default_record(str(raw.get("id", "")), str(raw.get("name", "Material")))
	for key in record.keys():
		if key == "id":
			continue
		if raw.has(key):
			record[key] = _coerce_value(key, raw[key])
	record["id"] = str(raw.get("id", ""))
	record["name"] = str(raw.get("name", "Material"))
	if str(record["id"]) == "":
		record["id"] = _next_id()
	return record


func _id_number(id: String) -> int:
	if not id.begins_with("mat_"):
		return 0
	return int(id.substr(4))


func _next_id() -> String:
	var id := "mat_%d" % _next_material_id
	_next_material_id += 1
	return id


# -------------------------------------------------------------------------
# Records and CRUD
# -------------------------------------------------------------------------

func _default_record(id: String, p_name: String) -> Dictionary:
	return {
		"id": id,
		"name": p_name,
		"shading": "pbr",
		"albedo_color": "#B8BCC2",
		"albedo_texture": "",
		"normal_texture": "",
		"normal_scale": 1.0,
		"orm_texture": "",
		"roughness_texture": "",
		"roughness_texture_channel": 1,
		"metallic_texture": "",
		"metallic_texture_channel": 2,
		"ao_texture": "",
		"ao_texture_channel": 0,
		"emission_color": "#000000",
		"emission_energy": 0.0,
		"emission_texture": "",
		"roughness": 0.42,
		"metallic": 0.0,
		"metallic_specular": 0.5,
		"rim": 1.0,
		"rim_tint": 0.5,
		"uv1_scale": [1.0, 1.0],
		"uv1_offset": [0.0, 0.0],
		"texture_filter": 3,
		"texture_repeat": true,
		"notes": [],
	}


func material_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for record in _materials:
		ids.append(str(record.get("id", "")))
	return ids


func get_material(id: String) -> Dictionary:
	var record := _find(id)
	return record.duplicate(true) if not record.is_empty() else {}


func _find(id: String) -> Dictionary:
	for record in _materials:
		if str(record.get("id", "")) == id:
			return record
	return {}


func has_material(id: String) -> bool:
	return not _find(id).is_empty()


func create_material(p_name := "Material", preset := "matte") -> String:
	last_error = ""
	var clean := p_name.strip_edges()
	if clean == "":
		clean = "Material"
	var id := _next_id()
	var record := _default_record(id, clean)
	_apply_preset(record, preset)
	_materials.append(record)
	materials_changed.emit()
	return id


func _apply_preset(record: Dictionary, preset: String) -> void:
	match preset:
		"satin":
			record["roughness"] = 0.4
			record["metallic_specular"] = 0.55
		"metal":
			record["roughness"] = 0.26
			record["metallic"] = 1.0
			record["metallic_specular"] = 0.6
			record["albedo_color"] = "#C8CCD2"
		"plastic":
			record["roughness"] = 0.3
			record["metallic_specular"] = 0.72
		"emissive":
			record["emission_color"] = "#FFFFFF"
			record["emission_energy"] = 2.0
		"toon":
			record["shading"] = "toon"
			record["roughness"] = 0.5
		"unlit":
			record["shading"] = "unlit"
		_:
			record["roughness"] = 0.72
			record["metallic_specular"] = 0.35


func duplicate_material(id: String) -> String:
	last_error = ""
	var source := _find(id)
	if source.is_empty():
		last_error = "Choose a material first."
		return ""
	var copy: Dictionary = source.duplicate(true)
	copy["id"] = _next_id()
	copy["name"] = str(source.get("name", "Material")) + " Copy"
	_materials.append(copy)
	materials_changed.emit()
	return str(copy["id"])


func delete_material(id: String) -> bool:
	last_error = ""
	var record := _find(id)
	if record.is_empty():
		last_error = "Choose a material first."
		return false
	_materials.erase(record)
	if _document != null and _document.has_method("get_object"):
		for obj in _document.objects:
			var changed := false
			if str(obj.get("material_id", "")) == id:
				obj["material_id"] = ""
				changed = true
			for map_key in ["part_materials", "part_surface_materials"]:
				var assignments: Dictionary = obj.get(map_key, {})
				if not (assignments is Dictionary):
					continue
				for path in assignments.keys():
					if str(assignments[path]) == id:
						assignments.erase(path)
						changed = true
			if changed:
				apply_object(str(obj.get("id", "")))
	materials_changed.emit()
	return true


func update_material(id: String, patch: Dictionary) -> bool:
	last_error = ""
	var record := _find(id)
	if record.is_empty():
		last_error = "Choose a material first."
		return false
	if not (patch is Dictionary):
		last_error = "The material change is invalid."
		return false
	# Validate the whole patch before writing anything.
	for key in patch.keys():
		if key == "shading" and not SHADING_MODELS.has(str(patch[key])):
			last_error = "Choose PBR, Unlit, Toon or Rim."
			return false
		if key in TEXTURE_KEYS:
			var path := str(patch[key])
			if path != "" and not _valid_texture_path(path):
				last_error = PATH_ERROR
				return false
	for key in patch.keys():
		if key == "id":
			continue
		if key == "notes":
			var notes: Variant = patch[key]
			record["notes"] = (notes as Array).duplicate() if notes is Array else []
			continue
		if record.has(key):
			record[key] = _coerce_value(key, patch[key])
	materials_changed.emit()
	return true


func _valid_texture_path(path: String) -> bool:
	if path.is_absolute_path():
		return false
	if path.begins_with("/") or path.begins_with("\\"):
		return false
	if path.contains("\\"):
		return false
	if path.contains("://"):
		return false
	for part in path.split("/", false):
		if part == "..":
			return false
	return true


func _coerce_value(key: String, value: Variant) -> Variant:	match key:
		"name":
			return str(value)
		"shading":
			return str(value) if SHADING_MODELS.has(str(value)) else "pbr"
		"albedo_color", "emission_color":
			return str(value)
		"roughness", "metallic", "metallic_specular", "rim", "rim_tint":
			return clampf(float(value), 0.0, 1.0)
		"normal_scale":
			return maxf(0.0, float(value))
		"emission_energy":
			return clampf(float(value), 0.0, 10.0)
		"roughness_texture_channel", "metallic_texture_channel", "ao_texture_channel":
			return clampi(int(value), 0, 2)
		"texture_filter":
			return clampi(int(value), 0, 5)
		"texture_repeat":
			return bool(value)
		"uv1_scale", "uv1_offset":
			if value is Array and (value as Array).size() >= 2:
				return [float(value[0]), float(value[1])]
			if value is Vector2:
				return [value.x, value.y]
			return [1.0, 1.0] if key == "uv1_scale" else [0.0, 0.0]
		_:
			return value


# -------------------------------------------------------------------------
# Assignment and rendering (filled in by the assignment task)
# -------------------------------------------------------------------------

func apply_object(_object_id: String) -> void:
	# Task 16 owns the real walk; before assignments exist there is nothing to
	# apply and legacy visuals stay untouched.
	pass
