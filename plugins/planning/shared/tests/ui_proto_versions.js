#!/usr/bin/env node
// A prototype's versions across rounds in real browsers, against `share.sh ensure-running` with the fake cloudflared.
// Round 1 asks Q1, a prototype with an html variant "One page" (version 1) and a picture "Two steps"; round 2 asks Q3,
// whose html variant "One page, shorter" names Q1's "One page" as its previous version (version 2, the current one),
// beside a picture "Three steps" with no earlier version. A guest on a desktop: finds both prototypes with the
// Prototypes filter, the rail showing them without scrolling; reads Q3's version list (v1 on Q1, v2 on Q3, v2 marked
// current, no list for Three steps); opens v1 from Q3's card and reads on its page which version is current; compares
// v1 and v2 side by side (v1 in a sandboxed frame with no pin helper, beside the current one); sees a note pinned on
// v1 stay on v1. Q1 is stored as a build before the look-at line wrote it (no lookAt): its page shows no look-at line,
// while Q3's shows its own. A guest on a 390x844 phone sees the two versions stacked. No 429, no CSP violation, no
// page error.
//   node plugins/planning/shared/tests/ui_proto_versions.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the issue's acceptance (open v1 and v2 from a later question, tell which is current, find
// earlier prototypes without scrolling), the questions and links written below, never from the page.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { loadPlaywright, suite, recorder, until, joinAs, png } = require("./browser_harness");

