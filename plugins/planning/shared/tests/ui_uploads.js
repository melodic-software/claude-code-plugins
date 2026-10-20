#!/usr/bin/env node
// Uploads (Phase 9) in real browsers, against `share.sh ensure-running` with the fake cloudflared: while Uploads is
// off no upload control shows; on, a guest on a 390x844 phone offers a file from the one attach picker (C36), which
// waits in her browser (IndexedDB) until the desktop owner accepts it in the Host queue; the browser then sends it in
// 8 MiB pieces, and a dropped piece plus a reload resumes from the server's count without sending a piece twice; the
// received file is byte for byte what she offered; she attaches it to her pick from the picker's list (C44) and a
// desktop guest sees it on her card; a file the owner declines is deleted from that guest's browser and shows "Not
// accepted" (AC 21); Uploads off hides the control again.
//   node plugins/planning/shared/tests/ui_uploads.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the Design's Upload contract and rules (8 MiB pieces, resume, whole-file sha256), the
// Brief's upload criteria (AC 21, AC 40), C36 and C44, and the bytes and texts this suite makes, never from the page.
"use strict";
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { loadPlaywright, suite, recorder, until, snap, joinAs } = require("./browser_harness");

const PHONE = { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 };
const MIB = 1024 * 1024;
const q = (id, text, format, purpose = "decide") => ({ id, text, alternatives: [], dependsOn: [], purpose, format });

