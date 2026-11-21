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
    const hidden = await inFrame.locator("nav.vs").waitFor({ state: "hidden", timeout: 5000 }).then(() => true, () => false);
    ok("framed by the host page, the page's own switcher is hidden: the command bar steps the variants", hidden);
    const showSwitcher = async () => {
      await frame.waitForFunction(() => document.documentElement.hasAttribute("data-ui-feedback-bar"), null, { timeout: 5000 });
      await frame.evaluate(() => { document.documentElement.removeAttribute("data-ui-feedback-bar"); document.querySelector("nav.vs").dataset.position = "top"; });
    };
    await showSwitcher();
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
    ok("the toggle says the markers are hidden", (await page.getAttribute("#markers", "aria-pressed")) === "false", await page.getAttribute("#markers", "aria-pressed"));
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
    await showSwitcher();
    ok("after a reload the toggle still says the markers are hidden", (await page.getAttribute("#markers", "aria-pressed")) === "false", await page.getAttribute("#markers", "aria-pressed"));
    await sendNote(inFrame.locator('[data-variant="A"] [data-testid="shipments-parcel-row"]').nth(0), "Bolder parcel ids.", 2);
    ok("a note sent after the reload draws no marker while they are hidden", (await markers()) === "", await markers());
    await page.click("#markers");
    await marker("2");
    ok("the toggle shows the markers again after the reload, the run's earlier note's too", (await markers()) === "1,2" && (await page.getAttribute("#markers", "aria-pressed")) === "true", await markers());

    const drawn = (want) => frame.waitForFunction((want) => [...document.documentElement.lastElementChild.children].filter((e) => !e.style.outline && e.textContent).map((e) => e.textContent).join() === want, want, { timeout: 5000 }).catch(() => {});
    await page.click("#vprev");
    await drawn("1");
    ok("switching to variant C hides note 2's marker, made on variant A, and keeps note 1's, made outside every variant", (await shownVariant()) === "C" && (await markers()) === "1", `${await shownVariant()}: ${await markers()}`);
    await frame.evaluate(() => document.dispatchEvent(new CustomEvent("vs:show", { detail: { variant: "B" } })));
    await drawn("1");
    ok("variant B does not draw note 2's marker either", (await shownVariant()) === "B" && (await markers()) === "1", `${await shownVariant()}: ${await markers()}`);
    const row2 = page.locator("#notes li", { hasText: "Bolder parcel ids." });
    ok("the notes list names the variant note 2 was made on in the page's words", (await row2.locator(".view").textContent()) === "On A Ledger", await row2.locator(".view").textContent());
    await row2.click();
    await drawn("1,2");
    ok("choosing note 2 from variant B switches the mockup to variant A and draws its marker", (await shownVariant()) === "A" && (await markers()) === "1,2", `${await shownVariant()}: ${await markers()}`);
  } catch (err) {
    R.push("ERROR " + String(err && err.message || err).slice(0, 300));
  }
  return R.join("\n");
}
