# map.gd — 选关界面: 大地图 + 缩放/拖拽相机
#
# 布局: 地图(网格底色区)做得很大, 预留未来新增人物列;
#       顶部人物栏固定在屏幕上缘, 随相机横向平移/缩放对齐剧情线;
#       没有信件(未解锁)的角色 header 隐藏, 出现第一封信才显示;
#       每个已显示角色一条竖直剧情线(角色色), 关卡块挂在本角色线上;
#       同一封信的 L/R 两行水平齐平, 中间用横着的红色实线相连。
# 机制(《选关界面-关卡地图与生长逻辑》文档): 点信箱 → BFS 找新解锁节点 →
#       三拍子演出(线生长 → 块弹出, 逐节点串行); 点块 → 画面滚动定位 →
#       块下浮现细节卡(关卡名 + 结局方块, 仿原版, 仅展示不进游戏);
#       拿信提示居屏幕正中, 文字后一横条黑色矩形; 信封进开箱内腔与提示同生共灭。
# 相机: 鼠标滚轮以指针为锚缩放, 左键拖拽全向平移, 范围钳制在大地图内。
# UI 全部代码构建, 场景文件只有根节点。
extends Node2D

# —— 布局常量(1920x1080 基准) ——
const HEADER_W := 444.0
const HEADER_H := 132.0
const UNIT_Y := 80.0             # 距离坐标 1 单位 = 80px(生长轴, 纵向)
const BASE_GAP := 60.0           # 头像底边到首格网格线的基准留白
const BLOCK := 70.0              # 关卡块尺寸(外框与填充齐平)
const LINE_W := 10.0             # 连线线宽(原版 10px)
const BG_COLOR := Color("f7f6ee")
const RUNG_COLOR := Color("d64545")  # 剧情关联横线(红色实线)
const MAP_COLS := 8              # 大地图预留人物列数(>= 当前角色数, 未来可加)
const MAP_ROWS := 60             # 大地图纵向刻度数
const ZOOM_MIN := 0.45
const ZOOM_MAX := 1.5

# 块下细节卡(仿原版 A.png): 深棕圆角框, 上白底关卡名, 下灰底结局方块
const CARD_W := 300.0
const CARD_TITLE_H := 88.0
const CARD_BAND_H := 58.0
const CARD_BORDER := 6.0

var font: Font

var world: Node2D                # 栅格/连线/块层(随相机缩放平移)
var surface: ColorRect           # 大地图白底表面(选中淡化蒙版用)
var grid_layer: Node2D
var rails_layer: Node2D          # 角色竖直剧情线层
var rungs_layer: Node2D          # 红色关联横线层
var blocks_layer: Node2D
var fx_layer: Node2D             # 信封等演出层(屏幕坐标)
var header_row: Control
var mailbox_btn: TextureButton
var mailbox_flag: TextureRect    # "有新信件" 标条
var ui_layer: CanvasLayer
var toast_bar: ColorRect           # 拿信提示的黑底横条
var toast_label: Label
var _toast_tw: Tween
var subtitle_label: Label          # 写信人独白字幕(屏幕下方)
var _subtitle_tw: Tween

var characters := {}             # 角色id -> {name, color, col}
var nodes := {}                  # "关卡id:行id" -> {key, level_id, row_id, char, pos, parent, pendings, unlock}
var revealed: Array = []         # 已生长节点 key
var rail_head := {}              # 角色id -> 首段线(顶端随相机贴合头像底边)
var rail_last_y := {}            # 角色id -> 剧情线当前底端(世界 y)
var block_ctls := {}             # key -> Control(块)
var header_ctls := {}            # 角色id -> TextureRect(已显示的人物图)
var header_kind := {}            # 角色id -> 当前使用的头像路径(两段式切换判断)

var zoom := 1.0
var pan := Vector2.ZERO          # 屏幕 = 世界*zoom + pan
var _zoom_tw: Tween
var _dim_tw: Tween               # 选中蒙版: 进入/退出淡化共用的一个动画
var _flag_tw: Tween              # 小旗子竖起来/缩回的动画
var _pending: Array = []         # 待点击的信封对应节点(点信才生长)
var _pending_envs: Array = []    # 待点击的信封 Control
var map_w := 0.0                 # 大地图宽(世界单位)
var map_h := 0.0                 # 大地图高(世界单位)
var dragging := false
var busy := false                # 生长演出中
var open_cards: Array = []      # 当前选中关卡的卡(每个关联块一张)
var open_level_id := ""
var _click_gen := 0             # 点块代次(滚动竞态防护)

func _ready() -> void:
	font = load("res://assets/fonts/HYRunYuan-55W.ttf")
	_build_static_ui()
	GameState.load_game()   # 按存档还原(判定链文档 §4.4: revealed 节点直接呈现)
	_load_data()
	revealed = GameState.revealed_nodes.duplicate()
	for key in revealed.duplicate():
		if nodes.has(key):
			_spawn_block(nodes[key], false)
		else:
			revealed.erase(key)
	_rebuild_rails()
	_rebuild_rungs()
	_build_headers()
	_update_mailbox_flag()
	# 初始相机: 地图中心列(首位角色)水平居中, 地图顶(头像底)贴上缘
	var view := get_viewport().get_visible_rect().size
	pan.x = view.x * 0.5 - map_w * 0.5 * zoom
	pan.y = HEADER_H * zoom
	_clamp_cam()
	_apply_cam()