/** A 20 MiB PDF-headed file: three pieces of 8, 8 and 4 MiB. */
function pdfBytes() {
  const buf = crypto.randomBytes(20 * MIB);
  Buffer.from("%PDF-1.7\n").copy(buf, 0);
  return buf;
}

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_uploads.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_uploads"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("uploads");
    s.apply(A.dir, [{ op: "set-title", title: "Wallets" }, { op: "open-round", questions: [
      q("Q1", "Which wallet do we add first?", { kind: "choice", options: [{ id: "opt-1", label: "Apple Pay" }, { id: "opt-2", label: "Google Pay" }] }),
    ] }]);
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const ann = await rec.open(A.localUrl, { context: PHONE });
    await joinAs(ann, "Ann");
    const bo = await rec.open(A.localUrl);
    await joinAs(bo, "Bo");
    const attach = page => page.locator(".vf-composer .vf-attach");
    const visibleUploadControls = page => page.evaluate(() => [...document.querySelectorAll("input[type=file], .vf-attach, button, [role=button]")]
      .filter(e => e.offsetParent && (e.matches("input[type=file], .vf-attach") || /attach|upload/i.test(`${e.textContent} ${e.getAttribute("aria-label") || ""} ${e.title || ""}`)))
      .map(e => e.className || e.tagName));
    // The page's own store (web/app.js keeps a pending file in IndexedDB "vf-uploads", object store "files").
    const keysIn = () => new Promise(res => {
      const r = indexedDB.open("vf-uploads", 1);
      r.onupgradeneeded = () => r.result.createObjectStore("files");
      r.onsuccess = () => { const g = r.result.transaction("files").objectStore("files").getAllKeys(); g.onsuccess = () => { res(g.result); r.result.close(); }; };
      r.onerror = () => res(null);
    });
    const idbKeys = page => page.evaluate(keysIn);
    /** True once the page's store no longer holds `id` (polled in the page: waitForFunction awaits a promise). */
    const idbLetGo = (page, id) => until(page, key => new Promise(res => {
      const r = indexedDB.open("vf-uploads", 1);
      r.onsuccess = () => { const g = r.result.transaction("files").objectStore("files").getAllKeys(); g.onsuccess = () => { res(!g.result.includes(key)); r.result.close(); }; };
      r.onerror = () => res(false);
    }), id, 10000);
    const setUploads = async on => {
      await owner.click(".vf-gear");
      const sw = owner.locator(".vf-sw-row", { hasText: "Uploads" });
      if ((await sw.getAttribute("aria-checked")) !== String(on)) await sw.click();
      await until(owner, v => window.Core.state.settings.uploads === v, on);
      await owner.keyboard.press("Escape");
    };
    const offer = async (page, file) => {
      await attach(page).click();
      await page.waitForSelector("dialog.vf-attdlg[open]");
      await page.locator("dialog.vf-attdlg .vf-rpfield:not([hidden]) input[type=file]").setInputFiles(file);
      await page.locator("dialog.vf-attdlg button[type=submit]").click();
      await until(page, () => !document.querySelector("dialog.vf-attdlg[open]"));
    };
    const mine = async (page, name) => (await snap(page)).myUploads.find(u => u.file === name);
    const hostRow = name => owner.locator(".vf-queue .vf-uprow", { hasText: name });

    // The comment box (and its attach button) shows once a pick is made: both guests pick first.
    for (const [page, label] of [[ann, "Apple Pay"], [bo, "Google Pay"]]) {
      await page.locator(".vf-opt", { hasText: label }).locator(".vf-optchoose").click();
      await until(page, () => window.Core.snapshot().cards.Q1?.some(c => c.kind === "person" && c.pid === window.Core.snapshot().me.pid && !!c.pick));
    }

    // ---------- Uploads off: no upload control anywhere ----------
    ok("Uploads is off by default", (await snap(owner)).settings.uploads === false);
    ok("the comment row shows on both guests' picks", await until(ann, () => !!document.querySelector(".vf-composer .vf-sendbtn")?.offsetParent || !!document.querySelector(".vf-composer #vf-answer")?.offsetParent));
    ok("while Uploads is off, the phone guest sees no attach button on her answer", await attach(ann).isHidden());
    ok("nor any upload control on the page (phone and desktop)", (await visibleUploadControls(ann)).length === 0 && (await visibleUploadControls(bo)).length === 0,
      JSON.stringify([...(await visibleUploadControls(ann)), ...(await visibleUploadControls(bo))]));

    // ---------- on: the phone guest offers a file; it waits in her browser ----------
    await setUploads(true);
    ok("with Uploads on, the attach button shows on the phone", await until(ann, () => !!document.querySelector(".vf-composer .vf-attach")?.offsetParent));
    await attach(ann).click();
    await ann.waitForSelector("dialog.vf-attdlg[open]");
    ok("the one attach picker offers Upload a file and nothing it cannot send", await ann.evaluate(() => {
      const d = document.querySelector("dialog.vf-attdlg"), shown = [...d.querySelectorAll(".vf-seg-btn")].filter(b => !b.hidden).map(b => b.textContent);
      return shown.length <= 1 && !!d.querySelector(".vf-rpfield:not([hidden]) input[type=file]");
    }));
    const box = await ann.locator("dialog.vf-attdlg button[type=submit]").boundingBox();
    ok("on the phone its Offer button lies inside the viewport", !!box && box.x >= 0 && box.y >= 0 && box.x + box.width <= 390 && box.y + box.height <= 844, JSON.stringify(box));
    await ann.keyboard.press("Escape");
    const data = pdfBytes(), sha = crypto.createHash("sha256").update(data).digest("hex");
    await offer(ann, { name: "funnel.pdf", mimeType: "application/pdf", buffer: data });
    const offered = await until(ann, () => (window.Core.snapshot().myUploads || []).some(u => u.file === "funnel.pdf" && u.status.kind === "offered"));
    const uid = (await mine(ann, "funnel.pdf"))?.id;
    ok("the offer is recorded, waiting for the host", offered, uid);
    ok("the file is held in her browser (IndexedDB) until the host accepts", (await idbKeys(ann) || []).includes(uid));
    ok("her row says it waits for the host", await until(ann, () => [...document.querySelectorAll(".vf-upstrip .vf-uprow")].some(r => /Waiting for the host/.test(r.textContent))));
    ok("Offer file attaches it to her answer at once, as a paste does, waiting for the host", await until(ann, () => [...document.querySelectorAll(".vf-composer .vf-attdraft .vf-ref")]
      .some(li => li.textContent.includes("funnel.pdf") && /Waiting for the host/.test(li.textContent))));
    ok("nothing of it reached the session folder yet", !fs.existsSync(path.join(A.dir, "uploads", "accepted")) || fs.readdirSync(path.join(A.dir, "uploads", "accepted")).length === 0);

    // ---------- a dropped piece, then a reload: the send resumes from the server's count ----------
    const sent = { 0: 0, 1: 0, 2: 0 };
    let drop = true;
    await ann.context().route("**/api/upload/chunk", route => {
      const i = Number(route.request().headers()["x-chunk-index"]);
      // A piece in flight when the page reloads is aborted under the handler, so abort or continue can throw.
      if (i === 1 && drop) return route.abort("connectionreset").catch(() => {});
      sent[i] = (sent[i] || 0) + 1;
      return route.continue().catch(() => {});
    });
    await owner.locator(".vf-seg-btn", { hasText: /^Host$/ }).click();
    await hostRow("funnel.pdf").locator("button", { hasText: "Accept" }).click();
    ok("after the owner's Accept, the first piece arrives and the next is dropped", await until(ann, id => (window.Core.snapshot().myUploads || [])
      .some(u => u.id === id && u.status.kind === "uploading" && u.status.received === 1), uid, 20000));
    await ann.waitForTimeout(1500);
    await ann.reload();
    drop = false;
    ok("after a reload the upload finishes from IndexedDB", await until(ann, id => (window.Core.snapshot()?.myUploads || []).some(u => u.id === id && u.status.kind === "done"), uid, 30000));
    ok("each piece reached the server once: the resume sent no piece twice", sent[0] === 1 && sent[1] === 1 && sent[2] === 1, JSON.stringify(sent));
    ok("the server's record holds the whole file's sha256", (await mine(ann, "funnel.pdf"))?.status.sha256 === sha);
    const dir = path.join(A.dir, "uploads", "accepted"), saved = fs.existsSync(dir) ? fs.readdirSync(dir) : [];
    ok("the received file is byte for byte what she offered, under a name the server made", saved.length === 1 && /^\d{8}-U\d+-[0-9a-f]{8}\.pdf$/.test(saved[0])
      && crypto.createHash("sha256").update(fs.readFileSync(path.join(dir, saved[0]))).digest("hex") === sha, saved.join(","));
    ok("her browser let go of the file once it was sent", await idbLetGo(ann, uid));
    await ann.context().unroute("**/api/upload/chunk");

    // ---------- C44: attach it to her pick from the picker's list; another guest sees it ----------
    await attach(ann).click();
    await ann.waitForSelector("dialog.vf-attdlg[open]");
    const pick = ann.locator("dialog.vf-attdlg .vf-attpick", { hasText: "funnel.pdf" });
    ok("the picker lists her accepted file to attach", await pick.isVisible());
    await pick.click();
    ok("it shows as a chip on her answer, not sent yet", await until(ann, () => [...document.querySelectorAll(".vf-attdraft .vf-ref")].some(li => li.textContent.includes("funnel.pdf"))));
    const chip = await ann.evaluate(() => {
      const d = [...document.querySelectorAll(".vf-attdraft .vf-ref")].find(li => li.textContent.includes("funnel.pdf"))?.querySelector(".vf-ref-dom");
      return d && { text: d.textContent, fits: d.scrollWidth <= d.clientWidth + 1 };
    });
    ok("on the phone the chip's status reads in full, not cut off", !!chip && /Received by the host/.test(chip.text) && chip.fits, JSON.stringify(chip));
    await ann.evaluate(() => document.querySelector("form.vf-composer").requestSubmit());
    ok("sent with the pick, the card carries the upload", await until(ann, id => window.Core.snapshot().cards.Q1?.some(c => c.kind === "person" && c.pick === "opt-1"
      && (c.attachments || []).includes(id)), uid));
    ok("the desktop guest sees the file on Ann's card", await until(bo, () => [...document.querySelectorAll(".vf-attlist .vf-ref")].some(li => li.textContent.includes("funnel.pdf"))));
    ok("and reads its name and size, never where it is saved", await bo.evaluate(id => {
      const t = JSON.stringify(window.Core.snapshot());
      return window.Core.snapshot().files[id]?.file === "funnel.pdf" && !t.includes("uploads/") && !t.includes('"stored"') && !t.includes('"tmp"');
    }, uid));

    // ---------- AC 21: a declined file is deleted from the guest's browser and shows "Not accepted" ----------
    await offer(bo, { name: "notes.txt", mimeType: "text/plain", buffer: Buffer.from("Shoppers stop at the address step.\n") });
    await until(bo, () => (window.Core.snapshot().myUploads || []).some(u => u.file === "notes.txt"));
    const nid = (await mine(bo, "notes.txt"))?.id;
    ok("the desktop guest's offer is held in his browser", (await idbKeys(bo) || []).includes(nid));
    ok("the owner's queue shows the server's extension beside the name", await until(owner, () => [...document.querySelectorAll(".vf-queue .vf-uprow .vf-upname")]
      .some(n => /^notes\.txt · TXT · /.test(n.textContent))));
    await hostRow("notes.txt").locator("button", { hasText: "Decline" }).click();
    await owner.locator("dialog[open] button", { hasText: "Decline file" }).click();
    ok("declined, his row shows \"Not accepted\"", await until(bo, () => [...document.querySelectorAll(".vf-upstrip .vf-uprow")].some(r => r.textContent.includes("notes.txt") && /Not accepted/.test(r.textContent))));
    ok("and his browser deleted its copy", await idbLetGo(bo, nid));
    ok("nothing of it is kept on the host's computer", !fs.existsSync(path.join(A.dir, "uploads", "pending")) || fs.readdirSync(path.join(A.dir, "uploads", "pending")).length === 0);

    // ---------- off again: the upload control goes ----------
    await setUploads(false);
    ok("Uploads off hides the attach button on the phone and the desktop", await until(ann, () => !document.querySelector(".vf-composer .vf-attach")?.offsetParent)
      && await until(bo, () => !document.querySelector(".vf-composer .vf-attach")?.offsetParent));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource|ERR_CONNECTION_RESET|Failed to fetch/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
