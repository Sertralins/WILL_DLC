# map_route_probe.gd — 管件路由几何探针: 直接构造 MapRoute 验证拼接与生长
# 运行: godot --headless --path . res://tools/map_route_probe.tscn
#       带窗运行时另存 user://map_route_probe.png 供人工查看
extends Node2D

const ROUTE := preload("res://scenes/map/map_route.gd")

var fails := 0

func _ready() -> void:
	_run()

func check(what: String, ok: bool) -> void:
	print("P: %s=%s" % [what, str(ok)])
	if not ok:
		fails += 1

func route_sections(from: Vector2, to: Vector2, is_dashed := false) -> Node2D:
	var r: Node2D = ROUTE.new()
	r.setup(from, to, Color.WHITE, is_dashed, 0.0)   # 注意: setup 必须先于 add_child(_ready 里构建段)
	add_child(r)
	return r

func tex_of(sec: Dictionary) -> String:
	var sp: Sprite2D = sec.seg.get_child(0)
	return sp.texture.resource_path.get_file()

func _run() -> void:
	# 1) 纯竖线(件 7, 内容中心落在输入列, 长度 = |dy|)
	var rv := route_sections(Vector2(400, 300), Vector2(400, 700))
	check("v_single", rv.sections.size() == 1 and String(rv.sections[0].kind) == "v"
		and tex_of(rv.sections[0]) == "connecting_lines_7.png")
	var sv: Node2D = rv.sections[0].seg
	var spv: Sprite2D = sv.get_child(0)
	check("v_axis_len", is_equal_approx(sv.position.x, 400.0) and is_equal_approx(spv.scale.y, 400.0 / 64.0))
	# 2) 纯横线(件 9)
	var rh := route_sections(Vector2(200, 500), Vector2(900, 500))
	check("h_single", rh.sections.size() == 1 and String(rh.sections[0].kind) == "h"
		and tex_of(rh.sections[0]) == "connecting_lines_9.png")
	# 3) 向右 S: 生长序 v → 弯角4 → h → 弯角1 → v; 横段轴线 y = 两 y 中点
	var rs := route_sections(Vector2(400, 300), Vector2(900, 600))
	print("P: s_right_sections=%s" % str(rs.sections.map(func(s): return "%s:%s" % [s.kind, tex_of(s)])))
	check("s_right_seq", rs.sections.size() == 5
		and rs.sections[0].kind == "v" and rs.sections[1].kind == "corner"
		and tex_of(rs.sections[1]) == "connecting_lines_4.png"
		and rs.sections[2].kind == "h" and rs.sections[3].kind == "corner"
		and tex_of(rs.sections[3]) == "connecting_lines_1.png" and rs.sections[4].kind == "v")
	var sh: Node2D = rs.sections[2].seg
	check("s_right_yh", is_equal_approx(sh.position.y, 450.0))
	# 横段枢轴 = 上弯角 H 出口 - OVER_RUN(伸入弯角下掩盖接缝)
	check("s_right_overrun", is_equal_approx(sh.position.x, 400.0 + 31.5 - 6.0))
	# 4) 向左 S: 弯角 5 + 0
	var rl := route_sections(Vector2(900, 300), Vector2(400, 600))
	check("s_left_seq", rl.sections[1].kind == "corner"
		and tex_of(rl.sections[1]) == "connecting_lines_5.png"
		and rl.sections[3].kind == "corner"
		and tex_of(rl.sections[3]) == "connecting_lines_0.png")
	# 5) 高度不足 → 回退斜线
	var rfall := route_sections(Vector2(400, 300), Vector2(900, 330))
	check("fallback_slant", rfall.sections.size() == 1 and String(rfall.sections[0].kind) == "slant")
	# 6) 虚线整套替换
	var rd := route_sections(Vector2(400, 300), Vector2(900, 600), true)
	var all_dotted := true
	for sec in rd.sections:
		all_dotted = all_dotted and tex_of(sec).begins_with("dotted_")
	check("dashed_all", all_dotted and rd.sections.size() == 5)
	# 7) set_progress: 零态每段至少一轴为 0, 终态全 1
	rs.set_progress(0.0)
	var zero_ok := true
	for sec in rs.sections:
		zero_ok = zero_ok and (sec.seg.scale.x <= 0.001 or sec.seg.scale.y <= 0.001)
	check("progress_zero", zero_ok)
	rs.set_progress(1.0)
	var end_ok := true
	for sec in rs.sections:
		end_ok = end_ok and sec.seg.scale.is_equal_approx(Vector2.ONE)
	check("progress_end1", end_ok)
	print("P: PROBE %s" % ("PASS" if fails == 0 else "FAIL(%d)" % fails))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://map_route_probe.png")
	get_tree().quit()
