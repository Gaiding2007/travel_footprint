// 下载 Natural Earth 50m admin1 并检查字段与规模
import fs from 'node:fs';
import path from 'node:path';

process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
const CACHE = path.join('C:', 'Users', '14127', 'Desktop', 'travel_footprint', 'tools', 'cache');
fs.mkdirSync(CACHE, { recursive: true });
const dest = path.join(CACHE, 'ne_50m_admin_1.geojson');

if (!fs.existsSync(dest) || fs.statSync(dest).size < 1000) {
  const url = 'https://cdn.jsdelivr.net/gh/nvkelso/natural-earth-vector@master/geojson/ne_50m_admin_1_states_provinces.geojson';
  const t0 = Date.now();
  const res = await fetch(url, { signal: AbortSignal.timeout(120000) });
  const buf = Buffer.from(await res.arrayBuffer());
  fs.writeFileSync(dest, buf);
  console.log('downloaded', res.status, buf.length, 'bytes', Date.now() - t0, 'ms');
} else {
  console.log('cached', fs.statSync(dest).size, 'bytes');
}

const geo = JSON.parse(fs.readFileSync(dest, 'utf8'));
console.log('features', geo.features.length);
console.log('props', Object.keys(geo.features[0].properties).join(','));
const sample = geo.features.slice(0, 3).map((f) => f.properties.name + ' | ' + (f.properties.admin || f.properties.adm0_a3 || ''));
console.log('sample', sample);
const byCountry = new Map();
for (const f of geo.features) {
  const key = f.properties.adm0_a3 || f.properties.ADM0_A3 || '??';
  byCountry.set(key, (byCountry.get(key) || 0) + 1);
}
console.log('countries', byCountry.size);
const taiwan = geo.features.filter((f) => /TWN|Taiwan/i.test(f.properties.adm0_a3 + ' ' + f.properties.admin));
console.log('taiwan features', taiwan.length, taiwan.slice(0, 5).map((f) => f.properties.name));
