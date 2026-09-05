# ArrangeBoard.gd — 《WILL:美好世界》核心玩法:拖动字条改变故事结局
# 布局参数照抄《信件界面-单行关卡布局参数-Godot实现》:
#   双行 = CanvasPlay(左右列 + 中缝跨行拖放区 + 立绘/评级位 + 右缘按钮组);
#   单行 = CanvasLetter2(标题 + 标题线 + 单列字条区, 块宽 540)。
extends Control

const CardScript := preload("res://scripts/ui/arrange/card.gd")

const REF := Vector2(1920, 1080)

# 双行列参数(双列模板, 见 templates/双列交换纸条模板.tscn):
#   两列各宽 550, 分别位于视图中心(960)两侧 50px: L 右缘 910, R 左缘 1010
const COL_LAYOUT := {
	"L": {"x": 360.0, "w": 550.0},
	"R": {"x": 1010.0, "w": 550.0},
}
# 中缝(两列之间的窄缝): 拖过中缝 = 移到另一封信(对应 IN(L/R/M) 条件)
const SEAM := [910.0, 1010.0]
# 单行(参照 assets/example/单人交换纸条.png 实测): 立绘在左, 字条列 x=634 宽 992, 无标题
const SINGLE_X := 634.0
const SINGLE_W := 992.0
const COL_TOP := 85.0

# 字体(HYRunYuan)与字号
const LETTER_FONT := preload("res://assets/fonts/HYRunYuan-55W.ttf")
const FONT_SIZE := 28
const LINE_H := 34.0          # 行高 28×1.2
const BLOCK_MIN_H := 56.0     # 句子块最小高度
const BOARD_BOTTOM := 240.0   # 画布底部留白(滚动空间)

const COLOR_TEXT := Color(0.1, 0.1, 0.16)
const COLOR_BLOCK_TEXT := Color(0.93, 0.93, 1, 1)
const COLOR_BLOCK_BG := Color(0, 0, 0, 0.4)   # 不透明字块背景: 黑色 60%

# 首次解锁新结局时点「决定」后的倒计时时长(秒):时钟走完才揭晓结局、才切场景
const DECIDE_COUNTDOWN := 5.0

# 加载后的关卡数据(LevelData 结构化对象)
var level: LevelData = null

# 本关是否单行(ROWCOUNT=1)
var single_row := false

# 判定结局后回到本场景(锁定态): 白底 + 字条锁定不可拖拽(条件句块染角色主题色半透明)
# + 右侧只剩「再试一次」「返回」+ 每栏显示结局 Rank 标签
var locked := false

# 新结局倒计时进行中:屏蔽重复点击「决定」
var _deciding := false

# 各行条件句块(白色字条下方最后一块)上的倒计时色彩条, 与旋转时钟同帧启动
var _cd_bars: Array = []

@onready var board: Control = $BoardScroll/Board
@onready var left_column: VBoxContainer = $BoardScroll/Board/LeftColumn
@onready var right_column: VBoxContainer = $BoardScroll/Board/RightColumn
# 人物剪影动画槽(EnvelopeLayer 下, 位置在场景文件里拖): 左槽=左列人物, 右槽=右列人物
@onready var l_anim_slot: Control = $EnvelopeLayer/LAnimSlot
@onready var r_anim_slot: Control = $EnvelopeLayer/RAnimSlot
# 背景: 双行 = DualBG 模式(左右主题色 + 中央锯齿互补, scenes/arrange/dual_bg.tscn);
#        单行 = 全屏 letter_bg 整图
@onready var dual_bg: Control = $DualBG
@onready var single_bg: TextureRect = $SingleBG
@onready var l_figure: ColorRect = get_node_or_null("BoardScroll/Board/LFigure") as ColorRect
@onready var r_figure: ColorRect = get_node_or_null("BoardScroll/Board/RFigure") as ColorRect
@onready var decide_btn: TextureButton = $EdgeButtons/DecideButton
@onready var reset_btn: TextureButton = $EdgeButtons/ResetButton
@onready var retry_btn: TextureButton = $EdgeButtons/RetryButton
@onready var back_btn: TextureButton = $EdgeButtons/BackButton
# 结算白底(锁定态盖住双人光柱/单人底图)
@onready var white_bg: ColorRect = $WhiteBG
# 每栏一个 Rank 标签(静态 UI, 位置在场景文件里改): L/R/M 三列预留
@onready var rank_tags: Array[TextureRect] = [$RankTagL, $RankTagR, $RankTagM]
@onready var result_label: Label = $ResultLabel

