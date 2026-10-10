// Stage 1 of the demo-video pipeline: replay a written flow once and write CAPTURE/timeline.json,
// every page frame (lossless PNG at device pixels, with its time) plus an event log of each step's
// actions, target boxes and times. No cursor is drawn in the browser; produce.py draws it.
//
// usage: node record.mjs [--playwright-core DIR] [--headed] REPLAY.mjs CAPTURE_DIR
//   REPLAY.mjs default-exports `async (demo) => { ... }`; see reference/replay-script.md for the API.
// exit: 0 recorded, 1 the replay failed (nothing written; an earlier capture is kept), 2 playwright-core or
// its Chromium is missing (remedy printed).
//
// Capture: Chromium's screencast delivers frames at CSS-pixel size whatever the deviceScaleFactor, so
// frames come from CDP Page.captureScreenshot with clip.scale = DSF (3840x2160 at DSF 2). That is slow
// (3.6-4.0 fps measured), so cursor travel and typing run in slow motion (SLOW) and build_edl.py retimes them.
import { createRequire } from 'node:module';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const REMEDY = 'pass --playwright-core <dir>, run `npm i playwright-core` in the working directory, or install '
  + '@playwright/cli (/playwright:setup); then `npx playwright install chromium`';

function onPath(name) {
  const exts = process.platform === 'win32' ? ['.cmd', '.exe', ''] : [''];
  for (const d of (process.env.PATH || '').split(path.delimiter).filter(Boolean))
    for (const e of exts) if (fs.existsSync(path.join(d, name + e))) return path.join(d, name + e);
  throw new Error(`${name} not on PATH`);
}

// playwright-core from --playwright-core DIR, the working directory, then the playwright-cli install on
// PATH (its own copy, so the browser build matches the one `playwright-cli install` provisioned).
function chromium(dir) {
  if (dir) dir = path.resolve(dir);
  const tries = [
    ...(dir ? [() => createRequire(import.meta.url)(dir), () => createRequire(path.join(dir, 'x.js'))('playwright-core')] : []),
    () => createRequire(path.join(process.cwd(), 'x.js'))('playwright-core'),
    ...[['..'], ['..', 'lib', 'node_modules'], ['node_modules']].map((up) => () =>
      createRequire(fs.realpathSync(path.join(path.dirname(onPath('playwright-cli')), ...up, '@playwright', 'cli', 'package.json')))('playwright-core')),
  ];
  for (const t of tries) { try { const m = t(); if (m?.chromium) return m.chromium; } catch { /* next */ } }
  console.error(`record.mjs: playwright-core not found; ${REMEDY}.`);
  process.exit(2);
}

const argv = process.argv.slice(2);
const take = (flag, n = 1) => { const i = argv.indexOf(flag); return i < 0 ? null : argv.splice(i, n + 1).slice(1); };
const pwDir = take('--playwright-core')?.[0];
const headed = take('--headed', 0) !== null;
const [replayPath, outArg] = argv;
if (!replayPath || !outArg) { console.error('usage: node record.mjs [--playwright-core DIR] [--headed] REPLAY.mjs CAPTURE_DIR'); process.exit(1); }

const W = Number(process.env.DEMO_WIDTH || 1920), H = Number(process.env.DEMO_HEIGHT || 1080);
const DSF = Number(process.env.DEMO_DSF || 2);
const SLOW = Number(process.env.DEMO_SLOW || 3);
const out = path.resolve(outArg);
const existing = fs.existsSync(out) ? fs.readdirSync(out) : [];
const isDir = (p) => fs.statSync(p, { throwIfNoEntry: false })?.isDirectory() ?? false;
const isFile = (p) => fs.statSync(p, { throwIfNoEntry: false })?.isFile() ?? false;
const earlierCapture = existing.length === 2 && isDir(path.join(out, 'frames')) && isFile(path.join(out, 'timeline.json'));
if (existing.length && !earlierCapture) {
  console.error(`record.mjs: ${out} is not empty and is not an earlier capture (exactly timeline.json and frames/); pass a new or empty CAPTURE_DIR.`);
  process.exit(1);
}
const launcher = chromium(pwDir);
// Record into a sibling staging directory: the earlier capture is replaced only once this one succeeds.
fs.mkdirSync(path.dirname(out), { recursive: true });
const stage = fs.mkdtempSync(path.join(path.dirname(out), `.${path.basename(out)}.recording-`));
let committed = false;
process.on('exit', () => { if (!committed) fs.rmSync(stage, { recursive: true, force: true }); });
fs.mkdirSync(path.join(stage, 'frames'));

