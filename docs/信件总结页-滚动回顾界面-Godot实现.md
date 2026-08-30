# 结局回顾页（读完信点击屏幕跳转的滚动阅览页）实现与 Godot 复现

> 日期：2026-08-29（修正版）
> 来源：`level0` 场景实测（RectTransform 层级 + ScrollRect 组件原始序列化数据解析）。
> **对应画布是 `CanvasAllEndings`**（不是 CanvasEnding——那是结局演出时的叠加层，见 §1）。

---

## 1. 界面流与画布分工（澄清）

| 阶段 | 画布（sortingOrder） | 内容 |
|---|---|---|
| 读信/换句 | CanvasLetter2（0） | 标题淡入在这里；ScrollRect 灵敏度 116 |
| 结局演出 | CanvasEnding（101）叠加 | 深色剪影立绘 (580,502)、AutoReading、Keywords 条——演出阶段，非回顾页 |
| **点击屏幕 → 回顾页** | **CanvasAllEndings** | **上下滚轮/拖拽阅览最终全文 + 右侧结局切换标签** |

回顾页 = 结局演出结束后点击屏幕跳入的页面，也是控制台「信件历史」按钮进入的同一界面：显示 REPLACE 替换后的最终句序，可滚动阅读，右侧可点 S/A/B… 标签切换已达成结局重新播放。

## 2. 回顾页结构（CanvasAllEndings 实测）

| 元素 | 实测参数 | 说明 |
|---|---|---|
| Header | 444×132 @ (-23, -63) 左上角 | 页头（标题/结局计数） |
| Background | (163, 0)，宽 1757，满高 | 内容区（从 x=163 起，给右侧切换器让位） |
| ScrollView | 宽 1735，满高 1080 | ScrollRect（参数见 §3） |
| LetterArea | 0×660，顶部锚 | 滚动内容（信件行容器） |
| LetterLine（每行） | **宽=屏宽-140（左右边距各 70）、高 130**、行顶 +25 | 自定义组件 LetterLine：LocalizedText + Text + Shadow + Underlines |
| EndingSwitcher | 150×124 @ (-628, 62)，右缘锚 | 结局切换器面板 |
| ├ RankTags | 顶部 y=-270，横向铺满 | 评级标签行（每标签：Text (0,-2) 100×-4 评级字、Number (42,45) 100×-45 次数、SelectedFrame 选中框） |
| └ WatchingEye | 166×166 锚点 @ (0,-270) → 眼 74×44 | 「正在观看结局」之眼 |
| sp_next | (-638, 49) 右上角 | 下一段箭头 |
| 右按钮 | Link (-83, 230)、Back (-83, 116)，409×117 | 另一封 / 返回 |
| 底部控制条 | Link 197×48、Back 48 高 | 主机模式 |

## 3. 滚动参数（ScrollRect 原始数据实测）

```
content            = LetterArea (0×660，顶部锚)
viewport           = 全屏；无滚动条（hbar/vbar 均空）
horizontal = 0, vertical = 1                      ← 只允许上下滚
movementType = 1 (Elastic 越界回弹), elasticity = 0.1
inertia = 1（松手惯性滑行）, decelerationRate = 0.005
scrollSensitivity = 100                           ← 回顾页 100；读信视图是 116（两页手感略不同）
```

滚轮 + 鼠标拖拽均为 ScrollRect 原生行为。

## 4. Godot 复现

### 4.1 场景结构

```
RecapScreen (Control, 1920×1080)
├── Bg (TextureRect)                 ← letter_bg 全屏，进入时渐入（点击屏幕后的过渡）
├── Header (Label)                   ← (938, 63) 页头
├── LetterScroll (ScrollContainer)   ← x∈[163, 1898]，宽 1735，满高
│   └── Lines (VBoxContainer)        ← 每行 130 高，宽 1595（边距 70）
├── DragCatcher (Control)            ← 覆盖滚动区的透明层，接管滚轮+拖拽
├── EndingSwitcher (VBoxContainer)   ← 右侧 (-628,62) 150×124：结局标签按钮列
├── LinkBtn / BackBtn                ← (-83,230) / (-83,116)，409×117
└── Eye (TextureRect)                ← 74×44 观看之眼
```

### 4.2 完整代码

