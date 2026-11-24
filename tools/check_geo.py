"""数据体检：省界重叠、小岛是否保留、台湾省轮廓点数。

用法：python tools/check_geo.py
"""
import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GEO = ROOT / "assets" / "geo"


def load(name):
    return json.loads((GEO / name).read_text(encoding="utf-8"))


def rings_of(entry):
    """把 {r:[[[x,y],...]]} 统一成 [[(lon,lat)]]，坐标单位是 1/10000 度。"""
    out = []
    for ring in entry.get("r", []):
        pts = []
        if ring and isinstance(ring[0], (list, tuple)):
            for pair in ring:
                if pair and len(pair) >= 2:
                    pts.append((pair[0] / 10000.0, pair[1] / 10000.0))
        else:
            for i in range(0, len(ring) - 1, 2):
                pts.append((ring[i] / 10000.0, ring[i + 1] / 10000.0))
        if len(pts) >= 3:
            out.append(pts)
    return out


def contains(rings, x, y):
    inside = False
    for pts in rings:
        n = len(pts)
        j = n - 1
        for i in range(n):
            xi, yi = pts[i]
            xj, yj = pts[j]
            if (yi > y) != (yj > y):
                xcross = xi + (y - yi) * (xj - xi) / (yj - yi)
                if x < xcross:
                    inside = not inside
            j = i
    return inside


def bbox(entry):
    b = entry.get("b")
    if b:
        return b[0] / 10000.0, b[1] / 10000.0, b[2] / 10000.0, b[3] / 10000.0
    lons = [p[0] for r in rings_of(entry) for p in r]
    lats = [p[1] for r in rings_of(entry) for p in r]
    return min(lons), min(lats), max(lons), max(lats)


def check_overlap(admin1, code, samples=4000, seed=7):
    regions = admin1["countries"].get(code)
    if not regions:
        print(f"{code}: 没有省级数据")
        return
    shapes = [(r.get("n") or r.get("e"), rings_of(r), bbox(r)) for r in regions]
    minx = min(s[2][0] for s in shapes)
    miny = min(s[2][1] for s in shapes)
    maxx = max(s[2][2] for s in shapes)
    maxy = max(s[2][3] for s in shapes)
    rnd = random.Random(seed)
    hist = {}
    worst = None
    for _ in range(samples):
        x = rnd.uniform(minx, maxx)
        y = rnd.uniform(miny, maxy)
        hits = [s[0] for s in shapes if s[2][0] <= x <= s[2][2] and s[2][1] <= y <= s[2][3] and contains(s[1], x, y)]
        n = len(hits)
        hist[n] = hist.get(n, 0) + 1
        if n >= 2 and worst is None:
            worst = (round(x, 3), round(y, 3), hits)
    print(f"{code}: 省份 {len(shapes)} 个，抽样 {samples} 点 → 覆盖层数分布 {dict(sorted(hist.items()))}")
    if worst:
        print(f"   重叠样例 {worst[0]},{worst[1]} 同时落在 {worst[2]}")


def ring_stats(entry):
    rings = rings_of(entry)
    small = [r for r in rings if len(r) <= 6]
    return len(rings), sum(len(r) for r in rings), len(small)


def main():
    world = load("world.json")
    admin1 = load("admin1.json")
    cn = load("cn.json")

    print("== 文件 ==")
    for name in ("cn.json", "world.json", "admin1.json"):
        print(f"   {name}: {(GEO / name).stat().st_size / 1024 / 1024:.2f} MB")
    print(f"   国家 {len(world['countries'])}，admin1 国家 {len(admin1['countries'])}，"
          f"省 34 / 市 {len(cn['cities'])}")

    print("\n== 台湾省轮廓 ==")
    tw = [p for p in cn["provinces"] if p["i"] == 71][0]
    rings, pts, small = ring_stats(tw)
    print(f"   环 {rings} 个 / 点 {pts} 个 / 小环 {small} 个")

    print("\n== 小岛保留（世界国家轮廓） ==")
    for code in ("NOR", "CHL", "IDN", "GRC"):
        c = next((x for x in world["countries"] if x["i"] == code), None)
        if not c:
            print(f"   {code}: 缺")
            continue
        rings, pts, small = ring_stats(c)
        print(f"   {code} {c['n']}: 环 {rings} 个 / 点 {pts} 个 / 小于 7 点的小环 {small} 个")

    print("\n== 省界重叠抽样 ==")
    for code in ("THA", "NOR", "USA"):
        check_overlap(admin1, code)


if __name__ == "__main__":
    main()
