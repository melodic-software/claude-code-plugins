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
