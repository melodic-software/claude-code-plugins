// Launch flags of exec-bash.mjs that decide, before bash starts, whether a row
// has anything to do: --skip-if-all-false (option list),
// --skip-unless-stdin-contains (payload text), the --run-if-any-set /
// --run-if-settings-mention any-of gate (autonomy's lane-stop gate) and
// --skip-unless-marker (disk-hygiene's guard-launch monitor). The live cases
// run on every platform, Windows included.
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";
import {
  needsStdin,
  optionGateOpen,
  parseLaunchArgs,
  payloadSessionId,
  settingsMention,
  stdinGateOpen,
  stdinIdleMs,
  stdinStallOpen,
  userSettingsFile,
} from "./exec-bash.mjs";

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

// --- the lane-stop gate's any-of gate: parsing ----------------------------------
const LANE = ["--run-if-any-set", "LANE_STOP_GATE_ARM_ID,LANE_STOP_GATE_ENABLED", "--run-if-settings-mention", "lane_stop_gate"];
for (const bad of ["", "A,,B", "lane_stop_gate_arm_id", "-A"]) {
  assert.match(parseLaunchArgs(["--run-if-any-set", bad, "x.sh"]).error ?? "", /^usage: --run-if-any-set /, bad);
}
assert.match(parseLaunchArgs(["--run-if-settings-mention", "", "x.sh"]).error ?? "", /^usage: --run-if-settings-mention /);
assert.match(parseLaunchArgs(["--skip-unless-marker", "", "x.sh"]).error ?? "", /^usage: --skip-unless-marker /);
assert.match(parseLaunchArgs(["--marker-root"]).error ?? "", /^usage: --marker-root /);
assert.match(parseLaunchArgs(["--marker-root", "--skip-unless-marker", "m", "x.sh"]).error ?? "", /^usage: --marker-root /);
// An unset ${CLAUDE_PLUGIN_DATA} substitutes as empty: no root, not a usage error.
assert.equal(parseLaunchArgs(["--marker-root", "", "--skip-unless-marker", "m", "x.sh"]).script, "x.sh");

// A fake disk: the files that exist, by path, and the directories that exist.
function fakeFs(files = {}, dirs = []) {
  const all = new Map(Object.entries(files));
  return {
    isFile: (p) => all.has(p),
    isDir: (p) => dirs.includes(p),
    read: (p) => (all.has(p) ? Buffer.from(all.get(p)) : null),
    list: (dir) => [...all.keys()].filter((p) => p.startsWith(`${dir}/`)).map((p) => p.slice(dir.length + 1)),
  };
}
const laneGates = parseLaunchArgs([...LANE, "x.sh"]).gates;
assert.equal(needsStdin(laneGates), false);
const CACHE_SCRIPT = "/home/u/.claude/plugins/cache/m/autonomy/1.0.0/hooks/lane-stop-gate.sh";
const laneOpen = (env, files = {}, extra = {}) =>
  optionGateOpen(laneGates, env, { script: CACHE_SCRIPT, platform: "linux", fs: fakeFs(files), ...extra });

// The user settings file is the one lane-stop-gate.sh's pre-filter derives from
// its own path (lines 128-135): <config>/plugins/cache/<marketplace>/<name>/...
// gives <config>/settings.json, a backslashed drive root folds to `/`, and a
// --plugin-dir or directory-marketplace checkout has none.
assert.equal(userSettingsFile(CACHE_SCRIPT), "/home/u/.claude/settings.json");
assert.equal(userSettingsFile("C:\\cfg\\plugins\\cache\\m\\autonomy\\9.9.9/hooks/lane-stop-gate.sh"), "C:/cfg/settings.json");
assert.equal(userSettingsFile("/src/claude-code-plugins/plugins/autonomy/hooks/lane-stop-gate.sh"), null);
assert.equal(userSettingsFile("/c/plugins/cache/x.sh"), null, "no <marketplace>/<name> under plugins/cache");

// --- the any-of gate: idle skips; any one source runs --------------------------
assert.equal(laneOpen({}), false, "idle");
assert.equal(laneOpen({ CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID: "" }), false, "an empty value is unset, as -n reads it");
assert.equal(laneOpen({ CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID: "arm-0123456789" }), true, "ARM_ID only");
assert.equal(laneOpen({ CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED: "true" }), true, "ENABLED only");
assert.equal(laneOpen({ CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED: "false" }), true, "ENABLED set to anything");
const userMention = { "/home/u/.claude/settings.json": '{"pluginConfigs":{"autonomy@m":{"options":{"lane_stop_gate_enabled":true}}}}' };
assert.equal(laneOpen({}, userMention), true, "user settings mention");
assert.equal(laneOpen({}, { "/home/u/.claude/settings.json": '{"theme":"dark"}' }), false, "user settings without it");
assert.equal(
  laneOpen({}, userMention, { script: "/src/claude-code-plugins/plugins/autonomy/hooks/lane-stop-gate.sh" }),
  false,
  "a directory-marketplace load reads no user settings, as the script does not",
);
for (const managed of [
  "/etc/claude-code/managed-settings.json",
  "/etc/claude-code/managed-settings.d/10-lanes.json",
  "/Library/Application Support/ClaudeCode/managed-settings.json",
  "C:/Program Files/ClaudeCode/managed-settings.d/lanes.json",
]) {
  assert.equal(laneOpen({}, { [managed]: '{"lane_stop_gate_enabled":true}' }), true, managed);
}
// The script's drop-in glob is *.json, which skips dot files.
assert.equal(laneOpen({}, { "/etc/claude-code/managed-settings.d/.hidden.json": "lane_stop_gate" }), false);

