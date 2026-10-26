// pr-merge.yml's main-verification trigger. Expected values come from the
// owner decision of 2026-10-18 (every merge to main starts the full run,
// whoever merged), GitHub's concurrency rules (a group holds one running and
// one pending job, and a newer pending job replaces the older one unless
// `queue: max` is set), and the rule babysit_postmerge.py and
// post-merge-demotion-alert.yml share: a cancelled full run counts as red, so
// no pr-require-checks run may be cancelled by concurrency.
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { LANE_ROOM_TIMEOUT_MS, VERIFY_BUDGET_MS, VERIFY_TIMEOUT_MS } from "./enable-auto-merge.mjs";
import { classify, resetLabel } from "../../actions/log-api-budget/rate-guard.mjs";

const read = (name) => readFileSync(new URL(`../../workflows/${name}`, import.meta.url), "utf8");
const merge = read("pr-merge.yml");
const jobs = merge.slice(merge.indexOf("\njobs:\n"));
const job = (id) => {
  const match = new RegExp(`\\n  ${id}:\\n([\\s\\S]*?)(?=\\n  [a-z-]+:\\n|$)`).exec(jobs);
  assert.ok(match, `job ${id}`);
  return match[1];
};

test("every push to main reaches the dispatch job, with no author filter", () => {
  assert.match(merge, /\n {2}push:\n {4}branches: \[main\]\n/);
  const dispatch = job("dispatch-full-run");
  const condition = /\n {4}if: >-\n([\s\S]*?)\n {4}[a-z-]+:/.exec(dispatch)[1];
  assert.match(condition, /\(github\.event_name == 'push' && github\.ref == 'refs\/heads\/main'\)/);
  assert.doesNotMatch(dispatch, /head_commit|AUTOMATION_LANES_APP_SENDER_ID|needs\.lane-merge-landed/);
  assert.doesNotMatch(jobs, /\n {2}lane-merge-landed:\n/);
});

test("push dispatches share one group that queues one and cancels nothing", () => {
  const dispatch = job("dispatch-full-run");
  const block = /\n {4}concurrency:\n {6}group: (.*)\n {6}cancel-in-progress: (.*)\n/.exec(dispatch);
  assert.ok(block, "a job-level concurrency block");
  assert.match(block[1], /github\.event_name == 'push' && '[a-z-]+'/);
  assert.match(block[1], /github\.run_id/);
  assert.equal(block[2], "false");
  assert.doesNotMatch(dispatch, /\n {6}queue:/);
});

test("a push job holds the group until the dispatched run finishes", () => {
  const dispatch = job("dispatch-full-run");
  const record = dispatch.indexOf("- name: Record the dispatched run");
  const wait = dispatch.indexOf("- name: Wait for the full run to finish");
  assert.ok(record >= 0 && wait > record);
  const step = dispatch.slice(wait);
  assert.match(step, /\n {8}if: github\.event_name == 'push' && steps\.dispatch\.outputs\.run-id != ''\n/);
  assert.doesNotMatch(step, /gh run watch|--exit-status/);
});

// The wait step's body, run under bash against a stub gh (one canned run
// read, then any write logged) and a stub sleep. The alert workflow hears of
// a failed run only through this dispatch: GITHUB_TOKEN started the run, so
// it raises no workflow_run event.
const HEAD = "0123456789abcdef0123456789abcdef01234567";
const SEND = `api -X POST repos/o/r/actions/workflows/post-merge-demotion-alert.yml/dispatches -f ref=main -f inputs[run-id]=4242 -f inputs[head-sha]=${HEAD}`;
// With notModified N, the first read finds the run in progress with ETag
// "e1", the next N reads (sent with If-None-Match on it) are answered 304
// with gh's exit 1, and the one after finds it completed. With limited, every
// read is refused with limitedMessage. Each entry of sendErrors fails one send
// in turn with that stderr; the send after them succeeds, unless
// dispatchFails.
// gh's stderr for a POST GitHub refused for a rate limit, as run 39906176584
// logged it (pr-merge.yml, dispatch-full-run, "Start the full CI run on main",
// 2026-10-23T05:30:57Z).
const RATE_LIMITED_STDERR =
  "gh: API rate limit exceeded for installation. If you reach out to GitHub Support for help, please include the request ID 8000:1DF2D:1EE39F:657D15:6ADAF110 and timestamp 2026-10-23 05:30:57 UTC. For more on scraping GitHub and how it may affect your rights, please review our Terms of Service (https://docs.github.com/en/site-policy/github-terms/github-terms-of-service) (HTTP 403)";
function runWait(conclusion, { dispatchFails = false, sendErrors = [], notModified = 0, limited = false, limitedMessage = RATE_LIMITED_STDERR } = {}) {
  const step = job("dispatch-full-run").split("\n      - name: Wait for the full run to finish\n")[1];
  const body = /\n {8}run: \|\n((?: {10}.*\n|\s*\n)+)/
    .exec(step)[1]
    .split("\n")
    .map((l) => l.slice(10))
    .join("\n");
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-wait-"));
  mkdirSync(join(dir, "bin"));
  writeFileSync(join(dir, "bin", "sleep"), `#!/bin/sh\necho "$*" >>"${dir}/sleeps"\n`, {
    mode: 0o755,
  });
  writeFileSync(join(dir, "n304"), String(notModified));
  sendErrors.forEach((stderr, i) => writeFileSync(join(dir, `send-stderr-${i + 1}`), stderr));
  const done = `{"status": "completed", "conclusion": "${conclusion}", "head_sha": "${HEAD}"}`;
  const first = notModified > 0 ? `{"status": "in_progress", "conclusion": null, "head_sha": "${HEAD}"}` : done;
  writeFileSync(
    join(dir, "bin", "gh"),
    `#!/usr/bin/env bash
printf '%s\\n' "$*" >>"${dir}/log"
case "$*" in
  *-X\\ POST*)
    s=$(($(cat "${dir}/sends" 2>/dev/null || echo 0) + 1)); echo "$s" >"${dir}/sends"
    if [ -f "${dir}/send-stderr-$s" ]; then cat "${dir}/send-stderr-$s" >&2; exit 1; fi
    exit ${dispatchFails ? 1 : 0} ;;
  ${limited ? `*) echo '${limitedMessage}' >&2; exit 1 ;;` : ""}
  *'-H If-None-Match: "e1"')
    n=$(cat "${dir}/n304")
    if [ "$n" -gt 0 ]; then
      echo $((n - 1)) >"${dir}/n304"
      printf 'HTTP/2.0 304 Not Modified\\r\\nEtag: "e1"\\r\\n\\r\\n'
      echo 'gh: HTTP 304' >&2
      exit 1
    fi
    printf 'HTTP/2.0 200 OK\\r\\nEtag: "e2"\\r\\n\\r\\n%s\\n' '${done}' ;;
  *) printf 'HTTP/2.0 200 OK\\r\\nEtag: "e1"\\r\\n\\r\\n%s\\n' '${first}' ;;
esac
`,
    { mode: 0o755 },
  );
  writeFileSync(join(dir, "body.sh"), body);
  const result = spawnSync("bash", ["-e", join(dir, "body.sh")], {
    env: {
      ...process.env,
      PATH: `${join(dir, "bin")}:${process.env.PATH}`,
      GH_TOKEN: "x",
      REPO: "o/r",
      RUN_ID: "4242",
      RUNNER_TEMP: dir,
    },
    encoding: "utf8",
  });
  const log = existsSync(join(dir, "log")) ? readFileSync(join(dir, "log"), "utf8") : "";
  const sleeps = existsSync(join(dir, "sleeps")) ? readFileSync(join(dir, "sleeps"), "utf8").split("\n").filter(Boolean) : [];
  rmSync(dir, { recursive: true, force: true });
  return {
    status: result.status,
    out: result.stdout + result.stderr,
    writes: log.split("\n").filter((l) => l.includes("-X POST")),
    reads: log.split("\n").filter((l) => l.startsWith("api -i ")),
    sleeps,
  };
}

