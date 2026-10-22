# 地图细节卡的外观组件：只接收显示数据，不读写存档，也不切场景。
# 改标题字号、边框或结局方块颜色时，从这个文件开始。
extends RefCounted

# 块下细节卡(仿原版 A.png): 深棕圆角框, 上白底关卡名, 下灰底结局方块
const CARD_W := 300.0
const CARD_TITLE_H := 88.0
const CARD_BAND_H := 58.0
const CARD_BORDER := 6.0

static func build(title_text: String, endings: Dictionary, achieved: Array, cur: String, font: Font) -> Control:
	# 第一次打开(尚无结局): 只显示标题栏, 底部结局横带隐藏
	var show_band: bool = achieved.size() > 0
	var card_h := CARD_BORDER * 2.0 + CARD_TITLE_H + (CARD_BAND_H if show_band else 0.0)

	# 创建卡片，摆放位置由地图决定
	var card := Control.new()
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
	title.text = title_text
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
		# 灰底横带 + 结局方块(黄色实心=当前选择, 实心=已解锁, 空心=未解锁, 未解锁结局仍可通过重试探索;
		# 评级字母显示在地图关卡块上, 不在这里)
		var band := ColorRect.new()
		band.color = Color("c9c7c2")
		band.position = Vector2(CARD_BORDER, CARD_BORDER + CARD_TITLE_H)
		band.size = Vector2(CARD_W - CARD_BORDER * 2.0, CARD_BAND_H)
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(band)
		if cur == "" and achieved.size() > 0:
			cur = String(achieved[achieved.size() - 1])
		var total := endings.size()
		var sq := 36.0
		var gap := 14.0
		var x0 := (CARD_W - (total * sq + (total - 1) * gap)) * 0.5
		var i := 0
		for eid in endings:
			var is_achieved: bool = achieved.has(String(eid))
			var is_current: bool = is_achieved and String(eid) == cur
			var sb := StyleBoxFlat.new()
			if is_current:
				sb.bg_color = Color("ffd83d")      # 当前选择: 黄色实心
				sb.border_color = Color("cc9a00")
			elif is_achieved:
				sb.bg_color = Color("f3ae01")      # 已解锁: 实心
				sb.border_color = Color("cc8f00")
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

	return card
