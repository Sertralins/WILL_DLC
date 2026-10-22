# 全局状态：save_data 是持久进度，其他字段是界面状态或查询索引。
# 修改进度请调用本类方法；不要直接写 history / sranks 等派生索引。
extends Node

const Store := preload("res://scripts/core/save_store.gd")
const ROW_IDS := ["L", "R", "M"]
const LEVEL_DIR := "res://data/levels/"

# —— 当前场景状态（重启从地图进入，不恢复半截演出）——
const Session := preload("res://scripts/core/game_session.gd")
var session := Session.new()

var current_level_id: String:
	get: return session.current_level_id
	set(value): session.current_level_id = value
var current_row: String:
	get: return session.current_row
	set(value): session.current_row = value
var sequences: Dictionary:
	get: return session.sequences
	set(value): session.sequences = value
var sequences_level: String:
	get: return session.sequences_level
	set(value): session.sequences_level = value
var verdicts: Dictionary:
	get: return session.verdicts
	set(value): session.verdicts = value
var review_letter: bool:
	get: return session.review_letter
	set(value): session.review_letter = value
var review_queue: Array:
	get: return session.review_queue
	set(value): session.review_queue = value
var first_entry_level: bool:
	get: return session.first_entry_level
	set(value): session.first_entry_level = value

# —— 存档与只读查询索引 ——
var save_path := "user://save.json"
var save_data: Dictionary = {}
var history: Dictionary = {}
var read_rows: Dictionary = {}
var sranks: Dictionary = {}
var unlocked_endings: Array = []
var revealed_nodes: Array = []
var entered_levels: Array = []
var total_rep := 0
var last_save_error: Error = OK
var recovered_from_backup := false
var _load_failed := false

func _ready() -> void:
	load_game()
	current_level_id = String(LevelData.load_index().get("start", "0001"))

func current_level_path() -> String:
	return LEVEL_DIR + current_level_id + ".json"

func new_save() -> Dictionary:
	return {
		"version": Store.VERSION, "levels": {}, "rows": {}, "story_flags": [], "achievements": [],
		"documents": [], "album": [], "profiles": [], "entered_levels": [], "total_rep": 0,
	}

# 修改某行前从这里取条目，默认值会写回存档。
func row(key: String) -> Dictionary:
	if not save_data.has("rows"):
		save_data = new_save()
	if not save_data.rows.has(key):
		save_data.rows[key] = {"read": false, "achieved": [], "current": "", "rep": 0, "revealed": false}
	return save_data.rows[key]

func row_read(key: String) -> bool:
	return bool(save_data.get("rows", {}).get(key, {}).get("read", false))

func row_revealed(key: String) -> bool:
	return bool(save_data.get("rows", {}).get(key, {}).get("revealed", false))

# 地图解锁与结局判定共用，CURRENT / READ 等直接查询行存档。
func world_state() -> Dictionary:
	return {"rows": save_data.get("rows", {}), "sranks": sranks,
		"stories": save_data.get("story_flags", []), "achievements": save_data.get("achievements", [])}

func mark_level_entered(level_id: String) -> bool:
	if entered_levels.has(level_id):
		return false
	save_data["entered_levels"].append(level_id)
	save_game()
	return true

func mark_row_read(row_id: String) -> void:
	if LevelData.load_level(current_level_id).row_by_id(row_id) != null:
		set_row_read("%s:%s" % [current_level_id, row_id])

func set_row_read(key: String) -> void:
	row(key)["read"] = true
	save_game()

func set_row_revealed(key: String) -> void:
	row(key)["revealed"] = true
	save_game()

func next_unread_row(after_row_id: String) -> String:
	var level := LevelData.load_level(current_level_id)
	var after := after_row_id.is_empty()
	for letter in level.rows:
		if after and not row_read("%s:%s" % [current_level_id, letter.id]):
			return letter.id
		if letter.id == after_row_id:
			after = true
	return ""

