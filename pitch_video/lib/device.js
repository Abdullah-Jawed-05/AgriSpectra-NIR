// AgriSpectra NIR device, modelled after the product renders.
// Units: 1 = 10 mm. Body 110 (x) x 75 (y) x 80 (z) mm. Drawer exits on +x.
import * as THREE from './three.module.js';
import { RoundedBoxGeometry } from './RoundedBoxGeometry.js';
import { RoomEnvironment } from './RoomEnvironment.js';
import { rng } from './core.js';

export { THREE };

export function makeRenderer(canvas, { alpha = false } = {}) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha, preserveDrawingBuffer: true });
  renderer.setPixelRatio(1);
  renderer.setSize(1920, 1080, false);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.localClippingEnabled = true;
  return renderer;
}

export function studio(scene, renderer) {
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  scene.environmentIntensity = 0.35;
  const key = new THREE.DirectionalLight(0xfff4e8, 2.4); key.position.set(-6, 10, 8); scene.add(key);
  const rim = new THREE.DirectionalLight(0xbfe8ff, 2.2); rim.position.set(8, 5, -9); scene.add(rim);
  const fill = new THREE.DirectionalLight(0xffffff, 0.5); fill.position.set(6, 2, 10); scene.add(fill);
  return { key, rim, fill };
}

function canvasTex(w, h, draw) {
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4;
  return t;
}

export function blobShadow(w = 16, d = 12, o = 0.75) {
  const tex = canvasTex(256, 256, (g, W, H) => {
    const gr = g.createRadialGradient(W / 2, H / 2, 0, W / 2, H / 2, W / 2);
    gr.addColorStop(0, `rgba(0,0,0,${o})`); gr.addColorStop(0.55, `rgba(0,0,0,${o * 0.45})`); gr.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = gr; g.fillRect(0, 0, W, H);
  });
  const m = new THREE.Mesh(new THREE.PlaneGeometry(w, d), new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false }));
  m.rotation.x = -Math.PI / 2;
  return m;
}

const mats = () => ({
  shell: new THREE.MeshStandardMaterial({ color: 0x1b1c1d, roughness: 0.62, metalness: 0.05, transparent: true }),
  shellDark: new THREE.MeshStandardMaterial({ color: 0x121313, roughness: 0.7, metalness: 0.05, transparent: true }),
  rubber: new THREE.MeshStandardMaterial({ color: 0x0c0c0c, roughness: 0.95 }),
  pcb: new THREE.MeshStandardMaterial({ color: 0x0f5a32, roughness: 0.45, metalness: 0.1 }),
  chip: new THREE.MeshStandardMaterial({ color: 0x151515, roughness: 0.4 }),
  shield: new THREE.MeshStandardMaterial({ color: 0xc9ccce, roughness: 0.25, metalness: 0.9 }),
  gold: new THREE.MeshStandardMaterial({ color: 0xd9b25a, roughness: 0.3, metalness: 0.9 }),
  white: new THREE.MeshStandardMaterial({ color: 0xece6da, roughness: 0.5 }),
  blueBoard: new THREE.MeshStandardMaterial({ color: 0x1d4fc4, roughness: 0.45 }),
  redBoard: new THREE.MeshStandardMaterial({ color: 0xc8302e, roughness: 0.45 }),
  battery: new THREE.MeshStandardMaterial({ color: 0x1e74e6, roughness: 0.28, metalness: 0.15 }),
  steel: new THREE.MeshStandardMaterial({ color: 0xbfc3c6, roughness: 0.3, metalness: 0.95 }),
  glass: new THREE.MeshStandardMaterial({ color: 0xe8f4f2, roughness: 0.05, metalness: 0, transparent: true, opacity: 0.22, depthWrite: false }),
  seed: new THREE.MeshStandardMaterial({ color: 0xcfa46a, roughness: 0.55 }),
  ledWhite: new THREE.MeshStandardMaterial({ color: 0xffffff, emissive: 0xfff6dc, emissiveIntensity: 0 }),
  ledGreen: new THREE.MeshStandardMaterial({ color: 0x1a3a22, emissive: 0x3cff8a, emissiveIntensity: 0 }),
  wireR: new THREE.MeshStandardMaterial({ color: 0xc8402a, roughness: 0.5 }),
});

