# GameFlow.gd — 流程控制器(autoload 注册名: GameFlow)
#
# 职责(见 架构设计.md 第 3/4 节):
# - 全项目唯一的场景切换入口 goto(): 场景之间永不互相跳转;
# - 各界面在完成阅读或决定后调用 goto；本节点统一维护路径和切换错误处理。
# - 不存剧情数据(数据都在 GameState)。
extends Node

# —— 场景注册表 ——
# 全项目唯一维护场景路径的地方; 场景代码里禁止出现 change_scene_to_file。
const SCENES := {
	"map": "res://scenes/map/map.tscn",                   # 信件墙/选关(邮箱生长新信件, 点击进入读信)
	"letter": "res://scenes/letter/letter_reader.tscn",   # 信件阅览(打字机; 初始逐封阅读 / 新结局重放)
	"recap": "res://scenes/recap/recap.tscn",             # 信件回顾页(读完信进入: 滚动阅览全文 + 另一封/回想/返回/开始!)
	"arrange": "res://scenes/arrange/arrange_board.tscn",    # 交换字条主界面(判定后的白底锁定态即结算展示)
}

# 上一个界面用于区分地图重新进入与判定演出返回，不写入玩家存档。
var previous_scene := ""

# 切换场景(唯一入口): GameFlow.goto("arrange")
func goto(scene_key: String) -> void:
	var path: String = String(SCENES.get(scene_key, ""))
	if path.is_empty():
		push_error("GameFlow: 未知场景 key: %s" % scene_key)
		return
	var source := ""
	var current := get_tree().current_scene
	if current:
		for key in SCENES:
			if SCENES[key] == current.scene_file_path:
				source = key
	var error := get_tree().change_scene_to_file(path)
	if error == OK:
		previous_scene = source
	if error != OK:
		push_error("场景切换失败：%s (%s)" % [path, error_string(error)])
