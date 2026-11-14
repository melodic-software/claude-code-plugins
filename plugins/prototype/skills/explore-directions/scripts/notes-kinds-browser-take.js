async page => {
  // Takes three notes through the notes host: a text note after Seed 10, Clear, Reset, Seed 10; a
  // region note made with the keyboard alone; an element note on record 57 after Seed 100.
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

    // 1. Text: select record 12's id after Seed 10, Clear, Reset, Seed 10, then Note on selected text.
    for (const c of ["seed:10", "clear", "reset", "seed:10"]) await press(c);
    const rows = await frame.evaluate(() => document.querySelectorAll('[data-variant="A"] [data-testid="shipments-row"]').length);
    ok("Seed 10, Clear, Reset, Seed 10 leaves 15 records", rows === 15, rows);
    await frame.evaluate(() => {
      const td = document.querySelectorAll('[data-variant="A"] [data-testid="shipments-row"]')[12].cells[0];
      const r = document.createRange();
      r.setStart(td.firstChild, 0);
      r.setEnd(td.firstChild, td.firstChild.length);
      getSelection().removeAllRanges();
      getSelection().addRange(r);
    });
    await page.click("#quote");
    await page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
    const picked = await page.textContent("#picked");
    ok("the selection becomes a text note on PT-1012", /Selected: variant A · state default · text “PT-1012”/.test(picked), picked);
    await page.keyboard.insertText("Make this id bold.");
    await page.click("#send");
    await sent(1);

    // 2. Region with the keyboard alone: R, arrows to move, Shift+arrows to resize, Enter, Tab to Send, Enter.
    const before = await view();
    await page.focus("#region");
    await page.keyboard.press("r");
    ok("R turns region mode on", await page.getAttribute("#region", "aria-pressed") === "true");
    for (const k of ["ArrowRight", "ArrowRight", "ArrowDown", "Shift+ArrowRight", "Shift+ArrowRight", "Shift+ArrowDown"]) await page.keyboard.press(k);
    const box = await frame.evaluate(() => {
      const o = [...document.documentElement.lastElementChild.children].find(e => e.style.outline.includes("dashed"));
      return o ? [parseFloat(o.style.width), parseFloat(o.style.height)].join("x") : "none";
    });
    ok("Shift+arrows resize the region by 20 by 10 pixels", box === "180x110", box);
    await page.keyboard.press("Enter");
    await page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
    const marked = await page.textContent("#picked");
    ok("Enter marks the region over the records", /Marked: variant A · state default · region at/.test(marked), marked);
    await page.keyboard.insertText("Too much space between these rows.");
    await page.keyboard.press("Tab");
    await page.keyboard.press("Enter");
    await sent(2);
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
    await sent(3);
    ok("three notes are listed", (await page.$$("#notes li")).length === 3);
  } catch (e) {
    R.push("ERROR " + String(e).split("\n")[0]);
  }
  return R.join("\n");
}
