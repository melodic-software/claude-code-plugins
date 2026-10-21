#!/usr/bin/env node
// The owner's polish asks of 2026-10-21, against `share.sh ensure-running` with the fake cloudflared, in a session
// past its first round: in the question rail every round's label starts at one x, at 1440x900 and on a 390x844 phone,
// a round with something done showing a check and one with nothing done an empty ring in the same slot, both hidden
// from screen readers (the label says the count); on the phone the question header keeps the arrows on the position's
// row and the host's Purpose and Ask someone (then Change who) together on one row, each a 44 px target, with a long
// "Asked of" name following them and nothing past the screen, while at 1440 the header stays one row; and the
// owner's Approve all in Proposed counts the new proposals in its confirm, makes each a question in the next round,
// leaves one that arrived after the confirm in New, and is never offered to a guest.
//   node plugins/planning/shared/tests/ui_rail_header.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the owner's asks (every rail label lines up; one tidy phone header; Approve All with a
// confirm naming how many), WCAG 2.5.5 Target Size (44 x 44 CSS px), the 1 px tolerance the layout suites use, and the
// texts this suite writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const PHONE = { context: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 } };
const DESK = { context: { viewport: { width: 1440, height: 900 } } };
const TOL = 1, MIN_HIT = 44;
const CHOICE = { kind: "choice", options: [{ id: "opt-1", label: "Card" }, { id: "opt-2", label: "Wallet" }] };
const q = (id, text, format = { kind: "text" }) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format });
const Q4 = "What should the receipt email say?";
const IDEAS = ["Ask how refunds should work", "Ask which delivery slots matter"], LATE = "Arrived after the confirm";
const LONG = "Bartholomew Fitzgerald-Montgomery";

/** The visible round toggles in the rail: each label's left edge, its slot's width, and whether the slot is a check or a ring. */
const railRows = page => page.evaluate(() => [...document.querySelectorAll(".vf-round .vf-rtoggle")].filter(t => t.getClientRects().length).map(t => {
  const slot = t.querySelector(".vf-rcheck"), l = t.querySelector(".vf-rlabel"), svg = slot?.querySelector("svg");
  return { label: l.textContent, x: l.getBoundingClientRect().left, slot: slot?.getBoundingClientRect().width || 0,
    check: !!svg && svg.getClientRects().length > 0, ring: !!slot && slot.classList.contains("vf-rcheck-none"), hidden: slot?.getAttribute("aria-hidden") };
}));

