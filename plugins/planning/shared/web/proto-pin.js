// Pin helper for an html prototype variant. server.py appends it as an inline script when the prototype page frames
// /assets/<id>.html?pin=1. It runs inside the variant's sandbox (scripts, no same origin), so it can reach nothing but
// the variant and its parent window. It answers the prototype page (proto.js) by postMessage only: an element's path
// and box when the person pins one, never the page's markup. proto.js checks every message it sends back.
(() => {
  if (window.parent === window) return;
  const root = document.documentElement;
  const post = m => window.parent.postMessage(m, "*"); // the sandbox has no origin the parent could name
  const TAG = /^[a-z][a-z0-9]{0,15}(?:-[a-z0-9]{1,15}){0,3}$/;
  const MAX_DEPTH = 32;
  let mode = false, pins = [], layer = null, hover = null;

  /** The reference box notes are measured in: the whole scrollable page. */
  const box = () => ({ w: Math.max(root.scrollWidth, 1), h: Math.max(root.scrollHeight, 1) });
  /** The element's path from the root, one step per level with its place among same-tag siblings. A step whose tag
   *  the server would refuse (an SVG camelCase name, say) ends the path there, so the note pins that ancestor. */
  function pathOf(el) {
    const chain = [];
    for (let e = el; e && e.nodeType === 1; e = e.parentElement) chain.unshift(e);
    const steps = [];
    for (const e of chain.slice(0, MAX_DEPTH)) {
      const tag = e.localName;
      if (!TAG.test(tag)) break;
      let n = 1;
      for (let s = e.previousElementSibling; s; s = s.previousElementSibling) if (s.localName === tag) n++;
      steps.push(e === root ? tag : `${tag}:nth-of-type(${n})`);
    }
    return { path: steps.join(" > "), el: chain[steps.length - 1] || root };
  }
  const r2 = n => Math.round(n * 100) / 100;
  /** An element's box in percent of the reference box, inside 0-100 with w and h above 0. */
  function rectOf(el) {
    const b = el.getBoundingClientRect(), page = box();
    const x = Math.min(99.5, Math.max(0, r2(((b.left + scrollX) / page.w) * 100)));
    const y = Math.min(99.5, Math.max(0, r2(((b.top + scrollY) / page.h) * 100)));
    const w = Math.max(0.5, Math.min(100 - x, r2((b.width / page.w) * 100)));
    const h = Math.max(0.5, Math.min(100 - y, r2((b.height / page.h) * 100)));
    return { x, y, w: r2(w), h: r2(h) };
  }
  const label = el => (el.getAttribute("aria-label") || el.getAttribute("alt") || el.textContent || "").replace(/\s+/g, " ").trim().slice(0, 60);
  const skip = el => !el || el === layer || layer?.contains(el);

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
    try { el = document.querySelector(p.selector); } catch { el = null; }
    if (el) { const b = el.getBoundingClientRect(); return { el, x: b.left + scrollX, y: b.top + scrollY }; }
    const page = box();
    return { el: null, x: (p.rect.x / 100) * page.w, y: (p.rect.y / 100) * page.h };
  }
  function draw() {
    const l = ensureLayer();
    l.replaceChildren();
    for (const p of pins) { const at = placeOf(p); l.append(badge(p.n, at.x, at.y, p.active)); }
    if (hover && mode) {
      const b = hover.getBoundingClientRect(), o = document.createElement("div");
      Object.assign(o.style, { position: "absolute", left: `${b.left + scrollX}px`, top: `${b.top + scrollY}px`, width: `${b.width}px`, height: `${b.height}px`,
        outline: "2px dashed #0d9488", outlineOffset: "1px", background: "rgb(13 148 136 / 0.08)" });
      l.append(o);
    }
  }

  const over = e => { if (!mode || skip(e.target)) return; hover = pathOf(e.target).el; draw(); };
  function pick(e) {
    if (!mode) return;
    e.preventDefault(); e.stopImmediatePropagation();
    if (skip(e.target)) return;
    const { path, el } = pathOf(e.target);
    if (!path) return;
    post({ type: "pinned", selector: path, rect: rectOf(el), label: label(el) });
  }
  const stop = e => { if (mode) { e.preventDefault(); e.stopImmediatePropagation(); } };
  addEventListener("pointermove", over, true);
  addEventListener("click", pick, true);
  for (const t of ["pointerdown", "mousedown", "mouseup", "submit", "auxclick", "dblclick"]) addEventListener(t, stop, true);
  addEventListener("keydown", e => { if (e.key === "Escape") post({ type: "escape" }); }, true);
  addEventListener("resize", draw);
  if (window.ResizeObserver) new ResizeObserver(() => { if (pins.length || mode) draw(); }).observe(root); // late images move elements

  addEventListener("message", e => {
    if (e.source !== window.parent || !e.data || typeof e.data !== "object") return;
    const m = e.data;
    if (m.type === "mode") { mode = !!m.on; hover = null; root.style.cursor = mode ? "crosshair" : ""; draw(); }
    else if (m.type === "pins" && Array.isArray(m.pins)) { pins = m.pins.slice(0, 500); draw(); }
    else if (m.type === "focus") {
      const p = pins.find(x => x.n === m.n);
      if (!p) return;
      const at = placeOf(p), reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
      if (at.el) at.el.scrollIntoView({ block: "center", behavior: reduce ? "auto" : "smooth" });
      else scrollTo({ top: Math.max(0, at.y - innerHeight / 3), behavior: reduce ? "auto" : "smooth" });
    }
  });
  post({ type: "ready" });
})();
