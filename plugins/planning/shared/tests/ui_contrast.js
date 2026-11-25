#!/usr/bin/env node
"use strict";
const { loadPlaywright, suite, recorder, until, settled, joinAs } = require("./browser_harness");

const q = (id, text, format, purpose = "decide") => ({ id, text, alternatives: [], dependsOn: [], purpose, format });
const choice = labels => ({ kind: "choice", options: labels.map((label, i) => ({ id: `opt-${i + 1}`, label })) });
const MAX_LIST = 8, SETTLE_MS = 10000, MODES = ["dark", "light"];

function tokenMatrix(modes) {
  const cx = document.createElement("canvas").getContext("2d", { willReadFrequently: true });
  const rgb = c => { cx.globalAlpha = 1; cx.fillStyle = "#fff"; cx.fillRect(0, 0, 1, 1); cx.fillStyle = "#000"; cx.fillStyle = c; cx.fillRect(0, 0, 1, 1); return [...cx.getImageData(0, 0, 1, 1).data].slice(0, 3); };
  const lum = c => { const [r, g, b] = rgb(c).map(v => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
  const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
  const app = document.getElementById("app"), was = app.dataset.theme, out = [], bgs = {};
  const tok = n => getComputedStyle(app).getPropertyValue(n).trim();
  const hb = document.querySelector(".hover-probe"), hover = { out: [], hovered: 0, min: null };
  for (const theme of modes) {
    app.dataset.theme = theme;
    const tag = theme, need = (what, r, n) => { if (r + 0.005 < n) out.push(`${tag}: ${what} ${r.toFixed(2)}:1 < ${n}`); };
    bgs[theme] = rgb(tok("--bg")).join(",");
    for (const s of ["--bg", "--sunk", "--pane", "--raise"]) need(`--accent-text on ${s}`, ratio(tok("--accent-text"), tok(s)), 4.5);
    need("--on-accent on --accent", ratio(tok("--on-accent"), tok("--accent")), 4.5);
    if (hb?.isConnected && hb.matches(":hover")) {
      const cs = getComputedStyle(hb), r = ratio(cs.color, cs.backgroundColor);
      hover.hovered++;
      for (const c of [cs.color, cs.backgroundColor]) { cx.fillStyle = "#000"; cx.fillStyle = c; if (cx.fillStyle === "#000000") hover.out.push(`${tag}: the canvas could not read ${c}`); }
      if (!hover.min || r < hover.min.r) hover.min = { tag, r: +r.toFixed(2) };
      if (rgb(cs.backgroundColor).join() === rgb(tok("--accent")).join()) hover.out.push(`${tag}: hover fill equals --accent`);
      if (r + 0.005 < 4.5) hover.out.push(`${tag}: ${r.toFixed(2)}:1 < 4.5`);
    }
    for (let i = 1; i <= 10; i++) {
      const probe = document.createElement("span"); probe.className = "core-avatar"; probe.style.setProperty("--av", `var(--pc-c${i})`); app.append(probe);
      const cs = getComputedStyle(probe);
      need(`person color c${i} initials`, ratio(cs.color, cs.backgroundColor), 4.5);
      need(`person color c${i} against the page`, ratio(cs.backgroundColor, tok("--bg")), 3);
      probe.remove();
    }
  }
  if (was === undefined) delete app.dataset.theme; else app.dataset.theme = was;
  return { out, bgs, hover };
}

function scan() {
  const cv = document.createElement("canvas"); cv.width = cv.height = 1;
  const cx = cv.getContext("2d", { willReadFrequently: true });
  const paint = layers => {
    cx.globalAlpha = 1; cx.fillStyle = "#fff"; cx.fillRect(0, 0, 1, 1);
    for (const [c, a = 1] of layers) { cx.globalAlpha = a; cx.fillStyle = "#000"; cx.fillStyle = c; cx.fillRect(0, 0, 1, 1); }
    return [...cx.getImageData(0, 0, 1, 1).data].slice(0, 3);
  };
  const opaque = c => { cx.globalAlpha = 1; cx.clearRect(0, 0, 1, 1); cx.fillStyle = "rgba(0,0,0,0)"; cx.fillStyle = c; cx.fillRect(0, 0, 1, 1); return cx.getImageData(0, 0, 1, 1).data[3] === 255; };
  const lum = ([r, g, b]) => { const f = v => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }; return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b); };
  const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((m, n) => n - m); return (x + 0.05) / (y + 0.05); };
  const under = el => {
    const layers = [];
    for (let e = el; e && e.nodeType === 1; e = e.parentElement) {
      const cs = getComputedStyle(e);
      if (cs.backgroundImage !== "none") return null;
      const c = cs.backgroundColor;
      if (c && c !== "rgba(0, 0, 0, 0)" && c !== "transparent") { layers.unshift([c]); if (opaque(c)) return layers; }
    }
    return layers;
  };
  const alphaOf = el => { let a = 1; for (let e = el; e && e.nodeType === 1; e = e.parentElement) a *= +getComputedStyle(e).opacity; return a; };
  const app = document.getElementById("app");
  const shown = el => {
    if (!el.isConnected || el.closest("[hidden], [inert]")) return false;
    const cs = getComputedStyle(el), r = el.getBoundingClientRect();
    return cs.display !== "none" && cs.visibility === "visible" && r.width > 1 && r.height > 1 && alphaOf(el) > 0;
  };
  const inactive = el => !!el.closest(":disabled, [aria-disabled='true']");
  const name = el => `${el.tagName.toLowerCase()}.${[...el.classList].join(".")} "${(el.textContent || el.placeholder || "").trim().slice(0, 30)}"`;
  const out = [];
  let measured = 0;
  const judge = (el, fgCss, need, what) => {
    const bgL = under(el); if (!bgL) return;
    const bg = paint(bgL), fg = paint([...bgL, [fgCss, alphaOf(el)]]), r = ratio(fg, bg);
    measured++;
    if (r + 0.005 < need) out.push({ what: `${what} ${name(el)}`, ratio: +r.toFixed(2), need, fg, bg });
  };
  for (const el of app.querySelectorAll("*")) {
    if (el.closest("svg") || !shown(el) || inactive(el)) continue;
    const cs = getComputedStyle(el);
    if ([...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim())) {
      const px = parseFloat(cs.fontSize), large = px >= 24 || (px >= 18.66 && +cs.fontWeight >= 700);
      judge(el, cs.color, large ? 3 : 4.5, "text");
    }
    if (el.matches("input:not([type=checkbox]):not([type=radio]), textarea")) {
      if (el.placeholder && !el.value) judge(el, getComputedStyle(el, "::placeholder").color, 4.5, "placeholder");
      if (parseFloat(cs.borderTopWidth) >= 1 && el.parentElement) {
        const bgL = under(el.parentElement);
        if (bgL) { measured++; const r = ratio(paint([...bgL, [cs.borderTopColor, alphaOf(el)]]), paint(bgL)); if (r + 0.005 < 3) out.push({ what: `field boundary ${name(el)}`, ratio: +r.toFixed(2), need: 3 }); }
      }
    }
    if (el.matches("button") && el.querySelector("svg") && !el.textContent.trim() && el.getAttribute("aria-hidden") !== "true") judge(el, cs.color, 3, "icon");
  }
  return { out, measured };
}

