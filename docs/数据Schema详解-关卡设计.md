# 数据 Schema 详解：关卡设计篇

> 基于《WILL：美好世界》全部 63 关关卡数据的完整分析（2026-08-21）
> 面向：用 Godot 从零实现类似「信件重排叙事」玩法的开发者
> 样例数据位置：`_extracted\text\leveldata-retail.bundle\*.txt`（每关一个 JSON）

---

## 1. 总览

游戏共 63 关，每关一个 JSON 文件。按行数分三种规模：

| 行数 | 数量 | 说明 |
|---|---|---|
| 单行（ROWCOUNT=1） | 34 关 | 一封单人的信，3~11 句 |
| 双行（ROWCOUNT=2） | 28 关 | 两人通信，句子可跨行移动 |
| 三行（ROWCOUNT=3） | 1 关（0048） | 三人通信（pi/carlos/ying） |

字段族按行前缀命名：`L*`（左行）、`R*`（右行）、`M*`（中行，仅三行关卡）。字段名无前缀的（`SENTENCE`、`CONDITION`、`UNLOCK` 等）是关卡级通用字段。

---

## 2. 顶层字段速查表

| 字段 | 出现位置 | 含义 |
|---|---|---|
| `LEVELID` | 全部 | 关卡编号（4 位字符串，`"0001"`~`"0071"`） |
| `ROWCOUNT` | 全部 | 行数：1/2/3 |
| `UNLOCK` | 大部分 | 解锁条件表达式（见 §7） |
| `SENTENCE` | 全部 | 全部句子槽位定义（见 §4），左右中行共用此表 |
| `LNAMECODE` / `RNAMECODE` / `MNAMECODE` | 按行 | 该行角色代码 |
| `LCOUNT` / `RCOUNT` / `MCOUNT` | 按行 | 该行句子数（不含条件句） |
| `LPREVIOUS` / `RPREVIOUS` / `MPREVIOUS` | 按行 | 前置关系（见 §8） |
| `LPOSITION` / `RPOSITION` / `MPOSITION` | 按行 | 排版位置 `"列,行"` |
| `LENDING` / `RENDING` / `MENDING` | 按行 | 该行的结局集（见 §5） |
| `CONDITION` | 大部分 | 排序判定条件列表（见 §6） |
| `LCONDITION` / `RCONDITION` | 部分双行/三行 | 行级「历史结局延续」条件（见 §8） |
| `LPENDINGS` / `RPENDINGS` | 部分双行/三行 | 行级结局继承声明（见 §8） |
| `LIMIT` / `LIMITDESC` | 少数 | 规则限制系统（见 §9） |

---

## 3. 行系统：单行 / 双行 / 三行

### 单行（34 关）

只有 `L*` 字段族。信件 = 一条句子序列，玩家重排中间句。

### 双行（28 关）

`L*` 与 `R*` 并存，两侧信件独立又关联：

- 每侧有自己的句子、结局、条件
- **句子可跨行移动**：中缝（M）是一个合法落点，条件用 `IN(L,X)` / `IN(R,X)` / `IN(M,X)` 判断某句在左/右/中缝
- 一侧的排序影响另一侧的结局（条件表达式混合引用 L/R 句）
- 两侧的 `LPREVIOUS`/`RPREVIOUS` 通常引用**不同**的前置关卡（如 0006 关：L 行接 0005 左行，R 行接 0004 右行）

### 三行（仅 0048）

`L`（pi）+ `M`（carlos）+ `R`（ying）三行并存，句子可以跨全部三行移动。是双行机制的推广——**你在 Godot 里把行数做成数组而不是硬编码 L/R，即可天然支持任意行数**。

```json
// 0048 关键字段
"ROWCOUNT": 3,
"LNAMECODE": "pi", "MNAMECODE": "carlos", "RNAMECODE": "ying",
"LCOUNT": 4, "MCOUNT": 3, "RCOUNT": 4
```

---

## 4. 句子系统（SENTENCE）

### 4.1 结构与命名

```json
"SENTENCE": {
  "L1":   { "ID": "L1",   "TYPE": 0, "CONTENT_ID": "0001_L1" },
  "L2":   { "ID": "L2",   "TYPE": 1, "CONTENT_ID": "0001_L2" },
  "L4_1": { "ID": "L4_1", "TYPE": 2, "CONTENT_ID": "0001_L4_1" }
}
```

