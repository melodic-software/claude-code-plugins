// capture-probe.mjs, pr-verify-capture.yml's reach probe: it must name every
// credential a process in the app's position can read, never print a value,
// and never pass when its own scan cannot be shown to work (the canary).
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { CREDENTIAL_NAMES, credentialFiles, envHits, fileReach, probedNames, scanFiles, scanProc, verdict } from "./capture-probe.mjs";

const SCRIPT = fileURLToPath(new URL("./capture-probe.mjs", import.meta.url));
// Built at run time so no key-shaped literal sits in the file.
const KEY = `${"sk-ant-"}api03-${"Q".repeat(40)}`;

// A /proc stand-in: one directory per pid, each with its environ.
const fakeProc = (processes) => {
  const root = tempDir("capture-probe-proc-");
  for (const [pid, entries] of Object.entries(processes)) {
    mkdirSync(path.join(root, pid));
    if (entries !== null) writeFileSync(path.join(root, pid, "environ"), `${entries.join("\0")}\0`);
  }
  mkdirSync(path.join(root, "self"));
  return root;
};

test("every pr-verify credential name, the job token and the runtime tokens are probed", () => {
  for (const name of ["PR_VERIFY_CLAUDE_API_KEY", "PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN", "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN", "LANE_API_KEY", "GITHUB_TOKEN", "ACTIONS_RUNTIME_TOKEN", "ACTIONS_ID_TOKEN_REQUEST_TOKEN"]) {
    assert.ok(CREDENTIAL_NAMES.includes(name), name);
  }
});

test("an environment hit names the variable, and a key under any name is a hit", () => {
  assert.deepEqual(envHits(["PATH=/usr/bin", "ANTHROPIC_API_KEY=x", "HOME=/home/runner"]), ["ANTHROPIC_API_KEY"]);
  assert.deepEqual(envHits(["ACTIONS_RUNTIME_TOKEN=eyJ0"]), ["ACTIONS_RUNTIME_TOKEN"]);
  assert.deepEqual(envHits([`HIDDEN=${KEY}`]), ["a credential-shaped value in HIDDEN"]);
  assert.deepEqual(envHits([`GH=${"ghs_"}${"a".repeat(36)}`]), ["a credential-shaped value in GH"]);
  // Set but empty carries nothing; a name that only looks like one is no hit.
  assert.deepEqual(envHits(["ANTHROPIC_API_KEY=", "GITHUB_TOKEN_NAME=github-token", "PATH=/bin"]), []);
});

test("a name the job adds is a hit by name in the environment and in /proc, and pr-verify's list stays as it was", () => {
  const names = probedNames("ISSUE_LANE_CLAUDE_API_KEY  OTHER_SECRET\n");
  assert.deepEqual(names.slice(-2), ["ISSUE_LANE_CLAUDE_API_KEY", "OTHER_SECRET"]);
  // A value of no credential shape, so only the name can hit.
  const entries = ["ISSUE_LANE_CLAUDE_API_KEY=plain", "PATH=/bin"];
  assert.deepEqual(envHits(entries, names), ["ISSUE_LANE_CLAUDE_API_KEY"]);
  assert.deepEqual(envHits(entries), []);
  const root = fakeProc({ 10: entries });
  assert.deepEqual(scanProc(root, "c", names).hits, [{ where: "process 10", name: "ISSUE_LANE_CLAUDE_API_KEY" }]);
  assert.deepEqual(scanProc(root, "c").hits, []);
  assert.deepEqual(probedNames(), [...CREDENTIAL_NAMES]);
  assert.deepEqual(probedNames(""), [...CREDENTIAL_NAMES]);
});

test("the process scan reads every environ it can, names each hit's process, and sees the canary", () => {
  const root = fakeProc({ 10: ["PATH=/bin", "PR_VERIFY_PROBE_CANARY=c0ffee"], 11: [`LANE_API_KEY=${KEY}`], 12: ["HOME=/root"], 13: null });
  const scan = scanProc(root, "c0ffee");
  assert.equal(scan.read, 3);
  assert.equal(scan.canarySeen, true);
  assert.deepEqual(scan.hits, [
    { where: "process 11", name: "LANE_API_KEY" },
    { where: "process 11", name: "a credential-shaped value in LANE_API_KEY" },
  ]);
  assert.equal(scanProc(root, "another").canarySeen, false);
  assert.deepEqual(scanProc(path.join(root, "missing"), "c0ffee"), { hits: [], read: 0, canarySeen: false });
});

test("a git config with an auth header or a stored token is a hit, and a plain one is not", () => {
  const dir = tempDir("capture-probe-files-");
  const header = path.join(dir, "header");
  const plain = path.join(dir, "plain");
  writeFileSync(header, '[http "https://github.com/"]\n\textraheader = AUTHORIZATION: basic eA==\n');
  writeFileSync(plain, '[remote "origin"]\n\turl = https://github.com/o/r\n');
  assert.deepEqual(scanFiles([header, plain, path.join(dir, "absent")]), [{ where: header, name: "a stored credential" }]);
});

