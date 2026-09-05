# 《WILL:美好世界》玩法原型 — 上手文档

> 本文档面向**刚接触这个项目(或 Godot)的同学**,说明目前已实现的功能、对应的代码、场景组件结构,以及背后的实现原理。读完可以快速理解项目,并知道从哪里开始改。

---

## 1. 项目简介

复刻解谜游戏《WILL:美好世界》的核心玩法:**拖动"字条"(白色字块)改变故事顺序,从而改写结局**。

当前已实现的玩法循环:

- 黑色**情节块**不可拖动,承载上下文剧情文字;
- 白色**字条**可拖动,右上角有角色小色块(洋红 = 角色A,蓝紫 = 角色B);
- 拖起字条 → 出现**虚影**跟随鼠标,原位置留下**灰色占位框**;
- 松手 → 字条**就近插入**松手位置,四周元素按统一间距**自动补位/让位**,并播放**回弹落座动画**;
- 拖到无效区域松手 → 字条**自动归位**;
- 拖动悬停到可放置位置时,下方元素**实时让位**(提前占位预览,松手前就能看到落位效果);
- **边缘吸附**:虚影靠近栏边缘 48px 内即可预览/落位,不必精确对准栏身;
- **拖拽自动滚屏**:按住字条拖向视图上下边缘,画布自动向该方向滚动;
- 游戏画布比屏幕高(2160 vs 1080),滚轮上下浏览;
- 右下角「执 行」按钮 → 结局(暂为占位文案);
- **内容数据化**:黑块/字条定义集中在 `data/levels/0001.json`,剧情文本在 `data/levels/0001.txt`(PO 格式),角色配色在 `data/characters.json`,改文案不用碰场景和代码;
- **信件阅览场景**(`scenes/letter/letter_reader.tscn`,F6 单独运行):打字机逐行显示信件,读完跳转主场景(见 7.4)。

---

## 2. 运行环境

