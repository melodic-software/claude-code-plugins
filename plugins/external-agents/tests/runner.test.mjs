import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, join, relative } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import { resolveBinary } from "../scripts/lib/binary.mjs";
import { readBreaker } from "../scripts/lib/breaker.mjs";
import { listJobs, readJob, repoKey, writeJob } from "../scripts/lib/jobs.mjs";
import { conventionHome, loadConfig } from "../scripts/lib/config.mjs";
import { classify } from "../scripts/lib/outcome.mjs";
import { pidStartTime } from "../scripts/lib/process.mjs";
import { loadProvider, validateProvider } from "../scripts/lib/provider.mjs";
import { cancel, dataDirFor, installedDataDir, result, review, run, status } from "../scripts/lib/runner.mjs";
import { assertNoBypass, clean, cli, cliArgs, completed, events, fakeAgy, fakeCmd, fixture, fixtures, gitRepo, isolation, launched, opened, said, scratch, THREAD, world } from "./support/world.mjs";

process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const here = dirname(fileURLToPath(import.meta.url));
const codex = loadProvider("codex");

describe("done versus blocked (Codex event stream)", () => {
  const judge = (stdout, extra = {}) => classify(codex, { exitCode: 0, stdout, stderr: "", finalMessage: "final answer", mode: "read-only", ...extra });

  test("the recorded read-only probe is blocked-by-mode, though Codex exited 0 and finished its turn", () => {
    const got = judge(fixture("events-default.jsonl"));
    assert.equal(got.status, "blocked-by-mode");
    assert.equal(got.denied_commands.count, 1);
    assert.match(got.denied_commands.commands[0], /echo hi > probe\.txt/);
    assert.equal(got.thread_id, "00000000-0000-7000-8000-000000000001");
  });

  test("the recorded write-outside-the-workspace probe is blocked-by-mode", () => {
    const got = judge(fixture("events-outside.jsonl"));
    assert.equal(got.status, "blocked-by-mode");
    assert.equal(got.denied_commands.count, 1);
    assert.match(got.denied_commands.commands[0], /outside-probe\.txt/);
  });

  test("the recorded clean probe is ok, its interleaved stderr lines skipped", () => {
    const got = judge(fixture("events-nomcp.jsonl"));
    assert.equal(got.status, "ok");
    assert.equal(got.denied_commands.count, 0);
    assert.equal(got.thread_id, "00000000-0000-7000-8000-000000000003");
  });

  test("a failed file_change is blocked-by-mode", () => {
    const patch = { type: "item.completed", item: { id: "item_1", type: "file_change", changes: [{ path: "src/a.js", kind: "update" }], status: "failed" } };
    const got = judge(events(...opened, patch, said, completed));
    assert.equal(got.status, "blocked-by-mode");
    assert.deepEqual(got.denied_commands, { count: 1, commands: ["src/a.js"] });
  });

  test("a declined command is blocked-by-mode", () => {
    const declined = { type: "item.completed", item: { id: "item_1", type: "command_execution", command: "rm -rf build", aggregated_output: "", exit_code: null, status: "declined" } };
    assert.deepEqual(judge(events(...opened, declined, said, completed)).denied_commands, { count: 1, commands: ["rm -rf build"] });
  });

  test("a command that failed for its own reasons is reported, and the run stays ok", () => {
    const tests = { type: "item.completed", item: { id: "item_1", type: "command_execution", command: "npm test", aggregated_output: "1 failing", exit_code: 1, status: "failed" } };
    const got = judge(events(...opened, tests, said, completed));
    assert.equal(got.status, "ok");
    assert.deepEqual(got.failed_commands, { count: 1, commands: ["npm test"] });
  });

  test("turn.failed is failed and carries the CLI's error", () => {
    const got = judge(events(...opened, { type: "turn.failed", error: { message: "stream disconnected" } }));
    assert.equal(got.status, "failed");
    assert.equal(got.last_error, "stream disconnected");
  });

  test("an error event is failed even when the turn then completes", () => {
    const got = judge(events(...opened, { type: "error", message: "model overloaded" }, said, completed));
    assert.equal(got.status, "failed");
    assert.equal(got.last_error, "model overloaded");
  });

  test("an empty final message is failed", () => {
    assert.equal(judge(clean, { finalMessage: " \n" }).status, "failed");
    assert.equal(judge(clean).status, "ok");
  });

  test("a non-zero exit is failed", () => {
    assert.equal(judge(clean, { exitCode: 1 }).status, "failed");
  });

  test("a stream that never reaches turn.completed is failed", () => {
    assert.equal(judge(events(...opened, said)).status, "failed");
  });

  test("a stream of only non-JSON lines is failed", () => {
    assert.equal(judge("Reading additional input from stdin...\nERROR worker quit\n{not json\n").status, "failed");
  });

  test("MCP tool calls are counted and named", () => {
    const call = (tool) => ({ type: "item.completed", item: { id: "item_1", type: "mcp_tool_call", server: "docs", tool, arguments: {}, result: null, error: null, status: "completed" } });
    const got = judge(events(...opened, call("search"), call("search"), call("fetch"), said, completed));
    assert.deepEqual(got.mcp_calls, { count: 3, tools: ["docs.search", "docs.fetch"] });
  });
});

