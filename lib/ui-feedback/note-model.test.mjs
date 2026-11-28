import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";
import { draftStore, problems, use, valid } from "./note-model.mjs";

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
for (const { why, change } of fixtures.changes.valid) {
  test(`accepts the change: ${why}`, () => assert.deepEqual(problems(change, schema, schema.$defs.change, "change"), []));
}
for (const { why, change } of fixtures.changes.invalid) {
  test(`refuses the change: ${why}`, () => assert.notDeepEqual(problems(change, schema, schema.$defs.change, "change"), []));
}
for (const kind of ["edit", "withdraw"]) {
  for (const c of fixtures[`${kind}s`].valid) {
    test(`accepts the ${kind}: ${c.why}`, () => assert.deepEqual(problems(c[kind], schema, schema.$defs[kind], kind), []));
  }
  for (const c of fixtures[`${kind}s`].invalid) {
    test(`refuses the ${kind}: ${c.why}`, () => assert.notDeepEqual(problems(c[kind], schema, schema.$defs[kind], kind), []));
  }
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

/** A sessionStorage stand-in holding strings, as the browser's does. */
function storage(initial = {}) {
  const m = new Map(Object.entries(initial));
  return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), raw: m };
}
const DRAFT_A = { kind: "element", anchor: { tag: "td", cssPath: "" }, text: "First draft." };
const DRAFT_B = { kind: "element", anchor: { tag: "td", cssPath: "" }, text: "<img src=x onerror=alert(1)>Second draft." };

test("the draft store gives back the drafts saved for the same run", () => {
  const s = storage();
  draftStore(s, "run-1", schema).save([DRAFT_A, DRAFT_B]);
  assert.deepEqual(draftStore(s, "run-1", schema).load(), [DRAFT_A, DRAFT_B]);
});

test("a sent or discarded draft is gone from the store once the drafts are saved without it", () => {
  const s = storage();
  const store = draftStore(s, "run-1", schema);
  store.save([DRAFT_A, DRAFT_B]);
  store.save([DRAFT_B]);
  assert.deepEqual(draftStore(s, "run-1", schema).load(), [DRAFT_B]);
  store.save([]);
  assert.deepEqual(draftStore(s, "run-1", schema).load(), []);
});

test("another run's drafts are never given back", () => {
  const s = storage();
  draftStore(s, "run-1", schema).save([DRAFT_A]);
  assert.deepEqual(draftStore(s, "run-2", schema).load(), [], "a different run sees no drafts");
  assert.deepEqual(draftStore(s, "run-1", schema).load(), [DRAFT_A], "the first run still has its own");
});

test("a malformed store, or a stored note the schema refuses, is dropped", () => {
  const KEY = "ui-feedback-drafts";
  for (const raw of ["not json", "null", '"text"', '{"run":"run-1"}', '{"run":"run-1","drafts":{}}']) {
    assert.deepEqual(draftStore(storage({ [KEY]: raw }), "run-1", schema).load(), [], raw);
  }
  const mixed = JSON.stringify({ run: "run-1", drafts: [DRAFT_A, { kind: "nope", text: "x" }, "a string", null, { ...DRAFT_B, label: "extra" }] });
  assert.deepEqual(draftStore(storage({ [KEY]: mixed }), "run-1", schema).load(), [DRAFT_A], "only the draft the contract admits is kept");
});

test("a store that throws, as storage can when it is off, loses the drafts without breaking the page", () => {
  const off = { getItem() { throw new Error("denied"); }, setItem() { throw new Error("denied"); } };
  const store = draftStore(off, "run-1", schema);
  assert.doesNotThrow(() => store.save([DRAFT_A]));
  assert.deepEqual(store.load(), []);
});

