import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { buildRating, main } from "./write-rating.mjs";

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
  // A checker reaching for a tool its agent file declares but the cage withholds reached nothing.
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
  };
  assert.equal(main(env, () => 160_000), 0);
  const rating = JSON.parse(readFileSync(join(dir, "out", "rating.json"), "utf8"));
  assert.equal(rating.max, "HIGH");
  assert.equal(rating.pr, 7);
  assert.equal(main({ ...env, OUTPUT_FILE: write("bad.json", "{"), OUT_DIR: join(dir, "out2") }, () => 1), 1);
  assert.equal(main({ ...env, HEAD_SHA: "nope", OUT_DIR: join(dir, "out3") }, () => 1), 1);
  assert.equal(main({ ...env, OUTPUT_FILE: "", OUT_DIR: join(dir, "out4") }, () => 1), 1);
});
