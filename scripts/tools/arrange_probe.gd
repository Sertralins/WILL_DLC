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
	print("white_bg color=", arr.white_bg.color, " modulate=", arr.white_bg.modulate,
		" dual_vis=", arr.dual_bg.visible, " single_vis=", arr.single_bg.visible)
	var pt2 := Vector2(500, 700)
	_print_covering(arr, pt2, "")
	var cond: PanelContainer = arr.find_child("PanelB2", true, false)
	if cond:
		print("cond_bg=", cond.get_theme_stylebox("panel").bg_color,
			" rect=", cond.get_global_rect())
		# 逐层检查块内部结构(定位遮住底色的可疑背景)
		for c in cond.get_children():
			print("  child: ", c.get_class(), " ", c.name)
			var rt: RichTextLabel = c.find_child("Text", true, false) as RichTextLabel
			if rt:
				var sb: StyleBox = rt.get_theme_stylebox("normal")
				if sb is StyleBoxFlat:
					print("    RichTextLabel normal stylebox bg=", (sb as StyleBoxFlat).bg_color)
				else:
					print("    RichTextLabel normal stylebox=", sb.get_class(), " (非 StyleBoxFlat)")
	for i in arr.rank_tags.size():
		print("rank", i, " rect=", arr.rank_tags[i].get_global_rect())
	# 定位覆盖 (1100,400)(R 栏空档)的节点链
	var pt := Vector2(1100, 400)
	var n: Node = arr
	while n != null:
		var found: Control = null
		for i in range(n.get_child_count() - 1, -1, -1):   # 逆序 = 最上层优先
			var c := n.get_child(i)
			if c is Control and (c as Control).get_global_rect().has_point(pt):
				found = c
				break
		if found == null:
			break
		print("cover@pt: ", found.get_class(), " ", String(found.name), " rect=", found.get_global_rect())
		if found is PanelContainer:
			print("  panel sb=", (found as PanelContainer).get_theme_stylebox("panel").bg_color)
		n = found
	# 打印右栏全部子节点(找出 115 灰的来源)
	var rc: VBoxContainer = arr.find_child("RightColumn", true, false)
	for c in rc.get_children():
		print("RCol child: ", c.get_class(), " ", String(c.name), " rect=", (c as Control).get_global_rect())
	var bs := arr.find_child("BoardScroll", true, false)
	var bss: StyleBox = bs.get_theme_stylebox("panel")
	print("BoardScroll panel sb=", bss.get_class())
	var b1: PanelContainer = arr.find_child("PanelB1", true, false)
	if b1:
		var s1: StyleBox = b1.get_theme_stylebox("panel")
		var extra := ""
		if s1 is StyleBoxFlat:
			extra = " bg=" + str((s1 as StyleBoxFlat).bg_color)
		print("PanelB1 sb=", s1.get_class(), extra)
	get_tree().quit()

func _print_covering(n: Node, pt: Vector2, indent: String) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree() and (c as Control).get_global_rect().has_point(pt):
			print(indent, c.get_class(), " ", String(c.name), " rect=", c.get_global_rect(),
				" mod=", (c as Control).modulate, " selfmod=", (c as Control).self_modulate)
			if c is PanelContainer:
				var sb: StyleBox = (c as PanelContainer).get_theme_stylebox("panel")
				if sb is StyleBoxFlat:
					print(indent, "  sb.bg=", (sb as StyleBoxFlat).bg_color)
			if c is ColorRect:
				print(indent, "  color=", (c as ColorRect).color)
			_print_covering(c, pt, indent + "  ")
