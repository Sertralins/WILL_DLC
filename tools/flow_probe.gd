# 独立单人/双人流程回归；不依赖正式关卡、不读写玩家存档。
# Watcher 挂在 root 下，切换场景时不会随旧场景销毁。
extends Node

const Fixtures := preload("res://tools/test_fixtures.gd")

func _ready() -> void:
	GameState.save_path = "user://flow_probe_save.json"
	GameState.reset_save()
	LevelData.overrides["flow_single"] = Fixtures.level_data("flow_single")
	LevelData.overrides["flow_dual"] = Fixtures.level_data("flow_dual", true)
	var watcher := Watcher.new()
	get_tree().root.add_child.call_deferred(watcher)

class Watcher extends Node:
	var failures := 0
	var checks := 0

	func _ready() -> void:
		get_tree().create_timer(80).timeout.connect(func():
			printerr("FLOW TIMEOUT")
			get_tree().quit(2))
		run.call_deferred()

	func check(ok: bool, label: String) -> void:
		checks += 1
		if not ok:
			failures += 1
			printerr("FAIL: ", label)

	func frames(count := 4) -> void:
		for i in count:
			await get_tree().process_frame

		var current := get_tree().current_scene
		if current and current.get("entrance") != null and current.entrance.playing:
			await current.entrance.finished

	func scene(key: String) -> Node:
		GameFlow.goto(key)
		await frames()
		return get_tree().current_scene

	func finish_letter(letter: Node) -> void:
		for i in 100:
			if letter.start_button.visible:
				break
			letter._handle_click()
			await frames(2)
		check(letter.start_button.visible, "信件可读完")
		letter._on_start_button_pressed()
		await frames()

	func run() -> void:
		for id in ["flow_single", "flow_dual"]:
			await check_flow(id)
		await check_map_reentry()
		await check_three_flow()
		GameState.reset_save()
		LevelData.overrides.clear()
		print("FLOW: %d checks, %d failures" % [checks, failures])
		get_tree().quit(1 if failures else 0)

	func check_flow(id: String) -> void:
		GameState.reset_save()
		GameState.current_level_id = id
		GameState.first_entry_level = true
		var level := LevelData.load_level(id)
		var letter := await scene("letter")
		await finish_letter(letter)
		var recap = get_tree().current_scene
		check(recap.name == "Recap", "读信进入回顾")
		check(GameState.row_read(id + ":L"), "阅读落盘")
		check(recap._show_start() == (level.rows.size() == 1), "首次阅读开始按钮规则")
		await check_scroll(recap)
		if level.rows.size() == 2:
			recap._on_other_letter()
			await frames()
			check(GameState.current_row == "R", "另一封切换右行")
			await finish_letter(get_tree().current_scene)
			check(get_tree().current_scene._show_start(), "第二封读完可开始")
		var board = await scene("arrange")
		check(board.can_edit(), "初始可编辑")
		check(board.right_column.visible == (level.rows.size() == 2), "单人/双人栏目")
		var card: Card = null
		for child in board.left_column.get_children():
			if child is Card and child.card_id == "A1":
				card = child
		check(card != null, "生成 A1 字条")
		if card == null:
			return
		card.origin_slot = board.left_column
		card.origin_index = card.get_index()
		board.left_column.update_preview_gap(card, Vector2(10, board.left_column.get_node("PanelA2").position.y + 1))
		board.left_column.receive_drop(card, Vector2(10, board.left_column.get_node("PanelA2").position.y + 1))
		await frames()
		check(board.get_sequence_ids(board.left_column) == ["PanelA1", "A2", "A1", "PanelA2"], "同栏预览落位顺序")
		if level.rows.size() == 2:
			board.right_column.receive_drop(card, Vector2(10, 100))
			await frames()
			check(card.get_parent() == board.right_column, "跨栏落位")
			check(card.card_id == "A1", "跨栏保持身份")
			board.left_column.receive_drop(card, Vector2(10, board.left_column.get_node("PanelA2").position.y + 1))
			await frames()
		else:
			check(board._target_column(card, Vector2(1, 200)) == null, "单人栏外无效落点")
		# 实际启动决定及五秒演出，而非只手动设置锁定字段。
		board._on_execute_pressed()
		await frames()
		check(board._deciding and card.locked and not board.can_edit(), "决定期间冻结输入")
		check(card._get_drag_data(Vector2.ZERO) == null, "冻结卡片不能拖起")
		var saved: Dictionary = GameState.sequences.duplicate(true)
		board._on_execute_pressed()
		board._on_back_pressed()
		board._on_reset_pressed()
		board._on_retry_pressed()
		board.left_column.receive_drop(card, Vector2.ZERO)
		check(GameState.total_rep == 325 and GameState.sequences == saved, "重复操作不改变判定或奖励")
		check(get_tree().current_scene == board, "倒计时返回被阻止")
		# 包含读秒后的停顿与淡出，按场景完成等待而不是猜固定时长。
		var deadline := Time.get_ticks_msec() + 9000
		while is_instance_valid(board) and Time.get_ticks_msec() < deadline:
			await get_tree().create_timer(0.1).timeout
		check(get_tree().current_scene.name == "LetterReader", "新结局进入重放")
		if get_tree().current_scene.name != "LetterReader":
			return
		await finish_letter(get_tree().current_scene)
		board = get_tree().current_scene
		check(board.name == "Main" and board.locked, "重放回到锁定界面")
		check(board.white_bg.visible and board.retry_btn.visible and not board.decide_btn.visible, "结算背景及按钮")
		for i in 3:
			check(board.rank_tags[i].visible == (i < level.rows.size()), "按实际行数显示评级")
		var block = board.left_column.get_node("PanelA2")
		var color: Color = block.get_theme_stylebox("panel").bg_color
		check(color.a > 0.85 and color.r > color.g, "条件块使用伊芙颜色")
		board._on_execute_pressed()
		check(GameState.total_rep == 325, "结算锁定态不可重复决定")
		board._on_retry_pressed()
		await frames()
		check(board.can_edit() and board.get_sequence_ids(board.left_column) == saved.L, "重试保留排列并解锁")
		board._on_execute_pressed()
		await frames()
		board = get_tree().current_scene
		check(board.name == "Main" and board.locked and GameState.total_rep == 325, "重复结局跳过演出且不奖励")
		# 删除只作用于结算展示，重试恢复完整排列。
		GameState.verdicts.changes = [{"type": "DRA", "data": "A1"}]
		board = await scene("arrange")
		check(not board.get_sequence_ids(board.left_column).has("A1"), "结算隐藏被删除字条")
		board._on_retry_pressed()
		await frames()
		check(board.get_sequence_ids(board.left_column).has("A1"), "重试恢复被删除字条")

	func check_scroll(recap: Node) -> void:
		var box = recap.scroll.get_child(0).get_child(0)
		for i in 30:
			var spacer := Control.new()
			spacer.custom_minimum_size.y = 100
			box.add_child(spacer)
		await frames()
		recap.scroll.scroll_vertical = 500
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = Vector2(960, 700)
		recap._on_drag_input(press)
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(960, 400)
		recap._on_drag_input(motion)
		check(recap.scroll.scroll_vertical == 800, "回顾上拖向信尾滚动")
		press.pressed = false
		recap._on_drag_input(press)
		press.button_index = MOUSE_BUTTON_WHEEL_UP
		press.pressed = true
		recap._on_drag_input(press)
		check(recap.scroll.scroll_vertical == 700, "滚轮上滚向信首")

	func check_map_reentry() -> void:
		GameState.load_game()  # 显式模拟重启；正常回地图不重新读磁盘。
		GameState.current_level_id = "flow_dual"
		var map = await scene("map")
		# 注入节点只测进入逻辑，不将 fixture 加入正式关卡索引。
		map.nodes["flow_dual:L"] = {"level_id": "flow_dual", "row_id": "L"}
		map._enter_level("flow_dual:L")
		await frames()
		var board = get_tree().current_scene
		check(board.name == "Main" and board.locked, "地图重进已完成关卡恢复锁定态")
		check(GameState.sranks.has("flow_dual"), "地图读档后保留 S")


	func check_three_flow() -> void:
		GameState.reset_save()
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://templates/三人独立结局示例.json"))
		LevelData.overrides[data.level_id] = data
		GameState.enter_level(data.level_id, "L")
		await scene("letter")
		for i in 3:
			await finish_letter(get_tree().current_scene)
			var recap = get_tree().current_scene
			check(recap._show_start() == (i == 2), "三人首次需读完三封信才开始")
			if i < 2:
				recap._on_other_letter()
				await frames()
		var board = await scene("arrange")
		var lv := LevelData.load_level(data.level_id)
		var seq := lv.initial_arrangement()
		seq.L.erase("A1")
		seq.R = ["PanelB1", "B2", "B1", "PanelB2"]
		seq.M = ["PanelC1", "A1", "C2", "C1", "PanelC2"]
		GameState.sequences = seq
		GameState.sequences_level = data.level_id
		board._apply_level()
		await frames()
		board._on_execute_pressed()
		check(GameState.verdicts.rows.size() == 3 and board._deciding, "三人决定进入统一判定阶段")
		var deadline := Time.get_ticks_msec() + 9000
		while is_instance_valid(board) and Time.get_ticks_msec() < deadline:
			await get_tree().create_timer(0.1).timeout
		for row_id in ["L", "R", "M"]:
			check(GameState.review_letter and GameState.current_row == row_id, "按行顺序播放新增结局")
			var letter = get_tree().current_scene
			check(letter.name == "LetterReader", "进入逐行信件演出")
			if letter.name != "LetterReader":
				return
			await finish_letter(letter)
		board = get_tree().current_scene
		check(board.locked and GameState.session.phase == GameState.Session.Phase.RESULT and GameState.review_queue.is_empty(), "三行重放结束恢复结算且清空队列")
		board._on_retry_pressed()
		await frames()
		board._on_execute_pressed()
		await frames()
		check(get_tree().current_scene.name == "Main" and GameState.total_rep == 600, "三行重复结局跳过重放且不加声望")
		GameState.load_game()
		var map = await scene("map")
		map.nodes["three_person_demo:M"] = {"level_id": "three_person_demo", "row_id": "M"}
		check(map.ranks_of("three_person_demo:M").has("S1"), "地图读取M行独立历史")
		map._enter_level("three_person_demo:M")
		await frames()
		board = get_tree().current_scene
		check(board.locked and board.middle_column.visible and GameState.sequences == seq, "从地图M入口重启恢复三栏排列")
