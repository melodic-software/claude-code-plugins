#!/usr/bin/env node
// Report a problem in real browsers, against `share.sh ensure-running` with the fake cloudflared, with Uploads off:
// a guest on a 390x844 phone opens it from More, sees "Sent with this report" listing the view, question, round,
// device, browser, screen, build and recent errors before Send, adds a 3200x1800 screenshot that her browser
// re-encodes to 1600 px on its long edge, types with a keyboard up while the field and Send report stay above it, and
// sends it; the request carries text, context and the picture only, never her answer, the chat, the address or her
// secret. The desktop owner (1440x900) sees it as a Problem in the Host queue, opens its picture, marks it Seen, which
// tells her, and then asks Claude about it behind a confirm (the report alone wakes nobody; guests never get the control). On a desktop, Help offers Report a problem, and a refused action's toast offers Report this, whose
// form lists that refusal among the recent errors.
//   node plugins/planning/shared/tests/ui_report.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the approved V1 (feedback triage row 38: the entry points, the field list, 1600 px, the
// png/jpeg/webp types) and the texts and bytes this suite makes, never from the page.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { loadPlaywright, suite, recorder, until, snap, joinAs, png } = require("./browser_harness");

const PHONE = { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 };
const DESK = { viewport: { width: 1440, height: 900 } };
const ANSWER = "my private answer words", CHAT = "a private chat line", TEXT = "The Send button does nothing on my phone";
const CTX_KEYS = ["view", "tab", "qid", "round", "device", "browser", "viewport", "visualViewport", "build", "errors"];
const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });

/** Before the page's scripts: a visualViewport the test shrinks by a 336 px keyboard, as WebKit does. */
function fakeViewport() {
  const t = new EventTarget();
  let kb = 0;
  const live = { width: () => innerWidth, height: () => innerHeight - kb, offsetTop: () => 0, offsetLeft: () => 0, pageTop: () => 0, pageLeft: () => 0, scale: () => 1 };
  for (const [k, f] of Object.entries(live)) Object.defineProperty(t, k, { get: f });
  Object.defineProperty(window, "visualViewport", { configurable: true, get: () => t });
  window.__kb = up => { kb = up ? 336 : 0; t.dispatchEvent(new Event("resize")); };
}

