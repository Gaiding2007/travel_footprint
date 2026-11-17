import json
from PIL import Image, ImageDraw

PATH = r"C:\Users\14127\Desktop\travel_footprint\assets\geo\admin1.json"
OUT = r"C:\Users\14127\Desktop\travel_footprint\shots\adm1_preview.png"

data = json.load(open(PATH, encoding="utf-8"))
countries = data["countries"]
print("meta", data["meta"])

targets = ["USA", "FRA", "JPN", "RU", "BRA", "ZAF"]
cols, rows = 3, 2
cell_w, cell_h = 460, 340
image = Image.new("RGB", (cell_w * cols, cell_h * rows), (250, 251, 253))
draw = ImageDraw.Draw(image)

for index, code in enumerate(targets):
    regions = countries.get(code)
    cx, cy = index % cols, index // cols
    if not regions:
        draw.text((cx * cell_w + 10, cy * cell_h + 10), f"{code}: none", fill=(200, 0, 0))
        continue
    xs = [r["b"][0] for r in regions] + [r["b"][2] for r in regions]
    ys = [r["b"][1] for r in regions] + [r["b"][3] for r in regions]
    min_x, max_x, min_y, max_y = min(xs), max(xs), min(ys), max(ys)
    span_x = max(max_x - min_x, 1)
    span_y = max(max_y - min_y, 1)
    scale = min((cell_w - 40) / span_x, (cell_h - 50) / span_y)
    ox = cx * cell_w + (cell_w - span_x * scale) / 2
    oy = cy * cell_h + (cell_h - span_y * scale) / 2 + 10

    for region in regions:
        for ring in region["r"]:
            points = [(ox + (x - min_x) * scale, oy + (y - min_y) * scale) for x, y in ring]
            if len(points) > 2:
                draw.polygon(points, fill=(235, 241, 248), outline=(90, 110, 130))
    draw.text((cx * cell_w + 10, cy * cell_h + 6), f"{code}  {len(regions)} regions", fill=(30, 40, 50))

image.save(OUT)
print("saved", OUT, image.size)
