# ArrangeBoard.gd — 《WILL:美好世界》核心玩法:拖动字条改变故事结局
# 布局参数照抄《信件界面-单行关卡布局参数-Godot实现》:
#   双行 = CanvasPlay(左右列 + 中缝跨行拖放区 + 立绘/评级位 + 右缘按钮组);
#   单行 = CanvasLetter2(标题 + 标题线 + 单列字条区, 块宽 540)。
extends Control

const DropShadow := preload("res://scenes/arrange/drop_shadow.gd")
const SNAP_RADIUS := preload("res://scenes/arrange/drop_column.gd").SNAP_MARGIN
var _invalid_shadow: Control
@onready var entrance := preload("res://scenes/arrange/entrance_animation.gd").new()

const StripView := preload("res://scenes/arrange/strip_view.gd")

const REF := Vector2(1920, 1080)

# 双行列参数(双列模板, 见 templates/双列交换纸条模板.tscn):
#   两列各宽 550, 分别位于视图中心(960)两侧 50px: L 右缘 910, R 左缘 1010
const COL_LAYOUT := {
	"L": {"x": 360.0, "w": 550.0},
	"R": {"x": 1010.0, "w": 550.0},
}
# 单行(参照 assets/example/单人交换纸条.png 实测): 立绘在左, 字条列 x=634 宽 992, 无标题
# 三人结算章：参考白底画面的中心点，L / M / R 分别独立定位。
const TRIPLE_RANK_CENTERS := {"L": Vector2(130, 350), "M": Vector2(955, 455), "R": Vector2(1760, 500)}
const SINGLE_X := 634.0
const SINGLE_W := 992.0
const COL_TOP := 85.0

# 字体(HYRunYuan)与字号
const LETTER_FONT := preload("res://assets/fonts/HYRunYuan-45J.ttf")
const FONT_SIZE := 32
const LINE_H := 36.0         # 行高 28×1.2
const BLOCK_MIN_H := 56.0     # 句子块最小高度
const BOARD_BOTTOM := 240.0   # 画布底部留白(滚动空间)

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
var _deciding: bool:
	get: return GameState.session.phase == GameState.Session.Phase.DECIDING
	set(value):
		GameState.session.phase = GameState.Session.Phase.DECIDING if value else GameState.Session.Phase.ARRANGING

# 各行条件句块(白色字条下方最后一块)上的倒计时色彩条, 与旋转时钟同帧启动
var _cd_bars: Array = []

