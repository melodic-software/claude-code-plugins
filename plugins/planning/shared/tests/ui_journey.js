#!/usr/bin/env node
// The page end to end in a real browser, against `share.sh ensure-running` on spare ports with the fake
// cloudflared: two browsers (the owner and a guest) join, answer, vote, lock, pick, react and send a round;
// every state poll carries a query string; the page runs under the server's CSP with no violation; and a
// guest of an imported prototype session, with the secret the prototype stored, comes back as the same pid.
//   node plugins/planning/shared/tests/ui_journey.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the Design's Contracts (routes, snapshot, auth) and the fixtures, never from the page.
"use strict";
const { execFileSync, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const net = require("node:net");
const os = require("node:os");
const path = require("node:path");

const here = __dirname, shared = path.resolve(here, "..");
const results = [];
const ok = (name, pass, detail) => results.push(`${pass ? "PASS" : "FAIL"} ${name}${detail !== undefined && !pass ? `  [${detail}]` : ""}`);

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
const env = { ...process.env, SHARED_CLOUDFLARED: process.env.SHARED_CLOUDFLARED || fake, WATCH_ID: "ui-journey" };
const share = (dir, ...args) => {
  const out = execFileSync("bash", [path.join(shared, "share.sh"), "--dir", dir, ...args], { env, encoding: "utf8", timeout: 90000 });
  return JSON.parse(out.trim().split("\n").filter(l => l.startsWith("{")).pop());
};
const apply = (dir, ops) => { fs.writeFileSync(path.join(dir, "ops.json"), JSON.stringify({ ops })); return share(dir, "apply", "--file", path.join(dir, "ops.json")); };

const textQ = (id, text, extra = {}) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" }, ...extra });

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_journey.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "shared-ui-journey-"));
  const dirs = [];
  const errors = [], csp = [], stateUrls = [], tooFast = [];
  /** A page that records its errors, its CSP violations and every /api/state request it makes. */
  async function openPage(url, init) {
    const ctx = await browser.newContext({ viewport: { width: 1400, height: 900 } });
    await ctx.addInitScript(() => document.addEventListener("securitypolicyviolation", e => { (window.__csp ||= []).push(`${e.violatedDirective} ${e.blockedURI}`); }));
    if (init) await ctx.addInitScript(init.fn, init.arg);
    const page = await ctx.newPage();
    page.on("pageerror", e => errors.push(String(e)));
    page.on("console", m => { if (m.type() === "error" && !/Failed to load resource/.test(m.text())) errors.push(m.text()); });
    page.on("request", r => { const u = new URL(r.url()); if (u.pathname === "/api/state") stateUrls.push(u.search); });
    page.on("response", r => { if (r.status() === 429) tooFast.push(new URL(r.url()).pathname); });
    await page.goto(url);
    return page;
  }
  const snap = page => page.evaluate(() => window.Core.snapshot());
  const until = (page, fn, arg, timeout = 8000) => page.waitForFunction(fn, arg, { timeout }).then(() => true).catch(() => false);
  const railQ = (page, qid) => page.locator(".vf-q", { hasText: qid === "Q1" ? "Where should" : qid === "Q2" ? "Which default" : "What worries" }).first();

  try {
    // ---------- session A: a fresh session ----------
    const dA = path.join(tmp, "topic", "shared", "po"); dirs.push(dA);
    const up = share(dA, "ensure-running", "--guest-port", String(await freePort()));
    ok("ensure-running answers a local URL", /^http:\/\/127\.0\.0\.1:\d+\/$/.test(up.localUrl), up.localUrl);
    const ownerUrl = fs.readFileSync(up.ownerLinkFile, "utf8").trim();
    apply(dA, [{ op: "set-title", title: "Checkout" }, { op: "open-round", questions: [
      textQ("Q1", "Where should the order summary sit?", { recommendation: "In a right-hand column.", alternatives: [{ key: "a", text: "Below the form." }, { key: "b", text: "In a header bar." }] }),
      textQ("Q2", "Which default payment method?", { format: { kind: "choice", options: [{ id: "opt-1", label: "Card" }, { id: "opt-2", label: "Saved method" }] } }),
      textQ("Q3", "What worries you about the new checkout?", { purpose: "gather" }),
    ] }]);

    const owner = await openPage(ownerUrl);
    ok("the owner's page lists the round's three questions", await until(owner, () => document.querySelectorAll(".vf-q").length === 3));
    ok("the owner is not asked to join", !(await owner.$("dialog.core-name[open]")));
    ok("the title shows", (await owner.textContent(".vf-title")) === "Checkout", await owner.textContent(".vf-title"));

    const guest = await openPage(up.localUrl);
    ok("a new guest gets the join dialog", await until(guest, () => !!document.querySelector("dialog.core-name[open]")));
    await guest.fill("#core-n", "Gus");
    await guest.click("dialog.core-name button");
    ok("the guest joins and sees the questions", await until(guest, () => !document.querySelector("dialog.core-name") && document.querySelectorAll(".vf-q").length === 3));
    const gusPid = (await snap(guest))?.me?.pid;
    ok("the guest's pid is stored under the prototype's key with its secret", await guest.evaluate(p => localStorage.getItem("pid") === p && (localStorage.getItem("secret") || "").length >= 32, gusPid));

    // answer
    await railQ(guest, "Q1").click();
    await guest.fill("#vf-answer", "Pin it on the right, sticky.");
    await guest.press("#vf-answer", "Control+Enter");
    ok("the guest's answer reaches the server as a person card", await until(owner, p => (window.Core.snapshot()?.cards?.Q1 || []).some(c => c.pid === p && c.text === "Pin it on the right, sticky."), gusPid));
    const details = (await snap(owner)).cardDetails?.Q1?.[`p:${gusPid}`];
    ok("the answer carries its view and device (Q99)", details?.view === "focus" && details?.deviceInfo?.kind === "computer" && Number.isInteger(details?.deviceInfo?.screen?.w), JSON.stringify(details));

    await railQ(owner, "Q1").click();
    await owner.fill("#vf-answer", "Below the total, collapsed.");
    await owner.press("#vf-answer", "Control+Enter");
    ok("the owner's answer shows on the guest's page", await until(guest, () => [...document.querySelectorAll(".vf-alist .vf-card")].some(c => /Below the total/.test(c.textContent))));

    // vote
    const ownerCard = guest.locator(".vf-alist .vf-card", { hasText: "Below the total" });
    await ownerCard.locator(".vf-vote").click();
    ok("the guest's vote lands on the owner's card", await until(owner, p => window.Core.snapshot()?.me && (window.Core.snapshot().cards.Q1.find(c => c.ref === "p:host")?.votes || []).includes(p), gusPid));
    ok("the vote button shows it is pressed", await until(guest, () => document.querySelector(".vf-alist .vf-card:not(.vf-mine):not(.vf-bot) .vf-vote")?.getAttribute("aria-pressed") === "true"));

    // lock
    ok("the owner sees Lock top answer", await until(owner, () => { const b = document.querySelector(".vf-anshead .vf-btn-brass"); return !!b && !b.hidden && b.getAttribute("aria-disabled") === "false"; }));
    await owner.click(".vf-anshead .vf-btn-brass");
    ok("Lock top answer locks the most voted card", await until(owner, () => window.Core.snapshot()?.locks?.Q1?.source?.card === "p:host"));
    ok("the guest's page shows the lock", await until(guest, () => !document.querySelector(".vf-lock").hidden && /Below the total/.test(document.querySelector(".vf-lock").textContent)));

    // pick on a choice question
    await railQ(guest, "Q2").click();
    await guest.locator(".vf-opt", { hasText: "Card" }).locator(".vf-optchoose").click();
    ok("a pick is the guest's vote on the option", await until(owner, p => window.Core.snapshot()?.me && (window.Core.snapshot().cards.Q2.find(c => c.ref === "o:opt-1")?.votes || []).includes(p), gusPid));
    // The server adds "Something else…" to every choice question; the owner locks options, never that one.
    await railQ(owner, "Q2").click();
    ok("the choice question offers Something else…, with no Lock this one on it", await until(owner, () => {
      const o = document.querySelector(".vf-opt.vf-opt-other");
      return !!o && /Something else…/.test(o.textContent) && o.querySelector(".vf-optlock").hidden && !document.querySelector(".vf-opt:not(.vf-opt-other) .vf-optlock").hidden;
    }));

    // gather: reactions instead of votes
    await railQ(owner, "Q3").click();
    await owner.fill("#vf-answer", "Losing the saved card.");
    await owner.press("#vf-answer", "Control+Enter");
    await railQ(guest, "Q3").click();
    const gatherCard = guest.locator(".vf-alist .vf-card", { hasText: "Losing the saved card" });
    ok("a gather answer shows reactions and no vote", await until(guest, () => { const c = [...document.querySelectorAll(".vf-alist .vf-card")].find(x => /Losing the saved card/.test(x.textContent)); return !!c && !c.querySelector(".vf-reacts").hidden && c.querySelector(".vf-vote").hidden; }));
    await gatherCard.locator('.vf-react[data-r="thumbs"]').click();
    ok("a reaction reaches the server", await until(owner, () => window.Core.snapshot()?.cards?.Q3?.find(c => c.ref === "p:host")?.reactions?.thumbs === 1));

    // send
    await owner.locator(".vf-round-cur .vf-send").click();
    const confirm = owner.locator(".vf-confirm button", { hasText: "Send anyway" });
    if (await confirm.isVisible().catch(() => false)) await confirm.click();
    const sent = await until(owner, () => window.Core.snapshot()?.round?.status === "sent");
    ok("the owner sends the round to Claude", sent && share(dA, "status").round?.status === "sent", JSON.stringify(share(dA, "status").round));
    ok("the guest's page shows the round went to Claude", await until(guest, () => { const s = document.querySelector(".vf-next .vf-steps"); return !!s && !s.hidden; }));
    ok("the guest's composer is read-only once the round is sent", await until(guest, () => document.getElementById("vf-answer").disabled));

    // ---------- session B: imported from the prototype, a returning guest ----------
    const dB = path.join(tmp, "topic", "shared", "imported"); dirs.push(dB);
    const upB = share(dB, "ensure-running", "--import", path.join(here, "fixtures", "state-v0-prototype.json"), "--guest-port", String(await freePort()));
    const seed = { fn: s => { if (!localStorage.getItem("seeded")) { localStorage.setItem("seeded", "1"); for (const [k, v] of Object.entries(s)) localStorage.setItem(k, v); } } };
    // The prototype's core.js stored the secret, pid and name under these keys.
    const back = await openPage(upB.localUrl, { ...seed, arg: { secret: "fixture-guest-secret-ann-not-a-real-secret-000", pid: "pidAnn001", name: "Ann Example" } });
    ok("a returning guest of the imported session resolves to their pid", await until(back, () => window.Core.snapshot()?.me?.pid === "pidAnn001"));
    ok("the returning guest is not asked to join again", !(await back.$("dialog.core-name")));
    const bare = await openPage(upB.localUrl, { ...seed, arg: { secret: "fixture-guest-secret-bo-not-a-real-secret-0000" } });
    ok("a stored secret with no name beside it still resolves to its pid", await until(bare, () => window.Core.snapshot()?.me?.pid === "pidBo0002" && window.Core.me.name === "Bo Sample"));

    // every page, every poll
    ok("every /api/state request the page made carries a query string", stateUrls.length > 10 && stateUrls.every(s => /^\?since=\d+$/.test(s)), `${stateUrls.length} polls, ${stateUrls.filter(s => !/^\?since=\d+$/.test(s)).slice(0, 3).join(",")}`);
    for (const p of [owner, guest, back, bare]) csp.push(...(await p.evaluate(() => window.__csp || [])));
    ok("no page broke the server's CSP", csp.length === 0, csp.slice(0, 3).join(" | "));
    ok("no page error or console error", errors.length === 0, errors.slice(0, 3).join(" | "));
    ok("no request was answered 429 (slow down)", tooFast.length === 0, tooFast.slice(0, 5).join(", "));
  } catch (e) {
    results.push(`ERROR ${e?.stack || e}`);
  } finally {
    await browser.close().catch(() => {});
    for (const d of dirs) { try { share(d, "stop"); } catch { /* not running */ } }
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  for (const line of results) console.log(line);
  const failed = results.filter(l => !l.startsWith("PASS")).length;
  console.log(`ui_journey: ${results.length - failed} passed, ${failed} failed`);
  return failed ? 1 : 0;
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