test("a rate-limited read of the full run stops the wait red after one read", () => {
  const { status, out, reads, writes } = runWait("failure", { limited: true });
  assert.equal(status, 1, out);
  assert.equal(reads.length, 1);
  assert.deepEqual(writes, []);
  assert.match(out, /::error title=GitHub rate limit::the read of run 4242 was rate limited/);
});

// gh's bare 429 message names no rate limit, and is one all the same.
test("a bare HTTP 429 on the read of the full run stops the wait red after one read", () => {
  const { status, out, reads, writes } = runWait("failure", { limited: true, limitedMessage: "gh: Too Many Requests (HTTP 429)" });
  assert.equal(status, 1, out);
  assert.equal(reads.length, 1);
  assert.deepEqual(writes, []);
  assert.match(out, /::error title=GitHub rate limit::the read of run 4242 was rate limited/);
});

// A 304 is the run as last read: the wait keeps its three-minute pace and
// sends the red run once it completes, as with plain reads.
test("a poll answered 304 waits on, then sends the red run once it completes", () => {
  const { status, writes, reads, sleeps } = runWait("failure", { notModified: 2 });
  assert.equal(status, 0);
  assert.deepEqual(writes, [SEND]);
  assert.deepEqual(sleeps, ["180", "180", "180", "180"]);
  assert.deepEqual(reads, [
    "api -i repos/o/r/actions/runs/4242",
    'api -i repos/o/r/actions/runs/4242 -H If-None-Match: "e1"',
    'api -i repos/o/r/actions/runs/4242 -H If-None-Match: "e1"',
    'api -i repos/o/r/actions/runs/4242 -H If-None-Match: "e1"',
  ]);
});

// The alert serializes on signal and head SHA, so the send names the run's
// head SHA as the run reports it, not this workflow's push SHA.
test("a red full run is sent to post-merge-demotion-alert.yml by its run id and head SHA", () => {
  const { status, writes } = runWait("failure");
  assert.equal(status, 0);
  assert.deepEqual(writes, [SEND]);
});

// babysit_postmerge.py's FAILED_CONCLUSIONS, the conclusions post-merge
// demotion counts as red: a cancel on a time-budget overrun is red too.
test("every red conclusion of a full run is sent to post-merge-demotion-alert.yml", () => {
  for (const conclusion of ["failure", "timed_out", "cancelled", "startup_failure", "action_required"]) {
    const { status, writes } = runWait(conclusion);
    assert.equal(status, 0, conclusion);
    assert.deepEqual(writes, [SEND], conclusion);
  }
});

test("a green, skipped or neutral full run is sent nowhere", () => {
  for (const conclusion of ["success", "skipped", "neutral"]) {
    const { status, writes } = runWait(conclusion);
    assert.equal(status, 0, conclusion);
    assert.deepEqual(writes, [], conclusion);
  }
});

test("a send that fails fails the job", () => {
  const { status, out } = runWait("failure", { dispatchFails: true });
  assert.equal(status, 1);
  assert.match(out, /::error::could not send run 4242 to post-merge-demotion-alert\.yml/);
});

// The owner outage rule (Q677: at most three attempts, a capped full-jitter
// backoff), sent again only when the request never left, as the dispatch.
// The 180 s entries are the wait's own polls; the alert's waits come after.
test("an alert send that never left is sent again after a jittered wait, at most three times", () => {
  const timeout = 'Post "https://api.github.com/repos/o/r/actions/workflows/post-merge-demotion-alert.yml/dispatches": net/http: TLS handshake timeout';
  const sent = runWait("failure", { sendErrors: [timeout, timeout] });
  assert.equal(sent.status, 0, sent.out);
  assert.deepEqual(sent.writes, [SEND, SEND, SEND]);
  const waits = sent.sleeps.slice(1).map(Number);
  assert.equal(waits.length, 2);
  assert.ok(waits[0] >= 1 && waits[0] <= 10, `${waits[0]}`);
  assert.ok(waits[1] >= 1 && waits[1] <= 20, `${waits[1]}`);
  const spent = runWait("failure", { sendErrors: [timeout, timeout, timeout] });
  assert.equal(spent.status, 1, spent.out);
  assert.equal(spent.writes.length, 3);
  assert.match(spent.out, /::error::could not send run 4242 to post-merge-demotion-alert\.yml after 3 attempt\(s\)/);
  // A send that may have reached GitHub is not sent again.
  const answered = runWait("failure", { sendErrors: ["gh: Server Error (HTTP 502)", ""] });
  assert.equal(answered.status, 1);
  assert.deepEqual(answered.writes, [SEND]);
});

test("a rate-limited alert send is sent once and stops red", () => {
  for (const stderr of [RATE_LIMITED_STDERR, "gh: Too Many Requests (HTTP 429)"]) {
    const { status, out, writes, sleeps } = runWait("failure", { sendErrors: [stderr] });
    assert.equal(status, 1, out);
    assert.deepEqual(writes, [SEND]);
    assert.deepEqual(sleeps, ["180"]);
    assert.match(out, /::error title=GitHub rate limit::the send of run 4242 to post-merge-demotion-alert\.yml was rate limited/);
  }
});

test("the dispatch job's token is actions: write and nothing else", () => {
  const block = /\n {4}permissions:\n((?: {6}[a-z-]+: [a-z]+.*\n)+)/.exec(job("dispatch-full-run"))[1];
  assert.deepEqual(
    [...block.matchAll(/ {6}([a-z-]+): ([a-z]+)/g)].map((m) => `${m[1]}: ${m[2]}`),
    ["actions: write"],
  );
});

test("pr-require-checks.yml never cancels a dispatched or scheduled run", () => {
  const checks = read("pr-require-checks.yml");
  const on = checks.slice(checks.indexOf("\non:\n"), checks.indexOf("\npermissions:\n"));
  assert.doesNotMatch(on, /\n {2}push:/);
  const group = /\nconcurrency:\n {2}group: >-\n([\s\S]*?)\n {2}cancel-in-progress:/.exec(checks)[1];
  assert.match(group, /github\.event\.pull_request\.number \|\| github\.run_id/);
});

