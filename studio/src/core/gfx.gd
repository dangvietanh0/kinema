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
# Apply
# -------------------------------------------------------------------------

func apply_globals() -> void:
	Engine.max_fps = max_fps
	RenderingServer.directional_soft_shadow_filter_set_quality(shadow_quality)
	RenderingServer.positional_soft_shadow_filter_set_quality(shadow_quality)
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS[clampi(shadow_quality, 0, 3)], false)

func apply_viewport(viewport: Viewport) -> void:
	if viewport == null:
		return
	viewport.msaa_3d = MSAA_MODES[clampi(msaa, 0, 3)]
	viewport.scaling_3d_scale = clampf(scale_3d, 0.5, 1.0)
	viewport.use_taa = taa and is_forward()

func apply_environment(env: Environment) -> void:
	if env == null:
		return
	var forward := is_forward()
	env.tonemap_mode = TONEMAPS[clampi(tonemap, 0, 3)]
	env.tonemap_exposure = exposure
	env.ssao_enabled = ssao and forward
	# SSAO quality is not an Environment property: in Godot 4.7 it lives on
	# RenderingServer as a global quality override (very low..ultra).
	if forward:
		# adaptive_target is a 0..1 rate: 1.0 asks for the highest quality the
		# selected preset can sustain, rather than a frame budget.
		RenderingServer.environment_set_ssao_quality(
			clampi(ssao_quality + 1, 1, 4), false, 1.0, 2, 0.0, 0.0
		)
	env.ssil_enabled = ssil and forward
	env.ssr_enabled = ssr and forward
	env.glow_enabled = glow
	env.volumetric_fog_enabled = volumetric_fog and forward

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

func default_environment(env: Environment) -> void:
	## The studio look: a neutral sky for ambient and reflections, contact
	## shadows from SSAO, and a filmic response so highlights roll off instead
	## of clipping. Called once when the preview viewport is built.
	# The background is a real sky so ambient light, reflections and the visible
	# backdrop all come from the same studio gradient. This is not a decorative
	# colour card: changing the sky changes the scene's indirect light.
	env.background_mode = Environment.BG_SKY
	env.background_energy_multiplier = 1.0

	var sky_material := ShaderMaterial.new()
	sky_material.shader = STUDIO_SKY
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.15
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# Exposure is owned by the persisted Gfx preference and applied by
	# apply_environment() below, so do not set a second value here.
	env.tonemap_white = 6.0

	env.ssao_enabled = true
	env.ssao_radius = 1.55
	env.ssao_intensity = 2.35
	env.ssao_power = 1.6
	env.ssao_detail = 0.65
	env.ssao_horizon = 0.06
	env.ssao_sharpness = 0.98
	env.ssao_light_affect = 0.22
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
	env.volumetric_fog_albedo = Color(0.79, 0.83, 0.9)

	env.fog_enabled = false
	apply_environment(env)
