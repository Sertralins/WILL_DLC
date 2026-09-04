# 选关界面：关卡地图、生长逻辑与 Godot 复现

> 日期：2026-08-28
> 目标：解析《WILL：美好世界》选关界面（关卡地图）的实现机制——点击邮箱后关卡如何"生长"出来、多条关卡链如何横向连线、关卡如何跳转、点击关卡后的小标题如何显示——并给出 Godot 4 的完整复现方案。
> 说明：原游戏 C# 源码为专有代码，此处是基于解包数据（关卡 JSON、strings.po、UI 贴图、图集配置）的**机制重建**；机制与数据结构可自由参考，**美术/文本等表达须原创**。

---

## 1. 原游戏选关界面的构成

解包出的相关素材（`_extracted/`）：

| 素材 | 尺寸 | 用途 |
|---|---|---|
| `textures/map00.png` / `map01.png` | 2048×1024 | 地图底图（两个"世界页"，滚动浏览） |
| `sprites/mailbox_closed.png` / `mailbox_open.png` | 236×289 / 291×289 | 信箱关/开两态 |
| `sprites/mailbox_new.png` | 40×240 | 信箱上的竖排"新信件"标条 |
| `sprites/mailbox_mail_0..5.png` | ~90×70~120 | 6 种信封造型（新信件列表用） |
| `sprites/levelblockv7_border.png` / `levelblockv7_window.png` | 34×34 / 26×26 | 关卡块（信件节点）的圆角边框与内窗，九宫格拉伸 |
| `sprites/connecting_lines_0..15.png` | 线宽 10px 的一组管件 | **实线**连接线的 16 种拼块（直段、弯角、三通等） |
| `sprites/dotted_lines_0..15.png` | 同上 | **虚线**版（未激活/待定连接） |
| `scripts/connecting_animations_conf.json` | — | 连线"生长"动画的图集配置（2 组 × 8 帧） |
| `scripts/levelmenu200_conf.json` / `levelmenu400_conf.json` | — | 选关菜单在 200%/400% 分辨率下的图集裁切表 |
| `sprites/levelinformationrank_selected_frame.png` | 32×32 | 关卡信息窗的评级选中框 |

连线拼块的线宽统一为 **10px**，弯角是半径约 37px 的圆弧件，另有 57px 长直段和 64px 的三通/十字件——原游戏的连线不是整张画好的图，而是**用管件沿网格路径逐段拼接**的（类似"铺水管"），因此任意两个节点之间都能路由出带圆角的折线。虚线拼块与实线一一对应，用于"尚未建立"的连接。

`strings.po`（`STRINGS.FONT.MENU_LEVEL.*`）里的布局/字体参数：

| 键 | 值 | 含义 |
|---|---|---|
| `MENU_LEVEL_SCREEN_HALF_WIDTH` | 17 | 视口半宽（网格单位） |
| `MENU_LEVEL_SCREEN_HALF_HEIGHT` | 10 | 视口半高 |
| `LEVEL_BLOCK_TITLE_FONT` / `_SIZE` | FANDOLFANG_LETTERTITLE / 80 | 关卡块大标题字体字号 |
| `LEVEL_BLOCK_TITLE_POS_X/Y` | 0 / -16 | 标题相对节点偏移 |
| `SUBTITLE_HELP_FONT` / `_SIZE` | FANDOLFANG_TEXTURE / 40 | 点击后"小标题"（角色呼喊语）字体字号 |
| `INFORMATION_WINDOW_SCALE` | 1 | 信息窗缩放 |

---

## 2. 数据模型：地图是一棵（多棵）有向树

### 2.1 节点 = "关卡的一行"

每一关的每一行（L/R，0048 还有 M 行）是地图上的**一个节点**。节点字段（`leveldata-retail.bundle/*.txt`）：

