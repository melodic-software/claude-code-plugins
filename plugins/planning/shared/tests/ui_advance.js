#!/usr/bin/env node
// "Go to the next question after I answer" (follow-up item 1), against `share.sh ensure-running` with the fake
// cloudflared: the switch sits in the person's own settings, off by default, and is kept with their other
// preferences on the server; with it on, a single pick, a confirm or a scale value with the comment box empty shows
// "Next question in 2 s · Stay" and moves on; Stay cancels; a pick-many, a rank or a written answer never moves on,
// and neither does a pick with a comment written, an Undo, a field being typed in, a move elsewhere or following the
// host; with it off nothing moves. A move lands on the next question still open for me in the round's order.
//   node plugins/planning/shared/tests/ui_advance.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the approved spec (follow-up item 1) and the texts this suite writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs, png } = require("./browser_harness");

const q = (id, text, format) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format });
const opts = (...labels) => labels.map((label, i) => ({ id: `opt-${i + 1}`, label }));
const QS = [
  q("Q1", "Which default payment method?", { kind: "choice", options: opts("Card", "Saved method") }),
  q("Q2", "Which payment methods should checkout offer?", { kind: "multi", options: opts("Card", "PayPal", "Apple Pay") }),
  q("Q3", "Where should the order summary sit?", { kind: "text" }),
  q("Q4", "How urgent is the checkout redesign?", { kind: "scale", min: 1, max: 5, labels: { min: "Not urgent", max: "Very urgent" } }),
  q("Q5", "Rank the checkout steps by importance", { kind: "rank", options: opts("Address", "Shipping", "Payment") }),
  q("Q6", "Which receipt layout?", { kind: "choice", options: opts("Short", "Long") }),
  q("Q7", "Did you mean this button?", { kind: "confirm", image: "", rect: { x: 10, y: 10, w: 30, h: 20 } }),
  q("Q8", "Which shipping default?", { kind: "choice", options: opts("Standard", "Express") }),
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
    const shot = s.asset(A.dir, "shot.png", png(400, 300));
    s.apply(A.dir, [{ op: "set-title", title: "Checkout" }, { op: "open-round", questions: QS.map(x => x.id === "Q7" ? { ...x, format: { ...x.format, image: shot } } : x) }]);
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
    ok("then it moves to Q7, the next question still open for me", await until(ann, t => document.querySelector(".vf-qtext")?.textContent === t, textOf("Q7"), 4000)
      && !(await bar()), await cur());

    // ---------- Undo within the 2 s stays ----------
    await go("Q7");
    await ann.locator(".vf-pickbtn", { hasText: "Yes" }).click();
    await until(ann, () => !!document.querySelector(".vf-advance:not([hidden])"));
    await ann.locator(".vf-optundo:visible", { hasText: "Undo" }).click();
    const undone = await until(ann, () => !(window.Core.snapshot()?.cards?.Q7 || []).some(c => c.pid === window.Core.me.cid && c.pick));
    ok("a confirm Yes then Undo within 2 s stays", undone && await stays("Q7"), `${await cur()} / undone ${undone}`);

    // ---------- typing in Ask Claude stays, and keeps what was typed ----------
    await pickOn("Q8", "Standard");
    await until(ann, () => !!document.querySelector(".vf-advance:not([hidden])"));
    await ann.click(".vf-askbtn");
    await ann.locator("#vf-ask-ta").pressSequentially("Is Express worth it?", { delay: 20 });
    ok("a pick, then typing in Ask Claude, stays with the Ask Claude form open", await stays("Q8")
      && await ann.evaluate(() => !document.querySelector(".vf-askform").hidden && document.getElementById("vf-ask-ta").value === "Is Express worth it?"), await cur());
    await ann.evaluate(() => { const f = document.querySelector(".vf-askform"); if (!f.hidden) f.querySelector(".vf-btn-ghost").click(); });

    // ---------- moving elsewhere cancels ----------
    await pickOn("Q8", "Express");
    await until(ann, () => !!document.querySelector(".vf-advance:not([hidden])"));
    await go("Q3");
    ok("a pick, then opening Q3 by hand, stays on Q3", await stays("Q3"), await cur());

    // ---------- following the host: no move, still following ----------
    await owner.locator(".vf-q", { hasText: textOf("Q6") }).first().click();
    await until(ann, () => (window.Core.state.presence || []).some(p => p.cid === window.Core.state.ownerPid && p.q === "Q6"));
    await ann.click(".vf-follow");
    await until(ann, t => document.querySelector(".vf-qtext")?.textContent === t, textOf("Q6"));
    await ann.locator(".vf-opt", { hasText: "Long" }).locator(".vf-optchoose").click();
    const pickedQ6 = await until(ann, () => (window.Core.snapshot()?.cards?.Q6 || []).some(c => c.pid === window.Core.me.cid && c.pick === "opt-2"));
    ok("while following the host a pick stays and keeps following", pickedQ6 && await stays("Q6") && (await ann.getAttribute(".vf-follow", "aria-pressed")) === "true",
      `${await cur()} / following ${await ann.getAttribute(".vf-follow", "aria-pressed")}`);
    await ann.click(".vf-follow");

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
    ok("a scale value moves on to Q5, the next question still open for me", await until(ann, t => document.querySelector(".vf-qtext")?.textContent === t, textOf("Q5"), 5000), await cur());

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

    // ---------- a filter that hides the only other open question: no countdown, no move ----------
    // Bo answers Q1 and Q6 with the switch off, then shows only his own questions (the full toolbar, filter Mine): Q1 and
    // Q6 are listed, both answered, and the open ones are filtered out. Changing his pick on Q1 has nowhere to go.
    const bo = await rec.open(A.localUrl, desk);
    await joinAs(bo, "Bo");
    const boPick = async (id, label) => {
      await bo.locator(".vf-q", { hasText: textOf(id) }).first().click();
      await until(bo, t => document.querySelector(".vf-qtext")?.textContent === t, textOf(id));
      await bo.locator(".vf-opt", { hasText: label }).locator(".vf-optchoose").click();
      return until(bo, ([q, o]) => (window.Core.snapshot()?.cards?.[q] || []).some(c => c.pid === window.Core.me.cid && c.pick === o), [id, label === "Card" || label === "Short" ? "opt-1" : "opt-2"]);
    };
    const boReady = await boPick("Q1", "Card") && await boPick("Q6", "Short");
    await bo.evaluate(() => window.Core.savePrefs({ toolbar: "full", filter: "mine", autoAdvance: true }));
    const listed = await until(bo, () => { const qs = [...document.querySelectorAll(".vf-rail .vf-q")].filter(e => e.getClientRects().length).map(e => e.textContent); return qs.length === 2; }, null, 8000);
    const moved = await boPick("Q1", "Saved method");
    await bo.waitForTimeout(400);
    const boBar = await bo.evaluate(() => { const b = document.querySelector(".vf-advance"); return !!b && !b.hidden; });
    await bo.waitForTimeout(2200);
    const boAt = await bo.evaluate(() => document.querySelector(".vf-qtext")?.textContent || "");
    ok("with a filter hiding every other open question, a single pick shows no countdown and stays",
      boReady && listed && moved && !boBar && boAt === textOf("Q1"), JSON.stringify({ boReady, listed, moved, boBar, boAt }));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
