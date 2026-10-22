#!/usr/bin/env node
// Keyboard use in real browsers, against `share.sh ensure-running` with the fake cloudflared. For each modal surface
// (the join dialog, session settings, the share panel, the shortcuts dialog opened with "?", notifications, the chat,
// the picture viewer, and on a 390x844 phone the More sheet, the notifications sheet and the chat): 30 presses of Tab
// and 30 of Shift+Tab keep focus inside it, Escape closes it, and focus goes back to what opened it. Picking an option
// and sending an answer each put a message in the page's polite live region (announce() in app.js). A choice is
// answered by keyboard alone: Tab from the question reaches the first option, Space picks it, Enter picks another.
// The first-visit tour (triage 4) traps focus, ends with Done or Escape, records the `tour` pref and reopens from Help;
// its ring moves by translate only, and the current round step stops pulsing within 5 s (animation-audit I3, I4).
// AC17: a Tab sweep per view (a guest's Focus, Compare and Tree, the chat, the picture viewer, the Host view, settings,
// share, notifications, shortcuts, a confirm dialog; on a phone the Questions and Answer tabs, the chat, More and the
// Host view) reaches every control, each with a focus ring, on screen and not covered (WCAG 2.4.7, 2.4.11).
//   node plugins/planning/shared/tests/ui_keyboard.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the keyboard requirements of the polish plan (30 presses each way, Escape closes, focus
// returns to the opener), the WAI-ARIA Authoring Practices dialog pattern (focus stays inside a modal dialog and returns
// to the invoking element, or where it was when a shortcut opened it), the server contract (session.py pick: one pick
// per person) and core.js's join dialog rule (it stays open until the join succeeds), never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, settled, snap, joinAs } = require("./browser_harness");

const PRESSES = 30;
const DESK = { viewport: { width: 1440, height: 900 } };
const PHONE = { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 };
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==", "base64");
const q = (id, text, format) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format });

const describe = () => { const a = document.activeElement; return a ? `${a.tagName.toLowerCase()}.${[...a.classList].join(".")} "${(a.getAttribute("aria-label") || a.textContent || "").trim().replace(/\s+/g, " ").slice(0, 30)}"` : "nothing"; };
/** In the page: true once the tour ring has stopped moving and is drawn round `sel`, its box the target's grown by 4 px a
 *  side and kept 4 px inside the page (placeTour), within 2 px. Read in one go, so no re-layout falls between the two. */
const ringOnTarget = sel => {
  const g = document.querySelector(".vf-tour-ring"), el = document.querySelector(sel);
  if (!el || g.getAnimations().length) return false;
  const ring = g.getBoundingClientRect(), R = document.querySelector(".app").getBoundingClientRect(), r = el.getBoundingClientRect();
  const near = (a, b) => Math.abs(a - b) <= 2;
  return near(ring.left, Math.max(R.left + 4, r.left - 4)) && near(ring.top, Math.max(R.top + 4, r.top - 4))
    && near(ring.right, Math.min(R.right - 4, r.right + 4)) && near(ring.bottom, Math.min(R.bottom - 4, r.bottom + 4));
};
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

/** Tag every interactive control in the view (the open modal dialog, the given surface, or the page minus inert parts)
 *  and record how each looks unfocused; returns their descriptions by tag. */
