# recap.gd — 信件回顾页: 读完信点屏幕进入, 可上下滚动阅览该信全部内容
#
# 布局照抄《信件总结页-滚动回顾界面-Godot实现》:
#   内容区 x∈[163,1898](给右侧按钮列让位), 行边距 70, 行高 130, 字号 42;
#   滚轮灵敏度 100 + 鼠标左键拖拽 + 惯性滑行(×0.74/秒) + 越界回弹(0.15s)。
#
# 静态 UI(Shade/Bg/LetterScroll/DragCatcher/右侧四个按钮及其文字贴图)都在场景文件里,
# 可直接在 2D 编辑器里调整; 代码只负责动态部分:
#   按角色加载 letter_bg、生成信件正文行、按流程切换按钮显隐与跳转。
#
# 按钮(右缘锚, 从上到下, 位置在场景文件里改):
#   「开始!」进入排布场景开始本关(条件显示, 见 _show_start);
#   「另一封」跳到本关按行序的下一行(循环, 单行关卡隐藏);
#   「回想」重新读这封信(回读信场景);
#   「返回」回选关地图。
extends Control

const LETTER_FONT := preload("res://assets/fonts/HYRunYuan-55W.ttf")

const MARGIN_X := 70.0             # 回顾页行边距(读信页是 200, 此处不同)
const FONT_SIZE := 42
const LINE_H := FONT_SIZE * 1.2    # 行高(1.2 倍字号, 与文档行距一致; 太疏读着累)
const LINE_W := 1595.0             # 行宽 = 内容区 1735 - 140(文档实测值)
const WHEEL_STEP := 100.0          # 回顾页滚轮灵敏度(实测值; 读信页为 116)

@onready var bg: TextureRect = $Bg
@onready var scroll: ScrollContainer = $LetterScroll
@onready var drag: Control = $DragCatcher
@onready var start_btn: TextureButton = $EdgeButtons/StartButton
@onready var other_btn: TextureButton = $EdgeButtons/OtherButton
@onready var recall_btn: TextureButton = $EdgeButtons/RecallButton
@onready var back_btn: TextureButton = $EdgeButtons/BackButton

var level: LevelData
var row: LevelData.Row

var _vel := 0.0
var _dragging := false
var _drag_from := Vector2.ZERO

func _ready() -> void:
	level = LevelData.load_level(GameState.current_level_id)
	row = level.row_by_id(GameState.current_row)
	if row == null:
		row = level.first_row()
	if row == null:
		push_error("recap: 关卡 %s 没有任何行, 无法回顾" % GameState.current_level_id)
		GameFlow.goto("map")
		return
	_bind_background()
	_build_letter()
	start_btn.pressed.connect(func(): GameFlow.goto("arrange"))
	other_btn.pressed.connect(_on_other_letter)
	recall_btn.pressed.connect(func(): GameFlow.goto("letter"))
	back_btn.pressed.connect(func(): GameFlow.goto("map"))
	start_btn.visible = _show_start()
	other_btn.visible = level.rows.size() > 1
	drag.gui_input.connect(_on_drag_input)

# —— 背景: 当前行角色的 letter_bg 全屏渐入(进入回顾页的过渡) ——
func _bind_background() -> void:
	var characters := LevelData.load_characters()
	var path := String(characters.get(String(row.character), {}).get("letter_bg", ""))
	if path != "" and ResourceLoader.exists(path):
		bg.texture = load(path)
	bg.modulate.a = 0.0
	create_tween().tween_property(bg, "modulate:a", 1.0, 0.5)

# —— 信件全文滚动区: 每行一个 Label(正文是动态内容, 不进场景文件) ——
func _build_letter() -> void:
	# 边距用 MarginContainer 承载: ScrollContainer 会把直接子节点定位回 (0,0), 直接设 position 无效
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(MARGIN_X))
	margin.add_theme_constant_override("margin_top", 25)
	margin.add_theme_constant_override("margin_right", int(MARGIN_X))
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)
	for line_text in _full_letter_text().split("\n"):
		var l := Label.new()
		l.text = line_text
		l.custom_minimum_size = Vector2(LINE_W, LINE_H)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER   # 行高 130 大于字高, 文字居中(与读信页一致)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_override("font", LETTER_FONT)
		l.add_theme_font_size_override("font_size", FONT_SIZE)
		l.add_theme_color_override("font_color", Color(0.816, 0.871, 0.91))  # 与读信页文字色一致
		box.add_child(l)

# 信件全文 = 当前行的初始句序(与读信页同一来源, 不应用结局 CHANGE)
func _full_letter_text() -> String:
	var parts: Array = []
	for sentence: Dictionary in level.initial_sequence(row):
		parts.append(level.sentence_text(sentence))
	return "\n".join(parts) if parts.size() > 0 else "（信件内容缺失）"

# 「开始!」显示条件: 非(首次进入该关卡 且 阅览的是第一封信);
# 单行关卡例外: 唯一的一封信读完即可开始, 否则永远进不了排布。
func _show_start() -> bool:
	if level.rows.size() == 1:
		return true
	var is_first_row: bool = row.id == String(level.rows[0].id)
	return not (GameState.first_entry_level and is_first_row)

# 「另一封」: 按行序跳到本关下一行(循环)
func _on_other_letter() -> void:
	var idx := 0
	for i in level.rows.size():
		if level.rows[i].id == row.id:
			idx = i
			break
	GameState.current_row = String(level.rows[(idx + 1) % level.rows.size()].id)
	GameFlow.goto("letter")

# ---------- 滚轮 + 拖拽 + 惯性 + 回弹(复刻 ScrollRect 手感, 文档 §4.2) ----------
# 方向约定:
#   滚轮向上/向下 = 视口向信首/信尾走(页面反向, 与桌面习惯一致);
#   鼠标拖拽 = 页面跟随指针(抓着纸拖: 向上拖页面向上走, 即朝信尾看)。

func _on_drag_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		match ev.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if ev.pressed:
					_vel = 0.0
					var dir := 1.0 if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0
					scroll.scroll_vertical += int(dir * WHEEL_STEP)   # 灵敏度 100
					_snap_back()
			MOUSE_BUTTON_LEFT:
				if ev.pressed:
					_dragging = true
					_vel = 0.0
					_drag_from = ev.position
				else:
					_dragging = false
					_snap_back()                     # Elastic 回弹
	elif ev is InputEventMouseMotion and _dragging:
		var dy: float = ev.position.y - _drag_from.y   # ev 静态类型是 InputEvent, 显式标注避免推断
		scroll.scroll_vertical -= int(dy)           # 页面跟随指针
		_vel = -dy * 40.0
		_drag_from = ev.position

func _process(delta: float) -> void:
	if not _dragging and absf(_vel) > 0.5:
		scroll.scroll_vertical += int(_vel * delta)
		_vel *= exp(-0.30 * delta)                   # decel 0.005/帧 ≈ ×0.74/秒
	elif not _dragging:
		_vel = 0.0

func _snap_back() -> void:
	var max_v: float = maxf(0.0, scroll.get_v_scroll_bar().max_value - scroll.size.y)
	var target := int(clampf(scroll.scroll_vertical, 0, max_v))
	if target != scroll.scroll_vertical:
		_vel = 0.0
		create_tween()\
			.tween_property(scroll, "scroll_vertical", target, 0.15)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
