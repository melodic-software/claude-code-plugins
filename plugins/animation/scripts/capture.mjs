// usage: node capture.mjs <url> <outdir> <k,k,...> [workers=4]   one PNG per drawing: window.renderDrawing(k) -> dNNN.png
//        node capture.mjs <url> <outdir> --fps <n> [workers=4]  every frame of the film: window.renderFrame(i / n) -> fNNNN.png
// Saves canvas#c at its own size after awaiting the render Promise. Encode frames with
//   ffmpeg -framerate <n> -i <outdir>/f%04d.png -c:v libx264 -pix_fmt yuv420p -crf 16 film.mp4
// playwright-core is resolved from PW_CORE, then the working directory, then a playwright-cli install on PATH.
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import { mkdirSync, realpathSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

function chromium() {
  const tries = [
    () => createRequire(import.meta.url)(process.env.PW_CORE),
    () => createRequire(join(process.cwd(), 'x.js'))('playwright-core'),
    () => createRequire(join(process.cwd(), 'x.js'))('playwright'),
    () => {
      const bin = execSync('command -v playwright-cli', { shell: '/bin/sh' }).toString().trim();
      return createRequire(realpathSync(join(dirname(bin), '..', '@playwright', 'cli', 'package.json')))('playwright-core');
    },
  ];
  for (const t of tries) { try { const m = t(); if (m?.chromium) return m.chromium; } catch { /* next */ } }
  console.error('capture.mjs: playwright-core not found. Set PW_CORE to its path, `npm i playwright-core` in the working directory, or install @playwright/cli; then `npx playwright install chromium`.');
  process.exit(2);
}

const [url, out, sel, ...rest] = process.argv.slice(2);
const fps = sel === '--fps' ? +rest.shift() : 0, workers = +(rest[0] || 4);
mkdirSync(out, { recursive: true });
const browser = await chromium().launch();
let failed = false;
const open = async () => {
  const p = await browser.newPage();
  p.on('pageerror', e => { console.error('pageerror:', e.message); failed = true; });
  await p.goto(url);
  await p.waitForFunction(() => typeof window.renderFrame === 'function', null, { timeout: 30000 });
  return p;
};
const pages = [await open()];
const jobs = fps
  ? Array.from({ length: Math.round(await pages[0].evaluate(() => window.DURATION) * fps) }, (_, i) => ({ t: i / fps, name: `f${String(i).padStart(4, '0')}.png` }))
  : sel.split(',').map(Number).map(k => ({ k, name: `d${String(k).padStart(3, '0')}.png` }));
while (pages.length < Math.min(workers, jobs.length)) pages.push(await open());
let next = 0;
await Promise.all(pages.map(async p => {
  while (next < jobs.length) {
    const j = jobs[next++];
    const b64 = await p.evaluate(async j => {
      await ('k' in j ? window.renderDrawing(j.k) : window.renderFrame(j.t));
      return document.getElementById('c').toDataURL('image/png').split(',')[1];
    }, j);
    writeFileSync(join(out, j.name), Buffer.from(b64, 'base64'));
  }
}));
await browser.close();
process.exit(failed ? 1 : 0);
