// 探测地理数据源：只打印极简结构摘要，避免刷屏
import https from 'node:https';

function get(url, binary = false) {
  return new Promise((resolve, reject) => {
    https
      .get(url, { rejectUnauthorized: false, headers: { 'User-Agent': 'Mozilla/5.0' } }, (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const buf = Buffer.concat(chunks);
          resolve({ status: res.statusCode, len: buf.length, body: binary ? buf : buf.toString('utf8') });
        });
      })
      .on('error', reject);
  });
}

const DATAV = 'https://geo.datav.aliyun.com/areas_v3/bound';

async function probeJson(url) {
  try {
    const r = await get(url);
    if (r.status !== 200) return { url, status: r.status, len: r.len };
    const j = JSON.parse(r.body);
    const feats = j.features || [];
    return {
      url,
      status: r.status,
      len: r.len,
      features: feats.length,
      sample: feats.slice(0, 6).map((f) => ({
        adcode: f.properties?.adcode,
        name: f.properties?.name,
        level: f.properties?.level,
        childrenNum: f.properties?.childrenNum,
        geom: f.geometry?.type,
      })),
    };
  } catch (e) {
    return { url, error: String(e).slice(0, 120) };
  }
}

const targets = [
  `${DATAV}/100000_full.json`,
  `${DATAV}/110000_full.json`, // 北京（直辖市 → 区）
  `${DATAV}/440000_full.json`, // 广东（地级市）
  `${DATAV}/710000_full.json`, // 台湾
  `${DATAV}/810000_full.json`, // 香港
  `${DATAV}/820000_full.json`, // 澳门
  `${DATAV}/100000.json`,
];

for (const t of targets) {
  const info = await probeJson(t);
  console.log(JSON.stringify(info));
}

// 世界国家：参考站 chunk 结构探测
try {
  const r = await get('https://zuji.subsfast.com/static/global_countries_chn_001-CVjf-O5L.js');
  const s = r.body;
  console.log('WORLD status=' + r.status + ' len=' + r.len);
  console.log('WORLD head=' + s.slice(0, 260).replace(/\s+/g, ' '));
  console.log('WORLD tail=' + s.slice(-200).replace(/\s+/g, ' '));
  const m = s.match(/"properties":\{"name":"[^"]{1,12}"/g);
  console.log('WORLD propHits=' + (m ? m.length : 0));
  const cn = s.match(/[\u4e00-\u9fa5]{2,8}/g) || [];
  console.log('WORLD cjkSample=' + [...new Set(cn)].slice(0, 12).join(','));
} catch (e) {
  console.log('WORLD error ' + String(e).slice(0, 120));
}
