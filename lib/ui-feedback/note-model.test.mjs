import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { problems, valid } from "./note-model.mjs";

const read = (name) => JSON.parse(readFileSync(new URL(name, import.meta.url), "utf8"));
const schema = read("./note.schema.json");
const fixtures = read("./fixtures/notes.json");

for (const { why, note } of fixtures.valid) {
  test(`accepts: ${why}`, () => assert.deepEqual(problems(note, schema), []));
}
for (const { why, note } of fixtures.invalid) {
  test(`refuses: ${why}`, () => assert.equal(valid(note, schema), false));
}

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
});
