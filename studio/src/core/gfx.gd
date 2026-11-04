extends Node
## Graphics and performance preferences.
##
## Every value here maps to a real Godot rendering API. Nothing is decorative:
## environment features go through Environment, viewport features through
## Viewport, shadow and scaling through RenderingServer. Options that the
## current renderer cannot honour are reported as unavailable and are never
## silently pretended to work.

signal changed

const PATH := "user://graphics.json"
const STUDIO_SKY = preload("res://src/viewport/studio_sky.gdshader")

const PRESETS := {
	"performance": {
		"msaa": 0,
		"taa": false,
		"ssao": false,
		"ssil": false,
		"ssr": false,
		"glow": false,
		"volumetric_fog": false,
		"shadow_quality": 1,
		"shadow_distance": 28.0,
		"shadow_splits": 1,
		"scale_3d": 0.8,
	},
	"balanced": {
		"msaa": 1,
		"taa": false,
		"ssao": true,
		"ssil": false,
		"ssr": false,
		"glow": true,
		"volumetric_fog": false,
		"shadow_quality": 2,
		"shadow_distance": 40.0,
		"shadow_splits": 2,
		"scale_3d": 1.0,
	},
	"quality": {
		"msaa": 2,
		"taa": true,
		"ssao": true,
		"ssil": true,
		"ssr": false,
		"glow": true,
		"volumetric_fog": false,
		"shadow_quality": 3,
		"shadow_distance": 60.0,
		"shadow_splits": 4,
		"scale_3d": 1.0,
	},
}

var preset := "balanced"
var msaa := 1
var taa := false
var ssao := true
var ssao_quality := 2
var ssil := false
var ssr := false
var glow := true
var tonemap := 3
var exposure := 1.0
var shadow_quality := 2
var shadow_distance := 40.0
var shadow_splits := 2
var volumetric_fog := false
var scale_3d := 1.0
var max_fps := 60
# Draft quality keeps the editor responsive while the camera, gizmo or
# playback is moving. It is a preference, not a preset value: turning it off
# should not mark the graphics preset as custom.
var draft_editing := true
## Last renderer the user asked for. Godot chooses the renderer when the
## process starts, so this is a request for the next launch, not a live switch.
var renderer_preference := ""
## A requested renderer that has not been confirmed by the running engine yet.
var renderer_pending := ""
var renderer_attempt_at := 0.0
var renderer_attempts := 0
## True only after a launch reached the editor with the requested backend. A
## pending switch that never gets here counts as a failed boot on the next
## launch; Android Forward+ falls back after one failure instead of retrying.
var renderer_ready := false
var last_renderer_error := ""
## Explicit opt-in to the full Forward+ feature set on Android/iOS. Enabling
## it writes a probe before the high-end profile applies; a launch that never
## reaches the editor reverts to the mobile-safe clamps on the next start.
var risk_enabled := false
var risk_boot := "idle"
var risk_last_error := ""
## Legacy mirror for callers written before the preference split.
var renderer_choice := ""
var _restart_request := PackedStringArray()

const MSAA_MODES := [
	Viewport.MSAA_DISABLED,
	Viewport.MSAA_2X,
	Viewport.MSAA_4X,
	Viewport.MSAA_8X,
]
const SHADOW_ATLAS := [1024, 2048, 4096, 4096]
const TONEMAPS := [
	Environment.TONE_MAPPER_LINEAR,
	Environment.TONE_MAPPER_REINHARDT,
	Environment.TONE_MAPPER_FILMIC,
	Environment.TONE_MAPPER_ACES,
]

