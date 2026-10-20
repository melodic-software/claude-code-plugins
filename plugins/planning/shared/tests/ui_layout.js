#!/usr/bin/env node
// Layout in real browsers, against `share.sh ensure-running` with the fake cloudflared: no page scroll at 390x844,
// 768x1024, 1024x768, 1440x900 and 2560x1440, dark and light, in a guest's Focus on a choice question and on a text
// question, Compare, Tree, the chat open, and the owner's Host view; the same at 200% zoom (720x450 and 640x400 CSS px
// at device scale 2). On a 390x844 phone with touch, in Focus: every visible control's hit area is at least 44x44 CSS
// px and no visible element sticks out past the viewport, nor with Ask Claude open and "Run it on my own Claude" on,
// where nothing in the panel scrolls sideways either. At 390x844 and 1440x900 the answer composer starts within
// 24 px below the question block (question text, options, and the hint and note lines around them). A new guest's
// first view shows the goal, the host's ask and "Start here: question 1" in view (triage 3); the ten person colors
// meet WCAG 2.2 AA in both themes (C40); editing a saved answer on a phone is a full-height sheet (triage 18). With
// an iOS keyboard of 300 to 600 px at 390x844 and 260 to 430 px at 375x667, Ask Claude shows the label, the field's
// first 3 lines and Send request uncovered above it, the sheet at its top, and it scrolls down to "Your requests".
// Ask Claude's tabs are Ask, Research and Explore, and the line under them opens the Propose form; that form, opened
// from the question list at 320 to 430 px wide with a keyboard of 260 px up, shows its label, the field's first 3
// lines and Propose above the keyboard, nothing in it clipped or scrolling sideways (triage 36, 44). At 320, 375, 390
// and 430 px wide the page never scrolls sideways, in the default
// view, with the chat open, or in Ask Claude with the keyboard up, and at 320 nothing in Ask Claude is clipped sideways.
// Pinch-zoomed to 1.5, 2 and 3, the page still reads an iOS keyboard as one, and the zoom alone as none. The Inbox page
// on a phone keeps a request being edited, its question line and Save above a 260 to 430 px keyboard.
//   node plugins/planning/shared/tests/ui_layout.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the layout requirements of the polish plan (the sizes, the 1 px tolerance, 44x44 CSS px
// from WCAG 2.5.5 Target Size, the 24 px composer gap) and the 200% zoom sizes worked out by hand (1440x900 / 2 =
// 720x450, 1280x800 / 2 = 640x400), never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, snap, joinAs } = require("./browser_harness");

const SIZES = [[390, 844], [768, 1024], [1024, 768], [1440, 900], [2560, 1440]];
const ZOOMED = [[720, 450, "1440x900 at 200%"], [640, 400, "1280x800 at 200%"]];
const TOL = 1, MIN_HIT = 44, COMPOSER_GAP = 24;
const PHONE = { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 };
const CHOICE = "Which default payment method?", TEXT = "Where should the order summary sit?", GOAL = "Pick the checkout we launch with.";
const q = (id, text, format) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format });
// The iOS Safari keyboard, as WebKit implements it. The layout viewport and innerHeight stay; visualViewport's height
// drops by the keyboard (https://www.bram.us/2021/09/13/prevent-items-from-being-hidden-underneath-the-virtual-keyboard-by-means-of-the-virtualkeyboard-api/).
// On an iPhone a focused text field always forces a reveal (WKContentViewInteraction.mm passes requiresAccessoryView as
// forceScroll), which centers the field in the height left above the keyboard, clamped to the document, over 0.25 s
// (WKWebViewIOS.mm _zoomToFocusRect): that pan is visualViewport.offsetTop. visualViewport fires resize along the way
// and scroll only once the pan stops (https://bugs.webkit.org/show_bug.cgi?id=218465); a resize handler can read
// offsetTop 0 that reads right a moment later (https://bugs.webkit.org/show_bug.cgi?id=237851), which `stale` makes
// the last event; `pan` sets the pan outright. KB (336 px, by judgment from an iPhone 13 with the suggestion bar) is the
// default keyboard height. `scale` pinch-zooms the page first, as WebKit reports it: visualViewport.scale is the zoom,
// its width and height shrink by it (the keyboard's screen height too), and so do innerWidth and innerHeight, which
// WebKit keeps on the visual viewport (https://bugs.webkit.org/show_bug.cgi?id=174362); closing undoes the zoom.
const KB = 336;
const keyboard = (page, up, { kb = KB, stale = false, pan: setPan = null, scale = 1 } = {}) => page.evaluate(async ([up, kb, stale, setPan, scale]) => {
  const vv = window.visualViewport, lift = (o, k, v) => Object.defineProperty(o, k, { configurable: true, get: () => v });
  if (window.vvZoomed) { for (const [k, d] of Object.entries(window.vvZoomed)) Object.defineProperty(window, k, d); delete window.vvZoomed; delete vv.width; delete vv.scale; }
  if (up && scale !== 1) {
    window.vvZoomed = Object.fromEntries(["innerWidth", "innerHeight"].map(k => [k, Object.getOwnPropertyDescriptor(window, k) || Object.getOwnPropertyDescriptor(Window.prototype, k)]));
    for (const [k, v] of [["innerWidth", innerWidth / scale], ["innerHeight", innerHeight / scale]]) lift(window, k, v);
    lift(vv, "width", innerWidth); lift(vv, "scale", scale);
  }
  const ih = innerHeight, h0 = vv.height, top0 = vv.offsetTop, h1 = up ? ih - kb / scale : ih;
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
}, [up, kb, stale, setPan, scale]);
/** What a person sees of the focused sheet's field: the label, the field's first 3 lines and its primary button must
 *  each be the topmost element at their sample points, inside the visual viewport, and the button's whole box inside
 *  it. Resolves to the problems found. */
const fieldSeen = (page, label, field, button) => page.evaluate(([l, f, b]) => {
  const vv = visualViewport, top = vv.offsetTop, bottom = vv.offsetTop + vv.height, out = [];
  const probe = (what, el, x, y) => {
    if (y < top + 0.5 || y > bottom - 0.5) return out.push(`${what} at y ${y.toFixed(0)} outside the visual viewport ${top.toFixed(0)}..${bottom.toFixed(0)}`);
    const hit = document.elementFromPoint(x, y);
    if (!el.contains(hit)) out.push(`${what} at y ${y.toFixed(0)} covered by ${hit ? `${hit.tagName.toLowerCase()}.${[...hit.classList].join(".")}` : "nothing"}`);
  };
  const L = document.querySelector(l), F = document.querySelector(f), B = document.querySelector(b);
  if (!L || !F || !B) return [`missing ${[!L && l, !F && f, !B && b].filter(Boolean).join(", ")}`];
  const lr = L.getBoundingClientRect(), fr = F.getBoundingClientRect(), br = B.getBoundingClientRect(), cs = getComputedStyle(F);
  const lh = parseFloat(cs.lineHeight) || 1.5 * parseFloat(cs.fontSize), pad = parseFloat(cs.paddingTop) + parseFloat(cs.borderTopWidth);
  probe("label", L, lr.left + Math.min(20, lr.width / 2), lr.top + lr.height / 2);
  for (let i = 0; i < 3; i++) for (const x of [fr.left + 16, fr.right - 16]) probe(`field line ${i + 1}`, F, x, fr.top + pad + (i + 0.5) * lh);
  probe(B.textContent.trim() || "button", B, br.left + br.width / 2, br.top + br.height / 2);
  if (br.top < top - 0.5 || br.bottom > bottom + 0.5 || br.left < -0.5 || br.right > innerWidth + 0.5) out.push(`${B.textContent.trim() || "button"} at ${br.left.toFixed(0)},${br.top.toFixed(0)} to ${br.right.toFixed(0)},${br.bottom.toFixed(0)} not whole inside the visual viewport ${top.toFixed(0)}..${bottom.toFixed(0)} by ${innerWidth}`);
  return [...new Set(out)];
}, [label, field, button]);
const settle = page => page.evaluate(() => Promise.all(document.getAnimations().filter(a => a.effect?.getTiming().iterations !== Infinity).map(a => a.finished.catch(() => null))));

