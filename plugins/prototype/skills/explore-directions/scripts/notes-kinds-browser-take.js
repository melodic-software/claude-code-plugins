async page => {
  // Takes four notes through the notes host: a text note on the opening set; a text note after Seed
  // 10, Clear, Reset, Seed 10; a region note made with the keyboard alone (one arrow pressed inside
  // the frame); an element note on record 57 after Seed 100.
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  try {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto("http://127.0.0.1:__PORT__/");
    await page.waitForFunction(() => !document.getElementById("pick").disabled, null, { timeout: 10000 });
    const frame = page.frames().find(f => f !== page.mainFrame());
    const inFrame = page.frameLocator("#page");
    const press = async (control) => inFrame.locator(`[data-data-control="${control}"]`).click();
    const view = () => frame.evaluate(() => [
      [...document.querySelectorAll("[data-variant]")].filter(v => !v.hidden).map(v => v.dataset.variant).join(),
      [...document.querySelectorAll('[data-variant="A"] [data-screen-state]')].filter(s => !s.hidden).map(s => s.dataset.screenState).join(),
    ].join("/"));
    const sent = async (n) => page.waitForFunction((k) => new RegExp(`Note ${k} sent`).test(document.getElementById("status").textContent), n, { timeout: 5000 });

    const select = (i) => frame.evaluate((k) => {
      const td = document.querySelectorAll('[data-variant="A"] [data-testid="shipments-row"]')[k].cells[0];
      const r = document.createRange();
      r.setStart(td.firstChild, 0);
      r.setEnd(td.firstChild, td.firstChild.length);
      getSelection().removeAllRanges();
      getSelection().addRange(r);
    }, i);

    // 0. Text on the opening set: record 2's id, before any data control; Clear and Reset follow below.
    await select(2);
    await page.click("#quote");
    await page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
    const first = await page.textContent("#picked");
    ok("the selection becomes a text note on PT-1002", /text “PT-1002”/.test(first), first);
    await page.keyboard.insertText("Is this id right?");
    await page.click("#send");
    await sent(1);

    // 1. Text: select record 12's id after Seed 10, Clear, Reset, Seed 10, then Note on selected text.
    for (const c of ["seed:10", "clear", "reset", "seed:10"]) await press(c);
    const rows = await frame.evaluate(() => document.querySelectorAll('[data-variant="A"] [data-testid="shipments-row"]').length);
    ok("Seed 10, Clear, Reset, Seed 10 leaves 15 records", rows === 15, rows);
    await select(12);
    await page.click("#quote");
    await page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
    const picked = await page.textContent("#picked");
    ok("the selection becomes a text note on PT-1012", /Selected: variant A · state default · text “PT-1012”/.test(picked), picked);
    await page.keyboard.insertText("Make this id bold.");
    await page.click("#send");
    await sent(2);

    // 2. Region with the keyboard alone: R, arrows to move (from the host page and from inside the frame),
    //    Shift+arrows to resize, Enter, Tab to Send, Enter.
    const before = await view();
    const box = () => frame.evaluate(() => {
      const o = [...document.documentElement.lastElementChild.children].find(e => e.style.outline.includes("dashed"));
      return o ? [o.style.left, o.style.top, o.style.width, o.style.height].map(parseFloat) : [];
    });
    await page.focus("#region");
    await page.keyboard.press("r");
    ok("R turns region mode on", await page.getAttribute("#region", "aria-pressed") === "true");
    for (const k of ["ArrowRight", "ArrowRight", "ArrowDown"]) await page.keyboard.press(k);
    const moved = await box();
    await inFrame.locator('[data-data-control="seed:10"]').focus();
    await page.keyboard.press("ArrowDown");
    const inFrameMove = await box();
    ok("ArrowDown inside the frame moves the region 10 pixels down", inFrameMove[1] - moved[1] === 10, `${moved} -> ${inFrameMove}`);
    ok("and does not reach the switcher's state keys", (await view()) === before, await view());
    await page.focus("#region");
    for (const k of ["Shift+ArrowRight", "Shift+ArrowRight", "Shift+ArrowDown"]) await page.keyboard.press(k);
    const sized = await box();
    ok("Shift+arrows resize the region by 20 by 10 pixels", sized[2] === 180 && sized[3] === 110, sized);
    await page.keyboard.press("Enter");
    await page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
    const marked = await page.textContent("#picked");
    ok("Enter marks the region over the records", /Marked: variant A · state default · region at/.test(marked), marked);
    await page.keyboard.insertText("Too much space between these rows.");
    await page.keyboard.press("Tab");
    await page.keyboard.press("Enter");
    await sent(3);
    ok("the arrow keys left the variant and screen state alone", (await view()) === before, await view());

    // 3. Element: record 57 after Seed 100.
    await press("seed:100");
    await page.click("#pick");
    await inFrame.locator('[data-variant="A"] [data-testid="shipments-row"] >> nth=57').locator("td").first().click();
    await page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
    const row = await page.textContent("#picked");
    ok("the pick is record 57's row", /shipments-row #58/.test(row), row);
    await page.keyboard.insertText("Why is this one green?");
    await page.click("#send");
    await sent(4);
    ok("four notes are listed", (await page.$$("#notes li")).length === 4);
  } catch (e) {
    R.push("ERROR " + String(e).split("\n")[0]);
  }
  return R.join("\n");
}
