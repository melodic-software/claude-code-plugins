async page => {
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + JSON.stringify(detail) + "]" : ""));
  const lines = () => page.evaluate(() => [...document.querySelectorAll(".vs .vs-item")]
    .filter((b) => b.offsetParent !== null)
    .map((b) => {
      const r = document.createRange();
      r.selectNodeContents(b);
      const tops = new Set([...r.getClientRects()].map((x) => Math.round(x.top)));
      return { label: b.textContent, lines: tops.size };
    }));
  const tip = (sel) => page.evaluate((s) => {
    const st = getComputedStyle(document.querySelector(s), "::after");
    return { content: st.content, shown: st.content !== "none" && st.display !== "none" && st.visibility !== "hidden" && Number(st.opacity) > 0 };
  }, sel);
  try {
    await page.goto("__FILE__");
    await page.locator(".vs .vs-replay").waitFor({ state: "visible", timeout: 5000 });
    for (const width of [1024, 1440]) {
      await page.setViewportSize({ width, height: 800 });
      const all = await lines();
      const wrapped = all.filter((x) => x.lines !== 1);
      ok(`at ${width}px every switcher item, motion controls shown, sits on one line`, all.length === 10 && wrapped.length === 0, wrapped.length ? wrapped : all.length);
      const bar = await page.evaluate(() => {
        const n = document.querySelector(".vs"), b = n.getBoundingClientRect();
        return { overflow: n.scrollWidth - n.clientWidth, center: Math.round(b.left + b.width / 2), right: Math.round(b.right) };
      });
      ok(`at ${width}px the bar holds its items without overflow, centered`, bar.overflow <= 0 && Math.abs(bar.center - width / 2) <= 1 && bar.right <= width, bar);
    }

    for (const [sel, label] of [[".vs-speed", "Motion speed (S)"], [".vs-replay", "Replay the variant (R)"]]) {
      ok(`the ${label} tooltip is hidden at rest`, !(await tip(sel)).shown);
      for (let i = 0; i < 20 && !(await page.evaluate((s) => document.activeElement === document.querySelector(s), sel)); i++) await page.keyboard.press("Tab");
      const focused = await tip(sel);
      ok(`keyboard focus on the ${label} button shows "${label}"`, focused.shown && focused.content === `"${label}"`, focused);
      await page.evaluate(() => document.activeElement.blur());
      await page.locator(sel).hover();
      const hovered = await tip(sel);
      ok(`hovering the ${label} button shows "${label}"`, hovered.shown && hovered.content === `"${label}"`, hovered);
      await page.mouse.move(0, 0);
    }

    await page.keyboard.press("s");
    ok("S still steps the motion speed to 0.5×", (await page.locator(".vs-speed").textContent()) === "0.5×");
    await page.keyboard.press("2");
    ok("2 still switches to the second variant", (await page.locator(".vs-item[aria-current='true']").textContent()) === "B Split board with long label");
  } catch (e) {
    R.push("ERROR " + String(e).split("\n")[0]);
  }
  return R.join("\n");
}
