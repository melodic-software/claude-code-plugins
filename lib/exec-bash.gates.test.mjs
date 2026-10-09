// Launch flags of exec-bash.mjs that decide, before bash starts, whether a row
// has anything to do: --skip-if-all-false (option list) and
// --skip-unless-stdin-contains (payload text). The live cases run on every
// platform, Windows included.
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { needsStdin, optionGateOpen, parseLaunchArgs, stdinGateOpen, stdinIdleMs } from "./exec-bash.mjs";

const VERIFY = "CLI_FLAG_VERIFY_ENABLED,SKILL_REFERENCE_VERIFY_ENABLED,STALE_PATH_VERIFY_ENABLED";
const NAMES = VERIFY.split(",");
const env = (values) =>
  Object.fromEntries(
    NAMES.flatMap((name, i) => (values[i] === undefined ? [] : [[`CLAUDE_PLUGIN_OPTION_${name}`, values[i]]])),
  );

// --- parsing -----------------------------------------------------------------
const verify = parseLaunchArgs(["--skip-if-all-false", VERIFY, "/hooks/run-guards.sh", "cli-flag-verify.sh"]);
assert.equal(verify.script, "/hooks/run-guards.sh");
assert.deepEqual(verify.args, ["cli-flag-verify.sh"]);
assert.equal(needsStdin(verify.gates), false);

for (const bad of ["", "A,,B", "A,", ",A", "cli_flag", "-A", "A B"]) {
  const parsed = parseLaunchArgs(["--skip-if-all-false", bad, "x.sh"]);
  assert.match(parsed.error ?? "", /^usage: --skip-if-all-false .*CLAUDE_PLUGIN_OPTION_/, JSON.stringify(bad));
}
assert.match(parseLaunchArgs(["--skip-if-all-false"]).error, /^usage: --skip-if-all-false /);
assert.match(parseLaunchArgs(["--skip-unless-stdin-contains", ""]).error, /^usage: --skip-unless-stdin-contains /);
assert.match(parseLaunchArgs(["--skip-unless-stdin-contains", "x"]).error, /^usage: node exec-bash\.mjs /);

// Flags combine in any order; the old gate keeps its meaning beside a new one.
const scan = parseLaunchArgs([
  "--require-true",
  "TEST_GUARDS_ENABLED",
  "--skip-unless-stdin-contains",
  "bashEditDiff",
  "/hooks/test-scan-bash.sh",
]);
assert.equal(scan.script, "/hooks/test-scan-bash.sh");
assert.equal(needsStdin(scan.gates), true);
assert.equal(optionGateOpen(scan.gates, {}), false);
assert.equal(optionGateOpen(scan.gates, { CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED: "true" }), true);

// --- --skip-if-all-false: skips only when every switch is exactly "false" -----
// Each verifier runs when its variable is unset, empty or "true", and exits at
// its switch otherwise; the gate is stricter still and runs on any value that is
// not literally "false", so a malformed value still starts bash.
assert.equal(optionGateOpen(verify.gates, env(["false", "false", "false"])), false);
for (const on of [undefined, "", "true", "TRUE", "0", " false", "False"]) {
  for (let i = 0; i < 3; i += 1) {
    const values = ["false", "false", "false"];
    values[i] = on;
    assert.equal(optionGateOpen(verify.gates, env(values)), true, `${NAMES[i]}=${JSON.stringify(on)}`);
  }
}
assert.equal(optionGateOpen(verify.gates, {}), true);

// --- --skip-unless-stdin-contains ----------------------------------------------
assert.equal(stdinGateOpen(scan.gates, Buffer.from('{"tool_response":{"bashEditDiff":{}}}')), true);
assert.equal(stdinGateOpen(scan.gates, Buffer.from('{"tool_response":{"stdout":"ok"}}')), false);
assert.equal(stdinGateOpen(scan.gates, Buffer.alloc(0)), false);