let browser;
try { browser = await launcher.launch({ headless: !headed }); } catch (e) {
  console.error(`record.mjs: Chromium did not launch (${e.message.split('\n')[0]}); ${REMEDY}.`);
  process.exit(2);
}
const context = await browser.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: DSF });
// backdrop-filter (a DocSearch-style modal blur) drops software-rendered capture to ~3 fps; the text
// caret's blink keeps a settled page from ever going still. Both go.
await context.addInitScript(() => {
  document.addEventListener('DOMContentLoaded', () => {
    const s = document.createElement('style');
    s.textContent = '*{backdrop-filter:none!important;-webkit-backdrop-filter:none!important;caret-color:transparent!important}';
    document.head.appendChild(s);
  });
});
const page = await context.newPage();

const frames = [];
const events = [];
const now = () => Date.now() / 1000;
const mark = (name, extra = {}) => events.push({ name, t: now(), ...extra });
let n = 0;
let capturing = false;
let grabber = null;

// page.screenshot at scale 'device' renders at device pixels and, unlike a CDP session held across the
// run, keeps working when a navigation swaps the renderer process (file:// pages, cross-site links).
function startCapture() {
  capturing = true;
  grabber = (async () => {
    while (capturing) {
      const t0 = now();
      let buf;
      try {
        buf = await page.screenshot({ type: 'png', scale: 'device', animations: 'allow', caret: 'initial', timeout: 3000 });
      } catch {
        await new Promise((res) => setTimeout(res, 10));
        continue;
      }
      const file = `frames/${String(n++).padStart(5, '0')}.png`;
      fs.writeFileSync(path.join(stage, file), buf);
      frames.push({ file, t: (t0 + now()) / 2, t0, digest: crypto.createHash('md5').update(buf).digest('hex') });
    }
  })();
}

const boxOf = async (target) => {
  if (Array.isArray(target)) return target;
  const loc = typeof target === 'string' ? page.locator(target).first() : target;
  const b = await loc.boundingBox();
  if (!b) throw new Error('target has no bounding box (not visible)');
  return [b.x, b.y, b.width, b.height];
};
const centerOf = (b) => ({ x: b[0] + b[2] / 2, y: b[1] + b[3] / 2 });
const union = (a, b) => {
  const x0 = Math.min(a[0], b[0]), y0 = Math.min(a[1], b[1]);
  return [x0, y0, Math.max(a[0] + a[2], b[0] + b[2]) - x0, Math.max(a[1] + a[3], b[1] + b[3]) - y0];
};
const ease = (u) => (u < 0.5 ? 4 * u * u * u : 1 - (-2 * u + 2) ** 3 / 2);
let mouse = { x: W * 0.62, y: H * 0.55 };

// A step is settled when the pixels stop changing (networkidle fires before late paint).
const STILL = 4;
async function settle(step, extra = {}) {
  await page.waitForLoadState('networkidle').catch(() => {});
  const tStart = now();
  for (;;) {
    const tail = frames.filter((f) => f.t0 >= tStart).slice(-STILL);
    if (tail.length === STILL && tail.every((f) => f.digest === tail[0].digest)) {
      let j = frames.lastIndexOf(tail[0]);
      while (j > 0 && frames[j - 1].digest === tail[0].digest && frames[j - 1].t0 >= tStart) j--;
      // the frame's own time: build_edl.py looks captures up by it, so it must select this frame
      events.push({ name: 'settled', step, t: frames[j].t, url: page.url(), ...extra });
      return;
    }
    if (now() - tStart > 20) throw new Error(`step ${step}: page never went still`);
    await page.waitForTimeout(50);
  }
}

