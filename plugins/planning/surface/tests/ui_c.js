async page => {
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  const errors = [];
  page.on("console", m => { if (m.type() === "error") errors.push(m.text()); });
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
  const openAssumptions = s => {
    let n = 0;
    for (const q of s.questions.questions) {
      const r = s.responses.responses[q.id], dec = (r && r.decision) || (q.terminal && q.terminal.decision);
      if (!dec || q.archived || !(q.commits || []).length) continue;
      const cf = new Set(s.responses.events.filter(e => e.kind === "confirm" && e.id === q.id && !e.withdrawn).map(e => String(e.alt)));
      n += q.commits.filter((c, i) => !cf.has(String(i))).length;
    }
    return n;
  };
  const open = n => n + (n === 1 ? " assumption open" : " assumptions open");
  const counter = async () => page.evaluate(() => { const el = document.getElementById("assumeCount"); return el && !el.hidden ? el.textContent : ""; });
  try {
  if (PHASE === 1) {
    await page.setViewportSize({width: 1400, height: 860});
    await page.goto(base);
    await page.waitForSelector(".qbtn", {state: "attached"});
    await page.evaluate(() => localStorage.clear());
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"});

    // AC26: no watcher has ever polled, so the rung 5 message shows 30 s after load
    const rung5 = await page.waitForFunction(() => /Claude is not listening: type next in the terminal/.test(document.getElementById("pill").textContent), null, {timeout: 40000}).then(() => true).catch(() => false);
    ok("AC26: rung 5 message with no watcher", rung5, await page.textContent("#pill"));

    // AC17: number order within a group, whatever the insertion order
    const order = await page.$$eval('.sec[data-key="g:base"] .qbtn', els => els.map(e => e.dataset.q));
    ok("AC17: Q1 renders before Q3 though Q3 was inserted first", order.indexOf("Q1") >= 0 && order.indexOf("Q1") < order.indexOf("Q3"), order.join(","));

    // R-J: emoji anchors on
    await pick("Q1");
    ok("R-J: question title leads with the question anchor", (await page.textContent("#dscroll .dhead h3")).startsWith(Q_MARK + " "), await page.textContent("#dscroll .dhead h3"));
    ok("R-J: Recommendation heading leads with the recommendation anchor", (await recHead()).startsWith(R_MARK + " "), await recHead());

    // AC22: commitments as separate unchecked rows, above the collapsed details
    const rows = await page.$$eval("#dscroll [data-confirm]", els => els.map(e => ({checked: e.checked, before: !!(e.compareDocumentPosition(document.getElementById("more")) & Node.DOCUMENT_POSITION_FOLLOWING)})));
    ok("AC22: one unchecked row per commitment", rows.length === 2 && rows.every(r => !r.checked), JSON.stringify(rows));
    ok("AC22: rows sit above the collapsed details", rows.length === 2 && rows.every(r => r.before) && !(await page.$("#more [data-confirm]")));
    await page.click("main.detail h3"); await page.keyboard.press("a");
    ok("AC16: a arms Accept", /Accept/.test(await armed()), await armed());
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
    const armedBehind = /Accept/.test(await armed());
    await page.keyboard.press("Control+Enter"); await page.waitForTimeout(600);
    ok("Ctrl+Enter saves nothing behind the open ? sheet", armedBehind && (await events()).length === n1 && await page.evaluate(() => document.getElementById("keysDlg").open), "armed " + armedBehind);
    await page.keyboard.press("Escape"); await page.waitForTimeout(150);
    ok("AC16: Esc closes the sheet", await page.evaluate(() => !document.getElementById("keysDlg").open));
    await pick("Q1"); await page.click("main.detail h3");
    await page.keyboard.press("r"); await page.waitForTimeout(700);
    const e4 = await events();
    ok("AC16: r sends Reopen when a decision exists", e4.length === n1 + 1 && e4[e4.length - 1].kind === "reopen" && e4[e4.length - 1].id === "Q1", e4[e4.length - 1].kind);

    // AC20: archived X1 is greyed, out of the open counts and the meter
    s = await state();
    const baseOpen = s.questions.questions.filter(q => q.group === "base" && !q.archived && !(s.responses.responses[q.id] || {}).decision).length;
    const cnt = await page.textContent('.sec[data-key="g:base"] .cnt');
    ok("AC20: archived question not in the group's open count", cnt === baseOpen + " open / 4", cnt + " want " + baseOpen);
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
    ok("a arms Reconfirm, choice 1, on a stale question", /^1\s*Reconfirm/.test((await armed()).trim()), await armed());
    ok("stale chip in the rail", /Stale/.test(await page.textContent('.qbtn[data-q="P2"]')));
    ok("upstream-pending dimmed with its chip", await page.$eval('.qbtn[data-q="P3"]', el => el.classList.contains("dim") && /upstream pending/.test(el.textContent)));
    await pick("P1"); await page.click("main.detail h3");
    await page.keyboard.press("n");
    ok("AC16: n goes to the next item needing you (stale P2)", await sel() === "P2", await sel());
    await page.keyboard.press("n");
    ok("AC16: n skips answered items to one with an unanswered reply (R1)", await sel() === "R1", await sel());
    await page.keyboard.press("Shift+N");
    ok("AC16: Shift+N goes back (P2)", await sel() === "P2", await sel());

    // SPEC 6 re-answer triage: Reconfirm re-sends the kept decision exactly; choice 2 onward picks again
    const last = async () => { const e = await events(); return e[e.length - 1]; };
    const stale = async id => (await state()).questions.questions.find(q => q.id === id).state === "stale";
    const reconfirm = async () => { await page.click("main.detail h3"); await page.keyboard.press("a"); const a = (await armed()).trim(); await page.keyboard.press("Control+Enter"); await page.waitForTimeout(800); return a; };
    const restale = async (p2, p1) => { await post(Object.assign({id: "P2", alt: null, text: ""}, p2)); await post(Object.assign({id: "P1", alt: null, text: ""}, p1)); await page.waitForTimeout(900); await pick("P2"); };
    const r0 = await reconfirm(), ev0 = await last();
    ok("Reconfirm of a kept accept records accept", /the recommendation/.test(r0) && ev0.id === "P2" && ev0.kind === "accept" && ev0.alt === null && !(await stale("P2")), r0 + " " + JSON.stringify(ev0));
    await restale({kind: "alt", alt: "b", text: "Only on weekends"}, {kind: "alt", alt: "a"});
    ok("stale banner names Reconfirm as choice 1", /Reconfirm it \(a, choice 1\)/.test(await page.textContent("#dscroll")), (await page.textContent("#dscroll")).slice(0, 160));
    const r1 = await reconfirm(), ev1 = await last();
    ok("a on a stale kept alternative arms 1 Reconfirm naming alternative (b)", /^1\s*Reconfirm/.test(r1) && /alternative \(b\): Later/.test(r1), r1);
    ok("Reconfirm of a kept alternative records the same alt and note", ev1.id === "P2" && ev1.kind === "alt" && ev1.alt === "b" && ev1.text === "Only on weekends" && !(await stale("P2")), JSON.stringify(ev1));
    await restale({kind: "own", text: "Run it by hand"}, {kind: "accept"});
    const r2 = await reconfirm(), ev2 = await last();
    ok("Reconfirm of a kept own answer records own with the kept text", /^1\s*Reconfirm/.test(r2) && /your own answer/.test(r2) && ev2.id === "P2" && ev2.kind === "own" && ev2.text === "Run it by hand" && !(await stale("P2")), r2 + " " + JSON.stringify(ev2));
    await restale({kind: "defer"}, {kind: "alt", alt: "b"});
    const radios = await page.$$eval("#choices .choice", els => els.map(e => e.querySelector("input").value + "=" + e.querySelector(".n").textContent + " " + e.querySelector("b").textContent));
    ok("stale with a decision: 1 Reconfirm, 2 Accept, radio values equal the numbers shown", radios[0] === "1=1 Reconfirm" && radios[1] === "2=2 Accept" && radios.every((r, i) => r.startsWith((i + 1) + "=" + (i + 1) + " ")), radios.join(", "));
    await page.click("main.detail h3"); await page.keyboard.press("2");
    const r3 = (await armed()).trim(); await page.keyboard.press("Control+Enter"); await page.waitForTimeout(800);
    const ev3 = await last();
    ok("2 then save on a stale question picks again: accept", /^2\s*Accept/.test(r3) && ev3.id === "P2" && ev3.kind === "accept" && ev3.alt === null && !(await stale("P2")), r3 + " " + JSON.stringify(ev3));
    await pick("P2");

    // SPEC 5.2: revising while an upstream decision is delivered and unhandled
    const r5 = await (await post({id: "P1", kind: "accept", alt: null, text: ""})).json();
    await page.request.get(base + "api/wait?after=" + (r5.seq - 1) + "&timeout=2", {headers: {"X-Interview-Token": await token()}});
    await page.waitForTimeout(900);
    ok("revising chip on the dependent", /Claude is revising/.test(await page.textContent('.qbtn[data-q="P2"]')));
    ok("revising banner in the detail", /Claude is revising/.test(await page.textContent("#dscroll")));

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
    ok("AC32: html only inside a sandboxed iframe", vh.sandbox === "" && /htmlmark/.test(vh.srcdoc) && !vh.mark && !/htmlmark/.test(vh.text));
    await page.click('[data-vtab="v:vm"]'); await page.waitForTimeout(150);
    const mm = await page.evaluate(() => ({code: (document.querySelector("#fbody pre code") || {}).textContent, text: document.getElementById("fbody").innerText, frame: !!document.querySelector("#fbody iframe")}));
    ok("AC32: mermaid shows its source and the not-available line", mm.code === "graph TD\n  A-->B" && /Mermaid rendering is not available in this version/.test(mm.text) && !mm.frame, JSON.stringify(mm).slice(0, 160));
    await page.click('[data-vtab="v:vc"]'); await page.waitForTimeout(150);
    ok("chart renders a table of series", /Saves/.test(await page.textContent("#fbody table")) && /Tue/.test(await page.textContent("#fbody table")));
    await page.click('[data-vtab="v:vi"]'); await page.waitForTimeout(150);
    ok("image file shows its path", /images\/flow\.png/.test(await page.textContent("#fbody")));
    await page.click('[data-vtab="v:vp"]'); await page.waitForTimeout(150);
    const vpSrc = (await state()).questions.questions.find(q => q.id === "Q2").visuals.find(v => v.id === "vp").content;
    const img = await page.evaluate(() => { const i = document.querySelector("#fbody img"); return i ? i.getAttribute("src") : null; });
    ok("inline image renders its content as the img src", img === vpSrc, String(img).slice(0, 60));
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
    ok("R-J: no anchors when emojiMarkers is false", !(await page.textContent("#dscroll .dhead h3")).includes(Q_MARK) && (await recHead()) === "1 Recommendation", await recHead());
    await page.click("#dlgOk"); await page.waitForTimeout(900);
    const ev = await events(), acc = ev.filter(e => e.kind === "accept" && (e.id === "A1" || e.id === "A2")).map(e => e.id);
    ok("AC23: Accept all skips the question whose contentRev changed", acc.join(",") === "A1", acc.join(","));
    ok("AC23: the toast names the skipped question", /Skipped A2/.test(await page.textContent("#toast")), await page.textContent("#toast"));
    // SPEC 5.6: wrap-up freeze
    await page.keyboard.press("w"); await page.waitForTimeout(300);
    const n0 = (await events()).length;
    await page.click("[data-wrapup]"); await page.waitForTimeout(700);
    const ev2 = await events();
    ok("Wrap up posts one wrapup event", ev2.length === n0 + 1 && ev2[ev2.length - 1].kind === "wrapup");
    ok("toast reads Wrapping up", /Wrapping up/.test(await page.textContent("#dscroll")));
    await pick("Q3"); await page.click("main.detail h3"); await page.keyboard.press("1");
    ok("Save disabled during the wrap-up freeze", await page.$eval("[data-save]", el => el.disabled) && /Accept/.test(await armed()));
    await page.click("#note"); await page.keyboard.press("Control+Enter"); await page.waitForTimeout(500); await page.keyboard.press("Escape");
    ok("Ctrl+Enter records nothing during the freeze", (await events()).length === n0 + 1);
  }
  if (PHASE === 3) {
    await page.waitForTimeout(900); // SSE brings the handle
    const ev = await events(), w = ev.filter(e => e.kind === "wrapup").pop();
    const age = (Date.now() - Date.parse(w.at)) / 1000;
    ok("Save re-enabled after handle, inside the 10 s freeze", !(await page.$eval("[data-save]", el => el.disabled)) && age < 10, "age " + age.toFixed(1) + " s");
  }
  if (PHASE === 4) { // its own server: D1's one event was delivered in 2020 and never handled, and no watcher has polled
    await page.setViewportSize({width: 1400, height: 860});
    await page.goto(base);
    await page.waitForFunction(() => /Waiting on Claude/.test(document.getElementById("pill").textContent), null, {timeout: 5000}).catch(() => {});
    const pill = await page.evaluate(() => { const p = document.getElementById("pill"); return {cls: p.className, text: p.textContent, code: (p.querySelector("code") || {}).textContent}; });
    ok("SPEC 2.4 rung 5: a delivery unhandled for 10 minutes with no watcher waiting says to type next", pill.text === "Waiting on Claude: D1. Type next in the terminal" && pill.code === "next" && pill.cls === "pill idle", JSON.stringify(pill));
  }
  const real = errors.filter(e => !/status of 409 \(Conflict\)/.test(e));
  ok("AC37: zero console errors in phase " + PHASE + " (besides the network line for an intended 409)", real.length === 0, errors.join(" | "));
  } catch (e) { R.push("ERROR " + e.message.split("\n").slice(0, 3).join(" | ")); }
  return R.join("\n");
}
