#!/usr/bin/env node
// Pictures on a question and the shared display parts, against `share.sh ensure-running` with the fake cloudflared:
// a picture pasted into the answer box shows in its uploader's file row as the thumbnail her browser made; received but
// carried by nothing, it shows under its question to the owner (with Approve picture) and its uploader (with Remove),
// and to another guest only once approved; the round-ready note names "You" by person, not by name, so a second
// person of the same name reads the first one's initial; an avatar on a proposal's who line is focusable and opens the
// person card; and the unread dot, inline link button and counter each use their one class.
//   node plugins/planning/shared/tests/ui_pictures_display.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the follow-ups (32, B5, B7, F14, F15) and the texts this suite writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, snap, joinAs } = require("./browser_harness");

const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "gather", format: { kind: "text" } });
const DESK = { context: { viewport: { width: 1440, height: 900 } } };
const IDEA = "Ask which cart default people expect.";

/** Paste a 640x400 PNG made in the page into `sel`, as a ClipboardEvent whose clipboardData holds an image File. */
const paste = (page, sel) => page.evaluate(async s => {
  const c = document.createElement("canvas"); c.width = 640; c.height = 400;
  const g = c.getContext("2d"); g.fillStyle = "#27a"; g.fillRect(0, 0, 640, 400);
  const dt = new DataTransfer(); dt.items.add(new File([await new Promise(r => c.toBlob(r, "image/png"))], "clip.png", { type: "image/png" }));
  const el = document.querySelector(s); el.focus();
  el.dispatchEvent(new ClipboardEvent("paste", { clipboardData: dt, bubbles: true, cancelable: true }));
}, sel);
/** What the question's picture strip shows: hidden or not, and each tile's picture kind and buttons. */
const strip = page => page.evaluate(() => {
  const box = document.querySelector(".vf-qpics");
  return { hidden: !box || box.hidden, tiles: [...(box?.querySelectorAll(".vf-ref") || [])].map(li => ({
    img: (li.querySelector(".vf-uppic img")?.getAttribute("src") || "").slice(0, 11),
    approve: !!li.querySelector(".vf-upapprove"), remove: !!li.querySelector(".vf-upremove") })) };
});

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_pictures_display.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_pictures_display"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("pictures-display");
    s.apply(A.dir, [{ op: "set-title", title: "Checkout" }, { op: "open-round", questions: [q("Q1", "Where should the order summary sit?"), q("Q2", "What should the cart remember?")] }]);
    const owner = await rec.open(A.ownerUrl, DESK);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    await owner.evaluate(() => window.Core.saveSettings({ uploads: true, names: "initials" }));
    const ann = await rec.open(A.localUrl, DESK);
    const annPid = await joinAs(ann, "Ann");
    const ann2 = await rec.open(A.localUrl, DESK);
    const ann2Pid = await joinAs(ann2, "Ann");
    const bo = await rec.open(A.localUrl, DESK);
    await joinAs(bo, "Bo");
    await until(ann, () => window.Core.state.settings.uploads === true);

    // ---------- F15: one class each ----------
    ok("the rail's new dot, the counters and inline link buttons use one class each", await bo.evaluate(() => !document.querySelector(".vf-newdot, .vf-linkbtn, .vf-catchup-go, .vf-rep-count")
      && !!document.querySelector(".vf-qside .vf-ndot") && !!document.querySelector(".vf-reportpop .vf-count-txt")));

    // ---------- B5: the uploader's row shows the thumbnail her browser made ----------
    await paste(ann, "#vf-answer");
    const uid = await until(ann, () => (window.Core.snapshot().myUploads || []).length === 1, null, 10000) && (await snap(ann)).myUploads[0].id;
    ok("the pasted picture's row shows the thumbnail made in her browser while it waits for the host", await until(ann, () => [...document.querySelectorAll(".vf-upstrip .vf-uprow")]
      .some(r => /Waiting for the host/.test(r.textContent) && r.querySelector(".vf-upthumb:not([hidden]) img")?.getAttribute("src")?.startsWith("data:image/")), null, 10000));
    await owner.evaluate(id => window.Core.uploadAct(id, "accept"), uid);
    ok("accepted, it arrives", await until(ann, id => window.Core.snapshot().myUploads.some(u => u.id === id && u.status.kind === "done"), uid, 20000));

    // ---------- 32: received, carried by nothing, it shows under Q1 by the approval rule ----------
    ok("the owner sees it under the question, with Approve picture and Remove", await until(owner, () => {
      const box = document.querySelector(".vf-qpics");
      return !!box && !box.hidden && [...box.querySelectorAll(".vf-ref")].some(li => li.querySelector(".vf-uppic img")?.getAttribute("src")?.startsWith("data:image/")
        && !!li.querySelector(".vf-upapprove") && !!li.querySelector(".vf-upremove"));
    }, null, 10000), JSON.stringify(await strip(owner)));
    ok("its uploader sees it there with Remove and no Approve", await until(ann, () => [...document.querySelectorAll(".vf-qpics .vf-ref")]
      .some(li => li.querySelector(".vf-uppic img")?.getAttribute("src")?.startsWith("data:image/") && !!li.querySelector(".vf-upremove") && !li.querySelector(".vf-upapprove")), null, 10000),
      JSON.stringify(await strip(ann)));
    ok("another guest sees nothing of it before the owner approves", (await strip(bo)).hidden && !(uid in ((await snap(bo)).files || {})));
    await owner.locator(".vf-qpics .vf-upapprove").click();
    ok("approved, the other guest sees it under the question", await until(bo, () => [...document.querySelectorAll(".vf-qpics:not([hidden]) .vf-ref")]
      .some(li => li.querySelector(".vf-uppic img")?.getAttribute("src")?.startsWith("data:image/") && !li.querySelector(".vf-upremove")), null, 10000), JSON.stringify(await strip(bo)));
    ok("and the owner's Approve picture goes", await until(owner, () => !document.querySelector(".vf-qpics .vf-upapprove")));
    await bo.locator(".vf-qpics .vf-uppic").click();
    ok("its tile opens the viewer", await until(bo, () => { const i = document.querySelector(".vf-lb-img"); return !!i?.offsetParent && i.getAttribute("src").startsWith("data:image/"); }));
    await bo.keyboard.press("Escape");
    await ann.locator(".vf-qpics .vf-upremove").click();
    await ann.locator("dialog[open] button", { hasText: "Remove picture" }).click();
    ok("the uploader's Remove takes it away for everyone", await until(bo, () => document.querySelector(".vf-qpics").hidden, null, 10000));

    // ---------- B7: "You marked this round ready" goes by person, not name ----------
    for (const p of [annPid, ann2Pid]) await owner.evaluate(x => window.Core.setLeader(x, true), p);
    await until(ann, () => window.Core.snapshot().me.role === "leader");
    await ann.evaluate(() => window.Core.markReady(true));
    ok("the one who marked it reads \"You marked this round ready just now.\"", await until(ann, () => document.querySelector(".vf-ready")?.textContent === "You marked this round ready just now."),
      await ann.evaluate(() => document.querySelector(".vf-ready")?.textContent));
    ok("another person of the same name reads her initial", await until(ann2, () => document.querySelector(".vf-ready")?.textContent === "A marked this round ready just now."),
      await ann2.evaluate(() => document.querySelector(".vf-ready")?.textContent));

    // ---------- F14: a who line's avatar is focusable and opens the person card ----------
    await bo.evaluate(t => window.Core.idea(t), IDEA);
    await owner.locator(".vf-proprow", { hasText: "Proposed" }).click();
    const item = owner.locator(".vf-panel .vf-pitem", { hasText: IDEA });
    ok("the proposal's who line names Bo (as \"B\": names show as initials) with his avatar", await item.waitFor({ timeout: 10000 }).then(() => item.locator(".vf-pfrom").textContent()).then(t => t.startsWith("BB"), () => false));
    const avatar = item.locator(".vf-pfrom .core-avatar[data-pid]");
    ok("  the avatar is focusable, as a button", (await avatar.getAttribute("tabindex")) === "0" && (await avatar.getAttribute("role")) === "button");
    await avatar.focus();
    await owner.keyboard.press("Enter");
    ok("  and opens Bo's person card", await until(owner, () => { const c = document.querySelector(".vf-pcard"); return !!c && !c.hidden && c.querySelector(".vf-pc-name")?.textContent === "B"; }));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource|Failed to fetch|ERR_CONNECTION/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
