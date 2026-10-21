#!/usr/bin/env node
// Attach and paste on every place people write, against `share.sh ensure-running` with the fake cloudflared: with
// Uploads off a pasted picture adds nothing; on, the answer box, Ask Claude, chat, the Discussion and Propose each show
// an Attach button, and a picture pasted into each (a ClipboardEvent carrying an image File) becomes a thumbnail chip
// reading "Waiting for the host", never text in the field; sending waits until the host accepts it; once accepted and
// received, the picture shows as a tile to another guest who sees what carries it and opens in the viewer, while a
// proposal, a request and a hidden comment keep theirs from that guest. Drafts stay on their own question; a declined
// file leaves the form at Send; taking a pasted chip off withdraws it; a picked JPEG reaches the host redrawn, with
// no EXIF; the host's own paste, the question's ask box and Suggest take pictures too; and the host removes one.
//   node plugins/planning/shared/tests/ui_attach_paste.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the approved spec (attach and paste on every text input; accepted pictures shown to
// everyone who sees their item) and the texts this suite writes, never from the page.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { loadPlaywright, suite, recorder, until, snap, joinAs, openClaude } = require("./browser_harness");

const q = (id, text, purpose = "gather") => ({ id, text, alternatives: [], dependsOn: [], purpose, format: { kind: "text" } });
const DESK = { context: { viewport: { width: 1440, height: 900 } } };

// Each place people write: how to open it, its field, its form (where the Attach button and the chips sit), how to send.
const FORMS = {
  answer: { field: "#vf-answer", form: ".vf-composer", text: "The green one, see the picture." },
  ask: { field: "#vf-ap-ta", form: ".vf-apform", text: "What is in this picture?" },
  chat: { field: ".vf-minput", form: ".vf-mform", chips: ".vf-chat", text: "Look at this screen." },
  discussion: { field: ".vf-disc-ta", form: ".vf-disc-form", text: "Here is how it looks today." },
  propose: { field: "#vf-prop-ta", form: ".vf-proposepop", text: "Should the summary sit beside the button?" },
};
const openChat = async page => { if (await page.evaluate(() => document.querySelector(".vf-chat").hidden)) await page.click(".vf-fab"); return until(page, () => !document.querySelector(".vf-chat").hidden); };
const openDisc = async page => { if ((await page.getAttribute(".vf-disc-head", "aria-expanded")) !== "true") await page.click(".vf-disc-head"); return until(page, () => !document.querySelector(".vf-disc-body").hidden); };
const opens = {
  answer: async () => true,
  ask: async page => {
    if (await page.evaluate(() => document.querySelector(".vf-apform")?.offsetParent === null)) await page.click(".vf-asktop");
    await page.selectOption(".vf-apq select", { index: 1 }); // a question: the whole session offers no own Claude
    return until(page, () => !!document.querySelector("#vf-ap-ta")?.offsetParent);
  },
  chat: openChat,
  discussion: openDisc,
  propose: async page => { await page.click(".vf-propose"); return until(page, () => !!document.querySelector(".vf-proposepop:not([hidden])")); },
};
const closeAll = page => page.keyboard.press("Escape");