// The idle bound reads stdin_read_timeout the way hook::resolve_read_timeout_to does.
assert.equal(stdinIdleMs({}), 2000);
assert.equal(stdinIdleMs({ CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT: "0.5" }), 500);
assert.equal(stdinIdleMs({ CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT: "5" }), 5000);
for (const bad of ["0", "0.0", "-1", "abc", "1e3", "", "0.000001"]) {
  assert.equal(stdinIdleMs({ CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT: bad }), 2000, bad);
}

// --- live: a skipped row never resolves bash ----------------------------------
// With an empty PATH on a stubbed win32 no bash resolves, so a launcher that got
// as far as resolving prints "no bash found" and exits 1; a skipped row exits 0
// silently.
const launcher = fileURLToPath(new URL("./exec-bash.mjs", import.meta.url));
const root = mkdtempSync(path.join(tmpdir(), "exec-bash-gates-"));
process.on("exit", () => rmSync(root, { recursive: true, force: true }));
const stub = path.join(root, "win32-stub.mjs");
writeFileSync(stub, 'Object.defineProperty(process, "platform", { value: "win32" });\n');

function runNoBash(args, extraEnv = {}, input = "") {
  return spawnSync(process.execPath, ["--import", pathToFileURL(stub).href, launcher, ...args, "x.sh"], {
    env: { SystemRoot: process.env.SystemRoot, PATH: "", ...extraEnv },
    input,
    encoding: "utf8",
  });
}
function assertSkipped(run, label) {
  assert.equal(run.status, 0, `${label}: ${run.stderr}`);
  assert.equal(run.stderr, "", label);
  assert.equal(run.stdout, "", label);
}
function assertReachedBash(run, label) {
  assert.equal(run.status, 1, label);
  assert.match(run.stderr, /no bash found/, label);
}

const editMd = JSON.stringify({ hook_event_name: "PostToolUse", tool_name: "Edit", tool_input: { file_path: "a.md" } });
assertSkipped(runNoBash(["--skip-if-all-false", VERIFY], env(["false", "false", "false"]), editMd), "all three off");
assertReachedBash(runNoBash(["--skip-if-all-false", VERIFY], env(["false", "true", "false"]), editMd), "one on");
assertReachedBash(runNoBash(["--skip-if-all-false", VERIFY], env(["false", "false"]), editMd), "one unset");
assertReachedBash(runNoBash(["--skip-if-all-false", VERIFY], {}, editMd), "all unset");

// A malformed list is a launcher usage error: exit 1, nothing on stdout, one
// stderr line under 240 characters, and no hook runs.
for (const args of [["--skip-if-all-false", "a,b"], ["--skip-if-all-false", "A,,B"], ["--skip-unless-stdin-contains", ""]]) {
  const run = runNoBash(args, {}, editMd);
  assert.equal(run.status, 1, JSON.stringify(args));
  assert.equal(run.stdout, "", JSON.stringify(args));
  assert.equal(run.stderr.split("\n").length, 2, run.stderr);
  assert.ok(run.stderr.length < 240, run.stderr);
  assert.match(run.stderr, /^exec-bash: the launcher itself was called wrongly, so no hook ran: usage: --skip-/);
}

const flag = ["--skip-unless-stdin-contains", "bashEditDiff"];
assertSkipped(runNoBash(flag, {}, '{"tool_name":"Bash","tool_response":{"stdout":"x"}}'), "no diff");
assertSkipped(runNoBash(flag, {}, ""), "empty stdin");
assertReachedBash(runNoBash(flag, {}, '{"tool_response":{"bashEditDiff":{"changedFiles":[]}}}'), "diff");

// A closed option gate exits before stdin is read: stdin left open does not hold it.
function runOpen(args, extraEnv, { writeAfterMs = null, payload = "" } = {}) {
  return new Promise((resolve) => {
    const started = Date.now();
    const child = spawn(process.execPath, ["--import", pathToFileURL(stub).href, launcher, ...args], {
      env: { SystemRoot: process.env.SystemRoot, PATH: "", ...extraEnv },
    });
    let stderr = "";
    child.stderr.on("data", (d) => {
      stderr += d;
    });
    child.stdin.on("error", () => {});
    if (writeAfterMs !== null) setTimeout(() => child.stdin.end(payload), writeAfterMs);
    child.on("exit", (code) => {
      child.stdin.destroy();
      resolve({ code, stderr, ms: Date.now() - started });
    });
  });
}

