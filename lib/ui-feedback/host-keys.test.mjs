import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const HOST = readFileSync(new URL("./host.html", import.meta.url), "utf8");
const start = HOST.indexOf('document.addEventListener("keydown"');
const HANDLER = HOST.slice(start, HOST.indexOf("\n  });", start));
const ACTIONS = {
  dock: "setPanel(",
  markers: "setMarkers(",
  pick: '"element"',
  region: '"region"',
  move: '"move"',
  quote: "askText(",
};

function branch(key) {
  return HANDLER.split("\n").filter((line) => line.includes(`key === "${key}"`));
}

test("no two shortcut branches share a key", () => {
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
