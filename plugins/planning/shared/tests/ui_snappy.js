#!/usr/bin/env node
// Interactions show at once over a slow link, against `share.sh ensure-running` with the fake cloudflared. Every /api/*
// request of the acting guest waits 600 ms first, as over a quick tunnel; a Gather reaction, a Decide vote, a choice,
// multi, scale and rank pick, a Disagree, a chat reaction and a chat message must each show on that guest's page in
// under 100 ms and stay shown while the server catches up. A refused reaction (409) rolls back with the error toast,
// and a reaction taken back at once ends with that reaction gone on the server.
//   node plugins/planning/shared/tests/ui_snappy.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values: the 100 ms and 600 ms bounds come from the dogfood brief; the texts and picks are the ones this
// suite writes; the toast's words are the "locked" entry of core.js MESSAGES behind fail()'s "Not saved:".
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const DELAY = 600, FAST = 100;
const q = (id, text, format, purpose = "decide") => ({ id, text, alternatives: [], dependsOn: [], purpose, format });
const OPTS = [{ id: "opt-1", label: "Card" }, { id: "opt-2", label: "PayPal" }, { id: "opt-3", label: "Cash" }];
const GATHER = "Owner gather idea", DECIDE = "Owner decide answer", HELLO = "Owner says hello", MINE = "Gus writes back";

