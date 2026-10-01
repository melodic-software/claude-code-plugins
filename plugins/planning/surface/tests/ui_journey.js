async page => { // the user journey in order on one page, no reload after phase 1; the shell writes as Claude between phases
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
    await tap('.rail-list .qbtn[data-q="' + id + '"]', 200);
  };
  const arm = async key => { await page.click("#qhead"); await page.keyboard.press(key); };
  const badge = async () => page.evaluate(() => { const b = document.getElementById("actBadge"); return b.hidden ? 0 : +b.textContent; });
  const dot = async id => !!(await page.$('.qbtn[data-q="' + id + '"] .newdot'));
  const tap = async (s, ms) => { await page.click(s); await page.waitForTimeout(ms); };
  const until = (fn, timeout) => page.waitForFunction(fn, null, {timeout}).then(() => true).catch(() => false);
  const setHidden = h => page.evaluate(h => {
    for (const [k, v] of [["hidden", h], ["visibilityState", h ? "hidden" : "visible"]]) Object.defineProperty(document, k, {configurable: true, get: () => v});
    document.dispatchEvent(new Event("visibilitychange"));
  }, h);
  try {
  if (PHASE === 1) {
    await page.setViewportSize({width: 1400, height: 860});
    await page.goto(base);
    await page.waitForSelector(".qbtn", {state: "attached"});
    await page.evaluate(() => localStorage.clear());
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(400);

    // start
    ok("header shows the title and the derived round", (await text("#title")) === "Journey page" && (await text("#roundLbl")) === "Round 1 · Interview", await text("#roundLbl"));
    ok("meter reads 0 of 5 answered", (await text("#meterText")) === "0 of 5 answered", await text("#meterText"));
    ok("the Claude line is its own polite live region showing the newest entry", /^Round 1 added: Q1, Q2, Q3, Q4, Q5/.test(await text("#claudeLine")) && await page.$eval("#claudeLine", el => el.getAttribute("aria-live")) === "polite" && await page.$eval("#pill", el => el.getAttribute("aria-live")) === "off", await text("#claudeLine"));
    ok("groups with open questions start expanded", await page.$$eval(".rail-list .sec", els => els.length === 2 && els.every(e => e.dataset.collapsed === "false")));
    ok("the first open question is selected", await sel() === "Q1", await sel());

    // answer
    await arm("a"); await tap("[data-save]", 700);
    const e1 = await last();
    ok("Accept saved on Q1", e1.id === "Q1" && e1.kind === "accept", JSON.stringify(e1));
    ok("the meter advances and the next open question is selected", (await text("#meterText")) === "1 of 5 answered" && await sel() === "Q2", (await text("#meterText")) + " " + await sel());
    await pick("Q1");
    ok("the receipt shows Saved with its time", /Saved \d/.test(await text("#cur")), await text("#cur"));

    // accept with note
    await pick("Q2"); await page.fill("#note", "Yes, but explain the retry rule"); await arm("a");
    ok("Save reads Accept with note", (await text("[data-save]")) === "Save: Accept with note", await text("[data-save]"));
    await tap("[data-save]", 700);
    const e2 = await last();
    ok("the accept carries the note and the page stays on Q2", e2.id === "Q2" && e2.kind === "accept" && e2.text === "Yes, but explain the retry rule" && await sel() === "Q2", JSON.stringify(e2) + " " + await sel());
    ok("the toast says Claude's reply lands in the thread", /reply lands in its thread/.test(await text("#toast")), await text("#toast"));

    // accept all per group, with carried notes
    await pick("Q3"); await page.fill("#note", "Keep the cache small");
    await pick("Q4"); await page.fill("#note", "Challenge: Fails a build that runs past ten minutes on a slow machine?");
    const aa = await page.$('[data-acceptall="g2"]');
    ok("Accept all offered on the group for the two opened questions", !!aa && /Accept all \(2\)/.test(aa ? await aa.textContent() : ""));
    await aa.click(); await page.waitForTimeout(200);
    const dlg = await page.evaluate(() => document.getElementById("dlgBody").innerText);
    ok("the dialog lists Q3 with its carried note", /Q3/.test(dlg) && /Note: Keep the cache small/.test(dlg), dlg.replace(/\s+/g, " ").slice(0, 200));
    ok("the dialog leaves out the Challenge note and the unopened question, and says there is no batch undo", /challenges a commitment: Q4/.test(dlg) && /1 open question you have not opened/.test(dlg) && /cannot be undone as one step/.test(dlg), dlg.replace(/\s+/g, " ").slice(0, 300));
    await tap("#dlgOk", 900);
    const acc = (await events()).filter(e => e.kind === "accept" && ["Q3", "Q4", "Q5"].includes(e.id));
    const drafts = await page.evaluate(() => Object.keys(localStorage).filter(k => /:draft:Q[34]$/.test(k)).map(k => k.slice(-2)).sort().join(","));
    ok("one accept for Q3 carrying its note, none for Q4; only Q3's draft is cleared", acc.length === 1 && acc[0].id === "Q3" && acc[0].text === "Keep the cache small" && drafts === "Q4", JSON.stringify(acc) + " drafts " + drafts);

    // ask Claude
    await pick("Q4"); await page.fill("#note", "What does slow mean here?"); await page.click("#note"); await page.keyboard.press("Control+Shift+Enter"); await page.waitForTimeout(700);
    const ask = await last();
    ok("Ask Claude posts the note as an ask", ask.kind === "ask" && ask.id === "Q4" && ask.text === "What does slow mean here?", JSON.stringify(ask));
    ok("Ask Claude empties the note", (await page.inputValue("#note")) === "", await page.inputValue("#note"));
    await page.fill("#note", "scratch"); await page.click("[data-clear]");
    ok("Clear empties the note and disables itself", (await page.inputValue("#note")) === "" && await page.$eval("[data-clear]", b => b.disabled));
    await page.request.get(base + "api/wait?after=0&timeout=2", {headers: {"X-Interview-Token": await token()}}); await page.waitForTimeout(900);
    ok("the Claude line reads Claude is working on", /^Claude is working on Q\d/.test(await text("#claudeLine")), await text("#claudeLine"));
    ok("an unanswered ask shows the Waiting for Claude's reply chip on Q4", /Waiting for Claude's reply/.test(await text('.qbtn[data-q="Q4"]')), await text('.qbtn[data-q="Q4"]'));
    await pick("Q4"); await arm("a"); await tap("[data-save]", 300);
    const nb = (await events()).length;
    ok("Accept on a question still waiting for Claude asks first", /Accept current recommendation anyway\?/.test(await text("#dlgTitle")), await text("#dlgTitle"));
    await tap("#dlgCancel", 300);
    ok("cancelling the prompt sends nothing", (await events()).length === nb, String(nb));

    // own answer that is a question
    const askToast = await text("#toast");
    await pick("Q5");
    ok("the ask's toast clears when the view changes", /reply lands in the thread/.test(askToast) && (await text("#toast")) === "", askToast + " / " + await text("#toast"));
    await page.fill("#note", "Should we pin the version?"); await arm("o");
    ok("an Own answer ending in ? shows the Ask Claude nudge before save", /This reads as a question\. Ask Claude instead\?/.test(await text("#askNudge")) && !!(await page.$('#askNudge [data-act="ask"]')), await text("#decideRow"));
    await page.fill("#note", "We should pin the version because");
    ok("an Own note that ends mid-sentence shows the cut-off nudge and Save stays enabled", /looks cut off/.test(await text("#cutNudge")) && !(await page.$("#askNudge")) && !(await page.$("[data-save][disabled]")), await text("#decideRow"));
    await page.fill("#note", "This is complete.");
    ok("a finished Own note shows no cut-off nudge", !(await page.$("#cutNudge")), await text("#decideRow"));
    await page.fill("#note", "Should we pin the version?");
    await page.keyboard.press("Escape"); await tap("[data-save]", 700);
    const own = await last();
    ok("saving as own stays possible", own.kind === "own" && own.id === "Q5" && own.text === "Should we pin the version?", JSON.stringify(own));
    await pick("Q1"); // off the rows the next writes name, so their dots show
    await page.click('.sec[data-key="g:g2"] .sec-h'); // collapsed by the user before Claude replies on Q4
  }
  if (PHASE === 2) {
    await page.waitForTimeout(900); // SSE brings the reply on Q4, then the holds and the status
    ok("a reply does not reopen a section the user collapsed", await page.$eval('.sec[data-key="g:g2"]', el => el.dataset.collapsed) === "true");
    await tap('.sec[data-key="g:g2"] .sec-h', 150);

    // receipts: phase 1's watcher poll delivered Q1's accept and the shell handled it (Q1 is selected)
    ok("Q1's receipt shows Saved, Delivered and Handled", /Saved \d.*Delivered \d.*Handled/.test(await text("#cur")), await text("#cur"));

    // the seen marker, the notice and the reply to the ask
    ok("two unseen entries badge Activity and dot the rows they name", await badge() === 2 && await dot("Q4") && await dot("Q3") && await dot("Q5"), "badge " + await badge());
    ok("the notice digests the newest unseen entry and is not a live region", /Q3 pending research/.test(await text("#notice")) && /\+1 more/.test(await text("#notice")) && !(await page.$eval("#notice", el => el.getAttribute("aria-live"))), await text("#notice"));
    ok("Claude's reply shows as the rail preview on Q4", /^Claude: Slow means over five minutes per run/.test(await text('.qbtn[data-q="Q4"] .qprev')), await text('.qbtn[data-q="Q4"] .qprev'));
    await pick("Q4");
    ok("visiting Q4 clears its dot and lowers the badge by the entry naming it", !(await dot("Q4")) && await badge() === 1 && await dot("Q3"), "badge " + await badge());
    ok("the detail shows Claude's reply above the recommendation", await page.evaluate(() => { const l = document.getElementById("latest"), r = document.querySelector(".recbox"); return !!l && !!r && /Slow means/.test(l.textContent) && !!(l.compareDocumentPosition(r) & Node.DOCUMENT_POSITION_FOLLOWING); }));

    // Claude researches
    const q3 = '.qbtn[data-q="Q3"]';
    ok("Q3's rail row reads Pending research with its own color", /Pending research: the retry benchmark/.test(await text(q3 + " .chip.s-wait")) && await page.$eval(q3, el => el.classList.contains("st-wait")), await text(q3));
    ok("the header counts 1 pending research and Q3 not answered", (await text("#pendBtn")) === "1 pending research" && (await text("#meterText")) === "2 of 5 answered", (await text("#pendBtn")) + " / " + await text("#meterText"));
    ok("the Claude line shows the status with its age", /^Researching the retry benchmark for Q3/.test(await text("#claudeLine")) && await page.$eval("#claudeLine .age", el => el.getAttribute("aria-hidden") === "true" && /ago|just now/.test(el.textContent)), await text("#claudeLine"));
    ok("a held question's commitments leave the to-confirm count", (await text("#assumeCount")) === "3 to confirm", await text("#assumeCount"));
    const f0 = await page.$eval("#filter", el => el.value);
    await page.selectOption("#filter", "open"); await page.waitForTimeout(200);
    const open2 = (await page.$$eval(".rail-list .qbtn", els => els.map(e => e.dataset.q))).join(",");
    await page.selectOption("#filter", f0); await page.waitForTimeout(150);
    ok("Show: Open leaves out Q3, held for research after its accept, and lists the questions that need you", open2 === "Q4,Q5", open2);
    await pick("Q3");
    ok("the card shows the banner beside the kept decision", /Pending research: the retry benchmark/.test(await text("#dscroll .waitban")) && /Accepted/.test(await text("#cur")) && /Counts once Claude's research on Q3 returns/.test(await text("#cur")), await text("#cur"));
    await arm("3");
    ok("Save reads Answer anyway", /^Answer anyway: \(a\)/.test(await text("[data-save]")), await text("[data-save]"));
    await tap("[data-save]", 700);
    const aw = await last();
    ok("Answer anyway saves, stays on Q3 and says it counts once the research returns", aw.id === "Q3" && aw.kind === "alt" && await sel() === "Q3" && /Counts once Claude's research on Q3 returns/.test(await text("#toast")) && (await text("#meterText")) === "2 of 5 answered", JSON.stringify(aw) + " " + await text("#toast"));
    ok("the held card says research is in progress with its start time and keeps the answer controls enabled", /Research in progress, started \d/.test(await text("#dscroll .waitban")) && !(await page.$("#choices input:disabled")) && !(await page.$("#note:disabled")), await text("#dscroll .waitban"));
    ok("a held question offers Cancel research and no Research this", !!(await page.$('[data-research="cancel-research"]')) && !(await page.$('[data-research="research"]')), await text("#talkRow"));
    await tap('[data-research="cancel-research"]', 600);
    const cr = await last();
    ok("Cancel research posts kind cancel-research for Q3 and the hold stays until Claude releases it", cr.kind === "cancel-research" && cr.id === "Q3" && !!(await page.$('#dscroll .waitban')), JSON.stringify(cr));
    await pick("Q4");
    ok("a question with no hold offers Research this and no Cancel research", !!(await page.$('[data-research="research"]')) && !(await page.$('[data-research="cancel-research"]')), await text("#talkRow"));
    await tap('[data-research="research"]', 600);
    const rr = await last();
    ok("Research this posts kind research for Q4", rr.kind === "research" && rr.id === "Q4", JSON.stringify(rr));
    await page.selectOption("#filter", "pending"); await page.waitForTimeout(200);
    const listed = (await page.$$eval(".rail-list .qbtn", els => els.map(e => e.dataset.q))).join(",");
    ok("Show: Pending lists only Q3", listed === "Q3", listed);
    await page.selectOption("#filter", "all"); await page.waitForTimeout(150);

    // awaiting the user
    ok("Q5 reads Needs your answer and its group counts it open", /Needs your answer: whether the version must be pinned/.test(await text('.qbtn[data-q="Q5"] .chip.s-need')) && (await text('.sec[data-key="g:g2"] .cnt')) === "3 open / 3", await text('.sec[data-key="g:g2"] .cnt'));
    await pick("Q1"); await page.click("#qhead"); await page.keyboard.press("n"); const n1 = await sel(); await page.keyboard.press("n"); const n2 = await sel();
    ok("n visits Q4 then Q5 and skips Q3, pending research", n1 === "Q4" && n2 === "Q5", n1 + " " + n2);
    ok("a question waiting on the user offers neither Research this nor Cancel research", !(await page.$('[data-research]')), await text("#talkRow"));
    ok("a long hold text wraps inside the rail: it never scrolls sideways", await page.$eval("#railList", el => el.scrollWidth <= el.clientWidth), await page.$eval("#railList", el => el.scrollWidth + " > " + el.clientWidth));
    ok("Q5 offers one action, Answer again, with a one-line reason and no Reopen", /set your earlier answer \(Own answer: .*\) aside because it needs your decision\./.test(await text("#cur")) && (await page.$$("#cur [data-again]")).length === 1 && !(await page.$('[data-act="reopen"]')) && !/Set aside/.test(await text("#cur")), await text("#cur"));
    const aside = await page.$eval('.qbtn[data-q="Q5"] .chip.aside', el => { const s = getComputedStyle(el); return {t: el.textContent, b: s.borderTopWidth, bg: s.backgroundColor, c: s.cursor}; }).catch(() => null);
    ok("the rail's Set aside chip reads as a status, not a button", !!aside && aside.t === "Set aside" && aside.b === "0px" && aside.bg === "rgba(0, 0, 0, 0)" && aside.c === "default", JSON.stringify(aside));
    await tap("#cur [data-again]", 150);
    ok("Answer again moves focus to the first choice", await page.evaluate(() => document.activeElement.matches('#choices input[type="radio"]')));

    // set up the notice checks: a note for Claude to answer, then the summary with a hiding filter and a hidden rail
    await post({kind: "note", text: "Is the plan on track?"});
    await page.selectOption("#filter", "answered"); await page.click("#title"); await page.keyboard.press("w"); await page.keyboard.press("["); await page.waitForTimeout(300);
    ok("setup: the summary shows with the Answered filter and the rail hidden", await sel() === "summary" && await page.$eval("#layout", el => el.classList.contains("norail")), await sel());
  }
  if (PHASE === 3) {
    await page.waitForTimeout(900); // SSE brings the research result, round 2 and the Notes reply

    // on the summary
    ok("the notice shows on the summary: Claude replied in Notes, with Open Notes and All activity", await sel() === "summary" && /Claude replied in Notes/.test(await text("#notice")) && (await text("#notice [data-go]")) === "Open Notes" && (await text("#notice [data-allact]")) === "All activity", await text("#notice"));
    const acts = (await state()).questions.activity, newest = acts[acts.length - 1].text;
    ok("the hold and status are gone and the Claude line falls back to the newest entry", !/Pending research/.test(await text('.qbtn[data-q="Q3"]')) && await page.$eval("#pendBtn", el => el.hidden) && (await text("#claudeLine")).startsWith(newest), await text("#claudeLine"));
    ok("the header derives Round 2 · Interview", (await text("#roundLbl")) === "Round 2 · Interview", await text("#roundLbl"));
    await tap("#notice [data-go]", 300);
    ok("Open shows Claude's reply in Notes", await page.evaluate(() => document.getElementById("fly").classList.contains("open") && /Yes, on track/.test(document.getElementById("fbody").innerText)));
    ok("the notice moves on to Round 2 added, and Go names the question it opens", /Round 2 added: Q6, Q7/.test(await text("#notice")) && (await text("#notice [data-go]")) === "Go to Q6", await text("#notice"));
    await page.click("#flyClose");
    await page.click("#railBtn"); await page.selectOption("#filter", "all"); await page.waitForTimeout(200);
    ok("the new round's group is expanded and highlighted", await page.$eval('.sec[data-key="g:g3"]', el => el.dataset.collapsed === "false" && el.classList.contains("fresh")) && await dot("Q6"));
    const chip = await page.$$eval(".qbtn .chip.hot", els => els.filter(el => !/after your answer/.test(el.textContent)).map(el => ({t: el.textContent, title: el.title}))).catch(() => []);
    ok("a carried question's chip reads 'carried N round(s)', never 'open open', and explains itself", chip.length > 0 && chip.every(c => /^carried \d+ rounds?$/.test(c.t) && !/open open/.test(c.t) && c.title.length > 0), JSON.stringify(chip));
    ok("Q3's heads-up reply after its answer puts the after-answer chip on its card", /Replied after your answer/.test(await text('.qbtn[data-q="Q3"]')), await text('.qbtn[data-q="Q3"]'));
    ok("an entry whose text says added highlights no section unless it added questions", await dot("Q1") && !(await page.$eval('.sec[data-key="g:g1"]', el => el.classList.contains("fresh"))));
    await page.selectOption("#filter", "answered"); await tap("#railBtn", 200);
    await tap("#notice [data-go]", 400);
    ok("Go resets the filter, shows the rail and says so", await page.$eval("#filter", el => el.value) === "all" && !(await page.$eval("#layout", el => el.classList.contains("norail"))) && /Showing all to reveal Q6/.test(await text("#toast")), await text("#toast"));
    ok("Go selects Q6 and moves focus to its heading", await sel() === "Q6" && await focused() === "qhead", await sel() + " " + await focused());

    // commitments, page side
    await arm("a"); await tap("[data-save]", 700);
    ok("the header counts commitments on accepted questions only", (await text("#assumeCount")) === "5 to confirm", await text("#assumeCount"));
    const inView = s => page.$eval(s, el => { const r = el.getBoundingClientRect(), v = document.getElementById("dscroll").getBoundingClientRect(); return r.top >= v.top - 2 && r.top < v.bottom; }).catch(() => false);
    await pick("Q6");
    ok("an accepted card with unconfirmed commitments links to its To confirm entries", (await text('[data-toconfirm="Q6"]')) === "Open in To confirm");
    await tap('[data-toconfirm="Q6"]', 400);
    ok("the card link opens the summary scrolled to Q6's entries", await sel() === "summary" && await inView("#tc-Q6"));
    await tap("#assumeCount", 400);
    ok("the link opens To confirm grouped by question", await sel() === "summary" && (await page.$$eval("#toConfirm .crows", els => els.length)) === 3 && /Things your answers commit you to/.test(await text("#toConfirm")), await text("#toConfirm"));
    ok("the header link scrolls to the list and each group links to its question", await inView("#toConfirm") && await page.$$eval("#toConfirm .crows", els => els.every(e => !!e.querySelector('.ref[data-q="' + e.id.slice(3) + '"]'))));
    const n0 = (await events()).length;
    await tap('#toConfirm [data-cq="Q1"][data-confirm="0"]', 700);
    const ev = await events(), cf = ev[ev.length - 1];
    ok("a tick posts one confirm and lowers the count", ev.length === n0 + 1 && cf.kind === "confirm" && cf.id === "Q1" && cf.alt === "0" && (await text("#assumeCount")) === "4 to confirm", JSON.stringify(cf) + " " + await text("#assumeCount"));
    await page.focus("#sc-Q6-1"); await page.evaluate(() => { document.getElementById("sc-Q6-1").__mark = 1; });
    await post({kind: "note", text: "A note while a tick has focus"}); await page.waitForTimeout(900);
    ok("a state push keeps the focused commitment tick", await page.evaluate(() => { const t = document.getElementById("sc-Q6-1"); return !!t && t.__mark === 1 && document.activeElement === t; }));

    // the Activity panel from the Claude line, the l key and the sheet
    await tap("#claudeLine", 300);
    const all = (await state()).questions.activity;
    const panel = await page.evaluate(() => { const lis = [...document.querySelectorAll("#fbody .act-list li")]; return {open: document.getElementById("fly").classList.contains("open"), title: document.getElementById("flyTitle").textContent, first: lis.length ? lis[0].innerText : "", times: lis.filter(li => li.querySelector("time")).length, refs: document.querySelectorAll("#fbody .act-list .ref[data-q]").length, badge: document.getElementById("actBadge").hidden}; });
    ok("the Claude line opens Activity, newest first with times and question links, and clears the badge", panel.open && panel.title === "Activity" && panel.first.includes(all[all.length - 1].text) && panel.times === all.length && panel.refs > 0 && panel.badge, JSON.stringify(panel).slice(0, 200));
    const split = await page.evaluate(() => { const log = document.getElementById("actLog"); return {needs: document.getElementById("actNeeds").textContent, log: log ? log.querySelector("summary").textContent : "", open: log ? log.open : null, inLog: log ? [...log.querySelectorAll("li")].map(li => li.textContent) : []}; });
    const nn = +/\((\d+)\)/.exec(split.needs)[1], nl = +/\((\d+)\)/.exec(split.log)[1];
    ok("Activity splits Needs you from a collapsed Log that holds the ledger churn", nn > 0 && nn + nl === all.length && split.open === false && split.inLog.some(t => /Added a retry note to Q1/.test(t)) && !split.inLog.some(t => /Round 2 added/.test(t)), JSON.stringify(split).slice(0, 240));
    const seen = await page.evaluate(() => Object.keys(localStorage).filter(k => /:actSeen$/.test(k)).map(k => localStorage.getItem(k)).join(""));
    ok("the seen marker stores no entry text", seen.length > 0 && !seen.includes("Round 2 added"), seen.slice(0, 120));
    ok("the seen marker keys each entry by its seq", all.every(e => Number.isInteger(e.seq)) && all.every(e => JSON.parse(seen).includes("s" + e.seq)), seen.slice(0, 120));
    await page.click("#flyClose"); await page.click("#title"); await page.keyboard.press("l"); await page.waitForTimeout(200);
    const byKey = await page.evaluate(() => document.getElementById("fly").classList.contains("open") && document.getElementById("flyTitle").textContent === "Activity");
    await page.keyboard.press("?"); await page.waitForTimeout(150);
    ok("l opens Activity and the shortcut sheet lists it", byKey && /Activity/.test(await page.evaluate(() => document.getElementById("keysBody").innerText)), String(byKey));
    await page.keyboard.press("Escape"); await page.keyboard.press("Escape"); await page.waitForTimeout(150);
  }
  if (PHASE === 4) {
    await page.waitForTimeout(900); // SSE brings Claude's confirm-commitments and the restatement
    const nt4 = await text("#notice");
    ok("a restatement to confirm keeps the notice over the Notes reply that followed it", /restated the shared understanding/i.test(nt4) && !/Claude replied in Notes/.test(nt4) && (await text("#notice [data-go]")) === "Go to the summary" && (await state()).questions.notes.length > 0, nt4);

    // Claude-side confirmation and Confirm all
    ok("Claude's confirmation leaves Q2's list, shows its reason and lowers the count", !(await page.$('#toConfirm [data-cq="Q2"]')) && /Q2 \(Confirmed in the terminal\)/.test(await text("#byClaude")) && (await text("#assumeCount")) === "3 to confirm", (await text("#assumeCount")) + " / " + await text("#byClaude"));
    ok("a terminal accept mirrored with record-terminal, then confirmed by Claude, leaves no part of Q4 to confirm", !(await page.$('#toConfirm [data-cq="Q4"]')) && /Q4 \(Said yes in the terminal\)/.test(await text("#byClaude")), await text("#toConfirm"));
    const f4 = await page.$eval("#filter", el => el.value);
    await page.selectOption("#filter", "open"); await page.waitForTimeout(200);
    const open4 = (await page.$$eval(".rail-list .qbtn", els => els.map(e => e.dataset.q))).join(",");
    await page.selectOption("#filter", f4); await page.waitForTimeout(150);
    const cards4 = await text('.qbtn[data-q="Q2"]') + await text('.qbtn[data-q="Q4"]');
    ok("Claude's confirm-commitments line after an answer is not a reply: Q2 and Q4 stay settled, off Show: Open and without the after-answer chip", !/Q[24]/.test(open4) && !/after your answer/.test(cards4) && /Q3/.test(open4) && (await text("#meterText")) === "4 of 7 answered", open4 + " / " + cards4 + " / " + await text("#meterText"));
    ok("Wrap up warns while assumptions are open and stays enabled", /^3 assumptions not confirmed yet\.$/.test(await text("#openAssumeWarn")) && !(await page.$eval('[data-wrapup="1"]', el => el.disabled)), await text("#openAssumeWarn"));
    const n1 = (await events()).length;
    await tap("[data-confirmall]", 1500);
    const added = (await events()).slice(n1);
    ok("Confirm all posts one confirm per unconfirmed commitment", added.length === 3 && added.every(e => e.kind === "confirm") && await page.$eval("#assumeCount", el => el.hidden), added.map(e => e.id + ":" + e.alt).join(","));
    ok("the open-assumptions warning is gone after Confirm all", !(await page.$("#openAssumeWarn")));

    // confirm understanding
    ok("the summary shows the restatement with Confirm and Something's off", /Ship green builds to staging/.test(await text("#restate")) && /Left to the plan stage/.test(await text("#restate")) && !!(await page.$('[data-understand="confirm"]')) && !!(await page.$('[data-understand="off"]')), (await text("#restate")).slice(0, 160));
    ok("Wrap up warns Understanding not confirmed yet", /Understanding not confirmed yet/.test(await text("#unconfWarn")));
    for (const [w, h] of [[1440, 900], [390, 844]]) {
      await page.setViewportSize({width: w, height: h}); await page.waitForTimeout(200);
      const hit = await page.evaluate(() => { const a = document.querySelector('[data-understand="confirm"]').getBoundingClientRect(), b = document.getElementById("offText").getBoundingClientRect(); return !(a.right <= b.left || b.right <= a.left || a.bottom <= b.top || b.bottom <= a.top); });
      ok("at " + w + "x" + h + " Confirm does not overlap the What-is-off box", !hit);
    }
    await page.setViewportSize({width: 1400, height: 860}); await page.waitForTimeout(200);
    const n2 = (await events()).length;
    await tap('[data-understand="off"]', 400);
    ok("Something's off needs text: nothing posts without it", (await events()).length === n2 && /Say what is off first/.test(await text("#restate")), await text("#restate"));
    await page.click("#offText"); await page.keyboard.type("The goal misses production");
    await page.evaluate(() => { document.getElementById("offText").__mark = 1; });
    await post({kind: "note", text: "A note that pushes new state"}); await page.waitForTimeout(900);
    ok("a state push keeps the typed box, its text and focus", await page.evaluate(() => { const t = document.getElementById("offText"); return !!t && t.__mark === 1 && t.value === "The goal misses production" && document.activeElement === t; }));
    await tap('[data-understand="off"]', 800);
    const off = await last();
    ok("Something's off posts the text and the restatement rev, and the summary shows it flagged", off.kind === "confirm-understanding" && off.alt === "off" && off.text === "The goal misses production" && off.contentRev === 1 && /You flagged/.test(await text("#restate")), JSON.stringify(off));
    const stale = await post({kind: "confirm-understanding", alt: "confirm", text: "", contentRev: 0});
    ok("a confirm on an old restatement is refused as stale", stale.status() === 409, stale.status());

    // set up the revise while answering
    await pick("Q7"); await page.fill("#note", "My own take"); await arm("o"); await page.keyboard.press("Escape");
    ok("setup: Q7 armed as own with a note before the external revise", /Own answer/.test(await text(".choice.armed")) && (await page.inputValue("#note")) === "My own take", await text(".choice.armed"));
  }
  if (PHASE === 5) {
    await page.waitForTimeout(900); // SSE brings the revise of Q7 and the new restatement

    // revise while typing, undo, reopen
    await page.click("#qhead"); await page.keyboard.press("Control+Enter"); await page.waitForTimeout(700);
    ok("a revise while answering shows the conflict banner and keeps the note", !(await page.$eval("#conflict", el => el.hidden)) && (await page.inputValue("#note")) === "My own take");
    await tap('[data-conflict="mine"]', 800);
    const km = await last();
    ok("Keep mine saves the own answer", km.id === "Q7" && km.kind === "own" && km.text === "My own take", JSON.stringify(km));
    await tap("[data-undo]", 800);
    const un = await last();
    ok("Undo withdraws the save and Q7 is open again", un.kind === "undo" && await sel() === "Q7" && /Open/.test(await text('.qbtn[data-q="Q7"] .chip')), un.kind + " " + await sel());
    await arm("a"); await tap("[data-save]", 800);
    await tap('[data-act="reopen"]', 800);
    const ro = await last();
    ok("Reopen records a reopen", ro.kind === "reopen" && ro.id === "Q7", JSON.stringify(ro));

    ok("the reopened question keeps its note under Your earlier answer, not in the note box", (await page.inputValue("#note")) === "" && /My own take/.test(await text("#earlier")), (await page.inputValue("#note")) + " | " + await text("#earlier"));

    // Accept all per round in the Rounds view carries only a note typed on the question
    await tap('.seg [data-view="rounds"]', 200);
    const rb = await text('[data-acceptround="interview:2"]');
    await tap('[data-acceptround="interview:2"]', 200);
    const rd = await page.evaluate(() => document.getElementById("dlg").open ? document.getElementById("dlgBody").innerText : "");
    ok("Accept all per round lists Q7 without the reopened note", rb === "Accept all (1)" && /Q7/.test(rd) && !/Note:/.test(rd), rb + " / " + rd.replace(/\s+/g, " ").slice(0, 160));
    await page.click("#dlgCancel"); await tap('.seg [data-view="groups"]', 200);

    // offline, then the catch-up when the tab becomes visible
    await page.context().setOffline(true);
    await page.evaluate(() => { Object.defineProperty(document, "visibilityState", {configurable: true, get: () => "visible"}); document.dispatchEvent(new Event("visibilitychange")); });
    const wentOff = await until(() => /^Connection lost: check the terminal$/.test(document.getElementById("pill").textContent), 8000);
    ok("a dropped connection reads Connection lost: check the terminal and announces it", wentOff && await page.$eval("#pill", el => el.getAttribute("aria-live")) === "polite", await text("#pill"));
    await page.context().setOffline(false);
    await post({id: "Q4", kind: "ask", text: "Asked while the tab was away"});
    const fetched = [], t0 = Date.now();
    page.on("request", r => { if (/\/api\/state$/.test(r.url())) fetched.push(Date.now() - t0); });
    await page.evaluate(() => document.dispatchEvent(new Event("visibilitychange")));
    const back = await until(() => !/^Connection lost/.test(document.getElementById("pill").textContent), 10000);
    await page.waitForTimeout(500);
    ok("becoming visible re-fetches /api/state and shows what happened meanwhile", back && fetched.length > 0 && fetched[0] < 1000 && /Sent to Claude/.test(await text('.qbtn[data-q="Q4"]')), "fetched at " + fetched.join(",") + " ms");

    // confirm understanding after a new restate, then wrap up
    await tap("#sumBtn", 300);
    ok("a changed restatement raises a persistent banner, and there is no diff without a confirmed earlier rev", !(await page.$eval("#reBanner", el => el.hidden)) && /^Restatement changed, needs your Confirm\./.test(await text("#reBanner")) && !(await page.$("#reDiff")), await text("#reBanner"));
    ok("a new restate resets the summary to unconfirmed",!!(await page.$('[data-understand="confirm"]')) && /Understanding not confirmed yet/.test(await text("#unconfWarn")) && /linked issues in the release notes/.test(await text("#restate")), (await text("#restate")).slice(0, 160));
    const u0 = (await events()).length;
    await page.route("**/api/answer", r => r.fulfill({status: 409, contentType: "application/json", body: '{"error": "stale", "contentRev": 9}'}), {times: 1});
    await tap('[data-understand="confirm"]', 800);
    ok("a stale Confirm tells the user the restatement changed and records nothing", /restated the understanding while you read it/.test(await text("#restate")) && (await events()).length === u0, (await text("#restate")).slice(-120));
    await tap('[data-understand="confirm"]', 800);
    const cu = await last();
    ok("Confirm posts confirm-understanding and the summary reads Confirmed with its time", cu.kind === "confirm-understanding" && cu.alt === "confirm" && cu.contentRev === 2 && /^Confirmed \S/.test(await text("#uDone")) && !(await page.$("#unconfWarn")), JSON.stringify(cu) + " " + await text("#uDone"));
    ok("a Confirm clears the banner", await page.$eval("#reBanner", el => el.hidden));
    const w0 = (await events()).length, chip = await text("#wrapChip");
    ok("the header chip counts what is outstanding before wrap-up", /^\d+ before wrap-up$/.test(chip) && !(await page.$eval("#wrapChip", el => el.hidden)), chip);
    await tap("#wrapChip", 300);
    const viaChip = await page.$$eval("#dlgBody li", ls => ls.map(l => l.textContent));
    ok("the chip opens the confirm list, with Wrap up anyway, and sends nothing", await page.$eval("#dlg", d => d.open) && viaChip.length === parseInt(chip, 10) && viaChip.some(x => /^\d+ questions? (is|are) still open: Q\d/.test(x)) && (await text("#dlgOk")) === "Wrap up anyway" && (await events()).length === w0, viaChip.join(" | "));
    await tap("#dlgCancel", 300);
    await tap("[data-wrapup]", 300);
    const viaBtn = await page.$$eval("#dlgBody li", ls => ls.map(l => l.textContent));
    ok("Wrap up lists the same items and sends nothing until the user confirms", await page.$eval("#dlg", d => d.open) && viaBtn.join("|") === viaChip.join("|") && (await events()).length === w0, viaBtn.join(" | "));
    await tap("#dlgCancel", 300);
    ok("Cancel sends no event and starts no freeze", (await events()).length === w0 && !(await page.$("dialog#dlg[open]")));
    await tap("[data-wrapup]", 300);
    await tap("#dlgOk", 700);
    const wr = await events();
    ok("Wrap up posts one wrapup event", wr.length === w0 + 1 && wr[wr.length - 1].kind === "wrapup");
    ok("a forced wrap-up names every skipped item in its text", /^Skipped before wrap-up:\n/.test(wr[wr.length - 1].text) && viaBtn.every(x => wr[wr.length - 1].text.includes("- " + x)), wr[wr.length - 1].text);
    ok("after the wrap-up the header chip is gone", await page.$eval("#wrapChip", el => el.hidden));
  }
  if (PHASE === 6) { // the shell settled Q5 and Q7 in the terminal, held Q3 on research again, and made Release depend on Build
    await page.waitForTimeout(900);
    ok("with only pending research left the summary says your part is done", (await text("#dscroll .done-h")) === "Your part is done for now. Claude is researching Q3.", await text("#dscroll .done-h"));
    ok("a research hold keeps the dependent group locked", /opens after Build/.test(await text('.sec[data-key="g:g3"] .lock')), await text('.sec[data-key="g:g3"]'));

    // a Claude line and a hold near their 500-character caps never widen the page
    for (const w of [360, 1400]) {
      await page.setViewportSize({width: w, height: 860});
      // a long unbroken question id keeps its rail row compact, the title readable and the chip whole
      const long = "Q8_runner_image_cache_key_follow_up_0123456789";
      await pick(long);
      const row = await page.evaluate(id => {
        const list = document.getElementById("railList"), b = list.querySelector('.qbtn[data-q="' + id + '"]'), r = b.getBoundingClientRect(), c = b.querySelector(".chip").getBoundingClientRect();
        return {scroll: list.scrollWidth, client: list.clientWidth, h: Math.round(r.height), title: Math.round(b.querySelector(".qtitle").getBoundingClientRect().width), chip: c.width > 0 && c.right <= r.right + 0.5, full: b.querySelector(".qid").title === id};
      }, long);
      ok("at " + w + " px a long unbroken question id keeps the rail from scrolling sideways, its row under 200 px, its title 100 px wide and its chip whole", row.scroll <= row.client && row.h < 200 && row.title >= 100 && row.chip && row.full, JSON.stringify(row));
      const fit = [];
      for (const v of ["Q3", "summary"]) {
        if (v === "summary") await tap("#sumBtn", 300); else await pick(v);
        fit.push(await page.evaluate(() => {
          const W = innerWidth, inView = id => { const r = document.getElementById(id).getBoundingClientRect(); return r.left >= 0 && r.right <= W; };
          return {scroll: document.scrollingElement.scrollWidth, W, wrap: inView("sumBtn"), counts: ["meterText", "pendBtn", "assumeCount"].every(id => document.getElementById(id).hidden || inView(id)), line: document.getElementById("clText").textContent.length};
        }));
      }
      ok("at " + w + " px the long Claude line and hold keep the page, Wrap up and the counts in the viewport", fit.every(f => f.scroll <= f.W && f.wrap && f.counts && f.line > 400), JSON.stringify(fit));
    }
  }
  if (PHASE === 7) { // the shell cleared Q3's hold
    await page.waitForTimeout(900);
    ok("clearing the hold unlocks the dependent group", !(await page.$('.sec[data-key="g:g3"] .lock')) && !(await page.$eval('.sec[data-key="g:g3"]', el => el.classList.contains("locked"))));
    ok("the summary reads All answered once the research returns", (await text("#dscroll .done-h")) === "All answered", await text("#dscroll .done-h"));

    // no watcher has polled since phase 1: calm while nothing waits on Claude, a prompt once something does
    const calm = await until(() => document.getElementById("pill").textContent === "Idle", 40000);
    ok("with nothing pending and no watcher the pill reads Idle, not an error", calm && await page.$eval("#pill", el => el.className === "pill rest" && el.getAttribute("aria-live") === "off"), await text("#pill"));
    await post({kind: "note", text: "Anything else?"});
    const prompt = await until(() => document.getElementById("pill").textContent === "Not listening: type next", 5000);
    ok("once an event waits on Claude the pill says Not listening: type next", prompt && await page.$eval("#pill", el => el.className === "pill idle"), await text("#pill"));
    await page.evaluate(b => { window.__badge7 = b; }, await badge());
  }
  if (PHASE === 14) { // the shell added Q9; the user answers it with their own text
    await page.waitForSelector('.qbtn[data-q="Q9"]', {state: "attached", timeout: 5000});
    const nq = await page.evaluate(() => { const t = document.getElementById("needToast"); return {hidden: t.hidden, text: t.innerText}; });
    ok("a new Needs-you entry raises a dismissible toast naming it", !nq.hidden && /Q9/.test(nq.text) && /Dismiss/.test(nq.text), JSON.stringify(nq));
    await page.evaluate(() => {
      window.__np = {asked: 0, made: []};
      window.Notification = class { constructor(t, o) { window.__np.made.push((o || {}).body || t); } static permission = "default"; static requestPermission() { window.__np.asked++; window.Notification.permission = "granted"; return Promise.resolve("granted"); } };
    });
    await until(() => !!document.querySelector("#needToast [data-notify]"), 4000);
    ok("the toast offers a browser notification and asks for nothing until clicked", (await page.$$("#needToast [data-notify]")).length === 1 && await page.evaluate(() => window.__np.asked) === 0);
    await tap("#needToast [data-notify]", 300);
    ok("one click asks permission once, keeps the answer and drops the offer", await page.evaluate(() => window.__np.asked) === 1 && await page.evaluate(() => Object.keys(localStorage).some(k => /:notify$/.test(k) && localStorage.getItem(k) === "true")) && !(await page.$("#needToast [data-notify]")));
    await tap("#needToast [data-ntdismiss]", 200);
    ok("Dismiss hides the toast", await page.$eval("#needToast", el => el.hidden));
    if (await page.$eval("#fly", el => el.classList.contains("open"))) { await page.click("#title"); await page.keyboard.press("l"); await page.waitForTimeout(300); }
    await pick("Q9"); await page.fill("#note", "what are the patterns?"); await arm("o"); await page.click("#note"); await page.keyboard.press("Control+Enter"); await page.waitForTimeout(800);
    const own = await last();
    ok("the own answer on Q9 is saved from the page with the note still focused", own.id === "Q9" && own.kind === "own" && own.text === "what are the patterns?", JSON.stringify(own));
    await setHidden(true); // phase 15's revision lands on a hidden tab
  }
  if (PHASE === 15) { // the shell revised Q9's recommendation in response to that own text
    await page.waitForTimeout(900);
    ok("a Needs-you entry on a hidden tab raises the browser notification the user enabled", await page.evaluate(() => window.__np.made.length) >= 1, JSON.stringify(await page.evaluate(() => window.__np)));
    await setHidden(false); await page.waitForTimeout(900);
    await pick("Q9");
    ok("the revision sets the own answer aside: the rail reads Open and the card says the answer no longer counts", (await text('.qbtn[data-q="Q9"] .chip')) === "Open" && /Own answer: .*aside\. It no longer counts\./.test(await text("#cur")) && !(await page.$('[data-act="reopen"]')), (await text('.qbtn[data-q="Q9"] .chip')) + " / " + await text("#cur"));
    ok("the note no longer shows the set-aside own text", (await page.inputValue("#note")) === "", await page.inputValue("#note"));
    await tap("[data-again]", 300);
    await arm("a"); await page.keyboard.press("Control+Enter"); await page.waitForTimeout(800);
    const acc = await last();
    ok("Ctrl+Enter accepts the revised recommendation, not the old own text", acc.id === "Q9" && acc.kind === "accept" && acc.text === "", JSON.stringify(acc));
  }
  if (PHASE === 16) { // after the wrap-up: the shell added Q10, put "Q1-Q3" in Q6's facts and posted a third restatement
    await page.waitForSelector('.qbtn[data-q="Q10"]', {state: "attached", timeout: 5000});
    await page.waitForTimeout(600);
    const nt16 = await text("#notice"); // before any question is opened: opening one marks the entries naming it seen
    ok("after the wrap-up a restatement to confirm still outranks the later Notes reply in the notice", /restated the shared understanding/i.test(nt16) && !/Claude replied in Notes/.test(nt16) && (await text("#notice [data-go]")) === "Go to the summary", nt16);
    if (await page.$eval("#fly", el => el.classList.contains("open"))) { await page.click("#title"); await page.keyboard.press("l"); await page.waitForTimeout(300); }
    // one label scheme
    await pick("Q10");
    const rows = await page.$$eval("#choices .choice", rs => rs.map(r => ({b: r.querySelectorAll("b").length, label: r.querySelector("b").textContent, n: !!r.querySelector(".n"), keys: r.querySelector("input").getAttribute("aria-keyshortcuts")})));
    ok("every option has one visible label and no number; Rec leads and Accept with note is its own row", rows.every(r => r.b === 1 && !r.n) && rows.slice(0, 3).map(r => r.label).join() === "Rec,Accept with note,(a)", JSON.stringify(rows));
    ok("number keys stay as shortcuts on every row", rows.every((r, i) => r.keys.startsWith(String(i + 1))), JSON.stringify(rows.map(r => r.keys)));
    ok("the detail names the recommendation and the alternatives by the same labels", /Recommendation \(Rec\)/.test(await text("#dscroll")) && (await page.$$eval("#dscroll .alt .k", ks => ks.map(k => k.textContent))).join() === "(a),(b)");
    // the note box
    await arm("2");
    ok("Accept with note needs a note: Save stays disabled until one is typed", await page.$eval("[data-save]", b => b.disabled) && /Accept with note needs a note/.test(await text("#decideRow")), await text("#decideRow"));
    await page.fill("#note", "but check the cache key");
    ok("with a note typed Save reads Accept with note", (await text("[data-save]")) === "Save: Accept with note" && !(await page.$eval("[data-save]", b => b.disabled)), await text("[data-save]"));
    await tap("[data-save]", 800);
    const an = await last();
    ok("Accept with note records an accept carrying the note and stays on Q10", an.id === "Q10" && an.kind === "accept" && an.text === "but check the cache key" && await sel() === "Q10", JSON.stringify(an) + " " + await sel());
    ok("the note box is empty after the save; the note shows read-only under Your earlier answer", (await page.inputValue("#note")) === "" && /^Your earlier answer/.test(await text("#earlier")) && /but check the cache key/.test(await text("#earlier")) && await page.$eval("#earlier q", q => !q.isContentEditable), await text("#earlier"));
    await arm("a"); await tap("[data-save]", 800);
    const a2 = await last();
    ok("pressing Accept again sends an empty text", a2.id === "Q10" && a2.kind === "accept" && a2.text === "" && a2.seq > an.seq, JSON.stringify(a2));
    await pick("Q5");
    ok("a decision settled in the terminal opens with an empty note box and shows its text read-only", (await page.inputValue("#note")) === "" && /Pin it to the lock file\./.test(await text("#earlier")), (await page.inputValue("#note")) + " | " + await text("#earlier"));
    await pick("Q10"); await arm("o");
    await page.fill("#note", "look into this");
    ok("a note ending in this is not flagged as cut off", !(await page.$("#cutNudge")), await text("#decideRow"));
    await page.fill("#note", "look into this and");
    ok("a note ending in and is flagged", !!(await page.$("#cutNudge")), await text("#decideRow"));
    await tap("[data-clear]", 200);
    // a note that starts from a label the card shows
    const dialogOf = async () => page.evaluate(() => { const d = document.getElementById("dlg"); return {open: d.open, title: document.getElementById("dlgTitle").textContent, ok: document.getElementById("dlgOk").textContent, alt: document.getElementById("dlgAlt").hidden ? "" : document.getElementById("dlgAlt").textContent}; });
    const typed = async (t, kind) => { await pick("Q10"); await arm(kind || "o"); await page.fill("#note", t); await tap("[data-save]", 400); };
    const r0 = (await events()).length;
    await typed("#1, but check the cache key");
    const dg = await dialogOf();
    ok("an own note starting with #1 asks Did you mean Accept with note? before saving", dg.open && dg.title === "Did you mean Accept with note?" && dg.ok === "Accept with note" && dg.alt === "Save as own answer" && (await events()).length === r0, JSON.stringify(dg));
    await page.keyboard.press("Escape"); await page.waitForTimeout(300);
    ok("Escape sends nothing and keeps the note", (await events()).length === r0 && (await page.inputValue("#note")) === "#1, but check the cache key" && !(await page.$("dialog#dlg[open]")));
    await tap("[data-save]", 300); await tap("#dlgAlt", 700);
    const o1 = await last();
    ok("Save as own answer keeps the note as typed", (await events()).length === r0 + 1 && o1.id === "Q10" && o1.kind === "own" && o1.text === "#1, but check the cache key", JSON.stringify(o1));
    await typed("(a) is closer, but check the jobs"); await tap("#dlgOk", 700);
    const o2 = await last();
    ok("a note naming (a) records that alternative with the note", o2.id === "Q10" && o2.kind === "alt" && o2.alt === "a" && o2.text === "(a) is closer, but check the jobs", JSON.stringify(o2));
    const r1 = (await events()).length;
    await typed("#1 and (a) together, in this order");
    ok("a note naming two options is saved as an own answer without asking", (await events()).length === r1 + 1 && (await last()).kind === "own" && !(await page.$("dialog#dlg[open]")), JSON.stringify(await last()));
    await typed("see #123 for the cache key");
    ok("a bare issue number is not a label", (await last()).text === "see #123 for the cache key" && (await last()).kind === "own", JSON.stringify(await last()));
    await pick("Q10"); await page.fill("#note", "#1, is the cache shared?"); await tap('[data-act="ask"]', 400);
    const da = await dialogOf(), r2 = (await events()).length;
    ok("Ask Claude on a note starting with #1 asks the same, with Send as a question", da.open && da.title === "Did you mean Accept with note?" && da.alt === "Send as a question", JSON.stringify(da));
    await page.keyboard.press("Escape"); await page.waitForTimeout(300);
    ok("backing out of the ask sends nothing", (await events()).length === r2 && (await page.inputValue("#note")) === "#1, is the cache shared?");
    await tap("[data-clear]", 200);
    await typed("#1, but check the cache key"); await tap("#dlgOk", 700);
    const o3 = await last();
    ok("choosing Accept with note records an accept carrying the note", o3.id === "Q10" && o3.kind === "accept" && o3.text === "#1, but check the cache key", JSON.stringify(o3));
    // the range chip
    await pick("Q6");
    const rr = await page.$$eval("#more .rrange", r => r.map(x => [x.textContent, x.querySelectorAll(".ref").length]));
    ok("Q1-Q3 renders as one chip-range and Q6 and Q9 stay separate chips", rr.length === 1 && rr[0][0] === "Q1–Q3" && rr[0][1] === 2 && (await page.$$eval("#more .ref", rs => rs.filter(r => !r.closest(".rrange")).map(r => r.dataset.q).join())) === "Q6,Q9", JSON.stringify(rr));
    // the summary at 1024 px
    await page.setViewportSize({width: 1024, height: 800});
    await tap("#sumBtn", 500);
    const df = await page.evaluate(() => { const d = document.getElementById("reDiff"); return d ? {head: d.querySelector("b").textContent, sec: [...d.querySelectorAll("h5")].map(h => h.textContent).join(), del: [...d.querySelectorAll("del")].map(x => x.textContent.trim()).join("|"), ins: [...d.querySelectorAll("ins")].map(x => x.textContent.trim()).join("|")} : null; });
    ok("the restatement shows a line diff against the newest confirmed rev", !!df && /rev 2/.test(df.head) && df.sec === "Constraints" && /Builds stop at ten minutes\./.test(df.del) && /share one cache/.test(df.ins), JSON.stringify(df));
    ok("after the wrap-up the banner is not shown, since Confirm is gone", await page.$eval("#reBanner", el => el.hidden));
    const sum = await page.evaluate(() => {
      const broken = [], tbl = document.querySelector("table.sum");
      tbl.querySelectorAll("td, th").forEach(c => {
        const w = document.createTreeWalker(c, NodeFilter.SHOW_TEXT);
        let n;
        while ((n = w.nextNode())) for (const m of n.nodeValue.matchAll(/[^\s-]+/g)) {
          const r = document.createRange(); r.setStart(n, m.index); r.setEnd(n, m.index + m[0].length);
          if (new Set([...r.getClientRects()].map(x => Math.round(x.top))).size > 1) broken.push(m[0]);
        }
      });
      const rows = [...tbl.tBodies[0].rows];
      return {broken, n: rows.length, empty: rows.filter(r => !r.cells[2].textContent.trim()).length, chip: Math.max(...[...tbl.querySelectorAll(".ref b")].map(b => b.getBoundingClientRect().height)),
        q5: (rows.find(r => r.cells[0].textContent.startsWith("Q5")) || {cells: [{}, {}, {}]}).cells[2].textContent, q9: (rows.find(r => r.cells[0].textContent.startsWith("Q9")) || {cells: [{}, {}, {}]}).cells[2].textContent};
    });
    ok("at 1024 px no Decisions cell breaks inside a word and each id chip stays on one line", sum.n > 5 && sum.broken.length === 0 && sum.chip < 24, JSON.stringify(sum));
    ok("every answered row shows what was decided", sum.empty === 0 && /Pin it to the lock file\./.test(sum.q5) && /^All of them/.test(sum.q9), JSON.stringify(sum));
    ok("after the wrap-up the summary shows no Confirm, Something's off or Confirm all", !(await page.$("[data-understand]")) && !(await page.$("[data-confirmall]")) && (await page.$$("#toConfirm [data-confirm]")).length > 0 && /Not confirmed; wrap-up already sent/.test(await text("#uDone")), await text("#restate"));
    ok("only one control is labeled Finish: export and end the session, and it sends the wrap-up event", await page.$$eval("button", bs => bs.filter(b => b.textContent.trim() === "Finish: export and end the session").map(b => b.hasAttribute("data-wrapup")).join()) === "true");
    ok("each panel button has a name that is not a number", await page.$$eval(".strip button", bs => bs.every(b => /\D/.test(b.getAttribute("aria-label") || ""))));
    // the header at 420 px
    await page.setViewportSize({width: 420, height: 800}); await page.waitForTimeout(300);
    const meter = await page.evaluate(() => ({h: [...document.querySelectorAll(".meter button")].filter(b => !b.hidden).map(b => Math.round(b.getBoundingClientRect().height)), page: document.scrollingElement.scrollWidth}));
    ok("at 420 px the header counts each stay on one line", meter.h.length >= 2 && meter.h.every(h => h < 26) && meter.page <= 420, JSON.stringify(meter));
  }
  if (PHASE === 8) { // the shell added activity while the tab was visible
    await page.waitForTimeout(900);
    const base = await text("#title");
    const newest = (await state()).questions.activity.pop();
    ok("on a visible tab new activity leaves the title unchanged", /while you were looking/.test(newest.text) && await page.title() === base, newest.text + " / " + await page.title());
    ok("a log entry that needs nobody does not raise the Activity badge or the notice", (await badge()) === await page.evaluate(() => window.__badge7) && !/while you were looking/.test(await text("#notice")), (await badge()) + " " + await text("#notice"));
    await setHidden(true); await page.waitForTimeout(200);
    ok("hiding the tab adds no badge for activity already waiting", await page.title() === base, await page.title());
  }
  if (PHASE === 9) { // the shell added one activity entry while the tab was hidden
    await page.waitForTimeout(900);
    const base = await text("#title");
    ok("a Needs-you entry that lands while the tab is hidden prefixes the title with a count, and the log entry beside it adds none", await page.title() === "(1) " + base && (await state()).questions.activity.some(e => /again while the tab was hidden/.test(e.text)), await page.title());
    await setHidden(false); await page.waitForTimeout(200);
    ok("showing the tab again restores the plain title", await page.title() === base, await page.title());
  }
  if (PHASE === 10) { // Activity panel left open, then the tab is hidden
    await page.click("#title"); await page.keyboard.press("l"); await page.waitForTimeout(300);
    const base = await text("#title");
    await setHidden(true); await page.waitForTimeout(200);
    ok("hiding the tab with the Activity panel open adds no badge", await page.title() === base && await page.$eval("#fly", el => el.classList.contains("open")), await page.title());
  }
  if (PHASE === 11) { // the shell added activity while the tab was hidden and the panel open
    await page.waitForTimeout(4000);
    const base = await text("#title");
    ok("an open Activity panel marking entries seen does not hide the title count", await page.title() === "(1) " + base, await page.title());
    await setHidden(false); await page.waitForTimeout(200);
  }
  if (PHASE === 12) { // reload so the page loads already hidden: no visibilitychange fires
    await page.addInitScript(() => { for (const [k, v] of [["hidden", true], ["visibilityState", "hidden"]]) Object.defineProperty(document, k, {configurable: true, get: () => v}); });
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(900);
    ok("a page loaded hidden shows no badge for activity already waiting", await page.title() === await text("#title"), await page.title());
  }
  if (PHASE === 13) { // the shell added one activity entry after the page loaded hidden
    await page.waitForTimeout(4000);
    const base = await text("#title");
    ok("activity landing on a page loaded hidden prefixes the title with a count", await page.title() === "(1) " + base, await page.title());
    await setHidden(false); await page.waitForTimeout(200);
  }
  if (PHASE === 17) { // after the wrap-up the user confirms the third restatement; the shell has written nothing since phase 16
    await page.setViewportSize({width: 1400, height: 860}); await tap("#sumBtn", 300);
    const before = await text("#assumeCount");
    ok("while the understanding is unconfirmed the header counts commitments to confirm", /^\d+ to confirm$/.test(before), before);
    ok("the summary labels the one control Finish: export and end the session", (await text("[data-wrapup]")) === "Finish: export and end the session" && /Finish sent/.test(await text("#sumRest")), await text("#sumRest"));
    const rev = (await state()).questions.restatement.rev, r = await post({kind: "confirm-understanding", alt: "confirm", text: "", contentRev: rev});
    await page.waitForTimeout(900);
    const n = await page.$$eval("#toConfirm [data-confirm]", els => els.length), line = await text("#assumeCount");
    ok("after confirm-understanding the header says what the Confirm did and left", r.ok() && n > 0 && line === "Understanding confirmed · " + n + (n === 1 ? " commitment" : " commitments") + " unticked; they become named risks unless ticked", line);
    const uc = await text("#uCommit");
    ok("the summary explains that Confirm ticks nothing and unticked commitments become named risks, with a link to the list", /does not tick commitments/.test(uc) && /named risks?/.test(uc) && uc.includes(String(n)) && (await page.$$eval("#toConfirm [data-confirm]", els => els.length)) === n && !!(await page.$("#uCommit [data-toconfirm]")), uc);
    await tap("#uCommit [data-toconfirm]", 300);
    ok("the link scrolls to the commitment list", await page.evaluate(() => { const r = document.getElementById("toConfirm").getBoundingClientRect(); return r.top < window.innerHeight && r.bottom > 0; }));
    await page.setViewportSize({width: 420, height: 800}); await page.waitForTimeout(300);
    ok("at 420 px the long line wraps inside the page", await page.evaluate(() => document.scrollingElement.scrollWidth <= 420 && document.getElementById("assumeCount").getBoundingClientRect().right <= 420));
    await page.setViewportSize({width: 1400, height: 860});
  }
  if (PHASE === 18) { // the shell posted a status and a finish op with a Brief path and a next step
    await page.waitForTimeout(900);
    const ft = await page.evaluate(() => ({hidden: document.getElementById("needToast").hidden, text: document.getElementById("needToast").innerText}));
    ok("the finish raises a Needs-you toast reading Interview complete", !ft.hidden && /^Interview complete/.test(ft.text), JSON.stringify(ft));
    const p2 = await page.context().newPage();
    await p2.route(/\/(api\/state|events)(\?.*)?$/, r => r.abort());
    await p2.goto(base);
    const kept = await p2.waitForFunction(() => document.getElementById("finDlg").open, null, {timeout: 8000}).then(() => true).catch(() => false);
    const k2 = kept ? await p2.evaluate(() => ({body: document.getElementById("finBody").innerText, page: document.getElementById("dscroll").innerText, pill: document.getElementById("pill").textContent})) : null;
    await p2.close();
    ok("a tab that cannot reach the server shows the finish this browser kept", !!k2 && /docs\/PLAN\.md/.test(k2.body) && /docs\/PLAN\.md/.test(k2.page) && k2.pill === "Interview finished: server stopped", JSON.stringify(k2));
    const d = await page.evaluate(() => { const el = document.getElementById("finDlg"); return {open: el.open, title: document.getElementById("finTitle").textContent, body: document.getElementById("finBody").innerText}; });
    ok("the finish opens a modal with the Brief path, the next step and that the tab can be closed", d.open && d.title === "Interview complete" && /docs\/PLAN\.md/.test(d.body) && /Run the plan with the next step/.test(d.body) && /You can close this tab/.test(d.body) && /The interview is complete/.test(d.body), JSON.stringify(d));
    ok("the finish is an Activity entry marked finished", (await state()).questions.activity.pop().finished === true);
    await tap("#finClose", 300);
    ok("the modal closes and stays dismissed", !(await page.$eval("#finDlg", el => el.open)) && await page.evaluate(() => Object.keys(localStorage).some(k => /:finSeen$/.test(k))));
    await tap("#sumBtn", 300);
    ok("the summary shows the finished state in place of the Finish control", !!(await page.$("#finished")) && !(await page.$("[data-wrapup]")) && /docs\/PLAN\.md/.test(await text("#finished")) && /You can close this tab/.test(await text("#finished")), await text("#finished"));
    ok("the pill reads Finished and the terminal status is the Claude line", (await text("#pill")) === "Finished" && (await text("#clText")) === "Done: the Brief is written", (await text("#pill")) + " / " + await text("#clText"));
    await tap("#claudeLine", 300);
    const needs = await page.$$eval("#fbody .act-list:first-of-type li", ls => ls.map(l => l.innerText));
    ok("the finish sits under Needs you in Activity", /Interview finished/.test(needs[0] || ""), (needs[0] || "").slice(0, 80));
    await page.click("#flyClose");
  }
  if (PHASE === 19) { // the shell ran round.sh stop
    const off = await until(() => /^Interview finished: server stopped$/.test(document.getElementById("pill").textContent), 15000);
    ok("after stop the pill reads Interview finished: server stopped, not a lost connection", off, await text("#pill"));
    ok("the pill is not a warning and says why on hover", await page.$eval("#pill", el => el.className === "pill rest" && /finished/.test(el.title)), await page.$eval("#pill", el => el.className + " | " + el.title));
    ok("the terminal status stays visible while offline", (await text("#clText")) === "Done: the Brief is written", await text("#clText"));
    await tap("#sumBtn", 300);
    ok("the finished state stays on the summary", !!(await page.$("#finished")) && /docs\/PLAN\.md/.test(await text("#finished")));
  }
  if (PHASE === 20) { // the shell started the server again on the same data dir
    const re = await until(() => /^Server restarted: reload$/.test(document.getElementById("pill").textContent), 15000);
    ok("after a restart on the kept port the pill says the server restarted and to reload", re && await page.$eval("#pill", el => el.className === "pill offline"), await text("#pill"));
    ok("the new server carries no finish", !(await state()).questions.finished);
    ok("a resumed interview drops the finish this browser kept", await page.evaluate(() => localStorage.getItem("iv2:finish")) === null);
  }
  const real = errors.filter(e => !/status of 409 \(Conflict\)/.test(e) && !/ERR_INTERNET_DISCONNECTED|ERR_CONNECTION_(REFUSED|RESET)/.test(e));
  ok("zero console errors in journey phase " + PHASE + " (besides the network lines for an intended 409, the offline step and the stopped server)", real.length === 0, errors.join(" | "));
  } catch (e) { R.push("ERROR " + e.message.split("\n").slice(0, 3).join(" | ")); }
  return R.join("\n");
}
