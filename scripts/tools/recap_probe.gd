# tools/recap_probe.gd — 回顾页冒烟/视觉验证(注意: PrintWindow 截 D3D12 窗口会拿到陈旧帧, 不可用):
#   无参数: 实例化 recap, 等 3 帧后把场景树/按钮几何打印到 stdout 后退出
#   -- shot [state1|state2|state3]: 等 60 帧(背景渐入完成后)用引擎自身截图存 user://recap_shot.png 后退出
#     state1 = 首次进入+第一封信(三按钮); state2 = 非首次进入(四按钮); state3 = 首次进入+第二封信(四按钮)
extends Control

func _ready() -> void:
	GameState.current_level_id = "0001"
	GameState.current_row = "L"
	GameState.first_entry_level = false
	var args := OS.get_cmdline_user_args()
	if "state1" in args:      # 首次进入 + 第一封信 → 只有 另一封/回想/返回
		GameState.first_entry_level = true
	elif "state3" in args:    # 首次进入 + 第二封信 → 顶部多「开始!」
		GameState.current_row = "R"
		GameState.first_entry_level = true
	var recap: Control = load("res://scenes/recap/recap.tscn").instantiate()
	add_child(recap)
	if "shot" in args:
		for i in 60:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://recap_shot.png")
		print("saved user://recap_shot.png size=", img.get_size())
		get_tree().quit()
		return
	for i in 3:
		await get_tree().process_frame
	_dump(recap, 0)
	get_tree().quit()

func _dump(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	var line := "%s%s" % [indent, node.get_class()]
	if node is Control:
		var c: Control = node
		line += " pos=%s size=%s" % [c.position, c.size]
		if c is TextureButton:
			var tb: TextureButton = c
			line += " tex=%s vis=%s" % [tb.texture_normal != null, c.visible]
		if c is Label:
			line += " text=%s" % String(c.text).substr(0, 8)
	print(line)
	for child in node.get_children():
		_dump(child, depth + 1)
