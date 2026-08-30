# tools/arrange_probe.gd — 排布场景结算态冒烟/截图:
#   默认: 预置一份 0001 的 S1 判定, 实例化排布场景(锁定态), 等 3 帧打印关键节点状态后退出
#   -- shot: 等 60 帧后用引擎自身截图存 user://arrange_shot.png 后退出
#   -- unlocked: 不预置判定(解锁态)
extends Control

func _ready() -> void:
	GameState.current_level_id = "0001"
	var args := OS.get_cmdline_user_args()
	if "unlocked" in args:
		GameState.verdicts = {}
	else:
		GameState.verdicts = {
			"level_id": "0001", "ending_id": "S1", "rank": "S", "rep": 325,
			"matched_index": 0, "changes": [{"type": "REPLACE", "data": "PanelB2_1"}],
		}
	var arr: Control = load("res://scenes/arrange/arrange_board.tscn").instantiate()
	add_child(arr)
	if "shot" in args:
		for i in 60:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://arrange_shot.png")
		print("saved user://arrange_shot.png size=", img.get_size())
		get_tree().quit()
		return
	for i in 3:
		await get_tree().process_frame
	print("locked=", arr.locked, " white=", arr.white_bg.visible, " retry=", arr.retry_btn.visible,
		" decide=", arr.decide_btn.visible, " rankL=", arr.rank_tags[0].visible,
		" rankR=", arr.rank_tags[1].visible)
	var cond: PanelContainer = arr.find_child("PanelB2", true, false)
	if cond:
		print("cond_bg=", cond.get_theme_stylebox("panel").bg_color,
			" rect=", cond.get_global_rect())
	for i in arr.rank_tags.size():
		print("rank", i, " rect=", arr.rank_tags[i].get_global_rect())
	get_tree().quit()
