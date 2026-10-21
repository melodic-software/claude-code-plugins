#!/usr/bin/env node
// The prototype page (Q98) in real browsers, against `share.sh ensure-running` with the fake cloudflared: the owner on a
// desktop, a guest on a desktop who opens the prototype from the question's "Open prototype" link, and a guest on a
// 390x844 phone with touch who opens /proto/<qid> directly, in separate browser contexts (separate storage). Covered:
// the preview tile and its link; the variant switcher (click and arrow keys); the Annotate toggle; a note pinned to an
// element inside an html variant (its path and box reach the server, its pin is drawn in the variant, and the variant's
// own click handler does not run while Annotate is on); a note on a spot of a picture variant; the notes in the
// question's Claude thread on the main page and in the round's digest for Claude; picking a variant; the variant's
// sandbox (no access to the page or its storage, and a forged pin message is ignored); a second pick while a note is
// open; a variant that navigates its frame away (dropped, and the page it goes to refused); the owner token kept out of every link and
// the address bar, the owner still the owner after a reload and on the pages its links open; the phone layout; no 429,
// no CSP violation and no page error.
//   node plugins/planning/shared/tests/ui_proto.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the Design (Q98 row, Annotation, /api/annotate), the variant markup written below (its
// element paths worked out by hand), and click points chosen below, never from the page.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { loadPlaywright, suite, recorder, until, snap, joinAs, png, openClaude } = require("./browser_harness");

