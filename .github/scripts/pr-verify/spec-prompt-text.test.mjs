// spec-prompt.md carries the chunk verifiers' spec rules word for word, so a
// final judge cannot read the spec more loosely than a chunk does.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const flat = (name) => readFileSync(new URL(name, import.meta.url), "utf8").replace(/\s+/g, " ");
const spec = flat("./spec-prompt.md");
const chunk = flat("./prompt.md");

test("the final judge reads the spec under the chunk verifiers' words", () => {
  for (const rule of [
    "Only `person_checks` excuses an item; a refinement comment's Split section never does.",
    "A `body` of null means the issue has no trusted spec text: say so, and return `fail` when no issue has any.",
  ]) {
    assert.ok(chunk.includes(rule), rule);
    assert.ok(spec.includes(rule), rule);
  }
});

test("the final judge is told what a cut leaves out", () => {
  assert.match(spec, /`notes_left_out` above 0/);
  assert.match(spec, /a long list ends with a count of the files it leaves out/);
});

test("a chunk verifier is told to read across chunks, and no text says it cannot", () => {
  const note = flat("./chunk-note.md");
  assert.match(note, /Read that part whole and judge both sides/);
  assert.doesNotMatch(note, /no one verifier sees both sides|You have not seen/);
  assert.doesNotMatch(chunk, /A read of any other path is denied/);
  assert.doesNotMatch(flat("./chunk-diff.sh"), /reads only its own parts/);
});
