// 用台湾 22 个县市的精细边界「合并」出台湾省的省级轮廓
//
// 原来 cn.json 里台湾省（id 71）的轮廓是参考站那份粗数据（11 个环、几十个点），
// 在手机上看省界是明显的折线；市一级的边界却是 ECharts 的精细边界。
// 这里把 22 个县市的多边形做一次真正的并集（polygon-clipping），
// 得到的省界就与县市边界完全贴合，也没有任何重叠。
//
// 依赖：npm i polygon-clipping（tools/package.json）
import fs from 'node:fs';
import polygonClipping from 'polygon-clipping';

const UNIT = 10000;
const TAIWAN_PROVINCE_ID = 71;
const CN_PATH = 'assets/geo/cn.json';

const cn = JSON.parse(fs.readFileSync(CN_PATH, 'utf8'));
const cities = cn.cities.filter((c) => c.p === TAIWAN_PROVINCE_ID);
if (cities.length === 0) {
  console.error('没有找到台湾县市，先跑 build_taiwan.mjs');
  process.exit(1);
}

function ringToCoords(ring) {
  const out = [];
  if (Array.isArray(ring[0])) {
    // 存成 [[x,y], ...] 的形式
    for (const pair of ring) {
      if (!Array.isArray(pair) || pair.length < 2) continue;
      const x = Number(pair[0]) / UNIT;
      const y = Number(pair[1]) / UNIT;
      if (!Number.isFinite(x) || !Number.isFinite(y)) continue;
      const prev = out[out.length - 1];
      if (prev && prev[0] === x && prev[1] === y) continue;
      out.push([x, y]);
    }
  } else {
    for (let i = 0; i + 1 < ring.length; i += 2) {
      const x = Number(ring[i]) / UNIT;
      const y = Number(ring[i + 1]) / UNIT;
      if (!Number.isFinite(x) || !Number.isFinite(y)) continue;
      const prev = out[out.length - 1];
      if (prev && prev[0] === x && prev[1] === y) continue;
      out.push([x, y]);
    }
  }
  if (out.length < 3) return null;
  const first = out[0];
  const last = out[out.length - 1];
  if (first[0] !== last[0] || first[1] !== last[1]) out.push([first[0], first[1]]);
  // 面积太小的退化环 polygon-clipping 会直接报错
  let area = 0;
  for (let i = 0; i < out.length - 1; i++) {
    area += out[i][0] * out[i + 1][1] - out[i + 1][0] * out[i][1];
  }
  if (Math.abs(area) < 1e-12) return null;
  return out;
}

const polygons = [];
for (const city of cities) {
  if (!city.r || city.r.length === 0) continue;
  const rings = city.r.map(ringToCoords).filter(Boolean);
  if (rings.length === 0) continue;
  polygons.push(rings);
}

const merged = polygonClipping.union(...polygons.map((rings) => [rings]));

const outRings = [];
let minX = Infinity;
let minY = Infinity;
let maxX = -Infinity;
let maxY = -Infinity;
let points = 0;
for (const polygon of merged) {
  for (const ring of polygon) {
    const pairs = [];
    for (const [lon, lat] of ring) {
      const x = Math.round(lon * UNIT);
      const y = Math.round(lat * UNIT);
      const prev = pairs[pairs.length - 1];
      // 去掉闭合时重复的最后一个点
      if (prev && prev[0] === x && prev[1] === y) continue;
      pairs.push([x, y]);
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    if (pairs.length >= 3) {
      outRings.push(pairs);
      points += pairs.length;
    }
  }
}

const province = cn.provinces.find((p) => p.i === TAIWAN_PROVINCE_ID);
if (!province) {
  console.error('cn.json 里没有 id 71 的台湾省');
  process.exit(1);
}
const before = province.r.reduce((s, r) => s + r.length / 2, 0);
province.r = outRings;
province.b = [minX, minY, maxX, maxY];
province.x = Math.round((minX + maxX) / 2);
province.y = Math.round((minY + maxY) / 2);

cn.meta = cn.meta ?? {};
cn.meta.taiwanProvinceRings = outRings.length;
cn.meta.taiwanProvincePoints = Math.round(points);
fs.writeFileSync(CN_PATH, JSON.stringify(cn));

console.log(
  `台湾省轮廓：${outRings.length} 个环 / ${Math.round(points)} 个点（原来 ${province.r.length ? before : 0} 个点）`,
);