// The subscription job's leg holds an OAuth token: run-claude-cli sets it as
// CLAUDE_CODE_OAUTH_TOKEN (lane.cjs legEnv), and on Linux Claude Code keeps a
// login in ~/.claude/.credentials.json (code.claude.com/docs/en/authentication,
// Credential management), so the probe looks in both.
test("a subscription token is a hit in the environment and in Claude Code's credential file", () => {
  const token = `${"sk-ant-"}oat01-${"Z".repeat(40)}`;
  assert.deepEqual(envHits([`CLAUDE_CODE_OAUTH_TOKEN=${token}`]), ["CLAUDE_CODE_OAUTH_TOKEN", "a credential-shaped value in CLAUDE_CODE_OAUTH_TOKEN"]);
  const home = tempDir("capture-probe-home-");
  const cwd = tempDir("capture-probe-cwd-");
  assert.deepEqual(credentialFiles(cwd, home), []);
  const store = path.join(home, ".claude/.credentials.json");
  mkdirSync(path.dirname(store));
  writeFileSync(store, JSON.stringify({ claudeAiOauth: { accessToken: token } }));
  assert.deepEqual(credentialFiles(cwd, home), [store]);
  assert.deepEqual(scanFiles(credentialFiles(cwd, home)), [{ where: store, name: "a stored credential" }]);
});

test("the verdict passes only a clean scan that saw its canary", () => {
  const procScan = (hits, canarySeen) => ({ hits, read: 3, canarySeen });
  assert.equal(verdict({ ownHits: [], procScan: procScan([], true), fileHits: [] }).exit, 0);
  assert.equal(verdict({ ownHits: [], procScan: procScan([], true), fileHits: [] }).clean, true);
  // A scan that missed its own canary proves nothing, whatever else it found.
  for (const hits of [[], [{ where: "process 1", name: "GITHUB_TOKEN" }]]) {
    const result = verdict({ ownHits: [], procScan: procScan(hits, false), fileHits: [] });
    assert.equal(result.exit, 2);
    assert.equal(result.clean, false);
  }
  const own = verdict({ ownHits: ["ANTHROPIC_API_KEY"], procScan: procScan([], true), fileHits: [] });
  assert.equal(own.exit, 1);
  assert.deepEqual(own.hits, [{ where: "own environment", name: "ANTHROPIC_API_KEY" }]);
  assert.equal(verdict({ ownHits: [], procScan: procScan([], true), fileHits: [{ where: "f", name: "a stored credential" }] }).exit, 1);
});

// The probe leg's stream-json messages, in the Agent SDK's shapes: a Read
// tool_use in an assistant message, its tool_result in a user message, and
// the result message's permission_denials (SDKResultMessage).
const readUse = (id, file) => ({ type: "assistant", message: { content: [{ type: "tool_use", id, name: "Read", input: { file_path: file } }] } });
const readResult = (id, isError) => ({ type: "user", message: { content: [{ type: "tool_result", tool_use_id: id, ...(isError ? { is_error: true } : {}), content: "x" }] } });
const resultMessage = (denials = []) => ({ type: "result", permission_denials: denials.map((id) => ({ tool_name: "Read", tool_use_id: id, tool_input: {} })) });
const TARGETS = ["/proc/self/environ", "/runner/_temp/probe.md"];

test("the driver's file tools pass only when a Read of every fenced path was refused", () => {
  const refused = [readUse("a", TARGETS[0]), readResult("a", true), readUse("b", TARGETS[1]), readResult("b", true), resultMessage(["a", "b"])];
  assert.deepEqual(fileReach(refused, TARGETS), { clean: true, reach: TARGETS.map((target) => ({ target, status: "refused" })) });
  // Listed as a denial alone counts as refused.
  assert.equal(fileReach([readUse("a", TARGETS[0]), readUse("b", TARGETS[1]), resultMessage(["a", "b"])], TARGETS).clean, true);
  // A read that came back, one with no result, and one never tried all fail it.
  const read = fileReach([readUse("a", TARGETS[0]), readResult("a", false), readUse("b", TARGETS[1]), readResult("b", true)], TARGETS);
  assert.deepEqual(read, { clean: false, reach: [{ target: TARGETS[0], status: "read" }, { target: TARGETS[1], status: "refused" }] });
  assert.equal(fileReach([readUse("a", TARGETS[0]), readUse("b", TARGETS[1]), readResult("b", true)], TARGETS).reach[0].status, "unknown");
  assert.equal(fileReach([readUse("b", TARGETS[1]), readResult("b", true)], TARGETS).reach[0].status, "not tried");
  // A second, successful try after a refusal is a read.
  assert.equal(fileReach([readUse("a", TARGETS[0]), readResult("a", true), readUse("c", TARGETS[0]), readResult("c", false), readUse("b", TARGETS[1]), readResult("b", true)], TARGETS).clean, false);
  assert.equal(fileReach(null, TARGETS).clean, false);
  assert.equal(fileReach(refused, []).clean, false);
  // The ~/.claude fence file is a third target: refused with the others it
  // passes; read, or never tried, it fails the probe.
  const fence = "/home/runner/.claude/pr-verify-probe-fence";
  const three = [...TARGETS, fence];
  assert.equal(fileReach([...refused.slice(0, 4), readUse("f", fence), readResult("f", true), resultMessage(["a", "b", "f"])], three).clean, true);
  assert.deepEqual(fileReach([...refused, readUse("f", fence), readResult("f", false)], three).reach[2], { target: fence, status: "read" });
  assert.deepEqual(fileReach(refused, three), { clean: false, reach: [...TARGETS.map((target) => ({ target, status: "refused" })), { target: fence, status: "not tried" }] });
});

