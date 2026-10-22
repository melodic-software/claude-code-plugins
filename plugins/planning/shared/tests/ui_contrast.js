#!/usr/bin/env node
// Computed contrast on the shared page, against `share.sh ensure-running` with the fake cloudflared: on the main page
// states (the focus view on a choice and a written question with answers, chat, the Host view, the Inbox, the Propose
// form, and a guest's phone), in dark and light, every visible text run reaches WCAG 2.2 AA (1.4.3: 4.5:1, or 3:1 for
// large text, 24 px or 18.66 px bold), placeholders included; text-field boundaries and icon-only buttons' icons reach
// 3:1 against what they sit on (1.4.11); and the Propose button's boundary reaches 3:1 too, since it is the one way in
// to Propose (research/propose-question-discoverability). Colors are read from computed styles and composited through
// a canvas, so they are the sRGB the browser paints (oklch may be gamut-mapped); an inactive control (disabled or
// aria-disabled) is exempt, as WCAG exempts it, and a run over a background image is skipped as unmeasurable.
//   node plugins/planning/shared/tests/ui_contrast.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from WCAG 2.2 (https://www.w3.org/TR/WCAG22/#contrast-minimum and #non-text-contrast) and the
// relative-luminance formula it defines; the self-checks use WebAIM's published ratios (#777 on white is 4.48:1).
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const q = (id, text, format, purpose = "decide") => ({ id, text, alternatives: [], dependsOn: [], purpose, format });
const choice = labels => ({ kind: "choice", options: labels.map((label, i) => ({ id: `opt-${i + 1}`, label })) });
const MAX_LIST = 8, SETTLE_MS = 10000;

/** In the page: every contrast failure under #app as [{what, ratio, need, fg, bg}], plus how many runs were measured. */
function scan() {
  const cv = document.createElement("canvas"); cv.width = cv.height = 1;
  const cx = cv.getContext("2d", { willReadFrequently: true });
  /** Paint layers (CSS colors, each with an optional alpha multiplier) over white, bottom first; the pixel is sRGB. */
  const paint = layers => {
    cx.globalAlpha = 1; cx.fillStyle = "#fff"; cx.fillRect(0, 0, 1, 1);
    for (const [c, a = 1] of layers) { cx.globalAlpha = a; cx.fillStyle = "#000"; cx.fillStyle = c; cx.fillRect(0, 0, 1, 1); }
    return [...cx.getImageData(0, 0, 1, 1).data].slice(0, 3);
  };
  const opaque = c => { cx.globalAlpha = 1; cx.clearRect(0, 0, 1, 1); cx.fillStyle = "rgba(0,0,0,0)"; cx.fillStyle = c; cx.fillRect(0, 0, 1, 1); return cx.getImageData(0, 0, 1, 1).data[3] === 255; };
  const lum = ([r, g, b]) => { const f = v => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }; return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b); };
  const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((m, n) => n - m); return (x + 0.05) / (y + 0.05); };
  /** The background layers under `el`, bottom first, or null where a background image makes it unmeasurable. */
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
    // 1.4.3: an element's own text
    if ([...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim())) {
      const px = parseFloat(cs.fontSize), large = px >= 24 || (px >= 18.66 && +cs.fontWeight >= 700);
      judge(el, cs.color, large ? 3 : 4.5, "text");
    }
    if (el.matches("input:not([type=checkbox]):not([type=radio]), textarea")) {
      if (el.placeholder && !el.value) judge(el, getComputedStyle(el, "::placeholder").color, 4.5, "placeholder");
      // 1.4.11: the field's boundary against what is around it
      if (parseFloat(cs.borderTopWidth) >= 1 && el.parentElement) {
        const bgL = under(el.parentElement);
        if (bgL) { measured++; const r = ratio(paint([...bgL, [cs.borderTopColor, alphaOf(el)]]), paint(bgL)); if (r + 0.005 < 3) out.push({ what: `field boundary ${name(el)}`, ratio: +r.toFixed(2), need: 3 }); }
      }
    }
    // 1.4.11: an icon-only button's icon (stroked in currentColor)
    if (el.matches("button") && el.querySelector("svg") && !el.textContent.trim() && el.getAttribute("aria-hidden") !== "true") judge(el, cs.color, 3, "icon");
  }
  return { out, measured };
}

/** In the page: true once no animation or transition runs and the colors and opacities under #app read the same a frame
 *  apart, false if that has not happened within `ms`. A transition's computed value is its start value until a frame
 *  ticks it, so a scan taken sooner can measure the previous theme's color on the new theme's background. */
