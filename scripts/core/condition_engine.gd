# condition_engine.gd — 条件表达式引擎(分词 → 递归下降解析 → 求值)
# 语法见 docs/文件结构与开发路线.md §5.3; 判定(conditions)与解锁(unlock)共用本引擎。
class_name ConditionEngine
extends RefCounted

# —— 求值上下文(三表) ——
# ctx = {
#   "merged":  Array[String]  — 合并序列: 各行句子 id 按行序拼接的完整顺序
#   "sides":   { "L": [...], "R": [...], "M": [...] } — 每行当前拥有的句子 id(IN 判定用)
#   "triggered": { id: bool } — 条件句触发状态(REPLACE 出场后为 true)
#   "world_state": {...}      — 跨关状态(history/sranks/read/stories/achievements)
# }

# 求值入口: 空表达式 = 无条件命中(fallback 条目)
static func evaluate(expr: String, ctx: Dictionary) -> bool:
	if expr.strip_edges() == "":
		return true
	var tokens := _tokenize(expr)
	if tokens.is_empty():
		return false
	var pos := [0]  # 数组模拟指针(传引用)
	return _parse_or(tokens, pos, ctx)

# —— 分词 ——

static func _tokenize(expr: String) -> Array:
	var tokens: Array = []
	var i := 0
	while i < expr.length():
		var c := expr[i]
		if c == " " or c == "\t":
			i += 1
			continue
		if c == "&" and i + 1 < expr.length() and expr[i + 1] == "&":
			tokens.append({"t": "AND"})
			i += 2
			continue
		if c == "|" and i + 1 < expr.length() and expr[i + 1] == "|":
			tokens.append({"t": "OR"})
			i += 2
			continue
		if c == "!":
			tokens.append({"t": "NOT"})
			i += 1
			continue
		if c == "(":
			tokens.append({"t": "LPAREN"})
			i += 1
			continue
		if c == ")":
			tokens.append({"t": "RPAREN"})
			i += 1
			continue
		if c == ",":
			tokens.append({"t": "COMMA"})
			i += 1
			continue
		if c.is_valid_identifier() or _is_digit(c):
			# 标识符(句子 id / 函数名)或数字(关卡号如 0002)
			var j := i
			while j < expr.length() and (expr[j].is_valid_identifier() or _is_digit(expr[j])):
				j += 1
			var word := expr.substr(i, j - i)
			tokens.append({"t": "NUMBER" if _is_digit(word[0]) else "IDENT", "v": word})
			i = j
			continue
		i += 1  # 跳过未知字符
	return tokens

static func _is_digit(s: String) -> bool:
	return s >= "0" and s <= "9"

# —— 递归下降解析(边解析边求值) ——
#   expr     := or_expr
#   or_expr  := and_expr ("||" and_expr)*
#   and_expr := unary ("&&" unary)*
#   unary    := "!" unary | primary
#   primary  := IDENT | IDENT "(" args ")" | "(" expr ")"

static func _parse_or(tokens: Array, pos: Array, ctx: Dictionary) -> bool:
	var value := _parse_and(tokens, pos, ctx)
	while _peek(tokens, pos, "OR"):
		pos[0] += 1
		value = value or _parse_and(tokens, pos, ctx)
	return value

static func _parse_and(tokens: Array, pos: Array, ctx: Dictionary) -> bool:
	var value := _parse_unary(tokens, pos, ctx)
	while _peek(tokens, pos, "AND"):
		pos[0] += 1
		value = value and _parse_unary(tokens, pos, ctx)
	return value

static func _parse_unary(tokens: Array, pos: Array, ctx: Dictionary) -> bool:
	if _peek(tokens, pos, "NOT"):
		pos[0] += 1
		return not _parse_unary(tokens, pos, ctx)
	return _parse_primary(tokens, pos, ctx)

static func _parse_primary(tokens: Array, pos: Array, ctx: Dictionary) -> bool:
	if _peek(tokens, pos, "LPAREN"):
		pos[0] += 1
		var value := _parse_or(tokens, pos, ctx)
		_consume(tokens, pos, "RPAREN")
		return value
	var tok := _cur(tokens, pos)
	if tok.get("t", "") != "IDENT":
		return false
	pos[0] += 1
	# 函数调用: IDENT "(" args ")"
	if _peek(tokens, pos, "LPAREN"):
		pos[0] += 1
		var args: Array = []
		if not _peek(tokens, pos, "RPAREN"):
			while true:
				args.append(_arg(tokens, pos))
				if _peek(tokens, pos, "COMMA"):
					pos[0] += 1
					continue
				break
		_consume(tokens, pos, "RPAREN")
		return _call(String(tok.get("v", "")), args, ctx)
	# 裸标识符: 条件句触发状态(未触发 = false)
	return bool(ctx.get("triggered", {}).get(String(tok.get("v", "")), false))

