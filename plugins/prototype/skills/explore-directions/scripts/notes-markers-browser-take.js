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
    const markers = () => frame.evaluate(() => [...document.documentElement.lastElementChild.children].filter((e) => !e.style.outline && e.textContent).map((e) => e.textContent).join());
    const marker = (n) => frame.waitForFunction((n) => [...document.documentElement.lastElementChild.children].some((e) => e.textContent === n), n, { timeout: 5000 });
    const released = () => frame.waitForFunction(() => ![...document.documentElement.lastElementChild.children].some((e) => e.style.outline.includes("solid")), null, { timeout: 5000 });
    const shownVariant =() => frame.evaluate(() => [...document.querySelectorAll("[data-variant]")].find((v) => !v.hidden)?.dataset.variant);
    const sendNote = async (target, words, seq) => {
      await page.click("#pick");
      await target.click();
      await page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
      await page.keyboard.insertText(words);
      await page.click("#send");
      await page.waitForFunction((seq) => new RegExp(`Note ${seq} sent`).test(document.getElementById("status").textContent), seq, { timeout: 5000 });
      await released();
    };

    await sendNote(inFrame.locator('nav.vs [aria-label="Next variant"]'), "Make this arrow bigger.", 1);
    await marker("1");
    const at = await frame.evaluate(() => {
      const b = [...document.documentElement.lastElementChild.children].find((e) => e.textContent === "1").getBoundingClientRect();
      const n = document.querySelector('nav.vs [aria-label="Next variant"]').getBoundingClientRect();
      const x = (Math.max(b.left, n.left) + Math.min(b.right, n.right)) / 2, y = (Math.max(b.top, n.top) + Math.min(b.bottom, n.bottom)) / 2;
      const inside = (r) => x > r.left && x < r.right && y > r.top && y < r.bottom;
      return { x, y, under: inside(b) && inside(n) && !!document.elementFromPoint(x, y)?.closest('[aria-label="Next variant"]') };
    });
    ok("note 1's marker sits over the page's Next variant button", at.under, JSON.stringify(at));

    await page.click("#pick");
    await page.keyboard.press("m");
    await frame.waitForFunction(() => ![...document.documentElement.lastElementChild.children].some((e) => e.textContent === "1"), null, { timeout: 5000 }).catch(() => {});
    ok("M hides the markers", (await markers()) === "", await markers());
    ok("hiding the markers leaves the element pick on", (await page.getAttribute("#pick", "aria-pressed")) === "true");
    ok("the toggle says the markers are hidden", (await page.textContent("#markers")) === "Show markers (M)", await page.textContent("#markers"));
    await page.click("#pick");
    ok("ending the pick leaves the markers hidden", (await page.getAttribute("#pick", "aria-pressed")) === "false" && (await markers()) === "");

    const before = await shownVariant();
    const frameBox = await page.locator("#page").boundingBox();
    await page.mouse.click(frameBox.x + at.x, frameBox.y + at.y);
    await frame.waitForFunction((v) => [...document.querySelectorAll("[data-variant]")].find((e) => !e.hidden)?.dataset.variant !== v, before, { timeout: 5000 }).catch(() => {});
    const after = await shownVariant();
    ok("a click where the marker was reaches the page: Next variant switches the variant", before === "A" && after === "B", `${before} -> ${after}`);

    await page.reload();
    frame = await loaded();
    ok("after a reload the toggle still says the markers are hidden", (await page.textContent("#markers")) === "Show markers (M)", await page.textContent("#markers"));
    await sendNote(inFrame.locator('[data-variant="A"] [data-testid="shipments-parcel-row"]').nth(0), "Bolder parcel ids.", 2);
    ok("a note sent after the reload draws no marker while they are hidden", (await markers()) === "", await markers());
    await page.click("#markers");
    await marker("2");
    ok("the toggle shows the markers again after the reload, the run's earlier note's too", (await markers()) === "1,2" && (await page.textContent("#markers")) === "Hide markers (M)", await markers());
  } catch (err) {
    R.push("ERROR " + String(err && err.message || err).slice(0, 300));
  }
  return R.join("\n");
}
