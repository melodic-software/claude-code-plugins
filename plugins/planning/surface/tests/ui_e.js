async page => { // answer controls: radios by keyboard, a withheld question, paste routing, the focus ring, and the controls while offline or after a restart
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  const errors = [];
  page.on("console", m => { if (m.type() === "error") errors.push(m.text()); });
  page.on("pageerror", e => errors.push(String(e)));
  const base = "http://127.0.0.1:__PORT__/";
  const text = async s => (await page.textContent(s).catch(() => "")) || "";
  const until = (fn, timeout) => page.waitForFunction(fn, null, {timeout}).then(() => true).catch(() => false);
  const focused = () => page.evaluate(() => { const a = document.activeElement; return a.name === "choice" ? "radio " + a.value : a.id || a.tagName; });
  const labels = () => page.$$eval("#choices .choice b", els => els.map(e => e.textContent));
  const pick = async id => { await page.click('.rail-list .qbtn[data-q="' + id + '"]'); await page.waitForTimeout(250); };
  const nudgeVisible = () => page.evaluate(() => { Object.defineProperty(document, "visibilityState", {configurable: true, get: () => "visible"}); document.dispatchEvent(new Event("visibilitychange")); });
  try {
  await page.setViewportSize({width: 1400, height: 860});
  await page.goto(base);
  await page.waitForSelector(".qbtn", {state: "attached"});
  await page.evaluate(() => localStorage.clear());
  await page.reload(); await page.waitForSelector(".qbtn", {state: "attached"}); await page.waitForTimeout(400);

  // #7755: with nothing waiting, the Pending filter says what Pending means
  await page.selectOption("#filter", "pending"); await page.waitForTimeout(200);
  const pendingEmpty = await text("#railList");
  ok("the Pending filter's empty state says what Pending means", /No questions match this filter\. Pending means waiting on research/.test(pendingEmpty), pendingEmpty.replace(/\s+/g, " ").slice(0, 200));
  await page.selectOption("#filter", "all"); await page.waitForTimeout(200);

  // #9719: ledger drift and unticked commitments show while the interview runs
  ok("a data dir without meta.ledgerSync shows no ledger line", await page.evaluate(() => document.getElementById("ledgerLine").hidden));
  const withLedger = sync => route => route.fetch().then(async res => {
    const body = await res.json();
    body.questions.meta = Object.assign({}, body.questions.meta, {ledgerSync: sync});
    body.questions.questions.forEach(q => { if (q.id === "E1") q.commits = ["Cache the lockfile", "Prune weekly"]; });
    body.responses.responses = Object.assign({}, body.responses.responses, {E1: {decision: "accept", updatedAt: "2026-01-01T00:00:00Z", seq: 1}});
    await route.fulfill({response: res, json: body});
  });
  await page.route("**/api/state", withLedger({rev: 7, rows: ["Q2"]}));
  await nudgeVisible();
  const drifted = await until(() => /^Ledger: 1 row out of sync$/.test(document.getElementById("ledgerLine").textContent), 8000);
  ok("a ledger that disagrees on one row reads Ledger: 1 row out of sync in the header", drifted && !(await page.evaluate(() => document.getElementById("ledgerLine").hidden)), await text("#ledgerLine"));
  const chip = await text('.rail-list .qbtn[data-q="E1"] .chip.s-accept');
  ok("an accepted row with two unticked commitments reads Accepted, 2 to confirm on the rail", chip === "Accepted, 2 to confirm", chip);
  const meterTitle = await page.getAttribute("#assumeCount", "title");
  ok("the meter's to-confirm count names the accepted row and its unticked commitments", /E1 accepted, 2 to confirm/.test(meterTitle || ""), meterTitle);
  await page.unroute("**/api/state");
  await page.route("**/api/state", withLedger({rev: 8, rows: []}));
  await nudgeVisible();
  const matched = await until(() => /^Ledger in sync, rev 8$/.test(document.getElementById("ledgerLine").textContent), 8000);
  ok("a ledger that matches reads Ledger in sync, rev 8", matched, await text("#ledgerLine"));
  await page.unroute("**/api/state");
  await nudgeVisible(); await page.waitForTimeout(400);

  // arrow keys move through the Decide radios without dropping focus
  await pick("E1");
  await page.focus('#choices input[value="1"]');
  await page.keyboard.press("ArrowDown"); await page.waitForTimeout(150);
  const f2 = await focused(), a2 = await text(".choice.armed b");
  ok("ArrowDown onto Accept with note keeps focus on that radio, not the note box", f2 === "radio 2" && a2 === "Accept with note", f2 + " / " + a2);
  await page.keyboard.press("ArrowDown"); await page.waitForTimeout(150);
  const f3 = await focused(), a3 = await text(".choice.armed b");
  ok("a second ArrowDown arms the next row and keeps focus on its radio", f3 === "radio 3" && a3 === "(a)", f3 + " / " + a3);
  await page.click('#choices .choice:has(input[value="5"])'); await page.waitForTimeout(150);
  ok("a pointer pick of Own answer still focuses the note box", (await focused()) === "note", await focused());

  // the View switcher's focus ring is not clipped by its rounded frame
  await page.keyboard.press("Escape");
  await page.focus('.seg [data-view="rounds"]');
  const ring = await page.evaluate(() => { const b = document.querySelector('.seg [data-view="rounds"]'), s = getComputedStyle(b); return {visible: b.matches(":focus-visible"), offset: parseFloat(s.outlineOffset), width: parseFloat(s.outlineWidth), overflow: getComputedStyle(b.parentElement).overflow}; });
  ok("a focused View button draws its whole ring inside the clipped frame", ring.visible && ring.width > 0 && (ring.overflow !== "hidden" || ring.offset + ring.width <= 0), JSON.stringify(ring));

  // a withheld question offers nothing to accept and stays out of Accept all
  await pick("E2");
  const l2 = await labels();
  ok("a withheld question shows no Rec, Accept with note or Hedged row, and keeps Someone else decides", !l2.some(l => /^(Rec|Accept with note|Hedged)$/.test(l)) && l2.includes("Own answer") && l2.includes("Defer") && l2.includes("Someone else decides"), l2.join(", "));
  ok("its recommendation block reads Recommendation withheld", /^Recommendation withheld$/.test((await text(".blk h4")).trim()), await text(".blk h4"));
  await page.click("#qhead"); await page.keyboard.press("a"); await page.waitForTimeout(150);
  ok("key a arms nothing on a withheld question", !(await page.$(".choice.armed")));
  const all = await text('.sec[data-key="g:base"] [data-acceptall]');
  ok("Accept all counts the recommended question and leaves the withheld one out", all === "Accept all (1)", all);

  // dictation pasted while a radio has focus lands in the note box
  await pick("E1");
  await page.click('#choices .choice:has(input[value="3"])'); await page.waitForTimeout(150);
  await page.evaluate(() => { const dt = new DataTransfer(); dt.setData("text/plain", "dictated words"); document.activeElement.dispatchEvent(new ClipboardEvent("paste", {clipboardData: dt, bubbles: true, cancelable: true})); });
  await page.waitForTimeout(150);
  ok("text pasted with a radio focused goes into the note box, which takes focus", (await page.inputValue("#note")) === "dictated words" && (await focused()) === "note", (await page.inputValue("#note")) + " / " + await focused());
  await page.keyboard.press("Escape");

  // offline: nothing can be saved, so nothing invites a save; reconnecting brings the controls back
  await page.context().setOffline(true);
  await nudgeVisible();
  const off = await until(() => /^Connection lost/.test(document.getElementById("pill").textContent), 8000);
  await page.waitForTimeout(200);
  const shut = await page.evaluate(() => ({radios: [...document.querySelectorAll("#choices input")].every(r => r.disabled), save: document.querySelector("[data-save]").disabled, talk: [...document.querySelectorAll('#talkRow [data-act="rephrase"], #talkRow [data-research]')].every(b => b.disabled), hint: document.getElementById("saveHint").textContent}));
  ok("offline, the radios, Save, Rephrase and Research are disabled and the dock says why", off && shut.radios && shut.save && shut.talk && /^Not connected\. Your draft is kept/.test(shut.hint), JSON.stringify(shut));
  ok("offline, the pasted draft stays in the note box", (await page.inputValue("#note")) === "dictated words");
  await page.context().setOffline(false);
  await nudgeVisible();
  const back = await until(() => !/^Connection lost/.test(document.getElementById("pill").textContent), 10000);
  await page.waitForTimeout(200);
  const open = await page.evaluate(() => ({radios: [...document.querySelectorAll("#choices input")].every(r => !r.disabled), hint: document.getElementById("saveHint").textContent}));
  ok("back online, the radios are enabled again", back && open.radios && !/Not connected/.test(open.hint), JSON.stringify(open));

  // a restarted server answers the state poll but rejects this page's token: the controls stay shut
  await page.route("**/api/state", async route => { const res = await route.fetch(); const body = await res.json(); body.instance = "restarted-" + body.instance; await route.fulfill({response: res, json: body}); });
  await nudgeVisible();
  const restarted = await until(() => /^Server restarted/.test(document.getElementById("pill").textContent), 8000);
  await page.waitForTimeout(200);
  const gone = await page.evaluate(() => ({radios: [...document.querySelectorAll("#choices input")].every(r => r.disabled), save: document.querySelector("[data-save]").disabled, hint: document.getElementById("saveHint").textContent}));
  ok("after a server restart, the radios and Save are disabled and the dock says to reload", restarted && gone.radios && gone.save && /^The server restarted\. Reload/.test(gone.hint), JSON.stringify(gone));
  await page.unroute("**/api/state");
  } catch (e) { R.push("ERROR " + e.message.split("\n").slice(0, 3).join(" | ")); }
  await page.context().setOffline(false); // the suites after this one share the browser context
  const real = errors.filter(e => !/ERR_INTERNET_DISCONNECTED|ERR_CONNECTION_(REFUSED|RESET)/.test(e));
  ok("zero console errors (besides the network lines for the offline step)", real.length === 0, errors.join(" | "));
  return R.join("\n");
}
