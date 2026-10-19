#!/usr/bin/env node
// Chat beyond the snapshot's window in a real browser (triage 48), against `share.sh ensure-running` with the fake
// cloudflared and 120 seeded messages: a guest's snapshot holds the newest 50; a notification and a reply quote that
// point at a message outside them open the chat at it; the "Load earlier messages" button works from the keyboard and
// keeps focus; scrolling to the top loads the rest and keeps the message the reader was looking at in place; and 60
// messages that arrive while the page is frozen all count as unread.
//   node plugins/planning/shared/tests/ui_chat_history.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from triage row 48 (50 in the window, Load earlier, kept position) and the messages this suite
// seeds and posts, never from the page.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const SEEDED = 120, WINDOW = 50;
const msgCount = page => page.evaluate(() => document.querySelectorAll(".vf-mlist > .vf-msg").length);

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_chat_history.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_chat_history"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("history");
    s.apply(A.dir, [{ op: "set-title", title: "History checks" }]);
    const first = await rec.open(A.localUrl);
    const gusPid = await joinAs(first, "Gus");
    const ctx = first.context();
    await first.close();
    // Seed while stopped: M1 mentions Gus (his bell links it), M2..M119 from the host, M120 replies to M1.
    const port = new URL(A.localUrl).port;
    s.share(A.dir, "stop");
    const file = path.join(A.dir, "state.json"), st = JSON.parse(fs.readFileSync(file, "utf8"));
    const t0 = Date.now() / 1000 - SEEDED * 30;
    st.chat = Array.from({ length: SEEDED }, (_, i) => ({ id: `M${i + 1}`, pid: "host", text: `Seeded message ${i + 1}`, at: t0 + i * 20 }));
    st.chat[119].replyTo = { id: "M1", pid: "host", excerpt: "Seeded message 1" };
    st.session.seq.M = SEEDED;
    st.session.seq.N = (st.session.seq.N || 0) + 1;
    (st.notifications[gusPid] ||= []).push({ id: `N${st.session.seq.N}`, kind: "mention", title: "mentioned you in chat.", at: t0, read: false, by: "host", body: "Seeded message 1", msg: "M1" });
    fs.writeFileSync(file, JSON.stringify(st));
    s.share(A.dir, "ensure-running", "--guest-port", port);
    const open = async () => {
      const p = await rec.openIn(ctx, A.localUrl);
      await until(p, () => !!window.Core.snapshot()?.me);
      return p;
    };

    // ---------- the window ----------
    let gus = await open();
    const sn = await gus.evaluate(() => { const x = window.Core.snapshot(); return { n: x.chat.length, first: x.chat[0].id, before: x.chatBefore }; });
    ok(`a guest's snapshot holds the newest ${WINDOW} messages and a cursor to the older ones`, sn.n === WINDOW && sn.first === "M71" && sn.before === "M71", JSON.stringify(sn));

    // ---------- a notification to a message outside the window ----------
    await gus.click(".vf-bell");
    await gus.locator(".vf-nitem", { hasText: "mentioned you in chat." }).click();
    const ringedM1 = () => {
      const li = [...document.querySelectorAll(".vf-mlist > .vf-msg")].find(x => x._m?.id === "M1"), box = document.querySelector(".vf-mscroll").getBoundingClientRect();
      const r = li?.getBoundingClientRect();
      return !!li && li.classList.contains("vf-hl") && r.top >= box.top - 1 && r.bottom <= box.bottom + 1;
    };
    ok("the bell's link to a message outside the window opens the chat at it, ringed and in view", await until(gus, ringedM1), await gus.evaluate(() => {
      const li = [...document.querySelectorAll(".vf-mlist > .vf-msg")].find(x => x._m?.id === "M1"), box = document.querySelector(".vf-mscroll").getBoundingClientRect();
      return JSON.stringify({ has: !!li, hl: li?.className, r: li?.getBoundingClientRect().top, box: [box.top, box.bottom], n: document.querySelectorAll(".vf-mlist > .vf-msg").length, st: document.querySelector(".vf-mscroll").scrollTop });
    }));
    ok("a Load earlier row marks the gap between the messages around it and the newest ones", await gus.evaluate(() => [...document.querySelectorAll(".vf-mlist > .vf-mgap")].some(g => g.previousElementSibling?.classList.contains("vf-msg"))));

    // ---------- a reply quote to a message outside the window ----------
    await gus.close();
    gus = await open();
    await gus.click(".vf-fab");
    await until(gus, () => document.querySelectorAll(".vf-mlist > .vf-msg").length >= 50);
    await gus.locator(".vf-mlist > .vf-msg", { hasText: "Seeded message 120" }).locator(".vf-mquote").click();
    ok("a reply's quote of a message outside the window goes to it", await until(gus, ringedM1));

    // ---------- the keyboard button ----------
    await gus.close();
    gus = await open();
    await gus.click(".vf-fab");
    await until(gus, n => document.querySelectorAll(".vf-mlist > .vf-msg").length === n, WINDOW);
    ok("the chat log keeps role=log", await gus.evaluate(() => document.querySelector(".vf-mlist").getAttribute("role") === "log"));
    const top = gus.locator(".vf-mlist > .vf-mgap:first-child button");
    ok("a focusable Load earlier messages button sits at the top", (await top.count()) === 1 && (await top.textContent()) === "Load earlier messages");
    await top.evaluate(b => b.focus({ preventScroll: true }));
    await gus.keyboard.press("Enter");
    ok("Enter on it loads the 50 before them", await until(gus, n => document.querySelectorAll(".vf-mlist > .vf-msg").length === n, 2 * WINDOW), String(await msgCount(gus)));
    ok("focus stays on the button while there is more to load", await gus.evaluate(() => document.activeElement?.textContent === "Load earlier messages"));
    ok("the load is announced once, not message by message", await until(gus, () => document.querySelector(".vf-sr")?.textContent === "50 earlier messages loaded."));

    // ---------- scrolling up loads the rest and keeps the reader's place ----------
    const before = await gus.evaluate(() => {
      const box = document.querySelector(".vf-mscroll");
      box.scrollTop = 0;
      const li = [...document.querySelectorAll(".vf-mlist > .vf-msg")].find(x => x.textContent.includes("Seeded message 21"));
      return li.getBoundingClientRect().top;
    });
    ok("scrolling to the top loads the oldest messages by itself", await until(gus, n => document.querySelectorAll(".vf-mlist > .vf-msg").length === n, SEEDED), String(await msgCount(gus)));
    // Read once the message holds still for 250 ms of frames (5 s at most): the load moves it, and the page puts it back.
    const after = await gus.evaluate(() => new Promise(res => {
      const top = () => [...document.querySelectorAll(".vf-mlist > .vf-msg")].find(x => x.textContent.includes("Seeded message 21")).getBoundingClientRect().top;
      const t0 = performance.now();
      let last = top(), since = t0;
      const f = now => {
        const v = top();
        if (v !== last) { last = v; since = now; }
        if (now - since >= 250 || now - t0 > 5000) res(v); else requestAnimationFrame(f);
      };
      requestAnimationFrame(f);
    }));
    ok("the message the reader was looking at stays where it was", Math.abs(after - before) <= 4, `${before} -> ${after}`);
    ok("at the start of the chat no Load earlier row is left", await gus.evaluate(() => !document.querySelector(".vf-mlist > .vf-mgap")));

    // ---------- someone else's reaction on a loaded message outside the window reaches it ----------
    const reacter = { "Content-Type": "application/json", "CF-Connecting-IP": "198.51.100.40" };
    reacter["X-Session-Secret"] = (await (await fetch(`${A.localUrl}api/join`, { method: "POST", headers: reacter, body: JSON.stringify({ name: "Reacter", device: "computer" }) })).json()).secret;
    const reacted = await fetch(`${A.localUrl}api/chat/react`, { method: "POST", headers: reacter, body: JSON.stringify({ id: "M5", emoji: "👍", on: true }) });
    ok("another person reacts to M5, outside the window", reacted.status === 200, reacted.status);
    ok("  and the page holding M5 shows that reaction", await until(gus, () => (window.Core.state.chat.find(m => m.id === "M5")?.reactions?.["👍"] || []).length === 1),
      await gus.evaluate(() => JSON.stringify(window.Core.state.chat.find(m => m.id === "M5")?.reactions)));

    // ---------- 60 arrivals while frozen all count as unread ----------
    await gus.click(".vf-fab"); // close the chat
    const posters = [];
    for (let i = 1; i <= 6; i++) {
      const r = await fetch(`${A.localUrl}api/join`, { method: "POST", headers: { "Content-Type": "application/json", "CF-Connecting-IP": `198.51.100.${i}` }, body: JSON.stringify({ name: `Poster ${i}`, device: "computer" }) });
      posters.push({ "Content-Type": "application/json", "X-Session-Secret": (await r.json()).secret, "CF-Connecting-IP": `198.51.100.${i}` });
    }
    const cdp = await gus.context().newCDPSession(gus);
    await cdp.send("Page.setWebLifecycleState", { state: "frozen" });
    const wait = ms => new Promise(r => setTimeout(r, ms));
    await Promise.all(posters.map(async h => { for (let k = 1; k <= 10; k++) { await fetch(`${A.localUrl}api/chat`, { method: "POST", headers: h, body: JSON.stringify({ text: `Arrival ${k}` }) }); await wait(1100); } }));
    await cdp.send("Page.setWebLifecycleState", { state: "active" });
    ok("60 messages that arrived while frozen, more than one window, all count as unread", await until(gus, () => document.querySelector(".vf-fab").getAttribute("aria-label") === "Open chat, 60 unread", null, 10000),
      await gus.evaluate(() => document.querySelector(".vf-fab").getAttribute("aria-label")));

    ok("no page errors", rec.errors.length === 0, rec.errors.join(" | "));
  } catch (e) {
    ok(`ran without throwing: ${e.message}`, false);
  } finally {
    await browser.close();
  }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
