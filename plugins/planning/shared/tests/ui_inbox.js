#!/usr/bin/env node
// The request Inbox (item 11) and host requests that skip Run and Share (item 9), against `share.sh ensure-running`
// with the fake cloudflared: the Inbox button's badge counts what changed since each item was last opened, opening an
// item marks it read and nothing else does; a guest's answer reads "Answered, waiting for the host to share" until
// the host shares it, then a toast "Claude answered your request on Q1" with Open shows it in the question's Claude
// section; the host's own request runs and shows with no Run or Share, and the host's Inbox lists what waits on them;
// the host's pop-ups are a join, a request waiting for Run and a report alone, several close together as one count;
// a guest never sees another person's request; on a 390-wide phone the Inbox is a page below the top bar, full width.
//   node plugins/planning/shared/tests/ui_inbox.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the approved spec (.work spec-question-screen.md, followups items 9 and 11) and the texts
// this suite writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const ASK = "How do the big shops place the order summary?", ANSWER = "Most keep it in a right column on desktop.";
const HOST_ASK = "Which of these did we already rule out?", HOST_ANSWER = "Bank transfer was ruled out in round 1.";
const ASK2 = "Ann's second question, still waiting", BO_ASK = "Bo's private wording";
const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });
const PHONE = { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true };

const badge = page => page.evaluate(() => document.querySelector(".vf-bell-n").textContent);
/** The Inbox page on one tab (needs, mine, notes, history), opened first when it is closed. */
const showTab = async (page, k) => { await openInbox(page); await page.click(`.vf-ixtabs [data-k=${k}]`); return until(page, x => document.querySelector(`.vf-ixtabs [data-k=${x}]`)?.getAttribute("aria-pressed") === "true", k); };
/** The rows of My requests (or History's own requests), with each one's chip, line under it, dot and label. */
const items = async (page, k = "mine") => { await showTab(page, k); return page.evaluate(sel => [...document.querySelectorAll(sel)].map(li => ({
  key: li.dataset.key, stat: li.dataset.stat, chip: li.querySelector(".vf-ixchip").textContent, sub: li.querySelector(".vf-ixsub").hidden ? "" : li.querySelector(".vf-ixsub").textContent,
  unread: !li.querySelector(".vf-ndot").hidden, label: li.querySelector(".vf-ixitem").getAttribute("aria-label") })), k === "mine" ? ".vf-ixmine .vf-ixlist > li" : ".vf-ibhist .vf-ixlist > li"); };
