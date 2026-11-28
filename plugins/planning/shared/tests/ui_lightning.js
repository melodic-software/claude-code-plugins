#!/usr/bin/env node
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const Q1T = "Should the retry count have a cap?";
const Q1 = {
  id: "Q1", text: Q1T, major: true, context: "Retries run until the job succeeds today.",
  recommendation: "Cap retries at five. Past five a stuck job only burns time.",
  basis: "Checked against: the retry budget.\nFive covers every recovery the logs show.\nFlips if: a job needs more than five tries to recover.",
  alternatives: [{ key: "a", text: "Reuse the queue's cap. It already exists." }, { key: "b", text: "No cap at all." }],
  dependsOn: [], purpose: "decide", format: { kind: "text" },
};
const Q2 = { id: "Q2", text: "Who owns the retry alerts?", recommendation: "Withheld: the team list is not settled yet.", alternatives: [{ key: "a", text: "The platform team" }, { key: "b", text: "Each service team" }], dependsOn: [], purpose: "decide", format: { kind: "text" } };
const Q3 = { id: "Q3", text: "What else should retries log?", alternatives: [], dependsOn: [], purpose: "gather", format: { kind: "text" } };

const card = () => {
  const box = document.querySelector(".vf-lite"), ctx = document.querySelector(".vf-qctx:not(.vf-qopen)");
  if (!box) return null;
  return {
    shown: box.checkVisibility(), rec: box.querySelector(".vf-lite-rec")?.textContent ?? null, bold: box.querySelector(".vf-lite-rec strong")?.textContent ?? null,
    lines: [...box.querySelectorAll(".vf-lite-line")].map(p => p.textContent), toggle: box.querySelector(".vf-lite-toggle")?.textContent ?? null,
    expanded: box.querySelector(".vf-lite-toggle")?.getAttribute("aria-expanded") ?? null, context: !!ctx && ctx.checkVisibility(),
  };
};

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_lightning.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; }
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; }
  const s = suite("ui_lightning"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("lightning");
    s.apply(A.dir, [{ op: "open-round", questions: [Q1, Q2, Q3] }]);
    const guest = await rec.open(A.localUrl);
    await joinAs(guest, "Gus");
    await until(guest, t => document.querySelector(".vf-qtext")?.textContent === t, Q1T);
    let c = await guest.evaluate(card);
    ok("standard style: no short card, the question's background shows", !!c && !c.shown && c.context, JSON.stringify(c));

    s.apply(A.dir, [{ op: "set-style", style: "lightning" }]);
    ok("set-style lightning reaches the guest's page", await until(guest, () => window.Core.state.settings.lightning === true));
    await until(guest, () => !!document.querySelector(".vf-lite-rec"));
    c = await guest.evaluate(card);
    ok("Answer first: the short card holds Claude's take until the guest answers or asks",
      !!c && c.shown && c.rec === "(major) Answer first - Claude's take shows once you answer or vote" && c.lines.length === 0, JSON.stringify(c));
    await guest.click(".vf-claudebar");
    await until(guest, () => document.querySelector(".vf-lite-rec strong")?.textContent === "Cap retries at five");
    c = await guest.evaluate(card);
    ok("the short card tags a major question and bolds the answer in a few words", !!c && c.shown && c.bold === "Cap retries at five", JSON.stringify(c));
    ok("  then its basis after a dash and each other option's letter and short label",
      !!c && c.rec === "(major) Cap retries at five - Five covers every recovery the logs show (or: a Reuse the queue's cap, b No cap at all)", c && c.rec);
    ok("  and the Flips if line on its own", !!c && JSON.stringify(c.lines) === JSON.stringify(["Flips if: a job needs more than five tries to recover."]), JSON.stringify(c && c.lines));
    ok("  the full question's background is folded away", !!c && !c.context);
    ok("  with one control that opens all of Q1", !!c && c.toggle === "Show all of Q1" && c.expanded === "false", JSON.stringify(c));

    await guest.focus(".vf-lite-toggle");
    await guest.keyboard.press("Enter");
    await until(guest, () => document.querySelector(".vf-lite-toggle")?.getAttribute("aria-expanded") === "true");
    ok("  pressing the toggle keeps keyboard focus on it", await guest.evaluate(() => document.activeElement?.classList.contains("vf-lite-toggle")));
    c = await guest.evaluate(card);
    ok("Show all of Q1 expands it to the full card: the background is back, the summary gone", !!c && c.context && c.rec === null && c.toggle === "Show the short card", JSON.stringify(c));
    await guest.click(".vf-lite-toggle");
    ok("Show the short card folds it again", await until(guest, () => !!document.querySelector(".vf-lite-rec")));

    await guest.keyboard.press("ArrowRight");
    await until(guest, () => document.querySelector(".vf-qtext")?.textContent === "Who owns the retry alerts?");
    c = await guest.evaluate(card);
    ok("a withheld question's short card says Withheld and why, with no options", !!c && c.rec === "Withheld - the team list is not settled yet.", c && c.rec);
    await guest.keyboard.press("ArrowRight");
    await until(guest, () => document.querySelector(".vf-qtext")?.textContent === "What else should retries log?");
    c = await guest.evaluate(card);
    ok("a question with no recommendation says No recommendation", !!c && c.rec === "No recommendation", c && c.rec);

    const status = await guest.evaluate(() => window.Core.saveSettings({ lightning: false }).then(() => 200, e => e.status));
    ok("a guest cannot turn lightning off", status === 403, status);
    ok("  and the session keeps it", (await guest.evaluate(() => window.Core.state.settings.lightning)) === true);

    const owner = await rec.open(A.ownerUrl);
    await owner.click(".vf-gear");
    const sw = owner.locator(".vf-settings .vf-sw-row", { hasText: "Lightning cards" });
    ok("the owner's Settings show Lightning cards on", (await sw.getAttribute("aria-checked")) === "true");
    await sw.click();
    ok("the owner turns it off for everyone", await until(guest, () => window.Core.state.settings.lightning === false));
    ok("  and the guest's page goes back to the full card", await until(guest, () => !document.querySelector(".vf-lite").checkVisibility()));

    const errs = rec.errors.filter(m => !/Failed to load resource|403/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
    const csp = await rec.cspViolations();
    ok("no CSP violation", csp.length === 0, csp.join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
