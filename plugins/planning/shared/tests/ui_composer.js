#!/usr/bin/env node
// The composer kit and the follow-ups built on it, against `share.sh ensure-running` with the fake cloudflared:
// unsent chat and Discussion text survives a reload; Ask Claude text belongs to the question it was typed on; the @
// picker works in the Discussion and a comment edit, with Claude first where "@Claude" files a request (chat and
// Discussion) and a picked person posted as a mention; Ctrl + Enter posts a comment, Enter sends chat, Escape cancels a
// comment edit, the counter shows near the limit and the request edit field has its limit (follow-ups 22, 31, F1, F2,
// B1, B3); a poll or pick-many comment goes in with the pick in one step (26); a field the person is not typing in
// never pulls the page back when it repaints (28); and Claude's answer to an ask becomes its asker's own option on a
// choice question, asking first when they had picked (29).
//   node plugins/planning/shared/tests/ui_composer.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the brief (.work/brief-A.md) and the texts this suite writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs, openClaude } = require("./browser_harness");

const T = { q1: "Where should the order summary sit?", q2: "Which default should the cart use?", q3: "Which carrier should we use?",
  q4: "Which lunch spot this Friday?", q5: "Which payment methods should checkout offer?" };
const q = (id, text, format, purpose = "decide") => ({ id, text, alternatives: [], dependsOn: [], purpose, format });
const choice = labels => ({ kind: "choice", options: labels.map((label, i) => ({ id: `opt-${i + 1}`, label })) });
const DESK = { context: { viewport: { width: 1400, height: 900 } } };

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_composer.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_composer"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("composer");
    s.apply(A.dir, [{ op: "set-title", title: "Composer checks" }, { op: "open-round", questions: [
      q("Q1", T.q1, { kind: "text" }), q("Q2", T.q2, { kind: "text" }), q("Q3", T.q3, choice(["Post", "Courier"])),
      q("Q4", T.q4, choice(["Pizza", "Sushi"]), "poll"), q("Q5", T.q5, { kind: "multi", options: [{ id: "opt-1", label: "Card" }, { id: "opt-2", label: "PayPal" }] }),
    ] }]);
    const owner = await rec.open(A.ownerUrl, DESK);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const ann = await rec.open(A.localUrl, DESK);
    await joinAs(ann, "Ann");
    const bo = await rec.open(A.localUrl, DESK);
    await joinAs(bo, "Bo Lee");
    await until(ann, () => Object.values(window.Core.state.people || {}).some(p => p.name === "Bo Lee"));
    const go = async (p, text) => { await p.locator(".vf-q", { hasText: text }).first().click(); return until(p, t => document.querySelector(".vf-qtext")?.textContent === t, text); };
    const openDisc = async p => { if ((await p.getAttribute(".vf-disc-head", "aria-expanded")) !== "true") await p.click(".vf-disc-head"); return until(p, () => !document.querySelector(".vf-disc-body").hidden); };
    const picker = p => p.evaluate(() => { const b = document.querySelector(".vf-mentions"); return b.hidden ? null : [...b.querySelectorAll(".vf-mopt-n")].map(x => x.textContent); });
    const comments = p => p.evaluate(() => (window.Core.state.discussions.Q1 || []).map(c => c.text));

    // ---------- Discussion: @ picker with Claude first, a picked person posts as a mention, Ctrl + Enter posts ----------
    await go(ann, T.q1);
    await openDisc(ann);
    await ann.click(".vf-disc-ta");
    await ann.keyboard.type("@");
    let list = await picker(ann);
    ok("typing @ in a Discussion comment opens the picker with Claude first", list?.[0] === "Claude" && list.length >= 2, JSON.stringify(list));
    await ann.keyboard.press("Enter");
    ok("  and picking Claude inserts the @Claude the server reads", (await ann.inputValue(".vf-disc-ta")) === "@Claude ", await ann.inputValue(".vf-disc-ta"));
    await ann.fill(".vf-disc-ta", "Thanks ");
    await ann.keyboard.type("@B");
    list = await picker(ann);
    ok("  @B lists Bo and not Claude", !!list && !list.includes("Claude") && list.length === 1, JSON.stringify(list));
    await ann.keyboard.press("Enter");
    await ann.keyboard.type("for the idea");
    ok("the comment box shows its send key", await ann.evaluate(() => [...document.querySelectorAll(".vf-disc-form .vf-hint")].some(h => /^(Ctrl|Cmd) \+ Enter to post$/.test(h.textContent))));
    await ann.keyboard.press("Control+Enter");
    ok("Ctrl + Enter posts the comment", await until(ann, () => (window.Core.state.discussions.Q1 || []).some(c => /for the idea/.test(c.text))), JSON.stringify(await comments(ann)));
    ok("  and the picked person shows as a mention in it", await until(bo, () => [...document.querySelectorAll(".vf-cm-txt .vf-mention")].some(m => m.textContent.startsWith("@")))
      || await until(ann, () => [...document.querySelectorAll(".vf-cm .vf-cm-txt .vf-mention")].length > 0));

    // ---------- the counter near the limit ----------
    await ann.waitForTimeout(1100);
    await ann.fill(".vf-disc-ta", "y".repeat(1499));
    const cnt = () => ann.evaluate(() => document.querySelector(".vf-disc-form .vf-count-txt")?.textContent ?? null);
    const before = await cnt();
    await ann.keyboard.type("y");
    ok("the comment counter stays hidden below the last quarter and shows 1500 / 2000 there", before === "" && (await cnt()) === "1500 / 2000", `${before} | ${await cnt()}`);
    await ann.fill(".vf-disc-ta", "");

    // ---------- comment edit: the @ picker (people only) and Escape cancels ----------
    const mine = ann.locator(".vf-disc-list > .vf-cm", { hasText: "for the idea" });
    await mine.locator(".vf-lbtn", { hasText: "Edit" }).click();
    await until(ann, () => !document.querySelector(".vf-cm-edit")?.hidden);
    await ann.focus(".vf-cm-edit textarea");
    await ann.keyboard.press("End");
    await ann.keyboard.type(" @");
    list = await picker(ann);
    ok("a comment edit has the @ picker, without Claude (an edit files no request)", !!list && list.length >= 1 && !list.includes("Claude"), JSON.stringify(list));
    await ann.keyboard.press("Escape");
    ok("  Escape first closes the list", (await picker(ann)) === null && !(await ann.evaluate(() => document.querySelector(".vf-cm-edit").hidden)));
    await ann.keyboard.press("Escape");
    ok("  then cancels the edit", await until(ann, () => document.querySelector(".vf-cm-edit").hidden));

    // ---------- chat: Claude first, Enter sends ----------
    await ann.click(".vf-fab");
    await ann.click(".vf-minput");
    await ann.keyboard.type("@");
    list = await picker(ann);
    ok("typing @ in chat lists Claude first", list?.[0] === "Claude", JSON.stringify(list));
    await ann.keyboard.press("Escape");
    await ann.fill(".vf-minput", "");
    await ann.keyboard.type("Hello from chat");
    await ann.keyboard.press("Enter");
    ok("Enter sends a chat message", await until(ann, () => (window.Core.state.chat || []).some(m => m.text === "Hello from chat")));

    // ---------- drafts: chat and Discussion survive a reload; Ask Claude text stays with its question ----------
    await ann.fill(".vf-minput", "An unsent chat line");
    await ann.click(".vf-fab");
    await ann.fill(".vf-disc-ta", "An unsent comment on Q1");
    await ann.click(".vf-askbtn");
    await until(ann, () => !document.querySelector(".vf-askform").hidden);
    await ann.fill("#vf-ask-ta", "Ask typed on Q1");
    await go(ann, T.q2);
    ok("Ask Claude text typed on Q1 does not show on Q2", (await ann.inputValue("#vf-ask-ta")) === "", await ann.inputValue("#vf-ask-ta"));
    ok("  nor does Q1's comment", (await ann.inputValue(".vf-disc-ta")) === "");
    await go(ann, T.q1);
    ok("back on Q1 its Ask Claude text is there", (await ann.inputValue("#vf-ask-ta")) === "Ask typed on Q1", await ann.inputValue("#vf-ask-ta"));
    await ann.reload();
    await until(ann, () => !!window.Core.snapshot()?.me);
    await go(ann, T.q1);
    ok("after a reload the unsent chat line is back", await until(ann, () => document.querySelector(".vf-minput").value === "An unsent chat line"), await ann.inputValue(".vf-minput"));
    ok("  and so is the unsent comment on Q1", await until(ann, () => document.querySelector(".vf-disc-ta").value === "An unsent comment on Q1"), await ann.inputValue(".vf-disc-ta"));
    ok("  and the Ask Claude text on Q1", (await ann.inputValue("#vf-ask-ta")) === "Ask typed on Q1", await ann.inputValue("#vf-ask-ta"));

    // ---------- a request's edit field has its limit ----------
    await ann.evaluate(() => window.Core.request("Q2", "ask", "Which cart default do the big shops use?"));
    await until(owner, () => (window.Core.state.requests || []).some(r => r.status === "pending"));
    await owner.click(".vf-bell");
    await owner.click(".vf-ixtabs [data-k=needs]");
    const row = owner.locator(".vf-ibneeds .vf-ritem", { hasText: "big shops" });
    await row.locator(".vf-acts button", { hasText: "Edit" }).click();
    const req = await row.evaluate(li => { const t = li.querySelector("textarea"); return { max: t.maxLength, pop: t.getAttribute("aria-haspopup") }; });
    ok("the host's request edit field takes at most 2000 characters and has the @ picker", req.max === 2000 && req.pop === "listbox", JSON.stringify(req));
    await row.locator("textarea").press("Escape");
    ok("  and Escape cancels that edit", await until(owner, () => [...document.querySelectorAll(".vf-ibneeds .vf-ritem")].some(li => /big shops/.test(li.textContent) && li.querySelector("textarea").hidden)));
    await owner.keyboard.press("Escape");

    // ---------- 26: the comment goes in with the pick, in one step ----------
    const sends = [];
    bo.on("request", r => { const p = new URL(r.url()).pathname; if (["/api/pick", "/api/answer"].includes(p)) sends.push(p); });
    await go(bo, T.q4);
    ok("on a poll the comment box works before the pick", await bo.evaluate(() => !document.getElementById("vf-answer").disabled));
    await bo.fill("#vf-answer", "Sushi is close to the office", { timeout: 5000 }).catch(() => {});
    await bo.locator(".vf-opt", { hasText: "Sushi" }).locator(".vf-optchoose").click();
    const myCard = (p, qid) => p.evaluate(([qq]) => (window.Core.snapshot().cards?.[qq] || []).find(c => c.ref === "p:" + window.Core.me.pid), [qid]);
    ok("  picking sends the pick and the comment together", await until(owner, () => (window.Core.snapshot().cards?.Q4 || []).some(c => c.pick === "opt-2" && c.text === "Sushi is close to the office")), JSON.stringify(await myCard(bo, "Q4")));
    ok("  in one request", sends.join() === "/api/pick", sends.join());
    sends.length = 0;
    await go(bo, T.q5);
    ok("on a pick-many question the comment box works before the pick", await bo.evaluate(() => !document.getElementById("vf-answer").disabled));
    await bo.fill("#vf-answer", "Both are common here", { timeout: 5000 }).catch(() => {});
    for (const label of ["Card", "PayPal"]) await bo.locator(".vf-check-row", { hasText: label }).locator("input").check();
    await bo.click(".vf-fmt-save", { timeout: 5000 }).catch(() => {});
    ok("  saving the picks sends the comment with them", await until(owner, () => (window.Core.snapshot().cards?.Q5 || []).some(c => JSON.stringify(c.picks) === '["opt-1","opt-2"]' && c.text === "Both are common here")), JSON.stringify(await myCard(bo, "Q5")));
    ok("  in one request", sends.join() === "/api/pick", sends.join());

    // ---------- 28: a repaint does not pull the page back to a focused field ----------
    const small = await rec.open(A.localUrl, { context: { viewport: { width: 1200, height: 520 } } });
    await joinAs(small, "Cy");
    await go(small, T.q1);
    await small.click(".vf-askbtn", { timeout: 5000 }).catch(() => {});
    await until(small, () => !document.querySelector(".vf-askform").hidden);
    await small.click("#vf-ask-ta", { timeout: 5000 }).catch(() => {});
    await small.keyboard.type("Reading the question first");
    await small.waitForTimeout(1200);
    const top = await small.evaluate(() => { const sc = document.getElementById("vf-ask-ta").closest(".vf-scroll"); sc.scrollTop = 0; return sc.scrollTop; });
    await owner.evaluate(() => window.Core.chat("A message that repaints every page"));
    await until(small, () => (window.Core.state.chat || []).some(m => m.text === "A message that repaints every page"));
    await small.waitForTimeout(400);
    const after = await small.evaluate(() => ({ top: (document.getElementById("vf-ask-ta").closest(".vf-scroll")).scrollTop, focused: document.activeElement?.id }));
    ok("scrolled up to read, a repaint leaves the page where the person put it, focus kept", top === 0 && after.top === 0 && after.focused === "vf-ask-ta", JSON.stringify(after));
    await small.keyboard.type(" more");
    const typed = await small.evaluate(() => { const f = document.getElementById("vf-ask-ta"), r = f.getBoundingClientRect(); return r.bottom > 0 && r.top < innerHeight; });
    ok("  and typing again brings the field back into view", typed);

    // ---------- 29: Use as my answer ----------
    const ASK = "Which carrier is cheapest for small parcels?", ANS = "Post: it is cheapest for parcels under 2 kg.";
    await ann.evaluate(t => window.Core.request("Q3", "ask", t), ASK);
    const rid = await owner.evaluate(async t => {
      for (let i = 0; i < 50 && !(window.Core.state.requests || []).some(r => r.text === t); i++) await new Promise(r => setTimeout(r, 100));
      return (window.Core.state.requests || []).find(r => r.text === t)?.id;
    }, ASK);
    await owner.evaluate(id => window.Core.requestAct(id, "run"), rid);
    s.apply(A.dir, [{ op: "result", qid: "Q3", request: rid, kind: "ask", summary: ANS, sources: [], report: "", used: [], why: "" }]);
    await go(ann, T.q3);
    await until(ann, a => (window.Core.state.research.Q3 || []).some(x => x.summary === a), ANS, 10000);
    await openClaude(ann);
    const useBtn = p => p.locator(".vf-res", { hasText: ANS }).locator(".vf-res-use button");
    ok("the asker sees Use as my answer on Claude's answer", await until(ann, a => [...document.querySelectorAll(".vf-res")].some(li => li.textContent.includes(a) && !li.querySelector(".vf-res-use").hidden), ANS));
    await go(bo, T.q3);
    await until(bo, a => (window.Core.state.research.Q3 || []).some(x => x.summary === a), ANS, 10000);
    await openClaude(bo);
    ok("  nobody else does", await until(bo, a => [...document.querySelectorAll(".vf-res")].some(li => li.textContent.includes(a) && li.querySelector(".vf-res-use").hidden), ANS));
    await useBtn(ann).click({ timeout: 5000 }).catch(() => {});
    ok("with no pick yet, one click opens her own option holding Claude's answer, focused", await until(ann, a => { const t = document.getElementById("vf-other"); return !!t?.offsetParent && t.value === a && document.activeElement === t; }, ANS));
    ok("  and asks nothing first", !(await ann.evaluate(() => document.querySelector("dialog.vf-cdlg")?.open)));
    await ann.fill("#vf-other", "Post, under 2 kg", { timeout: 5000 }).catch(() => {});
    await ann.click(".vf-other-save", { timeout: 5000 }).catch(() => {});
    ok("  saving makes the edited text her pick, as her own option", await until(owner, () => (window.Core.snapshot().cards?.Q3 || []).some(c => c.pick === "other" && c.text === "Post, under 2 kg")));
    // Bo picks, then asks: Use as my answer asks before replacing his pick
    await bo.locator(".vf-opt", { hasText: "Courier" }).locator(".vf-optchoose").click();
    await until(owner, () => (window.Core.snapshot().cards?.Q3 || []).some(c => c.pick === "opt-2"));
    ok("others (Bo, once he picked) can back it like any own option", await until(bo, () => [...document.querySelectorAll(".vf-card, .vf-opt")].some(c => c.textContent.includes("Post, under 2 kg")
      && !!c.querySelector('[aria-label^="Back this option"]'))), await bo.evaluate(() => [...document.querySelectorAll(".vf-card, .vf-opt")].filter(c => c.textContent.includes("Post, under 2 kg")).map(c => c.className + ": " + [...c.querySelectorAll("button")].map(b => b.getAttribute("aria-label") || b.textContent).join("/")).join(" | ")));
    const ASK2 = "Is a courier worth it?", ANS2 = "Only for same-day orders.";
    await bo.waitForTimeout(1100);
    await bo.evaluate(t => window.Core.request("Q3", "ask", t), ASK2);
    const rid2 = await owner.evaluate(async t => {
      for (let i = 0; i < 50 && !(window.Core.state.requests || []).some(r => r.text === t); i++) await new Promise(r => setTimeout(r, 100));
      return (window.Core.state.requests || []).find(r => r.text === t)?.id;
    }, ASK2);
    await owner.evaluate(id => window.Core.requestAct(id, "run"), rid2);
    s.apply(A.dir, [{ op: "result", qid: "Q3", request: rid2, kind: "ask", summary: ANS2, sources: [], report: "", used: [], why: "" }]);
    await until(bo, a => (window.Core.state.research.Q3 || []).some(x => x.summary === a), ANS2, 10000);
    await bo.locator(".vf-res", { hasText: ANS2 }).locator(".vf-res-use button").click({ timeout: 5000 }).catch(() => {});
    ok("with a pick already, Use as my answer asks before replacing it", await until(bo, () => document.querySelector("dialog.vf-cdlg")?.open && /Replace your pick/.test(document.querySelector("dialog.vf-cdlg").textContent)));
    await bo.click("dialog.vf-cdlg[open] .vf-btn-primary", { timeout: 5000 }).catch(() => {});
    ok("  confirming opens his own option with Claude's answer", await until(bo, a => document.getElementById("vf-other")?.value === a, ANS2));
    await bo.click(".vf-other-save", { timeout: 5000 }).catch(() => {});
    ok("  and saving moves his pick to it", await until(owner, a => (window.Core.snapshot().cards?.Q3 || []).some(c => c.pick === "other" && c.text === a), ANS2));

    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite runs to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally {
    await browser.close();
  }
  return s.finish();
}
main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
