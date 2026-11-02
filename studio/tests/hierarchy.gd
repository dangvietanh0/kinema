extends Node
## Import hierarchy suite (Task U2).
##
## Builds a real GLB fixture at runtime, imports it into a document and checks
## the derived part tree, part visibility/selection persistence and the
## outliner's disclosure, selection, visibility and search behaviour. Every
## assertion prints OK/FAIL and the run ends with HIERARCHY RESULT.

const DocumentScript = preload("res://src/core/document.gd")
const OutlinerScript = preload("res://src/ui/outliner.gd")
const EditorViewScript = preload("res://src/viewport/editor_view.gd")

const EPS := 0.01
const ROW_HEIGHT := 44.0

const BODY := "Model/Body"
const HEAD := "Model/Body/Head"
const EMPTY := "Model/Empty"
const CHILD_MESH := "Model/Empty/ChildMesh"
const LIGHT := "Model/KeyLight"
const CAMERA := "Model/Cam"
const SKELETON := "Model/Skeleton"

var _failures: Array[String] = []
var _checks := 0
var _tmp_dir := ""
var _fixture := ""
var _part_signal_count := 0
var _part_signal_log: Array = []


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("HIERARCHY OK: " + message)
	else:
		_failures.append(message)
		printerr("HIERARCHY FAIL: " + message)


func _ready() -> void:
	_tmp_dir = ProjectSettings.globalize_path("user://hierarchy_tests")
	_rmrf(_tmp_dir)
	DirAccess.make_dir_recursive_absolute(_tmp_dir)
	await get_tree().process_frame
	await get_tree().process_frame
	var exported: bool = await _export_fixture()
	_check(exported, "the hierarchy fixture GLB is written to user://")
	if not exported:
		_finish()
		return
	await _test_parts()
	await _test_lookup_and_bounds()
	await _test_part_selection()
	await _test_visibility()
	await _test_selection_roundtrip()
	await _test_obj_import_gate()
	await _test_outliner_tree()
	await _test_outliner_selection()
	await _test_outliner_visibility()
	await _test_outliner_search()
	await _test_outliner_identity()
	await _test_outliner_targets()
	await _test_stage_feedback()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("HIERARCHY RESULT: PASS (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		print("HIERARCHY RESULT: FAIL (%d checks, %d failures)" % [_checks, _failures.size()])
		for failure in _failures:
			printerr("  - " + failure)
		get_tree().quit(1)


# -------------------------------------------------------------------------
# Fixture
# -------------------------------------------------------------------------

func _rmrf(path: String) -> void:
	if path == "" or not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for name in dir.get_files():
		dir.remove(name)
	for name in dir.get_directories():
		_rmrf(path.path_join(name))
	DirAccess.remove_absolute(path)


func _export_fixture() -> bool:
	var root := Node3D.new()
	root.name = "StudioModel"
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = BoxMesh.new()
	body.position = Vector3(0.5, 1.0, 0.0)
	root.add_child(body)
	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.4, 0.4, 0.4)
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.8, 0.0)
	body.add_child(head)
	var empty := Node3D.new()
	empty.name = "Empty"
	empty.position = Vector3(1.5, 0.0, 0.0)
	root.add_child(empty)
	var child_mesh := MeshInstance3D.new()
	child_mesh.name = "ChildMesh"
	var child_box := BoxMesh.new()
	child_box.size = Vector3(0.3, 0.3, 0.3)
	child_mesh.mesh = child_box
	empty.add_child(child_mesh)
	var light := OmniLight3D.new()
	light.name = "KeyLight"
	light.position = Vector3(0.0, 2.0, 0.5)
	root.add_child(light)
	var camera := Camera3D.new()
	camera.name = "Cam"
	camera.position = Vector3(2.0, 1.5, 3.0)
	root.add_child(camera)
	add_child(root)
	await get_tree().process_frame
	_fixture = _tmp_dir.path_join("hierarchy_fixture.glb")
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_scene(root, state)
	if err == OK:
		err = gltf.write_to_filesystem(state, _fixture)
	root.queue_free()
	await get_tree().process_frame
	return err == OK


func _new_doc(title: String) -> Variant:
	var doc: Variant = DocumentScript.new()
	add_child(doc)
	await get_tree().process_frame
	doc.new_project(title, "blank")
	doc.project_dir = _tmp_dir.path_join("project_" + title.validate_node_name())
	DirAccess.make_dir_recursive_absolute(doc.project_dir)
	_part_signal_count = 0
	_part_signal_log.clear()
	doc.part_selection_changed.connect(_on_part_signal)
	return doc


func _on_part_signal(object_id: String, part_path: String) -> void:
	_part_signal_count += 1
	_part_signal_log.append([object_id, part_path])


func _free_doc(doc: Variant) -> void:
	if doc != null and is_instance_valid(doc):
		doc.queue_free()
		await get_tree().process_frame