- **命名约定**：`<行前缀><序号>`（如 L1~L5、R1~R4、M1~M3）
- **条件句命名**：`<所属固定句>_<变体号>`（如 L4_1~L4_6 = L4 的 6 个变体，替换 L4 用）
- `CONTENT_ID` 指向 `strings.po` 的 `STRINGS.DIALOG.CONTENT.<CONTENT_ID>` 取文本
- 全 63 关统计：TYPE 0 共 202 个，TYPE 1 共 231 个，TYPE 2 共 394 个

### 4.2 TYPE 语义（核心！）

| TYPE | 角色 | 行为 |
|---|---|---|
| **0** | 固定句 | 信件首尾句，**不可移动**（观察 63 关：TYPE=0 恒为首尾句） |
| **1** | 可排序句 | 中间句，玩家可拖拽重排 |
| **2** | 条件句（变体句） | **隐藏**，不出现在初始信件中；结局触发 `REPLACE` 时替换/插入显示 |

> 设计本质：TYPE=0 是「语境框架」（开头结尾固定，保证信件始终成立），TYPE=1 是「可操纵的因果」，TYPE=2 是「被操纵的结果」——排序正确时，原本的句子被更优/更差的变体替换，信件含义因此彻底改变。

### 4.3 条件句（TYPE=2）深入讲解 —— 以 0001 关为例

**一句话定义：条件句 = 结局的「剧本变体」。它平时不在信里，只有玩家排序触发了某个结局时，才会被召唤出来替换掉原句，让信件变成另一个故事。**

以 0001 关（李雯的第一封信）为例。玩家**初始看到的 4 句**：

| 句子 | 类型 | 内容（简写） |
|---|---|---|
| L1 | 固定句 | 一个人在球场练球 |
| L2 | 可排序句 | 「灯闪了两下，突然灭了。」 |
| L3 | 可排序句 | 「离开网球场，走向来时经过的小巷子。」 |
| L4 | 固定句 | 在暗巷哼歌壮胆……回家发现钥匙丢了……「真是悲催呢」 |

数据里还藏着一个玩家**看不到**的第 5 句：

| 句子 | 类型 | 内容（简写） |
|---|---|---|
| **L4_1** | **条件句** | 小巷灯灭伸手不见五指 → 害怕，改走热闹街道 → 抓娃娃机 → 遇到神秘事件 → 回家安稳睡觉 |

**三步流程**：

```
第 1 步 玩家排序：把信排成 L1 → L3 → L2 → L4（L3 在 L2 前）
第 2 步 条件匹配：数据里的条件 SS(L3,L2) 命中 → 触发 S1 结局
第 3 步 句子替换：S1 结局的 CHANGE = REPLACE L4_1

初始信件：  L1 → L2 → L3 → L4   （钥匙丢了，悲催）
                          ↓ 结局触发替换
S 结局信件：L1 → L3 → L2 → L4_1 （改走热闹街道，遇到神秘事件）
```

同一封信，排序不同 → 触发不同结局 → 结尾句被替换成不同变体 → **故事完全变了**。

**数据视角**（对应关系）：

```json
"SENTENCE": {
  "L4":   { "ID": "L4",   "TYPE": 0, "CONTENT_ID": "0001_L4" },
  "L4_1": { "ID": "L4_1", "TYPE": 2, "CONTENT_ID": "0001_L4_1" }
},
"LENDING": {
  "S1":   { "RANK": "S",   "CHANGE": [{ "TYPE": "REPLACE", "DATA": "L4_1" }], "REP": 325 },
  "BAD1": { "RANK": "Bad", "CHANGE": [{ "TYPE": "REPLACE", "DATA": "L4" }],   "REP": 0 }
}
```

**关键点**：

1. **条件句永远挂靠在一个固定句下**，命名约定 `<固定句ID>_<变体号>`：`L4_1` 就是 L4 的 1 号变体
2. **TYPE=2 不进初始信件**——游戏加载关卡时只显示 TYPE=0 和 TYPE=1 的句子
3. **条件句只能通过结局的 `REPLACE` 指令出场**——它不会自己「因为条件满足而自动出现」；排序条件只决定触发哪个结局，结局才决定召唤哪个变体
4. `BAD1` 结局里也有 `REPLACE L4`——用 L4 替换 L4，等于**保持原样**（「什么都没改变」的坏结局）
5. 一个固定句可以有多个变体：0048 关的 L4 有 **L4_1~L4_6 六个条件句**，对应六个不同结局、六个不同走向

**常见误区**：

