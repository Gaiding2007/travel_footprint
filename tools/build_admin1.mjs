// 用 Natural Earth 10m admin1（shapefile）生成：
//   1) assets/geo/admin1.json —— 世界各国内部的一级行政区（省/州）边界，供"国家特写"用
//   2) 台湾省的市级边界 —— 注入 assets/geo/cn.json 的 cities（原来台湾只有一个整体）
// 坐标格式与 cn.json / world.json 一致：整数，x=(经度+180)*10000, y=(90-纬度)*10000
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve('.');
const CACHE = path.join(ROOT, 'tools', 'cache', 'ne_10m_admin_1');
const SHP = path.join(CACHE, 'ne_10m_admin_1_states_provinces.shp');
const DBF = path.join(CACHE, 'ne_10m_admin_1_states_provinces.dbf');

const UNIT = 10000;
const PROJECT_DEG = 1000;

// ---------- DBF ----------
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
      const value = raw.replace(/\0/g, '').trim();
      record[field.name] = value;
      cursor += field.length;
    }
    records.push(record);
  }
  return records;
}

// ---------- SHP ----------
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
    // Polygon(5) / PolygonZ(15) / PolygonM(25)：前段结构一致
    const numParts = buffer.readInt32LE(contentStart + 36);
    const numPoints = buffer.readInt32LE(contentStart + 40);
    const partsOffset = contentStart + 44;
    const pointsOffset = partsOffset + numParts * 4;
    const parts = [];
    for (let i = 0; i < numParts; i++) parts.push(buffer.readInt32LE(partsOffset + i * 4));
    const points = [];
    for (let i = 0; i < numPoints; i++) {
      points.push([buffer.readDoubleLE(pointsOffset + i * 16), buffer.readDoubleLE(pointsOffset + i * 16 + 8)]);
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

// ---------- 几何工具 ----------
function perpendicularDistance(p, a, b) {
  const dx = b[0] - a[0];
  const dy = b[1] - a[1];
  if (dx === 0 && dy === 0) return Math.hypot(p[0] - a[0], p[1] - a[1]);
  const t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy);
  const px = a[0] + t * dx;
  const py = a[1] + t * dy;
  return Math.hypot(p[0] - px, p[1] - py);
}

function simplify(points, tolerance) {
  if (points.length <= 3) return points;
  const first = 0;
  const last = points.length - 1;
  let maxDistance = 0;
  let index = 0;
  for (let i = first + 1; i < last; i++) {
    const distance = perpendicularDistance(points[i], points[first], points[last]);
    if (distance > maxDistance) {
      maxDistance = distance;
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
  for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
    area += points[j][0] * points[i][1] - points[i][0] * points[j][1];
  }
  return Math.abs(area / 2);
}

function bboxOf(rings) {
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const ring of rings) {
    for (const [x, y] of ring) {
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }
  return [minX, minY, maxX, maxY];
}

// App 读取时按 x/10+180000、90000-y/10 还原，所以这里存的是 经度*10000 / 纬度*10000
const encodeX = (lon) => Math.round(lon * UNIT);
const encodeY = (lat) => Math.round(lat * UNIT);

function buildRegion(name, fullName, rings, labelLon, labelLat, tolerance, minRingArea) {
  const kept = [];
  for (const ring of rings) {
    const area = ringArea(ring);
    if (area < minRingArea) continue;
    const simple = simplify(ring, tolerance);
    if (simple.length < 4) continue;
    kept.push(simple.map(([lon, lat]) => [encodeX(lon), encodeY(lat)]));
  }
  if (kept.length === 0) {
    for (const ring of rings.slice(0, 1)) {
      const simple = simplify(ring, tolerance);
      if (simple.length >= 4) kept.push(simple.map(([lon, lat]) => [encodeX(lon), encodeY(lat)]));
    }
  }
  if (kept.length === 0) return null;
  const box = bboxOf(kept.map((ring) => ring.map(([x, y]) => [x / UNIT, y / UNIT])));
  const center = [encodeX((box[0] + box[2]) / 2), encodeY((box[1] + box[3]) / 2)];
  const label =
    Number.isFinite(labelLon) && Number.isFinite(labelLat)
      ? [encodeX(labelLon), encodeY(labelLat)]
      : center;
  const xs = kept.flatMap((ring) => ring.map((p) => p[0]));
  const ys = kept.flatMap((ring) => ring.map((p) => p[1]));
  return {
    n: name,
    e: fullName || name,
    x: label[0],
    y: label[1],
    b: [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)],
    r: kept,
  };
}

// ---------- 主流程 ----------
console.log('reading shapefile…');
const records = parseDbf(fs.readFileSync(DBF));
const shapes = parseShp(fs.readFileSync(SHP));
console.log('records', records.length, 'shapes', shapes.length);

