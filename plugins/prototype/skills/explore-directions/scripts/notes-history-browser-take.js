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
    const ROW = '[data-variant="A"] [data-testid="shipments-parcel-row"]', CARD = '[data-variant="B"] [data-testid="shipments-parcel-card"]';
    const XSS = '<img src=x onerror="window.__xss=1">';
    const shownVariant = () => frame.evaluate(() => [...document.querySelectorAll("[data-variant]")].find((v) => !v.hidden)?.dataset.variant);
    const box = (which, sel) => frame.evaluate(([which, sel]) => {
      const o = [...(document.querySelector("[data-ui-feedback-layer]")?.children ?? [])].find((e) => e.dataset.note === which);
      if (!o) return { drawn: false };
      const b = o.getBoundingClientRect(), r = document.querySelector(sel).getBoundingClientRect();
      const cx = b.left + b.width / 2, cy = b.top + b.height / 2;
      return { drawn: true, on: b.width > 0 && b.height > 0 && cx > r.left && cx < r.right && cy > r.top && cy < r.bottom
        && b.left >= r.left - 3 && b.top >= r.top - 3 && b.right <= r.right + 3 && b.bottom <= r.bottom + 3 };
    }, [which, sel]);
    const until = async (read, want) => { for (let i = 0; i < 50 && !want(await read()); i++) await page.waitForTimeout(100); };
    const sendNote = async (target, words, seq) => {
      await page.click("#pick");
      await target.click();
      await page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
      await page.keyboard.insertText(words);
      await page.click("#send");
      await page.waitForFunction((seq) => new RegExp(`Note ${seq} sent`).test(document.getElementById("status").textContent), seq, { timeout: 5000 });
    };

    await sendNote(inFrame.locator(ROW).nth(0), "Bolder parcel ids.", 1);
    await inFrame.locator('nav.vs [aria-label="Next variant"]').click();
    await frame.waitForFunction(() => !document.querySelector('[data-variant="B"]').hidden, null, { timeout: 5000 });
    await sendNote(inFrame.locator(CARD).nth(0), `${XSS}Cards need dates first.`, 2);

    await page.reload();
    frame = await loaded();
    const rows = page.locator("#notes li");
    await page.waitForFunction(() => document.querySelectorAll("#notes li").length === 2, null, { timeout: 5000 }).catch(() => {});
    const listed = await rows.allTextContents();
    ok("after a reload both notes are listed, oldest first, numbered as their markers",
      listed.length === 2 && listed[0].startsWith("#1") && listed[0].includes("Bolder parcel ids.") && listed[1].startsWith("#2"), JSON.stringify(listed));
    ok("a note's markup is listed as text and makes no element",
      listed[1]?.includes(`${XSS}Cards need dates first.`) && (await page.$$("#notes img")).length === 0 && (await page.evaluate(() => window.__xss)) === undefined);
    await frame.waitForFunction(() => ["1", "2"].every((n) => [...document.querySelector("[data-ui-feedback-layer]").children].some((e) => e.textContent === n)), null, { timeout: 5000 }).catch(() => {});
    ok("both notes' markers are drawn again after the reload", (await frame.evaluate(() => [...document.querySelector("[data-ui-feedback-layer]").children].filter((e) => e.textContent).map((e) => e.textContent).join())) === "1,2");
    ok("the reload starts on variant A", (await shownVariant()) === "A");

    await rows.nth(0).hover();
    await until(() => box("hover", ROW), (b) => b.drawn);
    let b = await box("hover", ROW);
    ok("hovering row 1 draws note 1's box on the row it was taken on", b.drawn && b.on, JSON.stringify(b));
    await page.hover("h1");
    await until(() => box("hover", ROW), (b) => !b.drawn);
    ok("moving off the row clears its box", !(await box("hover", ROW)).drawn);

    await rows.nth(1).click();
    await frame.waitForFunction(() => !document.querySelector('[data-variant="B"]').hidden, null, { timeout: 5000 }).catch(() => {});
    ok("clicking row 2 restores the variant note 2 was taken on", (await shownVariant()) === "B", await shownVariant());
    b = await box("selected", CARD);
    ok("clicking row 2 draws note 2's box on its card", b.drawn && b.on, JSON.stringify(b));
    ok("row 2 shows as selected", (await rows.nth(1).getAttribute("aria-current")) === "true");
    await page.hover("h1");
    ok("the clicked note's box stays drawn after the pointer leaves its row", (await box("selected", CARD)).drawn);

    await inFrame.locator(CARD).nth(2).click();
    await until(() => box("selected", CARD), (b) => !b.drawn);
    ok("a click elsewhere on the mockup clears the clicked note's box", !(await box("selected", CARD)).drawn);
    ok("and the row is no longer selected", (await rows.nth(1).getAttribute("aria-current")) === null);

    await rows.nth(1).click();
    await until(() => box("selected", CARD), (b) => b.drawn);
    await page.click("h1");
    await until(() => box("selected", CARD), (b) => !b.drawn);
    ok("a click elsewhere on the host page clears it too", !(await box("selected", CARD)).drawn && (await rows.nth(1).getAttribute("aria-current")) === null);

    const at = await frame.evaluate(() => {
      const m = [...document.querySelector("[data-ui-feedback-layer]").children].find((e) => e.textContent === "1").getBoundingClientRect();
      return { x: m.left + m.width / 2, y: m.top + m.height / 2 };
    });
    const f = await page.locator("#page").boundingBox();
    await page.mouse.click(f.x + at.x, f.y + at.y);
    await until(() => rows.nth(0).getAttribute("aria-current"), (v) => v === "true");
    ok("clicking marker 1 selects row 1, as clicking the row does", (await rows.nth(0).getAttribute("aria-current")) === "true");
    ok("and restores note 1's variant with its box drawn", (await shownVariant()) === "A" && (await box("selected", ROW)).on, await shownVariant());
  } catch (err) {
    R.push("ERROR " + String(err && err.message || err).slice(0, 300));
  }
  return R.join("\n");
}
