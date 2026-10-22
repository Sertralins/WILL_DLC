# 三人背景：沿用双人背景的原版锯齿素材，在 600 / 1320 处拼接。
extends Control

const EDGE_LEFT := preload("res://assets/background/BGL.png")
const EDGE_RIGHT := preload("res://assets/background/BGR.png")
const BOUNDARIES := [0.0, 600.0, 1320.0, 1920.0]

func setup(colors: Array[Color]) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in get_children():
		child.free()
	for i in 3:
		var fill := ColorRect.new()
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.color = colors[i]
		fill.position = Vector2(BOUNDARIES[i], 0)
		fill.size = Vector2(BOUNDARIES[i + 1] - BOUNDARIES[i], 1080)
		add_child(fill)
	for i in 2:
		for side in 2:
			var edge := TextureRect.new()
			edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			edge.texture = EDGE_LEFT if side == 0 else EDGE_RIGHT
			edge.modulate = colors[i + side]
			edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			edge.position = Vector2(BOUNDARIES[i + 1] - 56, 0)
			edge.size = Vector2(112, 1080)
			add_child(edge)
