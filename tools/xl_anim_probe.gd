# tools/xl_anim_probe.gd — 立绘动画框验证:
#   1. 动画框组件本身: SpriteFrames 加载/帧数/尺寸/循环/帧率(取 characters.json 里
#      第一个配置了 anim 的人物, 现在=伊芙 yf);
#   2. 场景层级(信封 → 动画 → 文字 → 交换纸条 → 纸条/RANK/按钮);
#   3. 行数模板绑定(单行/双行/三行): letter/arrange 场景按模板布局, 动画槽跟着每行
#      配置的人物走(有 anim 填、无 anim 隐藏); 换人物 = 只换对应槽的动画, 模板
#      (行数/布局)不变。关卡数据由 _template_level 内存构造注入 LevelData.overrides,
#      与 data/levels 下的具体关卡(0001/0002…)完全解耦;
#   4. 截图(仅 GUI 模式有意义)。
# 用法: godot res://tools/xl_anim_probe.tscn --quit-after 300   (headless 可, GUI 可)
extends Node

const SHOT_PATH := "user://xl_anim_probe.png"

# —— 行数模板: 每行 = 人物 id(字符串) 或 {character, anim} 字典(行级动画路径) ——
# 换人物只是换对应槽的动画, 模板结构不变; 字典的 anim 模拟"关卡 JSON 里直接配行动画"
const TEMPLATES := {
	"single":    ["yf"],            # 单行: 左槽 yf(有 anim)
	"dual":      ["yf", "qyy"],     # 双行: 左 yf(有 anim) 右 qyy(无 anim)
	"dual_swap": ["qyy", "yf"],     # 双行换人物: 左 qyy(无) 右 yf(有)
	"triple":    ["yf", "qyy", "yf"],  # 三行: letter 三行逐行验证; arrange 目前只到前两栏
	"row_anim":  ["yf", {"character": "qyy", "anim": "res://scenes/xl/yf_anim.tscn"}],
									# 行级 anim: qyy 行直接配动画路径(人物本身无 anim) → 该槽应填
}
const ROW_IDS := ["L", "R", "M"]

func _ready() -> void:
	_check.call_deferred()

func _check() -> void:
	var characters := LevelData.load_characters()
	# 注入模板关卡(内存构造, 不落盘、不碰 data/levels)
	for name in TEMPLATES:
		LevelData.overrides["probe_" + name] = _template_level("probe_" + name, TEMPLATES[name])
	var ok := await _check_component(characters)
	ok = _check_scene_order() and ok
	var templates_ok := await _check_templates(characters)
	ok = templates_ok and ok

	await get_tree().process_frame
	await get_tree().process_frame
	# —— 4. 截图(仅 GUI 模式: headless 的 viewport 纹理无效) ——
	if DisplayServer.get_name() == "headless":
		print("headless: 跳过截图")
	else:
		var img1 := get_viewport().get_texture().get_image()
		await get_tree().create_timer(0.5).timeout
		var img2 := get_viewport().get_texture().get_image()
		img1.save_png("user://xl_anim_shot1.png")
		img2.save_png("user://xl_anim_shot2.png")
		# 动画框区域(左上 512×1024)两次截图的差异采样数 > 0 即动画在动
		var diff := 0
		for y in range(0, 1024, 8):
			for x in range(0, 512, 8):
				if img1.get_pixel(x, y) != img2.get_pixel(x, y):
					diff += 1
		print("shot diff samples: ", diff, " (expect > 0)")
		ok = ok and diff > 0
	print("XL-OK" if ok else "XL-FAIL")
	get_tree().quit()

# —— 1. 动画框组件本身(人物 = characters.json 里第一个配置 anim 的, 现在是 yf) ——

func _check_component(characters: Dictionary) -> bool:
	var anim_path := ""
	for cid in characters:
		var p := String(characters[cid].get("anim", ""))
		if p != "" and ResourceLoader.exists(p):
			anim_path = p
			break
	if anim_path == "":
		push_error("characters.json 里没有任何 anim 配置, 组件验证跳过")
		return false
	var anim: Control = (load(anim_path) as PackedScene).instantiate()
	add_child(anim)   # 保留到截图(动画区域差异采样)
	var frames := anim.get_node("Frames") as AnimatedSprite2D
	var sf: SpriteFrames = frames.sprite_frames
	print("anim path: ", anim_path)
	print("frames count: ", sf.get_frame_count("default"))
	print("frame0 size: ", sf.get_frame_texture("default", 0).get_size())
	print("loop: ", sf.get_animation_loop("default"), " speed: ", sf.get_animation_speed("default"))
	print("anim box size: ", anim.size, " playing: ", frames.is_playing(), " animation: '", frames.animation, "' start frame: ", frames.frame)
	print("modulate a: ", frames.modulate.a, " (expect 0.6)")
	await get_tree().create_timer(1.0).timeout
	print("frame after 1.0s: ", frames.frame, " (expect ~24 @24fps)")
	var img: Image = sf.get_frame_texture("default", 0).get_image()
	print("bg(10,10) a=", img.get_pixel(10, 10).a, " corner(1,1) a=", img.get_pixel(1, 1).a)
	var body_a := 0.0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			body_a = maxf(body_a, img.get_pixel(x, y).a)
	print("max sampled a=", body_a)
	return body_a > 0.9 and frames.frame > 5 and frames.is_playing() \
		and is_equal_approx(frames.modulate.a, 0.6)

