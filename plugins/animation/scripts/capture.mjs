// usage: node capture.mjs [--playwright-core DIR] <url> <outdir> <k,k,...> <workers>   one PNG per drawing:
//                                               window.renderDrawing(k) -> dNNN.png
//        node capture.mjs [--playwright-core DIR] <url> <outdir> --fps <n> <workers>  every frame of the film:
//                                               window.renderFrame(i / n) -> fNNNN.png
//        node capture.mjs [--playwright-core DIR] --probe   launch Chromium, print {browser_build}, exit
// Saves canvas#c at its own size after awaiting the render Promise; prints one JSON line
// {browser_build, size, frames, duration}. Exit 1 when the scene fails (a page error, DURATION missing or not a
// positive finite number, renderDrawing missing), 2 when playwright-core or its Chromium is missing (remedy printed).
// render.py serves the scene, calls this, and encodes.
// playwright-core is resolved from --playwright-core DIR (the package directory or a folder holding
// node_modules/playwright-core), then the working directory, then a playwright-cli install on PATH.
import { createRequire } from 'node:module';
import { existsSync, mkdirSync, realpathSync, writeFileSync } from 'node:fs';
import { delimiter, dirname, join } from 'node:path';

const REMEDY = 'pass --playwright-core <dir> (the animation plugin\'s playwright_core option), run `npm i playwright-core` '
  + 'in the working directory, or install @playwright/cli (the playwright plugin\'s setup installs it, when that plugin '
  + 'is installed); then `npx playwright install chromium`';

function onPath(name) {
  const exts = process.platform === 'win32' ? ['.cmd', '.exe', ''] : [''];
  for (const d of (process.env.PATH || '').split(delimiter).filter(Boolean))
    for (const e of exts) if (existsSync(join(d, name + e))) return join(d, name + e);
  throw new Error(`${name} not on PATH`);
}

function chromium(dir) {
  const tries = [
    ...(dir ? [() => createRequire(import.meta.url)(dir), () => createRequire(join(dir, 'x.js'))('playwright-core')] : []),
    () => createRequire(join(process.cwd(), 'x.js'))('playwright-core'),
    () => createRequire(join(process.cwd(), 'x.js'))('playwright'),
    () => createRequire(realpathSync(join(dirname(onPath('playwright-cli')), '..', '@playwright', 'cli', 'package.json')))('playwright-core'),
  ];
  for (const t of tries) { try { const m = t(); if (m?.chromium) return m.chromium; } catch { /* next */ } }
  console.error(`capture.mjs: playwright-core not found; ${REMEDY}.`);
  process.exit(2);
}

const argv = process.argv.slice(2);
const at = argv.indexOf('--playwright-core');
const pwDir = at >= 0 ? argv.splice(at, 2)[1] : null;
const launch = async () => {
  try { return await chromium(pwDir).launch(); } catch (e) {
    console.error(`capture.mjs: Chromium did not launch (${e.message.split('\n')[0]}); ${REMEDY}.`);
    process.exit(2);
  }
};
if (argv[0] === '--probe') {
  const b = await launch();
  console.log(JSON.stringify({ browser_build: b.version() }));
  await b.close();
  process.exit(0);
}
const [url, out, sel, ...rest] = argv;
const fps = sel === '--fps' ? +rest.shift() : 0, workers = +rest[0];
if (!(workers >= 1)) { console.error('capture.mjs: <workers> is required (render.py passes it)'); process.exit(1); }
mkdirSync(out, { recursive: true });
const browser = await launch();
let failed = false;
const open = async () => {
  const p = await browser.newPage();
  p.on('pageerror', e => { console.error('pageerror:', e.message); failed = true; });
  await p.goto(url);
  await p.waitForFunction(() => typeof window.renderFrame === 'function', null, { timeout: 30000 });
  return p;
};
const pages = [await open()];
const duration = await pages[0].evaluate(() => window.DURATION);
const fail = msg => { console.error(`capture.mjs: ${msg}`); process.exit(1); };
if (fps && !(typeof duration === 'number' && Number.isFinite(duration) && duration > 0))
  fail(`window.DURATION is ${duration}; a scene must set it to a positive number of seconds`);
if (!fps && await pages[0].evaluate(() => typeof window.renderDrawing !== 'function'))
  fail('the scene defines no window.renderDrawing(k)');
const jobs = fps
  ? Array.from({ length: Math.round(duration * fps) }, (_, i) => ({ t: i / fps, name: `f${String(i).padStart(4, '0')}.png` }))
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
const size = await pages[0].evaluate(() => [document.getElementById('c').width, document.getElementById('c').height]);
console.log(JSON.stringify({ browser_build: browser.version(), size, frames: jobs.length, duration: duration ?? null }));
await browser.close();
process.exit(failed ? 1 : 0);
