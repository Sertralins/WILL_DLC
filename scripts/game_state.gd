# game_state.gd — 全局游戏状态(纯数据单例, autoload 注册名: GameState)
#
# 职责(见 docs/架构设计.md 第 3 节):
# - 向各场景提供"当前游戏相关的数据"(当前关卡、数据文件路径);
# - 存放跨场景共享的运行时状态(字条排列、判定结果、已解锁结局);
# - 不引用任何场景、不参与场景切换(跳转统一走 GameFlow)。
extends Node

# —— 数据路径 ——
# 关卡数据: 每关一个 JSON(data/levels/<id>.json), 索引与角色档案的读取见 LevelData
const LEVEL_DIR := "res://data/levels/"

# 当前关卡与当前阅览的信件行(信件墙/map 场景建好后由它改写)
var current_level_id: String = "0001"
var current_row: String = "L"

# —— 运行时状态(跨场景共享, 场景只负责读写) ——

# 各行字条排列序列: { 行id: [句子id序列] }
# ArrangeBoard 点「执行」时写入; RuleEngine 的输入来源(docs/文件结构与开发路线.md §5)
var sequences: Dictionary = {}

# 排列快照所属的关卡 id(判定"回到排布场景时是否按快照还原排列")
var sequences_level: String = ""

# 重排后阅览模式: 执行后 letter 场景按当前排列重放信件(临时状态, 不存档)
var review_letter: bool = false

# 重排阅览队列: 执行后需要重放的行 id 列表(每读完一行弹出一个)
var review_queue: Array = []

# 判定结果: 结局 id / 声望 / CHANGE 应用(RuleEngine 写入, 结算场景展示)
var verdicts: Dictionary = {}

# 已解锁的结局 id 列表("关卡id:结局id"条目, 结局图鉴与重玩的数据来源)
var unlocked_endings: Array = []

# 信件墙已生长的节点 id 列表("关卡id:行id"条目; map 场景邮箱生长动画后写入)
var revealed_nodes: Array = []

# 跨关历史: 本关已达成结局列表 { level_id: [ending_id] }(CURRENT/ELLE 查询、图鉴数据源)
var history: Dictionary = {}

# 已读行记录 { level_id: [row_index] }(READ 函数查询)
var read_rows: Dictionary = {}

# 已点进过的关卡 id 列表(回顾页「开始!」按钮判定: 非首次进入该关卡)
var entered_levels: Array = []

# 本次点进是否为该关卡的首次进入(地图点进时写入, 回顾页读取; 瞬态, 不存档)
var first_entry_level: bool = false

# S 评级记录 { level_id: true }(SRANK 函数查询)
var sranks: Dictionary = {}

# 累计声望(REP 跨关累积)
var total_rep: int = 0

func _ready() -> void:
	load_game()
	# 从关卡索引取起始关卡; 信件墙建好后, 由玩家选择改写 current_level_id
	var index := LevelData.load_index()
	current_level_id = String(index.get("start", "0001"))

# —— 数据访问接口 ——

# 当前关卡数据文件路径(每关一个 JSON)
func current_level_path() -> String:
	return LEVEL_DIR + current_level_id + ".json"

# —— 阅读流程 ——

# 记录一行已读(read_rows: { level_id: [行索引] }, READ() 查询与阅读流程共用)
func mark_row_read(row_id: String) -> void:
	var level := LevelData.load_level(current_level_id)
	var idx := -1
	for i in level.rows.size():
		if String(level.rows[i].id) == row_id:
			idx = i
			break
	if idx < 0:
		return
	var list: Array = read_rows.get(current_level_id, [])
	if not list.has(idx):
		list.append(idx)
	read_rows[current_level_id] = list

# 记录一次"点进关卡": 返回是否首次进入(地图场景点块进读信时调用)
func mark_level_entered(level_id: String) -> bool:
	if entered_levels.has(level_id):
		return false
	entered_levels.append(level_id)
	save_game()
	return true

# 本关尚未读过的下一行 id(从 after_row_id 之后开始找; 全部读完返回 "")
func next_unread_row(after_row_id: String) -> String:
	var level := LevelData.load_level(current_level_id)
	var start := -1
	for i in level.rows.size():
		if String(level.rows[i].id) == after_row_id:
			start = i
			break
	var list: Array = read_rows.get(current_level_id, [])
	for i in range(start + 1, level.rows.size()):
		if not list.has(i):
			return String(level.rows[i].id)
	return ""

# —— 序列化(存档 = dump 本对象, 读档 = 反向恢复) ——

func to_dict() -> Dictionary:
	return {
		"current_level_id": current_level_id,
		"current_row": current_row,
		"sequences": sequences,
		"sequences_level": sequences_level,
		"verdicts": verdicts,
		"unlocked_endings": unlocked_endings,
		"revealed_nodes": revealed_nodes,
		"history": history,
		"read_rows": read_rows,
		"entered_levels": entered_levels,
		"sranks": sranks,
		"total_rep": total_rep,
	}

