"""生成仇有余的 Spine 4.2 待机样例（只复制原图，不修改像素）。

运行：python tools/build_qyy_spine.py
修改动作：编辑 make_animation()；修改骨骼权重：编辑 influences()。
这是单张剪影的柔和网格形变，不适合抬手、转身等需要补画遮挡部分的动作。
"""
import json
import math
import shutil
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT.parent / "人设/仇有余/qyy_xl_uniform_240/qyy_xl_00000.png"
OUTPUT = PROJECT / "assets/spine/qyy"
DURATION = 8.0

# Spine 使用 Y 向上，脚底为原点；图片使用 Y 向下。
# 名字、父级、世界坐标。腿脚不绑定活动骨骼，保证站稳。
RIG = [
    ("root", None, 0, 0),
    ("hips", "root", 0, 440),
    ("chest", "hips", 0, 740),
    ("head", "chest", -10, 815),
    ("arm_left", "chest", -90, 725),
    ("arm_right", "chest", 90, 725),
    ("hair", "head", -10, 915),
]


def smooth(a, b, value):
    t = max(0.0, min(1.0, (value - a) / (b - a)))
    return t * t * (3 - 2 * t)


def influences(x, y):
    """在颈部、腰部和袖口连续过渡，避免单张网格产生关节折痕。"""
    chest = smooth(590, 280, y)
    hips = smooth(840, 610, y)
    weights = {0: 1 - hips, 1: hips * (1 - chest), 2: hips * chest}
    head = smooth(235, 165, y)
    hair = smooth(135, 55, y) * 0.65
    weights = {b: w * (1 - head) for b, w in weights.items()}
    weights[3] = head * (1 - hair)
    weights[6] = head * hair
    sleeve = smooth(240, 340, y) * (1 - smooth(550, 630, y))
    arm = max(smooth(200, 140, x), smooth(320, 380, x)) * sleeve * 0.8
    weights = {b: w * (1 - arm) for b, w in weights.items()}
    weights[4 if x < 256 else 5] = arm
    return [(b, w) for b, w in weights.items() if w > 0]


def make_animation():
    tracks = {}
    for name in [b[0] for b in RIG[1:]]:
        tracks[name] = {"rotate": [], "translate": []}
    for step in range(65):
        t = step / 8
        phase = math.tau * t / DURATION
        breath = (1 - math.cos(phase * 2)) / 2
        sway = math.sin(phase)
        values = {
            "hips": (0.12 * sway, 0.4 * sway, 0),
            "chest": (0.35 * sway, 0, 1.8 * breath),
            "head": (-0.9 * sway, 0, 0.5 * breath),
            "arm_left": (0.55 * math.sin(phase * 2), 0, -0.4 * breath),
            "arm_right": (-0.4 * math.sin(phase * 2), 0, -0.3 * breath),
            "hair": (0.35 * math.sin(phase * 2), 0, 0),
        }
        for name, (angle, x, y) in values.items():
            tracks[name]["rotate"].append({"time": t, "value": round(angle, 6)})
            tracks[name]["translate"].append({"time": t, "x": round(x, 6), "y": round(y, 6)})
    return {"idle": {"bones": tracks}}


def build():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SOURCE, OUTPUT / "qyy.png")
    bones = []
    by_name = {b[0]: b for b in RIG}
    for name, parent, x, y in RIG:
        bone = {"name": name}
        if parent:
            p = by_name[parent]
            bone.update(parent=parent, x=x - p[2], y=y - p[3], length=60)
        bones.append(bone)

    # 外沿顺时针排列在前，符合 Spine 的 hull 约定；其余为内部顶点。
    columns, rows = 16, 32
    boundary = ([(x, 0) for x in range(columns + 1)]
                + [(columns, y) for y in range(1, rows + 1)]
                + [(x, rows) for x in range(columns - 1, -1, -1)]
                + [(0, y) for y in range(rows - 1, 0, -1)])
    grid = boundary + [(x, y) for y in range(1, rows) for x in range(1, columns)]
    indices = {point: index for index, point in enumerate(grid)}
    uvs, vertices, triangles = [], [], []
    for gx, gy in grid:
        px, py = gx * 32, gy * 32
        uvs.extend([px / 512, py / 1024])
        weights = influences(px, py)
        vertices.append(len(weights))
        for bone, weight in weights:
            _, _, bx, by = RIG[bone]
            vertices.extend([bone, px - 256 - bx, 992 - py - by, weight])
    for y in range(rows):
        for x in range(columns):
            a, b, c, d = [indices[p] for p in [(x, y), (x + 1, y), (x + 1, y + 1), (x, y + 1)]]
            triangles.extend([a, b, c, a, c, d])
    mesh = {"type": "mesh", "path": "qyy", "width": 512, "height": 1024,
            "uvs": uvs, "vertices": vertices, "triangles": triangles, "hull": len(boundary)}
    skeleton = {
        "skeleton": {"spine": "4.2.00", "x": -256, "y": -32, "width": 512,
                     "height": 1024, "fps": 30, "images": "./"},
        "bones": bones,
        "slots": [{"name": "silhouette", "bone": "root", "attachment": "qyy"}],
        "skins": [{"name": "default", "attachments": {"silhouette": {"qyy": mesh}}}],
        "animations": make_animation(),
    }
    (OUTPUT / "qyy.json").write_text(json.dumps(skeleton, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    (OUTPUT / "qyy.atlas").write_text(
        "qyy.png\nsize: 512, 1024\nformat: RGBA8888\nfilter: Linear, Linear\nrepeat: none\n"
        "qyy\n  rotate: false\n  xy: 0, 0\n  size: 512, 1024\n  orig: 512, 1024\n  offset: 0, 0\n  index: -1\n", encoding="utf-8")
    print(f"QYY: {len(bones)} bones, {len(grid)} vertices, {len(triangles)//3} triangles, {DURATION}s idle")


if __name__ == "__main__":
    build()
