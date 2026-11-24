#!/usr/bin/env node
"use strict";
const { until, joinAs } = require("./browser_harness");
const { run, keyboard, fieldSeen, settle, docScrolls, shot, KB, PHONE, TOL } = require("./ui_layout");

run("ui_layout_keyboard", async (s, rec, A) => {
  const { ok } = s;
  const SWEEP = [[390, 844, [300, 350, 400, 450, 500, 550, 600], 450], [375, 667, [260, 310, 360, 410, 430], 360]];
  for (const [w, h, kbs, staleKb] of SWEEP) {
    const sp = await rec.open(A.localUrl, { context: { ...PHONE, viewport: { width: w, height: h } } });
    await joinAs(sp, `Kb ${w}`);
    await sp.evaluate(() => document.querySelector(".vf-asktop").click());
    await until(sp, () => !!document.querySelector(".vf-drawer:not([hidden]) .vf-apform"));
    await settle(sp, `Ask Claude at ${w}x${h}`);
    const bad = [];
    const parts = () => sp.evaluate(() => {
      const shown = [...document.querySelector(".vf-apform").children].filter(c => c.getClientRects().length);
      const tops = shown.filter(c => getComputedStyle(c).position !== "sticky").map(c => c.getBoundingClientRect().top);
      return { names: shown.map(c => c.className), inOrder: tops.every((t, i) => !i || t >= tops[i - 1] - 0.5) };
    });
    const closed = await parts();
    for (const [kb, stale] of [...kbs.map(k => [k, false]), [staleKb, true]]) {
      await sp.evaluate(() => { document.activeElement?.blur(); document.querySelector(".vf-apscroll").scrollTop = 0; });
      await sp.locator("#vf-ap-ta").tap();
      await keyboard(sp, true, { kb, stale });
      const seen = await fieldSeen(sp, ".vf-apform .vf-asklabel", "#vf-ap-ta", ".vf-apform .vf-btn-primary");
      const st = await sp.evaluate(() => document.querySelector(".vf-apscroll").scrollTop);
      if (st > 0.5) seen.push(`the sheet scrolled ${st.toFixed(0)} px from its top`);
      seen.push(...(await docScrolls(sp)));
      const up = await parts();
      if (!up.inOrder) seen.push(`the form's parts are out of DOM order on screen: ${up.names.join(", ")}`);
      if (seen.length) bad.push(`keyboard ${kb}${stale ? " (offsetTop read 0)" : ""}: ${seen.join(", ")}`);
      if (kb === kbs[kbs.length - 1] && !stale) await shot(sp, `ask-${w}x${h}-kb${kb}`);
      await keyboard(sp, false);
      const back = await parts();
      if (back.names.join() !== closed.names.join() || !back.inOrder) bad.push(`keyboard ${kb}${stale ? " (offsetTop read 0)" : ""}, closed again: the form shows ${back.names.join(", ")}, not ${closed.names.join(", ")}`);
    }
    ok(`${w}x${h}, Ask Claude, keyboard ${kbs[0]} to ${kbs[kbs.length - 1]} px: the label, the field's first 3 lines and Send request are seen above the keyboard, the sheet at its top, the form in DOM order, every part back once it closes, the document never scrolled`, bad.length === 0, bad.join("; "));
    await sp.context().close();
  }

  const clippedSideways = (page, sel) => page.evaluate(([sel, tol]) => {
    const top = document.querySelector(sel);
    if (!top) return [`no ${sel}`];
    const T = top.getBoundingClientRect(), out = [];
    for (const el of [top, ...top.querySelectorAll("*")]) {
      const r = el.getBoundingClientRect();
      if (r.width <= 1 || r.height <= 1) continue;
      if (r.left < Math.max(0, T.left) - tol || r.right > Math.min(innerWidth, T.right) + tol) out.push(`${el.tagName.toLowerCase()}.${[...el.classList].join(".")} ${r.left.toFixed(0)} to ${r.right.toFixed(0)}, form ${T.left.toFixed(0)} to ${T.right.toFixed(0)}, viewport ${innerWidth}`);
    }
    if (top.scrollWidth > top.clientWidth + tol) out.push(`${sel} content ${top.scrollWidth} in ${top.clientWidth}`);
    return out;
  }, [sel, TOL]);
  const PSWEEP = [[320, 568, [260, 300, 330]], [375, 667, [260, 310, 360, 410, 430]], [390, 844, [260, 300, 350, 400, 430]], [430, 932, [260, 300, 350, 400, 430]]];
  for (const [w, h, kbs] of PSWEEP) {
    const pp = await rec.open(A.localUrl, { context: { ...PHONE, viewport: { width: w, height: h } } });
    await joinAs(pp, `Prop ${w}`);
    await pp.locator(".vf-tab", { hasText: "Questions" }).tap();
    await pp.locator(".vf-propose").tap();
    const opened = await until(pp, () => !!document.querySelector(".vf-proposepop:not([hidden])"), null, 3000);
    await settle(pp, `the Propose form at ${w}x${h}`);
    const bad = opened ? [] : ["the form did not open"];
    for (const [kb, stale] of opened ? [...kbs.map(k => [k, false]), [kbs[kbs.length - 1], true]] : []) {
      await pp.evaluate(() => document.activeElement?.blur());
      if (!(await pp.locator("#vf-prop-ta").tap({ timeout: 5000 }).then(() => true, () => false))) { bad.push(`keyboard ${kb}: the field could not be tapped`); break; }
      await keyboard(pp, true, { kb, stale, scale: 1 });
      const seen = await fieldSeen(pp, ".vf-proposepop .vf-asklabel", "#vf-prop-ta", ".vf-proposepop button[type=submit]");
      seen.push(...(await clippedSideways(pp, ".vf-proposepop")), ...(await docScrolls(pp)));
      if (seen.length) bad.push(`keyboard ${kb}${stale ? " (offsetTop read 0)" : ""}: ${[...new Set(seen)].join(", ")}`);
      if (kb === kbs[kbs.length - 1] && !stale) await shot(pp, `propose-${w}x${h}-kb${kb}`);
      await keyboard(pp, false);
    }
    ok(`${w}x${h}, the Propose form from the question list, keyboard ${kbs[0]} to ${kbs[kbs.length - 1]} px: the label, the field's first 3 lines and Propose are seen above the keyboard, nothing clipped or scrolling sideways, the document never scrolled`, bad.length === 0, bad.join("; "));
    await pp.keyboard.press("Escape");
    await pp.locator(".vf-tab", { hasText: "More" }).tap();
    await pp.locator(".vf-msitem", { hasText: "Report a problem" }).tap();
    const repOpen = await until(pp, () => !!document.querySelector(".vf-reportpop:not([hidden])"), null, 3000);
    await settle(pp, `Report a problem at ${w}x${h}`);
    const rbad = repOpen ? [] : ["the form did not open"];
    for (const kb of repOpen ? kbs : []) {
      await pp.evaluate(() => document.activeElement?.blur());
      if (!(await pp.locator("#vf-rep-ta").tap({ timeout: 5000 }).then(() => true, () => false))) { rbad.push(`keyboard ${kb}: the field could not be tapped`); break; }
      await keyboard(pp, true, { kb, scale: 1 });
      const seen = await fieldSeen(pp, ".vf-reportpop .vf-asklabel", "#vf-rep-ta", ".vf-reportpop button[type=submit]");
      seen.push(...(await clippedSideways(pp, ".vf-reportpop")), ...(await docScrolls(pp)));
      if (seen.length) rbad.push(`keyboard ${kb}: ${[...new Set(seen)].join(", ")}`);
      await keyboard(pp, false);
    }
    ok(`${w}x${h}, Report a problem from More, keyboard ${kbs[0]} to ${kbs[kbs.length - 1]} px: the label, the field's first 3 lines and Send report are seen above the keyboard, nothing clipped or scrolling sideways, the document never scrolled`, rbad.length === 0, rbad.join("; "));
    await pp.context().close();
  }
  const ria = await rec.open(A.localUrl, { context: PHONE });
  await joinAs(ria, "Ria");
  for (const t of ["Which providers charge the least?", "Compare saved-card adoption", "What do returning customers pick?"]) await ria.evaluate(x => window.Core.request("Q1", "ask", x), t);
  await ria.evaluate(() => document.querySelector(".vf-asktop").click());
  await until(ria, () => document.querySelectorAll(".vf-drawer:not([hidden]) .vf-apreqs > li").length === 3);
  await settle(ria, "Ask Claude with three requests");
  await ria.locator("#vf-ap-ta").tap();
  await keyboard(ria, true);
  const reqs = await ria.evaluate(() => {
    const sc = document.querySelector(".vf-apscroll"), head = [...sc.querySelectorAll(".vf-pop-sub")].find(h => h.textContent === "Your requests");
    sc.scrollTop += head.getBoundingClientRect().top - sc.getBoundingClientRect().top;
    const vv = visualViewport, S = sc.getBoundingClientRect(), h = head.getBoundingClientRect(), li = sc.querySelector(".vf-apreqs > li").getBoundingClientRect();
    return { scrolled: sc.scrollTop > 0, shown: h.top >= S.top - 0.5 && li.bottom <= Math.min(S.bottom, vv.offsetTop + vv.height) + 0.5, sideways: sc.scrollWidth > sc.clientWidth + 1 || sc.scrollLeft !== 0 };
  });
  ok("390x844, keyboard up: the Ask Claude sheet scrolls down to \"Your requests\" and its first request, never sideways", reqs.scrolled && reqs.shown && !reqs.sideways, JSON.stringify(reqs));
  await ria.context().close();

  const ivy = await rec.open(A.localUrl, { context: PHONE });
  await joinAs(ivy, "Ivy");
  await ivy.evaluate(() => window.Core.request("Q1", "ask", "Ivy asks the host to run this one"));
  const io = await rec.open(A.ownerUrl, { context: PHONE });
  await until(io, () => window.Core.snapshot()?.me?.role === "owner" && (window.Core.state.requests || []).some(r => r.text.startsWith("Ivy asks")), null, 10000);
  await io.locator(".vf-tab", { hasText: "More" }).tap();
  await io.locator(".vf-msitem", { hasText: "Inbox" }).tap();
  await until(io, () => !document.querySelector(".vf-inboxpage").hidden);
  await io.locator(".vf-ixtabs [data-k=needs]").tap();
  const IVY = ".vf-ibneeds .vf-revlist > li:has(.vf-qref)", ibad = [];
  const ivyRow = io.locator(".vf-ibneeds .vf-revlist > li", { hasText: "Ivy asks" });
  await ivyRow.locator("button", { hasText: /^Edit$/ }).tap();
  await settle(io, "the Inbox request Edit");
  for (const kb of [260, KB, 430]) {
    await io.evaluate(() => document.activeElement?.blur());
    if (!(await ivyRow.locator("textarea").tap({ timeout: 5000 }).then(() => true, () => false))) { ibad.push(`keyboard ${kb}: the field could not be tapped`); break; }
    await keyboard(io, true, { kb });
    const seen = await fieldSeen(io, `${IVY} .vf-qref`, `${IVY} textarea`, `${IVY} .vf-acts button:not([hidden])`);
    seen.push(...(await docScrolls(io)));
    if (seen.length) ibad.push(`keyboard ${kb}: ${[...new Set(seen)].join(", ")}`);
    await keyboard(io, false);
  }
  ok("390x844, the Inbox page's request Edit, keyboard 260 to 430 px: the row's question, the field's first 3 lines and Save are seen above the keyboard, the document never scrolled", ibad.length === 0, ibad.join("; "));
  await io.context().close(); await ivy.context().close();

  const zp = await rec.open(A.localUrl, { context: PHONE });
  await joinAs(zp, "Zoe");
  await zp.evaluate(() => document.querySelector(".vf-fab").click());
  await until(zp, () => !document.querySelector(".vf-chat").hidden); await settle(zp, "the chat, pinch-zoomed");
  await zp.locator(".vf-minput").tap();
  const kbNow = () => zp.evaluate(() => ({ kb: parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--kb")), flagged: "kb" in document.documentElement.dataset }));
  const zoomed = [];
  for (const scale of [1.5, 2, 3]) {
    await keyboard(zp, true, { scale });
    const up = await kbNow();
    if (!up.flagged || Math.abs(up.kb - KB) > 1) zoomed.push(`zoom ${scale}, keyboard ${KB}: --kb ${up.kb}, data-kb ${up.flagged ? "set" : "unset"}`);
    await keyboard(zp, false);
    await keyboard(zp, true, { scale, kb: 0 });
    const none = await kbNow();
    if (none.flagged || none.kb !== 0) zoomed.push(`zoom ${scale}, no keyboard: --kb ${none.kb}, data-kb ${none.flagged ? "set" : "unset"}`);
    await keyboard(zp, false);
  }
  ok(`390x844 pinch-zoomed to 1.5, 2 and 3: a ${KB} px keyboard reads as ${KB} px, the zoom alone as none`, zoomed.length === 0, zoomed.join("; "));
  await zp.context().close();
}).then(code => process.exit(code), e => { console.error(e); process.exit(1); });
