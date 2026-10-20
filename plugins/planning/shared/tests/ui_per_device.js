#!/usr/bin/env node
// A question asked once per device (answerScope "device", follow-up 47), against `share.sh ensure-running` with the
// fake cloudflared: a guest answers it on a computer, opens the session on a phone with their personal link, sees that
// they answered on their computer and are asked for this phone too, and answers again; the owner then reads one card
// per device, each named with its device. A phone turned to landscape is still the phone; a tablet is its own device.
//   node plugins/planning/shared/tests/ui_per_device.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from Q94 (one answer per device, a prompt on a new device) and the texts this suite writes,
// never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const Q = "Which device do you use for checkout?";
const Q2 = "How do you pay on this device?";

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_per_device.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_per_device"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("per-device");
    s.apply(A.dir, [{ op: "set-title", title: "Checkout" },
      { op: "open-round", questions: [{ id: "Q1", text: Q, alternatives: [], dependsOn: [], purpose: "gather", format: { kind: "text" }, answerScope: "device" },
        { id: "Q2", text: Q2, alternatives: [], dependsOn: [], purpose: "decide", answerScope: "device",
          format: { kind: "choice", options: [{ id: "opt-1", label: "Saved cards" }, { id: "opt-2", label: "A wallet" }] } }] }]);
    const owner = await rec.open(A.ownerUrl, { context: { viewport: { width: 1440, height: 900 } } });
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const ann = await rec.open(A.localUrl, { context: { viewport: { width: 1440, height: 900 } } });
    const annPid = await joinAs(ann, "Ann");
    await until(ann, () => !!document.querySelector(".vf-qtext")?.textContent);
    if (await ann.locator(".vf-orient-x").isVisible().catch(() => false)) await ann.click(".vf-orient-x");
    ok("on her computer nothing asks her again yet", await ann.evaluate(() => document.querySelector(".vf-devnote").hidden));
    await ann.fill("#vf-answer", "My laptop, mostly.");
    await ann.press("#vf-answer", "Control+Enter");
    ok("her answer is stored as the computer's", await until(owner, pid => (window.Core.snapshot()?.cards?.Q1 || []).some(c => c.pid === pid && c.device === "computer" && c.text === "My laptop, mostly."), annPid, 10000),
      JSON.stringify(await owner.evaluate(() => window.Core.snapshot()?.cards?.Q1)));

    const link = await ann.evaluate(() => window.Core.personalLink());
    const phone = await rec.open(link.replace(/^https?:\/\/[^/]+\//, A.localUrl), { context: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true } });
    await until(phone, pid => window.Core.snapshot()?.me?.pid === pid, annPid, 10000);
    ok("on her phone the question says she answered on her computer and asks for this phone too", await until(phone, () =>
      document.querySelector(".vf-devnote:not([hidden])")?.textContent === "You answered this on your computer. It asks for one answer per device: answer for this phone too.", null, 10000),
    await phone.evaluate(() => document.querySelector(".vf-devnote")?.textContent || ""));
    ok("  and her answer box is empty for this phone", (await phone.inputValue("#vf-answer")) === "");
    await phone.fill("#vf-answer", "On the bus, my phone.");
    await phone.evaluate(() => window.Core.answerCiting("Q1", document.getElementById("vf-answer").value, []));
    ok("her phone answer is a second card, the computer's kept", await until(owner, pid => {
      const mine = (window.Core.snapshot()?.cards?.Q1 || []).filter(c => c.pid === pid).map(c => `${c.device}:${c.text}`).sort().join("|");
      return mine === "computer:My laptop, mostly.|phone:On the bus, my phone.";
    }, annPid, 10000), JSON.stringify(await owner.evaluate(() => window.Core.snapshot()?.cards?.Q1)));
    ok("  and the prompt goes", await until(phone, () => document.querySelector(".vf-devnote").hidden, null, 10000));
    // Codex P2: on a per-device choice, the phone reads its own record, not the computer's. The computer picked Saved
    // cards with a comment; the phone picking the same option is sent and stored as the phone's own card, with nothing
    // of the computer's (before the fix the page took the computer's pick as the phone's and sent nothing).
    await ann.evaluate(() => window.Core.pick("Q2", "opt-1", "On my laptop the browser keeps them."));
    await until(owner, pid => (window.Core.snapshot()?.cards?.Q2 || []).some(c => c.pid === pid && c.device === "computer" && c.pick === "opt-1"), annPid, 10000);
    // the phone's answer above went in through Core, so its editing sheet is still open: close it first
    if (await phone.locator(".vf-composer-sheet").count()) await phone.locator(".vf-sheethead button", { hasText: "Cancel" }).tap();
    await phone.locator(".vf-tab", { hasText: "Questions" }).tap();
    await phone.locator(".vf-q", { hasText: Q2 }).first().tap();
    await until(phone, t => document.querySelector(".vf-qtext")?.textContent === t, Q2, 10000);
    ok("on the phone the computer's pick is not shown as this device's", await phone.evaluate(() => !window.Core.myRecord("Q2")));
    await phone.locator(".vf-opt .vf-optlabel", { hasText: "Saved cards" }).tap();
    ok("  picking the same option there stores a phone card with that pick and nothing from the computer's", await until(owner, pid => {
      const mine = (window.Core.snapshot()?.cards?.Q2 || []).filter(c => c.pid === pid);
      const ph = mine.find(c => c.device === "phone"), pc = mine.find(c => c.device === "computer");
      return mine.length === 2 && ph?.pick === "opt-1" && !ph.text && !(ph.attachments || []).length && pc?.text === "On my laptop the browser keeps them.";
    }, annPid, 10000), JSON.stringify(await owner.evaluate(() => window.Core.snapshot()?.cards?.Q2)));
    await phone.locator(".vf-tab", { hasText: "Questions" }).tap();
    await phone.locator(".vf-q", { hasText: Q }).first().tap();

    // The review: a phone turned to landscape (844x390) is still the phone, so it edits that card, never adds one.
    const land = await rec.open(link.replace(/^https?:\/\/[^/]+\//, A.localUrl), { context: { viewport: { width: 844, height: 390 }, hasTouch: true, isMobile: true } });
    await until(land, pid => window.Core.snapshot()?.me?.pid === pid, annPid, 10000);
    ok("a phone in landscape is still her phone: its answer is in the box and nothing asks again", await until(land, () => document.getElementById("vf-answer").value === "On the bus, my phone."
      && document.querySelector(".vf-devnote").hidden, null, 10000), JSON.stringify(await land.evaluate(() => [document.getElementById("vf-answer").value, window.Core.thisDevice()])));
    await land.evaluate(() => window.Core.answerCiting("Q1", "On the bus, phone sideways.", []));
    ok("  and answering there edits the phone card, still two cards", await until(owner, pid => {
      const mine = (window.Core.snapshot()?.cards?.Q1 || []).filter(c => c.pid === pid).map(c => `${c.device}:${c.text}`).sort().join("|");
      return mine === "computer:My laptop, mostly.|phone:On the bus, phone sideways.";
    }, annPid, 10000), JSON.stringify(await owner.evaluate(() => window.Core.snapshot()?.cards?.Q1)));
    // A tablet (820x1180, touch) is its own device: it is asked for an answer and adds a third card.
    const tab = await rec.open(link.replace(/^https?:\/\/[^/]+\//, A.localUrl), { context: { viewport: { width: 820, height: 1180 }, hasTouch: true, isMobile: true } });
    await until(tab, pid => window.Core.snapshot()?.me?.pid === pid, annPid, 10000);
    ok("a tablet is asked for its own answer", await until(tab, () => /^You answered this on your (computer and phone|phone and computer)\. It asks for one answer per device: answer for this tablet too\.$/.test(document.querySelector(".vf-devnote:not([hidden])")?.textContent || ""), null, 10000),
      await tab.evaluate(() => document.querySelector(".vf-devnote")?.textContent || ""));
    await tab.evaluate(() => window.Core.answerCiting("Q1", "Reading on the sofa.", []));
    ok("  and its answer is a third card", await until(owner, pid => (window.Core.snapshot()?.cards?.Q1 || []).filter(c => c.pid === pid).map(c => c.device).sort().join() === "computer,phone,tablet", annPid, 10000),
      JSON.stringify(await owner.evaluate(() => window.Core.snapshot()?.cards?.Q1)));
    ok("the owner reads one card per device, each named with its device", await until(owner, () => {
      const names = [...document.querySelectorAll(".vf-alist .vf-card")].map(c => c.textContent);
      return names.some(t => t.includes("Ann, computer") && t.includes("My laptop")) && names.some(t => t.includes("Ann, phone") && t.includes("On the bus")) && names.some(t => t.includes("Ann, tablet"));
    }, null, 10000), await owner.evaluate(() => [...document.querySelectorAll(".vf-alist .vf-card")].map(c => c.textContent.slice(0, 60)).join(" | ")));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
