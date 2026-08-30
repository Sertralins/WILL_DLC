# 选关判定链与存档数据结构（点击信箱 → 关卡浮现）

> 日期：2026-08-28
> 内容：点击信箱与关卡动画浮现之间的**判定逻辑**、关卡的**静态存储**、进度的**状态存储**，三者的数据结构，以及 Godot 4 复现代码。
> 依据：63 关关卡 JSON、`data.bundle` 数据表、`strings.po`、**真实存档文件**（`gamedata00/01.aes`、`systemdata.aes`）、游戏运行日志。

---

## 1. 总纲：游戏数据分两层，判定是纯函数

原游戏（也是你应该采用的）的架构只有两层：

```
┌─ 静态内容（只读，随包分发）──────────────────────┐
│ 关卡定义 JSON ×63 + LEVELS 索引 + BASICDATA      │
│ data.bundle 规则/图鉴表（DIALOG/PROFILES/…）      │
│ localization.bundle.* 的 strings.po（全部文本）   │
└──────────────────────────────────────────────┘
              │ 读取，永不修改
              ▼
┌─ 运行时状态（玩家进度，读写）────────────────────┐
│ gamedata00.aes / gamedata01.aes（两个槽位）       │
│ systemdata.aes（设置）                           │
└──────────────────────────────────────────────┘
              │
              ▼
判定 = 纯函数 f(状态, 静态内容) → { 节点可见性, 边样式, 动画序列 }
```

**关键推论**：点击信箱后的所有行为——哪些关卡浮现、实线还是虚线、谁先长谁后长——都是"当前存档状态"代入"静态关卡数据"求值的结果，没有额外的手写触发器。你复现时保持这个分离，逻辑会非常干净。

---

## 2. 关卡存储：静态数据

### 2.1 原游戏的存放方式

| 位置 | 内容 |
|---|---|
| `leveldata-retail.bundle/` | **每个关卡一个 TextAsset**：`0001.txt`…`0071.txt`（UTF-16LE JSON，共 63 关）；`LEVELS.txt` = 关卡号数组（决定地图顺序）；`BASICDATA.txt` = 全局表 |
| `data.bundle/` | 规则与图鉴表：`DIALOG`（3339 条规则/分镜包）、`PROFILES`（人物档案解锁表）、`ACHIEVEMENTS`（成就定义）、`ALBUM`（相册 CG 组）、`DOCUMENTS`（辞典词条）、`BGM`（每关音乐）、`BLOCKS`（句子高亮标记）、`DECORATIONS`、`BUTTONMAPPING`、`ICONS`、`LANGUAGE` |
| `localization.bundle.<lang>/` | `strings.po`：全部文本（含 UI 布局参数） |

这些文件游戏启动时全部读入内存，运行期间**只读**。DLC 的本质就是"再加一个 bundle/几个 JSON + PO 条目"。

### 2.2 关卡 JSON 里跟"选关"相关的字段（地图拓扑部分）

```json
{
 "LEVELID": "0004",
 "ROWCOUNT": 2,
 "LNAMECODE": "lw",   "RNAMECODE": "yang",
 "LPREVIOUS": "0002:R",   "LPOSITION": "0,4",
 "LPENDINGS": "0002:R(S1)&0003:L(S1,BAD2)",
 "LCONDITION": "ELLE(0002,1,S1)&&ELLE(0003,0,S1)",
 "RPREVIOUS": "start",    "RPOSITION": "0,13",
 "RPENDINGS": "0002:R(S1)&0003:L(S1,BAD2)",
 "UNLOCK": "SRANK(0001)",
 "SENTENCE": { … }, "LENDING": { … }, "CONDITION": [ … ]
}
```

地图相关字段的语义（上一文档已详述，这里给出数据结构视角）：

- **节点** = `"关卡号:行号"`，如 `"0004:L"`、`"0048:M"`；
- **实线边** = `LPREVIOUS`（`"start"` 表示从信箱长出的链根）；
- **虚线边（待定）** = `LPENDINGS`，格式 `来源(评级集合)&来源(评级集合)`，激活条件在 `LCONDITION`；
- **坐标** = `LPOSITION "泳道,距离"`（泳道 ∈ {-2,0,2}，距离沿生长轴单调）。

### 2.3 Godot 对应设计（每关一个 JSON + 索引 + 静态表）

```
data/
├── levels/0001.json … 0071.json      ← 每关一个（内容可增量分发）
├── levels_index.json                 ← 顺序与解锁门（对应 LEVELS+BASICDATA）
├── persons.json                      ← 角色配色表（对应 BASICDATA.PERSON）
├── profiles.json / achievements.json / album.json / documents.json
└── locales/zh_CN.po                  ← 全部文本（Godot 原生 gettext，与原游戏同格式）
```

