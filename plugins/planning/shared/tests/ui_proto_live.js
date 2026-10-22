#!/usr/bin/env node
// Live prototypes on the prototype page, in real browsers, against server.py with a stand-in live starter
// (fixtures/live_stub_server.py: Approve answers https://fake-live-<id>.trycloudflare.com, which no step opens, and starts nothing): the owner and a
// guest on a desktop, in separate browser contexts. Covered: a guest never sees a pending entry's link, only "Live
// version waiting for the host", and the owner sees Approve and Stop; Approve makes the entry run, and both then get
// "Open live prototype" in a new tab with no opener and no referrer, at the entry's origin plus the variant's path; a
// live-only variant says it opens in its own tab and is never framed; Stop ends it ("Live prototype ended", no link,
// no url in anyone's state); a server on a port needs the owner's attestation before Approve, and offers the owner a
// look on this machine first; turning live prototypes off ends every entry and takes the live view out of guests'
// pages; no page error, no CSP violation and no 429.
//   node plugins/planning/shared/tests/ui_proto_live.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the stand-in starter's origins, the variant paths written below, and the page's texts in
// the Design (section 4: "Live version waiting for the host", "Open live prototype"), never from the page.
"use strict";
const { spawn } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { loadPlaywright, suite, recorder, until, snap, joinAs, png, upOnSparePort, guestKey } = require("./browser_harness");

const q = (id, text, format) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format });
const ORIGIN = id => `https://fake-live-${id.toLowerCase()}.trycloudflare.com`;