function tagControls(scopeSel) {
  const modal = document.querySelector("dialog:modal");
  const root = (scopeSel && document.querySelector(scopeSel)) || modal || document.body;
  const shown = el => el.getClientRects().length > 0 && el.checkVisibility({ visibilityProperty: true }) && !el.closest("[inert]");
  const look = el => { const c = getComputedStyle(el); return [c.outlineStyle, c.outlineWidth, c.outlineColor, c.boxShadow, c.borderColor, c.backgroundColor].join("|"); };
  const all = [...root.querySelectorAll("a[href], button, input:not([type=hidden]), select, textarea, summary, [tabindex], [contenteditable=true]")]
    .filter(el => !el.disabled && el.tabIndex >= 0 && shown(el));
  const radios = new Set();
  const out = {};
  // Record the unfocused look: the control a surface focused on opening is blurred while it is read, then refocused.
  const had = document.activeElement;
  had?.blur?.();
  document.querySelectorAll("[data-kb]").forEach(e => e.removeAttribute("data-kb"));
  all.forEach((el, i) => {
    // A native radio group is one Tab stop: only its first radio stands for the group.
    if (el.type === "radio" && el.name) { if (radios.has(el.name)) return; radios.add(el.name); el.closest("form, body").querySelectorAll(`input[type=radio][name="${el.name}"]`).forEach(r => r.dataset.kb = String(i)); }
    el.dataset.kb = String(i);
    el._kbLook = [el, el.parentElement, el.parentElement?.parentElement].map(e => e && look(e));
    out[i] = `${el.tagName.toLowerCase()}.${[...el.classList].join(".")} "${(el.getAttribute("aria-label") || el.textContent || el.placeholder || "").trim().replace(/\s+/g, " ").slice(0, 30)}"`;
  });
  // A native control taken out of the Tab order (tabindex -1) counts as reachable only inside a roving group, where
  // a sibling holds the group's one Tab stop and arrows move between them; it is checked after the sweep.
  document.querySelectorAll("[data-kbr]").forEach(e => e.removeAttribute("data-kbr"));
  [...root.querySelectorAll("a[href], button, input:not([type=hidden]), select, textarea, summary")]
    .filter(el => !el.disabled && el.tabIndex < 0 && shown(el)).forEach(el => { el.dataset.kbr = `${el.tagName.toLowerCase()}.${[...el.classList].join(".")} "${(el.getAttribute("aria-label") || el.textContent || "").trim().slice(0, 30)}"`; });
  if (had && had !== document.body) had.focus({ preventScroll: true });
  return out;
}

/** Out-of-order controls (tagControls) outside any composite widget (radiogroup, toolbar, menu, listbox, tablist,
 *  grid, group), or inside one where Tab reached no member. */
function strandedRoving(reached) {
  const got = new Set(reached);
  return [...document.querySelectorAll("[data-kbr]")].filter(el => {
    const group = el.closest("[role=radiogroup], [role=toolbar], [role=menu], [role=menubar], [role=listbox], [role=tablist], [role=grid], [role=group]");
    return !group || ![...group.querySelectorAll("[data-kb]")].some(e => got.has(e.dataset.kb));
  }).map(el => el.dataset.kbr);
}

/** The focused control: its tag, whether a ring shows (an outline on it, or a changed look on it or a near parent),
 *  whether that outline is cut off on every side by a clipping parent, and whether it is on screen and not covered. */
function focusedNow() {
  const a = document.activeElement, id = a?.dataset?.kb;
  if (!a || id === undefined || !a._kbLook) return { id: id ?? null };
  const c = getComputedStyle(a), r = a.getBoundingClientRect();
  const ow = c.outlineStyle !== "none" ? parseFloat(c.outlineWidth) || 0 : 0;
  const look = e => { const s = getComputedStyle(e); return [s.outlineStyle, s.outlineWidth, s.outlineColor, s.boxShadow, s.borderColor, s.backgroundColor].join("|"); };
  const changed = [a, a.parentElement, a.parentElement?.parentElement].some((e, i) => e && a._kbLook[i] !== look(e));
  let ring = ow >= 1 || changed, clipped = false;
  if (ow >= 1 && !changed) {
    // The outline's outer box, cut by every parent that clips: how many of its four sides are still drawn?
    const o = (parseFloat(c.outlineOffset) || 0) + ow;
    let box = { l: r.left - o, t: r.top - o, rt: r.right + o, b: r.bottom + o };
    const ring0 = { ...box };
    for (let p = a.parentElement; p && p !== document.documentElement; p = p.parentElement) {
      const pc = getComputedStyle(p);
      if (pc.overflowX === "visible" && pc.overflowY === "visible") continue;
      const pr = p.getBoundingClientRect();
      box = { l: Math.max(box.l, pr.left), t: Math.max(box.t, pr.top), rt: Math.min(box.rt, pr.right), b: Math.min(box.b, pr.bottom) };
    }
    const sides = [box.l <= ring0.l + 1, box.t <= ring0.t + 1, box.rt >= ring0.rt - 1, box.b >= ring0.b - 1].filter(Boolean).length;
    clipped = sides < 2;
    ring = !clipped;
  }
  // On screen and not covered: one of five points in it reaches it (or its label) from the top.
  const pts = [[0.5, 0.5], [0.2, 0.2], [0.8, 0.2], [0.2, 0.8], [0.8, 0.8]].map(([fx, fy]) => [r.left + r.width * fx, r.top + r.height * fy]);
  const seen = pts.some(([x, y]) => { if (x < 0 || y < 0 || x >= innerWidth || y >= innerHeight) return false; const h = document.elementFromPoint(x, y); return !!h && (h === a || a.contains(h) || h.contains(a) || h.closest("label")?.control === a); });
  const top = document.elementFromPoint(pts[0][0], pts[0][1]), cover = top ? `${top.tagName.toLowerCase()}.${[...top.classList].join(".")}` : "off screen";
  return { id, ring, clipped, seen, cover: seen ? "" : `${cover} at ${Math.round(r.left)},${Math.round(r.top)}`};
}