func _ready() -> void:
	decide_btn.pressed.connect(_on_execute_pressed)
	reset_btn.pressed.connect(_on_reset_pressed)
	retry_btn.pressed.connect(_on_retry_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	_load_level()

# 「原始状态」: 字条恢复最初的排布顺序(清除本关排列快照后重建)
func _on_reset_pressed() -> void:
	if _deciding or locked:
		return
	GameState.sequences = {}
	GameState.sequences_level = ""
	_apply_level()

# 「返回」: 回主界面(选关地图)
func _on_back_pressed() -> void:
	GameFlow.goto("map")

# 「再试一次」(锁定态): 解除锁定, 回到可拖拽的交换纸条画面(保留当前排列)
func _on_retry_pressed() -> void:
	if _deciding:
		return
	GameState.verdicts = {}
	_build_layout()
	_apply_level()

# —— 关卡加载:LevelData → 界面 ——

func _load_level() -> void:
	level = LevelData.load_level(GameState.current_level_id)
	_build_layout()
	_apply_level()

# 布局分支(参照双人/单人交换纸条截图): 单行 = 全屏底图 + 单列; 双行 = 光柱底 + 双列
func _build_layout() -> void:
	single_row = level.row_count == 1
	right_column.visible = not single_row
	_set_visible(r_figure, not single_row)
	# 剪影动画绑定: 左槽=第一行, 右槽=第二行(单行关右槽隐藏)
	if level.rows.size() > 0:
		_setup_row_anim(l_anim_slot, level.rows[0])
		if level.rows.size() > 1 and not single_row:
			_setup_row_anim(r_anim_slot, level.rows[1])
		else:
			CharacterAnim.setup(r_anim_slot, "")
	else:
		CharacterAnim.setup(l_anim_slot, "")
		CharacterAnim.setup(r_anim_slot, "")

# 槽位绑定行的动画: 关卡 JSON 行级 anim 直接配优先, 缺省按人物 characters.json 的 anim
func _setup_row_anim(slot: Control, row: LevelData.Row) -> void:
	if row.anim != "":
		CharacterAnim.setup_path(slot, row.anim)
	else:
		CharacterAnim.setup(slot, String(row.character))
	if single_row:
		# 单人: 全屏底图(角色 letter_bg, 文档 §5.1) + 单列(x=634, 宽 992)
		dual_bg.visible = false
		single_bg.visible = true
		var characters := LevelData.load_characters()
		var cid := String(level.rows[0].character)
		var path := String(characters.get(cid, {}).get("letter_bg", ""))
		if path != "" and ResourceLoader.exists(path):
			single_bg.texture = load(path)
		_set_visible(l_figure, true)
		left_column.position = Vector2(SINGLE_X, COL_TOP)
		left_column.size.x = SINGLE_W
	else:
		# 双人: DualBG 模式(左右各是 L/R 人物主题色, 中央锯齿互补卡齐)
		dual_bg.visible = true
		single_bg.visible = false
		var characters := LevelData.load_characters()
		var lc := String(level.rows[0].character)
		var rc := String(level.rows[1].character)
		var l_color := Color(String(characters.get(lc, {}).get("color", "#ffffff")))
		var r_color := Color(String(characters.get(rc, {}).get("color", "#ffffff")))
		dual_bg.setup(l_color, r_color)
		_set_visible(l_figure, true)
		left_column.position = Vector2(COL_LAYOUT["L"].x, COL_TOP)
		left_column.size.x = COL_LAYOUT["L"].w
		right_column.position = Vector2(COL_LAYOUT["R"].x, COL_TOP)
		right_column.size.x = COL_LAYOUT["R"].w

# 可空节点(占位立绘等被编辑器删掉时也不崩)
func _set_visible(node: Node, v: bool) -> void:
	if node != null:
		node.visible = v

# 基准栏宽(布局参数, 不随子节点增长——字块垫底矩形会超出栏 5px,
# 若用 column.size.x 会在每次重建时把栏越撑越宽)
func _col_base_w() -> float:
	return SINGLE_W if single_row else COL_LAYOUT["L"].w

func _apply_level() -> void:
	if level == null or level.rows.is_empty():
		push_error("关卡数据为空: %s" % GameState.current_level_id)
		return
	# 判定状态先算好(锁定 + Rank 标签): 锁定态下字条黑底白字、不可拖拽
	_restore_verdict_label()
	_cd_bars.clear()
	var characters: Dictionary = LevelData.load_characters()
	# 本关有保存的排列快照(执行过、从阅览信件跳回)则按快照还原字条位置
	var restore := GameState.sequences_level == level.level_id and not GameState.sequences.is_empty()
	# 最新判定若 REPLACE 过某些句子(触发过阅览重放), 这些句子的显示文本换成条件句正文
	var replace_map: Dictionary = {}
	var verdict: Dictionary = GameState.verdicts
	if String(verdict.get("level_id", "")) == level.level_id:
		replace_map = level.change_maps(verdict.get("changes", [])).get("replace", {})
	# 行 ↔ 栏:第 i 行对应第 i 栏(单行关卡只有左栏有内容)
	var columns: Array[VBoxContainer] = [left_column, right_column]
	for i in mini(level.rows.size(), columns.size()):
		var row: LevelData.Row = level.rows[i]
		var column := columns[i]
		for child in column.get_children():
			# 先移出树再延迟释放: 否则新块 add_child 撞名会被自动改名(@PanelContainer@N),
			# 快照里存的 id 对不上, 还原时块就"消失"了
			column.remove_child(child)
			child.queue_free()
		var row_color := _character_color(characters, row.character)
		# 块与字条的排布序列: 行级 order 字段优先(固定块可与字条穿插, 如块夹在两张字条之间);
		# 缺省 = 首固定块 → 字条 → 其余固定块; 有快照时按快照序列还原(块仍在其固定位置)
		var seq: Array[String] = level.layout_sequence(row)
		if restore and GameState.sequences.has(row.id):
			seq = []
			for sid in GameState.sequences[row.id]:
				seq.append(String(sid))
		# 顶部框架块 = 序列里的第一个固定块; 条件句块 = 最后一个固定块(挂倒计时色彩条)
		var top_block := ""
		var last_block := ""
		for id in seq:
			if _is_block_of(row, id):
				if top_block == "":
					top_block = id
				last_block = id
		for sid in seq:
			var id := String(sid)
			var info := level.find_sentence(id)
			if info.is_empty():
				continue
			if _is_block_of(row, id):
				# 固定块(黑块): 顶部框架块保持半透明黑; 白底锁定态其余块染本行角色主题色
				_create_block(column, info["sentence"], replace_map, locked, row_color,
					id == top_block, id == last_block)
			else:
				# 白色字条: 颜色 = 定义该字条的行所对应的角色色(跨栏移动后身份不变)
				var home: LevelData.Row = info["row"]
				_place_strip(
					column,
					id,
					_display_text(level, replace_map, info["sentence"]),
					_character_color(characters, home.character),
					locked,
					replace_map.has(id)
				)
# 4. 内容超出一屏时画布加高(滚轮上下滚动)
	call_deferred("_fit_board_height")

# 画布高度 = 最高一栏的内容高度 + 底部留白; 不足一屏保持一屏
func _fit_board_height() -> void:
	var max_h := 0.0
	for col: VBoxContainer in [left_column, right_column]:
		if col.visible:
			max_h = maxf(max_h, col.get_combined_minimum_size().y)
	board.custom_minimum_size.y = maxf(REF.y, COL_TOP + max_h + BOARD_BOTTOM)

# 情节块(固定句): 运行时按数据生成(文档: 块模板序列化位置是占位, 按信内容排布);
# 配色: 顶部框架块(首固定句)与非白底态 = 半透明黑;
#       白底锁定态下其余固定块染本行角色主题色半透明(0.9: 线性混合下白底会把低 alpha 洗成灰);
# 唯一效果: 2px 黑色外投影
func _create_block(column: VBoxContainer, block: Dictionary, replace_map: Dictionary, locked := false, row_color := Color(0, 0, 0, 1), is_top := false, with_cd_bar := false) -> void:
	var panel := PanelContainer.new()
	panel.name = String(block.get("id", ""))
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var sb := StyleBoxFlat.new()
	if is_top or not locked:
		sb.bg_color = COLOR_BLOCK_BG
	else:
		sb.bg_color = Color(row_color.r, row_color.g, row_color.b, 0.9)   # 白底锁定态: 本行角色主题色
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 2
	sb.shadow_offset = Vector2(2, 2)
	panel.add_theme_stylebox_override("panel", sb)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	panel.add_child(margin)
	var block_text := _display_text(level, replace_map, block)
	var col_w := _col_base_w()               # 基准栏宽(不随子节点增长)
	var bcol_w := maxf(col_w - 32.0, 200.0)  # 32 边距
	var bts := LETTER_FONT.get_multiline_string_size(block_text, HORIZONTAL_ALIGNMENT_LEFT, bcol_w, FONT_SIZE)
	var text_label := RichTextLabel.new()
	text_label.name = "Text"
	text_label.text = block_text
	text_label.fit_content = false
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.scroll_active = false
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label.add_theme_font_override("normal_font", LETTER_FONT)
	text_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	text_label.add_theme_color_override("default_color", COLOR_BLOCK_TEXT)
	text_label.custom_minimum_size = Vector2(bcol_w, maxf(BLOCK_MIN_H, bts.y))
	margin.add_child(text_label)
	column.add_child(panel)

	# 白色字条下方的条件句块(每行最后一块): 挂倒计时色彩条, 平时隐藏;
	# 「决定」后与旋转时钟同帧启动(原版红/蓝变体 = 各行角色主题色)
	if with_cd_bar:
		var bar := CdBar.new()
		bar.name = "CdBar"
		bar.bar_color = row_color
		panel.add_child(bar)
		_cd_bars.append(bar)

# 句子的当前显示文本: 被最新结局 REPLACE 时显示条件句正文, 否则显示自身文本;
# 排布界面上 [page] 换页标记按换行展示(换页只在读信场景生效), [right] 标记剔除
func _display_text(level: LevelData, replace_map: Dictionary, sentence: Dictionary) -> String:
	var sid := String(sentence.get("id", ""))
	if replace_map.has(sid):
		var info := level.find_sentence(String(replace_map[sid]))
		if not info.is_empty():
			return level.sentence_text(info["sentence"]).replace("\f", "\n").replace(LevelData.RIGHT_MARK, "")
	return level.sentence_text(sentence).replace("\f", "\n").replace(LevelData.RIGHT_MARK, "")

# 某个句子 id 是否是本行的黑块(黑块固定不可移动, 还原排列时跳过)
func _is_block_of(row: LevelData.Row, id: String) -> bool:
	for block: Dictionary in row.blocks:
		if String(block.get("id", "")) == id:
			return true
	return false

# 显示判定结果(执行后与场景重新载入后共用)
func _show_verdict(verdict: Dictionary) -> void:
	result_label.text = "【结局】%s 评级 %s 声望 +%d(命中条件 #%d)" % [
		String(verdict.get("ending_id", "?")),
		String(verdict.get("rank", "?")),
		int(verdict.get("rep", 0)),
		int(verdict.get("matched_index", 0)) + 1,
	]
	# 结局 Rank 标签(assets/RANK/ranktag<Rank>.png): 每栏一个(L/R/M), 与结局评级绑定;
	# 本关有几行就亮几个(单行只亮 L)
	var rk := String(verdict.get("rank", "?"))
	var path := "res://assets/RANK/ranktag%s.png" % rk
	if not ResourceLoader.exists(path):
		return
	var tex := load(path)
	for i in rank_tags.size():
		var tag: TextureRect = rank_tags[i]
		tag.texture = tex
		tag.visible = i < level.rows.size()

# 场景载入时恢复上次的判定结果显示(不是本关的判定则清空);
# 本关判定过 = 锁定态: 白底 + 字条不可拖拽 + 右侧只剩「再试一次」「返回」+ 每栏 Rank 标签
func _restore_verdict_label() -> void:
	var verdict: Dictionary = GameState.verdicts
	locked = String(verdict.get("level_id", "")) == level.level_id
	# 锁定态背景换成白色(盖掉双人光柱/单人底图)
	white_bg.visible = locked
	if locked:
		dual_bg.visible = false
		single_bg.visible = false
	# 右侧按钮: 解锁态 = 决定/原始状态/返回; 锁定态 = 再试一次/返回
	decide_btn.visible = not locked
	reset_btn.visible = not locked
	retry_btn.visible = locked
	for tag: TextureRect in rank_tags:
		tag.visible = false
	if not locked:
		result_label.text = "（尚未执行）"
		# 白底上用深色文字; 解锁态回到原本的暖黄色
		result_label.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
		return
	result_label.add_theme_color_override("font_color", Color(0.45, 0.25, 0.15))
	_show_verdict(verdict)

# 角色 id → 颜色(缺省返回白色,便于一眼发现配置错误)
func _character_color(characters: Dictionary, key: String) -> Color:
	var info: Dictionary = characters.get(key, {})
	return Color(String(info.get("color", "#ffffff")))

# 创建一张字条:白色字块 + 左上角斜角色标签(文档: 60 高起, 自动加高);
# locked(判定结局后回到本场景)= 黑底白字、不可拖拽;
# locked 且是条件句(被结局 REPLACE 的字条)= 底色换成角色主题色半透明;
# 唯一效果: 2px 黑色外投影
func _place_strip(column: VBoxContainer, id: String, text: String, color: Color, locked := false, is_condition := false) -> void:
	var strip: Card = CardScript.new()
	strip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # 只占自身高度,不吸收栏内多余空间
	strip.locked = locked

	var font := LETTER_FONT
	var col_w := _col_base_w()               # 基准栏宽(不随子节点增长)
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

	column.add_child(strip)
	strip.setup(id, text)

# 读取一栏当前的排列顺序(自上而下),返回 id 数组——结局判定就靠它:
# 白色字条 = 字条 id(如 A1);黑色情节块 = 节点名(如 PanelA1),同样计入顺序
func get_sequence_ids(column: VBoxContainer) -> Array[String]:
	var ids: Array[String] = []
	for child in column.get_children():
		if child is Card:
			ids.append(child.card_id)
		elif child is PanelContainer and child.find_child("Text", true, false):
			ids.append(String(child.name))
	return ids

# 点击"决定" = 做出决定:冻结排列 → 判定结局 → 进入下一场景。
# 判定后:
# - 首次解锁的新结局 → 旋转时钟倒数(走完才揭晓结局、切场景);
# - 重复结局(已解锁过)→ 不转钟, 立即揭晓、切场景。
# 下一场景:
# - 新解锁的结局, 且它的 CHANGE 会改动某行的 TYPE 2 条件句 → 信件阅览重放被改动的那行
#   (REPLACE 换正文 / DRA 删除), 读完由 letter 场景回本场景的白底锁定态(结算展示);
# - 其余情况(已解锁过的结局 / 没有需要改动的内容)→ 直接回本场景白底锁定态。
# 结算展示 = 白底锁定态: 字条排列与判定结果都保留
func _on_execute_pressed() -> void:
	if _deciding or level == null or level.rows.is_empty():
		return
	# 1. 冻结这次决定的排列(倒计时期间不再响应「决定」,字条也不会再动)
	var columns: Array[VBoxContainer] = [left_column, right_column]
	var sequences: Dictionary = {}
	for i in mini(level.rows.size(), columns.size()):
		sequences[level.rows[i].id] = get_sequence_ids(columns[i])
	print("排列: ", sequences)
	GameState.sequences = sequences
	GameState.sequences_level = level.level_id

	# 2. 判定结局
	var verdict := RuleEngine.judge(level, sequences)
	if verdict.is_empty():
		result_label.text = "【未命中】没有条件匹配(检查 conditions 是否缺 fallback)"
		return

	# 3. 首次解锁的新结局: 旋转时钟倒数(素材 assets/clock), 走完才揭晓、切场景;
	#    重复结局(已解锁过): 不转钟, 直接揭晓
	_deciding = true
	decide_btn.disabled = true
	# Bad 评级不进倒计时动画, 直接揭晓(初始排列默认命中 Bad 时尤其如此)
	if bool(verdict.get("is_new", false)) and String(verdict.get("rank", "")) != "Bad":
		result_label.text = "（判定中…）"
		# 倒计时演出: 切白底 + 隐藏右侧按钮组 + 旋转时钟与色彩条同帧启动
		white_bg.visible = true
		dual_bg.visible = false
		single_bg.visible = false
		result_label.add_theme_color_override("font_color", Color(0.45, 0.25, 0.15))
		for btn: TextureButton in [decide_btn, reset_btn, back_btn, retry_btn]:
			btn.visible = false
		var clock := CountdownClock.start(self, DECIDE_COUNTDOWN)
		for bar: CdBar in _cd_bars:
			bar.play()
		await clock.finished
		# 演出结束恢复按钮(随后揭晓结局并切场景; 恢复兜底避免间隙闪烁)
		decide_btn.visible = true
		reset_btn.visible = true
		back_btn.visible = true
		retry_btn.visible = locked
	_deciding = false
	decide_btn.disabled = false

	# 4. 揭晓结局
	_show_verdict(verdict)

	# 5. 进入下一场景。rows = 该结局需要改动的行(REPLACE/DRA 涉及的 TYPE 2 条件句所在行);
	#    已解锁过的结局不再重放(is_new 由 RuleEngine 在写入图鉴前判定)
	var rows: Array = []
	if bool(verdict.get("is_new", false)):
		rows = RuleEngine.affected_rows(level, verdict)
	if rows.is_empty():
		GameFlow.goto("arrange")   # 直接回本场景白底锁定态(结算展示)
		return
	GameState.review_queue = rows
	GameState.current_row = String(rows[0])
	GameState.review_letter = true
	GameFlow.goto("letter")

# —— 兜底放置逻辑(文档: 中缝跨行拖放) ——

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Card):
		return false
	_route_preview(data as Card, get_viewport().get_mouse_position())
	return true

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not (data is Card):
		return
	_route_drop(data as Card, get_viewport().get_mouse_position())

