# map_visual_test.gd — 视觉自检: 两轮生长后展示大地图/剧情线/红线, 保持画面供截图
extends "res://scenes/map/map.gd"

func _ready() -> void:
	GameState.save_path = "user://save_visual.json"
	GameState.reset_save()
	super._ready()
	_run()

func _run() -> void:
	await get_tree().create_timer(0.5).timeout
	_on_mailbox()
	await get_tree().create_timer(0.6).timeout
	_on_envelope_click(_pending_envs[0])   # 点一封 → 0001 L/R 关联组自动先后生长(等提示播完)
	await get_tree().create_timer(8.0).timeout
	GameState.history["0001"] = ["BAD1"]   # 当前=BAD1(X), S1 未解锁(空心) → 结局方块各态
	_on_mailbox()
	await get_tree().create_timer(0.6).timeout
	_on_envelope_click(_pending_envs[0])   # 0002 链生长
	await get_tree().create_timer(4.5).timeout
	var view := get_viewport().get_visible_rect().size
	print("V: view=%s zoom=%s pan=%s" % [str(view), str(zoom), str(pan)])
	for key in nodes:
		print("V: node %s char=%s pos=%s" % [key, String(nodes[key].char), str(nodes[key].pos)])
	for cid in rail_head:
		var line: Node2D = rail_head[cid]
		print("V: rail %s x=%s top=%s bottom=%s" % [cid, str(line.a.x), str(line.a.y), str(line.b.y)])
	for i in rungs_layer.get_child_count():
		var line: Node2D = rungs_layer.get_child(i)
		print("V: rung %d a=%s b=%s" % [i, str(line.a), str(line.b)])
	# 以屏幕中心为锚缩小, 验证滚轮缩放路径(等缓动结束)
	_zoom_at(view * 0.5, 0.75)
	await get_tree().create_timer(0.4).timeout
	print("V: after zoom zoom=%s pan=%s" % [str(zoom), str(pan)])
	# 点块 → 细节卡浮在块下; 收尾前触发拿信提示(居中黑条)供截图
	_on_block_click("0001:L")
	await get_tree().create_timer(1.0).timeout
	print("V: cards=%d level=%s" % [open_cards.size(), open_level_id])
	await get_tree().create_timer(5.3).timeout
	# 收尾: 竖标条(竖起状态) + 开箱 + 信封(人物色虚线) + 居中黑条 + 独白字幕, 供截图
	mailbox_flag.position = Vector2(228.0, view.y - 345.0)
	mailbox_flag.visible = true
	_set_mailbox_frame(true)
	show_toast("收到新信件：《黑伞》")
	_spawn_envelopes([nodes["0001:L"]])
	show_monologue("（伊芙的独白：待填写）")
	await get_tree().create_timer(0.8).timeout
