// Shared set-up for the browser suites (ui_formats.js, ui_presence.js): find Playwright, start a session with
// `share.sh ensure-running` on a spare port behind the fake cloudflared, apply ops, and open pages that record
// their errors, CSP violations and 429 answers. Not a test itself.
"use strict";
const { execFileSync, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const net = require("node:net");
const os = require("node:os");
const path = require("node:path");

const here = __dirname, shared = path.resolve(here, "..");

/** playwright-core from node_modules, else from the playwright-cli install (it bundles one). */
function loadPlaywright() {
  for (const name of ["playwright-core", "playwright"]) { try { return require(name); } catch { /* next */ } }
  const cli = spawnSync("bash", ["-c", "command -v playwright-cli"], { encoding: "utf8" }).stdout.trim();
  if (!cli) return null;
  let dir = path.dirname(fs.realpathSync(cli));
  for (let i = 0; i < 6 && dir !== path.dirname(dir); i++, dir = path.dirname(dir)) {
    const nm = path.join(dir, "node_modules");
    const tries = [path.join(nm, "playwright-core")];
    for (const sub of [".mise", ".pnpm"]) {
      try { for (const e of fs.readdirSync(path.join(nm, sub))) if (/^playwright-core@/.test(e)) tries.push(path.join(nm, sub, e, "node_modules", "playwright-core")); } catch { /* none */ }
    }
    for (const t of tries) { try { return require(t); } catch { /* next */ } }
  }
  return null;
}

const freePort = () => new Promise((res, rej) => { const s = net.createServer(); s.unref(); s.on("error", rej); s.listen(0, "127.0.0.1", () => { const { port } = s.address(); s.close(() => res(port)); }); });
const fake = path.join(here, "fixtures", process.platform === "win32" ? "fake_cloudflared.py" : "fake-cloudflared.sh");

/** A suite's run: a temp folder, sessions it starts (stopped at the end), and PASS/FAIL lines. */
function suite(name) {
  const env = { ...process.env, SHARED_CLOUDFLARED: process.env.SHARED_CLOUDFLARED || fake, WATCH_ID: name };
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), `shared-${name}-`));
  const dirs = [], results = [];
  const share = (dir, ...args) => {
    const out = execFileSync("bash", [path.join(shared, "share.sh"), "--dir", dir, ...args], { env, encoding: "utf8", timeout: 90000 });
    return JSON.parse(out.trim().split("\n").filter(l => l.startsWith("{")).pop());
  };
  const apply = (dir, ops) => { const f = path.join(dir, "ops.json"); fs.writeFileSync(f, JSON.stringify({ ops })); return share(dir, "apply", "--file", f); };
  /** A fresh session on a spare port: {dir, localUrl, ownerUrl}. */
  async function start(slug) {
    const dir = path.join(tmp, "topic", "shared", slug); dirs.push(dir);
    const up = share(dir, "ensure-running", "--guest-port", String(await freePort()));
    return { dir, localUrl: up.localUrl, ownerUrl: fs.readFileSync(up.ownerLinkFile, "utf8").trim() };
  }
  /** Save bytes in the session's staging folder and add them as an asset; returns its id. */
  function asset(dir, file, bytes) {
    const p = path.join(dir, "staging", file);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, bytes);
    return apply(dir, [{ op: "add-asset", path: p }]).results[0].id;
  }
  const ok = (what, pass, detail) => results.push(`${pass ? "PASS" : "FAIL"} ${what}${detail !== undefined && !pass ? `  [${detail}]` : ""}`);
  function finish() {
    for (const d of dirs) { try { share(d, "stop"); } catch { /* not running */ } }
    fs.rmSync(tmp, { recursive: true, force: true });
    for (const line of results) console.log(line);
    const failed = results.filter(l => !l.startsWith("PASS")).length;
    console.log(`${name}: ${results.length - failed} passed, ${failed} failed`);
    return failed ? 1 : 0;
  }
  return { share, apply, start, asset, ok, results, finish };
}

/** Pages that record page errors, console errors, CSP violations and every 429 answer they get. */
function recorder(browser) {
  const errors = [], csp = [], too = [];
  const pages = [];
  async function open(url, { context = {}, init } = {}) {
    const ctx = await browser.newContext({ viewport: { width: 1400, height: 900 }, ...context });
    await ctx.addInitScript(() => document.addEventListener("securitypolicyviolation", e => { (window.__csp ||= []).push(`${e.violatedDirective} ${e.blockedURI}`); }));
    if (init) await ctx.addInitScript(init.fn, init.arg);
    const page = await ctx.newPage();
    page.on("pageerror", e => errors.push(String(e)));
    page.on("console", m => { if (m.type() === "error") errors.push(m.text()); });
    page.on("response", r => { if (r.status() === 429) too.push(`${r.request().method()} ${new URL(r.url()).pathname}`); });
    await page.goto(url);
    pages.push(page);
    return page;
  }
  async function cspViolations() {
    const out = [...csp];
    for (const p of pages) if (!p.isClosed()) out.push(...(await p.evaluate(() => window.__csp || []).catch(() => [])));
    return out;
  }
  return { open, errors, too, cspViolations };
}

const until = (page, fn, arg, timeout = 8000) => page.waitForFunction(fn, arg, { timeout }).then(() => true).catch(() => false);
const snap = page => page.evaluate(() => window.Core.snapshot());

/** Join a fresh guest page with a name; resolves to its pid. */
async function joinAs(page, name) {
  await page.waitForSelector("dialog.core-name[open]");
  await page.fill("#core-n", name);
  await page.click("dialog.core-name button");
  await until(page, () => !document.querySelector("dialog.core-name") && !!window.Core.snapshot()?.me);
  return (await snap(page)).me.pid;
}

module.exports = { loadPlaywright, suite, recorder, until, snap, joinAs };