/** Tab through a view from its start until every tagged control has had focus or the presses run out. Returns the
 *  controls never reached, the ones reached without a visible ring, and the ones focused off screen or covered. */
async function sweep(page, scopeSel) {
  const names = await page.evaluate(tagControls, scopeSel || null);
  const ids = Object.keys(names), reached = new Map();
  await page.evaluate(scopeSel => {
    const root = (scopeSel && document.querySelector(scopeSel)) || document.querySelector("dialog:modal");
    if (root) root.querySelector("[data-kb]")?.focus(); else { document.activeElement?.blur?.(); }
  }, scopeSel || null);
  // Only focus that Tab moved counts: the first control a surface focuses on opening comes round again in its trap.
  for (let i = 0; i < ids.length * 2 + 20 && reached.size < ids.length; i++) {
    await page.keyboard.press("Tab");
    const f = await page.evaluate(focusedNow);
    if (f.id !== null && !reached.has(f.id)) reached.set(f.id, f);
  }
  const all = [...reached.values()];
  return {
    total: ids.length,
    missed: [...ids.filter(i => !reached.has(i)).map(i => names[i]), ...(await page.evaluate(strandedRoving, [...reached.keys()])).map(n => `${n} (tabindex -1)`)],
    noRing: all.filter(f => !f.ring).map(f => names[f.id] + (f.clipped ? " (outline clipped)" : "")),
    hidden: all.filter(f => !f.seen).map(f => `${names[f.id]} (under ${f.cover})`),
  };
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
    await surface(owner, "Inbox page", ".vf-inboxpage", { opener: owner.locator(".vf-bell") });
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
    await surface(phoneOwner, "phone Inbox page (from More)", ".vf-inboxpage", {
      before: async () => { await more.focus(); await more.evaluate(el => el.setAttribute("data-kb-opener", "")); await phoneOwner.keyboard.press("Enter"); await until(phoneOwner, shownSel, ".vf-moresheet", 3000); },
      opener: phoneOwner.locator(".vf-msitem", { hasText: "Inbox" }), expectBack: ".vf-tab[data-kb-opener]",
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

    // ---------- AC17: a Tab sweep per view, desktop and phone ----------
    // Every interactive control in the view takes focus from Tab, shows a ring when it has it (WCAG 2.4.7), and is on
    // screen and not covered when focused (WCAG 2.4.11). Views: a guest's Focus on a choice and on a text question with
    // answers, Compare, Tree, the chat, the picture viewer; the owner's Host view, settings, share, notifications,
    // shortcuts and a confirm dialog; on a phone the Questions and Answer tabs, the chat, the More sheet and Host view.
    await owner.locator(".vf-q", { hasText: "Where should the order summary sit?" }).first().click();
    await owner.locator("#vf-answer").fill("Next to the pay button.");
    await owner.press("#vf-answer", "Control+Enter");
    await until(gus, () => (window.Core.snapshot().cards.Q2 || []).some(c => c.ref === "p:host"));
    async function swept(page, name, { scope, open, close } = {}) {
      try { if (open) await open(); } catch (e) { ok(`Tab sweep, ${name}: the view opens`, false, String(e.message).split("\n")[0]); return; }
      // Swept once the view holds still: each control's resting look is the baseline its focus ring is told from.
      const still = await settled(page, { rects: true });
      const r = await sweep(page, scope);
      ok(`Tab sweep, ${name}: all ${r.total} controls take focus from Tab`, still && r.total > 0 && r.missed.length === 0,
        `${still ? "" : "not settled; "}${r.missed.length} missed: ${r.missed.slice(0, 6).join(", ")}`);
      ok(`Tab sweep, ${name}: each shows a focus ring`, r.noRing.length === 0, r.noRing.slice(0, 6).join(", "));
      ok(`Tab sweep, ${name}: each is on screen and not covered when focused`, r.hidden.length === 0, r.hidden.slice(0, 6).join(", "));
      if (close) await close();
    }
    const esc = page => () => page.keyboard.press("Escape");
    const viewSeg = (page, label) => async () => {
      const b = page.locator(".vf-bar .vf-seg-btn", { hasText: label }), more = page.locator(".vf-viewopts");
      if (!(await b.isVisible()) && (await more.isVisible())) await more.click();
      await b.click({ timeout: 5000 });
    };
    const openQ = (page, text) => async () => { await page.locator(".vf-q", { hasText: text }).first().click({ timeout: 5000 }); await until(page, t => document.querySelector(".vf-qtext")?.textContent === t, text); };
    await swept(gus, "guest Focus, a choice question (desktop)", { open: openQ(gus, "Which default payment method?") });
    await swept(gus, "guest Focus, a text question with answers (desktop)", { open: openQ(gus, "Where should the order summary sit?") });
    await swept(gus, "guest Compare (desktop)", { open: viewSeg(gus, "Compare") });
    await swept(gus, "guest Tree (desktop)", { open: viewSeg(gus, "Tree") });
    await viewSeg(gus, "Focus")();
    await swept(gus, "chat (desktop)", { scope: "section.vf-chat", open: () => gus.locator(".vf-fab").click(), close: esc(gus) });
    await swept(gus, "picture viewer (desktop)", { scope: ".vf-lb", open: async () => { await openQ(gus, "Did you mean this button?")(); await gus.locator(".vf-confirm-fig .vf-imgbtn").click(); }, close: esc(gus) });
    await swept(owner, "owner Host view (desktop)", { open: viewSeg(owner, "Host") });
    await swept(owner, "remove-person confirm dialog (desktop)", { open: () => owner.locator(".vf-hpeople .vf-btn-danger:visible", { hasText: "Remove" }).first().click(), close: esc(owner) });
    await viewSeg(owner, "Focus")();
    await swept(owner, "settings panel (desktop)", { scope: ".vf-settings", open: () => owner.locator(".vf-gear").click(), close: esc(owner) });
    await swept(owner, "share panel (desktop)", { scope: ".vf-share", open: () => owner.locator(".vf-sharebtn").click(), close: esc(owner) });
    await swept(owner, "Inbox page (desktop)", { scope: ".vf-inboxpage", open: () => owner.locator(".vf-bell").click(), close: esc(owner) });
    await swept(owner, "keyboard shortcuts (desktop)", { scope: ".vf-keys", open: () => owner.locator(".vf-keysbtn").click(), close: esc(owner) });
    const tab = (page, label) => () => page.locator(".vf-tab", { hasText: label }).click({ timeout: 5000 });
    await swept(pia, "guest Questions tab (phone)", { open: tab(pia, "Questions") });
    await swept(pia, "guest Answer tab, a choice question (phone)", { open: async () => { await tab(pia, "Questions")(); await pia.locator(".vf-q", { hasText: "Which shipping speed by default?" }).first().click(); await tab(pia, "Answer")(); } });
    await swept(pia, "chat sheet (phone)", { scope: "section.vf-chat", open: () => pia.locator(".vf-fab").click(), close: esc(pia) });
    await swept(phoneOwner, "More sheet (phone)", { scope: ".vf-moresheet", open: tab(phoneOwner, "More"), close: esc(phoneOwner) });
    await swept(phoneOwner, "owner Host view (phone)", { open: async () => { await tab(phoneOwner, "More")(); await phoneOwner.locator(".vf-msitem", { hasText: "Host view" }).click(); } });
    // One person, two tabs on two questions: the phone tab on the guest's question and hidden, the desktop tab on another
    // and focused after it. The host shows on the desktop tab's question only (the tab focused or shown last), so the
    // guest's page never says "The host is on this question" while it is sampled every 250 ms, whichever tab beats last.
    const piaQ = await pia.evaluate(() => document.querySelector(".vf-qtext")?.textContent);
    const qidOf = (page, text) => page.evaluate(t => window.Core.state.questions.find(x => x.text === t)?.id, text);
    const phoneQ = await qidOf(phoneOwner, piaQ), deskQ = await qidOf(owner, "Did you mean this button?"); // Gus is there already, so the tour below has its own question
    await phoneOwner.evaluate(id => window.Core.setFocus(id), phoneQ);
    await phoneOwner.evaluate(() => { Object.defineProperty(document, "visibilityState", { configurable: true, get: () => "hidden" }); document.dispatchEvent(new Event("visibilitychange")); });
    await owner.evaluate(id => { window.Core.setFocus(id); window.dispatchEvent(new Event("focus")); }, deskQ);
    const hostQ = () => pia.evaluate(() => window.Core.owner()?.q);
    const settledOnDesk = await until(pia, id => window.Core.owner()?.q === id, deskQ, 10000);
    const samples = [];
    for (let i = 0; i < 24; i++) { samples.push([await hostQ(), await pia.evaluate(() => !document.querySelector(".vf-onit").hidden)]); await pia.waitForTimeout(250); }
    const flips = samples.filter(([q, shown]) => q !== deskQ || shown).length;
    ok("a host with two tabs shows on the question of the tab focused last, never flipping", phoneQ && deskQ && phoneQ !== deskQ && settledOnDesk && flips === 0,
      `phone on ${phoneQ}, desktop on ${deskQ}, settled: ${settledOnDesk}, ${flips} of 24 samples off the desktop's question or showing the host here`);
    // Closed, so the tour below starts with no one else on that question and moves its target only when it means to.
    await phoneOwner.close();

    // ---------- triage 4: the first-visit tour (optional, skippable, re-opened from Help, remembered by the `tour` pref) ----------
    const tia = await rec.open(A.localUrl, { context: DESK });
    await joinAs(tia, "Tia");
    await until(tia, () => !document.querySelector(".vf-orient")?.hidden);
    await tia.click(".vf-orient-tour");
    const card = ".vf-tour-card[role=dialog][aria-modal=true]";
    ok("the tour opens as a modal dialog with focus on Next", await until(tia, c => { const d = document.querySelector(c); return !!d?.offsetParent && document.activeElement?.textContent === "Next"; }, card));
    // animation-audit I3: the ring moves by transform only (catalog "Properties": transform and opacity, no layout
    // transitions), and still lands on the step's target: its box is the target's grown by 4 px a side (paintTour).
    ok("the tour ring transitions translate only, never a layout property", await tia.evaluate(() => getComputedStyle(document.querySelector(".vf-tour-ring")).transitionProperty) === "translate",
      await tia.evaluate(() => getComputedStyle(document.querySelector(".vf-tour-ring")).transitionProperty));
    const alone = await until(tia, () => document.querySelector(".vf-onit").hidden, null, 10000); // no one else on this question
    await tia.click(".vf-tour-row .vf-btn-primary");
    ok("after Next the ring has moved onto the next step's target", await until(tia, ringOnTarget, ".vf-fmt"));
    // The ring follows its target when the page re-lays-out under the open tour: another person arriving on this
    // question shows "is on this question" above the options and pushes them down.
    const fmtTop = () => tia.evaluate(() => document.querySelector(".vf-fmt").getBoundingClientRect().top);
    const top0 = await fmtTop();
    await openQ(gus, await tia.textContent(".vf-qtext"))();
    const pushed = await until(tia, () => !document.querySelector(".vf-onit").hidden);
    ok("  and stays on it when the page moves it", alone && pushed && await fmtTop() > top0 && await until(tia, ringOnTarget, ".vf-fmt"),
      `alone on the question before: ${alone}, "on this question" shown after: ${pushed}`);
    let escaped = 0;
    for (let i = 0; i < PRESSES; i++) { await tia.keyboard.press(i % 2 ? "Shift+Tab" : "Tab"); if (!(await tia.evaluate(c => document.querySelector(c).contains(document.activeElement), card))) escaped++; }
    ok(`${PRESSES} Tab and Shift+Tab presses keep focus inside the tour`, escaped === 0, `${escaped} left it`);
    /** Every step's heading from here to Done, which ends the tour. */
    const walk = async page => {
      const seen = [];
      for (let i = 0; i < 20; i++) {
        seen.push(await page.textContent(".vf-tour-h"));
        const last = (await page.textContent(".vf-tour-row .vf-btn-primary")) === "Done";
        await page.click(".vf-tour-row .vf-btn-primary");
        if (last) break;
      }
      return seen;
    };
    const steps = await walk(tia); // from the second step: the ring check above pressed Next once
    ok("Done ends the tour and the `tour` pref says done (server state)", await until(tia, () => document.querySelector(".vf-tour").hidden && window.Core.snapshot()?.me?.prefs?.tour === "done"), steps.join(" | "));
    // Follow-up 38: a guest's tour adds the Discussion, Ask Claude (and @Claude), and the Inbox; none of the host's steps.
    const GUEST_STEPS = ["Your answer box", "Everyone's answers", "Discussion", "Ask Claude", "Chat with people", "Your Inbox", "Help is here"];
    ok("a guest's tour walks the answer box, others' answers, the Discussion, Ask Claude, the chat, the Inbox and Help", GUEST_STEPS.every(h => steps.includes(h)), steps.join(" | "));
    ok("  and none of the host's steps", !steps.some(h => ["Share the link", "Needs you", "Send the round"].includes(h)), steps.join(" | "));
    ok("once done, the first view stops offering the tour", await until(tia, () => document.querySelector(".vf-orient-tour").hidden));
    await tia.click(".vf-keysbtn");
    await tia.click(".vf-help-tour");
    ok("Help opens the tour again", await until(tia, c => !!document.querySelector(c)?.offsetParent, card));
    await tia.keyboard.press("Escape");
    ok("Escape skips the tour, the pref says skipped, and focus goes back to the Help button", await until(tia, () => document.querySelector(".vf-tour").hidden
      && window.Core.snapshot()?.me?.prefs?.tour === "skipped" && document.activeElement?.classList.contains("vf-keysbtn")));

    // Follow-up 38: the host's tour, from Help: Share, Needs you (Run and Approve) and Send, each on its real control.
    await owner.click(".vf-keysbtn");
    await owner.click(".vf-help-tour");
    await until(owner, c => !!document.querySelector(c)?.offsetParent, card);
    const hostSteps = [];
    for (let i = 0; i < 20; i++) {
      const h = await owner.textContent(".vf-tour-h");
      // What the ring is drawn round once it stops moving: the control each host step names.
      const at = await owner.waitForFunction(() => {
        const g = document.querySelector(".vf-tour-ring");
        if (g.getAnimations().length) return null;
        const ring = g.getBoundingClientRect(), mid = [(ring.left + ring.right) / 2, (ring.top + ring.bottom) / 2];
        return [[".vf-sharebtn", ".vf-bell", ".vf-round-cur .vf-send"].find(sel => { const r = document.querySelector(sel)?.getBoundingClientRect(); return r && r.width && Math.abs((r.left + r.right) / 2 - mid[0]) < 2 && Math.abs((r.top + r.bottom) / 2 - mid[1]) < 2; }) || ""];
      }, null, { timeout: 8000 }).then(v => v.jsonValue()).then(v => v[0], () => "(the ring never stopped)");
      hostSteps.push(`${h}@${at}`);
      const last = (await owner.textContent(".vf-tour-row .vf-btn-primary")) === "Done";
      await owner.click(".vf-tour-row .vf-btn-primary");
      if (last) break;
    }
    ok("the host's tour rings Share, the Inbox for Needs you, and the round's Send", ["Share the link@.vf-sharebtn", "Needs you@.vf-bell", "Send the round@.vf-round-cur .vf-send"].every(x => hostSteps.includes(x)), hostSteps.join(" | "));
    ok("  and skips a guest's Discussion and chat steps", !hostSteps.some(x => /^(Discussion|Chat with people)@/.test(x)), hostSteps.join(" | "));

    // animation-audit I4: once the round is sent, the current step's dot breathes a few times and stops (WCAG 2.2.2:
    // no auto-playing motion past 5 s beside other content).
    await owner.evaluate(() => window.Core.sendRound());
    await until(tia, () => !!document.querySelector('.vf-step[data-state="now"] .vf-step-dot')?.offsetParent);
    const breathe = await tia.evaluate(() => {
      const d = document.querySelector('.vf-step[data-state="now"] .vf-step-dot');
      if (!d) return null;
      const c = getComputedStyle(d);
      return { name: c.animationName, n: c.animationIterationCount, s: parseFloat(c.animationDuration) };
    });
    ok("the current step's dot pulse stops within 5 s", !!breathe && breathe.name === "vf-breathe" && breathe.n !== "infinite" && Number(breathe.n) * breathe.s <= 5, JSON.stringify(breathe));

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
