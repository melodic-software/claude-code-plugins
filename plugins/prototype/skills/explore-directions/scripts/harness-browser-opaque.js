async page => {
  // The page here has no CSP meta of its own, so only the policy the frame inherits from the host page applies.
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  const base = "http://127.0.0.1:__PORT__/";
  try {
    await page.goto(base);
    await page.waitForFunction(() => !document.getElementById("pick").disabled, null, { timeout: 10000 });
    const frame = page.frames().find(f => f !== page.mainFrame());
    const tried = await frame.evaluate(async (base) => {
      const out = {};
      for (const [k, url, init] of [
        ["token", base + "api/token", {}],
        ["page", base + "api/page", {}],
        ["note", base + "api/note", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ kind: "element", anchor: { tag: "main", cssPath: "" }, text: "from the frame" }) }],
      ]) {
        try { const r = await fetch(url, init); out[k] = r.status; } catch { out[k] = "blocked"; }
      }
      return out;
    }, base);
    ok("the framed page cannot read the token", tried.token !== 200, JSON.stringify(tried));
    ok("the framed page cannot read the page route", tried.page !== 200, JSON.stringify(tried));
    ok("the framed page cannot post a note", tried.note !== 200, JSON.stringify(tried));
  } catch (e) {
    R.push("ERROR " + String(e).split("\n")[0]);
  }
  return R.join("\n");
}
