async page => { // the question page itself: choices, chips, banners, header and layout; the shell writes as Claude between phases
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  const errors = [];
  page.on("console", m => { if (m.type() === "error") errors.push(m.text()); });
  page.on("pageerror", e => errors.push(String(e)));
  const PHASE = __PHASE__;
  const base = "http://127.0.0.1:__PORT__/";
  const text = async s => ((await page.textContent(s).catch(() => "")) || "").replace(/\s+/g, " ").trim();
  const pick = async id => {
    if (await page.$eval('.rail-list .qbtn[data-q="' + id + '"]', el => !el.offsetParent).catch(() => false)) await page.click('.sec:has(.qbtn[data-q="' + id + '"]) .sec-h');
    await page.click('.rail-list .qbtn[data-q="' + id + '"]'); await page.waitForTimeout(250);
  };
  const token = async () => page.$eval('meta[name="interview-token"]', m => m.content);
  const post = async body => page.request.post(base + "api/answer", {headers: {"Content-Type": "application/json", "X-Interview-Token": await token()}, data: body});
  const QS_MOD = "Ctrl", QS_HINT = verb => QS_MOD + " + Enter to " + verb; // Chromium on Linux: question-shape.js's MOD_KEY
  const recRow = () => page.$eval("#choices .choice.rec .t", el => ({text: el.textContent, clipped: el.scrollHeight > el.clientHeight + 1})).catch(() => ({text: "", clipped: true}));
  try {
  if (PHASE === 1) {
    await page.setViewportSize({width: 1440, height: 900});
    await page.goto(base);
    await page.waitForSelector(".qbtn", {state: "attached"});
    await page.evaluate(() => localStorage.clear());
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(300);

    // G7: the round's restate card sits above the round's first question and on no other
    await pick("Q1");
    const rs = await page.evaluate(() => { const c = document.getElementById("roundRestate"), h = document.querySelector("#dscroll .dhead");
      return {text: c ? c.textContent.replace(/\s+/g, " ").trim() : "", above: !!c && !!h && !!(c.compareDocumentPosition(h) & Node.DOCUMENT_POSITION_FOLLOWING), refs: c ? c.querySelectorAll("button.ref").length : 0}; });
    ok("G7: the round's restate card is above the first question, with its open branches", /Nothing is decided yet/.test(rs.text) && rs.above && rs.refs === 9, JSON.stringify(rs));
    await pick("Q2");
    ok("G7: a later question of the round shows no restate card", await page.$("#roundRestate") === null);

    // #7749: the Source text quote shows open and above the recommendation; a question without one renders as before
    for (const [w, h] of [[1440, 900], [390, 844]]) {
      await page.setViewportSize({width: w, height: h}); await page.waitForTimeout(250);
      await pick("Q1");
      const src = await page.evaluate(() => { const s = document.querySelector("#dscroll details.src"), r = document.querySelector("#dscroll .recbox"), m = document.querySelector("#dscroll details.more");
        return {open: !!s && s.open, text: s ? s.textContent.replace(/\s+/g, " ").trim() : "", above: !!s && !!r && !!(s.compareDocumentPosition(r) & Node.DOCUMENT_POSITION_FOLLOWING), moreHasQuote: !!m && /weekday/.test(m.textContent), moreKeepsRest: !!m && /bars weekend/.test(m.textContent)}; });
      ok("Q1's Source text quote is open and above the recommendation at " + w + " px, with the rest of facts under Details", src.open && src.above && /^Source text ?Releases ship on a weekday\.$/.test(src.text) && !src.moreHasQuote && src.moreKeepsRest, JSON.stringify(src));
      await pick("Q2");
      const none = await page.evaluate(() => ({src: document.querySelectorAll("#dscroll details.src").length, more: document.querySelectorAll("#dscroll details.more").length}));
      ok("Q2, with no source text, renders no Source text block at " + w + " px", none.src === 0 && none.more === 1, JSON.stringify(none));
      await pick("Q10");
      const two = await page.evaluate(() => { const s = document.querySelector("#dscroll details.src"), m = document.querySelector("#dscroll details.more");
        return {src: s ? s.textContent.replace(/\s+/g, " ").trim() : "", more: m ? m.textContent.replace(/\s+/g, " ").trim() : ""}; });
      ok("Q10's two-paragraph Source quote stays whole, with only the rest under Details at " + w + " px", /^Source text ?First paragraph\. ?Second paragraph\.$/.test(two.src) && /Rest\./.test(two.more) && !/paragraph/.test(two.more), JSON.stringify(two));
    }
    await page.setViewportSize({width: 1440, height: 900}); await page.waitForTimeout(250);

    // #5815: the Rec choice carries the whole recommendation, not its first sentence
    await pick("Q1");
    const wide = await recRow();
    ok("the Rec choice shows every sentence of the recommendation at 1440 px", /Ship it on Monday\..*Watch the error logs.*Roll back on the first new error/.test(wide.text) && !wide.clipped, JSON.stringify(wide));
    await page.setViewportSize({width: 390, height: 844}); await page.waitForTimeout(250);
    const narrow = await recRow();
    ok("the Rec choice shows every sentence of the recommendation at 390 px", /Roll back on the first new error/.test(narrow.text) && !narrow.clipped, JSON.stringify(narrow));
    // #7755: at 390 px the named buttons and each Decide row are touch-sized, and the selected Rec label reads at 4.5:1 in the light theme
    await page.emulateMedia({colorScheme: "light"}); await page.waitForTimeout(100);
    const sizes = await page.evaluate(() => {
      const want = ["Save", "Ask Claude", "Rephrase", "Research this", "Clear"], bs = [...document.querySelectorAll("button.act")];
      return {buttons: want.map(w => { const b = bs.find(x => x.textContent.trim().replace(/^Save.*/, "Save") === w); return [w, b ? Math.round(b.getBoundingClientRect().height) : 0]; }), rows: [...document.querySelectorAll("#choices .choice")].map(r => Math.round(r.getBoundingClientRect().height))};
    });
    ok("at 390 px Save, Ask Claude, Rephrase, Research this and Clear are at least 44 px tall", sizes.buttons.every(b => b[1] >= 44), JSON.stringify(sizes.buttons));
    ok("at 390 px each Decide row is at least 44 px tall", sizes.rows.length > 0 && sizes.rows.every(h => h >= 44), JSON.stringify(sizes.rows));
    await page.click("#choices .choice.rec"); await page.waitForTimeout(150);
    const recRatio = await page.$eval("#choices .choice.rec.armed .t b", el => {
      const rgb = s => s.match(/[\d.]+/g).map(Number), lum = c => { const v = c.slice(0, 3).map(x => { x /= 255; return x <= .03928 ? x / 12.92 : ((x + .055) / 1.055) ** 2.4; }); return .2126 * v[0] + .7152 * v[1] + .0722 * v[2]; };
      let b = el, bg = null;
      while (b && !bg) { const c = rgb(getComputedStyle(b).backgroundColor); if (c.length < 4 || c[3] > 0) bg = c; else b = b.parentElement; }
      const l1 = lum(rgb(getComputedStyle(el).color)), l2 = lum(bg);
      return (Math.max(l1, l2) + .05) / (Math.min(l1, l2) + .05);
    }).catch(() => 0);
    ok("the Rec label in the selected Decide row has at least 4.5:1 contrast in the light theme", recRatio >= 4.5, String(recRatio));
    await page.setViewportSize({width: 1440, height: 900}); await page.waitForTimeout(250);
    await page.click('[data-acceptall="g1"]'); await page.waitForSelector("#dlg[open]");
    const listed = await text("#dlgBody li");
    ok("the group Accept all list shows every sentence of the recommendation", /Ship it on Monday\..*Watch the error logs.*Roll back on the first new error/.test(listed), listed);
    await page.click("#dlgCancel"); await page.waitForTimeout(150);

    // #5917: five prerequisites share one wrapped row, and a met one is marked by more than color
    await post({id: "Q2", kind: "accept", alt: null, text: ""}); await page.waitForTimeout(900); await pick("Q7");
    for (const w of [1440, 390]) {
      await page.setViewportSize({width: w, height: w > 400 ? 900 : 844}); await page.waitForTimeout(250);
      if (w < 400 && await page.$eval("nav.rail", el => !el.offsetParent || el.getBoundingClientRect().width === 0).catch(() => true)) continue;
      const row = await page.$eval('.rail-list .qbtn[data-q="Q7"]', b => {
        const ns = [...b.querySelectorAll(".needsrow .needs")], t = b.querySelector(".qtitle").getBoundingClientRect();
        return {rows: b.querySelectorAll(".needsrow").length, n: ns.length, lines: new Set(ns.map(n => Math.round(n.getBoundingClientRect().top))).size, below: ns.every(n => n.getBoundingClientRect().top >= t.bottom - 1), marks: ns.map(n => n.textContent + (n.querySelector(".metmark") ? " [" + n.querySelector(".metmark").getAttribute("aria-label") + "]" : ""))};
      }).catch(e => ({error: String(e)}));
      ok("Q7's five needs chips sit in one wrapped row under its title at " + w + " px", row.rows === 1 && row.n === 5 && row.lines < 5 && row.below, JSON.stringify(row));
      if (w > 400) ok("the met prerequisite (Q2) carries a check and an answered label; an unmet one carries neither", /^needs Q2✓ \[answered\]$/.test(row.marks[0]) && row.marks.slice(1).every(m => !/✓|answered/.test(m)), JSON.stringify(row.marks));
    }
    await page.setViewportSize({width: 1440, height: 900}); await page.waitForTimeout(250);

    // #8083: an unpinned Notes or Activity flyout stays off the note box, Ask Claude and Rephrase at 1440 px
    await pick("Q1");
    for (const panel of ["notes", "activity"]) {
      await page.click('.strip [data-panel="' + panel + '"]'); await page.waitForTimeout(400);
      const hit = await page.evaluate(() => {
        const box = s => { const e = document.querySelector(s); if (!e || !e.offsetParent) return null; const r = e.getBoundingClientRect(); return {l: r.left, r: r.right, t: r.top, b: r.bottom}; };
        const fly = box("aside.fly.open"), hits = (a, b) => a.l < b.r && b.l < a.r && a.t < b.b && b.t < a.b;
        const names = {note: "#note", ask: '#talkRow [data-act="ask"]', rephrase: '#talkRow [data-act="rephrase"]'}, out = {pinned: document.getElementById("layout").classList.contains("pinned"), fly: !!fly};
        for (const k in names) { const b = box(names[k]); out[k] = !b ? "missing" : fly && hits(b, fly) ? "covered" : "clear"; }
        out.decideBar = Math.round(document.getElementById("answer").getBoundingClientRect().height);
        return out;
      });
      ok("at 1440 px the unpinned " + panel + " flyout does not cover the note box, Ask Claude or Rephrase", !hit.pinned && hit.fly && hit.note === "clear" && hit.ask === "clear" && hit.rephrase === "clear", JSON.stringify(hit));
      await page.click('.strip [data-panel="' + panel + '"]'); await page.waitForTimeout(250);
    }

    // #8085: at phone widths an id chip in Activity or Notes keeps each id on one line, even beside long text
    const toggle = panel => page.evaluate(p => document.querySelector('.strip [data-panel="' + p + '"]').click(), panel);
    const onOneLine = () => page.evaluate(() => {
      // Baseline-aligned boxes in two fonts have different tops on one line, so a rect starts a new line only below the last one's bottom.
      const lines = el => { const r = document.createRange(); r.selectNodeContents(el); let n = 0, bottom = -Infinity; for (const x of [...r.getClientRects()].sort((a, b) => a.top - b.top)) { if (x.top >= bottom - 1) n++; bottom = Math.max(bottom, x.bottom); } return n; };
      const chips = [...document.querySelectorAll("aside.fly.open .ref b, aside.fly.open .rrange")];
      return {n: chips.length, split: chips.filter(c => lines(c) > 1).map(c => c.textContent), page: document.scrollingElement.scrollWidth - innerWidth};
    });
    for (const [w, h] of [[390, 844], [425, 900]]) {
      await page.setViewportSize({width: w, height: h}); await page.waitForTimeout(250);
      await pick("Q1");
      for (const panel of ["activity", "notes"]) {
        await toggle(panel); await page.waitForTimeout(400);
        await page.evaluate(panel => {
          const chip = (id, title) => '<button type="button" class="ref" data-q="' + id + '"><b>' + id + "</b>" + title + "</button>";
          const range = '<span class="rrange" title="Q4 to Q6">' + chip("Q4", "") + "<span>&ndash;</span>" + chip("Q6", "") + "</span>";
          const host = document.querySelector(panel === "notes" ? "aside.fly.open .nthread" : "aside.fly.open .fbody");
          const box = document.createElement("div"); box.className = panel === "notes" ? "nmsg" : "links";
          box.innerHTML = "<p>Compare " + range + " with " + chip("Q2", "Build image cache key for the weekly release") + " and " + chip("Q7", "Pinned digests") + " before deciding.</p>";
          host.appendChild(box);
        }, panel);
        const got = await onOneLine();
        ok("at " + w + " px every id chip in " + panel + " keeps each id on one line", got.n > 0 && got.split.length === 0, JSON.stringify(got));
        await toggle(panel); await page.waitForTimeout(250);
      }
    }
    await page.setViewportSize({width: 1440, height: 900}); await page.waitForTimeout(250);
  }
  if (PHASE === 2) { // the shell revised Q1's recommendation with no why while Q8 was not open
    const banner = () => page.$$eval("#dscroll .banner", els => els.map(e => e.textContent).join(" | "));
    await pick("Q1");
    const first = await banner();
    ok("the first open after a revision shows the full banner, with the phrase once", (first.match(/Recommendation revised\./g) || []).length === 1, first);
    await pick("Q8"); await pick("Q1");
    ok("a later visit shows a Revised chip in its place, with Previous kept", !/Recommendation revised/.test(await banner()) && /Revised/.test(await text("#dscroll .revchip")) && /Previous/.test(await text("#dscroll .revchip")), await banner() + " / " + await text("#dscroll .revchip"));
    await pick("Q8");
  }
  if (PHASE === 3) { // the shell revised Q1 again
    await pick("Q1");
    ok("a further revision brings the full banner back on the next open", /Recommendation revised\./.test(await text("#dscroll .banner")) && !(await page.$("#dscroll .revchip")), await text("#dscroll .banner"));
  }
  if (PHASE === 4) { // Q7 is answered before its prerequisites, then the page changes Q2 under Show: Open
    const sel = () => page.evaluate(() => (document.querySelector('.qbtn[aria-current="true"]') || {}).dataset?.q || null);
    const first = () => page.$eval("#choices .choice", el => el.textContent).catch(() => "");
    for (const id of ["Q7", "Q3", "Q5", "Q4", "Q6"]) await post({id, kind: "accept", alt: null, text: ""});
    await page.waitForTimeout(900);
    await page.selectOption("#filter", "all"); await page.waitForTimeout(150);
    await pick("Q7");
    const b7 = await text("#dscroll .banner");
    ok("#5908: prerequisites first decided after this answer read 'was decided after you answered this'", /Stale: Q3Image was decided after you answered this; Q4Cache was decided after you answered this/.test(b7) && !/changed/.test(b7), b7);
    ok("#5908: the meter shows 1 to review and leaves the stale question out of answered", (await text("#revBtn")) === "1 to review" && (await text("#meterText")) === "5 of 9 answered", await text("#meterText") + " / " + await text("#revBtn"));
    await pick("Q2"); await page.selectOption("#filter", "open"); await page.waitForTimeout(150);
    await page.click('#choices .choice:has-text("A self-hosted machine")'); await page.click("[data-save]"); await page.waitForTimeout(1200);
    const toastT = await text("#toast");
    ok("#5909: the save lands on the first newly stale dependent and switches Show: Open to Review", await sel() === "Q3" && await page.$eval("#filter", el => el.value) === "review", await sel() + " / " + await page.$eval("#filter", el => el.value));
    ok("#5909: the toast names the newly stale questions and counts what waits on them", /^Saved Q2\. Q3 and Q5 need review; 2 more wait on them\. Now Q3\./.test(toastT), toastT);
    const b3 = await text("#dscroll .banner");
    ok("#5908: a prerequisite whose earlier decision was replaced reads 'changed'", /Stale: Q2Runner changed\. Your decision is kept/.test(b3), b3);
    ok("#5908: the meter now shows 3 to review and 3 of 9 answered", (await text("#revBtn")) === "3 to review" && (await text("#meterText")) === "3 of 9 answered", await text("#meterText") + " / " + await text("#revBtn"));
    await page.click("#qhead"); await page.keyboard.press("n"); await page.waitForTimeout(250);
    ok("#5909: n goes to the other newly stale dependent next", await sel() === "Q5", await sel());
    ok("#5910: a kept accept whose recommendation is unchanged still offers Reconfirm first", /^Reconfirm/.test((await first()).trim()), await first());
    await page.selectOption("#filter", "all"); await page.waitForTimeout(150);
    ok("#5922: a question two levels below the stale one waits on it, not on its direct prerequisite", /Waiting on Q3(?!,)/.test(await text('.qbtn[data-q="Q6"]')), await text('.qbtn[data-q="Q6"]'));
    await page.click("#revBtn"); await page.waitForTimeout(150);
    ok("#5908: the meter's review count opens Show: Review", await page.$eval("#filter", el => el.value) === "review");
  }
  if (PHASE === 5) { // the shell revised Q3's recommendation after its kept accept
    await page.waitForTimeout(600);
    await pick("Q3");
    const cs = await page.$$eval("#choices .choice", els => els.map(e => e.textContent));
    ok("#5910: no Reconfirm once the recommendation changed since the accept; Rec shows the revised text", !cs.some(t => /Reconfirm/.test(t)) && /pinned by digest/.test(await text("#choices .choice.rec")), JSON.stringify(cs));
    ok("#5910: the banner says Pick an answer and Previous keeps the old recommendation", /Pick an answer\./.test(await text("#dscroll .banner")) && /The default image\./.test(await text("#dscroll")), await text("#dscroll .banner"));
    ok("the revised banner labels the why as Claude's reason, not the user's note", /Claude's reason:\s*A digest cannot move under a tag\./.test(await text("#dscroll")) && !/Your note:/.test(await text("#dscroll .banner")), await text("#dscroll"));
    await page.click("#qhead"); await page.keyboard.press("a"); await page.waitForTimeout(150);
    ok("#5910: a arms Rec", /pinned by digest/.test(await text("#choices .choice.armed")), await text("#choices .choice.armed"));
  }
  if (PHASE === 6) { // the user asks Claude on Q8; the shell replies between phases
    await page.selectOption("#filter", "all"); await page.waitForTimeout(150);
    await pick("Q8"); await page.fill("#note", "Who reads the notes first?"); await page.click("#note"); await page.keyboard.press("Control+Shift+Enter"); await page.waitForTimeout(700);
  }
  if (PHASE === 7) { // #5817: the reply stays in the Thread, after a follow-up ask and a reload too
    const REPLY = /The support team reads them first/;
    await page.waitForTimeout(900); await pick("Q8");
    ok("#5817: Claude's reply to the ask is in the Thread, not only in the latest-reply box", REPLY.test(await text("#thread")) && REPLY.test(await text("#latest")), await text("#thread"));
    await page.click("#qhead"); await page.keyboard.press("l"); await page.waitForTimeout(300);
    const needs = await page.$eval("#actNeeds", h => (h.nextElementSibling || {}).textContent || "").catch(() => "");
    ok("#5817: the unanswered reply is listed under Activity: Needs you", /Replied on Q8/.test(needs), needs);
    await page.keyboard.press("Escape"); await page.waitForTimeout(150);
    await page.fill("#note", "And who reads them after that?"); await page.click("#note"); await page.keyboard.press("Control+Shift+Enter"); await page.waitForTimeout(700);
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(400); await pick("Q8");
    const th = await text("#thread");
    ok("#5817: after a follow-up ask and a reload the reply is still in the Thread, after the ask it answers", REPLY.test(th) && th.indexOf("And who reads them after that") < th.search(REPLY) && th.search(REPLY) < th.indexOf("Who reads the notes first"), th);
  }
  if (PHASE === 8) { // #5913: a long note or an open conflict box leaves the question body its share of the pane
    await page.setViewportSize({width: 1280, height: 800}); await page.waitForTimeout(250);
    await pick("Q2");
    const body = () => page.evaluate(() => {
      const d = document.querySelector("main.detail").getBoundingClientRect(), s = document.getElementById("dscroll"), b = s.getBoundingClientRect(), r = s.querySelector(".recbox"), rr = r && r.getBoundingClientRect();
      return {share: +(b.height / d.height).toFixed(2), top: s.scrollTop, rec: !!rr && rr.top >= b.top && rr.top + 20 <= b.bottom};
    });
    const short = await body();
    await page.fill("#note", Array.from({length: 600}, (_, i) => "word" + i).join(" ")); await page.waitForTimeout(250);
    const long = await body();
    ok("a 600-word note leaves the question body the share it had, with the recommendation in view", long.share >= short.share - 0.02 && long.top === 0 && long.rec, JSON.stringify({short, long}));
    ok("the answer panel scrolls inside its limit and Save is reachable in it", await page.evaluate(() => { const a = document.getElementById("answer"); const s = a.querySelector("[data-save]"); if (!s) return false; s.scrollIntoView({block: "nearest"}); const b = a.getBoundingClientRect(), r = s.getBoundingClientRect(); return a.scrollHeight > a.clientHeight && ["auto", "scroll"].includes(getComputedStyle(a).overflowY) && r.top >= b.top - 1 && r.bottom <= b.bottom + 1; }));
    await page.evaluate(() => { const c = document.getElementById("conflict"); c.hidden = false; c.innerHTML = "<p>" + "The question changed while you answered. ".repeat(60) + "</p>"; });
    const conf = await body();
    ok("an open conflict box leaves the question body the share it had", conf.share >= short.share - 0.02 && conf.rec, JSON.stringify({short, conf}));
    await page.fill("#note", ""); await page.evaluate(() => { document.getElementById("conflict").hidden = true; }); await page.waitForTimeout(150);
    const back = await body();
    ok("with a short note and no conflict the body keeps the space it had", Math.abs(back.share - short.share) <= 0.02, JSON.stringify({short, back}));
  }
  if (PHASE === 9) { // the page decides Q8; the shell then adds Q9 on Q8 and records Q9's decision from the terminal
    await post({id: "Q8", kind: "accept", alt: null, text: ""}); await page.waitForTimeout(900);
  }
  if (PHASE === 10) { // the page replaces Q8's decision after Q9's terminal decision
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(400);
    await post({id: "Q8", kind: "alt", alt: "a", text: ""}); await page.waitForTimeout(900);
    await page.selectOption("#filter", "all"); await page.waitForTimeout(150);
    await pick("Q9");
    const b9 = await text("#dscroll .banner");
    ok("#5908: a terminal decision whose prerequisite's earlier page decision was replaced reads 'changed'", /Stale: Q8Notes changed\./.test(b9) && !/decided after you answered/.test(b9), b9);
    const c9 = await page.$$eval("#choices .choice", els => els.map(e => e.textContent));
    ok("#5910: an older terminal accept (no rev) whose recommendation changed after it offers no Reconfirm", c9.length > 0 && !c9.some(t => /Reconfirm/.test(t)) && /support lead/.test(await text("#choices .choice.rec")), JSON.stringify(c9));
  }
  if (PHASE === 10) { // #7751: by now the feed holds revisions, an added question and a saved reply; Needs you lists only what waits on the user
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(400);
    const badge = await page.$eval("#actBadge", b => b.hidden ? 0 : +b.textContent.trim() || 0).catch(() => -1);
    await page.click("#qhead"); await page.keyboard.press("l"); await page.waitForTimeout(300);
    const split = await page.evaluate(() => {
      const h = document.getElementById("actNeeds"), n = h.nextElementSibling, log = document.getElementById("actLog");
      return {needs: (n ? n.textContent : "").replace(/\s+/g, " "), log: (log ? log.textContent : "").replace(/\s+/g, " "), count: +(h.textContent.match(/\((\d+)\)/) || [0, -1])[1], rows: n && n.matches("ol") ? n.children.length : 0, unseen: n && n.matches("ol") ? n.querySelectorAll("li.unseen").length : 0};
    });
    ok("#7751: added, revised and note-saved entries are in the log, not under Needs you", !/Added Q9|Revised Q|revised Q|added Q9/i.test(split.needs) && /Added Q9/.test(split.log) && /evised Q/.test(split.log), JSON.stringify(split));
    ok("#8035: a Notes reply that asks is under Needs you, a plain one is in the log", /Note posted/.test(split.needs) && /Note posted/.test(split.log) && split.rows > 0, JSON.stringify(split));
    ok("#7751: the Needs you heading counts only the entries listed under it", split.count === split.rows, JSON.stringify(split));
    ok("#7751: the Activity badge equals the unseen entries listed under Needs you", badge === split.unseen, badge + " badge / " + split.unseen + " unseen of " + split.count + " listed");
  }
  if (PHASE === 11) { // the note boxes run the shared composer (question-shape.js), and a phone page is pinned to the visual viewport
    const events = async () => (await (await page.request.get(base + "api/state")).json()).responses.events;
    await page.setViewportSize({width: 1440, height: 900});
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(400);
    await page.selectOption("#filter", "all"); await pick("Q10");
    const kit = await page.evaluate(() => ({src: !!document.querySelector('script[src="/question-shape.js"]'), max: document.getElementById("note").maxLength, hint: document.getElementById("saveHint").textContent, place: document.getElementById("note").placeholder}));
    ok("the note box is the composer's: its limit, and the send key hint and placeholder in the composer's words", kit.src && kit.max === 20000 && kit.hint === QS_HINT("save") && kit.place.includes(QS_MOD + "+Enter saves"), JSON.stringify(kit));
    await page.fill("#note", "x".repeat(14999)); await page.waitForTimeout(100);
    const below = await page.$eval("#noteCount", el => ({text: el.textContent, shown: el.getClientRects().length > 0}));
    await page.click("#note"); await page.keyboard.press("End"); await page.keyboard.type("y"); await page.waitForTimeout(100);
    const near = await page.$eval("#noteCount", el => ({text: el.textContent, shown: el.getClientRects().length > 0}));
    ok("the counter is hidden below three quarters of the limit and shows the count from there", below.text === "" && !below.shown && near.text === "15000 / 20000" && near.shown, JSON.stringify({below, near}));
    await page.fill("#note", Array.from({length: 60}, (_, i) => "line " + i).join("\n")); await page.waitForTimeout(150);
    const grown = await page.evaluate(() => { const t = document.getElementById("note"), p = document.querySelector("main.detail"); return {h: t.offsetHeight, pane: p.clientHeight, over: getComputedStyle(t).overflowY, line: parseFloat(getComputedStyle(t).lineHeight)}; });
    ok("a long note grows up to 40% of the question pane, then scrolls inside", grown.h > 3 * grown.line && grown.h <= grown.pane * 0.4 + 2 && grown.over === "auto", JSON.stringify(grown));
    await page.fill("#note", ""); await page.click("#qhead"); await page.keyboard.press("1");
    await page.click("#note"); await page.keyboard.type("Fine by me."); const n0 = (await events()).length;
    await page.keyboard.press("Control+Enter"); await page.waitForTimeout(800);
    const ev = await events(), last = ev[ev.length - 1] || {};
    ok("Ctrl+Enter in the note saves the armed choice once, with the note", ev.length === n0 + 1 && last.id === "Q10" && last.text === "Fine by me.", JSON.stringify({n0, n: ev.length, last}));
    await page.click("#qhead"); await page.keyboard.press("m"); await page.waitForSelector("#noteText");
    const panelHint = await page.$eval("#noteText", t => t.nextElementSibling.querySelector(".kbd").textContent);
    await page.click("#noteText"); await page.keyboard.type("A note from the composer check."); const m0 = (await events()).length;
    await page.keyboard.press("Control+Enter"); await page.waitForTimeout(800);
    const mv = await events(), ml = mv[mv.length - 1] || {};
    ok("Ctrl+Enter in the Notes panel sends one note, and the panel names the key the composer's way", mv.length === m0 + 1 && ml.kind === "note" && ml.text === "A note from the composer check." && panelHint === QS_HINT("send"), JSON.stringify({m0, n: mv.length, ml, panelHint}));
    await page.keyboard.press("Escape"); await page.keyboard.press("Escape"); await page.waitForTimeout(150);
    // a phone: the page is pinned to the visual viewport, and a keyboard taking its lower part leaves the note in view
    await page.setViewportSize({width: 390, height: 844}); await page.waitForTimeout(300);
    await pick("Q1"); await page.click("#note"); await page.waitForTimeout(100);
    const pin = await page.evaluate(() => { const a = document.querySelector(".app"), cs = getComputedStyle(a); return {pos: cs.position, h: Math.round(a.getBoundingClientRect().height), vv: Math.round(visualViewport.height), page: document.scrollingElement.scrollHeight - innerHeight, scrolls: a.scrollHeight > a.clientHeight}; });
    ok("at 390 px the page is pinned to the visual viewport and scrolls inside it, not the document", pin.pos === "fixed" && Math.abs(pin.h - pin.vv) <= 1 && pin.page <= 1 && pin.scrolls, JSON.stringify(pin));
    const kb = await page.evaluate(async () => {
      const frame = () => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
      Object.defineProperty(visualViewport, "height", {configurable: true, get: () => 400}); // a 444 px keyboard
      window.QuestionShape.fitViewport(); await frame();
      const a = document.querySelector(".app").getBoundingClientRect(), n = document.getElementById("note").getBoundingClientRect();
      const out = {kb: getComputedStyle(document.documentElement).getPropertyValue("--kb").trim(), dataKb: "kb" in document.documentElement.dataset, app: Math.round(a.height), noteTop: Math.round(n.top), noteBottom: Math.round(n.bottom), focused: document.activeElement.id};
      delete visualViewport.height; window.QuestionShape.fitViewport(); await frame();
      return out;
    });
    ok("a keyboard on the phone shrinks the page to what it leaves and the focused note stays in that part", kb.kb === "444px" && kb.dataKb && kb.app === 400 && kb.noteTop >= 0 && kb.noteBottom <= 400 && kb.focused === "note", JSON.stringify(kb));
    await page.keyboard.type("draft on Q1"); await pick("Q10"); await pick("Q1");
    const kept = await page.inputValue("#note");
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(400); await pick("Q1");
    ok("each question keeps its own note draft across a switch and a reload", kept === "draft on Q1" && await page.inputValue("#note") === "draft on Q1", kept);
    await page.fill("#note", ""); await page.setViewportSize({width: 1440, height: 900});
  }
  if (PHASE === 12) { // gap G8: the shell recorded two constraints with the constraint op; the header lists them
    await page.setViewportSize({width: 1440, height: 900});
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(400);
    const sum = await text("#consSum");
    ok("the header shows \"Constraints (2)\" for two recorded constraints", sum === "Constraints (2)" && await page.$eval("#consPanel", el => !el.hidden), sum);
    await page.click("#consSum"); await page.waitForTimeout(150);
    const items = await page.$$eval("#consList li", els => els.map(li => li.textContent));
    ok("the open panel lists each constraint with its id", items.length === 2 && items[0] === "C1Builds stop at ten minutes." && items[1] === "C2Stdlib only.", JSON.stringify(items));
  }
  const events = async () => (await (await page.request.get(base + "api/state")).json()).responses.events;
  const dialog = () => page.evaluate(() => { const a = document.getElementById("dlgAlt"); return {open: document.getElementById("dlg").open, title: document.getElementById("dlgTitle").textContent, ok: document.getElementById("dlgOk").textContent, alt: a.hidden ? null : a.textContent}; });
  if (PHASE === 13) { // #9709: frontierLock confirm, the default; the shell added Q11 (round 2, open) and Q12 (round 3, needs Q11)
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(400);
    await page.selectOption("#filter", "all"); await page.waitForTimeout(150);
    const chip = await page.$eval('.qbtn[data-q="Q12"] .qmeta', el => ({text: el.textContent, lock: !!el.querySelector(".lockchip svg.padlock")})).catch(e => ({error: String(e)}));
    ok("#9709: the rail shows a padlock chip in place of Blocked on a question whose prerequisite is open", chip.lock && /Locked/.test(chip.text) && !/Blocked/.test(chip.text), JSON.stringify(chip));
    await pick("Q12"); await page.click("#choices .choice.rec"); const n0 = (await events()).length;
    await page.click("[data-save]"); await page.waitForSelector("#dlg[open]");
    const d1 = await dialog();
    ok("#9709: Save on a blocked question opens the confirm dialog with Go to and Answer anyway, and sends nothing yet", d1.title === "Q12 depends on Q11, which is still open." && d1.ok === "Go to Q11" && d1.alt === "Answer anyway" && (await events()).length === n0, JSON.stringify(d1));
    await page.click("#dlgOk"); await page.waitForTimeout(300);
    const at = await page.evaluate(() => (document.querySelector('.qbtn[aria-current="true"]') || {}).dataset?.q || null);
    ok("#9709: Go to opens the open prerequisite and saves nothing", at === "Q11" && (await events()).length === n0, at);
    await pick("Q12"); await page.click("#choices .choice.rec"); await page.click("[data-save]"); await page.waitForSelector("#dlg[open]");
    await page.click("#dlgAlt"); await page.waitForTimeout(900);
    const ev = await events(), last = ev[ev.length - 1] || {};
    ok("#9709: Answer anyway saves the decision with outOfOrder naming the open prerequisite", ev.length === n0 + 1 && last.id === "Q12" && last.kind === "accept" && JSON.stringify(last.outOfOrder) === '["Q11"]', JSON.stringify(last));
  }
  if (PHASE === 14) { // #9709: the shell set frontierLock hard in the data dir's settings.json; Q11 is still open
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(400);
    await page.selectOption("#filter", "all"); await page.waitForTimeout(150);
    await pick("Q12"); await page.click("#choices .choice.rec"); await page.fill("#note", "Why does this wait on the rollout?"); await page.waitForTimeout(150);
    const ctl = await page.evaluate(() => { const on = s => { const e = document.querySelector(s); return e ? !e.disabled : null; }; return {save: on("[data-save]"), ask: on('#talkRow [data-act="ask"]'), rephrase: on('#talkRow [data-act="rephrase"]'), research: on('#talkRow [data-research="research"]'), hint: document.getElementById("saveHint").textContent}; });
    ok("#9709: under hard, Save is disabled and names the lock while Ask, Rephrase and Research this stay enabled", ctl.save === false && ctl.ask === true && ctl.rephrase === true && ctl.research === true && ctl.hint === "Locked: answer Q11 first", JSON.stringify(ctl));
    const n0 = (await events()).length;
    await page.click("#note"); await page.keyboard.press("Control+Enter"); await page.waitForSelector("#dlg[open]");
    const d2 = await dialog();
    ok("#9709: Ctrl+Enter under hard offers Go to and no Answer anyway, and sends nothing", d2.title === "Q12 depends on Q11, which is still open." && d2.ok === "Go to Q11" && d2.alt === null && (await events()).length === n0, JSON.stringify(d2));
    await page.click("#dlgCancel"); await page.waitForTimeout(150);
    const res = await post({id: "Q12", kind: "accept", alt: null, text: "", outOfOrder: ["Q11"]}), body = await res.json();
    ok("#9709: under hard the server answers a decision ahead of an open prerequisite 409 blocked", res.status() === 409 && body.error === "blocked" && JSON.stringify(body.waitsOn) === '["Q11"]', res.status() + " " + JSON.stringify(body));
    await page.click('#talkRow [data-act="ask"]'); await page.waitForTimeout(800);
    const ev = await events(), last = ev[ev.length - 1] || {};
    ok("#9709: Ask still sends under hard", ev.length === n0 + 1 && last.id === "Q12" && last.kind === "ask", JSON.stringify(last));
    await post({id: "Q11", kind: "accept", alt: null, text: ""}); await page.waitForTimeout(600);
    const q12 = (await (await page.request.get(base + "api/state")).json()).questions.questions.find(q => q.id === "Q12") || {};
    ok("#9709: deciding the prerequisite marks the out-of-order answer stale", q12.state === "stale", q12.state);
  }
  if (PHASE === 15) { // #9714: the shell set frontierLock back to confirm and added Q13, unanswered, on Q11; the page changes Q11's answer
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(400);
    await page.selectOption("#filter", "all"); await page.waitForTimeout(150);
    await post({id: "Q11", kind: "alt", alt: "a", text: ""}); await page.waitForTimeout(900);
    const qs = (await (await page.request.get(base + "api/state")).json()).questions.questions, q13 = qs.find(q => q.id === "Q13") || {}, q12 = qs.find(q => q.id === "Q12") || {};
    ok("#9714: a changed answer marks the undecided dependent upstream-changed and keeps the decided one stale", q13.state === "upstream-changed" && JSON.stringify(q13.changedBy) === '["Q11"]' && q12.state === "stale", q13.state + " " + JSON.stringify(q13.changedBy) + " / " + q12.state);
    const chip = await page.$eval('.qbtn[data-q="Q13"] .qmeta', el => ({text: el.textContent, lock: !!el.querySelector(".upchip svg.padlock")})).catch(e => ({error: String(e)}));
    ok("#9714: the dependent's rail card says the upstream change is not handled yet, with a padlock", chip.lock && /Upstream changed, not handled yet/.test(chip.text), JSON.stringify(chip));
    await pick("Q13");
    const ban = await text("#upstreamChanged");
    ok("#9714: its detail pane names the changed question and says Save stays locked", /^Upstream changed, not handled yet: the answer to Q11.* changed or was reopened, and Claude has not revised or reconfirmed Q13 yet\. Save stays locked until it does/.test(ban), ban);
    await page.click("#choices .choice.rec"); await page.fill("#note", "Does this still hold?"); await page.waitForTimeout(150);
    const ctl = await page.evaluate(() => { const on = s => { const e = document.querySelector(s); return e ? !e.disabled : null; }; return {save: on("[data-save]"), ask: on('#talkRow [data-act="ask"]'), rephrase: on('#talkRow [data-act="rephrase"]'), hint: document.getElementById("saveHint").textContent}; });
    ok("#9714: under confirm, Save is disabled and names the change while Ask and Rephrase stay enabled", ctl.save === false && ctl.ask === true && ctl.rephrase === true && ctl.hint === "Locked: Claude reviews it after Q11 changed", JSON.stringify(ctl));
    const n0 = (await events()).length;
    await page.click("#note"); await page.keyboard.press("Control+Enter"); await page.waitForTimeout(400);
    const t = await text("#toast");
    ok("#9714: Ctrl+Enter sends nothing and says why", (await events()).length === n0 && /^Not saved: The answer to Q11 changed or was reopened/.test(t) && !(await page.evaluate(() => document.getElementById("dlg").open)), t);
    const res = await post({id: "Q13", kind: "accept", alt: null, text: ""}), body = await res.json();
    ok("#9714: the server answers a decision on it 409 upstream-changed, naming the changed question", res.status() === 409 && body.error === "upstream-changed" && JSON.stringify(body.changedBy) === '["Q11"]', res.status() + " " + JSON.stringify(body));
  }
  if (PHASE === 16) { // #9714: the shell reconfirmed Q13
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(400);
    await page.selectOption("#filter", "all"); await page.waitForTimeout(150);
    await pick("Q13");
    const q13 = (await (await page.request.get(base + "api/state")).json()).questions.questions.find(q => q.id === "Q13") || {};
    ok("#9714: a reconfirm clears the state, the banner and the rail mark", q13.state === "open" && !q13.changedBy && !(await page.$("#upstreamChanged")) && !(await page.$('.qbtn[data-q="Q13"] .upchip')), q13.state + " " + JSON.stringify(q13.changedBy));
    ok("#9714: the thread shows Claude's reconfirm line", /Reconfirmed after Q11.* changed: The rollback owner does not turn on the rollout width\./.test(await text("#thread")), await text("#thread"));
    await page.click("#choices .choice.rec"); await page.waitForTimeout(150);
    ok("#9714: Save is enabled again", await page.$eval("[data-save]", el => !el.disabled), await text("#saveHint"));
  }
  ok("zero console errors in phase " + PHASE, errors.length === 0, errors.join(" | "));
  } catch (e) { R.push("ERROR " + e.message.split("\n")[0]); }
  return R.join("\n");
}
