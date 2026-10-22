# 关卡校验逻辑：编辑器与命令行共用，不加载游戏场景。
extends RefCounted

const LEVEL_DIR := "res://data/levels/"
const INDEX_PATH := "res://data/levels/levels_index.json"
const CHARACTERS_PATH := "res://data/characters.json"

# 表达式里允许的函数名(与 docs/文件结构与开发路线.md §5.3 一致)
const KNOWN_FUNCS := ConditionEngine.FUNCTIONS

var _errors: int = 0
var _warnings: int = 0
var quiet := false

# 单个关卡校验接口，供测试或未来的关卡编辑工具调用。
func validate_data(data: Dictionary, characters: Dictionary) -> int:
	_errors = 0
	_warnings = 0
	_validate_level(data, characters)
	return _errors

func run() -> int:
	_errors = 0
	_warnings = 0
	_texts.clear()
	print("=== 关卡数据校验开始 ===")
	var index := _load_json(INDEX_PATH, "关卡索引")
	if index.is_empty():
		_print_summary()
		return _errors

	var level_ids: Array = index.get("levels", [])
	if level_ids.is_empty():
		_error("levels_index.json 的 levels 数组为空")
	var start: String = String(index.get("start", ""))
	if not level_ids.has(start):
		_error("起始关 '%s' 不在 levels 列表里" % start)

	var characters := _load_json(CHARACTERS_PATH, "角色档案")

	for id in level_ids:
		var lid: String = String(id)
		print("--- 校验关卡 %s ---" % lid)
		var path := LEVEL_DIR + lid + ".json"
		if not FileAccess.file_exists(path):
			_error("关卡文件不存在: %s" % path)
			continue
		_validate_level(_load_json(path, "关卡 %s" % lid), characters)

	_print_summary()
	return _errors

# —— 单关校验 ——

func _validate_level(data: Dictionary, characters: Dictionary) -> void:
	if data.is_empty():
		_error("关卡数据为空")
		return
	if not _valid_structure(data):
		_error("关卡字段类型错误，请检查 rows/endings/conditions 和句子列表")
		return
	var lid := String(data.get("level_id", ""))
	if lid == "":
		_error("缺少 level_id")

	var rows: Array = data.get("rows", [])
	if rows.is_empty():
		_error("rows 为空, 至少需要一行")
		return
	var row_count: int = int(data.get("row_count", 0))
	if rows.size() > 3:
		_error("排列界面支持 1 至 3 行")
	if row_count != rows.size():
		_error("row_count=%d 与 rows 数组长度 %d 不一致" % [row_count, rows.size()])

	# 全关句子 id 唯一性(黑块/字条/条件句共享命名空间)
	var seen := {}          # id → 描述
	var base_ids := {}      # id → true(可被 variants 引用的句子)
	var variants := {}
	var variant_bases := {}
	var seen_rows := {}

	for row_data in rows:
		var rid := String(row_data.get("id", ""))
		if rid == "" or not ["L", "R", "M"].has(rid):
			_error("行 id 非法: '%s'(应为 L/R/M)" % rid)
		if seen_rows.has(rid):
			_error("行 id 重复: %s" % rid)
		seen_rows[rid] = true

		for kind in ["blocks", "strips", "readonly"]:
			for s in row_data.get(kind, []):
				var sid := String(s.get("id", ""))
				if sid == "":
					_error("行 %s 的 %s 里有句子缺少 id" % [rid, kind])
					continue
				if seen.has(sid):
					_error("句子 id 重复: %s(%s 与 %s)" % [sid, seen[sid], "%s.%s" % [rid, kind]])
				seen[sid] = "%s.%s" % [rid, kind]
				base_ids[sid] = true
				_check_text_source(s, lid, sid)

		if row_data.get("blocks", []).is_empty():
			_error("行 %s 没有固定块(至少需要一个顶部框架块)" % rid)

		for v in row_data.get("variants", []):
			var vid := String(v.get("id", ""))
			if vid.is_empty() or seen.has(vid):
				_error("句子 id 重复: %s(条件句)" % vid)
			seen[vid] = "variants"
			variants[vid] = true
			var base := String(v.get("base", ""))
			variant_bases[vid] = base
			_check_text_source(v, lid, vid)

		var cid := String(row_data.get("character", ""))
		if not characters.has(cid):
			_error("行 %s 引用的角色 '%s' 不在 characters.json 里" % [rid, cid])
		elif not (characters[cid] is Dictionary) or String(characters[cid].get("name", "")) == "":
			_error("角色 %s 缺少 name" % cid)

	# 两遍校验：先收齐句子，再查 base，允许引用定义在后面一行的原句。
	for vid in variant_bases:
		if not base_ids.has(variant_bases[vid]):
			_error("条件句 %s 的 base '%s' 不存在" % [vid, variant_bases[vid]])
	_check_expr_syntax(String(data.get("unlock", "")), seen, -1)
	for row_data in rows:
		var order: Array = row_data.get("order", [])
		var order_seen := {}
		var own_ids := {}
		for kind in ["blocks", "strips", "readonly"]:
			for sentence in row_data.get(kind, []):
				own_ids[String(sentence.get("id", ""))] = true
		for id in order:
			if not own_ids.has(id) or order_seen.has(id):
				_error("order 含未知句子或重复句子: %s" % id)
			order_seen[id] = true
		if not order.is_empty() and order_seen.size() != own_ids.size():
			_error("order 必须包含本行全部固定句、字条和只读句")
		var character_data: Variant = characters.get(String(row_data.get("character", "")), {})
		var character: Dictionary = character_data if character_data is Dictionary else {}
		if not Color.html_is_valid(String(character.get("color", ""))):
			_error("角色缺少有效的 color 颜色")
		for field in ["letter_bg", "header", "header_locked", "anim"]:
			var path := String(character.get(field, ""))
			if path != "" and not ResourceLoader.exists(path):
				_error("角色资源不存在: %s" % path)
		var anim := String(row_data.get("anim", ""))
		if anim != "" and not ResourceLoader.exists(anim):
			_error("行级动画资源不存在: %s" % anim)

	if rows.size() == 3 and not (seen_rows.has("L") and seen_rows.has("M") and seen_rows.has("R")):
		_error("三人关卡必须包含 L、M、R 三行")
	var independent := false
	for letter in rows:
		independent = independent or not letter.get("endings", {}).is_empty() or not letter.get("conditions", []).is_empty()
	if independent:
		for letter in rows:
			_validate_rules(letter.get("endings", {}), letter.get("conditions", []), seen, variants)
	else:
		_validate_rules(data.get("endings", {}), data.get("conditions", []), seen, variants)