// On Windows, Git Bash reads /etc/... under its own root, so the managed POSIX
// primaries are found there, beside the bash this launcher would start.
const gitBash = "C:\\Program Files\\Git\\bin\\bash.exe";
const winEnv = { ProgramFiles: "C:\\Program Files" };
assert.equal(
  settingsMention("lane_stop_gate", {
    env: winEnv,
    platform: "win32",
    fs: fakeFs({ [gitBash]: "", "C:\\Program Files\\Git/etc/claude-code/managed-settings.json": "lane_stop_gate" }),
  }),
  true,
);
// Gates still AND: a closed option gate beside the any-of gate skips.
const anded = parseLaunchArgs(["--require-true", "X", ...LANE, "x.sh"]).gates;
assert.equal(optionGateOpen(anded, { CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID: "arm-0123456789" }, { fs: fakeFs() }), false);

// --- --skip-unless-marker: run-python-hook.test.sh's marker cases ---------------
const MON = "guard-launch-monitor";
const markerGates = parseLaunchArgs(["--marker-root", "/data", "--skip-unless-marker", MON, "x.sh"]).gates;
assert.equal(needsStdin(markerGates), true);
const DIR = `/data/${MON}`;
const TMP_DIR = `/case-tmp/disk-hygiene-${MON}`;
const markerOpen = (payload, files = {}, dirs = [DIR], gates = markerGates) =>
  stdinGateOpen(gates, Buffer.from(payload), { env: { TMPDIR: "/case-tmp" }, platform: "linux", fs: fakeFs(files, dirs) });
const stop1 = '{"session_id":"sess-1","hook_event_name":"Stop"}';

assert.equal(payloadSessionId(Buffer.from(stop1)), "sess-1");
assert.equal(payloadSessionId(Buffer.from('{"hook_event_name":"Stop","session_id":"sess-2"}')), "sess-2");
assert.equal(markerOpen(stop1), false, "a marker tree with no marker for this session skips");
assert.equal(markerOpen(stop1, { [`${DIR}/sess-1.launched`]: "" }), true, "a recorded session runs");
assert.equal(markerOpen(stop1, { [`${TMP_DIR}/sess-1.launched`]: "" }), true, "a marker in the tmp fallback runs");
assert.equal(markerOpen(stop1, { [`${DIR}/sess-9.launched`]: "" }), false, "another session's marker does not count");
assert.equal(markerOpen(stop1, {}, []), true, "no candidate directory runs");
assert.equal(markerOpen('{"hook_event_name":"Stop","cwd":"/tmp"}'), true, "no session id runs");
assert.equal(markerOpen("not json at all"), true, "a payload that does not parse runs");
assert.equal(markerOpen(""), true, "an empty payload runs");
assert.equal(markerOpen('{"hook_event_name":"Stop","session_id":"sess-2"}'), false, "a reordered payload keys on its id");
assert.equal(markerOpen('{"hook_event_name":"Stop","session_id":"sess-2"}', { [`${DIR}/sess-2.launched`]: "" }), true);
assert.equal(markerOpen('{"session_id":"a/b"}', { [`${DIR}/a_b.launched`]: "" }), true, "unsafe bytes fold to _");
assert.equal(markerOpen('{"session_id":"s\u00e9ss"}'), true, "a non-ASCII id runs");
// biome-ignore lint/suspicious/noTemplateCurlyInString: the unsubstituted placeholder, verbatim
for (const root of ["", "${CLAUDE_PLUGIN_DATA}"]) {
  const gates = parseLaunchArgs(["--marker-root", root, "--skip-unless-marker", MON, "x.sh"]).gates;
  const label = `marker root ${JSON.stringify(root)}`;
  assert.equal(markerOpen(stop1, {}, [TMP_DIR], gates), false, `${label}: the script's tmp candidate alone skips`);
  assert.equal(markerOpen(stop1, { [`${TMP_DIR}/sess-1.launched`]: "" }, [TMP_DIR], gates), true, `${label}: its marker runs`);
  assert.equal(markerOpen(stop1, {}, [], gates), true, `${label}: no tmp directory runs`);
}
assert.equal(markerOpen(stop1, {}, [TMP_DIR]), false, "a missing marker-root directory beside the tmp candidate skips");
// On Windows TEMP and TMP join the tmp list though the script reads only
// ${TMPDIR:-/tmp}, so a tmp-side directory there is never evidence to skip.
const winTmpDir = `C:/t/disk-hygiene-${MON}`;
for (const env of [{ TMPDIR: "C:/t" }, { TEMP: "C:/t" }]) {
  assert.equal(
    stdinGateOpen(markerGates, Buffer.from(stop1), { env, platform: "win32", fs: fakeFs({}, [winTmpDir]) }),
    true,
    `win32 ${Object.keys(env)[0]}`,
  );
}