static func _arg(tokens: Array, pos: Array) -> String:
	var tok := _cur(tokens, pos)
	if tok.get("t", "") == "IDENT" or tok.get("t", "") == "NUMBER":
		pos[0] += 1
		return String(tok.get("v", ""))
	return ""

# —— 函数求值 ——

static func _call(name: String, args: Array, ctx: Dictionary) -> bool:
	match name:
		"SS":
			return _eval_ss(args, ctx)
		"OS":
			return _eval_os(args, ctx)
		"OSS", "S":
			return _eval_oss(args, ctx)
		"IN":
			return _eval_in(args, ctx)
		"CURRENT", "ELLE", "SRANK", "STORY", "READ", "ACHIEVE":
			return _eval_world(name, args, ctx)
		_:
			push_warning("ConditionEngine: 未知函数 %s" % name)
			return false

# SS(A,B[,C]): A 在 B(在 C)之前(严格顺序链, 全部位于合并序列中)
static func _eval_ss(args: Array, ctx: Dictionary) -> bool:
	var pos_map := _positions(ctx)
	var prev := -1
	for a in args:
		var id := String(a)
		if not pos_map.has(id):
			return false
		var p: int = pos_map[id]
		if p <= prev:
			return false
		prev = p
	return true

# OS(A,B): A 紧邻 B 之前
static func _eval_os(args: Array, ctx: Dictionary) -> bool:
	if args.size() < 2:
		return false
	var pos_map := _positions(ctx)
	if not pos_map.has(String(args[0])) or not pos_map.has(String(args[1])):
		return false
	return int(pos_map[String(args[1])]) == int(pos_map[String(args[0])]) + 1

# OSS(A,B) / S(A,B): A、B 相邻(不分前后)
static func _eval_oss(args: Array, ctx: Dictionary) -> bool:
	if args.size() < 2:
		return false
	var pos_map := _positions(ctx)
	if not pos_map.has(String(args[0])) or not pos_map.has(String(args[1])):
		return false
	return absi(int(pos_map[String(args[1])]) - int(pos_map[String(args[0])])) == 1

# IN(L/R/M, X): X 当前位于左行 / 右行 / 中缝
static func _eval_in(args: Array, ctx: Dictionary) -> bool:
	if args.size() < 2:
		return false
	var sides: Dictionary = ctx.get("sides", {})
	var side_list: Array = sides.get(String(args[0]), [])
	return side_list.has(String(args[1]))

# 句子 id → 合并序列中的位置
static func _positions(ctx: Dictionary) -> Dictionary:
	var map := {}
	var merged: Array = ctx.get("merged", [])
	for i in merged.size():
		map[String(merged[i])] = i
	return map

# —— 跨关函数(世界状态查询; 数据由 RuleEngine 写入 GameState, 阶段 E 随多关接入) ——
# 注: 本作结局是关卡级(无行级), CURRENT/ELLE 的行号参数暂时忽略, 只查"本关达成过哪些结局"
static func _eval_world(name: String, args: Array, ctx: Dictionary) -> bool:
	var world: Dictionary = ctx.get("world_state", {})
	match name:
		"CURRENT":
			if args.size() < 3:
				return false
			var got: Array = world.get("history", {}).get(String(args[0]), [])
			return got.has(String(args[2]))
		"ELLE":
			if args.size() < 3:
				return false
			var got2: Array = world.get("history", {}).get(String(args[0]), [])
			for a in args.slice(2):
				if got2.has(String(a)):
					return true
			return false
		"SRANK":
			return bool(world.get("sranks", {}).get(String(args[0]), false))
		"STORY":
			return (world.get("stories", []) as Array).has(String(args[0]))
		"READ":
			if args.size() < 2:
				return false
			var rows: Array = world.get("read", {}).get(String(args[0]), [])
			return rows.has(int(String(args[1])))
		"ACHIEVE":
			var key := ""
			for a in args:
				key += String(a) + ","
			return bool(world.get("achievements", {}).get(key, false))
	return false

# —— 工具 ——

static func _cur(tokens: Array, pos: Array) -> Dictionary:
	if pos[0] >= tokens.size():
		return {}
	return tokens[pos[0]]

static func _peek(tokens: Array, pos: Array, kind: String) -> bool:
	return _cur(tokens, pos).get("t", "") == kind

static func _consume(tokens: Array, pos: Array, kind: String) -> void:
	if _peek(tokens, pos, kind):
		pos[0] += 1
