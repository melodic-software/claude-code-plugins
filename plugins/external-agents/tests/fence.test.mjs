import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { review, run, status } from "../scripts/lib/runner.mjs";
import { assertNoBypass, clean, cliArgs, fakeAgy, fixtures, gitRepo, scratch, tests, world } from "./support/world.mjs";

describe("write fences and extra writable directories", () => {
  const agyWrite = "schema: 1\nantigravity:\n  uses:\n    task:\n      mode: write\n";
  const agy = (w, extra) => ({ ...w.opts, product: "antigravity", providersRoot: fixtures, binary: fakeAgy, model: "m1", use: "task", mode: "write", prompt: "fix it", ...extra });
  const dirs = (w, ...names) => names.map((name) => {
    const dir = join(dirname(w.cwd), name);
    mkdirSync(dir, { recursive: true });
    return dir;
  });
  const folderOf = (w, job) => join(w.dataDir, "jobs", "no-repo", job.id);
  const settingsOf = (w, job) => JSON.parse(readFileSync(join(folderOf(w, job), "settings.json"), "utf8"));
  // Settings and mode values the runner writes for the default fence, from
  // https://antigravity.google/docs/cli/modes and https://antigravity.google/docs/sandbox#cli-configuration.
  const HARD_FENCE = { enableTerminalSandbox: true, toolPermission: "proceed-in-sandbox", allowNonWorkspaceAccess: false };
  const AUTO_FALLBACK = "warning: --mode auto is not available for this account; continuing in the default mode.\n";
  const refusedBeforeStart = (w, got, pattern) => {
    assert.equal(got.code, 2, got.stdout);
    assert.match(got.stdout, pattern);
    assert.deepEqual(w.calls(), [], "the CLI is never started");
  };

  test("codex passes each --add-dir as its own --add-dir argument, records them, and status prints them with the fence", async () => {
    const w = world({ stdout: clean, final: "done" });
    const [a, b] = dirs(w, "shared-a", "shared-b");
    const { job } = await run({ ...w.opts, use: "task", addDirs: [a, b], prompt: "fix it" });
    const final = join(folderOf(w, job), "final.txt");
    assert.deepEqual(cliArgs(job), ["exec", "--json", "-o", final, "--sandbox", "workspace-write", "-c", 'approval_policy="never"', "--add-dir", a, "--add-dir", b, "-"]);
    assert.deepEqual(job.add_dirs, [a, b]);
    assert.equal(job.fence, "sandbox");
    const shown = status({ ...w.opts, jobId: job.id }).stdout;
    assert.match(shown, /^fence: sandbox$/m);
    assert.ok(shown.split("\n").includes(`add_dirs: ${a}, ${b}`), shown);
    assertNoBypass(job.argv);
  });

  test("a run without --add-dir records no added directories and passes no --add-dir", async () => {
    const w = world({ stdout: clean, final: "done" });
    const { job } = await run({ ...w.opts, use: "task", prompt: "fix it" });
    assert.ok(!cliArgs(job).includes("--add-dir"));
    assert.equal(Object.hasOwn(job, "add_dirs"), false);
    assert.match(status({ ...w.opts, jobId: job.id }).stdout, /^add_dirs: $/m);
  });

  test("--add-dir is refused for a relative path, a missing path and a file", async () => {
    const w = world({ stdout: clean, final: "done" });
    const file = join(dirname(w.cwd), "not-a-dir.txt");
    writeFileSync(file, "x\n");
    refusedBeforeStart(w, await run({ ...w.opts, use: "task", addDirs: ["shared"], prompt: "x" }), /^codex: refused: --add-dir "shared" is not an absolute path/);
    refusedBeforeStart(w, await run({ ...w.opts, use: "task", addDirs: [join(dirname(w.cwd), "missing")], prompt: "x" }), /is not an existing directory/);
    refusedBeforeStart(w, await run({ ...w.opts, use: "task", addDirs: [file], prompt: "x" }), /is not an existing directory/);
  });

  test("--add-dir is refused on a read-only run, whether asked for or set by the use's ceiling", async () => {
    const w = world({ stdout: clean, final: "done" });
    const [a] = dirs(w, "shared");
    refusedBeforeStart(w, await run({ ...w.opts, use: "investigate", addDirs: [a], prompt: "x" }), /^codex: refused: --add-dir needs a write run, and this run is read-only\n/);
    refusedBeforeStart(w, await run({ ...w.opts, use: "task", mode: "read-only", addDirs: [a], prompt: "x" }), /needs a write run/);
    const lowered = await run(agy(w, { addDirs: [a] }));
    refusedBeforeStart(w, lowered, /^antigravity: refused: --add-dir needs a write run, and this run is read-only because antigravity\.uses\.task\.mode is read-only/);
  });

  test("--add-dir is refused on a review, and on a resumed codex thread", async () => {
    const w = world({ stdout: clean, final: "done" });
    const [a] = dirs(w, "shared");
    gitRepo(w.cwd, { "a.txt": "two\n" });
    const got = await review({ ...w.opts, base: "main", addDirs: [a] });
    assert.equal(got.code, 2);
    assert.equal(got.stdout, "codex: failed (a review is read-only and takes no --add-dir or --unsandboxed)\n");
    await run({ ...w.opts, use: "task", prompt: "one" });
    const before = w.calls().length;
    const resumed = await run({ ...w.opts, use: "task", last: true, addDirs: [a], prompt: "two" });
    assert.equal(resumed.code, 2);
    assert.match(resumed.stdout, /^codex: refused: codex takes --add-dir on run only, and this is a resume/);
    assert.equal(w.calls().length, before);
  });

  test("codex declares no --unsandboxed opt-in, so asking for one is refused", async () => {
    const w = world({ stdout: clean, final: "done" });
    refusedBeforeStart(w, await run({ ...w.opts, use: "task", unsandboxed: "auto", prompt: "x" }), /^codex: refused: codex has no --unsandboxed "auto"\n/);
  });

  test("an antigravity write run is fenced by default: accept-edits, the terminal sandbox, and its --add-dir values", async () => {
    const w = world({ envelope: { status: "SUCCESS", response: "done", conversation_id: "conv-1" } }, { local: agyWrite });
    const [a] = dirs(w, "shared");
    const got = await run(agy(w, { addDirs: [a] }));
    const { job } = got;
    assert.deepEqual(cliArgs(job), ["--mode", "accept-edits", "--output-format", "json", "--disable-slash-commands", "--settings", join(folderOf(w, job), "settings.json"), "--add-dir", a, "--model", "m1", "-p=fix it"]);
    assert.deepEqual(settingsOf(w, job), HARD_FENCE);
    assert.equal(job.fence, "sandbox");
    assert.deepEqual(job.add_dirs, [a]);
    assert.match(status({ ...w.opts, jobId: job.id }).stdout, /^fence: sandbox$/m);
    assert.ok(!job.argv.some((arg) => /dangerously|^auto$|--log-file/.test(arg)), job.argv.join(" "));
  });

  test("a resumed antigravity write run keeps the fence and takes --add-dir", async () => {
    const w = world({ envelope: { status: "SUCCESS", response: "done", conversation_id: "conv-1" } }, { local: agyWrite });
    const [a] = dirs(w, "shared");
    await run(agy(w));
    const { job } = await run(agy(w, { last: true, addDirs: [a] }));
    assert.deepEqual(cliArgs(job).slice(0, 4), ["--conversation", "conv-1", "--mode", "accept-edits"]);
    assert.ok(cliArgs(job).join(" ").includes(`--add-dir ${a}`));
  });

  test("an outside-the-sandbox request the fenced run cannot prompt for is recorded blocked-by-mode", async () => {
    const refusal = 'jetski: no output produced — a tool required the "command" permission that headless mode cannot prompt for\n';
    const w = world({ envelope: { status: "SUCCESS", response: "" }, stderr: refusal }, { local: agyWrite });
    const got = await run(agy(w));
    assert.equal(got.job.status, "blocked-by-mode");
    assert.equal(got.job.fence, "sandbox");
    assert.equal(got.code, 3);
    assert.match(got.stdout, /^antigravity: blocked-by-mode \(.*1 command blocked by write mode: permission that headless mode cannot prompt for\)\n/);
  });

  test("--unsandboxed auto restores --mode auto with workspace-only settings, records the fence, and passes agy a per-run log file", async () => {
    const w = world({ envelope: { status: "SUCCESS", response: "done" } }, { local: agyWrite });
    const { job } = await run(agy(w, { unsandboxed: "auto" }));
    const folder = folderOf(w, job);
    assert.deepEqual(cliArgs(job), ["--mode", "auto", "--output-format", "json", "--disable-slash-commands", "--settings", join(folder, "settings.json"), "--log-file", join(folder, "cli.log"), "--model", "m1", "-p=fix it"]);
    assert.deepEqual(settingsOf(w, job), { allowNonWorkspaceAccess: false });
    assert.equal(job.fence, "unsandboxed auto");
    assert.match(status({ ...w.opts, jobId: job.id }).stdout, /^fence: unsandboxed auto$/m);
  });

  test("--unsandboxed is refused on a read-only run and for a name the provider does not declare", async () => {
    const w = world({ envelope: { status: "SUCCESS", response: "done" } }, { local: agyWrite });
    refusedBeforeStart(w, await run(agy(w, { use: "investigate", mode: undefined, unsandboxed: "auto" })), /^antigravity: refused: --unsandboxed needs a write run, and this run is read-only\n/);
    refusedBeforeStart(w, await run(agy(w, { unsandboxed: "full" })), /^antigravity: refused: antigravity has no --unsandboxed "full"; it takes auto\n/);
  });

  test("the auto-mode warning is a fallback notice only when agy's log for the run never applied auto mode", async () => {
    const applied = world({ envelope: { status: "SUCCESS", response: "done" }, stderr: AUTO_FALLBACK, log: "printmode.go:903 --mode auto is unavailable (rollout flag off)\nsilent auth succeeded\nSetCycleMode called: auto\n" }, { local: agyWrite });
    const ok = await run(agy(applied, { unsandboxed: "auto" }));
    assert.equal(ok.job.status, "ok");
    assert.deepEqual(ok.job.notices, ['the CLI warned "--mode auto is not available", but its log shows the mode was applied ("SetCycleMode called: auto")']);

    const fellBack = world({ envelope: { status: "SUCCESS", response: "done" }, stderr: AUTO_FALLBACK, log: "printmode.go:903 --mode auto is unavailable (rollout flag off)\n" }, { local: agyWrite });
    const fallback = await run(agy(fellBack, { unsandboxed: "auto" }));
    assert.equal(fallback.job.status, "ok", "a notice-level warning never changes the status");
    assert.deepEqual(fallback.job.notices, ["the CLI warned: --mode auto is not available"]);
    assert.match(fallback.stderr, /^notice: the CLI warned: --mode auto is not available$/m);
  });

  test("the auto-mode warning is no notice on the default fence, which never asks for auto", async () => {
    const w = world({ envelope: { status: "SUCCESS", response: "done" }, stderr: AUTO_FALLBACK }, { local: agyWrite });
    assert.deepEqual((await run(agy(w))).job.notices, []);
  });

  test("the command collects every --add-dir, refusing the first bad one before anything starts", () => {
    const bin = join(tests, "..", "bin", "external-agents");
    const { CLAUDE_PLUGIN_DATA: _unset, ...bare } = process.env;
    const env = { ...bare, CLAUDE_PLUGIN_DATA: join(scratch, "external-agents-cli-data") };
    const got = spawnSync(process.execPath, [bin, "run", "codex", "--use", "task", "--add-dir", scratch, "--add-dir", "relative/dir"], { encoding: "utf8", env, cwd: scratch, input: "fix it" });
    assert.equal(got.status, 2);
    assert.equal(got.stdout, 'codex: refused: --add-dir "relative/dir" is not an absolute path\n');
    const onReview = spawnSync(process.execPath, [bin, "review", "codex", "--base", "main", "--add-dir", scratch], { encoding: "utf8", env, cwd: scratch });
    assert.equal(onReview.status, 2);
    assert.equal(onReview.stdout, "codex: failed (review: unknown option --add-dir)\n");
  });
});
