import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";
import { problems, use, valid } from "./note-model.mjs";

const read = (name) => JSON.parse(readFileSync(new URL(name, import.meta.url), "utf8"));
const schema = read("./note.schema.json");
const controls = read("./controls.schema.json");
const fixtures = read("./fixtures/notes.json");
const manifests = read("./fixtures/controls.json");
use(schema, controls);

for (const { why, note } of fixtures.valid) {
  test(`accepts: ${why}`, () => assert.deepEqual(problems(note, schema), []));
}
for (const { why, note } of fixtures.invalid) {
  test(`refuses: ${why}`, () => assert.equal(valid(note, schema), false));
}
for (const { why, manifest } of manifests.valid) {
  test(`accepts the manifest: ${why}`, () => assert.deepEqual(problems(manifest, controls), []));
}
for (const { why, manifest } of manifests.invalid) {
  test(`refuses the manifest: ${why}`, () => assert.equal(valid(manifest, controls), false));
}

for (const { why, manifest } of [...manifests.registry.valid, ...manifests.registry.invalid]) {
  test(`the schema admits the registry case, so only the registry can refuse it: ${why}`, () => assert.deepEqual(problems(manifest, controls), []));
}

test("the schema's control types are the registry's, less the built-in action", () => {
  // controls.js is a page script: run it with a window and a document that never finish loading.
  const window = {};
  const context = { window, document: { readyState: "loading", addEventListener() {} } };
  vm.runInNewContext(readFileSync(new URL("./controls.js", import.meta.url), "utf8"), context);
  const registry = Object.keys(window.uiFeedbackControls.TYPES).filter((t) => t !== "action").sort();
  assert.deepEqual(registry, [...controls.$defs.control.properties.type.enum].sort());
});

const DATA_KEY = { "[data-testid]": "testid", "[data-variant]": "variant", "[data-screen-state]": "screenState" };
function element(localName, [left, top, width, height], dataset = {}, children = []) {
  const e = {
    nodeType: 1, localName, dataset, children, parentElement: null, previousElementSibling: null, style: {},
    getBoundingClientRect: () => ({ left, top, width, height, right: left + width, bottom: top + height }),
    getAttribute: () => null, setAttribute() {}, append() {}, replaceChildren() {},
    contains: (o) => { for (let x = o; x; x = x.parentElement) if (x === e) return true; return false; },
    closest: (sel) => { for (let x = e; x; x = x.parentElement) if (x.dataset[DATA_KEY[sel]] !== undefined) return x; return null; },
    querySelectorAll: (sel) => e.children.flatMap((c) => [c, ...c.querySelectorAll(sel)]).filter((c) => c.dataset[DATA_KEY[sel]] !== undefined),
  };
  children.forEach((c, i) => Object.assign(c, { parentElement: e, previousElementSibling: children[i - 1] ?? null }));
  return e;
}

function regionNote(paragraphs) {
  const main = element("main", [0, 0, 800, 1000], {}, paragraphs);
  const root = Object.assign(element("html", [0, 0, 800, 2000], {}, [element("body", [0, 0, 800, 2000], {}, [main])]), { scrollWidth: 800, scrollHeight: 2000 });
  const posted = [], listeners = {};
  const parent = { postMessage: (m) => posted.push(m) };
  const document = {
    documentElement: root,
    createElement: (tag) => element(tag, [0, 0, 0, 0]),
    querySelector: () => null,
    querySelectorAll: (sel) => root.querySelectorAll(sel),
    elementFromPoint: () => paragraphs[1],
  };
  const context = {
    parent, document, innerWidth: 800, innerHeight: 600, devicePixelRatio: 1, scrollX: 0, scrollY: 0,
    matchMedia: () => ({ matches: false }),
    addEventListener: (type, fn) => { listeners[type] ??= fn; },
    MutationObserver: class { observe() {} },
  };
  context.window = context;
  vm.runInNewContext(readFileSync(new URL("./proto-pin.js", import.meta.url), "utf8"), context);
  for (const data of [{ type: "mode", on: true, kind: "region", max: 10 }, { type: "commit" }]) listeners.message({ source: parent, data });
  const m = JSON.parse(JSON.stringify(posted.find((p) => p.type === "region")));
  return { kind: "region", rect: m.rect, anchor: m.anchor, elements: m.elements, text: "Tighten these rows." };
}
const rows = (testid) => [element("p", [0, 200, 800, 80]), element("p", [0, 280, 800, 80], testid ? { testid } : {}), element("p", [0, 360, 800, 80])];
const PARAGRAPH = (n) => `body:nth-of-type(1) > main:nth-of-type(1) > p:nth-of-type(${n})`;

