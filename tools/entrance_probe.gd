extends "res://scenes/arrange/arrange_board.gd"

var failures := 0
var checks := 0

func _ready() -> void:
	Engine.time_scale = 0.0  # 用手动步进验证时序，不受机器首帧耗时影响。
	GameState.save_path = "user://entrance_probe_save.json"
	GameState.reset_save()
	LevelData.overrides["entrance_probe"] = preload("res://tools/test_fixtures.gd").level_data("entrance_probe", true)
	GameState.current_level_id = "entrance_probe"
	super._ready()
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func settle() -> void:
	for i in 4:
		await get_tree().process_frame

func _run() -> void:
	check(entrance.playing and not can_edit(), "加载立即开始演出并暂停拖放")
	await settle()
	entrance._tween.pause()
	Engine.time_scale = 1.0
	var first: Control = left_column.get_child(0)
	var second: Control = right_column.get_child(0)
	var first_text: RichTextLabel = first.find_child("Text", true, false)
	check(first_text.modulate.a == 0.0, "先生成无字底板")
	check(second.scale.x < 0.01, "后续块等待间隔")
	entrance._tween.custom_step(minf(entrance.GROW_DURATION, entrance.BLOCK_INTERVAL) * 0.5)
	check(first.scale.x > second.scale.x and second.scale.x < 0.01, "同高度左先右后，遵循当前启动间隔")
	check(first_text.modulate.a == 0.0, "放大过程中不显示文字")
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://entrance_preview.png")
	entrance._tween.custom_step(entrance.GROW_DURATION - minf(entrance.GROW_DURATION, entrance.BLOCK_INTERVAL) * 0.5 + (entrance.BLOCK_DURATION - entrance.GROW_DURATION) * 0.5)
	check(first.scale.is_equal_approx(Vector2.ONE) and first_text.modulate.a > 0.0, "放大完成后显示文字")
	entrance._tween.custom_step((entrance.BLOCK_DURATION - entrance.GROW_DURATION) * 0.5 + 0.01)
	check(is_equal_approx(first_text.modulate.a, 1.0), "每块在配置时长内完成")
	Engine.time_scale = 0.0
	_on_reset_pressed()
	_on_reset_pressed()
	await settle()
	check(entrance.playing and left_column.get_child_count() == 4, "连续重置只保留最新内容和演出")
	entrance._tween.pause()
	Engine.time_scale = 1.0
	entrance._tween.custom_step(100.0)
	check(not entrance.playing and can_edit(), "整段结束恢复编辑")
	for column in [left_column, right_column]:
		for block in column.get_children():
			check(block.scale.is_equal_approx(Vector2.ONE), "所有块恢复正常尺寸")
			if block is Card:
				check(not block.entrance_active, "字条恢复可拖状态")
	GameState.reset_save()
	LevelData.overrides.erase("entrance_probe")
	print("ENTRANCE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
