async page => {
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  try {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto("http://127.0.0.1:__PORT__/");
    await page.waitForFunction(() => !document.getElementById("pick").disabled, null, { timeout: 10000 });
    const frame = page.frames().find(f => f !== page.mainFrame());
    const geom = await frame.evaluate(() => ({ pageH: document.documentElement.scrollHeight, viewH: innerHeight }));
    R.push("GEOM " + JSON.stringify(geom));
    const fb = await page.locator("#page").boundingBox();
    const status = (re) => page.waitForFunction((s) => new RegExp(s).test(document.getElementById("status").textContent), re.source, { timeout: 8000 });
    const outline = (line = "dashed") => frame.evaluate((l) => {
      const o = [...document.querySelectorAll("[data-ui-feedback-layer] > div")].find(e => e.style.outline.includes(l) && /245, 158, 11|f59e0b/.test(e.style.outline));
      return o ? { page: [o.style.left, o.style.top, o.style.width, o.style.height].map(parseFloat), scrollY } : null;
    }, line);
    const inside = (b) => fb.y + Math.max(60, Math.min(fb.height - 220, b.page[1] - b.scrollY + 30));
    const drag = async (x, y, dy) => {
      await page.mouse.move(x, y);
      await page.mouse.down();
      await page.mouse.move(x, y + dy, { steps: 6 });
      await page.mouse.up();
    };

    await page.focus("#region");
    await page.keyboard.press("r");
    ok("R turns region mode on", await page.getAttribute("#region", "aria-pressed") === "true");
    await page.mouse.move(fb.x + 100, fb.y + 120);
    await page.mouse.down();
    await page.mouse.move(fb.x + 400, fb.y + fb.height - 8, { steps: 8 });
    await page.waitForTimeout(1500);
    const scrolled = await frame.evaluate(() => scrollY);
    ok("holding the drag at the frame's bottom edge scrolls the mockup", scrolled > 0, scrolled);
    await page.mouse.up();
    await page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
    ok("the region's editor offers Move or resize", await page.isVisible("#reshape"));

    const held = await outline("solid");
    await page.click("#reshape");
    const editing = await outline();
    ok("the editor's Move or resize starts region mode at the draft's box", editing !== null && Math.abs(editing.page[1] - held.page[1]) < 1, JSON.stringify([held, editing]));
    await drag(fb.x + editing.page[0] + editing.page[2] / 2, inside(editing), 100);
    await status(/The region moved/);
    const moved = await outline("solid");
    ok("the draft's region moved 100 pixels down, the editor still open", Math.abs(moved.page[1] - held.page[1] - 100) < 1 && await page.isVisible("#composer"), JSON.stringify([held.page, moved.page]));
    R.push("DRAFT " + JSON.stringify(moved.page));
    await page.keyboard.insertText("All of these candidates.");
    await page.click("#send");
    await status(/Note 1 sent/);

    await page.click('[data-key^="reshape-"]');
    ok("Move or resize turns region mode on", await page.getAttribute("#region", "aria-pressed") === "true");
    const seeded = await outline();
    ok("region mode starts at the sent note's box", seeded !== null, JSON.stringify(seeded));
    R.push("SEEDED " + JSON.stringify(seeded.page));
    await drag(fb.x + seeded.page[0] + seeded.page[2] / 2, inside(seeded), 150);
    await status(/Note 1's region moved/);
    ok("the moved note keeps one row", (await page.$$("#notes li")).length === 1);

    await page.focus('[data-key^="reshape-"]');
    await page.keyboard.press("Enter");
    ok("Enter on Move or resize turns region mode on", await page.getAttribute("#region", "aria-pressed") === "true");
    for (const k of ["Shift+ArrowDown", "Shift+ArrowDown", "Enter"]) await page.keyboard.press(k);
    await status(/Note 1's region moved/);
  } catch (e) {
    R.push("ERROR " + String(e).split("\n")[0]);
  }
  return R.join("\n");
}
