// 探测可用的世界行政区（ADM1）数据源与台湾市级数据源
const targets = [
  { name: 'jsdelivr-world-atlas', url: 'https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json', range: [0, 64] },
  { name: 'jsdelivr-NE-admin1', url: 'https://cdn.jsdelivr.net/gh/nvkelso/natural-earth-vector@master/geojson/ne_10m_admin_1_states_provinces.geojson', range: [0, 64] },
  { name: 'jsdelivr-NE-admin1-labels', url: 'https://cdn.jsdelivr.net/gh/nvkelso/natural-earth-vector@master/geojson/ne_10m_admin_1_states_provinces_lakes.geojson', range: [0, 64] },
  { name: 'unpkg-world-atlas', url: 'https://unpkg.com/world-atlas@2/countries-110m.json', range: [0, 64] },
  { name: 'geoboundaries-api', url: 'https://www.geoboundaries.org/api/current/gbOpen/TWN/ADM1/', range: [0, 256] },
  { name: 'datav-taiwan', url: 'https://geo.datav.aliyun.com/areas_v3/bound/710000_full.json', range: [0, 64] },
  { name: 'npmjs', url: 'https://registry.npmjs.org/-/ping', range: [0, 64] },
  { name: 'aliyun-geojson-cdn', url: 'https://cdn.jsdelivr.net/gh/echarts-maps/echarts-countries-js@master/echarts-countries-js/china-contour.json', range: [0, 64] },
];

async function probe(target) {
  const started = Date.now();
  try {
    const res = await fetch(target.url, {
      headers: { 'Range': `bytes=${target.range[0]}-${target.range[1]}`, 'User-Agent': 'Mozilla/5.0' },
      redirect: 'follow',
      signal: AbortSignal.timeout(15000),
    });
    const buf = Buffer.from(await res.arrayBuffer());
    const text = buf.toString('utf8').replace(/\s+/g, ' ').slice(0, 80);
    return `${target.name}: ${res.status} ${res.headers.get('content-length') || '?'}B ${Date.now() - started}ms | ${text}`;
  } catch (error) {
    return `${target.name}: FAIL ${error.name} ${error.message} (${Date.now() - started}ms)`;
  }
}

process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
const results = await Promise.all(targets.map(probe));
for (const line of results) console.log(line);
