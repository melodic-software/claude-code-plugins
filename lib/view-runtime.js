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
// - No storage, no network. The one URL it makes is a blob: URL for a download.
// - It names no window globals an element id could shadow.
// - The file holds no HTML comment opener and no script tag text in any case,
//   so it cannot move the end of the element it is inlined into.
(() => {
  "use strict";

  const KEY = /^[a-z0-9-]{1,32}$/;
  const ROW_ID = /^[a-z0-9-]{1,128}$/;
  // Data never pre-fills a form control, so a payload holds only what the reader entered.
  const CONTROLS = new Set(["INPUT", "TEXTAREA", "SELECT", "OPTION"]);
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
      if (CONTROLS.has(el.tagName)) {
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
      const list = own(scope, el.getAttribute("data-rv-count"));
      el.textContent = Array.isArray(list) ? String(list.length) : "0";
    }
  };

  const bindLists = (root, scope, eachRoot, rowId) => {
    for (const container of scoped(root, "[data-rv-each]", eachRoot)) {
      const key = container.getAttribute("data-rv-each");
      const proto = container.firstElementChild;
      if (container === root || !proto || !KEY.test(key)) {
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

  const payload = (label) => {
    const picked = [...document.querySelectorAll("input[data-rv-pick]")]
      .filter((pick) => pick.checked && ROW_ID.test(pick.value))
      .map((pick) => pick.value);
    const lines = [label, `picked: ${picked.length ? picked.join(" ") : "none"}`];
    for (const note of document.querySelectorAll("textarea[data-rv-note]")) {
      if (note.value.trim() !== "") {
        lines.push(`${note.getAttribute("data-rv-note")}: ${note.value.trim()}`);
      }
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
      status("Saved the file. Where saving is blocked, copy the text below.");
    } catch {
      status("Saving is not available here. Select the text below and copy it.");
    }
  };

  const start = () => {
    bind(document.body, readData(), null, "");
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
