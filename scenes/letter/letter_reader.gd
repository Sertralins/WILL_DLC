# letter_reader.gd — 信件阅览:打字机逐行显示,点击跳过/翻页,读完浮现跳转按钮
extends Control

signal reading_finished # 阅读全部完成时发出的信号

# 信件内容来自当前关卡(rows[GameState.current_row])的初始句子序列, 不再有独立的信件文件
const CHARS_PER_SECOND := 30.0        # 打字机速度(字/秒)
const TITLE_FONT_SIZE := 100        # Panel0 标题字号(可调; 正文 42, 标题为正文的两倍多)

# —— 信纸正文排版(设计稿: 字号 42px / 行距 1.2 倍字号) ——
# 行高 = 42 × 1.2 = 50.4px, 也就是上下两行的字方块之间留 0.2 × 42 = 8.4px 空隙。
# 注意字体在 42px 下的自然高度是 52px(上高 39 + 下深 13), 比行高还大一点点,
# 但中文墨迹只有约 36px, 按字方块算行距才符合设计稿, 也不会裁到字。
const LETTER_FONT := preload("res://assets/fonts/HYRunYuan-55W.ttf")
const TITLE_FONT := preload("res://assets/fonts/KaiTi.ttf")   # 标题字体: 楷体(正楷)
const FONT_SIZE := 42
const MARKER_FONT_SIZE := 30
const LINE_HEIGHT := FONT_SIZE * 1.1  # (含行距), 同时用于超页检测
const PAPER_CONTENT_HEIGHT := 667.0   # 信纸文字区可用高度,超出时告警(现已有自动拆页兜底)
const MAX_LINES_PER_PAGE := 13        # 自动拆页的每页行数上限(667/50.4 ≈ 13.2)

# 加载后的信件数据(按页拆分的数组,内容来自当前关卡的初始句子序列)
var pages: Array = []
var current_page_index: int = 0

# 每行一个 Label + 行尾 ▼ 标记
var line_labels: Array[Label] = []
var markers: Array[Label] = []
var current_line: int = 0
var is_typing: bool = false
var char_progress: float = 0.0

# Panel0(读信专用句)第一行标题: 加大字号 + 下划线, 从文字区左上角左侧平移进入,
# 3 秒后变淡消失; 只在标题所在的页显示
var _title_label: RichTextLabel = null
var _title_page := -1
var _title_base_x := 0.0
var _title_tween: Tween

# 行不用 VBoxContainer 排:容器内部按整数像素布局,承载不了 50.4 这样的小数行高,
# 改成普通 Control + 逐行按 y = 行号 × LINE_HEIGHT 定位(渲染时各行各自吸附到整像素,
# 行距在 50/51 之间交替,平均正好 50.4,文字也不会因半像素而发虚)
@onready var lines_box: Control = $MarginContainer/Lines
@onready var start_button: Button = $StartButton
@onready var background: TextureRect = $Background
@onready var anim_slot: Control = $SilhouetteLayer/AnimSlot

func _ready() -> void:
	start_button.visible = false
	start_button.pressed.connect(_on_start_button_pressed)
	_bind_character_background()
	_bind_character_anim()
	# 读完信点屏幕任意处继续: 按钮铺满全屏、不显示文字, 点击由它接管
	# (普通模式进回顾页; 重排阅览模式进下一行/放完回排布白底锁定态)
	start_button.text = ""
	# 铺满全屏: 4.7 的 set_anchors_preset 无论参数都会保留矩形, 只能直接设 anchors+offsets
	start_button.anchor_left = 0.0
	start_button.anchor_top = 0.0
	start_button.anchor_right = 1.0
	start_button.anchor_bottom = 1.0
	start_button.offset_left = 0.0
	start_button.offset_top = 0.0
	start_button.offset_right = 0.0
	start_button.offset_bottom = 0.0
	for state in ["normal", "hover", "pressed", "focus"]:
		start_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	# 文字区尺寸变化(布局完成/窗口变化)时重排行, 保证按页行数居中
	lines_box.resized.connect(_center_lines)
	_load_letter()
	_show_page(0)

