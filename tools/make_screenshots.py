import os
from PIL import Image

SRC = r"C:\Users\14127\Desktop\travel_footprint\shots"
DST = r"C:\Users\14127\Desktop\travel_footprint\docs\screenshots"
os.makedirs(DST, exist_ok=True)

jobs = [
    ("v30p.png", "home-cn.jpg"),
    ("v30n.png", "home-world.jpg"),
    ("v30e.png", "country-detail.jpg"),
    ("v30r.png", "export-preview.jpg"),
    ("v30t.png", "south-china-sea.jpg"),
]

for src, dst in jobs:
    path = os.path.join(SRC, src)
    if not os.path.exists(path):
        print("skip", src)
        continue
    image = Image.open(path).convert("RGB")
    width = 460
    height = round(image.height * width / image.width)
    image = image.resize((width, height), Image.LANCZOS)
    out = os.path.join(DST, dst)
    image.save(out, "JPEG", quality=82, optimize=True)
    print(dst, image.size, os.path.getsize(out))
