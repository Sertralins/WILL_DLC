# 一栏的拖放：计算真实插槽，再用阴影展示，预览与实际放置共用候选结果。
extends VBoxContainer

const Shadow := preload("res://scenes/arrange/drop_shadow.gd")
const SNAP_MARGIN := 180.0
var gap: Control = null
var _gap_index := -1

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Card or data.locked:
		return false
	var scene := get_tree().current_scene
	if scene and scene.has_method("_route_preview"):
		return scene._route_preview(data, get_viewport().get_mouse_position())
	return update_preview_gap(data, at_position)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not data is Card or data.locked:
		return
	var scene := get_tree().current_scene
	if scene and scene.has_method("_route_drop"):
		scene._route_drop(data, get_viewport().get_mouse_position())
	else:
		receive_drop(data, at_position)

# 候选序列剔除被拿起的卡片和阴影，避免把临时控件当成真实纸条。
func _items(card: Card) -> Array[Control]:
	var items: Array[Control] = []
	for child in get_children():
		if child is Control and child != card and child != gap and child.visible:
			items.append(child)
	return items

# 顶部固定块前、底部固定块后是非法槽。不能通过 clamp 悄悄改成合法位置。
func drop_candidate(card: Card, point: Vector2) -> Dictionary:
	var items := _items(card)
	var index := 0
	if gap != null and gap.get_rect().has_point(point):
		index = _gap_index
	else:
		for child in items:
			if point.y <= child.position.y + child.size.y * 0.5:
				break
			index += 1
	return {"index": index, "allowed": not card.locked and index > 0 and index < items.size()}

func update_preview_gap(card: Card, point: Vector2) -> bool:
	var candidate := drop_candidate(card, point)
	if not candidate.allowed:
		_remove_preview_gap()
		return false
	var index := int(candidate.index)
	if gap != null and _gap_index == index:
		return true
	_remove_preview_gap()
	var anchor: Control = _items(card)[index]
	gap = Shadow.new()
	gap.name = "DropShadow"
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.custom_minimum_size = Vector2(0, card.size.y)
	_gap_index = index
	add_child(gap)
	move_child(gap, anchor.get_index())
	return true

func receive_drop(card: Card, point: Vector2) -> bool:
	var candidate := drop_candidate(card, point)
	if not candidate.allowed:
		return false
	var anchor: Control = _items(card)[int(candidate.index)]
	_remove_preview_gap()
	var old_parent := card.get_parent()
	if old_parent:
		old_parent.remove_child(card)
	add_child(card)
	move_child(card, anchor.get_index())
	card.visible = true
	card.drag_active = false
	card.clear_drop_preview()
	card.play_landing()
	return true

func _remove_preview_gap() -> void:
	if gap != null:
		remove_child(gap)
		gap.queue_free()
		gap = null
	_gap_index = -1