关卡 JSON schema（含选关与判定所需全部字段）：

```json
{
  "level_id": "0004",
  "row_count": 2,
  "rows": {
    "L": {
      "character": "lw",
      "position": { "lane": 0, "dist": 4 },
      "parent": "0002:R",
      "pendings": [
        { "from": "0002:R", "ranks": ["S1"] },
        { "from": "0003:L", "ranks": ["S1", "BAD2"] }
      ],
      "title_key": "STRINGS.DIALOG.CONTENT.0004_LTITLE",
      "subtitle_key": "SUBTITLE_HELP_LW_AGAIN"
    },
    "R": { "character": "yang", "position": { "lane": 0, "dist": 13 },
           "parent": "start", "pendings": [] }
  },
  "unlock": "SRANK(0001)",
  "sentences": { … }, "endings": { … }, "conditions": [ … ]
}
```

> 原游戏把 `SUBTITLE_HELP_*` 的映射放在代码/别表里；你自己在关卡 JSON 里加 `subtitle_key` 字段更内聚。

---

## 3. 状态存储：存档的真实结构与判定谓词

### 3.1 原游戏存档实况（真实文件勘察）

存档目录：`%USERPROFILE%\AppData\LocalLow\4D Door Games\WILL_ A Wonderful World\`

| 文件 | 大小 | 说明 |
|---|---|---|
| `gamedata00.aes` / `gamedata01.aes` | 各 45,456 B（= 2841 × 16B，整块对齐） | **两个进度槽位**（内容不同、同尺寸，双槽轮换/自动+手动备份） |
| `systemdata.aes` | 26,160 B（= 1635 × 16B） | 系统设置（语言/音量/难度/分辨率/云同步开关） |
| `steam_autocloud.vdf` | 52 B | Steam 云存档配置（只含 accountid） |

- **加密**：C# `RijndaelManaged`（AES-256，密钥 = SHA256(UTF8(运行时密钥串))），密文是 BinaryFormatter 风格的序列化对象图。对 `gamedata00.aes` 按 16 字节分块统计，2841 块中 **427 个重复块**——典型的 **ECB 模式指纹**（CBC 下几乎不可能出现重复块）。明文无法离线读取（密钥运行时注入），但**格式本身不影响你理解其逻辑**。
- **运行日志佐证**（`Logs/AWW_*.log`）：结算时出现 `SetStat(STAT_DOCUMENTS, 8)`、`SetStat(STAT_READ_DOCUMENTS, 8)`、`UnlockAchievement()`——存档在结算时刻写入并同步 Steam 统计（收集计数）。

### 3.2 存档必须记录的状态（从全部判定谓词的用法反推）

所有 `UNLOCK`/`LCONDITION`/`PROFILES.CONDITION`/`ACHIEVEMENTS.PARAM2` 引用过的谓词，构成了存档内容的**需求清单**：

| 谓词 | 出现位置 | 读取的存档字段 | 语义 |
|---|---|---|---|
| `READ(0028,0)` | 解锁门、档案 | `rows["0028:L"].read` | 该行信**读过**（哪怕没解出结局） |
| `ACHIEVE(0036,1,BAD2)` | 解锁门、成就、档案 | `rows["0036:R"].achieved` | 该行**曾达成**某结局（历史性，永久） |
| `CURRENT(0013,0,S1)` | 解锁门 | `rows["0013:L"].current` | 该行**当前生效结局**（可被"切换结局"改变） |
| `SRANK(0001)` | 解锁门 | 该关各行 `achieved/current` | 该关整体达成过 S |
| `ELLE(0060,0,S1)` | 待定线条件、档案 | `rows["0060:L"].achieved` | 待定线专用：来源行曾达成该评级 |
| `STORY(STORY07A_0)` | 剧情门 | `story_flags` | 某剧情分镜已看过 |
| `ACHIEVE(…)\|\|…`（成就表） | 成就系统 | `achievements` | 成就达成集合 |
| （图鉴界面） | 收集 | `documents / album / profiles` | 辞典词条、相册 CG、人物档案收集 |
| （结算动画） | 声望 | `rows[..].rep` + `total_rep` | 每行 REP 与累计 |
| （地图演出只播一次） | **revealed** | `rows[..].revealed` | 该节点是否已经在地图上"长出来"过 |

存档内容的完整推断结构：

```
存档 = {
  rows: {                            # 每个关卡行一条
    "0004:L": {
      "read": true,                  # 读过信（信箱里的"新信件"标志由此决定）
      "achieved": ["S1", "A1", "BAD1"],  # 历史达成结局集合（永久累加）
      "current": "S1",               # 当前生效结局（切换结局可改）
      "rep": 325,
      "revealed": true               # 地图节点已长出（生长动画只播一次）
    }, …
  },
  story_flags: ["STORY07A_0", …],    # 剧情分镜看过集合
  achievements: ["FIRST_STEP", …],   # 成就集合
  documents: ["ALZHEIMER", …],       # 辞典词条收集
  album: ["EV001", …],               # 相册 CG 收集
  profiles: ["LW_01", …],            # 人物档案解锁
  total_rep: 5210
}
```

### 3.3 Godot 存档实现

```gdscript
# save_manager.gd
class_name SaveManager
extends Node

