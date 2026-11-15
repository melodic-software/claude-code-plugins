async page => {
  // The Notes panel on the host page: hide and show it with N, save a draft whose text is markup,
  // edit it, delete a second draft, close the editor with Esc, then send the draft.
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  const MARKUP = '<img src=x onerror="window.__xss=1">';
  const focused = () => page.evaluate(() => document.activeElement.dataset.key || document.activeElement.id);
  const states = () => page.$$eval("#notes li .state", (s) => s.map((e) => e.textContent));
  try {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto("http://127.0.0.1:__PORT__/");
    await page.waitForFunction(() => !document.getElementById("pick").disabled, null, { timeout: 10000 });
    const inFrame = page.frameLocator("#page");
    const row = (i) => inFrame.locator('[data-variant="A"] [data-testid="shipments-parcel-row"]').nth(i);
    const pick = async (i, words) => {
      await page.click("#pick");
      await row(i).click();
      await page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
      await page.keyboard.insertText(words);
    };

    const wide = (await page.locator("#page").boundingBox()).width;
    await page.locator("body").press("n");
    ok("N hides the panel and leaves the focus on its button", await page.isHidden("#panel") && (await focused()) === "dock", await focused());
    ok("the button says the panel is closed", await page.getAttribute("#dock", "aria-expanded") === "false");
    ok("the mockup's frame takes the room", (await page.locator("#page").boundingBox()).width > wide);
    await page.keyboard.press("n");
    ok("N shows the panel and moves the focus into it", await page.isVisible("#panel") && (await focused()) === "pick", await focused());

    await pick(0, MARKUP + "Move this row up");
    await page.click("#save");
    ok("Save draft lists the note as a draft", String(await states()) === "draft", await states());
    ok("the editor closes and the focus is on the draft's Edit button", await page.isHidden("#composer") && (await focused()) === "edit-1", await focused());
    ok("the markup in the note is shown as text", (await page.textContent("#notes li")).includes(MARKUP + "Move this row up"));
    ok("and creates no element", (await page.$$("#notes img")).length === 0);

    await page.click('[data-key="edit-1"]');
    ok("Edit opens the editor on the draft's text", (await page.inputValue("#text")) === MARKUP + "Move this row up" && (await focused()) === "text");
    await page.fill("#text", MARKUP + "Move this row to the top");
    await page.click("#save");
    ok("the edited draft keeps its place with the new text", (await page.$$("#notes li")).length === 1 && (await page.textContent("#notes li")).includes("to the top"));

    await pick(1, "Delete me");
    await page.click("#save");
    ok("a second draft is listed and Send all drafts shows", String(await states()) === "draft,draft" && await page.isVisible("#sendall"), await states());
    await page.click('[data-key="delete-2"]');
    ok("Delete removes the draft and moves the focus to the list", String(await states()) === "draft" && (await focused()) === "notes-title", await focused());

    await page.click('[data-key="edit-1"]');
    await page.keyboard.press("Escape");
    ok("Esc closes the editor, gives the focus back to Edit and keeps the draft", await page.isHidden("#composer") && (await focused()) === "edit-1" && (await page.textContent("#notes li")).includes("to the top"), await focused());

    // Send pressed twice in one tick, with the editor open on that draft.
    await page.click('[data-key="edit-1"]');
    await page.evaluate(() => { const b = document.querySelector('[data-key="send-1"]'); b.click(); b.click(); });
    await page.waitForFunction(() => /Note 1 sent/.test(document.getElementById("status").textContent), null, { timeout: 5000 });
    ok("the sent note shows sent", String(await states()) === "sent", await states());
    ok("sending a draft closes the editor that was open on it", await page.isHidden("#composer"));
    await page.waitForTimeout(1500);
    ok("the second press sent no copy", (await page.$$("#notes li")).length === 1, await states());
    ok("no handler in the note ran", await page.evaluate(() => window.__xss) === undefined);
  } catch (e) {
    R.push("ERROR " + String(e).split("\n")[0]);
  }
  return R.join("\n");
}
