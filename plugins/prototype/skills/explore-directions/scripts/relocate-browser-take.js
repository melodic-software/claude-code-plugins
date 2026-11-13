async page => {
  // Takes one note through the notes host: variant B, state empty, worst content, on the worst set's
  // call to action, which the switcher partly covers.
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  try {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto("http://127.0.0.1:__PORT__/");
    await page.waitForFunction(() => !document.getElementById("pick").disabled, null, { timeout: 10000 });
    const frame = page.frames().find(f => f !== page.mainFrame());
    const inFrame = page.frameLocator("#page");
    await inFrame.locator("header").click();
    await page.keyboard.press("2");
    await page.keyboard.press("ArrowDown");
    await page.keyboard.press("w");
    const view = await frame.evaluate(() => [
      [...document.querySelectorAll("[data-variant]")].filter(v => !v.hidden).map(v => v.dataset.variant).join(),
      [...document.querySelectorAll('[data-variant="B"] [data-screen-state]')].filter(s => !s.hidden).map(s => s.dataset.screenState).join(),
      document.documentElement.dataset.vsContent,
    ].join("/"));
    ok("the person's view is B / empty / worst", view === "B/empty/worst", view);
    await page.click("#pick");
    await inFrame.locator('[data-variant="B"] [data-screen-state="empty"] [data-content-set="worst"] [data-testid="shipments-empty-cta"]').click({ position: { x: 12, y: 12 } });
    await page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
    const picked = await page.textContent("#picked");
    ok("the pick is the worst set's call to action, the second with its test id", /shipments-empty-cta #2/.test(picked), picked);
    // Text shaped to break out of a script literal: the relocation script must still carry it as data.
    await page.keyboard.insertText("Shorter. x\"); throw 1; //${1}$&$' ` </script>");
    await page.click("#send");
    await page.waitForFunction(() => /sent/.test(document.getElementById("status").textContent), null, { timeout: 5000 });
    ok("the note is sent", (await page.$$("#notes li")).length === 1);
  } catch (e) {
    R.push("ERROR " + String(e).split("\n")[0]);
  }
  return R.join("\n");
}