const SAVE_PATH := "user://save.json"
var data: Dictionary = new_game()

func new_game() -> Dictionary:
    return {
        "rows": {},
        "story_flags": [],
        "achievements": [],
        "documents": [],
        "album": [],
        "profiles": [],
        "total_rep": 0,
    }

func row(key: String) -> Dictionary:                    # key = "0004:L"
    if not data.rows.has(key):
        data.rows[key] = { "read": false, "achieved": [], "current": "",
                           "rep": 0, "revealed": false }
    return data.rows[key]

func save() -> void:
    var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    f.store_string(JSON.stringify(data, "\t"))

func load_save() -> void:
    if FileAccess.file_exists(SAVE_PATH):
        data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH)) or new_game()
```

- 用 JSON 明文即可；想防修改用 Godot 4.4+ `Crypto` 做 **AES-256-CBC + 随机 IV 存头部**（原游戏 ECB 是 2017 年的旧实现，CBC 更规范，不用照抄其弱点）。
- 双槽位：维护 `save.json` + `save.bak.json`，写新档前把旧档改名备份，防断电损坏（对应 `gamedata00/01`）。

---

## 4. 判定链：点击信箱 → 动画浮现

### 4.1 节点状态机

每个地图节点（关卡行）在"状态 × 静态数据"下有且仅有 5 个状态：

```
     解锁条件为真           信箱未取/未读           读过一次        解出结局
 hidden ────────────► available ───────────► new ────────► read ────────► cleared
（不显示）    UNLOCK/LCONDITION      （有"新信件"标条）  （信中）   （有评级，可重玩/切结局）
                    │                                        ▲
                    └── pending（条件不满足但来源已知）─────── 虚线边 ◄─┘
```

- `available` = `UNLOCK` 求值为真 **或** 待定线 `LCONDITION` 满足；
- `new` = available 且 `rows[key].read == false` ——**这就是"新信件"的唯一定义**；
- 从 `cleared` 回到 `read`：玩家点"切换结局"改变 `current`，依赖 `CURRENT` 的门随之重估（原游戏用 `CURRENT` 作门时确实支持这种"回溯改线"）。

### 4.2 谓词引擎（判定实现）

```gdscript
# predicates.gd —— 存档状态 → 判定谓词（对应原游戏 READ/ACHIEVE/CURRENT/SRANK/ELLE/STORY）
class_name Predicates
extends RefCounted

static func has_row(save: Dictionary, key: String) -> bool:
    return save.rows.has(key)

static func read(save: Dictionary, level_id: String, row_idx: int) -> bool:
    return save.rows.get(_key(level_id, row_idx), {}).get("read", false)

static func achieved(save: Dictionary, level_id: String, row_idx: int, rank: String) -> bool:
    return rank in save.rows.get(_key(level_id, row_idx), {}).get("achieved", [])

static func current(save: Dictionary, level_id: String, row_idx: int, rank: String) -> bool:
    return save.rows.get(_key(level_id, row_idx), {}).get("current", "") == rank

static func srank(save: Dictionary, level_id: String, levels: Dictionary) -> bool:
    var lv: Dictionary = levels[level_id]
    var rows: Dictionary = lv.get("rows", {})
    for side in rows:                              # 所有行都曾达成 S（自制时按需改为"主行即可"）
        if not achieved(save, level_id, _side_idx(side), "S1"):
            return false
    return true

static func elle(save: Dictionary, level_id: String, row_idx: int, rank: String) -> bool:
    return achieved(save, level_id, row_idx, rank)   # 待定线用历史达成判定

static func story(save: Dictionary, flag: String) -> bool:
    return flag in save.get("story_flags", [])

static func _key(level_id: String, row_idx: int) -> String:
    return "%s:%s" % [level_id, ["L", "R", "M"][row_idx]]
```

（`UNLOCK`/`LCONDITION` 表达式本身用《Godot从零实现指南》§4 的条件引擎求值，谓词函数注册进 `world_state`。）

### 4.3 点击信箱 → 浮现动画 的完整判定流程

```gdscript
# mailbox_flow.gd（节选）
func on_mailbox_clicked() -> void:
    # 第 1 步：求"新信件" = 已解锁 ∧ 未读
    var news := []
    for node in model.nodes.values():
        if _is_unlocked(node) and not node_data(node.key)["read"]:
            news.append(node)
    if news.is_empty():
        _toast(tr("STRINGS.UI.LEVELS.LETTER_MAILBOX_EMPTY"))
        mailbox.play_closed()
        return
    # 第 2 步：信箱展开，新信件以信封列出（6 种造型按角色取）
    mailbox.play_open()
    for i in news.size():
        spawn_envelope(news[i], i)          # 点击信封 → on_pick_letter(node)

