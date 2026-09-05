# 立绘序列 → 动画框模板

以后每拿到一套新的**透明底** PNG 序列（任意帧数、任意尺寸），三步变成可拖拽的循环动画框：

## 使用步骤

1. **拖图**：把整套透明底序列拖进 `assets/fig_anim/input/<动画名>/`
   （每套动画一个子目录，帧按文件名排序；512×1024 立绘或任何尺寸都行）
2. **一键处理**：在 Script 编辑器打开 `tools/fig_anim/make_anim.gd`，运行
   `File → Run`（快捷键 `Ctrl+Shift+X`）。脚本自动为 input 下所有**未处理过的**子目录：
   - 帧原样复制 → `assets/fig_anim/output/<动画名>/frames/`（像素零改动，缺透明通道的帧会警告）
   - 生成循环动画 → `assets/fig_anim/output/<动画名>/<动画名>_sprite_frames.tres`（默认 24fps，循环）
   - 生成动画框 → `scenes/fig_anim/<动画名>_anim.tscn`（Control 尺寸=帧尺寸、鼠标穿透、编辑器可见黄框、自动播放）
3. **摆放**：把生成的动画框场景实例拖进任意界面，在 2D 编辑器里拖动调位置即可
   （参考 `scenes/xl/yf_anim.tscn`，已按同样结构放进 letter/arrange 场景的信封层上、文字层下）

## 常见问题

- **报"处理失败…python + Pillow"**：命令行 `pip install pillow` 后重跑。
- **想重做某套动画**：删掉 `assets/fig_anim/output/<名>/` 里的 tres 再跑；
  或直接命令行 `python tools/fig_anim/process.py <图目录> <动画名> 24 force`。
- **改帧率**：改 `make_anim.gd` 顶部的 `FPS`（或命令行传第 3 个参数）。
- **生成的素材发灰/不显示**：编辑器正在后台导入新 PNG，稍等片刻即可。
- **提示"没有透明通道"**：说明有的帧不是透明底，会被当成不透明显示，检查源图。
- **原始序列**：处理完成后 input 里的原图可删，output 里已存副本。
- **动画不想循环**：在生成的场景里取消 Frames 节点的 `playing`，或把 tres 的 `"loop": true` 改 false。
