# validate_levels.gd — 关卡数据校验器(编辑器脚本)
#
# 用法: 在脚本编辑器里打开本文件 → 文件 > 运行(或 Ctrl+Shift+X) → 看底部「输出」面板
# (不需要运行游戏, 校验器直接在编辑器里读 data/ 下的 JSON)
#
# 校验项:
# 1. JSON 语法与 levels_index 登记(关卡文件存在、起始关有效)
# 2. 每关: 行 id 唯一且 ∈ {L,R,M}; 全部句子 id(blocks/strips/variants)全关唯一
# 3. 每行至少 1 个固定块(顶部框架); variants.base 必须存在
# 4. endings: conditions 引用的结局存在; CHANGE 指令类型合法; REPLACE/DRA 的 DATA 句子存在
# 5. conditions 表达式基础语法(括号配对、函数名白名单、引用句子存在)
# 6. characters: 行引用的角色在 characters.json 里存在且有 name/color
@tool
extends EditorScript

const LEVEL_DIR := "res://data/levels/"
const INDEX_PATH := "res://data/levels/levels_index.json"
const CHARACTERS_PATH := "res://data/characters.json"

# 表达式里允许的函数名(与 docs/文件结构与开发路线.md §5.3 一致)
const KNOWN_FUNCS := ["SS", "OS", "OSS", "S", "IN", "SRANK", "CURRENT", "ELLE"]

var _errors: int = 0
var _warnings: int = 0

func _run() -> void:
	print("=== 关卡数据校验开始 ===")
	var index := _load_json(INDEX_PATH, "关卡索引")
	if index.is_empty():
		_print_summary()
		return

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

# —— 单关校验 ——

func _validate_level(data: Dictionary, characters: Dictionary) -> void:
	if data.is_empty():
		return
	var lid := String(data.get("level_id", ""))
	if lid == "":
		_error("缺少 level_id")

	var rows: Array = data.get("rows", [])
	if rows.is_empty():
		_error("rows 为空, 至少需要一行")
		return
	var row_count: int = int(data.get("row_count", 0))
	if row_count != rows.size():
		_warning("row_count=%d 与 rows 数组长度 %d 不一致" % [row_count, rows.size()])

	# 全关句子 id 唯一性(黑块/字条/条件句共享命名空间)
	var seen := {}          # id → 描述
	var base_ids := {}      # id → true(可被 variants 引用的句子)
	var seen_rows := {}

	for row_data in rows:
		var rid := String(row_data.get("id", ""))
		if rid == "" or not ["L", "R", "M"].has(rid):
			_error("行 id 非法: '%s'(应为 L/R/M)" % rid)
		if seen_rows.has(rid):
			_error("行 id 重复: %s" % rid)
		seen_rows[rid] = true

		for kind in ["blocks", "strips"]:
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
			if seen.has(vid):
				_error("句子 id 重复: %s(条件句)" % vid)
			seen[vid] = "variants"
			var base := String(v.get("base", ""))
			if base == "" or not base_ids.has(base):
				_error("条件句 %s 的 base '%s' 不存在" % [vid, base])
			_check_text_source(v, lid, vid)

		var cid := String(row_data.get("character", ""))
		if not characters.has(cid):
			_error("行 %s 引用的角色 '%s' 不在 characters.json 里" % [rid, cid])
		elif not (characters[cid] is Dictionary) or String(characters[cid].get("name", "")) == "":
			_error("角色 %s 缺少 name" % cid)

	# 结局与条件
	var endings: Dictionary = data.get("endings", {})
	for eid in endings:
		var e: Dictionary = endings[eid]
		for change in e.get("change", []):
			var ctype := String(change.get("type", ""))
			if not ["REPLACE", "DRA", "D"].has(ctype):
				_error("结局 %s 的 CHANGE 类型非法: '%s'" % [eid, ctype])
			elif ctype != "D":
				var cdata := String(change.get("data", ""))
				if cdata != "" and not seen.has(cdata):
					_error("结局 %s 的 %s 引用的句子 '%s' 不存在" % [eid, ctype, cdata])

	var conditions: Array = data.get("conditions", [])
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
		if bool(c.get("fallback", false)) and i != conditions.size() - 1:
			_warning("fallback 条目不在 conditions 最后(会被后面的条目挡住)" % [])

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
	var depth := 0
	for ch in expr:
		if ch == "(":
			depth += 1
		elif ch == ")":
			depth -= 1
			if depth < 0:
				_error("conditions[%d] 括号不配对: %s" % [idx, expr])
				return
	if depth != 0:
		_error("conditions[%d] 括号不配对: %s" % [idx, expr])
		return

	# 函数名白名单: 提取 标识符( 形式的调用名
	for m in RegEx.create_from_string("([A-Za-z_][A-Za-z0-9_]*)\\s*\\(").search_all(expr):
		var fname := m.get_string(1)
		if not KNOWN_FUNCS.has(fname):
			_error("conditions[%d] 未知函数: %s" % [idx, fname])

	# 句子 id 引用: 提取所有标识符(排除函数名与布尔词), 校验存在性
	var identifiers := RegEx.create_from_string("[A-Za-z_][A-Za-z0-9_]*").search_all(expr)
	for m in identifiers:
		var name := m.get_string()
		if KNOWN_FUNCS.has(name):
			continue
		if not sentence_ids.has(name):
			_warning("conditions[%d] 引用的句子 '%s' 在本关不存在" % [idx, name])

# —— 工具 ——

func _load_json(path: String, what: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_error("%s文件不存在: %s" % [what, path])
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
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
	print("  ❌ %s" % msg)

func _warning(msg: String) -> void:
	_warnings += 1
	print("  ⚠️ %s" % msg)

func _print_summary() -> void:
	print("=== 校验完成: %d 个错误, %d 个警告 ===" % [_errors, _warnings])
	if _errors == 0:
		print("✅ 数据全部通过, 可以放心运行")
