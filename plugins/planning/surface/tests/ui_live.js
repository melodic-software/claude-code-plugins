async page => { // an open tab shows every change Claude applies without a reload, with a note half typed; the shell applies between phases
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  const errors = [];
  page.on("console", m => { if (m.type() === "error") errors.push(m.text()); });
  page.on("pageerror", e => errors.push(String(e)));
  const PHASE = __PHASE__;
  const base = "http://127.0.0.1:__PORT__/";
  const text = async s => (await page.textContent(s).catch(() => "")) || "";
  const rail = async id => (await page.textContent('.rail-list .qbtn[data-q="' + id + '"]').catch(() => "")) || "";
  const alts = () => page.$$eval(".alt", els => els.map(e => e.textContent.replace(/\s+/g, " ").trim()).join(" | "));
  const until = (fn, arg) => page.waitForFunction(fn, arg, {timeout: 6000}).then(() => true).catch(() => false);
  const recIs = (want) => until(w => (document.querySelector("#choices .choice.rec") || {}).textContent.includes(w), want);
  try {
  if (PHASE === 1) {
    await page.setViewportSize({width: 1400, height: 860});
    await page.goto(base);
    await page.waitForSelector(".qbtn", {state: "attached"});
    await page.evaluate(() => localStorage.clear());
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(400);
    // Q3 is accepted from the page with a note, so its event waits for Claude to handle it (the server auto-handles a plain accept).
    await page.click('.rail-list .qbtn[data-q="Q3"]'); await page.waitForTimeout(200);
    await page.fill("#note", "Fine for now"); await page.waitForTimeout(200);
    await page.click("#qhead"); await page.keyboard.press("a"); await page.keyboard.press("Control+Enter");
    ok("Q3 shows Sent to Claude after the page's accept", await until(() => /Sent/.test(document.querySelector('.rail-list .qbtn[data-q="Q3"]').textContent)), await rail("Q3"));
    await page.click('.rail-list .qbtn[data-q="Q1"]'); await page.waitForTimeout(200);
    await page.fill("#note", "half typed thought"); await page.waitForTimeout(200);
    ok("Q1 starts on its first recommendation with a note typed", /Every push starts it/.test(await text("#choices .choice.rec")) && (await page.inputValue("#note")) === "half typed thought");
  }
  if (PHASE === 2) {
    ok("a reply with rec shows the new recommendation in the open tab", await recIs("tagged releases"), await text("#choices .choice.rec"));
    ok("the typed note is kept when a reply changes the recommendation", (await page.inputValue("#note")) === "half typed thought");
  }
  if (PHASE === 3) {
    ok("revise --rec with --alt shows the new recommendation in the open tab", await recIs("every push on main and every tag"), await text("#choices .choice.rec"));
    ok("revise --alt shows the new alternatives in the open tab", /Only on tags/.test(await alts()), await alts());
    ok("the typed note is kept when revise changes the recommendation and alternatives", (await page.inputValue("#note")) === "half typed thought");
  }
  if (PHASE === 4) {
    ok("record-terminal shows the answer in the open tab", await until(() => /2 of 5 answered/.test(document.getElementById("meterText").textContent)), await text("#meterText"));
    ok("a handle-only apply clears Sent to Claude in the open tab", await until(() => !/Sent/.test(document.querySelector('.rail-list .qbtn[data-q="Q3"]').textContent)), await rail("Q3"));
    ok("the typed note is kept through both", (await page.inputValue("#note")) === "half typed thought");
    ok("zero console errors", errors.length === 0, errors.join(" | "));
  }
  if (PHASE === 5) { // #7757: Q3 was accepted in phase 1; tick its one commitment here, and the shell then revises only its title and short
    await page.click('.rail-list .qbtn[data-q="Q3"]'); await page.waitForTimeout(200);
    await page.click('#dscroll [data-confirm="0"]');
    const ticked = async () => ((await (await page.request.get(base + "api/state")).json()).responses.events || []).some(e => e.kind === "confirm" && e.id === "Q3" && !e.withdrawn);
    let saved = false;
    for (let i = 0; i < 30 && !(saved = await ticked()); i++) await page.waitForTimeout(200);
    ok("#7757: ticking Q3's commitment saves a confirm", saved);
    ok("#7757: Q3, accepted with every commitment ticked, wears no after-answer chip", !/after your answer/.test(await rail("Q3")), await rail("Q3"));
  }
  if (PHASE === 6) {
    ok("#7757: the title and short revise reaches the open tab", await until(() => /Dependency cache/.test(document.querySelector('.rail-list .qbtn[data-q="Q3"]').textContent)), await rail("Q3"));
    ok("#7757: a revise of only the title and short after the accept and ticks puts no after-answer chip on the card", !/after your answer/.test(await rail("Q3")), await rail("Q3"));
    await page.selectOption("#filter", "review"); await page.waitForTimeout(200);
    const review = await page.$$eval(".rail-list .qbtn", els => els.map(e => e.dataset.q));
    ok("#7757: Show: Review leaves out Q3, which the server counts closed", !review.includes("Q3"), review.join(","));
    await page.selectOption("#filter", "all"); await page.waitForTimeout(200);
    await page.click('.rail-list .qbtn[data-q="Q3"]'); await page.waitForTimeout(200);
    ok("#7757: Q3's detail shows no after-answer chip", !/after your answer/.test(await text("#dscroll")), (await text("#dscroll")).slice(0, 200));
    ok("zero console errors after the revise", errors.length === 0, errors.join(" | "));
  }
  } catch (e) { R.push("ERROR " + e.message.split("\n")[0]); }
  return R.join("\n");
}
