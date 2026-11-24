// 省界「去重叠」：同一国家内的省/州如果互相压到，把后画的（面积小的）裁掉重叠部分。
//
// Natural Earth 10m 的省界本身就不是严格无缝的：简化之后相邻省会在边界处互相压住一点点，
// 手机上放大看就是"省界线交叉"。这里用 polygon-clipping 做一次真正的差集，
// 保证同一国家内任意两个省州的内部不再相交（边界相邻）。
//
// 用法：node tools/fix_admin1_overlaps.mjs [--country=THA] [--dry]
import fs from 'node:fs';
import polygonClipping from 'polygon-clipping';

const CN_PATH = 'assets/geo/admin1.json';
const UNIT = 10000;

const args = process.argv.slice(2);
const only = args.find((a) => a.startsWith('--country='))?.split('=')[1] ?? null;
const dry = args.includes('--dry');

const data = JSON.parse(fs.readFileSync(CN_PATH, 'utf8'));

function toMulti(entry) {
  const polys = [];
  for (const ring of entry.r) {
    const pts = Array.isArray(ring[0])
      ? ring.map((p) => [p[0] / UNIT, p[1] / UNIT])
      : Array.from({ length: Math.floor(ring.length / 2) }, (_, i) => [ring[i * 2] / UNIT, ring[i * 2 + 1] / UNIT]);
    if (pts.length < 3) continue;
    const first = pts[0];
    const last = pts[pts.length - 1];
    if (first[0] !== last[0] || first[1] !== last[1]) pts.push([first[0], first[1]]);
    polys.push([pts]);
  }
  return polys; // MultiPolygon: [[ring], [ring], ...]（每个洞单独一个 polygon，够用）
}

function fromMulti(multi) {
  const rings = [];
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const poly of multi) {
    for (const ring of poly) {
      const pairs = [];
      for (const [lon, lat] of ring) {
        const x = Math.round(lon * UNIT);
        const y = Math.round(lat * UNIT);
        const prev = pairs[pairs.length - 1];
        if (prev && prev[0] === x && prev[1] === y) continue;
        pairs.push([x, y]);
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
      if (pairs.length >= 3) rings.push(pairs);
    }
  }
  return { rings, bbox: [minX, minY, maxX, maxY] };
}

function areaOf(entry) {
  let total = 0;
  for (const ring of entry.r) {
    const pts = Array.isArray(ring[0]) ? ring : Array.from({ length: Math.floor(ring.length / 2) }, (_, i) => [ring[i * 2], ring[i * 2 + 1]]);
    let a = 0;
    for (let i = 0; i < pts.length; i++) {
      const [x1, y1] = pts[i];
      const [x2, y2] = pts[(i + 1) % pts.length];
      a += x1 * y2 - x2 * y1;
    }
    total += Math.abs(a / 2);
  }
  return total;
}

function bboxIntersects(a, b) {
  return !(a[2] <= b[0] || b[2] <= a[0] || a[3] <= b[1] || b[3] <= a[1]);
}

let fixedCountries = 0;
let fixedRegions = 0;
const report = [];
const t0 = Date.now();

for (const [code, regions] of Object.entries(data.countries)) {
  if (only && code !== only) continue;
  if (regions.length < 2) continue;

  // 面积大的先保留原样，小的后处理（被裁掉的是小省交界处的细条）
  const order = regions
    .map((r, i) => ({ r, i, a: areaOf(r) }))
    .sort((x, y) => y.a - x.a)
    .map((x) => x.i);

  const done = []; // 已定稿的几何
  const doneBoxes = [];
  let countryFixed = 0;

  for (const idx of order) {
    let multi = toMulti(regions[idx]);
    const bbox = regions[idx].b;
    let touched = false;

    for (let k = 0; k < done.length; k++) {
      if (!bboxIntersects(bbox, doneBoxes[k])) continue;
      try {
        const diff = polygonClipping.difference(multi, done[k]);
        if (Array.isArray(diff)) {
          multi = diff;
          touched = true;
        }
      } catch {
        // 几何本身有自交之类的问题，跳过这一块
      }
    }

    const rebuilt = fromMulti(multi);
    if (touched && rebuilt.rings.length > 0) {
      regions[idx].r = rebuilt.rings;
      regions[idx].b = rebuilt.bbox.map((v) => Math.round(v));
      regions[idx].x = Math.round((rebuilt.bbox[0] + rebuilt.bbox[2]) / 2);
      regions[idx].y = Math.round((rebuilt.bbox[1] + rebuilt.bbox[3]) / 2);
      countryFixed++;
    }
    done.push(multi);
    doneBoxes.push(regions[idx].b);
  }

  if (countryFixed > 0) {
    fixedCountries++;
    fixedRegions += countryFixed;
    report.push(`${code}: ${countryFixed}/${regions.length}`);
  }
}

if (!dry) fs.writeFileSync(CN_PATH, JSON.stringify(data));

console.log(`处理 ${fixedCountries} 个国家、${fixedRegions} 个区域，用时 ${((Date.now() - t0) / 1000).toFixed(1)}s`);
if (report.length) console.log(report.slice(0, 20).join('  '));