const openInbox = async page => { if (await page.evaluate(() => document.querySelector(".vf-inboxpage").hidden)) await page.click(".vf-bell"); return until(page, () => !document.querySelector(".vf-inboxpage").hidden); };
const tabLabel = (page, k) => page.evaluate(x => document.querySelector(`.vf-ixtabs [data-k=${x}]`).textContent, k);
const reqId = (page, text) => page.evaluate(async t => {
  for (let i = 0; i < 50 && !(window.Core.state.requests || []).some(r => r.text === t); i++) await new Promise(r => setTimeout(r, 100));
  return (window.Core.state.requests || []).find(r => r.text === t)?.id;
}, text);

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_inbox.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_inbox"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("inbox");
    s.apply(A.dir, [{ op: "set-title", title: "Inbox checks" }, { op: "open-round", questions: [q("Q1", "Where should the order summary sit?"), q("Q2", "Which payment step?")] }]);
    const desk = { context: { viewport: { width: 1440, height: 900 } } };
    const owner = await rec.open(A.ownerUrl, desk);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    // This suite follows a guest's answer through the host's Share: the session reviews answers first.
    await owner.evaluate(() => window.Core.saveSettings({ reviewAnswers: true }));
    const ann = await rec.open(A.localUrl, desk);
    await joinAs(ann, "Ann");
    const bo = await rec.open(A.localUrl, { context: PHONE });
    await joinAs(bo, "Bo");
    const result = (rid, summary, qid = "Q1") => s.apply(A.dir, [{ op: "result", qid, request: rid, kind: "ask", summary, sources: [], report: "", used: [], why: "" }]).results[0];

    // ---------- the Inbox is in the bell's place, and asking is not news ----------
    // "Round 1 is here" is an unread notification the badge counts too: read it first, so each count below is the Inbox's.
    for (const p of [owner, ann]) { await until(p, () => window.Core.state.me?.notifications?.length > 0); await p.evaluate(() => window.Core.readNotifications("all")); }
    ok("the top bar's Inbox button reads Inbox", await until(ann, () => document.querySelector(".vf-bell .vf-inbox-l")?.textContent === "Inbox"));
    await ann.evaluate(t => window.Core.request("Q1", "ask", t), ASK);
    ok("Ann's new request is in her Inbox as Waiting, read: her badge stays empty", await until(ann, () => window.Core.state.inbox.length === 1) && (await badge(ann)) === "");
    const rid = await reqId(owner, ASK);
    ok("the host's badge counts the request to run", await until(owner, () => document.querySelector(".vf-bell-n").textContent === "1"), await badge(owner));
    await showTab(owner, "needs");
    const wait = await owner.evaluate(() => ({ tab: document.querySelector(".vf-ixtabs [data-k=needs]").textContent, head: document.querySelector(".vf-ibrev .vf-ixgh").textContent,
      rows: [...document.querySelectorAll(".vf-ibneeds .vf-revlist > li")].map(li => [li.querySelector(".vf-revstat").textContent, !li.querySelector(".vf-ndot").hidden]) }));
    ok("the host's Inbox shows Needs you · 1: Requests to Claude · 1, the request Waiting, unread", wait.tab === "Needs you · 1" && wait.head === "Requests to Claude · 1"
      && JSON.stringify(wait.rows) === JSON.stringify([["Waiting", true]]), JSON.stringify(wait));
    await owner.locator(".vf-ibneeds .vf-revlist > li .vf-qref").first().click();
    ok("  and opening it closes the Inbox page", await until(owner, () => document.querySelector(".vf-inboxpage").hidden && !document.querySelector(".app").classList.contains("vf-inboxon")));
    ok("opening it shows the request in Q1's Claude section, with its Run button", await until(owner, () => !document.querySelector(".vf-clbody").hidden
      && [...document.querySelectorAll(".vf-threq")].some(li => li.textContent.includes("How do the big shops") && [...li.querySelectorAll("button")].some(b => b.offsetParent && b.textContent === "Run"))));
    ok("  and marks it read: the host's badge empties", await until(owner, () => document.querySelector(".vf-bell-n").textContent === ""), await badge(owner));

    // ---------- a guest's request: Running, then answered but waiting for Share ----------
    await owner.evaluate(id => window.Core.requestAct(id, "run"), rid);
    ok("Run moves Ann's item to Running and her badge to 1", await until(ann, () => document.querySelector(".vf-bell-n").textContent === "1"), await badge(ann));
    let mine = await items(ann);
    ok("  her item reads Running, unread, under My requests", mine.length === 1 && mine[0].chip === "Running" && mine[0].unread, JSON.stringify(mine));
    await ann.waitForTimeout(1200);
    ok("nothing marks it read on its own: after a while open, it is still unread", (await items(ann))[0].unread && (await badge(ann)) === "1");
    await ann.locator(".vf-ixmine .vf-ixitem").first().click();
    ok("opening the item marks it read", await until(ann, () => document.querySelector(".vf-bell-n").textContent === "" && !window.Core.state.inbox[0].unread));
    const res = result(rid, ANSWER);
    ok("Claude's answer makes Ann's badge 1 again", await until(ann, () => document.querySelector(".vf-bell-n").textContent === "1", null, 10000), await badge(ann));
    mine = await items(ann);
    ok("  the item reads Answered, waiting for the host to share", mine[0].chip === "Answered" && mine[0].sub === "Waiting for the host to share" && /Answered, waiting for the host to share/.test(mine[0].label), JSON.stringify(mine));
    ok("  and the unshared answer is nowhere on Ann's page", await ann.evaluate(a => !document.body.textContent.includes(a) && !JSON.stringify(window.Core.snapshot()).includes(a), ANSWER));
    await ann.locator(".vf-ixmine .vf-ixitem").first().click();
    await until(ann, () => document.querySelector(".vf-bell-n").textContent === "");

    // ---------- the host shares: a toast with Open ----------
    await owner.evaluate(id => window.Core.requestAct(id, "publish"), res.id);
    ok("sharing shows Ann the toast \"Claude answered your request on Q1\" with Open", await until(ann, () => document.querySelector(".vf-toast.vf-on span")?.textContent === "Claude answered your request on Q1"
      && document.querySelector(".vf-toast-act:not([hidden])")?.textContent === "Open", null, 10000));
    ok("  and her badge counts the change to Shared", (await badge(ann)) === "1");
    await ann.locator(".vf-toast-act").click();
    ok("Open shows the answer in Q1's Claude section", await until(ann, a => !document.querySelector(".vf-clbody").hidden && [...document.querySelectorAll(".vf-res")].some(li => li.textContent.includes(a)), ANSWER));
    ok("  and marks the item read", await until(ann, () => document.querySelector(".vf-bell-n").textContent === ""));
    ok("  opened, it leaves My requests for History, where it reads Shared", (await items(ann)).length === 0 && (await items(ann, "history"))[0]?.chip === "Shared",
      JSON.stringify(await items(ann, "history")));
    await ann.keyboard.press("Escape");

    // ---------- the host's own request skips Run and Share ----------
    // every toast text the owner's page shows from here, as ui_inbox_page.js watches them
    await owner.evaluate(() => { window.__toasts = []; window.__obs = new MutationObserver(() => { const t = document.querySelector(".vf-toast span")?.textContent; if (t) window.__toasts.push(t); });
      window.__obs.observe(document.querySelector(".vf-toast"), { childList: true, characterData: true, subtree: true }); });
    await owner.evaluate(t => window.Core.request("Q1", "ask", t), HOST_ASK);
    const hid = await reqId(owner, HOST_ASK);
    ok("the host's own request runs at once: its card shows Running, with no Run button", await until(owner, t => {
      const li = [...document.querySelectorAll(".vf-threq")].find(x => x.textContent.includes(t));
      return !!li && li.dataset.stat === "running" && ![...li.querySelectorAll("button")].some(b => !b.hidden && b.textContent === "Run");
    }, HOST_ASK));
    result(hid, HOST_ANSWER);
    ok("its answer shows to Bo at once, with no Share", await until(bo, a => (window.Core.state.research.Q1 || []).some(x => x.summary === a), HOST_ANSWER, 10000));
    await until(owner, t => window.Core.state.inbox.some(i => i.group === "mine" && i.status === "answered" && window.Core.state.myRequests.find(r => r.id === i.id)?.text === t), HOST_ASK, 10000);
    await owner.waitForTimeout(2500); // a few polls: the answer is the host's news, in the Inbox only
    ok("  and the host gets no pop-up for it: only a join, a request to Run and a report pop up for the host", await owner.evaluate(() => !window.__toasts.some(t => /answered/.test(t))), JSON.stringify(await owner.evaluate(() => window.__toasts)));
    await owner.evaluate(() => window.__obs.disconnect());
    const hostMine = await items(owner);
    ok("  the host's Inbox lists it under My requests as Answered, unread", hostMine.length === 1 && hostMine[0].chip === "Answered" && hostMine[0].unread, JSON.stringify(hostMine));
    await showTab(owner, "needs");
    ok("  and Needs you holds only that unread answer, under For you: nothing else waits on the host", (await tabLabel(owner, "needs")) === "Needs you · 1"
      && await owner.evaluate(t => { const r = [...document.querySelectorAll(".vf-ibneeds li")]; return r.length === 1 && r[0].closest(".vf-ibneedix") && r[0].textContent.includes(t); }, HOST_ASK), await tabLabel(owner, "needs"));

    // ---------- several waiting items and the badge count ----------
    await ann.evaluate(t => window.Core.request("Q2", "ask", t), ASK2);
    await bo.evaluate(t => window.Core.request("Q2", "ask", t), BO_ASK);
    ok("the host's badge counts one unread answer and two requests to run", await until(owner, () => document.querySelector(".vf-bell-n").textContent === "3", null, 10000), await badge(owner));
    await showTab(owner, "needs");
    ok("  Needs you lists the two requests waiting to run, beside the unread answer", await until(owner, () => document.querySelector(".vf-ixtabs [data-k=needs]").textContent === "Needs you · 3"
      && [...document.querySelectorAll(".vf-ibneeds .vf-revlist .vf-revstat")].map(c => c.textContent).join() === "Waiting,Waiting"));
    ok("each tab shows only its own list", await owner.evaluate(() => !document.querySelector(".vf-ibneeds").hidden && document.querySelector(".vf-ixmine").hidden && document.querySelector(".vf-ixnotes").hidden && document.querySelector(".vf-ibhist").hidden));

    // ---------- Mark all read sends every unread key, 100 a read (the server's cap) ----------
    const batches = await owner.evaluate(() => {
      const C = window.Core, real = C.readInbox, inbox = C.state.inbox, sent = [];
      C.readInbox = keys => { sent.push(keys.length); return Promise.resolve({}); };
      C.state.inbox = Array.from({ length: 250 }, (_, i) => ({ key: "R" + (1000 + i), group: "mine", unread: true }));
      document.querySelector(".vf-iball").click();
      C.readInbox = real; C.state.inbox = inbox;
      return sent;
    });
    ok("Mark all read with 250 unread items sends reads of 100, 100 and 50", batches.join() === "100,100,50", batches.join());

    // ---------- a guest never sees another person's request ----------
    await until(bo, t => (window.Core.state.inbox || []).length === 1 && JSON.stringify(window.Core.snapshot()).includes(t), BO_ASK);
    const leak = await bo.evaluate(([a, b]) => ({ inbox: window.Core.state.inbox.map(i => i.key), text: JSON.stringify(window.Core.snapshot()), a, b }), [ASK2, BO_ASK]);
    ok("Bo's Inbox holds only his own request and nothing waiting", leak.inbox.length === 1 && !leak.text.includes(ASK2) && !leak.text.includes(ASK) && leak.text.includes(BO_ASK)
      && !(await bo.evaluate(() => window.Core.state.inbox.some(i => i.group === "waiting"))), JSON.stringify(leak.inbox));

    // ---------- a proposal is news to a moderator, though it has no Inbox item ----------
    const lee = await rec.open(A.localUrl, desk), leePid = await joinAs(lee, "Lee");
    await owner.evaluate(p => window.Core.setLeader(p, true), leePid);
    await until(lee, () => window.Core.me.isLeader && window.Core.state.me?.notifications?.length > 0);
    for (const p of [owner, lee]) await p.evaluate(() => window.Core.readNotifications("all"));
    ok("a leader whose notifications are read starts with an empty badge", await until(lee, () => document.querySelector(".vf-bell-n").textContent === ""), await badge(lee));
    await owner.evaluate(() => { const w = window.Core.state.inbox.find(i => i.group === "waiting" && i.unread); return window.Core.readInbox([w.key], { [w.key]: w.status }); });
    ok("the owner, having opened one of the two requests waiting to run, counts 2", await until(owner, () => document.querySelector(".vf-bell-n").textContent === "2"), await badge(owner));
    await bo.evaluate(() => window.Core.idea("Put the order summary in a sticky right column"));
    ok("a guest's proposal makes the leader's badge 1", await until(lee, () => document.querySelector(".vf-bell-n").textContent === "1", null, 10000), await badge(lee));
    await openInbox(lee);
    ok("  with Mark all read in the Inbox", await lee.evaluate(() => { const b = document.querySelector(".vf-iball"); return !b.hidden && b.textContent === "Mark all read"; }));
    ok("  and the proposal under Needs you, To place, for the leader to place", await until(lee, () => [...document.querySelectorAll(".vf-ibneeds .vf-ibq > li")].some(li => li.dataset.t === "proposal")
      && document.querySelector(".vf-ibneedq .vf-ixgh").textContent === "To place · 1"));
    await lee.click(".vf-iball");
    ok("  which empties it", await until(lee, () => document.querySelector(".vf-bell-n").textContent === ""), await badge(lee));
    ok("the owner, with requests waiting to run, gets the proposal's queue line, its only one", await until(owner, () => window.Core.state.me.notifications.filter(n => n.kind === "queue" && !n.read).length === 1, null, 10000));
    ok("  and the badge counts it: 3", await until(owner, () => document.querySelector(".vf-bell-n").textContent === "3"), await badge(owner));

    // ---------- what waits on the owner pops up once, for the owner alone ----------
    const RUN_T = "Ann asked Claude on Q2. Run it from the Inbox.", JOIN_T = "Jib asks to join.";
    const watchToasts = page => page.evaluate(() => {
      window.__toasts = [];
      new MutationObserver(() => { const t = document.querySelector(".vf-toast span")?.textContent; if (t) window.__toasts.push(t); })
        .observe(document.querySelector(".vf-toast"), { childList: true, characterData: true, subtree: true });
    });
    const toasts = (page, t) => page.evaluate(x => window.__toasts.filter(y => y === x).length, t);
    for (const p of [owner, lee]) await watchToasts(p);
    // An earlier pop-up would take the next one in: an urgent one stays until closed (Q39), so close it.
    const quiet = async () => { if (await owner.locator(".vf-toast.vf-on .vf-toast-x:not([hidden])").isVisible()) await owner.click(".vf-toast-x"); return until(owner, () => !document.querySelector(".vf-toast.vf-on"), null, 15000); };
    await quiet();
    await ann.evaluate(() => window.Core.request("Q2", "ask", "Ann's third question, waiting on Run"));
    ok("a guest's request waiting on Run pops one toast for the owner", await until(owner, t => window.__toasts.includes(t), RUN_T, 10000), JSON.stringify(await owner.evaluate(() => window.__toasts)));
    await owner.waitForTimeout(10000); // past the 9 s an ordinary toast with an action stays
    ok("  which stays while it waits, with Close (Q39)", await owner.evaluate(t => document.querySelector(".vf-toast.vf-on span")?.textContent === t && !document.querySelector(".vf-toast-x").hidden, RUN_T));
    await owner.evaluate(() => window.Core.runRequests([window.Core.state.requests.find(r => r.text === "Ann's third question, waiting on Run").id]));
    ok("  once it no longer waits, its pop-up goes", await until(owner, t => document.querySelector(".vf-toast span")?.textContent !== t || !document.querySelector(".vf-toast.vf-on"), RUN_T, 10000));
    await owner.evaluate(() => window.Core.saveSettings({ approveJoins: true }));
    await until(owner, () => window.Core.snapshot().settings.approveJoins === true);
    const jib = await rec.open(A.localUrl, desk);
    await jib.waitForSelector("dialog.core-name[open]");
    await jib.fill("#core-n", "Jib");
    await jib.click("dialog.core-name button");
    ok("a guest asking to join pops one toast for the owner, with their name", await until(owner, t => window.__toasts.includes(t), JOIN_T, 20000), JSON.stringify(await owner.evaluate(() => window.__toasts)));
    await owner.waitForTimeout(3000); // a few more polls: neither item pops again
    ok("  each exactly once", (await toasts(owner, RUN_T)) === 1 && (await toasts(owner, JOIN_T)) === 1, JSON.stringify(await owner.evaluate(() => window.__toasts)));
    ok("  and none for the leader", (await toasts(lee, RUN_T)) === 0 && (await toasts(lee, JOIN_T)) === 0, JSON.stringify(await lee.evaluate(() => window.__toasts)));
    // Follow-ups 18 and 24: pop-ups close together are one, with a count, and Open Inbox.
    const MANY = "2 requests wait on you";
    await quiet();
    await Promise.all([ann.evaluate(() => window.Core.request("Q1", "ask", "Ann asks at the same moment")), bo.evaluate(() => window.Core.request("Q1", "ask", "Bo asks at the same moment"))]);
    ok("two requests arriving together pop one toast, 2 requests wait on you, with Open Inbox", await until(owner, t => document.querySelector(".vf-toast.vf-on span")?.textContent === t
      && document.querySelector(".vf-toast-act:not([hidden])")?.textContent === "Open Inbox", MANY, 10000), JSON.stringify(await owner.evaluate(() => window.__toasts)));
    await owner.locator(".vf-toast-act").click();
    ok("  Open Inbox opens the Inbox page on Needs you", await until(owner, () => !document.querySelector(".vf-inboxpage").hidden && document.querySelector(".vf-ixtabs [data-k=needs]").getAttribute("aria-pressed") === "true"));
    await owner.keyboard.press("Escape");
    await owner.reload();
    await until(owner, () => window.Core.live && window.Core.state.inbox.some(i => i.kind === "join"));
    await watchToasts(owner);
    await owner.waitForTimeout(3000);
    const showing = await owner.evaluate(() => document.querySelector(".vf-toast.vf-on span")?.textContent || ""); // one fired before the watch would still show (9 s)
    ok("after a reload, items already waiting pop no toast", (await toasts(owner, RUN_T)) === 0 && (await toasts(owner, JOIN_T)) === 0 && ![RUN_T, JOIN_T].includes(showing),
      JSON.stringify([showing, ...(await owner.evaluate(() => window.__toasts))]));

    // ---------- the phone page ----------
    await bo.click(".vf-bell");
    ok("390: the Inbox opens as a page from the top bar's bottom edge to the screen's, full width", await until(bo, () => {
      const r = document.querySelector(".vf-inboxpage").getBoundingClientRect(), t = document.querySelector(".vf-top").getBoundingClientRect();
      return r.left === 0 && Math.round(r.width) === innerWidth && Math.abs(r.top - t.bottom) <= 1 && Math.round(r.bottom) >= innerHeight - 1;
    }), JSON.stringify(await bo.evaluate(() => document.querySelector(".vf-inboxpage").getBoundingClientRect().toJSON())));
    ok("  with Bo's two requests listed as Waiting", (await items(bo)).map(i => i.chip).join() === "Waiting,Waiting");
    ok("  and the same four tabs a guest has everywhere", await bo.evaluate(() => [...document.querySelectorAll(".vf-ixtabs button")].filter(b => !b.hidden).map(b => b.textContent.split(" · ")[0]).join() === "Needs you,My requests,Notifications,History"));
    ok("  nothing scrolls sideways", await bo.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.querySelector(".vf-inboxpage").scrollWidth <= innerWidth));
    await bo.click(".vf-ibback");
    ok("  Back to the session closes it", await until(bo, () => document.querySelector(".vf-inboxpage").hidden && !!document.querySelector(".vf-tabs")?.offsetParent));
    await bo.locator(".vf-tab", { hasText: "More" }).tap();
    await bo.locator(".vf-msitem", { hasText: "Inbox" }).tap();
    ok("  opened from More, the Inbox page leaves the More tab's aria-expanded false", await until(bo, () => !document.querySelector(".vf-inboxpage").hidden)
      && await bo.evaluate(() => [...document.querySelectorAll(".vf-tab")].find(b => b.textContent.includes("More")).getAttribute("aria-expanded") === "false"));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
