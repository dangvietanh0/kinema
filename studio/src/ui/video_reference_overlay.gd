extends Control
## Viewport video-reference overlay: the rotoscope layer.
##
## The overlay draws the last visible reference that covers the playhead as a
## translucent image over the 3D surface, below the HUD. It is a frame proxy:
## scrubbing changes the frame, nothing here plays video. OGV references have
## no frame proxy, so they never draw here (they play in their own player).

const VideoReference = preload("res://src/core/video_reference.gd")

var doc = null
var view = null
var render_mode := false

var _frame_image: Image
var _frame_key := ""
var _drawn_texture: ImageTexture


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func setup(document, view_ref = null) -> void:
	doc = document
	view = view_ref
	if doc != null and doc.has_signal("media_changed") and not doc.media_changed.is_connected(_on_media_changed):
		doc.media_changed.connect(_on_media_changed)
	refresh()


func set_render_mode(enabled: bool) -> void:
	render_mode = enabled
	refresh()


func refresh() -> void:
	visible = not render_mode and _reference_id() != ""
	queue_redraw()


func _on_media_changed() -> void:
	refresh()


func _reference() -> Dictionary:
	var references: Array = []
	if doc == null or doc.media_system == null:
		return {}
	references = doc.media_system.video_references()
	var time := _overlay_time()
	var best: Dictionary = {}
	for reference in references:
		var record: Dictionary = VideoReference.normalize(reference)
		if not bool(record.get("visible", true)):
			continue
		# A zero/negative duration means "open reference": every moment after
		# start counts; otherwise the block is [start, start + duration].
		var covered: bool = time >= float(record.get("start", 0.0))
		var length := float(record.get("duration", 0.0))
		if length > 0.0:
			covered = covered and time <= float(record.get("start", 0.0)) + length
		if covered:
			best = record
	return best


func _reference_id() -> String:
	if render_mode or doc == null or doc.media_system == null:
		return ""
	return str(_reference().get("id", ""))


## Sequence time while the sequence clock runs; the active strip's start plus
## the clip-local playhead while editing a clip; frame zero in isolation.
func _overlay_time() -> float:
	if doc.is_sequence_playing():
		return doc.sequence_time()
	var strip: Dictionary = {}
	if doc.animation != null and doc.animation.has_method("strip_at"):
		strip = doc.animation.strip_at(doc.current_time)
	return VideoReference.clip_preview_time(strip, doc.current_time)


func _process(_delta: float) -> void:
	if doc == null or render_mode:
		return
	refresh()


func _draw() -> void:
	if not visible or render_mode:
		return
	var reference := _reference()
	var reference_id := str(reference.get("id", ""))
	if reference_id == "" or doc == null or doc.media_system == null:
		return
	var key := "%s@%.3f" % [reference_id, _overlay_time()]
	var frame: Image = doc.media_system.frame_for_time(reference_id, _overlay_time())
	# OGV references (and missing proxies) own no frames; never fake a redraw.
	if frame == null:
		return
	if key != _frame_key or frame != _frame_image:
		_frame_key = key
		_frame_image = frame
		_drawn_texture = ImageTexture.create_from_image(frame)
	if _drawn_texture == null:
		return
	var texture_size := _drawn_texture.get_size()
	if texture_size.x < 1.0 or texture_size.y < 1.0:
		return
	var area := get_size()
	if area.x < 1.0 or area.y < 1.0:
		return
	var bounds := _filled_rect(texture_size, area, str(reference.get("fit", VideoReference.DEFAULT_FIT)))
	if bounds.size.x < 1.0 or bounds.size.y < 1.0:
		return
	var opacity := clampf(float(reference.get("opacity", VideoReference.DEFAULT_OPACITY)), 0.0, 1.0)
	var factor := maxf(0.01, float(reference.get("scale", 1.0)))
	var sx := -factor if bool(reference.get("flip_h", false)) else factor
	var offset: Array = reference.get("offset", [0.0, 0.0])
	var shift := Vector2(
		float(offset[0] if offset.size() > 0 else 0.0),
		float(offset[1] if offset.size() > 1 else 0.0)
	) * area
	# Scale/flip act around the fitted frame centre, so the anchor never slides
	# when the user moves the scale slider; the fractional offset shifts after.
	var matrix := Transform2D(Vector2(sx, 0.0), Vector2(0.0, factor), Vector2.ZERO)
	var pivot := bounds.get_center()
	var transform := Transform2D(Vector2(sx, 0.0), Vector2(0.0, factor), pivot - matrix * pivot)
	draw_set_transform_matrix(transform.translated(shift))
	draw_texture_rect(_drawn_texture, bounds, false, Color(1.0, 1.0, 1.0, opacity))


## Contain letterboxes inside the overlay; cover crops beyond its edges.
func _filled_rect(texture_size: Vector2, area: Vector2, fit: String) -> Rect2:
	var ratio := Vector2(area.x / texture_size.x, area.y / texture_size.y)
	var factor := minf(ratio.x, ratio.y) if fit == "contain" else maxf(ratio.x, ratio.y)
	if factor <= 0.0:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var size := texture_size * factor
	var position := (area - size) * 0.5
	return Rect2(position, size)
