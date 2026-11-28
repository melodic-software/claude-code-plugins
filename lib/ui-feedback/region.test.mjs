import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const FRAME = readFileSync(new URL("./proto-pin.js", import.meta.url), "utf8");
const PAGE_W = 800, PAGE_H = 4000, VIEW_W = 800, VIEW_H = 600;

function loadFrame() {
  const win = { scrollX: 0, scrollY: 0, innerWidth: VIEW_W, innerHeight: VIEW_H, devicePixelRatio: 1 };
  class El {
    constructor(tag, box = null, data = {}) {
      Object.assign(this, { localName: tag, tagName: tag.toUpperCase(), nodeType: 1, box, children: [], parentElement: null, dataset: { ...data }, style: {}, attrs: {}, textContent: "" });
    }
    append(...kids) { for (const k of kids) { k.parentElement = this; this.children.push(k); } }
    replaceChildren(...kids) { this.children = []; this.append(...kids); }
    get previousElementSibling() { const s = this.parentElement?.children ?? []; return s[s.indexOf(this) - 1] ?? null; }
    getAttribute(n) { return this.attrs[n] ?? null; }
    setAttribute(n, v) { this.attrs[n] = String(v); }
    getClientRects() { return this.box ? [this.box] : []; }
    getBoundingClientRect() {
      const b = this.box ?? { x: 0, y: 0, w: 0, h: 0 }, left = b.x - win.scrollX, top = b.y - win.scrollY;
      return { left, top, width: b.w, height: b.h, right: left + b.w, bottom: top + b.h };
    }
    contains(o) { for (let e = o; e; e = e.parentElement) if (e === this) return true; return false; }
    closest(sel) {
      const key = /^\[data-([a-z-]+)\]$/.exec(sel)?.[1].replace(/-([a-z])/g, (_, c) => c.toUpperCase());
      for (let e = this; e; e = e.parentElement) if (key && e.dataset[key] !== undefined) return e;
      return null;
    }
    querySelectorAll(sel) {
      const out = [], walk = (e) => { for (const k of e.children) { if (k.closest(sel) === k) out.push(k); walk(k); } };
      walk(this);
      return out;
    }
    setPointerCapture() {}
  }
  const root = new El("html", { x: 0, y: 0, w: PAGE_W, h: PAGE_H });
  const drawnBottom = () => root.children.filter((c) => c.attrs["data-ui-feedback-layer"] !== undefined)
    .flatMap((l) => l.children).map((o) => parseFloat(o.style.top) + parseFloat(o.style.height)).filter(Number.isFinite);
  Object.defineProperty(root, "scrollWidth", { value: PAGE_W });
  Object.defineProperty(root, "scrollHeight", { get: () => Math.max(PAGE_H, ...drawnBottom()) });
  const body = new El("body", { x: 0, y: 0, w: PAGE_W, h: PAGE_H });
  const list = new El("ul", { x: 0, y: 100, w: PAGE_W, h: 3000 });
  for (let i = 0; i < 30; i++) list.append(new El("li", { x: 0, y: 100 + i * 100, w: PAGE_W, h: 100 }, { testid: "row" }));
  root.append(body);
  body.append(list);
  const hit = (e, x, y) => {
    for (const k of e.children) if (k.box && x >= k.box.x && x < k.box.x + k.box.w && y >= k.box.y && y < k.box.y + k.box.h) return hit(k, x, y);
    return e;
  };
  const listeners = [], posted = [], frames = [];
  const clampScroll = () => { win.scrollY = Math.min(Math.max(0, win.scrollY), root.scrollHeight - VIEW_H); };
  Object.assign(win, {
    document: {
      documentElement: root, body,
      createElement: (tag) => new El(tag),
      querySelectorAll: (sel) => root.querySelectorAll(sel),
      querySelector: () => null,
      elementFromPoint: (x, y) => hit(root, x + win.scrollX, y + win.scrollY),
    },
    addEventListener: (type, fn, capture) => listeners.push({ type, fn, capture: capture === true }),
    scrollBy: (x, y) => { win.scrollY += y; clampScroll(); },
    scrollTo: (x, y) => { win.scrollY = typeof x === "object" ? x.top : y; clampScroll(); },
    requestAnimationFrame: (fn) => frames.push(fn),
    matchMedia: () => ({ matches: false }),
    getSelection: () => ({ isCollapsed: true }),
    MutationObserver: class { observe() {} },
    HTMLElement: El,
    parent: { postMessage: (m) => posted.push(m) },
  });
  win.window = win;
  runInNewContext(FRAME, win);

  const fire = (type, init = {}) => {
    let stopped = false;
    const e = {
      type, isTrusted: true, pointerId: 1, button: 0, shiftKey: false, key: "", metaKey: false, ctrlKey: false, altKey: false, ...init,
      preventDefault() { this.defaultPrevented = true; },
      stopImmediatePropagation() { stopped = true; },
    };
    if (e.target === undefined) e.target = typeof e.clientX === "number" ? win.document.elementFromPoint(e.clientX, e.clientY) : body;
    for (const capture of [true, false]) for (const l of listeners) if (l.type === type && l.capture === capture && !stopped) l.fn(e);
  };
  const host = (data) => fire("message", { source: win.parent, data, target: undefined });
  const point = (x, y) => ({ clientX: x, clientY: y });
  return {
    win, posted, fire,
    region: (rect) => host({ type: "mode", on: true, kind: "region", max: 10, hold: true, ...(rect ? { rect } : {}) }),
    press: (x, y) => fire("pointerdown", point(x, y)),
    move: (x, y) => fire("pointermove", point(x, y)),
    release: (x, y) => { fire("pointerup", point(x, y)); fire("click", point(x, y)); },
    key: (key, shiftKey = false) => fire("keydown", { key, shiftKey }),
    scrollTo: (y) => { win.scrollY = y; fire("scroll"); },
    frames: (n) => { for (let i = 0; i < n && frames.length; i++) frames.splice(0, frames.length).forEach((fn) => fn()); },
    sent: () => JSON.parse(JSON.stringify(posted.filter((m) => m.type === "region"))),
  };
}

