async page => {
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  const errors = [];
  page.on("console", m => { if (m.type() === "error") errors.push(m.text() + (m.location().url ? " at " + m.location().url : "")); });
  page.on("pageerror", e => errors.push(String(e)));
  const PHASE = __PHASE__;
  const base = "http://127.0.0.1:__PORT__/";
  const state = async () => (await page.request.get(base + "api/state")).json();
  const events = async () => (await state()).responses.events;
  const sel = async () => page.evaluate(() => (document.querySelector('.qbtn[aria-current="true"]') || {}).dataset?.q || (document.querySelector('.sumbtn[aria-current="true"]') ? "summary" : null));
  const pick = async id => {
    if (await page.$eval('.rail-list .qbtn[data-q="' + id + '"]', el => !el.offsetParent).catch(() => false)) await page.click('.sec:has(.qbtn[data-q="' + id + '"]) .sec-h'); // answered groups start collapsed
    await page.click('.rail-list .qbtn[data-q="' + id + '"]'); await page.waitForTimeout(200); };
  const token = async () => page.$eval('meta[name="interview-token"]', m => m.content);
  const post = async body => page.request.post(base + "api/answer", {headers: {"Content-Type": "application/json", "X-Interview-Token": await token()}, data: body});
  const armed = async () => (await page.textContent(".choice.armed").catch(() => "")) || "";
  const focused = async () => page.evaluate(() => document.activeElement.id || document.activeElement.tagName);
  const Q_MARK = "❓", R_MARK = "➡️";
  const recHead = async () => page.evaluate(() => { const h = [...document.querySelectorAll("#dscroll section.blk > h4")].find(x => /Recommendation/.test(x.textContent)); return h ? h.textContent : ""; });
  const openAssumptions = s => { // unconfirmed commitments on questions decided by accept or own (Q24)
    let n = 0;
    for (const q of s.questions.questions) {
      const r = s.responses.responses[q.id], dec = (r && r.decision) || (q.terminal && q.terminal.decision);
      if (!["accept", "hedged", "own"].includes(dec) || q.archived || !(q.commits || []).length) continue;
      const cf = new Set(s.responses.events.filter(e => e.kind === "confirm" && e.id === q.id && !e.withdrawn && !(q.commitsSinceSeq != null && e.seq <= q.commitsSinceSeq)).map(e => String(e.alt)).concat((q.commitsConfirmed || []).map(c => String(c.index))));
      n += q.commits.filter((c, i) => !cf.has(String(i))).length;
    }
    return n;
  };
  const open = n => n + " to confirm";
  const counter = async () => page.evaluate(() => { const el = document.getElementById("assumeCount"); return el && !el.hidden ? el.textContent : ""; });
  try {
  if (PHASE === 1) {
    await page.setViewportSize({width: 1400, height: 860});
    await page.goto(base);
    await page.waitForSelector(".qbtn", {state: "attached"});
    await page.evaluate(() => localStorage.clear());
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"});

    // AC26: no watcher has ever polled and every event is handled, so the calm Idle shows 30 s after load
    const rung5 = await page.waitForFunction(() => /^Idle$/.test(document.getElementById("pill").textContent), null, {timeout: 40000}).then(() => true).catch(() => false);
    ok("AC26: with no watcher and nothing pending the pill reads Idle", rung5 && await page.$eval("#pill", el => el.className === "pill rest"), await page.textContent("#pill"));

    // AC17: number order within a group, whatever the insertion order
    const order = await page.$$eval('.sec[data-key="g:base"] .qbtn', els => els.map(e => e.dataset.q));
    ok("AC17: Q1 renders before Q3 though Q3 was inserted first", order.indexOf("Q1") >= 0 && order.indexOf("Q1") < order.indexOf("Q3"), order.join(","));

    const chipOf = async id => (await page.textContent('.qbtn[data-q="' + id + '"] .qmeta')).replace(/\s+/g, " ").trim();
    ok("a question whose prerequisite is unanswered wears Blocked, not Open", /Blocked/.test(await chipOf("P2")) && !/Open/.test(await chipOf("P2")) && /Open/.test(await chipOf("P1")), await chipOf("P2") + " | " + await chipOf("P1"));

    ok("a question whose only prerequisite is archived is Open, not Blocked, and names it", /Open/.test(await chipOf("X2")) && !/Blocked/.test(await chipOf("X2")) && /needs X1 \(archived\)/.test(await page.textContent('.qbtn[data-q="X2"]')), await page.textContent('.qbtn[data-q="X2"]'));

    // R-J: emoji anchors on
    await pick("Q1");
    ok("R-J: question title leads with the question anchor", (await page.textContent("#dscroll .dhead h3")).startsWith(Q_MARK + " "), await page.textContent("#dscroll .dhead h3"));
    ok("R-J: Recommendation heading leads with the recommendation anchor", (await recHead()).startsWith(R_MARK + " "), await recHead());

    // AC22: commitments as separate unchecked rows, above the collapsed details
    const rows = await page.$$eval("#dscroll [data-confirm]", els => els.map(e => ({checked: e.checked, before: !!(e.compareDocumentPosition(document.getElementById("more")) & Node.DOCUMENT_POSITION_FOLLOWING)})));
    ok("AC22: one unchecked row per commitment", rows.length === 2 && rows.every(r => !r.checked), JSON.stringify(rows));
    ok("AC22: rows sit above the collapsed details", rows.length === 2 && rows.every(r => r.before) && !(await page.$("#more [data-confirm]")));
    await page.click("main.detail h3"); await page.keyboard.press("a");
    ok("AC16: a arms Rec", /Rec/.test(await armed()), await armed());
    await page.click("[data-save]"); await page.waitForTimeout(700);
    const e1 = await events();
    ok("Accept saved on Q1", e1[e1.length - 1].id === "Q1" && e1[e1.length - 1].kind === "accept");
    await pick("Q1");
    ok("AC22: Accept leaves every commitment row unchecked", (await page.$$eval("#dscroll [data-confirm]", els => els.filter(e => e.checked).length)) === 0);
    let s = await state(), want = openAssumptions(s);
    ok("AC22: header counter equals the unconfirmed commitments on answered questions", want >= 2 && (await counter()) === open(want), (await counter()) + " vs " + want);
    ok("displayName labels the user's lines", /Dana accepted/.test(await page.textContent("#thread")), (await page.textContent("#thread")).slice(0, 120));
    const n0 = (await events()).length;
    await page.click('#dscroll [data-confirm="0"]'); await page.waitForTimeout(700);
    const e2 = await events(), c = e2[e2.length - 1];
    ok("Confirm posts a confirm event with the commitment index", e2.length === n0 + 1 && c.kind === "confirm" && c.id === "Q1" && c.alt === "0" && c.text === "", JSON.stringify(c));
    ok("confirmed row shows checked", await page.$eval('#dscroll [data-confirm="0"]', el => el.checked));
    s = await state();
    ok("counter drops after Confirm", (await counter()) === open(want - 1) && openAssumptions(s) === want - 1, await counter());
    await page.click('#dscroll [data-confirm="0"]'); await page.waitForTimeout(500);
    ok("a second Confirm click does nothing", (await events()).length === n0 + 1);
    await page.click('#dscroll [data-challenge="1"]'); await page.waitForTimeout(150);
    ok("Challenge fills the note and focuses it", (await page.inputValue("#note")) === "Challenge: Runs on every save " && (await focused()) === "note", JSON.stringify(await page.inputValue("#note")));
    await page.keyboard.type("on a slow disk?"); await page.keyboard.press("Control+Shift+Enter"); await page.waitForTimeout(700);
    const e3 = await events(), ask = e3[e3.length - 1];
    ok("Ctrl+Shift+Enter sends the challenge as an ask", ask.kind === "ask" && ask.id === "Q1" && ask.text === "Challenge: Runs on every save on a slow disk?", JSON.stringify(ask));

    // AC16: letter keys on Q3 (open, no decision)
    await pick("Q3"); await page.click("main.detail h3");
    await page.keyboard.press("d");
    ok("AC16: d arms Defer", /Defer/.test(await armed()), await armed());
    await page.keyboard.press("o");
    ok("AC16: o arms Own and focuses the note", /Own answer/.test(await armed()) && (await focused()) === "note" && (await page.inputValue("#note")) === "", await focused());
    await page.keyboard.press("Escape");
    await page.keyboard.press("i");
    ok("AC16: i focuses the note", (await focused()) === "note" && (await page.inputValue("#note")) === "");
    await page.keyboard.press("Escape");
    await page.keyboard.press("/");
    ok("AC16: / focuses the filter", (await focused()) === "filter");
    await page.click("main.detail h3");
    const n1 = (await events()).length;
    await page.keyboard.press("r"); await page.waitForTimeout(400);
    ok("r does nothing without a decision", (await events()).length === n1);
    await page.keyboard.press("?"); await page.waitForTimeout(150);
    const sheet = await page.evaluate(() => { const d = document.getElementById("keysDlg"); return d && d.open ? d.innerText : ""; });
    ok("AC16: ? opens the shortcut sheet listing the keys", /Reconfirm/.test(sheet) && /Filter/.test(sheet) && /Shift\+N/.test(sheet), sheet.replace(/\s+/g, " ").slice(0, 120));
    await page.keyboard.press("Escape"); await page.waitForTimeout(150);
    await page.click("main.detail h3"); await page.keyboard.press("a"); await page.keyboard.press("?"); await page.waitForTimeout(150);
    const armedBehind = /Rec/.test(await armed());
    await page.keyboard.press("Control+Enter"); await page.waitForTimeout(600);
    ok("Ctrl+Enter saves nothing behind the open ? sheet", armedBehind && (await events()).length === n1 && await page.evaluate(() => document.getElementById("keysDlg").open), "armed " + armedBehind);
    await page.keyboard.press("Escape"); await page.waitForTimeout(150);
    ok("AC16: Esc closes the sheet", await page.evaluate(() => !document.getElementById("keysDlg").open));
    // Hedged: accept with a required condition note; its commitments count like an accept's
    await pick("Q3"); await page.click("main.detail h3");
    await page.keyboard.press("h");
    ok("h arms Hedged and focuses the note", /Hedged/.test(await armed()) && (await focused()) === "note", await armed());
    ok("Hedged with no condition cannot be saved", await page.$eval("[data-save]", el => el.disabled) && /Hedged needs a condition/.test(await page.textContent("#decideRow")));
    await page.keyboard.type("only if the migration is reversible"); await page.keyboard.press("Control+Enter"); await page.waitForTimeout(700);
    const eh = await events(), hd = eh[eh.length - 1];
    ok("Hedged posts a hedged event with the condition", hd.id === "Q3" && hd.kind === "hedged" && hd.text === "only if the migration is reversible", JSON.stringify(hd));
    await pick("Q3");
    ok("the hedged decision shows as Hedged with its condition", /Hedged/.test(await page.textContent("#cur")) && /only if the migration is reversible/.test(await page.textContent("#cur")), await page.textContent("#cur"));
    s = await state();
    ok("a hedged question's commitments count in To confirm", (await counter()) === (openAssumptions(s) ? open(openAssumptions(s)) : ""), (await counter()) + " vs " + openAssumptions(s));
    await page.click("main.detail h3"); await page.keyboard.press("r"); await page.waitForTimeout(600);
    await pick("Q1"); await page.click("main.detail h3");
    const nBeforeReopen = (await events()).length;
    await page.keyboard.press("r"); await page.waitForTimeout(700);
    const e4 = await events();
    ok("AC16: r sends Reopen when a decision exists", e4.length === nBeforeReopen + 1 && e4[e4.length - 1].kind === "reopen" && e4[e4.length - 1].id === "Q1", e4[e4.length - 1].kind);

    // AC20: archived X1 is greyed, out of the open counts and the meter
    s = await state();
    const baseOpen = s.questions.questions.filter(q => q.group === "base" && !q.archived && !(s.responses.responses[q.id] || {}).decision).length;
    const cnt = await page.textContent('.sec[data-key="g:base"] .cnt');
    ok("AC20: archived question not in the group's open count", cnt === baseOpen + " open / 5", cnt + " want " + baseOpen);
    ok("AC20: archived question greyed in Groups", await page.$eval('.qbtn[data-q="X1"]', el => el.classList.contains("archived")));
    const live = s.questions.questions.filter(q => !q.archived).length;
    ok("AC20: meter leaves the archived question out", new RegExp(" of " + live + " answered$").test(await page.textContent("#meterText")), await page.textContent("#meterText"));
    await page.click('.seg [data-view="tree"]'); await page.waitForTimeout(200);
    ok("AC20: archived question greyed in Tree", await page.$eval('.rail-list .tree .qbtn[data-q="X1"]', el => el.classList.contains("archived")));
    await page.click('.rail-list .tree .qbtn[data-q="X1"]'); await page.waitForTimeout(200);
    ok("AC20: archived question clickable in Tree and names why", await sel() === "X1" && /Archived: The old path left the plan/.test(await page.textContent("#dscroll")), await sel());
    await page.click('.seg [data-view="groups"]'); await page.waitForTimeout(150);

    // SPEC 6: stale after an upstream re-answer, upstream-pending further down
    for (const id of ["P1", "P2", "P3"]) await post({id, kind: "accept", alt: null, text: ""});
    await post({id: "P1", kind: "alt", alt: "b", text: "Later after all"});
    await page.waitForTimeout(900);
    await pick("P2");
    ok("stale banner names the changed prerequisite", /Stale: P1/.test(await page.textContent("#dscroll")), (await page.textContent("#dscroll")).slice(0, 160));
    ok("stale keeps its decision visible", /Accepted/.test(await page.textContent("#cur")), await page.textContent("#cur"));
    await page.click("main.detail h3"); await page.keyboard.press("a");
    ok("a arms Reconfirm, the first row, on a stale question", /^Reconfirm/.test((await armed()).trim()), await armed());
    ok("stale chip in the rail", /Stale/.test(await page.textContent('.qbtn[data-q="P2"]')));
    ok("upstream-pending dimmed with its Waiting on chip", await page.$eval('.qbtn[data-q="P3"]', el => el.classList.contains("dim") && /Waiting on P2/.test(el.textContent)));
    await pick("P1"); await page.click("main.detail h3");
    await page.keyboard.press("n");
    ok("AC16: n goes to the next item needing you (stale P2)", await sel() === "P2", await sel());
    await page.keyboard.press("n");
    ok("AC16: n skips answered items to one with an unanswered reply (R1)", await sel() === "R1", await sel());
    await page.keyboard.press("Shift+N");
    ok("AC16: Shift+N goes back (P2)", await sel() === "P2", await sel());

    // R1 holds an accept followed by Claude's reply to an ask: it still needs you, so Show: Open lists it and the group counts it
    await page.selectOption("#filter", "open"); await page.waitForTimeout(200);
    const openIds = await page.$$eval(".rail-list .qbtn", els => els.map(e => e.dataset.q));
    ok("Show: Open lists an accepted question with an unanswered Claude reply", openIds.includes("R1"), openIds.join(","));
    ok("Show: Open leaves out a settled question", !openIds.includes("P1"), openIds.join(","));
    ok("Show: Open leaves out a question held for research, whose newest Claude line is the hold", !openIds.includes("H1"), openIds.join(","));
    ok("no Sent to Claude chip once a reply carries replyTo at or past the last event", !/Sent to Claude/.test(await page.textContent('.qbtn[data-q="R1"]')), await page.textContent('.qbtn[data-q="R1"]'));
    ok("the group counter counts the unanswered reply", /^1 open \//.test(await page.textContent('.sec[data-key="g:talk"] .cnt')), await page.textContent('.sec[data-key="g:talk"] .cnt'));
    ok("a reply after the accept puts the after-answer chip on the card", /Replied after your answer/.test(await page.textContent('.qbtn[data-q="R1"]')), await page.textContent('.qbtn[data-q="R1"]'));
    await pick("R1");
    ok("an accepted question has input:checked on the recommended row, labeled Your answer", await page.$eval("#choices .choice.rec", el => el.querySelector("input:checked") !== null && /Your answer/.test(el.textContent)), await page.textContent("#choices"));
    ok("only the accepted row is checked", (await page.$$("#choices input:checked")).length === 1);
    ok("Save starts disabled on an answered question", await page.$eval("[data-save]", el => el.disabled));
    await page.click("#choices .choice.rec input");
    ok("clicking the pre-selected Your answer row arms it and enables Save", /Rec/.test(await armed()) && await page.$eval("[data-save]", el => !el.disabled), await armed());
    ok("the detail says when you answered", /You answered Accepted at /.test(await page.textContent("#dscroll")), await page.textContent("#dscroll"));
    ok("the detail shows the after-answer chip", /Replied after your answer/.test(await page.textContent("#dscroll")), await page.textContent("#dscroll"));
    await page.selectOption("#filter", "all"); await page.waitForTimeout(150);
    await pick("P2");

    // SPEC 6 re-answer triage: Reconfirm re-sends the kept decision exactly; choice 2 onward picks again
    const last = async () => { const e = await events(); return e[e.length - 1]; };
    const stale = async id => (await state()).questions.questions.find(q => q.id === id).state === "stale";
    const reconfirm = async () => { await page.click("main.detail h3"); await page.keyboard.press("a"); const a = (await armed()).trim(); await page.keyboard.press("Control+Enter"); await page.waitForTimeout(800); return a; };
    const restale = async (p2, p1) => { await post(Object.assign({id: "P2", alt: null, text: ""}, p2)); await post(Object.assign({id: "P1", alt: null, text: ""}, p1)); await page.waitForTimeout(900); await pick("P2"); };
    const r0 = await reconfirm(), ev0 = await last();
    ok("Reconfirm of a kept accept records accept", /the recommendation/.test(r0) && ev0.id === "P2" && ev0.kind === "accept" && ev0.alt === null && !(await stale("P2")), r0 + " " + JSON.stringify(ev0));
    await restale({kind: "alt", alt: "b", text: "Only on weekends"}, {kind: "alt", alt: "a"});
    ok("stale banner names the Reconfirm key", /Reconfirm it \(key a\)/.test(await page.textContent("#dscroll")), (await page.textContent("#dscroll")).slice(0, 160));
    const r1 = await reconfirm(), ev1 = await last();
    ok("a on a stale kept alternative arms Reconfirm naming alternative (b)", /^Reconfirm/.test(r1) && /alternative \(b\): Later/.test(r1), r1);
    ok("Reconfirm of a kept alternative records the same alt and note", ev1.id === "P2" && ev1.kind === "alt" && ev1.alt === "b" && ev1.text === "Only on weekends" && !(await stale("P2")), JSON.stringify(ev1));
    await restale({kind: "own", text: "Run it by hand"}, {kind: "accept"});
    const r2 = await reconfirm(), ev2 = await last();
    ok("Reconfirm of a kept own answer records own with the kept text", /^Reconfirm/.test(r2) && /your own answer/.test(r2) && ev2.id === "P2" && ev2.kind === "own" && ev2.text === "Run it by hand" && !(await stale("P2")), r2 + " " + JSON.stringify(ev2));
    await restale({kind: "defer"}, {kind: "alt", alt: "b"});
    const radios = await page.$$eval("#choices .choice", els => els.map(e => e.querySelector("input").value + "=" + e.querySelector("b").textContent + (e.querySelector(".n") ? "#n" : "")));
    ok("stale with a decision: Reconfirm, Rec, Accept with note, then the alternatives; radio values count from 1; no number shown", radios.slice(0, 3).join() === "1=Reconfirm,2=Rec,3=Accept with note" && radios.every((r, i) => r.startsWith((i + 1) + "=") && !r.endsWith("#n")), radios.join(", "));
    await pick("D1");
    const dup = await page.$$eval("#choices .choice", els => els.map(e => e.querySelector("b").textContent + "=" + e.textContent + (e.classList.contains("rec") ? "#rec" : "")));
    ok("an alternative restating the recommendation is folded into Accept: Rec is first with class rec and no (a) choice carries the duplicate", dup[0].startsWith("Rec=") && dup[0].endsWith("#rec") && !dup.some(x => /^\(a\)/.test(x) || /\(recommended\)/.test(x)) && dup.some(x => /^\(b\)/.test(x)) && dup.some(x => /^\(c\).*only on request/.test(x)), dup.join(" | "));
    const nEv = (await events()).length;
    await page.click("#qhead"); await page.keyboard.press("o"); await page.fill("#note", "(a), because it is hidden"); await page.click("[data-save]"); await page.waitForTimeout(400);
    const hid = await page.evaluate(() => ({open: document.getElementById("dlg").open, title: document.getElementById("dlgTitle").textContent}));
    ok("a note naming the hidden duplicate (a) is not offered as a choice and saves as typed", !hid.open && (await events()).length === nEv + 1, JSON.stringify(hid));
    await pick("P2"); await page.click("main.detail h3"); await page.keyboard.press("2");
    const r3 = (await armed()).trim(); await page.keyboard.press("Control+Enter"); await page.waitForTimeout(800);
    const ev3 = await last();
    ok("2 then save on a stale question picks again: Rec", /^Rec/.test(r3) && ev3.id === "P2" && ev3.kind === "accept" && ev3.alt === null && !(await stale("P2")), r3 + " " + JSON.stringify(ev3));
    await pick("P2");
    // An armed choice keeps its identity when an upstream decision stales the question and a Reconfirm row renumbers the list
    await page.click("main.detail h3"); await page.keyboard.press("4");
    const a0 = (await armed()).trim();
    await post({id: "P1", kind: "accept", alt: null, text: ""}); await page.waitForTimeout(900);
    const a1 = (await armed()).trim(), wasStale = await stale("P2");
    await page.click("main.detail h3"); await page.keyboard.press("Control+Enter"); await page.waitForTimeout(800);
    const ev4 = await last();
    ok("an armed alternative survives a Reconfirm row shifting the key numbers: (b) stays armed once stale and saves alt b", /^\(b\)/.test(a0) && wasStale && /^\(b\)/.test(a1) && ev4.id === "P2" && ev4.kind === "alt" && ev4.alt === "b", a0 + " / " + a1 + " " + JSON.stringify(ev4));
    // Reconfirm with a note typed over the kept one records the typed note
    await restale({kind: "alt", alt: "b", text: "Only on weekends"}, {kind: "accept"});
    await page.fill("#note", "Weekdays too");
    await page.click("main.detail h3"); await page.keyboard.press("a");
    const r6 = (await armed()).trim(); await page.keyboard.press("Control+Enter"); await page.waitForTimeout(800);
    const ev6 = await last();
    ok("Reconfirm sends the note typed over the kept one", /^Reconfirm/.test(r6) && ev6.id === "P2" && ev6.kind === "alt" && ev6.alt === "b" && ev6.text === "Weekdays too", r6 + " " + JSON.stringify(ev6));
    await pick("P2");

    // SPEC 5.2: revising while an upstream decision is delivered and unhandled
    const r5 = await (await post({id: "P1", kind: "accept", alt: null, text: ""})).json();
    await page.request.get(base + "api/wait?after=" + (r5.seq - 1) + "&timeout=2", {headers: {"X-Interview-Token": await token()}});
    await page.waitForTimeout(900);
    ok("revising chip on the answered question, not its dependent", /Answer not handled yet/.test(await page.textContent('.qbtn[data-q="P1"]')) && !/Answer not handled yet/.test(await page.textContent('.qbtn[data-q="P2"]')));

    // shortcuts off: no single key acts
    await page.keyboard.press(","); await page.waitForTimeout(200);
    await page.selectOption('[data-set="shortcuts"]', "false"); await page.waitForTimeout(150);
    await page.keyboard.press("Escape"); await page.keyboard.press("Escape"); await page.waitForTimeout(150);
    await pick("Q3"); await page.click("main.detail h3");
    const n2 = (await events()).length;
    for (const k of ["a", "o", "d", "i", "/", "?", "1", "n", "Shift+N", "r"]) await page.keyboard.press(k);
    await page.waitForTimeout(400);
    const off = await page.evaluate(() => ({armed: !!document.querySelector(".choice.armed"), focus: document.activeElement.id || document.activeElement.tagName, sheet: document.getElementById("keysDlg").open}));
    ok("AC16: shortcuts off disables every single key", !off.armed && off.focus === "BODY" && !off.sheet && await sel() === "Q3" && (await events()).length === n2, JSON.stringify(off));

    // AC33: settings rows name their layer
    await page.click('.strip [data-panel="settings"]'); await page.waitForTimeout(200);
    await page.click('[data-reset="shortcuts"]'); await page.waitForTimeout(150);
    const src = await page.$$eval(".setrow", els => Object.fromEntries(els.map(e => [e.dataset.key, e.querySelector(".src").textContent.replace(/\s*Reset$/, "")])));
    const val = async k => page.$eval('.setrow[data-key="' + k + '"]', e => { const c = e.querySelector("select, input"); return c ? c.value : e.querySelector(".val").textContent; });
    ok("AC33: repo beats default (undoSeconds 7 from repo)", src.undoSeconds === "From repo" && await val("undoSeconds") === "7", src.undoSeconds);
    ok("AC33: user beats repo (minText 18 from user)", src.minText === "From user" && await val("minText") === "18", src.minText);
    ok("AC33: session layer (theme light)", src.theme === "From session" && await val("theme") === "light", src.theme);
    ok("AC33: default layer (shortcuts)", src.shortcuts === "From default", src.shortcuts);
    ok("AC33: read-only rows for displayName, waitTimeout, staleDepth", src.displayName === "From user" && await val("displayName") === "Dana" && src.waitTimeout === "From default" && await val("waitTimeout") === "90" && src.staleDepth === "From default" && await val("staleDepth") === "direct", JSON.stringify(src));
    ok("AC33: read-only row for leaseTimeout (600, default)", src.leaseTimeout === "From default" && await val("leaseTimeout") === "600", JSON.stringify(src));
    ok("SPEC 4.15: read-only rows for port (0, default) and openBrowser (true, default)", src.port === "From default" && await val("port") === "0" && src.openBrowser === "From default" && await val("openBrowser") === "true", JSON.stringify(src));
    await page.fill('[data-set="undoSeconds"]', "9"); await page.dispatchEvent('[data-set="undoSeconds"]', "change"); await page.waitForTimeout(150);
    ok("AC33: a browser override shows this browser with Reset", /^From this browser/.test(await page.textContent('.setrow[data-key="undoSeconds"] .src')) && !!(await page.$('[data-reset="undoSeconds"]')));
    await page.click('[data-reset="undoSeconds"]'); await page.waitForTimeout(150);
    ok("Reset returns to the repo layer", /^From repo/.test(await page.textContent('.setrow[data-key="undoSeconds"] .src')));
    await page.click("#flyClose");

    // AC32: visuals by format; svg and html only inside a sandboxed iframe
    await pick("Q2");
    await page.keyboard.press("v"); await page.waitForTimeout(250);
    const frame = async id => { await page.click('[data-vtab="v:' + id + '"]'); await page.waitForTimeout(150); return page.evaluate(() => { const f = document.querySelector("#fbody iframe"), b = document.getElementById("fbody"); return {srcdoc: f ? f.srcdoc : null, sandbox: f ? f.getAttribute("sandbox") : null, svgs: b.querySelectorAll("svg").length, mark: !!document.getElementById("htmlmark"), text: b.innerText}; }); };
    const vk = await frame("vk"), vf = await frame("vf"), vh = await frame("vh");
    ok("AC32: kind svg and format svg give the same iframe srcdoc", !!vk.srcdoc && vk.srcdoc === vf.srcdoc && /svgmark/.test(vk.srcdoc));
    ok("AC32: svg only inside a sandboxed iframe", vk.sandbox === "" && vf.sandbox === "" && vk.svgs === 0 && vf.svgs === 0 && !/<svg/.test(vk.text + vf.text));
    ok("AC32: html only inside a sandboxed iframe", vh.sandbox === "allow-scripts" && /htmlmark/.test(vh.srcdoc) && !vh.mark && !/htmlmark/.test(vh.text));
    const hf = await (await page.$("#fbody iframe")).contentFrame();
    await hf.waitForSelector("#scriptmark", {state: "attached", timeout: 3000}).catch(() => {});
    const hs = await hf.evaluate(() => {
      const probe = f => { try { f(); return "reached"; } catch (e) { return "blocked"; } };
      return {built: !!document.getElementById("scriptmark"), parentDom: probe(() => parent.document.title), storage: probe(() => localStorage.length), cookie: probe(() => document.cookie)};
    });
    ok("an html visual's script runs, in an opaque origin that cannot reach the page", hs.built && hs.parentDom === "blocked" && hs.storage === "blocked" && hs.cookie === "blocked", JSON.stringify(hs));
    // Open in new tab: a one-time link that never carries the token, served as an opaque origin
    const newTab = async sel => { const [p] = await Promise.all([page.context().waitForEvent("page", {timeout: 5000}), page.click(sel)]); await p.waitForURL(/\/api\/visual-open\?/, {timeout: 5000}).catch(() => {}); return p; };
    const pop = await newTab('#fbody [data-vopen="vh"]'), pu = pop.url(), tok = await token();
    await pop.waitForSelector("#scriptmark", {state: "attached", timeout: 3000}).catch(() => {});
    const pv = await pop.evaluate(() => { const probe = f => { try { f(); return "reached"; } catch (e) { return "blocked"; } }; return {built: !!document.getElementById("scriptmark"), origin: self.origin, storage: probe(() => localStorage.length), opener: window.opener}; }).catch(e => ({err: e.message}));
    ok("Open in new tab opens the html visual in a new page whose scripts run in an opaque origin", /\/api\/visual-open\?id=vh&t=/.test(pu) && !pu.includes(tok) && pv.built && pv.origin === "null" && pv.storage === "blocked" && pv.opener === null, pu.replace(/t=.*/, "t=...") + " " + JSON.stringify(pv));
    ok("a used new-tab link is refused", (await page.request.get(pu)).status() === 403);
    await pop.close();
    await page.click("#fbody [data-full]"); await page.waitForTimeout(200);
    const fpop = await newTab("#fsTab");
    ok("full screen opens its visual in a new tab too", /\/api\/visual-open\?id=vh&t=/.test(fpop.url()), fpop.url().replace(/t=.*/, "t=..."));
    await fpop.close(); await page.bringToFront(); await page.click("#fsClose");
    await page.click('[data-vtab="v:vm"]'); await page.waitForTimeout(150);
    const mm = await page.evaluate(() => ({code: (document.querySelector("#fbody pre code") || {}).textContent, text: document.getElementById("fbody").innerText, frame: !!document.querySelector("#fbody iframe")}));
    ok("AC32: mermaid shows its source and the not-available line", mm.code === "graph TD\n  A-->B" && /Mermaid rendering is not available in this version/.test(mm.text) && !mm.frame, JSON.stringify(mm).slice(0, 160));
    await page.click('[data-vtab="v:vc"]'); await page.waitForTimeout(150);
    ok("chart renders a table of series", /Saves/.test(await page.textContent("#fbody table")) && /Tue/.test(await page.textContent("#fbody table")));
    // SPEC 3.4: a file visual is fetched by visual id and rendered through the inline format paths, captioned with its path
    const fileVis = async (id, done) => { await page.click('[data-vtab="v:' + id + '"]'); await page.waitForFunction(done, null, {timeout: 5000}).catch(() => {}); return page.evaluate(() => { const b = document.getElementById("fbody"), f = b.querySelector("iframe"), i = b.querySelector("img"); return {text: b.innerText, cap: (b.querySelector(".vfile code") || {}).textContent, srcdoc: f ? f.srcdoc : null, sandbox: f ? f.getAttribute("sandbox") : null, img: i ? i.getAttribute("src") : null}; }); };
    let vxFetches = 0;
    page.on("request", r => { if (/\/api\/visual-file\?id=vx$/.test(r.url())) vxFetches++; });
    const fi = await fileVis("vi", () => !!document.querySelector("#fbody img"));
    ok("file image renders an img from a data:image/png URL, captioned with its path", /^data:image\/png;base64,/.test(fi.img || "") && fi.cap === "images/flow.png", JSON.stringify(fi).slice(0, 160));
    const fv = await fileVis("vs", () => !!document.querySelector("#fbody iframe"));
    ok("file svg renders only inside a sandboxed iframe, captioned with its path", fv.sandbox === "" && /filemark/.test(fv.srcdoc || "") && !/filemark/.test(fv.text) && fv.cap === "diagrams/flow.svg", JSON.stringify(fv).slice(0, 160));
    const fx = await fileVis("vx", () => /not found/.test(document.getElementById("fbody").innerText));
    ok("a missing file shows its path and the error", fx.cap === "missing.svg" && /not found/.test(fx.text) && !fx.srcdoc, JSON.stringify(fx).slice(0, 160));
    await page.click('[data-vtab="v:vi"]'); await page.waitForTimeout(5200);
    await fileVis("vx", () => /not found/.test(document.getElementById("fbody").innerText)); await page.waitForTimeout(600);
    ok("a failed file visual is fetched again, once, on a render after 5 s", vxFetches === 2, "fetches " + vxFetches);
    await fileVis("vs", () => !!document.querySelector("#fbody iframe"));
    await page.click("[data-full]"); await page.waitForTimeout(200);
    const fsv = await page.evaluate(() => { const f = document.querySelector("#fsStage iframe"); return {open: !document.getElementById("fs").hidden, srcdoc: f ? f.srcdoc : "", sandbox: f ? f.getAttribute("sandbox") : null, cap: (document.querySelector("#fsStage .vfile code") || {}).textContent}; });
    ok("full screen renders a file svg in a sandboxed iframe", fsv.open && fsv.sandbox === "" && /filemark/.test(fsv.srcdoc) && fsv.cap === "diagrams/flow.svg", JSON.stringify(fsv).slice(0, 160));
    await page.click("#fsClose");
    const fetches = await page.evaluate(() => performance.getEntriesByType("resource").filter(e => /\/api\/visual-file\?id=vs$/.test(e.name)).length);
    ok("a file visual is fetched once across tab switches and full screen", fetches === 1, "fetches " + fetches);
    await page.click('[data-vtab="v:vp"]'); await page.waitForTimeout(150);
    const vpSrc = (await state()).questions.questions.find(q => q.id === "Q2").visuals.find(v => v.id === "vp").content;
    const img = await page.evaluate(() => { const i = document.querySelector("#fbody img"); return i ? i.getAttribute("src") : null; });
    ok("inline image renders its content as the img src", img === vpSrc, String(img).slice(0, 60));

    // gallery: two or more images offer a thumbnail strip, arrow flip and side-by-side compare
    const gcur = () => page.evaluate(() => (document.querySelector("#fbody [data-gthumb][aria-current=true]") || {}).dataset?.gthumb || null);
    const gimgs = sel => page.evaluate(s => document.querySelectorAll(s + " img").length, sel);
    await page.click('[data-vtab="gallery:*"]'); await page.waitForFunction(() => document.querySelectorAll("#fbody .gstrip img").length === 2, null, {timeout: 5000}).catch(() => {});
    const gs = await page.evaluate(() => ({thumbs: [...document.querySelectorAll("#fbody [data-gthumb]")].map(b => b.dataset.gthumb), shown: document.querySelectorAll("#fbody .gpair img").length}));
    ok("gallery: one thumbnail per image, in order, and one image shown", gs.thumbs.join() === "vi,vp" && gs.shown === 1, JSON.stringify(gs));
    await page.click('[data-gthumb="vi"]'); await page.keyboard.press("ArrowRight"); await page.waitForTimeout(150);
    ok("gallery: a right arrow key advances the selection and keeps focus on it", await gcur() === "vp" && await page.evaluate(() => document.activeElement.dataset.gthumb) === "vp");
    await page.keyboard.press("ArrowRight"); await page.waitForTimeout(100);
    ok("gallery: the selection wraps", await gcur() === "vi");
    await page.keyboard.press("ArrowLeft"); await page.waitForTimeout(100);
    ok("gallery: a left arrow key steps back", await gcur() === "vp");
    await page.evaluate(() => document.activeElement.blur()); await page.keyboard.press("ArrowLeft"); await page.waitForTimeout(100);
    ok("gallery: arrows do nothing while focus is outside the visuals panel", await gcur() === "vp");
    await page.click('[data-gthumb="vi"]'); await page.click("[data-gcompare]"); await page.waitForTimeout(200);
    ok("gallery: compare shows two images side by side", await gimgs("#fbody .gpair") === 2 && await page.evaluate(() => document.querySelectorAll("#fbody .gpair .gfig").length) === 2);
    await page.click("[data-full]"); await page.waitForTimeout(200);
    const gf = await page.evaluate(() => ({imgs: document.querySelectorAll("#fsStage .gpair img").length, cmp: !document.getElementById("fsCmp").hidden, first: (document.querySelector("#fsStage figcaption") || {}).textContent}));
    ok("gallery: full screen compares two images and offers the compare toggle", gf.imgs === 2 && gf.cmp && gf.first === "Image", JSON.stringify(gf));
    await page.keyboard.press("ArrowRight"); await page.waitForTimeout(150);
    ok("gallery: an arrow key flips inside full screen", await page.evaluate(() => (document.querySelector("#fsStage figcaption") || {}).textContent) === "Inline image");
    await page.click("#fsCmp"); await page.waitForTimeout(150);
    ok("gallery: the full-screen toggle returns to one image", await gimgs("#fsStage .gpair") === 1);
    await page.click("#fsClose");
    await page.click("[data-gcompare]"); await page.click('[data-vtab="v:vk"]'); await page.waitForTimeout(150);
    ok("a plain visual hides the full-screen compare toggle", await page.evaluate(() => { document.querySelector("[data-full]").click(); const h = document.getElementById("fsCmp").hidden; document.getElementById("fsClose").click(); return h; }));

    // grouped visual tabs: group headers, order, primary default, archived hidden, distinct labels
    await pick("Q3"); await page.waitForTimeout(150);
    const gt = await page.evaluate(() => ({
      heads: [...document.querySelectorAll("#fbody .tgh")].map(e => e.textContent),
      tabs: [...document.querySelectorAll("#fbody [data-vtab]")].map(e => ({id: e.dataset.vtab, text: e.textContent, tip: e.title, sel: e.getAttribute("aria-selected") === "true"})),
      body: document.getElementById("fbody").innerText}));
    ok("grouped tabs: one header per group, in order", JSON.stringify(gt.heads) === '["Checkout","Timeline"]', JSON.stringify(gt.heads));
    ok("grouped tabs: sorted by order, ungrouped last, Map after them, archived hidden", gt.tabs.map(t => t.id).join() === "v:ga,v:gb,v:gt,v:gl,map", gt.tabs.map(t => t.id).join());
    ok("grouped tabs: the primary opens by default", gt.tabs.filter(t => t.sel).map(t => t.id).join() === "v:gb" && /bodymark-b/.test(gt.body) && !/bodymark-a/.test(gt.body));
    const lab = gt.tabs.slice(0, 2);
    ok("grouped tabs: long similar titles get distinct labels without the shared prefix, full title in the tooltip", lab[0].text !== lab[1].text && lab.every(t => !/^Checkout flow/.test(t.text) && t.text.length <= 28) && lab[0].tip === "Checkout flow, option A: single page with inline payment form" && lab[1].tip === "Checkout flow, option B: two steps with a review page", JSON.stringify(lab));
    ok("grouped tabs: no raw id shows while a title exists", gt.tabs.every(t => !/^(ga|gb|gt|gl)$/.test(t.text)));
    await page.click('[data-vtab="v:gl"]'); await page.waitForTimeout(150);
    ok("Replay stays on a frame visual in a grouped set", !!(await page.$("#fbody [data-replay]")));
    await page.click('[data-vtab="v:ga"]'); await page.click("[data-full]"); await page.waitForTimeout(200);
    ok("full screen opens the selected grouped visual", await page.evaluate(() => !document.getElementById("fs").hidden && /bodymark-a/.test(document.getElementById("fsStage").innerText)));
    await page.click("#fsClose");
    await pick("Q2"); await page.waitForTimeout(150);
    ok("a question without a primary opens its first tab", await page.evaluate(() => document.querySelector("#fbody [data-vtab][aria-selected=true]").dataset.vtab) === "v:vk");
    await page.click("#flyClose");

    // SPEC 4.1: mobile stacks, no horizontal scroll at 800 px
    await page.setViewportSize({width: 800, height: 900}); await page.waitForTimeout(300);
    const mob = await page.evaluate(() => { const r = document.querySelector("nav.rail").getBoundingClientRect(), d = document.querySelector("main.detail").getBoundingClientRect(), a = document.getElementById("answer"); a.scrollIntoView(); const ar = a.getBoundingClientRect(); return {hscroll: document.scrollingElement.scrollWidth > innerWidth, stacked: r.bottom <= d.top + 1, answer: ar.height > 0 && ar.top < innerHeight && ar.bottom > 0}; });
    ok("mobile: panes stack, no horizontal scroll, answer pane reachable", !mob.hscroll && mob.stacked && mob.answer, JSON.stringify(mob));
    await page.setViewportSize({width: 1400, height: 860}); await page.waitForTimeout(300);
    ok("AC36: page never scrolls at 1400 by 860", await page.evaluate(() => document.scrollingElement.scrollHeight <= innerHeight + 1 && document.scrollingElement.scrollWidth <= innerWidth));

    // AC23 setup: open A1 and A2, then leave the Accept all dialog open for the external revise
    await pick("A1"); await pick("A2");
    await page.click("main.detail h3"); await page.keyboard.press("1");
    await page.click('[data-acceptall="batch"]'); await page.waitForTimeout(200);
    ok("Accept all lists both opened questions", await page.evaluate(() => document.getElementById("dlg").open && /A1/.test(document.getElementById("dlgBody").innerText) && /A2/.test(document.getElementById("dlgBody").innerText)));
    const n3 = (await events()).length;
    await page.keyboard.press("Control+Enter"); await page.waitForTimeout(600);
    ok("Ctrl+Enter saves nothing behind the open Accept all dialog", (await events()).length === n3 && await page.evaluate(() => document.getElementById("dlg").open), await armed());
  }
  if (PHASE === 2) {
    await page.waitForTimeout(900); // SSE brings the external revise of A2 and the emoji switch
    ok("R-J: no anchors when emojiMarkers is false", !(await page.textContent("#dscroll .dhead h3")).includes(Q_MARK) && (await recHead()) === "Recommendation (Rec)", await recHead());
    await page.click("#dlgOk"); await page.waitForTimeout(900);
    const ev = await events(), acc = ev.filter(e => e.kind === "accept" && (e.id === "A1" || e.id === "A2")).map(e => e.id);
    ok("AC23: Accept all skips the question whose contentRev changed", acc.join(",") === "A1", acc.join(","));
    ok("AC23: the toast names the skipped question", /Skipped A2/.test(await page.textContent("#toast")), await page.textContent("#toast"));
    // Accept all goes with the revision each question was opened at: A2 was opened in phase 1,
    // before the shell's revise, so a dialog opened only now still refuses it until A2 is opened again.
    await page.click('[data-acceptall="batch"]'); await page.waitForTimeout(200);
    ok("Accept all opened after the revise still lists A2", await page.evaluate(() => document.getElementById("dlg").open && /A2/.test(document.getElementById("dlgBody").innerText)));
    await page.click("#dlgOk"); await page.waitForTimeout(900);
    const acc2 = (await events()).filter(e => e.kind === "accept" && e.id === "A2").length;
    ok("Accept all refuses a question revised after the user opened it", acc2 === 0 && /Skipped A2/.test(await page.textContent("#toast")), acc2 + " " + await page.textContent("#toast"));
    await pick("A2");
    await page.click('[data-acceptall="batch"]'); await page.waitForTimeout(200);
    await page.click("#dlgOk"); await page.waitForTimeout(900);
    const acc3 = (await events()).filter(e => e.kind === "accept" && e.id === "A2").length;
    ok("once A2 is opened again, Accept all accepts it", acc3 === 1, String(acc3));
    { // the shell revised Q1's commitments after phase 1 ticked one: that tick belongs to the old list
      const s2 = await state(), q1 = s2.questions.questions.find(q => q.id === "Q1");
      await pick("Q1");
      const rows = await page.$$eval("#dscroll [data-confirm]", els => els.map(e => e.checked));
      ok("a revise of the commitments drops the old confirm tick", q1.commitsSinceSeq > 0 && rows.length === 2 && rows.every(c => !c), JSON.stringify(rows) + " since " + q1.commitsSinceSeq);
      ok("counter agrees after the commitments were replaced", (await counter()) === (openAssumptions(s2) ? open(openAssumptions(s2)) : ""), (await counter()) + " vs " + openAssumptions(s2));
    }
    // SPEC 5.6: wrap-up freeze
    await page.keyboard.press("w"); await page.waitForTimeout(300);
    const n0 = (await events()).length;
    await page.click("[data-wrapup]"); await page.waitForTimeout(300); if (await page.$("dialog#dlg[open]")) await page.click("#dlgOk"); await page.waitForTimeout(700);
    const ev2 = await events();
    ok("Wrap up posts one wrapup event", ev2.length === n0 + 1 && ev2[ev2.length - 1].kind === "wrapup");
    ok("toast reads Wrapping up", /Wrapping up/.test(await page.textContent("#dscroll")));
    await pick("Q3"); await page.click("main.detail h3"); await page.keyboard.press("1");
    ok("Save disabled during the wrap-up freeze", await page.$eval("[data-save]", el => el.disabled) && /Rec/.test(await armed()));
    await page.click("#note"); await page.keyboard.press("Control+Enter"); await page.waitForTimeout(500); await page.keyboard.press("Escape");
    ok("Ctrl+Enter records nothing during the freeze", (await events()).length === n0 + 1);
    // The shell's revise between phases dropped P2's alternative (b), which its kept decision names
    const s2 = await state(), p2 = s2.questions.questions.find(q => q.id === "P2");
    await pick("P2");
    const first = await page.$eval("#choices .choice b", e => e.textContent), dtext = await page.textContent("#dscroll");
    ok("no Reconfirm for a kept alternative a revise removed", p2.state === "stale" && s2.responses.responses.P2.alt === "b" && !p2.alternatives.some(a => a.key === "b") && first === "Rec" && /Pick an answer/.test(dtext), [p2.state, s2.responses.responses.P2.alt, first].join(" ") + " " + dtext.slice(0, 120));
    ok("a recommendation change on P1 marks P2 Upstream changed in the card and the rail", /Upstream changed: the recommendation of P1.*was revised/.test(dtext) && /Upstream changed/.test(await page.textContent('.qbtn[data-q="P2"]')) && JSON.stringify(p2.upstreamChanged) === '["P1"]', dtext.slice(0, 120) + " " + JSON.stringify(p2.upstreamChanged));
  }
  if (PHASE === 3) {
    await page.waitForTimeout(600); // SSE brings the handle of phase 2's events
    await pick("Q3"); await page.click("main.detail h3"); await page.keyboard.press("1");
    ok("Save enabled again once phase 2's wrap-up is handled", !(await page.$eval("[data-save]", el => el.disabled)));
    // A fresh wrapup freezes saves; the shell's background handler lifts the freeze well inside
    // the 10 s window, which the page must show before that window runs out on its own.
    const w = await (await post({kind: "wrapup", text: ""})).json();
    await page.waitForTimeout(600);
    ok("Save disabled by a fresh wrap-up", await page.$eval("[data-save]", el => el.disabled), "seq " + w.seq);
    const lifted = await page.waitForFunction(() => !document.querySelector("[data-save]").disabled, null, {timeout: 9000}).then(() => true).catch(() => false);
    const st = await state(), at = st.responses.events.find(e => e.seq === w.seq).at, age = (Date.now() - Date.parse(at)) / 1000;
    const handled = (st.questions.handled || []).includes(w.seq) || (st.questions.handledSeq || 0) >= w.seq;
    ok("Save re-enabled by the handle, inside the 10 s freeze", lifted && handled && age < 10, "age " + age.toFixed(1) + " s, handled " + handled);
  }
  if (PHASE === 4) { // its own server: D1's one event was delivered in 2020 and never handled, and no watcher has polled
    await page.setViewportSize({width: 1400, height: 860});
    await page.goto(base);
    await page.waitForFunction(() => /Not listening/.test(document.getElementById("pill").textContent), null, {timeout: 5000}).catch(() => {});
    const pill = await page.evaluate(() => { const p = document.getElementById("pill"); return {cls: p.className, text: p.textContent, code: (p.querySelector("code") || {}).textContent, line: document.getElementById("claudeLine").textContent}; });
    ok("SPEC 2.4 rung 5: a delivery unhandled for 10 minutes with no watcher waiting says to type next", pill.text === "Not listening: type next" && pill.code === "next" && pill.cls === "pill idle" && /D1/.test(pill.line), JSON.stringify(pill));
    // The ping-silence fallback: with nothing changing, this server sends only its 15 s ping, so a
    // page told to call a stream dead after 1 s drops it, polls, and opens a new one.
    await page.addInitScript(() => {
      const Real = window.EventSource;
      window.__streams = 0;
      window.EventSource = function (url, init) { window.__streams++; return new Real(url, init); };
      window.EventSource.prototype = Real.prototype;
    });
    await page.goto(base + "?silentMs=1000");
    const reopened = await page.waitForFunction(() => window.__streams >= 2, null, {timeout: 14000}).then(() => true).catch(() => false);
    const streams = await page.evaluate(() => window.__streams);
    ok("a stream silent past the ping window is dropped for polling and reopened", reopened, "streams " + streams);
    ok("the page stays online through the fallback", await page.evaluate(() => !/Connection lost|Reconnecting/.test(document.getElementById("pill").textContent)), await page.textContent("#pill"));
  }
  if (PHASE === 5) { // the same server, after the shell added D2 (interview, round 3) and then E1 (design, round 1)
    await page.goto(base);
    await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(300);
    const lbl = await page.textContent("#roundLbl");
    ok("the header round comes from the newest question's stage only", lbl === "Round 1 · Design", lbl);
    const rounds = await page.$$eval(".qbtn", els => els.length);
    ok("both stages' questions are listed", rounds >= 3, String(rounds));
  }
  const real = errors.filter(e => !/status of 409 \(Conflict\)/.test(e) && !/status of 404 \(Not Found\) at \S*\/api\/visual-file\?id=vx$/.test(e));
  ok("AC37: zero console errors in phase " + PHASE + " (besides the network lines for an intended 409 and the missing file visual's 404)", real.length === 0, errors.join(" | "));
  } catch (e) { R.push("ERROR " + e.message.split("\n").slice(0, 3).join(" | ")); }
  return R.join("\n");
}
