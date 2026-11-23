#!/usr/bin/env node
"use strict";
const { loadPlaywright, suite, recorder, until, settled, joinAs } = require("./browser_harness");

const PHONE = { context: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 } };
const DESK = { context: { viewport: { width: 1440, height: 900 } } };
const TOL = 1, MIN_HIT = 44;
const CHOICE = { kind: "choice", options: [{ id: "opt-1", label: "Card" }, { id: "opt-2", label: "Wallet" }] };
const q = (id, text, format = { kind: "text" }) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format });
const Q4 = "What should the receipt email say?";
const IDEAS = ["Ask how refunds should work", "Ask which delivery slots matter"], LATE = "Arrived after the confirm";
const LONG = "Bartholomew Fitzgerald-Montgomery";

const railRows = async page => ({ still: await settled(page, { rects: true }), rows: await page.evaluate(() => [...document.querySelectorAll(".vf-round .vf-rtoggle")].filter(t => t.getClientRects().length).map(t => {
  const slot = t.querySelector(".vf-rcheck"), l = t.querySelector(".vf-rlabel"), svg = slot?.querySelector("svg");
  return { label: l.textContent, x: l.getBoundingClientRect().left, slot: slot?.getBoundingClientRect().width || 0,
    check: !!svg && svg.getClientRects().length > 0, ring: !!slot && slot.classList.contains("vf-rcheck-none"), hidden: slot?.getAttribute("aria-hidden") };
})) });

