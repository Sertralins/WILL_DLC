## 仇有余样例专用播放器：直接使用同一份 Spine JSON 的骨骼、网格和时间线。
## 仅支持此样例的平移、旋转和线性插值，不是通用 Spine 运行库。
extends Control

const DATA_PATH := "res://assets/spine/qyy/qyy.json"
const TEXTURE := preload("res://assets/spine/qyy/qyy.png")
const DURATION := 8.0

var playing := true
var elapsed := 0.0
var bone_transforms: Array[Transform2D] = []
var vertices := PackedVector2Array()
var _bones: Array = []
var _parents: Array[int] = []
var _weights: Array = []
var _tracks: Dictionary = {}
var _paper := Polygon2D.new()

func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	_bones = data.bones
	_tracks = data.animations.idle.bones
	var mesh: Dictionary = data.skins[0].attachments.silhouette.qyy
	var names: Array[String] = []
	for bone: Dictionary in _bones:
		_parents.append(names.find(bone.get("parent", "")))
		names.append(bone.name)
		bone_transforms.append(Transform2D.IDENTITY)
	var packed: Array = mesh.vertices
	var cursor := 0
	while cursor < packed.size():
		var count := int(packed[cursor])
		cursor += 1
		var influences: Array = []
		for i in count:
			influences.append([int(packed[cursor]), Vector2(packed[cursor + 1], packed[cursor + 2]), float(packed[cursor + 3])])
			cursor += 4
		_weights.append(influences)
		vertices.append(Vector2.ZERO)
	var uvs := PackedVector2Array()
	for i in range(0, mesh.uvs.size(), 2):
		uvs.append(Vector2(mesh.uvs[i] * 512.0, mesh.uvs[i + 1] * 1024.0))
	var triangles: Array[PackedInt32Array] = []
	for i in range(0, mesh.triangles.size(), 3):
		triangles.append(PackedInt32Array(mesh.triangles.slice(i, i + 3)))
	_paper.texture = TEXTURE
	_paper.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_paper.uv = uvs
	_paper.polygons = triangles
	add_child(_paper)
	seek(0)

func _process(delta: float) -> void:
	if playing:
		seek(elapsed + delta)

## 显式指定时间，方便预览、暂停和检查循环接缝。
func seek(seconds: float) -> void:
	elapsed = fposmod(seconds, DURATION)
	for i in _bones.size():
		var bone: Dictionary = _bones[i]
		var track: Dictionary = _tracks.get(bone.name, {})
		var rotation_degrees := _sample(track.get("rotate", []), "value", elapsed)
		var offset := Vector2(float(bone.get("x", 0)), float(bone.get("y", 0)))
		offset += Vector2(_sample(track.get("translate", []), "x", elapsed), _sample(track.get("translate", []), "y", elapsed))
		var local := Transform2D(deg_to_rad(rotation_degrees), offset)
		bone_transforms[i] = bone_transforms[_parents[i]] * local if _parents[i] >= 0 else local
	for i in _weights.size():
		var point := Vector2.ZERO
		for weight: Array in _weights[i]:
			point += (bone_transforms[weight[0]] * weight[1]) * weight[2]
		# 转成 Godot 坐标；脚底基准仍在设计画布 y=992。
		vertices[i] = Vector2(point.x + 256, 992 - point.y)
	_paper.polygon = vertices

func _sample(keys: Array, field: String, time: float) -> float:
	if keys.is_empty():
		return 0.0
	# 本样例固定 0.125 秒一个关键帧；二分查找也兼容手动调整帧时间。
	var low := 0
	var high := keys.size() - 1
	while high - low > 1:
		var middle := (low + high) / 2
		if float(keys[middle].get("time", 0)) <= time:
			low = middle
		else:
			high = middle
	var a: Dictionary = keys[low]
	var b: Dictionary = keys[high]
	var span := float(b.get("time", 0)) - float(a.get("time", 0))
	var ratio := clampf((time - float(a.get("time", 0))) / span, 0, 1) if span > 0 else 0.0
	return lerpf(float(a.get(field, 0)), float(b.get(field, 0)), ratio)
