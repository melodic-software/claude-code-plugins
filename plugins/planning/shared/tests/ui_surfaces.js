#!/usr/bin/env node
// One surface model and one menu model (PR C, audit F11 and F12), against `share.sh ensure-running` with the fake
// cloudflared. Every dialog surface closes with one x named for what it closes, and focus goes back to what opened it;
// the Ask Claude panel is a bottom sheet only at phone width (720 px), the one breakpoint, so at 900 px it is a side
// drawer; Help lists the same entries as More in the same words, and a guest's desktop Help has Settings, which opens
// their own card.
//   node plugins/planning/shared/tests/ui_surfaces.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the consistency audit's F11 and F12 (one close control, an x whose name says what it closes;
// one breakpoint at 720 px; one menu model; guest Settings on desktop) and the texts this suite writes, never the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });
const DESK = { context: { viewport: { width: 1440, height: 900 } } };

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_surfaces.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_surfaces"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("surfaces");
    s.apply(A.dir, [{ op: "set-title", title: "Surfaces" }, { op: "set-intro", intro: "We are picking a checkout layout." },
      { op: "open-round", questions: [q("Q1", "Where should the order summary sit?")] }]);
    const owner = await rec.open(A.ownerUrl, DESK);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");

    // ---------- F11: one x on every surface, named for it; it closes and focus goes back ----------
    const SURFACES = [[".vf-gear", ".vf-settings", "Close Session settings"], [".vf-sharebtn", ".vf-share", "Close Invite people"],
      [".vf-keysbtn", ".vf-keys", "Close Help"], [".vf-introbtn", ".vf-intropop", "Close Why you're here"]];
    for (const [opener, pop, name] of SURFACES) {
      await owner.click(opener);
      await until(owner, sel => !document.querySelector(sel).hidden, pop);
      const xs = await owner.evaluate(sel => [...document.querySelector(sel).querySelectorAll("button")].filter(b => /^Close\b|^Done$/.test(b.getAttribute("aria-label") || b.textContent.trim()))
        .map(b => b.getAttribute("aria-label") || b.textContent.trim()), pop);
      ok(`${name.slice(6)}: one close control, an x labeled "${name}"`, JSON.stringify(xs) === JSON.stringify([name]), JSON.stringify(xs));
      await owner.getByRole("button", { name, exact: true }).click();
      ok(`  it closes and focus goes back to ${opener}`, await until(owner, ([sel, o]) => document.querySelector(sel).hidden && document.activeElement?.matches(o), [pop, opener]));
    }

    // ---------- F9: every Copy goes through one path: the clipboard and a toast, the button's words unchanged ----------
    await owner.context().grantPermissions(["clipboard-read", "clipboard-write"], { origin: new URL(A.ownerUrl).origin });
    await owner.click(".vf-sharebtn");
    await owner.locator(".vf-share button", { hasText: "Copy link" }).click();
    ok("Copy link in Invite people copies, says so in a toast, and keeps its own words", await until(owner, () => document.querySelector(".vf-toast.vf-on span")?.textContent === "Link copied. Send it to the people you want to ask.")
      && (await owner.locator(".vf-share .vf-crow button").last().textContent()) === "Copy link"
      && (await owner.evaluate(() => navigator.clipboard.readText())) === (await owner.inputValue(".vf-share .vf-share-url")));
    await owner.keyboard.press("Escape");

    // ---------- F11: one breakpoint: at 900 px Ask Claude is a side drawer, not a bottom sheet ----------
    const mid = await rec.open(A.localUrl, { context: { viewport: { width: 900, height: 800 } } });
    await joinAs(mid, "Mia");
    await mid.click(".vf-asktop");
    await until(mid, () => !document.querySelector(".vf-drawer").hidden);
    await mid.evaluate(() => Promise.all(document.querySelector(".vf-drawer").getAnimations().map(a => a.finished.catch(() => null))));
    const dr = await mid.evaluate(() => { const r = document.querySelector(".vf-drawer").getBoundingClientRect(); return { left: r.left, right: r.right, w: r.width, inert: document.querySelector(".vf-body").inert }; });
    ok("at 900 px the Ask Claude panel is a side drawer on the right, the page still live", dr.right === 900 && dr.w <= 420 && dr.left >= 480 && !dr.inert, JSON.stringify(dr));
    await mid.getByRole("button", { name: "Close Ask Claude", exact: true }).click();
    ok("  its x closes it and focus goes back to Ask Claude", await until(mid, () => document.querySelector(".vf-drawer").hidden && document.activeElement?.matches(".vf-asktop")));

    // ---------- F12: Help and More are one menu; a guest's desktop Help has Settings ----------
    const gus = await rec.open(A.localUrl, DESK);
    await joinAs(gus, "Gus");
    await gus.click(".vf-keysbtn");
    await until(gus, () => !document.querySelector(".vf-keys").hidden);
    const help = await gus.evaluate(() => [...document.querySelectorAll(".vf-keys .vf-hitem")].filter(b => !b.hidden).map(b => b.querySelector(".vf-ms-l").textContent));
    ok("a guest's desktop Help lists Settings, the tour, Why you're here and Report a problem", ["Settings", "Show me around", "Why you're here", "Report a problem"].every(l => help.includes(l)), JSON.stringify(help));
    await gus.locator(".vf-keys .vf-hitem", { hasText: "Settings" }).click();
    ok("  Settings opens Gus's own card: his name, accent and devices", await until(gus, () => { const c = document.querySelector(".vf-pcard"); return !!c && !c.hidden && /Gus/.test(c.getAttribute("aria-label") || "") && !!c.querySelector(".vf-swatch"); }),
      await gus.evaluate(() => document.querySelector(".vf-pcard")?.getAttribute("aria-label")));
    const pho = await rec.open(A.localUrl, { context: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true } });
    await joinAs(pho, "Pho");
    await pho.locator(".vf-tab", { hasText: "More" }).tap();
    await until(pho, () => !document.querySelector(".vf-moresheet").hidden);
    const more = await pho.evaluate(() => [...document.querySelectorAll(".vf-moresheet .vf-msitem")].filter(b => !b.hidden).map(b => b.querySelector(".vf-ms-l").textContent + "|" + b.querySelector(".vf-ms-d").textContent));
    const helpRows = await gus.evaluate(() => [...document.querySelectorAll(".vf-keys .vf-hitem")].filter(b => !b.hidden).map(b => b.querySelector(".vf-ms-l").textContent + "|" + b.querySelector(".vf-ms-d").textContent));
    // F12: Help's entries for a guest, in More's own words (the menu entries the spec moves out of the two copies).
    const HELP = ["Settings|Your name, accent and devices", "Show me around|A one-minute tour", "Why you're here|", "Report a problem|Tell the host something is broken"];
    ok("a guest's desktop Help lists Settings, the tour, Why you're here and Report a problem, in those words", JSON.stringify(helpRows) === JSON.stringify(HELP), JSON.stringify(helpRows));
    ok("  and a guest's phone More lists each of them in the same words", HELP.every(h => more.includes(h)), JSON.stringify(more));

    // ---------- F5: one list of person actions, the card's and the Host view people row's ----------
    const acts = (page, sel) => page.evaluate(x => [...document.querySelectorAll(x)].filter(b => !b.hidden).map(b => b.getAttribute("aria-label") || b.textContent), sel);
    await owner.locator(`.vf-people .vf-person[data-name="Gus"]`).click();
    await until(owner, () => !document.querySelector(".vf-pcard").hidden && !!document.querySelector(".vf-pcard .vf-pc-acts"));
    const card = await acts(owner, ".vf-pcard .vf-pc-acts button");
    await owner.getByRole("button", { name: "Close Gus's card", exact: true }).click();
    ok("the pinned card has the one x, named for it, and it closes the card", await until(owner, () => document.querySelector(".vf-pcard").hidden));
    await owner.click(".vf-seg-btn:has-text('Host')");
    await until(owner, () => [...document.querySelectorAll(".vf-hperson")].some(li => li.textContent.includes("Gus")));
    const row = await owner.evaluate(() => [...[...document.querySelectorAll(".vf-hperson")].find(li => li.textContent.includes("Gus")).querySelectorAll(".vf-hp-acts button")].filter(b => !b.hidden).map(b => b.getAttribute("aria-label") || b.textContent));
    // F16: one device and browser source (core.js): the row's device badge names the browser in words.
    await gus.evaluate(() => window.Core.answerCiting("Q1", "Beside the total.", []));
    ok("Gus's device badge in the Host view reads \"On a computer, Chrome\"", await until(owner, () => [...document.querySelectorAll(".vf-hperson")].some(li => li.textContent.includes("Gus")
      && /^On a computer, Chrome, 1440×900, in Focus$/.test(li.querySelector(".vf-ctx")?.getAttribute("aria-label") || "")), null, 10000),
      await owner.evaluate(() => [...document.querySelectorAll(".vf-hperson .vf-ctx")].map(e => e.getAttribute("aria-label")).join(" | ")));
    // F5: the host row's list (the most complete), by accessible name.
    const PERSON = ["View everything Gus did", "Leader: Gus", "Trusted: Gus", "Merge Gus into someone", "Remove Gus"];
    ok("the Host view row offers View all, Leader, Trusted, Merge and Remove for Gus", JSON.stringify(row) === JSON.stringify(PERSON), JSON.stringify(row));
    ok("  and Gus's card offers the same five, in the same words", JSON.stringify(card) === JSON.stringify(PERSON), JSON.stringify(card));

    // ---------- F6: one set of proposal actions and toasts, in Proposed and the Inbox ----------
    const IDEA = "Show the delivery date beside the total";
    await gus.evaluate(t => window.Core.idea(t), IDEA);
    await owner.keyboard.press("Escape");
    await owner.locator(".vf-proprow", { hasText: "Proposed" }).click();
    const propRow = () => owner.locator(".vf-panel:not([hidden]) .vf-pitem", { hasText: IDEA });
    await propRow().waitFor({ timeout: 10000 });
    const inPanel = (await acts(owner, ".vf-panel:not([hidden]) .vf-pitem .vf-acts button")).sort();
    await owner.keyboard.press("Escape");
    await owner.click(".vf-bell");
    await until(owner, t => [...document.querySelectorAll(".vf-ibneeds .vf-ibq > li")].some(li => li.textContent.includes(t)), IDEA, 10000);
    const inInbox = (await owner.evaluate(t => [...[...document.querySelectorAll(".vf-ibneeds .vf-ibq > li")].find(li => li.textContent.includes(t)).querySelectorAll(".vf-acts button")]
      .filter(b => !b.hidden && !b.matches(".vf-ibgo")).map(b => b.textContent), IDEA)).sort();
    ok("a new proposal has the same actions in Proposed and in the Inbox: Make it a question, Later, Park", JSON.stringify(inPanel) === JSON.stringify(["Later", "Make it a question", "Park"]) && JSON.stringify(inInbox) === JSON.stringify(inPanel), JSON.stringify({ inPanel, inInbox }));
    await owner.keyboard.press("Escape");
    await owner.evaluate(() => { window.__toasts = []; new MutationObserver(() => { const t = document.querySelector(".vf-toast span")?.textContent; if (t) window.__toasts.push(t); }).observe(document.querySelector(".vf-toast"), { childList: true, characterData: true, subtree: true }); });
    await owner.evaluate(t => window.Core.proposal(window.Core.state.ideas.find(i => i.text === t).id, "park"), IDEA);
    await owner.locator(".vf-proprow", { hasText: "Proposed" }).click();
    await owner.locator(".vf-panel:not([hidden]) .vf-seg-btn", { hasText: "Parked" }).click();
    await propRow().getByRole("button", { name: "Back to Proposed" }).click();
    ok("Back to Proposed in Proposed says what Later's does: \"Back in Proposed.\"", await until(owner, () => window.__toasts.includes("Back in Proposed.")), JSON.stringify(await owner.evaluate(() => window.__toasts)));
    await owner.keyboard.press("Escape");

    // ---------- F7 and F10: one set of request actions; Decline asks first, Mark failed says the same everywhere ----------
    const ASK = "Which payment providers support this?";
    await gus.waitForTimeout(1100);
    await gus.evaluate(t => window.Core.request("Q1", "ask", t), ASK);
    await owner.click(".vf-seg-btn:has-text('Host')");
    const qRow = () => owner.locator(".vf-queue > li", { hasText: ASK });
    await qRow().waitFor({ timeout: 10000 });
    await qRow().getByRole("button", { name: "Decline", exact: true }).click();
    ok("declining a request asks first: it is hard to undo and Gus sees it", await until(owner, () => /Decline this request\?/.test(document.querySelector("dialog.vf-cdlg[open]")?.textContent || "")));
    await owner.keyboard.press("Escape");
    ok("  Escape keeps it waiting", await until(owner, () => !document.querySelector("dialog.vf-cdlg[open]")) && await owner.evaluate(t => window.Core.state.requests.find(r => r.text === t).status === "pending", ASK));
    await qRow().getByRole("button", { name: "Run", exact: true }).click();
    await until(owner, t => window.Core.state.requests.find(r => r.text === t)?.status === "running", ASK, 10000);
    await owner.evaluate(() => { window.__toasts = []; });
    await qRow().getByRole("button", { name: "Mark failed", exact: true }).click();
    ok("Mark failed in the Host queue says \"Marked failed. The requester sees it.\"", await until(owner, () => window.__toasts.includes("Marked failed. The requester sees it.")), JSON.stringify(await owner.evaluate(() => window.__toasts)));

    // ---------- F10: Send round asks through the one confirm dialog while questions are open ----------
    await owner.keyboard.press("Escape");
    await owner.locator(".vf-seg-btn", { hasText: "Focus" }).click();
    const sends = [];
    owner.on("request", r => { if (new URL(r.url()).pathname === "/api/round/send") sends.push(r.method()); });
    await owner.locator(".vf-round-cur .vf-send").click();
    ok("Send round with Q1 still open asks in the confirm dialog, Keep answering first", await until(owner, () => {
      const d = document.querySelector("dialog.vf-cdlg[open]"); return !!d && /Send round 1 to Claude\?/.test(d.textContent) && /1 question is still open in round 1/.test(d.textContent) && document.activeElement?.textContent === "Keep answering";
    }), await owner.evaluate(() => document.querySelector("dialog.vf-cdlg[open]")?.textContent || "no dialog"));
    await owner.keyboard.press("Escape");
    await until(owner, () => !document.querySelector("dialog.vf-cdlg[open]"));
    await owner.waitForTimeout(1500); // a poll or two: a send made anyway would have gone out by now
    ok("  Escape sends nothing: no round send request went out", sends.length === 0, JSON.stringify(sends));

    // ---------- the message menu and React open beside what opened them (chat and a Discussion comment) ----------
    const beside = (page, menuSel, btnSel) => page.evaluate(([m, b]) => {
      const r = document.querySelector(m).getBoundingClientRect(), a = [...document.querySelectorAll(b)].find(x => x.getAttribute("aria-expanded") === "true" || x === document.activeElement)?.getBoundingClientRect()
        || document.querySelector(b).getBoundingClientRect();
      const gapX = Math.max(0, r.left - a.right, a.left - r.right), gapY = Math.max(0, r.top - a.bottom, a.top - r.bottom);
      return { ok: gapX < 24 && gapY < 24, menu: [r.left, r.top].map(Math.round), btn: [a.left, a.top].map(Math.round) };
    }, [menuSel, btnSel]);
    await owner.keyboard.press("Escape");
    await owner.evaluate(() => window.Core.saveSettings({ chat: true }));
    await gus.waitForTimeout(1100);
    await gus.evaluate(() => window.Core.chat("Where does the total go on phones?"));
    await owner.click(".vf-fab");
    const chatMsg = owner.locator(".vf-msg", { hasText: "Where does the total go on phones?" });
    await chatMsg.waitFor({ timeout: 10000 });
    await chatMsg.hover();
    await chatMsg.locator(".vf-msgmore").click();
    await until(owner, () => !document.querySelector(".vf-msgmenu").hidden);
    let b = await beside(owner, ".vf-msgmenu", ".vf-msg .vf-msgmore");
    ok("a chat message's ⋯ menu opens beside its ⋯ button", b.ok, JSON.stringify(b));
    await owner.keyboard.press("Escape");
    await chatMsg.hover();
    await chatMsg.locator(".vf-mreact-add").click();
    await until(owner, () => !document.querySelector(".vf-reactpop").hidden);
    b = await beside(owner, ".vf-reactpop", ".vf-msg .vf-mreact-add");
    ok("  and React opens beside its button", b.ok, JSON.stringify(b));
    await owner.keyboard.press("Escape");
    await owner.click(".vf-fab");
    await gus.waitForTimeout(1100);
    await owner.click(".vf-disc-head");
    await owner.fill(".vf-disc-ta", "A comment to open the menu on");
    await owner.click(".vf-disc-post");
    const com = owner.locator(".vf-disc-list > .vf-cm", { hasText: "A comment to open the menu on" });
    await com.waitFor({ timeout: 10000 });
    await com.locator(".vf-cm-more").click();
    await until(owner, () => !document.querySelector(".vf-msgmenu").hidden);
    b = await beside(owner, ".vf-msgmenu", ".vf-cm .vf-cm-more");
    ok("a Discussion comment's ⋯ menu opens beside its ⋯ button", b.ok, JSON.stringify(b));
    await owner.keyboard.press("Escape");
    await com.locator(".vf-cm-react").click();
    await until(owner, () => !document.querySelector(".vf-reactpop").hidden);
    b = await beside(owner, ".vf-reactpop", ".vf-cm .vf-cm-react");
    ok("  and its React opens beside its button", b.ok, JSON.stringify(b));
    await owner.keyboard.press("Escape");

    // ---------- read-only: once the session ends, a guest's menu offers no Ask Claude about this (the server refuses it) ----------
    await owner.evaluate(() => window.Core.endSession(true));
    await until(gus, () => window.Core.state.ended === true, null, 10000);
    const roMenu = async (open) => { await open(); await until(gus, () => !document.querySelector(".vf-msgmenu").hidden);
      const m = await gus.evaluate(() => [...document.querySelectorAll(".vf-msgmenu [role=menuitem]")].filter(x => !x.hidden).map(x => x.textContent.trim())); await gus.keyboard.press("Escape"); return m; };
    const roChat = await roMenu(async () => { await gus.click(".vf-fab"); const m = gus.locator(".vf-msg", { hasText: "Where does the total go on phones?" }); await m.hover(); await m.locator(".vf-msgmore").click(); });
    await gus.click(".vf-fab");
    await until(gus, () => document.querySelector(".vf-center").dataset.mode === "tree");
    // An ended session opens guests on the Tree; View options brings back the view switcher, and Focus the Discussion.
    if (!(await gus.locator(".vf-seg-btn", { hasText: "Focus" }).isVisible())) await gus.click(".vf-viewopts");
    await gus.locator(".vf-seg-btn", { hasText: "Focus" }).click();
    await until(gus, () => document.querySelector(".vf-center").dataset.mode === "focus");
    await gus.evaluate(() => { const h = document.querySelector(".vf-disc-head"); if (h.getAttribute("aria-expanded") !== "true") h.click(); });
    const roCm = await roMenu(() => gus.locator(".vf-disc-list > .vf-cm", { hasText: "A comment to open the menu on" }).locator(".vf-cm-more").click());
    ok("once the session ends, a guest's chat menu has no Reply or Ask Claude about this", !roChat.includes("Ask Claude about this") && !roChat.includes("Reply") && roChat.includes("Copy"), JSON.stringify(roChat));
    ok("  nor does a Discussion comment's", !roCm.includes("Ask Claude about this") && !roCm.includes("Reply") && roCm.includes("Copy"), JSON.stringify(roCm));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
