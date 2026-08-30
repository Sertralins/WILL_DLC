# 用 Godot 从零实现「信件重排叙事」玩法指南

> 日期：2026-08-21
> 本文档基于对《WILL：美好世界》数据格式与玩法机制的分析，提供用 Godot 独立实现同类玩法的完整参考。
> **玩法机制与数据结构不受版权保护，可自由参考实现；美术/音乐/剧情文本等受保护表达必须自己原创。**

---

## 1. 玩法机制完整解析（从游戏数据反推）

### 1.1 核心循环

1. 玩家收到一封信，由若干**句子**组成（单行信 3~5 句，双行信两侧各有句子）
2. 句子分三种类型：
   - **固定句**（TYPE=0）：位于信件首尾，不可移动
   - **可排序句**（TYPE=1）：玩家可拖拽重排
   - **条件句**（TYPE=2）：平时隐藏，排序达成条件后「触发」，替换/插入到信件中
3. 玩家重排句子后点击确认
4. 游戏用**条件表达式**逐条匹配，命中者触发对应**结局**（S/A/B…/Bad 多级评价）
5. 结局触发**句子替换**（REPLACE）：用条件句内容替换原句，信件含义完全改变
6. 玩家获得**声望值**（REP），跨关累积，影响后续解锁

> 玩法精髓：同一封信，不同排序 = 完全不同的人生。条件句是「蝴蝶效应」的载体。

### 1.2 双行信件（进阶机制）

- 信件有左右两行（两个角色互相通信，如 0002 关）
- 每行有独立的句子、前置关系、结局集合
- **句子可以跨行移动**：条件 `IN(L,L3)` = 「L3 在左行」，`IN(M,R2)` = 「R2 在中间缝位置」
- 左侧排序影响右侧结局，反之亦然——玩家要同时满足两边的条件

### 1.3 条件表达式语法（可直接移植）

从 63 关提取的全部表达式类型：

| 语法 | 含义 |
|---|---|
| `SS(A,B)` | A 排在 B **之前**（核心排序判定） |
| `SS(A,B,C)` | A、B、C 严格顺序排列 |
| `OS(A,B)` | A 紧邻 B 之前（相邻有序） |
| `OSS(A,B)` | A、B 相邻（顺序或逆序） |
| `S(A,B)` | A 与 B 相邻 |
| `IN(L,X)` / `IN(R,X)` | X 位于左行 / 右行 |
| `IN(M,X)` | X 位于中缝（两行交界处） |
| `X` / `!X` | 条件句 X 已触发 / 未触发 |
| `&&` `\|\|` `!` `()` | 标准布尔运算 |
| `CURRENT(0022,0,S1)` | 跨关引用：0022 关左行达到 S1 结局 |
| `SRANK(0001)` / `READ(0028,0)` / `STORY(X)` / `ACHIEVE(...)` | 解锁条件（S 评价/已读/剧情/成就） |

### 1.4 关卡结构（数据反推结果）

```
关卡 = {
  编号, 行数(1/2), 角色代码, 前置关卡, 屏幕位置,
  句子槽位[固定句|可排序句|条件句],
  结局集[评价等级, 句子替换, 声望值],
  条件列表[表达式 → 结局],       ← 按顺序匹配，首个命中生效
  解锁条件（引用其他关卡的进度）
}
```

---

## 2. Godot 项目架构建议

推荐 Godot 4.x + GDScript（数据结构简单，GDScript 完全够用）。

```
项目/
├── project.godot
├── data/                      ← 内容数据（JSON，可用 res:// 或 user:// 分发包）
│   ├── levels/0072.json       ← 每关一个文件（参考原游戏方案，方便 DLC 增量分发）
│   ├── dialog_rules.json      ← 规则库（如需要）
│   ├── profiles.json
│   └── levels_index.json      ← 关卡列表
├── locales/                   ← 本地化（Godot 原生 gettext）
│   ├── zh_CN.po
│   └── en.po
├── scenes/
│   ├── main.tscn              ← 主场景
│   ├── letter/
│   │   ├── letter_view.tscn   ← 信件视图（单行/双行布局）
│   │   ├── sentence_slot.tscn ← 句子槽位（可拖拽）
│   │   └── ending_popup.tscn  ← 结局演出
│   └── level_select.tscn
├── scripts/
│   ├── level_data.gd          ← 数据加载与模型（Resource 类）
│   ├── condition_engine.gd    ← 条件表达式解析/求值
│   ├── level_controller.gd    ← 关卡流程控制
│   ├── save_manager.gd        ← 存档（进度/声望/结局收集）
│   └── drag_controller.gd     ← 拖拽排序
└── art/  audio/               ← 原创素材
```

---

## 3. 数据 Schema 设计（自用版，参考原游戏改进）

