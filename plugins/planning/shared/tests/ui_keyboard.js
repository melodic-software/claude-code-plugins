#!/usr/bin/env node
// Keyboard use in real browsers, against `share.sh ensure-running` with the fake cloudflared. For each modal surface
// (the join dialog, session settings, the share panel, the shortcuts dialog opened with "?", notifications, the chat,
// the picture viewer, and on a 390x844 phone the More sheet, the notifications sheet and the chat): 30 presses of Tab
// and 30 of Shift+Tab keep focus inside it, Escape closes it, and focus goes back to what opened it. Picking an option
// and sending an answer each put a message in the page's polite live region (announce() in app.js). A choice is
// answered by keyboard alone: Tab from the question reaches the first option, Space picks it, Enter picks another.
// The first-visit tour (triage 4) traps focus, ends with Done or Escape, records the `tour` pref and reopens from Help.
//   node plugins/planning/shared/tests/ui_keyboard.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the keyboard requirements of the polish plan (30 presses each way, Escape closes, focus
// returns to the opener), the WAI-ARIA Authoring Practices dialog pattern (focus stays inside a modal dialog and returns
// to the invoking element, or where it was when a shortcut opened it), the server contract (session.py pick: one pick
// per person) and core.js's join dialog rule (it stays open until the join succeeds), never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, snap, joinAs } = require("./browser_harness");

const PRESSES = 30;
const DESK = { viewport: { width: 1440, height: 900 } };
const PHONE = { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 };
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==", "base64");
const q = (id, text, format) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format });

const describe = () => { const a = document.activeElement; return a ? `${a.tagName.toLowerCase()}.${[...a.classList].join(".")} "${(a.getAttribute("aria-label") || a.textContent || "").trim().replace(/\s+/g, " ").slice(0, 30)}"` : "nothing"; };
const shownSel = sel => { const el = document.querySelector(sel); return !!el && !el.hidden && el.getClientRects().length > 0 && (el.tagName !== "DIALOG" || el.open); };

