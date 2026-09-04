# xl_alpha.py — 伊芙立绘序列抠图: 黑底 → 透明底白色剪影
# 素材: assets/xl/yf_xl/伊芙_绿屏立绘_XXXXX.png (512×1024, 黑底 + ~74 亮度灰度人物)
# 输出: assets/xl/alpha/yf_XXXXX.png (RGBA, 白色人物, alpha = clamp(lum/74, 0, 1))
# 用法: python tools/xl_alpha.py
import os
from PIL import Image

SRC_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "xl", "yf_xl")
DST_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "xl", "alpha")
BODY_LUM = 74  # 人物主体亮度(全序列众数稳定在 72~74), 用于把主体归一化到 alpha=1

def main() -> None:
    os.makedirs(DST_DIR, exist_ok=True)
    files = sorted(f for f in os.listdir(SRC_DIR) if f.endswith(".png"))
    print("frames:", len(files))
    for f in files:
        im = Image.open(os.path.join(SRC_DIR, f)).convert("L")
        alpha = im.point(lambda v: min(255, v * 255 // BODY_LUM))
        white = Image.new("L", im.size, 255)
        out = Image.merge("RGBA", (white, white, white, alpha))
        out.save(os.path.join(DST_DIR, "yf_" + f[-9:]))  # 保留 00000~00119 编号
    print("done ->", DST_DIR)

if __name__ == "__main__":
    main()