```gdscript
# level_data.gd
class_name LevelData
extends Resource

@export var level_id: String          # "0072"
@export var row_count: int = 1        # 1 单行 / 2 双行
@export var left_char: String         # 角色代号
@export var right_char: String        # 双行时用
@export var unlock: String            # 解锁条件表达式

# 句子槽位（左右行分开）
@export var left_sentences: Array[SentenceSlot]
@export var right_sentences: Array[SentenceSlot]

# 结局与条件
@export var endings: Array[EndingDef]
@export var conditions: Array[ConditionEntry]
```

```json
// data/levels/0072.json —— 手写友好的格式
{
  "level_id": "0072",
  "row_count": 1,
  "left_char": "hero",
  "unlock": "SRANK(0071)",
  "left_sentences": [
    { "id": "L1", "type": 0, "text_key": "LEVEL.0072.L1" },
    { "id": "L2", "type": 1, "text_key": "LEVEL.0072.L2" },
    { "id": "L3", "type": 1, "text_key": "LEVEL.0072.L3" },
    { "id": "L4", "type": 0, "text_key": "LEVEL.0072.L4" },
    { "id": "L2_1", "type": 2, "text_key": "LEVEL.0072.L2_1" }
  ],
  "endings": [
    { "id": "S1", "rank": "S", "rep": 325,
      "replace": [ { "target": "L2", "with": "L2_1" } ] },
    { "id": "BAD1", "rank": "Bad", "rep": 0, "replace": [] }
  ],
  "conditions": [
    { "expr": "SS(L2,L3)", "ending": "S1" },
    { "expr": "SS(L3,L2)", "ending": "BAD1" }
  ]
}
```

**要点**：
- `text_key` 指向 `.po` 文件的 msgctxt（Godot `tr()` 直接可用）
- 条件句 type=2 平时不在界面上显示，触发后替换
- 结局按 rank 分级（S/A/B/C/Bad），rep 是声望增量
- 条件按数组顺序匹配，**首个命中生效**（原游戏行为）

---

## 4. 条件表达式引擎（GDScript 实现）

这是整个玩法的技术核心。建议实现：**分词 → 递归下降解析 → 求值**。

```gdscript
# condition_engine.gd
class_name ConditionEngine

# —— 求值上下文 ——
var order: Array[String]          # 当前句子顺序，如 ["L1","L3","L2","L4"]
var left_side: Array[String]      # 左行句子集合
var right_side: Array[String]
var triggered: Dictionary         # 条件句触发状态 { "L2_1": true }
var world_state: Dictionary       # 跨关状态 { "SRANK(0071)": true, ... }

# —— 分词器 ——
static func tokenize(expr: String) -> Array:
    var tokens := []
    var i := 0
    while i < expr.length():
        var c := expr[i]
        if c in "()!&|,":
            tokens.append(c)
            i += 1
        elif c.is_valid_identifier() or c.is_digit():
            var j := i
            while j < expr.length() and (expr[j].is_valid_identifier() or expr[j].is_digit()):
                j += 1
            tokens.append(expr.substr(i, j - i))
            i = j
        else:
            i += 1  # 跳过空白
    return tokens

# —— 递归下降解析器 ——
# 语法：
#   expr     := or_expr
#   or_expr  := and_expr ("||" and_expr)*
#   and_expr := unary ("&&" unary)*
#   unary    := "!" unary | primary
#   primary  := IDENT | IDENT "(" args ")"
# IDENT 求值为 true/false：
#   - "L2"      → triggered["L2"]
#   - "SS(...)" → 排序判定
#   - "IN(...)" → 位置判定
#   - "SRANK"/"CURRENT"/"STORY"/"READ" → world_state 查询

func evaluate(expr: String, ctx: Dictionary) -> bool:
    var tokens := tokenize(expr)
    var parser := _Parser.new(tokens, ctx)
    return parser.parse_or()
```

**求值函数对照**（与原游戏语义一致）：

```gdscript
func eval_ss(args: Array, ctx) -> bool:      # SS(A,B) A 在 B 前
    var order: Array = ctx["order"]
    var positions := {}
    for i in order.size():
        positions[order[i]] = i
    for k in args.size() - 1:
        var a: String = args[k].strip_edges()
        var b: String = args[k + 1].strip_edges()
        if not positions.has(a) or not positions.has(b):
            return false
        if positions[a] >= positions[b]:
            return false
    return true

func eval_in(args: Array, ctx) -> bool:      # IN(L,X) / IN(M,X)
    var side: String = args[0].strip_edges()
    var id: String = args[1].strip_edges()
    match side:
        "L": return ctx["order"].has(id) and ctx["left_side"].has(id)
        "R": return ctx["order"].has(id) and ctx["right_side"].has(id)
        "M": return ctx["middle_slot"] == id    # 中缝当前句子
    return false

func eval_os(args: Array, ctx) -> bool:      # OS(A,B) A 紧邻 B 前
    var order: Array = ctx["order"]
    var ia := order.find(args[0].strip_edges())
    var ib := order.find(args[1].strip_edges())
    return ia >= 0 and ib == ia + 1
```