- ❌ 「条件句是条件满足后才显示出来的隐藏句」
- ✅ **条件句是结局的产物，不是条件的产物**——排序条件只决定触发哪个结局；条件句是被结局「替换进去」的句子

**Godot 实现映射**：

```gdscript
# 加载关卡：只显示 type != 2 的句子
func _init_slots() -> void:
    for s in level.sentences:
        if s.type != 2:
            add_slot(s)          # 条件句不创建 UI 槽位，只留在数据表里待命

# 结局结算：执行 CHANGE 指令序列
func _apply_ending(ending: EndingDef) -> void:
    for change in ending.changes:
        match change.type:
            "REPLACE":
                var variant = level.get_sentence(change.data)   # 取出条件句
                _replace_slot(variant.base_id(), variant)        # 替换原句 UI + 数据
            "DRA", "D":
                _remove_slot(change.data)                        # 删除句子
```

---

## 5. 结局系统（LENDING / RENDING / MENDING）

```json
"LENDING": {
  "S1":   { "ID": "S1", "RANK": "S",
            "CHANGE": [{ "TYPE": "REPLACE", "DATA": "L4_1" }],
            "REP": 325 },
  "BAD1": { "ID": "BAD1", "RANK": "Bad",
            "CHANGE": [{ "TYPE": "REPLACE", "DATA": "L4" },
                       { "TYPE": "DRA", "DATA": "L5" }],
            "REP": 0 }
}
```

### 5.1 RANK 与 REP（声望）映射

从 63 关全部结局统计出的设计表：

| RANK | 含义 | REP 值 |
|---|---|---|
| S | 最佳 | **325**（标准）/ 131 / 1 |
| A | 优 | **131** / 52 / 1 |
| B | 良 | **52** / 1 |
| C | 中 | **21** / 1 |
| D | 差 | **8** / 4 / 1 |
| E | 很差 | **3** / 1 |
| Bad | 坏 | **0**（标准）/ 1 / 99（特殊） |
| Z | 隐藏结局 | 1（如 0028 的真结局 Z1） |

规律：**等级制奖励曲线** 325 → 131 → 52 → 21 → 8 → 3，S 是 A 的 ~2.5 倍，逐级递减；「通关系数」1 分打底；Bad 默认 0。你设计自己的声望表时可以沿用这个对数递减思路。

### 5.2 CHANGE（结局引发的信件修改）

| TYPE | 语义 | 样例 |
|---|---|---|
| `REPLACE` | 用 `DATA` 指定的句子**替换**同编号句子 | `{"TYPE":"REPLACE","DATA":"L4_1"}` = 用 L4_1 替换 L4 |
| `DRA` | **删除** `DATA` 指定的句子（信变短，剧情上"这封信没写完/被撕了"） | 0003 关 BAD1：替换 L5 后又删除 L4 |
| `D` | 删除变体（同 DRA，不同上下文使用） | 0010 关 |

CHANGE 是**数组**，可组合多个修改（先 REPLACE 再 DRA）。还有 `"DATA": "a00"` 这类非句子 ID 的特殊标记（与 UI 成就标记相关，制作时忽略即可）。

---

## 6. 条件系统（CONDITION）—— 玩法核心

### 6.1 条目结构

```json
"CONDITION": [
  { "CONDITION": "SS(L3,L2,L4)", "ENDING": "S1", "SIDE": "L", "ID": 1 },
  { "CONDITION": "!SS(L3,L2,L4)&&!S(L4,L3)", "ENDING": "BAD1", "SIDE": "L", "ID": 2 },
  { "CONDITION": "S(L5,L2)&&S(L4,L2)&&S(L2,L3)&&ELLE(0067,0,S1)&&CURRENT(0021,1,S1)",
    "ENDING": "S1", "SIDE": "L", "ID": 1,
    "FILTER": "ELLE(0067,0,S1)&&CURRENT(0021,1,S1)",
    "FALLBACK": "BAD3" }
]
```

- **按数组顺序匹配，首个满足者生效**（ID 即优先级）
- `SIDE`：`L` / `R` / `M`，指明该条件判定哪一行的结局
- 单关最多 29 条条件

### 6.2 排序函数

| 函数 | 语义 | 例 |
|---|---|---|
| `SS(A,B)` | A 排在 B 之前 | `SS(L3,L2)` = L3 在 L2 前 |
| `SS(A,B,C)` | 严格顺序链：A 前 B 前 C | `SS(L3,L2,L4)` |
| `OS(A,B)` | A **紧邻** B 之前 | `OS(L2,L3)` |
| `OSS(A,B)` | A、B 相邻（不分前后） | |
| `S(A,B)` | A、B 相邻 | `S(L4,L3)` |