| 字段 | 例子 | 含义 |
|---|---|---|
| `LPOSITION` / `RPOSITION` | `"0,6"`、`"-2,3"`、`"2,15"`、`"0,78"` | 坐标：**第一维=横向泳道**（仅取 -2 / 0 / 2 三档，左/中/右三条平行链），**第二维=沿链生长方向的距离**（单调累加，最大 78，地图沿此轴滚动） |
| `LPREVIOUS` / `RPREVIOUS` | `"start"`、`"0001:L"`、`"0048:M"` | **实线父边**：从哪个节点（或信箱 `start`）长出来 |
| `LPENDINGS` / `RPENDINGS` | `"0057:L(S1)&0013:L(S1)"` | **待定父边（虚线）来源列表**，`&` 分隔，括号内是要求的结局评级集合 |
| `LCONDITION` / `RCONDITION` | `"ELLE(0057,0,S1)&&ELLE(0013,0,S1)"` | 待定边转正/节点激活的条件表达式（`ELLE(关卡,行号,评级)` = 该行达到过该评级） |
| `UNLOCK` | `"SRANK(0001)"`、`"CURRENT(0013,0,S1)&&…"` | 关卡整体的解锁门（复用条件表达式引擎，见《Godot从零实现指南》§4） |

### 2.2 全图拓扑实例（从 63 关数据摘出）

```
信箱(start)
 ├─0001:L(0,6) ─实线→ 0002:R(0,3) ─→ 0003:L(0,3) ─→ 0057:L(0,30) ─→ 0017…
 │                    └─→ 0004:L(0,4)   ←──┐ 同时挂虚线 pending: 0002:R(S1)&0003:L(S1,BAD2)
 ├─0002:L(0,9)（0002 关自己也是新链根）     │
 ├─0004:R(0,13) ← start，且带同一条 pending ┘   ← 一个节点可同时被"实线"和"虚线"指向
 ├─0012:L(0,37) ← start（中段冒出的新链根）
 ├─0015:L(-2,3) ← 0014:R        ← 泳道 -2 = 左侧支链
 ├─0016:L( 2,3) ← 0014:R，pending 0014:R(BAD6)   ← 泳道 +2 = 右侧支链
 └─0048:R(0,78) ← start … 0049:L(0,5) ← 0048:M  ← 三行关的 M 行也能当父节点
```

观察结论：

1. **地图是多根森林**：多个节点 `PREVIOUS="start"`，即都从信箱长出来——点击信箱时，这些链一起"生长"。
2. **泳道制造横向并排**：主线走泳道 0，分支摆到 ±2，形成"多个关卡同时横向连线"的视觉。
3. **一个节点可有多条入边**：一条实线（PREVIOUS）+ 若干虚线（PENDINGS）。虚线在条件未达成时以 `dotted_lines` 画出，暗示"这封信和那边有关"；`LCONDITION` 全部满足后节点才真正解锁，虚线转实线。
4. **距离坐标沿生长方向单调**：子节点距离 = 父节点距离 + 增量（常见 3，大跳 30/52/78），地图视口沿该轴滚动，`HALF_WIDTH=17` 说明一屏约看到 34 个单位宽。

### 2.3 角色配色（连线颜色）

`data.bundle/BASICDATA.txt` 的 `PERSON` 表给每个角色定义了地图表现：

```json
{ "NAMECODE": "lw", "FIG_COLOR": "119,117,35", "BG_COLOR": "…",
  "WINDOW_COLOR": "…", "LINE_START_POINT": "0,1", … }
```

- **连线按角色着色**：每条链用该行角色的 `FIG_COLOR` 画线——地图上红/黄/绿几条线各代表一个角色的人生线。
- `LINE_START_POINT "0,1"`：该角色连线从信箱出发的锚点偏移（多条链在信箱处不重叠）。
- 关卡块内窗用 `WINDOW_COLOR` 上色，块底用 `BG_COLOR`。

### 2.4 点击关卡后显示的文字

