# tools/decide_probe.gd — 「决定」双击/二连点排查:
#   A(-- bad): 初始排列双击决定 → 切场景后检查新排布场景的块是否完整
#   B(-- s1):  对调字条双击决定 → 转钟 7s 后检查
#   C(-- cycle): 决定 → 再试一次 → 再决定 → 检查
# 用法: godot --headless --path . res://tools/decide_probe.tscn [-- bad|-- s1|-- cycle]
extends Node

class Watcher extends Node:
	var s1_cycle := false

	func run() -> void:
		_watch.call_deferred()

	func _watch() -> void:
		await get_tree().create_timer(7.0).timeout
		var scene := get_tree().current_scene
		print("scene=", scene.name if scene else "?")
		if scene and scene.has_method("_handle_click") and not scene.start_button.visible:
			# S1 循环: 点穿重放信件 → 回排布锁定 → 再试一次 → 再决定
			for i in 300:
				await get_tree().process_frame
				await get_tree().process_frame
				if not is_instance_valid(scene):
					break
				if scene.start_button.visible:
					break
				scene._handle_click()
			if is_instance_valid(scene) and scene.start_button.visible:
				scene._on_start_button_pressed()
				await get_tree().create_timer(0.6).timeout
				var arr := get_tree().current_scene
				if arr and arr != scene and arr.has_method("_on_retry_pressed"):
					print("回排布 locked=", arr.locked)
					arr._on_retry_pressed()
					await get_tree().create_timer(0.5).timeout
					var arr2 := get_tree().current_scene
					if arr2 and arr2 != arr and arr2.has_method("_on_execute_pressed"):
						print("第二次决定前 unlocked=", str(not arr2.locked))
						arr2.decide_btn.pressed.emit()
		await get_tree().create_timer(1.5).timeout
		var final := get_tree().current_scene
		if final and final is Control and "left_column" in final:
			var col: VBoxContainer = final.left_column
			var kinds: Array = []
			for c in col.get_children():
				if c is PanelContainer and not (c is Card):
					kinds.append("块:" + String(c.name))
				elif c is Card:
					kinds.append("字条:" + c.card_id)
			print("最终 L栏 = ", kinds, " locked=", final.locked)
			var missing: Array = []
			for n in ["PanelA1", "PanelA2"]:
				if final.find_child(n, true, false) == null:
					missing.append(n)
			print("缺失块 = ", missing if missing else "无")
		else:
			print("最终场景 = ", final.name if final else "?")
		get_tree().quit()

func _ready() -> void:
	GameState.save_path = "user://save_as_decide_probe.json"
	GameState.reset_save()
	GameState.current_level_id = "0001"
	var board: Control = preload("res://scenes/arrange/arrange_board.tscn").instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	var watcher := Watcher.new()
	get_tree().root.add_child(watcher)
	watcher.run()
	if OS.get_cmdline_user_args().has("s1"):
		# 对调 A3 提到 A1 上 → SS(A3,A1,A2) 命中 S1(新结局转钟)
		var lc: VBoxContainer = board.left_column
		var cards: Array = []
		for c in lc.get_children():
			if c is Card:
				cards.append(c)
		if cards.size() >= 3:
			lc.move_child(cards[2], cards[0].get_index())
	if OS.get_cmdline_user_args().has("cycle"):
		# 决定 → 再试一次 → 再决定
		board.decide_btn.pressed.emit()
		await get_tree().create_timer(0.8).timeout
		var scene1 := get_tree().current_scene
		if scene1 and scene1 != board:
			scene1.retry_btn.pressed.emit()
			await get_tree().create_timer(0.5).timeout
			var scene2 := get_tree().current_scene
			if scene2 and scene2 != scene1:
				scene2.decide_btn.pressed.emit()
		return
	# 双击: 同一帧连发两次(模拟快速二连点)
	board.decide_btn.pressed.emit()
	board.decide_btn.pressed.emit()
