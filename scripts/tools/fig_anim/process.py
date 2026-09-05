# fig_anim/process.py — 立绘序列模板: 透明底 PNG 序列 → 循环动画框
#
# 用法: python process.py <input_dir> <anim_name> [fps] [force]
#   input_dir  含透明底序列 PNG 的目录(任意帧数、任意尺寸, 帧按文件名排序)
#   anim_name  动画名(输出目录与节点名都基于它)
#   fps        帧率, 默认 24
#   force      存在输出时也重做(默认跳过)
#
# 流程:
#   1. 帧原样复制为 assets/fig_anim/output/<name>/frames/<name>_NNNNN.png
#      (像素零改动; 缺少透明通道的帧给出警告);
#   2. 生成 assets/fig_anim/output/<name>/<name>_sprite_frames.tres(循环动画);
#   3. 生成 scenes/fig_anim/<name>_anim.tscn(可拖拽动画框, 尺寸随帧自适应)。
import os
import sys
import shutil
from PIL import Image

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_FRAMES = os.path.join(PROJECT_ROOT, "assets", "fig_anim", "output", "%s", "frames")
OUT_TRES = os.path.join(PROJECT_ROOT, "assets", "fig_anim", "output", "%s", "%s_sprite_frames.tres")
OUT_SCENE = os.path.join(PROJECT_ROOT, "scenes", "fig_anim", "%s_anim.tscn")


def write_tres(name: str, count: int, fps: float, path: str) -> None:
    lines = ['[gd_resource type="SpriteFrames" load_steps=%d format=3]' % (count + 1), ""]
    for i in range(count):
        lines.append('[ext_resource type="Texture2D" path="res://assets/fig_anim/output/%s/frames/%s_%05d.png" id="1_%05d"]' % (name, name, i, i))
    lines += ["", "[resource]", 'animations = [{', '"frames": [']
    for i in range(count):
        lines += ['{', '"duration": 1.0,', '"texture": ExtResource("1_%05d")' % i, '},']
    lines += ['],', '"loop": true,', '"name": &"default",', '"speed": %.1f' % fps, '}]']
    with open(path, "w", encoding="utf-8") as fp:
        fp.write("\n".join(lines))


def write_scene(name: str, w: int, h: int, path: str) -> None:
    node = "".join(w[:1].upper() + w[1:] for w in name.split("_")) + "Anim"
    lines = [
        "[gd_scene load_steps=2 format=3]",
        "",
        '[ext_resource type="SpriteFrames" path="res://assets/fig_anim/output/%s/%s_sprite_frames.tres" id="1_frames"]' % (name, name),
        "",
        '[node name="%s" type="Control"]' % node,
        "custom_minimum_size = Vector2(%d, %d)" % (w, h),
        "offset_right = %d.0" % w,
        "offset_bottom = %d.0" % h,
        "mouse_filter = 2",
        "",
        '[node name="Bounds" type="ReferenceRect" parent="."]',
        "layout_mode = 0",
        "offset_right = %d.0" % w,
        "offset_bottom = %d.0" % h,
        "border_color = Color(1, 0.85, 0.25, 0.7)",
        "border_width = 2.0",
        "",
        '[node name="Frames" type="AnimatedSprite2D" parent="."]',
        "position = Vector2(%d, %d)" % (w / 2.0, h / 2.0),
        'sprite_frames = ExtResource("1_frames")',
        "playing = true",
        'autoplay = "default"',
    ]
    with open(path, "w", encoding="utf-8") as fp:
        fp.write("\n".join(lines))


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    input_dir, name = sys.argv[1], sys.argv[2]
    fps = float(sys.argv[3]) if len(sys.argv) > 3 else 24.0
    force = len(sys.argv) > 4 and sys.argv[4] == "force"

    tres_path = OUT_TRES % (name, name)
    if os.path.exists(tres_path) and not force:
        print("跳过(已处理过): %s" % name)
        return
    files = sorted(f for f in os.listdir(input_dir) if f.lower().endswith(".png"))
    if not files:
        print("错误: %s 里没有 PNG 序列" % input_dir)
        sys.exit(1)
    print("处理 %s: %d 帧 @ %.0ffps" % (name, len(files), fps))

    # 尺寸取自第一帧(序列应同源, 各帧一致)
    first = Image.open(os.path.join(input_dir, files[0]))
    w, h = first.size
    print("  尺寸 %dx%d" % (w, h))

    out_dir = OUT_FRAMES % name
    if os.path.exists(out_dir):
        shutil.rmtree(out_dir)
    os.makedirs(out_dir, exist_ok=True)
    no_alpha: list = []
    for i, f in enumerate(files):
        src = os.path.join(input_dir, f)
        im = Image.open(src)
        if im.mode not in ("RGBA", "LA") and "transparency" not in im.info:
            no_alpha.append(f)
        im.close()
        shutil.copyfile(src, os.path.join(out_dir, "%s_%05d.png" % (name, i)))
    if no_alpha:
        print("  警告: %d 帧没有透明通道(显示为不透明), 如 %s" % (len(no_alpha), no_alpha[0]))

    write_tres(name, len(files), fps, tres_path)
    write_scene(name, w, h, OUT_SCENE % name)
    print("完成 -> scenes/fig_anim/%s_anim.tscn (把本场景拖进界面即可)" % name)


if __name__ == "__main__":
    main()