/** In the page: ms from just before act() to the first frame where done() holds (-1 past `ms`), and whether
 *  done() then holds on every frame for `hold` ms more (a stale poll would flip it back). */
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
  window.__card = text => [...document.querySelectorAll(".vf-alist .vf-card")].find(c => c.textContent.includes(text));
  window.__msg = text => [...document.querySelectorAll(".vf-mlist .vf-msg")].find(m => m.textContent.includes(text));
}

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_snappy.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_snappy"), { ok } = s, rec = recorder(browser);
  const timings = [];
  try {
    const A = await s.start("snappy");
    s.apply(A.dir, [{ op: "set-title", title: "Snappy checks" }, { op: "open-round", questions: [
      q("Q1", "What worries you about checkout?", { kind: "text" }, "gather"),
      q("Q2", "Who should own checkout?", { kind: "text" }),
      q("Q3", "Which default payment method?", { kind: "choice", options: OPTS }),
      q("Q4", "Which payment methods to offer?", { kind: "multi", options: OPTS }),
      q("Q5", "How urgent is the redesign?", { kind: "scale", min: 1, max: 5, labels: { min: "Not urgent", max: "Very urgent" } }),
      q("Q6", "Rank the payment methods", { kind: "rank", options: OPTS }),
    ] }]);
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    await owner.evaluate(([a, b]) => window.Core.answerCiting("Q1", a, []).then(() => window.Core.answerCiting("Q2", b, [])), [GATHER, DECIDE]);
    await owner.evaluate(t => window.Core.chat(t), HELLO);

    const gus = await rec.open(A.localUrl, { init: { fn: helpers } });
    const gusPid = await joinAs(gus, "Gus");
    await until(gus, () => (window.Core.snapshot()?.chat || []).length > 0 && Object.keys(window.Core.snapshot()?.cards || {}).length >= 2);
    // From here on every request of Gus's page waits DELAY ms before it goes out, as over a quick tunnel.
    await gus.route(/\/api\//, async route => { await new Promise(r => setTimeout(r, DELAY)); await route.continue().catch(() => {}); });
    const go = async text => { await gus.locator(".vf-q", { hasText: text }).first().click(); return until(gus, t => document.querySelector(".vf-qtext")?.textContent === t, text); };
    const fast = (what, r) => {
      timings.push(`${what}: ${r.ms < 0 ? "never" : `${Math.round(r.ms)} ms`}`);
      ok(`${what} shows in under ${FAST} ms with every request delayed ${DELAY} ms, and stays shown`, r.ms >= 0 && r.ms < FAST && r.steady, `${Math.round(r.ms)} ms, steady ${r.steady}`);
    };
    const server = (fn, arg, t = 10000) => until(owner, fn, arg, t);

    // ---------- Gather: a reaction ----------
    await go("What worries you about checkout?");
    await until(gus, t => !!window.__card(t), GATHER);
    fast("a Gather reaction", await gus.evaluate(t => window.__time(() => window.__card(t).querySelector(".vf-react[data-r=thumbs]").click(),
      () => { const b = window.__card(t).querySelector(".vf-react[data-r=thumbs]"); return b.getAttribute("aria-pressed") === "true" && b.lastChild.textContent === "1"; }, 8000, 3000), GATHER));
    ok("the reaction reaches the server", await server(() => window.Core.snapshot().cards.Q1.find(c => c.ref === "p:host")?.reactions?.thumbs === 1));

    // ---------- a refused reaction rolls back and says why ----------
    await gus.route("**/api/react", route => route.fulfill({ status: 409, contentType: "application/json", body: JSON.stringify({ error: "locked" }) }), { times: 1 });
    const refused = await gus.evaluate(t => window.__time(() => window.__card(t).querySelector(".vf-react[data-r=heart]").click(),
      () => window.__card(t).querySelector(".vf-react[data-r=heart]").getAttribute("aria-pressed") === "true"), GATHER);
    ok("a refused reaction still shows at once", refused.ms >= 0 && refused.ms < FAST, `${Math.round(refused.ms)} ms`);
    ok("then rolls back to the server's state with the error toast", await until(gus, t => {
      const c = window.__card(t), b = r => c.querySelector(`.vf-react[data-r=${r}]`);
      return b("heart").getAttribute("aria-pressed") === "false" && b("thumbs").getAttribute("aria-pressed") === "true" && b("heart").lastChild.textContent === ""
        && /Not saved: This question was locked\. Suggest a change instead\./.test(document.querySelector(".vf-toast")?.textContent || "");
    }, GATHER));

    // ---------- react, then take it back at once ----------
    await gus.evaluate(t => { const b = window.__card(t).querySelector(".vf-react[data-r=heart]"); b.click(); b.click(); }, GATHER);
    // Reactions combine (triage row 45): the 👍 from before stays, and the ❤️ taken back at once is not there.
    const onlyThumbs = () => { const r = window.Core.snapshot().cards.Q1.find(c => c.ref === "p:host")?.reactions || {}; return r.thumbs === 1 && r.down + r.heart + r.idea === 0; };
    ok("react then un-react at once ends with that reaction gone on the server", await server(onlyThumbs) && await owner.waitForTimeout(2500).then(() => owner.evaluate(onlyThumbs)));
    ok("and gone on the page, the earlier one kept", await until(gus, t => [...window.__card(t).querySelectorAll(".vf-react")].map(b => b.getAttribute("aria-pressed")).join() === "true,false,false,false", GATHER));

    // ---------- Decide: a vote and a Disagree ----------
    await go("Who should own checkout?");
    await until(gus, t => !!window.__card(t), DECIDE);
    fast("a Decide vote", await gus.evaluate(t => window.__time(() => window.__card(t).querySelector(".vf-vote").click(),
      () => { const v = window.__card(t).querySelector(".vf-vote"); return v.getAttribute("aria-pressed") === "true" && v.children[1].textContent === "1"; }, 8000, 3000), DECIDE));
    ok("the vote reaches the server", await server(() => (window.Core.snapshot().cards.Q2.find(c => c.ref === "p:host")?.votes || []).length === 1));
    await gus.evaluate(t => window.__card(t).querySelector(".vf-disagree-btn").click(), DECIDE);
    await gus.locator(".vf-dis-in").fill("Ownership should sit with payments");
    fast("a Disagree", await gus.evaluate(t => window.__time(() => window.__card(t).querySelector(".vf-dis-send").click(),
      () => { const c = window.__card(t); return c.querySelector(".vf-disform").hidden && /You disagree:Ownership should sit with payments/.test(c.querySelector(".vf-dislist").textContent); }, 8000, 3000), DECIDE));
    ok("the disagreement reaches the server", await server(() => (window.Core.snapshot().disagreements?.Q2 || []).some(d => d.reason === "Ownership should sit with payments")));

    // ---------- picks: choice, multi, scale, rank ----------
    await go("Which default payment method?");
    fast("a choice pick", await gus.evaluate(() => window.__time(() => [...document.querySelectorAll(".vf-opt")].find(o => o.textContent.includes("PayPal")).querySelector(".vf-optchoose").click(),
      () => [...document.querySelectorAll(".vf-opt")].find(o => o.textContent.includes("PayPal")).querySelector(".vf-optchoose").getAttribute("aria-pressed") === "true", 8000, 3000)));
    ok("the choice reaches the server", await server(p => (window.Core.snapshot().cards.Q3.find(c => c.ref === "o:opt-2")?.votes || []).includes(p), gusPid));

    await go("Which payment methods to offer?");
    for (const label of ["Card", "Cash"]) await gus.locator(".vf-check-row", { hasText: label }).locator("input").check();
    fast("a multi pick saved", await gus.evaluate(() => window.__time(() => document.querySelector(".vf-fmt-save").click(),
      () => /^You picked 2\./.test(document.querySelector(".vf-fmt-note").textContent), 8000, 3000)));
    ok("the multi pick reaches the server", await server(p => JSON.stringify(window.Core.snapshot().cards.Q4.find(c => c.ref === "p:" + p)?.picks) === '["opt-1","opt-3"]', gusPid));

    await go("How urgent is the redesign?");
    fast("a scale pick", await gus.evaluate(() => window.__time(() => [...document.querySelectorAll(".vf-scale-btn")].find(b => b.textContent === "4").click(),
      () => /^You chose 4\./.test(document.querySelector(".vf-fmt-note").textContent), 8000, 3000)));
    ok("the scale pick reaches the server", await server(p => window.Core.snapshot().cards.Q5.find(c => c.ref === "p:" + p)?.value === 4, gusPid));

    await go("Rank the payment methods");
    await gus.locator(".vf-rank-item", { hasText: "Cash" }).locator(".vf-rank-up").click();
    fast("a rank saved", await gus.evaluate(() => window.__time(() => document.querySelector(".vf-fmt-save").click(),
      () => /^Your ranking is saved\./.test(document.querySelector(".vf-fmt-note").textContent), 8000, 3000)));
    ok("the ranking reaches the server", await server(p => JSON.stringify(window.Core.snapshot().cards.Q6.find(c => c.ref === "p:" + p)?.order) === '["opt-1","opt-3","opt-2"]', gusPid));

    // ---------- chat: a reaction and a message ----------
    await gus.click(".vf-fab");
    await until(gus, t => !!window.__msg(t), HELLO);
    await gus.evaluate(t => window.__msg(t).querySelector(".vf-mreact-add").click(), HELLO);
    await until(gus, () => !document.querySelector(".vf-reactpop").hidden);
    fast("a chat reaction", await gus.evaluate(t => window.__time(() => [...document.querySelectorAll(".vf-rp-quick .vf-rp-e")].find(b => b.dataset.e === "👍").click(),
      () => window.__msg(t)?.querySelector(".vf-mreact")?.textContent === "👍1", 8000, 3000), HELLO));
    ok("the chat reaction reaches the server", await server(() => (window.Core.snapshot().chat.find(m => m.text === "Owner says hello")?.reactions?.["👍"] || []).length === 1));
    await gus.locator(".vf-minput").fill(MINE);
    fast("a chat message", await gus.evaluate(t => window.__time(() => document.querySelector(".vf-mform button[type=submit]").click(),
      () => !!window.__msg(t) && document.querySelector(".vf-minput").value === "", 8000, 3000), MINE));
    ok("the chat message reaches the server once", await server(t => window.Core.snapshot().chat.filter(m => m.text === t).length === 1, MINE));
    ok("and shows once on the sender's page", await gus.waitForTimeout(2000).then(() => gus.evaluate(t => [...document.querySelectorAll(".vf-mlist .vf-msg")].filter(m => m.textContent.includes(t)).length === 1, MINE)));

    ok("no 429 from the server", rec.too.length === 0, rec.too.join(", "));
    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    ok("no page error", rec.errors.filter(m => !/Failed to load resource/.test(m)).length === 0, rec.errors.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  console.log(`timings (click to visible, ${DELAY} ms per request): ${timings.join("; ")}`);
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
