# cd_bar.gd — 「决定」之后的倒计时色彩条: 主题色+白色斜纹(仿原版滚动条形状)
# 覆盖白色字条下方的整个条件句块(黑块全部盖住); 由 arrange_board 在旋转时钟(CountdownClock)
# 启动的同一帧调 play(), 保证同步; 条带一直滚动, 直到场景切换(随场景销毁)。
# 斜纹如 "/": 图案沿竖直方向平移(与条带垂直), 视觉上斜纹持续朝右下角流动(理发店灯柱效果)。
class_name CdBar
extends Control

const SHADER := preload("res://scripts/ui/widgets/scroll_blocks.gdshader")

# 形状参照 assets/example/滚动条.png(569×125 实测): 主题色斜纹 + 白色斜纹交替,
# 斜纹像素斜率 dx/dy=1.808(全块覆盖时按块宽高比换算成 UV 斜率, 保持同样视觉角度)
const SLANT_PX := 1.808
const FADE_TIME := 0.2   # 斜纹淡入/淡出时长

@export var scroll_speed := 0.4                 # 相位速度(周期/秒), 递增 → 斜纹朝右下角流动
@export var bar_color := Color(0.85, 0.3, 0.3)  # 主题色斜纹颜色(arrange_board 按行角色色覆盖)

var _blocks: TextureRect
var _mat: ShaderMaterial
var _scroll := 0.0
var _playing := false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	set_process(false)

# 父块尺寸变化(布局完成/重排)时铺满整个块, 并按块宽高比换算斜纹 UV 斜率
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_full()

func _build() -> void:
	# 斜纹层: 2×2 白贴图只为拿到 0~1 的 UV, 颜色与滚动全由 shader 决定
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_blocks = TextureRect.new()
	_blocks.name = "Blocks"
	_blocks.texture = ImageTexture.create_from_image(img)
	_blocks.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_blocks.stretch_mode = TextureRect.STRETCH_SCALE
	_blocks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("stripe_color", bar_color)
	_mat.set_shader_parameter("scroll", 0.0)
	_blocks.material = _mat
	add_child(_blocks)
	visible = false

# 铺满整个条件句块(白色字条下方的黑块全部覆盖)
func _layout_full() -> void:
	_blocks.position = Vector2.ZERO
	_blocks.size = size
	if size.x > 0.0:
		_mat.set_shader_parameter("slant", SLANT_PX * size.y / size.x)

# 与旋转时钟同帧启动: 条带立即在场, 斜纹淡入后一直滚动(直到切场景随场景销毁)
func play() -> void:
	visible = true
	_mat.set_shader_parameter("stripe_color", bar_color)
	_blocks.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_blocks, "modulate:a", 1.0, FADE_TIME)
	_playing = true
	set_process(true)

func _process(delta: float) -> void:
	if not _playing:
		return
	_scroll = fmod(_scroll + scroll_speed * delta, 1.0)
	_mat.set_shader_parameter("scroll", _scroll)

# 中断/收场: 斜纹淡出, 条带撤走(条件句块恢复原样)
func stop() -> void:
	_playing = false
	set_process(false)
	var tw := create_tween()
	tw.tween_property(_blocks, "modulate:a", 0.0, FADE_TIME)
	await tw.finished
	visible = false
