# 字条外观组件：创建白纸、角色色标和正文；拖拽行为在 card.gd。
# 接收文本、颜色、栏宽和状态，不读取 GameState，也不执行判定。
extends RefCounted

const CardScript := preload("res://scenes/arrange/card.gd")
const LETTER_FONT := preload("res://assets/fonts/HYRunYuan-45J.ttf")
const FONT_SIZE := 32
const BLOCK_MIN_H := 56.0
const COLOR_TEXT := Color(0.1, 0.1, 0.16)

# 创建一张字条:白色字块 + 左上角斜角色标签(文档: 60 高起, 自动加高);
# locked(判定结局后回到本场景)= 黑底白字、不可拖拽;
# locked 且是条件句(被结局 REPLACE 的字条)= 底色换成角色主题色半透明;
# 唯一效果: 2px 黑色外投影
static func build(id: String, text: String, color: Color, col_w: float, locked := false, is_condition := false) -> Card:
	var strip: Card = CardScript.new()
	strip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # 只占自身高度,不吸收栏内多余空间
	strip.locked = locked

	var font := LETTER_FONT
	var wrap_w := maxf(col_w - 28.0, 1.0)    # 28 内容边距
	var text_size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, wrap_w, FONT_SIZE)
	var body_h := maxf(BLOCK_MIN_H, text_size.y)
	strip.custom_minimum_size = Vector2(col_w, body_h + 24.0)

	# 字块本体: 普通 = 白底; 锁定态 = 黑底白字; 锁定态条件句 = 角色主题色半透明
	# 上下边距一致; 2px 黑色外投影
	var white := StyleBoxFlat.new()
	if locked and is_condition:
		white.bg_color = Color(color.r, color.g, color.b, 0.9)   # 与条件句块一致: 0.9 才看得出主题色
	elif locked:
		white.bg_color = Color(0.1, 0.1, 0.12, 0.92)
	else:
		white.bg_color = Color.WHITE
	white.content_margin_left = 14.0
	white.content_margin_right = 14.0
	white.content_margin_top = 12.0
	white.content_margin_bottom = 12.0
	white.shadow_color = Color(0, 0, 0, 0.25)
	white.shadow_size = 2
	white.shadow_offset = Vector2(2, 2)
	strip.add_theme_stylebox_override("panel", white)

	# 内容根(普通 Control, 以便在左上角放斜着的角色小标签)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.custom_minimum_size = Vector2(wrap_w, body_h)   # 显式最小尺寸, 保证白纸包住文字
	strip.add_child(root)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	box.alignment = BoxContainer.ALIGNMENT_CENTER   # 文字在字条内垂直居中
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(box)

	# 左上角小标签(按规格): 长 60 宽 30, 顺时针旋转 30°, 中心与字条左上角顶点重合;
	# 颜色跟着人物色走, 跨栏移动后身份不变; 四周一圈 3px 半透明阴影
	# 注: Control.position 是矩形左上角原点, 锚点实际落在 position + pivot_offset
	var tag := ColorRect.new()
	tag.name = "Tag"
	tag.color = color
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.size = Vector2(45.0, 30.0)
	tag.pivot_offset = tag.size * 0.5          # 旋转轴 = 矩形中心
	tag.position = Vector2(-14.0, -12.0) - tag.pivot_offset   # 中心落在字条外框左上角
	tag.rotation = deg_to_rad(30.0)            # 顺时针 30°
	var tag_shadow := ColorRect.new()
	tag_shadow.color = Color(0, 0, 0, 0.25)
	tag_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_shadow.size = tag.size + Vector2(6.0, 6.0)   # 四周各多 3px
	tag_shadow.pivot_offset = tag_shadow.size * 0.5
	tag_shadow.position = tag.position + tag.pivot_offset - tag_shadow.pivot_offset   # 与标签同心
	tag_shadow.rotation = tag.rotation
	root.add_child(tag_shadow)
	root.add_child(tag)

	# 字条文字
	var label := RichTextLabel.new()
	label.name = "Label"
	label.text = text
	label.fit_content = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("normal_font", LETTER_FONT)
	label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	label.add_theme_color_override("default_color", Color(0.95, 0.95, 0.98) if locked else COLOR_TEXT)
	label.custom_minimum_size = Vector2(wrap_w, text_size.y)   # 实际文本高, 由 VBox 居中
	box.add_child(label)

	strip.setup(id, text)
	return strip