### 6.3 位置函数（跨行判定）

| 函数 | 语义 |
|---|---|
| `IN(L,X)` | X 句当前位于**左行** |
| `IN(R,X)` | X 句位于**右行** |
| `IN(M,X)` | X 句位于**中缝**（双行信件的分界处） |
| `!IN(...)` | 取反 |

> 实现提示：内部维护一个**合并序列**（左右行 + 中缝的完整顺序），`IN` 查询句子所在区域，`SS/OS/S` 查询合并序列中的相对位置。

### 6.4 条件句触发标记

- `L2` = 条件句 L2 已触发（被 REPLACE 出来）
- `!L2` = 未触发
- 可与布尔运算组合：`!L2&&!R3`、`L2&&R2`

### 6.5 跨关历史函数（网状剧情的关键）

| 函数 | 语义 |
|---|---|
| `CURRENT(0022,0,S1)` | 0022 关**第 0 行（L 行）**曾达成 S1 结局（`1`=R 行，`2`=M 行） |
| `ELLE(0067,0,S1,A1,BAD2)` | 0067 关 L 行结局 ∈ {S1, A1, BAD2}（**列表**判定） |
| `SRANK(0001)` | 0001 关达成 S 评价 |
| `STORY(STORY07A_0)` | 看过某剧情片段 |
| `READ(0028,0)` | 读过 0028 关 |
| `ACHIEVE(0025,1,A1)` | 成就 |

### 6.6 FILTER / FALLBACK（结局回退机制）⭐

部分条目带这两个字段，实现「同样的排序，不同历史 → 不同结局」：

- `FILTER`：条件中与**其他关卡结局历史**相关的子表达式
- `FALLBACK`：FILTER 不成立时回退到的结局 ID

语义：排序条件满足、但历史条件（FILTER）不满足时 → 触发 `FALLBACK` 结局。

例（0068 关）：
```json
{ "CONDITION": "S(L5,L2)&&S(L4,L2)&&S(L2,L3)&&ELLE(0067,0,S1)&&CURRENT(0021,1,S1)",
  "FILTER": "ELLE(0067,0,S1)&&CURRENT(0021,1,S1)",
  "FALLBACK": "BAD3" }
```
玩家排对了顺序，但如果 0067 关没打 S1、0021 关没打 S1 → 不能看 S 结局，回退到 BAD3。**这就是「历史影响现在」的实现方式。**

### 6.7 完整语法（EBNF）

```
expr     := or_expr
or_expr  := and_expr ("||" and_expr)*
and_expr := unary ("&&" unary)*
unary    := "!" unary | primary
primary  := IDENT | FUNC
FUNC     := NAME "(" ARG ("," ARG)* ")"
IDENT    := 句子ID | 条件句ID     ← 布尔（触发状态）
NAME     := SS | OS | OSS | S | IN | CURRENT | ELLE | SRANK | STORY | READ | ACHIEVE
```

---

## 7. 解锁系统（UNLOCK）

63 关的 UNLOCK 表达式统计出的设计模式：

| 模式 | 例 | 设计意图 |
|---|---|---|
| 单关 S 评价 | `SRANK(0005)` | 线性进阶 |
| 双关 S 评价 | `SRANK(0004)&&SRANK(0025)` | 多线汇合 |
| 双行都 S | `CURRENT(0002,0,S1)&&CURRENT(0002,1,S1)` | 要求一关的两侧都打满 |
| 多关多行 | `CURRENT(0035,0,S1)&&CURRENT(0035,1,S1)&&CURRENT(0055,1,S1)&&CURRENT(0055,0,S1)` | 剧情大汇合 |
| 或条件 | `CURRENT(0056,0,S1)\|\|CURRENT(0056,0,S2)` | 任一线索即可 |
| 非条件 | `!CURRENT(0028,1,Z1)` | **没达成某结局才解锁**（隐藏剧情分叉！） |
| 剧情/成就 | `STORY(STORY07A_0)`、`ACHIEVE(...)` | 收集驱动 |

> 精华：`!CURRENT(...)` 的用法——解锁条件可以引用「未发生的结局」，用来区分两条互斥的剧情线。

---

## 8. 行级剧情延续（LPREVIOUS / PENDINGS / LCONDITION）

