// 第二轮探测：世界 ADM1 数据与台湾市级数据的可用来源
const targets = [
  { name: 'naciscdn-zip', url: 'https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_1_states_provinces.zip', range: [0, 32] },
  { name: 'statically-NE-admin1', url: 'https://cdn.statically.io/gh/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_1_states_provinces.geojson', range: [0, 32] },
  { name: 'githack-NE-admin1', url: 'https://raw.githack.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_1_states_provinces.geojson', range: [0, 32] },
  { name: 'jsdelivr-NE-admin1-110m', url: 'https://cdn.jsdelivr.net/gh/nvkelso/natural-earth-vector@master/geojson/ne_110m_admin_1_states_provinces.geojson', range: [0, 32] },
  { name: 'jsdelivr-NE-admin1-50m', url: 'https://cdn.jsdelivr.net/gh/nvkelso/natural-earth-vector@master/geojson/ne_50m_admin_1_states_provinces.geojson', range: [0, 32] },
  { name: 'datav-taiwan-plain', url: 'https://geo.datav.aliyun.com/areas_v3/bound/710000.json', range: [0, 64] },
  { name: 'datav-taiwan-v4', url: 'https://geo.datav.aliyun.com/areas_v4/bound/710000_full.json', range: [0, 64] },
  { name: 'geoboundaries-TWN-full', url: 'https://www.geoboundaries.org/api/current/gbOpen/TWN/ADM1/', range: [0, 3000] },
  { name: 'jsdelivr-geoboundaries-twn', url: 'https://cdn.jsdelivr.net/gh/wmgeolab/geoBoundaries@main/releaseData/gbOpen/TWN/ADM1/geoBoundaries-TWN-ADM1_simplified.geojson', range: [0, 64] },
  { name: 'jsdelivr-geoboundaries-chn', url: 'https://cdn.jsdelivr.net/gh/wmgeolab/geoBoundaries@main/releaseData/gbOpen/CHN/ADM1/geoBoundaries-CHN-ADM1_simplified.geojson', range: [0, 64] },
];

async function probe(target) {
  const started = Date.now();
  try {
    const res = await fetch(target.url, {
      headers: { 'Range': `bytes=${target.range[0]}-${target.range[1]}`, 'User-Agent': 'Mozilla/5.0' },
      redirect: 'follow',
      signal: AbortSignal.timeout(20000),
    });
    const buf = Buffer.from(await res.arrayBuffer());
    const text = buf.toString('utf8').replace(/\s+/g, ' ').slice(0, 300);
    return `${target.name}: ${res.status} ${res.headers.get('content-length') || '?'}B ${Date.now() - started}ms | ${text}`;
  } catch (error) {
    return `${target.name}: FAIL ${error.name} ${error.message} (${Date.now() - started}ms)`;
  }
}

process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
const results = await Promise.all(targets.map(probe));
for (const line of results) console.log(line);