function proposeEdge() {
  const cv = document.createElement("canvas"); cv.width = cv.height = 1;
  const cx = cv.getContext("2d", { willReadFrequently: true });
  const px = cs => { cx.globalAlpha = 1; cx.fillStyle = "#fff"; cx.fillRect(0, 0, 1, 1); for (const c of cs) { cx.fillStyle = "#000"; cx.fillStyle = c; cx.fillRect(0, 0, 1, 1); } return [...cx.getImageData(0, 0, 1, 1).data].slice(0, 3); };
  const lum = ([r, g, b]) => { const f = v => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }; return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b); };
  const b = [...document.querySelectorAll(".vf-propose")].find(x => x.offsetParent);
  if (!b) return null;
  const bgs = [];
  for (let e = b.parentElement; e; e = e.parentElement) { const c = getComputedStyle(e).backgroundColor; if (c !== "rgba(0, 0, 0, 0)") bgs.unshift(c); }
  const around = px(bgs), edge = px([...bgs, getComputedStyle(b).borderTopColor]);
  const [x, y] = [lum(edge), lum(around)].sort((m, n) => n - m);
  return { ratio: +((x + 0.05) / (y + 0.05)).toFixed(2), border: getComputedStyle(b).borderTopColor };
}

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_contrast.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_contrast"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("contrast");
    s.apply(A.dir, [{ op: "set-title", title: "Contrast checks" }, { op: "set-goal", goal: "Settle the checkout layout" }, { op: "open-round", questions: [
      q("Q1", "Where should the order summary sit?", { kind: "text" }), q("Q2", "Which carrier should we use?", choice(["Post", "Courier"])),
    ] }]);
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const ann = await rec.open(A.localUrl);
    await joinAs(ann, "Ann");
    await ann.evaluate(() => window.Core.answerCiting("Q1", "On the right, beside the cart.", []));
    await ann.evaluate(() => window.Core.chat("Hello, I am here for the checkout questions"));
    await ann.waitForTimeout(1100);
    await ann.evaluate(() => window.Core.idea("Should guests see shipping costs before the cart?"));
    await until(owner, () => (window.Core.snapshot().cards?.Q1 || []).length > 0 && (window.Core.state.chat || []).length > 0);
    await until(owner, () => Object.values(window.Core.state.people || {}).some(p => p.name === "Ann"));
    await owner.evaluate(() => { const m = window.Core.state.chat[0]; window.Core.chatReact(m.id, "👍", true); return window.Core.chat("@Ann welcome, start with the order summary", m.id); });
    await until(owner, () => (window.Core.state.chat || []).length > 1);
    const ownerName = await owner.evaluate(() => window.Core.snapshot().me.name);
    await ann.evaluate(n => window.Core.chat(`@${n} the summary goes on the right`), ownerName);
    await until(owner, () => !!document.querySelector(".vf-bubble .vf-mention-me") || (window.Core.state.chat || []).length > 2);

    const probe = async (fg, bg) => {
      await owner.evaluate(([f, b]) => { const d = document.createElement("span"); d.className = "probe"; d.textContent = "Probe text"; Object.assign(d.style, { color: f, background: b, fontSize: "14px", position: "fixed", top: "0", left: "0" }); document.getElementById("app").append(d); }, [fg, bg]);
      const r = await owner.evaluate(scan);
      await owner.evaluate(() => document.querySelector(".probe").remove());
      return r.out.filter(x => x.what.includes("Probe text"));
    };
    const self = { black: await probe("#000", "#fff"), gray: await probe("#777", "#fff"), pass: await probe("#595959", "#fff") };
    ok("self-check: #777 on white measures 4.48:1 (WebAIM) and fails 4.5:1", self.gray.length === 1 && Math.abs(self.gray[0].ratio - 4.48) < 0.01, JSON.stringify(self.gray));
    ok("self-check: black on white and #595959 on white pass", self.black.length === 0 && self.pass.length === 0, JSON.stringify(self));

    await owner.evaluate(() => { const b = document.createElement("button"); b.className = "vf-btn vf-btn-primary hover-probe"; b.textContent = "Send";
      Object.assign(b.style, { position: "fixed", top: "50%", left: "50%", zIndex: "2147483647", transition: "none" }); document.getElementById("app").append(b); });
    await owner.hover(".hover-probe");
    const m = await owner.evaluate(tokenMatrix, MODES);
    await owner.evaluate(() => document.querySelector(".hover-probe").remove());
    await owner.mouse.move(0, 0);
    ok(`dark and light: accent text 4.5:1 on each surface, text on the accent 4.5:1, person colors AA`, m.out.length === 0, m.out.slice(0, MAX_LIST).join("; ") + (m.out.length > MAX_LIST ? ` and ${m.out.length - MAX_LIST} more` : ""));
    const h = m.hover;
    ok(`dark and light: a hovered primary button's label reaches 4.5:1 on its hover fill (lowest ${h.min?.r}:1, ${h.min?.tag})`,
      h.hovered === MODES.length && h.out.length === 0, `hovered in ${h.hovered} of ${MODES.length}; ` + h.out.join("; "));
    ok("dark and light each paint their own page background", new Set(Object.values(m.bgs)).size === MODES.length, JSON.stringify(m.bgs));

    const go = async (p, text) => { await p.locator(".vf-q", { hasText: text }).first().click(); return until(p, t => document.querySelector(".vf-qtext")?.textContent === t, text); };
    const closeAll = async p => { for (let i = 0; i < 3; i++) await p.keyboard.press("Escape"); };
    const phone = await rec.open(A.localUrl, { context: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true } });
    await joinAs(phone, "Bo");
    const STATES = [
      ["owner, a written question with an answer", owner, async () => { await closeAll(owner); await go(owner, "Where should the order summary sit?"); }],
      ["owner, a choice question", owner, async () => { await closeAll(owner); await go(owner, "Which carrier should we use?"); }],
      ["owner, chat open", owner, async () => { await closeAll(owner); await owner.click(".vf-fab"); await until(owner, () => !document.querySelector(".vf-chat").hidden); }],
      ["owner, the Host view", owner, async () => { await closeAll(owner); if (await owner.evaluate(() => !document.querySelector(".vf-chat").hidden)) await owner.click(".vf-chat-head .vf-icon-btn"); await owner.locator(".vf-bar .vf-seg-btn", { hasText: "Host" }).click(); }],
      ["owner, the Inbox", owner, async () => { await closeAll(owner); await owner.locator(".vf-bar .vf-seg-btn", { hasText: "Focus" }).click(); await owner.click(".vf-bell"); }],
      ["owner, Session settings", owner, async () => { await closeAll(owner); await owner.click(".vf-gear"); await until(owner, () => !document.querySelector(".vf-settings").hidden); }],
      ["owner, the Propose form", owner, async () => { await closeAll(owner); await owner.click(".vf-propose"); await until(owner, () => !document.querySelector(".vf-proposepop").hidden); }],
      ["guest phone, a choice question", phone, async () => { await until(phone, () => !!document.querySelector(".vf-qtext")); }],
      ["guest phone, chat open", phone, async () => { await phone.click(".vf-fab"); await until(phone, () => !document.querySelector(".vf-chat").hidden); }],
    ];
    for (const [label, page, open] of STATES) {
      await open().catch(e => ok(`${label}: opens`, false, String(e).slice(0, 120)));
      for (const theme of MODES) {
        await page.emulateMedia({ colorScheme: theme, reducedMotion: "reduce" });
        const still = await until(page, t => document.getElementById("app").dataset.theme === t, theme) && await settled(page, { timeout: SETTLE_MS });
        const { out, measured } = await page.evaluate(scan);
        ok(`${label}, ${theme}: every text run, placeholder, field edge and icon reaches its WCAG AA ratio (${measured} measured)`, still && measured > 20 && out.length === 0,
          (still ? "" : `not settled in ${theme} within ${SETTLE_MS} ms `) + JSON.stringify(out.slice(0, MAX_LIST)) + (out.length > MAX_LIST ? ` and ${out.length - MAX_LIST} more` : ""));
      }
    }
    await closeAll(owner);
    for (const theme of MODES) {
      await owner.emulateMedia({ colorScheme: theme, reducedMotion: "reduce" });
      const still = await until(owner, t => document.getElementById("app").dataset.theme === t, theme) && await settled(owner, { timeout: SETTLE_MS });
      const e = await owner.evaluate(proposeEdge);
      ok(`${theme}: the Propose button's boundary reaches 3:1 against the rail`, still && !!e && e.ratio >= 3, (still ? "" : `not settled in ${theme} within ${SETTLE_MS} ms `) + JSON.stringify(e));
    }
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite runs to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally {
    await browser.close();
  }
  return s.finish();
}
main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