### 8.1 LPREVIOUS / RPREVIOUS（前置行引用）

```
"LPREVIOUS": "0002:L"    ← 本行接续 0002 关的左行
"LPREVIOUS": "start"     ← 剧情线的起点（信件系列的第一封）
```

语义：本行信件是所引用行那封信的**下一封**（同一条通信线）。`0048:M` 这种三行引用也存在。

### 8.2 PENDINGS + LCONDITION（历史结局继承）

出现在双行/三行关卡中：

```json
"RPENDINGS":  "0004:R(S1,A1,BAD1,BAD2,BAD3,BAD4,BAD5)",
"RCONDITION": "ELLE(0004,1,S1,A1,BAD1,BAD2,BAD3,BAD4,BAD5)"
```

语义：**这一行的剧情内容取决于它所续接的那一行在历史关卡中达成了哪个结局**。`RCONDITION` 声明「历史结局必须在集合中」，`RPENDINGS` 声明「本行继承自这些结局」。配合 §6.6 的 FILTER/FALLBACK 使用，形成完整的剧情分支网。

---

## 9. LIMIT 限制系统（规则教学/特殊机制）

```json
"LIMIT": [
  { "TYPE": "CONFLICT", "DATA": ["L2", "R2"] }
],
"LIMITDESC": [
  { "TYPE": "RULETYPE_CONFLICT", "CONTENT": "RULE_CY04JI03_0" }
]
```

- `LIMIT`：规则限制。`CONFLICT [L2, R2]` = L2 与 R2 **互斥**（不能同时满足某种位置关系，如不能同时在中缝/同侧）
- `LIMITDESC`：规则说明文本引用，`CONTENT` 指向 `strings.po` 的 `STRINGS.DIALOG.CONTENT.<CONTENT>`，UI 上向玩家展示这条规则（教学用途）
- 对应数据包 `data.bundle/DIALOG.txt` 的 `CONTENT` 规则库（3339 条规则定义，如 `RULETYPE_CONFLICT → {"PARAM1": "letter"}`）

> 设计启示：LIMIT 可以用来做「特殊玩法关卡」——先教玩家一条新规则（LIMITDESC 展示），再用 CONFLICT 限制约束排序空间。

---

## 10. 排版字段（LPOSITION）

`"列,行"` 格式，控制信件在「世界地图/信件墙」上的显示位置：

- 常见：`"0,3"` ~ `"0,9"`（第一列竖直排布）
- 双行关卡的左右行用不同行号（如 L 在 `"0,3"`、R 在 `"0,6"`）
- 特殊：`"-2,3"`（负列，屏幕外/隐藏区域）、三行关卡用 `"0,30"`、`"0,78"` 等大行号（信件墙上的纵向布局）

Godot 实现：这是纯 UI 布局数据，用 GridContainer 或手写坐标映射即可，无需照搬。

---

## 11. 完整样例速查

- **单行 + DRA + 多 Bad 结局**：`0003.txt`（本章 §5 引用）
- **双行 + LIMIT + ELLE + FILTER/FALLBACK**：`0006.txt`
- **三行**：`0048.txt`
- **S 评价表**：`LEVELS.txt`（关卡列表）、`BASICDATA.txt`（`LEVELCOUNT: 63`）

---

## 12. 给 Godot 实现者的设计要点总结

1. **行数做成数组**（`rows: [left, right, middle?]`），单行只是数组长度为 1 的特例——不要为 1/2/3 行分别建模
2. **条件引擎三要素**：合并序列（所有句子的当前顺序）+ 触发状态表（条件句）+ 世界状态表（历史结局/评价/剧情）——`SS/IN/CURRENT/ELLE` 全部只需这三张表
3. **结局 = 修改指令序列**：`CHANGE` 数组（REPLACE/DRA）天然支持"同信件多结局的渐变质变"
4. **历史影响现在的三种手法**：`CURRENT`（单点判定）、`ELLE`（集合判定）、`FILTER/FALLBACK`（回退）
5. **解锁用同一套表达式引擎**（UNLOCK 与 CONDITION 同语法）——引擎一次实现，两处使用
6. **REP 声望用对数递减曲线**，S 结局固定高值（325），Bad 默认 0，普通通关保底 1
7. **文本与数据分离**：所有句子文本走 `.po`（CONTENT_ID → msgctxt），关卡 JSON 只存引用——这让你在 Godot 里能直接用 `tr()` 做本地化，也能独立维护剧情文本