# —— 构建 ——

func _build_static_ui() -> void:
	var view := get_viewport().get_visible_rect().size
	# 背景层(屏幕固定)
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(bg)

	# 世界层(随相机): 栅格 → 剧情线 → 红线 → 块
	world = Node2D.new()
	add_child(world)
	grid_layer = Node2D.new()
	grid_layer.visible = false   # 栅格线隐藏(保留构建, 需要时改回 true)
	world.add_child(grid_layer)
	rails_layer = Node2D.new()
	world.add_child(rails_layer)
	rungs_layer = Node2D.new()
	rungs_layer.visible = false   # 红线平时不显示, 选中相关关卡时才亮
	world.add_child(rungs_layer)
	blocks_layer = Node2D.new()
	world.add_child(blocks_layer)

	# 人物栏也嵌进大地图(随相机整体平移缩放)
	header_row = Control.new()
	world.add_child(header_row)

	# 信箱: 左下角(右移 25); 闭箱 236x289, 开箱 291x289(门向左甩, 右缘对齐, 见 _set_mailbox_frame)
	# "新信件"竖标条在信箱图层后面: 有信时从右上角屋顶后竖起来, 取完缩回消失
	mailbox_flag = TextureRect.new()
	mailbox_flag.texture = load("res://assets/sceneUI/mailbox/mailbox_new.png")
	mailbox_flag.position = Vector2(228.0, view.y - 255.0)
	mailbox_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mailbox_flag.visible = false
	add_child(mailbox_flag)
	mailbox_btn = TextureButton.new()
	mailbox_btn.texture_normal = load("res://assets/sceneUI/mailbox/mailbox_closed.png")
	mailbox_btn.position = Vector2(25, view.y - 289)
	mailbox_btn.size = Vector2(236, 289)
	mailbox_btn.pressed.connect(_on_mailbox)
	add_child(mailbox_btn)

	fx_layer = Node2D.new()
	add_child(fx_layer)

	# UI 层: Toast(顶部提示)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	# 拿信提示: 屏幕正中央, 文字后一横条黑色矩形(横贯全屏, 60% 不透明)
	toast_bar = ColorRect.new()
	toast_bar.color = Color(0.06, 0.06, 0.06, 0.6)
	toast_bar.modulate.a = 0.0
	toast_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(toast_bar)
	toast_label = Label.new()
	toast_label.add_theme_font_override("font", font)
	toast_label.add_theme_font_size_override("font_size", 40)
	toast_label.add_theme_color_override("font_color", Color.WHITE)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.modulate.a = 0.0
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(toast_label)

	# 写信人独白字幕: 屏幕下方居中, 取信时突然出现, 3 秒后缓缓消失
	subtitle_label = Label.new()
	subtitle_label.add_theme_font_override("font", font)
	subtitle_label.add_theme_font_size_override("font_size", 40)
	subtitle_label.add_theme_color_override("font_color", Color.WHITE)
	subtitle_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	subtitle_label.add_theme_constant_override("outline_size", 6)
	subtitle_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	subtitle_label.position = Vector2(-800, -170)
	subtitle_label.size = Vector2(1600, 60)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.modulate.a = 0.0
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(subtitle_label)

func _load_data() -> void:
	var chars_data := LevelData.load_characters()
	var i := 0
	for cid in chars_data.keys():
		var info: Dictionary = chars_data[cid]
		# header 从中间向两侧拓展: #0 居中, 之后右/左/右…交替外扩
		var slot := 0 if i == 0 else ((i + 1) / 2 if i % 2 == 1 else -i / 2)
		characters[String(cid)] = {
			"name": String(info.get("name", String(cid))),
			"color": Color(String(info.get("color", "#888888"))),
			"col": slot,
		}
		i += 1
	var cols := maxi(MAP_COLS, characters.size() + 4)
	if cols % 2 == 1:
		cols += 1   # 偶数列保证中心列落在格子线上
	map_w = cols * HEADER_W
	map_h = BASE_GAP + MAP_ROWS * UNIT_Y
	# 巨大的白底图: 整张地图的表面, 所有 UI 嵌入其上(不拦截鼠标, 拖拽/缩放穿透)
	surface = ColorRect.new()
	surface.color = BG_COLOR
	surface.position = Vector2(0, -HEADER_H)
	surface.size = Vector2(map_w, map_h + HEADER_H)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(surface)
	world.move_child(surface, 0)

	var index := LevelData.load_index()
	# 逐关建行; 纵向坐标需父节点先就位, 按"父先子后"多轮放置
	# (position = "泳道,距离": 距离 = 相对父节点向下的生长增量; 节点横轴 = 本角色剧情线)
	var raw_rows: Array = []
	for lid in index.get("levels", []):
		var lv := LevelData.load_level(String(lid))
		for row in lv.rows:
			raw_rows.append({
				"key": lv.level_id + ":" + row.id,
				"level_id": lv.level_id,
				"title": lv.title,
				"row_title": row.title if row.title != "" else lv.title,   # 每行独立标题, 缺省关卡名
				"monologue": row.monologue,    # 写信人独白(取信时屏幕下方字幕)
				"subtitle": lv.subtitle,
				"unlock": lv.unlock,
				"row_id": row.id,
				"char": row.character,
				"position": row.position,
				"parent": row.previous,
				"pendings": row.pendings,
			})
	var placed := {"start": 0.0}   # key -> 累计深度(距离单位)
	var progress := true
	while progress:
		progress = false
		for r in raw_rows:
			var key := String(r.key)
			if nodes.has(key) or not placed.has(String(r.parent)):
				continue
			var parts := String(r.position).split(",")
			var dist := int(parts[1]) if parts.size() > 1 else 3
			var depth: float = placed[String(r.parent)] + dist
			placed[key] = depth
			var cx := _rail_x(String(r.char))
			r["pos"] = Vector2(cx, BASE_GAP + depth * UNIT_Y)
			nodes[key] = r
			progress = true
	for r in raw_rows:
		if not nodes.has(String(r.key)):
			push_warning("map: 节点无法放置(父节点缺失?): %s" % r.key)
	_align_level_rows()
	# 大地图栅格: 横向铺满预留列, 纵向铺满预留行; 列界竖线 + 刻度横线
	var ys: Array = []
	for k in range(0, MAP_ROWS + 1):
		ys.append(BASE_GAP + k * UNIT_Y)
	var xs: Array = []
	for k in range(0, cols + 1):
		xs.append(k * HEADER_W)
	var grid: Node2D = load("res://scenes/map/map_grid.gd").new()
	grid.setup(xs, ys, map_h)
	grid_layer.add_child(grid)

