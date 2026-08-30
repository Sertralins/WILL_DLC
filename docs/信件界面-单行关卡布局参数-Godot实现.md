# 信件界面布局参数：单行 vs 双行关卡（Godot 实现）

> 日期：2026-08-29（修订版）
> 来源：`level0` 场景实测。**读信界面有两个画布**：单行关卡用 `CanvasLetter2`，双行/三行关卡用 `CanvasPlay`。
> 所有数值以 **1920×1080 设计分辨率**为基准（序列化画布尺寸 3660×2059 是编辑器缩放痕迹，数值本身即 1920×1080 设计空间单位）。

---

## 1. 单行关卡（ROWCOUNT=1）—— CanvasLetter2

只有 L 列一个人。布局：**一行信件居中偏左、立绘在右、右侧竖排按钮**。

```
全屏底图 RawOver 1920×1080（letter_bg_<角色>.png 2048×1024，含信纸的画法）
├── 标题 LetterTitle      起点 (79.5, 75) 左上角锚，宽 1150 高 118，pivot(0,0.5)，字号 70
├── 标题线 LetterTitleLine (0, 127)，贴图 436×17
├── 信件行区 LetterArea    顶部撑满，高 660
│   └── 每行 LetterLine    宽 = 1920-400 = 1520（左 135 右 185，中心 x 偏移 -65），高 130
│                          行顶距区域顶 25px；行内：Underlines（关键词下划线）+ Areas（块落点）
├── 立绘 Figure            中心 (580, -38) → 屏幕 (1540, 502)，尺寸 500×1000  ← 右侧
├── 右侧按钮组（右缘锚点，均伸出屏幕右缘 121px 的"半露"样式）
│   ├── 决定 Submit         (-83, +670)   ← 右上角
│   ├── 回想 Perform        (-83, +280)   ← 右上
│   ├── 切换结局 Endings    (-83, +410)   ← 右上
│   ├── 继续 Play           (-83, -145)   ← 右下
│   └── 另一封 Link         (-83, -275)   ← 右下
│        统一 409×117（内芯贴图 402×108），间距 130
└── 倒计时时钟锚点          (591, 511)，100×100（运行时挂 sp_clock Spine）
```

句子块（运行时生成）：**540×60 起**，文本 34px/行高 41.4 自动加高；贴图 `block_s_v5.png` 102×102 九宫格；角标 tag 27×20；选中框 62×62 / 122×122。

## 2. 双行关卡（ROWCOUNT=2/3）—— CanvasPlay

L、R（三行关还有 M）**三套并排列**，每列有自己的背景、立绘、评级标签、句子块列：

| 元素 | L 列（左） | R 列（右） | M 列（中，仅 0048） |
|---|---|---|---|
| 列背景 | `LBG` 宽 1016，满高，屏幕 x∈[160, 1176] | `RBG` 宽 1016，满高，x∈[744, 1760] | `MBG` 宽 1920 满屏 |
| 立绘 | `LFigure` (220, 440) | `RFigure` (1700, 440) | `MFigure` (960, 440) |
| 立绘尺寸 | 600×1200 | 600×1200 | 600×1200 |
| 评级标签 | `LRankTag` (142, 728) | `RRankTag` (1742, 576) | `MRankTag` (946, 624) |
| 标签尺寸 | 361×160（贴图 358×158，字 80px / 数字 40px） | 同 | 同 |
| 句子块列 | 块宽 **600**，列心屏 x ≈ 580~650 | 块宽 **550**，列心屏 x ≈ 1270 | 块宽 550（推断） |
| 结局文字 | `LEnding` 左锚 (184, -48) 320×60 | `REnding` 右锚 (20, -58) | `MEnding` 中锚 (102, -58) |

- **中缝**：LBG 右缘 1176 与 RBG 左缘 744 重叠 → **跨行拖放区 x∈[744, 1176]**（把句子拖过中缝 = 移到另一封信，对应 IN(L/R,M) 条件）。
- 右侧按钮组、底部主机控制条与单行**完全相同**（决定 (-83,670) 409×117 等）。
- 双行额外有：`CdBarRed`/`CdBarBlue`/`CdBroken`（倒计时条红/蓝/破损态，Spine）、`MapMask`+`MapBackground`（地图浮层 1526×1300 / 地图 1358×952）。
- 块模板（BlockButton1..12）序列化位置是占位值（y 为负、在屏外），运行时按信内容重新排布——**只有块宽（L 600 / R 550）和列心是有效信息**。

## 3. 两类关卡参数差异对照（Godot 实现直接照抄）

