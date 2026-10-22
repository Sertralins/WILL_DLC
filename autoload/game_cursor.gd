# 游戏全局光标：图片保留透明边缘，点击热点对准食指尖。
extends Node

const HAND_PATH := "res://assets/ui/cursors/play_hand.png"
const HOTSPOT := Vector2(56, 30)
const SHAPES := [Input.CURSOR_ARROW, Input.CURSOR_POINTING_HAND, Input.CURSOR_IBEAM,
	Input.CURSOR_DRAG, Input.CURSOR_CAN_DROP, Input.CURSOR_FORBIDDEN]

func _ready() -> void:
	var hand := load(HAND_PATH) as Texture2D
	# 按钮、正文和拖动状态也沿用手形；放置是否合法由落点阴影提示。
	for shape in SHAPES:
		Input.set_custom_mouse_cursor(hand, shape, HOTSPOT)

func _exit_tree() -> void:
	# 在渲染器关闭前释放系统光标持有的纹理。
	for shape in SHAPES:
		Input.set_custom_mouse_cursor(null, shape)
