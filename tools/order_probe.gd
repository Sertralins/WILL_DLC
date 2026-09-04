# tools/order_probe.gd — 行级 order 字段(块与字条穿插)验证:
#   用 LevelData.overrides 注入一个中间块关卡(块夹在两张字条之间),
#   验证排布场景渲染顺序、CdBar 只挂最后一块、信件初始阅读顺序。
# 用法: godot --headless --path . res://tools/order_probe.tscn
extends Node

func _ready() -> void:
	GameState.save_path = "user://save_as_order_probe.json"
	GameState.reset_save()
	LevelData.overrides["t01"] = {
		"level_id": "t01", "title": "t01", "subtitle": "", "row_count": 2, "unlock": "",
		"rows": [
			{
				"id": "L", "title": "测试行", "monologue": "", "character": "yf",
				"position": "0,3", "previous": "start",
				"blocks": [
					{"id": "PanelA1", "text": "开头框架"},
					{"id": "PanelA2", "text": "结尾条件句块"},
					{"id": "PanelA1_5", "text": "夹在字条中间的固定块"}
				],
				"strips": [
					{"id": "A1", "text": "字条一"},
					{"id": "A2", "text": "字条二"}
				],
				"variants": [
					{"id": "PanelA2_1", "base": "PanelA2", "text": "条件句正文"}
				],
				"readonly": [
					{"id": "Panel0_1", "text": "读信专用旁白"}
				],
				"order": ["Panel0_1", "PanelA1", "A1", "PanelA1_5", "A2", "PanelA2"]
			},
			{
				"id": "R", "title": "右行", "monologue": "", "character": "qyy",
				"position": "-2,5", "previous": "start",
				"blocks": [
					{"id": "PanelB1", "text": "右开头"},
					{"id": "PanelB2", "text": "右结尾"}
				],
				"strips": [{"id": "B1", "text": "右字条"}],
				"variants": [],
				"order": ["PanelB1", "B1", "PanelB2"]
			}
		],
		"endings": {
			"S1": {"rank": "S", "rep": 100, "change": [{"type": "REPLACE", "data": "PanelA2_1"}]},
			"BAD1": {"rank": "Bad", "rep": 0, "change": []}
		},
		"conditions": [
			{"expr": "SS(A1,A2)", "ending": "S1"},
			{"expr": "", "ending": "BAD1", "fallback": true}
		]
	}
	GameState.current_level_id = "t01"
	var board: Control = preload("res://scenes/arrange/arrange_board.tscn").instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. 排布序列: 块与字条穿插, 读信专用句(Panel0)不进交换纸条界面
	var ids: Array[String] = board.get_sequence_ids(board.left_column)
	print("L 序列 = ", ids)
	print("L 序列正确 = ", str(ids == ["PanelA1", "A1", "PanelA1_5", "A2", "PanelA2"]))
	# 2. 子节点类型顺序: Panel/Card/Panel/Card/Panel
	var kinds: Array = []
	for c in board.left_column.get_children():
		kinds.append("Panel" if c is PanelContainer and not (c is Card) else
			("Card" if c is Card else c.get_class()))
	print("L 子节点类型 = ", kinds)
	# 3. CdBar 只挂在各行的最后一个块上(L=PanelA2, R=PanelB2)
	var parents: Array = []
	for b in board._cd_bars:
		parents.append(String(b.get_parent().name))
	print("CdBar 数 = ", board._cd_bars.size(), " 父块 = ", parents,
		" 正确 = ", str(parents == ["PanelA2", "PanelB2"]))
	# 4. 数据层 layout_sequence / initial_sequence(读信专用句只在阅读序列里)
	var lv := LevelData.load_level("t01")
	var row := lv.row_by_id("L")
	print("layout_sequence = ", lv.layout_sequence(row))
	print("layout 无 Panel0 = ", str(not lv.layout_sequence(row).has("Panel0_1")))
	var texts: Array = []
	for s: Dictionary in lv.initial_sequence(row):
		texts.append(String(s.get("text", "")))
	print("阅读顺序 = ", texts)
	print("Panel0 在阅读序列首位 = ", str(texts[0] == "读信专用旁白"))
	print("中间块在两字条之间 = ", str(texts[2] == "字条一" and texts[3] == "夹在字条中间的固定块" and texts[4] == "字条二"))
	# 5. 首次读信: 按 order 完整阅览 readonly + 块 + 字条(逐句成页)
	var letter: Control = preload("res://scenes/letter/letter_reader.tscn").instantiate()
	add_child(letter)
	await get_tree().process_frame
	await get_tree().process_frame
	var first_text := ""
	for p in letter.pages:
		first_text += String(p) + "|"
	print("首次阅读 = ", first_text.replace("\n", "/"))
	# 首次阅读隐藏字条: 只含旁白 + 块(按 order), 字条不在其中
	print("首次阅读顺序正确 = ", str(first_text.contains("读信专用旁白\n开头框架\n夹在字条中间的固定块\n结尾条件句块|")
		and not first_text.contains("字条一") and not first_text.contains("字条二")))
	# 6. 点击决定后的重排阅览: 除去最上边块, 之后 = 字条(排列序) + 块 + 条件句正文
	GameState.sequences = {
		"L": ["PanelA1", "A2", "PanelA1_5", "A1", "PanelA2"],
		"R": ["PanelB1", "B1", "PanelB2"]
	}
	GameState.sequences_level = "t01"
	GameState.verdicts = {"level_id": "t01", "ending_id": "S1", "rank": "S", "rep": 100,
		"matched_index": 0, "changes": [{"type": "REPLACE", "data": "PanelA2_1"}]}
	GameState.review_letter = true
	GameState.current_row = "L"
	var letter2: Control = preload("res://scenes/letter/letter_reader.tscn").instantiate()
	add_child(letter2)
	await get_tree().process_frame
	await get_tree().process_frame
	var review_text := ""
	for p in letter2.pages:
		review_text += String(p) + "|"
	print("阅览文本 = ", review_text.replace("\n", "/"))
	print("阅览无顶部块 = ", str(not review_text.contains("开头框架")))
	print("阅览无旁白 = ", str(not review_text.contains("读信专用旁白")))
	print("阅览跳过字条 = ", str(not review_text.contains("字条一") and not review_text.contains("字条二")))
	print("阅览含中间块+条件句正文 = ", str(review_text.contains("夹在字条中间的固定块\n条件句正文|")
		and not review_text.contains("结尾条件句块")))
	get_tree().quit()

func _all_true(arr: Array, pred: Callable) -> bool:
	for x in arr:
		if not bool(pred.call(x)):
			return false
	return true
