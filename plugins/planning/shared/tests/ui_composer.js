#!/usr/bin/env node
// The composer kit and the follow-ups built on it, against `share.sh ensure-running` with the fake cloudflared:
// unsent chat and Discussion text survives a reload; Ask Claude text belongs to the question it was typed on; the @
// picker works in the Discussion and a comment edit, with Claude first where "@Claude" files a request (chat and
// Discussion) and a picked person posted as a mention; Ctrl + Enter posts a comment, also with the @ list open, Enter
// sends chat, Escape cancels a comment edit, the counter shows near the limit, the request edit field has its limit and
// a pasted answer from one's own Claude is never cut (follow-ups 22, 31, F1, F2, B1, B3); a poll or pick-many comment,
// and its files, go in with the pick in one step, on a phone too, keeping text typed while the pick is on its way
// (26), a save held back by a file still waiting for the host keeping the picks; a field the person is not typing in never pulls the page back when it repaints (28); Claude's answer to an ask
// becomes its asker's own option on a choice question, asking first when they had picked, Cancel putting the picks back, never cutting a long answer, never once taken down or
// while it is their own Claude's unshared answer (29); and unsent text comes back only to whoever wrote it.
//   node plugins/planning/shared/tests/ui_composer.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the brief (.work/brief-A.md), the review round (.work/review-round-1.md) and the texts this
// suite writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs, openClaude } = require("./browser_harness");

