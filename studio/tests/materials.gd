extends Node
## Materials workstream suite: records, construction, assignment, textures,
## imported adoption and the material UI.
##
## The suite exercises the real MaterialSystem against a document and real
## image files written under `user://`. No GPU path is claimed; the headless
## checks read the constructed resource properties directly.

const DocumentScript = preload("res://src/core/document.gd")
const MaterialSystemScript = preload("res://src/core/material_system.gd")
const ProjectStoreScript = preload("res://src/core/project_store.gd")

const RECORD_KEYS := [
	"id", "name", "shading", "albedo_color", "albedo_texture", "normal_texture",
	"normal_scale", "orm_texture", "roughness_texture", "roughness_texture_channel",
	"metallic_texture", "metallic_texture_channel", "ao_texture", "ao_texture_channel",
	"emission_color", "emission_energy", "emission_texture", "roughness", "metallic",
	"metallic_specular", "rim", "rim_tint", "uv1_scale", "uv1_offset", "texture_filter",
	"texture_repeat",
]

var _failures: Array[String] = []
var _checks := 0
var _tmp_dir := ""
var _project_dir := ""


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("MATERIALS OK: " + message)
	else:
		_failures.append(message)
		printerr("MATERIALS FAIL: " + message)


func _approx(a: float, b: float, epsilon: float = 0.0001) -> bool:
	return absf(a - b) <= epsilon


func _ready() -> void:
	_tmp_dir = ProjectSettings.globalize_path("user://materials_tests")
	_rmrf(_tmp_dir)
	DirAccess.make_dir_recursive_absolute(_tmp_dir)
	_project_dir = _tmp_dir.path_join("project")
	_rmrf(_project_dir)
	DirAccess.make_dir_recursive_absolute(_project_dir)
	await get_tree().process_frame
	await _test_records()
	await _test_persistence()
	await _test_document_contract()
	_finish()


