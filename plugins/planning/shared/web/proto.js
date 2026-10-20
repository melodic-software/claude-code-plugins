// The prototype page (Q98), /proto/<qid>: one prototype question's variants, a switcher between them, an Annotate
// toggle, and notes pinned to elements of a variant. Notes go to the server (/api/annotate), which shows them in the
// question's Claude thread and hands them to Claude with the round. Identity, polling and actions come from core.js.
// A variant is untrusted: an html one runs framed from /assets/ in a sandbox with no same origin, and only the pin
// helper inside it (proto-pin.js) talks to this page, by postMessage; every message is checked here before use.
(() => {
  const Core = window.Core;
  const qid = (location.pathname.match(/^\/proto\/(Q[1-9][0-9]{0,5})$/) || [])[1] || "";
  const E = (tag, cls, text) => Core.el(tag, cls, text);
  const btn = (cls, text) => { const b = E("button", cls, text); b.type = "button"; return b; };
  // The server's checks (session.py SELECTOR and _rect), repeated so a bad message from the frame never reaches it.
  const STEP = "[a-z][a-z0-9]{0,15}(?:-[a-z0-9]{1,15}){0,3}(?::nth-of-type\\([1-9][0-9]{0,3}\\))?";
  const SELECTOR = new RegExp(`^${STEP}(?: > ${STEP}){0,31}$`);
  const okRect = r => !!r && typeof r === "object" && ["x", "y", "w", "h"].every(k => typeof r[k] === "number" && Number.isFinite(r[k]) && r[k] >= 0)
    && r.w > 0 && r.h > 0 && r.x + r.w <= 100 && r.y + r.h <= 100;
  const WHOLE = { x: 0, y: 0, w: 100, h: 100 };
  const isHtml = v => /\.html$/.test(v?.asset || "");
  const params = new URLSearchParams(location.hash.slice(1));
  const ui = { variant: params.get("v") || "", annotate: false, draft: null, active: params.get("n") || "", ready: false, pinsKey: "", listKey: "" };
  Core.context = () => ({ view: "prototype" });

  // ---------- the page ----------
  const root = document.getElementById("app");
  const top = E("header", "vp-top");
  const back = E("a", "vf-btn vf-btn-ghost vf-btn-sm vp-back", "Back to the questions");
  const title = E("h1", "vp-title");
  const live = E("span", "vp-live"); live.setAttribute("role", "status");
  top.append(back, title, live);
  const bar = E("div", "vp-bar");
  const tabs = E("div", "vp-tabs"); tabs.setAttribute("role", "tablist"); tabs.setAttribute("aria-label", "Variants");
  const annotateBtn = btn("vf-btn vf-btn-ghost vp-annotate", "Annotate");
  annotateBtn.setAttribute("aria-pressed", "false");
  const chooseBtn = btn("vf-btn vf-btn-primary vp-choose");
  bar.append(tabs, E("span", "vf-spacer"), annotateBtn, chooseBtn);
  const hint = E("p", "vp-hint"); hint.id = "vp-hint";
  const body = E("div", "vp-body");
  const stage = E("section", "vp-stage"); stage.id = "vp-stage"; stage.setAttribute("role", "tabpanel");
  const side = E("aside", "vp-side"); side.setAttribute("aria-label", "Notes");
  const qText = E("p", "vp-qtext");
  const composer = E("form", "vp-composer"); composer.hidden = true; composer.setAttribute("aria-label", "New note");
  const where = E("p", "vp-where");
  const ta = E("textarea", "vf-ta vp-ta"); ta.id = "vp-note"; ta.rows = 3; ta.maxLength = 2000;
  ta.setAttribute("aria-label", "Your note"); ta.placeholder = "What do you think of this part?";
  const err = E("p", "vp-err"); err.setAttribute("role", "alert");
  const cRow = E("div", "vf-crow");
  const cancel = btn("vf-btn vf-btn-ghost vf-btn-sm", "Cancel");
  const save = E("button", "vf-btn vf-btn-primary vf-btn-sm vp-save", "Pin note"); save.type = "submit";
  cRow.append(E("span", "vf-spacer"), cancel, save);
  composer.append(where, ta, err, cRow);
  const wholeBtn = btn("vf-btn vf-btn-ghost vf-btn-sm vp-whole", "Note on the whole variant");
  const notesH = E("h2", "vf-h2 vp-notes-h");
  const notes = E("ol", "vp-notes"); notes.setAttribute("aria-label", "Notes on this variant");
  const empty = E("p", "vf-empty vp-empty");
  side.append(qText, wholeBtn, composer, notesH, notes, empty);
  body.append(stage, side);
  const missing = E("p", "vf-empty vp-missing"); missing.hidden = true;
  root.append(top, bar, hint, body, missing);

  // The stage: an iframe for an html variant, a picture with its own pin layer for an image one.
  let frame = null, img = null, layer = null, shownVariant = "", readySeen = false;
  const send = m => frame?.contentWindow?.postMessage(m, "*"); // the sandboxed frame has no origin to name

  // ---------- state ----------
  const S = () => Core.state;
  const question = () => (S().questions || []).find(q => q.id === qid && q.formatKind === "prototype") || null;
  const variants = q => q?.variants || [];
  const current = q => variants(q).find(v => v.id === ui.variant) || variants(q)[0] || null;
  const notesOn = vid => (S().annotations || []).filter(a => a.qid === qid && a.variant === vid);
  const mine = () => Core.answersFor(qid).find(a => a.cid === Core.me.cid && !a.claude && !a.option);
  const say = text => { live.textContent = ""; requestAnimationFrame(() => { live.textContent = text; }); };
  function readOnly(q) {
    const r = (S().rounds || []).find(x => x.n === q.round);
    if (Core.lockOf(qid)) return "Locked. The choice is decided.";
    if (!r) return "This question's round has not opened yet.";
    if (r.status === "sent" || r.status === "working") return "This round went to Claude, so picks wait for the next one.";
    return "";
  }

  function applyTheme() {
    const t = S().settings?.theme || {}, p = Core.snapshot()?.me?.prefs || {};
    const mode = p.theme || t.mode || "system";
    root.dataset.theme = mode === "system" ? (matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark") : mode;
    root.dataset.accent = p.accent || t.accent || "teal";
  }

  // ---------- variant switcher ----------
  function selectVariant(vid, { focus = false } = {}) {
    if (vid === ui.variant) return;
    closeComposer(); // its spot was on the variant being left
    ui.variant = vid; ui.active = "";
    const h = new URLSearchParams(location.hash.slice(1)); h.set("v", vid); h.delete("n");
    history.replaceState(null, "", location.pathname + "#" + h);
    render();
    if (focus) tabs.querySelector(`[data-v="${CSS.escape(vid)}"]`)?.focus();
  }
  tabs.addEventListener("keydown", e => {
    const list = [...tabs.querySelectorAll("[role=tab]")], i = list.indexOf(document.activeElement);
    if (i < 0) return;
    const to = e.key === "ArrowRight" ? i + 1 : e.key === "ArrowLeft" ? i - 1 : e.key === "Home" ? 0 : e.key === "End" ? list.length - 1 : null;
    if (to == null) return;
    e.preventDefault();
    selectVariant(list[(to + list.length) % list.length].dataset.v, { focus: true });
  });
  function renderTabs(q, v) {
    const key = variants(q).map(x => `${x.id}:${x.label}:${notesOn(x.id).length}`).join("|") + "@" + v.id;
    if (tabs._key === key) return;
    tabs._key = key;
    tabs.replaceChildren(...variants(q).map(x => {
      const b = btn("vf-seg-btn vp-tab");
      const n = notesOn(x.id).length;
      b.append(E("span", null, x.label), ...(n ? [E("span", "vp-tab-n", String(n))] : []));
      b.dataset.v = x.id;
      b.setAttribute("role", "tab");
      b.setAttribute("aria-selected", String(x.id === v.id));
      b.setAttribute("aria-controls", stage.id);
      b.setAttribute("aria-label", `${x.label}${n ? `, ${n} note${n === 1 ? "" : "s"}` : ""}`);
      b.tabIndex = x.id === v.id ? 0 : -1;
      b.onclick = () => selectVariant(x.id);
      return b;
    }));
  }

  // ---------- the stage and its pins ----------
  function mountStage(v) {
    if (shownVariant === v.id) return;
    shownVariant = v.id; ui.ready = false; ui.pinsKey = ""; readySeen = false;
    frame = img = layer = null;
    stage.setAttribute("aria-label", `Variant ${v.label}`);
    if (isHtml(v)) {
      const f = frame = E("iframe", "vp-frame");
      f.setAttribute("sandbox", "allow-scripts"); // plus the asset's own CSP sandbox; never allow-same-origin
      f.setAttribute("referrerpolicy", "no-referrer");
      f.title = `Prototype variant ${v.label}`;
      // The frame's window stays the same object when the variant navigates itself away, so a second load means the
      // frame now shows some other page: drop it, and stop talking to it, before it can pass for the variant.
      let loads = 0;
      f.addEventListener("load", () => { if (++loads > 1 && frame === f) leftPage(v); });
      f.src = `/assets/${v.asset}?pin=1`;
      stage.replaceChildren(f);
    } else {
      const wrap = E("div", "vp-imgwrap");
      img = E("img", "vp-img"); img.alt = `Prototype variant ${v.label}`; img.src = `/assets/${v.asset}`;
      layer = E("div", "vp-layer"); layer.setAttribute("aria-hidden", "true");
      wrap.append(img, layer);
      wrap.addEventListener("click", e => {
        if (!ui.annotate || ui.draft) return; // a new spot waits until the open note is saved or cancelled
        const b = img.getBoundingClientRect();
        if (!b.width || !b.height) return;
        const px = ((e.clientX - b.left) / b.width) * 100, py = ((e.clientY - b.top) / b.height) * 100;
        const x = Math.min(94, Math.max(0, Math.round((px - 3) * 100) / 100)), y = Math.min(94, Math.max(0, Math.round((py - 3) * 100) / 100));
        openComposer({ selector: "img", rect: { x, y, w: 6, h: 6 } }, "this spot on the picture");
      });
      stage.replaceChildren(wrap);
    }
  }
  function leftPage(v) {
    frame = null; ui.ready = false; ui.pinsKey = "";
    const note = E("div", "vp-left");
    note.setAttribute("role", "alert");
    const again = btn("vf-btn vf-btn-ghost vf-btn-sm", "Load it again");
    again.onclick = () => { shownVariant = ""; render(); };
    note.append(E("p", null, "This variant tried to leave its page, so it is not shown."), again);
    stage.replaceChildren(note);
  }
  /** Numbered pins for the shown variant's notes (1 is the oldest), plus the draft's while a note is being written. */
  function pinsFor(v) {
    const list = notesOn(v.id).map((a, i) => ({ n: i + 1, selector: a.selector, rect: a.rect || WHOLE, active: a.id === ui.active }));
    if (ui.draft) list.push({ n: list.length + 1, selector: ui.draft.selector, rect: ui.draft.rect, active: true });
    return list;
  }
  function drawPins(v) {
    const pins = pinsFor(v), key = JSON.stringify([pins, ui.annotate, ui.ready]);
    if (key === ui.pinsKey) return;
    ui.pinsKey = key;
    if (frame) {
      if (!ui.ready) return;
      send({ type: "mode", on: ui.annotate });
      send({ type: "pins", pins: pins.map(p => ({ n: p.n, selector: p.selector, rect: p.rect, active: p.active })) });
    } else if (layer) {
      layer.replaceChildren(...pins.map(p => {
        const b = E("span", "vp-pin" + (p.active ? " vp-pin-on" : ""), String(p.n));
        b.style.left = `${p.rect.x + p.rect.w / 2}%`; b.style.top = `${p.rect.y + p.rect.h / 2}%`;
        return b;
      }));
    }
  }
  window.addEventListener("message", e => {
    if (!frame || e.source !== frame.contentWindow) return; // only the shown variant's frame, never anything else
    const m = e.data;
    if (!m || typeof m !== "object") return;
    if (m.type === "ready") { if (readySeen) return; readySeen = ui.ready = true; ui.pinsKey = ""; render(); }
    else if (m.type === "escape") setAnnotate(false);
    else if (m.type === "pinned" && ui.annotate && !ui.draft) { // a new pick waits until the open note is saved or cancelled
      if (typeof m.selector !== "string" || m.selector.length > 1000 || !SELECTOR.test(m.selector) || !okRect(m.rect)) return;
      const label = typeof m.label === "string" ? m.label.replace(/\s+/g, " ").trim().slice(0, 60) : "";
      const r = m.rect;
      openComposer({ selector: m.selector, rect: { x: r.x, y: r.y, w: r.w, h: r.h } }, label ? `“${label}”` : "the part you picked");
    }
  });

  // ---------- Annotate and the note composer ----------
  function setAnnotate(on) {
    ui.annotate = !!on;
    if (!on) closeComposer();
    render();
    say(on ? "Annotate is on. Click a part of the prototype to pin a note to it." : "Annotate is off.");
  }
  annotateBtn.onclick = () => setAnnotate(!ui.annotate);
  function openComposer(anchor, what) {
    ui.draft = anchor;
    where.textContent = `Note on ${what}`;
    err.textContent = "";
    composer.hidden = false;
    render();
    ta.focus();
  }
  function closeComposer() {
    ui.draft = null; composer.hidden = true; err.textContent = ""; ta.value = "";
  }
  wholeBtn.onclick = () => {
    const v = current(question());
    if (v) openComposer({ selector: isHtml(v) ? "html" : "img", rect: { ...WHOLE } }, "the whole variant");
  };
  cancel.onclick = () => { closeComposer(); render(); annotateBtn.focus(); };
  composer.addEventListener("submit", e => {
    e.preventDefault();
    const v = current(question()), text = ta.value.trim();
    if (!v || !ui.draft) return;
    if (!text) { err.textContent = "Write the note first."; ta.focus(); return; }
    save.disabled = true;
    Core.annotate(qid, v.id, ui.draft, text).then(r => {
      closeComposer();
      ui.active = r.id || "";
      render();
      say("Note pinned. It is in the question's Claude thread, and Claude reads it with the round.");
      annotateBtn.focus();
    }).catch(x => { err.textContent = Core.errorText(x); }).finally(() => { save.disabled = false; });
  });
  document.addEventListener("keydown", e => {
    if (e.key !== "Escape") return;
    if (!composer.hidden) { closeComposer(); render(); annotateBtn.focus(); } else if (ui.annotate) setAnnotate(false);
  });

  // ---------- notes ----------
  function renderNotes(v) {
    const list = notesOn(v.id);
    const key = JSON.stringify([v.id, ui.active, list.map(a => [a.id, a.text, a.name, a.cid, Core.since(a.ts)])]);
    notesH.textContent = `Notes on ${v.label} (${list.length})`;
    empty.textContent = "No notes on this variant yet. Turn on Annotate, then click the part you want to comment on.";
    empty.hidden = list.length > 0;
    if (notes._key === key) return;
    notes._key = key;
    notes.replaceChildren(...list.map((a, i) => {
      const li = E("li", "vp-note" + (a.id === ui.active ? " vp-note-on" : ""));
      const b = btn("vp-note-btn");
      const head = E("span", "vp-note-head");
      head.append(E("span", "vp-pin vp-pin-static", String(i + 1)), Core.avatar(a.cid, a.name, 22),
        E("span", "vp-note-who", a.cid === Core.me.cid ? "You" : a.name), E("span", "vf-card-time", Core.since(a.ts)));
      b.append(head, E("span", "vp-note-text", a.text));
      b.setAttribute("aria-label", `Note ${i + 1} from ${a.cid === Core.me.cid ? "you" : a.name}: ${a.text}. Show it on the prototype.`);
      b.onclick = () => { ui.active = a.id; render(); send({ type: "focus", n: i + 1 }); };
      li.append(b);
      return li;
    }));
  }

  // ---------- render ----------
  function render() {
    applyTheme();
    const q = question();
    const known = (S().questions || []).length > 0;
    body.hidden = bar.hidden = hint.hidden = !q;
    missing.hidden = !!q || !known;
    back.href = Core.pageLink("/");
    if (!q) {
      title.textContent = "Prototype";
      missing.textContent = "This prototype is not in the session, or its round has not opened yet.";
      return;
    }
    const v = current(q);
    if (!v) return;
    if (ui.variant !== v.id) ui.variant = v.id;
    document.title = `${q.id}: ${q.short || q.text}`;
    title.textContent = `${q.id}: ${q.short || q.text}`;
    qText.textContent = q.text;
    renderTabs(q, v);
    mountStage(v);
    annotateBtn.setAttribute("aria-pressed", String(ui.annotate));
    annotateBtn.textContent = ui.annotate ? "Annotate: on" : "Annotate";
    root.dataset.annotate = String(ui.annotate);
    hint.textContent = ui.annotate
      ? `${matchMedia("(pointer: coarse)").matches ? "Tap" : "Click"} the part of ${v.label} your note is about. Esc turns Annotate off.`
      : "Try each variant. Turn on Annotate to pin a note to any part of it.";
    wholeBtn.hidden = !ui.annotate || !!ui.draft;
    const ro = readOnly(q), rec = mine(), chosen = rec?.pick === v.id;
    chooseBtn.textContent = chosen ? `You chose ${v.label}` : `Choose ${v.label}`;
    chooseBtn.setAttribute("aria-pressed", String(chosen));
    chooseBtn.disabled = !!ro;
    chooseBtn.title = ro;
    // A pick replaces the person's card, so it carries their comment along, as the main page's pick does.
    chooseBtn.onclick = () => Core.pick(qid, chosen ? "" : v.id, rec?.text || "").then(() => say(chosen ? "Your choice is cleared." : `You chose ${v.label}.`))
      .catch(x => say(Core.errorText(x)));
    renderNotes(v);
    drawPins(v);
  }

  if (!qid) { missing.hidden = false; missing.textContent = "No prototype is named in this address."; return; }
  Core.setFocus(qid);
  Core.subscribe(render);
  matchMedia("(prefers-color-scheme: light)").addEventListener("change", applyTheme);
})();