# —— 2. 场景层级(与模板无关, 用双行模板实例验证一次) ——

func _check_scene_order() -> bool:
	GameState.current_level_id = "probe_dual"
	GameState.current_row = "L"
	var arr: Control = (load("res://scenes/arrange/arrange_board.tscn") as PackedScene).instantiate()
	add_child(arr)
	var ael := arr.get_node("EnvelopeLayer") as Control
	var atl := arr.get_node("TextLayer") as Control
	var abs_ := arr.get_node("BoardScroll") as Control
	var aeb := arr.get_node("EdgeButtons") as Control
	var ranks := arr.get_node("RankTagL") as Control
	var order_ok := ael.get_index() < atl.get_index() and atl.get_index() < abs_.get_index() \
		and abs_.get_index() < aeb.get_index() and aeb.get_index() < ranks.get_index()
	print("arrange order: envelope=%d text=%d board=%d edge=%d rankL=%d order_ok=%s" % [
		ael.get_index(), atl.get_index(), abs_.get_index(), aeb.get_index(), ranks.get_index(), order_ok])
	arr.queue_free()
	return order_ok

# —— 3. 行数模板绑定: letter 逐行验证动画槽跟随该行人物; arrange 验证 L/R 槽跟随前两行 ——

func _check_templates(characters: Dictionary) -> bool:
	var ok := true
	for name in TEMPLATES:
		var chars: Array = TEMPLATES[name]
		GameState.current_level_id = "probe_" + name
		# letter: 每行人物 → AnimSlot 填/隐藏
		for i in chars.size():
			GameState.current_row = ROW_IDS[i]
			var letter: Control = (load("res://scenes/letter/letter_reader.tscn") as PackedScene).instantiate()
			add_child(letter)
			var lslot := letter.get_node("EnvelopeLayer/AnimSlot") as Control
			var filled := lslot.visible and lslot.get_child_count() > 0
			var expect := _row_expect_anim(characters, chars[i])
			print("letter %s 行%s(%s): slot=%s expect=%s" % [name, ROW_IDS[i], chars[i], filled, expect])
			ok = ok and filled == expect
			letter.queue_free()
		# arrange: L/R 槽跟随 rows[0]/rows[1]; 单行 R 栏整体隐藏(三行只验证前两栏)
		GameState.current_row = ROW_IDS[0]
		var arr: Control = (load("res://scenes/arrange/arrange_board.tscn") as PackedScene).instantiate()
		add_child(arr)
		var las := arr.get_node("EnvelopeLayer/LAnimSlot") as Control
		var ras := arr.get_node("EnvelopeLayer/RAnimSlot") as Control
		var lfill := las.visible and las.get_child_count() > 0
		var rfill := ras.visible and ras.get_child_count() > 0
		var lexpect := _row_expect_anim(characters, chars[0])
		var rexpect := chars.size() > 1 and _row_expect_anim(characters, chars[1])
		print("arrange %s: L=%s(expect %s) R=%s(expect %s)" % [name, lfill, lexpect, rfill, rexpect])
		ok = ok and lfill == lexpect and rfill == rexpect
		arr.queue_free()
	await get_tree().process_frame
	return ok

# 人物是否配置了可加载的 anim
func _has_anim(characters: Dictionary, cid: String) -> bool:
	var path := String(characters.get(cid, {}).get("anim", ""))
	return path != "" and ResourceLoader.exists(path)

# 行的动画期望: 行级 anim(关卡 JSON 直接配)优先, 缺省按人物 characters.json 的 anim
func _row_expect_anim(characters: Dictionary, spec: Variant) -> bool:
	if spec is Dictionary:
		var p := String(spec.get("anim", ""))
		if p != "":
			return ResourceLoader.exists(p)
		return _has_anim(characters, String(spec.get("character", "")))
	return _has_anim(characters, String(spec))

# 模板 → 关卡数据: 行数固定(单行/双行/三行), 每行人物可换;
# 行 = 人物 id 字符串, 或 {character, anim} 字典(行级动画路径);
# 句子内联 text(不依赖 <id>.txt 文本表), 无结局/条件(与动画验证无关)
func _template_level(lid: String, chars: Array) -> Dictionary:
	var rows: Array = []
	for i in chars.size():
		var rid: String = ROW_IDS[i]
		var spec: Variant = chars[i]
		var cid := ""
		var row_anim := ""
		if spec is Dictionary:
			cid = String(spec.get("character", ""))
			row_anim = String(spec.get("anim", ""))
		else:
			cid = String(spec)
		rows.append({
			"id": rid,
			"title": "探针行%s" % rid,
			"monologue": "",
			"character": cid,
			"anim": row_anim,
			"position": "0,1",
			"previous": "start",
			"blocks": [{"id": "P%s" % rid, "text": "固定句%s" % rid}],
			"strips": [{"id": "%s1" % rid, "text": "字条%s" % rid}],
			"variants": [],
		})
	return {
		"level_id": lid,
		"title": "探针%s" % lid,
		"unlock": "",
		"subtitle": "",
		"row_count": chars.size(),
		"rows": rows,
		"endings": {},
		"conditions": [],
	}