const page = text => `<!doctype html><html><body><main><h1>${text}</h1><button>Pay now</button></main></body></html>`;
const q = (id, text, format) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format });
const PHONE = { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 };

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_proto_versions.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_proto_versions"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("versions");
    const one = s.asset(A.dir, "one.html", page("One page")), shorter = s.asset(A.dir, "shorter.html", page("One page, shorter"));
    const two = s.asset(A.dir, "two.png", png(300, 200, [80, 120])), three = s.asset(A.dir, "three.png", png(300, 200, [20, 60]));
    s.apply(A.dir, [{ op: "set-title", title: "Checkout versions" }, { op: "open-round", questions: [
      q("Q1", "Which checkout layout?", { kind: "prototype", lookAt: "The layout.", variants: [{ id: "v-1", label: "One page", asset: one }, { id: "v-2", label: "Two steps", asset: two }] }),
      q("Q2", "What should the pay button say?", { kind: "text" }),
    ] }]);
    // Q1 as a build before the look-at line wrote it: the server reads the file again when it starts.
    s.share(A.dir, "stop");
    const file = path.join(A.dir, "state.json"), doc = JSON.parse(fs.readFileSync(file, "utf8"));
    delete doc.questions.find(x => x.id === "Q1").format.lookAt;
    fs.writeFileSync(file, JSON.stringify(doc) + "\n");
    s.share(A.dir, "ensure-running", "--guest-port", new URL(A.localUrl).port);
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => (window.Core?.snapshot()?.questions || []).some(x => x.id === "Q1"));
    await owner.evaluate(() => window.Core.sendRound());
    s.apply(A.dir, [{ op: "ack-round", round: 1 }, { op: "open-round", questions: [
      q("Q3", "Which checkout layout now?", { kind: "prototype", lookAt: "The order total, at the top of each page.", variants: [
        { id: "v-1", label: "One page, shorter", asset: shorter, previous: { qid: "Q1", variant: "v-1" } }, { id: "v-2", label: "Three steps", asset: three }] }),
      q("Q4", "Where should the total sit?", { kind: "text" }),
      q("Q5", "Anything else about checkout?", { kind: "text" }),
    ] }]);

    // ---------- finding the prototypes from every round ----------
    const gus = await rec.open(A.localUrl);
    await joinAs(gus, "Gus");
    await until(gus, () => (window.Core?.snapshot()?.questions || []).some(x => x.id === "Q3"));
    if (!(await gus.locator(".vf-fchip", { hasText: "Prototypes" }).isVisible())) await gus.click(".vf-viewopts");
    await gus.locator(".vf-fchip", { hasText: "Prototypes" }).click();
    const rail = await gus.evaluate(() => {
      const list = [...document.querySelectorAll(".vf-q[data-qid]")].filter(b => b.getClientRects().length);
      const r = b => b.getBoundingClientRect(), inView = b => r(b).top >= 0 && r(b).bottom <= innerHeight;
      return { qids: list.map(b => b.dataset.qid), inView: list.every(inView), note: document.querySelector(".vf-railfilter")?.textContent || "" };
    });
    ok("the Prototypes filter shows the prototypes of both rounds and nothing else", JSON.stringify(rail.qids) === JSON.stringify(["Q1", "Q3"]), JSON.stringify(rail));
    ok("both show without scrolling", rail.inView, JSON.stringify(rail));
    ok("the rail says it shows prototypes only", rail.note.startsWith("Showing Prototypes only"), rail.note);

    // ---------- Q3's version list ----------
    await gus.locator(".vf-q[data-qid=Q3]").click();
    await until(gus, () => !document.querySelector(".vf-proto-versions")?.hidden);
    const list = await gus.evaluate(() => [...document.querySelectorAll(".vf-proto-versions .vf-proto-line")].map(ol => ({
      label: ol.getAttribute("aria-label"),
      items: [...ol.querySelectorAll("li")].map(li => ({ href: li.querySelector("a.vf-proto-ver")?.getAttribute("href"), text: li.querySelector("a.vf-proto-ver")?.textContent,
        current: !!li.querySelector(".vf-proto-cur") })),
      cmp: ol.parentElement.querySelector(".vf-proto-cmp")?.getAttribute("href") })));
    ok("Q3 lists one line of versions, for One page, shorter", list.length === 1 && list[0].label === "Versions of One page, shorter", JSON.stringify(list));
    ok("v1 opens on Q1 and v2 on Q3", JSON.stringify(list[0]?.items.map(i => i.href)) === JSON.stringify(["/proto/Q1#v=v-1", "/proto/Q3#v=v-1"]), JSON.stringify(list[0]?.items));
    ok("each version names its number, question and label", JSON.stringify(list[0]?.items.map(i => i.text)) === JSON.stringify(["v1 · Q1 · One page", "v2 · Q3 · One page, shorter"]), JSON.stringify(list[0]?.items));
    ok("only v2 is marked current", JSON.stringify(list[0]?.items.map(i => i.current)) === JSON.stringify([false, true]), JSON.stringify(list[0]?.items));
    ok("Compare opens v2's page with v1 beside it", list[0]?.cmp === "/proto/Q3#v=v-1&with=Q1.v-1", list[0]?.cmp);

    // ---------- v1, opened from the later question ----------
    const [v1] = await Promise.all([gus.context().waitForEvent("page"), gus.locator(".vf-proto-ver", { hasText: "v1 · Q1" }).click()]);
    v1.on("pageerror", e => rec.errors.push(String(e)));
    v1.on("console", m => { if (m.type() === "error") rec.errors.push(m.text()); });
    await v1.waitForLoadState();
    ok("v1 opens Q1's prototype page on One page", new URL(v1.url()).pathname === "/proto/Q1"
      && await until(v1, () => document.querySelector(".vp-tab[aria-selected=true]")?.textContent.startsWith("One page")), v1.url());
    const nav = await v1.evaluate(() => ({ head: document.querySelector(".vp-versions-h")?.textContent || "",
      items: [...document.querySelectorAll(".vp-versions li")].map(li => ({ text: li.querySelector(".vp-ver")?.textContent, viewing: li.querySelector(".vp-ver")?.getAttribute("aria-current") === "page",
        current: !!li.querySelector(".vp-ver-cur") })) }));
    ok("v1's page says it shows version 1 of 2", nav.head === "Version 1 of 2", nav.head);
    ok("Q1, stored with no look-at line, shows none", await v1.evaluate(() => !document.querySelector(".vp-look").checkVisibility() && !window.Core.snapshot().questions[0].format.lookAt));
    ok("and marks v1 as the one shown and v2 as current", JSON.stringify(nav.items) === JSON.stringify([
      { text: "v1 · Q1 · One page", viewing: true, current: false }, { text: "v2 · Q3 · One page, shorter", viewing: false, current: true }]), JSON.stringify(nav.items));
    await until(v1, () => !!document.querySelector(".vp-frame"));
    await v1.evaluate(() => window.Core.annotate("Q1", "v-1", { selector: "html", rect: { x: 0, y: 0, w: 100, h: 100 } }, "Too long for a phone."));
    ok("a note pinned on v1 shows on v1", await until(v1, () => document.querySelector(".vp-notes-h")?.textContent === "Notes on One page (1)"));

    // ---------- v1 and v2 side by side ----------
    const [both] = await Promise.all([gus.context().waitForEvent("page"), v1.locator(".vp-ver-cmp").click()]);
    both.on("pageerror", e => rec.errors.push(String(e)));
    both.on("console", m => { if (m.type() === "error") rec.errors.push(m.text()); });
    await both.waitForLoadState();
    ok("Side by side opens v2's page with v1 beside it", await until(both, () => location.pathname === "/proto/Q3" && new URLSearchParams(location.hash.slice(1)).get("with") === "Q1.v-1"), both.url());
    ok("both versions are framed", await until(both, () => !!document.querySelector(".vp-cmp-frame") && !!document.querySelector(".vp-frame")));
    const split = await both.evaluate(() => {
      const r = s => document.querySelector(s)?.getBoundingClientRect(), cmp = document.querySelector(".vp-cmp-frame");
      return { cmp: r(".vp-pane-cmp"), caps: [...document.querySelectorAll(".vp-pane-cap-t")].map(c => c.textContent),
        src: cmp?.getAttribute("src"), sandbox: cmp?.getAttribute("sandbox"), main: document.querySelector(".vp-frame")?.getAttribute("src"),
        mainBox: r(".vp-pane-main"), heights: [r(".vp-cmp-frame")?.height, r(".vp-frame")?.height], notes: document.querySelector(".vp-notes-h")?.textContent };
    });
    ok("v1 sits left of v2", split.cmp && split.mainBox && split.cmp.right <= split.mainBox.left + 1 && split.cmp.width > 200, JSON.stringify(split));
    ok("each frame fills its side's height", split.heights.every(h => h > 400), JSON.stringify(split.heights));
    ok("each side names its version, v2 as current", JSON.stringify(split.caps) === JSON.stringify(["v1 · Q1 · One page", "v2 · Q3 · One page, shorter · Current"]), JSON.stringify(split.caps));
    ok("v1 is framed in the sandbox with no pin helper, v2 with it", split.src === `/assets/${one}` && split.sandbox === "allow-scripts" && split.main === `/assets/${shorter}?pin=1`, JSON.stringify(split));
    ok("v1's note stays on v1: v2 has none", split.notes === "Notes on One page, shorter (0)", split.notes);
    ok("Q3's page says where to look", (await both.locator(".vp-look").textContent()) === "Where to look: The order total, at the top of each page.");
    await both.locator(".vp-cmp-close").click();
    ok("Close side by side leaves v2 alone", await until(both, () => !document.querySelector(".vp-cmp-frame") && !new URLSearchParams(location.hash.slice(1)).has("with")));
    const tabs = gus.context().pages().length;
    await both.locator(".vp-ver-cmp").click();
    ok("on v2's own page, Side by side shows v1 beside it in the same tab", await until(both, () => !!document.querySelector(".vp-cmp-frame")
      && new URLSearchParams(location.hash.slice(1)).get("with") === "Q1.v-1") && gus.context().pages().length === tabs, both.url());
    await both.locator(".vp-annotate").click();
    const cmpFrame = both.frames().find(f => f.url().includes(`/assets/${one}`));
    await cmpFrame?.evaluate(() => parent.postMessage({ type: "pinned", selector: "html", rect: { x: 0, y: 0, w: 10, h: 10 }, label: "forged" }, "*"));
    await both.waitForTimeout(600);
    ok("a pin message from v1's side opens nothing", !!cmpFrame && await both.locator(".vp-composer").isHidden());
    await both.frameLocator(".vp-frame").locator("button").click();
    await until(both, () => !document.querySelector(".vp-composer").hidden);
    await both.locator("#vp-note").fill("Shorter is better.");
    await both.locator(".vp-save").click();
    await until(both, () => (window.Core.snapshot()?.annotations || []).some(a => a.text === "Shorter is better."));
    const pinned = await both.evaluate(() => window.Core.snapshot().annotations.find(a => a.text === "Shorter is better."));
    ok("a note pinned on the page while v1 is beside v2 lands on v2", pinned?.qid === "Q3" && pinned?.variant === "v-1", JSON.stringify(pinned));
    await both.keyboard.press("Escape");

    // ---------- the phone: the two stacked ----------
    const pia = await rec.open(A.localUrl, { context: PHONE });
    await joinAs(pia, "Pia");
    const phone = await rec.openIn(pia.context(), new URL("/proto/Q3#v=v-1&with=Q1.v-1", A.localUrl).href);
    await until(phone, () => !!document.querySelector(".vp-cmp-frame"));
    const stack = await phone.evaluate(() => {
      const r = s => document.querySelector(s)?.getBoundingClientRect();
      return { cmp: r(".vp-pane-cmp"), main: r(".vp-pane-main"), overflow: document.documentElement.scrollWidth - innerWidth };
    });
    ok("on a phone v1 sits above v2, each full width, nothing wider than the screen", stack.cmp && stack.main && stack.cmp.bottom <= stack.main.top + 1
      && stack.cmp.width > 300 && stack.main.width > 300 && stack.overflow <= 0, JSON.stringify(stack));

    ok("no request was answered 429 (slow down)", rec.too.length === 0, rec.too.slice(0, 5).join(", "));
    const csp = [...await rec.cspViolations(), ...(await Promise.all([v1, both].map(p => p.evaluate(() => window.__csp || [])))).flat()];
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
