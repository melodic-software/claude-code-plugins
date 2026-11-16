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
