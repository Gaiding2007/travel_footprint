// 用 Natural Earth 10m admin_0 的台湾轮廓替换 cn.json 里台湾省（id 71）的边界。
//
// 为什么不用县市并集：ECharts 的台湾县市数据西海岸有多余的尖刺/锯齿，
// 合并出来的省界看着不对（用户反馈"边缘错了"）。NE 10m 的国家轮廓是干净的海岸线，
// 与市界之间只有几百米到一两公里的偏差，在这个缩放级别完全看不出来。
//
// 用法：node tools/build_ne_taiwan_outline.mjs
import fs from 'node:fs';
import path from 'node:path';

const UNIT = 10000;
const CN_PATH = 'assets/geo/cn.json';
const CACHE = path.join('tools', 'cache', 'ne_10m_admin_0');
const SHP = path.join(CACHE, 'ne_10m_admin_0_countries.shp');
const DBF = path.join(CACHE, 'ne_10m_admin_0_countries.dbf');
const TAIWAN_PROVINCE_ID = 71;

function parseDbf(buffer) {
  const recordCount = buffer.readUInt32LE(4);
  const headerLength = buffer.readUInt16LE(8);
  const recordLength = buffer.readUInt16LE(10);
  const fields = [];
  let offset = 32;
  while (buffer[offset] !== 0x0d) {
    const name = buffer.toString('latin1', offset, offset + 11).replace(/\0.*$/, '').trim();
    const type = String.fromCharCode(buffer[offset + 11]);
    const length = buffer[offset + 16];
    fields.push({ name, type, length });
    offset += 32;
  }
  const records = [];
  for (let r = 0; r < recordCount; r++) {
    const base = headerLength + r * recordLength;
    if (buffer[base] === 0x2a) {
      records.push(null);
      continue;
    }
    let cursor = base + 1;
    const record = {};
    for (const field of fields) {
      const raw = buffer.toString('utf8', cursor, cursor + field.length);
      record[field.name] = raw.replace(/\0/g, '').trim();
      cursor += field.length;
    }
    records.push(record);
  }
  return records;
}

function parseShp(buffer) {
  const shapes = [];
  let offset = 100;
  const end = buffer.length - 8;
  while (offset < end) {
    const contentLength = buffer.readInt32BE(offset + 4) * 2;
    const contentStart = offset + 8;
    const shapeType = buffer.readInt32LE(contentStart);
    if (shapeType === 0) {
      shapes.push(null);
      offset = contentStart + contentLength;
      continue;
    }
    const numParts = buffer.readInt32LE(contentStart + 36);
    const numPoints = buffer.readInt32LE(contentStart + 40);
    const partsOffset = contentStart + 44;
    const pointsOffset = partsOffset + numParts * 4;
    const parts = [];
    for (let i = 0; i < numParts; i++) parts.push(buffer.readInt32LE(partsOffset + i * 4));
    const points = [];
    for (let i = 0; i < numPoints; i++) {
      points.push([
        buffer.readDoubleLE(pointsOffset + i * 16),
        buffer.readDoubleLE(pointsOffset + i * 16 + 8),
      ]);
    }
    const rings = [];
    for (let i = 0; i < numParts; i++) {
      const from = parts[i];
      const to = i + 1 < numParts ? parts[i + 1] : numPoints;
      if (to - from >= 4) rings.push(points.slice(from, to));
    }
    shapes.push(rings);
    offset = contentStart + contentLength;
  }
  return shapes;
}

function perpendicularDistance(p, a, b) {
  const dx = b[0] - a[0];
  const dy = b[1] - a[1];
  if (dx === 0 && dy === 0) return Math.hypot(p[0] - a[0], p[1] - a[1]);
  const t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy);
  return Math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy));
}

function simplify(points, tolerance) {
  if (points.length <= 3) return points;
  const first = 0;
  const last = points.length - 1;
  let maxDistance = 0;
  let index = 0;
  for (let i = first + 1; i < last; i++) {
    const d = perpendicularDistance(points[i], points[first], points[last]);
    if (d > maxDistance) {
      maxDistance = d;
      index = i;
    }
  }
  if (maxDistance <= tolerance) return [points[first], points[last]];
  const left = simplify(points.slice(0, index + 1), tolerance);
  const right = simplify(points.slice(index), tolerance);
  return left.slice(0, -1).concat(right);
}

function ringArea(points) {
  let area = 0;
  for (let i = 0; i < points.length; i++) {
    const [x1, y1] = points[i];
    const [x2, y2] = points[(i + 1) % points.length];
    area += x1 * y2 - x2 * y1;
  }
  return area / 2;
}

const dbf = fs.readFileSync(DBF);
const shp = fs.readFileSync(SHP);
const records = parseDbf(dbf);
const shapes = parseShp(shp);

let target = null;
for (let i = 0; i < records.length; i++) {
  const props = records[i];
  if (!props) continue;
  const code = (props.ADM0_A3 || props.ISO_A3 || '').trim();
  const name = (props.NAME || props.NAME_EN || '').trim();
  if (code === 'TWN' || name === 'Taiwan') {
    target = shapes[i];
    break;
  }
}

if (!target || target.length === 0) {
  console.error('NE admin_0 里没有找到台湾');
  process.exit(1);
}

// 只保留面积够大的环（去掉几个像素级的礁石），并按 0.002° 简化
const TOL = 0.002;
const rings = [];
let kept = 0;
let dropped = 0;
for (const ring of target) {
  if (Math.abs(ringArea(ring)) < 1e-5) {
    dropped++;
    continue;
  }
  const simplified = simplify(ring, TOL);
  const pairs = simplified.map(([lon, lat]) => [Math.round(lon * UNIT), Math.round(lat * UNIT)]);
  if (pairs.length >= 3) {
    rings.push(pairs);
    kept++;
  }
}

const cn = JSON.parse(fs.readFileSync(CN_PATH, 'utf8'));
const province = cn.provinces.find((p) => p.i === TAIWAN_PROVINCE_ID);
if (!province) {
  console.error('cn.json 里没有 id 71 的台湾省');
  process.exit(1);
}
const beforeRings = province.r.length;
const beforePts = province.r.reduce((s, r) => s + r.length, 0);
province.r = rings;
const xs = rings.flatMap((r) => r.map((p) => p[0]));
const ys = rings.flatMap((r) => r.map((p) => p[1]));
province.b = [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)];
province.x = Math.round((province.b[0] + province.b[2]) / 2);
province.y = Math.round((province.b[1] + province.b[3]) / 2);

cn.meta = cn.meta || {};
cn.meta.taiwanProvinceSource = 'Natural Earth 10m admin_0_countries';
cn.meta.taiwanProvinceRings = rings.length;
cn.meta.taiwanProvincePoints = rings.reduce((s, r) => s + r.length, 0);
fs.writeFileSync(CN_PATH, JSON.stringify(cn));

console.log(
  `台湾省界（NE 10m）：${kept} 个环 / ${cn.meta.taiwanProvincePoints} 个点` +
    `（原 ${beforeRings} 环 / ${beforePts} 点，丢弃小环 ${dropped} 个）`,
);
