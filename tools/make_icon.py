import os
from PIL import Image, ImageDraw

ROOT = r"C:\Users\14127\Desktop\travel_footprint\android\app\src\main\res"
SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

TOP = (74, 134, 240)
BOTTOM = (32, 84, 196)
WHITE = (255, 255, 255, 255)


def make(size: int) -> Image.Image:
    ss = 8  # supersampling for smooth edges
    s = size * ss
    base = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    # 背景：竖向渐变
    gradient = Image.new("RGBA", (1, s))
    for y in range(s):
        t = y / max(s - 1, 1)
        gradient.putpixel(
            (0, y),
            (
                round(TOP[0] + (BOTTOM[0] - TOP[0]) * t),
                round(TOP[1] + (BOTTOM[1] - TOP[1]) * t),
                round(TOP[2] + (BOTTOM[2] - TOP[2]) * t),
                255,
            ),
        )
    gradient = gradient.resize((s, s))

    # 圆角遮罩（Android ic_launcher 会被系统裁切，自己先做圆角更好看）
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.22), fill=255)
    base.paste(gradient, (0, 0), mask)

    draw = ImageDraw.Draw(base)

    # 定位针：圆 + 尖
    cx, cy = s * 0.5, s * 0.42
    r = s * 0.21
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=WHITE)
    draw.polygon(
        [(cx - r * 0.62, cy + r * 0.62), (cx + r * 0.62, cy + r * 0.62), (cx, s * 0.80)],
        fill=WHITE,
    )
    # 针孔
    hole = s * 0.075
    draw.ellipse([cx - hole, cy - hole, cx + hole, cy + hole], fill=(46, 100, 208, 255))

    # 底部一条弧线，像是"足迹轨迹"
    draw.arc(
        [s * 0.20, s * 0.66, s * 0.80, s * 0.98],
        start=200,
        end=340,
        fill=(255, 255, 255, 90),
        width=max(int(s * 0.028), 2),
    )

    return base.resize((size, size), Image.LANCZOS)


for folder, size in SIZES.items():
    target_dir = os.path.join(ROOT, folder)
    os.makedirs(target_dir, exist_ok=True)
    icon = make(size)
    path = os.path.join(target_dir, "ic_launcher.png")
    icon.save(path, "PNG")
    print(folder, size, os.path.getsize(path))