func _ready() -> void:
	load_preferences()
	# A preference written by an older build can name a renderer the platform
	# cannot serve (a stale Forward+ on Android, for instance). Repair it before
	# anything reads it so the process can never relaunch into a crashing
	# backend through a stored preference.
	var clean := sanitize_renderer_state(renderer_preference, renderer_pending, OS.get_name())
	if bool(clean.get("changed", false)):
		renderer_preference = str(clean.get("preference", renderer_preference))
		renderer_pending = str(clean.get("pending", ""))
		renderer_choice = renderer_preference
		save_preferences()
		last_renderer_error = str(clean.get("reason", ""))
	else:
		last_renderer_error = ""
	if renderer_preference == "":
		# An unset preference is not an error: adopt and persist the platform
		# default without writing a bogus "unsupported renderer" reason.
		renderer_preference = renderer_default_for_platform(OS.get_name())
		renderer_choice = renderer_preference
		save_preferences()
	renderer_choice = renderer_preference
	# Resolve the risk probe before any profile is applied. A stored "probing"
	# means the previous launch never reached the editor and must never apply
	# the high-end profile again.
	var risk_decision := begin_risk_boot(OS.get_name(), actual_method())
	risk_enabled = bool(risk_decision.get("risk_enabled", risk_enabled))
	risk_boot = str(risk_decision.get("boot", risk_boot))
	var risk_reason := str(risk_decision.get("reason", ""))
	if risk_reason != "":
		risk_last_error = risk_reason
	if str(risk_decision.get("action", "none")) != "none":
		save_preferences()
	apply_globals()

# -------------------------------------------------------------------------
# Capability checks
# -------------------------------------------------------------------------

func renderer_name() -> String:
	return str(RenderingServer.get_current_rendering_method())

func display_name() -> String:
	match renderer_name():
		"forward_plus":
			return "Forward+ / Vulkan"
		"mobile":
			return "Mobile / Vulkan"
		"gl_compatibility":
			return "Compatibility / OpenGL"
	return renderer_name()

func is_forward() -> bool:
	return renderer_name() == "forward_plus"

func supports_environment_extras() -> bool:
	return is_forward()

# -------------------------------------------------------------------------
# Platform capability gate
# -------------------------------------------------------------------------
## The single source of truth for which renderers a platform may launch. The
## engine selects a rendering method at process start, so a request the platform
## cannot serve must never reach a restart: the choice is refused before any
## `--rendering-method` argument is built.

func supported_renderers(platform: String) -> Array[String]:
	var target := platform if platform != "" else OS.get_name()
	if target == "Android" or target == "iOS":
		# Forward+ is restored as an experimental mobile backend. The engine
		# still picks it at process start; the mobile-safe profile below keeps
		# its high-end features inside what a phone can sustain.
		return ["forward_plus", "mobile", "gl_compatibility"]
	return ["forward_plus", "mobile", "gl_compatibility"]


func is_renderer_supported(method: String, platform: String) -> bool:
	return supported_renderers(platform).has(method)


func renderer_unavailable_reason(method: String, platform: String) -> String:
	var resolved := platform if platform != "" else OS.get_name()
	if is_renderer_supported(method, resolved):
		return ""
	return "The %s renderer is not supported on this platform." % method


func renderer_entries(platform: String) -> Array:
	var resolved := platform if platform != "" else OS.get_name()
	var mobile := resolved == "Android" or resolved == "iOS"
	var entries: Array = []
	for value in ["forward_plus", "mobile", "gl_compatibility"]:
		var method := str(value)
		var experimental: bool = mobile and method == "forward_plus"
		var note := ""
		if experimental:
			note = "Experimental on %s: high-end Forward+ effects are clamped for stability." % resolved
		entries.append({
			"label": "Forward+ (Experimental)" if experimental else renderer_label(method),
			"value": method,
			"supported": is_renderer_supported(method, resolved),
			"reason": renderer_unavailable_reason(method, resolved),
			"experimental": experimental,
			"note": note,
		})
	return entries

# -------------------------------------------------------------------------
# Renderer selection
# -------------------------------------------------------------------------
## Godot selects a rendering method at process start. These helpers keep the
## request, the pending state and the running backend honest; nothing here
## pretends a live renderer switch is possible.

func actual_method() -> String:
	return renderer_name()


# -------------------------------------------------------------------------
# Renderer risk
# -------------------------------------------------------------------------
## High-end Forward+ effects are an explicit, persisted opt-in on Android/iOS.
## The probe only arms when the running backend is Forward+; enabling the
## switch under Mobile is allowed and takes effect the next time Forward+ runs.

