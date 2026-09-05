# map_debug_test.gd — 从"开启信箱"开始调试某一关
# 用法: 改下面两个常量 → 在编辑器里打开 tools/map_debug_test.tscn 按 F6 运行
#   - TARGET_LEVEL: 要调试的关卡 id(它的 unlock 必须被 PREP 满足, 否则不会作为新信件出现)
#   - PREP_HISTORY: 解锁表达式依赖的历史结局(对应 GameState.history), 比如 0002 要 0001 达成过 BAD1
# 运行后信箱自动打开, 新信件按真实流程列出; 然后像正式游戏一样手动点信封/方块调试。
# 调试用独立存档 user://save_debug.json, 不污染真实存档。
extends "res://scripts/ui/map/map.gd"

const TARGET_LEVEL := "0001"
const PREP_HISTORY := {}

func _ready() -> void:
	GameState.save_path = "user://save_debug.json"
	GameState.reset_save()
	super._ready()
	_run()

func _run() -> void:
	await get_tree().process_frame
	for lv in PREP_HISTORY:
		GameState.history[lv] = (PREP_HISTORY[lv] as Array).duplicate()
	# 可选: 把目标关之前链上的节点直接标记"已读+已生长",
	# 这样点目标关的信封时链回溯不会把前面的关卡也演一遍:
	#   GameState.set_row_read("0001:L")
	#   GameState.set_row_revealed("0001:L")
	_on_mailbox()
	print("D: 信箱已打开, 可手动调试 %s (存档: save_debug.json)" % TARGET_LEVEL)