## Imports the fixture and appends the Skeleton3D that glTF skin export would
## otherwise be needed to provide.
func _import(doc: Variant) -> String:
	var imported: Dictionary = Store.import_model(_fixture, str(doc.project_dir), "Rig")
	if not bool(imported.get("ok", false)):
		_check(false, "ProjectStore imports the hierarchy fixture (%s)" % str(imported.get("error", "")))
		return ""
	var id: String = doc.add_imported(str(imported.get("rel_path", "")), "Rig")
	var object_node: Node3D = doc.nodes.get(id)
	if object_node != null:
		var model := object_node.get_node_or_null("Model")
		if model != null:
			var skeleton := Skeleton3D.new()
			skeleton.name = "Skeleton"
			model.add_child(skeleton)
	await get_tree().process_frame
	return id


func _entry(parts: Array, path: String) -> Dictionary:
	for part in parts:
		if str(part.get("path", "")) == path:
			return part
	return {}


func _paths(parts: Array) -> Array:
	var result: Array = []
	for part in parts:
		result.append(str(part.get("path", "")))
	return result


func _aabb_close(a: AABB, b: AABB) -> bool:
	if a.position.distance_to(b.position) > EPS:
		return false
	if a.size.distance_to(b.size) > EPS:
		return false
	return true


# -------------------------------------------------------------------------
# Document: parts, lookup, bounds
# -------------------------------------------------------------------------

func _test_parts() -> void:
	print("HIERARCHY STEP: document part tree")
	var doc: Variant = await _new_doc("Parts")
	var id: String = await _import(doc)
	_check(id != "", "the import object spawns")
	if id == "":
		await _free_doc(doc)
		return
	_check(str(doc.get_object(id).get("kind", "")) == "import", "the object is an import root")
	var parts: Array = doc.import_parts(id)
	_check(parts.size() == 7, "import_parts lists the seven Node3D parts (got %d)" % parts.size())
	var expected := [
		[BODY, "Body", "mesh", 1, "", true],
		[HEAD, "Head", "mesh", 2, BODY, false],
		[EMPTY, "Empty", "empty", 1, "", true],
		[CHILD_MESH, "ChildMesh", "mesh", 2, EMPTY, false],
		[LIGHT, "KeyLight", "light", 1, "", false],
		[CAMERA, "Cam", "camera", 1, "", false],
		[SKELETON, "Skeleton", "skeleton", 1, "", false],
	]
	var order_ok := _paths(parts) == _paths(_expected_entries(expected))
	_check(order_ok, "import_parts walks the tree deterministically in pre-order")
	for row in expected:
		var entry: Dictionary = _entry(parts, str(row[0]))
		_check(not entry.is_empty(), "part %s is listed" % str(row[0]))
		if entry.is_empty():
			continue
		_check(str(entry.get("name", "")) == str(row[1]), "%s keeps its node name" % str(row[0]))
		_check(str(entry.get("kind", "")) == str(row[2]), "%s maps to kind %s" % [str(row[0]), str(row[2])])
		_check(int(entry.get("depth", -1)) == int(row[3]), "%s sits at depth %d" % [str(row[0]), int(row[3])])
		_check(str(entry.get("parent", "?")) == str(row[4]), "%s reports its listed parent" % str(row[0]))
		_check(bool(entry.get("has_children", true)) == bool(row[5]), "%s has_children is %s" % [str(row[0]), str(row[5])])
		_check(bool(entry.get("visible", false)), "%s reports its local visibility" % str(row[0]))
		_check(bool(entry.get("effective_visible", false)), "%s is effectively visible" % str(row[0]))
	var again: Array = doc.import_parts(id)
	_check(_paths(again) == _paths(parts), "import_parts is stable across calls")
	var non_import: String = str(doc.objects[0].get("id", ""))
	_check(doc.import_parts(non_import).is_empty(), "a non-import object has no parts")
	_check(doc.import_parts("missing").is_empty(), "a missing object has no parts")
	var model_part: Array = doc.import_parts(id)
	_check(_entry(model_part, "Model").is_empty(), "the generated Model wrapper is not a part")
	await _free_doc(doc)


func _expected_entries(rows: Array) -> Array:
	var result: Array = []
	for row in rows:
		result.append({"path": str(row[0])})
	return result


