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

# 是否正被拿起：只清理当前拖动的卡片，不让其他卡片一起播放归位动画。
var drag_active := false
var entrance_active := false  # 入场完成后才允许悬停和拿起。

# 落座动画的 Tween
var landing_tween: Tween = null

# 悬停只改变白纸底色；每张纸使用独立样式，避免影响其他纸条。
const HOVER_PAPER_COLOR := Color(0.88, 0.88, 0.88, 1)
var paper_style: StyleBoxFlat
var normal_paper_color := Color.WHITE

func _ready() -> void:
	update_view()
	paper_style = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	normal_paper_color = paper_style.bg_color
	add_theme_stylebox_override("panel", paper_style)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_mouse_entered() -> void:
	if not locked and not entrance_active and not drag_active and not get_viewport().gui_is_dragging():
		if normal_paper_color.is_equal_approx(Color.WHITE):
			paper_style.bg_color = HOVER_PAPER_COLOR

func _on_mouse_exited() -> void:
	paper_style.bg_color = normal_paper_color

func setup(id: String, text: String) -> void:
	card_id = id
	text_content = text
	if is_node_ready():
		update_view()

func update_view() -> void:
	if label:
		label.text = text_content

# 1. 当鼠标在字条上按住并拖动时，Godot 自动调用此函数
func _get_drag_data(at_position: Vector2) -> Variant:
	if locked or entrance_active:
		return null
	# 记住来处
	origin_slot = get_parent()
	origin_index = get_index()

	_on_mouse_exited()  # 拿起前清除悬停色，避免松手后残留。
	drag_active = true
	var preview := build_drag_preview(at_position)
	set_drag_preview(preview)
	visible = false
	return self

# 拿起的纸张保持实色，稍微变暗并倾斜；鼠标仍抓住原来的位置。
func build_drag_preview(grab_position: Vector2) -> Control:
	var preview := PanelContainer.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 复制原纸条的样式和内容树，保留 RichTextLabel 的换行、边距和垂直居中。
	# 不复制 Card 本身，避免预览也执行拖拽脚本或连接原卡片的信号。
	var preview_style := get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	preview_style.bg_color = Color(0.78, 0.78, 0.78, 1)
	preview_style.anti_aliasing = true
	preview_style.anti_aliasing_size = 1.5
	preview_style.set_corner_radius_all(1)
	preview.add_theme_stylebox_override("panel", preview_style)
	for child in get_children():
		if child is Control:
			preview.add_child(child.duplicate(0))
	preview.custom_minimum_size = custom_minimum_size
	preview.size = size
	# 围绕鼠标抓住的位置旋转，文字和纸面使用同一个变换。
	preview.pivot_offset = grab_position
	preview.position = -grab_position
	preview.rotation_degrees = -3.0
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(preview)
	return holder

# 拖拽结束后由主界面清理落点阴影；不再创建原位置占位框。
func clear_drop_preview() -> void:
	var scene := get_tree().current_scene
	if scene and scene.has_method("clear_drop_preview"):
		scene.clear_drop_preview()

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

# 2. 无效放置时原卡片仍在原栏，只需恢复显示；意外脱离树时补回。
func return_to_origin() -> void:
	visible = true
	drag_active = false
	clear_drop_preview()
	if not is_inside_tree() and origin_slot and is_instance_valid(origin_slot):
		origin_slot.add_child(self)
		origin_slot.move_child(self, mini(origin_index, origin_slot.get_child_count() - 1))
	play_landing()

# 3. 拖拽结束通知:正常路径之外的兜底
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and drag_active:
		return_to_origin()

# 4. 看门狗:万一拖拽结束的所有路径都没触发,只要引擎已不在拖拽状态,
#    就恢复显示,保证字条永远不会"消失"
func _process(_delta: float) -> void:
	if locked:
		return
	if drag_active and not visible and is_inside_tree():
		var vp := get_viewport()
		if vp and not vp.gui_is_dragging():
			return_to_origin()
