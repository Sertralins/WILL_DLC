# map_line.gd — 自绘连接线(文档 §4.3 的竖排轴向版): 圆角折线 + 生长进度动画 + 虚线
#
# 竖滚地图路由: 同列 = 垂直直线; 跨列 = 垂直→圆弧→水平→圆弧→垂直 的 S 形管件,
# 从起点(父块底边/头像底)出发, 进入终点块顶边。
# (对还原版"管件"观感: 10px 线宽、~37px 圆角半径)
# progress 0→1 按折线总长截断, 实现"连线生长"动画。
extends Node2D

var a: Vector2                     # 起点(父块/头像锚点)
var b: Vector2                     # 终点(子块顶边锚点)
var line_color: Color = Color.WHITE
var dashed := false                # 待定边(虚线)
var width := 10.0
var corner := 37.0                 # 圆角半径
var progress := 1.0                # 生长进度 0..1

var _animating := false

func setup(from: Vector2, to: Vector2, color: Color, is_dashed := false, grow_time := 0.0) -> void:
	a = from
	b = to
	line_color = color
	dashed = is_dashed
	if grow_time > 0.0:
		progress = 0.0
		_animating = true

func _ready() -> void:
	if _animating:
		var tw := create_tween()
		tw.tween_method(_set_progress, 0.0, 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _set_progress(v: float) -> void:
	progress = v
	queue_redraw()

# 折线点列: 同列直线; 跨列 S 形(两段圆弧)
func _polyline() -> PackedVector2Array:
	if is_equal_approx(a.x, b.x):
		return PackedVector2Array([a, b])
	var dx := b.x - a.x
	var dy := b.y - a.y
	if dy <= 8.0:
		return PackedVector2Array([a, b])
	var hx := signf(dx)
	var r := minf(minf(corner, dy * 0.25), absf(dx) * 0.5)
	if r < 4.0:
		return PackedVector2Array([a, b])
	var mid_y := a.y + dy * 0.5
	# 弧1: 垂直→水平, 圆心 o1 = (a.x + r*hx, mid_y - r)
	var o1 := Vector2(a.x + r * hx, mid_y - r)
	var pts := PackedVector2Array([a, Vector2(a.x, mid_y - r)])
	var from1 := PI if hx > 0.0 else 0.0
	for i in range(1, 9):
		var ang := lerpf(from1, PI * 0.5, float(i) / 8.0)
		pts.append(o1 + Vector2(cos(ang), sin(ang)) * r)
	# 水平段
	pts.append(Vector2(b.x - r * hx, mid_y))
	# 弧2: 水平→垂直, 圆心 o2 = (b.x - r*hx, mid_y + r)
	var o2 := Vector2(b.x - r * hx, mid_y + r)
	var to2 := 0.0 if hx > 0.0 else -PI
	for i in range(1, 9):
		var ang := lerpf(-PI * 0.5, to2, float(i) / 8.0)
		pts.append(o2 + Vector2(cos(ang), sin(ang)) * r)
	pts.append(b)
	return pts

func _draw() -> void:
	var pts := _polyline()
	if pts.size() < 2:
		return
	# 按 progress 截断总长
	var lens: Array[float] = []
	var total := 0.0
	for i in pts.size() - 1:
		var l := pts[i].distance_to(pts[i + 1])
		lens.append(l)
		total += l
	var budget := total * clampf(progress, 0.0, 1.0)
	var out := PackedVector2Array([pts[0]])
	for i in lens.size():
		if budget <= 0.0:
			break
		if budget >= lens[i]:
			out.append(pts[i + 1])
		else:
			out.append(pts[i].lerp(pts[i + 1], budget / lens[i]))
			break
		budget -= lens[i]
	if out.size() < 2:
		return
	if dashed:
		for i in out.size() - 1:
			draw_dashed_line(out[i], out[i + 1], line_color, width, 6.0, false, true)
	else:
		draw_polyline(out, line_color, width, true)
