# 正式 0001 的存档兼容回归：模拟玩家遇到的空快照，绝不覆盖玩家 save.json。
extends "res://scenes/arrange/arrange_board.gd"

var failures := 0

func _ready() -> void:
	GameState.save_path = "user://first_level_probe_save.json"
	GameState.reset_save()
	GameState.current_level_id = "0001"
	var entry := GameState.row("0001:L")
	entry.achieved = ["S1", "BAD1"]
	entry.current = "BAD1"
	entry.sequence = {"L": []}
	GameState.save_data.total_rep = 4550
	GameState.save_game()
	GameState.load_game()
	GameState.restore_verdict("0001", "L")
	super._ready()
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", description)

func _run() -> void:
	if entrance.playing:
		await entrance.finished
	await get_tree().process_frame
	await get_tree().process_frame
	check(level.is_valid_arrangement(GameState.sequences), "空快照恢复成完整排列")
	check(GameState.total_rep == 4550 and GameState.history["0001"].size() == 2, "保留声望与结局")
	check(_visible_cards() == ["A1", "A2", "A3"], "结算态三张纸条可见")
	_on_retry_pressed()
	if entrance.playing:
		await entrance.finished
	await get_tree().process_frame
	await get_tree().process_frame
	check(can_edit() and _visible_cards() == ["A1", "A2", "A3"], "重试后三张纸条可拖拽")
	# 再现早期版本保存的自动节点名和残缺序列。
	GameState.row("0001:L").sequence = {"L": ["@PanelContainer@91", "A1"]}
	GameState.restore_verdict("0001", "L")
	check(level.is_valid_arrangement(GameState.sequences), "旧自动节点名快照恢复")
	check(RuleEngine.judge(level, {"L": []}).is_empty(), "残缺排列不能继续覆盖存档")
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path := "user://first_level_restored.png"
		get_viewport().get_texture().get_image().save_png(path)
		print("SCREENSHOT: ", ProjectSettings.globalize_path(path))
	GameState.reset_save()
	print("FIRST_LEVEL: 6 checks, %d failures" % failures)
	get_tree().quit(1 if failures else 0)

func _visible_cards() -> Array:
	var ids := []
	for child in left_column.get_children():
		if child is Card and child.is_visible_in_tree() and not child.text_content.is_empty():
			ids.append(child.card_id)
	return ids
