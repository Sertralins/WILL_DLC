# rule_engine.gd — 判定引擎(autoload 注册名: RuleEngine)
#
# 职责(见 docs/文件结构与开发路线.md §2-D6):
# judge() 按 conditions 顺序求值 → 首个命中者生效 → 应用 endings[命中].change → 写 GameState。
# evaluate 只计算，judge 通过 GameState 保存；不碰 UI; 条件表达式求值在 scripts/core/condition_engine.gd。
extends Node

# 判定一次排列。sequences = { 行id: [句子id序列] }(arrange_board 的 get_sequence_ids 输出)
# 命中返回 { level_id, ending_id, rank, rep, matched_index, changes };
# 无任何条件命中返回 {}。
func judge(level: LevelData, sequences: Dictionary) -> Dictionary:
	var result := evaluate(level, sequences)
	if not result.is_empty() and not GameState.record_verdict(level, result, sequences):
		return {}
	return result

# 无副作用接口，供预览和测试使用；不会增加声望或保存进度。
func evaluate(level: LevelData, sequences: Dictionary) -> Dictionary:
	# 不让残缺排列命中兜底 Bad 并继续覆盖存档。
	if not level.is_valid_arrangement(sequences):
		return {}
	var ctx := {
		"merged": _merged_order(level, sequences),
		"sides": sequences,          # 行 id → 该行当前句子序列(IN 判定直接查)
		"triggered": _triggered(level, sequences),             # 条件句触发状态(REPLACE 出场后为 true, 实际序列)
		"world_state": GameState.world_state(),
	}
	if level.has_row_endings():
		var results := {}
		for letter in level.rows:
			var result := _match(level.level_id, letter.conditions, letter.endings, ctx)
			if result.is_empty():
				return {} # 所有行必须成功判定，不能保存半份结果。
			results[letter.id] = result
		return {"level_id": level.level_id, "rows": results, "independent": true}
	var result := _match(level.level_id, level.conditions, level.endings, ctx)
	if not result.is_empty():
		var rows := {}
		for letter in level.rows:
			rows[letter.id] = result.duplicate(true)
		result["rows"] = rows
		result["independent"] = false
	return result

func _match(level_id: String, conditions: Array, endings: Dictionary, ctx: Dictionary) -> Dictionary:
	for i in conditions.size():
		var condition: Dictionary = conditions[i]
		var expression := String(condition.get("expr", ""))
		if not ConditionEngine.is_valid_expression(expression):
			return {}
		if not ConditionEngine.evaluate(expression, ctx):
			continue
		var id := String(condition.get("ending", ""))
		if not endings.has(id):
			return {}
		var ending: Dictionary = endings[id]
		return {"level_id": level_id, "ending_id": id, "rank": String(ending.get("rank", "")),
			"rep": int(ending.get("rep", 0)), "matched_index": i, "changes": ending.get("change", []).duplicate(true)}
	return {}

func needs_countdown(verdict: Dictionary) -> bool:
	for result in verdict.get("rows", {"L": verdict}).values():
		if result.get("is_new", false) and String(result.get("rank", "")).to_lower() != "bad":
			return true
	return false

# 合并序列: 按行的定义顺序拼接各行序列(原版双行信 = L 在上 R 在下)
func _merged_order(level: LevelData, sequences: Dictionary) -> Array:
	var merged: Array = []
	for row in level.rows:
		for id in sequences.get(row.id, []):
			merged.append(String(id))
	return merged

# 按当前排列寻找变化发生在哪封信。跨栏后不能再用字条原来的归属行。
func affected_rows(level: LevelData, verdict: Dictionary, sequences: Dictionary = {}) -> Array:
	if sequences.is_empty():
		sequences = GameState.sequences
	if level.has_row_endings() and verdict.has("rows"):
		var affected: Array = []
		for letter in level.rows:
			var result: Dictionary = verdict.rows.get(letter.id, {})
			if result.get("is_new", false):
				var candidates := affected_rows(level, {"changes": result.get("changes", [])}, sequences)
				if candidates.has(letter.id):
					affected.append(letter.id)
		return affected
	var changed_ids := {}
	for change in verdict.get("changes", []):
		var id := String(change.get("data", ""))
		if change.get("type", "") == "REPLACE":
			var info := level.find_sentence(id)
			if not info.is_empty():
				id = String(info.sentence.get("base", ""))
		changed_ids[id] = true
	var rows: Array = []
	for row in level.rows:
		for id in sequences.get(row.id, level.layout_sequence(row)):
			if changed_ids.has(id):
				rows.append(row.id)
				break
	return rows

# 触发标志来自输入中实际出现的条件句，不使用旧结局污染新尝试。
func _triggered(level: LevelData, sequences: Dictionary) -> Dictionary:
	var triggered := {}
	var merged := _merged_order(level, sequences)
	for letter in level.rows:
		for variant in letter.variants:
			var id := String(variant.get("id", ""))
			if merged.has(id):
				triggered[id] = true
	return triggered
