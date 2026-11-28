async page => {
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + JSON.stringify(detail) + "]" : ""));
  try {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto("__FILE__");
    const panel = page.locator('aside[aria-label="Controls"][data-harness-chrome]');
    await panel.waitFor({ timeout: 5000 });
    const box = await panel.boundingBox();
    ok("the panel sits in the top-left corner", box.x < 40 && box.y < 40 && box.x + box.width < 1280 - 40, box);
  } catch (e) {
    R.push("ERROR " + String(e).split("\n")[0]);
  }
  return R.join("\n");
}