func risk_supported(platform: String = OS.get_name()) -> bool:
	var resolved := platform if platform != "" else OS.get_name()
	return resolved == "Android" or resolved == "iOS"


func risk_active(platform: String = OS.get_name(), method: String = actual_method()) -> bool:
	return risk_enabled and risk_supported(platform) and method == "forward_plus"


## Pure boot decision. The caller applies the returned fields and saves only
## when the action is not "none". `preference` is the stored renderer request,
## unchanged by the risk decision.
func begin_risk_boot(platform: String, method: String) -> Dictionary:
	var resolved := platform if platform != "" else OS.get_name()
	var boot := "idle"
	var enabled := risk_enabled
	var action := "none"
	var reason := ""
	if risk_boot == "probing":
		if risk_enabled:
			action = "revert"
			enabled = false
			reason = "High-end Forward+ effects were reverted because the previous launch did not reach the editor."
		else:
			action = "clear"
	elif risk_enabled and risk_supported(resolved) and method == "forward_plus":
		action = "probe"
		boot = "probing"
	return {
		"action": action,
		"preference": renderer_preference,
		"boot": boot,
		"risk_enabled": enabled,
		"reason": reason,
	}


## Turn the high-end profile on. The probe is written before apply_all() so a
## crash during the first high-end frame is caught by the next launch.
func enable_risk(platform: String = OS.get_name(), method: String = actual_method()) -> bool:
	if not risk_supported(platform):
		return false
	risk_enabled = true
	risk_last_error = ""
	risk_boot = "probing" if risk_supported(platform) and method == "forward_plus" else "idle"
	save_preferences()
	if platform == OS.get_name() and method == actual_method():
		apply_all()
	return true


func disable_risk() -> void:
	risk_enabled = false
	risk_boot = "idle"
	save_preferences()
	apply_all()


func confirm_risk_probe() -> void:
	if risk_boot == "probing":
		risk_boot = "proven"
		save_preferences()


func renderer_default_for_platform(platform: String) -> String:
	return "mobile" if platform == "Android" or platform == "iOS" else "forward_plus"

func build_restart_args(preference: String, platform: String = OS.get_name()) -> PackedStringArray:
	var resolved := platform if platform != "" else OS.get_name()
	if preference == "auto" or preference == "" or not is_renderer_supported(preference, resolved):
		# Refuse before building: an unsupported backend never gets a restart arg.
		return PackedStringArray()
	var driver := "opengl3" if preference == "gl_compatibility" else "vulkan"
	return PackedStringArray(["--rendering-method", preference, "--rendering-driver", driver])

## Pure capability matrix. A method only claims a feature the engine can
## actually provide with that backend. Forward+ on Android/iOS keeps its look
## but runs a mobile-safe profile: high-end effects are clamped instead of
## pretending the phone can sustain them.
func capabilities_for(method: String, platform: String = OS.get_name()) -> Dictionary:
	var resolved := platform if platform != "" else OS.get_name()
	var mobile := resolved == "Android" or resolved == "iOS"
	var forward := method == "forward_plus"
	var compatibility := method == "gl_compatibility"
	return {
		"ssao": not compatibility,
		"ssao_quality": not compatibility,
		"ssil": forward and not mobile,
		"ssr": forward and not mobile,
		"taa": forward and not mobile,
		"volumetric_fog": forward and not mobile,
		"glow": true,
		"mobile_safe": mobile,
		"msaa_cap": 1 if mobile else 3,
		"scale_3d_cap": 0.85 if mobile else 1.0,
		"shadow_quality_cap": 2 if mobile else 3,
		"max_fps_cap": 60 if mobile else 0,
	}