func _validate_rules(endings: Dictionary, conditions: Array, seen: Dictionary, variants: Dictionary) -> void:
	for eid in endings:
		var e: Dictionary = endings[eid]
		for change in e.get("change", []):
			var ctype := String(change.get("type", ""))
			if not ["REPLACE", "DRA", "D"].has(ctype):
				_error("结局 %s 的 CHANGE 类型非法: '%s'" % [eid, ctype])
			else:
				var cdata := String(change.get("data", ""))
				if cdata == "" or not seen.has(cdata):
					_error("结局 %s 的 %s 引用的句子 '%s' 不存在" % [eid, ctype, cdata])
				elif ctype == "REPLACE" and not variants.has(cdata):
					_error("结局 %s 的 REPLACE 必须指向 variants 中的句子" % eid)

	if conditions.is_empty() or String(conditions.back().get("expr", "")).strip_edges() != "":
		_error("conditions 最后必须有空表达式兜底，避免排列无结果")
	for i in conditions.size():
		var c: Dictionary = conditions[i]
		var eid := String(c.get("ending", ""))
		if not endings.has(eid):
			_error("conditions[%d] 引用的结局 '%s' 不存在" % [i, eid])
		var expr := String(c.get("expr", ""))
		if expr == "":
			if not bool(c.get("fallback", false)):
				_warning("conditions[%d] 的 expr 为空但未标记 fallback" % i)
		else:
			_check_expr_syntax(expr, seen, i)
		if expr.strip_edges().is_empty() and i != conditions.size() - 1:
			_error("空表达式不在最后，会遮蔽后面的条件")

# 句子文本来源检查: text 内联 或 text_key 存在于关卡的 PO 文本表
var _texts: Dictionary = {}

func _texts_for(lid: String) -> Dictionary:
	if not _texts.has(lid):
		_texts[lid] = LevelData.load_texts(lid)
	return _texts[lid]

func _check_text_source(s: Dictionary, lid: String, sid: String) -> void:
	if String(s.get("text", "")) == "" and String(s.get("text_key", "")) == "":
		_warning("句子 %s 既无 text 也无 text_key" % sid)
	elif String(s.get("text", "")) == "" and not _texts_for(lid).has(String(s.get("text_key", ""))):
		_warning("句子 %s 的 text_key '%s' 在 %s.txt 中找不到" % [sid, String(s.get("text_key", "")), lid])

# —— 表达式基础语法检查(完整语义解析在阶段 C 的条件引擎里) ——

