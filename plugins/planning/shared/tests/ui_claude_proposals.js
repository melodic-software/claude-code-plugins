#!/usr/bin/env node
// Claude proposes, the owner approves (issue #8697), in a real browser against `share.sh ensure-running` with the fake
// cloudflared: a second "Ann" joins while the first is not here, the server tells Claude (person-joined), Claude's
// propose-merge lands in the owner's Host view and Inbox with its reasons, a guest never sees it, nothing merges
// until the owner taps Merge, and Merge folds the new browser into the earlier Ann as the owner's own merge does.
//   node plugins/planning/shared/tests/ui_claude_proposals.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the issue's acceptance list, the owner's decision on it, and the texts this suite
// writes, never from the page.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { loadPlaywright, suite, recorder, until, snap } = require("./browser_harness");

const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });

async function post(base, route, body, headers = {}) {
  const r = await fetch(new URL(route, base), { method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify(body) });
  return { status: r.status, body: await r.json() };
}

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_claude_proposals.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_claude_proposals"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("proposals");
    s.apply(A.dir, [{ op: "set-title", title: "Offsite" }, { op: "open-round", questions: [q("Q1", "Where should we go?")] }]);
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");

    // The first Ann joined earlier and is not here now: a join that names no device starts no presence.
    const first = await post(A.localUrl, "/api/join", { name: "Ann", key: A.guestKey });
    ok("the first Ann joins", first.status === 200, JSON.stringify(first.body));
    const annPid = first.body.pid, annHdr = { "X-Session-Secret": first.body.secret };
    ok("  and says hello in chat", (await post(A.localUrl, "/api/chat", { text: "Hello from my laptop" }, annHdr)).status === 200);

    // The same Ann on her phone, without her own link: a second person, who answers "No, I am new".
    const twin = await rec.open(A.localUrl);
    await twin.waitForSelector("dialog.core-name[open]");
    await twin.fill("#core-n", "Ann");
    await twin.click("dialog.core-name button");
    await twin.locator("dialog.core-name button", { hasText: "No, I am new" }).click();
    await until(twin, () => !document.querySelector("dialog.core-name") && !!window.Core.snapshot()?.me);
    const twinPid = (await snap(twin)).me.pid;
    ok("the second Ann is a person of her own", twinPid && twinPid !== annPid, twinPid);
    await twin.evaluate(() => window.Core.chat("Hi from my phone"));

    const state = () => JSON.parse(fs.readFileSync(path.join(A.dir, "state.json"), "utf8"));
    const ev = state().log.events.filter(e => e.kind === "person-joined");
    ok("the server tells Claude the second Ann's name is someone's who is not here", ev.length === 1 && ev[0].person === twinPid
      && ev[0].sameName.map(m => m.pid).join() === annPid, JSON.stringify(ev));

    const out = s.apply(A.dir, [{ op: "propose-merge", from: twinPid, to: annPid, reasons: ["same-name", "was-offline"], note: "Joined a minute after Ann left." }]);
    const kid = out.results[0].id;
    ok("Claude's proposal is accepted", !!kid, JSON.stringify(out));

    // ---------- the owner sees it in the Host view, with its reasons; a guest never does ----------
    await owner.locator(".vf-seg .vf-seg-btn", { hasText: "Host" }).click();
    const row = '.vf-queue .vf-qitem[data-t="people"]';
    ok("the Host view lists Claude's proposal with its reasons and the fix for next time", await until(owner, sel => {
      const t = document.querySelector(sel)?.textContent || "";
      return t.includes("Claude suggests") && t.includes("Why: the same name; the earlier one was offline when this one joined.") && t.includes("Joined a minute after Ann left.")
        && t.includes("their own link (Use on another device)");
    }, row), await owner.evaluate(sel => document.querySelector(sel)?.textContent, row));
    ok("  with Not the same person and Merge", await owner.evaluate(sel => [...document.querySelectorAll(`${sel} .vf-acts button`)].map(b => b.textContent).join() === "Not the same person,Merge", row),
      await owner.evaluate(sel => [...document.querySelectorAll(`${sel} .vf-acts button`)].map(b => b.textContent).join(), row));
    ok("a guest's snapshot holds no proposal", await twin.evaluate(() => (window.Core.state.claudeProposals || []).length === 0 && !("claudeProposals" in window.Core.snapshot())));
    const guestApprove = await post(A.localUrl, "/api/claude-proposal/act", { id: kid, action: "approve" }, annHdr);
    ok("a guest's approve is refused as owner-only", guestApprove.status === 403 && guestApprove.body.error === "owner-only", JSON.stringify(guestApprove));
    ok("  and nothing merged without the owner's tap", state().people[twinPid] !== undefined && state().people[annPid] !== undefined);

    // ---------- the Inbox lists it under Needs you; Merge there folds the two ----------
    await owner.click(".vf-bell");
    ok("the owner's Inbox lists it under Needs you, as From Claude", await until(owner, () => [...document.querySelectorAll(".vf-rev-chip")].some(b => b.textContent.startsWith("From Claude · 1"))
      && !!document.querySelector('.vf-ibq .vf-qitem[data-t="people"]')),
      await owner.evaluate(() => [...document.querySelectorAll(".vf-rev-chip")].map(b => b.textContent).join(" | ")));
    await owner.locator('.vf-ibq .vf-qitem[data-t="people"] .vf-acts button', { hasText: /^Merge$/ }).click();
    ok("one tap on Merge merges, with no dialog", await until(owner, () => document.querySelector(".vf-toast")?.textContent === "Merged into Ann." && !document.querySelector(".vf-cdlg[open]")),
      await owner.evaluate(() => document.querySelector(".vf-toast")?.textContent));
    ok("the second Ann leaves the people list and the proposal leaves the queue", await until(owner, p => !window.Core.snapshot().people.some(x => x.pid === p)
      && !document.querySelector('.vf-qitem[data-t="people"]'), twinPid));
    ok("the phone carries on as the earlier Ann", await until(twin, p => window.Core.snapshot()?.me?.pid === p, annPid, 10000), await twin.evaluate(() => window.Core.snapshot()?.me?.pid));
    ok("  and the phone's chat is the earlier Ann's now", await until(twin, p => window.Core.snapshot().chat.some(m => m.pid === p && m.text === "Hi from my phone"), annPid));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
    ok("no request was answered 429 (slow down)", rec.too.length === 0, rec.too.slice(0, 5).join(", "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
