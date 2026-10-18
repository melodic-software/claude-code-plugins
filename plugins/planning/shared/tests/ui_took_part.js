#!/usr/bin/env node
// Taking part, Pass, `for` and catch-up in a real browser, against `share.sh ensure-running` with the fake cloudflared.
// Triage row 42: a guest who only gave someone's answer a 👍, or only voted for it, sees the question as Took part, not
// Not answered, and the Host view's behind count says the same; once one other person answered, an untargeted question
// goes optional ("<name> answered. 👍 if you agree, or Pass") and no count includes it; Pass works on every purpose,
// with undo, and a Pass on a poll shows no results; a question asked of a person (`for`) stays open for them after a
// reaction, and their Pass needs a reason; the owner sets `for` from the question. Triage row 43: a late joiner lands on
// the current round and the welcome card and the rail say what an earlier closed round still wants, with a link to it.
//   node plugins/planning/shared/tests/ui_took_part.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values (states, sentences, counts) come from triage rows 42 and 43, never from the page itself.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const text = (id, t, purpose, extra = {}) => ({ id, text: t, alternatives: [], dependsOn: [], purpose, format: { kind: "text" }, ...extra });
const poll = (id, t) => ({ id, text: t, alternatives: [], dependsOn: [], purpose: "poll", format: { kind: "choice", options: [{ id: "opt-1", label: "Card" }, { id: "opt-2", label: "Wallet" }] } });
const T = { g: "What worries you about the new checkout?", d: "Which step should come first?", p: "Which payment method by default?", f: "What does finance need from refunds?" };

