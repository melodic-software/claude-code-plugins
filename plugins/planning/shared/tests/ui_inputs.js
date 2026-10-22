#!/usr/bin/env node
// Every input surface on its own (Phase 4 item 3b, triage 20 and 23), through the test-only web/harness.html, which
// this suite serves into the session's origin from the browser (server.py never serves it). Surfaces: the answer
// composer, the comment on a pick, editing a saved answer (the phone sheet), the chat composer, suggest, propose,
// request (Ask Claude), rename, and the "Something else…" box. Each runs on the iPhone 13, iPhone 15 and Pixel 7
// profiles at the height left above an on-screen keyboard, and on a 1440x900 desktop. For each, the suite types 2000
// characters, then pastes a 300-character unbroken word, and checks: no horizontal overflow, the caret (at the end)
// is in view, the field is wholly inside visualViewport, nothing covers its corners, and the send control's label
// or icon is centered in it within 0.5 px.
//   node plugins/planning/shared/tests/ui_inputs.js
// The iPhone profiles want WebKit; where it cannot launch they run in Chromium with the same device profile, and a
// NOTE line says so. Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the plan (2000 characters, a 300-character word, the 0.5 px pixel pass), the triage rows
// and the devices' published CSS sizes, never from the page.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { loadPlaywright, suite, recorder, until, settled, joinAs } = require("./browser_harness");

