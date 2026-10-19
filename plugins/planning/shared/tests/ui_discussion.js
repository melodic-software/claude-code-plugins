#!/usr/bin/env node
// The Discussion under each question (item 10), against `share.sh ensure-running` with the fake cloudflared: it starts
// folded under the Claude section, its head counts the comments and the ones new to this person, and opening it
// clears that count on the server; a comment's author edits and deletes it, nobody else can; the owner hides any,
// leaving it to its author marked Hidden; the composer says @Claude sends it to Claude, and such a comment becomes a
// request in the host's queue whose card, and later answer, link back with "from Discussion"; on a 390-wide phone the
// section fits the screen with nothing scrolling sideways.
//   node plugins/planning/shared/tests/ui_discussion.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected values come from the approved spec (.work spec-question-screen.md, followups item 10, mockup variant A) and
// the texts this suite writes, never from the page.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs, openClaude } = require("./browser_harness");

const ANN1 = "Should the summary stay pinned on phones?", ANN1_EDIT = "Should the summary stay pinned on phones and tablets?";
const OFF = "Unrelated: lunch at noon?", BO_ASK = "@Claude what do the big shops do on phones?", ANSWER = "Most keep a sticky total bar at the bottom.";
const q = (id, text) => ({ id, text, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } });
const PHONE = { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true };

const head = page => page.evaluate(() => ({ open: document.querySelector(".vf-disc-head").getAttribute("aria-expanded"), body: document.querySelector(".vf-disc-body").hidden,
  count: document.querySelector(".vf-disc-count").textContent, fresh: document.querySelector(".vf-disc-new").hidden ? "" : document.querySelector(".vf-disc-new").textContent }));
const shown = page => page.evaluate(() => [...document.querySelectorAll(".vf-disc-list > .vf-cm")].map(li => ({
  name: li.querySelector(".vf-cm-name").textContent, text: li.querySelector(".vf-cm-txt").textContent, edited: !li.querySelector(".vf-cm-edited").hidden,
  hidden: !li.querySelector(".vf-cm-hidden").hidden, isNew: !li.querySelector(".vf-cm-new").hidden,
  acts: [...li.querySelectorAll(".vf-cm-acts .vf-lbtn")].filter(b => !b.hidden).map(b => b.textContent),
  became: li.querySelector(".vf-cm-became").hidden ? "" : li.querySelector(".vf-cm-became-t").textContent })));
