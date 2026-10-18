#!/usr/bin/env node
// The keyboard readout on a touch phone, against `share.sh ensure-running` with the fake cloudflared: with the
// Propose sheet open, the keyboard coming up logs one `kind=layout` client entry to server.log carrying the viewport,
// the app's --kb, --vv-top and --vv-h, data-kb, the sheet's box and computed bottom styles, the safe-area inset and
// the screen height; the keyboard going down and up again in the same open logs nothing more, and the next open logs
// once again. No text the person typed reaches the log.
//   node plugins/planning/shared/tests/ui_kbreadout.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// The keyboard is a stand-in visualViewport, installed before the page's scripts, whose height shrinks by 344 px (a
// phone keyboard) and fires resize, as WebKit does. Expected field names come from the coordinator's brief for
// item E, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const FIELDS = ["sheet", "innerWidth", "innerHeight", "vvWidth", "vvHeight", "vvOffsetTop", "vvPageTop", "vvScale", "clientHeight", "kb", "vvTop", "vvH",
  "dataKb", "sheetTop", "sheetBottom", "sheetHeight", "paddingBottom", "marginBottom", "bottom", "transform", "safeBottom", "screenHeight"];
const TYPED = "secret words typed in the sheet";

/** Before the page's scripts: a visualViewport the test moves, as a keyboard would. */
function fakeViewport() {
  const t = new EventTarget();
  let kb = 0;
  const live = { width: () => innerWidth, height: () => innerHeight - kb, offsetTop: () => 0, offsetLeft: () => 0, pageTop: () => 0, pageLeft: () => 0, scale: () => 1 };
  for (const [k, f] of Object.entries(live)) Object.defineProperty(t, k, { get: f });
  Object.defineProperty(window, "visualViewport", { configurable: true, get: () => t });
  window.__kb = up => { kb = up ? 344 : 0; t.dispatchEvent(new Event("resize")); };
}

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_kbreadout.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_kbreadout"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("kbreadout");
    s.apply(A.dir, [{ op: "open-round", questions: [{ id: "Q1", text: "Where should the summary sit?", alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } }] }]);
    const phone = await rec.open(A.localUrl, { context: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true }, init: { fn: fakeViewport } });
    const pid = await joinAs(phone, "Pia");
    ok("the page is a touch device", await phone.evaluate(() => matchMedia("(pointer: coarse)").matches));
    const lines = () => s.share(A.dir, "logs", "--errors").lines.filter(l => l.includes(` client pid=${pid} `) && l.includes(" kind=layout "));
    const waitLines = async n => { let got = []; for (let i = 0; i < 40; i++) { got = lines(); if (got.length >= n) break; await phone.waitForTimeout(200); } return got; };
    const open = async () => {
      await phone.locator(".vf-tab", { hasText: "Questions" }).tap();
      await phone.locator(".vf-propose").tap();
      return until(phone, () => !!document.querySelector(".vf-proposepop:not([hidden])"));
    };

    ok("the Propose sheet opens", await open());
    await phone.locator("#vf-prop-ta").fill(TYPED);
    await phone.evaluate(() => window.__kb(true));
    ok("the keyboard comes up: data-kb is set", await until(phone, () => "kb" in document.documentElement.dataset));
    let got = await waitLines(1);
    ok("the keyboard coming up logs one layout readout", got.length === 1, got.join(" | "));
    const line = got[0] || "";
    const missing = FIELDS.filter(f => !new RegExp(`[ "]${f}=\\S`).test(line));
    ok("  carrying every field", missing.length === 0, `missing ${missing.join(", ")} in ${line}`);
    ok("  for the Propose sheet, with the keyboard's height and data-kb", / sheet=vf-proposepop /.test(line.replace('message="', " ")) && /kb=344px/.test(line) && /dataKb=true/.test(line) && /screenHeight=\d+/.test(line), line);
    await phone.evaluate(() => window.__kb(false));
    await until(phone, () => !("kb" in document.documentElement.dataset));
    await phone.evaluate(() => window.__kb(true));
    await phone.waitForTimeout(1500);
    ok("down and up again in the same open logs nothing more", (await waitLines(2)).length === 1);

    await phone.evaluate(() => window.__kb(false));
    await phone.keyboard.press("Escape");
    ok("the sheet closes", await until(phone, () => !document.querySelector(".vf-proposepop:not([hidden])")));
    await open();
    await phone.evaluate(() => window.__kb(true));
    got = await waitLines(2);
    ok("the next open logs once again", got.length === 2, got.join(" | "));
    const all = s.share(A.dir, "logs").lines.join("\n");
    ok("no text the person typed reaches the log", !all.includes(TYPED) && !all.includes("Pia"));

    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