| 项目 | 说明 |
|---|---|
| 引擎 | Godot **4.7**(Forward Plus) |
| 主场景 | `scenes/letter/letter_reader.tscn`(游戏从读信开始:逐封读完 → 排布 → 执行 → 新结局重放,见功能 #17) |
| 设计分辨率 | 1920 × 1080(`project.godot` → `window/size/viewport_width/height`) |
| 窗口缩放 | `canvas_items` + `expand`(不同窗口大小下 UI 等比缩放) |

---

## 3. 文件清单

| 文件 | 状态 | 作用 |
|---|---|---|
| `scenes/arrange/arrange_board.tscn` | ✅ 主场景 | 整个游戏画面:背景、滚动画布、左右故事栏、侧面板(**只有布局和样式,不含内容**) |
| `scripts/ui/arrange/arrange_board.gd` | ✅ 核心 | 关卡数据加载(JSON → 界面)、字条生成、执行按钮、兜底归位逻辑 |
| `scripts/game_state.gd` | ✅ 核心 | autoload 全局状态:当前天、数据文件路径、字条序列、判定结果(唯一可序列化对象) |
| `scripts/game_flow.gd` | ✅ 核心 | autoload 流程控制器:全项目唯一的场景切换入口 `goto()` |
| `scripts/rule_engine.gd` | ✅ 核心 | autoload 判定引擎:按序匹配 conditions → 应用 CHANGE → 写 GameState(历史/声望/图鉴) |
| `scripts/core/condition_engine.gd` | ✅ 核心 | 条件表达式引擎:SS/OS/OSS/S/IN/布尔/触发标记 + 跨关函数(判定与解锁共用) |
| `data/levels/0001.json` | ✅ 核心 | **关卡数据**(每关一个 JSON):句子定义(id + text_key)、结局表、判定条件 |
| `data/levels/0001.txt` | ✅ 剧情文本 | PO 格式(仿原版 strings.po):msgctxt 定位 + `[br]` 换行,**改文案只动这里** |
| `data/levels/levels_index.json` | ✅ 核心 | 关卡索引:关卡列表 + 起始关 |
| `data/characters.json` | ✅ 核心 | 角色档案:名字/配色/信纸背景(原版 PERSON 思路) |
| `scenes/letter/letter_reader.tscn` / `.gd` | ✅ 信件场景(主场景) | 打字机阅览信件:逐封阅读流程 / 执行后的重排序列(含 CHANGE 应用,读完进结算) |
| `scenes/verdict/verdict.tscn` / `.gd` | ✅ 结算场景 | 结局评级标签(S/A/B/C/D/E/Bad 配色)+ 声望结算 + 本关已解锁结局,读完返回排布 |
| `scripts/ui/arrange/card.gd` | ✅ 核心 | **字条组件**:拖拽、虚影预览、灰框、落座动画、防丢失 |
| `scripts/ui/arrange/drop_column.gd` | ✅ 核心 | 挂在左右两栏上:**接收拖入的字条,就近插入** |
| `project.godot` | ✅ | 项目配置(分辨率、缩放、主场景) |
| `assets/art/` | ✅ 素材 | 背景图(Gemini 生成) |
| `docs/reference/` | 📖 参考 | 玩法参考截图 `游戏关卡实例.png` |

> 2026-08-23 起项目采用分层目录结构,完整目录树见 `docs/文件结构与开发路线.md` §3。

---

## 4. 场景结构(scenes/arrange/arrange_board.tscn)

```
Main (Control, 全屏)                        ┐
├─ Background (TextureRect)                  │ 全屏背景图,Keep Aspect Covered 不变形
├─ BoardScroll (ScrollContainer)             │ 滚动容器:画布比屏幕高,滚轮浏览
│  └─ Board (Control, 1920×2160)             │ 游戏画布本体,高 = 2 倍屏幕
│     ├─ BoardBG (ColorRect)                 │ 画布底色(当前隐藏)
│     ├─ LeftColumn (VBoxContainer)          │ 左栏 = 角色A 的故事线
│     │  ├─ PanelA1 情节块 (不可拖)          │
│     │  ├─ [A1 字条] / [A2 字条] ← 运行时按 JSON 生成 │
│     │  └─ PanelA2 情节块 (弹性伸缩)        │
│     └─ RightColumn (VBoxContainer)         │ 右栏 = 角色B 的故事线
│        ├─ PanelB1 情节块 (不可拖)          │
│        ├─ [B1 字条] ← 运行时生成           │
│        └─ PanelB2 情节块 (弹性伸缩)        │
└─ SidePanel (右下角固定面板)                ┐
   └─ Box (VBox)                             │ 提示文字 +「执 行」按钮 + 结局文字
```

**布局关键点:**

- 两栏都是 `VBoxContainer`,统一间距 `separation = 16` —— 所有相邻元素(情节块↔字条↔字条)间距恒定;
- 上部情节块 `size_flags_vertical = 0`(高度固定);
- **最下面的情节块**(PanelA2/PanelB2)保持默认 `FILL` —— 它是"弹性块",字条插入/移走时由它吸收高度变化,这就是"补位"效果的来源;
- 字条**直接作为栏的子元素**插入(没有独立的"槽位"节点),位置由插入顺序决定;
- **内容与布局分离**:情节块里的 `Text` 节点在场景里是空的,文字由 `scripts/ui/arrange/arrange_board.gd` 启动时从 `data/levels/0001.json` 读入并填入(见 6.5 节)。

---

## 5. 已实现功能清单

| # | 功能 | 实现位置 |
|---|---|---|
| 1 | 字条拖拽(虚影跟随 + 0.6 半透明) | `scripts/ui/arrange/card.gd` `_get_drag_data()` |
| 2 | 拖起时原位置显示**灰色占位框** | `scripts/ui/arrange/card.gd` `_show_placeholder()` |
| 3 | 松手后灰框消失 | `scripts/ui/arrange/card.gd` `clear_placeholder()` |
| 4 | **就近插入**:松手后字条插到离鼠标最近的缝隙 | `scripts/ui/arrange/drop_column.gd` `_drop_data()` |
| 5 | 统一 16px 间距 + 自动补位/让位 | 栏的 `separation` + 弹性情节块 |
| 6 | 落座**回弹动画**(TRANS_BACK 缓动 + 淡入) | `scripts/ui/arrange/card.gd` `play_landing()` |
| 7 | 拖到无效区域 → **自动归位** | `scripts/ui/arrange/arrange_board.gd` 兜底 + `scripts/ui/arrange/card.gd` `return_to_origin()` |
| 8 | **防丢失看门狗**(字条永远不会消失) | `scripts/ui/arrange/card.gd` `_process()` |
| 9 | 大画布上下滚动(拖拽靠近边缘自动滚屏) | `scenes/arrange/arrange_board.tscn` `BoardScroll`(`scroll_deadzone = 60`) |
| 10 | 「执 行」按钮 → **真判定**:按条件表求值出结局(评级 + 声望) | `scripts/ui/arrange/arrange_board.gd` `_on_execute_pressed()` + `scripts/rule_engine.gd` |
| 11 | **数据驱动**:JSON 关卡数据加载 | `scripts/ui/arrange/arrange_board.gd` `_load_level()` / `_apply_level()` |
| 12 | **提前占位预览**:悬停可放置位置时,下方元素实时让位 | `scripts/ui/arrange/drop_column.gd` `update_preview_gap()` |
| 13 | **边缘吸附**:鼠标在栏边缘 48px 内也算悬停该栏 | `scripts/ui/arrange/arrange_board.gd` `_nearest_column_in_margin()` + `SNAP_MARGIN` |
| 14 | **拖拽自动滚屏**:鼠标靠近视图上下边缘时画布自动滚动 | `scripts/ui/arrange/arrange_board.gd` `_process()` + `AUTO_SCROLL_EDGE` / `AUTO_SCROLL_SPEED_UP` / `AUTO_SCROLL_SPEED_DOWN` |
| 15 | **字条顺序读取**:按数组读取每栏字条顺序,供结局判定 | `scripts/ui/arrange/arrange_board.gd` `get_strip_ids()` |
| 16 | 「执 行」→ 跳信件场景按**当前排列**打字机重放(从第一张字条开始,跳过顶部黑块),读完返回且排列/判定保留;**被 REPLACE 的句子在排布场景同步显示条件句新正文** | `scripts/ui/arrange/arrange_board.gd` + `scripts/ui/letter/letter_reader.gd`(review 模式) |
| 17 | 完整流程闭环:逐封读信(读完自动下一封)→ 排布 → 执行;**新解锁结局且 CHANGE 涉及条件句改动时**重放该行(REPLACE 换正文/DRA 删除),已解锁结局不再重放 | `scripts/ui/letter/letter_reader.gd` + `scripts/ui/arrange/arrange_board.gd` + `scripts/rule_engine.gd` |
| 18 | 结算场景:重放结束 → 评级标签 + 声望(增量/累计)+ 本关已解锁结局 → 返回排布 | `scenes/verdict/verdict.gd`(UI 代码构建) |

---

## 6. Godot 拖放系统原理(重点理解)

Godot 的 Control 拖放流程是一条固定的"链路",全部功能都挂在这条链上:

```
1. 鼠标在某 Control 上按下并拖动超过阈值
        ↓
2. 引擎调用该 Control 的 _get_drag_data()
   → 返回一个数据(这里返回字条自身 self)
   → set_drag_preview(控件) 设置的"虚影"开始跟随鼠标
        ↓
3. 拖动过程中,鼠标下方的最上层 Control 依次被询问
   can_drop_data(位置, 数据)
   → 注意:询问会【沿父链向上】:字条 → 栏 → 画布 → Main
   → 第一个返回 true 的节点就是"放置目标"
        ↓
4. 松手时,引擎调用放置目标的 _drop_data(位置, 数据)
        ↓
5. 引擎向拖拽发起者发送 NOTIFICATION_DRAG_END 通知
```

三个脚本各负责链条的一段:

| 链段 | 脚本 | 干什么 |
|---|---|---|
| 发起拖拽 | `scripts/ui/arrange/card.gd` | 记位置、放灰框、挂虚影、隐藏自己 |
| 接受放置 | `scripts/ui/arrange/drop_column.gd` | 栏内就近插入,恢复显示、清灰框、播放动画 |
| 兜底 | `scripts/ui/arrange/arrange_board.gd` | 拖到无效区域时,由 Main 接收并"归位" |

**两个必须知道的细节:**

- **`mouse_filter`**:子控件默认会拦截鼠标。字条内部的文字/色块/容器全部设成 `MOUSE_FILTER_IGNORE`,按下事件才会落到字条本体,拖拽才能触发;
- **拖拽期间不要移出场景树**:本项目早期曾把字条 `remove_child` 出树,导致"拖拽结束通知"不可靠、字条成为孤儿节点被引擎回收(看起来像消失)。现在改为**只隐藏(`visible = false`)**:容器会自动跳过隐藏子节点,布局效果相同,但字条始终在树里。

---

## 6.5 关卡数据文件(data/levels/0001.json)

> ⚠️ 2026-08-23 起关卡数据改用**新 Schema**(每关一个 JSON:行数组 rows + 条件句 variants + 结局表 endings + 判定条件 conditions,角色配色移入 `data/characters.json`,剧情文本在 `data/levels/0001.txt` PO 格式),见 `docs/文件结构与开发路线.md` §5。本节 JSON 示例为**旧格式**,仅作字段思路参考。

**所有可变内容集中在这一个 JSON 里**,改文案、加字条、换角色配色都只改它:

```json
{
	"level_id": "level_1",          // 关卡 id
	"title": "黑伞",                 // 关卡名
	"characters": {                  // 角色表:id → 名字 + 颜色(十六进制)
		"A": { "name": "角色 A", "color": "#905f80" },
		"B": { "name": "角色 B", "color": "#505070" }
	},
	"columns": [                     // 栏数组,每项对应场景里一个栏
		{
			"scene_node": "LeftColumn",   // 对应 scenes/arrange/arrange_board.tscn 里的节点名
			"character": "A",             // 本栏默认角色(字条没写 character 就用它)
			"header": "角色 A",           // 标题栏文字(需要栏里有名为 Name 的 Label)
			"blocks": [                   // 黑色情节块:按场景节点名填入文字
				{ "node": "PanelA1", "text": "　　下午六点,暴雨倾盆。\n..." },
				{ "node": "PanelA2", "text": "　　我冲进雨里…" }
			],
			"strips": [                   // 白色字条:按数组顺序从上到下生成
				{ "id": "A1", "text": "外面下着暴雨,我出门带上了黑伞。" }
			]
		},
		{
			"scene_node": "RightColumn",
			"character": "B",
			"header": "角色 B",
			"blocks": [ /* 同上结构 */ ],
			"strips": [
				{ "id": "A2", "text": "我走到玄关,发现伞架上是空的。", "character": "A" },
				{ "id": "B1", "text": "我浑身湿透了,冷得发抖。" }
			]
		}
	]
}
```

**字段约定:**

| 字段 | 说明 |
|---|---|
| `blocks[].node` | 必须与 `scenes/arrange/arrange_board.tscn` 里情节块节点名一致(如 `PanelA1`),文字填入该节点内部的 `Text` 子节点 |
| `strips[].character` | 可选;缺省用本栏的 `character`。决定右上角小色块的颜色 |
| `characters[].color` | 十六进制字符串(`#rrggbb`),Godot 的 `Color("#905f80")` 直接支持 |
| 换行 | 用 `\n` 转义,JSON 里不能直接敲回车 |

> 多关卡复用:在 `data/levels/` 新增 `0002.json`,并在 `data/levels/levels_index.json` 的 `levels` 数组登记即可(新 Schema 见 `docs/文件结构与开发路线.md` §5)。

---

## 7. 代码逐段讲解

### 7.1 `scripts/ui/arrange/arrange_board.gd` — 场景总控(数据加载)

```gdscript
# ArrangeBoard.gd — 《WILL:美好世界》核心玩法:拖动字条改变故事结局
extends Control

# 关卡数据(黑块文字、字条内容、角色配色)由 GameState 提供: 当前天的数据文件。
# 路径注册在 GameState.DAYS 里, 场景不再硬编码自己的数据路径(架构设计.md 第 5 节)。

const CardScript := preload("res://scripts/ui/arrange/card.gd")

# 字条文字色(界面样式常量,不属于关卡内容)
const COLOR_TEXT := Color(0.1, 0.1, 0.16)

# 拖拽时自动滚屏:鼠标进入视图上下边缘这个距离内开始滚动
const AUTO_SCROLL_EDGE := 90.0
const AUTO_SCROLL_SPEED_UP := 600.0    # 向上滚动最大速度(像素/秒)
const AUTO_SCROLL_SPEED_DOWN := 900.0  # 向下滚动最大速度(更快)

# 加载后的关卡数据
var level_data: Dictionary = {}

@onready var board_scroll: ScrollContainer = $BoardScroll
@onready var left_column: VBoxContainer = $BoardScroll/Board/LeftColumn
@onready var right_column: VBoxContainer = $BoardScroll/Board/RightColumn
@onready var execute_btn: Button = $SidePanel/Box/ExecuteButton
@onready var result_label: Label = $SidePanel/Box/ResultLabel

func _ready() -> void:
	execute_btn.pressed.connect(_on_execute_pressed)
	_load_level(GameState.current_level_path())

# 拖拽字条时,鼠标靠近视图上下边缘 → 画布自动向该方向滚动
func _process(delta: float) -> void:
	var vp := get_viewport()
	if vp == null or not vp.gui_is_dragging():
		return
	var card := vp.gui_get_drag_data() as Card
	if card == null:
		return
	var mouse := vp.get_mouse_position()
	var rect := board_scroll.get_global_rect()
	var dir := 0.0
	if mouse.y >= rect.position.y and mouse.y <= rect.end.y:
		if mouse.y < rect.position.y + AUTO_SCROLL_EDGE:
			dir = -1.0 + (mouse.y - rect.position.y) / AUTO_SCROLL_EDGE
		elif mouse.y > rect.end.y - AUTO_SCROLL_EDGE:
			dir = 1.0 - (rect.end.y - mouse.y) / AUTO_SCROLL_EDGE
	if dir == 0.0:
		return
	var speed := AUTO_SCROLL_SPEED_UP if dir < 0.0 else AUTO_SCROLL_SPEED_DOWN
	board_scroll.scroll_vertical += int(dir * speed * delta)
	# 画布移动后,鼠标相对画布的位置变了,刷新占位缝隙,保证预览不漂移
	var col := _nearest_column_in_margin()
	if col:
		col.update_preview_gap(card, col.get_local_mouse_position())

# —— 关卡加载:JSON → 界面 ——

func _load_level(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法打开关卡数据: %s" % path)
		return
	level_data = JSON.parse_string(file.get_as_text())
	if level_data == null or not (level_data is Dictionary):
		push_error("关卡数据解析失败: %s" % path)
		return
	_apply_level()

func _apply_level() -> void:
	var characters: Dictionary = level_data.get("characters", {})
	for col_data: Dictionary in level_data.get("columns", []):
		var column := _get_column(col_data)
		if column == null:
			continue

		# 0. 标题栏名字(若栏里有名为 Name 的 Label 则显示)
		var header := String(col_data.get("header", ""))
		if header != "":
			var name_label := column.find_child("Name", true, false) as Label
			if name_label:
				name_label.text = header

		# 1. 黑色情节块:按场景里的节点名填入文字
		for block: Dictionary in col_data.get("blocks", []):
			var panel := column.get_node_or_null(String(block.get("node", "")))
			if panel == null:
				push_warning("情节块节点不存在: %s" % String(block.get("node", "")))
				continue
			var text_label := panel.find_child("Text", true, false) as RichTextLabel
			if text_label:
				text_label.text = String(block.get("text", ""))

		# 2. 白色字条:按顺序生成
		var default_character := String(col_data.get("character", "A"))
		for strip_data: Dictionary in col_data.get("strips", []):
			var character := String(strip_data.get("character", default_character))
			_place_strip(
				column,
				String(strip_data.get("id", "")),
				String(strip_data.get("text", "")),
				_character_color(characters, character)
			)

# JSON 里的 scene_node → 场景节点
func _get_column(col_data: Dictionary) -> VBoxContainer:
	match String(col_data.get("scene_node", "")):
		"RightColumn":
			return right_column
		_:
			return left_column

# 角色 id → 颜色(缺省返回白色,便于一眼发现配置错误)
func _character_color(characters: Dictionary, key: String) -> Color:
	var info: Dictionary = characters.get(key, {})
	return Color(String(info.get("color", "#ffffff")))
```

**讲解:**
- `_load_level()` 负责读文件 + 解析 JSON;`_apply_level()` 负责把数据"灌"进界面;
- 黑块文字:JSON 的 `blocks[].node` 直接是场景节点名(`PanelA1` 等),按名找到面板,再 `find_child("Text")` 找到里面的文字标签填入;
- 字条:JSON 的 `strips[]` 数组按顺序生成,`character` 决定色块颜色(`_character_color` 从 `characters` 表查十六进制色值);
- **改内容 = 只改 JSON**,`scripts/ui/arrange/arrange_board.gd` 一行都不用动。

```gdscript
# 创建一张可拖拽字条:白色字块 + 右上角角色小色块,插到栏的最下面情节块之前
func _place_strip(column: VBoxContainer, id: String, text: String, color: Color, body_height: float = 86.0) -> void:
	var strip: Card = CardScript.new()
	strip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # 只占自身高度,不吸收栏内多余空间

	# 白色字块本体
	var white := StyleBoxFlat.new()
	white.bg_color = Color.WHITE
	white.content_margin_left = 14.0
	white.content_margin_right = 14.0
	white.content_margin_top = 10.0
	white.content_margin_bottom = 14.0
	strip.add_theme_stylebox_override("panel", white)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	strip.add_child(box)

	# 右上角小色块:标记字条属于哪个角色(不拦截鼠标,拖拽时跟着字条一起走)
	var tag_row := HBoxContainer.new()
	tag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(tag_row)
	var tag := ColorRect.new()
	tag.name = "Tag"
	tag.color = color
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.custom_minimum_size = Vector2(18, 18)
	tag_row.add_child(tag)

	# 字条文字
	var label := RichTextLabel.new()
	label.name = "Label"
	label.text = text
	label.fit_content = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.custom_minimum_size = Vector2(0, body_height)
	label.add_theme_font_size_override("normal_font_size", 22)
	label.add_theme_color_override("default_color", COLOR_TEXT)
	box.add_child(label)

	column.add_child(strip)
	column.move_child(strip, max(0, column.get_child_count() - 2))  # 插到最下面情节块之前
	strip.setup(id, text)
```

**讲解:**
- 字条结构:`PanelContainer`(白底) → `VBox` → 顶行 `HBox`(色块靠右) + 文字;
- **三个关键点**:① 内部所有子节点 `mouse_filter = IGNORE`(否则拖不动);② `size_flags_vertical = SHRINK_BEGIN`(字条只占自身高度,多余空间留给弹性情节块);③ 色块命名为 `Tag`、文字命名为 `Label`,供 `scripts/ui/arrange/card.gd` 通过 `find_child()` 查找。

```gdscript
# 读取一栏当前的字条顺序(自上而下),返回 id 数组——结局判定就靠它
func get_strip_ids(column: VBoxContainer) -> Array[String]:
	var ids: Array[String] = []
	for child in column.get_children():
		if child is Card:
			ids.append(child.card_id)
	return ids

# 点击"执行"按钮:读取两栏字条顺序(结局判定占位,后续在这里按顺序写分支)
func _on_execute_pressed() -> void:
	var left_order := get_strip_ids(left_column)
	var right_order := get_strip_ids(right_column)
	print("左栏字条顺序: ", left_order)
	print("右栏字条顺序: ", right_order)
	result_label.text = "【结局】左栏 %s | 右栏 %s（判定待实装）" % [str(left_order), str(right_order)]
```

**讲解:** 结局功能的挂载点。`get_strip_ids()` 把一栏的字条按自上而下顺序读成 id 数组(如 `["A2", "B1"]`),结局判定只需对 `left_order` / `right_order` 写 if 分支,例如 `if left_order == ["A1", "A2"] and right_order == ["B1"]: 进入某结局`。当前实现会打印并把顺序显示在侧面板上,方便调试。

```gdscript
# —— 兜底放置逻辑 ——
# 字条拖到无效区域时,放置目标链会一路向上找到 Main:
# 1) 若鼠标在某个栏的"吸附范围"内,把放置/预览转交给最近的栏;
# 2) 否则归位回原位置。
const SNAP_MARGIN := 48.0  # 吸附范围,与 scripts/ui/arrange/drop_column.gd 保持一致

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Card):
		return false
	# 悬停在栏的吸附范围内时,实时把占位缝隙交给最近的栏
	var col := _nearest_column_in_margin()
	if col:
		col.update_preview_gap(data as Card, col.get_local_mouse_position())
	return true

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var card := data as Card
	if card == null:
		return
	var col := _nearest_column_in_margin()
	if col:
		col.receive_drop(card, col.get_local_mouse_position())
		return
	card.return_to_origin()

# 找鼠标所在吸附范围内的最近栏(无则返回 null)
func _nearest_column_in_margin() -> VBoxContainer:
	var mouse := get_viewport().get_mouse_position()
	var best: VBoxContainer = null
	var best_d := INF
	for col: VBoxContainer in [left_column, right_column]:
		var rect := col.get_global_rect().grow(SNAP_MARGIN)
		if rect.has_point(mouse):
			var d := absf(mouse.x - rect.get_center().x)
			if d < best_d:
				best_d = d
				best = col
	return best
```

**讲解:** 第 6 节的"父链查找"最终会走到根节点 Main。Main 作为**全屏兜底接收器**,还负责**边缘吸附**:鼠标落在某栏外扩 48px 的范围内时,把预览和放置都转交给最近的栏(`update_preview_gap` / `receive_drop`);其他无效区域 → `return_to_origin()` 归位。栏的 `scripts/ui/arrange/drop_column.gd` 优先级更高(先被命中)。

---

### 7.2 `scripts/ui/arrange/card.gd` — 字条组件(拖拽核心)

```gdscript
# scripts/ui/arrange/card.gd — 可拖拽字条(白色字块 + 右上角角色小色块)
class_name Card
extends PanelContainer

@export var card_id: String = ""
@export var text_content: String = ""

@onready var label: RichTextLabel = find_child("Label", true, false) as RichTextLabel

# 拖拽前的原座位与顺序位置(归位/交换时使用)
var origin_slot: Node = null
var origin_index: int = 0

# 拖拽期间留在原位的灰色占位框
var placeholder: Control = null

# 落座动画的 Tween
var landing_tween: Tween = null

func _ready() -> void:
	update_view()

func setup(id: String, text: String) -> void:
	card_id = id
	text_content = text
	if is_node_ready():
		update_view()

func update_view() -> void:
	if label:
		label.text = text_content
```

**讲解:** `class_name Card` 让全项目可以用 `is Card` / `as Card` 判断类型;`card_id` 是字条的唯一标识(将来结局判定用);`origin_slot / origin_index` 记录"来处",归位时用。

```gdscript
# 1. 当鼠标在字条上按住并拖动时，Godot 自动调用此函数
func _get_drag_data(_at_position: Vector2) -> Variant:
	# 记住来处
	origin_slot = get_parent()
	origin_index = get_index()

	# 在原位放一个灰色占位框,标记字条原来的位置(松手后消失)
	_show_placeholder()

	# 虚化预览:白色字块 + 右上角同色小色块,跟随鼠标移动
	var preview := PanelContainer.new()
	# ...(构建一个半透明拷贝,结构同 _place_strip)...
	preview.modulate = Color(1, 1, 1, 0.6)
	set_drag_preview(preview)

	# 隐藏自己 → 灰框代替自己占住原位(不移出场景树,字条不会丢)
	visible = false

	# 返回自身，作为拖拽传递的数据
	return self
```

**讲解:**
- `set_drag_preview()` 的虚影是**临时拷贝**,引擎自动让它跟随鼠标、松手自动销毁;
- 字条本体只做 `visible = false`:容器布局会**跳过隐藏子节点**——占位框顶替它的位置,布局不塌(灰框高度 = `size.y`,与字条等高);
- 返回 `self` 作为拖拽数据,栏和 Main 都靠 `data is Card` 认出它。

```gdscript
# 在原座位放一个与字条等高的灰色占位框
func _show_placeholder() -> void:
	if placeholder == null:
		placeholder = PanelContainer.new()
		var gray := StyleBoxFlat.new()
		gray.bg_color = Color(0.6, 0.6, 0.65, 0.15)
		gray.border_color = Color(0.65, 0.65, 0.7, 0.9)
		gray.set_border_width_all(2)
		placeholder.add_theme_stylebox_override("panel", gray)
	placeholder.custom_minimum_size = Vector2(0, size.y)
	if origin_slot and is_instance_valid(origin_slot):
		origin_slot.add_child(placeholder)
		origin_slot.move_child(placeholder, origin_index)

# 移除灰色占位框(松手后调用)
func clear_placeholder() -> void:
	if placeholder:
		placeholder.queue_free()
		placeholder = null

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
```

**讲解:** 落座动画 = 缩放 1.12→1.0(`TRANS_BACK` 会"冲过头再弹回")+ 透明度 0.6→1.0 淡入,并行 0.22 秒。`is_running()` 防重复触发(松手后引擎还会补发一个拖拽结束通知,避免动画叠放)。

```gdscript
# 2. 归位:恢复显示并移除灰框;若因意外成了孤儿节点,则放回原座位
func return_to_origin() -> void:
	visible = true
	clear_placeholder()
	if not is_inside_tree() and origin_slot and is_instance_valid(origin_slot):
		origin_slot.add_child(self)
		origin_slot.move_child(self, mini(origin_index, origin_slot.get_child_count() - 1))
	play_landing()

# 3. 拖拽结束通知:正常路径之外的兜底
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		return_to_origin()

# 4. 看门狗:万一拖拽结束的所有路径都没触发,只要引擎已不在拖拽状态,
#    就恢复显示,保证字条永远不会"消失"
func _process(_delta: float) -> void:
	if not visible and is_inside_tree():
		var vp := get_viewport()
		if vp and not vp.gui_is_dragging():
			return_to_origin()
```

**讲解:** 三层保险,保证字条**绝对不会消失**:
1. 正常路径:拖到无效区 → Main 兜底 `_drop_data` → `return_to_origin()`;
2. 通知路径:引擎拖拽结束通知 `NOTIFICATION_DRAG_END` → 归位;
3. **看门狗**:只要"自己隐藏着 + 引擎已不在拖拽状态" → 自动归位。即使前两层全部失灵,最坏也只是延迟一帧恢复。

---

### 7.3 `scripts/ui/arrange/drop_column.gd` — 栏的放置逻辑(含提前占位预览)

```gdscript
# scripts/ui/arrange/drop_column.gd
# 挂在左右两栏上:栏内任意位置都是放置区。
# 拖动悬停时显示"提前占位"缝隙(下方元素实时让位,预览落位后的效果);
# 松手后字条落到缝隙所在位置,与预览完全一致。
# 另支持"边缘吸附":鼠标在栏边缘 SNAP_MARGIN 范围内也算悬停该栏。
extends VBoxContainer

# 吸附范围:鼠标离栏边缘这个距离内,也算悬停在该栏(与 scripts/ui/arrange/arrange_board.gd 保持一致)
const SNAP_MARGIN := 48.0

# 拖动悬停时显示的占位缝隙
var gap: Control = null

# 只有拖过来的是字条卡片时才允许放置。
# 同时:引擎在拖动中每帧都会带着鼠标位置调用本函数,借此实时更新占位缝隙。
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Card):
		return false
	update_preview_gap(data as Card, at_position)
	return true

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not (data is Card):
		return
	receive_drop(data as Card, at_position)

# —— 公开接口(scripts/ui/arrange/arrange_board.gd 的边缘吸附转发会调用) ——

# 放下字条:直接落到占位缝隙的位置,保证和预览一致
func receive_drop(card: Card, at_position: Vector2) -> void:
	card.visible = true       # 拖拽期间字条被隐藏,落下时恢复显示
	card.clear_placeholder()  # 松手后灰框消失

	if gap:
		# 有缝隙:字条顶替缝隙的位置(预览 = 落位,分毫不差)
		var idx := gap.get_index()
		_remove_preview_gap()
		var old_parent := card.get_parent()
		if old_parent and old_parent != self:
			old_parent.remove_child(card)
		elif old_parent == self and card.get_index() < idx:
			idx -= 1  # 隐藏的字条原本在缝隙之前,缝隙移除后其位置索引前移一位
		add_child(card)  # 若已在本栏,此调用无副作用
		move_child(card, idx)
	else:
		# 无缝隙(落点 = 原位置):按原逻辑就近插入
		var idx2 := _insert_index([card], at_position)
		var old_parent2 := card.get_parent()
		if old_parent2:
			old_parent2.remove_child(card)
		add_child(card)
		move_child(card, idx2)
	card.play_landing()  # 落座回弹动画

# 提前占位:在落点处放一个与字条等高的缝隙,把下面的字块/字条挤到落位后的位置
func update_preview_gap(card: Card, at_position: Vector2) -> void:
	# 在"旧缝隙仍占位"的布局下计算插入位置(与落位后布局一致,移动稳定不抖动)
	var idx := _insert_index([card, gap], at_position)
	# 落点就是字条原位置(灰框处)时,落位后布局不变,不显示缝隙
	if self == card.origin_slot and idx == card.origin_index:
		_remove_preview_gap()
		return
	if gap:
		# 旧缝隙当前的"过滤索引"(全索引 - 排在前面的被排除节点)
		var old_filtered := gap.get_index()
		if card.get_parent() == self and card.get_index() < gap.get_index():
			old_filtered -= 1
		if old_filtered == idx:
			return  # 位置没变,不重建
	_remove_preview_gap()
	gap = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.55, 0.75, 1.0, 0.15)
	style.border_color = Color(0.65, 0.85, 1.0, 0.8)
	style.set_border_width_all(2)
	gap.add_theme_stylebox_override("panel", style)
	gap.custom_minimum_size = Vector2(0, card.size.y)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gap)
	# 过滤索引 → 全列表索引:若隐藏的被拖字条排在目标位置之前,需后移一位,
	# 否则缝隙会插错位置(插不到最下面一张字条的下面)
	var full_idx := idx
	if card.get_parent() == self and card.get_index() < idx:
		full_idx += 1
	move_child(gap, full_idx)

func _remove_preview_gap() -> void:
	if gap:
		if gap.get_parent():
			gap.get_parent().remove_child(gap)
		gap.queue_free()
		gap = null

# 计算插入索引。
# 注意:先数"有效子元素总数"用于钳制——循环会提前 break,
# 边扫描边计数会得到错误的钳制值(字条会永远落到栏顶)。
func _insert_index(exclude: Array, at_position: Vector2) -> int:
	var total := 0
	for child in get_children():
		if not exclude.has(child):
			total += 1
	var idx := 0
	for child in get_children():
		if exclude.has(child):
			continue
		if at_position.y <= child.position.y + child.size.y * 0.5:
			break
		idx += 1
	# 不许放字条的位置:顶部标题区(0/1)与"最后情节块之后"(total);
	# 允许 2..total-1:顶部情节块之下、底部情节块之上的所有缝隙
	return clampi(idx, mini(2, total), total - 1)

# 每帧兜底:拖拽结束、或鼠标离开"本栏 + 吸附范围"时,清掉占位缝隙
func _process(_delta: float) -> void:
	if gap == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	if not vp.gui_is_dragging():
		_remove_preview_gap()
		return
	if not (vp.gui_get_drag_data() is Card):
		_remove_preview_gap()
		return
	if not get_global_rect().grow(SNAP_MARGIN).has_point(vp.get_mouse_position()):
		_remove_preview_gap()
```

**讲解:**
- 本脚本挂在**两栏的 VBoxContainer** 上(`scenes/arrange/arrange_board.tscn` 里 `LeftColumn` / `RightColumn` 的 `script` 属性),栏内任意位置松手都算"放进这一栏";
- **提前占位的核心**:拖动中鼠标在栏内移动时,引擎会**反复调用 `_can_drop_data(at_position, data)`**——借这个时机实时计算插入位置 `idx`,并在该处放一个**与字条等高的占位缝隙**。VBox 立即重排,下方元素被挤到"字条落位后"的最终位置,松手前就能预览效果;**松手后字条直接顶替缝隙的位置,预览与落位完全一致**(而不是重新按布局算一次索引);
- **缝隙高度 = 字条高度**,与最终插入的字条完全等高,所以预览位移与真实位移**分毫不差**;
- **落点 = 字条原位置**(灰框处)时不显示缝隙——因为落位后布局不变;
- `_insert_index()` 从上往下比较"落点与子元素中点"决定插入位置。**禁止的位置**:顶部标题区(0/1)与"最后情节块之后"(total);允许 2..total-1——顶部情节块之下、底部情节块之上的所有缝隙(含"最后一张字条下面")。**踩过的坑**:①钳制计数必须在循环前数总数——循环中途 `break` 后,边扫边数得到的计数是错的,会导致字条永远落在栏顶;②钳制上限曾写错,把下方位置挡掉,导致字条无法往下拖;③`_insert_index` 返回的是"排除被拖字条后的过滤索引",放进全列表前要换算(+1 当被拖字条在目标之前),否则缝隙永远插不到最下面一张字条的下面;
- **数据模型**:黑色情节块固定在场景里(顺序 = 场景中的排列,不随游戏变化);字条是栏的动态子元素,其顺序即视觉顺序,用 `scripts/ui/arrange/arrange_board.gd` 的 `get_strip_ids()` 直接读成数组,结局判定就按这个数组写分支。
- 缝隙的清理有三处:落位时(`_drop_data`)、拖拽结束 / 鼠标离开本栏时(每帧 `_process` 兜底检查 `gui_is_dragging()` 与鼠标位置)。

---

## 7.4 信件阅览场景(letter)

开场环节:**打字机逐行显示信件**,点击推进,读完浮现按钮跳转主场景。在编辑器里选中 `scenes/letter/letter_reader.tscn` 按 **F6** 单独运行。

**场景结构**(`scenes/letter/letter_reader.tscn`):

```
LetterReader (Control, script: scripts/ui/letter/letter_reader.gd)
├─ Background        信件背景图(assets/art/letter_bg_carlos.png),mouse_filter = IGNORE
├─ MarginContainer   文字区(锚点/颜色/字号按 `docs/reference/游戏信件实例.png` 设置:左 0.0714、上 0.2833、右 0.838、下 0.901;亮蓝白字 RGB(208,222,232);字号 38),mouse_filter = IGNORE
│  └─ Lines (VBox)   每行文字是运行时生成的 Label(逐行打字机)
└─ StartButton       "开始改变命运",读完淡入浮现 → GameFlow.goto("arrange")(全项目唯一的场景切换入口)
```

**点击状态机**(`_gui_input` 处理左键;所有文字子节点都设了 `mouse_filter = IGNORE`,点击会落到根节点):

| 当前状态 | 单击左键 |
|---|---|
| 正在打字(无符号) | **跳过**:立即显示整行,行尾出现 ▼ |
| 本行已完(▼ 可见,提示继续) | 开始下一行打字(▼ 收起) |
| 本页所有行已完 | **清空本页** → 显示下一页并开始打字 |
| 最后一页已完 | 淡入浮现"开始改变命运"按钮 |

> ▼ 在每行文字**打完后**出现在行尾,提示"点击继续剧情";下一行开始打字时收起;空行不显示 ▼;全部读完时收起,由跳转按钮接管。

**信件内容**:当前关卡对应行(rows[GameState.current_row])的**初始句子序列**(首固定块 → 字条 → 其余固定块,每句一页)——信件文本不再单独维护,与关卡数据同一来源(见 `docs/文件结构与开发路线.md` §5.5)。若某页行数 × `LINE_HEIGHT`(62px)超出信纸文字区高度 `PAPER_CONTENT_HEIGHT`(667px),启动时打印 `push_warning` 提示拆页。

---

## 8. 常见坑(踩过的,别重蹈)

| 坑 | 现象 | 原因与解法 |
|---|---|---|
| 字条点不动 | 拖拽无反应 | 内部子节点(文字/色块/容器)拦截了鼠标 → 全部设 `mouse_filter = IGNORE` |
| 拖动没有虚影 | 预览不出现 | 早期代码在字条 `remove_child` **之后**才 `set_drag_preview()`,而 `get_viewport()` 依赖节点在树中 → **先挂预览、后做隐藏/移除** |
| 字条松手后消失 | 孤儿节点被引擎回收 | 拖拽期间把字条移出场景树,拖拽结束通知不可靠 → 改为**只隐藏不移除**,另加看门狗兜底 |
| 间距忽大忽小 | 空槽位占位 | 早期"固定座位"方案中空座位永远占 134px → 改为**插入模型**,空位零占位 |
| 补位不生效 | 底下元素不动 | 弹性块(`size_flags_vertical = FILL`)才能吸收高度变化;把上方的固定元素设成 `SHRINK_BEGIN`(0) |
| 多张字条挤成一团 | 间距为 0 | 栏的 `theme_override_constants/separation` 控制统一间距,当前为 16 |
| 改了场景里的文字没反应 | 运行后文字被覆盖 | 内容已搬到 `data/levels/0001.json`,场景里的 `Text` 是空的、由 JSON 在启动时填入 |
| 字条总落到栏顶/位置不对 | 插入索引被错误钳制 | 曾用"扫描到一半的元素数"做钳制,循环提前 `break` 后计数不全 → **先数总数,再扫描**;钳制上限应为 `total`,曾误写 `total - 2` 挡掉最下方位置;且落位直接取缝隙索引,不重算 |

---

## 9. 从哪开始改(扩展指南)

| 想做的事 | 改哪里 |
|---|---|
| **加新字条 / 改文案** | 句子定义在 `data/levels/0001.json`(id + text_key),正文写进 `data/levels/0001.txt`(msgctxt = 关卡id_句子id),代码不用动 |
| **换角色 / 改配色** | `data/characters.json` → 对应角色的 `name` / `color`,颜色用 `#rrggbb` 十六进制 |
| **加新关卡(多关卡)** | `data/levels/` 加 `0002.json`,并在 `data/levels/levels_index.json` 登记 |
| **写结局判定** | 改 `data/levels/0001.json` 的 `conditions`(表达式如 `SS(A2,A1)`)与 `endings`(评级/声望/CHANGE),代码不用动 |
| **改统一间距** | `scenes/arrange/arrange_board.tscn` → `LeftColumn` / `RightColumn` 的 `theme_override_constants/separation` |
| **改落座动画手感** | `scripts/ui/arrange/card.gd` → `play_landing()`:初始缩放 `1.12`、时长 `0.22`、`TRANS_BACK` 缓动 |
| **改灰框样式** | `scripts/ui/arrange/card.gd` → `_show_placeholder()`:颜色、边框宽度 |
| **恢复彩色装饰带** | 参考 `docs/reference/游戏关卡实例.png`,在栏里给字条上下加同色 `ColorRect` |
| **换背景图** | `scenes/arrange/arrange_board.tscn` → `Background` 节点的 `texture`,或替换 `assets/art/` 里的图片 |
| **字条高度** | `scripts/ui/arrange/arrange_board.gd` → `_place_strip()` 的 `body_height` 参数(默认 86) |

---

## 10. 一句话架构总结

> **字条(`scripts/ui/arrange/card.gd`)只负责"自己怎么被拖";栏(`scripts/ui/arrange/drop_column.gd`)只负责"字条落到我这儿放哪";Main(`scripts/ui/arrange/arrange_board.gd`)负责"关卡数据加载 + 无效归位";文案与配色在 `data/levels/0001.json`;全局状态与数据路径在 `scripts/game_state.gd`(autoload);场景切换只走 `GameFlow.goto()`。** 布局交给 VBox 容器(统一间距 + 弹性块),拖拽交给 Godot 内建拖放系统(虚影 + 父链查找),动画交给 Tween,丢不了交给看门狗。
