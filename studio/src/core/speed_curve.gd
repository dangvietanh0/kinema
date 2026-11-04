extends RefCounted
## Curve-family math shared by the compact sheet and the speed graph.
##
## Every family maps t in [0,1] to a finite scalar with f(0) = 0 and
## f(1) = 1. Bounce, elastic, back and spring intentionally leave [0,1] in the
## middle of the curve; that overshoot is real, sampled animation data once a
## family is baked into keys.

const FAMILY_LABELS := {
	"bounce_out": "Bounce",
	"bounce_in": "Bounce",
	"bounce_in_out": "Bounce",
	"elastic_out": "Elastic",
	"elastic_in": "Elastic",
	"back_out": "Back",
	"back_in": "Back",
	"spring": "Spring",
	"sine_in": "Sine",
	"sine_out": "Sine",
	"sine_in_out": "Sine",
	"expo_in": "Expo",
	"expo_out": "Expo",
	"expo_in_out": "Expo",
}

static var SPEED_CURVES: Dictionary = {}


static func _static_init() -> void:
	SPEED_CURVES = {
		"bounce_out": func(t: float) -> float: return _bounce_out(t),
		"bounce_in": func(t: float) -> float: return _bounce_in(t),
		"bounce_in_out": func(t: float) -> float: return _bounce_in_out(t),
		"elastic_out": func(t: float) -> float: return _elastic_out(t),
		"elastic_in": func(t: float) -> float: return _elastic_in(t),
		"back_out": func(t: float) -> float: return _back_out(t),
		"back_in": func(t: float) -> float: return _back_in(t),
		"spring": func(t: float) -> float: return _spring(t),
		"sine_in": func(t: float) -> float: return _sine_in(t),
		"sine_out": func(t: float) -> float: return _sine_out(t),
		"sine_in_out": func(t: float) -> float: return _sine_in_out(t),
		"expo_in": func(t: float) -> float: return _expo_in(t),
		"expo_out": func(t: float) -> float: return _expo_out(t),
		"expo_in_out": func(t: float) -> float: return _expo_in_out(t),
	}


static func family_ids() -> PackedStringArray:
	return PackedStringArray(SPEED_CURVES.keys())


static func family_label(id: String) -> String:
	return str(FAMILY_LABELS.get(id, ""))


static func evaluate(id: String, t: float) -> float:
	## Clamp the input, keep exact endpoints and return 0 for an unknown id.
	var clamped := clampf(t, 0.0, 1.0)
	if clamped <= 0.0:
		return 0.0
	if clamped >= 1.0:
		return 1.0
	var curve: Callable = SPEED_CURVES.get(id, Callable())
	if not curve.is_valid():
		return 0.0
	var value: float = curve.call(clamped)
	if is_nan(value) or is_inf(value):
		return 0.0
	return value


static func _bounce_out(t: float) -> float:
	var x := t
	if x < 1.0 / 2.75:
		return 7.5625 * x * x
	if x < 2.0 / 2.75:
		x -= 1.5 / 2.75
		return 7.5625 * x * x + 0.75
	if x < 2.5 / 2.75:
		x -= 2.25 / 2.75
		return 7.5625 * x * x + 0.9375
	x -= 2.625 / 2.75
	return 7.5625 * x * x + 0.984375


static func _bounce_in(t: float) -> float:
	return 1.0 - _bounce_out(1.0 - t)


static func _bounce_in_out(t: float) -> float:
	if t < 0.5:
		return (1.0 - _bounce_out(1.0 - 2.0 * t)) * 0.5
	return (1.0 + _bounce_out(2.0 * t - 1.0)) * 0.5


static func _elastic_out(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	return pow(2.0, -10.0 * t) * sin((t - 0.075) * TAU / 0.3) + 1.0


static func _elastic_in(t: float) -> float:
	return 1.0 - _elastic_out(1.0 - t)


static func _back_out(t: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var x := t - 1.0
	return 1.0 + c3 * x * x * x + c1 * x * x


static func _back_in(t: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return c3 * t * t * t - c1 * t * t


static func _spring(t: float) -> float:
	## Normalized damped cosine: starts at 0, settles at 1, overshoots once.
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	return 1.0 - exp(-6.0 * t) * cos(10.0 * PI * t)


static func _sine_in(t: float) -> float:
	return 1.0 - cos(t * PI * 0.5)


static func _sine_out(t: float) -> float:
	return sin(t * PI * 0.5)


static func _sine_in_out(t: float) -> float:
	return -(cos(PI * t) - 1.0) * 0.5


static func _expo_in(t: float) -> float:
	if t <= 0.0:
		return 0.0
	return pow(2.0, 10.0 * t - 10.0)


static func _expo_out(t: float) -> float:
	if t >= 1.0:
		return 1.0
	return 1.0 - pow(2.0, -10.0 * t)


static func _expo_in_out(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	if t < 0.5:
		return pow(2.0, 20.0 * t - 10.0) * 0.5
	return (2.0 - pow(2.0, -20.0 * t + 10.0)) * 0.5
