async page => {
  // The dock's Controls tab on the host page: the tabs by keyboard, each control type writing its
  // target in the framed mockup and showing its value, Copy config, a note carrying every manifest
  // id, the built-in data and content entries, and Reset controls leaving the data alone.
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + JSON.stringify(detail) + "]" : ""));
  const focused = () => page.evaluate(() => document.activeElement.id);
  const selected = (id) => page.getAttribute(id, "aria-selected");
  const posted = [];
  page.on("request", (r) => { if (r.method() === "POST" && r.url().endsWith("/api/note")) posted.push(r.postDataJSON()); });
  try {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto("http://127.0.0.1:__PORT__/");
    await page.waitForFunction(() => !document.getElementById("pick").disabled, null, { timeout: 10000 });
    const frame = page.frames().find((f) => f !== page.mainFrame());
    const inFrame = page.frameLocator("#page");
    // A CSS variable on the root, or an attribute on the root or on variant A's element.
    const css = (name) => frame.evaluate((n) => getComputedStyle(document.documentElement).getPropertyValue(n).trim(), name);
    const attr = (name, variant) => frame.evaluate(([n, v]) => (v ? document.querySelector(`[data-variant="${v}"]`) : document.documentElement).getAttribute(n), [name, variant]);
    const shown = (label) => page.locator(".uifc-row", { has: page.getByLabel(label, { exact: true }) }).locator("output").textContent();
    const rows = () => inFrame.locator('[data-variant="A"] [data-testid="team-member-row"]').count();

    ok("Notes is the selected tab when the page opens", await selected("#tab-notes") === "true" && await page.isVisible("#notes-panel") && await page.isHidden("#controls-panel"));
    ok("only the selected tab is in the tab order", await page.getAttribute("#tab-controls", "tabindex") === "-1");
    ok("the tabs sit in a tablist and name their panels", await page.locator('[role="tablist"] [role="tab"]').count() === 2
      && await page.getAttribute("#tab-controls", "aria-controls") === "controls-panel" && await page.getAttribute("#controls-panel", "role") === "tabpanel");
    await page.focus("#tab-notes");
    await page.keyboard.press("ArrowRight");
    ok("ArrowRight moves the focus to Controls and shows its panel", (await focused()) === "tab-controls" && await selected("#tab-controls") === "true"
      && await page.isVisible("#controls-panel") && await page.isHidden("#notes-panel"), await focused());
    ok("the selected tab is the one in the tab order", await page.getAttribute("#tab-controls", "tabindex") === "0" && await page.getAttribute("#tab-notes", "tabindex") === "-1");
    await page.keyboard.press("ArrowRight");
    ok("ArrowRight on the last tab wraps to Notes", (await focused()) === "tab-notes" && await selected("#tab-notes") === "true");
    await page.keyboard.press("ArrowLeft");
    ok("ArrowLeft on the first tab wraps to Controls", (await focused()) === "tab-controls");
    await page.keyboard.press("Home");
    ok("Home selects the first tab", (await focused()) === "tab-notes" && await page.isVisible("#notes-panel"));
    await page.keyboard.press("End");
    ok("End selects the last tab", (await focused()) === "tab-controls" && await page.isVisible("#controls-panel"));
    await page.keyboard.press("n");
    ok("N hides the dock from the Controls tab, the focus on the dock button", await page.isHidden("#panel") && (await focused()) === "dock", await focused());
    await page.keyboard.press("n");
    ok("N shows the dock again on the Controls tab, the focus on that tab", await page.isVisible("#controls-panel") && (await focused()) === "tab-controls", await focused());
    await page.keyboard.press("r");
    ok("R from the Controls tab starts the pick on the Notes tab, its instructions in view", await selected("#tab-notes") === "true"
      && await page.isVisible("#status") && /Drag a box/.test(await page.textContent("#status")), await page.textContent("#status"));
    await page.keyboard.press("ArrowRight");
    await page.keyboard.press("ArrowRight");
    ok("during a region pick the arrows on a focused tab move the region, not the tabs", await page.getAttribute("#region", "aria-pressed") === "true" && await selected("#tab-notes") === "true");
    await page.keyboard.press("Escape");
    ok("Esc ends that pick", await page.getAttribute("#region", "aria-pressed") === "false");
    await page.click("#tab-controls");

    ok("the tab lists the manifest's five controls and says where they came from", /^5 control\(s\)/.test(await page.textContent("#controls-status")), await page.textContent("#controls-status"));
    ok("a manifest label holding markup is shown as text and makes no element", (await page.$$("#controls-panel img")).length === 0
      && (await page.textContent("#controls-panel")).includes('Alignment <img src=x onerror="window.__xss=1">'));
    ok("the defaults are shown and the page starts at them", (await shown("Card gap")) === "12px" && (await css("--card-gap")) === "12px" && (await attr("data-control-align")) === "start");

    await page.getByLabel("Card gap", { exact: true }).fill("24");
    // A value reaches the frame by postMessage, a task after the input event.
    await frame.waitForFunction(() => getComputedStyle(document.documentElement).getPropertyValue("--card-gap").trim() === "24px", null, { timeout: 2000 }).catch(() => {});
    ok("range: writes its CSS variable with its unit and shows the value", (await css("--card-gap")) === "24px" && (await shown("Card gap")) === "24px", [await css("--card-gap"), await shown("Card gap")]);
    await page.getByLabel("Accent", { exact: true }).fill("#aa3300");
    ok("color: writes its CSS variable and shows the value", (await css("--accent")) === "#aa3300" && (await shown("Accent")) === "#aa3300");
    await page.getByLabel("Typeface", { exact: true }).selectOption("Georgia, serif");
    ok("select: writes its CSS variable and shows the value", (await css("--font")) === "Georgia, serif" && (await shown("Typeface")) === "Georgia, serif");
    await page.getByLabel("Dense rows (variant A)", { exact: true }).check();
    ok("toggle: writes its attribute on its variant's element and shows the value", (await attr("data-control-dense", "A")) === "on" && (await shown("Dense rows (variant A)")) === "on");
    ok("a variant's control does not reach the page root or the other variant", (await attr("data-control-dense")) === null && (await attr("data-control-dense", "B")) === null);
    await page.getByRole("radio", { name: "center" }).check();
    const radioOut = await page.locator(".uifc-row", { has: page.getByRole("radio", { name: "center" }) }).locator("output").textContent();
    ok("radio: writes its attribute on the root and shows the value", (await attr("data-control-align")) === "center" && radioOut === "center", radioOut);

    await frame.evaluate(() => { document.dispatchEvent(new CustomEvent("vs:show", { detail: { variant: "B" } })); document.dispatchEvent(new CustomEvent("vs:show", { detail: { variant: "A" } })); });
    ok("a variant's control survives switching away and back (the switcher remounts the variant)", (await attr("data-control-dense", "A")) === "on");

    await page.click("#copy-config");
    const config = await page.inputValue("#config");
    ok("Copy config copies every control's id and the value the page receives", config === "card-gap: 24px · accent: #aa3300 · font: Georgia, serif · dense: on · align: center", config);

    const before = await rows();
    await page.getByRole("button", { name: "seed 10" }).click();
    ok("the built-in Seed entry presses the page's own Seed control", (await rows()) === before + 10, [before, await rows()]);
    await page.getByLabel("Worst content", { exact: true }).check();
    ok("the built-in content entry shows the worst content set", (await attr("data-vs-content")) === "worst");
    await page.getByLabel("Worst content", { exact: true }).uncheck();
    ok("and back to the demo set", (await attr("data-vs-content")) === "demo");

    await page.focus("#tab-controls");
    await page.keyboard.press("p");
    ok("P from the Controls tab starts the pick on the Notes tab, its instructions in view", await selected("#tab-notes") === "true" && await page.getAttribute("#pick", "aria-pressed") === "true"
      && await page.isVisible("#status") && /Click an element/.test(await page.textContent("#status")), await page.textContent("#status"));
    await inFrame.locator('[data-variant="A"] [data-testid="team-member-row"]').nth(1).click();
    await page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
    ok("a picked element opens the note on the Notes tab", await selected("#tab-notes") === "true" && await page.isVisible("#composer"));
    await page.keyboard.insertText("Tighten this row.");
    await page.click("#send");
    await page.waitForFunction(() => /Note 1 sent/.test(document.getElementById("status").textContent), null, { timeout: 5000 });
    const sent = posted[0]?.controls || {};
    ok("the note carries every manifest id with the value the person set", JSON.stringify(sent) === JSON.stringify({ "card-gap": "24", accent: "#aa3300", font: "Georgia, serif", dense: "on", align: "center" }), sent);
    ok("the note's data log holds the Seed press", JSON.stringify(posted[0]?.data?.log) === JSON.stringify([{ op: "seed", n: 10 }, { op: "content", name: "worst" }, { op: "content", name: "demo" }]), posted[0]?.data);

    await page.click("#tab-controls");
    const seeded = await rows();
    await page.click("#reset-controls");
    ok("Reset controls puts every control back at its default, shown and written", (await shown("Card gap")) === "12px" && (await css("--card-gap")) === "12px"
      && (await css("--accent")) === "#0d9488" && (await attr("data-control-dense", "A")) === "off" && (await attr("data-control-align")) === "start");
    ok("Reset controls leaves the data as it was", (await rows()) === seeded && seeded === before + 10, [seeded, await rows()]);

    const set = await frame.evaluate(() => window.uiFeedbackRelocate.setControls({ "card-gap": "30", dense: "on" }));
    ok("the relocation hook sets controls in the page", set === 0 && (await css("--card-gap")) === "30px" && (await attr("data-control-dense", "A")) === "on");
    ok("and counts a control the page has no entry for", await frame.evaluate(() => window.uiFeedbackRelocate.setControls({ gone: "1" })) === 1);
    ok("a value the control's field cannot hold is set nowhere and counted", await frame.evaluate(() => window.uiFeedbackRelocate.setControls({ font: "Papyrus", "card-gap": "999", accent: "oklch(0.6 0.1 180)" })) === 3
      && (await css("--font")) === "system-ui, sans-serif" && (await css("--card-gap")) === "30px");
    ok("no handler in a manifest string ran", await page.evaluate(() => window.__xss) === undefined && await frame.evaluate(() => window.__xss) === undefined);

    // The registry's own check, which the schema cannot state, over the shared fixtures.
    const registry = __REGISTRY__;
    for (const { why, manifest } of registry.valid) ok(`the registry admits: ${why}`, await page.evaluate((m) => window.uiFeedbackControls.refused(m.controls), manifest) === null);
    for (const { why, manifest } of registry.invalid) {
      const said = await page.evaluate((m) => window.uiFeedbackControls.refused(m.controls), manifest);
      ok(`the registry refuses: ${why}`, typeof said === "string", said);
    }

    // A second document in the frame: the host page stops listening, so the Controls tab stops too.
    await frame.evaluate(() => { location.href = "about:blank"; });
    await page.waitForFunction(() => document.getElementById("pick").disabled, null, { timeout: 5000 });
    ok("after the frame loads another page, the controls, Copy config and Reset controls are off and the tab says why",
      await page.locator("#controls-list input").first().isDisabled() && await page.isDisabled("#copy-config") && await page.isDisabled("#reset-controls")
      && /no longer reach/.test(await page.textContent("#controls-status")), await page.textContent("#controls-status"));
  } catch (e) {
    R.push("ERROR " + String(e).split("\n")[0]);
  }
  return R.join("\n");
}
