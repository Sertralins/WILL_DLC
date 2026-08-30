# letter_reader.gd — 信件阅览:打字机逐行显示,点击跳过/翻页,读完浮现跳转按钮
extends Control

signal reading_finished # 阅读全部完成时发出的信号

# 信件内容来自当前关卡(rows[GameState.current_row])的初始句子序列, 不再有独立的信件文件
const CHARS_PER_SECOND := 30.0        # 打字机速度(字/秒)

# —— 信纸正文排版(设计稿: 字号 42px / 行距 1.2 倍字号) ——
# 行高 = 42 × 1.2 = 50.4px, 也就是上下两行的字方块之间留 0.2 × 42 = 8.4px 空隙。
# 注意字体在 42px 下的自然高度是 52px(上高 39 + 下深 13), 比行高还大一点点,
# 但中文墨迹只有约 36px, 按字方块算行距才符合设计稿, 也不会裁到字。
const LETTER_FONT := preload("res://assets/fonts/HYRunYuan-55W.ttf")
const FONT_SIZE := 42
const MARKER_FONT_SIZE := 30
const LINE_HEIGHT := FONT_SIZE * 0.8 # = 50.4, 行高(含行距), 同时用于超页检测
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

# 行不用 VBoxContainer 排:容器内部按整数像素布局,承载不了 50.4 这样的小数行高,
# 改成普通 Control + 逐行按 y = 行号 × LINE_HEIGHT 定位(渲染时各行各自吸附到整像素,
# 行距在 50/51 之间交替,平均正好 50.4,文字也不会因半像素而发虚)
@onready var lines_box: Control = $MarginContainer/Lines
@onready var start_button: Button = $StartButton
@onready var background: TextureRect = $Background

func _ready() -> void:
	start_button.visible = false
	start_button.pressed.connect(_on_start_button_pressed)
	_bind_character_background()
	if GameState.review_letter:
		# 重排后阅览: 还有下一行要放 → "继续", 放完 → "查看结算"
		start_button.text = "继续" if GameState.review_queue.size() > 1 else "查看结算"
	else:
		# 普通阅读流程: 读完点屏幕任意处进回顾页 —— 按钮铺满全屏、不显示文字, 点击由它接管
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
		# 跳过顶部固定黑块, 从第二个元素(第一张字条)开始;
		# 并应用结局 CHANGE: REPLACE 换条件句正文, DRA/D 删除该句
		var seq: Array = GameState.sequences.get(row.id, [])
		if seq.size() > 1:
			seq = seq.slice(1)
		raw_pages = level.apply_changes(seq, GameState.verdicts.get("changes", []))
	else:
		for sentence: Dictionary in level.initial_sequence(row):
			raw_pages.append(level.sentence_text(sentence))
	for text in raw_pages:
		_append_pages(String(text))
	if pages.is_empty():
		pages = ["(信件内容缺失)"]

# 超长句子自动拆页: 按空行分段后贪心拼页, 每页不超过 MAX_LINES_PER_PAGE 行
func _append_pages(text: String) -> void:
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

	for i in lines.size():
		var line_text := lines[i]
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

# 全部阅读完毕:收起 ▼; 普通阅读浮现全屏透明按钮(点任意处进回顾页), 重排阅览淡入文字按钮
func _finish_reading() -> void:
	for m in markers:
		m.visible = false
	start_button.visible = true
	if GameState.review_letter:
		start_button.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(start_button, "modulate:a", 1.0, 0.6)
	reading_finished.emit()

# 点击按钮(场景之间不直接互相跳转, 都经 GameFlow):
# 重排后阅览: 弹出队列里已放完的行; 还有下一行就继续重放, 放完进结算场景;
# 普通阅读: 记录本行已读 → 进入回顾页(另一封/回想/返回/开始! 由回顾页接管)
func _on_start_button_pressed() -> void:
	if GameState.review_letter:
		GameState.review_letter = false
		GameState.review_queue.pop_front()
		if GameState.review_queue.is_empty():
			GameFlow.goto("verdict")
			return
		GameState.current_row = String(GameState.review_queue[0])
		GameState.review_letter = true
		GameFlow.goto("letter")
		return
	GameState.mark_row_read(GameState.current_row)
	GameFlow.goto("recap")
