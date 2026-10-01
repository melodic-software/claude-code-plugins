async page => {
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  const errors = [];
  page.on("console", m => { if (m.type() === "error") errors.push(m.text()); });
  page.on("pageerror", e => errors.push(String(e)));
  const base = "http://127.0.0.1:__PORT__/";
  const events = async () => (await (await page.request.get(base + "api/state")).json()).responses.events;
  const sel = async () => page.evaluate(() => (document.querySelector('.qbtn[aria-current="true"]') || {}).dataset?.q || (document.querySelector('.sumbtn[aria-current="true"]') ? "summary" : null));
  try {
  await page.setViewportSize({width: 1400, height: 860});
  await page.goto(base);
  await page.waitForSelector(".qbtn", {state: "attached"});
  await page.evaluate(() => localStorage.clear());
  await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(400);

  ok("first question that needs you is selected on load: stale Q9 comes before open N1", await sel() === "Q9" && /Stale/.test(await page.textContent('.qbtn[data-q="Q9"]')), await sel());
  const lock = await page.textContent('.sec[data-key="g:g10"] .lock').catch(() => "");
  ok("dependent group shows locked", /opens after New group/.test(lock), lock);
  ok("independent group not locked", !(await page.$('.sec[data-key="g:g9"] .lock')));
  ok("only the group whose summary predates a question shows Stale", (await page.$$('.sec[data-key="g:ordering"] .sec-hint .chip.hot')).length === 1 && !(await page.$('.sec[data-key="g:content"] .sec-hint .chip.hot')));
  ok("needs connector on N2", /needs N1/.test(await page.textContent('.qbtn[data-q="N2"]')));
  await page.setViewportSize({width: 510, height: 860});
  if (!(await page.isVisible('.qbtn[data-q="Q7"]'))) await page.click('.sec[data-key="g:realtime"] .sec-h');
  const n4 = await page.evaluate(() => { const b = document.querySelector('.qbtn[data-q="Q7"]'), q = b.querySelector(".qid"), r = document.createRange(); r.selectNodeContents(q); return {idW: q.getBoundingClientRect().width, textW: r.getBoundingClientRect().width, idRight: q.getBoundingClientRect().right, tLeft: b.querySelector(".qtitle").getBoundingClientRect().left}; });
  ok("a rail card with two dependsOn keeps the id column as wide as the id text", n4.idW <= n4.textW + 2 && n4.tLeft >= n4.idRight, JSON.stringify(n4));
  for (const id of ["Q8", "Q9", "Q7", "Q11"]) if (!(await page.isVisible('.qbtn[data-q="' + id + '"]'))) await page.evaluate(i => document.querySelector('.qbtn[data-q="' + i + '"]').closest(".sec").querySelector(".sec-h").click(), id);
  const lay = await page.evaluate(() => ["Q8", "Q9", "Q7", "Q11"].map(id => {
    const b = document.querySelector('.qbtn[data-q="' + id + '"]'), t = b.querySelector(".qtitle").getBoundingClientRect(), qid = b.querySelector(".qid").getBoundingClientRect(), ns = [...b.querySelectorAll(".needs")];
    return {id, n: ns.length, col2: t.left >= qid.right && t.top < qid.bottom, xs: ns.map(n => Math.round(n.getBoundingClientRect().left)), below: ns.every(n => n.getBoundingClientRect().top >= t.bottom - 1), over: [b, ...b.querySelectorAll("*")].filter(e => e.scrollWidth > e.clientWidth && getComputedStyle(e).textOverflow !== "ellipsis").map(e => e.className || e.tagName)};
  }));
  ok("cards with 0, 1, 2 and 4 dependsOn put the title in column 2 on row 1", lay.map(l => l.n).join() === "0,1,2,4" && lay.every(l => l.col2), JSON.stringify(lay));
  ok("every needs line sits at one x, below the title", lay.every(l => new Set(l.xs).size <= 1 && l.below), JSON.stringify(lay.map(l => l.xs)));
  ok("no card element overflows its own width at 510px", lay.every(l => !l.over.length), JSON.stringify(lay.map(l => l.over)));
  await page.setViewportSize({width: 1400, height: 860});

  // history labels
  await page.click('.qbtn[data-q="W1"]').catch(async () => { await page.click('.sec[data-key="g:wrap"] .sec-h'); await page.click('.qbtn[data-q="W1"]'); });
  await page.waitForTimeout(200);
  const hist = await page.$$eval("#thread .hl", els => els.map(e => e.innerText.replace(/\s+/g, " ").trim()));
  ok("history lines read 'You asked Claude · <date>'", hist.some(t => /^You asked Claude · \w{3} \d{1,2}, \d{1,2}:\d{2}/.test(t)), hist.find(t => /asked Claude/.test(t)));
  ok("no run-together labels", !hist.some(t => /YouAsked|PMYou|AMYou/.test(t)));
  ok("terminal lines lowercase verb", !hist.some(t => /You (Accepted|Answered|Chose)/.test(t)));

  // dictation: plain Enter, digits while typing, Ctrl+Enter unarmed
  await page.click('.qbtn[data-q="N1"]'); await page.waitForTimeout(200);
  const refs = await page.evaluate(() => [...document.querySelectorAll("#qhead a, .blk a")].map(a => a.textContent + " " + a.getAttribute("href")));
  ok("bare #N and owner/repo#N in a title and in facts render as issue links", ["#123 https://github.com/o/r/issues/123", "x/y#4 https://github.com/x/y/issues/4"].every(r => refs.filter(x => x === r).length === 2) && !refs.some(r => /#9\b/.test(r)), refs.join(" | "));
  const n0 = (await events()).length;
  await page.click("#note"); await page.keyboard.type("hello"); await page.keyboard.press("Enter"); await page.keyboard.type("world 1");
  await page.waitForTimeout(300);
  ok("plain Enter in note does not submit", (await events()).length === n0);
  ok("Enter adds a line, digits type", (await page.inputValue("#note")) === "hello\nworld 1");
  ok("digit while typing does not arm", !(await page.$(".choice.armed")));
  const h1 = await page.evaluate(() => document.getElementById("note").offsetHeight);
  await page.keyboard.press("Enter"); await page.keyboard.press("Enter"); await page.keyboard.type("more"); await page.keyboard.press("Enter"); await page.keyboard.type("lines");
  const h2 = await page.evaluate(() => document.getElementById("note").offsetHeight);
  ok("textarea auto-grows", h2 > h1, h1 + " -> " + h2);
  await page.keyboard.press("Control+Enter"); await page.waitForTimeout(300);
  ok("Ctrl+Enter with nothing armed records nothing", (await events()).length === n0, await page.textContent("#toast"));
  await page.keyboard.press("Escape");
  ok("Esc blurs the note", await page.evaluate(() => document.activeElement.id !== "note"));
  await page.keyboard.press("1");
  ok("digit 1 arms Rec outside the note", /Rec/.test(await page.textContent(".choice.armed").catch(() => "")));
  // save from inside the note: no auto-advance
  await page.click("#note"); await page.keyboard.press("Control+Enter"); await page.waitForTimeout(600);
  const ev1 = await events();
  ok("Ctrl+Enter saves the armed choice", ev1.length === n0 + 1 && ev1[ev1.length - 1].kind === "accept" && ev1[ev1.length - 1].id === "N1", ev1[ev1.length - 1].kind);
  ok("no auto-advance while the note has focus", await sel() === "N1", await sel());
  ok("undo offered", !!(await page.$("[data-undo]")));
  await page.click("[data-undo]"); await page.waitForTimeout(600);
  const ev2 = await events();
  ok("undo within the window withdraws the decision", ev2[ev2.length - 1].kind === "undo" && ev2.find(e => e.seq === ev1[ev1.length - 1].seq).withdrawn === true);
  ok("N1 is open again after undo", /Open/.test(await page.textContent('.qbtn[data-q="N1"] .chip')));
  ok("note restored after undo", /hello/.test(await page.inputValue("#note")));

  // Enter on a focused Save button never submits
  await page.keyboard.press("Escape"); await page.keyboard.press("3");
  const n2 = (await events()).length;
  await page.focus("[data-save]"); await page.keyboard.press("Enter"); await page.waitForTimeout(400);
  ok("plain Enter on a focused Save button does not submit", (await events()).length === n2);
  await page.click("[data-save]"); await page.waitForTimeout(700);
  const ev3 = await events();
  ok("click Save records the armed alternative", ev3[ev3.length - 1].kind === "alt" && ev3[ev3.length - 1].alt === "a");
  ok("auto-advance to next open after a click save", await sel() === "N2", await sel());
  ok("group lock clears once New group prerequisites... (still locked: N2 open)", !!(await page.$('.sec[data-key="g:g10"] .lock')));

  // flyout tabs
  await page.keyboard.press("v"); await page.waitForTimeout(250);
  ok("v opens the Visuals tab", await page.evaluate(() => document.getElementById("fly").classList.contains("open") && document.getElementById("flyTitle").textContent.startsWith("Visuals")));
  const flyBox = await page.evaluate(() => { const f = document.getElementById("fly").getBoundingClientRect(), m = document.querySelector("main.detail").getBoundingClientRect(); return {overlay: getComputedStyle(document.getElementById("fly")).position === "absolute", mainW: Math.round(m.width), flyL: Math.round(f.left), mainR: Math.round(m.right)}; });
  ok("flyout overlays the answer pane", flyBox.overlay && flyBox.flyL < flyBox.mainR, JSON.stringify(flyBox));
  await page.click('#tabs [data-panel="notes"]'); await page.waitForTimeout(200);
  ok("Notes tab", await page.textContent("#flyTitle") === "Notes to Claude" && !!(await page.$("#noteText")));
  await page.click('#tabs [data-panel="settings"]'); await page.waitForTimeout(200);
  ok("Settings tab", await page.textContent("#flyTitle") === "Settings" && !!(await page.$('[data-set="shortcuts"]')));
  await page.click("#pinBtn"); await page.waitForTimeout(200);
  const pinned = await page.evaluate(() => getComputedStyle(document.getElementById("fly")).position);
  ok("Pin splits the screen", pinned === "static", pinned);
  await page.click("#pinBtn");
  // shortcuts off setting
  await page.selectOption('[data-set="shortcuts"]', "false"); await page.waitForTimeout(150);
  await page.click("main.detail h3"); await page.keyboard.press("1"); await page.waitForTimeout(150);
  ok("shortcuts off: digit does not arm", !(await page.$(".choice.armed")));
  await page.selectOption('[data-set="shortcuts"]', "true"); await page.waitForTimeout(150);

  // notes
  await page.click('.strip [data-panel="notes"]'); await page.waitForTimeout(200);
  if (!(await page.$("#noteText"))) { await page.click('.strip [data-panel="notes"]'); await page.waitForTimeout(200); }
  const n3 = (await events()).length;
  await page.click("#noteText"); await page.keyboard.type("Side note for Claude"); await page.keyboard.press("Enter");
  ok("plain Enter in a note does not send", (await events()).length === n3);
  await page.keyboard.press("Control+Enter"); await page.waitForTimeout(600);
  const ev4 = await events();
  ok("note sent as event kind note", ev4[ev4.length - 1].kind === "note" && ev4[ev4.length - 1].id === null, ev4[ev4.length - 1].text);
  ok("note shows in the thread", /Side note for Claude/.test(await page.textContent(".nthread")));
  await page.keyboard.press("Escape"); await page.keyboard.press("Escape"); await page.waitForTimeout(200);
  ok("Esc then Esc closes the flyout", await page.evaluate(() => !document.getElementById("fly").classList.contains("open")));

  // tree view
  await page.click('.seg [data-view="tree"]'); await page.waitForTimeout(200);
  ok("Tree view renders with the current path", !!(await page.$(".rail-list .tree .qbtn.onpath")) && !!(await page.$('.rail-list .tree .tree .qbtn[data-q="N2"]')));
  await page.click('.seg [data-view="groups"]');

  // full-screen visual
  await page.click('.qbtn[data-q="Q10"]').catch(async () => { await page.click('.sec[data-key="g:ordering"] .sec-h'); await page.click('.qbtn[data-q="Q10"]'); });
  await page.waitForTimeout(200);
  await page.keyboard.press("v"); await page.waitForTimeout(250);
  await page.click("[data-full]"); await page.waitForTimeout(300);
  ok("full-screen visual opens with the frame", await page.evaluate(() => !document.getElementById("fs").hidden && !!document.querySelector("#fsStage iframe")));
  await page.click('[data-z="in"]'); await page.waitForTimeout(100);
  ok("zoom in", (await page.textContent("#fsZ")) === "125%", await page.textContent("#fsZ"));
  const box = await page.$eval("#fsView", el => el.getBoundingClientRect().toJSON());
  const tr = async () => (await page.$eval("#fsStage", el => el.style.transform)).match(/-?[\d.]+/g).map(Number);
  const t0 = await tr();
  await page.mouse.move(box.x + 300, box.y + 300); await page.mouse.down(); await page.mouse.move(box.x + 360, box.y + 340); await page.mouse.up();
  const t1 = await tr();
  ok("drag pans by the drag distance", Math.round(t1[0] - t0[0]) === 60 && Math.round(t1[1] - t0[1]) === 40, t0 + " -> " + t1);
  await page.keyboard.press("Escape"); await page.waitForTimeout(150);
  ok("Esc closes full screen", await page.evaluate(() => document.getElementById("fs").hidden));
  await page.keyboard.press("Escape");

  // set up the 409 test on N2: pick a choice and write a note
  await page.click('.qbtn[data-q="N2"]'); await page.waitForTimeout(200);
  await page.click("#note"); await page.keyboard.type("Keep this note"); await page.keyboard.press("Escape"); await page.keyboard.press("1");
  ok("N2 armed with a note before the external revise", !!(await page.$(".choice.armed")));
  const rail = await page.evaluate(() => { const r = document.getElementById("railList"); return r.scrollHeight > r.clientHeight ? "scrolls" : "fits"; });
  ok("page itself never scrolls", await page.evaluate(() => document.scrollingElement.scrollHeight <= innerHeight + 1), rail);
  const inView = await page.evaluate(() => { const box = el => { const b = el.getBoundingClientRect(); return b.height > 0 && b.top >= 0 && b.left >= 0 && b.bottom <= innerHeight && b.right <= innerWidth; }; return {answer: box(document.getElementById("answer")), save: box(document.querySelector("[data-save]"))}; });
  ok("AC36: answer pane and Save sit inside the 1400 by 860 viewport", inView.answer && inView.save, JSON.stringify(inView));
  ok("zero console errors so far", errors.length === 0, errors.join(" | "));
  } catch (e) { R.push("ERROR " + e.message.split("\n")[0] + " | " + await page.evaluate(() => document.getElementById("flyTitle").textContent + " / sel=" + (document.querySelector('.qbtn[aria-current="true"]') || {}).dataset?.q + " / " + document.getElementById("fbody").innerText.slice(0, 200)).catch(() => "")); }
  return R.join("\n");
}
