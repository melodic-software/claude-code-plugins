import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = fileURLToPath(new URL(".", import.meta.url));
const require = createRequire(import.meta.url);
const ci = process.env.CI === "true";
const skip = (why) => {
  if (ci) {
    console.log(`FAIL: ${why}`);
    process.exit(1);
  }
  console.log(`SKIP: ${why}`);
  process.exit(0);
};

let playwright = null;
for (const name of ["playwright-core", "playwright"]) {
  try {
    playwright = require(name);
    break;
  } catch {
    playwright = null;
  }
}
if (!playwright) skip("playwright-core is not installed (npm ci)");

const work = mkdtempSync(join(tmpdir(), "deepening-browser-"));
const built = spawnSync(process.execPath, [join(here, "build-view.mjs"), "deepening", "--record", join(here, "testdata", "deepening-candidates.json")], {
  encoding: "utf8",
  env: { ...process.env, TMPDIR: work, TEMP: work, TMP: work },
});
if (built.status !== 0) {
  console.log(`FAIL: the fixture did not build: ${built.stderr}`);
  process.exit(1);
}
const url = pathToFileURL(built.stdout.trim()).href;
const page0 = readFileSync(built.stdout.trim(), "utf8");
const ORDER = [...Array(8)].map((_, i) => `c-s${i + 1}`).concat([...Array(10)].map((_, i) => `c-w${i + 1}`), [...Array(5)].map((_, i) => `c-p${i + 1}`));

let browser;
try {
  browser = await playwright.chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME } : {});
} catch (err) {
  rmSync(work, { recursive: true, force: true });
  skip(`no Chromium to launch: ${String(err.message).split("\n")[0]}`);
}

let failed = 0;
const check = (name, pass, detail) => {
  console.log(`${pass ? "PASS" : "FAIL"}: ${name}${pass || detail === undefined ? "" : `  [${JSON.stringify(detail)}]`}`);
  if (!pass) failed += 1;
};

try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const state = () => page.evaluate(() => ({
    shown: [...document.querySelectorAll("article.card, #kept")].filter((pane) => !pane.hasAttribute("hidden")).map((pane) => pane.id),
    pos: document.querySelector(".reader-pos").textContent,
    prev: document.querySelector('[data-step="-1"]').disabled,
    next: document.querySelector('[data-step="1"]').disabled,
    top: !document.getElementById("top-recommendation").hidden,
    open: document.getElementById("zoom").open,
    focus: document.activeElement && document.activeElement.className,
    mermaid: Boolean(window.mermaid),
  }));
  const svgs = (id) => page.evaluate((card) => [...document.querySelectorAll(`#${card} pre.mermaid`)].map((pre) => pre.querySelector("svg") !== null), id);

  check("the page lists the candidates in the fixture's badge order", [...page0.matchAll(/<article class="card" id="([a-z0-9-]+)"/g)].map((m) => m[1]).join() === ORDER.join());

  await page.goto(url);
  await page.waitForLoadState("load");
  let s = await state();
  check("the page opens on the top candidate alone, with its reason, at 1 of 23", s.shown.join() === "c-s1" && s.top && s.pos === "1 of 23" && s.prev && !s.next, s);
  if (s.mermaid) {
    await page.waitForFunction(() => document.querySelectorAll("#c-s1 pre.mermaid svg").length === document.querySelectorAll("#c-s1 pre.mermaid").length, null, { timeout: 15000 }).catch(() => {});
    check("the top card's diagrams are drawn", (await svgs("c-s1")).every(Boolean), await svgs("c-s1"));
  } else {
    console.log("SKIP: the Mermaid CDN script did not load, so the drawn-diagram check did not run");
  }

  await page.click('[data-step="1"] >> nth=0');
  s = await state();
  check("Next shows the second candidate alone and hides the reason", s.shown.join() === "c-s2" && s.pos === "2 of 23" && !s.top && !s.prev, s);
  await page.click('[data-step="1"] >> nth=0');
  await page.click('[data-step="-1"] >> nth=0');
  s = await state();
  check("Next then Previous lands on the second candidate alone", s.shown.join() === "c-s2" && s.pos === "2 of 23", s);

  await page.click('.reader-item[href="#c-p5"]');
  s = await state();
  check("a sidebar link shows its card alone, and Next stops at the last candidate", s.shown.join() === "c-p5" && s.pos === "23 of 23" && s.next && !s.prev, s);
  await page.click(".reader-kept");
  s = await state();
  check("the sidebar's Looked at, no change link shows that section alone", s.shown.join() === "kept" && !s.prev, s);
  await page.click('[data-step="-1"] >> nth=0');
  s = await state();
  check("Previous from that section returns to the last candidate", s.shown.join() === "c-p5", s);

  await page.click('.reader-item[href="#c-s1"]');
  await page.click("#c-s1 figure[data-enlarge] .v >> nth=0");
  s = await state();
  const cloned = await page.evaluate(() => document.querySelector("#zoom .zoom-body > .v") !== null);
  check("clicking a diagram opens it enlarged in the dialog", s.open && cloned, s);
  await page.keyboard.press("Escape");
  await page.waitForFunction(() => document.activeElement && document.activeElement.className === "zoom-open", null, { timeout: 5000 }).catch(() => {});
  s = await state();
  check("Esc closes the dialog and returns focus to the Enlarge button", !s.open && s.focus === "zoom-open", s);
  await page.click("#c-s1 .zoom-open >> nth=1");
  await page.click("[data-zoom-close]");
  s = await state();
  check("the Close button closes the dialog", !s.open, s);
  await page.click("#c-s1 .zoom-open >> nth=0");
  await page.mouse.click(4, 4);
  s = await state();
  check("a click outside the dialog closes it", !s.open, s);

  for (const hash of ["#index", "#top-recommendation", "#zoom", "#no-such-id"]) {
    await page.goto(`${url}?fresh=${hash.slice(1)}${hash}`);
    await page.waitForLoadState("load");
    s = await state();
    check(`an address of ${hash}, which names no card, opens on the top candidate`, s.shown.join() === "c-s1" && s.pos === "1 of 23" && s.prev, s);
    if (s.mermaid) {
      await page.waitForFunction(() => document.querySelectorAll("#c-s1 pre.mermaid svg").length > 0, null, { timeout: 15000 }).catch(() => {});
      check(`an address of ${hash} still draws the top card's diagrams`, (await svgs("c-s1")).every(Boolean), await svgs("c-s1"));
    }
  }
  await page.goto(`${url}?fresh=w5#c-w5`);
  await page.waitForLoadState("load");
  s = await state();
  check("an address naming a card opens on that card alone", s.shown.join() === "c-w5" && s.pos === "13 of 23", s);
} finally {
  await browser.close();
  rmSync(work, { recursive: true, force: true });
}
process.exit(failed ? 1 : 0);
