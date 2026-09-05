# map_smoke_test.gd — headless 冒烟测试: 邮箱生长 / 剧情线(竖) / 同信齐平+红线(横) / 信息窗 / 解锁求值
# 运行: godot --headless --path . res://tools/map_smoke_test.tscn (headless 无帧率上限, 用外部 timeout 收尾)
extends "res://scripts/ui/map/map.gd"

func _ready() -> void:
	GameState.save_path = "user://save_smoke.json"
	GameState.reset_save()
	super._ready()
	_run()

func _run() -> void:
	await get_tree().process_frame
	print("T: nodes=%d new=%d grid=%d" % [nodes.size(), _collect_new().size(), grid_layer.get_child_count()])
	# 同信 L/R 水平齐平
	print("T: aligned_0001=%s" % str(is_equal_approx(float(nodes["0001:L"].pos.y), float(nodes["0001:R"].pos.y))))
	# 手动栅格位置(levels_index.json positions): 0001:L [0,5] / 0001:R [2,5] / 0002:L [-2,10]
	var manual_ok := is_equal_approx(float(nodes["0001:L"].pos.x), map_w * 0.5) \
		and is_equal_approx(float(nodes["0001:L"].pos.y), BASE_GAP + 5.0 * UNIT_Y) \
		and is_equal_approx(float(nodes["0001:R"].pos.x), map_w * 0.5 + 2.0 * GX) \
		and is_equal_approx(float(nodes["0001:R"].pos.y), BASE_GAP + 5.0 * UNIT_Y) \
		and is_equal_approx(float(nodes["0002:L"].pos.x), map_w * 0.5 - 2.0 * GX) \
		and is_equal_approx(float(nodes["0002:L"].pos.y), BASE_GAP + 10.0 * UNIT_Y) \
		and bool(nodes["0001:L"].get("manual", false)) \
		and bool(nodes["0002:L"].get("manual", false))
	print("T: manual_pos=%s" % str(manual_ok))
	print("T: previews_initial=%d" % previews_layer.get_child_count())   # 初始无待定虚线(0001 未 reveal)
	_on_mailbox()
	await get_tree().create_timer(0.4).timeout
	_on_envelope_click(_pending_envs[0])   # 点一封 → 关联组(L/R)自动先后生长
	await get_tree().create_timer(0.8).timeout
	print("T: toast_L=%s" % toast_label.text)   # 拿信蹦出的字 = 该行自己的故事标题
	print("T: mono_L=%s" % subtitle_label.text)   # 写信人独白字幕(每行不同)
	await get_tree().create_timer(3.4).timeout   # 等 L 的黑条+独白播完 → R 的线自己出来
	print("T: toast_R=%s" % toast_label.text)   # 关联的另一封自动播出
	print("T: mono_R=%s" % subtitle_label.text)
	print("T: pending_after_group=%d" % _pending.size())   # 关联组一次点完 = 0
	await get_tree().create_timer(3.2).timeout   # 等 R 播完 + 收尾重建
	print("T: revealed=%s rails=%d rungs=%d blocks=%d" % [
		str(revealed), rails_layer.get_child_count(), rungs_layer.get_child_count(), blocks_layer.get_child_count()])
	# 方块内容: 首次出现(无结局) → "!"
	print("T: block_label_before=%s" % String(block_ctls["0001:L"].get_child(2).text))
	# 剧情线顶端应锚在人物栏底边(世界 y=0); 未解锁角色 header 隐藏
	var anchor_ok := true
	for cid in rail_head:
		anchor_ok = anchor_ok and is_equal_approx(rail_head[cid].a.y, 0.0)
	print("T: headers_shown=%d of %d" % [header_ctls.size(), characters.size()])
	# header 两段式: 无结局 → ?图; 达成结局 → 无问号真实图
	var k0 := ""
	if header_ctls.has("yf"):
		k0 = String(header_ctls["yf"].texture.resource_path).get_file()
	print("T: header_yf_before_ending=%s" % k0)
	# 剧情线应是素材竖线管件(件 7)
	var rail_tex_ok := true
	for l in rails_layer.get_children():
		if l.sections.size() != 1 or String(l.sections[0].kind) != "v":
			rail_tex_ok = false
		else:
			var sp: Sprite2D = l.sections[0].seg.get_child(0)
			rail_tex_ok = rail_tex_ok and sp.texture.resource_path.get_file() == "connecting_lines_7.png"
	print("T: rail_solid_v=%s" % str(rail_tex_ok))
	# 关联线应为红色实线横线(件 9, 非虚线)
	var rung_ok := rungs_layer.get_child_count() > 0
	for l in rungs_layer.get_children():
		rung_ok = rung_ok and (not l.dashed) and l.line_color.is_equal_approx(RUNG_COLOR)
		if l.sections.size() != 1 or String(l.sections[0].kind) != "h":
			rung_ok = false
		else:
			var sp: Sprite2D = l.sections[0].seg.get_child(0)
			rung_ok = rung_ok and sp.texture.resource_path.get_file() == "connecting_lines_9.png"
	print("T: rail_anchor_ok=%s rung_red_solid=%s" % [str(anchor_ok), str(rung_ok)])
	# 通关 0001 (BAD1) → 0002 unlock 通过; 0002 只有 L 行 → 不加红线
	GameState.history["0001"] = ["BAD1"]
	_rebuild_previews()
	print("T: previews_bad1=%d" % previews_layer.get_child_count())   # BAD1 不满足 pendings(S1) → 0
	GameState.history["0001"] = ["S1"]
	_rebuild_previews()
	# S1 达成 → 0002:L 的待定虚线出现(dotted 素材)
	var preview_ok := previews_layer.get_child_count() == 1
	if preview_ok:
		var pl = previews_layer.get_child(0)
		preview_ok = pl.dashed
		if preview_ok and pl.sections.size() > 0:
			var sp: Sprite2D = pl.sections[0].seg.get_child(0)
			preview_ok = sp.texture.resource_path.get_file().begins_with("dotted_")
	print("T: preview_s1=%s" % str(preview_ok))
	GameState.history["0001"] = ["BAD1"]
	_on_mailbox()
	await get_tree().create_timer(0.4).timeout
	_on_envelope_click(_pending_envs[0])   # 0002 链: 0001:L 已长过跳过, 只长 0002
	await get_tree().create_timer(4.5).timeout
	print("T: revealed2=%s rails=%d rungs=%d blocks=%d" % [
		str(revealed), rails_layer.get_child_count(), rungs_layer.get_child_count(), blocks_layer.get_child_count()])
	print("T: rails_3=%s" % str(rails_layer.get_child_count() == 3))   # yf/qyy/jz 各一条主线/生长线
	print("T: previews_after_reveal=%d" % previews_layer.get_child_count())   # 0002 已 reveal → 虚线消失
	print("T: relations=%d" % _collect_relations().size())
	var k1 := ""
	if header_ctls.has("yf"):
		k1 = String(header_ctls["yf"].texture.resource_path).get_file()
	print("T: header_yf_after_ending=%s" % k1)
	# 信息窗: 画面滚动定位 + 弹窗
	_on_block_click("0001:L")
	await get_tree().create_timer(1.0).timeout
	print("T: cards=%d level=%s" % [open_cards.size(), open_level_id])
	# 再点关联块: 不关闭、不淡化退出
	_on_block_click("0001:R")
	await get_tree().create_timer(0.2).timeout
	print("T: cards_after_rel=%d level=%s" % [open_cards.size(), open_level_id])
	_close_popup()
	# 第一次打开(无结局)的细节卡: 只有标题栏, 无结局横带(高度 100 = 6*2+88)
	_on_block_click("0002:L")
	await get_tree().create_timer(1.2).timeout
	print("T: card_0002_h=%d" % int(open_cards[0].size.y))
	_close_popup()
	# 达成 S1 → 关联集合不变(红线只由同信关系决定, 与评级无关)
	GameState.history["0001"] = ["S1"]
	_rebuild_rungs()
	print("T: rungs_after_S1=%d" % rungs_layer.get_child_count())
	# 跳转读信(放最后: 切场景会释放本节点)
	print("T: SMOKE PASS, goto letter")
	GameState.current_level_id = "0001"
	GameState.current_row = "L"
	GameFlow.goto("letter")
