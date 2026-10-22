#!/usr/bin/env node
// GIFs in chat and answers, against `share.sh ensure-running` with the fake cloudflared: a pasted animated GIF goes
// whole, with only its frames and loop count, and is never redrawn; it shows as a still first frame with Play GIF,
// for a guest who asks for reduced motion and for one who does not, on its tile and in the viewer; another guest sees
// nothing of a guest's GIF before the owner approves it; a one-frame GIF shows as it is, with no Play GIF; a GIF over
// 512 KB is refused before it is offered.
//   env UI_JOBS=2 nice node plugins/planning/shared/tests/ui_gifs.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the GIF89a block layout this suite writes, WCAG 2.2.2 and the 512 KB shown-picture cap,
// never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, snap, joinAs } = require("./browser_harness");

const q = (id, text, purpose = "gather") => ({ id, text, alternatives: [], dependsOn: [], purpose, format: { kind: "text" } });
const DESK = { viewport: { width: 1440, height: 900 } };

// A 1x1 GIF89a in two colors, built by block: a frame's LZW data is clear, color index, end, in 3-bit codes.
const b = (...x) => Buffer.from(x);
const HEAD = Buffer.concat([Buffer.from("GIF89a"), b(1, 0, 1, 0, 0x80, 0, 0), b(0xff, 0, 0, 0, 0, 0xff)]);
const LOOP = Buffer.concat([b(0x21, 0xff, 11), Buffer.from("NETSCAPE2.0"), b(3, 1, 0, 0, 0)]);
const frame = color => Buffer.concat([b(0x21, 0xf9, 4, 4, 50, 0, 0, 0), b(0x2c, 0, 0, 0, 0, 1, 0, 1, 0, 0), b(2, 2, color ? 0x4c : 0x44, 1, 0)]);
const COMMENT = Buffer.concat([b(0x21, 0xfe, 13), Buffer.from("who-made-this"), b(0)]);
const XMP = Buffer.concat([b(0x21, 0xff, 11), Buffer.from("XMP DataXMP"), b(9), Buffer.from("gps=51,0;"), b(0)]);
// A plain-text extension (label 0x01, a 12-byte header, then text), an unknown label, and a loop block with a
// sub-block of text after its loop count: each can carry text, so only the loop count itself should survive.
const PLAIN = Buffer.concat([b(0x21, 0x01, 12, 0, 0, 0, 0, 1, 0, 1, 0, 8, 8, 1, 0, 10), Buffer.from("plain-note"), b(0)]);
const UNKNOWN = Buffer.concat([b(0x21, 0x99, 7), Buffer.from("unknown"), b(0)]);
const LOOP_TAIL = Buffer.concat([LOOP.subarray(0, -1), b(6), Buffer.from("tailed"), b(0)]);
const END = b(0x3b);
const ANIMATED = Buffer.concat([HEAD, LOOP_TAIL, COMMENT, PLAIN, frame(0), XMP, UNKNOWN, frame(1), END]);
const STRIPPED = Buffer.concat([HEAD, LOOP, frame(0), frame(1), END]); // what the host should hold: frames and the bare loop count
const STILL = Buffer.concat([HEAD, frame(0), END]);
// Over 512 KB: one frame whose image data is 2100 sub-blocks of 255 bytes.
const BIG = Buffer.concat([HEAD, b(0x2c, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2), Buffer.concat(Array.from({ length: 2100 }, () => Buffer.concat([b(255), Buffer.alloc(255)]))), b(0), END]);

