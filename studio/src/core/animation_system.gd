extends RefCounted
## Multi-clip animation subsystem contract.
##
## The contract commit installs this legacy bridge so the existing single-clip
## document keeps working while the workstreams are isolated. WS-A replaces the
## bridge with the real clip/layer/strip model; the public signatures below are
## the binding interface for the clip lane, mixer and glTF import.
##
## Ownership: `Document` creates one instance in `_init()` and never frees it
## during `_clear_runtime()`; `reset()` clears subsystem state instead.

var _document = null

func setup(document) -> void:
	_document = document

func reset() -> void:
	pass

func ensure_default_clip() -> void:
	## WS-A: adopt `document.animation` when no clip exists, otherwise create a
	## new Animation and make it active.
	pass

func to_data() -> Dictionary:
	## WS-A: serialize {"clips": [...], "layers": [...]}.
	return {"clips": [], "layers": []}

func load_data(_data: Dictionary, _nodes: Dictionary) -> void:
	## WS-A: migrate v1 `animation` or load v2 clips/layers. The document has
	## already loaded the legacy animation tracks before this call.
	pass

func advance(_delta: float) -> void:
	## WS-A: advance sequence time, evaluate the mixer, apply object/bone poses.
	pass

func create_clip(_name: String, _duration: float) -> String:
	return ""

func duplicate_clip(_id: String) -> String:
	return ""

func delete_clip(_id: String) -> bool:
	return false

func rename_clip(_id: String, _name: String) -> void:
	pass

func clip_ids() -> PackedStringArray:
	return PackedStringArray()

func get_clip(_id: String) -> Dictionary:
	return {}

func animation_for(_id: String) -> Animation:
	return null

func active_animation() -> Animation:
	if _document != null:
		return _document.animation
	return null

func set_active_clip(_id: String) -> void:
	pass

func active_clip_id() -> String:
	return ""

func add_layer(_name: String) -> String:
	return "layer_base"

func delete_layer(_id: String) -> bool:
	return false

func layers() -> Array:
	return [{
		"id": "layer_base",
		"name": "Base",
		"weight": 1.0,
		"blend": "override",
		"muted": false,
		"solo": false,
		"strips": [],
	}]

func add_strip(_layer_id: String, _clip_id: String, _start: float) -> String:
	return ""

func update_strip(_strip_id: String, _patch: Dictionary) -> void:
	pass

func delete_strip(_strip_id: String) -> void:
	pass

func sequence_duration() -> float:
	if _document == null:
		return 0.04
	return maxf(0.04, float(_document.duration))

func evaluate(_time: float) -> Dictionary:
	return {}

func strip_at(_time: float) -> Dictionary:
	return {}

func local_time(_strip: Dictionary, time: float) -> float:
	return time

func sequence_time() -> float:
	if _document == null:
		return 0.0
	return float(_document.current_time)

func active_local_time() -> float:
	if _document == null:
		return 0.0
	return float(_document.current_time)

func is_sequence_playing() -> bool:
	return false

func seek_sequence(_time: float) -> void:
	pass

func play_sequence() -> void:
	pass

func pause_sequence() -> void:
	pass

func stop_sequence() -> void:
	pass

func import_gltf_animations(_object_id: String, _node: Node) -> PackedStringArray:
	return PackedStringArray()

func on_imported_scene(_object_id: String, _node: Node) -> void:
	pass
