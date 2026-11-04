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
const InspectorScript = preload("res://src/ui/inspector.gd")
const MaterialSheetScript = preload("res://src/ui/material_sheet.gd")
const MaterialEditorSheetScript = preload("res://src/ui/material_editor_sheet.gd")
const KitScript = preload("res://src/ui/kit.gd")

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
	await _test_construction()
	await _test_assignment()
	await _test_texture_import()
	await _test_adoption()
	await _test_material_ui()
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


# -------------------------------------------------------------------------
# Task 15: construction, shading and packed ORM
# -------------------------------------------------------------------------

func _make_texture(rel: String, color: Color = Color(0.8, 0.7, 0.6, 1.0)) -> String:
	var path := _project_dir.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	image.save_png(path)
	return rel


func _test_construction() -> void:
	var doc = _new_document()
	var ms = doc.material_system
	_make_texture("textures/test/albedo.png", Color(0.9, 0.1, 0.2, 1.0))
	_make_texture("textures/test/normal.png", Color(0.5, 0.5, 1.0, 1.0))
	_make_texture("textures/test/emission.png", Color(1.0, 0.8, 0.1, 1.0))
	_make_texture("textures/test/orm.png", Color(0.2, 0.4, 0.6, 1.0))
	_make_texture("textures/test/rough.png", Color(0.3, 0.3, 0.3, 1.0))
	_make_texture("textures/test/metal.png", Color(0.4, 0.4, 0.4, 1.0))
	_make_texture("textures/test/ao.png", Color(0.1, 0.1, 0.1, 1.0))

	var pbr_id: String = ms.create_material("PBR", "satin")
	ms.update_material(pbr_id, {
		"albedo_color": "#336699",
		"albedo_texture": "textures/test/albedo.png",
		"normal_texture": "textures/test/normal.png",
		"normal_scale": 0.65,
		"roughness": 0.33,
		"metallic": 0.44,
		"metallic_specular": 0.66,
		"uv1_scale": [2.5, 3.5],
		"uv1_offset": [0.25, 0.75],
		"texture_filter": 1,
		"texture_repeat": false,
	})
	var pbr: BaseMaterial3D = ms.resource_for(pbr_id)
	_check(pbr is StandardMaterial3D, "a PBR record builds a StandardMaterial3D")
	_check(pbr.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL, "PBR uses per-pixel shading")
	_check(pbr.albedo_color.is_equal_approx(Color.from_string("#336699", Color.WHITE)), "albedo colour maps")
	_check(_approx(pbr.roughness, 0.33), "roughness maps")
	_check(_approx(pbr.metallic, 0.44), "metallic maps")
	_check(_approx(pbr.metallic_specular, 0.66), "metallic specular maps")
	_check(pbr.albedo_texture != null, "albedo texture loads")
	_check(pbr.normal_enabled and pbr.normal_texture != null, "normal texture and flag are set")
	_check(_approx(pbr.normal_scale, 0.65), "normal scale maps")
	_check(pbr.uv1_scale.is_equal_approx(Vector3(2.5, 3.5, 1.0)), "UV scale maps to Vector3(x, y, 1)")
	_check(pbr.uv1_offset.is_equal_approx(Vector3(0.25, 0.75, 0.0)), "UV offset maps to Vector3(x, y, 0)")
	_check(pbr.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR, "texture filter maps")
	_check(pbr.texture_repeat == false, "texture repeat maps")
	_check(ms.resource_for(pbr_id) == pbr, "one resource is reused per material id")

	var unlit_id: String = ms.create_material("Unlit", "unlit")
	_check(ms.resource_for(unlit_id).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
		"Unlit builds unshaded shading")
	var toon_id: String = ms.create_material("Toon", "toon")
	var toon: BaseMaterial3D = ms.resource_for(toon_id)
	_check(toon.diffuse_mode == BaseMaterial3D.DIFFUSE_TOON, "Toon selects toon diffuse")
	_check(toon.specular_mode == BaseMaterial3D.SPECULAR_TOON, "Toon selects toon specular")
	var rim_id: String = ms.create_material("Rim", "matte")
	ms.update_material(rim_id, {"shading": "rim", "rim": 0.8, "rim_tint": 0.3})
	var rim: BaseMaterial3D = ms.resource_for(rim_id)
	_check(rim.rim_enabled, "Rim enables the rim term")
	_check(_approx(rim.rim, 0.8) and _approx(rim.rim_tint, 0.3), "Rim strength and tint map")

	var emissive_id: String = ms.create_material("Glow", "matte")
	var off: BaseMaterial3D = ms.resource_for(emissive_id)
	_check(not off.emission_enabled, "zero emission energy disables emission")
	ms.update_material(emissive_id, {
		"emission_color": "#FF8800",
		"emission_energy": 4.5,
		"emission_texture": "textures/test/emission.png",
	})
	var glow: BaseMaterial3D = ms.resource_for(emissive_id)
	_check(glow.emission_enabled, "positive emission energy enables emission")
	_check(glow.emission.is_equal_approx(Color.from_string("#FF8800", Color.WHITE)), "emission colour maps")
	_check(_approx(glow.emission_energy_multiplier, 4.5), "emission energy maps")
	_check(glow.emission_texture != null, "emission texture maps")

	var ao_id: String = ms.create_material("AO", "matte")
	ms.update_material(ao_id, {"ao_texture": "textures/test/ao.png", "ao_texture_channel": 2})
	var ao: BaseMaterial3D = ms.resource_for(ao_id)
	_check(ao.ao_enabled and ao.ao_texture != null, "AO texture and flag are set")
	_check(ao.ao_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE, "AO channel maps")

	var orm_id: String = ms.create_material("Packed", "matte")
	ms.update_material(orm_id, {
		"orm_texture": "textures/test/orm.png",
		"roughness_texture": "textures/test/rough.png",
		"metallic_texture": "textures/test/metal.png",
		"ao_texture": "textures/test/ao.png",
		"roughness_texture_channel": 1,
		"metallic_texture_channel": 2,
	})
	var orm: BaseMaterial3D = ms.resource_for(orm_id)
	_check(orm is ORMMaterial3D, "a set ORM map builds an ORMMaterial3D")
	_check(orm.orm_texture != null, "the packed ORM map is attached")
	_check(orm.roughness_texture == null and orm.metallic_texture == null,
		"separate roughness and metallic maps are suppressed while ORM is set")
	_check(not orm.ao_enabled, "the separate AO map is suppressed while ORM is set")

	ms.update_material(orm_id, {"orm_texture": ""})
	var separate: BaseMaterial3D = ms.resource_for(orm_id)
	_check(separate is StandardMaterial3D, "clearing ORM rebuilds a StandardMaterial3D")
	_check(separate.roughness_texture != null and separate.metallic_texture != null,
		"clearing ORM re-applies the separate maps")
	_check(separate.ao_enabled and separate.ao_texture != null, "clearing ORM re-enables the AO map")

	var missing_id: String = ms.create_material("Missing", "matte")
	ms.update_material(missing_id, {
		"normal_texture": "textures/test/absent-normal.png",
		"albedo_texture": "textures/test/absent-albedo.png",
	})
	var missing: BaseMaterial3D = ms.resource_for(missing_id)
	_check(missing != null, "a missing texture does not crash construction")
	_check(not missing.normal_enabled and missing.normal_texture == null,
		"a missing normal map stays disabled")
	_check(missing.albedo_texture == null, "a missing albedo map stays empty")
	_check(ms.missing_textures().has("textures/test/absent-normal.png"),
		"missing_textures reports the missing normal map")
	_check(ms.missing_textures().has("textures/test/absent-albedo.png"),
		"missing_textures reports the missing albedo map")

	var cache_before: BaseMaterial3D = ms.resource_for(pbr_id)
	ms.clear_texture_cache()
	var cache_after: BaseMaterial3D = ms.resource_for(pbr_id)
	_check(cache_before != cache_after, "clear_texture_cache rebuilds resources")
	ms.update_material(pbr_id, {"albedo_texture": "textures/test/emission.png"})
	var replaced: BaseMaterial3D = ms.resource_for(pbr_id)
	_check(replaced != cache_after, "a texture replacement rebuilds that material")

	doc.queue_free()