/** The question header's boxes: the position, the arrows, the purpose select, the host's who button and the chip. */
const header = page => page.evaluate(() => {
  const box = el => { if (!el || !el.getClientRects().length) return null; const r = el.getBoundingClientRect(); return { top: r.top, bottom: r.bottom, left: r.left, right: r.right, h: r.height }; };
  const m = document.querySelector(".vf-focus .vf-qmeta");
  return { pos: box(m?.firstElementChild), nav: box(m?.querySelector(":scope > .vf-qnav")), sel: box(m?.querySelector(".vf-purposesel .vf-select")),
    who: box(m?.querySelector(".vf-forbtn")), whoText: m?.querySelector(".vf-forbtn")?.textContent, chip: box(m?.querySelector(".vf-forchip")),
    past: [...(m?.querySelectorAll("*") || [])].filter(e => e.getClientRects().length && e.getBoundingClientRect().right > innerWidth + 0.5).map(e => e.className),
    sideways: document.scrollingElement.scrollWidth > innerWidth };
});
const sameRow = (a, b) => !!a && !!b && a.top < b.bottom - TOL && b.top < a.bottom - TOL;

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_rail_header.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_rail_header"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("railhead");
    // Round 1 sent with one of its two questions decided; round 2 open.
    s.apply(A.dir, [{ op: "set-title", title: "Rail and header checks" }, { op: "open-round", questions: [q("Q1", "Which payment method first?", CHOICE), q("Q2", "Where should the summary sit?")] }]);
    const owner = await rec.open(A.ownerUrl, DESK);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    await owner.evaluate(() => window.Core.lock("Q1", "opt-1"));
    await owner.evaluate(() => window.Core.sendRound());
    s.apply(A.dir, [{ op: "ack-round", round: 1 }, { op: "open-round", questions: [q("Q3", "Which carrier?", CHOICE), q("Q4", Q4)] }]);
    await until(owner, () => (window.Core.snapshot()?.questions || []).some(x => x.id === "Q4"));
    const ann = await rec.open(A.localUrl, PHONE);
    await joinAs(ann, "Ann");
    const bart = await rec.open(A.localUrl, DESK);
    const bartPid = await joinAs(bart, LONG);

    // ---------- Approve all: the owner's, counted in its confirm, only what was counted ----------
    for (const t of IDEAS) await ann.evaluate(t => window.Core.idea(t), t);
    await until(owner, n => (window.Core.state.ideas || []).filter(i => i.status === "new").length === n, IDEAS.length);
    await owner.locator(".vf-proprow", { hasText: "Proposed" }).click();
    ok("the owner's Proposed panel offers Approve all, counting the new proposals", await until(owner, () => {
      const b = document.querySelector(".vf-prop-all"); return !!b?.getClientRects().length && b.textContent === "Approve all 2";
    }), await owner.evaluate(() => document.querySelector(".vf-prop-all")?.textContent));
    await owner.locator(".vf-prop-all").click();
    ok("  behind a confirm that names how many", await until(owner, () => /Approve all 2 proposals\?/.test(document.querySelector("dialog[open]")?.textContent || "")));
    await ann.evaluate(t => window.Core.idea(t), LATE); // arrives while the confirm is open
    await until(owner, () => (window.Core.state.ideas || []).filter(i => i.status === "new").length === 3);
    await owner.locator("dialog[open] button", { hasText: /^Approve 2$/ }).click();
    ok("  which makes each counted proposal a question in round 3", await until(owner, ideas => {
      const qs = window.Core.snapshot()?.questions || []; return ideas.every(t => qs.some(x => x.text === t && x.round === 3));
    }, IDEAS));
    ok("  and leaves the one that arrived after the confirm in New", await until(owner, t => {
      const fresh = (window.Core.state.ideas || []).filter(i => i.status === "new"); return fresh.length === 1 && fresh[0].text === t;
    }, LATE));
    ok("a guest is never offered Approve all", await ann.evaluate(() => !document.querySelector(".vf-prop-all")?.getClientRects().length));
    await owner.keyboard.press("Escape");

    // ---------- the rail: one label x, a check or a ring in every slot ----------
    const ownerPhone = await rec.open(A.ownerUrl, PHONE);
    await until(ownerPhone, () => window.Core.snapshot()?.me?.role === "owner");
    await ownerPhone.locator(".vf-tab", { hasText: "Questions" }).tap();
    for (const [label, page] of [["1440x900", owner], ["390x844", ownerPhone]]) {
      await until(page, () => [...document.querySelectorAll(".vf-round .vf-rtoggle")].filter(t => t.getClientRects().length).length >= 2);
      const rows = await railRows(page);
      const xs = rows.map(r => r.x), spread = xs.length ? Math.max(...xs) - Math.min(...xs) : Infinity;
      ok(`${label}: every round's label in the rail starts at one x`, rows.length >= 2 && spread <= TOL, JSON.stringify(rows));
      ok(`  a round with a decided question shows a check, one with none an empty ring, in a slot of one width`,
        rows.some(r => r.check && !r.ring) && rows.some(r => r.ring && !r.check) && rows.every(r => r.slot > 0 && Math.abs(r.slot - rows[0].slot) <= TOL), JSON.stringify(rows));
      ok("  each slot hidden from screen readers, as the label says the count", rows.every(r => r.hidden === "true"), JSON.stringify(rows));
    }

    // ---------- the phone question header ----------
    await ownerPhone.locator(".vf-q", { hasText: Q4 }).first().tap();
    await until(ownerPhone, t => document.querySelector(".vf-qtext")?.textContent === t, Q4);
    let h = await header(ownerPhone);
    ok("390x844 owner: the arrows stay on the position's row", sameRow(h.nav, h.pos), JSON.stringify(h));
    ok("  Purpose and Ask someone sit together on one row", h.whoText === "Ask someone" && sameRow(h.sel, h.who), JSON.stringify(h));
    ok(`  each a ${MIN_HIT} px tap target`, h.sel?.h >= MIN_HIT - 0.5 && h.who?.h >= MIN_HIT - 0.5, JSON.stringify([h.sel, h.who]));
    ok("  nothing past the screen and no sideways scroll", !h.past.length && !h.sideways, JSON.stringify(h.past));
    await owner.evaluate(p => window.Core.setFor("Q4", [p]), bartPid);
    await until(ownerPhone, () => document.querySelector(".vf-forbtn")?.textContent === "Change who");
    h = await header(ownerPhone);
    ok(`  asked of ${LONG}: Purpose and Change who still share a row`, sameRow(h.sel, h.who) && h.who?.h >= MIN_HIT - 0.5, JSON.stringify(h));
    ok("  who it asks shows after them, nothing past the screen", !!h.chip && (h.chip.top >= h.who.bottom - TOL || (sameRow(h.chip, h.who) && h.chip.left >= h.who.right - TOL))
      && !h.past.length && !h.sideways, JSON.stringify(h));

    await owner.locator(".vf-q", { hasText: Q4 }).first().click();
    await until(owner, t => document.querySelector(".vf-qtext")?.textContent === t, Q4);
    h = await header(owner);
    ok("1440x900 owner: the header stays one row, position, Purpose and Change who side by side", sameRow(h.pos, h.sel) && sameRow(h.sel, h.who), JSON.stringify(h));

    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
    ok("no CSP violation", (await rec.cspViolations()).length === 0);
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