- **大标题**：`STRINGS.DIALOG.CONTENT.<关卡号>_<L|R|M>TITLE`（如 `0001_LTITLE`=「我想回家」），用 `LEVEL_BLOCK_TITLE_*` 参数（FandolFang 80px，偏移 (0,-16)）画在关卡块信息处。模板在 `STRINGS.UI.LEVELS.LETTER_TITLE_DECORATED`（`[[[title]]]`）/`LETTER_TITLE_INTERNAL`（`[[[id]]]-[[[title]]]`）。
- **小标题（角色呼喊语）**：`STRINGS.UI.LEVELS.SUBTITLE_HELP_<角色>_<情绪>`（如 `SUBTITLE_HELP_LW_HELPME`=「神啊请帮帮我」），40px。即点击信件块时浮在旁边的角色心声，每角色多条、按关卡情绪选用。
- 已玩过的关在信息窗里显示评级（`levelinformationrank_selected_frame` 选中框）。

---

## 3. 原游戏行为重建（流程）

1. **打开信箱**（控制台 `MAILBOX` 按钮）：`mailbox_closed→open` 两态切换；未读新信以 6 种信封之一（`mailbox_mail_0..5`）+ `mailbox_new` 标条列出；空则提示 `LETTER_MAILBOX_EMPTY`「没有新信件」；取信时 toast `LETTER_NEW_COMING`「收到新信件：《…》」。
2. **生长**：结算/读信后，用存档重估所有 `UNLOCK` / `LCONDITION`。新解锁的链从 `start` 或已存在节点出发，**逐节点播放"块弹出 + 连线逐帧画出"动画**（`connecting_animations_conf` = 连线生长帧动画，2 组各 8 帧，对应实线/虚线两种画法）。
3. **横向连线**：同一父节点的多个子节点共享父块锚点，各画各的管件折线，互不重叠地摆到不同泳道 → "同时横向连线"。
4. **关卡跳转**：点击关卡块 → 视口平滑滚动定位到该块 → 弹出信息（大标题 + 小标题 + 评级）→ 确认后进入读信场景。`MESSAGE_TRAVEL_TO_ANOTHER_WORLD`「要启程去新的世界吗？」= 切换地图页（map00 ↔ map01）。

> 以上为从数据反推的行为模型；原 C# 实现为专有代码，不复刻。

---

## 4. Godot 4 复现方案

### 4.1 场景树

```
LevelSelect (Node2D)
├── Camera2D                      ← 沿生长轴滚动（limit 到地图全长）
├── ParallaxBackground?（可选底图视差）
├── MapRoot (Node2D)
│   ├── Background (TextureRect / Sprite2D)      ← 原创底图
│   ├── LinesLayer (Node2D)      ← 挂所有连线（自绘 Control）
│   ├── Mailbox (Area2D/Sprite2D) ← start 锚点，closed/open 两帧 + new 标条
│   └── Blocks (Node2D)          ← 每节点一个 LevelBlock 实例
└── UI (CanvasLayer)
    ├── InfoPopup (Control)      ← 大标题 + 小标题 + 评级 + 确认/取消
    └── Toast (Label)            ← 「收到新信件」
```

坐标映射（原数据 → 屏幕）：

```gdscript
const UNIT := 120.0        # 距离坐标 1 单位 = 120px（生长轴，用 X）
const LANE := 150.0        # 泳道 -2/0/2 → Y = lane/2 * LANE
func to_screen(lane: int, dist: int) -> Vector2:
    return Vector2(dist * UNIT, (lane / 2.0) * LANE)
```

（原游戏横向滚动地图：生长轴为水平、泳道为竖直；若想竖排，把两轴对调即可。）

**当前实现（竖排版 + 手动栅格，2026-09 起）**：