# 同一封信的两行(L/R)水平齐平: 浅者下移到较深者的深度, 其子树整体随移
func _align_level_rows() -> void:
	var by_level := {}
	for key in nodes:
		var lid := String(nodes[key].level_id)
		if not by_level.has(lid):
			by_level[lid] = []
		by_level[lid].append(String(key))
	for lid in by_level:
		var target := 0.0
		for key in by_level[lid]:
			target = maxf(target, float(nodes[key].pos.y))
		for key in by_level[lid]:
			var delta := target - float(nodes[key].pos.y)
			if delta > 0.5:
				_shift_subtree(String(key), delta)

func _shift_subtree(key: String, delta: float) -> void:
	nodes[key].pos.y += delta
	for k2 in nodes:
		if String(nodes[k2].parent) == key:
			_shift_subtree(String(k2), delta)

func _world_ctx() -> Dictionary:
	return {
		"merged": [],
		"sides": {},
		"triggered": {},
		"world_state": {
			"history": GameState.history,
			"sranks": GameState.sranks,
			"read": GameState.read_rows,
			"stories": [],
			"achievements": {},
		},
	}

func _char(cid: String) -> Dictionary:
	return characters.get(cid, {})

func _char_color(cid: String) -> Color:
	return _char(cid).get("color", Color.GRAY)

func _rail_x(cid: String) -> float:
	return map_w * 0.5 + float(_char(cid).get("col", 0)) * HEADER_W

# 节点的已达成评级(关卡级结局): history[level_id]
func ranks_of(key: String) -> Array:
	if not nodes.has(key):
		return []
	return GameState.history.get(String(nodes[key].level_id), [])

# —— 人物栏(固定顶行): 没有信件=隐藏; 出现第一封信才显示整张 PNG ——

# 角色解锁 = 有任意可生长(解锁表达式通过)的节点
func _char_unlocked(cid: String) -> bool:
	for key in nodes:
		var nd: Dictionary = nodes[key]
		if String(nd.char) == cid and _is_available(nd):
			return true
	return false

# 角色是否已达成过任一结局(决定 header 两段式: ?图 → 真实图)
func _char_has_ending(cid: String) -> bool:
	for key in nodes:
		var nd: Dictionary = nodes[key]
		if String(nd.char) == cid and ranks_of(String(key)).size() > 0:
			return true
	return false

# 人物栏两段式解锁(无动画, 直接显示):
#   - 角色有任一关卡解锁(解锁表达式通过) → "?"头像(header_locked);
#   - 达成过任一结局后 → 换无问号的真实头像(header)
func _build_headers() -> void:
	for c in header_row.get_children():
		c.free()
	header_ctls.clear()
	# 一长横条(地图顶部整条), header 嵌入其中
	var bar := ColorRect.new()
	bar.color = Color(0.09, 0.09, 0.1)
	bar.position = Vector2(0, -HEADER_H)
	bar.size = Vector2(map_w, HEADER_H)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(bar)
	for cid in characters:
		if not _char_unlocked(String(cid)):
			continue
		var info: Dictionary = characters[String(cid)]
		var path := String(info.get("header", "res://assets/header/header_%s_2.png" % cid))
		if not _char_has_ending(String(cid)):
			path = String(info.get("header_locked", "res://assets/header/header_%s_0.png" % cid))
		var tex := TextureRect.new()
		tex.texture = load(path)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header_row.add_child(tex)
		header_ctls[cid] = tex
		header_kind[String(cid)] = path
	_layout_headers()

# header 嵌在地图里的固定世界位置(各自人物列)
func _layout_headers() -> void:
	for cid in header_ctls:
		var tex: TextureRect = header_ctls[cid]
		tex.position = Vector2(_rail_x(String(cid)) - HEADER_W * 0.5, -HEADER_H)
		tex.size = Vector2(HEADER_W, HEADER_H)

# —— 块 ——

