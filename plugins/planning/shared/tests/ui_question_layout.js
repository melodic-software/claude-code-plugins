#!/usr/bin/env node
// The question screen's one-column layout (layout A), against `share.sh ensure-running` with the fake cloudflared:
// no Answers | Claude tabs or split exist; "Claude on this question" sits below the answers, folded to its head by
// default, and opens by itself for the person whose request Claude just answered (not for someone with nothing new);
// a Claude card reads "<Name> asked", the ask, a 1px line, "Claude", the answer, with ask and answer at one font size,
// and a running request shows its progress line under "Claude"; in a row of option cards with 1- and 2-line labels and
// 0 or 1 picks every "Choose" button's top is equal within 1 px at 1440 and 1024 wide.
//   node plugins/planning/shared/tests/ui_question_layout.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the approved spec (.work spec-question-screen.md: layout A, soft-rule cards, item 12 option
// alignment, 1 px tolerance) and the texts this suite writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs, openClaude } = require("./browser_harness");

const CHOICE = "Which payment method should checkout offer first?", TEXT = "Where should the order summary sit?";
const ASK = "How do the big shops place the order summary?", ANSWER = "Most keep it in a right column on desktop.";
const ASK2 = "And on phones?", LOCKQ = "Which side should the totals sit on?";
const OPTS = [{ id: "opt-1", label: "Card" }, { id: "opt-2", label: "A wallet such as PayPal, Apple Pay or Google Pay, whichever the shopper already has" },
  { id: "opt-3", label: "Bank transfer" }, { id: "opt-4", label: "Pay later in three parts, with no interest for the first month" }];
const q = (id, text, format) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format });

