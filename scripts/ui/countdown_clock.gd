# countdown_clock.gd — 「决定」之后的倒计时旋转时钟(跨场景共享 UI 组件)
#
# 倒计时的读秒靠两样东西: 指针每秒转一圈 + 中央数字由大缩小。
# 表盘本身始终完整显示(不做原版那种径向扫除)。
# 指针不另外画, 直接用素材图集左上角那根现成的元件。
#
# 用法(倒计时结束后才继续往下走):
#     await CountdownClock.start(self, 5.0).finished
class_name CountdownClock
extends CanvasLayer

signal finished

# 素材是一张图集: 表盘在下半部, 指针单独躺在左上角
# (sp_clock2 只是同一张图换了外圈配色, 这里不用)
const SHEET := preload("res://assets/clock/sp_clock1.png")

# 表盘实测(图集坐标): 圆心 (426.5, 575.5), 外圈半径约 412。
# 截取区取「以圆心为中心的正方形」——好处有二: 圆心即贴图正中, 摆位不必补偿偏移;
# 且把左上角的指针排除在外(否则它会静止地印在盘面上, 和旋转的那根撞车)。
const FACE_REGION := Rect2(6.5, 155.5, 840.0, 840.0)
const FACE_SIZE := 720.0                # 表盘在屏幕上的边长(正方形)
const SHEET_SCALE := FACE_SIZE / 840.0  # 图集像素 → 屏幕像素

# 指针实测(图集坐标): 细尖朝左、中段一颗菱形装饰、右端是圆形轴头;
# 轴心取圆头中心, 轴心到尖端 329px ≈ 表盘半径的 0.8, 正是表针的比例。
const NEEDLE_REGION := Rect2(19.0, 13.0, 356.0, 115.0)
const NEEDLE_PIVOT := Vector2(348.0, 68.5)
const NEEDLE_BASE_ROTATION := PI / 2.0  # 素材里指针朝左(9 点), 转 90° 才指向 12 点
const NEEDLE_TURNS_PER_SECOND := 1.0    # 一秒转一圈

const SHADE_COLOR := Color(0.03, 0.02, 0.05, 0.3)  # 压暗背景的遮罩(0.66→0.4→0.3, 用户嫌太暗两次调亮)
const FADE_TIME := 0.28
const HOLD_TIME := 0.5  # 数到「1」、指针归位后停这一拍再收场

# 中央数字用另一张图集 sp_clock12.png —— 里面正好是 1~5 五个黑色数字(#272727, 无需染色)。
# 注意 5 在图集里是「躺着」存的(打包时转了 90°), 显示时要顺时针转回来。
const DIGIT_SHEET := preload("res://assets/clock/sp_clock12.png")
const DIGIT_REGIONS := {
	1: Rect2(69.0, 602.0, 118.0, 324.0),
	2: Rect2(2.0, 84.0, 244.0, 330.0),
	3: Rect2(271.0, 602.0, 234.0, 330.0),
	4: Rect2(257.0, 66.0, 253.0, 348.0),
	5: Rect2(602.0, 786.0, 330.0, 218.0),
}
const DIGIT_ROTATED := 5         # 图集里躺着的那个数字
const DIGIT_REF_HEIGHT := 330.0  # 字形设计高度(图集像素): 五个数字共用一个缩放比, 保留字形本身的高矮差
const DIGIT_HEIGHT := 220.0      # 数字静止时在屏幕上的高度
const DIGIT_SCALE := DIGIT_HEIGHT / DIGIT_REF_HEIGHT

# 数字每秒出现时很大, 在这一秒内缩回原大小
const DIGIT_POP_SCALE := 2.8
const DIGIT_SHRINK_TIME := 0.9

# —— 可调参数(由 start() 或实例化后赋值) ——
var duration: float = 5.0     # 倒计时总时长(秒)
var show_number: bool = true  # 表盘中央显示剩余秒数

var _shade: ColorRect
var _face: TextureRect
var _needle: TextureRect
var _digit: TextureRect
var _elapsed: float = 0.0
var _seconds_left: int = -1
var _running: bool = false

# 挂到任意节点上并立即开播; 调用方 await 返回值的 finished 信号即可
static func start(parent: Node, seconds: float = 5.0) -> CountdownClock:
	var clock := CountdownClock.new()
	clock.duration = maxf(seconds, 0.1)
	parent.add_child(clock)
	clock.play()
	return clock

# 界面在 _init 里就搭好: add_child 之后可以立刻 play(),
# 不依赖 _ready 的调用时机(_ready 若被推迟到 play 之后, set_process 会把倒计时关掉)
func _init() -> void:
	layer = 100  # 盖在所有场景 UI 之上
	_build()
	set_process(false)

# —— 界面构建(纯代码, 与 verdict 场景同思路) ——

