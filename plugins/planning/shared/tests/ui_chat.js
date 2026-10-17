#!/usr/bin/env node
// The side chat in real browsers, against `share.sh ensure-running` with the fake cloudflared (triage 2 and 24): the
// host, chat closed, sees a guest's message on the chat button's badge and in the tab title; a page frozen the way a
// phone freezes a background tab shows all 3 messages posted meanwhile within 2 s of thawing; and a reader scrolled up
// in the chat gets a "3 new messages" pill instead of a jump.
//   node plugins/planning/shared/tests/ui_chat.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the triage rows (badge, 3 messages, 2 s) and the messages this suite posts, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_chat.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_chat"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("chat");
    s.apply(A.dir, [{ op: "set-title", title: "Chat checks" }, { op: "open-round", questions: [{ id: "Q1", text: "Anything?", alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } }] }]);
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const gus = await rec.open(A.localUrl);
    await joinAs(gus, "Gus");

    // ---------- triage 2: the host sees a guest's message ----------
    await gus.evaluate(() => window.Core.chat("Heyro?"));
    ok("the host, chat closed, sees a guest's message as a badge on the chat button", await until(owner, () => document.querySelector(".vf-fab-badge")?.textContent === "1"
      && /1 unread/.test(document.querySelector(".vf-fab").getAttribute("aria-label"))));
    ok("the host's tab title counts it too", await until(owner, () => document.title === "(1) Chat checks"));
    await owner.click(".vf-fab");
    ok("opening the chat clears the badge and the title count", await until(owner, () => !document.querySelector(".vf-fab-badge").textContent && document.title === "Chat checks"));

    // ---------- triage 24: a frozen page catches up within 2 s of thawing ----------
    const cdp = await owner.context().newCDPSession(owner);
    await cdp.send("Page.setWebLifecycleState", { state: "frozen" });
    const sent = [];
    for (const t of ["One while away", "Two while away", "Three while away"]) { sent.push(t); await gus.evaluate(x => window.Core.chat(x), t); }
    await owner.waitForTimeout(3000);
    await cdp.send("Page.setWebLifecycleState", { state: "active" });
    const t0 = Date.now();
    const all3 = await until(owner, ts => ts.every(t => [...document.querySelectorAll(".vf-mlist .vf-msg")].some(li => li.textContent.includes(t))), sent, 2000);
    ok("after the page thaws, all 3 messages posted meanwhile show within 2 s", all3, `${Date.now() - t0} ms`);

    // ---------- triage 24: scrolled up, new messages wait behind a pill ----------
    for (let i = 0; i < 12; i++) await gus.evaluate(x => window.Core.chat(x), `Filler ${i} ${"so the chat scrolls ".repeat(3)}`);
    await until(owner, () => document.querySelectorAll(".vf-mlist .vf-msg").length >= 16);
    await owner.evaluate(() => { document.querySelector(".vf-mscroll").scrollTop = 0; });
    await owner.waitForTimeout(300);
    for (const t of ["New A", "New B", "New C"]) await gus.evaluate(x => window.Core.chat(x), t);
    ok("scrolled up, the chat shows a \"3 new messages\" pill and stays where the reader is", await until(owner, () => {
      const p = document.querySelector(".vf-mnew");
      return !!p && !p.hidden && p.textContent.startsWith("3 new messages") && document.querySelector(".vf-mscroll").scrollTop < 40;
    }));
    await owner.click(".vf-mnew");
    ok("the pill takes the reader to the newest message and goes away", await until(owner, () => {
      const sc = document.querySelector(".vf-mscroll");
      return document.querySelector(".vf-mnew").hidden && sc.scrollHeight - sc.scrollTop - sc.clientHeight < 40;
    }));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    ok("no page error", rec.errors.filter(m => !/Failed to load resource/.test(m)).length === 0, rec.errors.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
