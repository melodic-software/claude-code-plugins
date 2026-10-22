#!/usr/bin/env node
// A late Disagree on a locked decision, in real browsers against `share.sh ensure-running` with the fake cloudflared:
// once the round closed, a guest may still Disagree with the locked answer; the owner's Inbox then holds a "Possibly
// reopened" row with Keep decision and Unlock; the question that depends on it reads "Needs review: Q1 may be
// reopened" for everyone; the owner alone reads the decision history (folded under the question, and the session's
// Decisions); Keep decision clears the row and the badge, and a newer late Disagree brings the row back.
//   node plugins/planning/shared/tests/ui_reopen.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the owner's decisions (late Disagree only on a lock; the owner's row with Keep decision
// and Unlock; "Needs review: <Q> may be reopened" for everyone; history for the owner only) and the texts this suite
// writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const Q1T = "Where should the offsite be?", Q2T = "Which hotel near the venue?", Q3T = "Which week works?";
const q1 = { id: "Q1", text: Q1T, recommendation: "Lisbon", alternatives: [{ key: "a", text: "Porto" }, { key: "b", text: "Madrid" }], dependsOn: [], purpose: "decide", format: { kind: "text" } };
const q = (id, text, dependsOn = []) => ({ id, text, alternatives: [], dependsOn, purpose: "decide", format: { kind: "text" } });
const REASON = "Too far for half the team", BADGE = "Needs review: Q1 may be reopened";
/** Open a question from the rail, opening its round's list first when it is folded (an earlier round). */
async function goQ(page, text) {
  const item = page.locator(".vf-q", { hasText: text }).first();
  if (!(await item.isVisible())) await page.locator(".vf-round", { has: item }).locator(".vf-rtoggle").click();
  await item.click();
  return until(page, t => document.querySelector(".vf-qtext")?.textContent === t, text);
}
const openInbox = async page => { if (await page.evaluate(() => document.querySelector(".vf-inboxpage").hidden)) await page.click(".vf-bell"); return until(page, () => !document.querySelector(".vf-inboxpage").hidden); };
const reopenRow = () => [...document.querySelectorAll(".vf-inboxpage .vf-qitem")].find(li => li.dataset.t === "reopen" && !li.closest("[hidden]"));

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_reopen.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_reopen"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("reopen");
    s.apply(A.dir, [{ op: "set-title", title: "Offsite" }, { op: "open-round", questions: [q1, q("Q2", Q2T, ["Q1"])] }]);
    const desk = { context: { viewport: { width: 1440, height: 900 } } };
    const owner = await rec.open(A.ownerUrl, desk);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const ann = await rec.open(A.localUrl, desk);
    await joinAs(ann, "Ann");
    await owner.evaluate(() => window.Core.lock("Q1", "c:rec"));
    await owner.evaluate(() => window.Core.sendRound());
    s.apply(A.dir, [{ op: "ack-round", round: 1 }, { op: "open-round", questions: [q("Q3", Q3T)] }]);
    await until(ann, () => (window.Core.snapshot()?.questions || []).some(x => x.id === "Q3"));

    // ---------- the guest disagrees late with the locked answer ----------
    await goQ(ann, Q1T);
    const disBtn = ann.locator(".vf-disagree-btn:visible").first();
    ok("on the closed round's locked question the guest is offered Disagree", await until(ann, () => [...document.querySelectorAll(".vf-disagree-btn")].some(b => !!b.offsetParent)));
    await disBtn.click();
    await ann.locator(".vf-dis-in:visible").first().fill(REASON);
    await ann.locator(".vf-dis-send:visible").first().click();
    ok("  and the disagreement is kept", await until(owner, r => (window.Core.snapshot().disagreements.Q1 || []).some(d => d.reason === r), REASON),
      await owner.evaluate(() => JSON.stringify(window.Core.snapshot().disagreements)));

    // ---------- the owner's Inbox row ----------
    await openInbox(owner);
    ok("the owner's Inbox shows a Possibly reopened row on Q1", await until(owner, reopenRow), await owner.evaluate(() => document.querySelector(".vf-inboxpage")?.textContent.slice(0, 300)));
    const rowText = await owner.evaluate(() => [...document.querySelectorAll(".vf-inboxpage .vf-qitem")].find(li => li.dataset.t === "reopen")?.textContent || "");
    ok("  naming the locked answer and Ann's reason", rowText.includes("Lisbon") && rowText.includes(REASON), rowText);
    const buttons = await owner.evaluate(() => [...document.querySelectorAll(".vf-inboxpage .vf-qitem[data-t=reopen] .vf-acts button")].map(b => b.textContent));
    ok("  with Keep decision and Unlock", buttons.includes("Keep decision") && buttons.includes("Unlock"), buttons.join(","));

    // ---------- the guest: the dependent's badge, no row, no history ----------
    await goQ(ann, Q2T);
    ok("the guest's Q2 reads \"Needs review: Q1 may be reopened\"", await until(ann, b => { const r = document.querySelector(".vf-reviewrow"); return !!r?.offsetParent && r.textContent.includes(b); }, BADGE),
      await ann.evaluate(() => document.querySelector(".vf-reviewrow")?.textContent));
    ok("  and the guest has no Possibly reopened row", await ann.evaluate(() => !(window.Core.state.inbox || []).some(i => i.kind === "reopen")));
    ok("  and no decision history: no log, no History under Q1", await ann.evaluate(() => !("decisions" in window.Core.snapshot()) && window.Core.state.decisions.length === 0));
    await goQ(ann, Q1T);
    ok("  and no History fold under the locked question", await until(ann, () => document.querySelector(".vf-qtext")?.textContent.includes("offsite") && !!document.querySelector(".vf-qhist")?.hidden));
    ok("  and no Decisions entry in Help or More", await ann.evaluate(() => { const b = [...document.querySelectorAll(".vf-help-decisions, .vf-ms-decisions")]; return b.length > 0 && b.every(x => x.hidden); }));

    // ---------- the owner's history ----------
    await owner.click(".vf-ibback");
    await until(owner, () => document.querySelector(".vf-inboxpage").hidden);
    await goQ(owner, Q1T);
    ok("the owner's Q1 has a folded History", await until(owner, () => { const d = document.querySelector(".vf-qhist"); return !!d?.offsetParent && !d.open; }));
    await owner.click(".vf-qhist-sum");
    const hist = await owner.evaluate(() => [...document.querySelectorAll(".vf-qhist .vf-hist")].map(li => li.textContent));
    ok("  listing the lock, then Ann's late Disagree, each with who and when", hist.length === 2 && /The host/.test(hist[0]) && /Locked: Lisbon/.test(hist[0]) && /Ann/.test(hist[1]) && hist[1].includes(REASON)
      && hist.every(t => /, (just now|\d+ (min|h|d) ago)/.test(t)), hist.join(" | "));
    await owner.evaluate(() => document.querySelector(".vf-help-decisions").click());
    const dec = await owner.evaluate(() => [...document.querySelectorAll(".vf-decpop .vf-hist")].map(li => li.textContent));
    ok("the owner's Decisions timeline lists the same, by question", dec.length === 2 && dec.every(t => t.startsWith("Q1 · ")), dec.join(" | "));
    await owner.keyboard.press("Escape");

    // ---------- Keep decision, then a newer late Disagree ----------
    await openInbox(owner);
    await owner.locator(".vf-inboxpage .vf-qitem[data-t=reopen]").getByRole("button", { name: "Keep decision" }).click();
    ok("Keep decision clears the row", await until(owner, () => !document.querySelector(".vf-inboxpage .vf-qitem[data-t=reopen]")));
    await goQ(ann, Q2T);
    ok("  and the guest's Q2 badge", await until(ann, () => !document.querySelector(".vf-reviewrow")?.offsetParent));
    await ann.evaluate(() => window.Core.disagree("Q1", "c:rec", "Still too far"));
    ok("a newer late Disagree brings the row back", await until(owner, reopenRow));
    await owner.locator(".vf-inboxpage .vf-qitem[data-t=reopen]").getByRole("button", { name: "Unlock" }).click();
    ok("Unlock unlocks Q1 and the row goes", await until(owner, () => !window.Core.lockOf("Q1") && !document.querySelector(".vf-inboxpage .vf-qitem[data-t=reopen]")));
    ok("  and the guest's Q2 reads that Q1 changed", await until(ann, () => document.querySelector(".vf-reviewrow")?.textContent.includes("Needs review: Q1 changed")),
      await ann.evaluate(() => document.querySelector(".vf-reviewrow")?.textContent));

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
