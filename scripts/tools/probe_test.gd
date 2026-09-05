extends Node
func _ready() -> void:
	GameState.current_level_id = "0001"
	var s = preload("res://scenes/arrange/arrange_board.tscn").instantiate()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	print("P: lfill=%s rfill=%s single=%s" % [
		str(s.dual_bg.l_fill.color.to_html(false)),
		str(s.dual_bg.r_fill.color.to_html(false)),
		str(s.single_row)])
	var chars := LevelData.load_characters()
	print("P: wzr=%s" % str(chars.get("wzr", {}).get("color", "?")))
	var lv := LevelData.load_level("0001")
	print("P: row0_char=%s row1_char=%s" % [lv.rows[0].character, lv.rows[1].character])
