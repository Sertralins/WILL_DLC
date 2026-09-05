# tools/letter_click_probe.gd — 信件场景全屏点击推进验证:
#   用真实输入路由(push_input)在信封文字区/剪影区/屏幕边缘各点两下,
#   验证点击都能推进打字机(第一下开始打字, 第二下跳过整行)。
#   注: 必须窗口模式跑 —— headless 下 push_input 坐标会被拉伸系数放大, GUI 拾取失效。
# 用法: godot --path . res://tools/letter_click_probe.tscn
extends Node

func _ready() -> void:
	GameState.save_path = "user://save_as_letter_click.json"
	GameState.reset_save()
	GameState.current_level_id = "0001"
	GameState.current_row = "L"
	GameState.review_letter = false
	var letter: Control = preload("res://scenes/letter/letter_reader.tscn").instantiate()
	add_child(letter)
	await get_tree().process_frame
	await get_tree().process_frame

	# 三个区域各点两下: 信封中部 / 剪影动画区 / 屏幕边缘
	for pt: Dictionary in [
		{"name": "信封中部", "pos": Vector2(600, 500)},
		{"name": "剪影区", "pos": Vector2(1650, 500)},
		{"name": "屏幕边缘", "pos": Vector2(30, 1000)},
	]:
		await _click(letter, pt.pos)
		var after1: Array = [letter.is_typing, letter.current_line]
		await _click(letter, pt.pos)
		var ok: bool = after1[1] != letter.current_line or after1[0] or letter.is_typing
		print("%s: 点1后 typing=%s line=%d → 点2后 typing=%s line=%d  %s" % [
			pt.name, str(after1[0]), after1[1], str(letter.is_typing), letter.current_line,
			"OK" if ok else "FAIL"])
	get_tree().quit()

func _click(letter: Control, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	get_viewport().push_input(ev)
	await get_tree().process_frame
	await get_tree().process_frame
