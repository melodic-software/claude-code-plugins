import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { buildRating, coverageRow, main, unreadParts } from "./write-rating.mjs";

const HEAD = "a".repeat(40);
const row = (level, extra = {}) => ({ area: "Impact", level, why: "w", check: "agreed", checker_level: "", checker: "", ...extra });
const result = (extra = {}) => ({ pr: 7, head: HEAD, risks: [row("LOW"), row("MEDIUM", { check: "disputed", checker_level: "HIGH", checker: "c" })], demote: false, ...extra });
const messages = (extra = {}) => [
  { type: "assistant", parent_tool_use_id: null, message: { model: "claude-opus-5-5" } },
  { type: "assistant", parent_tool_use_id: "toolu_1", message: { model: "claude-opus-5-5" } },
  { type: "result", structured_output: result(), permission_denials: [], ...extra },
];

test("buildRating recomputes max and demote and adds the rubric, models and times", () => {
  const rating = buildRating({ output: result(), messages: messages(), pr: 7, head: HEAD, rubric: "8.0.0", cliVersion: "2.1.312", startedAt: 100, endedAt: 160 });
  assert.equal(rating.max, "HIGH");
  assert.equal(rating.demote, true);
  assert.equal(rating.rubric, "8.0.0");
  assert.equal(rating.rater, "claude-opus-5-5");
  assert.equal(rating.checker, "claude-opus-5-5");
  assert.equal(rating.cli_version, "2.1.312");
  assert.equal(rating.started_at, "1970-01-01T00:01:40.000Z");
  assert.equal(rating.ended_at, "1970-01-01T00:02:40.000Z");
});

test("buildRating refuses a run with a permission denial, a bad rubric or a result for another head", () => {
  const base = { output: result(), messages: messages(), pr: 7, head: HEAD, rubric: "8.0.0", cliVersion: "2.1.312", startedAt: 1, endedAt: 2 };
  assert.throws(() => buildRating({ ...base, messages: messages({ permission_denials: [{ tool_name: "Read" }] }) }), /denial/);
  assert.throws(() => buildRating({ ...base, messages: messages({ permission_denials: [{ tool_name: "Grep" }, { tool_name: "WebFetch" }] }) }), /1 permission denial/);
  assert.equal(buildRating({ ...base, messages: messages({ permission_denials: [{ tool_name: "Bash" }, { tool_name: "Grep" }] }) }).max, "HIGH");
  assert.throws(() => buildRating({ ...base, rubric: "eight" }), /rubric/);
  assert.throws(() => buildRating({ ...base, output: result({ head: "b".repeat(40) }) }), /head/);
  assert.throws(() => buildRating({ ...base, cliVersion: "latest; rm" }), /CLI version/);
});

test("main writes rating.json only for a good result, and fails red otherwise", () => {
  const dir = tempDir("write-rating-");
  const write = (name, value) => {
    const file = join(dir, name);
    writeFileSync(file, typeof value === "string" ? value : JSON.stringify(value));
    return file;
  };
  const env = {
    OUTPUT_FILE: write("output.json", result()),
    EXECUTION_FILE: write("execution.json", messages()),
    PLUGIN_MANIFEST: write("plugin.json", { name: "review", version: "8.0.0" }),
    PR_NUMBER: "7",
    HEAD_SHA: HEAD,
    CLI_VERSION: "2.1.312",
    STARTED_AT: "100",
    OUT_DIR: join(dir, "out"),
    COVERAGE_FILE: write("coverage.json", { parts: [], left_out: { chunks: 0, bytes: 0, files: 0 } }),
  };
  assert.equal(main(env, () => 160_000), 0);
  const rating = JSON.parse(readFileSync(join(dir, "out", "rating.json"), "utf8"));
  assert.equal(rating.max, "HIGH");
  assert.equal(rating.pr, 7);
  assert.equal(main({ ...env, OUTPUT_FILE: write("bad.json", "{"), OUT_DIR: join(dir, "out2") }, () => 1), 1);
  assert.equal(main({ ...env, HEAD_SHA: "nope", OUT_DIR: join(dir, "out3") }, () => 1), 1);
  assert.equal(main({ ...env, OUTPUT_FILE: "", OUT_DIR: join(dir, "out4") }, () => 1), 1);
  assert.equal(main({ ...env, COVERAGE_FILE: "", OUT_DIR: join(dir, "out5") }, () => 1), 1, "no coverage list, no rating");
});