/** The bodies of every POST to /api/report the page sends. */
function reportBodies(page) {
  const out = [];
  page.on("request", r => { if (r.method() === "POST" && new URL(r.url()).pathname === "/api/report") out.push({ raw: r.postData() || "", headers: r.headers() }); });
  return out;
}

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_report.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_report"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("report");
    s.apply(A.dir, [{ op: "open-round", questions: [q("Q1", "Where should the order summary sit?")] }]);
    const owner = await rec.open(A.ownerUrl, { context: DESK });
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    ok("uploads are off in this session", (await snap(owner)).settings.uploads === false);

    // ---------- the phone: More, the sent list, the screenshot, the keyboard, Send ----------
    const pia = await rec.open(A.localUrl, { context: PHONE, init: { fn: fakeViewport } });
    await joinAs(pia, "Pia");
    const secret = await pia.evaluate(() => localStorage.getItem("secret") || "");
    ok("the guest holds a secret", secret.length > 20);
    await pia.evaluate(([a, c]) => Promise.all([window.Core.answerCiting("Q1", a, []), window.Core.chat(c)]), [ANSWER, CHAT]);
    const sent = reportBodies(pia);
    await pia.locator(".vf-tab", { hasText: "More" }).tap();
    await pia.locator(".vf-msitem", { hasText: "Report a problem" }).tap();
    ok("More opens Report a problem", await until(pia, () => !!document.querySelector(".vf-reportpop:not([hidden])")));
    const list = await pia.evaluate(() => {
      const ul = document.querySelector(".vf-reportpop .vf-rep-sent"), r = ul.getBoundingClientRect();
      return { seen: r.height > 0 && r.top < innerHeight, head: ul.previousElementSibling?.textContent, items: [...ul.children].map(li => li.textContent) };
    });
    ok("\"Sent with this report\" shows before Send", list.seen && list.head === "Sent with this report", JSON.stringify(list));
    const want = [/^View: /, /^Question: Q1, round 1$/, /^Device: phone, /, /^Screen: 390 × 844; visible 390 × 844 at 1×$/, /^Page version: \w+/, /^Recent errors: /, /^Not sent: /];
    ok("  it lists the view, question and round, device and browser, screen and visible area, build and recent errors", want.every(re => list.items.some(t => re.test(t))), list.items.join(" | "));
    ok("  and nothing anyone wrote", !list.items.join(" ").includes(ANSWER) && !list.items.join(" ").includes(CHAT));

    // F3: a pasted picture becomes the attachment chip every other form shows; its x takes it off.
    await pia.evaluate(async () => {
      const c = document.createElement("canvas"); c.width = 640; c.height = 400; c.getContext("2d").fillRect(0, 0, 640, 400);
      const dt = new DataTransfer(); dt.items.add(new File([await new Promise(r => c.toBlob(r, "image/png"))], "clip.png", { type: "image/png" }));
      document.querySelector("#vf-rep-ta").dispatchEvent(new ClipboardEvent("paste", { clipboardData: dt, bubbles: true, cancelable: true }));
    });
    ok("a screenshot pasted into the report's field shows as an attachment chip", await until(pia, () => [...document.querySelectorAll(".vf-reportpop .vf-attdraft .vf-ref")]
      .some(li => li.textContent.includes("Screenshot, 640 × 400") && li.querySelector(".vf-ref-thumb img")?.getAttribute("src")?.startsWith("data:image/"))));
    ok("  the sent list names it, and the field keeps no text", (await pia.locator(".vf-reportpop .vf-rep-sent li", { hasText: "Your screenshot, 640 × 400" }).count()) === 1 && (await pia.inputValue("#vf-rep-ta")) === "");
    await pia.locator(".vf-reportpop .vf-attdraft .vf-ref-x").tap();
    ok("  its x takes it off", await until(pia, () => document.querySelector(".vf-reportpop .vf-attdraft").hidden && ![...document.querySelectorAll(".vf-reportpop .vf-rep-sent li")].some(li => /screenshot/.test(li.textContent))));
    await pia.locator(".vf-reportpop input[type=file]").setInputFiles({ name: "shot.png", mimeType: "image/png", buffer: png(3200, 1800, [800, 1000]) });
    ok("the screenshot shows in the form", await until(pia, () => !!document.querySelector(".vf-reportpop .vf-attdraft .vf-ref-thumb img")?.naturalWidth));
    const shot = await pia.evaluate(() => { const i = document.querySelector(".vf-reportpop .vf-attdraft .vf-ref-thumb img"); return { w: i.naturalWidth, h: i.naturalHeight, src: i.src.slice(0, 30) }; });
    ok("  re-encoded in the browser to 1600 px on its long edge", shot.w === 1600 && shot.h === 900, JSON.stringify(shot));
    ok("  as WebP or JPEG", /^data:image\/(webp|jpeg);base64,/.test(shot.src), shot.src);
    ok("  and the sent list names it", (await pia.locator(".vf-reportpop .vf-rep-sent li", { hasText: "Your screenshot, 1600 × 900" }).count()) === 1);

    await pia.locator("#vf-rep-ta").tap();
    await pia.evaluate(() => window.__kb(true));
    ok("the keyboard comes up", await until(pia, () => "kb" in document.documentElement.dataset));
    // Measured settled: finite animations done, then two frames.
    await pia.evaluate(() => Promise.all(document.getAnimations().filter(a => a.effect?.getTiming().iterations !== Infinity).map(a => a.finished.catch(() => null)))
      .then(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))));
    const fit = await pia.evaluate(() => {
      const vv = visualViewport, sheet = document.querySelector(".vf-reportpop"), out = [];
      for (const sel of ["#vf-rep-ta", ".vf-reportpop button[type=submit]", ".vf-reportpop .vf-asklabel"]) {
        const r = document.querySelector(sel).getBoundingClientRect();
        if (r.top < vv.offsetTop - 0.5 || r.bottom > vv.offsetTop + vv.height + 0.5) out.push(`${sel} ${r.top.toFixed(0)}..${r.bottom.toFixed(0)} past ${vv.height}`);
      }
      const r = sheet.getBoundingClientRect();
      if (r.left < -0.5 || r.right > innerWidth + 0.5 || sheet.scrollWidth > sheet.clientWidth + 1) out.push(`sheet ${r.left}..${r.right}, content ${sheet.scrollWidth} in ${sheet.clientWidth}`);
      return out;
    });
    ok("  the field, its label and Send report sit above it, nothing clipped sideways", fit.length === 0, fit.join("; "));
    await pia.locator("#vf-rep-ta").fill(TEXT);
    await pia.locator(".vf-reportpop button[type=submit]").tap();
    ok("Send report closes the form", await until(pia, () => document.querySelector(".vf-reportpop").hidden));
    await pia.evaluate(() => window.__kb(false));
    const body = sent[0] ? JSON.parse(sent[0].raw) : {};
    ok("one report went to the server", sent.length === 1, String(sent.length));
    ok("  carrying only text, context and the picture", JSON.stringify(Object.keys(body).sort()) === JSON.stringify(["ctx", "image", "text"]), Object.keys(body).join(","));
    ok("  its context only the allowed fields", Object.keys(body.ctx || {}).every(k => CTX_KEYS.includes(k)) && body.ctx?.qid === "Q1" && body.ctx?.device === "phone", JSON.stringify(body.ctx));
    const raw = sent[0]?.raw || "";
    ok("  never her answer, the chat, the address's fragment or her secret", !raw.includes(ANSWER) && !raw.includes(CHAT) && !raw.includes("#") && !(secret && raw.includes(secret)));

    // ---------- the owner: a Problem in the Host queue, its picture, Seen ----------
    await owner.locator(".vf-seg-btn", { hasText: /^Host$/ }).click();
    const item = owner.locator(".vf-qitem[data-t=report]");
    ok("the owner sees it as a Problem in the Host queue", await until(owner, t => [...document.querySelectorAll(".vf-qitem[data-t=report]")].some(li => li.textContent.includes(t)), TEXT));
    ok("  with its chip and context", (await item.locator(".vf-chip").textContent()) === "Problem" && (await item.locator(".vf-rep-sent li").count()) >= 2);
    await item.locator("button", { hasText: "Show screenshot" }).click();
    ok("  and its picture on request", await until(owner, () => document.querySelector(".vf-qitem[data-t=report] .vf-rep-shot")?.naturalWidth === 1600));
    await item.locator("button", { hasText: /^Seen$/ }).click();
    ok("Seen tells the reporter", await until(pia, () => (window.Core.snapshot()?.me?.notifications || []).some(n => n.kind === "report")));
    ok("  and the item stays until Resolved", await until(owner, () => !!document.querySelector(".vf-qitem[data-t=report]") && ![...document.querySelectorAll(".vf-qitem[data-t=report] button")].some(b => b.textContent === "Seen")));
    // ---------- Ask Claude about this: the owner's review stands between a guest's report and Claude ----------
    const filed = () => JSON.parse(fs.readFileSync(path.join(A.dir, "state.json"), "utf8")).log.events.filter(e => e.kind === "report-filed");
    ok("the report alone wakes no Claude", filed().length === 0, JSON.stringify(filed()));
    ok("a guest never has Ask Claude about this report", await pia.evaluate(() => !document.querySelector(".vf-rep-ask") && ![...document.querySelectorAll("button")].some(b => /Ask Claude about this report/.test(b.textContent))));
    const askBtn = item.locator("button", { hasText: "Ask Claude about this report" });
    ok("the owner's seen Problem still offers Ask Claude about this report", await until(owner, () => document.querySelector(".vf-qitem[data-t=report]")?.textContent.includes("Seen.")) && await askBtn.isVisible());
    await askBtn.click();
    ok("  behind a confirm that says Claude proposes a fix and never acts on the report", await until(owner, () => /proposes a fix.*never acts/s.test(document.querySelector("dialog[open]")?.textContent || "")));
    await owner.locator("dialog[open] button", { hasText: /^Ask Claude$/ }).click();
    ok("  which marks it asked and hands it to Claude once", await until(owner, () => document.querySelector(".vf-qitem[data-t=report]")?.textContent.includes("Asked Claude.")
      && ![...document.querySelectorAll(".vf-qitem[data-t=report] button")].some(b => /Ask Claude/.test(b.textContent))) && filed().length === 1 && filed()[0].text === TEXT,
      JSON.stringify(filed()));
    await item.locator("button", { hasText: "Resolved" }).click();
    ok("Resolved takes it out of the queue", await until(owner, () => !document.querySelector(".vf-qitem[data-t=report]")));
    const guest = await snap(pia);
    ok("a guest's snapshot holds no reports", !("reports" in guest));

    // ---------- a desktop guest: Help, then a refused action's toast ----------
    const bo = await rec.open(A.localUrl, { context: DESK });
    await joinAs(bo, "Bo");
    await bo.locator(".vf-keysbtn").click();
    await bo.locator(".vf-help-report").click();
    ok("on a desktop, Help offers Report a problem", await until(bo, () => !!document.querySelector(".vf-reportpop:not([hidden])")));
    await bo.keyboard.press("Escape");
    await bo.route("**/api/propose", r => r.fulfill({ status: 403, contentType: "application/json", body: JSON.stringify({ ok: false, error: "ended", message: "This session has ended." }) }));
    await bo.locator(".vf-propose").click();
    await bo.locator("#vf-prop-ta").fill("Ask about delivery");
    await bo.locator(".vf-proposepop button[type=submit]").click();
    ok("a refused action's toast offers Report this", await until(bo, () => document.querySelector(".vf-toast .vf-toast-act:not([hidden])")?.textContent === "Report this"));
    await until(bo, () => window.Core.reportContext().errors.some(e => /HTTP 403/.test(e))); // the page's own error entry for the refusal lands
    await bo.locator(".vf-toast-act").click();
    ok("  which opens the form", await until(bo, () => !!document.querySelector(".vf-reportpop:not([hidden])")));
    const errs = await bo.locator(".vf-reportpop .vf-rep-sent li", { hasText: "Recent errors:" }).textContent();
    ok("  listing that refusal among the recent errors", /api ended: HTTP 403/.test(errs), errs);

    const pageErrs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", pageErrs.length === 0, pageErrs.slice(0, 3).join(" | "));
    ok("no CSP violation", (await rec.cspViolations()).length === 0);
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