async function settle(ms) {
  const end = performance.now() + ms, frame = () => new Promise(r => requestAnimationFrame(() => r()));
  const read = () => [...document.querySelectorAll("#app, #app *")].map(e => { const c = getComputedStyle(e); return `${c.color} ${c.backgroundColor} ${c.borderTopColor} ${c.opacity}`; }).join("|");
  while (performance.now() < end) {
    const running = document.getAnimations().filter(a => a.playState === "running");
    if (running.length) { await Promise.race([Promise.all(running.map(a => a.finished.catch(() => {}))), new Promise(r => setTimeout(r, Math.max(0, end - performance.now())))]); continue; }
    const before = read();
    await frame(); await frame();
    if (!document.getAnimations().some(a => a.playState === "running") && read() === before) return true;
  }
  return false;
}

/** In the page: the boundary of the Propose button against the rail, as {ratio}. */
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

    // ---------- the calculator itself ----------
    const probe = async (fg, bg) => {
      await owner.evaluate(([f, b]) => { const d = document.createElement("span"); d.className = "probe"; d.textContent = "Probe text"; Object.assign(d.style, { color: f, background: b, fontSize: "14px", position: "fixed", top: "0", left: "0" }); document.getElementById("app").append(d); }, [fg, bg]);
      const r = await owner.evaluate(scan);
      await owner.evaluate(() => document.querySelector(".probe").remove());
      return r.out.filter(x => x.what.includes("Probe text"));
    };
    const self = { black: await probe("#000", "#fff"), grey: await probe("#777", "#fff"), pass: await probe("#595959", "#fff") };
    ok("self-check: #777 on white measures 4.48:1 (WebAIM) and fails 4.5:1", self.grey.length === 1 && Math.abs(self.grey[0].ratio - 4.48) < 0.01, JSON.stringify(self.grey));
    ok("self-check: black on white and #595959 on white pass", self.black.length === 0 && self.pass.length === 0, JSON.stringify(self));

    // ---------- the page states, dark and light ----------
    const go = async (p, text) => { await p.locator(".vf-q", { hasText: text }).first().click(); return until(p, t => document.querySelector(".vf-qtext")?.textContent === t, text); };
    const closeAll = async p => { for (let i = 0; i < 3; i++) await p.keyboard.press("Escape"); };
    const phone = await rec.open(A.localUrl, { context: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true } });
    await joinAs(phone, "Bo");
    const STATES = [
      ["owner, a written question with an answer", owner, async () => { await closeAll(owner); await go(owner, "Where should the order summary sit?"); }],
      ["owner, a choice question", owner, async () => { await closeAll(owner); await go(owner, "Which carrier should we use?"); }],
      ["owner, chat open", owner, async () => { await closeAll(owner); await owner.click(".vf-fab"); await until(owner, () => !document.querySelector(".vf-chat").hidden); }],
      ["owner, the Host view", owner, async () => { await closeAll(owner); if (await owner.evaluate(() => !document.querySelector(".vf-chat").hidden)) await owner.click(".vf-fab"); await owner.locator(".vf-bar .vf-seg-btn", { hasText: "Host" }).click(); }],
      ["owner, the Inbox", owner, async () => { await closeAll(owner); await owner.locator(".vf-bar .vf-seg-btn", { hasText: "Focus" }).click(); await owner.click(".vf-bell"); }],
      ["owner, the Propose form", owner, async () => { await closeAll(owner); await owner.click(".vf-propose"); await until(owner, () => !document.querySelector(".vf-proposepop").hidden); }],
      ["guest phone, a choice question", phone, async () => { await until(phone, () => !!document.querySelector(".vf-qtext")); }],
    ];
    for (const [label, page, open] of STATES) {
      await open().catch(e => ok(`${label}: opens`, false, String(e).slice(0, 120)));
      for (const theme of ["dark", "light"]) {
        await page.emulateMedia({ colorScheme: theme, reducedMotion: "reduce" });
        const settled = await until(page, t => document.getElementById("app").dataset.theme === t, theme) && await page.evaluate(settle, SETTLE_MS);
        const { out, measured } = await page.evaluate(scan);
        ok(`${label}, ${theme}: every text run, placeholder, field edge and icon reaches its WCAG AA ratio (${measured} measured)`, settled && measured > 20 && out.length === 0,
          (settled ? "" : `not settled in ${theme} within ${SETTLE_MS} ms `) + JSON.stringify(out.slice(0, MAX_LIST)) + (out.length > MAX_LIST ? ` and ${out.length - MAX_LIST} more` : ""));
      }
    }
    // ---------- the Propose button is a bordered button whose edge reaches 3:1 ----------
    await closeAll(owner);
    for (const theme of ["dark", "light"]) {
      await owner.emulateMedia({ colorScheme: theme, reducedMotion: "reduce" });
      const settled = await until(owner, t => document.getElementById("app").dataset.theme === t, theme) && await owner.evaluate(settle, SETTLE_MS);
      const e = await owner.evaluate(proposeEdge);
      ok(`${theme}: the Propose button's boundary reaches 3:1 against the rail`, settled && !!e && e.ratio >= 3, JSON.stringify(e));
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
