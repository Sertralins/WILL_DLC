# 倒计时色彩条（黑框滚动彩块）实现与 Godot 复现

> 日期：2026-08-29
> 来源：`level0` 场景 + `sharedassets0` 素材实测（Spine skel/图集解析、条带像素直方图分析）。
> 对象：点击「决定」后，与旋转时钟**同时**出现的、白色纸条下方**黑框内滚动彩色块**的倒计时条。

---

## 1. 原游戏实现（实测结论）

### 1.1 对象与格式

| 对象 | 格式 | 说明 |
|---|---|---|
| `CdBarRed` / `CdBarBlue` | **Spine 2.1.27 二进制骨骼**（`sp_clock2` / `sp_clock3`） | 倒计时条的两个颜色变体 |
| `CdBroken` | 同上 | 倒计时被打断时的破碎态 |
| （同骨架）`cd_bg` 圆环 / `cd_hand` 指针 / `cd_top` 盖 | — | 旋转时钟与条**共用同一骨架**，所以同步演出 |

### 1.2 条带素材实测（`cd_1`~`cd_5`，各 256×512）

像素直方图显示每张帧**只有两种颜色**：

| 颜色 | 占比 | 含义 |
|---|---|---|
| 近黑 `(32,32,32)` | ~60% | **黑框** |
| 近白 `(224,224,224)` | ~35% | **块**（染色载体） |
| 透明 | 上下边缘 | 条带两端渐隐 |

5 张帧里块的位置逐帧平移 → 翻页 = 滚动。

### 1.3 染色机制：乘法混色

贴图本身是黑白的，颜色是**运行时给 Spine 插槽染红/蓝**：

```
黑(32,32,32) × 红 = 黑    → 框保持黑色
白(224,224,224) × 红 = 红  → 块变成彩色
```

所以成品观感 = 「黑框 + 滚动彩块」，一套灰度素材产出红/蓝两个变体。

### 1.4 动画

- skel 内单个动画：两个插槽各轮换 `cd_1 → cd_5` 附件（约 **0.15s/帧**，5 帧循环）
- 时序：点「决定」→ **黑框先出现（空）** → 倒计时开始 → **块出现并滚动**（染色同时）

---

## 2. Godot 复现

### 2.1 做法 A：黑框贴图 + shader 滚动块（推荐，平滑无帧感）

场景结构（节点在 2D 编辑器手动摆放）：

```
CdBar (Control)
├── BlockLayer (TextureRect)   ← 挂滚动 shader，区域=黑框内部
└── Frame (TextureRect)        ← 黑框贴图（中间镂空），盖在 BlockLayer 上
```

```glsl
// scroll_blocks.gdshader —— 块在固定区域横向滚动
shader_type canvas_item;
uniform vec4 block_color : source_color = vec4(0.85, 0.3, 0.3, 1.0); // 红/蓝在 inspector 换
uniform float scroll : hint_range(0.0, 1.0) = 0.0;
uniform float block_w : hint_range(0.01, 0.5) = 0.18;   // 块宽（占区域比例）
uniform float gap : hint_range(0.0, 0.5) = 0.12;        // 块间距

void fragment() {
    float m = mod(UV.x + scroll, block_w + gap);
    if (m > block_w) { discard; }      // 间隙镂空，透出黑底
    COLOR = block_color;
}
```

```gdscript
# cd_bar.gd —— 倒计时色彩条
extends Control

@export var scroll_speed := 0.4          # 块滚动速度（圈/秒）
@export var bar_color := Color(0.85, 0.3, 0.3)   # 与 shader uniform 同步

@onready var block_layer: TextureRect = $BlockLayer
@onready var frame: TextureRect = $Frame

var _scroll := 0.0
var _playing := false

func play_countdown(seconds: float) -> void:
    # 黑框已在场（进场时只显示 Frame），此刻块淡入并开始滚动
    visible = true
    block_layer.modulate.a = 0.0
    var tw := create_tween()
    tw.tween_property(block_layer, "modulate:a", 1.0, 0.2)
    block_layer.material.set_shader_parameter("block_color", bar_color)
    _playing = true

func _process(delta: float) -> void:
    if _playing:
        _scroll = fmod(_scroll + scroll_speed * delta, 1.0)
        block_layer.material.set_shader_parameter("scroll", _scroll)

func stop() -> void:
    _playing = false
    visible = false            # 或切破碎态贴图（CdBroken 对应）
```

### 2.2 做法 B：5 帧翻页（1:1 复刻原方案）

- 自绘 5 张 256×512「黑框 + 白块」PNG，块逐帧平移一格（块宽 = 平移步长）
- `AnimatedSprite2D`：`SpriteFrames` 装 5 帧，`fps = 6.7`（0.15s/帧）循环
- `modulate = 红/蓝`（乘法混色，与原游戏染色机制完全等价）
- 黑框单独一张贴图盖在上面（或画进帧里）

```gdscript
@onready var blocks: AnimatedSprite2D = $Blocks
@onready var frame: TextureRect = $Frame

func play_countdown(seconds: float) -> void:
    frame.visible = true
    blocks.modulate = bar_color          # 红或蓝
    blocks.play()

func stop() -> void:
    blocks.stop()
    blocks.visible = false
```

## 3. 参数速查

| 参数 | 原游戏实测 | Godot 建议 |
|---|---|---|
| 条带帧 | 256×512，5 帧 | 自绘同规格（或直接做 shader） |
| 翻页速度 | ≈0.15s/帧 | A 方案 `scroll_speed` / B 方案 `fps=6.7` |
| 帧颜色 | 黑 (32,32,32) / 白 (224,224,224) | 帧里只画黑白，颜色靠 modulate/染色 |
| 颜色 | 红 / 蓝两实例 | `@export bar_color` 在 inspector 换 |
| 时序 | 黑框先现 → 块淡入滚动 | `play_countdown()` 里 tween 0.2s 淡入 |
| 中断态 | CdBroken 破碎贴图 | `stop()` 里切破碎态贴图 |
| 与时钟同步 | 同一 Spine 骨架播放 | 条与时钟的 `play_countdown()` 同一帧调用 |

## 4. 备注

- 原游戏的条与旋转时钟共用 `sp_clock2/3` 骨架（时钟圆环 860×860、指针 141×379），要完整还原「同时」感只需把两者入场设在同一帧；
- 所有位置/颜色/速度参数做成 `@export`，节点在 2D 编辑器里手动摆放调整。
