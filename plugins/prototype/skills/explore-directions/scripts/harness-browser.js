async page => {
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  const errors = [];
  page.on("pageerror", e => errors.push(String(e)));
  const base = "http://127.0.0.1:__PORT__/";
  try {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto(base);
    await page.waitForFunction(() => !document.getElementById("pick").disabled, null, { timeout: 10000 });
    const frame = page.frames().find(f => f !== page.mainFrame());
    const inFrame = page.frameLocator("#page");
    const shown = () => frame.evaluate(() => [...document.querySelectorAll("[data-variant]")].filter(v => !v.hidden).map(v => v.dataset.variant).join());
    const clicks = () => frame.evaluate(() => window.probe.clicks);

    ok("the framed page has an opaque origin", await frame.evaluate(() => String(window.origin)) === "null");
    ok("the frame is sandboxed with scripts only", await page.getAttribute("#page", "sandbox") === "allow-scripts");
    ok("the switcher runs in the frame and shows A", await shown() === "A", await shown());
    await inFrame.locator("header").click();
    await page.keyboard.press("2");
    ok("with focus in the frame, key 2 switches to B", await shown() === "B", await shown());
    await page.keyboard.press("ArrowRight");
    await page.keyboard.press("ArrowLeft");
    ok("the arrow keys step and come back to B", await shown() === "B", await shown());

    await page.click("#pick");
    ok("Pick turns pick mode on", await page.getAttribute("#pick", "aria-pressed") === "true");
    await inFrame.locator('[data-variant="B"] [data-testid="shipments-parcel-card"]').nth(1).click();
    ok("in pick mode the click does not reach the page", await clicks() === 0, await clicks());
    await page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
    const picked = await page.textContent("#picked");
    ok("the pick names the variant, the test id and its index", /variant B/.test(picked) && /shipments-parcel-card #2/.test(picked), picked);
    ok("the note box has focus", await page.evaluate(() => document.activeElement.id) === "text");
    await page.keyboard.type("1 make the second card taller; 3 rows of text fit");
    ok("typing 1 and 3 in the note does not switch variants", await shown() === "B", await shown());
    await page.click("#send");
    await page.waitForFunction(() => /sent/.test(document.getElementById("status").textContent), null, { timeout: 5000 });
    ok("the sent note is listed", (await page.$$("#notes li")).length === 1);
    ok("pick mode is off after the pick", await page.getAttribute("#pick", "aria-pressed") === "false");
    await inFrame.locator('[data-variant="B"] [data-testid="shipments-parcel-card"]').nth(1).click();
    ok("out of pick mode the click reaches the page", await clicks() === 1, await clicks());

    await page.click("#pick");
    await page.keyboard.press("Escape");
    ok("Esc in the host ends pick mode", await page.getAttribute("#pick", "aria-pressed") === "false");
    await page.click("#pick");
    await frame.evaluate(() => window.focus());
    await page.keyboard.press("Escape");
    ok("Esc in the frame ends pick mode", await page.getAttribute("#pick", "aria-pressed") === "false");

    // A test id on the variant itself: an element inside it with no closer test id is that test id's first match.
    await frame.evaluate(() => {
      const v = document.querySelector('[data-variant="B"]'), p = document.createElement("p");
      v.dataset.testid = "shipments-cards";
      p.id = "plain";
      p.textContent = "no test id here";
      v.append(p);
    });
    await page.click("#pick");
    await inFrame.locator("#plain").click();
    await page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
    const scoped = await page.textContent("#picked");
    ok("a test id on the variant itself is its first match", /shipments-cards #1(?!\d)/.test(scoped) && !/NaN/.test(scoped), scoped);
    await page.click("#cancel");
    ok("no page error", errors.length === 0, errors.join(" | "));
  } catch (e) {
    R.push("ERROR " + String(e).split("\n")[0]);
  }
  return R.join("\n");
}