# -------------------------------------------------------------------------
# Task 16: assignment resolution and strict part targeting
# -------------------------------------------------------------------------

func _two_surface_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.0), Vector3(0.0, 0.5, 0.0),
	])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _assignment_doc() -> Dictionary:
	var doc = _new_document()
	var object_id: String = doc.add_primitive("box")
	var root: Node3D = doc.nodes[object_id]
	var multi := MeshInstance3D.new()
	multi.name = "Multi"
	multi.mesh = _two_surface_mesh()
	root.add_child(multi)
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	root.add_child(pivot)
	return {"doc": doc, "id": object_id, "multi": multi, "pivot": pivot}


func _test_assignment() -> void:
	var ctx := _assignment_doc()
	var doc = ctx["doc"]
	var id: String = ctx["id"]
	var multi: MeshInstance3D = ctx["multi"]
	var ms = doc.material_system

	var object_mat: String = ms.create_material("Object", "matte")
	var part_mat: String = ms.create_material("Part", "satin")
	var surface_mat: String = ms.create_material("Surface", "metal")

	_check(ms.can_assign_part(id, ""), "the object root is always a valid target")
	_check(ms.can_assign_part(id, "Multi"), "a real MeshInstance3D part is assignable")
	_check(not ms.can_assign_part(id, "Pivot"), "a non-mesh part is not assignable")
	_check(not ms.can_assign_part(id, "Missing"), "a missing part is not assignable")

	_check(ms.assign_material(id, object_mat), "an object material assigns")
	_check(ms.resolve_assignment(id, "", -1) == object_mat, "the object slot resolves")
	_check(ms.resolve_assignment(id, "Multi", -1) == object_mat, "a part falls back to the object")
	_check(ms.resolve_assignment(id, "Multi", 1) == object_mat, "a surface falls back to the object")

	_check(ms.assign_material(id, part_mat, "Multi"), "a part material assigns")
	_check(ms.resolve_assignment(id, "Multi", -1) == part_mat, "the part slot resolves")
	_check(ms.resolve_assignment(id, "Multi", 0) == part_mat, "a surface falls back to the part")
	_check(ms.resolve_assignment(id, "Mesh", -1) == object_mat, "other parts keep the object material")

	_check(ms.assign_material(id, surface_mat, "Multi", 1), "a surface material assigns")
	_check(ms.resolve_assignment(id, "Multi", 1) == surface_mat, "the surface slot wins")
	_check(ms.resolve_assignment(id, "Multi", 0) == part_mat, "other surfaces keep the part material")
	_check(ms.clear_material(id, "Multi", 1), "clearing a surface slot succeeds")
	_check(ms.resolve_assignment(id, "Multi", 1) == part_mat, "a cleared surface falls back to the part")
	_check(ms.clear_material(id, "Multi"), "clearing a part slot succeeds")
	_check(ms.resolve_assignment(id, "Multi", -1) == object_mat, "a cleared part falls back to the object")
	_check(ms.clear_material(id), "clearing the object slot succeeds")
	_check(ms.resolve_assignment(id, "Multi", 0) == "", "a cleared object falls back to legacy")

	# A non-mesh refusal writes nothing and opens no undo entry.
	ms.assign_material(id, object_mat)
	var before := JSON.stringify(doc.to_data())
	var undo_before: int = doc._undo_stack.size()
	_check(not ms.assign_material(id, part_mat, "Pivot"), "a non-mesh part refuses an assignment")
	_check(ms.last_error == "This part has no mesh to shade.", "the non-mesh refusal is exact")
	_check(JSON.stringify(doc.to_data()) == before, "the non-mesh refusal writes nothing")
	_check(doc._undo_stack.size() == undo_before, "the non-mesh refusal opens no undo entry")
	_check(not ms.clear_material(id, "Pivot"), "a non-mesh part refuses a clear")
	_check(ms.last_error == "This part has no mesh to shade.", "the non-mesh clear refusal is exact")

	# An out-of-range surface is refused with its index.
	_check(not ms.assign_material(id, part_mat, "Multi", 5), "an out-of-range surface is refused")
	_check(ms.last_error == "Surface 5 is out of range.", "the surface refusal is exact")
	_check(not ms.clear_material(id, "Multi", 2), "an out-of-range clear is refused")
	_check(ms.last_error == "Surface 2 is out of range.", "the clear refusal is exact")

	# Rendering: overrides follow the resolved id, and clearing restores legacy.
	ms.assign_material(id, object_mat)
	var object_resource: BaseMaterial3D = ms.resource_for(object_mat)
	_check(multi.get_surface_override_material(0) == object_resource,
		"apply_object sets a surface override from the object material")
	_check(multi.get_surface_override_material(1) == object_resource,
		"apply_object covers every surface")
	var primitive: MeshInstance3D = doc.nodes[id].get_node("Mesh") as MeshInstance3D
	_check(primitive.get_surface_override_material(0) == object_resource,
		"apply_object covers a primitive surface")
	_check(primitive.material_override == null,
		"a library assignment suppresses the legacy material override")

	ms.clear_material(id)
	_check(multi.get_surface_override_material(0) == null,
		"clearing an assignment removes the surface override")
	_check(primitive.get_surface_override_material(0) == null,
		"clearing a primitive assignment clears its surface override")
	_check(primitive.material_override is StandardMaterial3D,
		"clearing restores the legacy primitive material")

	# Deleting a material clears every reference and restores legacy visuals.
	ms.assign_material(id, object_mat)
	ms.assign_material(id, part_mat, "Multi")
	ms.assign_material(id, surface_mat, "Multi", 0)
	doc.begin_edit("Delete material")
	_check(ms.delete_material(part_mat), "deleting a referenced material succeeds")
	doc.end_edit()
	var obj: Dictionary = doc.get_object(id)
	_check(not (obj.get("part_materials", {}) as Dictionary).has("Multi"),
		"delete_material clears a part assignment")
	_check(str((obj.get("part_materials", {}) as Dictionary).get("Multi", "")) == "",
		"the cleared part assignment is gone")
	_check(ms.resolve_assignment(id, "Multi", 0) == surface_mat,
		"a surviving surface assignment keeps priority")
	_check(doc.can_undo(), "the delete is one undoable edit")
	doc.undo()
	var restored: Dictionary = doc.get_object(id)
	_check(str((restored.get("part_materials", {}) as Dictionary).get("Multi", "")) == part_mat,
		"undo restores the deleted material assignment")
	var restored_mesh: MeshInstance3D = doc.nodes[id].get_node("Mesh") as MeshInstance3D
	_check(restored_mesh.get_surface_override_material(0) == ms.resource_for(object_mat),
		"undo restores the rendered object override")

	# Duplicating an object shares material ids.
	doc.duplicate_selected()
	var copies: Array = doc.objects.filter(func(o: Dictionary) -> bool:
		return str(o.get("name", "")).ends_with("Copy"))
	_check(copies.size() == 1, "the duplicating test has one copy")
	if copies.size() == 1:
		_check(str(copies[0].get("material_id", "")) == object_mat,
			"a duplicate shares the object material id")
		_check(str((copies[0].get("part_surface_materials", {}) as Dictionary).get("Multi#0", "")) == surface_mat,
			"a duplicate shares the surface material id")

	doc.queue_free()