test("a region keeps its place on the page when the mockup scrolls", () => {
  const f = loadFrame();
  f.region();
  f.scrollTo(500);
  f.key("Enter");
  assert.deepEqual(f.sent().map((m) => m.rect), [{ x: 40, y: 6.25, w: 20, h: 2.5 }], "the opening box, 160 by 100 at x 320, y 250 of the first view, where it was drawn");
});

test("dragging to the bottom edge scrolls the mockup, so the region reaches past the viewport", () => {
  const f = loadFrame();
  f.region();
  f.press(100, 150);
  f.move(300, 595);
  f.frames(60);
  const scrolled = f.win.scrollY;
  assert.ok(scrolled > 0, `the frame scrolled (${scrolled})`);
  f.release(300, 595);
  const [m] = f.sent();
  assert.ok(m, "the region was sent");
  assert.deepEqual({ x: m.rect.x, y: m.rect.y, w: m.rect.w }, { x: 12.5, y: 3.75, w: 25 });
  const tall = (m.rect.h / 100) * PAGE_H;
  assert.ok(Math.abs(tall - (595 + scrolled - 150)) < 0.5, `the region runs from y 150 to the pointer's place on the page (${tall} px)`);
  assert.ok(tall > VIEW_H, `taller than the ${VIEW_H} pixel view (${tall} px)`);
  assert.equal(m.anchor.tag, "ul");
  assert.ok(m.elements.length > 6, `it crosses the rows below the first view (${m.elements.length})`);
});

test("dragging past the bottom of the frame keeps scrolling", () => {
  const f = loadFrame();
  f.region();
  f.press(100, 150);
  f.move(300, 700);
  f.frames(30);
  assert.ok(f.win.scrollY > 0, `the frame scrolled (${f.win.scrollY})`);
});