/** In the page: each rail question's text, data-stat and aria-label. */
const rail = () => [...document.querySelectorAll(".vf-q")].map(b => ({ t: b.querySelector(".vf-qtxt")?.textContent, stat: b.dataset.stat, label: b.getAttribute("aria-label") }));
const statOf = (page, t) => page.evaluate(t2 => [...document.querySelectorAll(".vf-q")].find(b => b.querySelector(".vf-qtxt")?.textContent === t2)?.dataset.stat ?? null, t);

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_took_part.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_took_part"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("took-part");
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const bo = await rec.open(A.localUrl), cy = await rec.open(A.localUrl);
    const boPid = await joinAs(bo, "Bo"), cyPid = await joinAs(cy, "Cy");
    s.apply(A.dir, [{ op: "open-round", questions: [text("Q1", T.g, "gather"), text("Q2", T.d, "decide"), poll("Q3", T.p), text("Q4", T.f, "gather", { for: ["Cy"] })] }]);
    for (const p of [owner, bo, cy]) await until(p, () => document.querySelectorAll(".vf-q").length === 4, null, 10000);

    // ---------- Q8: a 👍 or a vote alone is taking part ----------
    const say = async (page, t, answer) => {
      await page.locator(".vf-q", { hasText: t }).first().click();
      await page.fill("#vf-answer", answer);
      await page.press("#vf-answer", "Control+Enter");
    };
    await say(owner, T.g, "Losing the saved card.");
    await owner.waitForTimeout(1100);
    await say(owner, T.d, "Address first.");
    await bo.locator(".vf-q", { hasText: T.g }).first().click();
    await until(bo, () => !!document.querySelector('.vf-alist .vf-react[data-r="thumbs"]'), null, 10000);
    await bo.locator(".vf-alist .vf-card", { hasText: "Losing the saved card" }).locator('.vf-react[data-r="thumbs"]').click();
    ok("Q8: Bo, who only gave the owner's answer a 👍, sees it as Took part", await until(bo, t => {
      const b = [...document.querySelectorAll(".vf-q")].find(x => x.querySelector(".vf-qtxt")?.textContent === t);
      return b?.dataset.stat === "took" && /You took part\./.test(b.getAttribute("aria-label"));
    }, T.g, 10000), JSON.stringify(await bo.evaluate(rail)));
    await bo.locator(".vf-q", { hasText: T.d }).first().click();
    await until(bo, () => [...document.querySelectorAll(".vf-alist .vf-card")].some(c => /Address first/.test(c.textContent) && c.querySelector(".vf-vote")), null, 10000);
    await bo.locator(".vf-alist .vf-card", { hasText: "Address first" }).locator(".vf-vote").first().click();
    ok("  and the decide question he only voted on is Took part too", await until(bo, t => [...document.querySelectorAll(".vf-q")].find(x => x.querySelector(".vf-qtxt")?.textContent === t)?.dataset.stat === "took", T.d, 10000),
      JSON.stringify(await bo.evaluate(rail)));
    // Bo still owes the poll and Q4, which no one has answered yet: 2 open, and the two he took part in are not counted.
    ok("  the Questions count says 2 not answered yet", await until(bo, () => [...document.querySelectorAll("[aria-label]")].some(e => e.getAttribute("aria-label") === "Questions, 2 not answered yet"), null, 10000),
      await bo.evaluate(() => [...document.querySelectorAll("[aria-label^='Questions']")].map(e => e.getAttribute("aria-label")).join(" | ")));
    ok("  his rail shows 2 open", (await bo.evaluate(() => [...document.querySelectorAll(".vf-q")].filter(b => !b.dataset.stat).length)) === 2, JSON.stringify(await bo.evaluate(rail)));
    ok("  and the Host view's behind count for Bo is 2 as well", await until(owner, pid => window.Core.snapshot()?.behind?.[pid] === 2, boPid, 10000),
      JSON.stringify(await owner.evaluate(() => window.Core.snapshot()?.behind)));

    // ---------- the soft nudge ----------
    await cy.locator(".vf-q", { hasText: T.g }).first().click();
    ok("Cy, who has not acted on Q1 that the owner answered, sees it optional with the nudge", await until(cy, t => {
      const b = [...document.querySelectorAll(".vf-q")].find(x => x.querySelector(".vf-qtxt")?.textContent === t);
      return b?.dataset.stat === "soft" && /answered\. 👍 if you agree, or Pass\./.test(document.querySelector(".vf-passnote")?.textContent || "");
    }, T.g, 10000), await cy.evaluate(() => document.querySelector(".vf-passnote")?.textContent));
    ok("  and Pass is a quiet ghost button, not the primary action", await cy.evaluate(() => {
      const b = document.querySelector(".vf-passbtn");
      return !!b && b.offsetParent !== null && b.classList.contains("vf-btn-ghost") && !b.classList.contains("vf-btn-primary");
    }));

    // ---------- Pass on every purpose, with undo ----------
    const pass = async (page, t, reason) => {
      await page.locator(".vf-q", { hasText: t }).first().click();
      await page.locator(".vf-passbtn").click();
      if (reason) await page.fill("#vf-pass-reason", reason);
      await page.locator(".vf-passform button[type=submit]").click();
    };
    await pass(cy, T.g, "");
    ok("Gather: Cy's Pass makes Q1 Took part", await until(cy, t => [...document.querySelectorAll(".vf-q")].find(x => x.querySelector(".vf-qtxt")?.textContent === t)?.dataset.stat === "took", T.g, 10000));
    await cy.locator(".vf-passundo").click();
    ok("  Undo pass takes it back: optional again", await until(cy, t => [...document.querySelectorAll(".vf-q")].find(x => x.querySelector(".vf-qtxt")?.textContent === t)?.dataset.stat === "soft", T.g, 10000));
    await cy.waitForTimeout(1100);
    await pass(cy, T.d, "Not my area");
    ok("Decide: a Pass with a reason is Took part, and the page says so", await until(cy, ([t]) => [...document.querySelectorAll(".vf-q")].find(x => x.querySelector(".vf-qtxt")?.textContent === t)?.dataset.stat === "took"
      && /You passed: Not my area/.test(document.querySelector(".vf-passnote")?.textContent || ""), [T.d], 10000));
    await owner.locator(".vf-q", { hasText: T.d }).first().click();
    ok("  and the owner sees who passed and why", await until(owner, () => document.querySelector(".vf-passwho")?.textContent === "Passed: Cy (Not my area)", null, 10000),
      await owner.evaluate(() => document.querySelector(".vf-passwho")?.textContent));
    await bo.locator(".vf-q", { hasText: T.p }).first().click();
    await bo.locator(".vf-opt", { hasText: "Card" }).locator(".vf-optchoose").click();
    await until(owner, () => (window.Core.snapshot()?.cards?.Q3 || []).some(c => c.ref === "o:opt-1" && c.votes.length === 1), null, 10000);
    await cy.waitForTimeout(1100);
    await pass(cy, T.p, "");
    ok("Poll: a Pass is Took part", await until(cy, t => [...document.querySelectorAll(".vf-q")].find(x => x.querySelector(".vf-qtxt")?.textContent === t)?.dataset.stat === "took", T.p, 10000));
    ok("  and shows no results: no option counts Bo's pick", await cy.evaluate(() => [...document.querySelectorAll(".vf-opt")].filter(li => !/Something else|own/.test(li.textContent)).every(li => !li.querySelector(".vf-optn")?.textContent)),
      await cy.evaluate(() => [...document.querySelectorAll(".vf-optn")].map(n => n.textContent).join(" | ")));

    // ---------- `for`: asked of Cy ----------
    await bo.locator(".vf-q", { hasText: T.f }).first().click();
    await bo.fill("#vf-answer", "The refund reason.");
    await bo.press("#vf-answer", "Control+Enter");
    await cy.locator(".vf-q", { hasText: T.f }).first().click();
    ok("Q4 shows Cy it is asked of you", await until(cy, () => /Asked of you/.test(document.querySelector(".vf-forchip")?.textContent || "") && /asked of you/.test(document.querySelector(".vf-passnote")?.textContent || ""), null, 10000));
    await until(cy, () => [...document.querySelectorAll(".vf-alist .vf-card")].some(c => /The refund reason/.test(c.textContent) && c.querySelector(".vf-react")), null, 10000);
    await cy.locator(".vf-alist .vf-card", { hasText: "The refund reason" }).locator('.vf-react[data-r="heart"]').click();
    await until(cy, () => document.querySelector('.vf-react[data-r="heart"][aria-pressed="true"]'), null, 10000);
    await cy.waitForTimeout(400);
    ok("  a ❤️ alone leaves it open for Cy, never optional", (await statOf(cy, T.f)) === "", await statOf(cy, T.f));
    await cy.locator(".vf-passbtn").click();
    await cy.locator(".vf-passform button[type=submit]").click();
    ok("  her Pass needs a reason: an empty one is refused on the page", await until(cy, () => /asked of you: say why you pass/.test(document.querySelector(".vf-passerr")?.textContent || "")));
    await cy.fill("#vf-pass-reason", "Levi owns refunds");
    await cy.locator(".vf-passform button[type=submit]").click();
    ok("  with one it is Took part", await until(cy, t => [...document.querySelectorAll(".vf-q")].find(x => x.querySelector(".vf-qtxt")?.textContent === t)?.dataset.stat === "took", T.f, 10000));

    // the owner asks Bo for Q2 from the question, as the purpose is set
    await owner.locator(".vf-q", { hasText: T.d }).first().click();
    await owner.locator(".vf-forbtn").click();
    await owner.locator(".vf-forlist label", { hasText: "Bo" }).locator("input").check();
    ok("the owner asks Bo for Q2: the server records it", await until(owner, pid => (window.Core.snapshot()?.questions || []).find(q => q.id === "Q2")?.for?.join() === pid, boPid, 10000));
    await bo.locator(".vf-q", { hasText: T.d }).first().click();
    ok("  and Bo sees it is asked of him", await until(bo, () => document.querySelector(".vf-forchip")?.textContent === "Asked of you", null, 10000),
      await bo.evaluate(() => document.querySelector(".vf-forchip")?.textContent));

    // ---------- catch-up (row 43): Maude joins after round 1 closed ----------
    await owner.evaluate(() => window.Core.sendRound());
    s.apply(A.dir, [{ op: "ack-round", round: 1 }]);
    s.apply(A.dir, [{ op: "open-round", questions: [text("Q5", "Which receipt do we email?", "decide")] }]);
    const maude = await rec.open(A.localUrl);
    await joinAs(maude, "Maude");
    await until(maude, () => document.querySelectorAll(".vf-q").length >= 5, null, 10000);
    ok("Maude lands on the current round (Q100)", await until(maude, () => document.querySelector(".vf-qtext")?.textContent === "Which receipt do we email?", null, 10000),
      await maude.evaluate(() => document.querySelector(".vf-qtext")?.textContent));
    const line = "Round 1 has 4 questions you haven't answered. Answers there still go to Claude, marked late.";
    ok("  the welcome card says what round 1 still wants", await until(maude, l => {
      const c = document.querySelector(".vf-orient .vf-catchup");
      return c && !c.hidden && c.textContent === `${l} Catch up on round 1`;
    }, line, 10000), await maude.evaluate(() => document.querySelector(".vf-orient .vf-catchup")?.textContent));
    ok("  and so does the line above the current round in the rail", await maude.evaluate(l => {
      const c = document.querySelector(".vf-round-cur > .vf-catchup");
      return !!c && !c.hidden && c.textContent.startsWith(l);
    }, line));
    await maude.locator(".vf-orient .vf-catchup-go").click();
    ok("  Catch up on round 1 opens round 1's first open question", await until(maude, t => document.querySelector(".vf-qtext")?.textContent === t, T.g, 10000),
      await maude.evaluate(() => document.querySelector(".vf-qtext")?.textContent));

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
