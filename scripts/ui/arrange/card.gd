# Card.gd — 可拖拽字条(白色字块 + 右上角角色小色块)
class_name Card
extends PanelContainer

@export var card_id: String = ""
@export var text_content: String = ""

@onready var label: RichTextLabel = find_child("Label", true, false) as RichTextLabel

# 判定结局后回到排布场景: 锁定不可拖拽(黑底白字态)
var locked := false

# 拖拽前的原座位与顺序位置(归位/交换时使用)
var origin_slot: Node = null
var origin_index: int = 0

# 拖拽期间留在原位的灰色占位框
var placeholder: Control = null

# 落座动画的 Tween
var landing_tween: Tween = null

func _ready() -> void:
	update_view()

func setup(id: String, text: String) -> void:
	card_id = id
	text_content = text
	if is_node_ready():
		update_view()

func update_view() -> void:
	if label:
		label.text = text_content

# 1. 当鼠标在字条上按住并拖动时，Godot 自动调用此函数
func _get_drag_data(_at_position: Vector2) -> Variant:
	if locked:
		return null
	# 记住来处
	origin_slot = get_parent()
	origin_index = get_index()

	# 在原位放一个灰色占位框,标记字条原来的位置(松手后消失)
	_show_placeholder()

	# 虚化预览:白色字块 + 左上角同色斜标签,跟随鼠标移动; 唯一效果: 3px 黑色外投影
	var pw := maxf(size.x - 28.0, 40.0)
	var preview_label := Label.new()
	preview_label.text = text_content
	preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_label.add_theme_font_override("font", preload("res://assets/fonts/HYRunYuan-55W.ttf"))
	preview_label.add_theme_font_size_override("font_size", 28)
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_label.custom_minimum_size = Vector2(pw, 0)

	var preview := PanelContainer.new()
	var white := StyleBoxFlat.new()
	white.bg_color = Color.WHITE
	white.content_margin_left = 14.0
	white.content_margin_right = 14.0
	white.content_margin_top = 12.0
	white.content_margin_bottom = 12.0
	white.shadow_color = Color(0, 0, 0, 0.5)
	white.shadow_size = 3
	white.shadow_offset = Vector2(0,0)
	preview.add_theme_stylebox_override("panel", white)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview.add_child(root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(box)
	var tag := find_child("Tag", true, false) as ColorRect
	if tag:
		# 标签投影: 同中心、同旋转、四周各多 3px
		# (锚点落在 position + pivot_offset, 需把中心对齐换算成原点位置)
		var tag_prev_shadow := ColorRect.new()
		tag_prev_shadow.color = Color(0, 0, 0, 0.5)
		tag_prev_shadow.size = tag.size + Vector2(6, 6)
		tag_prev_shadow.pivot_offset = tag_prev_shadow.size * 0.5
		tag_prev_shadow.position = tag.position + tag.pivot_offset - tag_prev_shadow.pivot_offset
		tag_prev_shadow.rotation = tag.rotation
		tag_prev_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tag_prev_shadow)
		var tag_prev := ColorRect.new()
		tag_prev.color = tag.color
		tag_prev.position = tag.position
		tag_prev.size = tag.size
		tag_prev.pivot_offset = tag.pivot_offset
		tag_prev.rotation = tag.rotation
		tag_prev.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tag_prev)
	box.add_child(preview_label)
	# 预览与字条等宽(28 = 预览左右内容边距之和),超长文本同样换行,预览不跑偏
	var text_h := preload("res://assets/fonts/HYRunYuan-55W.ttf").get_multiline_string_size(
		text_content, HORIZONTAL_ALIGNMENT_LEFT, pw, 28).y
	root.custom_minimum_size = Vector2(pw, maxf(56.0, text_h))
	preview.modulate = Color(1, 1, 1, 0.6)
	set_drag_preview(preview)

	# 隐藏自己 → 灰框代替自己占住原位(不移出场景树,字条不会丢)
	visible = false

	# 返回自身，作为拖拽传递的数据
	return self

# 在原座位放一个与字条等高的灰色占位框
func _show_placeholder() -> void:
	if placeholder == null:
		placeholder = PanelContainer.new()
		var gray := StyleBoxFlat.new()
		gray.bg_color = Color(0.6, 0.6, 0.65, 0.15)
		gray.border_color = Color(0.65, 0.65, 0.7, 0.9)
		gray.set_border_width_all(2)
		placeholder.add_theme_stylebox_override("panel", gray)
	placeholder.custom_minimum_size = Vector2(0, size.y)
	if origin_slot and is_instance_valid(origin_slot):
		origin_slot.add_child(placeholder)
		origin_slot.move_child(placeholder, origin_index)

# 移除灰色占位框(松手后调用)
func clear_placeholder() -> void:
	if placeholder:
		placeholder.queue_free()
		placeholder = null

# 落座动画:从放大的虚影回弹到正常大小 + 淡入
func play_landing() -> void:
	if landing_tween and landing_tween.is_valid() and landing_tween.is_running():
		return  # 正在播放,不重复触发
	pivot_offset = size * 0.5
	scale = Vector2(1.12, 1.12)
	modulate.a = 0.6
	landing_tween = create_tween()
	landing_tween.set_parallel(true)
	landing_tween.tween_property(self, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	landing_tween.tween_property(self, "modulate:a", 1.0, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# 2. 归位:恢复显示并移除灰框;若因意外成了孤儿节点,则放回原座位
func return_to_origin() -> void:
	visible = true
	clear_placeholder()
	if not is_inside_tree() and origin_slot and is_instance_valid(origin_slot):
		origin_slot.add_child(self)
		origin_slot.move_child(self, mini(origin_index, origin_slot.get_child_count() - 1))
	play_landing()

# 3. 拖拽结束通知:正常路径之外的兜底
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		return_to_origin()

# 4. 看门狗:万一拖拽结束的所有路径都没触发,只要引擎已不在拖拽状态,
#    就恢复显示,保证字条永远不会"消失"
func _process(_delta: float) -> void:
	if locked:
		return
	if not visible and is_inside_tree():
		var vp := get_viewport()
		if vp and not vp.gui_is_dragging():
			return_to_origin()
