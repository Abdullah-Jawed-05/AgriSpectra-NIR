import fs from 'fs';
import * as topo from 'topojson-client';
import { geoMercator, geoPath, geoContains } from 'd3-geo';
const w = JSON.parse(fs.readFileSync('node_modules/world-atlas/countries-50m.json'));
const fc = topo.feature(w, w.objects.countries);
const pk = fc.features.find(f => f.properties.name === 'Pakistan');
const W = 900, H = 900;
const proj = geoMercator().fitSize([W, H], pk);
const path = geoPath(proj);
const step = 17; const dots = [];
for (let y = 0; y < H; y += step) for (let x = 0; x < W; x += step) {
  const xx = x + ((y / step) % 2 ? step / 2 : 0);
  const ll = proj.invert([xx, y]);
  if (geoContains(pk, ll)) dots.push([+xx.toFixed(1), y]);
}
fs.writeFileSync('lib/pakdots.js', `export const PAK_OUTLINE=${JSON.stringify(path(pk))};\nexport const PAK_DOTS=${JSON.stringify(dots)};\nexport const PAK_SIZE=[${W},${H}];\n`);
console.log(dots.length);