const T = { q1: "Where should the order summary sit?", q2: "Which default should the cart use?", q3: "Which carrier should we use?",
  q4: "Which lunch spot this Friday?", q5: "Which payment methods should checkout offer?", q6: "Rank the delivery options" };
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
      q("Q6", T.q6, { kind: "rank", options: [{ id: "opt-1", label: "Fast" }, { id: "opt-2", label: "Cheap" }, { id: "opt-3", label: "Green" }] }),
    ] }]);
    const owner = await rec.open(A.ownerUrl, DESK);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const ann = await rec.open(A.localUrl, DESK);
    await joinAs(ann, "Ann");
    const bo = await rec.open(A.localUrl, DESK);
    const boPid = await joinAs(bo, "Bo Lee");
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
    ok("  and the picked person is stored as Bo's mention token in it", await until(ann, t => (window.Core.snapshot().discussions?.Q1 || []).some(c => c.text.includes(t)), `<@${boPid}>`),
      JSON.stringify(await ann.evaluate(() => (window.Core.snapshot().discussions?.Q1 || []).map(c => c.text))));
    ok("  and shows in it as a mention of Bo", await until(ann, () => [...document.querySelectorAll(".vf-disc-list .vf-cm-txt .vf-mention")].some(m => m.textContent.startsWith("@Bo"))),
      await ann.evaluate(() => [...document.querySelectorAll(".vf-disc-list .vf-cm-txt")].map(t => t.innerHTML).join(" | ")));

    // ---------- Ctrl + Enter with the @ list open closes it and posts ----------
    await ann.waitForTimeout(1100);
    await ann.fill(".vf-disc-ta", "Ping ");
    await ann.keyboard.type("@B");
    const opened = !!(await picker(ann));
    await ann.keyboard.press("Control+Enter");
    ok("Ctrl + Enter with the @ list open closes the list and posts the comment", opened && await until(ann, () => document.querySelector(".vf-mentions").hidden
      && (window.Core.state.discussions.Q1 || []).some(c => c.text === "Ping @B")), JSON.stringify({ opened, list: await picker(ann), comments: await comments(ann) }));

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
    await mine.locator(".vf-cm-more").click();
    await ann.locator(".vf-msgmenu [role=menuitem]", { hasText: "Edit" }).click();
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
    // scrolled to the top, the field sits below what the scroller shows, so a pull back to it would move scrollTop
    const top = await small.evaluate(() => {
      const f = document.getElementById("vf-ask-ta"), sc = f.closest(".vf-scroll"); sc.scrollTop = 0;
      const r = f.getBoundingClientRect(), S = sc.getBoundingClientRect();
      return { top: sc.scrollTop, out: r.top >= S.bottom || r.bottom <= S.top };
    });
    ok("scrolled up to read, the Ask Claude field is out of view", top.top === 0 && top.out, JSON.stringify(top));
    await owner.evaluate(() => window.Core.chat("A message that repaints every page"));
    await until(small, () => (window.Core.state.chat || []).some(m => m.text === "A message that repaints every page"));
    await small.waitForTimeout(400);
    const after = await small.evaluate(() => ({ top: (document.getElementById("vf-ask-ta").closest(".vf-scroll")).scrollTop, focused: document.activeElement?.id }));
    ok("scrolled up to read, a repaint leaves the page where the person put it, focus kept", after.top === 0 && after.focused === "vf-ask-ta", JSON.stringify(after));
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

    // ---------- S3: no Use as my answer on an answer taken down, or on my own Claude's answer not yet shared ----------
    const useHidden = (p, a) => until(p, t => [...document.querySelectorAll(".vf-res")].some(li => li.textContent.includes(t) && li.querySelector(".vf-res-use").hidden), a);
    await owner.evaluate(id => window.Core.requestAct(id, "takedown"), rid2);
    await until(bo, a => (window.Core.state.research.Q3 || []).some(x => x.summary === a && x.takenDown), ANS2, 10000);
    ok("the asker gets no Use as my answer on an answer the host took down", await useHidden(bo, ANS2),
      await bo.evaluate(a => [...document.querySelectorAll(".vf-res")].filter(li => li.textContent.includes(a)).map(li => li.querySelector(".vf-res-use").hidden).join(), ANS2));
    const OWN = "My own Claude says Post.";
    await ann.waitForTimeout(1100);
    const ownId = await ann.evaluate(async a => {
      const { id } = await window.Core.request("Q3", "ask", "Which carrier, per my own Claude?", undefined, "self");
      await window.Core.myClaim(id);
      await window.Core.myResult(id, { summary: a, sources: [], report: "", used: [], why: "Pasted back from my own Claude." });
      return id;
    }, OWN);
    await until(ann, a => (window.Core.state.research.Q3 || []).some(x => x.summary === a && x.own && !x.published), OWN, 10000);
    ok("  nor on her own Claude's answer the host has not shared", !!ownId && await useHidden(ann, OWN),
      await ann.evaluate(a => [...document.querySelectorAll(".vf-res")].filter(li => li.textContent.includes(a)).map(li => li.querySelector(".vf-res-use").hidden).join(), OWN));

    // ---------- C5: a pasted answer from my own Claude is never cut; Post says how much to shorten ----------
    await ann.waitForTimeout(1100);
    await ann.evaluate(() => window.Core.request("Q3", "ask", "A long one for my own Claude", undefined, "self"));
    await ann.keyboard.press("Escape");
    if (await ann.evaluate(() => document.querySelector(".vf-apform")?.offsetParent === null)) await ann.click(".vf-asktop");
    const longItem = ann.locator(".vf-apreq", { hasText: "A long one for my own Claude" });
    await longItem.locator(".vf-self-paste").click();
    await longItem.locator(".vf-selfform textarea").focus();
    await ann.keyboard.insertText("x".repeat(9000));
    const kept = (await longItem.locator(".vf-selfform textarea").inputValue()).length;
    await longItem.locator(".vf-selfform button[type=submit]").click();
    ok("a pasted 9000-character answer from my own Claude stays whole, and Post asks to shorten it to 4000", kept === 9000
      && await until(ann, () => /Shorten it to 4000 characters; it has 9000\./.test(document.querySelector(".vf-toast.vf-on span")?.textContent || "")), kept);
    await ann.keyboard.press("Escape");

    // ---------- 26: a comment typed while the pick is on its way stays (C3) ----------
    const di = await rec.open(A.localUrl, DESK);
    await joinAs(di, "Di");
    await go(di, T.q4);
    await di.fill("#vf-answer", "First thought");
    let release, held = false;
    const gate = new Promise(r => { release = r; });
    await di.route("**/api/pick", async r => { held = true; await gate; await r.continue(); });
    await di.locator(".vf-opt", { hasText: "Pizza" }).locator(".vf-optchoose").click();
    for (let i = 0; i < 50 && !held; i++) await di.waitForTimeout(100);
    await di.focus("#vf-answer");
    await di.keyboard.press("End");
    await di.keyboard.type(" and more");
    release();
    await until(owner, () => (window.Core.snapshot().cards?.Q4 || []).some(c => c.pick === "opt-1" && c.text === "First thought"));
    await di.waitForTimeout(300);
    await di.unroute("**/api/pick");
    ok("text typed while the pick with its comment is on its way stays in the box", held && (await di.inputValue("#vf-answer")) === "First thought and more", `${held} ${await di.inputValue("#vf-answer")}`);

    // ---------- 26 on a phone: Save before the pick closes the sheet and keeps the comment (C1) ----------
    const PHONE = { context: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true } };
    const gus = await rec.open(A.localUrl, PHONE);
    await joinAs(gus, "Gus");
    await gus.locator(".vf-tab", { hasText: "Questions" }).click();
    await gus.locator(".vf-q", { hasText: T.q4 }).first().click();
    if (!(await gus.locator(".vf-qtext").isVisible())) await gus.locator(".vf-tab", { hasText: "Answer" }).click();
    await until(gus, t => document.querySelector(".vf-qtext")?.textContent === t, T.q4);
    await gus.locator("#vf-answer").tap();
    const sheetOpen = await until(gus, () => !!document.querySelector(".vf-composer-sheet"));
    await gus.keyboard.insertText("Typed on my phone");
    await gus.locator(".vf-sheetsave").tap();
    ok("on a phone, Save before the pick closes the sheet so the options show, the comment kept", sheetOpen && await until(gus, () => !document.querySelector(".vf-composer-sheet")
      && document.getElementById("vf-answer").value === "Typed on my phone" && !!document.querySelector(".vf-opt .vf-optchoose")?.offsetParent),
      JSON.stringify(await gus.evaluate(() => ({ sheet: !!document.querySelector(".vf-composer-sheet"), value: document.getElementById("vf-answer").value }))));
    await gus.locator(".vf-opt", { hasText: "Sushi" }).locator(".vf-optchoose").tap({ timeout: 5000 }).catch(() => {});
    ok("  and the pick takes the comment with it", await until(owner, () => (window.Core.snapshot().cards?.Q4 || []).some(c => c.pick === "opt-2" && c.text === "Typed on my phone")));

    // ---------- 26: a file attached before the pick goes in with it (C2) ----------
    await owner.evaluate(() => window.Core.saveSettings({ uploads: true }));
    const fay = await rec.open(A.localUrl, DESK);
    await joinAs(fay, "Fay");
    await go(fay, T.q4);
    await until(fay, () => !!document.querySelector(".vf-composer .vf-attach")?.offsetParent);
    await fay.fill("#vf-answer", "With a photo of the menu");
    await fay.evaluate(async () => {
      const c = document.createElement("canvas"); c.width = 64; c.height = 40; c.getContext("2d").fillRect(0, 0, 64, 40);
      const blob = await new Promise(r => c.toBlob(r, "image/png")), dt = new DataTransfer();
      dt.items.add(new File([blob], "menu.png", { type: "image/png" }));
      document.getElementById("vf-answer").dispatchEvent(new ClipboardEvent("paste", { clipboardData: dt, bubbles: true, cancelable: true }));
    });
    await until(fay, () => (window.Core.snapshot().myUploads || []).length === 1, null, 10000);
    const up = await fay.evaluate(() => window.Core.snapshot().myUploads[0].id);
    await owner.evaluate(id => window.Core.uploadAct(id, "accept"), up);
    await until(fay, id => (window.Core.snapshot().myUploads || []).some(u => u.id === id && u.status.kind === "done"), up, 30000);
    await fay.locator(".vf-opt", { hasText: "Sushi" }).locator(".vf-optchoose").click();
    ok("a file attached before the pick goes in with the pick and its comment", await until(owner, id => (window.Core.snapshot().cards?.Q4 || [])
      .some(c => c.pick === "opt-2" && c.text === "With a photo of the menu" && (c.attachments || []).includes(id)), up),
      JSON.stringify(await myCard(fay, "Q4")));

    // ---------- a pick-many save held back by a file still waiting for the host keeps the picks drafted ----------
    const hy = await rec.open(A.localUrl, DESK);
    await joinAs(hy, "Hy");
    await go(hy, T.q5);
    await until(hy, () => !!document.querySelector(".vf-composer .vf-attach")?.offsetParent);
    await hy.fill("#vf-answer", "Card first");
    await hy.evaluate(async () => {
      const c = document.createElement("canvas"); c.width = 64; c.height = 40; c.getContext("2d").fillRect(0, 0, 64, 40);
      const blob = await new Promise(r => c.toBlob(r, "image/png")), dt = new DataTransfer();
      dt.items.add(new File([blob], "cards.png", { type: "image/png" }));
      document.getElementById("vf-answer").dispatchEvent(new ClipboardEvent("paste", { clipboardData: dt, bubbles: true, cancelable: true }));
    });
    await until(hy, () => (window.Core.snapshot().myUploads || []).length === 1, null, 10000);
    for (const label of ["Card", "PayPal"]) await hy.locator(".vf-check-row", { hasText: label }).locator("input").check();
    const picksSent = [];
    hy.on("request", r => { if (new URL(r.url()).pathname === "/api/pick") picksSent.push(r.url()); });
    await hy.click(".vf-fmt-save");
    const waitSaid = await until(hy, () => /is waiting for the host/.test(document.querySelector(".vf-toast.vf-on span")?.textContent || ""));
    await hy.waitForTimeout(2000); // a poll or two repaint the page
    const checked = () => hy.evaluate(() => [...document.querySelectorAll(".vf-check-row")].filter(r => r.querySelector("input")?.checked).map(r => r.textContent.trim()));
    const heldPicks = await checked();
    ok("Save my picks held back by a file waiting for the host sends nothing and keeps both picks checked", waitSaid && picksSent.length === 0
      && heldPicks.length === 2 && heldPicks.some(t => t.includes("Card")) && heldPicks.some(t => t.includes("PayPal")), JSON.stringify({ waitSaid, sent: picksSent.length, heldPicks }));
    const hyUp = await hy.evaluate(() => window.Core.snapshot().myUploads[0].id);
    await owner.evaluate(id => window.Core.uploadAct(id, "accept"), hyUp);
    await until(hy, id => (window.Core.snapshot().myUploads || []).some(u => u.id === id && u.status.kind === "done"), hyUp, 30000);
    await hy.click(".vf-fmt-save");
    ok("  once the host accepts the file, Save sends those picks with the comment and the file", await until(owner, id => (window.Core.snapshot().cards?.Q5 || [])
      .some(c => JSON.stringify(c.picks) === '["opt-1","opt-2"]' && c.text === "Card first" && (c.attachments || []).includes(id)), hyUp), JSON.stringify(await myCard(hy, "Q5")));

    // ---------- 29: Use as my answer never cuts Claude's answer, and Cancel after Replace puts the picks back ----------
    const jo = await rec.open(A.localUrl, DESK);
    const joPid = await joinAs(jo, "Jo");
    const askAndAnswer = async (qid, ask, summary) => {
      await jo.waitForTimeout(1100);
      await jo.evaluate(([qq, t]) => window.Core.request(qq, "ask", t), [qid, ask]);
      const id = await owner.evaluate(async t => {
        for (let i = 0; i < 50 && !(window.Core.state.requests || []).some(r => r.text === t); i++) await new Promise(r => setTimeout(r, 100));
        return (window.Core.state.requests || []).find(r => r.text === t)?.id;
      }, ask);
      await owner.evaluate(i => window.Core.requestAct(i, "run"), id);
      s.apply(A.dir, [{ op: "result", qid, request: id, kind: "ask", summary, sources: [], report: "", used: [], why: "" }]);
      await until(jo, ([qq, a]) => (window.Core.state.research[qq] || []).some(x => x.summary === a), [qid, summary], 10000);
      await openClaude(jo);
    };
    const useAndReplace = async head => {
      await jo.locator(".vf-res", { hasText: head }).locator(".vf-res-use button").click({ timeout: 5000 }).catch(() => {});
      await until(jo, () => document.querySelector("dialog.vf-cdlg")?.open);
      await jo.click("dialog.vf-cdlg[open] .vf-btn-primary", { timeout: 5000 }).catch(() => {});
      return until(jo, () => !!document.getElementById("vf-other")?.offsetParent);
    };
    const saveLive = () => jo.evaluate(() => document.querySelector(".vf-fmt-save").getAttribute("aria-disabled") !== "true");
    // pick-many: Card saved, then a 2100-character answer
    await go(jo, T.q5);
    await jo.locator(".vf-check-row", { hasText: "Card" }).locator("input").check();
    await jo.click(".vf-fmt-save");
    await until(owner, p => (window.Core.snapshot().cards?.Q5 || []).some(c => c.pid === p && JSON.stringify(c.picks) === '["opt-1"]'), joPid);
    const LONG_HEAD = "Card only: most shoppers here pay that way.", LONG = (LONG_HEAD + " " + "Details follow. ".repeat(128)).trim();
    await askAndAnswer("Q5", "Which payment method do shoppers here use?", LONG);
    const boxOpen = await useAndReplace(LONG_HEAD);
    const inBox = await jo.inputValue("#vf-other");
    ok(`Use as my answer puts all of a ${LONG.length}-character answer in the own option, uncut`, boxOpen && LONG.length > 2000 && inBox === LONG, `${boxOpen} ${inBox.length}`);
    await jo.click(".vf-fmt-save");
    ok("  and saving it asks to shorten it to 2000 characters, sending nothing", await until(jo, n => document.querySelector(".vf-toast.vf-on span")?.textContent === `Shorten your own option to 2000 characters; it has ${n}.`, LONG.length)
      && !((await myCard(jo, "Q5"))?.picks || []).includes("other"), await jo.evaluate(() => document.querySelector(".vf-toast.vf-on span")?.textContent));
    await jo.locator(".vf-otherbox button", { hasText: "Cancel" }).click();
    await jo.waitForTimeout(300);
    const multiBack = await jo.evaluate(() => [...document.querySelectorAll(".vf-check-row")].filter(r => r.querySelector("input")?.checked).map(r => r.textContent.trim()));
    ok("on a pick-many question, Cancel after Replace brings back the saved pick, with Save not live", multiBack.length === 1 && multiBack[0].includes("Card") && !(await saveLive())
      && await jo.evaluate(() => document.querySelector(".vf-otherbox").hidden), JSON.stringify({ multiBack, live: await saveLive() }));
    // ranking: Fast, Cheap, Green saved, then Claude's answer
    await go(jo, T.q6);
    await until(jo, () => document.querySelectorAll(".vf-rank-item").length === 3);
    await jo.click(".vf-fmt-save");
    await until(owner, p => (window.Core.snapshot().cards?.Q6 || []).some(c => c.pid === p && JSON.stringify(c.order) === '["opt-1","opt-2","opt-3"]'), joPid);
    const RANK_ANS = "Green first: most buyers here ask for it.";
    await askAndAnswer("Q6", "Which delivery option do buyers here prefer?", RANK_ANS);
    await useAndReplace(RANK_ANS);
    await jo.locator(".vf-otherbox button", { hasText: "Cancel" }).click();
    await jo.waitForTimeout(300);
    const rankBack = await jo.evaluate(() => [...document.querySelectorAll(".vf-rank-item .vf-rank-l")].map(x => x.textContent).join(","));
    ok("on a ranking, Cancel after Replace brings back the saved order without the own option, with Save not live", rankBack === "Fast,Cheap,Green" && !(await saveLive()),
      JSON.stringify({ rankBack, live: await saveLive() }));

    // ---------- S1: unsent text belongs to whoever wrote it ----------
    const UNSENT_HOST = "The host's unsent line";
    const hostTab = await rec.open(A.ownerUrl, DESK);
    await until(hostTab, () => window.Core.snapshot()?.me?.role === "owner");
    await hostTab.click(".vf-fab");
    await hostTab.fill(".vf-minput", UNSENT_HOST);
    await hostTab.goto(A.localUrl + "?as=guest");
    await joinAs(hostTab, "Hal");
    await hostTab.click(".vf-fab");
    await hostTab.waitForTimeout(500);
    ok("an owner tab that opens the guest link does not put the host's unsent chat in the guest's field", (await hostTab.inputValue(".vf-minput")) === "", await hostTab.inputValue(".vf-minput"));
    const annSecret = await ann.evaluate(() => localStorage.getItem("secret")), boSecret = await bo.evaluate(() => localStorage.getItem("secret"));
    const annTab = await rec.open(`${A.localUrl}#me=${annSecret}`, DESK);
    await until(annTab, () => window.Core.snapshot()?.me?.name === "Ann");
    await annTab.click(".vf-fab");
    await annTab.fill(".vf-minput", "Ann's unsent line");
    await annTab.evaluate(sec => { location.hash = "me=" + sec; }, boSecret);
    await annTab.reload();
    await until(annTab, () => !!document.querySelector("dialog.core-switch[open]"));
    await annTab.click("dialog.core-switch button:text-is('Switch')");
    await until(annTab, () => window.Core.snapshot()?.me?.name === "Bo Lee" && !!document.querySelector(".vf-chat"), null, 10000);
    if (await annTab.evaluate(() => document.querySelector(".vf-chat").hidden)) await annTab.click(".vf-fab");
    await annTab.waitForTimeout(500);
    ok("  and Switch to another personal link leaves Ann's unsent chat behind", (await annTab.inputValue(".vf-minput")) === "", await annTab.inputValue(".vf-minput"));

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
