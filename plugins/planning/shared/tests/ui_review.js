#!/usr/bin/env node
// Sharing Claude's answers (owner decision 2026-10-19) and the host's review view (follow-up item 13), against
// `share.sh ensure-running` with the fake cloudflared. The Ask boxes offer Everyone and Just me: Everyone on a question,
// Just me about the whole session. An answer asked for everyone shows to everyone when it arrives; a Just me answer
// shows only to its asker, who can share it. The host's Inbox page lists the requests that need the host newest first under
// Needs you (to run, to share, failed and not yet opened) and the rest under History, each tab behind status chips the
// device remembers, with Run, Run again, Share and Take down on the rows, and a failed row says why. Take down hides a
// shared answer from everyone else.
//   node plugins/planning/shared/tests/ui_review.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the approved spec (the owner decision and item 13) and the texts this suite writes.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs, openClaude } = require("./browser_harness");

const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });
const ASK1 = "Ann asks on Q1 for everyone", ASK2 = "Ann asks just for herself", ASK3 = "Bo asks something that fails";
const ANS1 = "Everyone reads this answer.", ANS2 = "Only Ann reads this answer.", WHY = "No sources found.";
const CHAT_ASK = "@Claude where do we stand overall?", CHAT_ANS = "We stand halfway, with the copy open.";
const DISC_ASK = "@Claude is the first payment common?", DISC_ANS = "Cards come first almost everywhere.";
const openChat = async page => { if (await page.evaluate(() => document.querySelector(".vf-chat").hidden)) await page.click(".vf-fab"); return until(page, () => !document.querySelector(".vf-chat").hidden); };