func _test_lookup_and_bounds() -> void:
	print("HIERARCHY STEP: part lookup and world bounds")
	var doc: Variant = await _new_doc("Bounds")
	var id: String = await _import(doc)
	if id == "":
		await _free_doc(doc)
		return
	var head: Node3D = doc.get_import_part_node(id, HEAD)
	_check(head != null and head.name == "Head", "get_import_part_node resolves a nested part")
	_check(doc.get_import_part_node(id, "Model/Nope") == null, "a bad part path resolves to null")
	_check(doc.get_import_part_node(id, "Model") == null, "the Model wrapper resolves to null")
	_check(doc.get_import_part_node("missing", HEAD) == null, "a missing import resolves to null")
	head.position = Vector3(0.35, 0.55, -0.45)
	await get_tree().process_frame
	var measured: AABB = doc.get_import_part_aabb(id, HEAD)
	var expected: AABB = head.global_transform * head.get_aabb()
	_check(_aabb_close(measured, expected), "get_import_part_aabb matches the node's world AABB")
	# Hidden suppression belongs to the selection query, not the explicit part
	# bounds query: callers asking for a valid part always get its world AABB.
	doc.set_selected_part(id, HEAD)
	doc.set_import_part_visible(id, HEAD, false)
	await get_tree().process_frame
	var hidden_measured: AABB = doc.get_import_part_aabb(id, HEAD)
	_check(_aabb_close(hidden_measured, expected),
		"a hidden valid part still reports its world AABB")
	_check(doc.get_selected_part_aabb() == AABB(),
		"a hidden part selected via the root still has no stage highlight AABB")
	doc.set_import_part_visible(id, HEAD, true)
	await get_tree().process_frame
	_check(_aabb_close(doc.get_import_part_aabb(id, HEAD), expected),
		"the part bounds return to normal after unhiding")
	_check(doc.get_import_part_aabb(id, "Model/Nope") == AABB(), "a bad path returns an empty AABB")
	_check(doc.get_import_part_aabb("missing", HEAD) == AABB(), "a missing import returns an empty AABB")
	await _free_doc(doc)


func _test_part_selection() -> void:
	print("HIERARCHY STEP: part selection")
	var doc: Variant = await _new_doc("Selection")
	var id: String = await _import(doc)
	if id == "":
		await _free_doc(doc)
		return
	var other: String = doc.add_primitive("cube")
	doc.set_selection(id)
	_part_signal_count = 0
	_part_signal_log.clear()
	doc.set_selected_part(id, HEAD)
	_check(doc.selected_id == id, "selecting a part keeps the import root selected")
	_check(doc.selected_part_object_id == id, "the selected part object id is stored")
	_check(doc.selected_part_path == HEAD, "the selected part path is stored")
	_check(_part_signal_count == 1 and _part_signal_log[0] == [id, HEAD],
		"part_selection_changed fires once with the part")
	var head: Node3D = doc.get_import_part_node(id, HEAD)
	var expected: AABB = head.global_transform * head.get_aabb()
	_check(_aabb_close(doc.get_selected_part_aabb(), expected),
		"get_selected_part_aabb returns the selected part's world AABB")
	doc.set_selection(id)
	_check(doc.selected_part_path == HEAD, "selecting the same root again keeps the part")
	_check(_part_signal_count == 1, "selecting the same root does not re-emit part_selection_changed")
	doc.set_selected_part(id, "Model/Nope")
	_check(doc.selected_part_path == HEAD and _part_signal_count == 1,
		"an unresolvable part path is ignored")
	doc.set_selection(other)
	_check(doc.selected_part_path == "" and doc.selected_part_object_id == "",
		"selecting another root clears the part selection")
	_check(_part_signal_count == 2 and _part_signal_log[1] == ["", ""],
		"clearing the part selection emits the empty part once")
	doc.set_selected_part(id, HEAD)
	_check(doc.selected_part_path == HEAD, "the part can be selected again")
	doc.clear_selected_part()
	_check(doc.selected_part_path == "" and doc.selected_part_object_id == "",
		"clear_selected_part clears the fields")
	_check(_part_signal_count == 4, "clear_selected_part emits once")
	await _free_doc(doc)


func _test_visibility() -> void:
	print("HIERARCHY STEP: part visibility")
	var doc: Variant = await _new_doc("Visibility")
	var id: String = await _import(doc)
	if id == "":
		await _free_doc(doc)
		return
	var body: Node3D = doc.get_import_part_node(id, BODY)
	_check(body != null and body.visible, "the part starts visible")
	doc.set_import_part_visible(id, BODY, false)
	body = doc.get_import_part_node(id, BODY)
	_check(body != null and not body.visible, "set_import_part_visible hides the live part node")
	var obj: Dictionary = doc.get_object(id)
	_check(obj.has("part_visibility") and bool(obj["part_visibility"].get(BODY, true)) == false,
		"the visibility override is stored on the import object")
	var parts: Array = doc.import_parts(id)
	_check(bool(_entry(parts, BODY).get("effective_visible", true)) == false,
		"a hidden part reports effective_visible false")
	_check(bool(_entry(parts, HEAD).get("effective_visible", true)) == false,
		"a hidden ancestor hides its descendants")
	_check(bool(_entry(parts, EMPTY).get("effective_visible", false)) == true,
		"siblings stay visible")
	doc.undo()
	body = doc.get_import_part_node(id, BODY)
	_check(body != null and body.visible, "undo restores part visibility")
	obj = doc.get_object(id)
	_check(obj.get("part_visibility", {"x": true}).is_empty(), "undo restores the override dictionary")
	doc.set_selected_part(id, HEAD)
	doc.set_import_part_visible(id, BODY, false)
	_check(doc.get_selected_part_aabb() == AABB(),
		"a hidden selected part has no stage highlight AABB")
	var data: Dictionary = doc.to_data()
	_check(data.has("selected_part_object_id") and data.has("selected_part_path"),
		"to_data carries the part selection fields")
	var fresh: Variant = await _new_doc("VisibilityReload")
	fresh.load_project(data, str(doc.project_dir))
	body = fresh.get_import_part_node(id, BODY)
	_check(body != null and not body.visible, "a saved visibility override reapplies on load")
	var fresh_parts: Array = fresh.import_parts(id)
	_check(bool(_entry(fresh_parts, HEAD).get("effective_visible", true)) == false,
		"the loaded override still hides descendants")
	await _free_doc(doc)
	await _free_doc(fresh)