```gdscript
# letter_recap.gd —— 结局回顾页（读完信点击屏幕进入）
extends Control

const LINE_H := 130.0            # 行高
const MARGIN_X := 70.0           # 回顾页行边距（读信页是 200，此处不同）
const WHEEL_STEP := 100.0        # 回顾页滚轮灵敏度（实测值；读信页为 116）

@onready var scroll: ScrollContainer = $LetterScroll
@onready var drag: Control = $DragCatcher
@onready var tags: VBoxContainer = $EndingSwitcher

var _vel := 0.0
var _dragging := false
var _drag_from := Vector2.ZERO

# ---------- 进入：点击屏幕后跳入，背景渐入 ----------
func enter(level_id: String, side: String, ending_id: String) -> void:
    $Bg.modulate.a = 0.0
    create_tween().tween_property($Bg, "modulate:a", 1.0, 0.5)   # letter_bg 渐入
    _show_ending(ending_id)                                       # 生成最终句序
    _build_tags(level_id, side)                                   # 已达成结局标签列
    drag.gui_input.connect(_on_drag_input)

# ---------- 按结局重建信的内容（REPLACE 后的最终句序）----------
func _show_ending(ending_id: String) -> void:
    for c in scroll.get_children():
        if c is VBoxContainer: c.queue_free()
    var box := VBoxContainer.new()
    box.position = Vector2(MARGIN_X, 25)
    scroll.add_child(box)
    for key in final_sentence_keys(ending_id):     # 条件引擎结果 + 结局 REPLACE
        var l := Label.new()
        l.text = tr(key)
        l.add_theme_font_size_override("font_size", 42)
        l.add_theme_constant_override("line_spacing", int(42 * 1.2))
        l.custom_minimum_size = Vector2(1920 - 2 * MARGIN_X - 163, LINE_H)
        l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        box.add_child(l)
    scroll.scroll_vertical = 0                    # 每次切换回顶部
    _snap_back()

# ---------- 结局切换标签（右侧 S/A/B…）----------
func _build_tags(level_id: String, side: String) -> void:
    for tag in tags.get_children(): tag.queue_free()
    for rank in save.achieved_ranks(level_id, side):    # 存档里已达成的评级
        var btn := Button.new()
        btn.text = rank.trim_suffix("1")                # "S1" -> "S"
        btn.add_theme_font_size_override("font_size", 80)
        btn.pressed.connect(func(): _show_ending(rank))
        tags.add_child(btn)

# ---------- 滚轮 + 拖拽 + 惯性 + 回弹（复刻 ScrollRect 手感）----------
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
                    _drag_from = drag.get_global_mouse_position()
                else:
                    _dragging = false
                    _snap_back()                     # Elastic 0.1 回弹
    elif ev is InputEventMouseMotion and _dragging:
        var cur := drag.get_global_mouse_position()
        var dy := cur.y - _drag_from.y
        scroll.scroll_vertical += int(dy)
        _vel = dy * 40.0
        _drag_from = cur

func _process(delta: float) -> void:
    if not _dragging and absf(_vel) > 0.5:
        scroll.scroll_vertical += int(_vel * delta)
        _vel *= exp(-0.30 * delta)                   # decel 0.005/帧 ≈ ×0.74/秒
    elif not _dragging:
        _vel = 0.0

func _snap_back() -> void:
    var max_v := max(0, scroll.get_v_scroll_bar().max_value - scroll.size.y)
    var target := int(clamp(scroll.scroll_vertical, 0, max_v))
    if target != scroll.scroll_vertical:
        _vel = 0.0
        create_tween()\
            .tween_property(scroll, "scroll_vertical", target, 0.15)\
            .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
```

## 5. 与读信视图的差异速查

| 参数 | 读信视图（CanvasLetter2） | 回顾页（CanvasAllEndings） |
|---|---|---|
| 行边距 | 200（中心偏移 -65） | **70** |
| 行宽 | 1520 | 1595（内容区 1735-140） |
| 滚轮灵敏度 | 116 | **100** |
| Elasticity / 惯性 | 0.1 / 0.005 | 0.1 / 0.005（相同） |
| 标题 | 淡入（切换读信时） | 页头 Header（无淡入，属回顾页常态） |
| 附加 | — | 结局切换标签列 + 观看之眼 + sp_next |

## 6. 备注

- 回顾页内容 = 所选结局的 REPLACE 替换后最终句序；切换标签即重放不同结局的全文；
- 标题淡入是**读信切换**时的效果（CanvasLetter2），不属于回顾页——之前版本混淆了这两处；
- 素材与文本须自绘自写；字体用开源替代。
