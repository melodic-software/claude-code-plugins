async page => {
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  try {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto("http://127.0.0.1:__PORT__/");
    const loaded = async () => {
      await page.waitForFunction(() => !document.getElementById("pick").disabled, null, { timeout: 10000 });
      return page.frames().find((f) => f !== page.mainFrame());
    };
    let frame = await loaded();
    const inFrame = page.frameLocator("#page");
    const ROW = '[data-variant="A"] [data-testid="shipments-parcel-row"]';
    const said = (re) => page.waitForFunction((re) => new RegExp(re).test(document.getElementById("status").textContent), re, { timeout: 5000 });
    const markers = () => frame.evaluate(() => [...(document.querySelector("[data-ui-feedback-layer]")?.children ?? [])].filter((e) => e.textContent).map((e) => e.textContent).join());
    const rows = page.locator("#notes li");
    for (const [i, words] of [[0, "Bolder parcel ids."], [1, "Dates first."]]) {
      await page.click("#pick");
      await inFrame.locator(ROW).nth(i).click();
      await page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
      await page.keyboard.insertText(words);
      await page.click("#send");
      await said(`Note ${i + 1} sent`);
    }

    await rows.nth(0).locator(".text").click();
    await rows.nth(0).locator('[data-key^="edit-"]').click();
    await page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
    ok("Edit on sent note 1 opens the editor on its text, with no Save draft",
      (await page.textContent("#composer-label")) === "Edit note 1" && (await page.inputValue("#text")) === "Bolder parcel ids." && await page.isHidden("#save"));
    await page.fill("#text", "Bolder and larger parcel ids.");
    await page.click("#send");
    await said("Note 1 edited");
    ok("the edited note keeps its number and shows its new text, with no second row",
      (await rows.count()) === 2 && (await rows.nth(0).textContent()).startsWith("1") && (await rows.nth(0).locator(".text").textContent()) === "Bolder and larger parcel ids.");

    await page.reload();
    frame = await loaded();
    await page.waitForFunction(() => document.querySelectorAll("#notes li").length === 2, null, { timeout: 5000 }).catch(() => {});
    ok("after a reload note 1 is listed with its edited text", (await rows.nth(0).locator(".text").textContent()) === "Bolder and larger parcel ids.");

    await rows.nth(1).locator(".text").click();
    await rows.nth(1).locator('[data-key^="withdraw-"]').click();
    await said("Note 2 withdrawn");
    ok("a withdrawn note is listed as withdrawn, not pending, with no actions",
      (await rows.nth(1).locator(".state").textContent()) === "Withdrawn" && (await rows.nth(1).locator("button").count()) === 0);
    ok("note 1 is still pending", (await rows.nth(0).locator(".state").textContent()) !== "Withdrawn");
    for (let i = 0; i < 50 && (await markers()) !== "1"; i++) await page.waitForTimeout(100);
    ok("the withdrawn note draws no marker", (await markers()) === "1", await markers());

    await page.reload();
    frame = await loaded();
    await page.waitForFunction(() => document.querySelectorAll("#notes li .state")[1]?.textContent === "Withdrawn", null, { timeout: 5000 }).catch(() => {});
    ok("after a reload note 2 is still withdrawn", (await rows.nth(1).locator(".state").textContent()) === "Withdrawn");
  } catch (err) {
    R.push("ERROR " + String(err && err.message || err).slice(0, 300));
  }
  return R.join("\n");
}
