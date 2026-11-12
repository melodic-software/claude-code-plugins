// Runs the action's "Install subprocess isolation" script against stand-ins for
// sudo and apt-get, on a PATH that holds no real bwrap or socat, so each case
// controls how the mirror answers.
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, readdirSync, readFileSync, symlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { tempDir } from "../../../lib/test-tmp.mjs";

const ACTION = new URL("./action.yml", import.meta.url);
const FAIL_CLOSED = "::error::bubblewrap or socat is not installed; Claude Code cannot scrub its subprocess environment";

function installScript() {
  const lines = readFileSync(ACTION, "utf8").split("\n");
  const name = lines.findIndex((line) => line.trim() === "- name: Install subprocess isolation");
  assert.notEqual(name, -1, "action.yml has the install step");
  const start = lines.findIndex((line, i) => i > name && /^\s+run: \|$/.test(line));
  const keyIndent = lines[start].search(/\S/);
  const body = [];
  for (const line of lines.slice(start + 1)) {
    if (line.trim() !== "" && line.search(/\S/) <= keyIndent) break;
    body.push(line);
  }
  const indent = Math.min(...body.filter((l) => l.trim()).map((l) => l.search(/\S/)));
  return body.map((l) => l.slice(indent)).join("\n");
}

const TOOLS = ["bash", "timeout", "touch", "chmod"];

const sh = (body) => `#!/bin/bash\n${body}\n`;

// apt-get stand-in. FAKE_APT: `down` fails every call; `lists` installs without
// an index refresh; `stale` installs only after `update`. Installing writes bwrap
// and socat into the PATH directory.
const APT_GET = sh(`
echo "apt-get $*" >>"$FAKE_LOG"
args=" $* "
if [ "$FAKE_APT" = down ]; then
  exit 100
elif [[ $args == *" update "* ]]; then
  touch "$FAKE_STATE/updated"; exit 0
elif [ "$FAKE_APT" = stale ] && [ ! -e "$FAKE_STATE/updated" ]; then
  exit 100
fi
for tool in bwrap socat; do printf '#!/bin/bash\\n' >"$FAKE_BIN/$tool"; chmod +x "$FAKE_BIN/$tool"; done
`);

// dpkg stand-in: `stall` blocks 30 s until timeout kills it.
const DPKG = sh('[ "$FAKE_DPKG" = stall ] && exec "$REAL_SLEEP" 30\nexit 0');

function run({ apt, dpkg = "ok", budget, preinstalled = [] }) {
  const root = tempDir("runner-isolation-");
  const bin = path.join(root, "bin");
  const state = path.join(root, "state");
  for (const dir of [bin, state]) mkdirSync(dir, { recursive: true });
  for (const tool of TOOLS) symlinkSync(execFileSync("bash", ["-c", `command -v ${tool}`], { encoding: "utf8" }).trim(), path.join(bin, tool));
  const stubs = { sudo: sh('exec "$@"'), sleep: sh('echo "$*" >>"$FAKE_SLEEPS"'), sysctl: sh(":"), dpkg: DPKG, "apt-get": APT_GET };
  for (const tool of preinstalled) stubs[tool] = sh(":");
  for (const [name, body] of Object.entries(stubs)) {
    writeFileSync(path.join(bin, name), body);
    chmodSync(path.join(bin, name), 0o755);
  }
  const log = path.join(root, "log");
  writeFileSync(log, "");
  const sleeps = path.join(root, "sleeps");
  writeFileSync(sleeps, "");
  const env = {
    PATH: bin, FAKE_LOG: log, FAKE_BIN: bin, FAKE_STATE: state, FAKE_APT: apt, FAKE_DPKG: dpkg, FAKE_SLEEPS: sleeps,
    REAL_SLEEP: execFileSync("bash", ["-c", "command -v sleep"], { encoding: "utf8" }).trim(),
  };
  if (budget !== undefined) env.BUDGET_SECONDS = String(budget);
  const began = Date.now();
  const result = spawnSync(path.join(bin, "bash"), ["-e", "-o", "pipefail", "-c", installScript()], { encoding: "utf8", env });
  return {
    status: result.status,
    stdout: result.stdout,
    elapsed: (Date.now() - began) / 1000,
    sleeps: readFileSync(sleeps, "utf8").trim().split("\n").filter(Boolean),
    calls: readFileSync(log, "utf8").trim().split("\n").filter(Boolean),
    installed: existsSync(path.join(bin, "bwrap")) && existsSync(path.join(bin, "socat")),
  };
}

