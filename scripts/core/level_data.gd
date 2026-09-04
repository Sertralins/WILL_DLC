# level_data.gd — 关卡数据模型与加载器(JSON → 结构化对象)
# 供 arrange / letter / performance / map 共用; Schema 见 docs/文件结构与开发路线.md §5。
class_name LevelData
extends RefCounted

const LEVEL_DIR := "res://data/levels/"
const INDEX_PATH := "res://data/levels/levels_index.json"
const CHARACTERS_PATH := "res://data/characters.json"

# 文本标记的运行时换算目标(控制字符, 不会与正文冲突):
# [br] → \n 换行; [page] → \f 换页; [right] → RIGHT_MARK 该行右对齐
const RIGHT_MARK := "\u001e"

var level_id: String = ""
var title: String = ""
var unlock: String = ""
var subtitle: String = ""        # 选关信息窗"小标题"(角色呼喊语, 见 选关界面文档 §2.4)
var row_count: int = 0           # 行数(原版 ROWCOUNT, 1/2/3; 决定读信/排布界面的画布分支)
var rows: Array[Row] = []        # 行数组: 单行是长度为 1 的特例
var endings: Dictionary = {}     # 结局表: { 结局id: {rank, rep, change[]} }
var conditions: Array = []       # 判定表: 按序匹配、首个命中

# 一行信件(对应原版 ROWCOUNT 的 L/R/M 行)
class Row:
	var id: String = ""           # "L" / "R" / "M"
	var title: String = ""        # 本行自己的故事标题(独立起标题; 缺省用关卡 title)
	var monologue: String = ""    # 写信人的一句独白(取信时以字幕形式出现在屏幕下方)
	var character: String = ""    # 本行默认角色, 引用 characters.json 的 id
	var anim: String = ""         # 本行动画框场景路径(关卡 JSON 里直接配; 空则回退人物的 characters.json anim)
	var position: String = ""     # 地图布局 "泳道,距离": 泳道 -2/0/2(横向平行链), 距离 = 相对父节点的生长增量
	var previous: String = ""     # 实线父边: "start"(信箱) 或 "0002:L"
	var pendings: Array = []      # 待定父边(虚线): ["0001:R(S1)", ...] 括号内为要求的结局评级集合
	var blocks: Array = []        # 固定句(黑块, TYPE 0): blocks[0] = 顶部框架, 最后一项 = 底部弹性块
	var strips: Array = []        # 可排序句(字条, TYPE 1)
	var variants: Array = []      # 条件句(TYPE 2): {id, base, text, text_key}, 结局 REPLACE 时替换 base
	var order: Array = []         # 块与字条的初始排布顺序(可选): 固定块可与字条穿插,
	                              # 如 ["PanelA1","A1","PanelA2","A2","PanelA3"];
	                              # 缺省按约定: blocks[0] → strips → blocks[1:]
	var readonly: Array = []      # 读信专用句(不进交换纸条界面, id 建议 Panel0 开头):
	                              # 只在读信/回顾页出现, 位置由 order 指定,
	                              # 无 order 时排在整封信最前(旁白/舞台说明习惯位置)
	var title_block: Dictionary = {}  # 读信标题模块(可选): {text/text_key}, 在首页左上角演出;
	                              # 缺省回退到第一句 Panel0 的第一行

# —— 加载接口 ——

# 测试注入: level_id → 关卡数据字典(内存构造, 优先于磁盘 JSON; 工具 probe 用, 游戏流程不写)
static var overrides: Dictionary = {}

static func load_level(id: String) -> LevelData:
	var lv := LevelData.new()
	if overrides.has(id):
		lv._from_dict(overrides[id])
		return lv
	var path := LEVEL_DIR + id + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法打开关卡数据: %s" % path)
		return lv
	var data = JSON.parse_string(file.get_as_text())
	if data == null or not (data is Dictionary):
		push_error("关卡数据解析失败: %s" % path)
		return lv
	lv._from_dict(data)
	return lv

static func load_index() -> Dictionary:
	return _load_json_dict(INDEX_PATH)

# 手动栅格位置表: levels_index.json 的 "positions", key = "<level_id>:<row_id>", value = [gx, gy]
# (gx 以半列宽 222px 为一格, gy 以 80px 为一格; 未登记的节点走 map.gd 的自动布局)
static func load_positions() -> Dictionary:
	var index := load_index()
	var v = index.get("positions", {})
	return v if v is Dictionary else {}

static func load_characters() -> Dictionary:
	return _load_json_dict(CHARACTERS_PATH)

