# 仇有余骨骼待机样例

## 先看效果

在 Godot 打开 `tools/qyy_spine_preview.tscn`，按 **F6**。

- 空格：播放 / 暂停。
- 左右方向键：每次前后移动 0.125 秒。
- 动作名 `idle`，8 秒循环。胸口呼吸、头部和袖口微动，脚底保持原位。
- `data/characters.json` 的 `qyy.anim` 已指向 `scenes/xl/qyy_anim.tscn`，读信、排列界面均通过现有 `CharacterAnim` 加载。
- 动画框仍为 512×1024，底部对齐。场景外层管理入场滑动，待机骨骼不负责移动整个动画框。

## 交付文件

| 文件 | 用途 |
| --- | --- |
| `assets/spine/qyy/qyy.json` | Spine 4.2 格式骨骼、加权网格和动画时间线 |
| `assets/spine/qyy/qyy.atlas` | 单页纹理图集信息 |
| `assets/spine/qyy/qyy.png` | 原始透明剪影第一帧的逐字节副本 |
| `scenes/xl/qyy_anim.tscn` | 游戏内使用的角色动画场景 |
| `scripts/ui/qyy_mesh_preview.gd` | 此样例的 Godot 播放器 |
| `tools/build_qyy_spine.py` | 可重复生成资源的脚本 |

骨骼共 7 根：root、hips、chest、head、arm_left、arm_right、hair。网格 561 个顶点、1024 个三角形；单张 RGBA8 贴图的未压缩像素量约 2 MiB，不含网格、引擎对象和 GPU 其他开销。

这是单张剪影的骨骼网格变形，保留原轮廓并增加柔和待机。不是原有 240 帧动作的逐帧复刻。抬手、挠头、转身需要拆分身体部件、补画遮挡区域，再另外制作动作。

## 在 Spine 中继续编辑

1. 使用 Spine **4.2** 的“导入数据 / Import Data”导入 `qyy.json`。
2. 图片路径指向该 JSON 所在目录，图片名称为 `qyy.png`。
3. 选择 `idle` 动画。网格和权重编辑需要支持这些功能的编辑器版本。
4. 在 Spine 中另存为原生 `.spine` 工程。

此处交付的是 JSON 数据，不是 `.spine` 原生工程。本机未找到 Spine 编辑器，因此尚未完成编辑器内打开、保存验证。已用官方 `@esotericsoftware/spine-core@4.2.120` 成功读取 JSON、atlas 和动画，并比对六个时间点的全部顶点。

官方格式支持将 JSON 数据导回编辑器：[Spine JSON 格式](https://esotericsoftware.com/spine-json-format)。

## Godot 播放方式与边界

目前游戏使用项目自行编写的专用播放器，读取同一份 JSON 的骨骼和时间线。仅支持本样例使用的父子骨骼、旋转、平移、线性关键帧和单张加权网格；**不是通用 Spine 插件**。不要将任意 Spine 导出文件直接替换进来。

如果在 Spine 中加入 IK、切换附件、曲线插值、缩放或其他特性，应接入对应版本的官方 Godot Spine 运行库，并替换动画场景内部播放器；外层 Control 的 512×1024 设计画布与 CharacterAnim 接口可继续使用。

打包游戏时，应确保 `assets/spine/qyy/qyy.json` 被包含进导出包（非资源过滤器可加入 `*.json`）。当前没有新增或修改发布预设，尚未验证发布包。

官方运行库仅安装在系统临时目录用于格式验证，没有被加入游戏依赖。正式采用官方运行库时请按[官方 Godot 接入说明](https://esotericsoftware.com/spine-godot)选择匹配版本和授权。

## 如何调整动作

编辑 `tools/build_qyy_spine.py` 的 `make_animation()`：

- `chest` 的 Y 值：呼吸高度。
- `head` 的旋转值：头部摆动幅度。
- 两条 `arm` 的旋转值：袖口摆动。
- `influences()`：各区域绑定哪些骨骼以及混合比例。

随后在项目根目录运行 `python tools/build_qyy_spine.py`。脚本只覆盖此样例的 JSON、atlas、贴图；如果已在 Spine 手工编辑，请先另存，避免覆盖手工结果。

如果修改循环时长，需同步修改播放器的 `DURATION`。修改骨骼位置时，建议重新运行下面的检查，防止脚滑和网格折叠。

## 已完成的验证

- Godot `tools/qyy_spine_probe.tscn`：8 项检查通过；采样整个循环，脚底不移动、三角形不翻转、循环接缝连续、角色配置和动画框适配正常。
- 待机网格最大位移约 4.922 像素，属于背景微动。
- `tools/validate_qyy_spine.mjs`：官方 Spine 4.2 解析通过；六个姿态与 Godot 的最大坐标误差约 0.000122 像素。
- Godot D3D12 实际渲染截图检查通过。

常规检查已经纳入 `tools/run_checks.ps1`。可选的官方运行库验证步骤：

```powershell
npm.cmd install --prefix "$env:TEMP\will-spine-validation" --no-audit --no-fund --ignore-scripts @esotericsoftware/spine-core@4.2.120
# 先运行 tools/qyy_spine_probe.tscn 生成比对文件，再执行：
node tools/validate_qyy_spine.mjs "$env:TEMP\will-spine-validation\node_modules\@esotericsoftware\spine-core\dist\index.js" "$env:APPDATA\Godot\app_userdata\WILL_game\qyy_spine_validation.json"
```
