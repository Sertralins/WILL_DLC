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
		child.queue_free()
	if path == "" or not ResourceLoader.exists(path):
		slot.visible = false
		return
	slot.visible = true
	var anim: Control = (load(path) as PackedScene).instantiate()
	anim.position = Vector2.ZERO
	slot.add_child(anim)