| 参数 | 单行（CanvasLetter2） | 双行（CanvasPlay） |
|---|---|---|
| 列数 | 1（居中偏左） | 2（L 左 / R 右），3 行关加 M 中 |
| 立绘位置 | (1540, 502) | L (220,440) / R (1700,440) / M (960,440) |
| 立绘尺寸 | 500×1000 | 600×1200 |
| 信件行区 | 顶部 660 高，宽 1520（边距 200） | 每列一块，宽约 550~600 |
| 行高 | 130 | 由内容排布 |
| 句子块宽 | 540（模板 ShadowButton） | L 600 / R 550 |
| 标题 | (79.5, 75) 1150×118 | 每列各自（代码定位） |
| 评级标签 | 通用 RankTags（结局列表用） | 每列一个：L(142,728) R(1742,576) M(946,624) |
| 中缝 | 无 | x∈[744,1176] 跨行拖放区 |
| 倒计时 | 时钟锚 (591,511) | CdBar 红/蓝条（Spine） |

## 4. Godot 实现：按 ROWCOUNT 分支

```gdscript
# letter_view.gd —— 一个场景支持两种布局
const REF := Vector2(1920, 1080)

func _build_layout() -> void:
    match level.row_count:
        1: _build_single_row()
        2, 3: _build_multi_row()

# ---------- 单行 ----------
func _build_single_row() -> void:
    # 背景（原创 2048×1024 底图，含信纸画法）
    _fullscreen_texture("res://art/letter_bg.png")
    # 标题：屏幕坐标 (79.5, 75)，70px
    var title := _label(tr(level.title_key), 70)
    title.position = Vector2(79.5, 75)
    # 标题线贴图 436×17
    var tline := TextureRect.new()
    tline.texture = load("res://art/title_line.png")
    tline.position = Vector2(0, 127); tline.custom_minimum_size = Vector2(436, 17)
    add_child(tline)
    # 信件行区：顶部 660，左右边距 200（中心偏移 -65）
    var area := Control.new()
    area.position = Vector2(135, 0)                 # 左 135 = 200-65
    area.size = Vector2(REF.x - 400, 660)
    add_child(area)
    for i in level.row_sentences("L").size():
        _make_line(area, i)                          # 行高 130，行顶 +25+130*i
    # 立绘：右侧 (1540, 502)，500×1000（自绘 Spine/序列帧替代）
    _figure("res://art/figure.png", Vector2(1540, 502), Vector2(500, 1000))
    # 右侧按钮：右上角锚，409×117，间距 130，半露屏外（x = 1920-83-204.5+409 起）
    _edge_buttons([("决定", 670), ("回想", 280), ("切结局", 410)], true)

# ---------- 双行 ----------
const COL := {  # 实测参数
    "L": { "bg": [160, 1176], "figure": Vector2(220, 440), "rank": Vector2(142, 728), "block_w": 600 },
    "R": { "bg": [744, 1760], "figure": Vector2(1700, 440), "rank": Vector2(1742, 576), "block_w": 550 },
    "M": { "bg": [0, 1920],   "figure": Vector2(960, 440), "rank": Vector2(946, 624), "block_w": 550 },
}

func _build_multi_row() -> void:
    for side in level.row_sides():                  # ["L","R"] 或 ["L","R","M"]
        var c: Dictionary = COL[side]
        # 列背景：x∈c.bg，满高
        var bg := TextureRect.new()
        bg.texture = load("res://art/column_bg.png")
        bg.position = Vector2(c.bg[0], 0)
        bg.custom_minimum_size = Vector2(c.bg[1] - c.bg[0], REF.y)
        add_child(bg)
        # 立绘 600×1200
        _figure(level.character(side), c.figure, Vector2(600, 1200))
        # 评级标签 361×160
        _rank_tag(c.rank, Vector2(361, 160))
        # 该列句子块：块宽 c.block_w，列心 = (bg[0]+bg[1])/2
        var col_center := (c.bg[0] + c.bg[1]) / 2.0
        var y := 25.0
        for slot in level.row_sentences(side):
            if slot.type == 1:
                var block := SENTENCE_BLOCK.instantiate()
                block.custom_minimum_size = Vector2(c.block_w, 60 + 41.4 * (block.text_lines - 1))
                block.position = Vector2(col_center - c.block_w / 2.0, y)
                add_child(block)
                y += 130.0
            else:
                y += 130.0                           # 固定句只占行
    # 中缝：x∈[744,1176] 注册为跨行拖放区（Area2D/Control 接收 drop）
    var seam := Control.new()
    seam.position = Vector2(744, 0); seam.size = Vector2(1176 - 744, REF.y)
    seam.set_meta("seam", true)
    add_child(seam)
    # 右侧按钮组与单行完全一致
    _edge_buttons([("决定", 670), ("回想", 280), ("切结局", 410)], true)
```

拖放时判断落点：`drop_x in [744, 1176]` → 句子跨行（更新 `IN(L/R/M)` 状态）；否则回到原列最近行槽（行距 130 网格）。

## 5. 背景实现：单行整图 vs 多行拼接（实测拆解）

### 5.1 单行：一张整图，纸画在图里

