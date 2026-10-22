#!/usr/bin/env node
// The page on a 390x844 touch phone as a native app would behave (O114), against `share.sh ensure-running` with the fake
// cloudflared: after a guest saves a long answer (one unbroken 120-letter word and a long link) from the phone sheet,
// nothing scrolls sideways, the folded answer field and the answer card keep the text inside them, every control in the
// question's view is a 44 px tap target, the sheet's Save sits under the field in thumb reach, and the chat message menu
// opens as a bottom sheet the width of the screen, its last row clear of the bottom edge; with "Run it on my own Claude"
// on, the question's ask box offers no Attach and takes no pasted picture (sweep S11).
//   node plugins/planning/shared/tests/ui_phone.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from O114 (no sideways scroll, text wraps in its card, 44 px targets, primary action in thumb
// reach, menus as bottom sheets) and the texts this suite writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, settled, joinAs } = require("./browser_harness");

const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });
const QT = "What should the receipt email say?";
const WORD = "x".repeat(120);
const LONG = `The receipt should say ${WORD} and link https://example.com/receipts/${"segment/".repeat(12)}end so people find it.`;
const PHONE = { context: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true } };

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_phone.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_phone"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("phone");
    s.apply(A.dir, [{ op: "set-title", title: "Receipts" }, { op: "open-round", questions: [q("Q1", QT)] }]);
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const ann = await rec.open(A.localUrl, PHONE);
    await joinAs(ann, "Ann");
    await until(ann, t => document.querySelector(".vf-qtext")?.textContent === t, QT);
    // the welcome card is not under test here
    await ann.evaluate(() => document.querySelector(".vf-orient-x")?.click());

    // ---------- a long answer from the phone sheet ----------
    await ann.locator("#vf-answer").tap();
    ok("tapping the answer field opens the full-height sheet", await until(ann, () => !!document.querySelector(".vf-composer-sheet")));
    await ann.keyboard.insertText(LONG);
    const sheetStill = await settled(ann, { rects: true });
    const save = await ann.evaluate(() => {
      const b = document.querySelector(".vf-composer-sheet .vf-sheetsave").getBoundingClientRect(), t = document.querySelector("#vf-answer").getBoundingClientRect(), vv = visualViewport;
      return { under: b.top >= t.bottom - 1, inView: b.bottom <= vv.offsetTop + vv.height + 1, w: b.width, h: b.height };
    });
    ok("  its Save is under the field, inside the visible screen, in thumb reach, at least 44 px tall", sheetStill && save.under && save.inView && save.h >= 44, JSON.stringify({ still: sheetStill, ...save }));
    await ann.locator(".vf-sheetsave").tap();
    ok("Save sends the long answer", await until(owner, t => (window.Core.snapshot().cards?.Q1 || []).some(c => c.text === t), LONG, 10000));
    await until(ann, w => !document.querySelector(".vf-composer-sheet") && [...document.querySelectorAll(".vf-alist .vf-card")].some(c => c.textContent.includes(w)), WORD);
    const still = await settled(ann, { rects: true });
    const fit = { still, ...await ann.evaluate(w => {
      const se = document.scrollingElement, app = document.getElementById("app"), ta = document.querySelector("#vf-answer");
      const card = [...document.querySelectorAll(".vf-alist .vf-card")].find(c => c.textContent.includes(w));
      const r = card?.getBoundingClientRect();
      // the field's content box (its rect less padding) against the buttons drawn inside it
      const cs = getComputedStyle(ta), tr = ta.getBoundingClientRect(), px = v => parseFloat(v) || 0;
      const box = { l: tr.left + px(cs.borderLeftWidth) + px(cs.paddingLeft), r: tr.right - px(cs.borderRightWidth) - px(cs.paddingRight),
        t: tr.top + px(cs.borderTopWidth) + px(cs.paddingTop), b: tr.bottom - px(cs.borderBottomWidth) - px(cs.paddingBottom) };
      const btns = [...document.querySelectorAll(".vf-composer :is(.vf-sendbtn, .vf-attach)")].filter(b => b.getClientRects().length).map(b => b.getBoundingClientRect());
      const clear = btns.length > 0 && btns.every(b => b.right <= box.l + 0.5 || b.left >= box.r - 0.5 || b.bottom <= box.t + 0.5 || b.top >= box.b - 0.5);
      return { page: se.scrollWidth <= innerWidth && app.scrollWidth <= app.clientWidth, field: ta.scrollWidth <= ta.clientWidth + 1, clear, nBtns: btns.length,
        card: !!card && card.scrollWidth <= card.clientWidth + 1 && r.left >= 0 && r.right <= innerWidth,
        cardText: !!card && [...card.querySelectorAll(".vf-rich")].every(e => e.scrollWidth <= e.clientWidth + 1) };
    }, WORD) };
    ok("after the save nothing on the page scrolls sideways", still && fit.page, JSON.stringify(fit));
    ok("  the folded answer field wraps the long answer inside itself, under no button", still && fit.field && fit.clear, JSON.stringify(fit));
    ok("  and the answer card holds its text inside its own box, on the screen", still && fit.card && fit.cardText, JSON.stringify(fit));

    // ---------- 44 px tap targets in the question's view ----------
    // a control drawn small with a transparent ring (::after, absolutely placed) counts the ring's size
    const small = await ann.evaluate(() => [...document.querySelectorAll(".vf-focus :is(button, a[href], [role=button], input, select)")]
      .filter(e => e.getClientRects().length && getComputedStyle(e).visibility !== "hidden" && !e.closest("[hidden], [inert]") && !e.disabled)
      .map(e => {
        const r = e.getBoundingClientRect(), a = getComputedStyle(e, "::after"), ring = a.content !== "none" && a.position === "absolute";
        const out = side => (ring ? Math.max(0, -parseFloat(a[side]) || 0) : 0);
        return { e, w: r.width + out("left") + out("right"), h: r.height + out("top") + out("bottom") };
      })
      .filter(x => x.h < 44 - 0.5 || x.w < 44 - 0.5)
      .map(x => `${x.e.tagName.toLowerCase()}.${[...x.e.classList].join(".")} "${(x.e.textContent || x.e.getAttribute("aria-label") || "").trim().slice(0, 24)}" ${Math.round(x.w)}x${Math.round(x.h)}`));
    ok("every control in the question's view is at least 44 x 44 px", small.length === 0, small.slice(0, 8).join("; "));

    // ---------- the message menu is a bottom sheet ----------
    await ann.evaluate(() => window.Core.chat("Hello from my phone"));
    await ann.locator(".vf-fab").tap();
    await until(ann, () => !!document.querySelector(".vf-msg .vf-msgmore"), null, 10000);
    await ann.evaluate(() => [...document.querySelectorAll(".vf-msg .vf-msgmore")].at(-1).click());
    const menu = await ann.evaluate(async () => {
      const m = document.querySelector(".vf-msgmenu");
      await Promise.all(m.getAnimations().map(a => a.finished.catch(() => null))); // measured once its opening animation ends
      const r = m.getBoundingClientRect(), vv = visualViewport;
      const items = [...m.querySelectorAll(".vf-menu-item")].filter(i => i.getClientRects().length);
      return { open: !m.hidden, full: r.left <= 0.5 && r.right >= innerWidth - 0.5, bottom: Math.abs(r.bottom - (vv.offsetTop + vv.height)) <= 1,
        lastClear: items.length > 0 && items.at(-1).getBoundingClientRect().bottom <= r.bottom - 4, rows: items.length };
    });
    ok("the chat message menu opens as a bottom sheet the width of the screen", menu.open && menu.full && menu.bottom, JSON.stringify(menu));
    ok("  its last row clear of the bottom edge", menu.lastClear, JSON.stringify(menu));

    // ---------- the question's ask box on my own Claude carries no files (sweep S11) ----------
    await ann.keyboard.press("Escape"); // the menu
    await until(ann, () => document.querySelector(".vf-msgmenu").hidden);
    await ann.evaluate(() => { const f = document.querySelector(".vf-fab"); if (f.getAttribute("aria-expanded") === "true") f.click(); }); // the chat
    await until(ann, () => document.querySelector(".vf-chat").hidden);
    await owner.evaluate(() => window.Core.saveSettings({ uploads: true }));
    await until(ann, () => window.Core.state.settings?.uploads === true, null, 10000);
    await ann.evaluate(() => { const b = document.querySelector(".vf-askbtn"); if (b.getAttribute("aria-expanded") !== "true") b.click(); });
    const attachShown = () => ann.evaluate(() => { const b = document.querySelector(".vf-askform .vf-attach"); return !!b && b.getClientRects().length > 0; });
    ok("the question's ask box offers Attach while it goes to the host", await until(ann, () => { const b = document.querySelector(".vf-askform .vf-attach"); return !!b && b.getClientRects().length > 0; }, null, 10000));
    await ann.evaluate(() => document.querySelector(".vf-askself").click());
    ok("  with Run it on my own Claude on, Attach is gone", await until(ann, () => document.querySelector(".vf-askself").getAttribute("aria-checked") === "true"
      && !document.querySelector(".vf-askform .vf-attach")?.getClientRects().length) && !(await attachShown()));
    await ann.evaluate(async () => {
      const c = document.createElement("canvas"); c.width = 32; c.height = 20; c.getContext("2d").fillRect(0, 0, 32, 20);
      const blob = await new Promise(r => c.toBlob(r, "image/png")), dt = new DataTransfer();
      dt.items.add(new File([blob], "shot.png", { type: "image/png" }));
      document.getElementById("vf-ask-ta").dispatchEvent(new ClipboardEvent("paste", { clipboardData: dt, bubbles: true, cancelable: true }));
    });
    await ann.waitForTimeout(1500);
    ok("  and a pasted picture adds no file to it", await ann.evaluate(() => !(window.Core.snapshot().myUploads || []).length
      && ![...document.querySelectorAll(".vf-askform .vf-attdraft .vf-ref")].some(li => li.getClientRects().length)));

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
