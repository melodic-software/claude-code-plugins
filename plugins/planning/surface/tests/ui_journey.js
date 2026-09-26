async page => { // AC27: the user journey J1 to J15 in order on one page, no reload after phase 1; the shell writes as Claude between phases
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  const errors = [];
  page.on("console", m => { if (m.type() === "error") errors.push(m.text()); });
  page.on("pageerror", e => errors.push(String(e)));
  const PHASE = __PHASE__;
  const base = "http://127.0.0.1:__PORT__/";
  const state = async () => (await page.request.get(base + "api/state")).json();
  const events = async () => (await state()).responses.events;
  const last = async () => { const e = await events(); return e[e.length - 1]; };
  const sel = async () => page.evaluate(() => (document.querySelector('.qbtn[aria-current="true"]') || {}).dataset?.q || (document.querySelector('.sumbtn[aria-current="true"]') ? "summary" : null));
  const text = async s => (await page.textContent(s).catch(() => "")) || "";
  const token = async () => page.$eval('meta[name="interview-token"]', m => m.content);
  const post = async body => page.request.post(base + "api/answer", {headers: {"Content-Type": "application/json", "X-Interview-Token": await token()}, data: body});
  const focused = async () => page.evaluate(() => document.activeElement.id || document.activeElement.tagName);
  const pick = async id => {
    if (await page.$eval('.rail-list .qbtn[data-q="' + id + '"]', el => !el.offsetParent).catch(() => false)) await page.click('.sec:has(.qbtn[data-q="' + id + '"]) .sec-h');
    await page.click('.rail-list .qbtn[data-q="' + id + '"]'); await page.waitForTimeout(200);
  };
  const arm = async key => { await page.click("#qhead"); await page.keyboard.press(key); };
  const badge = async () => page.evaluate(() => { const b = document.getElementById("actBadge"); return b.hidden ? 0 : +b.textContent; });
  const dot = async id => !!(await page.$('.qbtn[data-q="' + id + '"] .newdot'));
  try {
  if (PHASE === 1) {
    await page.setViewportSize({width: 1400, height: 860});
    await page.goto(base);
    await page.waitForSelector(".qbtn", {state: "attached"});
    await page.evaluate(() => localStorage.clear());
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(400);

    // J1 start
    ok("J1: header shows the title and the derived round", (await text("#title")) === "Journey page" && (await text("#roundLbl")) === "Interview round 1", await text("#roundLbl"));
    ok("J1: meter reads 0 of 5 answered", (await text("#meterText")) === "0 of 5 answered", await text("#meterText"));
    ok("J1: the Claude line is its own polite live region showing the newest entry", /^Round 1 added: Q1, Q2, Q3, Q4, Q5/.test(await text("#claudeLine")) && await page.$eval("#claudeLine", el => el.getAttribute("aria-live")) === "polite" && await page.$eval("#pill", el => el.getAttribute("aria-live")) === "off", await text("#claudeLine"));
    ok("AC24: groups with open questions start expanded", await page.$$eval(".rail-list .sec", els => els.length === 2 && els.every(e => e.dataset.collapsed === "false")));
    ok("J1: the first open question is selected", await sel() === "Q1", await sel());

    // J2 answer
    await arm("a"); await page.click("[data-save]"); await page.waitForTimeout(700);
    const e1 = await last();
    ok("J2: Accept saved on Q1", e1.id === "Q1" && e1.kind === "accept", JSON.stringify(e1));
    ok("J2: the meter advances and the next open question is selected", (await text("#meterText")) === "1 of 5 answered" && await sel() === "Q2", (await text("#meterText")) + " " + await sel());
    await pick("Q1");
    ok("J2: the receipt shows Saved with its time", /Saved \d/.test(await text("#cur")), await text("#cur"));

    // J3 accept with note
    await pick("Q2"); await page.fill("#note", "Yes, but explain the retry rule"); await arm("a");
    ok("AC15: Save reads Accept with note", (await text("[data-save]")) === "Save: Accept with note", await text("[data-save]"));
    await page.click("[data-save]"); await page.waitForTimeout(700);
    const e2 = await last();
    ok("AC15: the accept carries the note and the page stays on Q2", e2.id === "Q2" && e2.kind === "accept" && e2.text === "Yes, but explain the retry rule" && await sel() === "Q2", JSON.stringify(e2) + " " + await sel());
    ok("AC15: the toast says Claude's reply lands in the thread", /reply lands in its thread/.test(await text("#toast")), await text("#toast"));

    // J4 accept all per group, with carried notes
    await pick("Q3"); await page.fill("#note", "Keep the cache small");
    await pick("Q4"); await page.fill("#note", "Challenge: Fails a build that runs past ten minutes on a slow runner?");
    const aa = await page.$('[data-acceptall="g2"]');
    ok("AC16: Accept all offered on the group for the two opened questions", !!aa && /Accept all \(2\)/.test(aa ? await aa.textContent() : ""));
    await aa.click(); await page.waitForTimeout(200);
    const dlg = await page.evaluate(() => document.getElementById("dlgBody").innerText);
    ok("AC16: the dialog lists Q3 with its carried note", /Q3/.test(dlg) && /Note: Keep the cache small/.test(dlg), dlg.replace(/\s+/g, " ").slice(0, 200));
    ok("AC16: the dialog leaves out the Challenge note and the unopened question, and says there is no batch undo", /challenges a commitment: Q4/.test(dlg) && /1 open question you have not opened/.test(dlg) && /cannot be undone as one step/.test(dlg), dlg.replace(/\s+/g, " ").slice(0, 300));
    await page.click("#dlgOk"); await page.waitForTimeout(900);
    const acc = (await events()).filter(e => e.kind === "accept" && ["Q3", "Q4", "Q5"].includes(e.id));
    const drafts = await page.evaluate(() => Object.keys(localStorage).filter(k => /:draft:Q[34]$/.test(k)).map(k => k.slice(-2)).sort().join(","));
    ok("AC16: one accept for Q3 carrying its note, none for Q4; only Q3's draft is cleared", acc.length === 1 && acc[0].id === "Q3" && acc[0].text === "Keep the cache small" && drafts === "Q4", JSON.stringify(acc) + " drafts " + drafts);

    // J5 ask Claude
    await pick("Q4"); await page.fill("#note", "What does slow mean here?"); await page.click("#note"); await page.keyboard.press("Control+Shift+Enter"); await page.waitForTimeout(700);
    const ask = await last();
    ok("J5: Ask Claude posts the note as an ask", ask.kind === "ask" && ask.id === "Q4" && ask.text === "What does slow mean here?", JSON.stringify(ask));
    await page.request.get(base + "api/wait?after=0&timeout=2", {headers: {"X-Interview-Token": await token()}}); await page.waitForTimeout(900);
    ok("J5: the Claude line reads Claude is working on", /^Claude is working on Q\d/.test(await text("#claudeLine")), await text("#claudeLine"));

    // J6 own answer that is a question
    await pick("Q5"); await page.fill("#note", "Should we pin the version?"); await arm("o");
    ok("AC26: an Own answer ending in ? shows the Ask Claude nudge before save", /This reads as a question\. Ask Claude instead\?/.test(await text("#askNudge")) && !!(await page.$('#askNudge [data-act="ask"]')), await text("#decideRow"));
    await page.keyboard.press("Escape"); await page.click("[data-save]"); await page.waitForTimeout(700);
    const own = await last();
    ok("AC26: saving as own stays possible", own.kind === "own" && own.id === "Q5" && own.text === "Should we pin the version?", JSON.stringify(own));
    await pick("Q1"); // off the rows the next writes name, so their dots show
  }
  if (PHASE === 2) {
    await page.waitForTimeout(900); // SSE brings the reply on Q4, then the holds and the status

    // UX3 seen marker, the notice and J5's reply
    ok("UX3: two unseen entries badge Activity and dot the rows they name", await badge() === 2 && await dot("Q4") && await dot("Q3") && await dot("Q5"), "badge " + await badge());
    ok("AC19: the notice digests the newest unseen entry and is not a live region", /Q3 pending research/.test(await text("#notice")) && /\+1 more/.test(await text("#notice")) && !(await page.$eval("#notice", el => el.getAttribute("aria-live"))), await text("#notice"));
    ok("AC8: Claude's reply shows as the rail preview on Q4", /^Claude: Slow means over five minutes per run/.test(await text('.qbtn[data-q="Q4"] .qprev')), await text('.qbtn[data-q="Q4"] .qprev'));
    await pick("Q4");
    ok("UX3: visiting Q4 clears its dot and lowers the badge by the entry naming it", !(await dot("Q4")) && await badge() === 1 && await dot("Q3"), "badge " + await badge());
    ok("AC8: the detail shows Claude's reply above the recommendation", await page.evaluate(() => { const l = document.getElementById("latest"), r = document.querySelector(".recbox"); return !!l && !!r && /Slow means/.test(l.textContent) && !!(l.compareDocumentPosition(r) & Node.DOCUMENT_POSITION_FOLLOWING); }));

    // J7 Claude researches
    const q3 = '.qbtn[data-q="Q3"]';
    ok("J7: Q3's rail row reads Pending research with its own colour", /Pending research: the retry benchmark/.test(await text(q3 + " .chip.s-wait")) && await page.$eval(q3, el => el.classList.contains("st-wait")), await text(q3));
    ok("J7: the header counts 1 pending research and Q3 not answered", (await text("#pendBtn")) === "1 pending research" && (await text("#meterText")) === "2 of 5 answered", (await text("#pendBtn")) + " / " + await text("#meterText"));
    ok("J7: the Claude line shows the status with its age", /^Researching the retry benchmark for Q3/.test(await text("#claudeLine")) && await page.$eval("#claudeLine .age", el => el.getAttribute("aria-hidden") === "true" && /ago|just now/.test(el.textContent)), await text("#claudeLine"));
    await pick("Q3");
    ok("J7: the card shows the banner beside the kept decision", /Pending research: the retry benchmark/.test(await text("#dscroll .waitban")) && /Accepted/.test(await text("#cur")) && /Counts once Claude's research on Q3 returns/.test(await text("#cur")), await text("#cur"));
    await arm("2");
    ok("J7: Save reads Answer anyway", /^Answer anyway: \(a\)/.test(await text("[data-save]")), await text("[data-save]"));
    await page.click("[data-save]"); await page.waitForTimeout(700);
    const aw = await last();
    ok("UX4: Answer anyway saves, stays on Q3 and says it counts once the research returns", aw.id === "Q3" && aw.kind === "alt" && await sel() === "Q3" && /Counts once Claude's research on Q3 returns/.test(await text("#toast")) && (await text("#meterText")) === "2 of 5 answered", JSON.stringify(aw) + " " + await text("#toast"));
    await page.selectOption("#filter", "pending"); await page.waitForTimeout(200);
    const listed = (await page.$$eval(".rail-list .qbtn", els => els.map(e => e.dataset.q))).join(",");
    ok("J7: Show: Pending lists only Q3", listed === "Q3", listed);
    await page.selectOption("#filter", "all"); await page.waitForTimeout(150);

    // J8 awaiting the user
    ok("J8: Q5 reads Needs your answer and its group counts it open", /Needs your answer: whether the version must be pinned/.test(await text('.qbtn[data-q="Q5"] .chip.s-need')) && (await text('.sec[data-key="g:g2"] .cnt')) === "3 open / 3", await text('.sec[data-key="g:g2"] .cnt'));
    await pick("Q1"); await page.click("#qhead"); await page.keyboard.press("n"); const n1 = await sel(); await page.keyboard.press("n"); const n2 = await sel();
    ok("J8: n visits Q4 then Q5 and skips Q3, pending research", n1 === "Q4" && n2 === "Q5", n1 + " " + n2);
    ok("UX4: Q5 keeps its set-aside answer and offers Answer again", /Set aside/.test(await text("#cur")) && !!(await page.$("#cur [data-again]")), await text("#cur"));

    // set up J10 and UX8: a note for Claude to answer, then the summary with a hiding filter and a hidden rail
    await post({kind: "note", text: "Is the plan on track?"});
    await page.selectOption("#filter", "answered"); await page.click("#title"); await page.keyboard.press("w"); await page.keyboard.press("["); await page.waitForTimeout(300);
    ok("setup: the summary shows with the Answered filter and the rail hidden", await sel() === "summary" && await page.$eval("#layout", el => el.classList.contains("norail")), await sel());
  }
  if (PHASE === 3) {
    await page.waitForTimeout(900); // SSE brings the research result, round 2 and the Notes reply

    // J9 to J11 on the summary
    ok("AC19: the notice shows on the summary: Claude replied in Notes, with Open", await sel() === "summary" && /Claude replied in Notes/.test(await text("#notice")) && (await text("#notice [data-go]")) === "Open", await text("#notice"));
    const acts = (await state()).questions.activity, newest = acts[acts.length - 1].text;
    ok("J9: the hold and status are gone and the Claude line falls back to the newest entry", !/Pending research/.test(await text('.qbtn[data-q="Q3"]')) && await page.$eval("#pendBtn", el => el.hidden) && (await text("#claudeLine")).startsWith(newest), await text("#claudeLine"));
    ok("AC25: the header derives Interview round 2", (await text("#roundLbl")) === "Interview round 2", await text("#roundLbl"));
    await page.click("#notice [data-go]"); await page.waitForTimeout(300);
    ok("J11: Open shows Claude's reply in Notes", await page.evaluate(() => document.getElementById("fly").classList.contains("open") && /Yes, on track/.test(document.getElementById("fbody").innerText)));
    ok("J10: the notice moves on to Round 2 added, with Go", /Round 2 added: Q6, Q7/.test(await text("#notice")) && (await text("#notice [data-go]")) === "Go", await text("#notice"));
    await page.click("#flyClose");
    await page.click("#railBtn"); await page.selectOption("#filter", "all"); await page.waitForTimeout(200);
    ok("AC24: the new round's group is expanded and highlighted", await page.$eval('.sec[data-key="g:g3"]', el => el.dataset.collapsed === "false" && el.classList.contains("fresh")) && await dot("Q6"));
    await page.selectOption("#filter", "answered"); await page.click("#railBtn"); await page.waitForTimeout(200);
    await page.click("#notice [data-go]"); await page.waitForTimeout(400);
    ok("UX8: Go resets the filter, shows the rail and says so", await page.$eval("#filter", el => el.value) === "all" && !(await page.$eval("#layout", el => el.classList.contains("norail"))) && /Showing all to reveal Q6/.test(await text("#toast")), await text("#toast"));
    ok("UX7: Go selects Q6 and moves focus to its heading", await sel() === "Q6" && await focused() === "qhead", await sel() + " " + await focused());

    // J12 commitments, page side
    await arm("a"); await page.click("[data-save]"); await page.waitForTimeout(700);
    ok("AC23: the header counts commitments on accepted questions only", (await text("#assumeCount")) === "5 to confirm", await text("#assumeCount"));
    await page.click("#assumeCount"); await page.waitForTimeout(300);
    ok("AC23: the link opens To confirm grouped by question", await sel() === "summary" && (await page.$$eval("#toConfirm .crows", els => els.length)) === 3 && /Things your answers commit you to/.test(await text("#toConfirm")), await text("#toConfirm"));
    const n0 = (await events()).length;
    await page.click('#toConfirm [data-cq="Q1"][data-confirm="0"]'); await page.waitForTimeout(700);
    const ev = await events(), cf = ev[ev.length - 1];
    ok("AC23: a tick posts one confirm and lowers the count", ev.length === n0 + 1 && cf.kind === "confirm" && cf.id === "Q1" && cf.alt === "0" && (await text("#assumeCount")) === "4 to confirm", JSON.stringify(cf) + " " + await text("#assumeCount"));
  }
  if (PHASE === 4) {
    await page.waitForTimeout(900); // SSE brings Claude's confirm-commitments and the restatement

    // J12 Claude-side confirmation and Confirm all
    ok("AC23: Claude's confirmation leaves Q2's list, shows its reason and lowers the count", !(await page.$('#toConfirm [data-cq="Q2"]')) && /Q2 \(Confirmed in the terminal\)/.test(await text("#byClaude")) && (await text("#assumeCount")) === "3 to confirm", (await text("#assumeCount")) + " / " + await text("#byClaude"));
    ok("Q24: a terminal accept mirrored with record-terminal, then confirmed by Claude, leaves no part of Q4 to confirm", !(await page.$('#toConfirm [data-cq="Q4"]')) && /Q4 \(Said yes in the terminal\)/.test(await text("#byClaude")), await text("#toConfirm"));
    const n1 = (await events()).length;
    await page.click("[data-confirmall]"); await page.waitForTimeout(1500);
    const added = (await events()).slice(n1);
    ok("AC23: Confirm all posts one confirm per unconfirmed commitment", added.length === 3 && added.every(e => e.kind === "confirm") && await page.$eval("#assumeCount", el => el.hidden), added.map(e => e.id + ":" + e.alt).join(","));

    // J13 confirm understanding
    ok("AC22: the summary shows the restatement with Confirm and Something's off", /Ship green builds to staging/.test(await text("#restate")) && /Left to the plan stage/.test(await text("#restate")) && !!(await page.$('[data-understand="confirm"]')) && !!(await page.$('[data-understand="off"]')), (await text("#restate")).slice(0, 160));
    ok("UX10: Wrap up warns Understanding not confirmed yet", /Understanding not confirmed yet/.test(await text("#unconfWarn")));
    const n2 = (await events()).length;
    await page.click('[data-understand="off"]'); await page.waitForTimeout(400);
    ok("AC22: Something's off needs text: nothing posts without it", (await events()).length === n2 && /Say what is off first/.test(await text("#restate")), await text("#restate"));
    await page.click("#offText"); await page.keyboard.type("The goal misses production");
    await page.evaluate(() => { document.getElementById("offText").__mark = 1; });
    await post({kind: "note", text: "A note that pushes new state"}); await page.waitForTimeout(900);
    ok("UX1: a state push keeps the typed box, its text and focus", await page.evaluate(() => { const t = document.getElementById("offText"); return !!t && t.__mark === 1 && t.value === "The goal misses production" && document.activeElement === t; }));
    await page.click('[data-understand="off"]'); await page.waitForTimeout(800);
    const off = await last();
    ok("AC22: Something's off posts the text and the restatement rev, and the summary shows it flagged", off.kind === "confirm-understanding" && off.alt === "off" && off.text === "The goal misses production" && off.contentRev === 1 && /You flagged/.test(await text("#restate")), JSON.stringify(off));
    const stale = await post({kind: "confirm-understanding", alt: "confirm", text: "", contentRev: 0});
    ok("AC22: a confirm on an old restatement is refused as stale", stale.status() === 409, stale.status());

    // set up UX10's revise while answering
    await pick("Q7"); await page.fill("#note", "My own take"); await arm("o"); await page.keyboard.press("Escape");
    ok("setup: Q7 armed as own with a note before the external revise", /Own answer/.test(await text(".choice.armed")) && (await page.inputValue("#note")) === "My own take", await text(".choice.armed"));
  }
  if (PHASE === 5) {
    await page.waitForTimeout(900); // SSE brings the revise of Q7 and the new restatement

    // UX10 revise while typing, undo, reopen
    await page.click("#qhead"); await page.keyboard.press("Control+Enter"); await page.waitForTimeout(700);
    ok("UX10: a revise while answering shows the conflict banner and keeps the note", !(await page.$eval("#conflict", el => el.hidden)) && (await page.inputValue("#note")) === "My own take");
    await page.click('[data-conflict="mine"]'); await page.waitForTimeout(800);
    const km = await last();
    ok("UX10: Keep mine saves the own answer", km.id === "Q7" && km.kind === "own" && km.text === "My own take", JSON.stringify(km));
    await page.click("[data-undo]"); await page.waitForTimeout(800);
    const un = await last();
    ok("UX10: Undo withdraws the save and Q7 is open again", un.kind === "undo" && await sel() === "Q7" && /Open/.test(await text('.qbtn[data-q="Q7"] .chip')), un.kind + " " + await sel());
    await arm("a"); await page.click("[data-save]"); await page.waitForTimeout(800);
    await page.click('[data-act="reopen"]'); await page.waitForTimeout(800);
    const ro = await last();
    ok("UX10: Reopen records a reopen", ro.kind === "reopen" && ro.id === "Q7", JSON.stringify(ro));

    // UX10 offline, then J15 catch-up when the tab becomes visible
    await page.context().setOffline(true);
    await page.evaluate(() => { Object.defineProperty(document, "visibilityState", {configurable: true, get: () => "visible"}); document.dispatchEvent(new Event("visibilitychange")); });
    const wentOff = await page.waitForFunction(() => document.getElementById("pill").textContent === "Offline", null, {timeout: 8000}).then(() => true).catch(() => false);
    ok("UX10: offline shows Offline and announces it", wentOff && await page.$eval("#pill", el => el.getAttribute("aria-live")) === "polite", await text("#pill"));
    await page.context().setOffline(false);
    await post({id: "Q4", kind: "ask", text: "Asked while the tab was away"});
    const fetched = [], t0 = Date.now();
    page.on("request", r => { if (/\/api\/state$/.test(r.url())) fetched.push(Date.now() - t0); });
    await page.evaluate(() => document.dispatchEvent(new Event("visibilitychange")));
    const back = await page.waitForFunction(() => document.getElementById("pill").textContent !== "Offline", null, {timeout: 10000}).then(() => true).catch(() => false);
    await page.waitForTimeout(500);
    ok("J15: becoming visible re-fetches /api/state and shows what happened meanwhile", back && fetched.length > 0 && fetched[0] < 1000 && /Sent to Claude/.test(await text('.qbtn[data-q="Q4"]')), "fetched at " + fetched.join(",") + " ms");

    // J13 after a new restate, then J14
    await page.click("#sumBtn"); await page.waitForTimeout(300);
    ok("UX10: a new restate resets the summary to unconfirmed", !!(await page.$('[data-understand="confirm"]')) && /Understanding not confirmed yet/.test(await text("#unconfWarn")) && /linked issues in the release notes/.test(await text("#restate")), (await text("#restate")).slice(0, 160));
    await page.click('[data-understand="confirm"]'); await page.waitForTimeout(800);
    const cu = await last();
    ok("AC22: Confirm posts confirm-understanding and the summary reads Confirmed with its time", cu.kind === "confirm-understanding" && cu.alt === "confirm" && cu.contentRev === 2 && /^Confirmed \S/.test(await text("#uDone")) && !(await page.$("#unconfWarn")), JSON.stringify(cu) + " " + await text("#uDone"));
    const w0 = (await events()).length;
    await page.click("[data-wrapup]"); await page.waitForTimeout(700);
    const wr = await events();
    ok("J14: Wrap up posts one wrapup event", wr.length === w0 + 1 && wr[wr.length - 1].kind === "wrapup");
  }
  const real = errors.filter(e => !/status of 409 \(Conflict\)/.test(e) && !/ERR_INTERNET_DISCONNECTED/.test(e));
  ok("zero console errors in journey phase " + PHASE + " (besides the network lines for an intended 409 and the offline step)", real.length === 0, errors.join(" | "));
  } catch (e) { R.push("ERROR " + e.message.split("\n").slice(0, 3).join(" | ")); }
  return R.join("\n");
}