/** Opens one view; resolves to "" or the reason it could not. Phone layouts use the tab bar, wider ones the view switch. */
async function show(page, view) {
  const tabs = await page.locator(".vf-tabs").isVisible().catch(() => false);
  const tab = label => page.locator(".vf-tab", { hasText: label }).click({ timeout: 5000 });
  // A guest's simple view hides the view switch behind View options; Focus goes back to the simple view after.
  const seg = async label => {
    const b = page.locator(".vf-bar .vf-seg-btn", { hasText: label }), more = page.locator(".vf-viewopts");
    if (label === "Focus" && (await page.evaluate(() => document.querySelector(".vf-center")?.dataset.mode)) === "focus") return;
    const expanded = !(await b.isVisible()) && (await more.isVisible()) && (await more.getAttribute("aria-expanded")) === "false";
    if (expanded) await more.click({ timeout: 5000 });
    await b.click({ timeout: 5000 });
    if (label === "Focus" && (await more.isVisible()) && (await more.getAttribute("aria-expanded")) === "true") await more.click({ timeout: 5000 });
  };
  try {
    // An open chat sheet makes the rest of a phone page inert, so it closes with Escape, not the chat button.
    if (await page.locator("section.vf-chat").isVisible().catch(() => false)) {
      await page.keyboard.press("Escape");
      if (!(await until(page, () => !!document.querySelector("section.vf-chat")?.hidden, null, 5000))) return "the open chat did not close";
    }
    if (view === "focus-choice" || view === "focus-text") {
      const text = view === "focus-choice" ? CHOICE : TEXT;
      if (tabs) await tab("Questions"); else await seg("Focus");
      await page.locator(".vf-q", { hasText: text }).first().click({ timeout: 5000 });
      if (tabs && !(await page.locator(".vf-qtext").isVisible())) await tab("Answer");
      if (!(await until(page, t => document.querySelector(".vf-qtext")?.textContent === t && !!document.querySelector(".vf-qtext").offsetParent, text, 5000))) return "the question did not open";
    } else if (view === "compare" || view === "tree") {
      const label = view === "compare" ? "Compare" : "Tree";
      if (tabs) await tab(label); else await seg(label);
      if (!(await until(page, m => document.querySelector(".vf-center")?.dataset.mode === m, view, 5000))) return `${label} did not open`;
    } else if (view === "chat") {
      await page.locator(".vf-fab").click({ timeout: 5000 });
      if (!(await until(page, () => !!document.querySelector("section.vf-chat:not([hidden])")?.offsetParent, null, 5000))) return "the chat did not open";
    } else if (view === "host") {
      if (tabs) { await tab("More"); await page.locator(".vf-msitem", { hasText: "Host view" }).click({ timeout: 5000 }); } else await seg("Host");
      if (!(await until(page, () => document.querySelector(".vf-center")?.dataset.mode === "host", null, 5000))) return "Host did not open";
    }
  } catch (e) { const l = String(e.message).split("\n"); return [l[0], ...l.filter(x => /intercepts|not visible|waiting for locator/.test(x)).slice(-2)].join(" ").replace(/\s+/g, " "); }
  // Measure the settled layout: an opening sheet slides in with a transform, which counts as overflow mid-flight.
  await page.evaluate(() => Promise.all(document.getAnimations().filter(a => a.effect?.getTiming().iterations !== Infinity).map(a => a.finished.catch(() => null))));
  await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
  await page.waitForTimeout(150);
  return "";
}

/** Page and #app scroll extents against the viewport. */
const extents = page => page.evaluate(() => {
  const s = document.scrollingElement, a = document.getElementById("app");
  // The outermost elements in #app that reach past the viewport, to name in a failure.
  const beyond = el => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 && (r.bottom > innerHeight + 1 || r.right > innerWidth + 1); };
  const past = [...a.querySelectorAll("*")].filter(el => beyond(el) && !(el.parentElement !== a && beyond(el.parentElement))).slice(0, 4)
    .map(c => { const r = c.getBoundingClientRect(); return `${c.tagName.toLowerCase()}.${[...c.classList].join(".")} ${r.left.toFixed(0)},${r.top.toFixed(0)} to ${r.right.toFixed(0)},${r.bottom.toFixed(0)}`; });
  return { iw: innerWidth, ih: innerHeight, sw: s.scrollWidth, sh: s.scrollHeight, aw: a.scrollWidth, ah: a.scrollHeight, past };
});
const fits = e => e.sw <= e.iw + 1 && e.sh <= e.ih + 1 && e.aw <= e.iw + 1 && e.ah <= e.ih + 1;
const fmt = e => `page ${e.sw}x${e.sh}, #app ${e.aw}x${e.ah}, viewport ${e.iw}x${e.ih}${e.past.length ? `; past it: ${e.past.join(", ")}` : ""}`;

/** One size: a joined guest and the owner, every view in dark and light. Pushes one check per size and scheme. */
async function sweep(s, rec, A, label, context, n) {
  const guest = await rec.open(A.localUrl, { context });
  await joinAs(guest, `Lay${n}`);
  const owner = await rec.open(A.ownerUrl, { context });
  await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
  for (const scheme of ["dark", "light"]) {
    for (const p of [guest, owner]) await p.emulateMedia({ colorScheme: scheme });
    const themed = await until(guest, t => document.getElementById("app").dataset.theme === t, scheme, 5000);
    const bad = [];
    if (!themed) bad.push(`the page did not switch to ${scheme}`);
    for (const [page, view] of [[guest, "focus-choice"], [guest, "focus-text"], [guest, "compare"], [guest, "tree"], [guest, "chat"], [owner, "host"]]) {
      const why = await show(page, view);
      if (why) { bad.push(`${view}: ${why}`); continue; }
      const e = await extents(page);
      if (!fits(e)) bad.push(`${view}: ${fmt(e)}`);
    }
    s.ok(`${label} ${scheme}: no page scroll in Focus (choice, text), Compare, Tree, chat open, Host`, bad.length === 0, bad.join("; "));
  }
  for (const p of [guest, owner]) await p.context().close();
}

