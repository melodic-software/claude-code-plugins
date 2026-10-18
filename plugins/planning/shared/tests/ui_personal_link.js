#!/usr/bin/env node
// A personal link ("Use on another device", #me=<secret>) in a real browser, against `share.sh ensure-running` with
// the fake cloudflared. In a browser that already holds a different person's secret, the link never signs it in as
// that person silently: it asks "This link signs you in as someone else on this device. Switch?", with Keep focused,
// Keep and Escape leave the stored secret as it was, and only Switch replaces it. With no secret stored, the link is
// adopted at once, as before; a link holding the browser's own secret asks nothing.
//   node plugins/planning/shared/tests/ui_personal_link.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the review finding (session fixation through #me; Keep is the default), the secrets the
// server issued on join and the names this suite types, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });
const ASK = "This link signs you in as someone else on this device. Switch?";

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_personal_link.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_personal_link"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("personal-link");
    s.apply(A.dir, [{ op: "set-title", title: "Offsite" }, { op: "open-round", questions: [q("Q1", "Where should we go?")] }]);
    const ann = await rec.open(A.localUrl);
    const annPid = await joinAs(ann, "Ann");
    const annSecret = await ann.evaluate(() => localStorage.getItem("secret"));
    const bo = await rec.open(A.localUrl);
    const boPid = await joinAs(bo, "Bo");
    const boSecret = await bo.evaluate(() => localStorage.getItem("secret"));
    const stored = page => page.evaluate(() => localStorage.getItem("secret"));
    const asking = page => until(page, () => !!document.querySelector("dialog.core-switch[open]"));

    // ---------- Bo's link in Ann's browser: asked, and Keep leaves Ann ----------
    const tab = await rec.openIn(ann.context(), `${A.localUrl}#me=${boSecret}`);
    ok("Bo's personal link in Ann's browser asks before switching", await asking(tab));
    ok("  with the finding's question", (await tab.evaluate(() => document.querySelector("dialog.core-switch h2")?.textContent)) === ASK,
      await tab.evaluate(() => document.querySelector("dialog.core-switch")?.textContent));
    ok("  and Keep has focus", await tab.evaluate(() => document.activeElement?.textContent === "Keep"));
    ok("  while it asks, the browser still holds Ann's secret", (await stored(tab)) === annSecret);
    ok("  and the address bar no longer carries Bo's secret", !(await tab.evaluate(() => location.hash)).includes(boSecret));
    await tab.keyboard.press("Escape");
    ok("Escape keeps Ann", await until(tab, () => !document.querySelector("dialog.core-switch")) && (await stored(tab)) === annSecret);
    ok("  and the page is still Ann's", await until(tab, p => window.Core.snapshot()?.me?.pid === p, annPid));

    const tab2 = await rec.openIn(ann.context(), `${A.localUrl}#me=${boSecret}`);
    await asking(tab2);
    await tab2.click("dialog.core-switch button:text-is('Keep')");
    await tab2.waitForTimeout(2000); // a poll and a beat
    ok("Keep keeps Ann", (await stored(tab2)) === annSecret && (await tab2.evaluate(() => window.Core.snapshot()?.me?.pid)) === annPid);

    // ---------- Switch: only then the browser becomes Bo ----------
    const tab3 = await rec.openIn(ann.context(), `${A.localUrl}#me=${boSecret}`);
    await asking(tab3);
    await tab3.click("dialog.core-switch button:text-is('Switch')");
    ok("Switch stores Bo's secret", await until(tab3, s => localStorage.getItem("secret") === s, boSecret));
    ok("  and the page signs in as Bo", await until(tab3, p => window.Core.snapshot()?.me?.pid === p && window.Core.me.name === "Bo", boPid, 10000));

    // ---------- no secret stored: adopted at once; the browser's own secret: nothing to ask ----------
    const fresh = await rec.open(`${A.localUrl}#me=${annSecret}`);
    ok("in a browser with no secret, a personal link signs in at once", await until(fresh, p => window.Core.snapshot()?.me?.pid === p, annPid, 10000));
    ok("  without asking", !(await fresh.evaluate(() => !!document.querySelector("dialog.core-switch"))));
    const own = await rec.openIn(fresh.context(), `${A.localUrl}#me=${annSecret}`);
    await own.waitForTimeout(1500);
    ok("a link holding the browser's own secret asks nothing", !(await own.evaluate(() => !!document.querySelector("dialog.core-switch"))) && (await stored(own)) === annSecret);

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
    ok("no request was answered 429 (slow down)", rec.too.length === 0, rec.too.slice(0, 5).join(", "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