- 布局常量在 `scenes/map/map.gd`：`UNIT_Y := 80`（纵向 1 格）、`GX := 222`（横向 1 格 = 半列宽，偶数 gx 对齐角色列轴线）、`HEADER_W := 444`（角色列宽）；
- 关卡块位置由 `data/levels/levels_index.json` 的 `positions` 表手动指定（绝对栅格 `[gx, gy]`，key = `关卡id:行id`；未登记的节点回退自动布局）；
- 连线由 `scenes/map/map_route.gd` 用 `assets/sceneUI/line/` 管件素材拼接（件 7/9 直段拉伸、件 0/1/4/5 四向弯角、`dotted_*` 虚线组给 pendings 待定边），替代下方 §4.3 的自绘 map_line 方案——同列竖直线、同高横线、跨列 S 弯（先竖→拐角→横向→拐角→竖）。

### 4.2 地图模型

```gdscript
# level_map_model.gd —— 从关卡 JSON 构图
class_name LevelMapModel
extends RefCounted

signal grown(nodes: Array, edges: Array)   # 本轮新长出的节点/边

class Edge:
    var from: String      # "start" 或 "<id>:<side>"
    var to: String
    var solid: bool
    var pending_ranks: PackedStringArray

class Node:
    var key: String                 # "0001:L"
    var level_id: String; var side: String
    var lane: int; var dist: int
    var character: String
    var title_key: String           # STRINGS.DIALOG.CONTENT.0001_LTITLE
    var subtitle_key: String        # SUBTITLE_HELP_<char>_<mood>（自制字段）
    var parent: String = ""
    var pendings: Array[Edge] = []

var nodes: Dictionary = {}          # key -> Node
var save: Dictionary                # {"0001:L": {"ranks": ["S1"], "read": true}, …}

func _parse_pendings(s: String) -> Array[Edge]:
    # "0057:L(S1)&0013:L(S1,BAD2)" -> 两条待定边
    var out: Array[Edge] = []
    for part in s.split("&", false):
        var i := part.find("(")
        var e := Edge.new()
        e.from = part.substr(0, i)
        e.pending_ranks = part.substr(i + 1, part.length() - i - 2).split(",")
        e.solid = false
        out.append(e)
    return out

func build(level_list: Array) -> void:
    for lv in level_list:
        for side in ["L", "R", "M"]:
            var pos: String = lv.get(side + "POSITION", "")
            if pos.is_empty(): continue
            var n := Node.new()
            n.key = "%s:%s" % [lv.LEVELID, side]
            n.level_id = lv.LEVELID; n.side = side
            var xy := pos.split(",")
            n.lane = xy[0].to_int(); n.dist = xy[1].to_int()
            n.character = lv.get(side + "NAMECODE", "")
            n.title_key = "STRINGS.DIALOG.CONTENT.%s_%sTITLE" % [lv.LEVELID, side]
            n.parent = lv.get(side + "PREVIOUS", "")
            n.pendings = _parse_pendings(lv.get(side + "PENDINGS", ""))
            nodes[n.key] = n

func ranks_of(key: String) -> PackedStringArray:
    return save.get(key, {}).get("ranks", [])

func is_unlocked(n: Node) -> bool:
    # 实线父边：父节点出现过且读过信；待定边：所有来源都达到要求评级
    if n.parent != "" and n.parent != "start":
        if ranks_of(n.parent).is_empty():
            return false
    for e in n.pendings:
        var got := ranks_of(e.from)
        for r in e.pending_ranks:
            if got.has(r): return true     # 任一来源满足即可（与原游戏 OR 语义一致）
    return true
```

### 4.3 连线绘制：折线 + 生长动画 + 虚线

原游戏用 16 种管件拼线；Godot 里更简单且观感一致的做法是 **`_draw()` 画圆角折线**（`draw_polyline` + 圆弧角），虚线用 `draw_dashed_line`，生长动画用一个 0→1 的 `progress` 截断折线长度：

