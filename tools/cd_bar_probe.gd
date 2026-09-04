# tools/cd_bar_probe.gd — CdBar 独立渲染自检:
#   纯色底 + 一条 CdBar(位置已知), 截图后量出条的实际渲染矩形(排查排布场景里的右缘缺口)
# 用法: godot --path . res://tools/cd_bar_probe.tscn -- shot
extends Node

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.5, 0.8)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(bg)

	var bar := CdBar.new()
	bar.position = Vector2(400, 300)
	bar.size = Vector2(600, 120)
	root.add_child(bar)
	bar.play_countdown(5.0)
	await get_tree().process_frame
	await get_tree().process_frame
	print("bar rect=", bar.get_global_rect())
	for c in bar.get_children():
		print("  ", c.name, " rect=", (c as Control).get_global_rect())
	await get_tree().create_timer(1.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://cd_bar_probe.png")
	print("saved size=", img.get_size())
	get_tree().quit()
