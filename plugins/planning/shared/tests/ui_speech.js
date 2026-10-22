#!/usr/bin/env node
// Read aloud and dictation, against `share.sh ensure-running` with the fake cloudflared, with the page's
// speechSynthesis and SpeechRecognition replaced by recording stubs before the page loads: both switches sit in the
// person's own settings, off by default, and are kept with their other preferences on the server; turning them on
// moves nothing on the question; Read aloud speaks the question, then its options as shown, and nothing else (never an
// answer the owner has not shared); a second press or Escape stops it; it is a keyboard-reachable button with a name;
// Dictate fills its own box at the caret and sends nothing; turning Dictate on shows a one-line disclosure; where the
// browser offers on-device recognition a press asks for it, words heard that way take the disclosure away, and a
// device that cannot take the language falls back to the browser's service with the disclosure kept; the page never
// calls SpeechRecognition.available(); without the API the Dictate switch and buttons never show.
//   node plugins/planning/shared/tests/ui_speech.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the issue's acceptance list, the texts this suite writes, and the server's own "Something
// else…" option (session.py OTHER_OPTION, the contract every choice question carries), never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const q = (id, text, format) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format });
const opts = (...labels) => labels.map((label, i) => ({ id: `opt-${i + 1}`, label }));
const QS = [
  q("Q1", "Which default payment method?", { kind: "choice", options: opts("Card", "Saved method") }),
  q("Q2", "Where should the order summary sit?", { kind: "text" }),
];
const textOf = id => QS.find(x => x.id === id).text;
const BO_ANSWER = "Bo thinks under the total";
const DISCLOSURE = "Your browser may send what you say to its maker's speech service to turn it into text.";

