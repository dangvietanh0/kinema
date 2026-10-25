extends RefCounted
## Pure layout resolution for the three workbench modes.
##
## `resolve()` is deterministic and side-effect free so the smoke suite can
## prove the maths without a window. The shell only applies its results.
##
## One UI unit is one dp on Android/iOS. The base scale is the display density,
## the user scale multiplies it, and Desktop mode additionally shrinks
## everything uniformly until the logical canvas is at least 960x600. When that
## fit drops below 100% the user scale is disabled; Desktop never falls back to
## another mode, it just gets smaller.

const COMPACT_MIN := Vector2(320.0, 480.0)
const DESKTOP_MIN := Vector2(960.0, 600.0)
const COMPACT_MAX_DP := 600.0
const STUDIO_MAX_DP := 1100.0
const USER_SCALE_MIN := 0.85
const USER_SCALE_MAX := 1.30


static func resolve(physical: Vector2i, dpi: float, platform: String, user_scale: float,
		mode_preference: String, fit_desktop: bool) -> Dictionary:
	var density := 1.0
	if platform == "Android" or platform == "iOS":
		density = clampf(dpi / 160.0, 1.0, 4.0)
	var size := Vector2(maxf(1.0, float(physical.x)), maxf(1.0, float(physical.y)))
	var device_dp := size / density
	var mode := _resolve_mode(device_dp, mode_preference)
	var scale := clampf(user_scale, USER_SCALE_MIN, USER_SCALE_MAX)
	var base_factor := density
	var logical_before := size / (base_factor * scale)
	var fit := 1.0
	var factor := base_factor * scale
	var clamped := false
	if mode == "desktop":
		if fit_desktop:
			fit = minf(1.0, minf(logical_before.x / DESKTOP_MIN.x, logical_before.y / DESKTOP_MIN.y))
			fit = maxf(fit, 0.0001)
			factor *= fit
	else:
		# Compact and Studio must never overflow the physical canvas: cap the
		# factor so the logical canvas keeps the mode's minimum size.
		var max_factor := minf(size.x / COMPACT_MIN.x, size.y / COMPACT_MIN.y)
		if factor > max_factor:
			factor = maxf(max_factor, 0.0001)
			clamped = true
	var logical_after := size / factor
	return {
		"mode": mode,
		"device_dp": device_dp,
		"base_factor": base_factor,
		"user_scale": scale,
		"logical_before": logical_before,
		"fit": fit,
		"fit_percent": fit * 100.0,
		"factor": factor,
		"logical_after": logical_after,
		"clamped": clamped,
		"user_scale_enabled": fit >= 0.999,
	}


static func _resolve_mode(device_dp: Vector2, preference: String) -> String:
	match preference:
		"compact":
			return "compact"
		"studio":
			return "studio"
		"desktop":
			return "desktop"
	# Auto: the width in dp decides, so no device silently gets the desktop
	# shell it cannot read. A 1280x800 desktop (1280 dp) is Desktop, a 1280 dp
	# tablet landscape is Studio (short side 800 dp when read as dp), a phone
	# upright is Compact (411 dp) and a phone on its side is Studio (891 dp).
	var width_dp := device_dp.x
	var short_side := minf(device_dp.x, device_dp.y)
	if width_dp < COMPACT_MAX_DP:
		return "compact"
	if short_side < COMPACT_MAX_DP:
		return "studio"
	if width_dp < STUDIO_MAX_DP:
		return "studio"
	return "desktop"


static func mode_for_device(device_dp: Vector2) -> String:
	return _resolve_mode(device_dp, "auto")


static func orientation_constant(value: String) -> int:
	match value:
		"portrait":
			return DisplayServer.SCREEN_PORTRAIT
		"landscape":
			return DisplayServer.SCREEN_LANDSCAPE
	return DisplayServer.SCREEN_SENSOR
