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

test("both judges excuse an owner-marked item only through person_checks", () => {
  for (const rule of [
    "An issue's `person_checks` lists done-when items of its `body` that the refinement records, or that its owner marks with `Person check:`, as checks a person runs",
    "An item marked `Person check:` that `person_checks` does not list is judged like any other.",
    "When an issue's `person_checks` is not empty, return `pass-notes`, never `pass`, with one note per item naming it as a person check and the evidence the pull request body offers for it, or that it offers none.",
  ]) {
    assert.ok(chunk.includes(rule), `prompt.md: ${rule}`);
    assert.ok(spec.includes(rule), `spec-prompt.md: ${rule}`);
  }
});

test("a refs pull request fails on no delivered part or a whole-issue claim, never on unnamed remaining work, under either judge", () => {
  assert.ok(chunk.includes("Return `fail`, saying why, when the body names no delivered part or claims to deliver the whole issue"));
  assert.ok(spec.includes("return `fail` when it names no delivered part or claims the whole issue."));
  for (const text of [chunk, spec]) assert.ok(!/names no remaining work|no remaining work, or claims|must name what remains/.test(text));
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

test("every judge of a chunked head is told a file larger than one chunk comes in pieces", () => {
  const note = flat("./chunk-note.md");
  assert.doesNotMatch(note, /each file whole,/);
  for (const text of [note, spec]) assert.match(text, /cut at its hunks into pieces in different chunks/);
  for (const text of [note, spec]) assert.ok(text.includes("`piece <i> of <n>`"));
  assert.match(note, /the file's other hunks are in the parts its other pieces name/);
});
