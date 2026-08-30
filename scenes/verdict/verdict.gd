# verdict.gd — 结算场景: 结局评级标签 + 声望结算 + 本关已解锁结局
# 流程: 排布执行 → 新结局重放(letter review) → 本场景 → 返回排布(排列/替换文本保留)
# UI 全部代码构建, 场景文件只有根节点(与 arrange 场景"内容数据化"同思路)
extends Control

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var verdict: Dictionary = GameState.verdicts
	var level := LevelData.load_level(GameState.current_level_id)

	# 背景图(与排布场景一致) + 半透明遮罩
	var bg := TextureRect.new()
	bg.texture = load("res://assets/example/Gemini_Generated_Image_ifnvizifnvizifnv.jpg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.08, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	# 居中面板
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.14, 0.94)
	style.border_color = Color(0.5, 0.4, 0.6, 1)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 56.0
	style.content_margin_top = 36.0
	style.content_margin_right = 56.0
	style.content_margin_bottom = 36.0
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	# 1. 评级标签(S/A/B/C/D/E/Bad 各自配色)
	var rank := String(verdict.get("rank", "?"))
	var rank_label := Label.new()
	rank_label.text = rank
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.add_theme_font_size_override("font_size", 88)
	rank_label.add_theme_color_override("font_color", _rank_color(rank))
	box.add_child(rank_label)

	# 2. 关卡与结局
	var title_label := Label.new()
	title_label.text = "%s · 结局 %s" % [level.title, String(verdict.get("ending_id", "?"))]
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.add_theme_color_override("font_color", Color(0.93, 0.93, 1, 1))
	box.add_child(title_label)

	# 3. 声望结算
	var rep_label := Label.new()
	rep_label.text = "声望 +%d　（累计 %d）" % [int(verdict.get("rep", 0)), GameState.total_rep]
	rep_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rep_label.add_theme_font_size_override("font_size", 24)
	rep_label.add_theme_color_override("font_color", Color(1, 0.95, 0.8, 1))
	box.add_child(rep_label)

	# 4. 本关已解锁结局
	var endings_label := Label.new()
	var unlocked: Array = GameState.history.get(level.level_id, [])
	endings_label.text = "已解锁结局: %s" % (", ".join(unlocked) if unlocked.size() > 0 else "无")
	endings_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	endings_label.add_theme_font_size_override("font_size", 18)
	endings_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.78, 1))
	box.add_child(endings_label)

	# 5. 返回按钮
	var back_btn := Button.new()
	back_btn.text = "返回排布"
	back_btn.custom_minimum_size = Vector2(0, 44)
	back_btn.add_theme_font_size_override("font_size", 20)
	back_btn.pressed.connect(_on_back_pressed)
	box.add_child(back_btn)

	var map_btn := Button.new()
	map_btn.text = "返回信件墙"
	map_btn.custom_minimum_size = Vector2(0, 44)
	map_btn.add_theme_font_size_override("font_size", 20)
	map_btn.pressed.connect(func(): GameFlow.goto("map"))
	box.add_child(map_btn)

# 评级配色(S 金 / A 绿 / B 蓝 / C 紫 / D 橙 / E 灰 / Bad 红)
func _rank_color(rank: String) -> Color:
	match rank:
		"S":
			return Color(1.0, 0.84, 0.25)
		"A":
			return Color(0.45, 0.85, 0.45)
		"B":
			return Color(0.5, 0.7, 1.0)
		"C":
			return Color(0.75, 0.6, 1.0)
		"D":
			return Color(1.0, 0.65, 0.35)
		"E":
			return Color(0.7, 0.7, 0.7)
		"Bad":
			return Color(0.9, 0.35, 0.35)
		_:
			return Color.WHITE

# 返回排布场景(排列、被 REPLACE 的文本、判定结果都已保留)
func _on_back_pressed() -> void:
	GameFlow.goto("arrange")
