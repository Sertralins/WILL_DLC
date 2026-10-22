extends Node

const BOARD := preload("res://scenes/arrange/arrange_board.tscn")
const LETTER := preload("res://scenes/letter/letter_reader.tscn")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	_check_frame_fit()
	GameState.save_path = "user://character_slide_probe_save.json"
	GameState.reset_save()
	LevelData.overrides["slide_probe"] = preload("res://tools/test_fixtures.gd").level_data("slide_probe", true)
	LevelData.overrides["slide_probe"].rows[1]["anim"] = "res://scenes/xl/yf_anim.tscn"
	GameState.current_level_id = "slide_probe"
	GameState.current_row = "L"
	GameFlow.previous_scene = "recap"
	var board := BOARD.instantiate()
	add_child(board)
	check(board.l_anim_slot.position.x < 0, "双人左侧从屏幕左外进入")
	check(board.r_anim_slot.position.x > get_viewport().get_visible_rect().size.x, "双人右侧从屏幕右外进入")
	await get_tree().create_timer(0.25).timeout
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://character_slide_preview.png")
	await get_tree().create_timer(0.6).timeout
	check(is_equal_approx(board.l_anim_slot.position.x, 122.0) and is_equal_approx(board.r_anim_slot.position.x, 1408.0), "滑入准确抵达原场景槽位")
	board._on_reset_pressed()
	check(is_equal_approx(board.l_anim_slot.position.x, 122.0), "原始状态不重播人物滑入")
	board.free()
	GameState.verdicts = {"level_id": "slide_probe"}
	GameFlow.previous_scene = "letter"
	board = BOARD.instantiate()
	add_child(board)
	check(board.locked and is_equal_approx(board.l_anim_slot.position.x, 122.0), "判定后返回结算界面不滑入")
	board.free()
	GameFlow.previous_scene = "map"
	board = BOARD.instantiate()
	add_child(board)
	check(board.locked and board.l_anim_slot.position.x < 0, "从地图重进已有结局仍播放入场")
	board.free()
	GameState.review_letter = true
	var letter := LETTER.instantiate()
	add_child(letter)
	check(letter.anim_slot.position.x < 0, "决定后的L信件从左进入")
	letter.free()
	GameState.current_row = "R"
	letter = LETTER.instantiate()
	add_child(letter)
	check(letter.anim_slot.position.x > get_viewport().get_visible_rect().size.x, "决定后的R信件从右进入")
	letter.free()
	LevelData.overrides["slide_probe"] = preload("res://tools/test_fixtures.gd").level_data("slide_probe")
	GameState.verdicts = {}
	GameState.review_letter = false
	GameState.current_row = "L"
	board = BOARD.instantiate()
	add_child(board)
	check(board.single_row and board.l_anim_slot.position.x < 0 and not board.r_anim_slot.visible, "单人仅左侧人物滑入")
	board.free()
	letter = LETTER.instantiate()
	add_child(letter)
	check(letter.anim_slot.position.x < 0, "初次读信单人从左进入")
	letter.free()
	await get_tree().process_frame
	await get_tree().process_frame
	LevelData.overrides.erase("slide_probe")
	GameState.reset_save()
	print("CHARACTER_SLIDE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _check_frame_fit() -> void:
	var slot := Control.new()
	slot.position = Vector2(140, 60)
	slot.size = Vector2(512, 1024)
	add_child(slot)
	var content := Control.new()
	content.size = Vector2(512, 1024)
	slot.add_child(content)
	var fit := preload("res://scripts/ui/character_frame_fit.gd").new()
	content.add_child(fit)
	fit.configure(slot, content)
	check(content.position == Vector2.ZERO and content.scale == Vector2.ONE, "同尺寸动画框保留原始画面")
	slot.size = Vector2(256, 512)
	check(content.scale == Vector2(0.5, 0.5), "框缩小时人物等比适配")
	slot.size = Vector2(512, 512)
	check(content.position == Vector2(128, 0), "宽框横向居中且底部对齐")
	check(slot.position == Vector2(140, 60), "适配不改场景里固定位置")
	slot.free()