/** Controls whose hit area (their own box, or the label around an input) is under the minimum. */
const smallTargets = (page, min) => page.evaluate(min => {
  const shown = el => { const r = el.getBoundingClientRect(), cs = getComputedStyle(el); return r.width > 1 && r.height > 1 && cs.visibility !== "hidden" && !el.closest("[hidden], dialog:not([open])"); };
  const sel = "button, a[href], input:not([type=hidden]), select, textarea, [role=button], [tabindex='0']";
  const out = [];
  for (const el of document.querySelectorAll(sel)) {
    if (!shown(el)) continue;
    let r = el.getBoundingClientRect();
    const lab = el.matches("input, select, textarea") && el.closest("label");
    if (lab) { const l = lab.getBoundingClientRect(); r = { width: Math.max(r.right, l.right) - Math.min(r.left, l.left), height: Math.max(r.bottom, l.bottom) - Math.min(r.top, l.top) }; }
    if (r.width < min - 0.01 || r.height < min - 0.01) {
      const name = (el.getAttribute("aria-label") || el.textContent || el.placeholder || "").trim().replace(/\s+/g, " ").slice(0, 30);
      out.push(`${el.tagName.toLowerCase()}.${[...el.classList].join(".")} "${name}" ${r.width.toFixed(0)}x${r.height.toFixed(0)}`);
    }
  }
  return out;
}, min);

/** Visible elements past the viewport's left or right edge, unless an ancestor clips them inside the viewport. */
const overflowing = page => page.evaluate(tol => {
  const iw = innerWidth, out = [];
  for (const el of document.body.querySelectorAll("*")) {
    const r = el.getBoundingClientRect(), cs = getComputedStyle(el);
    if (r.width <= 1 || r.height <= 1 || cs.visibility === "hidden" || el.closest("[hidden], dialog:not([open])")) continue;
    if (r.right <= iw + tol && r.left >= -tol) continue;
    let clipped = false;
    for (let a = el.parentElement; a && a !== document.documentElement; a = a.parentElement) {
      const ac = getComputedStyle(a);
      if (ac.overflowX !== "visible" || ac.clipPath !== "none") { const ar = a.getBoundingClientRect(); if (ar.right <= iw + tol && ar.left >= -tol) { clipped = true; break; } }
    }
    if (!clipped) out.push(`${el.tagName.toLowerCase()}.${[...el.classList].join(".")} left ${r.left.toFixed(0)} right ${r.right.toFixed(0)}`);
  }
  return out;
}, TOL);

/** Visible scroll containers in `root` (itself included) that scroll sideways: content wider than the box, which
 *  `overflowing` cannot see because the box itself clips it inside the viewport. */
const sideScroll = (page, root) => page.evaluate(([tol, root]) => {
  const out = [], top = document.querySelector(root);
  for (const el of top ? [top, ...top.querySelectorAll("*")] : []) {
    const cs = getComputedStyle(el);
    if (!/auto|scroll/.test(cs.overflowX) || el.closest("[hidden], dialog:not([open])") || el.clientWidth <= 1) continue;
    if (el.scrollWidth > el.clientWidth + tol) out.push(`${el.tagName.toLowerCase()}.${[...el.classList].join(".")} content ${el.scrollWidth} in ${el.clientWidth}`);
  }
  return top ? out : [`no ${root}`];
}, [TOL, root]);

