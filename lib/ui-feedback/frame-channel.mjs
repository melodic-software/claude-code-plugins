/** How long the host page waits for the frame helper's first ready message before it calls the frame blocked. */
export const READY_MS = 10000;

/** Whether message event `e` came from `frameWindow` and, when `origin` is a real-stack dev origin, from that origin; `origin` is null for the sandboxed mockup. */
export function fromFrame(e, frameWindow, origin) {
  if (!e || e.source !== frameWindow) return false;
  return origin === null || e.origin === origin;
}

/**
 * The targetOrigin of every host-to-frame postMessage: the dev origin on a real-stack route, else
 * `mockupTarget`, the target notes_bridge.py writes on the sandboxed mockup's frame tag alone (its
 * srcdoc document has an opaque origin, which only the wildcard target matches). Null when neither
 * is set, and then the host page posts nothing.
 */
export function frameTarget(origin, mockupTarget = null) {
  return origin || mockupTarget || null;
}

/** The most code points a page-derived label or name part keeps, and the most variants or states a view report keeps. */
const TEXT_MAX = 60;
const VIEWS_MAX = 26;
const plain = (s) => (typeof s === "string" ? [...s.replace(/\s+/g, " ").trim()].slice(0, TEXT_MAX).join("") : "");

/**
 * The frame's report of the variants and screen states the page has and which are shown, kept only as plain text: each
 * entry whose key fits `keyPattern` (note.schema.json's key) with its label cut to 60 code points, at most 26 of each,
 * and a current key only when it is listed.
 */
export function viewFrom(m, keyPattern) {
  const key = new RegExp(keyPattern);
  const list = (xs) => (Array.isArray(xs) ? xs : [])
    .filter((x) => x && typeof x === "object" && typeof x.key === "string" && key.test(x.key))
    .slice(0, VIEWS_MAX)
    .map((x) => ({ key: x.key, label: plain(x.label) }));
  const variants = list(m?.variants), states = list(m?.states);
  const current = (xs, k) => (xs.some((x) => x.key === k) ? k : null);
  return { variants, variant: current(variants, m?.variant), states, state: current(states, m?.state) };
}

/** The frame's name parts for listed notes, by the positive integer key the host page asked with: each part plain text cut to 60. */
export function namesFrom(m) {
  const out = new Map();
  for (const x of Array.isArray(m?.names) ? m.names.slice(0, 500) : []) {
    if (!x || typeof x !== "object" || !Number.isInteger(x.k) || x.k < 1) continue;
    out.set(x.k, { text: plain(x.text), card: plain(x.card), toText: plain(x.toText), toCard: plain(x.toCard) });
  }
  return out;
}

/**
 * Calls `onBlocked` unless the returned function is called first, within `ms`. On a frame a CSP
 * blocks, Firefox fires no load event and Chrome fires one
 * (https://bugzilla.mozilla.org/show_bug.cgi?id=1552504), so load cannot show a blocked frame;
 * only the frame helper's ready message shows the page runs.
 */
export function awaitReady(onBlocked, ms = READY_MS, timers = globalThis) {
  let waiting = true;
  const id = timers.setTimeout(() => {
    if (waiting) onBlocked();
    waiting = false;
  }, ms);
  return () => {
    if (waiting) timers.clearTimeout(id);
    waiting = false;
  };
}
