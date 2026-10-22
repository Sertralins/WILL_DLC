# condition_engine.gd — 条件表达式引擎(分词 → 递归下降解析 → 求值)
# 语法见 docs/文件结构与开发路线.md §5.3; 判定(conditions)与解锁(unlock)共用本引擎。
class_name ConditionEngine
extends RefCounted

# 运行时和校验器共用：参数数目为 [最少, 最多]，-1 表示不限。
const FUNCTIONS := {
	"SS": [2, -1], "OS": [2, 2], "OSS": [2, 2], "S": [2, 2],
	"IN": [2, 2], "CURRENT": [3, 3], "ELLE": [3, -1],
	"SRANK": [1, 1], "STORY": [1, 1], "READ": [2, 2], "ACHIEVE": [3, 3],
}

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
	# pos[0] 是读取位置，pos[1] 记录整条表达式是否仍然合法。
	var pos := [0, true]
	var result := _parse_or(tokens, pos, ctx)
	return result and bool(pos[1]) and pos[0] == tokens.size()

# 只检查语法，不查询游戏进度。与 evaluate 使用完全相同的解析流程。
static func is_valid_expression(expr: String) -> bool:
	if expr.strip_edges().is_empty():
		return true
	var tokens := _tokenize(expr)
	var pos := [0, true]
	_parse_or(tokens, pos, {"validate_only": true})
	return not tokens.is_empty() and bool(pos[1]) and pos[0] == tokens.size()

# —— 分词 ——

static func _tokenize(expr: String) -> Array:
	var tokens: Array = []
	var i := 0
	while i < expr.length():
		var c := expr[i]
		if c in [" ", "\t", "\n", "\r"]:
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
		return []  # 不能忽略错误，否则 A&B 可能被误读成 A。
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
		var right := _parse_and(tokens, pos, ctx)
		value = value or right  # 先读取右侧，再求值；不能让短路跳过解析。
	return value

static func _parse_and(tokens: Array, pos: Array, ctx: Dictionary) -> bool:
	var value := _parse_unary(tokens, pos, ctx)
	while _peek(tokens, pos, "AND"):
		pos[0] += 1
		var right := _parse_unary(tokens, pos, ctx)
		value = value and right
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
		pos[1] = false
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
		var name := String(tok.get("v", ""))
		if not _valid_call(name, args):
			pos[1] = false
		if not pos[1] or ctx.get("validate_only", false):
			return false
		return _call(name, args, ctx)
	# 裸标识符: 条件句触发状态(未触发 = false)
	return bool(ctx.get("triggered", {}).get(String(tok.get("v", "")), false))

static func _arg(tokens: Array, pos: Array) -> String:
	var tok := _cur(tokens, pos)
	if tok.get("t", "") == "IDENT" or tok.get("t", "") == "NUMBER":
		pos[0] += 1
		return String(tok.get("v", ""))
	pos[1] = false
	return ""

static func _valid_call(name: String, args: Array) -> bool:
	if not FUNCTIONS.has(name):
		return false
	var limits: Array = FUNCTIONS[name]
	if args.size() < limits[0] or (limits[1] >= 0 and args.size() > limits[1]):
		return false
	if name == "IN":
		return String(args[0]) in ["L", "R", "M"]
	if name in ["CURRENT", "ELLE", "READ", "ACHIEVE"]:
		return String(args[1]) in ["0", "1", "2"]
	return true

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

# —— 跨关函数：CURRENT 查当前，ELLE / ACHIEVE 查历史，行号 0/1/2 = L/R/M ——
static func _eval_world(name: String, args: Array, ctx: Dictionary) -> bool:
	var world: Dictionary = ctx.get("world_state", {})
	var entry: Dictionary = {}
	if name in ["CURRENT", "ELLE", "READ", "ACHIEVE"]:
		var key := "%s:%s" % [args[0], ["L", "R", "M"][int(String(args[1]))]]
		entry = world.get("rows", {}).get(key, {})
	match name:
		"CURRENT":
			return String(entry.get("current", "")) == String(args[2])
		"ELLE", "ACHIEVE":
			var got2: Array = entry.get("achieved", [])
			for a in args.slice(2):
				if got2.has(String(a)):
					return true
			return false
		"SRANK":
			return bool(world.get("sranks", {}).get(String(args[0]), false))
		"STORY":
			return (world.get("stories", []) as Array).has(String(args[0]))
		"READ":
			return bool(entry.get("read", false))
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
	else:
		pos[1] = false
