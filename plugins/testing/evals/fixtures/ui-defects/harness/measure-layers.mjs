#!/usr/bin/env node
// usage: node measure-layers.mjs [--python PATH] [--playwright-core DIR] [--out FILE]
// Rebuilds the variants with build-variants.py, loads each over file:// at widths 375 and 1280 with every
// non-file: request aborted, and writes a defect-by-layer table (JSON) to --out (default results/measured.json).
// No model calls. Exit 1 when a request left file: or a page failed to load, 2 when a prerequisite is missing.
// playwright-core comes from --playwright-core DIR, else from the playwright-cli install on PATH, so the run
// reuses that install's Chromium; @axe-core/playwright comes from this directory's node_modules (README.md).
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { delimiter, dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { inflateSync } from 'node:zlib';

const HERE = dirname(fileURLToPath(import.meta.url));
const FIXTURE = dirname(HERE);
const WIDTHS = [375, 1280];
const HEIGHT = 800;
const SETTLE_MS = 1000;
// WCAG 2.x A and AA rules only, the scope the Playwright accessibility-testing guide scans with; best-practice
// rules such as `region` judge page structure, not a planted defect.
const AXE_TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'];
const LAYERS = ['axe', 'geometry', 'cls', 'pixel', 'console', 'dom', 'aria'];

const args = process.argv.slice(2);
const opt = (name, fallback) => {
  const at = args.indexOf(name);
  return at >= 0 ? args[at + 1] : fallback;
};
const python = opt('--python', 'python3');
const out = resolve(opt('--out', join(HERE, 'results', 'measured.json')));

function missing(what) {
  console.error(`measure-layers.mjs: ${what}; see README.md for the one-time install.`);
  process.exit(2);
}

function onPath(name) {
  const exts = process.platform === 'win32' ? ['.cmd', '.exe', ''] : [''];
  for (const d of (process.env.PATH || '').split(delimiter).filter(Boolean))
    for (const e of exts) if (existsSync(join(d, name + e))) return join(d, name + e);
  throw new Error(`${name} not on PATH`);
}

function playwrightCore() {
  const dir = opt('--playwright-core');
  const tries = [
    ...(dir ? [() => createRequire(join(resolve(dir), 'x.js'))] : []),
    ...[['..'], ['..', 'lib', 'node_modules'], ['node_modules']].map(
      (up) => () =>
        createRequire(realpathSync(join(dirname(onPath('playwright-cli')), ...up, '@playwright', 'cli', 'package.json'))),
    ),
  ];
  for (const t of tries) {
    try {
      const require = t();
      const m = require('playwright-core');
      if (m?.chromium) return { chromium: m.chromium, version: require('playwright-core/package.json').version };
    } catch {
      /* next */
    }
  }
  return missing('playwright-core not found (install @playwright/cli or pass --playwright-core DIR)');
}

function axeBuilder() {
  try {
    const require = createRequire(join(HERE, 'x.js'));
    return { AxeBuilder: require('@axe-core/playwright').default, version: require('axe-core/package.json').version };
  } catch {
    return missing('@axe-core/playwright not installed in harness/node_modules');
  }
}

// Minimal PNG reader for Chromium screenshots: 8-bit RGB or RGBA, not interlaced.
function decodePng(buf) {
  let pos = 8;
  let width = 0;
  let height = 0;
  let channels = 0;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString('latin1', pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      if (data[8] !== 8 || data[12] !== 0 || ![2, 6].includes(data[9])) throw new Error('unsupported PNG format');
      channels = data[9] === 6 ? 4 : 3;
    } else if (type === 'IDAT') idat.push(data);
    pos += 12 + len;
  }
  const raw = inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const px = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const row = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let x = 0; x < stride; x++) {
      const a = x >= channels ? px[y * stride + x - channels] : 0;
      const b = y > 0 ? px[(y - 1) * stride + x] : 0;
      const c = x >= channels && y > 0 ? px[(y - 1) * stride + x - channels] : 0;
      const p = a + b - c;
      const pa = Math.abs(p - a);
      const pb = Math.abs(p - b);
      const pc = Math.abs(p - c);
      const pred = [0, a, b, (a + b) >> 1, pa <= pb && pa <= pc ? a : pb <= pc ? b : c][filter];
      px[y * stride + x] = (row[x] + pred) & 0xff;
    }
  }
  return { width, height, channels, px };
}

function pixelDiff(a, b) {
  const A = decodePng(a);
  const B = decodePng(b);
  if (A.width !== B.width || A.height !== B.height)
    return { differing: Math.max(A.width * A.height, B.width * B.height), size: [B.width, B.height] };
  let differing = 0;
  for (let i = 0; i < A.width * A.height; i++)
    for (let ch = 0; ch < 3; ch++)
      if (A.px[i * A.channels + ch] !== B.px[i * B.channels + ch]) {
        differing++;
        break;
      }
  return { differing };
}

