// The runtime's client-only bindings: a choice redraws its example and the theme
// toggle pins or releases the color scheme, both with no network call; and it keeps
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
