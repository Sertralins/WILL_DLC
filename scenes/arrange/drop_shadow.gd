# 落点提示：内部浅色，四周柔边；外形略小于即将放下的纸条。
extends Control

const INSET := Vector2(18, 10)
const SOFT_EDGE := 20
# 阴影强度集中在这里调整；边缘比中心更淡。
const BODY_ALPHA := 0.32
const EDGE_ALPHA := 0.16
var allowed := true:
	set(value):
		allowed = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var color := Color(0.025, 0.02, 0.02, BODY_ALPHA) if allowed else Color(0.7, 0.055, 0.045, BODY_ALPHA)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.shadow_color = Color(color.r, color.g, color.b, EDGE_ALPHA)
	style.shadow_size = SOFT_EDGE
	style.set_corner_radius_all(4)
	var inset := Vector2(minf(INSET.x, size.x * 0.1), minf(INSET.y, size.y * 0.15))
	draw_style_box(style, Rect2(inset, (size - inset * 2).max(Vector2.ONE)))
