# GameFlow.gd — 流程控制器(autoload 注册名: GameFlow)
#
# 职责(见 架构设计.md 第 3/4 节):
# - 全项目唯一的场景切换入口 goto(): 场景之间永不互相跳转;
# - 信号总线: 各场景只对外发"完成"类信号, 由本节点统一监听、推进流程;
# - 不存剧情数据(数据都在 GameState)。
extends Node

# —— 场景注册表 ——
# 全项目唯一维护场景路径的地方; 场景代码里禁止出现 change_scene_to_file。
const SCENES := {
	"map": "res://scenes/map/map.tscn",                   # 信件墙/选关(邮箱生长新信件, 点击进入读信)
	"letter": "res://scenes/letter/letter_reader.tscn",   # 信件阅览(打字机; 初始逐封阅读 / 新结局重放)
	"recap": "res://scenes/recap/recap.tscn",             # 信件回顾页(读完信进入: 滚动阅览全文 + 另一封/回想/返回/开始!)
	"arrange": "res://scenes/arrange/arrange_board.tscn",    # 交换字条主界面
	"verdict": "res://scenes/verdict/verdict.tscn",       # 结算(评级 + 声望 + 已解锁结局)
}

# 切换场景(唯一入口): GameFlow.goto("arrange")
func goto(scene_key: String) -> void:
	var path: String = String(SCENES.get(scene_key, ""))
	if path.is_empty():
		push_error("GameFlow: 未知场景 key: %s" % scene_key)
		return
	get_tree().change_scene_to_file(path)