# —— 内容加载 ——
# 背景与人物绑定: 当前行所属角色的 letter_bg(在 characters.json 里配置)铺满全屏
func _bind_character_background() -> void:
	var level := LevelData.load_level(GameState.current_level_id)
	var row := level.row_by_id(GameState.current_row)
	if row == null:
		row = level.first_row()
	if row == null:
		return
	var characters := LevelData.load_characters()
	var path := String(characters.get(String(row.character), {}).get("letter_bg", ""))
	if path != "" and ResourceLoader.exists(path):
		background.texture = load(path)

# 人物剪影动画: 按当前行人物把动画框填进 AnimSlot(该人物无 anim 配置则槽隐藏)
func _bind_character_anim() -> void:
	var level := LevelData.load_level(GameState.current_level_id)
	var row := level.row_by_id(GameState.current_row)
	if row == null:
		row = level.first_row()
	if row == null:
		anim_slot.visible = false
		return
	# 行动画: 关卡 JSON 行级 anim 直接配优先, 缺省按人物 characters.json 的 anim
	if row.anim != "":
		CharacterAnim.setup_path(anim_slot, row.anim)
	else:
		CharacterAnim.setup(anim_slot, String(row.character))
# 普通模式: 信件 = 当前行(GameState.current_row)的初始句子序列(首固定块 → 字条 → 其余固定块);
# 重排后阅览模式(review_letter): 信件 = 该行当前的排列序列, 从第二个元素(第一张字条)开始逐句展示(顶部固定黑块是开场框架, 不重放)
func _load_letter() -> void:
	pages = []
	var level := LevelData.load_level(GameState.current_level_id)
	var row := level.row_by_id(GameState.current_row)
	if row == null:
		row = level.first_row()
	if row == null:
		push_error("关卡 %s 没有任何行, 无法阅览信件" % GameState.current_level_id)
		pages = ["(信件内容缺失)"]
		return
	var raw_pages: Array = []
	if GameState.review_letter:
		# 重排阅览: 字条一律跳过(只出现固定块与条件句正文);
		# 序列去掉顶部固定黑块, 再应用结局 CHANGE: REPLACE 换条件句正文, DRA/D 删除该句
		var strip_ids := {}
		for r in level.rows:
			for s in r.strips:
				strip_ids[String(s.get("id", ""))] = true
		var seq: Array = GameState.sequences.get(row.id, [])
		var filtered: Array = []
		for id in seq:
			if not strip_ids.has(String(id)):
				filtered.append(String(id))
		if filtered.size() > 1:
			filtered = filtered.slice(1)
		raw_pages = level.apply_changes(filtered, GameState.verdicts.get("changes", []))
	else:
		# 首次阅读标题(只普通模式有, 重排阅览无):
		# 行级 title_block 模块优先(text/text_key, 标题在首页演出);
		# 缺省回退到第一句 Panel0 的第一行(在其所在的页演出)
		var title_text := level.sentence_text(row.title_block)
		if title_text != "":
			_title_page = 0
			_build_title(title_text)
		elif row.readonly.size() > 0:
			var first_line := String(level.sentence_text(row.readonly[0])).split("\n")[0]
			if first_line != "":
				_title_page = pages.size()
				_build_title(first_line)
		# 首次阅读隐藏字条的字(字条只在交换纸条界面与重排阅览里出现)
		var strip_ids := {}
		for s in row.strips:
			strip_ids[String(s.get("id", ""))] = true
		for sentence: Dictionary in level.initial_sequence(row):
			if strip_ids.has(String(sentence.get("id", ""))):
				continue
			raw_pages.append(level.sentence_text(sentence))
	# 整封信连续排页(不再一句一页): 短句(字条等)自然合并到同一页,
	# [page] 仍强制换页, 超页按空行分段贪心拼页
	_append_pages("\n".join(raw_pages))
	if pages.is_empty():
		pages = ["(信件内容缺失)"]

# 句子文本拆页: [page](已换算成 \f)强制换页, 优先按换页标记切分;
# 无标记的超长句子再按空行分段贪心拼页(每页不超过 MAX_LINES_PER_PAGE 行)
func _append_pages(text: String) -> void:
	for chunk in String(text).split("\f"):
		_append_page_chunk(chunk)

