// 生成 assets/geo 下的地图数据（国内省市 + 世界国家）
//
// 数据来源：公开行政区划边界数据（ECharts geoJSON，UTF-8 压缩编码），
// 由参考站 zuji.subsfast.com 公开发布的分片解码得到：
//   - 几何：/static/data-DwacQ-_H.js（406 个要素，含省/市两级）
//            /static/global_countries_chn_001-CVjf-O5L.js（243 个国家/地区）
//   - 名称：/static/index-DP_JamUQ.js 内的名称表 {id,p,d,n,e}
//
// 输出（坐标一律为“经纬度 × 10000”的整数，减小体积、加快解析）：
//   assets/geo/cn.json    {"meta":{...},"provinces":[Region],"cities":[Region]}
//   assets/geo/world.json {"meta":{...},"countries":[Country]}
// Region = {i:id, n:简称, e:全称, x:标注经度, y:标注纬度, b:[minX,minY,maxX,maxY], r:[[[x,y],...],...]}
import fs from 'node:fs';
import path from 'node:path';
import https from 'node:https';

const ROOT = path.resolve(import.meta.dirname, '..');
const CACHE = path.join(ROOT, 'tools', 'cache');
const OUT = path.join(ROOT, 'assets', 'geo');
const BASE = 'https://zuji.subsfast.com/static';
const FILES = {
  cn: { url: `${BASE}/data-DwacQ-_H.js`, file: 'cn_geo.js' },
  world: { url: `${BASE}/global_countries_chn_001-CVjf-O5L.js`, file: 'world_geo.js' },
  names: { url: `${BASE}/index-DP_JamUQ.js`, file: 'index.js' },
};

const SCALE = 10000; // 坐标放大倍数

