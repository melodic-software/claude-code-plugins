async page => {
  // The page here has no CSP meta of its own, so only the policy /api/page puts first in it, and the one the frame inherits, apply.
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  const base = "http://127.0.0.1:__PORT__/";
  try {
    await page.goto(base);
    await page.waitForFunction(() => !document.getElementById("pick").disabled, null, { timeout: 10000 });
    const frame = page.frames().find(f => f !== page.mainFrame());
    const tried = await frame.evaluate(async (base) => {
      const out = {}, blocked = [];
      document.addEventListener("securitypolicyviolation", e => blocked.push(e.effectiveDirective + " " + e.blockedURI));
      for (const [k, url, init] of [
        ["token", base + "api/token", {}],
        ["page", base + "api/page", {}],
        ["note", base + "api/note", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ kind: "element", anchor: { tag: "main", cssPath: "" }, text: "from the frame" }) }],
        ["ping", base + "api/ping", { mode: "no-cors" }],
        ["events", base + "events", { mode: "no-cors" }],
      ]) {
        try { const r = await fetch(url, init); out[k] = r.type === "opaque" ? "opaque" : r.status; } catch { out[k] = "threw"; }
      }
      await new Promise(r => setTimeout(r, 100));
      out.violations = blocked.filter(v => v.startsWith("connect-src ")).length;
      return out;
    }, base);
    const all = JSON.stringify(tried);
    for (const k of ["token", "page", "note", "ping", "events"]) {
      ok("the framed page's fetch of " + k + " throws", tried[k] === "threw", all);
    }
    ok("each of the five fetches is a connect-src violation", tried.violations === 5, all);
  } catch (e) {
    R.push("ERROR " + String(e).split("\n")[0]);
  }
  return R.join("\n");
}