/** Runs in the page before its scripts: recording stand-ins for the Web Speech API, or none of it. */
function stubSpeech(cfg) {
  const log = window.__speech = { spoken: [], cancels: 0, recs: [] };
  if (cfg.tts) {
    window.SpeechSynthesisUtterance = class { constructor(text) { this.text = text; this.voice = null; this.onend = null; this.onerror = null; } };
    const synth = {
      speaking: false, pending: false, paused: false,
      speak(u) { log.spoken.push(u.text); }, cancel() { log.cancels++; }, getVoices() { return []; },
      pause() {}, resume() {}, addEventListener() {}, removeEventListener() {},
    };
    Object.defineProperty(window, "speechSynthesis", { value: synth, configurable: true });
  }
  delete window.SpeechRecognition; delete window.webkitSpeechRecognition;
  if (cfg.sr) {
    class Rec {
      constructor() { this.started = false; this.ended = false; log.recs.push(this); }
      start() {
        this.started = true;
        // a device without this language: the error MDN names, then the session ends
        if (cfg.local === "missing" && this.processLocally) setTimeout(() => { this.onerror?.({ error: "language-not-supported" }); this.end(); }, 0);
      }
      stop() { this.end(); }
      abort() { this.end(); }
      end() { if (!this.ended) { this.ended = true; this.onend?.(); } }
      /** The test's voice: one final result, then the session ends, as a one-shot recognition does. */
      say(words) { this.onresult?.({ results: [Object.assign([{ transcript: words, confidence: 0.9 }], { isFinal: true })] }); this.end(); }
    }
    // processLocally exists only where the browser offers on-device recognition; available() only records a call
    if (cfg.local) Rec.prototype.processLocally = false;
    Rec.available = () => { log.available = (log.available || 0) + 1; return Promise.resolve("available"); };
    window.SpeechRecognition = Rec;
  }
}

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_speech.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_speech"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("speech");
    s.apply(A.dir, [{ op: "set-title", title: "Checkout" }, { op: "open-round", questions: QS }]);
    const desk = { viewport: { width: 1440, height: 900 } };
    const owner = await rec.open(A.ownerUrl, { context: desk });
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    // Bo answers Q2 first; the session holds every answer for the owner's Share, so Ann never sees it.
    const bo = await rec.open(A.localUrl, { context: desk });
    await joinAs(bo, "Bo");
    await bo.locator(".vf-q", { hasText: textOf("Q2") }).first().click();
    await until(bo, t => document.querySelector(".vf-qtext")?.textContent === t, textOf("Q2"));
    await bo.fill("#vf-answer", BO_ANSWER);
    await bo.keyboard.press("Control+Enter");
    ok("Bo's answer to Q2 is saved", await until(bo, () => (window.Core.snapshot()?.cards?.Q2 || []).some(c => c.pid === window.Core.me.cid)));

    const ann = await rec.open(A.localUrl, { context: desk, init: { fn: stubSpeech, arg: { tts: true, sr: true } } });
    const posts = [];
    ann.on("request", r => { if (r.method() === "POST") posts.push(new URL(r.url()).pathname); });
    await joinAs(ann, "Ann");
    const go = async id => { await ann.locator(".vf-q", { hasText: textOf(id) }).first().click(); return until(ann, t => document.querySelector(".vf-qtext")?.textContent === t, textOf(id)); };
    const log = () => ann.evaluate(() => ({ spoken: [...window.__speech.spoken], cancels: window.__speech.cancels, recs: window.__speech.recs.length }));
    const shown = sel => ann.evaluate(sel => [...document.querySelectorAll(sel)].some(e => e.getClientRects().length > 0), sel);
    const qTop = () => ann.evaluate(() => document.querySelector(".vf-qtext").getBoundingClientRect().top);
    await go("Q1");

    // ---------- off by default ----------
    ok("off by default: no Read aloud and no Dictate button shows", !(await shown(".vf-readbtn")) && !(await shown(".vf-dictate")));
    await ann.click(".vf-person-me");
    const readSw = ann.locator(".vf-pcard .vf-readsw"), dictSw = ann.locator(".vf-pcard .vf-dictsw");
    ok("my settings hold both switches, each a switch and off", await until(ann, () => !!document.querySelector(".vf-pcard .vf-dictsw"))
      && (await readSw.textContent()) === "Read questions aloud" && (await dictSw.textContent()) === "Dictate answers and comments"
      && (await readSw.getAttribute("role")) === "switch" && (await readSw.getAttribute("aria-checked")) === "false"
      && (await dictSw.getAttribute("role")) === "switch" && (await dictSw.getAttribute("aria-checked")) === "false");
    ok("no disclosure while Dictate is off", !(await shown(".vf-dictnote")));
    const prefsNow = () => ann.evaluate(() => window.Core.snapshot()?.me?.prefs || {});
    ok("neither is in my server preferences yet", !("readAloud" in await prefsNow()) && !("dictate" in await prefsNow()));

    // ---------- toggle on, by keyboard; kept on the server; nothing on the question moves ----------
    const topOff = await qTop();
    await readSw.focus(); await ann.keyboard.press("Enter");
    await ann.locator(".vf-pcard .vf-dictsw").focus(); await ann.keyboard.press("Space");
    ok("Enter and Space turn the switches on", (await ann.locator(".vf-pcard .vf-readsw").getAttribute("aria-checked")) === "true"
      && (await ann.locator(".vf-pcard .vf-dictsw").getAttribute("aria-checked")) === "true");
    ok("the server keeps both in my preferences", await until(ann, () => { const p = window.Core.snapshot()?.me?.prefs || {}; return p.readAloud === true && p.dictate === true; }, null, 5000));
    const note = ann.locator(".vf-pcard .vf-dictnote");
    ok("turning Dictate on shows the one-line disclosure, tied to the switch", (await note.textContent()) === DISCLOSURE
      && (await ann.locator(".vf-pcard .vf-dictsw").getAttribute("aria-describedby")) === (await note.getAttribute("id")));
    await ann.keyboard.press("Escape");
    ok("the Read aloud and Dictate buttons now show", await until(ann, () => !!document.querySelector(".vf-readbtn:not([hidden])")) && await shown("#vf-answer ~ .vf-crow .vf-dictate"));
    ok("turning them on leaves the question where it was", Math.abs((await qTop()) - topOff) < 0.5, `${topOff} -> ${await qTop()}`);
    const readBtn = ann.locator(".vf-readbtn");
    ok("Read aloud is a button named for what it does", (await readBtn.evaluate(b => b.tagName)) === "BUTTON" && (await readBtn.getAttribute("aria-label")) === "Read the question aloud"
      && (await readBtn.getAttribute("aria-pressed")) === "false");

    // ---------- read order: the question, then its options; a second press stops ----------
    const box0 = await readBtn.boundingBox();
    await readBtn.focus(); await ann.keyboard.press("Enter");
    const wantQ1 = [textOf("Q1"), "Card", "Saved method", "Something else…"];
    const l1 = await log();
    ok("Read aloud speaks the question, then its options, in order", JSON.stringify(l1.spoken) === JSON.stringify(wantQ1), JSON.stringify(l1.spoken));
    ok("while reading it is pressed and says it stops", (await readBtn.getAttribute("aria-pressed")) === "true" && (await readBtn.getAttribute("aria-label")) === "Stop reading aloud");
    const box1 = await readBtn.boundingBox();
    ok("pressing it does not move or resize it", ["x", "y", "width", "height"].every(k => Math.abs(box0[k] - box1[k]) < 0.5), JSON.stringify([box0, box1]));
    await readBtn.click();
    const l2 = await log();
    ok("a second press stops it", l2.cancels > l1.cancels && (await readBtn.getAttribute("aria-pressed")) === "false" && l2.spoken.length === wantQ1.length);

    // ---------- Escape stops it, even from inside the answer box ----------
    await readBtn.click();
    await ann.click("#vf-answer");
    const l3 = await log();
    await ann.keyboard.press("Escape");
    const l4 = await log();
    ok("Escape stops it from inside the answer box", l4.cancels > l3.cancels && (await readBtn.getAttribute("aria-pressed")) === "false");

    // ---------- only what is on screen for me: Bo's unshared answer is never spoken ----------
    await go("Q2");
    const before = (await log()).spoken.length;
    await readBtn.click();
    const l5 = (await log()).spoken.slice(before);
    ok("on a written question it speaks the question alone, never Bo's unshared answer", JSON.stringify(l5) === JSON.stringify([textOf("Q2")]) && !l5.some(t => t.includes(BO_ANSWER)), JSON.stringify(l5));
    await readBtn.click();

    // ---------- dictation fills the box at the caret and sends nothing ----------
    await ann.fill("#vf-answer", "I'd say");
    const mic = ann.locator("#vf-answer ~ .vf-crow .vf-dictate");
    ok("Dictate is a button named for its box", (await mic.evaluate(b => b.tagName)) === "BUTTON" && (await mic.getAttribute("aria-label")) === "Dictate your answer");
    const sentBefore = posts.length;
    await mic.click();
    ok("a press starts recognition and shows it is listening", (await log()).recs === 1 && await ann.evaluate(() => window.__speech.recs[0].started)
      && (await mic.getAttribute("aria-pressed")) === "true" && (await mic.getAttribute("aria-label")) === "Stop dictating");
    ok("where the browser offers no on-device recognition it does not ask for it", await ann.evaluate(() => window.__speech.recs[0].processLocally === undefined));
    await ann.evaluate(() => window.__speech.recs[0].say("pay by card"));
    ok("the words land in the answer box after what I typed, still editable", (await ann.inputValue("#vf-answer")) === "I'd say pay by card"
      && await ann.evaluate(() => document.activeElement?.id === "vf-answer" && !document.getElementById("vf-answer").disabled));
    ok("when it ends the button is off again", (await mic.getAttribute("aria-pressed")) === "false" && (await mic.getAttribute("aria-label")) === "Dictate your answer");
    await ann.waitForTimeout(1500);
    const sent = posts.slice(sentBefore).filter(p => ["/api/answer", "/api/pick", "/api/discussion"].includes(p));
    ok("dictation sent nothing", !sent.length && !(await ann.evaluate(() => (window.Core.snapshot()?.cards?.Q2 || []).some(c => c.pid === window.Core.me.cid))), sent.join(","));
    await mic.click();
    await mic.click();
    ok("a second press stops listening", (await mic.getAttribute("aria-pressed")) === "false" && await ann.evaluate(() => window.__speech.recs[1].ended));

    // ---------- the comment box has its own ----------
    await ann.click(".vf-disc-head");
    const cmic = ann.locator(".vf-disc-form .vf-dictate");
    await until(ann, () => !!document.querySelector(".vf-disc-form .vf-dictate")?.getClientRects().length);
    ok("the comment box has a Dictate button named for it", (await cmic.getAttribute("aria-label")) === "Dictate a comment");
    const cBefore = posts.length;
    await cmic.click();
    await ann.evaluate(() => window.__speech.recs.at(-1).say("looks good"));
    ok("dictated words fill the comment box and nothing is posted", (await ann.inputValue(".vf-disc-ta")) === "looks good" && !posts.slice(cBefore).includes("/api/discussion"));

    // ---------- turning them off hides both again ----------
    await ann.click(".vf-person-me");
    await ann.locator(".vf-pcard .vf-readsw").click();
    await ann.locator(".vf-pcard .vf-dictsw").click();
    await ann.keyboard.press("Escape");
    ok("turned off, neither button shows", await until(ann, () => !document.querySelector(".vf-readbtn:not([hidden]), .vf-dictate:not([hidden])")));

    // ---------- on-device offered: asked for first; words heard that way take the disclosure away ----------
    const dictateOnQ2 = async (page, name, local) => {
      await joinAs(page, name);
      await page.evaluate(() => window.Core.savePrefs({ dictate: true }));
      await page.locator(".vf-q", { hasText: textOf("Q2") }).first().click();
      await until(page, () => !!document.querySelector("#vf-answer ~ .vf-crow .vf-dictate:not([hidden])"));
      const card = async () => { await page.click(".vf-person-me"); await until(page, () => !!document.querySelector(".vf-pcard .vf-dictsw")); const n = await page.evaluate(() => document.querySelector(".vf-pcard .vf-dictnote")?.textContent || ""); await page.keyboard.press("Escape"); return n; };
      return card;
    };
    const cal = await rec.open(A.localUrl, { context: desk, init: { fn: stubSpeech, arg: { tts: true, sr: true, local: "ready" } } });
    const calCard = await dictateOnQ2(cal, "Cal");
    ok("before on-device is confirmed, Dictate on shows the disclosure", (await calCard()) === DISCLOSURE);
    await cal.locator("#vf-answer ~ .vf-crow .vf-dictate").click();
    ok("a press asks for on-device recognition", await cal.evaluate(() => window.__speech.recs.at(-1)?.processLocally === true));
    await cal.evaluate(() => window.__speech.recs.at(-1).say("ship it"));
    ok("words heard on the device fill the box and take the disclosure away", (await cal.inputValue("#vf-answer")) === "ship it" && (await calCard()) === "");
    ok("the page never asked SpeechRecognition.available()", await cal.evaluate(() => !window.__speech.available));

    // ---------- on-device offered but this language is not on the device: falls back, disclosure kept ----------
    const eve = await rec.open(A.localUrl, { context: desk, init: { fn: stubSpeech, arg: { tts: true, sr: true, local: "missing" } } });
    const eveCard = await dictateOnQ2(eve, "Eve");
    await eve.locator("#vf-answer ~ .vf-crow .vf-dictate").click();
    ok("a device without the language falls back to a second session not on the device", await until(eve, () => window.__speech.recs.length === 2
      && window.__speech.recs[0].processLocally === true && window.__speech.recs[1].processLocally === false && window.__speech.recs[1].started));
    await eve.waitForTimeout(400);
    ok("still listening, with no error shown", (await eve.locator("#vf-answer ~ .vf-crow .vf-dictate").getAttribute("aria-pressed")) === "true"
      && !(await eve.evaluate(() => /dictat/i.test(document.querySelector(".vf-toast")?.textContent || ""))));
    await eve.evaluate(() => window.__speech.recs[1].say("later"));
    ok("its words fill the box and the disclosure stays", (await eve.inputValue("#vf-answer")) === "later" && (await eveCard()) === DISCLOSURE);

    // ---------- no SpeechRecognition: no Dictate switch or button, even with the pref on ----------
    const dee = await rec.open(A.localUrl, { context: desk, init: { fn: stubSpeech, arg: { tts: true, sr: false } } });
    ok("the page has no SpeechRecognition", await dee.evaluate(() => !("SpeechRecognition" in window) && !("webkitSpeechRecognition" in window)));
    await joinAs(dee, "Dee");
    await dee.evaluate(() => window.Core.savePrefs({ dictate: true, readAloud: true }));
    await dee.locator(".vf-q", { hasText: textOf("Q2") }).first().click();
    ok("Read aloud still shows", await until(dee, () => !!document.querySelector(".vf-readbtn:not([hidden])")));
    ok("no Dictate button shows", !(await dee.evaluate(() => [...document.querySelectorAll(".vf-dictate")].some(e => e.getClientRects().length > 0))));
    await dee.click(".vf-person-me");
    await until(dee, () => !!document.querySelector(".vf-pcard .vf-readsw"));
    ok("my settings offer no Dictate switch", !(await dee.evaluate(() => !!document.querySelector(".vf-pcard .vf-dictsw"))));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
