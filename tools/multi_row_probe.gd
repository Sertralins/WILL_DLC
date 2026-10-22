extends "res://scenes/arrange/arrange_board.gd"

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func _ready() -> void:
	GameState.save_path = "user://multi_row_probe_save.json"
	GameState.reset_save()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://templates/三人独立结局示例.json"))
	LevelData.overrides[data.level_id] = data
	GameState.current_level_id = data.level_id
	var lv := LevelData.load_level(data.level_id)
	var validator := preload("res://scripts/core/level_validator.gd").new()
	validator.quiet = true
	check(validator.validate_data(data, LevelData.load_characters()) == 0, "三行独立结局定义通过校验")
	var broken := data.duplicate(true)
	broken.rows[2].erase("endings")
	check(validator.validate_data(broken, LevelData.load_characters()) > 0, "拒绝缺少第三行结局")
	var invalid_data := data.duplicate(true)
	invalid_data.rows[2].conditions = [{"expr": "IN(M,missing)", "ending": "S1"}]
	LevelData.overrides["incomplete_probe"] = invalid_data
	var invalid_level := LevelData.load_level("incomplete_probe")
	check(RuleEngine.judge(invalid_level, invalid_level.initial_arrangement()).is_empty() and GameState.history.is_empty(), "有一行无结果时整次决定不写入进度")
	LevelData.overrides.erase("incomplete_probe")
	var two := data.duplicate(true)
	two.level_id = "independent_dual"
	two.rows.pop_back()
	two.row_count = 2
	two.rows[0].conditions[0].expr = "SS(A2,A1)"
	LevelData.overrides[two.level_id] = two
	var two_level := LevelData.load_level(two.level_id)
	var two_seq := two_level.initial_arrangement()
	two_seq.L = ["PanelA1", "A2", "A1", "PanelA2"]
	var preview := RuleEngine.evaluate(two_level, two_seq)
	check(preview.rows.L.rank == "S" and preview.rows.R.rank == "Bad", "双人也支持独立结局")
	LevelData.overrides.erase(two.level_id)
	var seq := lv.initial_arrangement()
	var save_path := GameState.save_path
	GameState.save_path = "user://missing_probe_%d/save.json" % Time.get_ticks_usec()
	check(RuleEngine.judge(lv, seq).is_empty() and GameState.history.is_empty() and GameState.total_rep == 0 and GameState.verdicts.is_empty(), "保存失败时不提交半份结局或奖励")
	GameState.save_path = save_path
	var result := RuleEngine.judge(lv, seq)
	check(result.rows.size() == 3 and result.rows.L.ending_id == "BAD1" and GameState.total_rep == 0, "初始排列三个独立Bad")
	seq.L.erase("A1")
	seq.M.insert(1, "A1")
	result = RuleEngine.judge(lv, seq)
	check(result.rows.L.rank == "S" and result.rows.R.rank == "Bad" and result.rows.M.rank == "Bad", "一行成功不覆盖另外两行")
	check(not GameState.sranks.has(data.level_id), "仅一行S不算整关SRANK")
	check(GameState.total_rep == 100 and RuleEngine.affected_rows(lv, result) == ["L"], "只奖励与重放新增行结局")
	seq.R = ["PanelB1", "B2", "B1", "PanelB2"]
	seq.M = ["PanelC1", "A1", "C2", "C1", "PanelC2"]
	result = RuleEngine.judge(lv, seq)
	check(result.rows.R.is_new and result.rows.M.is_new and not result.rows.L.is_new, "相同S1标识按行分别解锁")
	check(GameState.sranks.has(data.level_id), "三行均获S恢复整关SRANK")
	check(GameState.total_rep == 600 and result.awarded_rep == 500, "多行奖励正确累计")
	check(RuleEngine.affected_rows(lv, result) == ["R", "M"], "演出队列只含本次新增且变化的行")
	RuleEngine.judge(lv, seq)
	check(GameState.total_rep == 600, "重复决定不重复奖励")
	check(not GameState.row("three_person_demo:L").has("sequence") and GameState.save_data.levels.three_person_demo.sequence == seq, "排列只在整关保存一次")
	GameState.load_game()
	GameState.current_level_id = data.level_id
	GameState.restore_verdict(data.level_id, "M")
	check(GameState.verdicts.rows.size() == 3 and GameState.sequences == seq and GameState.total_rep == 600, "重启从M入口恢复整关三行结果和排列")
	check(ConditionEngine.evaluate("CURRENT(three_person_demo,2,S1)", {"world_state": GameState.world_state()}), "M行跨关当前结局查询")
	check(GameState.row_history("three_person_demo:M").has("S1"), "逐行历史索引")
	GameState.retry_arrangement()
	GameState.reset_arrangement()
	super._ready()
	_run.call_deferred()

func _run() -> void:
	if entrance.playing:
		await entrance.finished
	check(can_edit() and middle_column.visible and _columns().size() == 3, "三栏可编辑")
	check(left_column.position.x < middle_column.position.x and middle_column.position.x < right_column.position.x, "视觉顺序L-M-R")
	check(right_column.position.x == 1260 and right_column.size.x == 480 and left_column.position == Vector2(180, 70), "三栏尺寸位置匹配参考图")
	var card: Card
	for child in left_column.get_children():
		if child is Card and child.card_id == "A1":
			card = child
	card.origin_slot = left_column
	card.origin_index = card.get_index()
	card.hide()
	var point := middle_column.global_position + Vector2(20, middle_column.get_node("PanelC2").position.y + 1)
	check(_target_column(card, point) == middle_column and _route_preview(card, point), "第三栏正常吸附")
	_route_drop(card, point)
	check(card.get_parent() == middle_column and not get_sequence_ids(left_column).has("A1"), "纸条跨入M栏且无副本")
	card.origin_slot = middle_column
	card.hide()
	point = right_column.global_position + Vector2(20, 1)
	check(not _route_preview(card, point), "第三栏纸条向非法位置拖动被拒绝")
	_route_drop(card, point)
	check(card.get_parent() == middle_column and card.visible, "非法松手归还M栏")
	_on_reset_pressed()
	if entrance.playing:
		await entrance.finished
	check(get_sequence_ids(middle_column) == level.layout_sequence(level.row_by_id("M")), "原始状态恢复第三栏")
	var seq := level.initial_arrangement()
	seq.L.erase("A1")
	seq.M.insert(1, "A1")
	RuleEngine.judge(level, seq)
	_apply_level()
	if entrance.playing:
		await entrance.finished
	check(locked and rank_tags[0].texture != rank_tags[1].texture, "结算各栏使用独立评级")
	for i in level.rows.size():
		var tag := rank_tags[i]
		check((tag.position + tag.pivot_offset).is_equal_approx(TRIPLE_RANK_CENTERS[level.rows[i].id]) and tag.size.is_equal_approx(Vector2(360, 160)), "结局章按行定位到参考白底画面")
	check(left_column.get_node("PanelA2").find_child("Text", true, false).text.contains("圆满"), "L结局变化应用到L")
	check(right_column.get_node("PanelB2").find_child("Text", true, false).text.contains("没有结果"), "R未被L结局污染")
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://three_person_result.png")
	_on_retry_pressed()
	if entrance.playing:
		await entrance.finished
	check(can_edit() and get_sequence_ids(middle_column).has("A1"), "三人再试保留排列并解锁")
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://three_person_arrange.png")
	GameState.reset_save()
	LevelData.overrides.erase("three_person_demo")
	print("MULTI_ROW: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