// Runs in the page. Generic checks over every visible element; none names a selector from the fixture.
function snapshotBoxes() {
  const els = [...document.body.querySelectorAll('*')];
  window.__boxes = els.map((el) => [el, el.getBoundingClientRect().toJSON()]);
}

function geometry(tolerance) {
  const visible = (el) => {
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none';
  };
  const name = (el) => `${el.tagName.toLowerCase()}${el.className ? `.${String(el.className).split(' ')[0]}` : ''}`;
  const all = [...document.body.querySelectorAll('*')].filter(visible);
  const texty = all.filter((el) => [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim()));
  const overlap = [];
  for (let i = 0; i < texty.length; i++)
    for (let j = i + 1; j < texty.length; j++) {
      const [a, b] = [texty[i], texty[j]];
      if (a.contains(b) || b.contains(a)) continue;
      const r = a.getBoundingClientRect();
      const q = b.getBoundingClientRect();
      const w = Math.min(r.right, q.right) - Math.max(r.left, q.left);
      const h = Math.min(r.bottom, q.bottom) - Math.max(r.top, q.top);
      if (w >= tolerance && h >= tolerance) overlap.push(`${name(a)}|${name(b)}`);
    }
  const clipped = all
    .filter((el) => {
      const s = getComputedStyle(el);
      return (
        (s.overflowX !== 'visible' && el.scrollWidth - el.clientWidth >= tolerance) ||
        (s.overflowY !== 'visible' && el.scrollHeight - el.clientHeight >= tolerance)
      );
    })
    .map(name);
  const viewport =
    document.documentElement.scrollWidth - window.innerWidth >= tolerance
      ? [`scrollWidth ${document.documentElement.scrollWidth} > innerWidth ${window.innerWidth}`]
      : [];
  // Same-tag siblings side by side in one row should share a top edge.
  const topEdge = [];
  for (const parent of new Set(all.map((el) => el.parentElement))) {
    const kids = [...parent.children].filter(visible);
    for (let i = 0; i < kids.length; i++)
      for (let j = i + 1; j < kids.length; j++) {
        const [a, b] = [kids[i].getBoundingClientRect(), kids[j].getBoundingClientRect()];
        const sameRow = Math.min(a.bottom, b.bottom) > Math.max(a.top, b.top) && (a.right <= b.left || b.right <= a.left);
        if (kids[i].tagName === kids[j].tagName && sameRow && Math.abs(a.top - b.top) >= tolerance)
          topEdge.push(`${name(kids[i])}|${name(kids[j])} ${Math.abs(a.top - b.top)}px`);
      }
  }
  const shift = window.__boxes
    .filter(([el]) => el.isConnected && visible(el))
    .filter(([el, r]) => {
      const now = el.getBoundingClientRect();
      return Math.abs(now.top - r.top) >= tolerance || Math.abs(now.left - r.left) >= tolerance;
    })
    .map(([el]) => name(el));
  const brokenImages = [...document.images].filter((img) => img.complete && img.naturalWidth === 0).map((img) => img.getAttribute('src'));
  return { geometry: { overlap, clipped, viewport, topEdge, shift: [...new Set(shift)] }, dom: brokenImages, cls: window.__cls };
}

async function measureWidth(browser, url, width, AxeBuilder) {
  const context = await browser.newContext({ viewport: { width, height: HEIGHT }, deviceScaleFactor: 1 });
  const stats = { aborted: [] };
  await context.route('**/*', (route) => {
    const u = route.request().url();
    if (u.startsWith('file:')) return route.continue();
    stats.aborted.push(u);
    return route.abort();
  });
  const page = await context.newPage();
  const console_ = [];
  page.on('console', (m) => m.type() === 'error' && console_.push(`console: ${m.text()}`));
  page.on('pageerror', (e) => console_.push(`pageerror: ${e.name}: ${e.message}`));
  page.on('requestfailed', (r) => console_.push(`requestfailed: ${r.url().split('/').pop()} ${r.failure()?.errorText}`));
  await page.addInitScript(() => {
    window.__cls = 0;
    new PerformanceObserver((list) => {
      for (const e of list.getEntries()) if (!e.hadRecentInput) window.__cls += e.value;
    }).observe({ type: 'layout-shift', buffered: true });
  });
  // install() alone lets time flow, so a 300 ms page timer can fire before the load snapshot; pausing first
  // means page timers run only inside runFor.
  await page.clock.install({ time: 0 });
  await page.clock.pauseAt(1000);
  await page.goto(url, { waitUntil: 'load' });
  await page.evaluate(snapshotBoxes);
  await page.clock.runFor(SETTLE_MS);
  await page.clock.resume();
  const screenshot = await page.screenshot({ fullPage: true, animations: 'disabled', caret: 'hide' });
  await page.waitForTimeout(250);
  const measured = await page.evaluate(geometry, 1);
  const aria = await page.locator('body').ariaSnapshot();
  const axe = await new AxeBuilder({ page }).withTags(AXE_TAGS).analyze();
  const button = page.locator('button').first();
  await button.click();
  await page.waitForTimeout(250);
  await context.close();
  return {
    ...measured,
    axe: axe.violations.map((v) => `${v.id} x${v.nodes.length}`),
    console: console_,
    aria,
    screenshot,
    aborted: stats.aborted,
  };
}