## The effective values for the running backend. On Android/iOS Forward+ the
## stored preference may stay high, but every applied value is clamped so a
## desktop-quality preset cannot disable the phone in one launch.
func safe_forward_plus_profile(platform: String = OS.get_name(), actual_method: String = renderer_name()) -> Dictionary:
	var resolved := platform if platform != "" else OS.get_name()
	var profile := {
		"msaa": msaa,
		"taa": taa,
		"ssao": ssao,
		"ssil": ssil,
		"ssr": ssr,
		"glow": glow,
		"volumetric_fog": volumetric_fog,
		"shadow_quality": shadow_quality,
		"shadow_distance": shadow_distance,
		"shadow_splits": shadow_splits,
		"scale_3d": scale_3d,
		"max_fps": max_fps,
	}
	if actual_method == "forward_plus" and (resolved == "Android" or resolved == "iOS"):
		profile["taa"] = false
		profile["ssil"] = false
		profile["ssr"] = false
		profile["volumetric_fog"] = false
		profile["msaa"] = mini(int(profile["msaa"]), 1)
		profile["scale_3d"] = minf(float(profile["scale_3d"]), 0.85)
		profile["shadow_quality"] = mini(int(profile["shadow_quality"]), 2)
		profile["shadow_distance"] = minf(float(profile["shadow_distance"]), 40.0)
		profile["shadow_splits"] = mini(int(profile["shadow_splits"]), 2)
		profile["max_fps"] = clampi(int(profile["max_fps"]), 1, 60)
	return profile

func sanitize_renderer_state(preference: String, pending: String, platform: String) -> Dictionary:
	var resolved := platform if platform != "" else OS.get_name()
	var default_method := renderer_default_for_platform(resolved)
	var safe_preference := preference
	var safe_pending := pending
	var changed := false
	var reason := ""
	if safe_preference == "":
		# An empty preference is unset, not unsupported: adopt the platform
		# default silently so first run never shows a bogus error.
		safe_preference = default_method
	elif not is_renderer_supported(safe_preference, resolved):
		safe_preference = default_method
		changed = true
		reason = "Unsupported renderer '%s' on %s. The platform default '%s' is being used." % [str(preference), resolved, default_method]
	if pending != "" and not is_renderer_supported(pending, resolved):
		safe_pending = ""
		changed = true
		if reason == "":
			reason = "Pending renderer '%s' on %s is unsupported and was cleared. The platform default '%s' is being used." % [str(pending), resolved, default_method]
	return {
		"preference": safe_preference,
		"pending": safe_pending,
		"changed": changed,
		"reason": reason,
	}


func prepare_renderer_switch(preference: String, platform: String = OS.get_name()) -> Dictionary:
	var resolved := platform if platform != "" else OS.get_name()
	var usable := preference == "auto" or is_renderer_supported(preference, resolved)
	if not usable:
		# M1: refuse before anything is stored. A blocked switch leaves every
		# stored field exactly as it was and never writes the preference file.
		return {
			"restart_required": false,
			"blocked": true,
			"reason": renderer_unavailable_reason(preference, resolved),
			"preference": renderer_preference,
			"args": PackedStringArray(),
		}
	var target := preference if preference != "auto" else renderer_default_for_platform(resolved)
	renderer_preference = target
	renderer_choice = target
	renderer_pending = ""
	renderer_attempts = 0
	renderer_attempt_at = 0.0
	# A simulated platform (tests) cannot be compared with the live backend:
	# the same method on another platform is still a real restart request.
	if target == actual_method() and resolved == OS.get_name():
		_restart_request = PackedStringArray()
		save_preferences()
		return {
			"restart_required": false,
			"blocked": false,
			"preference": target,
			"args": PackedStringArray(),
			"actual": actual_method(),
		}
	renderer_pending = target
	renderer_attempt_at = Time.get_unix_time_from_system()
	# The next launch has not proven this backend yet. If the editor never
	# appears, the one-failed-boot rule catches it on the following launch.
	renderer_ready = false
	var args := build_restart_args(target, resolved)
	_restart_request = args
	save_preferences()
	return {
		"restart_required": true,
		"blocked": false,
		"preference": target,
		"args": args,
		"actual": actual_method(),
	}