const openInbox = async page => { if (await page.evaluate(() => document.querySelector(".vf-inboxpage").hidden)) await page.click(".vf-bell"); return until(page, () => !document.querySelector(".vf-inboxpage").hidden); };
/** The Inbox page on one tab: needs (Needs you) or history (History). */
const showTab = async (page, k) => { await openInbox(page); await page.click(`.vf-ixtabs [data-k=${k}]`); return until(page, x => document.querySelector(`.vf-ixtabs [data-k=${x}]`)?.getAttribute("aria-pressed") === "true", k); };
const ROWS = ".vf-ibtab:not([hidden]) .vf-revlist > li";
/** The Ask boxes' Everyone / Just me group: which one is pressed, or "" while it is hidden. */
const audIn = (page, sel) => page.evaluate(s => { const g = document.querySelector(s); return g && !g.closest("[hidden]") && g.getClientRects().length ? g.querySelector("[aria-pressed=true]")?.textContent || "" : ""; }, sel);
/** The review rows shown, top to bottom: their text and status chip. */
const rows = page => page.evaluate(r => [...document.querySelectorAll(r)].map(li => ({ text: li.textContent, stat: li.querySelector(".vf-revstat")?.textContent || "" })), ROWS);
const chips = page => page.evaluate(() => Object.fromEntries([...document.querySelectorAll(".vf-ibchips .vf-rev-chip")].map(b => [b.textContent.split(" · ")[0], b.getAttribute("aria-pressed") === "true"])));
const row = (page, text) => page.locator(ROWS, { hasText: text });
const sees = (page, text) => page.evaluate(t => Object.values(window.Core.state.research || {}).flat().some(x => x.summary === t), text);

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_review.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_review"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("review");
    s.apply(A.dir, [{ op: "set-title", title: "Review checks" }, { op: "open-round", questions: [q("Q1", "Where should the summary sit?"), q("Q2", "Which payment first?")] }]);
    const desk = { context: { viewport: { width: 1440, height: 900 } } };
    const owner = await rec.open(A.ownerUrl, desk);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const ann = await rec.open(A.localUrl, desk);
    await joinAs(ann, "Ann");
    const bo = await rec.open(A.localUrl, desk);
    await joinAs(bo, "Bo");

    // ---------- the Ask boxes: Everyone on a question, Just me about the whole session ----------
    await ann.click(".vf-asktop");
    await until(ann, () => !!document.querySelector(".vf-drawer:not([hidden]) .vf-apform"));
    ok("Ask Claude on a question starts on Everyone", await audIn(ann, ".vf-apform .vf-aud") === "Everyone", await audIn(ann, ".vf-apform .vf-aud"));
    await ann.selectOption(".vf-apq select", "session");
    ok("  and about the whole session on Just me", await until(ann, () => document.querySelector(".vf-apform .vf-aud [aria-pressed=true]")?.textContent === "Just me"));
    await ann.click(".vf-drawer .vf-pp-head button");
    await ann.click(".vf-askbtn");
    await until(ann, () => !document.querySelector(".vf-askform").hidden);
    ok("the question's Ask form starts on Everyone", await audIn(ann, ".vf-askform .vf-aud") === "Everyone");
    await ann.click(".vf-askform .vf-aud [data-aud=me]");
    await ann.fill("#vf-ask-ta", ASK2);
    await ann.click(".vf-askform button[type=submit]");
    ok("  and Just me sends the request as Just me", await until(owner, t => (window.Core.snapshot().requests || []).some(r => r.text === t && r.audience === "me"), ASK2, 8000));
    await ann.waitForTimeout(1100);
    await ann.evaluate(t => window.Core.request("Q1", "ask", t), ASK1);
    await bo.evaluate(t => window.Core.request("Q2", "ask", t), ASK3);
    await until(owner, () => (window.Core.state.requests || []).length === 3);

    // ---------- the host's review view ----------
    await showTab(owner, "needs");
    ok("Needs you lists the requests newest first, each Waiting", await until(owner, ([ts, sel]) => {
      const r = [...document.querySelectorAll(sel)];
      return r.length === 3 && ts.every((t, i) => r[i].textContent.includes(t)) && r.every(li => li.querySelector(".vf-revstat").textContent.startsWith("Waiting"));
    }, [[ASK3, ASK1, ASK2], ROWS]), JSON.stringify(await rows(owner)));
    ok("  under one chip, Waiting · 3, on", JSON.stringify(await chips(owner)) === JSON.stringify({ Waiting: true }) && await owner.evaluate(() => document.querySelector(".vf-ibchips [data-stat=waiting]").textContent === "Waiting · 3"), JSON.stringify(await chips(owner)));
    ok("the rail has no Requests panel any more", await owner.evaluate(() => ![...document.querySelectorAll(".vf-proprow")].some(b => b.textContent.includes("Requests"))));
    for (const t of [ASK1, ASK2, ASK3]) await row(owner, t).locator("button", { hasText: /^Run$/ }).click();
    ok("Run on each row moves it out of Needs you", await until(owner, sel => !document.querySelectorAll(sel).length, ROWS, 8000), JSON.stringify(await rows(owner)));
    await showTab(owner, "history");
    ok("  to History, where each reads Running", await until(owner, ([ts, sel]) => ts.every(t => [...document.querySelectorAll(sel)].some(li => li.textContent.includes(t) && li.querySelector(".vf-revstat").textContent.startsWith("Running"))),
      [[ASK1, ASK2, ASK3], ROWS], 8000), JSON.stringify(await rows(owner)));
    await showTab(owner, "needs");
    const rid = t => owner.evaluate(x => window.Core.state.requests.find(r => r.text === x).id, t);
    const [r1, r2, r3] = [await rid(ASK1), await rid(ASK2), await rid(ASK3)];
    s.apply(A.dir, [{ op: "fail-request", request: r3, reason: WHY }]);
    ok("a failed request comes back to Needs you as Failed, with its reason and Run again", await until(owner, ([t, why, sel]) => {
      const li = [...document.querySelectorAll(sel)].find(l => l.textContent.includes(t));
      return li?.querySelector(".vf-revstat").textContent === "Failed" && li.textContent.includes(why) && [...li.querySelectorAll("button")].some(b => !b.hidden && b.textContent === "Run again");
    }, [ASK3, WHY, ROWS]), JSON.stringify(await rows(owner)));
    await row(owner, ASK3).locator("button", { hasText: "Run again" }).click();
    ok("  and Run again runs it again", await until(owner, t => window.Core.state.requests.find(r => r.text === t).status === "running", ASK3));
    ok("  and it leaves Needs you", await until(owner, ([t, sel]) => ![...document.querySelectorAll(sel)].some(l => l.textContent.includes(t)), [ASK3, ROWS]), JSON.stringify(await rows(owner)));
    const result = (request, qid, summary) => s.apply(A.dir, [{ op: "result", qid, request, kind: "ask", summary, sources: [], report: "", used: [], why: "" }]);
    result(r1, "Q1", ANS1);
    result(r2, "Q1", ANS2);

    // ---------- shared on arrival, and Just me only to its asker ----------
    ok("the answer asked for everyone shows to Bo when it arrives", await until(bo, a => (window.Core.state.research.Q1 || []).some(x => x.summary === a), ANS1, 10000));
    ok("the Just me answer shows to Ann", await until(ann, a => (window.Core.state.research.Q1 || []).some(x => x.summary === a), ANS2, 10000));
    ok("  and never to Bo", !(await sees(bo, ANS2)) && !(await bo.evaluate(a => JSON.stringify(window.Core.snapshot()).includes(a), ANS2)));
    ok("the shared row and the delivered Just me row are not in Needs you", await until(owner, ([a, b, sel]) => {
      const r = [...document.querySelectorAll(sel)];
      return !r.some(li => li.textContent.includes(a) || li.textContent.includes(b));
    }, [ASK1, ASK2, ROWS], 10000), JSON.stringify(await rows(owner)));
    await showTab(owner, "history");
    ok("History shows the Just me row, with no Discard", await until(owner, ([t, sel]) => {
      const li = [...document.querySelectorAll(sel)].find(l => l.textContent.includes(t));
      return li?.querySelector(".vf-revstat").textContent === "Just me" && ![...li.querySelectorAll("button")].some(b => !b.hidden && b.textContent === "Discard");
    }, [ASK2, ROWS]), JSON.stringify(await rows(owner)));
    await row(owner, ASK2).locator(".vf-rev-open").click();
    ok("  Open closes the Inbox page", await until(owner, () => document.querySelector(".vf-inboxpage").hidden));
    ok("  and its answer card offers the host no Discard", await until(owner, a => [...document.querySelectorAll(".vf-res")].some(li => li.textContent.includes(a)
      && !li.querySelector(".vf-res-share").hidden && ![...li.querySelectorAll("button")].some(b => !b.hidden && b.textContent === "Discard")), ANS2));
    await openInbox(owner);
    ok("the Inbox opens again on History, which shows the shared row with Take down", await until(owner, ([t, sel]) => {
      const li = [...document.querySelectorAll(sel)].find(l => l.textContent.includes(t));
      return document.querySelector(".vf-ixtabs [data-k=history]").getAttribute("aria-pressed") === "true"
        && li?.querySelector(".vf-revstat").textContent === "Shared" && [...li.querySelectorAll("button")].some(b => !b.hidden && b.textContent === "Take down");
    }, [ASK1, ROWS]));

    // ---------- Take down ----------
    await row(owner, ASK1).locator("button", { hasText: "Take down" }).click();
    await owner.locator("dialog[open] button", { hasText: "Take down" }).click();
    ok("Take down hides the answer from Bo", await until(bo, a => !(window.Core.state.research.Q1 || []).some(x => x.summary === a), ANS1, 10000));
    ok("  Ann still sees it", await sees(ann, ANS1));
    ok("  and its row reads Taken down", await until(owner, ([t, sel]) => [...document.querySelectorAll(sel)].find(l => l.textContent.includes(t))?.querySelector(".vf-revstat").textContent === "Taken down", [ASK1, ROWS]));
    await owner.click(".vf-ibchips [data-stat=running]");
    ok("  turning the Running chip off hides the running rows", await until(owner, ([t, sel]) => ![...document.querySelectorAll(sel)].some(l => l.textContent.includes(t)), [ASK3, ROWS]), JSON.stringify(await rows(owner)));
    await owner.keyboard.press("Escape");

    // ---------- the asker shares their Just me answer ----------
    await ann.click(".vf-q[data-qid=Q1]");
    await openClaude(ann);
    const annShare = ann.locator(".vf-res", { hasText: ANS2 }).locator("button", { hasText: "Share with everyone" });
    ok("Ann's Just me answer offers Share with everyone", await until(ann, a => [...document.querySelectorAll(".vf-res")].some(li => li.textContent.includes(a) && [...li.querySelectorAll("button")].some(b => !b.hidden && b.textContent === "Share with everyone")), ANS2, 8000));
    await annShare.click();
    ok("  and sharing it shows it to Bo", await until(bo, a => (window.Core.state.research.Q1 || []).some(x => x.summary === a), ANS2, 10000));

    // ---------- a general answer taken down leaves every open chat, and its asker's line says so ----------
    await ann.waitForTimeout(1100);
    await ann.evaluate(t => window.Core.chat(t), CHAT_ASK);
    ok("the host's page holds the chat @Claude ask", await until(owner, t => (window.Core.state.requests || []).some(r => r.text === t), CHAT_ASK, 10000));
    const grid = await owner.evaluate(t => window.Core.state.requests.find(r => r.text === t).id, CHAT_ASK);
    await owner.evaluate(id => window.Core.requestAct(id, "run"), grid);
    const gx = s.apply(A.dir, [{ op: "result", request: grid, kind: "ask", summary: CHAT_ANS, sources: [], report: "", used: [], why: "" }]).results[0].id;
    await openChat(bo);
    ok("Bo's open chat shows Claude's general answer", await until(bo, a => [...document.querySelectorAll(".vf-msg-claude")].some(li => li.textContent.includes(a)), CHAT_ANS, 10000));
    await owner.evaluate(id => window.Core.requestAct(id, "takedown"), gx);
    ok("  taking it down replaces it there with Taken down by the host, no reload", await until(bo, a => !document.body.textContent.includes(a)
      && [...document.querySelectorAll(".vf-msg-claude")].some(li => li.textContent.includes("Taken down by the host.")), CHAT_ANS, 10000));
    await openChat(ann);
    ok("Ann's @Claude message reads Sent to Claude · Taken down by the host", await until(ann, t => [...document.querySelectorAll(".vf-msg")].some(li => li.textContent.includes(t)
      && li.querySelector(".vf-msent")?.textContent === "Sent to Claude · Taken down by the host"), CHAT_ASK, 10000));

    // ---------- a Discussion ask taken down says so on its comment ----------
    await ann.waitForTimeout(1100);
    await ann.evaluate(t => window.Core.comment("Q2", t), DISC_ASK);
    ok("the host's page holds the Discussion @Claude ask", await until(owner, t => (window.Core.state.requests || []).some(r => r.text === t), DISC_ASK, 10000));
    const drid = await owner.evaluate(t => window.Core.state.requests.find(r => r.text === t).id, DISC_ASK);
    await owner.evaluate(id => window.Core.requestAct(id, "run"), drid);
    const dx = s.apply(A.dir, [{ op: "result", qid: "Q2", request: drid, kind: "ask", summary: DISC_ANS, sources: [], report: "", used: [], why: "" }]).results[0].id;
    await until(ann, a => (window.Core.state.research.Q2 || []).some(x => x.summary === a), DISC_ANS, 10000);
    await owner.evaluate(id => window.Core.requestAct(id, "takedown"), dx);
    await ann.click(".vf-q[data-qid=Q2]");
    if ((await ann.getAttribute(".vf-disc-head", "aria-expanded")) !== "true") await ann.click(".vf-disc-head");
    ok("Ann's @Claude comment reads Sent to Claude · Taken down by the host", await until(ann, t => [...document.querySelectorAll(".vf-cm")].some(li => li.textContent.includes(t)
      && li.querySelector(".vf-cm-became-t")?.textContent === "Sent to Claude · Taken down by the host"), DISC_ASK, 10000),
      await ann.evaluate(t => [...document.querySelectorAll(".vf-cm")].find(li => li.textContent.includes(t))?.querySelector(".vf-cm-became-t")?.textContent || "none", DISC_ASK));

    // ---------- the chips and the tab are remembered on this device ----------
    await owner.reload();
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    await openInbox(owner);
    ok("after a reload the Inbox opens on History", await until(owner, () => document.querySelector(".vf-ixtabs [data-k=history]")?.getAttribute("aria-pressed") === "true" && document.querySelector(".vf-ibneeds").hidden));
    ok("  with the Running chip still off", (await chips(owner)).Running === false, JSON.stringify(await chips(owner)));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
