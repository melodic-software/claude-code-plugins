import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const HOST = readFileSync(new URL("./host.html", import.meta.url), "utf8");
const FRAME = readFileSync(new URL("./proto-pin.js", import.meta.url), "utf8");
const start = HOST.indexOf("function shortcut(key)");
const HANDLER = HOST.slice(start, HOST.indexOf("\n  }\n", start));
const ACTIONS = {
  dock: "setPanel(",
  markers: "setMarkers(",
  pick: '"element"',
  region: '"region"',
  move: '"move"',
  quote: "askText(",
};
const FORWARDED = ["p", "r", "a", "m", "n"];

function branch(key) {
  return HANDLER.split("\n").filter((line) => line.includes(`key === "${key}"`));
}

test("no two shortcut branches share a key", () => {
  assert.ok(start > 0);
  const keys = [...HANDLER.matchAll(/key === "(\w)"/g)].map((m) => m[1]);
  assert.ok(keys.length >= Object.keys(ACTIONS).length);
  assert.deepEqual(keys.filter((k, i) => keys.indexOf(k) !== i), []);
});

for (const [id, action] of Object.entries(ACTIONS)) {
  test(`the ${id} button's shortcut reaches its own action`, () => {
    const label = HOST.match(new RegExp(`<button[^>]*id="${id}"[^>]*>[^<]*\\((\\w)\\)</button>`));
    assert.ok(label, `${id} button names a shortcut`);
    const lines = branch(label[1].toLowerCase());
    assert.equal(lines.length, 1, `one branch for ${label[1]}`);
    assert.ok(lines[0].includes(action), `${label[1]} runs ${action}`);
  });
}

test("the host runs a shortcut the frame forwards through the same handler as its own keys", () => {
  assert.match(HOST, /const FRAME_KEYS = new Set\(\["p", "r", "a", "m", "n"\]\);/);
  assert.match(HOST, /else if \(m\.type === "key" && FRAME_KEYS\.has\(m\.key\)\) shortcut\(m\.key\);/);
  assert.match(HOST, /if \(shortcut\(e\.key\.toLowerCase\(\)\)\) e\.preventDefault\(\);/);
});

class FakeElement {
  constructor(tagName, isContentEditable = false) {
    this.tagName = tagName;
    this.isContentEditable = isContentEditable;
  }
}

function loadFrame() {
  const listeners = [];
  const posted = [];
  const page = {
    document: { documentElement: { dataset: {}, style: {} }, querySelectorAll: () => [], querySelector: () => null },
    addEventListener: (type, fn, capture) => listeners.push({ type, fn, capture: capture === true }),
    MutationObserver: class { observe() {} },
    HTMLElement: FakeElement,
    getSelection: () => ({ isCollapsed: true }),
    parent: { postMessage: (m) => posted.push(m) },
  };
  page.window = page;
  runInNewContext(FRAME, page);
  return { listeners, posted };
}

function pressAndCollectForwarded(frame, init, pageHandler = () => {}) {
  let stopped = false;
  const e = {
    key: "", target: new FakeElement("BODY"), metaKey: false, ctrlKey: false, altKey: false, shiftKey: false, defaultPrevented: false,
    ...init,
    preventDefault() { this.defaultPrevented = true; },
    stopImmediatePropagation() { stopped = true; },
  };
  const run = (capture) => {
    for (const l of frame.listeners) if (l.type === "keydown" && l.capture === capture && !stopped) l.fn(e);
  };
  run(true);
  if (!stopped) pageHandler(e);
  run(false);
  return frame.posted.filter((m) => m.type === "key").map((m) => m.key);
}

for (const key of FORWARDED) {
  test(`with focus inside the mockup, ${key.toUpperCase()} reaches the host`, () => {
    assert.deepEqual(pressAndCollectForwarded(loadFrame(), { key }), [key]);
    assert.deepEqual(pressAndCollectForwarded(loadFrame(), { key: key.toUpperCase() }), [key]);
  });
}

test("the frame's forwarded keys are every host shortcut but T, which it sends as a text request", () => {
  const letters = Object.keys(ACTIONS).map((id) => HOST.match(new RegExp(`id="${id}"[^>]*>[^<]*\\((\\w)\\)<`))[1].toLowerCase());
  const frameKeys = FRAME.match(/const HOST_KEYS = new Set\(\[([^\]]*)\]\);/);
  assert.ok(frameKeys, "proto-pin.js names its forwarded keys");
  const forwarded = [...frameKeys[1].matchAll(/"(\w)"/g)].map((m) => m[1]);
  assert.deepEqual(forwarded.sort(), letters.filter((k) => k !== "t").sort());
  assert.deepEqual([...FORWARDED].sort(), forwarded);
});

test("a key typed in a field inside the mockup is not forwarded", () => {
  for (const target of [new FakeElement("INPUT"), new FakeElement("TEXTAREA"), new FakeElement("SELECT"), new FakeElement("DIV", true)]) {
    assert.deepEqual(pressAndCollectForwarded(loadFrame(), { key: "p", target }), [], target.tagName);
  }
});

test("a key held with Ctrl, Alt or Meta is not forwarded", () => {
  for (const mod of ["ctrlKey", "altKey", "metaKey"]) assert.deepEqual(pressAndCollectForwarded(loadFrame(), { key: "n", [mod]: true }), [], mod);
});

test("a key the page itself handles, like the switcher's R replay, stays in the mockup", () => {
  assert.deepEqual(pressAndCollectForwarded(loadFrame(), { key: "r" }, (e) => e.preventDefault()), []);
});

test("the switcher's own keys are never forwarded", () => {
  for (const key of ["1", "2", "9", "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "w", "s"]) {
    assert.deepEqual(pressAndCollectForwarded(loadFrame(), { key }), [], key);
  }
});
