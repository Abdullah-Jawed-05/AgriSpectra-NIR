// Usage:
//   node render.mjs <scene> [--fps 30] [--still 1,5,9]   (stills -> frames/<scene>_<t>.jpg)
//   node render.mjs <scene>                               (video  -> out/<scene>.mp4)
import http from 'http';
import fs from 'fs';
import path from 'path';
import { spawn } from 'child_process';
import { chromium } from 'playwright-core';

const root = path.dirname(new URL(import.meta.url).pathname);
const args = process.argv.slice(2);
const scene = args[0];
const opt = (k, d) => (args.includes(k) ? args[args.indexOf(k) + 1] : d);
const fps = +opt('--fps', 30);
const stills = opt('--still', null);
const tail = +opt('--tail', 0);

const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.webp': 'image/webp', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.json': 'application/json' };
const server = http.createServer((req, res) => {
  const p = path.join(root, decodeURIComponent(req.url.split('?')[0]));
  if (!fs.existsSync(p)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': types[path.extname(p)] || 'application/octet-stream' });
  fs.createReadStream(p).pipe(res);
});
await new Promise(r => server.listen(0, r));
const port = server.address().port;

const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--force-color-profile=srgb'],
});
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
page.on('console', m => console.log('[page]', m.text()));
page.on('pageerror', e => console.log('[err]', e.message));
await page.goto(`http://localhost:${port}/scenes/${scene}.html`);
await page.waitForFunction(() => window.SCENE && (!window.SCENE.ready || window.SCENE.ready()), null, { timeout: 60000 });
await page.evaluate(() => document.fonts.ready);
const duration = await page.evaluate(() => window.SCENE.duration);

async function frame(t) {
  await page.evaluate(t => window.SCENE.render(t), t);
  return page.screenshot({ type: 'jpeg', quality: 94 });
}

if (stills) {
  for (const t of stills.split(',').map(Number)) {
    fs.writeFileSync(path.join(root, 'frames', `${scene}_${t}.jpg`), await frame(t));
  }
  console.log('stills done');
} else {
  const total = Math.round((duration + tail) * fps);
  const ff = spawn('ffmpeg', ['-y', '-v', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-i', '-',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '15', '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
    path.join(root, 'out', `${scene}.mp4`)], { stdio: ['pipe', 'inherit', 'inherit'] });
  const t0 = Date.now();
  for (let i = 0; i < total; i++) {
    const buf = await frame(i / fps);
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    if (i % (fps * 5) === 0) console.log(`${scene} ${i}/${total} ${((Date.now() - t0) / 1000).toFixed(0)}s`);
  }
  ff.stdin.end();
  await new Promise(r => ff.on('close', r));
  console.log(`${scene} done: ${total} frames in ${((Date.now() - t0) / 1000).toFixed(0)}s`);
}
await browser.close();
server.close();
