async page => {
  // The same mockup opened alone from file://: no host page, so controls.js draws its own panel
  // from the same manifest, top-right, and the person can still set, copy and reset the controls.
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + JSON.stringify(detail) + "]" : ""));
  try {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto("__FILE__");
    const panel = page.locator('aside[aria-label="Controls"][data-harness-chrome]');
    await panel.waitFor({ timeout: 5000 });
    const box = await panel.boundingBox();
    ok("the page draws its own Controls panel in the top-right corner", box.x + box.width > 1280 - 40 && box.y < 40, box);
    ok("it lists the manifest's controls", await panel.locator(".uifc-row").count() === 5);
    const css = (n) => page.evaluate((x) => getComputedStyle(document.documentElement).getPropertyValue(x).trim(), n);
    await page.getByLabel("Card gap", { exact: true }).fill("30");
    ok("a control writes its CSS variable and shows its value", (await css("--card-gap")) === "30px"
      && (await panel.locator(".uifc-row", { has: page.getByLabel("Card gap", { exact: true }) }).locator("output").textContent()) === "30px");
    await panel.getByRole("button", { name: "Copy config" }).click();
    ok("Copy config shows the config line", (await panel.locator("p + output").textContent()).startsWith("card-gap: 30px · accent: #0d9488"));
    await panel.getByRole("button", { name: "Reset controls" }).click();
    ok("Reset controls restores the default", (await css("--card-gap")) === "12px" && (await page.getByLabel("Card gap", { exact: true }).inputValue()) === "12");
    ok("the panel carries no test id, so the copy-out test-id list is unchanged", await panel.locator("[data-testid]").count() === 0);
  } catch (e) {
    R.push("ERROR " + String(e).split("\n")[0]);
  }
  return R.join("\n");
}