func _test_selection_roundtrip() -> void:
	print("HIERARCHY STEP: selection persistence")
	var doc: Variant = await _new_doc("Roundtrip")
	var id: String = await _import(doc)
	if id == "":
		await _free_doc(doc)
		return
	doc.set_selected_part(id, HEAD)
	var data: Dictionary = doc.to_data()
	_check(str(data.get("selected_part_object_id", "")) == id, "to_data persists the selected part root")
	_check(str(data.get("selected_part_path", "")) == HEAD, "to_data persists the selected part path")
	var fresh: Variant = await _new_doc("RoundtripLoad")
	fresh.load_project(data, str(doc.project_dir))
	_check(fresh.selected_part_object_id == id, "load_project restores the selected part root")
	_check(fresh.selected_part_path == HEAD, "load_project restores the selected part path")
	_check(fresh.selected_id == id, "load_project keeps the import root selected")
	var stale: Dictionary = data.duplicate(true)
	stale["selected_part_path"] = "Model/Body/Ghost"
	var fresh_two: Variant = await _new_doc("StaleLoad")
	fresh_two.load_project(stale, str(doc.project_dir))
	_check(fresh_two.selected_part_object_id == "" and fresh_two.selected_part_path == "",
		"a stale part path clears silently on load")
	await _free_doc(doc)
	await _free_doc(fresh)
	await _free_doc(fresh_two)


# -------------------------------------------------------------------------
# OBJ imports
# -------------------------------------------------------------------------

## Spec §8 keeps OBJ as a single mesh row. The runtime OBJ parser still builds
## an internal wrapper, so an ungated part list would grow a disclosure and a
## fake Model/Model child. Only glTF/GLB sources expose parts.
func _test_obj_import_gate() -> void:
	print("HIERARCHY STEP: OBJ imports stay a single mesh row")
	var doc: Variant = await _new_doc("ObjGate")
	var obj_path := _tmp_dir.path_join("obj_gate.obj")
	var file := FileAccess.open(obj_path, FileAccess.WRITE)
	var wrote := false
	if file != null:
		file.store_string("# flat triangle\nv 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n")
		file.close()
		wrote = true
	_check(wrote, "the OBJ fixture is written")
	var imported: Dictionary = Store.import_model(obj_path, str(doc.project_dir), "Flat")
	_check(bool(imported.get("ok", false)),
		"ProjectStore imports the OBJ fixture (%s)" % str(imported.get("error", "")))
	if not bool(imported.get("ok", false)):
		await _free_doc(doc)
		return
	var id: String = doc.add_imported(str(imported.get("rel_path", "")), "Flat")
	await get_tree().process_frame
	_check(id != "", "the OBJ import object spawns")
	_check(doc.import_parts(id).is_empty(), "an OBJ import exposes no parts")
	_check(doc.get_import_part_node(id, "Model/Model") == null,
		"the OBJ wrapper never resolves as a listed part")
	_check(doc.get_import_part_aabb(id, "Model/Model") == AABB(),
		"the OBJ wrapper never reports part bounds")
	if id == "":
		await _free_doc(doc)
		return
	doc.set_selection(id)
	var outliner: Variant = await _new_outliner(doc)
	var root: Control = _root_row(outliner, id)
	_check(root != null, "the OBJ import has a root row")
	if root != null:
		_check(_disclosure(root) == null, "the OBJ root has no disclosure chevron")
	_check(_part_rows(outliner).is_empty(), "the OBJ import renders no part rows")
	# Force the expansion state on: even an expanded OBJ root must stay flat.
	outliner._expanded[id] = true
	outliner._rebuild()
	await get_tree().process_frame
	_check(_root_row(outliner, id) != null, "the expanded OBJ import keeps its root row")
	_check(_disclosure(_root_row(outliner, id)) == null,
		"the expanded OBJ root still has no disclosure chevron")
	_check(_part_rows(outliner).is_empty(), "the expanded OBJ import never grows part rows")
	await _free_doc(doc)


# -------------------------------------------------------------------------
# Outliner
# -------------------------------------------------------------------------

func _new_outliner(doc: Variant) -> Variant:
	var host := Control.new()
	host.size = Vector2(280.0, 760.0)
	add_child(host)
	var outliner: Variant = OutlinerScript.new()
	host.add_child(outliner)
	outliner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outliner.setup(doc)
	await get_tree().process_frame
	await get_tree().process_frame
	return outliner


