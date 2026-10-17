#!/usr/bin/env node
// The side chat in real browsers, against `share.sh ensure-running` with the fake cloudflared (triage 2 and 24): the
// host, chat closed, sees a guest's message on the chat button's badge and in the tab title; a page frozen the way a
// phone freezes a background tab shows all 3 messages posted meanwhile within 2 s of thawing; and a reader scrolled up
// in the chat gets a "3 new messages" pill instead of a jump. On a 390x844 phone with 20+ messages, a reader at the
// newest keeps it whole above the field as the keyboard opens, while typing 3 lines, when a message arrives, and as
// the keyboard closes; scrolled up, an arrival shows the pill.
//   node plugins/planning/shared/tests/ui_chat.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the triage rows (badge, 3 messages, 2 s) and the messages this suite posts, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");
// The iOS Safari keyboard, as WebKit implements it. The layout viewport and innerHeight stay; visualViewport's height
// drops by the keyboard (https://www.bram.us/2021/09/13/prevent-items-from-being-hidden-underneath-the-virtual-keyboard-by-means-of-the-virtualkeyboard-api/).
// On an iPhone a focused text field always forces a reveal (WKContentViewInteraction.mm passes requiresAccessoryView as
// forceScroll), which centers the field in the height left above the keyboard, clamped to the document, over 0.25 s
// (WKWebViewIOS.mm _zoomToFocusRect): that pan is visualViewport.offsetTop. visualViewport fires resize along the way
// and scroll only once the pan stops (https://bugs.webkit.org/show_bug.cgi?id=218465); a resize handler can read
// offsetTop 0 that reads right a moment later (https://bugs.webkit.org/show_bug.cgi?id=237851), which `stale` makes
// the last event. KB (336 px, by judgment from an iPhone 13 with the suggestion bar) is the default keyboard height.
const KB = 336;
const keyboard = (page, up, { kb = KB, stale = false } = {}) => page.evaluate(async ([up, kb, stale]) => {
  const vv = window.visualViewport, ih = innerHeight, h0 = vv.height, top0 = vv.offsetTop, h1 = up ? ih - kb : ih;
  const set = (h, top) => { for (const [k, v] of [["height", h], ["offsetTop", top]]) Object.defineProperty(vv, k, { configurable: true, get: () => v }); };
  let pan = 0;
  const f = document.activeElement;
  if (up && f && f !== document.body) {
    const r = f.getBoundingClientRect(), space = (h1 - r.height) / 2;
    pan = space > 0 ? r.top - space : Math.min(Math.max(top0, r.top - h1 / 2), r.top);
    pan = Math.min(Math.max(0, pan), document.documentElement.scrollHeight - h1);
  }
  for (let i = 1; i <= 5; i++) {
    set(h0 + (h1 - h0) * i / 5, i === 1 ? top0 : top0 + (pan - top0) * i / 5);
    vv.dispatchEvent(new Event("resize"));
    await new Promise(r => setTimeout(r, 50));
  }
  set(h1, pan); vv.dispatchEvent(new Event("scroll"));
  if (stale) { set(h1, 0); vv.dispatchEvent(new Event("resize")); set(h1, pan); }
  if (!up) { delete vv.height; delete vv.offsetTop; }
  await new Promise(r => setTimeout(r, 100));
  await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
  return pan;
}, [up, kb, stale]);

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_chat.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_chat"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("chat");
    s.apply(A.dir, [{ op: "set-title", title: "Chat checks" }, { op: "open-round", questions: [{ id: "Q1", text: "Anything?", alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } }] }]);
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const gus = await rec.open(A.localUrl);
    await joinAs(gus, "Gus");

    // ---------- triage 2: the host sees a guest's message ----------
    await gus.evaluate(() => window.Core.chat("Heyro?"));
    ok("the host, chat closed, sees a guest's message as a badge on the chat button", await until(owner, () => document.querySelector(".vf-fab-badge")?.textContent === "1"
      && /1 unread/.test(document.querySelector(".vf-fab").getAttribute("aria-label"))));
    ok("the host's tab title counts it too", await until(owner, () => document.title === "(1) Chat checks"));
    await owner.click(".vf-fab");
    ok("opening the chat clears the badge and the title count", await until(owner, () => !document.querySelector(".vf-fab-badge").textContent && document.title === "Chat checks"));

    // ---------- triage 24: a frozen page catches up within 2 s of thawing ----------
    const cdp = await owner.context().newCDPSession(owner);
    await cdp.send("Page.setWebLifecycleState", { state: "frozen" });
    const sent = [];
    for (const t of ["One while away", "Two while away", "Three while away"]) { sent.push(t); await gus.evaluate(x => window.Core.chat(x), t); }
    await owner.waitForTimeout(3000);
    await cdp.send("Page.setWebLifecycleState", { state: "active" });
    const t0 = Date.now();
    const all3 = await until(owner, ts => ts.every(t => [...document.querySelectorAll(".vf-mlist .vf-msg")].some(li => li.textContent.includes(t))), sent, 2000);
    ok("after the page thaws, all 3 messages posted meanwhile show within 2 s", all3, `${Date.now() - t0} ms`);

    // ---------- triage 24: scrolled up, new messages wait behind a pill ----------
    for (let i = 0; i < 12; i++) await gus.evaluate(x => window.Core.chat(x), `Filler ${i} ${"so the chat scrolls ".repeat(3)}`);
    await until(owner, () => document.querySelectorAll(".vf-mlist .vf-msg").length >= 16);
    await owner.evaluate(() => { document.querySelector(".vf-mscroll").scrollTop = 0; });
    await owner.waitForTimeout(300);
    for (const t of ["New A", "New B", "New C"]) await gus.evaluate(x => window.Core.chat(x), t);
    ok("scrolled up, the chat shows a \"3 new messages\" pill and stays where the reader is", await until(owner, () => {
      const p = document.querySelector(".vf-mnew");
      return !!p && !p.hidden && p.textContent.startsWith("3 new messages") && document.querySelector(".vf-mscroll").scrollTop < 40;
    }));
    await owner.click(".vf-mnew");
    ok("the pill takes the reader to the newest message and goes away", await until(owner, () => {
      const sc = document.querySelector(".vf-mscroll");
      return document.querySelector(".vf-mnew").hidden && sc.scrollHeight - sc.scrollTop - sc.clientHeight < 40;
    }));

    // ---------- dogfood: reactions show only when present; add on hover or focus, React in the long-press menu ----------
    const addOf = (page, text) => page.locator(".vf-msg", { hasText: text }).locator(".vf-mreact-add");
    const shown = el => !!el && getComputedStyle(el).opacity !== "0" && el.getBoundingClientRect().height > 0;
    const rowH = (text) => { const li = [...document.querySelectorAll(".vf-mlist .vf-msg")].find(m => m.textContent.includes(text)); const r = li?.querySelector(".vf-mreacts"); return r ? r.getBoundingClientRect().height : 0; };
    ok("a message with no reactions has no reaction row", await owner.evaluate(rowH, "New B") === 0, `row height ${await owner.evaluate(rowH, "New B")}`);
    await owner.mouse.move(1, 1);
    await owner.evaluate(() => document.activeElement?.blur());
    const addB = addOf(owner, "New B");
    const hiddenIdle = !(await addB.evaluate(shown));
    await owner.locator(".vf-msg", { hasText: "New B" }).locator(".vf-bubble").hover();
    ok("on a desktop pointer the add control is hidden until the message is hovered", hiddenIdle && await addB.evaluate(shown), `hidden idle ${hiddenIdle}`);
    await owner.mouse.move(1, 1);
    await owner.locator(".vf-msg", { hasText: "New A" }).locator(".vf-msgmore").focus();
    const hiddenBeforeTab = !(await addB.evaluate(shown));
    let tabs = 0;
    while (tabs < 8 && !(await addB.evaluate(el => document.activeElement === el))) { await owner.keyboard.press("Tab"); tabs++; }
    ok("Tab reaches the add control and focus shows it", hiddenBeforeTab && await addB.evaluate(el => document.activeElement === el) && await addB.evaluate(shown), `hidden before ${hiddenBeforeTab}, ${tabs} tabs`);

    const pia = await rec.open(A.localUrl, { context: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 } });
    await joinAs(pia, "Pia");
    await pia.evaluate(() => { document.querySelector(".vf-fab").click(); });
    await until(pia, () => [...document.querySelectorAll(".vf-mlist .vf-msg")].some(m => m.textContent.includes("New C")));
    ok("at 390x844 no add pill renders under any message, and an unreacted message has no row", await pia.evaluate(rowH, "New C") === 0
      && await pia.evaluate(() => [...document.querySelectorAll(".vf-mlist .vf-mreact-add")].every(b => b.getBoundingClientRect().height === 0)));
    const bub = pia.locator(".vf-msg", { hasText: "New C" }).locator(".vf-bubble");
    await bub.scrollIntoViewIfNeeded();
    const bb = await bub.boundingBox();
    const tcdp = await pia.context().newCDPSession(pia);
    const pt = [{ x: Math.round(bb.x + bb.width / 2), y: Math.round(bb.y + bb.height / 2) }];
    await tcdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: pt });
    await pia.waitForTimeout(700);
    await tcdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    const reactItem = pia.locator(".vf-msgmenu [role=menuitem]", { hasText: /React$/ });
    ok("at 390x844 a long-press opens the message menu with React", await until(pia, () => { const m = document.querySelector(".vf-msgmenu"); return !m.hidden && [...m.querySelectorAll("[role=menuitem]")].some(b => !b.hidden && /React$/.test(b.textContent)); }));
    if (await reactItem.count()) {
      await reactItem.tap();
      await until(pia, () => !document.querySelector(".vf-reactpop").hidden);
      await pia.locator(".vf-rp-quick .vf-rp-e", { hasText: "👍" }).tap();
    }
    const chipOn = page => until(page, () => { const li = [...document.querySelectorAll(".vf-mlist .vf-msg")].find(m => m.textContent.includes("New C")); const c = li?.querySelector(".vf-mreact"); return !!c && c.textContent === "👍1" && c.getBoundingClientRect().height > 0; });
    ok("React's quick row adds 👍, and the chip appears for the reactor and the host", await chipOn(pia) && await chipOn(owner));
    if (await pia.locator(".vf-msg", { hasText: "New C" }).locator(".vf-mreact").count()) await pia.locator(".vf-msg", { hasText: "New C" }).locator(".vf-mreact").tap();
    const rowGone = page => until(page, () => { const li = [...document.querySelectorAll(".vf-mlist .vf-msg")].find(m => m.textContent.includes("New C")); const r = li?.querySelector(".vf-mreacts"); return !!li && !li.querySelector(".vf-mreact") && (!r || r.getBoundingClientRect().height === 0); });
    ok("tapping the chip takes the reaction back and the row goes away", await rowGone(pia) && await rowGone(owner));

    // ---------- dogfood: at the newest message, the phone keyboard never hides it ----------
    for (let i = 0; i < 3; i++) await gus.evaluate(x => window.Core.chat(x), `More ${i} ${"so the chat scrolls ".repeat(3)}`);
    const kia = await rec.open(A.localUrl, { context: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 } });
    await joinAs(kia, "Kia");
    await kia.evaluate(() => { document.querySelector(".vf-fab").click(); });
    const n20 = await until(kia, () => document.querySelectorAll(".vf-mlist .vf-msg").length >= 20 && [...document.querySelectorAll(".vf-mlist .vf-msg")].pop().textContent.includes("More 2"));
    await kia.evaluate(() => Promise.all(document.getAnimations().map(a => a.finished.catch(() => null))));
    // The newest message whole between the list's top edge and the message field, inside the visual viewport.
    const newest = text => until(kia, t => {
      const sc = document.querySelector(".vf-mscroll").getBoundingClientRect(), form = document.querySelector(".vf-mform").getBoundingClientRect();
      const last = [...document.querySelectorAll(".vf-mlist .vf-msg")].pop(), r = last.getBoundingClientRect(), vv = visualViewport;
      return last.textContent.includes(t) && r.top >= sc.top - 0.5 && r.bottom <= Math.min(sc.bottom, form.top) + 0.5 && form.bottom <= vv.offsetTop + vv.height + 0.5;
    }, text, 3000);
    const where = () => kia.evaluate(() => { const sc = document.querySelector(".vf-mscroll"); return `${sc.scrollHeight - sc.scrollTop - sc.clientHeight} px below the list's bottom edge, visual viewport ${visualViewport.height}`; });
    await kia.locator(".vf-minput").tap();
    await keyboard(kia, true);
    ok("390x844, 20+ messages, at the newest: with the keyboard up the newest message is whole above the field", n20 && await newest("More 2"), await where());
    if (process.env.KBD_SHOTS) { const vv = await kia.evaluate(() => [visualViewport.offsetTop, visualViewport.height]); await kia.screenshot({ path: require("node:path").join(process.env.KBD_SHOTS, "chat-390x844-keyboard.png"), clip: { x: 0, y: vv[0], width: 390, height: vv[1] } }); }
    await kia.keyboard.insertText("Line one\nLine two\nLine three");
    ok("390x844, keyboard up: typing 3 lines keeps the newest message in view", await newest("More 2"), await where());
    await gus.evaluate(() => window.Core.chat("Arrived with the keyboard up"));
    ok("390x844, keyboard up: a message that arrives shows whole above the field", await newest("Arrived with the keyboard up"), await where());
    await kia.evaluate(() => { document.querySelector(".vf-mscroll").scrollTop = 0; });
    await kia.waitForTimeout(300);
    await gus.evaluate(() => window.Core.chat("Arrived while scrolled up"));
    ok("390x844, keyboard up, scrolled up: a new message shows the \"1 new message\" pill instead of a jump", await until(kia, () => {
      const p = document.querySelector(".vf-mnew");
      return !p.hidden && p.textContent.startsWith("1 new message") && document.querySelector(".vf-mscroll").scrollTop < 40;
    }));
    await kia.locator(".vf-mnew").tap();
    await newest("Arrived while scrolled up");
    await keyboard(kia, false);
    ok("390x844: closing the keyboard keeps the newest message in view", await newest("Arrived while scrolled up"), await where());
    await kia.context().close();

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    ok("no page error", rec.errors.filter(m => !/Failed to load resource/.test(m)).length === 0, rec.errors.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