# 判定引擎只计算结果；进度、声望、排列统一在此保存。
func record_verdict(level: LevelData, result: Dictionary, arrangement: Dictionary) -> bool:
	var previous_save := save_data.duplicate(true)
	var awarded := 0
	var any_new := false
	var legacy_new: bool = not history.get(level.level_id, []).has(result.get("ending_id", ""))
	for letter in level.rows:
		var item: Dictionary = result.get("rows", {}).get(letter.id, result)
		var ending_id := String(item.ending_id)
		var entry := row("%s:%s" % [level.level_id, letter.id])
		var achieved: Array = entry.get("achieved", []).duplicate()
		var is_new: bool = not achieved.has(ending_id) if level.has_row_endings() else legacy_new
		item["is_new"] = is_new
		item["awarded_rep"] = int(item.rep) if is_new else 0
		any_new = any_new or is_new
		if level.has_row_endings():
			awarded += int(item.awarded_rep)
		achieved.erase(ending_id)
		achieved.append(ending_id)
		entry.merge({"achieved": achieved, "current": ending_id, "rep": int(item.rep)}, true)
		entry.erase("sequence")
	if not level.has_row_endings():
		awarded = int(result.rep) if legacy_new else 0
	# 排列属于整关，仅保存一份；每行历史和当前结局独立保存。
	save_data.get_or_add("levels", {})[level.level_id] = {"sequence": arrangement.duplicate(true)}
	save_data["total_rep"] = int(save_data.get("total_rep", 0)) + awarded
	result["is_new"] = any_new
	result["awarded_rep"] = awarded
	if not save_game():
		save_data = previous_save
		_rebuild_indexes()
		return false
	verdicts = result
	sequences = arrangement.duplicate(true)
	sequences_level = level.level_id
	session.phase = Session.Phase.DECIDING
	return true

func row_history(key: String) -> Array:
	return save_data.get("rows", {}).get(key, {}).get("achieved", []).duplicate()

func retry_arrangement() -> void:
	verdicts = {}
	review_letter = false
	review_queue = []
	session.phase = Session.Phase.ARRANGING

func reset_arrangement() -> void:
	sequences = {}
	sequences_level = ""

func begin_review(rows: Array) -> void:
	review_queue = rows.duplicate()
	review_letter = not rows.is_empty()
	if review_letter:
		current_row = String(rows[0])
	session.phase = Session.Phase.REVIEWING if review_letter else Session.Phase.RESULT

func advance_review() -> bool:
	if not review_queue.is_empty():
		review_queue.pop_front()
	begin_review(review_queue)
	return review_letter

func enter_level(level_id: String, row_id: String) -> void:
	_clear_session()
	current_level_id = level_id
	current_row = row_id
	first_entry_level = mark_level_entered(level_id)

func save_game() -> bool:
	if not Store.is_valid(save_data):
		last_save_error = ERR_INVALID_DATA
		push_warning("进度结构不合法，未覆盖磁盘存档。")
		return false
	_rebuild_indexes()
	if _load_failed:
		last_save_error = ERR_FILE_CORRUPT
		push_warning("存档和备份均无法读取，已保留原文件；修复存档或明确新建游戏后再保存。")
		return false
	save_data["version"] = Store.VERSION
	last_save_error = Store.write_save(save_path, save_data)
	if last_save_error != OK:
		push_warning("保存失败（%s）：%s" % [error_string(last_save_error), save_path])
	return last_save_error == OK

func load_game() -> void:
	var loaded := Store.read_save(save_path)
	_load_failed = loaded.failed
	recovered_from_backup = loaded.recovered
	save_data = new_save()
	# 用默认值补齐旧档缺少的字段，保留原进度和未知字段。
	save_data.merge(loaded.data, true)
	save_data["version"] = Store.VERSION
	_clear_session()
	_rebuild_indexes()
	last_save_error = ERR_FILE_CORRUPT if _load_failed else OK
	if recovered_from_backup:
		push_warning("主存档不可用，已从备份恢复进度。")
	elif _load_failed:
		push_warning("存档和备份不可用，原文件未改动。")

