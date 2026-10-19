#!/usr/bin/env node
// "Go to the next question after I answer" (follow-up item 1), against `share.sh ensure-running` with the fake
// cloudflared: the switch sits in the person's own settings, off by default, and is kept with their other
// preferences on the server; with it on, a single pick, a confirm or a scale value with the comment box empty shows
// "Next question in 2 s · Stay" and moves on; Stay cancels; a pick-many, a rank or a written answer never moves on,
// and neither does a pick with a comment written; with it off nothing moves.
//   node plugins/planning/shared/tests/ui_advance.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the approved spec (follow-up item 1) and the texts this suite writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const q = (id, text, format) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format });
const opts = (...labels) => labels.map((label, i) => ({ id: `opt-${i + 1}`, label }));
const QS = [
  q("Q1", "Which default payment method?", { kind: "choice", options: opts("Card", "Saved method") }),
  q("Q2", "Which payment methods should checkout offer?", { kind: "multi", options: opts("Card", "PayPal", "Apple Pay") }),
  q("Q3", "Where should the order summary sit?", { kind: "text" }),
  q("Q4", "How urgent is the checkout redesign?", { kind: "scale", min: 1, max: 5, labels: { min: "Not urgent", max: "Very urgent" } }),
  q("Q5", "Rank the checkout steps by importance", { kind: "rank", options: opts("Address", "Shipping", "Payment") }),
  q("Q6", "Which receipt layout?", { kind: "choice", options: opts("Short", "Long") }),
];
const textOf = id => QS.find(x => x.id === id).text;

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_advance.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_advance"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("advance");
    s.apply(A.dir, [{ op: "set-title", title: "Checkout" }, { op: "open-round", questions: QS }]);
    const desk = { context: { viewport: { width: 1440, height: 900 } } };
    const owner = await rec.open(A.ownerUrl, desk);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const ann = await rec.open(A.localUrl, desk);
    await joinAs(ann, "Ann");
    const cur = () => ann.evaluate(() => document.querySelector(".vf-qtext")?.textContent || "");
    const go = async id => { await ann.locator(".vf-q", { hasText: textOf(id) }).first().click(); return until(ann, t => document.querySelector(".vf-qtext")?.textContent === t, textOf(id)); };
    const bar = () => ann.evaluate(() => { const b = document.querySelector(".vf-advance"); return b && !b.hidden && b.offsetParent ? b.textContent : ""; });
    const stays = async id => { await ann.waitForTimeout(2600); return (await cur()) === textOf(id) && !(await bar()); };
    const pickOn = async (id, label) => { await go(id); await ann.locator(".vf-opt", { hasText: label }).locator(".vf-optchoose").click(); };

    // ---------- the switch: in my own settings, off by default ----------
    await ann.click(".vf-person-me");
    const sw = ann.locator(".vf-pcard .vf-advsw");
    ok("my settings hold \"Go to the next question after I answer\", off by default",
      await until(ann, () => document.querySelector(".vf-pcard .vf-advsw")?.textContent === "Go to the next question after I answer")
      && (await sw.getAttribute("role")) === "switch" && (await sw.getAttribute("aria-checked")) === "false");

    // ---------- off: a single pick stays ----------
    await ann.keyboard.press("Escape");
    await pickOn("Q1", "Card");
    const pickedOff = await until(ann, () => (window.Core.snapshot()?.cards?.Q1 || []).some(c => c.pid === window.Core.me.cid && c.pick === "opt-1"));
    ok("off: a single pick stays on the question and shows no countdown", pickedOff && await stays("Q1"), `picked: ${pickedOff}`);

    // ---------- on: kept on the server with my other preferences ----------
    await ann.click(".vf-person-me");
    await sw.click();
    ok("turning it on checks the switch", (await sw.getAttribute("aria-checked")) === "true");
    ok("the server keeps it in my preferences", await until(ann, () => window.Core.snapshot()?.me?.prefs?.autoAdvance === true, null, 5000));
    await ann.keyboard.press("Escape");

    // ---------- a single pick moves on after showing Next question in 2 s · Stay ----------
    await pickOn("Q6", "Short");
    ok("a single pick with the comment box empty shows \"Next question in 2 s · Stay\"", await until(ann, () => {
      const b = document.querySelector(".vf-advance"); return !!b && !b.hidden && b.textContent === "Next question in 2 s·Stay" && b.querySelector("button")?.textContent === "Stay";
    }));
    ok("then it moves to the next question still open for me", await until(ann, t => document.querySelector(".vf-qtext")?.textContent !== t, textOf("Q6"), 4000)
      && (await cur()) !== textOf("Q6") && !(await bar()));

    // ---------- Stay cancels ----------
    await pickOn("Q1", "Saved method");
    await until(ann, () => !!document.querySelector(".vf-advance:not([hidden])"));
    await ann.click(".vf-advance-stay");
    ok("Stay cancels: the question stays and the countdown goes", await stays("Q1"));

    // ---------- a pick with a comment written stays ----------
    await go("Q1");
    await ann.fill("#vf-answer", "Card is what most people already have");
    await ann.locator(".vf-opt", { hasText: "Card" }).locator(".vf-optchoose").click();
    ok("a pick with something in the comment box stays", await stays("Q1"));

    // ---------- a scale value moves on ----------
    await go("Q4");
    await ann.locator(".vf-scale-btn", { hasText: "4" }).click();
    ok("a scale value moves on", await until(ann, t => document.querySelector(".vf-qtext")?.textContent !== t, textOf("Q4"), 5000));

    // ---------- never after pick-many, rank or a written answer ----------
    await go("Q2");
    await ann.locator(".vf-check", { hasText: "PayPal" }).click();
    await ann.click(".vf-fmt-save");
    const savedQ2 = await until(ann, () => (window.Core.snapshot()?.cards?.Q2 || []).some(c => c.pid === window.Core.me.cid));
    ok("pick-many never moves on", savedQ2 && await stays("Q2"), `saved: ${savedQ2}`);
    await go("Q5");
    await ann.click(".vf-fmt-save");
    const savedQ5 = await until(ann, () => (window.Core.snapshot()?.cards?.Q5 || []).some(c => c.pid === window.Core.me.cid));
    ok("rank never moves on", savedQ5 && await stays("Q5"), `saved: ${savedQ5}`);
    await go("Q3");
    await ann.fill("#vf-answer", "Under the total, always in view");
    await ann.keyboard.press("Control+Enter");
    const savedQ3 = await until(ann, () => (window.Core.snapshot()?.cards?.Q3 || []).some(c => c.pid === window.Core.me.cid));
    ok("a written answer never moves on", savedQ3 && await stays("Q3"), `saved: ${savedQ3}`);

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
