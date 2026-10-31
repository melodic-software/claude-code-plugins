// retry-call.bash's contract, on a stub call, a real rate guard and a clock
// the `sleep` stub moves: at most three runs, a recorded stop waited out, full
// jitter otherwise, nothing slept past the budget, and a call without --read
// never run twice.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { throttleFindings } from "../maintenance-monitor-signals/signals.mjs";

const root = fileURLToPath(new URL("../../../", import.meta.url));
const NOW = 2000000000;

// Runs `retry_call <args> call`, where `call` fails `failures` times with
// `failure` on stderr, then succeeds; `failures` -1 fails every time.
// `jumpAt` n moves the clock 10 s forward from the nth `date +%s` on.
const run = ({ args, failures, failure = "HTTP 502: Bad Gateway", stop, unreadableStop, jumpAt }) => {
  const dir = tempDir("retry-call-");
  try {
    const bin = join(dir, "bin");
    mkdirSync(bin);
    writeFileSync(join(dir, "clock"), String(NOW));
    const stub = (name, body) => {
      writeFileSync(join(bin, name), `#!/usr/bin/env bash\n${body}\n`);
      chmodSync(join(bin, name), 0o755);
    };
    stub(
      "date",
      `if [ "$1" != +%s ]; then exec /usr/bin/date "$@"; fi\n` +
        `n=$(($(cat "${dir}/dates" 2>/dev/null || echo 0) + 1))\necho "$n" >"${dir}/dates"\n` +
        (jumpAt ? `[ "$n" -lt ${jumpAt} ] || echo $(($(cat "${dir}/clock") + 10)) >"${dir}/clock"\n` : "") +
        `cat "${dir}/clock"`,
    );
    stub("sleep", `echo "$1" >>"${dir}/sleeps"\necho $(($(cat "${dir}/clock") + $1)) >"${dir}/clock"`);
    stub(
      "call",
      `n=$(($(cat "${dir}/calls" 2>/dev/null || echo 0) + 1))\necho "$n" >"${dir}/calls"\n` +
        `if [ ${failures} -lt 0 ] || [ "$n" -le ${failures} ]; then echo "${failure}" >&2; exit 1; fi\necho done`,
    );
    if (stop !== undefined) {
      mkdirSync(join(dir, "api-budget"));
      writeFileSync(join(dir, "api-budget/stop"), stop);
    }
    if (unreadableStop) mkdirSync(join(dir, "api-budget/stop"), { recursive: true });
    const script =
      `. ${join(root, ".github/actions/log-api-budget/api-budget.bash")}\n` +
      `. ${join(root, ".github/scripts/pr-merge/rate-stop.bash")}\n` +
      `. ${join(root, ".github/scripts/pr-merge/retry-call.bash")}\n` +
      `set -euo pipefail\nrc=0\nretry_call ${args} call || rc=$?\necho "rc=$rc"\necho "unknown=\${retry_call_unknown:-}"\n`;
    const result = spawnSync("bash", ["-c", script], {
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: dir },
    });
    const read = (name) => (existsSync(join(dir, name)) ? readFileSync(join(dir, name), "utf8") : "");
    return {
      status: result.status,
      stdout: result.stdout,
      stderr: result.stderr,
      calls: Number(read("calls") || 0),
      dates: Number(read("dates") || 0),
      sleeps: read("sleeps").split("\n").filter(Boolean).map(Number),
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

test("a read that fails twice then succeeds passes on its third try", () => {
  const out = run({ args: "--read 60", failures: 2 });
  assert.equal(out.status, 0, out.stderr);
  assert.match(out.stdout, /^done\nrc=0\n/m);
  assert.equal(out.calls, 3);
  assert.equal(out.sleeps.length, 2);
  assert.match(out.stderr, /HTTP 502/);
});

test("a read that succeeds at once sleeps nothing", () => {
  const out = run({ args: "--read 60", failures: 0 });
  assert.equal(out.calls, 1);
  assert.deepEqual(out.sleeps, []);
});

test("a read runs at most three times, with no wait after the last, then returns unknown", () => {
  const out = run({ args: "--read 60", failures: -1 });
  assert.equal(out.status, 0, out.stderr);
  assert.match(out.stdout, /^rc=2$/m);
  assert.match(out.stdout, /^unknown=failed 3 times$/m);
  assert.equal(out.calls, 3);
  assert.equal(out.sleeps.length, 2);
});

test("backoff is capped and jittered: each wait stays under its ceiling, and the waits differ", () => {
  const seen = new Set();
  for (let i = 0; i < 30; i += 1) {
    const { sleeps } = run({ args: "--read 60", failures: 2 });
    assert.ok(sleeps[0] >= 0 && sleeps[0] <= 15, String(sleeps));
    assert.ok(sleeps[1] >= 0 && sleeps[1] <= 30, String(sleeps));
    seen.add(sleeps.join());
  }
  assert.ok(seen.size > 1);
});

test("a recorded stop inside the budget is waited out to the second, not backed off", () => {
  const out = run({ args: "--read 60", failures: 1, stop: `core ${NOW + 40}\n` });
  assert.match(out.stdout, /^rc=0$/m);
  assert.deepEqual(out.sleeps, [40]);
  assert.equal(out.calls, 2);
});

test("a stop gh's message names, with no headers, is recorded and waited out when it fits", () => {
  const out = run({ args: "--read 60", failures: 1, failure: "You have exceeded a secondary rate limit" });
  assert.match(out.stdout, /^rc=0$/m);
  assert.deepEqual(out.sleeps, [60]);
});

test("a wait past the budget is not slept and returns unknown, naming the stop", () => {
  const out = run({ args: "--read 60", failures: -1, stop: `core ${NOW + 3600}\n` });
  assert.match(out.stdout, /^rc=2$/m);
  assert.match(out.stdout, /^unknown=rate limited \(the core pool until /m);
  assert.deepEqual(out.sleeps, []);
  assert.equal(out.calls, 1);
});

test("signal 3 reads retry_call's own rate-limit reason, and not its other reasons", () => {
  const reasonOf = (out) => /^unknown=(.+)$/m.exec(out.stdout)[1];
  const keys = (reason) =>
    throttleFindings({
      windowStart: new Date(NOW * 1000),
      heldSweeps: [{ runId: 1, url: "u", reason, createdAt: new Date(NOW * 1000).toISOString() }],
    }).map((f) => f.key);
  assert.deepEqual(keys(reasonOf(run({ args: "--read 60", failures: -1, stop: `core ${NOW + 3600}\n` }))), ["throttle:rate-limited"]);
  assert.deepEqual(keys(reasonOf(run({ args: "--read 60", failures: -1 }))), []);
});

// The stop is read as live, then the clock passes it before the wait is
// worked out: date call 5 is retry_call's own, after rate_stop_label's three
// reads (any, *, core) and retry_call's api_budget_stop_until.
test("a stop that passes between the two clock reads is waited out as zero, then retried", () => {
  const out = run({ args: "--read 60", failures: 1, stop: `core ${NOW + 5}\n`, jumpAt: 5 });
  assert.match(out.stdout, /^rc=0$/m);
  assert.equal(out.dates, 5);
  assert.deepEqual(out.sleeps, [0]);
  assert.equal(out.calls, 2);
});

test("the budget counts every wait together, not each alone", () => {
  // 20 s of the 30 s go on the stop, so a backoff over 10 s does not fit.
  for (let i = 0; i < 10; i += 1) {
    const { stdout, sleeps } = run({ args: "--read 30", failures: -1, stop: `core ${NOW + 20}\n` });
    assert.match(stdout, /^rc=2$/m);
    assert.equal(sleeps[0], 20);
    assert.ok(sleeps.reduce((sum, s) => sum + s, 0) <= 30, String(sleeps));
  }
});

test("a stop file that cannot be read counts as past any budget", () => {
  const out = run({ args: "--read 60", failures: -1, unreadableStop: true });
  assert.match(out.stdout, /^rc=2$/m);
  assert.deepEqual(out.sleeps, []);
  assert.equal(out.calls, 1);
});

test("a call without --read that fails runs once, sleeps nothing and returns unknown", () => {
  const out = run({ args: "60", failures: -1 });
  assert.equal(out.status, 0, out.stderr);
  assert.match(out.stdout, /^rc=2$/m);
  assert.match(out.stdout, /^unknown=failed once$/m);
  assert.equal(out.calls, 1);
  assert.deepEqual(out.sleeps, []);
});

test("a call without --read that succeeds passes through once", () => {
  const out = run({ args: "60", failures: 0 });
  assert.match(out.stdout, /^done\nrc=0\n/m);
  assert.equal(out.calls, 1);
});