func _finish() -> void:
	var status := "PASS" if _failures.is_empty() else "FAIL"
	print("MATERIALS RESULT: %s (%d OK, %d FAIL)" % [status, _checks, _failures.size()])
	if not _failures.is_empty():
		for failure in _failures:
			printerr("  - " + failure)
	print("SUITE RESULT: " + status)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _rmrf(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child := path.path_join(entry)
			if dir.current_is_dir():
				_rmrf(child)
			else:
				DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _new_document():
	var doc = DocumentScript.new()
	add_child(doc)
	doc.new_project("Materials", "blank")
	doc.project_dir = _project_dir
	return doc


# -------------------------------------------------------------------------
# Task 14: records, presets and persistence
# -------------------------------------------------------------------------

func _test_records() -> void:
	var doc = _new_document()
	var ms = doc.material_system
	var emitted := [0]
	ms.materials_changed.connect(func() -> void: emitted[0] += 1)

	var id: String = ms.create_material("Steel", "metal")
	_check(id == "mat_1", "create_material returns mat_1")
	_check(emitted[0] == 1, "create_material emits materials_changed")
	_check(ms.material_ids() == PackedStringArray(["mat_1"]), "material_ids lists creation order")
	var record: Dictionary = ms.get_material(id)
	for key in RECORD_KEYS:
		_check(record.has(key), "record carries %s" % key)
	_check(record.get("name", "") == "Steel", "create_material stores the name")
	_check(str(record.get("shading", "")) == "pbr", "metal preset stays PBR")
	_check(_approx(float(record.get("metallic", 0.0)), 1.0), "metal preset is metallic")
	_check(record.get("notes", null) is Array, "record carries adoption notes")

	var before: Dictionary = ms.get_material(id).duplicate(true)
	_check(ms.update_material(id, {"name": "Brushed", "roughness": 1.5, "metallic": -0.2}),
		"update_material applies a partial patch")
	var updated: Dictionary = ms.get_material(id)
	_check(str(updated.get("name", "")) == "Brushed", "update_material changes only the patched field")
	_check(_approx(float(updated.get("roughness", 0.0)), 1.0), "roughness clamps to 1")
	_check(_approx(float(updated.get("metallic", 0.0)), 0.0), "metallic clamps to 0")
	_check(str(updated.get("shading", "")) == str(before.get("shading", "")), "unpatched fields stay")

	var snapshot := JSON.stringify(ms.get_material(id))
	_check(not ms.update_material(id, {"shading": "glitter"}), "unknown shading is rejected")
	_check(ms.last_error != "", "unknown shading sets last_error")
	_check(JSON.stringify(ms.get_material(id)) == snapshot, "unknown shading mutates nothing")
	_check(not ms.update_material("mat_404", {"name": "Ghost"}), "unknown id is rejected")
	_check(ms.last_error != "", "unknown id sets last_error")

	for bad_path in ["/etc/tex.png", "C:/tex.png", "textures/../../tex.png", "../tex.png"]:
		var escaped_snapshot := JSON.stringify(ms.get_material(id))
		_check(not ms.update_material(id, {"albedo_texture": bad_path}),
			"texture path is refused: %s" % bad_path)
		_check(ms.last_error == "Texture paths must stay inside the project.",
			"texture refusal carries the exact message for %s" % bad_path)
		_check(JSON.stringify(ms.get_material(id)) == escaped_snapshot,
			"refused texture path mutates nothing: %s" % bad_path)
	_check(ms.update_material(id, {"albedo_texture": "textures/steel/albedo.png"}),
		"a project-relative texture path is accepted")

	var copy_id: String = ms.duplicate_material(id)
	_check(copy_id == "mat_2", "duplicate_material returns mat_2")
	var copy: Dictionary = ms.get_material(copy_id)
	_check(str(copy.get("name", "")) == "Brushed Copy", "duplicate names the copy")
	_check(str(copy.get("albedo_texture", "")) == "textures/steel/albedo.png", "duplicate copies the record")
	_check(ms.delete_material(copy_id), "delete_material removes the copy")
	_check(not ms.material_ids().has(copy_id), "deleted id leaves the library")

	var presets := ["matte", "satin", "metal", "plastic", "emissive", "toon", "unlit"]
	for preset in presets:
		var preset_id: String = ms.create_material("P " + preset, preset)
		_check(preset_id != "", "preset %s creates a material" % preset)
		var preset_record: Dictionary = ms.get_material(preset_id)
		_check(str(preset_record.get("id", "")) == preset_id, "preset %s keeps its id" % preset)
		if preset == "toon":
			_check(str(preset_record.get("shading", "")) == "toon", "toon preset selects toon shading")
		if preset == "unlit":
			_check(str(preset_record.get("shading", "")) == "unlit", "unlit preset selects unlit shading")
		if preset == "emissive":
			_check(float(preset_record.get("emission_energy", 0.0)) > 0.0, "emissive preset enables emission")

	doc.queue_free()


func _test_persistence() -> void:
	var doc = _new_document()
	var ms = doc.material_system
	var first: String = ms.create_material("Body", "satin")
	var second: String = ms.create_material("Glass", "unlit")
	ms.update_material(first, {
		"albedo_color": "#112233",
		"normal_texture": "textures/body/normal.png",
		"normal_scale": 0.6,
		"uv1_scale": [2.0, 3.0],
		"uv1_offset": [0.25, 0.5],
		"texture_filter": 1,
		"texture_repeat": false,
		"metallic_texture": "textures/body/metal.png",
		"metallic_texture_channel": 1,
		"notes": ["Imported"],
	})
	var data: Dictionary = ms.to_data()
	_check(data.has("materials"), "to_data returns a materials array")
	_check((data["materials"] as Array).size() == 2, "to_data carries every record")

	var loaded_doc = _new_document()
	loaded_doc.material_system.load_data(data)
	_check(loaded_doc.material_system.material_ids() == PackedStringArray([first, second]),
		"load_data keeps ids and order")
	var before := JSON.stringify(ms.get_material(first))
	var after := JSON.stringify(loaded_doc.material_system.get_material(first))
	_check(before == after, "load_data round-trips every field")
	var third: String = loaded_doc.material_system.create_material("Next", "matte")
	_check(third == "mat_3", "the next id derives from the loaded ids")

	doc.queue_free()
	loaded_doc.queue_free()


func _test_document_contract() -> void:
	var doc = _new_document()
	doc.material_system.create_material("Steel", "metal")
	var data: Dictionary = doc.to_data()
	_check(int(data.get("format", 0)) == 3, "documents serialize as format 3")
	_check(data.has("materials"), "format 3 carries a materials array")
	_check((data["materials"] as Array).size() == 1, "format 3 serializes the library")

	var base: Dictionary = doc._base_object("99", "Probe", "mesh")
	for key in ["material_id", "part_materials", "part_surface_materials"]:
		_check(base.has(key), "_base_object carries %s" % key)
	_check(str(base.get("material_id", "x")) == "", "material_id defaults empty")
	_check(base.get("part_materials", null) is Dictionary and (base["part_materials"] as Dictionary).is_empty(),
		"part_materials defaults empty")
	_check(base.get("part_surface_materials", null) is Dictionary
		and (base["part_surface_materials"] as Dictionary).is_empty(),
		"part_surface_materials defaults empty")

	var normalized: Dictionary = doc._normalize_object({
		"id": "7", "name": "Bad", "kind": "mesh",
		"material_id": 42,
		"part_materials": {"Model/Body": 5, "Model/Ok": "mat_1"},
		"part_surface_materials": "nope",
	})
	_check(str(normalized.get("material_id", "x")) == "", "non-string material_id is dropped")
	_check((normalized.get("part_materials", {}) as Dictionary).size() == 1,
		"non-string part ids are dropped")
	_check(not (normalized.get("part_surface_materials", {}) is String),
		"a non-dictionary surface map becomes an empty map")
	var scalar_normalized: Dictionary = doc._normalize_object({
		"id": "8", "name": "Scalar", "kind": "mesh",
		"part_materials": "nope",
	})
	_check((scalar_normalized.get("part_materials", {}) as Dictionary).is_empty(),
		"a non-dictionary part map becomes an empty map")

	# A v2 fixture has no materials: the library stays empty, legacy colours
	# survive and the load writes no files.
	var fixture_dir := _tmp_dir.path_join("v2")
	_rmrf(fixture_dir)
	DirAccess.make_dir_recursive_absolute(fixture_dir)
	var fixture := {
		"format": 2,
		"title": "V2 Materials",
		"fps": 24,
		"duration": 2.0,
		"loop": true,
		"objects": [{
			"id": "1", "name": "Cube", "kind": "mesh", "primitive": "box",
			"position": [0, 0, 0], "rotation": [0, 0, 0, 1], "scale": [1, 1, 1],
			"visible": true, "color": "#123456", "roughness": 0.7, "metallic": 0.25,
		}],
		"animation": {"name": "Take 01", "length": 2.0, "loop": true, "tracks": []},
	}
	var v2_doc = _new_document()
	v2_doc.project_dir = fixture_dir
	var files_before := DirAccess.get_files_at(fixture_dir).size()
	_check(v2_doc.load_project(fixture, fixture_dir), "a v2 project loads")
	_check(v2_doc.material_system.material_ids().is_empty(), "a v2 project creates no materials")
	var cube = v2_doc.get_object("1")
	_check(str(cube.get("color", "")) == "#123456", "v2 legacy colour survives")
	_check(_approx(float(cube.get("roughness", 0.0)), 0.7), "v2 legacy roughness survives")
	_check(DirAccess.get_files_at(fixture_dir).size() == files_before,
		"loading v2 writes no files")

	doc.queue_free()
	v2_doc.queue_free()
