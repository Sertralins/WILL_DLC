## F6 运行预览；空格暂停，左右方向键逐步查看。
extends Control

const CHARACTER := preload("res://scenes/xl/qyy_anim.tscn")
var character: Control
var status: Label

func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("e8e5de")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	character = CHARACTER.instantiate()
	character.modulate.a = 0.8
	add_child(character)
	resized.connect(_layout)
	_layout()
	var title := Label.new()
	title.text = "仇有余 · 骨骼待机样例"
	title.position = Vector2(40, 32)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color("343a37"))
	add_child(title)
	status = Label.new()
	status.position = Vector2(40, 90)
	status.add_theme_color_override("font_color", Color("4a524b"))
	add_child(status)
	if "--capture" in OS.get_cmdline_user_args():
		character.playing = false
		character.seek(2)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://qyy_spine_preview.png")
		print("QYY_CAPTURE: ", ProjectSettings.globalize_path("user://qyy_spine_preview.png"))
		get_tree().quit()

func _layout() -> void:
	var factor := minf((size.y - 60) / 1024.0, size.x / 700.0)
	character.scale = Vector2.ONE * factor
	character.position = Vector2((size.x - 512 * factor) * 0.5, size.y - 1024 * factor - 24)

func _process(_delta: float) -> void:
	if is_instance_valid(status):
		status.text = "8 秒循环 · 7 根骨骼 · 1 张贴图\n空格：暂停 / 播放    ← →：调整时间\n%.2f s" % character.elapsed

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.keycode == KEY_SPACE:
		character.playing = not character.playing
	elif event.keycode in [KEY_LEFT, KEY_RIGHT]:
		character.playing = false
		character.seek(character.elapsed + (0.125 if event.keycode == KEY_RIGHT else -0.125))
