"""生成竖屏 3:4 的 App 介绍图（1200x1600）。

用法：python tools/make_intro.py
产物：docs/intro-3x4.png
"""
from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "shots"
OUT = ROOT / "docs" / "intro-3x4.png"

W, H = 1200, 1600
SCALE = 2  # 先按 2 倍画，最后缩小，边缘更细腻
w, h = W * SCALE, H * SCALE

FONT_REG = "C:/Windows/Fonts/msyh.ttc"
FONT_BOLD = "C:/Windows/Fonts/msyhbd.ttc"

BLUE = (46, 107, 230)
BLUE_DEEP = (32, 84, 196)
LIT = (144, 206, 255)
TEXT = (31, 41, 51)
TEXT_SUB = (107, 122, 140)
BG_TOP = (232, 240, 252)
BG_BOTTOM = (246, 249, 255)


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size * SCALE)


def vertical_gradient(size: tuple[int, int], top, bottom) -> Image.Image:
    grad = Image.new("RGB", (1, size[1]))
    for y in range(size[1]):
        t = y / max(1, size[1] - 1)
        grad.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return grad.resize(size)


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius, fill=255)
    return mask


def draw_china_watermark(canvas: Image.Image) -> None:
    """右下角画一层极淡的中国省界，当作背景纹理。"""
    data = json.loads((ROOT / "assets" / "geo" / "cn.json").read_text(encoding="utf-8"))
    provinces = data["provinces"]
    left = min(p["b"][0] for p in provinces)
    right = max(p["b"][2] for p in provinces)
    top = min(p["b"][1] for p in provinces)
    bottom = max(p["b"][3] for p in provinces)
    box_w = int(w * 0.78)
    factor = box_w / (right - left)
    box_h = int((bottom - top) * factor)
    ox = int(w - box_w + w * 0.12)
    oy = int(h - box_h + h * 0.10)

    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for prov in provinces:
        for ring in prov["r"]:
            pts = [((p[0] - left) * factor + ox, (p[1] - top) * factor + oy) for p in ring]
            if len(pts) < 3:
                continue
            draw.line(pts + [pts[0]], fill=(46, 107, 230, 30), width=3 * SCALE)
    layer = layer.filter(ImageFilter.GaussianBlur(1 * SCALE))
    canvas.alpha_composite(layer)


def draw_logo(canvas: Image.Image, x: int, y: int, size: int) -> None:
    """蓝色圆角方块 + 白色定位针。"""
    box = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(box)
    for i in range(size):
        t = i / size
        color = tuple(round(BLUE[i2] + (BLUE_DEEP[i2] - BLUE[i2]) * t) for i2 in range(3))
        d.line([(0, i), (size, i)], fill=color, width=1)
    box.putalpha(rounded_mask((size, size), int(size * 0.26)))
    d = ImageDraw.Draw(box)
    cx, cy = size / 2, size * 0.45
    r = size * 0.17
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255))
    d.polygon([(cx - r * 0.82, cy + r * 0.55), (cx + r * 0.82, cy + r * 0.55), (cx, cy + r * 2.35)],
              fill=(255, 255, 255))
    d.ellipse([cx - r * 0.34, cy - r * 0.34, cx + r * 0.34, cy + r * 0.34], fill=color)
    canvas.alpha_composite(box, (x, y))


def phone_shot(path: Path, target_h: int, radius: int) -> Image.Image:
    shot = Image.open(path).convert("RGB")
    ratio = shot.width / shot.height
    target_w = int(target_h * ratio)
    shot = shot.resize((target_w, target_h), Image.LANCZOS)
    shot.putalpha(rounded_mask(shot.size, radius))
    return shot


def add_shadow(canvas: Image.Image, mask: Image.Image, xy: tuple[int, int], blur: int, alpha: int) -> None:
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    layer = Image.new("RGBA", mask.size, (20, 45, 90, alpha))
    layer.putalpha(mask)
    shadow.paste(layer, xy, layer)
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)))