每个角色一张全屏背景 `letter_bg_<角色>.png`（**2048×1024**，共 15 张：lw/wzr/yang/alicia/carlos/dh/jby/jz/pi/psj/st/ying/zjm/ci/story）。构图完全固定：**桌面 + 信纸画在图里（左中位置）+ 右侧留空给立绘**，只是每角色换配色与陈设。运行时由 `RawBase`/`RawOver`（RawImage，场景里 sprite 为空，按角色代码在运行时加载对应贴图）全屏铺开，`letter_bg_story` 是剧情段的通用版。

### 5.2 多行：不是拼两张房间图，而是"纯色底 + 两条光柱条"

实测 `CanvasPlay` 的三个背景组件（Image 组件原始序列化数据解析）：

| 组件 | 引用素材 | 颜色 tint | 矩形 |
|---|---|---|---|
| `MBG`（底层） | **无 sprite**（纯色矩形） | **(1, 1, 0.5, 1)** 暖黄 | 1920 全屏 |
| `LBG`（左条） | **`BGL`**：图集 `BG.png`(256×1024) 中 105×1024 的白色渐变条（图集 x=151） | (1, 1, 0.5, 1) | 1016 宽，屏幕 x∈[160,1176] |
| `RBG`（右条） | **`BGR`**：同图集另一条 105×1024（图集 x=0） | (1, 1, 0.5, 1) | 1016 宽，屏幕 x∈[744,1760] |

- 两条渐变条实测 alpha 分布：**BGL 顶部 α≈190 → 底部 α≈0**；BGR 底部 α≈255 → 顶部 α≈60——白色光柱/灯光渐隐效果，× tint (1,1,0.5) 后是淡黄光柱。
- 两条矩形在 **x∈[744,1176] 重叠** = 中缝（两列信件的过渡区）。
- 多角色的"专属感"由 **L/R/M 立绘（600×1200，站屏幕两侧）** + 各列句子块提供，不是靠拼接房间背景。
- 顺带实测：`MapBackground` 引用 `play_map_background` sprite；右侧竖排按钮的图集 hash 系统 = C# `string.GetHashCode()`（hash31），37/37 全部命中验证（`levelmenu200_conf` 的 atlasHash + trimming = 每个 sprite 的九宫格边框参数）。

### 5.3 Godot 复现

```gdscript
# 单行：一张全屏底图即可
var bg := TextureRect.new()
bg.texture = load("res://art/letter_bg_%s.png" % level.character)  # 原创 2048×1024，纸画在图里
bg.set_anchors_preset(Control.PRESET_FULL_RECT)
bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

# 多行：ColorRect 底 + 两条 GradientTexture2D 光柱 + 立绘
func _build_multi_row_bg() -> void:
    var base := ColorRect.new()
    base.color = Color(1, 1, 0.5, 1)                     # MBG 暖黄纯色
    base.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(base)

    for side in ["L", "R"]:                              # 两条光柱
        var strip := TextureRect.new()
        var grad := GradientTexture2D.new()
        grad.fill_from = Vector2(0, 0); grad.fill_to = Vector2(0, 1)
        if side == "L":                                   # BGL：顶亮→底透明
            grad.gradient = Gradient.new()
            grad.gradient.set_color(0, Color(1, 1, 1, 0.75))
            grad.gradient.set_color(1, Color(1, 1, 1, 0.0))
        else:                                             # BGR：底亮→顶暗
            grad.gradient = Gradient.new()
            grad.gradient.set_color(0, Color(1, 1, 1, 0.25))
            grad.gradient.set_color(1, Color(1, 1, 1, 1.0))
        strip.texture = grad
        strip.modulate = Color(1, 1, 0.5)                # tint 与色底同色系
        strip.position = Vector2(160 if side == "L" else 744, 0)
        strip.size = Vector2(1016, 1080)
        add_child(strip)
    # 立绘 600×1200：L (220,440) / R (1700,440)，再挂两列句子块
```

> 原游戏的渐变条是 105×1024 的贴图被水平拉长到 1016（Simple 拉伸，渐变是纯竖向的所以拉长无痕）；自绘时直接画 1024 高的渐变贴图即可，无需九宫格。



## 6. 修正与备注

- **修正**：旧版本文档中的"信纸 1080×1080 @(-36,0)"是**人物档案界面**（CanvasProfileContents）的对象，不属于读信界面——读信界面没有独立纸对象，信纸画法在 `letter_bg_<角色>.png` 底图里（2048×1024 全屏）。
- 单行信件行区实际左/右边距不对称：宽 1520、中心 x=895（偏移 -65）→ 左 135 / 右 185。
- 右侧按钮均以右缘为锚、中心在 x=1837（超出屏幕右缘 121px），是原游戏"按钮半露屏外"的样式。
- 双行的块模板位置是占位（y 为负），只有块宽（L 600 / R 550）与列背景区间是有效布局参数；行排布规则由代码按内容计算（行距沿用 130）。
- 三行关 0048：在双行基础上加 M 列（居中）。
- 素材须自绘；汉仪润圆为商业字体，请用开源替代。
