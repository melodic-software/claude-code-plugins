async page => {
  // A manifest the Controls tab refuses whole (one that is not JSON, or whose control cannot hold its
  // default) says why, renders no manifest control, keeps the data controls, and the page opened
  // alone draws no panel from it either.
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + JSON.stringify(detail) + "]" : ""));
  try {
    await page.goto("http://127.0.0.1:__PORT__/");
    await page.waitForFunction(() => !document.getElementById("pick").disabled, null, { timeout: 10000 });
    await page.click("#tab-controls");
    const status = await page.textContent("#controls-status");
    ok("the tab says why it refused the manifest", status.includes("__WANT__"), status);
    ok("no manifest control is rendered", await page.locator("#controls-list .uifc-row input:not([type=checkbox]), #controls-list select").count() === 0);
    ok("the data controls stay, in the Sample data menu", await page.locator("#data-list button", { hasText: "seed 10" }).count() === 1);
    await page.goto("__FILE__");
    const alone = page.locator('aside[aria-label="Controls"]');
    await alone.waitFor({ timeout: 3000 }).catch(() => {});
    const line = (await alone.count()) ? await alone.textContent() : "";
    ok("opened alone, the page shows the same reason in a one-line panel and draws no control", line.includes("__WANT__") && await alone.locator("input, select").count() === 0, line);
  } catch (e) {
    R.push("ERROR " + String(e).split("\n")[0]);
  }
  return R.join("\n");
}