describe("run", () => {
  test("an investigate run is read-only, sends the prompt on stdin and records the job", async () => {
    const w = world({ stdout: clean, final: "the answer\nline two" });
    const got = await run({ ...w.opts, use: "investigate", prompt: "why is it slow?" });
    const job = readJob(w.dataDir, "no-repo", got.job.id);
    const final = join(w.dataDir, "jobs", "no-repo", job.id, "final.txt");
    assert.deepEqual(cliArgs(job), ["exec", "--json", "-o", final, "--sandbox", "read-only", "-c", 'approval_policy="never"', "-"]);
    assert.deepEqual(launched(w)[0], { argv: cliArgs(job), stdin: "why is it slow?" });
    assert.equal(job.status, "ok");
    assert.equal(job.mode, "read-only");
    assert.equal(job.use, "investigate");
    assert.equal(job.thread_id, THREAD);
    assert.equal(job.exit_code, 0);
    assert.equal(job.cli_version, "codex-cli 0.0.1");
    assert.equal(job.final_message_path, final);
    assert.equal(readFileSync(job.log_path, "utf8"), clean);
    assert.equal(got.stdout, "codex: ok\nthe answer\nline two\n");
    assert.equal(got.code, 0);
    assertNoBypass(job.argv);
  });

  test("a task run uses the workspace-write sandbox", async () => {
    const w = world({ stdout: clean, final: "done" });
    const { job } = await run({ ...w.opts, use: "task", prompt: "fix it" });
    assert.deepEqual(cliArgs(job).slice(4, 8), ["--sandbox", "workspace-write", "-c", 'approval_policy="never"']);
    assertNoBypass(job.argv);
  });

  test("model, profile and effort are passed only when configured", async () => {
    const w = world({ stdout: clean, final: "done" }, { local: "schema: 1\ncodex:\n  model: my-model\n  profile: work\n  effort: high\n" });
    const { job } = await run({ ...w.opts, use: "task", prompt: "fix it" });
    assert.deepEqual(cliArgs(job).slice(8), ["-m", "my-model", "-p", "work", "-c", 'model_reasoning_effort="high"', "-"]);
  });

  test("a per-run model and effort override config, keep the sandbox and approval policy, and are recorded on the job", async () => {
    const w = world({ stdout: clean, final: "done" }, { local: "schema: 1\ncodex:\n  model: my-model\n  effort: low\n" });
    const { job } = await run({ ...w.opts, use: "task", model: "other-model", effort: "xhigh", prompt: "fix it" });
    assert.deepEqual(cliArgs(job).slice(4), ["--sandbox", "workspace-write", "-c", 'approval_policy="never"', "-m", "other-model", "-c", 'model_reasoning_effort="xhigh"', "-"]);
    assert.equal(job.model, "other-model");
    assert.equal(job.effort, "xhigh");
    const shown = status({ ...w.opts, jobId: job.id }).stdout;
    assert.match(shown, /^model: other-model$/m);
    assert.match(shown, /^effort: xhigh$/m);
  });

  test("a per-run effort that is not a plain word is refused before anything starts", async () => {
    const w = world({ stdout: clean, final: "done" });
    const got = await run({ ...w.opts, use: "task", effort: 'high" -c x="y', prompt: "fix it" });
    assert.match(got.stdout, /^codex: refused: effort .* is not a plain word/);
    assert.deepEqual(launched(w), []);
  });

  test("config is read from the convention home the repository's pointer region binds", async () => {
    const w = world({ stdout: clean, final: "done" }, { local: "schema: 1\ncodex:\n  model: from-the-default-home\n" });
    gitRepo(w.cwd, { "a.txt": "two\n" });
    mkdirSync(join(w.cwd, "team", "conventions"), { recursive: true });
    writeFileSync(join(w.cwd, "team", "conventions", "external-agents.local.yaml"), "schema: 1\ncodex:\n  model: from-the-bound-home\n");
    writeFileSync(join(w.cwd, "AGENTS.md"), "# Repo\n\n<!-- BEGIN GENERATED: convention-home -->\nTeam conventions live in `team/conventions`.\n<!-- END GENERATED: convention-home -->\n");
    const { job } = await run({ ...w.opts, use: "task", prompt: "fix it" });
    assert.deepEqual(cliArgs(job).slice(8, 10), ["-m", "from-the-bound-home"]);
  });

  test("a write request on a read-only use runs read-only and names the config key", async () => {
    const w = world({ stdout: clean, final: "done" });
    const got = await run({ ...w.opts, use: "investigate", mode: "write", prompt: "change it" });
    assert.deepEqual(cliArgs(got.job).slice(4, 6), ["--sandbox", "read-only"]);
    assert.equal(got.job.mode, "read-only");
    assert.match(got.stderr, /codex\.uses\.investigate\.mode/);
  });

  test("a blocked run exits 3 and its first line counts the blocked commands", async () => {
    const w = world({ stdout_file: join(fixtures, "events-default.jsonl"), final: "probe.txt does not exist." });
    const got = await run({ ...w.opts, use: "investigate", prompt: "write probe.txt" });
    assert.equal(got.job.status, "blocked-by-mode");
    assert.equal(got.job.denied_commands.count, 1);
    assert.match(got.stdout.split("\n")[0], /^codex: blocked-by-mode \(1 command blocked by read-only mode: /);
    assert.equal(got.stdout.split("\n")[1], "probe.txt does not exist.");
    assert.equal(got.code, 3);
  });

  test("a failed run reports the CLI's last error and relays no message", async () => {
    const w = world({ stdout: events(...opened, { type: "turn.failed", error: { message: "stream disconnected" } }), exit: 1 });
    const got = await run({ ...w.opts, use: "task", prompt: "fix it" });
    assert.equal(got.stdout, "codex: failed (exit 1; stream disconnected)\n");
    assert.equal(got.code, 1);
    assert.equal(readBreaker(w.dataDir, "codex"), null, "a task failure never opens the breaker");
  });

  test("a run the CLI rejects before any event reports the CLI's own error line", async () => {
    const usage = "error: the argument '--base <BRANCH>' cannot be used with '[PROMPT]'\n\nUsage: codex exec review --base <BRANCH> [PROMPT]\n\nFor more information, try '--help'.\n";
    const w = world({ stderr: usage, exit: 2 });
    const got = await run({ ...w.opts, use: "task", prompt: "fix it" });
    assert.equal(got.stdout, "codex: failed (exit 2; error: the argument '--base <BRANCH>' cannot be used with '[PROMPT]'; the run ended without turn.completed)\n");
  });

  test("stderr text alone never opens the breaker", async () => {
    const w = world({ stderr: "ERROR rmcp::transport::worker: 401 Unauthorized\n", exit: 1 });
    const got = await run({ ...w.opts, use: "task", prompt: "fix it" });
    assert.equal(got.job.status, "failed");
    assert.equal(readBreaker(w.dataDir, "codex"), null);
  });

  test("resume passes the mode as a config override and only resumes this plugin's threads", async () => {
    const w = world({ stdout: clean, final: "done" });
    const first = await run({ ...w.opts, use: "investigate", prompt: "one" });
    const again = await run({ ...w.opts, use: "investigate", prompt: "two", resume: THREAD });
    const final = join(w.dataDir, "jobs", "no-repo", again.job.id, "final.txt");
    assert.deepEqual(cliArgs(again.job), ["exec", "resume", THREAD, "--json", "-o", final, "-c", 'sandbox_mode="read-only"', "-c", 'approval_policy="never"', "-"]);
    assert.notEqual(again.job.id, first.job.id);
    assertNoBypass(again.job.argv);

    const before = launched(w).length;
    const stranger = await run({ ...w.opts, use: "investigate", prompt: "three", resume: "11111111-1111-7111-8111-111111111111" });
    assert.equal(stranger.code, 2);
    assert.match(stranger.stdout, /not in this plugin's job files/);
    assert.equal(launched(w).length, before, "the CLI is not started for a thread this plugin did not record");
  });

  test("--last resumes this plugin's newest job, never the CLI's own last session", async () => {
    const w = world({ stdout: clean, final: "done" });
    await run({ ...w.opts, use: "task", prompt: "one", now: () => Date.UTC(2026, 10, 21, 12, 0, 0) });
    w.set({ stdout: clean.replace(THREAD, "00000000-0000-7000-8000-00000000000b"), final: "done" });
    await run({ ...w.opts, use: "task", prompt: "two", now: () => Date.UTC(2026, 10, 21, 12, 0, 5) });
    const { job } = await run({ ...w.opts, use: "task", prompt: "three", last: true, now: () => Date.UTC(2026, 10, 21, 12, 0, 9) });
    assert.deepEqual(cliArgs(job).slice(0, 3), ["exec", "resume", "00000000-0000-7000-8000-00000000000b"]);
    assert.deepEqual(cliArgs(job).slice(6, 8), ["-c", 'sandbox_mode="workspace-write"']);
    assert.ok(!job.argv.includes("--last"));
  });

  test("a value that would be read as an option is refused", async () => {
    const w = world({ stdout: clean, final: "done" }, { local: "schema: 1\ncodex:\n  model: --dangerously-bypass-approvals-and-sandbox\n" });
    const got = await run({ ...w.opts, use: "task", prompt: "fix it" });
    assert.equal(got.code, 2);
    assert.equal(launched(w).length, 0);
  });

  test("finished jobs beyond jobs.keep are pruned with their folders", async () => {
    const w = world({ stdout: clean, final: "done" }, { local: "schema: 1\njobs:\n  keep: 1\n" });
    const first = await run({ ...w.opts, use: "task", prompt: "one", now: () => Date.UTC(2026, 10, 21, 12, 0, 0) });
    assert.ok(existsSync(join(w.dataDir, "jobs", "no-repo", first.job.id, "prompt.txt")));
    const second = await run({ ...w.opts, use: "task", prompt: "two", now: () => Date.UTC(2026, 10, 21, 12, 0, 5) });
    assert.deepEqual(readdirSync(join(w.dataDir, "jobs", "no-repo")).sort(), [second.job.id, `${second.job.id}.json`]);
  });
});

describe("review", () => {
  test("a Codex review with a brief is read-only, names the base in the prompt on stdin instead of --base, and relays the findings", async () => {
    const w = world({ stdout: clean, final: "IMPORTANT | a.txt:1 | wrong | fix\n" });
    gitRepo(w.cwd, { "a.txt": "two\n" });
    const got = await review({ ...w.opts, base: "main", model: "gpt-test", brief: "look for races" });
    const final = join(w.dataDir, "jobs", repoKey(w.cwd), got.job.id, "final.txt");
    assert.deepEqual(cliArgs(got.job), ["exec", "review", "--json", "-o", final, "-c", 'sandbox_mode="read-only"', "-c", 'approval_policy="never"', "-m", "gpt-test", "-"]);
    const sha = execFileSync("git", ["-C", w.cwd, "rev-parse", "main"], { encoding: "utf8" }).trim();
    assert.equal(launched(w)[0].stdin, `Review only the changes on this branch against main: the diff of ${sha}...HEAD. Changed files (1):\n- a.txt\n\nlook for races`);
    assert.equal(got.stdout, `codex: ran (reviewed 1 changed file against ${sha.slice(0, 8)})\nIMPORTANT | a.txt:1 | wrong | fix\n`);
    assert.deepEqual(got.job.review_scope, { base: "main", merge_base: sha, changed_files: 1 });
    assert.equal(got.code, 0);
    assert.equal(got.job.use, "review");
    assert.doesNotMatch(got.stderr, /\.codex/);
    assertNoBypass(got.job.argv);
  });

  test("a council review is skipped before anything starts when council.enabled is false; a direct review still runs", async () => {
    const w = world({ stdout: clean, final: "No findings." }, { local: "schema: 1\ncodex:\n  council:\n    enabled: false\n" });
    gitRepo(w.cwd, { "a.txt": "two\n" });
    const got = await review({ ...w.opts, base: "main", council: true });
    assert.equal(got.stdout, "codex: skipped (codex.council.enabled is false)\n");
    assert.equal(launched(w).length, 0);
    assert.match((await review({ ...w.opts, base: "main" })).stdout, /^codex: ran/);
  });

  test("a per-run effort overrides config on a review and is recorded on the job", async () => {
    const w = world({ stdout: clean, final: "No findings." }, { local: "schema: 1\ncodex:\n  effort: low\n" });
    gitRepo(w.cwd, { "a.txt": "two\n" });
    const { job } = await review({ ...w.opts, base: "main", effort: "xhigh" });
    assert.deepEqual(cliArgs(job).slice(-2), ["-c", 'model_reasoning_effort="xhigh"']);
    assert.ok(!cliArgs(job).includes('model_reasoning_effort="low"'));
    assert.equal(job.effort, "xhigh");
  });

  test("a review without a brief passes --base and no prompt argument", async () => {
    const w = world({ stdout: clean, final: "No findings." });
    gitRepo(w.cwd, { "a.txt": "two\n" });
    const { job } = await review({ ...w.opts, base: "main" });
    assert.deepEqual(cliArgs(job).slice(0, 5), ["exec", "review", "--base", "main", "--json"]);
    assert.deepEqual(cliArgs(job).slice(-2), ["-c", 'approval_policy="never"']);
    assert.equal(launched(w)[0].stdin, null);
  });

  test("the status line names blocked commands and MCP calls, and still relays the findings", async () => {
    const call = { type: "item.completed", item: { id: "item_9", type: "mcp_tool_call", server: "docs", tool: "search", arguments: {}, result: null, error: null, status: "completed" } };
    const stream = fixture("events-default.jsonl").replace('{"type":"turn.completed"', `${JSON.stringify(call)}\n{"type":"turn.completed"`);
    const w = world({ stdout: stream, final: "No findings." });
    gitRepo(w.cwd, { "a.txt": "two\n" });
    const got = await review({ ...w.opts, base: "main" });
    const [line, findings] = got.stdout.split("\n");
    assert.match(line, /^codex: ran \(reviewed 1 changed file against [0-9a-f]{8}; 1 command blocked by read-only mode: .*; 1 MCP call: docs\.search\)$/);
    assert.equal(findings, "No findings.");
    assert.deepEqual(got.job.mcp_calls, { count: 1, tools: ["docs.search"] });
  });

  test("a briefed review lists at most 200 changed files and counts the rest", async () => {
    const w = world({ stdout: clean, final: "No findings." });
    gitRepo(w.cwd, { "f/000.txt": "x\n" });
    for (let i = 1; i < 201; i += 1) writeFileSync(join(w.cwd, "f", `${String(i).padStart(3, "0")}.txt`), "x\n");
    execFileSync("git", ["-C", w.cwd, "add", "f"], { stdio: "ignore" });
    execFileSync("git", ["-C", w.cwd, "-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-q", "-m", "more"], { stdio: "ignore" });
    const got = await review({ ...w.opts, base: "main", brief: "look" });
    const stdin = launched(w)[0].stdin;
    assert.ok(stdin.includes("Changed files (201):\n- f/000.txt\n"), stdin.slice(0, 300));
    assert.ok(stdin.includes("\n- f/199.txt\n- and 1 more\n\nlook"), stdin.slice(-200));
    assert.ok(!stdin.includes("f/200.txt"));
    assert.equal(got.job.review_scope.changed_files, 201);
    assert.match(got.stdout, /^codex: ran \(reviewed 201 changed files against [0-9a-f]{8}\)\n/);
    assert.ok(!got.job.argv.some((a) => a.includes("f/000.txt")), "the file list never reaches argv");
  });

  test("a change that touches .codex/ is flagged", async () => {
    const w = world({ stdout: clean, final: "No findings." });
    gitRepo(w.cwd, { ".codex/config.toml": "[mcp_servers.x]\n" });
    const order = [];
    const got = await review({ ...w.opts, base: "main", warn: (line) => order.push([line, w.calls().length]) });
    assert.equal(order.length, 1);
    assert.match(order[0][0], /^notice: the reviewed change touches \.codex\/ \(1 file\)/);
    assert.equal(order[0][1], 0, "the warning is written before the CLI is started");
    assert.ok(w.calls().length > 0);
    assert.equal(got.job.notices.length, 1);
  });

  test("a failed review says failed and relays nothing", async () => {
    const w = world({ stdout: events(...opened, { type: "error", message: "model overloaded" }), exit: 1 });
    gitRepo(w.cwd, { "a.txt": "two\n" });
    const got = await review({ ...w.opts, base: "main" });
    assert.equal(got.stdout, "codex: failed (exit 1; model overloaded)\n");
  });

  test("a review that was blocked and then failed is failed, with no partial findings relayed", async () => {
    const stream = fixture("events-default.jsonl").replace(/\{"type":"turn\.completed".*/, JSON.stringify({ type: "turn.failed", error: { message: "stream disconnected" } }));
    const w = world({ stdout: `${stream}\n`, final: "half a review", exit: 1 });
    gitRepo(w.cwd, { "a.txt": "two\n" });
    const got = await review({ ...w.opts, base: "main" });
    assert.match(got.stdout, /^codex: failed \(blocked-by-mode; exit 1; stream disconnected; 1 command blocked by read-only mode: [^\n]*\)\n$/);
    assert.equal(got.code, 1);
  });

  test("an unknown base is failed before the CLI starts", async () => {
    const w = world({ stdout: clean, final: "x" });
    gitRepo(w.cwd, { "a.txt": "two\n" });
    const got = await review({ ...w.opts, base: "no-such-ref" });
    assert.match(got.stdout, /^codex: failed \(base "no-such-ref" is not a commit/);
    assert.equal(w.calls().length, 0);
  });
});

describe("a binary run through cmd.exe", () => {
  test("a base ref holding & is refused, pointing at binary_path", async () => {
    const w = world({ stdout: clean, final: "x" });
    gitRepo(w.cwd, { "a.txt": "two\n" });
    const got = await review({ ...w.opts, binary: fakeCmd, base: "a&b" });
    assert.match(got.stdout, /^codex: failed \(base "a&b" cannot be passed safely .*codex\.binary_path/);
    assert.equal(w.calls().length, 0);
    assert.deepEqual(listJobs(w.dataDir, repoKey(w.cwd)), []);
  });

  test("with a brief the same base travels on stdin, so the review runs", { skip: process.platform !== "win32" }, async () => {
    const w = world({ stdout: clean, final: "No findings." });
    gitRepo(w.cwd, { "a.txt": "two\n" });
    const got = await review({ ...w.opts, binary: fakeCmd, base: "a&b", brief: "look for races" });
    assert.match(got.stdout, /^codex: ran \(reviewed 1 changed file against [0-9a-f]{8}\)\nNo findings\.\n$/);
    assert.ok(!launched(w)[0].argv.includes("a&b"));
    const sha = execFileSync("git", ["-C", w.cwd, "rev-parse", "a&b"], { encoding: "utf8" }).trim();
    assert.equal(launched(w)[0].stdin, `Review only the changes on this branch against a&b: the diff of ${sha}...HEAD. Changed files (1):\n- a.txt\n\nlook for races`);
  });

  test("a team-layer model holding & is refused", async () => {
    const w = world({ stdout: clean, final: "x" }, { team: 'schema: 1\ncodex:\n  model: "gpt&calc"\n' });
    const got = await run({ ...w.opts, binary: fakeCmd, use: "task", prompt: "fix it" });
    assert.match(got.stdout, /^codex: refused: model "gpt&calc" cannot be passed safely .*codex\.binary_path/);
    assert.equal(got.code, 2);
    assert.equal(w.calls().length, 0);
  });

  test("a CLI that takes its prompt as an argument is refused", async () => {
    const w = world({ envelope: { status: "SUCCESS", response: "hi" } });
    const got = await run({ ...w.opts, product: "antigravity", providersRoot: fixtures, binary: fakeCmd, model: "m1", use: "task", prompt: "fix it" });
    assert.match(got.stdout, /^antigravity: refused: antigravity takes its prompt as an argument.*antigravity\.binary_path/);
    assert.equal(w.calls().length, 0);
  });

  test("a clean run still works, its quoted config values reaching the CLI bare", { skip: process.platform !== "win32" }, async () => {
    const w = world({ stdout: clean, final: "done" });
    const got = await run({ ...w.opts, binary: fakeCmd, use: "investigate", prompt: "why?" });
    assert.equal(got.job.status, "ok");
    const final = join(w.dataDir, "jobs", "no-repo", got.job.id, "final.txt");
    assert.deepEqual(launched(w)[0], { argv: ["exec", "--json", "-o", final, "--sandbox", "read-only", "-c", "approval_policy=never", "-"], stdin: "why?" });
  });
});

describe("use modes set once per machine through the plugin options", () => {
  const agy = (w, settings, extra) => ({ ...w.opts, product: "antigravity", providersRoot: fixtures, binary: fakeAgy, model: "m1", operatorSettings: settings, use: "task", mode: "write", prompt: "fix it", ...extra });
  const ok = { envelope: { status: "SUCCESS", response: "done", conversation_id: "conv-1" } };
  const downgrade = /notice: write was requested, but antigravity\.uses\.task\.mode is read-only, so this run is read-only/;
  const teamReadOnly = "schema: 1\nantigravity:\n  uses:\n    task:\n      mode: read-only\n";
  let files = 0;
  const userSettings = (text) => {
    const file = join(scratch, `user-settings-${(files += 1)}.json`);
    writeFileSync(file, text);
    return { install: { pluginId: "external-agents@test-market", name: "external-agents", userSettings: file }, managed: () => [] };
  };
  const withOptions = (options) => userSettings(JSON.stringify({ pluginConfigs: { "external-agents@test-market": { options } } }));

  test("a user-settings write with no repository files runs agy's task write with no downgrade notice", async () => {
    const got = await run(agy(world(ok), withOptions({ antigravity_uses_task_mode: "write" })));
    assert.equal(got.job.mode, "write");
    assert.doesNotMatch(got.stderr, downgrade);
  });

  test("a team file's read-only beats the user-settings write and prints the notice", async () => {
    const got = await run(agy(world(ok, { team: teamReadOnly }), withOptions({ antigravity_uses_task_mode: "write" })));
    assert.equal(got.job.mode, "read-only");
    assert.match(got.stderr, downgrade);
  });

  test("with no option set, agy's task stays read-only and Codex's task writes", async () => {
    const unset = withOptions({});
    const agyRun = await run(agy(world(ok), unset));
    assert.equal(agyRun.job.mode, "read-only");
    assert.match(agyRun.stderr, downgrade);
    const w = world({ stdout: clean, final: "done" });
    assert.equal((await run({ ...w.opts, operatorSettings: unset, use: "task", prompt: "fix it" })).job.mode, "write");
  });

  test("an invalid stored value is a config notice and the key takes the team value, else the default", async () => {
    const bad = withOptions({ antigravity_uses_task_mode: "yes" });
    const alone = await run(agy(world(ok), bad));
    assert.match(alone.stderr, /notice: config: userConfig: "antigravity\.uses\.task\.mode": "yes" is not one of "read-only", "write"/);
    assert.equal(alone.job.mode, "read-only");
    const teamWrite = await run(agy(world(ok, { team: teamReadOnly.replace("read-only", "write") }), bad));
    assert.equal(teamWrite.job.mode, "write");
  });

  test("a settings file that cannot be read is a config notice and sets no option", async () => {
    const got = await run(agy(world(ok), userSettings("{ not json")));
    assert.match(got.stderr, /notice: config: userConfig: settings file .* is not valid JSON .*; the userConfig layer is not read/);
    assert.equal(got.job.mode, "read-only");
  });

  test("each option's manifest default is the mode the cascade resolves with the option unset", () => {
    const declared = JSON.parse(readFileSync(join(here, "..", ".claude-plugin", "plugin.json"), "utf8")).userConfig;
    const { values, provenance } = loadConfig({ projectRoot: world().cwd, userConfig: {} });
    assert.equal(Object.keys(declared).length, 4);
    for (const [key, option] of Object.entries(declared)) {
      const [product, , use] = key.split("_");
      assert.equal(option.default, values[product].uses[use].mode, key);
      assert.equal(provenance[`${product}.uses.${use}.mode`], "defaults", key);
    }
  });

  test("a spawned CLI under the test isolation finds no managed settings file and no user settings location", () => {
    const options = pathToFileURL(join(here, "..", "lib", "plugin-options.mjs")).href;
    const probe = (expr) => `import(${JSON.stringify(options)}).then((m) => process.stdout.write(JSON.stringify(${expr})))`;
    const read = (args, expr) => JSON.parse(spawnSync(process.execPath, [...args, "--input-type=module", "-e", probe(expr)], { encoding: "utf8" }).stdout);
    const userSettings = 'm.resolveInstall("/x/plugins/cache/m/external-agents/1").userSettings';
    assert.equal(read([], userSettings), join("/x", "settings.json"));
    const isolated = ["--import", pathToFileURL(isolation).href];
    assert.equal(read(isolated, userSettings), null);
    assert.deepEqual(read(isolated, 'm.managedSettingsFiles("linux")'), []);
  });

  test("a managed settings file applies with no user settings location, as for a --plugin-dir copy", async () => {
    const managed = withOptions({ antigravity_uses_task_mode: "write" });
    const got = await run(agy(world(ok), { install: { pluginId: null, name: "external-agents", userSettings: null }, managed: () => [managed.install.userSettings] }));
    assert.equal(got.job.mode, "write");
  });
});

describe("a CLI that prints one JSON result (envelope)", () => {
  const agy = (w, extra) => ({ ...w.opts, product: "antigravity", providersRoot: fixtures, binary: fakeAgy, model: "m1", ...extra });
  const preface = loadProvider("antigravity", fixtures).modes["read-only"].prompt_preface;

  test("a read-only run writes the mode's settings file and puts the prefaced prompt in argv", async () => {
    const w = world({ envelope: { status: "SUCCESS", response: "it is slow because", conversation_id: "conv-1" } });
    const got = await run(agy(w, { use: "investigate", prompt: "why is it slow?" }));
    const folder = join(w.dataDir, "jobs", "no-repo", got.job.id);
    assert.deepEqual(cliArgs(got.job), ["--output-format", "json", "--disable-slash-commands", "--settings", join(folder, "settings.json"), "--model", "m1", `-p=${preface}\n\nwhy is it slow?`]);
    assert.deepEqual(JSON.parse(readFileSync(join(folder, "settings.json"), "utf8")), { agentMode: "", allowNonWorkspaceAccess: false });
    assert.equal(got.job.status, "ok");
    assert.equal(got.job.thread_id, "conv-1");
    assert.equal(got.stdout, "antigravity: ok\nit is slow because\n");
    assert.equal(readFileSync(got.job.final_message_path, "utf8"), "it is slow because");
  });

  test("a per-run effort reaches agy as --effort", async () => {
    const w = world({ envelope: { status: "SUCCESS", response: "ok", conversation_id: "conv-1" } });
    const got = await run(agy(w, { use: "investigate", effort: "high", prompt: "why?" }));
    const args = cliArgs(got.job);
    assert.deepEqual(args.slice(args.indexOf("--model"), -1), ["--model", "m1", "--effort", "high"]);
    assert.equal(got.job.effort, "high");
  });

  test("a non-empty denied_actions array is blocked-by-mode", async () => {
    const w = world({ envelope: { status: "SUCCESS", response: "", denied_actions: [{ action: "write_file", display_name: "Edit" }] } });
    const got = await run(agy(w, { use: "investigate", prompt: "edit it" }));
    assert.equal(got.job.status, "blocked-by-mode");
    assert.deepEqual(got.job.denied_commands, { count: 1, commands: ["Edit"] });
  });

  test("the stderr refusal text alone is blocked-by-mode", async () => {
    const w = world({ envelope: { status: "SUCCESS", response: "" }, stderr: 'jetski: no output produced — a tool required the "command" permission that headless mode cannot prompt for\n' });
    assert.equal((await run(agy(w, { use: "investigate", prompt: "run it" }))).job.status, "blocked-by-mode");
  });

  test("an ERROR result is failed with the CLI's error", async () => {
    const w = world({ envelope: { status: "ERROR", error: "prompt is empty" }, exit: 1 });
    const got = await run(agy(w, { use: "investigate", prompt: "x" }));
    assert.equal(got.stdout, "antigravity: failed (exit 1; prompt is empty)\n");
  });

  test("a signed-out run (agy 1.5.14's envelope) opens the auth breaker and the next run skips", async () => {
    const now = () => Date.UTC(2026, 10, 22, 12, 0, 0);
    const signedOut = { conversation_id: "", status: "ERROR", response: "", error: "authentication failed or timed out", finished_reason: "error" };
    const w = world({ envelope: signedOut, stderr: "Authentication required. Please visit the URL to log in:\nError: authentication timed out.\n", exit: 1 });
    assert.equal((await run(agy(w, { use: "investigate", prompt: "x", now }))).job.status, "failed");
    assert.equal(readBreaker(w.dataDir, "antigravity")?.class, "auth");
    assert.match((await run(agy(w, { use: "investigate", prompt: "x", now }))).stdout, /^antigravity: unavailable: /);
  });

  test("a RESOURCE_EXHAUSTED error opens the usage-limit breaker (the wording is judgment: none was captured from agy 1.5.14)", async () => {
    const w = world({ envelope: { status: "ERROR", error: "429 RESOURCE_EXHAUSTED: quota exceeded" }, exit: 1 });
    await run(agy(w, { use: "investigate", prompt: "x", now: () => Date.UTC(2026, 10, 22, 12, 0, 0) }));
    assert.equal(readBreaker(w.dataDir, "antigravity")?.class, "usage-limit");
  });


  test("resume passes the thread through the record's resume arguments", async () => {
    const w = world({ envelope: { status: "SUCCESS", response: "one", conversation_id: "conv-7" } });
    await run(agy(w, { use: "investigate", prompt: "one" }));
    const { job } = await run(agy(w, { use: "investigate", prompt: "two", last: true }));
    assert.deepEqual(cliArgs(job).slice(0, 2), ["--conversation", "conv-7"]);
  });

  test("a diff-file review writes the diff into the job's own folder and names the file, never pasting it", async () => {
    const w = world({ envelope: { status: "SUCCESS", response: "No findings." } });
    gitRepo(w.cwd, { "a.txt": "a changed line unique-marker-7f3\n" });
    const got = await review(agy(w, { base: "main", brief: "look for races" }));
    const folder = join(w.dataDir, "jobs", repoKey(w.cwd), got.job.id);
    const args = cliArgs(got.job);
    assert.deepEqual(args.slice(args.indexOf("--add-dir"), args.indexOf("--add-dir") + 2), ["--add-dir", folder]);
    assert.match(readFileSync(join(folder, "review.diff"), "utf8"), /\+a changed line unique-marker-7f3/);
    const prompt = args.at(-1);
    assert.ok(prompt.startsWith(`-p=${preface}\n\nlook for races\n\n`), prompt);
    assert.ok(prompt.includes(join(folder, "review.diff")));
    assert.ok(!prompt.includes("unique-marker-7f3"));
    assert.match(got.stdout, /^antigravity: ran \(reviewed 1 changed file against [0-9a-f]{8}\)\nNo findings\.\n$/);
  });

  test("with no model configured the run uses agy's own default and passes no --model", async () => {
    const w = world({ envelope: { status: "SUCCESS", response: "x" } });
    const got = await run(agy(w, { use: "investigate", prompt: "x", model: undefined }));
    assert.equal(got.job.status, "ok");
    assert.ok(!cliArgs(got.job).includes("--model"));
  });
});

describe("availability and the breaker", () => {
  const noon = Date.UTC(2026, 10, 21, 12, 0, 0);
  const hours = (n) => n * 3_600_000;

  test("a missing CLI gives the pointer to update and no answer", async () => {
    const w = world();
    const empty = join(w.cwd, "empty-path");
    mkdirSync(empty);
    const got = await run({ ...w.opts, binary: undefined, env: { PATH: empty, PATHEXT: ".EXE" }, use: "task", prompt: "fix it", now: () => noon });
    assert.match(got.stdout, /^codex: unavailable: codex not found .*external-agents update codex\n$/);
    assert.equal(got.code, 4);
    assert.deepEqual(listJobs(w.dataDir, "no-repo"), []);
    assert.equal(readBreaker(w.dataDir, "codex").class, "binary-missing");
  });

  test("a logged-out CLI gives the pointer to update and is never asked to run", async () => {
    const w = world({ login_exit: 1, stdout: clean, final: "an answer that must not appear" });
    const got = await run({ ...w.opts, use: "task", prompt: "fix it", now: () => noon });
    assert.equal(got.stdout, "codex: unavailable: not logged in. Log in with codex, then run: external-agents update codex\n");
    assert.equal(got.code, 4);
    assert.equal(launched(w).length, 0);
    assert.equal(readBreaker(w.dataDir, "codex").class, "not-logged-in");
  });

  test("an open breaker refuses with the next trial time, then lets one trial through and closes on success", async () => {
    const w = world({ login_exit: 1 });
    gitRepo(w.cwd, { "a.txt": "two\n" });
    await run({ ...w.opts, use: "task", prompt: "fix it", now: () => noon });
    w.set({ stdout: clean, final: "done" });
    const before = w.calls().length;
    const refused = await run({ ...w.opts, use: "task", prompt: "fix it", now: () => noon + hours(23) });
    assert.match(refused.stdout, /^codex: unavailable: not logged in; not retried until 2026-11-22T12:00:00\.000Z\./);
    assert.equal(refused.code, 4);
    assert.equal(w.calls().length, before, "nothing is started while the breaker is open");

    const viaReview = await review({ ...w.opts, base: "main", now: () => noon + hours(23) });
    assert.match(viaReview.stdout, /^codex: skipped \(/);

    const trial = await run({ ...w.opts, use: "task", prompt: "fix it", now: () => noon + hours(24) });
    assert.equal(trial.job.status, "ok");
    assert.equal(readBreaker(w.dataDir, "codex"), null);
  });

  test("breaker.cooldown_hours sets the wait", async () => {
    const w = world({ login_exit: 1 }, { local: "schema: 1\nbreaker:\n  cooldown_hours: 2\n" });
    await run({ ...w.opts, use: "task", prompt: "fix it", now: () => noon });
    assert.equal(readBreaker(w.dataDir, "codex").next_trial_at, "2026-11-21T14:00:00.000Z");
  });

  test("a usage limit that names its reset time is retried at that time (the message wording is judgment: none was captured from Codex 0.168.0)", async () => {
    const limit = { type: "turn.failed", error: { message: "You've hit your usage limit. Upgrade to Pro or try again at 2026-11-22T15:00:00Z." } };
    const w = world({ stdout: events(...opened, limit), exit: 1 });
    const got = await run({ ...w.opts, use: "task", prompt: "fix it", now: () => noon });
    assert.equal(got.job.status, "failed");
    const state = readBreaker(w.dataDir, "codex");
    assert.equal(state.class, "usage-limit");
    assert.equal(state.next_trial_at, "2026-11-22T15:00:00.000Z");
  });

  test("a usage limit with no reset time waits the cool-down", async () => {
    const w = world({ stdout: events(...opened, { type: "error", message: "You've hit your usage limit." }), exit: 1 });
    await run({ ...w.opts, use: "task", prompt: "fix it", now: () => noon });
    assert.equal(readBreaker(w.dataDir, "codex").next_trial_at, "2026-11-22T12:00:00.000Z");
  });

  test("a run that finishes well does not close a breaker another run opened meanwhile", async () => {
    const w = world({ stdout: clean, final: "done", sleep_ms: 2500 });
    const slow = run({ ...w.opts, use: "task", prompt: "one", now: () => noon });
    for (let i = 0; i < 200 && launched(w).length === 0; i += 1) await new Promise((r) => setTimeout(r, 25));
    w.set({ stdout: events(...opened, { type: "error", message: "You've hit your usage limit." }), exit: 1 });
    await run({ ...w.opts, use: "task", prompt: "two", now: () => noon + 1000 });
    assert.equal((await slow).job.status, "ok");
    assert.equal(readBreaker(w.dataDir, "codex")?.class, "usage-limit");
  });

  test("a blocked run never opens the breaker", async () => {
    const w = world({ stdout_file: join(fixtures, "events-default.jsonl"), final: "x" });
    await run({ ...w.opts, use: "investigate", prompt: "write", now: () => noon });
    assert.equal(readBreaker(w.dataDir, "codex"), null);
  });
});

describe("timeout, cancel and status", () => {
  const gone = (pid) => {
    try {
      process.kill(pid, 0);
      return false;
    } catch {
      return true;
    }
  };
  const until = async (check) => {
    for (let i = 0; i < 200; i += 1) {
      const value = check();
      if (value) return value;
      await new Promise((r) => setTimeout(r, 50));
    }
    throw new Error("condition not reached");
  };

  test("a run past codex.timeout_seconds is killed and recorded timed-out", async () => {
    const w = world({ stdout: events(...opened), sleep_ms: 60_000 }, { local: "schema: 1\ncodex:\n  timeout_seconds: 1\n" });
    const got = await run({ ...w.opts, use: "task", prompt: "fix it" });
    assert.equal(got.job.status, "timed-out");
    assert.equal(got.stdout, "codex: timed-out (no result after 1 s)\n");
    assert.ok(await until(() => gone(got.job.pid)));
    assert.equal(readBreaker(w.dataDir, "codex"), null, "a timeout never opens the breaker");
  });

  test("cancel kills the run, and the runner keeps the cancelled status", async () => {
    const w = world({ stdout: events(...opened), sleep_ms: 60_000 });
    const pending = run({ ...w.opts, use: "task", prompt: "fix it" });
    const running = await until(() => listJobs(w.dataDir, "no-repo").find((j) => j.status === "running"));
    assert.equal(status({ ...w.opts, jobId: running.id }).stdout.split("\n")[0], "codex: running");
    const got = cancel({ ...w.opts, jobId: running.id });
    assert.equal(got.stdout, "codex: cancelled (cancelled by request)\n");
    assert.equal(got.code, 0);
    const finished = await pending;
    assert.equal(finished.job.status, "cancelled");
    assert.equal(readJob(w.dataDir, "no-repo", running.id).status, "cancelled");
    assert.notEqual(readJob(w.dataDir, "no-repo", running.id).ended_at, null, "the runner still records when the process ended");
    assert.ok(gone(running.pid));
    assert.match(cancel({ ...w.opts, jobId: running.id }).stdout, /is cancelled; nothing to cancel/);
  });

  test("status marks a running job whose process is gone as failed (process exited)", () => {
    const w = world();
    const dead = spawnSync(process.execPath, ["-e", ""]).pid;
    writeJob(w.dataDir, "no-repo", { id: "dead-job", product: "codex", use: "task", mode: "write", status: "running", pid: dead, pid_started_at: "2026-11-21T12:00:00.0000000Z", started_at: "2026-11-21T12:00:00.000Z", notices: [] });
    writeJob(w.dataDir, "no-repo", { id: "live-job", product: "codex", use: "task", mode: "write", status: "running", pid: process.pid, pid_started_at: pidStartTime(process.pid), started_at: "2026-11-21T12:00:01.000Z", notices: [] });
    assert.equal(status({ ...w.opts }).stdout, "live-job  task  codex: running\ndead-job  task  codex: failed (process exited)\n");
    assert.equal(readJob(w.dataDir, "no-repo", "dead-job").status, "failed");
    assert.equal(readJob(w.dataDir, "no-repo", "live-job").status, "running");
  });

  test("a job whose CLI exited stays running while its runner is still recording the result", () => {
    const w = world();
    const dead = spawnSync(process.execPath, ["-e", ""]).pid;
    writeJob(w.dataDir, "no-repo", { id: "recording-job", product: "codex", use: "task", mode: "write", status: "running", pid: dead, pid_started_at: "2026-11-21T12:00:00.0000000Z", runner_pid: process.pid, runner_started_at: pidStartTime(process.pid), started_at: "2026-11-21T12:00:00.000Z", notices: [] });
    assert.equal(status({ ...w.opts }).stdout, "recording-job  task  codex: running\n");
    assert.equal(readJob(w.dataDir, "no-repo", "recording-job").status, "running");
  });

  test("cancel never kills a pid whose start time is not the job's", () => {
    const w = world();
    writeJob(w.dataDir, "no-repo", { id: "reused", product: "codex", use: "task", mode: "write", status: "running", pid: process.pid, pid_started_at: "1999-01-01T00:00:00.0000000Z", started_at: "2026-11-21T12:00:00.000Z", notices: [] });
    const got = cancel({ ...w.opts, jobId: "reused" });
    assert.equal(got.code, 1);
    assert.match(got.stdout, /is failed; nothing to cancel/);
    writeJob(w.dataDir, "no-repo", { id: "unknown", product: "codex", use: "task", mode: "write", status: "running", pid: process.pid, pid_started_at: null, started_at: "2026-11-21T12:00:00.000Z", notices: [] });
    assert.match(cancel({ ...w.opts, jobId: "unknown" }).stderr, /nothing was killed/);
  });

  test("result relays a finished job's message, and an unknown job is a usage error", async () => {
    const w = world({ stdout: clean, final: "the answer" });
    const { job } = await run({ ...w.opts, use: "task", prompt: "fix it" });
    assert.equal(result({ ...w.opts, jobId: job.id }).stdout, "codex: ok\nthe answer\n");
    assert.equal(result({ ...w.opts, jobId: "nope" }).code, 2);
    assert.equal(result({ ...w.opts, jobId: "../x" }).code, 2);
  });
});

describe("which executable runs", () => {
  const windows = process.platform === "win32";
  function setting(w, name) {
    const dir = join(w.cwd, "..", "tools");
    mkdirSync(dir, { recursive: true });
    const path = join(dir, windows ? `${name}.cmd` : name);
    const fake = join(fixtures, "fake-codex.mjs");
    writeFileSync(path, windows ? `@"${process.execPath}" "${fake}" %*\r\n` : `#!/bin/sh\nexec "${process.execPath}" "${fake}" "$@"\n`);
    chmodSync(path, 0o755);
    return { path, yaml: `schema: 1\ncodex:\n  binary_path: "${path.replace(/\\/g, "/")}"\n` };
  }
  function lookupOnly(w) {
    const empty = join(w.cwd, "..", "empty");
    mkdirSync(empty, { recursive: true });
    return { ...w.opts, binary: undefined, env: { ...w.opts.env, PATH: empty, Path: empty, LOCALAPPDATA: empty, APPDATA: empty } };
  }
  const localFile = "docs/conventions/external-agents.local.yaml";

  test("a binary_path in an untracked personal file is the executable that runs", async () => {
    const w = world({ stdout: clean, final: "done" });
    const chosen = setting(w, "codex");
    gitRepo(w.cwd, { "a.txt": "two\n" });
    writeFileSync(join(w.cwd, localFile), chosen.yaml);
    const got = await run({ ...lookupOnly(w), use: "task", prompt: "fix it" });
    assert.equal(got.job?.status, "ok", got.stdout + got.stderr);
    assert.equal(got.job.argv[0], chosen.path.replace(/\\/g, "/"));
  });

  test("a binary_path in a committed .local.yaml is ignored with a notice", async () => {
    const w = world({ stdout: clean, final: "done" });
    const chosen = setting(w, "codex");
    gitRepo(w.cwd, { [localFile]: chosen.yaml });
    const got = await run({ ...lookupOnly(w), use: "task", prompt: "fix it" });
    assert.equal(got.code, 4, got.stdout + got.stderr);
    assert.match(got.stdout, /^codex: unavailable: codex not found/);
    assert.match(got.stderr, /notice: config: local: codex\.binary_path .*tracked.*ignored/);
    assert.equal(w.calls().length, 0);
  });

  test("a binary_path whose file is not named for the CLI is refused", async () => {
    const w = world({ stdout: clean, final: "done" });
    const chosen = setting(w, "sh");
    writeFileSync(join(w.cwd, localFile), chosen.yaml);
    const got = await run({ ...lookupOnly(w), use: "task", prompt: "fix it" });
    assert.equal(got.code, 2, got.stdout + got.stderr);
    assert.match(got.stdout, /^codex: refused: codex\.binary_path .* is not named codex/);
    assert.equal(w.calls().length, 0);
  });

  test("a cmd.exe-run binary whose own path is unsafe is refused before anything is started", async () => {
    const w = world({ stdout: clean, final: "done" });
    const got = await run({ ...w.opts, binary: { path: "C:\\tools&more\\codex.cmd", args: [], shell: true }, use: "task", prompt: "fix it" });
    assert.equal(got.code, 2);
    assert.match(got.stdout, /^codex: refused: .*tools&more.*codex\.binary_path/);
    assert.equal(readBreaker(w.dataDir, "codex"), null);
  });

  test("a relative PATH entry is never searched", () => {
    const local = mkdtempSync(join(here, ".tmp-path-"));
    try {
      writeFileSync(join(local, windows ? "demo.exe" : "demo"), "", { mode: 0o755 });
      const entry = relative(process.cwd(), local) || ".";
      const record = { product: "demo", binary: { name: "demo" } };
      const env = { PATH: entry, PATHEXT: ".EXE" };
      assert.equal(resolveBinary(record, { env }).path, isAbsolute(entry) ? join(local, windows ? "demo.exe" : "demo") : null);
      assert.equal(resolveBinary(record, { env: { PATH: local, PATHEXT: ".EXE" } }).path, join(local, windows ? "demo.exe" : "demo"));
    } finally {
      rmSync(local, { recursive: true, force: true });
    }
  });
});

describe("provider record", () => {
  test("the bundled codex and antigravity records validate, and the agy tests run on the shipped record", () => {
    assert.deepEqual(validateProvider(codex), []);
    assert.deepEqual(validateProvider(loadProvider("antigravity")), []);
    const copy = (root) => readFileSync(join(root, "providers", "antigravity.yaml"), "utf8");
    assert.equal(copy(fixtures), copy(join(here, "..")), "tests/fixtures/providers/antigravity.yaml must match providers/antigravity.yaml");
  });

  test("a misspelled key is named wherever it sits", () => {
    const record = structuredClone(codex);
    record.prompt_form = "-";
    record.modes.write.sandbox = true;
    record.output.final_arg = "-o";
    record.soft_deny[0].pattern = "x";
    record.review.dir = "--add-dir";
    const problems = validateProvider(record);
    for (const key of ["prompt_form", "modes.write.sandbox", "output.final_arg", "soft_deny[0].pattern", "review.dir"]) {
      assert.ok(problems.includes(`${key}: unknown key`), `${key} in ${problems.join(" | ")}`);
    }
  });

  test("a misspelled key in an add_dir or unsandboxed entry is named, and an opt-in on the read-only mode is refused", () => {
    const record = structuredClone(loadProvider("antigravity"));
    record.modes.write.add_dir.flag = "--add-dir";
    record.modes.write.unsandboxed.auto.mode = "auto";
    record.modes.write.unsandboxed.auto.fallback_warning.log = "--log-file";
    delete record.modes.write.unsandboxed.auto.fallback_warning.log_arg;
    record.modes["read-only"].unsandboxed = { auto: {} };
    const problems = validateProvider(record);
    for (const key of ["modes.write.add_dir.flag", "modes.write.unsandboxed.auto.mode", "modes.write.unsandboxed.auto.fallback_warning.log"]) {
      assert.ok(problems.includes(`${key}: unknown key`), `${key} in ${problems.join(" | ")}`);
    }
    assert.ok(problems.includes("modes.write.unsandboxed.auto.fallback_warning.applied: log_arg and applied are set together"), problems.join(" | "));
    assert.ok(problems.includes("modes.read-only.unsandboxed: expected a mapping of opt-in names, on the write mode only"), problems.join(" | "));
  });

  test("a review preface naming a token the runner does not fill is refused", () => {
    const record = structuredClone(codex);
    record.review.brief_preface = "Review {base} at {sha}";
    assert.ok(validateProvider(record).includes("review.brief_preface: unknown token {sha}"), validateProvider(record).join(" | "));
  });

  test("a record with no prompt form or output kind is refused", () => {
    const record = structuredClone(codex);
    delete record.prompt;
    delete record.output;
    const problems = validateProvider(record).join("\n");
    assert.match(problems, /prompt\.form/);
    assert.match(problems, /output\.kind/);
  });
});

describe("the command", () => {
  const invoke = (args, env, input) => cli(args, { env, cwd: scratch, input });
  const { CLAUDE_PLUGIN_DATA: _unset, ...bare } = process.env;

  test("status lists nothing for a fresh data directory", () => {
    const got = invoke(["status"], { ...bare, CLAUDE_PLUGIN_DATA: join(scratch, "external-agents-cli-data") });
    assert.equal(got.stdout, "no jobs for this repository\n");
    assert.equal(got.status, 0);
  });

  test("an installed copy keeps its jobs in the plugin's documented data directory", () => {
    const claude = join(scratch, "home", ".claude");
    const installed = join(claude, "plugins", "cache", "melodic-software", "external-agents", "1.2.3");
    assert.equal(installedDataDir(installed), join(claude, "plugins", "data", "external-agents-melodic-software"));
    assert.equal(installedDataDir(join(scratch, "checkout", "plugins", "external-agents")), null);
  });

  test("another plugin's CLAUDE_PLUGIN_DATA is ignored for an installed copy, refused for a checkout, and this plugin's own is used", () => {
    const claude = join(scratch, "home", ".claude");
    const installed = join(claude, "plugins", "cache", "melodic-software", "external-agents", "1.2.3");
    const own = join(claude, "plugins", "data", "external-agents-melodic-software");
    const foreign = join(claude, "plugins", "data", "codex-openai-codex");
    const checkout = join(scratch, "checkout", "plugins", "external-agents");

    const ignored = dataDirFor({ env: { CLAUDE_PLUGIN_DATA: foreign }, root: installed });
    assert.equal(ignored.dataDir, own);
    assert.match(ignored.notice, /codex-openai-codex.*another plugin/);
    assert.throws(() => dataDirFor({ env: { CLAUDE_PLUGIN_DATA: foreign }, root: checkout }), /codex-openai-codex.*another plugin/);
    assert.deepEqual(dataDirFor({ env: { CLAUDE_PLUGIN_DATA: own }, root: checkout }), { dataDir: own, notice: null });
    assert.deepEqual(dataDirFor({ dataDir: foreign, env: {}, root: checkout }), { dataDir: foreign, notice: null });
  });

  test("an unknown option, a missing prompt and a missing data directory are usage errors", () => {
    assert.equal(invoke(["run", "codex", "--yolo"], bare).status, 2);
    assert.equal(invoke(["status"], bare).status, 2);
    assert.match(invoke(["status"], bare).stderr, /CLAUDE_PLUGIN_DATA is not set/);
    const empty = invoke(["run", "codex", "--use", "task"], { ...bare, CLAUDE_PLUGIN_DATA: join(scratch, "external-agents-cli-data") }, "");
    assert.equal(empty.status, 2);
    assert.match(empty.stdout, /no prompt was given/);
  });

  test("a review usage error still prints the status line first, with the usage on stderr", () => {
    const env = { ...bare, CLAUDE_PLUGIN_DATA: join(scratch, "external-agents-cli-data") };
    const missing = invoke(["review", "codex", "--base", "main", "--brief-file", join(scratch, "no-such-brief.md")], env);
    assert.match(missing.stdout, /^codex: failed \(.*no-such-brief\.md.*\)\n$/);
    assert.match(missing.stderr, /usage: external-agents/);
    assert.equal(missing.status, 2);
    const option = invoke(["review", "codex", "--base", "main", "--yolo"], env);
    assert.equal(option.stdout, "codex: failed (review: unknown option --yolo)\n");
    assert.equal(option.status, 2);
    assert.equal(invoke(["run", "codex", "--yolo"], env).stdout, "", "only review owes its caller a status line");
  });
});

describe("a review that hits an unexpected error", () => {
  const firstLine = /^codex: failed \([^\n]+\)\n$/;

  test("an unusable data directory still gives the status line, the detail on stderr and a non-zero exit", async () => {
    const w = world({ stdout: clean, final: "x" });
    gitRepo(w.cwd, { "a.txt": "two\n" });
    const file = join(w.cwd, "a.txt");
    const got = await review({ ...w.opts, dataDir: join(file, "x"), base: "main" });
    assert.match(got.stdout, firstLine);
    assert.match(got.stderr, /ENOTDIR|ENOENT|EEXIST/);
    assert.equal(got.code, 1);

    const { CLAUDE_PLUGIN_DATA: _unset, ...bare } = process.env;
    const spawned = cli(["review", "codex", "--base", "main"], { cwd: w.cwd, env: { ...bare, CLAUDE_PLUGIN_DATA: join(file, "external-agents-x") } });
    assert.match(spawned.stdout, firstLine);
    assert.equal(spawned.status, 1);
  });

  test("a corrupt breaker file still gives the status line", async () => {
    const w = world({ stdout: clean, final: "x" });
    gitRepo(w.cwd, { "a.txt": "two\n" });
    mkdirSync(join(w.dataDir, "breaker"));
    writeFileSync(join(w.dataDir, "breaker", "codex.json"), "{not json");
    const got = await review({ ...w.opts, base: "main" });
    assert.match(got.stdout, firstLine);
    assert.equal(got.code, 1);
    assert.equal(w.calls().length, 0);
  });
});

describe("robustness", () => {
  test("a denied command holding a newline stays on the one status line", async () => {
    const denied = { type: "item.completed", item: { id: "item_1", type: "command_execution", command: "echo one\necho two > x.txt", aggregated_output: "Access is denied", exit_code: 1, status: "failed" } };
    const w = world({ stdout: events(...opened, denied, said, completed), final: "done" });
    const got = await run({ ...w.opts, use: "investigate", prompt: "write" });
    assert.equal(got.stdout, "codex: blocked-by-mode (1 command blocked by read-only mode: echo one echo two > x.txt)\ndone\n");
  });

  test("a login check that cannot run is failed, and the breaker stays closed", async () => {
    const w = world();
    const got = await run({ ...w.opts, binary: { path: join(scratch, "no-such-cli"), args: [], shell: false }, use: "task", prompt: "fix it" });
    assert.match(got.stdout, /^codex: failed \(could not check the login state: .*ENOENT.*\)\n$/);
    assert.equal(got.code, 1);
    assert.equal(readBreaker(w.dataDir, "codex"), null);
  });

  test("a run refused after its job folder exists leaves no folder behind", { skip: process.platform !== "win32" }, async () => {
    const w = world({ stdout: clean, final: "done" });
    const dataDir = join(w.dataDir, "da&ta");
    mkdirSync(dataDir);
    const got = await run({ ...w.opts, dataDir, binary: fakeCmd, use: "task", prompt: "fix it" });
    assert.equal(got.code, 2);
    assert.match(got.stdout, /^codex: refused: .*da&ta.*cannot be passed safely/);
    assert.deepEqual(readdirSync(join(dataDir, "jobs", "no-repo")), []);
  });

  test("a job file that cannot be written once the CLI has started stops the CLI and reports failed", async () => {
    const w = world({ stdout: events(...opened), sleep_ms: 60_000 });
    let pid = null;
    const refusingWrite = (dataDir, key, job) => {
      if (job.status !== "running") return writeJob(dataDir, key, job);
      pid = job.pid;
      throw new Error("disk full");
    };
    const got = await run({ ...w.opts, writeJob: refusingWrite, use: "task", prompt: "fix it" });
    assert.equal(got.stdout, "codex: failed (could not write the job file (disk full); the CLI was stopped)\n");
    assert.equal(got.code, 1);
    assert.ok(Number.isInteger(pid), "the CLI had started");
    let gone = false;
    for (let i = 0; i < 100 && !gone; i += 1) {
      try {
        process.kill(pid, 0);
        await new Promise((r) => setTimeout(r, 50));
      } catch {
        gone = true;
      }
    }
    assert.ok(gone, `pid ${pid} still running`);
    assert.deepEqual(listJobs(w.dataDir, "no-repo"), []);
  });

  test("status, result and cancel turn an unexpected error into one line on stderr and a non-zero exit", () => {
    const oneLine = /^external-agents: [^\n]+\n$/;
    const w = world();
    const dir = join(w.dataDir, "jobs", "no-repo");
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "corrupt.json"), "{not json");
    const listed = status({ ...w.opts });
    assert.match(listed.stderr, oneLine);
    assert.notEqual(listed.code, 0);

    const dead = spawnSync(process.execPath, ["-e", ""]).pid;
    const other = world();
    const otherDir = join(other.dataDir, "jobs", "no-repo");
    mkdirSync(otherDir, { recursive: true });
    writeFileSync(join(otherDir, "odd.json"), JSON.stringify({ id: "../odd", product: "codex", use: "task", mode: "write", status: "running", pid: dead, pid_started_at: "x", started_at: "2026-11-21T12:00:00.000Z", notices: [] }));
    for (const [name, fn] of Object.entries({ status, result, cancel })) {
      const got = fn({ ...other.opts, jobId: "odd" });
      assert.match(got.stderr, oneLine, name);
      assert.notEqual(got.code, 0, name);
    }
  });

  test("a convention-home helper that cannot run is named, with the home that is read instead", () => {
    const broken = conventionHome(scratch, join(scratch, "no-such-helper.sh"));
    assert.equal(broken.home, "docs/conventions");
    assert.match(broken.problem, /convention-home helper did not run/);
    assert.deepEqual(conventionHome(scratch), { home: "docs/conventions", problem: null });
  });
});
