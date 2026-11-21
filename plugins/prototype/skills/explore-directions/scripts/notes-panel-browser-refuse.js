async page => {
  // Send all drafts with the session taking the first note and refusing the second: the status
  // keeps the reason beside what was sent, and the refused draft stays a draft.
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  try {
    const inFrame = page.frameLocator("#page");
    for (const [i, words] of [[0, "First"], [1, "Second"]]) {
      await page.click("#pick");
      await inFrame.locator('[data-variant="A"] [data-testid="shipments-parcel-row"]').nth(i).click();
      await page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
      await page.keyboard.insertText(words);
      await page.click("#save");
    }
    let posts = 0;
    await page.route("**/api/note", (route) => {
      posts += 1;
      return posts === 1
        ? route.fulfill({ status: 200, contentType: "application/json", body: '{"seq": 99}' })
        : route.fulfill({ status: 400, contentType: "application/json", body: '{"error": "no room"}' });
    });
    await page.click("#sendall");
    await page.waitForFunction(() => /Note 99 sent/.test(document.getElementById("status").textContent), null, { timeout: 5000 });
    const status = await page.textContent("#status");
    ok("the status keeps the refusal beside what was sent", status === "Note 99 sent. Not sent: no room.", status);
    const states = await page.$$eval("#notes li .state", (s) => s.map((e) => e.textContent));
    ok("the refused draft stays a draft", states.filter((s) => s === "Draft, not sent").length === 1, states);
    await page.unroute("**/api/note");
  } catch (e) {
    R.push("ERROR " + String(e).split("\n")[0]);
  }
  return R.join("\n");
}
