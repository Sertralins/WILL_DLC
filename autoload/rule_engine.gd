# rule_engine.gd — 判定引擎(autoload 注册名: RuleEngine)
#
# 职责(见 docs/文件结构与开发路线.md §2-D6):
# judge() 按 conditions 顺序求值 → 首个命中者生效 → 应用 endings[命中].change → 写 GameState。
# 纯逻辑, 不碰 UI; 条件表达式求值在 scripts/core/condition_engine.gd。
extends Node

# 判定一次排列。sequences = { 行id: [句子id序列] }(arrange_board 的 get_sequence_ids 输出)
# 命中返回 { level_id, ending_id, rank, rep, matched_index, changes };
# 无任何条件命中返回 {}。
func judge(level: LevelData, sequences: Dictionary) -> Dictionary:
	var ctx := {
		"merged": _merged_order(level, sequences),
		"sides": sequences,          # 行 id → 该行当前句子序列(IN 判定直接查)
		"triggered": {},             # 条件句触发状态(REPLACE 出场后为 true, 阶段 D 完善)
		"world_state": _world_state(),
	}
	for i in level.conditions.size():
		var c: Dictionary = level.conditions[i]
		if not ConditionEngine.evaluate(String(c.get("expr", "")), ctx):
			continue
		var ending_id := String(c.get("ending", ""))
		var ending: Dictionary = level.endings.get(ending_id, {})
		var verdict := {
			"level_id": level.level_id,
			"ending_id": ending_id,
			"rank": String(ending.get("rank", "")),
			"rep": int(ending.get("rep", 0)),
			"matched_index": i,
			"changes": ending.get("change", []),  # CHANGE 指令序列(演绎场景用)
		}
		_apply(level, verdict)
		return verdict
	return {}

# 合并序列: 按行的定义顺序拼接各行序列(原版双行信 = L 在上 R 在下)
func _merged_order(level: LevelData, sequences: Dictionary) -> Array:
	var merged: Array = []
	for row in level.rows:
		for id in sequences.get(row.id, []):
			merged.append(String(id))
	return merged

# 结局 CHANGE 涉及的行 id(按关卡行定义顺序去重):
# REPLACE 的 data 是条件句(变体)id, DRA/D 的 data 是句子 id——都查它们定义在哪个行
func affected_rows(level: LevelData, verdict: Dictionary) -> Array:
	var rows: Array = []
	for change in verdict.get("changes", []):
		var data := String(change.get("data", ""))
		if data == "":
			continue
		var info := level.find_sentence(data)
		if info.is_empty():
			continue
		var home: LevelData.Row = info["row"]
		if not rows.has(home.id):
			rows.append(home.id)
	return rows

# 跨关状态快照(阶段 E 多关接入后由各场景持续写入 GameState)
func _world_state() -> Dictionary:
	return {
		"history": GameState.history,          # { level_id: [ending_id] }
		"sranks": GameState.sranks,            # { level_id: true }
		"read": GameState.read_rows,           # { level_id: [row_index] }
		"stories": [],                         # 剧情片段(阶段 G 演绎分镜接入)
		"achievements": [],                    # 成就(阶段 F 接入)
	}

# 命中后写入 GameState: 判定结果 + 跨关历史 + 声望 + 图鉴
func _apply(level: LevelData, verdict: Dictionary) -> void:
	GameState.verdicts = verdict

	# 跨关历史: 本关已达成结局列表(CURRENT/ELLE 查询与图鉴的数据源)
	var list: Array = GameState.history.get(level.level_id, [])
	if not list.has(String(verdict.ending_id)):
		list.append(String(verdict.ending_id))
	GameState.history[level.level_id] = list

	# 当前选择结局(地图方块显示用): 记到本关当前行的存档条目
	GameState.row("%s:%s" % [level.level_id, GameState.current_row]).current = String(verdict.ending_id)

	# 声望累计(跨关累积, 影响后续解锁)
	GameState.total_rep += int(verdict.rep)

	# 图鉴解锁条目: "关卡id:结局id"; 首次达成标记 is_new(重放演绎只放新结局)
	var entry := "%s:%s" % [level.level_id, String(verdict.ending_id)]
	verdict["is_new"] = not GameState.unlocked_endings.has(entry)
	if verdict["is_new"]:
		GameState.unlocked_endings.append(entry)

	# S 评级记录(SRANK(0001) 解锁条件用)
	if String(verdict.rank) == "S":
		GameState.sranks[level.level_id] = true

	# 结算即落盘(判定链文档 §3.1: 原游戏结算时刻写入存档)
	GameState.save_game()