func _append_page_chunk(text: String) -> void:
	if text == "":
		return
	if text.split("\n").size() <= MAX_LINES_PER_PAGE:
		pages.append(text)
		return
	var paragraphs: Array = []
	var current := ""
	for line in text.split("\n"):
		if line == "":
			if current != "":
				paragraphs.append(current.strip_edges())
				current = ""
			continue
		current += line + "\n"
	if current != "":
		paragraphs.append(current.strip_edges())
	var page := ""
	for p in paragraphs:
		var para: String = String(p)
		var candidate: String = para if page == "" else page + "\n\n" + para
		if candidate.split("\n").size() <= MAX_LINES_PER_PAGE or page == "":
			page = candidate
		else:
			pages.append(page)
			page = para
	if page != "":
		pages.append(page)

# 显示指定页:清空上一页,渲染每行(不自动打字,等待点击)
func _show_page(page_idx: int) -> void:
	current_page_index = page_idx
	for child in lines_box.get_children():
		child.queue_free()
	line_labels.clear()
	markers.clear()
	current_line = 0
	is_typing = false
	char_progress = 0.0

	var page_text := String(pages[page_idx])
	var lines := page_text.split("\n")
	# 超页检测:按行高估算,超出信纸文字区时告警(可在 JSON 里拆更多页)
	if lines.size() * LINE_HEIGHT > PAPER_CONTENT_HEIGHT:
		push_warning("信件第 %d 页内容可能超出信纸(约 %d 行)" % [page_idx + 1, lines.size()])
	# 可复用右对齐标签: 行内的 [right] 标记(RIGHT_MARK)让该行右对齐(如落款)
	# Panel0 标题: 只在标题所在的页播放, 其余页隐藏
	if _title_label != null:
		if page_idx == _title_page:
			_play_title()
		else:
			_title_label.visible = false

	for i in lines.size():
		var line_text := lines[i]
		# [right] 可复用右对齐标签(如落款): 该行右对齐, 标记本身不显示
		var right_aligned := line_text.contains(LevelData.RIGHT_MARK)
		if right_aligned:
			line_text = line_text.replace(LevelData.RIGHT_MARK, "")
		# 每行: [文字(撑满)] [▼(该行完成时显示)],按行号定位,行高固定 = LINE_HEIGHT
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_preset(Control.PRESET_TOP_WIDE)  # 横向撑满文字区
		row.offset_top = i * LINE_HEIGHT
		row.offset_bottom = row.offset_top + LINE_HEIGHT
		row.add_theme_constant_override("separation", 6)
		lines_box.add_child(row)
		var label := Label.new()
		label.text = line_text
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER  # 行高大于字高,文字居中 → 上下留白均分
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right_aligned else HORIZONTAL_ALIGNMENT_LEFT
		label.visible_characters = 0
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_override("font", LETTER_FONT)
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.add_theme_color_override("font_color", Color(0.816, 0.871, 0.91))  # 参考图文字色 RGB(208,222,232)
		row.add_child(label)
		var marker := Label.new()
		marker.text = "▼"
		marker.visible = false
		marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.add_theme_font_override("font", LETTER_FONT)
		marker.add_theme_font_size_override("font_size", MARKER_FONT_SIZE)
		marker.add_theme_color_override("font_color", Color(0.65, 0.72, 0.78))
		row.add_child(marker)
		line_labels.append(label)
		markers.append(marker)
	# 按本页行数把整块文字行垂直居中: 等布局完成后把行块分布在横着的中线两侧
	call_deferred("_center_lines")

# 标题行: Panel0 第一行, 加大字号 + 下划线, 从文字区左上角的左侧平移进入, 3 秒后变淡消失
func _build_title(text: String) -> void:
	_title_label = RichTextLabel.new()
	_title_label.name = "Title"
	_title_label.text = "[u]%s[/u]" % text
	_title_label.bbcode_enabled = true
	_title_label.scroll_active = false
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 显式给足画布(实测 fit_content 会把宽度塌缩到 1px, 文字完全画不出来)
	_title_label.size = Vector2(900.0, TITLE_FONT_SIZE * 1.3)
	_title_label.add_theme_font_override("normal_font", TITLE_FONT)
	_title_label.add_theme_font_size_override("normal_font_size", TITLE_FONT_SIZE)
	_title_label.add_theme_color_override("default_color", Color(0.816, 0.871, 0.91))
	_title_label.visible = false
	add_child(_title_label)
	_title_base_x = ($MarginContainer as Control).position.x