# 关卡块: 角色色圆角填充 + 九宫格边框(与填充齐平) + 通关星; 整块可点
func _spawn_block(nd: Dictionary, animate: bool) -> void:
	var pos: Vector2 = nd.pos
	var ctl := Control.new()
	ctl.position = pos - Vector2(BLOCK, BLOCK) * 0.5
	ctl.size = Vector2(BLOCK, BLOCK)
	ctl.pivot_offset = Vector2(BLOCK, BLOCK) * 0.5

	var fill := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = _char_color(String(nd.char))
	sb.set_corner_radius_all(10)
	fill.add_theme_stylebox_override("panel", sb)
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctl.add_child(fill)

	var border := NinePatchRect.new()
	border.texture = load("res://assets/sceneUI/levelblockv7_border.png")
	border.patch_margin_left = 16
	border.patch_margin_right = 16
	border.patch_margin_top = 16
	border.patch_margin_bottom = 16
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctl.add_child(border)

	var achieved: Array = ranks_of(String(nd.key))
	var lv := LevelData.load_level(String(nd.level_id))
	# 块内文字: 首次出现(无结局) → "!"; 有结局 → 当前选择结局的评级首字母
	var rank_txt := "!"
	if achieved.size() > 0:
		var cur := String(GameState.row(String(nd.key)).get("current", ""))
		if cur == "":
			cur = String(achieved[achieved.size() - 1])
		var e: Dictionary = lv.endings.get(cur, {})
		var rk := String(e.get("rank", cur))
		rank_txt = "X" if rk.to_lower() == "bad" else rk.substr(0, 1).to_upper()
	var s_l := Label.new()
	s_l.text = rank_txt
	s_l.add_theme_font_override("font", font)
	s_l.add_theme_font_size_override("font_size", 40)
	s_l.add_theme_color_override("font_color", Color.WHITE)
	s_l.set_anchors_preset(Control.PRESET_FULL_RECT)
	s_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	s_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctl.add_child(s_l)

	var star := TextureRect.new()
	star.texture = load("res://assets/sceneUI/star.png")
	star.size = Vector2(40, 40)
	star.position = Vector2(BLOCK - 22, -24)
	star.visible = achieved.size() >= lv.endings.size()   # 结局全部解锁 → 右上角星号
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctl.add_child(star)

	var key := String(nd.key)
	ctl.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			_on_block_click(key)
	)
	blocks_layer.add_child(ctl)
	block_ctls[key] = ctl

	if animate:
		_pop_block(ctl, 0.0)