function box(w, h, d, mat, r = 0) {
  const g = r > 0 ? new RoundedBoxGeometry(w, h, d, 4, r) : new THREE.BoxGeometry(w, h, d);
  return new THREE.Mesh(g, mat);
}

export async function loadFonts() {
  await document.fonts.load('600 110px Inter'); await document.fonts.load('500 44px Inter');
}

export function buildDevice() {
  const M = mats();
  const root = new THREE.Group();
  const P = {}; // parts (each a Group with .home position)
  const part = (name) => { const g = new THREE.Group(); g.name = name; root.add(g); P[name] = g; return g; };

  // ---- main body: open-top shell (hidden under the top cover when assembled),
  // with the drawer opening cut into the lower part of the +x end.
  const body = part('body');
  const A = 5.5, B = 4, r = 0.95, th = 0.3, A2 = A - th, B2 = B - th, r2 = r - th;
  const ring = (gap) => {
    const sh = new THREE.Shape();
    // shape y == world -z (geometry is rotated below); gap spans world z -2.6..3.1
    const g1 = -3.1, g2 = 2.6;
    if (gap) sh.moveTo(A, g2); else sh.moveTo(A, 0);
    sh.lineTo(A, B - r); sh.absarc(A - r, B - r, r, 0, Math.PI / 2, false);
    sh.lineTo(-A + r, B); sh.absarc(-A + r, B - r, r, Math.PI / 2, Math.PI, false);
    sh.lineTo(-A, -B + r); sh.absarc(-A + r, -B + r, r, Math.PI, 1.5 * Math.PI, false);
    sh.lineTo(A - r, -B); sh.absarc(A - r, -B + r, r, 1.5 * Math.PI, 2 * Math.PI, false);
    if (gap) {
      sh.lineTo(A, g1); sh.lineTo(A2, g1);
      sh.lineTo(A2, -B2 + r2); sh.absarc(A2 - r2, -B2 + r2, r2, 0, -Math.PI / 2, true);
      sh.lineTo(-A2 + r2, -B2); sh.absarc(-A2 + r2, -B2 + r2, r2, -Math.PI / 2, -Math.PI, true);
      sh.lineTo(-A2, B2 - r2); sh.absarc(-A2 + r2, B2 - r2, r2, Math.PI, Math.PI / 2, true);
      sh.lineTo(A2 - r2, B2); sh.absarc(A2 - r2, B2 - r2, r2, Math.PI / 2, 0, true);
      sh.lineTo(A2, g2); sh.closePath();
    } else {
      sh.closePath();
      const h = new THREE.Path();
      h.moveTo(A2, 0); h.lineTo(A2, -B2 + r2); h.absarc(A2 - r2, -B2 + r2, r2, 0, -Math.PI / 2, true);
      h.lineTo(-A2 + r2, -B2); h.absarc(-A2 + r2, -B2 + r2, r2, -Math.PI / 2, -Math.PI, true);
      h.lineTo(-A2, B2 - r2); h.absarc(-A2 + r2, B2 - r2, r2, Math.PI, Math.PI / 2, true);
      h.lineTo(A2 - r2, B2); h.absarc(A2 - r2, B2 - r2, r2, Math.PI / 2, 0, true);
      h.closePath(); sh.holes.push(h);
    }
    return sh;
  };
  const extr = (shape, y0, y1, bevel) => {
    const g = new THREE.ExtrudeGeometry(shape, { depth: y1 - y0 - 2 * bevel, bevelEnabled: bevel > 0, bevelThickness: bevel, bevelSize: bevel * 0.6, bevelSegments: 4, curveSegments: 18 });
    g.rotateX(-Math.PI / 2); g.translate(0, y0 + bevel, 0);
    const m = new THREE.Mesh(g, M.shell); m.material.side = THREE.DoubleSide; return m;
  };
  const lower = extr(ring(true), 0.35, 4.3, 0.14); body.add(lower);
  const upper = extr(ring(false), 4.25, 6.35, 0.14); body.add(upper);
  const floor = box(10.6, 0.3, 7.6, M.shellDark, 0.1); floor.position.y = 0.55; body.add(floor);
  const bodyMesh = upper;
  const bayL = box(0.12, 2.8, 5.9, M.shellDark); bayL.position.set(0.3, 1.95, 0.25); body.add(bayL);
  const bayB = box(5.2, 2.8, 0.12, M.shellDark); bayB.position.set(2.9, 1.95, -2.75); body.add(bayB);
  const bayT = box(5.2, 0.12, 5.9, M.shellDark); bayT.position.set(2.9, 3.3, 0.25); body.add(bayT);
  // ridged grip panel on -x end
  const grip = new THREE.Group();
  const gripBase = box(0.1, 4.4, 5.0, M.shellDark, 0.0); gripBase.position.set(-5.6, 3.4, 0); grip.add(gripBase);
  for (let i = 0; i < 16; i++) {
    const rr = box(0.08, 0.09, 5.0, M.rubber); rr.position.set(-5.67, 1.6 + i * 0.25, 0); rr.rotation.x = 0.62; grip.add(rr);
  }
  body.add(grip);
  // branding on the +z long face
  const brandTex = canvasTex(1024, 512, (g, W, H) => {
    g.clearRect(0, 0, W, H);
    g.fillStyle = 'rgba(150,154,152,0.85)';
    g.save(); g.translate(250, 130);
    g.beginPath(); g.moveTo(0, 60); g.bezierCurveTo(10, 10, 60, -10, 90, -10); g.bezierCurveTo(90, 40, 50, 80, 0, 60); g.fill();
    g.restore();
    g.font = '600 110px Inter'; g.fillText('AgriSpectra', 230, 290);
    g.font = '500 44px Inter'; g.fillStyle = 'rgba(130,134,132,0.8)';
    g.fillText('Seeds Today,', 240, 360); g.fillText('Bigger Tomorrows', 240, 415);
  });
  const brand = new THREE.Mesh(new THREE.PlaneGeometry(5.2, 2.6), new THREE.MeshBasicMaterial({ map: brandTex, transparent: true, depthWrite: false }));
  brand.position.set(-0.2, 3.5, 4.1); brand.rotation.z = -0.12; body.add(brand);
  P.bodyMesh = bodyMesh; P.brand = brand;
  // USB-C on -z face
  const usb = box(0.95, 0.36, 0.1, M.rubber, 0.08); usb.position.set(-3.6, 2.2, -4.1); body.add(usb);

  // ---- bottom cover + feet
  const bottom = part('bottom');
  const bot = box(10.6, 0.35, 7.6, M.shellDark, 0.15); bot.position.y = 0.18; bottom.add(bot);
  [[-4.2, -2.9], [4.2, -2.9], [-4.2, 2.9], [4.2, 2.9]].forEach(([x, z]) => {
    const f = new THREE.Mesh(new THREE.CylinderGeometry(0.45, 0.45, 0.22, 24), M.rubber); f.position.set(x, -0.05, z); bottom.add(f);
  });

  // ---- top cover with button + status LED
  const top = part('top');
  const topMesh = box(11.1, 0.95, 8.1, M.shell, 0.45); topMesh.position.y = 6.75; top.add(topMesh);
  const btnRing = new THREE.Mesh(new THREE.CylinderGeometry(0.78, 0.78, 0.06, 48), M.rubber); btnRing.position.set(3.0, 7.24, -0.6); top.add(btnRing);
  const btn = new THREE.Mesh(new THREE.CylinderGeometry(0.62, 0.66, 0.26, 48), M.shellDark); btn.position.set(3.0, 7.34, -0.6); top.add(btn);
  const led = new THREE.Mesh(new THREE.SphereGeometry(0.11, 16, 12), M.ledGreen); led.position.set(3.15, 7.24, -1.95); top.add(led);
  P.button = btn; P.statusLed = led;

  // ---- main PCB with ESP32 module, TP4056 (blue), LDO (red)
  const pcb = part('pcb');
  const board = box(6.6, 0.12, 5.6, M.pcb); board.position.set(-1.7, 5.6, 0); pcb.add(board);
  const esp = box(1.9, 0.18, 2.4, M.chip); esp.position.set(-3.0, 5.75, -0.6); pcb.add(esp);
  const can = box(1.5, 0.22, 1.6, M.shield, 0.04); can.position.set(-3.0, 5.85, -0.85); pcb.add(can);
  const ant = box(1.9, 0.02, 0.6, M.gold); ant.position.set(-3.0, 5.85, 0.4); pcb.add(ant);
  const R = rng(5);
  for (let i = 0; i < 12; i++) {
    const c = box(0.25 + R() * 0.45, 0.12, 0.2 + R() * 0.4, M.chip); c.position.set(-1.6 + R() * 2.8, 5.72, -2.3 + R() * 4.6); pcb.add(c);
  }
  const conn = box(0.9, 0.5, 0.5, M.white); conn.position.set(0.9, 5.95, -2.2); pcb.add(conn);
  const tp = box(1.4, 0.1, 1.0, M.blueBoard); tp.position.set(0.4, 5.75, 1.3); pcb.add(tp);
  const tpChip = box(0.5, 0.12, 0.4, M.chip); tpChip.position.set(0.4, 5.85, 1.3); pcb.add(tpChip);
  const ldo = box(0.9, 0.1, 0.8, M.redBoard); ldo.position.set(1.0, 5.75, -0.2); pcb.add(ldo);
  const ldoChip = box(0.4, 0.14, 0.3, M.chip); ldoChip.position.set(1.0, 5.86, -0.2); pcb.add(ldoChip);
  P.esp = can; P.tp = tp; P.ldo = ldo;

  // ---- 18650 battery in a holder
  const batt = part('battery');
  const holder = box(6.8, 0.9, 2.1, M.rubber, 0.08); holder.position.set(-1.9, 4.0, -2.0); batt.add(holder);
  const cell = new THREE.Mesh(new THREE.CylinderGeometry(0.9, 0.9, 6.5, 48), M.battery);
  cell.rotation.z = Math.PI / 2; cell.position.set(-1.9, 4.6, -2.0); batt.add(cell);
  const capA = new THREE.Mesh(new THREE.CylinderGeometry(0.88, 0.88, 0.12, 48), M.steel); capA.rotation.z = Math.PI / 2; capA.position.set(1.4, 4.6, -2.0); batt.add(capA);
  const capB = capA.clone(); capB.position.x = -5.2; batt.add(capB);
  const band = new THREE.Mesh(new THREE.CylinderGeometry(0.905, 0.905, 0.5, 48), M.white); band.rotation.z = Math.PI / 2; band.position.set(-4.6, 4.6, -2.0); batt.add(band);
  P.cell = cell;

  // ---- optical chamber: LED + AS7265x sensor above the sample, light baffle
  const optics = part('optics');
  const baffle = box(3.4, 2.0, 3.6, M.shellDark, 0.1); baffle.position.set(3.2, 4.2, 0.6); optics.add(baffle);
  const ledBoard = box(0.9, 0.08, 0.9, M.white); ledBoard.position.set(2.5, 5.25, 0.6); optics.add(ledBoard);
  const ledDie = new THREE.Mesh(new THREE.CylinderGeometry(0.28, 0.28, 0.12, 24), M.ledWhite); ledDie.position.set(2.5, 5.33, 0.6); optics.add(ledDie);
  const sensBoard = box(1.3, 0.1, 1.3, M.pcb); sensBoard.position.set(3.9, 5.25, 0.6); optics.add(sensBoard);
  const sensChip = box(0.6, 0.14, 0.6, M.gold); sensChip.position.set(3.9, 5.33, 0.6); optics.add(sensChip);
  P.led = ledDie; P.sensor = sensChip; P.baffle = baffle;
  // leave the baffle see-through so the light path stays visible
  baffle.material = baffle.material.clone(); baffle.material.transparent = true; baffle.material.opacity = 0.88;

  // ---- drawer: tray + front panel + petri dish with seeds
  const drawer = part('drawer');
  const tray = box(5.2, 0.25, 5.4, M.shellDark, 0.08); tray.position.set(3.0, 1.35, 0.25); drawer.add(tray);
  const wallL = box(5.2, 0.9, 0.18, M.shellDark); wallL.position.set(3.0, 1.75, -2.4); drawer.add(wallL);
  const wallR = wallL.clone(); wallR.position.z = 2.9; drawer.add(wallR);
  const front = box(0.5, 3.2, 6.2, M.shell, 0.18); front.position.set(5.75, 2.55, 0.25); drawer.add(front);
  const slot = box(0.06, 0.12, 3.4, M.rubber, 0.03); slot.position.set(6.01, 2.2, 0.25); slot.rotation.x = 0; drawer.add(slot);
  const dish = new THREE.Mesh(new THREE.CylinderGeometry(1.75, 1.75, 0.55, 64, 1, true), M.glass); dish.position.set(3.1, 1.76, 0.4); drawer.add(dish);
  const dishBase = new THREE.Mesh(new THREE.CylinderGeometry(1.75, 1.75, 0.04, 64), M.glass); dishBase.position.set(3.1, 1.5, 0.4); drawer.add(dishBase);
  const seedGeo = new THREE.SphereGeometry(0.13, 14, 10); seedGeo.scale(2.4, 0.95, 1);
  const RS = rng(9);
  const seedMesh = new THREE.InstancedMesh(seedGeo, M.seed, 46);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler();
  for (let i = 0; i < 46; i++) {
    const a = RS() * Math.PI * 2, r = Math.sqrt(RS()) * 1.45;
    e.set((RS() - .5) * 0.6, RS() * Math.PI, (RS() - .5) * 0.6); q.setFromEuler(e);
    m4.compose(new THREE.Vector3(3.1 + Math.cos(a) * r, 1.66 + RS() * 0.18, 0.4 + Math.sin(a) * r), q, new THREE.Vector3(1, 1, 1));
    seedMesh.setMatrixAt(i, m4);
    seedMesh.setColorAt(i, new THREE.Color().setHSL(0.09 + RS() * 0.02, 0.45, 0.55 + RS() * 0.1));
  }
  drawer.add(seedMesh);
  P.dish = dish; P.seeds = seedMesh; P.front = front;

  // battery leads to PCB
  const wire = new THREE.Mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3([
    new THREE.Vector3(-5.3, 4.6, -2.0), new THREE.Vector3(-5.1, 5.2, -1.6), new THREE.Vector3(-4.6, 5.6, -1.6)]), 20, 0.05, 8), M.wireR);
  batt.add(wire);

  for (const k in P) if (P[k].isGroup) P[k].userData.home = P[k].position.clone();
  return { root, P, M };
}

/** Explode offsets (multiplied by p in 0..1). */
export const EXPLODE = {
  top: [0, 7.4, 0],
  pcb: [0, 4.5, 0],
  battery: [0, 3.2, 0],
  optics: [0.6, 2.4, 0.9],
  drawer: [5.4, -0.2, 0.5],
  bottom: [0, -2.4, 0],
  body: [0, 0, 0],
};

export function setExplode(P, p) {
  for (const k in EXPLODE) {
    const o = EXPLODE[k];
    P[k].position.set(o[0] * p, o[1] * p, o[2] * p);
  }
}

/** Screen-space position of a world point, in CSS pixels on a 1920x1080 stage. */
export function toScreen(v, camera) {
  const p = v.clone().project(camera);
  return { x: (p.x + 1) / 2 * 1920, y: (1 - p.y) / 2 * 1080 };
}
