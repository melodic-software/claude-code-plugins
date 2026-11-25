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

const RECORDED = JSON.parse(readFileSync(new URL("./fixtures/recorded-execution.json", import.meta.url), "utf8"));
const DIFF = "/workspace/lane/pr.diff";
const MAIN_RESULT = 1;
const SUB_RESULT = 4;
const part = (lines) => ({ path: DIFF, lines });
const recorded = (edit = () => {}) => {
  const copy = structuredClone(RECORDED);
  edit(copy);
  return copy;
};

test("a recorded run's main-thread Read of lines 1-8 and subagent Read of 9-16 cover 16 lines of the 18-line file, not all 18", () => {
  assert.deepEqual(unreadParts(RECORDED, [part(8)]), []);
  assert.deepEqual(unreadParts(RECORDED, [part(16)]), []);
  assert.deepEqual(unreadParts(RECORDED, [part(18)]), [part(18)], "lines 17-18 were never read");
});

test("a Read with no result, an error result, or a result in another thread reads nothing", () => {
  const noMainResult = recorded((m) => m.splice(MAIN_RESULT, 1));
  assert.deepEqual(unreadParts(noMainResult, [part(8)]), [part(8)], "the main thread's Read has no result");
  const noSubResult = recorded((m) => m.splice(SUB_RESULT, 1));
  assert.deepEqual(unreadParts(noSubResult, [part(16)]), [part(16)], "the subagent's Read has no result");
  const failed = recorded((m) => (m[MAIN_RESULT].message.content[0].is_error = true));
  assert.deepEqual(unreadParts(failed, [part(8)]), [part(8)]);
  const otherThread = recorded((m) => (m[SUB_RESULT].parent_tool_use_id = null));
  assert.deepEqual(unreadParts(otherThread, [part(16)]), [part(16)], "the subagent's result posed as the main thread's");
});

test("a rating that did not read the whole diff gains a HIGH Diff coverage row and demotes, even when every row is LOW", () => {
  const low = result({ risks: [row("LOW"), row("LOW", { area: "Reversibility" })] });
  const base = { output: low, pr: 7, head: HEAD, rubric: "8.0.0", cliVersion: "2.1.312", startedAt: 1, endedAt: 2 };
  const none = { chunks: 0, bytes: 0, files: 0 };
  const whole = buildRating({ ...base, messages: [...messages(), ...RECORDED], coverage: { parts: [part(16)], left_out: none } });
  assert.equal(whole.max, "LOW");
  assert.equal(whole.demote, false);
  assert.equal(whole.risks.length, 2);
  const partial = buildRating({ ...base, messages: [...messages(), ...RECORDED], coverage: { parts: [part(16), part(18)], left_out: none } });
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
  assert.match(partial.risks[2].why, /1 of 2 diff parts were never read/);
  const noResult = buildRating({ ...base, messages: [...messages(), ...recorded((m) => m.splice(MAIN_RESULT, 1))], coverage: { parts: [part(8)], left_out: none } });
  assert.equal(noResult.demote, true, "a Read with no result never certifies coverage");
  const leftOut = buildRating({ ...base, messages: [...messages(), ...RECORDED], coverage: { parts: [part(16)], left_out: { chunks: 4, bytes: 1_200_000, files: 90 } } });
  assert.equal(leftOut.demote, true);
  assert.match(leftOut.risks.at(-1).why, /4 chunk\(s\) of the diff \(1200000 bytes\)/);
  assert.equal(coverageRow(RECORDED, { parts: [part(16)], left_out: { chunks: 0 } }), undefined);
});
