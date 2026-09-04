# tools/title_shot_probe.gd — 标题动画窗口截图验证:
#   三个时间点(0.15s 滑入中 / 0.8s 就位 / 4.2s 淡出后)各截一张,
#   用像素检查标题「黑伞」在文字区左上角的位置与可见性。
# 用法: godot --path . res://tools/title_shot_probe.tscn -- shot
extends Node

func _ready() -> void:
	GameState.save_path = "user://save_as_title_shot.json"
	GameState.reset_save()
	LevelData.overrides["t03"] = {
		"level_id": "t03", "title": "t03", "subtitle": "", "row_count": 1, "unlock": "",
		"rows": [{
			"id": "L", "title": "t03", "monologue": "", "character": "yf",
			"position": "0,3", "previous": "start",
			"blocks": [{"id": "PanelA1", "text": "正文一行"}],
			"strips": [],
			"variants": [],
			"readonly": [{"id": "Panel0", "text": "黑伞\n第二行"}]
		}],
		"endings": {}, "conditions": []
	}
	GameState.current_level_id = "t03"
	GameState.current_row = "L"
	GameState.review_letter = false
	var letter: Control = preload("res://scenes/letter/letter_reader.tscn").instantiate()
	add_child(letter)
	await get_tree().process_frame
	if not OS.get_cmdline_user_args().has("shot"):
		print("title size=", letter._title_label.size, " min=", letter._title_label.custom_minimum_size,
			" visible=", letter._title_label.visible, " pos=", letter._title_label.position)
		get_tree().quit()
		return
	# t=0.15s: 滑入进行中(标题在文字区左上角左侧)
	await get_tree().create_timer(0.15).timeout
	RenderingServer.force_draw()
	await get_tree().process_frame
	_save("user://title_shot1.png", letter)
	# t=0.8s: 滑入完成, 标题就位
	await get_tree().create_timer(0.65).timeout
	RenderingServer.force_draw()
	await get_tree().process_frame
	_save("user://title_shot2.png", letter)
	# t=4.2s: 3 秒后已淡出
	await get_tree().create_timer(3.4).timeout
	RenderingServer.force_draw()
	await get_tree().process_frame
	_save("user://title_shot3.png", letter)
	get_tree().quit()

func _save(path: String, letter: Control) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path, " title_pos=", letter._title_label.position, " a=%.2f" % letter._title_label.modulate.a)
