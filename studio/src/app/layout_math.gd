extends RefCounted
## Pure layout resolution for the three workbench modes.
##
## `resolve()` is deterministic and side-effect free so the smoke suite can
## prove the maths without a window. The shell only applies its results.
##
## One UI unit is one dp on Android/iOS. The base scale is the display density,
## the user scale (50-200%) multiplies it, and Desktop mode additionally applies
## a fit so 100% still reaches a 960x600 logical canvas. The fit is computed
## from density alone, never from the user scale: otherwise a slider step would
## be cancelled by a matching fit step and the control would look broken. When
## the chosen scale makes the canvas smaller than the mode minimum, the shell
## clamps the effective factor and says so; it never rewrites the preference.

const COMPACT_MIN := Vector2(320.0, 480.0)
## Landscape-first minimum. A phone on its side is 360-480 dp tall, so the
## Studio shell is designed to fit 320 dp of height at a full 1:1 scale. Using
## the portrait minimum here would shrink every touch target on landscape
## phones and defeat the density.
const STUDIO_MIN := Vector2(480.0, 320.0)
const DESKTOP_MIN := Vector2(960.0, 600.0)
const COMPACT_MAX_DP := 600.0
const STUDIO_MAX_DP := 1100.0
const USER_SCALE_MIN := 0.50
const USER_SCALE_MAX := 2.00


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
	if mode == "desktop" and fit_desktop:
		# The fit is a 100% baseline: how much the raw density canvas must
		# shrink to reach 960x600. User scale multiplies on top so 50-200%
		# remains a real control even on a phone using the Desktop shell.
		var baseline := size / base_factor
		fit = minf(1.0, minf(baseline.x / DESKTOP_MIN.x, baseline.y / DESKTOP_MIN.y))
		fit = maxf(fit, 0.0001)
	var factor := base_factor * scale * fit
	var clamped := false
	if mode != "desktop":
		# Compact and Studio must never overflow the physical canvas: cap the
		# factor so the logical canvas keeps the mode's own minimum size. The
		# two modes have different shapes, so they cannot share one minimum.
		var minimum := COMPACT_MIN if mode == "compact" else STUDIO_MIN
		var max_factor := minf(size.x / minimum.x, size.y / minimum.y)
		if factor > max_factor:
			factor = maxf(max_factor, 0.0001)
			clamped = true
	elif fit_desktop:
		# Surface the honest case where a large user scale pushes the Desktop
		# canvas below its 960x600 design. The shell warns; it does not clamp.
		var logical_at_choice := size / maxf(factor, 0.0001)
		clamped = logical_at_choice.x < DESKTOP_MIN.x - 0.5 or logical_at_choice.y < DESKTOP_MIN.y - 0.5
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
		"user_scale_enabled": true,
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