```gdscript
# map_line.gd —— 挂在 LinesLayer 下的自绘节点
class_name MapLine
extends Node2D

var a: Vector2                 # 起点（父块锚点）
var b: Vector2                 # 终点（子块锚点）
var line_color: Color
var dashed := false
var width := 10.0
var corner := 37.0             # 圆角半径（对还原管件观感）
var progress := 1.0            # 0..1，生长动画推进

func _ready() -> void:
    if progress < 1.0:
        var tw := create_tween()
        tw.tween_property(self, "progress", 1.0, 0.5).set_ease(Tween.EASE_OUT)
        tw.tween_callback(queue_redraw)

func _polyline() -> PackedVector2Array:
    # L 形路由：先沿生长轴走到子节点投影点，再横摆到泳道；同泳道则直线
    if is_equal_approx(a.y, b.y):
        return PackedVector2Array([a, b])
    var mid := Vector2(b.x - corner * sign(b.x - a.x), a.y)
    return PackedVector2Array([a, mid, Vector2(b.x, a.y + corner * sign(b.y - a.y)), b])

func _draw() -> void:
    var pts := _polyline()
    # 按 progress 截断总长
    var lens: Array[float] = []
    var total := 0.0
    for i in pts.size() - 1:
        var l := pts[i].distance_to(pts[i + 1]); lens.append(l); total += l
    var budget := total * progress
    var out := PackedVector2Array([pts[0]])
    for i in lens.size():
        if budget <= 0: break
        if budget >= lens[i]:
            out.append(pts[i + 1])
        else:
            out.append(pts[i].lerp(pts[i + 1], budget / lens[i]))
        budget -= lens[i]
    if dashed:
        for i in out.size() - 1:
            draw_dashed_line(out[i], out[i + 1], line_color, width, 4.0)
    else:
        draw_polyline(out, line_color, width, true)   # 抗锯齿圆头
```

> 想 1:1 还原"管件拼接"观感，把 `_draw` 换成沿同样折线放置 9-slice 直段 + 四向圆弧角贴图即可（对原件的 10px 线宽 / 37px 圆角半径），但贴图须自绘。

### 4.4 关卡块场景

```gdscript
# level_block.gd
class_name LevelBlock
extends Area2D

signal clicked(key: String)
var key := ""

@onready var border: NinePatchRect = $Border     # 原创圆角边框（对应 levelblockv7_border）
@onready var window: ColorRect  = $Window        # 内窗，tint = 角色 WINDOW_COLOR

func setup(n, person: Dictionary) -> void:
    key = n.key
    window.color = _csv_color(person.get("WINDOW_COLOR", "0,0,0"))
    position = LevelSelect.to_screen(n.lane, n.dist)
    input_pickable = true

func _gui_input(ev: InputEvent) -> void:
    if ev is InputEventMouseButton and ev.pressed:
        clicked.emit(key)

# 弹出动画：从 0 弹性放大
func pop_in(delay: float) -> void:
    scale = Vector2.ZERO
    var tw := create_tween()
    tw.tween_interval(delay)
    tw.tween_property(self, "scale", Vector2.ONE, 0.35)\
      .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
```

### 4.5 生长编排（点击信箱后的核心演出）

```gdscript
# level_select.gd（节选）
func refresh_growth() -> void:
    # 1) 找出"现在该出现但还没出现"的节点（BFS，保证父先子后）
    var to_grow: Array = []
    var frontier := ["start"]
    var seen := {"start": true}
    while frontier.size():
        var cur := frontier.pop_front()
        for n in model.nodes.values():
            if n.key in seen: continue
            if n.parent == cur and model.is_unlocked(n):
                seen[n.key] = true
                to_grow.append(n)
                frontier.append(n.key)
    # 2) 逐节点演出：先画线（生长动画），线到后块弹出
    var t := 0.0
    for n in to_grow:
        var anchor_from := mailbox_anchor(n) if n.parent == "start" else block_anchor(n.parent)
        var line := MapLine.new()
        line.a = anchor_from
        line.b = LevelSelect.to_screen(n.lane, n.dist)
        line.line_color = person_color(model.nodes[n.key].character)
        line.progress = 0.0
        lines_layer.add_child(line)
        var block := LEVEL_BLOCK_SCENE.instantiate()
        block.setup(n, persons[n.character])
        block.pop_in(t + 0.4)          # 线画完的刹那弹出
        block.clicked.connect(_on_block_clicked)
        blocks.add_child(block)
        # 3) 虚线（pending 但来源未达标）：直接画满，不弹块
        for e in n.pendings:
            if model.ranks_of(e.from).is_empty(): continue
            var d := MapLine.new()
            d.a = block_anchor(e.from); d.b = line.b
            d.dashed = true; d.line_color = person_color(model.nodes[e.from].character)
            lines_layer.add_child(d)
        t += 0.55
    if to_grow.size():
        _toast(tr("STRINGS.UI.LEVELS.LETTER_NEW_COMING").replace("[[[title]]]", title_of(to_grow[0])))
```

