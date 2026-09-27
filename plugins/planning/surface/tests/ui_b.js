async page => {
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  const errors = [];
  page.on("console", m => { if (m.type() === "error") errors.push(m.text()); });
  page.on("pageerror", e => errors.push(String(e)));
  const base = "http://127.0.0.1:__PORT__/";
  const events = async () => (await (await page.request.get(base + "api/state")).json()).responses.events;
  const sel = async () => page.evaluate(() => (document.querySelector('.qbtn[aria-current="true"]') || {}).dataset?.q || (document.querySelector('.sumbtn[aria-current="true"]') ? "summary" : null));
  try {
  await page.waitForTimeout(800); // SSE brings the external revise
  ok("revised text is on screen", /Changed by Claude/.test(await page.textContent(".recbox")));
  const n0 = (await events()).length;
  await page.keyboard.press("Control+Enter"); await page.waitForTimeout(600);
  ok("stale contentRev gets a 409 and nothing is saved", (await events()).length === n0 && !(await page.$eval("#conflict", el => el.hidden)));
  ok("diff shows del and ins", !!(await page.$("#conflict del")) && !!(await page.$("#conflict ins")), await page.$eval("#conflict", el => el.innerText.replace(/\s+/g, " ").slice(0, 160)));
  ok("note kept during conflict", (await page.inputValue("#note")) === "Keep this note");
  await page.click('[data-conflict="mine"]'); await page.waitForTimeout(800);
  const ev = await events();
  ok("Keep mine saves with the new contentRev", ev.length === n0 + 1 && ev[ev.length - 1].id === "N2" && ev[ev.length - 1].text === "Keep this note");
  ok("AC15: an Accept with a new note stays on N2", await sel() === "N2" && /Accept with note/.test(await page.textContent("#toast")), await sel() + " " + await page.textContent("#toast"));
  ok("group unlocks when its prerequisite group is answered", !(await page.$('.sec[data-key="g:g10"] .lock')));

  // status while Claude has events: deliver them with one wait, like the watcher
  const token = await page.$eval('meta[name="interview-token"]', m => m.content);
  await page.request.get(base + "api/wait?after=" + (ev[ev.length - 1].seq - 1) + "&timeout=2", {headers: {"X-Interview-Token": token}});
  await page.waitForTimeout(900);
  ok("Claude line reads 'Claude is working on ...'", /^Claude is working on /.test(await page.textContent("#claudeLine")), await page.textContent("#claudeLine"));
  if (await page.$eval('.qbtn[data-q="N2"]', el => !el.offsetParent)) await page.click('.sec[data-key="g:g9"] .sec-h');
  await page.click('.qbtn[data-q="N2"]'); await page.waitForTimeout(200);
  ok("receipt shows Saved and Delivered with times", /Saved \d.*Delivered \d/.test(await page.textContent("#cur")), await page.textContent("#cur"));
  await page.click('.qbtn[data-q="N3"]'); await page.waitForTimeout(200);

  // Accept all on the group with N3 (opened)
  const btn = await page.$('[data-acceptall="g10"]');
  ok("Accept all offered for opened questions", !!btn, btn ? await btn.textContent() : "");
  await btn.click(); await page.waitForTimeout(200);
  ok("confirm dialog lists the questions", await page.evaluate(() => document.getElementById("dlg").open && /N3/.test(document.getElementById("dlgBody").innerText)));
  await page.click("#dlgOk"); await page.waitForTimeout(900);
  const ev2 = await events();
  ok("Accept all saved an accept for N3", ev2[ev2.length - 1].id === "N3" && ev2[ev2.length - 1].kind === "accept");

  // completion screen
  await page.keyboard.press("w"); await page.waitForTimeout(300);
  ok("completion screen when all are answered", /All answered/.test(await page.textContent(".done-h")), await page.textContent(".done-h"));
  ok("answer pane hidden on the summary", await page.$eval("#answer", el => el.hidden));
  const loose = await page.$$eval("ul.loose li", els => els.map(e => e.innerText.replace(/\s+/g, " ")));
  ok("loose ends listed (mid-sentence notes, unanswered replies)", loose.some(t => /mid-sentence/.test(t)), loose.slice(0, 4).join(" | "));
  ok("decision summary table", (await page.$$("table.sum tbody tr")).length >= 18);
  ok("what Claude does next", /What Claude does next/.test(await page.textContent("#dscroll")));
  const n3 = (await events()).length;
  await page.click("[data-wrapup]"); await page.waitForTimeout(700);
  const ev3 = await events();
  ok("Wrap up posts one wrapup event", ev3.length === n3 + 1 && ev3[ev3.length - 1].kind === "wrapup");
  const real = errors.filter(e => !/status of 409 \(Conflict\)/.test(e));
  ok("zero console errors (besides the browser's network line for the intended 409)", real.length === 0, errors.join(" | "));
  } catch (e) { R.push("ERROR " + e.message.split("\n")[0]); }
  return R.join("\n");
}
