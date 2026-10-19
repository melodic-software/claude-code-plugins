#!/usr/bin/env node
// Your reports (follow-up item 3), against `share.sh ensure-running` with the fake cloudflared: on a 390x844 phone,
// More holds "Your reports" once the person has filed one; it lists their reports in this session with Sent, Seen by
// the host or Fixed; while one is not fixed they add a line and a screenshot (re-encoded as Report a problem does),
// which the owner's Problem item shows; a seen report waits again once added to; a fixed one takes no more; another
// guest never sees it, and on a desktop Help holds the same entry.
//   node plugins/planning/shared/tests/ui_myreports.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the approved spec (follow-up item 3) and the texts and bytes this suite makes, never from
// the page.
"use strict";
const { loadPlaywright, suite, recorder, until, snap, joinAs, png } = require("./browser_harness");

const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });
const PHONE = { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true };
const FIRST = "Send does nothing on the payment question", LINE = "It also happens after a reload";

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_myreports.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_myreports"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("myreports");
    s.apply(A.dir, [{ op: "set-title", title: "Checkout" }, { op: "open-round", questions: [q("Q1", "Where should the order summary sit?")] }]);
    const desk = { context: { viewport: { width: 1440, height: 900 } } };
    const owner = await rec.open(A.ownerUrl, desk);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const pia = await rec.open(A.localUrl, { context: PHONE });
    await joinAs(pia, "Pia");
    const bo = await rec.open(A.localUrl, desk);
    await joinAs(bo, "Bo");
    const more = async () => { await pia.locator(".vf-tab", { hasText: "More" }).tap(); return until(pia, () => !!document.querySelector(".vf-moresheet:not([hidden])")); };
    const entry = page => page.evaluate(() => [...document.querySelectorAll(".vf-msitem, .vf-help-myreps")].some(b => /^Your reports/.test(b.textContent) && b.getClientRects().length && !b.hidden));
    const status = () => pia.evaluate(() => document.querySelector(".vf-myreps:not([hidden]) .vf-myrep .vf-myrep-status")?.textContent || "");
    const ownerReport = () => owner.evaluate(() => (window.Core.snapshot()?.reports || [])[0]);

    // ---------- nothing filed: no entry ----------
    await more();
    ok("before any report, More has no Your reports", !(await entry(pia)));
    await pia.keyboard.press("Escape");

    // ---------- file one, then More -> Your reports lists it as Sent ----------
    await pia.evaluate(t => window.Core.report(t, window.Core.reportContext()), FIRST);
    await more();
    ok("once one is filed, More has Your reports", await until(pia, () => [...document.querySelectorAll(".vf-msitem")].some(b => /^Your reports/.test(b.textContent) && !b.hidden)));
    await pia.locator(".vf-msitem", { hasText: "Your reports" }).tap();
    ok("Your reports lists it with its text and Sent", await until(pia, t => {
      const li = document.querySelector(".vf-myreps:not([hidden]) .vf-myrep");
      return !!li && li.querySelector(".vf-myrep-text").textContent === t && li.querySelector(".vf-myrep-status").textContent === "Sent";
    }, FIRST));
    ok("it says only Pia and the host see it", /Only you and the host see these\./.test(await pia.textContent(".vf-myreps")));

    // ---------- the owner's Seen shows as Seen by the host ----------
    const fid = (await ownerReport())?.id;
    await owner.evaluate(id => window.Core.reportAct(id, "seen"), fid);
    ok("the owner's Seen shows as Seen by the host", await until(pia, () => document.querySelector(".vf-myreps .vf-myrep-status")?.textContent === "Seen by the host"), await status());

    // ---------- add a line: the owner sees it, and the report waits again ----------
    await pia.locator(".vf-myrep textarea").fill(LINE);
    await pia.locator(".vf-myrep-add button[type=submit]").tap();
    ok("the added line shows under the report", await until(pia, t => [...document.querySelectorAll(".vf-myrep-adds li")].some(li => li.textContent === t), LINE));
    ok("a seen report goes back to Sent once added to", await until(pia, () => document.querySelector(".vf-myreps .vf-myrep-status")?.textContent === "Sent"), await status());
    ok("the owner's report carries the line and waits again", await until(owner, t => { const r = (window.Core.snapshot()?.reports || [])[0]; return r?.status === "open" && r.adds?.[0]?.text === t; }, LINE));
    await owner.locator(".vf-seg-btn", { hasText: /^Host$/ }).click();
    ok("the owner's Problem item shows the line", await until(owner, t => [...document.querySelectorAll(".vf-rep-adds li")].some(li => li.textContent.includes(t)), LINE));

    // ---------- add a screenshot: re-encoded, the owner reads it back ----------
    await pia.waitForTimeout(1200); // one addition a second
    await pia.locator(".vf-myrep input[type=file]").setInputFiles({ name: "shot.png", mimeType: "image/png", buffer: png(3200, 1800, [800, 1000]) });
    await until(pia, () => !document.querySelector(".vf-myrep .vf-rep-shot").hidden);
    await pia.locator(".vf-myrep-add button[type=submit]").tap();
    ok("the screenshot shows as added", await until(pia, () => [...document.querySelectorAll(".vf-myrep-adds li")].some(li => li.textContent === "Screenshot added")));
    const shot = await owner.evaluate(async id => {
      for (let i = 0; i < 50 && !(window.Core.snapshot()?.reports || [])[0]?.adds?.[1]?.image; i++) await new Promise(r => setTimeout(r, 100));
      const src = await window.Core.reportImage(id, 2);
      const im = new Image(); im.src = src; await im.decode();
      return { w: im.naturalWidth, h: im.naturalHeight, kind: src.slice(0, 15) };
    }, fid);
    ok("the owner reads the added screenshot back at 1600 px", shot.w === 1600 && shot.h === 900 && /^data:image\/(webp|jpeg)/.test(shot.kind), JSON.stringify(shot));

    // ---------- only the reporter and the owner ----------
    const boSees = await bo.evaluate(() => JSON.stringify(window.Core.snapshot()));
    ok("another guest's page never holds the report", !boSees.includes(FIRST) && !boSees.includes(LINE) && !(await entry(bo)));

    // ---------- Fixed: no more additions ----------
    await owner.evaluate(id => window.Core.reportAct(id, "resolved"), fid);
    ok("the owner's Resolved shows as Fixed", await until(pia, () => document.querySelector(".vf-myreps .vf-myrep-status")?.textContent === "Fixed"), await status());
    ok("a fixed report takes no more additions", await until(pia, () => document.querySelector(".vf-myrep-add").hidden));

    // ---------- on a desktop, Help holds the same entry ----------
    await bo.evaluate(() => window.Core.report("The chat jumps", window.Core.reportContext()));
    await bo.click(".vf-keysbtn");
    ok("on a desktop, Help has Your reports once one is filed", await until(bo, () => { const b = document.querySelector(".vf-help-myreps"); return !!b && !b.hidden && b.getClientRects().length > 0; }));
    await bo.click(".vf-help-myreps");
    ok("it lists only Bo's own report", await until(bo, () => [...document.querySelectorAll(".vf-myreps .vf-myrep-text")].map(e => e.textContent).join("|") === "The chat jumps"));
    const sn = await snap(bo);
    ok("Bo's snapshot lists only his own report", sn.myReports.length === 1 && sn.myReports[0].text === "The chat jumps", JSON.stringify(sn.myReports));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