const header = async page => ({ still: await settled(page, { rects: true }), ...await page.evaluate(() => {
  const box = el => { if (!el || !el.getClientRects().length) return null; const r = el.getBoundingClientRect(); return { top: r.top, bottom: r.bottom, left: r.left, right: r.right, h: r.height }; };
  const m = document.querySelector(".vf-focus .vf-qmeta");
  return { pos: box(m?.firstElementChild), nav: box(m?.querySelector(":scope > .vf-qnav")), sel: box(m?.querySelector(".vf-purposesel .vf-select")),
    who: box(m?.querySelector(".vf-forbtn")), whoText: m?.querySelector(".vf-forbtn")?.textContent, chip: box(m?.querySelector(".vf-forchip")),
    past: [...(m?.querySelectorAll("*") || [])].filter(e => e.getClientRects().length && e.getBoundingClientRect().right > innerWidth + 0.5).map(e => e.className),
    sideways: document.scrollingElement.scrollWidth > innerWidth };
}) });
const sameRow = (a, b) => !!a && !!b && a.top < b.bottom - TOL && b.top < a.bottom - TOL;

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_rail_header.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_rail_header"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("railhead");
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

    for (const t of IDEAS) await ann.evaluate(t => window.Core.idea(t), t);
    await until(owner, n => (window.Core.state.ideas || []).filter(i => i.status === "new").length === n, IDEAS.length);
    await owner.locator(".vf-proprow", { hasText: "Proposed" }).click();
    ok("the owner's Proposed panel offers Approve all, counting the new proposals", await until(owner, () => {
      const b = document.querySelector(".vf-prop-all"); return !!b?.getClientRects().length && b.textContent === "Approve all 2";
    }), await owner.evaluate(() => document.querySelector(".vf-prop-all")?.textContent));
    await owner.locator(".vf-prop-all").click();
    ok("  behind a confirm that names how many", await until(owner, () => /Approve all 2 proposals\?/.test(document.querySelector("dialog[open]")?.textContent || "")));
    await ann.evaluate(t => window.Core.idea(t), LATE);
    await until(owner, () => (window.Core.state.ideas || []).filter(i => i.status === "new").length === 3);
    await owner.locator("dialog[open] button", { hasText: /^Approve 2$/ }).click();
    ok("  which makes each counted proposal a question in round 3", await until(owner, ideas => {
      const qs = window.Core.snapshot()?.questions || []; return ideas.every(t => qs.some(x => x.text === t && x.round === 3));
    }, IDEAS));
    ok("  and leaves the one that arrived after the confirm in New", await until(owner, t => {
      const fresh = (window.Core.state.ideas || []).filter(i => i.status === "new"); return fresh.length === 1 && fresh[0].text === t;
    }, LATE));
    ok("a guest is never offered Approve all", await ann.evaluate(() => !document.querySelector(".vf-prop-all")?.getClientRects().length));
    const propose = async n => { for (let i = 0; i < n; i++) { await ann.waitForTimeout(1100); await ann.evaluate(t => window.Core.idea(t), `Extra proposal ${i} of ${n}`); } };
    await propose(5);
    ok("with 6 new proposals and room for 6, Approve all 6 can be pressed", await until(owner, () => {
      const b = document.querySelector(".vf-prop-all"); return b?.textContent === "Approve all 6" && !b.disabled;
    }), await owner.evaluate(() => `${document.querySelector(".vf-prop-all")?.textContent} disabled=${document.querySelector(".vf-prop-all")?.disabled}`));
    await propose(1);
    ok("  with 7 it cannot, and says the round has room for 6", await until(owner, () => {
      const b = document.querySelector(".vf-prop-all"), why = document.querySelector(".vf-prop-all-why");
      return b?.textContent === "Approve all 7" && b.disabled && !!why?.getClientRects().length && /room for 6\b/.test(why.textContent);
    }), await owner.evaluate(() => `${document.querySelector(".vf-prop-all")?.textContent} disabled=${document.querySelector(".vf-prop-all")?.disabled} why=${document.querySelector(".vf-prop-all-why")?.textContent}`));
    await owner.keyboard.press("Escape");

    const ownerPhone = await rec.open(A.ownerUrl, PHONE);
    await until(ownerPhone, () => window.Core.snapshot()?.me?.role === "owner");
    await ownerPhone.locator(".vf-tab", { hasText: "Questions" }).tap();
    for (const [label, page] of [["1440x900", owner], ["390x844", ownerPhone]]) {
      await until(page, () => [...document.querySelectorAll(".vf-round .vf-rtoggle")].filter(t => t.getClientRects().length).length >= 2);
      const { still, rows } = await railRows(page);
      const xs = rows.map(r => r.x), spread = xs.length ? Math.max(...xs) - Math.min(...xs) : Infinity;
      ok(`${label}: every round's label in the rail starts at one x`, still && rows.length >= 2 && spread <= TOL, JSON.stringify({ still, rows }));
      ok(`  a round with a decided question shows a check, one with none an empty ring, in a slot of one width`,
        rows.some(r => r.check && !r.ring) && rows.some(r => r.ring && !r.check) && rows.every(r => r.slot > 0 && Math.abs(r.slot - rows[0].slot) <= TOL), JSON.stringify(rows));
      ok("  each slot hidden from screen readers, as the label says the count", rows.every(r => r.hidden === "true"), JSON.stringify(rows));
    }

    await ownerPhone.locator(".vf-q", { hasText: Q4 }).first().tap();
    await until(ownerPhone, t => document.querySelector(".vf-qtext")?.textContent === t, Q4);
    let h = await header(ownerPhone);
    ok("390x844 owner: the arrows stay on the position's row", h.still && sameRow(h.nav, h.pos), JSON.stringify(h));
    ok("  Purpose and Ask someone sit together on one row", h.whoText === "Ask someone" && sameRow(h.sel, h.who), JSON.stringify(h));
    ok(`  each a ${MIN_HIT} px tap target`, h.sel?.h >= MIN_HIT - 0.5 && h.who?.h >= MIN_HIT - 0.5, JSON.stringify([h.sel, h.who]));
    ok("  nothing past the screen and no sideways scroll", !h.past.length && !h.sideways, JSON.stringify(h.past));
    await owner.evaluate(p => window.Core.setFor("Q4", [p]), bartPid);
    await until(ownerPhone, () => document.querySelector(".vf-forbtn")?.textContent === "Change who");
    h = await header(ownerPhone);
    ok(`  asked of ${LONG}: Purpose and Change who still share a row`, h.still && sameRow(h.sel, h.who) && h.who?.h >= MIN_HIT - 0.5, JSON.stringify(h));
    ok("  who it asks shows after them, nothing past the screen", !!h.chip && (h.chip.top >= h.who.bottom - TOL || (sameRow(h.chip, h.who) && h.chip.left >= h.who.right - TOL))
      && !h.past.length && !h.sideways, JSON.stringify(h));

    await owner.locator(".vf-q", { hasText: Q4 }).first().click();
    await until(owner, t => document.querySelector(".vf-qtext")?.textContent === t, Q4);
    h = await header(owner);
    ok("1440x900 owner: the header stays one row, position, Purpose and Change who side by side", h.still && sameRow(h.pos, h.sel) && sameRow(h.sel, h.who), JSON.stringify(h));

    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
    ok("no CSP violation", (await rec.cspViolations()).length === 0);
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
