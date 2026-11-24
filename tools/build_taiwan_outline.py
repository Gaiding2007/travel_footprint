"""用 shapely 把台湾 22 个县市合并成省界（替换 tools/build_taiwan_outline.mjs）。

polygon-clipping 版在台湾西海岸会丢一条边（拼出来的省界有缺口），
这里改用 shapely 的 unary_union + buffer(0) 修正无效几何，结果更可靠。

用法：python tools/build_taiwan_outline.py
"""
import json
from pathlib import Path

from shapely.geometry import MultiPolygon, Polygon
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parent.parent
CN_PATH = ROOT / "assets" / "geo" / "cn.json"
UNIT = 10000
TW_PROVINCE_ID = 71


def entry_rings(entry):
    rings = []
    for ring in entry.get("r", []):
        if ring and isinstance(ring[0], (list, tuple)):
            pts = [(p[0] / UNIT, p[1] / UNIT) for p in ring if p and len(p) >= 2]
        else:
            pts = [(ring[i] / UNIT, ring[i + 1] / UNIT) for i in range(0, len(ring) - 1, 2)]
        if len(pts) >= 3:
            rings.append(pts)
    return rings


def entry_geometry(entry):
    """把 {r: [ring...]} 还原成 shapely 几何。

    存的时候每个环是独立的一圈，没有区分 outer/hole；
    用 even-odd 语义（和 App 里的 PathFillType.evenOdd 一致）重建：
    最大的环当 outer，被它包住的环当 hole。
    """
    rings = entry_rings(entry)
    if not rings:
        return None
    rings.sort(key=lambda r: -abs(Polygon(r).area))
    polys = []
    holes = []
    for i, ring in enumerate(rings):
        poly = Polygon(ring)
        if i == 0:
            polys.append((poly, []))
            continue
        # 判断是否落在已有 outer 内部
        placed = False
        for p, hs in polys:
            if p.contains(poly.representative_point()):
                hs.append(ring)
                placed = True
                break
        if not placed:
            polys.append((poly, []))
    out = []
    for p, hs in polys:
        out.append(Polygon(p.exterior.coords, [h for h in hs]))
    return MultiPolygon(out) if len(out) > 1 else out[0]


def to_rings(geom):
    """几何转回 [[x,y]...] 环列表（整数 1/10000 度）。"""
    polys = [geom] if isinstance(geom, Polygon) else list(geom.geoms)
    rings = []
    for poly in polys:
        for ring in [poly.exterior, *poly.interiors]:
            pairs = []
            for lon, lat in ring.coords:
                x = round(lon * UNIT)
                y = round(lat * UNIT)
                if pairs and pairs[-1][0] == x and pairs[-1][1] == y:
                    continue
                pairs.append([x, y])
            if len(pairs) >= 3:
                rings.append(pairs)
    return rings


def main():
    data = json.loads(CN_PATH.read_text(encoding="utf-8"))
    cities = [c for c in data["cities"] if c.get("p") == TW_PROVINCE_ID]
    if not cities:
        raise SystemExit("cn.json 里没有台湾县市，先跑 build_taiwan.mjs")

    geoms = []
    bad = 0
    for city in cities:
        g = entry_geometry(city)
        if g is None:
            bad += 1
            continue
        if not g.is_valid:
            g = g.buffer(0)
        geoms.append((city.get("e") or city.get("n"), g))

    union = unary_union([g for _, g in geoms])
    union = union.buffer(0)  # 兜底修正
    if not union.is_valid:
        union = union.buffer(0)

    # 形态学开运算：去掉合并时留下的细尖刺（约 0.4km 以下），海岸线细节基本不受影响
    union = union.buffer(0.004, join_style=2).buffer(-0.004, join_style=2)
    if not union.is_valid:
        union = union.buffer(0)

    # 去掉零点几平方公里的碎屑（合并时产生的细条）
    if union.geom_type == "MultiPolygon":
        keep = [p for p in union.geoms if p.area > 5e-6]
        union = MultiPolygon(keep) if len(keep) > 1 else keep[0]

    province = next(p for p in data["provinces"] if p["i"] == TW_PROVINCE_ID)
    before_rings = len(province.get("r", []))
    before_pts = sum(len(r) for r in province.get("r", []))

    rings = to_rings(union)
    province["r"] = rings
    xs = [pt[0] for r in rings for pt in r]
    ys = [pt[1] for r in rings for pt in r]
    province["b"] = [min(xs), min(ys), max(xs), max(ys)]
    province["x"] = round((min(xs) + max(xs)) / 2)
    province["y"] = round((min(ys) + max(ys)) / 2)

    data["meta"] = data.get("meta") or {}
    data["meta"]["taiwanProvinceRings"] = len(rings)
    data["meta"]["taiwanProvincePoints"] = sum(len(r) for r in rings)

    CN_PATH.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    print(f"台湾省界：{len(rings)} 个环 / {sum(len(r) for r in rings)} 个点"
          f"（原来 {before_rings} 环 / {before_pts} 个点），丢弃退化县市 {bad} 个")
    print(f"面积 {union.area:.4f} 平方度，几何类型 {union.geom_type}")


if __name__ == "__main__":
    main()
