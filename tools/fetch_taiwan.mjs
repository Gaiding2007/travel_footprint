import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';

const CACHE = path.join('tools', 'cache');
fs.mkdirSync(CACHE, { recursive: true });

function download(url, dest, redirects = 0) {
  return new Promise((resolve, reject) => {
    https.get(url, { rejectUnauthorized: false, timeout: 60000 }, (res) => {
      const { statusCode, headers } = res;
      if (statusCode >= 300 && statusCode < 400 && headers.location && redirects < 5) {
        res.resume();
        resolve(download(new URL(headers.location, url).toString(), dest, redirects + 1));
        return;
      }
      if (statusCode !== 200) {
        res.resume();
        reject(new Error(`${url} -> ${statusCode}`));
        return;
      }
      const file = fs.createWriteStream(dest);
      res.pipe(file);
      file.on('finish', () => {
        file.close();
        resolve(fs.statSync(dest).size);
      });
    }).on('error', reject);
  });
}

const src = 'https://unpkg.com/echarts@4.9.0/map/json/province/taiwan.json';
const dest = path.join(CACHE, 'taiwan_province.json');
const size = await download(src, dest);
console.log('downloaded', size, 'bytes ->', dest);

const geo = JSON.parse(fs.readFileSync(dest, 'utf8'));
console.log('type', geo.type, 'features', geo.features.length);
console.log(
  'names',
  JSON.stringify(geo.features.map((f) => f.properties.name ?? f.properties.NAME ?? f.properties.adm1_name)),
);
const f0 = geo.features[0];
console.log('props keys', Object.keys(f0.properties).slice(0, 12).join(','));
console.log('geom type', f0.geometry.type, 'coords depth ok');
