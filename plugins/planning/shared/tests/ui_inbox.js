#!/usr/bin/env node
// The request Inbox (item 11) and host requests that skip Run and Share (item 9), against `share.sh ensure-running`
// with the fake cloudflared: the Inbox button's badge counts what changed since each item was last opened, opening an
// item marks it read and nothing else does; a guest's answer reads "Answered, waiting for the host to share" until
// the host shares it, then a toast "Claude answered your request on Q1" with Open shows it in the question's Claude
// section; the host's own request runs and shows with no Run or Share, and the host's Inbox lists what waits on them;
// a guest never sees another person's request; on a 390-wide phone the Inbox is a sheet over the whole screen.
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
const items = page => page.evaluate(() => [...document.querySelectorAll(".vf-ixmine .vf-ixlist > li")].map(li => ({
  key: li.dataset.key, stat: li.dataset.stat, chip: li.querySelector(".vf-ixchip").textContent, sub: li.querySelector(".vf-ixsub").hidden ? "" : li.querySelector(".vf-ixsub").textContent,
  unread: !li.querySelector(".vf-ndot").hidden, label: li.querySelector(".vf-ixitem").getAttribute("aria-label") })));
const openInbox = async page => { if (await page.evaluate(() => document.querySelector(".vf-inboxpop").hidden)) await page.click(".vf-bell"); return until(page, () => !document.querySelector(".vf-inboxpop").hidden); };
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
    await openInbox(owner);
    const wait = await owner.evaluate(() => ({ head: document.querySelector(".vf-ixwait > .vf-ixh").textContent,
      groups: [...document.querySelectorAll(".vf-ixwait .vf-ixgroup:not([hidden]) .vf-ixgh")].map(h => h.textContent),
      unread: [...document.querySelectorAll(".vf-ixwait .vf-ixlist > li")].map(li => !li.querySelector(".vf-ndot").hidden) }));
    ok("the host's Inbox shows Waiting on you · 1 with Requests to run · 1, unread", wait.head === "Waiting on you · 1" && wait.groups.join() === "Requests to run · 1" && wait.unread.join() === "true", JSON.stringify(wait));
    await owner.locator(".vf-ixwait .vf-ixitem").first().click();
    ok("opening it shows the request in Q1's Claude section, with its Run button", await until(owner, () => !document.querySelector(".vf-clbody").hidden
      && [...document.querySelectorAll(".vf-threq")].some(li => li.textContent.includes("How do the big shops") && [...li.querySelectorAll("button")].some(b => b.offsetParent && b.textContent === "Run"))));
    ok("  and marks it read: the host's badge empties", await until(owner, () => document.querySelector(".vf-bell-n").textContent === ""), await badge(owner));

    // ---------- a guest's request: Running, then answered but waiting for Share ----------
    await owner.evaluate(id => window.Core.requestAct(id, "run"), rid);
    ok("Run moves Ann's item to Running and her badge to 1", await until(ann, () => document.querySelector(".vf-bell-n").textContent === "1"), await badge(ann));
    await openInbox(ann);
    let mine = await items(ann);
    ok("  her item reads Running, unread", mine.length === 1 && mine[0].chip === "Running" && mine[0].unread, JSON.stringify(mine));
    await ann.waitForTimeout(1200);
    ok("nothing marks it read on its own: after a while open, it is still unread", (await items(ann))[0].unread && (await badge(ann)) === "1");
    await ann.locator(".vf-ixmine .vf-ixitem").first().click();
    ok("opening the item marks it read", await until(ann, () => document.querySelector(".vf-bell-n").textContent === "" && !window.Core.state.inbox[0].unread));
    const res = result(rid, ANSWER);
    ok("Claude's answer makes Ann's badge 1 again", await until(ann, () => document.querySelector(".vf-bell-n").textContent === "1", null, 10000), await badge(ann));
    await openInbox(ann);
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
    await openInbox(ann);
    ok("  where it now reads Shared", (await items(ann))[0].chip === "Shared");
    await ann.keyboard.press("Escape");

    // ---------- the host's own request skips Run and Share ----------
    await owner.evaluate(t => window.Core.request("Q1", "ask", t), HOST_ASK);
    const hid = await reqId(owner, HOST_ASK);
    ok("the host's own request runs at once: its card shows Running, with no Run button", await until(owner, t => {
      const li = [...document.querySelectorAll(".vf-threq")].find(x => x.textContent.includes(t));
      return !!li && li.dataset.stat === "running" && ![...li.querySelectorAll("button")].some(b => !b.hidden && b.textContent === "Run");
    }, HOST_ASK));
    result(hid, HOST_ANSWER);
    ok("its answer shows to Bo at once, with no Share", await until(bo, a => (window.Core.state.research.Q1 || []).some(x => x.summary === a), HOST_ANSWER, 10000));
    ok("  and the host gets the toast", await until(owner, () => document.querySelector(".vf-toast.vf-on span")?.textContent === "Claude answered your request on Q1", null, 10000));
    await openInbox(owner);
    const hostMine = await items(owner);
    ok("  the host's Inbox lists it under Your requests as Answered, unread", hostMine.length === 1 && hostMine[0].chip === "Answered" && hostMine[0].unread, JSON.stringify(hostMine));
    ok("  and nothing waits on the host", await owner.evaluate(() => document.querySelector(".vf-ixwait > .vf-ixh").textContent === "Waiting on you · 0"));

    // ---------- several waiting items and the badge count ----------
    await ann.evaluate(t => window.Core.request("Q2", "ask", t), ASK2);
    await bo.evaluate(t => window.Core.request("Q2", "ask", t), BO_ASK);
    ok("the host's badge counts one unread answer and two requests to run", await until(owner, () => document.querySelector(".vf-bell-n").textContent === "3", null, 10000), await badge(owner));
    ok("  under Requests to run · 2", await until(owner, () => [...document.querySelectorAll(".vf-ixwait .vf-ixgh")].some(h => h.textContent === "Requests to run · 2")));
    await owner.locator("button.vf-seg-btn", { hasText: "Waiting on you" }).click();
    ok("the Waiting on you tab hides Your requests and Notifications", await until(owner, () => document.querySelector(".vf-ixmine").hidden && document.querySelector(".vf-ixnotes").hidden && !document.querySelector(".vf-ixwait").hidden));
    await owner.locator("button.vf-seg-btn", { hasText: "All" }).click();

    // ---------- Mark all read sends every unread key, 100 a read (the server's cap) ----------
    const batches = await owner.evaluate(() => {
      const C = window.Core, real = C.readInbox, inbox = C.state.inbox, sent = [];
      C.readInbox = keys => { sent.push(keys.length); return Promise.resolve({}); };
      C.state.inbox = Array.from({ length: 250 }, (_, i) => ({ key: "R" + (1000 + i), group: "mine", unread: true }));
      document.querySelector(".vf-inboxpop .vf-pp-head .vf-btn").click();
      C.readInbox = real; C.state.inbox = inbox;
      return sent;
    });
    ok("Mark all read with 250 unread items sends reads of 100, 100 and 50", batches.join() === "100,100,50", batches.join());

    // ---------- a guest never sees another person's request ----------
    const leak = await bo.evaluate(([a, b]) => ({ inbox: window.Core.state.inbox.map(i => i.key), text: JSON.stringify(window.Core.snapshot()), a, b }), [ASK2, BO_ASK]);
    ok("Bo's Inbox holds only his own request and nothing waiting", leak.inbox.length === 1 && !leak.text.includes(ASK2) && !leak.text.includes(ASK) && leak.text.includes(BO_ASK)
      && !(await bo.evaluate(() => window.Core.state.inbox.some(i => i.group === "waiting"))), JSON.stringify(leak.inbox));

    // ---------- the phone sheet ----------
    await bo.click(".vf-bell");
    ok("390: the Inbox opens as a sheet over the whole screen", await until(bo, () => {
      const r = document.querySelector(".vf-inboxpop").getBoundingClientRect();
      return r.left === 0 && Math.round(r.width) === innerWidth && r.top <= 1 && Math.round(r.bottom) >= innerHeight - 1;
    }), JSON.stringify(await bo.evaluate(() => document.querySelector(".vf-inboxpop").getBoundingClientRect().toJSON())));
    ok("  with Bo's request listed as Waiting", (await items(bo)).map(i => i.chip).join() === "Waiting");
    ok("  and no Waiting on you tab for a guest", await bo.evaluate(() => [...document.querySelectorAll(".vf-ixtabs button")].filter(b => !b.hidden).map(b => b.textContent).join() === "All,Mine,Notifications"));
    ok("  nothing scrolls sideways", await bo.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.querySelector(".vf-inboxpop").scrollWidth <= innerWidth));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
