#!/usr/bin/env bash
# Behavior test: the "Check the skill took a model turn" step in both
# pr-run-activity files records each permission_denials entry as
# {tool_name, input} in act-turns.json and as `tool: input` in the step
# summary. Runs the step's github-script body against a canned execution file
# with a stub `core` whose summary records its code block.
# test-scope: .github/workflows/pr-run-activity-write.yml .github/workflows/pr-run-activity-read.yml .github/standards/runner-policy/package.json
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

results=$(
  cd "$ROOT" && node --input-type=module - <<'EOF'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
const require = createRequire(`${process.cwd()}/.github/standards/runner-policy/package.json`);
const YAML = require("yaml");

const say = (good, text) => console.log(`${good ? "ok" : "fail"}\t${text}`);
const AsyncFunction = (async () => {}).constructor;

const denials = [
  { tool_name: "Bash", tool_use_id: "t1", tool_input: { command: "git push origin HEAD" } },
  { tool_name: "Read", tool_use_id: "t2", tool_input: { file_path: "/etc/<shadow>" } },
  { tool_name: "Grep", tool_use_id: "t3", tool_input: { pattern: "a&b" } },
  { tool_name: "Glob", tool_use_id: "t4", tool_input: { path: "/src", pattern: "*.ts" } },
  { tool_name: "WebSearch", tool_use_id: "t5", tool_input: { query: "x" } },
  { tool_name: "Bash", tool_use_id: "t6", tool_input: { command: "y".repeat(400) } },
];
const expected = [
  { tool_name: "Bash", input: "git push origin HEAD" },
  { tool_name: "Read", input: "/etc/<shadow>" },
  { tool_name: "Grep", input: "a&b" },
  { tool_name: "Glob", input: "/src" },
  { tool_name: "WebSearch", input: null },
  { tool_name: "Bash", input: "y".repeat(300) },
];

for (const lane of ["write", "read"]) {
  const wf = YAML.parse(readFileSync(`.github/workflows/pr-run-activity-${lane}.yml`, "utf8"));
  const step = wf.jobs.run.steps.find((s) => s.id === "act-turns");
  if (!step?.with?.script) {
    say(false, `${lane}: the run job has an act-turns step with a script`);
    continue;
  }
  const dir = mkdtempSync(join(tmpdir(), "act-turns-"));
  const execution = join(dir, "execution.json");
  writeFileSync(execution, JSON.stringify([
    { type: "result", subtype: "success", is_error: false, num_turns: 3, duration_ms: 1,
      modelUsage: { "claude-x": {} }, permission_denials: denials },
  ]));
  process.env.EXECUTION_FILE = execution;
  process.env.REPLY_DIR = join(dir, "reply");
  process.env.LANE_TOKEN = "";
  const blocks = [];
  const summary = {
    addHeading: () => summary,
    addCodeBlock: (text) => (blocks.push(text), summary),
    write: async () => summary,
  };
  const failed = [];
  const core = { summary, info: () => {}, setOutput: () => {}, setFailed: (m) => failed.push(m) };
  let threw = null;
  try {
    await new AsyncFunction("require", "core", step.with.script)(require, core);
  } catch (e) {
    threw = e;
  }
  say(!threw && failed.length === 0, `${lane}: the step runs without failing (${threw?.message ?? failed.join("; ")})`);
  let recorded = null;
  try {
    recorded = JSON.parse(readFileSync(join(dir, "reply", "act-turns.json"), "utf8")).denied;
  } catch {}
  say(JSON.stringify(recorded) === JSON.stringify(expected),
    `${lane}: act-turns.json denied holds {tool_name, input}: command, file_path, path, pattern, null, cut to 300`);
  rmSync(dir, { recursive: true, force: true });
  const shown = blocks.join("\n");
  for (const line of [
    '"Bash: git push origin HEAD"',
    '"Read: /etc/&lt;shadow&gt;"',
    '"Grep: a&amp;b"',
    '"Glob: /src"',
    '"WebSearch"',
  ]) {
    say(shown.includes(line), `${lane}: the step summary shows ${line} HTML-escaped`);
  }
}
EOF
)
if [[ -z "$results" ]]; then
  fail "the check printed nothing; is .github/standards/runner-policy installed?"
fi
while IFS=$'\t' read -r verdict text; do
  [[ -n "$verdict" ]] || continue
  if [[ "$verdict" == ok ]]; then ok "$text"; else fail "$text"; fi
done <<<"$results"

test_harness::report
