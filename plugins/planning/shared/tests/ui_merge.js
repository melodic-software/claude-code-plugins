#!/usr/bin/env node
// The owner merges a person in a real browser, against `share.sh ensure-running` with the fake cloudflared: the
// merge picker lists the owner first as "You", so a second identity of the owner's own (opened on another
// device as "Admin 2") folds into the owner, its chat becoming the owner's and the person leaving the people list;
// a merge the session refuses shows the session's own sentence, not a generic one.
//   node plugins/planning/shared/tests/ui_merge.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the brief ("Merge into me (owner)"), the server's refusal text for a person who is gone
// ("No such person.") and the texts this suite writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_merge.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_merge"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("merge");
    s.apply(A.dir, [{ op: "set-title", title: "Offsite" }, { op: "open-round", questions: [q("Q1", "Where should we go?")] }]);
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const twin = await rec.open(A.localUrl);
    const twinPid = await joinAs(twin, "Admin 2");
    const bo = await rec.open(A.localUrl);
    const boPid = await joinAs(bo, "Bo");
    await twin.evaluate(() => window.Core.chat("Hi from my phone"));
    await owner.locator(".vf-seg .vf-seg-btn", { hasText: "Host" }).click();
    ok("the owner's people list shows Admin 2 and Bo", await until(owner, ([a, b]) => [a, b].every(p => document.querySelector(`.vf-hperson:has([data-pid="${p}"])`)), [twinPid, boPid]));

    // ---------- the owner renames a guest from that guest's card ----------
    const boEl = `.vf-hperson:has([data-pid="${boPid}"]) [data-pid="${boPid}"]`;
    await owner.click(boEl);
    await owner.click('.vf-pcard [data-k="pa-rename"]');
    ok("the card's Rename opens the name form", await until(owner, () => !!document.querySelector('.vf-pcard [data-k="rnp"]')));
    await owner.click('.vf-pcard [data-k="rpc"]');
    ok("  and Cancel closes it", await until(owner, () => !document.querySelector('.vf-pcard [data-k="rnp"]')));
    await owner.click('.vf-pcard [data-k="pa-rename"]');
    await owner.fill('.vf-pcard [data-k="rnp"]', "Bobby");
    await owner.click('.vf-pcard [data-k="rps"]');
    ok("  and Save renames the guest and closes the form", await until(owner, p => document.querySelector(".vf-toast")?.textContent === "Renamed to Bobby."
      && !document.querySelector('.vf-pcard [data-k="rnp"]') && window.Core.snapshot().people.some(x => x.pid === p && x.name === "Bobby"), boPid));
    await owner.click('.vf-pcard [data-k="pa-rename"]');
    await owner.fill('.vf-pcard [data-k="rnp"]', "Half typed");
    // The taller card with its form open can cover the row's avatar, so these two clicks go to it directly.
    await owner.locator(boEl).dispatchEvent("click");
    await until(owner, () => document.querySelector(".vf-pcard")?.hidden);
    await owner.locator(boEl).dispatchEvent("click");
    await owner.click('.vf-pcard [data-k="pa-rename"]');
    ok("  and a draft left unsaved does not come back when the card opens again", await until(owner, () => document.querySelector('.vf-pcard [data-k="rnp"]')?.value === "Bobby"),
      await owner.evaluate(() => document.querySelector('.vf-pcard [data-k="rnp"]')?.value));
    await owner.locator(boEl).dispatchEvent("click");
    await until(owner, () => document.querySelector(".vf-pcard")?.hidden);

    // ---------- the picker offers the owner ----------
    await owner.locator(`.vf-hperson:has([data-pid="${twinPid}"]) .vf-hp-acts button`, { hasText: "Merge…" }).click();
    ok("the merge picker lists the owner first, as \"You\"", await until(owner, () => {
      const items = [...document.querySelectorAll(".vf-pcard .vf-merge-item")];
      return items[0]?.dataset.k === "m:host" && items[0].querySelector(".core-avatar + span")?.textContent === "You";
    }), await owner.evaluate(() => [...document.querySelectorAll(".vf-pcard .vf-merge-item")].map(b => `${b.dataset.k}=${b.textContent}`).join(" | ")));

    // ---------- a refusal shows the session's sentence ----------
    await owner.click(`.vf-pcard [data-k="m:${boPid}"]`);
    await until(owner, () => !!document.querySelector('.vf-pcard [data-k="mg"]'));
    await owner.evaluate(p => window.Core.merge(p, "host"), boPid); // Bo is gone before the owner's click lands
    await until(owner, p => !(p in window.Core.state.people), boPid);
    await owner.click('.vf-pcard [data-k="mg"]');
    await owner.click(".vf-cdlg .vf-btn-danger-solid");
    ok("a refused merge shows the session's own sentence", await until(owner, () => document.querySelector(".vf-toast")?.textContent === "Not merged: No such person."),
      await owner.evaluate(() => document.querySelector(".vf-toast")?.textContent));

    // ---------- merging into the owner ----------
    await owner.click('.vf-pcard [data-k="mc"]');
    await owner.click('.vf-pcard [data-k="m:host"]');
    ok("the confirm button reads \"Merge into me (owner)\"", await until(owner, () => document.querySelector('.vf-pcard [data-k="mg"]')?.textContent === "Merge into me (owner)"));
    await owner.click('.vf-pcard [data-k="mg"]');
    const twinJoins = [];
    twin.on("request", r => { if (new URL(r.url()).pathname === "/api/join") twinJoins.push(r.method()); });
    await owner.click(".vf-cdlg .vf-btn-danger-solid");
    ok("the merge succeeds and says so", await until(owner, () => document.querySelector(".vf-toast")?.textContent === "Merged Admin 2 into me (owner)."),
      await owner.evaluate(() => document.querySelector(".vf-toast")?.textContent));
    ok("Admin 2 leaves the people list", await until(owner, p => !document.querySelector(`.vf-hperson:has([data-pid="${p}"])`) && !window.Core.snapshot().people.some(x => x.pid === p), twinPid));
    ok("Admin 2's chat is the owner's now", await until(owner, () => window.Core.snapshot().chat.map(m => [m.pid, m.text]).join() === "host,Hi from my phone"));
    ok("the owner is still the owner", await owner.evaluate(() => window.Core.snapshot().me.role === "owner"));

    // ---------- the merged browser: told to open the owner link, never joined again ----------
    const NOTICE = "This browser was merged into the owner. Open your owner link here."; // triage row 39's sentence
    const banner = () => document.querySelector(".vf-banner:not([hidden])")?.textContent || "";
    ok("the merged browser shows the merged-into-owner notice", await until(twin, n => (document.querySelector(".vf-banner:not([hidden])")?.textContent || "").includes(n), NOTICE, 10000),
      await twin.evaluate(banner));
    ok("  and forgot its guest secret", await twin.evaluate(() => !localStorage.getItem("secret") && !localStorage.getItem("pid")));
    await twin.evaluate(() => window.Core.chat("Still me?").catch(() => {}));
    await twin.waitForTimeout(3500); // two polls and a beat
    ok("  and neither joined again nor asked for a name", twinJoins.length === 0 && !(await twin.evaluate(() => !!document.querySelector("dialog.core-name"))),
      `${twinJoins.length} joins`);
    await twin.reload();
    await twin.waitForTimeout(2500);
    ok("  reloaded, it still shows the notice and asks for no name", (await twin.evaluate(banner)).includes(NOTICE) && !(await twin.evaluate(() => !!document.querySelector("dialog.core-name"))) && twinJoins.length === 0,
      `${await twin.evaluate(banner)} | ${twinJoins.length} joins`);
    ok("  and the owner's people list does not get Admin 2 back", await owner.evaluate(() => window.Core.snapshot().people.every(p => p.name !== "Admin 2")));

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
