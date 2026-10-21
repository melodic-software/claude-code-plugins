#!/usr/bin/env node
// Page alignment check: seeds a varied session and an empty one through `share.sh ensure-running` (fake cloudflared,
// spare ports), then opens every view below at each size and theme and checks the page: no mention token (<@pid>) in
// its text, attributes or fields, and the geometry: no page scroll,
// no horizontal overflow, the focus view's blocks on the question's column (column), a phone's previous and next arrows on the question
// position's row (qnav-row), no overlapping text, like rows aligned, icons on their text line (icon-line), the toast's
// place, the phone tab bar, choice and confirm controls above the fold, and icon-only buttons with the icon centered
// on the button within 0.5 px (icon-center).
//   node plugins/planning/shared/tests/align.js
//   ALIGN_VIEWS=chat,focus-q1-short ALIGN_SIZES=390x844,1440x900 node plugins/planning/shared/tests/align.js
// Screenshots of failing states go to a temp folder whose path is printed. Exits 1 on any failure.
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
"use strict";
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const zlib = require("node:zlib");
const { loadPlaywright, suite } = require("./browser_harness");

const SIZES = [[390, 844], [768, 1024], [1024, 768], [1440, 900], [2560, 1440]];
const THEMES = ["dark", "light"];
const MAX_DETAIL = 6;
const list = v => (v || "").split(",").map(x => x.trim()).filter(Boolean);