func _check_expr_syntax(expr: String, sentence_ids: Dictionary, idx: int) -> void:
	if not ConditionEngine.is_valid_expression(expr):
		_error("conditions[%d] 表达式语法或参数错误: %s" % [idx, expr])
		return
	# 只检查排列函数引用的句子，不把 CURRENT 中的结局名当成本关句子。
	var calls := RegEx.create_from_string("(SS|OS|OSS|S|IN)\\s*\\(([^()]*)\\)")
	for match_result in calls.search_all(expr):
		var args := match_result.get_string(2).split(",")
		var start := 1 if match_result.get_string(1) == "IN" else 0
		for i in range(start, args.size()):
			var id := args[i].strip_edges()
			if not sentence_ids.has(id):
				_error("conditions[%d] 引用不存在的句子: %s" % [idx, id])
	# 跨关函数：查目标关卡、行和结局；STORY 的事件目录尚未接入。
	var world_calls := RegEx.create_from_string("(CURRENT|ELLE|ACHIEVE|READ|SRANK)\\s*\\(([^()]*)\\)")
	for found in world_calls.search_all(expr):
		var args := found.get_string(2).split(",")
		var target_id := args[0].strip_edges()
		if not LevelData.overrides.has(target_id) and not FileAccess.file_exists(LEVEL_DIR + target_id + ".json"):
			_error("跨关条件引用不存在的关卡: %s" % target_id)
			continue
		var target := LevelData.load_level(target_id)
		if found.get_string(1) != "SRANK":
			var row_id: String = ["L", "R", "M"][int(args[1].strip_edges())]
			if target.row_by_id(row_id) == null:
				_error("跨关条件引用不存在的行: %s:%s" % [target_id, row_id])
		for i in range(2, args.size()):
			if not target.endings_for(["L", "R", "M"][int(args[1].strip_edges())]).has(args[i].strip_edges()):
				_error("跨关条件引用不存在的结局: %s" % args[i])
	# 去掉函数调用后，剩下的标识符是触发状态，不能拼错句子 id。
	var without_calls := RegEx.create_from_string("[A-Za-z_][A-Za-z0-9_]*\\s*\\([^()]*\\)").sub(expr, "", true)
	for token in RegEx.create_from_string("[A-Za-z_][A-Za-z0-9_]*").search_all(without_calls):
		if not sentence_ids.has(token.get_string()):
			_error("未知触发句子: %s" % token.get_string())

# —— 工具 ——

# 先检查容器类型，再做语义校验，避免校验器自身因手写 JSON 的错误而中断。
func _valid_structure(data: Dictionary) -> bool:
	if not data.get("rows") is Array or not data.get("conditions", []) is Array or not data.get("endings", {}) is Dictionary:
		return false
	for row in data.rows:
		if not row is Dictionary or not row.get("order", []) is Array:
			return false
		for kind in ["blocks", "strips", "readonly", "variants"]:
			if not row.get(kind, []) is Array:
				return false
			for sentence in row.get(kind, []):
				if not sentence is Dictionary:
					return false
	var all_conditions: Array = data.get("conditions", []).duplicate()
	var all_endings: Array = data.get("endings", {}).values()
	for letter in data.rows:
		if not letter.get("conditions", []) is Array or not letter.get("endings", {}) is Dictionary:
			return false
		all_conditions.append_array(letter.get("conditions", []))
		all_endings.append_array(letter.get("endings", {}).values())
	for condition in all_conditions:
		if not condition is Dictionary:
			return false
	for ending in all_endings:
		if not ending is Dictionary or not ending.get("change", []) is Array:
			return false
		for change in ending.get("change", []):
			if not change is Dictionary:
				return false
	return true

func _load_json(path: String, what: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_error("%s文件不存在: %s" % [what, path])
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_error("无法打开数据文件: %s" % path)
		return {}
	var text := file.get_as_text()
	if file.get_error() != OK:
		_error("%s读取失败: %s" % [what, path])
		return {}
	var data = JSON.parse_string(text)
	if data == null or not (data is Dictionary):
		_error("%s不是合法 JSON 字典: %s" % [what, path])
		return {}
	return data

func _error(msg: String) -> void:
	_errors += 1
	if not quiet:
		print("  ❌ %s" % msg)

func _warning(msg: String) -> void:
	_warnings += 1
	if not quiet:
		print("  ⚠️ %s" % msg)

func _print_summary() -> void:
	print("=== 校验完成: %d 个错误, %d 个警告 ===" % [_errors, _warnings])
	if _errors == 0:
		print("✅ 数据全部通过, 可以放心运行")
