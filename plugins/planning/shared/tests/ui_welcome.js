#!/usr/bin/env node
// The first-join welcome card (follow-up item 6), against `share.sh ensure-running` with the fake cloudflared: a new
// guest's first view opens with the welcome card, its first line "Enter your name to join, then answer this round's
// questions.", the session goal and the first step, and a visible Skip; Skip closes the card and the tour offer at
// once (the `tour` pref says skipped) and the card stays closed after a reload on that device; "Show the tour again"
// in the person's settings brings the card and the tour offer back; on a 390x844 phone Skip is a whole 44 px target.
// Also: the goal in one closable line on a return visit (follow-up 39), About you in the person's card, read only by
// the owner (follow-up 46), and the in-app browser banner in Instagram's browser (follow-up 45).
//   node plugins/planning/shared/tests/ui_welcome.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the approved spec (follow-up item 6) and the texts this suite writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });
const GOAL = "Settle the checkout layout before the sprint";
const LEAD = "Enter your name to join, then answer this round's questions.";
const shown = () => { const c = document.querySelector(".vf-orient"); return !!c && !c.hidden && c.getClientRects().length > 0; };

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_welcome.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_welcome"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("welcome");
    s.apply(A.dir, [{ op: "set-title", title: "Checkout" }, { op: "set-goal", goal: GOAL },
      { op: "open-round", questions: [q("Q1", "Where should the order summary sit?"), q("Q2", "What should the receipt say?")] }]);
    const desk = { context: { viewport: { width: 1440, height: 900 } } };
    const owner = await rec.open(A.ownerUrl, desk);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const ann = await rec.open(A.localUrl, desk);
    await joinAs(ann, "Ann");

    // ---------- shown by default on the first view ----------
    ok("a new guest's first view opens with the welcome card", await until(ann, shown));
    const card = await ann.evaluate(() => {
      const c = document.querySelector(".vf-orient"), lead = c.querySelector(".vf-orient-lead"), h = c.querySelector(".vf-orient-h"), skip = c.querySelector(".vf-orient-x");
      const lines = [...c.querySelectorAll("p, h2")].filter(e => e.getClientRects().length && e.textContent.trim()).sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top);
      return { first: lines[0]?.textContent, leadAboveHeading: !!lead && lead.getBoundingClientRect().bottom <= h.getBoundingClientRect().top + 1, text: c.textContent,
        start: c.querySelector(".vf-orient-start")?.textContent, skip: skip?.textContent, skipShown: !!skip && skip.getClientRects().length > 0 };
    });
    ok("its first line is \"Enter your name to join, then answer this round's questions.\"", card.first === LEAD && card.leadAboveHeading, JSON.stringify(card));
    ok("it shows the session goal and the first step", card.text.includes(`Goal: ${GOAL}`) && card.start === "Start here: question 1", JSON.stringify(card));
    ok("it shows a visible Skip", card.skip === "Skip" && card.skipShown, JSON.stringify(card));
    ok("it offers the optional tour after it", await until(ann, () => { const t = document.querySelector(".vf-orient-tour"); return !!t && !t.hidden && t.textContent === "Show me around"; }));

    // ---------- Skip closes the card and the tour at once ----------
    await ann.click(".vf-orient-x");
    ok("Skip closes the card", await until(ann, () => document.querySelector(".vf-orient").hidden));
    ok("Skip closes the tour too: the tour pref says skipped and no tour shows", await until(ann, () => window.Core.snapshot()?.me?.prefs?.tour === "skipped", null, 5000)
      && await ann.evaluate(() => document.querySelector(".vf-tour").hidden));
    const goalLine = page => page.evaluate(() => { const g = document.querySelector(".vf-goalback"); return g && !g.hidden && g.getClientRects().length > 0 ? g.querySelector(".vf-goalback-t").textContent : ""; });
    ok("follow-up 39: the first visit shows no goal line after Skip", (await goalLine(ann)) === "", await goalLine(ann));

    // ---------- once per person per device ----------
    await ann.reload();
    await until(ann, () => !!window.Core.snapshot()?.me && !!document.querySelector(".vf-qtext")?.textContent);
    await ann.waitForTimeout(1000);
    ok("after a reload on this device the card stays closed", !(await ann.evaluate(shown)));
    ok("follow-up 39: a return visit shows the goal in one line", await until(ann, g => document.querySelector(".vf-goalback-t")?.textContent === `Goal: ${g}` && !document.querySelector(".vf-goalback").hidden, GOAL), await goalLine(ann));
    await ann.click(".vf-goalback-x");
    ok("  its close button hides it", await until(ann, () => document.querySelector(".vf-goalback").hidden));
    await ann.reload();
    await until(ann, () => !!window.Core.snapshot()?.me && !!document.querySelector(".vf-qtext")?.textContent);
    await ann.waitForTimeout(1000);
    ok("  and it stays hidden for the rest of this visit", (await goalLine(ann)) === "", await goalLine(ann));
    const ann2 = await ann.context().newPage();
    await ann2.goto(ann.url());
    ok("  a new visit shows it again", await until(ann2, g => document.querySelector(".vf-goalback-t")?.textContent === `Goal: ${g}` && !document.querySelector(".vf-goalback").hidden, GOAL, 10000), await goalLine(ann2));
    await ann2.close();

    // ---------- Show the tour again ----------
    await ann.click(".vf-person-me");
    await until(ann, () => !!document.querySelector(".vf-pcard .vf-tour-again"));
    ok("my settings hold \"Show the tour again\"", (await ann.textContent(".vf-pcard .vf-tour-again")).trim() === "Show the tour again");
    // ---------- follow-up 46: About you, optional, for the owner only ----------
    ok("my card offers About you, optional", await ann.evaluate(() => /About you \(optional/.test(document.querySelector(".vf-pcard").textContent) && !!document.querySelector(".vf-pcard .vf-about")));
    await ann.fill(".vf-pcard .vf-about-note", "I use a screen reader");
    await ann.locator(".vf-pcard .vf-about .vf-seg-btn", { hasText: "Not very" }).click();
    ok("  picking one saves it with the note", await until(owner, () => Object.values(window.Core.snapshot()?.aboutYou || {}).some(a => a.techComfort === "low" && a.note === "I use a screen reader"), null, 8000),
      JSON.stringify(await owner.evaluate(() => window.Core.snapshot()?.aboutYou)));
    ok("  and my card shows my pick", await until(ann, () => document.querySelector('.vf-pcard .vf-about [aria-pressed="true"]')?.textContent === "Not very"));
    const ownerHost = async () => { const b = owner.locator(".vf-bar .vf-seg-btn", { hasText: "Host" }), more = owner.locator(".vf-viewopts"); if (!(await b.isVisible()) && (await more.isVisible())) await more.click(); await b.click(); };
    await ownerHost();
    ok("  the owner's Host view shows it on Ann's row", await until(owner, () => [...document.querySelectorAll(".vf-hp-meta")].some(m => m.textContent.endsWith("Tech comfort: Not very, “I use a screen reader”")), null, 8000),
      await owner.evaluate(() => [...document.querySelectorAll(".vf-hp-meta")].map(m => m.textContent).join(" | ")));
    ok("  and no guest snapshot holds anyone's", await ann.evaluate(() => !("aboutYou" in window.Core.snapshot())));
    await ann.click(".vf-pcard .vf-tour-again");
    ok("it brings the welcome card back", await until(ann, shown));
    ok("and the tour offer: the tour pref is cleared", await until(ann, () => !("tour" in (window.Core.snapshot()?.me?.prefs || {})) && !document.querySelector(".vf-orient-tour").hidden, null, 5000));

    // ---------- a phone: Skip is a whole target ----------
    const pia = await rec.open(A.localUrl, { context: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true } });
    await joinAs(pia, "Pia");
    await until(pia, shown);
    const skip = await pia.evaluate(() => { const r = document.querySelector(".vf-orient-x").getBoundingClientRect(); return { h: r.height, w: r.width, in: r.left >= 0 && r.right <= innerWidth }; });
    ok("on a 390x844 phone Skip is at least 44 px and inside the screen", skip.h >= 44 && skip.w >= 44 && skip.in, JSON.stringify(skip));
    await pia.locator(".vf-orient-x").tap();
    ok("on a phone Skip closes it too", await until(pia, () => document.querySelector(".vf-orient").hidden));

    // ---------- follow-up 45: Instagram's in-app browser gets a banner that never blocks the page ----------
    const IG_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 339.0.3.12.91 (iPhone14,5; iOS 17_5; en_US; en; scale=3.00; 1170x2532; 618423011)";
    const ig = await rec.open(A.localUrl, { context: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, userAgent: IG_UA } });
    const banner = () => ig.evaluate(() => { const b = document.querySelector(".vf-banner"); return b && !b.hidden ? b.querySelector(".vf-banner-txt").textContent + " | " + b.querySelector("button").textContent : ""; });
    await joinAs(ig, "Ig");
    ok("in Instagram's browser a banner says to open the page in Safari, with Copy link", await until(ig, () => /in Instagram's browser.*open this page in Safari/.test(document.querySelector(".vf-banner:not([hidden]) .vf-banner-txt")?.textContent || "")
      && document.querySelector(".vf-banner button").textContent === "Copy link"), await banner());
    ok("  and the page still works under it: the question and the answer box are there", await ig.evaluate(() => !!document.querySelector(".vf-qtext")?.textContent && !document.getElementById("vf-answer").disabled));
    await ig.locator(".vf-banner button", { hasText: "Copy link" }).tap();
    ok("  Copy link closes it", await until(ig, () => document.querySelector(".vf-banner").hidden), await banner());
    ok("  a regular browser never gets it", await pia.evaluate(() => !/in-app|browser\. For pictures/.test(document.querySelector(".vf-banner:not([hidden])")?.textContent || "")));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
