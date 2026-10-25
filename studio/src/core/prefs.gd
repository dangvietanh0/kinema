extends Node
## Persistent, validated user settings.
##
## Every key has a typed default. Values are clamped on read, so a hand-edited
## or corrupted file can never push the editor into an unrenderable state.
## Writes are atomic: the new document is written to `<path>.tmp` and renamed
## over the old one, and a file that fails to parse is moved aside as `.bak`
## so the user's settings are never silently destroyed.

signal changed(key: String, value: Variant)

const DEFAULTS := {
	"display.layout": "auto",
	"display.orientation": "auto",
	"display.user_scale": 1.0,
	"display.safe_area_preview": false,
	"display.keep_screen_on": true,
	"display.fullscreen": false,
	"editor.autosave_seconds": 30,
	"editor.confirm_delete": true,
	"editor.gizmo_size": 1.0,
	"editor.translate_snap": 0.25,
	"editor.rotate_snap": 15.0,
	"editor.scale_snap": 0.25,
	"editor.default_interpolation": "cubic",
	"editor.timeline_default": "dope",
	"editor.show_fps": true,
	"editor.reduce_motion": false,
	"editor.haptics": false,
	"editor.collapsed_sections": [],
	"editor.project_sort": "recent",
	"performance.overlay": "compact",
	"performance.frame_graph": false,
	"performance.adaptive_quality": true,
	"performance.target_fps": 60,
	"performance.min_preview_scale": 0.6,
	"performance.preview_update": "on_demand",
	"performance.preview_cap": 1920,
	"performance.max_fps": 60,
	"performance.vsync": true,
	"render.mode": "still",
	"render.resolution": 1920,
	"render.msaa": 2,
	"render.transparent": false,
	"render.start_frame": 0,
	"render.end_frame": -1,
	"render.output_dir": "user://renders",
	"import.scale": 1.0,
	"import.materials": true,
	"import.textures": true,
}

const ENUMS := {
	"display.layout": ["auto", "compact", "studio", "desktop"],
	"display.orientation": ["auto", "portrait", "landscape"],
	"editor.default_interpolation": ["linear", "cubic"],
	"editor.timeline_default": ["dope", "graph"],
	"editor.project_sort": ["recent", "name"],
	"performance.overlay": ["off", "compact", "full"],
	"performance.preview_update": ["on_demand", "always"],
	"render.mode": ["still", "sequence", "preview"],
}

const RANGES := {
	"display.user_scale": Vector2(0.85, 1.30),
	"editor.autosave_seconds": Vector2(0, 600),
	"editor.gizmo_size": Vector2(0.5, 2.0),
	"editor.translate_snap": Vector2(0.01, 10.0),
	"editor.rotate_snap": Vector2(1.0, 90.0),
	"editor.scale_snap": Vector2(0.01, 1.0),
	"performance.target_fps": Vector2(15, 240),
	"performance.min_preview_scale": Vector2(0.25, 1.0),
	"performance.preview_cap": Vector2(480, 7680),
	"performance.max_fps": Vector2(15, 240),
	"render.resolution": Vector2(480, 7680),
	"render.msaa": Vector2(0, 4),
	"render.start_frame": Vector2(0, 1000000),
	"render.end_frame": Vector2(-1, 1000000),
	"import.scale": Vector2(0.001, 1000.0),
}

var settings_path := "user://settings.json"
var last_error := ""
var _values: Dictionary = {}
var _loaded := false


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	_values = DEFAULTS.duplicate(true)
	last_error = ""
	_loaded = true
	if not FileAccess.file_exists(settings_path):
		return
	var file := FileAccess.open(settings_path, FileAccess.READ)
	if file == null:
		last_error = "Settings could not be read. Defaults are in use."
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		last_error = "Settings were damaged and have been reset."
		_backup_bad_file()
		return
	for raw_key in parsed.keys():
		var key := str(raw_key)
		if DEFAULTS.has(key):
			_values[key] = _coerce(key, parsed[raw_key])


func save_settings() -> bool:
	last_error = ""
	var tmp := settings_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		last_error = "Settings could not be saved."
		return false
	file.store_string(JSON.stringify(_values, "\t"))
	file.close()
	DirAccess.remove_absolute(settings_path)
	var err := DirAccess.rename_absolute(tmp, settings_path)
	if err != OK:
		last_error = "Settings could not be saved."
		return false
	return true


func get_value(key: String, default: Variant = null) -> Variant:
	if not _loaded:
		load_settings()
	var fallback: Variant = DEFAULTS[key] if DEFAULTS.has(key) else default
	if not _values.has(key):
		return _duplicate_default(fallback)
	return _values[key]


func set_value(key: String, value: Variant, save: bool = true) -> void:
	if not _loaded:
		load_settings()
	if not DEFAULTS.has(key):
		return
	var coerced: Variant = _coerce(key, value)
	if _values.has(key) and _values[key] == coerced and typeof(_values[key]) == typeof(coerced):
		return
	_values[key] = coerced
	if save:
		save_settings()
	changed.emit(key, coerced)


func reset_section(section: String) -> void:
	for key in DEFAULTS.keys():
		if not str(key).begins_with(section + "."):
			continue
		_values[key] = _duplicate_default(DEFAULTS[key])
		changed.emit(key, _values[key])
	save_settings()


func reset_all() -> void:
	_values = DEFAULTS.duplicate(true)
	for key in DEFAULTS.keys():
		changed.emit(key, _values[key])
	save_settings()


func keys() -> Array:
	return DEFAULTS.keys()


func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)


func _coerce(key: String, value: Variant) -> Variant:
	var default: Variant = DEFAULTS[key]
	match typeof(default):
		TYPE_BOOL:
			if value is bool:
				return value
			if value is float or value is int:
				return absf(float(value)) > 0.0001
			return default
		TYPE_INT:
			var number := 0
			if value is float or value is int:
				number = int(round(float(value)))
			elif value is String and (value as String).is_valid_int():
				number = (value as String).to_int()
			else:
				number = int(default)
			if RANGES.has(key):
				var range_value: Vector2 = RANGES[key]
				number = clampi(number, int(range_value.x), int(range_value.y))
			if ENUMS.has(key):
				return number
			return number
		TYPE_FLOAT:
			var number := 0.0
			if value is float or value is int:
				number = float(value)
			elif value is String and (value as String).is_valid_float():
				number = (value as String).to_float()
			else:
				number = float(default)
			if RANGES.has(key):
				var range_value: Vector2 = RANGES[key]
				number = clampf(number, range_value.x, range_value.y)
			return number
		TYPE_STRING:
			var text := str(value) if value != null else str(default)
			if ENUMS.has(key):
				var allowed: Array = ENUMS[key]
				return text if text in allowed else str(default)
			return text
		TYPE_ARRAY:
			if value is Array:
				var out: Array = []
				for item in value:
					out.append(str(item))
				return out
			return _duplicate_default(default)
	return _duplicate_default(default)


func _duplicate_default(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return value


func _backup_bad_file() -> void:
	if not FileAccess.file_exists(settings_path):
		return
	DirAccess.remove_absolute(settings_path + ".bak")
	DirAccess.rename_absolute(settings_path, settings_path + ".bak")
