#!/usr/bin/env node
// Long lists in a real browser (triage 48), against `share.sh ensure-running` with the fake cloudflared and 30 guests:
// answer cards show 12, then Show all (30); the Host view's people list shows 25 of 32 with Show more, presence
// chips (All, Here, Away, Offline) and the owner's Removed chip with their counts, and a name search; the queue shows
// its oldest 20; the proposals panel 20, Later 10 and a locked question's suggestions 10, each with Show more; the
// bell 20 with Show more and Unread only; and on a 320 px phone the people chips wrap inside the screen.
//   node plugins/planning/shared/tests/ui_lists.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from triage row 48 (the defaults and filters) and the people, answers and proposals this suite
// makes, never from the page; the bell's totals come from the server's snapshot.
"use strict";
const { loadPlaywright, suite, recorder, until } = require("./browser_harness");

const GUESTS = 30;
const PHONE = { viewport: { width: 320, height: 640 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 };
const wait = ms => new Promise(r => setTimeout(r, ms));
const rows = (page, sel) => page.evaluate(q => document.querySelectorAll(q).length, sel);

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_lists.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_lists"), { ok } = s, rec = recorder(browser);
  let beating = null;
  try {
    const A = await s.start("lists");
    s.apply(A.dir, [{ op: "set-title", title: "List checks" }, { op: "open-round", questions: [{ id: "Q1", text: "Which payment step?", alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } }] }]);
    const base = A.localUrl, owner = { "X-Owner-Token": new URL(A.ownerUrl).hash.replace(/^#owner=/, "") };
    const api = async (path, body, h) => {
      const r = await fetch(base + path.slice(1), { method: "POST", headers: { "Content-Type": "application/json", ...h }, body: JSON.stringify(body) });
      return r.json();
    };
    const guests = [];
    for (let i = 1; i <= GUESTS; i++) {
      const ip = { "CF-Connecting-IP": `198.51.100.${i}` }, out = await api("/api/join", { name: `Guest ${i}`, device: "computer" }, ip);
      guests.push({ pid: out.pid, h: { ...ip, "X-Session-Secret": out.secret } });
    }
    const { id: hello } = await api("/api/chat", { text: "Hello all" }, owner);
    await Promise.all(guests.map((g, i) => api("/api/answer", { qid: "Q1", text: `Answer from Guest ${i + 1}`, device: "computer", view: "focus" }, g.h)));
    // In order, one at a time: the checks below read proposals and replies oldest first.
    for (const [i, g] of guests.entries()) {
      await api("/api/propose", { text: `Proposal from Guest ${i + 1}` }, g.h);
      if (i < 25) await api("/api/chat", { text: `Reply ${i + 1}`, replyTo: hello }, g.h);
    }
    const gone = await api("/api/join", { name: "Gone", device: "computer" }, { "CF-Connecting-IP": "198.51.100.99" });
    await api("/api/person/remove", { pid: gone.pid, on: true }, owner);
    // Presence lives in memory: a restart leaves everyone offline until they beat. Guests 1-10 are here and active,
    // 11-15 here with their tab hidden (Away); the rest stay offline.
    const port = new URL(base).port;
    s.share(A.dir, "stop");
    s.share(A.dir, "ensure-running", "--guest-port", port);
    const beat = () => Promise.all(guests.slice(0, 15).map((g, i) => api("/api/heartbeat", { q: "", visible: i < 10, lastInput: 1, tab: "t" }, g.h).catch(() => {})));
    await beat();
    beating = setInterval(beat, 5000);

    const host = await rec.open(A.ownerUrl);
    await until(host, () => window.Core.snapshot()?.me?.role === "owner");

    // ---------- answer cards ----------
    await until(host, () => document.querySelectorAll(".vf-alist > li").length > 0);
    ok("a question shows 12 answer cards, then Show all (30)", await until(host, () => document.querySelectorAll(".vf-alist > li").length === 12
      && [...document.querySelectorAll(".vf-more-foot:not([hidden]) button")].some(b => b.textContent === "Show all (30)")), String(await rows(host, ".vf-alist > li")));
    await host.locator(".vf-more-foot button", { hasText: "Show all (30)" }).click();
    ok("Show all shows all 30", await until(host, () => document.querySelectorAll(".vf-alist > li").length === 30));

    // ---------- the Host view's people ----------
    const viewSeg = async label => {
      const b = host.locator(".vf-bar .vf-seg-btn", { hasText: label }), more = host.locator(".vf-viewopts");
      if (!(await b.isVisible()) && (await more.isVisible())) await more.click();
      await b.click({ timeout: 5000 });
    };
    await viewSeg("Host");
    const chipText = () => host.evaluate(() => [...document.querySelectorAll(".vf-pfilters .vf-fchip:not([hidden])")].map(b => b.textContent).join(" "));
    ok("the people chips count All 32, Here 16, Away 5, Offline 15 and the owner's Removed 1", await until(host, () =>
      [...document.querySelectorAll(".vf-pfilters .vf-fchip:not([hidden])")].map(b => b.textContent).join(" ") === "All32 Here16 Away5 Offline15 Removed1"), await chipText());
    ok("the people list shows 25 of 32", await until(host, () => document.querySelectorAll(".vf-hpeople > li").length === 25
      && [...document.querySelectorAll(".vf-more-foot:not([hidden])")].some(f => f.textContent.startsWith("Showing 25 of 32"))), String(await rows(host, ".vf-hpeople > li")));
    await host.locator(".vf-hpeople + .vf-more-foot button").click();
    ok("Show more shows all 32 and moves focus to the 26th", await until(host, () => document.querySelectorAll(".vf-hpeople > li").length === 32
      && document.querySelectorAll(".vf-hpeople > li")[25].contains(document.activeElement)));
    await host.locator(".vf-pfilters .vf-fchip", { hasText: "Away" }).click();
    ok("Away shows the 5 whose tabs are hidden", await until(host, () => {
      const li = [...document.querySelectorAll(".vf-hpeople > li")];
      return li.length === 5 && li.every(x => x.dataset.presence === "away");
    }), String(await rows(host, ".vf-hpeople > li")));
    await host.locator(".vf-pfilters .vf-fchip", { hasText: "Removed" }).click();
    ok("Removed shows the removed guest", await until(host, () => [...document.querySelectorAll(".vf-hpeople > li")].map(x => x.querySelector(".vf-hp-name").textContent).join() === "Gone"));
    await host.locator(".vf-pfilters .vf-fchip", { hasText: "All" }).click();
    ok("a name search shows past 12 people", await host.locator(".vf-pfind").isVisible());
    await host.fill(".vf-pfind", "Guest 1");
    ok("searching Guest 1 finds Guest 1 and Guest 10 to 19", await until(host, () => document.querySelectorAll(".vf-hpeople > li").length === 11), String(await rows(host, ".vf-hpeople > li")));
    await host.fill(".vf-pfind", "");

    // ---------- the queue ----------
    ok("the queue shows its oldest 20 of 30 proposals", await until(host, () => {
      const li = [...document.querySelectorAll(".vf-queue > li")];
      return li.length === 20 && li[0].textContent.includes("Proposal from Guest 1") && !li.some(x => /Proposal from Guest (2[1-9]|30)\b/.test(x.textContent));
    }), String(await rows(host, ".vf-queue > li")));
    await host.locator(".vf-queue + .vf-more-foot button").click();
    ok("Show more shows the other 10", await until(host, () => document.querySelectorAll(".vf-queue > li").length === 30));

    // ---------- the bell ----------
    const notes = await host.evaluate(() => window.Core.snapshot().me.notifications);
    const firstN = Math.min(20, notes.length);
    await host.click(".vf-bell");
    await host.click(".vf-ixtabs [data-k=notes]");
    ok(`the bell shows ${firstN} of its ${notes.length} notifications`, notes.length > 20 && await until(host, n => document.querySelectorAll(".vf-nlist > li").length === n, firstN), String(await rows(host, ".vf-nlist > li")));
    await host.locator(".vf-nlist + .vf-more-foot button").click();
    ok("Show more shows the next 20", await until(host, n => document.querySelectorAll(".vf-nlist > li").length === n, Math.min(40, notes.length)));
    const readIds = notes.slice(-5).map(n => n.id);
    await api("/api/notifications/read", { ids: readIds }, owner);
    await until(host, ids => window.Core.snapshot().me.notifications.filter(n => ids.includes(n.id)).every(n => n.read), readIds);
    const unread = (await host.evaluate(() => window.Core.snapshot().me.notifications)).filter(n => !n.read).length;
    await host.locator(".vf-bptools button", { hasText: "Unread only" }).click();
    ok("Unread only leaves the unread ones", await until(host, n => document.querySelectorAll(".vf-nlist > li").length === Math.min(20, n)
      && !document.querySelector(".vf-nlist .vf-nitem:not(.vf-nunread)") && document.querySelector(".vf-bptools button").getAttribute("aria-pressed") === "true", unread));
    await host.keyboard.press("Escape");

    // ---------- the proposals panel and Later ----------
    await host.locator(".vf-proprow", { hasText: "Proposed" }).click();
    ok("the proposals panel shows 20 of 30 new", await until(host, () => document.querySelectorAll(".vf-panel:not([hidden]) .vf-plist > li").length === 20));
    await host.locator(".vf-panel:not([hidden]) .vf-more-foot button").click();
    ok("Show more there shows all 30", await until(host, () => document.querySelectorAll(".vf-panel:not([hidden]) .vf-plist > li").length === 30));
    await host.keyboard.press("Escape");
    const props = (await host.evaluate(() => window.Core.snapshot().proposals)).slice(0, 12);
    for (const p of props) { await api("/api/proposal/act", { id: p.id, action: "later", reason: "Off the goal" }, owner); await wait(1050); }
    ok("Later shows 10 of 12", await until(host, () => document.querySelectorAll(".vf-laterlist > li").length === 10), String(await rows(host, ".vf-laterlist > li")));
    await host.locator(".vf-laterlist + .vf-more-foot button").click();
    ok("Show more there shows all 12", await until(host, () => document.querySelectorAll(".vf-laterlist > li").length === 12));

    // ---------- a locked question's suggestions ----------
    await api("/api/lock", { qid: "Q1", card: `p:${guests[0].pid}` }, owner);
    await Promise.all(guests.slice(0, 12).map((g, i) => api("/api/suggest", { qid: "Q1", text: `Suggestion ${i + 1}` }, g.h)));
    await viewSeg("Focus");
    ok("a locked question shows 10 of its 12 suggestions", await until(host, () => document.querySelectorAll(".vf-slist > li").length === 10), String(await rows(host, ".vf-slist > li")));
    await host.locator(".vf-slist + .vf-more-foot button").click();
    ok("Show more there shows all 12", await until(host, () => document.querySelectorAll(".vf-slist > li").length === 12));

    // ---------- the people chips on a 320 px phone ----------
    const phone = await rec.open(A.ownerUrl, { context: PHONE });
    await until(phone, () => window.Core.snapshot()?.me?.role === "owner");
    await phone.locator(".vf-tab", { hasText: "More" }).click();
    await phone.locator(".vf-msitem", { hasText: "Host view" }).click();
    ok("on a 320 px phone every people chip sits inside the screen, wrapped, with no sideways scroll", await until(phone, () => {
      const chips = [...document.querySelectorAll(".vf-pfilters .vf-fchip:not([hidden])")].map(b => b.getBoundingClientRect());
      const apart = chips.every((a, i) => chips.slice(i + 1).every(b => a.right <= b.left + 0.5 || b.right <= a.left + 0.5 || a.bottom <= b.top + 0.5 || b.bottom <= a.top + 0.5));
      return chips.length === 5 && chips.every(r => r.left >= 0 && r.right <= 320 && r.width > 0) && apart && document.documentElement.scrollWidth <= 320;
    }), await phone.evaluate(() => JSON.stringify([...document.querySelectorAll(".vf-pfilters .vf-fchip:not([hidden])")].map(b => { const r = b.getBoundingClientRect(); return [Math.round(r.left), Math.round(r.right)]; }))));

    ok("no page errors", rec.errors.length === 0, rec.errors.join(" | "));
  } catch (e) {
    ok(`ran without throwing: ${e.message}`, false);
  } finally {
    clearInterval(beating);
    await browser.close();
  }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
