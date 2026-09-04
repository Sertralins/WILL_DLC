# arrange_smoke_test.gd — 交换纸条界面冒烟: 布局分支 / 动态情节块 / 中缝跨行路由
# 运行: godot --headless --path . res://tools/arrange_smoke_test.tscn (外部 timeout 收尾)
extends Node

var board: Node = null

func _ready() -> void:
	GameState.save_path = "user://save_as_smoke.json"
	GameState.reset_save()
	GameState.current_level_id = ""
	_run()

func _run() -> void:
	board = preload("res://scenes/arrange/arrange_board.tscn").instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	var lc: VBoxContainer = board.left_column
	var rc: VBoxContainer = board.right_column
	# 双行关: CanvasPlay 参数(文档 §2)
	print("A: single_row=%s" % str(board.single_row))
	print("A: left=(%s, w=%s) right=(%s, w=%s)" % [str(lc.position.x), str(lc.size.x), str(rc.position.x), str(rc.size.x)])
	print("A: board_h=%s" % str(board.board.custom_minimum_size.y))
	print("A: dual_bg=%s lfill=%s rfill=%s" % [
		str(board.dual_bg.visible),
		str(board.dual_bg.l_fill.color.to_html(false)),
		str(board.dual_bg.r_fill.color.to_html(false))])
	print("A: left_ids=%s" % str(board.get_sequence_ids(lc)))
	print("A: right_ids=%s" % str(board.get_sequence_ids(rc)))
	# 中缝 x∈[910,1010] 跨行路由: 右栏字条拖到中缝 → 左栏
	var card: Card = null
	for c in rc.get_children():
		if c is Card:
			card = c
			break
	if card:
		card.origin_slot = rc
		var seam_col: VBoxContainer = board._target_column(card, Vector2(960, 500))
		var left_col: VBoxContainer = board._target_column(card, Vector2(600, 500))
		var right_col: VBoxContainer = board._target_column(card, Vector2(1200, 500))
		var out_col: VBoxContainer = board._target_column(card, Vector2(50, 500))
		print("A: seam=%s left=%s right=%s outside=%s" % [
			"left" if seam_col == lc else "right",
			"left" if left_col == lc else "right",
			"right" if right_col == rc else "left",
			"null" if out_col == null else "not-null"])
	print("A: DUAL READY")
	# 停顿供 GUI 截图(双人布局)
	await get_tree().create_timer(18.0).timeout
	# 单行关: 左立绘 + 居中偏右单列
	GameState.current_level_id = "0002"
	board.level = LevelData.load_level("0002")
	board._build_layout()
	board._apply_level()
	await get_tree().process_frame
	print("A: single2=%s right_hidden=%s left_x=%s left_w=%s" % [
		str(board.single_row), str(not rc.visible), str(lc.position.x), str(lc.size.x)])
	print("A: single_bg_visible=%s dual_hidden=%s" % [str(board.single_bg.visible), str(not board.dual_bg.visible)])
	print("A: single_ids=%s" % str(board.get_sequence_ids(lc)))
	print("A: SINGLE READY")
	# 停顿供 GUI 截图(单人布局)
	await get_tree().create_timer(6.0).timeout
	# 判定结局后回到本场景: 字条全部锁定(不可拖拽) + Rank 标签
	GameState.current_level_id = "0001"
	GameState.verdicts = {"level_id": "0001", "rank": "S", "ending_id": "S1", "rep": 0, "matched_index": 0, "changes": []}
	board.level = LevelData.load_level("0001")
	board._build_layout()
	board._apply_level()
	await get_tree().process_frame
	var locked_cards := 0
	for c in board.left_column.get_children():
		if c is Card and c.locked:
			locked_cards += 1
	print("A: locked_cards=%d rank_visible=%s reset_blocked=%s" % [
		locked_cards, str(board.rank_tags[0].visible), str(board.locked)])
	print("A: LOCKED READY")
	await get_tree().create_timer(10.0).timeout
	print("A: ARRANGE SMOKE PASS")
