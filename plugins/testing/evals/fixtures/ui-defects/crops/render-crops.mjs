#!/usr/bin/env node
// Renders the vision cases' screenshots: for each variant, widths 375 and 1280, once at load and once 1 s
// later on Playwright's fake clock, full page, into crops/<variant-id>/<width>-{load,after-1s}.png.
// usage: render-crops.mjs [--playwright-core DIR] [variant-id...]
// With no ids it re-renders every variant directory already under crops/. Build the variants first
// (build-variants.py). playwright-core comes from --playwright-core DIR, else from the playwright-cli
// install on PATH, so the render reuses that install's Chromium. Only file: requests load.
import { existsSync, mkdirSync, readdirSync, realpathSync } from 'node:fs';
import { createRequire } from 'node:module';
import { delimiter, dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const FIXTURE = dirname(HERE);

const args = process.argv.slice(2);
const at = args.indexOf('--playwright-core');
const coreDir = at >= 0 ? args.splice(at, 2)[1] : null;
const ids = args.length
  ? args
  : readdirSync(HERE, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name);

function playwrightCore() {
  const roots = [];
  if (coreDir) roots.push(join(resolve(coreDir), 'x.js'));
  for (const d of (process.env.PATH || '').split(delimiter).filter(Boolean))
    for (const e of process.platform === 'win32' ? ['.cmd', '.exe', ''] : [''])
      if (existsSync(join(d, `playwright-cli${e}`)))
        for (const up of [['..'], ['..', 'lib', 'node_modules'], ['node_modules']])
          roots.push(join(dirname(join(d, `playwright-cli${e}`)), ...up, '@playwright', 'cli', 'package.json'));
  for (const r of roots) {
    try {
      const m = createRequire(realpathSync(r))('playwright-core');
      if (m?.chromium) return m;
    } catch {
      /* next */
    }
  }
  console.error('render-crops.mjs: playwright-core not found (install @playwright/cli or pass --playwright-core DIR)');
  process.exit(2);
}

const { chromium } = playwrightCore();
// Without these, a frame redrawn after relayout varies by 1/255 at rounded-corner edges between runs.
const browser = await chromium.launch({ args: ['--disable-partial-raster', '--disable-gpu-rasterization'] });
for (const id of ids) {
  const url = pathToFileURL(join(FIXTURE, 'variants', id, 'index.html')).href;
  mkdirSync(join(HERE, id), { recursive: true });
  for (const width of [375, 1280]) {
    const context = await browser.newContext({ viewport: { width, height: 800 }, deviceScaleFactor: 1 });
    await context.route('**/*', (r) => (r.request().url().startsWith('file:') ? r.continue() : r.abort()));
    const page = await context.newPage();
    // install() alone lets time flow, so a 300 ms page timer can fire before the load frame; pausing first
    // means page timers run only inside runFor.
    await page.clock.install({ time: 0 });
    await page.clock.pauseAt(1000);
    await page.goto(url, { waitUntil: 'load' });
    const shot = async (name) => {
      const height = await page.evaluate(() => document.documentElement.scrollHeight);
      await page.screenshot({
        path: join(HERE, id, name),
        fullPage: true,
        clip: { x: 0, y: 0, width, height },
        animations: 'disabled',
        caret: 'hide',
      });
    };
    await shot(`${width}-load.png`);
    await page.clock.runFor(1000);
    await shot(`${width}-after-1s.png`);
    await context.close();
  }
}
await browser.close();