/** Paste `bytes` as an image/gif File into `sel`, as a ClipboardEvent whose clipboardData holds it. */
const paste = (page, sel, bytes) => page.evaluate(([s, arr]) => {
  const dt = new DataTransfer(); dt.items.add(new File([new Uint8Array(arr)], "clip.gif", { type: "image/gif" }));
  const el = document.querySelector(s); el.focus();
  el.dispatchEvent(new ClipboardEvent("paste", { clipboardData: dt, bubbles: true, cancelable: true }));
}, [sel, [...bytes]]);
/** The newest upload this page offered, once the host has it whole. */
const arrived = async (page, before) => {
  await until(page, n => (window.Core.snapshot().myUploads || []).length > n, before, 10000);
  const id = (await snap(page)).myUploads.at(-1).id;
  return (await until(page, x => window.Core.snapshot().myUploads.some(u => u.id === x && u.status.kind === "done"), id, 20000)) && id;
};
/** The picture a page reads back: the data: URL, or the refusal's status. */
const readBack = (page, id) => page.evaluate(x => window.Core.uploadImage(x).then(u => u, e => e.status || 0), id);
/** One attachment tile in the chat message whose text holds `text`: its picture's src kind, its Play GIF button, its wait state. */
const tile = (page, text) => page.evaluate(t => {
  const li = [...document.querySelectorAll(".vf-msg")].find(m => m.textContent.includes(t))?.querySelector(".vf-attlist .vf-ref");
  return li ? { src: (li.querySelector("img")?.getAttribute("src") || "").slice(0, 15), play: li.querySelector(".vf-gifplay")?.textContent || "",
    waits: !!li.querySelector(".vf-uppic-wait") } : null;
}, text);
const card = page => page.evaluate(() => {
  const li = document.querySelector(".vf-card.vf-mine .vf-attlist .vf-ref");
  return li ? { src: (li.querySelector("img")?.getAttribute("src") || "").slice(0, 15), play: li.querySelector(".vf-gifplay")?.textContent || "" } : null;
});

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_gifs.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_gifs"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("gifs");
    s.apply(A.dir, [{ op: "set-title", title: "Launch party" }, { op: "open-round", questions: [q("Q1", "What should the launch feel like?")] }]);
    const owner = await rec.open(A.ownerUrl, { context: DESK });
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    await owner.evaluate(() => window.Core.saveSettings({ uploads: true }));
    const ann = await rec.open(A.localUrl, { context: { ...DESK, reducedMotion: "reduce" } });
    await joinAs(ann, "Ann");
    const bo = await rec.open(A.localUrl, { context: DESK });
    await joinAs(bo, "Bo");
    await until(ann, () => window.Core.state.settings.uploads === true);
    ok("Ann's page asks for reduced motion and Bo's does not", (await ann.evaluate(() => matchMedia("(prefers-reduced-motion: reduce)").matches))
      && !(await bo.evaluate(() => matchMedia("(prefers-reduced-motion: reduce)").matches)));

    // ---------- Ann pastes an animated GIF into her answer: it goes whole, without its comment or XMP text ----------
    await paste(ann, "#vf-answer", ANIMATED);
    await until(ann, () => (window.Core.snapshot().myUploads || []).length > 0, null, 10000);
    const gif = (await snap(ann)).myUploads.at(-1).id;
    ok("the offer is a .gif of the stripped size", await ann.evaluate(([id, n]) => { const u = window.Core.state.myUploads.find(x => x.id === id); return u.file.endsWith(".gif") && u.size === n; }, [gif, STRIPPED.length]),
      JSON.stringify((await snap(ann)).myUploads.at(-1)));
    await owner.evaluate(id => window.Core.uploadAct(id, "accept"), gif);
    ok("accepted, it arrives", await until(ann, id => window.Core.snapshot().myUploads.some(u => u.id === id && u.status.kind === "done"), gif, 20000));
    const held = await readBack(owner, gif);
    ok("the host holds the GIF's own frames and loop, byte for byte, with no comment or XMP block", typeof held === "string" && held.startsWith("data:image/gif;base64,")
      && Buffer.from(held.slice(22), "base64").equals(STRIPPED), String(held).slice(0, 60));
    ok("  none of the plain-text, unknown-label or loop-tail text reaches the host", typeof held === "string"
      && !/plain-note|unknown|tailed/.test(Buffer.from(held.slice(22), "base64").toString("latin1")));
    await ann.locator(".vf-composer .vf-sendbtn").click();
    ok("Send saves her answer holding the GIF", await until(ann, id => window.Core.snapshot().cards.Q1?.some(c => (c.attachments || []).includes(id)), gif, 10000));

    // ---------- reduced motion: her card shows a still first frame with Play GIF ----------
    ok("with reduced motion her card shows the GIF's still first frame (a PNG) and Play GIF", await until(ann, () => {
      const li = document.querySelector(".vf-card.vf-mine .vf-attlist .vf-ref");
      return li?.querySelector("img")?.getAttribute("src")?.startsWith("data:image/png") && li.querySelector(".vf-gifplay")?.textContent === "Play GIF";
    }, null, 10000), JSON.stringify(await card(ann)));
    await ann.locator(".vf-card.vf-mine .vf-gifplay").click();
    ok("  Play GIF plays it, and the button reads Stop GIF", JSON.stringify(await card(ann)) === JSON.stringify({ src: "data:image/gif;", play: "Stop GIF" }), JSON.stringify(await card(ann)));
    await ann.keyboard.press("Enter"); // the button keeps focus: the keyboard stops it too
    ok("  Stop GIF shows the still again", JSON.stringify(await card(ann)) === JSON.stringify({ src: "data:image/png;", play: "Play GIF" }), JSON.stringify(await card(ann)));

    // ---------- in chat, Bo sees nothing of it until the owner approves it ----------
    await ann.evaluate(id => window.Core.chat("Ta-da", null, { attachments: [id] }), gif);
    await bo.locator(".vf-fab").click();
    ok("Bo's chat first shows the message's picture waiting for the host", await until(bo, () => !![...document.querySelectorAll(".vf-msg")].find(m => m.textContent.includes("Ta-da"))
      ?.querySelector(".vf-uppic-wait"), null, 10000), JSON.stringify(await tile(bo, "Ta-da")));
    ok("  with no picture, no Play GIF, and nothing to read back", JSON.stringify(await tile(bo, "Ta-da")) === JSON.stringify({ src: "", play: "", waits: true })
      && (await readBack(bo, gif)) === 404, JSON.stringify(await tile(bo, "Ta-da")));
    await owner.evaluate(id => window.Core.uploadAct(id, "approve"), gif);
    ok("approved, Bo (no reduced motion) sees it still too, with Play GIF", await until(bo, () => {
      const li = [...document.querySelectorAll(".vf-msg")].find(m => m.textContent.includes("Ta-da"))?.querySelector(".vf-attlist .vf-ref");
      return li?.querySelector("img")?.getAttribute("src")?.startsWith("data:image/png") && li.querySelector(".vf-gifplay")?.textContent === "Play GIF";
    }, null, 10000), JSON.stringify(await tile(bo, "Ta-da")));

    // ---------- the viewer starts still too ----------
    await bo.locator(".vf-msg", { hasText: "Ta-da" }).locator(".vf-uppic").click();
    const lb = () => bo.evaluate(() => ({ src: (document.querySelector(".vf-lb-img")?.getAttribute("src") || "").slice(0, 15), play: document.querySelector(".vf-lb-gif:not([hidden])")?.textContent || "" }));
    ok("the viewer shows the still with Play GIF", await until(bo, () => document.querySelector(".vf-lb-img")?.getAttribute("src")?.startsWith("data:image/png") && document.querySelector(".vf-lb-gif:not([hidden])")?.textContent === "Play GIF"),
      JSON.stringify(await lb()));
    await bo.locator(".vf-lb-gif").click();
    ok("  and plays it on Play GIF", JSON.stringify(await lb()) === JSON.stringify({ src: "data:image/gif;", play: "Stop GIF" }), JSON.stringify(await lb()));
    await owner.evaluate(() => window.Core.chat("Still watching"));
    await until(bo, () => [...document.querySelectorAll(".vf-msg")].some(m => m.textContent.includes("Still watching")), null, 10000);
    ok("  a repaint while it is open keeps it playing", JSON.stringify(await lb()) === JSON.stringify({ src: "data:image/gif;", play: "Stop GIF" }), JSON.stringify(await lb()));
    await bo.keyboard.press("Escape");
    await bo.locator(".vf-msg", { hasText: "Ta-da" }).locator(".vf-uppic").click();
    ok("  opened again, it starts still with Play GIF", await until(bo, () => document.querySelector(".vf-lb-img")?.getAttribute("src")?.startsWith("data:image/png") && document.querySelector(".vf-lb-gif:not([hidden])")?.textContent === "Play GIF"),
      JSON.stringify(await lb()));
    await bo.keyboard.press("Escape");

    // ---------- a one-frame GIF shows as it is ----------
    await paste(owner, "#vf-answer", STILL);
    const one = await arrived(owner, 0);
    await owner.evaluate(id => window.Core.chat("Just one frame", null, { attachments: [id] }), one);
    ok("a one-frame GIF shows as the GIF itself, with no Play GIF", await until(bo, () => {
      const li = [...document.querySelectorAll(".vf-msg")].find(m => m.textContent.includes("Just one frame"))?.querySelector(".vf-attlist .vf-ref");
      return li?.querySelector("img:not([hidden])")?.getAttribute("src")?.startsWith("data:image/gif") && !li.querySelector(".vf-gifplay");
    }, null, 10000), JSON.stringify(await tile(bo, "Just one frame")));

    // ---------- over 512 KB it is refused before it is offered ----------
    const before = (await snap(ann)).myUploads.length;
    await paste(ann, "#vf-answer", BIG);
    ok("a GIF over 512 KB is refused with the cap named", await until(ann, () => /A GIF shows in place up to 512 KB\./.test(document.querySelector(".vf-toast")?.textContent || ""), null, 10000),
      await ann.evaluate(() => document.querySelector(".vf-toast")?.textContent));
    ok("  and nothing is offered", (await snap(ann)).myUploads.length === before);

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource|Failed to fetch|ERR_CONNECTION/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
