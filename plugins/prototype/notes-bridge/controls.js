// GENERATED from lib/ui-feedback/controls.js by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// The controls runtime for a non-final page (docs/contracts/ui-feedback, "Controls"). One registry maps each control type
// of controls.schema.json to its renderer and its value reader; the page's manifest, the JSON in its script element of
// type application/json with id prototype-controls, is the one list of what can vary. A page inlines this file
// whole: opened alone it draws its own panel top-right, and framed by the notes host page it draws nothing, since the
// host page renders the same registry in its Controls tab and the frame helper (proto-pin.js) sets values here. Every
// string a control shows reaches the screen through textContent or a form field's value, never as markup.
(() => {
  if (window.uiFeedbackControls) return;
  const el = (doc, tag, props = {}) => Object.assign(doc.createElement(tag), props);
  const field = (doc, c, type, value) => el(doc, "input", { type, value, id: c.dom, name: c.dom });
  /** Each type: `render(doc, c, value)` builds the field, `read(field)` gives its value as a string, and `out(c, value)`
   *  what the page receives. A toggle's value is its first option off, its second on. */
  const TYPES = {
    range: {
      render: (doc, c, v) => Object.assign(field(doc, c, "range", ""), { min: c.min ?? 0, max: c.max ?? 100, step: c.step || "any", value: v }),
      read: f => f.value,
      out: (c, v) => v + (c.unit || ""),
    },
    color: { render: (doc, c, v) => field(doc, c, "color", v), read: f => f.value },
    select: {
      render: (doc, c, v) => {
        const s = el(doc, "select", { id: c.dom, name: c.dom });
        for (const o of c.options || []) s.append(el(doc, "option", { value: o, textContent: o }));
        s.value = v;
        return s;
      },
      read: f => f.value,
    },
    toggle: {
      render: (doc, c, v) => Object.assign(field(doc, c, "checkbox", ""), { checked: v === c.options?.[1] }),
      read: (f, c) => c.options?.[f.checked ? 1 : 0] ?? "",
    },
    radio: {
      render: (doc, c, v) => {
        const g = el(doc, "span", { role: "radiogroup", id: c.dom });
        g.setAttribute("aria-labelledby", `${c.dom}-label`);
        for (const o of c.options || []) {
          const l = el(doc, "label");
          l.append(el(doc, "input", { type: "radio", name: c.dom, value: o, checked: o === v }), ` ${o} `);
          g.append(l);
        }
        return g;
      },
      read: f => f.querySelector("input:checked")?.value ?? "",
    },
    // Built in: a press of a data control or the content-set flip, made by the host page from the page's own marks.
    action: { render: (doc, c) => el(doc, "button", { type: "button", id: c.dom, textContent: c.label }), read: () => "" },
  };
  const shown = (c, v) => (TYPES[c.type]?.out ? TYPES[c.type].out(c, v) : v);

  /** The page's manifest, or null when it has none or it is not JSON. */
  function manifest(doc = document) {
    const s = doc.getElementById("prototype-controls");
    try { return s ? JSON.parse(s.textContent) : null; } catch { return null; }
  }
  const entries = (doc = document) => (Array.isArray(manifest(doc)?.controls) ? manifest(doc).controls.filter(c => TYPES[c?.type] && c.type !== "action") : []);
  const defaults = list => Object.fromEntries(list.filter(c => c.type !== "action").map(c => [c.id, String(c.default ?? "")]));

  /** The rows for `list`, grouped in manifest order, each with its field and its shown value; `change(c, value)` runs
   *  on every input. */
  function panel(doc, list, values, change) {
    const box = el(doc, "div");
    const groups = new Map();
    list.forEach((c, i) => {
      c = { ...c, dom: `uifc-${i}` };
      if (!groups.has(c.group)) {
        const fs = el(doc, "fieldset");
        fs.append(el(doc, "legend", { textContent: c.group }));
        groups.set(c.group, fs);
        box.append(fs);
      }
      const row = el(doc, "div", { className: "uifc-row" });
      const f = TYPES[c.type].render(doc, c, values[c.id] ?? String(c.default ?? ""));
      if (c.type === "action") {
        f.addEventListener("click", () => change(c, ""));
        row.append(f);
      } else {
        const label = el(doc, c.type === "radio" ? "span" : "label", { id: `${c.dom}-label`, textContent: c.variant ? `${c.label} (variant ${c.variant})` : c.label });
        if (c.type !== "radio") label.htmlFor = c.dom;
        const out = el(doc, "output", { textContent: shown(c, values[c.id] ?? String(c.default ?? "")) });
        out.htmlFor = c.dom;
        f.addEventListener("input", () => { const v = TYPES[c.type].read(f, c); out.textContent = shown(c, v); change(c, v); });
        row.append(label, " ", f, " ", out);
      }
      groups.get(c.group).append(row);
    });
    return box;
  }
  /** One line a person can paste: each control's id and the value the page receives. */
  const config = (list, values) => list.filter(c => c.type !== "action").map(c => `${c.id}: ${shown(c, values[c.id] ?? "")}`).join(" · ");

  // The page side: the values set so far, written to each control's target.
  let values = null;
  const now = () => (values ??= defaults(entries()));
  function write(c, v) {
    const root = document.documentElement;
    const at = c.variant ? [...document.querySelectorAll("[data-variant]")].find(e => e.dataset.variant === c.variant) : root;
    if (!at || typeof c.target !== "string") return;
    const out = shown(c, v);
    if (c.target.startsWith("--")) at.style.setProperty(c.target, out);
    else if (c.target.startsWith("data-control-")) at.setAttribute(c.target, out);
  }
  /** Set the controls `next` names, as {id: value}; returns how many ids the manifest has no control for. */
  function set(next) {
    const byId = new Map(entries().map(c => [c.id, c]));
    let missed = 0;
    for (const [id, v] of Object.entries(next || {})) {
      const c = byId.get(id);
      if (!c || typeof v !== "string") { missed++; continue; }
      now()[id] = v;
      write(c, v);
    }
    return missed;
  }
  const reset = () => set(defaults(entries()));

  /** Opened alone: the page's own panel, top-right, harness chrome like the switcher. */
  function mount() {
    const list = entries();
    if (window.parent !== window || !list.length) return;
    const aside = el(document, "aside");
    aside.setAttribute("aria-label", "Controls");
    aside.setAttribute("data-harness-chrome", "");
    Object.assign(aside.style, {
      position: "fixed", top: "12px", right: "12px", zIndex: "2147483646", maxHeight: "80vh", overflow: "auto", padding: "8px 12px",
      background: "rgb(24 24 27 / 0.92)", color: "#fafafa", font: "12px/1.5 system-ui, sans-serif", borderRadius: "8px",
    });
    let rows = panel(document, list, now(), (c, v) => set({ [c.id]: v }));
    const copy = el(document, "button", { type: "button", textContent: "Copy config" });
    const again = el(document, "button", { type: "button", textContent: "Reset controls" });
    const text = el(document, "output");
    copy.addEventListener("click", () => {
      text.textContent = config(list, now());
      navigator.clipboard?.writeText(text.textContent).catch(() => {});
    });
    again.addEventListener("click", () => {
      reset();
      const fresh = panel(document, list, now(), (c, v) => set({ [c.id]: v }));
      rows.replaceWith(fresh);
      rows = fresh;
    });
    const bar = el(document, "p");
    bar.append(copy, " ", again);
    aside.append(rows, bar, text);
    document.body.append(aside);
  }
  // A value the host page set before the page finished loading stays.
  function start() { if (!values) reset(); mount(); }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();

  Object.defineProperty(window, "uiFeedbackControls", {
    value: Object.freeze({ TYPES, manifest, panel, config, defaults, set, reset, values: () => ({ ...now() }) }),
  });
})();
