async page => {
  // The open host page after a step of the session's: note 1's status becomes __WANT__, the
  // change is announced, and any reply is shown as text.
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  try {
    await page.waitForFunction((w) => document.querySelector("#notes li .state")?.textContent === w, "__WANT__", { timeout: 10000 });
    ok("note 1 shows __WANT__", true);
    const said = await page.textContent("#changes");
    ok("the change is announced in the live region", /Note 1: __WANT__/.test(said) && await page.getAttribute("#changes", "aria-live") === "polite", said);
    const reply = await page.$$eval("#notes li .reply", (r) => r.map((e) => e.textContent));
    ok("the replies shown are the ones applied, as text",JSON.stringify(reply) === JSON.stringify(__REPLY__), JSON.stringify(reply));
    ok("no element came from a note or reply, and no handler ran", (await page.$$("#notes img")).length === 0 && await page.evaluate(() => window.__xss) === undefined);
  } catch (e) {
    R.push("ERROR " + String(e).split("\n")[0]);
  }
  return R.join("\n");
}
