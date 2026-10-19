#!/usr/bin/env node
// The owner's Inbox (Needs you) shows a started run at once, against `share.sh ensure-running` with the fake cloudflared.
// Four guests each ask Claude on a question; every /api/request/act call of the owner's page waits 600 ms first, as
// over a quick tunnel. After Run all shown, every started request must read running with its row gone from Needs you,
// so no Run button is left to press, and Run all must be hidden, in under 100 ms and still so once the server answers.
// The same holds for one row's Run.
// A refused run rolls the rows back to waiting, with Run all back, and shows the refusal's own sentence.
//   node plugins/planning/shared/tests/ui_run_all.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values: the 100 ms and 600 ms bounds come from the dogfood brief (as in ui_snappy.js); the refusal is the
// sentence session.py act_on_request gives when none of the ids is still waiting; the request texts are this suite's.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const DELAY = 600, FAST = 100;
const REFUSAL = "None of these requests is still waiting.";
const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });

/** In the page: ms from just before act() to the first frame where done() holds (-1 past `ms`), and whether done()
 *  then holds on every frame for `hold` ms more (a stale poll would flip it back). */
function helpers() {
  window.__time = (act, done, ms = 8000, hold = 0) => new Promise(res => {
    const check = () => { try { return !!done(); } catch { return false; } };
    const t0 = performance.now();
    act();
    const tick = () => {
      const t = performance.now() - t0;
      if (check()) {
        if (!hold) return res({ ms: t, steady: true });
        const t1 = performance.now();
        const watch = () => { if (!check()) return res({ ms: t, steady: false }); if (performance.now() - t1 > hold) return res({ ms: t, steady: true }); requestAnimationFrame(watch); };
        return requestAnimationFrame(watch);
      }
      if (t > ms) return res({ ms: -1, steady: false });
      requestAnimationFrame(tick);
    };
    tick();
  });
  /** The Needs you rows whose text holds one of `texts`: each one's status line and whether its Run button can be pressed. */
  window.__rows = texts => [...document.querySelectorAll(".vf-ibneeds .vf-ritem")].filter(li => texts.some(t => li.textContent.includes(t))).map(li => {
    const run = [...li.querySelectorAll(".vf-acts button")].find(b => b.textContent === "Run"), stat = li.querySelector(".vf-rstat");
    return { status: stat && !stat.hidden ? stat.textContent : "", runEnabled: !!run && !run.hidden && !run.disabled };
  });
  window.__runAll = () => [...document.querySelectorAll("button")].find(b => b.textContent.startsWith("Run all shown"));
  /** Every request of `texts` reads running, none is left in Needs you to Run, and Run all is hidden. */
  window.__started = texts => texts.every(t => window.Core.state.requests.find(r => r.text === t)?.status === "running")
    && window.__rows(texts).every(r => !r.runEnabled) && window.__runAll()?.hidden === true;
  /** Every row of `texts` is waiting with its Run button enabled, and Run all is shown. */
  window.__waiting = texts => { const rows = window.__rows(texts); return rows.length === texts.length && rows.every(r => !r.status && r.runEnabled) && window.__runAll()?.hidden === false; };
}

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_run_all.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_run_all"), { ok } = s, rec = recorder(browser);
  const timings = [];
  try {
    const A = await s.start("runall");
    s.apply(A.dir, [{ op: "set-title", title: "Run all checks" }, { op: "open-round", questions: [q("Q1", "Where should we go?"), q("Q2", "When should we go?")] }]);
    const owner = await rec.open(A.ownerUrl, { init: { fn: helpers } });
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const ask = async (name, qid, text) => { const p = await rec.open(A.localUrl); await joinAs(p, name); await p.evaluate(([qq, t]) => window.Core.request(qq, "ask", t), [qid, text]); };
    const BO = "Bo asks about places", CY = "Cy asks about dates", DI = "Di asks again", EV = "Ev asks once more";
    await ask("Bo", "Q1", BO);
    await ask("Cy", "Q2", CY);
    await ask("Di", "Q1", DI);
    await ask("Ev", "Q2", EV);
    await until(owner, () => (window.Core.state.requests || []).filter(r => r.status === "pending").length === 4);
    await owner.click(".vf-bell"); // the Inbox page, on Needs you
    await owner.click(".vf-ixtabs [data-k=needs]");
    const shown = texts => until(owner, t => window.__waiting(t), texts);
    ok("the queue lists the waiting requests, each with Run, and Run all shown", await shown([BO, CY, DI, EV]),
      await owner.evaluate(t => JSON.stringify(window.__rows(t)), [BO, CY, DI, EV]));
    await owner.route("**/api/request/act", async route => { await new Promise(r => setTimeout(r, DELAY)); await route.continue().catch(() => {}); });
    const fast = (what, r) => {
      timings.push(`${what}: ${r.ms < 0 ? "never" : `${Math.round(r.ms)} ms`}`);
      ok(`${what} in under ${FAST} ms with the run delayed ${DELAY} ms, and stays so`, r.ms >= 0 && r.ms < FAST && r.steady, `${Math.round(r.ms)} ms, steady ${r.steady}`);
    };

    // ---------- a refused Run all rolls back with the refusal's own sentence ----------
    await owner.route("**/api/request/act", route => setTimeout(() => route.fulfill({ status: 409, contentType: "application/json",
      body: JSON.stringify({ ok: false, error: "wrong-status", message: REFUSAL, status: "not-pending" }) }).catch(() => {}), DELAY), { times: 1 });
    fast("a refused Run all still shows every request running and hides Run all", await owner.evaluate(t => window.__time(() => window.__runAll().click(), () => window.__started(t)), [BO, CY, DI, EV]));
    ok("then the rows roll back to waiting, Run all comes back, and the refusal shows", await until(owner, ([t, msg]) => window.__waiting(t)
      && (document.querySelector(".vf-toast")?.textContent || "").includes(msg), [[BO, CY, DI, EV], REFUSAL]),
      await owner.evaluate(t => `${JSON.stringify(window.__rows(t))} | ${document.querySelector(".vf-toast")?.textContent}`, [BO, CY, DI, EV]));
    ok("  and nothing ran on the server", await owner.evaluate(() => window.Core.snapshot().requests.every(r => r.status.kind === "pending")));

    // ---------- one row's Run ----------
    fast("one row's Run shows that request running, its row gone from Needs you", await owner.evaluate(t => window.__time(() => [...document.querySelectorAll(".vf-ibneeds .vf-ritem")]
      .find(li => li.textContent.includes(t)).querySelector(".vf-acts button.vf-btn-primary").click(), () => window.__started([t]) || (window.Core.state.requests.find(r => r.text === t)?.status === "running" && !window.__rows([t]).length), 8000, 2000), DI));
    ok("  and the server has it running", await until(owner, t => window.Core.snapshot().requests.find(r => r.text === t)?.status.kind === "running", DI));

    // ---------- Run all ----------
    await until(owner, t => window.__waiting(t), [BO, CY, EV]);
    fast("Run all shows every started request running and hides Run all", await owner.evaluate(t => window.__time(() => window.__runAll().click(), () => window.__started(t), 8000, 3000), [BO, CY, EV]));
    ok("  and the server has all of them running", await until(owner, () => window.Core.snapshot().requests.every(r => r.status.kind === "running")),
      await owner.evaluate(() => window.Core.snapshot().requests.map(r => r.status.kind).join()));
    ok("  and Run all stays hidden with nothing waiting", await owner.evaluate(() => window.__runAll()?.hidden === true));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
    ok("no request was answered 429 (slow down)", rec.too.length === 0, rec.too.slice(0, 5).join(", "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  console.log(`timings: ${timings.join("; ")}`);
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
