#!/usr/bin/env node
// Attach and paste on every place people write, against `share.sh ensure-running` with the fake cloudflared: with
// Uploads off a pasted picture adds nothing; on, the answer box, Ask Claude, chat, the Discussion and Propose each show
// an Attach button, and a picture pasted into each (a ClipboardEvent carrying an image File) becomes a thumbnail chip
// reading "Waiting for the host", never text in the field; sending waits until the host accepts it; once accepted and
// received, the picture shows as a tile to another guest who sees what carries it and opens in the viewer, while a
// proposal, a request and a hidden comment keep theirs from that guest.
//   node plugins/planning/shared/tests/ui_attach_paste.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the approved spec (attach and paste on every text input; accepted pictures shown to
// everyone who sees their item) and the texts this suite writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, snap, joinAs } = require("./browser_harness");

const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "gather", format: { kind: "text" } });
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
  ask: async page => { if (await page.evaluate(() => document.querySelector(".vf-apform")?.offsetParent === null)) await page.click(".vf-asktop"); return until(page, () => !!document.querySelector("#vf-ap-ta")?.offsetParent); },
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
    s.apply(A.dir, [{ op: "set-title", title: "Checkout" }, { op: "open-round", questions: [q("Q1", "Where should the order summary sit?")] }]);
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

    await owner.evaluate(() => window.Core.saveSettings({ uploads: true }));
    await until(ann, () => window.Core.state.settings.uploads === true);

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

    // ---------- Bo sees the pictures where he sees their items, as tiles that open the viewer ----------
    await openChat(bo);
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

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