const updates = (calls) => calls.filter((c) => / update /.test(` ${c} `)).length;

test("fresh image lists install without an index refresh", () => {
  const r = run({ apt: "lists" });
  assert.equal(r.status, 0, r.stdout);
  assert.equal(r.installed, true);
  assert.equal(r.calls.length, 1, `one apt-get call, got: ${r.calls}`);
  assert.equal(updates(r.calls), 0);
});

test("stale image lists fall back to update and install", () => {
  const r = run({ apt: "stale" });
  assert.equal(r.status, 0, r.stdout);
  assert.equal(r.installed, true);
  assert.equal(r.calls.length, 3, `install, update, install, got: ${r.calls}`);
  assert.match(r.calls[1], /update/);
});

test("no install override shadows the image's mirror failover settings", () => {
  const r = run({ apt: "stale" });
  assert.ok(!r.calls.some((c) => /Acquire::/.test(c)), `got: ${r.calls}`);
});

test("both tools already present make no apt call", () => {
  const r = run({ apt: "down", preinstalled: ["bwrap", "socat"] });
  assert.equal(r.status, 0, r.stdout);
  assert.deepEqual(r.calls, []);
});

test("a mirror that never answers fails closed after three refresh attempts", () => {
  const r = run({ apt: "down" });
  assert.equal(r.status, 1);
  assert.equal(r.installed, false);
  assert.equal(updates(r.calls), 3, `three update attempts, got: ${r.calls}`);
  assert.ok(r.stdout.includes(FAIL_CLOSED), r.stdout);
});

test("a dpkg repair that stalls is cut off at the time left in the budget", () => {
  const r = run({ apt: "down", dpkg: "stall", budget: 4 });
  assert.equal(r.status, 1);
  assert.ok(r.elapsed < 10, `4 s budget plus 2 s kill grace, took ${r.elapsed} s`);
});

test("a backoff sleep longer than the time left is skipped", () => {
  const r = run({ apt: "down", budget: 15 });
  assert.equal(r.status, 1);
  assert.deepEqual(r.sleeps, ["10"], "the 10 s backoff fits; the 20 s one does not");
});

test("bubblewrap present but socat missing fails closed", () => {
  const r = run({ apt: "down", preinstalled: ["bwrap"] });
  assert.equal(r.status, 1);
  assert.ok(r.stdout.includes(FAIL_CLOSED), r.stdout);
});

const INLINE_APT = /apt-get[^\n]*install[^\n]*\b(bubblewrap|socat)\b/;

test("the inline-apt pattern matches a known inline install line", () => {
  assert.match('timeout 180 sudo apt-get "${apt[@]}" install -y --no-install-recommends bubblewrap socat && break', INLINE_APT);
  assert.match("sudo apt-get install -y socat", INLINE_APT);
});

test("no workflow or other action installs bubblewrap or socat with its own apt block", () => {
  const github = fileURLToPath(new URL("../../", import.meta.url));
  const files = [
    ...readdirSync(path.join(github, "workflows")).filter((f) => f.endsWith(".yml")).map((f) => path.join(github, "workflows", f)),
    ...readdirSync(path.join(github, "actions"))
      .filter((d) => d !== "setup-runner-isolation" && existsSync(path.join(github, "actions", d, "action.yml")))
      .map((d) => path.join(github, "actions", d, "action.yml")),
  ];
  const inline = files.filter((f) => INLINE_APT.test(readFileSync(f, "utf8")));
  assert.deepEqual(inline.map((f) => path.relative(github, f)), []);
});
