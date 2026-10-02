// Copies the third-party files the scenes import into lib/ (kept out of git).
import fs from 'fs';
const copy = (from, to, patch) => {
  let s = fs.readFileSync(from);
  if (patch) s = Buffer.from(String(s).replaceAll("from 'three'", "from './three.module.js'"));
  fs.writeFileSync(to, s);
};
copy('node_modules/three/build/three.module.js', 'lib/three.module.js');
copy('node_modules/three/build/three.core.js', 'lib/three.core.js');
copy('node_modules/three/examples/jsm/geometries/RoundedBoxGeometry.js', 'lib/RoundedBoxGeometry.js', true);
copy('node_modules/three/examples/jsm/environments/RoomEnvironment.js', 'lib/RoomEnvironment.js', true);
copy('node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2', 'lib/inter.woff2');
console.log('lib/ ready');
