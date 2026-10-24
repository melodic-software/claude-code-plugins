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
  const w4 = await page.$$eval(".qbtn .qid", els => els.filter(e => e.offsetParent).map(e => Math.round(e.getBoundingClientRect().width)));
  ok("every rail card has the same fixed id column, wide enough for its id", new Set(w4).size === 1 && n4.idW >= n4.textW && n4.tLeft >= n4.idRight, JSON.stringify([w4, n4]));
  for (const id of ["Q8", "Q9", "Q7", "Q11"]) if (!(await page.isVisible('.qbtn[data-q="' + id + '"]'))) await page.evaluate(i => document.querySelector('.qbtn[data-q="' + i + '"]').closest(".sec").querySelector(".sec-h").click(), id);
  const lay = await page.evaluate(() => ["Q8", "Q9", "Q7", "Q11"].map(id => {
    const b = document.querySelector('.qbtn[data-q="' + id + '"]'), t = b.querySelector(".qtitle").getBoundingClientRect(), qid = b.querySelector(".qid").getBoundingClientRect(), ns = [...b.querySelectorAll(".needs")];
    return {id, n: ns.length, col2: t.left >= qid.right && t.top < qid.bottom, rows: b.querySelectorAll(".needsrow").length, tops: ns.map(n => Math.round(n.getBoundingClientRect().top)), below: ns.every(n => n.getBoundingClientRect().top >= t.bottom - 1), over: [b, ...b.querySelectorAll("*")].filter(e => e.scrollWidth > e.clientWidth && getComputedStyle(e).textOverflow !== "ellipsis").map(e => e.className || e.tagName)};
  }));
  ok("cards with 0, 1, 2 and 4 dependsOn put the title in column 2 on row 1", lay.map(l => l.n).join() === "0,1,2,4" && lay.every(l => l.col2), JSON.stringify(lay));
  ok("#5917: the needs chips share one wrapped row below the title", lay.every(l => l.rows === (l.n ? 1 : 0) && new Set(l.tops).size < Math.max(l.n, 2) && l.below), JSON.stringify(lay.map(l => [l.rows, l.tops])));
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
  const dec = await page.evaluate(() => { const t = [...document.querySelectorAll("#choices .choice .t")].find(e => /request/.test(e.textContent)); return t ? {code: [...t.querySelectorAll("code")].map(c => c.textContent), text: t.textContent, bold: [...t.querySelectorAll("b")].map(b => b.textContent), link: [...t.querySelectorAll("a")].map(a => a.textContent + " " + a.getAttribute("href"))} : null; });
  ok("a Decide row renders backticked code as a code element and shows <b> as text, not markup", !!dec && dec.code.join() === "request" && dec.text.includes("<b>by default</b>") && !dec.bold.includes("by default"), JSON.stringify(dec));
  ok("a bare issue number in a Decide row renders as an issue link", !!dec && dec.link.join() === "#77 https://github.com/o/r/issues/77", JSON.stringify(dec));
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
  const flyBox = await page.evaluate(() => { const f = document.getElementById("fly").getBoundingClientRect(), m = document.querySelector("main.detail").getBoundingClientRect(); return {overlay: getComputedStyle(document.getElementById("fly")).position === "absolute", vw: innerWidth, mainW: Math.round(m.width), flyL: Math.round(f.left), mainR: Math.round(m.right)}; });
  ok("unpinned flyout floats beside the answer pane without covering it from 1100px", flyBox.overlay && (flyBox.vw < 1100 || flyBox.flyL >= flyBox.mainR), JSON.stringify(flyBox));
  await page.click('#tabs [data-panel="notes"]'); await page.waitForTimeout(200);
  ok("Notes tab", await page.textContent("#flyTitle") === "Notes to Claude" && !!(await page.$("#noteText")));
  await page.click('#tabs [data-panel="settings"]'); await page.waitForTimeout(200);
  ok("Settings tab", await page.textContent("#flyTitle") === "Settings" && !!(await page.$('[data-set="shortcuts"]')));
  await page.focus('#tabs [data-panel="settings"]'); await page.keyboard.press("ArrowRight"); await page.waitForTimeout(200);
  ok("ArrowRight wraps from the last tab to the first and moves focus with it", await page.evaluate(() => document.activeElement.dataset.panel === "visuals" && document.activeElement.getAttribute("aria-selected") === "true" && document.getElementById("flyTitle").textContent.startsWith("Visuals")));
  await page.keyboard.press("End"); await page.waitForTimeout(150);
  ok("End goes to the last tab; only the selected tab is in the tab order", await page.evaluate(() => document.activeElement.dataset.panel === "settings" && [...document.querySelectorAll('#tabs [role="tab"]')].filter(b => b.tabIndex === 0).length === 1));
  await page.keyboard.press("ArrowLeft"); await page.waitForTimeout(150);
  ok("ArrowLeft goes back one tab", await page.evaluate(() => document.activeElement.dataset.panel === "terms"));
  ok("Terms tab lists the defined terms", await page.textContent("#flyTitle") === "Terms" && await page.$$eval("#fbody dl.terms dt", els => els.map(e => e.textContent).join()) === "markdown");
  const before = await sel();
  await page.evaluate(() => document.querySelector('.qbtn[data-q="Q1"]').click()); await page.waitForTimeout(200);
  ok("a defined term used in a question title shows its definition on hover", await page.$$eval("#qhead abbr.term", els => els.map(e => e.textContent + "=" + e.title).join()) === "markdown=The small text markup the page renders in question text.");
  await page.evaluate(id => document.querySelector('.qbtn[data-q="' + id + '"]').click(), before); await page.waitForTimeout(200);
  await page.focus('#tabs [data-panel="terms"]');
  await page.keyboard.press("ArrowRight"); await page.waitForTimeout(150); // back on Settings, where the steps below expect to be
  ok("the font stacks name no web font the CSP cannot load", await page.evaluate(() => { const c = getComputedStyle(document.documentElement); return !/Plex|Newsreader/.test(c.getPropertyValue("--sans") + c.getPropertyValue("--mono") + c.getPropertyValue("--display")); }));
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
  await page.click("#noteText"); await page.keyboard.type("Side note for Claude, see #123"); await page.keyboard.press("Enter");
  ok("plain Enter in a note does not send", (await events()).length === n3);
  await page.keyboard.press("Control+Enter"); await page.waitForTimeout(600);
  const ev4 = await events();
  ok("note sent as event kind note", ev4[ev4.length - 1].kind === "note" && ev4[ev4.length - 1].id === null, ev4[ev4.length - 1].text);
  ok("note shows in the thread", /Side note for Claude/.test(await page.textContent(".nthread")));
  ok("a bare issue number in a note renders as an issue link", (await page.$$eval(".nthread a", as => as.map(a => a.textContent + " " + a.getAttribute("href")))).includes("#123 https://github.com/o/r/issues/123"));
  ok("a short thread has no jump control and no folded note", !(await page.$("[data-notenewest]")) && !(await page.$("[data-notetoggle]")));
  for (let i = 1; i <= 6; i++) {
    await page.fill("#noteText", "Folding note " + i + (i === 6 ? "\n" + "newest filler line\n".repeat(40) : "\nsecond line " + i));
    await page.click("[data-sendnote]"); await page.waitForTimeout(500);
  }
  for (const pinned of [false, true]) {
    if ((await page.getAttribute("#pinBtn", "aria-pressed")) !== String(pinned)) await page.click("#pinBtn");
    await page.waitForTimeout(200);
    const tag = pinned ? "pinned" : "unpinned";
    ok("a long thread folds an older note to one line (" + tag + ")", await page.evaluate(() => { const b = document.querySelector('[data-notetoggle][aria-expanded="false"]'); return !!b && b.nextElementSibling.hidden && !document.querySelector("#noteNewest [data-notetoggle]"); }));
    await page.evaluate(() => { document.getElementById("fbody").scrollTop = 0; });
    await page.focus("[data-notenewest]"); await page.keyboard.press("Enter"); await page.waitForTimeout(200);
    ok("the jump control, from the keyboard, brings the newest note into the panel (" + tag + ")", await page.evaluate(() => { const r = document.getElementById("noteNewest").getBoundingClientRect(), p = document.getElementById("fbody").getBoundingClientRect(); return r.top < p.bottom && r.bottom > p.top; }));
    await page.evaluate(() => { document.getElementById("fbody").scrollTop = 0; });
    await page.click('[data-notetoggle][aria-expanded="false"]'); await page.waitForTimeout(100);
    ok("clicking a folded note expands it (" + tag + ")", await page.evaluate(() => { const b = document.querySelector("[data-notetoggle]"); return b.getAttribute("aria-expanded") === "true" && !b.nextElementSibling.hidden; }));
    await page.click("[data-notetoggle]"); await page.waitForTimeout(100);
  }
  await page.click("#pinBtn"); await page.waitForTimeout(150); // leave the panel unpinned, as the rest of the run expects
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

  // medium widths: the agrid stays two columns down to 900 px, the rail cut is marked, nothing widens the page
  await page.click('.qbtn[data-q="N2"]'); await page.waitForTimeout(200);
  for (const [w, h] of [[1440, 900], [1000, 800], [1000, 640], [860, 640]]) { // the dock never starves the question, Save sits in a footer, and no choice renders behind or below it
    await page.setViewportSize({width: w, height: h}); await page.waitForTimeout(250);
    const m = await page.evaluate(() => { const c = document.getElementById("choices"), d = document.getElementById("dscroll"), main = document.querySelector("main.detail"), save = document.querySelector("[data-save]").getBoundingClientRect(), dock = document.getElementById("answer").getBoundingClientRect();
      return {choicesScroll: c.scrollHeight > c.clientHeight + 1, detail: d.clientHeight, main: main.clientHeight, saveShown: save.top >= dock.top && save.bottom <= dock.bottom + 1}; });
    ok("at " + w + "x" + h + " the question keeps at least 40% of the pane and Save is in view" + (w === 1440 ? ", with every choice shown unscrolled" : ""), (w !== 1440 || !m.choicesScroll) && m.detail >= 0.4 * m.main && m.saveShown, JSON.stringify(m));
    const bad = await page.evaluate(() => { // each choice's rect clipped to every scroll container above it, at rest and scrolled to the end
      const a = document.getElementById("answer"), c = document.getElementById("choices"), out = [];
      const check = when => {
        const s = document.getElementById("decideRow").getBoundingClientRect();
        document.querySelectorAll("#choices .choice").forEach((el, i) => {
          let r = el.getBoundingClientRect(), top = r.top, bot = r.bottom;
          for (const p of [c, a]) { const b = p.getBoundingClientRect(); top = Math.max(top, b.top); bot = Math.min(bot, b.bottom); }
          if (bot - top <= 0.5) return;
          if (top < s.bottom - 0.5 && bot > s.top + 0.5) out.push(when + " #" + (i + 1) + " behind Save [" + Math.round(top) + "," + Math.round(bot) + "] vs [" + Math.round(s.top) + "," + Math.round(s.bottom) + "]");
          else if (top >= s.bottom - 0.5) out.push(when + " #" + (i + 1) + " below Save at " + Math.round(top));
        });
      };
      a.scrollTop = 0; c.scrollTop = 0; check("rest");
      a.scrollTop = a.scrollHeight; c.scrollTop = c.scrollHeight; check("end");
      a.scrollTop = 0; c.scrollTop = 0;
      return out;
    });
    ok("at " + w + "x" + h + " no choice renders behind or below Save, at rest or scrolled to the end", bad.length === 0, bad.join("; "));
  }
  for (const w of [1024, 820]) {
    await page.setViewportSize({width: w, height: 860}); await page.waitForTimeout(250);
    const m = await page.evaluate(() => ({cols: getComputedStyle(document.querySelector(".agrid")).gridTemplateColumns.split(" ").length, wide: document.scrollingElement.scrollWidth - innerWidth, railB: getComputedStyle(document.querySelector("nav.rail")).borderBottomWidth, choice: getComputedStyle(document.querySelector(".choice:not(.rec) .t")).webkitLineClamp}));
    ok("at " + w + " px the answer grid is " + (w > 900 ? "two columns" : "one column") + " and the page does not widen", m.cols === (w > 900 ? 2 : 1) && m.wide <= 1, JSON.stringify(m));
    if (w === 820) ok("at 820 px the rail ends in a border", m.railB === "1px", m.railB);
    ok("an option title may take two lines at " + w + " px", m.choice === "2", m.choice);
    await page.click(".sumbtn"); await page.waitForTimeout(250);
    ok("the summary renders no Decisions table without a decision row at " + w + " px", await page.evaluate(() => [...document.querySelectorAll("#dscroll table.sum")].every(t => t.tBodies[0] && t.tBodies[0].rows.length > 0)));
    ok("the summary does not widen the page at " + w + " px", await page.evaluate(() => document.scrollingElement.scrollWidth <= innerWidth + 1));
    await page.click('.qbtn[data-q="N2"]').catch(() => {}); await page.waitForTimeout(150);
  }
  await page.setViewportSize({width: 390, height: 844}); await page.waitForTimeout(250);
  const ph = await page.evaluate(() => ({main: Math.round(document.querySelector("main.detail").getBoundingClientRect().top + scrollY), rail: Math.round(document.querySelector("nav.rail").getBoundingClientRect().top + scrollY)}));
  ok("at 390 px the current question comes before the question list", ph.main < ph.rail, JSON.stringify(ph));
  await page.click('.rail-list .qbtn[data-q="N1"]'); await page.waitForTimeout(300);
  const pt = await page.evaluate(() => ({sel: (document.querySelector('.qbtn[aria-current="true"]') || {}).dataset?.q, top: Math.round(document.querySelector("main.detail").getBoundingClientRect().top)}));
  ok("at 390 px a pick from the list scrolls its question into view", pt.sel === "N1" && pt.top >= -1 && pt.top < 200, JSON.stringify(pt));
  await page.evaluate(() => scrollTo(0, 0)); await page.click('.qbtn[data-q="N2"]').catch(() => {});
  await page.setViewportSize({width: 1400, height: 860}); await page.waitForTimeout(250);
  ok("the meter title states the archived count", /\d+ archived/.test(await page.getAttribute("#meterText", "title")), await page.getAttribute("#meterText", "title"));
  ok("the header shows live and archived counts as visible text", /^\d+ live, \d+ archived$/.test(await page.textContent("#qCounts")), await page.textContent("#qCounts"));
  await page.selectOption("#filter", "pending"); await page.waitForTimeout(200);
  ok("a filter that matches nothing says so in the rail, not a blank list", (await page.$$(".rail-list .qbtn")).length > 0 || /No questions match/.test(await page.textContent("#railList")));
  await page.selectOption("#filter", "all"); await page.waitForTimeout(200);

  // a session with no answered question, on a second page whose state has its events, page responses and terminal decisions stripped and whose stream is refused (the 3 s poll then feeds the page the same stripped state)
  const stripped = await page.context().newPage();
  await stripped.route("**/events", r => r.abort());
  await stripped.route("**/api/state", async route => { const res = await route.fetch(); const body = await res.json(); body.responses.events = []; body.responses.responses = {}; for (const q of body.questions.questions) delete q.terminal; await route.fulfill({response: res, json: body}); });
  await stripped.setViewportSize({width: 1400, height: 860});
  await stripped.goto(base); await stripped.waitForSelector(".qbtn", {state: "attached"});
  await stripped.click(".sumbtn"); await stripped.waitForTimeout(400);
  const sum0 = await stripped.evaluate(() => { const hs = [...document.querySelectorAll("#dscroll h4")].map(h => h.textContent.trim()); return {table: !!document.querySelector("#dscroll table.sum"), decisions: hs.includes("Decisions"), loose: hs.includes("Loose ends")}; });
  ok("with no answered question the summary has no Decisions table or heading but still renders its other sections", !sum0.table && !sum0.decisions && sum0.loose, JSON.stringify(sum0));
  await stripped.close();

  // the connection pill: neutral Connecting until a first attempt has failed, then Connection lost
  const pillOf = p => p.evaluate(() => ({cls: document.getElementById("pill").className, text: document.getElementById("pill").textContent}));
  const wake = p => p.evaluate(() => { Object.defineProperty(document, "visibilityState", {configurable: true, get: () => "visible"}); document.dispatchEvent(new Event("visibilitychange")); });
  const hung = await page.context().newPage();
  await hung.route("**/api/state", () => {}); await hung.route("**/events", () => {});
  await hung.goto(base, {waitUntil: "domcontentloaded"}); await wake(hung); await hung.waitForTimeout(500);
  const pc = await pillOf(hung);
  ok("before any connection result the pill reads Connecting, not Connection lost", /\bconnecting\b/.test(pc.cls) && pc.text === "Connecting", JSON.stringify(pc));
  await hung.close();
  const refused = await page.context().newPage();
  await refused.route("**/api/state", r => r.abort()); await refused.route("**/events", r => r.abort());
  await refused.goto(base, {waitUntil: "domcontentloaded"}); await wake(refused); await refused.waitForTimeout(500);
  const pd = await pillOf(refused);
  ok("after a failed connection attempt the pill reads Connection lost", /\boffline\b/.test(pd.cls) && /^Connection lost/.test(pd.text), JSON.stringify(pd));
  await refused.close();

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
