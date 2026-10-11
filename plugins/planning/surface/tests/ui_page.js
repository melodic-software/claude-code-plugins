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

    // #5917: five prerequisites share one wrapped row, and a met one is marked by more than colour
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
  ok("zero console errors in phase " + PHASE, errors.length === 0, errors.join(" | "));
  } catch (e) { R.push("ERROR " + e.message.split("\n")[0]); }
  return R.join("\n");
}
