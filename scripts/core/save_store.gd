# 只负责磁盘读写，不认识地图或结局规则。GameState 负责解释存档内容。
class_name SaveStore
extends RefCounted

const VERSION := 3

static func backup_path(path: String) -> String:
	return path.get_basename() + ".bak.json"

# 主档坏了会尝试备份。读取时不覆盖任何文件。
static func read_save(path: String) -> Dictionary:
	for candidate in [path, backup_path(path)]:
		var data := _read_valid(candidate)
		if not data.is_empty():
			return {"data": data, "recovered": candidate != path, "failed": false}
	return {"data": {}, "recovered": false,
		"failed": FileAccess.file_exists(path) or FileAccess.file_exists(backup_path(path))}

# 先完整写临时文件，再备份有效旧档，最后替换主档。
# 任一步失败都返回错误；旧档损坏时不让它覆盖健康的备份。
static func write_save(path: String, data: Dictionary) -> Error:
	if not is_valid(data):
		return ERR_INVALID_DATA
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return error
	if _read_valid(temporary).is_empty():
		return ERR_FILE_CORRUPT
	if not _read_valid(path).is_empty():
		error = DirAccess.copy_absolute(path, backup_path(path))
		if error != OK:
			return error
	return DirAccess.rename_absolute(temporary, path)

static func _read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {}
	return parser.data if is_valid(parser.data) else {}

# 拒绝“语法正确、结构错误”的 JSON，避免读档中途报错或吞掉进度。
# 未带 version 的旧档视为版本 1；未知新版本不尝试降级。
static func is_valid(data: Variant) -> bool:
	if not data is Dictionary or not data.get("rows") is Dictionary:
		return false
	var version: Variant = data.get("version", 1)
	if not _number(version) or version < 1 or version > VERSION:
		return false
	if not _number(data.get("total_rep", 0)):
		return false
	for field in ["story_flags", "achievements", "documents", "album", "profiles", "entered_levels"]:
		if not _strings(data.get(field, [])):
			return false
	if not data.get("levels", {}) is Dictionary:
		return false
	for level in data.get("levels", {}).values():
		if not level is Dictionary or not level.get("sequence", {}) is Dictionary:
			return false
		for side in level.get("sequence", {}):
			if not side in ["L", "R", "M"] or not _strings(level.sequence[side]):
				return false
	for key in data.rows:
		var parts := String(key).split(":")
		if parts.size() != 2 or parts[0].is_empty() or not parts[1] in ["L", "R", "M"]:
			return false
		var entry: Variant = data.rows[key]
		if not entry is Dictionary or not _strings(entry.get("achieved", [])):
			return false
		if not entry.get("current", "") is String or not _number(entry.get("rep", 0)):
			return false
		for field in ["read", "revealed"]:
			if not entry.get(field, false) is bool:
				return false
		var sequence: Variant = entry.get("sequence", {})
		if not sequence is Dictionary:
			return false
		for side in sequence:
			if not side in ["L", "R", "M"] or not _strings(sequence[side]):
				return false
	return true

static func _strings(value: Variant) -> bool:
	if not value is Array:
		return false
	for item in value:
		if not item is String:
			return false
	return true

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))
