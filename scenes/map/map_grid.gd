# map_grid.gd — 大地图栅格背景: 浅色横线(距离刻度) + 浅色竖线(人物列界), 与角色竖线构成栅格
extends Node2D

var xs: Array = []
var ys: Array = []
var v_height := 0.0
var line_color := Color(0.35, 0.35, 0.33, 0.16)

func setup(lines_x: Array, lines_y: Array, height: float) -> void:
	xs = lines_x
	ys = lines_y
	v_height = height
	queue_redraw()

func _draw() -> void:
	if xs.is_empty():
		return
	var x_from: float = xs[0]
	var x_to: float = xs[xs.size() - 1]
	for y in ys:
		draw_line(Vector2(x_from, float(y)), Vector2(x_to, float(y)), line_color, 2.0, true)
	for x in xs:
		draw_line(Vector2(float(x), 0.0), Vector2(float(x), v_height), line_color, 2.0, true)