/** Paste a 640x400 PNG made in the page into `sel`, as a ClipboardEvent whose clipboardData holds an image File. */
const paste = (page, sel) => page.evaluate(async s => {
  const c = document.createElement("canvas"); c.width = 640; c.height = 400;
  const g = c.getContext("2d"); g.fillStyle = "#2a7"; g.fillRect(0, 0, 640, 400); g.fillStyle = "#fff"; g.fillRect(40, 300, 200, 60);
  const blob = await new Promise(r => c.toBlob(r, "image/png"));
  const dt = new DataTransfer(); dt.items.add(new File([blob], "clip.png", { type: "image/png" }));
  const el = document.querySelector(s); el.focus();
  const before = el.value;
  el.dispatchEvent(new ClipboardEvent("paste", { clipboardData: dt, bubbles: true, cancelable: true }));
  return before;
}, sel);
/** The draft chips of one form: each one's thumbnail source kind and its text. */
const chips = (page, sel) => page.evaluate(s => [...(document.querySelector(s)?.querySelectorAll(".vf-attdraft .vf-ref") || [])]
  .map(li => ({ img: (li.querySelector(".vf-ref-thumb img:not([hidden])")?.getAttribute("src") || "").slice(0, 11), text: li.textContent })), sel);

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_attach_paste.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_attach_paste"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("attach-paste");
    s.apply(A.dir, [{ op: "set-title", title: "Checkout" }, { op: "open-round", questions: [q("Q1", "Where should the order summary sit?"), q("Q2", "Which default should the cart use?", "decide")] }]);
    const owner = await rec.open(A.ownerUrl, DESK);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const ann = await rec.open(A.localUrl, DESK);
    await joinAs(ann, "Ann");
    const bo = await rec.open(A.localUrl, DESK);
    await joinAs(bo, "Bo");

    // ---------- Uploads off: a pasted picture adds nothing ----------
    await openChat(ann);
    ok("with Uploads off, chat shows no Attach button", await ann.locator(".vf-mform .vf-attach").isHidden());
    await paste(ann, ".vf-minput");
    await ann.waitForTimeout(500);
    ok("and a pasted picture makes no chip and offers nothing", (await chips(ann, ".vf-chat")).length === 0 && (await snap(ann)).myUploads.length === 0);
    await closeAll(ann);

    // Bo opens Propose while Uploads is off; the host turns it on meanwhile.
    ok("Bo's Propose form opens", await opens.propose(bo));
    await owner.evaluate(() => window.Core.saveSettings({ uploads: true }));
    await until(ann, () => window.Core.state.settings.uploads === true);
    await until(bo, () => window.Core.state.settings.uploads === true);
    await paste(bo, FORMS.propose.field);
    ok("a picture pasted into a Propose form opened before Uploads was on still becomes a chip", await until(bo, () => document.querySelectorAll(".vf-proposepop .vf-attdraft .vf-ref").length === 1, null, 10000));
    const boPasted = await until(bo, () => (window.Core.snapshot().myUploads || []).length === 1) && (await snap(bo)).myUploads[0].id;
    await bo.locator(".vf-proposepop .vf-attdraft .vf-ref-x").click();
    ok("taking the pasted chip off withdraws its upload", await until(bo, id => window.Core.snapshot().myUploads.find(u => u.id === id)?.status.kind === "withdrawn", boPasted));
    await closeAll(bo);

    // ---------- Ask Claude with "Run it on my own Claude" on takes no picture ----------
    ok("Bo's Ask Claude opens", await opens.ask(bo));
    await bo.click(".vf-apself");
    await until(bo, () => document.querySelector(".vf-apself").getAttribute("aria-checked") === "true");
    await paste(bo, FORMS.ask.field);
    await bo.waitForTimeout(1500);
    ok("with my own Claude on, a paste into Ask Claude offers nothing and makes no chip", (await snap(bo)).myUploads.length === 1
      && (await chips(bo, ".vf-apform")).length === 0, JSON.stringify((await snap(bo)).myUploads.map(u => u.file)));
    await bo.click(".vf-apself");
    await closeAll(bo);

    // ---------- on: Attach on every form, and a pasted picture becomes a thumbnail chip waiting for the host ----------
    const ids = {};
    for (const [name, f] of Object.entries(FORMS)) {
      ok(`${name}: the form opens`, await opens[name](ann));
      ok(`${name}: an Attach button shows`, await until(ann, sel => !!document.querySelector(`${sel} .vf-attach`)?.offsetParent, f.form));
      const had = (await snap(ann)).myUploads.map(u => u.id);
      await ann.fill(f.field, f.text);
      await paste(ann, f.field);
      const where = f.chips || f.form;
      ok(`${name}: the pasted picture shows as a thumbnail chip reading "Waiting for the host"`, await until(ann, sel => [...(document.querySelector(sel)?.querySelectorAll(".vf-attdraft .vf-ref") || [])]
        .some(li => li.querySelector(".vf-ref-thumb img:not([hidden])")?.getAttribute("src")?.startsWith("data:image/") && li.textContent.includes("Waiting for the host")), where, 10000),
        JSON.stringify(await chips(ann, where)));
      ok(`${name}: the field keeps only its text`, (await ann.inputValue(f.field)) === f.text);
      ids[name] = (await snap(ann)).myUploads.find(u => !had.includes(u.id))?.id;
      ok(`${name}: it was offered to the host as a picture made in the browser`, !!ids[name] && /^pasted-\d{14}\.(webp|jpg)$/.test((await snap(ann)).myUploads.find(u => u.id === ids[name]).file));
      if (name !== "answer") await closeAll(ann);
    }

    // ---------- before the host accepts: sending waits, the host sees the picture, Bo sees nothing ----------
    await openChat(ann);
    await ann.click(".vf-mform button[type=submit]");
    ok("sending chat before the host accepts says it waits for the host", await until(ann, () => /is waiting for the host\. Send once they accept it, or remove it\./.test(document.querySelector(".vf-toast.vf-on span")?.textContent || "")));
    ok("and posts nothing", !(await snap(ann)).chat.some(m => m.text === FORMS.chat.text));
    await closeAll(ann);
    await owner.locator(".vf-seg-btn", { hasText: /^Host$/ }).click();
    ok("the host's queue shows the offered picture", await until(owner, () => [...document.querySelectorAll(".vf-queue .vf-uprow")].some(r => /^pasted-/.test(r.querySelector(".vf-upname")?.textContent || "")
      && r.querySelector(".vf-upthumb:not([hidden]) img")?.getAttribute("src")?.startsWith("data:image/"))));
    ok("Bo's page holds none of them", !Object.keys((await snap(bo)).files || {}).some(id => Object.values(ids).includes(id)));

    for (const id of Object.values(ids)) await owner.evaluate(u => window.Core.uploadAct(u, "accept"), id);
    ok("accepted, every pasted picture arrives", await until(ann, want => want.every(id => (window.Core.snapshot().myUploads || []).some(u => u.id === id && u.status.kind === "done")), Object.values(ids), 30000));
    ok("and Ann's chips show the received picture", await until(ann, () => [...document.querySelectorAll(".vf-composer .vf-attdraft .vf-uppic img")].some(i => i.getAttribute("src")?.startsWith("data:image/")), null, 10000));

    // ---------- sent from each form ----------
    await ann.evaluate(() => document.querySelector("form.vf-composer").requestSubmit());
    for (const name of ["ask", "chat", "discussion", "propose"]) {
      await opens[name](ann);
      await ann.waitForTimeout(1100); // one write a second per person and route
      await ann.evaluate(sel => document.querySelector(sel).requestSubmit(), FORMS[name].form);
      await ann.waitForTimeout(300);
      if (name !== "chat" && name !== "discussion") await closeAll(ann);
    }
    const sent = await until(ann, want => {
      const s = window.Core.snapshot(), has = (recs, id) => (recs || []).some(r => (r.attachments || []).includes(id));
      return has(s.cards.Q1, want.answer) && has(s.myRequests, want.ask) && has(s.chat, want.chat) && has(s.discussions?.Q1, want.discussion) && has(s.proposals, want.propose);
    }, ids, 15000);
    ok("each form sent its picture with what it posted", sent, JSON.stringify(ids));

    // ---------- received, a guest's picture waits for the host's approval before Bo sees it ----------
    await openChat(bo);
    ok("before the host approves, Bo sees a placeholder reading \"Waiting for the host\" on the chat message, not the picture", await until(bo, t => {
      const m = [...document.querySelectorAll(".vf-chat .vf-msg")].find(li => li.textContent.includes(t));
      return !!m && /Waiting for the host/.test(m.querySelector(".vf-uppic-wait")?.textContent || "") && !m.querySelector(".vf-uppic img[src^='data:']");
    }, FORMS.chat.text, 10000));
    ok("and the server refuses him the picture", await bo.evaluate(id => window.Core.uploadImage(id).then(() => false, e => e.status === 404), ids.chat));
    for (const name of ["answer", "ask", "discussion", "propose"]) await owner.evaluate(id => window.Core.uploadAct(id, "approve"), ids[name]);
    const approveRow = owner.locator(".vf-queue .vf-uprow", { has: owner.locator(".vf-upapprove:visible") });
    ok("the host's queue lists the received picture with Approve picture, showing what arrived", await until(owner, () => {
      const rows = [...document.querySelectorAll(".vf-queue .vf-uprow")].filter(r => r.querySelector(".vf-upapprove") && !r.querySelector(".vf-upapprove").hidden);
      return rows.length === 1 && rows[0].querySelector(".vf-upthumb:not([hidden]) img")?.getAttribute("src")?.startsWith("data:image/") && !rows[0].querySelector(".vf-upremove").hidden;
    }, null, 10000));
    await approveRow.locator(".vf-upapprove").click();

    // ---------- Bo sees the pictures where he sees their items, as tiles that open the viewer ----------
    const tile = (page, scope, text) => until(page, ([sc, t]) => [...document.querySelectorAll(sc)].some(li => li.textContent.includes(t)
      && li.querySelector(".vf-uppic img")?.getAttribute("src")?.startsWith("data:image/")), [scope, text], 10000);
    ok("Bo sees Ann's chat picture as a tile", await tile(bo, ".vf-chat .vf-msg", FORMS.chat.text));
    ok("and on her answer", await tile(bo, ".vf-card", FORMS.answer.text));
    await openDisc(bo);
    ok("and on her Discussion comment", await tile(bo, ".vf-cm", FORMS.discussion.text));
    await bo.locator(".vf-chat .vf-msg", { hasText: FORMS.chat.text }).locator(".vf-uppic").click();
    ok("a tile opens the picture in the viewer", await until(bo, () => { const i = document.querySelector(".vf-lb-img"); return !!i?.offsetParent && i.getAttribute("src").startsWith("data:image/"); }));
    await closeAll(bo);
    const boFiles = Object.keys((await snap(bo)).files || {});
    ok("Bo's page holds no picture of Ann's proposal or her request", !boFiles.includes(ids.propose) && !boFiles.includes(ids.ask), JSON.stringify(boFiles));
    ok("the server refuses Bo the request's picture", await bo.evaluate(id => window.Core.uploadImage(id).then(() => false, e => e.status === 404), ids.ask));

    // ---------- a hidden comment takes its picture away from Bo ----------
    const cid = (await snap(owner)).discussions.Q1.find(c => (c.attachments || []).includes(ids.discussion)).id;
    await owner.evaluate(c => window.Core.hideComment("Q1", c, true), cid);
    ok("hidden, the comment's picture leaves Bo's page", await until(bo, id => !(id in (window.Core.snapshot().files || {})), ids.discussion));
    ok("and the server refuses it to him", await bo.evaluate(id => window.Core.uploadImage(id).then(() => false, e => e.status === 404), ids.discussion));

    // ---------- drafts stay on their question ----------
    const railQ = (page, qid) => page.locator(".vf-q", { hasText: qid === "Q1" ? "Where should" : "Which default" }).first();
    await openDisc(ann);
    // The offer is held back 1.5 s, so the reader moves to Q2 before it lands.
    await ann.route("**/api/upload/offer", async route => { await new Promise(r => setTimeout(r, 1500)); await route.continue(); });
    const before = (await snap(ann)).myUploads.length;
    await paste(ann, FORMS.discussion.field);
    await railQ(ann, "Q2").click();
    await until(ann, n => window.Core.snapshot().myUploads.length > n, before, 10000);
    await ann.unroute("**/api/upload/offer");
    const q1Draft = (await snap(ann)).myUploads.at(-1).id;
    await openDisc(ann);
    await ann.waitForTimeout(500);
    ok("a paste on Q1 that lands after the reader moved to Q2 puts no chip on Q2", await until(ann, () => document.querySelector(".vf-disc-form .vf-attdraft").hidden));
    await ann.fill(".vf-disc-ta", "A comment on the cart.");
    await ann.waitForTimeout(1100);
    await ann.evaluate(() => document.querySelector(".vf-disc-form").requestSubmit());
    ok("posted on Q2, the comment carries no file", await until(ann, () => (window.Core.snapshot().discussions?.Q2 || []).some(c => c.text === "A comment on the cart." && !c.attachments)));
    await railQ(ann, "Q1").click();
    await openDisc(ann);
    ok("back on Q1 the chip is still there", await until(ann, id => document.querySelectorAll(".vf-disc-form .vf-attdraft .vf-ref").length === 1
      && window.Core.state.myUploads.some(u => u.id === id && u.status === "offered"), q1Draft));

    // ---------- a file the host declines leaves the form at Send ----------
    await owner.evaluate(id => window.Core.uploadAct(id, "decline"), q1Draft);
    await until(ann, id => window.Core.state.myUploads.some(u => u.id === id && u.status === "declined"), q1Draft);
    await ann.fill(".vf-disc-ta", "Posting after the decline.");
    await ann.evaluate(() => document.querySelector(".vf-disc-form").requestSubmit());
    ok("Send names the declined file and takes it off", await until(ann, () => /^pasted-\d{14}\.(webp|jpg) is no longer available, so it was taken off\. Send again\.$/.test(document.querySelector(".vf-toast.vf-on span")?.textContent || "")
      && document.querySelector(".vf-disc-form .vf-attdraft").hidden));
    ok("and posts nothing", !((await snap(ann)).discussions?.Q1 || []).some(c => c.text === "Posting after the decline."));

    // ---------- a picked JPEG is redrawn: no EXIF reaches the host ----------
    const exifJpeg = Buffer.from(await ann.evaluate(async () => {
      const c = document.createElement("canvas"); c.width = 2400; c.height = 1600;
      const g = c.getContext("2d"); g.fillStyle = "#c44"; g.fillRect(0, 0, 2400, 1600);
      const jpg = new Uint8Array(await (await new Promise(r => c.toBlob(r, "image/jpeg", 0.95))).arrayBuffer());
      const tiff = [0x4d, 0x4d, 0, 0x2a, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0], note = [...new TextEncoder().encode("GPS-SECRET-51.5N-0.1W")];
      const body = [...new TextEncoder().encode("Exif\0\0"), ...tiff, ...note], len = body.length + 2;
      return [...jpg.slice(0, 2), 0xff, 0xe1, len >> 8, len & 255, ...body, ...jpg.slice(2)];
    }));
    ok("the test JPEG carries an EXIF segment with a GPS note", exifJpeg.includes(Buffer.from("Exif\0\0")) && exifJpeg.includes(Buffer.from("GPS-SECRET")));
    await railQ(ann, "Q2").click();
    await ann.locator(".vf-composer .vf-attach").click();
    await ann.waitForSelector("dialog.vf-attdlg[open]");
    await ann.locator("dialog.vf-attdlg .vf-rpfield:not([hidden]) input[type=file]").setInputFiles({ name: "street.jpg", mimeType: "image/jpeg", buffer: exifJpeg });
    await ann.locator("dialog.vf-attdlg button[type=submit]").click();
    ok("the picked picture is offered under its own name, redrawn", await until(ann, () => (window.Core.snapshot().myUploads || []).some(u => /^street\.(webp|jpg)$/.test(u.file)), null, 10000));
    const street = (await snap(ann)).myUploads.find(u => /^street\./.test(u.file));
    await owner.evaluate(id => window.Core.uploadAct(id, "accept"), street.id);
    ok("it arrives", await until(ann, id => window.Core.snapshot().myUploads.some(u => u.id === id && u.status.kind === "done"), street.id, 20000));
    const saved = fs.readdirSync(path.join(A.dir, "uploads", "accepted")).find(n => n.includes(street.id));
    const bytes = saved ? fs.readFileSync(path.join(A.dir, "uploads", "accepted", saved)) : Buffer.alloc(0);
    ok("the host's copy holds no EXIF and no GPS note, at most 512 KB", bytes.length > 0 && bytes.length <= 512 * 1024 && !bytes.includes(Buffer.from("Exif\0\0")) && !bytes.includes(Buffer.from("GPS-SECRET")), `${saved} ${bytes.length}`);
    await closeAll(ann);

    // ---------- the host's own paste, the question's ask box, and Suggest ----------
    await openChat(owner);
    await paste(owner, ".vf-minput");
    ok("the host's own pasted picture shows as a received picture in the chip", await until(owner, () => [...document.querySelectorAll(".vf-chat .vf-attdraft .vf-uppic img")].some(i => i.getAttribute("src")?.startsWith("data:image/")), null, 20000));
    await closeAll(owner);
    await railQ(ann, "Q1").click();
    await openClaude(ann);
    await ann.click(".vf-askbtn");
    await until(ann, () => !!document.querySelector("#vf-ask-ta")?.offsetParent);
    await paste(ann, "#vf-ask-ta");
    ok("a picture pasted into the question's ask box makes a chip", await until(ann, () => [...document.querySelectorAll(".vf-askform .vf-attdraft .vf-ref")].some(li => li.textContent.includes("Waiting for the host")), null, 10000));
    await bo.evaluate(() => window.Core.answerCiting("Q2", "Keep the cart open by default.", []));
    const lockErr = await owner.evaluate(pid => window.Core.lock("Q2", pid).then(() => "", e => JSON.stringify(e)), (await snap(bo)).me.pid);
    ok("the host locks Q2 on Bo's answer", !lockErr, lockErr);
    await railQ(ann, "Q2").click();
    await until(ann, () => !!window.Core.lockOf("Q2"));
    await ann.locator("button", { hasText: "Suggest a change" }).first().click();
    await until(ann, () => !document.querySelector(".vf-sugform").hidden);
    await paste(ann, ".vf-sugform textarea");
    ok("a picture pasted into Suggest makes a chip", await until(ann, () => [...document.querySelectorAll(".vf-sugform .vf-attdraft .vf-ref")].some(li => li.textContent.includes("Waiting for the host")), null, 10000));

    // ---------- the host removes a received picture ----------
    await openChat(owner);
    await owner.locator(".vf-chat .vf-msg", { hasText: FORMS.chat.text }).locator(".vf-upremove").click();
    await owner.locator("dialog[open] button", { hasText: "Remove picture" }).click();
    ok("removed, the picture leaves Bo's chat", await until(bo, t => { const m = [...document.querySelectorAll(".vf-chat .vf-msg")].find(li => li.textContent.includes(t)); return !!m && !m.querySelector(".vf-uppic"); }, FORMS.chat.text));
    ok("and Ann's own file reads Removed", await until(ann, id => window.Core.snapshot().myUploads.find(u => u.id === id)?.status.kind === "removed", ids.chat));

    // ---------- a message older than the chat window follows its picture's Approve and Remove ----------
    await closeAll(owner);
    await openChat(ann);
    const hadUps = (await snap(ann)).myUploads.length;
    await paste(ann, ".vf-minput");
    await until(ann, n => window.Core.snapshot().myUploads.length > n, hadUps, 10000);
    const oldPic = (await snap(ann)).myUploads.at(-1).id;
    await owner.evaluate(id => window.Core.uploadAct(id, "accept"), oldPic);
    await until(ann, id => window.Core.snapshot().myUploads.some(u => u.id === id && u.status.kind === "done"), oldPic, 20000);
    await ann.fill(".vf-minput", "A picture that scrolls away.");
    await ann.waitForTimeout(1100);
    await ann.click(".vf-mform button[type=submit]");
    const oldMsg = await until(ann, id => window.Core.snapshot().chat.some(m => (m.attachments || []).includes(id)), oldPic) && (await snap(ann)).chat.find(m => (m.attachments || []).includes(oldPic)).id;
    // 55 newer messages from the host, written while the server is stopped, push it out of the 50-message window.
    const port = new URL(A.localUrl).port, stFile = path.join(A.dir, "state.json");
    s.share(A.dir, "stop");
    const stj = JSON.parse(fs.readFileSync(stFile, "utf8")), n0 = stj.session.seq.M, t0 = stj.chat.at(-1).at;
    for (let i = 1; i <= 55; i++) stj.chat.push({ id: `M${n0 + i}`, pid: "host", text: `Later message ${i}`, at: t0 + i });
    stj.session.seq.M = n0 + 55;
    fs.writeFileSync(stFile, JSON.stringify(stj));
    s.share(A.dir, "ensure-running", "--guest-port", port);
    ok("the message left Bo's chat window", await until(bo, id => window.Core.snapshot()?.chat?.some(m => m.text === "Later message 55") && !window.Core.snapshot().chat.some(m => m.id === id && !m.gapAbove) , oldMsg, 30000));
    await openChat(bo);
    await bo.evaluate(id => window.Core.chatAround(id), oldMsg);
    const oldTile = (page, id) => page.evaluate(i => {
      const li = [...document.querySelectorAll(".vf-mlist > .vf-msg")].find(x => x._m?.id === i);
      return !li ? "gone" : li.querySelector(".vf-uppic img[src^='data:']") ? "tile" : /Waiting for the host/.test(li.querySelector(".vf-uppic-wait")?.textContent || "") ? "waiting" : "none";
    }, id);
    ok("scrolled back, Bo sees its placeholder", await until(bo, id => {
      const li = [...document.querySelectorAll(".vf-mlist > .vf-msg")].find(x => x._m?.id === id);
      return /Waiting for the host/.test(li?.querySelector(".vf-uppic-wait")?.textContent || "");
    }, oldMsg, 10000), await oldTile(bo, oldMsg));
    await owner.evaluate(id => window.Core.uploadAct(id, "approve"), oldPic);
    ok("after the host's Approve it becomes the picture without a reload", await until(bo, id => {
      const li = [...document.querySelectorAll(".vf-mlist > .vf-msg")].find(x => x._m?.id === id);
      return !!li?.querySelector(".vf-uppic img[src^='data:']");
    }, oldMsg, 15000), await oldTile(bo, oldMsg));
    await owner.evaluate(id => window.Core.uploadAct(id, "remove"), oldPic);
    ok("after the host's Remove it loses the picture without a reload", await until(bo, id => {
      const li = [...document.querySelectorAll(".vf-mlist > .vf-msg")].find(x => x._m?.id === id);
      return !!li && !li.querySelector(".vf-uppic");
    }, oldMsg, 15000), await oldTile(bo, oldMsg));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource|Failed to fetch|ERR_CONNECTION/.test(m)); // the server restarts once
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