# -------------------------------------------------------------------------
# Task 17: texture import and imported material adoption
# -------------------------------------------------------------------------

func _test_texture_import() -> void:
	var sources := _tmp_dir.path_join("sources")
	_rmrf(sources)
	DirAccess.make_dir_recursive_absolute(sources)
	var bad := FileAccess.open(sources.path_join("bad.gif"), FileAccess.WRITE)
	bad.store_buffer(PackedByteArray([1, 2, 3]))
	bad.close()
	var unsupported: Dictionary = Store.import_texture(sources.path_join("bad.gif"), _project_dir, "Bad")
	_check(not bool(unsupported.get("ok", true)), "an unsupported extension is refused")
	_check(str(unsupported.get("error", "")) == "Kinema imports PNG, JPEG and WebP textures.",
		"the unsupported extension error is exact")

	var broken := FileAccess.open(sources.path_join("broken.png"), FileAccess.WRITE)
	broken.store_string("not an image")
	broken.close()
	var unreadable: Dictionary = Store.import_texture(sources.path_join("broken.png"), _project_dir, "Broken")
	_check(not bool(unreadable.get("ok", true)), "an unreadable image is refused")
	_check(str(unreadable.get("error", "")) == "This image could not be read.",
		"the unreadable image error is exact")

	for extension in ["png", "jpg", "webp"]:
		var source := sources.path_join("small." + extension)
		var image := Image.create(16, 12, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.2, 0.6, 0.9, 1.0))
		match extension:
			"png":
				image.save_png(source)
			"jpg":
				image.save_jpg(source)
			"webp":
				image.save_webp(source)
		var original_bytes := FileAccess.get_file_as_bytes(source)
		var result: Dictionary = Store.import_texture(source, _project_dir, "Small " + extension)
		_check(bool(result.get("ok", false)), "%s imports inside the cap" % extension)
		_check(int(result.get("width", 0)) == 16 and int(result.get("height", 0)) == 12,
			"%s reports the real dimensions" % extension)
		_check(str(result.get("resized_from", "x")) == "", "%s is not resized" % extension)
		var rel := str(result.get("rel_path", ""))
		_check(rel.begins_with("textures/") and rel.ends_with("." + extension),
			"%s keeps its original extension" % extension)
		var stored := _project_dir.path_join(rel)
		_check(FileAccess.file_exists(stored), "%s is copied into the project" % extension)
		_check(FileAccess.get_file_as_bytes(stored) == original_bytes,
			"%s copies the original bytes unchanged" % extension)

	var alias_source := sources.path_join("alias.jpeg")
	var alias_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	alias_image.fill(Color(0.8, 0.8, 0.2, 1.0))
	alias_image.save_jpg(alias_source)
	var alias_result: Dictionary = Store.import_texture(alias_source, _project_dir, "Alias")
	_check(bool(alias_result.get("ok", false)), ".jpeg is accepted")

	var huge_source := sources.path_join("huge.jpg")
	var huge := Image.create(4100, 8, false, Image.FORMAT_RGBA8)
	huge.fill(Color(0.4, 0.4, 0.4, 1.0))
	huge.save_jpg(huge_source)
	var resized: Dictionary = Store.import_texture(huge_source, _project_dir, "Huge")
	_check(bool(resized.get("ok", false)), "an oversized image imports")
	_check(int(resized.get("width", 0)) == 4096, "the oversized image is 4096 wide")
	_check(str(resized.get("resized_from", "")) == "4100x8", "resized_from uses WxH with an ASCII x")
	var resized_rel := str(resized.get("rel_path", ""))
	_check(resized_rel.ends_with(".png"), "an oversized JPEG is stored as PNG")
	var resized_folder := _project_dir.path_join(resized_rel).get_base_dir()
	var resized_files := DirAccess.get_files_at(resized_folder)
	_check(resized_files.size() == 1, "an oversized image stores only the downscaled file")
	if resized_files.size() == 1:
		_check(str(resized_files[0]) == resized_rel.get_file(), "the downscaled file uses the slug name")
	_check(not FileAccess.file_exists(resized_folder.path_join("huge.jpg")),
		"an oversized image keeps no original copy")

	var import_files := _find_extension(_project_dir.path_join("textures"), "import")
	_check(import_files.is_empty(), "texture import creates no .import file")

	var blocked := _tmp_dir.path_join("blocked_project")
	_rmrf(blocked)
	var blocked_file := FileAccess.open(blocked, FileAccess.WRITE)
	blocked_file.store_string("not a directory")
	blocked_file.close()
	var failed: Dictionary = Store.import_texture(sources.path_join("small.png"), blocked, "Blocked")
	_check(not bool(failed.get("ok", true)), "a write failure is reported")

	# No .import file in the successful project folder either.
	var leftovers := _find_extension(_project_dir, "import")
	_check(leftovers.is_empty(), "no editor import pipeline file exists anywhere in the project")


