// Page side of the input harness (web/harness.html; ui_inputs.js serves both through the browser). Harness.open(name)
// opens one input surface the way a person would and resolves to the selectors of its field and its send control.
"use strict";
(() => {
  const $ = s => document.querySelector(s);
  const wait = ms => new Promise(r => setTimeout(r, ms));
  const phone = () => matchMedia("(max-width: 720px)").matches;
  const visible = el => !!el && !el.closest("[hidden]") && el.getClientRects().length > 0;
  async function until(fn, ms = 4000) { for (const end = Date.now() + ms; Date.now() < end; await wait(50)) { const v = fn(); if (v) return v; } return null; }
  const click = async (sel, text) => {
    const el = await until(() => [...document.querySelectorAll(sel)].find(e => visible(e) && (!text || e.textContent.includes(text))));
    if (!el) throw new Error(`no ${sel}${text ? ` "${text}"` : ""} to press`);
    el.scrollIntoView({ block: "nearest" }); el.click(); await wait(150);
  };
  async function closeAll() {
    for (let i = 0; i < 3; i++) document.activeElement?.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    document.activeElement?.blur?.(); await wait(150);
  }
  async function go(text) {
    if (phone()) await click(".vf-tab", "Questions");
    await click(".vf-q", text);
    if (phone()) await click(".vf-tab", "Answer");
    if (!(await until(() => $(".vf-qtext")?.textContent === text))) throw new Error(`question "${text}" did not open`);
  }
  const more = async label => { await click(".vf-tab", "More"); await click(".vf-msitem", label); };
  const answerSend = () => (phone() ? ".vf-composer-sheet .vf-sheetsave" : ".vf-composer .vf-sendbtn");
  const SURFACES = {
    async answer(Q) { await go(Q.answer); return { field: "#vf-answer", send: answerSend() }; },
    async comment(Q) { await go(Q.choice); await click(".vf-opts .vf-opt:not(.vf-opt-other) .vf-optchoose"); await until(() => !$("#vf-answer").disabled); return { field: "#vf-answer", send: answerSend() }; },
    async edit(Q) { await go(Q.answered); return { field: "#vf-answer", send: answerSend() }; },
    async chat() { await click(".vf-fab"); return { field: ".vf-minput", send: ".vf-mform button[type=submit]" }; },
    async suggest(Q) { await go(Q.locked); await click(".vf-subhead .vf-btn", "Suggest a change"); return { field: ".vf-sugform .vf-ta", send: ".vf-sugform button[type=submit]" }; },
    async propose() { if (phone()) await click(".vf-tab", "Questions"); await click(".vf-propose"); return { field: "#vf-prop-ta", send: ".vf-proposepop button[type=submit]" }; },
    async request() { if (phone()) await more("Ask Claude"); else await click(".vf-asktop"); return { field: "#vf-ap-ta", send: ".vf-apform button[type=submit]" }; },
    async rename() {
      if (phone()) await more("Settings"); else await click(".vf-person-me");
      if (!phone()) await wait(150);
      if (!visible($('[data-k="rename"]'))) await click(".vf-person-me"); // a hover card pins on click
      await click('[data-k="rename"]');
      return { field: '[data-k="rn"]', send: '[data-k="rs"]' };
    },
    async other(Q) { await go(Q.choice); await click(".vf-opt-other .vf-optchoose"); return { field: "#vf-other", send: ".vf-other-save" }; },
  };
  window.Harness = {
    surfaces: Object.keys(SURFACES),
    async open(name, questions) {
      await until(() => $(".vf-top") && window.Core?.snapshot()?.me, 8000);
      await closeAll();
      const out = await SURFACES[name](questions);
      const f = await until(() => visible($(out.field)) && $(out.field));
      if (!f) throw new Error(`${name}: its field did not show`);
      f.focus(); await wait(200);
      return out;
    },
  };
})();
