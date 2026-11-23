// 把 ECharts 的台湾县市地图（tools/cache/taiwan_province.json）合并进 assets/geo/cn.json
//
// - 原来那 21 条台湾"市"只有很粗糙的几个点，点击几乎点不中、也画不出边界，这里整段替换掉。
// - 顺手从 world.json 里删掉南极洲：墨卡托下它会被拉成一条横贯整屏的"滚木"，很难看。
import fs from 'node:fs';
import path from 'node:path';

const UNIT = 10000; // 存成 经度×10000 / 纬度×10000
const TAIWAN_PROVINCE_ID = 71;

const CN_PATH = path.join('assets', 'geo', 'cn.json');
const WORLD_PATH = path.join('assets', 'geo', 'world.json');
const TW_PATH = path.join('tools', 'cache', 'taiwan_province.json');

// 掉后缀后重名的（新竹市/新竹县、嘉义市/嘉义县）保留全名
const KEEP_FULL = new Set(['新竹市', '新竹县', '嘉义市', '嘉义县']);
const SKIP = new Set(['中国属钓鱼岛']);

function shortName(full) {
  if (KEEP_FULL.has(full)) return full;
  return full.replace(/(市|县)$/, '');
}

// ---------- ECharts UTF8Encoding 解码 ----------
// ECharts 的 geojson 把坐标压成了字符串（每个坐标两个 charCode），必须先解出经纬度再处理。
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
  if (!g || !g.encodeOffsets) return;
  const scale = g.UTF8Scale || 1024;
  for (let c = 0; c < g.coordinates.length; c++) {
    const coord = g.coordinates[c];
    const off = g.encodeOffsets[c];
    if (Array.isArray(off) && Array.isArray(off[0])) {
      for (let k = 0; k < coord.length; k++) coord[k] = decodeRing(coord[k], off[k], scale);
    } else {
      g.coordinates[c] = decodeRing(coord, off, scale);
    }
  }
  g.encodeOffsets = null;
}

function toRing(coords) {
  const ring = [];
  for (const [lon, lat] of coords) {
    ring.push([Math.round(lon * UNIT), Math.round(lat * UNIT)]);
  }
  return ring;
}

function buildEntry(feature, id) {
  decodeFeature(feature);
  const name = feature.properties.name;
  const geom = feature.geometry;
  const polygons = geom.type === 'Polygon' ? [geom.coordinates] : geom.coordinates;

  const rings = [];
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const polygon of polygons) {
    for (const ring of polygon) {
      if (ring.length < 3) continue;
      const converted = toRing(ring);
      rings.push(converted);
      for (const [x, y] of converted) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (rings.length === 0) return null;

  return {
    i: id,
    n: shortName(name),
    e: name,
    x: Math.round((minX + maxX) / 2),
    y: Math.round((minY + maxY) / 2),
    b: [minX, minY, maxX, maxY],
    r: rings,
    p: TAIWAN_PROVINCE_ID,
  };
}

const cn = JSON.parse(fs.readFileSync(CN_PATH, 'utf8'));
const tw = JSON.parse(fs.readFileSync(TW_PATH, 'utf8'));

const features = tw.features
  .filter((f) => !SKIP.has(f.properties.name))
  .sort((a, b) => a.properties.name.localeCompare(b.properties.name, 'zh'));

const taiwanCities = [];
let nextId = 7101;
for (const feature of features) {
  const entry = buildEntry(feature, nextId);
  if (entry) {
    taiwanCities.push(entry);
    nextId += 1;
  }
}

cn.cities = cn.cities.filter((city) => city.p !== TAIWAN_PROVINCE_ID).concat(taiwanCities);
cn.meta = cn.meta ?? {};
cn.meta.taiwanCities = taiwanCities.length;
fs.writeFileSync(CN_PATH, JSON.stringify(cn));

const world = JSON.parse(fs.readFileSync(WORLD_PATH, 'utf8'));
const before = world.countries.length;
world.countries = world.countries.filter((country) => country.i !== 'ATA');
world.meta = world.meta ?? {};
world.meta.removedAntarctica = before - world.countries.length;
fs.writeFileSync(WORLD_PATH, JSON.stringify(world));

const points = taiwanCities.reduce((sum, c) => sum + c.r.reduce((s, r) => s + r.length / 2, 0), 0);
console.log(
  `台湾县市 ${taiwanCities.length} 个（${taiwanCities.map((c) => c.n).join('、')}），共 ${Math.round(points)} 个坐标点`,
);
console.log(`cn.json 城市总数 ${cn.cities.length}，world.json 国家 ${before} -> ${world.countries.length}`);
