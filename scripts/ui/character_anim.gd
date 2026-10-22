# character_anim.gd — 人物剪影动画槽绑定:
#   按人物 id 查 characters.json 的 anim 字段(动画框场景路径), 实例化填进槽里;
#   该人物没有配置 anim 时清空并隐藏槽。槽是场景里的空 Control(位置在编辑器里拖),
#   槽决定了动画出现的位置, 动画组件本身只管播。
class_name CharacterAnim

# 把 character 的剪影动画填进 slot(先清空旧内容); 动画路径取自人物的 characters.json anim
static func setup(slot: Control, character: String) -> void:
	var characters := LevelData.load_characters()
	var path := String(characters.get(character, {}).get("anim", ""))
	setup_path(slot, path)

# 按动画框场景路径直接填槽(关卡 JSON 行级 anim 用; 空路径/不存在 = 清空并隐藏槽)
static func setup_path(slot: Control, path: String) -> void:
	for child in slot.get_children():
		slot.remove_child(child)
		child.queue_free()
	if path == "" or not ResourceLoader.exists(path):
		slot.visible = false
		return
	slot.visible = true
	var scene := load(path) as PackedScene
	if scene == null:
		slot.visible = false
		push_warning("人物动画需要 .tscn 场景：%s" % path)
		return
	var instance := scene.instantiate()
	if not instance is Control:
		instance.free()
		slot.visible = false
		push_warning("人物动画场景根节点需要 Control，用作固定设计画布：%s" % path)
		return
	var anim := instance as Control
	anim.position = Vector2.ZERO
	slot.add_child(anim)
	var fit := preload("res://scripts/ui/character_frame_fit.gd").new()
	anim.add_child(fit)
	fit.configure(slot, anim)


# 只移动场景中配置好的动画槽，不改人物内部动画、缩放或最终落点。
# from_right=false 从左侧入场；true 从右侧入场。调用方决定哪些流程播放。
const SLIDE_DURATION := 0.75

static func slide_in(slot: Control, from_right := false) -> Tween:
	if not slot.visible:
		return null
	var destination := slot.position
	var screen_rect := slot.get_global_rect()
	var viewport_width := slot.get_viewport_rect().size.x
	var start_x := viewport_width + 32.0 if from_right else -screen_rect.size.x - 32.0
	slot.global_position.x = start_x
	var tween := slot.create_tween()
	tween.tween_property(slot, "position", destination, SLIDE_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tween