func from_dict(data: Dictionary) -> void:
	current_level_id = String(data.get("current_level_id", "0001"))
	current_row = String(data.get("current_row", "L"))
	sequences = data.get("sequences", {})
	sequences_level = String(data.get("sequences_level", ""))
	verdicts = data.get("verdicts", {})
	unlocked_endings = data.get("unlocked_endings", [])
	revealed_nodes = data.get("revealed_nodes", [])
	history = data.get("history", {})
	read_rows = data.get("read_rows", {})
	entered_levels = data.get("entered_levels", [])
	sranks = data.get("sranks", {})
	total_rep = int(data.get("total_rep", 0))

# —— 存档(选关判定链与存档数据结构-Godot实现 §3.3) ——
# rows 主表: { "关卡:行": {read, achieved, current, rep, revealed} } + 收集项;
# 双槽 JSON(对应原版 gamedata00/01): 写前旧档改名 .bak 备份
var save_path := "user://save.json"
var save_data: Dictionary = {}

func new_save() -> Dictionary:
	return {
		"rows": {},
		"story_flags": [],
		"achievements": [],
		"documents": [],
		"album": [],
		"profiles": [],
		"entered_levels": [],
		"total_rep": 0,
	}

# 一行(节点)的存档条目, 缺省创建
func row(key: String) -> Dictionary:
	var rows: Dictionary = save_data.get("rows", {})
	if not rows.has(key):
		rows[key] = {"read": false, "achieved": [], "current": "", "rep": 0, "revealed": false}
	return rows[key]

func row_read(key: String) -> bool:
	return bool(row(key).get("read", false))

func row_revealed(key: String) -> bool:
	return bool(row(key).get("revealed", false))

func save_game() -> void:
	var rows: Dictionary = save_data.get("rows", {})
	for key in rows:
		rows[key]["achieved"] = history.get(String(key).split(":")[0], [])
	save_data["total_rep"] = total_rep
	save_data["entered_levels"] = entered_levels
	var bak := save_path.get_basename() + ".bak.json"
	if FileAccess.file_exists(save_path):
		var d := DirAccess.open("user://")
		if d != null:
			if d.file_exists(bak):
				d.remove(bak)
			d.rename(save_path.get_file(), bak)
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(save_data, "\t"))
		f.close()

func load_game() -> void:
	if not FileAccess.file_exists(save_path):
		save_data = new_save()
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not (data is Dictionary):
		save_data = new_save()
		return
	save_data = data
	# 从 rows 恢复兼容字段(其他场景读 history/read_rows/sranks/revealed_nodes)
	history.clear()
	read_rows.clear()
	sranks.clear()
	revealed_nodes.clear()
	var rows: Dictionary = save_data.get("rows", {})
	for key in rows:
		var r: Dictionary = rows[key]
		var parts := String(key).split(":")
		var lv := parts[0]
		var idx := ["L", "R", "M"].find(parts[1] if parts.size() > 1 else "L")
		for rk in r.get("achieved", []):
			var got: Array = history.get(lv, [])
			if not got.has(rk):
				got.append(rk)
				history[lv] = got
		if r.get("read", false) and idx >= 0:
			var rd: Array = read_rows.get(lv, [])
			if not rd.has(idx):
				rd.append(idx)
				read_rows[lv] = rd
		if r.get("revealed", false):
			revealed_nodes.append(key)
	total_rep = int(save_data.get("total_rep", 0))
	entered_levels = save_data.get("entered_levels", [])

# 取信 = 标记该行已读(新信件消失)并落盘(判定链文档 §4.3 第6步)
func set_row_read(key: String) -> void:
	row(key)["read"] = true
	var parts := String(key).split(":")
	var idx := ["L", "R", "M"].find(parts[1] if parts.size() > 1 else "L")
	if idx >= 0:
		var rd: Array = read_rows.get(parts[0], [])
		if not rd.has(idx):
			rd.append(idx)
			read_rows[parts[0]] = rd
	save_game()

# 节点生长 = 标记 revealed(动画只播一次, 重进地图直接呈现)并落盘(§4.3 第4步)
func set_row_revealed(key: String) -> void:
	row(key)["revealed"] = true
	if not revealed_nodes.has(key):
		revealed_nodes.append(key)
	save_game()

# 测试/新游戏: 清空内存与磁盘存档
func reset_save() -> void:
	save_data = new_save()
	history.clear()
	read_rows.clear()
	entered_levels.clear()
	first_entry_level = false
	sranks.clear()
	revealed_nodes.clear()
	unlocked_endings.clear()
	total_rep = 0
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	var bak := save_path.get_basename() + ".bak.json"
	if FileAccess.file_exists(bak):
		DirAccess.remove_absolute(bak)