def feature_icon(kind: str, size: int) -> Image.Image:
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(icon)
    d.rounded_rectangle([0, 0, size - 1, size - 1], int(size * 0.3), fill=(231, 240, 255))
    cx, cy = size / 2, size / 2
    stroke = max(2, size // 14)
    if kind == "pin":
        r = size * 0.19
        d.ellipse([cx - r, cy - r * 1.35, cx + r, cy + r * 0.65], outline=BLUE, width=stroke)
        d.polygon([(cx - r * 0.75, cy + r * 0.3), (cx + r * 0.75, cy + r * 0.3), (cx, cy + r * 1.7)],
                  fill=BLUE)
        d.ellipse([cx - r * 0.32, cy - r * 0.67, cx + r * 0.32, cy - r * 0.03], fill=(231, 240, 255))
    elif kind == "globe":
        r = size * 0.26
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=BLUE, width=stroke)
        d.ellipse([cx - r * 0.45, cy - r, cx + r * 0.45, cy + r], outline=BLUE, width=stroke)
        d.line([(cx - r, cy), (cx + r, cy)], fill=BLUE, width=stroke)
    else:  # image
        r = size * 0.26
        d.rounded_rectangle([cx - r, cy - r * 0.82, cx + r, cy + r * 0.82], int(size * 0.08),
                            outline=BLUE, width=stroke)
        d.ellipse([cx - r * 0.55, cy - r * 0.45, cx - r * 0.15, cy - r * 0.05], fill=BLUE)
        d.polygon([(cx - r * 0.8, cy + r * 0.6), (cx - r * 0.1, cy - r * 0.05),
                   (cx + r * 0.85, cy + r * 0.6)], fill=BLUE)
    return icon