const openDisc = async page => { if ((await page.getAttribute(".vf-disc-head", "aria-expanded")) !== "true") await page.click(".vf-disc-head"); return until(page, () => !document.querySelector(".vf-disc-body").hidden); };
/** Post through the composer once the last post finished (its field cleared, Post enabled again). */
const post = async (page, text) => {
  await until(page, () => !document.querySelector(".vf-disc-post").disabled && !document.querySelector(".vf-disc-ta").value);
  await page.fill(".vf-disc-ta", text); await page.click(".vf-disc-post");
  return until(page, t => (window.Core.state.discussions.Q1 || []).some(c => c.text === t), text, 10000);
};
const cm = (page, text) => page.locator(".vf-disc-list > .vf-cm", { hasText: text });

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_discussion.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_discussion"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("discussion");
    s.apply(A.dir, [{ op: "set-title", title: "Discussion checks" }, { op: "open-round", questions: [q("Q1", "Where should the order summary sit?")] }]);
    const desk = { context: { viewport: { width: 1440, height: 900 } } };
    const owner = await rec.open(A.ownerUrl, desk);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    const ann = await rec.open(A.localUrl, desk);
    await joinAs(ann, "Ann");
    const bo = await rec.open(A.localUrl, { context: PHONE });
    await joinAs(bo, "Bo");

    // ---------- folded by default, below the Claude section ----------
    let h = await head(ann);
    ok("the Discussion starts folded, reading No comments yet", h.open === "false" && h.body && h.count === "No comments yet" && !h.fresh, JSON.stringify(h));
    ok("  and sits right after the Claude section", await ann.evaluate(() => document.querySelector(".vf-clsec").nextElementSibling === document.querySelector(".vf-disc")));
    await openDisc(ann);
    ok("the composer says @Claude sends it to Claude", await ann.evaluate(() => document.querySelector(".vf-disc-hint").textContent === "Type @Claude to send it to Claude."));
    ok("Ann's two comments show in her open Discussion", await post(ann, ANN1) && await post(ann, OFF) && await until(ann, () => document.querySelectorAll(".vf-disc-list > .vf-cm").length === 2));

    // ---------- N new, cleared on open, on the server ----------
    ok("the host's folded head reads 2 comments and 2 new", await until(owner, () => document.querySelector(".vf-disc-count").textContent === "2 comments" && document.querySelector(".vf-disc-new").textContent === "2 new"), JSON.stringify(await head(owner)));
    ok("  and stays folded", (await head(owner)).body);
    ok("Ann's own comments are not new to her", (await head(ann)).fresh === "");
    await openDisc(owner);
    let rows = await shown(owner);
    ok("opening shows both, each marked new", rows.length === 2 && rows.every(r => r.isNew), JSON.stringify(rows));
    ok("  and clears the head's count", await until(owner, () => document.querySelector(".vf-disc-new").hidden));
    ok("  on the server: the host's seen mark covers both", await until(owner, () => { const l = window.Core.state.discussions.Q1; return window.Core.snapshot().me.discussionSeen.Q1 === l[l.length - 1].ts; }));
    await owner.reload();
    await until(owner, () => !!window.Core.snapshot()?.me);
    ok("  after a reload the head shows no new count", await until(owner, () => document.querySelector(".vf-disc-count").textContent === "2 comments" && document.querySelector(".vf-disc-new").hidden));
    ok("Bo's head still reads 2 new", await until(bo, () => document.querySelector(".vf-disc-new").textContent === "2 new"));

    // ---------- edit and delete one's own only ----------
    await openDisc(bo);
    rows = await shown(bo);
    ok("Bo sees no Edit, Delete or Hide on Ann's comments", rows.length === 2 && rows.every(r => !r.acts.some(a => ["Edit", "Delete", "Hide"].includes(a))), JSON.stringify(rows));
    rows = await shown(ann);
    ok("Ann sees Edit and Delete on her own, and no Hide", rows.length === 2 && rows.every(r => r.acts.join() === "Edit,Delete"), JSON.stringify(rows));
    await cm(ann, ANN1).locator(".vf-lbtn", { hasText: "Edit" }).click();
    await cm(ann, ANN1).locator(".vf-cm-edit textarea").fill(ANN1_EDIT);
    await cm(ann, ANN1).locator(".vf-cm-edit button[type=submit]").click();
    ok("her edit shows to Bo, marked edited", await until(bo, t => [...document.querySelectorAll(".vf-cm")].some(li => li.querySelector(".vf-cm-txt").textContent === t && !li.querySelector(".vf-cm-edited").hidden), ANN1_EDIT));
    const forged = await bo.evaluate(async () => { const c = window.Core.state.discussions.Q1[0]; return window.Core.editComment("Q1", c.id, "Bo's words").then(() => "saved", e => e.error); });
    ok("Bo's edit of Ann's comment is refused", forged === "not-found", forged);

    await cm(bo, ANN1_EDIT).locator(".vf-cm-react").click();
    await bo.click('.vf-reactpop .vf-rp-e[data-e="👍"]');
    ok("Bo's 👍 from the chat's emoji set shows on Ann's comment for her", await until(ann, t => [...document.querySelectorAll(".vf-cm")].some(li => li.textContent.includes(t)
      && [...li.querySelectorAll(".vf-mreact")].some(b => b.textContent === "👍1")), ANN1_EDIT));

    // ---------- the owner hides one ----------
    await openDisc(owner);
    rows = await shown(owner);
    ok("the host sees Hide on every comment", rows.length === 2 && rows.every(r => r.acts.includes("Hide")), JSON.stringify(rows));
    await cm(owner, OFF).locator(".vf-cm-hide").click();
    ok("hiding it takes it out of Bo's Discussion and his page's data", await until(bo, t => document.querySelectorAll(".vf-disc-list > .vf-cm").length === 1 && !JSON.stringify(window.Core.snapshot()).includes(t), OFF));
    ok("  Ann still sees it, marked Hidden", await until(ann, t => [...document.querySelectorAll(".vf-cm")].some(li => li.textContent.includes(t) && !li.querySelector(".vf-cm-hidden").hidden), OFF));
    ok("  and the host sees it marked Hidden with Show", await until(owner, t => [...document.querySelectorAll(".vf-cm")].some(li => li.textContent.includes(t) && !li.querySelector(".vf-cm-hidden").hidden && li.querySelector(".vf-cm-hide").textContent === "Show"), OFF));
    await ann.waitForTimeout(1100);
    await cm(ann, OFF).locator(".vf-lbtn", { hasText: "Delete" }).click();
    await ann.click("dialog.vf-cdlg[open] .vf-btn-danger-solid");
    ok("Ann deletes her own comment after confirming", await until(ann, t => ![...document.querySelectorAll(".vf-cm")].some(li => li.textContent.includes(t)), OFF));
    ok("  and it is gone for the host too", await until(owner, () => document.querySelector(".vf-disc-count").textContent === "1 comment"));

    // ---------- @Claude becomes a request in the host's queue ----------
    await bo.waitForTimeout(1100);
    await post(bo, BO_ASK);
    ok("Bo's @Claude comment reads Sent to Claude, waiting", await until(bo, t => [...document.querySelectorAll(".vf-cm")].some(li => li.textContent.includes(t) && li.querySelector(".vf-cm-became-t").textContent.startsWith("Sent to Claude")), BO_ASK), JSON.stringify(await shown(bo)));
    ok("  and offers Delete but no Edit on it", (await shown(bo)).some(r => r.text === BO_ASK && r.acts.join() === "Delete"), JSON.stringify(await shown(bo)));
    ok("Ann, who sees neither the request nor its answer, reads Sent to Claude with no status", await until(ann, t => [...document.querySelectorAll(".vf-cm")].some(li => li.textContent.includes(t) && li.querySelector(".vf-cm-became-t").textContent === "Sent to Claude"), BO_ASK), JSON.stringify(await shown(ann)));
    const rid = await owner.evaluate(async t => {
      for (let i = 0; i < 50 && !(window.Core.state.requests || []).some(r => r.text === t); i++) await new Promise(r => setTimeout(r, 100));
      return (window.Core.state.requests || []).find(r => r.text === t);
    }, BO_ASK);
    ok("the host's queue holds it as a waiting ask from Bo", !!rid && rid.kind === "ask" && rid.status === "pending" && rid.name === "Bo", JSON.stringify(rid));
    await owner.locator(".vf-cltoggle").click();
    ok("its card in the Claude section links back with from Discussion", await until(owner, t => [...document.querySelectorAll(".vf-threq")].some(li => li.textContent.includes(t) && !li.querySelector(".vf-fromdisc").hidden), BO_ASK));
    await owner.locator(".vf-threq .vf-fromdisc").first().click();
    ok("  which opens the Discussion at the comment", await until(owner, t => !document.querySelector(".vf-disc-body").hidden && [...document.querySelectorAll(".vf-cm")].some(li => li.textContent.includes(t)), BO_ASK));
    await owner.evaluate(id => window.Core.requestAct(id, "run"), rid.id);
    const res = s.apply(A.dir, [{ op: "result", qid: "Q1", request: rid.id, kind: "ask", summary: ANSWER, sources: [], report: "", used: [], why: "" }]).results[0];
    await owner.evaluate(id => window.Core.requestAct(id, "publish"), res.id);
    await until(bo, a => (window.Core.state.research.Q1 || []).some(x => x.summary === a), ANSWER, 10000);
    await openClaude(bo);
    ok("Claude's shared answer shows Bo from Discussion on its card", await until(bo, a => [...document.querySelectorAll(".vf-res")].some(li => li.textContent.includes(a) && !li.querySelector(".vf-fromdisc").hidden), ANSWER));
    ok("  and the comment now reads Sent to Claude · Answered", await until(bo, t => [...document.querySelectorAll(".vf-cm")].some(li => li.textContent.includes(t) && li.querySelector(".vf-cm-became-t").textContent === "Sent to Claude · Answered"), BO_ASK));

    // ---------- @Claude past the waiting cap: posted, with no request, and the reason said ----------
    await bo.evaluate(async () => { for (let i = 0; i < 10; i++) await window.Core.request("Q1", "ask", "filler " + i).catch(() => {}); });
    await bo.waitForTimeout(1100); // past the one request a second the comment's request shares with the fillers
    const FULL = "@Claude one more?";
    ok("an @Claude comment past the waiting cap still posts", await post(bo, FULL));
    ok("  and Bo is told it was not sent to Claude", await until(bo, () => /^Posted, but not sent to Claude/.test(document.querySelector(".vf-toast.vf-on span")?.textContent || "")));
    ok("  with no Sent to Claude line on it", (await shown(bo)).some(r => r.text === FULL && !r.became));

    // ---------- 390 phone ----------
    const fit = await bo.evaluate(() => {
      const r = document.querySelector(".vf-disc").getBoundingClientRect(), hd = document.querySelector(".vf-disc-head").getBoundingClientRect();
      return { left: r.left, right: r.right, w: innerWidth, head: hd.height, page: document.documentElement.scrollWidth,
        rows: [...document.querySelectorAll(".vf-cm")].every(li => li.getBoundingClientRect().right <= innerWidth) };
    });
    ok("390: the Discussion fits the screen with a 44px head and nothing scrolls sideways", fit.left >= 0 && fit.right <= fit.w && fit.head >= 44 && fit.page <= fit.w && fit.rows, JSON.stringify(fit));

    ok("no page broke the server's CSP", (await rec.cspViolations()).length === 0);
    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