# 所有查询索引只在这里生成，使读档和保存后的行为一致。
func _rebuild_indexes() -> void:
	history = {}
	read_rows = {}
	sranks = {}
	unlocked_endings = []
	revealed_nodes = []
	var levels := {}
	for key in save_data.get("rows", {}):
		var entry: Dictionary = save_data.rows[key]
		var parts := String(key).split(":")
		var level_id := parts[0]
		var index := ROW_IDS.find(parts[1])
		if not levels.has(level_id):
			levels[level_id] = _existing_level(level_id)
		var level: LevelData = levels[level_id]
		var achieved: Array = history.get(level_id, [])
		for ending in entry.get("achieved", []):
			if not achieved.has(ending):
				achieved.append(ending)
				unlocked_endings.append("%s:%s" % [level_id, ending])
			if level != null and level.has_row_endings():
				unlocked_endings.append("%s:%s" % [key, ending])
			if level != null and String(level.endings_for(parts[1]).get(ending, {}).get("rank", "")) == "S":
				sranks[level_id] = true
		history[level_id] = achieved
		if entry.get("read", false):
			var read: Array = read_rows.get(level_id, [])
			if not read.has(index):
				read.append(index)
			read_rows[level_id] = read
		if entry.get("revealed", false):
			revealed_nodes.append(key)
	# 独立模式的整关 SRANK 要求各行都曾获 S；行级历史仍可单独查询。
	for level_id in levels:
		var level: LevelData = levels[level_id]
		if level == null or not level.has_row_endings():
			continue
		var all_s := true
		for letter in level.rows:
			var has_s := false
			for ending in row_history("%s:%s" % [level_id, letter.id]):
				has_s = has_s or String(level.endings_for(letter.id).get(ending, {}).get("rank", "")) == "S"
			all_s = all_s and has_s
		if all_s:
			sranks[level_id] = true
		else:
			sranks.erase(level_id)
	total_rep = int(save_data.get("total_rep", 0))
	entered_levels = save_data.get("entered_levels", []).duplicate()

# 旧存档可能含已移除的关卡，保留进度但不反复报告资源不存在。
func _existing_level(id: String) -> LevelData:
	if LevelData.overrides.has(id) or FileAccess.file_exists(LEVEL_DIR + id + ".json"):
		return LevelData.load_level(id)
	return null

# 地图只负责选择关卡，恢复结果与排列由状态层完成，不再由 UI 拼装。
func restore_verdict(level_id: String, row_id: String) -> void:
	var level := LevelData.load_level(level_id)
	var results := {}
	for letter in level.rows:
		var entry := row("%s:%s" % [level_id, letter.id])
		var current := String(entry.get("current", ""))
		var achieved: Array = entry.get("achieved", [])
		if current.is_empty() and not achieved.is_empty():
			current = String(achieved.back())
		var endings := level.endings_for(letter.id)
		if not endings.has(current):
			continue
		var ending: Dictionary = endings[current]
		results[letter.id] = {"level_id": level_id, "ending_id": current,
			"rank": String(ending.get("rank", "")), "rep": int(ending.get("rep", 0)),
			"awarded_rep": 0, "is_new": false, "changes": ending.get("change", []).duplicate(true)}
	if results.is_empty():
		retry_arrangement()
		reset_arrangement()
		return
	verdicts = {"level_id": level_id, "rows": results, "independent": level.has_row_endings(), "awarded_rep": 0, "is_new": false}
	if not level.has_row_endings():
		verdicts.merge(results.get(row_id, results.values()[0]), true)
	var snapshot: Dictionary = save_data.get("levels", {}).get(level_id, {}).get("sequence", {})
	session.phase = Session.Phase.RESULT
	# 兼容只在另一行保存过排列的旧档。
	if not level.is_valid_arrangement(snapshot):
		for letter in level.rows:
			var candidate: Dictionary = row("%s:%s" % [level_id, letter.id]).get("sequence", {})
			if level.is_valid_arrangement(candidate):
				snapshot = candidate
				break
	# 空数组、旧节点名、改版后缺失的纸条都不能用于恢复。
	# 只修复排列，不清空历史结局、评级或声望；下次决定时会正常保存新排列。
	sequences = snapshot.duplicate(true) if level.is_valid_arrangement(snapshot) else level.initial_arrangement()
	sequences_level = level_id

func _clear_session() -> void:
	session = Session.new()
	sequences = {}
	sequences_level = ""
	verdicts = {}
	review_letter = false
	review_queue = []
	first_entry_level = false
	current_row = "L"

# 新游戏或隔离测试使用；调用者必须先选好 save_path。
func reset_save() -> void:
	save_data = new_save()
	_load_failed = false
	recovered_from_backup = false
	last_save_error = OK
	_clear_session()
	_rebuild_indexes()
	for path in [save_path, Store.backup_path(save_path), save_path + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