要点：**线先长、块后弹、逐链串行**，即原游戏"生长"演出的三拍子；多子节点同帧并排画线即"横向连线"。

### 4.6 信箱与新信件

```gdscript
func _on_mailbox_clicked() -> void:
    mailbox.frame = 1                          # closed -> open（TextureRect 两帧或 AnimationPlayer）
    var news := model.unread_letters()         # 已解锁未读的节点
    if news.is_empty():
        _toast(tr("STRINGS.UI.LEVELS.LETTER_MAILBOX_EMPTY"))
    else:
        for i in news.size():                  # 6 种信封造型按角色/序号取
            spawn_envelope(news[i], i)
        refresh_growth()                       # 取信后触发链生长
```

### 4.7 点击关卡 → 小标题 + 跳转

```gdscript
func _on_block_clicked(key: String) -> void:
    var n := model.nodes[key]
    # 视口平滑定位
    var tw := create_tween()
    tw.tween_property(camera, "position", LevelSelect.to_screen(n.lane, n.dist), 0.6)\
      .set_trans(Tween.TRANS_CUBIC)
    # 信息窗：大标题 + 角色呼喊小标题 + 评级
    info.title.text = tr(n.title_key)          # 「我想回家」（80px 标题字体）
    info.title.add_theme_font_size_override("font_size", 80)
    info.subtitle.text = tr(n.subtitle_key)    # 「神啊请帮帮我」（40px）
    info.show_ranks(model.ranks_of(key))       # 已玩过的评级盖章
    info.popup()
    info.confirmed.connect(func():
        get_tree().change_scene_to_file("res://scenes/letter/letter_view.tscn")
        # 进入前把 level_id/side 写入全局 GameState
    )
```

小标题数据建议在自己关卡 JSON 里加一字段 `"SUBTITLE_KEY": "SUBTITLE_HELP_LW_HELPME"`（原游戏把映射放在代码/别表里，自建数据直接内聚更省事）。

---

## 5. 参数速查（还原手感用）

| 原值 | 建议 Godot 值 | 备注 |
|---|---|---|
| 线宽 10px | `width = 10`（2048 基准下） | 随视口缩放 |
| 弯角半径 37px | `corner = 37` | 圆角折线 |
| 泳道 -2/0/2 | Y 间距 150px | 三排平行链 |
| 距离单位 | X 间距 120px | 一屏 ≈ 半个视口宽 |
| 块弹出 | TRANS_BACK/EASE_OUT 0.35s | 弹性过冲 |
| 线生长 | 0.5s/段，EASE_OUT | 对原 8 帧动画 |
| 标题 80px / 小标题 40px | 同名 theme_font_size | 字体换开源（如思源宋/黑体） |

---

## 6. 版权提醒

- 机制（森林拓扑、泳道布局、管件折线、虚线 pending、三拍子生长演出）= 思想，可参考；
- `map01.png`、`mailbox_*`、`connecting_lines_*`、`levelblockv7_*` 等贴图与全部标题/呼喊语文本 = 受保护表达，**你的 Godot 项目须自绘/自写**（信封两态、圆角块、10px 圆角线这类通用造型自己画不构成问题，不要直接拷贝原图）；
- 字体：Fandol 系列为开源可用，汉仪润圆为商业字体不可用（见前次字体结论）。