/** Bottom of the question block (text, options, hint) and top of the composer, in viewport px. */
const composerGap = page => page.evaluate(() => {
  const vis = el => el && el.getClientRects().length && getComputedStyle(el).visibility !== "hidden" && !el.closest("[hidden]");
  // The hint line above the options and the note line under them both belong to the options.
  const parts = [".vf-qtext", ".vf-fmt-hint", ".vf-opts", ".vf-fmt-note"].map(s => document.querySelector(s)).filter(vis);
  const c = document.querySelector(".vf-composer");
  if (!parts.length || !vis(c)) return { missing: `${parts.length} question parts, composer ${vis(c) ? "shown" : "not shown"}` };
  const qb = Math.max(...parts.map(p => p.getBoundingClientRect().bottom)), ct = c.getBoundingClientRect().top;
  // What sits in the gap, to name in a failure.
  const inGap = el => { const r = el.getBoundingClientRect(); return vis(el) && r.height > 0 && r.top >= qb - 0.5 && r.bottom <= ct + 0.5; };
  const between = [...document.querySelectorAll(".vf-scroll *")].filter(el => inGap(el) && !inGap(el.parentElement)).slice(0, 4).map(el => { const r = el.getBoundingClientRect(); return `${el.tagName.toLowerCase()}.${[...el.classList].join(".")} ${r.top.toFixed(0)}-${r.bottom.toFixed(0)}`; });
  return { qb, ct, gap: ct - qb, between };
});

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_layout.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_layout"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("layout");
    s.apply(A.dir, [{ op: "set-title", title: "Checkout layout" }, { op: "set-goal", goal: GOAL }, { op: "open-round", questions: [
      q("Q1", CHOICE, { kind: "choice", options: [{ id: "opt-1", label: "Card" }, { id: "opt-2", label: "Saved method" }, { id: "opt-3", label: "Pay later" }] }),
      q("Q2", TEXT, { kind: "text" }),
      q("Q3", "What worries you about the new checkout?", { kind: "text" }),
    ] }]);
    // Some answers, so Compare and Tree have cards to lay out.
    const seed = await rec.open(A.localUrl);
    await joinAs(seed, "Seed");
    for (const [text, answer] of [[TEXT, "Below the total, always visible."], ["What worries", "That people lose their basket when the card fails."]]) {
      await seed.locator(".vf-q", { hasText: text }).first().click();
      await seed.locator("#vf-answer").fill(answer);
      await seed.press("#vf-answer", "Control+Enter");
    }
    await until(seed, () => Object.keys(window.Core.snapshot()?.cards || {}).length >= 2);
    await seed.context().close();

    let n = 0;
    for (const [w, h] of SIZES) {
      const context = w <= 390 ? PHONE : { viewport: { width: w, height: h } };
      await sweep(s, rec, A, `${w}x${h}`, context, ++n);
    }
    for (const [w, h, label] of ZOOMED) await sweep(s, rec, A, label, { viewport: { width: w, height: h }, deviceScaleFactor: 2 }, ++n);

    // ---------- the phone in Focus: hit areas and horizontal overflow ----------
    const pia = await rec.open(A.localUrl, { context: PHONE });
    await joinAs(pia, "Pia");
    const why = await show(pia, "focus-choice");
    ok("390x844 phone: the choice question opens in Focus", !why, why);
    const small = await smallTargets(pia, MIN_HIT);
    ok(`390x844 phone, Focus: every visible control's hit area is at least ${MIN_HIT}x${MIN_HIT} CSS px`, small.length === 0, `${small.length}: ${small.join("; ")}`);
    const over = await overflowing(pia);
    ok("390x844 phone, Focus: no visible element sticks out past the viewport", over.length === 0, `${over.length}: ${over.slice(0, 12).join("; ")}`);

    // ---------- the phone, Ask Claude with "Run it on my own Claude" on: nothing scrolls sideways ----------
    await pia.evaluate(() => document.querySelector(".vf-asktop").click());
    const asked = await until(pia, () => !!document.querySelector(".vf-drawer:not([hidden]) .vf-apform"));
    await pia.click(".vf-apself");
    const connected = await until(pia, () => !document.querySelector(".vf-apconnect").hidden);
    await pia.evaluate(() => Promise.all(document.getAnimations().map(a => a.finished.catch(() => null))));
    const side = [...(await sideScroll(pia, ".vf-drawer:not([hidden])")), ...(await overflowing(pia))];
    ok("390x844 phone, Ask Claude with \"Run it on my own Claude\" on: no horizontal scroll and nothing past the viewport", asked && connected && side.length === 0,
      `${asked} ${connected} ${side.length}: ${side.slice(0, 8).join("; ")}`);
    await pia.keyboard.press("Escape");

    // ---------- dogfood: the Ask Claude sheet with an iOS keyboard of every plausible height ----------
    // Keyboard heights from 300 to 600 px at 390x844 and 260 to 430 at 375x667 (a small iPhone), each with WebKit's
    // centering pan, and one where the last resize reads offsetTop 0. The label, the field's first 3 lines and Send
    // request are seen above the keyboard and the sticky row, the button whole, and the sheet sits at its top. What the
    // form shows runs down the page in DOM order, and once the keyboard closes every part it showed before is back.
    const shot = async (p, name) => {
      if (!process.env.KBD_SHOTS) return;
      const vv = await p.evaluate(() => [visualViewport.offsetTop, visualViewport.height, innerWidth]);
      await p.screenshot({ path: require("node:path").join(process.env.KBD_SHOTS, `${name}.png`), clip: { x: 0, y: vv[0], width: vv[2], height: vv[1] } });
    };
    const docScrolls = async p => {
      const d = await p.evaluate(() => new Promise(r => { window.scrollTo(0, 80); requestAnimationFrame(() => requestAnimationFrame(() => { const se = document.scrollingElement; r([se.scrollHeight - se.clientHeight, se.scrollTop]); })); }));
      return d[0] > 0 || d[1] ? [`the document scrolls (${d[0]} px more than the viewport, at ${d[1]})`] : [];
    };
    const SWEEP = [[390, 844, [300, 350, 400, 450, 500, 550, 600], 450], [375, 667, [260, 310, 360, 410, 430], 360]];
    for (const [w, h, kbs, staleKb] of SWEEP) {
      const sp = await rec.open(A.localUrl, { context: { ...PHONE, viewport: { width: w, height: h } } });
      await joinAs(sp, `Kb ${w}`);
      await sp.evaluate(() => document.querySelector(".vf-asktop").click());
      await until(sp, () => !!document.querySelector(".vf-drawer:not([hidden]) .vf-apform"));
      await settle(sp);
      const bad = [];
      // The form's parts a person sees, in DOM order, and whether they also run down the page in that order (a sticky
      // row floats over what scrolls under it, so it has no place in that order).
      const parts = () => sp.evaluate(() => {
        const shown = [...document.querySelector(".vf-apform").children].filter(c => c.getClientRects().length);
        const tops = shown.filter(c => getComputedStyle(c).position !== "sticky").map(c => c.getBoundingClientRect().top);
        return { names: shown.map(c => c.className), inOrder: tops.every((t, i) => !i || t >= tops[i - 1] - 0.5) };
      });
      const closed = await parts();
      for (const [kb, stale] of [...kbs.map(k => [k, false]), [staleKb, true]]) {
        await sp.evaluate(() => { document.activeElement?.blur(); document.querySelector(".vf-apscroll").scrollTop = 0; });
        await sp.locator("#vf-ap-ta").tap();
        await keyboard(sp, true, { kb, stale });
        const seen = await fieldSeen(sp, ".vf-apform .vf-asklabel", "#vf-ap-ta", ".vf-apform .vf-btn-primary");
        const st = await sp.evaluate(() => document.querySelector(".vf-apscroll").scrollTop);
        if (st > 0.5) seen.push(`the sheet scrolled ${st.toFixed(0)} px from its top`);
        seen.push(...(await docScrolls(sp)));
        const up = await parts();
        if (!up.inOrder) seen.push(`the form's parts are out of DOM order on screen: ${up.names.join(", ")}`);
        if (seen.length) bad.push(`keyboard ${kb}${stale ? " (offsetTop read 0)" : ""}: ${seen.join(", ")}`);
        if (kb === kbs[kbs.length - 1] && !stale) await shot(sp, `ask-${w}x${h}-kb${kb}`);
        await keyboard(sp, false);
        const back = await parts();
        if (back.names.join() !== closed.names.join() || !back.inOrder) bad.push(`keyboard ${kb}${stale ? " (offsetTop read 0)" : ""}, closed again: the form shows ${back.names.join(", ")}, not ${closed.names.join(", ")}`);
      }
      ok(`${w}x${h}, Ask Claude, keyboard ${kbs[0]} to ${kbs[kbs.length - 1]} px: the label, the field's first 3 lines and Send request are seen above the keyboard, the sheet at its top, the form in DOM order, every part back once it closes, the document never scrolled`, bad.length === 0, bad.join("; "));
      await sp.context().close();
    }

    // ---------- triage 36: Ask Claude holds only requests Claude runs; the line under its title opens Propose ----------
    for (const [label, context] of [["390x844", PHONE], ["1440x900", { viewport: { width: 1440, height: 900 } }]]) {
      const g = await rec.open(A.localUrl, { context });
      await joinAs(g, `Point ${label}`);
      await g.evaluate(() => document.querySelector(".vf-asktop").click());
      await until(g, () => !!document.querySelector(".vf-drawer:not([hidden])"));
      await settle(g);
      const tabs = await g.evaluate(() => [...document.querySelectorAll(".vf-apmodes [role=tab]")].filter(t => t.getClientRects().length).map(t => t.textContent));
      const line = await g.evaluate(() => document.querySelector(".vf-drawer .vf-ap-pointer")?.textContent || "");
      const opened = await g.locator(".vf-ap-propose").click({ timeout: 3000 }).then(() => true, () => false) && await until(g, () => !document.querySelector(".vf-proposepop").hidden && document.querySelector(".vf-drawer").hidden && document.activeElement?.id === "vf-prop-ta", null, 3000);
      ok(`${label}: a guest's Ask Claude has no kind tabs (follow-up item 2), and "Propose a question" under its title closes it and opens the Propose form, its field focused`,
        tabs.join() === "" && line === "Want the group asked something? Propose a question" && opened, JSON.stringify({ tabs, line, opened }));
      await g.context().close();
    }

    // ---------- triage 44: the Propose form, from the question list, with an iOS keyboard ----------
    // At 320, 375, 390 and 430 px wide, keyboards from 260 px up to what leaves about the room the Ask Claude sweep's
    // smallest case does (375x667 under 430 px: 237 px; a 320 px iPhone is 568 tall, so 330 there), at pinch scale 1,
    // each with WebKit's centering pan and one with offsetTop read 0: the label, the field's first 3 lines and Propose
    // are seen above the keyboard, Propose whole, nothing in the form past the viewport's sides or its own, and nothing
    // in it scrolls sideways.
    const clippedSideways = (page, sel) => page.evaluate(([sel, tol]) => {
      const top = document.querySelector(sel);
      if (!top) return [`no ${sel}`];
      const T = top.getBoundingClientRect(), out = [];
      for (const el of [top, ...top.querySelectorAll("*")]) {
        const r = el.getBoundingClientRect();
        if (r.width <= 1 || r.height <= 1) continue;
        if (r.left < Math.max(0, T.left) - tol || r.right > Math.min(innerWidth, T.right) + tol) out.push(`${el.tagName.toLowerCase()}.${[...el.classList].join(".")} ${r.left.toFixed(0)} to ${r.right.toFixed(0)}, form ${T.left.toFixed(0)} to ${T.right.toFixed(0)}, viewport ${innerWidth}`);
      }
      if (top.scrollWidth > top.clientWidth + tol) out.push(`${sel} content ${top.scrollWidth} in ${top.clientWidth}`);
      return out;
    }, [sel, TOL]);
    const PSWEEP = [[320, 568, [260, 300, 330]], [375, 667, [260, 310, 360, 410, 430]], [390, 844, [260, 300, 350, 400, 430]], [430, 932, [260, 300, 350, 400, 430]]];
    for (const [w, h, kbs] of PSWEEP) {
      const pp = await rec.open(A.localUrl, { context: { ...PHONE, viewport: { width: w, height: h } } });
      await joinAs(pp, `Prop ${w}`);
      await pp.locator(".vf-tab", { hasText: "Questions" }).tap();
      await pp.locator(".vf-propose").tap();
      const opened = await until(pp, () => !!document.querySelector(".vf-proposepop:not([hidden])"), null, 3000);
      await settle(pp);
      const bad = opened ? [] : ["the form did not open"];
      for (const [kb, stale] of opened ? [...kbs.map(k => [k, false]), [kbs[kbs.length - 1], true]] : []) {
        await pp.evaluate(() => document.activeElement?.blur());
        if (!(await pp.locator("#vf-prop-ta").tap({ timeout: 5000 }).then(() => true, () => false))) { bad.push(`keyboard ${kb}: the field could not be tapped`); break; }
        await keyboard(pp, true, { kb, stale, scale: 1 });
        const seen = await fieldSeen(pp, ".vf-proposepop .vf-asklabel", "#vf-prop-ta", ".vf-proposepop button[type=submit]");
        seen.push(...(await clippedSideways(pp, ".vf-proposepop")), ...(await docScrolls(pp)));
        if (seen.length) bad.push(`keyboard ${kb}${stale ? " (offsetTop read 0)" : ""}: ${[...new Set(seen)].join(", ")}`);
        if (kb === kbs[kbs.length - 1] && !stale) await shot(pp, `propose-${w}x${h}-kb${kb}`);
        await keyboard(pp, false);
      }
      ok(`${w}x${h}, the Propose form from the question list, keyboard ${kbs[0]} to ${kbs[kbs.length - 1]} px: the label, the field's first 3 lines and Propose are seen above the keyboard, nothing clipped or scrolling sideways, the document never scrolled`, bad.length === 0, bad.join("; "));
      // Report a problem, from More: the same sheet place, so the same keyboards.
      await pp.keyboard.press("Escape");
      await pp.locator(".vf-tab", { hasText: "More" }).tap();
      await pp.locator(".vf-msitem", { hasText: "Report a problem" }).tap();
      const repOpen = await until(pp, () => !!document.querySelector(".vf-reportpop:not([hidden])"), null, 3000);
      await settle(pp);
      const rbad = repOpen ? [] : ["the form did not open"];
      for (const kb of repOpen ? kbs : []) {
        await pp.evaluate(() => document.activeElement?.blur());
        if (!(await pp.locator("#vf-rep-ta").tap({ timeout: 5000 }).then(() => true, () => false))) { rbad.push(`keyboard ${kb}: the field could not be tapped`); break; }
        await keyboard(pp, true, { kb, scale: 1 });
        const seen = await fieldSeen(pp, ".vf-reportpop .vf-asklabel", "#vf-rep-ta", ".vf-reportpop button[type=submit]");
        seen.push(...(await clippedSideways(pp, ".vf-reportpop")), ...(await docScrolls(pp)));
        if (seen.length) rbad.push(`keyboard ${kb}: ${[...new Set(seen)].join(", ")}`);
        await keyboard(pp, false);
      }
      ok(`${w}x${h}, Report a problem from More, keyboard ${kbs[0]} to ${kbs[kbs.length - 1]} px: the label, the field's first 3 lines and Send report are seen above the keyboard, nothing clipped or scrolling sideways, the document never scrolled`, rbad.length === 0, rbad.join("; "));
      await pp.context().close();
    }
    const ria = await rec.open(A.localUrl, { context: PHONE });
    await joinAs(ria, "Ria");
    for (const t of ["Which providers charge the least?", "Compare saved-card adoption", "What do returning customers pick?"]) await ria.evaluate(x => window.Core.request("Q1", "ask", x), t);
    await ria.evaluate(() => document.querySelector(".vf-asktop").click());
    await until(ria, () => document.querySelectorAll(".vf-drawer:not([hidden]) .vf-apreqs > li").length === 3);
    await settle(ria);
    await ria.locator("#vf-ap-ta").tap();
    await keyboard(ria, true);
    const reqs = await ria.evaluate(() => {
      const sc = document.querySelector(".vf-apscroll"), head = [...sc.querySelectorAll(".vf-pop-sub")].find(h => h.textContent === "Your requests");
      sc.scrollTop += head.getBoundingClientRect().top - sc.getBoundingClientRect().top;
      const vv = visualViewport, S = sc.getBoundingClientRect(), h = head.getBoundingClientRect(), li = sc.querySelector(".vf-apreqs > li").getBoundingClientRect();
      return { scrolled: sc.scrollTop > 0, shown: h.top >= S.top - 0.5 && li.bottom <= Math.min(S.bottom, vv.offsetTop + vv.height) + 0.5, sideways: sc.scrollWidth > sc.clientWidth + 1 || sc.scrollLeft !== 0 };
    });
    ok("390x844, keyboard up: the Ask Claude sheet scrolls down to \"Your requests\" and its first request, never sideways", reqs.scrolled && reqs.shown && !reqs.sideways, JSON.stringify(reqs));
    await ria.context().close();

    // ---------- spec PR 9: the Inbox page on a phone, with an iOS keyboard up while the host edits a request ----------
    // Expected: the same reveal rule as the sheets above (the row's question line, the field's first 3 lines and Save
    // seen above the keyboard), at the 260 px floor, KB and 430 px, and the document never scrolls.
    const ivy = await rec.open(A.localUrl, { context: PHONE });
    await joinAs(ivy, "Ivy");
    await ivy.evaluate(() => window.Core.request("Q1", "ask", "Ivy asks the host to run this one"));
    const io = await rec.open(A.ownerUrl, { context: PHONE });
    await until(io, () => window.Core.snapshot()?.me?.role === "owner" && (window.Core.state.requests || []).some(r => r.text.startsWith("Ivy asks")), null, 10000);
    await io.locator(".vf-tab", { hasText: "More" }).tap();
    await io.locator(".vf-msitem", { hasText: "Inbox" }).tap();
    await until(io, () => !document.querySelector(".vf-inboxpage").hidden);
    await io.locator(".vf-ixtabs [data-k=needs]").tap();
    const IVY = ".vf-ibneeds .vf-revlist > li:has(.vf-qref)", ibad = [];
    const ivyRow = io.locator(".vf-ibneeds .vf-revlist > li", { hasText: "Ivy asks" });
    await ivyRow.locator("button", { hasText: /^Edit$/ }).tap();
    await settle(io);
    for (const kb of [260, KB, 430]) {
      await io.evaluate(() => document.activeElement?.blur());
      if (!(await ivyRow.locator("textarea").tap({ timeout: 5000 }).then(() => true, () => false))) { ibad.push(`keyboard ${kb}: the field could not be tapped`); break; }
      await keyboard(io, true, { kb });
      const seen = await fieldSeen(io, `${IVY} .vf-qref`, `${IVY} textarea`, `${IVY} .vf-acts button:not([hidden])`);
      seen.push(...(await docScrolls(io)));
      if (seen.length) ibad.push(`keyboard ${kb}: ${[...new Set(seen)].join(", ")}`);
      await keyboard(io, false);
    }
    ok("390x844, the Inbox page's request Edit, keyboard 260 to 430 px: the row's question, the field's first 3 lines and Save are seen above the keyboard, the document never scrolled", ibad.length === 0, ibad.join("; "));
    await io.context().close(); await ivy.context().close();

    // ---------- dogfood: nothing scrolls the page sideways at 320 to 430 px, keyboard or not ----------
    for (const w of [320, 375, 390, 430]) {
      const p = await rec.open(A.localUrl, { context: { ...PHONE, viewport: { width: w, height: 844 } } });
      await joinAs(p, `Wid ${w}`);
      await settle(p);
      const side = async where => { const e = await p.evaluate(() => [document.scrollingElement.scrollWidth, document.scrollingElement.clientWidth]); return [...(e[0] > e[1] ? [`page ${e[0]} > ${e[1]}`] : []), ...(where ? await sideScroll(p, where) : [])]; };
      const bad = (await side()).map(x => `default: ${x}`);
      await p.evaluate(() => document.querySelector(".vf-fab").click());
      await until(p, () => !document.querySelector(".vf-chat").hidden); await settle(p);
      await p.locator(".vf-minput").tap(); await keyboard(p, true);
      bad.push(...(await side(".vf-chat")).map(x => `chat: ${x}`));
      await keyboard(p, false); await p.keyboard.press("Escape");
      await p.evaluate(() => document.querySelector(".vf-asktop").click());
      await until(p, () => !!document.querySelector(".vf-drawer:not([hidden])")); await settle(p);
      await p.locator("#vf-ap-ta").tap(); await keyboard(p, true);
      bad.push(...(await side(".vf-drawer")).map(x => `Ask Claude, keyboard up: ${x}`));
      // .vf-apscroll hides its sideways overflow, so `sideScroll` passes it over: compare its widths outright, with
      // "Run it on my own Claude" on too, since that panel is the widest thing in it.
      const clip = async when => { const e = await p.evaluate(() => { const a = document.querySelector(".vf-apscroll"); return [a.scrollWidth, a.clientWidth]; }); if (e[0] > e[1] + TOL) bad.push(`Ask Claude${when}: .vf-apscroll content ${e[0]} clipped in ${e[1]}`); };
      if (w === 320) {
        await clip(", keyboard up");
        await keyboard(p, false); await p.click(".vf-apself");
        await until(p, () => !document.querySelector(".vf-apconnect").hidden); await settle(p);
        await clip(" with \"Run it on my own Claude\" on");
      }
      ok(`${w}x844: no horizontal overflow in the default view, with the chat open, or in Ask Claude with the keyboard up${w === 320 ? ", nothing in Ask Claude clipped sideways" : ""}`, bad.length === 0, bad.join("; "));
      await p.context().close();
    }

    // ---------- dogfood: a pinch-zoomed phone still knows its keyboard is up, and a zoom alone is no keyboard ----------
    // Expected: --kb is the keyboard's screen height the helper models (KB, 1 px for rounding); a zoom with no keyboard
    // leaves --kb 0 and no data-kb.
    const zp = await rec.open(A.localUrl, { context: PHONE });
    await joinAs(zp, "Zoe");
    await zp.evaluate(() => document.querySelector(".vf-fab").click());
    await until(zp, () => !document.querySelector(".vf-chat").hidden); await settle(zp);
    await zp.locator(".vf-minput").tap();
    const kbNow = () => zp.evaluate(() => ({ kb: parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--kb")), flagged: "kb" in document.documentElement.dataset }));
    const zoomed = [];
    for (const scale of [1.5, 2, 3]) {
      await keyboard(zp, true, { scale });
      const up = await kbNow();
      if (!up.flagged || Math.abs(up.kb - KB) > 1) zoomed.push(`zoom ${scale}, keyboard ${KB}: --kb ${up.kb}, data-kb ${up.flagged ? "set" : "unset"}`);
      await keyboard(zp, false);
      await keyboard(zp, true, { scale, kb: 0 });
      const none = await kbNow();
      if (none.flagged || none.kb !== 0) zoomed.push(`zoom ${scale}, no keyboard: --kb ${none.kb}, data-kb ${none.flagged ? "set" : "unset"}`);
      await keyboard(zp, false);
    }
    ok(`390x844 pinch-zoomed to 1.5, 2 and 3: a ${KB} px keyboard reads as ${KB} px, the zoom alone as none`, zoomed.length === 0, zoomed.join("; "));
    await zp.context().close();

    // ---------- the composer directly under the question ----------
    for (const [page, label] of [[pia, "390x844"], [await (async () => { const d = await rec.open(A.localUrl, { context: { viewport: { width: 1440, height: 900 } } }); await joinAs(d, "Dee"); return d; })(), "1440x900"]]) {
      const w = await show(page, "focus-choice");
      const g = w ? { missing: w } : await composerGap(page);
      ok(`${label}, Focus on a choice question: the composer starts within ${COMPOSER_GAP} px below the question block`,
        !g.missing && g.gap >= -TOL && g.gap <= COMPOSER_GAP, g.missing || `question block ends at ${g.qb.toFixed(0)}, composer starts at ${g.ct.toFixed(0)}: gap ${g.gap.toFixed(0)} px${g.between.length ? `, in it: ${g.between.join(", ")}` : ""}`);
    }

    // ---------- triage 3: a guest's first view says why they are here and where to start ----------
    for (const [label, context] of [["390x844", PHONE], ["1440x900", { viewport: { width: 1440, height: 900 } }]]) {
      const g = await rec.open(A.localUrl, { context });
      await joinAs(g, `First ${label}`);
      const card = await until(g, () => !document.querySelector(".vf-orient")?.hidden);
      const facts = await g.evaluate(() => {
        const c = document.querySelector(".vf-orient"), b = c.querySelector(".vf-orient-start"), r = b.getBoundingClientRect();
        return { text: c.textContent, start: b.textContent, inView: r.top >= 0 && r.bottom <= innerHeight && r.left >= 0 && r.right <= innerWidth };
      });
      ok(`${label}: a new guest's first view shows the goal, the host's ask and "Start here: question 1" without scrolling`,
        card && facts.text.includes(`Goal: ${GOAL}`) && /asks you to answer 3 questions/.test(facts.text) && facts.start === "Start here: question 1" && facts.inView, JSON.stringify(facts));
      await g.locator(".vf-orient-start").click();
      ok(`${label}: Start here focuses question 1's first option, the primary control`, await until(g, t => document.querySelector(".vf-qtext")?.textContent === t
        && document.activeElement?.matches(".vf-optchoose") && /Card/.test(document.activeElement.closest(".vf-opt").textContent), CHOICE));
      await g.context().close();
    }

    // ---------- C40: person colors, distinct by default, AA in both themes ----------
    // Ten colors: the first ten people to join get ten different ones (more than ten must share).
    const colors = (await snap(pia)).people.slice().sort((a, b) => a.joinedAt - b.joinedAt).slice(0, 10).map(p => p.color);
    ok("C40: the first ten people to join got ten distinct default colors", colors.length === 10 && new Set(colors).size === 10, colors.join(","));
    for (const scheme of ["dark", "light"]) {
      await pia.emulateMedia({ colorScheme: scheme });
      await until(pia, t => document.getElementById("app").dataset.theme === t, scheme);
      const bad = await pia.evaluate(() => {
        const rgb = s => { const c = document.createElement("canvas").getContext("2d"); c.fillStyle = s; c.fillRect(0, 0, 1, 1); return [...c.getImageData(0, 0, 1, 1).data].slice(0, 3); };
        const lum = s => { const [r, g, b] = rgb(s).map(v => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
        const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
        const app = document.getElementById("app"), bg = getComputedStyle(app).getPropertyValue("--bg"), out = [];
        for (let i = 1; i <= 10; i++) {
          const probe = document.createElement("span"); probe.className = "core-avatar"; probe.style.setProperty("--av", `var(--pc-c${i})`); app.append(probe);
          const cs = getComputedStyle(probe), text = ratio(cs.color, cs.backgroundColor), page = ratio(cs.backgroundColor, bg);
          probe.remove();
          if (text < 4.5 || page < 3) out.push(`c${i}: initials ${text.toFixed(2)}:1, against the page ${page.toFixed(2)}:1`);
        }
        return out;
      });
      ok(`C40, ${scheme}: all ten person colors meet WCAG 2.2 AA (initials 4.5:1, against the page 3:1)`, bad.length === 0, bad.join("; "));
    }

    // ---------- triage 18: editing my answer on a phone is a full-height sheet ----------
    await pia.emulateMedia({ colorScheme: "dark" });
    await show(pia, "focus-text");
    await pia.evaluate(() => window.Core.answerCiting("Q2", "Below the total.", []));
    await until(pia, () => document.querySelector("#vf-answer").value === "Below the total.");
    await pia.locator("#vf-answer").tap();
    const sheet = await until(pia, () => !!document.querySelector(".vf-composer-sheet"));
    const geo = await pia.evaluate(() => {
      const c = document.querySelector(".vf-composer-sheet").getBoundingClientRect(), t = document.querySelector("#vf-answer").getBoundingClientRect();
      const save = document.querySelector(".vf-sheetsave").getBoundingClientRect(), cancel = [...document.querySelectorAll(".vf-sheethead button")].find(b => b.textContent === "Cancel").getBoundingClientRect();
      const vv = visualViewport;
      return { full: c.top <= vv.offsetTop + 1 && c.bottom >= vv.offsetTop + vv.height - 1 && c.left <= 0 && c.right >= innerWidth - 1,
        onTop: save.bottom <= t.top && cancel.bottom <= t.top, tall: t.height >= vv.height / 2, value: document.querySelector("#vf-answer").value };
    });
    ok("390x844: editing a saved answer opens a full-height sheet, text pre-filled, Cancel and Save above the field",
      sheet && geo.full && geo.onTop && geo.tall && geo.value === "Below the total.", JSON.stringify(geo));
    await pia.keyboard.insertText(" Always.");
    await pia.locator(".vf-sheethead button", { hasText: "Cancel" }).tap();
    ok("390x844: Cancel closes the sheet and keeps the saved answer", await until(pia, () => !document.querySelector(".vf-composer-sheet") && document.querySelector("#vf-answer").value === "Below the total."));

    // ---------- dogfood: a sideways swipe moves between questions and never works the control it starts on ----------
    const swi = await rec.open(A.localUrl, { context: PHONE });
    await joinAs(swi, "Swi");
    const cdp = await swi.context().newCDPSession(swi);
    const center = sel => swi.evaluate(s => { const r = document.querySelector(s).getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2]; }, sel);
    const swipe = async (sel, dx) => {
      const [x, y] = await center(sel);
      await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x, y }] });
      for (let i = 1; i <= 6; i++) { await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: x + dx * i / 6, y }] }); await swi.waitForTimeout(16); }
      await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
      await swi.waitForTimeout(400);
    };
    // What I picked, voted and wrote on Q1 and Q2, and what has focus.
    const mine = () => swi.evaluate(() => JSON.stringify(["Q1", "Q2"].map(id => window.Core.answersFor(id).map(a => [a.id, a.pick || "", (a.votes || []).includes(window.Core.me.cid), a.cid === window.Core.me.cid ? a.text : ""]))));
    const focused = () => swi.evaluate(() => { const a = document.activeElement; return a?.matches?.("input, textarea, select") ? `${a.tagName.toLowerCase()}#${a.id}` : ""; });
    const qNow = () => swi.evaluate(() => document.querySelector(".vf-qtext")?.textContent);
    const swiped = [];
    await show(swi, "focus-choice");
    let was = await mine();
    await swipe(".vf-opt .vf-optchoose", -160);
    if (await mine() !== was || await focused()) swiped.push(`from an option: ${await focused() || "the pick changed"}`);
    if (await qNow() !== TEXT) swiped.push(`from an option it stayed on "${await qNow()}"`);
    await until(swi, () => !!document.querySelector(".vf-vote"), null, 3000);
    was = await mine();
    await swipe(".vf-vote", 160);
    if (await mine() !== was || await focused()) swiped.push(`from a vote button: ${await focused() || "the vote changed"}`);
    if (await qNow() !== CHOICE) swiped.push(`from a vote button it stayed on "${await qNow()}"`);
    await show(swi, "focus-text");
    was = await mine();
    await swipe("#vf-answer", -160);
    if (await mine() !== was || await focused() || await swi.evaluate(() => !!document.querySelector(".vf-composer-sheet"))) swiped.push(`from the answer field: ${await focused() || "the field opened or changed"}`);
    ok("390x844: a sideways swipe that starts on an option, a vote button or the answer field moves between questions without picking, voting or focusing the field", swiped.length === 0, swiped.join("; "));
    const tapped = [];
    await show(swi, "focus-choice");
    await swi.locator(".vf-opt .vf-optchoose").first().tap();
    if (!(await until(swi, () => !!window.Core.answersFor("Q1").find(a => a.cid === window.Core.me.cid && a.pick), null, 3000))) tapped.push("tapping an option did not pick it");
    await show(swi, "focus-text");
    await until(swi, () => !!document.querySelector(".vf-vote"), null, 3000);
    await swi.locator(".vf-vote").first().tap();
    if (!(await until(swi, () => window.Core.answersFor("Q2").some(a => (a.votes || []).includes(window.Core.me.cid)), null, 3000))) tapped.push("tapping a vote button did not vote");
    await swi.locator("#vf-answer").tap();
    if (await focused() !== "textarea#vf-answer") tapped.push(`tapping the answer field focused ${await focused() || "nothing"}`);
    ok("390x844: a tap still picks an option, votes, and focuses the answer field", tapped.length === 0, tapped.join("; "));
    await swi.context().close();

    // ---------- question numbers inside the list markers ----------
    // Expected values: Q1 shows 1 and Q12 shows 12 (the id, not the position, which is 3); a one-line row keeps its
    // pre-change height, 44 px (52 px on a phone), the .vf-q min-block-size; text contrast 4.5:1 is WCAG 1.4.3 AA.
    const N = await s.start("qnum");
    s.apply(N.dir, [{ op: "set-title", title: "Numbers" }, { op: "open-round", questions: [
      q("Q1", "Card or cash?", { kind: "text" }), q("Q2", "Which header?", { kind: "text" }), q("Q12", "Anything else?", { kind: "text" })] }]);
    const nb = N.localUrl.replace(/\/$/, ""), ntok = new URL(N.ownerUrl).hash.replace(/^#owner=/, "");
    const npost = (route, body, h) => fetch(nb + route, { method: "POST", headers: { "Content-Type": "application/json", ...h }, body: JSON.stringify(body) }).then(r => r.json());
    const ng = await npost("/api/join", { name: "Num", device: "computer" }, {});
    await npost("/api/answer", { qid: "Q2", text: "The slim one.", view: "focus" }, { "X-Session-Secret": ng.secret });
    for (const [label, context] of [["1440x900", { viewport: { width: 1440, height: 900 } }], ["390x844", PHONE]]) {
      const own = await rec.open(N.ownerUrl, { context });
      await until(own, () => window.Core.snapshot()?.me?.role === "owner");
      if (label === "1440x900") {
        await npost("/api/lock", { qid: "Q2", card: `p:${ng.pid}` }, { "X-Owner-Token": ntok });
        await own.evaluate(() => window.Core.answerCiting("Q1", "Card.", []));
      }
      if (label === "390x844") await own.locator(".vf-tab", { hasText: "Questions" }).click();
      await until(own, () => document.querySelectorAll(".vf-round-cur .vf-q").length === 3 && document.querySelector(".vf-q[data-stat=locked]") && document.querySelector(".vf-q[data-stat=done]"));
      const rows = await own.evaluate(() => [...document.querySelectorAll(".vf-round-cur .vf-q")].map(b => ({ mark: b.querySelector(".vf-qstat")?.textContent.trim() ?? null, h: +b.getBoundingClientRect().height.toFixed(2) })));
      ok(`${label}: the list markers show the id numbers 1, 2 and 12, not positions`, rows.map(r => r.mark).join(",") === "1,2,12", JSON.stringify(rows));
      const gst = await rec.open(N.localUrl, { context });
      await joinAs(gst, `Num ${label}`);
      if (label === "390x844") await gst.locator(".vf-tab", { hasText: "Questions" }).click();
      await until(gst, () => document.querySelectorAll(".vf-round-cur .vf-q").length === 3);
      const gm = await gst.evaluate(() => [...document.querySelectorAll(".vf-round-cur .vf-q .vf-qstat")].filter(m => m.getClientRects().length).map(m => m.textContent.trim()).join(","));
      ok(`${label}: a guest's simple view shows the same marker numbers`, gm === "1,2,12", gm);
      await gst.context().close();
      const want = label === "390x844" ? 52 : 44;
      ok(`${label}: one-line list rows keep their ${want} px height with a number in the marker`, rows.every(r => Math.abs(r.h - want) <= 0.5), JSON.stringify(rows));
      const aria = await own.locator(".vf-round-cur .vf-q").nth(2).ariaSnapshot();
      ok(`${label}: Q12's row is announced as Question 12, the number once`, /Question 12: Anything else\?/.test(aria) && (aria.match(/\b12\b/g) || []).length === 1, aria);
      if (label === "1440x900") {
        const bad = [];
        for (const scheme of ["dark", "light"]) {
          await own.emulateMedia({ colorScheme: scheme });
          await until(own, t => document.getElementById("app").dataset.theme === t, scheme);
          // the theme switch starts color transitions; measure the settled colors
          await own.evaluate(() => Promise.all(document.getAnimations().filter(a => a.effect?.getTiming().iterations !== Infinity).map(a => a.finished.catch(() => null))));
          bad.push(...await own.evaluate(scheme => {
            const cx = document.createElement("canvas").getContext("2d", { willReadFrequently: true });
            const paint = colors => { cx.clearRect(0, 0, 1, 1); for (const c of colors) { cx.fillStyle = c; cx.fillRect(0, 0, 1, 1); } return [...cx.getImageData(0, 0, 1, 1).data].slice(0, 3); };
            const lum = rgb => { const [r, g, b] = rgb.map(v => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
            const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
            const app = document.getElementById("app"), was = app.dataset.accent, out = [];
            for (const accent of ["teal", "indigo", "violet", "amber"]) {
              app.dataset.accent = accent;
              for (const b of document.querySelectorAll(".vf-round-cur .vf-q")) {
                const m = b.querySelector(".vf-qstat"), layers = [];
                for (let e = m; e; e = e.parentElement) layers.unshift(getComputedStyle(e).backgroundColor);
                const bg = paint(["#fff", ...layers]), fg = paint([...layers, getComputedStyle(m).color]), r = ratio(fg, bg);
                if (r < 4.5) out.push(`${scheme} ${accent} ${b.dataset.stat || "open"}: ${r.toFixed(2)}:1`);
              }
            }
            if (was) app.dataset.accent = was; else delete app.dataset.accent;
            return out;
          }, scheme));
        }
        ok("1440x900: marker numbers meet 4.5:1 in dark and light, every accent, open, answered and locked", bad.length === 0, bad.join("; "));
      }
      await own.context().close();
    }

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
