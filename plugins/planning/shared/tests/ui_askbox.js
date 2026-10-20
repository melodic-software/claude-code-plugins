#!/usr/bin/env node
// One Ask Claude box (follow-up item 2), against `share.sh ensure-running` with the fake cloudflared: a guest's Ask
// Claude panel and a question's Ask Claude form show no kind picker (Ask, Research, Explore) but a "Use the web" chip,
// off by default; a request goes as `ask`, or as `research` with the chip on; the note says Claude works out how to
// answer; the owner keeps the Ask, Research and Explore tabs and gets no chip.
//   node plugins/planning/shared/tests/ui_askbox.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the approved spec (follow-up item 2) and the texts this suite writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });
const PLAIN = "Which of these options did people in the chat lean to?", WEB = "How do other checkouts place the summary?", INLINE = "What do payment guidelines say about this?";

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_askbox.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_askbox"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("askbox");
    s.apply(A.dir, [{ op: "set-title", title: "Checkout" }, { op: "open-round", questions: [q("Q1", "Where should the order summary sit?")] }]);
    const desk = { context: { viewport: { width: 1440, height: 900 } } };
    const owner = await rec.open(A.ownerUrl, desk);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const ann = await rec.open(A.localUrl, desk);
    await joinAs(ann, "Ann");
    const sent = text => until(owner, t => (window.Core.snapshot()?.requests || []).some(r => r.text === t), text, 8000)
      .then(() => owner.evaluate(t => window.Core.snapshot().requests.find(r => r.text === t)?.kind, text));

    // ---------- the Ask Claude panel: one box and a Use the web chip ----------
    await ann.click(".vf-asktop");
    await until(ann, () => !!document.querySelector(".vf-drawer:not([hidden]) .vf-apform"));
    const panel = await ann.evaluate(() => {
      const shown = sel => [...document.querySelectorAll(sel)].filter(e => e.getClientRects().length && !e.closest("[hidden]"));
      const chip = shown(".vf-drawer .vf-webchip")[0];
      return { tabs: shown(".vf-drawer .vf-apmodes [role=tab]").map(t => t.textContent), chip: chip?.textContent, pressed: chip?.getAttribute("aria-pressed"),
        note: shown(".vf-apform .vf-pop-note").map(n => n.textContent).join(" ") };
    });
    ok("a guest's Ask Claude shows no Ask, Research or Explore picker", panel.tabs.length === 0, JSON.stringify(panel));
    ok("it shows a Use the web chip, off", panel.chip === "Use the web" && panel.pressed === "false", JSON.stringify(panel));
    ok("the note says Claude works out how to answer and says what it did", /Claude works out how to answer and says what it did/.test(panel.note), panel.note);
    await ann.fill("#vf-ap-ta", PLAIN);
    await ann.click(".vf-apform button[type=submit]");
    ok("sent with the chip off, it goes as an ask", (await sent(PLAIN)) === "ask");
    await ann.waitForTimeout(1200); // one request a second per person
    await ann.click(".vf-drawer .vf-webchip");
    ok("pressing Use the web turns it on", (await ann.getAttribute(".vf-drawer .vf-webchip", "aria-pressed")) === "true");
    await ann.fill("#vf-ap-ta", WEB);
    await ann.click(".vf-apform button[type=submit]");
    ok("sent with Use the web on, it goes as research", (await sent(WEB)) === "research");
    ok("the chip is off again after sending", await until(ann, () => document.querySelector(".vf-drawer .vf-webchip").getAttribute("aria-pressed") === "false"));
    await ann.keyboard.press("Escape");

    // ---------- a question's Ask Claude form: the same ----------
    await ann.waitForTimeout(1200);
    const aria = await ann.evaluate(() => { const b = document.querySelector(".vf-askbtn"); return { pop: b.getAttribute("aria-haspopup"), ctl: b.getAttribute("aria-controls"), form: document.querySelector(".vf-askform").id, chev: !!b.querySelector(".vf-chev") }; });
    ok("the question's Ask Claude button claims no menu: it controls the ask form, with no chevron (B4)", aria.pop === null && aria.ctl === aria.form && !!aria.form && !aria.chev, JSON.stringify(aria));
    await ann.click(".vf-askbtn");
    await until(ann, () => !document.querySelector(".vf-askform").hidden);
    ok("pressing it opens the form and says so", (await ann.getAttribute(".vf-askbtn", "aria-expanded")) === "true");
    const form = await ann.evaluate(() => {
      const shown = sel => [...document.querySelectorAll(sel)].filter(e => e.getClientRects().length && !e.closest("[hidden]"));
      return { seg: shown(".vf-askform .vf-seg-btn").filter(b => !b.closest(".vf-aud")).map(b => b.textContent), chip: shown(".vf-askform .vf-webchip").map(b => b.textContent) };
    });
    ok("a question's Ask Claude form shows no Ask or Research picker, only Use the web", form.seg.length === 0 && form.chip.join() === "Use the web", JSON.stringify(form));
    await ann.click(".vf-askform .vf-webchip");
    await ann.fill("#vf-ask-ta", INLINE);
    await ann.click(".vf-askform button[type=submit]");
    ok("sent from the question with Use the web on, it goes as research", (await sent(INLINE)) === "research");

    // ---------- the owner keeps the picker ----------
    await owner.click(".vf-asktop");
    await until(owner, () => !!document.querySelector(".vf-drawer:not([hidden]) .vf-apform"));
    const own = await owner.evaluate(() => {
      const shown = sel => [...document.querySelectorAll(sel)].filter(e => e.getClientRects().length && !e.closest("[hidden]"));
      return { tabs: shown(".vf-drawer .vf-apmodes [role=tab]").map(t => t.textContent), chip: shown(".vf-drawer .vf-webchip").length };
    });
    ok("the owner keeps Ask, Research and Explore and gets no chip", own.tabs.join() === "Ask,Research,Explore" && own.chip === 0, JSON.stringify(own));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