// The html variant. Its button's path, from its markup: html > body(1st) > main(1st) > section(1st) > div(1st) > button(1st).
const BUTTON_PATH = "html > body:nth-of-type(1) > main:nth-of-type(1) > section:nth-of-type(1) > div:nth-of-type(1) > button:nth-of-type(1)";
const VARIANT = `<!doctype html><html><head><style>body{margin:0;font:16px sans-serif}section{height:1400px;padding:24px}</style></head>
<body><header><h1>Checkout</h1></header><main><section><p>Order total: 42</p><div><button id="pay">Pay now</button></div><p id="out"></p><p id="sec"></p></section></main>
<script>
document.getElementById("pay").addEventListener("click", () => { document.getElementById("out").textContent = "paid"; });
const sec = [];
try { sec.push(parent.document.title !== undefined ? "parent-read" : "parent-read"); } catch (e) { sec.push("parent-blocked"); }
try { localStorage.getItem("secret"); sec.push("storage-read"); } catch (e) { sec.push("storage-blocked"); }
document.getElementById("sec").textContent = sec.join(",");
// A hostile variant forges the pin helper's message with a script-shaped selector; the page must ignore it.
addEventListener("message", e => { if (e.data && e.data.type === "mode" && e.data.on) parent.postMessage({ type: "pinned", selector: "<img src=x onerror=alert(1)>", rect: { x: 0, y: 0, w: 10, h: 10 }, label: "forged" }, "*"); });
</script></body></html>`;
// A hostile variant: once loaded it sends its own frame to another page, which then talks like the pin helper (ready,
// and a pin on "html", a path the page would take) and shows a sign-in form inside the session's page. The other page
// is an asset of the same session, so the page's frame-src 'self' lets the frame go there, but the server refuses it
// (401): a navigation the sandboxed frame starts comes from an opaque origin, so its request carries no SameSite=Strict
// asset cookie (decision 1: assets only for joined people and the owner).
const ELSEWHERE = `<!doctype html><p id="evil">Sign in again</p><script>parent.postMessage({ type: "ready" }, "*");
setInterval(() => parent.postMessage({ type: "pinned", selector: "html", rect: { x: 0, y: 0, w: 10, h: 10 }, label: "evil" }, "*"), 100);</script>`;
const leaver = to => `<!doctype html><html><body><p>Loading</p><script>
addEventListener("load", () => setTimeout(() => { location.href = "/assets/${to}"; }, 300));
</script></body></html>`;
const q = (id, text, format, extra = {}) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format, ...extra });
const PHONE = { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 };

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_proto.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_proto"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("proto");
    const v1 = s.asset(A.dir, "v1.html", VARIANT), v2 = s.asset(A.dir, "v2.png", png(300, 200, [80, 120])), elsewhere = s.asset(A.dir, "elsewhere.html", ELSEWHERE), v3 = s.asset(A.dir, "v3.html", leaver(elsewhere));
    s.apply(A.dir, [{ op: "set-title", title: "Checkout prototype" }, { op: "open-round", questions: [
      q("Q1", "Which checkout layout?", { kind: "prototype", variants: [{ id: "v-1", label: "One page", asset: v1 }, { id: "v-2", label: "Two steps", asset: v2 }] }),
      q("Q2", "What should the pay button say?", { kind: "text" }),
      q("Q3", "Which sign-in page?", { kind: "prototype", variants: [{ id: "v-1", label: "Leaves", asset: v3 }, { id: "v-2", label: "Picture", asset: v2 }] }),
    ] }]);
    const ownerToken = new URL(A.ownerUrl).hash.replace(/^#owner=/, "");
    const owner = await rec.open(A.ownerUrl);
    // Every request the server answers 401, in the contexts whose pages the error check below covers.
    const refused = [], hear401 = ctx => ctx.on("response", r => { if (r.status() === 401) refused.push(`${r.request().method()} ${new URL(r.url()).pathname}`); });
    hear401(owner.context());
    await until(owner, () => (window.Core.snapshot()?.questions || []).some(x => x.id === "Q1"));
    await owner.locator(".vf-q", { hasText: "Which checkout layout?" }).first().click();

    // ---------- the preview tile and "Open prototype" ----------
    await until(owner, () => !document.querySelector(".vf-proto")?.hidden);
    const tile = await owner.evaluate(() => ({ img: document.querySelector(".vf-proto-tile img")?.getAttribute("src") || "",
      href: document.querySelector(".vf-proto-open")?.getAttribute("href") || "", text: document.querySelector(".vf-proto-open")?.textContent || "",
      meta: document.querySelector(".vf-proto-meta")?.textContent || "" }));
    ok("the question shows a preview tile from its picture variant", tile.img === `/assets/${v2}`, tile.img);
    ok("the owner's Open prototype link holds no owner token", tile.text === "Open prototype" && tile.href === "/proto/Q1", tile.href);
    ok("the tile names both variants", tile.meta.startsWith("2 variants: One page, Two steps."), tile.meta);

    // ---------- the owner token stays out of the address bar and every link ----------
    const tokenShown = page => page.evaluate(t => ({ hash: location.hash, hrefs: [...document.querySelectorAll("a[href]")].map(a => a.href).filter(h => h.includes(t)) }), ownerToken);
    const isOwner = page => until(page, () => window.Core.snapshot()?.me?.role === "owner");
    const shown = await tokenShown(owner);
    ok("the owner page takes the token out of its address and no link holds it", shown.hash === "" && shown.hrefs.length === 0, JSON.stringify(shown));
    // Reloads run in a context of their own: a reload's hidden-then-visible beats land within a second, and the 429
    // the second gets is not this suite's concern.
    const solo = await (await browser.newContext({ viewport: { width: 1400, height: 900 } })).newPage();
    await solo.goto(A.ownerUrl);
    await isOwner(solo);
    await solo.reload();
    ok("the owner is still the owner after a reload, the token still out of the address", await isOwner(solo) && (await solo.evaluate(() => location.hash)) === "");
    await solo.locator(".vf-q", { hasText: "Which checkout layout?" }).first().click();
    await until(solo, () => !document.querySelector(".vf-proto")?.hidden);
    const [ownerProto] = await Promise.all([solo.context().waitForEvent("page"), solo.locator(".vf-proto-open").click()]);
    await ownerProto.waitForLoadState();
    ok("the owner's Open prototype opens /proto/Q1 as the owner", new URL(ownerProto.url()).pathname === "/proto/Q1" && await isOwner(ownerProto), ownerProto.url());
    await until(ownerProto, () => document.querySelector(".vp-back")?.getAttribute("href") === "/");
    const protoShown = await tokenShown(ownerProto);
    ok("the prototype tab's address and links hold no owner token", protoShown.hash === "" && protoShown.hrefs.length === 0, JSON.stringify(protoShown));
    ok("the prototype tab has no handle on the page that opened it", (await ownerProto.evaluate(() => window.opener)) === null);
    await ownerProto.reload();
    ok("the owner is still the owner on the prototype tab after a reload", await isOwner(ownerProto));
    ok("a link within the owner's page still moves within it, no token in the address", await solo.evaluate(() => {
      const a = document.createElement("a");
      a.href = "#vf-answer";
      document.body.append(a);
      a.click();
      a.remove();
      return location.pathname === "/" && location.hash === "#vf-answer";
    }));
    await solo.context().close();

    // ---------- desktop guest: opens the prototype from the question ----------
    const gus = await rec.open(A.localUrl);
    hear401(gus.context());
    const gusPid = await joinAs(gus, "Gus");
    await gus.locator(".vf-q", { hasText: "Which checkout layout?" }).first().click();
    await until(gus, () => !document.querySelector(".vf-proto")?.hidden);
    const [proto] = await Promise.all([gus.context().waitForEvent("page"), gus.locator(".vf-proto-open").click()]);
    proto.on("pageerror", e => rec.errors.push(String(e)));
    proto.on("console", m => { if (m.type() === "error") rec.errors.push(m.text()); });
    proto.on("response", r => { if (r.status() === 429) rec.too.push(`${r.request().method()} ${new URL(r.url()).pathname}`); });
    await proto.waitForLoadState();
    ok("the link opens /proto/Q1 in a new tab", new URL(proto.url()).pathname === "/proto/Q1", proto.url());
    ok("the prototype page knows the guest without a second join",
      await until(proto, pid => window.Core.snapshot()?.me?.pid === pid && !document.querySelector("dialog.core-name"), gusPid));
    await until(proto, () => document.querySelectorAll(".vp-tab").length === 2);
    const head = await proto.evaluate(() => ({ title: document.querySelector(".vp-title").textContent, tabs: [...document.querySelectorAll(".vp-tab")].map(b => [b.textContent, b.getAttribute("aria-selected")]),
      src: document.querySelector(".vp-frame")?.getAttribute("src"), sandbox: document.querySelector(".vp-frame")?.getAttribute("sandbox") }));
    ok("the page names the question and lists both variants, the first selected", head.title === "Q1: Which checkout layout?"
      && JSON.stringify(head.tabs) === JSON.stringify([["One page", "true"], ["Two steps", "false"]]), JSON.stringify(head));
    ok("the html variant is framed from /assets/ with the pin helper and a script-only sandbox", head.src === `/assets/${v1}?pin=1` && head.sandbox === "allow-scripts", JSON.stringify(head));

    const fb = await proto.locator(".vp-frame").boundingBox(), sb = await proto.locator(".vp-side").boundingBox();
    ok("desktop: the variant fills the stage beside the notes column", fb.height > 600 && fb.width > 800 && sb.x >= fb.x + fb.width - 1, JSON.stringify([fb, sb]));
    const frame = proto.frameLocator(".vp-frame");
    await frame.locator("#sec").waitFor();
    const sec = await frame.locator("#sec").textContent();
    ok("the variant cannot reach the page or any storage (opaque-origin sandbox)", sec === "parent-blocked,storage-blocked", sec);
    await frame.locator("#pay").click();
    ok("with Annotate off the variant is live: its own button works", (await frame.locator("#out").textContent()) === "paid");
    await frame.locator("#out").evaluate(el => { el.textContent = ""; });

    // ---------- Annotate: pin a note to the variant's button ----------
    await proto.locator(".vp-annotate").click();
    ok("Annotate turns on and says so", (await proto.locator(".vp-annotate").getAttribute("aria-pressed")) === "true");
    await proto.waitForTimeout(600);
    ok("a forged pin message with a script-shaped selector opens nothing", await proto.locator(".vp-composer").isHidden());
    await frame.locator("#pay").click();
    ok("with Annotate on, clicking an element opens a note about it", await until(proto, () => !document.querySelector(".vp-composer").hidden
      && document.querySelector(".vp-where").textContent === "Note on “Pay now”"));
    ok("the variant's own handler did not run under Annotate", (await frame.locator("#out").textContent()) === "");
    await frame.locator("h1").click();
    await proto.waitForTimeout(300);
    ok("a second pick while the note is open leaves its anchor alone", (await proto.locator(".vp-where").textContent()) === "Note on “Pay now”");
    await proto.locator("#vp-note").fill("Make the total sit next to Pay now.");
    await proto.locator(".vp-save").click();
    const serverSaw = () => until(owner, n => (window.Core.snapshot()?.annotations || []).length === n, 1);
    ok("the note reaches the server", await serverSaw());
    const a1 = (await snap(owner)).annotations[0];
    const r = a1.anchor.rect;
    ok("the note is pinned to the button's element path", a1.anchor.selector === BUTTON_PATH && a1.variant === "v-1" && a1.pid === gusPid, a1.anchor.selector);
    ok("its box is in percent of the variant's page, the button near the top", r.x >= 0 && r.w > 0 && r.x + r.w <= 100 && r.y + r.h <= 100 && r.y < 15, JSON.stringify(r));
    ok("the notes list shows it with its number", await until(proto, () => document.querySelector(".vp-notes li")?.textContent.includes("Make the total sit next to Pay now.")
      && document.querySelector(".vp-notes .vp-pin")?.textContent === "1"));
    ok("its pin is drawn on the variant", await frame.locator("html > div[aria-hidden=true] > div", { hasText: "1" }).first().isVisible());
    await proto.keyboard.press("Escape");
    ok("Escape turns Annotate off", (await proto.locator(".vp-annotate").getAttribute("aria-pressed")) === "false");

    // ---------- the variant switcher ----------
    await proto.locator(".vp-tab", { hasText: "Two steps" }).click();
    ok("the switcher shows the picture variant", await until(proto, () => document.querySelector(".vp-img")?.naturalWidth === 300 && !document.querySelector(".vp-frame")
      && location.hash === "#v=v-2"));
    await proto.locator(".vp-tab[aria-selected=true]").press("ArrowLeft");
    ok("ArrowLeft moves back to One page and keeps focus on the switcher", await until(proto, () => document.querySelector(".vp-tab[aria-selected=true]")?.textContent.startsWith("One page")
      && document.activeElement?.classList.contains("vp-tab") && !!document.querySelector(".vp-frame")));
    ok("the One page tab counts its note", (await proto.locator(".vp-tab", { hasText: "One page" }).getAttribute("aria-label")) === "One page, 1 note");
    await proto.locator(".vp-annotate").click();
    await proto.locator(".vp-whole").click();
    await until(proto, () => !document.querySelector(".vp-composer").hidden);
    await proto.locator(".vp-tab", { hasText: "Two steps" }).click();
    ok("switching variants closes an open note, whose spot was on the other one, and a new note can start", await until(proto, () => document.querySelector(".vp-composer").hidden
      && !document.querySelector(".vp-whole").hidden && document.querySelector(".vp-tab[aria-selected=true]")?.textContent.startsWith("Two steps")));
    await proto.keyboard.press("Escape"); // Annotate off

    // ---------- a note on a spot of the picture variant ----------
    await proto.locator(".vp-tab", { hasText: "Two steps" }).click();
    await until(proto, () => document.querySelector(".vp-img")?.naturalWidth === 300);
    await proto.locator(".vp-annotate").click();
    const box = await proto.locator(".vp-img").boundingBox();
    await proto.mouse.click(box.x + box.width / 2, box.y + box.height / 2); // the middle: 50%, 50%
    await until(proto, () => !document.querySelector(".vp-composer").hidden);
    await proto.locator("#vp-note").fill("This band hides the address.");
    await proto.waitForTimeout(1100); // one write a second per person per route
    await proto.locator(".vp-save").click();
    ok("a picture note reaches the server", await until(owner, () => (window.Core.snapshot()?.annotations || []).length === 2));
    const a2 = (await snap(owner)).annotations[1];
    // A 6% box centered on the click at 50%, 50%: x = y = 47, within one CSS pixel of the 300x200 picture (0.5%).
    const near = (v, want) => Math.abs(v - want) <= 0.5;
    const ar = a2.anchor.rect;
    ok("the picture note is the spot clicked, in percent of the picture", a2.anchor.selector === "img" && a2.variant === "v-2"
      && near(ar.x, 47) && near(ar.y, 47) && ar.w === 6 && ar.h === 6, JSON.stringify(a2.anchor));
    ok("its pin sits on the picture where the note is", await until(proto, () => {
      const p = document.querySelector(".vp-layer .vp-pin");
      return !!p && Math.abs(parseFloat(p.style.left) - 50) <= 0.5 && Math.abs(parseFloat(p.style.top) - 50) <= 0.5;
    }));
    await proto.keyboard.press("Escape");

    // ---------- pick a variant ----------
    const COMMENT = "Two steps reads calmer.";
    const gusCard = () => owner.evaluate(pid => (window.Core.snapshot()?.cards?.Q1 || []).find(c => c.pid === pid) || null, gusPid);
    await gus.evaluate(t => window.Core.answerCiting("Q1", t, []), COMMENT);
    await until(proto, t => window.Core.answersFor("Q1").some(a => a.cid === window.Core.me.cid && a.text === t), COMMENT);
    await proto.locator(".vp-choose").click();
    ok("Choose picks the shown variant", await until(owner, pid => (window.Core.snapshot()?.cards?.Q1 || []).some(c => c.pid === pid && c.pick === "v-2"), gusPid));
    ok("the button then says it is the choice", await until(proto, () => document.querySelector(".vp-choose").textContent === "You chose Two steps"));
    ok("  and the person's comment stays on their card", (await gusCard())?.text === COMMENT, JSON.stringify(await gusCard()));
    await proto.waitForTimeout(1100); // one write a second per person per route
    await proto.locator(".vp-choose").click();
    ok("pressing it again clears the choice and keeps the comment", await until(owner, ([pid, t]) => (window.Core.snapshot()?.cards?.Q1 || []).some(c => c.pid === pid && !c.pick && c.text === t), [gusPid, COMMENT]),
      JSON.stringify(await gusCard()));

    // ---------- phone guest in another browser context, straight to /proto/Q1 ----------
    const pia = await rec.open(new URL("/proto/Q1", A.localUrl).href, { context: PHONE });
    hear401(pia.context());
    const piaPid = await joinAs(pia, "Pia");
    ok("a phone opening the prototype first joins on that page", !!piaPid && piaPid !== gusPid);
    await until(pia, () => document.querySelectorAll(".vp-notes li").length === 1);
    ok("the phone sees the desktop guest's note on One page", (await pia.locator(".vp-notes li").first().textContent()).includes("Make the total sit next to Pay now."));
    const layout = await pia.evaluate(() => {
      const r = el => document.querySelector(el).getBoundingClientRect();
      return { overflow: document.documentElement.scrollWidth - innerWidth, stage: r(".vp-stage"), side: r(".vp-side"),
        tabs: [...document.querySelectorAll(".vp-tab, .vp-annotate, .vp-choose")].map(b => Math.round(b.getBoundingClientRect().height)) };
    });
    ok("phone: nothing runs past the width", layout.overflow <= 0, layout.overflow);
    ok("phone: the variant sits above the notes, both on screen", layout.stage.bottom <= layout.side.top + 1 && layout.stage.height > 200 && layout.side.top < 844 && layout.side.height > 100, JSON.stringify(layout));
    ok("phone: the switcher, Annotate and Choose are at least 40 px tall", layout.tabs.every(h => h >= 40), JSON.stringify(layout.tabs));
    await pia.locator(".vp-annotate").tap();
    await pia.locator(".vp-whole").tap();
    await pia.locator("#vp-note").fill("Too long for a phone.");
    await pia.locator(".vp-save").tap();
    ok("phone: a note on the whole variant reaches the server", await until(owner, pid => (window.Core.snapshot()?.annotations || []).some(a => a.pid === pid
      && a.anchor.selector === "html" && JSON.stringify(a.anchor.rect) === JSON.stringify({ x: 0, y: 0, w: 100, h: 100 })), piaPid));

    // ---------- the notes in the question's Claude thread, and for Claude ----------
    ok("the owner's Claude thread on Q1 lists the three notes", await until(owner, () => document.querySelectorAll(".vf-thnote").length === 3));
    const th = await owner.evaluate(() => [...document.querySelectorAll(".vf-thnote")].map(li => ({ text: li.querySelector(".vf-thnote-text").textContent, href: li.querySelector(".vf-thnote-go").getAttribute("href") })));
    ok("the thread shows each note's text", th.map(x => x.text).join("|") === "Make the total sit next to Pay now.|This band hides the address.|Too long for a phone.", JSON.stringify(th));
    ok("each note links to its variant and pin on the prototype page, with no owner token", th[0].href === "/proto/Q1#v=v-1&n=A1", th[0].href);
    ok("the Claude section opens to show them", await openClaude(owner));
    const [notePage] = await Promise.all([owner.context().waitForEvent("page"), owner.locator(".vf-thnote-go").first().click()]);
    await notePage.waitForLoadState();
    ok("the owner following a note opens its variant and pin as the owner, the token out of the address",
      await isOwner(notePage) && (await notePage.evaluate(() => location.hash)) === "#v=v-1&n=A1"
      && await until(notePage, () => document.querySelector(".vp-note-on") && document.querySelector(".vp-tab[aria-selected=true]")?.textContent.startsWith("One page")), notePage.url());
    await notePage.close();

    // ---------- a variant that sends its frame to another page ----------
    const away = await rec.openIn(gus.context(), new URL("/proto/Q3", A.localUrl).href);
    ok("a variant that navigates its frame away is dropped with a notice", await until(away, () => !document.querySelector(".vp-frame")
      && document.querySelector(".vp-left")?.textContent.startsWith("This variant tried to leave its page")));
    await away.locator(".vp-annotate").click();
    await away.waitForTimeout(800);
    ok("the page it went to is refused and opens no note", refused.includes(`GET /assets/${elsewhere}`) && await away.locator(".vp-composer").isHidden(), refused.join(", "));
    ok("Load it again frames the variant afresh", await away.evaluate(() => { document.querySelector(".vp-left button").click(); return !!document.querySelector(".vp-frame"); }));
    ok("and drops it again when it leaves again", await until(away, () => !document.querySelector(".vp-frame") && !!document.querySelector(".vp-left")));
    await away.keyboard.press("Escape");
    await owner.evaluate(() => window.Core.sendRound());
    const doc = JSON.parse(fs.readFileSync(path.join(A.dir, "state.json"), "utf8"));
    const digest = doc.log.events.find(e => e.kind === "round-sent")?.digest;
    ok("the round's digest hands Claude each note with its element", JSON.stringify(digest?.annotations?.map(x => [x.variant, x.element, x.text])) === JSON.stringify([
      ["v-1", BUTTON_PATH, "Make the total sit next to Pay now."], ["v-2", "img", "This band hides the address."], ["v-1", "html", "Too long for a phone."]]), JSON.stringify(digest?.annotations));
    await owner.evaluate(() => window.Core.endSession(true));
    ok("once the session ends, a guest's Choose is disabled and says the session has ended (B6)", await until(proto, () => {
      const b = document.querySelector(".vp-choose"); return b.disabled && b.title === "This session has ended."; }),
      await proto.evaluate(() => document.querySelector(".vp-choose").title));

    ok("no request was answered 429 (slow down)", rec.too.length === 0, rec.too.slice(0, 5).join(", "));
    const csp = [...await rec.cspViolations(), ...(await proto.evaluate(() => window.__csp || []))];
    ok("no page broke the server's CSP", csp.length === 0, csp.slice(0, 3).join(" | "));
    const left = `GET /assets/${elsewhere}`;
    ok("the only 401s are the leaving variant's two trips to the other page", JSON.stringify(refused) === JSON.stringify([left, left]), refused.join(", "));
    let expected401 = refused.length; // each refused load also logs one console error; drop only those
    const errors = rec.errors.filter(e => !(expected401 > 0 && e.includes("status of 401") && expected401--));
    ok("no page error or console error", errors.length === 0, errors.slice(0, 3).join(" | "));
  } catch (e) {
    s.results.push(`ERROR ${e?.stack || e}`);
  } finally {
    await browser.close().catch(() => {});
  }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
