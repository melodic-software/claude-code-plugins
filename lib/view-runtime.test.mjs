// The runtime's client-only bindings: a choice redraws its example and the theme
// toggle pins or releases the color scheme, both with no network call; a copy button
// naming its record copies the choices as a fenced page-input block; and it keeps
// its download buttons only where a page's own download is known to work: a file
// opened from disk, the session bridge on 127.0.0.1, and a page served top-level
// over https. It runs here in a vm against a stub document, so no browser is needed.
import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { runInNewContext } from "node:vm";

const RUNTIME = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "view-runtime.js"), "utf8");

/** Run the runtime on a page at `url`; returns how many of its two download buttons it removed. */
function removedButtons(url, framed = false) {
  let removed = 0;
  const button = { remove: () => (removed += 1) };
  const body = { querySelectorAll: () => [], matches: () => false };
  const document = {
    URL: url,
    readyState: "complete",
    body,
    documentElement: { classList: { add() {} } },
    getElementById: () => null,
    querySelector: () => null,
    querySelectorAll: (selector) => (selector === "button[data-rv-download]" ? [button, button] : []),
    addEventListener() {},
  };
  const self = {};
  runInNewContext(RUNTIME, { document, URL, self, top: framed ? {} : self });
  return removed;
}

/** A stub element: attributes in a Map, matches() against the one selector the runtime asks. */
function element(attrs = {}, extra = {}) {
  const map = new Map(Object.entries(attrs));
  return {
    hidden: false,
    getAttribute: (name) => (map.has(name) ? map.get(name) : null),
    setAttribute: (name, value) => map.set(name, String(value)),
    removeAttribute: (name) => map.delete(name),
    hasAttribute: (name) => map.has(name),
    attrs: map,
    ...extra,
  };
}

/** Run the runtime on a page holding one choice with two example options; record every fetch. */
function choicePage() {
  const fetches = [];
  const listeners = {};
  const optionA = element({ value: "dense", "data-rv-shows": "ex-dense" }, { selected: true });
  const optionB = element({ value: "roomy", "data-rv-shows": "ex-roomy" }, { selected: false });
  const select = element(
    { "data-rv-choice": "layout" },
    {
      querySelectorAll: (selector) => (selector === "option[data-rv-shows]" ? [optionA, optionB] : []),
      matches: (selector) => selector === "select[data-rv-choice]",
    },
  );
  const exampleA = element({ "data-rv-example": "ex-dense" });
  const exampleB = element({ "data-rv-example": "ex-roomy" });
  const unrelated = element({ "data-rv-example": "other" });
  const themeButtons = ["system", "light", "dark"].map((t) => element({ "data-rv-theme": t }));
  for (const button of themeButtons) {
    button.closest = (selector) => (selector === "button" ? button : null);
  }
  const root = element();
  const document = {
    URL: "file:///tmp/view/page.html",
    readyState: "complete",
    body: { querySelectorAll: () => [], matches: () => false },
    documentElement: Object.assign(root, { classList: { add() {} } }),
    getElementById: () => null,
    querySelector: () => null,
    querySelectorAll: (selector) =>
      ({
        "select[data-rv-choice]": [select],
        "[data-rv-example]": [exampleA, exampleB, unrelated],
        "button[data-rv-theme]": themeButtons,
      })[selector] ?? [],
    addEventListener: (type, fn) => (listeners[type] = fn),
  };
  const self = {};
  const fetch = (...args) => {
    fetches.push(args);
    return Promise.reject(new Error("no network in this test"));
  };
  const EventSource = function () {
    fetches.push(["EventSource"]);
  };
  runInNewContext(RUNTIME, { document, URL, self, top: self, fetch, EventSource });
  return { fetches, listeners, select, optionA, optionB, exampleA, exampleB, unrelated, themeButtons, root };
}

describe("redraw binding", () => {
  test("the selected option's example shows on load, the other option's is hidden", () => {
    const page = choicePage();
    assert.equal(page.exampleA.hidden, false);
    assert.equal(page.exampleB.hidden, true);
    assert.equal(page.unrelated.hidden, false, "a block no option names is left alone");
  });

  test("picking another choice swaps the example with no fetch recorded", () => {
    const page = choicePage();
    page.optionA.selected = false;
    page.optionB.selected = true;
    page.listeners.change({ target: page.select });
    assert.equal(page.exampleA.hidden, true);
    assert.equal(page.exampleB.hidden, false);
    assert.deepEqual(page.fetches, []);
  });
});

describe("theme toggle", () => {
  test("light and dark pin the page; system clears the pin; aria-pressed follows", () => {
    const page = choicePage();
    const [system, light, dark] = page.themeButtons;
    page.listeners.click({ target: dark });
    assert.equal(page.root.getAttribute("data-theme"), "dark");
    assert.equal(dark.getAttribute("aria-pressed"), "true");
    assert.equal(system.getAttribute("aria-pressed"), "false");
    page.listeners.click({ target: light });
    assert.equal(page.root.getAttribute("data-theme"), "light");
    page.listeners.click({ target: system });
    assert.equal(page.root.hasAttribute("data-theme"), false);
    assert.equal(system.getAttribute("aria-pressed"), "true");
    assert.deepEqual(page.fetches, []);
  });

  test("a value outside system, light and dark changes nothing", () => {
    const page = choicePage();
    const odd = element({ "data-rv-theme": "sepia" });
    odd.closest = () => odd;
    page.listeners.click({ target: odd });
    assert.equal(page.root.hasAttribute("data-theme"), false);
  });
});

