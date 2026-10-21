#!/usr/bin/env node
// Presence dots in a real browser, against `share.sh ensure-running` with the fake cloudflared, on the owner's page:
// the header row (its count says "Only you here" when no one else is), the empty view's row of who is here and the Host view's people list each show a dot at the
// avatar's bottom-right (Active filled --ok, Away filled --away with a clock hand, Offline a hollow --faint ring)
// in a ring of the surface it sits on; no name or avatar is dimmed; the people list runs you, Active, Away, then
// Offline with the most recently seen first; the header shows present people only; avatar labels name the state;
// and each dot measures at least 3:1 against its ring and its surface in dark and light, read from computed styles
// through a canvas so the colors are the sRGB the browser paints (oklch may be gamut-mapped).
//   node plugins/planning/shared/tests/ui_presence_dots.js   (about 2 minutes: two people go offline)
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from triage row 40 and research/presence-indicator/RESEARCH-recommendation.md (states,
// order, 3:1 for a non-text indicator, WCAG 1.4.11) and session.py OFFLINE_AFTER (90 s), never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const OFFLINE_AFTER = 90; // seconds: session.py OFFLINE_AFTER
const text = (id, t) => ({ id, text: t, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });

/** In the page: every presence dot under `scope`, measured in dark and light. Per dot: its state, the dot's color,
 *  ring and surface as sRGB, and the dot's contrast against each. */
function measure(scope) {
  const cv = document.createElement("canvas"); cv.width = cv.height = 1;
  const cx = cv.getContext("2d", { willReadFrequently: true });
  const rgb = c => { cx.clearRect(0, 0, 1, 1); cx.fillStyle = "#000"; cx.fillStyle = c; cx.fillRect(0, 0, 1, 1); return [...cx.getImageData(0, 0, 1, 1).data]; };
  const lum = ([r, g, b]) => { const f = v => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }; return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b); };
  const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((m, n) => n - m); return (x + 0.05) / (y + 0.05); };
  const surface = el => { for (let e = el; e; e = e.parentElement) { const c = getComputedStyle(e).backgroundColor; const v = rgb(c); if (v[3] === 255 && c !== "rgba(0, 0, 0, 0)") return v; } return [255, 255, 255, 255]; };
  const root = document.querySelector(".app"), was = root.dataset.theme, out = {};
  for (const theme of ["dark", "light"]) {
    root.dataset.theme = theme;
    out[theme] = [...document.querySelectorAll(`${scope} .vf-pres`)].map(d => {
      const av = d.parentElement, st = av.dataset.presence, cs = getComputedStyle(d);
      const dot = rgb(st === "offline" ? cs.borderTopColor : cs.backgroundColor);
      const ring = rgb(cs.boxShadow.match(/^(\w+\([^)]*\)|#\w+)/)?.[1] || "transparent");
      const surf = surface(av.parentElement);
      return { pid: av.dataset.pid, st, dot, ring, surf, vsRing: ratio(dot, ring), vsSurface: ratio(dot, surf), ringIsSurface: ring.slice(0, 3).every((v, i) => Math.abs(v - surf[i]) <= 2),
        hidden: d.getAttribute("aria-hidden") === "true", hollow: st === "offline" ? rgb(cs.backgroundColor).slice(0, 3).every((v, i) => Math.abs(v - surf[i]) <= 2) : true };
    });
  }
  root.dataset.theme = was;
  return out;
}

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_presence_dots.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_presence_dots"), { ok } = s, rec = recorder(browser);
  const good = (what, rows) => {
    const bad = rows.filter(r => !(r.vsRing >= 3 && r.vsSurface >= 3 && r.ringIsSurface && r.hidden && r.hollow));
    ok(what, rows.length > 0 && bad.length === 0, JSON.stringify(bad.slice(0, 2)));
    const low = Object.entries(Object.groupBy(rows, r => r.st)).map(([st, rs]) => `${st} ${Math.min(...rs.map(r => Math.min(r.vsRing, r.vsSurface))).toFixed(2)}`);
    console.log(`  lowest contrast, ${what.trim().split(" ")[1]}: ${low.join(", ")}`);
  };
  try {
    const A = await s.start("dots");
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    // The header count with no one else here: a bare "1 here" read as a guest count to the owner (S10:5), so it says who.
    ok("alone on the page, the header count says only you are here", await until(owner, () => document.querySelector(".vf-here")?.textContent === "Only you here"),
      await owner.evaluate(() => document.querySelector(".vf-here")?.textContent));
    // Fay leaves first and Eve a few seconds later, so Eve is the more recently seen of the two offline people.
    const fay = await rec.open(A.localUrl), fayPid = await joinAs(fay, "Fay");
    const eve = await rec.open(A.localUrl), evePid = await joinAs(eve, "Eve");
    const bo = await rec.open(A.localUrl), boPid = await joinAs(bo, "Bo");
    const cai = await rec.open(A.localUrl), caiPid = await joinAs(cai, "Cai");
    await cai.evaluate(() => window.Core.setAway(true));
    await fay.context().close();
    const leftAt = Date.now();
    await owner.waitForTimeout(4000);
    await eve.context().close();

    // ---------- the empty view: who is here, with their dots ----------
    ok("Cai shows Away and Bo Active on the owner's page", await until(owner, ([b, c]) => {
      const p = Object.fromEntries(window.Core.state.presence.map(x => [x.cid, x.away]));
      return p[b] === false && p[c] === true;
    }, [boPid, caiPid], 10000));
    const evRow = () => owner.evaluate(() => Object.fromEntries([...document.querySelectorAll(".vf-ev-here .core-avatar")].map(a => [a.dataset.pid, [a.dataset.presence, a.getAttribute("aria-label"), !!a.querySelector(".vf-pres")]])));
    ok("the empty view's row shows Bo active and Cai away, each with a dot and the state in its label", await until(owner, ([b, c]) => {
      const row = Object.fromEntries([...document.querySelectorAll(".vf-ev-here .core-avatar")].map(a => [a.dataset.pid, a]));
      const ok1 = (a, st, label) => a?.dataset.presence === st && !!a.querySelector(".vf-pres") && a.getAttribute("aria-label") === label;
      return ok1(row[b], "active", "Bo, active") && ok1(row[c], "away", "Cai, away");
    }, [boPid, caiPid], 10000), JSON.stringify(await evRow()));
    good("  each empty-view dot is 3:1 against its ring and its surface, dark and light", Object.values(await owner.evaluate(measure, ".vf-ev-here")).flat());

    // ---------- Fay and Eve go offline ----------
    ok(`Fay and Eve go offline about ${OFFLINE_AFTER} s after they left`, await until(owner, ps => ps.every(p => !window.Core.state.presence.some(x => x.cid === p)), [fayPid, evePid], (OFFLINE_AFTER + 20) * 1000));
    ok("  not before", (Date.now() - leftAt) / 1000 >= OFFLINE_AFTER - 5);
    s.apply(A.dir, [{ op: "open-round", questions: [text("Q1", "Where should the order summary sit?")] }]);
    await owner.locator(".vf-seg .vf-seg-btn", { hasText: "Host" }).click();

    // ---------- the people list ----------
    const want = ["host", boPid, caiPid, evePid, fayPid];
    const states = { host: "active", [boPid]: "active", [caiPid]: "away", [evePid]: "offline", [fayPid]: "offline" };
    ok("the people list runs you, Active, Away, then Offline with the most recently seen first", await until(owner, w => {
      const order = [...document.querySelectorAll(".vf-hpeople .vf-hperson .vf-hp-av .core-avatar")].map(a => a.dataset.pid);
      return order.join() === w.join();
    }, want, 10000), await owner.evaluate(() => [...document.querySelectorAll(".vf-hpeople .vf-hp-av .core-avatar")].map(a => a.dataset.name).join(", ")));
    const rows = await owner.evaluate(() => [...document.querySelectorAll(".vf-hpeople .vf-hperson")].map(li => {
      const a = li.querySelector(".vf-hp-av .core-avatar"), nm = li.querySelector(".vf-hp-name");
      const dim = e => { for (let x = e; x && x !== li.parentElement; x = x.parentElement) { const cs = getComputedStyle(x); if (cs.opacity !== "1" || cs.filter !== "none") return true; } return false; };
      return { pid: a.dataset.pid, st: a.dataset.presence, dot: !!a.querySelector(".vf-pres"), label: a.getAttribute("aria-label"), meta: li.querySelector(".vf-hp-meta").textContent, dimmed: dim(a) || dim(nm) };
    }));
    ok("each person's avatar carries their state and a dot", rows.length === 5 && rows.every(r => r.dot && r.st === states[r.pid]), JSON.stringify(rows));
    ok("no name or avatar is dimmed, offline and away included", rows.every(r => !r.dimmed), JSON.stringify(rows.filter(r => r.dimmed)));
    const by = Object.fromEntries(rows.map(r => [r.pid, r]));
    ok("avatar labels name the state", by[boPid]?.label === "Bo, active, show details" && /^Cai, away( \d+ (?:min|h|d))?, show details$/.test(by[caiPid]?.label || "") && by[evePid]?.label === "Eve, offline, show details",
      JSON.stringify(rows.map(r => r.label)));
    ok("the status text stays: Away, and Offline with when they were last active", by[caiPid]?.meta.startsWith("Away") && /^Offline, last active \d+ (?:min|h|d) ago/.test(by[evePid]?.meta || "") && by[boPid]?.meta.startsWith("Active"),
      JSON.stringify(rows.map(r => r.meta)));
    good("each people-list dot is 3:1 against its ring and its surface, dark and light, offline a hollow ring", Object.values(await owner.evaluate(measure, ".vf-hpeople")).flat());

    // ---------- the header row: present people only ----------
    const head = await owner.evaluate(() => [...document.querySelectorAll(".vf-people .vf-person")].map(b => ({ pid: b.dataset.pid, label: b.getAttribute("aria-label"), st: b.firstChild?.dataset.presence, dot: !!b.querySelector(".vf-pres"),
      dimmed: [b, b.firstChild].some(e => getComputedStyle(e).opacity !== "1" || getComputedStyle(e).filter !== "none") })));
    ok("the header shows present people only, Active before Away", head.map(h => h.pid).join() === ["host", boPid, caiPid].join(), JSON.stringify(head));
    ok("  and the count beside it says 3 here", await owner.evaluate(() => document.querySelector(".vf-here")?.textContent) === "3 here", await owner.evaluate(() => document.querySelector(".vf-here")?.textContent));
    ok("  each with its dot and state, none dimmed", head.every(h => h.dot && h.st === states[h.pid] && !h.dimmed), JSON.stringify(head));
    ok("  and the state in its label", /^Cai, away( \d+ (?:min|h|d))?\. Show details$/.test(head.find(h => h.pid === caiPid)?.label || "") && head.find(h => h.pid === boPid)?.label === "Bo, active. Show details", JSON.stringify(head.map(h => h.label)));
    good("each header dot is 3:1 against its ring and its surface, dark and light", Object.values(await owner.evaluate(measure, ".vf-people")).flat());

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
