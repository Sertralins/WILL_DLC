# 逻辑回归：只写自己的隔离存档，失败时返回非零退出码。
extends Node

const Fixtures := preload("res://tools/test_fixtures.gd")
const Store := preload("res://scripts/core/save_store.gd")
var failures := 0
var checks := 0

func _ready() -> void:
	GameState.save_path = "user://core_regression_save.json"
	GameState.reset_save()
	LevelData.overrides["test_core"] = Fixtures.level_data("test_core", true)
	_test_parser()
	_test_progress()
	_test_save_recovery()
	_test_changes()
	_test_validation()
	_test_detail_card()
	var errors: int = preload("res://scripts/core/level_validator.gd").new().run()
	check(errors == 0, "正式关卡校验")
	GameState.reset_save()
	LevelData.overrides.clear()
	print("CORE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _test_parser() -> void:
	var ctx := {"triggered": {"T": true, "F": false}, "merged": ["A1", "A2"], "sides": {"L": ["A1"]}}
	for expr in ["", "T", "T||F", "F&&T||T", "(T||F)&&T", "!(F&&T)", "SS(A1,A2)", "IN(L,A1)"]:
		check(ConditionEngine.evaluate(expr, ctx), "真表达式 " + expr)
	for expr in ["F", "T&&F", "(T||F)&&F", "!(T||F)", "OS(A2,A1)"]:
		check(not ConditionEngine.evaluate(expr, ctx), "假表达式 " + expr)
	for expr in ["T&&", "T||", "(T", "T)", "T F", "T&F", "!", "SS()", "SS(A1,)", "BOGUS(A1)", "!BOGUS()", "SRANK()", "CURRENT(0001,9,S1)", "IN(X,A1)"]:
		check(not ConditionEngine.is_valid_expression(expr), "拒绝语法 " + expr)
		check(not ConditionEngine.evaluate(expr, ctx), "非法表达式不命中 " + expr)
	for expr in ["CURRENT(0001,0,S1)", "ELLE(0001,1,S1,BAD1)", "ACHIEVE(0001,0,S1)", "STORY(INTRO)", "READ(0001,0)"]:
		check(ConditionEngine.is_valid_expression(expr), "跨关函数语法 " + expr)

func _test_progress() -> void:
	var level := LevelData.load_level("test_core")
	var seq := Fixtures.initial(level)
	seq.L = ["PanelA1", "A2", "A1", "PanelA2"]
	var preview := RuleEngine.evaluate(level, seq)
	check(preview.ending_id == "S1" and GameState.total_rep == 0, "预览不写进度")
	var first := RuleEngine.judge(level, seq)
	check(first.is_new and first.awarded_rep == 325 and GameState.total_rep == 325, "首次奖励")
	check(GameState.last_save_error == OK, "首次存档成功")
	var repeated := RuleEngine.judge(level, seq)
	check(not repeated.is_new and repeated.awarded_rep == 0 and GameState.total_rep == 325, "重复不奖励")
	GameState.load_game()
	check(GameState.sranks.has("test_core"), "重启恢复 S 评级")
	check(GameState.unlocked_endings.has("test_core:S1"), "重启恢复图鉴索引")
	check(GameState.save_data.levels.test_core.sequence == seq, "保存的是传入排列")
	RuleEngine.judge(level, seq)
	check(GameState.total_rep == 325, "重启后重复也不奖励")
	RuleEngine.judge(level, Fixtures.initial(level))
	var ctx := {"world_state": GameState.world_state()}
	check(not ConditionEngine.evaluate("CURRENT(test_core,0,S1)", ctx), "当前 Bad 不能满足 CURRENT S")
	check(ConditionEngine.evaluate("CURRENT(test_core,0,BAD1)&&ACHIEVE(test_core,0,S1)", ctx), "当前与历史独立")
	GameState.row("test_core:R")["achieved"] = []
	GameState.row("test_core:R")["current"] = ""
	GameState.set_row_read("test_core:L")
	ctx = {"world_state": GameState.world_state()}
	check(not ConditionEngine.evaluate("ELLE(test_core,1,S1)", ctx), "不串行历史")
	check(ConditionEngine.evaluate("READ(test_core,0)&&!READ(test_core,1)", ctx), "不串行已读")
	GameState.save_data.story_flags.append("INTRO")
	check(ConditionEngine.evaluate("STORY(INTRO)", {"world_state": GameState.world_state()}), "剧情标志接通")
	GameState.save_game()
	GameState.load_game()
	check(GameState.sranks.has("test_core") and GameState.row_read("test_core:L"), "跨关状态再次恢复")

func _test_save_recovery() -> void:
	# 模拟旧版存档：无版本字段，已有累计声望。
	var old := {"rows": {"test_core:L": {"achieved": ["S1"], "current": "S1"}}, "total_rep": 999}
	_write(GameState.save_path, JSON.stringify(old))
	GameState.load_game()
	check(GameState.total_rep == 999 and GameState.sranks.has("test_core"), "旧档迁移保留总额及 S")
	check(GameState.save_game(), "迁移后可保存")
	check(GameState.save_game(), "主档替换和备份成功")
	_write(GameState.save_path, "{broken")
	GameState.load_game()
	check(GameState.recovered_from_backup and GameState.total_rep == 999, "坏主档恢复备份")
	check(GameState.save_game(), "恢复后可重新保存")
	check(Store.read_save(GameState.save_path).data.total_rep == 999, "恢复后有效主档")
	check(not Store.is_valid({"rows": []}), "拒绝错误 rows 类型")
	check(not Store.is_valid({"rows": {"x:L": {"achieved": 1}}}), "拒绝错误行数据")
	check(not Store.is_valid({"version": 999, "rows": {}}), "拒绝未知存档版本")
	check(Store.write_save("user://missing_regression_directory/save.json", GameState.save_data) != OK, "写入失败返回错误")
	_write(GameState.save_path, "bad main")
	_write(Store.backup_path(GameState.save_path), "bad backup")
	GameState.load_game()
	check(not GameState.save_game(), "双坏档不自动覆盖")
	check(FileAccess.get_file_as_string(GameState.save_path) == "bad main", "原始坏档保留")
	GameState.reset_save()
	check(GameState.history.is_empty() and GameState.verdicts.is_empty() and GameState.sequences.is_empty(), "新游戏清除所有会话状态")

func _test_changes() -> void:
	var level := LevelData.load_level("test_core")
	var text := level.apply_changes(["PanelA1", "A1", "PanelA2"], [
		{"type": "DRA", "data": "A1"}, {"type": "REPLACE", "data": "PanelA2_1"}])
	check(text.size() == 2 and text[1] == "事情有了新的结果。", "替换与删除共同应用")
	var sequences := Fixtures.initial(level)
	sequences.L.erase("A1")
	sequences.R.insert(1, "A1")
	check(RuleEngine.affected_rows(level, {"changes": [{"type": "D", "data": "A1"}]}, sequences) == ["R"], "跨栏删除按实际行重放")
	check(RuleEngine.affected_rows(level, {"changes": [{"type": "REPLACE", "data": "PanelA2_1"}]}, sequences) == ["L"], "替换按原句位置重放")

func _test_validation() -> void:
	var validator := preload("res://scripts/core/level_validator.gd").new()
	validator.quiet = true
	var characters := LevelData.load_characters()
	var data := Fixtures.level_data("test_core", true)
	check(validator.validate_data(data, characters) == 0, "独立双人关卡有效")
	data.rows[0].variants[0].base = "PanelB2"
	check(validator.validate_data(data, characters) == 0, "变体可引用后定义的行")
	data.endings.S1.change[0].data = "A1"
	check(validator.validate_data(data, characters) > 0, "REPLACE 必须引用变体")
	data = Fixtures.level_data("test_core")
	data.unlock = "CURRENT(test_core,0,NO_ENDING)"
	check(validator.validate_data(data, characters) > 0, "跨关结局拼写检查")
	data.unlock = "SRANK(missing_level)"
	check(validator.validate_data(data, characters) > 0, "跨关文件存在检查")
	data.unlock = "UNKNOWN_TRIGGER"
	check(validator.validate_data(data, characters) > 0, "裸触发句检查")
	data = Fixtures.level_data("test_core")
	data.conditions.reverse()
	check(validator.validate_data(data, characters) > 0, "提前兜底不能遮蔽条件")
	data.rows = [123]
	check(validator.validate_data(data, characters) > 0, "错误数据类型不会使校验器崩溃")

func _test_detail_card() -> void:
	var factory := preload("res://scenes/map/map_detail_card.gd")
	var font := load("res://assets/fonts/HYRunYuan-55W.ttf")
	var card := factory.build("测试标题", {"S1": {}, "BAD1": {}}, [], "", font)
	check(card.size == Vector2(300, 100), "未完成地图卡只有标题")
	card.free()
	card = factory.build("测试标题", {"S1": {}, "BAD1": {}}, ["S1"], "S1", font)
	check(card.size == Vector2(300, 158), "完成地图卡显示结局带")
	card.free()

func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
