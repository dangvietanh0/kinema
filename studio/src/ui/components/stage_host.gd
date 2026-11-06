extends Control
## The one stage surface for every workspace.
##
## The host owns the viewport rectangle and nothing else. Overlays that belong
## to the stage (perf, rig, the view's own HUD) are mounted by the editor into
## the viewport host so they can never outlive the stage. The workspace panel
## and the Animate pane are layout siblings, never stage children.

var _viewport_host: Control


func _ready() -> void:
	if _viewport_host == null:
		_build_host()


func setup(view: Control) -> void:
	if _viewport_host == null:
		_build_host()
	if view == null:
		return
	if view.get_parent() != _viewport_host:
		if view.get_parent() != null:
			view.get_parent().remove_child(view)
		_viewport_host.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_host() -> void:
	_viewport_host = Control.new()
	_viewport_host.name = "ViewportHost"
	_viewport_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_host.custom_minimum_size.y = 120
	_viewport_host.clip_contents = true
	add_child(_viewport_host)


## The rectangle the 3D view actually occupies, in global coordinates.
func stage_rect() -> Rect2:
	if _viewport_host == null:
		return Rect2()
	return _viewport_host.get_global_rect()


func view_host() -> Control:
	return _viewport_host
