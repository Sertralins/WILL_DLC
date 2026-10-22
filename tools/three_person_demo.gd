# 用 F6 运行本场景体验三人排列。独立存档，不修改正式游戏进度。
extends "res://scenes/arrange/arrange_board.gd"

func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://templates/三人独立结局示例.json"))
	LevelData.overrides[data.level_id] = data
	GameState.save_path = "user://three_person_demo_save.json"
	GameState.load_game()
	GameState.current_level_id = data.level_id
	GameState.current_row = "L"
	GameState.retry_arrangement()
	super._ready()
