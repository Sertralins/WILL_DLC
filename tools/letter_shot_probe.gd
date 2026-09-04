# tools/letter_shot_probe.gd — 信件场景渲染截图自检:
#   载入 letter_reader, 截图初始状态; 模拟点击推进两行后再截一张
# 用法: godot --path . res://tools/letter_shot_probe.tscn -- shot
extends Node

func _ready() -> void:
	GameState.save_path = "user://save_as_letter_shot.json"
	GameState.reset_save()
	GameState.current_level_id = "0001"
	GameState.current_row = "L"
	GameState.review_letter = false
	var letter: Control = preload("res://scenes/letter/letter_reader.tscn").instantiate()
	add_child(letter)
	await get_tree().process_frame
	await get_tree().process_frame
	if not OS.get_cmdline_user_args().has("shot"):
		get_tree().quit()
		return
	await get_tree().create_timer(0.8).timeout
	RenderingServer.force_draw()
	await get_tree().process_frame
	var img1 := get_viewport().get_texture().get_image()
	img1.save_png("user://letter_shot1.png")
	# 模拟点击两下(推进打字/行), 再截一张
	letter._handle_click()
	await get_tree().create_timer(0.6).timeout
	letter._handle_click()
	await get_tree().create_timer(0.6).timeout
	RenderingServer.force_draw()
	await get_tree().process_frame
	var img2 := get_viewport().get_texture().get_image()
	img2.save_png("user://letter_shot2.png")
	print("saved letter_shot1/2.png size=", img2.get_size())
	print("current_line=", letter.current_line, " typing=", letter.is_typing)
	get_tree().quit()