test("a region over unmarked content records the holder's child elements it crosses", () => {
  const note = regionNote(rows());
  assert.deepEqual(note.elements, [{ tag: "p", cssPath: PARAGRAPH(1) }, { tag: "p", cssPath: PARAGRAPH(2) }]);
  assert.deepEqual(problems(note, schema), []);
});

test("a region that crosses a test-id element records only the test-id elements", () => {
  const note = regionNote(rows("row"));
  assert.deepEqual(note.elements, [{ tag: "p", cssPath: PARAGRAPH(2), testid: "row", testidIndex: 0 }]);
});

/** proto-pin.js on a two-paragraph page whose drawing layer keeps what it is given, so a test can count its outlines. */
function pinFrame() {
  const kept = (n) => Object.assign(n, { kids: [], append: (...c) => n.kids.push(...c), replaceChildren: (...c) => { n.kids = c; } });
  const paragraphs = [element("p", [0, 200, 800, 80]), element("p", [0, 280, 800, 80])];
  paragraphs[1].getClientRects = () => [paragraphs[1].getBoundingClientRect()];
  const words = { nodeType: 3, data: "Tighten these rows", parentElement: paragraphs[1] };
  const range = {
    startContainer: words, startOffset: 0, endContainer: words, endOffset: 7, commonAncestorContainer: words,
    getBoundingClientRect: () => ({ left: 0, top: 280, width: 60, height: 16, right: 60, bottom: 296 }),
    comparePoint: () => 0,
  };
  const main = element("main", [0, 0, 800, 1000], {}, paragraphs);
  const root = kept(Object.assign(element("html", [0, 0, 800, 2000], {}, [element("body", [0, 0, 800, 2000], {}, [main])]), { scrollWidth: 800, scrollHeight: 2000 }));
  const posted = [], listeners = {};
  const parent = { postMessage: (m) => posted.push(m) };
  const document = {
    documentElement: root,
    createElement: (tag) => kept(element(tag, [0, 0, 0, 0])),
    querySelector: () => null,
    querySelectorAll: (sel) => root.querySelectorAll(sel),
    elementFromPoint: () => paragraphs[1],
    createTreeWalker: () => { let done = false; return { nextNode: () => (done ? null : ((done = true), words)) }; },
  };
  const context = {
    parent, document, innerWidth: 800, innerHeight: 600, devicePixelRatio: 1, scrollX: 0, scrollY: 0,
    NodeFilter: { SHOW_TEXT: 4 },
    getSelection: () => ({ rangeCount: 1, isCollapsed: false, getRangeAt: () => range }),
    matchMedia: () => ({ matches: false }),
    addEventListener: (type, fn) => { listeners[type] ??= fn; },
    MutationObserver: class { observe() {} },
  };
  context.window = context;
  vm.runInNewContext(readFileSync(new URL("./proto-pin.js", import.meta.url), "utf8"), context);
  const layer = () => root.kids.find((k) => k.kids);
  return {
    posted,
    paragraphs,
    listeners,
    send: (data) => listeners.message({ source: parent, data }),
    click: (target) => listeners.click({ target, preventDefault() {}, stopImmediatePropagation() {} }),
    outlines: () => (layer()?.kids ?? []).filter((k) => k.style.outline).length,
    markers: () => (layer()?.kids ?? []).filter((k) => !k.style.outline).map((k) => k.textContent),
  };
}

const PINS = { type: "pins", pins: [{ n: 1, selector: "", rect: { x: 10, y: 10 } }, { n: "D1", selector: "", rect: { x: 20, y: 20 } }] };

test("the host hides every marker and shows them again, and pins sent while hidden stay hidden", () => {
  const f = pinFrame();
  f.send(PINS);
  assert.deepEqual(f.markers(), ["1", "D1"]);
  f.send({ type: "markers", on: false });
  assert.deepEqual(f.markers(), []);
  f.send(PINS);
  assert.deepEqual(f.markers(), []);
  f.send({ type: "markers", on: true });
  assert.deepEqual(f.markers(), ["1", "D1"]);
});

test("hiding markers during a region pick keeps the region drawn and the pick working", () => {
  const f = pinFrame();
  f.send(PINS);
  f.send({ type: "mode", on: true, kind: "region", max: 10, hold: true });
  f.send({ type: "markers", on: false });
  assert.equal(f.outlines(), 1);
  assert.deepEqual(f.markers(), []);
  f.send({ type: "commit" });
  assert.ok(f.posted.some((p) => p.type === "region"));
});

