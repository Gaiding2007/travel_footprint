// 探测参考站两个 ECharts geojson chunk 的结构（UTF8Encoding 压缩坐标）
import https from 'node:https';

function get(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, { rejectUnauthorized: false, headers: { 'User-Agent': 'Mozilla/5.0' } }, (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString('utf8') }));
      })
      .on('error', reject);
  });
}

// 把 ES module 的 chunk 变成可直接求值的表达式，返回 default 导出
export function evalChunk(src) {
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
  const fn = new Function(body + '\n;return ' + (defaultName || 'undefined') + ';');
  return fn();
}

export function zigzagDecode(coordinate, encodeOffsets, encodeScale) {
  const result = [];
  let prevX = encodeOffsets[0];
  let prevY = encodeOffsets[1];
  for (let i = 0; i < coordinate.length; i += 2) {
    let x = coordinate.charCodeAt(i) - 64;
    let y = coordinate.charCodeAt(i + 1) - 64;
    x = (x >> 1) ^ -(x & 1);
    y = (y >> 1) ^ -(y & 1);
    x += prevX;
    y += prevY;
    prevX = x;
    prevY = y;
    result.push([x / encodeScale, y / encodeScale]);
  }
  return result;
}

export function decodeGeoJson(json) {
  if (!json.UTF8Encoding) return json;
  const scale = json.UTF8Scale || 1024;
  for (const f of json.features) {
    const g = f.geometry;
    if (!g || !g.encodeOffsets) continue;
    for (let c = 0; c < g.coordinates.length; c++) {
      g.coordinates[c] = g.encodeOffsets[c].map((off, i) => zigzagDecode(g.coordinates[c][i], off, scale));
    }
    g.encodeOffsets = null;
  }
  return json;
}

const CN = 'https://zuji.subsfast.com/static/data-DwacQ-_H.js';
const WORLD = 'https://zuji.subsfast.com/static/global_countries_chn_001-CVjf-O5L.js';

const cnSrc = (await get(CN)).body;
const cn = evalChunk(cnSrc);
console.log('CN keys=' + Object.keys(cn).join(','));
console.log('CN featureCount=' + cn.features.length + ' UTF8Encoding=' + cn.UTF8Encoding + ' scale=' + cn.UTF8Scale);
const levels = {};
for (const f of cn.features) {
  const p = f.properties || {};
  const key = `${p.level}|${f.geometry?.type}`;
  levels[key] = (levels[key] || 0) + 1;
}
console.log('CN levels=' + JSON.stringify(levels));
console.log('CN propKeys=' + Object.keys(cn.features[0].properties).join(','));
console.log('CN sample=' + JSON.stringify(cn.features.slice(0, 3).map((f) => f.properties)));
const decoded = decodeGeoJson(JSON.parse(JSON.stringify(cn)));
const f0 = decoded.features[0];
const ring0 = f0.geometry.coordinates[0][0];
console.log('CN decoded sample coords=' + JSON.stringify(ring0.slice(0, 3)) + ' ringLen=' + ring0.length);
console.log('CN totalRings=' + decoded.features.reduce((a, f) => a + f.geometry.coordinates.reduce((b, poly) => b + poly.length, 0), 0));
console.log('CN totalPoints=' + decoded.features.reduce((a, f) => a + f.geometry.coordinates.reduce((b, poly) => b + poly.reduce((c, r) => c + r.length, 0), 0), 0));

const wSrc = (await get(WORLD)).body;
const w = evalChunk(wSrc);
console.log('WORLD featureCount=' + w.features.length);
console.log('WORLD propKeys=' + Object.keys(w.features[0].properties).join(','));
console.log('WORLD sample=' + JSON.stringify(w.features.slice(0, 4).map((f) => f.properties)));
