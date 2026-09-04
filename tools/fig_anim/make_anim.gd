# fig_anim/make_anim.gd — 立绘序列一键处理(EditorScript)
#
# 用法:
#   1. 把新序列拖进 assets/fig_anim/input/<动画名>/ (每套动画一个子目录, 图需已是透明底);
#   2. 在 Script 编辑器打开本脚本, File → Run(Ctrl+Shift+X);
#   3. 脚本为每个未处理的序列调用 tools/fig_anim/process.py, 自动生成:
#      帧副本 + SpriteFrames 循环动画 + scenes/fig_anim/<动画名>_anim.tscn 可拖拽动画框;
#   4. 把生成的动画框场景拖进任意界面, 在 2D 编辑器里拖动调位置。
#
# 依赖: 本机需有 python + Pillow(process.py 用); 已处理过的序列自动跳过,
#       想重做删掉 output/<名>/ 下的 tres 或传入 force 再跑。
@tool
extends EditorScript

const INPUT_DIR := "res://assets/fig_anim/input"
const OUT_TRES := "res://assets/fig_anim/output/%s/%s_sprite_frames.tres"
const PY := "res://tools/fig_anim/process.py"
const FPS := 24

func _run() -> void:
	var abs_input := ProjectSettings.globalize_path(INPUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_input):
		printerr("缺少输入目录: ", INPUT_DIR, " —— 先在项目里建好这个目录, 再把序列拖进它的子目录")
		return
	var dir := DirAccess.open(abs_input)
	var processed := 0
	var names := dir.get_directories()
	names.sort()
	for name in names:
		if ResourceLoader.exists(OUT_TRES % [name, name]):
			print("跳过(已处理过): ", name)
			continue
		var files := DirAccess.get_files_at(abs_input + "/" + name)
		if files.is_empty():
			print("跳过(空目录): ", name)
			continue
		var out: Array = []
		var code := OS.execute("python", [
			ProjectSettings.globalize_path(PY),
			abs_input + "/" + name,
			name,
			str(FPS),
		], out, true)
		for line in out:
			print(String(line).strip_edges())
		if code != 0:
			printerr("处理失败: ", name, " (退出码 ", code, "), 请确认本机已装 python + Pillow")
			continue
		processed += 1
	print("本次处理 %d 个新动画" % processed)
	# 刷新文件系统让新 PNG 完成导入(刚生成的头几次预览若发灰, 稍等 import 完成即可)
	get_editor_interface().get_resource_filesystem().scan()
	print("动画框在 scenes/fig_anim/ 下, 拖进场景即可使用; 原始序列用完可删")
