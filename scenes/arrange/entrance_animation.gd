# 排列界面的逐块入场演出。只改变绘制大小和透明度，不改变布局占位。
extends Node

signal finished
const BLOCK_DURATION := 0.15
const BLOCK_INTERVAL := 0.1
const GROW_DURATION := 0.08

var playing := false
var _generation := 0
var _tween: Tween

func play(columns: Array) -> void:
	_generation += 1
	if _tween and _tween.is_valid():
		_tween.kill()
	playing = true
	var blocks: Array[Control] = []
	for column in columns:
		if not column.visible:
			continue
		for child in column.get_children():
			if child is PanelContainer:
				blocks.append(child)
				child.modulate.a = 0.0
				if child is Card:
					child.entrance_active = true
				for label in child.find_children("*", "RichTextLabel", true, false):
					label.modulate.a = 0.0
	_animate.call_deferred(blocks, _generation)

func _animate(blocks: Array[Control], generation: int) -> void:
	# 等容器排好实际尺寸，避免 Container 重置 scale 或中心点算错。
	await get_tree().process_frame
	await get_tree().process_frame
	if generation != _generation:
		return
	# 双栏也按屏幕从上到下；同高度先左后右。
	blocks.sort_custom(func(a: Control, b: Control) -> bool:
		if is_equal_approx(a.global_position.y, b.global_position.y):
			return a.global_position.x < b.global_position.x
		return a.global_position.y < b.global_position.y)
	_tween = create_tween().set_parallel(true)
	for i in blocks.size():
		var block := blocks[i]
		var delay := i * BLOCK_INTERVAL
		block.pivot_offset = block.size * 0.5
		block.scale = Vector2.ZERO
		block.modulate.a = 1.0
		_tween.tween_property(block, "scale", Vector2.ONE, GROW_DURATION).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		for label in block.find_children("*", "RichTextLabel", true, false):
			_tween.tween_property(label, "modulate:a", 1.0, BLOCK_DURATION - GROW_DURATION).set_delay(delay + GROW_DURATION)
	# 即使没有内容，也正常结束；重置会杀掉旧 Tween，不会回调旧节点。
	_tween.tween_interval(maxf(0.0, (blocks.size() - 1) * BLOCK_INTERVAL) + BLOCK_DURATION)
	_tween.finished.connect(func():
		playing = false
		for block in blocks:
			if is_instance_valid(block) and block is Card:
				block.entrance_active = false
		finished.emit(), CONNECT_ONE_SHOT)

func _exit_tree() -> void:
	_generation += 1
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
