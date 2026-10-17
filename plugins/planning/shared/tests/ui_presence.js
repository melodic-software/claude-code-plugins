#!/usr/bin/env node
// Presence in real browsers, against `share.sh ensure-running` with the fake cloudflared, watched from the owner's page:
// a tab hidden for 3 minutes with hidden-tab timer throttling emulated shows Away and never drops out and back; a closed
// tab goes offline after about 90 s; Away by hand shows, and the next key press ends it; and normal use (switching
// questions while typing, answering, a personal link) gets no 429 from the heartbeat or any other route.
//   node plugins/planning/shared/tests/ui_presence.js   (about 4 minutes)
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the Presence amendment (visible and lastInput on the heartbeat, Away when hidden or snoozed,
// offline after 90 s without a heartbeat: session.py OFFLINE_AFTER) and the one-a-second heartbeat limit
// (HEARTBEAT_INTERVAL), never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const HIDDEN_FOR = 180; // seconds: the Brief's 3 minutes
const OFFLINE_AFTER = 90; // seconds: session.py OFFLINE_AFTER
const text = (id, t) => ({ id, text: t, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });

/** In the page before its scripts: a visibility switch, and hidden-tab timers. Chrome runs a hidden tab's timers at
 *  most once a minute after a while hidden (intensive throttling); here that starts the moment the tab hides, so every
 *  timer callback waits for the next one-minute wake, and each timer runs once per wake. */
function hideable() {
  let hidden = false;
  Object.defineProperty(Document.prototype, "visibilityState", { configurable: true, get: () => (hidden ? "hidden" : "visible") });
  Object.defineProperty(Document.prototype, "hidden", { configurable: true, get: () => hidden });
  const realTimeout = window.setTimeout.bind(window), realInterval = window.setInterval.bind(window);
  const queued = new Map(); let n = 0;
  const gate = (key, fn) => (hidden ? queued.set(key, fn) : fn());
  const flush = () => { const run = [...queued.values()]; queued.clear(); for (const f of run) { try { f(); } catch (e) { console.error(e); } } };
  window.setTimeout = (fn, ms, ...a) => { const key = "t" + ++n; return realTimeout(() => gate(key, () => fn(...a)), ms); };
  window.setInterval = (fn, ms, ...a) => { const key = "i" + ++n; return realInterval(() => gate(key, () => fn(...a)), ms); };
  window.__wakes = 0;
  realInterval(() => { if (hidden) { window.__wakes++; flush(); } }, 60000);
  window.__setHidden = h => { hidden = h; if (!h) flush(); document.dispatchEvent(new Event("visibilitychange")); };
}

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_presence.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_presence"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("presence");
    s.apply(A.dir, [{ op: "open-round", questions: [text("Q1", "Where should the order summary sit?"), text("Q2", "Which default payment method?"), text("Q3", "What worries you?")] }]);
    const owner = await rec.open(A.ownerUrl);
    await owner.locator(".vf-seg .vf-seg-btn", { hasText: "Host" }).click();

    const hid = await rec.open(A.localUrl, { init: { fn: hideable } });
    const hidPid = await joinAs(hid, "Hana");
    const gone = await rec.open(A.localUrl);
    const gonePid = await joinAs(gone, "Bo");
    const snooze = await rec.open(A.localUrl);
    const snoozePid = await joinAs(snooze, "Cai");
    const busy = await rec.open(A.localUrl);
    const busyPid = await joinAs(busy, "Dee");
    const view = () => owner.evaluate(() => Object.fromEntries(window.Core.state.presence.map(p => [p.cid, p.away ? "away" : "active"])));
    const shownAs = pid => owner.evaluate(p => document.querySelector(`.vf-hperson:has([data-pid="${p}"])`)?.dataset.presence || "", pid);
    ok("everyone shows Active on the owner's page", await until(owner, ps => ps.every(p => window.Core.state.presence.some(x => x.cid === p && !x.away)), [hidPid, gonePid, snoozePid, busyPid], 10000));

    // ---------- hide one tab for 3 minutes; close another; watch both from the owner's page ----------
    await hid.evaluate(() => window.__setHidden(true));
    await gone.context().close();
    const t0 = Date.now(), samples = [];
    const watch = (async () => {
      while ((Date.now() - t0) / 1000 < HIDDEN_FOR) {
        const v = await view();
        samples.push({ t: (Date.now() - t0) / 1000, hid: v[hidPid] || "absent", gone: v[gonePid] || "absent", row: await shownAs(hidPid), goneRow: await shownAs(gonePid) });
        await owner.waitForTimeout(1000);
      }
    })();

    // ---------- meanwhile: Away by hand, and normal use with no 429 ----------
    const meanwhile = (async () => {
      await snooze.locator(`.vf-people .vf-person[data-pid="${snoozePid}"]`).click();
      await snooze.locator(".vf-away-btn").click();
      ok("Away by hand shows on the owner's page", await until(owner, p => window.Core.state.presence.find(x => x.cid === p)?.away === true, snoozePid, 10000));
      ok("  and in the owner's people list", await until(owner, p => document.querySelector(`.vf-hperson:has([data-pid="${p}"])`)?.dataset.presence === "away", snoozePid, 10000));
      ok("  and the snoozed person's own menu says so", await until(snooze, () => document.querySelector(".vf-away-btn")?.getAttribute("aria-pressed") === "true"));
      await snooze.keyboard.press("Escape");
      ok("the next key press ends Away by hand", await until(owner, p => window.Core.state.presence.find(x => x.cid === p)?.away === false, snoozePid, 10000));

      // Switch questions while typing, answer, switch again: each switch is a focus change and typing starts a beat.
      for (let i = 0; i < 6; i++) {
        for (const label of ["Where should", "Which default", "What worries"]) {
          await busy.locator(".vf-q", { hasText: label }).first().click();
          await busy.locator("#vf-answer").pressSequentially("ok", { delay: 30 });
        }
      }
      await busy.locator("#vf-answer").fill("Below the total.");
      await busy.press("#vf-answer", "Control+Enter");
      for (const label of ["Where should", "Which default", "Where should"]) await busy.locator(".vf-q", { hasText: label }).first().click();
      ok("the busy guest's answer lands", await until(owner, p => (window.Core.snapshot().cards.Q3 || []).some(c => c.ref === "p:" + p && c.text === "Below the total."), busyPid));
      // A personal link: the page asks the server who the secret is, then beats.
      const eve = await rec.open(A.localUrl);
      await joinAs(eve, "Eve");
      const secret = await eve.evaluate(() => localStorage.getItem("secret"));
      await eve.context().close();
      await busy.waitForTimeout(2500); // past the closed tab's last beat, so the new device's first beat is not a second one in the same second
      const eve2 = await rec.open(`${A.localUrl}#me=${secret}`);
      ok("a personal link signs the person in on another device", await until(eve2, () => window.Core.me.name === "Eve" && !!window.Core.snapshot()?.me));
      for (const label of ["Which default", "Where should"]) { await eve2.locator(".vf-q", { hasText: label }).first().click(); await eve2.locator("#vf-answer").pressSequentially("hi", { delay: 30 }); }
      await eve2.waitForTimeout(3000);
    })();
    await Promise.all([watch, meanwhile]);

    // The hidden tab: Away from its visibility-change beat on, present the whole time.
    const firstAway = samples.find(x => x.hid === "away")?.t ?? Infinity;
    ok("the hidden tab shows Away within seconds of hiding", firstAway <= 5, `first Away at ${firstAway}s`);
    const after = samples.filter(x => x.t > firstAway);
    ok(`the hidden tab stays present and Away for ${HIDDEN_FOR} s: it never drops out and back`, samples.length > 150 && samples.every(x => x.hid !== "absent") && after.every(x => x.hid === "away"),
      JSON.stringify(samples.filter(x => x.hid !== "away").slice(0, 5)));
    ok("  and the people list shows it Away, never offline", after.every(x => x.row === "away"), JSON.stringify(after.filter(x => x.row !== "away").slice(0, 3)));
    ok("  its timers really were throttled to the one-minute wakes", (await hid.evaluate(() => window.__wakes)) >= 2, await hid.evaluate(() => window.__wakes));
    // The closed tab: present until about 90 s after its last beat, then offline (absent), and it stays so.
    const lastSeen = Math.max(0, ...samples.filter(x => x.gone !== "absent").map(x => x.t));
    const offAt = samples.find(x => x.t > lastSeen)?.t ?? Infinity;
    ok(`the closed tab goes offline about ${OFFLINE_AFTER} s after it closed`, offAt >= OFFLINE_AFTER - 5 && offAt <= OFFLINE_AFTER + 10 && samples.filter(x => x.t > offAt).every(x => x.gone === "absent"), `offline at ${offAt}s`);
    ok("  and the people list shows it offline", samples.filter(x => x.t > offAt + 2).every(x => x.goneRow === "offline"), JSON.stringify(samples.filter(x => x.t > offAt + 2 && x.goneRow !== "offline").slice(0, 3)));

    await hid.evaluate(() => window.__setHidden(false));
    ok("shown again, the tab is Active", await until(owner, p => window.Core.state.presence.find(x => x.cid === p)?.away === false, hidPid, 10000));

    ok("no request was answered 429 (slow down)", rec.too.length === 0, rec.too.slice(0, 5).join(", "));
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