// A stall runs the marker row and still skips the stdin-contains row.
assert.equal(stdinStallOpen(markerGates), true);
assert.equal(stdinStallOpen(scan.gates), false);
assert.equal(stdinStallOpen([...markerGates, ...scan.gates]), false);

// --- live: the two Stop rows, with a no-op target that records that it ran -----
const ranScript = path.join(root, "ran.sh");
writeFileSync(ranScript, 'cat >"$1"\n');
const sentinel = path.join(root, "ran.txt");
const cleanEnv = Object.fromEntries(
  Object.entries(process.env).filter(([k]) => !k.startsWith("CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_")),
);
function liveRun(args, script, input, extraEnv = {}) {
  rmSync(sentinel, { force: true });
  const run = spawnSync(process.execPath, [launcher, ...args, script, sentinel], {
    env: { ...cleanEnv, ...extraEnv },
    input,
    encoding: "utf8",
  });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(run.stderr, "");
  return existsSync(sentinel) ? readFileSync(sentinel, "utf8") : null;
}

// The autonomy row: a synthetic plugins/cache install with its own config root.
const laneHooks = path.join(root, "cfg", "plugins", "cache", "m", "autonomy", "1.0.0", "hooks");
mkdirSync(laneHooks, { recursive: true });
const laneScript = path.join(laneHooks, "ran.sh").replaceAll("\\", "/");
writeFileSync(laneScript, 'cat >"$1"\n');
const lanePayload = '{"session_id":"live","hook_event_name":"Stop"}';
// A host whose managed settings already mention the gate runs every row; the
// idle case is only decidable where they do not.
if (!settingsMention("lane_stop_gate", { script: laneScript })) {
  assert.equal(liveRun(LANE, laneScript, lanePayload), null, "idle: no bash child");
}
assert.equal(liveRun(LANE, laneScript, lanePayload, { CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID: "arm-0123456789" }), lanePayload);
assert.equal(liveRun(LANE, laneScript, lanePayload, { CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED: "true" }), lanePayload);
writeFileSync(path.join(root, "cfg", "settings.json"), '{"pluginConfigs":{"autonomy@m":{"options":{"lane_stop_gate_enabled":true}}}}');
assert.equal(liveRun(LANE, laneScript, lanePayload), lanePayload, "user settings mention");

// The disk-hygiene row: a marker root with its directory and a private TMPDIR.
const markerRoot = path.join(root, "data");
const liveTmp = path.join(root, "tmp");
mkdirSync(path.join(markerRoot, MON), { recursive: true });
mkdirSync(liveTmp);
const session = `live-${process.pid}`;
const markerArgs = ["--marker-root", markerRoot, "--skip-unless-marker", MON];
const markerEnv = { TMPDIR: liveTmp, TEMP: liveTmp, TMP: liveTmp };
const stopPayload = `{"session_id":"${session}","hook_event_name":"Stop"}`;
assert.equal(liveRun(markerArgs, ranScript, stopPayload, markerEnv), null, "no marker: no bash child");
assert.equal(liveRun(markerArgs, ranScript, '{"hook_event_name":"Stop"}', markerEnv), '{"hook_event_name":"Stop"}');
writeFileSync(path.join(markerRoot, MON, `${session}.launched`), "");
assert.equal(liveRun(markerArgs, ranScript, stopPayload, markerEnv), stopPayload, "marker present");
rmSync(path.join(markerRoot, MON), { recursive: true });
assert.equal(liveRun(markerArgs, ranScript, stopPayload, markerEnv), stopPayload, "no marker directory");
mkdirSync(path.join(markerRoot, MON));

// A stall runs the monitor with the bytes that arrived, where the full payload
// would have skipped.
const partial = `{"session_id":"${session}"`;
const stalledRun = await new Promise((resolve) => {
  rmSync(sentinel, { force: true });
  const child = spawn(process.execPath, [launcher, ...markerArgs, ranScript, sentinel], {
    env: { ...cleanEnv, ...markerEnv, CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT: "0.3" },
  });
  child.stdin.on("error", () => {});
  child.stdin.write(partial);
  child.on("exit", (code) => {
    child.stdin.destroy();
    resolve(code);
  });
});
assert.equal(stalledRun, 0);
assert.equal(readFileSync(sentinel, "utf8"), partial, "a stall runs the script with what arrived");

console.log(
  "exec-bash gates: option list, stdin predicate, lane-stop any-of gate, launch marker, stall, and byte-for-byte delivery passed.",
);
