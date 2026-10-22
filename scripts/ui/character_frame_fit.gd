# 将动画的设计画布放进场景动画框；序列帧和将来的骨骼动画共用此规则。
# 缩放按整张设计画布计算，不按每帧人物轮廓计算，避免呼吸时人物上下跳动。
extends Node

var _slot: Control
var _content: Control
var _design_size: Vector2
var _design_scale: Vector2

func configure(slot: Control, content: Control) -> void:
	_slot = slot
	_content = content
	_design_size = content.size
	_design_scale = content.scale
	_slot.resized.connect(_fit)
	_fit()

func _fit() -> void:
	if _design_size.x <= 0 or _design_size.y <= 0 or _slot.size.x <= 0 or _slot.size.y <= 0:
		return
	var ratio := minf(_slot.size.x / _design_size.x, _slot.size.y / _design_size.y)
	_content.scale = _design_scale * ratio
	# 底部对齐、横向居中；外层槽位仍负责人物滑入与场景中的位置。
	_content.position = Vector2((_slot.size.x - _design_size.x * ratio) * 0.5,
		_slot.size.y - _design_size.y * ratio)

func _exit_tree() -> void:
	if is_instance_valid(_slot) and _slot.resized.is_connected(_fit):
		_slot.resized.disconnect(_fit)
