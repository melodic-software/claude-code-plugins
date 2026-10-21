#!/usr/bin/env node
// Asking Claude about the whole session (follow-up item 4), against `share.sh ensure-running` with the fake
// cloudflared: the chat composer says @Claude sends a message to Claude; such a message says Sent to Claude and waits
// for the host's Run; the Inbox lists it under General, never a question id, and its toasts say "about the session";
// the host shares Claude's answer from Ask Claude's General thread, and it then replies to the message in every
// chat, a 390-wide phone's included; Ask Claude's picker offers "About the whole session" first, with no "Run it on my
// own Claude"; the top Ask Claude opens on it, Reply on Claude's answer quotes it in a new ask, and Move to puts the
// asker's own request on a question (R26, R27).
//   node plugins/planning/shared/tests/ui_general.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the approved spec (follow-up item 4) and the texts this suite writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const ASK = "@Claude what have we settled so far?", ANSWER = "The summary stays pinned; the copy is still open.";
const PICK_ASK = "Which questions did nobody answer?";
const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });
const PHONE = { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true };

const openChat = async page => { if (await page.evaluate(() => document.querySelector(".vf-chat").hidden)) await page.click(".vf-fab"); return until(page, () => !document.querySelector(".vf-chat").hidden); };
const openInbox = async page => { if (await page.evaluate(() => document.querySelector(".vf-inboxpage").hidden)) await page.click(".vf-bell"); return until(page, () => !document.querySelector(".vf-inboxpage").hidden); };
/** The Inbox page on one tab (needs, mine, notes, history). */
const showTab = async (page, k) => { await openInbox(page); await page.click(`.vf-ixtabs [data-k=${k}]`); return until(page, x => document.querySelector(`.vf-ixtabs [data-k=${x}]`)?.getAttribute("aria-pressed") === "true", k); };
const toast = (page, re) => until(page, src => new RegExp(src).test(document.querySelector(".vf-toast.vf-on span")?.textContent || ""), re.source, 10000);
const msg = (page, text) => page.locator(".vf-msg", { hasText: text });

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_general.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_general"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("general");
    s.apply(A.dir, [{ op: "set-title", title: "General asks" }, { op: "open-round", questions: [q("Q1", "Where should the order summary sit?")] }]);
    const desk = { context: { viewport: { width: 1440, height: 900 } } };
    const owner = await rec.open(A.ownerUrl, desk);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    // This suite follows the host's Share of a guest's general ask: the session reviews answers first.
    await owner.evaluate(() => window.Core.saveSettings({ reviewAnswers: true }));
    const ann = await rec.open(A.localUrl, desk);
    await joinAs(ann, "Ann");
    const bo = await rec.open(A.localUrl, { context: PHONE });
    await joinAs(bo, "Bo");

    // ---------- the chat composer says what @Claude does ----------
    await openChat(ann);
    const hint = await ann.evaluate(() => { const h = document.querySelector(".vf-mhint"); return { text: h?.textContent, shown: !!h && !h.hidden && h.offsetParent !== null,
      described: document.querySelector(".vf-minput").getAttribute("aria-describedby") === h?.id }; });
    ok("the chat composer says Type @Claude to send it to Claude", hint.text === "Type @Claude to send it to Claude." && hint.shown && hint.described, JSON.stringify(hint));

    // ---------- @Claude in chat: sent to Claude, waiting on the host ----------
    await ann.fill(".vf-minput", ASK);
    await ann.click(".vf-mform button[type=submit]");
    ok("sending it says it went to Claude and runs once the host presses Run", await toast(ann, /^Sent, and sent to Claude\. It runs once the host presses Run\.$/));
    ok("Ann's message reads Sent to Claude · Waiting for the host", await until(ann, t => [...document.querySelectorAll(".vf-msg")].some(li => li.textContent.includes(t)
      && li.querySelector(".vf-msent:not([hidden])")?.textContent === "Sent to Claude · Waiting for the host"), ASK));
    await showTab(ann, "mine");
    const row = await ann.evaluate(() => { const li = document.querySelector(".vf-ixmine .vf-ixlist > li"); const qEl = li?.querySelector(".vf-ixq");
      return li && { q: qEl.textContent, gen: qEl.classList.contains("vf-ixgen"), shown: !qEl.hidden, label: li.querySelector(".vf-ixitem").getAttribute("aria-label") }; });
    ok("Ann's Inbox lists it under General, not a question id", !!row && row.q === "General" && row.gen && row.shown && /^General\. /.test(row.label), JSON.stringify(row));
    await ann.keyboard.press("Escape");
    ok("the host is told Ann asked Claude about the session", await toast(owner, /^Ann asked Claude about the session\. Run it from the Inbox\.$/));
    const rid = await owner.evaluate(async t => {
      for (let i = 0; i < 50 && !(window.Core.state.requests || []).some(r => r.text === t); i++) await new Promise(r => setTimeout(r, 100));
      return (window.Core.state.requests || []).find(r => r.text === t);
    }, ASK);
    ok("the host's queue holds it waiting, with no question", !!rid && rid.status === "pending" && rid.qid === "", JSON.stringify(rid));
    await owner.locator(".vf-seg-btn", { hasText: /^Host$/ }).click();
    ok("the host's Run card labels it General", await until(owner, t => [...document.querySelectorAll(".vf-qitem[data-t=request]")].some(li => li.textContent.includes(t.slice(8)) && li.querySelector(".vf-qref:not([hidden])")?.textContent === "General"), ASK));

    // ---------- Run, Claude's answer, the host's Share: it replies in chat ----------
    await owner.evaluate(id => window.Core.requestAct(id, "run"), rid.id);
    s.apply(A.dir, [{ op: "result", request: rid.id, kind: "ask", summary: ANSWER, sources: [], report: "", used: [], why: "" }]);
    ok("the answer waits on the host's Share in the Inbox, with no pop-up", await until(owner, () => window.Core.state.inbox.some(i => i.kind === "share"), null, 10000)
      && await owner.evaluate(() => !/Share it from the Inbox/.test(document.querySelector(".vf-toast span")?.textContent || "")));
    ok("before the Share no guest's page holds the answer", !(await ann.evaluate(a => JSON.stringify(window.Core.snapshot()).includes(a), ANSWER)));
    await showTab(owner, "needs");
    await owner.locator(".vf-ibneeds .vf-revlist > li", { hasText: ANSWER }).locator(".vf-rev-open").click();
    ok("opening it shows the answer in Ask Claude, About the whole session", await until(owner, a => !document.querySelector(".vf-drawer").hidden
      && document.querySelector(".vf-apq select").value === "session" && [...document.querySelectorAll(".vf-apgen .vf-res")].some(li => li.textContent.includes(a)), ANSWER));
    await owner.locator(".vf-apgen .vf-res", { hasText: ANSWER }).locator("button", { hasText: "Share with everyone" }).click();
    for (const [who, page] of [["Ann", ann], ["Bo's phone", bo]]) {
      await openChat(page);
      ok(`${who}: Claude's answer replies to Ann's message in chat`, await until(page, ([a, t]) => [...document.querySelectorAll(".vf-msg.vf-msg-claude")].some(li =>
        li.querySelector(".vf-msg-name").textContent === "Claude" && li.textContent.includes(a) && li.querySelector(".vf-mquote-t")?.textContent === t), [ANSWER, ASK], 10000));
    }
    ok("Ann is told Claude answered her request about the session", await toast(ann, /^Claude answered your request about the session$/));
    ok("  and her message now reads Sent to Claude · Answered", await until(ann, t => [...document.querySelectorAll(".vf-msg")].some(li => li.textContent.includes(t)
      && li.querySelector(".vf-msent")?.textContent === "Sent to Claude · Answered"), ASK));
    // ---------- a shared answer whose chat message chat no longer keeps still opens, in Ask Claude ----------
    // Ann's page reads the answer's message as one the server never kept, so GET /api/chat?around= answers 404.
    // A poll still in flight when the page reloads is aborted under the handler, so fetch or fulfill can throw.
    const lostMsg = async route => {
      try {
        const res = await route.fetch(), body = await res.text();
        let j; try { j = JSON.parse(body); } catch { return await route.fulfill({ response: res, body }); }
        for (const x of j.results?.session || []) if (x.msg) x.msg = "M999999";
        await route.fulfill({ response: res, body: JSON.stringify(j) });
      } catch { /* the request was aborted or already answered */ }
    };
    await ann.route(/\/api\/state\?/, lostMsg);
    await ann.reload();
    await until(ann, () => (window.Core.state.research.session || []).some(x => x.msg === "M999999"), null, 10000);
    await showTab(ann, "mine");
    await ann.locator(".vf-ixmine .vf-ixlist > li", { hasText: ASK }).locator(".vf-ixitem").click();
    ok("opening it from the Inbox shows the answer in Ask Claude", await until(ann, a => !document.querySelector(".vf-drawer").hidden
      && [...document.querySelectorAll(".vf-apgen .vf-res")].some(li => li.textContent.includes(a)), ANSWER, 10000));
    await ann.keyboard.press("Escape");
    await ann.unroute(/\/api\/state\?/);
    await ann.reload();
    await until(ann, () => !!window.Core.snapshot()?.me);

    const fit = await bo.evaluate(() => ({ page: document.documentElement.scrollWidth, w: innerWidth,
      rows: [...document.querySelectorAll(".vf-msg-claude")].every(li => li.getBoundingClientRect().right <= innerWidth) }));
    ok("390: Claude's message fits and nothing scrolls sideways", fit.page <= fit.w && fit.rows, JSON.stringify(fit));

    // ---------- Ask Claude's picker: About the whole session ----------
    await ann.click(".vf-asktop");
    await until(ann, () => !document.querySelector(".vf-drawer").hidden);
    ok("the top Ask Claude opens about the whole session (R26)", await until(ann, () => document.querySelector(".vf-apq select").value === "session"));
    const first = await ann.evaluate(() => { const o = document.querySelector(".vf-apq select").options[0]; return { value: o.value, text: o.textContent }; });
    ok("the picker's first option is About the whole session", first.value === "session" && first.text === "About the whole session", JSON.stringify(first));
    await ann.selectOption(".vf-apq select", "session");
    ok("  which offers no Run it on my own Claude", await until(ann, () => document.querySelector(".vf-apself").hidden));
    // ---------- Reply on Claude's answer: a new ask about the whole session quoting it (R27) ----------
    await ann.locator(".vf-apgen .vf-res", { hasText: ANSWER }).locator(".vf-res-reply").click();
    ok("Reply opens an ask quoting Claude's answer, about the whole session", await until(ann, a => document.querySelector("#vf-ap-ta").value === `About Claude's answer: "${a}"\n\n`
      && document.querySelector(".vf-apq select").value === "session", ANSWER), await ann.inputValue("#vf-ap-ta"));
    await ann.waitForTimeout(1100);
    await ann.fill("#vf-ap-ta", PICK_ASK);
    await ann.click(".vf-apform button[type=submit]");
    ok("sending it files a request with no question", await until(ann, t => (window.Core.state.myRequests || []).some(r => r.text === t && r.qid === ""), PICK_ASK));
    ok("  listed under Your requests as General", await until(ann, t => [...document.querySelectorAll(".vf-apreqs > li")].some(li => li.textContent.includes(t) && li.querySelector(".vf-qref").textContent === "General"), PICK_ASK));
    // ---------- Move to: Ann puts her own request on Q1 (R27) ----------
    await ann.locator(".vf-apreqs > li", { hasText: PICK_ASK }).locator(".vf-req-move select").selectOption("Q1");
    ok("Move to puts Ann's request on Q1", await until(ann, t => (window.Core.state.myRequests || []).some(r => r.text === t && r.qid === "Q1"), PICK_ASK));
    ok("  and its row names Q1", await until(ann, t => [...document.querySelectorAll(".vf-apreqs > li")].some(li => li.textContent.includes(t) && li.querySelector(".vf-qref").textContent.startsWith("Q1:")), PICK_ASK));
    ok("Bo's page holds no Move to for Ann's request", await bo.evaluate(t => ![...document.querySelectorAll("li")].some(li => li.textContent.includes(t) && li.querySelector(".vf-req-move:not([hidden])")), PICK_ASK));
    // ---------- Move to: once the host takes up her request, only the host can move it ----------
    const pickId = await ann.evaluate(t => window.Core.state.myRequests.find(r => r.text === t).id, PICK_ASK);
    await owner.evaluate(id => window.Core.requestAct(id, "decline"), pickId);
    ok("the host declines Ann's request", await until(ann, id => window.Core.state.myRequests.find(r => r.id === id)?.status === "declined", pickId));
    ok("  and her row holds no Move to", await until(ann, t => [...document.querySelectorAll(".vf-apreqs > li")].some(li => li.textContent.includes(t)
      && li.querySelector(".vf-req-move")?.hidden), PICK_ASK), await ann.evaluate(t => [...document.querySelectorAll(".vf-apreqs > li")].find(li => li.textContent.includes(t))?.outerHTML.slice(0, 300), PICK_ASK));

    // ---------- a reply to Claude's answer quotes Claude ----------
    await ann.keyboard.press("Escape");
    await openChat(ann);
    ok("Ann's chat holds Claude's answer after the reload", await until(ann, a => (window.Core.state.chat || []).some(m => m.claude && m.text === a), ANSWER, 10000));
    const cmid = await ann.evaluate(a => window.Core.state.chat.find(m => m.claude && m.text === a)?.id, ANSWER);
    await ann.evaluate(id => window.Core.chat("Thanks, Claude", id), cmid);
    ok("Bo sees a reply to Claude's answer quoting Claude, not the host", await until(bo, () => [...document.querySelectorAll(".vf-msg")].some(li =>
      li.textContent.includes("Thanks, Claude") && li.querySelector(".vf-mquote-n")?.textContent === "Claude"), null, 10000));

    // ---------- with chat off, the page says the answer shows in Ask Claude ----------
    await owner.evaluate(() => window.Core.saveSettings({ chat: false }));
    await until(owner, () => window.Core.state.settings.chat === false);
    // the first Escape takes an urgent pop-up away when one shows (Q39); Ask Claude closes on the next
    for (let i = 0; i < 3 && await owner.evaluate(() => !document.querySelector(".vf-drawer").hidden); i++) await owner.keyboard.press("Escape");
    await owner.click(".vf-asktop");
    await owner.selectOption(".vf-apq select", "session");
    ok("about the whole session Ask Claude starts on Just me", await until(owner, () => document.querySelector(".vf-apform .vf-aud [aria-pressed=true]")?.textContent === "Just me"));
    await owner.click(".vf-apform .vf-aud [data-aud=everyone]");
    ok("chat off: Ask Claude says the answer shows in Ask Claude, About the whole session", await until(owner, () =>
      [...document.querySelectorAll(".vf-apform .vf-pop-note")].some(p => p.textContent === "Claude runs it now and the answer shows in Ask Claude, About the whole session for everyone.")));
    await owner.fill("#vf-ap-ta", "Where are we, with chat off?");
    await owner.click(".vf-apform button[type=submit]");
    ok("  and sending says so too", await toast(owner, /^Sent to Claude\. The answer shows in Ask Claude, About the whole session and in your Inbox\.$/));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