## Pure startup resolution. A request is retried at most twice; after that the
## platform default wins and the UI reports why. `attempts` is the number of
## restarts already issued for this pending request. `ready` is false when the
## previous launch never reached the editor; Android/iOS Forward+ falls back
## after that single failure instead of being retried into.
func resolve_startup_renderer(preference: String, pending: String, actual: String,
		attempts: int, platform: String, ready: bool = true) -> Dictionary:
	var resolved := platform if platform != "" else OS.get_name()
	var fallback := renderer_default_for_platform(resolved)
	var mobile := resolved == "Android" or resolved == "iOS"
	if pending == "forward_plus" and mobile and not ready and pending != actual:
		# One failed Android/iOS Forward+ boot is enough. Do not retry into a
		# backend that did not reach the editor.
		return {
			"action": "fallback",
			"preference": fallback,
			"pending": "",
			"args": build_restart_args(fallback, resolved) if fallback != actual else PackedStringArray(),
			"reason": "Forward+ did not reach the editor on the previous launch. The platform default renderer is active.",
		}
	if pending != "" and not is_renderer_supported(pending, resolved):
		# A stale or unsupported pending is never retried into: fall back to the
		# platform default immediately, with restart args only if that default
		# differs from the backend that is actually running.
		return {
			"action": "fallback",
			"preference": fallback,
			"pending": "",
			"args": build_restart_args(fallback, resolved) if fallback != actual else PackedStringArray(),
			"reason": "Pending renderer '%s' is unsupported on %s. The platform default is active." % [pending, resolved],
		}
	var clean := sanitize_renderer_state(preference, pending, resolved)
	var safe_preference: String = str(clean.get("preference", preference))
	var safe_pending: String = str(clean.get("pending", ""))
	if safe_pending == "":
		return {"action": "none", "preference": safe_preference, "pending": "", "args": PackedStringArray(), "reason": ""}
	if safe_pending == actual:
		# The requested backend is running, but it is not proven until the
		# editor's 3D viewport has drawn. Keep the request so a crash before
		# that frame still counts as the one failed attempt next launch.
		return {"action": "none", "preference": safe_preference, "pending": safe_pending, "args": PackedStringArray(), "reason": ""}
	if attempts < 2:
		return {
			"action": "restart",
			"preference": safe_pending,
			"pending": safe_pending,
			"args": build_restart_args(safe_pending, resolved),
			"reason": "",
		}
	return {
		"action": "fallback",
		"preference": fallback,
		"pending": "",
		"args": build_restart_args(fallback, resolved) if fallback != actual else PackedStringArray(),
		"reason": "The selected renderer was not accepted after two restarts. The platform default renderer is active.",
	}

func ensure_renderer() -> Dictionary:
	if renderer_pending == "":
		return {"action": "none", "preference": renderer_preference, "pending": "", "args": PackedStringArray()}
	var request := renderer_pending
	var now := Time.get_unix_time_from_system()
	# A stale pending request is not retried forever. If the first attempt is
	# older than the verification window, treat it as failed.
	if renderer_attempt_at > 0.0 and now - renderer_attempt_at > 60.0:
		renderer_attempts = 2
	var result := resolve_startup_renderer(
		renderer_preference, renderer_pending, actual_method(), renderer_attempts,
		OS.get_name(), renderer_ready
	)
	match str(result.get("action", "none")):
		"none":
			if renderer_pending != "" and not renderer_ready \
					and renderer_pending == actual_method():
				# The requested backend is running but the editor has not drawn
				# its first 3D frame yet. Keep the pending request and the
				# attempt bookkeeping; mark_renderer_ready() clears them after
				# that frame, and a crash before it fails over next launch.
				_restart_request = PackedStringArray()
				last_renderer_error = ""
			else:
				renderer_pending = ""
				renderer_attempts = 0
				renderer_attempt_at = 0.0
				_restart_request = PackedStringArray()
				last_renderer_error = ""
		"restart":
			renderer_attempts += 1
			renderer_attempt_at = now
			_restart_request = result.get("args", PackedStringArray())
			last_renderer_error = ""
		"fallback":
			renderer_preference = str(result.get("preference", renderer_default_for_platform(OS.get_name())))
			renderer_choice = renderer_preference
			renderer_pending = ""
			renderer_attempts = 0
			renderer_attempt_at = 0.0
			_restart_request = PackedStringArray()
			if request == "forward_plus":
				last_renderer_error = "Forward+ did not reach the editor on the previous launch. The platform default renderer is active."
			else:
				last_renderer_error = "The selected renderer was not accepted after two restarts. The platform default is active."
	save_preferences()
	return result

