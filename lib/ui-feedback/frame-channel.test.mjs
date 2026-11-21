import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { awaitReady, frameTarget, fromFrame, namesFrom, READY_MS, viewFrom } from "./frame-channel.mjs";

const DEV = "http://localhost:5173";
const HOST = readFileSync(new URL("./host.html", import.meta.url), "utf8");
const CODE = readFileSync(new URL("./host.mjs", import.meta.url), "utf8");
const CHANNEL = readFileSync(new URL("./frame-channel.mjs", import.meta.url), "utf8");
const frameWindow = { name: "the dev frame" };
const otherWindow = { name: "another window" };

function fakeTimers() {
  const pending = new Map();
  let next = 0;
  return {
    setTimeout(run, ms) {
      pending.set(++next, { run, ms });
      return next;
    },
    clearTimeout(id) {
      pending.delete(id);
    },
    elapse(ms) {
      for (const [id, t] of pending) {
        if (t.ms <= ms) {
          pending.delete(id);
          t.run();
        }
      }
    },
  };
}

test("a real-stack message is taken only from the dev frame's window on the dev origin", () => {
  assert.equal(fromFrame({ source: frameWindow, origin: DEV }, frameWindow, DEV), true);
});

test("a message from another origin is ignored, even from the dev frame's window", () => {
  for (const origin of ["http://localhost:5174", "http://127.0.0.1:5173", "https://localhost:5173", "null", "", undefined]) {
    assert.equal(fromFrame({ source: frameWindow, origin }, frameWindow, DEV), false, String(origin));
  }
});

test("a message from another window is ignored, even on the dev origin", () => {
  for (const source of [otherWindow, null, undefined]) {
    assert.equal(fromFrame({ source, origin: DEV }, frameWindow, DEV), false, String(source?.name));
  }
  assert.equal(fromFrame(null, frameWindow, DEV), false);
});

test("the sandboxed mockup's messages are checked by window alone, since its origin is opaque", () => {
  assert.equal(fromFrame({ source: frameWindow, origin: "null" }, frameWindow, null), true);
  assert.equal(fromFrame({ source: otherWindow, origin: "null" }, frameWindow, null), false);
});

test("on a real-stack route every host-to-frame postMessage names the dev origin as targetOrigin", () => {
  for (const origin of [DEV, "http://127.0.0.1:3000"]) {
    assert.equal(frameTarget(origin), origin);
    assert.equal(frameTarget(origin, "*"), origin, "the dev origin wins over a mockup target");
  }
  const posts = [...CODE.matchAll(/\.postMessage\(([^)]*)\)/g)].map((m) => m[1]);
  assert.deepEqual(posts, ["m, target"], "the host page posts to the frame only through `target`");
  assert.match(CODE, /const target = frameTarget\(devOrigin, frame\.dataset\.mockupTarget \|\| null\);/);
  for (const [name, text] of [["host.html", HOST], ["host.mjs", CODE], ["frame-channel.mjs", CHANNEL]]) {
    assert.doesNotMatch(text, /["']\*["']/, `${name} names no "*" target origin`);
  }
});

test("the mockup's target comes only from its frame tag, and with no target the host page posts nothing", () => {
  assert.equal(frameTarget(null, "*"), "*");
  assert.equal(frameTarget(null), null);
  assert.equal(frameTarget(null, null), null);
  assert.match(CODE, /const toFrame = \(m\) => \{ if \(target && ready && loads < 2\) /);
});

test("a frame that sends no ready message is reported blocked once the timeout passes", () => {
  const timers = fakeTimers();
  let blocked = 0;
  awaitReady(() => { blocked += 1; }, READY_MS, timers);
  timers.elapse(READY_MS - 1);
  assert.equal(blocked, 0);
  timers.elapse(READY_MS);
  assert.equal(blocked, 1);
});

test("a frame whose ready message comes in time is never reported blocked", () => {
  const timers = fakeTimers();
  let blocked = 0;
  const heard = awaitReady(() => { blocked += 1; }, READY_MS, timers);
  heard();
  timers.elapse(READY_MS);
  assert.equal(blocked, 0);
  heard();
});

test("the host page arms the ready timeout before it sets the frame's document, and only the ready message disarms it", () => {
  const armed = CODE.indexOf("heard = awaitReady(");
  assert.ok(armed > 0);
  assert.ok(armed < CODE.indexOf("frame.src = `${devOrigin}/`"));
  assert.ok(armed < CODE.indexOf("frame.srcdoc = "));
  const load = CODE.slice(CODE.indexOf('frame.addEventListener("load"'), CODE.indexOf("const blocked = "));
  assert.ok(load.length > 0);
  assert.doesNotMatch(load, /heard|blocked/, "the load event neither reports nor clears a blocked frame");
  assert.match(CODE, /if \(m\.type === "ready"\) \{\s*if \(ready\) return;\s*ready = true;\s*heard\(\);/);
});

const KEY = "^[A-Za-z0-9_-]{1,32}$";

test("the frame's view report keeps the variants and states whose keys fit, labels as plain text cut to 60", () => {
  const got = viewFrom({
    type: "view",
    variants: [{ key: "A", label: "Editorial  column" }, { key: "B", label: "L".repeat(80) }, { key: "no spaces", label: "x" }, { key: "C" }, "D"],
    variant: "B",
    states: [{ key: "populated", label: "Populated" }],
    state: "populated",
  }, KEY);
  assert.deepEqual(got, {
    variants: [{ key: "A", label: "Editorial column" }, { key: "B", label: "L".repeat(60) }, { key: "C", label: "" }],
    variant: "B",
    states: [{ key: "populated", label: "Populated" }],
    state: "populated",
  });
});

test("a current variant or state the report does not list is no current one", () => {
  const got = viewFrom({ variants: [{ key: "A", label: "One" }], variant: "Z", states: "none", state: "empty" }, KEY);
  assert.deepEqual(got, { variants: [{ key: "A", label: "One" }], variant: null, states: [], state: null });
});

test("a view report caps the variants and states it keeps", () => {
  const many = Array.from({ length: 40 }, (_, i) => ({ key: `v${i}`, label: `V${i}` }));
  const got = viewFrom({ variants: many, states: many }, KEY);
  assert.equal(got.variants.length, 26);
  assert.equal(got.states.length, 26);
});

test("the frame's names for listed notes keep positive integer keys and string parts cut to 60", () => {
  const got = namesFrom({ type: "named", names: [
    { k: 3, text: "Before  diagram", card: "S1 Give the ledger register one owner", extra: "dropped" },
    { k: 4, text: 7, toText: "T".repeat(90) },
    { k: "5", text: "no" },
    { k: 0, text: "no" },
    null,
  ] });
  assert.deepEqual([...got], [
    [3, { text: "Before diagram", card: "S1 Give the ledger register one owner", toText: "", toCard: "" }],
    [4, { text: "", card: "", toText: "T".repeat(60), toCard: "" }],
  ]);
  assert.deepEqual([...namesFrom({ names: "x" })], []);
});
