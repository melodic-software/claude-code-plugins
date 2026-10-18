#!/usr/bin/env node
// Gather reaction chips in a real browser, against `share.sh ensure-running` with the fake cloudflared: at rest a
// chip has no fill (the grey the owner saw was the browser's own button background, so the computed background
// must be transparent, not the UA default) and a --line-input outline; hovered it takes --raise; chosen, the
// --accent-soft fill inside a full --accent border with the count in --accent-text; focused, a 2px --accent outline
// with an offset. aria-pressed carries the choice and the label never changes with it, in dark and light. One person
// holds ❤️ and 💡 with 👍 or 👎, and 👎 takes 👍's place (triage row 45).
//   node plugins/planning/shared/tests/ui_reactions.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from triage row 41 and research/presence-indicator/RESEARCH-reactions.md (the token each
// state takes, read back through a probe element styled with that token), and the labels Core.REACTIONS names in
// the brief's set (Agree, Disagree, Love it, Sparks an idea), never from the chip itself.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const gather = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "gather", format: { kind: "text" } });
const LABELS = { thumbs: "Agree", down: "Disagree", heart: "Love it", idea: "Sparks an idea" };

/** In the page: one chip's computed look next to what each token computes to on a probe in the same place. */
function look([r, theme]) {
  if (theme) document.querySelector(".app").dataset.theme = theme;
  const card = [...document.querySelectorAll(".vf-alist .vf-card")].find(c => /Losing the saved card/.test(c.textContent));
  const b = card.querySelector(`.vf-react[data-r="${r}"]`), cs = getComputedStyle(b);
  const probe = document.createElement("span");
  b.parentElement.append(probe);
  const token = v => { probe.style.color = `var(${v})`; return getComputedStyle(probe).color; };
  const t = { transparent: "rgba(0, 0, 0, 0)", lineInput: token("--line-input"), raise: token("--raise"), accent: token("--accent"), accentSoft: token("--accent-soft"), accentText: token("--accent-text") };
  probe.remove();
  return { theme: document.querySelector(".app").dataset.theme, pressed: b.getAttribute("aria-pressed"), label: b.getAttribute("aria-label"), bg: cs.backgroundColor, border: cs.borderTopColor, borderW: cs.borderTopWidth,
    count: getComputedStyle(b.lastChild).color, outline: `${cs.outlineStyle} ${cs.outlineWidth} ${cs.outlineColor} ${cs.outlineOffset}`, t };
}

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_reactions.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_reactions"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("reactions");
    s.apply(A.dir, [{ op: "open-round", questions: [gather("Q1", "What worries you about the new checkout?")] }]);
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    await owner.locator(".vf-q", { hasText: "What worries you" }).first().click();
    await owner.fill("#vf-answer", "Losing the saved card.");
    await owner.press("#vf-answer", "Control+Enter");
    const bo = await rec.open(A.localUrl);
    await joinAs(bo, "Bo");
    await bo.locator(".vf-q", { hasText: "What worries you" }).first().click();
    ok("Bo sees the owner's answer with its chips", await until(bo, () => [...document.querySelectorAll(".vf-alist .vf-card")].some(c => /Losing the saved card/.test(c.textContent) && c.querySelector(".vf-react"))));
    const chip = r => bo.locator(".vf-alist .vf-card", { hasText: "Losing the saved card" }).locator(`.vf-react[data-r="${r}"]`);

    for (const t of ["dark", "light"]) {
      const rest = await bo.evaluate(look, ["heart", t]);
      ok(`${t}: a chip at rest has a transparent background, not the browser's button fill`, rest.bg === rest.t.transparent && rest.pressed === "false", JSON.stringify(rest));
      ok(`${t}:   and a 1px --line-input outline`, rest.border === rest.t.lineInput && rest.borderW === "1px", JSON.stringify(rest));
    }
    await bo.mouse.move(0, 0);
    await chip("heart").hover();
    const hover = await bo.evaluate(look, ["heart", "light"]);
    ok("light: hovered, it takes --raise", hover.bg === hover.t.raise, JSON.stringify(hover));
    await bo.mouse.move(0, 0);

    await chip("heart").click();
    ok("clicking a chip presses it", await until(bo, () => [...document.querySelectorAll('.vf-react[data-r="heart"]')].some(b => b.getAttribute("aria-pressed") === "true")));
    await bo.waitForTimeout(300);
    for (const t of ["dark", "light"]) {
      const on = await bo.evaluate(look, ["heart", t]);
      ok(`${t}: chosen, the --accent-soft fill inside a full --accent border, the count in --accent-text`, on.bg === on.t.accentSoft && on.border === on.t.accent && on.count === on.t.accentText, JSON.stringify(on));
      ok(`${t}:   and its label names the reaction and count only`, on.label === `${LABELS.heart}: 1`, on.label);
    }
    await chip("heart").focus();
    await bo.keyboard.press("Space"); // a keyboard press: focus-visible, and the chip lets go
    ok("Space lets the chip go", await until(bo, () => [...document.querySelectorAll('.vf-react[data-r="heart"]')].every(b => b.getAttribute("aria-pressed") === "false")));
    await bo.mouse.move(0, 0); // the click left the pointer on the chip
    await bo.waitForTimeout(300);
    const off =await bo.evaluate(look, ["heart", ""]);
    ok("let go, the label is the same sentence with the count", off.label === `${LABELS.heart}: 0` && off.bg === off.t.transparent, JSON.stringify(off));
    ok("focused from the keyboard, a 2px --accent outline with an offset", off.outline === `solid 2px ${off.t.accent} 2px`, off.outline);

    // ---------- combined reactions (triage row 45): ❤️ and 💡 with 👍 or 👎, never 👍 and 👎 together ----------
    const pressed = () => bo.evaluate(() => {
      const card = [...document.querySelectorAll(".vf-alist .vf-card")].find(c => /Losing the saved card/.test(c.textContent));
      return [...card.querySelectorAll(".vf-react")].filter(b => b.getAttribute("aria-pressed") === "true").map(b => b.dataset.r).join(" ");
    });
    const mine = () => owner.evaluate(p => window.Core.snapshot()?.cards?.Q1?.find(c => c.ref === "p:host")?.reactions, null);
    for (const r of ["heart", "idea", "thumbs"]) { await chip(r).click(); await bo.waitForTimeout(150); }
    ok("one person holds 👍 ❤️ 💡 on one answer at once", await until(bo, () => {
      const card = [...document.querySelectorAll(".vf-alist .vf-card")].find(c => /Losing the saved card/.test(c.textContent));
      return [...card.querySelectorAll(".vf-react")].filter(b => b.getAttribute("aria-pressed") === "true").map(b => b.dataset.r).join(" ") === "thumbs heart idea";
    }), await pressed());
    ok("  and the server counts each of them", await until(owner, () => JSON.stringify(window.Core.snapshot()?.cards?.Q1?.find(c => c.ref === "p:host")?.reactions) === JSON.stringify({ thumbs: 1, down: 0, heart: 1, idea: 1 }), null, 10000),
      JSON.stringify(await mine()));
    await chip("down").click();
    ok("👎 takes 👍's place and leaves ❤️ and 💡 pressed", await until(bo, () => {
      const card = [...document.querySelectorAll(".vf-alist .vf-card")].find(c => /Losing the saved card/.test(c.textContent));
      return [...card.querySelectorAll(".vf-react")].filter(b => b.getAttribute("aria-pressed") === "true").map(b => b.dataset.r).join(" ") === "down heart idea";
    }), await pressed());
    ok("  on the server too", await until(owner, () => JSON.stringify(window.Core.snapshot()?.cards?.Q1?.find(c => c.ref === "p:host")?.reactions) === JSON.stringify({ thumbs: 0, down: 1, heart: 1, idea: 1 }), null, 10000),
      JSON.stringify(await mine()));
    ok("  and Bo's own record is the list of the three", await until(bo, () => JSON.stringify(window.Core.snapshot()?.me?.reactions?.Q1?.["p:host"]) === JSON.stringify(["down", "heart", "idea"]), null, 10000));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
    ok("no request was answered 429 (slow down)", rec.too.length === 0, rec.too.slice(0, 5).join(", "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