# 目标栏: 中缝 x∈[950,1016] → 另一栏(跨行 = 移到另一封信);
# 单行关只允许左栏; 双行按字条列区间归属; 都不在 → null(归位)
func _target_column(card: Card, mouse: Vector2) -> VBoxContainer:
	if mouse.y < 0.0 or mouse.y > REF.y:
		return null
	if single_row:
		return left_column
	if mouse.x >= SEAM[0] and mouse.x <= SEAM[1]:
		return right_column if card.origin_slot == left_column else left_column
	if mouse.x >= COL_LAYOUT["L"].x and mouse.x <= COL_LAYOUT["L"].x + COL_LAYOUT["L"].w:
		return left_column
	if mouse.x >= COL_LAYOUT["R"].x and mouse.x <= COL_LAYOUT["R"].x + COL_LAYOUT["R"].w:
		return right_column
	return null

# 悬停占位缝隙路由到目标栏(栏外清空所有缝隙)
func _route_preview(card: Card, mouse: Vector2) -> void:
	var col := _target_column(card, mouse)
	if col:
		col.update_preview_gap(card, col.get_local_mouse_position())
	else:
		for c: VBoxContainer in [left_column, right_column]:
			if c.has_method("_remove_preview_gap"):
				c._remove_preview_gap()

func _route_drop(card: Card, mouse: Vector2) -> void:
	var col := _target_column(card, mouse)
	if col:
		col.receive_drop(card, col.get_local_mouse_position())
		return
	card.return_to_origin()
