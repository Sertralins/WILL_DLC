# 在 Godot 脚本编辑器运行本文件，或在终端运行 tools/run_checks.ps1。
@tool
extends EditorScript

func _run() -> void:
	preload("res://scripts/core/level_validator.gd").new().run()