**实现提示**：
- 原游戏的 `SS(A,B,C)` 是**严格顺序链**（A 在 B 前 且 B 在 C 前），不是全排列
- `!L2` 中 L2 是条件句触发状态，不是排序位置
- 双行信中 `order` 是**合并视图**（左右行 + 中缝），`IN(L/R/M,X)` 判定位置归属
- 表达式按关卡数据里的顺序求值，命中即停

---

## 5. 关键 UI 实现要点（Godot）

### 5.1 拖拽排序

```gdscript
# sentence_slot.gd 关键思路
# 方案 A：用 Control 的 _get_drag_data / _can_drop_data / _drop_data
#   句子槽位 = PanelContainer 子节点，拖动时传递自身 index
# 方案 B：手动 _gui_input 处理 InputEventMouseMotion + 按下状态，
#   计算目标槽位（position.y 对每个槽位中心做插入点判定），松手落位
# 双行信件：把中缝也做成一个合法落点（对应 IN(M,X) 条件）
```

推荐方案 A（Godot 内建拖放），注意：
- `_get_drag_data` 里 `set_drag_preview()` 显示句子快照
- 目标槽位高亮：`_can_drop_data` 时切换样式
- 固定句（TYPE=0）返回空数据，禁止拖动

### 5.2 结局演出与句子替换

确认排序后：
1. `ConditionEngine` 求值 → 命中结局
2. 按 `endings[命中].replace` 执行句子替换：被替换句子加删除线/打字机动画 → 条件句浮现
3. 播放结局文本（`tr()` 取本地化）、声望结算
4. 写入存档（关卡完成状态 + rank + rep 累积）

### 5.3 本地化（Godot 原生 gettext 支持，和原游戏同格式！）

Godot 4 原生支持 `.po` 文件——与原游戏格式一致，可以直接沿用「msgctxt 定位文本」的习惯：

```
# locales/zh_CN.po
msgctxt "LEVEL.0072.L1"
msgid "This is the first line."
msgstr "这是第一句。"
```

GDScript 中：`tr("LEVEL.0072.L1")`。也可以给 msgctxt 加上下文：`tr("L1", "LEVEL.0072")`。

### 5.4 存档

- Godot 4 用 `FileAccess` 存 `user://save.json`
- 建议结构：`{ "completed": {"0071": {"rank": "S", "rep": 325}}, "total_rep": 1200, "collected_endings": [...] }`
- 想防修改可用 `crypto` 类（Godot 4.4+ 有 `Crypto`，支持 AES-256-CBC）；原游戏是 Rijndael/AES-256-ECB + SHA256 密钥派生，Godot 里 CBC + 随机 IV 存头部更规范

### 5.5 内容管线（对标原游戏的分发结构）

```
data/levels/0001.json  …  0072.json    ← 每关一个文件
data/levels_index.json                  ← 关卡列表 + 解锁顺序
locales/zh_CN.po                        ← 文本全在 .po
art/cg/  art/spine/  audio/             ← 素材（原创！）
```

好处：新增关卡 = 新增一个 JSON + 若干 PO 条目，不需要动代码——这就是原游戏 DLC 的本质思路，你的游戏从一开始就天然支持扩展。

---

## 6. 原游戏数据可作「关卡设计参考」的部分

以下内容属于事实性数据/机制，可作为关卡设计灵感（**内容文本与美术不可复用**）：

- 63 关的难度曲线：单行 → 双行 → 跨行移动 → 复合布尔条件（从 `SS(L3,L2)` 逐步升级到 `!(R2&&S(L3,R2))&&L3&&!(L2&&S(L3,L2))&&!(!L2&&!R2)` 这种 4 层嵌套）
- 声望值设计：REP 集合 `{0,1,3,4,8,21,52,99,131,325}`，S 结局恒为 325
- 结局替换手法：REPLACE 单句替换，让「同一封信」产生「不同含义」
- 解锁链设计：`SRANK`/`STORY`/`CURRENT` 交叉引用制造网状解锁而非线性解锁

提取工具：`extract_bundles.py` + `_extracted/` 目录（全部关卡 JSON 在 `_extracted/text/leveldata-retail.bundle/`）。

---

## 7. 版权与合规提醒

- ✅ 可参考：玩法机制、数据结构设计思路、条件表达式语法、难度曲线思路
- ❌ 不可使用：原游戏的剧情文本、美术、音乐、字体、角色形象（均为受版权保护的表达）
- 用 Godot 从零实现自己的内容，与原游戏保持「机制相似但表达完全不同」即可
- 原游戏中的商业字体（汉仪润圆等）与开源字体（Noto、Ubuntu 等，OFL 协议可免费商用）要区分，使用前各自查证协议
