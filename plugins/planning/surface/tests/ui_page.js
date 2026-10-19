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
  const recRow = () => page.$eval("#choices .choice.rec .t", el => ({text: el.textContent, clipped: el.scrollHeight > el.clientHeight + 1})).catch(() => ({text: "", clipped: true}));
  try {
  if (PHASE === 1) {
    await page.setViewportSize({width: 1440, height: 900});
    await page.goto(base);
    await page.waitForSelector(".qbtn", {state: "attached"});
    await page.evaluate(() => localStorage.clear());
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(300);

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
    await page.setViewportSize({width: 1440, height: 900}); await page.waitForTimeout(250);
    await page.click('[data-acceptall="g1"]'); await page.waitForSelector("#dlg[open]");
    const listed = await text("#dlgBody li");
    ok("the Accept all list still shows the recommendation's first sentence only", /Ship it on Monday\./.test(listed) && !/Watch the error logs/.test(listed), listed);
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
  ok("zero console errors in phase " + PHASE, errors.length === 0, errors.join(" | "));
  } catch (e) { R.push("ERROR " + e.message.split("\n")[0]); }
  return R.join("\n");
}
