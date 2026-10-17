#!/usr/bin/env node
// The Brief's acceptance criteria in real browsers, against `share.sh ensure-running` with the fake cloudflared:
// the join dialog says answers are saved on the host's computer and read by Claude when a round is sent and the side
// chat is not sent; a refused join (rate-limited, session full) shows the reason and a retry; two guests see each
// other's current question and typing within about 2 seconds; Claude's suggestion cards wait behind "Show Claude's
// take (N)" until the person answers or votes, a chosen card always shows, and Always show shows them; WHILE a question
// is locked its composer is disabled and says how to suggest a change; a changed locked answer flags its dependents
// "Needs review" naming the changed question; WHILE uploads are off no upload control appears; answers and the Claude
// thread sit side by side on desktop and as two tabs on phones; on phones the header is one row, the composer one line
// with send inside it, and the question and answers take at least ~70% of the height; long text clamps with Show more
// and opens in a reader, and chat shows a character count; the owner and leaders get a Host view (people, queue, round
// status, links, goal, Later) and a guest does not; IF the server drops, pages show "Reconnecting…", keep unsent text
// and recover; IF the tunnel restarts with a new address, the owner view shows "New guest link, share again"; after
// Send a round shows Waiting for Claude (Cancel works, and guests see it reopen), then Claude is working (no cancel),
// then a "Round N is here" toast on the owner's and a guest's page, moving nobody unless Follow is on; a proposal Claude marks "Not placed" shows its
// author the reason; WHILE a session is ended guests see a read-only Tree and new joins are refused; Focus, Compare and
// Tree show the same live data and Compare marks off-screen columns; new answers are announced; answers stay visible at
// 200% zoom.
//   node plugins/planning/shared/tests/ui_acceptance.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the Brief's acceptance criteria (PLAN.md), the server contract (error codes, limits) and
// the texts this suite writes, never from the page.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { loadPlaywright, suite, recorder, until, snap, joinAs } = require("./browser_harness");