func _play_title() -> void:
	if _title_label == null:
		return
	if _title_tween and _title_tween.is_valid():
		_title_tween.kill()
	_title_label.visible = true
	_title_label.modulate.a = 1.0
	var mc: Control = $MarginContainer
	_title_label.position = Vector2(_title_base_x - 460.0, mc.position.y)
	# 快进缓出: 入场快(0.25s), 退场慢(1.2s 淡出)
	_title_tween = create_tween()
	_title_tween.tween_property(_title_label, "position:x", _title_base_x, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_title_tween.tween_interval(3.0)
	_title_tween.tween_property(_title_label, "modulate:a", 0.0, 1.2)
	_title_tween.tween_callback(func() -> void: _title_label.visible = false)

# 文字行垂直居中: 行块总高 = 行数 × LINE_HEIGHT, 上下留白均分(中线两侧分布);
# 行块超出文字区时贴顶(留白最小 0)。页面切换与文字区尺寸变化都会重排
func _center_lines() -> void:
	var total_h := line_labels.size() * LINE_HEIGHT
	var off := maxf((lines_box.size.y - total_h) / 2.0, 0.0)
	var i := 0
	for child in lines_box.get_children():
		var row := child as Control
		if row == null or row.is_queued_for_deletion():
			continue   # 翻页时旧行还在释放队列里, 不参与排版
		row.offset_top = off + i * LINE_HEIGHT
		row.offset_bottom = row.offset_top + LINE_HEIGHT
		i += 1

# 处理鼠标左键点击(文字区所有子节点都设了 IGNORE,点击会落到本节点)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if start_button.visible:
			return  # 跳转按钮已浮现,点击交给按钮
		_handle_click()

func _handle_click() -> void:
	# 1. 正在打字 → 立即显示整行
	if is_typing:
		_finish_line(current_line)
		return
	# 1.5 先跳过空行(段落分隔与 [page] 行尾 [br] 产生的空行都不消耗点击)
	while current_line < line_labels.size() and line_labels[current_line].text == "":
		_finish_line(current_line)
	# 2. 本页还有未显示的行 → 显示下一行
	if current_line < line_labels.size():
		_start_next_line()
		return
	# 3. 本页全部显示完毕 → 清空翻页
	if current_page_index < pages.size() - 1:
		_show_page(current_page_index + 1)
		_start_next_line()
	else:
		_finish_reading()

# —— 打字机 ——

func _process(delta: float) -> void:
	if not is_typing or current_line >= line_labels.size():
		return
	var label := line_labels[current_line]
	var total := label.text.length()
	char_progress += CHARS_PER_SECOND * delta
	label.visible_characters = mini(total, int(char_progress))
	if label.visible_characters >= total:
		_finish_line(current_line)

# 行文本显示完:行尾出现 ▼(意味着可以点击继续剧情)
func _finish_line(i: int) -> void:
	line_labels[i].visible_characters = -1
	markers[i].visible = line_labels[i].text != ""  # 空行不显示 ▼
	is_typing = false
	char_progress = 0.0
	if i == current_line:
		current_line += 1

# 开始下一行的打字(空行直接跳过)
func _start_next_line() -> void:
	while current_line < line_labels.size() and line_labels[current_line].text == "":
		_finish_line(current_line)
	if current_line >= line_labels.size():
		is_typing = false
		return
	# 打字时没有符号:收起上一行的 ▼
	for m in markers:
		m.visible = false
	is_typing = true
	char_progress = 0.0

# 全部阅读完毕:收起 ▼; 铺全屏无字按钮, 点击任意处继续
# (普通模式进回顾页; 重排阅览模式进下一行/放完回排布白底锁定态)
func _finish_reading() -> void:
	for m in markers:
		m.visible = false
	start_button.visible = true
	reading_finished.emit()

# 点击按钮(场景之间不直接互相跳转, 都经 GameFlow):
# 重排后阅览: 弹出队列里已放完的行; 还有下一行就继续重放, 放完回排布白底锁定态(结算展示);
# 普通阅读: 记录本行已读 → 进入回顾页(另一封/回想/返回/开始! 由回顾页接管)
func _on_start_button_pressed() -> void:
	if GameState.review_letter:
		GameState.review_letter = false
		GameState.review_queue.pop_front()
		if GameState.review_queue.is_empty():
			GameFlow.goto("arrange")
			return
		GameState.current_row = String(GameState.review_queue[0])
		GameState.review_letter = true
		GameFlow.goto("letter")
		return
	GameState.mark_row_read(GameState.current_row)
	GameFlow.goto("recap")
