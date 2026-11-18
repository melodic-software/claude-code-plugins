import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

const CHECK = join(dirname(fileURLToPath(import.meta.url)), "../lib/diagram-file-check.mjs");
const { checkExcalidraw } = await import(pathToFileURL(CHECK).href);

const scratch = mkdtempSync(join(tmpdir(), "diagram-file-check-"));
after(() => rmSync(scratch, { recursive: true, force: true }));

const box = (id, extra = {}) => ({ id, type: "rectangle", x: 0, y: 0, width: 160, height: 60, ...extra });
const label = (id, containerId, text) => ({ id, type: "text", x: 10, y: 20, width: 140, height: 20, text, containerId });
const arrow = (id, from, to) => ({ id, type: "arrow", x: 160, y: 30, width: 80, height: 0, points: [[0, 0], [80, 0]], startBinding: { elementId: from }, endBinding: { elementId: to } });
const lane = (id, name) => ({ id, type: "frame", x: -20, y: -20, width: 600, height: 120, name });
const file = (elements, top = {}) => JSON.stringify({ type: "excalidraw", version: 2, source: "https://excalidraw.com", elements, appState: {}, files: {}, ...top });

/** A two-lane swim-lane flow: every element type the skill draws, every reference resolved. */
const SWIM_LANES = [
  lane("lane-user", "User"),
  lane("lane-service", "Service"),
  box("ask", { frameId: "lane-user" }),
  label("ask-label", "ask", "Request reset"),
  box("mail", { type: "diamond", x: 240, frameId: "lane-service" }),
  label("mail-label", "mail", "Email token"),
  arrow("ask-to-mail", "ask", "mail"),
  { id: "end", type: "ellipse", x: 480, y: 0, width: 40, height: 40 },
  { id: "rule", type: "line", x: 0, y: 100, width: 600, height: 0, points: [[0, 0], [600, 0]] },
];

const problems = (text) => checkExcalidraw(text).problems;

describe("diagram-file-check", () => {
  test("a swim-lane flow with frames, bound labels and a bound arrow passes", () => {
    assert.deepEqual(checkExcalidraw(file(SWIM_LANES)), { ok: true, elements: 9, problems: [] });
  });

  test("a file the loader would not open is refused", () => {
    assert.equal(checkExcalidraw("{ not json").ok, false);
    assert.match(problems("{ not json")[0], /^not JSON/);
    assert.deepEqual(problems("[]"), ["the top level is not an object"]);
    assert.deepEqual(problems(file([box("a")], { type: "excalidrawlib" })), ['type is "excalidrawlib", not "excalidraw"']);
    assert.deepEqual(problems(file([box("a")], { version: "2" })), ["version is not a number"]);
    assert.deepEqual(problems(file([box("a")], { appState: [] })), ["appState is not an object"]);
    assert.deepEqual(problems(file(null)), ["elements is not an array"]);
    assert.deepEqual(problems(file([])), ["elements is empty"]);
  });

  test("an element the loader would drop or rewrite is refused", () => {
    assert.deepEqual(problems(file([box("a", { type: "sticky" })])), ['elements[0] (a) has type "sticky", outside rectangle, ellipse, diamond, arrow, line, text, frame']);
    assert.deepEqual(problems(file([box("a", { x: Number.NaN })])), ["elements[0] (a) has no finite x"]);
    assert.deepEqual(problems(file([box("a", { y: "10" })])), ["elements[0] (a) has no finite y"]);
    assert.deepEqual(problems(file([box("a", { width: 0, height: 0 })])), ["elements[0] (a) needs a finite width and height, not both zero"]);
    assert.deepEqual(problems(file([{ id: "l", type: "line", x: 0, y: 0, points: [[0, 0]] }])), ["elements[0] (l) needs at least two [x, y] points"]);
    assert.deepEqual(problems(file([box("a"), label("t", "a", "")])), ["elements[1] (t) has no text"]);
    assert.deepEqual(problems(file([box("a"), box("a")])), ['elements[1] repeats the id "a"']);
    assert.deepEqual(problems(file([{ type: "rectangle", x: 0, y: 0, width: 1, height: 1 }])), ["elements[0] has no string id"]);
    assert.deepEqual(problems(file([box("a", { isDeleted: true })])), ["elements[0] (a) is marked deleted"]);
  });

  test("a reference to an element that does not exist is refused", () => {
    assert.deepEqual(problems(file([box("a", { frameId: "lane-gone" })])), ['elements[0] (a) frameId names "lane-gone", which no element has']);
    assert.deepEqual(problems(file([label("t", "gone", "Hi")])), ['elements[0] (t) containerId names "gone", which no element has']);
    assert.deepEqual(problems(file([box("a"), arrow("e", "a", "b")])), ['elements[1] (e) endBinding names "b", which no element has']);
  });

  test("links and images, which reach outside the file when opened, are refused", () => {
    assert.deepEqual(problems(file([box("a", { link: "https://example.com" })])), ["elements[0] (a) carries a link"]);
    assert.deepEqual(problems(file([box("a")], { files: { f1: { dataURL: "data:image/png;base64," } } })), ["files is not empty"]);
    assert.deepEqual(problems(file([box("a", { type: "embeddable" })])), ['elements[0] (a) has type "embeddable", outside rectangle, ellipse, diamond, arrow, line, text, frame']);
  });

  test("the CLI prints one JSON line and exits 0 on pass, 1 on refusal, 2 on usage", () => {
    const run = (...args) => spawnSync(process.execPath, [CHECK, ...args], { encoding: "utf8" });
    const good = join(scratch, "flow.excalidraw");
    writeFileSync(good, file(SWIM_LANES));
    const pass = run(good);
    assert.equal(pass.status, 0);
    assert.deepEqual(JSON.parse(pass.stdout), { file: good, ok: true, elements: 9, problems: [] });

    const bad = join(scratch, "bad.excalidraw");
    writeFileSync(bad, file([]));
    const refused = run(bad);
    assert.equal(refused.status, 1);
    assert.deepEqual(JSON.parse(refused.stdout).problems, ["elements is empty"]);

    assert.equal(run().status, 2);
    assert.equal(run(join(scratch, "flow.json")).status, 2);
    assert.equal(run(join(scratch, "missing.excalidraw")).status, 2);
    assert.equal(run(join(scratch, "missing.excalidraw")).stdout, "");
  });
});