## Called by the shell once startup resolution is done and this launch reached
## the editor. Never called before resolution and never on the restart path.
func mark_renderer_ready() -> void:
	renderer_ready = true
	if risk_boot == "probing":
		risk_boot = "proven"
	if renderer_pending != "" and renderer_pending == actual_method():
		renderer_pending = ""
		renderer_attempts = 0
		renderer_attempt_at = 0.0
		_restart_request = PackedStringArray()
	save_preferences()

## The renderer the project actually requests for this feature set. Both
## renderer surfaces use this so the mobile override is never ignored.
func project_renderer_request(features := PackedStringArray()) -> String:
	var setting := "rendering/renderer/rendering_method"
	if features.is_empty():
		return str(ProjectSettings.get_setting_with_override(setting))
	return str(ProjectSettings.get_setting_with_override_and_custom_features(setting, features))

func consume_restart_request() -> PackedStringArray:
	var args := _restart_request
	_restart_request = PackedStringArray()
	return args

# -------------------------------------------------------------------------
# Apply
# -------------------------------------------------------------------------

func apply_globals() -> void:
	var profile := safe_forward_plus_profile()
	var quality := int(profile["shadow_quality"])
	Engine.max_fps = int(profile["max_fps"])
	RenderingServer.directional_soft_shadow_filter_set_quality(quality)
	RenderingServer.positional_soft_shadow_filter_set_quality(quality)
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS[clampi(quality, 0, 3)], false)

func apply_viewport(viewport: Viewport) -> void:
	if viewport == null:
		return
	var profile := safe_forward_plus_profile()
	viewport.msaa_3d = MSAA_MODES[clampi(int(profile["msaa"]), 0, 3)]
	viewport.scaling_3d_scale = clampf(float(profile["scale_3d"]), 0.5, 1.0)
	viewport.use_taa = bool(profile["taa"]) and is_forward()

func apply_environment(env: Environment) -> void:
	if env == null:
		return
	var forward := is_forward()
	var profile := safe_forward_plus_profile()
	env.tonemap_mode = TONEMAPS[clampi(tonemap, 0, 3)]
	env.tonemap_exposure = exposure
	env.ssao_enabled = bool(profile["ssao"]) and forward
	# SSAO quality is not an Environment property: in Godot 4.7 it lives on
	# RenderingServer as a global quality override (very low..ultra).
	if forward:
		# adaptive_target is a 0..1 rate: 1.0 asks for the highest quality the
		# selected preset can sustain, rather than a frame budget.
		RenderingServer.environment_set_ssao_quality(
			clampi(ssao_quality + 1, 1, 4), false, 1.0, 2, 0.0, 0.0
		)
	env.ssil_enabled = bool(profile["ssil"]) and forward
	env.ssr_enabled = bool(profile["ssr"]) and forward
	env.glow_enabled = bool(profile["glow"])
	env.volumetric_fog_enabled = bool(profile["volumetric_fog"]) and forward

func apply_all() -> void:
	apply_globals()
	for view in get_tree().get_nodes_in_group("kinema_viewport"):
		if view is SubViewport:
			apply_viewport(view)
	for env_node in get_tree().get_nodes_in_group("kinema_environment"):
		if env_node is WorldEnvironment and env_node.environment != null:
			apply_environment(env_node.environment)
	changed.emit()

func apply_preset(name: String) -> void:
	if not PRESETS.has(name):
		return
	preset = name
	var values: Dictionary = PRESETS[name]
	for key in values.keys():
		set(key, values[key])
	if name == "quality":
		ssao_quality = 3
	elif name == "balanced":
		ssao_quality = 2
	else:
		ssao_quality = 1
	save_preferences()
	apply_all()

func mark_custom() -> void:
	preset = "custom"

