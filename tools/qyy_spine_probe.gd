extends Node

var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _ready() -> void:
	var actor = load("res://scenes/xl/qyy_anim.tscn").instantiate()
	add_child(actor)
	actor.playing = false
	actor.seek(0)
	var initial: PackedVector2Array = actor.vertices.duplicate()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(actor.DATA_PATH))
	var mesh: Dictionary = data.skins[0].attachments.silhouette.qyy
	var setup_ok := true
	for i in initial.size():
		var expected := Vector2(mesh.uvs[i * 2] * 512, mesh.uvs[i * 2 + 1] * 1024)
		setup_ok = setup_ok and initial[i].distance_to(expected) < 0.001
	check(setup_ok, "setup pose must preserve the original texture geometry")
	var feet_fixed := true
	var triangles_valid := true
	var maximum_motion := 0.0
	for frame in 241:
		actor.seek(frame / 30.0)
		for i in initial.size():
			var distance: float = initial[i].distance_to(actor.vertices[i])
			maximum_motion = maxf(maximum_motion, distance)
			if initial[i].y >= 864:
				feet_fixed = feet_fixed and distance < 0.001
		for i in range(0, mesh.triangles.size(), 3):
			var a: Vector2 = actor.vertices[int(mesh.triangles[i])]
			var b: Vector2 = actor.vertices[int(mesh.triangles[i + 1])]
			var c: Vector2 = actor.vertices[int(mesh.triangles[i + 2])]
			triangles_valid = triangles_valid and (b - a).cross(c - a) > 0.01
	check(feet_fixed, "feet cannot drift during idle")
	check(triangles_valid, "mesh cannot fold or invert")
	check(maximum_motion > 2 and maximum_motion < 15, "visible but restrained idle motion")
	actor.seek(8)
	check(actor.vertices == initial, "loop ends at its initial pose")
	actor.seek(7.999)
	var seam := 0.0
	for i in initial.size():
		seam = maxf(seam, initial[i].distance_to(actor.vertices[i]))
	check(seam < 0.02, "loop boundary cannot jump")
	# 供可选的官方 Spine 运行库校验脚本逐顶点比对，写入隔离的测试输出。
	var samples: Array = []
	for time in [0.0, 1.37, 2.0, 4.25, 6.0, 7.999]:
		actor.seek(time)
		var points: Array = []
		for vertex: Vector2 in actor.vertices:
			points.append_array([vertex.x - 256, 992 - vertex.y])
		samples.append({"time": time, "vertices": points})
	var sample_file := FileAccess.open("user://qyy_spine_validation.json", FileAccess.WRITE)
	sample_file.store_string(JSON.stringify(samples))
	sample_file.close()
	var slot := Control.new()
	slot.size = Vector2(256, 512)
	add_child(slot)
	load("res://scripts/ui/character_anim.gd").setup(slot, "qyy")
	check(slot.get_child_count() == 1 and slot.visible, "qyy is available through character configuration")
	if slot.get_child_count() == 1:
		check(slot.get_child(0).scale.is_equal_approx(Vector2(0.5, 0.5)), "fixed animation frame scales qyy correctly")
	print("QYY_SPINE: %d checks, %d failures; maximum motion %.3f px" % [checks, failures, maximum_motion])
	get_tree().quit(1 if failures else 0)