// Only a scheduled or hand-started run arms (enable-auto-merge.mjs
// READER_EVENTS), and a pull request the issue lane just opened is not armed,
// so the issue lane finishing would give the job nothing to do: no
// workflow_run trigger wakes it.
test("no workflow_run trigger wakes pr-merge, and the enable-auto-merge job skips push", () => {
  const on = merge.slice(merge.indexOf("\non:\n"), merge.indexOf("\npermissions:"));
  assert.doesNotMatch(on, /\n {2}workflow_run:/);
  const condition = (body) => /\n {4}if: >-\n([\s\S]*?)\n {4}(?:[a-z-]+:|#)/.exec(body)[1];
  assert.doesNotMatch(condition(job("merge")), /workflow_run/);
  const arm = job("enable-auto-merge");
  const armIf = condition(arm);
  assert.doesNotMatch(armIf, /workflow_run/);
  // A push to main is a merge landing, never a new lane pull request.
  assert.match(armIf, /github\.event_name != 'push'/);
  assert.match(arm, /\n {4}concurrency:\n {6}group: pr-merge-enable-auto-merge\n {6}queue: max\n/);
});

// A job its condition skips never joins the group, so a pull request the job
// cannot arm (not the lanes App's) shows a skipped check, not one pending
// behind every queued run. The other events keep their conditions.
test("a pull request event wakes enable-auto-merge only for a lanes App pull request", () => {
  const armIf = /\n {4}if: >-\n([\s\S]*?)\n {4}[a-z-]+:/.exec(job("enable-auto-merge"))[1];
  assert.match(
    armIf,
    /\(github\.event_name != 'pull_request_target'\n {6}\|\| \(github\.event\.pull_request\.head\.repo\.full_name == github\.repository\n {6}&& format\('\{0\}', github\.event\.pull_request\.user\.id\) == vars\.AUTOMATION_LANES_APP_SENDER_ID\)\)\n/,
  );
  assert.match(armIf, /^ {6}!cancelled\(\)\n/);
  assert.doesNotMatch(armIf, /schedule|workflow_dispatch/);
});

// The merge job's skip, run for enable-auto-merge's own group before the lane
// token or any other read.
test("enable-auto-merge skips its work when a waiting run's enable-auto-merge job does it", () => {
  const arm = job("enable-auto-merge");
  const step = /- name: Check for a newer run that does this work\n([\s\S]*?)(?=\n {6}- name: )/.exec(arm)?.[1];
  assert.ok(step, "a superseded step");
  assert.match(step, /^ {8}id: superseded\n {8}if: steps\.who\.outputs\.proceed == 'true'\n {8}continue-on-error: true\n/);
  assert.match(step, /\n {10}ACTIONS_TOKEN: \$\{\{ github\.token \}\}\n {10}SUPERSEDED_JOB: enable-auto-merge\n/);
  assert.match(step, /\n {8}run: node \.base\/\.github\/scripts\/pr-merge\/superseded\.mjs\n/);
  const names = [...arm.matchAll(/\n {6}- name: (.*)/g)].map((m) => m[1]);
  assert.equal(names.indexOf("Check for a newer run that does this work"), names.indexOf("Check who started the run") + 1);
  assert.ok(names.indexOf("Check for a newer run that does this work") < names.indexOf("Request the lane token"));
  assert.match(arm, /- name: Resolve the config\n {8}id: config\n {8}if: steps\.who\.outputs\.proceed == 'true' && steps\.superseded\.outputs\.superseded != 'true'\n/);
  // The merge job asks for its own job, by default.
  assert.doesNotMatch(job("merge"), /SUPERSEDED_JOB/);
});

// Each job's readers of the files the last run kept share one file of GET
// answers in that job's RUNNER_TEMP; the readers' tests count what it saves.
test("the merge and enable-auto-merge jobs' kept-file readers share their reads", () => {
  for (const [id, scripts] of [
    ["merge", ["rotation.mjs", "head-ref-map.mjs read", "lane-records.mjs read"]],
    ["enable-auto-merge", ["head-ref-map.mjs read", "lane-records.mjs read"]],
  ]) {
    for (const script of scripts) {
      const step = new RegExp(`\\n {10}PR_MERGE_READS_PATH: (.*)\\n {8}run: node \\.base/\\.github/scripts/pr-merge/${script.replace(".", "\\.")}\\n`).exec(job(id));
      assert.equal(step?.[1], "${{ runner.temp }}/pr-merge-reads.json", `${id}: ${script}`);
    }
  }
});

test("the last verifier read enable-auto-merge starts ends inside its step's timeout", () => {
  const arm = job("enable-auto-merge");
  const step = /- name: Arm and disarm auto-merge\n {8}id: arm\n {8}if: .*\n {8}timeout-minutes: ([0-9]+)\n/.exec(arm);
  assert.ok(step, "the arm step names its timeout");
  // The room read, then the verdict budget and the last read it starts.
  assert.ok(LANE_ROOM_TIMEOUT_MS + VERIFY_BUDGET_MS + VERIFY_TIMEOUT_MS < Number(step[1]) * 60_000);
});

test("enable-auto-merge logs both tokens' readings at job end, before the token is revoked", () => {
  const arm = job("enable-auto-merge");
  const block = /- name: Log the API budget at job end\n([\s\S]*?)(?=\n {6}- name: |$)/.exec(arm)?.[1];
  assert.ok(block, "a job-end budget step");
  assert.match(block, /\n {8}uses: \.\/\.base\/\.github\/actions\/log-api-budget /);
  assert.match(block, /^ {8}id: budget-end\n {8}if: always\(\) && steps\.lane-token\.outputs\.token != ''\n/);
  assert.match(block, /\n {8}continue-on-error: true\n {8}timeout-minutes: 1\n/);
  assert.match(block, /\n {10}tokens: lanes-app github-token\n/);
  // The reader's gh calls read into both names.
  const step = /- name: Arm and disarm auto-merge\n([\s\S]*?)(?=\n {6}- name: )/.exec(arm)[1];
  assert.match(step, /\n {10}API_BUDGET_TOKEN: lanes-app\n {10}API_BUDGET_OVERRIDE_TOKEN: github-token\n/);
  const names = [...arm.matchAll(/\n {6}- name: (.*)/g)].map((m) => m[1]);
  assert.ok(names.indexOf("Arm and disarm auto-merge") < names.indexOf("Log the API budget at job end"));
  assert.ok(names.indexOf("Log the API budget at job end") < names.indexOf("Revoke the lane token"));
});

// The lane's room (lane-room) reads this run's post-merge report, which
// post-merge-dispatch keeps, rather than running the check a third time per
// scheduled run, and the rung cap as the merge job passes it: an unset cap
// holds the lane off, so a step that drops it would disarm every lane pull
// request.
test("enable-auto-merge reads the lane's room from this run's post-merge-dispatch report and the rung cap", () => {
  const dispatch = job("post-merge-dispatch");
  const keep = /- name: Keep the post-merge report for enable-auto-merge\n([\s\S]*?)(?=\n {6}- name: |\n*$)/.exec(dispatch)?.[1];
  assert.ok(keep, "post-merge-dispatch keeps its report");
  assert.match(keep, /uses: actions\/upload-artifact@[0-9a-f]{40} /);
  // The directory holds post-merge.json, so the download below finds it at
  // post-merge/post-merge.json.
  assert.match(keep, /\n {10}name: pr-merge-post-merge-report\n {10}path: \$\{\{ runner\.temp \}\}\/post-merge-report\/\n {10}retention-days: 1\n/);
  assert.match(dispatch, /\n {10}cp "\$RUNNER_TEMP\/post-merge\.json" "\$kept\/post-merge\.json"\n/);
  const arm = job("enable-auto-merge");
  assert.match(arm, /^ {4}# [\s\S]*?\n {4}needs: \[post-merge-dispatch\]\n/);
  assert.match(/\n {4}if: >-\n([\s\S]*?)\n {4}[a-z-]+:/.exec(arm)[1], /^ {6}!cancelled\(\)\n/);
  // No check of its own: the report comes from this run's job alone.
  assert.doesNotMatch(arm, /python3 [^\n]*babysit_postmerge\.py/);
  const read = /- name: Read this run's post-merge report\n([\s\S]*?)(?=\n {6}- name: )/.exec(arm)?.[1];
  assert.ok(read, "a download of the report");
  assert.match(read, /uses: actions\/download-artifact@[0-9a-f]{40} /);
  assert.match(read, /\n {10}name: pr-merge-post-merge-report\n/);
  // Not 'success': a step after the kept report can fail the job.
  assert.match(read, /needs\.post-merge-dispatch\.result != 'skipped'/);
  assert.doesNotMatch(read, /run-id|github-token|repository:/);
  const step = /- name: Arm and disarm auto-merge\n([\s\S]*?)(?=\n {6}- name: )/.exec(arm)[1];
  assert.match(step, /\n {10}POSTMERGE_RESULT: \$\{\{ runner\.temp \}\}\/post-merge\/post-merge\.json\n/);
  assert.match(step, /\n {10}RUNG_CAP: \$\{\{ vars\.CLAUDE_LANES_MERGE_RUNG_CAP \}\}\n/);
  const names = [...arm.matchAll(/\n {6}- name: (.*)/g)].map((m) => m[1]);
  assert.ok(names.indexOf("Read this run's post-merge report") < names.indexOf("Arm and disarm auto-merge"));
});

// A room that checks the post-merge answer again reads the lane records the
// last run kept, as post-merge-dispatch's check does, so the check answers
// them with no artifact or run read each; without them the check can run
// past the room's LANE_ROOM_TIMEOUT_MS.
test("enable-auto-merge hands the room's post-merge check the lane records the last run kept", () => {
  const arm = job("enable-auto-merge");
  const records = /- name: Read the lane records the last run kept\n([\s\S]*?)(?=\n {6}- name: )/.exec(arm)?.[1];
  assert.ok(records, "a lane-records read");
  assert.match(records, /\n {8}continue-on-error: true\n/);
  assert.match(records, /\n {10}ACTIONS_TOKEN: \$\{\{ github\.token \}\}\n {10}LANE_RECORDS_PATH: \$\{\{ runner\.temp \}\}\/lane-records\.json\n/);
  assert.match(records, /\n {8}run: node \.base\/\.github\/scripts\/pr-merge\/lane-records\.mjs read\n/);
  const step = /- name: Arm and disarm auto-merge\n([\s\S]*?)(?=\n {6}- name: )/.exec(arm)[1];
  assert.match(step, /\n {10}BABYSIT_POSTMERGE_LANE_RECORDS: \$\{\{ runner\.temp \}\}\/lane-records\.json\n/);
  const names = [...arm.matchAll(/\n {6}- name: (.*)/g)].map((m) => m[1]);
  assert.ok(names.indexOf("Read the lane records the last run kept") < names.indexOf("Arm and disarm auto-merge"));
  // Within the job's own permissions: the read needs actions: read alone.
  assert.match(arm, /\n {6}actions: read #/);
});

// Without history the post-merge check's containment test cannot decide, and
// every lane record falls back to a compare API call.
test("the default branch checkouts of the post-merge check, the merge and enable-auto-merge fetch full history", () => {
  for (const name of ["post-merge-dispatch", "merge", "enable-auto-merge"]) {
    const checkout = /- name: Check out the default branch tip\n([\s\S]*?)(?=\n {6}- name: |\n*$)/.exec(job(name))?.[1];
    assert.ok(checkout, `${name} checks out the default branch tip`);
    assert.match(checkout, /\n {10}fetch-depth: 0\n/, name);
  }
});

test("enable-auto-merge's step timeouts fit inside its job's", () => {
  const arm = job("enable-auto-merge");
  const total = Number(/\n {4}timeout-minutes: ([0-9]+)\n/.exec(arm)[1]);
  const steps = [...arm.matchAll(/\n {8}timeout-minutes: ([0-9]+)\n/g)].map((m) => Number(m[1]));
  assert.ok(steps.length >= 4, "the post-merge check, the run cache read, the arm step and the budget step name timeouts");
  assert.ok(steps.reduce((sum, minutes) => sum + minutes, 0) < total, `${steps.join(" + ")} inside ${total}`);
});

// pr-unblock's report-conflict-status precedent: statuses: write only on a
// job that holds no lane token and runs only main's script.
test("the pr-merge/unarmed statuses are posted by a job of their own, with statuses: write and nothing it could run from a pull request", () => {
  const arm = job("enable-auto-merge");
  assert.match(arm, /\n {4}outputs:\n {6}unarmed-statuses: \$\{\{ steps\.arm\.outputs\.unarmed-statuses \}\}\n/);
  assert.match(arm, /\n {6}- name: Arm and disarm auto-merge\n {8}id: arm\n/);
  assert.match(arm, /RISK_ESCALATION_MINUTES=\$\(yq '\.merge\."risk-escalation-minutes" \/\/ ""' "\$config"\)\n/);
  const post = job("unarmed-status");
  assert.match(post, /^ {4}needs: \[enable-auto-merge\]\n/);
  // It runs whenever enable-auto-merge handed it statuses, after a failed
  // step too, and only then.
  assert.match(post, /\n {4}if: \$\{\{ !cancelled\(\) && needs\.enable-auto-merge\.outputs\.unarmed-statuses != '' \}\}\n/);
  const block = /\n {4}permissions:\n((?: {6}[a-z-]+: [a-z]+.*\n)+)/.exec(post)[1];
  assert.deepEqual(
    [...block.matchAll(/ {6}([a-z-]+): ([a-z]+)/g)].map((m) => `${m[1]}: ${m[2]}`),
    ["contents: read", "statuses: write"],
  );
  assert.doesNotMatch(post, /lane-token|request-lane-token|id-token/);
  assert.match(post, /\n {10}ref: refs\/heads\/main\n {10}path: \.base\n {10}persist-credentials: false\n/);
  // The statuses reach the script through its environment, never the shell.
  assert.match(post, /\n {10}STATUSES: \$\{\{ needs\.enable-auto-merge\.outputs\.unarmed-statuses \}\}\n {8}run: node \.base\/\.github\/scripts\/pr-merge\/post-unarmed-status\.mjs\n/);
});

// The merge job's sizing comment: about a minute before the loop, then the
// longer of the gate budget (10) plus a candidate's read limit (4) and a
// deferred candidate's ceiling (20), plus one read's own timeout (4); the
// escalation clear's own timeout comes on top.
test("the merge job's ceiling covers the gate's sweep and the escalation clear", () => {
  const gate = job("merge");
  const total = Number(/\n {4}timeout-minutes: ([0-9]+)\n/.exec(gate)[1]);
  const clear = Number(/- name: Clear escalations whose reason no longer holds\n[\s\S]*?\n {8}timeout-minutes: ([0-9]+)\n/.exec(gate)[1]);
  assert.ok(total >= 1 + Math.max(10 + 4, 20) + 4 + clear, `${total} minutes for the gate and a ${clear}-minute clear`);
});

test("enable-auto-merge asks the broker for its own activity's merge token", () => {
  const arm = job("enable-auto-merge");
  const steps = [...arm.matchAll(/\n {10}lane: (.*)\n {10}activity: (.*)\n/g)].map((m) => `${m[1]}/${m[2]}`);
  assert.deepEqual(steps, ["pr-merge/enable-auto-merge", "pr-merge/enable-auto-merge"]);
  assert.match(arm, /node \.base\/\.github\/scripts\/pr-merge\/enable-auto-merge\.mjs/);
  // A missing merge.report-only reaches the script as `null`, which it reads
  // as report-only; the job must not turn it into `false`.
  assert.match(arm, /REPORT_ONLY=\$\(yq '\.merge\."report-only"' "\$config"\)\n/);
  assert.doesNotMatch(arm, /REPORT_ONLY=false/);
  // The hold paths come from the config the job resolved.
  assert.match(arm, /output-path: \$\{\{ runner\.temp \}\}\/resolved-config\.json\n/);
  assert.match(arm, /\n {10}RESOLVED_CONFIG: \$\{\{ runner\.temp \}\}\/resolved-config\.json\n/);
  const block = /\n {4}permissions:\n((?: {6}[a-z-]+: [a-z]+.*\n)+)/.exec(arm)[1];
  assert.deepEqual(
    [...block.matchAll(/ {6}([a-z-]+): ([a-z]+)/g)].map((m) => `${m[1]}: ${m[2]}`),
    ["contents: read", "actions: read", "pull-requests: read", "checks: read", "issues: read", "id-token: write"],
  );
  // The verifier evidence is read as the gate reads it: the job's
  // GITHUB_TOKEN for the Actions reads, with the run's head-ref map and
  // carried run cache.
  for (const line of [
    "EVENT_NAME: ${{ github.event_name }}",
    "BABYSIT_VERIFY_GH_TOKEN: ${{ github.token }}",
    "BABYSIT_VERIFY_HEAD_REFS: ${{ runner.temp }}/head-refs-in.json",
    "BABYSIT_RUN_CACHE: ${{ runner.temp }}/babysit-run-cache.json",
  ]) {
    assert.ok(arm.includes(`\n          ${line}\n`), line);
  }
  assert.match(arm, /node \.base\/\.github\/scripts\/pr-merge\/head-ref-map\.mjs read\n/);
  // Only the runs that read the verdict (READER_EVENTS) read the map.
  assert.match(
    arm,
    /- name: Read the head refs the last gate run kept\n {8}if: steps\.lane-token\.outputs\.token != '' && \(github\.event_name == 'schedule' \|\| github\.event_name == 'workflow_dispatch'\)\n/,
  );
  // The reader resolves the FAIL cap itself, from the base and main (--base-sha).
  assert.doesNotMatch(arm, /MAX_VERIFY_FAILS/);
});

// The dispatch POST's retry, run under bash against a stub gh that answers
// each POST in turn from `answers` ({status, headers, body}, or {stderr} for
// no response at all, with gh's error text), a stub sleep that logs its seconds and a stub date
// whose `+%s` is NOW. The expected answers come from the owner outage rule
// (at most three attempts, a capped full-jitter backoff) and the owner's
// ban rule: a rate limit is never sent again, and the step fails red naming
// the reset, the later of retry-after and x-ratelimit-reset while remaining
// is 0, else a minute on, as GitHub documents the waits
// (https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api).
// Each expected reset below is `date -u -d @<seconds>` of the NOW sum.
const NOW = 1792736000;
const runBody = (block) =>
  /\n {8}run: \|\n((?: {10}.*\n|\s*\n)+)/
    .exec(block)[1]
    .split("\n")
    .map((l) => l.slice(10))
    .join("\n")
    .trimEnd();
const dispatchStep = (id) => {
  const block = job(id).split("\n      - name: Start the full CI run on main\n")[1].split("\n      - name: ")[0];
  return { body: runBody(block), cap: /\n {10}WAIT_CAP: (\d+)\n/.exec(block)[1] };
};
const ok = (id) => ({ status: "200 OK", headers: {}, body: JSON.stringify({ workflow_run_id: id }) });
const limited = (headers, message = "API rate limit exceeded for installation") => ({
  status: "403 Forbidden",
  headers,
  body: JSON.stringify({ message }),
});
function runDispatch(answers, { jobId = "dispatch-full-run", cap, event = "push" } = {}) {
  const step = dispatchStep(jobId);
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-dispatch-"));
  mkdirSync(join(dir, "bin"));
  answers.forEach((a, i) => {
    const text =
      a.status === undefined
        ? ""
        : `HTTP/2.0 ${a.status}\n${Object.entries(a.headers)
            .map(([k, v]) => `${k}: ${v}\r\n`)
            .join("")}\r\n${a.body}`;
    writeFileSync(join(dir, `answer-${i + 1}`), text);
    writeFileSync(join(dir, `stderr-${i + 1}`), a.stderr ?? "");
    writeFileSync(join(dir, `code-${i + 1}`), a.status?.startsWith("200") ? "0" : "1");
  });
  writeFileSync(
    join(dir, "bin", "gh"),
    `#!/usr/bin/env bash
n=$(($(cat "${dir}/calls" 2>/dev/null || echo 0) + 1)); echo "$n" >"${dir}/calls"
printf '%s\\n' "$*" >>"${dir}/log"
cat "${dir}/answer-$n" 2>/dev/null
cat "${dir}/stderr-$n" >&2 2>/dev/null
exit "$(cat "${dir}/code-$n" 2>/dev/null || echo 1)"
`,
    { mode: 0o755 },
  );
  writeFileSync(join(dir, "bin", "sleep"), `#!/bin/sh\necho "$1" >>"${dir}/slept"\n`, { mode: 0o755 });
  const realDate = spawnSync("bash", ["-c", "command -v date"], { encoding: "utf8" }).stdout.trim();
  writeFileSync(join(dir, "bin", "date"), `#!/bin/sh\nif [ "$1" = +%s ]; then echo ${NOW}; else exec ${realDate} "$@"; fi\n`, { mode: 0o755 });
  writeFileSync(join(dir, "body.sh"), step.body);
  writeFileSync(join(dir, "output"), "");
  const result = spawnSync("bash", ["-e", join(dir, "body.sh")], {
    env: {
      ...process.env,
      PATH: `${join(dir, "bin")}:${process.env.PATH}`,
      GH_TOKEN: "x",
      REPO: "o/r",
      WAIT_CAP: cap ?? step.cap,
      GITHUB_EVENT_NAME: event,
      GITHUB_SHA: HEAD,
      GITHUB_RUN_ID: "77",
      GITHUB_OUTPUT: join(dir, "output"),
      RUNNER_TEMP: dir,
    },
    encoding: "utf8",
  });
  const read = (name) => (existsSync(join(dir, name)) ? readFileSync(join(dir, name), "utf8") : "");
  const out = {
    status: result.status,
    out: result.stdout + result.stderr,
    posts: read("log").split("\n").filter((l) => l.includes("-X POST")).length,
    slept: read("slept").split("\n").filter(Boolean).map(Number),
    output: read("output"),
    record: read("dispatched.json"),
  };
  rmSync(dir, { recursive: true, force: true });
  return out;
}

test("both jobs send the dispatch with the same retry", () => {
  assert.equal(dispatchStep("post-merge-dispatch").body, dispatchStep("dispatch-full-run").body);
});

test("a dispatch answered at once records its run and waits for nothing", () => {
  const r = runDispatch([ok(4242)]);
  assert.equal(r.status, 0, r.out);
  assert.equal(r.posts, 1);
  assert.deepEqual(r.slept, []);
  assert.match(r.output, /^run-id=4242$/m);
  assert.deepEqual(JSON.parse(r.record), { dispatcher_run_id: 77, run_id: 4242 });
});

// A rate limit stops the step red after its one POST, with no wait.
const stopped = (r) => {
  assert.equal(r.status, 1, r.out);
  assert.equal(r.posts, 1);
  assert.deepEqual(r.slept, []);
  assert.doesNotMatch(r.output, /run-id=/);
  // post-merge-dispatch's re-run step reads it and sends nothing.
  assert.match(r.output, /^rate-limited=true$/m);
  assert.equal(r.record, "");
};

test("a retry-after stops every pool until the later of it and a spent pool's reset", () => {
  const r = runDispatch([limited({ "Retry-After": "7", "X-Ratelimit-Remaining": "0", "X-Ratelimit-Reset": `${NOW + 100}` }), ok(4243)]);
  stopped(r);
  assert.match(r.out, /::error title=GitHub rate limit::every pool is exhausted \(HTTP 403: .*\); nothing more is sent before 2026-10-23T06:15:00Z/);
});

test("a primary limit with no retry-after names its pool and the reset", () => {
  const r = runDispatch([limited({ "X-Ratelimit-Remaining": "0", "X-Ratelimit-Reset": `${NOW + 30}`, "X-Ratelimit-Resource": "core" }), ok(4244)]);
  stopped(r);
  assert.match(r.out, /::error title=GitHub rate limit::the core pool is exhausted .*before 2026-10-23T06:13:50Z/);
  // The merge job reads this through post-merge-dispatch's rate-limited output.
  assert.match(r.output, /^stop=the core pool until 2026-10-23T06:13:50Z$/m);
});

test("a secondary limit named only by its message stops every pool for a minute", () => {
  const r = runDispatch(
    [limited({ "X-Ratelimit-Remaining": "812" }, "You have exceeded a secondary rate limit"), ok(4245)],
    { jobId: "post-merge-dispatch", event: "schedule" },
  );
  stopped(r);
  assert.match(r.out, /::error title=GitHub rate limit::every pool is exhausted .*before 2026-10-23T06:14:20Z/);
});

test("a 429 is stopped like a 403", () => {
  const r = runDispatch([{ ...limited({ "Retry-After": "5" }), status: "429 Too Many Requests" }, ok(1)]);
  stopped(r);
});

// Any 429 is a rate limit, and a limit no header times waits as
// rate-guard.mjs classify decides: the minute for a secondary one, else the hour.
const DISPATCH_URL = "https://api.github.com/repos/o/r/actions/workflows/pr-require-checks.yml/dispatches";
for (const [name, status, body] of [
  ["a bare 429 with no headers or message", 429, ""],
  ["a 403 whose message names a primary rate limit, with no headers", 403, JSON.stringify({ message: "API rate limit exceeded for installation" })],
  ["a 403 whose message names a secondary rate limit, with no headers", 403, JSON.stringify({ message: "You have exceeded a secondary rate limit" })],
  ["a 403 whose message names only abuse detection, with no headers", 403, JSON.stringify({ message: "You have triggered an abuse detection mechanism" })],
]) {
  test(`${name} stops every pool until the guard's reset`, () => {
    const want = classify({ url: DISPATCH_URL, status, headers: {}, body }, { now: NOW * 1000 });
    assert.equal(want.pool, "*");
    for (const jobId of ["dispatch-full-run", "post-merge-dispatch"]) {
      const r = runDispatch([{ status: `${status} X`, headers: {}, body }, ok(1)], { jobId, event: "schedule" });
      stopped(r);
      assert.match(r.out, new RegExp(`::error title=GitHub rate limit::every pool is exhausted \\(HTTP ${status}: .*before ${resetLabel(want.reset)}`));
    }
  });
}

test("a secondary limit with a spent pool still stops every pool, as the guard does", () => {
  const headers = { "x-ratelimit-remaining": "0", "x-ratelimit-reset": `${NOW + 30}`, "x-ratelimit-resource": "core" };
  const body = JSON.stringify({ message: "You have exceeded a secondary rate limit" });
  const want = classify({ url: DISPATCH_URL, status: 403, headers, body }, { now: NOW * 1000 });
  assert.equal(want.pool, "*");
  for (const jobId of ["dispatch-full-run", "post-merge-dispatch"]) {
    const r = runDispatch([{ status: "403 X", headers, body }, ok(1)], { jobId, event: "schedule" });
    stopped(r);
    assert.match(r.out, new RegExp(`::error title=GitHub rate limit::every pool is exhausted \\(HTTP 403: .*before ${resetLabel(want.reset)}`));
    assert.match(r.output, new RegExp(`^stop=every pool until ${resetLabel(want.reset)}$`, "m"));
  }
});

const refused = () => limited({ "X-Ratelimit-Remaining": "900" }, "Resource not accessible by integration");

test("a refusal ends green with a warning naming the merge, and no run id", () => {
  const r = runDispatch([refused(), ok(1)]);
  assert.equal(r.status, 0, r.out);
  assert.match(r.out, new RegExp(`::warning::no full CI run started for merge ${HEAD} after 1 attempt\\(s\\): HTTP 403`));
  assert.doesNotMatch(r.output, /run-id=/);
});

test("a scheduled run's warning names main at the run's start, not a merge", () => {
  const r = runDispatch([refused()], { jobId: "post-merge-dispatch", event: "schedule" });
  assert.match(r.out, new RegExp(`::warning::no full CI run started for main \\(this run started at ${HEAD}\\)`));
});

test("a wait past the job's cap is not taken", () => {
  const r = runDispatch([{ stderr: 'Post "https://api.github.com/x": dial tcp: lookup api.github.com: no such host' }, ok(1)], { cap: "0" });
  assert.equal(r.status, 0, r.out);
  assert.equal(r.posts, 1);
  assert.deepEqual(r.slept, []);
  assert.match(r.out, /::warning::.*wait does not fit the 0s this job allows/);
  assert.doesNotMatch(r.output, /run-id=/);
});

test("a refusal that is no rate limit, and a 5xx, are sent once", () => {
  for (const answer of [
    limited({ "X-Ratelimit-Remaining": "900" }, "Resource not accessible by integration"),
    { status: "422 Unprocessable Entity", headers: {}, body: '{"message":"No ref found for: main"}' },
    { status: "502 Bad Gateway", headers: {}, body: "" },
  ]) {
    const r = runDispatch([answer, ok(1)]);
    assert.equal(r.status, 0, r.out);
    assert.equal(r.posts, 1, answer.status);
    assert.deepEqual(r.slept, [], answer.status);
    assert.match(r.out, /::warning::no full CI run started/, answer.status);
  }
});

// gh's errors for a request that never left (Go net/http wording, as gh
// prints it): a DNS lookup, a refused connection, a failed TLS handshake.
const unsent = [
  'Post "https://api.github.com/repos/o/r/actions/workflows/pr-require-checks.yml/dispatches": dial tcp: lookup api.github.com on 127.0.0.53:53: no such host',
  'Post "https://api.github.com/repos/o/r/actions/workflows/pr-require-checks.yml/dispatches": dial tcp 140.82.112.6:443: connect: connection refused',
  'Post "https://api.github.com/repos/o/r/actions/workflows/pr-require-checks.yml/dispatches": remote error: tls: handshake failure',
].map((stderr) => ({ stderr }));

test("a request that never left is sent again after a jittered wait inside its bound", () => {
  const r = runDispatch([unsent[0], unsent[1], ok(4246)]);
  assert.equal(r.status, 0, r.out);
  assert.equal(r.posts, 3);
  assert.equal(r.slept.length, 2);
  assert.ok(r.slept[0] >= 1 && r.slept[0] <= 10, `${r.slept[0]}`);
  assert.ok(r.slept[1] >= 1 && r.slept[1] <= 20, `${r.slept[1]}`);
  assert.match(r.output, /^run-id=4246$/m);
  assert.equal(runDispatch([unsent[2], ok(4247)]).posts, 2);
});

// Go's net/http error when the TLS handshake outlasts its timeout, before any
// request byte is written, so a resend cannot start a second run.
const handshakeTimeout = { stderr: `Post "${DISPATCH_URL}": net/http: TLS handshake timeout` };

test("a TLS handshake timeout is sent again in both jobs", () => {
  for (const jobId of ["dispatch-full-run", "post-merge-dispatch"]) {
    const r = runDispatch([handshakeTimeout, ok(4248)], { jobId, event: "schedule" });
    assert.equal(r.status, 0, r.out);
    assert.equal(r.posts, 2, jobId);
    assert.equal(r.slept.length, 1, jobId);
    assert.ok(r.slept[0] >= 1 && r.slept[0] <= 10, `${r.slept[0]}`);
    assert.match(r.output, /^run-id=4248$/m, jobId);
  }
});

// The resend never reaches past a rate limit: the attempt after the timeout
// is answered with one, and nothing is sent after it.
test("a rate limit after a TLS handshake timeout still stops red, with no further send", () => {
  for (const jobId of ["dispatch-full-run", "post-merge-dispatch"]) {
    const r = runDispatch([handshakeTimeout, limited({ "X-Ratelimit-Remaining": "0", "X-Ratelimit-Reset": `${NOW + 30}`, "X-Ratelimit-Resource": "core" }), ok(1)], { jobId, event: "schedule" });
    assert.equal(r.status, 1, r.out);
    assert.equal(r.posts, 2, jobId);
    assert.equal(r.slept.length, 1, jobId);
    assert.match(r.output, /^rate-limited=true$/m, jobId);
    assert.doesNotMatch(r.output, /run-id=/, jobId);
  }
});

// Only a lane merge is picked up by the scheduled post-merge check; any other
// merge waits for the next push or pr-require-checks.yml's own schedule.
test("the exhausted-retry warning names who starts the run next", () => {
  assert.match(read("pr-require-checks.yml"), /\n {2}schedule:\n {4}- cron: /);
  for (const jobId of ["dispatch-full-run", "post-merge-dispatch"]) {
    const r = runDispatch([refused()], { jobId, event: "schedule" });
    assert.match(r.out, /::warning::no full CI run started .*; a scheduled pr-merge run starts one only for a lane merge, and any other merge waits for the next push or pr-require-checks' own schedule$/m, jobId);
  }
});

// A reset or a timeout on an open connection may come after GitHub took the
// request, so the run may exist: stop as on exhaustion.
test("no response once the request may have been sent is not sent again", () => {
  for (const stderr of [
    'Post "https://api.github.com/repos/o/r/actions/workflows/pr-require-checks.yml/dispatches": read tcp 10.1.0.4:51234->140.82.112.6:443: read: connection reset by peer',
    'Post "https://api.github.com/repos/o/r/actions/workflows/pr-require-checks.yml/dispatches": context deadline exceeded (Client.Timeout exceeded while awaiting headers)',
    "",
  ]) {
    const r = runDispatch([{ stderr }, ok(1)]);
    assert.equal(r.status, 0, r.out);
    assert.equal(r.posts, 1, stderr);
    assert.deepEqual(r.slept, [], stderr);
    assert.match(r.out, /::warning::no full CI run started .*the request may have been sent; not sent again/, stderr);
    assert.doesNotMatch(r.output, /run-id=/);
  }
});

test("a dispatch that returns no run id is not sent again and records nothing", () => {
  const r = runDispatch([{ status: "200 OK", headers: {}, body: "{}" }, ok(1)]);
  assert.equal(r.status, 0, r.out);
  assert.equal(r.posts, 1);
  assert.match(r.out, /::warning::.*the dispatch returned no run id/);
  assert.doesNotMatch(r.output, /run-id=/);
});

test("a dispatch that failed skips the record and the wait", () => {
  for (const id of ["dispatch-full-run", "post-merge-dispatch"]) {
    const record = job(id).split("\n      - name: Record the dispatched run\n")[1];
    assert.match(record, /^ {8}if: steps\.dispatch\.outputs\.run-id != ''\n/, id);
  }
  const wait = job("dispatch-full-run").split("\n      - name: Wait for the full run to finish\n")[1];
  assert.match(wait, /^ {8}if: github\.event_name == 'push' && steps\.dispatch\.outputs\.run-id != ''\n/);
});

// Each job's "Check who started the run" step, run under bash from a directory
// whose .base is this checkout, with the step's own env (its github context
// filled from the run below) and an API that serves this run attempt's record,
// or answers 404 when record is null. Expected values come from GitHub's
// workflow run record: actor is who started the run and triggering_actor who
// started this attempt, each with a permanent account id, while a login can be
// released and registered by someone else. The listed human is
// trusted-actors.json's entry 153232337.
const OWNER = { id: 153232337, login: "kyle-sexton" };
const BOT = { id: 41898282, login: "github-actions[bot]" };
async function runWho(
  jobId,
  {
    event = "workflow_dispatch",
    attempt = "2",
    actor = OWNER,
    actorId = String(actor.id),
    rerunner = actor,
    record = { id: 4242, run_attempt: Number(attempt), actor, triggering_actor: rerunner },
    env: extra = {},
  } = {},
) {
  const step = /- name: Check who started the run\n([\s\S]*?)(?=\n {6}- name: )/.exec(job(jobId))[1];
  const context = {
    "github.event_name": event,
    "github.actor_id": actorId,
    "github.triggering_actor": rerunner.login,
    "github.token": "t",
  };
  const stepEnv = Object.fromEntries(
    [...step.matchAll(/^ {10}([A-Z_]+): (.*)$/gm)].map(([, k, v]) => [k, v.replace(/\$\{\{ (\S+) \}\}/g, (_, e) => context[e])]),
  );
  const block = /\n {8}run: \|\n((?: {10}.*\n|\s*\n)+)/.exec(step);
  const body = block ? block[1].split("\n").map((l) => l.slice(10)).join("\n") : /\n {8}run: (.*)/.exec(step)[1];
  const reads = [];
  const server = createServer((req, res) => {
    reads.push(req.url);
    const found = req.url === "/repos/o/r/actions/runs/4242" && record !== null;
    res.writeHead(found ? 200 : 404, { "Content-Type": "application/json" });
    res.end(JSON.stringify(found ? record : { message: "Not Found" }));
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-who-"));
  try {
    symlinkSync(fileURLToPath(new URL("../../../", import.meta.url)), join(dir, ".base"));
    writeFileSync(join(dir, "body.sh"), body);
    const output = join(dir, "output");
    const env = {
      ...process.env,
      ...stepEnv,
      GITHUB_OUTPUT: output,
      GITHUB_REPOSITORY: "o/r",
      GITHUB_RUN_ID: "4242",
      GITHUB_RUN_ATTEMPT: attempt,
      GITHUB_EVENT_NAME: event,
      GITHUB_API_URL: `http://127.0.0.1:${server.address().port}`,
      // .base is a link here, a checkout in CI: keep the script's own path.
      NODE_OPTIONS: "--preserve-symlinks-main",
      ...extra,
    };
    let stdout = "";
    const status = await new Promise((resolve) => {
      const child = spawn("bash", ["-e", join(dir, "body.sh")], { cwd: dir, env, stdio: ["ignore", "pipe", "ignore"] });
      child.stdout.on("data", (chunk) => {
        stdout += chunk;
      });
      child.on("close", resolve);
    });
    assert.equal(status, 0);
    return { proceed: /^proceed=(.*)$/m.exec(readFileSync(output, "utf8"))?.[1], reads, stdout };
  } finally {
    server.close();
    rmSync(dir, { recursive: true, force: true });
  }
}

const RUN_READ = ["/repos/o/r/actions/runs/4242"];

for (const jobId of ["merge", "enable-auto-merge"]) {
  test(`${jobId}: a listed human's id proceeds whatever its login now reads`, async () => {
    const renamed = { id: OWNER.id, login: "kyle-renamed" };
    const { proceed, reads } = await runWho(jobId, { actor: renamed });
    assert.equal(proceed, "true");
    assert.deepEqual(reads, RUN_READ);
  });

  test(`${jobId}: a re-runner holding a listed login under another id stops, naming both ids`, async () => {
    const { proceed, stdout } = await runWho(jobId, { rerunner: { id: 999, login: OWNER.login } });
    assert.equal(proceed, "false");
    assert.match(stdout, /::notice::.*actor id 153232337, re-runner id 999\)/);
  });

  test(`${jobId}: an unreadable run record stops`, async () => {
    assert.equal((await runWho(jobId, { record: null })).proceed, "false");
  });

  test(`${jobId}: another attempt's record or a missing id stops`, async () => {
    assert.equal((await runWho(jobId, { record: { id: 4242, run_attempt: 1, actor: OWNER, triggering_actor: OWNER } })).proceed, "false");
    assert.equal((await runWho(jobId, { record: { id: 4242, run_attempt: 2, actor: OWNER, triggering_actor: { login: OWNER.login } } })).proceed, "false");
  });

  test(`${jobId}: an unlisted actor stops before any read, whoever re-ran it`, async () => {
    const { proceed, reads, stdout } = await runWho(jobId, { actor: { id: 999, login: "someone" }, rerunner: OWNER });
    assert.equal(proceed, "false");
    assert.deepEqual(reads, []);
    assert.match(stdout, /::notice::.*\(actor id 999\)/);
    const malformed = await runWho(jobId, { actorId: "abc", rerunner: OWNER });
    assert.equal(malformed.proceed, "false");
    assert.deepEqual(malformed.reads, []);
    // Number() reads this as the listed id; only the id's own shape refuses it.
    const padded = await runWho(jobId, { actorId: `0${OWNER.id}`, rerunner: OWNER });
    assert.equal(padded.proceed, "false");
    assert.deepEqual(padded.reads, []);
  });

  // GitHub names as a scheduled run's actor whoever last changed the
  // schedule, often a bot, and a re-run keeps the schedule event.
  test(`${jobId}: a scheduled run's first attempt proceeds without a read`, async () => {
    const { proceed, reads } = await runWho(jobId, { event: "schedule", attempt: "1", actor: BOT, record: null });
    assert.equal(proceed, "true");
    assert.deepEqual(reads, []);
  });

  test(`${jobId}: a re-run of a scheduled run proceeds only for a listed re-runner`, async () => {
    const listed = await runWho(jobId, { event: "schedule", actor: BOT, rerunner: OWNER });
    assert.equal(listed.proceed, "true");
    assert.deepEqual(listed.reads, RUN_READ);
    assert.equal((await runWho(jobId, { event: "schedule", actor: BOT, rerunner: { id: 999, login: "someone" } })).proceed, "false");
    assert.equal((await runWho(jobId, { event: "schedule", actor: BOT, rerunner: OWNER, record: null })).proceed, "false");
  });

  test(`${jobId}: a repository name GitHub cannot hold stops before any read`, async () => {
    const { proceed, reads } = await runWho(jobId, { env: { GITHUB_REPOSITORY: "o/.." } });
    assert.equal(proceed, "false");
    assert.deepEqual(reads, []);
  });

  test(`${jobId}: an unreadable trusted list stops with its own reason`, async () => {
    const { proceed, reads, stdout } = await runWho(jobId, { env: { TRUSTED_ACTORS_PATH: "missing.json" } });
    assert.equal(proceed, "false");
    assert.deepEqual(reads, []);
    assert.match(stdout, /::warning title=who::ENOENT/);
    assert.doesNotMatch(stdout, /record/);
  });
}

// A job holding `id-token: write` (the token broker's proof) or a lanes App
// token restores no Actions cache by a bare `restore-keys` prefix: any job in
// the default branch's cache scope can write such an entry, and the pinned
// restore extracts its archive with no entry filter, so a crafted entry could
// replace a checked-out script before it runs (#9455). In pr-merge.yml no such
// job restores a cache at all. Steps of a local composite action count as the
// job's own.
const root = new URL("../../../", import.meta.url);
const workflowsDir = new URL(".github/workflows/", root);
const stepsIn = (text) => text.split(/\n(?=\s*- (?:name|uses|id|if|run|env|with|shell|continue-on-error|timeout-minutes):)/).slice(1);
const restoresOf = (stepTexts, seen = new Set()) =>
  stepTexts.flatMap((s) => {
    const uses = /^\s*(?:- )?uses: *['"]?([^\s'"#]+)/m.exec(s)?.[1] ?? "";
    if (/^actions\/cache(?:\/restore)?@/.test(uses)) return [{ uses, prefix: /\n\s*restore-keys:/.test(s) }];
    // setup-node restores a package cache unless told not to
    // (package-manager-cache defaults to true); any setup action with a
    // `cache:` input restores one.
    const setupNode = /^actions\/setup-node@/.test(uses) && !/\n\s*package-manager-cache: false\b/.test(s);
    if (setupNode || (/^actions\/setup-[a-z]+@/.test(uses) && /\n\s*cache: *\S/.test(s))) return [{ uses, prefix: false }];
    const local = /^\.\/(?:\.base\/)?(\.github\/actions\/[^@]+)$/.exec(uses)?.[1];
    if (!local || seen.has(local)) return [];
    seen.add(local);
    const action = ["action.yml", "action.yaml"].map((f) => new URL(`${local.replace(/\/$/, "")}/${f}`, root)).find((u) => existsSync(u));
    return action ? restoresOf(stepsIn(readFileSync(action, "utf8")), seen) : [];
  });
function tokenJobRestores(text) {
  const head = text.slice(0, text.indexOf("\njobs:\n"));
  const workflowIdToken = /\npermissions:\n(?: {2}.*\n)*? {2}id-token: write/.test(`${head}\n`);
  const body = text.slice(text.indexOf("\njobs:\n") + 6);
  return body
    .split(/\n(?= {2}[A-Za-z0-9_-]+:\n)/)
    .map((block) => ({ id: /^ {2}([A-Za-z0-9_-]+):/m.exec(block)?.[1], block }))
    .filter(({ id, block }) => id && (workflowIdToken || /\n {6}id-token: write/.test(block) || /request-lane-token|create-github-app-token/.test(block)))
    .flatMap(({ id, block }) => restoresOf(stepsIn(block)).map((r) => ({ job: id, ...r })));
}

test("no job holding id-token or a lanes App token restores a cache by a bare prefix", () => {
  const found = readdirSync(workflowsDir)
    .filter((f) => /\.ya?ml$/.test(f))
    .flatMap((f) => tokenJobRestores(readFileSync(new URL(f, workflowsDir), "utf8")).map((r) => ({ file: f, ...r })))
    .filter((r) => r.prefix);
  assert.deepEqual(found, []);
});

test("no token-holding job in pr-merge.yml restores a cache", () => {
  assert.deepEqual(tokenJobRestores(merge), []);
  // The check sees a restore a token-holding job adds, directly or through a
  // local composite action, and ignores one in a job holding neither token.
  const withStep = (job, step) => merge.replace(new RegExp(`(\\n  ${job}:\\n[\\s\\S]*?\\n    steps:\\n)`), `$1${step}`);
  const exact = "      - name: Restore\n        uses: actions/cache/restore@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0\n        with:\n          key: k\n";
  const composite = "      - name: Count\n        uses: ./.base/.github/actions/check-wip-cap # zizmor: ignore[self-repository]\n";
  const setupNode = "      - name: Node\n        uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0\n        with:\n          node-version: 24\n";
  const setupPython = "      - name: Python\n        uses: actions/setup-python@v6\n        with:\n          cache: pip\n";
  for (const job of ["merge", "enable-auto-merge"]) {
    for (const added of [exact, setupNode, setupPython]) {
      assert.deepEqual(tokenJobRestores(withStep(job, added)).map((r) => [r.job, r.prefix]), [[job, false]], job);
    }
    assert.deepEqual(tokenJobRestores(withStep(job, composite)).map((r) => [r.job, r.prefix]), [[job, true]], job);
  }
  assert.deepEqual(tokenJobRestores(withStep("gate-check", exact)), []);
});
