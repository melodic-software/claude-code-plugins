import { strict as assert } from "node:assert";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import { decide, relocate, script } from "./relocate-note.mjs";

// A stand-in for the Playwright surface relocate() uses. A locator is its selector chain; the
// test says how many elements each chain matches, and which are hidden.
function world(counts, hidden = [], answer = () => undefined) {
  const calls = { evaluate: [], screenshot: [], closed: false, media: [], viewport: [], host: 0 };
  const L = (sel) => ({
    sel,
    locator: (s) => L(`${sel} >> ${s}`),
    getByTestId: (t) => L(`${sel} >> testid=${t}`),
    and: (o) => L(`(${sel}) & (${o.sel})`),
    nth: (i) => L(`${sel} >> nth=${i}`),
    count: async () => counts[sel] ?? 0,
    isVisible: async () => (counts[sel] ?? 0) === 1 && !hidden.includes(sel),
    scrollIntoViewIfNeeded: async () => { calls.shot = sel; },
    boundingBox: async () => ({ x: 100, y: 50, width: 200, height: 40 }),
  });
  const main = {}, frame = { evaluate: async (fn, arg) => { calls.evaluate.push(arg); return answer(arg); } };
  const p = {
    emulateMedia: async (o) => { calls.media.push(o); },
    setViewportSize: async (o) => { calls.viewport.push(o); },
    evaluate: async () => { calls.host++; },
    goto: async (url) => { calls.url = url; },
    waitForFunction: async () => {},
    frames: () => [main, frame],
    mainFrame: () => main,
    frameLocator: () => L("frame"),
    locator: () => ({ boundingBox: async () => ({ x: 0, y: 0, width: 960, height: 800 }) }),
    screenshot: async (o) => { calls.screenshot.push(o); },
    close: async () => { calls.closed = true; },
  };
  return { page: { context: () => ({ newPage: async () => p }) }, calls };
}

const ROOT = "frame >> :root";
const B = `${ROOT} >> [data-variant="B"]`;
const S = `${B} >> [data-screen-state="empty"]`;
const PATH = `${S} >> :scope > div:nth-of-type(1) > article:nth-of-type(2)`;
const CARDS = `${S} >> testid=shipments-parcel-card`;
const note = {
  kind: "element",
  variant: { key: "B" },
  state: { key: "empty" },
  content: "worst",
  anchor: { testid: "shipments-parcel-card", testidIndex: 1, tag: "article", cssPath: "div:nth-of-type(1) > article:nth-of-type(2)" },
  rect: { x: 10, y: 20, w: 30, h: 5 },
  text: "Make this card taller.",
};
const input = (n = note) => ({ seq: 3, url: "http://127.0.0.1:4100/", note: n, shot: "/run/shots/3.png" });
const run = async (counts, n = note, hidden = [], answer = undefined) => {
  const w = world(counts, hidden, answer);
  return { out: JSON.parse(await relocate(w.page, input(n), decide)), calls: w.calls };
};
const scoped = { [B]: 1, [S]: 1, [`${ROOT}[data-vs-content="worst"]`]: 1 };

test("decide: the first rung that hits matches", () => {
  assert.deepEqual(decide([{ rung: "testid", hit: true }, { rung: "cssPath", hit: true }]), { matched: "testid", confirmed: true });
});
test("decide: a weaker rung after a broken stronger one matches unconfirmed", () => {
  assert.deepEqual(decide([{ rung: "testid", hit: false, broken: true }, { rung: "cssPath", hit: true }]), { matched: "cssPath", confirmed: false });
});
test("decide: an ambiguous stronger rung does not demote a weaker match", () => {
  assert.deepEqual(decide([{ rung: "role", hit: false, broken: false }, { rung: "cssPath", hit: true }]), { matched: "cssPath", confirmed: true });
});
test("decide: no rung hits", () => {
  assert.deepEqual(decide([{ rung: "testid", hit: false, broken: true }, { rung: "cssPath", hit: false, broken: true }]), { matched: null, confirmed: false });
});