test("hiding markers during an element pick leaves the pick on, and the held outline survives it", () => {
  const f = pinFrame();
  f.send({ type: "mode", on: true, kind: "element", hold: true });
  f.send({ type: "markers", on: false });
  f.click(f.paragraphs[1]);
  assert.ok(f.posted.some((p) => p.type === "pinned"));
  f.send({ type: "mode", on: false, hold: true });
  f.send({ type: "markers", on: false });
  assert.equal(f.outlines(), 1);
});

test("a marked region stays drawn after pick mode ends, until the host releases it", () => {
  const f = pinFrame();
  f.send({ type: "mode", on: true, kind: "region", max: 10, hold: true });
  f.send({ type: "commit" });
  assert.ok(f.posted.some((p) => p.type === "region"));
  f.send({ type: "mode", on: false });
  assert.equal(f.outlines(), 1);
  f.send({ type: "release" });
  assert.equal(f.outlines(), 0);
});

test("a picked element stays outlined after pick mode ends, until the host releases it", () => {
  const f = pinFrame();
  f.send({ type: "mode", on: true, kind: "element", hold: true });
  f.click(f.paragraphs[1]);
  assert.ok(f.posted.some((p) => p.type === "pinned"));
  f.send({ type: "mode", on: false });
  assert.equal(f.outlines(), 1);
  f.send({ type: "release" });
  assert.equal(f.outlines(), 0);
});

test("selected text on a fresh page stays highlighted, until the host releases it", () => {
  const f = pinFrame();
  f.send({ type: "mode", on: false, kind: "element", hold: true });
  f.send({ type: "text", exact: 500, context: 32 });
  assert.ok(f.posted.some((p) => p.type === "selected" && !p.none));
  assert.equal(f.outlines(), 1);
  f.send({ type: "release" });
  assert.equal(f.outlines(), 0);
});

test("the page under a held pick takes no clicks, and takes them again once released", () => {
  const f = pinFrame();
  f.send({ type: "mode", on: true, kind: "region", max: 10, hold: true });
  f.send({ type: "commit" });
  f.send({ type: "mode", on: false, hold: true });
  let blocked = 0;
  const click = () => f.listeners.click({ target: f.paragraphs[0], preventDefault: () => blocked++, stopImmediatePropagation() {} });
  click();
  assert.equal(blocked, 1);
  f.send({ type: "release" });
  click();
  assert.equal(blocked, 1);
});

test("a host that does not ask to hold gets today's behavior: the region goes when pick mode ends", () => {
  const f = pinFrame();
  f.send({ type: "mode", on: true, kind: "region", max: 10 });
  f.send({ type: "commit" });
  f.send({ type: "mode", on: false });
  assert.equal(f.outlines(), 0);
});

/** proto-pin.js's relocate API on a framed page whose data controls are the given data-data-control values. */
function relocateOn(values) {
  const marked = values.map((v) => ({ getAttribute: (n) => (n === "data-data-control" ? v : null), click() {} }));
  const all = (sel) => (sel === "[data-data-control]" ? marked : []);
  const document = { documentElement: { dataset: {} }, querySelectorAll: all, querySelector: (sel) => all(sel)[0] ?? null };
  const context = { parent: { postMessage() {} }, document, addEventListener() {}, MutationObserver: class { observe() {} } };
  context.window = context;
  vm.runInNewContext(readFileSync(new URL("./proto-pin.js", import.meta.url), "utf8"), context);
  return context.uiFeedbackRelocate;
}

test("replay reports a missed step as -1 on a page that marks no data control", () => {
  assert.equal(relocateOn([]).replay([{ op: "toggle", name: "filter" }]), -1);
});

test("replay counts a missed step on a page that marks a data control", () => {
  assert.equal(relocateOn(["toggle:other"]).replay([{ op: "toggle", name: "filter" }]), 1);
});

test("a schema keyword outside the honored subset throws", () => {
  assert.throws(() => problems({}, { ...schema, oneOf: [] }), /oneOf is not honored/);
});

test("a rect number JSON cannot carry is refused (postMessage can)", () => {
  const base = fixtures.valid[0].note;
  for (const bad of [NaN, Infinity, -Infinity]) {
    assert.equal(valid({ ...base, rect: { x: bad, y: 0, w: 1, h: 1 } }, schema), false, String(bad));
  }
});

test("an unresolvable $ref throws", () => {
  assert.throws(() => problems({}, { $ref: "#/$defs/missing" }), /unresolvable/);
  assert.throws(() => problems({}, { $ref: "other.schema.json#/$defs/id" }), /unresolvable/, "a schema never registered");
});