## Builds the real stage view and hands it the document the same way the app
## does, so the overlay feedback is tested at the control that draws it. The
## view adopts (re-parents) the document into its SubViewport.
func _new_view(doc: Variant) -> Variant:
	var host := Control.new()
	host.size = Vector2(800.0, 500.0)
	add_child(host)
	var view: Variant = EditorViewScript.new()
	view.name = "HierarchyView"
	host.add_child(view)
	view.size = host.size
	view.set_document(doc)
	for _i in 3:
		await get_tree().process_frame
	return view


func _root_row(outliner: Variant, id: String) -> Control:
	for row in outliner._list.get_children():
		if row.has_meta("object_id") and not row.has_meta("part_path") and str(row.get_meta("object_id")) == id:
			return row as Control
	return null


func _part_row(outliner: Variant, root_id: String, path: String) -> Control:
	for row in outliner._list.get_children():
		if row.has_meta("part_path") and str(row.get_meta("part_path")) == path and str(row.get_meta("object_id")) == root_id:
			return row as Control
	return null


func _part_rows(outliner: Variant) -> Array:
	var rows: Array = []
	for row in outliner._list.get_children():
		if row.has_meta("part_path"):
			rows.append(row)
	return rows


func _row_buttons(row: Control) -> Array:
	var result: Array = []
	var stack: Array[Node] = [row]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Button:
			result.append(node)
	return result


func _disclosure(row: Control) -> Button:
	for button in _row_buttons(row):
		if button.has_meta("disclosure"):
			return button
	return null


func _control_role(row: Control, role: String) -> Control:
	var stack: Array[Node] = [row]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Control and str(node.get_meta("role", "")) == role:
			return node as Control
	return null


func _row_eye(row: Control) -> Button:
	for button in _row_buttons(row):
		if not button.has_meta("disclosure"):
			return button
	return null