/** The Choose buttons grouped by their card's grid row: the largest spread of button tops within any one row. */
const chooseSpread = page => page.evaluate(() => {
  const rows = new Map();
  for (const li of document.querySelectorAll(".vf-opts > .vf-opt")) {
    const top = Math.round(li.getBoundingClientRect().top), b = li.querySelector(".vf-optchoose").getBoundingClientRect().top;
    if (!rows.has(top)) rows.set(top, []);
    rows.get(top).push(b);
  }
  const multi = [...rows.values()].filter(r => r.length > 1);
  return { rows: multi.length, perRow: multi.map(r => r.length), spread: Math.max(0, ...multi.map(r => Math.max(...r) - Math.min(...r))),
    lines: [...document.querySelectorAll(".vf-opts .vf-optlabel")].map(l => Math.round(l.getBoundingClientRect().height / parseFloat(getComputedStyle(l).lineHeight))),
    feet: [...document.querySelectorAll(".vf-opts .vf-optn")].map(n => n.textContent) };
});

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_question_layout.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_question_layout"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("qlayout");
    s.apply(A.dir, [{ op: "set-title", title: "Question layout checks" }, { op: "open-round", questions: [
      q("Q1", CHOICE, { kind: "choice", options: OPTS }), q("Q2", TEXT, { kind: "text" }), q("Q3", LOCKQ, { kind: "text" })] }]);
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const ann = await rec.open(A.localUrl, { context: { viewport: { width: 1440, height: 900 } } });
    await joinAs(ann, "Ann");
    const bo = await rec.open(A.localUrl, { context: { viewport: { width: 1440, height: 900 } } });
    await joinAs(bo, "Bo");
    const go = async (page, text) => { await page.locator(".vf-q", { hasText: text }).first().click(); return until(page, t => document.querySelector(".vf-qtext")?.textContent === t, text); };

    // ---------- (a) no Answers | Claude tabs or split, at any width ----------
    for (const [w, h] of [[1440, 900], [1024, 768], [390, 844]]) {
      await ann.setViewportSize({ width: w, height: h });
      const n = await ann.evaluate(() => document.querySelectorAll(".vf-splittabs, .vf-split, .vf-thpane, [role=tablist][aria-label='Answers or Claude']").length);
      ok(`${w}x${h}: no Answers | Claude tabs or split exist`, n === 0, n);
    }
    await ann.setViewportSize({ width: 1440, height: 900 });

    // ---------- (c) option cards: every Choose button in a row at one height ----------
    await go(ann, CHOICE);
    await go(bo, CHOICE);
    await bo.locator(".vf-opt", { hasText: "Bank transfer" }).locator(".vf-optchoose").click();
    for (const picked of [false, true]) {
      if (picked) {
        await ann.locator(".vf-opt", { hasText: "Card" }).first().locator(".vf-optchoose").click();
        await until(ann, () => [...document.querySelectorAll(".vf-optn")].some(n => /1 person chose this/.test(n.textContent)));
      }
      for (const [w, h] of [[1440, 900], [1024, 768]]) {
        await ann.setViewportSize({ width: w, height: h });
        await ann.waitForTimeout(150);
        const r = await chooseSpread(ann);
        const mixed = r.lines.some(n => n === 1) && r.lines.some(n => n >= 2);
        ok(`${w} wide, ${picked ? "after picking (0 or 1 picks shown)" : "before picking"}: every Choose button in a row of 1- and 2-line cards has one top (within 1 px)`,
          r.rows >= 1 && mixed && r.spread <= 1, JSON.stringify(r));
        if (picked) ok(`${w} wide: the feet read 1 pick or "No picks yet"`, r.feet.includes("1 person chose this") && r.feet.includes("No picks yet"), JSON.stringify(r.feet));
      }
    }
    await ann.setViewportSize({ width: 390, height: 844 });
    const phone = await ann.evaluate(() => [...document.querySelectorAll(".vf-opts > .vf-opt")].map(li => Math.round(li.getBoundingClientRect().left)));
    ok("390 wide: options stay one per row", new Set(phone).size === 1 && phone.length === OPTS.length + 1, JSON.stringify(phone));
    await ann.setViewportSize({ width: 1440, height: 900 });

    // ---------- (b) the Claude section: folded by default, opens by itself on an unread result ----------
    await go(ann, TEXT);
    await go(bo, TEXT);
    await ann.evaluate(t => window.Core.request("Q2", "ask", t), ASK);
    const state = page => page.evaluate(() => ({ open: document.querySelector(".vf-cltoggle").getAttribute("aria-expanded"), body: !document.querySelector(".vf-clbody").hidden,
      fresh: document.querySelector(".vf-clnew").hidden ? "" : document.querySelector(".vf-clnew").textContent, counts: document.querySelector(".vf-clcounts").textContent }));
    await until(ann, () => /1 waiting/.test(document.querySelector(".vf-clcounts")?.textContent));
    const s1 = await state(ann);
    ok("with a request waiting, the Claude section is folded to its head by default", s1.open === "false" && !s1.body && /1 waiting/.test(s1.counts), JSON.stringify(s1));
    const reqId = await owner.evaluate(async t => {
      for (let i = 0; i < 40 && !(window.Core.state.requests || []).some(r => r.text === t); i++) await new Promise(r => setTimeout(r, 100));
      return (window.Core.state.requests || []).find(r => r.text === t)?.id;
    }, ASK);
    await owner.evaluate(id => window.Core.requestAct(id, "run"), reqId);
    await until(owner, id => window.Core.snapshot().requests.find(r => r.id === id)?.status.kind === "running", reqId);
    s.apply(A.dir, [{ op: "result", qid: "Q2", request: reqId, kind: "ask", summary: ANSWER, sources: [], report: "", used: [{ name: "discovery:research", type: "skill" }], why: "Outside comparison." }]); // asked for everyone: shared when it arrives
    ok("once the host shares Claude's answer to Ann's request, her section opens by itself", await until(ann, () => document.querySelector(".vf-cltoggle").getAttribute("aria-expanded") === "true"
      && !document.querySelector(".vf-clbody").hidden && /1 new/.test(document.querySelector(".vf-clnew").textContent), null, 10000), JSON.stringify(await state(ann)));
    ok("  the answers and the composer still show above it", await ann.evaluate(() => !!document.querySelector(".vf-anspane").offsetParent && !!document.querySelector(".vf-composer").offsetParent
      && document.querySelector(".vf-anspane").getBoundingClientRect().bottom <= document.querySelector(".vf-clsec").getBoundingClientRect().top + 1));
    await until(bo, a => [...document.querySelectorAll(".vf-res")].some(li => li.textContent.includes(a)), ANSWER);
    const s2 = await state(bo);
    ok("Bo, with nothing new for him, keeps it folded", s2.open === "false" && !s2.body, JSON.stringify(s2));
    ok("Bo opens the Claude section", await openClaude(bo));
    const kinds = await bo.evaluate(() => ({ pressed: Object.fromEntries([...document.querySelectorAll(".vf-askform .vf-seg-btn")].map(b => [b.textContent, b.getAttribute("aria-pressed")])),
      label: document.querySelector(".vf-askform .vf-asklabel").textContent }));
    ok("a fresh Ask Claude form starts on Ask: Ask pressed, Research not, the label \"What should Claude answer?\"",
      kinds.pressed.Ask === "true" && kinds.pressed.Research === "false" && kinds.label === "What should Claude answer?", JSON.stringify(kinds));

    // ---------- (d) the soft-rule card ----------
    const card = await ann.evaluate(() => {
      const li = [...document.querySelectorAll(".vf-res")].pop(), askBox = li.querySelector(".vf-qa-ask"), ansBox = li.querySelector(".vf-qa-ans");
      const fs = el => getComputedStyle(el.querySelector(".vf-rich")).fontSize;
      const label = box => [...box.querySelector(".vf-qa-lbl").children].pop().textContent; // the words after the avatar
      return { askLbl: label(askBox), ansLbl: label(ansBox),
        askFs: fs(askBox.querySelector(".vf-cbox")), ansFs: fs(ansBox.querySelector(".vf-cbox")),
        rule: getComputedStyle(askBox).borderBottomWidth, order: askBox.compareDocumentPosition(ansBox) === Node.DOCUMENT_POSITION_FOLLOWING };
    });
    ok("the card reads \"You asked\", the ask, a 1px line, then \"Claude\" and the answer", card.askLbl === "You asked" && card.ansLbl === "Claude" && card.rule === "1px" && card.order, JSON.stringify(card));
    ok("ask and answer text have the same computed font-size", card.askFs === card.ansFs, JSON.stringify(card));
    await ann.evaluate(t => window.Core.request("Q2", "ask", t), ASK2);
    const req2 = await owner.evaluate(async t => {
      for (let i = 0; i < 40 && !(window.Core.state.requests || []).some(r => r.text === t); i++) await new Promise(r => setTimeout(r, 100));
      return (window.Core.state.requests || []).find(r => r.text === t)?.id;
    }, ASK2);
    await owner.evaluate(id => window.Core.requestAct(id, "run"), req2);
    ok("a running request shows its progress line under \"Claude\"", await until(ann, t => {
      const li = [...document.querySelectorAll(".vf-threq")].find(x => x.textContent.includes(t));
      const ans = li?.querySelector(".vf-qa-ans"), line = ans?.querySelector(".vf-runline");
      return !!line && !ans.hidden && line.dataset.run === "true" && /Running/.test(line.textContent) && ans.querySelector(".vf-qa-lbl").textContent === "Claude";
    }, ASK2, 10000));
    ok("  and its counts say 1 answer and 1 running", await until(ann, () => document.querySelector(".vf-clcounts").textContent === "1 answer · 1 running"),
      await ann.evaluate(() => document.querySelector(".vf-clcounts").textContent));
    await ann.locator(".vf-cltoggle").click();
    ok("its head folds it again", await until(ann, () => document.querySelector(".vf-clbody").hidden));
    ok("and opens it again", await openClaude(ann));

    // ---------- the chat button never covers the end of the page ----------
    for (const [w, h] of [[1440, 900], [390, 844]]) {
      await ann.setViewportSize({ width: w, height: h });
      await ann.waitForTimeout(200);
      const hit = await ann.evaluate(() => {
        const sc = document.querySelector(".vf-scroll"); sc.scrollTop = sc.scrollHeight;
        const f = document.querySelector(".vf-fab").getBoundingClientRect();
        return [...document.querySelectorAll(".vf-clsec :is(button, a[href], textarea, input, select)")].filter(e => e.getClientRects().length).map(e => [e, e.getBoundingClientRect()])
          .filter(([, r]) => r.left < f.right && r.right > f.left && r.top < f.bottom && r.bottom > f.top).map(([e]) => e.className || e.textContent);
      });
      ok(`${w}x${h}: scrolled to the bottom, the chat button covers no control in the Claude section`, hit.length === 0, JSON.stringify(hit));
    }
    // ---------- the disabled composer's placeholder fits a phone's one line ----------
    const cy = await rec.open(A.localUrl, { context: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true } });
    await joinAs(cy, "Cy");
    await until(cy, t => document.querySelector(".vf-qtext")?.textContent === t, CHOICE);
    const fit = await cy.evaluate(() => {
      const ta = document.getElementById("vf-answer"), cs = getComputedStyle(ta), cx = document.createElement("canvas").getContext("2d");
      cx.font = `${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`;
      return { text: ta.placeholder, need: Math.ceil(cx.measureText(ta.placeholder).width), room: Math.floor(ta.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight)), disabled: ta.disabled };
    });
    ok("390: the disabled composer's placeholder fits its line", fit.disabled && fit.need <= fit.room, JSON.stringify(fit));

    // ---------- a lock and a last suggestion that go clear on another page without a reload ----------
    await ann.setViewportSize({ width: 1440, height: 900 });
    await go(ann, LOCKQ);
    await ann.evaluate(() => window.Core.answerCiting("Q3", "Put it on the right.", []));
    await until(owner, () => window.Core.snapshot().cards?.Q3?.length > 0);
    await owner.evaluate(() => window.Core.lock("Q3", window.Core.snapshot().cards.Q3[0].ref));
    const lockShown = page => page.evaluate(() => !document.querySelector(".vf-lock").hidden && /Locked/.test(document.querySelector(".vf-lock").textContent));
    ok("the owner locks the question and Ann's page shows Locked", await until(ann, () => !document.querySelector(".vf-lock").hidden && /Locked/.test(document.querySelector(".vf-lock").textContent), null, 10000), String(await lockShown(ann)));
    await owner.evaluate(() => window.Core.unlock("Q3"));
    ok("after the owner unlocks, Ann's page loses the lock block without a reload", await until(ann, () => document.querySelector(".vf-lock").hidden && !window.Core.snapshot().locks?.Q3, null, 10000), String(await lockShown(ann)));
    await owner.evaluate(() => window.Core.lock("Q3", window.Core.snapshot().cards.Q3[0].ref));
    await until(ann, () => !document.querySelector(".vf-lock").hidden, null, 10000);
    await bo.evaluate(() => window.Core.suggest("Q3", "Put it on the left."));
    ok("Bo's only suggestion on the locked question shows on Ann's page", await until(ann, () => document.querySelectorAll(".vf-slist > li").length === 1, null, 10000));
    const sugId = await owner.evaluate(async () => {
      for (let i = 0; i < 40 && !(window.Core.snapshot().suggestions?.Q3 || []).length; i++) await new Promise(r => setTimeout(r, 100));
      return window.Core.snapshot().suggestions.Q3[0]?.id;
    });
    await owner.evaluate(id => window.Core.dismissSuggestion("Q3", id), sugId);
    ok("once the owner dismisses it, Ann's page no longer lists it, without a reload", await until(ann, () => document.querySelectorAll(".vf-slist > li").length === 0 && !(window.Core.snapshot().suggestions?.Q3 || []).some(x => x.status === "open"), null, 10000),
      await ann.evaluate(() => JSON.stringify(window.Core.snapshot().suggestions?.Q3)));

    ok("no page broke the server's CSP",(await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
