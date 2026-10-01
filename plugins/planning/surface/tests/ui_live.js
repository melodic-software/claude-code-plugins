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
  const recIs = (want) => until(w => (document.querySelector(".recbox") || {}).textContent.includes(w), want);
  try {
  if (PHASE === 1) {
    await page.setViewportSize({width: 1400, height: 860});
    await page.goto(base);
    await page.waitForSelector(".qbtn", {state: "attached"});
    await page.evaluate(() => localStorage.clear());
    await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(400);
    // Q3 is accepted from the page, so its event waits for Claude to handle it.
    await page.click('.rail-list .qbtn[data-q="Q3"]'); await page.waitForTimeout(200);
    await page.click("#qhead"); await page.keyboard.press("a"); await page.keyboard.press("Control+Enter");
    ok("Q3 shows Sent to Claude after the page's accept", await until(() => /Sent/.test(document.querySelector('.rail-list .qbtn[data-q="Q3"]').textContent)), await rail("Q3"));
    await page.click('.rail-list .qbtn[data-q="Q1"]'); await page.waitForTimeout(200);
    await page.fill("#note", "half typed thought"); await page.waitForTimeout(200);
    ok("Q1 starts on its first recommendation with a note typed", /Every push starts it/.test(await text(".recbox")) && (await page.inputValue("#note")) === "half typed thought");
  }
  if (PHASE === 2) {
    ok("a reply with rec shows the new recommendation in the open tab", await recIs("tagged releases"), await text(".recbox"));
    ok("the typed note is kept when a reply changes the recommendation", (await page.inputValue("#note")) === "half typed thought");
  }
  if (PHASE === 3) {
    ok("revise --rec with --alt shows the new recommendation in the open tab", await recIs("every push on main and every tag"), await text(".recbox"));
    ok("revise --alt shows the new alternatives in the open tab", /Only on tags/.test(await alts()), await alts());
    ok("the typed note is kept when revise changes the recommendation and alternatives", (await page.inputValue("#note")) === "half typed thought");
  }
  if (PHASE === 4) {
    ok("record-terminal shows the answer in the open tab", await until(() => /2 of 5 answered/.test(document.getElementById("meterText").textContent)), await text("#meterText"));
    ok("a handle-only apply clears Sent to Claude in the open tab", await until(() => !/Sent/.test(document.querySelector('.rail-list .qbtn[data-q="Q3"]').textContent)), await rail("Q3"));
    ok("the typed note is kept through both", (await page.inputValue("#note")) === "half typed thought");
    ok("zero console errors", errors.length === 0, errors.join(" | "));
  }
  } catch (e) { R.push("ERROR " + e.message.split("\n")[0]); }
  return R.join("\n");
}
