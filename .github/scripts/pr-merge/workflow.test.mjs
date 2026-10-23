// pr-merge.yml's main-verification trigger. Expected values come from the
// owner decision of 2026-10-18 (every merge to main starts the full run,
// whoever merged), GitHub's concurrency rules (a group holds one running and
// one pending job, and a newer pending job replaces the older one unless
// `queue: max` is set), and the rule babysit_postmerge.py and
// post-merge-demotion-alert.yml share: a cancelled full run counts as red, so
// no pr-require-checks run may be cancelled by concurrency.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { VERIFY_BUDGET_MS, VERIFY_TIMEOUT_MS } from "./enable-auto-merge.mjs";

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
function runWait(conclusion, { dispatchFails = false } = {}) {
  const step = job("dispatch-full-run").split("\n      - name: Wait for the full run to finish\n")[1];
  const body = /\n {8}run: \|\n((?: {10}.*\n|\s*\n)+)/
    .exec(step)[1]
    .split("\n")
    .map((l) => l.slice(10))
    .join("\n");
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-wait-"));
  mkdirSync(join(dir, "bin"));
  writeFileSync(join(dir, "bin", "sleep"), "#!/bin/sh\nexit 0\n", {
    mode: 0o755,
  });
  writeFileSync(
    join(dir, "bin", "gh"),
    `#!/usr/bin/env bash
printf '%s\\n' "$*" >>"${dir}/log"
case "$*" in
  *-X\\ POST*) exit ${dispatchFails ? 1 : 0} ;;
  *) jq -r "\${@: -1}" <<<'{"status": "completed", "conclusion": "${conclusion}", "head_sha": "${HEAD}"}' ;;
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
    },
    encoding: "utf8",
  });
  const log = existsSync(join(dir, "log")) ? readFileSync(join(dir, "log"), "utf8") : "";
  rmSync(dir, { recursive: true, force: true });
  return {
    status: result.status,
    out: result.stdout + result.stderr,
    writes: log.split("\n").filter((l) => l.includes("-X POST")),
  };
}

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

// The native-merge plan's arm-merge item: the lanes App token arms a lane
// pull request as soon as the issue lane finishes, in pr-merge.yml, the one
// caller the token broker mints `merge` for; the merge job's gate never runs
// on that event.
test("the issue lane finishing wakes only the enable-auto-merge job", () => {
  assert.match(merge, /\n {2}workflow_run: # zizmor: ignore\[dangerous-triggers\]\n {4}workflows: \[work-resolve-issue\]\n {4}types: \[completed\]\n/);
  assert.match(job("merge"), /\n {6}&& github\.event_name != 'workflow_run'\n/);
  const arm = job("enable-auto-merge");
  const armIf = /\n {4}if: >-\n([\s\S]*?)\n {4}[a-z-]+:/.exec(arm)[1];
  assert.match(armIf, /github\.event_name != 'workflow_run' \|\| github\.event\.workflow_run\.conclusion != 'skipped'/);
  // A push to main is a merge landing, never a new lane pull request.
  assert.match(armIf, /github\.event_name != 'push'/);
  assert.match(arm, /\n {4}concurrency:\n {6}group: pr-merge-enable-auto-merge\n {6}queue: max\n/);
});

test("the last verifier read enable-auto-merge starts ends inside its step's timeout", () => {
  const arm = job("enable-auto-merge");
  const step = /- name: Arm and disarm auto-merge\n {8}if: .*\n {8}timeout-minutes: ([0-9]+)\n/.exec(arm);
  assert.ok(step, "the arm step names its timeout");
  // The room read, then the verdict budget and the last read it starts.
  assert.ok(VERIFY_TIMEOUT_MS + VERIFY_BUDGET_MS + VERIFY_TIMEOUT_MS < Number(step[1]) * 60_000);
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

// The lane's room (lane-room) needs the run's post-merge check and the rung
// cap as the merge job passes it: an unset cap holds the lane off, so a step
// that drops it would disarm every lane pull request.
test("enable-auto-merge reads the lane's room from this run's post-merge check and the rung cap", () => {
  const arm = job("enable-auto-merge");
  const check = /- name: Check earlier lane merges\n([\s\S]*?)(?=\n {6}- name: )/.exec(arm)?.[1];
  assert.ok(check, "a post-merge check step");
  assert.match(check, /^ {8}if: steps\.lane-token\.outputs\.token != '' && \(github\.event_name == 'schedule' \|\| github\.event_name == 'workflow_dispatch'\)\n/);
  assert.match(check, /\n {10}GH_TOKEN: \$\{\{ github\.token \}\}\n/);
  assert.match(check, /babysit_postmerge\.py \\\n {12}--repo "\$REPO" --agent-identity "\$identity" --lane-merges-only \\\n {12}<\/dev\/null >"\$RUNNER_TEMP\/post-merge\.json"/);
  const step = /- name: Arm and disarm auto-merge\n([\s\S]*?)(?=\n {6}- name: )/.exec(arm)[1];
  assert.match(step, /\n {10}POSTMERGE_RESULT: \$\{\{ runner\.temp \}\}\/post-merge\.json\n/);
  assert.match(step, /\n {10}RUNG_CAP: \$\{\{ vars\.CLAUDE_LANES_MERGE_RUNG_CAP \}\}\n/);
  assert.match(arm, /\n {6}pull-requests: read #/);
  assert.match(arm, /\n {6}issues: read #/);
  const names = [...arm.matchAll(/\n {6}- name: (.*)/g)].map((m) => m[1]);
  assert.ok(names.indexOf("Check earlier lane merges") < names.indexOf("Arm and disarm auto-merge"));
});

test("enable-auto-merge's step timeouts fit inside its job's", () => {
  const arm = job("enable-auto-merge");
  const total = Number(/\n {4}timeout-minutes: ([0-9]+)\n/.exec(arm)[1]);
  const steps = [...arm.matchAll(/\n {8}timeout-minutes: ([0-9]+)\n/g)].map((m) => Number(m[1]));
  assert.ok(steps.length >= 4, "the post-merge check, the cache restore, the arm step and the budget step name timeouts");
  assert.ok(steps.reduce((sum, minutes) => sum + minutes, 0) < total, `${steps.join(" + ")} inside ${total}`);
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
    ["contents: read", "actions: read", "pull-requests: read", "issues: read", "checks: read", "id-token: write"],
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
// no response at all, with gh's error text), a stub sleep that logs its seconds and a stub date. The
// expected waits come from the owner outage rule (at most three attempts;
// retry-after, else x-ratelimit-reset for a primary limit, else at least
// 60 s for a secondary one; otherwise a capped full-jitter backoff) and
// GitHub's documented order
// (https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#handle-rate-limit-errors-appropriately).
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
  writeFileSync(join(dir, "bin", "date"), `#!/bin/sh\necho ${NOW}\n`, { mode: 0o755 });
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

test("a rate-limited dispatch waits retry-after seconds, then sends again", () => {
  const r = runDispatch([limited({ "Retry-After": "7", "X-Ratelimit-Remaining": "0", "X-Ratelimit-Reset": `${NOW + 100}` }), ok(4243)]);
  assert.equal(r.status, 0, r.out);
  assert.equal(r.posts, 2);
  assert.deepEqual(r.slept, [7]);
  assert.match(r.output, /^run-id=4243$/m);
});

test("a primary limit with no retry-after waits until one second past the reset", () => {
  const r = runDispatch([limited({ "X-Ratelimit-Remaining": "0", "X-Ratelimit-Reset": `${NOW + 30}` }), ok(4244)]);
  assert.equal(r.status, 0, r.out);
  assert.deepEqual(r.slept, [31]);
  assert.match(r.output, /^run-id=4244$/m);
});

test("a secondary limit named only by its message waits 60 s", () => {
  const r = runDispatch(
    [limited({ "X-Ratelimit-Remaining": "812" }, "You have exceeded a secondary rate limit"), ok(4245)],
    { jobId: "post-merge-dispatch", event: "schedule" },
  );
  assert.equal(r.status, 0, r.out);
  assert.deepEqual(r.slept, [60]);
  assert.match(r.output, /^run-id=4245$/m);
});

test("three rate-limited answers end green with a warning naming the merge, and no run id", () => {
  const busy = limited({ "Retry-After": "5" });
  const r = runDispatch([busy, busy, busy, ok(1)]);
  assert.equal(r.status, 0, r.out);
  assert.equal(r.posts, 3);
  assert.deepEqual(r.slept, [5, 5]);
  assert.match(r.out, new RegExp(`::warning::no full CI run started for merge ${HEAD} after 3 attempt\\(s\\): HTTP 403`));
  assert.doesNotMatch(r.output, /run-id=/);
  assert.equal(r.record, "");
});

test("a scheduled run's warning names main at the run's start, not a merge", () => {
  const busy = limited({ "Retry-After": "5" });
  const r = runDispatch([busy, busy, busy], { jobId: "post-merge-dispatch", event: "schedule" });
  assert.match(r.out, new RegExp(`::warning::no full CI run started for main \\(this run started at ${HEAD}\\)`));
});

test("a wait past the job's cap is not taken", () => {
  const r = runDispatch([limited({ "X-Ratelimit-Remaining": "0", "X-Ratelimit-Reset": `${NOW + 1800}` }), ok(1)], { cap: "180" });
  assert.equal(r.status, 0, r.out);
  assert.equal(r.posts, 1);
  assert.deepEqual(r.slept, []);
  assert.match(r.out, /::warning::.*a 1801s wait does not fit the 180s this job allows/);
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

// post-merge-dispatch's 15 minutes hold its measured steps, the re-run
// step's read-back after this one, and at most 180 s of waits here (the yaml
// comment holds the numbers): a 181 s wait is not taken, two 60 s ones are.
test("post-merge-dispatch takes at most 180 s of waits", () => {
  const opts = { jobId: "post-merge-dispatch", event: "schedule" };
  const over = runDispatch([limited({ "Retry-After": "181" }), ok(1)], opts);
  assert.equal(over.posts, 1);
  assert.deepEqual(over.slept, []);
  assert.match(over.out, /a 181s wait does not fit the 180s this job allows/);
  const secondary = limited({ "Retry-After": "60" });
  const within = runDispatch([secondary, secondary, ok(4248)], opts);
  assert.deepEqual(within.slept, [60, 60]);
  assert.match(within.output, /^run-id=4248$/m);
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