const gated = await runOpen(["--require-true", "TEST_GUARDS_ENABLED", ...flag, "x.sh"], {
  CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT: "30",
});
assert.equal(gated.code, 0, gated.stderr);
assert.ok(gated.ms < 10000, `closed gate waited on stdin for ${gated.ms} ms`);

// A stdin that stalls past the idle bound exits 0 without running the script.
const stalled = await runOpen([...flag, "x.sh"], { CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT: "0.3" });
assert.equal(stalled.code, 0, stalled.stderr);
assert.equal(stalled.stderr, "");

// A payload that arrives inside the idle bound is still read.
const late = await runOpen([...flag, "x.sh"], { CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT: "5" }, {
  writeAfterMs: 300,
  payload: '{"bashEditDiff":{}}',
});
assertReachedBash({ status: late.code, stderr: late.stderr }, "payload inside the bound");

// --- live with bash: the script gets the payload byte for byte -----------------
const echoScript = path.join(root, "echo-stdin.sh");
writeFileSync(echoScript, "cat\n");
function runBash(args, input, extraEnv = {}) {
  return spawnSync(process.execPath, [launcher, ...args, echoScript], {
    env: { ...process.env, ...extraEnv },
    input,
  });
}
const big = Buffer.from(`{"tool_response":{"bashEditDiff":{"x":"${"y".repeat(200 * 1024)}"}}}`);
const unicode = Buffer.from('{"tool_response":{"bashEditDiff":{"path":"tëst-ü-日本.test.ts"}}}');
const crlf = Buffer.from('{"tool_response":\r\n{"bashEditDiff":{"a":"b\r\n"}}}\r\n');
for (const [label, payload] of [
  ["over 64 KB", big],
  ["non-ASCII", unicode],
  ["CRLF", crlf],
]) {
  const run = runBash(flag, payload);
  assert.equal(run.status, 0, `${label}: ${run.stderr}`);
  assert.ok(Buffer.compare(run.stdout, payload) === 0, `${label}: payload changed on the way to the script`);
}

// A payload dripped in chunks with gaps inside the idle bound arrives whole.
function dripRun(args, chunks, gapMs, extraEnv) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [launcher, ...args, echoScript], { env: { ...process.env, ...extraEnv } });
    const out = [];
    child.stdout.on("data", (d) => out.push(d));
    child.stdin.on("error", () => {});
    let i = 0;
    const next = () => {
      if (i === chunks.length) return child.stdin.end();
      child.stdin.write(chunks[i]);
      i += 1;
      setTimeout(next, gapMs);
    };
    next();
    child.on("close", (code) => resolve({ code, stdout: Buffer.concat(out) }));
  });
}
const drip = ['{"tool_response":', '{"bashEd', 'itDiff":{', '"a":1}}}'];
const dripped = await dripRun(flag, drip, 150, { CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT: "1" });
assert.equal(dripped.code, 0);
assert.equal(dripped.stdout.toString(), drip.join(""));

// A row without a stdin flag keeps stdin inherited: a payload that starts later
// than the stdin flag's idle bound still reaches the script.
const delayed = await new Promise((resolve) => {
  const child = spawn(process.execPath, [launcher, echoScript], {
    env: { ...process.env, CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT: "0.2" },
  });
  const out = [];
  child.stdout.on("data", (d) => out.push(d));
  setTimeout(() => child.stdin.end("late payload"), 800);
  child.on("close", (code) => resolve({ code, stdout: Buffer.concat(out).toString() }));
});
assert.equal(delayed.code, 0);
assert.equal(delayed.stdout, "late payload");

console.log("exec-bash gates: option list, stdin predicate, stall, and byte-for-byte delivery passed.");