test("restores the view, matches the test id's nth element in the scope and shoots it inside the frame", async () => {
  const { out, calls } = await run({ ...scoped, [CARDS]: 2, [`${CARDS} >> nth=1`]: 1, [`(${CARDS} >> nth=1) & (frame >> article)`]: 1, [PATH]: 1 });
  assert.deepEqual(calls.evaluate[0], { variant: "B", state: "empty", content: "worst" });
  assert.equal(calls.url, "http://127.0.0.1:4100/");
  assert.deepEqual(out.restored, { variant: true, state: true, content: true });
  assert.deepEqual(out.rungs.map((r) => [r.rung, r.candidates, r.hit]), [["testid", 2, true], ["cssPath", 1, true]]);
  assert.equal(out.matched, "testid");
  assert.equal(out.confirmed, true);
  assert.equal(out.positionOnly, false);
  assert.equal(calls.screenshot.length, 1);
  assert.equal(calls.screenshot[0].path, "/run/shots/3.png");
  assert.match(calls.screenshot[0].style, /\.vs \{ visibility: hidden/);
  assert.deepEqual(calls.screenshot[0].clip, { x: 100, y: 50, width: 200, height: 40 });
  assert.equal(calls.closed, true);
});

test("the scope itself carrying the test id is its first match", async () => {
  const self = `(${S}) & (frame >> testid=shipments-parcel-card)`;
  const n = { ...note, anchor: { ...note.anchor, testidIndex: 0, tag: "div", cssPath: "" } };
  const { out } = await run({ ...scoped, [self]: 1, [CARDS]: 2, [`(${S}) & (frame >> div)`]: 1 }, n);
  assert.deepEqual(out.rungs[0], { rung: "testid", candidates: 3, hit: true, broken: false });
  assert.equal(out.matched, "testid");
});

test("a test id on an ancestor: the path finds the noted element inside it", async () => {
  const n = { ...note, anchor: { ...note.anchor, tag: "strong", cssPath: "div:nth-of-type(1) > article:nth-of-type(2) > strong:nth-of-type(1)" } };
  const path = `${S} >> :scope > ${n.anchor.cssPath}`;
  const { out, calls } = await run({ ...scoped, [CARDS]: 2, [path]: 1, [`(${path}) & (${CARDS} >> nth=1 >> *)`]: 1 }, n);
  assert.equal(out.matched, "testid");
  assert.equal(out.container, undefined);
  assert.equal(calls.shot, path);
});

test("a test id on an ancestor with the noted element's own tag: the path, not the ancestor, is shot", async () => {
  const n = { ...note, anchor: { ...note.anchor, tag: "div", cssPath: "div:nth-of-type(1) > div:nth-of-type(2) > div:nth-of-type(1)" } };
  const path = `${S} >> :scope > ${n.anchor.cssPath}`;
  const t = `${CARDS} >> nth=1`;
  const { out, calls } = await run({ ...scoped, [CARDS]: 2, [t]: 1, [`(${t}) & (frame >> div)`]: 1, [path]: 1, [`(${path}) & (${t} >> *)`]: 1 }, n);
  assert.equal(out.matched, "testid");
  assert.equal(out.confirmed, true);
  assert.equal(out.container, undefined);
  assert.equal(calls.shot, path);
});

test("a role attribute with several tokens is found by its first token", async () => {
  const n = { ...note, anchor: { tag: "a", role: "button", cssPath: "a:nth-of-type(9)" } };
  const r = `${S} >> a[role~="button"]`;
  const { out, calls } = await run({ ...scoped, [r]: 1 }, n);
  assert.deepEqual(out.rungs[0], { rung: "role", candidates: 1, hit: true, broken: false });
  assert.equal(out.matched, "role");
  assert.equal(calls.shot, r);
});

test("a test id on an ancestor whose path finds nothing: the ancestor stands in, unconfirmed", async () => {
  const n = { ...note, anchor: { ...note.anchor, tag: "strong", cssPath: "div:nth-of-type(1) > article:nth-of-type(2) > strong:nth-of-type(1)" } };
  const t = `${CARDS} >> nth=1`;
  const { out, calls } = await run({ ...scoped, [CARDS]: 2, [t]: 1 }, n);
  assert.equal(out.matched, "testid");
  assert.equal(out.container, true);
  assert.equal(out.confirmed, false);
  assert.equal(calls.screenshot.length, 1);
});

test("a test id that is gone: the path still matches, unconfirmed", async () => {
  const { out } = await run({ ...scoped, [PATH]: 1 });
  assert.deepEqual(out.rungs.map((r) => [r.rung, r.candidates, r.hit]), [["testid", 0, false], ["cssPath", 1, true]]);
  assert.equal(out.matched, "cssPath");
  assert.equal(out.confirmed, false);
});

test("an index past the last match is broken", async () => {
  const { out } = await run({ ...scoped, [CARDS]: 1 });
  assert.deepEqual(out.rungs[0], { rung: "testid", candidates: 1, hit: false, broken: true });
});

test("role runs between the test id and the path; an ambiguous role does not demote the path", async () => {
  const n = { ...note, anchor: { tag: "article", role: "listitem", cssPath: note.anchor.cssPath } };
  const { out } = await run({ ...scoped, [`${S} >> article[role~="listitem"]`]: 2, [PATH]: 1 }, n);
  assert.deepEqual(out.rungs.map((r) => r.rung), ["role", "cssPath"]);
  assert.equal(out.matched, "cssPath");
  assert.equal(out.confirmed, true);
});

test("nothing found: the stored box is shot, labeled position only", async () => {
  const { out, calls } = await run({ ...scoped, [`frame >> [data-relocate-position]`]: 1 });
  assert.equal(out.matched, null);
  assert.equal(out.positionOnly, true);
  assert.deepEqual(calls.evaluate[1], note.rect);
  assert.equal(calls.screenshot.length, 1);
});

test("nothing found and no stored box: no shot", async () => {
  const { rect: _r, ...n } = note;
  const { out, calls } = await run(scoped, n);
  assert.equal(out.positionOnly, false);
  assert.equal(calls.screenshot.length, 0);
});

test("a variant the page no longer has: nothing in it is searched", async () => {
  const { out } = await run({ [CARDS]: 2, [PATH]: 1 });
  assert.equal(out.restored.variant, false);
  assert.ok(out.rungs.every((r) => r.candidates === 0));
});

test("a matched element that is hidden is reported, not shot", async () => {
  const t = `${CARDS} >> nth=1`;
  const { out, calls } = await run({ ...scoped, [CARDS]: 2, [`(${t}) & (frame >> article)`]: 1, [t]: 1 }, note, [t]);
  assert.equal(out.hidden, true);
  assert.equal(calls.screenshot.length, 0);
});

const QUOTE = { exact: "PT-1057", prefix: "Row 58 ", suffix: " Delayed" };
const textNote = { ...note, kind: "text", anchor: { ...note.anchor, textQuote: QUOTE } };
const QUOTED = "frame >> [data-relocate-quote]";
// The frame helper's answers: the quote's match count, the replay's missed steps.
const helper = (quotes, missed = 0) => (arg) => (arg?.quote ? quotes : Array.isArray(arg) ? missed : undefined);
const hitAll = { ...scoped, [CARDS]: 2, [`${CARDS} >> nth=1`]: 1, [`(${CARDS} >> nth=1) & (frame >> article)`]: 1, [PATH]: 1, [QUOTED]: 1 };

test("the text quote is the rung after the path, and reaches the frame only as an argument", async () => {
  const { out, calls } = await run(hitAll, textNote, [], helper(1));
  assert.deepEqual(out.rungs.map((r) => [r.rung, r.candidates, r.hit]), [["testid", 2, true], ["cssPath", 1, true], ["textQuote", 1, true]]);
  assert.deepEqual(calls.evaluate[1], { variant: "B", state: "empty", quote: QUOTE });
  assert.equal(out.matched, "testid");
  assert.equal(out.confirmed, true);
  assert.equal(out.quoteMissing, undefined);
});

test("a text note whose element is found but whose quote is not is unconfirmed", async () => {
  const { out } = await run(hitAll, textNote, [], helper(0));
  assert.equal(out.matched, "testid");
  assert.equal(out.quoteMissing, true);
  assert.equal(out.confirmed, false);
});

test("with the test id and path broken, the quote finds the text, unconfirmed", async () => {
  const { out, calls } = await run({ ...scoped, [QUOTED]: 1 }, textNote, [], helper(1));
  assert.equal(out.matched, "textQuote");
  assert.equal(out.confirmed, false);
  assert.equal(calls.shot, QUOTED);
});

test("a quote found twice is ambiguous: no hit, not broken", async () => {
  const { out } = await run(hitAll, textNote, [], helper(2));
  assert.deepEqual(out.rungs.at(-1), { rung: "textQuote", candidates: 2, hit: false, broken: false });
  assert.equal(out.confirmed, true);
});

test("the data log replays after the view is shown, and a missed step is reported", async () => {
  const log = [{ op: "seed", n: 100 }, { op: "toggle", name: "filter" }];
  const n = { ...note, data: { log } };
  let r = await run(hitAll, n, [], helper(0, 0));
  assert.deepEqual(r.calls.evaluate[0], { variant: "B", state: "empty", content: "worst" });
  assert.deepEqual(r.calls.evaluate[1], log);
  assert.equal(r.out.restored.data, true);
  r = await run(hitAll, n, [], helper(0, 1));
  assert.equal(r.out.restored.data, false);
  r = await run(hitAll, n, [], helper(0, -1));
  assert.equal(r.out.restored.data, false, "no frame helper");
});

test("content flips in the log replay in order, and the note's content set is shown last", async () => {
  const log = [{ op: "seed", n: 10 }, { op: "content", name: "worst" }, { op: "seed", n: 10 }];
  const { calls } = await run(hitAll, { ...note, data: { log } }, [], helper(0, 0));
  assert.equal(calls.evaluate[0].content, undefined);
  assert.deepEqual(calls.evaluate[1], log);
  assert.deepEqual(calls.evaluate[2], { content: "worst" });
});

test("the note's viewport sets the page size, color scheme and motion before the page loads", async () => {
  const viewport = { w: 700, h: 500, dpr: 2, scrollX: 0, scrollY: 40, colorScheme: "dark", reducedMotion: true };
  const { out, calls } = await run(hitAll, { ...note, viewport });
  assert.deepEqual(calls.media, [{ colorScheme: "dark", reducedMotion: "reduce" }]);
  assert.deepEqual(calls.viewport, [{ width: 700, height: 500 }]);
  assert.equal(calls.host, 1);
  assert.equal(out.restored.viewport, true);
  const plain = await run(hitAll);
  assert.deepEqual([plain.calls.media, plain.calls.viewport, plain.calls.host], [[], [], 0]);
  assert.equal(plain.out.restored.viewport, undefined);
});

test("a region's shot is the box the person drew, position only when its anchor is gone", async () => {
  const region = { ...note, kind: "region", elements: [] };
  const box = `frame >> [data-relocate-position]`;
  let r = await run({ ...hitAll, [box]: 1 }, region);
  assert.equal(r.out.matched, "testid");
  assert.equal(r.out.region, true);
  assert.equal(r.out.positionOnly, false);
  assert.equal(r.calls.shot, box);
  assert.deepEqual(r.calls.evaluate.at(-1), note.rect);
  r = await run({ ...scoped, [box]: 1 }, region);
  assert.equal(r.out.matched, null);
  assert.equal(r.out.positionOnly, true);
});

test("the script carries its input as one JSON literal, whatever the note's text holds", async () => {
  const text = 'x"); process.exit(1); //${1}$&$\'` </script>';
  const i = input({ ...note, text });
  const src = script(i);
  assert.ok(src.includes(JSON.stringify(i)));
  const fn = vm.runInNewContext(src);
  const w = world({ ...scoped, [PATH]: 1 });
  const out = JSON.parse(await fn(w.page));
  assert.equal(out.seq, 3);
  // The detail object comes from the vm's realm, so compare its JSON.
  assert.equal(JSON.stringify(w.calls.evaluate[0]), JSON.stringify({ variant: "B", state: "empty", content: "worst" }));
});

const cli = fileURLToPath(new URL("./relocate-note.mjs", import.meta.url));
const runCli = (args) => {
  try {
    return { code: 0, out: execFileSync(process.execPath, [cli, ...args], { encoding: "utf8", stdio: "pipe" }) };
  } catch (e) {
    return { code: e.status, out: String(e.stderr) };
  }
};

test("the command writes the script and names the shot from the seq alone", () => {
  const d = mkdtempSync(join(tmpdir(), "relocate-"));
  try {
    writeFileSync(join(d, "actions.json"), JSON.stringify({ seq: 3, events: [{ seq: 3, at: "2026-11-13T00:00:00Z", deliveredAt: "x", ...note }] }));
    const r = runCli(["--dir", d, "--seq", "3", "--url", "http://127.0.0.1:4100/"]);
    assert.equal(r.code, 0, r.out);
    const out = JSON.parse(r.out);
    assert.equal(out.shot, join(d, "shots", "3.png"));
    assert.ok(readFileSync(out.script, "utf8").includes(JSON.stringify(note)));
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test("the command refuses a bad seq, a foreign url, a missing note and a note outside the contract", () => {
  const d = mkdtempSync(join(tmpdir(), "relocate-"));
  try {
    writeFileSync(join(d, "actions.json"), JSON.stringify({ seq: 1, events: [{ seq: 1, ...note, label: "Export" }] }));
    const url = "http://127.0.0.1:4100/";
    assert.equal(runCli(["--dir", d, "--seq", "../1", "--url", url]).code, 2);
    assert.equal(runCli(["--dir", d, "--seq", "1", "--url", "https://example.com/"]).code, 2);
    assert.equal(runCli(["--dir", d, "--seq", "2", "--url", url]).code, 2);
    assert.match(runCli(["--dir", d, "--seq", "1", "--url", url]).out, /outside the note contract/);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});
