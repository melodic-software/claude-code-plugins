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

test("nothing a chunk reports is cut from the final judge", () => {
  assert.doesNotMatch(spec, /notes_left_out|A cut can hide/);
  for (const text of [spec, flat("./chunk-note.md")]) assert.doesNotMatch(text, /leaves? (it |the path )?out|a count of the files/);
});

test("a verifier is told every line is readable, so no prose or data part is passed unread", () => {
  assert.match(chunk, /`\\ continued:`/);
  assert.doesNotMatch(chunk, /line cut short/);
  // A binary lockfile or compiled code still fails; an image does not.
  assert.ok(chunk.includes("a workflow, an action, a script, a hook, compiled code or a library, or a file a workflow, script or hook runs"));
  assert.match(chunk, /takes the side of the line it continues/);
  assert.match(chunk, /a package or plugin manifest, a lockfile, or agent or skill instructions/);
});

test("a denied read voids only a pass, and a refs judgment reads the context whole", () => {
  for (const text of [chunk, spec]) {
    assert.match(text, /a denied read voids a `pass` or `pass-notes`/);
    assert.doesNotMatch(text, /a denied read voids the verdict/);
  }
  assert.match(spec, /When an entry's `spec_kind` is `refs`, it is listed whole/);
});

test("a chunk verifier is told to read across chunks, and no text says it cannot", () => {
  const note = flat("./chunk-note.md");
  assert.match(note, /Read that part whole and judge both sides/);
  assert.doesNotMatch(note, /no one verifier sees both sides|You have not seen/);
  assert.doesNotMatch(chunk, /A read of any other path is denied/);
  assert.match(chunk, /a `pass` or `pass-notes` that skips a part, or reads one in pieces, is void/);
  assert.doesNotMatch(flat("./chunk-diff.sh"), /reads only its own parts/);
});
