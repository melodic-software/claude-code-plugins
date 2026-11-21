async page => {
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  try {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto("http://127.0.0.1:__PORT__/");
    await page.waitForFunction(() => !document.getElementById("pick").disabled, null, { timeout: 10000 });
    const frame = page.frames().find((f) => f !== page.mainFrame());
    const inFrame = page.frameLocator("#page");
    const row = (i) => inFrame.locator('[data-variant="A"] [data-testid="shipments-parcel-row"]').nth(i);
    const drawn = () => frame.evaluate(() => {
      const layer = document.documentElement.lastElementChild;
      const kids = [...layer.children];
      return { held: kids.filter((e) => e.style.outline.includes("solid")).length };
    });
    const opened = () => page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
    const closed = () => page.waitForSelector("#composer", { state: "hidden", timeout: 5000 });

    await frame.evaluate(() => {
      const td = document.querySelector('[data-variant="A"] [data-testid="shipments-parcel-row"]').cells[0];
      const r = document.createRange();
      r.selectNodeContents(td);
      getSelection().removeAllRanges();
      getSelection().addRange(r);
    });
    await page.click("#quote");
    await opened();
    let d = await drawn();
    ok("a text pick made first on a fresh page stays drawn while its note is written", d.held === 1, JSON.stringify(d));
    await page.click("#cancel");
    await closed();
    d = await drawn();
    ok("cancel clears the text pick's outline", d.held === 0, JSON.stringify(d));

    await page.click("#pick");
    await row(1).click();
    await opened();
    d = await drawn();
    ok("an element pick stays outlined while its note is written", d.held === 1, JSON.stringify(d));
    const before = await frame.evaluate(() => getSelection().toString());
    await row(2).click({ force: true });
    const after = await frame.evaluate(() => getSelection().toString());
    ok("a click on the page under a held pick changes nothing there", before === after && (await page.isVisible("#composer")), after);
    await page.click("#cancel");
    await closed();
    d = await drawn();
    ok("cancel clears the element's outline", d.held === 0, JSON.stringify(d));

    await page.click("#region");
    await page.keyboard.press("Enter");
    await opened();
    d = await drawn();
    ok("a region pick stays drawn while its note is written", d.held === 1, JSON.stringify(d));
    await page.keyboard.insertText("Tighten these rows.");
    await page.click("#send");
    await closed();
    await page.waitForFunction(() => /Note 1 sent/.test(document.getElementById("status").textContent), null, { timeout: 5000 });
    d = await drawn();
    ok("after send the region's outline is gone", d.held === 0, JSON.stringify(d));
  } catch (err) {
    R.push("ERROR " + String(err && err.message || err).slice(0, 300));
  }
  return R.join("\n");
}
