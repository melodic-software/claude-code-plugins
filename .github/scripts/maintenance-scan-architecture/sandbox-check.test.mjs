// test-scope: .github/workflows/maintenance-scan-architecture-find.yml
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { sandboxRefusals } from "./sandbox-check.mjs";

const REPO_ROOT = fileURLToPath(new URL("../../../", import.meta.url));
const SCRIPT = join(REPO_ROOT, ".github/scripts/maintenance-scan-architecture/sandbox-check.mjs");
const result = (content, isError = true) => ({ type: "user", message: { role: "user", content: [{ type: "tool_result", content, is_error: isError, tool_use_id: "toolu_1" }] } });
const REFUSED = result("Exit code 1\nbwrap: Can't create file at /home/runner/work/repo/repo/.claude/commands: Read-only file system");

test("a tool call the sandbox refused to start counts; other errors and successes do not", () => {
  assert.equal(sandboxRefusals([REFUSED, REFUSED]), 2);
  assert.equal(sandboxRefusals([result([{ type: "text", text: "bwrap: Can't create file at /x: Read-only file system" }])]), 1, "array content counts too");
  assert.equal(sandboxRefusals([result("Exit code 1\nfatal: not a git repository")]), 0, "an ordinary command failure is the model's, not the sandbox's");
  assert.equal(sandboxRefusals([result("bwrap: mentioned in output", false)]), 0, "a successful call never counts");
  assert.equal(sandboxRefusals([{ type: "assistant", message: { content: [{ type: "text", text: "bwrap: quoted" }] } }]), 0);
});

test("the check fails the step on a refusal, writes a summary without the refusal text, and passes a clean run", () => {
  const dir = tempDir("sandbox-check-");
  const run = (messages) => {
    const file = join(dir, "execution.json");
    const summary = join(dir, "summary.md");
    writeFileSync(file, JSON.stringify(messages));
    writeFileSync(summary, "");
    try {
      const stdout = execFileSync("node", [SCRIPT], { env: { PATH: process.env.PATH, EXECUTION_FILE: file, GITHUB_JOB: "find-candidates", GITHUB_STEP_SUMMARY: summary }, encoding: "utf8" });
      return { status: 0, stdout, summary: readFileSync(summary, "utf8") };
    } catch (error) {
      return { status: error.status, stdout: error.stdout, summary: readFileSync(summary, "utf8") };
    }
  };
  const refused = run([REFUSED]);
  assert.equal(refused.status, 1);
  assert.match(refused.stdout, /^::error::the sandbox refused to start 1 tool call\(s\)/);
  assert.match(refused.summary, /^### maintenance-scan-architecture \/ find-candidates\n\nFailed: /);
  assert.doesNotMatch(refused.stdout + refused.summary, /Read-only file system/, "the tool result's text stays in the sealed transcript");
  assert.deepEqual(run([result("ok", false)]), { status: 0, stdout: "", summary: "" });
});

test("every model leg runs the check from the trusted checkout", () => {
  const text = readFileSync(join(REPO_ROOT, ".github/workflows/maintenance-scan-architecture-find.yml"), "utf8");
  const legs = text.match(/uses: melodic-software\/ci-workflows\/\.github\/actions\/run-claude-cli@main/g) ?? [];
  const checks = text.match(/run: node \.lane-trusted\/\.github\/scripts\/maintenance-scan-architecture\/sandbox-check\.mjs/g) ?? [];
  assert.ok(legs.length >= 3);
  assert.equal(checks.length, legs.length);
});