func _find_extension(root: String, extension: String) -> Array:
	var found: Array = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child := root.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_find_extension(child, extension))
			elif entry.get_extension().to_lower() == extension:
				found.append(child)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


func _image_texture(color: Color = Color(0.7, 0.2, 0.2, 1.0)) -> ImageTexture:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _test_adoption() -> void:
	var doc = _new_document()
	var ms = doc.material_system
	var object_id: String = doc.add_primitive("box")

	# A shared StandardMaterial3D on two surfaces dedupes to one entry.
	var generated := Node3D.new()
	generated.name = "Model"
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _two_surface_mesh()
	generated.add_child(body)
	add_child(generated)
	var source := StandardMaterial3D.new()
	source.resource_name = "Painted"
	source.albedo_color = Color(0.15, 0.55, 0.25)
	source.roughness = 0.25
	source.metallic = 0.75
	source.metallic_specular = 0.6
	source.albedo_texture = _image_texture()
	source.normal_enabled = true
	source.normal_texture = _image_texture(Color(0.5, 0.5, 1.0))
	source.normal_scale = 0.7
	source.uv1_scale = Vector3(2.0, 3.0, 1.0)
	source.uv1_offset = Vector3(0.1, 0.2, 0.0)
	source.texture_repeat = false
	source.emission_enabled = true
	source.emission = Color(1.0, 0.5, 0.0)
	source.emission_energy_multiplier = 1.5
	source.emission_texture = _image_texture(Color(1.0, 0.8, 0.1))
	body.set_surface_override_material(0, source)
	body.set_surface_override_material(1, source)

	var adopted: Dictionary = ms.adopt_import(object_id, generated, "Robot")
	_check(bool(adopted.get("ok", false)), "adoption succeeds")
	_check(int(adopted.get("materials", 0)) == 1, "a shared resource dedupes to one material")
	_check(int(adopted.get("textures", 0)) == 3, "albedo, normal and emission textures persist")
	var assigned: Dictionary = doc.get_object(object_id).get("part_surface_materials", {})
	_check(assigned.has("Body#0") and assigned.has("Body#1"), "both surfaces are assigned")
	var adopted_id := str(assigned.get("Body#0", ""))
	_check(str(assigned.get("Body#1", "")) == adopted_id, "both surfaces share the adopted id")
	var record: Dictionary = ms.get_material(adopted_id)
	_check(str(record.get("name", "")).begins_with("Robot · "), "the adopted name carries the model prefix")
	_check(str(record.get("shading", "")) == "pbr", "a Standard material adopts as PBR")
	_check(_approx(float(record.get("roughness", 0.0)), 0.25), "adoption copies roughness")
	_check(_approx(float(record.get("metallic", 0.0)), 0.75), "adoption copies metallic")
	_check(_approx(float(record.get("emission_energy", 0.0)), 1.5), "adoption copies emission energy")
	var albedo_path := str(record.get("albedo_texture", ""))
	_check(albedo_path.begins_with("textures/imported/robot-1-albedo"),
		"the albedo texture is saved under textures/imported")
	_check(FileAccess.file_exists(_project_dir.path_join(albedo_path)), "the adopted texture file exists")
	var built: BaseMaterial3D = ms.resource_for(adopted_id)
	_check(built.albedo_texture != null and built.normal_enabled, "the adopted resource loads its maps")

	# An imported ORMMaterial3D keeps the packed map.
	var orm_root := Node3D.new()
	orm_root.name = "Model"
	var arm := MeshInstance3D.new()
	arm.name = "Arm"
	arm.mesh = BoxMesh.new()
	orm_root.add_child(arm)
	add_child(orm_root)
	var orm_source := ORMMaterial3D.new()
	orm_source.resource_name = "Packed"
	orm_source.orm_texture = _image_texture(Color(0.3, 0.4, 0.5))
	arm.set_surface_override_material(0, orm_source)
	var orm_adopted: Dictionary = ms.adopt_import(object_id, orm_root, "Robot")
	_check(bool(orm_adopted.get("ok", false)), "an ORM material adopts")
	var orm_id := str(doc.get_object(object_id).get("part_surface_materials", {}).get("Arm#0", ""))
	var orm_record: Dictionary = ms.get_material(orm_id)
	_check(str(orm_record.get("orm_texture", "")).begins_with("textures/imported/"),
		"the packed ORM map persists")
	var orm_resource: BaseMaterial3D = ms.resource_for(orm_id)
	_check(orm_resource is ORMMaterial3D, "the adopted ORM record builds an ORMMaterial3D")

	# A texture with no extractable image leaves the slot empty but keeps scalars.
	var placeholder_root := Node3D.new()
	placeholder_root.name = "Model"
	var head := MeshInstance3D.new()
	head.name = "Head"
	head.mesh = BoxMesh.new()
	placeholder_root.add_child(head)
	add_child(placeholder_root)
	var placeholder_material := StandardMaterial3D.new()
	placeholder_material.resource_name = "Compressed"
	placeholder_material.roughness = 0.9
	placeholder_material.albedo_texture = PlaceholderTexture2D.new()
	head.set_surface_override_material(0, placeholder_material)
	var placeholder: Dictionary = ms.adopt_import(object_id, placeholder_root, "Robot")
	_check(bool(placeholder.get("ok", false)), "a compressed material still adopts")
	var placeholder_id := str(doc.get_object(object_id).get("part_surface_materials", {}).get("Head#0", ""))
	var placeholder_record: Dictionary = ms.get_material(placeholder_id)
	_check(str(placeholder_record.get("albedo_texture", "x")) == "",
		"a null texture image leaves the slot empty")
	_check(not (placeholder_record.get("notes", []) as Array).is_empty(),
		"a null texture image records a note")
	_check(_approx(float(placeholder_record.get("roughness", 0.0)), 0.9),
		"the scalar fallback still applies")

	generated.queue_free()
	orm_root.queue_free()
	placeholder_root.queue_free()

	# The material cap leaves the remaining surfaces embedded.
	var capped_doc = _new_document()
	var capped_ms = capped_doc.material_system
	var capped_object: String = capped_doc.add_primitive("box")
	var capped_root := Node3D.new()
	capped_root.name = "Model"
	add_child(capped_root)
	for index in range(33):
		var part := MeshInstance3D.new()
		part.name = "Part%d" % index
		part.mesh = BoxMesh.new()
		capped_root.add_child(part)
		var part_material := StandardMaterial3D.new()
		part_material.resource_name = "Unique %d" % index
		part_material.albedo_color = Color(0.1 * float(index % 5), 0.2, 0.3)
		part.set_surface_override_material(0, part_material)
	var capped: Dictionary = capped_ms.adopt_import(capped_object, capped_root, "Big")
	_check(int(capped.get("materials", 0)) == 32, "adoption caps at 32 materials")
	_check(bool(capped.get("capped", false)), "the cap is reported")
	_check(str(capped.get("notice", "")) == "Adopted 32 of 33 materials; the rest keep their embedded materials.",
		"the cap notice is exact")
	_check(capped_ms.material_ids().size() == 32, "the library holds 32 adopted materials")
	var capped_map: Dictionary = capped_doc.get_object(capped_object).get("part_surface_materials", {})
	_check(capped_map.size() == 32, "adoption assigns exactly the capped surfaces")
	capped_root.queue_free()

	# Real glTF import adoption, then a project load that must not adopt again.
	var glb_root := Node3D.new()
	glb_root.name = "Fixture"
	var glb_mesh := MeshInstance3D.new()
	glb_mesh.name = "Body"
	var box := BoxMesh.new()
	var box_material := StandardMaterial3D.new()
	box_material.albedo_color = Color(0.2, 0.4, 0.8)
	box_material.roughness = 0.31
	box.surface_set_material(0, box_material)
	glb_mesh.mesh = box
	glb_root.add_child(glb_mesh)
	add_child(glb_root)
	await get_tree().process_frame
	var models_dir := _project_dir.path_join("models")
	DirAccess.make_dir_recursive_absolute(models_dir)
	var glb_path := models_dir.path_join("adopted_model.glb")
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var glb_error := gltf.append_from_scene(glb_root, state)
	if glb_error == OK:
		glb_error = gltf.write_to_filesystem(state, glb_path)
	glb_root.queue_free()
	await get_tree().process_frame
	_check(glb_error == OK, "the adoption GLB fixture is written")
	if glb_error == OK:
		var import_doc = _new_document()
		var imported_id: String = import_doc.add_imported("models/adopted_model.glb", "Adopted", Vector3.ZERO)
		await get_tree().process_frame
		var import_count: int = import_doc.material_system.material_ids().size()
		_check(import_count > 0, "a new model import adopts its material")
		_check(import_doc.get_object(imported_id).size() > 0, "the imported object exists")
		var data: Dictionary = import_doc.to_data()
		var reopen = _new_document()
		reopen.load_project(data, _project_dir)
		_check(reopen.material_system.material_ids().size() == import_count,
			"loading a project never adopts the model again")
		import_doc.queue_free()
		reopen.queue_free()

	doc.queue_free()
	capped_doc.queue_free()


