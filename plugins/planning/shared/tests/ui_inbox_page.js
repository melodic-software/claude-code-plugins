#!/usr/bin/env node
// The Inbox page (spec PR 9, follow-up 23), against `share.sh ensure-running` with the fake cloudflared. Needs you
// holds only what needs this person now: for the owner, a request Claude failed waits until opened, while one the
// owner discarded or cancelled, and a report already asked about, never wait; the rest is in History. Every row
// opens where it happened and closes the page: a request on its question, a notification on its question, a
// question the guest is asked to answer, a proposal in the Host view's queue. A leader sees proposals to place, and
// the server refuses a leader's Run however the page looks. The owner's Notifications start with Pop-ups switches
// (a join, a request for Run and a report on); one turned off leaves its items in Needs you with no pop-up. A guest's
// own three switches start as the owner's Guests start with defaults until the guest changes them.
//   node plugins/planning/shared/tests/ui_inbox_page.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the owner-approved spec (spec-question-screen.md item 9, follow-up 23) and the texts this
// suite writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, settled, joinAs } = require("./browser_harness");

const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });
const CTX = { view: "focus", device: "computer", browser: "chrome", viewport: { w: 1440, h: 900 }, errors: [] };
const DISCARD = "Ann asks one the host discards", CANCEL = "Ann asks one the host cancels", FAILS = "Ann asks one Claude fails";
const REPORT = "The Send button stays grey on Q1.", IDEA = "Put the summary in a sticky right column";
const openInbox = async page => { if (await page.evaluate(() => document.querySelector(".vf-inboxpage").hidden)) await page.click(".vf-bell"); return until(page, () => !document.querySelector(".vf-inboxpage").hidden); };
const showTab = async (page, k) => { await openInbox(page); await page.click(`.vf-ixtabs [data-k=${k}]`); return until(page, x => document.querySelector(`.vf-ixtabs [data-k=${x}]`)?.getAttribute("aria-pressed") === "true", k); };
const closed = page => until(page, () => document.querySelector(".vf-inboxpage").hidden);
/** The text of every row on the tab shown. */
const shown = page => page.evaluate(() => [...document.querySelectorAll(".vf-ibtab:not([hidden]) li")].filter(li => !li.closest("[hidden]") && !li.parentElement.closest("li")).map(li => li.textContent));

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_inbox_page.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_inbox_page"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("inboxpage");
    s.apply(A.dir, [{ op: "set-title", title: "Inbox page checks" }, { op: "open-round", questions: [q("Q1", "Where should the order summary sit?"), q("Q2", "Which payment step first?")] }]);
    const desk = { context: { viewport: { width: 1440, height: 900 } } };
    const owner = await rec.open(A.ownerUrl, desk);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    await owner.evaluate(() => window.Core.saveSettings({ reviewAnswers: true }));
    const ann = await rec.open(A.localUrl, desk), annPid = await joinAs(ann, "Ann");
    const lee = await rec.open(A.localUrl, desk), leePid = await joinAs(lee, "Lee");
    await owner.evaluate(p => window.Core.setLeader(p, true), leePid);

    // ---------- follow-up 23: what the owner handled no longer waits ----------
    for (const t of [DISCARD, CANCEL, FAILS]) { await ann.evaluate(x => window.Core.request("Q1", "ask", x), t); await ann.waitForTimeout(1100); }
    await until(owner, () => (window.Core.state.requests || []).length === 3);
    const id = t => owner.evaluate(x => window.Core.state.requests.find(r => r.text === x).id, t);
    const [rd, rc, rf] = [await id(DISCARD), await id(CANCEL), await id(FAILS)];
    await owner.evaluate(ids => window.Core.runRequests(ids), [rd, rc, rf]);
    await until(owner, () => window.Core.state.requests.every(r => r.status === "running"));
    const x = s.apply(A.dir, [{ op: "result", qid: "Q1", request: rd, kind: "ask", summary: "An answer the host discards.", sources: [], report: "", used: [], why: "" }]).results[0];
    s.apply(A.dir, [{ op: "fail-request", request: rf, reason: "No sources found." }]);
    await until(owner, xid => (window.Core.state.research.Q1 || []).some(y => y.id === xid), x.id);
    await owner.evaluate(xid => window.Core.requestAct(xid, "discard"), x.id);
    await owner.evaluate(r => window.Core.requestAct(r, "fail"), rc);
    await ann.evaluate(([t, c]) => window.Core.report(t, c), [REPORT, CTX]);
    await until(owner, () => (window.Core.state.reports || []).length === 1);
    await owner.evaluate(() => window.Core.reportAct(window.Core.state.reports[0].id, "ask"));
    await until(owner, () => window.Core.state.reports[0]?.asked && window.Core.state.requests.every(r => r.status === "failed"));
    await showTab(owner, "needs");
    ok("Needs you holds the request Claude failed alone: not the discarded or cancelled one, nor the report asked about", await until(owner, t => {
      const r = [...document.querySelectorAll(".vf-ibneeds li")].filter(li => !li.closest("[hidden]") && !li.parentElement.closest("li"));
      return r.length === 1 && r[0].textContent.includes(t) && r[0].querySelector(".vf-revstat")?.textContent === "Failed";
    }, FAILS), JSON.stringify(await shown(owner)));
    await owner.click(".vf-iball");
    await owner.waitForTimeout(1500); // the reads land and a poll comes back
    ok("Mark all read leaves the failed request in Needs you, unread: it clears only from its row", await owner.evaluate(t => {
      const li = [...document.querySelectorAll(".vf-ibneeds .vf-revlist > li")].find(l => l.textContent.includes(t));
      return !!li && !li.querySelector(".vf-ndot").hidden && window.Core.state.inbox.some(i => i.kind === "fail" && i.unread);
    }, FAILS));
    await owner.locator(".vf-ibneeds .vf-revlist > li", { hasText: FAILS }).locator(".vf-qref").click();
    ok("opening the failed request closes the page and shows it on Q1", await closed(owner) && await until(owner, t => [...document.querySelectorAll(".vf-threq")].some(li => li.textContent.includes(t)), FAILS));
    await showTab(owner, "needs");
    ok("  opened, it leaves Needs you, which says nothing needs the host now", await until(owner, () => !document.querySelector(".vf-ibempty").hidden && /^Nothing needs you now/.test(document.querySelector(".vf-ibneeds .vf-ibempty").textContent)));
    await showTab(owner, "history");
    const hist = await shown(owner);
    ok("History holds the three requests and the report", [DISCARD, CANCEL, FAILS, REPORT].every(t => hist.some(h => h.includes(t))), JSON.stringify(hist));
    await owner.keyboard.press("Escape");

    // ---------- a leader: proposals to place, and no Run ----------
    await ann.evaluate(t => window.Core.idea(t), IDEA);
    await showTab(lee, "needs");
    ok("a leader's Needs you lists the proposal to place", await until(lee, t => [...document.querySelectorAll(".vf-ibneeds .vf-ibq > li")].some(li => li.dataset.t === "proposal" && li.textContent.includes(t)), IDEA, 10000));
    ok("  and no request rows: Run is the owner's", await lee.evaluate(() => !document.querySelector(".vf-ibneeds .vf-revlist > li")));
    const refused = await lee.evaluate(r => window.Core.requestAct(r, "rerun").then(() => "ran", e => String(e?.status)), rf);
    ok("  the server refuses a leader's Run again however the page looks", refused === "403", refused);
    await lee.keyboard.press("Escape");

    // ---------- the owner: Show in Host view ----------
    await showTab(owner, "needs");
    ok("Show in Host view leads the proposal row's own actions, one row of buttons (follow-up 51)", await until(owner, t => {
      const go = [...document.querySelectorAll(".vf-ibneeds .vf-ibq > li")].find(li => li.textContent.includes(t))?.querySelector(".vf-ibgo");
      return !!go && go.parentElement.matches(".vf-acts") && go.parentElement.firstElementChild === go && /Make it a question/.test(go.parentElement.textContent)
        && go.closest("li").querySelectorAll(".vf-acts").length === 1;
    }, IDEA));
    await owner.locator(".vf-ibneeds .vf-ibq > li", { hasText: IDEA }).locator(".vf-ibgo").click();
    ok("Show in Host view closes the page and rings the proposal's row in the Host queue", await closed(owner)
      && await until(owner, t => document.querySelector(".vf-center")?.dataset.mode === "host" && [...document.querySelectorAll(".vf-queue > li")].some(li => li.textContent.includes(t) && li.classList.contains("vf-hl")), IDEA));

    // ---------- the Host view's Review in Inbox, and a chip turned off ----------
    const REVIEW = "Ann asks one the host reviews from the Host view";
    await ann.evaluate(t => window.Core.request("Q1", "ask", t), REVIEW);
    await until(owner, t => [...document.querySelectorAll(".vf-queue > li")].some(li => li.dataset.t === "request" && li.textContent.includes(t)), REVIEW, 10000);
    await owner.locator(".vf-queue > li", { hasText: REVIEW }).locator("button", { hasText: "Review in Inbox" }).click();
    ok("the Host view's Review in Inbox opens Needs you with the request's row ringed", await until(owner, t => !document.querySelector(".vf-inboxpage").hidden
      && document.querySelector(".vf-ixtabs [data-k=needs]").getAttribute("aria-pressed") === "true"
      && [...document.querySelectorAll(".vf-ibneeds .vf-revlist > li")].some(li => li.textContent.includes(t) && li.classList.contains("vf-hl")), REVIEW));
    const colsStill = await settled(owner, { rects: true });
    const cols = await owner.evaluate(() => { const r = s => document.querySelector(s).getBoundingClientRect(); const a = r(".vf-ibneeds > .vf-ibrev"), b = r(".vf-ibneeds > .vf-ibneedq"); return { aL: a.left, aR: a.right, bL: b.left, top: Math.abs(a.top - b.top) }; });
    ok("at 1440 px, Needs you lists requests and what waits on the host side by side (follow-up 51)", colsStill && cols.aR <= cols.bL && cols.top < 2, JSON.stringify({ still: colsStill, ...cols }));
    await owner.click(".vf-ibchips [data-stat=proposal]");
    await owner.locator(".vf-ibneeds .vf-revlist > li", { hasText: REVIEW }).locator("button", { hasText: /^Run$/ }).click();
    ok("with only a kind whose chip is off left, the chips stay in reach and say so", await until(owner, () => !document.querySelector(".vf-ibchips").hidden
      && document.querySelector(".vf-ibchips [data-stat=proposal]")?.getAttribute("aria-pressed") === "false" && /^Nothing with these chips on/.test(document.querySelector(".vf-ibneeds .vf-ibempty").textContent)));
    await owner.click(".vf-ibchips [data-stat=proposal]");

    // ---------- an urgent pop-up over the open Inbox: Close, a second one for the same report, Escape ----------
    const REPORT2 = "The Next button skips Q2.";
    await owner.evaluate(() => { window.__toasts = []; new MutationObserver(() => { const t = document.querySelector(".vf-toast span")?.textContent; if (t) window.__toasts.push(t); }).observe(document.querySelector(".vf-toast"), { childList: true, characterData: true, subtree: true }); });
    await lee.evaluate(([t, c]) => window.Core.report(t, c), [REPORT2, CTX]);
    ok("a report pops up for the owner over the open Inbox page", await until(owner, () => document.querySelector(".vf-toast.vf-on span")?.textContent === "Lee reported a problem.", null, 10000));
    ok("  its Close is named Close this pop-up", await owner.evaluate(() => document.querySelector(".vf-toast-x").getAttribute("aria-label") === "Close this pop-up"));
    await owner.click(".vf-toast-x");
    ok("  Close takes the pop-up away and leaves the Inbox page open", await until(owner, () => !document.querySelector(".vf-toast.vf-on")) && await owner.evaluate(() => !document.querySelector(".vf-inboxpage").hidden));
    const f2 = await owner.evaluate(t => window.Core.state.reports.find(r => r.text === t).id, REPORT2);
    await owner.evaluate(id => window.Core.reportAct(id, "ask"), f2);
    await until(owner, id => !window.Core.state.inbox.some(i => i.key === "report:" + id), f2);
    await owner.waitForTimeout(1500);
    await lee.evaluate(id => window.Core.addToReport(id, "It skips Q3 too."), f2);
    ok("the same report, back after its reporter adds to it, pops up again", await until(owner, () => window.__toasts.filter(t => t === "Lee reported a problem.").length === 2, null, 10000), JSON.stringify(await owner.evaluate(() => window.__toasts)));
    await owner.keyboard.press("Escape");
    ok("  the first Escape takes the pop-up away and leaves the Inbox page open", await until(owner, () => !document.querySelector(".vf-toast.vf-on")) && await owner.evaluate(() => !document.querySelector(".vf-inboxpage").hidden));
    await owner.keyboard.press("Escape");
    await closed(owner);

    // ---------- review round 2: an opened failure never pops up; Open follows the newer item; chat yields ----------
    await showTab(owner, "notes");
    await owner.click(".vf-ibpops [data-k=fail]");
    await until(owner, () => (window.Core.state.me.prefs.popups || []).includes("fail"), null, 8000);
    await owner.keyboard.press("Escape");
    await owner.waitForTimeout(2500); // a few polls
    ok("with Failed pop-ups on, a failure the owner already opened does not pop up", await owner.evaluate(() => !window.__toasts.some(t => /could not answer/.test(t))), JSON.stringify(await owner.evaluate(() => window.__toasts)));
    const po = await rec.open(A.ownerUrl, { context: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true } });
    await until(po, () => window.Core.snapshot()?.me?.role === "owner" && window.Core.live);
    await po.waitForTimeout(1500); // primed: what waits already never pops up here
    const REP_A = "The total jumps on Q1.", REP_B = "The total jumps on Q2 as well.";
    await ann.evaluate(([t, c]) => window.Core.report(t, c), [REP_A, CTX]);
    await until(owner, () => document.querySelector(".vf-toast.vf-on span")?.textContent === "Ann reported a problem.", null, 10000);
    const fa = await owner.evaluate(t => window.Core.state.reports.find(r => r.text === t).id, REP_A);
    await po.click(".vf-fab");
    await until(po, () => !document.querySelector(".vf-chat").hidden);
    await ann.waitForTimeout(10500); // one report every 10 s a person (session.py REPORT_INTERVAL)
    await Promise.all([owner.evaluate(id => window.Core.reportAct(id, "seen"), fa), ann.evaluate(([t, c]) => window.Core.report(t, c), [REP_B, CTX])]);
    await until(owner, t => window.Core.state.inbox.some(i => i.kind === "report" && window.Core.state.reports.find(r => r.id === i.id)?.text === t)
      && !window.Core.state.inbox.some(i => i.key.startsWith("report:") && window.Core.state.reports.find(r => r.id === i.id)?.status === "seen"), REP_B, 10000);
    await until(owner, () => document.querySelector(".vf-toast.vf-on span")?.textContent === "Ann reported a problem.", null, 10000);
    await owner.click(".vf-toast-act");
    ok("Open on a pop-up whose words stayed the same opens the newer report's row", await until(owner, t => !document.querySelector(".vf-inboxpage").hidden
      && [...document.querySelectorAll(".vf-ibq > li")].some(li => li.textContent.includes(t) && li.classList.contains("vf-hl") && !li.closest("[hidden]")), REP_B));
    await owner.keyboard.press("Escape");
    ok("390, chat open: the report pops up for the owner", await until(po, () => document.querySelector(".vf-toast.vf-on span")?.textContent === "Ann reported a problem.", null, 10000));
    await po.click(".vf-toast-act");
    await until(po, () => !document.querySelector(".vf-inboxpage").hidden);
    for (let i = 0; i < 6; i++) await po.keyboard.press("Tab");
    ok("  Open from it gives the Inbox page the screen: chat closed, the top bar live, Tab inside the page", await po.evaluate(() => document.querySelector(".vf-chat").hidden
      && !document.querySelector(".vf-top").inert && document.querySelector(".vf-inboxpage").contains(document.activeElement)));
    await po.context().close();
    await showTab(owner, "notes");
    await owner.click(".vf-ibpops [data-k=fail]"); // back to the defaults the switches check below
    await until(owner, () => !(window.Core.state.me.prefs.popups || []).includes("fail"), null, 8000);
    await owner.keyboard.press("Escape");

    // ---------- a guest: the question they are asked, and a notification ----------
    s.apply(A.dir, [{ op: "set-for", qid: "Q2", for: [annPid] }]);
    await showTab(ann, "needs");
    ok("a guest's Needs you lists no proposal or suggestion to place, her own proposal included", await until(ann, () => document.querySelectorAll(".vf-ibneeds .vf-ixitem").length > 0)
      && await ann.evaluate(() => !document.querySelector(".vf-ibneeds .vf-ibq > li")));
    ok("Ann's Needs you lists Q2, the question she is asked to answer", await until(ann, () => [...document.querySelectorAll(".vf-ibneeds .vf-ixitem")].some(b => b.textContent.includes("Q2") && b.textContent.includes("You are asked to answer this question.")), null, 10000),
      JSON.stringify(await shown(ann)));
    await ann.locator(".vf-ibneeds .vf-ixitem", { hasText: "Q2" }).click();
    ok("  opening it closes the page on Q2", await closed(ann) && await until(ann, () => document.querySelector(".vf-qtext")?.textContent === "Which payment step first?"));
    await showTab(ann, "notes");
    const failed = ann.locator(".vf-nitem", { hasText: "failed" });
    ok("Ann's Notifications list her failed request", await until(ann, () => [...document.querySelectorAll(".vf-nitem")].some(b => b.textContent.includes("failed")), null, 10000));
    await failed.first().click();
    ok("  opening it closes the page on Q1", await closed(ann) && await until(ann, () => document.querySelector(".vf-qtext")?.textContent === "Where should the order summary sit?"));

    // ---------- the owner's Pop-ups switches ----------
    const pops = page => page.evaluate(() => Object.fromEntries([...document.querySelectorAll(".vf-ibpops [role=switch]")].filter(b => !b.hidden).map(b => [b.dataset.k, b.getAttribute("aria-checked") === "true"])));
    await showTab(owner, "notes");
    ok("the owner's Notifications start with Pop-ups: a join, a request for Run and a report on, the rest off", await until(owner, () => !document.querySelector(".vf-ibpops").hidden)
      && JSON.stringify(await pops(owner)) === JSON.stringify({ join: true, run: true, report: true, share: false, merge: false, fail: false, upload: false }), JSON.stringify(await pops(owner)));
    await owner.click(".vf-ibpops [data-k=run]");
    ok("  turning Run off saves it for the owner", await until(owner, () => JSON.stringify(window.Core.state.me.prefs.popups) === JSON.stringify(["join", "report"]), null, 8000));
    await owner.keyboard.press("Escape");
    await owner.evaluate(() => { window.__toasts = []; new MutationObserver(() => { const t = document.querySelector(".vf-toast span")?.textContent; if (t) window.__toasts.push(t); }).observe(document.querySelector(".vf-toast"), { childList: true, characterData: true, subtree: true }); });
    await ann.evaluate(() => window.Core.request("Q2", "ask", "Ann asks with Run's pop-up off"));
    await until(owner, () => window.Core.state.inbox.some(i => i.kind === "run"), null, 10000);
    await owner.waitForTimeout(2500); // a few polls
    ok("  then a request waiting for Run waits in Needs you with no pop-up", await owner.evaluate(() => !window.__toasts.some(t => /Run it from the Inbox|wait on you/.test(t))), JSON.stringify(await owner.evaluate(() => window.__toasts)));

    // #8386: each new thing waiting on the owner pops up while its switch is on: an offered file, a merge request.
    await owner.evaluate(() => window.Core.saveSettings({ uploads: true }));
    await showTab(owner, "notes");
    await owner.click(".vf-ibpops [data-k=upload]");
    await owner.click(".vf-ibpops [data-k=merge]");
    await until(owner, () => ["upload", "merge"].every(k => (window.Core.state.me.prefs.popups || []).includes(k)), null, 8000);
    await owner.keyboard.press("Escape");
    await until(ann, () => window.Core.state.settings.uploads === true);
    await ann.evaluate(() => window.Core.uploadOffer({ file: "plan.txt", size: 12, type: "text/plain" }));
    ok("with Files on, a file Ann offers pops up for the owner", await until(owner, () => window.__toasts.includes("Ann offered a file: plan.txt."), null, 10000), JSON.stringify(await owner.evaluate(() => window.__toasts)));
    await lee.evaluate(p => window.Core.mergeRequest(p), annPid);
    ok("  and so does a merge request, with Merges on", await until(owner, () => window.__toasts.some(t => /^Lee asks to be joined with an earlier name\.|merge requests wait on you|things wait on you/.test(t)), null, 10000), JSON.stringify(await owner.evaluate(() => window.__toasts)));

    // ---------- follow-up 51: the Notifications layout ----------
    await showTab(owner, "notes");
    const sideStill = await settled(owner, { rects: true });
    const side = await owner.evaluate(() => {
      const r = s => document.querySelector(s).getBoundingClientRect(), list = r(".vf-ixnotes > .vf-bptools"), pops = r(".vf-ibside > .vf-ibpops"), box = r(".vf-ibside > .vf-mutebox");
      return { beside: pops.left >= list.right, top: Math.abs(pops.top - list.top) < 40, box: box.height > 0, btn: document.querySelector(".vf-mutebtn").getClientRects().length };
    });
    ok("at 1440 px, Pop-ups and the switches sit in a column beside the messages, open, with no button", sideStill && side.beside && side.top && side.box && side.btn === 0, JSON.stringify({ still: sideStill, ...side }));
    await owner.keyboard.press("Escape");
    const ph = await rec.open(A.localUrl, { context: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true } });
    await joinAs(ph, "Pho");
    await ph.locator(".vf-bell").tap();
    await ph.locator(".vf-ixtabs [data-k=notes]").tap();
    const folded = await ph.evaluate(() => { const shown = s => document.querySelector(s).getClientRects().length > 0, b = document.querySelector(".vf-mutebtn");
      return { pops: shown(".vf-ibpops"), box: shown(".vf-ixnotes .vf-ibside > .vf-mutebox"), label: b.textContent, after: !!(document.querySelector(".vf-nlist").compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING) }; });
    ok("on a phone, the messages come first and one \"Pop-ups and notifications\" button folds both away", !folded.pops && !folded.box && folded.label === "Pop-ups and notifications" && folded.after, JSON.stringify(folded));
    await ph.locator(".vf-mutebtn").tap();
    ok("  tapping it opens Pop-ups and the switches", await until(ph, () => document.querySelector(".vf-ibpops").getClientRects().length > 0 && document.querySelector(".vf-ixnotes .vf-ibside > .vf-mutebox").getClientRects().length > 0));
    await ph.context().close();

    // ---------- round 11: a guest's own pop-ups; F13: the rest waits in the Inbox ----------
    await showTab(ann, "notes");
    ok("a guest's Pop-ups: Claude answered my request, named or mentioned, and a new round, all on", await until(ann, () => !document.querySelector(".vf-ibpops").hidden)
      && JSON.stringify(await pops(ann)) === JSON.stringify({ request: true, mention: true, round: true }), JSON.stringify(await pops(ann)));
    await ann.keyboard.press("Escape");
    await ann.evaluate(() => { window.__toasts = []; new MutationObserver(() => { const t = document.querySelector(".vf-toast span")?.textContent; if (t) window.__toasts.push(t); }).observe(document.querySelector(".vf-toast"), { childList: true, characterData: true, subtree: true }); });
    await lee.evaluate(() => window.Core.chat("@Ann can you look at Q1?"));
    ok("  a mention pops up for her", await until(ann, () => window.__toasts.some(t => /^Lee mentioned you/.test(t)), null, 10000), JSON.stringify(await ann.evaluate(() => window.__toasts)));
    await showTab(ann, "notes");
    await ann.click(".vf-ibpops [data-k=mention]");
    await until(ann, () => JSON.stringify(window.Core.state.me.prefs.popups) === JSON.stringify(["request", "round"]), null, 8000);
    await ann.keyboard.press("Escape");
    await ann.evaluate(() => { window.__toasts = []; });
    await lee.waitForTimeout(1100);
    await lee.evaluate(() => window.Core.chat("@Ann and Q2 too"));
    await until(ann, () => (window.Core.state.me.notifications || []).filter(n => n.kind === "mention").length === 2, null, 10000);
    await ann.waitForTimeout(1500);
    ok("  with Mentions off it waits in the Inbox only", await ann.evaluate(() => !window.__toasts.some(t => /mentioned you/.test(t))), JSON.stringify(await ann.evaluate(() => window.__toasts)));
    // F13: a muted kind never toasts, even for the result of her own proposal.
    await ann.evaluate(() => window.Core.savePrefs({ mute: ["proposal"] }));
    await until(ann, () => (window.Core.state.me.prefs.mute || []).includes("proposal"), null, 8000);
    const MUTED = "Ann proposes one while proposals are muted";
    await ann.evaluate(t => window.Core.idea(t), MUTED);
    await until(owner, t => window.Core.state.ideas.some(i => i.text === t), MUTED, 10000);
    await owner.evaluate(t => window.Core.proposal(window.Core.state.ideas.find(i => i.text === t).id, "question"), MUTED);
    await until(ann, t => window.Core.state.ideas.find(i => i.text === t)?.status !== "new", MUTED, 10000);
    await ann.waitForTimeout(1500);
    ok("  with Proposals muted, her placed proposal does not toast", await ann.evaluate(() => !window.__toasts.some(t => /^Your proposal/.test(t))), JSON.stringify(await ann.evaluate(() => window.__toasts)));

    // ---------- round 11: the owner sets the pop-ups a guest starts with; a guest's own switches win ----------
    const gpops = () => owner.evaluate(() => Object.fromEntries([...document.querySelectorAll(".vf-ibgpops [role=switch]")].map(b => [b.dataset.k, b.getAttribute("aria-checked") === "true"])));
    await showTab(owner, "notes");
    ok("the owner's Notifications show what guests start with: all three on", await until(owner, () => !document.querySelector(".vf-ibgpops").hidden)
      && JSON.stringify(await gpops()) === JSON.stringify({ request: true, mention: true, round: true }), JSON.stringify(await gpops()));
    await owner.click(".vf-ibgpops [data-k=round]");
    ok("  turning a new round off saves it as the session's default", await until(owner, () => JSON.stringify(window.Core.state.settings.guestPopups) === JSON.stringify(["request", "mention"]), null, 8000));
    await owner.keyboard.press("Escape");
    await showTab(lee, "notes");
    ok("  a guest who never changed theirs starts with it off", await until(lee, () => document.querySelector(".vf-ibpops [data-k=round]")?.getAttribute("aria-checked") === "false", null, 8000)
      && JSON.stringify(await pops(lee)) === JSON.stringify({ request: true, mention: true, round: false }), JSON.stringify(await pops(lee)));
    ok("  and has no Guests start with section", await lee.evaluate(() => document.querySelector(".vf-ibgpops").hidden));
    await showTab(ann, "notes");
    ok("  a guest who set their own keeps them", JSON.stringify(await pops(ann)) === JSON.stringify({ request: true, mention: false, round: true }), JSON.stringify(await pops(ann)));
    await lee.keyboard.press("Escape"); await ann.keyboard.press("Escape");

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
