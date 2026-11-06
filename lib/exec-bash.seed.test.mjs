// exec-bash.mjs --bps-seed (Windows only): the shfmt parse the launcher hands a script in
// HOOK_BPS_SEED_KEY/VAL. The list must be the one hook-utils.sh computes, an
// inherited pair must never reach the script, and every failure passes no pair.
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { BPS_SEED_ENV, bpsSeed, bpsSeedPlatform, parseLaunchArgs } from "./exec-bash.mjs";
import { tempDir } from "./test-tmp.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const lib = path.join(here, "hook-utils.sh");
const launcher = path.join(here, "exec-bash.mjs");
const payload = (command, tool = "Bash") => Buffer.from(JSON.stringify({ tool_name: tool, tool_input: { command } }));

// --- parsing ----------------------------------------------------------------
assert.match(parseLaunchArgs(["--bps-seed", ""]).error, /^usage: --bps-seed /);
assert.deepEqual(parseLaunchArgs(["--bps-seed", lib, "x.sh"]).gates, [{ flag: "--bps-seed", value: lib }]);

// --- bpsSeed with a stand-in for spawnSync -----------------------------------
const ok = (stdout) => ({ status: 0, stdout: Buffer.from(stdout) });
const fake = (...results) => {
  const calls = [];
  const run = (cmd, args, opts) => {
    calls.push({ cmd, args, input: String(opts.input) });
    return results.shift();
  };
  return { run, calls };
};
{
  const { run, calls } = fake(ok("{}"), ok("'G' '1'\r\n"));
  assert.deepEqual(bpsSeed(payload("ls"), lib, run), { key: "ls", value: "'G' '1'" });
  assert.equal(calls[0].cmd, "shfmt");
  assert.deepEqual(calls[0].args, ["-ln", "bash", "--to-json"]);
  assert.equal(calls[0].input, "ls");
  assert.equal(calls[1].cmd, "jq");
  assert.equal(calls[1].input, "{}");
}
const never = () => assert.fail("spawned for a payload it should not seed");
assert.equal(bpsSeed(payload("ls", "Write"), lib, never), null, "another tool");
assert.equal(bpsSeed(payload("echo héllo"), lib, never), null, "non-ASCII");
assert.equal(bpsSeed(payload("echo \0"), lib, never), null, "NUL");
assert.equal(bpsSeed(payload("x".repeat(8193)), lib, never), null, "over the command cap");
assert.equal(bpsSeed(Buffer.from("{not json"), lib, never), null, "malformed payload");
assert.equal(bpsSeed(payload("ls"), path.join(here, "no-such-lib.sh"), never), null, "missing library");
assert.equal(bpsSeed(payload("ls"), lib, fake({ error: new Error("ENOENT") }).run), null, "no shfmt");
assert.equal(bpsSeed(payload("ls"), lib, fake({ status: 1, stdout: Buffer.from("") }).run), null, "shfmt refuses");
assert.equal(bpsSeed(payload("ls"), lib, fake({ status: null, signal: "SIGTERM", error: new Error("ETIMEDOUT") }).run), null, "timeout");
assert.equal(bpsSeed(payload("ls"), lib, fake(ok("{}"), { status: 5, stdout: Buffer.from("") }).run), null, "jq fails");
assert.equal(bpsSeed(payload("ls"), lib, fake(ok("{}"), ok("x".repeat(24577))).run), null, "over the list cap");

// --- live: the same list hook::_bps_shfmt_to computes ------------------------
const has = (tool) => spawnSync(tool, ["--version"]).status === 0;
const bash = spawnSync("bash", ["-c", "true"]).status === 0;
if (has("shfmt") && has("jq") && bash) {
  const program = spawnSync("bash", ["-c", 'source "$1"; printf %s "$HOOK_BPS_JQ"', "--", lib]).stdout.toString();
  const seen = [];
  const recording = (cmd, args, opts) => {
    if (cmd === "jq") seen.push(args[1]);
    return spawnSync(cmd, args, opts);
  };
  for (const command of ["git status", "git log -1 && git diff | head -5", "cat <<'EOF' >f\nx $y\nEOF", "echo a\\", "bash -c 'git reset --hard'"]) {
    const want = spawnSync("bash", ["-c", 'source "$1"; hook::_bps_shfmt_to l "$2" && printf %s "$l"', "--", lib, command]).stdout.toString();
    assert.ok(want.length > 0, `bash parsed ${JSON.stringify(command)}`);
    assert.deepEqual(bpsSeed(payload(command), lib, recording), { key: command, value: want }, command);
  }
  assert.equal(seen[0], program, "the jq program read from the library is HOOK_BPS_JQ byte for byte");
  assert.equal(bpsSeed(payload("echo ("), lib), null, "a syntax error seeds nothing");

  // The script sees the launcher's pair and never an inherited one.
  const dir = tempDir("exec-bash-seed-");
  const script = path.join(dir, "show.sh");
  writeFileSync(script, 'printf "%s|%s" "${HOOK_BPS_SEED_KEY-unset}" "${#HOOK_BPS_SEED_VAL}"\n');
  const launch = (args, input) =>
    new Promise((resolve) => {
      const child = spawn(process.execPath, [launcher, ...args], {
        env: { ...process.env, [BPS_SEED_ENV[0]]: "forged", [BPS_SEED_ENV[1]]: "forged list" },
      });
      let out = "";
      child.stdout.on("data", (d) => {
        out += d;
      });
      child.on("exit", (code) => resolve({ code, out }));
      child.stdin.end(input);
    });
  const seeded = await launch(["--bps-seed", lib, script], payload("git status"));
  assert.equal(seeded.code, 0);
  if (bpsSeedPlatform(process.platform)) assert.match(seeded.out, /^git status\|[1-9][0-9]*$/, "the launcher's own pair");
  else assert.equal(seeded.out, "unset|0", "off Windows the flag is inert: no pair, the inherited one dropped");
  assert.equal((await launch(["--bps-seed", lib, script], payload("ls", "Write"))).out, "unset|0", "inherited pair dropped, none set");
  assert.equal((await launch([script], payload("ls"))).out, "unset|0", "a row without the flag drops an inherited pair too");
} else {
  console.log("skip: live --bps-seed cases need bash, shfmt and jq on PATH");
}
console.log("ok: exec-bash --bps-seed");
