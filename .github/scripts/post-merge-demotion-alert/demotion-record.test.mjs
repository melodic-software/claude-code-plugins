import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { KINDS, parseRecordMarker, recordMarker, recordPrefix, SIGNALS } from "./demotion-record.mjs";

const VECTORS = JSON.parse(readFileSync(new URL("./demotion-record.vectors.json", import.meta.url), "utf8"));
const HANDOFF = fileURLToPath(new URL("./handoff.bash", import.meta.url));
const SOURCES = {
  "handoff.bash": readFileSync(HANDOFF, "utf8"),
  "post-merge-file-demotion-issues.yml": readFileSync(new URL("../../workflows/post-merge-file-demotion-issues.yml", import.meta.url), "utf8"),
};
const LINES = [...VECTORS.markers.map((v) => v.line), ...VECTORS.not_markers.map((v) => v.line)];

test("each record vector formats to its line and parses back to its kind, SHA and signal", () => {
  assert.ok(VECTORS.markers.length > 0);
  for (const { name, kind, sha, signal, line } of VECTORS.markers) {
    assert.equal(recordMarker(kind, sha, signal), line, name);
    assert.deepEqual(parseRecordMarker(line), { kind, sha, signal }, name);
    assert.ok(line.startsWith(recordPrefix(kind, sha)), name);
  }
});

test("each non-record vector parses to null", () => {
  assert.ok(VECTORS.not_markers.length > 0);
  for (const { name, line } of VECTORS.not_markers) assert.equal(parseRecordMarker(line), null, name);
  assert.equal(parseRecordMarker(undefined), null);
});

test("every whole record marker the inline workflow and handoff.bash write parses as a record", () => {
  const sha = VECTORS.markers[0].sha;
  const written = Object.entries(SOURCES).flatMap(([file, text]) =>
    [...text.matchAll(/<!-- ([a-z-]+) sha=\$\{?\w+\}? signal=(\$\{?\w+\}?|[a-z-]+) -->/g)].map((m) => ({ file, ...m })),
  );
  assert.ok(KINDS.every((kind) => written.some((m) => m[1] === kind)), "the workflow writes each kind");
  for (const m of written) {
    for (const signal of m[2].startsWith("$") ? SIGNALS : [m[2]]) {
      const line = m[0].replace(/sha=\$\{?\w+\}?/, `sha=${sha}`).replace(/signal=\S+/, `signal=${signal}`);
      assert.deepEqual(parseRecordMarker(line), { kind: m[1], sha, signal }, `${m.file}: ${m[0]}`);
    }
  }
});

test("the workflow's record prefixes, kind alternations and signal alternations name only record kinds and signals", () => {
  for (const [file, text] of Object.entries(SOURCES)) {
    for (const [, kind] of text.matchAll(/"<!-- ([a-z-]*merge-(?:demotion|failure)[a-z-]*) "/g)) {
      assert.ok(KINDS.includes(kind), `${file}: prefix ${kind}`);
    }
    for (const [, group] of text.matchAll(/\(((?:[a-z-]+\|)+[a-z-]+)\)\\? sha=/g)) {
      assert.deepEqual(group.split("|").sort(), [...KINDS].sort(), `${file}: ${group}`);
    }
    for (const [, group] of text.matchAll(/signal=\(((?:[a-z-]+\|)*[a-z-]+)\)/g)) {
      assert.ok(group.split("|").every((s) => SIGNALS.includes(s)), `${file}: ${group}`);
    }
  }
});

test("each bash record regex matches a vector line exactly when it is a record of a signal the regex names", () => {
  const regexes = Object.entries(SOURCES).flatMap(([file, text]) => [...text.matchAll(/=~ (\^\\<!--\\ [^\n]*?signal=\([^\n]*?\$) \]\]/g)].map((m) => ({ file, re: m[1] })));
  assert.deepEqual(new Set(regexes.map((r) => r.file)), new Set(Object.keys(SOURCES)));
  for (const { file, re } of regexes) {
    const named = /signal=\(([^)]*)\)/.exec(re)[1].split("|");
    for (const line of LINES) {
      const record = parseRecordMarker(line);
      const run = spawnSync("bash", ["-c", `[[ $1 =~ ${re} ]]`, "_", line]);
      assert.equal(run.status === 0, record !== null && named.includes(record.signal), `${file}: ${JSON.stringify(line)}`);
    }
  }
});

test("handoff.bash refuses a fix-issue check name that carries a record kind", () => {
  const ok = (name) => spawnSync("bash", ["-c", '. "$1"; fix_name_ok "$2"', "_", HANDOFF, name]).status;
  assert.equal(ok("Test Bash"), 0);
  for (const kind of KINDS) assert.notEqual(ok(`Test ${kind} job`), 0, kind);
});