function download(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, { rejectUnauthorized: false, headers: { 'User-Agent': 'Mozilla/5.0' } }, (res) => {
        if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode} ${url}`));
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
      })
      .on('error', reject);
  });
}

async function ensure(file) {
  fs.mkdirSync(CACHE, { recursive: true });
  const p = path.join(CACHE, file.file);
  if (fs.existsSync(p)) return fs.readFileSync(p, 'utf8');
  console.log(`下载 ${file.url}`);
  const body = await download(file.url);
  fs.writeFileSync(p, body);
  return body;
}

// ---------- ECharts UTF8Encoding 解码 ----------
function decodeRing(str, offset, scale) {
  const out = [];
  let prevX = offset[0];
  let prevY = offset[1];
  for (let i = 0; i < str.length; i += 2) {
    let x = str.charCodeAt(i) - 64;
    let y = str.charCodeAt(i + 1) - 64;
    x = (x >> 1) ^ -(x & 1);
    y = (y >> 1) ^ -(y & 1);
    x += prevX;
    y += prevY;
    prevX = x;
    prevY = y;
    out.push([x / scale, y / scale]);
  }
  return out;
}

function decodeFeature(feature) {
  const g = feature.geometry;
  const scale = g.UTF8Scale || 1024;
  if (!g.encodeOffsets) return; // 已解码
  for (let c = 0; c < g.coordinates.length; c++) {
    const coord = g.coordinates[c];
    const off = g.encodeOffsets[c];
    // off 为“环形偏移=[x,y]”表示 Polygon 的一个环；
    // off 为“偏移数组=[[x,y],...]”表示 MultiPolygon 的一个多边形（多个环）
    if (Array.isArray(off) && Array.isArray(off[0])) {
      for (let k = 0; k < coord.length; k++) coord[k] = decodeRing(coord[k], off[k], scale);
    } else {
      g.coordinates[c] = decodeRing(coord, off, scale);
    }
  }
  g.encodeOffsets = null;
}

function evalChunkModule(src) {
  const m = src.match(/export\s*\{([^}]*)\}\s*;?\s*$/);
  let body = src;
  let defaultName = null;
  if (m) {
    body = src.slice(0, m.index);
    for (const part of m[1].split(',')) {
      const seg = part.split(/\s+as\s+/);
      if (seg[1] && seg[1].trim() === 'default') defaultName = seg[0].trim();
    }
  }
  return new Function(body + '\n;return ' + (defaultName || 'null') + ';')();
}

// ---------- 简化（Douglas-Peucker，单位：经纬度） ----------
function perpDist(p, a, b) {
  const dx = b[0] - a[0];
  const dy = b[1] - a[1];
  if (dx === 0 && dy === 0) return Math.hypot(p[0] - a[0], p[1] - a[1]);
  const t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy);
  const cx = a[0] + Math.max(0, Math.min(1, t)) * dx;
  const cy = a[1] + Math.max(0, Math.min(1, t)) * dy;
  return Math.hypot(p[0] - cx, p[1] - cy);
}

function simplifyRing(points, tol) {
  if (tol <= 0 || points.length <= 4) return points;
  const keep = new Uint8Array(points.length);
  keep[0] = 1;
  keep[points.length - 1] = 1;
  const stack = [[0, points.length - 1]];
  while (stack.length) {
    const [s, e] = stack.pop();
    let maxD = -1;
    let idx = -1;
    for (let i = s + 1; i < e; i++) {
      const d = perpDist(points[i], points[s], points[e]);
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (maxD > tol && idx > 0) {
      keep[idx] = 1;
      stack.push([s, idx], [idx, e]);
    }
  }
  const out = [];
  for (let i = 0; i < points.length; i++) if (keep[i]) out.push(points[i]);
  return out;
}

// ---------- 工具 ----------
const toInt = (deg) => Math.round(deg * SCALE);

function ringArea(r) {
  let a = 0;
  for (let i = 0, j = r.length - 1; i < r.length; j = i++) {
    a += r[j][0] * r[i][1] - r[i][0] * r[j][1];
  }
  return Math.abs(a / 2);
}

// 去掉连续重复点，并丢弃过小的环（避免渲染大量看不见的碎片）
function cleanRing(ring, minArea) {
  const out = [];
  for (const p of ring) {
    const x = toInt(p[0]);
    const y = toInt(p[1]);
    const last = out[out.length - 1];
    if (!last || last[0] !== x || last[1] !== y) out.push([x, y]);
  }
  if (out.length > 2 && out[0][0] === out[out.length - 1][0] && out[0][1] === out[out.length - 1][1]) {
    out.pop();
  }
  if (out.length < 3) return null;
  if (minArea > 0 && ringArea(out) < minArea) return null;
  return out;
}

function buildRegion(geom, minArea, tolDeg) {
  const polys = geom.type === 'Polygon' ? [geom.coordinates] : geom.coordinates;
  const rings = [];
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const poly of polys) {
    for (let i = 0; i < poly.length; i++) {
      // 面积门槛只用于丢弃“小岛”等外环；洞（i>0）保留
      let cleaned = cleanRing(poly[i], i === 0 ? minArea : 0);
      if (!cleaned) continue;
      if (tolDeg > 0) cleaned = simplifyRing(cleaned, tolDeg * SCALE);
      if (cleaned.length < 4) continue;
      rings.push(cleaned);
      for (const [x, y] of cleaned) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (!rings.length) return null;
  return { rings, bbox: [minX, minY, maxX, maxY] };
}

// ---------- 主流程 ----------
const cnSrc = await ensure(FILES.cn);
const worldSrc = await ensure(FILES.world);
const namesSrc = await ensure(FILES.names);

const cn = evalChunkModule(cnSrc);
const world = evalChunkModule(worldSrc);

for (const f of cn.features) decodeFeature(f);
for (const f of world.features) decodeFeature(f);

// 名称表：{id:11,p:0,d:0,n:"北京",e:"北京市"}
const nameRe = /\{id:(\d+),p:(\d+),d:(\d),n:"([^"]*)",e:"([^"]*)"\}/g;
const names = new Map();
let mm;
while ((mm = nameRe.exec(namesSrc))) {
  const id = Number(mm[1]);
  names.set(id, { id, parent: Number(mm[2]), depth: Number(mm[3]), name: mm[4], full: mm[5] });
}

const geoById = new Map();
for (const f of cn.features) {
  const id = Number(f.properties.id);
  geoById.set(id, f);
}

const MIN_AREA_PROV = 0.0; // 省级保留全部岛屿
const MIN_AREA_CITY = 0.0;
const CN_TOL_PROV = 0.0; // 国内数据本身已是简化版，不再二次简化
const CN_TOL_CITY = 0.0;

const provinces = [];
const cities = [];
const orphanNames = [];
const orphanGeo = [];

for (const rec of names.values()) {
  const f = geoById.get(rec.id);
  if (!f) {
    orphanNames.push(rec.id);
    continue;
  }
  const built = buildRegion(
    f.geometry,
    rec.depth === 0 ? MIN_AREA_PROV : MIN_AREA_CITY,
    rec.depth === 0 ? CN_TOL_PROV : CN_TOL_CITY,
  );
  if (!built) continue;
  const geo = (f.properties.geo || '').split(' ');
  const x = geo.length === 2 ? toInt(Number(geo[0])) : Math.round((built.bbox[0] + built.bbox[2]) / 2);
  const y = geo.length === 2 ? toInt(Number(geo[1])) : Math.round((built.bbox[1] + built.bbox[3]) / 2);
  const item = { i: rec.id, n: rec.name, e: rec.full, x, y, b: built.bbox, r: built.rings };
  if (rec.depth === 0) {
    provinces.push(item);
  } else {
    item.p = rec.parent;
    cities.push(item);
  }
}
for (const id of geoById.keys()) {
  if (!names.has(id)) orphanGeo.push(id);
}

// 世界国家轮廓：0.03°(约 3km) 的简化肉眼不可见，但会把挪威北边那种小岛直接抹成一条线，
// 所以降到 0.008°（约 0.9km），小岛至少能保留成一个小多边形。
const WORLD_TOL = 0.008;
const worldCountries = [];
const seenWorld = new Set();
for (const f of world.features) {
  const p = f.properties;
  const built = buildRegion(f.geometry, 0.0, WORLD_TOL);
  if (!built) continue;
  const id = String(p.id);
  const key = id + '|' + p.nameZh;
  if (seenWorld.has(key)) continue;
  seenWorld.add(key);
  worldCountries.push({
    i: id,
    n: p.nameZh,
    x: toInt(p.x),
    y: toInt(p.y),
    b: built.bbox,
    r: built.rings,
  });
}

const cnOut = {
  meta: {
    version: 1,
    scale: SCALE,
    generatedAt: new Date().toISOString(),
    source: 'ECharts geoJSON (UTF-8 编码) 公开行政区划边界，经 zuji.subsfast.com 分片解码',
    provinceCount: provinces.length,
    cityCount: cities.length,
  },
  provinces,
  cities,
};
const worldOut = {
  meta: {
    version: 1,
    scale: SCALE,
    generatedAt: new Date().toISOString(),
    source: 'ECharts geoJSON (UTF-8 编码) 公开世界国家边界，经 zuji.subsfast.com 分片解码',
    countryCount: worldCountries.length,
  },
  countries: worldCountries,
};

fs.mkdirSync(OUT, { recursive: true });
fs.writeFileSync(path.join(OUT, 'cn.json'), JSON.stringify(cnOut));
fs.writeFileSync(path.join(OUT, 'world.json'), JSON.stringify(worldOut));

const countPoints = (list) => list.reduce((a, r) => a + r.r.reduce((b, ring) => b + ring.length, 0), 0);
const size = (p) => (fs.statSync(p).size / 1024 / 1024).toFixed(2) + 'MB';
console.log(`省 ${provinces.length} 个，市 ${cities.length} 个，点数 ${countPoints([...provinces, ...cities])}`);
console.log(`国家 ${worldCountries.length} 个，点数 ${countPoints(worldCountries)}`);
console.log(`cn.json ${size(path.join(OUT, 'cn.json'))}，world.json ${size(path.join(OUT, 'world.json'))}`);
if (orphanNames.length) console.log('缺少几何的名称 id: ' + orphanNames.slice(0, 20).join(',') + ` (共 ${orphanNames.length})`);
if (orphanGeo.length) console.log('缺少名称的几何 id: ' + orphanGeo.slice(0, 20).join(',') + ` (共 ${orphanGeo.length})`);
const provIds = new Set(provinces.map((p) => p.i));
const noProv = cities.filter((c) => !provIds.has(c.p));
console.log(
  `父级不是省的市: ${noProv.length}` +
    (noProv.length ? ' 例: ' + noProv.slice(0, 8).map((c) => `${c.n}(id=${c.i},p=${c.p})`).join(',') : ''),
);
const big = [...provinces, ...cities].sort((a, b) => countPoints([b]) - countPoints([a])).slice(0, 3);
console.log('点数最多的区域: ' + big.map((r) => `${r.n}(${countPoints([r])})`).join(', '));