test("the schema's control types are the registry's, less the built-in action", () => {
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
    closest: (sel) => { for (let x = e; x; x = x.parentElement) if (sel === "[hidden]" ? x.hidden : x.dataset[DATA_KEY[sel]] !== undefined) return x; return null; },
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

const node = (localName) => {
  const n = { localName, style: {}, attrs: {}, kids: [], contains: () => false };
  Object.assign(n, { setAttribute: (k, v) => { n.attrs[k] = v; }, append: (...c) => n.kids.push(...c), replaceChildren: () => { n.kids = []; } });
  return n;
};
const reflow = (e, [left, top, width, height]) => {
  e.getBoundingClientRect = () => ({ left, top, width, height, right: left + width, bottom: top + height });
};

function movePage() {
  const a = element("section", [0, 100, 400, 100], { testid: "card-a" });
  const b = element("section", [0, 300, 400, 100], { testid: "card-b" });
  const main = element("main", [0, 0, 800, 1000], {}, [a, b]);
  const root = Object.assign(element("html", [0, 0, 800, 2000], {}, [element("body", [0, 0, 800, 2000], {}, [main])]), { scrollWidth: 800, scrollHeight: 2000 });
  const page = { a, b, posted: [], layer: null };
  root.append = (l) => { page.layer = l; };
  const parent = { postMessage: (m) => page.posted.push(JSON.parse(JSON.stringify(m))) }, listeners = {};
  const document = {
    documentElement: root, createElement: node, createElementNS: (_ns, tag) => node(tag),
    querySelector: () => null, querySelectorAll: (sel) => root.querySelectorAll(sel),
  };
  const context = {
    parent, document, innerWidth: 800, innerHeight: 600, devicePixelRatio: 1, scrollX: 0, scrollY: 0,
    matchMedia: () => ({ matches: false }),
    addEventListener: (type, fn) => { listeners[type] ??= fn; },
    MutationObserver: class { observe() {} },
  };
  context.window = context;
  vm.runInNewContext(readFileSync(new URL("./proto-pin.js", import.meta.url), "utf8"), context);
  const event = (target, clientX, clientY, shiftKey = false) => ({ target, clientX, clientY, shiftKey, preventDefault() {}, stopImmediatePropagation() {} });
  page.send = (data) => listeners.message({ source: parent, data });
  page.click = (target, x, y, shift) => listeners.click(event(target, x, y, shift));
  page.resize = () => listeners.resize();
  page.line = () => page.layer.kids.find((k) => k.localName === "svg")?.kids.find((k) => k.localName === "line")?.attrs;
  page.send({ type: "mode", on: true, kind: "move" });
  return page;
}
const sitsOn = (x, y, el) => {
  const r = el.getBoundingClientRect();
  return Number(x) >= r.left && Number(x) <= r.right && Number(y) >= r.top && Number(y) <= r.bottom;
};

test("a move arrow drawn between two elements keeps both ends on them when the page re-flows", () => {
  const page = movePage();
  page.click(page.a, 50, 150);
  page.click(page.b, 200, 350);
  let line = page.line();
  assert.ok(sitsOn(line.x1, line.y1, page.a) && sitsOn(line.x2, line.y2, page.b), JSON.stringify(line));
  reflow(page.a, [400, 700, 300, 200]);
  reflow(page.b, [0, 50, 200, 80]);
  page.resize();
  line = page.line();
  assert.ok(sitsOn(line.x1, line.y1, page.a), `the start left the element it moves: ${JSON.stringify(line)}`);
  assert.ok(sitsOn(line.x2, line.y2, page.b), `the end left the element it goes to: ${JSON.stringify(line)}`);
});

test("the move note names both ends' anchors and fits the contract", () => {
  const page = movePage();
  page.click(page.a, 50, 150);
  page.click(page.b, 200, 350);
  const m = page.posted.find((p) => p.type === "move");
  const note = { kind: "move", anchor: m.anchor, rect: m.rect, to: m.to, text: "Put this card below the other." };
  assert.deepEqual(problems(note, schema), []);
  assert.deepEqual([note.anchor.testid, note.to.anchor.testid], ["card-a", "card-b"]);
  assert.equal(note.anchor.cssPath, "body:nth-of-type(1) > main:nth-of-type(1) > section:nth-of-type(1)");
  assert.equal(note.to.anchor.cssPath, "body:nth-of-type(1) > main:nth-of-type(1) > section:nth-of-type(2)");
  assert.deepEqual(note.to.point, { x: 25, y: 17.5 });
});

test("Shift picks a point alone, and the host clears the arrow once the note is done", () => {
  const page = movePage();
  page.click(page.a, 50, 150);
  page.click(page.b, 200, 350, true);
  const m = page.posted.find((p) => p.type === "move");
  assert.deepEqual(m.to, { point: { x: 25, y: 17.5 } });
  assert.deepEqual([Number(page.line().x2), Number(page.line().y2)], [200, 350]);
  page.send({ type: "mode", on: false });
  assert.ok(page.line(), "the arrow stays drawn while the note is written");
  page.send({ type: "clear-arrow" });
  assert.equal(page.line(), undefined);
});

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
  const root = kept(Object.assign(element("html", [0, 0, 800, 2000], {}, [element("body", [0, 0, 800, 2000], {}, [main])]), { scrollWidth: 800, scrollHeight: 2000, querySelector: () => null }));
  const posted = [], listeners = {}, dispatched = [];
  const parent = { postMessage: (m) => posted.push(m) };
  const document = {
    documentElement: root,
    createElement: (tag) => kept(element(tag, [0, 0, 0, 0])),
    querySelector: () => null,
    querySelectorAll: (sel) => root.querySelectorAll(sel),
    elementFromPoint: () => paragraphs[1],
    createTreeWalker: () => { let done = false; return { nextNode: () => (done ? null : ((done = true), words)) }; },
    dispatchEvent: (ev) => dispatched.push({ type: ev.type, detail: ev.detail }),
  };
  const context = {
    parent, document, innerWidth: 800, innerHeight: 600, devicePixelRatio: 1, scrollX: 0, scrollY: 0,
    CustomEvent: class { constructor(type, init) { this.type = type; this.detail = init?.detail; } },
    scrollTo() {},
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
    root,
    dispatched,
    layer,
    send: (data) => listeners.message({ source: parent, data }),
    click: (target) => listeners.click({ target, preventDefault() {}, stopImmediatePropagation() {} }),
    outlines: () => (layer()?.kids ?? []).filter((k) => k.style.outline).length,
    markers: () => (layer()?.kids ?? []).filter((k) => !k.style.outline).map((k) => k.textContent),
  };
}

const PINS = { type: "pins", pins: [{ n: 1, selector: "", rect: { x: 10, y: 10 } }, { n: "D1", selector: "", rect: { x: 20, y: 20 } }] };

test("a scroll redraws the layer, so an outline on a fixed element follows it", () => {
  const f = pinFrame();
  f.send(PINS);
  const before = f.layer();
  let redraws = 0;
  const replace = before.replaceChildren;
  before.replaceChildren = (...c) => { redraws += 1; replace(...c); };
  assert.equal(typeof f.listeners.scroll, "function");
  f.listeners.scroll();
  f.listeners.scroll();
  assert.equal(redraws, 2, "each scroll with no frame callback pending redraws once");
});

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

const plain = (x) => JSON.parse(JSON.stringify(x));
const noteBoxes = (f, which) => (f.layer()?.kids ?? []).filter((k) => k.dataset.note === which)
  .map((k) => [k.style.left, k.style.top, k.style.width, k.style.height].join(" "));
const REGION_NOTE = { n: 1, kind: "region", rect: { x: 10, y: 10, w: 20, h: 5 } };
const PARAGRAPH_NOTE = { n: 2, kind: "element", cssPath: PARAGRAPH(2), rect: { x: 50, y: 50, w: 1, h: 1 } };

test("a hovered list row draws its note's stored box on the page, and moving off clears it", () => {
  const f = pinFrame();
  f.send({ type: "show", target: REGION_NOTE });
  assert.deepEqual(noteBoxes(f, "hover"), ["80px 200px 160px 100px"], "10%, 10%, 20% and 5% of an 800 by 2000 page");
  f.send({ type: "show", target: null });
  assert.deepEqual(noteBoxes(f, "hover"), [], "no hover box once the row is left");
});

test("an element note's box is its element's box today when its path still finds it", () => {
  const f = pinFrame();
  f.root.querySelector = (sel) => (sel === `:scope > ${PARAGRAPH(2)}` ? f.paragraphs[1] : null);
  f.send({ type: "show", target: PARAGRAPH_NOTE });
  assert.deepEqual(noteBoxes(f, "hover"), ["0px 280px 800px 80px"], "the second paragraph's box, not the stored 50% one");
});

test("selecting a note restores its view, keeps its box drawn, and a page click clears it and still reaches the page", () => {
  const f = pinFrame();
  f.send({ type: "select", target: { ...REGION_NOTE, variant: "B", state: "empty", content: "worst" } });
  assert.deepEqual(plain(f.dispatched), [{ type: "vs:show", detail: { variant: "B", state: "empty", content: "worst" } }], "the switcher is asked for the note's variant, state and content set");
  assert.deepEqual(noteBoxes(f, "selected"), ["80px 200px 160px 100px"], "the selected note's box is drawn");
  assert.deepEqual(plain(f.posted.at(-1)), { type: "shown", n: 1, found: true }, "the host hears the box was drawn");
  f.send({ type: "show", target: null });
  assert.deepEqual(noteBoxes(f, "selected"), ["80px 200px 160px 100px"], "leaving a row keeps the selected box");
  let blocked = 0;
  f.listeners.click({ target: f.paragraphs[0], clientX: 400, clientY: 500, preventDefault: () => blocked++, stopImmediatePropagation() {} });
  assert.deepEqual(noteBoxes(f, "selected"), [], "a click on the page clears the selected box");
  assert.deepEqual(plain(f.posted.at(-1)), { type: "unselected" }, "the host hears the selection ended");
  assert.equal(blocked, 0, "the click still reaches the page");
});

function variantFrame() {
  const kept = (n) => Object.assign(n, { kids: [], append: (...c) => n.kids.push(...c), replaceChildren: (...c) => { n.kids = c; } });
  const states = () => ["empty", "full"].map((k) => element("div", [0, 0, 800, 400], { screenState: k }));
  const view = {};
  for (const v of ["A", "B"]) {
    const [empty, full] = states();
    view[v] = { el: element("section", [0, 0, 800, 800], { variant: v }, [empty, full]), empty, full };
  }
  const root = kept(Object.assign(element("html", [0, 0, 800, 2000], {}, [element("body", [0, 0, 800, 2000], {}, [view.A.el, view.B.el])]), { scrollWidth: 800, scrollHeight: 2000 }));
  const show = (v, s) => {
    for (const k of ["A", "B"]) {
      view[k].el.hidden = k !== v;
      view[k].empty.hidden = s !== "empty";
      view[k].full.hidden = s !== "full";
    }
    for (const o of observers) if (o.opts?.attributeFilter?.includes("hidden") && o.opts.subtree) o.cb([]);
  };
  const observers = [], listeners = {};
  const parent = { postMessage() {} };
  const document = {
    documentElement: root, createElement: (tag) => kept(element(tag, [0, 0, 0, 0])),
    querySelector: () => null, querySelectorAll: (sel) => root.querySelectorAll(sel),
  };
  const context = {
    parent, document, innerWidth: 800, innerHeight: 600, devicePixelRatio: 1, scrollX: 0, scrollY: 0,
    matchMedia: () => ({ matches: false }),
    addEventListener: (type, fn) => { listeners[type] ??= fn; },
    MutationObserver: class { constructor(cb) { this.cb = cb; observers.push(this); } observe(_t, opts) { this.opts = opts; } },
  };
  context.window = context;
  vm.runInNewContext(readFileSync(new URL("./proto-pin.js", import.meta.url), "utf8"), context);
  show("A", "empty");
  const layer = () => root.kids.find((k) => k.kids);
  return {
    show,
    send: (data) => listeners.message({ source: parent, data }),
    markers: () => (layer()?.kids ?? []).filter((k) => !k.style.outline).map((k) => k.textContent),
    hovered: () => (layer()?.kids ?? []).filter((k) => k.dataset.note === "hover").length,
  };
}

test("a note's marker is drawn only while the variant and screen state it was made on are shown", () => {
  const f = variantFrame();
  const at = { selector: "", rect: { x: 10, y: 10 } };
  f.send({ type: "pins", pins: [
    { n: 1, ...at }, { n: 2, ...at, variant: "A", state: "empty" }, { n: 3, ...at, variant: "B", state: "empty" },
    { n: 4, ...at, variant: "A", state: "full" }, { n: 5, ...at, variant: "A" }, { n: 6, ...at, variant: "Z" },
  ] });
  assert.deepEqual(f.markers(), ["1", "2", "5"], "variant A, state empty: its notes, the variant-wide note and the note made outside every variant");
  f.show("B", "empty");
  assert.deepEqual(f.markers(), ["1", "3"], "switching to variant B hides variant A's markers and shows B's");
  f.show("B", "full");
  assert.deepEqual(f.markers(), ["1"], "switching B's state hides the marker made on its empty state");
  f.show("A", "full");
  assert.deepEqual(f.markers(), ["1", "4", "5"], "switching back to variant A shows the markers made on the state now shown");
  f.show("A", "empty");
  assert.deepEqual(f.markers(), ["1", "2", "5"], "switching back to the first view shows its markers again");
});

test("hovering a note from a variant not shown draws no box over the variant that is", () => {
  const f = variantFrame();
  f.send({ type: "show", target: { ...REGION_NOTE, variant: "B", state: "empty" } });
  assert.equal(f.hovered(), 0, "variant B's note draws nothing over variant A");
  f.send({ type: "show", target: { ...REGION_NOTE, variant: "A", state: "empty" } });
  assert.equal(f.hovered(), 1, "variant A's note draws its box");
});

test("a note with no box to draw says so to the host and draws nothing", () => {
  const f = pinFrame();
  f.send({ type: "select", target: { n: 3, kind: "element", cssPath: PARAGRAPH(9) } });
  assert.deepEqual(plain(f.posted.at(-1)), { type: "shown", n: 3, found: false });
  assert.deepEqual(noteBoxes(f, "selected"), []);
});

test("a click on a marker's own box selects its note instead of reaching the page, outside a pick mode only", () => {
  const f = pinFrame();
  f.send(PINS);
  const badge = f.layer().kids.find((k) => k.textContent === "1");
  badge.getBoundingClientRect = () => ({ left: 70, top: 70, width: 22, height: 22, right: 92, bottom: 92 });
  let blocked = 0;
  const click = (x, y, target = f.paragraphs[0]) => f.listeners.click({ target, clientX: x, clientY: y, preventDefault: () => blocked++, stopImmediatePropagation() {} });
  click(80, 80);
  assert.equal(blocked, 0, "a host that never asked for marker clicks (the planning page) keeps every click on the page");
  f.send({ type: "markers", on: true, clicks: true });
  const badge2 = f.layer().kids.find((k) => k.textContent === "1");
  badge2.getBoundingClientRect = badge.getBoundingClientRect;
  click(80, 80);
  assert.deepEqual(plain(f.posted.at(-1)), { type: "marker", n: 1 }, "the host hears which marker was clicked");
  assert.equal(blocked, 1, "the marker's click does not reach the page");
  click(200, 200);
  assert.equal(blocked, 1, "a click beside the marker reaches the page");
  assert.equal(f.posted.filter((p) => p.type === "marker").length, 1, "a click beside the marker selects no note");
  f.listeners.click({ target: f.paragraphs[0], clientX: 80, clientY: 80, isTrusted: false, detail: 0, preventDefault: () => blocked++, stopImmediatePropagation() {} });
  assert.equal(blocked, 1, "a script's click under the marker (a data log replay) still reaches the page");
  f.send({ type: "mode", on: true, kind: "element", hold: true });
  const before = f.posted.length;
  click(80, 80, f.paragraphs[1]);
  assert.ok(!f.posted.slice(before).some((p) => p.type === "marker"), "in a pick mode the marker takes no click");
  assert.ok(f.posted.slice(before).some((p) => p.type === "pinned"), "the pick goes to the element under it");
});

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
