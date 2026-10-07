// Shared helper for fixture pages. Reads ?run, ?delay and ?variant, reports outcomes to the server
// (the grader's source of truth), and mirrors them into #result and window.__fixture.
(() => {
  const q = new URLSearchParams(location.search);
  const run = q.get("run") ?? "none";
  const delay = Number(q.get("delay") ?? 0);
  const variant = q.get("variant") ?? "A";
  const state = {};
  window.__fixture = state;

  // #result mirrors the recorded state for people debugging a fixture. It is hidden from view and
  // from the accessibility tree so it gives an agent no readiness or success signal a real app
  // would not; graders read the server's record instead.
  function show() {
    const el = document.getElementById("result");
    if (!el) return;
    el.hidden = true;
    el.setAttribute("aria-hidden", "true");
    el.textContent = JSON.stringify(state);
  }
  function post(key, value, mode) {
    const body = JSON.stringify({ key, value, mode });
    fetch(`/__record?run=${encodeURIComponent(run)}`, { method: "POST", body, keepalive: true }).catch(() => {});
  }

  window.fx = {
    run,
    delay,
    variant,
    q,
    record(key, value, mode) {
      if (mode === "inc") state[key] = (state[key] ?? 0) + 1;
      else if (mode === "append") (state[key] ??= []).push(value);
      else state[key] = value;
      post(key, value, mode);
      show();
    },
    after(ms, fn) {
      setTimeout(fn, ms);
    },
    async code(purpose) {
      const r = await fetch(`/api/code?run=${encodeURIComponent(run)}&purpose=${purpose}`);
      return (await r.json()).code;
    },
    link(path, extra = "") {
      return `${path}?run=${encodeURIComponent(run)}&delay=${delay}${extra}`;
    },
  };
  document.addEventListener("DOMContentLoaded", show);
})();
