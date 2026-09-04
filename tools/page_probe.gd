# tools/page_probe.gd — 读信排版验证:
#   [page] 换页标记 / 行按页行数垂直居中 / Panel0 第一行标题(左移进入+下划线+3秒消失)
#   / 最后一页最后一行(落款)右对齐
# 用法: godot --headless --path . res://tools/page_probe.tscn
extends Node

func _ready() -> void:
	GameState.save_path = "user://save_as_page_probe.json"
	GameState.reset_save()
	var long_lines: String = ""
	for i in 20:
		long_lines += "第%d行\n" % i
	LevelData.overrides["t02"] = {
		"level_id": "t02", "title": "t02", "subtitle": "", "row_count": 1, "unlock": "",
		"rows": [{
			"id": "L", "title": "换页", "monologue": "", "character": "yf",
			"position": "0,3", "previous": "start",
			"blocks": [
				{"id": "PanelA1", "text": "第一页[br]第二行[br][page]第二页开头[page]第三页"},
				{"id": "PanelA2", "text": long_lines + "[right]寄信人：小明"}
			],
			"strips": [
				{"id": "C1", "text": "字条文字不该出现在首次阅读里"}
			],
			"variants": [],
			"title_block": {"text": "黑伞"},
			"readonly": [
				{"id": "Panel0_1", "text": "黑伞\n（这是标题下的正文）"}
			]
		}],
		"endings": {}, "conditions": []
	}
	GameState.current_level_id = "t02"
	GameState.current_row = "L"
	GameState.review_letter = false
	var letter: Control = preload("res://scenes/letter/letter_reader.tscn").instantiate()
	add_child(letter)
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. 连续排页(句子合并同页, [page] 强制换页)与居中
	print("pages 数 = ", letter.pages.size())
	var first_text := ""
	for p in letter.pages:
		first_text += String(p) + "|"
	print("连续排页正确 = ", str(letter.pages.size() == 3
		and String(letter.pages[0]).contains("黑伞")
		and String(letter.pages[0]).contains("第一页")
		and String(letter.pages[1]) == "第二页开头"))
	print("字条文字隐藏 = ", str(not first_text.contains("字条文字不该出现在首次阅读里")))
	var lines_box: Control = letter.get_node("MarginContainer/Lines")
	var lh: float = letter.LINE_HEIGHT
	var first_row: Control = lines_box.get_child(0) as Control
	var expect_off := maxf((lines_box.size.y - letter.line_labels.size() * lh) / 2.0, 0.0)
	print("按页行数居中 = ", str(absf(first_row.offset_top - expect_off) < 1.0))

	# 2. Panel0 标题: 左移进入 + 3 秒后消失
	print("标题页 = ", letter._title_page, " 标题 = ", letter._title_label.text if letter._title_label else "-")
	print("标题来自 title_block 模块 = ", str(letter._title_page == 0))
	print("标题可见+下划线 = ", str(letter._title_label != null and letter._title_label.visible
		and letter._title_label.text.begins_with("[u]黑伞[/u]")))
	var x0: float = letter._title_label.position.x
	await get_tree().create_timer(1.0).timeout
	var x1: float = letter._title_label.position.x
	print("标题左移进入 = ", str(x0 < x1 and letter._title_label.visible))
	await get_tree().create_timer(3.6).timeout
	print("标题 3 秒后消失 = ", str(not letter._title_label.visible))

	# 3.5 [page] 翻页点击次数: 行尾空行([br][page])不消耗点击, 翻页一下即可
	letter._show_page(0)
	await get_tree().process_frame
	var clicks := 0
	while letter.current_page_index < 1 and clicks < 30:
		letter._handle_click()
		clicks += 1
	# 首页 4 行内容: 每行 2 次点击 = 8, 第 9 次翻页(同时跳过行尾空行、开始下一页打字)
	print("翻 1 页点击数 = ", clicks, "(期望 9)")
	print("翻页一下 = ", str(clicks == 9))

	# 4. 落款右对齐(最后一页最后一行 = 寄信人)
	letter._show_page(letter.pages.size() - 1)
	await get_tree().process_frame
	await get_tree().process_frame
	var sig: Label = null
	for j in range(letter.line_labels.size() - 1, -1, -1):
		if letter.line_labels[j].text != "":
			sig = letter.line_labels[j]
			break
	print("落款行文本 = ", sig.text if sig else "-")
	print("落款右对齐 = ", str(sig != null and sig.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT))
	print("right 标记剔除 = ", str(sig != null and not sig.text.contains("right") and not sig.text.contains("u001e")))
	get_tree().quit()
