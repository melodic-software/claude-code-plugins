async page => {
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + JSON.stringify(detail) + "]" : ""));
  const A = "direction: A Ledger\ntest-ids: A: shipments-title, shipments-row; B: shipments-list";
  const B = "direction: B Cards\ntest-ids: A: shipments-title, shipments-row; B: shipments-list";
  const block = () => page.inputValue("#block");
  const status = () => page.textContent("#status");
  const settle = async (read, want) => {
    for (let i = 0; i < 40 && (await read()) !== want; i++) await page.waitForTimeout(50);
  };
  try {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto("http://127.0.0.1:__PORT__/");
    await page.waitForFunction(() => !document.getElementById("pick").disabled, null, { timeout: 10000 });
    const frame = page.frames().find((f) => f !== page.mainFrame());
    const inFrame = page.frameLocator("#page");
    const rows = () => inFrame.locator('[data-testid="shipments-row"]').count();

    await settle(() => inFrame.locator(".bar").isHidden(), true);
    ok("framed, the mockup's own data bar is hidden", await inFrame.locator(".bar").isHidden());
    await page.click("#data");
    await page.getByRole("button", { name: "seed 10" }).click();
    await settle(rows, 13);
    ok("Sample data still presses the hidden bar's Seed control", (await rows()) === 13, await rows());

    await page.click("#copy-button");
    ok("the Copy menu offers Copy chosen design, on", await page.isEnabled("#copy-chosen"));
    await page.click("#copy-chosen");
    await settle(block, A);
    ok("Copy chosen design copies the shown variant's copy-out text", (await block()) === A, await block());
    ok("it is the text the page's own copy-out gives", (await block()) === (await frame.evaluate(() => window.uiFeedbackCopyOut())));
    await settle(async () => /Copied the chosen design/.test(await status()), true);
    ok("the copy is said in the status line", /Copied the chosen design/.test(await status()), await status());

    await page.click("#vnext");
    await page.click("#copy-button");
    await page.click("#copy-chosen");
    await settle(block, B);
    ok("after the view arrows show variant B, the copy names B", (await block()) === B, await block());

    await frame.evaluate(() => { window.__markup = true; });
    await page.click("#copy-button");
    await page.click("#copy-chosen");
    await page.waitForFunction(() => /nothing was copied/.test(document.getElementById("status").textContent), null, { timeout: 5000 }).catch(() => {});
    ok("a copy-out holding markup copies nothing and says why", (await block()) === B && /nothing was copied/.test(await status()), [await block(), await status()]);
    ok("and makes no element and runs no handler", (await page.$$("#panel img")).length === 0 && await page.evaluate(() => window.__xss) === undefined);

    for (const why of ["throws", "returns no string", "is gone"]) {
      await frame.evaluate((w) => {
        window.uiFeedbackCopyOut = w === "throws" ? () => { throw new Error("broken copy-out"); } : w === "returns no string" ? () => 42 : undefined;
      }, why);
      await page.click("#copy-button");
      await page.click("#copy-chosen");
      await page.waitForFunction(() => /gave nothing/.test(document.getElementById("status").textContent), null, { timeout: 5000 }).catch(() => {});
      ok(`when the page's copy-out function ${why}, nothing is copied and the status says it gave nothing`, (await block()) === B && /gave nothing.*console/.test(await status()), [await block(), await status()]);
      await page.evaluate(() => { document.getElementById("status").textContent = ""; });
    }

    await frame.evaluate(() => window.parent.postMessage({ type: "chosen", text: "unasked" }, "*"));
    await page.waitForTimeout(300);
    ok("a chosen-design message the host page did not ask for copies nothing", (await block()) === B, await block());

    await page.goto("__FILE__");
    ok("opened alone from file://, the page keeps its data bar", await page.isVisible(".bar"));
    await page.click("#copy-out");
    ok("and its own copy-out gives the same text", (await page.textContent("#copied")) === A, await page.textContent("#copied"));
  } catch (e) {
    R.push("ERROR " + String(e).split("\n")[0]);
  }
  return R.join("\n");
}
