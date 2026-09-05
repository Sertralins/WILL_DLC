# map_route.gd — 素材管件拼接连线(取代 map_line.gd 的自绘折线)
#
# 用 assets/sceneUI/line/ 的手绘管件沿路由逐段拼接(类似"铺水管"):
#   同列     = 竖直线(件 7 拉伸); 同高异列 = 横直线(件 9 拉伸);
#   跨列 S 弯 = 竖段 → 上弯角(4/5) → 横段 → 下弯角(0/1) → 竖段。
# 拼装规则: 直段两端各伸入弯角件下方 6px(OVER_RUN) 掩盖接缝, 弯角件 z_index 在上;
#           弯角件固定 37×37 不缩放, 直段只拉伸不旋转。
# dashed=true 时整套换成 dotted_lines_*(虚线, 同构)。
# 生长动画: set_progress(0..1) 按各段时间窗映射 scale, 沿路径序逐段 reveal
#           (直段沿轴伸长, 弯角以入口管口为枢轴弹出)。
# TODO: 断线件 12~15(线与线正交穿越时"被压住"的视觉)未实现, 当前数据无穿越场景。
extends Node2D

const TEX_DIR := "res://assets/sceneUI/line/"
const OVER_RUN := 6.0
const CORNER_DUR := 0.09              # 弯角弹出时长(秒)
const STRAIGHT_MIN := 0.10            # 直段最短时长
const STRAIGHT_MAX := 0.28            # 直段最长时长
const CORNER_HALF := 31.5             # 弯角管口到管口的世界偏移(37 画布, 内容 3..33)

# 弯角件方向(件内内容包围盒实测, 37×37 画布):
#   0 = 横左入→竖下出(内容 x3..36,y3..36)  1 = 横右入→竖下出(内容 x0..33,y3..36)
#   4 = 竖上入→横右出(内容 x3..36,y0..33)  5 = 竖上入→横左出(内容 x0..33,y0..33)
# 直段件: 7 = 竖(10×64, 内容双端齐平)  9 = 横(64×10, 内容双端齐平)

static var _cache := {}                # "solid_7" → Texture2D(懒加载, 实例共享)

var a := Vector2.ZERO                  # 起点(父块顶边中点 / start 锚点)
var b := Vector2.ZERO                  # 终点(子块顶边中点)
var line_color := Color.WHITE
var dashed := false                    # true → dotted_lines_*
var grow_time := 0.0
var total := 0.0                       # 生长总时长(秒)
var sections: Array = []               # 生长序: {kind, seg(Node2D), t0, t1}

static func _tex(id: int, is_dashed: bool) -> Texture2D:
	var key := ("dotted_%d" if is_dashed else "solid_%d") % id
	if not _cache.has(key):
		var prefix := "dotted_lines_%d.png" if is_dashed else "connecting_lines_%d.png"
		_cache[key] = load(TEX_DIR + prefix % id)
	return _cache[key]

func setup(from: Vector2, to: Vector2, color: Color, is_dashed := false, grow := 0.0) -> void:
	a = from
	b = to
	line_color = color
	dashed = is_dashed
	grow_time = grow