test("a drag held past the frame's bottom stops at the end of the mockup, so the drawn box never stretches the page", () => {
  const f = loadFrame();
  f.region();
  f.press(100, 150);
  f.move(300, 700);
  f.frames(300);
  assert.equal(f.win.scrollY, PAGE_H - VIEW_H, "scrolled to the end of the 4000 pixel page and no further");
  f.release(300, 700);
  assert.deepEqual(f.sent().map((m) => m.rect), [{ x: 12.5, y: 3.75, w: 25, h: 96.25 }], "from y 150 to the page's bottom at 4000");
});

for (const end of ["pointercancel", "lostpointercapture", "blur"]) {
  test(`a drag the browser ends with ${end} stops the edge scroll and keeps the box it started with`, () => {
    const f = loadFrame();
    f.region();
    f.press(100, 150);
    f.move(300, 595);
    f.frames(5);
    f.fire(end, {});
    const stopped = f.win.scrollY;
    f.frames(30);
    assert.equal(f.win.scrollY, stopped, `no scrolling after ${end}`);
    f.key("Enter");
    assert.deepEqual(f.sent().map((m) => m.rect), [{ x: 40, y: 6.25, w: 20, h: 2.5 }], "the opening box at x 320, y 250, 160 by 100");
  });
}

test("dragging inside a drawn region moves it", () => {
  const f = loadFrame();
  f.region();
  f.press(400, 300);
  f.move(450, 420);
  f.release(450, 420);
  assert.deepEqual(f.sent().map((m) => m.rect), [{ x: 46.25, y: 9.25, w: 20, h: 2.5 }], "moved 50 right and 120 down from x 320, y 250 to x 370, y 370, still 160 by 100");
});

test("dragging a region's corner or edge resizes it", () => {
  const corner = loadFrame();
  corner.region();
  corner.press(480, 350);
  corner.move(520, 450);
  corner.release(520, 450);
  assert.deepEqual(corner.sent().map((m) => m.rect), [{ x: 40, y: 6.25, w: 25, h: 5 }], "the bottom-right corner from 480, 350 to 520, 450: 200 by 200 from x 320, y 250");
  const edge = loadFrame();
  edge.region();
  edge.press(400, 250);
  edge.move(400, 200);
  edge.release(400, 200);
  assert.deepEqual(edge.sent().map((m) => m.rect), [{ x: 40, y: 5, w: 20, h: 3.75 }], "the top edge from y 250 to 200: 160 by 150 from x 320, y 200");
});

test("a press inside a region without a drag keeps it", () => {
  const f = loadFrame();
  f.region();
  f.press(400, 300);
  f.release(400, 300);
  assert.deepEqual(f.sent(), []);
  f.key("Enter");
  assert.deepEqual(f.sent().map((m) => m.rect), [{ x: 40, y: 6.25, w: 20, h: 2.5 }]);
});

test("a region the host seeds with a note's box starts there, in view, and comes back unchanged", () => {
  const f = loadFrame();
  f.region({ x: 10, y: 50, w: 20, h: 5 });
  assert.ok(f.win.scrollY <= 2000 && 2200 <= f.win.scrollY + VIEW_H, `the box, page y 2000 to 2200, is in view (scrollY ${f.win.scrollY})`);
  f.key("Enter");
  assert.deepEqual(f.sent().map((m) => m.rect), [{ x: 10, y: 50, w: 20, h: 5 }]);
});

test("Shift and the down arrow grow a region past the viewport, scrolling to its bottom edge", () => {
  const f = loadFrame();
  f.region();
  for (let i = 0; i < 70; i++) f.key("ArrowDown", true);
  assert.ok(f.win.scrollY + VIEW_H >= 1050 && f.win.scrollY <= 1050, `the bottom edge, at y 250 + 100 + 70 x 10 = 1050, is in view (scrollY ${f.win.scrollY})`);
  f.key("Enter");
  assert.deepEqual(f.sent().map((m) => m.rect), [{ x: 40, y: 6.25, w: 20, h: 20 }], "800 pixels tall from y 250");
});