# -------------------------------------------------------------------------
# Persistence
# -------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"preset": preset,
		"msaa": msaa,
		"taa": taa,
		"ssao": ssao,
		"ssao_quality": ssao_quality,
		"ssil": ssil,
		"ssr": ssr,
		"glow": glow,
		"tonemap": tonemap,
		"exposure": exposure,
		"shadow_quality": shadow_quality,
		"shadow_distance": shadow_distance,
		"shadow_splits": shadow_splits,
		"volumetric_fog": volumetric_fog,
		"scale_3d": scale_3d,
		"max_fps": max_fps,
		"draft_editing": draft_editing,
		"renderer_preference": renderer_preference,
		"renderer_pending": renderer_pending,
		"renderer_attempt_at": renderer_attempt_at,
		"renderer_attempts": renderer_attempts,
		"renderer_ready": renderer_ready,
		"renderer_choice": renderer_preference,
		"risk_enabled": risk_enabled,
		"risk_boot": risk_boot,
		"risk_last_error": risk_last_error,
	}

func load_preferences() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	var raw := parsed as Dictionary
	for key in to_dict().keys():
		if raw.has(key):
			set(key, raw[key])
	preset = str(raw.get("preset", preset))
	if raw.has("renderer_preference"):
		renderer_preference = str(raw["renderer_preference"])
	elif raw.has("renderer_choice"):
		renderer_preference = str(raw["renderer_choice"])
	renderer_choice = renderer_preference
	# Missing keys keep the safe defaults; a value written by a future build
	# that this build does not understand cannot leave the probe stuck.
	risk_enabled = bool(raw.get("risk_enabled", false))
	risk_boot = str(raw.get("risk_boot", "idle"))
	if not risk_boot in ["idle", "probing", "proven"]:
		risk_boot = "idle"
	risk_last_error = str(raw.get("risk_last_error", ""))

func save_preferences() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(to_dict(), "  "))
	file.close()

func set_option(key: String, value: Variant, save: bool = true) -> void:
	set(key, value)
	mark_custom()
	if save:
		save_preferences()
	apply_all()

## Draft quality is an interaction policy, not a render feature. Changing it
## never moves the graphics preset to Custom.
func set_draft_editing(enabled: bool) -> void:
	draft_editing = enabled
	save_preferences()
	changed.emit()

const RENDERERS := ["forward_plus", "mobile", "gl_compatibility"]

func renderer_label(value: String) -> String:
	match value:
		"forward_plus":
			return "Forward+"
		"mobile":
			return "Mobile"
		"gl_compatibility":
			return "Compatibility"
	return value

func set_renderer_choice(value: String) -> void:
	if value not in RENDERERS:
		return
	renderer_preference = value
	renderer_choice = value
	save_preferences()

func set_renderer_preference(value: String) -> void:
	set_renderer_choice(value)

func default_environment(env: Environment) -> void:
	## The studio look: a neutral sky for ambient and reflections, contact
	## shadows from SSAO, and a filmic response so highlights roll off instead
	## of clipping. Called once when the preview viewport is built.
	# The background is a real sky so ambient light, reflections and the visible
	# backdrop all come from the same studio gradient. This is not a decorative
	# colour card: changing the sky changes the scene's indirect light.
	env.background_mode = Environment.BG_SKY
	env.background_energy_multiplier = 1.1

	var sky_material := ShaderMaterial.new()
	sky_material.shader = STUDIO_SKY
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# Exposure is owned by the persisted Gfx preference and applied by
	# apply_environment() below, so do not set a second value here.
	env.tonemap_white = 6.0

	env.ssao_enabled = true
	env.ssao_radius = 1.55
	env.ssao_intensity = 1.25
	env.ssao_power = 1.35
	env.ssao_detail = 0.65
	env.ssao_horizon = 0.06
	env.ssao_sharpness = 0.98
	env.ssao_light_affect = 0.08
	env.ssao_ao_channel_affect = 0.0

	env.ssil_enabled = false
	env.ssr_enabled = false
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 1.6
	env.ssr_depth_tolerance = 0.2

	env.glow_enabled = true
	env.glow_intensity = 0.42
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.15
	env.glow_hdr_scale = 2.0

	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.03
	env.adjustment_saturation = 1.05

	env.volumetric_fog_enabled = false
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = Color(0.80, 0.80, 0.80)

	env.fog_enabled = false
	apply_environment(env)
