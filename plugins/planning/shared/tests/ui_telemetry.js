#!/usr/bin/env node
// Passive telemetry in real browsers, against `share.sh ensure-running` with the fake cloudflared, every request to
// another host refused. A desktop guest's join dialog shows the notice line, its "What this page records" list and
// the switch. A script error thrown three times is sent once with a fingerprint, its two repeats counted in the
// summary the page sends when it hides; two picks (one refused on a locked question, so its optimistic patch rolls
// back) show as tap-to-answer latency and one rollback; showing the page again gives a reconnect gap; INP and LCP come
// from the vendored web-vitals file, loaded from this origin. The summary names no one, in its body or on the server,
// where it has no line of its own until the batch that stopping the server writes.
// No client-log body ever holds the guest's name, typed text, an answer comment or chat. Turning the switch off in
// Help stops every send, across a reload. A 320 px phone logs a too-wide pane as a layout anomaly naming components
// only. A page whose web-vitals file is missing still works and says so.
//   node plugins/planning/shared/tests/ui_telemetry.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the approved V1 (feedback triage row 49: the signals, no pid on usage entries, the Off
// switch, local web-vitals) and the texts this suite makes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const NAME = "Quillon Fernsby", CHAT = "chat-line-telemetry-never-holds", COMMENT = "comment-telemetry-never-holds";
const TYPED = "typed-words-telemetry-never-holds", THROWN = "injected-telemetry-error";
const PHONE = { viewport: { width: 320, height: 640 }, hasTouch: true, isMobile: true };