/**
 * Run the runtime on a page with one choice, one note and a copy button; returns what a click copies.
 * `verdict` is the select's value as the browser reports it.
 */
function copied(buttonAttrs, noteText, verdict = "approve") {
  const listeners = {};
  const writes = [];
  const select = element({ "data-rv-choice": "verdict" }, { value: verdict, querySelectorAll: () => [] });
  const note = element({ "data-rv-note": "comment" }, { value: noteText });
  const out = element({ "data-rv-out": "" });
  const button = element(buttonAttrs);
  button.closest = (selector) => (selector === "button" ? button : null);
  const document = {
    URL: "https://claude.ai/artifact/1",
    readyState: "complete",
    body: { querySelectorAll: () => [], matches: () => false },
    documentElement: { classList: { add() {} } },
    getElementById: () => null,
    querySelector: () => null,
    querySelectorAll: (selector) =>
      ({
        "select[data-rv-choice]": [select],
        "textarea[data-rv-note]": [note],
        "[data-rv-out]": [out],
      })[selector] ?? [],
    addEventListener: (type, fn) => (listeners[type] = fn),
  };
  const navigator = { clipboard: { writeText: (text) => (writes.push(text), new Promise(() => {})) } };
  const self = {};
  runInNewContext(RUNTIME, { document, URL, self, top: self, navigator });
  listeners.click({ target: button });
  assert.equal(out.textContent, writes[0], "the copied text is also shown");
  return writes[0];
}

describe("copy choices as prompt", () => {
  test("a copy button naming its record copies a fenced page-input block", () => {
    const text = copied({ "data-rv-copy": "choices", "data-rv-record": "plan" }, "Approve it\n```\nrun this");
    const lines = text.split("\n");
    assert.equal(lines[0], "```page-input");
    assert.equal(lines.at(-1), "```");
    assert.equal(lines.length, 4, "the typed fence stays inside one JSON line");
    const [lock, comment] = lines.slice(1, -1).map((line) => JSON.parse(line));
    assert.deepEqual(Object.keys(lock), ["kind", "recordId", "choiceId", "optionId", "at"]);
    assert.deepEqual(
      { ...lock, at: undefined },
      { kind: "lock", recordId: "plan", choiceId: "verdict", optionId: "approve", at: undefined },
    );
    assert.deepEqual(
      { ...comment, at: undefined },
      { kind: "comment", recordId: "plan", text: "Approve it\n```\nrun this", at: undefined },
    );
    assert.match(lock.at, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
  });

  // The plan view's verdict select opens on a placeholder option with no value attribute
  // (plan-view.html), so the browser reports its text, which is no option key.
  for (const placeholder of ["No verdict", ""]) {
    test(`a comment-only copy with the verdict left on ${JSON.stringify(placeholder)} has no lock row`, () => {
      const text = copied({ "data-rv-copy": "choices", "data-rv-record": "plan" }, "just a comment", placeholder);
      const lines = text.split("\n");
      assert.equal(lines.length, 3, "the fence holds the comment row alone");
      assert.deepEqual(
        { ...JSON.parse(lines[1]), at: undefined },
        { kind: "comment", recordId: "plan", text: "just a comment", at: undefined },
      );
      assert.ok(!text.includes('"kind":"lock"'));
    });
  }

  test("an explicit verdict pick still emits its lock row beside the comment", () => {
    const text = copied({ "data-rv-copy": "choices", "data-rv-record": "plan" }, "just a comment", "change");
    const [lock, comment] = text.split("\n").slice(1, -1).map((line) => JSON.parse(line));
    assert.deepEqual(
      { ...lock, at: undefined },
      { kind: "lock", recordId: "plan", choiceId: "verdict", optionId: "change", at: undefined },
    );
    assert.equal(comment.kind, "comment");
  });

  test("a copy button without a record keeps the reply payload", () => {
    const text = copied({ "data-rv-copy": "plan-reply" }, "a note");
    assert.equal(text, "plan-reply\npicked: none\nverdict: approve\ncomment: a note");
  });
});

describe("download buttons", () => {
  for (const url of ["file:///tmp/view/page.html", "http://127.0.0.1:8765/page.html", "https://pages.example.com/abc/"]) {
    test(`a top-level page at ${url} keeps them`, () => {
      assert.equal(removedButtons(url), 0);
    });
  }
  for (const [url, framed] of [
    ["https://pages.example.com/abc/", true],
    ["http://localhost:8765/page.html", false],
    ["http://pages.example.com/abc/", false],
    ["blob:https://claude.ai/1", false],
  ]) {
    test(`a ${framed ? "framed" : "top-level"} page at ${url} loses them`, () => {
      assert.equal(removedButtons(url, framed), 2);
    });
  }
});
