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
    "Only `person_checks` and `credited_siblings` excuse an item; a refinement comment's Split section never does, nor does this pull request's body, a sibling it names that has no entry there included.",
    "A `body` of null means the issue has no trusted spec text: say so, and return `fail` when no issue has any.",
  ]) {
    assert.ok(chunk.includes(rule), rule);
    assert.ok(spec.includes(rule), rule);
  }
});

test("a refs pull request that names no remaining work fails, under either judge", () => {
  assert.ok(chunk.includes("Return `fail`, saying why, when the body names no delivered part, names no remaining work or claims to deliver the whole issue"));
  assert.ok(spec.includes("return `fail` when it names no delivered part or no remaining work, or claims the whole issue."));
});

test("a refs pull request for a main-red incident needs no remaining work, under either judge", () => {
  const rule =
    "A `refs` entry with `source` `main-red-incident` is the exception: fixing the failing check's cause is the whole delivery and the monitoring lane closes the issue itself, so judge the diff against its whole `body` and require no remaining work.";
  assert.ok(chunk.includes(rule), "prompt.md carries the main-red exception");
  assert.ok(spec.includes(rule), "spec-prompt.md carries the main-red exception");
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

test("every verifier leads a note on the pull request body, and only such a note, with `PR body`", () => {
  const rule =
    "A note about the pull request body, its description text and not a file in the diff, starts with `PR body`; a note about anything else, an undelivered item, a correctness bug or a missing test included, never starts with `PR body`.";
  for (const [name, text] of [["prompt.md", chunk], ["spec-prompt.md", spec], ["chunk-note.md", flat("./chunk-note.md")]]) {
    assert.ok(text.includes(rule), `${name} carries the body-note rule`);
  }
});

test("a chunk verifier is told to read across chunks, and no text says it cannot", () => {
  const note = flat("./chunk-note.md");
  assert.match(note, /Read that part whole and judge both sides/);
  assert.doesNotMatch(note, /no one verifier sees both sides|You have not seen/);
  assert.doesNotMatch(chunk, /A read of any other path is denied/);
  assert.match(chunk, /a `pass` or `pass-notes` that skips a part, or reads one in pieces, is void/);
  assert.doesNotMatch(flat("./chunk-diff.sh"), /reads only its own parts/);
});