func _build() -> void:
	# 半透明遮罩: 压暗背景, 同时吃掉所有鼠标事件 —— 倒计时期间字条不可再拖动
	_shade = ColorRect.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color(SHADE_COLOR, 0.0)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)

	# 表盘: 圆心即贴图正中, 所以直接居中摆放
	_face = _make_piece(FACE_REGION)
	_face.anchor_left = 0.5
	_face.anchor_top = 0.5
	_face.anchor_right = 0.5
	_face.anchor_bottom = 0.5
	_face.offset_left = -FACE_SIZE * 0.5
	_face.offset_top = -FACE_SIZE * 0.5
	_face.offset_right = FACE_SIZE * 0.5
	_face.offset_bottom = FACE_SIZE * 0.5
	_face.pivot_offset = Vector2(FACE_SIZE, FACE_SIZE) * 0.5  # 入场缩放绕表盘圆心
	_shade.add_child(_face)

	# 指针: 图集左上角那根, 轴心对准表盘圆心
	_needle = _make_piece(NEEDLE_REGION)
	_needle.size = NEEDLE_REGION.size * SHEET_SCALE
	_needle.pivot_offset = (NEEDLE_PIVOT - NEEDLE_REGION.position) * SHEET_SCALE
	_needle.position = Vector2(FACE_SIZE, FACE_SIZE) * 0.5 - _needle.pivot_offset
	_needle.rotation = NEEDLE_BASE_ROTATION
	_face.add_child(_needle)

	# 剩余秒数: 压在表盘圆心上(排在指针之后添加, 数字不会被指针盖住);
	# 具体贴图与尺寸每秒由 _show_digit() 换
	_digit = TextureRect.new()
	_digit.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_digit.stretch_mode = TextureRect.STRETCH_SCALE
	_digit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.add_child(_digit)

# 从表盘图集里裁出一块, 做成按 SHEET_SCALE 缩放的 TextureRect
func _make_piece(region: Rect2) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = _atlas(SHEET, region)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func _atlas(sheet: Texture2D, region: Rect2) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = sheet
	tex.region = region
	return tex

# 换中央数字: 字形居中压在表盘圆心上(素材只有 1~5, 超出范围就不显示)
func _show_digit(value: int) -> void:
	if not DIGIT_REGIONS.has(value):
		_digit.visible = false
		return
	var region: Rect2 = DIGIT_REGIONS[value]
	_digit.texture = _atlas(DIGIT_SHEET, region)
	_digit.size = region.size * DIGIT_SCALE
	_digit.pivot_offset = _digit.size * 0.5             # 旋转与缩放都绕字形自身中心
	_digit.position = Vector2(FACE_SIZE, FACE_SIZE) * 0.5 - _digit.pivot_offset
	_digit.rotation = PI / 2.0 if value == DIGIT_ROTATED else 0.0
	_digit.visible = true

# —— 播放 ——

func play() -> void:
	if _running:
		return
	_running = true
	_elapsed = 0.0
	_seconds_left = -1
	_needle.rotation = NEEDLE_BASE_ROTATION
	_tick(ceili(duration))
	# 入场: 遮罩淡入 + 表盘从略大回弹
	_face.modulate.a = 0.0
	_face.scale = Vector2(1.14, 1.14)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_shade, "color:a", SHADE_COLOR.a, FADE_TIME)
	tw.tween_property(_face, "modulate:a", 1.0, FADE_TIME)
	tw.tween_property(_face, "scale", Vector2.ONE, FADE_TIME * 1.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	set_process(true)

# 用 _process 而不是 tween 推进: 指针与秒数读同一个 _elapsed, 两者永远对得上
func _process(delta: float) -> void:
	_elapsed += delta
	_needle.rotation = NEEDLE_BASE_ROTATION + _elapsed * TAU * NEEDLE_TURNS_PER_SECOND
	var left := maxi(ceili(duration - _elapsed), 0)
	if left != _seconds_left:
		_tick(left)
	if _elapsed >= duration:
		set_process(false)
		# 归位: 整秒时长本就转满整圈, 这里只是抹掉最后一帧的零头, 让指针正正停在 12 点
		_needle.rotation = NEEDLE_BASE_ROTATION
		_finish()

# 跨过一秒: 换数字, 从很大缩回原大小(此刻指针正好转满一圈回到 12 点)
func _tick(left: int) -> void:
	_seconds_left = left
	if not show_number:
		_digit.visible = false
		return
	if left <= 0:
		return  # 走到 0 不再换字: 让最后的「1」留在盘上, 配合收尾的停顿
	_show_digit(left)
	if not _digit.visible:
		return
	_digit.scale = Vector2(DIGIT_POP_SCALE, DIGIT_POP_SCALE)
	_digit.modulate.a = 0.35
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_digit, "scale", Vector2.ONE, DIGIT_SHRINK_TIME) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(_digit, "modulate:a", 1.0, DIGIT_SHRINK_TIME * 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# 收场: 先停一拍(指针停在 12 点、盘上留着「1」), 再淡出;
# 淡出之后才发 finished —— 调用方接着切场景, 不会看到时钟被硬切掉
func _finish() -> void:
	_running = false
	await get_tree().create_timer(HOLD_TIME).timeout
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_shade, "color:a", 0.0, FADE_TIME)
	tw.tween_property(_face, "modulate:a", 0.0, FADE_TIME * 0.7)
	tw.tween_property(_face, "scale", Vector2(0.86, 0.86), FADE_TIME)
	await tw.finished
	finished.emit()
	queue_free()