test("the reads subcommand exits 0 only on a refused read of every path, and prints no content", () => {
  const dir = tempDir("capture-probe-reads-");
  const file = path.join(dir, "execution.json");
  const run = (messages) => {
    if (messages !== undefined) writeFileSync(file, JSON.stringify(messages));
    return spawnSync(process.execPath, [SCRIPT, "reads", file, ...TARGETS], { encoding: "utf8" });
  };
  assert.equal(run([readUse("a", TARGETS[0]), readResult("a", true), readUse("b", TARGETS[1]), readResult("b", true)]).status, 0);
  const leaked = run([readUse("a", TARGETS[0]), { type: "user", message: { content: [{ type: "tool_result", tool_use_id: "a", content: KEY }] } }, readUse("b", TARGETS[1]), readResult("b", true)]);
  assert.equal(leaked.status, 1);
  assert.match(leaked.stdout, /\/proc\/self\/environ read/);
  assert.ok(!leaked.stdout.includes(KEY));
  writeFileSync(file, "{not json");
  assert.equal(run().status, 1);
});

test("the reads subcommand exits 3, not 1, when the session never tried a path, and 1 whenever any Read came back", () => {
  const dir = tempDir("capture-probe-untried-");
  const file = path.join(dir, "execution.json");
  const run = (messages) => {
    writeFileSync(file, JSON.stringify(messages));
    return spawnSync(process.execPath, [SCRIPT, "reads", file, ...TARGETS], { encoding: "utf8" });
  };
  const bash = { type: "assistant", message: { content: [{ type: "tool_use", id: "z", name: "Bash", input: { command: "true" } }] } };
  for (const [messages, why] of [
    [[], "no message at all"],
    [[bash, resultMessage()], "a Bash call and no Read"],
  ]) {
    const none = run(messages);
    assert.equal(none.status, 3, `${why}: ${none.stdout}`);
    assert.match(none.stdout, /\/proc\/self\/environ not tried, \/runner\/_temp\/probe\.md not tried/, why);
    assert.match(none.stdout, /the fence was not tested/, why);
  }
  const partial = run([readUse("a", TARGETS[0]), readResult("a", true)]);
  assert.equal(partial.status, 3, partial.stdout);
  assert.match(partial.stdout, /\/runner\/_temp\/probe\.md not tried/);
  // A Read that came back, or one with no result, is a breach whatever else went untried.
  const read = run([readUse("b", TARGETS[1]), readResult("b", false)]);
  assert.equal(read.status, 1, read.stdout);
  assert.doesNotMatch(read.stdout, /not tested/);
  assert.equal(run([readUse("b", TARGETS[1])]).status, 1);
});

test("run where a key is in reach, the probe fails, names it and writes no value", { skip: !existsSync("/proc/self/environ") && "needs /proc" }, () => {
  const dir = tempDir("capture-probe-run-");
  const result = path.join(dir, "result.json");
  const run = spawnSync(process.execPath, [SCRIPT, result], { cwd: dir, env: { PATH: process.env.PATH, HOME: dir, ANTHROPIC_API_KEY: KEY }, encoding: "utf8" });
  assert.equal(run.status, 1, run.stdout + run.stderr);
  const written = readFileSync(result, "utf8");
  const parsed = JSON.parse(written);
  assert.equal(parsed.clean, false);
  assert.equal(parsed.canary, true);
  assert.ok(parsed.hits.some((hit) => hit.where === "own environment" && hit.name === "ANTHROPIC_API_KEY"), written);
  assert.ok(!written.includes(KEY) && !run.stdout.includes(KEY));
});

test("run with an added name, the probe hits on that variable and lists the name it probed", { skip: !existsSync("/proc/self/environ") && "needs /proc" }, () => {
  const dir = tempDir("capture-probe-extra-");
  const result = path.join(dir, "result.json");
  const run = spawnSync(process.execPath, [SCRIPT, result], { cwd: dir, env: { PATH: process.env.PATH, HOME: dir, CAPTURE_PROBE_EXTRA_NAMES: "ISSUE_LANE_CLAUDE_API_KEY", ISSUE_LANE_CLAUDE_API_KEY: "plain" }, encoding: "utf8" });
  assert.equal(run.status, 1, run.stdout + run.stderr);
  const parsed = JSON.parse(readFileSync(result, "utf8"));
  assert.ok(parsed.names.includes("ISSUE_LANE_CLAUDE_API_KEY"));
  assert.ok(parsed.hits.some((hit) => hit.where === "own environment" && hit.name === "ISSUE_LANE_CLAUDE_API_KEY"));
});
