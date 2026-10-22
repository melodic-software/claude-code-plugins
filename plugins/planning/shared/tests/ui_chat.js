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
const { loadPlaywright, suite, recorder, until, settled, joinAs } = require("./browser_harness");
// The iOS Safari keyboard, as WebKit implements it. The layout viewport and innerHeight stay; visualViewport's height
// drops by the keyboard (https://www.bram.us/2021/09/13/prevent-items-from-being-hidden-underneath-the-virtual-keyboard-by-means-of-the-virtualkeyboard-api/).
// On an iPhone a focused text field always forces a reveal (WKContentViewInteraction.mm passes requiresAccessoryView as
// forceScroll), which centers the field in the height left above the keyboard, clamped to the document, over 0.25 s
// (WKWebViewIOS.mm _zoomToFocusRect): that pan is visualViewport.offsetTop. visualViewport fires resize along the way
// and scroll only once the pan stops (https://bugs.webkit.org/show_bug.cgi?id=218465); a resize handler can read
// offsetTop 0 that reads right a moment later (https://bugs.webkit.org/show_bug.cgi?id=237851), which `stale` makes
// the last event; `pan` sets the pan outright. KB (336 px, by judgment from an iPhone 13 with the suggestion bar) is the
// default keyboard height.
const KB = 336;
const keyboard = (page, up, { kb = KB, stale = false, pan: setPan = null } = {}) => page.evaluate(async ([up, kb, stale, setPan]) => {
  const vv = window.visualViewport, ih = innerHeight, h0 = vv.height, top0 = vv.offsetTop, h1 = up ? ih - kb : ih;
  const set = (h, top) => { for (const [k, v] of [["height", h], ["offsetTop", top]]) Object.defineProperty(vv, k, { configurable: true, get: () => v }); };
  let pan = 0;
  const f = document.activeElement;
  if (up && f && f !== document.body) {
    const r = f.getBoundingClientRect(), space = (h1 - r.height) / 2;
    pan = space > 0 ? r.top - space : Math.min(Math.max(top0, r.top - h1 / 2), r.top);
    pan = Math.min(Math.max(0, pan), document.documentElement.scrollHeight - h1);
  }
  if (up && setPan !== null) pan = setPan;
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
}, [up, kb, stale, setPan]);
/** Two frames: a scroll set from script has fired its scroll event by then. */
const frames = page => page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
/** The chat list at rest: its scrollTop unchanged through 250 ms of frames (5 s at most). */
const atRest = page => page.evaluate(() => new Promise(res => {
  const sc = document.querySelector(".vf-mscroll"), t0 = performance.now();
  let last = sc.scrollTop, since = t0;
  const f = now => {
    if (sc.scrollTop !== last) { last = sc.scrollTop; since = now; }
    if (now - since >= 250 || now - t0 > 5000) res(); else requestAnimationFrame(f);
  };
  requestAnimationFrame(f);
}));

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
    await frames(owner);
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
    // Held until the menu opens, as a person holds: the page opens it 500 ms in, later on a busy machine.
    await until(pia, () => { const m = document.querySelector(".vf-msgmenu"); return !!m && !m.hidden; });
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
    // The WAI-ARIA APG toggle button: aria-pressed carries the state, and the label names no action that flips with it.
    const chipA11y = page => page.evaluate(() => { const li = [...document.querySelectorAll(".vf-mlist .vf-msg")].find(m => m.textContent.includes("New C")); const c = li?.querySelector(".vf-mreact"); return c && [c.getAttribute("aria-pressed"), c.getAttribute("aria-label")]; });
    const [onP, onL] = (await chipA11y(pia)) || [], [offP, offL] = (await chipA11y(owner)) || [];
    ok("  the chip is a toggle: pressed for the reactor, not for the host, and its label names no action (APG)", onP === "true" && offP === "false"
      && ![onL, offL].some(l => !l || /take|add|back/i.test(l)), JSON.stringify({ onP, onL, offP, offL }));
    if (await pia.locator(".vf-msg", { hasText: "New C" }).locator(".vf-mreact").count()) await pia.locator(".vf-msg", { hasText: "New C" }).locator(".vf-mreact").tap();
    const rowGone = page => until(page, () => { const li = [...document.querySelectorAll(".vf-mlist .vf-msg")].find(m => m.textContent.includes("New C")); const r = li?.querySelector(".vf-mreacts"); return !!li && !li.querySelector(".vf-mreact") && (!r || r.getBoundingClientRect().height === 0); });
    ok("tapping the chip takes the reaction back and the row goes away", await rowGone(pia) && await rowGone(owner));

    // ---------- dogfood: at the newest message, the phone keyboard never hides it ----------
    for (let i = 0; i < 3; i++) await gus.evaluate(x => window.Core.chat(x), `More ${i} ${"so the chat scrolls ".repeat(3)}`);
    const kia = await rec.open(A.localUrl, { context: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 } });
    await joinAs(kia, "Kia");
    await kia.evaluate(() => { document.querySelector(".vf-fab").click(); });
    const n20 = await until(kia, () => document.querySelectorAll(".vf-mlist .vf-msg").length >= 20 && [...document.querySelectorAll(".vf-mlist .vf-msg")].pop().textContent.includes("More 2"));
    const kiaStill = await settled(kia, { rects: true });
    // The newest message whole between the list's top edge and the message field, inside the visual viewport.
    const newest = text => until(kia, t => {
      const sc = document.querySelector(".vf-mscroll").getBoundingClientRect(), form = document.querySelector(".vf-mform").getBoundingClientRect();
      const last = [...document.querySelectorAll(".vf-mlist .vf-msg")].pop(), r = last.getBoundingClientRect(), vv = visualViewport;
      return last.textContent.includes(t) && r.top >= sc.top - 0.5 && r.bottom <= Math.min(sc.bottom, form.top) + 0.5 && form.bottom <= vv.offsetTop + vv.height + 0.5;
    }, text, 3000);
    const where = () => kia.evaluate(() => { const sc = document.querySelector(".vf-mscroll"); return `${sc.scrollHeight - sc.scrollTop - sc.clientHeight} px below the list's bottom edge, visual viewport ${visualViewport.height}`; });
    await kia.locator(".vf-minput").tap();
    await keyboard(kia, true);
    ok("390x844, 20+ messages, at the newest: with the keyboard up the newest message is whole above the field", n20 && kiaStill && await newest("More 2"), `${await where()}${kiaStill ? "" : ", not settled"}`);
    if (process.env.KBD_SHOTS) { const vv = await kia.evaluate(() => [visualViewport.offsetTop, visualViewport.height]); await kia.screenshot({ path: require("node:path").join(process.env.KBD_SHOTS, "chat-390x844-keyboard.png"), clip: { x: 0, y: vv[0], width: 390, height: vv[1] } }); }
    await kia.keyboard.insertText("Line one\nLine two\nLine three");
    ok("390x844, keyboard up: typing 3 lines keeps the newest message in view", await newest("More 2"), await where());
    await gus.evaluate(() => window.Core.chat("Arrived with the keyboard up"));
    ok("390x844, keyboard up: a message that arrives shows whole above the field", await newest("Arrived with the keyboard up"), await where());
    await kia.evaluate(() => { document.querySelector(".vf-mscroll").scrollTop = 0; });
    await frames(kia);
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

    // ---------- dogfood: the chat scrolls by touch with an iOS keyboard, and the composer sits on the keyboard ----------
    // iPhones with a home indicator have a 34 px bottom safe area (Apple's Human Interface Guidelines, Layout); the
    // check sets it where Chromium can, so the sheet's bottom padding counts.
    for (let i = 0; i < 10; i++) await gus.evaluate(x => window.Core.chat(x), `Later ${i} ${"to give the chat more to scroll ".repeat(2)}`);
    const chatPhone = async (w, h, name) => {
      const p = await rec.open(A.localUrl, { context: { viewport: { width: w, height: h }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 } });
      const c = await p.context().newCDPSession(p);
      await c.send("Emulation.setSafeAreaInsetsOverride", { insets: { bottom: 34 } }).catch(() => null);
      await joinAs(p, name);
      shell.push(...(await docScroll(p)).map(x => `${name}, default view: ${x}`));
      await p.locator(".vf-fab").tap();
      await until(p, () => document.querySelectorAll(".vf-mlist .vf-msg").length >= 30 && [...document.querySelectorAll(".vf-mlist .vf-msg")].pop().textContent.includes("Later 9"), null, 5000);
      if (!(await settled(p, { rects: true }))) shell.push(`${name}, chat open: did not settle`);
      const f = await p.evaluate(() => document.activeElement?.className || "");
      if (/vf-minput/.test(f)) autoFocus.push(`${name}: opening the chat focused the message box`);
      shell.push(...(await docScroll(p)).map(x => `${name}, chat open: ${x}`));
      return [p, c];
    };
    // The page shell never scrolls: the document is no taller or wider than the viewport, and stays at 0.
    const docScroll = p => p.evaluate(() => { const se = document.scrollingElement; return [...(se.scrollHeight > se.clientHeight || se.scrollWidth > se.clientWidth ? [`document ${se.scrollWidth}x${se.scrollHeight} in ${se.clientWidth}x${se.clientHeight}`] : []), ...(se.scrollTop || se.scrollLeft ? [`document scrolled to ${se.scrollLeft},${se.scrollTop}`] : [])]; });
    const shell = [], autoFocus = [];
    const [sia, scdp] = await chatPhone(390, 844, "Sia");
    const stuck = [];
    for (const [kbUp, pan] of [[false, 0], [true, 0], [true, 40]]) {
      const what = kbUp ? `keyboard up, pan ${pan}` : "keyboard down";
      if (kbUp) { await sia.locator(".vf-minput").tap(); await keyboard(sia, true, { pan }); }
      await sia.evaluate(() => { const sc = document.querySelector(".vf-mscroll"); sc.scrollTop = sc.scrollHeight; });
      await frames(sia);
      const [x, y, st0] = await sia.evaluate(() => { const sc = document.querySelector(".vf-mscroll"), r = sc.getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2, sc.scrollTop]; });
      await scdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x, y: y - 150 }] });
      for (let i = 1; i <= 15; i++) { await scdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x, y: y - 150 + i * 20 }] }); await sia.waitForTimeout(16); }
      await scdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
      await atRest(sia); // the fling after the drag comes to rest
      const st1 = await sia.evaluate(() => document.querySelector(".vf-mscroll").scrollTop);
      // iOS keeps firing visualViewport scroll and resize while a page is touched; the list must stay where it was put.
      await sia.evaluate(async () => { for (let i = 0; i < 10; i++) { visualViewport.dispatchEvent(new Event("scroll")); visualViewport.dispatchEvent(new Event("resize")); await new Promise(r => setTimeout(r, 100)); } });
      const [st2, page] = await sia.evaluate(() => [document.querySelector(".vf-mscroll").scrollTop, document.scrollingElement.scrollTop + document.scrollingElement.scrollLeft]);
      if (!(st1 < st0 - 100)) stuck.push(`${what}: a 300 px drag moved the list from ${st0.toFixed(0)} to ${st1.toFixed(0)}`);
      else if (Math.abs(st2 - st1) > 2) stuck.push(`${what}: the list went back from ${st1.toFixed(0)} to ${st2.toFixed(0)} within 1 s`);
      if (page) stuck.push(`${what}: the page scrolled ${page} px`);
      if (kbUp) await keyboard(sia, false);
    }
    ok("390x844, 30+ messages: a touch drag scrolls the chat up and it stays for 1 s, keyboard down and up (pan 0 and 40 px), the page never scrolls", stuck.length === 0, stuck.join("; "));
    await sia.context().close();
    for (const [w, h] of [[390, 844], [375, 667]]) {
      const [cp] = await chatPhone(w, h, `Cp ${w}`);
      const gaps = [];
      for (const kb of [300, 350, 400, 450]) {
        await cp.locator(".vf-minput").tap();
        await keyboard(cp, true, { kb });
        // iOS can also scroll a scrollable document to bring the field into view; the shell must not move.
        await cp.evaluate(() => new Promise(r => { window.scrollTo(0, 80); requestAnimationFrame(() => requestAnimationFrame(r)); }));
        shell.push(...(await docScroll(cp)).map(x => `${w}x${h}, keyboard ${kb} up: ${x}`));
        const g = await cp.evaluate(() => { const f = document.querySelector(".vf-mform").getBoundingClientRect(), vv = visualViewport; return [f.bottom, vv.offsetTop + vv.height, f.top]; });
        if (Math.abs(g[0] - g[1]) > 2 || g[2] < 0) gaps.push(`keyboard ${kb}: composer bottom ${g[0].toFixed(0)}, keyboard top ${g[1].toFixed(0)}`);
        await keyboard(cp, false);
        await cp.evaluate(() => document.activeElement?.blur());
      }
      ok(`${w}x${h}, keyboard 300 to 450 px: the chat composer's bottom edge sits within 2 px of the keyboard's top, even after a document scroll attempt`, gaps.length === 0, gaps.join("; "));
      await cp.context().close();
    }
    ok("touch phones: opening the chat leaves the message box unfocused, so the keyboard waits for a tap", autoFocus.length === 0, autoFocus.join("; "));
    ok("phones: the document never scrolls, in the default view, with the chat open, and with the keyboard up", shell.length === 0, shell.join("; "));

    // ---------- triage 46: a mention points at the person, so a rename shows in it, and Copy gives "@Name" ----------
    const mau = await rec.open(A.localUrl);
    await joinAs(mau, "Maude");
    await until(gus, () => Object.values(window.Core.state.people).some(p => p.name === "Maude"));
    await gus.evaluate(() => window.Core.chat("@Maude can you check the card field?"));
    const chipIs = want => until(owner, w => { const li = [...document.querySelectorAll(".vf-mlist .vf-msg")].find(m => m.textContent.includes("can you check the card field?"));
      return !!li && li.querySelector(".vf-mention")?.textContent === w; }, want);
    ok("a mention shows as a chip with the person's name", await chipIs("@Maude"));
    await mau.evaluate(() => window.Core.rename("Courtney"));
    ok("after Maude renames herself Courtney, the chip in the message she was mentioned in shows @Courtney", await chipIs("@Courtney"));
    await owner.evaluate(() => { window.__copied = null; navigator.clipboard.writeText = t => { window.__copied = t; return Promise.resolve(); }; });
    await owner.locator(".vf-msg", { hasText: "can you check the card field?" }).locator(".vf-msgmore").click();
    await owner.locator(".vf-msgmenu [role=menuitem]", { hasText: "Copy" }).click();
    const copied = await until(owner, () => window.__copied) && await owner.evaluate(() => window.__copied);
    ok("Copy gives the message as \"@Courtney can you check the card field?\"", copied === "@Courtney can you check the card field?", JSON.stringify(copied));
    const raw = await owner.evaluate(() => { const t = [document.documentElement.textContent, ...[...document.querySelectorAll("*")].flatMap(e => [...e.attributes].map(a => a.value)), ...[...document.querySelectorAll("input, textarea")].map(e => e.value)].join("\n"); return (t.match(/<@[A-Za-z0-9_-]+>/) || [""])[0]; });
    ok("no raw mention token anywhere on the page, its attributes or its fields", raw === "", raw);

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    ok("no page error", rec.errors.filter(m => !/Failed to load resource/.test(m)).length === 0, rec.errors.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