# -------------------------------------------------------------------------
# Task 18: inspector, library sheet and editor sheet
# -------------------------------------------------------------------------

func _test_material_ui() -> void:
	var doc = _new_document()
	var object_id: String = doc.add_primitive("box")
	var root: Node3D = doc.nodes.get(object_id)
	var mesh_instance: MeshInstance3D = root.get_node("Mesh")
	mesh_instance.mesh = _two_surface_mesh()

	var inspector = InspectorScript.new()
	add_child(inspector)
	inspector.setup(doc)
	await get_tree().process_frame
	_check(inspector.object_material_text() == "Legacy colour", "an unassigned object shows the legacy colour")
	_check(inspector.legacy_visible(), "legacy colour controls appear without a library material")
	_check(inspector._object_choose != null \
		and inspector._object_choose.custom_minimum_size == Vector2(96.0, 44.0),
		"Choose material is 96x44")
	_check(inspector._object_edit != null and inspector._object_edit.disabled,
		"Edit material is disabled with no material")

	var captured: Dictionary = {}
	inspector.choose_material_requested.connect(func(target: Dictionary) -> void:
		captured["target"] = target
	)
	inspector._object_choose.pressed.emit()
	var object_target: Dictionary = captured.get("target", {})
	_check(str(object_target.get("object_id", "")) == object_id
		and str(object_target.get("part_path", "x")) == ""
		and int(object_target.get("surface", 9)) == -1,
		"the object section targets the object root at surface -1")

	var material_id: String = doc.material_system.create_material("Painted", "satin")
	doc.material_system.assign_material(object_id, material_id)
	inspector._rebuild()
	await get_tree().process_frame
	_check(inspector.object_material_text() == "Painted", "the object section shows the assigned material name")
	_check(not inspector.legacy_visible(), "legacy controls hide once a material is assigned")
	_check(not inspector._object_edit.disabled, "Edit material enables with a material")

	var builds: int = inspector.section_build_count
	doc.part_selection_changed.emit(object_id, "")
	_check(inspector.section_build_count == builds + 1, "the inspector rebuilds on part_selection_changed")

	doc.selected_part_object_id = object_id
	doc.selected_part_path = "Mesh"
	inspector._rebuild()
	await get_tree().process_frame
	_check(inspector.part_material_text().begins_with("Part · Mesh"),
		"a mesh part shows its name in the Part material section")
	var chips: Array = inspector.surface_chips()
	_check(chips.size() == 3, "a two-surface mesh shows All, 0 and 1")
	for chip in chips:
		_check((chip as Button).custom_minimum_size.y >= 44.0, "a surface chip is at least 44 dp tall")
	chips[0].pressed.emit()
	await get_tree().process_frame
	_check(inspector.active_surface() == -1, "the All chip selects surface -1")
	var surface_chips: Array = inspector.surface_chips()
	surface_chips[2].pressed.emit()
	await get_tree().process_frame
	_check(inspector.active_surface() == 1, "a numbered chip selects that surface")
	captured.clear()
	inspector._part_choose.pressed.emit()
	var part_target: Dictionary = captured.get("target", {})
	_check(str(part_target.get("part_path", "")) == "Mesh"
		and int(part_target.get("surface", 9)) == 1,
		"the part action carries the active surface")

	doc.selected_part_path = "NoSuchPart"
	inspector._rebuild()
	await get_tree().process_frame
	_check(inspector.part_material_text() \
		== "Part · NoSuchPart · No mesh. Materials apply at the object level.",
		"a non-mesh part shows the exact no-mesh copy")
	_check(inspector._part_choose == null, "a non-mesh part exposes no part actions")
	_check(inspector.object_material_text() == "Painted", "the object section survives a non-mesh part")
	inspector.queue_free()

	# Library sheet empty state, creation and duplicate.
	var sheet_doc = _new_document()
	var sheet_object: String = sheet_doc.add_primitive("box")
	var sheet = MaterialSheetScript.new()
	sheet.setup(sheet_doc, {"object_id": sheet_object, "part_path": "", "surface": -1})
	add_child(sheet)
	await get_tree().process_frame
	_check(sheet.row_count() == 0, "an empty library lists no rows")
	_check(sheet.empty_text() == "No materials yet. Create one to use textures and shading models.",
		"the empty library copy is exact")
	_check(sheet._new_button.custom_minimum_size.y >= 44.0, "New material is 44 dp tall")
	_check(sheet._duplicate_button.custom_minimum_size.y >= 44.0, "Duplicate is 44 dp tall")
	sheet._on_new()
	await get_tree().process_frame
	_check(sheet.row_count() == 1, "New material adds one row")
	var first_id := sheet.selected_id()
	_check(first_id != "", "a created material is selected")
	_check(sheet.row_height(first_id) >= 44.0, "a library row is 44 dp tall")
	_check(sheet.assign_button(first_id) != null \
		and sheet.assign_button(first_id).custom_minimum_size == Vector2(96.0, 44.0),
		"Assign is 96x44")
	sheet._on_duplicate()
	await get_tree().process_frame
	_check(sheet.row_count() == 2, "Duplicate adds one row")
	var copy_id := sheet.selected_id()
	_check(copy_id != "" and copy_id != first_id, "Duplicate selects the copy")
	var assigned: Dictionary = {}
	sheet.assigned.connect(func(material_id: String) -> void:
		assigned["id"] = material_id
	)
	sheet.assign_material(first_id)
	var sheet_record: Dictionary = sheet_doc.get_object(sheet_object)
	_check(str(sheet_record.get("material_id", "")) == first_id,
		"Assign writes the target object material")
	_check(str(assigned.get("id", "")) == first_id, "Assign reports the material it assigned")
	sheet.queue_free()

	# Editor sheet controls, shading, locks and warnings.
	var edit_doc = _new_document()
	var edit_object: String = edit_doc.add_primitive("box")
	var edit_root: Node3D = edit_doc.nodes.get(edit_object)
	var edit_mesh: MeshInstance3D = edit_root.get_node("Mesh")
	var edit_id: String = edit_doc.material_system.create_material("Editor", "matte")
	var editor_sheet = MaterialEditorSheetScript.new()
	editor_sheet.setup(edit_doc, edit_id)
	add_child(editor_sheet)
	await get_tree().process_frame
	for model in ["pbr", "unlit", "toon", "rim"]:
		var button: Button = editor_sheet.shading_button(model)
		_check(button != null and button.custom_minimum_size.y >= 44.0,
			"the %s shading segment is 44 dp tall" % model)
	_check(editor_sheet.orm_label_text() == "ORM (R=AO · G=Roughness · B=Metallic)",
		"the ORM slot label is exact")
	_check(editor_sheet.texture_filter() == "*.png, *.jpg, *.jpeg, *.webp;Images",
		"the texture picker filter is exact")
	_check(not editor_sheet.rim_visible(), "rim fields stay hidden for PBR")
	_check(editor_sheet.emission_scrub() != null \
		and is_equal_approx(editor_sheet.emission_scrub().max_value, 10.0),
		"emission energy scrubs from 0 to 10")
	_check(editor_sheet.uv_fields().size() == 4, "the editor exposes four UV numeric fields")
	_check(editor_sheet.map_row_height("normal") >= 44.0, "a map row is 44 dp tall")

	editor_sheet.shading_button("unlit").pressed.emit()
	await get_tree().process_frame
	_check(str(edit_doc.material_system.get_material(edit_id).get("shading", "")) == "unlit",
		"Unlit updates the record")
	editor_sheet.shading_button("rim").pressed.emit()
	await get_tree().process_frame
	_check(editor_sheet.rim_visible(), "rim fields appear for Rim")
	editor_sheet.shading_button("pbr").pressed.emit()
	await get_tree().process_frame
	_check(not editor_sheet.rim_visible(), "rim fields hide again for PBR")

	editor_sheet.set_map("roughness", "textures/rough.png")
	editor_sheet.set_map("metallic", "textures/metal.png")
	editor_sheet.set_map("ao", "textures/ao.png")
	_check(not editor_sheet.slot_disabled("roughness"), "separate maps start enabled")
	editor_sheet.set_map("orm", "textures/orm.png")
	_check(editor_sheet.orm_reason_visible(), "the ORM lock explains itself")
	_check(editor_sheet.orm_reason_text() \
		== "Packed ORM supplies AO, roughness and metallic. Clear ORM to use separate maps.",
		"the ORM lock copy is exact")
	_check(editor_sheet.slot_disabled("roughness") and editor_sheet.slot_disabled("metallic") \
		and editor_sheet.slot_disabled("ao"),
		"ORM disables AO, roughness and metallic")
	var locked_record: Dictionary = edit_doc.material_system.get_material(edit_id)
	_check(str(locked_record.get("roughness_texture", "")) == "textures/rough.png" \
		and str(locked_record.get("metallic_texture", "")) == "textures/metal.png" \
		and str(locked_record.get("ao_texture", "")) == "textures/ao.png",
		"the separate map files survive the ORM lock")
	editor_sheet.clear_map("orm")
	_check(not editor_sheet.slot_disabled("roughness"), "clearing ORM re-enables separate maps")
	_check(not editor_sheet.orm_reason_visible(), "clearing ORM hides the lock copy")

	editor_sheet.set_map("normal", "textures/missing.png")
	_check(editor_sheet.slot_state("normal") == "textures/missing.png",
		"a missing map shows its stored path")
	_check(editor_sheet.slot_state_color("normal") == KitScript.WARNING,
		"a missing map is a warning colour")

	var bare_mesh := ArrayMesh.new()
	var bare_arrays: Array = []
	bare_arrays.resize(Mesh.ARRAY_MAX)
	bare_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.0), Vector3(0.0, 0.5, 0.0),
	])
	bare_arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	bare_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bare_arrays)
	edit_mesh.mesh = bare_mesh
	editor_sheet.set_target({"object_id": edit_object, "part_path": "Mesh", "surface": -1})
	_check(editor_sheet.uv_warning_visible(), "a mesh without UVs warns about textures")
	_check(editor_sheet.uv_warning_text() == "This part has no UVs; a texture will sample a single point.",
		"the no-UV warning copy is exact")
	_check(editor_sheet.duplicate_button() != null \
		and editor_sheet.duplicate_button().custom_minimum_size.y >= 44.0,
		"Duplicate is 44 dp tall in the editor")
	_check(editor_sheet.delete_button() != null \
		and editor_sheet.delete_button().custom_minimum_size.y >= 44.0,
		"Delete is 44 dp tall in the editor")
	editor_sheet.queue_free()

	doc.queue_free()
	sheet_doc.queue_free()
	edit_doc.queue_free()
