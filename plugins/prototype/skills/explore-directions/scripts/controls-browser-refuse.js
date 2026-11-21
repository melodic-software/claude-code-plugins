async page => {
  // A manifest outside controls.schema.json (a target that is no CSS variable or data-control
  // attribute) is refused whole: the Controls tab says why and keeps only the page's data controls.
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + JSON.stringify(detail) + "]" : ""));
  try {
    await page.goto("http://127.0.0.1:__PORT__/");
    await page.waitForFunction(() => !document.getElementById("pick").disabled, null, { timeout: 10000 });
    await page.click("#tab-controls");
    const status = await page.textContent("#controls-status");
    ok("the tab says the manifest is outside the controls contract", /outside the controls contract/.test(status), status);
    ok("no manifest control is rendered", await page.locator("#controls-list .uifc-row input:not([type=checkbox]), #controls-list select").count() === 0);
    ok("the data controls stay, in the Sample data menu", await page.locator("#data-list button", { hasText: "seed 10" }).count() === 1);
    ok("Copy config and Reset controls are off", await page.isDisabled("#copy-config") && await page.isDisabled("#reset-controls"));
    const frame = page.frames().find((f) => f !== page.mainFrame());
    ok("the page itself is never written by the refused control", await frame.evaluate(() => document.documentElement.getAttribute("onclick")) === null);
  } catch (e) {
    R.push("ERROR " + String(e).split("\n")[0]);
  }
  return R.join("\n");
}
