(() => {
  "use strict";

  const KEY = /^[a-z0-9-]{1,32}$/;
  const ROW_ID = /^[a-z0-9-]{1,128}$/;
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

  const inputBlock = (recordId) => {
    const at = new Date().toISOString();
    const { choices, notes } = collect();
    const lines = [
      ...Object.entries(choices).map(([choiceId, optionId]) => ({ kind: "lock", recordId, choiceId, optionId, at })),
      ...Object.values(notes).map((text) => ({ kind: "comment", recordId, text, at })),
    ].map((entry) => JSON.stringify(entry));
    return ["```page-input", ...lines, "```"].join("\n");
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
    const record = button.getAttribute("data-rv-record");
    const text = record !== null && KEY.test(record) ? inputBlock(record) : payload(button.getAttribute("data-rv-copy"));
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

  const THEMES = new Set(["system", "light", "dark"]);

  const setTheme = (choice) => {
    if (!THEMES.has(choice)) {
      return;
    }
    if (choice === "system") {
      document.documentElement.removeAttribute("data-theme");
    } else {
      document.documentElement.setAttribute("data-theme", choice);
    }
    for (const button of document.querySelectorAll("button[data-rv-theme]")) {
      button.setAttribute("aria-pressed", String(button.getAttribute("data-rv-theme") === choice));
    }
  };

  const redraw = (select) => {
    const named = new Set();
    const shown = new Set();
    for (const option of select.querySelectorAll("option[data-rv-shows]")) {
      const key = option.getAttribute("data-rv-shows");
      if (KEY.test(key)) {
        named.add(key);
        if (option.selected) {
          shown.add(key);
        }
      }
    }
    for (const block of document.querySelectorAll("[data-rv-example]")) {
      const key = block.getAttribute("data-rv-example");
      if (named.has(key)) {
        block.hidden = !shown.has(key);
      }
    }
  };

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
    for (const select of document.querySelectorAll("select[data-rv-choice]")) {
      redraw(select);
    }
    document.addEventListener("input", (event) => {
      if (event.target.matches?.("input[data-rv-filter]")) {
        filter(event.target);
      }
    });
    document.addEventListener("change", (event) => {
      if (event.target.matches?.("select[data-rv-choice]")) {
        redraw(event.target);
      }
    });
    document.addEventListener("click", (event) => {
      const button = event.target.closest?.("button");
      if (button?.hasAttribute("data-rv-theme")) {
        setTheme(button.getAttribute("data-rv-theme"));
      } else if (button?.hasAttribute("data-rv-copy")) {
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
