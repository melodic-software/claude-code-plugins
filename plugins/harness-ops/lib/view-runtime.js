// GENERATED from lib/view-runtime.js by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// Client runtime for pages view-builder.mjs builds. The builder inlines this
// file into each interactive page and pins it in the page's content security
// policy by SHA-256, so any change here changes every page's hash.
//
// Rules this file keeps (rendered-views README, interactive validator profile):
// - It reads the data block only through JSON.parse of its text.
// - Data reaches the page only through textContent. No data value is ever
//   written to an attribute, a URL, a selector, or a form control's value.
// - Every id the runtime assigns is built from a template key and a list
//   position, never from data, so a copied payload carries no data text.
// - Payloads hold the reader's own input and those ids, nothing else.
// - No storage. The one URL it makes is a blob: URL for a download.
// - Network only on a page built with --connect: its policy names one
//   session-bridge origin (http://127.0.0.1:<port>), and the runtime talks to
//   that origin and no other: the token, page actions, and the session's state.
//   The token is fetched, never in the markup, so a saved copy holds none.
// - It names no window globals an element id could shadow.
// - The file holds no HTML comment opener and no script tag text in any case,
//   so it cannot move the end of the element it is inlined into.
(() => {
  "use strict";

  const KEY = /^[a-z0-9-]{1,32}$/;
  const ROW_ID = /^[a-z0-9-]{1,128}$/;
  // Data never pre-fills a form control, so a payload holds only what the reader entered,
  // and never becomes CSS, metadata, or code.
  const UNBOUND = new Set(["input", "textarea", "select", "option", "html", "head", "title", "meta", "style", "script"]);
  const rowsByKey = new Map();

  const readData = () => {
    const block = document.getElementById("rv-data");
    if (!block) {
      return {};
    }
    try {
      return JSON.parse(block.textContent);
    } catch {
      return {};
    }
  };

  const own = (scope, key) =>
    scope !== null && typeof scope === "object" && KEY.test(key) && Object.hasOwn(scope, key)
      ? scope[key]
      : undefined;

  const asText = (value) =>
    ["string", "number", "boolean"].includes(typeof value) ? String(value) : null;

  // root and the elements under it that match selector and whose nearest
  // list container is eachRoot. A nested list's rows bind against their own item.
  const scoped = (root, selector, eachRoot) => {
    const all = [...root.querySelectorAll(selector)];
    if (root.matches(selector)) {
      all.unshift(root);
    }
    return all.filter((el) => (el.parentElement?.closest("[data-rv-each]") ?? null) === eachRoot);
  };

  const bindText = (root, scope, eachRoot) => {
    for (const el of scoped(root, "[data-rv-text]", eachRoot)) {
      if (UNBOUND.has(el.localName)) {
        continue;
      }
      const text =
        scope !== null && typeof scope === "object"
          ? asText(own(scope, el.getAttribute("data-rv-text")))
          : asText(scope);
      if (text !== null) {
        el.textContent = text;
      }
    }
    for (const el of scoped(root, "[data-rv-count]", eachRoot)) {
      if (UNBOUND.has(el.localName)) {
        continue;
      }
      const list = own(scope, el.getAttribute("data-rv-count"));
      el.textContent = Array.isArray(list) ? String(list.length) : "0";
    }
  };

  const bindLists = (root, scope, eachRoot, rowId) => {
    for (const container of scoped(root, "[data-rv-each]", eachRoot)) {
      const key = container.getAttribute("data-rv-each");
      const proto = container.firstElementChild;
      if (container === root || !proto || !KEY.test(key) || UNBOUND.has(container.localName)) {
        continue;
      }
      container.removeChild(proto);
      const items = own(scope, key);
      if (!Array.isArray(items)) {
        continue;
      }
      const prefix = rowId ? `${rowId}-${key}` : key;
      const rows = rowsByKey.get(key) ?? [];
      rowsByKey.set(key, rows);
      items.forEach((item, n) => {
        const row = proto.cloneNode(true);
        const id = `${prefix}-${n + 1}`;
        row.id = id;
        container.appendChild(row);
        bind(row, item, container, id);
        for (const pick of scoped(row, "input[data-rv-pick]", container)) {
          pick.value = id;
        }
        rows.push(row);
      });
    }
  };

  const bind = (root, scope, eachRoot, rowId) => {
    bindLists(root, scope, eachRoot, rowId);
    bindText(root, scope, eachRoot);
  };

  const filter = (input) => {
    const query = input.value.trim().toLowerCase();
    for (const row of rowsByKey.get(input.getAttribute("data-rv-filter")) ?? []) {
      row.hidden = query !== "" && !row.textContent.toLowerCase().includes(query);
    }
  };

  // The reader's input: picked row ids, chosen option keys, typed notes.
  const collect = () => {
    const picked = [...document.querySelectorAll("input[data-rv-pick]")]
      .filter((pick) => pick.checked && ROW_ID.test(pick.value))
      .map((pick) => pick.value);
    const choices = {};
    for (const select of document.querySelectorAll("select[data-rv-choice]")) {
      const key = select.getAttribute("data-rv-choice");
      if (KEY.test(key) && KEY.test(select.value)) {
        choices[key] = select.value;
      }
    }
    const notes = {};
    for (const note of document.querySelectorAll("textarea[data-rv-note]")) {
      const key = note.getAttribute("data-rv-note");
      if (KEY.test(key) && note.value.trim() !== "") {
        notes[key] = note.value.trim();
      }
    }
    return { picked, choices, notes };
  };

  const payload = (label) => {
    const { picked, choices, notes } = collect();
    const lines = [label, `picked: ${picked.length ? picked.join(" ") : "none"}`];
    for (const [key, value] of Object.entries({ ...choices, ...notes })) {
      lines.push(`${key}: ${value}`);
    }
    return lines.join("\n");
  };

  const status = (text) => {
    for (const el of document.querySelectorAll("[data-rv-status]")) {
      el.textContent = text;
    }
  };

  const showPayload = (text) => {
    for (const el of document.querySelectorAll("[data-rv-out]")) {
      el.textContent = text;
      el.hidden = false;
    }
  };

  const copy = (button) => {
    const text = payload(button.getAttribute("data-rv-copy"));
    showPayload(text);
    try {
      navigator.clipboard.writeText(text).then(
        () => status("Copied. Paste it back into the session."),
        () => status("Copy was refused. Select the text below and copy it."),
      );
    } catch {
      status("Copy is not available here. Select the text below and copy it.");
    }
  };

  const download = (button) => {
    const text = payload(button.getAttribute("data-rv-download"));
    showPayload(text);
    try {
      const url = URL.createObjectURL(new Blob([text], { type: "text/plain" }));
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = `${button.getAttribute("data-rv-download")}.txt`;
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      URL.revokeObjectURL(url);
      status("If no file was saved, select the text below and copy it.");
    } catch {
      status("Saving is not available here. Select the text below and copy it.");
    }
  };

  // ------------------------------------------------ session-bridge client
  const BRIDGE = /(?:^|; )connect-src (http:\/\/127\.0\.0\.1:[0-9]{1,5})$/;
  const LISTENING = {
    listening: "Claude is listening. What you send reaches the session as data for it to weigh.",
    reading: "Claude is reading what you sent.",
    idle: "The session is not listening right now. What you send waits for it.",
  };
  const OFFLINE = "No session is connected. Copy your reply and paste it into the session.";
  const session = { origin: null, token: null };

  const sessionStatus = (text) => {
    for (const el of document.querySelectorAll("[data-rv-session]")) {
      el.textContent = text;
    }
  };

  // The origin the builder wrote into this page's policy, or null for a page built without one.
  const bridgeOrigin = () => {
    const meta = document.querySelector("meta[http-equiv=Content-Security-Policy]");
    return BRIDGE.exec(meta?.getAttribute("content") ?? "")?.[1] ?? null;
  };

  const showReplies = (events) => {
    for (const list of document.querySelectorAll("[data-rv-replies]")) {
      const items = (Array.isArray(events) ? events : []).map((event) => {
        const item = document.createElement("li");
        const reply = asText(event?.reply);
        const progress = event?.handled ? "handled" : event?.delivered ? "delivered, no reply yet" : "waiting for the session";
        item.textContent = `${asText(event?.seq) ?? "?"} ${asText(event?.action) ?? ""}: ${reply ?? progress}`;
        return item;
      });
      list.replaceChildren(...items);
    }
  };

  const listen = (origin) => {
    const source = new EventSource(`${origin}/events`);
    source.addEventListener("state", (event) => {
      let state;
      try {
        state = JSON.parse(event.data);
      } catch {
        return;
      }
      sessionStatus(LISTENING[state?.listening] ?? LISTENING.idle);
      showReplies(state?.events);
    });
    source.addEventListener("error", () => sessionStatus(OFFLINE));
  };

  // The page says it is offline until the bridge answers, so it never claims a session it lacks.
  const connect = () => {
    sessionStatus(OFFLINE);
    const origin = bridgeOrigin();
    if (!origin) {
      return;
    }
    fetch(`${origin}/api/token`, { cache: "no-store", credentials: "omit" })
      .then((response) => (response.ok ? response.json() : null))
      .then((body) => {
        if (typeof body?.token !== "string") {
          throw new Error("no token");
        }
        session.origin = origin;
        session.token = body.token;
        listen(origin);
      })
      .catch(() => sessionStatus(OFFLINE));
  };

  const send = (button) => {
    const action = button.getAttribute("data-rv-send");
    if (!session.token) {
      showPayload(payload(action));
      status(OFFLINE);
      return;
    }
    fetch(`${session.origin}/api/action`, {
      method: "POST",
      cache: "no-store",
      credentials: "omit",
      headers: { "Content-Type": "application/json", "X-View-Token": session.token },
      body: JSON.stringify({ action, ...collect() }),
    })
      .then((response) => status(response.ok ? "Sent to the session." : "The session refused it. Copy your reply instead."))
      .catch(() => status("Could not reach the session. Copy your reply instead."));
  };

  // A host that blocks a page's own download, such as the claude.ai artifact viewer, raises no
  // error and fires no event, so the page cannot tell whether a file was saved. The button stays
  // only where an anchor download is known to work: a file opened from disk, the session bridge
  // on 127.0.0.1, and a page served top-level over https (a page host whose policy allows
  // downloads). A framed page is inside some other host's document, so it loses the button.
  // Anywhere else it is removed, not hidden, so no template rule shows it.
  const canDownload = (url, isTop) => {
    const { protocol, hostname } = new URL(url);
    return protocol === "file:" || hostname === "127.0.0.1" || (protocol === "https:" && isTop);
  };

  const start = () => {
    bind(document.body, readData(), null, "");
    if (!canDownload(document.URL, top === self)) {
      for (const button of document.querySelectorAll("button[data-rv-download]")) {
        button.remove();
      }
    }
    if (document.querySelector("[data-rv-session]")) {
      connect();
    }
    document.addEventListener("input", (event) => {
      if (event.target.matches?.("input[data-rv-filter]")) {
        filter(event.target);
      }
    });
    document.addEventListener("click", (event) => {
      const button = event.target.closest?.("button");
      if (button?.hasAttribute("data-rv-copy")) {
        copy(button);
      } else if (button?.hasAttribute("data-rv-download")) {
        download(button);
      } else if (button?.hasAttribute("data-rv-send")) {
        send(button);
      }
    });
    document.documentElement.classList.add("rv-ready");
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();
