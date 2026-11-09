extends VBoxContainer
## The Animate workspace's real layout pane.
##
## The existing Timeline component is mounted here once. The pane is a sibling
## below the stage, never an overlay: resizing the window gives the pane its
## own rows instead of covering the 3D image. The stage preview itself is the
## real StageHost above the pane, so this class only reports its state.

var _timeline: Control = null
var _stage_preview_visible := false
var _stage_preview_height := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func setup(timeline: Control) -> void:
	_timeline = timeline
	if timeline == null:
		return
	timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if timeline.get_parent() != self:
		if timeline.get_parent() != null:
			timeline.get_parent().remove_child(timeline)
		add_child(timeline)


func timeline() -> Control:
	return _timeline


## The stage preview lives in the StageHost above this pane; recording the
## size here keeps the pane API honest without inventing a second viewport.
func set_stage_preview(visible: bool, height: float) -> void:
	_stage_preview_visible = visible
	_stage_preview_height = maxf(0.0, height) if visible else 0.0
	if _timeline != null:
		_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL


func stage_preview_visible() -> bool:
	return _stage_preview_visible


func stage_preview_height() -> float:
	return _stage_preview_height


func set_timeline_visible(visible: bool) -> void:
	if _timeline != null:
		_timeline.visible = visible
