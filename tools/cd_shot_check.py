# cd_shot_check.py — 倒计时色彩条截图采样:
#   对 cd_shot1/2.png 在 L/R 两条条件句块区域按行扫描,
#   找「亮块 / 黑间隙」交替模式并对比两帧的相位(验证彩块在滚动);
#   再采样表盘中心与四周, 确认旋转时钟同场。
# 用法: python tools/cd_shot_check.py
import os
from PIL import Image

BASE = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\WILL_game")
Y = 950               # 采样行: 两条条都完整覆盖(避开上下渐隐区)
L = (365, 905)        # 左栏条 x 范围(条 360..910, 内缩 8)
R = (1015, 1555)      # 右栏条 x 范围(条 1010..1560, 内缩 8)
BRIGHT = 100          # RGB 之和超过即视为彩块像素(线性空间截图, 数值偏暗)


def bright_runs(im, x0, x1, y):
    runs, start = [], None
    for x in range(x0, x1):
        p = im.getpixel((x, y))
        on = sum(p) > BRIGHT
        if on and start is None:
            start = x
        elif not on and start is not None:
            runs.append((start, x - 1, im.getpixel(((start + x - 1) // 2, y))))
            start = None
    if start is not None:
        runs.append((start, x1 - 1, im.getpixel(((start + x1 - 1) // 2, y))))
    return runs


def main():
    for name in ("cd_shot1.png", "cd_shot2.png"):
        im = Image.open(os.path.join(BASE, name)).convert("RGB")
        print(f"== {name} {im.size}")
        for label, (x0, x1) in (("L", L), ("R", R)):
            runs = bright_runs(im, x0, x1, Y)
            print(f"{label} 亮块段数={len(runs)} ", end="")
            for s, e, c in runs:
                print(f"[{s}..{e}]{c}", end=" ")
            print()
            if runs:
                gaps = [runs[i + 1][0] - runs[i][1] - 1 for i in range(len(runs) - 1)]
                print(f"{label} 间隙像素={gaps}")
        # 表盘中心与四角(时钟在屏幕中央)
        for pt in ((960, 527), (800, 400), (1120, 680)):
            print("clock@", pt, im.getpixel(pt))
        # 屏幕角落(遮罩压暗后的背景)
        print("corner", im.getpixel((20, 20)), im.getpixel((1900, 1030)))


if __name__ == "__main__":
    main()
