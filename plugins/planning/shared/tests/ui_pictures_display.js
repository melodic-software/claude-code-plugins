#!/usr/bin/env node
// Pictures on a question and the shared display parts, against `share.sh ensure-running` with the fake cloudflared:
// a picture pasted into the answer box shows once, as its tile in the answer, with the thumbnail her browser made; a draft's
// picture shows under no question and reads back to nobody else, and the x on its chip removes it for good; a picture
// from before attachments that nothing carried shows under its question to the owner (with Approve picture) and its
// uploader (with Remove), and to another guest only once approved; the round-ready note names "You" by person, not by name, so a second
// person of the same name reads the first one's initial; an avatar on a proposal's who line is focusable and opens the
// person card; the unread dot, inline link button and counter each use their one class, at the sizes they had; and a
// picture pasted into an empty answer box and sent is an answer, its card showing the picture; locked, it shows in the
// locked view to the owner, and to a guest once approved.
//   node plugins/planning/shared/tests/ui_pictures_display.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the follow-ups (32, B5, B7, F14, F15) and the texts this suite writes, never from the page.
"use strict";
const fs = require("fs"), path = require("path");
const { loadPlaywright, suite, recorder, until, snap, joinAs } = require("./browser_harness");

const q = (id, text, purpose = "gather") => ({ id, text, alternatives: [], dependsOn: [], purpose, format: { kind: "text" } });
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
/** The HTTP status reading a picture back gives this page: 200, or the refusal's (404). */
const readBack = (page, id) => page.evaluate(x => window.Core.uploadImage(x).then(() => 200, e => e.status || 0), id);
/** The id of the newest upload this page offered, once the host has it whole. */
const pasted = async (page, before) => (await until(page, n => (window.Core.snapshot().myUploads || []).length > n, before, 10000))
  && (await snap(page)).myUploads.at(-1).id;

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_pictures_display.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_pictures_display"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("pictures-display");
    s.apply(A.dir, [{ op: "set-title", title: "Checkout" }, { op: "open-round", questions: [q("Q1", "Where should the order summary sit?"), q("Q2", "What should the cart remember?"), q("Q3", "Which box art goes on the shelf?", "decide")] }]);
    let owner = await rec.open(A.ownerUrl, DESK);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    await owner.evaluate(() => window.Core.saveSettings({ uploads: true, names: "initials" }));
    let ann = await rec.open(A.localUrl, DESK);
    const annPid = await joinAs(ann, "Ann");
    await until(ann, () => window.Core.state.settings.uploads === true);

    // ---------- a picture from before attachments: received on Q1 under main, nothing carries it ----------
    await paste(ann, "#vf-answer");
    const old = await pasted(ann, 0);
    await owner.evaluate(id => window.Core.uploadAct(id, "accept"), old);
    await until(ann, id => window.Core.snapshot().myUploads.some(u => u.id === id && u.status.kind === "done"), old, 20000);
    const port = new URL(A.localUrl).port;
    s.share(A.dir, "stop");
    const file = path.join(A.dir, "state.json"), st = JSON.parse(fs.readFileSync(file, "utf8"));
    // unmarked, neither a draft nor carried, as an offer from before attachments is in the live state
    for (const u of st.uploads) if (u.id === old) { delete u.draft; delete u.carried; }
    fs.writeFileSync(file, JSON.stringify(st));
    s.share(A.dir, "ensure-running", "--guest-port", port);
    const reopen = async (page, url) => { const p = await rec.openIn(page.context(), url); await until(p, () => !!window.Core.snapshot()?.me); await page.close(); return p; };
    owner = await reopen(owner, A.ownerUrl);
    ann = await reopen(ann, A.localUrl);
    const ann2 = await rec.open(A.localUrl, DESK);
    const ann2Pid = await joinAs(ann2, "Ann");
    const bo = await rec.open(A.localUrl, DESK);
    await joinAs(bo, "Bo");

    // ---------- F15: one class each, the dots at the sizes they had ----------
    ok("the rail's new dot, the counters and inline link buttons use one class each", await bo.evaluate(() => !document.querySelector(".vf-newdot, .vf-linkbtn, .vf-catchup-go, .vf-rep-count")
      && !!document.querySelector(".vf-qside .vf-ndot") && !!document.querySelector(".vf-reportpop .vf-count-txt")));
    const dot = (page, cls, dotCls = "vf-ndot") => page.evaluate(([c, dc]) => {
      const host = document.createElement(c.split(" ")[0]); host.className = c.split(" ").slice(1).join(" ");
      const d = document.createElement("span"); d.className = dc; host.append(d); document.querySelector(".app").append(host);
      const cs = getComputedStyle(d), out = `${cs.width} ${cs.marginBlockStart}`; host.remove(); return out;
    }, [cls, dotCls]);
    const dots = { card: await dot(bo, "div vf-card-head"), rail: await dot(bo, "span vf-qside"), note: await dot(bo, "button vf-nitem"), inbox: await dot(bo, "button vf-ixitem"),
      comment: await dot(bo, "div vf-cm-head", "vf-ndot vf-cm-new") };
    ok("an answer card's dot is 7 px, a question row's 7 px 2 px down, a notification's and a Discussion comment's 8 px 6 px down, an Inbox row's 8 px",
      dots.card === "7px 0px" && dots.rail === "7px 2px" && dots.note === "8px 6px" && dots.comment === "8px 6px" && dots.inbox === "8px 0px", JSON.stringify(dots));

    // ---------- B5: the uploader's row shows the thumbnail her browser made ----------
    await paste(ann, "#vf-answer");
    const uid = await pasted(ann, 1);
    ok("the pasted picture's tile shows the thumbnail made in her browser while it waits for the host", await until(ann, () => [...document.querySelectorAll(".vf-composer .vf-attdraft .vf-ref")]
      .some(r => /Waiting for the host/.test(r.textContent) && r.querySelector(".vf-uppic-wait img:not([hidden])")?.getAttribute("src")?.startsWith("data:image/")), null, 10000));
    ok("  and shows once: no file row repeats it under the answer (sweep S17)", await ann.evaluate(() => ![...document.querySelectorAll(".vf-upstrip .vf-uprow")].some(r => /Waiting for the host/.test(r.textContent))),
      await ann.evaluate(() => JSON.stringify({ rows: [...document.querySelectorAll(".vf-upstrip .vf-uprow")].map(r => r.textContent), draft: window.Core.snapshot().myUploads?.map(u => [u.id, u.status?.kind, u.file]) })));
    await owner.evaluate(id => window.Core.uploadAct(id, "accept"), uid);
    ok("accepted, it arrives", await until(ann, id => window.Core.snapshot().myUploads.some(u => u.id === id && u.status.kind === "done"), uid, 20000));

    // ---------- a draft's picture is no question's: the owner's own reads back to nobody else ----------
    await paste(owner, "#vf-answer");
    const own = await pasted(owner, 0);
    await until(owner, id => window.Core.snapshot().myUploads.some(u => u.id === id && u.status.kind === "done"), own, 20000);
    await bo.waitForTimeout(2500); // a few polls past its arrival
    ok("the owner's unsent picture shows under no question for another guest", !((await snap(bo)).questionPics?.Q1 || []).includes(own) && !(own in ((await snap(bo)).files || {})),
      JSON.stringify((await snap(bo)).questionPics));
    ok("  nor reads back for him", (await readBack(bo, own)) === 404);
    ok("  nor does Ann's draft show to the owner under the question", !((await snap(owner)).questionPics?.Q1 || []).includes(uid), JSON.stringify((await snap(owner)).questionPics));
    await ann.locator(".vf-composer .vf-attdraft .vf-ref-x").last().click(); // her newest chip
    ok("x on her draft chip removes the picture", await until(ann, id => window.Core.snapshot().myUploads.find(u => u.id === id)?.status.kind === "removed", uid, 10000),
      JSON.stringify((await snap(ann)).myUploads.map(u => [u.id, u.status.kind])));
    ok("  so it reads back to nobody, the owner included", (await readBack(owner, uid)) === 404 && (await readBack(ann, uid)) === 404);
    ok("  and no strip under the question holds it for the owner", !((await snap(owner)).questionPics?.Q1 || []).includes(uid));

    // ---------- 32: received, carried by nothing, it shows under Q1 by the approval rule ----------
    ok("the owner sees the old picture under the question, with Approve picture and Remove", await until(owner, () => {
      const box = document.querySelector(".vf-qpics");
      return !!box && !box.hidden && [...box.querySelectorAll(".vf-ref")].some(li => li.querySelector(".vf-uppic img")?.getAttribute("src")?.startsWith("data:image/")
        && !!li.querySelector(".vf-upapprove") && !!li.querySelector(".vf-upremove"));
    }, null, 10000), JSON.stringify(await strip(owner)));
    ok("  and only that one", (await snap(owner)).questionPics?.Q1?.join() === old, JSON.stringify((await snap(owner)).questionPics));
    ok("its uploader sees it there with Remove and no Approve", await until(ann, () => [...document.querySelectorAll(".vf-qpics .vf-ref")]
      .some(li => li.querySelector(".vf-uppic img")?.getAttribute("src")?.startsWith("data:image/") && !!li.querySelector(".vf-upremove") && !li.querySelector(".vf-upapprove")), null, 10000),
      JSON.stringify(await strip(ann)));
    ok("another guest sees nothing of it before the owner approves", (await strip(bo)).hidden && !(old in ((await snap(bo)).files || {})) && (await readBack(bo, old)) === 404);
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

    // ---------- a picture alone answers a text question: Bo pastes one into his empty box and presses Send ----------
    await bo.fill("#vf-answer", "");
    await paste(bo, "#vf-answer");
    const boPic = await pasted(bo, 0);
    await owner.evaluate(id => window.Core.uploadAct(id, "accept"), boPic);
    ok("Bo's pasted picture arrives with his answer box still empty", await until(bo, id => window.Core.snapshot().myUploads.some(u => u.id === id && u.status.kind === "done"), boPic, 20000)
      && (await bo.inputValue("#vf-answer")) === "");
    await bo.locator(".vf-composer .vf-sendbtn").click();
    ok("Send saves his card holding the picture and no text", await until(bo, id => window.Core.snapshot().cards.Q1?.some(c => c.kind === "person" && c.pid === window.Core.snapshot().me.pid
      && c.text === "" && (c.attachments || []).includes(id)), boPic, 10000), JSON.stringify((await snap(bo)).cards.Q1));
    ok("  and his card shows the picture", await until(bo, () => !!document.querySelector(".vf-card.vf-mine .vf-attlist .vf-uppic img")?.getAttribute("src")?.startsWith("data:image/"), null, 10000));

    // ---------- a locked picture-only answer shows its picture in the locked view, by the approval rule ----------
    await bo.evaluate(id => window.Core.answerCiting("Q3", "", [], { attachments: [id] }), boPic);
    await owner.evaluate(pid => window.Core.lock("Q3", `p:${pid}`), (await snap(bo)).me.pid);
    const lockPic = page => until(page, () => !!document.querySelector(".vf-lock:not([hidden]) .vf-attlist .vf-uppic img")?.getAttribute("src")?.startsWith("data:image/"), null, 10000);
    for (const page of [owner, ann]) { await page.keyboard.press("Escape"); await page.locator(".vf-q", { hasText: "Which box art" }).first().click(); }
    ok("the owner sees the locked picture-only answer's picture in the locked view", await lockPic(owner),
      await owner.evaluate(() => document.querySelector(".vf-lock")?.outerHTML.slice(0, 300)));
    ok("  a guest sees no picture there before the owner approves it", !(await ann.evaluate(() => !!document.querySelector(".vf-lock:not([hidden]) .vf-attlist .vf-uppic img"))));
    await owner.evaluate(id => window.Core.uploadAct(id, "approve"), boPic);
    ok("  and once approved, the guest sees it in the locked view", await lockPic(ann), await ann.evaluate(() => document.querySelector(".vf-lock")?.outerHTML.slice(0, 300)));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource|Failed to fetch|ERR_CONNECTION/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