// 台湾的 21 个县市：GB/T 2260 代码 ← Natural Earth 的 iso_3166_2 编码
const TAIWAN_UNITS = {
  'TW-TPE': 7101,
  'TW-KHH': 7102,
  'TW-TNN': 7103,
  'TW-TXG': 7104,
  'TW-KIN': 7105,
  'TW-NAN': 7106,
  'TW-KEE': 7107,
  'TW-HSZ': 7108,
  'TW-CYI': 7109,
  'TW-TPQ': 7111,
  'TW-ILA': 7112,
  'TW-HSQ': 7113,
  'TW-TAO': 7114,
  'TW-MIA': 7115,
  'TW-CHA': 7117,
  'TW-CYQ': 7119,
  'TW-YUN': 7121,
  'TW-PIF': 7124,
  'TW-TTT': 7125,
  'TW-HUA': 7126,
  'TW-PEN': 7127,
};

const countries = {};
const taiwan = [];
let keptFeatures = 0;
let droppedFeatures = 0;

for (let i = 0; i < records.length; i++) {
  const props = records[i];
  const rings = shapes[i];
  if (!props || !rings || rings.length === 0) {
    droppedFeatures++;
    continue;
  }
  const code = (props.adm0_a3 || '').trim();
  if (!code || code === '-99' || code === '') {
    droppedFeatures++;
    continue;
  }
  const nameZh = (props.name_zh || props.name_zht || '').trim();
  const nameEn = (props.name_en || props.name || '').trim();
  const labelLon = Number(props.longitude);
  const labelLat = Number(props.latitude);
  const areaDeg = Number(props.area_sqkm) > 0 ? Number(props.area_sqkm) : 10000;

  // 岛屿/小区域的简化力度小一些，大区域大一些
  const tolerance = Math.min(Math.max(Math.sqrt(areaDeg) / 2600, 0.004), 0.03);
  const minRingArea = Math.max(areaDeg / 9000, 0.0008);

  if (code === 'TWN') {
    const iso = (props.iso_3166_2 || '').trim();
    const unitId = TAIWAN_UNITS[iso] ?? null;
    const region = buildRegion(nameZh || nameEn, nameEn, rings, labelLon, labelLat, tolerance, minRingArea);
    if (region) {
      taiwan.push({ unit: unitId, name: nameZh || nameEn, region });
    }
    continue;
  }

  const region = buildRegion(nameZh || nameEn, nameEn, rings, labelLon, labelLat, tolerance, minRingArea);
  if (!region) {
    droppedFeatures++;
    continue;
  }
  keptFeatures++;
  if (!countries[code]) countries[code] = [];
  countries[code].push(region);
}

// 台湾：按 GB 代码生成市级要素（新竹市/县、嘉义市/县 名称不能简称，否则重名）
const taiwanCities = [];
const baseCount = new Map();
for (const item of taiwan) {
  const base = item.name.replace(/[市县]$/, '');
  baseCount.set(base, (baseCount.get(base) || 0) + 1);
}
let fallbackId = 7140;
for (const item of taiwan) {
  const base = item.name.replace(/[市县]$/, '');
  const short = (baseCount.get(base) || 0) > 1 ? item.name : base;
  const id = item.unit ?? fallbackId++;
  taiwanCities.push({
    i: id,
    p: 71,
    n: short,
    e: item.name,
    x: item.region.x,
    y: item.region.y,
    b: item.region.b,
    r: item.region.r,
  });
}
taiwanCities.sort((a, b) => a.i - b.i);

// 输出 admin1.json
const admin1 = {
  meta: {
    source: 'Natural Earth 10m admin_1_states_provinces',
    unit: UNIT,
    countries: Object.keys(countries).length,
    regions: keptFeatures,
  },
  countries,
};
const admin1Path = path.join(ROOT, 'assets', 'geo', 'admin1.json');
fs.writeFileSync(admin1Path, JSON.stringify(admin1));
console.log('admin1.json', (fs.statSync(admin1Path).size / 1024 / 1024).toFixed(2), 'MB', 'countries', Object.keys(countries).length, 'regions', keptFeatures, 'dropped', droppedFeatures);

// 把台湾的市写进 cn.json（幂等）
const cnPath = path.join(ROOT, 'assets', 'geo', 'cn.json');
const cn = JSON.parse(fs.readFileSync(cnPath, 'utf8'));
const existing = cn.cities.filter((city) => city.p === 71);
const others = cn.cities.filter((city) => city.p !== 71);
cn.cities = others.concat(taiwanCities);
cn.cities.sort((a, b) => a.i - b.i);
cn.meta.cities = cn.cities.length;
fs.writeFileSync(cnPath, JSON.stringify(cn));
console.log('cn.json cities', cn.cities.length, '台湾市', existing.length, '->', taiwanCities.length, (fs.statSync(cnPath).size / 1024 / 1024).toFixed(2), 'MB');
console.log('台湾市:', taiwanCities.map((city) => `${city.i}${city.n}`).join(' '));

// 覆盖率检查：world.json 里的国家有几个没有省级数据
const world = JSON.parse(fs.readFileSync(path.join(ROOT, 'assets', 'geo', 'world.json'), 'utf8'));
const worldCodes = world.countries.map((country) => country.i);
const missing = worldCodes.filter((code) => !countries[code]);
console.log('world countries', worldCodes.length, 'with admin1', worldCodes.length - missing.length, 'missing', missing.length);
console.log('missing codes:', missing.join(','));
const extra = Object.keys(countries).filter((code) => !worldCodes.includes(code));
console.log('admin1 codes not in world.json:', extra.length, extra.slice(0, 40).join(','));