func _tap(control: Control) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(8.0, 8.0)
	press.device = 0
	control.gui_input.emit(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(8.0, 8.0)
	release.device = 0
	control.gui_input.emit(release)


func _style_bg(row: Control) -> Color:
	var style := row.get_theme_stylebox("panel") as StyleBoxFlat
	return style.bg_color if style != null else Color(0, 0, 0, 0)


func _test_outliner_tree() -> void:
	print("HIERARCHY STEP: outliner disclosure tree")
	var doc: Variant = await _new_doc("Outliner")
	var id: String = await _import(doc)
	if id == "":
		await _free_doc(doc)
		return
	doc.set_selection(id)
	var outliner: Variant = await _new_outliner(doc)
	var root: Control = _root_row(outliner, id)
	_check(root != null, "the import root has an outliner row")
	if root == null:
		await _free_doc(doc)
		return
	var disclosure: Button = _disclosure(root)
	_check(disclosure != null, "an import root with parts has a disclosure control")
	if disclosure != null:
		_check(absf(disclosure.custom_minimum_size.x - ROW_HEIGHT) < 0.01
			and absf(disclosure.custom_minimum_size.y - ROW_HEIGHT) < 0.01,
			"the root disclosure is a 44x44 target")
	_check(_part_rows(outliner).is_empty(), "roots start collapsed")
	disclosure.pressed.emit()
	await get_tree().process_frame
	var rows: Array = _part_rows(outliner)
	_check(rows.size() == 5, "expanding the root lists its five direct parts (got %d)" % rows.size())
	var row_heights_ok := true
	for row in rows:
		if absf(row.custom_minimum_size.y - ROW_HEIGHT) > 0.01:
			row_heights_ok = false
		if not row.has_meta("object_id") or str(row.get_meta("object_id")) != id:
			row_heights_ok = false
	_check(row_heights_ok, "every part row is 44 dp and carries the root object id")
	_check(_part_row(outliner, id, BODY) != null and _part_row(outliner, id, HEAD) == null,
		"a collapsed part hides its children")
	var body_row: Control = _part_row(outliner, id, BODY)
	_check(body_row.has_meta("part_path"), "part rows carry part_path metadata")
	var body_disclosure: Button = _disclosure(body_row)
	_check(body_disclosure != null, "a part with children exposes a disclosure control")
	if body_disclosure != null:
		_check(absf(body_disclosure.custom_minimum_size.x - ROW_HEIGHT) < 0.01,
			"the part disclosure slot is 44 dp wide")
		body_disclosure.pressed.emit()
		await get_tree().process_frame
		_check(_part_row(outliner, id, HEAD) != null, "expanding a part lists its children")
		_check(_part_rows(outliner).size() == 6, "the nested part adds one row")
	var leaf: Control = _part_row(outliner, id, LIGHT)
	var leaf_disclosure: Button = _disclosure(leaf)
	_check(leaf_disclosure == null, "a childless part has no disclosure control")
	var slot: Control = _control_role(leaf, "disclosure-slot")
	_check(slot != null and absf(slot.custom_minimum_size.x - ROW_HEIGHT) < 0.01,
		"a childless part keeps the 44 dp disclosure slot as an inert spacer")
	var cube: String = doc.add_primitive("cube")
	await get_tree().process_frame
	var cube_row: Control = _root_row(outliner, cube)
	_check(cube_row != null and _disclosure(cube_row) == null,
		"a root without parts has no disclosure control")
	disclosure = _disclosure(_root_row(outliner, id))
	disclosure.pressed.emit()
	await get_tree().process_frame
	_check(_part_rows(outliner).is_empty(), "collapsing the root removes every part row")
	var max_height := 0.0
	for row in outliner._list.get_children():
		max_height = maxf(max_height, (row as Control).size.y)
	_check(max_height <= ROW_HEIGHT + 0.6, "expanded rows never grow taller than 44 dp")
	await _free_doc(doc)


func _test_outliner_selection() -> void:
	print("HIERARCHY STEP: outliner selection")
	var doc: Variant = await _new_doc("OutlinerSelect")
	var id: String = await _import(doc)
	if id == "":
		await _free_doc(doc)
		return
	doc.set_selection(id)
	var outliner: Variant = await _new_outliner(doc)
	var disclosure: Button = _disclosure(_root_row(outliner, id))
	disclosure.pressed.emit()
	await get_tree().process_frame
	disclosure = _disclosure(_root_row(outliner, id))
	var body_row: Control = _part_row(outliner, id, BODY)
	var root_row: Control = _root_row(outliner, id)
	_tap(body_row)
	await get_tree().process_frame
	_check(doc.selected_part_path == BODY and doc.selected_part_object_id == id,
		"tapping a part row selects it in the document")
	_check(doc.selected_id == id, "the inspector keeps editing the import root")
	body_row = _part_row(outliner, id, BODY)
	root_row = _root_row(outliner, id)
	_check(_style_bg(body_row).is_equal_approx(Kit.SURFACE_ACTIVE),
		"the selected part row uses the bright selected fill")
	_check(not _style_bg(root_row).is_equal_approx(Kit.SURFACE_ACTIVE),
		"the selected part's root row switches to the quiet context style")
	_check(doc.selected_id == id and doc.selected_part_path == BODY,
		"tapping the disclosure or the eye never changes the selection")
	_disclosure(root_row).pressed.emit()
	await get_tree().process_frame
	_check(doc.selected_part_path == BODY, "the root disclosure does not clear the part selection")
	disclosure = _disclosure(_root_row(outliner, id))
	disclosure.pressed.emit()
	await get_tree().process_frame
	root_row = _root_row(outliner, id)
	_row_eye(root_row).pressed.emit()
	await get_tree().process_frame
	_check(doc.selected_part_path == BODY, "the root eye does not clear the part selection")
	_tap(_root_row(outliner, id))
	await get_tree().process_frame
	_check(doc.selected_part_path == "", "tapping the root clears the part highlight")
	_check(doc.selected_id == id, "the root stays selected")
	_check(_style_bg(_root_row(outliner, id)).is_equal_approx(Kit.SURFACE_ACTIVE),
		"the root returns to the bright selected fill")
	await _free_doc(doc)


func _test_outliner_visibility() -> void:
	print("HIERARCHY STEP: outliner visibility")
	var doc: Variant = await _new_doc("OutlinerVisibility")
	var id: String = await _import(doc)
	if id == "":
		await _free_doc(doc)
		return
	doc.set_selection(id)
	var outliner: Variant = await _new_outliner(doc)
	_disclosure(_root_row(outliner, id)).pressed.emit()
	await get_tree().process_frame
	var empty_row: Control = _part_row(outliner, id, EMPTY)
	_row_eye(empty_row).pressed.emit()
	await get_tree().process_frame
	var node: Node3D = doc.get_import_part_node(id, EMPTY)
	_check(node != null and not node.visible, "the part eye hides the live part")
	empty_row = _part_row(outliner, id, EMPTY)
	_check(empty_row.modulate.a < 0.99, "a hidden part row dims")
	_row_eye(empty_row).pressed.emit()
	await get_tree().process_frame
	node = doc.get_import_part_node(id, EMPTY)
	_check(node != null and node.visible, "the part eye restores visibility")
	_check(_part_row(outliner, id, EMPTY).modulate.a > 0.99, "a visible part row is not dimmed")
	# Expand Body so its child is on screen, then hide the parent.
	_disclosure(_part_row(outliner, id, BODY)).pressed.emit()
	await get_tree().process_frame
	var head_row: Control = _part_row(outliner, id, HEAD)
	_check(head_row != null, "the nested part row is visible")
	_row_eye(_part_row(outliner, id, BODY)).pressed.emit()
	await get_tree().process_frame
	head_row = _part_row(outliner, id, HEAD)
	_check(head_row != null and head_row.modulate.a < 0.99,
		"a hidden parent dims its descendants")
	var doc_node: Node3D = doc.get_import_part_node(id, HEAD)
	_check(doc_node != null and doc_node.is_visible_in_tree() == false,
		"the descendant is effectively hidden")
	# Hiding the import root dims every part.
	doc.set_object_visible(id, false)
	await get_tree().process_frame
	var all_dim := true
	for row in _part_rows(outliner):
		if row.modulate.a > 0.99:
			all_dim = false
	_check(all_dim and not _part_rows(outliner).is_empty(), "a hidden import root dims all its parts")
	await _free_doc(doc)


func _test_outliner_search() -> void:
	print("HIERARCHY STEP: outliner search")
	var doc: Variant = await _new_doc("OutlinerSearch")
	var id: String = await _import(doc)
	if id == "":
		await _free_doc(doc)
		return
	doc.set_selection(id)
	var outliner: Variant = await _new_outliner(doc)
	_disclosure(_root_row(outliner, id)).pressed.emit()
	await get_tree().process_frame
	outliner._search.text = "head"
	outliner._on_search_changed("head")
	await get_tree().process_frame
	var paths: Array = []
	for row in _part_rows(outliner):
		paths.append(str(row.get_meta("part_path")))
	_check(_root_row(outliner, id) != null, "a part match keeps the root visible")
	_check(paths.has(BODY) and paths.has(HEAD),
		"a part match shows the matching part and its listed ancestor")
	_check(not paths.has(EMPTY) and not paths.has(LIGHT) and not paths.has(CAMERA),
		"a part match hides siblings")
	_check(_part_rows(outliner).size() == 2, "a part match shows only the path rows (got %d)" % _part_rows(outliner).size())
	# A forced part search ignores the stored expansion state, so an
	# interactive chevron there would be a fake affordance. The rows keep the
	# 44 dp slot for alignment, but no disclosure control.
	_check(_disclosure(_root_row(outliner, id)) == null,
		"a forced part search hides the fake root disclosure")
	var forced_disclosures := 0
	for row in _part_rows(outliner):
		if _disclosure(row) != null:
			forced_disclosures += 1
	_check(forced_disclosures == 0,
		"a forced part search draws no disclosure chevrons (found %d)" % forced_disclosures)
	_check(_control_role(_root_row(outliner, id), "disclosure-slot") != null,
		"the forced root keeps the 44 dp disclosure slot")
	_check(_control_role(_part_row(outliner, id, BODY), "disclosure-slot") != null,
		"a forced part with children keeps the 44 dp disclosure slot")
	outliner._search.text = "rig"
	outliner._on_search_changed("rig")
	await get_tree().process_frame
	_check(_root_row(outliner, id) != null, "a root name match keeps the root visible")
	_check(_disclosure(_root_row(outliner, id)) != null,
		"a root name match keeps the real disclosure control")
	_check(_part_rows(outliner).size() == 5, "a root match honours the stored expansion state")
	_check(_part_row(outliner, id, BODY) != null, "the root match shows its first-level parts")
	outliner._search.text = ""
	outliner._on_search_changed("")
	await get_tree().process_frame
	_check(_part_rows(outliner).size() == 5, "clearing the search restores the expansion state")
	_check(_part_row(outliner, id, HEAD) == null, "clearing the search restores the collapsed part")
	outliner._search.text = "zzzz"
	outliner._on_search_changed("zzzz")
	await get_tree().process_frame
	_check(_root_row(outliner, id) == null and _part_rows(outliner).is_empty(),
		"a non-matching search hides every row")
	_check(outliner._empty.visible, "the empty state appears when nothing matches")
	var empty_title := outliner._empty.get_child(1) as Label
	_check(empty_title != null and empty_title.text == "No matching objects",
		"the empty state says no matching objects")
	outliner._search.text = ""
	outliner._on_search_changed("")
	await get_tree().process_frame
	await _free_doc(doc)


func _test_outliner_identity() -> void:
	print("HIERARCHY STEP: outliner project identity")
	var doc: Variant = await _new_doc("Identity")
	var id: String = await _import(doc)
	if id == "":
		await _free_doc(doc)
		return
	doc.set_selection(id)
	var outliner: Variant = await _new_outliner(doc)
	_disclosure(_root_row(outliner, id)).pressed.emit()
	await get_tree().process_frame
	_check(not outliner._expanded.is_empty(), "expansion state is remembered while the project is open")
	_check(_part_rows(outliner).size() == 5, "the expanded root is on screen before the load")
	var data: Dictionary = doc.to_data()
	data["title"] = "Another Take"
	doc.load_project(data, str(doc.project_dir))
	await get_tree().process_frame
	_check(outliner._expanded.is_empty(), "loading another project clears the UI expansion state")
	_check(_part_rows(outliner).is_empty(), "reopening a project shows roots collapsed")
	_check(_root_row(outliner, id) != null, "the import root itself is still listed")
	await _free_doc(doc)


func _test_outliner_targets() -> void:
	print("HIERARCHY STEP: outliner touch targets")
	var doc: Variant = await _new_doc("Targets")
	var id: String = await _import(doc)
	if id == "":
		await _free_doc(doc)
		return
	var outliner: Variant = await _new_outliner(doc)
	_disclosure(_root_row(outliner, id)).pressed.emit()
	await get_tree().process_frame
	var short := 0
	var buttons: Array = _row_buttons(outliner)
	var saw_add := false
	var saw_header_collapse := false
	for button in buttons:
		if button.tooltip_text == "Add object":
			saw_add = true
		if button == outliner._collapse_button:
			saw_header_collapse = true
		if not button.visible or button.has_meta("qa_hit_exempt"):
			continue
		if (button.get_combined_minimum_size().x < ROW_HEIGHT - 0.01
			or button.get_combined_minimum_size().y < ROW_HEIGHT - 0.01):
			short += 1
			print("HIERARCHY SHORT: '", button.tooltip_text, "' min=", button.get_combined_minimum_size())
	_check(saw_add and saw_header_collapse,
		"the target walker covers the outliner header controls")
	_check(short == 0, "every visible outliner button keeps a 44x44 target (short=%d)" % short)
	await _free_doc(doc)


## The stage has to point at the selected part even when that part draws no
## geometry. Only an effectively hidden part may suppress the feedback.
func _test_stage_feedback() -> void:
	print("HIERARCHY STEP: stage selection feedback")
	var doc: Variant = await _new_doc("Feedback")
	var id: String = await _import(doc)
	if id == "":
		await _free_doc(doc)
		return
	var view: Variant = await _new_view(doc)
	_check(view.has_method("selection_feedback"),
		"the stage exposes its selection feedback")
	if not view.has_method("selection_feedback"):
		view.get_parent().queue_free()
		await get_tree().process_frame
		return
	# A geometry part draws its AABB box.
	doc.set_selected_part(id, HEAD)
	var feedback: Dictionary = view.selection_feedback()
	var head: Node3D = doc.get_import_part_node(id, HEAD)
	var expected: AABB = head.global_transform * head.get_aabb()
	_check(feedback.has("aabb") and not feedback.has("dot"),
		"a selected mesh part reports its world AABB")
	_check(_aabb_close(feedback.get("aabb", AABB()), expected),
		"the mesh part feedback AABB matches the part")
	# KeyLight, Cam and the skeleton all select but draw nothing; the 15 px
	# dot must stay for each of them.
	for pair in [[LIGHT, "light"], [CAMERA, "camera"], [SKELETON, "skeleton"]]:
		doc.set_selected_part(id, str(pair[0]))
		var part: Node3D = doc.get_import_part_node(id, str(pair[0]))
		feedback = view.selection_feedback()
		_check(feedback.has("dot") and not feedback.has("aabb"),
			"a visible %s part falls back to the 15 px dot" % str(pair[1]))
		var dot: Vector3 = feedback.get("dot", Vector3.ZERO)
		_check(dot.distance_to(part.global_position) < EPS,
			"the %s dot sits on the part's world position" % str(pair[1]))
	# The fixture's Empty owns ChildMesh, so its subtree has geometry and draws
	# a box. Hide that only mesh: the still-visible Empty is now geometry-less
	# and must fall back to the dot rather than look unselected.
	doc.set_selected_part(id, EMPTY)
	_check(view.selection_feedback().has("aabb"),
		"an empty part with visible child geometry reports the subtree AABB")
	doc.set_import_part_visible(id, CHILD_MESH, false)
	doc.set_selected_part(id, EMPTY)
	feedback = view.selection_feedback()
	var empty_part: Node3D = doc.get_import_part_node(id, EMPTY)
	_check(feedback.has("dot") and not feedback.has("aabb"),
		"a visible geometry-less empty part falls back to the 15 px dot")
	var empty_dot: Vector3 = feedback.get("dot", Vector3.ZERO)
	_check(empty_dot.distance_to(empty_part.global_position) < EPS,
		"the empty part dot sits on its world position")
	doc.set_import_part_visible(id, CHILD_MESH, true)
	# A hidden part draws nothing.
	doc.set_import_part_visible(id, LIGHT, false)
	doc.set_selected_part(id, LIGHT)
	_check(view.selection_feedback().is_empty(),
		"a hidden selected part reports no stage feedback")
	# An ancestor hiding the part is the same as hiding the part itself.
	doc.set_import_part_visible(id, LIGHT, true)
	doc.set_import_part_visible(id, BODY, false)
	doc.set_selected_part(id, HEAD)
	_check(view.selection_feedback().is_empty(),
		"a part hidden by an ancestor draws nothing")
	doc.set_import_part_visible(id, BODY, true)
	# Root objects keep the existing zero-size fallback.
	var empty_id: String = doc.add_empty(Vector3(0.0, 0.4, 0.0))
	var empty_node: Node3D = doc.nodes.get(empty_id)
	var root_feedback: Dictionary = view.selection_feedback()
	_check(root_feedback.has("dot") and not root_feedback.has("aabb"),
		"a selected zero-size root keeps the dot fallback")
	var root_dot: Vector3 = root_feedback.get("dot", Vector3.ZERO)
	_check(root_dot.distance_to(empty_node.global_position) < EPS,
		"the root dot sits on the object's world position")
	doc.set_object_visible(empty_id, false)
	_check(view.selection_feedback().is_empty(),
		"a hidden root draws nothing")
	var cube_id: String = doc.add_primitive("cube")
	_check(cube_id != "", "the mesh root spawns")
	_check(view.selection_feedback().has("aabb"),
		"a selected mesh root keeps its AABB box")
	view.get_parent().queue_free()
	await get_tree().process_frame
