extends VBoxContainer
## The Animate workspace's real layout pane.
##
## The existing Timeline component is mounted here once. The pane is a sibling
## below the stage, never an overlay: resizing the window gives the pane its
## own rows instead of covering the 3D image.

var _timeline: Control = null


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