static func _load_json_dict(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法打开数据文件: %s" % path)
		return {}
	var data = JSON.parse_string(file.get_as_text())
	if data == null or not (data is Dictionary):
		push_error("数据解析失败: %s" % path)
		return {}
	return data

# —— 解析 ——

func _from_dict(data: Dictionary) -> void:
	level_id = String(data.get("level_id", ""))
	title = String(data.get("title", ""))
	unlock = String(data.get("unlock", ""))
	subtitle = String(data.get("subtitle", ""))
	row_count = int(data.get("row_count", 0))
	endings = data.get("endings", {})
	conditions = data.get("conditions", [])
	for row_data in data.get("rows", []):
		var row := Row.new()
		row.id = String(row_data.get("id", ""))
		row.title = String(row_data.get("title", ""))
		row.monologue = String(row_data.get("monologue", ""))
		row.character = String(row_data.get("character", ""))
		row.anim = String(row_data.get("anim", ""))
		row.position = String(row_data.get("position", ""))
		row.previous = String(row_data.get("previous", ""))
		row.pendings = parse_pendings(row_data.get("pendings", []))
		row.blocks = row_data.get("blocks", [])
		row.strips = row_data.get("strips", [])
		row.variants = row_data.get("variants", [])
		row.order = row_data.get("order", [])
		row.readonly = row_data.get("readonly", [])
		row.title_block = row_data.get("title_block", {})
		rows.append(row)
	if row_count <= 0:
		row_count = rows.size()

# 待定边解析: 数组或 "&" 分隔字符串 → [{from: "0001:R", ranks: ["S1", ...]}, ...]
static func parse_pendings(v) -> Array:
	var raw := ""
	if v is Array:
		var parts: Array = []
		for x in v:
			parts.append(String(x))
		raw = "&".join(PackedStringArray(parts))
	else:
		raw = String(v)
	var out: Array = []
	for part in raw.split("&", false):
		part = part.strip_edges()
		if part == "":
			continue
		var i := part.find("(")
		if i < 0:
			out.append({"from": part, "ranks": []})
			continue
		var ranks := part.substr(i + 1, part.length() - i - 2).split(",")
		out.append({"from": part.substr(0, i), "ranks": ranks})
	return out

# —— 访问 ——

func row_by_id(id: String) -> Row:
	for row in rows:
		if row.id == id:
			return row
	return null

func first_row() -> Row:
	return rows[0] if rows.size() > 0 else null

# 句子文本取值: 优先内联 text, 其次 text_key → 剧情文本表(<level_id>.txt, PO 格式);
# 都找不到时原样返回 text_key(便于一眼发现漏配)。
# 统一标记换算(内联 text 同样支持): [br] → 换行, [page] → \f 换页标记
func sentence_text(s: Dictionary) -> String:
	var t := String(s.get("text", ""))
	if t != "":
		return _normalize_text(t)
	var key := String(s.get("text_key", ""))
	var table := _text_table()
	if table.has(key):
		return _normalize_text(String(table[key]))
	return key

static func _normalize_text(text: String) -> String:
	return text.replace("[br]", "\n").replace("[page]", "\f").replace("[right]", RIGHT_MARK)

# —— 剧情文本表 ——
# 文本文件与关卡 JSON 同目录、同名 .txt, PO-lite 格式(仿原版 strings.po):
#   msgctxt "STRINGS.DIALOG.CONTENT.<text_key>"  ← 前缀剥离后即 JSON 里的 text_key
#   msgid ""
#   msgstr "正文[br]\n" ...                     ← [br] = 换行; 引号内 \n = 段落换行; 相邻引号串拼接
static var _text_tables: Dictionary = {}   # level_id → { text_key: 正文 }

static func load_texts(level_id: String) -> Dictionary:
	if not _text_tables.has(level_id):
		_text_tables[level_id] = _parse_po(LEVEL_DIR + level_id + ".txt")
	return _text_tables[level_id]

func _text_table() -> Dictionary:
	return load_texts(level_id)

# PO-lite 解析: 逐行读 msgctxt / msgstr, 跳过 msgid、注释与空行
static func _parse_po(path: String) -> Dictionary:
	var table := {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return table  # 文本文件不存在时静默(允许关卡 JSON 内联 text)
	var current_key := ""
	var lines: Array = []
	while not file.eof_reached():
		var line := file.get_line()
		if line.begins_with("msgctxt "):
			if current_key != "":
				table[current_key] = _join_po_lines(lines)
			# 取 msgctxt 最后一个点分段作为 text_key("STRINGS.DIALOG.CONTENT.0001_A1" → "0001_A1")
			var parts := _unquote(line.substr(8)).split(".")
			current_key = String(parts[parts.size() - 1])
			lines = []
		elif line.begins_with("msgstr "):
			lines.append(_unquote(line.substr(7)))
		elif line.begins_with('"'):
			lines.append(_unquote(line))
	if current_key != "":
		table[current_key] = _join_po_lines(lines)
	return table

# 去掉首尾引号并反转义(PO 常用转义: \n \t \" \\)
static func _unquote(s: String) -> String:
	var t := s.strip_edges()
	if t.length() >= 2 and t.begins_with('"') and t.ends_with('"'):
		t = t.substr(1, t.length() - 2)
	t = t.replace("\\n", "\n").replace("\\t", "\t").replace('\\"', '"').replace("\\\\", "\\")
	return t

# 拼接一条 msgstr 的相邻引号串; [br] → 换行; [page] → \f 换页标记(读信按页展示);
# [right] → RIGHT_MARK 该行右对齐(读信排版用); 其余 [标签] 剔除(演绎阶段再解析指令)
static func _join_po_lines(lines: Array) -> String:
	var text := ""
	for line in lines:
		text += String(line)
	text = text.replace("[br]", "\n")
	text = text.replace("[page]", "\f")
	text = text.replace("[right]", RIGHT_MARK)
	var tag := RegEx.create_from_string("\\[[^\\]]*\\]")
	text = tag.sub(text, "", true)
	return text

# 一行是否为读信专用句(不进交换纸条界面)
func is_readonly(row: Row, id: String) -> bool:
	for s in row.readonly:
		if String(s.get("id", "")) == id:
			return true
	return false

# 一行的初始布局序列(交换纸条界面, 块与字条可穿插): 行级 order 字段优先(剔除读信专用句),
# 缺省按约定 = 首固定块 → 字条 → 其余固定块
func layout_sequence(row: Row) -> Array[String]:
	if not row.order.is_empty():
		var out: Array[String] = []
		for id in row.order:
			if not is_readonly(row, String(id)):
				out.append(String(id))
		return out
	var seq: Array[String] = []
	if row.blocks.size() > 0:
		seq.append(String(row.blocks[0].get("id", "")))
	for strip in row.strips:
		seq.append(String(strip.get("id", "")))
	for i in range(1, row.blocks.size()):
		seq.append(String(row.blocks[i].get("id", "")))
	return seq

# 一行的初始阅读序列(句子字典): 读信专用句包含在内, 位置由 order 指定;
# 无 order 时读信专用句排在整封信最前(旁白/舞台说明习惯位置), 其余按约定
func initial_sequence(row: Row) -> Array:
	var seq: Array = []
	if not row.order.is_empty():
		for id in row.order:
			var info := find_sentence(String(id))
			if not info.is_empty():
				seq.append(info["sentence"])
		return seq
	for s in row.readonly:
		seq.append(s)
	for id in layout_sequence(row):
		var info := find_sentence(id)
		if not info.is_empty():
			seq.append(info["sentence"])
	return seq

# 全关查找句子(排列还原 / 重排阅览 / 演绎拼接用):
# 返回 { "sentence": {id, text, ...}, "row": Row }, 找不到返回 {}
func find_sentence(id: String) -> Dictionary:
	for row in rows:
		for s in row.blocks:
			if String(s.get("id", "")) == id:
				return {"sentence": s, "row": row}
		for s in row.strips:
			if String(s.get("id", "")) == id:
				return {"sentence": s, "row": row}
		for s in row.variants:
			if String(s.get("id", "")) == id:
				return {"sentence": s, "row": row}
		for s in row.readonly:
			if String(s.get("id", "")) == id:
				return {"sentence": s, "row": row}
	return {}

# 结局 CHANGE 拆成两张查找表: { "replace": base_id → variant_id, "remove": {id: true} }
func change_maps(changes: Array) -> Dictionary:
	var replace_map := {}   # base_id → variant_id
	var remove_ids := {}    # 被删除的句子 id
	for change in changes:
		var ctype := String(change.get("type", ""))
		var data := String(change.get("data", ""))
		match ctype:
			"REPLACE":
				var info := find_sentence(data)
				if not info.is_empty():
					replace_map[String(info["sentence"].get("base", ""))] = data
			"DRA", "D":
				remove_ids[data] = true
	return {"replace": replace_map, "remove": remove_ids}

# 应用结局 CHANGE 后的最终序列文本(重排阅览/演绎用):
# REPLACE → base 句换成条件句正文; DRA/D → 该句删除
func apply_changes(seq: Array, changes: Array) -> Array:
	var maps := change_maps(changes)
	var replace_map: Dictionary = maps.get("replace", {})
	var remove_ids: Dictionary = maps.get("remove", {})
	var texts: Array = []
	for id in seq:
		var sid := String(id)
		if remove_ids.has(sid):
			continue
		if replace_map.has(sid):
			sid = String(replace_map[sid])
		var info2 := find_sentence(sid)
		if info2.is_empty():
			continue
		texts.append(sentence_text(info2["sentence"]))
	return texts
