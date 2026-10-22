#!/usr/bin/env node
// Profile pictures in a real browser, against `share.sh ensure-running` with the fake cloudflared: a guest picks a
// picture on their person card; once it arrives they see it on their own avatar at once, and another guest still sees
// their initials on their color until the owner presses Approve picture on the guest's card; then everyone sees it as a
// circle crop. Turning Show names off hides it for everyone and brings it back when names show again; removed, the
// initials show again.
//   node plugins/planning/shared/tests/ui_avatars.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the owner's decisions (approval as for received pictures, PNG, JPEG or WebP at most
// 256 KB, a circle crop, initials as the fallback, hidden with the names) and the texts this suite writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, snap, joinAs, png } = require("./browser_harness");

const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "gather", format: { kind: "text" } });

/** What one page's header shows for a person's avatar: the picture's data: URL kind (or "" for none), its crop, and
 *  the initials under it. */
const headAvatar = (page, pid) => page.evaluate(p => {
  const a = document.querySelector(`.vf-people .vf-person[data-pid="${p}"] .core-avatar`);
  const img = a?.querySelector(":scope > img.core-avatar-img"), cs = img && getComputedStyle(img);
  return { found: !!a, kind: (img?.getAttribute("src") || "").match(/^data:(image\/[a-z]+);/)?.[1] || "", text: a?.textContent || "",
    round: cs ? cs.borderTopLeftRadius === "50%" && cs.objectFit === "cover" && cs.width === getComputedStyle(a).width : false };
}, pid);
const hasPic = (page, pid) => until(page, p => !!document.querySelector(`.vf-people .vf-person[data-pid="${p}"] .core-avatar > img.core-avatar-img[src^="data:image/"]`), pid, 15000);
const noPic = (page, pid) => until(page, p => { const a = document.querySelector(`.vf-people .vf-person[data-pid="${p}"] .core-avatar`); return !!a && !a.querySelector("img"); }, pid, 15000);

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_avatars.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_avatars"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("avatars");
    s.apply(A.dir, [{ op: "set-title", title: "Checkout" }, { op: "open-round", questions: [q("Q1", "Where should the order summary sit?")] }]);
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    await owner.evaluate(() => window.Core.saveSettings({ uploads: true, showNames: true }));
    const ann = await rec.open(A.localUrl), annPid = await joinAs(ann, "Ann");
    const bo = await rec.open(A.localUrl);
    await joinAs(bo, "Bo");
    await until(ann, () => window.Core.state.settings.uploads === true);
    await until(bo, p => !!document.querySelector(`.vf-people .vf-person[data-pid="${p}"]`), annPid, 15000);

    // ---------- Ann picks her picture on her own card ----------
    await ann.click(`.vf-people .vf-person[data-pid="${annPid}"]`);
    await ann.waitForSelector(".vf-pcard .vf-pavatar input[type=file]", { state: "attached" });
    ok("her card offers Choose a picture", (await ann.textContent(".vf-pcard .vf-pavatar button")) === "Choose a picture");
    await ann.setInputFiles(".vf-pcard .vf-pavatar input[type=file]", { name: "me.png", mimeType: "image/png", buffer: png(320, 200, [40, 120]) });
    ok("her offer is marked as a profile picture", await until(ann, () => (window.Core.snapshot().myUploads || []).some(u => u.avatar), null, 10000));
    const uid = (await snap(ann)).myUploads.find(u => u.avatar).id;
    await owner.evaluate(id => window.Core.uploadAct(id, "accept"), uid);
    ok("it arrives", await until(ann, id => window.Core.snapshot().myUploads.some(u => u.id === id && u.status.kind === "done"), uid, 20000));
    const sent = (await snap(ann)).myUploads.find(u => u.id === uid);
    ok("  redrawn small: at most 256 KB", sent.size <= 256 * 1024, sent.size);

    // ---------- pending: Ann sees it, Bo sees her initials ----------
    ok("Ann sees her own picture at once", await hasPic(ann, annPid));
    ok("  as a circle crop", (await headAvatar(ann, annPid)).round, JSON.stringify(await headAvatar(ann, annPid)));
    await ann.waitForSelector(".vf-pcard .vf-pavatar .vf-pop-note");
    ok("  and her card says only she and the host see it until approved", (await ann.textContent(".vf-pcard .vf-pavatar")).includes("Only you and the host see it until the host approves it."));
    const boBefore = await headAvatar(bo, annPid);
    ok("Bo sees Ann's initials on her color while it waits", boBefore.found && boBefore.kind === "" && boBefore.text === "A", JSON.stringify(boBefore));

    // ---------- the owner approves it on Ann's card ----------
    await owner.click(`.vf-people .vf-person[data-pid="${annPid}"]`);
    await owner.waitForSelector(".vf-pcard .vf-pavatar .vf-upapprove");
    ok("the owner's card for Ann shows the picture waiting", await until(owner, () => /^data:image\//.test(document.querySelector(".vf-pcard .vf-pavatar-prev")?.getAttribute("src") || ""), null, 10000));
    await owner.click(".vf-pcard .vf-pavatar .vf-upapprove");
    ok("once approved, Bo sees Ann's picture", await hasPic(bo, annPid));
    const boAfter = await headAvatar(bo, annPid);
    ok("  a PNG, JPEG or WebP, as a circle crop", ["image/png", "image/jpeg", "image/webp"].includes(boAfter.kind) && boAfter.round, JSON.stringify(boAfter));

    // ---------- Show names off hides it for everyone ----------
    await owner.evaluate(() => window.Core.saveSettings({ showNames: false }));
    ok("with Show names off Bo sees no picture", await noPic(bo, annPid));
    ok("  and neither does the owner", await noPic(owner, annPid));
    ok("  and neither does Ann", await noPic(ann, annPid));
    await owner.evaluate(() => window.Core.saveSettings({ showNames: true }));
    ok("with Show names on again Bo sees it again", await hasPic(bo, annPid));

    // ---------- removed: the initials come back ----------
    await ann.evaluate(id => window.Core.uploadAct(id, "remove"), uid);
    ok("removed, Bo sees Ann's initials again", await noPic(bo, annPid) && (await headAvatar(bo, annPid)).text === "A");
    ok("  and so does Ann", await noPic(ann, annPid));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
