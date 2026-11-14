// Pin helper for a framed non-final page (docs/contracts/ui-feedback). The host appends it as an inline script: the
// planning shared page's server.py when it frames /assets/<id>.html?pin=1, the notes bridge when it hands host.html the
// page. It runs inside the page's sandbox (scripts, no same origin), so it can reach nothing but the page and its
// parent window. It answers the host by postMessage only: when the person pins an element, its path, box and up to 60
// characters of its label, plus its structural anchor (variant and state keys, content set, nearest test id and its
// index in that scope, role attribute, tag, and its path from that scope) and the view snapshot; never the page's
// markup. Hosts that ask for more get more: a region the person drags or moves with the keys (its box, the element
// holding it and the test-id elements it crosses), and the selected text as a quote with a little visible text either
// side, both only on a model-written page (docs/contracts/rendered-views, rule 9). The host checks every message it
// receives and keeps only what its contract admits. For a script re-locating a note, window.uiFeedbackRelocate
// replays a data log and finds a quote, with the same rules this file takes them by.
(() => {
  if (window.parent === window) return;
  const root = document.documentElement;
  const post = m => window.parent.postMessage(m, "*"); // the sandbox has no origin the parent could name
  const TAG = /^[a-z][a-z0-9]{0,15}(?:-[a-z0-9]{1,15}){0,3}$/;
  const STEP = /^([a-z]+)(?::([a-z0-9]+))?$/; // a data control's data-data-control value: op, or op:argument
  const MAX_DEPTH = 32;
  const NUDGE = 10; // pixels an arrow key moves or resizes a region
  let mode = false, kind = "element", pins = [], layer = null, hover = null, region = null, drag = null, maxElements = 0;
  const log = []; // the data controls pressed and content sets shown since the page loaded, in order

  /** The reference box notes are measured in: the whole scrollable page. */
  const box = () => ({ w: Math.max(root.scrollWidth, 1), h: Math.max(root.scrollHeight, 1) });
  /** The element's path from the root, one step per level with its place among same-tag siblings. A step whose tag
   *  the server would refuse (an SVG camelCase name, say) ends the path there, so the note pins that ancestor. */
  function pathOf(el, top = null) {
    const chain = [];
    for (let e = el; e && e.nodeType === 1 && e !== top; e = e.parentElement) chain.unshift(e);
    const steps = [];
    for (const e of chain.slice(0, MAX_DEPTH)) {
      const tag = e.localName;
      if (!TAG.test(tag)) break;
      let n = 1;
      for (let s = e.previousElementSibling; s; s = s.previousElementSibling) if (s.localName === tag) n++;
      steps.push(e === root ? tag : `${tag}:nth-of-type(${n})`);
    }
    return { path: steps.join(" > "), el: chain[steps.length - 1] || top || root };
  }
  /** The variant and screen state around an element, and its scope: the screen state inside the variant, else the
   *  variant, else the page. */
  function viewOf(el) {
    const variant = el.closest("[data-variant]"), state = el.closest("[data-screen-state]");
    const scope = state && variant && variant.contains(state) ? state : variant || root;
    return { variant, state: scope === state ? state : null, scope };
  }
  /** The scope two keys name, as viewOf takes it; null when the page has no such variant or state. */
  function scopeOf(variantKey, stateKey) {
    let s = root;
    if (variantKey) s = [...document.querySelectorAll("[data-variant]")].find(e => e.dataset.variant === variantKey) || null;
    if (s && variantKey && stateKey) s = [...s.querySelectorAll("[data-screen-state]")].find(e => e.dataset.screenState === stateKey) || null;
    return s;
  }
  /** Where an element sits by structure: the variant and screen state around it, the content set shown, the nearest
   *  element at or above it with a test id (and which match it is inside that scope), its role attribute, its tag, and
   *  its path from the scope. */
  function anchorOf(el) {
    const { variant, state, scope } = viewOf(el);
    const { path, el: at } = pathOf(el, scope); // a step the path cannot name ends it: the anchor is that ancestor
    el = at;
    const a = { tag: el.localName, cssPath: path };
    if (variant) a.variant = variant.dataset.variant;
    if (state) a.state = state.dataset.screenState;
    if (root.dataset.vsContent) a.content = root.dataset.vsContent;
    const t = el.closest("[data-testid]");
    if (t && (t === scope || scope.contains(t))) {
      a.testid = t.dataset.testid;
      a.testidIndex = [scope, ...scope.querySelectorAll("[data-testid]")].filter(e => e.dataset.testid === a.testid).indexOf(t);
    }
    const role = (el.getAttribute("role") || "").trim().split(/\s+/)[0];
    if (role) a.role = role;
    return a;
  }
  /** Everything a reload loses, for a note on `el`: its variant and screen state, the content set, the data log and
   *  the framed page's viewport. */
  function snapshot(el) {
    const { variant, state } = viewOf(el);
    const s = {
      data: { log: log.slice() },
      viewport: {
        w: Math.round(innerWidth), h: Math.round(innerHeight), dpr: devicePixelRatio,
        scrollX: Math.max(0, scrollX), scrollY: Math.max(0, scrollY),
        colorScheme: matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light",
        reducedMotion: matchMedia("(prefers-reduced-motion: reduce)").matches,
      },
    };
    if (variant) s.variant = variant.dataset.variant;
    if (state) s.state = state.dataset.screenState;
    if (root.dataset.vsContent) s.content = root.dataset.vsContent;
    return s;
  }
  const r2 = n => Math.round(n * 100) / 100;
  /** A client box in percent of the reference box, inside 0-100 with w and h above 0. */
  function pct(b) {
    const page = box();
    const x = Math.min(99.5, Math.max(0, r2(((b.left + scrollX) / page.w) * 100)));
    const y = Math.min(99.5, Math.max(0, r2(((b.top + scrollY) / page.h) * 100)));
    const w = Math.max(0.5, Math.min(100 - x, r2((b.width / page.w) * 100)));
    const h = Math.max(0.5, Math.min(100 - y, r2((b.height / page.h) * 100)));
    return { x, y, w: r2(w), h: r2(h) };
  }
  const rectOf = el => pct(el.getBoundingClientRect());
  const label = el => (el.getAttribute("aria-label") || el.getAttribute("alt") || el.textContent || "").replace(/\s+/g, " ").trim().slice(0, 60);
  const skip = el => !el || el === layer || layer?.contains(el);

  /** The text nodes of `scope` a person can see, in document order. */
  function visibleText(scope) {
    const out = [], w = document.createTreeWalker(scope, NodeFilter.SHOW_TEXT);
    for (let t = w.nextNode(); t; t = w.nextNode()) {
      const p = t.parentElement;
      if (p && !skip(p) && p.getClientRects().length) out.push(t);
    }
    return out;
  }
  const cp = s => [...s]; // code points, as the note contract counts
  /** A selection as a quote: its text with whitespace runs collapsed, cut to `lim.exact` code points, and up to
   *  `lim.context` code points of the scope's visible text either side. Never offsets: Seed and Clear move text. */
  function quoteOf(range, scope, lim) {
    let before = "", exact = "", after = "";
    for (const t of visibleText(scope)) {
      const d = t.data, s = t === range.startContainer ? range.startOffset : null, e = t === range.endContainer ? range.endOffset : null;
      // A space between text nodes keeps table cells and blocks apart for a reader; matching ignores whitespace.
      if (s !== null || e !== null) {
        before += ` ${d.slice(0, s ?? 0)}`;
        exact += ` ${d.slice(s ?? 0, e ?? d.length)}`;
        if (e !== null) after += ` ${d.slice(e)}`;
      } else {
        const c = range.comparePoint(t, 0);
        if (c < 0 && range.comparePoint(t, d.length) < 0) before += ` ${d}`;
        else if (c > 0) after += ` ${d}`;
        else exact += ` ${d}`;
      }
    }
    const full = cp(exact.replace(/\s+/g, " ").trim());
    if (!full.length) return null;
    const rest = full.slice(lim.exact).join("") + after;
    return {
      exact: full.slice(0, lim.exact).join(""),
      prefix: cp(before.replace(/\s+/g, " ")).slice(-lim.context).join(""),
      suffix: cp(rest.replace(/\s+/g, " ")).slice(0, lim.context).join(""),
    };
  }
  /** How many places in the scope's visible text hold the quote, whitespace ignored. The exact text decides; prefix
   *  and suffix pick among several. The element holding the one match gets data-relocate-quote. */
  function findQuote({ variant, state, quote }) {
    for (const old of document.querySelectorAll("[data-relocate-quote]")) old.removeAttribute("data-relocate-quote");
    const scope = scopeOf(variant, state), bare = s => (typeof s === "string" ? s.replace(/\s+/g, "") : "");
    const exact = bare(quote?.exact), pre = bare(quote?.prefix), suf = bare(quote?.suffix);
    if (!scope || !exact) return 0;
    const nodes = visibleText(scope), owner = [];
    let text = "";
    nodes.forEach((t, i) => { for (const ch of t.data) if (!/\s/.test(ch)) { text += ch; for (let k = 0; k < ch.length; k++) owner.push(i); } });
    const all = [];
    for (let i = text.indexOf(exact); i >= 0; i = text.indexOf(exact, i + 1)) all.push(i);
    const near = all.filter(i => text.slice(0, i).endsWith(pre) && text.startsWith(suf, i + exact.length));
    const found = near.length ? near : all;
    if (found.length === 1) {
      const r = document.createRange(), a = nodes[owner[found[0]]], b = nodes[owner[found[0] + exact.length - 1]];
      r.setStart(a, 0);
      r.setEnd(b, b.length);
      let el = r.commonAncestorContainer;
      if (el.nodeType !== 1) el = el.parentElement;
      el.setAttribute("data-relocate-quote", "");
    }
    return found.length;
  }
  /** Press each data control a log names, in order, and show each content set it names; returns how many steps found
   *  no single control to press. */
  function replay(steps) {
    let missed = 0;
    for (const s of Array.isArray(steps) ? steps : []) {
      if (s?.op === "content") { document.dispatchEvent(new CustomEvent("vs:show", { detail: { content: s.name } })); continue; }
      const want = s?.n !== undefined ? `${s.op}:${s.n}` : s?.name !== undefined ? `${s.op}:${s.name}` : String(s?.op);
      const hits = [...document.querySelectorAll("[data-data-control]")].filter(e => e.getAttribute("data-data-control") === want);
      if (hits.length === 1) hits[0].click();
      else missed++;
    }
    return missed;
  }
  Object.defineProperty(window, "uiFeedbackRelocate", { value: Object.freeze({ replay, findQuote }) });

  function ensureLayer() {
    if (layer) return layer;
    layer = document.createElement("div");
    layer.setAttribute("aria-hidden", "true");
    Object.assign(layer.style, { position: "absolute", left: "0", top: "0", width: "0", height: "0", zIndex: "2147483647", pointerEvents: "none" });
    root.append(layer);
    return layer;
  }
  function badge(n, x, y, active) {
    const b = document.createElement("div");
    b.textContent = String(n);
    Object.assign(b.style, {
      position: "absolute", left: `${x}px`, top: `${y}px`, transform: "translate(-40%, -40%)", minWidth: "22px", height: "22px",
      padding: "0 6px", borderRadius: "11px", font: "700 12px/22px system-ui, sans-serif", textAlign: "center",
      background: active ? "#f59e0b" : "#0d9488", color: "#fff", boxShadow: "0 0 0 2px #fff, 0 2px 6px rgb(0 0 0 / 0.35)",
    });
    return b;
  }
  /** Where a note sits: its element's top-left when the path still finds it, else its stored box. */
  function placeOf(p) {
    let el = null;
    try { el = document.querySelector(p.selector); } catch { /* not a selector: the stored box */ }
    if (el) { const b = el.getBoundingClientRect(); return { el, x: b.left + scrollX, y: b.top + scrollY }; }
    const page = box();
    return { el: null, x: (p.rect.x / 100) * page.w, y: (p.rect.y / 100) * page.h };
  }
  function outline(b, style) {
    const o = document.createElement("div");
    Object.assign(o.style, { position: "absolute", left: `${b.left + scrollX}px`, top: `${b.top + scrollY}px`, width: `${b.width}px`, height: `${b.height}px`, ...style });
    return o;
  }
  function draw() {
    const l = ensureLayer();
    l.replaceChildren();
    for (const p of pins) { const at = placeOf(p); l.append(badge(p.n, at.x, at.y, p.active)); }
    if (hover && mode && kind === "element") {
      l.append(outline(hover.getBoundingClientRect(), { outline: "2px dashed #0d9488", outlineOffset: "1px", background: "rgb(13 148 136 / 0.08)" }));
    }
    if (region && mode && kind === "region") {
      l.append(outline({ left: region.x, top: region.y, width: region.w, height: region.h }, { outline: "2px dashed #f59e0b", background: "rgb(245 158 11 / 0.12)" }));
    }
  }

  const meets = (a, b) => a.width > 0 && a.height > 0 && a.left < b.left + b.width && b.left < a.left + a.width && a.top < b.top + b.height && b.top < a.top + a.height;
  /** The region as a note: its box, the innermost element holding all of it, and the test-id elements it crosses. */
  function sendRegion() {
    if (!region || region.w < 1 || region.h < 1) return;
    const b = { left: region.x, top: region.y, width: region.w, height: region.h };
    let holder = document.elementFromPoint(b.left + b.width / 2, b.top + b.height / 2) || root;
    for (; holder !== root; holder = holder.parentElement || root) {
      const h = holder.getBoundingClientRect();
      if (!skip(holder) && h.left <= b.left && h.top <= b.top && h.right >= b.left + b.width && h.bottom >= b.top + b.height) break;
    }
    const crossed = [...document.querySelectorAll("[data-testid]")].filter(e => !skip(e) && meets(e.getBoundingClientRect(), b));
    post({ type: "region", rect: pct(b), anchor: anchorOf(holder), elements: crossed.slice(0, maxElements).map(anchorOf), snapshot: snapshot(holder) });
  }
  function nudge(dx, dy, grow) {
    if (!region) return;
    if (grow) { region.w = Math.max(NUDGE, region.w + dx); region.h = Math.max(NUDGE, region.h + dy); }
    else { region.x = Math.max(0, region.x + dx); region.y = Math.max(0, region.y + dy); }
    draw();
  }
  const ARROWS = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] };

  const over = e => {
    if (!mode) return;
    if (kind === "region") {
      if (drag) { region = { x: Math.min(drag.x, e.clientX), y: Math.min(drag.y, e.clientY), w: Math.abs(e.clientX - drag.x), h: Math.abs(e.clientY - drag.y) }; draw(); }
      return;
    }
    if (skip(e.target)) return;
    hover = pathOf(e.target).el;
    draw();
  };
  const stop = e => { if (mode) { e.preventDefault(); e.stopImmediatePropagation(); } };
  function pick(e) {
    if (!mode) return;
    stop(e);
    if (kind !== "element" || skip(e.target)) return;
    const { path, el } = pathOf(e.target);
    if (!path) return;
    post({ type: "pinned", selector: path, rect: rectOf(el), label: label(el), anchor: anchorOf(el), snapshot: snapshot(el) });
  }
  addEventListener("pointermove", over, true);
  addEventListener("click", pick, true);
  // Before `stop`, which ends the event for every later listener.
  addEventListener("pointerdown", e => { if (mode && kind === "region") { drag = { x: e.clientX, y: e.clientY }; region = { x: e.clientX, y: e.clientY, w: 0, h: 0 }; draw(); } }, true);
  addEventListener("pointerup", e => { if (mode && kind === "region" && drag) { stop(e); drag = null; if (region.w >= 4 && region.h >= 4) sendRegion(); } }, true);
  for (const t of ["pointerdown", "mousedown", "mouseup", "submit", "auxclick", "dblclick"]) addEventListener(t, stop, true);
  addEventListener("keydown", e => {
    if (e.key === "Escape") { post({ type: "escape" }); return; }
    if (mode && kind === "region") {
      // Region keys stay here: the arrows never reach the page's own keys (the switcher's state steps).
      const a = ARROWS[e.key];
      if (a) { stop(e); nudge(a[0] * NUDGE, a[1] * NUDGE, e.shiftKey); }
      else if (e.key === "Enter") { stop(e); sendRegion(); }
      return;
    }
    const field = e.target instanceof HTMLElement && (/^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName) || e.target.isContentEditable);
    if ((e.key === "t" || e.key === "T") && !field && !e.metaKey && !e.ctrlKey && !e.altKey && !getSelection().isCollapsed) post({ type: "want-text" });
  }, true);
  // The data log: a press of a data control the page marks, and each content set the switcher shows.
  addEventListener("click", e => {
    if (mode) return;
    const c = e.target instanceof Element ? e.target.closest("[data-data-control]") : null;
    const m = c && STEP.exec(c.getAttribute("data-data-control"));
    if (!m) return;
    const step = { op: m[1] };
    if (m[2] !== undefined) { if (/^[0-9]+$/.test(m[2])) step.n = Number(m[2]); else step.name = m[2]; }
    log.push(step);
  }, true);
  new MutationObserver(() => { if (root.dataset.vsContent) log.push({ op: "content", name: root.dataset.vsContent }); })
    .observe(root, { attributes: true, attributeFilter: ["data-vs-content"] });
  addEventListener("resize", draw);
  if (window.ResizeObserver) new ResizeObserver(() => { if (pins.length || mode) draw(); }).observe(root); // late images move elements

  addEventListener("message", e => {
    if (e.source !== window.parent || !e.data || typeof e.data !== "object") return;
    const m = e.data;
    if (m.type === "mode") {
      mode = !!m.on;
      kind = m.kind === "region" ? "region" : "element";
      maxElements = Number.isInteger(m.max) && m.max > 0 ? m.max : 0;
      hover = null;
      drag = null;
      // A region starts in the middle of the view, so the keys alone can place it.
      region = mode && kind === "region" ? { x: Math.max(0, innerWidth / 2 - 80), y: Math.max(0, innerHeight / 2 - 50), w: 160, h: 100 } : null;
      root.style.cursor = mode ? "crosshair" : "";
      draw();
    } else if (m.type === "nudge" && mode && kind === "region") nudge(Math.sign(m.dx) * NUDGE, Math.sign(m.dy) * NUDGE, !!m.grow);
    else if (m.type === "commit" && mode && kind === "region") sendRegion();
    else if (m.type === "text") {
      const sel = getSelection(), lim = { exact: m.exact, context: m.context };
      const range = sel && sel.rangeCount && !sel.isCollapsed ? sel.getRangeAt(0) : null;
      let el = range ? range.commonAncestorContainer : null;
      if (el && el.nodeType !== 1) el = el.parentElement;
      const quote = el && !skip(el) && Number.isInteger(lim.exact) && Number.isInteger(lim.context) ? quoteOf(range, viewOf(el).scope, lim) : null;
      if (!quote) post({ type: "selected", none: true });
      else post({ type: "selected", rect: pct(range.getBoundingClientRect()), anchor: anchorOf(el), quote, snapshot: snapshot(el) });
    }
    else if (m.type === "pins" && Array.isArray(m.pins)) { pins = m.pins.slice(0, 500); draw(); }
    else if (m.type === "focus") {
      const p = pins.find(x => x.n === m.n);
      if (!p) return;
      const at = placeOf(p), behavior = matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth";
      if (at.el) at.el.scrollIntoView({ block: "center", behavior });
      else scrollTo({ top: Math.max(0, at.y - innerHeight / 3), behavior });
    }
  });
  post({ type: "ready" });
})();
