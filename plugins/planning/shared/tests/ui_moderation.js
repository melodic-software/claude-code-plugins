#!/usr/bin/env node
// Phase 4c in real browsers, against `share.sh ensure-running` with the fake cloudflared: the session intro ("Why
// you're here") before question 1 and from the header; on a 390x844 phone the first screen still shows the goal, the
// ask, "Start here", "Something else…" and the answer box, with the intro folded behind its toggle; the owner hides an
// answer (gone for another guest, marked for its author, held through the author's new version) and shows it again;
// the owner edits an answer ("Edited by the host" for everyone, earlier versions fetched for the owner only), locks it
// (the lock says it was edited) and cannot hide the locked answer; a hidden multi pick tells its author it is not
// counted; Approve new joins holds a new person, listed in join order with a device hint, until the owner lets them
// in, while a guest already here keeps going; the owner's per-person view lists one person's answers, votes, chat and
// the hidden answer they cleared; chat reactions toggle per person and tell the author. Two browsers and a phone.
//   node plugins/planning/shared/tests/ui_moderation.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from PLAN.md Phase 4c and the texts this suite writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, snap, joinAs } = require("./browser_harness");

const PHONE = { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 };
const GOAL = "Pick the offsite venue";
const INTRO = "Kim is asking the team where the offsite should be. About 5 minutes. Claude reads your answers when a round is sent; the chat is not sent.";
const q = (id, text, format, purpose = "decide") => ({ id, text, alternatives: [], dependsOn: [], purpose, format });

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_moderation.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_moderation"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("moderation");
    s.apply(A.dir, [{ op: "set-title", title: "Offsite" }, { op: "set-goal", goal: GOAL }, { op: "set-intro", intro: INTRO }, { op: "open-round", questions: [
      q("Q1", "Which city should we go to?", { kind: "choice", options: [{ id: "opt-1", label: "Lisbon" }, { id: "opt-2", label: "Berlin" }, { id: "opt-3", label: "Porto" }] }),
      q("Q2", "What should the first evening be?", { kind: "text" }),
      q("Q3", "Which activities?", { kind: "multi", options: [{ id: "opt-1", label: "Hike" }, { id: "opt-2", label: "Cooking class" }] }),
    ] }]);
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const gus = await rec.open(A.localUrl);
    const gusPid = await joinAs(gus, "Gus");

    // ---------- intro before question 1, and from the header ----------
    ok("a new guest sees \"Why you're here\" in the first-view card above question 1", await until(gus, intro => {
      const c = document.querySelector(".vf-orient"), t = document.querySelector(".vf-orient-intro"), qt = document.querySelector(".vf-qtext");
      return !!c && !c.hidden && t?.textContent === intro && !!t.offsetParent && c.getBoundingClientRect().bottom <= qt.getBoundingClientRect().top + 1
        && /Start here: question 1/.test(document.querySelector(".vf-orient-start").textContent);
    }, INTRO));
    await gus.click(".vf-introbtn");
    ok("the header reopens the intro", await until(gus, intro => { const p = document.querySelector(".vf-intropop"); return !!p && !p.hidden && p.textContent.includes(intro); }, INTRO));
    await gus.keyboard.press("Escape");

    // ---------- the phone's first screen ----------
    const pia = await rec.open(A.localUrl, { context: PHONE });
    const piaPid = await joinAs(pia, "Pia");
    const first = await until(pia, () => !document.querySelector(".vf-orient")?.hidden && !!document.querySelector(".vf-opt.vf-opt-other"));
    // The fold is the bottom of the scrolling question pane (the tab bar sits under it).
    const fold = await pia.evaluate(() => {
      const end = document.querySelector(".vf-scroll").getBoundingClientRect().bottom;
      const at = (sel, whole) => { const el = document.querySelector(sel); if (!el || !el.offsetParent) return `${sel} not shown`; const r = el.getBoundingClientRect(); return r.top >= 0 && (whole ? r.bottom : r.top) < end ? "" : `${sel} at ${r.top.toFixed(0)}-${r.bottom.toFixed(0)}, fold ${end.toFixed(0)}`; };
      const card = document.querySelector(".vf-orient").getBoundingClientRect();
      return [...[".vf-orient-goal", ".vf-orient-ask", ".vf-orient-start", ".vf-opt.vf-opt-other"].map(s => at(s, true)), at(".vf-composer", false),
        card.height <= innerHeight * 0.15 ? "" : `the card is ${card.height.toFixed(0)} px tall`].filter(Boolean);
    });
    ok("phone 390x844: the card takes at most 15% of the screen; the goal, the ask, Start here and Something else… show whole, and the answer box starts above the fold",
      first && fold.length === 0, fold.join("; "));
    ok("phone: the intro folds behind its toggle", await until(pia, () => document.querySelector(".vf-orient-why").hidden && !document.querySelector(".vf-orient-whybtn").hidden
      && document.querySelector(".vf-orient-whybtn").getAttribute("aria-expanded") === "false"));
    await pia.locator(".vf-orient-whybtn").tap();
    ok("phone: the toggle shows the intro", await until(pia, intro => !document.querySelector(".vf-orient-why").hidden && document.querySelector(".vf-orient-intro").textContent === intro, INTRO));
    await pia.locator(".vf-orient-whybtn").tap();
    ok("phone: the toggle folds it again", await until(pia, () => document.querySelector(".vf-orient-why").hidden));

    // ---------- hide an answer ----------
    await gus.evaluate(() => window.Core.answerCiting("Q2", "A pub crawl, rude words here", []));
    await owner.locator(".vf-q", { hasText: "What should the first evening" }).first().click();
    await gus.locator(".vf-q", { hasText: "What should the first evening" }).first().click();
    const hideBtn = owner.locator(".vf-card .vf-mod-hide:not([hidden])").first();
    ok("the owner gets Hide on a guest's answer", await hideBtn.waitFor({ timeout: 8000 }).then(() => true).catch(() => false));
    await hideBtn.click();
    const ref = `p:${gusPid}`;
    ok("a hidden answer leaves another guest's view", await until(pia, r => !(window.Core.snapshot().cards.Q2 || []).some(c => c.ref === r)
      && !JSON.stringify(window.Core.snapshot()).includes("rude words"), ref));
    ok("its author sees \"Hidden by the host\" on it, with no promise that sending it again shows it", await until(gus, () => [...document.querySelectorAll(".vf-modnote")]
      .some(n => !n.hidden && n.textContent.startsWith("Hidden by the host") && !/send it again/i.test(n.textContent))));
    ok("the owner still sees it, marked", await until(owner, () => !!document.querySelector(".vf-card.vf-hiddencard") && /Show/.test(document.querySelector(".vf-card.vf-hiddencard .vf-mod-hide").textContent)));
    await gus.evaluate(() => window.Core.answerCiting("Q2", "A pub crawl, more rude words", []));
    ok("a new version from its author stays hidden", await until(gus, () => (window.Core.snapshot().cards.Q2 || []).some(c => c.text === "A pub crawl, more rude words" && c.hidden)));
    ok("while it is hidden, Pia's page shows none of its text", await pia.evaluate(() => !document.body.innerText.includes("rude words")
      && !JSON.stringify(window.Core.snapshot()).includes("rude words")));
    await owner.locator(".vf-card.vf-hiddencard .vf-mod-hide").click();
    ok("Show puts it back for everyone", await until(pia, r => (window.Core.snapshot().cards.Q2 || []).some(c => c.ref === r), ref));

    // ---------- edit an answer, history for the owner only ----------
    await owner.locator(".vf-card .vf-mod-edit:not([hidden])").first().click();
    ok("Edit opens the answer's text", await until(owner, () => { const p = document.querySelector(".vf-editpop"); return !p.hidden && document.querySelector(".vf-edit-ta").value === "A pub crawl, more rude words"; }));
    await owner.fill(".vf-edit-ta", "A pub crawl");
    await owner.click(".vf-editpop .vf-btn-primary");
    ok("everyone sees the new text marked \"Edited by the host\"", await until(pia, () => {
      const c = (window.Core.snapshot().cards.Q2 || []).find(x => x.kind === "person");
      return c?.text === "A pub crawl" && !!c.edited;
    }) && await until(gus, () => [...document.querySelectorAll(".vf-modnote")].some(n => !n.hidden && n.textContent === "Edited by the host")));
    ok("no guest's snapshot carries the earlier versions", await pia.evaluate(() => !JSON.stringify(window.Core.snapshot()).includes("\"history\""))
      && await gus.evaluate(() => !JSON.stringify(window.Core.snapshot()).includes("\"history\"")));
    await owner.locator(".vf-card .vf-mod-edit:not([hidden])").first().click();
    ok("the owner sees the earlier versions, with who wrote them, fetched when the list opens", await until(owner, () => {
      const items = [...document.querySelectorAll(".vf-editpop .vf-hist")];
      return items.length === 2 && items[0].textContent.includes("A pub crawl, rude words here") && items[1].textContent.includes("A pub crawl, more rude words")
        && items.every(i => i.textContent.includes("Gus"));
    }));
    await owner.keyboard.press("Escape");

    // ---------- lock the edited answer: the lock says the host edited it ----------
    await owner.evaluate(r => window.Core.lock("Q2", r), ref);
    ok("the lock banner says the host edited the locked answer", await until(gus, () => [...document.querySelectorAll(".vf-lock-from")].some(n => /edited by the host/.test(n.textContent))));
    ok("Hide is refused on the locked answer, with a reason", await owner.evaluate(r => window.Core.hideCard("Q2", r, true).then(() => "", e => e.message || ""), ref)
      .then(m => /Unlock/.test(m)));
    await owner.evaluate(() => window.Core.unlock("Q2"));

    // ---------- a hidden multi pick: its author is told it is not counted ----------
    await gus.evaluate(() => window.Core.pickWith("Q3", { options: ["opt-1"] }, { comment: "Hike, please" }));
    await owner.evaluate(r => window.Core.hideCard("Q3", r, true), ref);
    await gus.locator(".vf-q", { hasText: "Which activities?" }).first().click();
    ok("its author reads that a hidden pick is not counted", await until(gus, () => [...document.querySelectorAll(".vf-modnote")]
      .some(n => !n.hidden && /not counted while it is hidden/.test(n.textContent))));
    await gus.evaluate(() => window.Core.pickWith("Q3", { options: [] }, { comment: "" })); // he clears it: the owner keeps a tombstone
    await gus.locator(".vf-q", { hasText: "What should the first evening" }).first().click();

    // ---------- chat reactions ----------
    await gus.evaluate(() => window.Core.chat("Lunch at noon?"));
    await pia.evaluate(() => { document.querySelector(".vf-fab").click(); });
    await until(pia, () => [...document.querySelectorAll(".vf-mlist .vf-msg")].some(m => m.textContent.includes("Lunch at noon?")));
    await pia.locator(".vf-msg", { hasText: "Lunch at noon?" }).locator(".vf-mreact-add").tap();
    ok("+ opens the quick row of six", await until(pia, () => { const p = document.querySelector(".vf-reactpop"); return !p.hidden && [...p.querySelectorAll(".vf-rp-quick .vf-rp-e")].map(b => b.textContent).join("") === "👍👎😂❤️🎉😮"; }));
    await pia.locator(".vf-rp-more").tap();
    ok("More opens the larger set", await until(pia, () => { const g = document.querySelector(".vf-rp-grid"); return !g.hidden && g.querySelectorAll(".vf-rp-e").length >= 74; }));
    await pia.locator(".vf-rp-quick .vf-rp-e", { hasText: "🎉" }).tap();
    await gus.evaluate(() => { if (document.querySelector(".vf-chat").hidden) document.querySelector(".vf-fab").click(); });
    ok("the author sees 🎉 1 from Pia", await until(gus, () => { const c = document.querySelector(".vf-msg .vf-mreact"); return !!c && c.textContent === "🎉1" && /Pia/.test(c.title); }));
    ok("the author is told, as a reaction notification", await until(gus, () => (window.Core.snapshot().me.notifications || []).some(n => n.kind === "reaction" && n.title === "1 reaction on your chat message.")));
    await pia.locator(".vf-msg", { hasText: "Lunch at noon?" }).locator(".vf-mreact").tap();
    ok("tapping her own chip takes Pia's reaction back", await until(gus, () => !document.querySelector(".vf-msg .vf-mreact")));

    // ---------- the owner's per-person view ----------
    await owner.locator(".vf-seg-btn", { hasText: /^Host$/ }).click();
    await owner.locator(".vf-hperson", { hasText: "Gus" }).locator(".vf-hp-view").click();
    ok("View all lists Gus's answer with Hide and Edit, and his chat line", await until(owner, () => {
      const p = document.querySelector(".vf-personpop");
      if (!p || p.hidden) return false;
      const items = [...p.querySelectorAll(".vf-ppv-item")].map(i => i.textContent);
      return items.some(t => t.includes("Q2") && t.includes("A pub crawl") && t.includes("Hide") && t.includes("Edit")) && items.some(t => t.includes("Lunch at noon?"))
        && /Remove Gus/.test(p.textContent);
    }));
    const clearedRow = owner.locator(".vf-personpop .vf-ppv-item", { hasText: "Q3, cleared" });
    ok("View all lists the hidden answer Gus cleared, marked hidden", await clearedRow.waitFor({ timeout: 8000 }).then(() => clearedRow.textContent()).then(t => /\(hidden\)/.test(t), () => false));
    await clearedRow.getByRole("button", { name: /Show what Gus's cleared answer on Q3 said/ }).click();
    ok("Show what it said fetches its last text for the owner", await until(owner, () => [...document.querySelectorAll(".vf-personpop .vf-ppv-item")]
      .some(i => i.textContent.includes("Q3, cleared") && i.querySelector(".vf-ppv-t").textContent === "Hike, please")));
    await owner.keyboard.press("Escape");

    // ---------- approve new joins ----------
    await owner.click(".vf-gear");
    await owner.locator(".vf-settings .vf-sw-row", { hasText: "Approve new joins" }).click();
    ok("the owner turns on Approve new joins", await until(owner, () => window.Core.snapshot().settings.approveJoins === true));
    await owner.keyboard.press("Escape");
    const jib = await rec.open(A.localUrl);
    await jib.waitForSelector("dialog.core-name[open]");
    await jib.fill("#core-n", "Jib");
    await jib.click("dialog.core-name button");
    ok("a new person waits, and is told so", await until(jib, () => !document.querySelector("dialog.core-name") && window.Core.state.youWaiting === true
      && document.querySelector(".vf-ev-title")?.textContent === "Waiting for the host to let you in"));
    ok("a waiting person reads nothing of the session", await jib.evaluate(() => window.Core.state.questions.length === 0 && !window.Core.snapshot()));
    const gus2 = await rec.openIn(gus.context(), A.localUrl); // a new tab: the stored secret, no join
    ok("a guest already here keeps going in a new tab", await until(gus2, pid => window.Core.snapshot()?.me?.pid === pid && window.Core.state.questions.length === 3, gusPid));
    ok("the owner's queue says \"Wants to join: Jib\", first in line, on a computer in Chrome", await until(owner, () => [...document.querySelectorAll(".vf-qitem")]
      .some(i => i.textContent.includes("Wants to join: Jib (1st waiting; computer · Chrome)"))));
    await owner.locator(".vf-qitem", { hasText: "Wants to join: Jib" }).getByRole("button", { name: "Let in" }).click();
    ok("once let in, the page opens by itself", await until(jib, () => window.Core.snapshot()?.me?.name === "Jib" && window.Core.state.questions.length === 3, null, 10000));

    ok("after the host's edit, Pia's page holds none of Gus's earlier text", piaPid && await pia.evaluate(() => !document.body.innerText.includes("rude words")
      && !JSON.stringify(window.Core.snapshot()).includes("rude words")));
    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    ok("no page error", rec.errors.filter(m => !/Failed to load resource/.test(m)).length === 0, rec.errors.slice(0, 3).join(" | "));
    ok("no request was answered 429 (slow down)", rec.too.length === 0, rec.too.slice(0, 5).join(", "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