/** server.py through the stand-in starter, on a spare port: {dir, proc, localUrl, ownerUrl, guestKey}. */
async function startStub(tmp) {
  const dir = path.join(tmp, "topic", "shared", "live");
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  const py = process.platform === "win32" ? "python" : "python3";
  return upOnSparePort(port => new Promise((resolve, reject) => {
    const proc = spawn(py, [path.join(__dirname, "fixtures", "live_stub_server.py"), "--dir", dir, "--guest-port", String(port), "--control-port", "0", "--nonce", "live"],
      { stdio: ["ignore", "ignore", "pipe"] });
    let err = "";
    proc.stderr.on("data", d => { err += d; });
    proc.on("exit", code => reject(new Error(`the server stopped (${code}): ${err.trim().split("\n").pop()}`)));
    const link = path.join(dir, ".owner-link");
    const tries = setInterval(() => {
      let ports = null;
      try { ports = JSON.parse(fs.readFileSync(path.join(dir, ".shared-ports.json"), "utf8")); } catch { return; }
      if (ports.guest !== port || !fs.existsSync(link)) return;
      clearInterval(tries);
      proc.removeAllListeners("exit");
      resolve({ dir, proc, localUrl: `http://127.0.0.1:${port}/`, ownerUrl: fs.readFileSync(link, "utf8").trim(), guestKey: guestKey(dir) });
    }, 100);
  }));
}

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_proto_live.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_proto_live"), { ok } = s, rec = recorder(browser);
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "shared-ui_proto_live-"));
  let A = null;
  try {
    A = await startStub(tmp);
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    await owner.evaluate(() => window.Core.saveSettings({ prototypeTiers: ["screenshot", "snapshot", "live"] }));
    const build = path.join(A.dir, "staging", "r1", "live");
    fs.mkdirSync(build, { recursive: true });
    fs.writeFileSync(path.join(build, "index.html"), "<!doctype html><p>Checkout app</p>");
    const shot = s.asset(A.dir, "a.png", png(300, 200, [60, 90]));
    const own = JSON.parse(fs.readFileSync(path.join(A.dir, ".shared-ports.json"), "utf8"));
    const devPort = [51731, 51732, 51733].find(p => p !== own.guest && p !== own.control); // add-live refuses the session's own ports
    // L3 is one the stand-in starter never starts (fixtures/live_stub_server.py FAILS): each Approve answers the same 502.
    const added = s.apply(A.dir, [{ op: "add-live", label: "Checkout app", folder: build }, { op: "add-live", label: "Dev server", port: devPort },
      { op: "add-live", label: "Broken build", folder: build }]).results;
    ok("add-live answers L1, L2 and L3, each pending", JSON.stringify(added) === JSON.stringify(["L1", "L2", "L3"].map(id => ({ id, status: "pending" }))), JSON.stringify(added));
    s.apply(A.dir, [{ op: "open-round", questions: [
      q("Q1", "Which checkout?", { kind: "prototype", lookAt: "The basket: add an item, then open it.", variants: [
        { id: "v-1", label: "Dense", shots: [shot], live: { id: "L1", path: "/?variant=A" } }, { id: "v-2", label: "Roomy", live: { id: "L1", path: "/?variant=B" } }] }),
      q("Q2", "Which dashboard?", { kind: "prototype", lookAt: "The first chart.", variants: [
        { id: "v-1", label: "On the dev server", live: { id: "L2", path: "/" } }, { id: "v-2", label: "Picture", asset: shot }] }),
      q("Q3", "Which settings page?", { kind: "prototype", lookAt: "The settings form.", variants: [
        { id: "v-1", label: "Broken", live: { id: "L3", path: "/" } }, { id: "v-2", label: "Picture", asset: shot }] }),
    ] }]);

    // ---------- pending: the guest waits and never holds a link; the owner gets Approve and Stop ----------
    const gctx = await browser.newContext({ viewport: { width: 1400, height: 900 } });
    // Each page change opens a tab of its own: a navigation's hidden-then-visible heartbeats land within a second, and
    // the 429 the second gets is not this suite's concern. The guest's identity is the context's (localStorage).
    const joined = await rec.openIn(gctx, `${A.localUrl}#join=${A.guestKey}`);
    await joinAs(joined, "Ann");
    let guest = await rec.openIn(gctx, `${A.localUrl}proto/Q1`);
    await joined.close();
    await until(guest, () => !!document.querySelector(".vp-livebox:not([hidden]) .vp-live-wait"));
    const leaked = page => page.evaluate(() => ({ links: [...document.querySelectorAll("a[href]")].map(a => a.href).filter(h => /fake-live-|127\.0\.0\.1:5173/.test(h)),
      state: /fake-live-/.test(JSON.stringify(window.Core.snapshot())), urls: (window.Core.snapshot().lives || []).filter(e => "url" in e).length }));
    const pend = await guest.evaluate(() => ({ wait: document.querySelector(".vp-live-wait")?.textContent || "", open: !!document.querySelector(".vp-live-open"),
      approve: !!document.querySelector(".vp-live-approve"), stop: !!document.querySelector(".vp-live-stop") }));
    ok("a guest sees Live version waiting for the host, and no link, Approve or Stop", pend.wait === "Live version waiting for the host" && !pend.open && !pend.approve && !pend.stop, JSON.stringify(pend));
    const gl = await leaked(guest);
    ok("a guest's page and state hold no link or url for a pending entry", !gl.links.length && !gl.state && !gl.urls, JSON.stringify(gl));
    // The owner link's fragment works on any of the session's pages: the owner's prototype page opens with it.
    const ownerAt = page => { const u = new URL(A.ownerUrl); u.pathname = page; return u.href; };
    let oproto = await rec.open(ownerAt("/proto/Q1"));
    await until(oproto, () => window.Core.snapshot()?.me?.role === "owner");
    await until(oproto, () => !!document.querySelector(".vp-live-approve"));
    const ownerPend = await oproto.evaluate(() => ({ wait: document.querySelector(".vp-live-wait")?.textContent || "", stop: !!document.querySelector(".vp-live-stop"), open: !!document.querySelector(".vp-live-open") }));
    ok("the owner sees the entry waiting for Approve, with Approve and Stop and no open link", ownerPend.wait === "Live version waiting for your Approve." && ownerPend.stop && !ownerPend.open, JSON.stringify(ownerPend));

    // ---------- Approve: both get Open live prototype, a new tab with no opener and no referrer ----------
    await oproto.locator(".vp-live-approve").click();
    const openOf = page => page.evaluate(() => { const a = document.querySelector(".vp-live-open"); return a && { href: a.getAttribute("href"), target: a.target, rel: a.rel, ref: a.referrerPolicy, text: a.textContent }; });
    const want = { href: `${ORIGIN("L1")}/?variant=A`, target: "_blank", rel: "noopener noreferrer", ref: "no-referrer", text: "Open live prototype" };
    await until(oproto, () => !!document.querySelector(".vp-live-open"));
    ok("after Approve the owner gets Open live prototype at the entry's origin and the variant's path", JSON.stringify(await openOf(oproto)) === JSON.stringify(want), JSON.stringify(await openOf(oproto)));
    await until(guest, () => !!document.querySelector(".vp-live-open"), undefined, 10000);
    ok("the guest then gets the same link, opening a new tab with rel noopener noreferrer", JSON.stringify(await openOf(guest)) === JSON.stringify(want), JSON.stringify(await openOf(guest)));
    ok("the guest's state now holds the running entry's origin", await guest.evaluate(o => (window.Core.snapshot().lives || []).some(e => e.id === "L1" && e.url === o && e.status.kind === "running"), ORIGIN("L1")));
    await guest.locator(".vp-tab", { hasText: "Roomy" }).click();
    await until(guest, () => document.querySelector(".vp-live-open")?.getAttribute("href")?.endsWith("variant=B"));
    const roomy = await guest.evaluate(() => ({ href: document.querySelector(".vp-live-open")?.getAttribute("href"), stage: document.querySelector(".vp-live-only")?.textContent || "",
      frames: [...document.querySelectorAll("iframe")].map(f => f.src).filter(s => /fake-live-/.test(s)).length }));
    ok("a live-only variant links its own path, says it opens in its own tab, and is never framed",
      roomy.href === `${ORIGIN("L1")}/?variant=B` && /opens in its own tab/.test(roomy.stage) && roomy.frames === 0, JSON.stringify(roomy));
    ok("the main page's question tile still offers Open prototype for a live-only question", await (async () => {
      const main = await rec.openIn(gctx, A.localUrl);
      await main.locator(".vf-q", { hasText: "Which checkout?" }).first().click();
      const shown = await until(main, () => !document.querySelector(".vf-proto")?.hidden && !document.querySelector(".vf-proto-go")?.hidden);
      await main.close();
      return shown;
    })());

    // ---------- Stop: ended, no link, no url anywhere ----------
    await oproto.locator(".vp-live-stop").click();
    await until(guest, () => document.querySelector(".vp-live-ended")?.textContent === "Live prototype ended", undefined, 10000);
    const ended = await guest.evaluate(() => ({ label: document.querySelector(".vp-live-ended")?.textContent || "", open: !!document.querySelector(".vp-live-open") }));
    ok("after Stop the guest sees Live prototype ended and no link", ended.label === "Live prototype ended" && !ended.open, JSON.stringify(ended));
    await until(oproto, () => !!document.querySelector(".vp-live-ended"));
    const oend = await oproto.evaluate(() => ({ open: !!document.querySelector(".vp-live-open"), approve: !!document.querySelector(".vp-live-approve"), stop: !!document.querySelector(".vp-live-stop"),
      url: (window.Core.snapshot().lives || []).filter(e => e.id === "L1" && ("url" in e || "url" in e.status)).length }));
    ok("the owner sees it ended too, with no link, Approve, Stop or url", !oend.open && !oend.approve && !oend.stop && !oend.url, JSON.stringify(oend));
    const gl2 = await leaked(guest);
    ok("the guest's page and state hold no url once it ended", !gl2.links.length && !gl2.state && !gl2.urls, JSON.stringify(gl2));

    // ---------- a server on a port: a look on this machine, and Approve only with the attestation ----------
    await oproto.close();
    oproto = await rec.open(ownerAt("/proto/Q2"));
    await until(oproto, () => window.Core.snapshot()?.me?.role === "owner");
    await until(oproto, () => !!document.querySelector(".vp-live-approve"));
    const port = await oproto.evaluate(() => ({ local: document.querySelector(".vp-live-local")?.getAttribute("href") || "", disabled: document.querySelector(".vp-live-approve")?.disabled,
      attest: !!document.querySelector(".vp-live-attest input") }));
    ok("for a port the owner gets a look on this machine, and Approve waits for the attestation",
      port.local === `http://127.0.0.1:${devPort}` && port.disabled === true && port.attest, JSON.stringify(port));
    await guest.close();
    guest = await rec.openIn(gctx, `${A.localUrl}proto/Q2`);
    await until(guest, () => !!document.querySelector(".vp-live-wait"));
    ok("the guest gets no look at the owner's machine", !(await guest.evaluate(() => !!document.querySelector(".vp-live-local") || /127\.0\.0\.1/.test(JSON.stringify(window.Core.snapshot().lives)))));
    await oproto.locator(".vp-live-attest input").check();
    await oproto.locator(".vp-live-approve").click();
    await until(guest, () => document.querySelector(".vp-live-open")?.getAttribute("href") === `https://fake-live-l2.trycloudflare.com/`, undefined, 10000);
    ok("with the attestation Approve runs it, and the guest gets its link", (await openOf(guest))?.href === `${ORIGIN("L2")}/`, JSON.stringify(await openOf(guest)));

    // ---------- a start that fails twice with the same error: Approve comes back, the error shows ----------
    const failing = await rec.open(ownerAt("/proto/Q3"));
    await until(failing, () => !!document.querySelector(".vp-live-approve"));
    for (const n of [1, 2]) {
      await until(failing, () => document.querySelector(".vp-live-approve")?.disabled === false, undefined, 5000);
      await Promise.all([failing.waitForResponse(r => new URL(r.url()).pathname === "/api/live/approve"), failing.locator(".vp-live-approve").click()]);
      await until(failing, () => document.querySelector(".vp-live-approve")?.disabled === false && !!document.querySelector(".vp-live-err"), undefined, 3000);
      const after = await failing.evaluate(() => ({ disabled: document.querySelector(".vp-live-approve")?.disabled, err: document.querySelector(".vp-live-err")?.textContent || "" }));
      ok(`after failed Approve ${n} of 2 Approve is enabled again and the error shows`, after.disabled === false && !!after.err, JSON.stringify(after));
    }
    await failing.close();

    // ---------- live prototypes off: every entry ends, and guests lose the live view ----------
    await owner.evaluate(() => window.Core.saveSettings({ prototypeTiers: ["screenshot", "snapshot"] }));
    await until(oproto, () => !!document.querySelector(".vp-live-ended"));
    ok("turning live prototypes off ends the running entry on the owner's page", await oproto.evaluate(() => (window.Core.snapshot().lives || []).every(e => e.status.kind === "ended")));
    await until(guest, () => document.querySelector(".vp-livebox")?.hidden === true, undefined, 10000);
    const off = await guest.evaluate(() => ({ box: document.querySelector(".vp-livebox")?.hidden, lives: (window.Core.snapshot().lives || []).length, stage: document.querySelector(".vp-off")?.textContent || "" }));
    ok("guests then get no live view: no box, no entry, the live-only variant reads as off", off.box === true && off.lives === 0 && /off in this session/.test(off.stage), JSON.stringify(off));

    // ---------- no errors ----------
    // The two failed Approves above each log their 502 to the console; nothing else may.
    const failed502 = rec.errors.filter(e => /status of 502/.test(e)), others = rec.errors.filter(e => !/status of 502/.test(e));
    ok("no page error or console error beyond the two expected 502s", others.length === 0 && failed502.length <= 2, rec.errors.join(" | "));
    const csp = await rec.cspViolations();
    ok("no CSP violation", csp.length === 0, csp.join(" | "));
    ok("no 429", rec.too.length === 0, rec.too.join(" | "));
    ok("the owner's state ends with no url anywhere", !/fake-live-/.test(JSON.stringify(await snap(owner))));
  } catch (e) {
    ok("the suite ran to the end", false, String(e && e.stack || e));
  } finally {
    await browser.close().catch(() => {});
    if (A) A.proc.kill();
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  return s.finish();
}

main().then(code => process.exit(code));
