#!/usr/bin/env node
// The Phase 4b formats in real browsers, against `share.sh ensure-running` with the fake cloudflared: the owner and a
// guest on desktops, and a guest on a 390x844 phone with touch, in a session past its first round (so the phone's
// Questions tab must take taps on the round toggle and the questions with two rounds listed). Covered: multi (checkboxes), scale (keyboard and touch),
// rank (keyboard, and a touch drag), None of these on a multi that asks for it (exclusive both ways, on the page and
// the server), "Something else…" on choice, multi and rank (the person's own option becomes a card
// others back), Disagree with a reason, the 👎 reaction, a diagram reference's alt text, the digest numbers where the
// page shows results, no Something else on confirm and prototype questions, no 429 and no CSP violation. ux-review-3:
// the confirm mark is drawn inside a phone-width picture, a pixel-sized rect from an earlier build is clamped into it,
// picture options keep both Choose buttons above the phone tab bar, and tapping an option's name picks it.
//   node plugins/planning/shared/tests/ui_formats.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the Phase 4b amendment (formats, Borda: first n-1, last 0; mean and median), the server
// contract (session.py pick, vote and disagree), and numbers worked out by hand below, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, settled, snap, joinAs, png } = require("./browser_harness");

const DIAGRAM_ALT = "Checkout flow: cart, then address, then payment, then review.";
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==", "base64");
const SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 40"><rect x="2" y="2" width="60" height="36" fill="none" stroke="black"/><text x="10" y="25">Cart</text></svg>';
const q = (id, text, format, extra = {}) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format, ...extra });

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_formats.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_formats"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("formats");
    const shot = s.asset(A.dir, "shot.png", PNG), svg = s.asset(A.dir, "flow.svg", SVG);
    const v1 = s.asset(A.dir, "v1.html", "<!doctype html><html><body><p>One</p></body></html>");
    const v2 = s.asset(A.dir, "v2.html", "<!doctype html><html><body><p>Two</p></body></html>");
    // Two rounds, as in a live session past its first: round 1 sent and closed, round 2 holds the formats.
    s.apply(A.dir, [{ op: "set-title", title: "Checkout formats" }, { op: "open-round", questions: [q("Q20", "Which browsers do your customers use?", { kind: "text" })] }]);
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    await owner.evaluate(() => window.Core.sendRound());
    s.apply(A.dir, [{ op: "ack-round", round: 1 }, { op: "open-round", questions: [
      q("Q1", "Which default payment method?", { kind: "choice", options: [{ id: "opt-1", label: "Card" }, { id: "opt-2", label: "Saved method" }] }),
      q("Q2", "Which payment methods should checkout offer?", { kind: "multi", options: [{ id: "opt-1", label: "Card" }, { id: "opt-2", label: "PayPal" }, { id: "opt-3", label: "Apple Pay" }, { id: "opt-4", label: "Bank transfer" }] }),
      q("Q3", "How urgent is the checkout redesign?", { kind: "scale", min: 1, max: 5, labels: { min: "Not urgent", max: "Very urgent", mid: "Somewhat" } }),
      q("Q4", "Rank the checkout steps by importance", { kind: "rank", options: [{ id: "opt-1", label: "Address" }, { id: "opt-2", label: "Shipping" }, { id: "opt-3", label: "Payment" }, { id: "opt-4", label: "Review" }] }),
      q("Q5", "Where should the order summary sit?", { kind: "text" }, { references: [{ kind: "diagram", asset: svg, alt: DIAGRAM_ALT, caption: "Checkout flow" }] }),
      q("Q6", "What worries you about the new checkout?", { kind: "text" }, { purpose: "gather" }),
      q("Q7", "Did you mean this button?", { kind: "confirm", image: shot, rect: { x: 10, y: 10, w: 30, h: 20 } }),
      q("Q8", "Which checkout layout?", { kind: "prototype", lookAt: "The checkout page.", variants: [{ id: "v-1", label: "Layout one", asset: v1 }, { id: "v-2", label: "Layout two", asset: v2 }] }),
    ] }]);
    await until(owner, () => (window.Core.snapshot()?.questions || []).some(x => x.id === "Q8"));

    const gus = await rec.open(A.localUrl);
    const gusPid = await joinAs(gus, "Gus");
    const pia = await rec.open(A.localUrl, { context: { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 } });
    const piaPid = await joinAs(pia, "Pia");
    ok("three people are in: the owner, a desktop guest and a phone guest", !!gusPid && !!piaPid && gusPid !== piaPid);
    const picks = { gus: 0 };
    gus.on("request", r => { if (new URL(r.url()).pathname === "/api/pick") picks.gus++; });

    const isPhone = p => p === pia;
    const press = (p, loc) => (isPhone(p) ? loc.tap({ timeout: 5000 }) : loc.click());
    async function go(p, qid, text) {
      if (isPhone(p)) await p.locator(".vf-tab", { hasText: "Questions" }).tap();
      await press(p, p.locator(".vf-q", { hasText: text }).first());
      return until(p, t => document.querySelector(".vf-qtext")?.textContent === t, text);
    }

    // ---------- the phone's Questions tab in a two-round session ----------
    await pia.locator(".vf-tab", { hasText: "Questions" }).tap();
    const r1 = pia.locator(".vf-round:not(.vf-round-cur) .vf-rtoggle");
    const tapped = async loc => loc.tap({ timeout: 5000 }).then(() => true, e => String(e.message).split("\n").find(x => /intercepts|Timeout/.test(x)) || "tap failed");
    const t1 = await tapped(r1);
    ok("phone, two rounds: the round 1 toggle takes the tap and opens the round", t1 === true && (await r1.getAttribute("aria-expanded")) === "true", t1);
    const t2 = await tapped(pia.locator(".vf-q", { hasText: "Which browsers do your customers use?" }));
    ok("phone, two rounds: a round 1 question in the list takes the tap and opens",
      t2 === true && await until(pia, () => document.querySelector(".vf-qtext")?.textContent === "Which browsers do your customers use?"), t2);
    ok("phone, two rounds: a round 2 question opens from the Questions tab", await go(pia, "Q5", "Where should the order summary sit?"));
    const cardOf = async (page, qid, ref) => (await snap(page))?.cards?.[qid]?.find(c => c.ref === ref);
    const server = (fn, arg, t) => until(owner, fn, arg, t);

    // ---------- choice: Something else… ----------
    const qs = (await snap(owner)).questions;
    const lastOpt = id => qs.find(x => x.id === id).format.options?.at(-1);
    ok("choice, multi and rank questions end with the server's Something else… option",
      ["Q1", "Q2", "Q4"].every(id => lastOpt(id)?.other === true && lastOpt(id)?.label === "Something else…"), JSON.stringify(["Q1", "Q2", "Q4"].map(lastOpt)));
    ok("confirm, prototype and scale questions carry no Something else option",
      !qs.find(x => x.id === "Q7").format.options && qs.find(x => x.id === "Q8").format.variants.every(v => !v.other) && !qs.find(x => x.id === "Q3").format.options);

    await go(gus, "Q1", "Which default payment method?");
    const other = gus.locator(".vf-opt.vf-opt-other");
    ok("the choice question shows a Something else… card", (await other.count()) === 1 && /Something else…/.test(await other.textContent()));
    await other.locator(".vf-optchoose").click();
    ok("choosing Something else… opens a box for one's own option", await until(gus, () => { const t = document.getElementById("vf-other"); return !!t?.offsetParent && document.activeElement === t; }));
    await gus.click(".vf-other-save");
    ok("an empty own option is not sent: the page asks for it", await until(gus, () => /Write your own option first/.test(document.querySelector(".vf-toast")?.textContent || "")) && picks.gus === 0, `picks sent: ${picks.gus}`);
    await gus.fill("#vf-other", "Pay on delivery");
    await gus.click(".vf-other-save");
    ok("submitting sends the own option: a person card with pick other and that text",
      await server(p => { const c = (window.Core.snapshot()?.cards?.Q1 || []).find(x => x.ref === "p:" + p); return c?.pick === "other" && c?.text === "Pay on delivery"; }, gusPid), JSON.stringify(await cardOf(owner, "Q1", `p:${gusPid}`)));

    const chipOn = (page, text) => page.evaluate(t => [...document.querySelectorAll(".vf-alist .vf-card")].find(c => c.textContent.includes(t))?.querySelector(".vf-pickchip-t")?.textContent, text);
    ok("Gus's own option card tells Gus it is his", await until(gus, () => [...document.querySelectorAll(".vf-alist .vf-card")].find(c => c.textContent.includes("Pay on delivery"))?.querySelector(".vf-pickchip-t")?.textContent === "Your own option"),
      await chipOn(gus, "Pay on delivery"));

    await go(owner, "Q1", "Which default payment method?");
    ok("the owner sees it as Gus's own option", await until(owner, () => [...document.querySelectorAll(".vf-alist .vf-card")].find(c => c.textContent.includes("Pay on delivery"))?.querySelector(".vf-pickchip-t")?.textContent === "Their own option"),
      await chipOn(owner, "Pay on delivery"));
    ok("the owner gets no Lock this one on Something else…, but does on a real option",
      await until(owner, () => { const o = document.querySelector(".vf-opt.vf-opt-other .vf-optlock"), r = document.querySelector(".vf-opt:not(.vf-opt-other) .vf-optlock"); return !!o && o.hidden && !!r && !r.hidden; }));

    await go(pia, "Q1", "Which default payment method?");
    await pia.locator(".vf-opt", { hasText: "Card" }).locator(".vf-optchoose").tap();
    ok("the phone guest picks Card by touch", await server(p => (window.Core.snapshot()?.cards?.Q1?.find(c => c.ref === "o:opt-1")?.votes || []).includes(p), piaPid));
    const gusOwn = pia.locator(".vf-alist .vf-card", { hasText: "Pay on delivery" });
    ok("Gus's own option shows as a card the phone guest can back", await until(pia, () => { const c = [...document.querySelectorAll(".vf-alist .vf-card")].find(x => /Pay on delivery/.test(x.textContent)); const v = c?.querySelector(".vf-vote"); return !!v && !v.hidden && !v.disabled; }));
    await gusOwn.locator(".vf-vote").tap();
    ok("on choice, backing someone's own option moves the one pick there",
      await server(([p, g]) => { const c1 = window.Core.snapshot().cards.Q1; return (c1.find(c => c.ref === "p:" + g)?.votes || []).includes(p) && !(c1.find(c => c.ref === "o:opt-1")?.votes || []).includes(p) && !c1.some(c => c.ref === "p:" + p); }, [piaPid, gusPid]),
      JSON.stringify((await snap(owner)).cards.Q1));

    const ownCardOwner = owner.locator(".vf-alist .vf-card", { hasText: "Pay on delivery" });
    ok("the owner gets Lock this one on Gus's own option card", await until(owner, () => { const c = [...document.querySelectorAll(".vf-alist .vf-card")].find(x => /Pay on delivery/.test(x.textContent)); return !!c && !c.querySelector(".vf-btn-brass-ghost").hidden; }));
    await ownCardOwner.locator(".vf-btn-brass-ghost", { hasText: "Lock this one" }).click();
    ok("Lock this one on the own option locks that person card", await server(g => window.Core.snapshot()?.locks?.Q1?.source?.card === "p:" + g, gusPid));

    // ---------- multi ----------
    await go(gus, "Q2", "Which payment methods should checkout offer?");
    for (const label of ["Card", "PayPal"]) await gus.locator(".vf-check-row", { hasText: label }).locator("input").check();
    await gus.click(".vf-fmt-save");
    ok("multi: a desktop guest saves a subset", await server(g => JSON.stringify((window.Core.snapshot().cards.Q2 || []).find(c => c.ref === "p:" + g)?.picks) === '["opt-1","opt-2"]', gusPid));

    await go(pia, "Q2", "Which payment methods should checkout offer?");
    await pia.locator(".vf-check-row", { hasText: "PayPal" }).locator("label").tap();
    await pia.locator(".vf-check-row", { hasText: "Something else…" }).locator("label").tap();
    ok("multi: ticking Something else… opens the own-option box", await until(pia, () => !!document.getElementById("vf-other")?.offsetParent));
    await pia.fill("#vf-other", "Gift cards");
    await pia.locator(".vf-fmt-save").tap();
    ok("multi: the phone guest's picks hold PayPal and her own option, by touch",
      await server(p => { const c = (window.Core.snapshot().cards.Q2 || []).find(x => x.ref === "p:" + p); return JSON.stringify(c?.picks) === '["opt-2","other"]' && c?.text === "Gift cards"; }, piaPid), JSON.stringify(await cardOf(owner, "Q2", `p:${piaPid}`)));

    await go(owner, "Q2", "Which payment methods should checkout offer?");
    await owner.locator(".vf-check-row", { hasText: "Apple Pay" }).locator("input").check();
    await owner.click(".vf-fmt-save");
    ok("multi: the owner saves one pick", await server(() => JSON.stringify((window.Core.snapshot().cards.Q2 || []).find(c => c.ref === "p:host")?.picks) === '["opt-3"]'));
    await until(owner, () => [...document.querySelectorAll(".vf-alist .vf-card")].some(x => /Gift cards/.test(x.textContent)));
    await owner.locator(".vf-alist .vf-card", { hasText: "Gift cards" }).locator(".vf-vote").click();
    ok("multi: backing Pia's own option is a separate vote; the owner's picks stay",
      await server(p => { const s2 = window.Core.snapshot(); return (s2.cards.Q2.find(c => c.ref === "p:" + p)?.votes || []).includes("host") && JSON.stringify(s2.cards.Q2.find(c => c.ref === "p:host")?.picks) === '["opt-3"]'; }, piaPid));
    // By hand: Card {Gus} 1, PayPal {Gus, Pia} 2, Apple Pay {owner} 1, Bank transfer 0; 3 people picked.
    const res = (page, k) => page.evaluate(id => document.querySelector(`.vf-fmtres-row[data-k="${id}"] .vf-fmtres-n`)?.textContent, k);
    ok("multi results: counts per option where results show", await until(owner, () => {
      const t = id => document.querySelector(`.vf-fmtres-row[data-k="${id}"] .vf-fmtres-n`)?.textContent;
      return t("opt-1") === "1 picked" && t("opt-2") === "2 picked" && t("opt-3") === "1 picked" && t("opt-4") === "0 picked" && document.querySelector(".vf-fmtres-sum")?.textContent === "3 people picked.";
    }), JSON.stringify(await Promise.all(["opt-1", "opt-2", "opt-3", "opt-4"].map(k => res(owner, k)))));

    // ---------- scale ----------
    await go(gus, "Q3", "How urgent is the checkout redesign?");
    ok("scale shows its end and middle labels", await until(gus, () => /1: Not urgent/.test(document.querySelector(".vf-scale-ends")?.textContent) && /3: Somewhat/.test(document.querySelector(".vf-scale-ends")?.textContent) && /5: Very urgent/.test(document.querySelector(".vf-scale-ends")?.textContent)));
    const before = picks.gus;
    await gus.locator('.vf-scale-btn[tabindex="0"]').focus();
    for (let i = 0; i < 4; i++) await gus.keyboard.press("ArrowRight");
    await gus.keyboard.press("ArrowLeft");
    ok("scale by keyboard: arrows land on 4 and send it", await server(g => (window.Core.snapshot().cards.Q3 || []).find(c => c.ref === "p:" + g)?.value === 4, gusPid));
    await gus.waitForTimeout(1500);
    ok("scale by keyboard: five arrow presses send one pick", picks.gus - before === 1, `${picks.gus - before} picks`);

    await go(pia, "Q3", "How urgent is the checkout redesign?");
    const two = pia.locator(".vf-scale-btn", { hasText: "2" });
    const box = await two.boundingBox();
    ok("scale on the phone: each value is a 44 px touch target", box && box.height >= 44, JSON.stringify(box));
    await two.tap();
    ok("scale by touch: the phone guest chooses 2", await server(p => (window.Core.snapshot().cards.Q3 || []).find(c => c.ref === "p:" + p)?.value === 2, piaPid));
    await go(owner, "Q3", "How urgent is the checkout redesign?");
    await owner.locator(".vf-scale-btn", { hasText: "5" }).click();
    // By hand: 2, 4, 5: mean 11 / 3 = 3.67 (2 places), median 4.
    ok("scale results: mean and median where results show", await until(owner, () => document.querySelector(".vf-fmtres-sum")?.textContent === "Mean 3.67, median 4, from 3 people."),
      await owner.evaluate(() => document.querySelector(".vf-fmtres-sum")?.textContent));
    ok("scale results: the count per value", await until(owner, () => document.querySelector('.vf-fmtres-row[data-k="4"] .vf-fmtres-n')?.textContent === "1 person" && document.querySelector('.vf-fmtres-row[data-k="1"] .vf-fmtres-n')?.textContent === "0 people"));

    // ---------- rank ----------
    await go(gus, "Q4", "Rank the checkout steps by importance");
    const item = (p, label) => p.locator(".vf-rank-item", { hasText: label });
    await item(gus, "Payment").locator(".vf-rank-grip").focus();
    await gus.keyboard.press("ArrowUp");
    await gus.keyboard.press("ArrowUp");
    ok("rank by keyboard: Payment moves to the top and keeps focus", await until(gus, () => [...document.querySelectorAll(".vf-rank-item .vf-rank-l")].map(x => x.textContent).join(",") === "Payment,Address,Shipping,Review"
      && document.activeElement?.closest(".vf-rank-item")?.textContent.includes("Payment")));
    await gus.click(".vf-fmt-own");
    await gus.fill("#vf-other", "Delivery date");
    await gus.click(".vf-other-save");
    ok("rank: Something else… adds one's own option to the ranking", await until(gus, () => document.querySelectorAll(".vf-rank-item").length === 5 && /Delivery date/.test(document.querySelector(".vf-rank-item:last-child").textContent)));
    await gus.click(".vf-fmt-save");
    ok("rank: the full order and the own option reach the server", await server(g => { const c = (window.Core.snapshot().cards.Q4 || []).find(x => x.ref === "p:" + g); return JSON.stringify(c?.order) === '["opt-3","opt-1","opt-2","opt-4","other"]' && c?.text === "Delivery date"; }, gusPid),
      JSON.stringify(await cardOf(owner, "Q4", `p:${gusPid}`)));

    await go(pia, "Q4", "Rank the checkout steps by importance");
    // Gus is on Q4, and his presence lands after the question renders: measure the handles once it shows, or the
    // drag starts on whatever moved under the finger.
    ok("rank by touch: the phone shows Gus on the question before the drag", await until(pia, () => [...document.querySelectorAll(":is(.vf-onit, .vf-qonit) .core-avatar")].some(a => a.offsetParent && a.dataset.name === "Gus")));
    const grip = item(pia, "Review").locator(".vf-rank-grip");
    await grip.scrollIntoViewIfNeeded();
    const g = await grip.boundingBox(), top = await item(pia, "Address").boundingBox();
    const cdp = await pia.context().newCDPSession(pia);
    const at = (x, y) => [{ x: Math.round(x), y: Math.round(y) }];
    const from = { x: g.x + g.width / 2, y: g.y + g.height / 2 }, to = { x: from.x, y: top.y + 4 };
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: at(from.x, from.y) });
    for (let i = 1; i <= 12; i++) { await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: at(from.x, from.y + (to.y - from.y) * i / 12) }); await pia.waitForTimeout(20); }
    // The finger rests before it lifts, as a person's does: a lift mid-move is a fling, and the next tap only stops it.
    await pia.waitForTimeout(200);
    await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: at(to.x, to.y) });
    await pia.waitForTimeout(150);
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    ok("rank by touch: dragging Review's handle to the top reorders", await until(pia, () => [...document.querySelectorAll(".vf-rank-item .vf-rank-l")].map(x => x.textContent).join(",") === "Review,Address,Shipping,Payment"),
      await pia.evaluate(() => [...document.querySelectorAll(".vf-rank-item .vf-rank-l")].map(x => x.textContent).join(",")));
    await pia.locator(".vf-fmt-save").tap();
    ok("rank by touch: the phone guest's order is saved", await server(p => JSON.stringify((window.Core.snapshot().cards.Q4 || []).find(c => c.ref === "p:" + p)?.order) === '["opt-4","opt-1","opt-2","opt-3"]', piaPid));
    await until(pia, () => [...document.querySelectorAll(".vf-alist .vf-card")].some(x => /Delivery date/.test(x.textContent)));
    await pia.locator(".vf-alist .vf-card", { hasText: "Delivery date" }).locator(".vf-vote").tap();
    ok("rank: backing Gus's own option is a vote outside the order", await server((gp) => (window.Core.snapshot().cards.Q4.find(c => c.ref === "p:" + gp)?.votes || []).length === 1, gusPid));

    await go(owner, "Q4", "Rank the checkout steps by importance");
    await owner.click(".vf-fmt-save");
    ok("rank: the owner saves the order as given", await server(() => JSON.stringify((window.Core.snapshot().cards.Q4 || []).find(c => c.ref === "p:host")?.order) === '["opt-1","opt-2","opt-3","opt-4"]'));
    // By hand, Borda with 4 options (3, 2, 1, 0), own options left out (opt-1 Address, opt-2 Shipping, opt-3 Payment, opt-4 Review):
    //   Gus Payment,Address,Shipping,Review; Pia Review,Address,Shipping,Payment; owner Address,Shipping,Payment,Review
    //   Address 2+2+3 = 7, Shipping 1+1+2 = 4, Payment 3+0+1 = 4, Review 0+3+0 = 3; a tie keeps the given order.
    const rankRows = () => owner.evaluate(() => [...document.querySelectorAll(".vf-fmtres-row")].map(r => `${r.dataset.k}:${r.querySelector(".vf-fmtres-n").textContent}`).join(","));
    ok("rank results: Borda totals, highest first", await until(owner, () => [...document.querySelectorAll(".vf-fmtres-row")].map(r => `${r.dataset.k}:${r.querySelector(".vf-fmtres-n").textContent}`).join(",")
      === "opt-1:7 points,opt-2:4 points,opt-3:4 points,opt-4:3 points"), await rankRows());
    ok("rank results: the summary names the rule", await until(owner, () => document.querySelector(".vf-fmtres-sum")?.textContent === "Borda points from 3 rankings: first place gets 3, last gets 0."));

    // ---------- decide: Disagree; a diagram reference ----------
    await go(owner, "Q5", "Where should the order summary sit?");
    await owner.fill("#vf-answer", "Below the total, collapsed.");
    await owner.press("#vf-answer", "Control+Enter");
    await go(gus, "Q5", "Where should the order summary sit?");
    await until(gus, () => [...document.querySelectorAll(".vf-alist .vf-card")].some(x => /Below the total/.test(x.textContent)));
    const ownerCard = gus.locator(".vf-alist .vf-card", { hasText: "Below the total" });
    let disagrees = 0;
    gus.on("request", r => { if (new URL(r.url()).pathname === "/api/disagree") disagrees++; });
    await ownerCard.locator(".vf-disagree-btn").click();
    ok("Disagree opens a reason field capped at 200 characters", await until(gus, () => { const i = document.querySelector(".vf-card .vf-dis-in"); return !!i?.offsetParent && i.maxLength === 200 && document.activeElement === i; }));
    await ownerCard.locator(".vf-dis-send").click();
    ok("Disagree without a reason is not sent", await until(gus, () => /Say why you disagree first/.test(document.querySelector(".vf-toast")?.textContent || "")) && disagrees === 0);
    await ownerCard.locator(".vf-dis-in").fill("x".repeat(250));
    ok("the reason field holds at most 200 characters", (await ownerCard.locator(".vf-dis-in").inputValue()).length === 200);
    await ownerCard.locator(".vf-dis-in").fill("It hides the total on phones.");
    await ownerCard.locator(".vf-dis-send").click();
    ok("Disagree with a reason reaches the server and leaves the votes alone",
      await server(gp => { const s2 = window.Core.snapshot(); const d = s2.disagreements?.Q5 || []; return d.length === 1 && d[0].pid === gp && d[0].card === "p:host" && d[0].reason === "It hides the total on phones." && (s2.cards.Q5.find(c => c.ref === "p:host")?.votes || []).length === 0; }, gusPid),
      JSON.stringify((await snap(owner)).disagreements));
    ok("the owner sees the reason on the answer", await until(owner, () => [...document.querySelectorAll(".vf-alist .vf-card .vf-dis")].some(x => /It hides the total on phones\./.test(x.textContent))));
    const dImg = gus.locator('.vf-ref[data-kind="diagram"] img');
    ok("the diagram reference shows the SVG with its alt text", (await dImg.count()) === 1 && (await dImg.getAttribute("alt")) === DIAGRAM_ALT
      && await until(gus, () => document.querySelector('.vf-ref[data-kind="diagram"] img')?.naturalWidth > 0));
    await gus.locator('.vf-ref[data-kind="diagram"] .vf-ref-img').click();
    ok("the diagram opens in the viewer with its alt text", await until(gus, a => { const i = document.querySelector(".vf-lb-img"); return !!i?.offsetParent && i.alt === a; }, DIAGRAM_ALT));
    await gus.keyboard.press("Escape");

    // ---------- gather: the four reactions, 👎 included ----------
    await go(owner, "Q6", "What worries you about the new checkout?");
    await owner.fill("#vf-answer", "Losing the saved card.");
    await owner.press("#vf-answer", "Control+Enter");
    await go(gus, "Q6", "What worries you about the new checkout?");
    await until(gus, () => [...document.querySelectorAll(".vf-alist .vf-card")].some(x => /Losing the saved card/.test(x.textContent)));
    const gatherCard = gus.locator(".vf-alist .vf-card", { hasText: "Losing the saved card" });
    ok("a gather answer offers 👍 👎 ❤️ 💡", (await gatherCard.locator(".vf-react .vf-react-g").allTextContents()).join(" ") === "👍 👎 ❤️ 💡");
    await gatherCard.locator('.vf-react[data-r="down"]').click();
    ok("👎 reaches the server", await server(() => window.Core.snapshot()?.cards?.Q6?.find(c => c.ref === "p:host")?.reactions?.down === 1));

    // ---------- no Something else on confirm and prototype questions ----------
    await go(gus, "Q7", "Did you mean this button?");
    // Only what shows counts: innerText and offsetParent skip the hidden controls of other formats.
    const shown = sel => `[...document.querySelectorAll("${sel}")].filter(e => e.offsetParent)`;
    ok("a confirm question shows no Something else… option or own-option box", await until(gus, new Function(`return !document.querySelector(".vf-fmt").hidden
      && ${shown(".vf-opt-other, .vf-check-other, .vf-rank-own")}.length === 0 && !/Something else…/.test(document.querySelector(".vf-fmt").innerText) && !document.getElementById("vf-other").offsetParent`)));
    // Answer first (the session default) hides others' picks until you pick, in the picture viewer as on the card.
    await owner.evaluate(() => window.Core.pick("Q7", "opt-yes"));
    await until(gus, () => window.Core.snapshot()?.cards?.Q7?.some(c => c.votes?.length));
    await gus.locator(".vf-confirm-fig .vf-imgbtn").click();
    await until(gus, () => !document.querySelector(".vf-lb").hidden);
    ok("answer first: the picture viewer shows no Yes/No counts before the guest picks",
      await gus.evaluate(() => { const p = document.querySelector(".vf-lb-picks"); return p.hidden && !/Yes \d/.test(document.querySelector(".vf-lb").innerText); }));
    await gus.locator(".vf-lb .vf-lb-yn", { hasText: "No" }).click();
    ok("after picking, the picture viewer shows the counts (owner Yes, guest No)",
      await until(gus, () => document.querySelector(".vf-lb-picks")?.textContent === "Yes 1, No 1"));
    await gus.keyboard.press("Escape");
    await go(gus, "Q8", "Which checkout layout?");
    ok("a prototype question shows its variants and no Something else…", await until(gus, new Function(`return ${shown(".vf-opts .vf-opt")}.length === 2
      && ${shown(".vf-opt-other")}.length === 0 && !/Something else…/.test(document.querySelector(".vf-fmt").innerText)`)));

    // ---------- ux-review-3: the confirm mark and size, picture options on a phone, tapping an option's name ----------
    // A 390x844 phone screenshot with a dark "button" band over rows 700-760; in percent of the picture that is
    // y 82.9-90.0 (700 / 844, 760 / 844), so the rect below marks it.
    const B = await s.start("ux3");
    const phoneShot = s.asset(B.dir, "phone.png", png(390, 844, [700, 760]));
    const pa = s.asset(B.dir, "a.png", png(1440, 900)), pb = s.asset(B.dir, "b.png", png(1440, 900, [100, 200]));
    s.apply(B.dir, [{ op: "open-round", questions: [
      q("Q1", "Which checkout layout looks right?", { kind: "choice", options: [{ id: "opt-1", label: "One column", image: pa }, { id: "opt-2", label: "Two columns", image: pb }] }),
      q("Q2", "Did you mean this button?", { kind: "confirm", image: phoneShot, rect: { x: 10, y: 83, w: 80, h: 7 } }),
      q("Q3", "Which default payment method?", { kind: "choice", options: [{ id: "opt-1", label: "Card" }, { id: "opt-2", label: "Saved method" }] }),
      q("Q4", "Which shipping speed should be the default?", { kind: "choice", options: [{ id: "opt-1", label: "Standard" }, { id: "opt-2", label: "Express" }] }, { purpose: "poll" }),
      q("Q5", "Which wallets do you already use?", { kind: "multi", none: true, options: [{ id: "opt-1", label: "Apple Wallet" }, { id: "opt-2", label: "Google Wallet" }] }),
    ] }]);
    const PHONE = { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 };
    const nia = await rec.open(B.localUrl, { context: PHONE });
    const niaPid = await joinAs(nia, "Nia");
    const tabTop = () => nia.evaluate(() => document.querySelector(".vf-tabs")?.getBoundingClientRect().top ?? innerHeight);
    await until(nia, () => document.querySelector(".vf-qtext")?.textContent === "Which checkout layout looks right?");
    const firstStill = await settled(nia, { rects: true });
    const chooseBottoms = await nia.evaluate(() => [...document.querySelectorAll(".vf-opt:not(.vf-opt-other) .vf-optchoose")].filter(e => e.offsetParent).map(e => Math.round(e.getBoundingClientRect().bottom)));
    const tabs = await tabTop();
    ok("phone, picture options: both Choose buttons are above the tab bar at first view", firstStill && chooseBottoms.length === 2 && chooseBottoms.every(b => b <= tabs),
      `${chooseBottoms} vs tab bar ${tabs}${firstStill ? "" : ", not settled"}`);
    // The mark is inside the picture and inside the part of it on screen; the picture uses the column's width.
    // Measured once the page holds still; a page that does not counts as neither inside nor seen.
    const markIn = async page => { const still = await settled(page, { rects: true }), m = await page.evaluate(() => {
      const f = document.querySelector(".vf-confirm-fig"), r = e => e.getBoundingClientRect();
      const box = r(f.querySelector(".vf-confirm-box")), img = r(f.querySelector(".vf-confirm-img")), m = r(f.querySelector(".vf-confirm-mark"));
      const inside = (a, b) => a.left >= b.left - 1 && a.right <= b.right + 1 && a.top >= b.top - 1 && a.bottom <= b.bottom + 1;
      const drawn = !f.querySelector(".vf-confirm-mark").hidden && m.width > 0 && m.height > 0 && inside(m, img);
      return { ok: drawn && inside(m, box), seen: drawn && m.top < box.bottom && m.bottom > box.top, box: [box.width, box.height].map(Math.round), m: [m.left, m.top, m.width, m.height].map(Math.round), img: [img.top, img.height].map(Math.round), col: Math.round(r(f).width) };
    }); return { ...m, still, ok: still && m.ok, seen: still && m.seen }; };
    await nia.locator(".vf-tab", { hasText: "Questions" }).tap();
    await nia.locator(".vf-q", { hasText: "Did you mean this button?" }).first().tap();
    await until(nia, () => document.querySelector(".vf-confirm-img")?.naturalWidth > 0 && !document.querySelector(".vf-confirm-fig").hidden);
    let mk = await markIn(nia);
    ok("confirm on a phone: the marked area is drawn inside the picture and on screen", mk.ok, JSON.stringify(mk));
    ok("confirm on a phone: the picture spans the column (at least 90% of it), not a 115 px strip", mk.box[0] >= 0.9 * mk.col, JSON.stringify(mk));
    // By hand: 80% of the box width marks the band; a 60 px band in 844 at the box's scale is at least 40 px tall.
    ok("confirm on a phone: the marked band is big enough to see (at least 40 px tall)", mk.m[3] >= 40, JSON.stringify(mk));
    // Tapping an option's name picks it (Q3 has no pictures, so the name is the card's only text).
    await nia.locator(".vf-tab", { hasText: "Questions" }).tap();
    await nia.locator(".vf-q", { hasText: "Which default payment method?" }).first().tap();
    await until(nia, () => document.querySelector(".vf-qtext")?.textContent === "Which default payment method?");
    await nia.locator(".vf-opt .vf-optlabel", { hasText: "Saved method" }).tap();
    ok("tapping an option's name picks that option", await until(nia, p => (window.Core.snapshot()?.cards?.Q3?.find(c => c.ref === "o:opt-2")?.votes || []).includes(p), niaPid));
    // A poll closes only as a whole: the owner sees Close poll and no Lock this one, on an option or on a person's own option.
    await nia.evaluate(() => window.Core.pick("Q4", "other", undefined, { other: "Next day" }));
    const bOwner = await rec.open(B.ownerUrl);
    await until(bOwner, () => window.Core.snapshot()?.me?.role === "owner");
    await bOwner.evaluate(() => window.Core.pick("Q4", "opt-1"));
    await bOwner.locator(".vf-q", { hasText: "Which shipping speed should be the default?" }).first().click();
    await until(bOwner, () => document.querySelector(".vf-qtext")?.textContent === "Which shipping speed should be the default?"
      && [...document.querySelectorAll(".vf-alist .vf-card")].some(c => /Next day/.test(c.textContent)));
    const pollLocks = () => bOwner.evaluate(() => [...document.querySelectorAll("button")].filter(b => b.offsetParent && b.textContent.trim() === "Lock this one").length);
    const closePoll = bOwner.locator("button", { hasText: "Close poll" });
    ok("poll, as the owner: Close poll shows and no Lock this one shows on any option or answer card",
      await until(bOwner, () => [...document.querySelectorAll("button")].some(b => b.offsetParent && b.textContent.trim() === "Close poll")) && (await pollLocks()) === 0,
      `${await pollLocks()} Lock this one visible`);
    // Standard 1 (the owner), Nia's own option 1: a tie, and a poll still closes as a tally with no winner.
    await closePoll.click();
    ok("poll, as the owner: Close poll closes a tied poll as a tally (no card), and Unlock shows",
      await until(bOwner, () => JSON.stringify(window.Core.snapshot()?.locks?.Q4?.source) === '{"kind":"poll"}' && [...document.querySelectorAll("button")].some(b => b.offsetParent && b.textContent.trim() === "Unlock")),
      JSON.stringify((await snap(bOwner))?.locks?.Q4));

    // ---------- multi: None of these, which the server adds when the format asks and keeps apart from every other pick ----------
    const q5 = (await snap(bOwner)).questions.find(x => x.id === "Q5").format.options;
    ok("multi with none: the server adds None of these after Something else…", JSON.stringify(q5.slice(-2).map(o => [o.id, o.label, !!o.other, !!o.none])) === '[["other","Something else…",true,false],["none","None of these",false,true]]', JSON.stringify(q5));
    await bOwner.locator(".vf-q", { hasText: "Which wallets do you already use?" }).first().click();
    await until(bOwner, () => document.querySelector(".vf-qtext")?.textContent === "Which wallets do you already use?");
    const row5 = label => bOwner.locator(".vf-check-row", { hasText: label });
    const picks5 = () => bOwner.evaluate(() => JSON.stringify((window.Core.snapshot().cards.Q5 || []).find(c => c.ref === "p:host")?.picks));
    const saved5 = want => until(bOwner, w => JSON.stringify((window.Core.snapshot().cards.Q5 || []).find(c => c.ref === "p:host")?.picks) === w, want);
    ok("None of these looks like Something else…", (await row5("None of these").getAttribute("class")).includes("vf-check-other"));
    await row5("Apple Wallet").locator("input").check();
    await row5("None of these").locator("input").check();
    ok("ticking None of these clears the other picks on the page", !(await row5("Apple Wallet").locator("input").isChecked()) && await row5("None of these").locator("input").isChecked());
    await bOwner.click(".vf-fmt-save");
    ok("None of these saves as the only pick", await saved5('["none"]'), await picks5());
    await row5("Google Wallet").locator("input").check();
    ok("ticking another option clears None of these on the page", !(await row5("None of these").locator("input").isChecked()) && await row5("Google Wallet").locator("input").isChecked());
    await bOwner.click(".vf-fmt-save");
    ok("the saved picks no longer hold None of these", await saved5('["opt-2"]'), await picks5());
    // The server enforces it too: a page that sends both keeps the pick just made.
    const both = await bOwner.evaluate(() => window.Core.pickWith("Q5", { options: ["opt-2", "none"] }, {}).then(() => "", e => String(e)));
    ok("the server keeps None of these alone when it is the pick just made", !both && await saved5('["none"]'), both || await picks5());
    await bOwner.close();
    // A state.json the 6579f21 build wrote can hold a pixel-sized rect (it took any number); it loads as it is and
    // the page clamps the mark into the picture.
    await nia.close();
    s.share(B.dir, "stop");
    const statePath = require("node:path").join(B.dir, "state.json"), fsx = require("node:fs");
    const doc = JSON.parse(fsx.readFileSync(statePath, "utf8"));
    doc.questions.find(x => x.id === "Q2").format.rect = { x: 40, y: 700, w: 300, h: 60 };
    fsx.writeFileSync(statePath, JSON.stringify(doc));
    s.share(B.dir, "ensure-running", "--guest-port", new URL(B.localUrl).port);
    const ola = await rec.open(B.localUrl, { context: PHONE });
    await joinAs(ola, "Ola");
    await ola.locator(".vf-tab", { hasText: "Questions" }).tap();
    await ola.locator(".vf-q", { hasText: "Did you mean this button?" }).first().tap();
    await until(ola, () => document.querySelector(".vf-confirm-img")?.naturalWidth > 0 && !document.querySelector(".vf-confirm-fig").hidden);
    ok("a pixel-sized rect from an earlier build loads and the page clamps its mark into the picture",
      (await snap(ola)).questions.find(x => x.id === "Q2").format.rect?.y === 700 && (mk = await markIn(ola)).seen, JSON.stringify(mk));

    // ---------- the phone layout and the page rules ----------
    await go(pia, "Q2", "Which payment methods should checkout offer?");
    ok("on the phone the options fit the width", await pia.evaluate(() => { const f = document.querySelector(".vf-fmt"); return f.scrollWidth <= f.clientWidth + 1; }));
    ok("no request was answered 429 (slow down)", rec.too.length === 0, rec.too.slice(0, 5).join(", "));
    const csp = await rec.cspViolations();
    ok("no page broke the server's CSP", csp.length === 0, csp.slice(0, 3).join(" | "));
    ok("no page error or console error", rec.errors.length === 0, rec.errors.slice(0, 3).join(" | "));
  } catch (e) {
    s.results.push(`ERROR ${e?.stack || e}`);
  } finally {
    await browser.close().catch(() => {});
  }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
