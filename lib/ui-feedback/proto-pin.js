// Pin helper for a framed non-final page (docs/contracts/ui-feedback). The host appends it as an inline script: the
// planning shared page's server.py when it frames /assets/<id>.html?pin=1, the notes bridge when it hands host.html the
// page. It runs inside the page's sandbox (scripts, no same origin), so it can reach nothing but the page and its
// parent window. It answers the host by postMessage only: when the person pins an element, its path, box and up to 60
// characters of its label, plus its structural anchor (variant and state keys, content set, nearest test id and its
// index in that scope, role attribute, tag, and its path from that scope) and the view snapshot; never the page's
// markup. Hosts that ask for more get more: a region the person drags, moves or resizes, by pointer or keys, kept in
// page coordinates so it can run past the view, which a drag at the frame's edge scrolls (its box, the element
// holding it and the test-id elements it crosses, or the holder's child elements it crosses when it crosses none),
// a move arrow (the element to move, then the element or point it should go to, each end with its own anchor),
// and the selected text as a quote with a little visible text either
// side, both only on a model-written page (docs/contracts/rendered-views, rule 9). The host checks every message it
// receives and keeps only what its contract admits. For a script re-locating a note, window.uiFeedbackRelocate
// replays a data log, finds a quote and sets the controls, with the same rules this file takes them by. When the page
// carries the controls runtime (controls.js), the ready message also carries its manifest and the data controls and
// content sets it marks, and the host page's Controls tab sets values and presses data controls through this file.
// Contract: https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/ui-feedback/README.md
(() => {
  if (window.parent === window) return;
  const root = document.documentElement;
  const post = m => window.parent.postMessage(m, "*"); // the sandbox has no origin the parent could name
  const TAG = /^[a-z][a-z0-9]{0,15}(?:-[a-z0-9]{1,15}){0,3}$/;
  const STEP = /^([a-z]+)(?::([a-z0-9]+))?$/; // a data control's data-data-control value: op, or op:argument
  const MAX_DEPTH = 32;
  const NUDGE = 10; // pixels an arrow key moves or resizes a region
  const RESIZE_REACH_PX = 6, SCROLL_BAND_PX = 40;
  const SVG = "http://www.w3.org/2000/svg";
  const KINDS = ["element", "region", "move"];
  let mode = false, kind = "element", pins = [], layer = null, hover = null, region = null, drag = null, maxElements = 0;
  let moving = null, arrow = null;
  let holding = false, held = null, markers = true;
  let hovered = null, selected = null, badges = [], markerClicks = false;
  const hold = h => { if (holding) { held = h; draw(); } };
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
  /** Whether the variant and screen state a note was made on are shown now; a note made outside every variant is. */
  function inView(t) {
    if (typeof t.variant !== "string") return true;
    const s = scopeOf(t.variant, typeof t.state === "string" ? t.state : null);
    return !!s && !s.closest("[hidden]");
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
  /** Everything a reload loses, for a note on `el`: its variant and screen state, the content set, the data log, the
   *  control values and the framed page's viewport. */
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
    const values = window.uiFeedbackControls?.values();
    if (values && Object.keys(values).length) s.controls = values;
    return s;
  }
  /** A data control's mark as a data step: {op} or {op, n} or {op, name}; null when it is no mark. */
  function stepOf(c) {
    const m = c && STEP.exec(c.getAttribute("data-data-control"));
    if (!m) return null;
    const step = { op: m[1] };
    if (m[2] !== undefined) { if (/^[0-9]+$/.test(m[2])) step.n = Number(m[2]); else step.name = m[2]; }
    return step;
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
   *  no single control to press, or -1 when one did and the page marks no data control. */
  function replay(steps) {
    const marked = !!document.querySelector("[data-data-control]");
    let missed = 0;
    for (const s of Array.isArray(steps) ? steps : []) {
      if (s?.op === "content") { document.dispatchEvent(new CustomEvent("vs:show", { detail: { content: s.name } })); continue; }
      const want = s?.n !== undefined ? `${s.op}:${s.n}` : s?.name !== undefined ? `${s.op}:${s.name}` : String(s?.op);
      const hits = [...document.querySelectorAll("[data-data-control]")].filter(e => e.getAttribute("data-data-control") === want);
      if (hits.length === 1) hits[0].click();
      else missed++;
    }
    return missed && !marked ? -1 : missed;
  }
  /** Set each control a note carries; returns how many it could not set (no control for the id, or a value its control
   *  cannot hold), or -1 with no controls runtime. */
  const setControls = v => (window.uiFeedbackControls ? window.uiFeedbackControls.set(v) : -1);
  Object.defineProperty(window, "uiFeedbackRelocate", { value: Object.freeze({ replay, findQuote, setControls }) });

  function ensureLayer() {
    if (layer) return layer;
    layer = document.createElement("div");
    layer.setAttribute("aria-hidden", "true");
    layer.setAttribute("data-ui-feedback-layer", "");
    Object.assign(layer.style, { position: "absolute", left: "0", top: "0", width: "0", height: "0", zIndex: "2147483647", pointerEvents: "none" });
    root.append(layer);
    return layer;
  }
  /** The host page's accent tokens (host.html --uif-*), for the color scheme the page is shown in now. */
  const ink = () => (matchMedia("(prefers-color-scheme: dark)").matches
    ? { accent: "#a99bff", on: "#15122b", surface: "#1c1d24", wash: "rgb(169 155 255 / 0.14)" }
    : { accent: "#4433cc", on: "#ffffff", surface: "#ffffff", wash: "rgb(68 51 204 / 0.1)" });
  function badge(n, x, y, active) {
    const b = document.createElement("div"), c = ink(), draft = String(n).startsWith("D");
    b.textContent = String(n);
    Object.assign(b.style, {
      position: "absolute", left: `${x}px`, top: `${y}px`, transform: "translate(-40%, -40%)", minWidth: "22px", height: "22px",
      padding: "0 6px", boxSizing: "border-box", borderRadius: "11px 11px 11px 3px", font: "700 12px/18px system-ui, sans-serif", textAlign: "center",
      background: draft ? c.surface : c.accent, color: draft ? c.accent : c.on, border: `2px ${draft ? "dashed" : "solid"} ${draft ? c.accent : c.surface}`,
      boxShadow: active ? `0 0 0 2px ${c.surface}, 0 0 0 4px ${c.accent}` : "0 2px 6px rgb(0 0 0 / 0.3)",
    });
    return b;
  }
  /** Where a note sits: the top-left of its box now when it carries a contract path (noteBox), else of the element its
   *  selector finds, else of its stored box. */
  function placeOf(p) {
    const now = typeof p.cssPath === "string" && noteBox(p);
    if (now) return { el: null, x: now.left + scrollX, y: now.top + scrollY };
    let el = null;
    try { el = document.querySelector(p.selector); } catch { /* not a selector: the stored box */ }
    if (el) { const b = el.getBoundingClientRect(); return { el, x: b.left + scrollX, y: b.top + scrollY }; }
    const page = box();
    return { el: null, x: ((p.rect?.x ?? 0) / 100) * page.w, y: ((p.rect?.y ?? 0) / 100) * page.h };
  }
  function outline(b, style) {
    const o = document.createElement("div");
    Object.assign(o.style, { position: "absolute", left: `${b.left + scrollX}px`, top: `${b.top + scrollY}px`, width: `${b.width}px`, height: `${b.height}px`, ...style });
    return o;
  }
  /** A listed note's box now, in client pixels: an element note's element while its path still finds one shown in the
   *  note's scope, else the stored box; null when it has neither. */
  function noteBox(t) {
    if (t.kind === "element" && typeof t.cssPath === "string") {
      const scope = scopeOf(t.variant, t.state);
      let el = null;
      try { el = scope && (t.cssPath === "" ? scope : scope.querySelector(`:scope > ${t.cssPath}`)); } catch { el = null; }
      if (el && el.getClientRects?.().length) return el.getBoundingClientRect();
    }
    const r = t.rect;
    if (!r || ![r.x, r.y, r.w, r.h].every(Number.isFinite)) return null;
    const page = box();
    return { left: (r.x / 100) * page.w - scrollX, top: (r.y / 100) * page.h - scrollY, width: (r.w / 100) * page.w, height: (r.h / 100) * page.h };
  }
  /** The marker under a pointer event, outside a pick mode and a held pick; null elsewhere. Only its own box counts. */
  function markerAt(e) {
    if (!markerClicks || mode || held || !markers || typeof e.clientX !== "number") return null;
    if (e.isTrusted === false || (e.detail === 0 && !e.pointerType)) return null;
    const hit = badges.find(({ el }) => { const b = el.getBoundingClientRect(); return e.clientX >= b.left && e.clientX <= b.left + b.width && e.clientY >= b.top && e.clientY <= b.top + b.height; });
    return hit ? hit.n : null;
  }
  /** The middle of a move arrow's end in page pixels: its element while the page still holds it, else the element its
   *  path finds, else its stored box or point. */
  function endOf(end) {
    let el = end.el && root.contains(end.el) ? end.el : null;
    if (!el && end.selector) try { el = document.querySelector(end.selector); } catch { el = null; }
    if (el) { const b = el.getBoundingClientRect(); return { x: b.left + scrollX + b.width / 2, y: b.top + scrollY + b.height / 2 }; }
    const page = box(), r = end.rect || end.point;
    return { x: ((r.x + (r.w || 0) / 2) / 100) * page.w, y: ((r.y + (r.h || 0) / 2) / 100) * page.h };
  }
  function arrowShape(a, b) {
    const page = box(), svg = document.createElementNS(SVG, "svg"), line = document.createElementNS(SVG, "line"), tip = document.createElementNS(SVG, "polygon");
    svg.setAttribute("width", String(page.w));
    svg.setAttribute("height", String(page.h));
    Object.assign(svg.style, { position: "absolute", left: "0", top: "0", overflow: "visible" });
    for (const [k, v] of Object.entries({ x1: a.x, y1: a.y, x2: b.x, y2: b.y, stroke: ink().accent, "stroke-width": 3 })) line.setAttribute(k, String(v));
    const t = Math.atan2(b.y - a.y, b.x - a.x), side = d => `${b.x - 14 * Math.cos(t + d)},${b.y - 14 * Math.sin(t + d)}`;
    tip.setAttribute("points", `${b.x},${b.y} ${side(-0.45)} ${side(0.45)}`);
    tip.setAttribute("fill", ink().accent);
    svg.append(line, tip);
    return svg;
  }
  function draw() {
    const l = ensureLayer(), c = ink();
    l.replaceChildren();
    badges = [];
    if (markers) for (const p of pins.filter(inView)) { const at = placeOf(p), b = badge(p.n, at.x, at.y, p.active); badges.push({ n: p.n, el: b }); l.append(b); }
    for (const [t, which, style] of [[hovered, "hover", { outline: `2px dashed ${c.accent}`, outlineOffset: "1px", background: c.wash }],
      [selected, "selected", { outline: `3px solid ${c.accent}`, outlineOffset: "1px", background: c.wash }]]) {
      const b = t && !mode && (which === "selected" || inView(t)) && noteBox(t);
      if (!b) continue;
      const o = outline(b, style);
      o.dataset.note = which;
      l.append(o);
    }
    if (arrow) l.append(arrowShape(endOf(arrow.from), endOf(arrow.to)));
    if (hover && mode && kind !== "region") {
      l.append(outline(hover.getBoundingClientRect(), { outline: `2px dashed ${c.accent}`, outlineOffset: "1px", background: c.wash }));
    }
    if (moving && mode && kind === "move") {
      l.append(outline(moving.from.el.getBoundingClientRect(), { outline: `2px solid ${c.accent}`, outlineOffset: "1px" }));
      if (moving.at) l.append(arrowShape(endOf(moving.from), moving.at));
    }
    if (region && mode && kind === "region") {
      l.append(outline({ left: region.x - scrollX, top: region.y - scrollY, width: region.w, height: region.h }, { outline: `2px dashed ${c.accent}`, background: c.wash }));
    }
    if (held && !mode) {
      const b = held.el ? held.el.getBoundingClientRect() : { left: held.left - scrollX, top: held.top - scrollY, width: held.width, height: held.height };
      l.append(outline(b, { outline: `2px solid ${c.accent}`, outlineOffset: "1px", background: c.wash }));
    }
  }

  const meets = (a, b) => a.width > 0 && a.height > 0 && a.left < b.left + b.width && b.left < a.left + a.width && a.top < b.top + b.height && b.top < a.top + a.height;
  /** The region as a note: its box, the innermost element holding all of it, and the test-id elements it crosses, or
   *  the holder's child elements it crosses when it crosses none. */
  function sendRegion() {
    if (!region || region.w < 1 || region.h < 1) return;
    const b = { left: region.x - scrollX, top: region.y - scrollY, width: region.w, height: region.h };
    const within = (v, hi) => Math.min(Math.max(v, 0), hi - 1);
    let holder = document.elementFromPoint(within(b.left + b.width / 2, innerWidth), within(b.top + b.height / 2, innerHeight)) || root;
    for (; holder !== root; holder = holder.parentElement || root) {
      const h = holder.getBoundingClientRect();
      if (!skip(holder) && h.left <= b.left && h.top <= b.top && h.right >= b.left + b.width && h.bottom >= b.top + b.height) break;
    }
    const crossing = els => [...els].filter(e => !skip(e) && meets(e.getBoundingClientRect(), b));
    const marked = crossing(document.querySelectorAll("[data-testid]"));
    const crossed = marked.length ? marked : crossing(holder.children);
    post({ type: "region", rect: pct(b), anchor: anchorOf(holder), elements: crossed.slice(0, maxElements).map(anchorOf), snapshot: snapshot(holder) });
    hold({ left: region.x, top: region.y, width: region.w, height: region.h });
  }
  /** Scroll the page just enough to show page row `y`. */
  function reveal(y) {
    if (y < scrollY) scrollBy(0, y - scrollY);
    else if (y > scrollY + innerHeight) scrollBy(0, y - scrollY - innerHeight);
  }
  function nudge(dx, dy, grow) {
    if (!region) return;
    if (grow) { region.w = Math.max(NUDGE, region.w + dx); region.h = Math.max(NUDGE, region.h + dy); }
    else { region.x = Math.max(0, region.x + dx); region.y = Math.max(0, region.y + dy); }
    if (dy) reveal(dy > 0 ? region.y + region.h : region.y);
    draw();
  }
  const pageAt = e => ({ x: e.clientX + scrollX, y: e.clientY + scrollY });
  /** What a press at page point `p` takes hold of: "move" inside the region, the edges it is within RESIZE_REACH_PX of
   *  ({l, r, t, b}, two for a corner), or null outside it, where a press draws a new region. */
  function grabAt(p) {
    if (!region || !region.w || !region.h) return null;
    const { x, y, w, h } = region, k = RESIZE_REACH_PX;
    if (p.x < x - k || p.x > x + w + k || p.y < y - k || p.y > y + h + k) return null;
    const dl = Math.abs(p.x - x), dr = Math.abs(p.x - x - w), dt = Math.abs(p.y - y), db = Math.abs(p.y - y - h);
    const edges = { l: dl <= k && dl < dr, r: dr <= k && dr <= dl, t: dt <= k && dt < db, b: db <= k && db <= dt };
    if (edges.l || edges.r || edges.t || edges.b) return edges;
    return p.x > x && p.x < x + w && p.y > y && p.y < y + h ? "move" : null;
  }
  function cursorFor(g) {
    if (!g) return "crosshair";
    if (g === "move") return "move";
    if ((g.t && g.l) || (g.b && g.r)) return "nwse-resize";
    if ((g.t && g.r) || (g.b && g.l)) return "nesw-resize";
    return g.l || g.r ? "ew-resize" : "ns-resize";
  }
  /** The region with the drag's pointer at page point `at`, held inside the page as it was at the press: a new box
   *  from the press, the grabbed box moved by the pointer's travel, or the grabbed box with its grabbed edges at the
   *  pointer. */
  function dragTo(at) {
    const { from, grab, box: b, page } = drag;
    const p = { x: Math.min(Math.max(at.x, 0), page.w), y: Math.min(Math.max(at.y, 0), page.h) };
    drag.moved = drag.moved || p.x !== from.x || p.y !== from.y;
    const span = (x1, y1, x2, y2) => ({ x: Math.min(x1, x2), y: Math.min(y1, y2), w: Math.abs(x2 - x1), h: Math.abs(y2 - y1) });
    if (!grab) region = span(from.x, from.y, p.x, p.y);
    else if (grab === "move") region = { ...b, x: Math.min(Math.max(0, b.x + p.x - from.x), page.w - b.w), y: Math.min(Math.max(0, b.y + p.y - from.y), page.h - b.h) };
    else region = span(grab.l ? p.x : b.x, grab.t ? p.y : b.y, grab.r ? p.x : b.x + b.w, grab.b ? p.y : b.y + b.h);
    draw();
  }
  const nextFrame = window.requestAnimationFrame ? fn => window.requestAnimationFrame(fn) : fn => setTimeout(fn, 16);
  /** Each frame a drag holds the pointer near the frame's top or bottom, or past it, scroll the page that way and
   *  keep the region's moving edge under the pointer. */
  function edgeScroll(d) {
    if (drag !== d) return;
    const y = d.cy, over = y < SCROLL_BAND_PX ? y - SCROLL_BAND_PX : y > innerHeight - SCROLL_BAND_PX ? y - innerHeight + SCROLL_BAND_PX : 0;
    if (over) {
      const before = scrollY;
      scrollBy(0, Math.sign(over) * Math.min(40, Math.ceil(Math.abs(over) / 2)));
      if (scrollY !== before) dragTo({ x: d.cx + scrollX, y: d.cy + scrollY });
    }
    nextFrame(() => edgeScroll(d));
  }
  const ARROWS = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] };
  const HOST_KEYS = new Set(["p", "r", "a", "m", "n"]);
  const inField = e => e.target instanceof HTMLElement && (/^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName) || e.target.isContentEditable);
  const chorded = e => e.metaKey || e.ctrlKey || e.altKey;

  const over = e => {
    if (!mode) return;
    if (kind === "region") {
      if (drag) { drag.cx = e.clientX; drag.cy = e.clientY; dragTo(pageAt(e)); }
      else root.style.cursor = cursorFor(grabAt(pageAt(e)));
      return;
    }
    if (skip(e.target)) return;
    hover = pathOf(e.target).el;
    if (moving) moving.at = { x: e.clientX + scrollX, y: e.clientY + scrollY };
    draw();
  };
  const swallow = e => { e.preventDefault(); e.stopImmediatePropagation(); };
  const stop = e => { if (mode || held || markerAt(e) !== null) swallow(e); };
  function pick(e) {
    if (!mode) {
      const n = markerAt(e);
      if (n !== null) { swallow(e); post({ type: "marker", n }); return; }
      if (selected && !held) { selected = null; draw(); post({ type: "unselected" }); }
      stop(e);
      return;
    }
    stop(e);
    if (kind === "region" || skip(e.target)) return;
    const { path, el } = pathOf(e.target);
    if (kind === "move") return pickMove(e, path, el);
    if (!path) return;
    post({ type: "pinned", selector: path, rect: rectOf(el), label: label(el), anchor: anchorOf(el), snapshot: snapshot(el) });
    hold({ el });
  }
  /** A move arrow's first click picks the element to move; the second picks where it goes: the element clicked, or the
   *  point alone with Shift, on the page's root or body, on the element being moved, or outside the scope the note's
   *  anchors are counted in. */
  function pickMove(e, path, el) {
    if (!moving) {
      if (path) { moving = { from: { el, selector: path, rect: rectOf(el) } }; draw(); }
      return;
    }
    const page = box(), at = v => Math.min(100, Math.max(0, r2(v)));
    const point = { x: at(((e.clientX + scrollX) / page.w) * 100), y: at(((e.clientY + scrollY) / page.h) * 100) };
    const fits = path && !e.shiftKey && el !== root && el !== document.body && el !== moving.from.el;
    const onto = fits && viewOf(el).scope === viewOf(moving.from.el).scope ? el : null;
    const { from } = moving;
    moving = null;
    arrow = { from, to: onto ? { el: onto, selector: path, point } : { point } };
    post({ type: "move", selector: from.selector, rect: from.rect, anchor: anchorOf(from.el), to: onto ? { anchor: anchorOf(onto), point } : { point }, snapshot: snapshot(from.el) });
    draw();
  }
  addEventListener("pointermove", over, true);
  addEventListener("click", pick, true);
  // Before `stop`, which ends the event for every later listener.
  addEventListener("pointerdown", e => {
    if (!mode || kind !== "region") return;
    const from = pageAt(e);
    drag = { from, grab: grabAt(from), box: region, page: box(), cx: e.clientX, cy: e.clientY, moved: false };
    if (!drag.grab) region = { ...from, w: 0, h: 0 };
    if (e.isTrusted && root.setPointerCapture) root.setPointerCapture(e.pointerId);
    edgeScroll(drag);
    draw();
  }, true);
  // A press that never became a drag (a click to focus the frame) keeps the box the keys were moving.
  addEventListener("pointerup", e => {
    if (!mode || kind !== "region" || !drag) return;
    stop(e);
    const d = drag;
    drag = null;
    if (d.grab ? d.moved : region.w >= 4 && region.h >= 4) sendRegion();
    else { region = d.box; draw(); }
  }, true);
  for (const t of ["pointercancel", "lostpointercapture", "blur"]) {
    addEventListener(t, () => { if (drag) { region = drag.box; drag = null; draw(); } }, true);
  }
  for (const t of ["pointerdown", "mousedown", "mouseup", "submit", "auxclick", "dblclick"]) addEventListener(t, stop, true);
  addEventListener("keydown", e => {
    if (e.key === "Escape") { post({ type: "escape" }); return; }
    if (held && !mode) { stop(e); return; }
    if (mode && kind === "region") {
      // Region keys stay here: the arrows never reach the page's own keys (the switcher's state steps).
      const a = ARROWS[e.key];
      if (a) { stop(e); nudge(a[0] * NUDGE, a[1] * NUDGE, e.shiftKey); }
      else if (e.key === "Enter") { stop(e); sendRegion(); }
      return;
    }
    if ((e.key === "t" || e.key === "T") && !inField(e) && !chorded(e) && !getSelection().isCollapsed) post({ type: "want-text" });
  }, true);
  addEventListener("keydown", e => {
    const key = (e.key || "").toLowerCase();
    if (HOST_KEYS.has(key) && !e.defaultPrevented && !inField(e) && !chorded(e)) post({ type: "key", key });
  });
  // The data log: a press of a data control the page marks, and each content set the switcher shows.
  addEventListener("click", e => {
    if (mode) return;
    const step = stepOf(e.target instanceof Element ? e.target.closest("[data-data-control]") : null);
    if (step) log.push(step);
  }, true);
  new MutationObserver(() => {
    if (!root.dataset.vsContent) return;
    log.push({ op: "content", name: root.dataset.vsContent });
    post({ type: "content", name: root.dataset.vsContent });
  }).observe(root, { attributes: true, attributeFilter: ["data-vs-content"] });
  addEventListener("resize", draw);
  window.matchMedia?.("(prefers-color-scheme: dark)").addEventListener?.("change", draw);
  /** The variants and the shown variant's screen states, with which are shown, for the host page's view arrows; sent
   *  when it changes. */
  let viewSent = "";
  function postView() {
    const shown = els => els.find(e => !e.closest("[hidden]"))?.dataset;
    const variants = [...document.querySelectorAll("[data-variant]")];
    const current = variants.find(v => !v.closest("[hidden]")) || null;
    const states = current ? [...current.querySelectorAll("[data-screen-state]")] : [];
    const m = {
      type: "view",
      variants: variants.map(v => ({ key: v.dataset.variant, label: v.dataset.variantLabel || "" })),
      variant: current ? current.dataset.variant : null,
      states: states.map(s => ({ key: s.dataset.screenState, label: s.dataset.screenStateLabel || "" })),
      state: shown(states)?.screenState ?? null,
    };
    const now = JSON.stringify(m);
    if (now !== viewSent) { viewSent = now; post(m); }
  }
  new MutationObserver(postView).observe(root, { subtree: true, attributes: true, attributeFilter: ["hidden"] });
  const HEADING = "h1, h2, h3, h4, h5, h6, [role='heading']";
  /** What a reader calls `el`: its accessible label, else the heading it holds, else its text. */
  function ownText(el) {
    const h = el.getAttribute("aria-label") || el.getAttribute("alt") ? null : el.querySelector(HEADING);
    return label(h || el);
  }
  /** The row's first cell for an element in a later cell, else the heading text of the nearest block around `el`, inside
   *  its scope, that has a heading `el` is not part of. */
  function cardOf(el, scope) {
    const row = el.closest("tr"), first = row && scope.contains(row) ? row.querySelector("th, td") : null;
    if (first && !first.contains(el) && !el.contains(first)) return label(first);
    for (let a = el.parentElement; a; a = a === scope ? null : a.parentElement) {
      const h = [...a.querySelectorAll(HEADING)].find(x => x !== el && !el.contains(x) && !x.contains(el));
      if (h) return label(h);
    }
    return "";
  }
  /** A listed note's element, found as noteBox finds an element note's, shown or not; null when its path finds none. */
  function elementAt(variant, state, cssPath) {
    const scope = scopeOf(variant, state);
    if (!scope || typeof cssPath !== "string") return null;
    try { return cssPath === "" ? scope : scope.querySelector(`:scope > ${cssPath}`); } catch { return null; }
  }
  /** Each asked note's own visible text and its card's heading, by the key the host page asked with. */
  function names(targets) {
    const out = [];
    for (const t of Array.isArray(targets) ? targets.slice(0, 500) : []) {
      if (!t || !Number.isInteger(t.k)) continue;
      const el = elementAt(t.variant, t.state, t.cssPath), scope = scopeOf(t.variant, t.state);
      const to = typeof t.toPath === "string" ? elementAt(t.variant, t.state, t.toPath) : null;
      out.push({ k: t.k, text: el ? ownText(el) : "", card: el ? cardOf(el, scope) : "", toText: to ? ownText(to) : "", toCard: to ? cardOf(to, scope) : "" });
    }
    post({ type: "named", names: out });
  }
  let drawQueued = false;
  const queueDraw = () => {
    if (drawQueued) return;
    drawQueued = true;
    (window.requestAnimationFrame || (fn => fn()))(() => { drawQueued = false; draw(); });
  };
  addEventListener("scroll", queueDraw, { passive: true });
  new MutationObserver(() => { if (pins.length || hovered || selected) queueDraw(); }).observe(root, { subtree: true, attributes: true, attributeFilter: ["hidden"] });
  if (window.ResizeObserver) new ResizeObserver(() => { if (pins.length || mode || arrow) draw(); }).observe(root);

  addEventListener("message", e => {
    if (e.source !== window.parent || !e.data || typeof e.data !== "object") return;
    const m = e.data;
    if (m.type === "mode") {
      mode = !!m.on;
      holding = m.hold === true;
      kind = KINDS.includes(m.kind) ? m.kind : "element";
      maxElements = Number.isInteger(m.max) && m.max > 0 ? m.max : 0;
      hover = null;
      drag = null;
      if (mode) hovered = selected = null;
      moving = null;
      if (mode) arrow = null;
      // A region starts in the middle of the view, so the keys alone can place it.
      const r = m.rect, page = box();
      const seed = r && typeof r === "object" && [r.x, r.y, r.w, r.h].every(Number.isFinite) && r.w > 0 && r.h > 0;
      region = !mode || kind !== "region" ? null
        : seed ? { x: (r.x / 100) * page.w, y: (r.y / 100) * page.h, w: (r.w / 100) * page.w, h: (r.h / 100) * page.h }
        : { x: scrollX + Math.max(0, innerWidth / 2 - 80), y: scrollY + Math.max(0, innerHeight / 2 - 50), w: 160, h: 100 };
      if (region && seed) { reveal(region.y + region.h); reveal(region.y); }
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
      else {
        const r = range.getBoundingClientRect();
        post({ type: "selected", rect: pct(r), anchor: anchorOf(el), quote, snapshot: snapshot(el) });
        hold({ left: r.left + scrollX, top: r.top + scrollY, width: r.width, height: r.height });
      }
    }
    else if (m.type === "release") { held = null; draw(); }
    else if (m.type === "pins" && Array.isArray(m.pins)) { pins = m.pins.slice(0, 500); draw(); }
    else if (m.type === "clear-arrow") { arrow = null; draw(); }
    else if (m.type === "markers") { markers = m.on !== false; markerClicks = m.clicks === true; draw(); }
    else if (m.type === "show") { hovered = m.target && typeof m.target === "object" ? m.target : null; draw(); }
    else if (m.type === "select") {
      selected = m.target && typeof m.target === "object" && !mode ? m.target : null;
      if (selected) {
        const detail = {};
        for (const k of ["variant", "state", "content"]) if (typeof selected[k] === "string") detail[k] = selected[k];
        document.dispatchEvent(new CustomEvent("vs:show", { detail }));
        const b = noteBox(selected);
        post({ type: "shown", n: selected.n, found: !!b });
        const behavior = matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth";
        if (b) scrollTo({ top: Math.max(0, b.top + scrollY - innerHeight / 3), behavior });
      }
      draw();
    }
    else if (m.type === "view") {
      const detail = {};
      for (const k of ["variant", "state"]) if (typeof m[k] === "string") detail[k] = m[k];
      document.dispatchEvent(new CustomEvent("vs:show", { detail }));
    }
    else if (m.type === "bar") root.setAttribute("data-ui-feedback-bar", "");
    else if (m.type === "name") names(m.targets);
    else if (m.type === "set") setControls(m.values);
    else if (m.type === "press" && !mode) replay([m.step]);
    else if (m.type === "focus") {
      const p = pins.find(x => x.n === m.n);
      if (!p) return;
      const at = placeOf(p), behavior = matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth";
      if (at.el) at.el.scrollIntoView({ block: "center", behavior });
      else scrollTo({ top: Math.max(0, at.y - innerHeight / 3), behavior });
    }
  });
  const marks = [...document.querySelectorAll("[data-data-control]")].map(stepOf).filter(Boolean);
  post({
    type: "ready",
    controls: window.uiFeedbackControls?.manifest() ?? null,
    data: [...new Map(marks.map(m => [JSON.stringify(m), m])).values()],
    content: document.querySelector('[data-content-set="demo"]') && document.querySelector('[data-content-set="worst"]') ? root.dataset.vsContent || null : null,
  });
  postView();
})();
