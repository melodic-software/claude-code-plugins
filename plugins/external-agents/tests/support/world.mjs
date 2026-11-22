import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after } from "node:test";
import { fileURLToPath } from "node:url";

export const tests = dirname(dirname(fileURLToPath(import.meta.url)));
export const fixtures = join(tests, "fixtures");
export const fixture = (name) => readFileSync(join(fixtures, name), "utf8");
export const scratch = mkdtempSync(join(tmpdir(), "external-agents-runner-"));
after(() => rmSync(scratch, { recursive: true, force: true }));

export const fakeCodex = { path: process.execPath, args: [join(fixtures, "fake-codex.mjs")], shell: false };
export const fakeAgy = { path: process.execPath, args: [join(fixtures, "fake-agy.mjs")], shell: false };
export const fakeCmd = { path: join(fixtures, "fake-codex.cmd"), args: [], shell: true };

// Event shapes: the sample lines in https://learn.chatgpt.com/docs/non-interactive-mode.md and the
// item and status names in openai/codex codex-rs/exec/src/exec_events.rs, both read 2026-11-21.
export const events = (...list) => `${list.map((e) => JSON.stringify(e)).join("\n")}\n`;
export const THREAD = "00000000-0000-7000-8000-00000000000a";
export const opened = [{ type: "thread.started", thread_id: THREAD }, { type: "turn.started" }];
export const said = { type: "item.completed", item: { id: "item_0", type: "agent_message", text: "done" } };
export const completed = { type: "turn.completed", usage: { input_tokens: 1, output_tokens: 1 } };
export const clean = events(...opened, said, completed);

let count = 0;
export function world(scenario = {}, { local, team } = {}) {
  const root = join(scratch, `w${(count += 1)}`);
  const cwd = join(root, "cwd");
  const dataDir = join(root, "data");
  const home = join(cwd, "docs", "conventions");
  mkdirSync(home, { recursive: true });
  mkdirSync(dataDir);
  if (local) writeFileSync(join(home, "external-agents.local.yaml"), local);
  if (team) writeFileSync(join(home, "external-agents.yaml"), team);
  const calls = join(root, "calls.jsonl");
  const set = (next) => writeFileSync(join(root, "scenario.json"), JSON.stringify({ record: calls, ...next }));
  set(scenario);
  return {
    opts: { product: "codex", cwd, dataDir, binary: fakeCodex, warn: () => {}, env: { ...process.env, FAKE_SCENARIO: join(root, "scenario.json") } },
    cwd,
    dataDir,
    set,
    calls: () => (existsSync(calls) ? readFileSync(calls, "utf8").trim().split("\n").filter(Boolean).map((l) => JSON.parse(l)) : []),
  };
}
export const launched = (w, verb = "exec") => w.calls().filter((c) => c.argv[0] === verb);
export const cliArgs = (job) => job.argv.slice(2);

const WIDENING_FLAGS_IN_CODEX_EXEC_HELP = /dangerously|danger-full-access|approve-for-me|ignore-rules/;
export const assertNoBypass = (argv) => assert.ok(!argv.some((a) => WIDENING_FLAGS_IN_CODEX_EXEC_HELP.test(a)), argv.join(" "));

export function gitRepo(cwd, files) {
  const g = (...args) => execFileSync("git", ["-C", cwd, "-c", "user.email=t@example.com", "-c", "user.name=t", ...args], { stdio: "ignore" });
  g("init", "-q", "-b", "main");
  writeFileSync(join(cwd, "a.txt"), "one\n");
  g("add", "a.txt");
  g("commit", "-q", "-m", "base");
  g("branch", "a&b");
  g("checkout", "-q", "-b", "change");
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(cwd, path)), { recursive: true });
    writeFileSync(join(cwd, path), text);
    g("add", path);
  }
  g("commit", "-q", "-m", "change");
}
