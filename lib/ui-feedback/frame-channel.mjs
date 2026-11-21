/** How long the host page waits for the frame helper's first ready message before it calls the frame blocked. */
export const READY_MS = 10000;

/** Whether message event `e` came from `frameWindow` and, when `origin` is a real-stack dev origin, from that origin; `origin` is null for the sandboxed mockup. */
export function fromFrame(e, frameWindow, origin) {
  if (!e || e.source !== frameWindow) return false;
  return origin === null || e.origin === origin;
}

/** The targetOrigin of every host-to-frame postMessage: the dev origin, or for the sandboxed mockup, whose srcdoc document has an opaque origin, "*", the one target an opaque origin matches. */
export function frameTarget(origin) {
  return origin === null ? "*" : origin;
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