/** Every /api/client-log body a page sends, and every request to another host (refused). */
async function watch(page, ctx, out) {
  await ctx.route("**/*", r => {
    const u = new URL(r.request().url());
    if (u.hostname !== "127.0.0.1" && u.hostname !== "localhost") { out.foreign.push(u.href); return r.abort(); }
    return r.fallback();
  });
  page.on("request", r => { if (new URL(r.url()).pathname === "/api/client-log") out.bodies.push(r.postData() || ""); });
}
const setVisibility = (page, state) => page.evaluate(st => {
  Object.defineProperty(document, "visibilityState", { configurable: true, get: () => st });
  Object.defineProperty(document, "hidden", { configurable: true, get: () => st === "hidden" });
  document.dispatchEvent(new Event("visibilitychange", { bubbles: true }));
}, state);
const parsed = bodies => bodies.map(b => { try { return JSON.parse(b); } catch { return {}; } });
const tokens = m => Object.fromEntries((m || "").split(" ").map(t => [t.slice(0, t.indexOf("=")), t.slice(t.indexOf("=") + 1)]));

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_telemetry.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let chromium;
  try { chromium = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_telemetry"), { ok } = s;
  const rec = recorder(chromium);
  try {
    const A = await s.start("telemetry");
    const choice = id => ({ id, text: `Which option for ${id}?`, alternatives: [], dependsOn: [], purpose: "decide",
      format: { kind: "choice", options: [{ id: "opt-1", label: "Card" }, { id: "opt-2", label: "Saved method" }] } });
    s.apply(A.dir, [{ op: "open-round", questions: [choice("Q1"), choice("Q2")] }]);
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    await owner.evaluate(() => window.Core.lock("Q1", "opt-1"));

    // ---------- a desktop guest: the notice, the list, the signals ----------
    const w = { bodies: [], foreign: [] };
    const guest = await rec.open(A.localUrl);
    await watch(guest, guest.context(), w);
    await guest.reload();
    await guest.waitForSelector("dialog.core-name[open]");
    const dlg = await guest.evaluate(() => {
      const d = document.querySelector("dialog.core-name");
      return { line: d.querySelector(".core-rec-line")?.textContent || "", link: d.querySelector("a.core-rec-link")?.textContent, on: d.querySelector(".core-rec-switch input")?.checked };
    });
    ok("the join dialog says what the page records, with the link and the switch on", /records errors, slow or failed actions and layout problems/.test(dlg.line)
      && /never records what you type/.test(dlg.line) && dlg.link === "What this page records" && dlg.on === true, JSON.stringify(dlg));
    await guest.locator("dialog.core-name a.core-rec-link").click();
    const note = await until(guest, () => !!document.querySelector("dialog.core-records[open]")) && await guest.evaluate(() => {
      const d = document.querySelector("dialog.core-records");
      return { heads: [...d.querySelectorAll("h3")].map(h => h.textContent), items: d.querySelectorAll("li").length, never: d.textContent.includes("What you type"), sw: !!d.querySelector(".core-rec-switch input") };
    });
    ok("the link opens the plain list of what is and is not recorded, with the switch", !!note && note.heads.join("|") === "Recorded|Never recorded" && note.items >= 8 && note.never && note.sw, JSON.stringify(note));
    await guest.locator("dialog.core-records button").click();
    ok("  which closes", await until(guest, () => !document.querySelector("dialog.core-records")));
    const pid = await joinAs(guest, NAME);

    ok("the vendored web-vitals loads from this origin", await until(guest, () => !!window.webVitals?.onINP));
    await guest.evaluate(t => { for (let i = 0; i < 3; i++) setTimeout(() => { throw new Error(t); }, 10 * i); }, THROWN);
    const refused = await guest.evaluate(c => window.Core.pick("Q1", "opt-2", c).then(() => 200, e => e.status), COMMENT);
    ok("a pick on the locked question is refused 409", refused === 409, refused);
    await guest.evaluate(c => window.Core.pick("Q2", "opt-2", c), COMMENT);
    await guest.evaluate(t => window.Core.chat(t), CHAT);
    await guest.locator(".vf-propose").click();
    await guest.locator("#vf-prop-ta").fill(TYPED);
    await guest.keyboard.press("Escape");
    await guest.locator(".vf-keysbtn").click(); // an interaction for INP
    await guest.keyboard.press("Escape");
    await guest.waitForTimeout(500);

    const errorsSent = () => parsed(w.bodies).filter(b => b.kind === "error" && b.message?.includes(THROWN));
    ok("the error thrown three times is sent once, with its fingerprint", errorsSent().length === 1 && /^[0-9a-f]{8}$/.test(errorsSent()[0].fp), JSON.stringify(errorsSent()));
    ok("no refusal is sent as a client copy", !parsed(w.bodies).some(b => b.kind === "api"), w.bodies.join(" | "));

    await setVisibility(guest, "hidden");
    let sums = [];
    for (let i = 0; i < 40 && !sums.length; i++) { sums = parsed(w.bodies).filter(b => b.kind === "summary"); if (!sums.length) await guest.waitForTimeout(100); }
    const t1 = tokens(sums[0]?.message);
    const lat = (t1["lat:/api/pick"] || "").split(",").reduce((a, n) => a + Number(n), 0);
    ok("hiding sends one summary: both picks timed, one rollback, the two repeats", sums.length === 1 && lat === 2 && t1["rb:/api/pick"] === "1" && t1[`rep:${errorsSent()[0]?.fp}`] === "2", sums[0]?.message);
    // A target is a component name, or "-" when web-vitals found no element for it (one removed before it measured).
    ok("  with INP and LCP named by component, never text", /^\d+:(pointer|keyboard):(?:[a-z][\w-]*|-)$/.test(t1.inp || "") && /^\d+:(?:[a-z][\w-]*|-)$/.test(t1.lcp || ""), `${t1.inp} ${t1.lcp}`);
    ok("  and no pid or name in its body", !("pid" in sums[0]) && !JSON.stringify(sums[0]).includes(pid) && !/owner=/.test(sums[0]?.message || ""), JSON.stringify(sums[0]));

    await setVisibility(guest, "visible");
    await guest.waitForTimeout(2500);
    await setVisibility(guest, "hidden");
    for (let i = 0; i < 40 && sums.length < 2; i++) { sums = parsed(w.bodies).filter(b => b.kind === "summary"); if (sums.length < 2) await guest.waitForTimeout(100); }
    const gap = Number(tokens(sums[1]?.message).gap);
    ok("showing the page again gives a reconnect gap in the next summary", sums.length === 2 && gap >= 0 && gap < 2500, sums[1]?.message);
    await setVisibility(guest, "visible");

    const leaked = w.bodies.filter(b => [NAME, CHAT, COMMENT, TYPED, "Quillon"].some(x => b.includes(x)));
    ok("no client-log body holds the name, typed text, the comment or the chat", w.bodies.length >= 3 && leaked.length === 0, leaked.join(" | "));
    ok("no request left this origin", w.foreign.length === 0, w.foreign.join(" | "));

    // ---------- the switch in Help stops every send, and stays off ----------
    await guest.locator(".vf-keysbtn").click();
    const sw = guest.locator(".vf-keys .vf-help-rec .core-rec-switch input");
    ok("Help shows the same notice and switch", await sw.isVisible() && await guest.locator(".vf-keys .vf-help-rec a.core-rec-link").isVisible());
    await sw.uncheck();
    await guest.keyboard.press("Escape");
    const before = w.bodies.length;
    await guest.evaluate(t => setTimeout(() => { throw new Error(t + "-off"); }), THROWN);
    await guest.evaluate(() => window.Core.pick("Q2", "opt-1", ""));
    await guest.evaluate(() => window.Core.reportLayout({ probe: 1 }));
    await setVisibility(guest, "hidden");
    await guest.waitForTimeout(800);
    await setVisibility(guest, "visible");
    ok("turned off, the page sends nothing: no fault, no readout, no summary", w.bodies.length === before, w.bodies.slice(before).join(" | "));
    await guest.reload();
    await until(guest, () => !!window.Core.snapshot()?.me);
    await guest.evaluate(t => setTimeout(() => { throw new Error(t + "-reloaded"); }), THROWN);
    await setVisibility(guest, "hidden");
    await guest.waitForTimeout(800);
    ok("  and stays off after a reload", await guest.evaluate(() => window.Core.telemetry.off && localStorage.getItem("telemetry") === "off") && w.bodies.length === before, w.bodies.slice(before).join(" | "));
    await setVisibility(guest, "visible");

    // ---------- a 320 px phone: a too-wide pane is a layout anomaly ----------
    const pw320 = { bodies: [], foreign: [] };
    const phone = await rec.open(A.localUrl, { context: PHONE });
    await watch(phone, phone.context(), pw320);
    await joinAs(phone, "Pia");
    await phone.waitForTimeout(3000);
    const anomalies = () => parsed(pw320.bodies).filter(b => b.kind === "layout" && /^anomaly=/.test(b.message || ""));
    ok("the page itself fits 320 px: no layout anomaly", anomalies().length === 0, anomalies().map(b => b.message).join(" | "));
    const pane = await phone.evaluate(() => {
      const c = [...document.querySelectorAll("#app *")].find(e => e.offsetParent && /auto|scroll/.test(getComputedStyle(e).overflowY) && e.clientWidth > 200);
      if (!c) return "";
      const wide = document.createElement("div"); wide.className = "vf-telemetry-probe"; wide.style.cssText = "inline-size:900px;block-size:4px"; c.append(wide);
      return [...c.classList].find(x => x.startsWith("vf-")) || c.tagName.toLowerCase();
    });
    await phone.locator("#app").tap({ position: { x: 5, y: 300 } });
    let found = [];
    for (let i = 0; i < 40 && !found.length; i++) { found = anomalies(); if (!found.length) await phone.waitForTimeout(150); }
    const t = tokens(found[0]?.message);
    ok("a pane wider than the 320 px screen is logged once as an overflow, naming components", !!pane && found.length === 1 && t.anomaly === "overflow" && t.el === "vf-telemetry-probe"
      && t.vw === "320" && Number(t.sw) > Number(t.w) && found[0].ua === "chrome phone" && /^[0-9a-f]{8}$/.test(found[0].fp), `${pane} ${found.map(b => b.message).join(" | ")}`);

    // ---------- the web-vitals file missing: the page still works ----------
    const wm = { bodies: [], foreign: [] };
    const bare = await rec.open(A.localUrl);
    await watch(bare, bare.context(), wm);
    await bare.context().route("**/web-vitals.attribution.iife.js", r => r.fulfill({ status: 404, contentType: "application/json", body: "{}" }));
    await bare.reload();
    await joinAs(bare, "Bo");
    const picked = await bare.evaluate(() => window.Core.pick("Q2", "opt-1", "").then(() => "ok", e => String(e.status)));
    await setVisibility(bare, "hidden");
    let bs = [];
    for (let i = 0; i < 40 && !bs.length; i++) { bs = parsed(wm.bodies).filter(b => b.kind === "summary"); if (!bs.length) await bare.waitForTimeout(100); }
    ok("without the web-vitals file the page works and its summary says vitals=missing", picked === "ok" && !(await bare.evaluate(() => !!window.webVitals)) && tokens(bs[0]?.message).vitals === "missing", `${picked} ${bs[0]?.message}`);

    const pageErrs = rec.errors.filter(m => !/Failed to load resource/.test(m) && !m.includes(THROWN));
    ok("no other page error", pageErrs.length === 0, pageErrs.slice(0, 3).join(" | "));
    ok("no CSP violation", (await rec.cspViolations()).length === 0);

    // ---------- the server's log: a summary only in its batch, which stopping the server writes ----------
    const lines = () => s.share(A.dir, "logs").lines;
    const posts = lines().filter(l => / request method=POST route=\/api\/client-log status=200 /.test(l));
    ok("each fault is logged under the guest's pid, and no summary has a line or a request entry of its own", posts.length >= 1 && posts.every(l => / pid=\S/.test(l))
      && lines().some(l => l.includes(` client pid=${pid} kind=error `) && l.includes(THROWN)) && !lines().some(l => / summary-batch |kind=summary/.test(l)), posts.join(" | "));
    s.share(A.dir, "stop");
    const batches = lines().filter(l => / summary-batch /.test(l));
    ok("  stopping the server writes them in one batch with no pid", batches.length === 1 && !batches[0].includes("pid="), batches.join(" | "));
    // The guest's two summaries and the page without web-vitals' one; its pick makes three timed picks.
    const sum = s.share(A.dir, "logs", "--summary", "--json");
    ok("logs --summary counts the error, the latency and the rollback", sum.summaries.count === 3 && sum.errors.some(g => g.message.includes(THROWN) && g.count === 3)
      && sum.latency["/api/pick"]?.actions === 3 && sum.latency["/api/pick"]?.rollbacks === 1 && sum.reconnect.count === 1 && sum.inp.pages === 1, JSON.stringify(sum));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally {
    await chromium.close();
  }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
