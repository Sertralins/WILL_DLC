# xl_anim_tres.py — 从抠图后的帧序列生成 Godot SpriteFrames(.tres)
# 动画名 "default"(AnimatedSprite2D 默认自动播放), 24fps 循环(120 帧 = 5 秒一圈)
# 用法: python tools/xl_anim_tres.py
import os

FRAME_DIR = "res://assets/xl/yf_xl"
OUT_PATH = os.path.join(os.path.dirname(__file__), "..", "assets", "xl", "yf_anim_sprite_frames.tres")
FPS = 24

def main() -> None:
    files = sorted(f for f in os.listdir(os.path.join(os.path.dirname(__file__), "..", "assets", "xl", "yf_xl")) if f.endswith(".png"))
    lines = ["[gd_resource type=\"SpriteFrames\" load_steps=%d format=3]" % (len(files) + 1), ""]
    for i, f in enumerate(files):
        lines.append('[ext_resource type="Texture2D" path="%s/%s" id="1_%s"]' % (FRAME_DIR, f, f[:-4]))
    lines.append("")
    lines.append("[resource]")
    lines.append('animations = [{')
    lines.append('"frames": [')
    for f in files:
        lines.append('{')
        lines.append('"duration": 1.0,')
        lines.append('"texture": ExtResource("1_%s")' % f[:-4])
        lines.append('},')
    lines.append('],')
    lines.append('"loop": true,')
    lines.append('"name": &"default",')
    lines.append('"speed": %.1f' % FPS)
    lines.append('}]')
    with open(OUT_PATH, "w", encoding="utf-8") as fp:
        fp.write("\n".join(lines))
    print("wrote %s (%d frames @ %dfps)" % (OUT_PATH, len(files), FPS))

if __name__ == "__main__":
    main()