@onready var board: Control = $BoardScroll/Board
@onready var left_column: VBoxContainer = $BoardScroll/Board/LeftColumn
@onready var middle_column: VBoxContainer = $BoardScroll/Board/MiddleColumn
@onready var m_anim_slot: Control = $EnvelopeLayer/MAnimSlot
var triple_background: Control

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
	add_child(entrance)
	decide_btn.pressed.connect(_on_execute_pressed)
	reset_btn.pressed.connect(_on_reset_pressed)
	retry_btn.pressed.connect(_on_retry_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	_load_level()
	# 每次从地图进入都滑入；判定演出结束回到结算态则留在原位。
	# 原始状态和再试一次只重建内容，不调用人物入场。
	if level != null and level.rows.size() in [1, 2] and (not locked or GameFlow.previous_scene == "map"):
		CharacterAnim.slide_in(l_anim_slot)
		if not single_row:
			CharacterAnim.slide_in(r_anim_slot, true)

# 「原始状态」: 字条恢复最初的排布顺序(清除本关排列快照后重建)
func _on_reset_pressed() -> void:
	if _deciding or locked:
		return
	GameState.reset_arrangement()
	_apply_level()

# 「返回」: 回主界面(选关地图)
func _on_back_pressed() -> void:
	if _deciding:
		return
	GameFlow.goto("map")

# 「再试一次」(锁定态): 解除锁定, 回到可拖拽的交换纸条画面(保留当前排列)
func _on_retry_pressed() -> void:
	if _deciding:
		return
	GameState.retry_arrangement()
	_build_layout()
	_apply_level()

# —— 关卡加载:LevelData → 界面 ——

func _load_level() -> void:
	level = LevelData.load_level(GameState.current_level_id)
	if not level.supports_layout():
		result_label.text = "关卡行数配置有误；目前支持一至三人关卡。"
		decide_btn.disabled = true
		reset_btn.disabled = true
		retry_btn.disabled = true
		return
	_build_layout()
	_apply_level()

# 布局分支(参照双人/单人交换纸条截图): 单行 = 全屏底图 + 单列; 双行 = 光柱底 + 双列
func _build_layout() -> void:
	single_row = level.row_count == 1
	right_column.visible = not single_row
	_set_visible(r_figure, not single_row)
	# 剪影动画绑定: 左槽=第一行, 右槽=第二行(单行关右槽隐藏)
	if level.rows.size() > 0:
		_setup_row_anim(l_anim_slot, level.row_by_id("L") if level.rows.size() == 3 else level.rows[0])
		if level.rows.size() > 1 and not single_row:
			_setup_row_anim(r_anim_slot, level.row_by_id("R") if level.rows.size() == 3 else level.rows[1])
		else:
			CharacterAnim.setup(r_anim_slot, "")
	else:
		CharacterAnim.setup(l_anim_slot, "")
		CharacterAnim.setup(r_anim_slot, "")
	if level.rows.size() == 3:
		_setup_row_anim(m_anim_slot, level.row_by_id("M"))
	else:
		CharacterAnim.setup(m_anim_slot, "")
	_configure_columns()

# 槽位绑定行的动画: 关卡 JSON 行级 anim 直接配优先, 缺省按人物 characters.json 的 anim
func _setup_row_anim(slot: Control, row: LevelData.Row) -> void:
	if row.anim != "":
		CharacterAnim.setup_path(slot, row.anim)
	else:
		CharacterAnim.setup(slot, String(row.character))

# 背景与栏目布局只配置一次，不夹在每个人物的动画绑定里重复执行。
func _configure_columns() -> void:
	middle_column.visible = level.rows.size() == 3
	if triple_background:
		triple_background.visible = middle_column.visible
	if level.rows.size() == 3:
		_configure_triple()
		return
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
	return 480.0 if level.rows.size() == 3 else (SINGLE_W if single_row else COL_LAYOUT["L"].w)

func _apply_level() -> void:
	if level == null or level.rows.is_empty():
		push_error("关卡数据为空: %s" % GameState.current_level_id)
		return
	# 判定状态先算好(锁定 + Rank 标签): 锁定态下字条黑底白字、不可拖拽
	_restore_verdict_label()
	_cd_bars.clear()
	var characters: Dictionary = LevelData.load_characters()
	# 本关有保存的排列快照(执行过、从阅览信件跳回)则按快照还原字条位置
	var restore := GameState.sequences_level == level.level_id and level.is_valid_arrangement(GameState.sequences)
	# 最新判定若 REPLACE 过某些句子(触发过阅览重放), 这些句子的显示文本换成条件句正文
	# 行 ↔ 栏:第 i 行对应第 i 栏(单行关卡只有左栏有内容)
	var columns: Array[VBoxContainer] = _columns()
	for i in mini(level.rows.size(), columns.size()):
		var row: LevelData.Row = level.rows[i]
		var column := columns[i]
		var changes := level.change_maps(level.changes_for(GameState.verdicts, row.id))
		var replace_map: Dictionary = changes.replace
		var remove_ids: Dictionary = changes.remove
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
			if remove_ids.has(id):
				continue
			if _is_block_of(row, id):
				if top_block == "":
					top_block = id
				last_block = id
		for sid in seq:
			var id := String(sid)
			if remove_ids.has(id):
				continue
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
	clear_drop_preview()
	entrance.play(_columns())

# 画布高度 = 最高一栏的内容高度 + 底部留白; 不足一屏保持一屏
func _fit_board_height() -> void:
	var max_h := 0.0
	for col: VBoxContainer in _columns():
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
	var summaries: Array[String] = []
	for i in level.rows.size():
		var row_id := level.rows[i].id
		var item: Dictionary = verdict.get("rows", {}).get(row_id, verdict if not level.has_row_endings() else {})
		var rank := String(item.get("rank", ""))
		summaries.append("%s：%s %s" % [row_id, item.get("ending_id", "未判定"), rank])
		var tag := rank_tags[i]
		var path := "res://assets/RANK/ranktag%s.png" % rank
		tag.visible = not rank.is_empty() and ResourceLoader.exists(path)
		if tag.visible:
			tag.texture = load(path)
			if level.rows.size() == 3:
				tag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tag.size = Vector2(360, 160)
				tag.pivot_offset = tag.size * 0.5
				tag.position = TRIPLE_RANK_CENTERS[row_id] - tag.pivot_offset
				tag.rotation_degrees = -12.0
				tag.z_index = 1
	result_label.text = "  |  ".join(summaries) + "  本次声望 +%d" % int(verdict.get("awarded_rep", 0))

# 场景载入时恢复上次的判定结果显示(不是本关的判定则清空);
# 本关判定过 = 锁定态: 白底 + 字条不可拖拽 + 右侧只剩「再试一次」「返回」+ 每栏 Rank 标签
func _restore_verdict_label() -> void:
	var verdict: Dictionary = GameState.verdicts
	locked = String(verdict.get("level_id", "")) == level.level_id
	GameState.session.phase = GameState.Session.Phase.RESULT if locked else GameState.Session.Phase.ARRANGING
	# 锁定态背景换成白色(盖掉双人光柱/单人底图)
	white_bg.visible = locked
	if triple_background:
		triple_background.visible = level.rows.size() == 3 and not locked
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

# 栏目负责放置，StripView 负责外观，Card 负责拖拽。
func _place_strip(column: VBoxContainer, id: String, text: String, color: Color, locked := false, is_condition := false) -> void:
	column.add_child(StripView.build(id, text, color, _col_base_w(), locked, is_condition))

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
	if not can_edit() or level == null or level.rows.is_empty() or level.rows.size() > 3:
		return
	# 正在拖动时不提交，避免把隐藏卡片或预览占位当成最终排列。
	if get_viewport().gui_is_dragging():
		return
	# 1. 冻结这次决定的排列(倒计时期间不再响应「决定」,字条也不会再动)
	var columns: Array[VBoxContainer] = _columns()
	var sequences: Dictionary = {}
	for i in mini(level.rows.size(), columns.size()):
		sequences[level.rows[i].id] = get_sequence_ids(columns[i])
	print("排列: ", sequences)
	GameState.sequences = sequences
	GameState.sequences_level = level.level_id

	# 2. 判定结局
	var verdict := RuleEngine.judge(level, sequences)
	if verdict.is_empty():
		result_label.text = "【未保存】请检查存档路径或磁盘空间" if GameState.last_save_error != OK else "【未命中】请检查每行 conditions 是否有兜底"
		return

	# 3. 首次解锁的新结局: 旋转时钟倒数(素材 assets/clock), 走完才揭晓、切场景;
	#    重复结局(已解锁过): 不转钟, 直接揭晓
	_set_deciding(true)
	decide_btn.disabled = true
	# Bad 评级不进倒计时动画, 直接揭晓(初始排列默认命中 Bad 时尤其如此)
	if RuleEngine.needs_countdown(verdict):
		result_label.text = "（判定中…）"
		# 倒计时演出: 切白底 + 隐藏右侧按钮组 + 旋转时钟与色彩条同帧启动
		white_bg.visible = true
		if triple_background:
			triple_background.visible = false
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
	# 保持输入冻结直到离开场景，避免揭晓与切场景之间又接收一次拖拽。
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
	GameState.begin_review(rows)
	GameFlow.goto("letter")

# 统一输入开关：按钮、卡片和栏目都遵守同一个编辑状态。
func can_edit() -> bool:
	return level != null and level.supports_layout() and not locked and not _deciding and not entrance.playing

func _set_deciding(active: bool) -> void:
	_deciding = active
	for column in _columns():
		column._remove_preview_gap()
		for child in column.get_children():
			if child is Card:
				child.locked = active or locked

# —— 拖放路由：每帧更新，所以鼠标经过背景和非法区域时也有提示 ——
func _process(_delta: float) -> void:
	var viewport := get_viewport()
	var data: Variant = viewport.gui_get_drag_data()
	if can_edit() and viewport.gui_is_dragging() and data is Card:
		_route_preview(data, viewport.get_mouse_position())
	else:
		clear_drop_preview()

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not can_edit() or not data is Card:
		return false
	return _route_preview(data, get_viewport().get_mouse_position())

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Card:
		_route_drop(data, get_viewport().get_mouse_position())

# 先选最近的栏目，扩大范围但不抢另一栏；中缝保留跨行交换行为。
func _target_column(card: Card, mouse: Vector2) -> VBoxContainer:
	if not get_viewport_rect().has_point(mouse):
		return null
	if level.rows.size() == 2:
		var left_edge := left_column.global_position.x + left_column.size.x
		var right_edge := right_column.global_position.x
		if mouse.x >= left_edge and mouse.x <= right_edge:
			return right_column if card.origin_slot == left_column else left_column
	var nearest: VBoxContainer = null
	var distance := INF
	for column in _columns():
		if not column.visible:
			continue
		var rect: Rect2 = column.get_global_rect()
		var dx := maxf(maxf(rect.position.x - mouse.x, mouse.x - rect.end.x), 0)
		if dx <= SNAP_RADIUS and dx < distance:
			distance = dx
			nearest = column
	return nearest

# 返回值同时驱动鼠标可放置状态和阴影颜色，避免“黑色预览却放不下”。
func _route_preview(card: Card, mouse: Vector2) -> bool:
	if not can_edit() or card.locked:
		clear_drop_preview()
		return false
	var column := _target_column(card, mouse)
	for other in _columns():
		if other != column:
			other._remove_preview_gap()
	if column != null:
		var local := column.get_global_transform().affine_inverse() * mouse
		if column.update_preview_gap(card, local):
			_hide_invalid_shadow()
			return true
	_show_invalid_shadow(card, column, mouse)
	return false

func _route_drop(card: Card, mouse: Vector2) -> void:
	if can_edit() and not card.locked:
		var column := _target_column(card, mouse)
		if column != null:
			var local := column.get_global_transform().affine_inverse() * mouse
			if column.receive_drop(card, local):
				return
	card.return_to_origin()

# 非法候选不撑开栏目，红色阴影只是覆盖提示，松手回原位置。
func _show_invalid_shadow(card: Card, column: VBoxContainer, mouse: Vector2) -> void:
	if not is_instance_valid(_invalid_shadow):
		_invalid_shadow = DropShadow.new()
		_invalid_shadow.allowed = false
		_invalid_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_invalid_shadow.z_index = 50
		add_child(_invalid_shadow)
	_invalid_shadow.visible = true
	_invalid_shadow.size = Vector2(column.size.x if column != null else card.size.x, card.size.y)
	var x := column.global_position.x if column != null else mouse.x - card.size.x * 0.5
	var y := clampf(mouse.y - card.size.y * 0.5, 0, maxf(0, get_viewport_rect().size.y - card.size.y))
	_invalid_shadow.global_position = Vector2(x, y)

func _hide_invalid_shadow() -> void:
	if is_instance_valid(_invalid_shadow):
		_invalid_shadow.visible = false

func clear_drop_preview() -> void:
	for column in _columns():
		column._remove_preview_gap()
	_hide_invalid_shadow()


# 返回数据行对应的栏目。三人视觉位置 L / M / R，与 JSON 数组顺序解耦。
func _columns() -> Array[VBoxContainer]:
	if level != null and level.rows.size() == 3 and level.supports_layout():
		var by_id := {"L": left_column, "R": right_column, "M": middle_column}
		var result: Array[VBoxContainer] = []
		for letter in level.rows:
			result.append(by_id[letter.id])
		return result
	return [left_column, right_column]

# 三人布局按参考画面：480 宽、60 横向间距、45 纵向间距。
func _configure_triple() -> void:
	dual_bg.hide()
	single_bg.hide()
	var chars := LevelData.load_characters()
	if not triple_background:
		triple_background = preload("res://scenes/arrange/triple_bg.gd").new()
		add_child(triple_background)
		move_child(triple_background, $EnvelopeLayer.get_index())
	var columns := [left_column, middle_column, right_column]
	var slots := [l_anim_slot, m_anim_slot, r_anim_slot]
	var ids := ["L", "M", "R"]
	var colors: Array[Color] = []
	result_label.position = Vector2(180, 1020)
	result_label.size = Vector2(1350, 50)
	result_label.add_theme_font_size_override("font_size", 22)
	for i in 3:
		var row := level.row_by_id(ids[i])
		var x := 180.0 + i * 540.0
		columns[i].position = Vector2(x, 70)
		columns[i].size.x = 480
		columns[i].add_theme_constant_override("separation", 45)
		slots[i].position = Vector2(x - 100, 28)
		slots[i].scale = Vector2.ONE
		colors.append(_character_color(chars, row.character))
	triple_background.setup(colors)
