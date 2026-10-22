# 独立测试关卡：不受 data/levels/0001.json 的剧情编辑影响。
extends RefCounted

static func level_data(id: String, two_rows := false) -> Dictionary:
	var rows := [_row("L", "A", "yf")]
	if two_rows:
		rows.append(_row("R", "B", "qyy"))
	return {"level_id": id, "title": "测试信件", "row_count": rows.size(), "unlock": "",
		"rows": rows,
		"endings": {
			"S1": {"rank": "S", "rep": 325, "change": [{"type": "REPLACE", "data": "PanelA2_1"}]},
			"BAD1": {"rank": "Bad", "rep": 0, "change": []}},
		"conditions": [{"expr": "SS(A2,A1)", "ending": "S1"},
			{"expr": "", "ending": "BAD1", "fallback": true}]}

static func _row(id: String, prefix: String, character: String) -> Dictionary:
	return {"id": id, "character": character, "previous": "start", "position": "0,3",
		"title_block": {"text": "测试信件"},
		"blocks": [{"id": "Panel%s1" % prefix, "text": "我写下了这封信。"},
			{"id": "Panel%s2" % prefix, "text": "事情还没有结束。"}],
		"strips": [{"id": prefix + "1", "text": "第一张字条"}, {"id": prefix + "2", "text": "第二张字条"}],
		"variants": [{"id": "Panel%s2_1" % prefix, "base": "Panel%s2" % prefix, "text": "事情有了新的结果。"}]}

static func initial(level: LevelData) -> Dictionary:
	var sequences := {}
	for row in level.rows:
		sequences[row.id] = level.layout_sequence(row)
	return sequences

# 手工视觉探针设置前置进度时使用；调用前先切换到探针自己的 save_path。
static func set_history(level_id: String, endings: Array) -> void:
	var level := LevelData.load_level(level_id)
	for row in level.rows:
		var entry := GameState.row("%s:%s" % [level_id, row.id])
		entry["achieved"] = endings.duplicate()
		entry["current"] = String(endings.back()) if not endings.is_empty() else ""
	GameState.save_game()