# 块弹出: 从 0 弹性放大(文档 §4.4/§5: TRANS_BACK/EASE_OUT 0.35s)
func _pop_block(ctl: Control, delay: float) -> void:
	ctl.scale = Vector2(0.01, 0.01)
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(ctl, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# —— 连线: 角色竖直剧情线 + 红色关联横线 ——

func _make_line(from: Vector2, to: Vector2, color: Color, grow_time := 0.0, dashed := false) -> Node2D:
	var line: Node2D = load("res://scenes/map/map_line.gd").new()
	line.width = LINE_W
	line.setup(from, to, color, dashed, grow_time)
	return line

# 剧情线(每角色一条, 从头像底边到最深块): 读档重建用
func _rebuild_rails() -> void:
	for child in rails_layer.get_children():
		child.free()
	rail_head.clear()
	rail_last_y.clear()
	var by_char := {}
	for key in revealed:
		var nd: Dictionary = nodes[key]
		var cid := String(nd.char)
		if not by_char.has(cid):
			by_char[cid] = []
		by_char[cid].append(nd)
	for cid in by_char:
		var deepest := 0.0
		for nd in by_char[cid]:
			deepest = maxf(deepest, float(nd.pos.y) - BLOCK * 0.5)   # 线停在最深块上缘
		var x := _rail_x(String(cid))
		var line := _make_line(Vector2(x, 0.0), Vector2(x, deepest), _char_color(String(cid)))
		rails_layer.add_child(line)
		rail_head[cid] = line
		rail_last_y[cid] = deepest

# 剧情关联 = 同一封信的不同角色行(交换纸条的双方, 水平齐平);
# 两端都已生长时, 用横着的红色实线在两块中间相连
func _collect_relations() -> Array:
	var seen := {}
	var out: Array = []
	var by_level := {}
	for key in revealed:
		var lid := String(nodes[key].level_id)
		if not by_level.has(lid):
			by_level[lid] = []
		by_level[lid].append(String(key))
	for lid in by_level:
		var ks: Array = by_level[lid]
		for i in ks.size():
			for j in range(i + 1, ks.size()):
				var ak: String = ks[i]
				var bk: String = ks[j]
				if String(nodes[ak].char) == String(nodes[bk].char):
					continue
				var k := ak + "|" + bk if ak < bk else bk + "|" + ak
				if seen.has(k):
					continue
				seen[k] = true
				out.append({"a": ak, "b": bk})
	return out

func _rebuild_rungs() -> void:
	for child in rungs_layer.get_children():
		child.free()
	for rel in _collect_relations():
		var na: Dictionary = nodes[rel.a]
		var nb: Dictionary = nodes[rel.b]
		# 同信两块水平齐平: 红线从左块右缘连到右块左缘
		var y: float = float(na.pos.y)
		var left: Dictionary = na if float(na.pos.x) < float(nb.pos.x) else nb
		var right: Dictionary = nb if left == na else na
		var rung := _make_line(
			Vector2(float(left.pos.x) + BLOCK * 0.5, y),
			Vector2(float(right.pos.x) - BLOCK * 0.5, y), RUNG_COLOR)
		rung.set_meta("rel", {"a": String(rel.a), "b": String(rel.b)})
		rungs_layer.add_child(rung)

# —— 相机: 滚轮缩放(指针为锚) + 左键拖拽全向平移, 钳制在大地图内 ——

func _clamp_cam() -> void:
	var view := get_viewport().get_visible_rect().size
	var mw := map_w * zoom
	if mw >= view.x:
		pan.x = clampf(pan.x, view.x - mw, 0.0)
	else:
		pan.x = (view.x - mw) * 0.5
	var top := HEADER_H * zoom              # 未滚动时: 地图顶(横条顶)贴视口顶
	var bottom := view.y - map_h * zoom     # 滚到底: 地图底贴视口底
	pan.y = top if bottom > top else clampf(pan.y, bottom, top)

func _apply_cam() -> void:
	world.scale = Vector2(zoom, zoom)
	world.position = pan

func _set_cam(v: Vector2) -> void:
	pan = v
	_apply_cam()

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		dragging = ev.pressed
		if ev.pressed:
			_close_popup()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_at(ev.position, 1.1)
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_at(ev.position, 1.0 / 1.1)
	elif ev is InputEventMouseMotion and dragging and ev.button_mask & MOUSE_BUTTON_MASK_LEFT:
		pan += ev.relative
		_clamp_cam()
		_apply_cam()

# 以屏幕点 m 为锚平滑缩放: m 下的世界点保持不动, 0.12s 缓动到位
func _zoom_at(m: Vector2, factor: float) -> void:
	var z0 := zoom
	var z1 := clampf(z0 * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(z1, z0):
		return
	var w := (m - pan) / z0
	if _zoom_tw != null and _zoom_tw.is_valid():
		_zoom_tw.kill()
	_zoom_tw = create_tween()
	_zoom_tw.tween_method(func(z: float):
		zoom = z
		pan = m - w * z
		_clamp_cam()
		_apply_cam()
	, z0, z1, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# —— 信箱: 新信件生长(文档 §4.6 + §4.5) ——

# 新信件 = 已解锁(可用) ∧ 未读(判定链文档 §4.1/§4.3: "新信件"的唯一定义)
func _collect_new() -> Array:
	var out: Array = []
	for key in nodes:
		var nd: Dictionary = nodes[key]
		if _is_available(nd) and not GameState.row_read(String(key)):
			out.append(nd)
	return out

# 节点可生长 = 关卡 unlock 表达式通过(条件引擎) 且 实线父节点已玩过(文档 §4.2)
func _is_available(nd: Dictionary) -> bool:
	var unlock := String(nd.unlock).strip_edges()
	if unlock != "" and not ConditionEngine.evaluate(unlock, _world_ctx()):
		return false
	var parent := String(nd.parent)
	if parent != "start" and parent != "" and ranks_of(parent).is_empty():
		return false
	return true

func _set_mailbox_frame(opened: bool) -> void:
	var view_y := get_viewport().get_visible_rect().size.y
	if opened:
		mailbox_btn.texture_normal = load("res://assets/sceneUI/mailbox/mailbox_open.png")
		mailbox_btn.size = Vector2(291, 289)
		mailbox_btn.position = Vector2(-30.0, view_y - 289.0)   # 门向左甩 55, 箱体不动
	else:
		mailbox_btn.texture_normal = load("res://assets/sceneUI/mailbox/mailbox_closed.png")
		mailbox_btn.size = Vector2(236, 289)
		mailbox_btn.position = Vector2(25.0, view_y - 289.0)

# 新信件标条: 有信时从信箱右上角屋顶后"竖起来", 信被取完后缩回消失
func _update_mailbox_flag() -> void:
	var has := _collect_new().size() > 0
	if has == mailbox_flag.visible:
		return
	var view_y := get_viewport().get_visible_rect().size.y
	var up_y := view_y - 345.0      # 竖起来的位置(露出屋顶约 56px)
	var down_y := view_y - 255.0    # 完全藏进屋顶后
	mailbox_flag.visible = true
	mailbox_flag.position.x = 228.0
	if _flag_tw != null and _flag_tw.is_valid():
		_flag_tw.kill()
	_flag_tw = create_tween()
	if has:
		mailbox_flag.position.y = down_y
		_flag_tw.tween_property(mailbox_flag, "position:y", up_y, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		mailbox_flag.position.y = up_y
		_flag_tw.tween_property(mailbox_flag, "position:y", down_y, 0.25)
		_flag_tw.tween_callback(func(): mailbox_flag.visible = false)

func _on_mailbox() -> void:
	if busy or not _pending.is_empty():
		return
	var grow := _collect_new()
	_set_mailbox_frame(true)
	if grow.is_empty():
		show_toast("没有新信件")
		var tw := create_tween()
		tw.tween_interval(0.6)
		tw.tween_callback(func(): _set_mailbox_frame(false))
		return
	_close_popup()
	_spawn_envelopes(grow)   # 信箱保持开启, 等玩家点信(新方块延伸时逐次弹标题条)

# 点信封 → 相关联的信(同一封信的 L/R, 红线相连)自动一起生长, 无需逐封点;
# 每封沿 parent 边回溯到链根, 链上未生长节点逐个演出(判定链文档 §4.3 第3/4步)
func _on_envelope_click(holder: Control) -> void:
	if busy:
		return
	var i := _pending_envs.find(holder)
	if i < 0:
		return
	var lid := String(_pending[i].level_id)
	# 收集关联组(同关卡的待点信), 点一封整组一起演出
	var group: Array = []
	var remove_idx: Array = []
	for j in _pending.size():
		if String(_pending[j].level_id) == lid:
			group.append(_pending[j])
			remove_idx.append(j)
	for j in range(remove_idx.size() - 1, -1, -1):
		var idx: int = remove_idx[j]
		var h: Control = _pending_envs[idx]
		var tw0: Tween = h.get_meta("tw", null)
		if tw0 != null and tw0.is_valid():
			tw0.kill()
		var tw := create_tween()
		tw.tween_property(h, "modulate:a", 0.0, 0.2)
		tw.tween_callback(h.queue_free)
		_pending.remove_at(idx)
		_pending_envs.remove_at(idx)
	busy = true
	# 组内每封回溯链并逐个演出: 一条线先出来(线生长→块弹出→黑条+独白),
	# 等黑条+独白播完, 另一条线才出来(已长过的跳过, 不等待)
	for gnd in group:
		var chain: Array = []
		var cur_key := String(gnd.key)
		var guard := 0
		while cur_key != "" and nodes.has(cur_key) and guard < 64:
			chain.push_front(cur_key)
			var p := String(nodes[cur_key].parent)
			cur_key = p if p != "start" else ""
			guard += 1
		for ck in chain:
			var cnd: Dictionary = nodes[ck]
			if GameState.row_revealed(String(ck)):
				continue
			_grow_anim(cnd, 0.0)
			GameState.set_row_revealed(String(ck))
			# 块弹出(0.45s)后黑条+独白播 2.7s 结束 → 下一条线再出来
			await get_tree().create_timer(3.2).timeout
	# 组内每封都标读 + 存档(第6步)
	for gnd in group:
		GameState.set_row_read(String(gnd.key))
	await get_tree().create_timer(0.6).timeout
	_rebuild_rungs()
	_build_headers()
	_update_mailbox_flag()
	busy = false
	# 没有信了就关门; 还有就保持开门等玩家点下一封
	if _pending.is_empty():
		_set_mailbox_frame(false)

# 单节点生长: 线延伸 0.5s → 块弹出(delay 为串行节拍)
func _grow_anim(nd: Dictionary, delay: float) -> void:
	var key := String(nd.key)
	revealed.append(key)
	var cid := String(nd.char)
	var x := _rail_x(cid)
	var new_bottom: float = float(nd.pos.y) - BLOCK * 0.5   # 线停在块上缘, 不深入块内
	# 1) 剧情线先生长: 首次从头像底边引出, 否则从现有底端延伸(文档: 0.5s/段)
	var from_y: float = rail_last_y.get(cid, 0.0)
	var line := _make_line(Vector2(x, from_y), Vector2(x, maxf(from_y, new_bottom)), _char_color(cid), 0.5)
	rails_layer.add_child(line)
	if not rail_head.has(cid):
		rail_head[cid] = line
	rail_last_y[cid] = maxf(from_y, new_bottom)
	# 2) 线到后块弹出
	_spawn_block(nd, false)
	_pop_block(block_ctls[key], delay + 0.45)
	# 块弹出的同时: 黑矩形条+标题弹出一次, 并弹出写信人独白字幕(按节拍延迟, 不互相覆盖)
	var tw := create_tween()
	tw.tween_interval(delay + 0.45)
	tw.tween_callback(func():
		show_toast("收到新信件：《%s》" % String(nd.get("row_title", String(nd.get("title", "")))))
		show_monologue(String(nd.get("monologue", "")))
	)

# 新信件演出: 信封放进开箱内腔向右伸出箱外(不上浮), 只有虚线染成对应关卡人物色
# (与小方块/生长线一致); 信封淡入后常驻, 等玩家点击; 点击后关联信一起生长
func _spawn_envelopes(grow: Array) -> void:
	_pending = grow.duplicate()
	_pending_envs.clear()
	var n := grow.size()
	for i in n:
		var nd: Dictionary = grow[i]
		var base := mailbox_btn.position + Vector2(92.0 + (i - (n - 1) / 2.0) * 26.0, 168.0)
		var holder := Control.new()
		holder.position = base
		holder.size = Vector2(120, 90)
		holder.modulate.a = 0.0
		fx_layer.add_child(holder)
		var env := TextureRect.new()
		env.texture = load("res://assets/sceneUI/mailbox/mailbox_mail_%d.png" % (i % 6))
		env.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(env)
		var line := TextureRect.new()
		line.texture = load("res://assets/sceneUI/mailbox/mailbox_mail_%d_line.png" % (i % 6))
		line.position = Vector2(8.0, 5.0)
		line.modulate = _char_color(String(nd.char))
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(line)
		holder.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				get_viewport().set_input_as_handled()
				_on_envelope_click(holder)
		)
		var tw := create_tween()
		tw.tween_property(holder, "modulate:a", 1.0, 0.2)
		holder.set_meta("tw", tw)
		_pending_envs.append(holder)

# —— 细节卡(仿原版 A.png): 块下浮现 关卡名+结局方块; 再点块/点卡 进读信 ——

func _on_block_click(key: String) -> void:
	if busy:
		return
	var lid := String(nodes[key].level_id)
	if open_level_id == lid:
		return   # 已选中该关(含关联块): 再点关联块不关闭、不淡化退出
	_close_popup()
	var nd: Dictionary = nodes[key]
	var pos: Vector2 = nd.pos
	# 立即进入选中态(淡化其余内容 + 亮相关红线), 不等滚动结束
	var sel: Array = []
	for k2 in revealed:
		if String(nodes[k2].level_id) == lid:
			sel.append(String(k2))
	_set_dim(true, sel)
	# 画面平滑滚动, 把块定位到视口上部中央(卡挂在块下方)
	var view := get_viewport().get_visible_rect().size
	var target := _clamped(Vector2(
		view.x * 0.5 - pos.x * zoom,
		HEADER_H * zoom + (view.y - HEADER_H * zoom) * 0.42 - pos.y * zoom))
	_click_gen += 1
	var gen := _click_gen
	var tw := create_tween()
	tw.tween_method(_set_cam, pan, target, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished
	if gen == _click_gen:
		_open_cards(lid)

func _clamped(v: Vector2) -> Vector2:
	var saved := pan
	pan = v
	_clamp_cam()
	var out := pan
	pan = saved
	return out

# 选中一关: 该关所有已生长行(关联块)下面各浮一张卡
func _open_cards(lid: String) -> void:
	open_level_id = lid
	for k2 in revealed:
		if String(nodes[k2].level_id) == lid:
			_create_card(String(k2))

func _create_card(key: String) -> void:
	var nd: Dictionary = nodes[key]
	var lv := LevelData.load_level(String(nd.level_id))
	var achieved: Array = GameState.history.get(String(nd.level_id), [])
	var endings: Dictionary = lv.endings
	# 第一次打开(尚无结局): 只显示标题栏, 底部结局横带隐藏
	var show_band: bool = achieved.size() > 0
	var card_h := CARD_BORDER * 2.0 + CARD_TITLE_H + (CARD_BAND_H if show_band else 0.0)

	# 卡挂在块正下方(世界坐标, 随相机缩放平移)
	var card := Control.new()
	card.position = Vector2(float(nd.pos.x) - CARD_W * 0.5, float(nd.pos.y) + BLOCK * 0.5 + 16.0)
	card.size = Vector2(CARD_W, card_h)
	card.pivot_offset = card.size * 0.5

	var frame := Panel.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color("4a3b2c")
	fsb.set_corner_radius_all(12)
	frame.add_theme_stylebox_override("panel", fsb)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(frame)

	var paper := ColorRect.new()
	paper.color = Color("fbfaf4")
	paper.position = Vector2(CARD_BORDER, CARD_BORDER)
	paper.size = Vector2(CARD_W - CARD_BORDER * 2.0, CARD_TITLE_H)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(paper)

	# 关卡名(每行独立标题: 横向相连的多个块各显示各的故事名)
	var title := Label.new()
	title.text = String(nd.get("row_title", lv.title))
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color("3f3a33"))
	title.position = paper.position
	title.size = paper.size
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(title)

	if show_band:
		# 灰底横带 + 结局方块(黄色实心=当前选择, 实心=已解锁, 空心=未解锁, 灰色=条件已不可用;
		# 评级字母显示在地图关卡块上, 不在这里)
		var band := ColorRect.new()
		band.color = Color("c9c7c2")
		band.position = Vector2(CARD_BORDER, CARD_BORDER + CARD_TITLE_H)
		band.size = Vector2(CARD_W - CARD_BORDER * 2.0, CARD_BAND_H)
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(band)
		var cur := String(GameState.row(String(nd.key)).get("current", ""))
		if cur == "" and achieved.size() > 0:
			cur = String(achieved[achieved.size() - 1])
		var unavailable := _unavailable_endings(lv, achieved)
		var total := endings.size()
		var sq := 36.0
		var gap := 14.0
		var x0 := (CARD_W - (total * sq + (total - 1) * gap)) * 0.5
		var i := 0
		for eid in endings:
			var e: Dictionary = endings[eid]
			var is_achieved: bool = achieved.has(String(eid))
			var is_current: bool = is_achieved and String(eid) == cur
			var is_gray: bool = not is_achieved and unavailable.has(String(eid))
			var sb := StyleBoxFlat.new()
			if is_current:
				sb.bg_color = Color("ffd83d")      # 当前选择: 黄色实心
				sb.border_color = Color("cc9a00")
			elif is_achieved:
				sb.bg_color = Color("f3ae01")      # 已解锁: 实心
				sb.border_color = Color("cc8f00")
			elif is_gray:
				sb.bg_color = Color("9a9a9a")      # 条件不可用: 灰色
				sb.border_color = Color("777777")
			else:
				sb.bg_color = Color("fbfaf4")      # 未解锁: 空心
				sb.border_color = Color("c25b6b")
			sb.set_border_width_all(4)
			var box := Panel.new()
			box.add_theme_stylebox_override("panel", sb)
			box.position = Vector2(x0 + i * (sq + gap), band.position.y + (CARD_BAND_H - sq) * 0.5)
			box.size = Vector2(sq, sq)
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(box)
			i += 1

	# 点卡 = 进读信
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			_close_popup()
			_enter_level(key)
	)
	blocks_layer.add_child(card)
	open_cards.append(card)
	card.scale = Vector2(0.9, 0.9)
	card.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.15)

# 条件已不可用的结局: 已达成结局的 CHANGE(REPLACE/DRA) 移除了其条件引用句 → 该结局再也无法达成(灰色)
func _unavailable_endings(lv: LevelData, achieved: Array) -> Dictionary:
	var removed := {}
	for eid in achieved:
		var e: Dictionary = lv.endings.get(String(eid), {})
		for c in e.get("change", []):
			var ctype := String(c.get("type", ""))
			var data := String(c.get("data", ""))
			if ctype == "DRA" or ctype == "D":
				removed[data] = true
			elif ctype == "REPLACE":
				var info := lv.find_sentence(data)
				if not info.is_empty():
					removed[String(info["sentence"].get("base", ""))] = true
	var out := {}
	var re := RegEx.new()
	re.compile("[A-Za-z][A-Za-z0-9_]*")
	for cond in lv.conditions:
		var eid2 := String(cond.get("ending", ""))
		var expr := String(cond.get("expr", ""))
		for m in re.search_all(expr):
			if removed.has(String(m.get_string())):
				out[eid2] = true
				break
	return out

func _enter_level(key: String) -> void:
	var nd: Dictionary = nodes[key]
	GameState.current_level_id = String(nd.level_id)
	GameState.current_row = String(nd.row_id)
	# 回顾页「开始!」判定用: 记录本次点进是否为该关卡首次进入(并落盘)
	GameState.first_entry_level = GameState.mark_level_entered(String(nd.level_id))
	# 已解锁过结局的关卡: 再进入直接到调换纸条(排布)环节, 不再重读信件
	if GameState.history.get(String(nd.level_id), []).size() > 0:
		GameFlow.goto("arrange")
		return
	GameFlow.goto("letter")

func _close_popup() -> void:
	_click_gen += 1   # 作废飞行中的滚动开卡
	if open_cards.is_empty():
		return
	for c in open_cards:
		c.queue_free()
	open_cards.clear()
	open_level_id = ""
	_set_dim(false, [])

# 选中蒙版: 用一个动画同时处理进入淡化与退出淡化(0.25s);
# active 时淡出地图其余内容(表面/人物栏/剧情线/无关块), 只亮相关块与相关红线
func _set_dim(active: bool, keys: Array) -> void:
	var alpha := 0.32 if active else 1.0
	if _dim_tw != null and _dim_tw.is_valid():
		_dim_tw.kill()
	_dim_tw = create_tween()
	_dim_tw.set_parallel(true)
	_dim_tw.tween_property(surface, "modulate:a", alpha, 0.1)
	# 人物栏整体淡化, 但选中块对应角色的 header 保持高亮
	var bright_texes := {}
	if active:
		for k in keys:
			var cid := String(nodes[k].char)
			if header_ctls.has(cid):
				bright_texes[header_ctls[cid]] = true
	for c in header_row.get_children():
		if not bright_texes.has(c):
			_dim_tw.tween_property(c, "modulate:a", alpha, 0.1)
	for c in bright_texes:
		_dim_tw.tween_property(c, "modulate:a", 1.0, 0.1)
	_dim_tw.tween_property(rails_layer, "modulate:a", alpha, 0.1)
	for k in block_ctls:
		var ctl: Control = block_ctls[k]
		var ta := alpha if active and not keys.has(k) else 1.0
		_dim_tw.tween_property(ctl, "modulate:a", ta, 0.1)
	if active:
		rungs_layer.visible = true
		for rung in rungs_layer.get_children():
			var rel: Dictionary = rung.get_meta("rel", {})
			rung.visible = keys.has(String(rel.get("a", ""))) and keys.has(String(rel.get("b", "")))
		rungs_layer.modulate.a = 0.0
		_dim_tw.tween_property(rungs_layer, "modulate:a", 1.0, 0.1)
	else:
		_dim_tw.tween_property(rungs_layer, "modulate:a", 0.0, 0.1)
		_dim_tw.chain().tween_callback(func(): rungs_layer.visible = false)

# —— Toast ——

# 写信人独白字幕: 突然出现(无淡入), 与黑条提示同步播完(2.7s)后缓缓消失
func show_monologue(text: String) -> void:
	if text == "":
		return
	subtitle_label.text = text
	if _subtitle_tw != null and _subtitle_tw.is_valid():
		_subtitle_tw.kill()
	subtitle_label.modulate.a = 1.0
	_subtitle_tw = create_tween()
	_subtitle_tw.tween_interval(1.7)
	_subtitle_tw.tween_property(subtitle_label, "modulate:a", 0.0, 1.0)

func show_toast(text: String) -> void:
	toast_label.text = text
	var view := get_viewport().get_visible_rect().size
	var bh := 96.0
	toast_bar.size = Vector2(view.x, bh)
	toast_bar.position = Vector2(0.0, (view.y - bh) * 0.5)
	toast_label.size = Vector2(view.x, bh)
	toast_label.position = toast_bar.position
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	toast_bar.modulate.a = 0.0
	toast_label.modulate.a = 0.0
	_toast_tw = create_tween()
	_toast_tw.tween_property(toast_label, "modulate:a", 1.0, 0.2)
	_toast_tw.parallel().tween_property(toast_bar, "modulate:a", 1.0, 0.2)
	_toast_tw.tween_interval(2.0)
	_toast_tw.tween_property(toast_label, "modulate:a", 0.0, 0.5)
	_toast_tw.parallel().tween_property(toast_bar, "modulate:a", 0.0, 0.5)