const build = spawnSync(python, [join(FIXTURE, 'build-variants.py')], { encoding: 'utf8' });
if (build.error) missing(`${python} did not run (${build.error.message})`);
if (build.status !== 0) {
  console.error(`measure-layers.mjs: build-variants.py failed:\n${build.stderr}`);
  process.exit(1);
}
const map = JSON.parse(readFileSync(join(FIXTURE, 'variant-map.json'), 'utf8'));
const variants = Object.entries(map)
  .map(([vid, v]) => ({ vid, id: v.id }))
  .sort((a, b) => a.id.localeCompare(b.id));
if (!variants.some((v) => v.id === 'C0')) {
  console.error('measure-layers.mjs: no C0 control in variant-map.json');
  process.exit(1);
}

const pw = playwrightCore();
const { AxeBuilder, version: axeVersion } = axeBuilder();
let browser;
try {
  // Without these, a frame redrawn after relayout varies by 1/255 at rounded-corner edges between runs.
  browser = await pw.chromium.launch({ args: ['--disable-partial-raster', '--disable-gpu-rasterization'] });
} catch (e) {
  missing(`Chromium did not launch (${e.message.split('\n')[0]}); run playwright-cli install-browser`);
}

const runs = {};
for (const { vid, id } of variants) {
  const url = pathToFileURL(join(FIXTURE, 'variants', vid, 'index.html')).href;
  runs[id] = {};
  for (const width of WIDTHS) runs[id][width] = await measureWidth(browser, url, width, AxeBuilder);
}
const browserVersion = browser.version();
await browser.close();

const aborted = Object.values(runs).flatMap((r) => WIDTHS.flatMap((w) => r[w].aborted));
const matrix = {};
const geometryChecks = {};
const details = {};
for (const { id } of variants) {
  const cells = Object.fromEntries(LAYERS.map((l) => [l, false]));
  const checks = new Set();
  const notes = {};
  for (const width of WIDTHS) {
    const m = runs[id][width];
    const base = runs.C0[width];
    for (const [check, hits] of Object.entries(m.geometry)) if (hits.length) checks.add(check);
    const found = {
      axe: m.axe,
      geometry: Object.entries(m.geometry).flatMap(([k, v]) => v.map((x) => `${k}: ${x}`)),
      cls: m.cls > 0 ? [`score ${m.cls.toFixed(4)}`] : [],
      pixel: (() => {
        const d = pixelDiff(base.screenshot, m.screenshot);
        return d.differing > 0 ? [`${d.differing} px differ from C0${d.size ? ` (size ${d.size.join('x')})` : ''}`] : [];
      })(),
      console: m.console,
      dom: m.dom.map((src) => `image not decoded: ${src}`),
      aria: m.aria === base.aria ? [] : ['snapshot differs from C0'],
    };
    for (const layer of LAYERS)
      if (found[layer].length) {
        cells[layer] = true;
        notes[`${layer}@${width}`] = found[layer];
      }
  }
  matrix[id] = cells;
  geometryChecks[id] = [...checks].sort();
  details[id] = notes;
}

const result = {
  versions: {
    'axe-core': axeVersion,
    'playwright-core': pw.version,
    chromium: browserVersion,
  },
  widths: WIDTHS,
  layers: LAYERS,
  aborted: aborted.length,
  matrix,
  geometry_checks: geometryChecks,
  details,
};

mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, `${JSON.stringify(result, null, 2)}\n`);
for (const [id, cells] of Object.entries(matrix))
  console.log(`${id}: ${LAYERS.filter((l) => cells[l]).join(', ') || '-'}`);
if (aborted.length) {
  console.error(`measure-layers.mjs: ${aborted.length} non-file request(s) aborted: ${aborted.join(' ')}`);
  process.exit(1);
}