/** A w x h PNG in two colors, striped, so each picture is its own asset. */
function png(w, h, [r1, g1, b1], [r2, g2, b2]) {
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const o = y * (w * 3 + 1) + 1 + x * 3, c = ((x + y) >> 4) & 1 ? [r1, g1, b1] : [r2, g2, b2];
    raw[o] = c[0]; raw[o + 1] = c[1]; raw[o + 2] = c[2];
  }
  const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
  const crc = b => { let c = 0xffffffff; for (const x of b) c = crcTable[(c ^ x) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([len, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}
const SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 80"><rect x="4" y="4" width="90" height="72" fill="none" stroke="black"/><text x="20" y="45">Cart</text><rect x="120" y="4" width="90" height="72" fill="none" stroke="black"/><text x="130" y="45">Pay</text></svg>';
const q = (id, text, format = { kind: "text" }, extra = {}) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format, ...extra });

/** Seed the varied session over the API: questions in two rounds, people, answers, votes, a lock, chat, mentions,
 *  a proposal, a request and a published result. Attachments have no route yet (core.js uploadOffer), so none. */
async function seed(s, A) {
  const base = A.localUrl.replace(/\/$/, ""), owner = new URL(A.ownerUrl).hash.replace(/^#owner=/, "");
  const last = new Map(); // one write a second per person and route (session.py WRITE_INTERVAL)
  async function post(route, body, who) {
    const key = `${who.id}|${route}`, wait = (last.get(key) || 0) + 1100 - Date.now();
    if (wait > 0) await new Promise(r => setTimeout(r, wait));
    const r = await fetch(base + route, { method: "POST", headers: { "Content-Type": "application/json", ...who.h }, body: JSON.stringify(body) });
    last.set(key, Date.now());
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(`${route} ${JSON.stringify(body).slice(0, 80)} -> ${r.status} ${JSON.stringify(j)}`);
    return j;
  }
  const host = { id: "host", h: { "X-Owner-Token": owner } };
  await post("/api/join", { name: "Kyle" }, host).catch(() => {});
  const join = async name => { const j = await post("/api/join", { name, device: "computer" }, { id: "anon-" + name, h: {} }); return { id: j.pid, pid: j.pid, h: { "X-Session-Secret": j.secret } }; };

  const shot = s.asset(A.dir, "shot.png", png(640, 400, [40, 90, 160], [220, 220, 230]));
  const pics = [[200, 60, 60], [60, 160, 90], [230, 180, 40], [120, 70, 170]].map((c, i) => s.asset(A.dir, `opt${i + 1}.png`, png(320, 200, c, [245, 245, 245])));
  const svg = s.asset(A.dir, "flow.svg", SVG);
  const longWord = "Supercalifragilistic".repeat(15); // 300 characters, no break
  const refs = [
    { kind: "image", asset: shot, rect: { x: 6, y: 8, w: 32, h: 30 }, caption: "The current checkout, with the order summary boxed" },
    { kind: "quote", text: "Most people abandon a checkout that asks them to create an account first.", source: "Support survey, spring", url: "https://example.com/survey" },
    { kind: "link", url: "https://example.com/a/very/long/path/to/the/checkout/design/guidelines/page", title: "Checkout design guidelines" },
    { kind: "diagram", asset: svg, alt: "Checkout flow: cart, then payment.", caption: "Checkout flow" },
    { kind: "link", url: "https://example.com/benchmarks", title: "Benchmarks" },
  ];
  s.apply(A.dir, [{ op: "set-title", title: "Checkout redesign: layout, payment and trust signals for every device" },
    { op: "set-goal", goal: "Agree the checkout layout and the payment methods before the design sprint starts." },
    { op: "open-round", questions: [
      q("Q1", "Where should the order summary sit?", undefined, { references: refs, context: "The summary is in the sidebar today." }),
      q("Q2", "Which pages need the new header?"),
      q("Q3", `Is this word too long: ${longWord}?`),
      q("Q4", "Should guest checkout be the default?"),
      q("Q5", "Which reaction fits the new flow best? 🎉🚀😅👍🏽 🧑‍💻 or 🛒✨"),
      q("Q6", "האם עמוד התשלום צריך לתמוך בעברית? ما هي طريقة الدفع المفضلة لديك؟"),
      q("Q7", "What worries you about the new checkout?", undefined, { purpose: "gather" }),
      q("Q8", "How should the confirmation page read?\n\nToday it repeats the whole order, the address and the delivery estimate, then asks for a review.\n\nSecond paragraph: should it link to the order history, or to the help center, or neither?\n\nThird paragraph: anything else it should say."),
    ] }]);
  const [bea, chen, dana, eli] = [await join("Bea"), await join("Chen"), await join("Dana Okonkwo-Fitzgerald"), await join("Eli")];
  const at = { view: "focus", deviceInfo: { kind: "computer", browser: "chrome", screen: { w: 1440, h: 900 } } };
  const ans = (who, qid, text) => post("/api/answer", { qid, text, ...at }, who);
  await ans(bea, "Q1", "Right column on desktop, collapsed above the pay button on phones.");
  await ans(chen, "Q1", "Keep it in the sidebar, but sticky.");
  await ans(dana, "Q1", "Under the total, with an expand control. @Bea agrees, I think.");
  await ans(bea, "Q2", "Cart, checkout and the confirmation page.");
  await ans(chen, "Q2", `Every page. ${longWord}`);
  await ans(eli, "Q4", "Yes: most of our buyers never come back.");
  await ans(dana, "Q4", "No, nudge people to sign in.");
  await ans(chen, "Q5", "🎉 for the confirmation, 😅 for errors.");
  await ans(bea, "Q6", "כן, וגם ערבית. نعم بالتأكيد.");
  await ans(eli, "Q7", "Losing the saved card.");
  await ans(dana, "Q8", "Link to the order history.\n\nNothing else: short is better.");
  await post("/api/vote", { qid: "Q1", card: "p:" + bea.pid, on: true }, chen);
  await post("/api/vote", { qid: "Q1", card: "p:" + bea.pid, on: true }, eli);
  await post("/api/vote", { qid: "Q4", card: "p:" + eli.pid, on: true }, bea);
  await post("/api/lock", { qid: "Q4", card: "p:" + eli.pid }, host);
  for (const [who, text] of [[bea, "Hi all, starting on Q1."], [chen, "@Bea the sidebar one is mine 🙂"], [dana, "Long message: " + "the summary should never hide the total. ".repeat(6)], [eli, "مرحبا! Hebrew and Arabic both read fine here."], [bea, longWord]]) await post("/api/chat", { text }, who);
  await post("/api/request", { qid: "Q1", kind: "research", text: "How do the five biggest shops place the order summary? @Chen asked too." }, bea);
  await post("/api/request", { qid: "Q2", kind: "ask", text: "Which pages share the header component today?" }, eli);
  const res = s.apply(A.dir, [{ op: "result", qid: "Q1", kind: "research", used: [{ name: "discovery:research", type: "skill" }], why: "Outside comparison.",
    summary: "Four of five big shops keep the summary in a right column on desktop and collapse it on phones.", sources: [{ title: "Patterns", url: "https://example.com/p" }],
    report: "## Findings\n\nFour of five shops use a right column.\n\n" + "Detail line. ".repeat(40) }]).results[0];
  await post("/api/request/act", { id: res.id, action: "publish" }, host).catch(e => console.log(`note: result not published (${e.message})`));
  // Round 1 goes to Claude and comes back; round 2 holds a choice with pictures and a confirm with an image and a box.
  await post("/api/round/send", {}, host);
  s.apply(A.dir, [{ op: "ack-round", round: 1 }, { op: "open-round", questions: [
    q("Q9", "Anything to add before we decide?"),
    q("Q10", "Which payment methods should checkout offer?", { kind: "multi", options: [{ id: "opt-1", label: "Card" }, { id: "opt-2", label: "PayPal" }, { id: "opt-3", label: "Apple Pay" }] }),
    q("Q11", "Which checkout layout should we build?", { kind: "choice", options: [
      { id: "opt-1", label: "One page", image: pics[0] }, { id: "opt-2", label: "Steps with a progress bar along the top", image: pics[1] },
      { id: "opt-3", label: "Accordion", image: pics[2] }, { id: "opt-4", label: "Two columns", image: pics[3] }] }),
    q("Q12", "Did you mean this button?", { kind: "confirm", image: shot, rect: { x: 45, y: 62, w: 22, h: 15 } }),
  ] }]);
  await post("/api/pick", { qid: "Q11", option: "opt-2", comment: "Clear progress helps.", ...at }, bea);
  await post("/api/pick", { qid: "Q11", option: "opt-1", comment: "", ...at }, chen);
  await post("/api/pick", { qid: "Q12", option: "yes", comment: "", ...at }, dana).catch(e => console.log(`note: no confirm pick (${e.message})`));
  await ans(eli, "Q9", "Nothing from me.");
  // proposals after round 1 went out: a proposal in a sent round's digest needs a placement when the next round opens
  await post("/api/propose", { text: "Ask about express checkout buttons (Apple Pay, Google Pay) above the fold." }, chen);
  await post("/api/propose", { text: "Should we test the new layout with five customers first? @Eli could run it." }, dana);
  await post("/api/report", { text: "The Send button does nothing on my phone after I pick a layout.", ctx: { view: "focus", tab: "answer", qid: "Q11", round: 2,
    device: "phone", browser: "safari", viewport: { w: 390, h: 844 }, visualViewport: { w: 390, h: 508, scale: 1 }, errors: ["api slow-down: HTTP 429: Wait a moment"] } }, eli);
}

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: align.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const t0 = Date.now();
  const s = suite("align"), shots = fs.mkdtempSync(path.join(os.tmpdir(), "align-shots-"));
  const sizes = list(process.env.ALIGN_SIZES).map(x => x.split("x").map(Number));
  const CFG = { sizes: sizes.length ? sizes : SIZES, views: list(process.env.ALIGN_VIEWS) };
  const results = [], details = [];
  try {
    const A = await s.start("align"), E = await s.start("empty"), C = await s.start("crowd");
    try { await seed(s, A); s.ok("seed the varied session", true); } catch (e) { s.ok("seed the varied session", false, e.message); throw e; }
    try { await crowd(s, C); s.ok("seed the crowd session", true); } catch (e) { s.ok("seed the crowd session", false, e.message); throw e; }
    const ctx = await browser.newContext({ reducedMotion: "reduce" });
    const page = await ctx.newPage();
    const VIEWS = views(page, { emptyHost: E.ownerUrl, emptyGuest: E.localUrl, crowdHost: C.ownerUrl });
    const unknown = CFG.views.filter(v => !VIEWS[v]);
    if (unknown.length) throw new Error(`ALIGN_VIEWS names no such view: ${unknown.join(", ")}; known: ${Object.keys(VIEWS).join(", ")}`);
    const names = CFG.views.length ? CFG.views : Object.keys(VIEWS);
    const H = helpers(page);
    for (const [w, h] of CFG.sizes) {
      await page.setViewportSize({ width: w, height: h });
      let loaded = false;
      for (const v of names) {
        if (!loaded) { await page.emulateMedia({ colorScheme: THEMES[0], reducedMotion: "reduce" }); await page.goto(A.ownerUrl); await page.reload(); await H.joinIfAsked("Kyle"); loaded = true; }
        let ok;
        for (const [i, theme] of THEMES.entries()) {
          // the toast fades: set it up again for each theme; other views keep their state across a live theme switch
          await page.emulateMedia({ colorScheme: theme, reducedMotion: "reduce" });
          if (i === 0 || v.startsWith("toast")) { await H.reset(); await H.mode("focus"); ok = await VIEWS[v](); }
          if (ok === "skip") break;
          await page.evaluate(t => { window.__expectToast = t; }, v.startsWith("toast"));
          await page.waitForTimeout(i === 0 ? 250 : 120);
          await settled(page);
          const tag = `${v} ${w}x${h} ${theme}`;
          const f = ok === false ? [{ rule: "setup", msg: "could not open this view" }] : await check(page, theme);
          results.push({ v, size: `${w}x${h}`, theme, fails: f.length });
          if (f.length) {
            const file = path.join(shots, `${v}-${w}x${h}-${theme}.png`);
            await page.screenshot({ path: file }).catch(() => {});
            details.push(`FAIL ${tag}  (${path.basename(file)})\n    ` + f.slice(0, MAX_DETAIL).map(x => `[${x.rule}] ${x.msg}`).join("\n    ") + (f.length > MAX_DETAIL ? `\n    …${f.length - MAX_DETAIL} more` : ""));
          }
        }
        if (/^(empty|crowd)-/.test(v)) loaded = false; // these leave the seeded page
      }
    }
  } catch (e) {
    s.results.push(`ERROR ${e?.stack || e}`);
  } finally {
    await browser.close().catch(() => {});
  }
  for (const d of details) console.log(d);
  const code = s.finish();
  const pass = results.filter(r => !r.fails).length;
  if (details.length) console.log(`screenshots of failing states: ${shots}`);
  else fs.rmSync(shots, { recursive: true, force: true });
  console.log(`runtime ${Math.round((Date.now() - t0) / 1000)} s`);
  console.log(`PASS ${pass} / ${results.length}`);
  return code || pass !== results.length || !results.length ? 1 : 0;
}

/** A session of 13 guests and the host with one question open (the Host view needs a round), so the Host view's people list is past its compact cutoff (#8698). */
async function crowd(s, C) {
  s.apply(C.dir, [{ op: "open-round", questions: [q("Q1", "Which loot rule should the first playable use?")] }]);
  const base = C.localUrl.replace(/\/$/, "");
  for (let i = 1; i <= 13; i++) {
    const r = await fetch(base + "/api/join", { method: "POST", headers: { "Content-Type": "application/json", "CF-Connecting-IP": `198.51.100.${i}` }, body: JSON.stringify({ name: `Guest ${i}`, device: "computer" }) });
    if (!r.ok) throw new Error(`join Guest ${i} -> ${r.status}`);
  }
}

/** Resolves once the page holds still, so the check measures what a person sees and not a passing frame: fonts
 *  loaded, no finite animation running, and every box in #app the same for two frames in a row (5 s at most). A theme
 *  switch starts color transitions (0.01 ms under reduced motion, still a frame on a busy machine), and mid-way a
 *  popover's or the chat panel's background reads as a half-way color the overlap rule cannot call opaque. */
const settled = page => page.evaluate(async () => {
  const frame = () => new Promise(r => requestAnimationFrame(() => r()));
  const running = () => document.getAnimations().filter(a => a.playState === "running" && a.effect?.getTiming().iterations !== Infinity);
  const boxes = () => [...document.querySelectorAll("#app *")].map(e => { const r = e.getBoundingClientRect(); return `${r.x},${r.y},${r.width},${r.height}`; }).join("|");
  await document.fonts.ready;
  const t0 = performance.now();
  let last = null, same = 0;
  while (performance.now() - t0 < 5000) {
    await Promise.all(running().map(a => a.finished.catch(() => null)));
    await frame();
    const now = boxes();
    same = now === last && !running().length ? same + 1 : 0;
    if (same >= 2) return;
    last = now;
  }
});

function helpers(page) {
  const clickIn = (sel, text) => page.evaluate(([sel, text]) => {
    const els = [...document.querySelectorAll(sel)].filter(e => !text || e.textContent.includes(text));
    const el = els.find(e => e.offsetParent || getComputedStyle(e).position === "fixed") || null;
    if (!el) return false;
    el.scrollIntoView({ block: "nearest" }); el.click(); return true;
  }, [sel, text]);
  const phone = () => page.evaluate(() => matchMedia("(max-width: 720px)").matches);
  const reset = async () => {
    for (let i = 0; i < 3; i++) await page.keyboard.press("Escape");
    // drop drafts a view typed (the mention views), so the next view starts clean
    await page.evaluate(() => {
      for (const t of document.querySelectorAll("#vf-answer, .vf-minput")) if (t.value) { t.value = ""; t.dispatchEvent(new Event("input", { bubbles: true })); }
      document.activeElement?.blur?.();
    });
  };
  // phones reach Ask Claude, Share, Settings and Host through the More sheet
  const more = async label => { if (!(await clickIn(".vf-tab", "More"))) return false; await page.waitForTimeout(120); return clickIn(".vf-msitem", label); };
  const mode = async m => {
    if (await phone()) return m === "host" ? more("Host view") : clickIn(".vf-tab", { focus: "Answer", compare: "Compare", tree: "Tree" }[m]);
    return clickIn(".vf-bar .vf-seg-btn", { focus: "Focus", compare: "Compare", tree: "Tree", host: "Host" }[m]);
  };
  const joinIfAsked = async name => {
    await page.waitForTimeout(300);
    if (await page.locator("#core-n").count()) {
      await page.fill("#core-n", name); await page.click("dialog.core-name button");
      // "Were you here before as …?": a fresh guest at each size answers No
      await page.waitForTimeout(400);
      await page.locator("dialog.core-name .core-btn-quiet").click({ timeout: 1000 }).catch(() => {});
    }
    await page.waitForSelector(".vf-top"); await page.waitForTimeout(1600);
  };
  return { clickIn, phone, reset, more, mode, joinIfAsked };
}

function views(page, CFG) {
  const { clickIn, phone, more, mode, joinIfAsked } = helpers(page);
  // the Claude thread: the "Claude on this question" section below the answers, opened
  const claudeTab = async () => { if (await page.evaluate(() => document.querySelector(".vf-cltoggle")?.getAttribute("aria-expanded") !== "true")) await page.click(".vf-cltoggle"); return true; };
  const gotoQ = async id => { await mode("tree"); const ok = await clickIn(`[data-tkey="q:${id}"]`); await mode("focus"); return ok; };
  const railTab = async () => { if (await phone()) await clickIn(".vf-tab", "Questions"); };
  const W = ms => page.waitForTimeout(ms);
  let guests = 0;
  return {
    "focus-q1-short": () => gotoQ("Q1"),
    // O113: the owner's "Who must answer" panel, open; the column rule holds it to the question's width
    "for-panel": async () => { await gotoQ("Q1"); if (!(await clickIn(".vf-forbtn"))) return false; await W(120); return page.evaluate(() => !document.querySelector(".vf-forbox").hidden); },
    "focus-q3-longword": () => gotoQ("Q3"),
    "focus-q4-locked": () => gotoQ("Q4"),
    "focus-q5-emoji": () => gotoQ("Q5"),
    "focus-q6-rtl": () => gotoQ("Q6"),
    "focus-q8-multipara": () => gotoQ("Q8"),
    "rail": async () => { await gotoQ("Q2"); await railTab(); return true; },
    "compare": () => mode("compare"),
    "tree": () => mode("tree"),
    "proposed": async () => { await railTab(); return clickIn(".vf-proprow", "Proposed"); },
    // the Inbox page on Needs you: the host's request rows behind their chips, and what else waits on the host
    "review": async () => { if (!((await phone()) ? await more("Inbox") : await clickIn(".vf-bell"))) return false; await W(120); return clickIn(".vf-ixtabs .vf-seg-btn", "Needs you"); },
    "inbox-history": async () => { if (!((await phone()) ? await more("Inbox") : await clickIn(".vf-bell"))) return false; await W(120); return clickIn(".vf-ixtabs .vf-seg-btn", "History"); },
    "propose-form": async () => { await railTab(); return clickIn(".vf-propose"); },
    "chat": () => clickIn(".vf-fab"),
    "settings": async () => ((await phone()) ? more("Settings") : clickIn(".vf-gear")),
    "share": async () => ((await phone()) ? more("Share") : clickIn(".vf-sharebtn")),
    "shortcuts": async () => { await page.keyboard.press("?"); return true; },
    "person-card": async () => { await gotoQ("Q1"); return clickIn(".vf-card [data-pid], .vf-alist [data-pid]"); },
    // Q2 has answers but no votes, so Lock top answer only shows a toast (no state change)
    "toast": async () => { await gotoQ("Q2"); const ok = await clickIn(".vf-anshead .vf-btn-brass"); await W(300); return ok; },
    "toast-chat": async () => { await gotoQ("Q2"); await clickIn(".vf-fab"); const ok = await clickIn(".vf-anshead .vf-btn-brass"); await W(300); return ok; },
    "reader": async () => { await gotoQ("Q1"); await claudeTab(); return clickIn(".vf-res .vf-btn", "Full report"); },
    "host": () => mode("host"),
    "host-uploads": async () => { await mode("host"); return clickIn(".vf-qfilters .vf-fchip", "Uploads"); },
    "host-problems": async () => { await mode("host"); return clickIn(".vf-qfilters .vf-fchip", "Problems"); },
    "report-form": async () => {
      if (await phone()) return more("Report a problem");
      await page.keyboard.press("?"); await W(120); return clickIn(".vf-help-report");
    },
    // Your reports: the owner files one the first time (one report every 10 s), then opens the list from More or Help
    "my-reports": async () => {
      if (!(await page.evaluate(() => (window.Core.state.myReports || []).length))) {
        await page.evaluate(() => window.Core.report("The Send button did nothing on the payment question", window.Core.reportContext()));
        await page.waitForFunction(() => (window.Core.state.myReports || []).length > 0, null, { timeout: 5000 }).catch(() => {});
      }
      if (await phone()) return more("Your reports");
      await page.keyboard.press("?"); await W(120); return clickIn(".vf-help-myreps");
    },
    "ask-panel": async () => ((await phone()) ? more("Ask Claude") : clickIn(".vf-asktop")),
    "thread": async () => { await gotoQ("Q1"); return claudeTab(); },
    "choice": () => gotoQ("Q11"),
    "confirm": () => gotoQ("Q12"),
    "choice-lightbox": async () => { await gotoQ("Q11"); return clickIn(".vf-optview"); },
    // the owner's pick stays between sizes: choose only when it is not chosen yet
    "choice-picked": async () => {
      await gotoQ("Q11");
      if (!(await page.evaluate(() => !!document.querySelector(".vf-opt[data-state='mine']")))) { await clickIn(".vf-optchoose", "Choose"); await W(400); }
      return page.evaluate(() => !!document.querySelector(".vf-opt[data-state='mine']"));
    },
    "claude-hidden": () => gotoQ("Q3"),
    "device": async () => { await clickIn(".vf-person-me"); await W(150); return clickIn(".vf-pcard .vf-menu-item", "another device"); },
    "msg-menu": async () => { await clickIn(".vf-fab"); await W(150); return clickIn(".vf-msgmore"); },
    "compare-formats": async () => { await mode("compare"); return page.evaluate(() => { const b = document.querySelector(".vf-board"); if (!b) return false; b.scrollLeft = b.scrollWidth; return true; }); },
    // the Inbox remembers its tab on the device, and "review" leaves it on Needs you: these start on Notifications
    "bell": async () => { if (!(await clickIn(".vf-bell"))) return false; await W(120); return clickIn(".vf-ixtabs .vf-seg-btn", "Notifications"); },
    "bell-mute": async () => { await clickIn(".vf-bell"); await W(120); await clickIn(".vf-ixtabs .vf-seg-btn", "Notifications"); await W(120);
      // from 1100 px the switches sit open beside the messages with no button (follow-up 51); below, the button opens them
      return (await clickIn(".vf-mutebtn")) || page.evaluate(() => document.querySelector(".vf-ibside > .vf-mutebox")?.getClientRects().length > 0); },
    "mention": async () => {
      await gotoQ("Q9"); await page.click("#vf-answer"); await page.keyboard.type("Ask @");
      await W(150); return page.evaluate(() => !document.querySelector(".vf-mentions").hidden);
    },
    "mention-chat": async () => {
      await clickIn(".vf-fab"); await W(150); await page.click(".vf-minput"); await page.keyboard.type("@B");
      await W(150); return page.evaluate(() => !document.querySelector(".vf-mentions").hidden);
    },
    "references": async () => { await gotoQ("Q1"); return page.evaluate(() => { const r = document.querySelector(".vf-refs"); r?.scrollIntoView({ block: "start" }); return !!r; }); },
    "references-end": async () => { await gotoQ("Q1"); return page.evaluate(() => { const r = document.querySelector(".vf-reflist"); if (!r) return false; r.scrollIntoView({ block: "start" }); r.scrollLeft = r.scrollWidth; return true; }); },
    "ref-add": async () => { await gotoQ("Q5"); return clickIn(".vf-refadd"); },
    "ref-reader": async () => { await gotoQ("Q1"); return clickIn(".vf-ref-img"); },
    "reply": async () => { await clickIn(".vf-fab"); await W(150); await clickIn(".vf-msgmore"); await W(120); return clickIn(".vf-msgmenu .vf-menu-item", "Reply"); },
    "confirm-unlock": async () => { await gotoQ("Q4"); return clickIn(".vf-lock .vf-btn", "Unlock"); },
    "confirm-remove": async () => { await mode("host"); return clickIn(".vf-hpeople .vf-btn-danger", "Remove"); },
    "pick-thumbs": async () => { await gotoQ("Q11"); return page.evaluate(() => { const a = document.querySelector(".vf-alist .vf-pickthumb:not([hidden])"); a?.scrollIntoView({ block: "center" }); return !!a; }); },
    "more": async () => ((await phone()) ? clickIn(".vf-tab", "More") : "skip"),
    // last: these leave the seeded page; the next view reloads it
    // #8698: past 12 people the Host view's people rows are compact, one line each
    "crowd-host": async () => { await page.goto(CFG.crowdHost); await page.reload(); await joinIfAsked("Kyle"); return mode("host"); },
    "empty-host": async () => { await page.goto(CFG.emptyHost); await page.reload(); await joinIfAsked("Kyle"); return true; },
    "empty-guest": async () => { await page.goto(CFG.emptyGuest); await page.evaluate(() => localStorage.clear()); await page.reload(); await joinIfAsked(`Sam${++guests}`); return true; },
  };
}

/** The geometry rules, run in the page. Returns [{rule, msg}]. */
const check = (page, theme) => page.evaluate(theme => {
  const T = 0.5, out = [];
  const app = document.getElementById("app");
  const vis = el => {
    if (!el.isConnected || el.closest("[hidden]")) return false;
    const cs = getComputedStyle(el);
    if (cs.display === "none" || cs.visibility === "hidden" || +cs.opacity === 0) return false;
    const r = el.getBoundingClientRect();
    return r.width > 1 && r.height > 1;
  };
  const name = el => {
    const c = typeof el.className === "string" ? el.className : el.getAttribute?.("class") || "";
    const t = (el.textContent || "").trim().slice(0, 24);
    return `${el.tagName.toLowerCase()}${c ? "." + c.trim().split(/\s+/).join(".") : ""}${t ? ` "${t}"` : ""}`;
  };
  const fail = (rule, msg) => out.push({ rule, msg });
  const ownText = el => [...el.childNodes].filter(n => n.nodeType === 3 && n.textContent.trim());
  const firstLine = el => {
    const t = ownText(el)[0]; if (!t) return null;
    const rg = document.createRange(); rg.selectNodeContents(t);
    return [...rg.getClientRects()].find(r => r.width > 0) || null;
  };
  if (!app) return [{ rule: "setup", msg: "no #app on the page" }];
  // 0. No mention token (<@pid>, as the server stores a mention) anywhere: in text, an attribute, a field or the title.
  const raw = [document.title, document.documentElement.textContent, ...[...document.querySelectorAll("*")].flatMap(e => [...e.attributes].map(a => a.value)),
    ...[...document.querySelectorAll("input, textarea")].map(e => e.value)].join("\n").match(/<@[A-Za-z0-9_-]{1,32}>/);
  if (raw) fail("raw-token", `${raw[0]} shows on the page`);
  // the theme the page shows follows the emulated color scheme (the default theme mode is System)
  const shown = app.dataset.theme || document.documentElement.dataset.theme || app.closest("[data-theme]")?.dataset.theme;
  if (shown && shown !== theme) fail("theme", `page shows theme ${shown}, expected ${theme}`);
  const all = [...app.querySelectorAll("*")].filter(vis);
  const open = all.filter(e => !e.closest("svg") || e.tagName.toLowerCase() === "svg");

  // 1. No page-level scroll.
  const se = document.scrollingElement;
  if (se.scrollHeight > innerHeight + 1 || se.scrollWidth > innerWidth + 1) fail("page-scroll", `document ${se.scrollWidth}x${se.scrollHeight} > viewport ${innerWidth}x${innerHeight}`);
  if (app.scrollWidth > app.clientWidth + 1 || app.scrollHeight > app.clientHeight + 1) fail("page-scroll", `#app content ${app.scrollWidth}x${app.scrollHeight} > ${app.clientWidth}x${app.clientHeight}`);

  // 2. Horizontal overflow: content wider than its own box, or sticking out of a clipping ancestor or the viewport.
  const hScroller = el => { const cs = getComputedStyle(el); return /auto|scroll/.test(cs.overflowX) && el.scrollWidth > el.clientWidth; };
  for (const el of open) {
    if (el.tagName.toLowerCase() === "svg") continue;
    const cs = getComputedStyle(el), r = el.getBoundingClientRect();
    if (cs.position === "fixed" && (r.right <= 0 || r.left >= innerWidth)) continue; // parked offscreen on purpose
    if (cs.clip !== "auto" || cs.clipPath !== "none") continue; // sr-only
    if (r.right > innerWidth + T || r.left < -T) {
      let p = el.parentElement, inScroller = false;
      while (p && p !== app) { if (hScroller(p)) { inScroller = true; break; } p = p.parentElement; }
      if (!inScroller) fail("overflow", `${name(el)} spans x ${r.left.toFixed(1)}..${r.right.toFixed(1)} outside viewport ${innerWidth}`);
    }
    const clipsX = cs.overflowX !== "visible";
    if (!clipsX && cs.display !== "inline") {
      const right = r.right - parseFloat(cs.borderRightWidth), left = r.left + parseFloat(cs.borderLeftWidth);
      for (const t of ownText(el)) {
        const rg = document.createRange(); rg.selectNodeContents(t);
        const bad = [...rg.getClientRects()].find(q => q.width > 0 && (q.right > right + T || q.left < left - T));
        if (bad) { fail("overflow", `${name(el)} text x ${bad.left.toFixed(1)}..${bad.right.toFixed(1)} runs past its box x ${left.toFixed(1)}..${right.toFixed(1)}`); break; }
      }
    }
    // a form field scrolls its own value, so a long value in one is not clipped content
    if (clipsX && !el.matches("input, textarea, select") && cs.textOverflow !== "ellipsis" && !/auto|scroll/.test(cs.overflowX) && el.scrollWidth > el.clientWidth + 1
      && !(cs.webkitLineClamp && cs.webkitLineClamp !== "none")) {
      fail("overflow", `${name(el)} clips ${el.scrollWidth - el.clientWidth}px of content (overflow-x ${cs.overflowX}, no ellipsis)`);
    }
    const p = el.parentElement;
    if (p && p !== app && vis(p) && cs.position !== "absolute" && cs.position !== "fixed") {
      const pr = p.getBoundingClientRect(), pcs = getComputedStyle(p);
      // a negative margin is a deliberate bleed (hover backgrounds that keep text on the column edge)
      const bleedL = Math.max(0, -parseFloat(cs.marginLeft)), bleedR = Math.max(0, -parseFloat(cs.marginRight));
      if (pcs.overflowX === "visible" && pcs.display !== "inline" && (r.right > pr.right + bleedR + T || r.left < pr.left - bleedL - T)) {
        fail("overflow", `${name(el)} x ${r.left.toFixed(1)}..${r.right.toFixed(1)} sticks out of parent ${name(p)} x ${pr.left.toFixed(1)}..${pr.right.toFixed(1)}`);
      }
    }
  }

  // 2b. The focus view's column (O113): each block beside the question text spans the question text's width and place.
  const qt = document.querySelector(".vf-focus .vf-qtext");
  if (qt && vis(qt)) {
    const qr = qt.getBoundingClientRect();
    for (const el of qt.parentElement.children) {
      const cs = getComputedStyle(el);
      if (el === qt || !vis(el) || cs.display.startsWith("inline") || cs.position !== "static") continue;
      const r = el.getBoundingClientRect();
      if (Math.abs(r.left - qr.left) > 1 || Math.abs(r.right - qr.right) > 1) fail("column", `${name(el)} x ${r.left.toFixed(1)}..${r.right.toFixed(1)} is not on the question's column x ${qr.left.toFixed(1)}..${qr.right.toFixed(1)}`);
    }
  }
  // 2c. A phone's question row (app.css .vf-qmeta): previous and next stay on the position's row; the host's Who must
  // answer, the chips and the avatars of who else is on it wrap below, never the arrows.
  const qnav = document.querySelector(".vf-focus .vf-qmeta > .vf-qnav"), qpos = qnav?.parentElement.firstElementChild;
  if (qnav && vis(qnav) && qpos && vis(qpos)) {
    const n = qnav.getBoundingClientRect(), p = qpos.getBoundingClientRect();
    if (n.top >= p.bottom - T || n.bottom <= p.top + T) fail("qnav-row", `${name(qnav)} y ${n.top.toFixed(1)}..${n.bottom.toFixed(1)} wrapped off the position's row y ${p.top.toFixed(1)}..${p.bottom.toFixed(1)}`);
  }

  // 3. Visible text never overlaps other visible text.
  const texts = [];
  for (const el of open) {
    for (const t of ownText(el)) {
      const rg = document.createRange(); rg.selectNodeContents(t);
      for (const r of rg.getClientRects()) {
        if (r.width < 2 || r.height < 2) continue;
        const hit = document.elementFromPoint(Math.min(innerWidth - 1, r.left + r.width / 2), Math.min(innerHeight - 1, r.top + r.height / 2));
        if (!hit || !(el === hit || el.contains(hit) || hit.contains(el))) continue; // covered by a layer above
        const cs = getComputedStyle(el);
        if (cs.overflow !== "visible" || cs.textOverflow === "ellipsis") {
          const b = el.getBoundingClientRect();
          const L = Math.max(r.left, b.left), R = Math.min(r.right, b.right), Tp = Math.max(r.top, b.top), B = Math.min(r.bottom, b.bottom);
          if (R - L < 2 || B - Tp < 2) continue;
          texts.push({ el, r: { left: L, right: R, top: Tp, bottom: B } });
        } else texts.push({ el, r });
      }
    }
  }
  const opaque = s => { const bg = getComputedStyle(s).backgroundColor.replace(/\s/g, ""); return /rgba?\(|color\(|oklch\(/.test(bg) && !/,0\)$|\/0\)$|^rgba\(0,0,0,0\)$|transparent/.test(bg); };
  for (let i = 0; i < texts.length; i++) for (let j = i + 1; j < texts.length; j++) {
    const a = texts[i], b = texts[j];
    if (a.el === b.el || a.el.contains(b.el) || b.el.contains(a.el)) continue;
    const w = Math.min(a.r.right, b.r.right) - Math.max(a.r.left, b.r.left);
    const h = Math.min(a.r.bottom, b.r.bottom) - Math.max(a.r.top, b.r.top);
    if (!(w > 1 && h > Math.min(a.r.bottom - a.r.top, b.r.bottom - b.r.top) * 0.35)) continue;
    const cx = Math.max(a.r.left, b.r.left) + w / 2, cy = Math.max(a.r.top, b.r.top) + h / 2;
    const stack = document.elementsFromPoint(cx, cy);
    const covered = el => {
      const k = stack.findIndex(s => s === el || el.contains(s));
      if (k < 0) return true;
      return stack.slice(0, k).some(s => !s.contains(el) && !el.contains(s) && opaque(s));
    };
    if (covered(a.el) || covered(b.el)) continue;
    fail("text-overlap", `${name(a.el)} overlaps ${name(b.el)} (${w.toFixed(1)}x${h.toFixed(1)})`);
  }

  // 4. Sibling rows of one kind share the left x of icon, id and text; icons center on their first text line.
  const STATE = /^(vf-(?:q-cur|tcur|col-cur|round-cur|rcur|fresh|ritem-fresh|on|pinned|mine|tgrey|tlocked|topen|bump|badge-pop|dim|edited|nunread|hl))$/;
  const kindOf = el => `${el.tagName}|${[...el.classList].filter(c => !STATE.test(c)).sort().join(".")}`;
  const ICON = "svg, .core-avatar, .vf-tstat, .vf-qstat, .vf-rstat, .vf-mp-stat, .vf-mr-stat, .vf-claude-av, .vf-switch";
  const lines = row => {
    const tw = document.createTreeWalker(row, NodeFilter.SHOW_TEXT), res = [];
    for (let n; (n = tw.nextNode());) {
      const el = n.parentElement;
      if (!n.textContent.trim() || !vis(el) || el.closest(ICON) || el.closest(".vf-tid")) continue;
      const rg = document.createRange(); rg.selectNodeContents(n);
      const rs = [...rg.getClientRects()].filter(r => r.width > 0);
      if (rs.length) res.push({ el, r: rs[0] });
    }
    return res;
  };
  const parts = row => {
    const icon = [...row.querySelectorAll(ICON)].find(e => vis(e) && !e.parentElement.closest(ICON)) || null;
    const id = [...row.querySelectorAll(".vf-tid")].find(vis) || null;
    const ls = lines(row);
    return { icon, id, text: ls[0]?.el || null, ls };
  };
  const rowsets = [];
  for (const p of open) {
    const kids = [...p.children].filter(vis);
    const byKind = new Map();
    for (const k of kids) { const key = kindOf(k); if (!byKind.has(key)) byKind.set(key, []); byKind.get(key).push(k); }
    for (const [key, rows] of byKind) if (rows.length >= 2 && !/^(SPAN|svg|path|BR|KBD|DT|DD|P|polyline|circle|line|rect)\|/i.test(key)) rowsets.push({ where: `${name(p).split(" ")[0]} > ${key.split("|")[1] || key.split("|")[0]}`, rows });
  }
  for (const sel of [".vf-tq", ".vf-tleaf:not(.vf-tgrey)", ".vf-tround", ".vf-q", ".vf-proprow", ".vf-sw-row", ".vf-menu-item"]) {
    const rows = [...app.querySelectorAll(sel)].filter(vis);
    if (rows.length >= 2) rowsets.push({ where: sel, rows });
  }
  for (const { where, rows } of rowsets) {
    const ps = rows.map(r => ({ r, ...parts(r), box: r.getBoundingClientRect() }));
    const sameCol = ps.filter(p => Math.abs(p.box.left - ps[0].box.left) <= T);
    if (sameCol.length < 2) continue;
    for (const k of ["icon", "id", "text"]) for (const kind of new Set(sameCol.filter(p => p[k]).map(p => kindOf(p[k])))) {
      const have = sameCol.filter(p => p[k] && kindOf(p[k]) === kind);
      if (have.length < 2) continue;
      const boxXs = have.map(p => p[k].getBoundingClientRect().left);
      const min = Math.min(...boxXs), max = Math.max(...boxXs);
      if (max - min > T) {
        const odd = have[boxXs.indexOf(Math.abs(boxXs[0] - min) > T ? min : max)];
        fail("row-align", `${where}: ${k} left x ranges ${min.toFixed(1)}..${max.toFixed(1)} across ${have.length} rows (odd: ${name(odd.r)})`);
      }
    }
  }
  // live-pill: the Live pill sits on the title's line, its center y within 1px of the title row's, its left edge at most
  // 8px past the title or rename pencil before it, inside the row, and clear of every other top-bar control
  const pill = app.querySelector(".vf-top .vf-live"), trow = app.querySelector(".vf-top .vf-titlerow");
  if (pill && trow && vis(pill) && vis(trow)) {
    const pb = pill.getBoundingClientRect(), rb = trow.getBoundingClientRect();
    const before = [...trow.children].filter(k => k !== pill && vis(k)).map(k => k.getBoundingClientRect()).filter(b => b.right <= pb.left + T);
    const prevRight = before.length ? Math.max(...before.map(b => b.right)) : rb.left;
    const dy = (pb.top + pb.bottom) / 2 - (rb.top + rb.bottom) / 2;
    if (Math.abs(dy) > 1) fail("live-pill", `${name(pill)} center y off the title row's by ${dy.toFixed(1)}px`);
    if (pb.left - prevRight > 8 + T) fail("live-pill", `${name(pill)} left x ${pb.left.toFixed(1)} sits ${(pb.left - prevRight).toFixed(1)}px past the title row's content end ${prevRight.toFixed(1)}`);
    if (pb.left < rb.left - T || pb.right > rb.right + T) fail("live-pill", `${name(pill)} x ${pb.left.toFixed(1)}..${pb.right.toFixed(1)} outside the title row x ${rb.left.toFixed(1)}..${rb.right.toFixed(1)}`);
    for (const el of app.querySelectorAll(".vf-top button, .vf-top .vf-people, .vf-top .vf-here")) {
      if (!vis(el) || trow.contains(el)) continue;
      const b = el.getBoundingClientRect();
      if (b.left < pb.right - T && b.right > pb.left + T && b.top < pb.bottom - T && b.bottom > pb.top + T) fail("live-pill", `${name(pill)} overlaps ${name(el)}`);
    }
  } else if (pill && vis(pill)) fail("live-pill", `${name(pill)} shows with no title row beside it`);
  // toast: centered on the center pane ±1px, text centered, clear of composer, tab bar, chat button and chat
  const toast = app.querySelector(".vf-toast.vf-on");
  if (toast && vis(toast)) {
    const tb = toast.getBoundingClientRect(), mid = (tb.left + tb.right) / 2;
    const cp = app.querySelector(".vf-center"), C = cp && vis(cp) ? cp.getBoundingClientRect() : { left: 0, right: innerWidth };
    const chEl = [app.querySelector(".vf-chat"), app.querySelector(".vf-drawer")].find(e => e && vis(e) && !matchMedia("(max-width: 720px)").matches) || app.querySelector(".vf-chat");
    const ch = chEl && vis(chEl) ? chEl.getBoundingClientRect() : null;
    const full = (C.left + C.right) / 2, narrowed = (C.left + (ch ? ch.left - 8 : 0)) / 2;
    const ref = Math.abs(mid - full) <= 1 || !ch ? full : narrowed;
    if (ref === full && ch && ch.left < tb.right && ch.left > C.left + 200) fail("toast", "toast centered on the full pane runs under the open chat panel");
    if (Math.abs(mid - ref) > 1) fail("toast", `toast center x ${mid.toFixed(1)} vs center-pane center ${ref.toFixed(1)}`);
    if (getComputedStyle(toast).textAlign !== "center") fail("toast", "toast text is not centered");
    for (const el of app.querySelectorAll(".vf-top, .vf-composer, .vf-tabs, .vf-fab, .vf-chat, .vf-panel, .vf-drawer, textarea, input")) {
      if (!vis(el)) continue;
      const b = el.getBoundingClientRect();
      if (b.left < tb.right && b.right > tb.left && b.top < tb.bottom && b.bottom > tb.top) fail("toast", `toast overlaps ${name(el)}`);
    }
    if (tb.top < 0 || tb.bottom > innerHeight) fail("toast", "toast is outside the viewport");
    // a dock is a composer or tab bar pinned to the viewport's bottom (on wide screens the composer sits in the page)
    const dock = [...app.querySelectorAll(".vf-composer, .vf-tabs")].filter(vis).map(e => e.getBoundingClientRect())
      .filter(b => b.left < tb.right && b.right > tb.left && b.bottom >= innerHeight - 2).sort((a, b) => a.top - b.top)[0];
    const topBar = app.querySelector(".vf-top").getBoundingClientRect();
    const blocked = [...app.querySelectorAll(".vf-chat, .vf-panel, .vf-drawer")].some(e => vis(e) && e.getBoundingClientRect().left < tb.right && e.getBoundingClientRect().right > tb.left);
    if (blocked && Math.abs(tb.top - (topBar.bottom + 8)) > 1) fail("toast", `with a panel open below, toast top ${tb.top.toFixed(1)} should sit 8px under the top bar (${(topBar.bottom + 8).toFixed(1)})`);
    if (dock && !blocked && !(tb.bottom <= dock.top && tb.bottom >= dock.top - 24)) fail("toast", `toast bottom ${tb.bottom.toFixed(1)} is not just above the dock top ${dock.top.toFixed(1)}`);
  }
  if (window.__expectToast && !(toast && vis(toast))) fail("toast", "no toast showed");
  // phone tab bar: equal cells, every label (badge included) inset at least 4px inside its own cell
  const tabCells = [...app.querySelectorAll(".vf-tab")].filter(vis);
  if (tabCells.length) {
    const ws = tabCells.map(t => t.getBoundingClientRect().width);
    if (Math.max(...ws) - Math.min(...ws) > T) fail("row-align", `tab cells differ in width: ${ws.map(w => w.toFixed(1)).join(", ")}`);
    const labels = tabCells.map(t => [...t.querySelectorAll("*")].filter(k => vis(k) && !k.matches(".vf-badge")));
    tabCells.forEach((t, i) => {
      const bd = [...t.querySelectorAll(".vf-badge")].find(vis), nx = labels[i + 1]?.[0];
      if (bd && nx && bd.getBoundingClientRect().right > nx.getBoundingClientRect().left - 4 + T) fail("overflow", `${name(bd)} comes within 4px of the next tab's label`);
      if (bd && !nx && bd.getBoundingClientRect().right > t.getBoundingClientRect().right + T) fail("overflow", `${name(bd)} runs past the last tab`);
    });
    for (const [i, t] of tabCells.entries()) {
      const c = t.getBoundingClientRect();
      for (const k of labels[i]) {
        const b = k.getBoundingClientRect();
        if (b.left < c.left + 4 - T || b.right > c.right - 4 + T) fail("overflow", `${name(k)} x ${b.left.toFixed(1)}..${b.right.toFixed(1)} has under 4px inset in tab cell x ${c.left.toFixed(1)}..${c.right.toFixed(1)}`);
      }
    }
  }
  // icon-line: an icon vs the text line beside it (the first line sharing its height band, else the row's first line)
  const seen = new Set();
  for (const { rows } of rowsets) for (const r of rows) {
    const { icon, ls } = parts(r);
    if (!icon || seen.has(icon)) continue; seen.add(icon);
    const ib = icon.getBoundingClientRect();
    const side = ls.filter(l => l.r.left >= ib.right - T || l.r.right <= ib.left + T);
    if (!side.length) continue;
    const pick = side.find(l => l.r.top < ib.bottom && l.r.bottom > ib.top) || side[0];
    const multi = pick.el.getBoundingClientRect().height > pick.r.height * 1.7;
    if (ib.height > 24 && multi) continue; // large avatars may top-align with a block
    const cs = getComputedStyle(pick.el), lh = parseFloat(cs.lineHeight), eb = pick.el.getBoundingClientRect();
    const top = eb.top + parseFloat(cs.borderTopWidth) + parseFloat(cs.paddingTop);
    const blockLine = cs.display !== "inline" && lh > 0 && pick.r.top >= top - 0.5 && pick.r.bottom <= top + lh + 0.5;
    const lineMid = blockLine ? top + lh / 2 : pick.r.top + pick.r.height / 2, iconMid = ib.top + ib.height / 2;
    if (Math.abs(lineMid - iconMid) > 1) fail("icon-line", `${name(icon)} center y off the text line of ${name(pick.el)} by ${(iconMid - lineMid).toFixed(1)}px`);
  }
  for (const svg of app.querySelectorAll("svg")) {
    if (!vis(svg) || seen.has(svg)) continue;
    const lab = [...svg.parentElement.children].find(s => s !== svg && vis(s) && ownText(s).length) || (ownText(svg.parentElement).length ? svg.parentElement : null);
    if (!lab) continue;
    const fl = firstLine(lab); if (!fl) continue;
    const ib = svg.getBoundingClientRect();
    if (fl.left < ib.right - T && ib.left < fl.right) continue;
    const d = (ib.top + ib.height / 2) - (fl.top + fl.height / 2);
    if (Math.abs(d) > 1) fail("icon-line", `${name(svg.parentElement)} icon off its label's first line by ${d.toFixed(1)}px`);
  }
  // icon-center: an icon-only button (the answer and chat send buttons, the chat button, any round icon button) has
  // its one visible icon centered on the button's border box within 0.5 px on both axes.
  const shownText = b => { // text a person sees in the button, badges (positioned) and screen-reader-only labels left out
    const tw = document.createTreeWalker(b, NodeFilter.SHOW_TEXT);
    for (let n; (n = tw.nextNode());) {
      const el = n.parentElement;
      if (!n.textContent.trim() || !vis(el) || el.closest("svg")) continue;
      if (el !== b && ["absolute", "fixed"].includes(getComputedStyle(el).position)) continue;
      const rg = document.createRange(); rg.selectNodeContents(n);
      if ([...rg.getClientRects()].some(r => r.width > 1 && r.height > 1)) return true;
    }
    return false;
  };
  const named = [".vf-composer .vf-sendbtn", ".vf-composer button[type=submit]", ".vf-mform button[type=submit]", ".vf-fab"];
  const cands = new Set(named.flatMap(sel => [...app.querySelectorAll(sel)]));
  for (const b of app.querySelectorAll("button, [role=button]")) {
    if (!vis(b)) continue;
    const r = b.getBoundingClientRect(), rad = parseFloat(getComputedStyle(b).borderTopLeftRadius) || 0;
    if (rad >= Math.min(r.width, r.height) / 2 - 1) cands.add(b);
  }
  for (const b of cands) {
    if (!vis(b) || shownText(b)) continue;
    const icons = [...b.querySelectorAll("svg")].filter(s => vis(s) && !s.parentElement.closest("svg"));
    if (icons.length !== 1) continue;
    const br = b.getBoundingClientRect(), ir = icons[0].getBoundingClientRect();
    const dx = (ir.left + ir.right) / 2 - (br.left + br.right) / 2, dy = (ir.top + ir.bottom) / 2 - (br.top + br.bottom) / 2;
    if (Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5) fail("icon-center", `${name(b)}${b.getAttribute("aria-label") ? ` [${b.getAttribute("aria-label")}]` : ""} icon center off the button center by x ${dx.toFixed(2)}, y ${dy.toFixed(2)}px (button ${br.width.toFixed(1)}x${br.height.toFixed(1)}, icon ${ir.width.toFixed(1)}x${ir.height.toFixed(1)})`);
  }
  // marker-number: each question-list marker holds its id number, whose ink centers on the marker within 0.5 px.
  // Ink comes from drawing the number K times larger on a canvas and scanning its pixels (measureText rounds to whole
  // px); the baseline from a zero-height inline-block probe.
  const K = 20, cv = document.createElement("canvas"), ink = cv.getContext("2d", { willReadFrequently: true });
  for (const b of app.querySelectorAll(".vf-q")) {
    const m = b.querySelector(".vf-qstat");
    if (!vis(b) || !m || !vis(m)) continue;
    const n = m.querySelector(".vf-qnum"), t = n?.firstChild;
    if (!t || n.textContent !== b.dataset.qid?.slice(1)) { fail("marker-number", `${name(b)} marker shows "${m.textContent}", not its id number`); continue; }
    const cs = getComputedStyle(n), rg = document.createRange(); rg.selectNodeContents(t);
    const probe = document.createElement("span"); probe.style.cssText = "display:inline-block;inline-size:0;block-size:0"; n.append(probe);
    const base = probe.getBoundingClientRect().top; probe.remove();
    const tr = rg.getClientRects()[0], size = parseFloat(cs.fontSize) * K;
    cv.width = Math.ceil(tr.width * K + 2 * size); cv.height = 3 * size;
    ink.font = `${cs.fontWeight} ${size}px ${cs.fontFamily}`; ink.textBaseline = "alphabetic"; ink.fillText(t.textContent, size, 2 * size);
    const px = ink.getImageData(0, 0, cv.width, cv.height).data;
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    for (let y = 0; y < cv.height; y++) for (let x = 0; x < cv.width; x++) if (px[(y * cv.width + x) * 4 + 3] > 127) { x0 = Math.min(x0, x); x1 = Math.max(x1, x + 1); y0 = Math.min(y0, y); y1 = Math.max(y1, y + 1); }
    const mr = m.getBoundingClientRect();
    const dx = tr.left + ((x0 + x1) / 2 - size) / K - (mr.left + mr.right) / 2;
    const dy = base + ((y0 + y1) / 2 - 2 * size) / K - (mr.top + mr.bottom) / 2;
    if (Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5) fail("marker-number", `${name(b)} number ${t.textContent} ink off the marker center by x ${dx.toFixed(2)}, y ${dy.toFixed(2)}px`);
  }
  // fold: with nothing focused and the question at its top, a choice or confirm question's answer controls show
  // without scrolling (confirm: every pick button; choice: the first Choose button)
  const act = document.activeElement;
  if (!act || act === document.body || act === app) {
    const fmt = document.querySelector(".vf-fmt");
    const scroller = fmt && fmt.closest(".vf-scroll, [class*='scroll']");
    if (fmt && vis(fmt) && scroller && scroller.scrollTop < 2) {
      const bottom = Math.min(scroller.getBoundingClientRect().bottom, innerHeight);
      const ctrls = fmt.dataset.fmt === "confirm" ? [...fmt.querySelectorAll(".vf-pickbtn")].filter(vis) : [...fmt.querySelectorAll(".vf-optchoose")].filter(vis).slice(0, 1);
      for (const c of ctrls) if (c.getBoundingClientRect().bottom > bottom + T) fail("fold", `${name(c)} ends at ${c.getBoundingClientRect().bottom.toFixed(0)}px, below the fold at ${bottom.toFixed(0)}px`);
    }
  }
  return [...new Map(out.map(f => [f.rule + f.msg, f])).values()];
}, theme);

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