/** Tab then Shift+Tab, PRESSES each; the first press per direction that leaves the surface, or none. */
async function cycle(page, sel) {
  const out = [];
  for (const key of ["Tab", "Shift+Tab"]) {
    // Start each direction from inside: the first control the surface offers.
    await page.evaluate(sel => { const s = document.querySelector(sel); if (!s.contains(document.activeElement)) s.querySelector("button, input, textarea, select, a[href], [tabindex='0']")?.focus(); }, sel);
    for (let i = 1; i <= PRESSES; i++) {
      await page.keyboard.press(key);
      if (await page.evaluate(sel => !!document.querySelector(sel)?.contains(document.activeElement), sel)) continue;
      out.push(`${key} press ${i} moved focus to ${await page.evaluate(`(${describe})()`)}`);
      break;
    }
  }
  return out;
}

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_keyboard.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_keyboard"), { ok } = s, rec = recorder(browser), skipped = [];
  try {
    const A = await s.start("keyboard");
    const shot = s.asset(A.dir, "shot.png", PNG);
    s.apply(A.dir, [{ op: "set-title", title: "Checkout by keyboard" }, { op: "open-round", questions: [
      q("Q1", "Which default payment method?", { kind: "choice", options: [{ id: "opt-1", label: "Card" }, { id: "opt-2", label: "Saved method" }] }),
      q("Q2", "Where should the order summary sit?", { kind: "text" }),
      q("Q3", "Did you mean this button?", { kind: "confirm", image: shot, rect: { x: 0, y: 0, w: 1, h: 1 } }),
      q("Q4", "Which shipping speed by default?", { kind: "choice", options: [{ id: "opt-1", label: "Standard" }, { id: "opt-2", label: "Express" }, { id: "opt-3", label: "Next day" }] }),
    ] }]);

    /** One surface: open it from `opener` (focus, then Enter) or with `key`, check the trap, Escape, focus back. */
    async function surface(page, name, sel, { opener, key, before, expectBack } = {}) {
      if (before) await before();
      if (opener && !(await opener.isVisible().catch(() => false))) { skipped.push(`${name}: no visible control opens it`); console.log(`SKIP ${name}: no visible control opens it`); return; }
      if (opener) { await opener.focus(); await opener.evaluate(el => el.setAttribute("data-kb-opener", "")); await page.keyboard.press(key || "Enter"); }
      else await page.keyboard.press(key);
      if (!(await until(page, shownSel, sel, 5000))) { ok(`${name}: opens from the keyboard`, false, `${sel} not shown`); return; }
      const inside = await page.evaluate(sel => document.querySelector(sel).contains(document.activeElement), sel);
      ok(`${name}: focus moves into it when it opens`, inside, await page.evaluate(`(${describe})()`));
      const left = await cycle(page, sel);
      ok(`${name}: ${PRESSES} Tab and ${PRESSES} Shift+Tab keep focus inside`, left.length === 0, left.join("; "));
      await page.keyboard.press("Escape");
      ok(`${name}: Escape closes it`, await until(page, sel => !(() => { const el = document.querySelector(sel); return !!el && !el.hidden && el.getClientRects().length > 0 && (el.tagName !== "DIALOG" || el.open); })(), sel, 3000));
      const back = expectBack || "[data-kb-opener]";
      ok(`${name}: focus goes back to what opened it`, await until(page, b => !!document.activeElement?.matches(b), back, 2000),
        `focus on ${await page.evaluate(`(${describe})()`)}`);
      await page.evaluate(() => document.querySelectorAll("[data-kb-opener]").forEach(e => e.removeAttribute("data-kb-opener")));
    }

    // ---------- the join dialog ----------
    const gus = await rec.open(A.localUrl, { context: DESK });
    await gus.waitForSelector("dialog.core-name[open]");
    const joinLeft = await cycle(gus, "dialog.core-name");
    ok(`join dialog: ${PRESSES} Tab and ${PRESSES} Shift+Tab keep focus inside`, joinLeft.length === 0, joinLeft.join("; "));
    await gus.keyboard.press("Escape");
    ok("join dialog: Escape leaves it open (core.js: it stays open until the join succeeds)", await gus.evaluate(() => !!document.querySelector("dialog.core-name")?.open));
    const gusPid = await joinAs(gus, "Gus");

    // ---------- the owner's surfaces on a desktop ----------
    const owner = await rec.open(A.ownerUrl, { context: DESK });
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    await surface(owner, "settings panel", ".vf-settings", { opener: owner.locator(".vf-gear") });
    await surface(owner, "share panel", ".vf-share", { opener: owner.locator(".vf-sharebtn") });
    await surface(owner, "notifications", ".vf-bellpop", { opener: owner.locator(".vf-bell") });
    // "?" from a question in the list: focus goes back to that question, where it was.
    await surface(owner, "keyboard shortcuts (?)", ".vf-keys", { opener: owner.locator(".vf-q").first(), key: "?" });

    // ---------- the guest's surfaces on a desktop ----------
    await surface(gus, "chat", "section.vf-chat", { opener: gus.locator(".vf-fab") });
    await gus.locator(".vf-q", { hasText: "Did you mean this button?" }).first().click();
    await surface(gus, "picture viewer", ".vf-lb", { opener: gus.locator(".vf-confirm-fig .vf-imgbtn") });

    // ---------- the phone sheets ----------
    const phoneOwner = await rec.open(A.ownerUrl, { context: PHONE });
    await until(phoneOwner, () => window.Core.snapshot()?.me?.role === "owner");
    const more = phoneOwner.locator(".vf-tab", { hasText: "More" });
    await surface(phoneOwner, "phone More sheet", ".vf-moresheet", { opener: more });
    await surface(phoneOwner, "phone notifications sheet (from More)", ".vf-bellpop", {
      before: async () => { await more.focus(); await more.evaluate(el => el.setAttribute("data-kb-opener", "")); await phoneOwner.keyboard.press("Enter"); await until(phoneOwner, shownSel, ".vf-moresheet", 3000); },
      opener: phoneOwner.locator(".vf-msitem", { hasText: "Notifications" }), expectBack: ".vf-tab[data-kb-opener]",
    });
    const pia = await rec.open(A.localUrl, { context: PHONE });
    await joinAs(pia, "Pia");
    await surface(pia, "phone chat", "section.vf-chat", { opener: pia.locator(".vf-fab") });

    // ---------- announcements ----------
    await gus.evaluate(() => {
      window.__said = [];
      const live = document.querySelector(".vf-sr[aria-live]");
      new MutationObserver(() => { if (live.textContent.trim()) window.__said.push(live.textContent.trim()); }).observe(live, { childList: true, characterData: true, subtree: true });
    });
    const said = () => gus.evaluate(() => window.__said.length);
    await gus.locator(".vf-q", { hasText: "Which default payment method?" }).first().click();
    let n0 = await said();
    await gus.locator(".vf-opt", { hasText: "Card" }).locator(".vf-optchoose").click();
    ok("picking an option puts a message in the polite live region", await until(gus, n => window.__said.length > n, n0, 5000),
      `messages so far: ${JSON.stringify(await gus.evaluate(() => window.__said))}`);
    await gus.locator(".vf-q", { hasText: "Where should the order summary sit?" }).first().click();
    await gus.locator("#vf-answer").fill("Below the total.");
    n0 = await said();
    await gus.press("#vf-answer", "Control+Enter");
    const landed = await until(owner, p => (window.Core.snapshot().cards.Q2 || []).some(c => c.ref === "p:" + p && c.text === "Below the total."), gusPid, 8000);
    ok("the sent answer lands on the server", landed);
    ok("sending an answer puts a message in the polite live region", await until(gus, n => window.__said.length > n, n0, 5000),
      `messages so far: ${JSON.stringify(await gus.evaluate(() => window.__said))}`);

    // ---------- a choice answered by keyboard alone ----------
    await gus.locator(".vf-q", { hasText: "Which shipping speed by default?" }).first().click();
    await until(gus, () => document.querySelector(".vf-qtext")?.textContent === "Which shipping speed by default?");
    await gus.evaluate(() => document.querySelector(".vf-qtext").focus());
    /** Tab until focus is on option `i`'s pick button; the stops on the way, and whether it got there before another option. */
    async function tabTo(i, max = 12) {
      const path = [];
      for (let k = 0; k < max; k++) {
        await gus.keyboard.press("Tab");
        const at = await gus.evaluate(() => { const a = document.activeElement, li = a?.closest(".vf-opts > .vf-opt"); return { opt: li ? [...li.parentElement.children].indexOf(li) : -1, choose: !!a?.matches(".vf-optchoose") }; });
        path.push(await gus.evaluate(`(${describe})()`));
        if (at.opt === i && at.choose) return { ok: true, path };
        if (at.opt > i) return { ok: false, path };
      }
      return { ok: false, path };
    }
    const t1 = await tabTo(0);
    ok("Tab from the question text reaches the first option's pick button", t1.ok, t1.path.join(" -> "));
    if (t1.ok) {
      await gus.keyboard.press("Space");
      ok("Space on the first option picks it (server state)", await until(owner, p => (window.Core.snapshot().cards.Q4 || []).find(c => c.ref === "o:opt-1")?.votes?.includes(p), gusPid, 8000),
        JSON.stringify((await snap(owner)).cards.Q4));
      const t2 = await tabTo(1);
      ok("Tab goes on to the second option's pick button", t2.ok, t2.path.join(" -> "));
      if (t2.ok) {
        await gus.keyboard.press("Enter");
        ok("Enter on the second option moves the one pick there (server state)",
          await until(owner, p => { const c = window.Core.snapshot().cards.Q4 || []; return !!c.find(x => x.ref === "o:opt-2")?.votes?.includes(p) && !c.find(x => x.ref === "o:opt-1")?.votes?.includes(p); }, gusPid, 8000),
          JSON.stringify((await snap(owner)).cards.Q4));
      }
    }

    // ---------- triage 4: the first-visit tour (optional, skippable, re-opened from Help, remembered by the `tour` pref) ----------
    const tia = await rec.open(A.localUrl, { context: DESK });
    await joinAs(tia, "Tia");
    await until(tia, () => !document.querySelector(".vf-orient")?.hidden);
    await tia.click(".vf-orient-tour");
    const card = ".vf-tour-card[role=dialog][aria-modal=true]";
    ok("the tour opens as a modal dialog with focus on Next", await until(tia, c => { const d = document.querySelector(c); return !!d?.offsetParent && document.activeElement?.textContent === "Next"; }, card));
    let escaped = 0;
    for (let i = 0; i < PRESSES; i++) { await tia.keyboard.press(i % 2 ? "Shift+Tab" : "Tab"); if (!(await tia.evaluate(c => document.querySelector(c).contains(document.activeElement), card))) escaped++; }
    ok(`${PRESSES} Tab and Shift+Tab presses keep focus inside the tour`, escaped === 0, `${escaped} left it`);
    let steps = 1;
    while (steps < 10 && (await tia.evaluate(() => document.querySelector(".vf-tour-row .vf-btn-primary").textContent)) === "Next") { await tia.click(".vf-tour-row .vf-btn-primary"); steps++; }
    await tia.click(".vf-tour-row .vf-btn-primary"); // Done
    ok("Done ends the tour and the `tour` pref says done (server state)", await until(tia, () => document.querySelector(".vf-tour").hidden && window.Core.snapshot()?.me?.prefs?.tour === "done"), `${steps} steps`);
    ok("the tour walks at least the questions, the answer, the answer box, others' answers, the chat and Help", steps >= 6, `${steps} steps`);
    ok("once done, the first view stops offering the tour", await until(tia, () => document.querySelector(".vf-orient-tour").hidden));
    await tia.click(".vf-keysbtn");
    await tia.click(".vf-help-tour");
    ok("Help opens the tour again", await until(tia, c => !!document.querySelector(c)?.offsetParent, card));
    await tia.keyboard.press("Escape");
    ok("Escape skips the tour, the pref says skipped, and focus goes back to the Help button", await until(tia, () => document.querySelector(".vf-tour").hidden
      && window.Core.snapshot()?.me?.prefs?.tour === "skipped" && document.activeElement?.classList.contains("vf-keysbtn")));

    if (skipped.length) console.log(`skipped surfaces: ${skipped.join("; ")}`);
    const csp = await rec.cspViolations();
    ok("no page broke the server's CSP", csp.length === 0, csp.slice(0, 3).join(" | "));
    ok("no page error or console error", rec.errors.length === 0, rec.errors.slice(0, 3).join(" | "));
  } catch (e) {
    s.results.push(`ERROR ${e?.stack || e}`);
  } finally {
    await browser.close().catch(() => {});
  }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