const PARTS = [
  { path: "/w/data/diff/chunk-1/part-001.patch", lines: 1000 },
  { path: "/w/data/diff/chunk-2/part-001.patch", lines: 40 },
  { path: "/w/data/diff/chunk-2/part-002.patch", lines: 0 },
];
const readCall = (id, input, parent = null) => ({ type: "assistant", parent_tool_use_id: parent, message: { model: "claude-opus-5-5", content: [{ type: "tool_use", id, name: "Read", input }] } });
const readResult = (id, isError, parent = null) => ({ type: "user", parent_tool_use_id: parent, message: { content: [{ type: "tool_result", tool_use_id: id, is_error: isError, content: "..." }] } });
const allRead = [
  readCall("r1", { file_path: PARTS[0].path }, "toolu_a"),
  readResult("r1", false, "toolu_a"),
  readCall("r2", { file_path: PARTS[1].path, offset: 1, limit: 40 }, "toolu_b"),
  readCall("r3", { file_path: PARTS[2].path }),
];

test("unreadParts counts a part read whole from its first line in any thread, and nothing less", () => {
  assert.deepEqual(unreadParts(allRead, PARTS), []);
  assert.deepEqual(unreadParts([readCall("x", { file_path: PARTS[0].path, offset: 500 }), readCall("y", { file_path: PARTS[1].path, limit: 39 })], PARTS), PARTS, "a read from line 500, one line short, and no read at all");
  assert.deepEqual(unreadParts([...allRead, readResult("r2", true, "toolu_b")], PARTS), [PARTS[1]], "a Read whose result is an error read nothing");
  assert.deepEqual(unreadParts([readCall("g", { file_path: PARTS[0].path }), { ...readCall("h", {}), message: { content: [{ type: "tool_use", id: "h", name: "Grep", input: { file_path: PARTS[1].path } }] } }], PARTS), [PARTS[1], PARTS[2]]);
});

test("a rating that did not read the whole diff gains a HIGH Diff coverage row and demotes, even when every row is LOW", () => {
  const low = result({ risks: [row("LOW"), row("LOW", { area: "Reversibility" })] });
  const base = { output: low, pr: 7, head: HEAD, rubric: "8.0.0", cliVersion: "2.1.312", startedAt: 1, endedAt: 2 };
  const whole = buildRating({ ...base, messages: [...messages(), ...allRead], coverage: { parts: PARTS, left_out: { chunks: 0, bytes: 0, files: 0 } } });
  assert.equal(whole.max, "LOW");
  assert.equal(whole.demote, false);
  assert.equal(whole.risks.length, 2);
  const partial = buildRating({ ...base, messages: [...messages(), ...allRead.slice(0, 2)], coverage: { parts: PARTS, left_out: { chunks: 0, bytes: 0, files: 0 } } });
  assert.equal(partial.max, "HIGH");
  assert.equal(partial.demote, true);
  assert.deepEqual(
    partial.risks.map(({ area, level, check }) => [area, level, check]),
    [
      ["Impact", "LOW", "agreed"],
      ["Reversibility", "LOW", "agreed"],
      ["Diff coverage", "HIGH", "unchecked"],
    ],
  );
  assert.match(partial.risks[2].why, /2 of 3 diff parts were never read/);
  const leftOut = buildRating({ ...base, messages: [...messages(), ...allRead], coverage: { parts: PARTS, left_out: { chunks: 4, bytes: 1_200_000, files: 90 } } });
  assert.equal(leftOut.demote, true);
  assert.match(leftOut.risks.at(-1).why, /4 chunk\(s\) of the diff \(1200000 bytes\)/);
  assert.deepEqual(coverageRow(allRead, { parts: PARTS, left_out: { chunks: 0 } }), undefined);
});
