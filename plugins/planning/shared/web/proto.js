// The prototype page (Q98), /proto/<qid>: one prototype question's variants, a switcher between them, an Annotate
// toggle, and notes pinned to elements of a variant. Notes go to the server (/api/annotate), which shows them in the
// question's Claude thread and hands them to Claude with the round. A variant that revises one on an earlier prototype
// question (its `previous`) lists every version, and shows any of them side by side with it.
// Identity, polling and actions come from core.js.
// A variant is untrusted: an html one runs framed from /assets/ in a sandbox with no same origin, and only the pin
// helper inside it (proto-pin.js) talks to this page, by postMessage; every message is checked here before use.
// A variant shows its views (Core.viewsOf): an html snapshot, and one to four screenshots shown one under another, each
// with its own pins; a note on screenshot k (k > 1) is pinned at "img:nth-of-type(k)", on the first at "img".
// A live view is another origin's running server: never framed here, only linked to open in a new tab with no opener
// and no referrer, and only once the owner approved it and it runs (the server sends a guest its url only then). Notes
// on a live-only variant are on the whole variant.
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
  const views = v => Core.viewsOf(v), hasView = v => !!(views(v).snapshot || views(v).shots.length || views(v).live);
  const liveOnly = v => !views(v).snapshot && !views(v).shots.length && !!views(v).live;
  const params = new URLSearchParams(location.hash.slice(1));
  const ui = { variant: params.get("v") || "", view: "", with: params.get("with") || "", annotate: false, draft: null, active: params.get("n") || "", ready: false, pinsKey: "", listKey: "", liveErr: "" };
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
  // Where to look, above the tabs: the question's lookAt, then the shown variant's own line when it has one.
  const look = E("p", "vp-look"), lookQ = E("span", "vp-look-q"), lookV = E("span", "vp-look-v");
  look.append(lookQ, lookV);
  // A variant with both an html snapshot and screenshots shows one of the two at a time.
  const viewSeg = E("div", "vp-viewseg"); viewSeg.setAttribute("role", "group"); viewSeg.setAttribute("aria-label", "Views of this variant");
  const snapBtn = btn("vf-seg-btn vp-viewbtn", "HTML snapshot"), shotsBtn = btn("vf-seg-btn vp-viewbtn", "Screenshots");
  snapBtn.dataset.view = "snapshot"; shotsBtn.dataset.view = "shots";
  viewSeg.append(snapBtn, shotsBtn);
  // The shown variant's live view: Open live prototype while it runs, else what it waits for; the owner's Approve and Stop.
  const liveBox = E("div", "vp-livebox"); liveBox.setAttribute("role", "group"); liveBox.setAttribute("aria-label", "Live prototype"); liveBox.hidden = true;
  bar.append(look, liveBox, tabs, viewSeg, E("span", "vf-spacer"), annotateBtn, chooseBtn);
  const hint = E("p", "vp-hint"); hint.id = "vp-hint";
  const body = E("div", "vp-body");
  const stage = E("section", "vp-stage"); stage.id = "vp-stage"; stage.setAttribute("role", "tabpanel");
  // Side by side: an earlier or later version of the shown variant (cmpPane) beside it (mainPane, where notes pin).
  const capText = () => E("span", "vp-pane-cap-t");
  const cmpPane = E("figure", "vp-pane vp-pane-cmp"), cmpCap = E("figcaption", "vp-pane-cap"), cmpView = E("div", "vp-view");
  const cmpClose = btn("vf-btn vf-btn-ghost vf-btn-sm vp-cmp-close", "Close side by side");
  cmpCap.append(capText(), cmpClose); cmpPane.append(cmpCap, cmpView); cmpPane.hidden = true;
  const mainPane = E("div", "vp-pane vp-pane-main"), mainCap = E("p", "vp-pane-cap"), mainView = E("div", "vp-view");
  mainCap.append(capText()); mainCap.hidden = true; mainPane.append(mainCap, mainView);
  stage.append(cmpPane, mainPane);
  const side = E("aside", "vp-side"); side.setAttribute("aria-label", "Notes");
  const qText = E("p", "vp-qtext");
  const offNote = E("p", "vp-offnote"); offNote.hidden = true; // the owner's: which views guests do not get (prototypeTiers)
  const versNav = E("nav", "vp-versions"), versH = E("h2", "vf-h2 vp-versions-h"), versList = E("ol", "vp-vers");
  versNav.append(versH, versList); versNav.hidden = true;
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
  side.append(qText, offNote, versNav, wholeBtn, composer, notesH, notes, empty);
  body.append(stage, side);
  const missing = E("p", "vf-empty vp-missing"); missing.hidden = true;
  root.append(top, bar, hint, body, missing);

  // The stage: an iframe for an html view, each picture with its own pin layer, a notice for a variant whose views the
  // session switched off (its state then holds none).
  let frame = null, layers = [], shownVariant = "", readySeen = false;
  const OFF_TEXT = "This view is off in this session. You can still choose this variant.";
  const OFF_NAME = { screenshot: "screenshots are off", snapshot: "HTML snapshots are off", live: "live prototypes are off" };
  const LIVE_ONLY_TEXT = "This variant is a live prototype. It opens in its own tab, from Open live prototype above.";
  const send = m => frame?.contentWindow?.postMessage(m, "*"); // the sandboxed frame has no origin to name

  // ---------- state ----------
  const S = () => Core.state;
  const question = () => (S().questions || []).find(q => q.id === qid && q.formatKind === "prototype") || null;
  const variants = q => q?.variants || [];
  /** The view of `v` on the stage: its snapshot unless the person picked its screenshots, or it has none. */
  const shownView = v => (views(v).snapshot && !(ui.view === "shots" && views(v).shots.length) ? "snapshot" : "shots");
  /** The screenshot (0-based) a note is pinned on, -1 for the snapshot, or null when this viewer holds no such view, so
   *  a note on a view switched off is drawn nowhere: "img" is the first screenshot, "img:nth-of-type(k)" the k-th; any
   *  other path is on the snapshot, except on a one-picture variant written as `asset`, where an earlier build's
   *  free-form note sits on the picture. A variant written with `shots` is this build's, whose picture notes are
   *  always img paths. */
  const shotOf = (v, selector) => {
    const { shots, snapshot } = views(v), k = selector === "img" ? 1 : +((selector.match(/^img:nth-of-type\(([1-9][0-9]*)\)$/) || [])[1] || 0);
    if (k) return k <= shots.length ? k - 1 : null;
    return snapshot ? -1 : v.asset && shots.length ? 0 : null;
  };
  const shotSelector = k => (k ? `img:nth-of-type(${k + 1})` : "img");
  const current = q => variants(q).find(v => v.id === ui.variant) || variants(q)[0] || null;
  const notesOn = vid => (S().annotations || []).filter(a => a.qid === qid && a.variant === vid);
  const mine = () => Core.answersFor(qid).find(a => a.cid === Core.me.cid && !a.claude && !a.option);
  const say = text => { live.textContent = ""; requestAnimationFrame(() => { live.textContent = text; }); };
  function readOnly(q) {
    const r = (S().rounds || []).find(x => x.n === q.round);
    if (S().youRemoved) return "The host removed you from this session.";
    if (S().ended && !Core.me.isOwner) return "This session has ended.";
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
    root.dataset.palette = p.palette || t.palette || "default";
  }

  // ---------- variant switcher ----------
  function selectVariant(vid, { focus = false } = {}) {
    if (vid === ui.variant) return;
    closeComposer(); // its spot was on the variant being left
    ui.variant = vid; ui.view = ""; ui.active = ""; ui.with = ""; // another variant has its own views and versions
    const h = new URLSearchParams(location.hash.slice(1)); h.set("v", vid); h.delete("n"); h.delete("with");
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
  for (const b of [snapBtn, shotsBtn]) b.onclick = () => { if (shownView(current(question())) !== b.dataset.view) { ui.view = b.dataset.view; closeComposer(); render(); } };
  function mountStage(v) {
    const { shots, snapshot } = views(v), kind = shownView(v);
    const key = `${v.id}|${kind}|${snapshot}|${shots.join(",")}|${liveOnly(v)}`; // a view switched off or back on mounts afresh
    if (shownVariant === key) return;
    shownVariant = key; ui.ready = false; ui.pinsKey = ""; readySeen = false;
    frame = null; layers = [];
    stage.setAttribute("aria-label", `Variant ${v.label}`);
    if (!hasView(v)) {
      mainView.replaceChildren(E("p", "vp-left vp-off", OFF_TEXT));
    } else if (liveOnly(v)) {
      mainView.replaceChildren(E("p", "vp-left vp-live-only", LIVE_ONLY_TEXT));
    } else if (kind === "snapshot") {
      const f = frame = E("iframe", "vp-frame");
      f.setAttribute("sandbox", "allow-scripts"); // plus the asset's own CSP sandbox; never allow-same-origin
      f.setAttribute("referrerpolicy", "no-referrer");
      f.title = `Prototype variant ${v.label}`;
      // The frame's window stays the same object when the variant navigates itself away, so a second load means the
      // frame now shows some other page: drop it, and stop talking to it, before it can pass for the variant.
      let loads = 0;
      f.addEventListener("load", () => { if (++loads > 1 && frame === f) leftPage(v); });
      f.src = `/assets/${snapshot}?pin=1`;
      mainView.replaceChildren(f);
    } else {
      // One picture shows as it always has; two or more stack, each captioned.
      mainView.replaceChildren(...shots.map((asset, k) => {
        const wrap = E("div", "vp-imgwrap");
        const img = E("img", "vp-img"); img.src = `/assets/${asset}`;
        img.alt = shots.length > 1 ? `Prototype variant ${v.label}, screenshot ${k + 1} of ${shots.length}` : `Prototype variant ${v.label}`;
        const layer = E("div", "vp-layer"); layer.setAttribute("aria-hidden", "true");
        wrap.append(img, layer);
        layers.push(layer);
        wrap.addEventListener("click", e => {
          if (!ui.annotate || ui.draft) return; // a new spot waits until the open note is saved or cancelled
          const b = img.getBoundingClientRect();
          if (!b.width || !b.height) return;
          const px = ((e.clientX - b.left) / b.width) * 100, py = ((e.clientY - b.top) / b.height) * 100;
          const x = Math.min(94, Math.max(0, Math.round((px - 3) * 100) / 100)), y = Math.min(94, Math.max(0, Math.round((py - 3) * 100) / 100));
          openComposer({ selector: shotSelector(k), rect: { x, y, w: 6, h: 6 } }, shots.length > 1 ? `this spot on screenshot ${k + 1}` : "this spot on the picture");
        });
        if (shots.length < 2) return wrap;
        const fig = E("figure", "vp-shot"), cap = E("figcaption", "vp-shot-cap", `Screenshot ${k + 1} of ${shots.length}`);
        fig.append(cap, wrap);
        return fig;
      }));
    }
  }
  function leftPage(v) {
    frame = null; ui.ready = false; ui.pinsKey = "";
    const note = E("div", "vp-left");
    note.setAttribute("role", "alert");
    const again = btn("vf-btn vf-btn-ghost vf-btn-sm", "Load it again");
    again.onclick = () => { shownVariant = ""; render(); };
    note.append(E("p", null, "This variant tried to leave its page, so it is not shown."), again);
    mainView.replaceChildren(note);
  }

  // ---------- versions ----------
  const vname = x => `v${x.n} · ${x.qid} · ${x.label}`;
  /** A link to another question's prototype page opens a new tab, as the question's own links do; one to this page
   *  only changes the fragment. */
  const versionLink = (a, to, params) => {
    a.href = Core.pageLink(`/proto/${to}`, params);
    if (to !== qid) { a.target = "_blank"; a.rel = "noopener noreferrer"; }
    return a;
  };
  /** The shown variant's versions, when it has more than one: each links to its own page, the shown one and the
   *  current one marked, and Side by side shows the newer of the two in the main pane with the older beside it. */
  function renderVersions(v, line, me) {
    versNav.hidden = !me;
    if (!me) return;
    versH.textContent = `Version ${me.n} of ${line.length}`;
    versNav.setAttribute("aria-label", `Versions of ${v.label}`);
    const key = JSON.stringify([line, me.n]);
    if (versList._key === key) return;
    versList._key = key;
    versList.replaceChildren(...line.map(x => {
      const li = E("li", "vp-ver-row"), a = versionLink(E("a", "vp-ver", vname(x)), x.qid, { v: x.variant });
      li.append(a);
      if (x === me) a.setAttribute("aria-current", "page");
      if (x.current) li.append(E("span", "vp-ver-cur", "Current"));
      if (x !== me) {
        const [newer, older] = x.n > me.n ? [x, me] : [me, x], c = E("a", "vf-btn vf-btn-ghost vf-btn-sm vp-ver-cmp", "Side by side");
        versionLink(c, newer.qid, { v: newer.variant, with: `${older.qid}.${older.variant}` });
        c.setAttribute("aria-label", `Show version ${x.n} beside version ${me.n}`);
        li.append(c);
      }
      return li;
    }));
  }
  /** The version named by `with` beside the shown one: framed with no pin helper, so it takes no notes and nothing
   *  it posts is read; an html one runs in the same sandbox as the variant, and one that leaves its page is dropped. */
  let cmpShown = "";
  function mountCompare(other) {
    const { shots = [], snapshot = "" } = other?.views || {};
    const key = other ? `${other.qid}.${other.variant}.${snapshot}.${shots.join(",")}` : "";
    if (other) cmpCap.firstChild.textContent = vname(other) + (other.current ? " · Current" : "");
    if (cmpShown === key) return;
    cmpShown = key;
    stage.dataset.split = String(!!other);
    cmpPane.hidden = mainCap.hidden = !other;
    if (!other) { cmpView.replaceChildren(); return; }
    if (!snapshot && !shots.length) {  // a live version is never framed here either
      cmpView.replaceChildren(E("p", "vp-left vp-off", other.views?.live ? "This version is a live prototype, which opens in its own tab." : "This view is off in this session."));
    } else if (snapshot) {
      const f = E("iframe", "vp-cmp-frame");
      f.setAttribute("sandbox", "allow-scripts"); // plus the asset's own CSP sandbox; never allow-same-origin
      f.setAttribute("referrerpolicy", "no-referrer");
      f.title = `Version ${other.n}: ${other.label}`;
      let loads = 0;
      f.addEventListener("load", () => {
        if (++loads > 1 && f.isConnected) cmpView.replaceChildren(E("p", "vp-left", "This version tried to leave its page, so it is not shown."));
      });
      f.src = `/assets/${snapshot}`;
      cmpView.replaceChildren(f);
    } else {
      cmpView.replaceChildren(...shots.map((asset, k) => {
        const im = E("img", "vp-cmp-img"); im.src = `/assets/${asset}`;
        im.alt = `Version ${other.n}: ${other.label}` + (shots.length > 1 ? `, screenshot ${k + 1} of ${shots.length}` : "");
        return im;
      }));
    }
  }
  cmpClose.onclick = () => {
    ui.with = "";
    const h = new URLSearchParams(location.hash.slice(1)); h.delete("with");
    history.replaceState(null, "", location.pathname + (h.toString() ? "#" + h : ""));
    render();
    say("Side by side is closed.");
  };
  // A version link to this same page only changes the address's fragment.
  addEventListener("hashchange", () => {
    const h = new URLSearchParams(location.hash.slice(1)), nv = h.get("v") || ui.variant;
    if (nv !== ui.variant) closeComposer(); // a note being written stays while only the side-by-side version changes
    ui.variant = nv; ui.with = h.get("with") || ""; ui.active = h.get("n") || "";
    render();
  });
  /** Numbered pins for the shown variant's notes (1 is the oldest), plus the draft's while a note is being written. */
  /** The notes' pins on the shown variant (numbered across it, 1 the oldest), plus the draft's while a note is being
   *  written, each with the screenshot it sits on (`shot`, -1 for the snapshot). */
  function pinsFor(v) {
    const list = notesOn(v.id).map((a, i) => ({ n: i + 1, selector: a.selector, rect: a.rect || WHOLE, active: a.id === ui.active }));
    if (ui.draft) list.push({ n: list.length + 1, selector: ui.draft.selector, rect: ui.draft.rect, active: true });
    return list.map(p => ({ ...p, shot: shotOf(v, p.selector) }));
  }
  function drawPins(v) {
    const pins = pinsFor(v), key = JSON.stringify([pins, ui.annotate, ui.ready, shownVariant]);
    if (key === ui.pinsKey) return;
    ui.pinsKey = key;
    if (frame) {
      if (!ui.ready) return;
      send({ type: "mode", on: ui.annotate });
      send({ type: "pins", pins: pins.filter(p => p.shot < 0).map(p => ({ n: p.n, selector: p.selector, rect: p.rect, active: p.active })) });
    } else {
      layers.forEach((layer, k) => layer.replaceChildren(...pins.filter(p => p.shot === k).map(p => {
        const b = E("span", "vp-pin" + (p.active ? " vp-pin-on" : ""), String(p.n));
        b.style.left = `${p.rect.x + p.rect.w / 2}%`; b.style.top = `${p.rect.y + p.rect.h / 2}%`;
        return b;
      })));
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
    if (v) openComposer({ selector: shownView(v) === "snapshot" || liveOnly(v) ? "html" : "img", rect: { ...WHOLE } }, "the whole variant");
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

  // ---------- the live view ----------
  /** A failed Approve or Stop: show its error and build the box afresh, so its button comes back even when the error
   *  reads the same as the last one (the box's key would not change). */
  const liveFailed = x => { ui.liveErr = Core.errorText(x); liveBox._key = ""; render(); };
  /** The shown variant's live view: Open live prototype (a new tab, no opener, no referrer) only while its entry runs;
   *  else what it waits for, or that it ended. The owner also gets Approve (with the attestation a server on a port
   *  needs), Stop, and for a port a link to look at it on this machine first. */
  function renderLive(v) {
    const w = views(v), e = Core.liveOf(v), owner = Core.me.isOwner, link = Core.liveLink(v), kind = e?.status.kind || "";
    liveBox.hidden = !w.live;
    if (!w.live) return;
    const key = JSON.stringify([v.id, v.label, w.live, e, owner, link, ui.liveErr]);
    if (liveBox._key === key) return;
    liveBox._key = key;
    const parts = [];
    if (link) {
      const a = E("a", "vf-btn vf-btn-primary vf-btn-sm vp-live-open", "Open live prototype");
      a.href = link; a.target = "_blank"; a.rel = "noopener noreferrer"; a.referrerPolicy = "no-referrer";
      a.setAttribute("aria-label", `Open the live prototype of ${v.label} in a new tab`);
      parts.push(a);
    } else if (kind === "ended") {
      parts.push(E("p", "vp-live-state vp-live-ended", "Live prototype ended"));
    } else {
      parts.push(E("p", "vp-live-state vp-live-wait", !owner ? "Live version waiting for the host"
        : kind === "starting" ? "Starting the live prototype." : "Live version waiting for your Approve."));
    }
    if (owner && e && kind !== "ended") {
      const port = e.target?.kind === "port";
      if (kind === "pending" && port && /^http:\/\/127\.0\.0\.1:[0-9]{1,5}$/.test(e.url || "")) {
        const look = E("a", "vf-btn vf-btn-ghost vf-btn-sm vp-live-local", "Look at it on this machine");
        look.href = e.url; look.target = "_blank"; look.rel = "noopener noreferrer"; look.referrerPolicy = "no-referrer";
        parts.push(look);
      }
      let attest = null;
      if (kind === "pending" && port) {
        const lab = E("label", "vp-live-attest");
        attest = E("input"); attest.type = "checkbox";
        lab.append(attest, E("span", null, "It runs on sample data only, with writes stubbed and no credentials in its environment."));
        parts.push(lab);
      }
      if (kind === "pending") {
        const ok = btn("vf-btn vf-btn-primary vf-btn-sm vp-live-approve", "Approve");
        ok.setAttribute("aria-label", `Approve the live prototype ${e.label}, so guests can open it`);
        if (attest) { ok.disabled = true; attest.onchange = () => { ok.disabled = !attest.checked; }; }
        ok.onclick = () => {
          ok.disabled = true; ui.liveErr = "";
          Core.approveLive(e.id, !!attest?.checked).then(() => say("The live prototype is running. Guests can open it now."))
            .catch(liveFailed);
        };
        parts.push(ok);
      }
      const stop = btn("vf-btn vf-btn-ghost vf-btn-sm vp-live-stop", "Stop");
      stop.setAttribute("aria-label", `Stop the live prototype ${e.label}`);
      stop.onclick = () => {
        stop.disabled = true; ui.liveErr = "";
        Core.stopLive(e.id).then(() => say("The live prototype has stopped.")).catch(liveFailed);
      };
      parts.push(stop);
    }
    if (owner && ui.liveErr) { const er = E("p", "vp-live-err", ui.liveErr); er.setAttribute("role", "alert"); parts.push(er); }
    liveBox.replaceChildren(...parts);
  }

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
    if (!hasView(v) && ui.annotate) { ui.annotate = false; closeComposer(); } // nothing to pin a note to
    document.title = `${q.id}: ${q.short || q.text}`;
    title.textContent = `${q.id}: ${q.short || q.text}`;
    qText.textContent = q.text;
    look.hidden = !q.lookAt && !v.lookAt;
    lookQ.replaceChildren(...(q.lookAt ? [E("span", "vp-look-h", "Where to look: "), q.lookAt] : []));
    lookV.replaceChildren(...(v.lookAt ? [E("span", "vp-look-h", `${v.label}: `), v.lookAt] : []));
    renderTabs(q, v);
    renderLive(v);
    const w = views(v), kind = shownView(v);
    viewSeg.hidden = !(w.snapshot && w.shots.length);
    snapBtn.setAttribute("aria-pressed", String(kind === "snapshot"));
    shotsBtn.setAttribute("aria-pressed", String(kind === "shots"));
    shotsBtn.textContent = `Screenshots (${w.shots.length})`;
    mountStage(v);
    const line = Core.versionsOf(qid, v.id), me = line.length > 1 ? line.find(x => x.qid === qid && x.variant === v.id) : null;
    const [wq, wv] = ui.with.split("."), other = me ? line.find(x => x !== me && x.qid === wq && x.variant === wv) || null : null;
    renderVersions(v, line, me);
    mountCompare(other);
    if (me) mainCap.firstChild.textContent = vname(me) + (me.current ? " · Current" : "");
    annotateBtn.setAttribute("aria-pressed", String(ui.annotate));
    annotateBtn.textContent = ui.annotate ? "Annotate: on" : "Annotate";
    root.dataset.annotate = String(ui.annotate);
    hint.textContent = !hasView(v) ? OFF_TEXT : liveOnly(v) ? (ui.annotate ? "A live prototype opens in its own tab, so a note on it is on the whole variant." : "Open the live prototype, then come back here to choose it or leave a note.") : ui.annotate
      ? `${matchMedia("(pointer: coarse)").matches ? "Tap" : "Click"} the part of ${v.label} your note is about. Esc turns Annotate off.`
      : "Try each variant. Turn on Annotate to pin a note to any part of it.";
    wholeBtn.hidden = !ui.annotate || !!ui.draft;
    annotateBtn.hidden = !hasView(v);
    const hidden = Core.me.isOwner ? variants(q).filter(x => Core.viewsOff(x).length) : [];
    offNote.hidden = !hidden.length;
    offNote.textContent = hidden.length ? `Hidden from guests: ${hidden.map(x => `${x.label} (${Core.viewsOff(x).map(t => OFF_NAME[t]).join(", ")})`).join(", ")}.` : "";
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
