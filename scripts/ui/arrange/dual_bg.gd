# dual_bg.gd — 双行背景模式(均存在 L/R 时使用):
#   左半边 = L 人物主题色, 右半边 = R 人物主题色;
#   中央两张锯齿贴图(BGL 锯齿朝右 / BGR 锯齿朝左)互补卡齐,
#   各自染成对应人物主题色, 形成屏幕中央的锯齿渐变过渡。
extends Control

@onready var l_fill: ColorRect = $LFill
@onready var r_fill: ColorRect = $RFill
@onready var bgl: TextureRect = $BGL
@onready var bgr: TextureRect = $BGR

func setup(l_color: Color, r_color: Color) -> void:
	l_fill.color = l_color
	r_fill.color = r_color
	bgl.modulate = l_color
	bgr.modulate = r_color