const web = path.resolve(__dirname, "..", "web");
// CSS viewport left above the keyboard, by judgment from each device's CSS size (iPhone 13: 390x844, iPhone 15:
// 393x852, Pixel 7: 412x915) less a typical keyboard with its suggestion bar and the browser's toolbars.
const DEVICES = [["iPhone 13", 460, "webkit"], ["iPhone 15", 470, "webkit"], ["Pixel 7", 520, "chromium"]];
const TEXT = { answer: "What should the new checkout keep?", choice: "Which payment method by default?", locked: "Which currency do we show?", answered: "What worries you about checkout?" };
const q = (id, text, format) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format });
const LONG = ("Dictated text keeps going and going with no stop in sight " ).repeat(40).slice(0, 2000);
const WORD = "x".repeat(300);

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_inputs.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let chromium;
  try { chromium = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  let webkit = null;
  try { webkit = await pw.webkit.launch(); } catch { console.log("NOTE: WebKit cannot launch on this machine; the iPhone profiles run in Chromium with the same device profile"); }
  const s = suite("ui_inputs"), { ok } = s;
  const recs = [recorder(chromium), ...(webkit ? [recorder(webkit)] : [])];
  try {
    const A = await s.start("inputs");
    s.apply(A.dir, [{ op: "set-title", title: "Input checks" }, { op: "open-round", questions: [
      q("Q1", TEXT.answer, { kind: "text" }),
      q("Q2", TEXT.choice, { kind: "choice", options: [{ id: "opt-1", label: "Card" }, { id: "opt-2", label: "Saved method" }] }),
      q("Q3", TEXT.locked, { kind: "choice", options: [{ id: "opt-1", label: "Euro" }, { id: "opt-2", label: "Dollar" }] }),
      q("Q4", TEXT.answered, { kind: "text" }),
    ] }]);
    const owner = await recs[0].open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    await owner.evaluate(() => window.Core.lock("Q3", "opt-1"));
    // server.py's allowlist: the harness is test-only and never served.
    const served = await owner.evaluate(() => fetch("/harness.html").then(r => r.status));
    ok("the server does not serve web/harness.html (it is not on the allowlist)", served === 404, served);

    const files = { "/harness.html": [path.join(web, "harness.html"), "text/html"], "/harness-open.js": [path.join(__dirname, "harness-open.js"), "text/javascript"] };
    const csp = "default-src 'self'; img-src 'self' data:; frame-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'";
    const serveHarness = ctx => ctx.route(u => u.pathname in files, route => {
      const [f, type] = files[new URL(route.request().url()).pathname];
      return route.fulfill({ status: 200, contentType: type, headers: { "Content-Security-Policy": csp }, body: fs.readFileSync(f) });
    });

    const runs = [...DEVICES.map(([d, h, engine]) => ({ label: d, engine, ctx: { ...pw.devices[d], viewport: { width: pw.devices[d].viewport.width, height: h } } })),
      { label: "desktop 1440x900", engine: "chromium", ctx: { viewport: { width: 1440, height: 900 } } }];
    for (const run of runs) {
      const rec = run.engine === "webkit" && webkit ? recs[1] : recs[0];
      const { defaultBrowserType: _, ...ctx } = run.ctx;
      const joined = await rec.open(A.localUrl, { context: ctx });
      await serveHarness(joined.context());
      await joinAs(joined, `Ina ${run.label}`);
      await joined.evaluate(() => window.Core.answerCiting("Q4", "My first answer", []));
      // The harness opens in a second tab of the same browser (it shares the join), so the joined tab's beats never meet its own.
      const page = await rec.openIn(joined.context(), new URL("/harness.html", A.localUrl).href);
      await joined.close();
      if (!(await until(page, () => !!window.Harness && !!window.Core?.snapshot()?.me, null, 10000))) { ok(`${run.label}: the harness loads`, false, "no Harness"); continue; }
      const names = await page.evaluate(() => window.Harness.surfaces);
      for (const name of names) {
        let sel;
        try { sel = await page.evaluate(([n, t]) => window.Harness.open(n, t), [name, TEXT]); }
        catch (e) { ok(`${run.label}, ${name}: the surface opens`, false, String(e.message).split("\n")[0]); continue; }
        for (const [what, text] of [["2000 typed characters", LONG], ["a pasted 300-character word", WORD]]) {
          await page.evaluate(f => { const el = document.querySelector(f); el.focus(); el.value = ""; el.dispatchEvent(new Event("input", { bubbles: true })); }, sel.field);
          await page.keyboard.insertText(text);
          // Measured once the page holds still: a surface that opens scales in, and its send icon is held to 0.5 px.
          const still = await settled(page, { rects: true });
          const bad = (still ? [] : ["the page did not hold still"]).concat(await page.evaluate(([f, sendSel]) => {
            const out = [], el = document.querySelector(f), vv = window.visualViewport, T = 0.5;
            const se = document.scrollingElement, app = document.getElementById("app");
            if (se.scrollWidth > innerWidth + 1 || app.scrollWidth > app.clientWidth + 1) out.push(`page overflows sideways (${se.scrollWidth}/${app.scrollWidth} > ${innerWidth})`);
            if (el.tagName === "TEXTAREA" && el.scrollWidth > el.clientWidth + 1) out.push(`field content ${el.scrollWidth} wider than ${el.clientWidth}`);
            if (document.activeElement !== el) out.push("field lost focus");
            if (el.selectionEnd !== el.value.length) out.push("caret not at the end");
            // The caret sits on the last line: at most the field's own end padding may stay scrolled away under it.
            const cs = getComputedStyle(el), padB = parseFloat(cs.paddingBottom), padR = parseFloat(cs.paddingRight);
            const left = el.tagName === "TEXTAREA" ? el.scrollHeight - el.scrollTop - el.clientHeight - padB : el.scrollWidth - el.scrollLeft - el.clientWidth - padR;
            if (left > 2) out.push(`caret scrolled out of view (${left.toFixed(0)} px below)`);
            const r = el.getBoundingClientRect(), top = vv.offsetTop, bottom = vv.offsetTop + vv.height;
            if (r.top < top - T || r.bottom > bottom + T || r.left < -T || r.right > vv.width + T) out.push(`field ${r.left.toFixed(1)},${r.top.toFixed(1)}..${r.right.toFixed(1)},${r.bottom.toFixed(1)} not inside the visual viewport 0,${top}..${vv.width},${bottom}`);
            for (const [x, y] of [[r.left + 3, r.top + 3], [r.right - 3, r.top + 3], [r.left + 3, r.bottom - 3], [r.right - 3, r.bottom - 3]]) {
              const hit = document.elementFromPoint(x, y);
              if (hit && hit !== el && !el.contains(hit)) out.push(`corner ${x.toFixed(0)},${y.toFixed(0)} is covered by ${hit.tagName.toLowerCase()}.${String(hit.className).split(" ")[0]}`);
            }
            const b = document.querySelector(sendSel);
            if (!b || !b.getClientRects().length) out.push(`no visible send control ${sendSel}`);
            else {
              const br = b.getBoundingClientRect(), svg = [...b.querySelectorAll("svg")].find(x => x.getClientRects().length);
              let cr;
              if (svg) cr = svg.getBoundingClientRect();
              else { const rg = document.createRange(); rg.selectNodeContents(b); cr = [...rg.getClientRects()].find(x => x.width > 0); }
              if (cr) {
                const dx = (cr.left + cr.right) / 2 - (br.left + br.right) / 2, dy = (cr.top + cr.bottom) / 2 - (br.top + br.bottom) / 2;
                // A text label's range box follows the font's ascent and descent, not the glyphs, so only an icon is held
                // to the 0.5 px pass on both axes; a label is held to it across.
                if (Math.abs(dx) > T || (svg && Math.abs(dy) > T)) out.push(`send control's ${svg ? "icon" : "label"} off center by ${dx.toFixed(2)}, ${dy.toFixed(2)}`);
              }
            }
            return out;
          }, [sel.field, sel.send]));
          ok(`${run.label}, ${name}, ${what}`, bad.length === 0, bad.join("; "));
          if (bad.length && process.env.UI_INPUTS_SHOTS) await page.screenshot({ path: path.join(process.env.UI_INPUTS_SHOTS, `${run.label}-${name}-${what.length}.png`.replace(/\s+/g, "_")) });
        }
        await page.evaluate(f => { const el = document.querySelector(f); el.value = ""; el.dispatchEvent(new Event("input", { bubbles: true })); }, sel.field);
      }
    }
    ok("no page broke the server's CSP", (await Promise.all(recs.map(r => r.cspViolations()))).flat().length === 0);
    // The suite's own fetch of /harness.html answers 404 by design; a browser logs that as a failed resource.
    const errs = recs.flatMap(r => r.errors).filter(m => !/Failed to load resource/.test(m));
    ok("no page error or console error", !errs.length, errs.slice(0, 3).join(" | "));
    const too = recs.flatMap(r => r.too);
    ok("no request was answered 429 (slow down)", !too.length, too.slice(0, 5).join(", "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally {
    await chromium.close(); if (webkit) await webkit.close();
  }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
