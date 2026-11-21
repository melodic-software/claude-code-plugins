import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { awaitReady, frameTarget, fromFrame, READY_MS } from "./frame-channel.mjs";

const DEV = "http://localhost:5173";
const HOST = readFileSync(new URL("./host.html", import.meta.url), "utf8");
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
  const posts = [...HOST.matchAll(/\.postMessage\(([^)]*)\)/g)].map((m) => m[1]);
  assert.deepEqual(posts, ["m, target"], "the host page posts to the frame only through `target`");
  assert.match(HOST, /const target = frameTarget\(devOrigin, frame\.dataset\.mockupTarget \|\| null\);/);
  for (const [name, text] of [["host.html", HOST], ["frame-channel.mjs", CHANNEL]]) {
    assert.doesNotMatch(text, /["']\*["']/, `${name} names no "*" target origin`);
  }
});

test("the mockup's target comes only from its frame tag, and with no target the host page posts nothing", () => {
  assert.equal(frameTarget(null, "*"), "*");
  assert.equal(frameTarget(null), null);
  assert.equal(frameTarget(null, null), null);
  assert.match(HOST, /const toFrame = \(m\) => \{ if \(target && ready && loads < 2\) /);
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
  const armed = HOST.indexOf("heard = awaitReady(");
  assert.ok(armed > 0);
  assert.ok(armed < HOST.indexOf("frame.src = `${devOrigin}/`"));
  assert.ok(armed < HOST.indexOf("frame.srcdoc = "));
  const load = HOST.slice(HOST.indexOf('frame.addEventListener("load"'), HOST.indexOf("const blocked = "));
  assert.ok(load.length > 0);
  assert.doesNotMatch(load, /heard|blocked/, "the load event neither reports nor clears a blocked frame");
  assert.match(HOST, /if \(m\.type === "ready"\) \{\s*if \(ready\) return;\s*ready = true;\s*heard\(\);/);
});