const demo = {
  page, width: W, height: H, union, boxOf,
  async goto(url, opts = {}) {
    await page.goto(url, { waitUntil: 'networkidle', ...opts });
    await page.mouse.move(mouse.x, mouse.y);
    if (!capturing) {
      startCapture();
      await page.waitForTimeout(600);
      mark('start');
      await page.waitForTimeout(1200);
    }
  },
  // Move the real mouse along an eased path (hover states render); log it for the drawn cursor.
  async moveTo(step, target, ms = 700 * SLOW) {
    const p = Array.isArray(target) || typeof target !== 'object' || target.x === undefined ? centerOf(await boxOf(target)) : target;
    const from = { ...mouse }, t0 = now(), steps = Math.max(1, Math.round(ms / 25));
    for (let i = 1; i <= steps; i++) {
      const e = ease(i / steps);
      await page.mouse.move(from.x + (p.x - from.x) * e, from.y + (p.y - from.y) * e);
      await page.waitForTimeout(25);
    }
    events.push({ name: 'move', step, t: t0, t1: now(), from, to: p });
    mouse = { ...p };
  },
  // Click a target. `block` is the semantic block the shot frames (defaults to the target plus padding);
  // a click that changes the URL is a navigation: the settled event records it and the camera cuts at 1.0x.
  async click(step, target, { block = null } = {}) {
    const box = await boxOf(target);
    const blk = block ? await boxOf(block) : null;
    const url = page.url();
    await demo.moveTo(step, centerOf(box));
    await page.waitForTimeout(250);
    mark('click', { step, ...centerOf(box), box, block: blk, url });
    await page.mouse.down();
    await page.waitForTimeout(60);
    await page.mouse.up();
  },
  // Type into a focused field one key at a time; `modal` is the panel the shot frames while typing.
  async type(step, target, text, { modal = null } = {}) {
    const box = await boxOf(target);
    mark('type', { step, box, modal: modal ? await boxOf(modal) : null, text });
    for (const ch of text) {
      await page.keyboard.type(ch);
      mark('key', { step, ch });
      const tk = now();
      while (frames.filter((f) => f.t0 > tk).length < 2) await page.waitForTimeout(15);
    }
    mark('typed', { step });
  },
  // Wait until the page is still; extra fields (box, modal) are logged with the settled event.
  async settle(step, extra = {}) {
    const resolved = {};
    for (const [k, v] of Object.entries(extra)) resolved[k] = v && (typeof v === 'string' || Array.isArray(v) || v.boundingBox) ? await boxOf(v) : v;
    await settle(step, resolved);
  },
  // Inject CSS for the rest of the recording (hide a flashing partial state); returns a remover.
  async style(css) {
    const h = await page.addStyleTag({ content: css });
    return async () => h.evaluate((el) => el.remove());
  },
  mark: (name, extra) => mark(name, extra),
  wait: (ms) => page.waitForTimeout(ms),
};

let failed = null;
try {
  const replay = (await import(pathToFileURL(path.resolve(replayPath)).href)).default;
  if (typeof replay !== 'function') throw new Error(`${replayPath} must default-export an async function (demo) => {}`);
  await replay(demo);
  await page.waitForTimeout(1500);
  mark('end');
} catch (e) {
  failed = e;
}
capturing = false;
if (grabber) await grabber;
await browser.close();
if (failed) {
  console.error(`record.mjs: replay failed, no capture written (${out} ${earlierCapture ? 'keeps the earlier capture' : 'was not created'}): ${failed.message}`);
  process.exit(1);
}
if (!frames.length) { console.error('record.mjs: no frames captured (did the replay call demo.goto?)'); process.exit(1); }
fs.writeFileSync(path.join(stage, 'timeline.json'), JSON.stringify({ width: W, height: H, dsf: DSF, frames, events }, null, 1));
fs.rmSync(out, { recursive: true, force: true });
fs.renameSync(stage, out);
committed = true;
const span = frames.at(-1).t - frames[0].t;
console.log(`frames=${frames.length} (${(frames.length / Math.max(span, 1e-9)).toFixed(1)} fps) events=${events.length} span=${span.toFixed(2)}s -> ${out}`);
