#!/usr/bin/env node
// A personal link ("Use on another device", #me=<secret>) in a real browser, against `share.sh ensure-running` with
// the fake cloudflared. In a browser that already holds a different person's secret, the link never signs it in as
// that person silently: it asks "This link signs you in as someone else on this device. Switch?", with Keep focused,
// Keep and Escape leave the stored secret as it was, and only Switch replaces it. With no secret stored, the link is
// adopted at once, as before; a link holding the browser's own secret asks nothing.
//   node plugins/planning/shared/tests/ui_personal_link.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the review finding (session fixation through #me; Keep is the default), the secrets the
// server issued on join and the names this suite types, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });
const ASK = "This link signs you in as someone else on this device. Switch?";

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_personal_link.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_personal_link"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("personal-link");
    s.apply(A.dir, [{ op: "set-title", title: "Offsite" }, { op: "open-round", questions: [q("Q1", "Where should we go?")] }]);
    const ann = await rec.open(A.localUrl);
    const annPid = await joinAs(ann, "Ann");
    const annSecret = await ann.evaluate(() => localStorage.getItem("secret"));
    const bo = await rec.open(A.localUrl);
    const boPid = await joinAs(bo, "Bo");
    const boSecret = await bo.evaluate(() => localStorage.getItem("secret"));
    const stored = page => page.evaluate(() => localStorage.getItem("secret"));
    const asking = page => until(page, () => !!document.querySelector("dialog.core-switch[open]"));

    // ---------- Bo's link in Ann's browser: asked, and Keep leaves Ann ----------
    const tab = await rec.openIn(ann.context(), `${A.localUrl}#me=${boSecret}`);
    ok("Bo's personal link in Ann's browser asks before switching", await asking(tab));
    ok("  with the finding's question", (await tab.evaluate(() => document.querySelector("dialog.core-switch h2")?.textContent)) === ASK,
      await tab.evaluate(() => document.querySelector("dialog.core-switch")?.textContent));
    ok("  and Keep has focus", await tab.evaluate(() => document.activeElement?.textContent === "Keep"));
    ok("  while it asks, the browser still holds Ann's secret", (await stored(tab)) === annSecret);
    ok("  and the address bar no longer carries Bo's secret", !(await tab.evaluate(() => location.hash)).includes(boSecret));
    await tab.keyboard.press("Escape");
    ok("Escape keeps Ann", await until(tab, () => !document.querySelector("dialog.core-switch")) && (await stored(tab)) === annSecret);
    ok("  and the page is still Ann's", await until(tab, p => window.Core.snapshot()?.me?.pid === p, annPid));

    const tab2 = await rec.openIn(ann.context(), `${A.localUrl}#me=${boSecret}`);
    await asking(tab2);
    await tab2.click("dialog.core-switch button:text-is('Keep')");
    await tab2.waitForTimeout(2000); // a poll and a beat
    ok("Keep keeps Ann", (await stored(tab2)) === annSecret && (await tab2.evaluate(() => window.Core.snapshot()?.me?.pid)) === annPid);

    // ---------- Switch: only then the browser becomes Bo ----------
    const tab3 = await rec.openIn(ann.context(), `${A.localUrl}#me=${boSecret}`);
    await asking(tab3);
    await tab3.click("dialog.core-switch button:text-is('Switch')");
    ok("Switch stores Bo's secret", await until(tab3, s => localStorage.getItem("secret") === s, boSecret));
    ok("  and the page signs in as Bo", await until(tab3, p => window.Core?.snapshot()?.me?.pid === p && window.Core.me.name === "Bo", boPid, 10000));

    // ---------- no secret stored: adopted at once; the browser's own secret: nothing to ask ----------
    const fresh = await rec.open(`${A.localUrl}#me=${annSecret}`);
    ok("in a browser with no secret, a personal link signs in at once", await until(fresh, p => window.Core.snapshot()?.me?.pid === p, annPid, 10000));
    ok("  without asking", !(await fresh.evaluate(() => !!document.querySelector("dialog.core-switch"))));
    const own = await rec.openIn(fresh.context(), `${A.localUrl}#me=${annSecret}`);
    await own.waitForTimeout(1500);
    ok("a link holding the browser's own secret asks nothing", !(await own.evaluate(() => !!document.querySelector("dialog.core-switch"))) && (await stored(own)) === annSecret);

    // ---------- the host signs in on another device with a one-time code; the owner link stays where it was ----------
    const ownerTok = new URL(A.ownerUrl).hash.slice("#owner=".length);
    const host = await rec.open(A.ownerUrl);
    await until(host, () => window.Core.snapshot()?.me?.role === "owner", null, 10000);
    await host.click(".vf-person-me");
    await until(host, () => !!document.querySelector('.vf-pcard [data-k="pair"]'));
    ok("the host's menu offers Sign in on another device in place of a personal link", (await host.textContent('.vf-pcard [data-k="pair"]')).trim() === "Sign in on another device"
      && !(await host.evaluate(() => !!document.querySelector('.vf-pcard [data-k="device"]'))));
    await host.click('.vf-pcard [data-k="pair"]');
    const shownCode = () => host.evaluate(() => document.querySelector(".vf-pair-code")?.textContent || "");
    ok("  it shows a QR code and a code of 8 characters", await until(host, () => /^[0-9A-Z]{4}-[0-9A-Z]{4}$/.test(document.querySelector(".vf-pair-code")?.textContent || "")
      && !!document.querySelector(".vf-pairpop .vf-qr svg")), await shownCode());
    ok("  and nothing on it holds the owner link's token", !(await host.evaluate(t => document.querySelector(".vf-pairpop").outerHTML.includes(t), ownerTok)));
    const code1 = (await shownCode()).replace("-", "");
    const PHONE = { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true };
    const phone = await rec.open(`${A.localUrl}#join=${A.guestKey}&pair=${code1}`, { context: PHONE });
    ok("the code in the QR code's link signs a fresh phone in as the host", await until(phone, () => window.Core.snapshot()?.me?.role === "owner", null, 10000));
    const phoneCred = await phone.evaluate(() => localStorage.getItem("ownerDevice"));
    ok("  with its own credential, not the owner link's token, and no code left in the address", !!phoneCred && phoneCred !== ownerTok && !(await phone.evaluate(() => location.hash.includes("pair"))));
    ok("  the host's list shows the phone", await until(host, () => [...document.querySelectorAll(".vf-pairlist .vf-pair-dev")].map(li => li.textContent).join().startsWith("Phone")));

    await host.waitForTimeout(1100); // the server makes one code a second
    await host.click(".vf-pairpop button:text-is('New code')");
    ok("New code makes another", await until(host, c => /^[0-9A-Z]{4}-[0-9A-Z]{4}$/.test(document.querySelector(".vf-pair-code")?.textContent || "") && document.querySelector(".vf-pair-code").textContent.replace("-", "") !== c, code1));
    const code2 = (await shownCode()).replace("-", "");
    const laptop = await rec.open(A.localUrl);
    await until(laptop, () => !!document.querySelector("dialog.core-name[open] .core-host-code"));
    await laptop.click("dialog.core-name .core-host-code");
    await laptop.waitForTimeout(1100); // one try a second from one address, and every page here is the same address
    await laptop.fill("#core-code", "2222-2222");
    await laptop.click("dialog.core-name button:text-is('Sign in')");
    ok("the join dialog's code entry says when a code is wrong", await until(laptop, () => /wrong or has expired/.test(document.getElementById("core-code-err")?.textContent || "")));
    await laptop.waitForTimeout(1100);
    await laptop.fill("#core-code", code2.toLowerCase());
    await laptop.click("dialog.core-name button:text-is('Sign in')");
    ok("  and the right one, typed in lower case, signs this browser in as the host", await until(laptop, () => window.Core.snapshot()?.me?.role === "owner", null, 10000));
    ok("  where the settings offer no New owner link: it would hand over the owner link", await laptop.evaluate(() => { const b = [...document.querySelectorAll(".vf-menu-item")].filter(x => x.textContent === "New owner link"); return b.length === 1 && b[0].hidden; }));

    await until(host, () => document.querySelectorAll(".vf-pairlist .vf-pair-dev").length === 2);
    await host.locator(".vf-pairlist .vf-pair-dev", { hasText: "Phone" }).locator("button").click();
    ok("signing the phone out turns its page into a guest's join dialog, which says why", await until(phone, () => /signed out as the host/.test(document.querySelector("dialog.core-name[open]")?.textContent || "")
      && !localStorage.getItem("ownerDevice"), null, 10000));
    ok("  and the other device stays the host", await until(laptop, () => window.Core.snapshot()?.me?.role === "owner") && await until(host, () => document.querySelectorAll(".vf-pairlist .vf-pair-dev").length === 1));

    // ---------- a browser that keeps no site data, and a device holding a signed-out credential (review findings) ----------
    const C = await s.start("pair-edges");
    const hostC = await rec.open(C.ownerUrl);
    await until(hostC, () => window.Core.snapshot()?.me?.role === "owner", null, 10000);
    await hostC.click(".vf-person-me");
    await until(hostC, () => !!document.querySelector('.vf-pcard [data-k="pair"]'));
    await hostC.click('.vf-pcard [data-k="pair"]');
    const codeC = () => until(hostC, () => /^[0-9A-Z]{4}-[0-9A-Z]{4}$/.test(document.querySelector(".vf-pair-code")?.textContent || ""))
      .then(() => hostC.evaluate(() => document.querySelector(".vf-pair-code").textContent.replace("-", "")));
    const code3 = await codeC();
    // every storage write throws, as in a browser that blocks site data: core.js falls back to a map in the page
    const BLOCKED = { fn: () => { Storage.prototype.setItem = () => { throw new DOMException("blocked", "QuotaExceededError"); }; } };
    const noStore = await rec.open(`${C.localUrl}#join=${C.guestKey}&pair=${code3}`, { init: BLOCKED });
    ok("a browser that keeps no site data is told it cannot stay signed in as the host", await until(noStore, () => /site data/.test(document.querySelector("dialog.core-name[open]")?.textContent || ""), null, 10000),
      await noStore.evaluate(() => document.querySelector("dialog.core-name[open]")?.textContent || "(no dialog)"));
    await noStore.waitForTimeout(1100); // one try a second from one address
    const kept = await rec.open(`${C.localUrl}#join=${C.guestKey}&pair=${code3}`);
    ok("  and its code is not spent: a browser that keeps data signs in with it", await until(kept, () => window.Core.snapshot()?.me?.role === "owner", null, 10000));
    ok("  and the host's list shows only that one device", await until(hostC, () => document.querySelectorAll(".vf-pairlist .vf-pair-dev").length === 1));


    // ---------- names hidden: two guests share a name, and only the moderator's people list tells them apart ----------
    const B = await s.start("shared-name");
    s.apply(B.dir, [{ op: "set-title", title: "Names" }, { op: "open-round", questions: [q("Q1", "Where should we go?")] }]);
    const owner = await rec.open(B.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    await owner.evaluate(() => window.Core.saveSettings({ names: "someone" }));
    const sam1 = await rec.open(B.localUrl), sam1Pid = await joinAs(sam1, "Sam");
    const sam2 = await rec.open(B.localUrl), sam2Pid = await joinAs(sam2, "Sam");
    await owner.locator(".vf-seg .vf-seg-btn", { hasText: "Host" }).click();
    const nameOf = (page, pid) => page.evaluate(p => document.querySelector(`.vf-hperson:has([data-pid="${p}"]) .vf-hp-name`)?.textContent ?? null, pid);
    ok("the owner's people list numbers two people who share a name, in join order",
      await until(owner, ([a, b]) => [a, b].map(p => document.querySelector(`.vf-hperson:has([data-pid="${p}"]) .vf-hp-name`)?.textContent).map(t => t?.match(/ \((\d)\)$/)?.[1]).join() === "1,2", [sam1Pid, sam2Pid]),
      `${await nameOf(owner, sam1Pid)} | ${await nameOf(owner, sam2Pid)}`);
    ok("a guest's page shows no number", !(await sam1.evaluate(() => /\(\d\)/.test(document.body.innerText))));
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
