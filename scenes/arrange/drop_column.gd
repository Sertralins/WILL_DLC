# DropColumn.gd
# 挂在左右两栏上:栏内任意位置都是放置区。
# 拖动悬停时显示"提前占位"缝隙(下方元素实时让位,预览落位后的效果);
# 松手后字条落到缝隙所在位置,与预览完全一致。
# 另支持"边缘吸附":鼠标在栏边缘 SNAP_MARGIN 范围内也算悬停该栏(见 _process)。
extends VBoxContainer

# 吸附范围:鼠标离栏边缘这个距离内,也算悬停在该栏(与 main.gd 保持一致)
const SNAP_MARGIN := 80.0

# 拖动悬停时显示的占位缝隙
var gap: Control = null

# 只有拖过来的是字条卡片时才允许放置。
# 放置/预览统一路由到场景根(中缝跨行拖放按文档判定: 拖过中缝 = 移到另一封信)
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Card):
		return false
	var main := get_tree().current_scene
	if main and main.has_method("_route_preview"):
		main._route_preview(data as Card, get_viewport().get_mouse_position())
	else:
		update_preview_gap(data as Card, at_position)
	return true

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not (data is Card):
		return
	var main := get_tree().current_scene
	if main and main.has_method("_route_drop"):
		main._route_drop(data as Card, get_viewport().get_mouse_position())
	else:
		receive_drop(data as Card, at_position)

# —— 公开接口(main.gd 的边缘吸附转发会调用) ——

# 放下字条:直接落到占位缝隙的位置,保证和预览一致
func receive_drop(card: Card, at_position: Vector2) -> void:
	card.visible = true       # 拖拽期间字条被隐藏,落下时恢复显示
	card.clear_placeholder()  # 松手后灰框消失

	if gap:
		# 有缝隙:字条顶替缝隙的位置(预览 = 落位,分毫不差)
		var idx := gap.get_index()
		_remove_preview_gap()
		var old_parent := card.get_parent()
		if old_parent and old_parent != self:
			old_parent.remove_child(card)
		elif old_parent == self and card.get_index() < idx:
			idx -= 1  # 隐藏的字条原本在缝隙之前,缝隙移除后其位置索引前移一位
		add_child(card)  # 若已在本栏,此调用无副作用
		move_child(card, idx)
	else:
		# 无缝隙(落点 = 原位置):按原逻辑就近插入
		var idx2 := _insert_index([card], at_position)
		var old_parent2 := card.get_parent()
		if old_parent2:
			old_parent2.remove_child(card)
		add_child(card)
		move_child(card, idx2)
	card.play_landing()  # 落座回弹动画

# 提前占位:在落点处放一个与字条等高的缝隙,把下面的字块/字条挤到落位后的位置
func update_preview_gap(card: Card, at_position: Vector2) -> void:
	# 在"旧缝隙仍占位"的布局下计算插入位置(与落位后布局一致,移动稳定不抖动)
	var idx := _insert_index([card, gap], at_position)
	# 落点就是字条原位置(灰框处)时,落位后布局不变,不显示缝隙
	if self == card.origin_slot and idx == card.origin_index:
		_remove_preview_gap()
		return
	if gap:
		# 旧缝隙当前的"过滤索引"(全索引 - 排在前面的被排除节点)
		var old_filtered := gap.get_index()
		if card.get_parent() == self and card.get_index() < gap.get_index():
			old_filtered -= 1
		if old_filtered == idx:
			return  # 位置没变,不重建
	_remove_preview_gap()
	gap = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.55, 0.75, 1.0, 0.15)
	style.border_color = Color(0.65, 0.85, 1.0, 0.8)
	style.set_border_width_all(2)
	gap.add_theme_stylebox_override("panel", style)
	gap.custom_minimum_size = Vector2(0, card.size.y)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gap)
	# 过滤索引 → 全列表索引:若隐藏的被拖字条排在目标位置之前,需后移一位,
	# 否则缝隙会插错位置(插不到最下面一张字条的下面)
	var full_idx := idx
	if card.get_parent() == self and card.get_index() < idx:
		full_idx += 1
	move_child(gap, full_idx)

func _remove_preview_gap() -> void:
	if gap:
		if gap.get_parent():
			gap.get_parent().remove_child(gap)
		gap.queue_free()
		gap = null

# 计算插入索引。
# 注意:先数"有效子元素总数"用于钳制——循环会提前 break,
# 边扫描边计数会得到错误的钳制值(字条会永远落到栏顶)。
func _insert_index(exclude: Array, at_position: Vector2) -> int:
	var total := 0
	for child in get_children():
		if not exclude.has(child):
			total += 1
	var idx := 0
	for child in get_children():
		if exclude.has(child):
			continue
		if at_position.y <= child.position.y + child.size.y * 0.5:
			break
		idx += 1
	# 不许放字条的位置:顶部情节块之上(0)与"最后情节块之后"(total);
	# 允许 1..total-1:顶部情节块之下、底部情节块之上的所有缝隙
	return clampi(idx, mini(1, total), total - 1)

# 每帧兜底:拖拽结束、或鼠标离开"本栏 + 吸附范围"时,清掉占位缝隙
func _process(_delta: float) -> void:
	if gap == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	if not vp.gui_is_dragging():
		_remove_preview_gap()
		return
	if not (vp.gui_get_drag_data() is Card):
		_remove_preview_gap()
		return
	if not get_global_rect().grow(SNAP_MARGIN).has_point(vp.get_mouse_position()):
		_remove_preview_gap()
