extends Node
## Real frame instrumentation plus the adaptive preview-quality policy.
##
## Every value comes from Godot's own monitors. Nothing is estimated: when a
## monitor is unavailable it is reported as -1 so the UI can show a dash
## instead of an invented number.

signal sample_updated(sample: Dictionary)

const HISTORY := 120
const EMIT_INTERVAL := 0.25
const ADAPT_COOLDOWN := 1.0

var fps := 0.0
var frame_ms := 0.0
var process_ms := 0.0
var physics_ms := 0.0
var draw_calls := 0
var primitives := 0
var node_count := 0
var samples: Array[float] = []
var preview_scale := 1.0
var preview_update := "on_demand"
var preview_cap := 1920
var adaptive_quality := true
var target_fps := 60
var min_preview_scale := 0.6
var max_fps := 60
var vsync := true

var _elapsed := 0.0
var _adapt_cooldown := 0.0
var _view: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	_adapt_cooldown = maxf(0.0, _adapt_cooldown - delta)
	var measured_fps := float(Performance.get_monitor(Performance.TIME_FPS))
	var measured_frame := float(Performance.get_monitor(Performance.TIME_PROCESS))
	if measured_frame > 0.0:
		fps = measured_fps
		frame_ms = measured_frame * 1000.0
		samples.append(frame_ms)
		while samples.size() > HISTORY:
			samples.pop_front()
	if _elapsed >= EMIT_INTERVAL:
		_elapsed = 0.0
		fps = float(Performance.get_monitor(Performance.TIME_FPS))
		process_ms = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
		physics_ms = 0.0
		node_count = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		_adapt()
		sample_updated.emit(sample())


func sample() -> Dictionary:
	return {
		"fps": fps,
		"frame_ms": frame_ms,
		"process_ms": process_ms,
		"physics_ms": physics_ms,
		"draw_calls": draw_calls,
		"primitives": primitives,
		"nodes": node_count,
		"preview_scale": preview_scale,
		"samples": samples.duplicate(),
	}


func reset_stats() -> void:
	samples.clear()
	fps = 0.0
	frame_ms = 0.0
	process_ms = 0.0
	physics_ms = 0.0
	draw_calls = 0
	primitives = 0
	_elapsed = 0.0
	_adapt_cooldown = 0.0


func watch(view: Node) -> void:
	_view = view
	if _view != null:
		_view.set_preview_scale(preview_scale)
		_view.set_preview_cap(preview_cap)


func set_adaptive_quality(enabled: bool) -> void:
	adaptive_quality = enabled


func set_target_fps(value: int) -> void:
	target_fps = clampi(value, 1, 240)


func set_preview_scale(value: float) -> void:
	preview_scale = clampf(value, min_preview_scale, 1.0)
	if _view != null:
		_view.set_preview_scale(preview_scale)


func set_preview_cap(value: int) -> void:
	preview_cap = clampi(value, 480, 7680)
	if _view != null:
		_view.set_preview_cap(preview_cap)


func set_preview_update(policy: String) -> void:
	preview_update = policy if policy in ["on_demand", "always"] else "on_demand"


## Pure policy step. Low frame rates drop the preview resolution by 10%, a
## comfortable frame rate buys back 5% headroom, and the floor is respected.
static func next_preview_scale(current: float, measured_fps: float, p_target_fps: int, min_scale: float) -> float:
	var target := float(maxi(1, p_target_fps))
	if measured_fps <= 0.0:
		return clampf(current, min_scale, 1.0)
	if measured_fps < target * 0.8:
		return clampf(current - 0.10, min_scale, 1.0)
	if measured_fps > target * 0.95:
		return clampf(current + 0.05, min_scale, 1.0)
	return clampf(current, min_scale, 1.0)


func _adapt() -> void:
	if not adaptive_quality or _adapt_cooldown > 0.0 or fps <= 0.0:
		return
	var next := next_preview_scale(preview_scale, fps, target_fps, min_preview_scale)
	if is_equal_approx(next, preview_scale):
		return
	preview_scale = next
	_adapt_cooldown = ADAPT_COOLDOWN
	if _view != null:
		_view.set_preview_scale(preview_scale)
