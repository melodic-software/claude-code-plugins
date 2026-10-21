#!/usr/bin/env node
// A page told the session moved (GET /api/state answers {moved} on a retired tunnel's host, server.py) in a real
// browser, against `share.sh ensure-running` with the fake cloudflared. core.js's moveTo follows only an https address
// on another origin, once, carrying a guest's secret as #me= (or a newcomer's invite key as #join=), and never moves
// the owner's tab. A page holding unsent text (sessionStorage keeps it per origin) stays and shows the move in its
// banner until the person presses Go to the new address. The answer is staged with page.route, as the retired host
// would send it; the new address is served by a route too, so nothing leaves the machine.
//   node plugins/planning/shared/tests/ui_move.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the security review's guards for moveTo and the secret the server issued on join.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });
const NEW = "https://moved.example";

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_move.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_move"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("move");
    s.apply(A.dir, [{ op: "set-title", title: "Offsite" }, { op: "open-round", questions: [q("Q1", "Where should we go?")] }]);
    /** Answer this page's polls with {moved: to} from now on; count the requests that reach NEW. */
    const stage = async (page, to, { arrive = true } = {}) => {
      const hits = [];
      await page.context().route(`${NEW}/**`, r => { hits.push(r.request().url()); return arrive ? r.fulfill({ status: 200, contentType: "text/html", body: "<!doctype html><title>moved</title>" }) : r.abort(); });
      await page.route(/\/api\/state/, r => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ moved: to }) }));
      return hits;
    };
    const stays = async page => { const at = page.url(); await page.waitForTimeout(4000); return page.url() === at; };
    const notice = page => until(page, () => !document.querySelector(".vf-banner").hidden
      && /moved to a new address.*stops working in about 10 minutes/.test(document.querySelector(".vf-banner-txt").textContent), null, 10000);

    const ann = await rec.open(A.localUrl);
    await joinAs(ann, "Ann");
    const secret = await ann.evaluate(() => localStorage.getItem("secret"));
    await stage(ann, NEW);
    ok("a guest's page with no unsent text moves to the new https address with its secret as a personal link",
      await until(ann, u => location.href === u, `${NEW}/#me=${secret}`, 10000), ann.url());

    for (const [name, field, text, chat] of [["Ed", "#vf-answer", "Somewhere with a lake."], ["Flo", ".vf-minput", "An unsent chat line", true]]) {
      const p = await rec.open(A.localUrl);
      await joinAs(p, name);
      const key = await p.evaluate(() => localStorage.getItem("secret"));
      if (chat) await p.click(".vf-fab");
      await p.fill(field, text);
      if (chat) await p.click(".vf-fab");
      await stage(p, NEW);
      ok(`a guest with unsent text in ${field} is told the session moved and stays`, (await notice(p)) && (await stays(p)), p.url());
      await p.getByRole("button", { name: "Go to the new address" }).click();
      ok(`pressing Go to the new address moves the guest with ${field} text, with its secret`,
        await until(p, u => location.href === u, `${NEW}/#me=${key}`, 10000), p.url());
    }

    const bo = await rec.open(A.localUrl);
    await joinAs(bo, "Bo");
    await stage(bo, "http://moved.example");
    ok("an http address is not followed", await stays(bo));

    const cy = await rec.open(A.localUrl);
    await joinAs(cy, "Cy");
    await stage(cy, A.localUrl);
    ok("this page's own origin is not followed", await stays(cy));

    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    await stage(owner, NEW);
    ok("the owner's tab never moves", await stays(owner));

    const di = await rec.open(A.localUrl);
    await joinAs(di, "Di");
    const hits = await stage(di, NEW, { arrive: false });
    await di.waitForTimeout(5000); // several polls, each answering {moved}
    ok("a move is tried once, however many polls say moved", hits.length === 1, JSON.stringify(hits));

    const newcomer = await rec.open(`${A.localUrl}#join=k3y`);
    await stage(newcomer, NEW);
    ok("someone who has not joined moves with the invite key only",
      await until(newcomer, u => location.href === u, `${NEW}/#join=k3y`, 10000), newcomer.url());
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
