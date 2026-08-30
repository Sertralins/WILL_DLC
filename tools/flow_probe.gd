# tools/flow_probe.gd — headless 流程集成冒烟(观察者挂在 root 下, 不随 change_scene 销毁):
#   A. 进读信场景 → 模拟点完全部行 → 点「继续」→ 验证切到了 recap 场景;
#   B. recap 拖拽方向(页面跟随指针: 上拖 300 → scroll_vertical +300)、滚轮(上滚 -100);
#   C. 已解锁结局的关卡再进入 → 直接到排布场景(不经读信)。
# 用法: godot --headless res://tools/flow_probe.tscn --quit-after 600
# 存档隔离到 user://flow_probe_save.json, 不碰真实进度, 结束自动删除。
extends Node

class Watcher extends Node:
	func run() -> void:
		_watch.call_deferred()

	func _watch() -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		# —— A. 读信 → 继续 → recap ——
		var letter = get_tree().current_scene
		print("scene after goto letter: ", letter.name)
		# 模拟点击: 打字中→整行显示, 行完→下一行, 页完→翻页, 全部完→按钮浮现
		for i in 300:
			await get_tree().process_frame
			await get_tree().process_frame
			if not is_instance_valid(letter):
				break
			if letter.start_button.visible:
				break
			letter._handle_click()
		print("button visible: ", letter.start_button.visible, " text='", letter.start_button.text, "' size=", letter.start_button.size)
		letter._on_start_button_pressed()
		for i in 5:
			await get_tree().process_frame
		var recap = get_tree().current_scene
		print("scene after continue: ", recap.name, " (", recap.get_class(), ")")
		print("FLOW-OK" if recap.name == "Recap" else "FLOW-FAIL")

		# —— B. 拖拽/滚轮方向(headless 视口 1920 方形, 先垫高内容使其可滚动) ——
		var scroll: ScrollContainer = recap.scroll
		var margin: MarginContainer = scroll.get_child(0)
		var box: VBoxContainer = margin.get_child(0)
		for i in 40:
			var pad := Label.new()
			pad.custom_minimum_size = Vector2(100, 100)
			box.add_child(pad)
		await get_tree().process_frame
		scroll.scroll_vertical = 500
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = Vector2(960, 700)
		recap._on_drag_input(press)
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(960, 400)   # 向上拖 300
		recap._on_drag_input(motion)
		var v1: int = scroll.scroll_vertical
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = Vector2(960, 400)
		recap._on_drag_input(release)
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		wheel.position = Vector2(960, 400)
		recap._on_drag_input(wheel)
		var v2: int = scroll.scroll_vertical
		print("drag up 300 -> scroll=", v1, " (expect 800); wheel up -> scroll=", v2, " (expect 700)")
		print("DRAG-OK" if v1 == 800 and v2 == 700 else "DRAG-FAIL")

		# —— C. 已解锁结局的关卡再进入 → 直接到排布 ——
		GameState.row("0001:L")["achieved"] = ["S1"]
		GameState.save_game()
		GameState.history["0001"] = ["S1"]
		GameFlow.goto("map")
		for i in 5:
			await get_tree().process_frame
		var map = get_tree().current_scene
		map._enter_level("0001:L")
		for i in 5:
			await get_tree().process_frame
		var cur = get_tree().current_scene
		print("scene after re-enter completed level: ", cur.name, " (", cur.get_class(), ")")
		print("DIRECT-ARRANGE-OK" if cur.name == "Main" else "DIRECT-ARRANGE-FAIL")

		# —— D. 结算态排布画面: 白底/按钮只剩两个/每栏 Rank/条件句染角色色 ——
		GameState.verdicts = {
			"level_id": "0001", "ending_id": "S1", "rank": "S", "rep": 325,
			"matched_index": 0, "changes": [{"type": "REPLACE", "data": "PanelB2_1"}],
		}
		GameFlow.goto("arrange")
		for i in 5:
			await get_tree().process_frame
		var arr = get_tree().current_scene
		var cond: PanelContainer = arr.find_child("PanelB2", true, false)
		var cond_bg: Color = cond.get_theme_stylebox("panel").bg_color if cond else Color.TRANSPARENT
		print("locked ui: white=", arr.white_bg.visible, " retry=", arr.retry_btn.visible,
			" decide=", arr.decide_btn.visible, " rankL=", arr.rank_tags[0].visible,
			" rankR=", arr.rank_tags[1].visible, " rankM=", arr.rank_tags[2].visible,
			" cond_bg=", cond_bg)
		var ok_d: bool = arr.white_bg.visible and arr.retry_btn.visible and not arr.decide_btn.visible \
			and arr.rank_tags[0].visible and arr.rank_tags[1].visible and not arr.rank_tags[2].visible \
			and cond_bg.a > 0.5 and cond_bg.a < 0.8 and cond_bg.g > cond_bg.b   # qyy 橄榄绿, 半透明
		print("LOCKED-OK" if ok_d else "LOCKED-FAIL")

		# —— E. 「再试一次」解除锁定 ——
		arr._on_retry_pressed()
		await get_tree().process_frame
		var ok_e: bool = not arr.white_bg.visible and not arr.retry_btn.visible and arr.decide_btn.visible \
			and not arr.rank_tags[0].visible
		print("retry: white=", arr.white_bg.visible, " retry=", arr.retry_btn.visible,
			" decide=", arr.decide_btn.visible, " rankL=", arr.rank_tags[0].visible)
		print("RETRY-OK" if ok_e else "RETRY-FAIL")

		# 清理隔离存档
		if FileAccess.file_exists(GameState.save_path):
			DirAccess.remove_absolute(GameState.save_path)
		get_tree().quit()

func _ready() -> void:
	# 存档隔离: 冒烟期间读写的都是探针自己的存档, 不碰真实进度
	GameState.save_path = "user://flow_probe_save.json"
	if FileAccess.file_exists(GameState.save_path):
		DirAccess.remove_absolute(GameState.save_path)
	GameState.load_game()
	GameState.current_level_id = "0001"
	GameState.current_row = "L"
	GameState.review_letter = false
	var watcher := Watcher.new()
	watcher.name = "FlowWatcher"
	get_tree().root.add_child.call_deferred(watcher)   # _ready 里场景树正忙, 入树也必须延迟
	watcher.run.call_deferred()
	GameFlow.goto.call_deferred("letter")   # 同上