func _ready() -> void:
	_build_sections()
	if grow_time > 0.0:
		set_progress(0.0)
		var tw := create_tween()
		tw.tween_method(set_progress, 0.0, 1.0, grow_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# —— 路由 ——

func _build_sections() -> void:
	if is_equal_approx(a.x, b.x):
		_add_v(a.x, a.y, b.y)
	elif is_equal_approx(a.y, b.y):
		_add_h(a.y, a.x, b.x)
	elif _s_bend():
		pass
	else:
		_add_slant()
	_finalize()

# 同列竖直线(入口端 = a 端)
func _add_v(x: float, y0: float, y1: float, order := 0) -> void:
	var top := minf(y0, y1)
	var len := absf(y1 - y0)
	var down := y1 >= y0
	_spawn("v", _tex(7, dashed),
		Vector2(x, top if down else top + len),      # 枢轴 = 入口端(生长端)
		Vector2(-4.5, 0.0),
		Vector2(1.0, len / 64.0 if down else -len / 64.0),
		false, 0.0, order)

# 同高横直线(入口端 = a 端)
func _add_h(y: float, x0: float, x1: float, order := 0) -> void:
	var left := minf(x0, x1)
	var len := absf(x1 - x0)
	var right := x1 >= x0
	_spawn("h", _tex(9, dashed),
		Vector2(left if right else left + len, y),
		Vector2(0.0, -4.5),
		Vector2(len / 64.0 if right else -len / 64.0, 1.0),
		false, 0.0, order)

# 跨列 S 弯: 上弯角(竖→横) + 横段 + 下弯角(横→竖下); 仅支持子块在父块下方(a.y < b.y)
# 段几何(向右, dx>0): 上弯角件 4 TL=(a.x-4.5, yh-31.5), H 出口 (a.x+31.5, yh);
#   下弯角件 1 TL=(b.x-31.5, yh-4.5), V 出口 (b.x, yh+31.5)。向左镜像(件 5/0)。
func _s_bend() -> bool:
	if a.y >= b.y:
		return false
	var dx := b.x - a.x
	var dy := b.y - a.y
	if dy < 71.0 or absf(dx) < 75.0:   # 高度不够放两个弯角 / 横段净长 <4px
		return false
	var yh := clampf((a.y + b.y) * 0.5, a.y + 35.5, b.y - 35.5)
	var right := dx > 0.0
	# v1: a → 上弯角 V 口(末端伸入 +OVER_RUN)
	_add_v(a.x, a.y, yh - CORNER_HALF + OVER_RUN, 0)
	# h: 两弯角 H 口之间(两端各 +OVER_RUN); 净长至少 4px
	var hx0 := a.x + CORNER_HALF if right else a.x - CORNER_HALF
	var hx1 := b.x - CORNER_HALF if right else b.x + CORNER_HALF
	if absf(hx1 - hx0) < 4.0:
		return false
	_add_h(yh, hx0 - OVER_RUN if right else hx0 + OVER_RUN,
		hx1 + OVER_RUN if right else hx1 - OVER_RUN, 2)
	# v2: 下弯角 V 出口 → b(起点上探 +OVER_RUN 伸入弯角)
	_add_v(b.x, yh + CORNER_HALF - OVER_RUN, b.y, 4)
	# 上弯角: 竖入横出(件 4 向右 / 件 5 向左), 入口管口 = V 口上缘
	_spawn("corner", _tex(4 if right else 5, dashed),
		Vector2(a.x, yh - CORNER_HALF),
		Vector2(-4.5 if right else -CORNER_HALF, 0.0),
		Vector2.ONE, false, 0.0, 1)
	# 下弯角: 横入竖下出(件 1 向右 / 件 0 向左), 入口管口 = H 口
	# (件 1 H 口在件内 x=0, 件 0 H 口在件内 x=36 → 枢轴 = H 口世界坐标)
	_spawn("corner", _tex(1 if right else 0, dashed),
		Vector2(b.x - CORNER_HALF if right else b.x + CORNER_HALF, yh),
		Vector2(0.0 if right else -36.0, -4.5),
		Vector2.ONE, false, 0.0, 3)
	return true

# 回退: 单段斜线(件 9 拉伸 + 旋转), 防御异常几何(子在上 / 窗口太窄)
func _add_slant() -> void:
	push_warning("map_route: 无法管件路由(%s → %s), 回退斜线" % [str(a), str(b)])
	var len := a.distance_to(b)
	var ang := (b - a).angle()
	_spawn("slant", _tex(9, dashed),
		a, Vector2(len * 0.5, 0.0), Vector2(len / 64.0, 1.0),
		true, ang)

# —— 段构建 ——

func _spawn(kind: String, tex: Texture2D, pos: Vector2, sp_pos: Vector2,
		sp_scale: Vector2, centered := false, rot := 0.0, order := 0) -> void:
	var seg := Node2D.new()
	seg.position = pos
	seg.rotation = rot
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.centered = centered
	sp.position = sp_pos
	sp.scale = sp_scale
	sp.modulate = line_color
	sp.z_index = 1 if kind == "corner" else 0   # 弯角压住直段接缝
	seg.add_child(sp)
	add_child(seg)
	sections.append({"kind": kind, "seg": seg, "t0": 0.0, "t1": 0.0, "order": order})

# 生长时间窗: 按显式生长序分配(弯角 0.09s, 直段按长度 0.10~0.28s);
# 注意 spawn 顺序(v1/h/v2 → 弯角)为 z 序, 与生长序不同
func _finalize() -> void:
	sections.sort_custom(func(x, y): return x.order < y.order)
	total = 0.0
	for sec in sections:
		var dur := CORNER_DUR if sec.kind == "corner" else \
			clampf(_seg_len(sec.seg) / 600.0, STRAIGHT_MIN, STRAIGHT_MAX)
		sec.t0 = total
		sec.t1 = total + dur
		total += dur

func _seg_len(seg: Node2D) -> float:
	var sp: Sprite2D = seg.get_child(0)
	var s := sp.scale
	return 64.0 * (absf(s.x) if sp.texture.get_width() > sp.texture.get_height() else absf(s.y))

# —— 生长动画 ——

func set_progress(p: float) -> void:
	if sections.is_empty() or total <= 0.0:
		return
	var t := clampf(p, 0.0, 1.0) * total
	for sec in sections:
		var u: float = clampf((t - sec.t0) / maxf(sec.t1 - sec.t0, 0.001), 0.0, 1.0)
		var seg: Node2D = sec.seg
		match sec.kind:
			"v":
				seg.scale = Vector2(1.0, u)
			"h", "slant":
				seg.scale = Vector2(u, 1.0)
			"corner":
				var e := u * u * (3.0 - 2.0 * u)   # smoothstep 弹出
				seg.scale = Vector2(e, e)