def main() -> None:
    canvas = vertical_gradient((w, h), BG_TOP, BG_BOTTOM).convert("RGBA")
    draw_china_watermark(canvas)

    # 顶部 Logo + 标题
    logo = 108 * SCALE
    draw_logo(canvas, 96 * SCALE, 92 * SCALE, logo)
    d = ImageDraw.Draw(canvas)
    d.text((96 * SCALE, 214 * SCALE), "旅行足迹", font=font(FONT_BOLD, 62), fill=TEXT)
    d.text((98 * SCALE, 296 * SCALE), "点亮走过的每一座城市", font=font(FONT_REG, 30), fill=TEXT_SUB)

    # 顶部两枚小标签
    tag_font = font(FONT_REG, 21)
    pill_y = 356 * SCALE
    tag_text = "完全离线 · 数据只保存在你自己的手机里"
    tw0 = d.textlength(tag_text, font=tag_font)
    d.rounded_rectangle([96 * SCALE, pill_y, 96 * SCALE + tw0 + 40 * SCALE, pill_y + 42 * SCALE],
                        21 * SCALE, fill=(228, 237, 252))
    d.text((116 * SCALE, pill_y + 8 * SCALE), tag_text, font=tag_font, fill=BLUE)
    ver_font = font(FONT_BOLD, 21)
    ver = "v0.3.4"
    tw1 = d.textlength(ver, font=ver_font)
    x1 = 96 * SCALE + tw0 + 56 * SCALE
    d.rounded_rectangle([x1, pill_y, x1 + tw1 + 36 * SCALE, pill_y + 42 * SCALE], 21 * SCALE, fill=(236, 241, 250))
    d.text((x1 + 18 * SCALE, pill_y + 8 * SCALE), ver, font=ver_font, fill=TEXT_SUB)

    # 手机主视觉
    phone_h = 960 * SCALE
    phone = phone_shot(SHOTS / "t9.png", phone_h, 46 * SCALE)
    phone_x = w - phone.width - 78 * SCALE
    phone_y = 214 * SCALE
    add_shadow(canvas, phone.getchannel("A"), (phone_x + 6 * SCALE, phone_y + 20 * SCALE), 26 * SCALE, 110)
    frame = Image.new("RGBA", (phone.width + 18 * SCALE, phone.height + 18 * SCALE), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle(
        [0, 0, frame.width - 1, frame.height - 1], 54 * SCALE, fill=(255, 255, 255, 255)
    )
    canvas.alpha_composite(frame, (phone_x - 9 * SCALE, phone_y - 9 * SCALE))
    canvas.alpha_composite(phone, (phone_x, phone_y))

    # 左侧三个卖点
    bullets = [
        ("pin", "省市两级，点哪亮哪", "点地图上的城市就只亮这座城市，\n整省可以在列表里一次勾选。"),
        ("globe", "全球 242 个国家和地区", "长按国家进入省 / 州特写，\n点亮一个州就算去过这个国家。"),
        ("image", "一键出图，直接分享", "保存前先看预览，\n可存进相册或直接分享给朋友。"),
    ]
    bx, by = 96 * SCALE, 452 * SCALE
    icon = 62 * SCALE
    gap = 118 * SCALE
    for i, (kind, title, desc) in enumerate(bullets):
        y = by + i * gap
        canvas.alpha_composite(feature_icon(kind, icon), (bx, y))
        d.text((bx + icon + 22 * SCALE, y + 2 * SCALE), title, font=font(FONT_BOLD, 33), fill=TEXT)
        d.multiline_text((bx + icon + 22 * SCALE, y + 40 * SCALE), desc, font=font(FONT_REG, 23),
                         fill=TEXT_SUB, spacing=8 * SCALE)

    # 数据规模
    stats = [("34", "个省级行政区"), ("393", "个地级城市"), ("242", "个国家和地区")]
    sx, sy = 96 * SCALE, 900 * SCALE
    for i, (num, label) in enumerate(stats):
        x = sx + i * 178 * SCALE
        d.text((x, sy), num, font=font(FONT_BOLD, 54), fill=BLUE)
        d.text((x, sy + 72 * SCALE), label, font=font(FONT_REG, 22), fill=TEXT_SUB)
        if i:
            d.line([(x - 34 * SCALE, sy + 6 * SCALE), (x - 34 * SCALE, sy + 96 * SCALE)],
                   fill=(214, 224, 240), width=2 * SCALE)

    # 左下两张缩略图（全球 / 国家特写）
    thumbs = [
        ("n2.png", "全球 242 个国家"),
        ("v20o.png", "国家里的省 / 州"),
    ]
    thumb_h = 350 * SCALE
    thumb_w = int(thumb_h * 1080 / 2400)
    tx, ty = 96 * SCALE, 1078 * SCALE
    step = thumb_w + 34 * SCALE
    for i, (name, caption) in enumerate(thumbs):
        path = SHOTS / name
        if not path.exists():
            continue
        img = phone_shot(path, thumb_h, 18 * SCALE)
        x = tx + i * step
        add_shadow(canvas, img.getchannel("A"), (x + 3 * SCALE, ty + 8 * SCALE), 14 * SCALE, 90)
        canvas.alpha_composite(img, (x, ty))
        cw = d.textlength(caption, font=font(FONT_REG, 20))
        d.text((x + thumb_w / 2 - cw / 2, ty + thumb_h + 16 * SCALE), caption,
               font=font(FONT_REG, 20), fill=TEXT_SUB)

    # 右下角：导出的足迹卡片（倾斜展示）
    card_src = SHOTS / "card_crop.png"
    if card_src.exists():
        card_h = 330 * SCALE
        ratio = Image.open(card_src).width / Image.open(card_src).height
        card_w = int(card_h * ratio)
        card = Image.open(card_src).convert("RGB").resize((card_w, card_h), Image.LANCZOS)
        card = card.convert("RGBA")
        card.putalpha(rounded_mask(card.size, 18 * SCALE))
        rotated = card.rotate(-4, expand=True, resample=Image.BICUBIC)
        cx = w - rotated.width - 96 * SCALE
        cy = 1196 * SCALE
        add_shadow(canvas, rotated.getchannel("A"), (cx + 4 * SCALE, cy + 12 * SCALE), 18 * SCALE, 100)
        canvas.alpha_composite(rotated, (cx, cy))
        caption = "出图后可存相册 / 直接分享"
        cw2 = d.textlength(caption, font=font(FONT_REG, 20))
        d.text((w - 96 * SCALE - cw2, cy + rotated.height + 12 * SCALE), caption,
               font=font(FONT_REG, 20), fill=TEXT_SUB)

    final = canvas.convert("RGB").resize((W, H), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    final.save(OUT, "PNG")
    print("saved", OUT, final.size)


if __name__ == "__main__":
    main()
