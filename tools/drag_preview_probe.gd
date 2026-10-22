# 拖拽候选、非法槽和柔边阴影回归。加 -- --capture 可输出实际渲染截图。
extends "res://scenes/arrange/arrange_board.gd"

var failures := 0
var checks := 0

func _ready() -> void:
	GameState.save_path = "user://drag_preview_probe_save.json"
	GameState.reset_save()
	LevelData.overrides["drag_probe"] = preload("res://tools/test_fixtures.gd").level_data("drag_probe", true)
	GameState.current_level_id = "drag_probe"
	super._ready()
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func frames() -> void:
	if entrance.playing:
		await entrance.finished
	for i in 4:
		await get_tree().process_frame

func _run() -> void:
	await frames()
	# 手动放置候选以检查渲染；暂停每帧路由，防止无真实鼠标拖动时清除提示。
	set_process(false)
	var card: Card
	for child in left_column.get_children():
		if child is Card and child.card_id == "A1":
			card = child
	var initial := get_sequence_ids(left_column)
	var original_count := left_column.get_child_count()
	card.origin_slot = left_column
	card.origin_index = card.get_index()
	card.hide()
	await frames()
	check(left_column.get_child_count() == original_count, "拿起不创建原位置框")
	var point := left_column.global_position + Vector2(20, left_column.get_node("PanelA2").position.y + 1)
	check(_route_preview(card, point), "合法槽返回可放置")
	await frames()
	check(left_column.gap != null and left_column.gap.allowed, "合法槽黑色阴影")
	check(left_column.gap.get_script() == DropShadow, "落点使用柔边阴影组件")
	var holder := card.build_drag_preview(Vector2(150, 40))
	add_child(holder)
	holder.global_position = point + Vector2(290, -100)
	var paper: Control = holder.get_child(0)
	check(is_equal_approx(paper.rotation_degrees, -3), "拿起倾斜三度")
	var style: StyleBoxFlat = paper.get_theme_stylebox("panel")
	check(style.bg_color.r < 0.85 and style.bg_color.a == 1, "拿起变深且不透明")
	await frames()
	var preview_text := paper.find_child("Label", true, false) as RichTextLabel
	check(preview_text != null, "预览沿用富文本控件")
	if preview_text:
		var source_rect := Rect2(card.get_global_transform().affine_inverse() * card.label.global_position, card.label.size)
		var preview_rect := Rect2(paper.get_global_transform().affine_inverse() * preview_text.global_position, preview_text.size)
		check(source_rect.is_equal_approx(preview_rect), "拿起前后正文位置和尺寸一致")
		check(preview_text.autowrap_mode == card.label.autowrap_mode, "换行设置一致")
	check(style.anti_aliasing and style.anti_aliasing_size >= 1, "倾斜纸面启用柔化边缘")
	check(get_viewport().msaa_2d == Viewport.MSAA_4X, "二维边缘启用四倍抗锯齿")
	await capture("valid")
	holder.queue_free()
	_route_drop(card, point)
	await frames()
	check(get_sequence_ids(left_column) == ["PanelA1", "A2", "A1", "PanelA2"], "松手与预览顺序一致")
	check(left_column.gap == null, "落座后清理阴影")
	card.hide()
	await frames()
	point = left_column.global_position + Vector2(20, 1)
	check(not _route_preview(card, point), "顶部固定块前不允许放置")
	check(_invalid_shadow.visible and not _invalid_shadow.allowed, "非法槽显示红色阴影")
	check(left_column.gap == null, "非法槽不撑开布局")
	await capture("invalid")
	var before := get_sequence_ids(left_column)
	_route_drop(card, point)
	check(card.visible and get_sequence_ids(left_column) == before, "非法松手恢复原位")
	check(not _invalid_shadow.visible, "归位清除红影")
	point = left_column.global_position + Vector2(-150, 200)
	check(_target_column(card, point) == left_column, "扩大范围支持栏外150px")
	point.x = left_column.global_position.x - 181
	check(_target_column(card, point) == null, "超出范围不吸附")
	point = right_column.global_position + Vector2(20, 1)
	check(not _route_preview(card, point), "右栏非法槽同样拒绝")
	point.y = right_column.global_position.y + right_column.size.y + 100
	check(not _route_preview(card, point), "末尾固定块后不允许放置")
	point = right_column.global_position + Vector2(20, right_column.get_node("PanelB2").position.y + 1)
	check(_route_preview(card, point), "右栏合法槽吸附")
	await frames()
	check(right_column.gap != null and left_column.gap == null, "只有目标栏显示阴影")
	_route_drop(card, point)
	check(card.get_parent() == right_column and not get_sequence_ids(left_column).has("A1"), "跨栏成功且不复制字条")
	# 恢复初始排列，检查真实鼠标事件触发拖起和取消。
	_on_reset_pressed()
	await frames()
	check(get_sequence_ids(left_column) == initial, "重置后排列完整")
	await check_mouse_drag()
	GameState.reset_save()
	LevelData.overrides.erase("drag_probe")
	print("DRAG: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func check_mouse_drag() -> void:
	set_process(true)
	var card: Card
	for child in left_column.get_children():
		if child is Card:
			card = child
	var point := card.global_position + Vector2(100, 30)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = point
	get_viewport().push_input(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = point + Vector2(40, 20)
	motion.relative = Vector2(40, 20)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)
	await frames()
	check(get_viewport().gui_is_dragging() and card.drag_active and not card.visible, "真实鼠标拿起纸条")
	press.pressed = false
	press.position = Vector2(5, 5)
	get_viewport().push_input(press, true)
	await frames()
	check(not get_viewport().gui_is_dragging() and card.visible, "真实非法松手恢复纸条")
	check(left_column.gap == null and right_column.gap == null, "拖动结束无残留提示")

func capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name() == "headless":
		return
	await frames()
	await RenderingServer.frame_post_draw
	var path := "user://drag_preview_%s.png" % label
	get_viewport().get_texture().get_image().save_png(path)
	print("SCREENSHOT: ", ProjectSettings.globalize_path(path))