const PHONE = { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 };
const DESK = { viewport: { width: 1440, height: 900 } };
const MAX_TEXT = 2000; // session.py MAX_TEXT: the longest chat message the server takes
const GOAL = "Pick the offsite venue";
const REC = "Lisbon, by the river.", ALT_A = "Berlin, near the office.", ALT_B = "Porto, small and quiet.";
const Q1T = "Where should the offsite be?", Q2T = "Which hotel near it?", Q3T = "What should the first evening be?";
const tq = (id, text, extra = {}) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" }, ...extra });

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_acceptance.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_acceptance"), { ok } = s, rec = recorder(browser);
  const railQ = (page, text) => page.locator(".vf-q", { hasText: text }).first();
  const qText = page => page.evaluate(() => document.querySelector(".vf-qtext")?.textContent || "");
  const toastHas = (page, re) => until(page, r => new RegExp(r).test(document.querySelector(".vf-toast")?.textContent || ""), re.source, 10000);
  const curStep = page => page.evaluate(() => document.querySelector(".vf-next .vf-steps [aria-current=step]")?.textContent || "");
  try {
    // ================= session A: joining, cards, locks, layout, connection, host view, tunnel =================
    const A = await s.start("acceptance");
    s.apply(A.dir, [{ op: "set-title", title: "Offsite" }, { op: "set-goal", goal: GOAL }, { op: "open-round", questions: [
      tq("Q1", Q1T, { recommendation: REC, alternatives: [{ key: "a", text: ALT_A }, { key: "b", text: ALT_B }] }),
      tq("Q2", Q2T, { dependsOn: ["Q1"] }),
      tq("Q3", Q3T, { purpose: "gather" }),
    ] }]);
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");

    // ---------- join dialog ----------
    const gus = await rec.open(A.localUrl);
    await gus.waitForSelector("dialog.core-name[open]");
    const note = await gus.textContent("#core-n-note");
    ok("join dialog: states answers are saved on the host's computer and read by Claude when a round is sent",
      /answers are saved on the host's computer/i.test(note) && /read by Claude when a round is sent/i.test(note), note);
    ok("join dialog: states the side chat is not sent to Claude", /side chat is not sent to Claude/i.test(note), note);
    const gusPid = await joinAs(gus, "Gus");

    // ---------- refused join: the reason and a retry ----------
    const rae = await rec.open(A.localUrl);
    await rae.waitForSelector("dialog.core-name[open]");
    const refuse = (status, error, message) => route => route.fulfill({ status, contentType: "application/json", body: JSON.stringify({ error, message }) });
    await rae.route("**/api/join", refuse(429, "join-rate", "Too many joins from here; wait a minute."));
    await rae.fill("#core-n", "Rae");
    await rae.click("dialog.core-name button");
    const retryShown = () => until(rae, () => { const b = document.querySelector("dialog.core-name button"); return !!b && !b.disabled && /try again/i.test(b.textContent); });
    const errText = () => rae.textContent("#core-n-err");
    ok("refused join: rate-limited shows the reason and a Try again control", await retryShown() && /too many/i.test(await errText()), await errText());
    await rae.unroute("**/api/join");
    await rae.route("**/api/join", refuse(503, "full", "This session is full."));
    await rae.click("dialog.core-name button");
    ok("refused join: session full shows the reason and a Try again control", await until(rae, () => /full/i.test(document.getElementById("core-n-err").textContent)) && await retryShown(), await errText());
    await rae.unroute("**/api/join");
    await rae.click("dialog.core-name button");
    ok("refused join: Try again joins once the server lets them in", await until(rae, () => !document.querySelector("dialog.core-name") && !!window.Core.snapshot()?.me?.pid));

    // ---------- two guests: presence, current question and typing within about 2 seconds ----------
    const pia = await rec.open(A.localUrl);
    const piaPid = await joinAs(pia, "Pia");
    await railQ(pia, Q1T).click();
    await railQ(gus, Q3T).click();
    await gus.waitForTimeout(300);
    const t0 = Date.now();
    await gus.locator("#vf-answer").pressSequentially("Tap", { delay: 30 });
    const seen = await until(pia, p => window.Core.state.presence.some(x => x.cid === p && x.q === "Q3" && x.typing), gusPid, 2500);
    const ms = Date.now() - t0;
    ok("two guests: B sees A on another question, typing, within 2500 ms", seen && ms <= 2500, `${ms} ms`);
    ok("two guests: B's question list shows A on that question", await until(pia, p => !![...document.querySelectorAll(".vf-q")]
      .find(n => n.textContent.includes("What should the first evening"))?.querySelector(`[data-who="${p}"]`), gusPid, 3000));
    await gus.fill("#vf-answer", "");

    // ---------- Claude's suggestion cards ----------
    await railQ(gus, Q1T).click();
    const botCards = page => page.evaluate(() => [...document.querySelectorAll(".vf-alist .vf-card.vf-bot")].filter(c => c.offsetParent).map(c => c.textContent));
    const barText = page => page.evaluate(() => { const b = document.querySelector(".vf-claudebar"); return b && b.offsetParent ? b.textContent : ""; });
    ok("Claude's cards: a guest who has not answered or voted sees \"Show Claude's take (3)\" and no cards",
      await until(gus, () => /Show Claude's take \(3\)/.test(document.querySelector(".vf-claudebar")?.textContent || "") && !!document.querySelector(".vf-claudebar").offsetParent)
        && (await botCards(gus)).length === 0, `${await barText(gus)} | ${(await botCards(gus)).length} cards`);
    await gus.locator("#vf-answer").fill("Somewhere with a lake.");
    await gus.press("#vf-answer", "Control+Enter");
    ok("Claude's cards: after answering, all three show", await until(gus, n => [...document.querySelectorAll(".vf-alist .vf-card.vf-bot")].filter(c => c.offsetParent).length === n
      && !document.querySelector(".vf-claudebar")?.offsetParent, 3), `${(await botCards(gus)).length} cards`);
    // AC4 names the tag: the recommendation's card reads "Claude recommends"; the alternatives carry no such tag.
    const recTags = () => gus.evaluate(() => [...document.querySelectorAll(".vf-alist .vf-card.vf-bot")].filter(c => c.offsetParent)
      .map(c => [c.textContent.slice(0, 60), [...c.querySelectorAll(".vf-tag")].filter(t => !t.hidden).map(t => t.textContent).join("|")]));
    ok("Claude's cards: the recommendation is tagged \"Claude recommends\" and the alternatives are not", await until(gus, ([rec, a, b]) => {
      const tags = [...document.querySelectorAll(".vf-alist .vf-card.vf-bot")].filter(c => c.offsetParent).map(c => [c.textContent, [...c.querySelectorAll(".vf-tag")].filter(t => !t.hidden).map(t => t.textContent).join("|")]);
      const tagOf = t => tags.find(([text]) => text.includes(t))?.[1];
      return tagOf(rec) === "Claude recommends" && tagOf(a) === "" && tagOf(b) === "";
    }, [REC, ALT_A, ALT_B]), JSON.stringify(await recTags()));
    await gus.evaluate(() => window.Core.vote("Q1", "c:a", true));
    await until(owner, () => (window.Core.snapshot().cards.Q1 || []).some(c => c.ref === "c:a" && (c.votes || []).length === 1));
    const ivy = await rec.open(A.localUrl, { context: DESK });
    await joinAs(ivy, "Ivy");
    await railQ(ivy, Q1T).click();
    ok("Claude's cards: a card someone chose always shows; the others wait behind \"Show Claude's take (2)\"", await until(ivy, alt => {
      const cards = [...document.querySelectorAll(".vf-alist .vf-card.vf-bot")].filter(c => c.offsetParent);
      return cards.length === 1 && cards[0].textContent.includes(alt) && /Show Claude's take \(2\)/.test(document.querySelector(".vf-claudebar")?.textContent || "");
    }, ALT_A), `${await barText(ivy)} | ${JSON.stringify(await botCards(ivy))}`);
    await pia.locator(".vf-person.vf-person-me").first().click();
    await pia.locator(".vf-seg-btn", { hasText: "Always show" }).click();
    await pia.keyboard.press("Escape");
    ok("Claude's cards: Always show shows them before answering", await until(pia, n => [...document.querySelectorAll(".vf-alist .vf-card.vf-bot")].filter(c => c.offsetParent).length === n, 3)
      && !(await pia.evaluate(p => (window.Core.snapshot().cards.Q1 || []).some(c => c.ref === `p:${p}`), piaPid)), `${(await botCards(pia)).length} cards`);

    // ---------- long text ----------
    const LONG = Array.from({ length: 30 }, (_, i) => `Line ${i + 1} of a long answer about the evening plan, with enough words to wrap.`).join(" ").slice(0, 1500);
    await railQ(ivy, Q3T).click();
    await ivy.evaluate(t => window.Core.answerCiting("Q3", t, []), LONG);
    await railQ(owner, Q3T).click();
    const longCard = owner.locator(".vf-alist .vf-card", { hasText: "Line 1 of a long answer" });
    ok("long text: a 1500-character answer clamps with Show more", await until(owner, () => [...document.querySelectorAll(".vf-alist .vf-card")]
      .some(c => c.textContent.includes("Line 1 of a long answer") && !c.querySelector(".vf-cctl").hidden && /Show more/.test(c.querySelector(".vf-cctl").textContent))));
    await longCard.locator(".vf-cctl .vf-lbtn", { hasText: "Show more" }).click();
    ok("long text: Show more expands it in place", await until(owner, () => [...document.querySelectorAll(".vf-alist .vf-card")]
      .some(c => c.textContent.includes("Line 1 of a long answer") && c.querySelector(".vf-clamp.vf-exp") && /Show less/.test(c.querySelector(".vf-cctl").textContent))));
    await longCard.locator(".vf-cctl .vf-lbtn", { hasText: "Open" }).click();
    ok("long text: Open shows the whole text in the reader", await until(owner, t => { const r = document.querySelector(".vf-reader"); return !!r && !r.hidden && r.querySelector(".vf-rd-text").textContent.replace(/\s+/g, " ").includes(t.slice(-60).trim()); }, LONG));
    await owner.keyboard.press("Escape");
    await ivy.locator(".vf-fab").click();
    const near = "x".repeat(1600);
    await ivy.fill(".vf-minput", near);
    ok("long text: the chat composer shows a character count near its limit", await until(ivy, m => document.querySelector(".vf-mcount")?.textContent === `1600 / ${m}`, MAX_TEXT),
      await ivy.textContent(".vf-mcount"));
    await ivy.fill(".vf-minput", "x".repeat(MAX_TEXT - 1));
    await ivy.locator(".vf-minput").press("End");
    await ivy.keyboard.type("yz");
    const atLimit = await ivy.evaluate(() => ({ n: document.querySelector(".vf-minput").value.length, c: document.querySelector(".vf-mcount").textContent }));
    ok("long text: at the limit the count says so instead of cutting text silently", atLimit.n === MAX_TEXT && atLimit.c === `${MAX_TEXT} / ${MAX_TEXT}`, JSON.stringify(atLimit));
    await ivy.fill(".vf-minput", "");
    await ivy.keyboard.press("Escape");

    // ---------- uploads off: no upload control ----------
    const uploadControls = page => page.evaluate(() => [...document.querySelectorAll("input[type=file], .vf-attach, button, [role=button]")]
      .filter(e => e.offsetParent && (e.matches("input[type=file], .vf-attach") || /attach|upload/i.test(`${e.textContent} ${e.getAttribute("aria-label") || ""} ${e.title || ""}`)))
      .map(e => e.getAttribute("aria-label") || e.textContent.trim() || e.className));
    await railQ(gus, Q3T).click();
    const upFocus = await uploadControls(gus);
    await gus.locator(".vf-fab").click();
    await until(gus, () => !!document.querySelector("section.vf-chat:not([hidden])"));
    const upChat = await uploadControls(gus);
    await gus.keyboard.press("Escape");
    ok("uploads off: no upload or attach control on the guest's question or chat", upFocus.length === 0 && upChat.length === 0, JSON.stringify([...upFocus, ...upChat]));

    // ---------- reconnecting keeps unsent text ----------
    await railQ(gus, Q3T).click();
    const DRAFT = "A dinner by the water, not sent yet";
    await gus.fill("#vf-answer", DRAFT);
    await gus.context().route("**/api/state**", route => route.abort("failed"));
    ok("reconnecting: the page shows \"Reconnecting…\" when the server drops", await until(gus, () => document.querySelector(".vf-live-txt")?.textContent === "Reconnecting…", null, 15000));
    ok("reconnecting: the unsent answer stays while it is down", (await gus.inputValue("#vf-answer")) === DRAFT, await gus.inputValue("#vf-answer"));
    await gus.context().unroute("**/api/state**");
    ok("reconnecting: the page recovers on its own", await until(gus, () => document.querySelector(".vf-live-txt")?.textContent !== "Reconnecting…" && window.Core.live, null, 15000));
    ok("reconnecting: the unsent answer is still there after it recovers", (await gus.inputValue("#vf-answer")) === DRAFT, await gus.inputValue("#vf-answer"));
    await gus.fill("#vf-answer", "");

    // ---------- answers and Claude thread: side by side at 1440x900, two tabs at 390x844 ----------
    await railQ(ivy, Q1T).click();
    const cols = await ivy.evaluate(() => {
      const sp = document.querySelector(".vf-split"), a = document.querySelector(".vf-anspane").getBoundingClientRect(), t = document.querySelector(".vf-thpane").getBoundingClientRect();
      return { layout: sp.dataset.layout, side: a.width > 0 && t.width > 0 && a.right <= t.left && Math.abs(a.top - t.top) < 4, tabs: !!document.querySelector(".vf-splittabs")?.offsetParent };
    });
    ok("side by side: at 1440x900 answers and the Claude thread sit next to each other, no tabs", cols.side && !cols.tabs, JSON.stringify(cols));
    const pho = await rec.open(A.localUrl, { context: PHONE });
    await joinAs(pho, "Pho");
    await until(pho, () => !!document.querySelector(".vf-qtext")?.offsetParent);
    const paneState = () => pho.evaluate(() => ({ tabs: [...document.querySelectorAll(".vf-splittabs .vf-seg-btn")].filter(b => b.offsetParent).map(b => b.textContent),
      ans: !!document.querySelector(".vf-anspane").offsetParent, th: !!document.querySelector(".vf-thpane").offsetParent }));
    const ph1 = await paneState();
    ok("side by side: at 390x844 they are two tabs, Answers showing", ph1.tabs.length === 2 && /^Answers/.test(ph1.tabs[0]) && /^Claude/.test(ph1.tabs[1]) && ph1.ans && !ph1.th, JSON.stringify(ph1));
    await pho.locator(".vf-splittabs .vf-seg-btn", { hasText: /^Claude/ }).tap();
    const ph2 = await paneState();
    ok("side by side: the Claude tab shows the thread instead of the answers", ph2.th && !ph2.ans, JSON.stringify(ph2));
    await pho.locator(".vf-splittabs .vf-seg-btn", { hasText: /^Answers/ }).tap();

    // ---------- phone 390x844: header one row, composer one line with send inside, question and answers >= 70% ----------
    await pho.evaluate(() => document.activeElement?.blur());
    const geo = await pho.evaluate(() => {
      const vis = e => e.offsetParent && e.getBoundingClientRect().width > 0 && getComputedStyle(e).visibility !== "hidden";
      const kids = [...document.querySelector(".vf-top").children].filter(vis).map(e => e.getBoundingClientRect());
      const tops = kids.map(r => r.top), bottoms = kids.map(r => r.bottom);
      const ta = document.getElementById("vf-answer"), cs = getComputedStyle(ta), send = document.querySelector(".vf-composer .vf-sendbtn");
      const lh = parseFloat(cs.lineHeight) || parseFloat(cs.fontSize) * 1.5, pad = parseFloat(cs.paddingTop) + parseFloat(cs.paddingBottom) + parseFloat(cs.borderTopWidth) + parseFloat(cs.borderBottomWidth);
      const comp = document.querySelector(".vf-composer").getBoundingClientRect(), sr = send.getBoundingClientRect(), tr = ta.getBoundingClientRect();
      const region = document.querySelector(".vf-scroll").getBoundingClientRect();
      return { rows: Math.max(...tops) < Math.min(...bottoms), kids: kids.length, taH: tr.height, oneLine: tr.height <= lh * 1.6 + pad, lh, pad,
        sendIn: !!send.offsetParent && sr.left >= comp.left - 1 && sr.right <= comp.right + 1 && sr.top >= comp.top - 1 && sr.bottom <= comp.bottom + 1 && sr.top < tr.bottom && sr.bottom > tr.top,
        region: region.height / innerHeight };
    });
    ok("phone 390x844: the header is one row", geo.kids > 1 && geo.rows, JSON.stringify(geo));
    ok("phone 390x844: the composer is one line with send inside it", geo.oneLine && geo.sendIn, JSON.stringify(geo));
    ok("phone 390x844: the question and answers take at least 70% of the height with nothing focused", geo.region >= 0.7, geo.region.toFixed(3));

    // ---------- locked question: composer disabled, says how to suggest a change ----------
    await owner.evaluate(() => window.Core.lock("Q1", "c:rec"));
    await railQ(gus, Q1T).click();
    ok("locked question: the guest's composer is disabled and says how to suggest a change", await until(gus, () => {
      const ta = document.getElementById("vf-answer");
      return !!document.querySelector(".vf-lock:not([hidden])") && ta.disabled && /suggest a change/i.test(ta.placeholder);
    }), await gus.evaluate(() => `${document.getElementById("vf-answer").disabled} ${document.getElementById("vf-answer").placeholder}`));
    ok("locked question: a Suggest a change control is offered", await gus.locator("button", { hasText: "Suggest a change" }).first().isVisible());

    // ---------- Needs review on a dependent question ----------
    await owner.evaluate(() => window.Core.lockEdit("Q1", "Lisbon, by the river, in May."));
    await railQ(gus, Q2T).click();
    ok("needs review: a question depending on the changed locked answer shows Needs review naming Q1", await until(gus, () => {
      const r = document.querySelector(".vf-reviewrow"); return !!r && !!r.offsetParent && /Needs review/.test(r.textContent) && /Q1/.test(r.textContent);
    }), await gus.evaluate(() => JSON.stringify([document.querySelector(".vf-qtext")?.textContent, document.querySelector(".vf-reviewrow")?.outerHTML.slice(0, 300), document.querySelector(".vf-center")?.dataset.mode])));
    ok("needs review: nothing was deleted (Q1's answers are all still there)", await owner.evaluate(p => (window.Core.snapshot().cards.Q1 || []).some(c => c.ref === `p:${p}` && c.text === "Somewhere with a lake."), gusPid));

    // ---------- Host view: owner and a leader; a guest has none ----------
    const hostPane = async page => {
      const seg = page.locator(".vf-bar .vf-seg-btn", { hasText: /^Host$/ }), more = page.locator(".vf-viewopts");
      if (!(await seg.isVisible()) && (await more.isVisible())) await more.click();
      if (!(await seg.isVisible())) return null;
      await seg.click();
      await until(page, () => document.querySelector(".vf-center")?.dataset.mode === "host");
      return page.evaluate(() => {
        const secs = Object.fromEntries([...document.querySelectorAll(".vf-hostv .vf-hsec")].filter(x => x.offsetParent).map(x => [x.querySelector(".vf-hsec-title").textContent, x.textContent]));
        return { secs: Object.keys(secs), people: secs.People || "", round: secs.Round || "", goal: document.querySelector(".vf-hgoal")?.textContent || "" };
      });
    };
    const own = await hostPane(owner);
    ok("host view: the owner's shows people, the queue, round status, links, goal and Later",
      !!own && ["People", "Queue", "Round", "Links and settings", "Later"].every(k => own.secs.includes(k)) && own.people.includes("Gus") && /Round 1/.test(own.round) && own.goal === GOAL, JSON.stringify(own));
    await owner.evaluate(p => window.Core.setLeader(p, true), piaPid);
    await until(pia, () => window.Core.me.isLeader);
    const lead = await hostPane(pia);
    ok("host view: a leader's shows people, the queue, round status, goal and Later",
      !!lead && ["People", "Queue", "Round", "Later"].every(k => lead.secs.includes(k)) && lead.people.includes("Gus") && /Round 1/.test(lead.round) && lead.goal === GOAL, JSON.stringify(lead));
    ok("host view: a plain guest has none", (await hostPane(gus)) === null && !(await gus.evaluate(() => [...document.querySelectorAll(".vf-msitem")].some(m => m.offsetParent && /Host view/.test(m.textContent)))));

    // ---------- new tunnel address ----------
    const recFile = path.join(A.dir, ".shared-tunnel.json");
    const cf = JSON.parse(fs.readFileSync(recFile, "utf8"));
    const cmd = fs.readFileSync(`/proc/${cf.pid}/cmdline`, "utf8");
    if (!/fake-cloudflared/.test(cmd)) throw new Error(`the tunnel record's pid ${cf.pid} is not the fake cloudflared: ${cmd}`);
    process.kill(cf.pid, "SIGTERM");
    ok("new tunnel address: the owner view shows \"New guest link, share again\"", await until(owner, () => /New guest link, share again/.test(document.querySelector(".vf-banner")?.textContent || "")
      || document.querySelector(".vf-share")?.getAttribute("aria-label") === "New guest link, share again"
      || [...document.querySelectorAll("button")].some(b => b.offsetParent && b.getAttribute("aria-label") === "New guest link, share again"), null, 40000));

    // ================= session B: the round lifecycle, Follow, a proposal not placed =================
    const B = await s.start("rounds");
    s.apply(B.dir, [{ op: "set-title", title: "Venue" }, { op: "open-round", questions: [tq("Q1", Q1T), tq("Q2", Q2T)] }]);
    const host = await rec.open(B.ownerUrl);
    await until(host, () => window.Core.snapshot()?.me?.role === "owner");
    const bo = await rec.open(B.localUrl);
    await joinAs(bo, "Bo");
    const cy = await rec.open(B.localUrl);
    await joinAs(cy, "Cy");
    await bo.evaluate(() => window.Core.idea("Should we bring partners?"));
    await railQ(bo, Q2T).click();
    await railQ(cy, Q2T).click();
    await railQ(host, Q1T).click();
    await host.locator(".vf-round-cur .vf-send").click();
    const sendAnyway = host.locator(".vf-confirm button", { hasText: "Send anyway" });
    if (await sendAnyway.isVisible().catch(() => false)) await sendAnyway.click();
    ok("round lifecycle: after Send, guests see Waiting for Claude", await until(bo, () => document.querySelector(".vf-next .vf-steps [aria-current=step]")?.textContent === "Waiting for Claude"), await curStep(bo));
    const cancelBtn = host.locator(".vf-cancel-send").first();
    ok("round lifecycle: the owner gets Cancel while it waits", await cancelBtn.isVisible());
    await cancelBtn.click();
    await host.locator("dialog[open] button", { hasText: "Cancel sending" }).click();
    ok("round lifecycle: Cancel works, and guests see the round open again", await toastHas(bo, /cancelled\. It is open again/)
      && await until(bo, () => window.Core.snapshot().round.status === "open" && !document.getElementById("vf-answer").disabled), await bo.evaluate(() => window.Core.snapshot().round.status));
    await host.locator(".vf-round-cur .vf-send").click();
    if (await sendAnyway.isVisible().catch(() => false)) await sendAnyway.click();
    await until(host, () => window.Core.snapshot().round.status === "sent");
    s.apply(B.dir, [{ op: "ack-round", round: 1 }]);
    ok("round lifecycle: once Claude picks it up, the page shows Claude is working", await until(bo, () => document.querySelector(".vf-next .vf-steps [aria-current=step]")?.textContent === "Claude is working"), await curStep(bo));
    ok("round lifecycle: while Claude is working the owner has no Cancel", await until(host, () => window.Core.snapshot().round.status === "working"
      && ![...document.querySelectorAll("button")].some(b => b.offsetParent && /^Cancel sending$/.test(b.textContent.trim()))));
    const propId = await host.evaluate(() => window.Core.snapshot().proposals.find(p => p.text === "Should we bring partners?").id);
    const REASON = "Not about the venue";
    s.apply(B.dir, [{ op: "open-round", questions: [tq("Q3", Q3T)], placements: [{ proposal: propId, as: "not-placed", reason: REASON }] }]);
    const [hostToast, cyToast, boToast] = await Promise.all([host, cy, bo].map(p => toastHas(p, /Round 2 is here/)));
    ok("round lifecycle: the owner sees the toast \"Round 2 is here\"", hostToast);
    ok("round lifecycle: a guest sees the toast \"Round 2 is here\"", cyToast);
    ok("round lifecycle: a proposal's author sees \"Round 2 is here\" too, then the not-placed notice", boToast && await toastHas(bo, /not placed/i));
    ok("round lifecycle: with Follow off the guest's current question does not change", (await qText(bo)) === Q2T, await qText(bo));
    ok("proposal not placed: its author sees \"Not placed\" and Claude's reason", await until(bo, r => [...document.querySelectorAll(".vf-mp")]
      .some(li => li.offsetParent && /Not placed/.test(li.querySelector(".vf-mp-stat").textContent) && li.querySelector(".vf-mp-stat").textContent.includes(r)), REASON),
      await bo.evaluate(() => [...document.querySelectorAll(".vf-mp-stat")].map(x => x.textContent).join(" | ")));
    await railQ(host, Q3T).click();
    await until(cy, () => !!document.querySelector(".vf-follow")?.offsetParent);
    await cy.locator(".vf-follow").click();
    ok("round lifecycle: with Follow on, the guest moves to the owner's question", await until(cy, t => document.querySelector(".vf-qtext")?.textContent === t, Q3T), await qText(cy));

    // ================= session C: ended =================
    const C = await s.start("ended");
    s.apply(C.dir, [{ op: "set-title", title: "Done" }, { op: "open-round", questions: [tq("Q1", Q1T)] }]);
    const boss = await rec.open(C.ownerUrl);
    await until(boss, () => window.Core.snapshot()?.me?.role === "owner");
    const dee = await rec.open(C.localUrl);
    await joinAs(dee, "Dee");
    await boss.evaluate(() => window.Core.endSession(true));
    ok("session ended: the guest sees the Tree view, read-only", await until(dee, () => document.querySelector(".vf-center")?.dataset.mode === "tree"
      && [...document.querySelectorAll(".vf-center textarea, .vf-center input")].filter(e => e.offsetParent).every(e => e.disabled || e.readOnly)
      && /ended/i.test(document.querySelector(".vf-banner")?.textContent || "")));
    const late = await rec.open(C.localUrl);
    await late.waitForSelector("dialog.core-name[open]");
    await late.fill("#core-n", "Late");
    await late.click("dialog.core-name button");
    ok("session ended: a new join is refused with a reason", await until(late, () => /ended/i.test(document.getElementById("core-n-err")?.textContent || "")) && !(await snap(late))?.me,
      await late.evaluate(() => document.getElementById("core-n-err")?.textContent));

    // ================= session D: views share data, Compare's edge, new answers announced, 200% zoom =================
    const D = await s.start("views");
    const MANY = Array.from({ length: 8 }, (_, i) => tq(`Q${i + 1}`, `View question ${i + 1}?`));
    s.apply(D.dir, [{ op: "set-title", title: "Views" }, { op: "open-round", questions: MANY }]);
    const vo = await rec.open(D.ownerUrl, { context: { viewport: { width: 1024, height: 768 } } });
    await until(vo, () => window.Core.snapshot()?.me?.role === "owner");
    const vg = await rec.open(D.localUrl, { context: DESK });
    await joinAs(vg, "Vic");
    await railQ(vg, "View question 1?").click();
    await vg.evaluate(() => {
      window.__said = [];
      for (const live of document.querySelectorAll('[aria-live="polite"]'))
        new MutationObserver(() => { if (live.textContent.trim()) window.__said.push(live.textContent.trim()); }).observe(live, { childList: true, characterData: true, subtree: true });
    });
    const MARK = "Shared across every view";
    await vo.evaluate(t => window.Core.answerCiting("Q1", t), MARK);
    ok("announced: a guest on the question hears that a new answer arrived", await until(vg, () => window.__said.some(m => /new answer/i.test(m))),
      await vg.evaluate(() => JSON.stringify(window.__said)));
    const seg = async (page, label) => {
      const b = page.locator(".vf-bar .vf-seg-btn", { hasText: label }), more = page.locator(".vf-viewopts");
      if (!(await b.isVisible()) && (await more.isVisible())) await more.click();
      await b.click();
      return until(page, m => document.querySelector(".vf-center")?.dataset.mode === m, label.toLowerCase(), 5000);
    };
    // Tree summarizes each question (its answer count), so the same data there is "1 answer" on Q1, "no answers" on Q2.
    const inFocus = await until(vg, t => [...document.querySelectorAll(".vf-card")].some(c => c.offsetParent && c.textContent.includes(t)), MARK);
    const inCompare = (await seg(vg, "Compare")) && await until(vg, t => document.querySelector(".vf-board")?.innerText.includes(t), MARK);
    const inTree = (await seg(vg, "Tree")) && await until(vg, () => /View question 1\?\s+Open\s+1 answer\b/.test(document.querySelector(".vf-tree")?.innerText || "")
      && /View question 2\?\s+Open\s+no answers yet/.test(document.querySelector(".vf-tree")?.innerText || ""));
    ok("views: the same answer shows in Focus and Compare, and Tree counts it on its question", inFocus && inCompare && inTree, JSON.stringify({ inFocus, inCompare, inTree }));
    await seg(vo, "Compare");
    const edgeOk = await until(vo, () => {
      const b = document.querySelector(".vf-board"), r = b.getBoundingClientRect();
      const off = [...b.children].filter(c => { const x = c.getBoundingClientRect(); return x.right > r.right + 1 || x.left < r.left - 1; }).length;
      return off > 0 && !!document.querySelector(".vf-fade-r.vf-on, .vf-fade-l.vf-on") && [...document.querySelectorAll(".vf-edge")].some(e => !e.hidden && e.offsetParent);
    });
    ok("views: Compare at 1024 wide has columns off screen and shows the edge indicator", edgeOk);
    await seg(vg, "Focus");
    await railQ(vg, "View question 2?").click();
    await vg.fill("#vf-answer", Array.from({ length: 60 }, (_, i) => `line ${i + 1}`).join("\n"));
    const grown = await vg.evaluate(() => {
      const t = document.getElementById("vf-answer"), pane = t.closest(".vf-center");
      return { h: t.getBoundingClientRect().height, pane: pane.clientHeight, line: parseFloat(getComputedStyle(t).lineHeight) || 20 };
    });
    ok("long text: the answer box grows with its text up to 40% of its pane", grown.h > 3 * grown.line && grown.h <= grown.pane * 0.4 + 2, JSON.stringify(grown));
    await vg.fill("#vf-answer", "");
    ok("announced: the toast is a status region, so screen readers hear it",
      await vg.evaluate(() => { const t = document.querySelector(".vf-toast"); return t.getAttribute("role") === "status" || t.getAttribute("aria-live") === "polite"; }));
    const zoom = await rec.open(D.localUrl, { context: { viewport: { width: 720, height: 450 }, deviceScaleFactor: 2 } });
    await joinAs(zoom, "Zed");
    await zoom.locator(".vf-q", { hasText: "View question 1?" }).first().click().catch(() => {});
    // Visible = in the page, not clipped away: scrolled into view inside its pane, it is the element on top there.
    ok("200% zoom (1440x900 at 200% = 720x450): the answers stay visible", await until(zoom, t => [...document.querySelectorAll(".vf-card")].some(c => {
      if (!c.textContent.includes(t) || !c.offsetParent) return false;
      c.scrollIntoView({ block: "center" });
      const r = c.getBoundingClientRect();
      return r.height > 0 && document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)?.closest(".vf-card") === c && document.scrollingElement.scrollTop === 0;
    }), MARK), await zoom.evaluate(() => JSON.stringify(document.querySelector(".vf-card")?.getBoundingClientRect())));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
    const too = rec.too.filter(x => x !== "POST /api/join");
    ok("no request was answered 429 (slow down) except the refused join this suite staged", too.length === 0, too.slice(0, 5).join(", "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
