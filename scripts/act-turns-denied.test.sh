#!/usr/bin/env bash
# Behavior test: the "Check the skill took a model turn" step in both
# pr-run-activity files records each permission_denials entry as
# {tool_name, input} in act-turns.json, keeping the first 20 with denied_total
# counting all, and the step summary shows each as `tool: input`, then
# `(+N more)` for any cut. A worst-case read-lane file fits its carry cap. The write file's step writes the summary itself; the read
# file's writes none, and its summary steps (the scan job's, after the leak
# scan, and issue mode's) render the act-turns.json it wrote. Runs each step's
# github-script body against a canned execution file with a stub `core` whose
# summary records its code blocks.
# test-scope: .github/workflows/pr-run-activity-write.yml .github/workflows/pr-run-activity-read.yml .github/standards/runner-policy/package.json
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

results=$(
  cd "$ROOT" && node --input-type=module - <<'EOF'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { Buffer } from "node:buffer";
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

// Runs one github-script body in a fresh directory against an execution file
// holding `messages`; returns the directory, the code blocks it wrote and any failure.
const runScript = async (script, env, blocks) => {
  const summary = {
    addHeading: () => summary,
    addCodeBlock: (text) => (blocks.push(text), summary),
    write: async () => summary,
  };
  const failed = [];
  const core = { summary, info: () => {}, setOutput: () => {}, setFailed: (m) => failed.push(m) };
  Object.assign(process.env, env);
  let threw = null;
  try {
    await new AsyncFunction("require", "core", script)(require, core);
  } catch (e) {
    threw = e;
  }
  return threw?.message ?? failed.join("; ");
};
const runActTurns = async (lane, wf, messages) => {
  const dir = mkdtempSync(join(tmpdir(), "act-turns-"));
  const execution = join(dir, "execution.json");
  writeFileSync(execution, JSON.stringify(messages));
  const blocks = [];
  const step = wf.jobs.run.steps.find((s) => s.id === "act-turns");
  const error = await runScript(step.with.script,
    { EXECUTION_FILE: execution, REPLY_DIR: join(dir, "reply"), LANE_TOKEN: "" }, blocks);
  let turns = null;
  try {
    turns = readFileSync(join(dir, "reply", "act-turns.json"), "utf8");
  } catch {}
  return { dir, blocks, error, turns };
};
// The summary views of a run: the write step's own, else the read file's two
// summary steps rendering the act-turns.json in `dir`.
const views = async (lane, wf, dir, blocks) => {
  if (lane === "write") return [["the act-turns step", blocks.join("\n")]];
  const out = [];
  for (const [job, steps] of [["scan", wf.jobs.scan.steps], ["run (issue mode)", wf.jobs.run.steps]]) {
    const show = steps.find((s) => s.name === "Show the skill's run in the step summary");
    if (!show?.with?.script) {
      say(false, `read: the ${job} job has a summary step with a script`);
      continue;
    }
    const shown = [];
    await runScript(show.with.script, { REPLY_DIR: join(dir, "reply") }, shown);
    out.push([`the ${job} summary step`, shown.join("\n")]);
  }
  return out;
};
const result = (extra) => ({ type: "result", subtype: "success", is_error: false, num_turns: 3, duration_ms: 1,
  modelUsage: { "claude-x": {} }, ...extra });

for (const lane of ["write", "read"]) {
  const wf = YAML.parse(readFileSync(`.github/workflows/pr-run-activity-${lane}.yml`, "utf8"));
  if (!wf.jobs.run.steps.find((s) => s.id === "act-turns")?.with?.script) {
    say(false, `${lane}: the run job has an act-turns step with a script`);
    continue;
  }
  {
    const { dir, blocks, error, turns } = await runActTurns(lane, wf, [result({ permission_denials: denials })]);
    say(!error, `${lane}: the step runs without failing (${error})`);
    const recorded = turns && JSON.parse(turns);
    say(JSON.stringify(recorded?.denied) === JSON.stringify(expected),
      `${lane}: act-turns.json denied holds {tool_name, input}: command, file_path, path, pattern, null, cut to 300`);
    say(recorded?.denied_total === expected.length, `${lane}: denied_total counts every denial`);
    if (lane === "read") say(blocks.length === 0, "read: the act-turns step writes no step summary; it shows only after the leak scan");
    for (const [where, shown] of await views(lane, wf, dir, blocks)) {
      for (const line of [
        '"Bash: git push origin HEAD"',
        '"Read: /etc/&lt;shadow&gt;"',
        '"Grep: a&amp;b"',
        '"Glob: /src"',
        '"WebSearch"',
      ]) {
        say(shown.includes(line), `${lane}: ${where} shows ${line} HTML-escaped`);
      }
      say(!shown.includes("more)"), `${lane}: ${where} notes no extra denials when all are kept`);
    }
    rmSync(dir, { recursive: true, force: true });
  }
  {
    // 25 denials: the first 20 are kept, and the summary says 5 more were cut.
    const many = Array.from({ length: 25 }, (_, n) => ({ tool_name: "Bash", tool_input: { command: `cmd ${n}` } }));
    const { dir, blocks, turns } = await runActTurns(lane, wf, [result({ permission_denials: many })]);
    const recorded = turns && JSON.parse(turns);
    say(JSON.stringify(recorded?.denied?.map((d) => d.input)) === JSON.stringify(many.slice(0, 20).map((d) => d.tool_input.command)),
      `${lane}: 25 denials keep the first 20 in denied`);
    say(recorded?.denied_total === 25, `${lane}: 25 denials record denied_total 25`);
    for (const [where, shown] of await views(lane, wf, dir, blocks)) {
      say(shown.includes('"(+5 more)"'), `${lane}: ${where} shows "(+5 more)"`);
      say(shown.includes('"Bash: cmd 19"') && !shown.includes('"Bash: cmd 20"'), `${lane}: ${where} shows denials 0-19 only`);
    }
    rmSync(dir, { recursive: true, force: true });
  }
  if (lane === "read") {
    // Worst case: 100 denials and 6 stderr messages, every character one that
    // JSON escapes to two bytes; the file must fit the 32768-byte carry cap.
    const q = '"';
    const many = Array.from({ length: 100 }, () => ({
      tool_name: "mcp__github_inline_comment__create_inline_comment",
      tool_input: { command: q.repeat(1000) },
    }));
    const stderr = { type: "user", message: { content: `<local-command-stderr>${q.repeat(5000)}` } };
    const { dir, turns } = await runActTurns(lane, wf,
      [...Array(6).fill(stderr), result({ permission_denials: many })]);
    const bytes = Buffer.byteLength(turns ?? "", "utf8");
    say(turns !== null && bytes <= 32768, `read: worst-case act-turns.json is ${bytes} bytes, within the 32768-byte carry cap`);
    rmSync(dir, { recursive: true, force: true });
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
