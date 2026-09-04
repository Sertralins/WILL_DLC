# tools/cd_probe.gd — 「决定」倒计时色彩条冒烟/截图:
#   存档重定向到临时文件(不污染本机进度); 默认把左栏字条对调(A2 提到 A1 上)
#   命中 S1 新结局 → 走转钟分支, 1s 后打印色彩条/时钟/白底/按钮状态;
#   -- shot: t=1.0 与 t=2.5 各截一张(force_draw 防窗口遮挡拿到陈旧帧),
#            用 tools/cd_shot_check.py 采样验证斜纹+滚动;
#   -- full: root 观察者等 7s 验证倒计时走完后的判定与场景切换;
#   -- bad:  初始排列(不交换)命中 BAD1 → 不进动画, root 观察者验证直接揭晓切场景。
# 用法: godot --headless --path . res://tools/cd_probe.tscn        (冒烟)
#       godot --path . res://tools/cd_probe.tscn -- shot           (窗口截图)
#       godot --headless --path . res://tools/cd_probe.tscn -- full
#       godot --headless --path . res://tools/cd_probe.tscn -- bad
extends Node

func _ready() -> void:
	GameState.save_path = "user://save_as_cd_probe.json"
	GameState.reset_save()
	GameState.current_level_id = "0002" if OS.get_cmdline_user_args().has("bad2") else "0001"
	var board: Control = preload("res://scenes/arrange/arrange_board.tscn").instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	# 默认路径: 左栏字条对调(A2 提到 A1 上)→ SS(A2,A1) 命中 S1 → 转钟分支;
	# -- bad/-- bad2 路径: 保持初始排列 → 命中 BAD1 → 不进动画直接揭晓
	if not (OS.get_cmdline_user_args().has("bad") or OS.get_cmdline_user_args().has("bad2")):
		var lc: VBoxContainer = board.left_column
		var cards: Array = []
		for c in lc.get_children():
			if c is Card:
				cards.append(c)
		if cards.size() >= 2:
			lc.move_child(cards[1], cards[0].get_index())
	# Bad 路径是同步流程(点击 → 揭晓 → 立即切场景, 本 probe 会被释放),
	# 观察者必须提前挂到 root 下
	var bad_path := OS.get_cmdline_user_args().has("bad") or OS.get_cmdline_user_args().has("bad2")
	if bad_path:
		var watcher := BadWatcher.new()
		get_tree().root.add_child(watcher)
		watcher.run()
	# 模拟点击「决定」
	board.decide_btn.pressed.emit()
	if bad_path:
		return
	await get_tree().create_timer(1.0).timeout
	var bars: Array = board._cd_bars
	print("bars=%d visible=%s playing=%s" % [bars.size(),
		str(_all_true(bars, func(b): return b.visible)),
		str(_all_true(bars, func(b): return b._playing))])
	for bar in bars:
		print("bar rect=", bar.get_global_rect(), " strip=", bar._blocks.get_global_rect(),
			" color=", bar.bar_color.to_html(false),
			" scroll=%.3f" % bar._scroll, " alpha=%.2f" % bar._blocks.modulate.a)
	var clock: CountdownClock = null
	for c in board.get_children():
		if c is CountdownClock:
			clock = c
			break
	print("clock=%s elapsed=%.2f" % [
		"在场(CanvasLayer)" if clock else "缺失",
		clock._elapsed if clock else -1.0])
	print("white=%s dual=%s single=%s decide=%s reset=%s back=%s retry=%s" % [
		str(board.white_bg.visible), str(board.dual_bg.visible), str(board.single_bg.visible),
		str(board.decide_btn.visible), str(board.reset_btn.visible),
		str(board.back_btn.visible), str(board.retry_btn.visible)])
	if OS.get_cmdline_user_args().has("shot"):
		# 两个时间点各截一张: 相位差 0.6, 用来验证彩块确实在滚动
		var img1 := get_viewport().get_texture().get_image()
		img1.save_png("user://cd_shot1.png")
		print("saved user://cd_shot1.png size=", img1.get_size())
		await get_tree().create_timer(1.5).timeout
		RenderingServer.force_draw()   # 窗口可能被遮挡/不呈现, 强制离屏重画拿新鲜帧
		await get_tree().process_frame
		var img2 := get_viewport().get_texture().get_image()
		img2.save_png("user://cd_shot2.png")
		print("saved user://cd_shot2.png size=", img2.get_size())
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("full"):
		# 完整流程: 时钟走完(5s+停顿淡出)后场景切到 letter —— 本 probe 是场景根节点,
		# 换场景即被释放, 观察者挂 root 下不随 change_scene 销毁(flow_probe 同款做法)
		var watcher := FullWatcher.new()
		get_tree().root.add_child(watcher)
		watcher.run()
		return
	get_tree().quit()

# 完整流程观察者: 等 7s(覆盖 5.8s 的时钟+淡出)后打印切换结果并退出
class FullWatcher extends Node:
	func run() -> void:
		_watch.call_deferred()

	func _watch() -> void:
		await get_tree().create_timer(7.0).timeout
		var scene := get_tree().current_scene
		print("full: scene=", scene.name if scene else "?")
		print("full: review_letter=", GameState.review_letter, " row=", GameState.current_row,
			" verdict=", GameState.verdicts.get("ending_id", "?"))
		get_tree().quit()

# Bad 路径观察者: 0.3s 确认时钟从未出现, 1.5s 确认已切到排布锁定态直接揭晓
class BadWatcher extends Node:
	func run() -> void:
		_watch.call_deferred()

	func _watch() -> void:
		await get_tree().create_timer(0.3).timeout
		print("bad: clock_appeared=", str(_find_clock(get_tree().root)))
		await get_tree().create_timer(1.2).timeout
		var scene := get_tree().current_scene
		print("bad: scene=", scene.name if scene else "?")
		if scene:
			print("bad: locked=", str(scene.locked),
				" rank_visible=", str(scene.rank_tags[0].visible),
				" verdict=", GameState.verdicts.get("ending_id", "?"),
				" rank=", GameState.verdicts.get("rank", "?"))
		get_tree().quit()

	func _find_clock(n: Node) -> bool:
		for c in n.get_children():
			if c is CountdownClock or _find_clock(c):
				return true
		return false

func _all_true(arr: Array, pred: Callable) -> bool:
	for x in arr:
		if not bool(pred.call(x)):
			return false
	return true