func on_pick_letter(node) -> void:
    # 第 3 步：从该信沿 parent 边回溯到链根（"start"），得到要生长的路径
    var chain := []
    var cur := node
    while cur != null:
        chain.push_front(cur)               # 根在前
        cur = model.nodes.get(cur.parent)   # parent 为 "start" 时停止
    # 第 4 步：逐节点判定三种演出
    var t := 0.0
    for n in chain:
        var d := node_data(n.key)
        if d["revealed"]:                   # 已长过 → 跳过动画，只保证可见
            _ensure_block(n); t += 0.05; continue
        var parent_anchor := _anchor_of(n)  # 父块锚点 或 信箱锚点(按角色 LINE_START_POINT 偏移)
        _play_line_growth(parent_anchor, _block_pos(n), person_color(n.character), t)
        _play_block_pop(n, t + 0.4)         # 线画完 → 块弹出
        d["revealed"] = true                # ← 关键：只演一次，写进存档
        t += 0.55
    # 第 5 步：待定虚线边
    for n in chain:
        for e in n.pendings:
            var src := model.nodes[e.from]
            if src == null or not node_data(e.from)["read"]:
                continue                      # 来源都没读过 → 虚线也不画（避免剧透）
            var line := _make_line(_block_pos(src), _block_pos(n), true)  # dotted
            if Predicates.pending_met(e):     # ELLE 条件满足 → 实线 + 触发其生长
                line.solid = true
                _play_line_growth(…)
    # 第 6 步：标读 + 存档 + 清"新信件"标条
    node_data(node.key)["read"] = true
    SaveManager.save()
    mailbox.hide_new_badge()
    # 第 7 步：相机滚动定位到新信，弹标题/小标题信息窗（见上一文档 §4.7）
```

**判定要点小结**：

1. **浮现的判定** = `UNLOCK`/`LCONDITION` 表达式对存档求值，没有任何"硬编码关卡序号"的开关；
2. **生长只演一次**：`revealed` 标志持久化在存档里，重进游戏地图直接呈现、不再重播；
3. **虚线只在对玩家"有意义的时刻"出现**：来源行已读但评级未达成才画虚线，完全未知的来源不画；
4. **虚线转实线的时刻** = 来源行达成 `LPENDINGS` 括号里的评级（`ELLE`）——通常发生在结算返回地图时。

### 4.4 判定重估时机（什么时候跑 §4.3 的求值）

| 时机 | 触发 |
|---|---|
| 启动/载档后首次进地图 | 按存档还原（全部 revealed 节点直接显示） |
| 读信结算 → 返回地图 | `achieved/current/rep/story/collect` 变更 → 新节点浮现、虚线转实线 |
| 切换结局后 | `current` 变更 → 依赖 `CURRENT` 的门重估 |
| 点击信箱 | 过滤出 `new` 集合（信封装帧列表） |
| 收集/档案界面动作后 | 图鉴标记 |

---

## 5. 数据结构速查表（原游戏 ↔ Godot）

| 概念 | 原游戏 | 你的 Godot 项目 |
|---|---|---|
| 关卡定义 | TextAsset JSON（UTF-16LE），一关一文件 | `data/levels/XXXX.json`，一关一文件 |
| 关卡索引 | `LEVELS.txt`（数组）+ `BASICDATA.LEVELCOUNT` | `levels_index.json` |
| 角色配色 | `BASICDATA.PERSON[]`（FIG_COLOR 等） | `persons.json` |
| 文本 | `strings.po`（msgctxt 命名空间） | `locales/zh_CN.po` + `tr()` |
| 地图拓扑 | `LPREVIOUS/LPENDINGS/LCONDITION/LPOSITION` | JSON 内 `rows.{L,R}.{parent,pendings,position}` |
| 进度 | `gamedata00/01.aes`（AES-ECB 密文对象图） | `user://save.json`（或 CBC 加密）+ `.bak` 双槽 |
| 设置 | `systemdata.aes` | `user://settings.cfg`（Godot ConfigFile 原生） |
| 判定 | C# 条件引擎（运行时） | `condition_engine.gd` + `predicates.gd` |
| 新信件 | unlocked ∧ ¬read | 同左（`read` 布尔） |
| 生长只演一次 | 存档内 revealed 类标志 | `rows[key].revealed` |

---

。
